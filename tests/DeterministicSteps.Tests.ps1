$installer = Join-Path $PSScriptRoot '..\installer\install.ps1'
$deterministicSteps = @(
    @{ Number = 3;  Name = 'permanent memory rules' }
    @{ Number = 5;  Name = 'crew profile creation' }
    @{ Number = 8;  Name = 'specialist Telegram isolation' }
    @{ Number = 9;  Name = 'Telegram topic plugin' }
    @{ Number = 11; Name = 'activity logger' }
    @{ Number = 12; Name = 'durable logging smoke rows' }
    @{ Number = 15; Name = 'dashboard service installation' }
    @{ Number = 17; Name = 'dashboard split assets' }
    @{ Number = 18; Name = 'dashboard backup baseline' }
    @{ Number = 19; Name = 'dashboard Home state and events' }
    @{ Number = 20; Name = 'dashboard Agents view' }
    @{ Number = 21; Name = 'chat history and send' }
    @{ Number = 22; Name = 'cron and content routes' }
    @{ Number = 23; Name = 'research document protocol' }
    @{ Number = 25; Name = 'research SerpApi skill' }
    @{ Number = 26; Name = 'model inventory and update' }
    @{ Number = 27; Name = 'Kokoro runtime' }
    @{ Number = 29; Name = 'voice health gate' }
    @{ Number = 30; Name = 'voice scenarios and proxy' }
    @{ Number = 31; Name = 'voice greeting cache' }
    @{ Number = 32; Name = 'push to talk state machine' }
    @{ Number = 33; Name = 'conversation overlay' }
    @{ Number = 34; Name = 'owner shortcuts and greetings' }
    @{ Number = 35; Name = 'Comms dictation' }
    @{ Number = 38; Name = 'briefing configuration' }
    @{ Number = 39; Name = 'poller and stale cache' }
)

Describe 'Deterministic installer steps against a fake Hermes home' {
    BeforeEach {
        $fakeHermes = Join-Path $TestDrive ('hermes-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $fakeHermes 'memories') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $fakeHermes 'profiles') | Out-Null
        Set-Content -LiteralPath (Join-Path $fakeHermes '.env') -Value 'TELEGRAM_BOT_TOKEN=fake-token' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $fakeHermes 'config.yaml') -Value "model:`n  default: gpt-oss:20b`n  provider: custom`n" -Encoding UTF8
    }

    foreach ($spec in $deterministicSteps) {
        It "covers step $($spec.Number): $($spec.Name)" {
            $oldHermes = $env:HERMES_HOME
            try {
                $env:HERMES_HOME = $fakeHermes
                $output = @(& $installer -DryRun -Step $spec.Number 2>&1 | Out-String)
                $text = $output -join "`n"
                $? | Should Be $true
                $text | Should Match "DRY-RUN: Step $($spec.Number) pre-check"
                $text | Should Match "DRY-RUN: Step $($spec.Number) post-check"
                Test-Path -LiteralPath (Join-Path $fakeHermes 'memories\MEMORY.md') | Should Be $false
            } finally {
                if ($null -eq $oldHermes) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue }
                else { $env:HERMES_HOME = $oldHermes }
            }
        }
    }
}
