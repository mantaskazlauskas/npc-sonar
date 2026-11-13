"""Generates the sonar ping ring drawn behind the nameplate icon.

  python make_ring.py ../NpcSonar/Media/ping_ring.tga

A white, soft-edged ring on transparency, 64x64. The addon tints it with
SetVertexColor and draws it additively, so colour is chosen in code. Written
straight to TGA (no SVG/PNG step) with png_to_tga's writer.
"""
import math
import sys

from png_to_tga import write_tga

SIZE = 64            # power of two, as WoW requires
RADIUS = 27.0        # ring centre line, in pixels from the middle
WIDTH = 2.2          # gaussian sigma of the bright band
GLOW = 7.0           # sigma of the faint halo around it


def alpha_at(d):
    band = math.exp(-((d - RADIUS) / WIDTH) ** 2 / 2)
    halo = 0.35 * math.exp(-((d - RADIUS) / GLOW) ** 2 / 2)
    # Fade the halo out before the texture edge so the square never shows.
    edge = max(0.0, min(1.0, (SIZE / 2 - d) / 3))
    return min(1.0, band + halo) * edge


rows = []
c = (SIZE - 1) / 2
for y in range(SIZE):
    line = bytearray()
    for x in range(SIZE):
        a = round(255 * alpha_at(math.hypot(x - c, y - c)))
        line += bytes((255, 255, 255, a))
    rows.append(line)

out = sys.argv[1]
write_tga(out, SIZE, SIZE, rows)
print(f"wrote {out} ({SIZE}x{SIZE})")
