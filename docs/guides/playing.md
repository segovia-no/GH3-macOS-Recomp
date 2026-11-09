# Playing

## Controls

### Keyboard and mouse
The game starts with GH3's PC **"Keyboard/Mouse"** layout:

| Action | Key |
|---|---|
| Frets: green, red, yellow, blue, orange | `1` `2` `3` `4` `5` |
| Strum down / menu down | **left mouse button** |
| Strum up / menu up | **right mouse button** (two-finger click on a trackpad) |
| Star Power | Right Shift |
| Whammy | Right Ctrl |
| Back / pause | Backspace / Esc |
| Confirm (menus) | green (`1`) or Return |

Every note has to be strummed while its fret is held, except hammer-ons and pull-offs.

For a keyboard-only layout, go to the options menu → button binding → **"Reset to Default Keyboard"**:

| Action | Key |
|---|---|
| Frets: green, red, yellow, blue, orange | `V` `C` `X` `Z` Left Shift |
| Strum up / menu up | Right Shift |
| Strum down / menu down | `/` |
| Star Power | Space |
| Whammy | Right Ctrl |

Any action can be rebound in the same menu. Bindings are saved in `~/Library/Application Support/gh3/AspyrConfig.ini`.

### Xbox 360 wireless guitars and gamepads
Plug the **Xbox 360 Wireless Receiver for Windows** into your Mac; clones work too. macOS has no driver for it, so the game reads it directly over USB. Nothing needs to be installed, and no system settings change.

1. **Quit Steam** if it is running. Steam takes over the receiver, and the game then waits until it is free.
2. Start the game; it finds the receiver within 2 seconds, even if you plug it in later.
3. Pair: press the receiver's button (its light blinks), then hold the connect button on the guitar or gamepad.
4. The controller's ring light shows its player number. A guitar is recognised as a guitar and needs no setup in the game. Frets, strum bar and whammy have been tested; tilt for Star Power has not been checked yet.

Up to four controllers can connect. Rumble is sent to gamepads (not tested yet).

### Other gamepads
Controllers that SDL supports (Xbox One/Series, DualShock 4, DualSense, ...) appear to the game as XInput gamepads. This path has not been tested with GH3 yet.

## Window and quitting
- In a window, the mouse pointer stays free: you can use the desktop and click the strum buttons in the window. In fullscreen (`GH3_FULLSCREEN=desktop` or `exclusive`), the game captures the pointer as it does on Windows.
- **Quit** from the Dock, **⌘Q** or the window's close button ends the game right away. Settings are saved as you change them; quit from the game's own menu if you are in the middle of something you want saved.

## Audio calibration
At 0 ms the music is in sync with the notes on a Mac's built-in output. Leave both offsets at 0 unless you hear a difference (Bluetooth headphones add their own delay).

With a BetterGH3 installation (the recommended starting point), the calibration menu has **Audio** and **Video** offsets instead of the game's original audio lag setting (options menu → calibrate lag):
- **Audio** moves the notes and the hit timing together, relative to the music. Use it when the music sounds early or late compared with the notes and your hits.
- **Video** moves only where the notes are drawn.
- The music itself never moves. The offsets apply when a song starts, so **restart the song after changing them**.

## Settings
In-game options (resolution, quality, crowd, ...) are saved to `~/Library/Application Support/gh3/AspyrConfig.ini`.

**Window size:** by default the window is the largest 16:9 size that fits in 85% of your desktop. To choose another size, set it in the game's options or in `AspyrConfig.ini` (`Video.Width`, `Video.Height`).

**Switches** for the app, given as environment variables. Finder doesn't pass these, so launch with `open --env`:
```sh
open --env GH3_FULLSCREEN=desktop "build/Guitar Hero III.app"
```

| Variable | Effect |
|---|---|
| `GH3_FULLSCREEN=window\|desktop\|exclusive` | windowed (default), borderless fullscreen, or exclusive fullscreen |
| `GH3_RESOLUTION=WxH` | the window size when `AspyrConfig.ini` has none |
| `GH3_VSYNC=0` | turn vsync off |
| `GH3_FPS_REPORT=1` | log the frame rate once a second (to `~/Library/Logs/Guitar Hero III.log`) |

Saves and settings are in `~/Library/Application Support/gh3`; the Windows paths the game uses are mapped under `drive_c/` there.
