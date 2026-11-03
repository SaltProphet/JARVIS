Set-StrictMode -Version Latest

function Read-JarvisOwnerForm {
    param([switch]$SkipPrompt)
    if ($SkipPrompt) { return [pscustomobject]@{ name='Owner'; work='not provided yet'; timezone='UTC'; hours='not provided yet'; weather_city='not provided yet'; priority='not provided yet'; telegram_chat_id='-1000000000000'; interview=@('not provided yet') * 6 } }
    $answers = [ordered]@{}
    $answers.name = Read-Host 'Owner first name'
    $answers.work = Read-Host 'What do you do? One sentence'
    $answers.timezone = Read-Host 'IANA time zone (for example America/New_York)'
    $answers.hours = Read-Host 'Working hours'
    $answers.weather_city = Read-Host 'Weather city for the morning briefing'
    $answers.priority = Read-Host 'Crew purpose / top priority'
    $answers.telegram_chat_id = Read-Host 'Telegram group chat ID (leave blank to detect from getUpdates)'
    $answers.interview = @(
        (Read-Host '1/6 Build and deploy preferences'), (Read-Host '2/6 What should RESEARCH watch?'),
        (Read-Host '3/6 Apps and calendars that run the week'), (Read-Host '4/6 Who is owed replies?'),
        (Read-Host '5/6 What must never interrupt?'), (Read-Host '6/6 Anything else the crew should know?')
    )
    [pscustomobject]$answers
}

function Complete-JarvisOwnerForm {
    param([psobject]$Form, [string]$EnvFile, [switch]$DryRun)
    $result = [ordered]@{}
    foreach ($field in @('name','work','timezone','hours','weather_city','priority','telegram_chat_id')) {
        $result[$field] = if ($Form -and $Form.PSObject.Properties.Name -contains $field) { [string]$Form.$field } else { '' }
    }
    $result.interview = if ($Form) { @($Form.interview) } else { @() }
    if ($DryRun) {
        foreach ($field in @('name','work','timezone','hours','weather_city','priority','telegram_chat_id')) { if ([string]::IsNullOrWhiteSpace($result[$field])) { $result[$field] = if ($field -eq 'telegram_chat_id') { '-1000000000000' } else { 'not provided yet' } } }
        if (@($result.interview).Count -ne 6) { $result.interview = @('not provided yet') * 6 }
        return [pscustomobject]$result
    }
    foreach ($field in @('name','work','timezone','hours','weather_city','priority')) {
        if ([string]::IsNullOrWhiteSpace($result[$field])) { $result[$field] = Read-Host ("Owner form: $field") }
    }
    if (@($result.interview).Count -ne 6) {
        $result.interview = @(
            (Read-Host '1/6 Build and deploy preferences'), (Read-Host '2/6 What should RESEARCH watch?'),
            (Read-Host '3/6 Apps and calendars that run the week'), (Read-Host '4/6 Who is owed replies?'),
            (Read-Host '5/6 What must never interrupt?'), (Read-Host '6/6 Anything else the crew should know?')
        )
    } else {
        for ($i = 0; $i -lt 6; $i++) { if ([string]::IsNullOrWhiteSpace([string]$result.interview[$i])) { $result.interview[$i] = Read-Host ("$($i + 1)/6 missing interview answer") } }
    }
    if ([string]::IsNullOrWhiteSpace($result.telegram_chat_id)) {
        $token = Get-JarvisEnvValue -EnvFile $EnvFile -Name 'TELEGRAM_BOT_TOKEN'
        if ($token) {
            $candidate = Read-Host 'Telegram group chat ID [default -1003967974233; type detect to detect]'
            if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate = '-1003967974233' }
            if ($candidate -eq 'detect') {
                Write-Host 'Send any message in the Telegram group, then press Enter to detect it.'
                Read-Host 'Press Enter after sending the group message' | Out-Null
                $found = Get-JarvisTelegramGroupFromUpdates -Token $token
                if ($found) { $candidate = $found.id; Write-Host "Detected Telegram group: $($found.title) [$($found.id)]" }
            }
            if ($candidate) { $result.telegram_chat_id = Normalize-JarvisTelegramChatId -Token $token -ChatId $candidate }
        }
        if ([string]::IsNullOrWhiteSpace($result.telegram_chat_id)) { $result.telegram_chat_id = Read-Host 'Telegram group chat ID' }
    }
    [pscustomobject]$result
}

function Test-JarvisOwnerForm {
    param([psobject]$Form)
    if ($null -eq $Form) { return $false }
    foreach ($field in @('name','work','timezone','hours','weather_city','priority','telegram_chat_id')) {
        if ([string]::IsNullOrWhiteSpace([string]$Form.$field)) { return $false }
    }
    $answers = @($Form.interview)
    if ($answers.Count -ne 6) { return $false }
    foreach ($answer in $answers) {
        if ([string]::IsNullOrWhiteSpace([string]$answer)) { return $false }
    }
    $true
}

function Get-JarvisMissingOwnerFields {
    param([psobject]$Form)
    $missing = @()
    foreach ($field in @('name','work','timezone','hours','weather_city','priority','telegram_chat_id')) {
        if ($null -eq $Form -or $Form.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$Form.$field)) { $missing += $field }
    }
    $answers = @($Form.interview)
    if ($answers.Count -ne 6 -or @($answers | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) { $missing += 'interview' }
    $missing
}

function Write-JarvisMemoryEntry {
    param([string]$MemoryFile, [string]$Entry)
    New-Item -ItemType Directory -Force -Path (Split-Path $MemoryFile -Parent) | Out-Null
    $raw = if (Test-Path $MemoryFile) { Read-JarvisUtf8Text $MemoryFile } else { $null }
    $existing = if ($null -eq $raw) { '' } else { $raw.Trim() }
    if ($existing -notlike "*$Entry*") { Write-JarvisUtf8Text -Path $MemoryFile -Text (($existing, $Entry -join "`n§`n").Trim()) }
}

function Get-JarvisInstallerPrompt {
    param([string]$PromptFile, [int]$StepNumber, [switch]$Retry)
    $job = "ONE JOB: complete only installer step $StepNumber."
    $prompt = Read-JarvisUtf8Text -Path $PromptFile
    $suffix = @(
        'Do not review, read or describe config files.'
        'Do not answer a different question, use a resumed conversation, or do extra work.'
        'FINAL OUTPUT: follow the exact required output format stated in the step prompt.'
    )
    if ($Retry) { $suffix += 'Retry once now: follow the exact required output format and do not do anything else.' }
    "$job`n`n$prompt`n`n$($suffix -join "`n")"
}

function Get-JarvisInstallerToolset {
    param([int]$StepNumber)
    if ($StepNumber -eq 6) { return 'file' }
    'clarify'
}

function Invoke-JarvisAgentTurn {
    param([string]$PromptFile, [string]$Profile = 'default', [string]$Hermes = 'hermes', [string]$WorkDirectory, [int]$StepNumber = 0, [int]$TimeoutMinutes = 25, [string]$LogPath = $(Join-Path $env:LOCALAPPDATA 'hermes\logs\agent.log'), [switch]$SkipOllamaCheck, [switch]$Retry)
    if ([string]::IsNullOrWhiteSpace($WorkDirectory)) { $WorkDirectory = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' } }
    if (-not (Test-Path -LiteralPath $WorkDirectory -PathType Container)) { throw "Hermes work directory does not exist: $WorkDirectory" }
    $prompt = Get-JarvisInstallerPrompt -PromptFile $PromptFile -StepNumber $StepNumber -Retry:$Retry
    $turnWorkspace = Join-Path ([IO.Path]::GetTempPath()) ("jarvis-installer-step-{0}-{1}" -f $StepNumber, [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $turnWorkspace | Out-Null
    $quotedWorkspace = '"' + ([regex]::Replace($turnWorkspace, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
    $processArguments = @('--safe-mode', '--ignore-user-config', '--ignore-rules', '--model', 'gpt-oss:20b', '--reasoning', 'none', '-t', (Get-JarvisInstallerToolset -StepNumber $StepNumber), '--in', $quotedWorkspace)
    if ($Profile -ne 'default') { $processArguments += @('-p', $Profile) }
    $processArguments += @('-z', ('"' + ([regex]::Replace($prompt, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'))
    $outFile = [IO.Path]::GetTempFileName(); $errFile = [IO.Path]::GetTempFileName(); $started = Get-Date
    try {
        $process = Start-Process -FilePath $Hermes -ArgumentList ($processArguments -join ' ') -WorkingDirectory $WorkDirectory -RedirectStandardOutput $outFile -RedirectStandardError $errFile -PassThru
        $lastLogLength = 0; $nextHeartbeat = $started.AddSeconds(30)
        while (-not $process.HasExited) {
            Start-Sleep -Seconds 1
            $elapsed = (Get-Date) - $started
            if ((Get-Date) -ge $nextHeartbeat) { Write-Host (Format-JarvisModelHeartbeat -Step $StepNumber -Elapsed $elapsed); $nextHeartbeat = $nextHeartbeat.AddSeconds(30) }
            if (Test-Path $LogPath) { $log = Read-JarvisUtf8Text $LogPath; if ($log.Length -gt $lastLogLength) { $new = $log.Substring($lastLogLength); $lastLogLength = $log.Length; $new -split "`r?`n" | Where-Object { $_ -match 'APIConnectionError|Connection error|API call failed' } | ForEach-Object { Write-Host $_ } } }
            if (-not $SkipOllamaCheck) { try { Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 5 | Out-Null } catch { throw "Ollama stopped responding during step $StepNumber. Start it and rerun; the installer resumes at step $StepNumber." } }
            if ($elapsed.TotalMinutes -ge $TimeoutMinutes) { $process.Kill(); throw (Get-JarvisModelTimeoutMessage -Step $StepNumber -Minutes $TimeoutMinutes) }
        }
        $process.WaitForExit()
        $process.Refresh()
        $result = @(Get-Content -LiteralPath $outFile -Encoding UTF8; Get-Content -LiteralPath $errFile -Encoding UTF8)
        $exitCode = if ($null -eq $process.ExitCode) { 0 } else { [int]$process.ExitCode }
        if ($exitCode -ne 0) { throw "Hermes turn failed for ${Profile} (exit $exitCode): $($result -join ' ')" }
        $result -join [Environment]::NewLine
    } finally {
        Remove-Item $outFile,$errFile -Force -ErrorAction SilentlyContinue
        Remove-Item $turnWorkspace -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function *-Jarvis*
