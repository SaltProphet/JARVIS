$steps = Join-Path $PSScriptRoot '..\installer\lib\steps.psm1'
$logging = Join-Path $PSScriptRoot '..\installer\lib\logging.psm1'
Import-Module $steps -Force
Import-Module $logging -Force

Describe 'Milestone 1 post-checks' {
    It 'accepts only the real end states for steps 1 through 12' {
        $root = Join-Path $TestDrive 'project'
        $hermes = Join-Path $TestDrive 'hermes'
        $state = Join-Path $TestDrive 'state'
        New-Item -ItemType Directory -Force -Path "$root\content", "$hermes\memories", $state | Out-Null
        $paths = [pscustomobject]@{ ProjectRoot = $root; HermesHome = $hermes; StateRoot = $state }
        Set-Content "$hermes\memories\USER.md" "Owner works as: engineer`nInterview answers: a | b | c | d | e | f`nOpen questions: none"
        Set-Content "$hermes\memories\MEMORY.md" "PROGRESS`nAPPROVAL`nCOMMUNICATION`nDELEGATION`nBLOCKED COMMANDS`nPERSONAL AUTHORITY`nlog-task"
        Set-Content "$state\agent-turn-04.txt" 'JARVIS dev DEV research RESEARCH assistant ASSISTANT'
        New-Item -ItemType Directory -Force -Path "$hermes\profiles\dev", "$hermes\profiles\research", "$hermes\profiles\assistant" | Out-Null
        foreach ($profile in @('dev','research','assistant')) { New-Item -ItemType Directory -Force -Path "$hermes\profiles\$profile\memories" | Out-Null; Set-Content "$hermes\profiles\$profile\SOUL.md" $profile; Set-Content "$hermes\profiles\$profile\memories\MEMORY.md" 'log-task' }
        Set-Content "$state\agent-turn-06.txt" 'JARVIS DEV RESEARCH ASSISTANT'
        [ordered]@{ chat_id = '-100'; topics = [ordered]@{ DEV = 'dev'; RESEARCH = 'research'; ASSISTANT = 'assistant' } } | ConvertTo-Json | Set-Content "$state\telegram.json"
        Set-Content "$hermes\config.yaml" "multiplex_profiles: true`nprofile_routes:`n- name: telegram-dev`n  platform: telegram`n  profile: dev`n- name: telegram-research`n  platform: telegram`n  profile: research`n- name: telegram-assistant`n  platform: telegram`n  profile: assistant"
        Set-Content "$state\agent-turn-10.txt" 'DEV works; RESEARCH works; ASSISTANT works'
        Initialize-JarvisActivityLog (Join-Path $root 'agent-logs.db')
        foreach ($agent in @('JARVIS','DEV','RESEARCH','ASSISTANT')) { Add-JarvisActivity (Join-Path $root 'agent-logs.db') $agent 'smoke' 'completed' 'test-model' }
        foreach ($number in 1..12) { Test-JarvisStepPostCheck -Number $number -Paths $paths -Root $PSScriptRoot | Should Be $true }
    }

    It 'reports later milestone state as incomplete instead of passing by default' {
        $paths = [pscustomobject]@{ ProjectRoot = $TestDrive; HermesHome = (Join-Path $TestDrive 'hermes'); StateRoot = (Join-Path $TestDrive 'state') }
        New-Item -ItemType Directory -Force -Path $paths.HermesHome,$paths.StateRoot | Out-Null
        Set-Content (Join-Path $paths.ProjectRoot 'step-19.json') '{}'
        Test-JarvisStepPostCheck -Number 19 -Paths $paths -Root $PSScriptRoot | Should Be $false
    }
}
