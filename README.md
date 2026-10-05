# ZombieBuddy Friends distribution

Versioned, manually installed ZombieBuddy for Project Zomboid Build 42.21 friends
who cannot download the original Steam Workshop item. This is a community
distribution, not an official ZombieBuddy release. ZombieBuddy is by Andrey
"Zed" Zaikin and is MIT licensed. Its original source is
https://github.com/zed-0xff/ZombieBuddy. The included 2.3.4 mod folder is an
unchanged snapshot from Workshop item 3619862853, except for its location in
this package. Its original `LICENSE.txt` is included.

The package also includes an unchanged MIT licensed 2.3.3 based Build 42.21
compatibility JAR by Antikristianos as a fallback, plus the Chaosworld setup
helper. The helper downloads Zed's official Windows installer and a pinned
Windows native fix when needed; those executables are not bundled. See the
license files in `setup` and the provenance in
[the CW notices](https://github.com/Bokicks-Labs/CW-Modpack-Compatibility/blob/main/Contents/mods/CWModpackCompatibility/ZombieBuddy-Setup/THIRD-PARTY-NOTICES.md).

## For Windows players

1. Download `ZombieBuddy-Friends.zip` and `SHA256SUMS.txt` from the
   [latest release](https://github.com/Bokicks-Labs/ZombieBuddy-Friends/releases/latest).
   Check the ZIP hash with `Get-FileHash .\ZombieBuddy-Friends.zip -Algorithm SHA256`.
2. Extract the ZIP and run `Install-ZombieBuddy.cmd` with Project Zomboid and
   any local server closed. The official ZombieBuddy installer may open to set
   up the game launcher; review its preview and choose the launch modes you use.
3. Keep the extracted folder. For later patches, run `Update-ZombieBuddy.cmd`.
   It fetches the latest release and verifies its published SHA-256 before
   installing it.
4. Enable the `ZombieBuddy` mod as required by your other mods. If ZombieBuddy
   asks you to approve a Java mod, approve only the one you intended to run.

The installer places the mod at `%USERPROFILE%\Zomboid\mods\ZombieBuddy` and
backs up any prior local copy under
`%USERPROFILE%\Zomboid\backups\ZombieBuddy-Friends`. Its agent helper backs up
game root JAR and DLL changes under `%USERPROFILE%\Zomboid\backups\CW-ZombieBuddy`.
It does not change saves or Workshop subscriptions. If your game is in a
location Steam discovery cannot find, run `Install-ZombieBuddy.ps1` with
`-ProjectZomboidPath 'D:\path\to\ProjectZomboid'` in PowerShell.

The original Workshop item is currently unavailable. Steam will not install
this local package for friends automatically. The server must not request
Workshop item `3619862853` from new clients. Remove that number from the
server's `WorkshopItems` list; keep `ZombieBuddy` in `Mods` if the server
actually loads it. Test with a fresh client before relying on a live server.

## For maintainers

The source of the release is `payload/ZombieBuddy`. To publish a patch:

1. Replace or patch the payload and update the pinned JAR hash in both
   `Install-ZombieBuddy.ps1` and `setup/Setup-ZombieBuddyAgent.ps1`.
2. Test installation into a disposable Zomboid home and test the actual game
   with a second client. Keep the upstream and patch licenses and credits.
3. Run `scripts/Build-Release.ps1` and upload both files from `dist` to a new
   GitHub release. The existing updater follows the newest published release.

The Windows agent installer is pinned to Zed's `windows_installer_4.2` release.
The native fix is pinned to
`Bokicks-Labs/ZombieBuddy-Windows-Native-Fix` release
`v2.3.3-pz42.21-native1`. The installer refuses an unexpected download hash.
Java mods run with full process privileges, so friends should review the
package source and only install releases from this repository.
