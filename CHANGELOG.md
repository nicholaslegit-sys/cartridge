# Changelog

Each release's section here becomes its notes on the GitHub release page.

## [1.3.5] - 2026-09-20

### Fixed

- Pressing Play on a PlayStation game opened DuckStation's setup wizard and stopped there instead of booting the disc. Cartridge has already put the BIOS where DuckStation looks, so it now marks that wizard done, as it already did for PCSX2.
- Adding a lot of games at once asked libretro for the same list of covers once per game. It is fetched once now, so a big library comes in much faster.
- A game added while the Mac was offline was remembered as having no cover and never looked up again. Cartridge now tries again next time it runs.

## [1.3.4] - 2026-09-20

### Fixed

- **Cartridge runs on Intel Macs.** Every build until now was Apple Silicon only, so an Intel Mac refused to open the app at all, although Cartridge asks only for macOS 14. The release is now built for both kinds of Mac.

## [1.3.3] - 2026-09-20

### Fixed

- Covers were only found for games whose file still had its full Redump name. A game renamed by hand, or copied by Finder into "… (USA) 2.iso", now has libretro's box art library searched for it too.
- Picking a disc's .cue and its .bin together in Add Games… added the same game twice. The picker and drag-and-drop now leave out the track files a disc already brings with it, which is what the games folder scan has always done.
- Double-clicking a game didn't always start it: the second click was lost once the first opened the details panel.

## [1.3.2] - 2026-09-18

### Fixed

- Games added before 1.3.0 from a Finder copy ("… (USA) 2.iso") kept the " 2" in their title, so Cartridge looked for a sequel and missed the right manual and artwork. Those titles are now fixed when the library loads.
- When no manual is a sure match, the message now says which sites were searched and what to do next: pick from Possible Matches, search the Internet Archive yourself, or choose a PDF.

## [1.3.1] - 2026-09-18

### Added

- **Search Artwork…** in a game's right-click menu.

### Fixed

- Fetch Missing Artwork and Check Game File (from the right-click menu) finished without showing anything, so they seemed not to work. Both now say what they found, and Fetch Missing Artwork offers to search by hand for games still missing a cover.

## [1.3.0] - 2026-09-18

### Added

- **Zipped discs.** Drop or pick a .zip or .7z holding an ISO, CUE/BIN, CHD or PS3/PS4 folder and Cartridge unpacks it (several at once, straight onto your games drive) and adds the game inside. Zipped cartridge ROMs still stay zipped, since RetroArch plays them as they are. Unpacked games can now be checked against the Redump list too.
- **Search artwork sources by hand.** When the automatic lookup finds nothing, the game's panel says so and offers Search Sources…, which now searches libretro's box art library alongside LaunchBox and IGDB. libretro needs no account.

- **Advanced Mode** (Settings → Advanced). Set resolution (Native to 4K), widescreen hack, aspect ratio and fullscreen for PCSX2, DuckStation, Dolphin, PPSSPP, Flycast and RetroArch, and override any of them for a single game in its details. Cartridge writes them into the emulator's settings when it starts a game and puts the old values back when the emulator quits.

### Fixed

- PS2 games wouldn't start the first time: PCSX2 opened its setup wizard instead, and quit if it was cancelled. Cartridge now marks that wizard done and selects the BIOS you added, keeping PCSX2's own default settings.
- A Finder duplicate suffix ("… (USA) 2.iso") no longer ends up in the game's title, where it also stopped artwork being found.
- The installer disk is named after its version ("Cartridge 1.2.3"). With an older installer still open, the new one's window could show the older background and version number.

## [1.2.2] - 2026-09-18

### Added

- **Demo Mode.** A tickbox in Settings → About swaps in a sample library of well-known games to try the shelf with. It lives in its own folder, so your own library is untouched and comes back when you turn it off.

### Changed

- The Credits tab in Settings is now called About.

### Fixed

- Real PS2 BIOS dumps were turned away as "not a PS2 BIOS". Cartridge now finds their file table where retail dumps keep it, and says which files to use from newer dumps that split the BIOS into .ROM0, .ROM1 and so on.

## [1.2.1] - 2026-09-18

### Fixed

- The homebrew store skips any Homebrew Hub entry whose folder name would lead outside your games folder.
- A homebrew game's website link only opens if it is a web address.

## [1.2.0] - 2026-09-18

Everything since 1.0.0 - versions 1.0.1 and 1.1.0 were numbered but never released.

### Added

- **Setup.** The first launch asks which consoles you play, sorts out the BIOS files they need, where your games should live, and which emulators to install. Afterwards Cartridge only shows those consoles.
- **BIOS files you can trust.** Each BIOS you add is identified from its own contents - which PlayStation or PS2 revision it is, and for which region - then copied to where its emulator looks and fingerprinted, so damage shows up later. Pressing Play on a game whose emulator has no BIOS now says so instead of letting the emulator fail.
- **Games folder.** Games dropped into your games folder are added by themselves; a disc's track files stay part of it.
- **Save backups.** The Saves page finds every emulator's saves, backs them up to iCloud Drive or a folder you choose after each game, keeps the last ten, and can put any of them back.
- **Dump check.** Check Game File compares a game with the No-Intro and Redump lists of known-good dumps - the usual reason a game won't boot is a bad dump.
- **RetroAchievements.** Sign in once and RetroArch, DuckStation and PCSX2 all earn achievements on your account.
- **Controllers.** See what's connected and what each emulator needs, once, to use it.
- **Update notice.** Cartridge → Check for Updates…
- A new app icon, and a disk-image installer.

### Changed

- Cartridge is released under the MIT licence.
- The emulator list and the import sheet put your consoles first.

### Fixed

- RetroArch BIOS files go to `~/Documents/RetroArch/system`, where RetroArch has looked since early 2024.
- A game file named `..` from Homebrew Hub could delete a console's games folder; download names that leave their folder are now refused.
- Emulator downloads must come from the project's own release page and keep the same signer as the copy already installed.
- Disc playlists that point outside their folder are refused before anything in them is opened.
- The IGDB client secret is sent in the request body instead of the URL.
- A games folder on an unplugged drive is named as such instead of "file is missing".
- Scrolling a large library no longer keeps every cover it has drawn in memory.

## [1.0.0] - 2026-09-17

The first release: a game library with a 3D shelf, emulators installed from their official releases, a homebrew store, artwork, trailers and instruction manuals.
