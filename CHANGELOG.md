# Changelog

## 1.2.1 — Security session and authentication usability

- Reuses a successful macOS LocalAuthentication context for up to five minutes across desktop reveal/copy actions, avoiding a separate password prompt for every saved item.
- Explicitly invalidates the cached context and clears the desktop session when Vaultline is locked.
- Requires authentication again after five minutes or an explicit lock.
- Aligns desktop app, native helper, browser extension, and release metadata at 1.2.1.
- Adds static regression checks for authentication-session behavior and release version consistency.

## 1.2.0 — Password Generator Studio and actionable Security Center

- Added a standalone Password Generator Studio to the browser extension.
- Added configurable 12–64-character passwords with uppercase, lowercase, number, symbol, and ambiguous-character options.
- Added configurable 4–10-word passphrases with selectable separators.
- Generated values use the browser Web Crypto API with rejection sampling and a cryptographically secure shuffle; they are only placed into the login editor or clipboard after a user action.
- Added rough search-space estimates with an explicit note that estimates are not a security guarantee.
- Expanded Security Center results to identify affected login records and local findings (short password, reused password, or HTTP website) without returning password values.
- Added automated Node tests for generator options, passphrase settings, class coverage, and estimated search-space calculations.
- Bumped the desktop app, native helper, and browser extension version to 1.2.0.

## 1.0.0 — First open-source feature release

- Retained the extension-first architecture with macOS Keychain as the local source of truth.
- Added secure notes and personal identity records with create, view, edit, delete, search, tags, and favorites.
- Added tags and favorite support to payment cards and login records.
- Added a password-history view in the desktop app and extension; history is limited to five prior passwords per login.
- Added recently-used filtering in the desktop and extension interfaces.
- Added smart matching order for the active tab's exact hostname.
- Added an explicit save-login prompt for populated web login forms; saving requires the user to click the prompt.
- Added passphrase generation (12 random words) alongside password generation.
- Added user-approved payment card autofill for supported cardholder, number, expiration, and postal fields on HTTPS pages. CVV/CVC and PIN are never stored or filled.
- Added keyboard shortcuts and configurable save prompts.
- Added local password health checks and activity history; no remote breach lookup or telemetry is performed.
- Added encrypted backup/restore using AES-GCM with PBKDF2-SHA-256 key derivation.
- Added clipboard auto-clear preferences, light/dark/system appearance, and customizable sidebar sections.
- Added GitHub publishing guide, MIT license, issue templates, pull request template, release test plan, and contribution/security policies.
- Preserved the existing `com.vaultline.credentials.v2` Keychain service and compatible login/card record structure.

## 0.9.1 — Desktop visual refresh

- Replaced the default macOS brown/material appearance with the extension-matching navy, slate, and blue palette.
- Redesigned the desktop sidebar, search control, selected account rows, top bar, locked state, empty state, and status footer.
- Kept Keychain storage service and login/card data formats unchanged.

## 0.9.0

- Added payment-card records, masked card display, card reveal/copy, editing, deletion, and Luhn number validation.
- Added login editing and desktop payment-card management.
- CVV/CVC codes and PINs remain intentionally unsupported.

## 0.8.0

- Added selectable saved-login list to Vaultline Desktop.
- Added detail panel and password reveal/hide with macOS authentication.
- Added copy controls, login creation, and deletion confirmation.
- Preserved the existing Keychain service name and login record format.

## 1.0.0 Build Fix

- Split the desktop sidebar into smaller SwiftUI view components to avoid the Swift compiler's type-check timeout in the macOS 1.0.0 build.
- Corrected Swift `DispatchTime` expression spacing in clipboard auto-clear scheduling.
- No Keychain service names, record schemas, extension IDs, or storage formats were changed.

## 1.0.0 build polish

- Added the macOS app icon using the exact same artwork as the browser extension (`Extension/icons/icon128.png`).
- The macOS build script generates a standard `.icns` file and sets `CFBundleIconFile` in the app bundle.
- Static verification now checks that the shared icon source and macOS bundle integration are present.
