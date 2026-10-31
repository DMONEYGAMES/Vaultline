# Contributing to Vaultline

Thanks for considering a contribution! Vaultline is an early-stage, local-first password manager. Its source is published under the MIT License, and community contributions are welcome through issues and pull requests.

## Before you start

- Open an issue for a bug or substantial feature idea before doing major work.
- Use a fork or feature branch; do not work directly on `main`.
- Never include real passwords, card numbers, Keychain exports, `.vaultline` backups, plaintext CSV exports, extension IDs tied to a personal development install, tokens, certificates, or private keys.
- Keep changes focused and describe how they affect privacy and security.
- Do not add telemetry, remote password transmission, automatic form submission, or broader website access without explicit design review.

## Development checks

```bash
chmod +x Scripts/*.sh
./Scripts/verify-static.sh
```

On macOS, also build the native app:

```bash
./Scripts/build-macos.sh
```

Test with disposable accounts and synthetic card numbers. The static checker does not replace runtime tests on macOS and Chrome/Edge.

## Security-sensitive changes

Changes to Keychain access, LocalAuthentication, encryption, backup format, native messaging, website matching, content scripts, card handling, or autofill require extra review. Explain the threat model and failure cases in the pull request. Do not include secrets or sensitive reproduction data.

## Pull request checklist

- [ ] Describe the problem and the intended change.
- [ ] Include the commands and platforms used to test it.
- [ ] Add/update tests where possible.
- [ ] Explain any security/privacy impact.
- [ ] Include UI screenshots only with synthetic sample data.
- [ ] Confirm no credentials, backups, local IDs, keys, or personal information are staged.

A maintainer must review and approve changes before merging. The MIT License permits reuse under its conditions; it does not mean unreviewed code should be trusted with credentials.
