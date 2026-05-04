#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_ROOT="$REPO_ROOT/runtime"
BIN_ROOT="$RUNTIME_ROOT/bin"
CONFIG_ROOT="$RUNTIME_ROOT/config"
AUTH_ROOT="$RUNTIME_ROOT/auth"
CACHE_ROOT="$RUNTIME_ROOT/cache"
CERT_ROOT="$RUNTIME_ROOT/certs"
ATTACH_ROOT="$RUNTIME_ROOT/attachments"
LOG_ROOT="$RUNTIME_ROOT/logs"
CONFIG_FILE="$REPO_ROOT/config.json"
LISTEN_PORT=8091

json_get() {
  python3 - "$CONFIG_FILE" "$1" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
value = data
for part in key.split('.'):
    value = value[part]
print(value)
PY
}

require_config() {
  test -f "$CONFIG_FILE" || { echo 'Missing config.json' >&2; exit 1; }
  local host deployment
  host="$(json_get host)"
  deployment="$(json_get deploymentName)"
  [[ "$host" == *.ts.net ]] || { echo 'host must end with .ts.net' >&2; exit 1; }
  [[ "$deployment" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || { echo 'bad deploymentName' >&2; exit 1; }
}

ntfy_version() { json_get ntfyVersion; }
deployment_name() { json_get deploymentName; }
tailscale_host() { json_get host; }
default_operator() { json_get defaultUser; }
service_name() { echo "whispergate-$(deployment_name)"; }
serve_target() { echo "https+insecure://localhost:$LISTEN_PORT"; }
server_config() { echo "$CONFIG_ROOT/main.server.yml"; }
credential_file() { echo "$AUTH_ROOT/operator-credentials.txt"; }
ntfy_exe() { echo "$BIN_ROOT/ntfy_$(ntfy_version)_linux_amd64/ntfy"; }
