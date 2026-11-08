# Building from source

`./setup.sh` runs the whole pipeline (see [install.md](../guides/install.md)). This page describes each step, so you can run, redo or change them one at a time.

## Paths
All the setup scripts share `scripts/setup/common.sh`:

| Variable | Default | What |
|---|---|---|
| `GH3_GAME_DIR` | `./Guitar Hero III` | your Guitar Hero III install (read only) |
| `GH3_BUILD_DIR` | `./build` | everything generated (gitignored) |
| `SWARC_DIR` | `./third_party/SwARc` | the patched SwARc checkout (gitignored) |

Layout of `build/`:

| Path | Made by | What |
|---|---|---|
| `input/` | `prepare_inputs.sh` | `GH3.exe`, the unpacked `fmodex.dll`, `msvcr80.dll`, `msvcp80.dll` |
| `gamedir/` | `prepare_inputs.sh` | the game folder the build runs: links to the install, plus the runtime's own copies of the files above and an empty `PLUGINS/` |
| `symbols/<module>/` | `analyze.sh` | `pe_info.txt`, `imports.tsv`, `exports.tsv` (SwARc's `pe_symbols.py`); `functions.tsv`, `jumptables.tsv` (Ghidra) |
| `ghidra/` | `analyze.sh` | the Ghidra projects (for looking around, or for `scripts/dev/ghidra/*.java`) |
| `generated/` | `lift.sh` | the lifted C++ (about 150 files, 290 MB) |
| `cmake/` | `build.sh` | the CMake build; the game is `cmake/gh3` |
| `Guitar Hero III.app` | `packaging/macos/make_app.sh` | the app bundle |
| `logs/` | all | one log per step |

## The steps
1. **`scripts/setup/fetch_swarc.sh`**: clones [SwARc](https://github.com/JTM-rootstorm/SwARc) at the tested commit (`SWARC_COMMIT` in `common.sh`) and applies `patches/swarc-gh3.patch` with `git apply --index`. Then it builds only the lifter: `cmake --preset release && cmake --build --preset release --target recomp_lift`.
2. **`scripts/setup/prepare_inputs.sh`**:
   - checks `GH3.exe`'s SHA-256;
   - UPX-unpacks `fmodex.dll` (`upx -d`, checked against a known hash);
   - downloads Microsoft's VC++ 2005 SP1 redistributable and extracts `msvcr80.dll`/`msvcp80.dll` 8.0.50727.6195 from it with `7zz` (exe → `vcredist.msi` → the CRT merge module), checking all hashes;
   - makes `build/gamedir`.
3. **`scripts/setup/analyze.sh`**: for each module, SwARc's `tools/pe_symbols.py`, then Ghidra headless with SwARc's `ExportFunctions.java`/`ExportJumpTables.java`. A module is skipped if its `functions.tsv` exists.
4. **`scripts/setup/lift.sh`**: `recomp_lift` on GH3.exe (with `manifests/lifter.manifest` and `--no-x87-doubles`). The three DLLs are lifted as modules, FMOD with `manifests/fmodex.manifest`. Output goes to `build/generated`.
5. **`scripts/setup/build.sh`**: configures `CMakeLists.txt` into `build/cmake` (Ninja, RelWithDebInfo) and builds the `gh3` target. That builds SwARc's runtime libraries too.
6. **`packaging/macos/make_app.sh [--embed-game]`**: rebuilds `gh3` if needed. Then it makes the app bundle:
   - copies the libraries into `Contents/Frameworks` and relinks them (`bundle_dylibs.py`);
   - adds the icon from `GH3.exe` (`exe_icon.py`);
   - writes the game links in `~/Library/Application Support/gh3/game`;
   - signs it ad hoc.

After changing code in `src/`, run `cmake --build build/cmake --target gh3` (or `make_app.sh`). After changing a manifest, re-lift first.

## Running a development build
| Command | What |
|---|---|
| `scripts/dev/play.sh` | runs `build/cmake/gh3` on `build/gamedir` as a minimal app (`build/dev/GH3.app`), so it gets focus and keyboard. The log is `build/logs/play.log`, also shown in the terminal. |
| `scripts/dev/boot.sh [secs]` | boots unattended (`GH3_BACKGROUND=1`: no window focus, no input, no pads) for at most `secs` seconds, then prints the end of `build/logs/boot.log`. Never leaves the game running. |

Switches for `play.sh` (environment variables, passed through to the game):

| Variable | Effect |
|---|---|
| `GH3_RESOLUTION=WxH`, `GH3_FULLSCREEN=window\|desktop\|exclusive` | window size and mode |
| `GH3_FPS_REPORT=1` | frame rate in the log once a second |
| `GH3_PROFILE=1` | the frame rate, plus a 5 s CPU sample of the game (`sample`) every 15 s into `build/prof/` |
| `GH3_TRACE=1`, `GH3_TRACE_FILTER=<dll>` | log every import call (optionally only one DLL's) |
| `GH3_AUDIO_DUMP=<file.wav>` | record what the mixer plays (float32 stereo, 48 kHz) |
| `GH3_VERIFY_SKIN=1` | run the native skinning (`src/skinning.cpp`) and the lifted original on every call, and report any difference |
| `GH3_X360RX_TRACE=1` | log every packet from an Xbox 360 wireless receiver |

## Changing SwARc
Work in `third_party/SwARc`; the patch is applied there with `--index`. To save your changes:
```sh
cd third_party/SwARc
git add -N <new files>
git diff HEAD > ../../patches/swarc-gh3.patch
```
After lifter changes, re-lift and diff `build/generated` before and after: lifter output should not change unintentionally. SwARc's own rules are in its `CLAUDE.md` and `ARCHITECTURE.md`; nothing game-specific goes into SwARc.

## Regenerating the manifests
`manifests/lifter.manifest` is generated, so don't edit it. It merges:
- `manifests/overrides.manifest`: hand-written `entry`, `replace` and `noentry` lines;
- the QB script-function names (`docs/data/cfuncs.tsv`);
- GH3+'s symbols (`docs/data/gh3plus_symbols.tsv`);
- `manifests/noentry.manifest`.

```sh
python3 -I scripts/dev/gen_manifest.py --exe build/input/GH3.exe \
  --overrides manifests/overrides.manifest \
  --cfuncs docs/data/cfuncs.tsv --gh3plus docs/data/gh3plus_symbols.tsv \
  --noentry manifests/noentry.manifest --out manifests/lifter.manifest
```

`manifests/noentry.manifest` lists the lifter's weak function entries that land inside a Ghidra basic block: data that only looks like code pointers. To redo it, export the blocks, lift, then run the finder:
```sh
JAVA_HOME=$(brew --prefix)/opt/openjdk@25 $(brew --prefix)/opt/ghidra/libexec/support/analyzeHeadless \
  build/ghidra gh3 -process GH3.exe -noanalysis -readOnly -scriptPath scripts/dev/ghidra \
  -postScript ExportBlockStarts.java "$PWD/build/symbols/gh3/blocks.tsv"
python3 -I scripts/dev/find_false_entries.py --generated build/generated \
  --functions build/symbols/gh3/functions.tsv --blocks build/symbols/gh3/blocks.tsv \
  --out manifests/noentry.manifest
```

Other tools in `scripts/dev/`:
- `import_coverage.py`: which of a module's imports SwARc and `src/` implement.
- `extract_cfuncs.py`, `extract_gh3plus_symbols.py`: regenerate `docs/data/` from `GH3.exe` and the reference clones in `ref/`.
- `ghidra/DecompileAt.java`: decompiles functions by address from the Ghidra project.
