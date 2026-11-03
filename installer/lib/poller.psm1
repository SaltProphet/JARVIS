Set-StrictMode -Version Latest
function Install-JarvisPoller {
    param([string]$ProjectRoot, [string]$Root)
    New-Item -ItemType Directory -Force -Path $ProjectRoot | Out-Null
    [ordered]@{ cache = 'private-services-cache.json'; max_age_minutes = 25; min_start_seconds = 60; max_calls_per_run = 2 } | ConvertTo-Json | Set-Content (Join-Path $ProjectRoot 'poller.json') -Encoding UTF8
}
Export-ModuleMember -Function *-Jarvis*
