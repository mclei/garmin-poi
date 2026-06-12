#!/usr/bin/env python3
"""Generate resources/drawables/launcher_icon.png (70x70 compass icon).

Uses only the Python standard library (zlib + struct), no PIL needed.
"""
import os
import struct
import zlib

W = H = 70
CX = CY = (W - 1) / 2.0
R_OUTER = 33.0
R_RING = 30.0

BG = (0, 0, 0, 0)            # transparent corners
RING = (230, 230, 235, 255)  # white ring
FACE = (16, 32, 64, 255)     # dark navy face
NORTH = (255, 90, 40, 255)   # orange-red north needle
SOUTH = (235, 235, 240, 255) # light south needle


def in_tri(p, a, b, c):
    def sign(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
    d1, d2, d3 = sign(p, a, b), sign(p, b, c), sign(p, c, a)
    has_neg = d1 < 0 or d2 < 0 or d3 < 0
    has_pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (has_neg and has_pos)


def pixel(x, y):
    dx, dy = x - CX, y - CY
    r2 = dx * dx + dy * dy
    if r2 > R_OUTER * R_OUTER:
        return BG
    if r2 >= R_RING * R_RING:
        return RING
    if in_tri((x, y), (35, 8), (27, 38), (43, 38)):
        return NORTH
    if in_tri((x, y), (35, 61), (27, 31), (43, 31)):
        return SOUTH
    return FACE


def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def main():
    raw = b""
    for y in range(H):
        raw += b"\x00"  # filter type: none
        for x in range(W):
            raw += bytes(pixel(x, y))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "resources", "drawables", "launcher_icon.png")
    with open(out, "wb") as fh:
        fh.write(png)
    print("wrote", out, len(png), "bytes")


if __name__ == "__main__":
    main()
