#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
require_config
unit="/etc/systemd/system/$(service_name).service"
"$SCRIPT_DIR/render-systemd.sh" | sudo tee "$unit" >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now "$(service_name).service"
echo "Installed $(service_name).service"
