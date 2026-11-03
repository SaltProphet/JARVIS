$dashboard = Join-Path $PSScriptRoot '..\installer\lib\dashboard.psm1'
$common = Join-Path $PSScriptRoot '..\installer\lib\common.psm1'
$steps = Join-Path $PSScriptRoot '..\installer\lib\steps.psm1'
Import-Module $common -Force
Import-Module $dashboard -Force
Import-Module $steps -Force

Describe 'Dashboard snapshots' {
    It 'executes backup undo entries in reverse order and restores exact bytes' {
        $project = Join-Path $TestDrive 'undo-project'
        $backups = Join-Path $TestDrive 'undo-backups'
        $undo = Join-Path $TestDrive 'undo-state\undo.ps1'
        New-Item -ItemType Directory -Force -Path $project | Out-Null
        $file = Join-Path $project 'server.py'
        [IO.File]::WriteAllBytes($file, [byte[]](0,10,13,255))
        Backup-JarvisFile -Path $file -BackupRoot $backups -RelativeTo $project -UndoPath $undo -Timestamp 'before' | Out-Null
        [IO.File]::WriteAllBytes($file, [byte[]](9,9,9))
        Invoke-JarvisUndoFile -Path $undo
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($file)) | Should Be 'AAoN/w=='
    }

    It 'manifests only copied files and restores their exact bytes' {
        $project = Join-Path $TestDrive 'project'
        $backups = Join-Path $TestDrive 'backups'
        New-Item -ItemType Directory -Force -Path $project,$backups | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $project 'server.py'), [byte[]](0,1,2,255))
        [IO.File]::WriteAllBytes((Join-Path $project 'index.html'), [Text.Encoding]::UTF8.GetBytes('original index'))
        $snapshot = & (Join-Path $PSScriptRoot '..\installer\dashboard\jarvis-backup.ps1') -Note 'pre-wiring baseline' -ProjectRoot $project -BackupRoot $backups -Timestamp '20261103-120000'
        $manifest = Get-Content -LiteralPath (Join-Path $snapshot 'MANIFEST') -Raw | ConvertFrom-Json
        @($manifest.files) | Should Be @('server.py','index.html')
        $manifest.note | Should Be 'pre-wiring baseline'
        [IO.File]::WriteAllBytes((Join-Path $project 'server.py'), [byte[]](9,9))
        Remove-Item -LiteralPath (Join-Path $project 'index.html')
        & (Join-Path $snapshot 'restore.ps1') -Destination $project
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $project 'server.py'))) | Should Be 'AAEC/w=='
        [IO.File]::ReadAllText((Join-Path $project 'index.html')) | Should Be 'original index'
        Test-Path (Join-Path $project 'styles.css') | Should Be $false
    }

    It 'creates collision-safe snapshots for the same timestamp' {
        $project = Join-Path $TestDrive 'collision-project'
        $backups = Join-Path $TestDrive 'collision-backups'
        New-Item -ItemType Directory -Force -Path $project,$backups | Out-Null
        Set-Content -LiteralPath (Join-Path $project 'server.py') -Value 'one'
        $first = & (Join-Path $PSScriptRoot '..\installer\dashboard\jarvis-backup.ps1') -Note first -ProjectRoot $project -BackupRoot $backups -Timestamp 'same'
        $second = & (Join-Path $PSScriptRoot '..\installer\dashboard\jarvis-backup.ps1') -Note second -ProjectRoot $project -BackupRoot $backups -Timestamp 'same'
        $first | Should Not Be $second
        Test-Path -LiteralPath $first | Should Be $true
        Test-Path -LiteralPath $second | Should Be $true
    }

    It 'can restore a prior scheduled task definition from an undo entry' {
        $taskXml = Join-Path $TestDrive 'previous-task.xml'
        $fakeTasks = Join-Path $TestDrive 'fake-schtasks.cmd'
        $calls = Join-Path $TestDrive 'schtasks-calls.txt'
        Set-Content -LiteralPath $taskXml -Value '<Task />' -Encoding UTF8
        Set-Content -LiteralPath $fakeTasks -Value "@echo %*>>`"$calls`"`r`n@exit /b 0" -Encoding ASCII
        $undo = Join-Path $TestDrive 'task-undo.ps1'
        Set-Content -LiteralPath $undo -Value "Register-JarvisScheduledTask -TaskName 'JARVIS Mission Control' -XmlPath '$taskXml'" -Encoding UTF8
        Invoke-JarvisUndoFile -Path $undo -ScheduledTasks $fakeTasks
        (Get-Content -LiteralPath $calls -Raw) | Should Match '/Create /TN "?JARVIS Mission Control"? /XML .*previous-task\.xml /F'
    }
}

Describe 'Dashboard scheduled task and installer steps' {
    It 'verifies and records an explicit supported Python interpreter' {
        $python = (& py -3.12 -c "import sys; print(sys.executable)").Trim()
        $runtime = Resolve-JarvisDashboardPython -PythonExecutable $python
        $runtime.Executable | Should Be $python
        ([version]$runtime.Version -ge [version]'3.9') | Should Be $true
        { Assert-JarvisDashboardPythonVersion -Version '3.8.10' } | Should Throw
    }

    It 'generates restart recovery XML with the verified interpreter and script' {
        $project = 'C:\Users\Owner\jarvis-mission-control'
        $python = 'C:\Python312\python.exe'
        $xml = New-JarvisDashboardTaskXml -ProjectRoot $project -PythonExecutable $python
        $xml.Task.Settings.RestartOnFailure.Interval | Should Be 'PT1M'
        $xml.Task.Settings.RestartOnFailure.Count | Should Be '3'
        $xml.Task.Actions.Exec.Command | Should Be $python
        $xml.Task.Actions.Exec.Arguments | Should Be ('"' + (Join-Path $project 'server.py') + '"')
        $xml.Task.Triggers.LogonTrigger.Enabled | Should Be 'true'
    }

    It 'requires substantive artifacts for steps 15 through 18' {
        $project = Join-Path $TestDrive 'post-project'
        $state = Join-Path $TestDrive 'post-state'
        $hermes = Join-Path $TestDrive 'post-hermes'
        New-Item -ItemType Directory -Force -Path $project,$state,$hermes | Out-Null
        $paths = [pscustomobject]@{ ProjectRoot=$project; StateRoot=$state; HermesHome=$hermes; BackupRoot=(Join-Path $TestDrive 'post-backups') }
        foreach ($number in 15..18) { Test-JarvisStepPostCheck -Number $number -Paths $paths -Root $TestDrive | Should Be $false }
    }

    It 'dry runs through step 18 without files tasks processes or network probes' {
        $case = Join-Path $TestDrive 'dry-18'
        $hermes = Join-Path $case 'hermes'
        $state = Join-Path $case 'state'
        New-Item -ItemType Directory -Force -Path $hermes,$state | Out-Null
        $oldHermes = $env:HERMES_HOME
        $oldState = $env:JARVIS_STATE_ROOT
        $oldTasks = $env:JARVIS_SCHTASKS
        try {
            $env:HERMES_HOME = $hermes
            $env:JARVIS_STATE_ROOT = $state
            $env:JARVIS_SCHTASKS = Join-Path $case 'must-not-run-schtasks.exe'
            $output = @(& (Join-Path $PSScriptRoot '..\installer\install.ps1') -DryRun -Through 18 2>&1 | Out-String) -join "`n"
            $? | Should Be $true
            $output | Should Match 'through step 18'
            @(Get-ChildItem -LiteralPath $state -Force).Count | Should Be 0
            Test-Path (Join-Path $case 'jarvis-mission-control') | Should Be $false
        } finally {
            if ($null -eq $oldHermes) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue } else { $env:HERMES_HOME = $oldHermes }
            if ($null -eq $oldState) { Remove-Item Env:JARVIS_STATE_ROOT -ErrorAction SilentlyContinue } else { $env:JARVIS_STATE_ROOT = $oldState }
            if ($null -eq $oldTasks) { Remove-Item Env:JARVIS_SCHTASKS -ErrorAction SilentlyContinue } else { $env:JARVIS_SCHTASKS = $oldTasks }
        }
    }
}
