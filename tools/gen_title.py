"""Build the title screen body (screen rows 1..23) -> build/title.bin

title.bin = 920 character codes followed by 920 colour attributes.
Rows 0 (score line) and 24 (power-up bar) are drawn by the game itself.
"""
import random
import sys
from pathlib import Path

out = Path(sys.argv[1])
ROWS, COLS = 23, 40
STRIDE, BLOCK = 296, 23 * 296
BLACK, BLUE, RED, MAGENTA, GREEN, CYAN, YELLOW, WHITE = range(8)
random.seed(1982)

LOGO = {
    "G": [".XXXXX.", "XX...XX", "XX.....", "XX.....", "XX..XXX",
          "XX...XX", "XX...XX", "XX...XX", ".XXXXX."],
    "R": ["XXXXXX.", "XX...XX", "XX...XX", "XX...XX", "XXXXXX.",
          "XX.XX..", "XX..XX.", "XX...XX", "XX...XX"],
    "A": ["..XXX..", ".XX.XX.", "XX...XX", "XX...XX", "XXXXXXX",
          "XX...XX", "XX...XX", "XX...XX", "XX...XX"],
    "D": ["XXXXX..", "XX..XX.", "XX...XX", "XX...XX", "XX...XX",
          "XX...XX", "XX...XX", "XX..XX.", "XXXXX.."],
    "I": ["XX"] * 9,
    "U": ["XX...XX"] * 8 + [".XXXXX."],
    "M": ["XX.....XX", "XXX...XXX", "XXXX.XXXX", "XX.XXX.XX", "XX..X..XX",
          "XX.....XX", "XX.....XX", "XX.....XX", "XX.....XX"],
    "Z": ["XXXXXXX", ".....XX", "....XX.", "...XX..", "..XX...",
          ".XX....", "XX.....", "XX.....", "XXXXXXX"],
}
WORD, GAP = "GRADIUMZ", 2
LOGO_COLOURS = [YELLOW, YELLOW, RED, RED, MAGENTA]   # body rows 3..7

TEXT = {  # screen row: (text, colour, column or None to centre)
    10: ("A SHOOT EM UP FOR THE SHARP MZ700", WHITE, None),
    12: ("PUSH SPACE KEY", YELLOW, None),
    14: ("CURSOR KEYS    MOVE", WHITE, 10),
    15: ("SPACE          FIRE", WHITE, 10),
    16: ("SHIFT OR Z     POWER UP", WHITE, 10),
    17: ("", CYAN, 0),        # trainer line, drawn by the game
    18: ("DART 100  SPINNER 200  CAPSULE 500", CYAN, None),
}

def dcode(ch):
    if "A" <= ch <= "Z":
        return ord(ch) - 0x40
    if "0" <= ch <= "9":
        return ord(ch) - 0x10
    assert ch == " ", ch
    return 0

chars = [[0] * COLS for _ in range(ROWS)]
attrs = [[WHITE << 4] * COLS for _ in range(ROWS)]
used = [[False] * COLS for _ in range(ROWS)]

# ---- logo in dots
dots = [[False] * 80 for _ in range(46)]
width = sum(len(LOGO[c][0]) for c in WORD) + GAP * (len(WORD) - 1)
x0, y0 = (80 - width) // 2, 6
x = x0
for c in WORD:
    for yy, row in enumerate(LOGO[c]):
        for xx, ch in enumerate(row):
            if ch == "X":
                dots[y0 + yy][x + xx] = True
    x += len(LOGO[c][0]) + GAP
for r in range(3, 8):
    for col in range(COLS):
        t, b = dots[2 * r], dots[2 * r + 1]
        chars[r][col] = 0xF0 | t[2 * col] | t[2 * col + 1] << 1 | b[2 * col] << 2 | b[2 * col + 1] << 3
        attrs[r][col] = LOGO_COLOURS[r - 3] << 4
        used[r][col] = True

# ---- text
for srow, (txt, colour, col) in TEXT.items():
    r = srow - 1
    if col is None:
        col = (COLS - len(txt)) // 2
    for i, ch in enumerate(txt):
        chars[r][col + i] = dcode(ch)
        attrs[r][col + i] = colour << 4
    for c in range(COLS):
        used[r][c] = True

# ---- a strip of stage 1 scenery (rows 18..22, from tools/gen_stage.py)
strip = (out / "titlestrip.bin").read_bytes()
for i, r in enumerate(range(18, 23)):
    for c in range(COLS):
        chars[r][c] = strip[i * 40 + c]
        attrs[r][c] = strip[200 + i * 40 + c]
        used[r][c] = True

# ---- stars in the empty space
for r in range(ROWS):
    for c in range(COLS):
        if not used[r][c] and random.random() < 0.06:
            chars[r][c] = 0xF0 | (1 << random.randrange(4))
            attrs[r][c] = (CYAN if random.random() < 0.3 else WHITE) << 4

blob = bytes(v for row in chars for v in row) + bytes(v for row in attrs for v in row)
(out / "title.bin").write_bytes(blob)
print(f"title.bin {len(blob)} bytes, logo {width} dots wide")
