Set-StrictMode -Version Latest

function Get-JarvisCrew {
    @(
        [pscustomobject]@{ key='default'; name='JARVIS'; code='J-00'; initials='JV'; role='Chief of staff'; tagline='Routes, verifies, reports' },
        [pscustomobject]@{ key='dev'; name='DEV'; code='J-01'; initials='DV'; role='Build engineer'; tagline='Makes the machine useful' },
        [pscustomobject]@{ key='research'; name='RESEARCH'; code='J-02'; initials='RS'; role='Research lead'; tagline='Evidence before confidence' },
        [pscustomobject]@{ key='assistant'; name='ASSISTANT'; code='J-03'; initials='AS'; role='Executive assistant'; tagline='Quietly keeps the day moving' }
    )
}

function Assert-JarvisUploadName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -match '[\\/]' -or $Name -match '\.\.') { throw 'Invalid upload filename' }
    if ([IO.Path]::GetExtension($Name).ToLowerInvariant() -notin @('.html','.png','.jpg','.jpeg','.webp','.svg')) { throw 'Unsupported upload extension' }
    $true
}

function Install-JarvisDashboardFiles {
    param([string]$ProjectRoot, [string]$DashboardRoot)
    New-Item -ItemType Directory -Force -Path $ProjectRoot | Out-Null
    foreach ($key in @('default','dev','research','assistant')) { New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot "content\$key") | Out-Null }
    Copy-Item (Join-Path $DashboardRoot 'jarvis-dashboard-template.html') (Join-Path $ProjectRoot 'jarvis-dashboard-template.html') -Force
    Copy-Item (Join-Path $DashboardRoot 'index.html') (Join-Path $ProjectRoot 'index.html') -Force
    Copy-Item (Join-Path $DashboardRoot 'styles.css') (Join-Path $ProjectRoot 'styles.css') -Force
    Copy-Item (Join-Path $DashboardRoot 'script.js') (Join-Path $ProjectRoot 'script.js') -Force
    Copy-Item (Join-Path $DashboardRoot 'favicon.svg') (Join-Path $ProjectRoot 'favicon.svg') -Force
    Copy-Item (Join-Path $DashboardRoot 'upload.html') (Join-Path $ProjectRoot 'upload.html') -Force
    Copy-Item (Join-Path $DashboardRoot 'server.py') (Join-Path $ProjectRoot 'server.py') -Force
    if (-not (Test-Path (Join-Path $ProjectRoot 'docs.md'))) { Set-Content (Join-Path $ProjectRoot 'docs.md') "# JARVIS Mission Control`n`nOperate from Home. Comms is explicit-send only. Services bind to loopback." -Encoding UTF8 }
}

function Register-JarvisDashboardTask {
    param([string]$ProjectRoot)
    $action = "py -3.12 `"$ProjectRoot\server.py`""
    & schtasks.exe /Create /TN 'JARVIS Mission Control' /SC ONLOGON /TR $action /F | Out-Null
}

Export-ModuleMember -Function *-Jarvis*
