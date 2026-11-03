$surveyModule = Join-Path $PSScriptRoot '..\installer\lib\survey.psm1'
$commonModule = Join-Path $PSScriptRoot '..\installer\lib\common.psm1'
Import-Module $commonModule -Force
Import-Module $surveyModule -Force

Describe 'JARVIS read-only data survey' {
    It 'returns structured sanitized facts without changing source bytes' {
        $hermes = Join-Path $TestDrive 'hermes'
        $project = Join-Path $TestDrive 'jarvis-mission-control'
        New-Item -ItemType Directory -Force -Path (Join-Path $hermes 'profiles\dev'),(Join-Path $hermes 'cron'),$project | Out-Null
        $stateDb = Join-Path $hermes 'state.db'
        $profileDb = Join-Path $hermes 'profiles\dev\state.db'
        $kanbanDb = Join-Path $hermes 'kanban.db'
        $activityDb = Join-Path $project 'agent-logs.db'
        $fixture = @'
import sqlite3, sys
path, table = sys.argv[1:3]
con = sqlite3.connect(path)
con.execute('CREATE TABLE alpha (value TEXT)')
con.execute('INSERT INTO alpha VALUES (?)', ('metadata only',))
con.execute('CREATE TABLE ' + table + ' (created_at TEXT, token TEXT, notes TEXT, count INTEGER)')
con.execute('INSERT INTO ' + table + ' VALUES (?, ?, ?, ?)', ('2026-11-03T12:00:00+00:00', 'never-report-this-secret', 'private owner detail', 7))
con.commit()
con.close()
'@
        & py -3.12 -c $fixture $stateDb 'sessions'
        & py -3.12 -c $fixture $profileDb 'messages'
        & py -3.12 -c $fixture $kanbanDb 'tasks'
        & py -3.12 -c $fixture $activityDb 'agent_logs'
        '{"jobs":[{"id":"daily","description":"private cron detail","next_run_at":1793707200}]}' | Set-Content (Join-Path $hermes 'cron\jobs.json') -Encoding UTF8
        '{"pid":4321,"gateway_state":"running","updated_at":1793707200.5,"token":"never-report-this-secret"}' | Set-Content (Join-Path $hermes 'gateway_state.json') -Encoding UTF8
        $paths = [pscustomobject]@{ HermesHome=$hermes; ProjectRoot=$project; StateRoot=(Join-Path $TestDrive 'state') }
        $before = [ordered]@{}
        foreach ($path in @($stateDb,$profileDb,$kanbanDb,$activityDb,(Join-Path $hermes 'cron\jobs.json'),(Join-Path $hermes 'gateway_state.json'))) {
            $before[$path] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
        }

        $result = Get-JarvisDataSurvey -Paths $paths

        @($result.sources).Count | Should BeGreaterThan 5
        @($result.capabilities).Count | Should BeGreaterThan 0
        @($result.limitations).Count | Should BeGreaterThan 0
        $default = @($result.sources | Where-Object name -eq 'hermes-default-state')[0]
        $default.available | Should Be $true
        (@($default.tables) -contains 'sessions') | Should Be $true
        (@($default.timestamp_types) -contains 'iso-8601') | Should Be $true
        ($result | ConvertTo-Json -Depth 12) | Should Not Match 'never-report-this-secret'
        ($result | ConvertTo-Json -Depth 12) | Should Not Match 'private owner detail|private cron detail'
        foreach ($path in $before.Keys) {
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should Be $before[$path]
        }
    }

    It 'reports missing sources and dashboard limitations without throwing' {
        $hermes = Join-Path $TestDrive 'empty-hermes'
        $project = Join-Path $TestDrive 'empty-project'
        New-Item -ItemType Directory -Force -Path $hermes | Out-Null
        $result = Get-JarvisDataSurvey -Paths ([pscustomobject]@{ HermesHome=$hermes; ProjectRoot=$project; StateRoot=(Join-Path $TestDrive 'state') })
        @($result.sources | Where-Object { -not $_.available }).Count | Should BeGreaterThan 0
        ($result.limitations -join ' ') | Should Match 'cost.*unavailable'
    }
}
