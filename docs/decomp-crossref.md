# GH3 decomp/recomp cross-reference → naming PC GH3.exe

Status: 2026-11-08. **[O]** = observed locally (command/script output); **[I]** = inferred; **[R]** = reported by the repo itself, not re-verified.
Target: `work/GH3.exe`, FileVersion **1.3.1.68131** [O], same build BetterGH3 uses.
All clones are shallow, under `ref/` (gitignored), read-only. No scripts or builds from them were run.

## TL;DR

- **GH3.exe has its own script C-function table.** It is at `.data` **0x9551B8**: 1170 `{const char* name, fn*}` pairs, **1160 unique function VAs** [O]. The count is confirmed by the getter `0x4134A0: mov eax,0x492; ret` [O]. A list of 90 member-function names follows it at 0x957648 [O]. Extracted to `docs/data/cfuncs.tsv` with `tools/extract_cfuncs.py`. The PS2 decomp is **not needed** for these names: PC already has them with PC addresses.
- **GH3+/BetterGH3/gh3ml/GH3.CT** give 510 distinct PC addresses (**171 functions, 339 globals**) in `docs/data/gh3plus_symbols.tsv` [O]. 80 of the functions are not in the CFunc table. 81 of the 86 that overlap the table agree on the name (the other 5 are truncated or placeholder names) [O]. That cross-check validates both sources.
- **MSVC RTTI is present:** 1168 class type descriptors, 1236 vftables, about 4.1k distinct virtual-method targets [O, rough walk]. This is the largest naming source after the CFunc table, and no other project exploits it.
- **HATRED = relocated function bodies.** 1568 16-byte-aligned `.text` entries start with `jmp rel32 → HATRED`, and the body runs there in clean, unobfuscated code [O]. Example: `0x4A6AC0 → 0xD94F31`, the member-function registrar. Each name must be applied to both the thunk and the body.
- **Other repos:** gh3-decomp (PS2, AGPL) is stripped, and its names are almost all `CFunc_*` (941) or `func_XXXXXXXX` (8034). The sp00nznet PS3 recomp has no game names. gh3-r36s is very good for data formats. neversoft-script-library has the full PC **1.31** QB script source and a 5831-name `debugger_names` dictionary.
- **Coverage now:** about **1,240 named function VAs** out of an estimated **25–29k** function entries, so roughly 4–5%. With RTTI vftables and HATRED-thunk propagation, about 20% is realistic (see the plan below).

## 1. Repos surveyed

| Repo (ref/ dir) | What | License | Size | Naming data (format, count) | Transfers to PC? |
|---|---|---|---|---|---|
| `gh3-decomp` (Ketbome) | PS2 SLUS-216.72 matching decomp, EE GCC 2.95, splat | **AGPL-3.0** | 10 MB | `config/functions.txt` (`name addr size srcfile`): 9002 functions, of which 968 are named (941 `CFunc_*`, 9 `SndDrv_*`, about 18 others) [R]. `config/symbols/cfuncs.txt`: 941 entries plus `g_cfunc_table=0x32E358` (943 entries) [R]. `config/symbols/game.txt`: 27 inferred engine names with evidence. `config/qbkeys.txt`: 3216 `0xKEY = name` [O]. No mangling, no class names, no headers (structs are mechanical `S2562_Script`). | The names are the same strings as the PC table: 823 of its 941 CFunc names exist in the PC table [O]. Its only extra value is the ~27 engine names via call-graph matching, plus understanding of the C bodies (776 CFunc bodies in C) [R]. |
| `gh3-ps3recomp` (sp00nznet/gh3) | PS3 static recomp, reaches gameplay | MIT | 22 MB | Only `imports.json`: 229 PS3 NIDs. Game functions are all auto-named `func_XXXXXXXX` (28,987 lifted) [R]. | No names. Gives engine-behaviour notes (below). |
| `gh3-r36s` (fernandoalves25) | Clean-room C/SDL2/GLES2 player that reads PC data | MIT (+ minimp3, pl_mpeg) | 7.8 MB | None (no PC addresses). `tools/qbkey_guess.py` | Format and gameplay knowledge only. |
| `gh3ml` (Bambo-Borris) | PC mod loader (xinput1_3 proxy + MinHook) | MIT | 0.5 MB | 11 distinct PC addresses (`src/gh3ml/main.cpp`, `libGH3/include/GH3/Qb/*.hpp`). `Keys.hpp` = a copy of GH3Keys (5831). | Yes, direct PC VAs (LoadPak 0x4A1780, DebugLog 0x472B50, CFunc Printf 0x530940, qbMalloc 0x402370 …). |
| `GH3-Plus-donnaken15` | GH3+ fork (BetterGH3 vendors this lineage) | none | 22 MB | 808 distinct PC address literals, against 312 upstream [R]. `src/plugins/Logger/AssertPoints.h`: 175 `AIF(start,end,"name")` ranges, 107 named, exported from IDA via ScriptAssert xrefs. Some names are MSVC-mangled (`?MainLoop@Manager@Mlp@@QAEXXZ` 0x484310, `?hit_note@GuitarFuncs@@YAXHH@Z` 0x4308F0). Those mangled strings are **not** in GH3.exe [O], so their provenance is unknown (possibly another platform's symbols). | Yes, direct. |
| `GH3-Plus` (ExileLord), `BetterGH3/GH3Plus` | Already present | none | – | `GH3GlobalAddresses.h` (249 `#define ADDR_*`), `GH3Functions.h` (19), `malloc.h`, `QbStruct.cpp` (Insert* natives 0x479920–0x479E40), `QbScript.h` (SpawnScript*), `gh3.CT` (208 entries; identical in BetterGH3 and donnaken15) [O] | Yes, direct. |
| `neversoft-script-library` (nsneverhax) | Decompiled `.q` scripts: gh3/gha/ghwt/gh5/…; GH3 pc/360/ps2/ps3/wii | none | 523 MB total (gh3: 78 MB) | `gh3/pc/base_1.31/scripts/debugger_names.q`: 5831 names, the source of GH3Keys.h [R]. 3350 `script` definitions in base_1.31 [O]. | Indirectly. 564 or more of the 1170 CFunc names are called from 1.31 scripts [O], which gives call-site semantics for every CFunc. |

License note (**important**): gh3-decomp is **AGPL-3.0**, so it is reference-only. Do not copy its C bodies, struct declarations or symbol files into our tree. Facts we re-derive from **our own** exe are fine: the CFunc names in `cfuncs.tsv` come from GH3.exe's own strings, not from the decomp. gh3-r36s and gh3ml are MIT and may be adapted with attribution. GH3+/BetterGH3/donnaken15/neversoft-script-library have **no license**: treat them as reference, use their addresses as facts, and do not vendor their code. The neversoft-script-library scripts and GH3Keys names are Activision content.

## 2. Name sources in the PC exe, and how names transfer

### 2a. QB C-function table (observed, primary anchor)

```
0x41756D  call 0x4134A0      ; mov eax,0x492; ret  → 1170
0x417572  push eax
0x417573  push 0x9551B8      ; {char* name, bool(*)(Script::CStruct*,Script::CScript*)}[1170]
0x417578  call 0x4A6A70      ; register C functions (hash name → symbol table)
0x417580  call 0x4134B0      ; mov eax,0x5A; ret   → 90
0x417585  push eax
0x417586  push 0x957648      ; char*[90] member-function names (AnimLoaded, SetProps, Text_GetString…)
0x41758B  call 0x4A6AC0      ; register member-function names (thunk → HATRED 0xD94F31)
```
- First entry: `WinPortSioGetDevicePress → 0x419A20`. Last: `GetEnterButtonAssignment → 0x411AB0`. Sample [O]: `SpawnScript 0x534100`, `SpawnScriptNow 0x534140`, `SpawnScriptLater 0x534160`, `KillSpawnedScript 0x531820`, `LoadPak 0x4A1780`, `WaitUnloadPak 0x4A21D0`, `Wait 0x52EAF0`, `GetSongTime 0x53BB00`, `WaitForFileCache 0x5380F0`, `Printf 0x530940`, `ResetEngine 0x5377F0`, `CreateViewport 0x550D10`.
- 7 names share **0x410900**, a generic "return true" stub: LaunchPanelMessage, KillMessages, WriteAchievements, UseOnePadInFrontEnd … [O]. This is a console/360 feature stubbed on PC. Do not name 0x410900 after any one of them.
- 22 names are PC-only `WinPort*` (WinPortSio*, WinPortGfx*Option*, WinPortSongHighwaySync, WinPortSetSongSkew, WinPortGetLaptopInfo) [O]. They are the Aspyr platform layer and are high-value for HLE.
- Against PS2: 823 names are shared, 347 are PC-only (net/Live: ConnectToInternet, CheckForSignIn, Tesla effects, CompactPool profiling, achievements), and 118 are PS2-only (AddMusicTrack, BCSND_UpdateSound, Bootstrap, …) [O].
- 13 CFunc targets begin with `jmp → HATRED` [O]. Their bodies live in HATRED.
- **Lifter naming suggestion:** `CFunc_<Name>` (the same convention as gh3-decomp, which avoids clashing with engine-internal functions that have the same name, e.g. `Script::SpawnScript` vs `CFunc_SpawnScript`).

Strings in the exe that were asked about [O]: `SpawnScript` (0x8A4578), `LoadPak` (0x8A23C4), `PlaySound` (0x8A52B8), `GetSongTimeMs` (0x8A1C30), `ScriptAssert` (0x8A68C0), `CreateScreenElement` and `SetScreenElementProps` are all present and in the table: `CreateScreenElement 0x4914B0`, `SetScreenElementProps 0x491CF0`, `PlaySound 0x546F40`, `GetSongTimeMs 0x53BB30`, `ScriptAssert 0x532DD0`. The 5 that were pointer-scanned each have exactly one reference, their table slot. `WaitOneGameFrame` is **not** a CFunc. QB uses `Wait 1 gameframe` (CFunc `Wait`). `printf` is spelled `Printf`.

### 2b. Other anchors in the PC exe

| Anchor | Observation | Use |
|---|---|---|
| RTTI `.?AV…@@` | 1168 type descriptors, 1236 COLs/vftables, about 4148 distinct code pointers in vftables (crude walk) [O]. Namespaces seen: Obj (94), Anm (89), Nx (47), Net (30), Gfx (27), Ass (20), Front (16), Progression, GameNet, Mem, Mdl, hk* (Havok), std. | Name vftables `Class::vftable`, slots `Class::vf<N>`, and constructors (the functions that store a vftable pointer) as `Class::ctor_<va>`. Ghidra's RTTI analyzer (`RecoverClassesFromRTTIScript`) does this automatically. |
| QbKey immediates | The QbKey hash is `CRC32(lower(name).replace('/','\\'))` with init 0xFFFFFFFF and **no final xor** (= `~zlib.crc32`). Verified on GH3Keys.h: 5744/5831 matches; the misses are key-name spelling artifacts [O]. The CRC table is at `.data` 0x95CD28, used by the functions at 0x4FFA30/0x4FFB30/0x4FFC20/0x4FFCA0/0x4FFD10 (≈ `Crc::GenerateCRC*` family [I]), 0x4939D0, 0x4C9B10 and 0x60DC70 [O]. | Annotate `push 0xXXXXXXXX` checksums with names (5831 + 250 extra in the decomp's qbkeys). This identifies which CStruct param a function reads (e.g. `0xA750190B` at 0x417563) [I]. |
| Source paths | 105 `.cpp` strings, almost all DemonWare `.\bd*\*.cpp`. Also `e:\depot\gh3_th9\port\gh3\code\sk\gamenet\ps3\demonware\…` and `E:\depot\GH3_TH9\Port\nxcommon_gh3\DemonWare\1.80\…` [O]. Engine asserts are stripped. | Name the DemonWare (bd*) library functions via their assert strings. The depot layout shows THUG-lineage `code/sk` and `nxcommon_gh3` [O]. |
| Heap / pak format strings | `heap_bink`, `heap_frontend`, `heap_network`, `heap_script_pools`, `heap_global_scripts`, `heap_havok`, `heap_hashitem_pool`, `skaterheap%d`, `pak/qb.pak`, `pak/dbgq.pak`, `%s%s.pak.%s`, `%s.qb.%s`, `levels\%s\%s%s.scn.%s` [O] | xrefs → Mem::Manager heap init and the PAK-path builders. |
| Imports | FMOD Ex C++ API (System::createStream/createSound/setFileSystem/update, Channel::*, DSP::*): 53 entries. Aspyr `AWL.dll` `Aspyr::Win::*` (paths, config, window): 20 [O]. | Name the import thunks and their wrappers (callers of `System::update` → audio-manager update, etc.). |
| GH3+ ScriptAssert xrefs | `AssertPoints.h` is in effect an IDA export of the callers of `ScriptAssert` 0x532DD0 with function bounds | Already harvested into `gh3plus_symbols.tsv` |

### 2c. What gh3-decomp could still contribute (reference-only, AGPL)

- **Engine names by call-graph matching:** about 27 names. Pair a PS2 `CFunc_X` with PC `CFunc_X` (823 pairs) and walk their callees in parallel. For example, the PS2 decomp has `CFunc_SpawnScript` calling `func_0027D1F8(params, 0xEE67888A, …)` (≈ `CStruct::GetChecksum/GetInteger`, 1039 call sites [R]). On PC, the callee of `CFunc_SpawnScript` (0x534100) that is called with the same QbKey immediate is the same accessor [I]. In the same way: `Heap_Alloc/Free`, `operator new/delete`, `PoolAlloc/Free`, `HashTable_GetItem/FlushItem`, `CrcFromPathLowercase`, `Get/SetProgressionDifficulty`. The engine names must be re-derived by us from PC evidence, not copied.
- **Understanding:** reading the C bodies of 776 CFuncs. MSVC x86 and EE GCC code differ, but the control flow and QbKey constants are the same [I].

## 3. Engine knowledge for HLE / porting

| Area | Knowledge (source) |
|---|---|
| **QB VM** | Value types (`GH3Plus/src/gh3/QbValueType.h`): 1 int, 2 float, 3 cstring, 4 wstring, 5 pair, 6 vector, 7 script, 8 cfunc, 0xA struct, 0xC array, 0xD qbkey, 0x1A string-ptr, 0x1B map. Struct item = `{u8 ?, u8 flags/type, u16, QbKey key, value, next}`, 16 bytes; PS3 confirms the same layout, with the value at +4 after the key (sp00nznet `tools/harness/bot.sh`). `CScript`/`QbScript` layout: next/prev, +0x10 IP, +0x14 params, +0x18 args, +0x1C vars, +0x38 depth, +0x3C callstack (`QbScript.h`, donnaken15 `Logger.cpp`). Token enum: donnaken15 `plugins/QDB/QDB.cpp`. Global symbol hash map: `GlobalMap.h` (nodes at 0xC03AA8), `GlobalMapGet*` 0x4A58C0–0x4A5E00. Insert natives 0x479AC0–0x479E40, `CStruct::Get*` 0x4788B0–0x479330. CFunc signature `bool(CStruct* params, CScript* script)`. Registration is described in 2a. |
| **Memory** | `qbMalloc` 0x402370 / `qbFree` 0x4023E0 / `qbArrMalloc` 0x4373A0 / `qbItemMalloc` 0x437410 (GH3+ `malloc.h`). Named heaps come from strings (2b). CFuncs `MemInitHeap`, `MemDeleteHeap`, `MemHeapExists`, `DumpHeaps`, `AnalyzeHeap` [O]. On PS3, heap selection depends on the current thread, through a per-thread allocator stack; the PS2 decomp has `Heap_Alloc(heap,size,align,0)` and pools with fallback [R]. Expect the same Mem::Manager on PC [I]. The array allocator memsets without a null check on OOM, a PS3 bug pattern that may also exist on PC [R]. |
| **File system** | `LoadPak` 0x4A1780 (gh3ml hooks it to inject a mod pak after the 2nd call), `WaitUnloadPak` 0x4A21D0, `WaitForFileCache` 0x5380F0, `LoadFSB` 0x548E50. Boot loads `pak/qb.pak` and `GLOBAL.PAB`/`GLOBAL_VRAM.PAK` (PS3 notes). Formats (`gh3-r36s/src/gh3fmt.c`): PAK = big-endian 32-byte entries `{type, off(rel), len, pakKey, fullKey, nameKey, ?, flags}`; flag 0x20 means a 160-byte name follows; the list ends at `.last`; PAB data offset = off − pakLen. QB file sections start at +28. Files are `.xen` (360 endianness) even on PC [O, research.md]. |
| **Audio** | FMOD Ex on PC (53 imports) and on PS3, where it runs as a SPURS task [R]. FSB3: XOR with `"5atu6w4zaw"` then bit-reverse; MP3 streams guitar/rhythm/song/preview/coop (`gh3fmt.c:438–449`). `System::setFileSystem` is imported, so the game supplies its own file callbacks; an HLE must honour them [I]. The PS2 IOP sound driver is irrelevant. |
| **Render** | `Nx::` RTTI namespace (47 classes), `Nx::jqManager` string [O]. Render toggles in globals: `g_renderInstances` 0x95FDA8 … `g_renderScreenFx` 0x95FDD0 (GH3.CT). Present hook sites 0x48453B/0x48458B and `d3ddev` 0xC5C7A8 (FastGH3 `startup.cpp`). `WinPortGfx*Option*` CFuncs. A zero-size scissor must clip everything, and menus issue about 1.5k draws per frame [R, PS3]. `.tex` = 40-byte metadata records + embedded DDS (gh3-r36s `tools/research/tex.py`). |
| **Input** | `WinPortSio*` 0x419A20–0x419D20 (device/control press, binding, keyboard vs DirectInput gamepad). Classes `CButtonInput`, `CThumbStickInput`, `COscillatingInput` (RTTI) [O]. |
| **Frame loop / timing** | `Mlp::Manager::MainLoop` 0x484310 (donnaken15 AssertPoints). Globals: `g_delta` 0x9596BC, `g_gameSpeed1/2` 0x9596B4/B8, `g_renderLockFramerate` 0x95FDCC (CT/FastGH3). Notes are judged per frame, so late frames cost notes [R, PS3]. Hit-window defaults from gh3-r36s `gh3_default_tuning`: early 116 ms, late 100 ms, HOPO 83/83 ms, hammer_on_measure_scale 2.95. `WinPortSetSongSkew`/`WinPortSongHighwaySync` handle the PC A/V calibration. |
| **Threading** | PS3 runs FMOD and Havok as SPU tasks [R]. On PC, Havok is statically linked (`hk*` RTTI, `heap_havok`) [O]. The thread model is not yet observed on PC; look at `CreateThread`/`_beginthreadex` imports and xrefs [I]. |
| **Debug hooks** | `DebugLog(fmt, va_list)` 0x472B50, `LogErrDfnct` 0x4F6500 (a bare `ret`, i.e. stubbed in retail [O]), `PrintStruct` 0x530970, `PrintScriptInfo` 0x5309A0, param formatter 0x532A80. Re-enabling these in the recomp gives script logging for free [I]. |

## 4. Generated data (this pass)

| File | Rows | Producer | Content |
|---|---|---|---|
| `docs/data/cfuncs.tsv` | 1170 (1160 unique VAs) | `tools/extract_cfuncs.py` | `va<TAB>name`, in table order; aliases repeat the VA |
| `docs/data/cmemberfuncs.tsv` | 90 | same | `str_va<TAB>name` (member-function names have no code pointer; they are dispatched by checksum) |
| `docs/data/gh3plus_symbols.tsv` | 659 rows / 510 VAs (171 func, 339 global) | `tools/extract_gh3plus_symbols.py` | `va<TAB>kind<TAB>name<TAB>sources`. Drops 484 mid-function patch/detour sites and 134 addresses outside the image (heap pointers in the CT/GlobalAddresses) |

Both scripts are stdlib-only, run with `python3 -I`, and treat `ref/` as data. `extract_cfuncs.py` finds the table heuristically and checks the count against the call-site getter. `extract_gh3plus_symbols.py` keeps a code address only if it is a plausible function entry: an E8 call target, a CFunc target, a 16-aligned address after CC/C3/90 padding, or an AIF start.

## 5. Acceleration plan (ranked)

Estimated function population: about 28k 16-aligned entries after `int3` padding, of which 9.2k are also direct-call targets [O, heuristic]. It includes statically linked Havok and DemonWare.

| # | Step | Names gained (est.) | Cum. coverage | Effort |
|---|---|---|---|---|
| 1 | Emit `entry <va> CFunc_<Name>` for the 1160 CFunc VAs (one name per VA; alias VA 0x410900 → `CFunc_ReturnTrueStub`) plus the 171 GH3+ functions into SwARc's `lifter.manifest`, and `name <va> <global>` / Ghidra labels for the 339 globals. Write a Ghidra script that reads `cfuncs.tsv` and `gh3plus_symbols.tsv` and runs `createFunction` + `setName` (after the current analysis finishes; don't touch `work/ghidra` mid-run). | 1,240 functions, 339 globals [O] | ~4.5% | hours |
| 2 | **HATRED thunk propagation.** For every named `.text` entry that is `jmp rel32 → HATRED`, name the body `<name>` and the thunk `<name>_thunk`. Do the same for all 1568 thunks, as `hatred_<textva>`, so they stay traceable. Make sure the lifter treats the HATRED bodies as functions: Ghidra will see the `jmp` as a tail call. | doubles the names on thunked functions; 1568 traceable bodies | – | hours |
| 3 | **RTTI recovery** (Ghidra `RecoverClassesFromRTTIScript`, or a small TSV pass over COL → vftable → slots). Gives class names for 1236 vftables, `Class::vfN` for about 4k virtual functions, and constructors/destructors via vftable stores. | ~4,000 [I] | ~18% | 1 day |
| 4 | **QbKey annotation.** Hash the 5831 `debugger_names` plus 250 extra decomp keys, then comment every `push imm32` / `cmp imm32` that matches. This makes the CFunc bodies and their callees readable (which params they read), and it is the basis for step 5. | 0 names, large readability gain | – | hours |
| 5 | **Callee naming from CFuncs** (our own PC analysis; the PS2 decomp only as an AGPL reference for "what this is"). Single-caller callees of `CFunc_X` → `X_impl`. Accessors identified by QbKey-param patterns → `CStruct::GetInteger/GetChecksum/GetString/GetFloat/...`, `CScript::*`, `Mem::*`, `Crc::*` (CRC table 0x95CD28). | ~500–1,500 [I] | ~20–23% | days |
| 6 | **Library ID.** DemonWare via its `.\bd*\*.cpp` assert strings (105 source paths). Havok via `hk*` RTTI plus FLIRT/BSim against a Havok 4.x SDK if one is available. MSVC 2005 static CRT/STL via Ghidra FID (Rich header: VS2005 build 50727). Non-game code needs names more than understanding. | ~2,000–4,000 [I] | ~30–35% | days |
| 7 | **Script cross-reference.** For each CFunc, list its QB call sites from `neversoft-script-library/gh3/pc/base_1.31` (564+ of 1170 used). Prioritise HLE/lifting work on the CFuncs that BetterGH3's `qb/` actually calls, and drop dead ones (e.g. 360 Live). | prioritisation | – | hours |
| 8 | Optional: an Xbox 360 / PS3 debug-prototype build with symbols would give a large name transfer by call-graph matching. AssertPoints' mangled names hint that someone has such symbols. No public symbolized build was found in these repos [O]. | unknown | – | research |

Lifter formats (SwARc `tools/lifter_x86/program.cpp`): `functions.tsv` column 8 is the name (non-`FUN_` names win), the manifest takes `entry|name|replace <va> <name>`, and exports override both. Use `entry` lines for CFuncs, because they are reached only through the table, so Ghidra may not create them as functions. Use `replace` later for HLE'd CFuncs (WinPort*, LoadPak, Printf).

## 6. Engine-level caveats found along the way

- **Never patch a HATRED body address by its `.text` VA.** GH3+ patch sites inside thunked functions (e.g. `BossWaitForAttack` 0xD7EB8C, FMOD getPosition detour 0xD932A4, return addresses 0xD7EC12) are already HATRED VAs [O]. Plugin ports must target whichever copy actually runs.
- Some GH3+ names are guesses or placeholders (`lol3` for `ResetEngine`, `change`, `GCStk`). Prefer the CFunc-table name where they collide; the TSV lists sources for triage.
- CT entries such as `game.exe+…` belong to another game and were skipped. Some `ADDR_*` (0x017B38BD, 0x018C3EB8, 0x0203B372) are heap pointers, not image addresses, and were dropped.
