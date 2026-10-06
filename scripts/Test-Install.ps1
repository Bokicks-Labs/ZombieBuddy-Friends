$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fixture = Join-Path $root 'dist\install-fixture'
$game = Join-Path $fixture 'game\ProjectZomboid'
$zomboidFixtureHome = Join-Path $fixture 'profile\Zomboid'
$oldProfile = $env:USERPROFILE
if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
New-Item -ItemType Directory -Path $game,$zomboidFixtureHome -Force | Out-Null
Set-Content -LiteralPath (Join-Path $game 'ProjectZomboid64.exe') -Value 'fixture'
Set-Content -LiteralPath (Join-Path $game 'projectzomboid.jar') -Value 'fixture'
Set-Content -LiteralPath (Join-Path $game 'ProjectZomboid64.json') -Value '{"vmArgs":["-Xmx2048m"]}'
Set-Content -LiteralPath (Join-Path $game 'ProjectZomboid64.bat') -Value "@echo off`r`nSET _JAVA_OPTIONS=-Xmx2048m`r`n"
try {
    $env:USERPROFILE = Join-Path $fixture 'profile'
    & (Join-Path $root 'Install-ZombieBuddy.ps1') -ProjectZomboidPath $game -ZomboidHome $zomboidFixtureHome
    $expectedJar = (Get-FileHash (Join-Path $root 'payload\ZombieBuddy\libs\ZombieBuddy.jar') -Algorithm SHA256).Hash
    foreach ($jar in @((Join-Path $game 'ZombieBuddy.jar'), (Join-Path $zomboidFixtureHome 'mods\ZombieBuddy\libs\ZombieBuddy.jar'))) {
        if ((Get-FileHash $jar -Algorithm SHA256).Hash -ne $expectedJar) { throw "JAR mismatch: $jar" }
    }
    if ((Get-FileHash (Join-Path $game 'zbNative.dll') -Algorithm SHA256).Hash -ne '49E5D596B54E5E4EAB535E613CDC7C3F0DE9BB7EF07239C255E2B127657104CE') {
        throw 'Native fix mismatch.'
    }
    $json = Get-Content -Raw (Join-Path $game 'ProjectZomboid64.json') | ConvertFrom-Json
    if (@($json.vmArgs) -notcontains '-agentlib:zbNative') { throw 'Normal launcher was not patched.' }
    if ((Get-Content -Raw (Join-Path $game 'ProjectZomboid64.bat')) -notmatch '-agentlib:zbNative') { throw 'Alternate launcher was not patched.' }
    & (Join-Path $root 'Install-ZombieBuddy.ps1') -ProjectZomboidPath $game -ZomboidHome $zomboidFixtureHome -UseBundledJar
    if (@(Get-ChildItem (Join-Path $zomboidFixtureHome 'backups\ZombieBuddy-Friends') -Directory).Count -ne 1) { throw 'Reinstall did not back up the local mod.' }
    Write-Output 'Fresh install and reinstall fixture passed.'
} finally {
    $env:USERPROFILE = $oldProfile
}
