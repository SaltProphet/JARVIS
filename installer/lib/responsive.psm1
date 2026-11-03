Set-StrictMode -Version Latest
function Write-JarvisResponsiveAudit {
    param([string]$Path, [string]$DashboardRoot)
    $sizes = @(@{ width = 390; height = 844 }, @{ width = 768; height = 1024 }, @{ width = 1280; height = 800 }, @{ width = 1440; height = 900 }, @{ width = 1920; height = 1080 })
    $css = [IO.File]::ReadAllText((Join-Path $DashboardRoot 'styles.css'))
    $html = [IO.File]::ReadAllText((Join-Path $DashboardRoot 'index.html'))
    [ordered]@{ evidence = 'source-only'; sizes = $sizes; overflow = ($css -match 'overflow'); tab_reachability = ($html -match 'data-view'); primary_action_visible = ($html -match 'id="orb"'); visual_drift = 'not assessed without browser screenshots' } | ConvertTo-Json -Depth 5 | Set-Content $Path -Encoding UTF8
}
Export-ModuleMember -Function *-Jarvis*
