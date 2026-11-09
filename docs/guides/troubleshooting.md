# Troubleshooting

## Where things are
| What | Where |
|---|---|
| Log of the last run of the app | `~/Library/Logs/Guitar Hero III.log` |
| Crash reports (one file per crash, with a backtrace) | `~/Library/Application Support/gh3/crashes/` |
| Settings and key bindings | `~/Library/Application Support/gh3/AspyrConfig.ini` |
| Saves (the game's Windows paths) | `~/Library/Application Support/gh3/drive_c/` |
| The game folder the app runs | `~/Library/Application Support/gh3/game` (links to your game folder) |
| Setup logs | `build/logs/` in this repository |

When reporting a problem, attach the log and the newest crash report. See [CONTRIBUTING.md](../../CONTRIBUTING.md).

## Setup
- **"GH3.exe: unexpected SHA-256"**: the build is made for one specific `GH3.exe`, and the addresses in `manifests/` and `src/` belong to it. Other versions of the executable (for example an unmodified 1.3.1 without the GH3+ loader) are not supported yet.
- **"third_party/SwARc has local changes and is not at …"**: the SwARc checkout was edited, or comes from an older version of this project (the SwARc patch). Delete `third_party/SwARc` and run `./setup.sh` again.
- **The build fails**: see `build/logs/build.log`. The first build compiles very large generated files; give it time and memory.

## Starting the game
- **The app quits right away**: look at the end of `~/Library/Logs/Guitar Hero III.log`. A `FATAL` line names what was missing. "lifted DLL ... cannot open" means the game folder links are gone, for example because the game folder moved. Run `packaging/macos/make_app.sh` again (or `./setup.sh --game <new place>`).
- **The window opens behind other windows / the keyboard doesn't reach it**: start the app from Finder or with `open`, not by running the binary inside it. A binary started from a terminal never becomes the active app on macOS.

## Controllers
- **The receiver isn't found**: quit Steam. Check that macOS sees it: `system_profiler SPUSBDataType | grep -i -A3 xbox`. Try another port or adapter.
- **The receiver is found but nothing connects**: pair again (receiver button, then the controller's connect button). To see every packet from the receiver, run the development launcher with tracing: `GH3_X360RX_TRACE=1 scripts/dev/play.sh`. The packets go to `build/logs/play.log`.
- **Keyboard strum doesn't work**: in the default layout, strum is on the mouse buttons. See [playing.md](playing.md#keyboard-and-mouse) for the keyboard-only layout.

## Audio
- **The music is out of sync with the notes**: see [audio calibration](playing.md#audio-calibration). Restart the song after each change.
- **No sound**: check that the log has `audio: 48000 Hz stereo on SDL driver 'coreaudio'`, and check the macOS output device.

## Resetting
- Settings and bindings: delete `~/Library/Application Support/gh3/AspyrConfig.ini`.
- Everything (settings, saves, crash reports): delete `~/Library/Application Support/gh3`. Then run `packaging/macos/make_app.sh` to recreate the game links.
