# Vaultline macOS App Icon

Vaultline Desktop uses the exact same icon artwork as the browser extension: `Extension/icons/icon128.png`.

When you build on macOS, `Scripts/build-macos.sh` uses `sips` to generate the standard iconset sizes and `iconutil` to create `Build/Vaultline.app/Contents/Resources/Vaultline.icns`. The app's `Info.plist` references `Vaultline.icns` via `CFBundleIconFile`.

No extra install step is required. Rebuild the app after pulling this source update. macOS may cache icons briefly; quit the app and Finder/Dock may need a refresh or sign-out/restart before every location displays the new icon.
