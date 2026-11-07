#!/usr/bin/env python3
"""TETHRA Welt-Thema "Obsidian": schwarzes Oel unter fast schwarzem Himmel.

Erzeugt in assets_game/themes/obsidian/:
  obsidian_sky.webp    4096x2048 equirektangulares Panorama (Standard):
    - Himmel fast schwarz, kalter stahlblauer Dunst nur knapp ueber dem
      Horizont; vorn-mitte am dunkelsten (Lesbarkeit der Strecke).
    - Zwei verborgene kalte Lichtquellen tief am Horizont (links/rechts
      vorn) und eine schwache hinten - die einzigen Lichter der Welt.
    - Schwarze Tintenschwaden steigen aus dem Oel auf und verdecken den
      Dunst (Silhouetten mit feiner kalter Kante).
    - Riesige schwebende Tropfenformen aus schwarzem Oel (Raymarching einer
      SDF, glatte Vereinigung + Fluessigkeits-Wellung), spiegeln das echte
      Panorama mit Fresnel: schwarzer Koerper, Horizontlinie und Lichtkerne
      als stahlblaue Glanzlichter.
    - Unter dem Horizont: ferne, ruhige Oelflaeche (unscharfe Spiegelung des
      Himmels mit Fresnel, Glanzbahnen unter den Lichtern). Nah zeichnet
      shaders/theme_obsidian.gdshader die rollenden Wellen live darueber.
  obsidian_waves.webp  1024x1024 kachelbare Wellen-Ebene (verlustfrei):
    R/G = Steigung dh/dx, dh/dz (0.5 = flach, +-WAVE_SLOPE), B = Hoehe 0..1.
    Schwere, runde Duenung (trochoidale Kaemme, periodisch verwirbelt) plus
    aufquellende Tropfenkuppen. Der Shader legt sie in zwei Massstaeben auf
    die Oelflaeche (Parallax, Flug, Beat-Atmen).

Abbildung identisch zu shaders/sky_panorama.gdshader / theme_obsidian.gdshader:
  u = atan(d.x, -d.z) / 2pi + 0.5   (u=0.5 = vorn, -Z)
  v = 0.5 - asin(d.y) / pi          (v=0 = Zenit)
Kodierung Panorama: wurzel-kodiert (gespeichert sqrt(linear) als sRGB), der
Shader dekodiert mit pow(textur, 2.0) - mehr 8-Bit-Stufen im Schwarz.
Die Wellen-Ebene ist Daten (linear, kein sRGB).

Reproduzierbar per Seed:
  python tools/gen_theme_obsidian.py                       # 4096x2048
  python tools/gen_theme_obsidian.py --width 2048 --preview <ordner>
  python tools/gen_theme_obsidian.py --seed 7              # andere Schwaden/Tropfen
--preview schreibt eine Ansicht wie die Komfort-Kamera (fov 62, Neigung -16),
eine Seitenansicht und eine verkleinerte Gesamtansicht als PNG.
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
OUT_DIR = os.path.join(ROOT, "assets_game", "themes", "obsidian")

# Lichtquellen (Laenge, Breite in Grad; Staerke). Gleiche Werte im Shader
# (light_a / light_b / light_c), damit Wellen-Glanz und Himmel zusammenpassen.
LIGHTS = [(-42.0, 3.0, 1.0), (46.0, 4.2, 0.8), (172.0, 2.4, 0.45)]
WAVE_SLOPE = 1.0  # Steigungsbereich der Wellen-Ebene (+-), Shader: wave_slope


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def hexcol(h, k=1.0):
    h = h.lstrip("#")
    return srgb_to_lin([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]) * k


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def fbm2(rng, H, W, base=(3, 6), octaves=7, gain=0.55, wrap_y=False):
    """Periodisches fbm (wickelt in x um, optional auch in y), Mittel 0."""
    acc = np.zeros((H, W), F32)
    amp, norm = 1.0, 0.0
    mode = "grid-wrap"
    for o in range(octaves):
        h, w = base[0] << o, base[1] << o
        if h > H // 2 or w > W // 2:
            break
        g = rng.standard_normal((h, w)).astype(F32)
        up = ndimage.zoom(g, (H / h, W / w), order=3, mode=mode, grid_mode=True)
        acc += amp * up[:H, :W]
        norm += amp
        amp *= gain
    return acc / norm


STEEL = hexcol("#8fb0d0")      # kaltes Stahlblau (Glanz)
STEEL_HI = hexcol("#d8e6f5")   # Glanzkern
HAZE = hexcol("#3a4e66")       # Horizont-Dunst
INK = hexcol("#0b0e13")        # Tinte (fast schwarz, kalt)


class Pano:
    def __init__(self, W):
        self.W, self.H = W, W // 2
        self.ppd = W / 360.0
        v = (np.arange(self.H) + 0.5) / self.H
        u = (np.arange(self.W) + 0.5) / self.W
        self.lat = ((0.5 - v) * 180.0).astype(F32)
        self.lon = ((u - 0.5) * 360.0).astype(F32)
        self.img = np.zeros((self.H, self.W, 3), F32)

    def row(self, lat):
        return int(round((0.5 - lat / 180.0) * self.H))


def ang_dist(lon, lat, lon0, lat0):
    """Winkelabstand in Grad (gross-kreis) - fuer runde Lichtflecken."""
    a, b = np.radians(lat), math.radians(lat0)
    dl = np.radians(lon - lon0)
    c = np.sin(a) * math.sin(b) + np.cos(a) * math.cos(b) * np.cos(dl)
    return np.degrees(np.arccos(np.clip(c, -1.0, 1.0)))


def wrap_deg(x):
    return (x + 180.0) % 360.0 - 180.0


# ---------------------------------------------------------------------------
def paint_sky(P, rng):
    E = P.lat[:, None]
    L = P.lon[None, :]
    up = (E >= 0.0).astype(F32)
    Ep = np.maximum(E, 0.0)
    # Azimut-Gewicht des Dunstes: Lichtseiten heller, vorn-mitte dunkel.
    az = 0.10 + 0.12 * np.exp(-(wrap_deg(L - 180.0) / 50.0) ** 2)
    for lon0, _lat0, k in LIGHTS:
        az = az + k * np.exp(-(wrap_deg(L - lon0) / 34.0) ** 2)
    az = az * (1.0 - 0.75 * np.exp(-(L / 22.0) ** 2))
    # Grundhimmel: fast schwarz, minimal kalt.
    base = 0.00055 + 0.0009 * np.exp(-Ep / 30.0)
    haze = np.exp(-Ep / 3.0) * 0.016 + np.exp(-Ep / 12.0) * 0.010 + np.exp(-Ep / 30.0) * 0.002
    sky = (base[..., None] * hexcol("#1c2632") / hexcol("#1c2632").max()
           + (haze * az)[..., None] * HAZE)
    P.img += (sky * up[..., None]).astype(F32)

    # Lichtquellen: weiter Schein, mittlerer Hof, harter Kern (hinter Tinte).
    glow = np.zeros_like(E * L, dtype=F32)
    core = np.zeros_like(glow)
    for lon0, lat0, k in LIGHTS:
        dl = wrap_deg(L - lon0)
        dE = E - lat0
        # horizontal gestreckter Schein (Dunstschicht)
        glow += k * (0.050 * np.exp(-(dl / 16.0) ** 2 - (dE / 3.2) ** 2)
                     + 0.016 * np.exp(-(dl / 42.0) ** 2 - (dE / 7.0) ** 2))
        d = ang_dist(L, E, lon0, lat0)
        core += k * (0.55 * np.exp(-(d / 0.32) ** 2) + 0.10 * np.exp(-(d / 1.3) ** 2))
    glow *= up
    core *= up
    # Duenne kalte Horizontlinie (Weltkante), vorn ausgeblendet.
    line = np.exp(-(E / 0.22) ** 2) * 0.030 * az * up

    # Tintenschwaden: steigen vom Horizont, zweifach verwirbelt (Tinte in Wasser).
    H, W = P.H, P.W
    sc = W / 4096.0
    yy, xx = np.mgrid[0:H, 0:W].astype(F32)
    w1x = fbm2(rng, H, W, base=(3, 9), octaves=5)
    w1y = fbm2(rng, H, W, base=(3, 9), octaves=5)
    w2x = fbm2(rng, H, W, base=(8, 28), octaves=4)
    w2y = fbm2(rng, H, W, base=(8, 28), octaves=4)
    n = fbm2(rng, H, W, base=(2, 11), octaves=6, gain=0.5)
    cy = yy + (w1y * 90.0 + w2y * 26.0) * sc
    cx = xx + (w1x * 200.0 + w2x * 40.0) * sc
    n = ndimage.map_coordinates(n, [cy, cx], order=1, mode="grid-wrap")
    # Schwaden-Hoehe je Laenge verschieden (4..22 Grad).
    top = 4.0 + 18.0 * smoothstep(-0.45, 0.45, fbm2(rng, 8, W, base=(1, 9), octaves=4)[4])[None, :]
    rise = np.exp(-Ep / top) * up  # nur ueber dem Horizont
    col_mask = smoothstep(-0.05, 0.35, fbm2(rng, H, W, base=(1, 7), octaves=3))
    dens = smoothstep(-0.10, 0.30, n + 0.25 * col_mask - 0.08)
    dens = dens * np.clip(rise * 1.3, 0.0, 1.0) * (0.40 + 0.60 * col_mask)
    dens = ndimage.gaussian_filter(dens.astype(F32), 1.0 * sc)
    # Kalte Kante nur an der Oberseite der Schwaden (Licht von hinten unten).
    gy = np.gradient(ndimage.gaussian_filter(dens, 2.0 * sc), axis=0)
    edge = np.clip(gy * 14.0 / sc, 0.0, 1.0) * up
    behind = glow[..., None] * STEEL + core[..., None] * STEEL_HI + line[..., None] * STEEL
    occl = 1.0 - 0.92 * dens
    P.img *= (1.0 - 0.80 * dens)[..., None]
    P.img += behind * occl[..., None]
    P.img += (edge * (glow * 0.35 + 0.0025 * az))[..., None] * STEEL
    P.img += (dens * 0.0006)[..., None] * INK / INK.max()


def paint_far_sea(P):
    """Ferne Oelflaeche: unscharfe Fresnel-Spiegelung des Himmels."""
    H = P.H
    h0 = P.row(0.0)
    sky = P.img[:h0].copy()
    mirror = sky[::-1]  # Zeile 0 = knapp ueber dem Horizont
    rows = H - h0
    mirror = np.concatenate([mirror, np.repeat(mirror[-1:], rows - mirror.shape[0], 0)], 0)[:rows]
    blurred = ndimage.gaussian_filter(mirror, (5.0, 9.0, 0.0), mode=("nearest", "wrap", "nearest"))
    depth = -P.lat[h0:]
    s = np.sin(np.radians(np.maximum(depth, 0.0)))
    F = 0.04 + 0.96 * (1.0 - s) ** 5
    sea = blurred * F[:, None, None].astype(F32) * 0.85
    # Glanzbahnen unter den Lichtern (vertikal gestreckt, werden nach unten breit).
    L = P.lon[None, :]
    D = depth[:, None]
    for lon0, _lat0, k in LIGHTS:
        dl = wrap_deg(L - lon0)
        wdt = 2.2 + D * 0.9
        path = k * 0.05 * np.exp(-(dl / wdt) ** 2) * np.exp(-D / 2.2)
        sea += (path[..., None] * STEEL).astype(F32)
    P.img[h0:] = sea


# ---------------------------------------------------------------------------
def sample_pano(img, d):
    """Panorama an Richtungen d (N,3) bilinear (equirektangulaer)."""
    H, W = img.shape[:2]
    u = (np.arctan2(d[:, 0], -d[:, 2]) / (2 * math.pi) + 0.5) * W
    v = (0.5 - np.arcsin(np.clip(d[:, 1], -1, 1)) / math.pi) * H
    out = np.empty((len(d), 3), F32)
    for ch in range(3):
        out[:, ch] = ndimage.map_coordinates(img[..., ch], [v - 0.5, u - 0.5], order=1, mode="grid-wrap")
    return out


def dir_of(lon, lat):
    lo, la = math.radians(lon), math.radians(lat)
    return np.array([math.sin(lo) * math.cos(la), math.sin(la), -math.cos(lo) * math.cos(la)])


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


class Drop:
    """Tropfenform: glatte Vereinigung von Kugeln (lokal, Einheit = Radius)."""

    def __init__(self, lon, lat, ang, parts, wob, seed, dist=100.0):
        self.lon, self.lat, self.ang = lon, lat, ang
        self.c = dir_of(lon, lat) * dist
        self.R = dist * math.sin(math.radians(ang))
        self.parts = parts  # [(offset xyz in R, radius in R, k)]
        self.wob = wob
        r = np.random.default_rng(seed)
        self.ph = r.uniform(0, 6.28, 6)
        ext = max(np.linalg.norm(np.array(o)) + rr for o, rr, _ in parts)
        self.ext = ext * 1.15 + wob

    def sdf(self, p):
        q = (p - self.c) / self.R
        d = None
        for off, rr, k in self.parts:
            di = np.linalg.norm(q - np.array(off), axis=-1) - rr
            d = di if d is None else smin(d, di, k)
        ph = self.ph
        w = (np.sin(q[:, 0] * 3.1 + ph[0]) * np.sin(q[:, 1] * 2.7 + ph[1]) * np.sin(q[:, 2] * 3.3 + ph[2])
             + 0.5 * np.sin(q[:, 0] * 6.3 + ph[3]) * np.sin(q[:, 1] * 5.9 + ph[4]) * np.sin(q[:, 2] * 6.7 + ph[5]))
        return (d + self.wob * w) * self.R


def render_drop(P, env, dr, ss=2):
    """Raymarching einer Tropfenform in ihrem Bildausschnitt, ss-fach ueberabgetastet."""
    ang = math.degrees(math.asin(min(dr.ext * dr.R / np.linalg.norm(dr.c), 0.99)))
    lat0, lat1 = dr.lat - ang * 1.05, dr.lat + ang * 1.05
    cl = max(math.cos(math.radians(min(abs(lat0), abs(lat1), 80.0) if lat0 * lat1 > 0 else 0.0)), 0.2)
    dlon = ang * 1.05 / cl
    r0, r1 = max(P.row(lat1), 0), min(P.row(lat0) + 1, P.H)
    c0 = int(math.floor(((dr.lon - dlon) / 360.0 + 0.5) * P.W))
    c1 = int(math.ceil(((dr.lon + dlon) / 360.0 + 0.5) * P.W))
    hh, ww = r1 - r0, c1 - c0
    ys = r0 + (np.arange(hh * ss) + 0.5) / ss
    xs = c0 + (np.arange(ww * ss) + 0.5) / ss
    lat = np.radians((0.5 - ys / P.H) * 180.0)[:, None]
    lon = np.radians((xs / P.W - 0.5) * 360.0)[None, :]
    d = np.stack(np.broadcast_arrays(np.sin(lon) * np.cos(lat), np.sin(lat) + 0 * lon,
                                     -np.cos(lon) * np.cos(lat)), -1).reshape(-1, 3)
    cn = np.linalg.norm(dr.c)
    t = np.full(len(d), cn - dr.ext * dr.R)
    alive = np.ones(len(d), bool)
    hit = np.zeros(len(d), bool)
    tmax = cn + dr.ext * dr.R
    for _ in range(96):
        idx = np.nonzero(alive)[0]
        if len(idx) == 0:
            break
        p = d[idx] * t[idx, None]
        s = dr.sdf(p)
        t[idx] += s * 0.75
        h = s < 0.0006 * dr.R
        hit[idx[h]] = True
        alive[idx[h]] = False
        alive[idx[t[idx] > tmax]] = False
    col = np.zeros((len(d), 3), F32)
    hi = np.nonzero(hit)[0]
    if len(hi):
        p = d[hi] * t[hi, None]
        e = 0.0025 * dr.R
        n = np.stack([dr.sdf(p + [e, 0, 0]) - dr.sdf(p - [e, 0, 0]),
                      dr.sdf(p + [0, e, 0]) - dr.sdf(p - [0, e, 0]),
                      dr.sdf(p + [0, 0, e]) - dr.sdf(p - [0, 0, e])], -1)
        n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9
        v = d[hi]
        cosv = np.clip(-(n * v).sum(-1), 0.0, 1.0)
        r = v - 2.0 * (n * v).sum(-1, keepdims=True) * n
        F = 0.045 + 0.955 * (1.0 - cosv) ** 5
        refl = sample_pano(env, r)
        # Kerne der Lichter extra hart (Glanzpunkt), das Panorama hat sie schon weich.
        spec = np.zeros(len(hi))
        for lon0, lat0, k in LIGHTS:
            Ld = dir_of(lon0, lat0)
            spec += k * np.maximum((r * Ld).sum(-1), 0.0) ** 900 * 2.2
        col[hi] = refl * F[:, None] * 2.4 + (spec * F * 4.0)[:, None] * STEEL_HI + 0.0004 * STEEL
    a = hit.astype(F32).reshape(hh * ss, ww * ss)
    col = col.reshape(hh * ss, ww * ss, 3)
    a = a.reshape(hh, ss, ww, ss).mean((1, 3))
    col = col.reshape(hh, ss, ww, ss, 3).mean((1, 3))
    cols = np.arange(c0, c1) % P.W
    region = P.img[r0:r1][:, cols]
    P.img[r0:r1, cols] = region * (1.0 - a[..., None]) + col


def paint_drops(P, rng):
    env = P.img.copy()
    drops = [
        # Laenge, Breite, Winkelradius, Teile, Wellung
        Drop(-35.0, 9.0, 4.2, [((0, 0, 0), 1.0, 0.4), ((0.15, -1.25, 0.1), 0.42, 0.55),
                              ((0.2, -2.05, 0.1), 0.16, 0.35)], 0.025, rng.integers(1 << 30)),
        Drop(-27.5, 4.4, 0.9, [((0, 0, 0), 1.0, 0.3)], 0.02, rng.integers(1 << 30)),
        Drop(37.5, 9.0, 2.6, [((0, 0, 0), 1.0, 0.4), ((-0.9, 0.55, 0.2), 0.55, 0.6)], 0.03,
             rng.integers(1 << 30)),
        Drop(43.0, 6.4, 0.55, [((0, 0, 0), 1.0, 0.3)], 0.0, rng.integers(1 << 30)),
        Drop(105.0, 20.0, 9.0, [((0, 0, 0), 1.0, 0.5), ((0.1, -1.3, 0.0), 0.5, 0.7),
                                ((0.15, -2.2, 0.0), 0.22, 0.4), ((0.8, 0.7, 0.3), 0.45, 0.6)],
             0.03, rng.integers(1 << 30)),
        Drop(178.0, 27.0, 13.0, [((0, 0, 0), 1.0, 0.5), ((-1.1, -0.35, 0.2), 0.62, 0.7),
                                 ((1.0, 0.45, -0.3), 0.4, 0.6)], 0.025, rng.integers(1 << 30)),
        Drop(-112.0, 16.0, 7.0, [((0, 0, 0), 1.0, 0.5), ((0.0, 1.35, 0.0), 0.38, 0.6)], 0.035,
             rng.integers(1 << 30)),
        Drop(-138.0, 33.0, 2.2, [((0, 0, 0), 1.0, 0.3)], 0.02, rng.integers(1 << 30)),
        Drop(132.0, 8.5, 1.6, [((0, 0, 0), 1.0, 0.3)], 0.02, rng.integers(1 << 30)),
        Drop(-80.0, 41.0, 3.4, [((0, 0, 0), 1.0, 0.4), ((0.4, -1.1, 0), 0.3, 0.45)], 0.03,
             rng.integers(1 << 30)),
    ]
    for dr in drops:
        render_drop(P, env, dr)


# ---------------------------------------------------------------------------
def make_waves(N, rng):
    """Kachelbare Hoehe der Oel-Duenung (periodisch in beiden Richtungen)."""
    y, x = np.mgrid[0:N, 0:N].astype(np.float64) / N
    wx = fbm2(rng, N, N, base=(2, 2), octaves=4, wrap_y=True).astype(np.float64)
    wz = fbm2(rng, N, N, base=(2, 2), octaves=4, wrap_y=True).astype(np.float64)
    xw = x + 0.06 * wx
    yw = y + 0.06 * wz
    h = np.zeros((N, N))
    # (kx, kz) ganzzahlig -> kachelbar; Amplitude, Schaerfe der Kaemme.
    waves = [((0, 2), 1.00, 2.4), ((1, 3), 0.55, 2.0), ((-2, 3), 0.42, 1.8),
             ((3, 1), 0.22, 1.5), ((-1, 5), 0.20, 1.6), ((4, -3), 0.10, 1.3),
             ((2, 7), 0.08, 1.3), ((-6, 5), 0.05, 1.2)]
    for (kx, kz), a, sharp in waves:
        ph = 2 * math.pi * (kx * xw + kz * yw) + rng.uniform(0, 2 * math.pi)
        c = 0.5 + 0.5 * np.cos(ph)
        h += a * (c ** sharp - 1.0 / (1.0 + sharp))
    # Aufquellende Tropfenkuppen (glatt, periodisch gekachelt).
    n = 26
    px, pz = rng.random(n), rng.random(n)
    rad = rng.uniform(0.025, 0.07, n)
    amp = rng.uniform(0.25, 0.6, n)
    for i in range(n):
        dx = (x - px[i] + 0.5) % 1.0 - 0.5
        dz = (y - pz[i] + 0.5) % 1.0 - 0.5
        h += amp[i] * np.exp(-(dx * dx + dz * dz) / (rad[i] ** 2))
    h += 0.06 * fbm2(rng, N, N, base=(4, 4), octaves=4, wrap_y=True)
    return h


def save_waves(N, rng, out_dir, tile_world=48.0):
    h = make_waves(N, rng)
    h = (h - h.mean()) / (h.max() - h.min())
    # Hoehe in Welteinheiten bei Kachel = tile_world (Shader: Massstab passt
    # die Steigung an); Steigung zentral differenziert, periodisch.
    amp_world = 3.2
    hw = h * amp_world
    dx = (np.roll(hw, -1, 1) - np.roll(hw, 1, 1)) * N / (2 * tile_world)
    dz = (np.roll(hw, -1, 0) - np.roll(hw, 1, 0)) * N / (2 * tile_world)
    print("waves: slope max %.2f / %.2f" % (np.abs(dx).max(), np.abs(dz).max()))
    sx = np.clip(dx / WAVE_SLOPE * 0.5 + 0.5, 0, 1)
    sz = np.clip(dz / WAVE_SLOPE * 0.5 + 0.5, 0, 1)
    hb = (h - h.min()) / (h.max() - h.min())
    img = np.stack([sx, sz, hb], -1)
    u8 = np.clip(np.rint(img * 255.0 + rng.triangular(-0.5, 0, 0.5, img.shape)), 0, 255).astype(np.uint8)
    path = os.path.join(out_dir, "obsidian_waves.webp")
    Image.fromarray(u8).save(path, "WEBP", lossless=True, quality=100, method=6)
    print("obsidian_waves: %dx%d  %.2f MB" % (N, N, os.path.getsize(path) / 1e6))
    return os.path.getsize(path) / 1e6


# ---------------------------------------------------------------------------
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
    d = np.stack([x3, y2, z3], -1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    u = (np.arctan2(d[..., 0], -d[..., 2]) / (2 * math.pi) + 0.5) * W
    v = (0.5 - np.arcsin(np.clip(d[..., 1], -1, 1)) / math.pi) * H
    out = np.zeros((vh, vw, 3))
    for ch in range(3):
        out[..., ch] = ndimage.map_coordinates(pano[..., ch], [v - 0.5, u - 0.5], order=1, mode="grid-wrap")
    return out


def build(W, seed, out_dir, preview, quality, wave_n):
    t0 = time.time()
    P = Pano(W)
    rng = np.random.default_rng(seed)
    paint_sky(P, np.random.default_rng(seed + 1))
    paint_far_sea(P)
    paint_drops(P, np.random.default_rng(seed + 2))
    lin = tonemap(np.clip(P.img, 0, None))
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "obsidian_sky.webp")
    Image.fromarray(to_u8(np.sqrt(lin), rng)).save(path, "WEBP", quality=quality, method=6)
    mb = os.path.getsize(path) / 1e6
    print("obsidian_sky: %dx%d  %.1f s  %.2f MB  -> %s" % (W, W // 2, time.time() - t0, mb, path))
    wmb = save_waves(wave_n, np.random.default_rng(seed + 3), out_dir)
    if preview:
        os.makedirs(preview, exist_ok=True)
        dec = srgb_to_lin(np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255.0) ** 2
        for name, yaw, pitch in (("cam_obsidian.png", 0.0, -16.0), ("cam_obsidian_side.png", 70.0, -8.0),
                                 ("cam_obsidian_back.png", 175.0, 6.0)):
            view = camera_view(dec, yaw=yaw, pitch=pitch)
            Image.fromarray(to_u8(np.clip(view * 2.0, 0, 1), rng)).save(os.path.join(preview, name))
        small = Image.fromarray(to_u8(np.clip(lin * 2.0, 0, 1), rng)).resize((2048, 1024), Image.LANCZOS)
        small.save(os.path.join(preview, "pano_obsidian.png"))
    return mb, wmb


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--width", type=int, default=4096)
    ap.add_argument("--waves", type=int, default=1024)
    ap.add_argument("--seed", type=int, default=6623)
    ap.add_argument("--quality", type=int, default=95)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    mb, wmb = build(a.width, a.seed, a.out, a.preview, a.quality, a.waves)
    if a.width >= 4096 and (mb >= 2.5 or wmb >= 2.5):
        raise SystemExit("WebP zu gross (%.2f / %.2f MB >= 2.5 MB)" % (mb, wmb))


if __name__ == "__main__":
    main()
