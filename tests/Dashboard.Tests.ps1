$module = Join-Path $PSScriptRoot '..\installer\lib\dashboard.psm1'
Import-Module $module -Force
Import-Module (Join-Path $PSScriptRoot '..\installer\lib\steps.psm1') -Force

Describe 'Dashboard contract helpers' {
    It 'returns the fixed crew keys' {
        $crew = Get-JarvisCrew
        @($crew.key) | Should Be @('default', 'dev', 'research', 'assistant')
        @($crew.name) | Should Be @('JARVIS', 'DEV', 'RESEARCH', 'ASSISTANT')
    }

    It 'rejects upload traversal and unsupported extensions' {
        { Assert-JarvisUploadName -Name '..\evil.html' } | Should Throw
        { Assert-JarvisUploadName -Name 'payload.exe' } | Should Throw
        Assert-JarvisUploadName -Name 'jarvis-dashboard-template.html' | Should Be $true
    }

    It 'defines a real action and post-check for every installer step' {
        $definitions = Get-JarvisStepDefinitions
        @($definitions).Count | Should Be 48
        foreach ($definition in $definitions) {
            $definition.Action | Should Not BeNullOrEmpty
            $definition.PreCheck | Should Not BeNullOrEmpty
            $definition.PostCheck | Should Not BeNullOrEmpty
        }
    }

    It 'does not claim a later milestone is complete without its real end state' {
        $paths = [pscustomobject]@{ ProjectRoot = $TestDrive; HermesHome = (Join-Path $TestDrive 'hermes'); StateRoot = (Join-Path $TestDrive 'state') }
        New-Item -ItemType Directory -Force -Path $paths.HermesHome | Out-Null
        Test-JarvisStepPostCheck -Number 19 -Paths $paths -Root $PSScriptRoot -DryRun:$false | Should Be $false
    }

    It 'verifies the repository push-to-talk artifact for step 32' {
        $paths = [pscustomobject]@{ ProjectRoot = $TestDrive; HermesHome = (Join-Path $TestDrive 'hermes'); StateRoot = (Join-Path $TestDrive 'state') }
        Test-JarvisStepPostCheck -Number 32 -Paths $paths -Root (Join-Path $PSScriptRoot '..\installer') -DryRun:$false | Should Be $true
    }

    It 'verifies the repository conversation overlay artifact for step 33' {
        $paths = [pscustomobject]@{ ProjectRoot = $TestDrive; HermesHome = (Join-Path $TestDrive 'hermes'); StateRoot = (Join-Path $TestDrive 'state') }
        Test-JarvisStepPostCheck -Number 33 -Paths $paths -Root (Join-Path $PSScriptRoot '..\installer') -DryRun:$false | Should Be $true
    }

    It 'verifies the repository owner shortcut artifact for step 34' {
        $paths = [pscustomobject]@{ ProjectRoot = $TestDrive; HermesHome = (Join-Path $TestDrive 'hermes'); StateRoot = (Join-Path $TestDrive 'state') }
        Test-JarvisStepPostCheck -Number 34 -Paths $paths -Root (Join-Path $PSScriptRoot '..\installer') -DryRun:$false | Should Be $true
    }

    It 'verifies the repository dictation fallback artifact for step 35' {
        $paths = [pscustomobject]@{ ProjectRoot = $TestDrive; HermesHome = (Join-Path $TestDrive 'hermes'); StateRoot = (Join-Path $TestDrive 'state') }
        Test-JarvisStepPostCheck -Number 35 -Paths $paths -Root (Join-Path $PSScriptRoot '..\installer') -DryRun:$false | Should Be $true
    }

    It 'records Composio as pending owner with the exact read allowlist' {
        $module = Join-Path $PSScriptRoot '..\installer\lib\composio.psm1'
        Import-Module $module -Force
        $project = Join-Path $TestDrive 'composio'
        Install-JarvisComposio $project
        $text = Get-Content (Join-Path $project 'composio-state.json') -Raw
        $text | Should Match 'pending-owner'
        $text | Should Match 'GMAIL_FETCH_EMAILS'
        $text | Should Match 'GOOGLECALENDAR_EVENTS_LIST'
    }

    It 'installs the private-service allowlist and deny hook' {
        $module = Join-Path $PSScriptRoot '..\installer\lib\private-services.psm1'
        Import-Module $module -Force
        $project = Join-Path $TestDrive 'private-services'
        Install-JarvisPrivateServices $project (Join-Path $PSScriptRoot '..\installer')
        (Get-Content (Join-Path $project 'private-services.json') -Raw) | Should Match 'owner-approval-pending'
        (Get-Content (Join-Path $PSScriptRoot '..\installer\hooks\deny-private-services.py') -Raw) | Should Match 'pre_tool_call'
    }

    It 'formats a three-sentence briefing and preserves owner triggers' {
        Import-Module (Join-Path $PSScriptRoot '..\installer\lib\briefing.psm1') -Force
        $text = Format-JarvisBriefing 'Sunny' 'Mail' 'Calendar'
        @($text -split '\. ' | Where-Object { $_ }).Count | Should Be 3
        $path = Join-Path $TestDrive 'briefing.json'
        Write-JarvisBriefingConfig $path 'Greenwood'
        (Get-Content $path -Raw) | Should Match 'run my morning briefing'
    }

    It 'installs the bounded private-services poller contract' {
        $module = Join-Path $PSScriptRoot '..\installer\lib\poller.psm1'
        Import-Module $module -Force
        $project = Join-Path $TestDrive 'poller'
        Install-JarvisPoller $project (Join-Path $PSScriptRoot '..\installer')
        (Get-Content (Join-Path $project 'poller.json') -Raw) | Should Match 'max_calls_per_run'
        (Get-Content (Join-Path $PSScriptRoot '..\installer\dashboard\private-services-poller.py') -Raw) | Should Match 'def is_stale'
    }

    It 'writes responsive evidence for all required viewport widths' {
        Import-Module (Join-Path $PSScriptRoot '..\installer\lib\responsive.psm1') -Force
        $path = Join-Path $TestDrive 'responsive.json'
        Write-JarvisResponsiveAudit $path (Join-Path $PSScriptRoot '..\installer\dashboard')
        $text = Get-Content $path -Raw
        $text | Should Match '390'
        $text | Should Match '1920'
    }
}
