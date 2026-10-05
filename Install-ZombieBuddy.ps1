[CmdletBinding()]
param(
    [string]$ProjectZomboidPath,
    [string]$ZomboidHome = (Join-Path $env:USERPROFILE 'Zomboid'),
    [switch]$SkipAgentSetup
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
    $agentArgs = @{ Action = 'Install'; LaunchOfficialInstaller = $true }
    if ($ProjectZomboidPath) { $agentArgs.ProjectZomboidPath = $ProjectZomboidPath }
    & $agent @agentArgs
}

New-Item -ItemType Directory -Path $mods -Force | Out-Null
$stage = Join-Path $mods ('ZombieBuddy.stage-' + [guid]::NewGuid().ToString('N'))
$backup = $null
try {
    Copy-Item -LiteralPath $source -Destination $stage -Recurse
    $stagedJar = Join-Path $stage 'libs\ZombieBuddy.jar'
    if ((Get-FileHash -LiteralPath $stagedJar -Algorithm SHA256).Hash -ne $expectedJarHash) {
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
