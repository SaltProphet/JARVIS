# JARVIS Verification Checklist

This checklist is the final evidence record for the Windows installer. It is
intentionally separate from the installer so a verification run can be read
without executing any commands.

## Automated

Run from the repository root:

```powershell
Invoke-Pester -Path tests
py -3.12 -m unittest discover -s tests -p 'test_*.py'
py -3.12 -m py_compile installer/dashboard/server.py installer/voice/voice-server.py installer/lib/sqlite_helper.py
.\installer\install.ps1 -DryRun
```

Record the date, PowerShell version, Python executable, and the exact output
under the release or install ticket. The dry run must not create files,
processes, scheduled tasks, firewall rules, or network calls.

## Runtime Gates

- Paperclip, Postgres, and Ollama remain running before and after step 15.
- TCP port `127.0.0.1:8899` is free before dashboard installation.
- Dashboard binds only to `127.0.0.1`; `/api/state` contains the fixed contract.
- `/events` emits state events and a restart recovers the listener.
- Kokoro health and `/say` return a 24 kHz WAV before voice UI steps proceed.
- The recorded voice interpreter is Python 3.12 and matches the venv runtime.
- Telegram topics map to `dev`, `research`, and `assistant` without moving the
  default profile token.
- Every changed Hermes file has a backup and a reverse-order undo entry.
- Secrets are absent from console output, activity logs, committed files, and
  dashboard JSON responses.

## Owner Checks

- Send the first-words test in all four Telegram topics and confirm identity.
- Hold and release push-to-talk; confirm interruption and no self-echo.
- Switch voice scenarios and confirm the engine badge is truthful.
- Upload the original dashboard template and confirm traversal and size errors.
- Edit one model, restart the gateway, and confirm the selected block survives.
- Open the generated brief and confirm the weather city came from local input.
- Reboot or restart scheduled tasks and confirm dashboard and voice recovery.

## Evidence

| Check | Result | Evidence path or note |
|---|---|---|
| Pester | pending | |
| Python tests | pending | |
| Parser/compile checks | pending | |
| Dry run | pending | |
| Dashboard runtime | pending | |
| Kokoro runtime | pending | |
| Telegram topics | pending | |
| Owner acceptance | pending | |
