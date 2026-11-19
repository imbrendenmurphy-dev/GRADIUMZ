"""Generate the scroll-test level and ship graphics.

Screen model: the 40x25 text screen with quarter-block characters F0-FF
gives an 80x50 grid of dots.  Code = F0 + TL + 2*TR + 4*BL + 8*BR
(verified against mz700fon.int).

Playfield = 23 character rows (46 dot rows) x a looping map of 256 cells
(512 dot columns).

level.bin layout (three blocks, each 23 rows x STRIDE bytes):
  CHR0  char codes, even dot offset
  CHR1  char codes, odd dot offset (shifted one dot left)
  COL   colour attributes (fg<<4 | bg), per cell
STRIDE is 296 = 256 + 40, so after copying 40 bytes of a row the next
row starts exactly 256 bytes further on (one INC H in the blitter), and
any offset 0..255 can be copied without wrapping.
"""
import math
import random
import sys
from pathlib import Path

ROWS = 23
DROWS = ROWS * 2
MAPW = 256           # cells
DOTW = MAPW * 2      # dot columns
STRIDE = MAPW + 40

BLACK, BLUE, RED, MAGENTA, GREEN, CYAN, YELLOW, WHITE = range(8)

random.seed(700)

# ---- terrain heights (periodic so the map loops seamlessly) -------------
def wave(x, parts):
    return sum(a * math.sin(2 * math.pi * (k * x / DOTW) + ph) for a, k, ph in parts)

ceil_h = []
floor_h = []
for x in range(DOTW):
    c = 5 + wave(x, [(3, 3, 0.0), (1.5, 11, 1.0), (1.0, 23, 2.0)])
    f = 7 + wave(x, [(4, 2, 0.5), (2, 9, 2.5), (1.0, 31, 0.3)])
    ceil_h.append(max(1, int(round(c))))
    floor_h.append(max(2, int(round(f))))

dots = [[False] * DOTW for _ in range(DROWS)]
depth = [[99] * DOTW for _ in range(DROWS)]   # dots below/above surface
for x in range(DOTW):
    for y in range(ceil_h[x]):
        d = ceil_h[x] - 1 - y
        dots[y][x] = (d < 2) or ((x + y) % 2 == 0)    # solid skin, textured core
        depth[y][x] = d
    for i in range(floor_h[x]):
        y = DROWS - 1 - i
        d = floor_h[x] - 1 - i
        dots[y][x] = (d < 2) or ((x + y) % 2 == 0)
        depth[y][x] = d

stars = set()
for _ in range(70):
    x, y = random.randrange(DOTW), random.randrange(DROWS)
    if depth[y][x] == 99:
        dots[y][x] = True
        stars.add((x, y))

# ---- cells -----------------------------------------------------------------
def cell_code(cx_dot, r):
    """cx_dot = dot column of the cell's left half."""
    l, rr = cx_dot % DOTW, (cx_dot + 1) % DOTW
    y0, y1 = 2 * r, 2 * r + 1
    return (0xF0 | dots[y0][l] | dots[y0][rr] << 1
            | dots[y1][l] << 2 | dots[y1][rr] << 3)

def cell_colour(c, r):
    xs = [(2 * c) % DOTW, (2 * c + 1) % DOTW]
    ys = [2 * r, 2 * r + 1]
    ds = [depth[y][x] for y in ys for x in xs]
    if min(ds) < 99:
        fg = YELLOW if min(ds) < 3 else RED
    else:
        # sky colour is constant along a row, so rows of open sky never
        # need their colours redrawn while scrolling
        fg = CYAN if r % 3 == 1 else WHITE
    return fg << 4 | BLACK

chr0, chr1, col = bytearray(), bytearray(), bytearray()
for r in range(ROWS):
    for j in range(STRIDE):
        c = j % MAPW
        chr0.append(cell_code(2 * c, r))
        chr1.append(cell_code(2 * c + 1, r))
        col.append(cell_colour(c, r))

out = Path(sys.argv[1])
(out / "level.bin").write_bytes(bytes(chr0 + chr1 + col))

# rowflags: 1 = this row's colours vary along the map and must be redrawn
flags = bytes(int(len(set(col[r * STRIDE:r * STRIDE + MAPW])) > 1) for r in range(ROWS))
(out / "rowflags.bin").write_bytes(flags)
print("colour rows to redraw:", sum(flags), "of", ROWS)

# ---- ship: 6x3 dots, four sub-cell variants of 4x2 cells ---------------
SHIP = ["XXX...",
        ".XXXXX",
        "XXX..."]
gfx = bytearray()
for dy in (0, 1):
    for dx in (0, 1):
        canvas = [[False] * 8 for _ in range(4)]
        for y, row in enumerate(SHIP):
            for x, ch in enumerate(row):
                if ch == "X":
                    canvas[y + dy][x + dx] = True
        for cr in range(2):
            for cc in range(4):
                v = (canvas[2 * cr][2 * cc] | canvas[2 * cr][2 * cc + 1] << 1
                     | canvas[2 * cr + 1][2 * cc] << 2 | canvas[2 * cr + 1][2 * cc + 1] << 3)
                gfx.append(v)
(out / "ship.bin").write_bytes(bytes(gfx))
print(f"level.bin {len(chr0) * 3} bytes, ship.bin {len(gfx)} bytes")
