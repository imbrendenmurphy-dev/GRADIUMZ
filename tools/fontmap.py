"""Analyse the MZ-700 character generator ROM.

Finds the 2x2 quarter-block glyphs (4x4 pixel quadrants fully on/off)
and writes a full glyph dump to build/fontdump.txt.
"""
import sys
from pathlib import Path

rom = Path(sys.argv[1]).read_bytes()
out = Path(sys.argv[2])
assert len(rom) == 4096

def quad_pattern(g):
    # bit 3=TL 2=TR 1=BL 0=BR ; returns None if not a pure quadrant glyph
    q = 0
    for qi, (r0, mask) in enumerate([(0, 0xF0), (0, 0x0F), (4, 0xF0), (4, 0x0F)]):
        rows = [g[r0 + i] & mask for i in range(4)]
        if all(r == mask for r in rows):
            q |= 8 >> qi
        elif any(rows):
            return None
    return q

found = {}
lines = []
for bank in range(2):
    for code in range(256):
        g = rom[(bank * 256 + code) * 8:(bank * 256 + code) * 8 + 8]
        q = quad_pattern(g)
        if q is not None:
            found.setdefault(q, []).append((bank, code))
        lines.append(f"bank{bank} {code:02X}" + (f"  QUAD {q:X}" if q is not None else ""))
        for b in g:
            lines.append("  " + "".join("#" if b & (0x80 >> i) else "." for i in range(8)))
out.write_text("\n".join(lines))

for q in range(16):
    print(f"quad {q:04b} (TL TR BL BR):", ", ".join(f"b{b}:{c:02X}" for b, c in found.get(q, [])))
