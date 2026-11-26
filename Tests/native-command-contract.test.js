'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const native = fs.readFileSync(path.join(root, 'NativeHost/main.swift'), 'utf8');
const background = fs.readFileSync(path.join(root, 'Extension/background.js'), 'utf8');
const desktop = fs.readFileSync(path.join(root, 'App/Sources/Vaultline/main.swift'), 'utf8');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'Extension/manifest.json'), 'utf8'));
const buildScript = fs.readFileSync(path.join(root, 'Scripts/build-macos.sh'), 'utf8');
const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
const required = [
  'listLogins','saveLogin','getLogin','deleteLogin',
  'listCards','saveCard','getCard','deleteCard',
  'listNotes','saveNote','getNote','deleteNote',
  'listIdentities','saveIdentity','getIdentity','deleteIdentity',
  'listActivity','securityAudit','exportVault','importVault'
];
const authStart = native.indexOf('let reason: String');
const authEnd = native.indexOf('guard session.ensureAuthenticated', authStart);
if (authStart < 0 || authEnd < 0) throw new Error('Could not locate native authentication gate.');
const authBlock = native.slice(authStart, authEnd);
for (const command of required) {
  if (!authBlock.includes(`case "${command}"`)) throw new Error(`Native command is not behind the authentication gate: ${command}`);
  if (!background.includes(`'${command}'`)) throw new Error(`Extension background allow-list is missing: ${command}`);
  if (!native.includes(`case "${command}"`)) throw new Error(`Native command implementation is missing: ${command}`);
}
if (!native.includes('kSecMatchLimit as String: kSecMatchLimitOne')) throw new Error('Expected single-item Keychain data reads were not found.');
if (!native.includes('com.vaultline.credentials.v2')) throw new Error('Existing Keychain service identifier changed unexpectedly.');
if (!native.includes('let findings: [[String: Any]] = records.compactMap')) throw new Error('Security audit findings are missing.');
if (!native.includes('"issues": issues')) throw new Error('Security audit issue metadata is missing.');
if (!native.includes('"version": "1.2.0"')) throw new Error('Native helper version was not updated.');
if (!native.includes('"version": "1.2.1"')) throw new Error('Native helper version is not 1.2.1.');
if (manifest.version !== '1.2.1') throw new Error('Extension version is not 1.2.1.');
if (!buildScript.includes('<key>CFBundleShortVersionString</key><string>1.2.1</string>')) throw new Error('Desktop version is not 1.2.1.');
if (!readme.includes('version-1.2.1-')) throw new Error('README version badge is not 1.2.1.');
if (!desktop.includes('private let desktopSessionLifetime: TimeInterval = 5 * 60') ||
    !desktop.includes('private var authenticationContext: LAContext?') ||
    !desktop.includes('self.authenticatedUntil = Date().addingTimeInterval(desktopSessionLifetime)')) {
  throw new Error('Desktop five-minute authentication cache is missing.');
}
const lockStart = desktop.indexOf('    func lock() {');
const lockEnd = desktop.indexOf('    }', lockStart);
const lockBlock = desktop.slice(lockStart, lockEnd);
if (!lockBlock.includes('authenticationContext?.invalidate()') ||
    !lockBlock.includes('authenticatedUntil = .distantPast')) {
  throw new Error('Desktop lock does not invalidate the cached authentication context.');
}
process.stdout.write(`Native command contract passed (${required.length} authenticated commands).\n`);
