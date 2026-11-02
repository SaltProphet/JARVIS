Describe 'Installer progress with a fake Hermes home' {
    It 'supports a bounded dry run through milestone one' {
        $fakeHermes = Join-Path $TestDrive 'through-hermes'
        $fakeState = Join-Path $TestDrive 'through-state'
        New-Item -ItemType Directory -Force -Path $fakeHermes,$fakeState | Out-Null
        $env:HERMES_HOME = $fakeHermes
        $env:JARVIS_STATE_ROOT = $fakeState
        try {
            $output = @(& (Join-Path $PSScriptRoot '..\installer\install.ps1') -DryRun -Through 12 2>&1 | Out-String) -join "`n"
            $? | Should Be $true
            $output | Should Match 'through step 12'
            $output | Should Not Match 'Step 13 pre-check'
        } finally {
            Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue
            Remove-Item Env:JARVIS_STATE_ROOT -ErrorAction SilentlyContinue
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
