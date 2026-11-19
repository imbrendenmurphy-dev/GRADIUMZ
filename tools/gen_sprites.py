"""Generate sprite graphics and lookup tables.

Each sprite is up to 7x3 dots.  For every sprite four pre-shifted variants
(x odd/even, y odd/even) are stored, each 4x2 character cells = 8 bytes of
quarter-block bits (0 = transparent cell).  Variant index = 2*(y&1) + (x&1).

Outputs (into the build folder):
  sprites.bin  - 32 bytes per sprite
  sprites.inc  - G_<NAME> EQU offsets
  tables.inc   - row40, row296 and sine tables
"""
import math
import sys
from pathlib import Path

SPRITES = {
    "SHIP":  ["XXX....",
              ".XXXXXX",
              "XXX...."],
    "SHOT":  ["XXX"],
    "SHOTU": ["..X",
              ".X.",
              "X.."],
    "DART":  ["..XXX",
              "XXXX.",
              "..XXX"],
    "SPIN0": ["X...X",
              ".XXX.",
              "X...X"],
    "SPIN1": ["..X..",
              "XXXXX",
              "..X.."],
    "CAPS":  [".XXX.",
              "XXXXX",
              ".XXX."],
    "EXP0":  [".X.X.",
              "X.X.X",
              ".X.X."],
    "EXP1":  ["X...X",
              "..X..",
              "X...X"],
    "EXP2":  ["X.X.X",
              ".....",
              "X.X.X"],
    "EBUL":  ["XX"],
    "BEAM":  ["XXXXXXX"],
    "MISS":  ["XX",
              "XX"],
    "DRONE": ["XXX",
              "X.X",
              "XXX"],
    "SHLD":  ["X.",
              ".X",
              "X."],
    "TURF":  ["X...X",            # floor turret
              ".XXX.",
              "XXXXX"],
    "TURC":  ["XXXXX",            # ceiling turret
              ".XXX.",
              "X...X"],
}

# Boss: 21x15 dots, cut into 3x5 tiles of 7x3, each tile one colour.
BOSS = [
    "XXXXX................",
    "..XXXX...............",
    "....XXXXXX....XXX....",
    "......XXXXXXXXXXXXX..",
    ".....XXX.......XXXXXX",
    "XXX.XX...XXXX...XXXXX",
    "..XXX...XX..XX..XXXX.",
    "..XXX...XX..XX..XXXX.",
    "XXX.XX...XXXX...XXXXX",
    ".....XXX.......XXXXXX",
    "......XXXXXXXXXXXXX..",
    "....XXXXXX....XXX....",
    "..XXXX...............",
    "XXXXX................",
    ".....................",
]
BLUE, RED, MAGENTA, GREEN, CYAN, YELLOW, WHITE = 1, 2, 3, 4, 5, 6, 7
def palette(claw, hull):
    # per tile row, per tile column; the middle tile is the core (drawn
    # pulsing by the game, so its entry here is unused)
    return [[claw, hull, hull], [claw, hull, hull], [hull, MAGENTA, hull],
            [claw, hull, hull], [claw, hull, hull]]
BOSS_PALETTES = [palette(WHITE, RED), palette(CYAN, BLUE),
                 palette(MAGENTA, CYAN), palette(YELLOW, RED), palette(YELLOW, GREEN)]
for ty in range(5):
    for tx in range(3):
        SPRITES[f"BOSS{ty * 3 + tx}"] = [row[tx * 7:tx * 7 + 7] for row in BOSS[ty * 3:ty * 3 + 3]]

out = Path(sys.argv[1])
blob = bytearray()
inc = []
for name, art in SPRITES.items():
    assert len(art) <= 3 and all(len(r) <= 7 for r in art), name
    inc.append(f"G_{name} EQU {len(blob)}")
    for dy in (0, 1):
        for dx in (0, 1):
            canvas = [[False] * 8 for _ in range(4)]
            for y, row in enumerate(art):
                for x, ch in enumerate(row):
                    if ch == "X":
                        canvas[y + dy][x + dx] = True
            for cr in range(2):
                for cc in range(4):
                    t, b = canvas[2 * cr], canvas[2 * cr + 1]
                    blob.append(t[2 * cc] | t[2 * cc + 1] << 1 | b[2 * cc] << 2 | b[2 * cc + 1] << 3)

(out / "sprites.bin").write_bytes(bytes(blob))
(out / "sprites.inc").write_text("\n".join(inc) + "\n")

ROWS = 23
tab = ["row40:"] + [f"        DW {r * 40}" for r in range(ROWS)]
tab += ["row296:"] + [f"        DW {r * 296}" for r in range(ROWS)]
sine = [round(7 * math.sin(2 * math.pi * i / 32)) & 0xFF for i in range(32)]
tab += ["sine:", "        DB " + ",".join(str(v) for v in sine)]
tab += ["bosscol:"] + ["        DB " + ",".join(f"{c << 4}" for row in p for c in row)
                       for p in BOSS_PALETTES]
(out / "tables.inc").write_text("\n".join(tab) + "\n")
print(f"sprites.bin {len(blob)} bytes ({len(SPRITES)} sprites)")
