Set-StrictMode -Version Latest
function Test-JarvisInstall { param([string]$ProjectRoot, [string]$HermesHome)
    $required = @('server.py','index.html','styles.css','script.js','favicon.svg','docs.md')
    $missing = @($required | Where-Object { -not (Test-Path (Join-Path $ProjectRoot $_)) })
    [pscustomobject]@{ ok = $missing.Count -eq 0; missing = $missing; loopback = $true; hermes_home = $HermesHome }
}
Export-ModuleMember -Function *-Jarvis*
