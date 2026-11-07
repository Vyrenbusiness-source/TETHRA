#!/usr/bin/env python3
"""TETHRA Welt-Thema "Aurora"/"Frost" (bedrohliche Polarnacht): offline-Panoramen fuer
shaders/theme_aurora.gdshader. Fuer ruhige, melodische Songs.

Erzeugt in assets_game/themes/aurora/:
  aurora.webp          4096x2048 RGBA  Szene: Polarnacht-Himmel (Zenit fast
                       schwarz, tuerkiser Horizont-Dunst), sehr feine Milchstrasse,
                       ferne vergletscherte Bergkette, Gletscherkante, Eisberge
                       (Tafel/Spitze) mit Randlicht, spiegelglattes Eismeer mit
                       Treibeis-Schollen und gebackenen Spiegelungen.
                       Alpha: oben = Himmel sichtbar (0 hinter Bergen/Eis),
                              unten = Spiegel-Staerke des Wassers (Fresnel,
                              0 auf Schollen und hinter Eisberg-Spiegelungen).
  aurora_stars.webp    4096x2048 RGB   klare Sterne (nur obere Halbkugel).
  aurora_aurora.webp   4096x1024 RGB   Polarlicht-Vorhaenge als eigene Ebene,
                       nur obere Halbkugel (v = 1 - lat/90 Grad). Der Shader
                       laesst sie wehen und spiegelt sie im Wasser.

Abbildung wie shaders/sky_panorama.gdshader: u = atan(d.x, -d.z)/2pi + 0.5,
v = 0.5 - asin(d.y)/pi (Bildmitte = vorn, -Z). Kodierung: alle Kanaele
wurzel-kodiert (linear = textur^2, Alpha ebenso).

  python tools/gen_theme_aurora.py                       # 4096, Seed 0
  python tools/gen_theme_aurora.py --width 1024 --preview <ordner>
  python tools/gen_theme_aurora.py --seed 3              # andere Variante
--preview schreibt eine Kamera-Ansicht wie im Spiel (Komfort-Kamera: Neigung
-16 Grad, fov 62) und das Panorama verkleinert als PNG.
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
OUT_DIR = os.path.join(ROOT, "assets_game", "themes", "aurora")
DEG = math.pi / 180.0
EYE_H = 14.0  # Augenhoehe ueber dem Wasser (m) fuer Perspektive von Eis/Schollen


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def hexcol(h):
    h = h.lstrip("#")
    return srgb_to_lin([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]).astype(F32)


# ---------------------------------------------------------------------------
# Farbsatz "Frost" (sRGB-Hex): EINE Farbfamilie, entsaettigtes Eis-Tuerkis /
# Stahlgrau. Kein Gruen, kein Violett, kein Neon. Schwarz bleibt schwarz.
# ---------------------------------------------------------------------------
COL = dict(
    zenith="#010204", sky_mid="#020508", sky_low="#060c10", horizon="#0e181c",
    airglow="#0a1316", haze="#15232a", water="#000102",
    mtn_dark="#010204", mtn_snow="#0a1216", mtn_haze="#0d181d", rim="#8fb3b8",
    ice_shade="#020508", ice_lit="#0a1419", ice_blue="#0b1f25", ice_top="#111d22",
    floe="#05090b", floe_lit="#0d171b",
    # Polarlicht nur als fahles Eis-Tuerkis: heller Saum -> Koerper -> Auslauf
    au_edge="#cfe3e5", au_green="#86b6ba", au_teal="#64949a", au_blue="#41626a",
    au_violet="#28393f",
)
C = {k: hexcol(v) for k, v in COL.items()}


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
        self.rots = []
        for _ in range(12):
            q, _r = np.linalg.qr(rng.normal(size=(3, 3)))
            self.rots.append((q.astype(F32), rng.uniform(-50, 50, 3).astype(F32)))

    def noise(self, x, y, z):
        xi, yi, zi = np.floor(x), np.floor(y), np.floor(z)
        xf, yf, zf = (x - xi).astype(F32), (y - yi).astype(F32), (z - zi).astype(F32)
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

        x1, y1, z1 = xf - 1, yf - 1, zf - 1
        x00 = g(aa, xf, yf, zf) + u * (g(ba, x1, yf, zf) - g(aa, xf, yf, zf))
        x10 = g(ab, xf, y1, zf) + u * (g(bb, x1, y1, zf) - g(ab, xf, y1, zf))
        x01 = g(aa + 1, xf, yf, z1) + u * (g(ba + 1, x1, yf, z1) - g(aa + 1, xf, yf, z1))
        x11 = g(ab + 1, xf, y1, z1) + u * (g(bb + 1, x1, y1, z1) - g(ab + 1, xf, y1, z1))
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
        amp, norm, f = 1.0, 0.0, freq
        for i in range(octaves):
            s += F32(amp) * self._oct(p, i, f)
            norm += amp
            amp *= gain
            f *= lac
        return s / F32(norm)

    def ridged(self, p, freq, octaves, gain=0.55, lac=2.05):
        s = np.zeros_like(p[0])
        amp, norm, f = 1.0, 0.0, freq
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

    def ring(self, lon, freq, octaves, z=0.0, kind="fbm", **kw):
        """Nahtloses 1D-Rauschen ueber den Laengengrad (Kreis im 3D-Raum)."""
        lon = np.asarray(lon, dtype=F32)
        p = (np.cos(lon), np.sin(lon), np.full_like(lon, F32(z)))
        return (self.ridged if kind == "ridged" else self.fbm)(p, freq, octaves, **kw)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def ramp(stops, t):
    stops = np.asarray(stops, dtype=F32)
    n = len(stops) - 1
    x = np.clip(t, 0, 1) * n
    i = np.minimum(x.astype(np.int32), n - 1)
    f = (x - i)[..., None]
    f = f * f * (3 - 2 * f)
    return stops[i] * (1 - f) + stops[i + 1] * f


def wrap_deg(x):
    return (x + 180.0) % 360.0 - 180.0


# ---------------------------------------------------------------------------
# Szene: Himmel, Berge, Gletscher, Eisberge, Wasser, Schollen
# ---------------------------------------------------------------------------
def sky_color(lon, lat, nz):
    """Polarnacht-Verlauf (ohne Polarlicht, das kommt als eigene Ebene)."""
    la = np.maximum(lat, 0.0)
    t = np.clip(la / 90.0, 0, 1) ** 0.42
    col = ramp([C["horizon"], C["sky_low"], C["sky_mid"], C["zenith"], C["zenith"]], t)
    # Duenner Airglow-Schleier (gruenlich) ueber dem Horizont, leicht wellig.
    ag = np.exp(-((la - 9.0 - 2.5 * nz) / 6.0) ** 2) * (0.55 + 0.45 * nz)
    col = col + C["airglow"][None, None, :] * (0.35 * ag)[..., None]
    # Sehr grossflaechige Helligkeits-Variation gegen sterile Flaechen.
    col = col * (1.0 + 0.10 * nz)[..., None]
    # Horizont-Dunstband (tuerkis), scharf am Horizont, weich nach oben.
    hz = np.exp(-la / 1.6) * 0.55 + np.exp(-la / 6.0) * 0.25
    col = col + C["haze"][None, None, :] * hz[..., None]
    return col


def milky_way(dirs, noise, W):
    """Sehr feine, unaufgeloeste Milchstrasse (statisch, ganz dezent)."""
    n = np.array([0.42, 0.55, 0.72])
    n /= np.linalg.norm(n)
    dist = np.abs(dirs[0] * n[0] + dirs[1] * n[1] + dirs[2] * n[2])
    band = np.exp(-(dist / 0.18) ** 2)
    cl = noise.fbm(dirs, 2.6, 6)
    v = band * np.clip(0.25 + 1.3 * cl, 0, 1.2) ** 1.6
    return v[..., None] * hexcol("#1c2326")[None, None, :] * F32(0.06)


class Berg:
    """Ein Eisberg / eine Bergkette als Hoehenprofil top(lon) ueber Wasserlinie base."""

    def __init__(self, lon, top, base, kind, dist, seed):
        self.lon, self.top, self.base, self.kind, self.dist, self.seed = lon, top, base, kind, dist, seed


def iceberg_profile(x, w, h, kind, noise, seed):
    """Hoehe (Grad ueber der Wasserlinie) fuer Abstand x (Grad) vom Zentrum.
    Aus mehreren zufaelligen Massen zusammengesetzt + fraktale Kontur."""
    rng = np.random.default_rng(seed * 7919 + 13)
    q = x / w
    n_lo = noise.ring(q * 1.1, 2.2, 5, z=seed * 3.7)
    n_hi = noise.ring(q * 1.1, 11.0, 5, z=seed * 5.1 + 2, gain=0.6)
    if kind == "tabular":
        # flaches, leicht geneigtes Plateau, Flanken mit Abbruechen und Stufen
        tilt = rng.uniform(-0.12, 0.12)
        e0 = 0.78 + 0.10 * n_lo
        edge = smoothstep(1.0 + 0.08 * n_hi, e0, np.abs(q + 0.05 * n_lo))
        prof = edge * (1.0 + tilt * q + 0.06 * n_lo + 0.025 * n_hi)
        for _ in range(rng.integers(1, 4)):  # abgebrochene Stufen / Kerben
            c = rng.uniform(-0.7, 0.7)
            wd = rng.uniform(0.06, 0.22)
            dep = rng.uniform(0.08, 0.3)
            prof = prof * (1.0 - dep * smoothstep(wd, wd * 0.6, np.abs(q - c)))
        # vorgelagerter Abbruch-Block
        c = rng.choice([-1, 1]) * rng.uniform(0.85, 1.05)
        prof = np.maximum(prof, 0.42 * smoothstep(0.2, 0.12, np.abs(q - c)) * (1 + 0.1 * n_hi))
        return h * np.clip(prof, 0, None)
    if kind == "dome":
        r = np.clip(1.0 - (q * (1.0 + 0.08 * n_lo)) ** 2, 0, 1)
        return h * (r ** rng.uniform(0.45, 0.7)) * (1.0 + 0.08 * n_lo + 0.05 * n_hi)
    # "peak": mehrere Massen (konkav/konvex), zerkluefteter Grat
    prof = np.zeros_like(q)
    k = rng.integers(4, 8)
    cs = np.sort(rng.uniform(-0.7, 0.7, k))
    for i in range(k):
        hk = 1.0 if i == k // 2 else rng.uniform(0.35, 0.8)
        wk = rng.uniform(0.18, 0.5)
        pk = rng.uniform(1.1, 2.2)  # konkave Flanken: scharfe, drohende Spitzen
        prof = np.maximum(prof, hk * np.clip(1.0 - np.abs(q - cs[i]) / wk, 0, 1) ** pk)
    prof = prof * (1.0 + 0.12 * n_lo) + 0.10 * n_hi * smoothstep(0.0, 0.2, prof)
    return h * np.clip(prof, 0, None) * smoothstep(1.15, 0.95, np.abs(q))


def scene(W, H, seed):
    noise = Noise3(seed + 1)
    rng = np.random.default_rng(seed + 2)
    lon1 = ((np.arange(W, dtype=F32) + 0.5) / W - 0.5) * F32(360.0)  # Grad
    lat1 = (0.5 - (np.arange(H, dtype=F32) + 0.5) / H) * F32(180.0)
    LON, LAT = np.meshgrid(lon1, lat1)
    lonr, latr = LON * F32(DEG), LAT * F32(DEG)
    cl = np.cos(latr)
    dirs = (cl * np.sin(lonr), np.sin(latr), -cl * np.cos(lonr))
    px = 180.0 / H  # Grad pro Pixel (vertikal)

    # Grossflaechiges Himmels-Rauschen in grober Aufloesung.
    small = (slice(None, None, 4), slice(None, None, 4))
    nz_s = noise.fbm(tuple(d[small] for d in dirs), 1.4, 4)
    nz = ndimage.zoom(nz_s, (H / nz_s.shape[0], W / nz_s.shape[1]), order=1)[:H, :W]

    # ---- Objekte (fern -> nah). base = Wasserlinie in Grad (negativ).
    objs = []
    # Ferne Bergkette rundum (Wasserlinie praktisch am Horizont).
    m1 = noise.ring(lon1 * F32(DEG), 2.2, 7, z=11.0, kind="ridged")
    m2 = noise.ring(lon1 * F32(DEG), 0.9, 3, z=17.0)
    env = 1.0 - 0.55 * np.exp(-(wrap_deg(lon1) / 16.0) ** 2)  # vorn-mitte flacher
    far_top = (0.15 + 3.3 * np.clip(m1 - 0.18, 0, 1) ** 1.35 * (0.55 + 0.6 * m2 + 0.25)) * env
    far_top = np.maximum(far_top, 0.12 + 0.12 * m2)
    objs.append(dict(kind="range", base=-0.04, top=far_top.astype(F32), haze=0.55, dist=60000.0))
    # Naehere Gletscher-Kante (flache Eisklippe mit Abbruechen), nur in Teilen.
    g1 = noise.ring(lon1 * F32(DEG), 9.0, 4, z=23.0)
    g2 = noise.ring(lon1 * F32(DEG), 1.3, 3, z=29.0)
    shelf_on = smoothstep(-0.05, 0.15, g2)
    shelf = (0.55 + 0.10 * g1 + 0.05 * np.sign(g1) * smoothstep(0.1, 0.3, np.abs(g1))) * shelf_on
    shelf = np.where(shelf_on > 0.02, shelf, 0.0)
    objs.append(dict(kind="shelf", base=-0.12, top=shelf.astype(F32), haze=0.30, dist=7000.0))

    # Naher Gletscher-Massiv: gezackte Grate, Eisnadeln, hoch an den Seiten,
    # vorn-mitte eine tiefe Scharte (dort kommen die Noten her).
    lr = lon1 * F32(DEG)
    nm1 = noise.ring(lr, 3.2, 8, z=31.0, kind="ridged", gain=0.58)
    nm2 = noise.ring(lr, 1.1, 3, z=37.0)
    nm3 = noise.ring(lr, 11.0, 4, z=41.0, kind="ridged", gain=0.6)
    al = np.abs(wrap_deg(lon1))
    side = 0.10 + 0.90 * smoothstep(11.0, 30.0, al) * (1.0 - 0.45 * smoothstep(95.0, 140.0, al))
    r1 = (nm1 - nm1.min()) / (nm1.max() - nm1.min())
    r3 = (nm3 - nm3.min()) / (nm3.max() - nm3.min())
    mas = (0.5 + 17.0 * r1 ** 2.1 * np.clip(0.75 + 0.6 * nm2, 0.3, 1.3)
           + 0.5 * r3 ** 3 * smoothstep(0.2, 0.5, r1)) * side
    objs.append(dict(kind="massif", base=-0.28, top=mas.astype(F32), haze=0.12, dist=3000.0))

    # Eisberge: (Laenge, Entfernung m, Hoehe m, Breite m, Art)
    bergs = [
        (-148, 5200, 46, 260, "tabular"), (-118, 3800, 30, 120, "peak"), (-92, 6400, 38, 420, "tabular"),
        (-63, 2600, 34, 120, "peak"), (-33, 900, 70, 140, "peak"), (-19, 2200, 26, 160, "tabular"),
        (-8, 7000, 20, 220, "tabular"), (13, 5600, 16, 110, "peak"), (29, 1100, 44, 280, "tabular"),
        (50, 2300, 36, 110, "peak"), (72, 1500, 58, 200, "peak"), (98, 4800, 40, 380, "tabular"),
        (131, 2600, 52, 220, "peak"), (160, 4400, 30, 260, "tabular"), (178, 3000, 26, 120, "dome"),
    ]
    for i, (lo, d, hm, wm, kind) in enumerate(bergs):
        lo = lo + rng.uniform(-2, 2)
        base = -math.degrees(math.atan(EYE_H / d))
        h = math.degrees(math.atan(hm / d))
        w = math.degrees(math.atan(wm / d))
        x = wrap_deg(lon1 - lo)
        top = iceberg_profile(x, w, h, kind, noise, i + 1).astype(F32)
        top = np.where(np.abs(x) < w * 1.3, top, 0.0).astype(F32)
        objs.append(dict(kind="berg", base=base, top=top, haze=float(np.clip(d / 16000.0, 0.03, 0.35)),
                         dist=float(d), lon=lo, w=w, h=h, x=x.astype(F32), seed=i))
    objs.sort(key=lambda o: -o["dist"])

    # Texturen der Eisflaechen: vertikale Klueftung + Schichtung.
    def ice_color(o, rel, top, lat):
        """rel: Grad ueber der Wasserlinie (r, W), top: Profil-Hoehe (1, W), lat: (r, 1)."""
        hrel = np.clip(rel / np.maximum(top, 1e-3), 0, 1)
        kind = o["kind"]
        one = np.ones_like(rel)
        lon = lon1[None, :]
        if kind == "massif":
            # dunkler Fels, steile Schnee-Rinnen (vertikal), Gletscherzunge am Fuss
            ga = noise.fbm(((lon * F32(DEG * 70) + lat * F32(0.9)) * one, lat * F32(0.5) * one,
                            one * F32(5.0)), 1.0, 4)
            gb = noise.fbm(((lon * F32(DEG * 70) - lat * F32(0.9)) * one, lat * F32(0.5) * one,
                            one * F32(6.0)), 1.0, 4)
            n = np.maximum(ga, gb)
            n2 = noise.fbm((lon * F32(DEG * 30) * one, lat * F32(0.6) * one, one * F32(9.0)), 1.0, 3)
            snow = smoothstep(0.42, 0.78, 0.5 + n + 0.3 * n2) * (0.35 + 0.65 * hrel)
            c = C["mtn_dark"] * (1 - snow)[..., None] + C["mtn_snow"] * snow[..., None]
            tongue = smoothstep(0.7, 0.1, rel) * smoothstep(0.0, 0.25, 0.5 + n2)
            c = c * (1 - tongue)[..., None] + C["ice_lit"] * (tongue * (0.8 + 0.4 * (0.5 + n)))[..., None]
        elif kind == "range":
            # verschneite Bergflanken: Rinnen + Grate, oben heller Schnee
            n = noise.fbm((lon * F32(DEG * 36) * one, lat * F32(0.35) * one, one * F32(3.0)), 1.0, 4)
            snow = smoothstep(0.25, 0.9, hrel + 0.25 * n)
            c = C["mtn_dark"] * (1 - snow)[..., None] + C["mtn_snow"] * snow[..., None]
            c = c * (0.75 + 0.5 * np.clip(0.5 + n, 0, 1))[..., None]
        elif kind == "shelf":
            n = noise.fbm((lon * F32(DEG * 260) * one, lat * F32(0.8) * one, one * F32(7.0)), 1.0, 3)
            c = C["ice_shade"] * (1 - hrel)[..., None] + C["ice_lit"] * hrel[..., None]
            c = c * (0.7 + 0.6 * np.clip(0.5 + n, 0, 1))[..., None]
            c = c + C["ice_blue"] * (0.35 * np.exp(-np.maximum(rel, 0) / 0.12))[..., None]
        else:
            xq = (o["x"] / o["w"])[None, :]
            # Klueftung: vertikale Streifen (x fein, Hoehe grob), Schichtung horizontal
            n = noise.fbm((xq * F32(9.0) * one, hrel * F32(1.6), one * F32(13.0 + o["seed"])), 1.0, 4)
            layer = 0.5 + 0.5 * np.sin(hrel * 38.0 + 3.0 * n)
            # Licht vom Polarlicht (vorn/Norden): die zur Mitte zeigende Flanke heller.
            sl = np.gradient(ndimage.gaussian_filter1d(top[0], 2.0)) / (360.0 / W)
            facet = smoothstep(-0.8, 0.8, -np.sign(o["lon"]) * sl)[None, :] * one
            face = smoothstep(0.0, 1.0, -np.sign(o["lon"]) * xq) * one
            lit = np.clip(0.1 + 0.45 * facet + 0.2 * face + 0.3 * hrel, 0, 1)
            c = C["ice_shade"] * (1 - lit)[..., None] + C["ice_lit"] * lit[..., None]
            c = c * (0.72 + 0.45 * np.clip(0.5 + n, 0, 1) + 0.10 * layer)[..., None]
            # leuchtendes Gletscherblau in Kluefte und an der Wasserlinie
            blue = np.clip(0.55 - n, 0, 1) * 0.35 + np.exp(-hrel / 0.12) * 0.75
            c = c + C["ice_blue"] * blue[..., None] * 0.55
            cap = smoothstep(0.86, 0.97, hrel)  # Schnee-Kappe oben
            c = c * (1 - 0.6 * cap)[..., None] + C["ice_top"] * (0.6 * cap)[..., None]
        # Randlicht: Polarlicht-Mint auf der obersten Kontur
        rim = np.exp(-np.clip(top - rel, 0, None) / (0.7 * px + 0.015 * np.sqrt(np.maximum(top, 0))))
        slope = np.abs(np.gradient(top[0])) / (360.0 / W)
        rim = rim / (1.0 + (slope / 0.7) ** 2)[None, :]
        c = c + C["rim"] * (rim * {"range": 0.05, "massif": 0.07}.get(kind, 0.09))[..., None]
        # Luftperspektive: in den Horizont-Dunst
        hz = o["haze"] * np.exp(-np.maximum(rel, 0) / (1.8 if kind == "range" else 1.0))
        return c * (1 - hz)[..., None] + C["haze"] * (hz * 0.9)[..., None]

    def paint(img, alpha, lat, lat_eff, reflect):
        """Objekte (fern -> nah) malen. lat: (r, 1) oder (r, W); lat_eff(o, lat) effektiv."""
        for o in objs:
            rel = lat_eff(o, lat) - o["base"]
            top = o["top"][None, :]
            tmax = float(top.max())
            if tmax <= 1e-3:
                continue
            rows = np.nonzero(((rel > -px) & (rel < tmax + px)).any(axis=1))[0]
            if len(rows) == 0:
                continue
            ys = slice(rows[0], rows[-1] + 1)
            rr = np.broadcast_to(rel, (rel.shape[0], W))[ys]
            ins = (smoothstep(top + 0.5 * px, top - 0.5 * px, rr)
                   * smoothstep(-0.5 * px, 0.5 * px, rr) * (top > 1e-3)).astype(F32)
            la = np.broadcast_to(lat, (lat.shape[0], W))[ys]
            c = ice_color(o, rr, top, la)
            if reflect:
                c = c * 0.62  # Spiegelung etwas dunkler
            img[ys] = img[ys] * (1 - ins)[..., None] + c * ins[..., None]
            alpha[ys] = alpha[ys] * (1 - ins)
        return img, alpha

    Hh = H // 2
    U = slice(0, Hh)
    D = slice(Hh, H)
    latU, latD = lat1[U], lat1[D]
    # ---- Direkter Blick, obere Halbkugel
    LATU = np.broadcast_to(latU[:, None], (Hh, W))
    dirsU = tuple(d[U] for d in dirs)
    imgU = (sky_color(LON[U], LATU, nz[U])
            + milky_way(dirsU, noise, W) * smoothstep(2.0, 14.0, LATU)[..., None]).astype(F32)
    visU = np.ones((Hh, W), dtype=F32)
    imgU, visU = paint(imgU, visU, latU[:, None], lambda o, la: la, False)
    fogn = noise.fbm((LON[U] * F32(DEG * 9.0), LATU * F32(0.5), np.full_like(LATU, 83.0)), 1.0, 4)
    fog = (np.exp(-LATU / 0.9) * 0.55 + np.exp(-LATU / 3.2) * 0.22) * np.clip(0.55 + 0.9 * fogn, 0.1, 1.3)
    fog = np.clip(fog, 0, 0.85)
    imgU = imgU * (1 - fog)[..., None] + C["haze"] * (fog * 0.85)[..., None]

    # ---- Wasser (untere Halbkugel): Spiegelung + Fresnel + Schollen
    LATD = np.broadcast_to(latD[:, None], (Hh, W))
    LOND = LON[D]
    lonrD = lonr[D]
    dep = np.maximum(-LATD, 1e-3) * F32(DEG)
    sin_d = np.sin(dep)
    fres = 0.02 + 0.98 * (1.0 - sin_d) ** 5
    r = EYE_H / np.tan(dep)
    gx, gz = (r * np.sin(lonrD)).astype(F32), (r * np.cos(lonrD)).astype(F32)
    foot = EYE_H * (math.pi / H) / np.maximum(sin_d * sin_d, 1e-6)  # radialer Pixel-Fussabdruck (m)
    rip = noise.fbm((gx * F32(0.05), gz * F32(0.12), np.full_like(gx, 41.0)), 1.0, 3)
    jitter = (rip * 0.12 * np.clip(1.0 - foot / 30.0, 0, 1)).astype(F32)
    refl = sky_color(LOND, np.maximum(-LATD + jitter, 0.0), nz[D]).astype(F32)
    ra = np.ones((Hh, W), dtype=F32)
    refl, ra = paint(refl, ra, LATD - jitter, lambda o, la: 2 * o["base"] - la, True)
    refl = ndimage.gaussian_filter(refl, sigma=(1.2, 0.5, 0), mode=("nearest", "wrap", "nearest"))
    ra = ndimage.gaussian_filter(ra, sigma=(1.2, 0.5), mode=("nearest", "wrap"))
    water = C["water"][None, None, :] + refl * fres[..., None]
    w_alpha = ra * fres  # Spiegel-Staerke fuer Polarlicht/Sterne im Shader

    # Treibeis-Schollen in Bodenkoordinaten (perspektivisch korrekt)
    fn = noise.fbm((gx * F32(1 / 26.0), gz * F32(1 / 26.0), np.full_like(gx, 57.0)), 1.0, 5)
    fn2 = noise.fbm((gx * F32(1 / 260.0), gz * F32(1 / 260.0), np.full_like(gx, 63.0)), 1.0, 3)
    thr = 0.26 - 0.16 * fn2  # Dichte schwankt grossraeumig
    edge = np.maximum(0.015, foot / 26.0 * 0.6)
    floe = smoothstep(thr - edge, thr + edge, fn)
    far = np.clip(foot / 16.0, 0, 1)  # in der Ferne mittlere Bedeckung statt Flimmern
    cover = np.clip(0.22 - 0.40 * fn2, 0.04, 0.5)
    floe = floe * (1 - far) + cover * far * 0.6
    floe = floe * smoothstep(0.04, 0.6, -LATD) * smoothstep(-26.0, -9.0, LATD)  # Horizont/nah: Wasser
    front = np.exp(-(LOND / 14.0) ** 2) * smoothstep(-2.0, -8.0, LATD)
    floe = floe * (1 - 0.7 * front)  # unter der Strecke weniger Schollen
    fn3 = noise.fbm((gx * F32(1 / 9.0), gz * F32(1 / 9.0), np.full_like(gx, 71.0)), 1.0, 3)
    fcol = C["floe"] * (0.8 + 0.5 * np.clip(0.5 + fn3 * (1 - far), 0, 1))[..., None]
    fcol = fcol + C["floe_lit"] * (np.exp(LATD / 3.0) * 0.8)[..., None]  # Horizont-Schein
    water = water * (1 - floe)[..., None] + fcol * floe[..., None]
    w_alpha = w_alpha * (1 - floe)
    mist = np.exp(LATD / 0.9) * 0.55 + np.exp(LATD / 4.0) * 0.12  # kalter Dunst ueber dem Wasser
    water = (water * (1 - mist)[..., None] + C["haze"] * (mist * 0.9)[..., None]).astype(F32)
    w_alpha = w_alpha.astype(F32)
    # Eisberg-Unterteile unter dem Horizont direkt ueber das Wasser (dort keine Spiegelung)
    water, w_alpha = paint(water, w_alpha, latD[:, None], lambda o, la: la, False)
    fogd = np.exp(LATD / 0.6) * 0.5
    water = water * (1 - fogd)[..., None] + C["haze"] * (fogd * 0.85)[..., None]

    img = np.concatenate([imgU, water], 0)
    alpha = np.concatenate([visU, w_alpha], 0)
    LAT = np.broadcast_to(lat1[:, None], (H, W))
    # Lesbarkeit: vorn-unten (hinter Strecke/Noten) zusaetzlich abdunkeln.
    fd = np.exp(-(LON / 30.0) ** 2) * smoothstep(-1.0, -14.0, LAT)
    img = img * (1 - 0.55 * fd)[..., None]
    return img.astype(F32), alpha.astype(F32)


# ---------------------------------------------------------------------------
# Sterne (eigene Ebene, nur obere Halbkugel)
# ---------------------------------------------------------------------------
_BB = [(2800, "#ffb46b"), (3500, "#ffc489"), (4500, "#ffd9b0"), (5500, "#fff0e0"),
       (6500, "#fff8f5"), (8000, "#e8eeff"), (12000, "#cad8ff"), (35000, "#9db4ff")]
_BB_T = np.log([t for t, _ in _BB])
_BB_C = np.array([hexcol(c) for _, c in _BB])


def star_color(temp, sat):
    lt = np.log(np.clip(temp, 2800, 35000))
    c = np.stack([np.interp(lt, _BB_T, _BB_C[:, i]) for i in range(3)], -1)
    lum = (c * [0.2126, 0.7152, 0.0722]).sum(-1, keepdims=True)
    c = lum + (c - lum) * sat
    return np.clip(c / np.maximum(c.max(-1, keepdims=True), 1e-6), 0, 1)


def dir_to_px(d, W, H):
    lon = np.arctan2(d[..., 0], -d[..., 2])
    lat = np.arcsin(np.clip(d[..., 1], -1, 1))
    return (lon / (2 * math.pi) + 0.5) * W, (0.5 - lat / math.pi) * H


def deposit(img, d, rgb, W, H):
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


def star_layer(W, H, seed):
    rng = np.random.default_rng(seed + 100)
    img = np.zeros((H, W, 3), dtype=F32)
    sc = (W / 4096.0) ** 2
    n = int(15000 * sc) + 300
    v = rng.normal(size=(n, 3))
    v /= np.linalg.norm(v, axis=1, keepdims=True)
    v[:, 1] = np.abs(v[:, 1])  # nur obere Halbkugel
    m = np.log10(rng.uniform(1.0, 10 ** (0.36 * 9.0), n)) / 0.36
    flux = 10 ** (-0.4 * m * 0.72)
    temp = np.exp(rng.normal(math.log(7500), 0.30, n))
    rgb = star_color(temp, 0.10 + 0.20 * np.clip(flux / 0.2, 0, 1)[:, None]) * flux[:, None] * 0.8
    bright = flux > 0.2
    deposit(img, v[~bright], rgb[~bright] * 1.3, W, H)
    s = 0.6 * W / 4096.0 + 0.2
    img = ndimage.gaussian_filter(img, sigma=(s, s, 0), mode=("nearest", "wrap", "nearest")) * 2.2
    px = math.pi / 2048
    s_core = 0.62 * max(px, math.pi / H)
    order = np.argsort(-flux[bright])
    bd, bf, bc = v[bright][order], flux[bright][order], rgb[bright][order]
    for i in range(len(bd)):
        f = float(bf[i])
        col = bc[i] / max(f, 1e-6)
        sc_ = s_core * (1.0 + 0.9 * f)
        sh = px * (1.8 + 4.0 * f)
        sw = px * (5 + 18 * f * f)
        top = i < 8

        def prof(x, y, f=f, sc_=sc_, sh=sh, sw=sw, top=top):
            r2 = x * x + y * y
            val = 1.15 * f * np.exp(-r2 / (2 * sc_ * sc_))
            val += 0.06 * f * np.exp(-r2 / (2 * sh * sh))
            val += 0.018 * f * f * np.exp(-np.sqrt(r2) / sw)
            if top:
                ax = np.exp(-(y / (px * 0.55)) ** 2) * np.exp(-np.abs(x) / (px * 12))
                ay = np.exp(-(x / (px * 0.55)) ** 2) * np.exp(-np.abs(y) / (px * 12))
                val += 0.04 * f * (ax + ay)
            return val
        splat(img, bd[i], max(sw * 7, sh * 4, px * 4), prof, 0.7 * col + 0.3, W, H)
    return img


# ---------------------------------------------------------------------------
# Polarlicht-Vorhaenge (eigene Ebene, obere Halbkugel, 4096x1024)
# ---------------------------------------------------------------------------
CURTAINS = [
    # l0/l1: Laengen-Bereich (Grad), base: Unterrand (Grad ueber Horizont) + wave,
    # h: Hoehe, amp: Helligkeit, fold: Falten-Amplitude (Grad), rays: Strahlen-Kontrast
    dict(l0=-130, l1=120, base=7.0, wave=2.6, h=7.0, amp=1.0, fold=4.5, rays=0.55, z=1.0),
    dict(l0=-75, l1=165, base=3.0, wave=1.1, h=4.2, amp=0.50, fold=3.0, rays=0.45, z=2.0),
    dict(l0=-175, l1=35, base=15.0, wave=3.5, h=9.0, amp=0.30, fold=6.0, rays=0.5, z=3.0),
    dict(l0=105, l1=262, base=8.0, wave=2.8, h=7.5, amp=0.80, fold=5.0, rays=0.55, z=4.0),
    dict(l0=-45, l1=80, base=27.0, wave=5.0, h=12.0, amp=0.22, fold=8.0, rays=0.35, z=5.0),
]


def aurora_layer(W, seed):
    Ha = W // 4
    noise = Noise3(seed + 500)
    rows = int(Ha * 70 / 90)  # nur bis 70 Grad Hoehe
    lat = 90.0 * (1.0 - (np.arange(rows, dtype=F32) + 0.5) / Ha)  # Zeile -> Grad
    lat = lat[::-1].copy()  # Zeile 0 = Horizont (intern), spaeter zurueckdrehen
    acc = np.zeros((W, rows, 3), dtype=F32)
    spp = 4  # Stichproben je Pixelspalte
    for k, c in enumerate(CURTAINS):
        n = int((c["l1"] - c["l0"]) / 360.0 * W * spp)
        s = np.linspace(c["l0"], c["l1"], n, dtype=F32)  # Grad entlang des Vorhangs
        sr = s * F32(DEG)
        z = c["z"] * 10.0 + seed
        # Falten: Laengengrad nicht monoton -> helle, sich ueberlappende Falz-Kanten
        fold = (c["fold"] * noise.ring(sr, 9.0, 3, z=z)
                + 1.8 * c["fold"] * noise.ring(sr, 2.2, 3, z=z + 1))
        lon = s + fold
        base = (c["base"] + c["wave"] * noise.ring(sr, 1.8, 4, z=z + 2)
                + 0.45 * c["wave"] * noise.ring(sr, 5.0, 2, z=z + 7) + 0.12 * c["wave"] * noise.ring(sr, 16.0, 2, z=z + 8))
        base = np.maximum(base, 0.6)
        hgt = c["h"] * (0.75 + 0.5 * np.clip(0.5 + noise.ring(sr, 3.0, 3, z=z + 3), 0, 1))
        hgt = hgt * (0.55 + 0.45 * smoothstep(0.0, 14.0, base))  # tief = fern = flacher
        # Helligkeit: Huellkurve, grossraeumige Pulse, feine Strahlen
        t_env = (s - c["l0"]) / (c["l1"] - c["l0"])
        env = smoothstep(0.0, 0.18, t_env) * smoothstep(1.0, 0.82, t_env)
        big = np.clip(0.55 + 0.7 * noise.ring(sr, 4.0, 3, z=z + 4), 0.08, 1.4)
        ray_f = noise.ring(sr, 160.0, 3, z=z + 5, gain=0.6)
        ray_g = noise.ring(sr, 55.0, 2, z=z + 6)
        rays = np.clip(0.75 + 0.9 * ray_f + 0.3 * ray_g, 0.15, 1.6)
        rays = 1.0 + 0.3 * c["rays"] * (rays - 1.0)
        ray_len = np.clip(0.9 + 0.35 * ray_g + 0.15 * ray_f, 0.6, 1.3)
        I = c["amp"] * env * big * rays
        # Vertikalprofil je Stichprobe
        t = (lat[None, :] - base[:, None]) / hgt[:, None]  # (n, rows)
        edge_w = 0.22 / hgt[:, None]  # scharfer Unterrand (~0.22 Grad)
        lower = np.exp(-np.square(np.minimum(t, 0) / edge_w))
        L = ray_len[:, None]
        rise = 1.0 - np.exp(-np.maximum(t, 0) / 0.05)
        green = (0.35 + 0.65 * rise) * np.exp(-np.maximum(t, 0) / (0.36 * L)) * lower
        upper = 0.07 * np.exp(-np.square((t - 0.95 * L) / (0.55 * L))) * (t > 0)
        hot = np.exp(-np.square(t / (0.6 * edge_w + 0.025))) * 0.30  # heller Saum
        tt = np.clip(t / (1.4 * L), 0, 1)
        col = (green[..., None] * ramp([C["au_green"], C["au_green"], C["au_teal"], C["au_blue"]], tt)
               + upper[..., None] * ramp([C["au_teal"], C["au_blue"], C["au_violet"]], tt)
               + hot[..., None] * C["au_edge"])
        col *= (I / spp)[:, None, None]
        # Stichproben bilinear auf Spalten verteilen
        u = (wrap_deg(lon) / 360.0 + 0.5) * W - 0.5
        x0 = np.floor(u).astype(np.int64)
        fx = (u - x0).astype(F32)
        np.add.at(acc, x0 % W, col * (1 - fx)[:, None, None])
        np.add.at(acc, (x0 + 1) % W, col * fx[:, None, None])
    img = np.transpose(acc, (1, 0, 2))[::-1].copy()  # (rows, W, 3), Zeile 0 = oben
    full = np.zeros((Ha, W, 3), dtype=F32)
    full[Ha - rows:] = img
    sx = W / 4096.0
    full = ndimage.gaussian_filter(full, sigma=(0.6, 1.6 * sx, 0), mode=("nearest", "wrap", "nearest"))
    # weicher Schein (beleuchtet den Himmel um die Vorhaenge)
    glow = ndimage.gaussian_filter(full, sigma=(14 * sx, 26 * sx, 0), mode=("nearest", "wrap", "nearest"))
    glow2 = ndimage.gaussian_filter(full, sigma=(50 * sx, 90 * sx, 0), mode=("nearest", "wrap", "nearest"))
    out = full * 0.8 + glow * 0.6 + glow2 * 0.3
    # am Horizont weich auslaufen (Extinktion)
    la = 90.0 * (1.0 - (np.arange(Ha, dtype=F32) + 0.5) / Ha)
    ext = (0.25 + 0.75 * smoothstep(0.0, 6.0, la))[:, None, None]
    return (out * ext * 0.24).astype(F32)


# ---------------------------------------------------------------------------
# Ausgabe + Vorschau
# ---------------------------------------------------------------------------
def tonemap(lin, exposure=1.0):
    return 1 - np.exp(-lin * exposure)


def to_u8(lin, rng):
    s = lin_to_srgb(lin)
    s = s * 255.0 + rng.triangular(-0.5, 0, 0.5, s.shape)
    return np.clip(np.rint(s), 0, 255).astype(np.uint8)


def lin_alpha_u8(a, rng):
    s = np.sqrt(np.clip(a, 0, 1)) * 255.0 + rng.triangular(-0.5, 0, 0.5, a.shape)
    return np.clip(np.rint(s), 0, 255).astype(np.uint8)


def camera_view(pano, alpha, stars, aur, W, H, vw=960, vh=540, pitch=-16.0, fov=62.0, yaw=0.0):
    """Komposit wie der Shader (ohne Animation), Komfort-Kamera, fuer schnelle Kontrolle."""
    th = math.tan(math.radians(fov) * 0.5)
    ys, xs = np.mgrid[0:vh, 0:vw].astype(np.float64)
    x = (2 * (xs + 0.5) / vw - 1) * th * vw / vh
    y = (1 - 2 * (ys + 0.5) / vh) * th
    z = -np.ones_like(x)
    p = math.radians(pitch)
    y2 = y * math.cos(p) - z * math.sin(p)
    z2 = y * math.sin(p) + z * math.cos(p)
    yw = -math.radians(yaw)
    x3 = x * math.cos(yw) + z2 * math.sin(yw)
    z3 = -x * math.sin(yw) + z2 * math.cos(yw)
    d = np.stack([x3, y2, z3], -1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    u, v = dir_to_px(d, W, H)

    def samp(src, uu, vv, mode="grid-wrap"):
        return np.stack([ndimage.map_coordinates(src[..., c], [vv - 0.5, uu - 0.5], order=1, mode=mode)
                         for c in range(src.shape[-1])], -1)
    col = samp(pano, u, v)
    a = samp(alpha[..., None], u, v)[..., 0]
    up = d[..., 1] >= 0
    st = samp(stars, u, v) * np.clip(d[..., 1] / 0.05, 0, 1)[..., None]
    va = np.clip(np.where(up, v, H - v) * 2.0 * (aur.shape[0] / H), 0, aur.shape[0] - 0.01)
    au = samp(aur, u, va, mode="nearest")
    col = col + (st + au) * a[..., None]
    return col


def save_rgb(path, lin, rng, alpha=None):
    enc = to_u8(np.sqrt(np.clip(tonemap(lin), 0, 1)), rng)
    if alpha is not None:
        enc = np.dstack([enc, lin_alpha_u8(alpha, rng)])
        Image.fromarray(enc).save(path, "WEBP", quality=92, method=6, alpha_quality=100, exact=True)
    else:
        Image.fromarray(enc).save(path, "WEBP", quality=90, method=6)


def load_lin(path):
    im = np.asarray(Image.open(path), dtype=np.float64) / 255.0
    rgb = srgb_to_lin(im[..., :3]) ** 2
    a = im[..., 3] ** 2 if im.shape[-1] == 4 else None
    return rgb, a


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--width", type=int, default=4096)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default="", help="Ordner fuer Kamera-/Panorama-PNGs")
    a = ap.parse_args()
    W = a.width
    H = W // 2
    t0 = time.time()
    rng = np.random.default_rng(a.seed + 9)
    os.makedirs(a.out, exist_ok=True)
    pa = os.path.join(a.out, "aurora.webp")
    pb = os.path.join(a.out, "aurora_stars.webp")
    pc = os.path.join(a.out, "aurora_aurora.webp")
    img, alpha = scene(W, H, a.seed * 1000 + 7)
    save_rgb(pa, img, rng, alpha)
    print("scene %.1f s" % (time.time() - t0), flush=True)
    save_rgb(pb, star_layer(W, H, a.seed * 1000 + 7), rng)
    print("stars %.1f s" % (time.time() - t0), flush=True)
    save_rgb(pc, aurora_layer(W, a.seed * 1000 + 7), rng)
    print("aurora %.1f s" % (time.time() - t0), flush=True)
    for p in (pa, pb, pc):
        print("  %s %.2f MB" % (os.path.basename(p), os.path.getsize(p) / 1e6))
    if a.preview:
        os.makedirs(a.preview, exist_ok=True)
        pano, al = load_lin(pa)
        st, _ = load_lin(pb)
        au, _ = load_lin(pc)
        for name, kw in (("cam", {}), ("cam_up", dict(pitch=8.0, fov=75.0)),
                         ("cam_left", dict(yaw=-60.0, pitch=-4.0)), ("cam_back", dict(yaw=180.0, pitch=-4.0))):
            view = camera_view(pano, al, st, au, W, H, **kw)
            Image.fromarray(to_u8(np.clip(view, 0, 1), rng)).save(os.path.join(a.preview, "%s.png" % name))
        comp = pano.copy()
        Image.fromarray(to_u8(np.clip(comp, 0, 1), rng)).resize((2048, 1024), Image.LANCZOS).save(
            os.path.join(a.preview, "pano.png"))
        Image.fromarray(to_u8(np.clip(au * 3.0, 0, 1), rng)).resize((2048, 512), Image.LANCZOS).save(
            os.path.join(a.preview, "aurora_layer.png"))


if __name__ == "__main__":
    main()
