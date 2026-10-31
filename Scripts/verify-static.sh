#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "Node.js is required for JavaScript syntax checks."; exit 1; }
command -v swiftc >/dev/null 2>&1 || { echo "Swift compiler is required for Swift syntax checks."; exit 1; }
node --check "$ROOT/Extension/background.js"
node --check "$ROOT/Extension/manager.js"
node --check "$ROOT/Extension/content.js"
node "$ROOT/Tests/card-number-validation.test.js"
node "$ROOT/Tests/native-command-contract.test.js"
bash -n "$ROOT/Scripts/build-macos.sh"
bash -n "$ROOT/Scripts/install-native-host.sh"
swiftc -frontend -parse "$ROOT/NativeHost/main.swift"
swiftc -frontend -parse "$ROOT/App/Sources/Vaultline/main.swift"
python3 - "$ROOT" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import json, re, sys
root = Path(sys.argv[1])
manifest = json.loads((root / "Extension/manifest.json").read_text())
ext = root / "Extension"
class Parser(HTMLParser):
    def __init__(self):
        super().__init__(); self.ids=set(); self.resources=[]
    def handle_starttag(self, tag, attrs):
        values=dict(attrs)
        if "id" in values:
            if values["id"] in self.ids: raise SystemExit(f"Duplicate HTML id: {values['id']}")
            self.ids.add(values["id"])
        if tag == "script" and values.get("src"): self.resources.append(values["src"])
        if tag == "link" and values.get("href"): self.resources.append(values["href"])
p=Parser(); p.feed((ext / "manager.html").read_text())
js=(ext / "manager.js").read_text()
selectors=set(re.findall(r"\$\(['\"]#([\w-]+)['\"]\)", js))
missing=sorted(selectors-p.ids)
if missing: raise SystemExit("JS selectors missing in HTML: " + ", ".join(missing))
for resource in p.resources:
    if not (ext / resource).is_file(): raise SystemExit("Missing HTML resource: " + resource)
for path in [manifest["background"]["service_worker"], *manifest["icons"].values()]:
    if not (ext / path).is_file(): raise SystemExit("Missing manifest resource: " + path)
icon_source = ext / "icons/icon128.png"
build_script = (root / "Scripts/build-macos.sh").read_text()
if not icon_source.is_file(): raise SystemExit("Missing shared extension/app icon: " + str(icon_source))
if "iconutil -c icns" not in build_script or "CFBundleIconFile" not in build_script:
    raise SystemExit("macOS app icon generation or Info.plist integration is missing.")
print(f"Manifest, HTML IDs ({len(p.ids)}), UI selectors ({len(selectors)}), shared app icon, and referenced resources passed.")
PY
echo "Static verification passed. This does not replace a native macOS build or live Chrome/Keychain test."
