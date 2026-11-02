Set-StrictMode -Version Latest
function Write-JarvisBriefingConfig { param([string]$Path, [string]$City)
    [ordered]@{ weather_city = $City; source = 'owner-form'; weather_endpoint = 'https://api.open-meteo.com/v1/forecast'; max_sentences = 3 } | ConvertTo-Json | Set-Content $Path -Encoding UTF8
}
Export-ModuleMember -Function *-Jarvis*
