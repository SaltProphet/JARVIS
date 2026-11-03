Set-StrictMode -Version Latest
function Install-JarvisResearch { param([string]$ProjectRoot, [string]$ProfileRoot, [switch]$WithSerpApi)
    $skill = Join-Path $ProfileRoot 'skills\jarvis-search'; New-Item -ItemType Directory -Force -Path $skill | Out-Null
    Write-JarvisUtf8Text -Path (Join-Path $skill 'SKILL.md') -Text (@("Search only with the key from %LOCALAPPDATA%\\jarvis-secrets\\serpapi.key.", 'Cite a URL for every searched fact.', 'Log every search through the activity logger.') -join "`n")
}
Export-ModuleMember -Function *-Jarvis*
