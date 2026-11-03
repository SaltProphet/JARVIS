$installer = Join-Path $PSScriptRoot '..\installer\install.ps1'
$deterministicSteps = @(
    @{ Number = 3;  Name = 'permanent memory rules' }
    @{ Number = 5;  Name = 'crew profile creation' }
    @{ Number = 8;  Name = 'specialist Telegram isolation' }
    @{ Number = 9;  Name = 'Telegram topic plugin' }
    @{ Number = 11; Name = 'activity logger' }
    @{ Number = 12; Name = 'durable logging smoke rows' }
)

Describe 'Deterministic installer steps against a fake Hermes home' {
    BeforeEach {
        $fakeHermes = Join-Path $TestDrive ('hermes-' + [Guid]::NewGuid().ToString('N'))
        $fakeState = Join-Path $TestDrive ('state-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $fakeHermes 'memories') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $fakeHermes 'profiles') | Out-Null
        New-Item -ItemType Directory -Force -Path $fakeState | Out-Null
        Set-Content -LiteralPath (Join-Path $fakeHermes '.env') -Value 'TELEGRAM_BOT_TOKEN=fake-token' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $fakeHermes 'config.yaml') -Value "model:`n  default: gpt-oss:20b`n  provider: custom`n" -Encoding UTF8
    }

    foreach ($spec in $deterministicSteps) {
        It "covers step $($spec.Number): $($spec.Name)" {
            $oldHermes = $env:HERMES_HOME
            $oldState = $env:JARVIS_STATE_ROOT
            try {
                $env:HERMES_HOME = $fakeHermes
                $env:JARVIS_STATE_ROOT = $fakeState
                $output = @(& $installer -DryRun -Step $spec.Number 2>&1 | Out-String)
                $text = $output -join "`n"
                $? | Should Be $true
                $text | Should Match "DRY-RUN: Step $($spec.Number) pre-check"
                $text | Should Match "DRY-RUN: Step $($spec.Number) post-check"
                Test-Path -LiteralPath (Join-Path $fakeHermes 'memories\MEMORY.md') | Should Be $false
            } finally {
                if ($null -eq $oldHermes) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue }
                else { $env:HERMES_HOME = $oldHermes }
                if ($null -eq $oldState) { Remove-Item Env:JARVIS_STATE_ROOT -ErrorAction SilentlyContinue }
                else { $env:JARVIS_STATE_ROOT = $oldState }
            }
        }
    }
}
