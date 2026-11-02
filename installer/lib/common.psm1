Set-StrictMode -Version Latest

function Get-JarvisPaths {
    param(
        [string]$HermesHome = $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }),
        [string]$StateRoot = $(Join-Path $PSScriptRoot '..\state')
    )
    $hermesRoot = [IO.Path]::GetFullPath($HermesHome)
    $state = [IO.Path]::GetFullPath($StateRoot)
    [pscustomobject]@{
        HermesHome = $hermesRoot
        StateRoot = $state
        BackupRoot = Join-Path (Split-Path $hermesRoot -Parent) 'jarvis-mission-control-backups'
        ProjectRoot = Join-Path (Split-Path $hermesRoot -Parent) 'jarvis-mission-control'
        SecretsRoot = Join-Path $env:LOCALAPPDATA 'jarvis-secrets'
        VoiceRoot = Join-Path $env:LOCALAPPDATA 'jarvis-voice'
    }
}

function Format-JarvisSecret {
    param([string]$Name, [AllowEmptyString()][string]$Value)
    "$Name=<redacted; length $($Value.Length)>"
}

function Test-JarvisPortFree {
    param([int]$Port, [string]$Address = '127.0.0.1')
    $client = New-Object Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($Address, $Port)
        if (-not $task.Wait(250)) { return $true }
        return -not $task.Result
    } catch { return $true } finally { $client.Dispose() }
}

function Test-JarvisRequiredProcesses {
    param([string[]]$Names = @('paperclip', 'postgres', 'ollama'))
    foreach ($name in $Names) {
        if (-not (Get-Process -Name $name -ErrorAction SilentlyContinue)) { return $false }
    }
    $true
}

function Save-JarvisProgress {
    param([string]$Path, [int[]]$Completed = @(), [int]$Current = 1)
    $parent = Split-Path $Path -Parent
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $existing = @()
    if (Test-Path -LiteralPath $Path) {
        try { $existing = @((Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json).completed) } catch { $existing = @() }
    }
    $merged = @($existing + $Completed | Sort-Object -Unique | ForEach-Object { [int]$_ })
    $payload = [ordered]@{ version = 1; completed = $merged; current = $Current; updated_at = [DateTime]::UtcNow.ToString('o') }
    $tmp = "$Path.tmp"
    $payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-JarvisProgress {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ completed = @(); current = 1 } }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Backup-JarvisFile {
    param([string]$Path, [string]$BackupRoot, [string]$Timestamp = $(Get-Date -Format 'yyyyMMdd-HHmmss'), [string]$UndoPath)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $target = Join-Path $BackupRoot $Timestamp
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    $name = Split-Path $Path -Leaf
    Copy-Item -LiteralPath $Path -Destination (Join-Path $target $name) -Force
    if ($UndoPath) { Write-JarvisUndo -Path $UndoPath -Line "Copy-Item -LiteralPath '$target\$name' -Destination '$Path' -Force" }
    Join-Path $target $name
}

function Write-JarvisUndo {
    param([string]$Path, [string]$Line)
    $parent = Split-Path $Path -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Add-Content -LiteralPath $Path -Value $Line -Encoding UTF8
}

Export-ModuleMember -Function *-Jarvis*
