Set-StrictMode -Version Latest

function Install-JarvisPrivateServices {
    param([string]$ProjectRoot, [string]$Root)
    New-Item -ItemType Directory -Force -Path $ProjectRoot,(Join-Path $Root 'hooks') | Out-Null
    [ordered]@{ allowlist = @('GMAIL_FETCH_EMAILS','GOOGLECALENDAR_EVENTS_LIST'); allowed_agents = @('JARVIS','ASSISTANT'); denied_agents = @('DEV','RESEARCH'); status = 'owner-approval-pending' } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $ProjectRoot 'private-services.json') -Encoding UTF8
}

Export-ModuleMember -Function *-Jarvis*
