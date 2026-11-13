"""Generates the radar arrow that points at a detected NPC.

  python make_arrow.py ../NpcSonar/Media/radar_arrow.tga

A white arrowhead pointing up on transparency, 64x64. The addon rotates it
with SetRotation and tints it with SetVertexColor. Edges are anti-aliased by
4x4 supersampling. Written straight to TGA with png_to_tga's writer.
"""
import sys

from png_to_tga import write_tga

SIZE = 64   # power of two, as WoW requires
SS = 4      # supersamples per axis

# Arrowhead with a notched tail, in pixel coordinates (y down), tip at top.
POLY = [(32, 4), (56, 58), (32, 44), (8, 58)]


def inside(x, y):
    """Even-odd point-in-polygon test."""
    hit = False
    n = len(POLY)
    for i in range(n):
        x0, y0 = POLY[i]
        x1, y1 = POLY[(i + 1) % n]
        if (y0 > y) != (y1 > y):
            if x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
                hit = not hit
    return hit


rows = []
for py in range(SIZE):
    line = bytearray()
    for px in range(SIZE):
        cover = sum(
            inside(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
            for sx in range(SS) for sy in range(SS)
        )
        line += bytes((255, 255, 255, round(255 * cover / (SS * SS))))
    rows.append(line)

out = sys.argv[1]
write_tga(out, SIZE, SIZE, rows)
print(f"wrote {out} ({SIZE}x{SIZE})")
