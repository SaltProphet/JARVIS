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
sensitive = re.compile(r'(secret|token|password|credential|api.?key|content|message|prompt|response|email|phone|address|chat.?id|thread.?id)', re.I)
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
sample = None
quote = chr(34)
for table in tables:
    escaped = table.replace(quote, quote + quote)
    cursor = con.execute('SELECT * FROM ' + quote + escaped + quote + ' LIMIT 1')
    row = cursor.fetchone()
    if row is None:
        continue
    values = {}
    for index, column in enumerate(cursor.description):
        key = column[0]
        value = row[index]
        kind = timestamp_type(value) if time_name.search(key) else None
        if kind:
            timestamp_types.add(kind)
        if sensitive.search(key):
            values[key] = '[redacted]'
        elif isinstance(value, bytes):
            values[key] = '<bytes:' + str(len(value)) + '>'
        elif isinstance(value, str) and not kind:
            values[key] = '[text]'
        else:
            values[key] = value
    if sample is None:
        sample = {'table': table, 'values': values}
con.close()
print(json.dumps({'tables': tables, 'timestamp_types': sorted(timestamp_types), 'sample': sample}, sort_keys=True))
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

function ConvertTo-JarvisSanitizedValue {
    param($Value, [string]$Name = '')
    if ($Name -match '(?i)secret|token|password|credential|api.?key|content|message|prompt|response|email|phone|address|chat.?id|thread.?id') { return '[redacted]' }
    if ($null -eq $Value) { return $null }
    if ($Value -is [array]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return @() }
        return @(ConvertTo-JarvisSanitizedValue -Value $items[0])
    }
    if ($Value -is [pscustomobject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $result[$property.Name] = ConvertTo-JarvisSanitizedValue -Value $property.Value -Name $property.Name }
        return [pscustomobject]$result
    }
    if ($Value -is [string]) {
        if ($Name -match '(?i)time|date|created|updated|started|ended|timestamp|run_at') {
            $parsed = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse($Value, [ref]$parsed)) { return $Value }
        }
        return '[text]'
    }
    $Value
}

function Get-JarvisJsonSurveySource {
    param([string]$Name, [string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{ name=$Name; kind='json'; path=$Path; available=$false; tables=@(); keys=@(); timestamp_types=@(); sample=$null; error='missing' }
    }
    try {
        $value = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        $keys = if ($value -is [pscustomobject]) { @($value.PSObject.Properties.Name | Sort-Object) } else { @() }
        [pscustomobject][ordered]@{ name=$Name; kind='json'; path=$Path; available=$true; tables=@(); keys=$keys; timestamp_types=@(Get-JarvisJsonTimestampTypes $value); sample=(ConvertTo-JarvisSanitizedValue $value); error=$null }
    } catch {
        [pscustomobject][ordered]@{ name=$Name; kind='json'; path=$Path; available=$false; tables=@(); keys=@(); timestamp_types=@(); sample=$null; error='malformed or unreadable' }
    }
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
