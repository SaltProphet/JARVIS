Set-StrictMode -Version Latest

function Read-JarvisOwnerForm {
    param([switch]$SkipPrompt)
    if ($SkipPrompt) { return [pscustomobject]@{ name='Owner'; work='not provided yet'; timezone='UTC'; hours='not provided yet'; weather_city='not provided yet'; priority='not provided yet'; telegram_chat_id='-1000000000000'; interview=@('not provided yet') * 6 } }
    $answers = [ordered]@{}
    $answers.name = Read-Host 'Owner first name'
    $answers.work = Read-Host 'What do you do? One sentence'
    $answers.timezone = Read-Host 'IANA time zone (for example America/New_York)'
    $answers.hours = Read-Host 'Working hours'
    $answers.weather_city = Read-Host 'Weather city for the morning briefing'
    $answers.priority = Read-Host 'Crew purpose / top priority'
    $answers.telegram_chat_id = Read-Host 'Telegram group chat ID (leave blank to detect from getUpdates)'
    $answers.interview = @(
        (Read-Host '1/6 Build and deploy preferences'), (Read-Host '2/6 What should RESEARCH watch?'),
        (Read-Host '3/6 Apps and calendars that run the week'), (Read-Host '4/6 Who is owed replies?'),
        (Read-Host '5/6 What must never interrupt?'), (Read-Host '6/6 Anything else the crew should know?')
    )
    [pscustomobject]$answers
}

function Complete-JarvisOwnerForm {
    param([psobject]$Form, [string]$EnvFile, [switch]$DryRun)
    $result = [ordered]@{}
    foreach ($field in @('name','work','timezone','hours','weather_city','priority','telegram_chat_id')) {
        $result[$field] = if ($Form -and $Form.PSObject.Properties.Name -contains $field) { [string]$Form.$field } else { '' }
    }
    $result.interview = if ($Form) { @($Form.interview) } else { @() }
    if ($DryRun) {
        foreach ($field in @('name','work','timezone','hours','weather_city','priority','telegram_chat_id')) { if ([string]::IsNullOrWhiteSpace($result[$field])) { $result[$field] = if ($field -eq 'telegram_chat_id') { '-1000000000000' } else { 'not provided yet' } } }
        if (@($result.interview).Count -ne 6) { $result.interview = @('not provided yet') * 6 }
        return [pscustomobject]$result
    }
    foreach ($field in @('name','work','timezone','hours','weather_city','priority')) {
        if ([string]::IsNullOrWhiteSpace($result[$field])) { $result[$field] = Read-Host ("Owner form: $field") }
    }
    if (@($result.interview).Count -ne 6) {
        $result.interview = @(
            (Read-Host '1/6 Build and deploy preferences'), (Read-Host '2/6 What should RESEARCH watch?'),
            (Read-Host '3/6 Apps and calendars that run the week'), (Read-Host '4/6 Who is owed replies?'),
            (Read-Host '5/6 What must never interrupt?'), (Read-Host '6/6 Anything else the crew should know?')
        )
    } else {
        for ($i = 0; $i -lt 6; $i++) { if ([string]::IsNullOrWhiteSpace([string]$result.interview[$i])) { $result.interview[$i] = Read-Host ("$($i + 1)/6 missing interview answer") } }
    }
    if ([string]::IsNullOrWhiteSpace($result.telegram_chat_id)) {
        $token = Get-JarvisEnvValue -EnvFile $EnvFile -Name 'TELEGRAM_BOT_TOKEN'
        if ($token) {
            Write-Host 'Send any message in the Telegram group, then press Enter to detect it.'
            Read-Host 'Press Enter after sending the group message' | Out-Null
            $candidate = Get-JarvisTelegramGroupFromUpdates -Token $token
            if ($candidate) {
                Write-Host "Detected Telegram group: $($candidate.title) [$($candidate.id)]"
                if ((Read-Host 'Use this group? (Y/N)') -match '^[Yy]') { $result.telegram_chat_id = $candidate.id }
            }
        }
        if ([string]::IsNullOrWhiteSpace($result.telegram_chat_id)) { $result.telegram_chat_id = Read-Host 'Telegram group chat ID' }
    }
    [pscustomobject]$result
}

function Test-JarvisOwnerForm {
    param([psobject]$Form)
    if ($null -eq $Form) { return $false }
    foreach ($field in @('name','work','timezone','hours','weather_city','priority','telegram_chat_id')) {
        if ([string]::IsNullOrWhiteSpace([string]$Form.$field)) { return $false }
    }
    $answers = @($Form.interview)
    if ($answers.Count -ne 6) { return $false }
    foreach ($answer in $answers) {
        if ([string]::IsNullOrWhiteSpace([string]$answer)) { return $false }
    }
    $true
}

function Get-JarvisMissingOwnerFields {
    param([psobject]$Form)
    $missing = @()
    foreach ($field in @('name','work','timezone','hours','weather_city','priority','telegram_chat_id')) {
        if ($null -eq $Form -or $Form.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$Form.$field)) { $missing += $field }
    }
    $answers = @($Form.interview)
    if ($answers.Count -ne 6 -or @($answers | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) { $missing += 'interview' }
    $missing
}

function Write-JarvisMemoryEntry {
    param([string]$MemoryFile, [string]$Entry)
    New-Item -ItemType Directory -Force -Path (Split-Path $MemoryFile -Parent) | Out-Null
    $raw = if (Test-Path $MemoryFile) { Get-Content $MemoryFile -Raw } else { $null }
    $existing = if ($null -eq $raw) { '' } else { $raw.Trim() }
    if ($existing -notlike "*$Entry*") { Set-Content -LiteralPath $MemoryFile -Value (($existing, $Entry -join "`n§`n").Trim()) -Encoding UTF8 }
}

function Invoke-JarvisAgentTurn {
    param([string]$PromptFile, [string]$Profile = 'default', [string]$Hermes = 'hermes', [string]$WorkDirectory)
    $prompt = Get-Content -LiteralPath $PromptFile -Raw
    $args = @(); if ($Profile -ne 'default') { $args += @('-p', $Profile) }; $args += @('-z', $prompt)
    $result = & $Hermes @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Hermes turn failed for ${Profile}: $($result -join ' ')" }
    $result -join [Environment]::NewLine
}

Export-ModuleMember -Function *-Jarvis*
