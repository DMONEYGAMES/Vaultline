# Vaultline 1.0.0

**Vaultline only works on Mac right now; we will expand to Windows soon.**

**Your Mac is the vault. Your browser extension is the interface.**

Vaultline is an early-stage, local-first password manager for macOS with a Chrome/Edge extension. The extension is the day-to-day interface; the native macOS helper validates requests and stores records in the macOS Keychain.

> **Security status:** This is a first public-source milestone, not an independently audited password manager. Static checks are not a substitute for live macOS, Keychain, browser, and security testing. Use disposable sample data until you have completed the test plan and obtained an independent security review. Do not use Vaultline as your only protection for important accounts yet.

## Features in this build

- **Logins:** save, edit, delete, search, categories, favorites, tags, password generator, 12-word passphrase generator, five-entry password history, recently-used filtering, and exact-host matching for autofill.
- **Cards:** add, edit, delete, favorite, tag, reveal/copy, Luhn format validation, and user-approved autofill of supported cardholder/number/expiry/postal fields on HTTPS pages. CVV/CVC and card PINs are not collected, stored, or filled.
- **Secure notes:** create, edit, search, favorite, tag, and delete notes stored in Keychain.
- **Personal identities:** store profile details and use supported fields in a user-approved form-fill action.
- **Security Center:** local checks for short/reused passwords and HTTP website entries. No remote breach lookup is performed; the score is not a guarantee that an account is safe.
- **Authentication:** macOS LocalAuthentication uses Touch ID when available, with Mac password fallback. The native bridge caches successful authentication for a short session (currently five minutes); Lock ends the session.
- **Clipboard protection:** optional delayed clipboard clearing, only when the clipboard still contains the value Vaultline copied.
- **Encrypted backup:** extension encrypts a complete export with AES-256-GCM using a passphrase-derived PBKDF2-SHA-256 key (600,000 iterations). Keep the passphrase safe; Vaultline cannot recover it.
- **Activity history:** local audit events for supported vault actions. Event details intentionally avoid recording secret values.
- **Themes/settings:** light, dark, and system appearance; configurable sidebar sections; save-login prompt and clipboard preferences.
- **Keyboard shortcuts:** open the vault and request a save prompt; in-app shortcuts for search and creating an item.

## Deliberate 1.0.0 limits

- This release does not provide cloud sync, user accounts, or account-to-account password sharing. Records remain on the Mac.
- Touch ID / Mac password approval is device-owner authentication; a separate TOTP factor for unlocking the Vaultline vault is not included in 1.0.0.
- The Security Center performs local length/reuse/HTTP checks only. It does not query breach databases or guarantee that a password has not been exposed.
- No independent security audit has been completed. Public source access is not proof that the software is production-ready.

## Architecture

```text
Chrome / Edge extension (UI)
          |
          | Chrome Native Messaging (JSON, length-prefixed)
          v
Vaultline native helper (macOS)
          |
          | LocalAuthentication + Security.framework
          v
macOS Keychain (credential records)
```

The desktop app is a native vault viewer/editor and authentication surface. The native helper is launched by the browser through Native Messaging; the desktop window does not have to remain open for extension requests. The extension holds UI preferences in `chrome.storage.local`, but credential records remain in the Mac Keychain.

The save-password detection content script runs on HTTP and HTTPS pages so it can detect a filled login form. It shows a prompt; it only sends a captured login to the native helper after the user explicitly clicks **Save to Mac**. This is broad website access and should be reviewed carefully before distributing the extension.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools / Swift compiler
- Chrome 114+ or a compatible Chromium browser such as Microsoft Edge
- Node.js and Python 3 for static checks and installation scripts

## App icon

The macOS app uses the same artwork as the browser extension (`Extension/icons/icon128.png`). The build script creates `Vaultline.icns` and installs it into the `.app` bundle automatically.

## Build and install on macOS

1. Extract this repository to a stable folder (for example `~/Applications/Vaultline-1.0.0`).
2. In Terminal, run:

   ```bash
   cd ~/Applications/Vaultline-1.0.0
   chmod +x Scripts/*.sh
   ./Scripts/verify-static.sh
   ./Scripts/build-macos.sh
   open Build/Vaultline.app
   ```

3. In Chrome, open `chrome://extensions`; in Edge, open `edge://extensions`.
4. Enable Developer mode and choose **Load unpacked**.
5. Select this repository's `Extension` folder.
6. Copy the extension ID into `Docs/extension_id.txt` (Chrome) or `Docs/edge_extension_id.txt` (Edge).
7. Run `./Scripts/install-native-host.sh`.
8. Fully quit and restart the browser.
9. Test save, list, reveal, edit, delete, backup/restore, and autofill with disposable accounts and synthetic card data.

Do not delete older Vaultline folders or Keychain data until you have confirmed the new build can still read your existing records and that you have a valid encrypted backup.

## Tests and verification

```bash
./Scripts/verify-static.sh
```

This checks JavaScript syntax, HTML selectors/resources, the extension manifest, card-number validation examples, native command allow-list coverage, shell syntax, and Swift parsing. It **does not** compile the native app against the macOS SDK, execute Keychain operations, verify Touch ID, exercise Chrome Native Messaging, or prove autofill works on real websites. Those require live testing on a Mac.

See `Docs/RELEASE_TEST_PLAN.md` before using real credentials. See `Docs/GITHUB_PUBLISHING.md` for repository setup and publishing steps. The extension requests clipboard-read permission so it can compare clipboard contents before its optional clear timer; this is used to avoid deleting a different value copied by another application.

## Open source

Vaultline is released under the MIT License. Contributions are welcome through issues and pull requests. Security-sensitive changes must be carefully reviewed; see `CONTRIBUTING.md` and `SECURITY.md`.
