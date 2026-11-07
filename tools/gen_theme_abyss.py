#!/usr/bin/env python3
"""TETHRA Welt-Thema "Abgrund": duestere Leere mit Monolithen, kein Neon.

Erzeugt (Standard 4096x2048, Seed-reproduzierbar):
  assets_game/themes/abyss/abyss_sky.webp      Panorama (Farbe, wurzel-kodiert)
  assets_game/themes/abyss/abyss_sky_fog.webp  Nebel-Ebene (Daten, verlustfrei)

Panorama:
  - Schwarze Leere, oben eine kaum sichtbare Wolkendecke mit einem einzigen
    Loch, aus dem ein kalter Lichtschacht schraeg herabfaellt (Streifen im
    Strahl, Streuschein, Lichtsee im Nebel am Horizont, matte Spiegelung auf
    dem schwarzen Boden). Kaum Sterne, nur durch Wolkenluecken.
  - Riesige ferne Monolithen, Obelisken, Saeulen, Tore in mehreren
    Tiefenebenen: Luftperspektive (ferne verschwinden im Dunst), Hoehennebel
    am Fuss, Kantenlicht zur Lichtquelle, verwitterte Kanten und Flaechen.
  - Vorn-Mitte bleibt eine Leere (das "Tor" in den Abgrund), Boden schwarz.
  Farbfamilie: nur Schwarz + kaltes Grau-Stahlblau (Farben unten).

Nebel-Ebene (keine Farbe, Datenkanaele, wurzel-kodiert: Wert = byte/255 hoch 2):
  R  tiefe Nebelbaenke am Horizont (rollen im Shader, schnelle Ebene)
  G  hoehere Dunst-Schlieren (rollen langsamer -> Parallax)
  B  sichtbarer Anteil des Lichtschachts (verdeckt durch nahe Monolithen),
     normiert; der Shader laesst damit den Schacht auf dem Beat atmen.
  shaders/theme_abyss.gdshader faerbt den Nebel selbst (fog_color/fog_lit_color)
  und beleuchtet ihn am Schacht.

Abbildung identisch zu shaders/sky_panorama.gdshader / theme_abyss.gdshader:
  u = atan(d.x, -d.z) / 2pi + 0.5   (u=0.5 = vorn, -Z)
  v = 0.5 - asin(d.y) / pi          (v=0 = Zenit)
Kodierung Panorama: gespeichert sqrt(linear) als sRGB, der Shader dekodiert
mit pow(textur, 2.0) - mehr 8-Bit-Stufen in den dunklen Verlaeufen.

  python tools/gen_theme_abyss.py                       # 4096x2048
  python tools/gen_theme_abyss.py --width 2048 --preview <ordner>
  python tools/gen_theme_abyss.py --seed 7              # andere Monolithen
--preview schreibt die Komfort-Kamera-Ansicht (fov 62, Neigung -16) vorn und
seitlich (inkl. Nebel wie im Shader, ohne Animation) und eine Gesamtansicht.
"""
import argparse
import math
import os
import time

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

F32 = np.float32
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets_game", "themes", "abyss")

# Lichtschacht (Grad). Gleiche Werte als Uniforms in theme_abyss.gdshader.
SHAFT_LON = -27.0      # Fusspunkt am Horizont
SHAFT_TOP_LON = -22.0  # Loch in der Wolkendecke
SHAFT_TOP_LAT = 58.0
SHAFT_W0 = 2.3        # halbe Breite unten
SHAFT_W1 = 0.62        # halbe Breite oben
SHAFT_DEPTH = 0.35     # Objekte mit depth > SHAFT_DEPTH stehen davor
SHAFT_PEAK = 0.62      # Normierung fuer Kanal B


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def hexcol(h, k=1.0):
    h = h.lstrip("#")
    return (srgb_to_lin([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]) * k).astype(F32)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def wrap(d):
    return (d + 180.0) % 360.0 - 180.0


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


# ---------------------------------------------------------------------------
# Farben (sRGB-Hex -> linear). Nur Schwarz + kaltes Grau-Stahlblau.
HAZE = hexcol("#6f8094")      # Horizont-Dunst
HAZE_DEEP = hexcol("#3a4757")  # Dunst in der Hoehe / Rueckseite
SHAFT = hexcol("#d8e3ef")     # Schachtlicht (kaltes Weiss)
POOL = hexcol("#a8b8ca")      # Lichtsee im Nebel
SURF = hexcol("#5a6572")      # Monolith-Flaeche (wird sehr dunkel skaliert)
RIM = hexcol("#c4d2e2")       # Kantenlicht
STAR = hexcol("#dfe8f4")


class Pano:
    def __init__(self, W):
        self.W, self.H = W, W // 2
        self.ppd = W / 360.0
        v = (np.arange(self.H) + 0.5) / self.H
        u = (np.arange(self.W) + 0.5) / self.W
        self.lat = ((0.5 - v) * 180.0).astype(F32)
        self.lon = ((u - 0.5) * 360.0).astype(F32)
        self.img = np.zeros((self.H, self.W, 3), F32)
        self.occ = np.ones((self.H, self.W), F32)  # Sichtbarkeit Schacht

    def LAT(self):
        return self.lat[:, None]

    def LON(self):
        return self.lon[None, :]

    def y(self, lat):
        return (0.5 - lat / 180.0) * self.H

    def x(self, lon):
        return (lon / 360.0 + 0.5) * self.W


# ---------------------------------------------------------------------------
def haze_lum(lat, lon):
    """Dunst-Helligkeit (linear, ohne Farbe) des leeren Himmels."""
    la = np.abs(lat)
    up = np.maximum(lat, 0.0)
    h = 0.0011 + 0.020 * np.exp(-up / 2.0) + 0.013 * np.exp(-up / 11.0) + 0.0035 * np.exp(-up / 26.0)
    # Unter dem Horizont: Dunst endet schnell im schwarzen Boden.
    h = h * np.exp(np.minimum(lat, 0.0) / 1.4)
    # Leere vorn-mitte: der Abgrund hinter dem Tor ist dunkler.
    void = 1.0 - 0.55 * np.exp(-(wrap(lon) / 11.0) ** 2) * np.exp(-la / 9.0)
    # Rueckseite etwas schwaecher, Schachtseite heller (Streuung).
    back = 0.72 + 0.28 * np.cos(np.radians(wrap(lon))) ** 2
    side = 1.0 + 0.9 * np.exp(-np.abs(wrap(lon - SHAFT_LON)) / 26.0) * np.exp(-up / 10.0)
    return h * void * back * side


def paint_sky(P, rng):
    lat, lon = P.LAT(), P.LON()
    n = fbm2(rng, P.H, P.W, base=(4, 10), octaves=6)
    h = haze_lum(lat, lon) * (0.82 + 0.36 * n)
    up = np.maximum(lat, 0.0)
    t = smoothstep(0.0, 18.0, up)
    col = HAZE[None, None, :] * (1 - t[..., None]) + HAZE_DEEP[None, None, :] * t[..., None]
    P.img += h[..., None] * col

    # Wolkendecke: nur am Loch sichtbar beleuchtet, sonst fast schwarz.
    c = fbm2(rng, P.H, P.W, base=(6, 9), octaves=7, gain=0.6)
    c2 = fbm2(rng, P.H, P.W, base=(16, 12), octaves=5, gain=0.5)
    cloud = smoothstep(-0.25, 0.55, c + 0.35 * c2) * smoothstep(16.0, 34.0, lat)
    d = ang_dist(P, SHAFT_TOP_LON, SHAFT_TOP_LAT)
    lit = 0.055 * np.exp(-d / 6.0) + 0.012 * np.exp(-d / 20.0) + 0.0011
    P.img += (cloud * lit)[..., None] * (0.55 * HAZE + 0.45 * POOL)[None, None, :]
    P.cloud = cloud


def _dir(lon, lat):
    la, lo = math.radians(lat), math.radians(lon)
    return np.array([math.cos(la) * math.sin(lo), math.sin(la), -math.cos(la) * math.cos(lo)])


def ang_dist(P, lon0, lat0):
    la, lo = np.radians(P.LAT()), np.radians(P.LON())
    a0, o0 = math.radians(lat0), math.radians(lon0)
    cd = np.sin(la) * math.sin(a0) + np.cos(la) * math.cos(a0) * np.cos(lo - o0)
    return np.degrees(np.arccos(np.clip(cd, -1.0, 1.0))).astype(F32)


def paint_stars(P, rng):
    n = 340
    lat = np.degrees(np.arcsin(rng.uniform(math.sin(math.radians(24)), 1.0, n)))
    lon = rng.uniform(-180, 180, n)
    mag = np.exp(rng.uniform(np.log(0.006), np.log(0.07), n))
    big = rng.random(n) < 0.03
    mag[big] *= 3.5
    for la, lo, m in zip(lat, lon, mag):
        if abs(wrap(lo - SHAFT_LON)) < 6 and la < 50:
            continue
        x, y = P.x(lo), P.y(la)
        xi, yi = int(x), int(y)
        if yi < 2 or yi >= P.H - 2:
            continue
        clr = 1.0 - 0.92 * P.cloud[yi, xi % P.W]
        if clr < 0.05:
            continue
        sx = 0.55 / max(math.cos(math.radians(la)), 0.08)
        ys, xs = np.mgrid[-2:3, -3:4]
        g = np.exp(-(((xs + xi + 0.5 - x) / sx) ** 2 + ((ys + yi + 0.5 - y) / 0.55) ** 2) * 0.5)
        g *= m * clr
        cols = (np.arange(-3, 4) + xi) % P.W
        P.img[yi - 2:yi + 3][:, cols] += g[..., None] * STAR[None, None, :]


# ---------------------------------------------------------------------------
def shaft_light(P, rng):
    """Lichtschacht (linear, Helligkeit) und Farbanteile."""
    lat, lon = P.LAT(), P.LON()
    # Gerader Strahl im Raum = Grosskreis zwischen Fusspunkt und Loch:
    # Abstand (Grad) zur Ebene durch beide Richtungen.
    b = _dir(SHAFT_LON, 0.0)
    t = _dir(SHAFT_TOP_LON, SHAFT_TOP_LAT)
    nrm = np.cross(b, t)
    nrm /= np.linalg.norm(nrm)
    mid = b + t
    la, lo = np.radians(lat), np.radians(lon)
    dx, dy, dz = np.cos(la) * np.sin(lo), np.sin(la) * np.ones_like(lo), -np.cos(la) * np.cos(lo)
    dl = np.degrees(np.arcsin(np.clip(dx * nrm[0] + dy * nrm[1] + dz * nrm[2], -1, 1))).astype(F32)
    side_ok = (dx * mid[0] + dy * mid[1] + dz * mid[2]) > 0
    dl = np.where(side_ok, dl, 90.0).astype(F32)
    s = np.clip(lat / SHAFT_TOP_LAT, 0.0, 1.0)
    w = SHAFT_W0 + (SHAFT_W1 - SHAFT_W0) * s
    x = dl / w
    # Streifen im Strahl (laufen mit dem Strahl), Baender wo er Dunst kreuzt.
    xs = np.linspace(-4.0, 4.0, 2048)
    st = fbm1(rng, 2048, base=10, octaves=6, gain=0.6)
    st = np.clip(st / (np.abs(st).max() + 1e-6) * 1.6, -1, 1)
    streak = np.interp(np.clip(x, -4, 4), xs, st)
    lb = fbm1(rng, 1024, base=8, octaves=6)
    band = np.interp(np.clip(lat, -10, 80), np.linspace(-10, 80, 1024), lb / (np.abs(lb).max() + 1e-6))
    ax = np.abs(x)
    core = smoothstep(1.45, 0.15, ax)
    beam = core * (0.58 + 0.42 * streak) + 0.24 * np.exp(-x * x * 0.28)
    beam += 0.30 * np.exp(-x * x * 6.0)  # heller Kern
    iv = (0.30 + 0.70 * np.exp(-np.maximum(lat, 0) / 11.0)) * (0.80 + 0.20 * band)
    iv = iv * smoothstep(-0.9, 0.9, lat) * smoothstep(SHAFT_TOP_LAT + 0.3, SHAFT_TOP_LAT - 2.5, lat)
    beam_l = 0.42 * beam * iv

    up = np.maximum(lat, 0.0)
    hv = np.exp(-up / 14.0) * smoothstep(-3.5, 0.0, lat) * smoothstep(SHAFT_TOP_LAT + 4, SHAFT_TOP_LAT - 6, lat)
    halo = (0.040 * np.exp(-np.abs(dl) / 3.2) + 0.013 * np.exp(-np.abs(dl) / 13.0)) * hv

    db = wrap(lon - SHAFT_LON)
    pool = (0.26 * np.exp(-(db / 4.6) ** 2) * np.exp(-np.abs(lat - 0.35) / 0.85)
            + 0.060 * np.exp(-(db / 14.0) ** 2) * np.exp(-np.abs(lat) / 2.4)
            + 0.016 * np.exp(-(db / 38.0) ** 2) * np.exp(-np.abs(lat) / 6.0))
    d = ang_dist(P, SHAFT_TOP_LON, SHAFT_TOP_LAT)
    # Loch = ausgerissene Wolkenluecke, kein Scheinwerfer-Kreis.
    hn = fbm2(rng, P.H, P.W, base=(24, 48), octaves=4)
    hd = d + 2.2 * hn * smoothstep(0.0, 2.5, d)
    hole = 0.36 * smoothstep(2.6, 0.4, hd) + 0.10 * np.exp(-(d / 0.9) ** 2) + 0.05 * np.exp(-d / 5.0)
    beam_col = beam_l + hole
    soft = halo + pool
    return beam_col.astype(F32), soft.astype(F32)


def paint_shaft(P, beam, soft):
    P.img += beam[..., None] * SHAFT[None, None, :] + soft[..., None] * POOL[None, None, :]


def paint_ground(P, rng):
    lat, lon = P.LAT(), P.LON()
    lo = np.minimum(lat, 0.0)
    g = 0.0002 + 0.0011 * np.exp(lo / 7.0) + 0.006 * np.exp(lo / 0.8)
    db = wrap(lon - SHAFT_LON)
    n = fbm2(rng, P.H, P.W, base=(8, 60), octaves=5)
    refl = 0.030 * np.exp(-(db / (1.3 - 0.04 * lo)) ** 2) * np.exp(lo / 3.2) * (0.55 + 0.45 * np.clip(n * 1.5 + 0.5, 0, 1))
    refl += 0.006 * np.exp(-(db / 9.0) ** 2) * np.exp(lo / 2.2)
    front = np.exp(-(wrap(lon) / 30.0) ** 2) * smoothstep(-0.5, -10.0, lat)
    gl = (g * (1.0 - 0.6 * front) + refl) * (lat < 0)
    P.img += gl[..., None] * HAZE[None, None, :]


# ---------------------------------------------------------------------------
# Monolithen: Polygone in (lon, lat) Grad, Basis unter dem Horizont.
def _top_edge(rng, x0, x1, ytop, rough, n=28, notch=0.25):
    xs = np.linspace(x0, x1, n)
    j = np.cumsum(rng.normal(0, 1, n))
    j -= np.linspace(j[0], j[-1], n)
    ys = ytop + rough * 0.35 * j / (np.abs(j).max() + 1e-6)
    if rng.random() < notch:  # ausgebrochene Ecke
        k = rng.integers(2, n // 3)
        if rng.random() < 0.5:
            ys[:k] -= rough * rng.uniform(2, 5) * np.linspace(1, 0, k)
        else:
            ys[-k:] -= rough * rng.uniform(2, 5) * np.linspace(0, 1, k)
    return list(zip(xs, ys))


def _side(rng, x, y0, y1, rough, n=10):
    ys = np.linspace(y0, y1, n)
    xs = x + rng.normal(0, rough * 0.06, n)
    xs[0] = x
    return list(zip(xs, ys))


def shape_slab(rng, lon, w, top, base=-3.0, taper=0.05, tilt=0.0):
    r = (top - base) * 0.012 + 0.04
    hw, tw = w / 2, w / 2 * (1 - taper)
    t0, t1 = top + tilt * w / 2, top - tilt * w / 2
    left = _side(rng, lon - hw, base, t0, r)
    right = _side(rng, lon + hw, t1, base, r)
    top_e = _top_edge(rng, lon - tw, lon + tw, 0.0, r)
    top_e = [(x, (t0 + (t1 - t0) * (x - (lon - tw)) / (2 * tw)) + y) for x, y in top_e]
    return [left + top_e + right]


def shape_obelisk(rng, lon, w, top, base=-3.0):
    hw = w / 2
    sh = top - w * 0.9
    tw = hw * 0.62
    return [[(lon - hw, base), (lon - tw, sh), (lon, top), (lon + tw, sh), (lon + hw, base)]]


def shape_pillar(rng, lon, w, top, base=-3.0, broken=False):
    hw = w / 2
    r = w * 0.05
    polys = []
    if broken:
        e = _top_edge(rng, lon - hw, lon + hw, top, w * 0.8, n=12, notch=0.0)
        e[0] = (lon - hw, top - w * rng.uniform(0.2, 1.2))
        e[-1] = (lon + hw, top - w * rng.uniform(0.2, 1.2))
        polys.append([(lon - hw, base)] + e + [(lon + hw, base)])
    else:
        ch = w * 0.55
        polys.append([(lon - hw, base), (lon - hw, top - ch), (lon + hw, top - ch), (lon + hw, base)])
        cw = hw * 1.32
        polys.append([(lon - cw, top - ch - r), (lon - cw, top), (lon + cw, top), (lon + cw, top - ch - r)])
    return polys


def shape_gate(rng, lon, w, top, base=-3.0):
    pw = w * 0.2
    lh = (top - base) * 0.13
    a = shape_slab(rng, lon - w / 2 + pw / 2, pw, top - lh * 0.4, base, taper=0.02)
    b = shape_slab(rng, lon + w / 2 - pw / 2, pw, top - lh * 0.4, base, taper=0.02)
    lint = shape_slab(rng, lon, w * 1.08, top, top - lh, taper=0.0, tilt=rng.uniform(-0.02, 0.02))
    return a + b + lint


def shape_lean(rng, lon, w, top, base=-3.0, ang=8.0):
    polys = shape_slab(rng, lon, w, top, base)
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    out = []
    for p in polys:
        out.append([(lon + (x - lon) * c + (y - base) * s, base - (x - lon) * s + (y - base) * c) for x, y in p])
    return out


def raster(P, polys, ss=4):
    """Antialiasierte Abdeckung im Bounding-Box-Fenster (Spalten wickeln)."""
    pts = [pt for p in polys for pt in p]
    lo0 = min(p[0] for p in pts) - 0.5
    lo1 = max(p[0] for p in pts) + 0.5
    la0 = min(p[1] for p in pts) - 0.5
    la1 = max(p[1] for p in pts) + 0.5
    x0 = int(math.floor(P.x(lo0))) - 4
    x1 = int(math.ceil(P.x(lo1))) + 4
    y0 = max(int(math.floor(P.y(la1))) - 4, 0)
    y1 = min(int(math.ceil(P.y(la0))) + 4, P.H)
    w, h = x1 - x0, y1 - y0
    im = Image.new("L", (w * ss, h * ss), 0)
    dr = ImageDraw.Draw(im)
    for p in polys:
        dr.polygon([((P.x(a) - x0) * ss, (P.y(b) - y0) * ss) for a, b in p], fill=255)
    m = np.asarray(im, dtype=F32) / 255.0
    return m, x0, y0, ss


def down(m, ss):
    h, w = m.shape[0] // ss, m.shape[1] // ss
    return m[:h * ss, :w * ss].reshape(h, ss, w, ss).mean(axis=(1, 3))


def paint_object(P, rng, polys, lon, depth, fog_h):
    m_ss, x0, y0, ss = raster(P, polys)
    cov = down(m_ss, ss)
    h, w = cov.shape
    cols = np.arange(x0, x0 + w) % P.W
    rows = slice(y0, y0 + h)
    lat = P.lat[rows][:, None]
    lonv = P.lon[cols][None, :]
    bg = P.img[rows][:, cols]

    # Kanten: zur Lichtquelle (seitlich) und oben (Licht von oben).
    dls = wrap(lon - SHAFT_LON)
    k = int(1.6 * ss)
    if dls < 0:
        sh = np.zeros_like(m_ss); sh[:, :-k] = m_ss[:, k:]
    else:
        sh = np.zeros_like(m_ss); sh[:, k:] = m_ss[:, :-k]
    # Weiche Kante: schmales Band an der Lichtseite, nach innen verlaufend.
    rim_side = down(ndimage.gaussian_filter(np.clip(m_ss - sh, 0, 1), k * 0.7) * m_ss, ss)
    kt = int(1.2 * ss)
    st = np.zeros_like(m_ss); st[kt:, :] = m_ss[:-kt, :]
    rim_top = down(ndimage.gaussian_filter(np.clip(m_ss - st, 0, 1), kt * 0.7) * m_ss, ss)

    near = np.exp(-np.abs(wrap(lonv - SHAFT_LON)) / 16.0)
    lowlit = np.exp(-np.maximum(lat, 0) / 7.0)
    front = depth < SHAFT_DEPTH
    rk = (0.10 if front else 0.20) * near * (0.35 + 0.65 * lowlit)
    rk = rk * near
    rim = rim_side * rk + rim_top * (0.0008 + 0.05 * near * near)

    # Flaeche: Streifen + Schichten + Flecken, sehr dunkel.
    wpx = max(w, 8)
    strip = np.interp(np.arange(w), np.linspace(0, w, wpx), fbm1(rng, wpx, base=max(2, wpx // 24), octaves=4))
    lay = np.interp(np.arange(h), np.linspace(0, h, max(h, 8)), fbm1(rng, max(h, 8), base=max(2, h // 40), octaves=4))
    tex = np.clip(0.75 + 0.55 * strip[None, :] + 0.35 * lay[:, None], 0.25, 1.8)
    surf = 0.0011 * tex * (1.0 - 0.5 * depth)
    if front:  # hinter dem Schacht: von vorn angestrahlt
        surf = surf + 0.030 * np.exp(-np.abs(wrap(lonv - SHAFT_LON)) / 6.5) * lowlit * tex
    # Luftperspektive + Hoehennebel am Fuss.
    T = 0.22 + 0.76 * depth ** 0.8
    T = T * (0.15 + 0.85 * smoothstep(-0.8, fog_h, lat))
    col = surf[..., None] * SURF[None, None, :] / SURF.max() + rim[..., None] * RIM[None, None, :]
    obj = bg * (1.0 - T[..., None]) + col * T[..., None]
    a = cov[..., None]
    P.img[rows.start:rows.stop, cols] = bg * (1 - a) + obj * a
    if not front:
        P.occ[rows.start:rows.stop, cols] *= 1.0 - cov


def make_objects(rng):
    """(depth, kind, lon, w, top, extra) - von fern nach nah sortiert."""
    O = [
        # Fernste Riesen im Dunst (Mitte: der Monolith hinter dem Tor).
        (0.03, "slab", 1.5, 6.5, 22.0, {}),
        (0.05, "obelisk", -48.0, 5.0, 30.0, {}),
        (0.06, "slab", 38.0, 8.0, 26.0, {"tilt": 0.04}),
        (0.08, "slab", -9.5, 3.4, 13.0, {}),
        (0.10, "obelisk", 9.0, 2.6, 15.0, {}),
        # Saeulenreihe im Lichtsee (Gegenlicht).
        (0.38, "pillar", -36.5, 1.15, 7.2, {}),
        (0.39, "pillar", -33.0, 1.05, 6.6, {"broken": True}),
        (0.40, "pillar", -30.2, 1.1, 7.0, {}),
        (0.41, "pillar", -23.6, 1.05, 6.8, {"broken": True}),
        (0.42, "pillar", -20.8, 1.1, 7.1, {}),
        (0.43, "pillar", -18.3, 1.0, 4.2, {"broken": True}),
        (0.20, "gate", 27.0, 7.5, 9.5, {}),
        (0.26, "obelisk", 33.5, 2.2, 13.0, {}),
        # Mitte, vor dem Schacht.
        (0.45, "lean", -40.5, 4.0, 15.0, {"ang": -6.0}),
        (0.50, "slab", 22.0, 3.2, 12.0, {"tilt": -0.05}),
        (0.55, "pillar", -26.2, 1.7, 3.6, {"broken": True}),
        # Das Tor in den Abgrund.
        (0.62, "slab", -15.5, 5.6, 27.0, {"taper": 0.07}),
        (0.66, "slab", 16.5, 6.4, 31.0, {"taper": 0.06, "tilt": 0.03}),
        # Nahe Rahmen-Massen (fast schwarz).
        (0.86, "slab", -58.0, 13.0, 44.0, {"taper": 0.08}),
        (0.90, "lean", 60.0, 14.0, 40.0, {"ang": 5.0}),
    ]
    # Rueckseite prozedural.
    kinds = ["slab", "slab", "obelisk", "pillar", "pillar", "gate", "lean"]
    for i in range(34):
        lon = rng.uniform(72, 288)
        lon = lon - 360 if lon > 180 else lon
        if abs(abs(lon) - 180) < 4:
            lon += 8 * np.sign(lon) * -1
        d = float(rng.choice([rng.uniform(0.02, 0.15), rng.uniform(0.15, 0.4), rng.uniform(0.4, 0.92)]))
        k = kinds[rng.integers(len(kinds))]
        if k == "pillar":
            w = rng.uniform(0.8, 1.8) * (1 + d)
            top = rng.uniform(4, 9) * (1 + d * 1.5)
            ex = {"broken": bool(rng.random() < 0.4)}
        elif k == "gate":
            w = rng.uniform(5, 9)
            top = rng.uniform(7, 12) * (1 + d)
            ex = {}
        elif k == "obelisk":
            w = rng.uniform(1.8, 4.5)
            top = rng.uniform(10, 28)
            ex = {}
        else:
            w = rng.uniform(3, 9) * (1 + d)
            top = rng.uniform(8, 30) * (0.7 + d)
            ex = {"tilt": float(rng.uniform(-0.05, 0.05))} if k == "slab" else {"ang": float(rng.uniform(-9, 9))}
        O.append((d, k, lon, w, top, ex))
    O.sort(key=lambda o: o[0])
    return O


def build_shape(rng, kind, lon, w, top, ex):
    if kind == "slab":
        return shape_slab(rng, lon, w, top, **ex)
    if kind == "obelisk":
        return shape_obelisk(rng, lon, w, top)
    if kind == "pillar":
        return shape_pillar(rng, lon, w, top, **ex)
    if kind == "gate":
        return shape_gate(rng, lon, w, top)
    return shape_lean(rng, lon, w, top, **ex)


def near_layer(W, seed):
    """Ebene `near` (Daten, verlustfrei, linear): R ferne Platten, G nahe riesige
    Platten (Oberflaechenhelligkeit, 0 = leer), B Kantenlicht zum Schacht.
    Der Shader schiebt R/G mit beat_step verschieden weit (Parallax-Einrasten)."""
    P = Pano(W)
    rng = np.random.default_rng(seed)
    H = P.H
    out = np.zeros((H, W, 3), F32)
    lat = P.LAT()
    lon = P.LON()
    ss = 3
    def slab(ch, c, w, top, taper, tilt, rough):
        half = w / 2.0
        x0, x1 = int(P.x(c - half - 4)), int(P.x(c + half + 4))
        cols = np.arange(x0, x1)
        lo = (cols / W - 0.5) * 360.0
        dl = lo - c
        n = len(cols)
        edge = fbm1(rng, 512, base=8, octaves=6)
        tn = np.interp((np.arange(n) / n) * 512, np.arange(512), edge)
        # hoehe pro Spalte: Kante rau, Taper
        tp = top + rough * tn * 2.0 - taper * np.abs(dl)
        lat_c = (0.5 - (np.arange(H) + 0.5) / H) * 180.0
        halfw = half - np.maximum(lat_c[:, None], 0.0) * tilt
        ins = (np.abs(dl)[None, :] < halfw).astype(F32)
        under = (lat_c[:, None] < tp[None, :]).astype(F32)
        under *= (lat_c[:, None] > -1.5)
        m = ins * under
        m = ndimage.gaussian_filter(m, 0.9)
        # Oberflaeche: Schichtung (Streifen in Breitenrichtung) + Verwitterung
        strat = fbm1(np.random.default_rng(int(c * 100) % 9999 + 7), H, base=40, octaves=5)[:, None]
        wea = ndimage.zoom(rng.standard_normal((H // 8, n // 8 + 1)).astype(F32), (8, 8), order=3)[:H, :n]
        # Seite zum Schacht heller
        toward = np.sign(P.lon[0] * 0 + (SHAFT_LON - c))
        side = np.clip(0.5 + 0.5 * toward * dl / max(half, 0.1), 0, 1)
        sh = 0.25 + 0.45 * side[None, :] + 0.18 * strat + 0.10 * wea
        sh *= np.clip(0.65 + 0.35 * (lat_c[:, None] + 1.5) / 14.0, 0, 1)
        v = np.clip(m * (0.06 + 0.94 * np.clip(sh, 0, 1)), 0, 1)
        out[:, x0:x0 + n, ch] = np.maximum(out[:, x0:x0 + n, ch], v)
        # Kantenlicht (nur Seite zum Schacht, zum Schacht staerker)
        near_sh = math.exp(-abs(wrap(SHAFT_LON - c)) / 60.0)
        e = np.clip(1.0 - np.abs(toward * (dl) - halfw) / 0.35, 0, 1) * (m > 0.5)
        out[:, x0:x0 + n, 2] = np.maximum(out[:, x0:x0 + n, 2], (e * near_sh * 0.9 * np.clip(0.4 + 0.6 * sh, 0, 1)).astype(F32))
    # ferne Platten (R): 38 Stueck, ueberall, niedrig-mittel
    lons = np.sort(rng.uniform(-163, 163, 38))
    for c in lons:
        if abs(c) < 14 and rng.random() < 0.5:
            continue
        slab(0, c, rng.uniform(2.0, 5.5), rng.uniform(4, 22), rng.uniform(0.0, 0.15), rng.uniform(-0.02, 0.05), rng.uniform(0.2, 0.8))
    # nahe riesige Platten (G): Seiten, nie vorn-mitte, nie im Schacht
    cands = [-150, -118, -86, -58, 46, 70, 98, 128, 158]
    for c in cands:
        c = c + rng.uniform(-8, 8)
        slab(1, c, rng.uniform(7, 14), rng.uniform(24, 46), rng.uniform(0.0, 0.2), rng.uniform(0.0, 0.08), rng.uniform(0.6, 1.6))
    return out


def paint_world(P, rng, beam, soft):
    objs = make_objects(rng)
    shaft_done = False
    for d, kind, lon, w, top, ex in objs:
        if not shaft_done and d > SHAFT_DEPTH:
            paint_shaft(P, beam, soft)
            shaft_done = True
        polys = build_shape(rng, kind, lon, w, top, ex)
        fog_h = 6.5 - 4.0 * d
        paint_object(P, rng, polys, lon, d, fog_h)
    if not shaft_done:
        paint_shaft(P, beam, soft)


# ---------------------------------------------------------------------------
def fog_layer(P, rng, beam, soft, fw):
    """Datenkanaele (siehe Kopf) in Aufloesung fw x fw/2."""
    fh = fw // 2
    v = (np.arange(fh) + 0.5) / fh
    u = (np.arange(fw) + 0.5) / fw
    lat = ((0.5 - v) * 180.0).astype(F32)[:, None]
    lon = ((u - 0.5) * 360.0).astype(F32)[None, :]

    # R: tiefe Baenke mit unruhiger Oberkante.
    topl = 1.6 + 2.8 * fbm1(rng, fw, base=7, octaves=7)[None, :]
    det = fbm2(rng, fh, fw, base=(20, 60), octaves=5)
    n = fbm2(rng, fh, fw, base=(6, 22), octaves=6)
    top = topl + 0.9 * det
    bank = smoothstep(top + 0.9, top - 1.6, lat) * smoothstep(-7.0, -1.0, lat)
    R = bank * np.clip(0.55 + 0.75 * n, 0.0, 1.0)
    R = np.clip(R * 0.95, 0, 1)

    # G: hohe Schlieren, stark in die Breite gezogen.
    s1 = fbm2(rng, fh, fw, base=(56, 10), octaves=5, gain=0.5)
    s2 = fbm2(rng, fh, fw, base=(10, 16), octaves=5)
    band = smoothstep(0.5, 3.5, lat) * smoothstep(16.0, 6.0, lat)
    G = band * smoothstep(0.05, 0.75, s1 + 0.4 * s2) * 0.75

    # B: sichtbares Schachtlicht (normiert, verdeckt durch nahe Objekte).
    vis = (beam + soft) * P.occ
    B = ndimage.zoom(vis, (fh / P.H, fw / P.W), order=1) / SHAFT_PEAK
    B = np.clip(B, 0, 1)
    return np.stack([R, G, B], -1).astype(F32)


def tonemap(x):
    k = 0.72
    over = np.maximum(x - k, 0.0)
    return np.where(x < k, x, k + (1 - k) * (1 - np.exp(-over / (1 - k))))


def to_u8(lin, rng):
    s = lin_to_srgb(lin)
    s = s * 255.0 + rng.triangular(-0.5, 0, 0.5, s.shape)
    return np.clip(np.rint(s), 0, 255).astype(np.uint8)


# Nebel wie im Shader (ohne Animation) - fuer --preview.
FOG_COLOR = hexcol("#7d8ca0")
FOG_LIT = hexcol("#bccadb")


def fog_shade(lat, lon, fog):
    up = np.maximum(lat, 0.0)
    amb = 0.045 + 0.110 * np.exp(-np.abs(lat) / 2.5)
    db = np.abs(wrap(lon - SHAFT_LON))
    lit = (0.30 * np.exp(-(db / 4.0) ** 2) + 0.085 * np.exp(-db / 12.0)) * np.exp(-up / 5.0)
    fc = amb[..., None] * FOG_COLOR + lit[..., None] * FOG_LIT
    a = np.clip(fog[..., 0] * 0.85, 0, 1)
    g = np.clip(fog[..., 1] * 0.45, 0, 1)
    return fc, a, g


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
    d = np.stack([x3, y2, z3], -1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    u = (np.arctan2(d[..., 0], -d[..., 2]) / (2 * math.pi) + 0.5) * W
    v = (0.5 - np.arcsin(np.clip(d[..., 1], -1, 1)) / math.pi) * H
    out = np.zeros((vh, vw, pano.shape[2]))
    for ch in range(pano.shape[2]):
        out[..., ch] = ndimage.map_coordinates(pano[..., ch], [v - 0.5, u - 0.5], order=1, mode="grid-wrap")
    return out


def build(W, seed, out_dir, preview, quality, fog_w):
    t0 = time.time()
    P = Pano(W)
    rng = np.random.default_rng(seed)
    paint_sky(P, np.random.default_rng(seed + 1))
    paint_stars(P, np.random.default_rng(seed + 2))
    beam, soft = shaft_light(P, np.random.default_rng(seed + 3))
    paint_ground(P, np.random.default_rng(seed + 4))
    paint_world(P, np.random.default_rng(seed + 5), beam, soft)
    fog = fog_layer(P, np.random.default_rng(seed + 6), beam, soft, fog_w or W // 2)
    lin = tonemap(np.clip(P.img, 0, None))
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "abyss_sky.webp")
    Image.fromarray(to_u8(np.sqrt(lin), rng)).save(path, "WEBP", quality=quality, method=6)
    fpath = os.path.join(out_dir, "abyss_sky_fog.webp")
    fu8 = np.clip(np.rint(np.sqrt(fog) * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(fu8).save(fpath, "WEBP", lossless=True, quality=100, method=6)
    nl = near_layer(W, seed + 9)
    npath = os.path.join(out_dir, "abyss_sky_near.webp")
    Image.fromarray(np.clip(np.rint(nl * 255.0), 0, 255).astype(np.uint8)).save(npath, "WEBP", lossless=True, quality=100, method=4)
    print("near layer %.2f MB" % (os.path.getsize(npath) / 1e6))
    mb = os.path.getsize(path) / 1e6
    fmb = os.path.getsize(fpath) / 1e6
    print("abyss_sky: %dx%d %.2f MB, fog %dx%d %.2f MB, %.1f s" % (
        W, W // 2, mb, fog.shape[1], fog.shape[0], fmb, time.time() - t0))
    if preview:
        os.makedirs(preview, exist_ok=True)
        dec = srgb_to_lin(np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255.0) ** 2
        fdec = (np.asarray(Image.open(fpath).convert("RGB"), dtype=np.float64) / 255.0) ** 2
        for name, yaw in (("cam_abyss.png", 0.0), ("cam_abyss_side.png", 70.0), ("cam_abyss_back.png", 180.0)):
            view = camera_view(dec, yaw=yaw)
            fv = camera_view(fdec, yaw=yaw)
            vh, vw = view.shape[:2]
            th = math.tan(math.radians(31))
            ys, xs = np.mgrid[0:vh, 0:vw].astype(np.float64)
            # lat/lon je Pixel (grob, fuer die Nebelfarbe)
            x = (2 * (xs + 0.5) / vw - 1) * th * vw / vh
            y = (1 - 2 * (ys + 0.5) / vh) * th
            p = math.radians(-16.0)
            y2 = y * math.cos(p) + math.sin(p)
            z2 = y * math.sin(p) - math.cos(p)
            yw = math.radians(yaw)
            x3 = x * math.cos(yw) + z2 * math.sin(yw)
            z3 = -x * math.sin(yw) + z2 * math.cos(yw)
            nrm = np.sqrt(x3 ** 2 + y2 ** 2 + z3 ** 2)
            la = np.degrees(np.arcsin(y2 / nrm))
            lo = np.degrees(np.arctan2(x3, -z3))
            fc, a, g = fog_shade(la, lo, fv)
            view = view * (1 - g[..., None]) + fc * g[..., None]
            view = view * (1 - a[..., None]) + fc * a[..., None]
            Image.fromarray(to_u8(np.clip(view, 0, 1), rng)).save(os.path.join(preview, name))
        small = Image.fromarray(to_u8(np.clip(lin, 0, 1), rng)).resize((2048, 1024), Image.LANCZOS)
        small.save(os.path.join(preview, "pano_abyss.png"))
        Image.fromarray(fu8).resize((1024, 512)).save(os.path.join(preview, "fog_abyss.png"))
    return mb, fmb


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--width", type=int, default=8192)
    ap.add_argument("--fog-width", type=int, default=0, help="Standard: width/2")
    ap.add_argument("--seed", type=int, default=6660)
    ap.add_argument("--quality", type=int, default=95)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    mb, fmb = build(a.width, a.seed, a.out, a.preview, a.quality, a.fog_width)
    if a.width >= 4096 and max(mb, fmb) >= 6.0:
        raise SystemExit("WebP zu gross (%.2f / %.2f MB >= 2.5 MB)" % (mb, fmb))


if __name__ == "__main__":
    main()
