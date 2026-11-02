Set-StrictMode -Version Latest

function Select-JarvisVoicePython {
    param([string]$Python312, [string]$DefaultPython)
    if ($Python312) { return [pscustomobject]@{ Executable = $Python312; Version = '3.12' } }
    if ($DefaultPython -and $DefaultPython -notmatch '3\.14') { return [pscustomobject]@{ Executable = $DefaultPython; Version = 'detected' } }
    throw 'Kokoro requires Python 3.12; install it with py -3.12 or uv.'
}

function Save-JarvisVoiceRuntime {
    param([string]$Path, [string]$Executable, [string]$Version)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    [ordered]@{ executable = $Executable; version = $Version; recorded_at = [DateTime]::UtcNow.ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Install-JarvisVoiceRuntime {
    param([string]$VoiceRoot, [string]$StatePath, [string]$SourceServer)
    $python = (Get-Command py -ErrorAction Stop).Source
    $exe = (& $python -3.12 -c "import sys; print(sys.executable)").Trim()
    $version = (& $python -3.12 --version).Trim() -replace '^Python\s+', ''
    $venv = Join-Path $VoiceRoot '.venv'
    if (-not (Test-Path $venv)) { & $python -3.12 -m venv $venv }
    $venvPython = Join-Path $venv 'Scripts\python.exe'
    if ($SourceServer) { Copy-Item $SourceServer (Join-Path $VoiceRoot 'voice-server.py') -Force }
    Save-JarvisVoiceRuntime -Path $StatePath -Executable $venvPython -Version $version
    [pscustomobject]@{ Executable = $venvPython; Version = $version; Venv = $venv }
}

function Register-JarvisVoiceTask {
    param([string]$VoiceRoot, [string]$PythonExecutable)
    & schtasks.exe /Create /TN 'JARVIS Local Voice' /SC ONLOGON /TR "`"$PythonExecutable`" `"$VoiceRoot\voice-server.py`"" /F | Out-Null
}

Export-ModuleMember -Function *-Jarvis*
