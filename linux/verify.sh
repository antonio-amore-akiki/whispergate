#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
require_config
host="$(tailscale_host)"
curl -fsS "https://$host/v1/health" | grep -q 'healthy'
tailscale serve status | grep -q "$(serve_target)"
echo 'Linux beta verification passed.'
