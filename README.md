# Whispergate

Whispergate is a Windows-first setup for running a private ntfy server behind Tailscale HTTPS.
It publishes source code only. Cloning this repo never grants access to another operator's server.

## Features

- Downloads a pinned official ntfy release for Windows.
- Verifies the ntfy release checksum before extraction.
- Generates local runtime config, certs, auth, cache, logs, and attachments under ignored runtime state.
- Uses Tailscale MagicDNS and HTTPS so devices use a no-port URL.
- Installs ntfy as an automatic Windows service named from deploymentName.
- Verifies health, publish, authenticated receive, WebSocket subscribe, unknown-topic denial, and HTTP rejection.

## Quick start

Create local config.
```powershell
Copy-Item .\config.example.json .\config.json
notepad .\config.json
```

Set these fields before bootstrapping:
- deploymentName: lowercase service prefix, for example marmoura.
- host: this machine's Tailscale DNS name ending in .ts.net.
- defaultUser: local ntfy operator account to create.
- instances: topic names to serve.

Bootstrap runtime state.
```powershell
.\scripts\bootstrap.ps1
```

Start ntfy without installing a service.
```powershell
.\scripts\start.ps1
```

Verify readiness.
```powershell
.\scripts\verify.ps1
```

Install automatic Windows service from elevated PowerShell.
```powershell
.\scripts\install-service.ps1
```

Restart service from elevated PowerShell.
```powershell
.\scripts\restart-service.ps1
```

Uninstall service from elevated PowerShell.
```powershell
.\scripts\uninstall-service.ps1
```

Stop local ntfy processes.
```powershell
.\scripts\stop.ps1
```

Run public-source safety checks before publishing.
```powershell
.\scripts\check-public-safety.ps1
```

## Tailscale exposure

Default production use is Tailnet-only Tailscale Serve.
The phone or client server URL should be the Tailscale HTTPS URL without port 8091.

Example Serve command:
```powershell
tailscale serve --bg https+insecure://localhost:8091
```

Funnel publishes the same URL to the public internet. Use Funnel only when public access is intended.
Check exposure before sharing URLs.
```powershell
tailscale serve status
```

## Authentication

ntfy authentication is enabled and default access is deny-all.
The bootstrap command creates runtime/auth/operator-credentials.txt for the configured defaultUser.
Subscribers need that ntfy username and password to read protected topics.
Anonymous access is controlled by anonymousPermission in config.json.

## Public repository safety

Do not commit config.json, runtime, certs, keys, auth databases, logs, operator credentials, or local legacy scripts.
The repository CI runs the public-source safety check on Windows.
