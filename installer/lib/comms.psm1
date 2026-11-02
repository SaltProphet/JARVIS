Set-StrictMode -Version Latest
function Install-JarvisComms { param([string]$ProjectRoot)
    foreach ($key in @('default','dev','research','assistant')) { New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot "content\$key") | Out-Null }
}
Export-ModuleMember -Function *-Jarvis*
