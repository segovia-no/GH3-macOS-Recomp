# Contributing

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Reporting a problem or an idea
Open an [issue](../../issues/new/choose) and pick **Bug report** or **Feature request**. For bugs, include:
- the commit you built;
- your Mac and macOS version;
- your controller;
- what happened.

For crashes, also attach the log (`~/Library/Logs/Guitar Hero III.log`) and the newest crash report from `~/Library/Application Support/gh3/crashes/`. See the [troubleshooting guide](docs/guides/troubleshooting.md).

Check the open issues first. Never attach game files (`GH3.exe`, `DATA/`, DLLs from the install) or anything built from them.

## Pull requests
Pull requests come from your own fork:
1. Fork the repository and clone your fork.
2. Build it from your own copy of the game: [docs/dev/building.md](docs/dev/building.md). How the pieces fit together is in [docs/dev/architecture.md](docs/dev/architecture.md).
3. Make your change on a branch and test it (below). Then open a pull request against `main`; its template has a short checklist.

Small, focused pull requests are easiest to review. For larger changes, open an issue first so we can agree on the approach.

### Where changes go
| Change | Where |
|---|---|
| Behaviour of a Windows API, DirectX or middleware (Bink, FMOD's DirectSound path, XInput, ...) | SwARc, in `third_party/SwARc`; save it as `patches/swarc-gh3.patch` (`git diff HEAD > ../../patches/swarc-gh3.patch` there, with new files `git add -N`'d first). SwARc's own rules apply: nothing game-specific in it. |
| Lifter fixes (new instructions, function discovery) | SwARc's lifter, same patch. Re-lift (`scripts/setup/lift.sh`) and diff `build/generated` before and after. |
| Game-specific code: replacements of game functions, stubs for the game's DLLs, configuration | `src/`, plus `manifests/overrides.manifest` for `replace`/`entry`/`noentry` lines. Regenerate `manifests/lifter.manifest` with `scripts/dev/gen_manifest.py`. |
| Build, packaging | `scripts/setup/`, `packaging/macos/`, `CMakeLists.txt` |

### Testing
- Play the part you changed, and say in the pull request what you played.
- `scripts/dev/play.sh` runs the current build with its log in `build/logs/play.log`. `scripts/dev/boot.sh [secs]` boots it unattended, without input or focus.
- Native replacements of game functions must give the same bits as the lifted code they replace, which stays in the build as `f_<VA>_lifted`. Add a check mode like `GH3_VERIFY_SKIN=1` in `src/skinning.cpp`, which runs both versions on every call and reports any difference. Play with it and see no mismatches.

### Rules
- **No game content in the repository**: no game files, and nothing generated from them (lifted C++, binaries, symbol exports, screenshots of game art). Addresses, names and facts about the binary are fine.
- Reference projects (GH3+, mods, decompilations; see [docs/notes/01-research.md](docs/notes/01-research.md)) are for reading. Do not copy their code: several have no license or an incompatible one.
- Match the style of the surrounding code; comments explain *why*.
- Update the docs when behaviour, settings or build steps change.

By contributing you agree that your contributions are released under the project's [MIT License](LICENSE).
