Set-StrictMode -Version Latest

function Get-JarvisCrew {
    @(
        [pscustomobject]@{ key='default'; name='JARVIS'; code='J-00'; initials='JV'; role='Chief of staff'; tagline='Routes, verifies, reports' },
        [pscustomobject]@{ key='dev'; name='DEV'; code='J-01'; initials='DV'; role='Build engineer'; tagline='Makes the machine useful' },
        [pscustomobject]@{ key='research'; name='RESEARCH'; code='J-02'; initials='RS'; role='Research lead'; tagline='Evidence before confidence' },
        [pscustomobject]@{ key='assistant'; name='ASSISTANT'; code='J-03'; initials='AS'; role='Executive assistant'; tagline='Quietly keeps the day moving' }
    )
}

function Get-JarvisStepDefinitions {
    $agentSteps = @(4, 6, 13, 14, 19, 20, 21, 22, 23, 26, 29, 30, 31, 32, 33, 34, 35, 38, 40, 42, 43)
    foreach ($number in 1..48) {
        $kind = if ($agentSteps -contains $number) { 'agent-or-deterministic' } elseif ($number -in @(7,10,24,28,36,37,41,44)) { 'interactive' } else { 'deterministic' }
        [pscustomobject]@{ Number=$number; Kind=$kind; PreCheck="Test-JarvisStepPreCheck $number"; Action="Invoke-JarvisStepAction $number"; PostCheck="Test-JarvisStepPostCheck $number" }
    }
}

function Assert-JarvisUploadName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -match '[\\/]' -or $Name -match '\.\.' -or $Name -match '[:*?"<>|]' -or $Name.EndsWith('.') -or $Name.EndsWith(' ')) { throw 'Invalid upload filename' }
    if ([IO.Path]::GetExtension($Name).ToLowerInvariant() -notin @('.html','.png','.jpg','.jpeg','.webp','.svg')) { throw 'Unsupported upload extension' }
    $true
}

function Assert-JarvisDashboardPythonVersion {
    param([Parameter(Mandatory=$true)][string]$Version)
    $parsed = $null
    if (-not [version]::TryParse($Version, [ref]$parsed) -or $parsed -lt [version]'3.9' -or $parsed.Major -ge 4) { throw "Dashboard Python must be a supported Python 3.9 or newer interpreter; found '$Version'." }
    $true
}

function Resolve-JarvisDashboardPython {
    param([string]$PythonExecutable, [string]$HermesHome = $env:HERMES_HOME)
    $candidate = $PythonExecutable
    if (-not $candidate -and $env:JARVIS_PYTHON) { $candidate = $env:JARVIS_PYTHON }
    if (-not $candidate -and $HermesHome) {
        try { $candidate = Get-JarvisHermesPython -HermesHome $HermesHome } catch { $candidate = $null }
    }
    if (-not $candidate) {
        $launcher = Get-Command py -ErrorAction SilentlyContinue
        if ($launcher) {
            $candidate = (& $launcher.Source -3.12 -c 'import sys; print(sys.executable)' 2>$null | Select-Object -First 1)
        }
    }
    if (-not $candidate) {
        $command = Get-Command python -ErrorAction SilentlyContinue
        if ($command) { $candidate = $command.Source }
    }
    if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw 'A concrete dashboard Python interpreter could not be resolved.' }
    $versionOutput = @(& $candidate --version 2>&1)
    if ($LASTEXITCODE -ne 0 -or $versionOutput.Count -ne 1 -or $versionOutput[0] -notmatch '^Python\s+(.+)$') { throw "Dashboard Python version verification failed for '$candidate'." }
    $version = $Matches[1]
    $pathOutput = @(& $candidate -c 'import sys; print(sys.executable)' 2>&1)
    if ($LASTEXITCODE -ne 0 -or $pathOutput.Count -ne 1) { throw "Dashboard Python path verification failed for '$candidate'." }
    $resolved = [IO.Path]::GetFullPath([string]$pathOutput[0])
    Assert-JarvisDashboardPythonVersion -Version $version | Out-Null
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Verified dashboard Python path does not exist: $resolved" }
    [pscustomobject]@{ Executable=$resolved; Version=$version }
}

function Copy-JarvisDashboardAsset {
    param([string]$Source, [string]$Destination, [string]$BackupRoot, [string]$UndoPath, [string]$RelativeTo)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Dashboard source asset is missing: $Source" }
    $parent = Split-Path $Destination -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    if (Test-Path -LiteralPath $Destination) {
        Backup-JarvisFile -Path $Destination -BackupRoot $BackupRoot -RelativeTo $RelativeTo -UndoPath $UndoPath | Out-Null
    } elseif ($UndoPath) {
        $safeDestination = $Destination.Replace("'", "''")
        Write-JarvisUndo -Path $UndoPath -Line "Remove-Item -LiteralPath '$safeDestination' -Force -ErrorAction SilentlyContinue"
    }
    $temporary = Join-Path $parent ('.jarvis-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Copy-Item -LiteralPath $Source -Destination $temporary
        Move-Item -LiteralPath $temporary -Destination $Destination -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Install-JarvisDashboardRuntime {
    param([string]$ProjectRoot, [string]$DashboardRoot, [string]$BackupRoot, [string]$UndoPath, [psobject]$Runtime)
    New-Item -ItemType Directory -Force -Path $ProjectRoot | Out-Null
    foreach ($key in @('default','dev','research','assistant')) { New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot "content\$key") | Out-Null }
    foreach ($file in @('server.py','upload.html')) {
        Copy-JarvisDashboardAsset (Join-Path $DashboardRoot $file) (Join-Path $ProjectRoot $file) $BackupRoot $UndoPath $ProjectRoot
    }
    $versionPath = Join-Path $ProjectRoot 'version.txt'
    if (-not (Test-Path -LiteralPath $versionPath)) {
        [IO.File]::WriteAllText($versionPath, "v0.1`n", (New-Object Text.UTF8Encoding($false)))
        if ($UndoPath) { Write-JarvisUndo -Path $UndoPath -Line "Remove-Item -LiteralPath '$($versionPath.Replace("'", "''"))' -Force -ErrorAction SilentlyContinue" }
    }
    $runtimePath = Join-Path $ProjectRoot 'dashboard-runtime.json'
    if (Test-Path -LiteralPath $runtimePath) {
        Backup-JarvisFile -Path $runtimePath -BackupRoot $BackupRoot -RelativeTo $ProjectRoot -UndoPath $UndoPath | Out-Null
    } elseif ($UndoPath) {
        Write-JarvisUndo -Path $UndoPath -Line "Remove-Item -LiteralPath '$($runtimePath.Replace("'", "''"))' -Force -ErrorAction SilentlyContinue"
    }
    $runtimeJson = [ordered]@{ executable=$Runtime.Executable; version=$Runtime.Version; recorded_at=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json
    $runtimeTemp = "$runtimePath.tmp"
    [IO.File]::WriteAllText($runtimeTemp, $runtimeJson, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $runtimeTemp -Destination $runtimePath -Force
}

function Install-JarvisDashboardTemplate {
    param([string]$ProjectRoot, [string]$DashboardRoot, [string]$BackupRoot, [string]$UndoPath)
    Copy-JarvisDashboardAsset (Join-Path $DashboardRoot 'jarvis-dashboard-template.html') (Join-Path $ProjectRoot 'jarvis-dashboard-template.html') $BackupRoot $UndoPath $ProjectRoot
}

function Install-JarvisDashboardShell {
    param([string]$ProjectRoot, [string]$DashboardRoot, [string]$BackupRoot, [string]$UndoPath)
    foreach ($file in @('index.html','styles.css','script.js','favicon.svg')) {
        Copy-JarvisDashboardAsset (Join-Path $DashboardRoot $file) (Join-Path $ProjectRoot $file) $BackupRoot $UndoPath $ProjectRoot
    }
}

function New-JarvisDashboardTaskXml {
    param([string]$ProjectRoot, [string]$PythonExecutable)
    $command = [Security.SecurityElement]::Escape([IO.Path]::GetFullPath($PythonExecutable))
    $script = [Security.SecurityElement]::Escape('"' + (Join-Path ([IO.Path]::GetFullPath($ProjectRoot)) 'server.py') + '"')
    $user = [Security.SecurityElement]::Escape([Security.Principal.WindowsIdentity]::GetCurrent().Name)
    [xml]@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers><LogonTrigger><Enabled>true</Enabled></LogonTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>$user</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><StartWhenAvailable>true</StartWhenAvailable><RestartOnFailure><Interval>PT1M</Interval><Count>3</Count></RestartOnFailure><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Enabled>true</Enabled></Settings>
  <Actions Context="Author"><Exec><Command>$command</Command><Arguments>$script</Arguments><WorkingDirectory>$([Security.SecurityElement]::Escape([IO.Path]::GetFullPath($ProjectRoot)))</WorkingDirectory></Exec></Actions>
</Task>
"@
}

function Register-JarvisDashboardTask {
    param([string]$ProjectRoot, [string]$PythonExecutable, [string]$BackupRoot, [string]$UndoPath)
    $xmlPath = Join-Path $ProjectRoot 'dashboard.task.xml'
    $xml = New-JarvisDashboardTaskXml -ProjectRoot $ProjectRoot -PythonExecutable $PythonExecutable
    $previousTaskXml = $null
    if (Test-Path -LiteralPath $xmlPath) {
        $previousTaskXml = Backup-JarvisFile -Path $xmlPath -BackupRoot $BackupRoot -RelativeTo $ProjectRoot -UndoPath $UndoPath
    } elseif ($UndoPath) {
        Write-JarvisUndo -Path $UndoPath -Line "Remove-Item -LiteralPath '$($xmlPath.Replace("'", "''"))' -Force -ErrorAction SilentlyContinue"
    }
    $xmlTemporary = "$xmlPath.tmp"
    $xml.Save($xmlTemporary)
    Move-Item -LiteralPath $xmlTemporary -Destination $xmlPath -Force
    $schtasks = if ($env:JARVIS_SCHTASKS) { $env:JARVIS_SCHTASKS } else { 'schtasks.exe' }
    & $schtasks /Create /TN 'JARVIS Mission Control' /XML $xmlPath /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Task Scheduler rejected the dashboard task definition (exit code $LASTEXITCODE)." }
    & $schtasks /Run /TN 'JARVIS Mission Control' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Task Scheduler could not start the dashboard task (exit code $LASTEXITCODE)." }
    if ($UndoPath) {
        if ($previousTaskXml) {
            Write-JarvisUndo -Path $UndoPath -Line "Register-JarvisScheduledTask -TaskName 'JARVIS Mission Control' -XmlPath '$($previousTaskXml.Replace("'", "''"))'"
        } else {
            Write-JarvisUndo -Path $UndoPath -Line "Unregister-JarvisScheduledTask -TaskName 'JARVIS Mission Control'"
        }
    }
    $xmlPath
}

function Test-JarvisDashboardTaskXml {
    param([string]$Path, [string]$RuntimePath, [string]$ProjectRoot)
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or -not (Test-Path -LiteralPath $RuntimePath -PathType Leaf)) { return $false }
        [xml]$xml = Get-Content -LiteralPath $Path -Raw
        $runtime = Get-Content -LiteralPath $RuntimePath -Raw | ConvertFrom-Json
        Assert-JarvisDashboardPythonVersion -Version ([string]$runtime.version) | Out-Null
        return $xml.Task.Settings.RestartOnFailure.Interval -eq 'PT1M' -and [int]$xml.Task.Settings.RestartOnFailure.Count -ge 1 -and
            $xml.Task.Actions.Exec.Command -eq $runtime.executable -and $xml.Task.Actions.Exec.Arguments -eq ('"' + (Join-Path $ProjectRoot 'server.py') + '"')
    } catch { return $false }
}

function Test-JarvisDashboardTaskRegistered {
    $schtasks = if ($env:JARVIS_SCHTASKS) { $env:JARVIS_SCHTASKS } else { 'schtasks.exe' }
    & $schtasks /Query /TN 'JARVIS Mission Control' | Out-Null
    return $LASTEXITCODE -eq 0
}

function Test-JarvisDashboardRuntime {
    param([string]$ProjectRoot, [int]$Port = 8899, [int]$RequestCount = 200, [int]$StartupTimeoutSeconds = 20)
    try {
        $runtime = Get-Content -LiteralPath (Join-Path $ProjectRoot 'dashboard-runtime.json') -Raw | ConvertFrom-Json
        $serverPath = Join-Path $ProjectRoot 'server.py'
        $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
        do {
            try { $first = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/state" -TimeoutSec 2; break } catch { Start-Sleep -Milliseconds 250 }
        } while ((Get-Date) -lt $deadline)
        if (-not $first) { return $false }
        foreach ($key in @('crew','ops','sessions','heatmap','hourly','hourly_peak','box','gateway','events','alerts','capabilities','version')) {
            if ($first.PSObject.Properties.Name -notcontains $key) { return $false }
        }
        if (@($first.crew).Count -ne 4) { return $false }
        foreach ($agent in @($first.crew)) {
            foreach ($key in @('key','name','code','initials','role','tagline','state','model','channel','telegram','reachable','share','sessions','messages','tokens','tasks','failed','events','hourly','mix')) {
                if ($agent.PSObject.Properties.Name -notcontains $key) { return $false }
            }
        }
        $process = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { $_.ExecutablePath -eq $runtime.executable -and $_.CommandLine -and $_.CommandLine.Contains($serverPath) }) | Select-Object -First 1
        if (-not $process) { return $false }
        $before = (Get-Process -Id $process.ProcessId -ErrorAction Stop).HandleCount
        foreach ($request in 1..$RequestCount) { Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/state" -TimeoutSec 2 | Out-Null }
        $after = (Get-Process -Id $process.ProcessId -ErrorAction Stop).HandleCount
        if (($after - $before) -gt 4) { return $false }
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop)
        return $listeners.Count -gt 0 -and @($listeners | Where-Object { $_.LocalAddress -notin @('127.0.0.1','::1') }).Count -eq 0
    } catch { return $false }
}

function Install-JarvisDashboardBackup {
    param([string]$ProjectRoot, [string]$DashboardRoot, [string]$BackupRoot, [string]$UndoPath, [string]$StateRoot)
    Copy-JarvisDashboardAsset (Join-Path $DashboardRoot 'jarvis-backup.ps1') (Join-Path $ProjectRoot 'jarvis-backup.ps1') $BackupRoot $UndoPath $ProjectRoot
    $snapshot = & (Join-Path $ProjectRoot 'jarvis-backup.ps1') -Note 'pre-wiring baseline' -ProjectRoot $ProjectRoot -BackupRoot $BackupRoot
    $record = [ordered]@{ snapshot=[IO.Path]::GetFullPath($snapshot); note='pre-wiring baseline' } | ConvertTo-Json
    $recordPath = Join-Path $StateRoot 'step-18-backup.json'
    $temporary = "$recordPath.tmp"
    [IO.File]::WriteAllText($temporary, $record, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $recordPath -Force
    $snapshot
}

Export-ModuleMember -Function *-Jarvis*
