Set-StrictMode -Version Latest
function Install-JarvisAccess { param([string]$ProjectRoot, [switch]$WithTailscale)
    [ordered]@{ dashboard = '127.0.0.1:8899'; voice = '127.0.0.1:8767'; tailscale = [bool]$WithTailscale; funnel = $false } | ConvertTo-Json | Set-Content (Join-Path $ProjectRoot 'access.json') -Encoding UTF8
}
Export-ModuleMember -Function *-Jarvis*
