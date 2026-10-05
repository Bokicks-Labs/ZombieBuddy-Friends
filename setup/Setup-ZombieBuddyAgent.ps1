[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Install', 'Status', 'Restore')]
    [string]$Action = 'Install',
    [string]$ProjectZomboidPath,
    [switch]$LaunchOfficialInstaller,
    [string]$BackupPath
)

$ErrorActionPreference = 'Stop'

$expectedInstallerHash = '2A52466AFE804FECE5E88868EEF75A70E8964D3E4E01A3629B57CF6FF19E24B3'
$expectedPatchHash = '909D1FF579BE34AC2C3EE860A1A499B889A677D0DA74EB4A1D3632AE4E2ED102'
$expectedPackageJarHash = 'EB79B9876332010733A8E0D7CE4FE0377846059A9E28859029E2A0FB449F6CF2'
$expectedNativeHash = '49E5D596B54E5E4EAB535E613CDC7C3F0DE9BB7EF07239C255E2B127657104CE'
$installerDownloadUrl = 'https://github.com/zed-0xff/ZombieBuddy/releases/download/windows_installer_4.2/ZombieBuddyInstaller_v4.2.exe'
$nativeDownloadUrl = 'https://github.com/Bokicks-Labs/ZombieBuddy-Windows-Native-Fix/releases/download/v2.3.3-pz42.21-native1/zbNative.dll'
$patchPath = Join-Path $PSScriptRoot 'ZombieBuddy-2.3.3-B42.21-Fix.jar'
$backupRoot = Join-Path $env:USERPROFILE 'Zomboid\backups\CW-ZombieBuddy'

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-JarVersion([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $jar = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $manifest = $jar.GetEntry('META-INF/MANIFEST.MF')
        if (-not $manifest) { return $null }
        $reader = [IO.StreamReader]::new($manifest.Open())
        try {
            while (($line = $reader.ReadLine()) -ne $null -and $line -ne '') {
                if ($line -match '^Implementation-Version:\s*(\S+)') { return $Matches[1] }
            }
        } finally {
            $reader.Dispose()
        }
    } finally {
        $jar.Dispose()
    }
    return $null
}

function Get-WorkshopJar([string]$GameRoot) {
    $packageJar = Join-Path $PSScriptRoot '..\payload\ZombieBuddy\libs\ZombieBuddy.jar'
    if (Test-Path -LiteralPath $packageJar -PathType Leaf) {
        Assert-BundledFile $packageJar $expectedPackageJarHash 'Packaged ZombieBuddy 2.3.4 JAR'
        $packageVersionText = Get-JarVersion $packageJar
        $packageVersion = $null
        if (-not [version]::TryParse($packageVersionText, [ref]$packageVersion)) {
            throw "Could not read the packaged ZombieBuddy JAR version: $packageJar"
        }
        return [pscustomobject]@{ Path = $packageJar; Version = $packageVersion; Hash = Get-Sha256 $packageJar }
    }
    $libraries = [Collections.Generic.List[string]]::new()
    $gameMarker = '\steamapps\common\'
    $index = $GameRoot.IndexOf($gameMarker, [StringComparison]::OrdinalIgnoreCase)
    if ($index -ge 0) { $libraries.Add($GameRoot.Substring(0, $index)) }
    foreach ($library in Get-SteamLibraries) { $libraries.Add($library) }

    foreach ($library in @($libraries | Select-Object -Unique)) {
        $path = Join-Path $library 'steamapps\workshop\content\108600\3619862853\mods\ZombieBuddy\libs\ZombieBuddy.jar'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $versionText = Get-JarVersion $path
        $version = $null
        if (-not [version]::TryParse($versionText, [ref]$version)) {
            throw "Could not read the official Workshop ZombieBuddy JAR version: $path"
        }
        return [pscustomobject]@{ Path = $path; Version = $version; Hash = Get-Sha256 $path }
    }
    return $null
}

function Assert-BundledFile([string]$Path, [string]$ExpectedHash, [string]$Label) {
    $actualHash = Get-Sha256 $Path
    if (-not $actualHash) {
        throw "$Label is missing: $Path"
    }
    if ($actualHash -ne $ExpectedHash) {
        throw "$Label failed SHA-256 verification. Expected $ExpectedHash; found $actualHash"
    }
}

function Test-GameRoot([string]$Path) {
    if (-not $Path) {
        return $false
    }
    return (
        (Test-Path -LiteralPath (Join-Path $Path 'ProjectZomboid64.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Path 'projectzomboid.jar') -PathType Leaf)
    )
}

function Get-SteamLibraries {
    $result = [Collections.Generic.List[string]]::new()
    $steamPath = $null
    try {
        $steamPath = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
    } catch {
        # Steam may be installed for another Windows account or omitted on a server.
    }

    if ($steamPath) {
        $result.Add([IO.Path]::GetFullPath($steamPath))
        $libraryFile = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $libraryFile -PathType Leaf) {
            $libraryText = Get-Content -Raw -LiteralPath $libraryFile
            foreach ($match in [regex]::Matches($libraryText, '(?m)^\s*"path"\s+"(?<path>[^"]+)"')) {
                $library = $match.Groups['path'].Value -replace '\\\\', '\'
                $result.Add([IO.Path]::GetFullPath($library))
            }
        }
    }

    return @($result | Select-Object -Unique)
}

function Resolve-GameRoot([string]$ExplicitPath) {
    if ($ExplicitPath) {
        $resolved = [IO.Path]::GetFullPath($ExplicitPath).TrimEnd('\')
        if (-not (Test-GameRoot $resolved)) {
            throw "The supplied Project Zomboid path is not a game installation: $resolved"
        }
        return $resolved
    }

    $candidates = [Collections.Generic.List[string]]::new()
    $setupPath = [IO.Path]::GetFullPath($PSScriptRoot)
    $workshopMarker = '\steamapps\workshop\content\108600\'
    $markerIndex = $setupPath.IndexOf($workshopMarker, [StringComparison]::OrdinalIgnoreCase)
    if ($markerIndex -ge 0) {
        $libraryRoot = $setupPath.Substring(0, $markerIndex)
        $candidates.Add((Join-Path $libraryRoot 'steamapps\common\ProjectZomboid'))
    }

    foreach ($library in Get-SteamLibraries) {
        $manifest = Join-Path $library 'steamapps\appmanifest_108600.acf'
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
            continue
        }
        $manifestText = Get-Content -Raw -LiteralPath $manifest
        $installDirMatch = [regex]::Match($manifestText, '(?m)^\s*"installdir"\s+"(?<name>[^"]+)"')
        if ($installDirMatch.Success) {
            $candidates.Add((Join-Path $library ('steamapps\common\' + $installDirMatch.Groups['name'].Value)))
        }
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        $resolved = [IO.Path]::GetFullPath($candidate).TrimEnd('\')
        if (Test-GameRoot $resolved) {
            return $resolved
        }
    }

    throw 'Could not locate Project Zomboid. Rerun with -ProjectZomboidPath pointing at the installation root.'
}

function Get-AgentState([string]$GameRoot) {
    $liveJar = Join-Path $GameRoot 'ZombieBuddy.jar'
    $nativeDll = Join-Path $GameRoot 'zbNative.dll'
    $normalLauncher = Join-Path $GameRoot 'ProjectZomboid64.json'
    $alternateLauncher = Join-Path $GameRoot 'ProjectZomboid64.bat'
    $launcherConfigured = $false

    foreach ($launcher in @($normalLauncher, $alternateLauncher)) {
        if ((Test-Path -LiteralPath $launcher -PathType Leaf) -and
            (Get-Content -Raw -LiteralPath $launcher) -match '-agentlib:zbNative') {
            $launcherConfigured = $true
        }
    }

    $liveHash = Get-Sha256 $liveJar
    $nativeHash = Get-Sha256 $nativeDll
    return [pscustomobject]@{
        GameRoot = $GameRoot
        LiveJar = $liveJar
        LiveJarExists = Test-Path -LiteralPath $liveJar -PathType Leaf
        LiveJarHash = $liveHash
        NativeDllExists = Test-Path -LiteralPath $nativeDll -PathType Leaf
        NativeDll = $nativeDll
        NativeDllHash = $nativeHash
        LauncherFileConfigured = $launcherConfigured
        IsPatched = $liveHash -eq $expectedPatchHash
        IsNativePatched = $nativeHash -eq $expectedNativeHash
    }
}

function Assert-GameStopped([string]$GameRoot) {
    $rootPrefix = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\') + '\'
    $running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^ProjectZomboid' -and
            $_.ExecutablePath -and
            [IO.Path]::GetFullPath($_.ExecutablePath).StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
        }
    if ($running) {
        throw "Project Zomboid is running from $GameRoot. Close it before installing or restoring ZombieBuddy."
    }
}

function Show-State($State) {
    Write-Output "Project Zomboid: $($State.GameRoot)"
    Write-Output "ZombieBuddy.jar present: $($State.LiveJarExists)"
    Write-Output "ZombieBuddy.jar SHA-256: $($State.LiveJarHash)"
    Write-Output "zbNative.dll present: $($State.NativeDllExists)"
    Write-Output "zbNative.dll SHA-256: $($State.NativeDllHash)"
    Write-Output "Launcher file contains -agentlib:zbNative: $($State.LauncherFileConfigured)"
    Write-Output "42.21 compatibility JAR installed: $($State.IsPatched)"
    Write-Output "Windows native DNS loader installed: $($State.IsNativePatched)"
    if (-not $State.LauncherFileConfigured) {
        Write-Warning 'The launcher files do not contain -agentlib:zbNative. Steam launch options may still provide it; verify them manually.'
    }
}

function Invoke-OfficialInstaller {
    if (-not $PSCmdlet.ShouldProcess($installerDownloadUrl, 'Download, verify, and run Zed''s official ZombieBuddy installer v4.2')) {
        return
    }

    $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'CW-ZombieBuddy'
    New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    $downloadPath = Join-Path $downloadRoot ('ZombieBuddyInstaller_v4.2-' + [guid]::NewGuid().ToString('N') + '.exe')
    try {
        Write-Output "Downloading Zed's official ZombieBuddy installer from $installerDownloadUrl"
        try {
            Invoke-WebRequest -Uri $installerDownloadUrl -OutFile $downloadPath -UseBasicParsing
        } catch {
            throw "Could not download the official ZombieBuddy installer. Download it manually from Zed's windows_installer_4.2 GitHub release, verify SHA-256 $expectedInstallerHash, run it, and then rerun this helper. $($_.Exception.Message)"
        }
        Assert-BundledFile $downloadPath $expectedInstallerHash 'Downloaded ZombieBuddy installer'
        Write-Output 'Starting the verified interactive ZombieBuddy installer. Review its preview before accepting changes.'
        $process = Start-Process -FilePath $downloadPath -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            throw "ZombieBuddy installer exited with code $($process.ExitCode)."
        }
    } finally {
        if (Test-Path -LiteralPath $downloadPath -PathType Leaf) {
            Remove-Item -LiteralPath $downloadPath -Force
        }
    }
}

function Install-Patch([string]$GameRoot, [string]$SourcePath, [string]$SourceHash, [string]$Description) {
    Assert-BundledFile $SourcePath $SourceHash $Description
    Assert-GameStopped $GameRoot
    $state = Get-AgentState $GameRoot

    if ($state.LiveJarHash -eq $SourceHash) {
        Write-Output "$Description is already installed."
        return
    }
    if (-not $state.LiveJarExists -or -not $state.NativeDllExists) {
        throw 'The base ZombieBuddy installation is incomplete. Rerun with -LaunchOfficialInstaller, then retry.'
    }
    if (Test-Path -LiteralPath (Join-Path $GameRoot 'ZombieBuddy.jar.new') -PathType Leaf) {
        throw 'A pending ZombieBuddy.jar.new update would replace the compatibility JAR at startup. Resolve it before installing.'
    }

    if (-not $PSCmdlet.ShouldProcess($state.LiveJar, "Back up and install $Description")) {
        return
    }

    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupJar = Join-Path $backupRoot "ZombieBuddy-$timestamp-$($state.LiveJarHash).jar"
    $manifestPath = "$backupJar.json"
    Copy-Item -LiteralPath $state.LiveJar -Destination $backupJar
    if ((Get-Sha256 $backupJar) -ne $state.LiveJarHash) {
        throw 'Backup hash verification failed. The live JAR was not changed.'
    }

    [ordered]@{
        formatVersion = 1
        created = (Get-Date).ToString('o')
        gameRoot = $GameRoot
        livePath = $state.LiveJar
        backupPath = $backupJar
        originalHash = $state.LiveJarHash
        installedHash = $SourceHash
    } | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $stagedJar = Join-Path $GameRoot ('.ZombieBuddy.jar.cw-stage-' + [guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $stagedJar
        if ((Get-Sha256 $stagedJar) -ne $SourceHash) {
            throw 'Staged ZombieBuddy JAR failed hash verification.'
        }
        Move-Item -LiteralPath $stagedJar -Destination $state.LiveJar -Force
    } finally {
        if (Test-Path -LiteralPath $stagedJar) {
            Remove-Item -LiteralPath $stagedJar -Force
        }
    }

    if ((Get-Sha256 $state.LiveJar) -ne $SourceHash) {
        throw "Installed JAR failed final verification. Restore from: $backupJar"
    }
    Write-Output "Installed ${Description}: $($state.LiveJar)"
    Write-Output "Backup: $backupJar"
}

function Install-NativePatch([string]$GameRoot) {
    Assert-GameStopped $GameRoot
    $state = Get-AgentState $GameRoot
    if ($state.IsNativePatched) {
        Write-Output 'The expected Windows native DNS loader is already installed.'
        return
    }
    if (-not $state.NativeDllExists) {
        throw 'The base ZombieBuddy native DLL is missing. Install the official Windows agent first.'
    }
    if (-not $PSCmdlet.ShouldProcess($state.NativeDll, 'Download, verify, back up, and install the pinned Windows native DNS loader')) {
        return
    }

    $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'CW-ZombieBuddy'
    New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    $downloadPath = Join-Path $downloadRoot ('zbNative-' + [guid]::NewGuid().ToString('N') + '.dll')
    $stagedDll = $null
    try {
        try {
            Invoke-WebRequest -Uri $nativeDownloadUrl -OutFile $downloadPath -UseBasicParsing
        } catch {
            throw "Could not download the pinned native loader from $nativeDownloadUrl. $($_.Exception.Message)"
        }
        Assert-BundledFile $downloadPath $expectedNativeHash 'Downloaded Windows native DNS loader'

        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupDll = Join-Path $backupRoot "zbNative-$timestamp-$($state.NativeDllHash).dll"
        $manifestPath = "$backupDll.json"
        Copy-Item -LiteralPath $state.NativeDll -Destination $backupDll
        if ((Get-Sha256 $backupDll) -ne $state.NativeDllHash) {
            throw 'Native DLL backup hash verification failed. The live DLL was not changed.'
        }
        [ordered]@{
            formatVersion = 1
            created = (Get-Date).ToString('o')
            gameRoot = $GameRoot
            livePath = $state.NativeDll
            backupPath = $backupDll
            originalHash = $state.NativeDllHash
            installedHash = $expectedNativeHash
        } | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $stagedDll = Join-Path $GameRoot ('.zbNative.dll.cw-stage-' + [guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath $downloadPath -Destination $stagedDll
        Assert-BundledFile $stagedDll $expectedNativeHash 'Staged Windows native DNS loader'
        Move-Item -LiteralPath $stagedDll -Destination $state.NativeDll -Force
        Assert-BundledFile $state.NativeDll $expectedNativeHash 'Installed Windows native DNS loader'
        Write-Output "Installed Windows native DNS loader: $($state.NativeDll)"
        Write-Output "Backup: $backupDll"
    } finally {
        if ($stagedDll -and (Test-Path -LiteralPath $stagedDll -PathType Leaf)) {
            Remove-Item -LiteralPath $stagedDll -Force
        }
        if (Test-Path -LiteralPath $downloadPath -PathType Leaf) {
            Remove-Item -LiteralPath $downloadPath -Force
        }
    }
}

function Restore-Backup([string]$GameRoot, [string]$RequestedBackup, [switch]$SkipIfMissing) {
    Assert-GameStopped $GameRoot
    if ($RequestedBackup) {
        $candidate = [IO.Path]::GetFullPath($RequestedBackup)
        $manifestCandidate = if ($candidate.EndsWith('.json')) { $candidate } else { "$candidate.json" }
        if (-not (Test-Path -LiteralPath $manifestCandidate -PathType Leaf)) {
            throw "Backup manifest not found: $manifestCandidate"
        }
        $manifest = Get-Content -Raw -LiteralPath $manifestCandidate | ConvertFrom-Json
    } else {
        $latest = Get-ChildItem -LiteralPath $backupRoot -File -Filter '*.jar.json' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Where-Object {
                try {
                    $record = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
                    [IO.Path]::GetFullPath([string]$record.gameRoot) -eq [IO.Path]::GetFullPath($GameRoot)
                } catch { $false }
            } | Select-Object -First 1
        if (-not $latest) {
            if ($SkipIfMissing) { return }
            throw "No CW ZombieBuddy backup manifest was found under $backupRoot"
        }
        $manifest = Get-Content -Raw -LiteralPath $latest.FullName | ConvertFrom-Json
    }
    if ([IO.Path]::GetFullPath([string]$manifest.gameRoot) -ne [IO.Path]::GetFullPath($GameRoot)) {
        throw 'Backup manifest belongs to a different Project Zomboid installation.'
    }

    $resolvedBackup = [IO.Path]::GetFullPath([string]$manifest.backupPath)
    $resolvedTarget = [IO.Path]::GetFullPath((Join-Path $GameRoot 'ZombieBuddy.jar'))
    if (-not (Test-Path -LiteralPath $resolvedBackup -PathType Leaf)) {
        throw "Backup JAR is missing: $resolvedBackup"
    }
    if ((Get-Sha256 $resolvedBackup) -ne [string]$manifest.originalHash) {
        throw 'Backup JAR does not match its recorded SHA-256.'
    }
    if (-not $PSCmdlet.ShouldProcess($resolvedTarget, "Restore ZombieBuddy backup $resolvedBackup")) {
        return
    }
    Copy-Item -LiteralPath $resolvedBackup -Destination $resolvedTarget -Force
    if ((Get-Sha256 $resolvedTarget) -ne [string]$manifest.originalHash) {
        throw 'Restored JAR failed final hash verification.'
    }
    Write-Output "Restored ZombieBuddy JAR: $resolvedTarget"
}

function Restore-NativeBackup([string]$GameRoot, [string]$RequestedBackup, [switch]$SkipIfMissing) {
    Assert-GameStopped $GameRoot
    if ($RequestedBackup) {
        $candidate = [IO.Path]::GetFullPath($RequestedBackup)
        $manifestCandidate = if ($candidate.EndsWith('.json')) { $candidate } else { "$candidate.json" }
        if (-not (Test-Path -LiteralPath $manifestCandidate -PathType Leaf)) {
            throw "Native backup manifest not found: $manifestCandidate"
        }
    } else {
        $latest = Get-ChildItem -LiteralPath $backupRoot -File -Filter '*.dll.json' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Where-Object {
                try {
                    $record = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
                    [IO.Path]::GetFullPath([string]$record.gameRoot) -eq [IO.Path]::GetFullPath($GameRoot)
                } catch { $false }
            } | Select-Object -First 1
        if (-not $latest) {
            if ($SkipIfMissing) { return }
            throw "No CW ZombieBuddy native backup manifest was found under $backupRoot"
        }
        $manifestCandidate = $latest.FullName
    }
    $manifest = Get-Content -Raw -LiteralPath $manifestCandidate | ConvertFrom-Json
    if ([IO.Path]::GetFullPath([string]$manifest.gameRoot) -ne [IO.Path]::GetFullPath($GameRoot)) {
        throw 'Native backup manifest belongs to a different Project Zomboid installation.'
    }
    $resolvedBackup = [IO.Path]::GetFullPath([string]$manifest.backupPath)
    $resolvedTarget = [IO.Path]::GetFullPath((Join-Path $GameRoot 'zbNative.dll'))
    if (-not (Test-Path -LiteralPath $resolvedBackup -PathType Leaf)) {
        throw "Native backup DLL is missing: $resolvedBackup"
    }
    if ((Get-Sha256 $resolvedBackup) -ne [string]$manifest.originalHash) {
        throw 'Native backup DLL does not match its recorded SHA-256.'
    }
    if (-not $PSCmdlet.ShouldProcess($resolvedTarget, "Restore ZombieBuddy native backup $resolvedBackup")) {
        return
    }
    Copy-Item -LiteralPath $resolvedBackup -Destination $resolvedTarget -Force
    if ((Get-Sha256 $resolvedTarget) -ne [string]$manifest.originalHash) {
        throw 'Restored native DLL failed final hash verification.'
    }
    Write-Output "Restored ZombieBuddy native DLL: $resolvedTarget"
}

if ($env:OS -ne 'Windows_NT') {
    throw 'This bundled helper supports Windows clients and Windows dedicated servers only.'
}

Assert-BundledFile $patchPath $expectedPatchHash 'Bundled ZombieBuddy 42.21 compatibility JAR'
$gameRoot = Resolve-GameRoot $ProjectZomboidPath

switch ($Action) {
    'Status' {
        Show-State (Get-AgentState $gameRoot)
    }
    'Install' {
        $state = Get-AgentState $gameRoot
        if ((-not $state.LiveJarExists -or -not $state.NativeDllExists) -and $LaunchOfficialInstaller) {
            Invoke-OfficialInstaller
            $gameRoot = Resolve-GameRoot $ProjectZomboidPath
            $state = Get-AgentState $gameRoot
        }
        if (Test-Path -LiteralPath (Join-Path $gameRoot 'ZombieBuddy.jar.new') -PathType Leaf) {
            throw 'A pending ZombieBuddy.jar.new update would replace the compatibility JAR at startup. Resolve it before installing.'
        }
        $sourcePath = $patchPath
        $sourceHash = $expectedPatchHash
        $sourceVersion = [version]'2.3.3'
        $description = 'bundled ZombieBuddy 42.21 compatibility JAR'
        $workshopJar = Get-WorkshopJar $gameRoot
        if ($workshopJar -and $workshopJar.Version -gt $sourceVersion) {
            $sourcePath = $workshopJar.Path
            $sourceHash = $workshopJar.Hash
            $sourceVersion = $workshopJar.Version
            $description = "packaged ZombieBuddy $sourceVersion JAR"
        }
        $liveVersion = $null
        if ($state.LiveJarExists -and -not $state.IsPatched) {
            $liveVersionText = Get-JarVersion $state.LiveJar
            if ($liveVersionText -and -not [version]::TryParse($liveVersionText, [ref]$liveVersion)) {
                throw "Could not read the installed ZombieBuddy JAR version: $($state.LiveJar)"
            }
        }
        $installJar = -not $state.IsPatched -or $sourceVersion -gt [version]'2.3.3'
        if ($liveVersion -and $liveVersion -gt $sourceVersion) {
            $installJar = $false
        }
        Install-NativePatch $gameRoot
        if ($installJar) {
            Install-Patch $gameRoot $sourcePath $sourceHash $description
        } else {
            Write-Output 'Keeping the installed ZombieBuddy JAR; it is current or newer.'
        }
        Show-State (Get-AgentState $gameRoot)
    }
    'Restore' {
        if ($BackupPath -match '\.dll(?:\.json)?$') {
            Restore-NativeBackup $gameRoot $BackupPath
        } elseif ($BackupPath) {
            Restore-Backup $gameRoot $BackupPath
        } else {
            Restore-NativeBackup $gameRoot '' -SkipIfMissing
            Restore-Backup $gameRoot '' -SkipIfMissing
        }
        Show-State (Get-AgentState $gameRoot)
    }
}
