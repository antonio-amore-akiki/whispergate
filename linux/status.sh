#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
require_config
echo "service=$(service_name)"
systemctl is-active "$(service_name).service" || true
tailscale serve status || true
curl -kfsS "https://localhost:$LISTEN_PORT/v1/health" || true
