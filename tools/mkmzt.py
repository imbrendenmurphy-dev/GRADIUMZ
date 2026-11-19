"""Wrap a raw Z80 binary in a 128-byte MZ-700 tape header (.MZT / .MZF).

usage: py tools/mkmzt.py input.bin output.mzt NAME LOADADDR EXECADDR
addresses in hex, e.g. 1200
"""
import sys
from pathlib import Path

src, dst, name, load, exe = sys.argv[1:6]
data = Path(src).read_bytes()
load, exe = int(load, 16), int(exe, 16)
if load + len(data) > 0xD000:
    sys.exit(f"binary too big: ends at {load + len(data):04X}, must stay below D000")

hdr = bytearray(128)
hdr[0] = 0x01                                   # machine-code program
fn = name.upper().encode("ascii")[:16]
hdr[1:1 + len(fn)] = fn
hdr[1 + len(fn):18] = b"\x0d" * (17 - len(fn))  # name terminator / padding
hdr[18:20] = len(data).to_bytes(2, "little")
hdr[20:22] = load.to_bytes(2, "little")
hdr[22:24] = exe.to_bytes(2, "little")
Path(dst).write_bytes(bytes(hdr) + data)
print(f"{dst}: {len(data)} bytes at {load:04X}, exec {exe:04X}")
