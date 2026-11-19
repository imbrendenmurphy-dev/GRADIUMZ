"""Render build/title.bin (screen rows 1..23) with the real font ROM -> PNG."""
import struct
import sys
import zlib
from pathlib import Path

rom = Path(sys.argv[1]).read_bytes()
out = Path(sys.argv[2])
t = (out / "title.bin").read_bytes()
PAL = [(0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255),
       (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)]
S, ROWS = 3, 23
W, H = 320 * S, ROWS * 8 * S
px = bytearray(W * H * 3)
for r in range(ROWS):
    for c in range(40):
        code, attr = t[r * 40 + c], t[920 + r * 40 + c]
        fg, bg = PAL[(attr >> 4) & 7], PAL[attr & 7]
        g = rom[((attr >> 7) * 256 + code) * 8:][:8]
        for y in range(8):
            for x in range(8):
                col = bytes(fg if g[y] >> x & 1 else bg)
                for yy in range(S):
                    o = (((r * 8 + y) * S + yy) * W + (c * 8 + x) * S) * 3
                    px[o:o + 3 * S] = col * S
raw = b"".join(b"\0" + px[y * W * 3:(y + 1) * W * 3] for y in range(H))
def chunk(k, d):
    return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d))
(out / "preview_title.png").write_bytes(
    b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
print("preview_title.png")
