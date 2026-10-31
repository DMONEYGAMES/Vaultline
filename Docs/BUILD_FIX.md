# Vaultline 1.0.0 Build Fix

This replacement package fixes two compile errors reported in the first 1.0.0 build:

1. The large sidebar `VStack` was split into smaller computed SwiftUI views so Swift can type-check it reliably.
2. The clipboard-clear timer now uses the valid `DispatchQueue` deadline expression `.now() + .seconds(delay)`.

The fixes do not intentionally alter the Keychain service name, credential record formats, or Native Messaging protocol.

## Install

1. Extract this complete ZIP into a new folder. Do not merge it into the previous `VD-1` folder.
2. In Terminal, `cd` into the extracted `Vaultline_Desktop_1.0.0_BuildFix` directory.
3. Run:

```bash
chmod +x Scripts/*.sh
./Scripts/verify-static.sh
./Scripts/build-macos.sh
open Build/Vaultline.app
```

4. Since the browser extension files and extension ID are unchanged when loading the same extension folder, keep the same unpacked extension folder if you did not change it. If you load the Extension folder from this new extracted project, Chrome will assign an extension ID; copy that ID to `Docs/extension_id.txt` and rerun `Scripts/install-native-host.sh`.
5. If the extension ID is unchanged, simply rebuild and restart Vaultline/Chrome. Do not delete Keychain records.

## Notes

The static verification script checks syntax, resource references, card validation, and the native command contract. It is not a full macOS SwiftUI compile or a live Chrome/Keychain test. The actual build must complete on a Mac before considering the release ready.
