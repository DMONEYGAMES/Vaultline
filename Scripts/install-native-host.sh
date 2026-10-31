#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST_SOURCE="$ROOT/Build/vaultline-native-host"
[[ -x "$HOST_SOURCE" ]] || { echo "Run Scripts/build-macos.sh first."; exit 1; }
CHROME_ID="$(tr -d '\r\n ' < "$ROOT/Docs/extension_id.txt")"
[[ "$CHROME_ID" =~ ^[a-p]{32}$ ]] || { echo "Set Docs/extension_id.txt to the 32-character Chrome extension ID first."; exit 1; }

INSTALL_DIR="$HOME/Library/Application Support/Vaultline"
mkdir -p "$INSTALL_DIR"
HOST_PATH="$INSTALL_DIR/vaultline-native-host"
cp "$HOST_SOURCE" "$HOST_PATH"
chmod 755 "$HOST_PATH"

python3 - "$HOST_PATH" "$CHROME_ID" "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts" <<'PY'
import json, os, pathlib, sys
host_path, extension_id, folder = sys.argv[1:]
root = pathlib.Path(folder)
root.mkdir(parents=True, exist_ok=True)
manifest = {
  "name": "com.vaultline.bridge",
  "description": "Vaultline Desktop credential bridge",
  "path": host_path,
  "type": "stdio",
  "allowed_origins": [f"chrome-extension://{extension_id}/"]
}
(root / "com.vaultline.bridge.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY

EDGE_ID="$(tr -d '\r\n ' < "$ROOT/Docs/edge_extension_id.txt" 2>/dev/null || true)"
if [[ -n "$EDGE_ID" && "$EDGE_ID" =~ ^[a-p]{32}$ ]]; then
  python3 - "$HOST_PATH" "$EDGE_ID" "$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts" <<'PY'
import json, pathlib, sys
host_path, extension_id, folder = sys.argv[1:]
root = pathlib.Path(folder)
root.mkdir(parents=True, exist_ok=True)
manifest = {"name":"com.vaultline.bridge","description":"Vaultline Desktop credential bridge","path":host_path,"type":"stdio","allowed_origins":[f"chrome-extension://{extension_id}/"]}
(root / "com.vaultline.bridge.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY
  echo "Installed Native Messaging host for Chrome and Edge."
else
  echo "Installed Native Messaging host for Chrome. Add the Edge extension ID to Docs/edge_extension_id.txt and rerun to enable Edge."
fi

echo "Host executable: $HOST_PATH"
echo "Quit Chrome completely with Cmd+Q, then reopen it."
