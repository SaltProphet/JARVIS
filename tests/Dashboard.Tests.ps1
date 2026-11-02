$module = Join-Path $PSScriptRoot '..\installer\lib\dashboard.psm1'
Import-Module $module -Force
Import-Module (Join-Path $PSScriptRoot '..\installer\lib\steps.psm1') -Force

Describe 'Dashboard contract helpers' {
    It 'returns the fixed crew keys' {
        $crew = Get-JarvisCrew
        @($crew.key) | Should Be @('default', 'dev', 'research', 'assistant')
        @($crew.name) | Should Be @('JARVIS', 'DEV', 'RESEARCH', 'ASSISTANT')
    }

    It 'rejects upload traversal and unsupported extensions' {
        { Assert-JarvisUploadName -Name '..\evil.html' } | Should Throw
        { Assert-JarvisUploadName -Name 'payload.exe' } | Should Throw
        Assert-JarvisUploadName -Name 'jarvis-dashboard-template.html' | Should Be $true
    }

    It 'defines a real action and post-check for every installer step' {
        $definitions = Get-JarvisStepDefinitions
        @($definitions).Count | Should Be 48
        foreach ($definition in $definitions) {
            $definition.Action | Should Not BeNullOrEmpty
            $definition.PreCheck | Should Not BeNullOrEmpty
            $definition.PostCheck | Should Not BeNullOrEmpty
        }
    }

    It 'does not claim a later milestone is complete without its real end state' {
        $paths = [pscustomobject]@{ ProjectRoot = $TestDrive; HermesHome = (Join-Path $TestDrive 'hermes'); StateRoot = (Join-Path $TestDrive 'state') }
        New-Item -ItemType Directory -Force -Path $paths.HermesHome | Out-Null
        Test-JarvisStepPostCheck -Number 19 -Paths $paths -Root $PSScriptRoot -DryRun:$false | Should Be $false
    }
}
