[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist'))

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$jar = Join-Path $root 'payload\ZombieBuddy\libs\ZombieBuddy.jar'
$installer = Join-Path $root 'Install-ZombieBuddy.ps1'
$agent = Join-Path $root 'setup\Setup-ZombieBuddyAgent.ps1'
$jarHash = (Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash
if ((Get-Content -Raw -LiteralPath $installer) -notmatch $jarHash -or
    (Get-Content -Raw -LiteralPath $agent) -notmatch $jarHash) {
    throw "Update the pinned package JAR hash in both installers before building: $jarHash"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$out = (Resolve-Path $OutputDirectory).Path
$zip = Join-Path $out 'ZombieBuddy-Friends.zip'
$hashes = Join-Path $out 'SHA256SUMS.txt'
$paths = @(
    'Install-ZombieBuddy.cmd', 'Install-ZombieBuddy.ps1',
    'Update-ZombieBuddy.cmd', 'Update-ZombieBuddy.ps1',
    'README.md', 'payload', 'setup'
) | ForEach-Object { Join-Path $root $_ }
Compress-Archive -LiteralPath $paths -DestinationPath $zip -Force
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $hashes -Encoding Ascii -Value "$hash  ZombieBuddy-Friends.zip"
Write-Output $zip
Write-Output $hashes
