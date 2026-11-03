Set-StrictMode -Version Latest

function Get-JarvisPaths {
    param(
        [string]$HermesHome = $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }),
        [string]$StateRoot = $(Join-Path $PSScriptRoot '..\state')
    )
    $hermesRoot = [IO.Path]::GetFullPath($HermesHome)
    $state = [IO.Path]::GetFullPath($StateRoot)
    [pscustomobject]@{
        HermesHome = $hermesRoot
        StateRoot = $state
        BackupRoot = Join-Path (Split-Path $hermesRoot -Parent) 'jarvis-mission-control-backups'
        ProjectRoot = Join-Path (Split-Path $hermesRoot -Parent) 'jarvis-mission-control'
        SecretsRoot = Join-Path $env:LOCALAPPDATA 'jarvis-secrets'
        VoiceRoot = Join-Path $env:LOCALAPPDATA 'jarvis-voice'
    }
}

function Format-JarvisSecret {
    param([string]$Name, [AllowEmptyString()][string]$Value)
    "$Name=<redacted; length $($Value.Length)>"
}

function Test-JarvisPortFree {
    param([int]$Port, [string]$Address = '127.0.0.1')
    $client = New-Object Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($Address, $Port)
        if (-not $task.Wait(250)) { return $true }
        return -not $task.Result
    } catch { return $true } finally { $client.Dispose() }
}

function Test-JarvisRequiredProcesses {
    param([string[]]$Names = @('paperclip', 'postgres', 'ollama'))
    foreach ($name in $Names) {
        if (-not (Get-Process -Name $name -ErrorAction SilentlyContinue)) { return $false }
    }
    $true
}

function Invoke-JarvisHermesCommand {
    param([string]$Hermes = $(if ($env:JARVIS_HERMES_CLI) { $env:JARVIS_HERMES_CLI } else { 'hermes' }), [string[]]$Arguments, [string]$WorkingDirectory = $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }))
    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) { throw "Hermes working directory does not exist: $WorkingDirectory" }
    $output = @(& $Hermes @Arguments 2>&1)
    [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE; Arguments = $Arguments }
}

function Assert-JarvisHermesCommand {
    param([psobject]$Result, [string]$Label)
    if ($Result.ExitCode -ne 0) { throw "$Label failed (exit code $($Result.ExitCode)): $($Result.Output -join [Environment]::NewLine)" }
    $true
}

function Get-JarvisGatewayPid {
    param([object[]]$Output)
    $text = $Output -join [Environment]::NewLine
    if ($text -match '(?i)Gateway process running.*?PID\D+(\d+)') { return [int]$Matches[1] }
    $null
}

function Wait-JarvisGatewayRestart {
    param([string]$Hermes = $(if ($env:JARVIS_HERMES_CLI) { $env:JARVIS_HERMES_CLI } else { 'hermes' }), [string]$WorkingDirectory = $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }), [int]$PreviousPid, [int]$TimeoutSeconds = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $status = Invoke-JarvisHermesCommand -Hermes $Hermes -Arguments @('gateway','status') -WorkingDirectory $WorkingDirectory
        $pid = Get-JarvisGatewayPid -Output $status.Output
        if ($status.ExitCode -eq 0 -and $pid -and (($PreviousPid -eq 0) -or ($pid -ne $PreviousPid))) { return $pid }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    throw "Hermes gateway did not report 'Gateway process running' with a new PID within $TimeoutSeconds seconds. Previous PID: $PreviousPid. Last output: $($status.Output -join [Environment]::NewLine)"
}

function Write-JarvisUtf8Text {
    param([string]$Path, [AllowEmptyString()][string]$Text)
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Read-JarvisUtf8Text {
    param([string]$Path)
    [IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding($false)))
}

function Get-JarvisHermesPython {
    param([string]$HermesHome = $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }))
    $tools = Join-Path $HermesHome 'tools'
    $python = Get-ChildItem -LiteralPath $tools -Filter 'python.exe' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { (Split-Path $_.DirectoryName -Leaf) -like 'python-*' } | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $python) { throw "Hermes bundled Python was not found under $tools." }
    $python.FullName
}

function Test-JarvisHermesYaml {
    param([string]$Path, [string]$PythonPath)
    if (-not $PythonPath) { $PythonPath = Get-JarvisHermesPython }
    $output = & $PythonPath -c "import sys, yaml; yaml.safe_load(open(sys.argv[1], encoding='utf-8'))" $Path 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join [Environment]::NewLine) }
    $true
}

function Invoke-JarvisSpecialistProfileCleanup {
    param([string]$ProfileDir, [string]$BackupRoot, [string]$RelativeTo, [string]$Timestamp = $(Get-Date -Format 'yyyyMMdd-HHmmss'), [string]$PythonPath, [string]$UndoPath)
    $envFile = Join-Path $ProfileDir '.env'
    if (Test-Path -LiteralPath $envFile) {
        $raw = Read-JarvisUtf8Text $envFile
        $clean = [regex]::Replace($raw, '(?m)^TELEGRAM_BOT_TOKEN=.*(?:\r?\n|$)', '')
        if ($clean -cne $raw) { Backup-JarvisFile $envFile $BackupRoot -Timestamp $Timestamp -RelativeTo $RelativeTo -UndoPath $UndoPath | Out-Null; Write-JarvisUtf8Text $envFile $clean }
    }
    $configFile = Join-Path $ProfileDir 'config.yaml'
    if (Test-Path -LiteralPath $configFile) {
        $raw = Read-JarvisUtf8Text $configFile
        $clean = [regex]::Replace($raw, '(?ms)^platforms:\s*\n(?:^[ \t]+.*\n?)+', '')
        if ($clean -cne $raw) {
            $backup = Backup-JarvisFile $configFile $BackupRoot -Timestamp $Timestamp -RelativeTo $RelativeTo -UndoPath $UndoPath
            try {
                Write-JarvisUtf8Text $configFile $clean
                Test-JarvisHermesYaml -Path $configFile -PythonPath $PythonPath | Out-Null
            } catch {
                Copy-Item -LiteralPath $backup -Destination $configFile -Force
                throw "Hermes could not parse $configFile after step 8 cleanup: $($_.Exception.Message)"
            }
        }
    }
}

function Test-JarvisOllamaReady {
    param([object[]]$Processes, [string[]]$Tags)
    if (@($Processes).Count -eq 0) { return [pscustomobject]@{ Ready = $false; Message = "Ollama isn't running. Start the Ollama app once, then rerun." } }
    if (@($Processes).Count -gt 1) { return [pscustomobject]@{ Ready = $false; Message = "Two Ollama servers are running. Close the extra one (keep the Ollama app), then rerun. PIDs: $(@($Processes | ForEach-Object Id) -join ', ')" } }
    if (@($Tags) -notcontains 'gpt-oss:20b') { return [pscustomobject]@{ Ready = $false; Message = 'Ollama is answering, but gpt-oss:20b is not listed by /api/tags.' } }
    [pscustomobject]@{ Ready = $true; Message = '' }
}

function Get-JarvisModelTimeoutMessage {
    param([int]$Step, [int]$Minutes)
    "Step $Step exceeded the $Minutes minute model time limit; its Hermes process was ended. Progress was not advanced. Rerun to resume at step $Step."
}

function Format-JarvisModelHeartbeat {
    param([int]$Step, [timespan]$Elapsed)
    "Step $Step, elapsed $($Elapsed.ToString('hh\:mm\:ss')), waiting on model"
}

function Get-JarvisPostCheckFailureMessage {
    param([int]$Step, [AllowEmptyString()][string]$Output)
    $sample = if ($Output.Length -gt 500) { $Output.Substring(0, 500) } else { $Output }
    "Step $Step post-check failed; first 500 characters of agent output: $sample"
}

function Save-JarvisProgress {
    param([string]$Path, [int[]]$Completed = @(), [int]$Current = 1)
    $parent = Split-Path $Path -Parent
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $existing = @()
    if (Test-Path -LiteralPath $Path) {
        try { $existing = @((Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json).completed) } catch { $existing = @() }
    }
    $merged = @($existing + $Completed | Sort-Object -Unique | ForEach-Object { [int]$_ })
    $payload = [ordered]@{ version = 1; completed = $merged; current = $Current; updated_at = [DateTime]::UtcNow.ToString('o') }
    $tmp = "$Path.tmp"
    $payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-JarvisProgress {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ completed = @(); current = 1 } }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Backup-JarvisFile {
    param([string]$Path, [string]$BackupRoot, [string]$Timestamp = $(Get-Date -Format 'yyyyMMdd-HHmmss'), [string]$UndoPath, [string]$RelativeTo)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $target = Join-Path $BackupRoot $Timestamp
    $relative = if ($RelativeTo) { $Path.Substring(([IO.Path]::GetFullPath($RelativeTo)).Length).TrimStart('\','/') } else { Split-Path $Path -Leaf }
    $destination = Join-Path $target $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    Copy-Item -LiteralPath $Path -Destination $destination -Force
    if ($UndoPath) {
        $safeDestination = $destination.Replace("'", "''")
        $safePath = $Path.Replace("'", "''")
        Write-JarvisUndo -Path $UndoPath -Line "Copy-Item -LiteralPath '$safeDestination' -Destination '$safePath' -Force"
    }
    $destination
}

function Write-JarvisUndo {
    param([string]$Path, [string]$Line)
    $parent = Split-Path $Path -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Add-Content -LiteralPath $Path -Value $Line -Encoding UTF8
}

function Invoke-JarvisUndoFile {
    param([string]$Path, [string]$ScheduledTasks = $(if ($env:JARVIS_SCHTASKS) { $env:JARVIS_SCHTASKS } else { 'schtasks.exe' }))
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $lines = @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
    [array]::Reverse($lines)
    foreach ($line in $lines) {
        if ($line -match "^Copy-Item -LiteralPath '((?:''|[^'])*)' -Destination '((?:''|[^'])*)' -Force$") {
            $source = $Matches[1].Replace("''", "'")
            $destination = $Matches[2].Replace("''", "'")
            if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination $destination -Force }
        } elseif ($line -match "^Remove-Item -LiteralPath '((?:''|[^'])*)' -Force -ErrorAction SilentlyContinue$") {
            $target = $Matches[1].Replace("''", "'")
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue }
        } elseif ($line -eq "Unregister-JarvisScheduledTask -TaskName 'JARVIS Mission Control'") {
            & $ScheduledTasks /Delete /TN 'JARVIS Mission Control' /F | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Could not remove the JARVIS Mission Control scheduled task (exit code $LASTEXITCODE)." }
        } elseif ($line -match "^Register-JarvisScheduledTask -TaskName 'JARVIS Mission Control' -XmlPath '((?:''|[^'])*)'$") {
            $xmlPath = $Matches[1].Replace("''", "'")
            if (-not (Test-Path -LiteralPath $xmlPath -PathType Leaf)) { throw "Scheduled task undo XML is missing: $xmlPath" }
            & $ScheduledTasks /Create /TN 'JARVIS Mission Control' /XML $xmlPath /F | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Could not restore the JARVIS Mission Control scheduled task (exit code $LASTEXITCODE)." }
        } else {
            throw "Unsupported undo entry: $line"
        }
    }
}

Export-ModuleMember -Function *-Jarvis*
