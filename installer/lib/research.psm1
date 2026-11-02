Set-StrictMode -Version Latest
function Install-JarvisResearch { param([string]$ProjectRoot, [string]$ProfileRoot, [switch]$WithSerpApi)
    $skill = Join-Path $ProfileRoot 'skills\jarvis-search'; New-Item -ItemType Directory -Force -Path $skill | Out-Null
    @("Search only with the key from %LOCALAPPDATA%\\jarvis-secrets\\serpapi.key.", 'Cite a URL for every searched fact.', 'Log every search through the activity logger.') | Set-Content (Join-Path $skill 'SKILL.md') -Encoding UTF8
}
Export-ModuleMember -Function *-Jarvis*
