# Changelog

All notable changes to Arcadia are listed here. Versions follow [Semantic Versioning](https://semver.org).

## [0.1.0] - Unreleased

The first release: one native home for games from the Atari 2600 to the PlayStation 5, for Macs
with Apple silicon running macOS 26 or later.

### Added
- Library of 26 systems with box art, favorites, recently played, play time and search, in
  English, Türkçe, 简体中文, Español, हिन्दी, العربية, Français and Português (Brasil).
- Find Games on This Mac: searches folders and drives, recognises each game's console from the
  disc or ROM itself and adds it in place as a link.
- One-click installs and updates of 12 emulators from their official releases.
- Tuned presets for every emulator, written before each launch: renderer, resolution matched to
  the Mac's GPU through a single Graphics quality setting, no first-run wizards or update prompts,
  BIOS folders and saves kept by Arcadia.
- Controller mapping for player 1 through SDL, including emulators that need the device's exact
  name or GUID; Select + Start quits back to Arcadia in most emulators.
- BIOS handling: a BIOS card that sorts dropped files into place, built-in BIOS fallbacks for PS1
  and Saturn, and PS3 system software downloaded from Sony on first play.
- PS2 runs natively through RetroArch's PCSX2 core. PS4, PS5 and Wii U emulators only exist for
  Intel, so Arcadia offers to install Rosetta for them.
- A warning when a game closes right after starting, and download progress before launches.
- Up to four controllers mapped to players 1–4 in every emulator that supports it, telling
  identical controllers apart (DuckStation uses its multitap for 3–4 players).
- TV Mode: a full-screen, 10-foot interface for controllers with a hero for the focused game,
  shelves for Continue Playing, Favorites and each console, on-screen search, and options and
  problem menus. Controller input goes to the emulator while a game runs.
- Game details with snapshots, title screens, genre, developer, publisher, year and player count
  from libretro-database, and a Wikipedia description, downloaded on demand and cached.
- Collections, a sort menu and genre/decade/players filters on every game grid.
- The library updates as soon as games are added to or removed from its folder.
- Save Disk Space: lossless compression of PSP/PS2 ISOs to CSO and GameCube ISOs to GCZ, with
  estimated savings, verification and originals moved to the Trash.
- iCloud Drive save sync (off by default), with conflict backups and downloads before each launch.
- RetroAchievements sign-in for RetroArch, DuckStation, PPSSPP, Dolphin and Flycast, with
  hardcore mode.
- Spotlight search, Shortcuts and Siri actions ("Play Game", "Continue Playing"), a Continue
  Playing widget and `arcadia://` links.
- Launch logs in `~/Library/Logs/Arcadia`, opened from the failed-start alert or Settings.
- Automatic updates for Arcadia through Sparkle, and daily emulator update checks with an
  Update Available badge, Update All and background updates while no game is running.
