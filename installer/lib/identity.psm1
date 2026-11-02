Set-StrictMode -Version Latest

function Read-JarvisOwnerForm {
    param([switch]$SkipPrompt)
    if ($SkipPrompt) { return [pscustomobject]@{ name='Owner'; work='not provided yet'; timezone='UTC'; hours='not provided yet'; weather_city='not provided yet'; priority='not provided yet'; interview=@('not provided yet') * 6 } }
    $answers = [ordered]@{}
    $answers.name = Read-Host 'Owner first name'
    $answers.work = Read-Host 'What do you do? One sentence'
    $answers.timezone = Read-Host 'IANA time zone (for example America/New_York)'
    $answers.hours = Read-Host 'Working hours'
    $answers.weather_city = Read-Host 'Weather city for the morning briefing'
    $answers.priority = Read-Host 'Crew purpose / top priority'
    $answers.interview = @(
        (Read-Host '1/6 Build and deploy preferences'), (Read-Host '2/6 What should RESEARCH watch?'),
        (Read-Host '3/6 Apps and calendars that run the week'), (Read-Host '4/6 Who is owed replies?'),
        (Read-Host '5/6 What must never interrupt?'), (Read-Host '6/6 Anything else the crew should know?')
    )
    [pscustomobject]$answers
}

function Test-JarvisOwnerForm {
    param([psobject]$Form)
    if ($null -eq $Form) { return $false }
    foreach ($field in @('name','work','timezone','hours','weather_city','priority')) {
        if ([string]::IsNullOrWhiteSpace([string]$Form.$field)) { return $false }
    }
    $answers = @($Form.interview)
    if ($answers.Count -ne 6) { return $false }
    foreach ($answer in $answers) {
        if ([string]::IsNullOrWhiteSpace([string]$answer)) { return $false }
    }
    $true
}

function Write-JarvisMemoryEntry {
    param([string]$MemoryFile, [string]$Entry)
    New-Item -ItemType Directory -Force -Path (Split-Path $MemoryFile -Parent) | Out-Null
    $existing = if (Test-Path $MemoryFile) { (Get-Content $MemoryFile -Raw).Trim() } else { '' }
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
