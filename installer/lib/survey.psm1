Set-StrictMode -Version Latest

function Get-JarvisSqliteSurveySource {
    param([string]$Name, [string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{ name=$Name; kind='sqlite'; path=$Path; available=$false; tables=@(); keys=@(); timestamp_types=@(); sample=$null; error='missing' }
    }
    $code = @'
import datetime
import json
import pathlib
import re
import sqlite3
import sys

path = pathlib.Path(sys.argv[1]).resolve()
con = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=5)
time_name = re.compile(r'(time|date|created|updated|started|ended|timestamp|run_at)', re.I)
timestamp_types = set()

def timestamp_type(value):
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return 'epoch-milliseconds' if abs(value) >= 100000000000 else 'epoch-integer'
    if isinstance(value, float):
        return 'epoch-float'
    if isinstance(value, str):
        try:
            datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
            return 'iso-8601'
        except ValueError:
            return None
    return None

tables = [row[0] for row in con.execute('SELECT name FROM sqlite_master WHERE type = \'table\' AND name NOT LIKE \'sqlite_%\' ORDER BY name')]
schemas = []
quote = chr(34)
for table in tables:
    escaped = table.replace(quote, quote + quote)
    cursor = con.execute('SELECT * FROM ' + quote + escaped + quote + ' LIMIT 1')
    row = cursor.fetchone()
    declared = {item[1]: item[2] for item in con.execute('PRAGMA table_info(' + quote + escaped + quote + ')')}
    columns = []
    for index, column in enumerate(cursor.description or []):
        key = column[0]
        value = row[index] if row is not None else None
        kind = timestamp_type(value) if time_name.search(key) else None
        if kind:
            timestamp_types.add(kind)
        if value is None:
            value_type = 'null'
        elif isinstance(value, bool):
            value_type = 'boolean'
        elif isinstance(value, int):
            value_type = 'integer'
        elif isinstance(value, float):
            value_type = 'number'
        elif isinstance(value, bytes):
            value_type = 'binary'
        else:
            value_type = 'text'
        columns.append({'name': key, 'declared_type': declared.get(key, ''), 'value_type': value_type, 'timestamp_type': kind})
    schemas.append({'name': table, 'columns': columns})
con.close()
print(json.dumps({'tables': tables, 'timestamp_types': sorted(timestamp_types), 'sample': {'tables': schemas}}, sort_keys=True))
'@
    try {
        $raw = & py -3.12 -c $code $Path 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($raw -join ' ') }
        $facts = $raw -join '' | ConvertFrom-Json
        [pscustomobject][ordered]@{ name=$Name; kind='sqlite'; path=$Path; available=$true; tables=@($facts.tables); keys=@(); timestamp_types=@($facts.timestamp_types); sample=$facts.sample; error=$null }
    } catch {
        [pscustomobject][ordered]@{ name=$Name; kind='sqlite'; path=$Path; available=$false; tables=@(); keys=@(); timestamp_types=@(); sample=$null; error='unreadable or locked' }
    }
}

function Get-JarvisJsonTimestampTypes {
    param($Value, [string]$Name = '')
    $types = @()
    if ($null -eq $Value) { return $types }
    if ($Value -is [array]) {
        foreach ($item in $Value) { $types += @(Get-JarvisJsonTimestampTypes -Value $item -Name $Name) }
    } elseif ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) { $types += @(Get-JarvisJsonTimestampTypes -Value $property.Value -Name $property.Name) }
    } elseif ($Name -match '(?i)time|date|created|updated|started|ended|timestamp|run_at') {
        if ($Value -is [int] -or $Value -is [long]) { $types += $(if ([math]::Abs([double]$Value) -ge 100000000000) { 'epoch-milliseconds' } else { 'epoch-integer' }) }
        elseif ($Value -is [double] -or $Value -is [decimal]) { $types += 'epoch-float' }
        elseif ($Value -is [string]) { $parsed = [datetimeoffset]::MinValue; if ([datetimeoffset]::TryParse($Value, [ref]$parsed)) { $types += 'iso-8601' } }
    }
    @($types | Sort-Object -Unique)
}

function ConvertTo-JarvisValueShape {
    param($Value, [string]$Name = '')
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [array]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return @() }
        return @(ConvertTo-JarvisValueShape -Value $items[0])
    }
    if ($Value -is [pscustomobject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $result[$property.Name] = ConvertTo-JarvisValueShape -Value $property.Value -Name $property.Name }
        return [pscustomobject]$result
    }
    if ($Value -is [bool]) { return 'boolean' }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int] -or $Value -is [long] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) { return 'number' }
    if ($Value -is [string]) { return 'text' }
    'unknown'
}

function Get-JarvisJsonSurveySource {
    param([string]$Name, [string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{ name=$Name; kind='json'; path=$Path; available=$false; tables=@(); keys=@(); timestamp_types=@(); sample=$null; error='missing' }
    }
    try {
        $value = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        $keys = if ($value -is [pscustomobject]) { @($value.PSObject.Properties.Name | Sort-Object) } else { @() }
        [pscustomobject][ordered]@{ name=$Name; kind='json'; path=$Path; available=$true; tables=@(); keys=$keys; timestamp_types=@(Get-JarvisJsonTimestampTypes $value); sample=(ConvertTo-JarvisValueShape $value); error=$null }
    } catch {
        [pscustomobject][ordered]@{ name=$Name; kind='json'; path=$Path; available=$false; tables=@(); keys=@(); timestamp_types=@(); sample=$null; error='malformed or unreadable' }
    }
}

function Get-JarvisDirectorySurveySource {
    param([string]$Name, [string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [pscustomobject][ordered]@{ name=$Name; kind='directory'; path=$Path; available=$false; tables=@(); keys=@('item_count','extensions','last_write_time'); timestamp_types=@(); sample=$null; item_count=0; error='missing' }
    }
    try {
        $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction Stop)
        $extensions = @($files | ForEach-Object { if ($_.Extension) { $_.Extension.ToLowerInvariant() } else { '[none]' } } | Sort-Object -Unique)
        [pscustomobject][ordered]@{
            name=$Name; kind='directory'; path=$Path; available=$true; tables=@(); keys=@('item_count','extensions','last_write_time')
            timestamp_types=$(if ($files.Count -gt 0) { @('filesystem-datetime') } else { @() })
            sample=[pscustomobject][ordered]@{ item='file'; fields=@('extension','last_write_time','length'); value_types=@('text','filesystem-datetime','number') }
            item_count=$files.Count; extensions=$extensions; error=$null
        }
    } catch {
        [pscustomobject][ordered]@{ name=$Name; kind='directory'; path=$Path; available=$false; tables=@(); keys=@('item_count','extensions','last_write_time'); timestamp_types=@(); sample=$null; item_count=0; error='unreadable' }
    }
}

function Get-JarvisDataSurveyEvidenceHash {
    param([psobject]$Evidence)
    $payload = [pscustomobject][ordered]@{
        format_version=$Evidence.format_version; step=$Evidence.step; status=$Evidence.status; profile=$Evidence.profile
        source_count=$Evidence.source_count; sources=@($Evidence.sources)
        capabilities=@($Evidence.capabilities); limitations=@($Evidence.limitations)
    }
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($payload | ConvertTo-Json -Depth 20 -Compress))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { -join @($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) } finally { $sha.Dispose() }
}

function Test-JarvisDataSurveyEvidence {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try { $evidence = [IO.File]::ReadAllText($Path) | ConvertFrom-Json } catch { return $false }
    $evidenceProperties = @($evidence.PSObject.Properties.Name)
    foreach ($property in @('format_version','step','status','profile','source_count','sources','capabilities','limitations','evidence_hash')) {
        if ($evidenceProperties -notcontains $property) { return $false }
    }
    if ($evidence.step -ne 14 -or $evidence.status -ne 'completed' -or $evidence.profile -ne 'dev') { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$evidence.evidence_hash) -or $evidence.evidence_hash -ne (Get-JarvisDataSurveyEvidenceHash -Evidence $evidence)) { return $false }
    $sources = @($evidence.sources)
    if ($sources.Count -eq 0 -or [int]$evidence.source_count -ne $sources.Count) { return $false }
    if (@($evidence.capabilities).Count -eq 0 -or @($evidence.limitations).Count -eq 0) { return $false }
    $required = @(
        'hermes-default-state','hermes-profile-dev-state','hermes-profile-research-state','hermes-profile-assistant-state',
        'hermes-kanban','hermes-cron-default','hermes-cron-dev','hermes-cron-research','hermes-cron-assistant',
        'hermes-gateway-state','hermes-gateway-logs','jarvis-activity-log'
    )
    $names = @($sources | ForEach-Object name)
    if (@($names | Sort-Object -Unique).Count -ne $names.Count) { return $false }
    foreach ($name in $required) { if ($names -notcontains $name) { return $false } }
    foreach ($source in $sources) {
        $properties = @($source.PSObject.Properties.Name)
        foreach ($property in @('name','kind','path','available','tables','keys','timestamp_types','sample','error')) {
            if ($properties -notcontains $property) { return $false }
        }
        if ($source.kind -notin @('sqlite','json','directory')) { return $false }
        if ($source.kind -eq 'directory' -and $properties -notcontains 'item_count') { return $false }
    }
    $true
}

function Get-JarvisDataSurvey {
    param([Parameter(Mandatory=$true)][psobject]$Paths)
    $sources = @()
    $sources += Get-JarvisSqliteSurveySource -Name 'hermes-default-state' -Path (Join-Path $Paths.HermesHome 'state.db')

    $profiles = @('dev','research','assistant')
    $profileRoot = Join-Path $Paths.HermesHome 'profiles'
    if (Test-Path -LiteralPath $profileRoot -PathType Container) {
        $profiles += @(Get-ChildItem -LiteralPath $profileRoot -Directory | ForEach-Object Name)
    }
    foreach ($profile in @($profiles | Sort-Object -Unique)) {
        $sources += Get-JarvisSqliteSurveySource -Name "hermes-profile-$profile-state" -Path (Join-Path $Paths.HermesHome "profiles\$profile\state.db")
    }

    $sources += Get-JarvisSqliteSurveySource -Name 'hermes-kanban' -Path (Join-Path $Paths.HermesHome 'kanban.db')
    $boardRoot = Join-Path $Paths.HermesHome 'kanban\boards'
    if (Test-Path -LiteralPath $boardRoot -PathType Container) {
        foreach ($board in @(Get-ChildItem -LiteralPath $boardRoot -Directory | Sort-Object Name)) {
            $sources += Get-JarvisSqliteSurveySource -Name "hermes-kanban-$($board.Name)" -Path (Join-Path $board.FullName 'kanban.db')
        }
    }
    $sources += Get-JarvisJsonSurveySource -Name 'hermes-cron-default' -Path (Join-Path $Paths.HermesHome 'cron\jobs.json')
    foreach ($profile in @($profiles | Sort-Object -Unique)) {
        $sources += Get-JarvisJsonSurveySource -Name "hermes-cron-$profile" -Path (Join-Path $Paths.HermesHome "profiles\$profile\cron\jobs.json")
    }
    $sources += Get-JarvisJsonSurveySource -Name 'hermes-gateway-state' -Path (Join-Path $Paths.HermesHome 'gateway_state.json')
    $sources += Get-JarvisDirectorySurveySource -Name 'hermes-gateway-logs' -Path (Join-Path $Paths.HermesHome 'logs')
    $sources += Get-JarvisSqliteSurveySource -Name 'jarvis-activity-log' -Path (Join-Path $Paths.ProjectRoot 'agent-logs.db')

    [pscustomobject][ordered]@{
        sources = @($sources)
        capabilities = @(
            'Report available Hermes session, message, usage, kanban, cron, gateway, and activity source metadata.'
            'Report discovered tables, JSON keys, timestamp representations, and sanitized sample rows.'
        )
        limitations = @(
            'Dollar cost is unavailable unless an inspected source exposes a populated cost field.'
            'Gateway JSON reports persisted state only; process liveness requires a separate PID check.'
            'Missing, malformed, or locked sources remain unavailable and are never inferred.'
        )
    }
}

Export-ModuleMember -Function *-Jarvis*
