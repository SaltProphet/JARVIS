[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Note,
    [string]$ProjectRoot = $env:JARVIS_PROJECT_ROOT,
    [string]$BackupRoot = $env:JARVIS_BACKUP_ROOT,
    [string]$Timestamp = $(Get-Date -Format 'yyyyMMdd-HHmmss')
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot) -or -not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { throw 'ProjectRoot must be an existing directory.' }
if ([string]::IsNullOrWhiteSpace($BackupRoot)) { throw 'BackupRoot is required.' }
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
$target = Join-Path $BackupRoot ("$Timestamp-$([guid]::NewGuid().ToString('N'))")
New-Item -ItemType Directory -Path $target | Out-Null

$wanted = @('server.py','index.html','styles.css','script.js','jarvis-dashboard-template.html','version.txt')
$copied = @()
foreach ($file in $wanted) {
    $source = Join-Path $ProjectRoot $file
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $target $file)
        $copied += $file
    }
}
$manifest = [ordered]@{
    format_version = 1
    note = $Note
    created_at = [DateTime]::UtcNow.ToString('o')
    files = @($copied)
}
[IO.File]::WriteAllText(
    (Join-Path $target 'MANIFEST'),
    ($manifest | ConvertTo-Json -Depth 4),
    (New-Object Text.UTF8Encoding($false))
)

$restoreLines = @(
    '[CmdletBinding()]',
    'param([string]$Destination)',
    '$ErrorActionPreference = ''Stop''',
    'if ([string]::IsNullOrWhiteSpace($Destination) -or -not (Test-Path -LiteralPath $Destination -PathType Container)) { throw ''Destination must be an existing directory.'' }',
    '$Source = Split-Path -Parent $MyInvocation.MyCommand.Path'
)
foreach ($file in $copied) {
    $restoreLines += "Copy-Item -LiteralPath (Join-Path `$Source '$file') -Destination (Join-Path `$Destination '$file') -Force"
}
[IO.File]::WriteAllText(
    (Join-Path $target 'restore.ps1'),
    (($restoreLines -join "`r`n") + "`r`n"),
    (New-Object Text.UTF8Encoding($false))
)
Write-Output $target
