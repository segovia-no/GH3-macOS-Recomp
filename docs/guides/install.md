# Install

The app is built on your Mac from your own copy of the game. There is no download with the game in it.

## Requirements
- A Mac with **Apple Silicon** (M1 or later). It was developed on macOS 26; the app is marked for macOS 13 and later, but older versions are untested.
- **Your own Guitar Hero III: Legends of Rock installation for PC** (version 1.3.1): the folder with `GH3.exe`, `DATA/`, `AWL.dll` and `fmodex.dll`. We recommend starting from a [BetterGH3](https://github.com/lunalawl/BetterGH3) installation, which is the one this port was developed and tested with. The build is made for one specific `GH3.exe` (SHA-256 `4322a71d…5e804`, see [docs/README.md](../README.md)), and setup stops if yours differs.
- The **Xcode Command Line Tools**: `xcode-select --install`.
- **Homebrew** ([brew.sh](https://brew.sh)). Setup installs the packages it needs: cmake, ninja, sdl3, ffmpeg, llvm@22, glslang, spirv-cross, ghidra (with openjdk@25), sevenzip, upx and libusb.
- Disk space: about 2.6 GB (`build/` 1.7 GB, `third_party/SwARc` 0.9 GB). The game folder itself is linked, not copied.
- An internet connection during setup. It clones SwARc from GitHub and downloads Microsoft's Visual C++ 2005 SP1 redistributable, whose runtime DLLs the game was built against.

## Building the app
```sh
git clone https://github.com/segovia-no/GH3-macOS-Recomp.git
cd GH3-macOS-Recomp
./setup.sh --game "/path/to/Guitar Hero III"
```
You can also put the game folder next to `setup.sh`, named `Guitar Hero III`, and run `./setup.sh` with no options.

Setup runs these steps (details in [building.md](../dev/building.md)):
1. Checks the tools and installs missing Homebrew packages.
2. Checks out [SwARc](https://github.com/JTM-rootstorm/SwARc) at the tested commit in `third_party/SwARc`, applies this project's patch and builds the lifter.
3. Copies `GH3.exe` and checks its hash. Unpacks `fmodex.dll`. Downloads and extracts the CRT DLLs. Makes `build/gamedir`.
4. Analyses the executable and the DLLs with Ghidra (a few minutes).
5. Lifts them to C++ in `build/generated`.
6. Compiles the game. This is the long step: about 150 large generated files.

The whole first run took about 21 minutes on an M3 Pro (11 cores), Homebrew packages already installed.
7. Packages `build/Guitar Hero III.app`.

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
Setup reuses what is still valid: the SwARc checkout, the downloads and the Ghidra analysis. It re-lifts and rebuilds what changed. If a pull changes `patches/swarc-gh3.patch`, delete `third_party/SwARc` first so it is checked out again.

## Uninstalling
Delete the app. Then, if you want to remove everything it made:
- `build/` and `third_party/` in this repository;
- `~/Library/Application Support/gh3`: settings, saves, crash reports and the game links. Keep it if you want your saves.
- `~/Library/Logs/Guitar Hero III.log`.

Your game folder is never modified by setup.
