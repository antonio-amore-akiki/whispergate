#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
unit="$(service_name).service"
sudo systemctl disable --now "$unit" || true
sudo rm -f "/etc/systemd/system/$unit"
sudo systemctl daemon-reload
echo "Uninstalled $unit"
