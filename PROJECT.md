# Whispergate project spec

## Locked deployment decisions

- Primary deployment target is Windows plus Tailscale plus a local ntfy Windows service.
- GitHub deployment is source and release package distribution only, not hosted server access.
- Windows setup must install ntfy as an Automatic Windows service.
- Non-technical Windows operators must have a guided entrypoint that checks Tailscale, prepares config, installs, verifies, and prints the phone URL.
- `deployment green` requires a durable startup owner and verification on the actual Tailscale HTTPS route.
- Doctor must report service runtime state and fail when the Windows service is not configured for automatic startup.
- Tailnet-only Tailscale Serve is the default exposure mode; Funnel remains explicit opt-in only.

## First verification

Run `scripts\setup.ps1`, then `scripts\doctor.ps1`, then `scripts\verify.ps1`.

## First abort action

Stop before release or push when the Automatic Windows service, Tailnet-only exposure, health, publish, receive, or websocket checks fail.
