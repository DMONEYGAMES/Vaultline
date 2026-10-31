# Vaultline 1.0.0 — Build & installation

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)
- Chrome 114+ or Microsoft Edge
- Node.js and Python 3 for validation/setup scripts

## Build the Mac app and native helper

```bash
cd /path/to/Vaultline-1.0.0
chmod +x Scripts/*.sh
./Scripts/verify-static.sh
./Scripts/build-macos.sh
open Build/Vaultline.app
```

## Install the browser extension

1. Open `chrome://extensions` or `edge://extensions`.
2. Turn on Developer mode.
3. Choose **Load unpacked** and select this project's `Extension` folder.
4. Copy the extension ID to `Docs/extension_id.txt` (Chrome) or `Docs/edge_extension_id.txt` (Edge).
5. Run `./Scripts/install-native-host.sh`.
6. Quit and reopen the browser completely.

The native helper is launched by Chrome/Edge through Native Messaging when the extension sends a request. The desktop window does not have to stay open, but the Mac must be unlocked for Keychain access.

## Security and test notes

- All credential records are stored in the macOS Keychain using the existing `com.vaultline.credentials.v2` service so compatible earlier records can remain available.
- Touch ID is used through macOS LocalAuthentication when available; the Mac account password is the fallback.
- The extension list receives metadata; full secrets are requested only for a selected/reveal/copy/fill action and require native authentication.
- Login autofill requires exact normalized hostname matching and an explicit user action. It does not submit forms.
- Card autofill is restricted to HTTPS and supported card fields. CVV/CVC and PIN values are not stored or filled.
- The form-save helper runs on HTTP/HTTPS pages, but only saves when the user explicitly clicks its prompt.
- The encrypted backup file requires a passphrase of at least 12 characters and is currently limited to a 600 KiB plaintext vault payload due to the Native Messaging message-size cap. Losing the passphrase means losing access to that backup.
- Clipboard-read permission is used only to check whether the clipboard still contains the text Vaultline copied before clearing it on a timer.
- TOTP-based second-factor unlock and cloud/account sharing are not included in 1.0.0.
- Static checks are not a live macOS/browser test or independent security audit. Start with sample data and follow `RELEASE_TEST_PLAN.md`.

## Build fix note

If you downloaded the original 1.0.0 package and saw a Swift compiler error in the sidebar or clipboard timer, use the separate **1.0.0 Build Fix** package. See `Docs/BUILD_FIX.md` in that package.
