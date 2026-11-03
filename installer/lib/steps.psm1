Set-StrictMode -Version Latest

function Get-JarvisStepPrompt {
    param([int]$Number, [string]$Root)
    $names = @{ 4='04-plan-crew.txt'; 6='06-team-awareness.txt'; 10='10-first-words.txt'; 14='14-data-survey.txt'; 43='43-final-verification.txt' }
    if ($names.ContainsKey($Number)) { Join-Path $Root ("prompts\$($names[$Number])") } else { $null }
}

function Invoke-JarvisStepAction {
    param([int]$Number, [psobject]$Paths, [string]$Root, [psobject]$Form, [switch]$DryRun, [int]$TimeoutMinutes = 25)
    $prompt = Get-JarvisStepPrompt -Number $Number -Root $Root
    if ($prompt) {
        if ($DryRun -and -not $env:JARVIS_DRYRUN_HERMES) { Write-Output "DRY-RUN: owner/agent self-check $Number using $([IO.Path]::GetFileName($prompt))"; return }
        Write-Host "Don't post in the Telegram group until this step finishes."
        $hermes = if ($env:JARVIS_DRYRUN_HERMES) { $env:JARVIS_DRYRUN_HERMES } else { 'hermes' }
        $logPath = if ($DryRun) { Join-Path $Paths.StateRoot 'dryrun-agent.log' } else { Join-Path $env:LOCALAPPDATA 'hermes\logs\agent.log' }
        $response = Invoke-JarvisAgentTurn -PromptFile $prompt -Profile 'default' -Hermes $hermes -WorkDirectory $Paths.HermesHome -StepNumber $Number -TimeoutMinutes $TimeoutMinutes -LogPath $logPath -SkipOllamaCheck:$DryRun
        if ($DryRun) { Write-Output "DRY-RUN: stub Hermes turn completed for step $Number"; return }
        New-Item -ItemType Directory -Force -Path $Paths.StateRoot | Out-Null
        Write-JarvisUtf8Text -Path (Join-Path $Paths.StateRoot ("agent-turn-{0:D2}.txt" -f $Number)) -Text $response
        $lastLine = @($response -split "`r?`n" | Where-Object { $_.Trim() })[-1]
        if ($lastLine -match '\?\s*$') { throw "Agent ended step $Number with a question instead of doing the work. Answer it in $([IO.Path]::GetFullPath($prompt)), then rerun." }
    }
}

function Test-JarvisStepPostCheck {
    param([int]$Number, [psobject]$Paths, [string]$Root, [switch]$DryRun)
    if ($DryRun) { return $true }
    $userMemory = Join-Path $Paths.HermesHome 'memories\USER.md'
    $memory = Join-Path $Paths.HermesHome 'memories\MEMORY.md'
    switch ($Number) {
        1 { return (Test-Path $userMemory) -and (Test-Path $memory) -and ((Read-JarvisUtf8Text $userMemory).Trim().Length -gt 0) }
        2 { return (Read-JarvisUtf8Text $userMemory) -match 'Interview answers:' -and (Read-JarvisUtf8Text $userMemory) -match 'Open questions:' }
        3 {
            $text = Read-JarvisUtf8Text $memory
            foreach ($heading in @('PROGRESS','APPROVAL','COMMUNICATION','DELEGATION','BLOCKED COMMANDS','PERSONAL AUTHORITY')) { if ($text -notmatch [regex]::Escape($heading)) { return $false } }
            return $true
        }
        4 { $turn = Join-Path $Paths.StateRoot 'agent-turn-04.txt'; $text = if (Test-Path $turn) { Read-JarvisUtf8Text $turn } else { '' }; return $text -match 'JARVIS' -and $text -match 'dev' -and $text -match 'research' -and $text -match 'assistant' }
        5 { return @('dev','research','assistant' | Where-Object { -not (Test-Path (Join-Path $Paths.HermesHome "profiles\$_\SOUL.md")) }).Count -eq 0 }
        6 { $turn = Join-Path $Paths.StateRoot 'agent-turn-06.txt'; $text = if (Test-Path $turn) { Read-JarvisUtf8Text $turn } else { '' }; return $text -match 'JARVIS' -and $text -match 'DEV' -and $text -match 'RESEARCH' -and $text -match 'ASSISTANT' }
        7 {
            if (-not (Test-Path (Join-Path $Paths.StateRoot 'telegram.json'))) { return $false }
             $telegram = Read-JarvisUtf8Text (Join-Path $Paths.StateRoot 'telegram.json') | ConvertFrom-Json
            return -not [string]::IsNullOrWhiteSpace([string]$telegram.chat_id) -and @($telegram.topics.PSObject.Properties).Count -eq 3
        }
        8 {
            foreach ($profile in @('dev','research','assistant')) {
                $envFile = Join-Path $Paths.HermesHome "profiles\$profile\.env"
                $config = Join-Path $Paths.HermesHome "profiles\$profile\config.yaml"
                if ((Test-Path $envFile) -and (Read-JarvisUtf8Text $envFile) -match 'TELEGRAM_BOT_TOKEN=') { return $false }
                if ((Test-Path $config) -and (Read-JarvisUtf8Text $config) -match '(?m)^platforms:') { return $false }
            }
            return $true
        }
        9 { $config = Join-Path $Paths.HermesHome 'config.yaml'; return (Test-Path (Join-Path $Paths.HermesHome 'plugins\telegram_topic_profiles\plugin.yaml')) -and (Test-Path (Join-Path $Paths.HermesHome 'plugins\telegram_topic_profiles\topics.json')) -and (Test-Path $config) -and ((Read-JarvisUtf8Text $config) -match 'multiplex_profiles') }
        10 { $turn = Join-Path $Paths.StateRoot 'agent-turn-10.txt'; $text = if (Test-Path $turn) { Read-JarvisUtf8Text $turn } else { '' }; return $text -match 'DEV' -and $text -match 'RESEARCH' -and $text -match 'ASSISTANT' -and $text -match 'works|failed' }
        11 { $db = Join-Path $Paths.ProjectRoot 'agent-logs.db'; return (Test-Path $db) -and ((Get-Item $db).Length -gt 0) }
        12 {
            $rows = @(Get-JarvisActivity -DatabasePath (Join-Path $Paths.ProjectRoot 'agent-logs.db'))
            $names = @($rows | ForEach-Object { $_.agent_name })
            if ((@('JARVIS','DEV','RESEARCH','ASSISTANT' | Where-Object { $names -contains $_ }).Count -ne 4)) { return $false }
            foreach ($profile in @('default','dev','research','assistant')) {
                $memoryFile = if ($profile -eq 'default') { Join-Path $Paths.HermesHome 'memories\MEMORY.md' } else { Join-Path $Paths.HermesHome "profiles\$profile\memories\MEMORY.md" }
                if (-not (Test-Path $memoryFile) -or (Read-JarvisUtf8Text $memoryFile) -notmatch 'log-task') { return $false }
            }
            return $true
        }
        default { return $false }
    }
}

function Test-JarvisStepPreCheck {
    param([int]$Number, [psobject]$Paths, [switch]$DryRun)
    if ($DryRun) { return $true }
    if (-not (Test-Path -LiteralPath $Paths.HermesHome)) { return $false }
    switch ($Number) {
        1 { return Test-Path (Join-Path $Paths.HermesHome 'memories') }
        5 { return Test-Path $Paths.HermesHome }
        7 { return Test-Path (Join-Path $Paths.HermesHome '.env') }
        default { return $true }
    }
}

Export-ModuleMember -Function *-Jarvis*
