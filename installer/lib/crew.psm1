Set-StrictMode -Version Latest

function Install-JarvisCrew {
    param([string]$HermesHome, [string]$TemplateRoot, [string]$OwnerName, [switch]$DryRun)
    $profiles = @('dev','research','assistant')
    foreach ($profile in $profiles) {
        $dir = Join-Path $HermesHome "profiles\$profile"
        if ($DryRun) { Write-Output "CREATE PROFILE $profile with hermes profile create $profile --clone"; continue }
        if (-not (Test-Path $dir)) { & hermes profile create $profile --clone | Out-Null }
        $soul = Join-Path $TemplateRoot "SOUL-$($profile.ToUpperInvariant()).md"
        Copy-Item $soul (Join-Path $dir 'SOUL.md') -Force
    }
}

Export-ModuleMember -Function *-Jarvis*
