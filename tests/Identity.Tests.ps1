$module = Join-Path $PSScriptRoot '..\installer\lib\identity.psm1'
Import-Module $module -Force

Describe 'JARVIS owner form validation' {
    It 'rejects a form with missing required values' {
        $form = [pscustomobject]@{ name = $null; work = 'work'; timezone = 'UTC'; hours = '9-5'; weather_city = 'City'; priority = 'priority'; telegram_chat_id = '-100'; interview = @('a','b','c','d','e','f') }
        Test-JarvisOwnerForm -Form $form | Should Be $false
    }

    It 'accepts six complete interview answers' {
        $form = [pscustomobject]@{ name = 'Owner'; work = 'work'; timezone = 'UTC'; hours = '9-5'; weather_city = 'City'; priority = 'priority'; telegram_chat_id = '-100'; interview = @('a','b','c','d','e','f') }
        Test-JarvisOwnerForm -Form $form | Should Be $true
    }

    It 'merges saved values and identifies only missing fields' {
        $saved = [pscustomobject]@{ name = 'Owner'; work = $null; timezone = 'UTC'; hours = '9-5'; weather_city = 'City'; priority = 'priority'; telegram_chat_id = $null; interview = @('a','b','c','d','e','f') }
        $missing = Get-JarvisMissingOwnerFields -Form $saved
        (@($missing) -contains 'work') | Should Be $true
        (@($missing) -contains 'telegram_chat_id') | Should Be $true
        (@($missing) -contains 'name') | Should Be $false
    }
}
