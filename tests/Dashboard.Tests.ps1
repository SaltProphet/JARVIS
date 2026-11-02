$module = Join-Path $PSScriptRoot '..\installer\lib\dashboard.psm1'
Import-Module $module -Force

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
}
