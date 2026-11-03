# JARVIS Installer Plan

Source of truth: `jarvis-installer-findings.md`. This is the Windows 11 plan
for Hermes Agent v0.22.5. The installer will use PowerShell 5.1-compatible
syntax, with PowerShell 7 treated as an enhancement rather than a requirement.
No owner Hermes file is changed until the real install is explicitly run.

## Architecture

`installer/install.ps1` owns ordered execution, prompts, state, backups, undo,
and switches. Small PowerShell modules implement one concern each. Python
stdlib services and plain HTML/CSS/JS live in the project folder created by the
installer. Windows Task Scheduler replaces systemd; a Linux service backend can
be added later without changing the service contracts. Secrets are read from
`.env` or masked input and are passed only through process environments or
mode-restricted files.

## Phase Rules

- Each row runs a pre-check, action, and post-check and records its result in
  `state\progress.json`.
- Before a Hermes file changes, the installer copies it to
  `state\backups\<timestamp>\` and appends a reversible entry to
  `state\undo.ps1`.
- Agent turns use `hermes -z` or the discovered profile-scoped equivalent;
  replies are appended to the activity log without secrets.
- `-DryRun` performs no writes, network calls, process starts, task changes,
  firewall changes, Telegram calls, or prompts beyond the initial form.
- `-Step`, `-From`, and resume state select ordered work. `-Uninstall` executes
  undo entries in reverse order and asks before deleting files.
- Steps 45-48 are troubleshooting commands, not automatic install steps.
- During Phase 3 and a real install, Paperclip, Postgres, and Ollama remain
  running. Before step 15, the installer proves that TCP port 8899 is free.

## Ordered Steps

| # / page | Class | Installer action | Files written | Verification |
|---|---|---|---|---|
| 1 / 1 | I | Collect identity, work, timezone, hours, weather city, and priority; run JARVIS identity turn. The weather city is runtime input only. | `memories/USER.md`, `memories/MEMORY.md`, activity log; `state/inputs.json` is local-only | USER/MEMORY entries contain owner facts and turn reply names JARVIS, owner, priority; weather city is never committed. |
| 2 / 2 | I | Collect exactly six interview answers up front; run the interview prompt with gaps marked. | `memories/USER.md`, `memories/MEMORY.md`, `state/inputs.json` | Six numbered answers are present; open questions and saved filename are reported. |
| 3 / 3 | D | Install the original permanent operating rules into default memory. | default `memories/MEMORY.md` | All six rule headings are present and fit memory limits. |
| 4 / 4 | A | Run the crew-planning turn and confirm fixed profile/name mapping. | activity log | Reply confirms default JARVIS plus `dev`, `research`, `assistant`. |
| 5 / 5 | D | Create three profiles with `hermes profile create <name> --clone`; install original SOUL files. | `profiles/{dev,research,assistant}/`, each `SOUL.md` | Profiles exist, no default clone is created, and each non-interactive identity turn answers correctly. |
| 6 / 6 | A | Distribute owner brief, role boundaries, isolated workspaces, and roster by profile. | profile `memories/USER.md`, `MEMORY.md`, workspace folders | Four profiles report the correct identity and boundary. |
| 7 / 7 | I | Read `TELEGRAM_BOT_TOKEN` from default `.env`; call `getChatMember`, then create DEV/RESEARCH/ASSISTANT topics. | `state/telegram.json` | Bot is administrator with `can_manage_topics`; API responses contain chat and thread IDs. |
| 8 / 7b | D | Back up each specialist config and remove platform blocks and token lines. | specialist `config.yaml`, `.env`; backup and undo records | No specialist config or env contains Telegram settings; default still has the token. |
| 9 / 7c | D | Write the topic plugin, enable it, set multiplexing, and restart the gateway through Hermes. | `plugins/telegram_topic_profiles/{plugin.yaml,topics.json,__init__.py}`, root `config.yaml` | Plugin validation, `multiplex_profiles: true`, and gateway status pass. |
| 10 / 7d | I | Ask the owner to send the exact first-words test in all four topics. | activity log | Owner confirms four replies identify their own profiles. |
| 11 / 8e | D | Create the project folder and SQLite activity logger. | `jarvis-mission-control/log-task.ps1`, `agent-logs.db` | Rows from two working directories, all statuses, invalid usage, and one DB path pass. |
| 12 / 8f | D | Add the durable logging rule and write four smoke rows. | four profile memory files; `agent-logs.db` | Last five rows show four agent names and exact model fields. |
| 13 / 8g | A | If `-WithBuilderOrientation`, orient the current coding application as a builder tool; otherwise record skipped. | activity log only | Orientation reports layout, crew, plugin, project, builder-only role, and independence from the chosen application. |
| 14 / 9 | A | Run DEV read-only survey against Hermes DBs, cron, gateway JSON, and log DB. | activity log only | Survey names sources, tables, timestamp types, and truthful dashboard limits. |
| 15 / 10 | D | Confirm Paperclip/Postgres/Ollama remain running and port 8899 is free; install the stdlib dashboard server on `127.0.0.1:8899` and register a per-user scheduled task. | `server.py`, `dashboard.task.xml` | Process-preservation and port checks pass before installation; contract keys, restart recovery, and 200-request handle stability pass. |
| 16 / 11 | I | Serve `/upload`; accept the owner template upload or use the bundled original template. | `jarvis-dashboard-template.html` | Extension, traversal, size, checklist, and saved-file checks pass. |
| 17 / 12 | D | Keep `/template`; produce the original split dashboard and remove the shim only from `/`. | `index.html`, `styles.css`, `script.js`, `favicon.svg` | `__TEMPLATE__` is true only on `/template`; seven views and MIME/cache checks pass. |
| 18 / 13 | D | Install backup script and version badge, starting at `v0.1`. | `jarvis-backup.ps1`, backup root, dashboard files | Baseline snapshot has manifest, restore script, and matching badge. |
| 19 / 14 | D | Wire Home state and `/events` SSE with the original data renderer. | `server.py`, `script.js`, `styles.css` | Real data, stable SSE, 3-second state events, dash rules, and bumped badge pass. |
| 20 / 15 | D | Wire Agents roster, dossier, heatmap, and per-agent feed. | `server.py`, `script.js` | All four selections show real scoped values and no placeholder data. |
| 21 / 16 | D | Add chat history/send using profile-scoped `hermes -z`, latest eligible session, and logging. | `server.py`, `script.js` | Explicit send creates a plain reply, never page-loads a turn, and logs `Comms: `. |
| 22 / 17 | D | Add cron and content routes, four shelves, and honest empty states. | `server.py`, `script.js`, `content/{default,dev,research,assistant}` | Route contract and traversal checks pass; example data is absent. |
| 23 / 18 | D | Add the document protocol and ask RESEARCH to write the first original brief. | four memory files; `content/research/<date>_<slug>.md` | Library shows author, title, date, and body; chat contains title plus one line. |
| 24 / 18a | I | With `-WithSerpApi`, collect masked key and write one protected file; otherwise skip. | `%LOCALAPPDATA%\jarvis-secrets\serpapi.key` | File has no newline, is not printed, and is absent when skipped. |
| 25 / 18b | D | Install one research-only SerpApi skill/command with citations and logging. | `profiles/research/skills/jarvis-search/` | New-session smoke search cites URLs and writes a research document. |
| 26 / 19 | D | Use Hermes inventory picker to expose providers/models and atomically update one model block. | dashboard server/client; profile `config.yaml` | Each model card is live and one changed config block is preserved exactly. |
| 27 / 19a | D | Install a supported Python 3.12 interpreter via `py -3.12` or uv, create the Kokoro venv with that interpreter, record the exact interpreter in state, verify model sizes, and create the voice service task. | `%LOCALAPPDATA%\jarvis-voice\`, `voice-server.py`, task XML, local `state\voice-runtime.json` | `/health` loads; `/say` returns 24 kHz WAV and loopback-only listener; state records the exact Python executable/version. |
| 28 / 19b | I | With `-WithElevenLabs`, collect masked key; otherwise record local-only. | `%LOCALAPPDATA%\jarvis-secrets\elevenlabs.key` | Key length/status is shown without key content. |
| 29 / 19c | D | Gate voice work on Kokoro health/synthesis and optional ElevenLabs voices check. | activity log | Every verdict is `works`, `skipped`, or `failed`; failed blocks later voice steps. |
| 30 / 20 | D | Add server-stored scenarios, proxy routes, transcription, fallback, and engine header. | dashboard server/client; `voice-scenarios.json` | Key-present and key-absent Control states, fallback, and output metadata pass. |
| 31 / 20b | D | Generate four Kokoro greetings and optional ElevenLabs clips with cache and level normalization. | greeting cache, voice map, dashboard files | Four clips play, sizes are listed, and scenario switch speech is demonstrated. |
| 32 / 21 | D | Add globe/space push-to-talk state machine with fixed timing constants. | `script.js`, `styles.css` | Spoken turn, latch/hold, interruption, restart, and no echo self-reply pass. |
| 33 / 22 | D | Add conversation overlay, start-time transcript scope, and 1100 ms rest return. | `script.js`, `styles.css` | Mic/stop overlay and cancellable rest transition pass. |
| 34 / 23 | D | Add face greetings, `/api/owner`, keyboard shortcuts, and hover keycaps. | `server.py`, `script.js`, `styles.css` | Four keys, Esc, `?`, text-input exclusion, and owner name pass. |
| 35 / 24 | D | Add Comms dictation, append-only pauses, send clearing, and upload fallback. | `script.js`, `server.py` | Dictated text survives pauses and cannot refill after send. |
| 36 / 25 | I | With `-WithComposio`, install CLI and pause for login plus two browser links. | `%LOCALAPPDATA%\composio\`, state record | Both connections show ACTIVE and only two read operations are available. |
| 37 / 26 | I | Install allowlisted mail/calendar command and deny hook; request one owner approval. | profile skill/command; `config.yaml` hooks; allowlist | JARVIS/ASSISTANT work; DEV/RESEARCH are denied in a fresh gateway session. |
| 38 / 26b | D | Add `brief`, the step-1 owner-form weather city, trigger phrases, and three-sentence spoken format. | JARVIS memory; profile skill/command | New-session output has mail/weather/calendar rules and sentence-count proof; the city is read from local runtime state, never hardcoded. |
| 39 / 26c | D | Add the separate throttled poller and stale cache chips. | poller, cache JSON, task XML, `server.py` | At most two calls per ten minutes, one auto-start per minute, and stale state is honest. |
| 40 / 27 | A | Run responsive screenshots and console audit at all five required sizes. | evidence screenshots and activity log | No overflow, clipping, tab loss, or console errors; Chromium is terminated. |
| 41 / 28 | I | With `-WithTailscale`, install Tailscale, authorize, serve HTTPS, and add Defender rules. | scheduled task; firewall rules; state record | Loopback sockets, HTTPS tailnet URL, reboot recovery, and no public listener pass. |
| 42 / 28b | A | Reconcile original docs seed with actual Windows services and routes. | `docs.md`, dashboard route | One edited word appears on reload and changed claims are listed. |
| 43 / 29 | A | Run the evidence checklist, stamp `v1.0`, and make final verified backup. | final backup, `docs/VERIFY.md`, owner summary | Automated checks pass; owner ear/phone checks are explicitly marked. |
| 44 / 30 | I | With `-WithHomeAssistant`, install Docker or Core fallback on loopback and pause for onboarding. | `%LOCALAPPDATA%\homeassistant\`, scheduled task | Restart recovery, port 8123 loopback, and owner browser onboarding pass. |
| 45 / T1 | A | Provide on-demand topic identity diagnosis and retest workflow. | troubleshooting log only | Thread ID, exact profile, restart, and all-four-topic checks are ordered. |
| 46 / T2 | A | Provide on-demand service connection diagnosis and fresh-session check. | troubleshooting log only | Tool path, session age, and Composio ACTIVE/EXPIRED checks are reported. |
| 47 / T3 | A | Provide on-demand CSS measurement-first diagnosis and backup restore path. | troubleshooting log only | Computed style, animation fill, specificity order, and restore are covered. |
| 48 / T4 | A | Provide outside-in dashboard diagnosis from process to `window.__TEMPLATE__`. | troubleshooting log only | Listener, JSON, console, network, and shim checks are shown side by side. |

## Chosen Unspecified Values

| §9 item | Choice | Reason |
|---|---|---|
| 19 | `-16 LUFS-I`, `-1 dBTP` | Common speech target with headroom; deterministic and easy to verify with ffmpeg. |
| 20 | ElevenLabs `eleven_multilingual_v2`; STT `scribe_v1`; TTS `/v1/text-to-speech/{voice_id}`, voices `/v1/voices`, STT `/v1/speech-to-text` | Current stable API shapes; all endpoints remain configurable in `voice-scenarios.json`. |
| 21 | `bm_daniel` for JARVIS | The greeting voice map is authoritative over the earlier `bm_lewis` example. |
| 22 | Initials `RS` and `AS`; taglines `Evidence before confidence` and `Quietly keeps the day moving`; role strings `Research lead` and `Executive assistant` | Distinguishable, compact, and consistent with the role boundaries. |
| 23 | `active` = reachable with activity in 15 minutes; `standby` = reachable but no recent activity; `idle` = unreachable or stopped. Events use a rolling 80-hour window; hourly uses 13 one-hour buckets ending in the current hour; `peak_hour` is the max bucket or null; alerts are high for stopped/unreadable services and info for stale optional data; cost uses Hermes `estimated_cost_usd` then `actual_cost_usd`, otherwise null. | Avoids invented activity and makes every state derivable from observed data. |
| 24 | Start `v0.1`; increment by `0.1` after each wiring card; stamp `v1.0` only at final verification. | Matches both version examples and keeps a visible monotonic history. |
| 25 | Add non-contract `last_session_at` and `owner` only inside the server's internal normalized records; expose them only where the view needs them. | Preserves the fixed top-level API contract while satisfying the view requirements. |
| 26 | Windows: `winget install --id Tailscale.Tailscale`; Defender via `New-NetFirewallRule`; Composio first attempt `py -m pip install --user composio`, with the exact successful command recorded. | Native Windows tools, reversible firewall rules, and no guessed vendor shell installer. |
| 27 | Geocode the owner-form `weather_city` with Open-Meteo `/v1/search?name=<url-encoded-city>&count=1&language=en&format=json`; request `temperature_2m_max`, `temperature_2m_min`, and `weather_code` with `timezone=auto` and Celsius. | No weather key, stable fields, and city-specific output without a committed location. |
| 28 | `py -m pip install --user playwright` followed by `py -m playwright install chromium`; fallback is an existing Edge/Chrome executable and otherwise an explicit unchecked result. | Works on both PowerShell versions and avoids assuming admin rights. |

## Explicit Windows Deviations To Revisit During Build

- Linux `bash` logger becomes a PowerShell 5.1-compatible logger while keeping
  the same SQLite schema, argument semantics, and path resolution.
- Linux `systemd` units become per-user Task Scheduler tasks with restart-on-
  failure and logon/startup triggers. No service binds beyond loopback.
- Linux `apt` package steps use `winget`, `py -m pip`, or a documented skip;
  no installer step silently assumes WSL.
- Linux `chmod` permissions become Windows ACLs that grant the owner only;
  tests verify no inherited broad ACL where the secret files are stored.
- Tailscale firewall and serve verification use Windows Defender Firewall and
  `tailscale serve`; `tailscale funnel` is never called.
- Findings' unavailable purchased template is replaced by an original local
  single-file template that satisfies §6.3 and §6.7's interface contract.
