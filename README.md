# ntfy Marmoura

Reusable local HTTPS ntfy deployment for three Marmoura notification profiles.

## Features

- Downloads pinned official `ntfy` for Windows.
- Generates local HTTPS configs for `main`, `a`, and `b`.
- Generates local auth, cache, logs, and certificate files under `runtime`.
- Verifies health, allowed publish, blocked unknown-topic publish, and HTTP rejection.
- Keeps Tailscale or custom hostnames optional through `config.json`.

## Commands

Bootstrap a fresh local runtime.
```powershell
.\scripts\bootstrap.ps1
```

Start local ntfy servers.
```powershell
.\scripts\start.ps1
```

Verify local health and publish behavior.
```powershell
.\scripts\verify.ps1
```

Stop local ntfy servers.
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

Edit a local copy when defaults need changes.
```powershell
Copy-Item .\config.example.json .\config.json
```

Set `host` to a Tailscale or custom DNS name only when that name resolves locally.
