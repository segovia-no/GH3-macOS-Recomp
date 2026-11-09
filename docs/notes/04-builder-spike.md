# Builder app spike

**Question:** can players build the game with one app, without Homebrew, LLVM or a terminal? The game itself can't be shared (it is made from `GH3.exe`), but a builder holding none of the game can be.

**Answer:** yes. The only thing the player's Mac needs is Apple's **Xcode Command Line Tools**, which macOS installs from a system dialog. Built from the kit, the game is identical to the developer build: same lifted C++, and it boots, plays the intro movies with audio and quits.

## Why Homebrew's LLVM was never the compiler
The developer build already compiles with **Apple clang** (`/usr/bin/c++`, from the Command Line Tools). Homebrew's `llvm@22` (1.5 GB) supplied only two things:
- `libLLVMDemangle.a` (400 KB), linked into SwARc's runtime for `UnDecorateSymbolName`. The kit ships the runtime prebuilt, so the player's Mac never links it.
- `llvm-undname`, which `pe_symbols.py` runs to demangle export names. The lifter only uses those names in comments. `packaging/builder/undname.cpp` is a 20-line stand-in built against the static demangler. On all four modules its output is byte-identical to `llvm-undname`'s.

A compiler of our own (upstream clang or zig, in the app) would remove even the Command Line Tools. It isn't worth it: the macOS SDK can't be redistributed, and the prebuilt runtime shares C++ types with the game, so the game must use the system's libc++. Apple's tools are the supported way to get both.

## How it works
`packaging/builder/make_kit.sh` assembles `build/builder/kit` (57 MB) from a finished developer build. Nothing in it comes from the game:

| Kit path | What |
|---|---|
| `bin/` | SwARc's `recomp_lift`, `llvm-undname` (the stand-in), `upx`, `7zz` (both static) |
| `Frameworks/` | SwARc's runtime and its libraries (SDL3, ffmpeg, libusb, glslang, ...), relinked to `@rpath` |
| `include/` | SwARc's 35 headers: all the lifted code includes |
| `native/` | `src/*.o` and SwARc's `lifted_table.cpp.o`, prebuilt |
| `manifests/` | `lifter.manifest`, `fmodex.manifest`, `ghidra/` |
| `cxxflags`, `link` | the lifted code's compile flags and the game's libraries, taken from the CMake build (`ninja -t commands`, `kit_flags.py`) |
| `config.sh` | the expected hashes and the VC++ URL (from `scripts/setup/common.sh`), the version |
| `build_game.sh` | the build that runs on the player's Mac |

`kit/build_game.sh <game folder> <output folder> [--embed-game]` runs with only `/usr/bin:/bin:/usr/sbin:/sbin` on `PATH`. It works in `~/Library/Caches/GH3-macOS-Recomp`:
1. Checks for clang (`xcrun`) and the SDK.
2. Checks `GH3.exe` and unpacks `fmodex.dll`. Downloads the VC++ 2005 runtime and extracts the CRT.
3. Reads imports and exports (`pe_symbols.py`) and copies in the Ghidra tables.
4. Lifts the code; only changed files are replaced.
5. Compiles the 147 lifted files with Apple clang, one job per core (`xargs -P`). No CMake or Ninja.
6. Links against the kit's libraries, builds the app (Frameworks, icon, Info.plist, game folder links), ad hoc signs it.

It prints `@@step n/6 title`, `@@progress done/total` and `@@done <app>` for the front end.

`packaging/builder/make_builder.sh` makes `build/builder/GH3 Builder.app` (58 MB). It's a SwiftUI front end (`app/GH3Builder.swift`, one file, compiled with the Command Line Tools' `swiftc`, macOS 13+) with the kit in `Contents/Resources/kit`. In it, the player:
- installs the Command Line Tools if missing (`xcode-select --install`; the app checks again every 5 s);
- picks the game folder and where the app goes (default `~/Applications`);
- clicks Build.

It shows the step, a progress bar for the compile and the log. It keeps the Mac awake while building, Cancel stops the whole process tree, and when it's done it offers "Play".

## Measurements (M3 Pro, 11 cores)
| | Time |
|---|---|
| `./setup.sh` from scratch (Homebrew, CMake, SwARc built from source) | 17m52s |
| Kit build, first run: steps 1–4 / step 5 (compile) / total | 60 s / ~14 min / 15m13s |
| Kit build, rerun (nothing changed) | 61 s |

## Open problems before it can be shared
1. **Minimum macOS.** Every kit binary requires macOS 26 (`vtool -show-build`: `minos 26.0`). Homebrew's bottles and the CMake build both target the building Mac's OS. A shareable kit needs its libraries built for macOS 13 (`MACOSX_DEPLOYMENT_TARGET=13`, `CMAKE_OSX_DEPLOYMENT_TARGET=13`): SDL3, libusb, ffmpeg, glslang and SPIRV-Tools from source, in a CI job.
2. **ffmpeg is GPL as Homebrew builds it** (`--enable-gpl`, with x264/x265/SVT-AV1/vpx encoders that the game never uses). An LGPL build with only the decoders needed (Bink, MP3, MJPEG) would avoid the GPL obligations and shrink the kit a lot: 20 of the 38 libraries come from ffmpeg's dependencies, OpenSSL included.
3. **Signing.** A downloaded, ad hoc signed app is stopped by Gatekeeper ("cannot be opened"), and the quarantine flag carries over to the kit's binaries. Real distribution needs a Developer ID and notarization (an Apple Developer account). Until then, players would have to use System Settings → Privacy & Security → Open Anyway. The game app built on the player's Mac isn't quarantined, so it isn't affected.
4. **License notices.** The kit needs a NOTICES file covering SwARc (MIT), SDL3 (zlib), libusb and ffmpeg (LGPL), UPX (GPL with exception), 7-Zip (LGPL, unRAR restriction), the LLVM demangler (Apache 2.0 with LLVM exception) and glslang/SPIRV-Tools.
5. **Duplicated logic.** `build_game.sh` repeats `prepare_inputs.sh`, `symbols.sh`, `lift.sh` and `make_app.sh`. If the builder becomes the main route, `setup.sh` could build the kit, then run `build_game.sh`, so both paths share one build.
6. **The kit is tied to one `GH3.exe`, SwARc commit and set of manifests.** A new release of the project means a new builder, which is the same rule as today.
