"""Stage designs -> build/stage.inc, build/titlestrip.bin

The game builds the scenery at run time from these descriptions (see
gencell in src/game.asm), one 2-dot character column at a time.

Terrain: a list of sections (length in dot columns, ceiling height,
floor height, style).  Heights are in dots (the playfield is 46 dots tall)
and move towards the section's values by one dot per dot column, so changes
make 45-degree slopes.  Keep ceiling + floor <= 32 so there is room to fly.

Events fire when the given character column is built at the right edge of
the screen (12.5 columns per second).  Stage 1 is placed by hand; the other
stages are placed automatically from the terrain (turrets on flat floors and
ceilings, waves aimed at the middle of the gap).
"""
import random
import sys
from pathlib import Path

ROCK, FORT, CRYS, HIVE = 0, 1, 2, 3
E_DART, E_SPIN, E_TURF, E_TURC, E_BOSS = 1, 2, 3, 4, 5

STAGE1 = [
    (120, 0, 0, ROCK), (80, 0, 6, ROCK), (60, 2, 10, ROCK), (40, 4, 6, ROCK),
    (40, 4, 16, ROCK), (30, 4, 8, ROCK), (40, 9, 4, ROCK), (30, 13, 4, ROCK),
    (40, 6, 10, ROCK), (60, 12, 14, ROCK), (40, 15, 12, ROCK), (50, 10, 16, ROCK),
    (60, 4, 6, ROCK), (30, 4, 6, FORT), (60, 8, 10, FORT), (36, 14, 10, FORT),
    (36, 8, 16, FORT), (60, 10, 10, FORT), (40, 5, 5, FORT), (60, 6, 8, ROCK),
    (50, 11, 14, ROCK), (60, 6, 6, ROCK), (90, 2, 2, ROCK),
]
STAGE1_EVENTS = [
    (36, E_DART, 14), (64, E_DART, 28), (92, E_SPIN, 0),
    (120, E_TURF, 0), (140, E_DART, 18), (165, E_TURF, 0),
    (188, E_SPIN, 0), (212, E_TURC, 0), (232, E_DART, 22),
    (262, E_SPIN, 0), (288, E_DART, 22), (316, E_TURF, 0),
    (336, E_TURC, 0), (356, E_DART, 16), (384, E_TURF, 0),
    (404, E_TURC, 0), (424, E_SPIN, 0), (448, E_TURF, 0),
    (460, E_TURC, 0), (480, E_DART, 20), (504, E_SPIN, 0),
    (524, E_TURF, 0), (548, E_DART, 24),
]

STAGE2 = [   # the fortress
    (100, 0, 0, ROCK), (40, 4, 4, FORT), (60, 8, 8, FORT), (40, 14, 6, FORT),
    (40, 6, 14, FORT), (50, 12, 12, FORT), (30, 16, 10, FORT), (30, 10, 16, FORT),
    (40, 6, 6, FORT), (60, 4, 18, FORT), (40, 18, 4, FORT), (60, 10, 10, FORT),
    (60, 14, 14, FORT), (40, 6, 6, FORT), (40, 8, 16, FORT), (40, 16, 8, FORT),
    (60, 8, 12, ROCK), (60, 4, 4, FORT), (40, 12, 4, FORT), (40, 4, 12, FORT),
    (50, 14, 8, FORT), (50, 8, 14, FORT), (40, 4, 18, FORT), (40, 18, 4, FORT),
    (60, 10, 10, FORT), (40, 16, 14, FORT), (60, 6, 6, FORT), (90, 2, 2, FORT),
]
STAGE3 = [   # crystal caves
    (100, 0, 0, ROCK), (60, 0, 8, CRYS), (40, 10, 0, CRYS), (40, 0, 14, CRYS),
    (40, 14, 0, CRYS), (40, 4, 16, CRYS), (40, 16, 4, CRYS), (60, 8, 8, CRYS),
    (40, 12, 16, CRYS), (40, 16, 12, CRYS), (60, 6, 6, CRYS), (50, 10, 18, CRYS),
    (50, 18, 10, CRYS), (40, 6, 14, CRYS), (40, 14, 6, CRYS), (60, 6, 6, ROCK),
    (60, 0, 12, CRYS), (40, 12, 0, CRYS), (40, 2, 18, CRYS), (40, 18, 2, CRYS),
    (40, 6, 18, CRYS), (40, 18, 6, CRYS), (60, 12, 12, CRYS), (40, 8, 8, CRYS),
    (90, 2, 2, CRYS),
]
STAGE4 = [   # inferno: a bit of everything, tighter
    (80, 0, 0, ROCK), (40, 6, 10, ROCK), (40, 14, 14, ROCK), (40, 10, 18, ROCK),
    (40, 18, 10, ROCK), (40, 8, 8, FORT), (40, 14, 14, FORT), (40, 16, 10, FORT),
    (40, 10, 16, FORT), (50, 6, 6, CRYS), (40, 14, 14, CRYS), (40, 18, 10, CRYS),
    (40, 10, 18, CRYS), (60, 12, 12, ROCK), (40, 16, 14, ROCK), (40, 6, 6, ROCK),
    (40, 4, 20, ROCK), (40, 20, 4, ROCK), (40, 12, 16, FORT), (40, 16, 12, FORT),
    (40, 14, 14, FORT), (40, 8, 18, CRYS), (40, 18, 8, CRYS), (50, 15, 15, ROCK),
    (40, 10, 10, FORT), (40, 16, 10, CRYS),
    (40, 6, 6, ROCK), (90, 2, 2, ROCK),
]
STAGE5 = [   # the hive
    (80, 0, 0, ROCK), (60, 4, 8, HIVE), (40, 10, 6, HIVE), (40, 6, 14, HIVE),
    (40, 16, 6, HIVE), (40, 8, 16, HIVE), (50, 14, 14, HIVE), (40, 18, 8, HIVE),
    (40, 8, 18, HIVE), (60, 6, 6, HIVE), (40, 20, 6, HIVE), (40, 6, 20, HIVE),
    (40, 12, 12, HIVE), (40, 16, 16, HIVE), (40, 10, 10, FORT), (40, 16, 12, FORT),
    (40, 12, 16, CRYS), (40, 16, 16, CRYS), (60, 6, 6, HIVE), (40, 18, 12, HIVE),
    (40, 12, 18, HIVE), (40, 16, 16, HIVE), (40, 20, 10, HIVE), (40, 10, 20, HIVE),
    (60, 8, 8, HIVE), (90, 2, 2, HIVE),
]

STAGES = [
    # sections, hand events or None, auto spacing, random seed
    (STAGE1, STAGE1_EVENTS, None, 1),
    (STAGE2, None, 20, 2),
    (STAGE3, None, 17, 3),
    (STAGE4, None, 15, 4),
    (STAGE5, None, 13, 5),
]


def heights(sections):
    """Per dot column (ceiling, floor, style), exactly as the Z80 steps it."""
    c = f = 0
    for n, tc, tf, st in sections:
        for _ in range(n):
            c += (tc > c) - (tc < c)
            f += (tf > f) - (tf < f)
            yield c, f, st


def auto_events(cols, ncells, spacing, seed):
    rnd = random.Random(seed)
    ev, pick = [], 0
    cell = 30
    while cell < ncells - 70:
        x = 2 * cell + 2                       # the column built for this cell
        c, f, _ = cols[x]
        flat_f = all(cols[x + d][1] == f for d in range(-6, 7))
        flat_c = all(cols[x + d][0] == c for d in range(-6, 7))
        gap_mid = (c + (46 - f)) // 2 - 1
        kinds = []
        if flat_f and f >= 4:
            kinds.append(E_TURF)
        if flat_c and c >= 4:
            kinds.append(E_TURC)
        kinds += [E_DART, E_SPIN] if pick % 2 else [E_SPIN, E_DART]
        k = kinds[0] if rnd.random() < 0.7 else rnd.choice(kinds)
        y = max(8, min(30, gap_mid))
        ev.append((cell, k, y if k == E_DART else 0))
        pick += 1
        cell += spacing + rnd.randrange(-3, 4)
    return ev


out = Path(sys.argv[1])
inc = ["; generated by tools/gen_stage.py"]
table = ["stagetab:"]
all_cols = []
for i, (sections, hand, spacing, seed) in enumerate(STAGES, 1):
    cols = list(heights(sections))
    all_cols.append(cols)
    ncells = len(cols) // 2
    boss_at = ncells - 45 + 20
    ev = hand if hand else auto_events(cols, ncells, spacing, seed)
    events = sorted(ev + [(boss_at, E_BOSS, 0)])
    assert all(col < ncells for col, _, _ in events)
    assert len({col for col, _, _ in events}) == len(events), "two events in one column"
    inc.append(f"stage{i}_seg:")
    for n, tc, tf, st in sections:
        assert 0 < n < 256 and tc + tf <= 32, (i, n, tc, tf)
        inc.append(f"        DB {n},{tc},{tf},{st}")
    inc.append("        DB 0")
    inc.append(f"stage{i}_ev:")
    for col, t, p in events:
        inc.append(f"        DW {col}")
        inc.append(f"        DB {t},{p}")
    inc.append("        DW 0FFFFh")
    # rows whose colours can ever change while scrolling
    flags = [0] * 23
    for c, f, st in cols:
        for r in range(23):
            if 2 * r < c + 1 or 2 * r + 1 >= 46 - f - 1:
                flags[r] = 1
    inc.append(f"stage{i}_rf:")
    inc.append("        DB " + ",".join(map(str, flags)))
    table.append(f"        DW stage{i}_seg,stage{i}_ev,stage{i}_rf")
    print(f"stage {i}: {ncells} cells ({ncells / 12.5:.0f} s), {len(events)} events, "
          f"boss at column {boss_at}, colour rows {sum(flags)}/23")
(out / "stage.inc").write_text("\n".join(inc + table) + "\n")

# ---- a strip of stage 1 scenery for the title screen (rows 18..22)
def dot(col, y, x):
    c, f, st = col
    y0 = 46 - f
    if y < c:
        d = c - 1 - y
    elif y >= y0:
        d = y - y0
    else:
        return False, 0
    cls = 1 if d < 3 else 2
    if d < 2:
        return True, cls
    if st == ROCK:
        return (x + y) % 2 == 0, cls
    if st == FORT:
        return y % 4 == 0 or x % 8 == 0, cls
    if st == CRYS:
        return (x - y) % 4 == 0, cls
    return (x ^ y) & 2 == 0, cls

ATTR = {ROCK: [0x70, 0x60, 0x20], FORT: [0x70, 0x71, 0x51], CRYS: [0x70, 0x50, 0x30],
        HIVE: [0x70, 0x40, 0x64]}
cols = all_cols[0]
start = 260                     # the volcano
strip_c, strip_a = bytearray(), bytearray()
for r in range(18, 23):
    for cc in range(40):
        xl, xr = start + 2 * cc, start + 2 * cc + 1
        bits, cls = 0, 0
        for bit, (x, y) in enumerate([(xl, 2 * r), (xr, 2 * r), (xl, 2 * r + 1), (xr, 2 * r + 1)]):
            lit, k = dot(cols[x], y, (x + 1) & 255)
            bits |= lit << bit
            cls = max(cls, k)
        strip_c.append(0xF0 | bits)
        strip_a.append(ATTR[cols[xl][2]][cls])
(out / "titlestrip.bin").write_bytes(bytes(strip_c + strip_a))
