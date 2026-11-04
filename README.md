# JARVIS Mission Control

JARVIS Mission Control is a local Windows dashboard for Hermes Agent profiles,
local speech recognition, and local Kokoro speech synthesis.

## Current Status

- Dashboard: `http://127.0.0.1:8899`
- Dashboard version: `v0.1`
- Speech recognition: local `faster-whisper`
- Speech synthesis: local `kokoro-onnx`
- Voice service: `http://127.0.0.1:8767`
- Hermes Agent: local profile routing through `hermes -z`
- Audio processing is local; no cloud speech service is required.

The dashboard currently supports push-to-talk from the Home orb or Space bar,
browser `MediaRecorder` capture, local transcription, Hermes replies, and
Kokoro playback.

## Requirements

- Windows 10/11
- Python 3.12 for the Kokoro environment
- Python with `faster-whisper`, `numpy`, and `sounddevice` for local testing
- Hermes Agent installed at `%LOCALAPPDATA%\hermes`
- A working Windows microphone and output device
- Kokoro model files:
  - `kokoro-v1.0.onnx`
  - `voices-v1.0.bin`

## Voice Setup

Create the Kokoro environment with PowerShell:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\installer\voice\setup-voice.ps1 `
  -VoiceRoot "$env:USERPROFILE\jarvis-voice" `
  -StatePath "$env:USERPROFILE\jarvis-voice\voice-state.json"
```

Place the Kokoro model files in `$env:USERPROFILE\jarvis-voice`.

Start the voice service:

```powershell
$env:JARVIS_VOICE_ROOT = "$env:USERPROFILE\jarvis-voice"
& "$env:USERPROFILE\jarvis-voice\.venv\Scripts\python.exe" `
  .\installer\voice\voice-server.py
```

Verify it:

```powershell
Invoke-RestMethod http://127.0.0.1:8767/health
```

Test synthesis:

```powershell
Invoke-WebRequest -Method Post `
  -Uri 'http://127.0.0.1:8767/say?voice=bm_daniel&speed=1.0' `
  -ContentType 'text/plain; charset=utf-8' `
  -Body 'JARVIS voice test.' `
  -OutFile "$env:TEMP\jarvis-voice-test.wav"
```

## Dashboard Setup

The dashboard server defaults to local CPU `int8` transcription. This avoids
CUDA startup failures on systems without the required cuBLAS DLLs. CUDA can be
selected explicitly when the runtime is installed correctly.

```powershell
$env:JARVIS_PROJECT_ROOT = "$env:LOCALAPPDATA\jarvis-mission-control"
$env:JARVIS_DASHBOARD_PORT = '8899'
$env:JARVIS_STT_MODEL = "$env:USERPROFILE\.cache\huggingface\hub\models--Systran--faster-whisper-base\snapshots\<snapshot>"
$env:JARVIS_STT_DEVICE = 'cpu'
$env:JARVIS_STT_COMPUTE_TYPE = 'int8'

& python .\installer\dashboard\server.py
```

For a repository-only run, point `JARVIS_PROJECT_ROOT` at the dashboard source:

```powershell
$env:JARVIS_PROJECT_ROOT = (Resolve-Path .\installer\dashboard).Path
& python .\installer\dashboard\server.py
```

Open `http://127.0.0.1:8899/` and use the Home orb or hold Space while
speaking. Release Space to send the captured clip to `/api/transcribe`.

## Dashboard API

- `GET /api/state` returns dashboard, Hermes, crew, activity, and version state.
- `POST /api/transcribe` accepts an `audio/*` body and returns local transcript text.
- `POST /api/chat/send` sends a text turn to the selected Hermes profile.
- `POST /api/voice` sends text to Kokoro and returns a WAV response.
- `GET /api/voice/config` reads the configured voice scenario.
- `POST /api/voice/config` changes the voice scenario.
- `GET /api/models` returns the configured model view.

## Tests

Run the complete test suite from the repository root:

```powershell
python -m pytest -q
```

The tests cover dashboard state, upload validation, static dashboard contracts,
local transcription behavior, CUDA-to-CPU fallback, and voice capture wiring.

## Installed Runtime

The installer copies the runtime dashboard to:

```text
%LOCALAPPDATA%\jarvis-mission-control
```

If the browser does not show a recent repository change, verify that the
installed files and the running server use the same path:

```powershell
Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" |
  Where-Object CommandLine -match 'jarvis-mission-control\\server.py' |
  Select-Object ProcessId, CommandLine
```

The dashboard header displays the runtime version. The active server should be
bound only to `127.0.0.1:8899`.

## Known Pending Checks

- Real microphone speech through the browser still requires an owner-operated
  push-to-talk test.
- Reboot recovery and scheduled-task registration require an installed runtime.
- Telegram, OAuth, Tailscale, and private mail/calendar integrations remain
  owner-configured checks.
