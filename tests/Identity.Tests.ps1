$module = Join-Path $PSScriptRoot '..\installer\lib\identity.psm1'
Import-Module $module -Force

Describe 'JARVIS owner form validation' {
    It 'rejects a form with missing required values' {
        $form = [pscustomobject]@{ name = $null; work = 'work'; timezone = 'UTC'; hours = '9-5'; weather_city = 'City'; priority = 'priority'; interview = @('a','b','c','d','e','f') }
        Test-JarvisOwnerForm -Form $form | Should Be $false
    }

    It 'accepts six complete interview answers' {
        $form = [pscustomobject]@{ name = 'Owner'; work = 'work'; timezone = 'UTC'; hours = '9-5'; weather_city = 'City'; priority = 'priority'; interview = @('a','b','c','d','e','f') }
        Test-JarvisOwnerForm -Form $form | Should Be $true
    }
}
