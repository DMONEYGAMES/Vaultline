# Vaultline 1.0.0 release test plan

Use synthetic/test credentials only. Do not use real payment card details or important passwords during pre-release testing.

## Build and install

- [ ] `Scripts/verify-static.sh` passes.
- [ ] `Scripts/build-macos.sh` builds on macOS 13+.
- [ ] Chrome extension loads without errors.
- [ ] Native Messaging host installs and reconnects after browser restart.
- [ ] Extension `ping` displays desktop connection status.

## Vault records

- [ ] Add, view, reveal, copy, edit, favorite, tag, and delete a login.
- [ ] Save two different usernames for the same hostname; confirm both appear.
- [ ] Confirm a login is only offered on its exact hostname; test a lookalike hostname and a subdomain.
- [ ] Change a password and verify the prior password is placed in history.
- [ ] Add/edit/delete a secure note.
- [ ] Add/edit/delete a personal identity and test the supported form fields.
- [ ] Add/edit/delete a synthetic Luhn-valid test card; test masked/reveal/copy controls.
- [ ] Confirm CVV/CVC and PIN are never requested or stored.
- [ ] Test tags, favorites, search, recently used, and configurable sidebar.
- [ ] Confirm card tags survive reload, edit, backup, and restore.

## Browser behavior

- [ ] Smart login suggestions prioritize the exact matching host.
- [ ] Save-password prompt appears only after a password field is filled and requires a deliberate click to save.
- [ ] Login autofill is user-triggered and never submits the form.
- [ ] Card autofill works only on HTTPS and never fills a CVV field.
- [ ] Passphrase/password generators produce non-empty values.
- [ ] Keyboard shortcuts work and can be changed in browser shortcut settings.

## Security and recovery

- [ ] Locking the desktop invalidates the current authentication session.
- [ ] Canceling macOS authentication cancels the requested operation.
- [ ] Clipboard auto-clear does not clear unrelated clipboard content copied later by another app.
- [ ] Create an encrypted `.vaultline` backup with a strong unique passphrase.
- [ ] Restore the backup into a clean test vault and compare record counts and content.
- [ ] Wrong backup passphrase is rejected; damaged backup is rejected.
- [ ] Security Center weak/reused/HTTP counts match test data; UI clearly states no breach lookup is done.
- [ ] Activity history records expected operations without storing secret values.
- [ ] Inspect browser and native logs to ensure passwords/card numbers are not logged.

## Release gate

Do not describe Vaultline as production-ready or audited until these tests pass on supported Macs/browsers and an independent security review has been completed. Record platform versions, test dates, and failures in the release notes.
