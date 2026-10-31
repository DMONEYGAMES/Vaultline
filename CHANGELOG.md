# Changelog

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
