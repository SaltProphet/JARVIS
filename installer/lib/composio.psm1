Set-StrictMode -Version Latest

function Install-JarvisComposio {
    param([string]$ProjectRoot)
    New-Item -ItemType Directory -Force -Path $ProjectRoot | Out-Null
    [ordered]@{ status = 'pending-owner'; provider = 'composio'; allowlist = @('GMAIL_FETCH_EMAILS','GOOGLECALENDAR_EVENTS_LIST'); browser_links = @('login','gmail','googlecalendar') } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $ProjectRoot 'composio-state.json') -Encoding UTF8
}

Export-ModuleMember -Function *-Jarvis*
