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

## Shipping it (0.1.0)
GH3 Builder is published with each release, as an experimental download for macOS 26 and later. Of the problems the spike left:
1. **Minimum macOS: accepted.** Every kit binary requires macOS 26, because Homebrew's bottles and the CMake build target the building Mac's OS. The apps declare it (`LSMinimumSystemVersion` 26.0). Supporting older versions would mean building SDL3, libusb, glslang and SPIRV-Tools from source for an older target.
2. **FFmpeg: now LGPL.** `packaging/builder/deps.sh` builds FFmpeg 9.0.2 (Homebrew's version, so the same library names and ABI) with only what SwARc uses: the Bink demuxer, the Bink video/audio, MP3 and MJPEG decoders, swscale. Configure: `--disable-everything --disable-autodetect --disable-network`, no `--enable-gpl`. `make_kit.sh` builds SwARc's runtime and `src/` again for the kit (`build/builder/cmake`), linked against it. Swapping the libraries after linking is not enough: FFmpeg 9's libavformat re-exports some libavcodec/libavutil symbols, and which ones depends on the configuration. Libraries linked against Homebrew's build bound `av_new_packet` to libavformat, and the game stopped at launch ("Symbol not found"). `kit_prune.py` drops what only Homebrew's FFmpeg needed: x264, x265, SVT-AV1, vpx, dav1d, opus, lame, mpg123, OpenSSL, xz, swresample. That's 12 libraries, and the kit went from 57 to 26 MB. The kit build checks that the FFmpeg libraries are byte-identical to the LGPL build. It then signs and runs a stand-in that loads every library the game links, which proves all symbols resolve.
3. **Signing: approved once.** The builder is ad hoc signed, so a downloaded copy has to be allowed once: System Settings → Privacy & Security → Open Anyway. All of a downloaded app's files carry the quarantine flag. So that Gatekeeper doesn't stop each of the kit's tools, the builder runs a copy of its kit in `~/Library/Caches/GH3-macOS-Recomp/kit` with the flag removed (`ditto`, then `xattr -dr com.apple.quarantine`). A Developer ID and notarization would remove the Open Anyway step.
4. **Notices: done.** The kit has `licenses/`: `NOTICES.md` (component, version, license, where it is used) and each component's license text. Both the builder and every game app it builds carry it, and the builder has a Licenses button. The source of the LGPL and GPL components (FFmpeg, libusb, UPX, 7-Zip), exactly the shipped versions, is published next to the builder as `GH3-Builder-<version>-sources.tar`, together with FFmpeg's configure line. `deps.sh` pins those sources by SHA-256 and refuses to run if Homebrew's versions differ from the pins.
5. **No paths from the build machine.** Debug info in the prebuilt objects and libraries, and FFmpeg's embedded configure line, named the developer's home folder. The objects are stripped (`strip -S`), the libraries lose their debug maps, and FFmpeg is configured with `--prefix=/ffmpeg`. `make_kit.sh` fails if the kit still contains `$HOME`.

Still open:
- **Duplicated logic.** `build_game.sh` repeats `prepare_inputs.sh`, `symbols.sh`, `lift.sh` and `make_app.sh`. If the builder becomes the main route, `setup.sh` could build the kit and run `build_game.sh`.
- **Tied to one `GH3.exe`, SwARc commit and set of manifests.** A new release of the project means a new builder.
