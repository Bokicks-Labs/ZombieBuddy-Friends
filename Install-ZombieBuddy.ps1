[CmdletBinding()]
param(
    [string]$ProjectZomboidPath,
    [string]$ZomboidHome = (Join-Path $env:USERPROFILE 'Zomboid'),
    [switch]$SkipAgentSetup,
    [switch]$UseBundledJar
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$source = Join-Path $PSScriptRoot 'payload\ZombieBuddy'
$jar = Join-Path $source 'libs\ZombieBuddy.jar'
$expectedJarHash = 'EB79B9876332010733A8E0D7CE4FE0377846059A9E28859029E2A0FB449F6CF2'
if (-not (Test-Path -LiteralPath (Join-Path $source '42\mod.info') -PathType Leaf) -or
    -not (Test-Path -LiteralPath $jar -PathType Leaf)) {
    throw 'The release is incomplete: payload\ZombieBuddy is missing its Build 42 metadata or JAR.'
}
if ((Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash -ne $expectedJarHash) {
    throw 'The packaged ZombieBuddy JAR does not match the tested 2.3.4 snapshot.'
}

$officialJar = $jar
$officialHash = $expectedJarHash
$officialVersion = [version]'2.3.4'
$officialSourceRoot = $null
$downloadRoot = $null
try {
if (-not $UseBundledJar) {
    $releases = Invoke-RestMethod -Uri 'https://api.github.com/repos/zed-0xff/ZombieBuddy/releases?per_page=100' -Headers @{
        'User-Agent' = 'ZombieBuddy-Friends-Installer'
        'Accept' = 'application/vnd.github+json'
    }
    $candidates = foreach ($release in $releases) {
        if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^v?(2\.\d+\.\d+)$') { continue }
        $version = [version]$Matches[1]
        $assets = @($release.assets | Where-Object { $_.name -eq 'ZombieBuddy.jar' -and $_.digest -match '^sha256:[A-Fa-f0-9]{64}$' })
        if ($assets.Count -eq 1) { [pscustomobject]@{ Version = $version; Asset = $assets[0]; SourceUrl = $release.zipball_url } }
    }
    $latest = $candidates | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $latest) { throw 'No official ZombieBuddy 2.x.x release with a SHA-256-identified JAR was found.' }
    if ($latest.Version -lt $officialVersion) { throw 'The latest official 2.x.x release is older than the bundled 2.3.4 JAR.' }
    $officialHash = $latest.Asset.digest.Substring(7).ToUpperInvariant()
    $officialVersion = $latest.Version
    $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) ('ZombieBuddy-official-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $downloadRoot | Out-Null
    $officialJar = Join-Path $downloadRoot 'ZombieBuddy.jar'
    Invoke-WebRequest -Uri $latest.Asset.browser_download_url -OutFile $officialJar
    if ((Get-FileHash -LiteralPath $officialJar -Algorithm SHA256).Hash -ne $officialHash) {
        throw 'Official ZombieBuddy JAR failed its GitHub release SHA-256 digest.'
    }
    $sourceZip = Join-Path $downloadRoot 'official-source.zip'
    $sourceExtract = Join-Path $downloadRoot 'official-source'
    Invoke-WebRequest -Uri $latest.SourceUrl -OutFile $sourceZip
    Expand-Archive -LiteralPath $sourceZip -DestinationPath $sourceExtract
    $roots = @(Get-ChildItem -LiteralPath $sourceExtract -Directory)
    if ($roots.Count -ne 1) { throw 'Official source archive has an unexpected layout.' }
    $officialSourceRoot = $roots[0].FullName
    $officialModInfo = Join-Path $officialSourceRoot '42\mod.info'
    if (-not (Test-Path -LiteralPath $officialModInfo -PathType Leaf) -or
        (Get-Content -Raw -LiteralPath $officialModInfo) -notmatch '(?m)^id=ZombieBuddy\s*$' -or
        -not (Test-Path -LiteralPath (Join-Path $officialSourceRoot 'common\media') -PathType Container)) {
        throw 'Official 2.x.x source does not contain the expected ZombieBuddy mod layout.'
    }
    Write-Output "Selected official ZombieBuddy $officialVersion ($officialHash)."
}

$mods = Join-Path $ZomboidHome 'mods'
$target = Join-Path $mods 'ZombieBuddy'
$backupRoot = Join-Path $ZomboidHome 'backups\ZombieBuddy-Friends'
if (Test-Path -LiteralPath $target) {
    $item = Get-Item -LiteralPath $target -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to replace a file or linked directory: $target"
    }
}

$running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(ProjectZomboid|ProjectZomboid64|StartServer64)' }
if ($running) { throw 'Close Project Zomboid and local server processes before installing.' }

if (-not $SkipAgentSetup) {
    $agent = Join-Path $PSScriptRoot 'setup\Setup-ZombieBuddyAgent.ps1'
    $agentArgs = @{ Action = 'Install'; OfficialJarPath = $officialJar; OfficialJarSha256 = $officialHash }
    if ($ProjectZomboidPath) { $agentArgs.ProjectZomboidPath = $ProjectZomboidPath }
    & $agent @agentArgs
}

New-Item -ItemType Directory -Path $mods -Force | Out-Null
$stage = Join-Path $mods ('ZombieBuddy.stage-' + [guid]::NewGuid().ToString('N'))
$backup = $null
try {
    Copy-Item -LiteralPath $source -Destination $stage -Recurse
    if ($officialSourceRoot) {
        foreach ($directory in @('42', 'common')) {
            $destination = Join-Path $stage $directory
            if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
            Copy-Item -LiteralPath (Join-Path $officialSourceRoot $directory) -Destination $destination -Recurse
        }
    }
    $stagedJar = Join-Path $stage 'libs\ZombieBuddy.jar'
    Copy-Item -LiteralPath $officialJar -Destination $stagedJar -Force
    if ((Get-FileHash -LiteralPath $stagedJar -Algorithm SHA256).Hash -ne $officialHash) {
        throw 'Staged ZombieBuddy JAR failed verification.'
    }
    if (Test-Path -LiteralPath $target) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        $backup = Join-Path $backupRoot ('ZombieBuddy-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
        Move-Item -LiteralPath $target -Destination $backup
    }
    try {
        Move-Item -LiteralPath $stage -Destination $target
    } catch {
        if ($backup -and -not (Test-Path -LiteralPath $target)) {
            Move-Item -LiteralPath $backup -Destination $target
        }
        throw
    }
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}

Write-Output "Installed ZombieBuddy mod: $target"
if ($backup) { Write-Output "Previous mod backup: $backup" }
Write-Output 'For a dedicated server, remove Workshop item 3619862853 from WorkshopItems and keep ZombieBuddy in Mods only if that server loads it.'
} finally {
    if ($downloadRoot -and (Test-Path -LiteralPath $downloadRoot)) {
        Remove-Item -LiteralPath $downloadRoot -Recurse -Force
    }
}
