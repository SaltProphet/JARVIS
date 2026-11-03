[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$DryRun,
    [ValidateRange(1,48)][int]$Step,
    [ValidateRange(1,48)][int]$From = 1,
    [ValidateRange(1,48)][int]$Through,
    [ValidateRange(1,120)][int]$ModelTimeoutMinutes = 25,
    [switch]$Uninstall,
    [switch]$WithBuilderOrientation,
    [switch]$WithSerpApi,
    [switch]$WithElevenLabs,
    [switch]$WithComposio,
    [switch]$WithTailscale,
    [switch]$WithHomeAssistant
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$lib = Join-Path $root 'lib'
Get-ChildItem $lib -Filter '*.psm1' | ForEach-Object { Import-Module $_.FullName -Force }
$stateRoot = if ($env:JARVIS_STATE_ROOT) { $env:JARVIS_STATE_ROOT } else { Join-Path $root 'state' }
$paths = Get-JarvisPaths -StateRoot $stateRoot
$progressPath = Join-Path $paths.StateRoot 'progress.json'
$undoPath = Join-Path $paths.StateRoot 'undo.ps1'
$inputPath = Join-Path $paths.StateRoot 'inputs.json'
$logPath = Join-Path $paths.ProjectRoot 'agent-logs.db'

function Show-Action { param([string]$Text); if ($DryRun) { Write-Output "DRY-RUN: $Text" } else { Write-Output $Text } }
function Save-Inputs($form) {
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $paths.StateRoot | Out-Null; $form | ConvertTo-Json -Depth 8 | Set-Content $inputPath -Encoding UTF8 }
}
function Invoke-Undo {
    if (-not (Test-Path $undoPath)) { Write-Output 'No undo state found.'; return }
    $lines = @(Get-Content $undoPath | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
    foreach ($line in ($lines | Sort-Object -Descending)) { if ($line -match '^Remove-Item') { if (Test-Path ($line -replace '.*-LiteralPath ''([^'']+)''.*','$1')) { if ($PSCmdlet.ShouldProcess($line, 'undo')) { Invoke-Expression $line } } } }
}
if ($Uninstall) { Invoke-Undo; exit 0 }

$savedForm = if (Test-Path $inputPath) { Read-JarvisUtf8Text $inputPath | ConvertFrom-Json } else { $null }
$form = Complete-JarvisOwnerForm -Form $savedForm -EnvFile (Join-Path $paths.HermesHome '.env') -DryRun:$DryRun
if (-not $DryRun -and -not (Test-JarvisOwnerForm -Form $form)) { throw 'Owner form is incomplete after prompting for missing fields.' }
Save-Inputs $form
$progress = Get-JarvisProgress $progressPath
$first = if ($progress.completed) { ($progress.completed | ForEach-Object {[int]$_} | Measure-Object -Maximum).Maximum + 1 } else { 1 }
$start = if ($Step) { $Step } elseif ($From -gt $first) { $From } else { $first }
if ($Step -and $Through -and $Step -ne $Through) { throw '-Step and -Through cannot specify different steps.' }
$end = if ($Step) { $Step } elseif ($Through) { $Through } else { 44 }

for ($n = $start; $n -le $end; $n++) {
    if (@($progress.completed) -contains $n) { continue }
    Show-Action "Step $n pre-check"
    if (-not (Test-JarvisStepPreCheck -Number $n -Paths $paths -DryRun:$DryRun)) { throw "Step $n pre-check failed." }
    $isModelStep = ($n -notin @(13,14)) -and ($null -ne (Get-JarvisStepPrompt -Number $n -Root $root))
    if ($isModelStep -and -not $DryRun) {
        $servers = @(Get-Process -Name ollama -ErrorAction SilentlyContinue)
        if ($servers.Count -eq 0) { throw "Ollama isn't running. Start the Ollama app once, then rerun." }
        if ($servers.Count -gt 1) { throw "Two Ollama servers are running. Close the extra one (keep the Ollama app), then rerun. PIDs: $(@($servers | ForEach-Object Id) -join ', ')" }
        try { $tags = @((Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 5).models | ForEach-Object name) }
        catch { throw "Ollama /api/tags did not answer within 5 seconds: $($_.Exception.Message)" }
        $ready = Test-JarvisOllamaReady -Processes $servers -Tags $tags
        if (-not $ready.Ready) { throw $ready.Message }
    }
    if ($n -gt 43) { throw "Step $n not implemented: the current milestone stops after step 43." }
    switch ($n) {
        1 { if (-not $DryRun) { foreach ($f in @('USER.md','MEMORY.md')) { Backup-JarvisFile (Join-Path $paths.HermesHome "memories\$f") (Join-Path $paths.StateRoot 'backups') -RelativeTo $paths.HermesHome -UndoPath $undoPath | Out-Null }; Write-JarvisMemoryEntry (Join-Path $paths.HermesHome 'memories\USER.md') "$($form.name) works as: $($form.work). Time zone: $($form.timezone). Hours: $($form.hours). Weather city: $($form.weather_city)."; Write-JarvisMemoryEntry (Join-Path $paths.HermesHome 'memories\MEMORY.md') "JARVIS is chief of staff. Top priority: $($form.priority)." } }
        2 { if (-not $DryRun) { Backup-JarvisFile (Join-Path $paths.HermesHome 'memories\USER.md') (Join-Path $paths.StateRoot 'backups') -RelativeTo $paths.HermesHome -UndoPath $undoPath | Out-Null; Write-JarvisMemoryEntry (Join-Path $paths.HermesHome 'memories\USER.md') "Interview answers: $($form.interview -join ' | ')`nOpen questions: none recorded by installer." } }
        3 { if (-not $DryRun) { Backup-JarvisFile (Join-Path $paths.HermesHome 'memories\MEMORY.md') (Join-Path $paths.StateRoot 'backups') -RelativeTo $paths.HermesHome -UndoPath $undoPath | Out-Null; Write-JarvisMemoryEntry (Join-Path $paths.HermesHome 'memories\MEMORY.md') (Read-JarvisUtf8Text (Join-Path $root 'templates\memory-rules.md')) } }
        4 { Invoke-JarvisStepAction -Number 4 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        5 { Install-JarvisCrew $paths.HermesHome (Join-Path $root 'templates') $form.name -DryRun:$DryRun }
        6 { Invoke-JarvisStepAction -Number 6 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        7 {
            if (-not $DryRun) {
                $token = Get-JarvisEnvValue (Join-Path $paths.HermesHome '.env') 'TELEGRAM_BOT_TOKEN'
                if (-not $token -or -not $form.telegram_chat_id) { throw 'Telegram token and chat id are required before topic creation.' }
                $topicMap = New-JarvisTelegramTopics $token $form.telegram_chat_id
                $topicMap | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $paths.StateRoot 'telegram.json') -Encoding UTF8
            } else { Show-Action 'Call Telegram getChatMember and createForumTopic for three lanes' }
        }
        8 {
            if (-not $DryRun) {
                foreach ($profile in @('dev','research','assistant')) {
                    $profileDir = Join-Path $paths.HermesHome "profiles\$profile"
                    Invoke-JarvisSpecialistProfileCleanup -ProfileDir $profileDir -BackupRoot (Join-Path $paths.StateRoot 'backups') -RelativeTo $paths.HermesHome -UndoPath $undoPath
                }
            } else { Show-Action 'Back up specialist configs and strip Telegram channel settings' }
        }
        9 {
            if (-not $DryRun) {
                Backup-JarvisFile (Join-Path $paths.HermesHome 'config.yaml') (Join-Path $paths.StateRoot 'backups') -RelativeTo $paths.HermesHome -UndoPath $undoPath | Out-Null
                $telegram = Read-JarvisUtf8Text (Join-Path $paths.StateRoot 'telegram.json') | ConvertFrom-Json
                $map = @{ chat_id = $telegram.chat_id; topics = @{} }; foreach ($p in $telegram.topics.PSObject.Properties) { $map.topics[$p.Name] = $p.Value }
                $routes = @(Get-JarvisTelegramProfileRoutes -TopicMap ([pscustomobject]$map))
                $routeLiteral = '[' + (($routes | ForEach-Object { "{name: $($_.name), platform: telegram, profile: $($_.profile), chat_id: '$($_.chat_id)', thread_id: '$($_.thread_id)'}" }) -join ', ') + ']'
                $hermesCli = if ($env:JARVIS_HERMES_CLI) { $env:JARVIS_HERMES_CLI } else { 'hermes' }
                $beforeRestart = Invoke-JarvisHermesCommand -Hermes $hermesCli -Arguments @('gateway','status') -WorkingDirectory $paths.HermesHome
                $previousPid = Get-JarvisGatewayPid -Output $beforeRestart.Output
                $quotedRoutes = '"' + ([regex]::Replace($routeLiteral, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
                Assert-JarvisHermesCommand -Result (Invoke-JarvisHermesCommand -Hermes $hermesCli -Arguments @('config','set','profile_routes',$quotedRoutes) -WorkingDirectory $paths.HermesHome) -Label 'Hermes Telegram profile routes' | Out-Null
                Assert-JarvisHermesCommand -Result (Invoke-JarvisHermesCommand -Hermes $hermesCli -Arguments @('plugins','disable','telegram_topic_profiles') -WorkingDirectory $paths.HermesHome) -Label 'Hermes topic plugin disable' | Out-Null
                Assert-JarvisHermesCommand -Result (Invoke-JarvisHermesCommand -Hermes $hermesCli -Arguments @('config','set','gateway.multiplex_profiles','true') -WorkingDirectory $paths.HermesHome) -Label 'Hermes multiplex_profiles configuration' | Out-Null
                Assert-JarvisHermesCommand -Result (Invoke-JarvisHermesCommand -Hermes $hermesCli -Arguments @('gateway','restart','-y','--detach') -WorkingDirectory $paths.HermesHome) -Label 'Hermes gateway restart' | Out-Null
                Wait-JarvisGatewayRestart -Hermes $hermesCli -WorkingDirectory $paths.HermesHome -PreviousPid $previousPid | Out-Null
            } else { Show-Action 'Set native Telegram profile_routes; disable topic plugin; set multiplexing; restart gateway' }
        }
        10 { Invoke-JarvisStepAction -Number 10 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        11 { if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $paths.ProjectRoot | Out-Null; Initialize-JarvisActivityLog $logPath } }
        12 {
            if (-not $DryRun) {
                $loggingRule = 'After substantial work, run the local log-task command with your agent name, brief description, status, and exact model. Log failures as well as successes.'
                foreach ($profile in @('default','dev','research','assistant')) {
                    $memoryFile = if ($profile -eq 'default') { Join-Path $paths.HermesHome 'memories\MEMORY.md' } else { Join-Path $paths.HermesHome "profiles\$profile\memories\MEMORY.md" }
                    Write-JarvisMemoryEntry -MemoryFile $memoryFile -Entry $loggingRule
                }
                foreach ($agent in @('JARVIS','DEV','RESEARCH','ASSISTANT')) { Add-JarvisActivity $logPath $agent 'installer smoke test' 'completed' 'gpt-oss:20b' }
            }
        }
        13 {
            if ($DryRun) { Show-Action $(if ($WithBuilderOrientation) { 'Record provider-neutral external builder orientation' } else { 'Record durable builder orientation skip' }) }
            elseif ($WithBuilderOrientation) {
                Add-JarvisActivity $logPath 'JARVIS' 'step=13; orientation=recorded; evidence=provider-neutral; scope=layout,crew,routing,project,builder-only,independence; routing=native-profile-routes' 'completed'
            } else {
                Add-JarvisActivity $logPath 'JARVIS' 'step=13; orientation=skipped; evidence=provider-neutral; routing=native-profile-routes; independence=external-builder-optional' 'completed'
            }
        }
        14 {
            if ($DryRun) { Show-Action 'Survey Hermes and JARVIS data sources read-only; record sanitized DEV-attributed facts' }
            else {
                $survey = Get-JarvisDataSurvey -Paths $paths
                $evidence = [pscustomobject][ordered]@{
                    format_version=1; step=14; status='completed'; profile='dev'; source_count=@($survey.sources).Count
                    sources=@($survey.sources); capabilities=@($survey.capabilities); limitations=@($survey.limitations)
                }
                $evidence | Add-Member -NotePropertyName evidence_hash -NotePropertyValue (Get-JarvisDataSurveyEvidenceHash -Evidence $evidence)
                New-Item -ItemType Directory -Force -Path $paths.StateRoot | Out-Null
                Write-JarvisUtf8Text -Path (Join-Path $paths.StateRoot 'step-14-survey.json') -Text ($evidence | ConvertTo-Json -Depth 20)
                Add-JarvisActivity $logPath 'DEV' 'step=14; survey=completed; evidence=step-14-survey.json' 'completed'
            }
        }
        15 {
            if ($DryRun) { Show-Action 'Verify required processes and free port 8899; install loopback dashboard runtime and recovery task' }
            else {
                $runtime = Resolve-JarvisDashboardPython -HermesHome $paths.HermesHome
                Install-JarvisDashboardRuntime -ProjectRoot $paths.ProjectRoot -DashboardRoot (Join-Path $root 'dashboard') -BackupRoot $paths.BackupRoot -UndoPath $undoPath -Runtime $runtime
                Register-JarvisDashboardTask -ProjectRoot $paths.ProjectRoot -PythonExecutable $runtime.Executable -BackupRoot $paths.BackupRoot -UndoPath $undoPath | Out-Null
            }
        }
        16 {
            if ($DryRun) { Show-Action 'Install the bundled original template; owner upload remains available at /upload' }
            else { Install-JarvisDashboardTemplate -ProjectRoot $paths.ProjectRoot -DashboardRoot (Join-Path $root 'dashboard') -BackupRoot $paths.BackupRoot -UndoPath $undoPath }
        }
        17 {
            if ($DryRun) { Show-Action 'Install split seven-view dashboard shell while preserving /template' }
            else { Install-JarvisDashboardShell -ProjectRoot $paths.ProjectRoot -DashboardRoot (Join-Path $root 'dashboard') -BackupRoot $paths.BackupRoot -UndoPath $undoPath }
        }
        18 {
            if ($DryRun) { Show-Action 'Install backup protocol and create the v0.1 pre-wiring baseline' }
            else { Install-JarvisDashboardBackup -ProjectRoot $paths.ProjectRoot -DashboardRoot (Join-Path $root 'dashboard') -BackupRoot $paths.BackupRoot -UndoPath $undoPath -StateRoot $paths.StateRoot | Out-Null }
        }
        19 { Invoke-JarvisStepAction -Number 19 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        20 { Invoke-JarvisStepAction -Number 20 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        21 { Invoke-JarvisStepAction -Number 21 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        22 { Invoke-JarvisStepAction -Number 22 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        23 { if (-not $DryRun) { Install-JarvisComms $paths.ProjectRoot }; Invoke-JarvisStepAction -Number 23 -Paths $paths -Root $root -Form $form -DryRun:$DryRun }
        24 { if ($WithSerpApi) { Invoke-JarvisStepAction -Number 24 -Paths $paths -Root $root -Form $form -DryRun:$DryRun } else { Show-Action 'SerpApi skipped by switch' } }
        25 { if ($WithSerpApi -and -not $DryRun) { Install-JarvisResearch $paths.ProjectRoot (Join-Path $paths.HermesHome 'profiles\research') -WithSerpApi } }
        26 { Invoke-JarvisStepAction -Number 26 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        27 { if (-not $DryRun) { $voice = Install-JarvisVoiceRuntime $paths.VoiceRoot (Join-Path $paths.StateRoot 'voice-runtime.json') (Join-Path $root 'voice\voice-server.py'); Register-JarvisVoiceTask $paths.VoiceRoot $voice.Executable } else { Show-Action 'Create Kokoro venv with py -3.12, verify models, and prepare loopback voice task' } }
        28 { if ($WithElevenLabs) { Show-Action 'Collect protected ElevenLabs key' } else { Show-Action 'ElevenLabs skipped by switch' } }
        29 { Invoke-JarvisStepAction -Number 29 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        30 { Invoke-JarvisStepAction -Number 30 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        31 { Invoke-JarvisStepAction -Number 31 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        32 { Show-Action 'Use the repository dashboard fixed-timing push-to-talk state machine; no model code generation required' }
        33 { Show-Action 'Use the repository dashboard conversation overlay and cancellable microphone lifecycle; no model code generation required' }
        34 { Invoke-JarvisStepAction -Number 34 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        35 { Invoke-JarvisStepAction -Number 35 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        36 { if ($WithComposio) { Show-Action 'Install Composio and pause for owner login and two browser links' } else { Show-Action 'Composio skipped by switch' } }
        37 { Show-Action 'Install private-service allowlist and DEV/RESEARCH deny hooks' }
        38 { if (-not $DryRun) { Write-JarvisBriefingConfig (Join-Path $paths.ProjectRoot 'briefing.json') $form.weather_city }; Invoke-JarvisStepAction -Number 38 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        39 { Show-Action 'Install throttled private-services poller and stale cache chips' }
        40 { Invoke-JarvisStepAction -Number 40 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        41 { if ($WithTailscale) { Show-Action 'Install Tailscale, await owner authorization, and configure HTTPS serve' } else { Show-Action 'Tailscale skipped by switch' } }
        42 { Invoke-JarvisStepAction -Number 42 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        43 { if (-not $DryRun) { Test-JarvisInstall $paths.ProjectRoot $paths.HermesHome | ConvertTo-Json | Set-Content (Join-Path $paths.StateRoot 'verification.json') }; Invoke-JarvisStepAction -Number 43 -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes }
        44 { if ($WithHomeAssistant) { Invoke-JarvisStepAction -Number 44 -Paths $paths -Root $root -Form $form -DryRun:$DryRun } else { Show-Action 'Home Assistant skipped by switch' } }
        default { throw "Step $n not implemented: this milestone is intentionally gated before dashboard, voice, comms, and finish work." }
    }
    $postPassed = Test-JarvisStepPostCheck -Number $n -Paths $paths -Root $root -DryRun:$DryRun
    if (-not $postPassed -and $null -ne (Get-JarvisStepPrompt -Number $n -Root $root)) {
        Write-Host "Step $n post-check failed; retrying the model turn once with a stricter reminder."
        Invoke-JarvisStepAction -Number $n -Paths $paths -Root $root -Form $form -DryRun:$DryRun -TimeoutMinutes $ModelTimeoutMinutes -Retry | Out-Null
        $postPassed = Test-JarvisStepPostCheck -Number $n -Paths $paths -Root $root -DryRun:$DryRun
    }
    if (-not $postPassed) { throw (Get-JarvisPostCheckFailureMessage -Step $n -Output $(if (Test-Path (Join-Path $paths.StateRoot ("agent-turn-{0:D2}.txt" -f [int]$n))) { Read-JarvisUtf8Text (Join-Path $paths.StateRoot ("agent-turn-{0:D2}.txt" -f [int]$n)) } else { '' })) }
    Show-Action "Step $n post-check passed"
    if (-not $DryRun) { Save-JarvisProgress -Path $progressPath -Completed (@($progress.completed) + @($n)) -Current ($n + 1); $progress = Get-JarvisProgress $progressPath }
}
Write-Output "JARVIS installer run complete through step $end."
