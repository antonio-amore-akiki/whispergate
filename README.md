# Whispergate

Private ntfy notifications for phones, laptops, and agent workflows, served through Tailscale instead of the public internet.

**Story:** your automation can send the message, ntfy can deliver it, and Tailscale can keep it private. The hard part is making the whole path survive reboot, hide the local port, and give a non-technical operator one obvious button.

Whispergate packages that path.

- **1 double-click Windows setup**: `START-HERE-Windows.bat`
- **1 durable process owner**: an Automatic Windows service
- **1 private phone URL**: `https://your-device.your-tailnet.ts.net`
- **0 public exposure by default**: Tailnet-only Tailscale Serve
- **0 phone-side port typing**: do not add `:8091`
- **2 release artifacts**: source ZIP plus SHA256 checksum

Source only: https://github.com/antonio-amore-akiki/whispergate

## The problem

Self-hosted ntfy is easy to start and easy to break.

A laptop restarts. A terminal closes. The phone app points at the wrong port. Tailscale Serve is not active. Funnel accidentally publishes a private server. Nobody knows whether the problem is ntfy, DNS, Tailscale, the Windows service, or the topic itself.

That is not a production setup. That is a weekend command still running in a window.

## The Whispergate fix

Whispergate turns a local ntfy server into an operator-owned notification gateway:

```text
phone or agent -> Tailscale HTTPS -> local ntfy on 127.0.0.1:8091
```

The local port stays local. The phone uses the Tailscale HTTPS name. Windows owns startup. Doctor checks the full path before you call it ready.

## What you get

- Private push notifications for Codex, agent loops, scripts, and home automation.
- Tailnet-only access by default, with public Funnel blocked unless explicitly enabled.
- Automatic startup after login or reboot through a Windows service.
- A doctor command that checks config, Tailscale, Serve/Funnel exposure, port `8091`, service state, health, and topics.
- A release ZIP for operators who should not touch git.
- Linux systemd commands in a separate beta lane.

## Quick start for Windows

Download the latest release ZIP, unzip it, then double-click:

```text
START-HERE-Windows.bat
```

Approve the Windows Administrator prompt.

The guided setup can install Tailscale through Windows Package Manager, opens the Tailscale sign-in path when needed, creates `config.json` when missing, installs ntfy as an Automatic Windows service, enables Tailnet-only Serve, verifies the route, and prints the phone URL.

Use the printed URL in the ntfy phone app.

```text
https://your-device.your-tailnet.ts.net
```

Do not add `:8091` on the phone.

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
| `START-HERE-Windows.bat` | Guided setup for non-technical Windows operators. |
| `scripts\doctor.ps1` | Full diagnostic report with fix hints. |
| `scripts\doctor.ps1 -Json` | Machine-readable diagnostics. |
| `scripts\verify.ps1` | Health, publish, receive, and websocket checks. |
| `scripts\exposure-status.ps1` | Show Tailnet-only, Funnel, or missing exposure. |
| `scripts\disable-funnel.ps1` | Turn public Funnel off. |
| `scripts\update.ps1 -DryRun` | Preview update steps. |
| `scripts\build-release.ps1` | Build source ZIP and SHA256 checksum. |

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

GitHub releases are source distribution only. They do not grant access to the maintainer's server.

Release packages are built from tracked files and exclude `config.json`, `runtime`, certs, keys, auth DBs, logs, and local operator files.

## Search map

ntfy, self-hosted ntfy, private notifications, push notifications, Tailscale, Tailscale Serve, Tailscale Funnel, MagicDNS, Tailnet, Windows service, local notification server, Codex notifications, agent notifications, home automation notifications.

## License

MIT. See `LICENSE`.
