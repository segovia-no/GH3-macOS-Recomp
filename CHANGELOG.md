# Changelog

All notable changes to this project. Versions follow [Semantic Versioning](https://semver.org); before 1.0, a minor version may change how the game is built.

## [0.1.0] - 2026-11-09
First playable release. Source only: the game is built on your Mac from your own copy (see the [install guide](docs/guides/install.md)).

### Works
- Intro movies, menus and songs. Tested in quickplay with the keyboard and with an Xbox 360 wireless guitar.
- Metal rendering at 120 fps on a 120 Hz display (vsync-capped), in a window or fullscreen.
- Audio through CoreAudio. BetterGH3's audio and video calibration offsets work: calibrate once for your output (see [playing.md](docs/guides/playing.md#audio-calibration)).
- Keyboard and mouse. In a window the pointer stays free.
- Xbox 360 wireless guitars through the Windows receiver (clones too), read over USB with no driver: frets, strum bar and whammy.
- A double-clickable app bundle. Quit from the Dock, ⌘Q or the close button.
- `./setup.sh` builds everything from your game folder in about 18 minutes (M3 Pro). The Ghidra analysis comes with the repository, so Ghidra isn't needed.

### Known limitations
- Only the `GH3.exe` from a BetterGH3 installation is supported (SHA-256 `4322a71d…5e804`).
- GH3+ plugins don't load (the plugin loader is replaced by a stub).
- Untested: online play, tilt for Star Power, Xbox 360 gamepads on the receiver and rumble, other gamepads (through SDL), and game modes other than quickplay.
- Requires macOS 26 or later: the bundled libraries are built for it.

### GH3 Builder (experimental)
- An app that builds the game with only Apple's Command Line Tools: no Homebrew, no terminal. It is attached to the release (`GH3-Builder-0.1.0-macOS26-arm64.zip`, Apple Silicon, macOS 26+). It isn't notarized, so allow it once with Open Anyway.
- It holds nothing from the game. Its open-source components are listed in its `licenses/NOTICES.md`, with the LGPL FFmpeg built for it. The LGPL and GPL sources are attached as `GH3-Builder-0.1.0-sources.tar`. Details: [docs/notes/04-builder-spike.md](docs/notes/04-builder-spike.md).

### Built on
- [SwARc](https://github.com/JTM-rootstorm/SwARc) at [`gh3-v0.1.0`](https://github.com/segovia-no/SwARc/tree/gh3-v0.1.0) on our fork (`4a7ec39`).

[0.1.0]: https://github.com/segovia-no/GH3-macOS-Recomp/releases/tag/v0.1.0
