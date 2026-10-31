'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const native = fs.readFileSync(path.join(root, 'NativeHost/main.swift'), 'utf8');
const background = fs.readFileSync(path.join(root, 'Extension/background.js'), 'utf8');
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
process.stdout.write(`Native command contract passed (${required.length} authenticated commands).\n`);
