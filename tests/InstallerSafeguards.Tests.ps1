$steps = Join-Path $PSScriptRoot '..\installer\lib\steps.psm1'
$common = Join-Path $PSScriptRoot '..\installer\lib\common.psm1'
$identity = Join-Path $PSScriptRoot '..\installer\lib\identity.psm1'
$telegram = Join-Path $PSScriptRoot '..\installer\lib\telegram.psm1'
Import-Module $steps -Force
Import-Module $common -Force
Import-Module $identity -Force
Import-Module $telegram -Force

Describe 'JARVIS model safeguards' {
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
