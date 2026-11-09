# Documentation

## Guides (players)
- [guides/install.md](guides/install.md): requirements, building the app from your copy, updating, uninstalling.
- [guides/playing.md](guides/playing.md): controls (keyboard, mouse, Xbox 360 guitars), audio calibration, settings.
- [guides/troubleshooting.md](guides/troubleshooting.md): logs, crash reports, controllers, resetting settings.

## Developer docs
- [dev/building.md](dev/building.md): the build pipeline step by step, developer tools and switches.
- [dev/architecture.md](dev/architecture.md): how the recompilation works, the repository layout, where changes go.

## Technical notes
- [notes/01-research.md](notes/01-research.md): prior art. Existing GH3 reverse-engineering, mod and port projects, and what each offers this port.
- [notes/02-decomp-crossref.md](notes/02-decomp-crossref.md): naming PC `GH3.exe` from the other projects (the QB C-function table, RTTI, GH3+ symbols), with each project's license.
- [notes/03-porting-log.md](notes/03-porting-log.md): the development log. Lifter coverage, the boot sequence, the CRT, AWL, Bink, input, performance (SSE fast paths, native skinning), audio, controllers, packaging.
- [notes/04-builder-spike.md](notes/04-builder-spike.md): an experimental builder app that builds the game with only Apple's Command Line Tools, and what remains before it can be shared.
- [data/](data/): tables extracted from the executable:
  - `cfuncs.tsv`, `cmemberfuncs.tsv`: the QB script-function tables;
  - `gh3plus_symbols.tsv`: addresses named by GH3+ and related projects;
  - `import_coverage.tsv`: which imports SwARc implements.

## Source artifact
| Item | Value |
|---|---|
| Game | Guitar Hero III: Legends of Rock, PC 1.3.1 (Aspyr port). Tested with the `GH3.exe` from a BetterGH3 installation, which includes the GH3+ loader. |
| Executable | `GH3.exe`, PE32 i386, MSVC 2005, image base 0x400000, entry 0x68F03C, a second executable section (`HATRED`) besides `.text` |
| SHA-256 | `4322a71ddda6c3c971ae2162bdc62299e4cf0c0bc6f6ee9032bcfdccb8e5e804` |
| Lifted with it | `fmodex.dll` (FMOD Ex, UPX-unpacked; packed SHA-256 `6340182911e7213ddcc26372b38dc4aaf1d91c722dd42e64336987dd24beafbb`), `msvcr80.dll`/`msvcp80.dll` 8.0.50727.6195 (Microsoft's VC++ 2005 SP1 redistributable) |
| Data | Xbox 360 format (`.pak.xen`, `.fsb.xen`, Bink 1.9 `.bik.xen`) |

The addresses in `manifests/` and `src/` belong to this executable, and `scripts/setup/prepare_inputs.sh` checks the hashes. Game files are never committed (see `.gitignore`).

## Status
**Playable on macOS (Apple Silicon)** as of 2026-11-09:
- intro movies, menus, songs;
- 120 fps (vsync-capped) in gameplay;
- audio through CoreAudio, with working calibration offsets;
- keyboard, mouse, SDL gamepads (untested), and Xbox 360 wireless guitars through the receiver (read over libusb, no driver);
- a double-clickable app bundle.

Not yet:
- the GH3+ plugin loader is replaced by a stub, so plugins don't load;
- online play is untested;
- `D3DXSaveTextureToFileInMemory` and `SHFileOperationA` are not implemented (not reached in play so far).
