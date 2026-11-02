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
| Pester | passed: 28 | `Invoke-Pester -Path tests` |
| Python tests | passed: 2 | `py -3.12 -m unittest discover -s tests -p 'test_*.py'` |
| Parser/compile checks | passed | `py -3.12 -m py_compile ...` |
| Dry run | passed through step 12 | copied-Hermes Milestone 1 log below |
| Dashboard runtime | passed | local contract smoke on `127.0.0.1:18899` |
| Kokoro runtime | pending | |
| Telegram topics | pending | |
| Owner acceptance | pending | |

## Milestone 1 Verification Record

Executed on 2026-11-02 against a read-only copy of `%LOCALAPPDATA%\hermes`:

```powershell
$copy = 'C:\Users\Shadow\AppData\Local\Temp\opencode\jarvis-hermes-phase3-7ff1dcfa38884de7b9eb49770fd7be3c'
$env:HERMES_HOME = $copy
.\installer\install.ps1 -DryRun -Through 12
```

The copy completed with `DRYRUN_SUCCESS=True` through step 12. The real owner
directory was not used as `HERMES_HOME` for execution and was not modified.

### Deterministic Step Counts

The six deterministic Milestone 1 rows have one Pester case each in
`tests/DeterministicSteps.Tests.ps1`; Milestone 1 state tests cover every
post-check. Result: **28 Pester tests, 28 passed, 0 failed**.

| Plan step | Tests | Result |
|---:|---:|---|
| 3, 5, 8, 9, 11, 12 | 1 each | passed |

The tests verify the real entry point, fake `HERMES_HOME`, pre/action/post
output, successful completion, and dry-run non-write behavior. They do not
claim production artifact verification for actions that remain deferred below.

### Real Step Actions: Steps 1-12

The installer now has real actions and non-default post-checks for Milestone 1:

- Steps 1-3: owner memory, interview, and permanent rules writes with backups.
- Step 1: writes owner identity and priority to Hermes memory after backups.
- Step 2: writes exactly six interview answers and an open-questions entry.
- Step 3: writes the six permanent operating-rule headings.
- Step 4: runs the complete crew-plan self-check prompt and verifies its response.
- Step 5: creates the three specialist profiles and installs their SOUL files.
- Step 6: runs the complete team-awareness prompt and verifies all four identities.
- Step 7: calls Telegram membership/topic APIs and saves the chat/thread map.
- Step 8: backs up and strips Telegram settings from specialist profiles.
- Step 9: writes and enables the topic plugin, configures multiplexing, and restarts Hermes.
- Step 10: runs the complete first-words self-check prompt and verifies all lanes are reported.
- Step 11: creates the SQLite activity logger.
- Step 12: writes the durable logging rule to all four memories and creates four smoke rows.

### Later Milestones

| Findings requirement | Current limitation | Reason |
|---|---|---|
| Steps 13-14 | Not part of `-Through 12`; step 14 remains an agent self-check for the next milestone boundary. | Later milestone work is intentionally stopped. |
| Steps 15-43 | Not implemented in this milestone. Their post-checks return false and the installer stops with `not implemented`; no placeholder JSON is written. | Dashboard, voice, comms/briefing, and finish milestones will be built one at a time as requested. |

The installer refuses to advance a non-dry-run step when its post-check fails.

## Owner Real-Install Command

From the repository root, after reviewing this file and supplying the prompts:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\installer\install.ps1"
```

Optional integrations are explicitly opt-in:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\installer\install.ps1" -WithClaudeCode -WithSerpApi -WithElevenLabs -WithComposio -WithTailscale -WithHomeAssistant
```
