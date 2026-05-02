# ntfy Marmoura

Tailscale-first HTTPS ntfy deployment for Marmoura notification topics.

## Features

- Downloads pinned official `ntfy` for Windows.
- Requires Tailscale CLI, healthy Tailscale status, and MagicDNS resolution.
- Uses `tailscale cert` for the configured Tailscale hostname.
- Uses `ntfy.sh` upstream push wake-up for mobile delivery.
- Generates auth, cache, logs, and runtime configs under ignored `runtime`.
- Runs one Tailscale HTTPS server on port `8091`.
- Verifies Tailscale health, allowed publish, server receive, unknown-topic denial, and HTTP rejection.

## Commands

Create and edit local config.
```powershell
Copy-Item .\config.example.json .\config.json
```

Bootstrap the Tailscale runtime.
```powershell
.\scripts\bootstrap.ps1
```

Start ntfy servers.
```powershell
.\scripts\start.ps1
```

Verify Tailscale production readiness.
```powershell
.\scripts\verify.ps1
```
This proves server receive, not phone notification delivery.

Stop ntfy servers.
```powershell
.\scripts\stop.ps1
```

Install optional Windows services from elevated PowerShell.
```powershell
.\scripts\install-service.ps1
```

Restart optional Windows services from elevated PowerShell.
```powershell
.\scripts\restart-service.ps1
```

## Configuration

Set `host` in `config.json` to the Tailscale DNS name of this machine.

Use port `8091` for all topics.

Localhost is not a production readiness target.
