import SwiftUI
import LocalAuthentication
import Security
import AppKit

private let serviceName = "com.vaultline.credentials.v2"

struct LoginRecord: Codable, Identifiable, Equatable {
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
    var host: String { URL(string: website)?.host?.lowercased() ?? website.lowercased() }
}

struct CardRecord: Codable, Identifiable, Equatable {
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
    var last4: String { String(number.suffix(4)) }
    var maskedNumber: String { "••••  ••••  ••••  \(last4)" }
}

struct SecureNoteRecord: Codable, Identifiable, Equatable {
    var id: String; var type: String = "note"; var title: String; var content: String; var category: String
    var tags: [String]; var favorite: Bool; var createdAt: Double; var updatedAt: Double
}
struct IdentityRecord: Codable, Identifiable, Equatable {
    var id: String; var type: String = "identity"; var title: String; var fullName: String; var email: String; var phone: String
    var company: String; var addressLine1: String; var addressLine2: String; var city: String; var region: String
    var postalCode: String; var country: String; var notes: String; var tags: [String]; var favorite: Bool
    var createdAt: Double; var updatedAt: Double
}

struct VaultActivity: Codable, Identifiable { var id: String; var date: Double; var action: String; var detail: String }

@MainActor final class VaultModel: ObservableObject {
    @Published var logins: [LoginRecord] = []
    @Published var cards: [CardRecord] = []
    @Published var notes: [SecureNoteRecord] = []
    @Published var identities: [IdentityRecord] = []
    @Published var activities: [VaultActivity] = []
    @Published var status = "Your vault is stored in this Mac's Keychain."
    @Published var unlocked = false

    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            status = "Mac authentication unavailable: \(error?.localizedDescription ?? "unknown reason")"
            completion(false); return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authError in
            DispatchQueue.main.async {
                if !success { self.status = authError?.localizedDescription ?? "Authentication cancelled." }
                completion(success)
            }
        }
    }

    func unlock() {
        authenticate(reason: "Unlock Vaultline to manage passwords and payment cards") { success in
            self.unlocked = success
            if success { self.loadRecords() }
        }
    }

    func loadRecords() {
        guard unlocked else { status = "Unlock Vaultline first."; return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: serviceName,
                                    kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &result)
        if code == errSecItemNotFound { logins = []; cards = []; notes = []; identities = []; status = "Your vault is empty."; return }
        guard code == errSecSuccess, let items = result as? [[String: Any]] else {
            status = "Could not read Keychain items (\(code))."; return
        }
        var loadedLogins: [LoginRecord] = []
        var loadedCards: [CardRecord] = []
        var loadedNotes: [SecureNoteRecord] = []
        var loadedIdentities: [IdentityRecord] = []
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { continue }
            let read: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecAttrService as String: serviceName,
                                       kSecAttrAccount as String: account,
                                       kSecReturnData as String: true,
                                       kSecMatchLimit as String: kSecMatchLimitOne]
            var blob: CFTypeRef?
            guard SecItemCopyMatching(read as CFDictionary, &blob) == errSecSuccess,
                  let data = blob as? Data,
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = raw["type"] as? String else { continue }
            if type == "login", let value = try? JSONDecoder().decode(LoginRecord.self, from: data) {
                loadedLogins.append(value)
            } else if type == "card", let value = try? JSONDecoder().decode(CardRecord.self, from: data) {
                loadedCards.append(value)
            } else if type == "note", let value = try? JSONDecoder().decode(SecureNoteRecord.self, from: data) {
                loadedNotes.append(value)
            } else if type == "identity", let value = try? JSONDecoder().decode(IdentityRecord.self, from: data) {
                loadedIdentities.append(value)
            }
        }
        logins = loadedLogins.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        cards = loadedCards.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        notes = loadedNotes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        identities = loadedIdentities.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        activities = loadActivityEvents()
        status = "Connected · \(logins.count) logins · \(cards.count) cards · \(notes.count) notes · \(identities.count) identities"
    }

    private func store<T: Encodable>(_ record: T, id: String, title: String, comment: String) -> Bool {
        guard unlocked, let data = try? JSONEncoder().encode(record) else { status = "Unlock the vault before saving."; return false }
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: serviceName,
                                  kSecAttrAccount as String: id]
        let updates: [String: Any] = [kSecValueData as String: data,
                                      kSecAttrLabel as String: title,
                                      kSecAttrComment as String: comment]
        let updateCode = SecItemUpdate(key as CFDictionary, updates as CFDictionary)
        if updateCode == errSecSuccess { return true }
        guard updateCode == errSecItemNotFound else { status = "Keychain update failed (\(updateCode))."; return false }
        var add = key
        updates.forEach { add[$0.key] = $0.value }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let code = SecItemAdd(add as CFDictionary, nil)
        guard code == errSecSuccess else { status = "Keychain save failed (\(code))."; return false }
        return true
    }

    private func logActivity(_ action: String, _ detail: String) {
        let service = "com.vaultline.activity.v1", account = "events"
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var existing: CFTypeRef?; var events: [VaultActivity] = []
        if SecItemCopyMatching(query as CFDictionary,&existing) == errSecSuccess, let data=existing as? Data { events=(try? JSONDecoder().decode([VaultActivity].self,from:data)) ?? [] }
        events.insert(VaultActivity(id:UUID().uuidString,date:Date().timeIntervalSince1970*1000,action:action,detail:String(detail.prefix(160))),at:0); events=Array(events.prefix(200))
        guard let data=try? JSONEncoder().encode(events) else{return}
        let key: [String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        let attrs: [String:Any]=[kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let code=SecItemUpdate(key as CFDictionary,attrs as CFDictionary); if code==errSecItemNotFound { var add=key;attrs.forEach{add[$0.key]=$0.value};_ = SecItemAdd(add as CFDictionary,nil) }
        activities=events
    }
    private func loadActivityEvents() -> [VaultActivity] {
        let query: [String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.vaultline.activity.v1",kSecAttrAccount as String:"events",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result:CFTypeRef?;guard SecItemCopyMatching(query as CFDictionary,&result)==errSecSuccess,let data=result as? Data else{return []}
        return (try? JSONDecoder().decode([VaultActivity].self,from:data)) ?? []
    }
    func saveLogin(_ value: LoginRecord) -> Bool {
        guard let parsed = URL(string: value.website.contains("://") ? value.website : "https://" + value.website),
              ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""), parsed.host != nil,
              !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !value.password.isEmpty else {
            status = "Enter a title, valid website, and password."; return false
        }
        var record = value
        if let old = logins.first(where: { $0.id == value.id }) {
            var history = old.passwordHistory ?? []
            if old.password != value.password { history.insert(old.password, at: 0) }
            record.passwordHistory = Array(history.prefix(5)); record.lastUsedAt = old.lastUsedAt
        }
        record.tags = Array((value.tags ?? []).map { String($0.prefix(32)) }.prefix(12))
        record.website = parsed.originString
        record.updatedAt = Date().timeIntervalSince1970 * 1000
        guard store(record, id: record.id, title: record.title, comment: record.host) else { return false }
        logActivity("Saved login", record.title); loadRecords(); status = "Saved \(record.title) to Mac Keychain."; return true
    }

    func saveCard(_ value: CardRecord) -> Bool {
        let digits = value.number.filter(\.isNumber)
        guard !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              luhnIsValid(digits), (1...12).contains(value.expiryMonth), (2020...2099).contains(value.expiryYear) else {
            status = "Check the card name, card number, and expiration date."; return false
        }
        var record = value
        record.number = digits
        record.updatedAt = Date().timeIntervalSince1970 * 1000
        guard store(record, id: record.id, title: record.title, comment: "card •••• \(record.last4)") else { return false }
        logActivity("Saved payment card", record.title); loadRecords(); status = "Saved \(record.title) to Mac Keychain."; return true
    }

    func saveNote(_ value: SecureNoteRecord) -> Bool {
        guard unlocked, !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !value.content.isEmpty else { status = "Enter a note title and content."; return false }
        var record = value; record.updatedAt = Date().timeIntervalSince1970 * 1000
        guard store(record, id: record.id, title: record.title, comment: "Vaultline secure note") else { return false }
        logActivity("Saved secure note", record.title); loadRecords(); status = "Saved secure note to Mac Keychain."; return true
    }
    func saveIdentity(_ value: IdentityRecord) -> Bool {
        guard unlocked, !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "Enter a profile name."; return false }
        var record = value; record.updatedAt = Date().timeIntervalSince1970 * 1000
        guard store(record, id: record.id, title: record.title, comment: "Vaultline identity") else { return false }
        logActivity("Saved identity", record.title); loadRecords(); status = "Saved identity to Mac Keychain."; return true
    }
    func deleteLogin(_ value: LoginRecord) {
        deleteID(value.id); logActivity("Deleted login", value.title); loadRecords(); status = "Deleted \(value.title)."
    }
    func deleteCard(_ value: CardRecord) {
        deleteID(value.id); loadRecords(); status = "Deleted \(value.title)."
    }
    func deleteNote(_ value: SecureNoteRecord) { deleteID(value.id); loadRecords(); status = "Deleted secure note." }
    func deleteIdentity(_ value: IdentityRecord) { deleteID(value.id); loadRecords(); status = "Deleted identity." }
    private func deleteID(_ id: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: serviceName,
                                    kSecAttrAccount as String: id]
        let code = SecItemDelete(query as CFDictionary)
        if code != errSecSuccess && code != errSecItemNotFound { status = "Delete failed (\(code))." }
    }
    func lock() {
        logins = []; cards = []; notes = []; identities = []; unlocked = false
        status = "Vault locked. Unlock again to manage your data."
    }
}

private extension URL {
    var originString: String { "\(scheme ?? "https")://\(host ?? "")" + (port.map { ":\($0)" } ?? "") }
}

private func luhnIsValid(_ value: String) -> Bool {
    let digits = value.compactMap(\.wholeNumberValue)
    guard (12...19).contains(digits.count) else { return false }
    let sum = digits.reversed().enumerated().reduce(0) { total, pair in
        let (index, digit) = pair
        if index.isMultiple(of: 2) { return total + digit }
        let doubled = digit * 2
        return total + (doubled > 9 ? doubled - 9 : doubled)
    }
    return sum.isMultiple(of: 10)
}

enum VaultlinePalette {
    static var light: Bool { UserDefaults.standard.string(forKey: "vaultlineDesktopAppearance") == "light" || (UserDefaults.standard.string(forKey: "vaultlineDesktopAppearance") == "system" && NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua) }
    static var background: Color { light ? Color(red:0.953,green:0.965,blue:0.984) : Color(red:0.047,green:0.078,blue:0.137) }
    static var sidebar: Color { light ? Color(red:0.925,green:0.945,blue:0.973) : Color(red:0.055,green:0.090,blue:0.157) }
    static var panel: Color { light ? .white : Color(red:0.071,green:0.118,blue:0.192) }
    static var panelRaised: Color { light ? Color(red:0.890,green:0.925,blue:0.965) : Color(red:0.090,green:0.145,blue:0.231) }
    static var border: Color { light ? Color(red:0.800,green:0.840,blue:0.900) : Color(red:0.149,green:0.212,blue:0.306) }
    static var text: Color { light ? Color(red:0.10,green:0.15,blue:0.23) : Color(red:0.910,green:0.937,blue:0.980) }
    static var muted: Color { light ? Color(red:0.34,green:0.41,blue:0.51) : Color(red:0.608,green:0.667,blue:0.753) }
    static let accent = Color(red:0.20,green:0.53,blue:0.94)
    static let green = Color(red:0.145,green:0.718,blue:0.482)
}

struct ContentView: View {
    @StateObject private var vault = VaultModel()
    @AppStorage("vaultlineDesktopAppearance") private var appearance = "system"
    @AppStorage("vaultlineClipboardClearSeconds") private var clipboardClearSeconds = 45
    @AppStorage("vaultlineShowCards") private var showCards = true
    @AppStorage("vaultlineShowNotes") private var showNotes = true
    @AppStorage("vaultlineShowIdentities") private var showIdentities = true
    @State private var section = "Logins"
    @State private var search = ""
    @State private var selectedID: String?
    @State private var showLoginEditor = false
    @State private var showCardEditor = false
    @State private var showNoteEditor = false
    @State private var showIdentityEditor = false
    @State private var editNote: SecureNoteRecord?
    @State private var editIdentity: IdentityRecord?
    @State private var pendingDeleteNote: SecureNoteRecord?
    @State private var pendingDeleteIdentity: IdentityRecord?
    @State private var editLogin: LoginRecord?
    @State private var editCard: CardRecord?
    @State private var pendingDeleteLogin: LoginRecord?
    @State private var pendingDeleteCard: CardRecord?

    private var filteredLogins: [LoginRecord] {
        let q = search.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return vault.logins.filter { q.isEmpty || ([$0.title, $0.website, $0.username, $0.category] + ($0.tags ?? [])).contains(where: { $0.lowercased().contains(q) }) }
    }
    private var filteredCards: [CardRecord] {
        let q = search.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return vault.cards.filter { q.isEmpty || ([$0.title, $0.cardholder, $0.last4] + ($0.tags ?? [])).contains(where: { $0.lowercased().contains(q) }) }
    }
    private var chosenLogin: LoginRecord? { vault.logins.first { $0.id == selectedID } }
    private var chosenCard: CardRecord? { vault.cards.first { $0.id == selectedID } }
    private var filteredNotes: [SecureNoteRecord] { let q=search.lowercased(); return vault.notes.filter { q.isEmpty || [$0.title,$0.content,$0.category,$0.tags.joined(separator:" ")].contains { $0.lowercased().contains(q) } } }
    private var filteredIdentities: [IdentityRecord] { let q=search.lowercased(); return vault.identities.filter { q.isEmpty || [$0.title,$0.fullName,$0.email,$0.company,$0.tags.joined(separator:" ")].contains { $0.lowercased().contains(q) } } }
    private var chosenNote: SecureNoteRecord? { vault.notes.first { $0.id == selectedID } }
    private var chosenIdentity: IdentityRecord? { vault.identities.first { $0.id == selectedID } }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(VaultlinePalette.border).frame(width: 1)
            mainPanel
        }
        .background(VaultlinePalette.background)
        .foregroundStyle(VaultlinePalette.text)
        .tint(VaultlinePalette.accent)
        .preferredColorScheme(appearance == "system" ? nil : (appearance == "light" ? .light : .dark))
        .frame(minWidth: 1040, minHeight: 700)
        .sheet(isPresented: $showLoginEditor) {
            LoginEditor(record: editLogin, onSave: { value in
                let ok = vault.saveLogin(value)
                if ok { selectedID = value.id; section = "Logins" }
                return ok
            })
        }
        .sheet(isPresented: $showCardEditor) {
            CardEditor(record: editCard, onSave: { value in
                let ok = vault.saveCard(value)
                if ok { selectedID = value.id; section = "Cards" }
                return ok
            })
        }
        .sheet(isPresented: $showNoteEditor) { NoteEditor(record: editNote, onSave: { value in let ok=vault.saveNote(value); if ok { selectedID=value.id; section="Notes" }; return ok }) }
        .sheet(isPresented: $showIdentityEditor) { IdentityEditor(record: editIdentity, onSave: { value in let ok=vault.saveIdentity(value); if ok { selectedID=value.id; section="Identities" }; return ok }) }
        .confirmationDialog("Delete this login?", isPresented: Binding(get: { pendingDeleteLogin != nil }, set: { if !$0 { pendingDeleteLogin = nil } }), presenting: pendingDeleteLogin) { item in
            Button("Delete \(item.title)", role: .destructive) { vault.deleteLogin(item); selectedID = nil; pendingDeleteLogin = nil }
            Button("Cancel", role: .cancel) { pendingDeleteLogin = nil }
        }
        .confirmationDialog("Delete this card?", isPresented: Binding(get: { pendingDeleteCard != nil }, set: { if !$0 { pendingDeleteCard = nil } }), presenting: pendingDeleteCard) { item in
            Button("Delete \(item.title)", role: .destructive) { vault.deleteCard(item); selectedID = nil; pendingDeleteCard = nil }
            Button("Cancel", role: .cancel) { pendingDeleteCard = nil }
        }
        .confirmationDialog("Delete this secure note?", isPresented: Binding(get: { pendingDeleteNote != nil }, set: { if !$0 { pendingDeleteNote=nil } }), presenting: pendingDeleteNote) { item in
            Button("Delete \(item.title)", role: .destructive) { vault.deleteNote(item); selectedID=nil; pendingDeleteNote=nil }
            Button("Cancel", role: .cancel) { pendingDeleteNote=nil }
        }
        .confirmationDialog("Delete this identity?", isPresented: Binding(get: { pendingDeleteIdentity != nil }, set: { if !$0 { pendingDeleteIdentity=nil } }), presenting: pendingDeleteIdentity) { item in
            Button("Delete \(item.title)", role: .destructive) { vault.deleteIdentity(item); selectedID=nil; pendingDeleteIdentity=nil }
            Button("Cancel", role: .cancel) { pendingDeleteIdentity=nil }
        }
        .onChange(of: section) { _ in selectedID = nil }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarBrand
            sidebarNavigation
            sidebarSearch
            sidebarEntries
            sidebarFooter
        }
        .frame(width: 278)
        .background(VaultlinePalette.sidebar)
    }

    private var sidebarBrand: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(
                        colors: [VaultlinePalette.accent, Color(red: 0.09, green: 0.39, blue: 0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("Vaultline")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(VaultlinePalette.text)
                Text("PRIVATE VAULT")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(VaultlinePalette.muted)
            }
            Spacer(minLength: 4)
            Text("1.0.0")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(VaultlinePalette.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(VaultlinePalette.panelRaised, in: Capsule())
                .overlay(Capsule().stroke(VaultlinePalette.border, lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 25)
    }

    private var sidebarNavigation: some View {
        VStack(spacing: 6) {
            sidebarButton("Overview", icon: "square.grid.2x2.fill", count: nil, target: "Dashboard")
            sidebarButton("Logins", icon: "key.horizontal.fill", count: vault.logins.count)
            sidebarButton("Recently used", icon: "clock.fill", count: nil, target: "Recent")
            sidebarButton("Favorites", icon: "star.fill", count: favoriteCount, target: "Favorites")
            if showCards {
                sidebarButton("Cards", icon: "creditcard.fill", count: vault.cards.count)
            }
            if showNotes {
                sidebarButton("Secure Notes", icon: "note.text", count: vault.notes.count, target: "Notes")
            }
            if showIdentities {
                sidebarButton("Identities", icon: "person.text.rectangle", count: vault.identities.count, target: "Identities")
            }
            sidebarButton("Security Center", icon: "shield.lefthalf.filled", count: nil, target: "Security")
            sidebarButton("Activity", icon: "clock.arrow.circlepath", count: nil, target: "Activity")
            sidebarButton("Settings", icon: "gearshape.fill", count: nil, target: "Settings")
        }
        .padding(.horizontal, 13)
    }

    private var favoriteCount: Int {
        vault.logins.filter { $0.favorite }.count
        + vault.cards.filter { $0.favorite }.count
        + vault.notes.filter { $0.favorite }.count
        + vault.identities.filter { $0.favorite }.count
    }

    private var sidebarSearch: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VaultlinePalette.muted)
            TextField("Search your vault", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(VaultlinePalette.text)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(VaultlinePalette.panelRaised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(VaultlinePalette.border, lineWidth: 1))
        .padding(.horizontal, 17)
        .padding(.top, 17)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var sidebarEntries: some View {
        if vault.unlocked {
            ScrollView {
                LazyVStack(spacing: 5) {
                    sidebarEntryRows
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        } else {
            sidebarLockedState
        }
    }

    private var sidebarLockedState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 19))
                .foregroundStyle(VaultlinePalette.muted)
            Text("Unlock to view your vault")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VaultlinePalette.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private var sidebarEntryRows: some View {
        if section == "Logins" || section == "Recent" || section == "Favorites" {
            loginSidebarRows
        }
        if section == "Favorites" {
            favoriteSidebarRows
        }
        if section == "Cards" {
            cardSidebarRows
        }
        if section == "Notes" {
            noteSidebarRows
        }
        if section == "Identities" {
            identitySidebarRows
        }
    }

    private var visibleLoginRows: [LoginRecord] {
        if section == "Recent" {
            return filteredLogins
                .filter { ($0.lastUsedAt ?? 0) > 0 }
                .sorted { ($0.lastUsedAt ?? 0) > ($1.lastUsedAt ?? 0) }
        }
        if section == "Favorites" {
            return filteredLogins.filter { $0.favorite }
        }
        return filteredLogins
    }

    private var loginSidebarRows: some View {
        Group {
            if visibleLoginRows.isEmpty {
                sidebarEmpty(
                    title: "No logins found",
                    subtitle: search.isEmpty ? "Add a login to get started." : "Try a different search."
                )
            }
            ForEach(visibleLoginRows) { item in
                sidebarItem(
                    id: item.id,
                    title: item.title,
                    subtitle: item.host,
                    symbol: "key.fill",
                    favorite: item.favorite,
                    tint: VaultlinePalette.accent
                )
            }
        }
    }

    private var favoriteSidebarRows: some View {
        Group {
            ForEach(filteredCards.filter { $0.favorite }) { item in
                sidebarItem(id: item.id, title: item.title, subtitle: "•••• \(item.last4)", symbol: "creditcard.fill", favorite: true, tint: Color(red: 0.62, green: 0.56, blue: 1.0))
            }
            ForEach(filteredNotes.filter { $0.favorite }) { item in
                sidebarItem(id: item.id, title: item.title, subtitle: item.category, symbol: "note.text", favorite: true, tint: VaultlinePalette.accent)
            }
            ForEach(filteredIdentities.filter { $0.favorite }) { item in
                sidebarItem(id: item.id, title: item.title, subtitle: item.email.isEmpty ? item.fullName : item.email, symbol: "person.text.rectangle", favorite: true, tint: VaultlinePalette.accent)
            }
        }
    }

    private var cardSidebarRows: some View {
        Group {
            if filteredCards.isEmpty {
                sidebarEmpty(title: "No cards found", subtitle: search.isEmpty ? "Add a payment card to get started." : "Try a different search.")
            }
            ForEach(filteredCards) { item in
                sidebarItem(id: item.id, title: item.title, subtitle: "•••• \(item.last4)", symbol: "creditcard.fill", favorite: item.favorite, tint: Color(red: 0.62, green: 0.56, blue: 1.0))
            }
        }
    }

    private var noteSidebarRows: some View {
        Group {
            if filteredNotes.isEmpty {
                sidebarEmpty(title: "No notes found", subtitle: "Create a secure note.")
            }
            ForEach(filteredNotes) { item in
                sidebarItem(id: item.id, title: item.title, subtitle: item.category, symbol: "note.text", favorite: item.favorite, tint: VaultlinePalette.accent)
            }
        }
    }

    private var identitySidebarRows: some View {
        Group {
            if filteredIdentities.isEmpty {
                sidebarEmpty(title: "No identities found", subtitle: "Create a personal profile.")
            }
            ForEach(filteredIdentities) { item in
                sidebarItem(id: item.id, title: item.title, subtitle: item.email.isEmpty ? item.fullName : item.email, symbol: "person.text.rectangle", favorite: item.favorite, tint: VaultlinePalette.accent)
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Rectangle().fill(VaultlinePalette.border).frame(height: 1)
            HStack(spacing: 9) {
                Circle()
                    .fill(vault.unlocked ? VaultlinePalette.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(vault.unlocked ? "Mac Keychain connected" : "Vault locked")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VaultlinePalette.muted)
                Spacer()
                Button { vault.loadRecords() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(VaultlinePalette.muted)
                .disabled(!vault.unlocked)
                .help("Refresh vault")
                Button { vault.lock(); selectedID = nil } label: {
                    Image(systemName: "lock")
                }
                .buttonStyle(.plain)
                .foregroundStyle(VaultlinePalette.muted)
                .disabled(!vault.unlocked)
                .help("Lock Vaultline")
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 15)
        }
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(["Dashboard":"Your vault overview","Recent":"Recently used","Favorites":"Favorite items","Logins":"Your passwords","Cards":"Payment cards","Notes":"Secure notes","Identities":"Personal identities","Security":"Security Center","Settings":"Settings"][section] ?? "Vaultline")
                        .font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-0.6)
                    Text(["Dashboard":"A quick look at your private vault.","Recent":"Your latest account activity.","Favorites":"Your pinned vault items.","Logins":"Manage website accounts and autofill details.","Cards":"Keep your payment cards organized in your private vault.","Notes":"Private notes stored in your Mac Keychain.","Identities":"Profiles for forms you choose to autofill.","Security":"Review password health and local vault activity.","Settings":"Customize the Vaultline experience."][section] ?? "Your private vault.")
                        .font(.system(size: 12)).foregroundStyle(VaultlinePalette.muted)
                }
                Spacer()
                HStack(spacing: 7) {
                    HStack(spacing: 7) {
                        Circle().fill(vault.unlocked ? VaultlinePalette.green : Color.orange).frame(width: 7, height: 7)
                        Text(vault.unlocked ? "Desktop connected" : "Vault locked").font(.system(size: 10, weight: .semibold))
                    }.foregroundStyle(VaultlinePalette.muted).padding(.horizontal, 11).padding(.vertical, 8)
                        .background(VaultlinePalette.panel, in: Capsule()).overlay(Capsule().stroke(VaultlinePalette.border, lineWidth: 1))
                    Button { vault.loadRecords() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(IconChromeButtonStyle()).disabled(!vault.unlocked).help("Refresh")
                    Menu { Picker("Appearance", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") } } label: { Image(systemName: "circle.lefthalf.filled") }.buttonStyle(IconChromeButtonStyle()).help("Appearance")
                    Button { if section == "Logins" { editLogin=nil; showLoginEditor=true } else if section == "Cards" { editCard=nil; showCardEditor=true } else if section == "Notes" { editNote=nil; showNoteEditor=true } else if section == "Identities" { editIdentity=nil; showIdentityEditor=true } } label: {
                        Label(["Logins":"Add login","Cards":"Add card","Notes":"Add note","Identities":"Add identity"][section] ?? "Add", systemImage: "plus")
                    }.buttonStyle(PrimaryChromeButtonStyle()).keyboardShortcut("n", modifiers: .command).disabled(!vault.unlocked || !["Logins","Cards","Notes","Identities"].contains(section))
                }
            }.padding(.horizontal, 30).padding(.vertical, 25)
            Rectangle().fill(VaultlinePalette.border).frame(height: 1)

            if !vault.unlocked {
                lockedState
            } else if ["Logins","Recent","Favorites"].contains(section), let record = chosenLogin {
                LoginDetail(record: record, vault: vault, onEdit: { editLogin = record; showLoginEditor = true }, onDelete: { pendingDeleteLogin = record }).id(record.id)
                    .background(VaultlinePalette.background)
            } else if ["Cards", "Favorites"].contains(section), let record = chosenCard {
                CardDetail(record: record, vault: vault, onEdit: { editCard = record; showCardEditor = true }, onDelete: { pendingDeleteCard = record }).id(record.id)
                    .background(VaultlinePalette.background)
            } else if ["Notes", "Favorites"].contains(section), let record = chosenNote {
                NoteDetail(record: record, onEdit: { editNote=record; showNoteEditor=true }, onDelete: { pendingDeleteNote=record }).background(VaultlinePalette.background)
            } else if ["Identities", "Favorites"].contains(section), let record = chosenIdentity {
                IdentityDetail(record: record, onEdit: { editIdentity=record; showIdentityEditor=true }, onDelete: { pendingDeleteIdentity=record }).background(VaultlinePalette.background)
            } else if section == "Dashboard" {
                DashboardView(logins:vault.logins,cards:vault.cards,notes:vault.notes,identities:vault.identities,onSelect:{ section=$0 }).background(VaultlinePalette.background)
            } else if section == "Security" {
                SecurityCenterView(logins: vault.logins).background(VaultlinePalette.background)
            } else if section == "Activity" {
                ActivityView(events:vault.activities).background(VaultlinePalette.background)
            } else if section == "Settings" {
                SettingsView(appearance: $appearance, clipboardClearSeconds: $clipboardClearSeconds, showCards: $showCards, showNotes: $showNotes, showIdentities: $showIdentities).background(VaultlinePalette.background)
            } else {
                emptyState
            }

            Rectangle().fill(VaultlinePalette.border).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(VaultlinePalette.accent)
                Text(vault.status).lineLimit(1)
                Spacer()
                Text("Stored locally on this Mac").foregroundStyle(VaultlinePalette.muted)
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(VaultlinePalette.muted)
                .padding(.horizontal, 22).padding(.vertical, 12)
                .background(VaultlinePalette.sidebar)
        }
        .background(VaultlinePalette.background)
    }

    private var lockedState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 17) {
                ZStack {
                    RoundedRectangle(cornerRadius: 23).fill(VaultlinePalette.panelRaised).frame(width: 82, height: 82)
                    Image(systemName: "lock.shield.fill").font(.system(size: 38, weight: .medium)).foregroundStyle(VaultlinePalette.accent)
                }
                VStack(spacing: 7) {
                    Text("Welcome to Vaultline").font(.system(size: 27, weight: .bold, design: .rounded)).tracking(-0.7)
                    Text("Your Mac is the vault. Your extension is the interface.")
                        .font(.system(size: 13)).foregroundStyle(VaultlinePalette.muted).multilineTextAlignment(.center)
                }
                Button { vault.unlock() } label: {
                    Label("Unlock with Touch ID or Mac password", systemImage: "lock.open.fill")
                }.buttonStyle(PrimaryChromeButtonStyle()).padding(.top, 4)
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.shield.fill")
                    Text("Your vault is protected by this Mac's Keychain.")
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(VaultlinePalette.muted).padding(.top, 5)
                if vault.status != "Your vault is stored in this Mac's Keychain." && !vault.status.isEmpty {
                    Text(vault.status).font(.system(size: 10)).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.top, 3)
                }
            }
            .padding(.horizontal, 35).padding(.vertical, 38)
            .frame(maxWidth: 490)
            .background(VaultlinePalette.panel, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(VaultlinePalette.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 15)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(35)
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(VaultlinePalette.panelRaised).frame(width: 76, height: 76)
                Image(systemName: ["Logins":"key.horizontal.fill","Cards":"creditcard.fill","Notes":"note.text","Identities":"person.text.rectangle"][section] ?? "shield.lefthalf.filled")
                    .font(.system(size: 30)).foregroundStyle(VaultlinePalette.accent)
            }
            Text(search.isEmpty ? (["Logins":"Your vault is ready","Cards":"Your wallet is ready","Notes":"No secure notes yet","Identities":"No identities yet"][section] ?? "Nothing to show") : "No matching items")
                .font(.system(size: 21, weight: .bold, design: .rounded))
            Text(search.isEmpty ? (["Logins":"Add your first login or save one from the browser extension.","Cards":"Add a payment card to your encrypted vault.","Notes":"Create your first encrypted private note.","Identities":"Create a profile for form autofill."][section] ?? "Explore your private vault.") : "Try searching for another name or website.")
                .font(.system(size: 12)).foregroundStyle(VaultlinePalette.muted).multilineTextAlignment(.center).frame(maxWidth: 360)
            if search.isEmpty && ["Logins", "Cards", "Notes", "Identities"].contains(section) {
                Button { if section == "Logins" { editLogin=nil; showLoginEditor=true } else if section == "Cards" { editCard=nil; showCardEditor=true } else if section == "Notes" { editNote=nil; showNoteEditor=true } else { editIdentity=nil; showIdentityEditor=true } } label: {
                    Label(["Logins":"Add a login","Cards":"Add a card","Notes":"Add a note","Identities":"Add identity"][section] ?? "Add", systemImage: "plus")
                }.buttonStyle(PrimaryChromeButtonStyle()).padding(.top, 3)
            }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }

    private func sidebarButton(_ title: String, icon: String, count: Int?, target: String? = nil) -> some View {
        let destination = target ?? title
        let isSelected = section == destination
        return Button { section = destination; selectedID = nil; search = "" } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).frame(width: 19).foregroundStyle(isSelected ? VaultlinePalette.accent : VaultlinePalette.muted)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(VaultlinePalette.text)
                Spacer()
                if let count {
                    Text("\(count)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(isSelected ? VaultlinePalette.text : VaultlinePalette.muted)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(isSelected ? VaultlinePalette.accent.opacity(0.18) : VaultlinePalette.panelRaised, in: Capsule())
                }
            }.padding(.horizontal, 12).padding(.vertical, 11)
                .background(isSelected ? VaultlinePalette.panelRaised : .clear, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(isSelected ? VaultlinePalette.border : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func sidebarItem(id: String, title: String, subtitle: String, symbol: String, favorite: Bool, tint: Color) -> some View {
        Button { selectedID = id } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.13)).frame(width: 36, height: 36)
                    .overlay(Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(VaultlinePalette.text).lineLimit(1)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(VaultlinePalette.muted).lineLimit(1)
                }
                Spacer(minLength: 2)
                if favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color.orange) }
            }.padding(8).background(selectedID == id ? VaultlinePalette.panelRaised : .clear, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(selectedID == id ? VaultlinePalette.accent.opacity(0.40) : .clear, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func sidebarEmpty(title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "tray").font(.system(size: 21)).foregroundStyle(VaultlinePalette.muted).padding(.bottom, 4)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(VaultlinePalette.text)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(VaultlinePalette.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}

struct PrimaryChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(configuration.isPressed ? Color(red: 0.20, green: 0.48, blue: 0.82) : VaultlinePalette.accent, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: VaultlinePalette.accent.opacity(configuration.isPressed ? 0.05 : 0.20), radius: 12, y: 5)
    }
}

struct IconChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(VaultlinePalette.muted)
            .frame(width: 36, height: 36).background(configuration.isPressed ? VaultlinePalette.panelRaised : VaultlinePalette.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaultlinePalette.border, lineWidth: 1))
    }
}

private func copyVaultText(_ value: String, clearAfter seconds: Int? = nil) {
    guard !value.isEmpty else { return }
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType:.string)
    let delay = seconds ?? (UserDefaults.standard.object(forKey:"vaultlineClipboardClearSeconds") as? Int ?? 45)
    guard delay > 0 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) { if NSPasteboard.general.string(forType:.string) == value { NSPasteboard.general.clearContents() } }
}

struct LoginDetail: View {
    let record: LoginRecord
    @ObservedObject var vault: VaultModel
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var revealed = false
    @State private var copied = ""
    @State private var revealedHistoryIndices: Set<Int> = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [.blue.opacity(0.9), .cyan.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 62, height: 62)
                        .overlay(Text(String(record.title.prefix(1)).uppercased()).font(.largeTitle.bold()).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 4) { Text(record.title).font(.largeTitle.bold()); Text(record.host).foregroundStyle(.secondary) }
                    Spacer()
                    Button(action: onEdit) { Label("Edit", systemImage: "pencil") }.buttonStyle(IconChromeButtonStyle())
                    Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(IconChromeButtonStyle())
                }.padding(.bottom, 12)
                GroupBox { VStack(spacing: 0) {
                    detailRow("Website", record.website, copy: record.website)
                    Divider()
                    detailRow("Username", record.username.isEmpty ? "Not set" : record.username, copy: record.username)
                    Divider()
                    HStack { VStack(alignment: .leading, spacing: 5) { Text("PASSWORD").font(.caption2.bold()).foregroundStyle(.secondary); Text(revealed ? record.password : "••••••••••••").font(.system(.body, design: .monospaced)).textSelection(.enabled) }; Spacer(); Button(revealed ? "Hide" : "Reveal") { if revealed { revealed = false } else { vault.authenticate(reason: "Reveal the password for \(record.title)") { if $0 { revealed = true; DispatchQueue.main.asyncAfter(deadline: .now() + 20) { revealed = false } } } } }.buttonStyle(.borderless) }
                        .padding(.vertical, 14)
                    if revealed {
                        HStack { Spacer(); Button("Copy password") {
                            vault.authenticate(reason: "Copy the password for \(record.title)") { success in
                                if success { copyVaultText(record.password); copied = "Password copied. Clipboard clear is scheduled." }
                            }
                        }.buttonStyle(.bordered) }.padding(.bottom, 10)
                    }
                }} label: { Label("Login details", systemImage: "key.horizontal.fill") }
                    .padding(5).background(VaultlinePalette.panel, in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(VaultlinePalette.border, lineWidth: 1))
                if let history = record.passwordHistory, !history.isEmpty {
                    DisclosureGroup("Previous passwords (\(history.count))") {
                        VStack(spacing: 8) {
                            ForEach(Array(history.enumerated()), id: \.offset) { index, oldPassword in
                                HStack {
                                    Text(revealedHistoryIndices.contains(index) ? oldPassword : "••••••••••••")
                                        .font(.system(.caption, design: .monospaced)).lineLimit(1).textSelection(.enabled)
                                    Spacer()
                                    Button(revealedHistoryIndices.contains(index) ? "Hide" : "Reveal") {
                                        if revealedHistoryIndices.contains(index) { revealedHistoryIndices.remove(index) }
                                        else { vault.authenticate(reason: "Reveal a previous password for \(record.title)") { success in if success { revealedHistoryIndices.insert(index); DispatchQueue.main.asyncAfter(deadline: .now()+20) { revealedHistoryIndices.remove(index) } } } }
                                    }.buttonStyle(.borderless)
                                    Button { vault.authenticate(reason: "Copy a previous password for \(record.title)") { success in if success { copyVaultText(oldPassword); copied = "Previous password copied." } } } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
                                }.padding(.vertical, 5)
                            }
                        }.padding(.top, 8)
                    }.font(.subheadline.bold()).padding(14).background(VaultlinePalette.panel, in: RoundedRectangle(cornerRadius: 12))
                }
                HStack { Label("\(record.category) · \(record.favorite ? "Favorite" : "Standard")", systemImage: "tag"); Spacer(); if !copied.isEmpty { Text(copied).foregroundStyle(.secondary) } }.font(.caption).foregroundStyle(.secondary)
                Text("The password stays hidden until you approve a macOS authentication prompt.").font(.caption).foregroundStyle(.secondary)
            }.padding(30).frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .center)
        }.background(VaultlinePalette.background).onChange(of: record.id) { _ in revealed = false; revealedHistoryIndices = [] }
    }
    private func detailRow(_ label: String, _ value: String, copy: String) -> some View {
        HStack { VStack(alignment: .leading, spacing: 5) { Text(label.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary); Text(value).textSelection(.enabled) }; Spacer(); Button { copyVaultText(copy); copied = "Copied \(label.lowercased())." } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).disabled(copy.isEmpty) }.padding(.vertical, 14)
    }
}

struct CardDetail: View {
    let record: CardRecord
    @ObservedObject var vault: VaultModel
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var revealed = false
    @State private var copied = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 62, height: 62).overlay(Image(systemName: "creditcard.fill").font(.title).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 4) { Text(record.title).font(.largeTitle.bold()); Text("Payment card · ending in \(record.last4)").foregroundStyle(.secondary) }
                    Spacer(); Button(action: onEdit) { Label("Edit", systemImage: "pencil") }.buttonStyle(IconChromeButtonStyle()); Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(IconChromeButtonStyle())
                }
                RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: [Color(red: 0.10, green: 0.18, blue: 0.36), Color(red: 0.22, green: 0.29, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(height: 190)
                    .overlay(alignment: .topLeading) { VStack(alignment: .leading, spacing: 18) { Text("VAULTLINE CARD").font(.caption.bold()).tracking(1.5); Spacer(); Text(revealed ? record.number : record.maskedNumber).font(.system(size: 18, weight: .medium, design: .monospaced)); HStack { VStack(alignment: .leading) { Text("CARDHOLDER").font(.system(size: 8, weight: .bold)); Text(record.cardholder.isEmpty ? "CARDHOLDER" : record.cardholder).font(.caption.bold()) }; Spacer(); VStack(alignment: .leading) { Text("EXPIRES").font(.system(size: 8, weight: .bold)); Text(String(format: "%02d/%02d", record.expiryMonth, record.expiryYear % 100)).font(.caption.bold()) } } }.foregroundStyle(.white).padding(22) }
                GroupBox { VStack(spacing: 0) {
                    HStack { VStack(alignment: .leading, spacing: 5) { Text("CARD NUMBER").font(.caption2.bold()).foregroundStyle(.secondary); Text(revealed ? record.number : record.maskedNumber).font(.system(.body, design: .monospaced)) }; Spacer(); Button(revealed ? "Hide" : "Reveal") { if revealed { revealed = false } else { vault.authenticate(reason: "Reveal the card number for \(record.title)") { if $0 { revealed = true; DispatchQueue.main.asyncAfter(deadline: .now() + 20) { revealed = false } } } } }.buttonStyle(.borderless) }.padding(.vertical, 13)
                    Divider(); cardRow("Cardholder", record.cardholder); Divider(); cardRow("Expiration", String(format: "%02d/%04d", record.expiryMonth, record.expiryYear)); Divider(); cardRow("Billing ZIP", record.billingZip); if !record.notes.isEmpty { Divider(); cardRow("Notes", record.notes) }
                }} label: { Label("Card details", systemImage: "creditcard") }
                    .padding(5).background(VaultlinePalette.panel, in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(VaultlinePalette.border, lineWidth: 1))
                HStack { Button("Copy number") { vault.authenticate(reason: "Copy the card number for \(record.title)") { if $0 { copyVaultText(record.number); copied = "Card number copied." } } }.buttonStyle(.bordered); Spacer(); Text(copied).font(.caption).foregroundStyle(.secondary) }
                if let tags = record.tags, !tags.isEmpty { Text("Tags: " + tags.joined(separator: ", ")).font(.caption).foregroundStyle(VaultlinePalette.muted) }
                Text("Vaultline does not store CVV/CVC codes or card PINs.").font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .center)
        }.background(VaultlinePalette.background).onChange(of: record.id) { _ in revealed = false }
    }
    private func cardRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).font(.subheadline).foregroundStyle(.secondary); Spacer(); Text(value.isEmpty ? "Not set" : value).textSelection(.enabled) }.padding(.vertical, 12)
    }
}

struct LoginEditor: View {
    let record: LoginRecord?
    let onSave: (LoginRecord) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var website = ""
    @State private var username = ""
    @State private var password = ""
    @State private var category = "Personal"
    @State private var favorite = false
    @State private var tagsText = ""
    @State private var showPassword = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(record == nil ? "Add login" : "Edit login").font(.title2.bold())
            Form {
                TextField("Account name", text: $title)
                TextField("Website", text: $website)
                TextField("Username or email", text: $username)
                HStack { Group { if showPassword { TextField("Password", text: $password) } else { SecureField("Password", text: $password) } }; Button(showPassword ? "Hide" : "Show") { showPassword.toggle() }.buttonStyle(.borderless) }
                Picker("Category", selection: $category) { ForEach(["Personal","Work","Banking","Email","Social","Shopping","Gaming","Travel","Other"], id: \.self) { Text($0) } }
                TextField("Tags (comma-separated)", text: $tagsText)
                Toggle("Favorite", isOn: $favorite)
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { let candidate = website.contains("://") ? website : "https://" + website; guard let parsed = URL(string: candidate), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""), parsed.host != nil else { error = "Enter a valid website, such as accounts.example.com."; return }; let now = Date().timeIntervalSince1970 * 1000; let value = LoginRecord(id: record?.id ?? UUID().uuidString, title: title, website: candidate, username: username, password: password, category: category, favorite: favorite, createdAt: record?.createdAt ?? now, updatedAt: now, tags: tagsText.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) }, passwordHistory: record?.passwordHistory, lastUsedAt: record?.lastUsedAt); if onSave(value) { dismiss() } }.buttonStyle(.borderedProminent).disabled(title.isEmpty || website.isEmpty || password.isEmpty) }
        }.padding(22).frame(width: 500, height: 430).onAppear { if let record { title = record.title; website = record.website; username = record.username; password = record.password; category = record.category; favorite = record.favorite; tagsText = (record.tags ?? []).joined(separator:", ") } }
    }
}

struct CardEditor: View {
    let record: CardRecord?
    let onSave: (CardRecord) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var cardholder = ""
    @State private var number = ""
    @State private var month = ""
    @State private var year = ""
    @State private var zip = ""
    @State private var notes = ""
    @State private var favorite = false
    @State private var tagsText = ""
    @State private var showNumber = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(record == nil ? "Add payment card" : "Edit payment card").font(.title2.bold())
            Form {
                TextField("Card nickname (e.g. Personal Visa)", text: $title)
                TextField("Cardholder name", text: $cardholder)
                HStack {
                    Group { if showNumber { TextField("Card number", text: $number) } else { SecureField("Card number", text: $number) } }
                    Button(showNumber ? "Hide" : "Show") { showNumber.toggle() }.buttonStyle(.borderless)
                }
                HStack { TextField("Month (MM)", text: $month); TextField("Year (YYYY)", text: $year) }
                TextField("Billing ZIP / postal code", text: $zip)
                TextField("Notes (optional)", text: $notes)
                TextField("Tags (comma-separated)", text: $tagsText)
                Toggle("Favorite", isOn: $favorite)
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            Text("Card number is stored in your Mac's Keychain. CVV/CVC and PIN are not stored.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save card") { guard let m = Int(month), let y = Int(year) else { error = "Enter a valid expiration month and year."; return }; let digits = number.filter(\.isNumber); guard luhnIsValid(digits) else { error = "The card number doesn't pass validation. Check the digits."; return }; guard (2020...2099).contains(y) else { error = "Enter an expiration year between 2020 and 2099."; return }; let now = Date().timeIntervalSince1970 * 1000; let value = CardRecord(id: record?.id ?? UUID().uuidString, title: title, cardholder: cardholder, number: digits, expiryMonth: m, expiryYear: y, billingZip: zip, notes: notes, favorite: favorite, createdAt: record?.createdAt ?? now, updatedAt: now, tags: tagsText.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) }); if onSave(value) { dismiss() } }.buttonStyle(.borderedProminent).disabled(title.isEmpty || number.isEmpty || month.isEmpty || year.isEmpty) }
        }.padding(22).frame(width: 500, height: 510).onAppear { if let record { title = record.title; cardholder = record.cardholder; number = record.number; month = String(format: "%02d", record.expiryMonth); year = String(record.expiryYear); zip = record.billingZip; notes = record.notes; favorite = record.favorite; tagsText = (record.tags ?? []).joined(separator:", ") } }
    }
}

struct NoteDetail: View {
    let record: SecureNoteRecord; let onEdit:()->Void; let onDelete:()->Void
    var body: some View { ScrollView { VStack(alignment:.leading,spacing:18) { HStack { Image(systemName:"note.text").font(.title).foregroundStyle(VaultlinePalette.accent); VStack(alignment:.leading){Text(record.title).font(.largeTitle.bold());Text(record.category).foregroundStyle(VaultlinePalette.muted)};Spacer();Button("Edit",action:onEdit).buttonStyle(IconChromeButtonStyle());Button(role:.destructive,action:onDelete){Image(systemName:"trash")}.buttonStyle(IconChromeButtonStyle()) }; Text(record.content).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(18).background(VaultlinePalette.panel,in:RoundedRectangle(cornerRadius:15));if !record.tags.isEmpty{Text("Tags: "+record.tags.joined(separator:", ")).foregroundStyle(VaultlinePalette.muted)} }.padding(28).frame(maxWidth:760).frame(maxWidth:.infinity,alignment:.center) }.background(VaultlinePalette.background) }
}
struct IdentityDetail: View {
    let record: IdentityRecord; let onEdit:()->Void; let onDelete:()->Void
    var body: some View { ScrollView { VStack(alignment:.leading,spacing:16){HStack{Image(systemName:"person.text.rectangle").font(.title).foregroundStyle(VaultlinePalette.accent);VStack(alignment:.leading){Text(record.title).font(.largeTitle.bold());Text(record.fullName).foregroundStyle(VaultlinePalette.muted)};Spacer();Button("Edit",action:onEdit).buttonStyle(IconChromeButtonStyle());Button(role:.destructive,action:onDelete){Image(systemName:"trash")}.buttonStyle(IconChromeButtonStyle())};GroupBox("Personal details"){VStack(spacing:0){identityRow("Full name",record.fullName);Divider();identityRow("Email",record.email);Divider();identityRow("Phone",record.phone);Divider();identityRow("Company",record.company);Divider();identityRow("Address",[record.addressLine1,record.addressLine2,record.city,record.region,record.postalCode,record.country].filter{!$0.isEmpty}.joined(separator:", "))}}.padding(5).background(VaultlinePalette.panel,in:RoundedRectangle(cornerRadius:14));Text("Identity autofill is available from the browser extension.").font(.caption).foregroundStyle(VaultlinePalette.muted)}.padding(28).frame(maxWidth:760).frame(maxWidth:.infinity,alignment:.center)}.background(VaultlinePalette.background) }
    private func identityRow(_ label:String,_ value:String)->some View{HStack{Text(label).foregroundStyle(VaultlinePalette.muted);Spacer();Text(value.isEmpty ? "Not set":value).textSelection(.enabled)}.padding(.vertical,10)}
}
struct NoteEditor: View {
    let record: SecureNoteRecord?; let onSave:(SecureNoteRecord)->Bool; @Environment(\.dismiss) private var dismiss
    @State private var title="";@State private var content="";@State private var category="Personal";@State private var tags="";@State private var favorite=false;@State private var error=""
    var body:some View{VStack(alignment:.leading,spacing:14){Text(record == nil ? "Add secure note":"Edit secure note").font(.title2.bold());Form{TextField("Title",text:$title);TextField("Category",text:$category);TextField("Tags (comma-separated)",text:$tags);TextEditor(text:$content).frame(minHeight:180);Toggle("Favorite",isOn:$favorite)};if !error.isEmpty{Text(error).foregroundStyle(.red)};HStack{Spacer();Button("Cancel"){dismiss()};Button("Save note"){let now=Date().timeIntervalSince1970*1000;let value=SecureNoteRecord(id:record?.id ?? UUID().uuidString,title:title,content:content,category:category,tags:tags.split(separator:",").map{$0.trimmingCharacters(in:.whitespaces)},favorite:favorite,createdAt:record?.createdAt ?? now,updatedAt:now);if onSave(value){dismiss()}else{error="Check the title and content."}}.buttonStyle(.borderedProminent).disabled(title.isEmpty||content.isEmpty)}}.padding(22).frame(width:540,height:520).onAppear{if let r=record{title=r.title;content=r.content;category=r.category;tags=r.tags.joined(separator:", ");favorite=r.favorite}}}
}
struct IdentityEditor: View {
    let record:IdentityRecord?;let onSave:(IdentityRecord)->Bool;@Environment(\.dismiss) private var dismiss
    @State private var title="";@State private var fullName="";@State private var email="";@State private var phone="";@State private var company="";@State private var address1="";@State private var address2="";@State private var city="";@State private var region="";@State private var postal="";@State private var country="";@State private var notes="";@State private var tags="";@State private var favorite=false
    var body:some View{VStack(alignment:.leading,spacing:12){Text(record == nil ? "Add identity":"Edit identity").font(.title2.bold());Form{TextField("Profile name",text:$title);TextField("Full name",text:$fullName);TextField("Email",text:$email);TextField("Phone",text:$phone);TextField("Company",text:$company);TextField("Address line 1",text:$address1);TextField("Address line 2",text:$address2);HStack{TextField("City",text:$city);TextField("State / region",text:$region)};HStack{TextField("Postal code",text:$postal);TextField("Country",text:$country)};TextField("Notes",text:$notes);TextField("Tags (comma-separated)",text:$tags);Toggle("Favorite",isOn:$favorite)};HStack{Spacer();Button("Cancel"){dismiss()};Button("Save identity"){let now=Date().timeIntervalSince1970*1000;let value=IdentityRecord(id:record?.id ?? UUID().uuidString,title:title,fullName:fullName,email:email,phone:phone,company:company,addressLine1:address1,addressLine2:address2,city:city,region:region,postalCode:postal,country:country,notes:notes,tags:tags.split(separator:",").map{$0.trimmingCharacters(in:.whitespaces)},favorite:favorite,createdAt:record?.createdAt ?? now,updatedAt:now);if onSave(value){dismiss()}}.buttonStyle(.borderedProminent).disabled(title.isEmpty)}}.padding(22).frame(width:540,height:640).onAppear{if let r=record{title=r.title;fullName=r.fullName;email=r.email;phone=r.phone;company=r.company;address1=r.addressLine1;address2=r.addressLine2;city=r.city;region=r.region;postal=r.postalCode;country=r.country;notes=r.notes;tags=r.tags.joined(separator:", ");favorite=r.favorite}}}
}
struct DashboardView:View{let logins:[LoginRecord];let cards:[CardRecord];let notes:[SecureNoteRecord];let identities:[IdentityRecord];let onSelect:(String)->Void
    var body:some View{ScrollView{VStack(alignment:.leading,spacing:20){Text("Welcome back").font(.largeTitle.bold());Text("Your private vault at a glance.").foregroundStyle(VaultlinePalette.muted);LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12){metric("Logins",logins.count,"key.fill");metric("Cards",cards.count,"creditcard.fill");metric("Secure notes",notes.count,"note.text");metric("Identities",identities.count,"person.text.rectangle")};GroupBox("Recently used logins"){ForEach(logins.sorted{($0.lastUsedAt ?? 0)>($1.lastUsedAt ?? 0)}.prefix(6)){item in HStack{Image(systemName:"key.fill").foregroundStyle(VaultlinePalette.accent);VStack(alignment:.leading){Text(item.title);Text(item.host).font(.caption).foregroundStyle(VaultlinePalette.muted)};Spacer();Text(item.lastUsedAt == nil ? "Not used yet":Date(timeIntervalSince1970:(item.lastUsedAt ?? 0)/1000).formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(VaultlinePalette.muted)}.padding(.vertical,4)}}}.padding(28).frame(maxWidth:780).frame(maxWidth:.infinity,alignment:.center)}.background(VaultlinePalette.background)}
    private func metric(_ title:String,_ count:Int,_ icon:String)->some View{VStack(alignment:.leading,spacing:8){Image(systemName:icon).foregroundStyle(VaultlinePalette.accent);Text(String(count)).font(.system(size:28,weight:.bold,design:.rounded));Text(title).font(.caption).foregroundStyle(VaultlinePalette.muted)}.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(VaultlinePalette.panel,in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(VaultlinePalette.border,lineWidth:1))}
}
struct SecurityCenterView:View{let logins:[LoginRecord]
    private var weakCount:Int{logins.filter{$0.password.count<12}.count};private var reusedCount:Int{Dictionary(grouping:logins,by:{$0.password}).values.filter{$0.count>1}.reduce(0){$0+$1.count}};private var insecureCount:Int{logins.filter{URL(string:$0.website)?.scheme?.lowercased()=="http" && !["localhost","127.0.0.1"].contains($0.host)}.count}
    var body:some View{VStack(alignment:.leading,spacing:18){Text("Local password health").font(.title2.bold());Text("These checks run on this Mac. They do not contact a breach database.").foregroundStyle(VaultlinePalette.muted);HStack{health("Weak / short passwords",weakCount,"exclamationmark.shield");health("Reused passwords",reusedCount,"arrow.triangle.2.circlepath");health("HTTP websites",insecureCount,"lock.slash")};Text("Recommendations").font(.headline);Text("Use unique passwords of at least 12 characters. Keep your Mac updated, lock the vault when away, and maintain an encrypted backup.").foregroundStyle(VaultlinePalette.muted);Spacer()}.padding(28).frame(maxWidth:760,alignment:.leading).frame(maxWidth:.infinity,alignment:.center)}
    private func health(_ label:String,_ value:Int,_ icon:String)->some View{VStack(alignment:.leading,spacing:8){Image(systemName:icon).foregroundStyle(VaultlinePalette.accent);Text(String(value)).font(.title.bold());Text(label).font(.caption).foregroundStyle(VaultlinePalette.muted)}.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(VaultlinePalette.panel,in:RoundedRectangle(cornerRadius:14))}
}
struct ActivityView:View{let events:[VaultActivity];var body:some View{ScrollView{VStack(alignment:.leading,spacing:10){ForEach(events){e in HStack{Image(systemName:"clock.arrow.circlepath").foregroundStyle(VaultlinePalette.accent);VStack(alignment:.leading){Text(e.action).font(.subheadline.bold());Text(e.detail).font(.caption).foregroundStyle(VaultlinePalette.muted)};Spacer();Text(Date(timeIntervalSince1970:e.date/1000).formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(VaultlinePalette.muted)}};if events.isEmpty{Text("No activity recorded yet.").foregroundStyle(VaultlinePalette.muted)}}.padding(24).frame(maxWidth:760).frame(maxWidth:.infinity,alignment:.center)}}}
struct SettingsView:View{
    @Binding var appearance:String
    @Binding var clipboardClearSeconds:Int
    @Binding var showCards:Bool
    @Binding var showNotes:Bool
    @Binding var showIdentities:Bool
    var body:some View {
        Form {
            Section("Appearance") {
                Picker("Theme",selection:$appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
            }
            Section("Sidebar") {
                Toggle("Show payment cards",isOn:$showCards)
                Toggle("Show secure notes",isOn:$showNotes)
                Toggle("Show identities",isOn:$showIdentities)
            }
            Section("Clipboard protection") {
                Picker("Clear copied secrets after",selection:$clipboardClearSeconds) { Text("Never").tag(0); Text("30 seconds").tag(30); Text("45 seconds").tag(45); Text("60 seconds").tag(60); Text("2 minutes").tag(120) }
            }
            Section("Security information") {
                Text("Credentials are stored in macOS Keychain. Biometric approval uses Touch ID when available, with Mac password fallback. Vaultline has not received an independent security audit. Use sample data until you have completed local testing.").font(.caption).foregroundStyle(VaultlinePalette.muted)
            }
        }.padding(25).frame(maxWidth:700).frame(maxWidth:.infinity,alignment:.center)
    }
}

@main struct VaultlineApp: App {
    var body: some Scene { WindowGroup { ContentView().tint(VaultlinePalette.accent) } }
}
