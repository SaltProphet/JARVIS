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
| Pester | passed: 37 | `Invoke-Pester -Path tests` |
| Python tests | passed: 2 | `py -3.12 -m unittest discover -s tests -p 'test_*.py'` |
| Parser/compile checks | passed | `py -3.12 -m py_compile ...` |
| Dry run | passed through step 44 | copied-Hermes Phase 3 log below |
| Dashboard runtime | passed | local contract smoke on `127.0.0.1:18899` |
| Kokoro runtime | pending | |
| Telegram topics | pending | |
| Owner acceptance | pending | |

## Phase 3 Verification Record

Executed on 2026-11-02 against a read-only copy of `%LOCALAPPDATA%\hermes`:

```powershell
$copy = 'C:\Users\Shadow\AppData\Local\Temp\opencode\jarvis-hermes-phase3-7ff1dcfa38884de7b9eb49770fd7be3c'
$env:HERMES_HOME = $copy
.\installer\install.ps1 -DryRun
```

The copy completed with `DRYRUN_SUCCESS=True` through step 44. The real owner
directory was not used as `HERMES_HOME` for execution and was not modified.

### Deterministic Step Counts

Each deterministic row has one Pester case in
`tests/DeterministicSteps.Tests.ps1`. Result: **26 tests, 26 passed, 0 failed**.

| Plan step | Tests | Result |
|---:|---:|---|
| 3, 5, 8, 9, 11, 12 | 1 each | passed |
| 15, 17, 18, 19, 20, 21, 22, 23 | 1 each | passed |
| 25, 26, 27, 29, 30, 31, 32, 33 | 1 each | passed |
| 34, 35, 38, 39 | 1 each | passed |

The tests verify the real entry point, fake `HERMES_HOME`, pre/action/post
output, successful completion, and dry-run non-write behavior. They do not
claim production artifact verification for actions that remain deferred below.

### Deviations From Findings

| Findings requirement | Current deviation | Reason |
|---|---|---|
| Every deterministic row performs its complete production action | Steps 4, 6, 10, 14, 16, 19-22, 26, 29-35, 37, 40, and 42 are currently recorded as prompt/module work or minimal route behavior | Phase 2 built the safe installer foundation and contracts; real Hermes turns, browser/OAuth flows, screenshot audit, and full UI state machines require runtime services or owner interaction and were intentionally not run in Phase 3. |
| Step 3 installs all six permanent rule headings | Current action writes the bundled memory-rules template, but no post-check counts the six headings | The template is present; the production post-check remains to be added. |
| Step 5 uses Hermes clone commands and confirms identity turns | Dry run reports clone commands; non-dry-run invokes the CLI but does not yet run identity post-checks | Avoids changing the owner installation before explicit approval. |
| Step 8/9 fully rewrites and validates Telegram routing | Telegram API, gateway restart, and plugin validation are not run in Phase 3 | Requires live bot credentials and a running gateway; dry run only proves no calls occur. |
| Step 15 registers and verifies restart recovery | Dashboard files/task registration exist, but restart recovery and 200-request stability are not exercised | Requires a process/task runtime test. |
| Step 23/25/38/39 generate live research, SerpApi, briefing, and poller outputs | Modules and configuration scaffolds exist, but no external calls or live scheduled poller are run | Requires optional credentials and owner-approved external integrations. |
| Steps 27/29-31 provide full Kokoro and optional ElevenLabs behavior | Kokoro setup, health, greeting generation, fallback, and ElevenLabs checks are not run in the copied-Hermes dry run | Voice downloads and optional credentials are runtime work, not dry-run work. |
| Steps 32-35 provide the complete interaction state machine | Dashboard assets contain the interface contract, but end-to-end microphone, speech, keyboard, and dictation acceptance is not automated | Requires browser/device verification; no owner device interaction was requested. |

These are documented scope deviations, not hidden failures. The real install
must not be run until the deferred runtime and owner checks are implemented or
explicitly accepted.

## Owner Real-Install Command

From the repository root, after reviewing this file and supplying the prompts:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\installer\install.ps1"
```

Optional integrations are explicitly opt-in:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\installer\install.ps1" -WithClaudeCode -WithSerpApi -WithElevenLabs -WithComposio -WithTailscale -WithHomeAssistant
```
