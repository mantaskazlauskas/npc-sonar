"""Generates the speaker icon on each NPC row's sound button.

  python make_speaker.py ../NpcSonar/Media/speaker.tga

A white speaker with two sound waves on transparency, 32x32. The addon tints
it with SetVertexColor. Anti-aliased by 4x4 supersampling and written straight
to TGA with png_to_tga's writer.
"""
import math
import sys

from png_to_tga import write_tga

SIZE = 32   # power of two, as WoW requires
SS = 4      # supersamples per axis

# Speaker body (box plus cone), in pixel coordinates, y down.
BODY = [(4, 12), (10, 12), (17, 5), (17, 27), (10, 20), (4, 20)]
# Sound waves: arcs centred on the cone's mouth, as (radius, half-thickness).
WAVES = [(6.5, 1.3), (11.5, 1.3)]
WAVE_CENTER = (17, 16)
WAVE_SPAN = math.radians(50)  # half-angle either side of pointing right


def in_poly(x, y, poly):
    hit = False
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            hit = not hit
    return hit


def in_wave(x, y):
    dx, dy = x - WAVE_CENTER[0], y - WAVE_CENTER[1]
    if dx <= 0 or abs(math.atan2(dy, dx)) > WAVE_SPAN:
        return False
    r = math.hypot(dx, dy)
    return any(abs(r - radius) <= half for radius, half in WAVES)


rows = []
for py in range(SIZE):
    line = bytearray()
    for px in range(SIZE):
        cover = 0
        for sx in range(SS):
            for sy in range(SS):
                x, y = px + (sx + 0.5) / SS, py + (sy + 0.5) / SS
                cover += in_poly(x, y, BODY) or in_wave(x, y)
        line += bytes((255, 255, 255, round(255 * cover / (SS * SS))))
    rows.append(line)

out = sys.argv[1]
write_tga(out, SIZE, SIZE, rows)
print(f"wrote {out} ({SIZE}x{SIZE})")
