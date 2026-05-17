#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
require_config
mkdir -p "$BIN_ROOT" "$CONFIG_ROOT" "$AUTH_ROOT" "$CACHE_ROOT/main" "$CERT_ROOT" "$ATTACH_ROOT/main" "$LOG_ROOT"
version="$(ntfy_version)"
archive="ntfy_${version}_linux_amd64.tar.gz"
release="https://github.com/binwiederhier/ntfy/releases/download/v${version}"
mkdir -p "$RUNTIME_ROOT/downloads"
curl -fsSL "$release/$archive" -o "$RUNTIME_ROOT/downloads/$archive"
curl -fsSL "$release/checksums.txt" -o "$RUNTIME_ROOT/downloads/checksums.txt"
expected="$(grep " $archive" "$RUNTIME_ROOT/downloads/checksums.txt" | awk '{print $1}')"
actual="$(sha256sum "$RUNTIME_ROOT/downloads/$archive" | awk '{print $1}')"
[ "$expected" = "$actual" ] || { echo 'checksum mismatch' >&2; exit 1; }
tar -xzf "$RUNTIME_ROOT/downloads/$archive" -C "$BIN_ROOT"
host="$(tailscale_host)"
cert="$CERT_ROOT/$host.crt"
key="$CERT_ROOT/$host.key"
if [ ! -f "$cert" ] || [ ! -f "$key" ]; then
  tailscale cert --cert-file="$cert" --key-file="$key" "$host"
fi
cat > "$(server_config)" <<YAML
base-url: "https://$host"
upstream-base-url: "$(json_get upstreamBaseUrl)"
listen-http: ""
listen-https: ":$LISTEN_PORT"
cert-file: "$cert"
key-file: "$key"
cache-file: "$CACHE_ROOT/main/cache.db"
attachment-cache-dir: "$ATTACH_ROOT/main"
auth-file: "$AUTH_ROOT/auth.db"
auth-default-access: "deny-all"
enable-login: true
behind-proxy: false
YAML
if [ ! -f "$AUTH_ROOT/auth.db" ]; then
  operator_value="$(python3 - <<'PY'
import base64, os
print(base64.b64encode(os.urandom(24)).decode())
PY
)"
  credential_path="$(credential_file)"
  umask 077
  printf 'user=%s\npassword=%s\n' "$(default_operator)" "$operator_value" > "$credential_path"
  chmod 600 "$credential_path"
  NTFY_PASSWORD=$operator_value "$(ntfy_exe)" user --config "$(server_config)" add "$(default_operator)"
fi
echo 'Bootstrapped Whispergate Linux beta runtime.'
