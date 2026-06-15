#!/usr/bin/env python3
"""Render a store screenshot of Ahead's main screen at Venu X1 resolution.

Reproduces MainView.onUpdate geometry exactly (ring = min(w,h)/2 - 10, focused
name/distance/detail offsets, the aligned-green arrow, in-view radar dots and
the status line) for a plausible scene. Rendered at 4x and downsampled. Pillow
only, no network.

    python3 scripts/make_screenshot.py     # -> store/screenshot_venux1_448x486.png
"""
import math
import os
from PIL import Image, ImageDraw, ImageFont

W0, H0 = 448, 486           # Venu X1 panel
SS = 4
W, H = W0 * SS, H0 * SS
CX, CY = W // 2, H // 2
RING = (min(W, H) // 2) - 10 * SS

# Garmin system colours.
DK_GRAY = (0x55, 0x55, 0x55)
LT_GRAY = (0xAA, 0xAA, 0xAA)
RED = (0xFF, 0x00, 0x00)
GREEN = (0x00, 0xFF, 0x00)
WHITE = (0xFF, 0xFF, 0xFF)
# Category colours from source/Poi.mc.
GOLD = (0xFF, 0xCC, 0x00)
ORANGE = (0xFF, 0x88, 0x00)
SKY = (0x33, 0xAA, 0xFF)
REST = (0x33, 0xDD, 0x33)
TEAL = (0x00, 0xCC, 0x88)
PINK = (0xFF, 0x66, 0xCC)
ROSE = (0xFF, 0x99, 0xAA)

LIB = "/usr/share/fonts/truetype/liberation"
DEJ = "/usr/share/fonts/truetype/dejavu"


def font(name_lib, name_dej, px):
    for p in (os.path.join(LIB, name_lib), os.path.join(DEJ, name_dej)):
        if os.path.exists(p):
            return ImageFont.truetype(p, px)
    return ImageFont.load_default()


def ctext(d, cx, cy, s, fnt, fill):
    """Draw text centred on (cx, cy), like TEXT_JUSTIFY_CENTER|VCENTER."""
    b = d.textbbox((0, 0), s, font=fnt)
    d.text((cx - (b[2] - b[0]) / 2 - b[0], cy - (b[3] - b[1]) / 2 - b[1]),
           s, font=fnt, fill=fill)


def main():
    img = Image.new("RGB", (W, H), (0, 0, 0))   # AMOLED true black
    d = ImageDraw.Draw(img)

    hdg = 327                   # facing NW
    f_name = "Charles Bridge"
    f_dist = "210 m"
    f_detail = "Monument"
    f_detail_col = GOLD
    n_poi = 7

    f_name_font = font("LiberationSans-Regular.ttf", "DejaVuSans.ttf", 30 * SS)
    card_font = font("LiberationSans-Regular.ttf", "DejaVuSans.ttf", 22 * SS)
    tiny_font = font("LiberationSans-Regular.ttf", "DejaVuSans.ttf", 18 * SS)
    num_font = font("LiberationSans-Bold.ttf", "DejaVuSans-Bold.ttf", 46 * SS)

    # --- compass ring ---
    d.ellipse([CX - RING, CY - RING, CX + RING, CY + RING],
              outline=DK_GRAY, width=2 * SS)
    labels = ["N", "E", "S", "W"]
    for deg in range(0, 360, 45):
        a = math.radians((deg - hdg) % 360)
        sx, sy = math.sin(a), math.cos(a)
        if deg % 90 == 0:
            lx = CX + (RING - 18 * SS) * sx
            ly = CY - (RING - 18 * SS) * sy
            col = RED if deg == 0 else LT_GRAY
            ctext(d, lx, ly, labels[deg // 90], card_font, col)
        else:
            x1, y1 = CX + (RING - 8 * SS) * sx, CY - (RING - 8 * SS) * sy
            x2, y2 = CX + RING * sx, CY - RING * sy
            d.line([(x1, y1), (x2, y2)], fill=DK_GRAY, width=1 * SS)

    # --- POI radar dots (in-view set: clustered ahead, screen angle 0 = up) ---
    # (screen-angle deg, distance-fraction of (ring-28), colour)
    dots = [(-8, 0.34, GOLD), (-32, 0.52, PINK), (24, 0.44, ORANGE),
            (44, 0.72, SKY), (-48, 0.78, ROSE), (14, 0.86, TEAL),
            (-20, 0.66, REST)]
    rpx_max = RING - 28 * SS
    for ang, frac, col in sorted(dots, key=lambda t: -t[1]):  # far first
        a = math.radians(ang)
        x = CX + rpx_max * frac * math.sin(a)
        y = CY - rpx_max * frac * math.cos(a)
        r = 4 * SS
        d.ellipse([x - r, y - r, x + r, y + r], fill=col)

    # --- focused arrow (aligned -> green), at cy - ring*0.45, size ring*0.17 ---
    rel = -1.0
    size = RING * 0.17
    ax, ay = CX, CY - RING * 0.45
    a = math.radians(rel)
    cs, sn = math.cos(a), math.sin(a)
    pts = [(0.0, -size), (0.62 * size, 0.55 * size),
           (0.0, 0.22 * size), (-0.62 * size, 0.55 * size)]
    poly = [(ax + px * cs - py * sn, ay + px * sn + py * cs) for px, py in pts]
    d.polygon(poly, fill=GREEN)

    # --- focused POI text ---
    ctext(d, CX, CY - RING * 0.10, f_name, f_name_font, WHITE)
    ctext(d, CX, CY + RING * 0.22, f_dist, num_font, WHITE)
    ctext(d, CX, CY + RING * 0.42, f_detail, tiny_font, f_detail_col)

    # --- status line ---
    status = "{} NW | {} POI".format(hdg, n_poi)
    bottom_margin = H - (CY + RING)
    sy = (CY + RING + bottom_margin / 2) if bottom_margin >= 20 * SS \
        else (CY + RING - 18 * SS)
    ctext(d, CX, sy, status, tiny_font, LT_GRAY)

    out_dir = "store"
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "screenshot_venux1_448x486.png")
    img.resize((W0, H0), Image.LANCZOS).save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
