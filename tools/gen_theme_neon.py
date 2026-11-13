#!/usr/bin/env python3
"""OMEN Welt-Thema "Neon": Synthwave-Nacht als equirektangulares Panorama.

Erzeugt assets_game/themes/neon/neon_sky.webp (Standard 4096x2048):
  - Nachthimmel violett -> magenta -> Glut am Horizont, feiner Nebel-Dunst,
    Sterne (Farbe, Potenzgesetz-Helligkeit, Halos der hellsten).
  - Riesige Retro-Sonne vorn am Horizont: Verlauf gelb -> orange -> pink,
    Scanline-Luecken, die nach unten breiter werden, weicher Halo,
    duenne Wolkenstreifen davor.
  - Zwei Gebirgsketten seitlich (Kammlinie mit Neonsaum, Hoehenlinien).
  - Neon-Skyline in der Mitte (Fern- und Nahschicht): Fenster, Neonkanten
    Magenta/Cyan, Leuchtschilder, Antennen mit Positionslicht, Bodennebel.
  - Boden: fast schwarz mit Horizont-Dunst und schwacher Sonnenspiegelung.
    Das Neon-Gitter selbst zeichnet shaders/theme_neon.gdshader (animiert,
    Beat-Welle, Mitte frei) - nicht im Bild.

Abbildung identisch zu shaders/sky_panorama.gdshader / theme_neon.gdshader:
  u = atan(d.x, -d.z) / 2pi + 0.5   (u=0.5 = vorn, -Z)
  v = 0.5 - asin(d.y) / pi          (v=0 = Zenit)
Kodierung: wurzel-kodiert (gespeichert sqrt(linear) als sRGB), der Shader
dekodiert mit pow(textur, 2.0) - mehr 8-Bit-Stufen in den dunklen Verlaeufen.

Reproduzierbar per Seed:
  python tools/gen_theme_neon.py                       # 4096x2048
  python tools/gen_theme_neon.py --width 2048 --preview <ordner>
  python tools/gen_theme_neon.py --seed 3              # andere Skyline/Sterne
--preview schreibt eine Ansicht wie die Komfort-Kamera (fov 62, Neigung -16)
und eine verkleinerte Gesamtansicht als PNG.
"""
import argparse
import math
import os
import time

import numpy as np
from PIL import Image
from scipy import ndimage

F32 = np.float32
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets_game", "themes", "neon")

# Sonne (Grad): Mitte knapp ueber dem Horizont, unteres Drittel hinter Boden/Stadt.
SUN_LAT = 6.5
SUN_R = 11.5


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def hexcol(h, k=1.0):
    h = h.lstrip("#")
    return srgb_to_lin([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]) * k


def ramp(x, keys):
    """Farbverlauf: keys = [(pos, rgb_lin), ...] aufsteigend nach pos."""
    xs = np.array([k[0] for k in keys], dtype=np.float64)
    cs = np.array([k[1] for k in keys], dtype=np.float64)
    return np.stack([np.interp(x, xs, cs[:, i]) for i in range(3)], -1).astype(F32)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def fbm2(rng, H, W, base=(3, 6), octaves=7, gain=0.55):
    """Periodisches fbm (wickelt in Laengsrichtung um), Mittel 0, ~Std 0.5."""
    acc = np.zeros((H, W), F32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        h, w = base[0] << o, base[1] << o
        if h > H // 2 or w > W // 2:
            break
        g = rng.standard_normal((h, w)).astype(F32)
        up = ndimage.zoom(g, (H / h, W / w), order=3, mode="grid-wrap", grid_mode=True)
        acc += amp * up[:H, :W]
        norm += amp
        amp *= gain
    return acc / norm


def fbm1(rng, W, base=6, octaves=8, gain=0.55):
    acc = np.zeros(W, F32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        n = base << o
        if n > W // 2:
            break
        g = rng.standard_normal(n).astype(F32)
        up = ndimage.zoom(g, W / n, order=3, mode="grid-wrap", grid_mode=True)
        acc += amp * up[:W]
        norm += amp
        amp *= gain
    return acc / norm


def ihash(*a):
    """Ganzzahl-Hash -> [0,1) (vektorisiert)."""
    h = np.uint64(1469598103934665603)
    with np.errstate(over="ignore"):
        return _ihash(h, a)


def _ihash(h, a):
    for x in a:
        x = np.asarray(x).astype(np.uint64)
        h = (h ^ x) * np.uint64(1099511628211)
        h ^= h >> np.uint64(29)
    return ((h >> np.uint64(11)) & np.uint64(0xFFFFF)).astype(np.float64) / float(0x100000)


# ---------------------------------------------------------------------------
# Farben (sRGB-Hex -> linear, mit Helligkeitsfaktor)
MAGENTA = hexcol("#ff2bd6")
CYAN = hexcol("#19f0ff")
VIOLET = hexcol("#8a3cff")
PINK = hexcol("#ff4f9a")
AMBER = hexcol("#ffb347")

SKY_FRONT = [  # Elevation (Grad) -> Farbe, Sonnenseite
    (0.0, hexcol("#ff5c8a", 0.42)),
    (2.0, hexcol("#ff3478", 0.34)),
    (6.0, hexcol("#b0187c", 0.18)),
    (12.0, hexcol("#5a127a", 0.10)),
    (22.0, hexcol("#260d5a", 0.055)),
    (38.0, hexcol("#140a3c", 0.05)),
    (60.0, hexcol("#08061f", 0.04)),
    (90.0, hexcol("#040314", 0.035)),
]
SKY_BACK = [  # Rueckseite: kuehler, dunkler
    (0.0, hexcol("#9a2fc0", 0.20)),
    (4.0, hexcol("#5a1c96", 0.12)),
    (14.0, hexcol("#26105a", 0.07)),
    (38.0, hexcol("#120a36", 0.045)),
    (90.0, hexcol("#040314", 0.035)),
]
GROUND = [  # Tiefe unter dem Horizont (Grad) -> Farbe
    (0.0, hexcol("#ff3d8a", 0.16)),
    (0.8, hexcol("#b01a74", 0.07)),
    (3.0, hexcol("#3a0c48", 0.022)),
    (10.0, hexcol("#120520", 0.008)),
    (90.0, hexcol("#040108", 0.004)),
]
SUN = [  # t: -1 unten .. 1 oben
    (-1.0, hexcol("#c8006e", 0.42)),
    (-0.45, hexcol("#ff1f6a", 0.55)),
    (0.05, hexcol("#ff5a3c", 0.66)),
    (0.5, hexcol("#ffa040", 0.74)),
    (1.0, hexcol("#ffe873", 0.82)),
]


class Pano:
    def __init__(self, W):
        self.W, self.H = W, W // 2
        self.ppd = W / 360.0  # Pixel pro Grad
        v = (np.arange(self.H) + 0.5) / self.H
        u = (np.arange(self.W) + 0.5) / self.W
        self.lat = ((0.5 - v) * 180.0).astype(F32)  # Grad, +oben
        self.lon = ((u - 0.5) * 360.0).astype(F32)  # Grad, 0 = vorn
        self.img = np.zeros((self.H, self.W, 3), F32)

    def row(self, lat):
        return int(round((0.5 - lat / 180.0) * self.H))

    def col(self, lon):
        return int(round((lon / 360.0 + 0.5) * self.W)) % self.W


# ---------------------------------------------------------------------------
def paint_sky(P, rng):
    E = P.lat[:, None]
    L = P.lon[None, :]
    front = np.exp(-(L / 75.0) ** 2).astype(F32)[..., None]
    up = P.lat >= 0
    ef = ramp(P.lat[up], SKY_FRONT)[:, None, :]
    eb = ramp(P.lat[up], SKY_BACK)[:, None, :]
    P.img[up] = ef * front + eb * (1.0 - front)
    # Ferner Dunst: zwei fbm-Felder (Dichte, Farbe), nur im oberen Himmel.
    n = fbm2(rng, P.H, P.W)
    hue = fbm2(rng, P.H, P.W, base=(2, 4), octaves=5)
    band = smoothstep(8.0, 22.0, E) * (1.0 - smoothstep(55.0, 80.0, E))
    # Diagonales, galaxienartiges Band (leicht schraeg ueber den Himmel).
    gal = np.exp(-((E - 30.0 - 14.0 * np.sin(np.radians(L) + 0.6)) / 13.0) ** 2)
    dens = np.clip(n * 1.6 + 0.15, 0.0, None) ** 2 * band * (0.35 + 0.9 * gal)
    hm = smoothstep(-0.3, 0.3, hue)[..., None]
    col = VIOLET * (1 - hm) + hexcol("#2a8cff") * hm
    P.img += (dens[..., None] * col * 0.035).astype(F32)
    # Hauch von Magenta-Dunst tief am Himmel ueber der Stadt.
    low = np.exp(-(np.maximum(E, 0.0) / 9.0)) * (E >= 0) * np.exp(-(L / 50.0) ** 2)
    P.img += (low[..., None] * hexcol("#ff2b9a", 0.05)).astype(F32)


def paint_stars(P, rng):
    W, H = P.W, P.H
    n = int(14000 * (W / 4096.0) ** 0.6)
    z = rng.uniform(math.sin(math.radians(2.0)), 1.0, n)
    lat = np.degrees(np.arcsin(z))
    lon = rng.uniform(-180.0, 180.0, n)
    b = (rng.pareto(1.7, n) + 1.0) * 0.022
    b = np.minimum(b, 1.6)
    b *= smoothstep(4.0, 18.0, lat) * (0.55 + 0.45 * rng.random(n))
    palette = np.array([hexcol("#dfe8ff"), hexcol("#9feaff"), hexcol("#ffb8ec"),
                        hexcol("#ffffff"), hexcol("#c8a8ff")])
    pick = rng.choice(len(palette), n, p=[0.34, 0.24, 0.16, 0.16, 0.10])
    cols = palette[pick]
    x = (lon / 360.0 + 0.5) * W - 0.5
    y = (0.5 - lat / 180.0) * H - 0.5
    cl = np.maximum(np.cos(np.radians(lat)), 0.25)

    def splat(sel, sigma, gain, rad):
        xs, ys, bs, cs, c = x[sel], y[sel], b[sel] * gain, cols[sel], cl[sel]
        x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
        flat = P.img.reshape(-1, 3)
        acc_w = np.zeros(len(xs))
        parts = []
        for dy in range(-rad, rad + 2):
            for dx in range(-rad, rad + 2):
                px, py = x0 + dx, y0 + dy
                w = np.exp(-(((px - xs) * c) ** 2 + (py - ys) ** 2) / (2 * sigma * sigma))
                acc_w += w
                parts.append((px, py, w))
        for px, py, w in parts:
            ok = (py >= 0) & (py < H)
            idx = py[ok] * W + (px[ok] % W)
            val = (bs[ok] * w[ok] / acc_w[ok])[:, None] * cs[ok]
            np.add.at(flat, idx, val.astype(F32))

    splat(np.ones(n, bool), 0.62, 1.0, 2)
    bright = b > np.quantile(b, 0.985)
    splat(bright, 2.6, 0.30, 6)


def paint_sun(P, rng):
    """Retro-Sonne + Halo + Wolkenstreifen (nur im relevanten Ausschnitt)."""
    r0, r1 = P.row(80.0), P.row(-8.0)
    c0, c1 = P.col(-110.0), P.col(110.0)
    E = P.lat[r0:r1, None].astype(np.float64)
    L = P.lon[None, c0:c1].astype(np.float64)
    er, lr, sr = np.radians(E), np.radians(L), math.radians(SUN_LAT)
    cosd = np.cos(er) * math.cos(sr) * np.cos(lr) + np.sin(er) * math.sin(sr)
    d = np.degrees(np.arccos(np.clip(cosd, -1.0, 1.0)))
    t = np.clip((E - SUN_LAT) / SUN_R, -1.0, 1.0)
    reg = P.img[r0:r1, c0:c1]

    # Halo: enger heller Kranz + breiter Schein (hinter allem, auch in den Luecken).
    halo = (0.16 * np.exp(-np.maximum(d - SUN_R, 0.0) / (0.22 * SUN_R))
            + 0.06 * np.exp(-(d / (2.4 * SUN_R)) ** 2)
            + 0.018 * np.exp(-(d / (5.0 * SUN_R)) ** 2))
    hc = ramp(np.clip(t * 0.8, -1, 1), [(-1.0, hexcol("#ff1f7a")), (0.0, hexcol("#ff3f6a")),
                                         (1.0, hexcol("#ff7a4a"))])
    reg += (halo[..., None] * hc).astype(F32)

    # Scheibe mit Scanline-Luecken: unterhalb t=0.3, 9 Baender, Luecke waechst nach unten.
    disk = np.clip((SUN_R - d) * P.ppd + 0.5, 0.0, 1.0)
    T0, NB = 0.42, 8
    s = (T0 - t) / (1.0 + T0)
    k = s * NB
    fr = k - np.floor(k)
    duty = 0.07 + 0.62 * np.clip(s, 0, 1) ** 1.1
    band_px = SUN_R * (1.0 + T0) / NB * P.ppd
    inside = fr < duty
    sd = np.where(inside, np.minimum(fr, duty - fr), -np.minimum(fr - duty, 1.0 - fr)) * band_px
    gap = np.clip(sd + 0.5, 0.0, 1.0) * (s > 0)
    alpha = disk * (1.0 - gap)
    sc = ramp(t, SUN)
    # Leichte Randverdunklung + heller Kern oben.
    limb = 1.0 - 0.18 * (d / SUN_R) ** 3
    sc = sc * np.clip(limb, 0.6, 1.0)[..., None]
    reg[:] = reg * (1.0 - alpha[..., None]) + sc * alpha[..., None]

    # Wolkenstreifen: duenne, dunkle Stratus-Baender mit pinkem Saum unten.
    W = c1 - c0
    for e0, th, amp, cov in ((14.6, 0.30, 0.8, 0.10), (11.8, 0.22, 0.7, 0.20),
                             (19.5, 0.20, 0.55, 0.30), (3.6, 0.45, 0.45, -0.05)):
        wob = fbm1(rng, W, base=2, octaves=5) * 0.35
        cv = smoothstep(cov - 0.12, cov + 0.25, fbm1(rng, W, base=4, octaves=7) + 0.35)
        thick = th * (0.6 + 0.8 * np.clip(fbm1(rng, W, base=5) + 0.5, 0, 1.5))
        y = (E - e0 - wob[None, :]) / thick[None, :]
        prof = np.exp(-y * y) * cv[None, :] * amp
        prof *= np.exp(-(L / 55.0) ** 2)
        lit = np.exp(-((y + 1.1) / 0.6) ** 2) * cv[None, :]
        near_sun = np.exp(-np.maximum(d - SUN_R * 0.9, 0.0) / (0.5 * SUN_R))
        cc = hexcol("#1c0830", 0.5)
        reg[:] = reg * (1.0 - prof[..., None]) + cc * prof[..., None]
        reg += (lit * near_sun * 0.10)[..., None] * hexcol("#ff4f8a").astype(F32)


def paint_mountains(P, rng):
    """Zwei Ketten seitlich; Mitte (Sonne/Stadt) frei."""
    L = P.lon
    absl = np.abs(L)
    for layer, (hmax, haze, rim, rimk, contour) in enumerate((
            (8.5, 0.62, VIOLET, 0.22, 0.0),
            (5.6, 0.18, MAGENTA, 0.55, 1.0))):
        n = fbm1(rng, P.W, base=10 + 6 * layer, octaves=8, gain=0.5)
        ridge = 1.0 - np.abs(n * 2.2)
        ridge = np.clip(ridge, 0, 1) ** 1.6
        env = smoothstep(20.0 - 4 * layer, 40.0 - 6 * layer, absl) * (0.75 + 0.25 * np.cos(np.radians(L) * 3.0 + layer))
        h = (hmax * (0.25 + 0.75 * ridge) * env).astype(F32)
        r0 = P.row(hmax + 1.0)
        r1 = P.row(0.0)
        E = P.lat[r0:r1, None]
        hh = h[None, :]
        cov = np.clip((hh - E) * P.ppd + 0.5, 0.0, 1.0) * (hh > 0.05)
        reg = P.img[r0:r1]
        depth = np.clip((hh - E) / np.maximum(hh, 0.3), 0, 1)  # 0 Kamm .. 1 Fuss
        base = hexcol("#0a0418", 0.6) * (1 - depth[..., None] * 0.5)
        sky_here = reg.copy()
        col = base * (1 - haze) + sky_here * haze * 0.9
        # Nebel am Fuss: Richtung Horizont-Dunst.
        fog = np.exp(-np.maximum(E, 0) / (1.1 + layer * 0.3))[..., None]
        col = col * (1 - fog * 0.55) + hexcol("#ff3a8a", 0.13) * fog * 0.55
        if contour > 0:
            # Hoehenlinien (Tron-Berge): fein, zum Fuss hin im Nebel.
            ph = (E * P.ppd / 7.0)
            f = np.abs(ph - np.round(ph)) * 7.0
            cl = np.clip(1.0 - f, 0, 1) * (1 - fog[..., 0]) * 0.5 * (1 - depth * 0.6)
            col += (cl[..., None] * CYAN * 0.05).astype(F32)
        reg[:] = reg * (1 - cov[..., None]) + col * cov[..., None]
        # Neonsaum auf dem Kamm (+ Schein darueber).
        dist = (hh - E) * P.ppd  # >0 innen
        edge = np.exp(-((dist - 0.6) / 0.75) ** 2) * (hh > 0.2)
        glow = np.exp(-np.abs(dist) / 4.0) * (dist < 0) * (hh > 0.2)
        reg += ((edge * rimk + glow * rimk * 0.12)[..., None] * rim).astype(F32)


def make_buildings(rng, lo, hi, wmin, wmax, hfun, gapp):
    out = []
    x = lo
    while x < hi:
        w = rng.uniform(wmin, wmax)
        if rng.random() < gapp:
            x += w * rng.uniform(0.2, 0.8)
            continue
        out.append((x, x + w, max(0.4, hfun(x + w / 2))))
        x += w
    return out


def paint_city(P, rng):
    W = P.W
    cx = (np.arange(W) + 0.5)
    lon = P.lon

    def raster(blds, style_seed):
        hcol = np.zeros(W, F32)
        bid = np.full(W, -1, np.int64)
        x0c = np.zeros(W, np.int64)
        for i, (a, b, h) in enumerate(blds):
            ca, cb = P.col(a), P.col(b)
            if cb <= ca:
                continue
            seg = np.arange(ca, cb)
            r = ihash(style_seed, i, 7)
            hh = np.full(len(seg), h, F32)
            wpx = cb - ca
            if r < 0.22 and wpx > 6:  # Stufen-Dach
                inset = max(2, wpx // 4)
                hh[:inset] = h * 0.82
                hh[-inset:] = h * 0.82
            elif r < 0.34 and wpx > 6:  # Pyramiden-/Spitzdach
                m = np.abs(np.arange(wpx) - (wpx - 1) / 2) / (wpx / 2)
                hh = h * (1.0 - 0.28 * m)
            elif r < 0.42 and wpx > 8:  # abgeschraegt
                hh = h * (0.86 + 0.14 * np.arange(wpx) / wpx)
            take = hh > hcol[seg]
            hcol[seg[take]] = hh[take]
            bid[seg[take]] = i
            x0c[seg[take]] = ca
        return hcol, bid, x0c

    # Fernschicht: dicht, mittelhoch, im Dunst.
    far = make_buildings(rng, -36, 36, 0.35, 1.3,
                         lambda x: 0.8 + 3.2 * math.exp(-(x / 17) ** 2) * rng.uniform(0.5, 1.25)
                         + rng.uniform(0, 0.8), 0.04)
    # Nahschicht: breiter, Tuerme in der Mitte, Luecken (Sonne scheint durch).
    def near_h(x):
        c = math.exp(-(x / 11.0) ** 2)
        tower = rng.random() < 0.18
        return 0.4 + (3.4 * c + 0.8) * rng.uniform(0.35, 1.0) + (2.0 * c if tower else 0.0)
    near = make_buildings(rng, -30, 30, 0.7, 2.3, near_h, 0.16)

    for li, (blds, fog_k, base_c, win_k, rim_k) in enumerate((
            (far, 0.55, hexcol("#2a0c46", 0.10), 0.45, 0.0),
            (near, 0.22, hexcol("#06020e", 0.6), 1.0, 1.0))):
        seed = 1000 + li
        hcol, bid, x0c = raster(blds, seed)
        top = float(hcol.max()) + 4.0
        r0, r1 = P.row(top), P.row(0.0) + 1
        E = P.lat[r0:r1, None]
        rows = np.arange(r0, r1)[:, None]
        hh = hcol[None, :]
        inside = (E < hh) & (bid[None, :] >= 0)
        reg = P.img[r0:r1]
        fog = np.exp(-np.maximum(E, 0) / (0.9 + 0.6 * li))[..., None] * fog_k
        col = np.broadcast_to(base_c, reg.shape).astype(F32).copy()
        # Leichtes Hinterlicht von der Sonne auf den Kanten der Fernschicht.
        if li == 0:
            col += (np.exp(-(lon[None, :] / 14.0) ** 2) * 0.02)[..., None] * PINK
        # Fenster: Pixelraster je Gebaeude, zufaellig beleuchtet.
        lx = np.arange(W)[None, :] - x0c[None, :]
        ly = rows - np.array([P.row(h) for h in hcol])[None, :]
        b2 = np.broadcast_to(bid[None, :], lx.shape)
        lit_rate = 0.12 + 0.30 * ihash(seed, b2, 3)
        if li == 0:
            wm = (lx % 3 == 1) & (ly % 3 == 2) & (ly > 1)
        else:
            wm = (lx % 3 == 1) & ((ly % 4 == 1) | (ly % 4 == 2)) & (ly > 2)
        on = ihash(seed, b2, lx // 3, ly // 4) < lit_rate
        wsel = ihash(seed, b2, 11)
        wcol = np.where((wsel < 0.45)[..., None], hexcol("#ff9ad8"),
                        np.where((wsel < 0.8)[..., None], hexcol("#8ff4ff"), hexcol("#ffc27a")))
        wint = (0.035 + 0.09 * ihash(seed, b2, lx, ly)) * win_k
        col += ((wm & on) * wint)[..., None] * wcol
        # Leuchtschilder (Nahschicht): senkrechte Neonstreifen an einigen Fassaden.
        if li == 1:
            nb = len(blds)
            sign = ihash(seed, np.arange(nb), 21) < 0.28
            sign_col = np.where((ihash(seed, np.arange(nb), 22) < 0.5)[:, None], MAGENTA, CYAN)
            sx = (ihash(seed, np.arange(nb), 23) * 0.6 + 0.2)
            bw = np.array([max(1, P.col(b) - P.col(a)) for a, b, _ in blds])
            hpx = np.array([max(1, P.row(0.0) - P.row(h)) for _, _, h in blds])
            bi = np.clip(b2, 0, nb - 1)
            pos = (lx == np.floor(sx[bi] * bw[bi]).astype(int)) | (lx == np.floor(sx[bi] * bw[bi]).astype(int) + 1)
            vy = (ly > hpx[bi] * 0.12) & (ly < hpx[bi] * 0.55)
            s_on = sign[bi] & pos & vy & (bw[bi] > 8)
            col += (s_on * 0.55)[..., None] * sign_col[bi]
            # Waagerechtes Band unter dem Dach.
            band = (ihash(seed, np.arange(nb), 24) < 0.25)[bi] & (ly == 3) & (lx > 1) & (lx < bw[bi] - 2)
            col += (band * 0.35)[..., None] * sign_col[bi]
        col = col * (1 - fog) + hexcol("#ff3a8a", 0.16) * fog
        reg[:] = np.where(inside[..., None], col, reg)

        if rim_k > 0:
            # Neonkanten: Dachlinie + freistehende Seitenkanten, je Gebaeude Magenta/Cyan.
            m = inside
            up = np.zeros_like(m)
            up[1:] = m[:-1]
            left = np.roll(m, 1, axis=1)
            right = np.roll(m, -1, axis=1)
            edge = m & (~up | ~left | ~right)
            nb = len(blds)
            has = ihash(seed, np.arange(nb), 31) < 0.66
            ecol = np.where((np.arange(nb) % 3 == 0)[:, None], CYAN, MAGENTA)
            bi = np.clip(b2, 0, nb - 1)
            ek = (edge & has[bi]).astype(F32) * (1 - fog[..., 0] * 1.6).clip(0, 1)
            e3 = ek[..., None] * ecol[bi] * 0.8
            glow = np.stack([ndimage.gaussian_filter(e3[..., c], 2.2, mode="wrap") for c in range(3)], -1)
            reg += (e3 + glow * 0.9).astype(F32)
            # Antennen auf den hoechsten Tuermen mit Positionslicht.
            order = np.argsort([-h for _, _, h in blds])[:7]
            for j in order:
                a, b, h = blds[j]
                c = P.col((a + b) / 2)
                ah = h + 0.8 + 1.8 * ihash(seed, j, 41)
                ra, rb = P.row(ah) - r0, P.row(h) - r0
                reg[ra:rb, c] = reg[ra:rb, c] * 0.2 + hexcol("#1a0c26", 0.3)
                yy, xx = np.mgrid[-6:7, -6:7]
                spot = np.exp(-(xx * xx + yy * yy) / 2.0)[..., None] * hexcol("#ff3b5c") * 0.9
                spot += np.exp(-(xx * xx + yy * yy) / 18.0)[..., None] * hexcol("#ff3b5c") * 0.12
                y0, x0 = ra - 6, c - 6
                if y0 >= 0:
                    reg[y0:y0 + 13, x0:x0 + 13] += spot.astype(F32)


def paint_horizon_ground(P, rng):
    E = P.lat[:, None]
    L = P.lon[None, :]
    down = P.lat < 0
    front = np.exp(-(L / 70.0) ** 2)
    g = ramp(-P.lat[down], GROUND)[:, None, :]
    fr = front[..., None]
    P.img[down] = g * (0.45 + 0.55 * fr)
    # Sonnenspiegelung auf dem nassen Boden: schmal, schwach (Mitte bleibt lesbar).
    ed = np.minimum(E, 0.0)
    refl = 0.05 * np.exp(-(L / 5.5) ** 2) * np.exp(ed / 2.2) * (E < 0)
    sh = 0.5 + 0.5 * np.cos(ed * P.ppd * 0.9)  # zerrissene Spiegel-Streifen
    P.img += ((refl * (0.55 + 0.45 * sh))[..., None] * hexcol("#ff3a70")).astype(F32)
    # Horizontlinie: scharfer Kern + weicher Schein, vorn heller.
    dpx = np.abs(E) * P.ppd
    line = (0.45 * np.exp(-(dpx / 0.9) ** 2) + 0.10 * np.exp(-dpx / 5.0)) * (0.35 + 0.65 * front)
    lc = hexcol("#ff3fae") * 0.8 + hexcol("#ffa0e0") * 0.2
    P.img += (line[..., None] * lc).astype(F32)


def tonemap(x):
    k = 0.72
    over = np.maximum(x - k, 0.0)
    return np.where(x < k, x, k + (1 - k) * (1 - np.exp(-over / (1 - k))))


def to_u8(lin, rng):
    s = lin_to_srgb(lin)
    s = s * 255.0 + rng.triangular(-0.5, 0, 0.5, s.shape)
    return np.clip(np.rint(s), 0, 255).astype(np.uint8)


def camera_view(pano, vw=1280, vh=720, pitch=-16.0, fov=62.0, yaw=0.0):
    H, W = pano.shape[:2]
    th = math.tan(math.radians(fov) * 0.5)
    ys, xs = np.mgrid[0:vh, 0:vw].astype(np.float64)
    x = (2 * (xs + 0.5) / vw - 1) * th * vw / vh
    y = (1 - 2 * (ys + 0.5) / vh) * th
    z = -np.ones_like(x)
    p = math.radians(pitch)
    y2 = y * math.cos(p) - z * math.sin(p)
    z2 = y * math.sin(p) + z * math.cos(p)
    yw = math.radians(yaw)
    x3 = x * math.cos(yw) + z2 * math.sin(yw)
    z3 = -x * math.sin(yw) + z2 * math.cos(yw)
    d = np.stack([x3, y2, z2 * 0 + z3], -1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    u = (np.arctan2(d[..., 0], -d[..., 2]) / (2 * math.pi) + 0.5) * W
    v = (0.5 - np.arcsin(np.clip(d[..., 1], -1, 1)) / math.pi) * H
    out = np.zeros((vh, vw, 3))
    for ch in range(3):
        out[..., ch] = ndimage.map_coordinates(pano[..., ch], [v - 0.5, u - 0.5], order=1, mode="grid-wrap")
    return out


def build(W, seed, out_dir, preview, quality):
    t0 = time.time()
    P = Pano(W)
    rng = np.random.default_rng(seed)
    paint_sky(P, np.random.default_rng(seed + 1))
    paint_stars(P, np.random.default_rng(seed + 2))
    paint_sun(P, np.random.default_rng(seed + 3))
    paint_mountains(P, np.random.default_rng(seed + 4))
    paint_city(P, np.random.default_rng(seed + 5))
    paint_horizon_ground(P, np.random.default_rng(seed + 6))
    lin = tonemap(np.clip(P.img, 0, None))
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "neon_sky.webp")
    Image.fromarray(to_u8(np.sqrt(lin), rng)).save(path, "WEBP", quality=quality, method=6)
    mb = os.path.getsize(path) / 1e6
    print("neon_sky: %dx%d  %.1f s  %.2f MB  -> %s" % (W, W // 2, time.time() - t0, mb, path))
    if preview:
        os.makedirs(preview, exist_ok=True)
        dec = srgb_to_lin(np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255.0) ** 2
        for name, yaw in (("cam_neon.png", 0.0), ("cam_neon_side.png", 60.0)):
            view = camera_view(dec, yaw=yaw)
            Image.fromarray(to_u8(np.clip(view, 0, 1), rng)).save(os.path.join(preview, name))
        small = Image.fromarray(to_u8(np.clip(lin, 0, 1), rng)).resize((2048, 1024), Image.LANCZOS)
        small.save(os.path.join(preview, "pano_neon.png"))
    return mb


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--width", type=int, default=4096)
    ap.add_argument("--seed", type=int, default=1984)
    ap.add_argument("--quality", type=int, default=95)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    mb = build(a.width, a.seed, a.out, a.preview, a.quality)
    if a.width >= 4096 and mb >= 2.5:
        raise SystemExit("WebP zu gross (%.2f MB >= 2.5 MB): --quality senken" % mb)


if __name__ == "__main__":
    main()
