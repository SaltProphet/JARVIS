Set-StrictMode -Version Latest
function Write-JarvisBriefingConfig { param([string]$Path, [string]$City)
    [ordered]@{ weather_city = $City; source = 'owner-form'; weather_endpoint = 'https://api.open-meteo.com/v1/forecast'; max_sentences = 3; triggers = @('run my morning briefing','morning briefing','brief me','what did I miss') } | ConvertTo-Json | Set-Content $Path -Encoding UTF8
}

function Format-JarvisBriefing {
    param([string]$Weather = 'Weather unavailable.', [string]$Mail = 'No unread mail reported.', [string]$Calendar = 'No calendar events reported.')
    (($Mail.TrimEnd('.') + '.') + ' ' + ($Weather.TrimEnd('.') + '.') + ' ' + ($Calendar.TrimEnd('.') + '.'))
}
Export-ModuleMember -Function *-Jarvis*
