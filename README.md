# Whispergate

Whispergate runs a private ntfy server behind Tailscale HTTPS.
It publishes source code only; cloning this repo never grants access to another operator's server.

## Quick start

For non-technical Windows setup, double-click:
```text
START-HERE-Windows.bat
```

Approve the Windows Administrator prompt. The guided setup installs Tailscale when Windows Package Manager is available, checks Tailscale sign-in, creates `config.json` when it is missing, installs the Automatic Windows service, verifies the Tailnet HTTPS route, and shows the phone URL.

The phone URL looks like `https://your-device.your-tailnet.ts.net`. Do not add `:8091`.

## Manual Windows setup

Create local config.
```powershell
Copy-Item .\config.example.json .\config.json
notepad .\config.json
```

Set `deploymentName`, `host`, `defaultUser`, and `instances`, then run the stable Windows setup.
Setup installs an Automatic Windows service so ntfy starts after reboot.
```powershell
.\scripts\setup.ps1
```

Check the installation.
```powershell
.\scripts\doctor.ps1
.\scripts\verify.ps1
```


## Tailscale setup

Whispergate assumes every operator uses their own Tailscale account and devices.
The guided Windows setup can install Tailscale, but each operator must still sign in to their own tailnet.

Windows server:
1. Install Tailscale for Windows: https://tailscale.com/docs/install
2. Sign in from the Tailscale tray app or run `tailscale up`.
3. Confirm the device is online.
```powershell
tailscale status --self
```
4. Confirm the machine has a MagicDNS name ending in `.ts.net`.
```powershell
tailscale status --self
```
5. Put that full MagicDNS name in `config.json` as `host`.

Phone or client:
1. Install Tailscale on the phone from the official app store.
2. Sign in to the same tailnet.
3. Use the server URL from `config.json`, for example `https://your-device.your-tailnet.ts.net`.
4. Do not add `:8091` on the phone URL.

Serve requirements:
- Tailscale Serve needs HTTPS enabled in the tailnet.
- If Serve asks for approval, follow the Tailscale admin link it prints.
- Whispergate configures Tailnet-only Serve with `scripts\enable-tailnet-only.ps1`.
- Serve command reference: https://tailscale.com/kb/1242/tailscale-serve
- Serve overview: https://tailscale.com/docs/features/tailscale-serve

## Core commands

| Command | Purpose |
| --- | --- |
| `START-HERE-Windows.bat` | Guided Windows setup for non-technical operators. |
| `scripts\doctor.ps1` | Diagnose config, Tailscale, exposure, service, health, and topics. |
| `scripts\setup.ps1` | Bootstrap, enable Tailnet-only Serve, install the Automatic Windows service, and verify. |
| `scripts\exposure-status.ps1` | Show whether Tailscale is Tailnet-only, Funnel, or missing. |
| `scripts\disable-funnel.ps1` | Turn off public Funnel and restore Tailnet-only Serve. |
| `scripts\update.ps1 -DryRun` | Preview update steps without changing local runtime. |
| `scripts\build-release.ps1` | Build a source zip and SHA256 checksum from tracked files. |

## Doctor

Human output:
```powershell
.\scripts\doctor.ps1
```

Machine output:
```powershell
.\scripts\doctor.ps1 -Json
```

JSON includes `status`, `checks`, `exposure`, `service`, `topics`, and `fixes`.
Doctor fails when the Windows service is missing, stopped, or not set to Automatic startup.

## Exposure

Default production use is Tailnet-only Tailscale Serve.
Clients use the Tailscale HTTPS URL without port `8091`.

Enable Tailnet-only Serve.
```powershell
.\scripts\enable-tailnet-only.ps1
```

Disable public Funnel.
```powershell
.\scripts\disable-funnel.ps1
```

Public Funnel is opt-in only.
```powershell
.\scripts\enable-funnel.ps1 -IUnderstandThisPublishesToInternet
```

## Update

Preview update actions.
```powershell
.\scripts\update.ps1 -DryRun
```

Apply update from the current git remote, restart service, and verify.
```powershell
.\scripts\update.ps1
```

## Reset and uninstall

Setup refuses existing runtime unless reset is explicit.
```powershell
.\scripts\reset-runtime.ps1 -ConfirmReset
.\scripts\uninstall-service.ps1
```

## Linux beta

Linux support is beta until verified on a real Tailscale Linux host.
```bash
cp config.example.json config.json
linux/bootstrap.sh
linux/render-systemd.sh
linux/install-systemd.sh
linux/status.sh
linux/verify.sh
```

## Release package

CI builds a source zip and checksum from tracked files only.
Tag pushes create release artifacts after safety checks pass.
No package includes `config.json`, `runtime`, certs, keys, auth DBs, logs, or credentials.

## Troubleshooting

Run doctor first.
```powershell
.\scripts\doctor.ps1
```

If health fails, restart service and verify.
```powershell
.\scripts\restart-service.ps1
.\scripts\verify.ps1
```

If clients cannot connect, check exposure.
```powershell
.\scripts\exposure-status.ps1
```
