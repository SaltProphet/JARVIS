$module = Join-Path $PSScriptRoot '..\installer\lib\common.psm1'
Import-Module $module -Force

Describe 'JARVIS installer common safeguards' {
    It 'derives all runtime paths from a supplied Hermes home' {
        $paths = Get-JarvisPaths -HermesHome 'C:\fake\hermes' -StateRoot 'C:\fake\state'
        $paths.HermesHome | Should Be 'C:\fake\hermes'
        $paths.StateRoot | Should Be 'C:\fake\state'
        $paths.ProjectRoot | Should Be 'C:\fake\jarvis-mission-control'
        $paths.BackupRoot | Should Be 'C:\fake\jarvis-mission-control-backups'
    }

    It 'redacts secret values while preserving secret name and length' {
        $line = Format-JarvisSecret -Name 'TELEGRAM_BOT_TOKEN' -Value 'abcdefghij'
        $line | Should Be 'TELEGRAM_BOT_TOKEN=<redacted; length 10>'
        $line | Should Not Match 'abcdefghij'
    }

    It 'rejects a busy dashboard port' {
        $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 18899)
        $listener.Start()
        try { Test-JarvisPortFree -Port 18899 | Should Be $false } finally { $listener.Stop() }
    }

    It 'requires the protected companion processes to be running' {
        Test-JarvisRequiredProcesses -Names @('process-that-cannot-exist-jarvis') | Should Be $false
    }

    It 'merges progress without losing completed steps' {
        $file = Join-Path $TestDrive 'progress.json'
        Save-JarvisProgress -Path $file -Completed @(1, 2) -Current 3
        Save-JarvisProgress -Path $file -Completed @(1, 2, 3) -Current 4
        $progress = Get-Content $file -Raw | ConvertFrom-Json
        (@($progress.completed) -contains 3) | Should Be $true
        $progress.current | Should Be 4
    }

}
