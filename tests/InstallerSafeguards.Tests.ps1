$steps = Join-Path $PSScriptRoot '..\installer\lib\steps.psm1'
$common = Join-Path $PSScriptRoot '..\installer\lib\common.psm1'
$identity = Join-Path $PSScriptRoot '..\installer\lib\identity.psm1'
$telegram = Join-Path $PSScriptRoot '..\installer\lib\telegram.psm1'
$logging = Join-Path $PSScriptRoot '..\installer\lib\logging.psm1'
$survey = Join-Path $PSScriptRoot '..\installer\lib\survey.psm1'
Import-Module $steps -Force
Import-Module $common -Force
Import-Module $identity -Force
Import-Module $telegram -Force
Import-Module $logging -Force
Import-Module $survey -Force

Describe 'JARVIS model safeguards' {
    It 'keeps external orientation out of Hermes and routes optional survey interpretation to DEV' {
        Get-JarvisStepPrompt -Number 13 -Root (Join-Path $PSScriptRoot '..\installer') | Should Be $null
        Get-JarvisStepProfile -Number 13 | Should Be $null
        Get-JarvisStepProfile -Number 14 | Should Be 'dev'
    }

    It 'does not accept stale orientation or survey activity as the current post-check' {
        $project = Join-Path $TestDrive 'post-check-project'
        $paths = [pscustomobject]@{ ProjectRoot=$project; HermesHome=(Join-Path $TestDrive 'hermes'); StateRoot=(Join-Path $TestDrive 'state') }
        $db = Join-Path $project 'agent-logs.db'
        Add-JarvisActivity $db 'JARVIS' 'Builder orientation: skipped by test' 'completed'
        Add-JarvisActivity $db 'DEV' 'unrelated later activity' 'completed'
        $rows = @(Get-JarvisActivity $db)
        $rows.Count | Should Be 2
        $rows[-1].task_description | Should Be 'unrelated later activity'
        Test-JarvisStepPostCheck -Number 13 -Paths $paths -Root $TestDrive | Should Be $false
        Add-JarvisActivity $db 'DEV' 'Read-only data survey: limitations=test' 'completed'
        Add-JarvisActivity $db 'JARVIS' 'unrelated later activity' 'completed'
        Test-JarvisStepPostCheck -Number 14 -Paths $paths -Root $TestDrive | Should Be $false
    }

    It 'rejects failed and incomplete step 13 activity rows' {
        $project = Join-Path $TestDrive 'step-13-negative-project'
        $paths = [pscustomobject]@{ ProjectRoot=$project; HermesHome=(Join-Path $TestDrive 'hermes'); StateRoot=(Join-Path $TestDrive 'step-13-state') }
        $db = Join-Path $project 'agent-logs.db'
        Add-JarvisActivity $db 'JARVIS' 'step=13; orientation=skipped; evidence=provider-neutral; routing=native-profile-routes; independence=external-builder-optional' 'failed'
        Test-JarvisStepPostCheck -Number 13 -Paths $paths -Root $TestDrive | Should Be $false
        Add-JarvisActivity $db 'DEV' 'step=13; orientation=recorded; evidence=provider-neutral; scope=layout,crew,routing,project,builder-only,independence; routing=native-profile-routes' 'completed'
        Test-JarvisStepPostCheck -Number 13 -Paths $paths -Root $TestDrive | Should Be $false
        Add-JarvisActivity $db 'JARVIS' 'step=13; orientation=skipped; evidence=incomplete' 'completed'
        Test-JarvisStepPostCheck -Number 13 -Paths $paths -Root $TestDrive | Should Be $false
    }

    It 'rejects failed, incomplete, and structurally invalid step 14 evidence' {
        $project = Join-Path $TestDrive 'step-14-negative-project'
        $state = Join-Path $TestDrive 'step-14-negative-state'
        New-Item -ItemType Directory -Force -Path $state | Out-Null
        $paths = [pscustomobject]@{ ProjectRoot=$project; HermesHome=(Join-Path $TestDrive 'hermes'); StateRoot=$state }
        $db = Join-Path $project 'agent-logs.db'
        Add-JarvisActivity $db 'DEV' 'step=14; survey=completed; evidence=step-14-survey.json' 'failed'
        Test-JarvisStepPostCheck -Number 14 -Paths $paths -Root $TestDrive | Should Be $false
        Add-JarvisActivity $db 'JARVIS' 'step=14; survey=completed; evidence=step-14-survey.json' 'completed'
        Test-JarvisStepPostCheck -Number 14 -Paths $paths -Root $TestDrive | Should Be $false
        '{"step":14,"status":"completed","profile":"dev","source_count":0,"sources":[],"capabilities":[],"limitations":[]}' |
            Set-Content (Join-Path $state 'step-14-survey.json') -Encoding UTF8
        Add-JarvisActivity $db 'DEV' 'step=14; survey=completed; evidence=step-14-survey.json' 'completed'
        Test-JarvisStepPostCheck -Number 14 -Paths $paths -Root $TestDrive | Should Be $false
    }

    It 'rejects no Ollama server' {
        $result = Test-JarvisOllamaReady -Processes @() -Tags @('gpt-oss:20b')
        $result.Message | Should Be "Ollama isn't running. Start the Ollama app once, then rerun."
    }

    It 'rejects two Ollama servers and lists PIDs' {
        $result = Test-JarvisOllamaReady -Processes @([pscustomobject]@{ Id = 12 }, [pscustomobject]@{ Id = 34 }) -Tags @('gpt-oss:20b')
        $result.Message | Should Match 'Two Ollama servers are running.*12.*34'
    }

    It 'rejects Ollama without the required model' {
        $result = Test-JarvisOllamaReady -Processes @([pscustomobject]@{ Id = 12 }) -Tags @('llama3')
        $result.Message | Should Match 'gpt-oss:20b'
    }

    It 'formats a model heartbeat' {
        Format-JarvisModelHeartbeat -Step 6 -Elapsed ([timespan]::FromSeconds(61)) | Should Be 'Step 6, elapsed 00:01:01, waiting on model'
    }

    It 'reports the model time limit' {
        (Get-JarvisModelTimeoutMessage -Step 6 -Minutes 25) | Should Be 'Step 6 exceeded the 25 minute model time limit; its Hermes process was ended. Progress was not advanced. Rerun to resume at step 6.'
    }

    It 'reports post-check output on failure' {
        Get-JarvisPostCheckFailureMessage -Step 6 -Output ('x' * 600) | Should Match 'Step 6 post-check failed.*first 500 characters'
        (Get-JarvisPostCheckFailureMessage -Step 6 -Output ('x' * 600)).Length | Should BeLessThan 650
    }
}

Describe 'JARVIS Telegram and owner form safeguards' {
    It 'normalizes and validates a supergroup chat ID before saving' {
        InModuleScope telegram {
            Mock Invoke-JarvisTelegramApi { [pscustomobject]@{ id = 1003967974233; type = 'supergroup' } }
            Normalize-JarvisTelegramChatId -Token 'token' -ChatId '1003967974233' | Should Be '-1003967974233'
            Assert-MockCalled Invoke-JarvisTelegramApi -ParameterFilter { $Method -eq 'getChat' -and $Body.chat_id -eq '-1003967974233' }
        }
    }

    It 'round trips an apostrophe in a UTF-8 prompt' {
        $file = Join-Path $TestDrive 'prompt.txt'
        $text = "Owner's isolated turn"
        Write-JarvisUtf8Text -Path $file -Text $text
        Read-JarvisUtf8Text -Path $file | Should Be $text
    }

    It 'prompts only for missing saved owner fields' {
        InModuleScope identity {
            $saved = [pscustomobject]@{ name = 'Owner'; work = ''; timezone = 'UTC'; hours = '9-5'; weather_city = 'City'; priority = 'priority'; telegram_chat_id = '-1003967974233'; interview = @('a','b','c','d','e','f') }
            Mock Read-Host { param($Prompt); if ($Prompt -eq 'Owner form: work') { return 'work' }; throw "Unexpected prompt: $Prompt" }
            $result = Complete-JarvisOwnerForm -Form $saved -EnvFile 'missing.env'
            $result.work | Should Be 'work'
            Assert-MockCalled Read-Host -Times 1 -ParameterFilter { $Prompt -eq 'Owner form: work' }
        }
    }
}

Describe 'JARVIS specialist profile encoding safeguards' {
    It 'removes the platforms block without changing non-ASCII config bytes or adding a BOM' {
        $hermes = Join-Path $TestDrive 'hermes'
        $profile = Join-Path $hermes 'profiles\dev'
        $backup = Join-Path $TestDrive 'backups'
        New-Item -ItemType Directory -Force -Path $profile | Out-Null
        $config = Join-Path $profile 'config.yaml'
        $dash = [char]0x2014
        $original = "model:`r`n  name: gpt-oss:20b`r`ndescription: em dash $dash stays`r`nplatforms:`r`n  telegram:`r`n    enabled: true`r`n"
        Write-JarvisUtf8Text -Path $config -Text $original
        InModuleScope common { Mock Test-JarvisHermesYaml { return $true } }
        Invoke-JarvisSpecialistProfileCleanup -ProfileDir $profile -BackupRoot $backup -RelativeTo $hermes -Timestamp 'stamp'
        $expected = "model:`r`n  name: gpt-oss:20b`r`ndescription: em dash $dash stays`r`n"
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($config)) | Should Be ([Convert]::ToBase64String((New-Object Text.UTF8Encoding($false)).GetBytes($expected)))
        (Get-Content -LiteralPath $config -Encoding Byte -TotalCount 3) -join ',' | Should Not Be '239,187,191'
        Test-Path (Join-Path $backup 'stamp\profiles\dev\config.yaml') | Should Be $true
        $afterFirst = [Convert]::ToBase64String([IO.File]::ReadAllBytes($config))
        Invoke-JarvisSpecialistProfileCleanup -ProfileDir $profile -BackupRoot $backup -RelativeTo $hermes -Timestamp 'second-stamp'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($config)) | Should Be $afterFirst
    }

    It 'restores a config when Hermes rejects the cleaned YAML' {
        $hermes = Join-Path $TestDrive 'hermes-restore'
        $profile = Join-Path $hermes 'profiles\dev'
        $backup = Join-Path $TestDrive 'backups-restore'
        New-Item -ItemType Directory -Force -Path $profile | Out-Null
        $config = Join-Path $profile 'config.yaml'
        $original = "description: em dash $([char]0x2014) stays`nplatforms:`n  telegram:`n    enabled: true`n"
        Write-JarvisUtf8Text -Path $config -Text $original
        InModuleScope common { Mock Test-JarvisHermesYaml { throw 'yaml.reader.ReaderError: unacceptable character' } }
        { Invoke-JarvisSpecialistProfileCleanup -ProfileDir $profile -BackupRoot $backup -RelativeTo $hermes -Timestamp 'restore-stamp' } | Should Throw
        Read-JarvisUtf8Text $config | Should Be $original
    }
}

Describe 'JARVIS Hermes process invocation' {
    It 'fails clearly when the work directory does not exist' {
        $prompt = Join-Path $TestDrive 'missing-work-prompt.txt'
        Write-JarvisUtf8Text -Path $prompt -Text 'prompt'
        { Invoke-JarvisAgentTurn -PromptFile $prompt -Hermes 'missing-hermes.exe' -WorkDirectory (Join-Path $TestDrive 'missing-work') } | Should Throw
    }

    It 'defaults the work directory and passes a quoted multiline prompt intact' {
        $root = Join-Path $TestDrive 'hermes-invocation'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $promptFile = Join-Path $root 'prompt.txt'
        $hermes = Join-Path $root 'fake-hermes.exe'
        $quote = [char]34
        Write-JarvisUtf8Text -Path $promptFile -Text "First line with a $quote quote $quote`r`nSecond line with $quote quotes $quote"
        Add-Type -TypeDefinition 'using System; public static class FakeHermes { public static int Main(string[] args) { Console.WriteLine(String.Join("|", args)); for (var i = 0; i < args.Length - 1; i++) { if (args[i] == "--query-file") Console.WriteLine(System.IO.File.ReadAllText(args[i + 1])); } Console.WriteLine("stub response"); return 0; } }' -OutputAssembly $hermes -OutputType ConsoleApplication
        $oldHome = $env:HERMES_HOME
        try {
            $env:HERMES_HOME = $root
            $response = Invoke-JarvisAgentTurn -PromptFile $promptFile -Hermes $hermes -StepNumber 6 -LogPath (Join-Path $root 'missing.log')
        } finally {
            if ($null -eq $oldHome) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue } else { $env:HERMES_HOME = $oldHome }
        }
        $response | Should Match '--query-file\|'
        $response | Should Match 'First line with a .*quote'
        $response | Should Match 'Second line with .*quotes'
        $response | Should Match 'stub response'
    }

    It 'builds a narrow prompt with a strict retry reminder' {
        $promptFile = Join-Path $TestDrive 'narrow-prompt.txt'
        Write-JarvisUtf8Text -Path $promptFile -Text 'Return a compact table with lane and result.'
        $prompt = Get-JarvisInstallerPrompt -PromptFile $promptFile -StepNumber 10 -Retry
        $prompt | Should Match '^ONE JOB: complete only installer step 10\.'
        $prompt | Should Match 'Return a compact table with lane and result\.'
        $prompt | Should Match 'Do not review, read or describe config files\.'
        $prompt.TrimEnd() | Should Match 'Retry once now: follow the exact required output format and do not do anything else\.$'
    }

    It 'uses isolated Hermes settings and the smallest step toolset' {
        $root = Join-Path $TestDrive 'isolated-hermes-invocation'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $promptFile = Join-Path $root 'prompt.txt'
        $hermes = Join-Path $root 'fake-hermes.exe'
        Write-JarvisUtf8Text -Path $promptFile -Text 'Return exactly one line.'
        Add-Type -TypeDefinition 'using System; public static class FakeIsolatedHermes { public static int Main(string[] args) { Console.WriteLine(String.Join("|", args)); return 0; } }' -OutputAssembly $hermes -OutputType ConsoleApplication
        $response = Invoke-JarvisAgentTurn -PromptFile $promptFile -Hermes $hermes -WorkDirectory $root -StepNumber 10 -LogPath (Join-Path $root 'missing.log')
        $response | Should Match '--safe-mode'
        $response | Should Match '--ignore-user-config'
        $response | Should Match '--ignore-rules'
        $response | Should Match '--model\|gpt-oss:20b'
        $response | Should Match '--provider\|custom'
        $response | Should Match '--base-url\|http://127\.0\.0\.1:11434/v1'
        $response | Should Match '--reasoning\|none'
        $response | Should Match '-t\|clarify'
        $response | Should Match 'chat\|--query-file\|'
        $response | Should Match '--oneshot'
    }

    It 'does not pass an empty profile flag for steps without a profile' {
        $root = Join-Path $TestDrive 'unprofiled-hermes-invocation'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $promptFile = Join-Path $root 'prompt.txt'
        $hermes = Join-Path $root 'fake-hermes.exe'
        Write-JarvisUtf8Text -Path $promptFile -Text 'Return exactly one line.'
        Add-Type -TypeDefinition 'using System; public static class FakeUnprofiledHermes { public static int Main(string[] args) { Console.WriteLine(String.Join("|", args)); return 0; } }' -OutputAssembly $hermes -OutputType ConsoleApplication
        $response = Invoke-JarvisAgentTurn -PromptFile $promptFile -Profile '' -Hermes $hermes -WorkDirectory $root -StepNumber 32 -LogPath (Join-Path $root 'missing.log')
        $response | Should Not Match '\|-p'
    }

    It 'uses a fresh Hermes workspace for each isolated turn' {
        $root = Join-Path $TestDrive 'fresh-hermes-workspace'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $promptFile = Join-Path $root 'prompt.txt'
        $hermes = Join-Path $root 'fake-hermes.exe'
        Write-JarvisUtf8Text -Path $promptFile -Text 'Return exactly one line.'
        Add-Type -TypeDefinition 'using System; public static class FakeFreshWorkspaceHermes { public static int Main(string[] args) { Console.WriteLine(String.Join("|", args)); return 0; } }' -OutputAssembly $hermes -OutputType ConsoleApplication
        $response = Invoke-JarvisAgentTurn -PromptFile $promptFile -Hermes $hermes -WorkDirectory $root -StepNumber 10 -LogPath (Join-Path $root 'missing.log')
        $response | Should Match '--in\|'
    }

    It 'ignores a transient agent log lock while polling a model turn' {
        $log = Join-Path $TestDrive 'locked-agent.log'
        Write-JarvisUtf8Text -Path $log -Text 'existing'
        Mock Read-JarvisUtf8Text { throw [IO.IOException]::new('log is locked') } -ModuleName identity
        Get-JarvisAgentLogText -Path $log | Should Be $null
    }
}

Describe 'JARVIS gateway command safeguards' {
    It 'passes non-interactive restart flags and reports stub failure output' {
        $root = Join-Path $TestDrive 'gateway-stub'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $hermes = Join-Path $root 'fake-hermes.exe'
        Add-Type -TypeDefinition 'using System; public static class FakeGatewayHermes { public static int Main(string[] args) { if (Array.IndexOf(args, "fail") >= 0) { Console.Error.WriteLine("refused: interactive confirmation required"); return 7; } if (Array.IndexOf(args, "status") >= 0) { Console.WriteLine("Gateway process running (PID 4321)"); } else { Console.WriteLine(String.Join(" ", args)); } return 0; } }' -OutputAssembly $hermes -OutputType ConsoleApplication
        $restart = Invoke-JarvisHermesCommand -Hermes $hermes -Arguments @('gateway','restart','-y','--detach') -WorkingDirectory $root
        Assert-JarvisHermesCommand -Result $restart -Label 'Hermes gateway restart'
        ($restart.Output -join ' ') | Should Match '-y.*--detach'
        $failure = Invoke-JarvisHermesCommand -Hermes $hermes -Arguments @('gateway','restart','fail') -WorkingDirectory $root
        { Assert-JarvisHermesCommand -Result $failure -Label 'Hermes gateway restart' } | Should Throw
        ($failure.Output -join ' ') | Should Match 'interactive confirmation required'
        $status = Invoke-JarvisHermesCommand -Hermes $hermes -Arguments @('gateway','status') -WorkingDirectory $root
        (Get-JarvisGatewayPid -Output $status.Output) | Should Be 4321
        (Wait-JarvisGatewayRestart -Hermes $hermes -WorkingDirectory $root -PreviousPid 1234 -TimeoutSeconds 2) | Should Be 4321
    }
}

Describe 'JARVIS Telegram topic routing' {
    It 'builds native Hermes profile routes for specialist topics only' {
        $map = [pscustomobject]@{
            chat_id = '-1003967974233'
            topics = [pscustomobject]@{ '35' = 'dev'; '36' = 'research'; '37' = 'assistant' }
        }
        $routes = @(Get-JarvisTelegramProfileRoutes -TopicMap $map)
        $routes.Count | Should Be 3
        ($routes | Where-Object profile -eq 'dev').thread_id | Should Be '35'
        ($routes | Where-Object profile -eq 'research').thread_id | Should Be '36'
        ($routes | Where-Object profile -eq 'assistant').thread_id | Should Be '37'
        ($routes | Where-Object profile -eq 'dev').chat_id | Should Be '-1003967974233'
    }

}

Describe 'JARVIS numeric step formatting' {
    It 'formats a string step number with the numeric D2 format' {
        $step = '10'
        ('agent-turn-{0:D2}.txt' -f [int]$step) | Should Be 'agent-turn-10.txt'
    }
}
