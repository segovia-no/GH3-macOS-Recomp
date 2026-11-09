# Install

The app is built on your Mac from your own copy of the game. There is no download with the game in it.

## Requirements
- A Mac with **Apple Silicon** (M1 or later) running **macOS 26** or later. The libraries the app bundles are built for macOS 26.
- **Your own Guitar Hero III: Legends of Rock installation for PC** (version 1.3.1): the folder with `GH3.exe`, `DATA/`, `AWL.dll` and `fmodex.dll`. We recommend starting from a [BetterGH3](https://github.com/lunalawl/BetterGH3) installation, which is the one this port was developed and tested with. The build is made for one specific `GH3.exe` (SHA-256 `4322a71d…5e804`, see [docs/README.md](../README.md)), and setup stops if yours differs.
- The **Xcode Command Line Tools**: `xcode-select --install`.
- **Homebrew** ([brew.sh](https://brew.sh)). Setup installs the packages it needs: cmake, ninja, sdl3, ffmpeg, llvm@22, glslang, spirv-cross, sevenzip, upx and libusb.
- Disk space: about 2.6 GB (`build/` 1.7 GB, `third_party/SwARc` 0.9 GB). The game folder itself is linked, not copied.
- An internet connection during setup. It clones SwARc from GitHub and downloads Microsoft's Visual C++ 2005 SP1 redistributable, whose runtime DLLs the game was built against.

## The easy way: GH3 Builder (experimental)
Each [release](https://github.com/segovia-no/GH3-macOS-Recomp/releases) has **GH3 Builder**, an app that builds the game on your Mac without Homebrew or the terminal. You need macOS 26 or later and Apple's Xcode Command Line Tools; the builder offers to install the tools if they are missing.
1. Download `GH3-Builder-<version>-macOS26-arm64.zip` and unzip it.
2. Open **GH3 Builder**. The first time, macOS stops it because it is not notarized: open System Settings → Privacy & Security, click **Open Anyway** next to "GH3 Builder", and confirm.
3. Choose your Guitar Hero III folder and where to put the app (default: your Applications folder), then click **Build**. The first build takes about 15 minutes.
4. Click **Play**.

The builder holds nothing from the game. Its Licenses button lists the open-source components inside it. It keeps its work files in `~/Library/Caches/GH3-macOS-Recomp`, so building again after an update is quick.

## Building the app from source
```sh
git clone https://github.com/segovia-no/GH3-macOS-Recomp.git
cd GH3-macOS-Recomp
./setup.sh --game "/path/to/Guitar Hero III"
```
You can also put the game folder next to `setup.sh`, named `Guitar Hero III`, and run `./setup.sh` with no options.

Setup runs these steps (details in [building.md](../dev/building.md)):
1. Checks the tools and installs missing Homebrew packages.
2. Checks out [SwARc](https://github.com/JTM-rootstorm/SwARc) (this project's [fork](https://github.com/segovia-no/SwARc/tree/gh3)) at the tested commit in `third_party/SwARc` and builds the lifter.
3. Copies `GH3.exe` and checks its hash. Unpacks `fmodex.dll`. Downloads and extracts the CRT DLLs. Makes `build/gamedir`.
4. Reads the executable's and the DLLs' imports and exports; the function lists come with the repository (`manifests/ghidra`).
5. Lifts them to C++ in `build/generated`.
6. Compiles the game. This is the long step: about 150 large generated files.

7. Packages `build/Guitar Hero III.app`.

The whole first run takes about 18 minutes on an M3 Pro (11 cores), Homebrew packages already installed.

When it finishes:
```sh
open "build/Guitar Hero III.app"
```
You can move the app anywhere, for example to Applications. It reads the game through links in `~/Library/Application Support/gh3/game` that point to your game folder, so keep the game folder where it was. Songs you add to it show up in the app.

### A self-contained app
```sh
./setup.sh --game "/path/to/Guitar Hero III" --embed-game
```
This copies the game into the app (`Contents/Resources/game`). On the same APFS volume the copy is a clone, so it takes no extra space until either side changes. The app then works without the game folder or this repository. Songs added to the original folder later won't appear in it.

The app is ad hoc signed and built on your Mac, so Gatekeeper doesn't ask about it. It is for your Mac only: don't share it, because it contains code made from the game.

## Updating
```sh
git pull
./setup.sh --game "/path/to/Guitar Hero III"
```
Setup reuses what is still valid: the SwARc checkout (moved to a newer tested commit when a pull changes it) and the downloads. It re-lifts and rebuilds what changed.

## Uninstalling
Delete the app. Then, if you want to remove everything it made:
- `build/` and `third_party/` in this repository;
- `~/Library/Application Support/gh3`: settings, saves, crash reports and the game links. Keep it if you want your saves.
- `~/Library/Logs/Guitar Hero III.log`.

Your game folder is never modified by setup.
