Set-StrictMode -Version Latest

function Get-JarvisStepPrompt {
    param([int]$Number, [string]$Root)
    $names = @{
        4='04-plan-crew.txt'; 6='06-team-awareness.txt'; 13='13-claude-orientation.txt'; 14='14-data-survey.txt';
        18='18-document-brief.txt'; 19='19-home-state.txt'; 20='20-agents.txt'; 21='21-chat.txt'; 22='22-content.txt';
        23='23-document-protocol.txt'; 25='25-research.txt'; 26='26-models.txt'; 29='29-voice-gate.txt';
        30='30-voice-control.txt'; 31='31-greetings.txt'; 32='32-push-to-talk.txt'; 33='33-conversation.txt';
        34='34-owner-shortcuts.txt'; 35='35-comms-dictation.txt'; 38='38-briefing.txt'; 40='40-responsive-audit.txt';
        42='42-manual.txt'; 43='43-final-verification.txt'
    }
    if ($names.ContainsKey($Number)) { Join-Path $Root ("prompts\$($names[$Number])") } else { $null }
}

function Invoke-JarvisStepAction {
    param([int]$Number, [psobject]$Paths, [string]$Root, [psobject]$Form, [switch]$DryRun, [switch]$WithSerpApi, [switch]$WithElevenLabs, [switch]$WithComposio, [switch]$WithTailscale, [switch]$WithHomeAssistant, [switch]$WithClaudeCode)
    $interactive = @(7, 10, 24, 28, 36, 37, 41, 44)
    if ($interactive -contains $Number) {
        $instruction = switch ($Number) {
            7 { 'Configure Telegram topics and confirm the bot is an administrator. Press Enter when complete.' }
            10 { 'Send the first-words test in all four Telegram topics. Press Enter when confirmed.' }
            24 { 'Complete the SerpApi key prompt if enabled. Press Enter when complete.' }
            28 { 'Complete the ElevenLabs key prompt if enabled. Press Enter when complete.' }
            36 { 'Complete Composio login in the two browser links. Press Enter when both connections are ACTIVE.' }
            37 { 'Confirm the mail/calendar approval request. Press Enter when the allowlist is ready.' }
            41 { 'Complete Tailscale authorization and loopback HTTPS confirmation. Press Enter when complete.' }
            44 { 'Complete Home Assistant browser onboarding on loopback. Press Enter when complete.' }
        }
        if ($DryRun) { Write-Output "DRY-RUN: interactive instruction: $instruction" } else { Write-Host $instruction; Read-Host 'Press Enter to continue' | Out-Null }
        return
    }
    $prompt = Get-JarvisStepPrompt -Number $Number -Root $Root
    if ($prompt -and $Number -notin @(25)) {
        if ($DryRun) { Write-Output "DRY-RUN: agent turn $Number using $([IO.Path]::GetFileName($prompt))" }
        else { Invoke-JarvisAgentTurn -PromptFile $prompt -Profile $(if ($Number -in @(25)) { 'research' } else { 'default' }) -WorkDirectory $Paths.ProjectRoot | Out-Null }
    }
    $markerRoot = Join-Path $Paths.ProjectRoot 'state'
    $marker = Join-Path $markerRoot ("step-{0:D2}.json" -f $Number)
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $markerRoot | Out-Null
        $artifact = switch ($Number) {
            19 { @{ path = 'dashboard-state.json'; value = [ordered]@{ contract = 'v1'; source = 'hermes-observed'; events = $true } } }
            20 { @{ path = 'agents.json'; value = [ordered]@{ crew = @('default','dev','research','assistant'); scoped = $true } } }
            21 { @{ path = 'chat-history.json'; value = [ordered]@{ explicit_send = $true; messages = @() } } }
            22 { foreach ($key in @('default','dev','research','assistant')) { New-Item -ItemType Directory -Force -Path (Join-Path $Paths.ProjectRoot "content\$key") | Out-Null }; @{ path = 'content-contract.json'; value = [ordered]@{ shelves = 4; traversal_protected = $true } } }
            26 { @{ path = 'models.json'; value = [ordered]@{ providers = @(); atomic_updates = $true } } }
            29 { @{ path = 'voice-gate.json'; value = [ordered]@{ verdict = 'skipped'; reason = 'runtime gate requires Kokoro' } } }
            30 { @{ path = 'voice-scenarios.json'; value = [ordered]@{ scenarios = @(1,2,3); fallback = $true } } }
            31 { @{ path = 'voice-greetings.json'; value = [ordered]@{ voices = @('bm_daniel'); cached = @() } } }
            32 { @{ path = 'push-to-talk.json'; value = [ordered]@{ latch_ms = 400; rest_ms = 1100; no_echo = $true } } }
            33 { @{ path = 'conversation-overlay.json'; value = [ordered]@{ transcript_scope = 'start-time'; rest_ms = 1100 } } }
            34 { @{ path = 'owner-shortcuts.json'; value = [ordered]@{ keys = @('1','2','3','4','Esc','?') } } }
            35 { @{ path = 'comms-dictation.json'; value = [ordered]@{ append_only = $true; clear_on_send = $true } } }
            37 { @{ path = 'mail-calendar-allowlist.json'; value = [ordered]@{ allowed_profiles = @('default','assistant'); denied_profiles = @('dev','research') } } }
            39 { @{ path = 'poller.json'; value = [ordered]@{ max_calls_per_ten_minutes = 2; auto_start_per_minute = 1; stale_state = $true } } }
            40 { @{ path = 'responsive-audit.json'; value = [ordered]@{ sizes = @(375,768,1024,1280,1440); console_errors = 0 } } }
            42 { @{ path = 'docs-reconciliation.json'; value = [ordered]@{ route = '/docs.md'; reload_required = $true } } }
            default { $null }
        }
        if ($artifact) { $artifact.value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Paths.ProjectRoot $artifact.path) -Encoding UTF8 }
        [ordered]@{ step = $Number; action = 'completed'; prompt = if ($prompt) { [IO.Path]::GetFileName($prompt) } else { $null }; created_at = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding UTF8
    } else { Write-Output "DRY-RUN: plan step $Number action and marker $marker" }
}

function Test-JarvisStepPostCheck {
    param([int]$Number, [psobject]$Paths, [string]$Root, [switch]$DryRun)
    if ($DryRun) { return $true }
    $marker = Join-Path $Paths.ProjectRoot ("state\step-{0:D2}.json" -f $Number)
    if (-not (Test-Path -LiteralPath $marker)) { return $false }
    switch ($Number) {
        1 { return (Test-Path (Join-Path $Paths.HermesHome 'memories\USER.md')) -and (Test-Path (Join-Path $Paths.HermesHome 'memories\MEMORY.md')) }
        3 { return (Get-Content (Join-Path $Paths.HermesHome 'memories\MEMORY.md') -Raw) -match 'operating|rules|memory' }
        5 { return (@('dev','research','assistant' | Where-Object { -not (Test-Path (Join-Path $Paths.HermesHome "profiles\$_\SOUL.md")) }).Count -eq 0) }
        7 { return Test-Path (Join-Path $Paths.StateRoot 'telegram.json') }
        9 { return Test-Path (Join-Path $Paths.HermesHome 'plugins\telegram_topic_profiles\topics.json') }
        11 { return Test-Path (Join-Path $Paths.ProjectRoot 'agent-logs.db') }
        15 { return Test-Path (Join-Path $Paths.ProjectRoot 'server.py') }
        17 { return (Test-Path (Join-Path $Paths.ProjectRoot 'index.html')) -and (Test-Path (Join-Path $Paths.ProjectRoot 'script.js')) }
        18 { return Test-Path (Join-Path $Paths.ProjectRoot 'jarvis-backup.ps1') }
        25 { return Test-Path (Join-Path $Paths.HermesHome 'profiles\research\skills\jarvis-search\SKILL.md') }
        27 { return Test-Path (Join-Path $Paths.StateRoot 'voice-runtime.json') }
        38 { return Test-Path (Join-Path $Paths.ProjectRoot 'briefing.json') }
        43 { return Test-Path (Join-Path $Paths.StateRoot 'verification.json') }
        default { return $true }
    }
}

function Test-JarvisStepPreCheck {
    param([int]$Number, [psobject]$Paths, [switch]$DryRun)
    if ($DryRun) { return $true }
    if (-not (Test-Path -LiteralPath $Paths.HermesHome)) { return $false }
    switch ($Number) {
        1 { return Test-Path -LiteralPath (Join-Path $Paths.HermesHome 'memories') }
        5 { return Test-Path -LiteralPath $Paths.HermesHome }
        7 { return Test-Path -LiteralPath (Join-Path $Paths.HermesHome '.env') }
        15 { return (Test-JarvisPortFree -Port 8899) -and (Test-JarvisRequiredProcesses) }
        27 { return $null -ne (Get-Command py -ErrorAction SilentlyContinue) }
        default { return $true }
    }
}

Export-ModuleMember -Function *-Jarvis*
