#!/usr/bin/env python3
"""Generate resources/drawables/launcher_icon.png (70x70).

A map pin whose head is a compass: the teardrop shape says "point of interest",
the red/white needle and dial inside keep the navigation identity. Rendered at
8x and downsampled with LANCZOS for smooth edges. Uses Pillow (like the other
store-asset scripts).

    python3 scripts/make_icon.py
"""
import math
import os
from PIL import Image, ImageDraw

OUT = 70
SS = 8
S = OUT * SS

# Pin geometry in 70-space (scaled by SS at draw time).
HC = (35.0, 31.0)       # head centre
HR = 23.0               # head radius (outer rim)
TIP = (35.0, 66.0)      # teardrop point at the bottom

RIM = (236, 238, 244, 255)    # light rim
FACE = (14, 33, 56, 255)      # dark navy compass face
DIAL = (95, 120, 150, 255)    # faint inner dial ring
NORTH = (255, 70, 51, 255)    # red north needle
SOUTH = (216, 222, 230, 255)  # light south needle
HUB = (255, 196, 0, 255)      # gold centre dot (a "place" accent)


def sx(v):
    return v * SS


def teardrop(center, r, tip):
    """Circle head + tangent lines down to the tip = a smooth map-pin outline,
    as a high-res point list for ImageDraw.polygon."""
    ox, oy = center
    px, py = tip
    d = math.hypot(px - ox, py - oy)
    a = math.acos(max(-1.0, min(1.0, r / d)))      # half-angle to tangents
    base = math.atan2(py - oy, px - ox)            # O -> tip direction
    t1, t2 = base + a, base - a
    pts = []
    # Arc forming the head, from one tangent point the long way to the other.
    steps = 96
    start, end = t1, t2 + 2 * math.pi
    for i in range(steps + 1):
        ang = start + (end - start) * i / steps
        pts.append((sx(ox + r * math.cos(ang)), sx(oy + r * math.sin(ang))))
    pts.append((sx(px), sx(py)))                   # the point
    return pts


def tri(d, apex, b1, b2, fill):
    d.polygon([(sx(apex[0]), sx(apex[1])), (sx(b1[0]), sx(b1[1])),
               (sx(b2[0]), sx(b2[1]))], fill=fill)


def main():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Pin rim (outer teardrop), then the navy face inside it.
    d.polygon(teardrop(HC, HR, TIP), fill=RIM)
    d.polygon(teardrop(HC, HR - 2.5, (TIP[0], TIP[1] - 2.0)), fill=FACE)

    cx, cy = HC
    # Faint dial ring inside the head.
    rr = HR - 6.0
    d.ellipse([sx(cx - rr), sx(cy - rr), sx(cx + rr), sx(cy + rr)],
              outline=DIAL, width=max(1, int(sx(0.7))))

    # Compass needle (vertical rhombus): red north up, light south down.
    nl = HR - 7.0          # needle half-length
    hw = 5.0               # needle half-width at the hub
    tri(d, (cx, cy - nl), (cx - hw, cy), (cx + hw, cy), NORTH)
    tri(d, (cx, cy + nl), (cx - hw, cy), (cx + hw, cy), SOUTH)

    # Centre hub (gold accent).
    hub = 3.2
    d.ellipse([sx(cx - hub), sx(cy - hub), sx(cx + hub), sx(cy + hub)], fill=HUB)

    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "resources", "drawables", "launcher_icon.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.resize((OUT, OUT), Image.LANCZOS).save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
