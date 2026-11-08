# GH3 PC → native macOS: research ledger

Status: survey phase (2026-11-08). Observed = verified locally; Reported = from web research, not verified.

## Target (observed, local `Guitar Hero III/`: the BetterGH3 installation used for development)

- `GH3.exe` — PE32 i386, MSVC 2005 (MSVCR80/MSVCP80), not stripped, entry 0x68f03c.
  - Sections: `.text` 0x401000 (4.6 MB), `.rdata`, `.data` (4 MB virtual), `.rsrc`, **`HATRED`** 0xd7a000 (0x36000, executable).
  - `HATRED`: a second executable section added after the original build. It holds live code, which `.text` calls into (1,621 branches).
  - GH3+ loader stub patched into `.text` slack at **0x897d40**: `LoadLibraryA("PLUGINS\core.dll")`, `exit(1)` on failure. Called from startup at **0x4016de**.
- Imports needing replacement on macOS: d3d9 + d3dx9_35 (8 funcs), fmodex (53), binkw32 (21), WS2_32 (26), DINPUT8, XINPUT1_3, WINMM, Aspyr `AWL.dll` (20: paths, config, window), `mac3r.dll` (MassiveAdClient3 — stub), `IntelLaptopGaming.dll` (battery/wifi — stub).
- Third-party DLLs in release:
  - `D3D9.dll` = dgVoodoo (D3D9→D3D11).
  - `dinput8.dll` = "XDinput" XInput→DInput wrapper (pdb `C:\Users\sanjay\...\XDinput`). Source not found.
  - `wh.dll` = Rust, hooks `gethostbyname` (online server redirect). Source not found.
  - `xinput1_*.dll`, `hidapi.dll` — controller stack. Source not found.
- Plugins (`PLUGINS/`): `core.dll` (GH3+ loader + Qb types), `BetterGH3.dll`, `FastGH3.dll`, `TapHopoChord.dll`, `NoteLimitFix.dll`, `SongLimitFix.dll`.
- Data: 5.4 GB, Xbox 360 formats (`*.pak.xen`, `*.fsb.xen`, `*.bik.xen`). Platform-neutral to the engine; carries over unchanged.

## BetterGH3 source (observed, cloned to `ref/BetterGH3`, gitignored)

- https://github.com/lunalawl/BetterGH3 — no license file.
- `GH3Plus/` — vendored GH3+: `src/core` (loader, `Patcher`: WriteJmp/WriteCall/WriteInt32/WriteNOPs on absolute addresses), `src/gh3` (RE'd engine types, `GH3GlobalAddresses.h`, `GH3Functions.h`, `GH3Keys.h`), `gh3.CT` (Cheat Engine address map).
- Plugin patch-site counts (grep of Write*/asm/naked): tapHopoChord 144, FastGH3 60, BetterGH3 8, noteLimit 6, forceTapNotes 5, songLimit 4. Small, enumerable.
- `qb/` — 387 decompiled/modified `.q` scripts; built with Honeycomb (`honeycomb pak compile`). Bulk of BetterGH3's behavior lives here, as data.
- Upstream GH3+: `ref/GH3-Plus` (https://github.com/ExileLord/GH3-Plus, 2018).

## Prior art (reported)

| Project | Relevance |
|---|---|
| SwARc — github.com/JTM-rootstorm/SwARc | PE32 static recompiler → C++, SDL3, macOS arm64/Metal, exact x87, SEH, DInput8/XInput/Bink HLE. D3D9 in progress. MIT. **Primary candidate.** |
| sp00nznet/gh3 + ps3recomp | GH3 PS3 static recomp, reaches gameplay (Windows). ps3recomp runtime builds on macOS/Metal. Alt path. |
| luisxl15/Guitar-Hero-3-Recomp- (ReXGlue) | GH3 Xbox 360 recomp; no macOS. Several clones — vet carefully. |
| Ketbome/gh3-decomp | GH3 PS2 matching decomp, ~29%. AGPL; reference only. |
| fernandoalves25/gh3-r36s | Clean-room GH3 player (C/SDL2/GLES2) reading PC DATA. MIT. Format/gameplay reference + fallback. |
| AddyMills/Honeycomb-CLI | QB/PAK compiler used by BetterGH3 build. .NET, runs on macOS. |
| sp00nznet/pcrecomp | PE32→C toolkit; no D3D9/DInput/FMOD. Technique reference. |

Avoid: leaked THUG source (legally tainted).

## Candidate plan (inferred)

1. Spike: build SwARc on macOS, run its pipeline on GH3.exe, measure function coverage / indirect-call gaps / HATRED handling.
2. HLE layer: D3D9+D3DX9 (contribute to SwARc), FMOD Ex (lift fmodex.dll or HLE on FSB decoder), AWL, stubs for mac3r/IntelLaptopGaming, WinSock→BSD.
3. Port plugins as native overrides of lifted functions at their documented addresses (core.dll loader becomes compile-time registration).
4. Keep QB/PAK pipeline unchanged.

## Open questions

- Exact contents/role of HATRED section (OEP stub? import fixups? deobfuscated code?).
- SwARc D3D9 maturity; performance of lifted x87 code on arm64.
- Controller path on macOS (guitar HID → GH3 input) — replace XDinput/hidapi stack.
- Online (`wh.dll`) — likely drop or reimplement as hostname remap.
