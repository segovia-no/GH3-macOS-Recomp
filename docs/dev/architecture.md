# Architecture

## The idea
`GH3.exe` is a 32-bit x86 Windows program. Instead of emulating it, the port translates its machine code ahead of time into C++. Every x86 function becomes a C++ function that works on a model of the CPU state (registers, flags, the x87 FPU and SSE, both exact) and on the game's memory. That C++ is compiled for arm64 with clang. At run time there is no interpreter and no JIT. Code that was not lifted is a fatal error naming its address, never a slow fallback.

The Windows side is reimplemented, not emulated. Each DLL function the game imports is a native handler (HLE). Kernel32, user32, Direct3D 9, DirectSound, DirectInput, XInput, Bink and the rest run on SDL3 and Metal. Both the lifter and this runtime come from [SwARc](https://github.com/JTM-rootstorm/SwARc). This repository is the game project on top of it; our changes to SwARc are on the `gh3` branch of [its fork](https://github.com/segovia-no/SwARc/tree/gh3).

```
your GH3.exe ──┐
fmodex.dll ────┼─ manifests/ghidra (functions, jump tables) ─┐
CRT DLLs ──────┘                                            ├─ recomp_lift ─► build/generated/*.cpp ─┐
manifests/ (names, replacements, noentry) ──────────────────┘                                       │
src/ (native code for this game) ──────────────────────────────────────────────────────────┼─ clang ─► gh3 ─► Guitar Hero III.app
SwARc runtime (Win32/D3D9/... on SDL3 + Metal, the gh3 branch) ───────────────────────────┘
```

## What is lifted
- **GH3.exe**: the game, including its second executable section `HATRED` and the GH3+ plugin loader call. Its x87 float code is lifted with `--no-x87-doubles`. The game runs at 24-bit precision (D3D9 creates its device without `FPU_PRESERVE`), so the host-double path never applied; dropping it lets clang optimise the huge Havok solver functions.
- **msvcr80.dll / msvcp80.dll**: Microsoft's C and C++ runtime the game was built against. Lifting the real DLLs gives the exact CRT behaviour (heap, stdio, locale, exceptions) for free. They run on SwARc's kernel32.
- **fmodex.dll**: FMOD Ex, the game's audio engine, lifted with its CPU feature probes replaced (`src/fmod_cpu.cpp`), so it takes its plain C mixing paths. It outputs through SwARc's DirectSound, which mixes to CoreAudio through SDL.

## What is native (`src/`)
| File | What |
|---|---|
| `main.cpp` | the game configuration for SwARc (id, guest path, lifted DLLs); finds the game folder and the log when run as an app; sets a small audio buffer so the music stays in sync with the notes |
| `awl.cpp` | Aspyr's `AWL.dll` (the PC port's OS layer: config store, paths, window activation), reimplemented. Settings go to `AspyrConfig.ini`. |
| `stubs.cpp` | `mac3r.dll` (Massive in-game ads, a long-gone service) and `IntelLaptopGaming.dll`, as the "not available" case the game already handles |
| `plugins.cpp` | replaces the GH3+ plugin loader (its stub lies past the end of `.text`); native ports of plugins would go here |
| `fmod_cpu.cpp` | FMOD's CPU probes: report no MMX/SSE/3DNow!, which the lifter does not implement for FMOD's hand-written mixers |
| `skinning.cpp` | the CPU skinning of character meshes (0x61C590), rewritten natively: bit-identical to the lifted code (checked with `GH3_VERIFY_SKIN=1` over 131,072 calls) and much faster. That made gameplay go from about 60–100 fps to 120. |

`manifests/overrides.manifest` wires these in. `replace <va> <name>` swaps a lifted function for native code; the lifted body stays available as `f_<VA>_lifted`, the reference for checking a replacement.

## SwARc changes (the `gh3` branch)
Generic changes, nothing specific to GH3, as commits on [segovia-no/SwARc](https://github.com/segovia-no/SwARc/tree/gh3)'s `gh3` branch, on top of upstream SwARc; `SWARC_COMMIT` in `scripts/setup/common.sh` pins the tested one:
- **Lifter:**
  - multiple executable sections;
  - the `noentry` manifest directive;
  - partial jump tables merged, and jump-table bounds held in a register;
  - RCPPS/RCPSS and MOVNT* stores;
  - `--no-x87-doubles` per module.
- **Process:**
  - lifted DLLs that are imported statically (bound into the importer's IAT, DllMain before the entry point);
  - PE sections mapped up to their aligned virtual size;
  - a padded main stack top.
- **Win32:**
  - kernel32 (Interlocked*, overlapped I/O, ...), advapi32 crypto, user32 keyboard functions, ws2_32 TCP, iphlpapi;
  - XInput, plus the **Xbox 360 wireless receiver over libusb** (`xbox360_receiver.cpp`);
  - DirectSound by name and device enumeration;
  - Bink 1.9 frame buffers;
  - Direct3D 9 volume textures and occlusion queries;
  - D3DX texture loaders (DDS volume/cube, PNG, JPEG, DXT encode/decode).
- **Performance:**
  - exact SSE host fast paths (`sse_fast.h`): used only where host floating point provably gives the same bits as SoftFloat, otherwise the exact path, with fuzz tests;
  - deeper GPU pipelining.

The [porting log](../notes/03-porting-log.md) has the story and the measurements behind each change.

## Repository layout
```
setup.sh                 the whole build, from your game folder to the app
CMakeLists.txt           the game build (SwARc as a subdirectory, lifted code, src/)
src/                     native code for this game (above)
manifests/               lifter input: overrides (hand-written), noentry and lifter (generated), fmodex,
                         ghidra/ (each module's functions and jump tables, from Ghidra)
scripts/setup/           the pipeline steps setup.sh runs
scripts/dev/             running and debugging (play.sh, boot.sh), manifest generators, Ghidra (ghidra_analyze.sh and scripts)
packaging/macos/         make_app.sh and its helpers
docs/                    guides, developer docs, technical notes, extracted tables
third_party/SwARc/       (gitignored) the SwARc checkout
build/                   (gitignored) everything generated from your copy of the game
```
