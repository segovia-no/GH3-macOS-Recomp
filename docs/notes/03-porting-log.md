# Porting log — GH3.exe on SwARc, macOS arm64

The development log of the port, in the order things happened: what was tried, what was measured, and why each decision was made. Started 2026-11-08. **Observed** = verified locally; **Inferred** = reasoning, not yet tested.

The commands here are as run at the time. Paths have been updated to the current layout (`build/`, `third_party/SwARc`, `scripts/`), but some steps were later folded into `./setup.sh`. For how to build today, see [docs/dev/building.md](../dev/building.md).

## Setup (observed, reproducible)

Host: macOS 26 (Darwin 25.6), Apple Silicon, Apple clang 21.

```sh
brew install cmake ninja sdl3 ffmpeg llvm@22 glslang spirv-cross ghidra   # ghidra pulls openjdk@25
git clone https://github.com/JTM-rootstorm/SwARc third_party/SwARc               # tested at 240ef13
cd third_party/SwARc
git checkout -b gh3-multi-code-sections 240ef13
git apply ../../patches/swarc-gh3.patch   # our SwARc changes (code sections, noentry, kernel32)
cmake --preset release -DRECOMP_LLVM_ROOT=/opt/homebrew/opt/llvm@22
cmake --build --preset release          # 489/489, clean
ctest --test-dir out/build/release -j8  # 17/17 pass
```

- Ghidra 12.2 (brew) needs **JDK 25**, not 21: `JAVA_HOME=/opt/homebrew/opt/openjdk@25`.
- Lifter: `out/build/release/tools/lifter_x86/recomp_lift`.
- Lifter inputs (`--symbols dir`): `functions.tsv` + `jumptables.tsv` (Ghidra scripts in `scripts/dev/ghidra/`), `exports.tsv` (`tools/pe_symbols.py`).

```sh
# PE facts / imports / exports
PATH=/opt/homebrew/opt/llvm@22/bin:$PATH python3 -I third_party/SwARc/tools/pe_symbols.py build/input/GH3.exe --out work/symbols
# Ghidra full analysis + exports (build/ is gitignored)
JAVA_HOME=/opt/homebrew/opt/openjdk@25 /opt/homebrew/opt/ghidra/libexec/support/analyzeHeadless \
  build/ghidra GH3 -import build/input/GH3.exe -overwrite -scriptPath third_party/SwARc/tools/ghidra \
  -postScript ExportFunctions.java $PWD/build/symbols/gh3/functions.tsv \
  -postScript ExportJumpTables.java $PWD/build/symbols/gh3/jumptables.tsv
```

## GH3.exe facts relevant to SwARc (observed)

- Image base 0x400000, **no relocations** (fixed base) — fine, SwARc maps the 4 GiB guest arena.
- Entry 0x68f03c. Only 2 exports.
- Instruction mix (objdump, 1.72M insns): x87 185k (11%), SSE float 108k, SSE2 double 507, indirect calls 15k, `fs:` refs 5.2k (SEH), `fldcw` 278.
- **D3D9 device creation** at 0x57bb86: `IDirect3D9::CreateDevice(adapter 0, devtype edi, hwnd esi, BehaviorFlags=0x40 (HARDWARE_VERTEXPROCESSING), pp=0xc5b900, ppDevice=0xc5c7a8)`.
  - **No `D3DCREATE_FPU_PRESERVE`** → real D3D9 drops the render thread's x87 to PC=24. SwARc's d3d9 HLE reproduces this (`platforms/win32/src/win32/d3d9.cpp:570`).
  - Consequence (inferred): the PC=53 "host doubles" x87 runs don't apply on that thread; the **`run::Fast24`** integer fast path does (ARCHITECTURE.md, "x87: full 80-bit model"). Measure before optimizing.
  - BetterGH3's uncapped-FPS patch at 0x57BB79 rewrites the `mov [0xc5b934], edi` (PresentationInterval) in this same block.
- GH3+ loader stub at 0x897d40 (`LoadLibraryA("PLUGINS\core.dll")`), called from 0x4016de. In a recomp build this call becomes a native plugin-init hook (or is skipped).

## Import coverage vs SwARc HLE (observed)

`python3 -I scripts/dev/import_coverage.py build/symbols/gh3/imports.tsv third_party/SwARc/platforms/win32/src --out docs/data/import_coverage.tsv`

| DLL | imports | HLE'd | missing in existing module | no module |
|---|---:|---:|---:|---:|
| msvcr80 | 107 | 0 | 0 | 107 |
| kernel32 | 68 | 61 | 7 | |
| fmodex | 53 | 0 | 0 | 53 |
| msvcp80 | 46 | 0 | 0 | 46 |
| ws2_32 | 26 | 0 | 26 (ordinal imports — module exists, check ordinal mapping) | |
| binkw32 | 21 | 12 | 9 | |
| awl (Aspyr) | 20 | | | 20 |
| user32 | 13 | 9 | 4 | |
| mac3r (MassiveAd) | 9 | | | 9 |
| d3dx9_35 | 8 | 2 | 6 | |
| intellaptopgaming | 5 | | | 5 |
| others (ole32, oleaut32, winmm, d3d9, dinput8, gdi32, xinput, advapi32, shell32, iphlpapi) | 24 | 15 | 5 (xinput #5, CryptAcquireContextA/GenRandom/ReleaseContext, SHFileOperationA) | 1 (iphlpapi) |
| **Total** | **397** | **99 (25%)** | **57** | **241** |

Missing-in-module list: kernel32 CancelIo, GetOverlappedResult, GetFileAttributesExA, GetExitCodeThread, InterlockedExchangeAdd, SignalObjectAndWait, InterlockedCompareExchange; d3dx9 Vec3TransformCoord, SaveTextureToFileInMemory, CreateVolumeTextureFromFileInMemoryEx, MatrixLookAtRH, MatrixOrthoRH, CreateCubeTextureFromFileInMemoryEx; Bink SetMemory, OpenWaveOut, GetFrameBuffersInfo, GetError, SetIOSize, SetFrameRate, ControlBackgroundIO, ShouldSkip, RegisterFrameBuffers; user32 CharLowerBuffA, SetWindowTextW, GetKeyboardState, ToAscii.

### Strategy per gap (inferred)

- **MSVCR80 / MSVCP80 (153)**: SwARc's existing 32-bit games link the CRT statically, so there's no msvcr80 HLE. Options: (a) lift the real `msvcr80.dll`/`msvcp80.dll` as `--module`s (VC++ 2005 SP1 redist, user-supplied — the bundled `VC_redist.x86.exe` is 2015-2022, wrong version); (b) HLE them. (a) is less code; it rides on the kernel32 HLE.
- **fmodex.dll (53)**: shipped, **UPX-packed** → `upx -d` a copy, then lift as a module (FMOD's own mixer runs as lifted code; output via a waveOut/DSound path SwARc HLEs) or HLE FMOD Ex on SDL audio + an FSB decoder. Lift first, measure.
- **AWL.dll (20)**: shipped; small (paths, config, window). HLE natively (simplest) or lift.
- **mac3r (9), IntelLaptopGaming (5), iphlpapi (1)**: trivial stubs in the game project (SwARc rule: explicit handler per import, no catch-alls).
- **ws2_32**: by-ordinal imports; verify SwARc's ordinal table, else add.
- **d3d9 / d3dx9**: d3d9 is SwARc's in-progress work; GH3's d3dx9 surface is small (8).

## Lift results (observed)

Ghidra 12.2 headless (about 10 min on this Mac): 20,049 functions (1,012 multi-chunk, 1,907 thunks; 1,624 in HATRED), 413 resolved and 576 unresolved computed jumps.

| Run | Functions | Instructions | Branches out of code | Unimplemented sites | Files | Time |
|---|---:|---:|---:|---:|---:|---:|
| Upstream SwARc (only `.text`) | 32,235 | 1,999,318 | **1,621** (into HATRED) | 471 | 163 | 155 s |
| + multi-code-section patch | 34,196 | 2,077,041 | 9 | 474 | 170 | 159 s |

- **HATRED blocker and fix.** SwARc's lifter (`Module::text_lo/hi`) and runtime (`process.cpp TextOf`) assume one `.text`. GH3's `.text` tail-jumps into HATRED (relocated bodies; 1,568 thunks per `docs/notes/02-decomp-crossref.md`). Patch on branch `gh3-multi-code-sections` in `third_party/SwARc` (39 lines added, 5 removed): every `IMAGE_SCN_MEM_EXECUTE` section becomes a code range in both the lifter (`Module::extra_text`, `HasCode`, `CodeEnd`) and the runtime (`ExtraCodeOf` → `Process::code`; the dispatcher already handled several ranges). Worth upstreaming in generic terms ("code a protector's unwrapper moved out of .text").
- **Unimplemented sites** are mostly data decoded as code from weak data-pointer entries (`arpl` 60, `les` 52, `in`/`out` 69, `iretd` 16, `bound` 16, BCD ops). Candidates for real code to check: `movntps` 11, `enter` 27, `punpckhdq` 4, `cvtpi2ps` 2, `fisttp` 3, `psllq`, `psubusw`. Triage only when the runtime reaches one: by design, reaching unlifted code is a fatal error that names the VA.
- Output: 371 MB of C++ in `build/generated/` (gitignored, regenerable).

## Naming pipeline (observed)

- `scripts/dev/extract_cfuncs.py` → `docs/data/cfuncs.tsv` (QB C-function table at 0x9551B8, 1,170 names). I spot-checked the first entries against the bytes.
- `scripts/dev/extract_gh3plus_symbols.py` → `docs/data/gh3plus_symbols.tsv` (GH3+, BetterGH3, gh3ml, gh3.CT).
- `scripts/dev/gen_manifest.py` merges `manifests/overrides.manifest` (hand-written) with those into `manifests/lifter.manifest`: 1,257 `entry` names, plus `__body` names for the 18 named thunks into HATRED.
- Names reach the generated C++ only as comments, but `entry` lines also make the table-only CFuncs real lifted functions.

## Game project (observed)

`CMakeLists.txt` + `src/main.cpp`: SwARc via `add_subdirectory`, `recomp_add_lifted(gh3_lifted build/generated)`, links recomp_win32/d3d9/dinput8/xinput/bink. `GameConfig` id `gh3`, guest dir `C:\Program Files\Aspyr\Guitar Hero III`.

## Status log

- [x] Build SwARc on macOS arm64, tests green.
- [x] pe_symbols on GH3.exe.
- [x] Import coverage.
- [x] Ghidra function/jump-table export.
- [x] First `recomp_lift` run; HATRED blocker found and patched.
- [x] Name pipeline (CFuncs + GH3+) into the manifest.
- [x] Compile lifted output on arm64.
- [x] First boot: runs CRT startup natively; stops at the first missing import.
- [x] CRT: msvcr80/msvcp80 lifted as statically imported modules.
- [x] AWL reimplemented natively (`src/awl.cpp`).
- [x] GH3+ loader stub replaced (`src/plugins.cpp`).
- [x] Bink 1.9 frame-buffer API; intro movies play.
- [x] FMOD Ex lifted (CPU probes replaced), Winsock TCP, overlapped I/O, D3DX volume/PNG/JPEG/conversions.
- [x] **Title screen, BetterGH3 online dialog and controller-help screen render** (Metal), 3-minute runs without a fatal.
- [x] Performance: ~120 fps (vsync-capped) after `--no-x87-doubles` + all -O2 (was 20-40).
- [x] Audio: FMOD → DirectSound → SwARc mixer → CoreAudio; verified by dump.
- [x] Keyboard input: GH3's default map decoded; menus navigable (user-tested).
- [ ] Gameplay (song) not yet reached in automation; guitar controllers untested.

## First arm64 build and boot (observed)

- Build: 112 lifted files. Most compile at -O2 in about 6 min on 11 cores. Files over 5 MB use -O1, and the two over 6.5 MB use -O0: at -O1, clang ran 30+ min on the 85–95k-line functions without finishing. With -O0 the final pair plus the link took 5.3 min. Zero warnings.
- Binary: `build/cmake/gh3`, **551 MB** native arm64 (SwARc runtime in its own dylibs).
- Boot harness: `scripts/dev/boot.sh [secs]` runs against `build/gamedir` (symlinks to the real install, a private GH3.exe copy, an empty PLUGINS) with `GH3_BACKGROUND=1 GH3_WATCHDOG_SECS=30`; log in `build/logs/boot.log`. Crash reports go to `~/Library/Application Support/gh3/crashes/`.
- Boot 1: process, PEB/TEB, image and guest thread come up; lifted `__tmainCRTStartup` (0x68ed7b) runs, then fatal on `kernel32!InterlockedCompareExchange`. Added it and `InterlockedExchangeAdd` to SwARc's kernel32 (same branch).
- Boot 2: fatal on **`msvcr80.dll!_initterm_e`**. This is the CRT wall.

## CRT decision (inferred, pending)

- GH3's manifest binds `Microsoft.VC80.CRT` **8.0.50727.762** (VC++ 2005 SP1).
- Of the 107 msvcr80 imports, 42 names already exist in SwARc's UCRT HLE (x64 work). The other 65 are startup, SEH (`_except_handler4_common`, `__CxxFrameHandler3`), libm SSE2, printf variants and `std::exception`.
- msvcp80 (46) is `std::basic_string`, iostream and so on. GH3's inlined STL code reads those objects' fields directly, so an HLE must match MSVC 2005's exact layouts. That makes it risky.
- **Recommendation: lift the real `msvcr80.dll` and `msvcp80.dll` (8.0.50727.762, x86) as `--module`s**. They sit on kernel32, which SwARc HLEs, and layouts and behaviour come out exact for free. Source: Microsoft's VC++ 2005 SP1 redistributable (x86), extracted locally (needs `7z`/`cabextract`).
- Then: AWL (20) and the stubs (mac3r, IntelLaptopGaming, iphlpapi) in the game project; fmodex (UPX-packed, `upx -d`) lifted as a module; ws2_32 ordinals; Bink and d3dx9 gaps; D3D9 (SwARc in progress).

## Other identifications

- Havok is statically linked (`<hkpackfile classversion=...>` string, `hk*` RTTI). The giant x87 functions at 0x7FD500–0x8126E0 (called from 0x6EE000–0x747000) are probably Havok math. Not confirmed.

## Build-time hotspot (observed during first arm64 build)

- 167/170 lifted files compiled in about 10 min. `gen_147/148/149.cpp` (6–9.5 MB each) took 20+ min each at -O2.
- Cause: two real, huge straight-line x87 functions in Ghidra's list, `FUN_008066a0` (0x8066a0–0x80c029) and `FUN_0080c0a0` (0x80c0a0–0x812665), about 84–94k lines of C++ each. They are probably unrolled math (Havok or matrix code; not identified yet).
- They are made worse by **false weak entries** from the data-pointer scan: 0x00800081, 0x00808000, 0x00808020, 0x00808080, 0x00810000 look like colour/flag constants (e.g. 0x808080 grey), not code pointers. Each one lifts the rest of the big function again as a separate ~84k-line function.
- Fix options (todo): add a lifter manifest directive that drops a weak entry (e.g. `noentry <va>`), or filter weak entries that land mid-instruction or mid-function in Ghidra's ranges. Separately, compile the giant functions at -O1.

### False-entry fix (done)

- Lifter patch (same SwARc branch): manifest directive **`noentry <va>`**. The pointer scans skip that value as a code address.
- `scripts/dev/ghidra/ExportBlockStarts.java` → `build/symbols/gh3/blocks.tsv` (172,122 basic blocks, start and end).
- `scripts/dev/find_false_entries.py`: flags lifted entries that are not Ghidra functions and land **strictly inside a Ghidra basic block**. Real mid-function pointers (SEH handlers, catch blocks, switch targets) are block starts, and functions Ghidra missed lie outside its blocks. Output goes to `manifests/noentry.manifest`, which `gen_manifest.py --noentry` merges in. Extra manual ones (constants outside blocks, e.g. 0x007fffff) go in `manifests/overrides.manifest`.
- First pass flagged 2,433 entries = **37% of all lifted lines**. Examples: UTF-16 text (0x00730061 = "a\0s\0"), ASCII (0x00797261 = "ary"), colour/flag constants (0x00808080).

| Lift | Functions | Instructions | Unimplemented sites | Files | Lift time |
|---|---:|---:|---:|---:|---:|
| Before | 34,196 | 2,077,041 | 474 | 170 | 159 s |
| With noentry | 31,762 | 1,347,472 (−35%) | 143 | 112 | 81 s |

- What remains large is real code: `0x80C0A0`, `0x8066A0`, `0x8126E0` (84–95k lines each), `0x7FD500`, `0x7A6C30`, `0x797050`. `CMakeLists.txt` compiles lifted files over 5 MB at -O1.
- Caveat: when a dropped entry was a real target that Ghidra missed, the runtime stops with "indirect branch to unlifted address X". The fix is an `entry X` line in `manifests/overrides.manifest`.

## Boot progress log (observed)

Each line is the fatal stop after the previous fix. `scripts/dev/boot.sh`.

| # | Stops at | Fix |
|---|---|---|
| 1 | `kernel32!InterlockedCompareExchange` | SwARc kernel32: InterlockedCompareExchange, InterlockedExchangeAdd |
| 2 | `msvcr80!_initterm_e` | Lift the real CRT (below) |
| 3 | `advapi32!CryptAcquireContextA` (static init, 0x896276) | SwARc advapi32: CryptAcquireContextA/ReleaseContext/GenRandom (host CSPRNG) |
| 4 | `awl.dll!Aspyr::Win::Init` (WinMain 0x40157c) | `src/awl.cpp`: all 20 AWL imports natively |
| 5 | branch 0x4016de → 0x897d40 outside lifted code | SwARc PE loader maps raw data up to the aligned virtual size, as Windows does (the stub is in `.text`'s last page past VirtualSize); stub `replace`d by `src/plugins.cpp` |
| 6 | `user32!SetWindowTextW` (window setup 0x57ba91) | SwARc user32: SetWindowTextW |
| 7 | `binkw32!_BinkSetMemory@8` (0x5e0a29) | SwARc binkw32: Bink 1.9 frame buffers (`BinkGetFrameBuffersInfo`/`RegisterFrameBuffers`, planes written straight from ffmpeg's YUV), SetMemory/SetIOSize/SetFrameRate/ControlBackgroundIO/ShouldSkip/GetError/OpenWaveOut |
| 8 | `ws2_32!#21` (setsockopt) | SwARc ws2_32: connect, listen, accept, send, recv, getsockname, setsockopt, select, __WSAFDIsSet, WSAAsyncSelect (no notifications), gethostname, inet_addr, inet_ntoa, gethostbyname |
| 9 | `fmodex!FMOD_System_Create` | Lift `fmodex.dll` (UPX-unpacked) as a static-import module; replace its 3 CPU probes so it takes C mixing paths (`manifests/fmodex.manifest`, `src/fmod_cpu.cpp`) |
| 10 | branch into an FMOD switch case Ghidra missed | Lifter: merge its own jump-table recovery with Ghidra's partial tables (3 completed) |
| 11 | `d3dx9!D3DXCreateVolumeTextureFromFileInMemoryEx` | SwARc d3d9: `IDirect3DVolumeTexture9` (guest-memory levels; no GPU 3D upload yet, shaders get gfx's dummy volume); D3DX loads volume DDS, and a 2D DDS as depth 1 like D3DX |
| 12 | D3DX G16R16F → A8R8G8B8 | gfx: float formats in DecodePixel; D3DX: general format conversion |
| 13 | `d3dx9!D3DXCreateCubeTextureFromFileInMemoryEx` | SwARc d3dx9 |
| 14 | `ReadFile` with OVERLAPPED (loader thread) | SwARc kernel32: overlapped I/O completes synchronously (pread/pwrite, event set), GetOverlappedResult, CancelIo |
| 15 | D3DX DXT1 → DXT2 | Lossless DXT1→DXT2/3 block transcoder |
| 16 | `rcpss` in msvcr80 | Lifter + sse: RCPPS/RCPSS, correctly rounded, with an exhaustive test (`tests/x86/sse_rcp_test.cpp`) |
| 17 | PNG texture | D3DX: PNG via `SDL_LoadPNG_IO` |
| 18 | D3DX A8R8G8B8 → DXT5, DXT3 → DXT5 | D3DX: DXT1-5 block decoder + bounding-box DXT1/3/5 encoder; one decode→encode path for all conversions |
| 19 | JPEG texture | D3DX: JPEG via ffmpeg's MJPEG decoder |
| 20 | `iphlpapi!GetAdaptersInfo` | SwARc: no adapters (ERROR_NO_DATA) |
| 21 | msvcr80 printf state machine switch (`push 7; pop ecx; cmp eax, ecx`) | Lifter: jump-table bounds held in a register (`mov reg, imm` / `push imm; pop reg`) |
| — | none | **Runs 3+ minutes**: intro movies, title screen, menus (see below) |

### Lifting the CRT (observed)

- Source: Microsoft's VC++ 2005 SP1 redistributable with the MFC security update (`download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x86.EXE`, Microsoft-signed, sha256 `8648c5fc…adfd`). `7zz x` → `vcredist.msi` → `_14241_Microsoft_VC80_CRT_x86.msm` → `msvcr80.dll` (sha256 `c3ac989c…1c6d`) and `msvcp80.dll` (`372af797…ffb2`), **8.0.50727.6195**. That's the security-patched build of the 8.0.50727.762 GH3's manifest names; Windows' publisher policy redirects .762 to it.
- Staged in `build/input/` and `build/gamedir/` (gitignored; build inputs, not redistributed).
- Ghidra: 2,019 functions (msvcr80), 2,841 (msvcp80). Neither has static TLS. msvcr80 imports 160 kernel32 functions (120 HLE'd; the rest are console/process/wide-path APIs, fatal only if called), msvcp80 imports msvcr80 + 23 kernel32.
- Lift: `recomp_lift --exe GH3.exe ... --module crt/msvcr80.dll --symbols symbols_msvcr80 --module crt/msvcp80.dll --symbols symbols_msvcp80`: 37,551 functions, 1.56M instructions, 131 files.
- **SwARc change: statically imported lifted DLLs.** SwARc only supported DLLs a game loads itself. New `GameConfig::LiftedDll::static_import`: such DLLs are mapped before the EXE in list order, their exports are bound into importers' IATs (`BindImportSlot` in `process.cpp`; HLE thunk otherwise), and their DllMain(PROCESS_ATTACH) runs before the EXE entry.

### AWL (observed)

- Decompiled the 20 used exports (a local decompilation). They're thin wrappers around cached strings and an XML key/value config.
- GH3 needs `Init` to return **12**. Language is a two-letter code (GH3 compares the first 2 chars, e.g. "fr"); `LANGUAGE`/`GH3_LANGUAGE` env overrides, default "en".
- Config keys GH3 reads: Debugging.FullScreen, IntelGpu, Options.{Crowd,Flares,FrontRowCamera,GraphicsQuality,Physics}, Sound.{DspBufferLength,DspNumBuffers,SongSkew,SongSyncInterval,StreamBufferSize,StreamDecodeBufferSize}, Video.{Width,Height,MultiSampleQuality,MultiSampleType}; strings AutoLogin, Username, MatchUsername. Stored in `~/Library/Application Support/gh3/AspyrConfig.ini`.
- `GetConfigNumber` returns a double in ST0: `x87::LoadF64(c.fpu, ...)`.

### Bink (next)

- GH3 imports Bink 1.9's frame-buffer API (`BinkGetFrameBuffersInfo`, `BinkRegisterFrameBuffers`) and **no** `BinkCopyToBuffer`: it decodes into its own Y/cR/cB/A planes and converts YUV on the GPU. SwARc's binkw32 (ffmpeg) implements only the 1.x copy-to-buffer path. The plan is to extend it: ffmpeg's Bink decoder already outputs planar YUV (+alpha), which maps directly onto the frame-buffer planes. The `BINKFRAMEBUFFERS` layout must be confirmed against GH3's reads of it before relying on it.
- Lifting the real `binkw32.dll` instead is unlikely to work: its decoder is MMX-heavy, and the lifter lacks MMX (see the unimplemented `punpckhdq`/`psllq` sites).

## Running state (observed)

- Boot to intro movies (Activision, RedOctane, Neversoft, intro) via Bink frame buffers + GH3's YUV shader on Metal, then the title screen ("PRESS ANY BUTTON TO ROCK"), then BetterGH3's menus.
- BetterGH3's QB patches run unchanged (its custom "Try allowing Guitar Hero III through Firewall" online string appears).
- Online: with `AutoLogin=PROMPT` (default) the game asks to log in and, offline, ends on the online error dialog. `AutoLogin=OFF` in `~/Library/Application Support/gh3/AspyrConfig.ini` (values PROMPT/ON/OFF, strings in GH3.exe) skips it; the game then shows the controller help screen ("In the event of rock", continue = green).
- Input: test input (`GH3_TEST_INPUT`) keys reach the game (Return starts/skips). The keyboard fret mapping is not worked out yet (F1 did not act as green); XDinput/guitar input is the next input task.
- Intermittent: one host SIGSEGV right after Direct3DCreate9 in ~1 of 5 boots (the crash reporter faulted while unwinding); not reproduced since. To investigate.
- Audio: SwARc's DirectSound module is now linked (FMOD could not load dsound.dll before); output not yet verified by ear. Bink movie audio reports "0 playing" (GH3 sets no Bink sound system).

## Performance (observed)

`sample` on the running game (`build/prof/`): ~80% of the main thread is Havok's world step, game loop 0x484310 → 0x525840 → 0x6E5F40 → … → constraint solver 0x70F440 → **0x80C0A0** and **0x7FD500** (strings `MiNumJacobians` etc.). These are the two huge straight-line x87 functions built at -O0 (above). `Options.Physics=0` does not stop the step. Next: SoftFloat SSE (`sse::Arith`) and per-pixel texture conversion on upload (`gfx::DecodePixel`).

- fps: ~40 in early menus/movies before the solver became active; ~20-23 once it runs.
- Options, in order of payoff:
  1. **Native replacements of the solver functions** (`replace 0080c0a0` / `007fd500`): SwARc's intended workflow; the lifted body stays as reference. Havok 4.x solver code; write from the decompilation (a local decompilation), verify against the lifted body.
  2. Make clang finish at -O1/-O2 on them: the x87 runs emit a fast host-double path plus an exact fallback for every instruction, so the CFG is huge. Try `-ftime-trace` to find the pass, or a lifter option to split giant functions.
  3. Upload L8/other formats without per-pixel CPU conversion where SDL_GPU has a native format.

## Performance fix (observed)

- Profile showed ~80% of the main thread in Havok's solver (0x80C0A0, 0x7FD500), built at -O0 because clang could not finish them at -O1/-O2.
- Cause: every x87 run is emitted three times: a host-double path (taken only at PC=53), the exact register-run path (with the PC=24 `Fast24` fast path), and a per-instruction fallback. The double path's per-instruction exits into a resume switch make the CFG huge. GH3's render thread runs at PC=24 (D3D9 without FPU_PRESERVE), so that path is never taken.
- Fix: lifter option **`--no-x87-doubles`**, per module (after its `--exe`/`--module`), on for GH3.exe only. FMOD and the CRT keep the double path (FMOD's mixer thread stays at PC=53).
- The solver function alone (12.5k instructions):

| | -O0 | -O1 | -O2 |
|---|---|---|---|
| with double path | 268 s, 178 MB .o | >25 min | – |
| `--no-x87-doubles` | 258 s, 166 MB | 754 s | **470 s, 4.5 MB** |

- Whole build at -O2: 14 min on 11 cores; binary **590 MB → 114 MB**.
- fps (menus/movies, 1024x768, vsync): median **119.9** (display 120 Hz), p10 80, min 3.4 (load hitches). Before: 20-40.

## Audio fix (observed)

- FMOD Ex loads `dsound.dll` dynamically. SwARc lacked it in its known-module list and registered `DirectSoundCreate8` by ordinal only.
- Then FMOD enumerated devices and created none: its `DirectSoundEnumerateA` callback (fmodex 0x1002F030) skips the NULL-GUID "Primary Sound Driver" entry. Windows also reports each real device with a GUID; SwARc now reports the primary entry plus one device ("Speakers").
- Now: `DirectSoundCreate8` → `audio: 48000 Hz stereo on SDL driver 'coreaudio'`.
- Dev aid: `GH3_AUDIO_DUMP=file.wav` (mixer tap, float32 stereo 48 kHz). A 37 s boot dump has the logo-movie sounds (2-10 s) and sustained menu music (25 s on); nothing is silent where sound is expected. By-ear check pending.
- `GH3_TRACE=1` (+ `GH3_TRACE_FILTER=dsound`) logs import calls (wired in `src/main.cpp`).
- By ear (user session): music, hit and miss sounds play correctly.

### Audio lag (observed, user session)

- Symptom: notes and input were in sync with each other, but the music was heard late.
- Song clock: `ResetSongTimer`/`IncrementSongTimer` (0x53ba80/0x53bac0) keep the timer at 0xc489e0. 0x42ec92 corrects it from the music stream's position (0x497310, in ms) plus the stock song skew at 0xa12f78. So the game follows FMOD's stream position. That position is ahead of what is heard by the host's output buffering: SDL's default device buffer is 1024 frames, double-buffered on CoreAudio, about 50 ms (estimate).
- Fix: `src/main.cpp` sets `SDL_AUDIO_DEVICE_SAMPLE_FRAMES=256` unless the environment already sets it. User: in sync at 0 ms offsets, no crackle.
- Calibration (pure QB script, works as on Windows): BetterGH3 forces the stock skew to 0 (`qb/patch/globaltags.q:100`, `WinPortSetSongSkew value = 0`). Its own offsets `lag_audio`/`lag_video` (`qb/patch/winport/menu_calibrate_lag.q`, range ±1000 ms) are applied only at song start (`qb/patch/winport/apply_new_calibration.q:439`): gem_offset -= lag_audio, gem_offset += lag_video, input_offset -= lag_audio. The music itself never moves. Changes need a song restart.
- Not done: subtracting the remaining output latency from the DirectSound play cursor. FMOD refills its ring from that cursor, so a lagging report could make the mixer read blocks FMOD has not refilled yet.

## Window, resolution, focus (observed)

- SwARc sizes the game window in pixels, so GH3's default 1024x768 was a 512x384-point window on a Retina display (desktop 3024x1964 px).
- `src/awl.cpp`: `Video.Width/Height` default to the largest 16:9 display mode within 85% of the desktop: **2560x1440** here (a 1280x720-point window, sharp on Retina). `GH3_RESOLUTION=WxH` overrides it; a value saved in AspyrConfig.ini wins. fps at 2560x1440: median 116, p10 77.
- Focus: a bare binary started from a terminal never becomes the active app on macOS (window opens behind, keyboard stays with the terminal). `scripts/dev/play.sh` now builds `build/dev/GH3.app` (binary symlinked in; the rpaths are absolute) and launches it with `open -W -n --stdout/--stderr`, so it comes up frontmost with keyboard focus. Verified: frontmost process is `gh3` after launch.
- `GH3_FULLSCREEN=desktop` (SwARc) gives borderless fullscreen; `play.sh` passes it and the other GH3_* options through `open --env`.

## Gameplay performance (observed, user sessions with GH3_PROFILE=1)

Gameplay fps (between profiler windows; macOS `sample` pauses the game, so the 5 s windows every 15 s dip and are excluded):

| Build | Gameplay fps | Main change |
|---|---|---|
| `083be42` | 15-18 | (Havok fixed; menus already ~120) |
| `09028bb` | 35-60 | SSE add/sub/mul/div + conversions: host fast path in sse.cpp (was SoftFloat, ~55% of the main thread) |
| `d925878`, `9b91ad8` | 47-89 | fast paths inlined into lifted code (`x86/sse_fast.h`), sqrt and min/max, sticky-PE skip, GPU submissions pipelined (64 in flight, 256 MB staging cap) |
| `8c89c7d` | 62-104 (mostly 65-100) | fast paths force-inlined (the compiler had declined in the biggest functions); RSQRTPS/RCPPS fast exact lanes |
| `97232fa` | **120, vsync-capped** (median frame 8.33 ms, p99 mostly < 9 ms) | native skinning (0x61c590), bit-identical to the original |

- Every fast path gives the exact model's bits and MXCSR flags. `tests/x86/sse_fast_test` fuzzes each against the SoftFloat path (rsqrt/rcp exhaustively over significands). Planted mutations are caught, except the rsqrt midpoint margin, which the exhaustive test shows never fires.
- What remains on the main thread (`build/prof/t57.txt`, 8c89c7d):
  - **44%: `f_0061C590`**, a large hand-written SSE kernel, called from 0x61E260 ← 0x58A920 (render/update). Uses rsqrtps normalisation and movntps streaming stores: most likely CPU skinning of character meshes (bone-matrix transforms of positions and normals). All of its SSE is inline now; the rest is the cost of emulating it instruction by instruction. **Next lever: a native replacement** (`replace 0061c590`, written from the decompilation, verified against the lifted body).
  - 19%: game logic under 0x4A2E70/0x65C770 (diffuse).
  - 16%: render submission (0x5FA040 → D3D9 HLE draws and render-target binds).
- FMOD's mixer thread uses ~75% of another core (C mixing paths forced by the CPU-probe replacements). It's off the critical path but could later get its own SSE path once the lifter has MMX, or a native mixer.

## Native skinning (observed)

- `src/skinning.cpp` replaces 0x61c590 (`replace 0061c590`): 1/2/3-bone vertex groups, positions transformed, normal/tangent/binormal transformed and renormalised (RSQRTPS through SwARc's model), AoS output (p n t b) with MOVNTPS-aligned stores, running min/max, vertex count in eax. Compiled with `-ffp-contract=off -fno-fast-math`.
- Operation order transcribed from the disassembly. The decompiler keeps float grouping inside a row but printed the 3-bone sum flat; the original is `C*wC + (A*wA + B*wB)`.
- Verification: `GH3_VERIFY_SKIN=1` runs native into a host buffer and the lifted body (`f_0061C590_lifted`) for real, then compares every output float, min/max and eax.
  - First run: 1/2-bone paths identical; 3-bone vertices off by 1 ulp (wrong grouping). Fixed in 97232fa.
  - Second run: **131,072 calls, 0 mismatches** in gameplay.
- MXCSR: sets PE, as the original does; flags that only denormal or non-finite data could raise are not modelled.

## Xbox 360 wireless receiver (observed, user session)

- macOS has no driver for the receiver: it is a vendor-class USB device, not HID, so SDL never sees it. The community driver x360w (github.com/zeromiyi/x360w) was reviewed. Its code is clean, but its virtual gamepad needs `amfi_get_out_of_my_way=1`, which turns off AMFI's entitlement enforcement for the whole system. Not used.
- Instead, SwARc's XInput layer reads the receiver itself over libusb (`platforms/win32/src/win32/xbox360_receiver.cpp`). An unclaimed vendor interface needs no entitlement and no root. It finds receivers by interface (FF/5D/81 with interrupt IN/OUT), not by id. A supervisor thread rescans every 2 s and sends LED and rumble commands; there is one reader thread per slot. Connected slots take XInput user indices next to SDL's pads. The input report from byte 6 is XINPUT_GAMEPAD verbatim, with guide masked. The subtype comes from the announcement packet, byte 25 & 0x7f.
- User's clone receiver enumerates as 045e:0291 with 4 slots. Its GH guitar announced `... 51 87 ff ff ff`: subtype 7 (guitar alternate), with the force-feedback bit set. Pairing, menus and songs all worked.
- `GH3_X360RX_TRACE=1` logs every packet; `scripts/dev/play.sh` passes it through. A guitar streams about 1 report per frame while held (52k packets in one session), so the trace is for debugging only.
- Needs libusb at build time (`brew install libusb`). Without it the receiver code compiles to stubs.

## App bundle (observed)

- `packaging/macos/make_app.sh` builds `build/Guitar Hero III.app` (169 MB) from the current build:
  - `gh3`, plus 38 dylibs in `Contents/Frameworks`: SwARc's 15 libraries, plus SDL3, ffmpeg and its codec deps, libusb, SPIRV and others from Homebrew. `packaging/macos/bundle_dylibs.py` walks `otool -L`, resolves @rpath/@loader_path, rewrites every reference to `@rpath/<name>`, and leaves one rpath, `@executable_path/../Frameworks`. A check finds no reference outside the bundle except /usr/lib and /System.
  - An icon from GH3.exe. `packaging/macos/exe_icon.py` takes the largest RT_ICON, which is only 48×48, so the big Finder sizes are upscaled.
  - An ad hoc signature; `codesign --verify --strict` passes.
- Game folder: symlinks that point out of a bundle fail strict verification ("invalid destination for symbolic link in bundle"). So the default build puts a folder of links at `~/Library/Application Support/gh3/game`: links to `Guitar Hero III/`, plus real copies of build/gamedir's runtime files (lifted msvcr80/msvcp80, the unpacked fmodex.dll). `--embed-game` instead APFS-clones the game into `Contents/Resources/game`, which makes the app standalone.
- `gh3` with no arguments uses the bundle's `Resources/game`, or failing that `~/Library/Application Support/gh3/game`, and writes stdout/stderr to `~/Library/Logs/Guitar Hero III.log`. Passing arguments works as before (`play.sh`).
- Smoke test: the bundled binary, run with no arguments and `GH3_BACKGROUND=1`, booted to audio and the intro movies in 20 s.

## Pointer capture and quitting (observed, user session)

- In a window, the pointer was captured: GH3 takes DirectInput's mouse with `DISCL_EXCLUSIVE`, and SwARc's `Grab` (dinput8) turns on SDL relative mode, as Windows confines the pointer. New `GameConfig::grab_pointer_in_window` (default true): when false, the grab happens only while the window is fullscreen (`PointerGrabAllowed` in user32_window.cpp, used by the DirectInput grab, `ClipCursor` and re-attaching a clip). Mouse buttons and motion still reach DirectInput through SDL's events. GH3 sets it false (`src/main.cpp`).
- Dock → Quit did nothing: SDL turns the app's quit request into `SDL_EVENT_QUIT`, SwARc posts `WM_CLOSE` to the game's windows, and GH3 ignores `WM_CLOSE`. New `GameConfig::quit_on_close_request` (default false): when true, a host quit request or the window's close button exits the process at once (as `ExitProcess(0)`). GH3 sets it true. Tested: a Quit Apple Event (`osascript ... to quit`, what the Dock and Cmd+Q send) ends the app immediately.

## A simpler build: no Ghidra, no patch

Two parts of `./setup.sh` made the build heavier and less reproducible than it needed to be:
- **Ghidra ran on every machine.** Ghidra (775 MB) and its JDK (371 MB) were installed only to export each module's functions and jump tables, which took about 5 minutes. Homebrew does not pin Ghidra's version, and `manifests/noentry.manifest` was made against Ghidra 12.2's function list. A newer Ghidra could have found other functions and changed the lifted code without anyone noticing. The four modules' `functions.tsv`/`jumptables.tsv` (1.6 MB, addresses and names only) are now committed in `manifests/ghidra/`. `scripts/setup/symbols.sh` copies them next to `pe_symbols.py`'s output. `scripts/dev/ghidra_analyze.sh` redoes them, and warns when the Ghidra version is not 12.2.
- **SwARc changes were a 4,000-line patch.** It had to be regenerated by hand (`git add -N`, `git diff HEAD`), and it stopped applying whenever the checkout had changes. They are now seven signed commits on the `gh3` branch of [segovia-no/SwARc](https://github.com/segovia-no/SwARc/tree/gh3), grouped by subject: lifter, x86 core, loader, Win32 APIs, graphics/video/audio, the Xbox 360 receiver, the window. The tree is identical to the old patch. `SWARC_COMMIT` pins the tested commit; `fetch_swarc.sh` clones, checks it out, and leaves a checkout that is ahead of it alone (work in progress). A clean `./setup.sh` now takes 17m52s on the M3 Pro (20m49s before), and the lifted code is byte-identical.
