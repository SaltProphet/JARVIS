Set-StrictMode -Version Latest

function Invoke-JarvisSqlite {
    param([string[]]$Arguments)
    $helper = Join-Path $PSScriptRoot 'sqlite_helper.py'
    $output = & py -3.12 $helper @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join [Environment]::NewLine) }
    $output
}

function Initialize-JarvisActivityLog {
    param([string]$DatabasePath)
    New-Item -ItemType Directory -Force -Path (Split-Path $DatabasePath -Parent) | Out-Null
    Invoke-JarvisSqlite @($DatabasePath, 'init') | Out-Null
}

function Add-JarvisActivity {
    param([string]$DatabasePath, [string]$Agent, [string]$Description, [ValidateSet('completed','failed','running')][string]$Status, [string]$Model = '')
    Initialize-JarvisActivityLog $DatabasePath
    Invoke-JarvisSqlite @($DatabasePath, 'add', $Agent, $Description, $Status, $Model) | Out-Null
}

function Get-JarvisActivity {
    param([string]$DatabasePath)
    Initialize-JarvisActivityLog $DatabasePath
    $raw = Invoke-JarvisSqlite @($DatabasePath, 'get')
    if (-not $raw) { return @() }
    $rows = $raw -join '' | ConvertFrom-Json
    foreach ($row in @($rows)) { Write-Output $row }
}

Export-ModuleMember -Function *-Jarvis*
