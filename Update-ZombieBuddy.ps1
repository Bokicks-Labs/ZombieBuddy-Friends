[CmdletBinding()]
param([string]$ProjectZomboidPath)

$ErrorActionPreference = 'Stop'
$repo = 'Bokicks-Labs/ZombieBuddy-Friends'
$api = "https://api.github.com/repos/$repo/releases/latest"
$release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'ZombieBuddy-Friends-Updater'; 'Accept' = 'application/vnd.github+json' }
$archiveAsset = @($release.assets | Where-Object name -eq 'ZombieBuddy-Friends.zip')
$hashAsset = @($release.assets | Where-Object name -eq 'SHA256SUMS.txt')
if ($archiveAsset.Count -ne 1 -or $hashAsset.Count -ne 1) { throw 'Latest release is missing its ZIP or checksum asset.' }

$temp = Join-Path ([IO.Path]::GetTempPath()) ('ZombieBuddy-Friends-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $zip = Join-Path $temp 'ZombieBuddy-Friends.zip'
    $hashFile = Join-Path $temp 'SHA256SUMS.txt'
    Invoke-WebRequest -Uri $archiveAsset[0].browser_download_url -OutFile $zip
    Invoke-WebRequest -Uri $hashAsset[0].browser_download_url -OutFile $hashFile
    $line = @(Get-Content -LiteralPath $hashFile | Where-Object { $_ -match '^[A-Fa-f0-9]{64}  ZombieBuddy-Friends\.zip$' })
    if ($line.Count -ne 1) { throw 'Release checksum file is invalid.' }
    $expected = ($line[0] -split ' ')[0]
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $expected) { throw 'Downloaded release ZIP failed SHA-256 verification.' }
    $unpacked = Join-Path $temp 'unpacked'
    Expand-Archive -LiteralPath $zip -DestinationPath $unpacked
    $installer = Join-Path $unpacked 'Install-ZombieBuddy.ps1'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw 'Release ZIP has no installer.' }
    $installArgs = @{}
    if ($ProjectZomboidPath) { $installArgs.ProjectZomboidPath = $ProjectZomboidPath }
    & $installer @installArgs
    if (-not $?) { throw 'ZombieBuddy installation failed.' }
    Write-Output "Installed release $($release.tag_name)."
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
