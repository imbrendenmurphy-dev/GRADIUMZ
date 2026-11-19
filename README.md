# GRADIUMZ

An original side-scrolling shoot-'em-up for the **Sharp MZ-700** (PAL), written in Z80 assembly.

- Smooth 1-dot scrolling on an 80×50 dot playfield built from the international
  character ROM's quarter-block characters
- Five stages (Volcano, Fortress, Crystal Caves, Inferno, Hive), built at run time
  from compact stage descriptions, each ending in a boss
- Power-up bar: SPEED, MISSL, SPRED, BEAM, DRONE, SHLD
- Parallax starfield, sound effects on the 8253, title screen, attract mode with
  an autopilot demo, and a trainer (stage select, infinite lives, invincibility)

## Play

Load **`release/GRADIUMZ.MZT`** on a real MZ-700 (e.g. with a UniCMT) or in an
emulator such as MZ700WIN. It loads at `1200h` and starts automatically.

| Key | Action |
|---|---|
| Cursor keys | Move |
| Space | Fire |
| Shift or Z | Take the highlighted power-up |

On the title screen: **1–5** choose the starting stage, **T** infinite lives,
**I** invincible.

## Build

Requirements (Windows):

- Python 3 (`py` launcher)
- [sjasmplus 1.24.0](https://github.com/z00m128/sjasmplus/releases/tag/v1.24.0),
  unzipped so that `tools/sjasmplus/sjasmplus-1.24.0.win/sjasmplus.exe` exists

Then run `build.bat`. It generates the stage, sprite and title data and writes
`build/GRADIUMZ.MZT`.

The preview scripts in `tools/` (`preview_title.py`, `preview.py`) render screens
with the real character ROM. The ROM is not included in this repository (it is
Sharp's copyright); put your own dump at `rom/mz700fon.int` to use them.

## Layout

| Path | What |
|---|---|
| `src/game.asm` | The game |
| `src/scrolltest.asm` | The original display-engine test |
| `tools/gen_stage.py` | Stage terrain and enemy events |
| `tools/gen_sprites.py` | Sprites, boss tiles and lookup tables |
| `tools/gen_title.py` | Title screen |
| `tools/mkmzt.py` | Wraps a binary in an MZ-700 tape header |
