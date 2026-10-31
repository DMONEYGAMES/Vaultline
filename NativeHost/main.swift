import Foundation
import LocalAuthentication
import Security

private let serviceName = "com.vaultline.credentials.v2"
private let legacyServiceName = "com.vaultline.credentials"
private let activityServiceName = "com.vaultline.activity.v1"
private let maxMessageSize: UInt32 = 1_048_576
private let sessionLifetime: TimeInterval = 5 * 60

struct LegacyLoginRecord: Codable {
    var id: String
    var title: String
    var website: String
    var username: String
    var password: String
}

struct LoginRecord: Codable {
    var id: String
    var type: String = "login"
    var title: String
    var website: String
    var username: String
    var password: String
    var category: String
    var favorite: Bool
    var createdAt: Double
    var updatedAt: Double
    var tags: [String]? = []
    var passwordHistory: [String]? = []
    var lastUsedAt: Double? = nil

    var host: String {
        normalizedHost(from: website) ?? ""
    }

    func publicSummary() -> [String: Any] {
        return [
            "id": id, "type": "login", "title": title, "website": website,
            "host": host, "username": username, "category": category,
            "favorite": favorite, "createdAt": createdAt, "updatedAt": updatedAt,
            "tags": tags ?? [], "lastUsedAt": lastUsedAt ?? 0, "passwordHistoryCount": passwordHistory?.count ?? 0
        ]
    }
}


struct CardRecord: Codable {
    var id: String
    var type: String = "card"
    var title: String
    var cardholder: String
    var number: String
    var expiryMonth: Int
    var expiryYear: Int
    var billingZip: String
    var notes: String
    var favorite: Bool
    var createdAt: Double
    var updatedAt: Double
    var tags: [String]? = []

    var last4: String { String(number.filter(\.isNumber).suffix(4)) }

    func publicSummary() -> [String: Any] {
        ["id": id, "type": "card", "title": title, "cardholder": cardholder,
         "last4": last4, "expiryMonth": expiryMonth, "expiryYear": expiryYear,
         "billingZip": billingZip, "notesPreview": String(notes.prefix(80)), "favorite": favorite,
         "tags": tags ?? [], "createdAt": createdAt, "updatedAt": updatedAt]
    }
}

struct SecureNoteRecord: Codable {
    var id: String
    var type: String = "note"
    var title: String
    var content: String
    var category: String
    var tags: [String]
    var favorite: Bool
    var createdAt: Double
    var updatedAt: Double
    func publicSummary() -> [String: Any] { ["id": id, "type": "note", "title": title, "category": category, "tags": tags, "favorite": favorite, "createdAt": createdAt, "updatedAt": updatedAt, "preview": String(content.prefix(90))] }
}

struct IdentityRecord: Codable {
    var id: String
    var type: String = "identity"
    var title: String
    var fullName: String
    var email: String
    var phone: String
    var company: String
    var addressLine1: String
    var addressLine2: String
    var city: String
    var region: String
    var postalCode: String
    var country: String
    var notes: String
    var tags: [String]
    var favorite: Bool
    var createdAt: Double
    var updatedAt: Double
    func publicSummary() -> [String: Any] { ["id": id, "type": "identity", "title": title, "fullName": fullName, "email": email, "company": company, "country": country, "tags": tags, "favorite": favorite, "createdAt": createdAt, "updatedAt": updatedAt] }
}

struct ActivityEvent: Codable {
    var id: String
    var date: Double
    var action: String
    var detail: String
}

func luhnIsValid(_ digits: String) -> Bool {
    let numbers = digits.compactMap { $0.wholeNumberValue }
    guard (12...19).contains(numbers.count) else { return false }
    let sum = numbers.reversed().enumerated().reduce(0) { total, pair in
        let (index, digit) = pair
        if index % 2 == 1 { let doubled = digit * 2; return total + (doubled > 9 ? doubled - 9 : doubled) }
        return total + digit
    }
    return sum % 10 == 0
}

func readExactly(_ count: Int) -> Data? {
    var data = Data(count: count)
    let ok = data.withUnsafeMutableBytes { rawBuffer -> Bool in
        guard let base = rawBuffer.baseAddress else { return false }
        var offset = 0
        while offset < count {
            let readCount = fread(base.advanced(by: offset), 1, count - offset, stdin)
            if readCount == 0 { return false }
            offset += readCount
        }
        return true
    }
    return ok ? data : nil
}

func readMessage() -> [String: Any]? {
    guard let header = readExactly(4) else { return nil }
    let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    guard length > 0, length <= maxMessageSize,
          let data = readExactly(Int(length)),
          let object = try? JSONSerialization.jsonObject(with: data),
          let message = object as? [String: Any] else { return nil }
    return message
}

func send(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]) else { return }
    var length = UInt32(data.count).littleEndian
    withUnsafeBytes(of: &length) { bytes in
        if let base = bytes.baseAddress { _ = fwrite(base, 1, 4, stdout) }
    }
    data.withUnsafeBytes { bytes in
        if let base = bytes.baseAddress { _ = fwrite(base, 1, data.count, stdout) }
    }
    fflush(stdout)
}

func normalizedHost(from value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains("\n"), !trimmed.contains("\r") else { return nil }
    // Extension requests use a bare hostname (for example, accounts.google.com),
    // while saved records may supply a full HTTP(S) URL. Accept both forms.
    let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let url = URL(string: candidate),
          let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
          let host = url.host?.lowercased(), !host.isEmpty,
          url.user == nil, url.password == nil else { return nil }
    let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    guard !normalized.isEmpty else { return nil }
    return normalized
}

final class VaultSession {
    private var authenticatedUntil = Date.distantPast
    private var context: LAContext?

    func lock() {
        context?.invalidate()
        context = nil
        authenticatedUntil = .distantPast
    }

    func ensureAuthenticated(reason: String) -> Bool {
        if Date() < authenticatedUntil, context != nil { return true }
        lock()
        let nextContext = LAContext()
        nextContext.localizedCancelTitle = "Cancel"
        var policyError: NSError?
        guard nextContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        var succeeded = false
        nextContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            succeeded = success
            semaphore.signal()
        }
        semaphore.wait()
        guard succeeded else { nextContext.invalidate(); return false }
        context = nextContext
        authenticatedUntil = Date().addingTimeInterval(sessionLifetime)
        return true
    }
}

func keychainAddOrUpdate(record: LoginRecord) -> OSStatus {
    guard let data = try? JSONEncoder().encode(record) else { return errSecParam }
    let key: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: record.id
    ]
    let update: [String: Any] = [
        kSecValueData as String: data,
        kSecAttrLabel as String: record.title,
        kSecAttrComment as String: record.host
    ]
    let updateStatus = SecItemUpdate(key as CFDictionary, update as CFDictionary)
    if updateStatus == errSecSuccess { return errSecSuccess }
    if updateStatus != errSecItemNotFound { return updateStatus }
    var add = key
    update.forEach { add[$0.key] = $0.value }
    add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    return SecItemAdd(add as CFDictionary, nil)
}

func keychainCopyData(service: String, account: String) -> (Data?, OSStatus) {
    // Apple Keychain does not allow kSecReturnData with kSecMatchLimitAll
    // for generic-password items. Fetch the data for one account at a time.
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else { return (nil, status) }
    guard let data = result as? Data else { return (nil, errSecDecode) }
    return (data, errSecSuccess)
}

func keychainGet(id: String) -> LoginRecord? {
    let (data, status) = keychainCopyData(service: serviceName, account: id)
    guard status == errSecSuccess, let data else { return nil }
    return try? JSONDecoder().decode(LoginRecord.self, from: data)
}

func keychainAddOrUpdate(card: CardRecord) -> OSStatus {
    guard let data = try? JSONEncoder().encode(card) else { return errSecParam }
    let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                              kSecAttrService as String: serviceName,
                              kSecAttrAccount as String: card.id]
    let update: [String: Any] = [kSecValueData as String: data,
                                 kSecAttrLabel as String: card.title,
                                 kSecAttrComment as String: "card •••• \(card.last4)"]
    let updateStatus = SecItemUpdate(key as CFDictionary, update as CFDictionary)
    if updateStatus == errSecSuccess { return errSecSuccess }
    if updateStatus != errSecItemNotFound { return updateStatus }
    var add = key
    update.forEach { add[$0.key] = $0.value }
    add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    return SecItemAdd(add as CFDictionary, nil)
}

func keychainGetCard(id: String) -> CardRecord? {
    let (data, status) = keychainCopyData(service: serviceName, account: id)
    guard status == errSecSuccess, let data else { return nil }
    return try? JSONDecoder().decode(CardRecord.self, from: data)
}

func keychainGetNote(id: String) -> SecureNoteRecord? {
    let (data, status) = keychainCopyData(service: serviceName, account: id)
    guard status == errSecSuccess, let data else { return nil }
    return try? JSONDecoder().decode(SecureNoteRecord.self, from: data)
}
func keychainGetIdentity(id: String) -> IdentityRecord? {
    let (data, status) = keychainCopyData(service: serviceName, account: id)
    guard status == errSecSuccess, let data else { return nil }
    return try? JSONDecoder().decode(IdentityRecord.self, from: data)
}
func keychainAddOrUpdate<T: Encodable>(record: T, id: String, title: String, comment: String) -> OSStatus {
    guard let data = try? JSONEncoder().encode(record) else { return errSecParam }
    let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName, kSecAttrAccount as String: id]
    let update: [String: Any] = [kSecValueData as String: data, kSecAttrLabel as String: title, kSecAttrComment as String: comment]
    let updateStatus = SecItemUpdate(key as CFDictionary, update as CFDictionary)
    if updateStatus == errSecSuccess { return errSecSuccess }
    if updateStatus != errSecItemNotFound { return updateStatus }
    var add = key; update.forEach { add[$0.key] = $0.value }; add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    return SecItemAdd(add as CFDictionary, nil)
}
func listTypedRecords<T: Decodable>(_ type: T.Type, expectedType: String) -> ([T], OSStatus) {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName, kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return ([], errSecSuccess) }
    guard status == errSecSuccess, let items = result as? [[String: Any]] else { return ([], status == errSecSuccess ? errSecDecode : status) }
    var records: [T] = []
    for item in items {
        guard let account = item[kSecAttrAccount as String] as? String else { continue }
        let (data, readStatus) = keychainCopyData(service: serviceName, account: account)
        guard readStatus == errSecSuccess, let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["type"] as? String == expectedType,
              let record = try? JSONDecoder().decode(T.self, from: data) else { continue }
        records.append(record)
    }
    return (records, errSecSuccess)
}
func makeNote(_ raw: [String: Any]) -> SecureNoteRecord? {
    guard let id = raw["id"] as? String, UUID(uuidString: id) != nil, let title = raw["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 120, let content = raw["content"] as? String, content.count <= 20000 else { return nil }
    let now = Date().timeIntervalSince1970 * 1000
    let tags = Array((raw["tags"] as? [String] ?? []).map { String($0.prefix(32)) }.prefix(12))
    return SecureNoteRecord(id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), content: content, category: String((raw["category"] as? String ?? "Personal").prefix(40)), tags: tags, favorite: raw["favorite"] as? Bool ?? false, createdAt: raw["createdAt"] as? Double ?? now, updatedAt: now)
}
func makeIdentity(_ raw: [String: Any]) -> IdentityRecord? {
    guard let id = raw["id"] as? String, UUID(uuidString: id) != nil, let title = raw["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 120 else { return nil }
    func field(_ key: String, _ max: Int = 240) -> String { String((raw[key] as? String ?? "").prefix(max)) }
    let now = Date().timeIntervalSince1970 * 1000
    let tags = Array((raw["tags"] as? [String] ?? []).map { String($0.prefix(32)) }.prefix(12))
    return IdentityRecord(id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), fullName: field("fullName"), email: field("email"), phone: field("phone"), company: field("company"), addressLine1: field("addressLine1"), addressLine2: field("addressLine2"), city: field("city"), region: field("region"), postalCode: field("postalCode"), country: field("country"), notes: field("notes", 2000), tags: tags, favorite: raw["favorite"] as? Bool ?? false, createdAt: raw["createdAt"] as? Double ?? now, updatedAt: now)
}
func activityLog(_ action: String, _ detail: String) {
    let account = "events"
    var events: [ActivityEvent] = []
    let (data, readStatus) = keychainCopyData(service: activityServiceName, account: account)
    if readStatus == errSecSuccess, let data, let old = try? JSONDecoder().decode([ActivityEvent].self, from: data) { events = old }
    events.insert(ActivityEvent(id: UUID().uuidString, date: Date().timeIntervalSince1970 * 1000, action: action, detail: String(detail.prefix(160))), at: 0)
    events = Array(events.prefix(200))
    guard let encoded = try? JSONEncoder().encode(events) else { return }
    let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: activityServiceName, kSecAttrAccount as String: account]
    let update = [kSecValueData as String: encoded, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as [String: Any]
    let code = SecItemUpdate(key as CFDictionary, update as CFDictionary)
    if code == errSecItemNotFound { _ = SecItemAdd(key.merging(update) { _, new in new } as CFDictionary, nil) }
}
func readActivity() -> [ActivityEvent] {
    let (data, status) = keychainCopyData(service: activityServiceName, account: "events")
    guard status == errSecSuccess, let data else { return [] }
    return (try? JSONDecoder().decode([ActivityEvent].self, from: data)) ?? []
}

func keychainListCards() -> ([CardRecord], OSStatus) {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: serviceName,
                                kSecReturnAttributes as String: true,
                                kSecMatchLimit as String: kSecMatchLimitAll]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return ([], errSecSuccess) }
    guard status == errSecSuccess else { return ([], status) }
    guard let items = result as? [[String: Any]] else { return ([], errSecDecode) }
    var cards: [CardRecord] = []
    for item in items {
        guard let account = item[kSecAttrAccount as String] as? String else { continue }
        let (data, readStatus) = keychainCopyData(service: serviceName, account: account)
        guard readStatus == errSecSuccess, let data,
              let card = try? JSONDecoder().decode(CardRecord.self, from: data), card.type == "card" else { continue }
        cards.append(card)
    }
    return (cards.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }, errSecSuccess)
}

func makeCard(_ raw: [String: Any]) -> CardRecord? {
    guard let id = raw["id"] as? String, UUID(uuidString: id) != nil,
          let title = raw["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 120,
          let cardholder = raw["cardholder"] as? String, cardholder.count <= 120,
          let rawNumber = raw["number"] as? String, rawNumber.count <= 40,
          let month = raw["expiryMonth"] as? Int, (1...12).contains(month),
          let year = raw["expiryYear"] as? Int, (2020...2099).contains(year),
          let billingZip = raw["billingZip"] as? String, billingZip.count <= 24,
          let notes = raw["notes"] as? String, notes.count <= 2000 else { return nil }
    let digits = rawNumber.filter(\.isNumber)
    guard luhnIsValid(digits) else { return nil }
    let now = Date().timeIntervalSince1970 * 1000
    return CardRecord(id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                      cardholder: cardholder, number: digits, expiryMonth: month, expiryYear: year,
                      billingZip: billingZip, notes: notes, favorite: raw["favorite"] as? Bool ?? false,
                      createdAt: raw["createdAt"] as? Double ?? now, updatedAt: now,
                      tags: Array((raw["tags"] as? [String] ?? []).map { String($0.prefix(32)) }.prefix(12)))
}

// Delete exactly one login item. The service + account pair is the item's
// composite key; never issue a broad delete query for the whole service.
func keychainDelete(id: String) -> OSStatus {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: id
    ]
    return SecItemDelete(query as CFDictionary)
}

func keychainList() -> ([LoginRecord], OSStatus) {
    // First enumerate attributes only. Each matching password is then read
    // individually through keychainCopyData(), as required by Apple's API.
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecReturnAttributes as String: true,
        kSecMatchLimit as String: kSecMatchLimitAll
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return ([], errSecSuccess) }
    guard status == errSecSuccess else { return ([], status) }
    guard let items = result as? [[String: Any]] else { return ([], errSecDecode) }

    var records: [LoginRecord] = []
    for item in items {
        guard let account = item[kSecAttrAccount as String] as? String else { continue }
        let (data, dataStatus) = keychainCopyData(service: serviceName, account: account)
        guard dataStatus == errSecSuccess, let data,
              let record = try? JSONDecoder().decode(LoginRecord.self, from: data),
              record.type == "login", !record.host.isEmpty else { continue }
        records.append(record)
    }
    return (records.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }, errSecSuccess)
}

func migrateLegacyRecords() -> Int {
    // Enumerate legacy item attributes only, then fetch each blob individually.
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: legacyServiceName,
        kSecReturnAttributes as String: true,
        kSecMatchLimit as String: kSecMatchLimitAll
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let items = result as? [[String: Any]] else { return 0 }
    var migrated = 0
    for item in items {
        guard let legacyAccount = item[kSecAttrAccount as String] as? String else { continue }
        let (data, readStatus) = keychainCopyData(service: legacyServiceName, account: legacyAccount)
        guard readStatus == errSecSuccess, let data,
              let old = try? JSONDecoder().decode(LegacyLoginRecord.self, from: data),
              let host = normalizedHost(from: old.website),
              !old.password.isEmpty else { continue }
        let now = Date().timeIntervalSince1970 * 1000
        let migratedWebsite = old.website.contains("://") ? old.website : "https://\(host)"
        let record = LoginRecord(id: old.id, title: old.title, website: migratedWebsite,
                                  username: old.username, password: old.password,
                                  category: "Personal", favorite: false,
                                  createdAt: now, updatedAt: now)
        if keychainAddOrUpdate(record: record) == errSecSuccess {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyServiceName,
                kSecAttrAccount as String: legacyAccount
            ]
            SecItemDelete(deleteQuery as CFDictionary)
            migrated += 1
        }
    }
    return migrated
}

func makeRecord(_ raw: [String: Any]) -> LoginRecord? {
    guard let id = raw["id"] as? String, UUID(uuidString: id) != nil, id.count <= 120,
          let title = raw["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 120,
          let website = raw["website"] as? String, website.count <= 500,
          normalizedHost(from: website) != nil,
          let username = raw["username"] as? String, username.count <= 500,
          let password = raw["password"] as? String, !password.isEmpty, password.count <= 2000 else { return nil }
    let categories = ["Personal", "Work", "Banking", "Email", "Social", "Shopping", "Gaming", "Travel", "Other"]
    let categoryRaw = raw["category"] as? String ?? "Personal"
    let category = categories.contains(categoryRaw) ? categoryRaw : "Personal"
    let now = Date().timeIntervalSince1970 * 1000
    let old = keychainGet(id: id)
    var history = Array((raw["passwordHistory"] as? [String] ?? old?.passwordHistory ?? []).filter { !$0.isEmpty && $0.count <= 2000 }.prefix(5))
    if let old, old.password != password { history.insert(old.password, at: 0); history = Array(history.prefix(5)) }
    let tags = Array((raw["tags"] as? [String] ?? old?.tags ?? []).map { String($0.prefix(32)) }.prefix(12))
    return LoginRecord(
        id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), website: website,
        username: username, password: password, category: category,
        favorite: raw["favorite"] as? Bool ?? false,
        createdAt: raw["createdAt"] as? Double ?? now,
        updatedAt: now, tags: tags, passwordHistory: history, lastUsedAt: raw["lastUsedAt"] as? Double ?? old?.lastUsedAt
    )
}

let session = VaultSession()
while let message = readMessage() {
    let requestID = message["requestId"] ?? NSNull()
    let command = message["command"] as? String ?? ""
    let payload = message["payload"] as? [String: Any] ?? [:]
    func reply(_ values: [String: Any]) {
        var response = values
        response["requestId"] = requestID
        send(response)
    }

    if command == "ping" {
        reply(["ok": true, "version": "1.0.0", "store": "macOS-Keychain"])
        continue
    }
    if command == "lock" {
        session.lock()
        reply(["ok": true, "locked": true])
        continue
    }

    let reason: String
    switch command {
    case "listLogins": reason = "Unlock Vaultline to view your saved login list"
    case "saveLogin": reason = "Approve saving a login in Vaultline"
    case "getLogin": reason = "Approve using a saved Vaultline login"
    case "deleteLogin": reason = "Approve deleting a saved Vaultline login"
    case "listCards": reason = "Unlock Vaultline to view saved payment cards"
    case "saveCard": reason = "Approve saving a payment card in Vaultline"
    case "getCard": reason = "Approve viewing a saved payment card"
    case "deleteCard": reason = "Approve deleting a saved payment card"
    case "listNotes": reason = "Unlock Vaultline to view secure notes"
    case "saveNote": reason = "Approve saving a secure note"
    case "getNote": reason = "Approve viewing a secure note"
    case "deleteNote": reason = "Approve deleting a secure note"
    case "listIdentities": reason = "Unlock Vaultline to view saved identities"
    case "saveIdentity": reason = "Approve saving a personal identity"
    case "getIdentity": reason = "Approve viewing a personal identity"
    case "deleteIdentity": reason = "Approve deleting a personal identity"
    case "listActivity": reason = "Unlock Vaultline to view vault activity"
    case "securityAudit": reason = "Approve a local password security check"
    case "exportVault": reason = "Authenticate before exporting your encrypted vault backup"
    case "importVault": reason = "Authenticate before restoring a vault backup"
    default:
        reply(["ok": false, "error": "unsupported-command"])
        continue
    }
    guard session.ensureAuthenticated(reason: reason) else {
        reply(["ok": false, "error": "authentication-required-or-cancelled"])
        continue
    }

    switch command {
    case "listLogins":
        let migrated = migrateLegacyRecords()
        let (records, status) = keychainList()
        guard status == errSecSuccess else {
            reply(["ok": false, "error": "keychain-list-failed", "status": Int(status)])
            continue
        }
        let summaries = records.map { $0.publicSummary() }
        reply(["ok": true, "records": summaries, "count": summaries.count, "migrated": migrated])

    case "saveLogin":
        guard let raw = payload["record"] as? [String: Any], let record = makeRecord(raw) else {
            reply(["ok": false, "error": "invalid-login-record"])
            continue
        }
        let status = keychainAddOrUpdate(record: record)
        if status == errSecSuccess {
            activityLog("Saved login", "\(record.title) · \(record.host)")
            reply(["ok": true, "record": record.publicSummary(), "message": "saved"])
        } else {
            reply(["ok": false, "error": "keychain-save-failed", "status": Int(status)])
        }

    case "getLogin":
        guard let id = payload["id"] as? String, UUID(uuidString: id) != nil,
              let requestedHost = payload["host"] as? String,
              let host = normalizedHost(from: requestedHost), let record = keychainGet(id: id) else {
            reply(["ok": false, "error": "login-not-found"])
            continue
        }
        guard record.host == host else {
            reply(["ok": false, "error": "website-mismatch"])
            continue
        }
        var used = record; used.lastUsedAt = Date().timeIntervalSince1970 * 1000; _ = keychainAddOrUpdate(record: used)
        activityLog("Used login", "\(record.title) · \(record.host)")
        reply(["ok": true, "id": record.id, "host": record.host, "username": record.username, "password": record.password, "passwordHistory": record.passwordHistory ?? [], "title": record.title, "website": record.website])

    case "listCards":
        let (cards, status) = keychainListCards()
        guard status == errSecSuccess else {
            reply(["ok": false, "error": "keychain-list-failed", "status": Int(status)])
            continue
        }
        reply(["ok": true, "records": cards.map { $0.publicSummary() }, "count": cards.count])

    case "saveCard":
        guard let raw = payload["record"] as? [String: Any], let card = makeCard(raw) else {
            reply(["ok": false, "error": "invalid-card-record"])
            continue
        }
        let status = keychainAddOrUpdate(card: card)
        if status == errSecSuccess {
            activityLog("Saved payment card", card.title)
            reply(["ok": true, "record": card.publicSummary(), "message": "saved"])
        } else {
            reply(["ok": false, "error": "keychain-save-failed", "status": Int(status)])
        }

    case "getCard":
        guard let id = payload["id"] as? String, UUID(uuidString: id) != nil,
              let card = keychainGetCard(id: id) else {
            reply(["ok": false, "error": "card-not-found"])
            continue
        }
        reply(["ok": true, "id": card.id, "title": card.title, "cardholder": card.cardholder,
               "number": card.number, "expiryMonth": card.expiryMonth, "expiryYear": card.expiryYear,
               "billingZip": card.billingZip, "notes": card.notes])

    case "deleteLogin":
        guard let id = payload["id"] as? String, UUID(uuidString: id) != nil,
              keychainGet(id: id) != nil else {
            reply(["ok": false, "error": "login-not-found"])
            continue
        }
        let status = keychainDelete(id: id)
        if status == errSecSuccess || status == errSecItemNotFound {
            activityLog("Deleted login", "Saved login removed")
            reply(["ok": true, "deleted": true])
        } else {
            reply(["ok": false, "error": "keychain-delete-failed", "status": Int(status)])
        }

    case "deleteCard":
        guard let id = payload["id"] as? String, UUID(uuidString: id) != nil, keychainGetCard(id: id) != nil else { reply(["ok": false, "error": "card-not-found"]); continue }
        let status = keychainDelete(id: id)
        if status == errSecSuccess || status == errSecItemNotFound { activityLog("Deleted card", "Payment card removed"); reply(["ok": true, "deleted": true]) }
        else { reply(["ok": false, "error": "keychain-delete-failed", "status": Int(status)]) }

    case "listNotes":
        let (records, status) = listTypedRecords(SecureNoteRecord.self, expectedType: "note")
        guard status == errSecSuccess else { reply(["ok": false, "error": "keychain-list-failed", "status": Int(status)]); continue }
        reply(["ok": true, "records": records.map { $0.publicSummary() }, "count": records.count])

    case "saveNote":
        guard let raw = payload["record"] as? [String: Any], let record = makeNote(raw) else { reply(["ok": false, "error": "invalid-note-record"]); continue }
        let status = keychainAddOrUpdate(record: record, id: record.id, title: record.title, comment: "Vaultline secure note")
        if status == errSecSuccess { activityLog("Saved secure note", record.title); reply(["ok": true, "record": record.publicSummary()]) } else { reply(["ok": false, "error": "keychain-save-failed", "status": Int(status)]) }

    case "getNote":
        guard let id = payload["id"] as? String, UUID(uuidString: id) != nil, let record = keychainGetNote(id: id) else { reply(["ok": false, "error": "note-not-found"]); continue }
        activityLog("Viewed secure note", record.title)
        reply(["ok": true, "id": record.id, "title": record.title, "content": record.content, "category": record.category, "tags": record.tags, "favorite": record.favorite])

    case "deleteNote":
        guard let id = payload["id"] as? String, UUID(uuidString: id) != nil, keychainGetNote(id: id) != nil else { reply(["ok": false, "error": "note-not-found"]); continue }
        let status = keychainDelete(id: id)
        if status == errSecSuccess || status == errSecItemNotFound { activityLog("Deleted secure note", "Secure note removed"); reply(["ok": true, "deleted": true]) } else { reply(["ok": false, "error": "keychain-delete-failed", "status": Int(status)]) }

    case "listIdentities":
        let (records, status) = listTypedRecords(IdentityRecord.self, expectedType: "identity")
        guard status == errSecSuccess else { reply(["ok": false, "error": "keychain-list-failed", "status": Int(status)]); continue }
        reply(["ok": true, "records": records.map { $0.publicSummary() }, "count": records.count])

    case "saveIdentity":
        guard let raw = payload["record"] as? [String: Any], let record = makeIdentity(raw) else { reply(["ok": false, "error": "invalid-identity-record"]); continue }
        let status = keychainAddOrUpdate(record: record, id: record.id, title: record.title, comment: "Vaultline identity")
        if status == errSecSuccess { activityLog("Saved identity", record.title); reply(["ok": true, "record": record.publicSummary()]) } else { reply(["ok": false, "error": "keychain-save-failed", "status": Int(status)]) }

    case "getIdentity":
        guard let id = payload["id"] as? String, UUID(uuidString: id) != nil, let record = keychainGetIdentity(id: id) else { reply(["ok": false, "error": "identity-not-found"]); continue }
        activityLog("Viewed identity", record.title)
        reply(["ok": true, "id": record.id, "title": record.title, "fullName": record.fullName, "email": record.email, "phone": record.phone, "company": record.company, "addressLine1": record.addressLine1, "addressLine2": record.addressLine2, "city": record.city, "region": record.region, "postalCode": record.postalCode, "country": record.country, "notes": record.notes, "tags": record.tags, "favorite": record.favorite])

    case "deleteIdentity":
        guard let id = payload["id"] as? String, UUID(uuidString: id) != nil, keychainGetIdentity(id: id) != nil else { reply(["ok": false, "error": "identity-not-found"]); continue }
        let status = keychainDelete(id: id)
        if status == errSecSuccess || status == errSecItemNotFound { activityLog("Deleted identity", "Identity removed"); reply(["ok": true, "deleted": true]) } else { reply(["ok": false, "error": "keychain-delete-failed", "status": Int(status)]) }

    case "listActivity":
        let events = readActivity().map { ["id": $0.id, "date": $0.date, "action": $0.action, "detail": $0.detail] as [String: Any] }
        reply(["ok": true, "events": events])

    case "securityAudit":
        let (records, status) = keychainList()
        guard status == errSecSuccess else { reply(["ok": false, "error": "keychain-list-failed", "status": Int(status)]); continue }
        let weak = records.filter { $0.password.count < 12 }.count
        let grouped = Dictionary(grouping: records, by: { $0.password })
        let reused = grouped.values.filter { $0.count > 1 }.reduce(0) { $0 + $1.count }
        let insecure = records.filter { URL(string: $0.website)?.scheme?.lowercased() == "http" && !["localhost", "127.0.0.1"].contains($0.host) }.count
        reply(["ok": true, "total": records.count, "weak": weak, "reused": reused, "insecureSites": insecure, "favorites": records.filter { $0.favorite }.count])

    case "exportVault":
        let (logins, loginStatus) = keychainList(); let (cards, cardStatus) = keychainListCards()
        let (notes, noteStatus) = listTypedRecords(SecureNoteRecord.self, expectedType: "note")
        let (identities, identityStatus) = listTypedRecords(IdentityRecord.self, expectedType: "identity")
        guard [loginStatus, cardStatus, noteStatus, identityStatus].allSatisfy({ $0 == errSecSuccess }) else { reply(["ok": false, "error": "keychain-export-failed"]); continue }
        func jsonObject<T: Encodable>(_ value: T) -> [String: Any] { guard let data = try? JSONEncoder().encode(value), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }; return object }
        reply(["ok": true, "format": "vaultline-backup-v1", "logins": logins.map { jsonObject($0) }, "cards": cards.map { jsonObject($0) }, "notes": notes.map { jsonObject($0) }, "identities": identities.map { jsonObject($0) }])

    case "importVault":
        let groups: [(String, String)] = [("logins", "login"), ("cards", "card"), ("notes", "note"), ("identities", "identity")]
        var imported = 0
        for (key, kind) in groups {
            guard let rows = payload[key] as? [[String: Any]] else { continue }
            for raw in rows {
                var status: OSStatus = errSecParam
                if kind == "login", let record = makeRecord(raw) { status = keychainAddOrUpdate(record: record) }
                else if kind == "card", let record = makeCard(raw) { status = keychainAddOrUpdate(card: record) }
                else if kind == "note", let record = makeNote(raw) { status = keychainAddOrUpdate(record: record, id: record.id, title: record.title, comment: "Vaultline secure note") }
                else if kind == "identity", let record = makeIdentity(raw) { status = keychainAddOrUpdate(record: record, id: record.id, title: record.title, comment: "Vaultline identity") }
                if status == errSecSuccess { imported += 1 }
            }
        }
        activityLog("Imported encrypted backup", "Imported or updated \(imported) records")
        reply(["ok": true, "imported": imported])

    default:
        reply(["ok": false, "error": "unsupported-command"])
    }
}
session.lock()
