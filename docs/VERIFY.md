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
| Pester | passed: 44 | `Invoke-Pester -Path tests` |
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
`tests/DeterministicSteps.Tests.ps1`; the additional safety and orchestration
tests cover the new action and post-check layer. Result: **44 Pester tests,
44 passed, 0 failed**.

| Plan step | Tests | Result |
|---:|---:|---|
| 3, 5, 8, 9, 11, 12 | 1 each | passed |
| 15, 17, 18, 19, 20, 21, 22, 23 | 1 each | passed |
| 25, 26, 27, 29, 30, 31, 32, 33 | 1 each | passed |
| 34, 35, 38, 39 | 1 each | passed |

The tests verify the real entry point, fake `HERMES_HOME`, pre/action/post
output, successful completion, and dry-run non-write behavior. They do not
claim production artifact verification for actions that remain deferred below.

### Real Step Actions

The installer now has explicit action, pre-check, and post-check definitions
for all steps 1-48. The real actions currently covered are:

- Steps 1-3: owner memory, interview, and permanent rules writes with backups.
- Steps 4, 6, 13, 14, 19-23, 26, 29-35, 38, 40, 42, 43: matching prompt
  files are routed through `Invoke-JarvisAgentTurn`; deterministic artifacts
  and post-check state are written locally.
- Step 5: specialist profile creation and SOUL installation.
- Steps 7-9: Telegram discovery/topic creation, specialist isolation, and
  plugin installation.
- Steps 11-12: SQLite logger creation and smoke rows.
- Steps 15-18: dashboard files, upload/template assets, and backup baseline.
- Step 25: research skill installation when `-WithSerpApi` is enabled.
- Step 27: Python 3.12 Kokoro runtime state and scheduled task.
- Steps 36, 41, and 44: explicit owner pause/instruction, with optional
  integration actions where their switches are enabled.
- Steps 24, 28, and 37: explicit optional/approval pauses instead of silent
  `Show-Action` placeholders.

### Remaining Runtime Limitations

| Findings requirement | Current limitation | Reason |
|---|---|---|
| Every deterministic row performs its complete production action | The deterministic layer now writes explicit local artifacts and invokes the matching agent prompt, but live Hermes turns, browser/OAuth flows, screenshot capture, and device interaction remain runtime checks | These cannot be safely exercised against the real owner installation during this verification pass. |
| Step 3 installs all six permanent rule headings | The post-check currently verifies the rules file contains rule/memory content, not an exact six-heading count | The template is deterministic; exact heading-count validation remains a follow-up hardening item. |
| Step 5 uses Hermes clone commands and confirms identity turns | Dry run reports clone commands; non-dry-run invokes the CLI but does not yet run identity post-checks | Avoids changing the owner installation before explicit approval. |
| Step 8/9 fully rewrites and validates Telegram routing | Telegram API, gateway restart, and plugin validation are not run in Phase 3 | Requires live bot credentials and a running gateway; dry run only proves no calls occur. |
| Step 15 registers and verifies restart recovery | Dashboard files/task registration exist, but restart recovery and 200-request stability are not exercised | Requires a process/task runtime test. |
| Step 16/19-22/26/29-35/37/39/40/42 fully exercise live UI and integrations | Local contracts, marker artifacts, and prompt actions are implemented; live browser, voice, provider inventory, allowlist enforcement, poller, and screenshot evidence are not executed | Requires runtime services, optional credentials, or owner device interaction. |
| Steps 27/29-31 provide full Kokoro and optional ElevenLabs behavior | Kokoro setup, health, greeting generation, fallback, and ElevenLabs checks are not run in the copied-Hermes dry run | Voice downloads and optional credentials are runtime work, not dry-run work. |
| Steps 32-35 provide the complete interaction state machine | Dashboard assets contain the interface contract, but end-to-end microphone, speech, keyboard, and dictation acceptance is not automated | Requires browser/device verification; no owner device interaction was requested. |

These are documented runtime limitations, not hidden dry-run failures. The
installer now refuses to advance a non-dry-run step when its post-check fails.

## Owner Real-Install Command

From the repository root, after reviewing this file and supplying the prompts:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\installer\install.ps1"
```

Optional integrations are explicitly opt-in:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\installer\install.ps1" -WithClaudeCode -WithSerpApi -WithElevenLabs -WithComposio -WithTailscale -WithHomeAssistant
```
