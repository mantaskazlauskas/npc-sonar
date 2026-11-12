"""Generates the NPC Sonar artwork as SVG.

  python make_icon.py icon.svg                 400x400 CurseForge icon (tile, both blips)
  python make_icon.py badge.svg --badge        in-game badge while searching: scope only,
                                               no tile, no blips (the addon spins it)
  python make_icon.py badge_found.svg --badge --found  in-game badge once found: adds the orange blip

PNGs are rendered from the SVG with headless Edge:
  msedge --headless=new --default-background-color=00000000
         --window-size=400,400 --screenshot=icon.png file:///.../icon.svg
(128,128 for the badges), and the badge PNGs are converted to the .tga files the
game loads with png_to_tga.py.
"""
import math, sys
out = sys.argv[1]
BADGE = "--badge" in sys.argv
FOUND = "--found" in sys.argv or not BADGE
CX = CY = 200
R = 150
def pt(deg, r):
    a = math.radians(deg)
    return CX + r * math.cos(a), CY + r * math.sin(a)

LEAD = -40       # sweep line angle (screen coords: 0 = right, -90 = up)
TRAIL = 75       # degrees of fading trail behind it
SLICES = 60

wedges = []
# Stacked wedges that all end at the sweep line: each adds a little opacity,
# so the fade is built from overlap with no internal gaps or seams.
for i in range(SLICES):
    a0 = LEAD - TRAIL + i * TRAIL / SLICES
    x0, y0 = pt(a0, R); x1, y1 = pt(LEAD, R)
    wedges.append(f'<path d="M{CX} {CY} L{x0:.2f} {y0:.2f} A{R} {R} 0 0 1 {x1:.2f} {y1:.2f} Z" fill="#40b3f2" fill-opacity="0.017"/>')

lx, ly = pt(LEAD, R)
bx, by = pt(LEAD - 18, 96)      # the found NPC, just swept
ox, oy = pt(160, 62)            # an older, fading contact

TILE = "" if BADGE else '''
  <!-- Tile -->
  <rect x="8" y="8" width="384" height="384" rx="76" fill="url(#bg)"/>
  <rect x="8" y="8" width="384" height="384" rx="76" fill="none" stroke="#2c3446" stroke-width="4"/>
'''
OLD_CONTACT = "" if BADGE else f'''
    <!-- Older contact, fading -->
    <circle cx="{ox:.2f}" cy="{oy:.2f}" r="7" fill="#40b3f2" fill-opacity="0.45"/>
'''
CONTACT = "" if not FOUND else f'''
    <!-- Found contact -->
    <circle cx="{bx:.2f}" cy="{by:.2f}" r="44" fill="url(#blipGlow)"/>
    <circle cx="{bx:.2f}" cy="{by:.2f}" r="24" fill="none" stroke="#ff9a52" stroke-width="3" stroke-opacity="0.55"/>
    <circle cx="{bx:.2f}" cy="{by:.2f}" r="12" fill="#ffb366"/>
    <circle cx="{bx:.2f}" cy="{by:.2f}" r="5" fill="#fff4e6"/>
'''
# The badge is cropped to the bezel so the scope fills the texture.
SIZE, VIEW = (128, "32 32 336 336") if BADGE else (400, "0 0 400 400")

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="{VIEW}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1b2130"/>
      <stop offset="1" stop-color="#0b0e14"/>
    </linearGradient>
    <radialGradient id="scope" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#14304a"/>
      <stop offset="0.75" stop-color="#0f1c2b"/>
      <stop offset="1" stop-color="#0a121c"/>
    </radialGradient>
    <radialGradient id="blipGlow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#ffb366" stop-opacity="0.9"/>
      <stop offset="0.35" stop-color="#ff7a3d" stop-opacity="0.45"/>
      <stop offset="1" stop-color="#ff7a3d" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="bezel" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#7fd3ff"/>
      <stop offset="1" stop-color="#2a8fcc"/>
    </linearGradient>
    <clipPath id="scopeClip"><circle cx="{CX}" cy="{CY}" r="{R}"/></clipPath>
  </defs>
{TILE}
  <!-- Scope face -->
  <circle cx="{CX}" cy="{CY}" r="{R}" fill="url(#scope)"/>

  <g clip-path="url(#scopeClip)">
    <!-- Range rings and crosshair -->
    <g fill="none" stroke="#40b3f2">
      <circle cx="{CX}" cy="{CY}" r="112" stroke-opacity="0.35" stroke-width="3"/>
      <circle cx="{CX}" cy="{CY}" r="74" stroke-opacity="0.35" stroke-width="3"/>
      <circle cx="{CX}" cy="{CY}" r="36" stroke-opacity="0.35" stroke-width="3"/>
      <line x1="{CX - R}" y1="{CY}" x2="{CX + R}" y2="{CY}" stroke-opacity="0.22" stroke-width="2.5"/>
      <line x1="{CX}" y1="{CY - R}" x2="{CX}" y2="{CY + R}" stroke-opacity="0.22" stroke-width="2.5"/>
    </g>

    <!-- Sweep trail -->
    {chr(10).join("    " + w for w in wedges)}
{OLD_CONTACT}{CONTACT}  </g>

  <!-- Sweep line -->
  <line x1="{CX}" y1="{CY}" x2="{lx:.2f}" y2="{ly:.2f}" stroke="#bfe9ff" stroke-width="5" stroke-linecap="round"/>
  <circle cx="{CX}" cy="{CY}" r="9" fill="#bfe9ff"/>

  <!-- Bezel -->
  <circle cx="{CX}" cy="{CY}" r="{R + 7}" fill="none" stroke="url(#bezel)" stroke-width="14"/>
  <circle cx="{CX}" cy="{CY}" r="{R + 15}" fill="none" stroke="#0b0e14" stroke-width="2" stroke-opacity="0.7"/>
</svg>
'''
open(out, "w", encoding="utf-8").write(svg)
print("wrote", out)
