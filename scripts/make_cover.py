#!/usr/bin/env python3
"""Generate the Connect IQ Store cover image (500x500) for Ahead.

Echoes the app's own UI: a compass ring, nearby places as colored radar dots,
and the green arrow pointing at the place you're facing. Rendered at 4x and
downsampled with LANCZOS for smooth edges. Pure Pillow, no network.

    python3 scripts/make_cover.py            # -> store/cover_500.png
"""
import math
import os
from PIL import Image, ImageDraw, ImageFont

SS = 4                      # supersample factor
S = 500 * SS                # working size
CX, CY = 250 * SS, 198 * SS  # compass centre
R = 150 * SS                # compass outer radius

FONT_DIR = "/usr/share/fonts/truetype/quicksand"
F_TITLE = os.path.join(FONT_DIR, "Quicksand-Bold.ttf")
F_TAG = os.path.join(FONT_DIR, "Quicksand-Medium.ttf")
F_CARD = os.path.join(FONT_DIR, "Quicksand-Medium.ttf")

# Category colours, mirrored from source/Poi.mc.
GOLD = (0xFF, 0xCC, 0x00)
ORANGE = (0xFF, 0x88, 0x00)
SKY = (0x33, 0xAA, 0xFF)
GREEN = (0x33, 0xDD, 0x33)
LIME = (0xAA, 0xDD, 0x00)
TEAL = (0x00, 0xCC, 0x88)
PINK = (0xFF, 0x66, 0xCC)
PURPLE = (0xCC, 0x66, 0xFF)
ROSE = (0xFF, 0x99, 0xAA)
RED = (0xFF, 0x3B, 0x3B)
RING = (0x3A, 0x4E, 0x63)
RING_HI = (0x5E, 0x79, 0x92)
WHITE = (0xFF, 0xFF, 0xFF)
TAGCOL = (0x9F, 0xB3, 0xC8)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def polar(bearing_deg, dist):
    """Screen point for a compass bearing (0=up/N, clockwise) at radius dist."""
    th = math.radians(bearing_deg)
    return (CX + dist * math.sin(th), CY - dist * math.cos(th))


def main():
    img = Image.new("RGB", (S, S), (5, 8, 13))
    # Vertical gradient: deep blue at the top fading to near-black at the bottom.
    top, bot = (0x10, 0x27, 0x3C), (0x05, 0x08, 0x0D)
    d = ImageDraw.Draw(img)
    for y in range(S):
        d.line([(0, y), (S, y)], fill=lerp(top, bot, y / S))

    # Soft radial glow behind the compass.
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i in range(28, 0, -1):
        rr = R * (1.7 * i / 28)
        a = int(46 * (i / 28) ** 2)
        gd.ellipse([CX - rr, CY - rr, CX + rr, CY + rr],
                   fill=(0x1E, 0x4D, 0x78, a))
    img = Image.alpha_composite(img.convert("RGBA"), glow)
    d = ImageDraw.Draw(img)

    # Compass ring.
    lw = 3 * SS
    d.ellipse([CX - R, CY - R, CX + R, CY + R], outline=RING, width=lw)
    rin = R - 9 * SS
    d.ellipse([CX - rin, CY - rin, CX + rin, CY + rin],
              outline=(0x21, 0x2F, 0x3E), width=1 * SS)

    # Tick marks: 36 minor, longer at the cardinals.
    for b in range(0, 360, 10):
        major = (b % 90 == 0)
        outer = R - 3 * SS
        inner = R - (20 * SS if major else 11 * SS)
        p1, p2 = polar(b, outer), polar(b, inner)
        col = RED if b == 0 else (RING_HI if major else RING)
        d.line([p1, p2], fill=col, width=(3 * SS if major else 1 * SS))

    # Cardinal letters.
    cf = ImageFont.truetype(F_CARD, 26 * SS)
    for b, label, col in [(0, "N", RED), (90, "E", TAGCOL),
                          (180, "S", TAGCOL), (270, "W", TAGCOL)]:
        px, py = polar(b, R - 36 * SS)
        tb = d.textbbox((0, 0), label, font=cf)
        d.text((px - (tb[2] - tb[0]) / 2, py - (tb[3] - tb[1]) / 2 - tb[1]),
               label, font=cf, fill=col)

    # Nearby places as radar dots (bearing, distance-fraction, colour).
    dots = [(45, 0.52, GOLD), (88, 0.78, SKY), (130, 0.52, ROSE),
            (175, 0.72, PURPLE), (225, 0.58, ORANGE), (270, 0.50, TEAL),
            (300, 0.80, LIME)]
    for b, frac, col in dots:
        px, py = polar(b, R * frac)
        gr = 16 * SS
        gl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(gl).ellipse([px - gr, py - gr, px + gr, py + gr],
                                   fill=col + (60,))
        img = Image.alpha_composite(img, gl)
        d = ImageDraw.Draw(img)
        r = 6 * SS
        d.ellipse([px - r, py - r, px + r, py + r], fill=col)

    # The place you are facing: green arrow + glowing dot up and to the left,
    # clear of the N marker. The arrow tip meets the focused dot.
    fb = -28
    tipd = R * 0.62
    tip = polar(fb, tipd)
    th = math.radians(fb)
    ux, uy = math.sin(th), -math.cos(th)      # forward unit vector
    px_, py_ = math.cos(th), math.sin(th)     # perpendicular
    L = tipd
    w = 13 * SS
    fwd = 0.16 * L

    def pt(f, side):
        return (CX + ux * f + px_ * side, CY + uy * f + py_ * side)

    arrow = [pt(L, 0), pt(fwd, w), pt(-0.20 * L, 0), pt(fwd, -w)]
    d.polygon(arrow, fill=GREEN)

    # Glow + bright dot at the focused place.
    fr = 22 * SS
    gl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gld = ImageDraw.Draw(gl)
    for i in range(10, 0, -1):
        rr = fr * i / 10
        gld.ellipse([tip[0] - rr, tip[1] - rr, tip[0] + rr, tip[1] + rr],
                    fill=GREEN + (int(70 * (i / 10) ** 2),))
    img = Image.alpha_composite(img, gl)
    d = ImageDraw.Draw(img)
    r = 9 * SS
    d.ellipse([tip[0] - r, tip[1] - r, tip[0] + r, tip[1] + r], fill=(220, 255, 220))
    d.ellipse([tip[0] - r, tip[1] - r, tip[0] + r, tip[1] + r], outline=GREEN, width=2 * SS)

    # Centre hub.
    hr = 7 * SS
    d.ellipse([CX - hr, CY - hr, CX + hr, CY + hr], fill=RING_HI)

    # Title + tagline.
    tf = ImageFont.truetype(F_TITLE, 76 * SS)
    title = "Ahead"
    tb = d.textbbox((0, 0), title, font=tf)
    d.text((S / 2 - (tb[2] - tb[0]) / 2 - tb[0], 380 * SS), title, font=tf, fill=WHITE)

    gf = ImageFont.truetype(F_TAG, 25 * SS)
    tag = "the place in front of you"
    tb = d.textbbox((0, 0), tag, font=gf)
    d.text((S / 2 - (tb[2] - tb[0]) / 2 - tb[0], 452 * SS), tag, font=gf, fill=TAGCOL)

    out_dir = "store"
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "cover_500.png")
    img.convert("RGB").resize((500, 500), Image.LANCZOS).save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
