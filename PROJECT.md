# Whispergate project spec

## Locked deployment decisions

- Primary deployment target is Windows plus Tailscale plus a local ntfy Windows service.
- GitHub deployment is source and release package distribution only, not hosted server access.
- Windows setup must install ntfy as an Automatic Windows service.
- `WhispergateSetup.exe` is the primary Windows entrypoint for operator-grade setup.
- The setup EXE must embed only tracked source payload, never runtime config, auth DBs, logs, certs, or credentials.
- The setup EXE is a wizard orchestrator; repo scripts remain the setup, doctor, verify, and service authority.
- Non-technical Windows operators must get guided Tailscale checks, config creation, install, verify, and phone values.
- `deployment green` requires a durable startup owner and verification on the actual Tailscale HTTPS route.
- Doctor must report service runtime state and fail when the Windows service is not configured for automatic startup.
- Tailnet-only Tailscale Serve is the default exposure mode; Funnel remains explicit opt-in only.
- Unsigned v1 releases must document the expected Windows SmartScreen warning.

## First verification

Run `scripts\build-release.ps1`, then `scripts\setup.ps1`, then `scripts\doctor.ps1`, then `scripts\verify.ps1`.

## First abort action

Stop before release or push when EXE build, source safety scan, service, exposure, health,
publish, receive, or websocket checks fail.
