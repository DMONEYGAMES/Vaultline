# Security policy

Vaultline 1.0.0 is an early open-source release candidate. It has not received an independent security audit and should be tested with disposable credentials until a qualified reviewer has inspected the implementation.

## Reporting a vulnerability

Please do not publish passwords, card data, Keychain exports, backup files, tokens, exploit details, or personal information in public issues. The repository owner should enable GitHub's **private vulnerability reporting** in repository Settings → Security before inviting sensitive reports. Until this is enabled and confirmed, do not submit sensitive details through public GitHub issues.

## Security design notes

- Credential records are stored locally in macOS Keychain. There is no cloud sync in this release.
- Native Messaging requests pass through an allow-list and macOS LocalAuthentication gate. A short authenticated session is cached; users can lock the vault to end it.
- Login retrieval checks exact normalized hostnames. Autofill is user-initiated and does not submit forms.
- Card autofill is limited to HTTPS and supported fields; CVV/CVC and PIN are never stored or filled.
- The optional save-password prompt content script runs on HTTP/HTTPS pages because it detects populated login forms. It only sends a detected record after the user explicitly clicks the save prompt.
- Encrypted backup uses AES-GCM with a passphrase-derived key. Losing the backup passphrase makes the backup unrecoverable.
- Clipboard clearing is best-effort; it only clears the clipboard if the value still matches what Vaultline copied.

## Safe testing

- Use disposable logins and synthetic payment-card test numbers.
- Never upload `.vaultline`, CSV exports, Keychain data, real credentials, or screenshots containing revealed secrets.
- Treat static validation as a code sanity check, not a security audit or runtime proof.
- Report any suspected issue privately using the repository's configured security advisory/reporting feature once enabled.
