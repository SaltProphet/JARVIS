param([Parameter(Mandatory=$true)][string]$Note, [string]$ProjectRoot = $env:JARVIS_PROJECT_ROOT, [string]$BackupRoot = $env:JARVIS_BACKUP_ROOT)
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$target = Join-Path $BackupRoot $stamp
New-Item -ItemType Directory -Force -Path $target | Out-Null
$files = @('server.py','index.html','styles.css','script.js','jarvis-dashboard-template.html')
foreach ($file in $files) { $source = Join-Path $ProjectRoot $file; if (Test-Path $source) { Copy-Item $source (Join-Path $target $file) -Force } }
"note=$Note`nfiles=$($files -join ',')" | Set-Content (Join-Path $target 'MANIFEST') -Encoding UTF8
@"
param([string]`$Source = (Split-Path -Parent `$MyInvocation.MyCommand.Path), [string]`$Destination = '$ProjectRoot')
Copy-Item (Join-Path `$Source '*.py') `$Destination -Force
Copy-Item (Join-Path `$Source '*.html') `$Destination -Force
Copy-Item (Join-Path `$Source '*.css') `$Destination -Force
Copy-Item (Join-Path `$Source '*.js') `$Destination -Force
"@ | Set-Content (Join-Path $target 'restore.ps1') -Encoding UTF8
Write-Output $target
