Describe 'Installer progress with a fake Hermes home' {
    It 'supports a bounded dry run through milestone one' {
        $fakeHermes = Join-Path $TestDrive 'through-hermes'
        $fakeState = Join-Path $TestDrive 'through-state'
        New-Item -ItemType Directory -Force -Path $fakeHermes,$fakeState | Out-Null
        $oldHermes = $env:HERMES_HOME
        $oldState = $env:JARVIS_STATE_ROOT
        $env:HERMES_HOME = $fakeHermes
        $env:JARVIS_STATE_ROOT = $fakeState
        try {
            $output = @(& (Join-Path $PSScriptRoot '..\installer\install.ps1') -DryRun -Through 12 2>&1 | Out-String) -join "`n"
            $? | Should Be $true
            $output | Should Match 'through step 12'
            $output | Should Not Match 'Step 13 pre-check'
        } finally {
            if ($null -eq $oldHermes) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue } else { $env:HERMES_HOME = $oldHermes }
            if ($null -eq $oldState) { Remove-Item Env:JARVIS_STATE_ROOT -ErrorAction SilentlyContinue } else { $env:JARVIS_STATE_ROOT = $oldState }
        }
    }

    It 'durably records a skipped provider-neutral builder orientation without Hermes' {
        $caseRoot = Join-Path $TestDrive 'skipped-case'
        $fakeHermes = Join-Path $caseRoot 'builder-hermes'
        $fakeState = Join-Path $caseRoot 'builder-state'
        New-Item -ItemType Directory -Force -Path $fakeHermes,$fakeState | Out-Null
        $oldHermes = $env:HERMES_HOME
        $oldState = $env:JARVIS_STATE_ROOT
        try {
            $env:HERMES_HOME = $fakeHermes
            $env:JARVIS_STATE_ROOT = $fakeState
            [ordered]@{ name='Owner'; work='work'; timezone='UTC'; hours='9-5'; weather_city='City'; priority='priority'; telegram_chat_id='-100'; interview=@('a','b','c','d','e','f') } |
                ConvertTo-Json -Depth 5 | Set-Content (Join-Path $fakeState 'inputs.json') -Encoding UTF8
            $env:JARVIS_HERMES_CLI = Join-Path $TestDrive 'must-not-run-hermes.exe'
            & (Join-Path $PSScriptRoot '..\installer\install.ps1') -Step 13 2>&1 | Out-Null
            $? | Should Be $true
            $rows = @(Get-JarvisActivity -DatabasePath (Join-Path (Split-Path $fakeHermes -Parent) 'jarvis-mission-control\agent-logs.db'))
            $rows[-1].task_description | Should Match 'Builder orientation: skipped'
            $rows[-1].task_description | Should Match 'native profile_routes'
        } finally {
            Remove-Item Env:JARVIS_HERMES_CLI -ErrorAction SilentlyContinue
            if ($null -eq $oldHermes) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue } else { $env:HERMES_HOME = $oldHermes }
            if ($null -eq $oldState) { Remove-Item Env:JARVIS_STATE_ROOT -ErrorAction SilentlyContinue } else { $env:JARVIS_STATE_ROOT = $oldState }
        }
    }

    It 'records provider-neutral builder orientation without making it a Hermes profile' {
        $caseRoot = Join-Path $TestDrive 'oriented-case'
        $fakeHermes = Join-Path $caseRoot 'oriented-hermes'
        $fakeState = Join-Path $caseRoot 'oriented-state'
        New-Item -ItemType Directory -Force -Path $fakeHermes,$fakeState | Out-Null
        $oldHermes = $env:HERMES_HOME
        $oldState = $env:JARVIS_STATE_ROOT
        try {
            $env:HERMES_HOME = $fakeHermes
            $env:JARVIS_STATE_ROOT = $fakeState
            [ordered]@{ name='Owner'; work='work'; timezone='UTC'; hours='9-5'; weather_city='City'; priority='priority'; telegram_chat_id='-100'; interview=@('a','b','c','d','e','f') } |
                ConvertTo-Json -Depth 5 | Set-Content (Join-Path $fakeState 'inputs.json') -Encoding UTF8
            $env:JARVIS_HERMES_CLI = Join-Path $TestDrive 'must-not-run-hermes.exe'
            & (Join-Path $PSScriptRoot '..\installer\install.ps1') -Step 13 -WithBuilderOrientation 2>&1 | Out-Null
            $? | Should Be $true
            $rows = @(Get-JarvisActivity -DatabasePath (Join-Path (Split-Path $fakeHermes -Parent) 'jarvis-mission-control\agent-logs.db'))
            $rows[-1].task_description | Should Match 'provider-neutral external builder'
            $rows[-1].task_description | Should Match 'builder-only'
            $rows[-1].task_description | Should Match 'keeps running when the builder closes'
        } finally {
            Remove-Item Env:JARVIS_HERMES_CLI -ErrorAction SilentlyContinue
            if ($null -eq $oldHermes) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue } else { $env:HERMES_HOME = $oldHermes }
            if ($null -eq $oldState) { Remove-Item Env:JARVIS_STATE_ROOT -ErrorAction SilentlyContinue } else { $env:JARVIS_STATE_ROOT = $oldState }
        }
    }

    It 'performs a dry run through step 14 without Hermes, Ollama, or writes' {
        $caseRoot = Join-Path $TestDrive 'dry-case'
        $fakeHermes = Join-Path $caseRoot 'dry-hermes'
        $fakeState = Join-Path $caseRoot 'dry-state'
        New-Item -ItemType Directory -Force -Path $fakeHermes,$fakeState | Out-Null
        $oldHermes = $env:HERMES_HOME
        $oldState = $env:JARVIS_STATE_ROOT
        try {
            $env:HERMES_HOME = $fakeHermes
            $env:JARVIS_STATE_ROOT = $fakeState
            $env:JARVIS_DRYRUN_HERMES = Join-Path $TestDrive 'must-not-run-hermes.exe'
            $output = @(& (Join-Path $PSScriptRoot '..\installer\install.ps1') -DryRun -Through 14 2>&1 | Out-String) -join "`n"
            $? | Should Be $true
            $output | Should Match 'through step 14'
            @(Get-ChildItem -LiteralPath $fakeState -Force).Count | Should Be 0
            Test-Path (Join-Path (Split-Path $fakeHermes -Parent) 'jarvis-mission-control') | Should Be $false
        } finally {
            Remove-Item Env:JARVIS_DRYRUN_HERMES -ErrorAction SilentlyContinue
            if ($null -eq $oldHermes) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue } else { $env:HERMES_HOME = $oldHermes }
            if ($null -eq $oldState) { Remove-Item Env:JARVIS_STATE_ROOT -ErrorAction SilentlyContinue } else { $env:JARVIS_STATE_ROOT = $oldState }
        }
    }

    It 'completes a real step 14 survey when a large profile inventory truncates the activity detail' {
        $caseRoot = Join-Path $TestDrive 'survey-case'
        $fakeHermes = Join-Path $caseRoot 'survey-hermes'
        $fakeState = Join-Path $caseRoot 'survey-state'
        New-Item -ItemType Directory -Force -Path $fakeHermes,$fakeState | Out-Null
        foreach ($number in 1..40) { New-Item -ItemType Directory -Force -Path (Join-Path $fakeHermes ("profiles\profile-{0:D2}" -f $number)) | Out-Null }
        $oldHermes = $env:HERMES_HOME
        $oldState = $env:JARVIS_STATE_ROOT
        try {
            $env:HERMES_HOME = $fakeHermes
            $env:JARVIS_STATE_ROOT = $fakeState
            [ordered]@{ name='Owner'; work='work'; timezone='UTC'; hours='9-5'; weather_city='City'; priority='priority'; telegram_chat_id='-100'; interview=@('a','b','c','d','e','f') } |
                ConvertTo-Json -Depth 5 | Set-Content (Join-Path $fakeState 'inputs.json') -Encoding UTF8
            & (Join-Path $PSScriptRoot '..\installer\install.ps1') -Step 14 2>&1 | Out-Null
            $? | Should Be $true
            $progress = Get-Content (Join-Path $fakeState 'progress.json') -Raw | ConvertFrom-Json
            (@($progress.completed) -contains 14) | Should Be $true
        } finally {
            if ($null -eq $oldHermes) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue } else { $env:HERMES_HOME = $oldHermes }
            if ($null -eq $oldState) { Remove-Item Env:JARVIS_STATE_ROOT -ErrorAction SilentlyContinue } else { $env:JARVIS_STATE_ROOT = $oldState }
        }
    }

    It 'saves step one progress without nested array conversion errors' {
        $fakeHermes = Join-Path $TestDrive 'hermes'
        $fakeState = Join-Path $TestDrive 'state'
        New-Item -ItemType Directory -Force -Path (Join-Path $fakeHermes 'memories') | Out-Null
        New-Item -ItemType Directory -Force -Path $fakeState | Out-Null
        $inputs = [ordered]@{
            name = 'Owner'; work = 'work'; timezone = 'UTC'; hours = '9-5'; weather_city = 'City'; priority = 'priority'; telegram_chat_id = '-100'
            interview = @('a','b','c','d','e','f')
        }
        $oldHermes = $env:HERMES_HOME
        $oldState = $env:JARVIS_STATE_ROOT
        try {
            $env:HERMES_HOME = $fakeHermes
            $env:JARVIS_STATE_ROOT = $fakeState
            $inputs | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $fakeState 'inputs.json') -Encoding UTF8
            & (Join-Path $PSScriptRoot '..\installer\install.ps1') -Step 1 2>&1 | Out-Null
            $? | Should Be $true
            $progress = Get-Content (Join-Path $fakeState 'progress.json') -Raw | ConvertFrom-Json
            (@($progress.completed) -contains 1) | Should Be $true
        } finally {
            if ($null -eq $oldHermes) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue } else { $env:HERMES_HOME = $oldHermes }
            if ($null -eq $oldState) { Remove-Item Env:JARVIS_STATE_ROOT -ErrorAction SilentlyContinue } else { $env:JARVIS_STATE_ROOT = $oldState }
        }
    }
}
