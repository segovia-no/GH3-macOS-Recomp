# GH3-macOS-Recomp

![Platform](https://img.shields.io/badge/platform-macOS%20(Apple%20Silicon)-blue)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
![Status](https://img.shields.io/badge/status-playable-brightgreen)

Play **Guitar Hero III: Legends of Rock** for PC natively on Apple Silicon Macs. It renders on Metal at 120 fps, and Xbox 360 wireless guitars work without installing a driver.

This is a *static recompilation*. The game's Windows executable from your own copy is translated ahead of time to C++ and compiled into a native arm64 program on your Mac. It runs on [SwARc](https://github.com/JTM-rootstorm/SwARc), a runtime that reimplements the Windows, Direct3D 9, DirectSound, DirectInput/XInput and Bink parts the game uses. There is no emulator, no Wine and no interpreter.

> **You need your own copy of the game.** You need a Guitar Hero III PC installation (version 1.3.1; the folder that has `GH3.exe` and `DATA/`). This repository contains no game code or assets. Everything game-specific is made from your copy, on your Mac.
>
> **Recommended:** start from a [BetterGH3](https://github.com/lunalawl/BetterGH3) installation. That is what this port was developed and tested with, and setup checks for that `GH3.exe` (see the [install guide](docs/guides/install.md)).

## Quick start
You need an Apple Silicon Mac with the [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/) (`xcode-select --install`) and [Homebrew](https://brew.sh).

```sh
git clone https://github.com/segovia-no/GH3-macOS-Recomp.git
cd GH3-macOS-Recomp
./setup.sh --game "/path/to/Guitar Hero III"
open "build/Guitar Hero III.app"
```

`setup.sh` installs the Homebrew packages it needs, translates the game, and builds `build/Guitar Hero III.app`. The first run takes about 18 minutes (M3 Pro); later runs only redo what changed. Drag the app to Applications if you like. Details are in the **[install guide](docs/guides/install.md)**.

## What works
- Intro movies, menus, and playing songs. Tested in quickplay with the keyboard and with a wireless guitar; other modes have not been checked one by one.
- **Metal** rendering. 120 fps on a 120 Hz display (vsync-capped). A window sized for Retina displays by default, or fullscreen.
- **Controllers**:
  - keyboard and mouse;
  - SDL gamepads (untested);
  - **Xbox 360 wireless guitars and gamepads** through the Windows wireless receiver. Clones work too; no driver or system changes are needed. They are read directly over USB.
- A double-clickable, ad hoc signed app bundle.

Not yet: GH3+ plugins (the plugin loader is disabled), online play (untested). See the [porting log](docs/notes/03-porting-log.md) for what is known.

## Documentation
| | |
|---|---|
| [Install](docs/guides/install.md) | requirements, building the app, updating, uninstalling |
| [Playing](docs/guides/playing.md) | controls (keyboard, mouse, guitars), audio calibration, settings |
| [Troubleshooting](docs/guides/troubleshooting.md) | logs, crash reports, controllers, resetting settings |
| [Building from source](docs/dev/building.md) | the pipeline step by step, developer tools |
| [Architecture](docs/dev/architecture.md) | how the recompilation works, repository layout |
| [Technical notes](docs/README.md) | research, decompilation cross-reference, porting log |
| [Changelog](CHANGELOG.md) | what changed in each release |

## Contributing
Found a bug or have an idea? [Open an issue](../../issues/new/choose). Pull requests are welcome; see **[CONTRIBUTING.md](CONTRIBUTING.md)** for how changes are tested and the few rules (above all: no game files in the repository).

## Credits
- [SwARc](https://github.com/JTM-rootstorm/SwARc) (MIT): the static recompiler and Win32 runtime this port is built on. Our changes to it are on the `gh3` branch of [our fork](https://github.com/segovia-no/SwARc/tree/gh3).
- [GH3+](https://github.com/ExileLord/GH3-Plus) and the PC modding community: what is known about GH3's PC executable.
- The GH3 research community: the decompilation, script and format projects listed in [docs/notes/01-research.md](docs/notes/01-research.md).
- [Ghidra](https://ghidra-sre.org), which found the functions the lifter starts from (`manifests/ghidra`).

## Distribution and legal
This repository contains only original code, build scripts and documentation. It has no game code, no game assets and nothing translated from `GH3.exe`. The tables in `manifests/` hold only addresses and names of functions (where they are, not what they do).

`setup.sh` makes the following on your computer, from your copy of the game:
- `build/` (the lifted C++, symbol exports, the `gh3` binary);
- `build/Guitar Hero III.app`;
- `~/Library/Application Support/gh3/game`.

All of these contain or are made from the game's code. They are for your own use and **must not be redistributed**. The Microsoft Visual C++ 2005 runtime DLLs the build needs are downloaded from Microsoft during setup and stay in `build/`.

The code, scripts and documentation here are released under the [MIT License](LICENSE). The license does not cover Guitar Hero III or anything generated from it.

This is an unofficial fan project for preservation and interoperability. It is not affiliated with or endorsed by Activision, Neversoft, RedOctane or Aspyr. "Guitar Hero" and related names are trademarks of their respective owners.
