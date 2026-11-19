"""Render playfield frames from build/level.bin with the real font ROM -> PNG.
Also writes build/MZ700FON.DAT (bit-reversed font for MZ700WIN).

usage: py tools/preview.py rom/mz700fon.int build  scrollx [scrollx ...]
"""
import struct
import sys
import zlib
from pathlib import Path

rom = Path(sys.argv[1]).read_bytes()
out = Path(sys.argv[2])
ROWS, STRIDE = 23, 296
BLOCK = ROWS * STRIDE
lvl = (out / "level.bin").read_bytes()

# MZ700WIN wants the leftmost pixel in bit 7; the .int dump has it in bit 0
rev = bytes(int(f"{b:08b}"[::-1], 2) for b in rom)
(out / "MZ700FON.DAT").write_bytes(rev)

PAL = [(0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255),
       (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)]
S = 3

def png(path, w, h, px):
    raw = b"".join(b"\0" + bytes(c for p in px[y * w:(y + 1) * w] for c in p) for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

for sx in map(int, sys.argv[3:]):
    o, ph = sx >> 1, sx & 1
    W, H = 320 * S, ROWS * 8 * S
    px = [(0, 0, 0)] * (W * H)
    for r in range(ROWS):
        for c in range(40):
            code = lvl[ph * BLOCK + r * STRIDE + o + c]
            attr = lvl[2 * BLOCK + r * STRIDE + o + c]
            fg, bg = PAL[(attr >> 4) & 7], PAL[attr & 7]
            g = rom[((attr >> 7) * 256 + code) * 8:][:8]
            for y in range(8):
                for x in range(8):
                    col = fg if g[y] >> x & 1 else bg
                    for yy in range(S):
                        base = ((r * 8 + y) * S + yy) * W + (c * 8 + x) * S
                        px[base:base + S] = [col] * S
    png(out / f"preview_{sx}.png", W, H, px)
    print(f"preview_{sx}.png")
