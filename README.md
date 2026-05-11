# Whispergate

Private ntfy notifications for phones, laptops, and agent workflows.

Whispergate turns local ntfy into an operator-owned notification gateway:

```text
phone or agent -> Tailscale HTTPS -> local ntfy on 127.0.0.1:8091
```

The local port stays local. The phone uses the Tailscale HTTPS name.
Windows owns startup, restart recovery, and health checks.

## What you get

- A one-shot Windows setup EXE for guided install or repair.
- An Automatic Windows service for the ntfy backend.
- Tailnet-only Tailscale Serve by default; Funnel is opt-in only.
- No phone-side port typing; do not add `:8091`.
- Operator password storage in Windows Credential Manager.
- Doctor and verify scripts for health, publish, receive, websocket, service, and exposure checks.
- Linux systemd scripts in a beta lane.

Codex notify has two autonomy owners.
Whispergate owns ntfy through the Windows service.
Codex owns its hidden supervisor plus daemon through login startup.
Forced sends prove routing; a real Codex completion remains the final live-run gate.

## Quick start for Windows

Download the latest release and run:

```text
WhispergateSetup.exe
```

v1 is unsigned. Windows SmartScreen may warn before the wizard opens.

The wizard checks Windows, Tailscale, MagicDNS, admin status, config, setup, doctor, and verify.
It asks for UAC only when service or Tailscale setup needs elevation.
It shows the server URL, username, topics, and Credential Manager target for the phone password.

Use this URL shape in the ntfy phone app:

```text
https://your-device.your-tailnet.ts.net
```

Do not add `:8091` on the phone.

## Source ZIP fallback

If you downloaded the source ZIP instead of the EXE, unzip it and double-click:

```text
START-HERE-Windows.bat
```

Approve the Windows Administrator prompt. The script path uses the same setup authority as the EXE.

## Manual setup

```powershell
Copy-Item .\config.example.json .\config.json
notepad .\config.json
.\scripts\setup.ps1
.\scripts\doctor.ps1
.\scripts\verify.ps1
```

Set `deploymentName`, `host`, `defaultUser`, and `instances` in `config.json` before setup.

## Tailscale setup

Whispergate uses your own Tailscale account and your own tailnet.

Server laptop:
1. Install Tailscale for Windows: https://tailscale.com/docs/install
2. Sign in from the tray app or run `tailscale up`.
3. Confirm the device is online.

```powershell
tailscale status --self
```

4. Copy the MagicDNS name ending in `.ts.net` into `config.json` as `host`.

Phone:
1. Install Tailscale from the official app store.
2. Sign in to the same tailnet.
3. Add the server URL printed by setup.
4. Leave port `8091` off the phone URL.

Serve requirements:
- Tailscale Serve needs HTTPS enabled in the tailnet.
- If Tailscale asks for approval, follow the admin link it prints.
- Tailnet-only Serve is enabled by `scripts\enable-tailnet-only.ps1`.
- Tailscale Serve docs: https://tailscale.com/kb/1242/tailscale-serve

## Operator commands

| Command | Result |
| --- | --- |
| `WhispergateSetup.exe` | Guided Windows setup, repair, check, and phone instructions. |
| `START-HERE-Windows.bat` | Source ZIP guided setup fallback. |
| `scripts\doctor.ps1` | Full diagnostic report with fix hints. |
| `scripts\doctor.ps1 -Json` | Machine-readable diagnostics. |
| `scripts\verify.ps1` | Health, publish, receive, and websocket checks. |
| `scripts\exposure-status.ps1` | Show Tailnet-only, Funnel, or missing exposure. |
| `scripts\disable-funnel.ps1` | Turn public Funnel off. |
| `scripts\rotate-operator-credential.ps1` | Rotate the Credential Manager password. |
| `scripts\build-release.ps1` | Build EXE, source ZIP, and SHA256 checksums. |

## Setup EXE flags

```powershell
.\WhispergateSetup.exe --check-only
.\WhispergateSetup.exe --log-path C:\Temp\whispergate-setup.log
.\WhispergateSetup.exe --payload-dir C:\Path\To\whispergate
```

`--check-only` reports preflight status without changing the machine. `--payload-dir` is for developer debugging.

## Exposure model

Default: Tailnet-only.

Public Funnel is not enabled by setup or update. Turning it on requires the explicit confirmation flag:

```powershell
.\scripts\enable-funnel.ps1 -IUnderstandThisPublishesToInternet
```

Turn Funnel off and restore private Serve:

```powershell
.\scripts\disable-funnel.ps1
```

## Update, reset, uninstall

```powershell
.\scripts\update.ps1 -DryRun
.\scripts\update.ps1
.\scripts\reset-runtime.ps1 -ConfirmReset
.\scripts\uninstall-service.ps1
```

Setup refuses to overwrite existing runtime config, auth DBs, certs, or keys unless reset is explicit.
Operator auth is owned by Windows Credential Manager.
Rotate it with `scripts\rotate-operator-credential.ps1`.

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

## Release safety

GitHub releases distribute `WhispergateSetup.exe`, the source ZIP, and SHA256 checksums.
They do not grant access to the maintainer's server.

Release packages are built from tracked files and exclude runtime state.
They exclude `config.json`, `runtime`, certs, keys, auth DBs, logs, and local operator files.
The EXE embeds that same tracked source payload and never embeds Credential Manager values.

Security status today is `approved-internal` for private tailnet use only.
Public internet and enterprise production remain unapproved.

## License

MIT.
