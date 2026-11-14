#!/usr/bin/env python3
"""Social Preview (docs/media/social_preview.png, 1280x640) und OG-Bild (docs/media/og_image.png,
1200x630): echte Spielszene rechts, OMEN-Logo und Claim links auf Graphit.

Aufruf: python tools/make_social_preview.py <szene.png>

<szene.png> = 1920x1080-Bild der Eclipse-Welt ohne HUD, z. B. ein Frame aus einer
Movie-Maker-Aufnahme wie in tools/make_trailer.sh (override.cfg aus tools/test_override.cfg plus
window_width_override=1920/window_height_override=1080/borderless, dann
  Godot --path . --audio-driver Dummy --write-movie <avi> --fixed-fps 60 --resolution 1920x1080
  --position -1920,0 res://scenes/song_select.tscn --mode=mania --map="Cyber Grind" --diff=Hard
  --3d --theme=eclipse --autoplay --lang=en --nohud --shot --shot-at=135500 --shot-lead=0
  --movie-len=3
und einen Frame mit ffmpeg herausziehen). Logo: docs/media/logo_wordmark.png
(aus tools/render_logo_drafts.py --final). Schrift: Bahnschrift wie im Spiel (UiTheme.heading_font).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
MEDIA = os.path.join(REPO, "docs", "media")
FONT = r"C:\Windows\Fonts\bahnschrift.ttf"
GROUND = (12, 11, 10)          # Graphit, etwas tiefer als UiTheme.BG, damit die Szene leuchtet
TEXT = (238, 234, 225)         # UiTheme.TEXT
SUB = (193, 186, 172)          # zwischen TEXT und DIM
RULE = (207, 172, 120)         # gedaempftes Bernstein
HEAD = "Six rhythm modes. One game."
TAIL = "Free for Windows  \u00b7  plays your osu! maps"

# Ziel je Bild: Groesse, Eclipse-Mitte (Szene), Szenen-Massstab (1920x1080 -> Bild, so dass die
# Empfaenger unten knapp im Bild bleiben), Logo (links, oben, Tintenhoehe),
# Claim (links, oben, Breite), Linie (x, y, b, h), Zeile 2 (links, oben, Breite).
LAYOUTS = {
    "social_preview.png": dict(size=(1280, 640), sun=(908, 105), scale=0.72, logo=(75, 201, 81),
                               head=(80, 331, 607), rule=(78, 402, 65, 5), tail=(81, 428, 500)),
    "og_image.png": dict(size=(1200, 630), sun=(852, 102), scale=0.685, logo=(71, 203, 77),
                         head=(76, 328, 568), rule=(74, 392, 61, 4), tail=(76, 416, 466)),
}


def find_sun(img):
    """Mitte und Radius der dunklen Eclipse-Scheibe im oberen Bilddrittel."""
    a = np.asarray(img.convert("L"), dtype=float)
    h, w = a.shape
    top = a[: h // 3, w // 4: 3 * w // 4]
    # Scheibe = dunkle Flaeche, die von hellem Kranz umgeben ist: Spalten/Zeilen mit Kranz suchen
    bright = top > 200
    ys, xs = np.nonzero(bright)
    cx = xs.mean() + w // 4
    # Radius: dunkler Lauf entlang der Zeile durch die Kranz-Mitte
    cy = ys.mean()
    for _ in range(3):
        row = a[int(cy), :]
        x = int(cx)
        l = x
        while l > 0 and row[l] < 60:
            l -= 1
        r = x
        while r < w - 1 and row[r] < 60:
            r += 1
        cx = (l + r) / 2
        col = a[:, int(cx)]
        t = int(cy)
        while t > 0 and col[t] < 60:
            t -= 1
        b = int(cy)
        while b < h - 1 and col[b] < 60:
            b += 1
        cy = (t + b) / 2
    return cx, cy, (r - l) / 2


def fit_font(text, width):
    lo, hi = 8, 120
    while hi - lo > 1:
        mid = (lo + hi) // 2
        f = ImageFont.truetype(FONT, mid)
        f.set_variation_by_name("Regular")
        x0, _, x1, _ = f.getbbox(text)
        if x1 - x0 <= width:
            lo = mid
        else:
            hi = mid
    f = ImageFont.truetype(FONT, lo)
    f.set_variation_by_name("Regular")
    return f


def put_text(d, text, left, top, width, fill):
    f = fit_font(text, width)
    x0, y0, _, _ = f.getbbox(text)
    d.text((left - x0, top - y0), text, font=f, fill=fill)


def compose(scene, name, L):
    W, H = L["size"]
    sx, sy, sr = find_sun(scene)
    print("Eclipse in der Szene: %.0f, %.0f, r=%.0f" % (sx, sy, sr))
    tx, ty = L["sun"]
    k = L["scale"] * scene.width / 1920.0
    sc = scene.resize((round(scene.width * k), round(scene.height * k)), Image.LANCZOS)
    ox, oy = round(tx - sx * k), round(ty - sy * k)
    out = Image.new("RGB", (W, H), GROUND)
    out.paste(sc, (ox, oy))
    # Szene nach links in den Graphit-Grund auslaufen lassen (glatte S-Kurve, kein Schein)
    a = np.asarray(out, dtype=float)
    x = np.arange(W, dtype=float)
    t = np.clip((x - ox) / (W * 0.48), 0.0, 1.0)
    keep = t * t * (3 - 2 * t)
    a = a * keep[None, :, None] + np.array(GROUND, dtype=float)[None, None, :] * (1 - keep[None, :, None])
    out = Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8)).convert("RGBA")
    # Logo
    lg = Image.open(os.path.join(MEDIA, "logo_wordmark.png")).convert("RGBA")
    bx = lg.getchannel("A").point(lambda v: 255 if v > 128 else 0).getbbox()
    lx, ly, lh = L["logo"]
    s = lh / (bx[3] - bx[1])
    small = lg.resize((round(lg.width * s), round(lg.height * s)), Image.LANCZOS)
    out.alpha_composite(small, (round(lx - bx[0] * s), round(ly - bx[1] * s)))
    d = ImageDraw.Draw(out)
    put_text(d, HEAD, *L["head"], fill=TEXT)
    rx, ry, rw, rh = L["rule"]
    d.rectangle((rx, ry, rx + rw - 1, ry + rh - 1), fill=RULE)
    put_text(d, TAIL, *L["tail"], fill=SUB)
    path = os.path.join(MEDIA, name)
    # 256-Farben-PNG wie bisher (klein); Palette erst bestimmen, dann mit Fehlerstreuung
    # abbilden, sonst stuft sich der Bernstein-Verlauf der Haltenoten sichtbar ab.
    rgb = out.convert("RGB")
    pal = rgb.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    rgb.quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG).save(path, optimize=True)
    print(name, out.size, "Szene x%.3f" % k, os.path.getsize(path), "Bytes")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    scene = Image.open(sys.argv[1]).convert("RGB")
    for name, L in LAYOUTS.items():
        compose(scene, name, L)


if __name__ == "__main__":
    main()
