[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$DryRun,
    [ValidateRange(1,48)][int]$Step,
    [ValidateRange(1,48)][int]$From = 1,
    [switch]$Uninstall,
    [switch]$WithClaudeCode,
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

$form = if (Test-Path $inputPath) { Get-Content $inputPath -Raw | ConvertFrom-Json } else { Read-JarvisOwnerForm -SkipPrompt:$DryRun }
if (-not $DryRun -and -not (Test-JarvisOwnerForm -Form $form)) { throw 'Owner form is incomplete. Re-run interactively and provide all six interview answers before installation.' }
if (-not (Test-Path $inputPath)) { Save-Inputs $form }
$progress = Get-JarvisProgress $progressPath
$first = if ($progress.completed) { ($progress.completed | ForEach-Object {[int]$_} | Measure-Object -Maximum).Maximum + 1 } else { 1 }
$start = if ($Step) { $Step } elseif ($From -gt $first) { $From } else { $first }
$end = if ($Step) { $Step } else { 44 }

for ($n = $start; $n -le $end; $n++) {
    if (@($progress.completed) -contains $n) { continue }
    Show-Action "Step $n pre-check"
    if ($n -eq 15) {
        if (-not (Test-JarvisPortFree -Port 8899)) { throw 'Port 8899 must be free before dashboard installation.' }
        if (-not $DryRun -and -not (Test-JarvisRequiredProcesses)) { throw 'Paperclip, Postgres, and Ollama must remain running during installation.' }
    }
    switch ($n) {
        1 { if (-not $DryRun) { foreach ($f in @('USER.md','MEMORY.md')) { Backup-JarvisFile (Join-Path $paths.HermesHome "memories\$f") (Join-Path $paths.StateRoot 'backups') -UndoPath $undoPath | Out-Null }; Write-JarvisMemoryEntry (Join-Path $paths.HermesHome 'memories\USER.md') "$($form.name) works as: $($form.work). Time zone: $($form.timezone). Hours: $($form.hours). Weather city: $($form.weather_city)."; Write-JarvisMemoryEntry (Join-Path $paths.HermesHome 'memories\MEMORY.md') "JARVIS is chief of staff. Top priority: $($form.priority)." } }
        2 { if (-not $DryRun) { Backup-JarvisFile (Join-Path $paths.HermesHome 'memories\USER.md') (Join-Path $paths.StateRoot 'backups') -UndoPath $undoPath | Out-Null; Write-JarvisMemoryEntry (Join-Path $paths.HermesHome 'memories\USER.md') "Interview answers: $($form.interview -join ' | ')" } }
        3 { if (-not $DryRun) { Backup-JarvisFile (Join-Path $paths.HermesHome 'memories\MEMORY.md') (Join-Path $paths.StateRoot 'backups') -UndoPath $undoPath | Out-Null; Write-JarvisMemoryEntry (Join-Path $paths.HermesHome 'memories\MEMORY.md') (Get-Content (Join-Path $root 'templates\memory-rules.md') -Raw) } }
        4 { Show-Action 'Run prompts/04-plan-crew.txt as default profile' }
        5 { Install-JarvisCrew $paths.HermesHome (Join-Path $root 'templates') $form.name -DryRun:$DryRun }
        6 { Show-Action 'Distribute owner brief and role boundaries to all four profiles' }
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
                    foreach ($file in @('config.yaml','.env')) {
                        $target = Join-Path $profileDir $file; if (Test-Path $target) { Backup-JarvisFile $target (Join-Path $paths.StateRoot 'backups') -UndoPath $undoPath | Out-Null }
                    }
                    $envFile = Join-Path $profileDir '.env'; if (Test-Path $envFile) { (Get-Content $envFile | Where-Object { $_ -notmatch '^TELEGRAM_BOT_TOKEN=' }) | Set-Content $envFile -Encoding UTF8 }
                    $configFile = Join-Path $profileDir 'config.yaml'; if (Test-Path $configFile) { $yaml = Get-Content $configFile -Raw; $yaml = [regex]::Replace($yaml, '(?ms)^platforms:\s*\n(?:^[ \t]+.*\n?)+', ''); Set-Content $configFile $yaml -Encoding UTF8 }
                }
            } else { Show-Action 'Back up specialist configs and strip Telegram channel settings' }
        }
        9 {
            if (-not $DryRun) {
                Backup-JarvisFile (Join-Path $paths.HermesHome 'config.yaml') (Join-Path $paths.StateRoot 'backups') -UndoPath $undoPath | Out-Null
                $telegram = Get-Content (Join-Path $paths.StateRoot 'telegram.json') -Raw | ConvertFrom-Json
                $map = @{ chat_id = $telegram.chat_id; topics = @{} }; foreach ($p in $telegram.topics.PSObject.Properties) { $map.topics[$p.Name] = $p.Value }
                Write-JarvisTelegramPlugin $paths.HermesHome $map $form.name
                & hermes plugins enable telegram_topic_profiles | Out-Null
                & hermes config set gateway.multiplex_profiles true | Out-Null
                & hermes gateway restart | Out-Null
            } else { Show-Action 'Install and enable telegram_topic_profiles; set multiplexing; restart gateway' }
        }
        10 { Show-Action 'Owner first-words test in four Telegram topics' }
        11 { if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $paths.ProjectRoot | Out-Null; Initialize-JarvisActivityLog $logPath } }
        12 { if (-not $DryRun) { foreach ($agent in @('JARVIS','DEV','RESEARCH','ASSISTANT')) { Add-JarvisActivity $logPath $agent 'installer smoke test' 'completed' 'gpt-oss:20b' } } }
        13 { if ($WithClaudeCode) { Show-Action 'Run prompts/13-claude-orientation.txt' } else { Show-Action 'Claude Code skipped' } }
        14 { Show-Action 'Run read-only Hermes data survey' }
        15 { if (-not $DryRun) { Install-JarvisDashboardFiles $paths.ProjectRoot (Join-Path $root 'dashboard'); Register-JarvisDashboardTask $paths.ProjectRoot } }
        16 { Show-Action 'Dashboard upload route is available at /upload' }
        17 { Show-Action 'Original split dashboard assets installed' }
        18 { if (-not $DryRun) { Copy-Item (Join-Path $root 'dashboard\jarvis-backup.ps1') (Join-Path $paths.ProjectRoot 'jarvis-backup.ps1') -Force } }
        23 { if (-not $DryRun) { Install-JarvisComms $paths.ProjectRoot } }
        24 { if ($WithSerpApi) { Show-Action 'Prompt for masked SerpApi key and store locally' } }
        25 { if ($WithSerpApi -and -not $DryRun) { Install-JarvisResearch $paths.ProjectRoot (Join-Path $paths.HermesHome 'profiles\research') -WithSerpApi } }
        27 { if (-not $DryRun) { $voice = Install-JarvisVoiceRuntime $paths.VoiceRoot (Join-Path $paths.StateRoot 'voice-runtime.json') (Join-Path $root 'voice\voice-server.py'); Register-JarvisVoiceTask $paths.VoiceRoot $voice.Executable } else { Show-Action 'Create Kokoro venv with py -3.12 and record exact interpreter' } }
        28 { if ($WithElevenLabs) { Show-Action 'Prompt for masked ElevenLabs key and store locally' } }
        36 { if ($WithComposio) { Show-Action 'Install Composio and pause for browser OAuth links' } }
        38 { if (-not $DryRun) { Write-JarvisBriefingConfig (Join-Path $paths.ProjectRoot 'briefing.json') $form.weather_city } }
        41 { if ($WithTailscale -and -not $DryRun) { Install-JarvisAccess $paths.ProjectRoot -WithTailscale } }
        43 { if (-not $DryRun) { Test-JarvisInstall $paths.ProjectRoot $paths.HermesHome | ConvertTo-Json | Set-Content (Join-Path $paths.StateRoot 'verification.json') } }
        44 { if ($WithHomeAssistant) { Show-Action 'Install loopback Home Assistant and pause for browser onboarding' } }
        default { Show-Action "Step $n action recorded; agent-driven or optional work is handled by its prompt/module." }
    }
    Show-Action "Step $n post-check"
    if (-not $DryRun) { Save-JarvisProgress -Path $progressPath -Completed (@($progress.completed) + @($n)) -Current ($n + 1); $progress = Get-JarvisProgress $progressPath }
}
Write-Output "JARVIS installer run complete through step $end."
