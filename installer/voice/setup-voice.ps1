param([string]$VoiceRoot, [string]$StatePath)
$ErrorActionPreference = 'Stop'
$py = (Get-Command py -ErrorAction Stop).Source
$base = (& $py -3.12 -c "import sys; print(sys.executable)").Trim()
$version = (& $py -3.12 --version).Trim() -replace '^Python\s+', ''
$venv = Join-Path $VoiceRoot '.venv'
if (-not (Test-Path $venv)) { & $py -3.12 -m venv $venv }
$venvPy = Join-Path $venv 'Scripts\python.exe'
& $venvPy -m pip install --upgrade pip
& $venvPy -m pip install kokoro-onnx soundfile numpy
New-Item -ItemType Directory -Force -Path (Split-Path $StatePath -Parent) | Out-Null
[ordered]@{ executable=$venvPy; launcher=$base; version=$version; recorded_at=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content $StatePath -Encoding UTF8
