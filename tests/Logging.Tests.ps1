$module = Join-Path $PSScriptRoot '..\installer\lib\logging.psm1'
Import-Module $module -Force

Describe 'JARVIS activity logging' {
    It 'creates the required SQLite schema and normalizes agent names' {
        $db = Join-Path $TestDrive 'agent-logs.db'
        Initialize-JarvisActivityLog -DatabasePath $db
        Add-JarvisActivity -DatabasePath $db -Agent 'default' -Description 'boot check' -Status 'completed' -Model 'gpt-oss:20b'
        $rows = @(Get-JarvisActivity -DatabasePath $db)
        $rows.Count | Should Be 1
        $rows[0].agent_name | Should Be 'JARVIS'
        $rows[0].task_description | Should Be 'boot check'
        $rows[0].model_used | Should Be 'gpt-oss:20b'
    }

    It 'stores an omitted model as null without shifting logger arguments' {
        $db = Join-Path $TestDrive 'model-null.db'
        Add-JarvisActivity -DatabasePath $db -Agent 'DEV' -Description 'surveyed sources' -Status 'completed'
        $row = @(Get-JarvisActivity -DatabasePath $db)[0]
        $row.task_description | Should Be 'surveyed sources'
        $row.status | Should Be 'completed'
        $row.model_used | Should Be $null
    }

    It 'rejects invalid statuses' {
        $db = Join-Path $TestDrive 'agent-logs.db'
        { Add-JarvisActivity -DatabasePath $db -Agent 'DEV' -Description 'bad' -Status 'waiting' } | Should Throw
    }
}
