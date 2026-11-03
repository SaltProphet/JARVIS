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
            $rows[-1].task_description | Should Match '^step=13; orientation=skipped;'
            $rows[-1].task_description | Should Match 'routing=native-profile-routes'
            $rows[-1].task_description | Should Match 'independence=external-builder-optional'
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
            $rows[-1].task_description | Should Match '^step=13; orientation=recorded; evidence=provider-neutral;'
            $rows[-1].task_description | Should Match 'scope=layout,crew,routing,project,builder-only,independence'
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
        New-Item -ItemType Directory -Force -Path (Join-Path $fakeHermes 'logs') | Out-Null
        'gateway status line with private value 999999' | Set-Content (Join-Path $fakeHermes 'logs\gateway.log') -Encoding UTF8
        '{"pid":4321,"gateway_state":"running","updated_at":1793707200.5}' | Set-Content (Join-Path $fakeHermes 'gateway_state.json') -Encoding UTF8
        $fixture = "import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);c.execute('CREATE TABLE sessions (created_at TEXT)');c.execute('INSERT INTO sessions VALUES (?)',('2026-11-03T12:00:00+00:00',));c.commit();c.close()"
        & py -3.12 -c $fixture (Join-Path $fakeHermes 'state.db')
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
            $evidencePath = Join-Path $fakeState 'step-14-survey.json'
            Test-Path -LiteralPath $evidencePath | Should Be $true
            $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
            $evidence.step | Should Be 14
            $evidence.status | Should Be 'completed'
            $evidence.profile | Should Be 'dev'
            $evidence.source_count | Should Be @($evidence.sources).Count
            @($evidence.sources).Count | Should BeGreaterThan 80
            (@($evidence.sources.name) -contains 'hermes-profile-profile-40-state') | Should Be $true
            (@($evidence.sources.name) -contains 'hermes-cron-profile-40') | Should Be $true
            (@($evidence.sources.name) -contains 'hermes-gateway-logs') | Should Be $true
            $default = @($evidence.sources | Where-Object name -eq 'hermes-default-state')[0]
            (@($default.tables) -contains 'sessions') | Should Be $true
            (@($default.timestamp_types) -contains 'iso-8601') | Should Be $true
            $gateway = @($evidence.sources | Where-Object name -eq 'hermes-gateway-state')[0]
            (@($gateway.keys) -contains 'pid') | Should Be $true
            @($evidence.limitations).Count | Should BeGreaterThan 0
            (Get-Content -LiteralPath $evidencePath -Raw) | Should Not Match '999999'
            $rows = @(Get-JarvisActivity -DatabasePath (Join-Path (Split-Path $fakeHermes -Parent) 'jarvis-mission-control\agent-logs.db'))
            $rows[-1].task_description | Should Be 'step=14; survey=completed; evidence=step-14-survey.json'
            $originalEvidence = Get-Content -LiteralPath $evidencePath -Raw
            foreach ($mutation in @('source','table','key','timestamp','limitation')) {
                $changed = $originalEvidence | ConvertFrom-Json
                switch ($mutation) {
                    'source' { $changed.sources = @($changed.sources | Where-Object name -ne 'hermes-profile-profile-40-state'); $changed.source_count = @($changed.sources).Count }
                    'table' { @($changed.sources | Where-Object name -eq 'hermes-default-state')[0].tables = @() }
                    'key' { @($changed.sources | Where-Object name -eq 'hermes-gateway-state')[0].keys = @() }
                    'timestamp' { @($changed.sources | Where-Object name -eq 'hermes-default-state')[0].timestamp_types = @() }
                    'limitation' { $changed.limitations = @('invented limitation') }
                }
                $changed | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
                Test-JarvisStepPostCheck -Number 14 -Paths (Get-JarvisPaths -HermesHome $fakeHermes -StateRoot $fakeState) -Root (Join-Path $PSScriptRoot '..\installer') | Should Be $false
            }
            $originalEvidence | Set-Content -LiteralPath $evidencePath -Encoding UTF8
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
