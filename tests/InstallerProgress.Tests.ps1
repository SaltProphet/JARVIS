Describe 'Installer progress with a fake Hermes home' {
    It 'saves step one progress without nested array conversion errors' {
        $fakeHermes = Join-Path $TestDrive 'hermes'
        $fakeState = Join-Path $TestDrive 'state'
        New-Item -ItemType Directory -Force -Path (Join-Path $fakeHermes 'memories') | Out-Null
        New-Item -ItemType Directory -Force -Path $fakeState | Out-Null
        $inputs = [ordered]@{
            name = 'Owner'; work = 'work'; timezone = 'UTC'; hours = '9-5'; weather_city = 'City'; priority = 'priority'
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
