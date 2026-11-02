# Hermes Interfaces

Read-only probe performed against Hermes Agent v0.22.5 at
`%LOCALAPPDATA%\hermes`. No Hermes files were changed by this probe.

## 5. Memory Layout

- The built-in stores are `%HERMES_HOME%\memories\MEMORY.md` and
  `%HERMES_HOME%\memories\USER.md`.
- `MEMORY.md` contains agent notes. `USER.md` contains the owner profile.
- Entries are separated by the `§` delimiter. The current documented limits are
  2,200 characters for `MEMORY.md` and 1,375 for `USER.md`.
- Named profiles use the same two files below
  `%HERMES_HOME%\profiles\<profile>\memories\`.

Proof:

- `%LOCALAPPDATA%\hermes\hermes-agent\tools\memory_tool.py:38-40` resolves
  the memory directory from `get_hermes_home()`.
- `%LOCALAPPDATA%\hermes\hermes-agent\tools\memory_tool.py:1-5` names the
  files and their roles.
- `%LOCALAPPDATA%\hermes\hermes-agent\website\docs\user-guide\features\memory.md:13-20,38-57`
  documents paths, limits, and delimiters.
- `hermes profile create --help` and
  `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\profiles.py:37-41,1367-1374`
  prove that clone copies `memories/MEMORY.md` and `memories/USER.md`.

## 6. State Databases and JSON State

- Default state database: `%HERMES_HOME%\state.db`.
- Named-profile state database: `%HERMES_HOME%\profiles\<profile>\state.db`.
- The default state schema includes `sessions`, `messages`,
  `session_model_usage`, `gateway_routing`, `gateway_heartbeats`, and
  `state_meta`, among other runtime tables. `sessions` contains source,
  Telegram identifiers, profile name, timestamps, message/tool/token counts,
  model, and cost fields. `messages` contains role, content, timestamp,
  token count, and tool-call fields.
- Default Kanban storage is `%HERMES_HOME%\kanban.db`; additional board stores
  are under `%HERMES_HOME%\kanban\boards\<board>\kanban.db`.
- Gateway status is persisted in `%HERMES_HOME%\gateway_state.json`.
  The observed file contains `pid`, `gateway_state`, `platforms`,
  `served_profiles`, `updated_at`, and `code_version`. A stale JSON state is
  not proof of liveness; the installer must also check the PID.

Proof:

- `python` read-only SQLite inspection of `%LOCALAPPDATA%\hermes\state.db`
  returned the tables and schemas above.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\backup.py:1103-1116`
  names `state.db`, profile runtime files, `gateway_state.json`, and
  `kanban.db` as managed state.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\doctor_platform.py:50-53`
  enumerates profile and board database locations.
- `%LOCALAPPDATA%\hermes\gateway_state.json` is the observed gateway-state
  file; `%LOCALAPPDATA%\hermes\hermes-agent\container_boot.py:161-163`
  shows the state-file path construction.

## 7. Cron Store and Commands

- Cron jobs are stored in `%HERMES_HOME%\cron\jobs.json` for the active
  profile. For a named profile the path is
  `%HERMES_HOME%\profiles\<profile>\cron\jobs.json`.
- Run output is in the sibling `cron\output\<job_id>\` directory.
- The CLI commands are:

  - `hermes cron list [--all]`
  - `hermes cron run <job_id>`
  - `hermes cron pause <job_id>`
  - `hermes cron resume <job_id> [--at ISO-8601] [--run-now]`
  - `hermes cron remove <job_id>`
  - `hermes cron status`, `hermes cron runs`, and `hermes cron history`

Proof:

- `hermes cron --help` and the help for each listed subcommand provide the
  command names and arguments.
- `%LOCALAPPDATA%\hermes\hermes-agent\cron\jobs.py:1-3,78-90,114-126`
  defines the store and output paths.
- `%LOCALAPPDATA%\hermes\hermes-agent\cron\jobs.py:169-183` proves that
  the active profile home is used dynamically.

## 8. Non-Interactive Turn

- Preferred installer command for an independent turn:
  `hermes -z <prompt>`.
- `-z` / `--oneshot` prints only the final response, with no banner, spinner,
  or session-id line. It supports `--usage-file`, `--provider`, `--model`,
  `--in`, and `--resume`.
- Equivalent profile-scoped form:
  `hermes -p <profile> chat -q <prompt> --oneshot --quiet`.
- `--resume latest` resumes the most recent workspace-scoped session. For a
  profile, set `HERMES_HOME` to that profile or invoke `hermes -p <profile>`.
- Installer prompts will be passed with `--query-file` when arbitrary text
  must not be shell-interpreted.

Proof:

- `hermes --help` documents `-z`, `--resume`, `--in`, and the output contract.
- `hermes chat --help` documents `-q`, `--query-file`, `--oneshot`, `--quiet`,
  `--resume`, and `--in`.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\gateway_chat.py:141-178`
  implements latest-session resume and one-shot dispatch.

## 9. Model Block and Model Picker

- The root configuration is `%HERMES_HOME%\config.yaml`; named profiles use
  `%HERMES_HOME%\profiles\<profile>\config.yaml`.
- The model block is `model:` with at least `default`, `provider`, and, for a
  custom OpenAI-compatible server, `base_url`. The owner install currently
  uses `default: gpt-oss:20b`, `provider: custom`, and
  `base_url: http://127.0.0.1:11434/v1`.
- Custom provider catalogs can be represented by `custom_providers:` or the
  modern `providers:` form. The CLI's picker returns a payload containing
  `providers`, `model`, and `provider`.
- The reusable picker path is
  `hermes_cli.inventory.load_picker_context()` followed by
  `hermes_cli.inventory.build_models_payload(...)`. The CLI calls it from
  `hermes_cli.cli_model_switch_mixin._show_model_picker`.

Proof:

- `%LOCALAPPDATA%\hermes\config.yaml:72-112` shows the model block and custom
  endpoint values.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\inventory.py:76-103,170`
  defines the picker function and returned shape.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\cli_model_switch_mixin.py:374-405`
  shows the CLI call path.
- `hermes config path`, `hermes config get model --json`, and
  `hermes model --help` are the operator-facing paths. The installer will use
  the Python picker only for discovery and will write only the model block.

## 10. Shell Hooks and Approval

- Hooks are configured in each active profile's `config.yaml` under
  `hooks:`. The value maps an event such as `pre_tool_call` to entries with
  `matcher`, `command`, and `timeout`.
- `pre_tool_call` receives JSON on stdin with `tool_name`, `args`, session and
  task identifiers. A hook can return the Hermes wire decision used to block
  or modify a call.
- First use requires consent. Consent is persisted at
  `%HERMES_HOME%\shell-hooks-allowlist.json`.
- Non-interactive approval is supported by `--accept-hooks`,
  `HERMES_ACCEPT_HOOKS=1`, or `hooks_auto_accept: true`.
- The verification command is `hermes hooks test pre_tool_call --for-tool
  <tool>`; `hermes hooks doctor` checks executable state, consent, mtime drift,
  and a synthetic JSON run.

Proof:

- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\config_defaults.py:1756-1764`
  documents the configuration and approval file.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\hooks.py:99-116,182-221,286-321`
  documents payloads, test execution, and approval checks.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\plugins.py:1941-2058`
  defines the `pre_tool_call` veto path.
- `hermes hooks --help` and `hermes hooks test --help` provide the commands.

## 11. Giving a Tool to One Profile

- A profile-scoped tool is supplied as a skill under
  `%HERMES_HOME%\profiles\<profile>\skills\<skill-name>\`, with the skill's
  instructions and command/tool implementation there. The profile's
  `config.yaml` controls enabled and disabled toolsets.
- A built-in or installed plugin can also register a tool, but plugin
  configuration is profile-scoped through that profile's config and plugin
  tree. A shell hook is the correct enforcement mechanism for a deny rule;
  memory text is not access control.
- The installer will use a small profile-local skill/command for optional
  SerpApi and Composio access and a `pre_tool_call` hook for the DEV and
  RESEARCH deny boundary.

Proof:

- `hermes skills --help` exposes profile skill management.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\profiles.py:35-41,1369-1375`
  shows that each profile has its own `skills` directory and that clone copies
  it.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\config.py:945-964`
  identifies profile tool/config roots.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\plugins.py:1996-2018`
  proves the runtime pre-tool-call enforcement point.

## 12. Telegram Group Authorization and Multiplexing

- Telegram group authorization can be expressed by `platforms.telegram.extra.group_allowed_chats`
  or `TELEGRAM_GROUP_ALLOWED_CHATS`. Response filtering uses
  `platforms.telegram.extra.allowed_chats` or `TELEGRAM_ALLOWED_CHATS`.
- Topic filtering uses `platforms.telegram.extra.allowed_topics` or
  `TELEGRAM_ALLOWED_TOPICS`; General is represented as thread id `1` when a
  message has no `message_thread_id`.
- The multiplex setting is `gateway.multiplex_profiles` (the top-level alias
  is also accepted by the config reader). Current Hermes defaults it to true.
- Explicit profile routing, when needed, is `gateway.profile_routes`, a list
  of profile/platform/chat/user match records. The JARVIS installer instead
  writes its own `pre_gateway_dispatch` plugin map because the findings
  require topic-to-profile routing by thread id.

Proof:

- `%LOCALAPPDATA%\hermes\hermes-agent\plugins\platforms\telegram\adapter.py:5825-5846`
  defines `allowed_chats`, `group_allowed_chats`, and `allowed_topics`.
- `%LOCALAPPDATA%\hermes\hermes-agent\plugins\platforms\telegram\gateway_env.py:21-29`
  names the environment authorization variables.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\config_defaults.py:2180-2194`
  defines `multiplex_profiles` and `profile_routes`.
- `%LOCALAPPDATA%\hermes\hermes-agent\gateway\authz_mixin.py:552-563`
  shows the group-chat authorization check.

## 13. `--clone` Semantics

`hermes profile create <name> --clone` copies, when present:

- `config.yaml`
- `.env`
- `SOUL.md`
- `memories/MEMORY.md`
- `memories/USER.md`
- the source `skills` directory
- installed user plugins and their provenance

It creates the standard profile directories, strips messaging channel settings
and bot credentials by default, removes the multiplex flag from the clone, and
does not copy channel state. `--clone-channels` opts into copying channel
settings but is unsafe for one shared Telegram bot and is refused in some live
multiplexed cases. `--clone-all` copies broader state but excludes per-profile
history, cron, gateway runtime markers, and infrastructure trees.

Proof:

- `hermes profile create --help` reports the clone and clone-channel behavior.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\profiles.py:37-89`
  lists copied and excluded paths.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\profiles.py:1292-1309`
  removes the multiplex flag from clones.
- `%LOCALAPPDATA%\hermes\hermes-agent\hermes_cli\profiles.py:1383-1455`
  implements the clone, channel stripping, and atomic profile publication.

## Windows Translation Used by the Plan

- `%LOCALAPPDATA%\hermes` is the default Hermes home; the installer honors an
  explicit `HERMES_HOME` for temporary tests.
- Hermes itself supports Windows file locking through `msvcrt`; the installer
  uses PowerShell and Python rather than Bash/systemd.
- Dashboard and voice services use per-user Task Scheduler tasks or the
  per-user Startup folder. They bind only to `127.0.0.1`.
- Firewall work uses Windows Defender Firewall via `New-NetFirewallRule`.
- The findings' Linux paths are represented by `%LOCALAPPDATA%\jarvis-*` and
  `%USERPROFILE%\jarvis-*` data roots while keeping the installer path model
  portable for a later Linux backend.
