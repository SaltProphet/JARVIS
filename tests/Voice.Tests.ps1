$module = Join-Path $PSScriptRoot '..\installer\lib\voice.psm1'
Import-Module $module -Force

Describe 'Kokoro runtime selection' {
    It 'prefers the supported Python 3.12 launcher over the user default' {
        $result = Select-JarvisVoicePython -Python312 'C:\Python312\python.exe' -DefaultPython 'C:\Python314\python.exe'
        $result.Version | Should Be '3.12'
        $result.Executable | Should Be 'C:\Python312\python.exe'
    }

    It 'records the exact interpreter in local state' {
        $file = Join-Path $TestDrive 'voice-runtime.json'
        Save-JarvisVoiceRuntime -Path $file -Executable 'C:\Python312\python.exe' -Version '3.12.13'
        $runtime = Get-Content $file -Raw | ConvertFrom-Json
        $runtime.executable | Should Be 'C:\Python312\python.exe'
        $runtime.version | Should Be '3.12.13'
    }
}
