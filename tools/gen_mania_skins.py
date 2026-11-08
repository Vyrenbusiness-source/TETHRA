#!/usr/bin/env python3
"""Erzeugt die 3 eingebauten 2D-Skins nach assets_game/skins/<name>/.

Eigene Grafiken (keine fremden osu!-Skins). Noten, Hold-Koerper und Kappen sind
NEUTRALE GRAUSTUFEN-Bilder (Schattierung/Kante bleiben als Helligkeit erhalten);
Playfield2D toent sie beim Zeichnen mit der Notenfarbe (Multiplikation): Kopf und
Kappe (T) mit der Notenfarbe, Hold-Koerper (L) mit der Hold-Farbe (Notenfarbe 28 % dunkler). Die
Paletten dieses Generators stehen in der skin.ini ([TETHRA] AutoColors, je Spalte):
im Modus "auto" ergibt Grau x AutoColor den bisherigen Look. Tasten/Receptors und
Buehnenraender bleiben farbig. Deterministisch, 4x
Supersampling, @2x-Dateinamen, skin.ini im osu!-Format. Aufruf:
    python tools/gen_mania_skins.py
Danach Godot einmal importieren lassen (--headless --import) und die
*.png.import mit einchecken.
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets_game", "skins")
SS = 4
W = 160            # Spaltenbreite in Pixeln (Seitenverhaeltnis zaehlt, Spalte = 40 Einheiten)
UNITS = 40


def canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def finish(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rrect(d, box, r, fill=None):
    x0, y0, x1, y1 = [v * SS for v in box]
    d.rounded_rectangle((x0, y0, x1, y1), radius=r * SS, fill=fill)


def save(path, img):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)


WHITE = (255, 255, 255)


def gray(v):
    return (v, v, v)


def hexc(c):
    return "%02x%02x%02x" % tuple(c)


def ini(name, lines, files, auto_colors):
    body = ["[General]", "Name: " + name, "Author: TETHRA", "Version: 2.5", "", "[Mania]", "Keys: 4",
            "ColumnWidth: %d,%d,%d,%d" % ((UNITS,) * 4), "ColumnLineWidth: 0,0,0,0,0",
            "HitPosition: 402", "LightPosition: 413", "NoteBodyStyle: 0", "KeysUnderNotes: 0",
            "JudgementLine: 0"] + lines
    # Dateiliste fuer den Export (Verzeichnis-Listing im .pck ist unzuverlaessig).
    body += ["", "[TETHRA]", "Files: " + ",".join(sorted(files)), "Tint: 1",
             "AutoColors: " + ",".join(hexc(c) for c in auto_colors), ""]
    return "\n".join(body)


def write_skin(folder, name, lines, images, auto_colors):
    d = os.path.join(OUT, folder)
    files = []
    for fn, im in images.items():
        save(os.path.join(d, fn + "@2x.png"), im)
        files.append(fn)
    with open(os.path.join(d, "skin.ini"), "w", newline="\n") as f:
        f.write(ini(name, lines, files, auto_colors))


def stage_images(edge=(70, 78, 98), hint=(150, 160, 185)):
    left = Image.new("RGBA", (6, 8), rgba(edge, 0))
    dl = ImageDraw.Draw(left)
    dl.rectangle((3, 0, 5, 7), fill=rgba(edge, 150))
    dl.rectangle((5, 0, 5, 7), fill=rgba(mix(edge, (255, 255, 255), 0.3), 190))
    right = left.transpose(Image.FLIP_LEFT_RIGHT)
    h = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    ImageDraw.Draw(h).rectangle((0, 3, 7, 4), fill=rgba(hint, 110))
    return {"mania-stage-left": left, "mania-stage-right": right, "mania-stage-hint": h}


# ------------------------------------------------------------------ Balken
def skin_balken():
    BH = 44
    cols = {1: (236, 240, 248), 2: (96, 150, 224)}   # weiss / blau (= AutoColors)
    imgs = {}
    for k, key_c in cols.items():
        c = WHITE   # Noten: neutral, die Notenfarbe kommt beim Zeichnen
        im = canvas(W, BH)
        d = ImageDraw.Draw(im)
        rrect(d, (6, 6, W - 6, BH - 6), 7, fill=rgba(mix(c, (0, 0, 0), 0.12)))
        rrect(d, (6, 6, W - 6, 20), 7, fill=rgba(c))
        rrect(d, (6, BH - 12, W - 6, BH - 6), 4, fill=rgba(mix(c, (0, 0, 0), 0.28)))
        im = finish(im, W, BH)
        imgs["mania-note%d" % k] = im
        imgs["mania-note%dH" % k] = im
        b = canvas(W, 16)
        bd = ImageDraw.Draw(b)
        bd.rectangle((26 * SS, 0, (W - 26) * SS, 16 * SS), fill=rgba(gray(194), 215))
        bd.rectangle((26 * SS, 0, 30 * SS, 16 * SS), fill=rgba(c, 235))
        bd.rectangle(((W - 30) * SS, 0, (W - 26) * SS, 16 * SS), fill=rgba(c, 235))
        imgs["mania-note%dL" % k] = finish(b, W, 16)
        t = canvas(W, 24)
        td = ImageDraw.Draw(t)
        rrect(td, (26, 0, W - 26, 18), 6, fill=rgba(mix(c, (0, 0, 0), 0.12)))
        rrect(td, (26, 0, W - 26, 8), 6, fill=rgba(c))
        imgs["mania-note%dT" % k] = finish(t, W, 24)
        for pressed in (False, True):
            ky = canvas(W, 200)
            kd = ImageDraw.Draw(ky)
            base = (46, 52, 70) if not pressed else mix((46, 52, 70), key_c, 0.55)
            rrect(kd, (5, 0, W - 5, 196), 10, fill=rgba(base))
            rrect(kd, (5, 0, W - 5, 10), 5, fill=rgba(key_c, 255 if pressed else 150))
            imgs["mania-key%d%s" % (k, "D" if pressed else "")] = finish(ky, W, 200)
    imgs.update(stage_images())
    write_skin("Balken", "Balken", [], imgs, [cols[1], cols[2], cols[2], cols[1]])


# ------------------------------------------------------------------ Kreise
def circle_note(outer, inner, hi, size=W):
    im = canvas(size, size)
    d = ImageDraw.Draw(im)
    c = size * SS / 2
    R = (size / 2 - 8) * SS
    glow = canvas(size, size)
    gd = ImageDraw.Draw(glow)
    gd.ellipse((c - R - 4 * SS, c - R - 4 * SS, c + R + 4 * SS, c + R + 4 * SS), fill=rgba(outer, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(5 * SS))
    im.alpha_composite(glow)
    d.ellipse((c - R, c - R, c + R, c + R), fill=rgba(outer))
    r2 = R * 0.74
    d.ellipse((c - r2, c - r2, c + r2, c + r2), fill=rgba(inner))
    r3 = R * 0.34
    d.ellipse((c - r3, c - r3, c + r3, c + r3), fill=rgba(hi, 230))
    return finish(im, size, size)


def body_cap(col, inset, alpha):
    """Runde Kappe oben, unten buendig mit dem Hold-Koerper (Breite W - 2*inset)."""
    bw = W - 2 * inset
    h = bw // 2
    t = canvas(W, h)
    td = ImageDraw.Draw(t)
    td.ellipse((inset * SS, 0, (W - inset) * SS, bw * SS), fill=rgba(col, alpha))
    t = t.filter(ImageFilter.GaussianBlur(1.5 * SS))
    return finish(t, W, h)


def skin_kreise():
    pal = {1: ((126, 196, 214), (34, 62, 82)), 2: ((196, 150, 214), (60, 40, 84))}
    imgs = {}
    for k, (outer, inner) in pal.items():
        key_outer = outer
        # Neutral: aussen volle Helligkeit (= AutoColor), Innenring/Kern als Grauwert
        # (Verhaeltnis innen/aussen ~0,3 wie in den alten Paletten).
        outer = WHITE
        inner = gray(79)
        n = circle_note(outer, inner, gray(150))
        imgs["mania-note%d" % k] = n
        imgs["mania-note%dH" % k] = n
        b = canvas(W, 16)
        bd = ImageDraw.Draw(b)
        bd.rectangle((52 * SS, 0, (W - 52) * SS, 16 * SS), fill=rgba(gray(245), 200))
        b = b.filter(ImageFilter.GaussianBlur(1.5 * SS))
        imgs["mania-note%dL" % k] = finish(b, W, 16)
        # Ende des Holds: abgerundete Kappe in Koerperbreite/-farbe, KEIN Kreis
        # (Nutzer: Ball am Slider-Ende stoert).
        imgs["mania-note%dT" % k] = body_cap(gray(176), 52, 200)
        for pressed in (False, True):
            ky = canvas(W, W)
            kd = ImageDraw.Draw(ky)
            cc = W * SS / 2
            R = (W / 2 - 12) * SS
            if pressed:
                kd.ellipse((cc - R, cc - R, cc + R, cc + R), fill=rgba(key_outer, 150))
            kd.ellipse((cc - R, cc - R, cc + R, cc + R), outline=rgba(key_outer, 255 if pressed else 140), width=6 * SS)
            imgs["mania-key%d%s" % (k, "D" if pressed else "")] = finish(ky, W, W)
    imgs.update(stage_images((80, 84, 110), (170, 170, 200)))
    o1, o2 = pal[1][0], pal[2][0]
    write_skin("Kreise", "Kreise", [], imgs, [o1, o2, o2, o1])


# ------------------------------------------------------------------ Pfeile
ARROW_COLS = [(150, 190, 232), (224, 160, 190), (168, 214, 168), (232, 200, 140)]  # links/unten/oben/rechts
DIRS = ["left", "down", "up", "right"]


def arrow_poly(direction, size, pad, thick):
    s = size
    cx = s / 2
    hw = s / 2 - pad
    top = pad
    head_h = (s - 2 * pad) * 0.52
    neck = hw * thick
    pts = [(cx, top), (cx + hw, top + head_h), (cx + neck, top + head_h), (cx + neck, s - pad),
           (cx - neck, s - pad), (cx - neck, top + head_h), (cx - hw, top + head_h)]
    a = math.radians({"up": 0, "right": 90, "down": 180, "left": 270}[direction])
    out = []
    for x, y in pts:
        dx, dy = x - cx, y - s / 2
        out.append((cx + dx * math.cos(a) - dy * math.sin(a), s / 2 + dx * math.sin(a) + dy * math.cos(a)))
    return out


def draw_arrow(direction, c, outline_only=False, size=W):
    im = canvas(size, size)
    d = ImageDraw.Draw(im)
    pts = [(x * SS, y * SS) for x, y in arrow_poly(direction, size, 14, 0.42)]
    if outline_only:
        d.polygon(pts, fill=rgba(c, 40))
        d.line(pts + [pts[0]], fill=rgba(c, 200), width=6 * SS, joint="curve")
    else:
        d.polygon(pts, fill=rgba(mix(c, (0, 0, 0), 0.18)))   # neutral: c = weiss -> 209
        m = size * SS / 2
        inner = [(m + (x - m) * 0.72, m + (y - m) * 0.72) for x, y in pts]
        d.polygon(inner, fill=rgba(c))
    return finish(im, size, size)


def skin_pfeile():
    imgs = {}
    for col in range(4):
        c = ARROW_COLS[col]
        n = draw_arrow(DIRS[col], WHITE)
        nm = "mania-arrow%d" % col
        imgs[nm] = n
        imgs[nm + "H"] = n
        b = canvas(W, 16)
        ImageDraw.Draw(b).rectangle((66 * SS, 0, (W - 66) * SS, 16 * SS), fill=rgba(gray(212), 215))
        imgs[nm + "L"] = finish(b, W, 16)
        t = canvas(W, 24)
        rrect(ImageDraw.Draw(t), (66, 0, W - 66, 14), 7, fill=rgba(gray(153), 215))
        imgs[nm + "T"] = finish(t, W, 24)
        imgs["mania-karrow%d" % col] = draw_arrow(DIRS[col], c, outline_only=True)
        pressed = draw_arrow(DIRS[col], mix(c, (255, 255, 255), 0.15))
        pressed.putalpha(pressed.split()[3].point(lambda v: int(v * 0.8)))
        imgs["mania-karrow%dD" % col] = pressed
    lines = []
    for col in range(4):
        lines.append("NoteImage%d: mania-arrow%d" % (col, col))
        lines.append("KeyImage%d: mania-karrow%d" % (col, col))
        lines.append("KeyImage%dD: mania-karrow%dD" % (col, col))
    imgs.update(stage_images((76, 82, 104), (160, 168, 196)))
    write_skin("Pfeile", "Pfeile", lines, imgs, ARROW_COLS)


if __name__ == "__main__":
    skin_balken()
    skin_kreise()
    skin_pfeile()
    print("ok")
