# ZombieBuddy Friends distribution

Versioned, manually installed ZombieBuddy for Project Zomboid Build 42.21 friends
who cannot download the original Steam Workshop item. This is a community
distribution, not an official ZombieBuddy release. ZombieBuddy is by Andrey
"Zed" Zaikin and is MIT licensed. Its original source is
https://github.com/zed-0xff/ZombieBuddy. The included 2.3.4 mod folder is an
unchanged snapshot from Workshop item 3619862853, except for its location in
this package. Its original `LICENSE.txt` is included.

The script selects the newest stable official `v2.x.x` GitHub release with a
SHA-256-identified `ZombieBuddy.jar`, downloads that JAR and its tagged source,
and installs the Build 42 Lua and media files from the matching source. The
2.3.4 snapshot in this ZIP supports offline installation with `-UseBundledJar`.
The package also includes an MIT licensed 2.3.3 based Build 42.21 compatibility
JAR by Antikristianos as a fallback. See the license files in `setup` and
[third-party notices](THIRD-PARTY-NOTICES.md).

## For Windows players

1. Download `ZombieBuddy-Friends.zip` and `SHA256SUMS.txt` from the
   [latest release](https://github.com/Bokicks-Labs/ZombieBuddy-Friends/releases/latest).
   Check the ZIP hash with `Get-FileHash .\ZombieBuddy-Friends.zip -Algorithm SHA256`.
2. Extract the ZIP and run `Install-ZombieBuddy.cmd` with Project Zomboid and
   any local server closed. The script downloads the latest official 2.x.x JAR,
   installs the local mod, and enables the normal and alternate Windows launchers.
3. Keep the extracted folder. For later patches, run `Update-ZombieBuddy.cmd`.
   It fetches the latest release and verifies its published SHA-256 before
   installing it.
4. Enable the `ZombieBuddy` mod as required by your other mods. If ZombieBuddy
   asks you to approve a Java mod, approve only the one you intended to run.

The installer places the mod at `%USERPROFILE%\Zomboid\mods\ZombieBuddy` and
backs up any prior local copy under
`%USERPROFILE%\Zomboid\backups\ZombieBuddy-Friends`. Its agent helper backs up
game root JAR and DLL changes under `%USERPROFILE%\Zomboid\backups\CW-ZombieBuddy`.
It does not change saves or Workshop subscriptions. It does not run the older
official Windows `.exe`, which still expects the removed Workshop item. If your game is in a
location Steam discovery cannot find, run `Install-ZombieBuddy.ps1` with
`-ProjectZomboidPath 'D:\path\to\ProjectZomboid'` in PowerShell.

The original Workshop item is currently unavailable. Steam will not install
this local package for friends automatically. The server must not request
Workshop item `3619862853` from new clients. Remove that number from the
server's `WorkshopItems` list; keep `ZombieBuddy` in `Mods` if the server
actually loads it. Test with a fresh client before relying on a live server.

## For maintainers

The source of the release is `payload/ZombieBuddy`. To publish a patch:

1. For changes to the bundled offline snapshot, replace or patch the payload
   and update the pinned JAR hash in both `Install-ZombieBuddy.ps1` and
   `setup/Setup-ZombieBuddyAgent.ps1`. Official 2.x.x updates are fetched at
   install time without a new release of this repo.
2. Test installation into a disposable Zomboid home and test the actual game
   with a second client. Keep the upstream and patch licenses and credits.
3. Run `scripts/Build-Release.ps1` and upload both files from `dist` to a new
   GitHub release. The existing updater follows the newest published release.

The native fix is pinned to
`Bokicks-Labs/ZombieBuddy-Windows-Native-Fix` release
`v2.3.3-pz42.21-native1`. The installer refuses an unexpected download hash.
Java mods run with full process privileges, so friends should review the
package source and only install releases from this repository.
