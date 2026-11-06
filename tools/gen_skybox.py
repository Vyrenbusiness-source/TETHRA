#!/usr/bin/env python3
"""TETHRA Skybox-Generator: equirektangulare Weltraum-Panoramen (offline).

Erzeugt pro Palette zwei Texturen in assets_game/space/:
  sky_<name>.webp        Nebel-Ebene: mehrschichtige domain-warped fbm-Nebel
                         (ferner Dunst + nahe Gaswolken + Filamente), dunkle
                         Staubbahnen mit Roetung, Emissions-Knoten, unaufgeloester
                         Sternenstaub im Galaxie-Band, ferne Galaxien.
  sky_<name>_stars.webp  Sternen-Ebene ohne Nebel (fuer Parallax): Sterne mit
                         Farbtemperatur (blau-weiss bis orange), Groessenklassen
                         nach Potenzgesetz, Sternhaufen, weiche Bloom-Halos.

Alles wird auf der Kugel (3D-Rauschen ueber Blickrichtungen) berechnet: keine
Naht bei u=0/1, keine Pol-Verzerrung. Abbildung (identisch zu
shaders/sky_panorama.gdshader):
  u = atan(d.x, -d.z) / 2pi + 0.5      (u=0.5 = Blick nach vorn, -Z)
  v = 0.5 - asin(d.y) / pi             (v=0 = Zenit)
Bildmitte vorn/unten bleibt dunkel (Noten-Lesbarkeit), Akzente oben/seitlich.

Reproduzierbar per Seed:
  python tools/gen_skybox.py                     # alle 4 Paletten, 4096x2048
  python tools/gen_skybox.py --only violet --width 1024 --preview <ordner>
  python tools/gen_skybox.py --seed 7            # andere Variante
--preview schreibt zusaetzlich eine Kamera-Ansicht wie im Spiel (Mania-Kamera,
fov 72, Neigung -15.2 Grad) als PNG zum schnellen Ansehen.
"""
import argparse
import math
import os
import sys
import time
from multiprocessing import Pool

import numpy as np
from PIL import Image
from scipy import ndimage

F32 = np.float32
PXR = math.pi / 2048  # Referenz-Texel (bei 4096x2048) fuer Groessen in rad
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets_game", "space")


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def hexcol(h):
    h = h.lstrip("#")
    return srgb_to_lin([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


# ---------------------------------------------------------------------------
# Paletten (Farben als sRGB-Hex, intern linear). ramp_a: Hauptgas von dunkel
# nach heiss, ramp_b: zweiter Farbton (Harmonie), knot: Emissions-Knoten,
# dust: Roetungs-Absorption pro Kanal, haze: ferner Dunst.
# ---------------------------------------------------------------------------
PALETTES = {
    "violet": dict(
        ramp_a=["#000000", "#12061f", "#3a0f4d", "#8a2a78", "#e07ab0", "#ffe0ee"],
        ramp_b=["#000000", "#060b24", "#142a66", "#2f5fb0", "#8fb8f0", "#eef4ff"],
        knot="#ff6a8e", haze="#1a0b2e", base="#020107", cluster="#9fc0ff",
        dust=(1.25, 1.0, 0.8), hue_amt=0.55, band=((-75, -22), (35, 34)),
        hero=(-36, 5, 27), second=(48, 2, 18), seed=11),
    "azure": dict(
        ramp_a=["#000000", "#03101f", "#08304d", "#11707e", "#5fd0cc", "#e4fffb"],
        ramp_b=["#000000", "#07081f", "#1a1a5c", "#3b3fa8", "#9a9cf0", "#f2f0ff"],
        knot="#ff9a5a", haze="#06142a", base="#010309", cluster="#bfe4ff",
        dust=(1.2, 1.0, 0.85), hue_amt=0.45, band=((70, -20), (-40, 32)),
        hero=(36, 5, 28), second=(-48, 2, 17), seed=23),
    "ember": dict(
        ramp_a=["#000000", "#1a0504", "#4d1008", "#a3360e", "#f09a3a", "#fff0c8"],
        ramp_b=["#000000", "#1a0410", "#4a0b2a", "#9c1f45", "#f0708a", "#ffe6ea"],
        knot="#ffd27a", haze="#1c0806", base="#050102", cluster="#a8c8ff",
        dust=(1.1, 1.0, 0.9), hue_amt=0.5, band=((-70, -24), (40, 30)),
        hero=(-36, 5, 26), second=(48, 2, 19), seed=37),
    "emerald": dict(
        ramp_a=["#000000", "#02140c", "#063a24", "#127a52", "#5fe0a6", "#e6fff2"],
        ramp_b=["#000000", "#031220", "#0a3150", "#16708c", "#6cc8e0", "#e8faff"],
        knot="#e07ad8", haze="#04160f", base="#010503", cluster="#d8f0ff",
        dust=(1.2, 1.0, 0.85), hue_amt=0.5, band=((72, -18), (-36, 33)),
        hero=(36, 5, 27), second=(-48, 2, 18), seed=53),
}


# ---------------------------------------------------------------------------
# 3D-Gradientenrauschen (Perlin) + fbm/ridged, vektorisiert (float32).
# ---------------------------------------------------------------------------
class Noise3:
    def __init__(self, seed):
        rng = np.random.default_rng(seed)
        p = rng.permutation(256).astype(np.int32)
        self.perm = np.concatenate([p, p, p]).astype(np.int32)
        g = rng.normal(size=(256, 3))
        g /= np.linalg.norm(g, axis=1, keepdims=True)
        self.gx, self.gy, self.gz = (g[:, i].astype(F32) for i in range(3))
        # Zufaellige Rotation + Versatz je Oktave gegen Gitter-Artefakte.
        self.rots = []
        for _ in range(12):
            q, _r = np.linalg.qr(rng.normal(size=(3, 3)))
            self.rots.append((q.astype(F32), rng.uniform(-50, 50, 3).astype(F32)))

    def noise(self, x, y, z):
        xi = np.floor(x)
        yi = np.floor(y)
        zi = np.floor(z)
        xf = (x - xi).astype(F32)
        yf = (y - yi).astype(F32)
        zf = (z - zi).astype(F32)
        xi = xi.astype(np.int32) & 255
        yi = yi.astype(np.int32) & 255
        zi = zi.astype(np.int32) & 255
        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
        w = zf * zf * zf * (zf * (zf * 6 - 15) + 10)
        P = self.perm
        a = P[xi] + yi
        b = P[xi + 1] + yi
        aa, ab = P[a] + zi, P[a + 1] + zi
        ba, bb = P[b] + zi, P[b + 1] + zi

        def g(h, dx, dy, dz):
            h = P[h]
            return self.gx[h] * dx + self.gy[h] * dy + self.gz[h] * dz

        x1 = xf - 1
        y1 = yf - 1
        z1 = zf - 1
        n000 = g(aa, xf, yf, zf)
        n100 = g(ba, x1, yf, zf)
        n010 = g(ab, xf, y1, zf)
        n110 = g(bb, x1, y1, zf)
        n001 = g(aa + 1, xf, yf, z1)
        n101 = g(ba + 1, x1, yf, z1)
        n011 = g(ab + 1, xf, y1, z1)
        n111 = g(bb + 1, x1, y1, z1)
        x00 = n000 + u * (n100 - n000)
        x10 = n010 + u * (n110 - n010)
        x01 = n001 + u * (n101 - n001)
        x11 = n011 + u * (n111 - n011)
        y0 = x00 + v * (x10 - x00)
        y1_ = x01 + v * (x11 - x01)
        return (y0 + w * (y1_ - y0)) * F32(1.6)

    def _oct(self, p, i, f):
        r, o = self.rots[i % len(self.rots)]
        x = (p[0] * r[0, 0] + p[1] * r[0, 1] + p[2] * r[0, 2]) * f + o[0]
        y = (p[0] * r[1, 0] + p[1] * r[1, 1] + p[2] * r[1, 2]) * f + o[1]
        z = (p[0] * r[2, 0] + p[1] * r[2, 1] + p[2] * r[2, 2]) * f + o[2]
        return self.noise(x, y, z)

    def fbm(self, p, freq, octaves, gain=0.5, lac=2.03):
        s = np.zeros_like(p[0])
        amp = 1.0
        norm = 0.0
        f = freq
        for i in range(octaves):
            s += F32(amp) * self._oct(p, i, f)
            norm += amp
            amp *= gain
            f *= lac
        return s / F32(norm)

    def ridged(self, p, freq, octaves, gain=0.55, lac=2.05):
        """Filament-Rauschen: scharfe Grate, jede Oktave vom Vorgaenger gewichtet."""
        s = np.zeros_like(p[0])
        amp = 1.0
        norm = 0.0
        f = freq
        prev = np.ones_like(p[0])
        for i in range(octaves):
            n = F32(1.0) - np.abs(self._oct(p, i + 5, f))
            n = n * n
            s += F32(amp) * n * prev
            prev = np.clip(n * 1.6, 0, 1)
            norm += amp
            amp *= gain
            f *= lac
        return s / F32(norm)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def ramp(stops, t):
    """Mehrstufiger Farbverlauf (linear), t 0..1 -> (N,3)."""
    stops = np.asarray(stops, dtype=F32)
    n = len(stops) - 1
    x = np.clip(t, 0, 1) * n
    i = np.minimum(x.astype(np.int32), n - 1)
    f = (x - i)[..., None]
    f = f * f * (3 - 2 * f)
    return stops[i] * (1 - f) + stops[i + 1] * f


def lonlat_dir(lon_deg, lat_deg):
    lo, la = math.radians(lon_deg), math.radians(lat_deg)
    return np.array([math.cos(la) * math.sin(lo), math.sin(la), -math.cos(la) * math.cos(lo)])


def grid_dirs(W, H, r0, r1):
    lon = ((np.arange(W, dtype=F32) + 0.5) / W - 0.5) * F32(2 * math.pi)
    lat = (0.5 - (np.arange(r0, r1, dtype=F32) + 0.5) / H) * F32(math.pi)
    lon, lat = np.meshgrid(lon, lat)
    cl = np.cos(lat)
    return np.stack([cl * np.sin(lon), np.sin(lat), -cl * np.cos(lon)]), lon, lat


class Comp:
    """Grosse Komposition einer Palette: Galaxie-Band, Wolkenmassen, Knoten."""

    def __init__(self, pal, rng):
        p1 = lonlat_dir(*pal["band"][0])
        p2 = lonlat_dir(*pal["band"][1])
        n = np.cross(p1, p2)
        self.band_n = n / np.linalg.norm(n)
        hl, hb, hr = pal["hero"]
        sl, sb, sr = pal["second"]
        # (Richtung, Radius rad, Staerke)
        self.clouds = [(lonlat_dir(hl, hb), math.radians(hr), 1.25),
                       (lonlat_dir(sl, sb), math.radians(sr), 0.7)]
        for _ in range(7):
            lon = rng.uniform(70, 290)  # hinten/seitlich, ausserhalb des Blicks
            lat = rng.uniform(-50, 55)
            self.clouds.append((lonlat_dir(lon, lat), math.radians(rng.uniform(14, 34)),
                                rng.uniform(0.45, 0.9)))
        # Emissions-Knoten: im Helden-Nebel, im Zweit-Nebel und im Band.
        self.knots = []
        for c, r, s in self.clouds[:2]:
            for _ in range(3 if s >= 1.0 else 2):
                d = c + rng.normal(size=3) * r * 0.45
                self.knots.append((d / np.linalg.norm(d), math.radians(rng.uniform(1.2, 3.6)),
                                   rng.uniform(0.6, 1.0) * s))
        for _ in range(8):
            d = self.band_point(rng)
            if d[2] < -0.35 and abs(d[1]) < 0.5:  # nicht mitten ins Blickfeld
                continue
            self.knots.append((d, math.radians(rng.uniform(1.0, 3.0)), rng.uniform(0.35, 0.75)))

    def band_point(self, rng, spread=0.12):
        v = rng.normal(size=3)
        v -= self.band_n * np.dot(v, self.band_n)
        v /= np.linalg.norm(v)
        v += self.band_n * rng.normal() * spread
        return v / np.linalg.norm(v)


def view_mask(lon, lat):
    """Lesbarkeit: vorn-mitte/unten (hinter Strecke + Noten) abdunkeln."""
    front = np.exp(-(lon / F32(0.62)) ** 2) * smoothstep(F32(0.22), F32(-0.30), lat)
    low = smoothstep(F32(0.12), F32(-0.75), lat)
    return np.clip(1 - 0.72 * front - 0.35 * low, 0.12, 1)


def nebula_rows(args):
    name, W, H, r0, r1, seed = args
    pal = PALETTES[name]
    rng = np.random.default_rng(seed)
    comp = Comp(pal, rng)
    nz = Noise3(seed + 1)
    d, lon, lat = grid_dirs(W, H, r0, r1)

    # Grossform: Band (gewellt) + Wolkenmassen.
    wob = nz.fbm(d, 1.1, 3)
    b = np.tensordot(comp.band_n.astype(F32), d, axes=1) + F32(0.22) * wob
    band = np.exp(-(b / F32(0.34)) ** 2)
    clouds = np.zeros_like(band)
    for c, r, s in comp.clouds:
        ang2 = 2 * (1 - np.tensordot(c.astype(F32), d, axes=1))  # ~ Winkel^2
        clouds += F32(s) * np.exp(-ang2 / F32(r * r))
    mask = np.clip(band * 0.6 + clouds, 0, 1.5)
    mask *= np.clip(0.55 + 0.9 * nz.fbm(d, 0.9, 3), 0.15, 1.3)

    # Domain-Warp (zweistufig): q verbiegt die Gaswolken, q2 die Filamente.
    q = [nz.fbm(d + F32(k * 7.3), 1.4, 3) for k in range(3)]
    pw = [d[i] + F32(0.6) * q[i] for i in range(3)]
    n1 = nz.fbm(pw, 2.1, 8, gain=0.54)
    q2 = [d[i] + F32(0.45) * q[(i + 1) % 3] + F32(0.18) * n1 for i in range(3)]

    # Weich, ohne Plateau: Dichte exponentiell aus dem Rauschen, Ränder laufen aus.
    dens = np.exp(F32(2.8) * (n1 - F32(0.12)))
    gas = mask ** F32(1.6) * dens * F32(0.42)
    fil = nz.ridged(q2, 4.4, 6)
    fil = (fil ** F32(2.6)) * mask ** F32(1.3) * smoothstep(-0.35, 0.3, n1) * F32(0.7)

    # Ferner Dunst: weich, kuehler, gibt Tiefe hinter dem nahen Gas.
    hz = nz.fbm([d[i] + F32(0.35) * q[i] for i in range(3)], 1.0, 4)
    haze = np.clip(mask * 0.8 + band * 0.4, 0, 1.2) * smoothstep(-0.45, 0.6, hz)

    # Emissions-Knoten: kompakte, klumpige HII-Regionen.
    knot = np.zeros_like(gas)
    for c, r, s in comp.knots:
        ang2 = 2 * (1 - np.tensordot(c.astype(F32), d, axes=1))
        knot += F32(s) * np.exp(-ang2 / F32(r * r))
    knot *= (smoothstep(-0.25, 0.45, n1) + fil * F32(0.8)) * np.clip(mask, 0, 1)

    # Milchstrassen-Leuchten: unaufgeloeste Sternwolken im Band (klumpig, weich),
    # liegt hinter dem Staub -> dunkle Risse wie in echten Galaxie-Baendern.
    sc_ = nz.fbm(pw, 4.2, 4)
    milky = band ** F32(2.4) * (F32(0.25) + smoothstep(-0.35, 0.55, sc_)) * F32(0.03)

    E = gas * F32(1.0) + fil * F32(0.8) + knot * F32(0.4)
    hue = smoothstep(-0.28, 0.32, nz.fbm([d[i] + F32(0.5) * q[i] for i in range(3)], 0.85, 3))
    hue = (hue * F32(pal["hue_amt"]))[..., None]
    e1 = F32(1) - np.exp(-E * F32(1.5))
    col = ramp([hexcol(h) for h in pal["ramp_a"]], e1) * (1 - hue) \
        + ramp([hexcol(h) for h in pal["ramp_b"]], e1) * hue
    col *= F32(pal.get("gain", 0.85))
    col += hexcol(pal["haze"]).astype(F32) * (haze * F32(0.9))[..., None]
    col += hexcol(pal["knot"]).astype(F32) * (knot ** F32(1.5) * F32(0.55))[..., None]
    mcol = hexcol("#fff2e6") * 0.35 + hexcol(pal["ramp_b"][3]) * 0.4 + hexcol(pal["ramp_a"][3]) * 0.6
    col += mcol.astype(F32) * milky[..., None]

    # Staub: duenne dunkle Bahnen + breite Absorption, rotet (blau staerker).
    nd = nz.fbm([q2[i] + F32(3.1) for i in range(3)], 2.6, 6)
    lanes = (1 - np.abs(nd)) ** F32(5.0) * smoothstep(-0.2, 0.25, n1)
    broad = smoothstep(-0.05, 0.45, nz.fbm([q[i] * F32(0.8) + d[i] for i in range(3)], 1.7, 5))
    A = (lanes * F32(0.75) + broad * F32(1.3)) * np.clip(mask * 1.2 + band * 0.5, 0, 1)
    k = np.asarray(pal["dust"], dtype=F32)
    col *= np.exp(-A[..., None] * k * F32(1.25))

    col += hexcol(pal["base"]).astype(F32) * (0.55 + 0.45 * np.clip(mask + band, 0, 1))[..., None]
    col *= view_mask(lon, lat)[..., None]
    return r0, col.astype(F32), band.astype(F32)


# ---------------------------------------------------------------------------
# Sterne: Farbtemperatur, Helligkeitsverteilung, Splats.
# ---------------------------------------------------------------------------
_BB = [(2800, "#ffa65a"), (3500, "#ffc283"), (4500, "#ffdab0"), (5500, "#ffeedd"),
       (6500, "#fff6f0"), (8000, "#e4ecff"), (11000, "#cbdaff"), (20000, "#aec4ff"),
       (35000, "#9db4ff")]
_BB_T = np.log([t for t, _ in _BB])
_BB_C = np.array([hexcol(c) for _, c in _BB])


def star_color(temp, sat=1.15):
    lt = np.log(np.clip(temp, 2800, 35000))
    c = np.stack([np.interp(lt, _BB_T, _BB_C[:, i]) for i in range(3)], -1)
    lum = (c * [0.2126, 0.7152, 0.0722]).sum(-1, keepdims=True)
    c = lum + (c - lum) * sat
    return np.clip(c / np.maximum(c.max(-1, keepdims=True), 1e-6), 0, 1)


def sample_temps(rng, n, hot_bias=0.0):
    """Viele kuehle (K/M), weniger heisse (O/B) Sterne; hot_bias fuer junge Haufen."""
    lt = rng.normal(math.log(5200) + hot_bias, 0.42, n)
    return np.exp(lt)


def dir_to_px(d, W, H):
    lon = np.arctan2(d[..., 0], -d[..., 2])
    lat = np.arcsin(np.clip(d[..., 1], -1, 1))
    return (lon / (2 * math.pi) + 0.5) * W, (0.5 - lat / math.pi) * H


def deposit(img, d, rgb, W, H):
    """Punktquellen bilinear verteilen (Sub-Pixel-Sterne)."""
    u, v = dir_to_px(d, W, H)
    u -= 0.5
    v -= 0.5
    x0 = np.floor(u).astype(np.int64)
    y0 = np.floor(v).astype(np.int64)
    fx, fy = u - x0, v - y0
    flat = img.reshape(-1, 3)
    for dx, dy, wt in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)),
                       (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
        yy = np.clip(y0 + dy, 0, H - 1)
        idx = yy * W + (x0 + dx) % W
        for ch in range(3):
            flat[:, ch] += np.bincount(idx, weights=wt * rgb[:, ch], minlength=W * H).astype(F32)


def splat(img, d0, radius, profile, rgb, W, H):
    """Ausgedehnte Quelle auf der Kugel: profile(x, y) in Tangential-Koordinaten (rad)."""
    lon0 = math.atan2(d0[0], -d0[2])
    lat0 = math.asin(max(-1.0, min(1.0, d0[1])))
    u0 = (lon0 / (2 * math.pi) + 0.5) * W
    v0 = (0.5 - lat0 / math.pi) * H
    pix = math.pi / H
    hh = int(math.ceil(radius / pix)) + 1
    hw = min(W // 2 - 1, int(math.ceil(radius / pix / max(math.cos(lat0), 0.04))) + 1)
    ys = np.arange(max(0, int(v0) - hh), min(H, int(v0) + hh + 1))
    xs = np.arange(int(u0) - hw, int(u0) + hw + 1)
    if len(ys) == 0:
        return
    lon = ((xs + 0.5) / W - 0.5) * 2 * math.pi
    lat = (0.5 - (ys + 0.5) / H) * math.pi
    lon, lat = np.meshgrid(lon, lat)
    cl = np.cos(lat)
    dx, dy, dz = cl * np.sin(lon), np.sin(lat), -cl * np.cos(lon)
    east = np.array([math.cos(lon0), 0.0, math.sin(lon0)])
    north = np.array([-math.sin(lat0) * math.sin(lon0), math.cos(lat0), math.sin(lat0) * math.cos(lon0)])
    front = dx * d0[0] + dy * d0[1] + dz * d0[2]
    ok = front > 0.5
    x = (dx * east[0] + dz * east[2]) / np.maximum(front, 1e-3)
    y = (dx * north[0] + dy * north[1] + dz * north[2]) / np.maximum(front, 1e-3)
    val = np.where(ok, profile(x, y), 0.0).astype(F32)
    img[ys[0]:ys[-1] + 1][:, xs % W] += val[..., None] * np.asarray(rgb, dtype=F32)


def random_dirs(rng, n):
    v = rng.normal(size=(n, 3))
    return v / np.linalg.norm(v, axis=1, keepdims=True)


def band_weighted_dirs(rng, comp, n, band_frac):
    nb = int(n * band_frac)
    out = [random_dirs(rng, n - nb)]
    v = random_dirs(rng, nb)
    off = rng.normal(0, 0.16, nb) * np.abs(rng.normal(0, 1, nb))  # schlank, dichter Kern
    v -= comp.band_n * (v @ comp.band_n)[:, None]
    v /= np.linalg.norm(v, axis=1, keepdims=True)
    v += comp.band_n * off[:, None]
    out.append(v / np.linalg.norm(v, axis=1, keepdims=True))
    return np.concatenate(out)


def front_dim(d):
    """Sterne vorn-unten etwas zurueck (wie view_mask, nur milder)."""
    lon = np.arctan2(d[:, 0], -d[:, 2])
    lat = np.arcsin(np.clip(d[:, 1], -1, 1))
    f = np.exp(-(lon / 0.6) ** 2) * smoothstep(0.15, -0.3, lat)
    return 1 - 0.45 * f


def star_layer(name, W, H, seed):
    pal = PALETTES[name]
    rng = np.random.default_rng(seed + 100)
    comp = Comp(pal, np.random.default_rng(seed))
    img = np.zeros((H, W, 3), dtype=F32)
    sc = (W / 4096.0) ** 2  # Anzahl skaliert mit der Flaeche

    # Helligkeit nach Magnitude: N(m) ~ 10^(0.36 m), Fluss perzeptiv gestaucht.
    n = int(30000 * sc) + 400
    m = np.log10(rng.uniform(10 ** (0.36 * 0.0), 10 ** (0.36 * 9.0), n)) / 0.36
    d = band_weighted_dirs(rng, comp, n, 0.42)
    flux = 10 ** (-0.4 * m * 0.7) * front_dim(d)
    temp = sample_temps(rng, n)
    rgb = star_color(temp, 0.45 + 0.8 * np.clip(flux / 0.2, 0, 1)[:, None]) * flux[:, None]

    # Sternhaufen: offene (jung, blau-weiss) und Kugelhaufen (alt, gelblich).
    cd, cr, cf, ct = [], [], [], []
    for k in range(9):
        c = comp.band_point(rng, 0.2)
        glob = k >= 6
        cnt = int((rng.integers(260, 480) if glob else rng.integers(50, 140)) * max(sc, 0.25))
        spread = math.radians(rng.uniform(0.25, 0.5) if glob else rng.uniform(0.6, 1.4))
        r = np.abs(rng.standard_cauchy(cnt) if glob else rng.normal(size=cnt)) * spread * (0.25 if glob else 1.0)
        r = np.minimum(r, spread * 3)
        ang = rng.uniform(0, 2 * math.pi, cnt)
        e1 = np.cross(c, [0, 1, 0])
        e1 /= np.linalg.norm(e1)
        e2 = np.cross(c, e1)
        pts = c + np.outer(r * np.cos(ang), e1) + np.outer(r * np.sin(ang), e2)
        cd.append(pts / np.linalg.norm(pts, axis=1, keepdims=True))
        mm = rng.uniform(3.5, 9.0, cnt) if not glob else rng.uniform(5.5, 9.5, cnt)
        cf.append(10 ** (-0.4 * mm * 0.62))
        ct.append(sample_temps(rng, cnt, hot_bias=0.75) if not glob else rng.normal(4800, 500, cnt))
    cd = np.concatenate(cd)
    cflux = np.concatenate(cf) * front_dim(cd)
    crgb = star_color(np.concatenate(ct), 0.6 + 0.6 * np.clip(cflux / 0.2, 0, 1)[:, None]) * cflux[:, None]

    alld = np.concatenate([d, cd])
    allf = np.concatenate([flux, cflux])
    allc = np.concatenate([rgb, crgb])
    bright = allf > 0.2
    faint = ~bright
    deposit(img, alld[faint], allc[faint] * 1.35, W, H)
    px = PXR
    s_core = 0.62 * max(PXR, math.pi / H)  # Kern ~0.62 Texel
    img = ndimage.gaussian_filter(img, sigma=(0.6 * W / 4096.0 + 0.2, 0.6 * W / 4096.0 + 0.2, 0),
                                  mode=("nearest", "wrap", "nearest")) * 2.2

    # Helle Sterne einzeln: scharfer Kern + weicher Halo (Bloom) + ferner Schein.
    order = np.argsort(-allf[bright])
    bd, bf, bc = alld[bright][order], allf[bright][order], allc[bright][order]
    for i in range(len(bd)):
        f = float(bf[i])
        col = bc[i] / max(f, 1e-6)
        sc_ = s_core * (1.0 + 0.9 * f)
        sh = px * (1.8 + 4.5 * f)
        sw = px * (6 + 22 * f * f)
        top = i < 10

        def prof(x, y, f=f, sc_=sc_, sh=sh, sw=sw, top=top):
            r2 = x * x + y * y
            v = 1.15 * f * np.exp(-r2 / (2 * sc_ * sc_))
            v += 0.07 * f * np.exp(-r2 / (2 * sh * sh))
            v += 0.02 * f * f * np.exp(-np.sqrt(r2) / sw)
            if top:  # sehr feine, kurze Beugungs-Andeutung nur bei den hellsten
                ax = np.exp(-(y / (px * 0.55)) ** 2) * np.exp(-np.abs(x) / (px * 14))
                ay = np.exp(-(x / (px * 0.55)) ** 2) * np.exp(-np.abs(y) / (px * 14))
                v += 0.05 * f * (ax + ay)
            return v
        rad = max(sw * 7, sh * 4, px * 4)
        halo_col = 0.65 * col + 0.35 * np.array([1.0, 1.0, 1.0])
        splat(img, bd[i], rad, prof, halo_col, W, H)
    return img, comp


# ---------------------------------------------------------------------------
# Nebel-Extras: unaufgeloester Sternenstaub, Haufen-Schein, ferne Galaxien.
# ---------------------------------------------------------------------------
def nebula_extras(img, name, W, H, seed, comp):
    pal = PALETTES[name]
    rng = np.random.default_rng(seed + 200)
    sc = (W / 4096.0) ** 2
    # Milchstrassen-Sternwolken: sehr viele, sehr schwache Punkte -> koerniges Leuchten.
    n = int(400000 * sc)
    d = band_weighted_dirs(rng, comp, n, 0.9)
    f = rng.uniform(0.002, 0.008, n) * front_dim(d)
    rgb = star_color(sample_temps(rng, n, -0.1), 0.8) * f[:, None]
    dust = np.zeros_like(img)
    deposit(dust, d, rgb, W, H)
    dust = ndimage.gaussian_filter(dust, sigma=(2.2 * W / 4096, 2.2 * W / 4096, 0), mode=("nearest", "wrap", "nearest"))
    img += dust * 0.35

    px = PXR
    # Reflexionsnebel-Schein um zwei junge Haufen (blaeulich, weich).
    for _ in range(2):
        c = comp.band_point(rng, 0.2)
        r = math.radians(rng.uniform(1.5, 3.0))
        splat(img, c, r * 3, lambda x, y, r=r: 0.05 * np.exp(-(x * x + y * y) / (2 * r * r)),
              hexcol(pal["cluster"]), W, H)

    # Ferne Galaxien: kleine Spiral-/Elliptik-Flecken, dazu eine groessere im Blickfeld.
    gals = []
    for _ in range(int(14 * max(sc, 0.3))):
        gals.append((random_dirs(rng, 1)[0], px * rng.uniform(1.0, 3.2), rng.uniform(0.012, 0.04), False))
    hl = pal["hero"][0]
    gd = lonlat_dir(-hl * 0.55 + rng.uniform(-6, 6), rng.uniform(17, 21))
    gals.append((gd, px * 11.0, 0.10, True))
    for gd, re, br, spiral in gals:
        ang = rng.uniform(0, math.pi)
        qx = rng.uniform(0.3, 0.75)
        ca, sa = math.cos(ang), math.sin(ang)
        core_col = star_color(np.array([4300.0]))[0]
        disk_col = star_color(np.array([9000.0]))[0]

        def prof(x, y, re=re, br=br, spiral=spiral, ca=ca, sa=sa, qx=qx):
            xr = x * ca + y * sa
            yr = (-x * sa + y * ca) / qx
            r = np.sqrt(xr * xr + yr * yr) / re
            core = np.exp(-(r / 0.18) ** 0.9 * 1.0)
            disk = np.exp(-r * 1.7)
            if spiral:
                th = np.arctan2(yr, xr)
                arm = 0.5 + 0.5 * np.cos(2 * (th - np.log(r + 0.05) * 2.6))
                disk = disk * (0.35 + 0.9 * arm ** 2.5)
            return br * np.stack([core, disk], -1)

        rad = re * 6
        # zwei Komponenten: warmer Kern, blaeulicher Arm-/Scheibenanteil
        splat(img, gd, rad, lambda x, y, p=prof: p(x, y)[..., 0], core_col * 0.9, W, H)
        splat(img, gd, rad, lambda x, y, p=prof: p(x, y)[..., 1] * 0.6, disk_col, W, H)


# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------
def tonemap(lin, exposure):
    x = lin * exposure
    return 1 - np.exp(-x)  # weiches Abrollen, nichts brennt hart aus


def to_u8(lin, rng):
    s = lin_to_srgb(lin)
    s = s * 255.0 + rng.triangular(-0.5, 0, 0.5, s.shape)  # TPDF-Dither gegen Banding
    return np.clip(np.rint(s), 0, 255).astype(np.uint8)


def camera_view(pano, stars, W, H, vw=960, vh=540, pitch=-15.2, fov=72.0):
    """Ansicht wie die Mania-Kamera (gnomonisch), fuer die schnelle Kontrolle."""
    th = math.tan(math.radians(fov) * 0.5)
    ys, xs = np.mgrid[0:vh, 0:vw].astype(np.float64)
    x = (2 * (xs + 0.5) / vw - 1) * th * vw / vh
    y = (1 - 2 * (ys + 0.5) / vh) * th
    z = -np.ones_like(x)
    p = math.radians(pitch)
    y2 = y * math.cos(p) - z * math.sin(p)
    z2 = y * math.sin(p) + z * math.cos(p)
    d = np.stack([x, y2, z2], -1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    u, v = dir_to_px(d, W, H)
    out = np.zeros((vh, vw, 3))
    for src, g in ((pano, 1.0), (stars, 1.0)):
        for ch in range(3):
            out[..., ch] += g * ndimage.map_coordinates(src[..., ch], [v - 0.5, u - 0.5], order=1,
                                                         mode="grid-wrap")
    return out


def build(name, W, seed, out_dir, preview):
    H = W // 2
    t0 = time.time()
    pal = PALETTES[name]
    s = pal["seed"] + seed * 1000
    rows = max(16, (1 << 19) // W)
    jobs = [(name, W, H, r, min(H, r + rows), s) for r in range(0, H, rows)]
    neb = np.zeros((H, W, 3), dtype=F32)
    for r0, col, _band in map(nebula_rows, jobs):
        neb[r0:r0 + col.shape[0]] = col
    stars, comp = star_layer(name, W, H, s)
    nebula_extras(neb, name, W, H, s, comp)
    rng = np.random.default_rng(s + 7)
    neb_t = tonemap(neb, 1.0)
    star_t = tonemap(stars, 1.0)
    os.makedirs(out_dir, exist_ok=True)
    pa = os.path.join(out_dir, "sky_%s.webp" % name)
    pb = os.path.join(out_dir, "sky_%s_stars.webp" % name)
    # Wurzel-Kodierung (ENC=2): hebt die Schatten in mehr 8-Bit-Stufen, damit
    # WebP die dunklen Verlaeufe nicht zu Blöcken quantisiert. Der Shader
    # dekodiert mit pow(textur_linear, 2.0).
    Image.fromarray(to_u8(np.sqrt(neb_t), rng)).save(pa, "WEBP", quality=88, method=6)
    Image.fromarray(to_u8(np.sqrt(star_t), rng)).save(pb, "WEBP", quality=88, method=6)
    msg = "%s: %dx%d  %.1f s  nebula %.2f MB  stars %.2f MB" % (
        name, W, H, time.time() - t0, os.path.getsize(pa) / 1e6, os.path.getsize(pb) / 1e6)
    if preview:
        os.makedirs(preview, exist_ok=True)
        dec = [srgb_to_lin(np.asarray(Image.open(f).convert("RGB"), dtype=np.float64) / 255.0) ** 2
               for f in (pa, pb)]
        view = camera_view(dec[0], dec[1], W, H)
        Image.fromarray(to_u8(np.clip(view, 0, 1), rng)).save(os.path.join(preview, "cam_%s.png" % name))
        small = Image.fromarray(to_u8(np.clip(neb_t + star_t, 0, 1), rng)).resize((2048, 1024), Image.LANCZOS)
        small.save(os.path.join(preview, "pano_%s.png" % name))
    return msg


def _build_star(a):
    return build(*a)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--width", type=int, default=4096)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--only", default="", help="kommagetrennte Palettennamen")
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default="", help="Ordner fuer Kamera-/Panorama-PNGs")
    ap.add_argument("--jobs", type=int, default=4)
    a = ap.parse_args()
    names = [n for n in (a.only.split(",") if a.only else PALETTES) if n]
    for n in names:
        if n not in PALETTES:
            sys.exit("unbekannte Palette: %s (%s)" % (n, ", ".join(PALETTES)))
    work = [(n, a.width, a.seed, a.out, a.preview) for n in names]
    if a.jobs > 1 and len(work) > 1:
        with Pool(min(a.jobs, len(work))) as pool:
            for msg in pool.imap(_build_star, work):
                print(msg, flush=True)
    else:
        for w in work:
            print(_build_star(w), flush=True)


if __name__ == "__main__":
    main()
