#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
require_config
cat <<UNIT
[Unit]
Description=Whispergate ntfy $(deployment_name)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$(ntfy_exe) serve --config $(server_config)
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
