# SwARc spike — GH3.exe on macOS arm64

Started 2026-11-08. Observed = verified locally; Inferred = reasoning, not yet tested.

## Setup (observed, reproducible)

Host: macOS 26 (Darwin 25.6), Apple Silicon, Apple clang 21.

```sh
brew install cmake ninja sdl3 ffmpeg llvm@22 glslang spirv-cross ghidra   # ghidra pulls openjdk@25
git clone https://github.com/JTM-rootstorm/SwARc ref/SwARc               # tested at 240ef13
cd ref/SwARc
git checkout -b gh3-multi-code-sections 240ef13
git apply ../../patches/swarc-gh3.patch   # our SwARc changes (code sections, noentry, kernel32)
cmake --preset release -DRECOMP_LLVM_ROOT=/opt/homebrew/opt/llvm@22
cmake --build --preset release          # 489/489, clean
ctest --test-dir out/build/release -j8  # 17/17 pass
```

- Ghidra 12.2 (brew) needs **JDK 25**, not 21: `JAVA_HOME=/opt/homebrew/opt/openjdk@25`.
- Lifter: `out/build/release/tools/lifter_x86/recomp_lift`.
- Lifter inputs (`--symbols dir`): `functions.tsv` + `jumptables.tsv` (Ghidra scripts in `tools/ghidra/`), `exports.tsv` (`tools/pe_symbols.py`).

```sh
# PE facts / imports / exports
PATH=/opt/homebrew/opt/llvm@22/bin:$PATH python3 -I ref/SwARc/tools/pe_symbols.py work/GH3.exe --out work/symbols
# Ghidra full analysis + exports (work/ is gitignored)
JAVA_HOME=/opt/homebrew/opt/openjdk@25 /opt/homebrew/opt/ghidra/libexec/support/analyzeHeadless \
  work/ghidra GH3 -import work/GH3.exe -overwrite -scriptPath ref/SwARc/tools/ghidra \
  -postScript ExportFunctions.java $PWD/work/symbols/functions.tsv \
  -postScript ExportJumpTables.java $PWD/work/symbols/jumptables.tsv
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

`python3 -I tools/import_coverage.py work/symbols/imports.tsv ref/SwARc/platforms/win32/src --out docs/data/import_coverage.tsv`

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

- **HATRED blocker and fix.** SwARc's lifter (`Module::text_lo/hi`) and runtime (`process.cpp TextOf`) assume one `.text`. GH3's `.text` tail-jumps into HATRED (relocated bodies; 1,568 thunks per `docs/decomp-crossref.md`). Patch on branch `gh3-multi-code-sections` in `ref/SwARc` (39 lines added, 5 removed): every `IMAGE_SCN_MEM_EXECUTE` section becomes a code range in both the lifter (`Module::extra_text`, `HasCode`, `CodeEnd`) and the runtime (`ExtraCodeOf` → `Process::code`; the dispatcher already handled several ranges). Worth upstreaming in generic terms ("code a protector's unwrapper moved out of .text").
- **Unimplemented sites** are mostly data decoded as code from weak data-pointer entries (`arpl` 60, `les` 52, `in`/`out` 69, `iretd` 16, `bound` 16, BCD ops). Candidates for real code to check: `movntps` 11, `enter` 27, `punpckhdq` 4, `cvtpi2ps` 2, `fisttp` 3, `psllq`, `psubusw`. Triage only when the runtime reaches one: by design, reaching unlifted code is a fatal error that names the VA.
- Output: 371 MB of C++ in `work/generated/` (gitignored, regenerable).

## Naming pipeline (observed)

- `tools/extract_cfuncs.py` → `docs/data/cfuncs.tsv` (QB C-function table at 0x9551B8, 1,170 names). I spot-checked the first entries against the bytes.
- `tools/extract_gh3plus_symbols.py` → `docs/data/gh3plus_symbols.tsv` (GH3+, BetterGH3, gh3ml, gh3.CT).
- `tools/gen_manifest.py` merges `recomp/overrides.manifest` (hand-written) with those into `recomp/lifter.manifest`: 1,257 `entry` names, plus `__body` names for the 18 named thunks into HATRED.
- Names reach the generated C++ only as comments, but `entry` lines also make the table-only CFuncs real lifted functions.

## Game project (observed)

`recomp/CMakeLists.txt` + `recomp/src/main.cpp`: SwARc via `add_subdirectory`, `recomp_add_lifted(gh3_lifted work/generated)`, links recomp_win32/d3d9/dinput8/xinput/bink. `GameConfig` id `gh3`, guest dir `C:\Program Files\Aspyr\Guitar Hero III`.

## Status log

- [x] Build SwARc on macOS arm64, tests green.
- [x] pe_symbols on GH3.exe.
- [x] Import coverage.
- [x] Ghidra function/jump-table export.
- [x] First `recomp_lift` run; HATRED blocker found and patched.
- [x] Name pipeline (CFuncs + GH3+) into the manifest.
- [x] Compile lifted output on arm64.
- [x] First boot: runs CRT startup natively; stops at the first missing import.
- [ ] CRT: lift msvcr80/msvcp80 8.0.50727.762 as modules (see below).

## First arm64 build and boot (observed)

- Build: 112 lifted files. Most compile at -O2 in about 6 min on 11 cores. Files over 5 MB use -O1, and the two over 6.5 MB use -O0: at -O1, clang ran 30+ min on the 85–95k-line functions without finishing. With -O0 the final pair plus the link took 5.3 min. Zero warnings.
- Binary: `work/build/gh3`, **551 MB** native arm64 (SwARc runtime in its own dylibs).
- Boot harness: `tools/boot.sh [secs]` runs against `work/gamedir` (symlinks to the real install, a private GH3.exe copy, an empty PLUGINS) with `GH3_BACKGROUND=1 GH3_WATCHDOG_SECS=30`; log in `work/boot.log`. Crash reports go to `~/Library/Application Support/gh3/crashes/`.
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
- `tools/ghidra/ExportBlockStarts.java` → `work/symbols/blocks.tsv` (172,122 basic blocks, start and end).
- `tools/find_false_entries.py`: flags lifted entries that are not Ghidra functions and land **strictly inside a Ghidra basic block**. Real mid-function pointers (SEH handlers, catch blocks, switch targets) are block starts, and functions Ghidra missed lie outside its blocks. Output goes to `recomp/noentry.manifest`, which `gen_manifest.py --noentry` merges in. Extra manual ones (constants outside blocks, e.g. 0x007fffff) go in `recomp/overrides.manifest`.
- First pass flagged 2,433 entries = **37% of all lifted lines**. Examples: UTF-16 text (0x00730061 = "a\0s\0"), ASCII (0x00797261 = "ary"), colour/flag constants (0x00808080).

| Lift | Functions | Instructions | Unimplemented sites | Files | Lift time |
|---|---:|---:|---:|---:|---:|
| Before | 34,196 | 2,077,041 | 474 | 170 | 159 s |
| With noentry | 31,762 | 1,347,472 (−35%) | 143 | 112 | 81 s |

- What remains large is real code: `0x80C0A0`, `0x8066A0`, `0x8126E0` (84–95k lines each), `0x7FD500`, `0x7A6C30`, `0x797050`. `recomp/CMakeLists.txt` compiles lifted files over 5 MB at -O1.
- Caveat: when a dropped entry was a real target that Ghidra missed, the runtime stops with "indirect branch to unlifted address X". The fix is an `entry X` line in `recomp/overrides.manifest`.
