#!/usr/bin/env python3
"""TETHRA Welt-Thema "Nerv": ein unendliches Netz schwarzer Fasern, Synapsen-Impulse in Bordeaux.

Erzeugt in assets_game/themes/nerve/ fuenf Texturen (8192x4096, WebP):
  nerve_sky.webp     Panorama (RGB): dunkler Dunst, Bordeaux-Nebel, ferne unscharfe Fasernetze.
  nerve_net.webp     RGBA mittlere Ebene: duenne schwarze Fasern, RGB = Kantenlicht (nur die
                     dem Licht zugewandte Seite), A = Deckkraft (ueberabgetastet, gefiltert).
  nerve_pulse.webp   DATEN (nicht sRGB, deckungsgleich mit nerve_net): R/G = 0.5+0.5*cos/sin der
                     Bogenlaenge entlang der Faser (Periode PERIOD px, mip-sicher, kein Sprung),
                     B = Faser-Hash (Gate/Richtung/Versatz der Impulse), A = Synapsenknoten.
  nerve_near.webp    RGBA nahe Ebene: dicke Faserbuendel + Ganglien mit Rundungs-Schattierung.
  nerve_spores.webp  Panorama (RGB): schwebende Sporen.

RGB-Kanaele (ausser pulse) wurzel-kodiert wie sky_panorama (linear = pow(tex, 2)).
Reproduzierbar per Seed:
  python tools/gen_theme_nerve.py                      # 8192x4096, Seed 0
  python tools/gen_theme_nerve.py --width 2048 --preview <ordner>
"""
import argparse
import math
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_skybox import smoothstep, hexcol, to_u8, lin_to_srgb  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
F32 = np.float32
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets_game", "themes", "nerve")

# Farbsatz: Bordeaux + gedecktes Rosegrau auf Schwarz (kein Neon).
GREY = hexcol("#6c5a60").astype(F32)     # Dunst
BORD = hexcol("#7a1a2e").astype(F32)     # Nebel, Knoten
RIM = hexcol("#a98790").astype(F32)      # Kantenlicht der Fasern
# Licht von links oben (Bildkoordinaten x rechts, y unten): Richtung ZUR Lichtquelle.
LDIR = np.array([-0.55, -0.83], F32)
LDIR /= np.linalg.norm(LDIR)
PERIOD = 520.0  # Impuls-Periode in Texeln bei Breite 8192 (skaliert mit W)


def noise(rng, H, W, gh, gw):
    g = rng.standard_normal((gh, gw)).astype(F32)
    z = ndimage.zoom(g, (H / gh, W / gw), order=3, mode="grid-wrap")
    return z[:H, :W].astype(F32)


def fbm(rng, H, W, gh, gw, octaves=5, gain=0.55):
    acc = np.zeros((H, W), F32)
    amp, tot = 1.0, 0.0
    for _ in range(octaves):
        acc += amp * noise(rng, H, W, gh, gw)
        tot += amp * amp
        amp *= gain
        gh, gw = gh * 2, gw * 2
    return acc / math.sqrt(tot)


def pano_grid(W, H):
    lon = ((np.arange(W, dtype=F32) + 0.5) / W - 0.5) * (2 * math.pi)
    lat = (0.5 - (np.arange(H, dtype=F32) + 0.5) / H) * math.pi
    return lon[None, :], lat[:, None]


def enc_rgb(lin, rng, dither=True):
    """linear -> wurzel-kodiert -> sRGB 8 Bit (Godot source_color + Quadrieren im Shader)."""
    s = np.sqrt(np.clip(lin, 0, 1))
    if dither:
        return to_u8(s, rng)
    return np.clip(np.rint(lin_to_srgb(s) * 255.0), 0, 255).astype(np.uint8)


def save_webp(path, arr, lossless=False, quality=96):
    im = Image.fromarray(arr)
    if lossless:
        im.save(path, "WEBP", lossless=True, exact=True, quality=100, method=4)
    else:
        im.save(path, "WEBP", quality=quality, method=6)


# ---------------------------------------------------------------------------
# Netz-Geometrie: Knoten auf der Kugel (gleichmaessiger Winkelabstand), Kanten als Kurven.
# ---------------------------------------------------------------------------
def make_nodes(rng, spacing, lat_min, lat_max, jitter=0.38):
    rows = []
    lats = np.arange(lat_min, lat_max + 1e-6, spacing)
    for i, la in enumerate(lats):
        c = max(math.cos(math.radians(la)), 0.4)
        n = max(int(360.0 / (spacing / c)), 6)
        lons = (np.arange(n) + (0.5 if i % 2 else 0.0) + rng.uniform(-jitter, jitter, n)) * (360.0 / n) - 180.0
        las = la + rng.uniform(-jitter, jitter, n) * spacing
        rows.append(np.stack([lons, las], 1))
    return rows


def make_edges(rng, rows, p_row=0.9, p_cross=(0.95, 0.55)):
    """Kanten (lon0,lat0,lon1,lat1) in Grad; lon1 so gewaehlt, dass |lon1-lon0| <= 180."""
    edges = []
    for i, r in enumerate(rows):
        n = len(r)
        for j in range(n):
            if rng.random() < p_row:
                a, b = r[j], r[(j + 1) % n]
                edges.append((a[0], a[1], a[0] + ((b[0] - a[0] + 180) % 360 - 180), b[1]))
        if i + 1 < len(rows):
            nx = rows[i + 1]
            for j in range(n):
                d = np.abs((nx[:, 0] - r[j, 0] + 180) % 360 - 180)
                order = np.argsort(d)[:2]
                for k, o in enumerate(order):
                    if rng.random() < p_cross[k]:
                        b = nx[o]
                        edges.append((r[j, 0], r[j, 1], r[j, 0] + ((b[0] - r[j, 0] + 180) % 360 - 180), b[1]))
    return edges


def curve(rng, p0, p1, step, bend=0.22, wobble=0.035):
    """Kubische Bezier-Kurve p0->p1 mit seitlichem Ausbauchen und feinem Wackeln. Gibt (N,2) zurueck."""
    d = p1 - p0
    L = float(np.hypot(*d)) + 1e-6
    nrm = np.array([-d[1], d[0]]) / L
    c1 = p0 + d * 0.33 + nrm * rng.normal(0, bend) * L
    c2 = p0 + d * 0.67 + nrm * rng.normal(0, bend) * L
    n = max(int(L / step), 6)
    t = np.linspace(0.0, 1.0, n)[:, None]
    pts = ((1 - t) ** 3) * p0 + 3 * ((1 - t) ** 2) * t * c1 + 3 * (1 - t) * t * t * c2 + t ** 3 * p1
    k = rng.integers(2, 6)
    ph = rng.uniform(0, 6.28)
    pts = pts + nrm * (np.sin(t[:, 0] * 6.283 * k + ph) * wobble * L * np.sin(math.pi * t[:, 0]))[:, None]
    return pts


class Canvas:
    """Zeichnet Faserzuege in mehrere Bilder gleichzeitig (Masken ueberabgetastet, Daten nicht)."""

    def __init__(self, W, H, ss=2):
        self.W, self.H, self.ss = W, H, ss
        self.mask = Image.new("L", (W * ss, H * ss), 0)
        self.dm = ImageDraw.Draw(self.mask)

    def to_px(self, lon, lat):
        return np.array([(lon + 180.0) / 360.0 * self.W, (90.0 - lat) / 180.0 * self.H])

    def stroke(self, pts, widths, phase_img=None, color=None, dil=0.0, s0=0.0, period=PERIOD):
        """pts (N,2) Pixel, widths (N,) Pixel. phase_img: ImageDraw (nativ) mit Phase aus Bogenlaenge."""
        W, ss = self.W, self.ss
        seg = np.hypot(*np.diff(pts, axis=0).T)
        s = s0 + np.concatenate([[0], np.cumsum(seg)])
        for off in (-W, 0, W):
            xs = pts[:, 0] + off
            if xs.max() < -40 or xs.min() > W + 40:
                continue
            for i in range(len(pts) - 1):
                x0, y0, x1, y1 = xs[i], pts[i, 1], xs[i + 1], pts[i + 1, 1]
                w = float(widths[i])
                self.dm.line([(x0 * ss, y0 * ss), (x1 * ss, y1 * ss)], fill=255, width=max(int(round(w * ss)), 1))
                r = w * ss * 0.5
                self.dm.ellipse([x0 * ss - r, y0 * ss - r, x0 * ss + r, y0 * ss + r], fill=255)
                if phase_img is not None:
                    ph = (s[i] / period) * 6.2831853
                    col = (int(round(127.5 + 127.5 * math.cos(ph))), int(round(127.5 + 127.5 * math.sin(ph))), color)
                    wd = max(int(round(w + dil)), 1)
                    phase_img.line([(x0, y0), (x1, y1)], fill=col, width=wd)
                    rr = wd * 0.5
                    phase_img.ellipse([x0 - rr, y0 - rr, x0 + rr, y0 + rr], fill=col)
        return s[-1]

    def coverage(self):
        m = self.mask.reduce(self.ss) if self.ss > 1 else self.mask
        return np.asarray(m, dtype=F32) / 255.0


def width_profile(n, w_mid, w_end, rng):
    """Faser: dick an den Knoten, duenn in der Mitte (Axon-Anschwellung) + leichte Unruhe."""
    t = np.linspace(0, 1, n)
    base = w_mid + (w_end - w_mid) * (np.abs(2 * t - 1) ** 3)
    base = base * (1.0 + 0.12 * np.sin(t * 6.283 * rng.integers(2, 7) + rng.uniform(0, 6.28)))
    return np.maximum(base, 0.6)


def light_rim(cov, r, gain):
    """Kantenlicht nur auf der dem Licht zugewandten Seite (Versatz r Pixel zur Lichtquelle)."""
    sh = ndimage.shift(cov, (LDIR[1] * r, LDIR[0] * r), order=1, mode="grid-wrap")
    return np.clip(cov - sh, 0, 1) * gain


# ---------------------------------------------------------------------------
# Ferne: Dunst + Nebel + unscharfe Fasernetze
# ---------------------------------------------------------------------------
def far_layer(W, H, seed):
    S = W / 8192.0
    rng = np.random.default_rng(seed)
    lon, lat = pano_grid(W, H)
    band = smoothstep(-0.30, 0.18, lat) * (0.55 + 0.45 * np.exp(-((lat - 0.55) / 0.55) ** 2))
    n1 = fbm(rng, H, W, 4, 16, 6, 0.58)
    n2 = fbm(rng, H, W, 2, 8, 4, 0.6)
    n3 = fbm(rng, H, W, 8, 32, 5, 0.55)
    dens = np.clip(0.55 + 0.34 * n1 + 0.22 * n2, 0, None) ** 1.7
    hue = smoothstep(-0.3, 0.6, n2 + 0.5 * n1)  # 0 grau -> 1 bordeaux
    haze = 0.095 * band * dens * (0.75 + 0.25 * n3.clip(-1, 1))
    col = (GREY[None, None, :] * (1 - hue[..., None]) + BORD[None, None, :] * 0.85 * hue[..., None]) * haze[..., None]
    col += 0.0012 * (0.6 + 0.4 * n2.clip(-1, 1))[..., None] * GREY[None, None, :]
    # ferne Fasernetze: zwei Tiefen, schwarz vor dem Dunst, unscharf
    for k, (spacing, wd, blur, depth) in enumerate([(7.5, 2.6, 2.4, 0.55), (5.0, 1.7, 1.2, 0.85)]):
        cv = Canvas(W, H, 2)
        rows = make_nodes(rng, spacing, -35, 70)
        for e in make_edges(rng, rows, 0.8, (0.9, 0.45)):
            p0, p1 = cv.to_px(e[0], e[1]), cv.to_px(e[2], e[3])
            pts = curve(rng, p0, p1, 6.0 * S)
            cv.stroke(pts, width_profile(len(pts), wd * S, wd * 2.2 * S, rng))
        cov = cv.coverage()
        del cv
        cov = ndimage.gaussian_filter(cov, blur * S)
        # Tiefenfade: Fasern nach oben zum Himmel hin dichter sichtbar, unten verloren
        cov *= 0.4 + 0.6 * smoothstep(-0.1, 0.45, lat)
        col *= (1.0 - depth * np.clip(cov * 1.4, 0, 1))[..., None]
        # weiche Kantenlichter der Ferne
        col += light_rim(cov, 2.0 * S + 0.5, 0.020 * depth)[..., None] * RIM[None, None, :] * (0.4 + 2.0 * haze[..., None] / 0.095)
    # Bordeaux-Kern: wenige weiche Glutnester (Synapsen-Cluster) im Dunst
    for _ in range(14):
        c_lon = rng.uniform(-math.pi, math.pi)
        c_lat = rng.uniform(0.05, 0.85)
        sx = rng.uniform(0.05, 0.14)
        sy = sx * rng.uniform(0.5, 0.9)
        dl = (lon - c_lon + math.pi) % (2 * math.pi) - math.pi
        g = np.exp(-(dl * np.cos(c_lat) / sx) ** 2 - ((lat - c_lat) / sy) ** 2)
        col += 0.016 * rng.uniform(0.5, 1.0) * g[..., None] * BORD[None, None, :] * (0.7 + 0.3 * n3.clip(-1, 1))[..., None]
    col *= (1.0 - 0.75 * np.exp(-(lon / 0.62) ** 2) * smoothstep(0.22, -0.30, lat))[..., None]
    return col.astype(F32), rng


# ---------------------------------------------------------------------------
# Mittlere Ebene: Netz mit Impuls-Daten
# ---------------------------------------------------------------------------
def net_layer(W, H, seed):
    S = W / 8192.0
    rng = np.random.default_rng(seed + 101)
    cv = Canvas(W, H, 2)
    pimg = Image.new("RGB", (W, H), (128, 128, 0))
    pd = ImageDraw.Draw(pimg)
    nodeimg = Image.new("L", (W, H), 0)
    nd = ImageDraw.Draw(nodeimg)
    rows = make_nodes(rng, 8.5, -40, 72)
    edges = make_edges(rng, rows, 0.88, (0.97, 0.6))
    for e in edges:
        p0, p1 = cv.to_px(e[0], e[1]), cv.to_px(e[2], e[3])
        pts = curve(rng, p0, p1, 4.0 * S)
        wd = rng.uniform(1.9, 3.4) * S
        wprof = width_profile(len(pts), wd, wd * 2.1, rng)
        h = rng.random()
        cv.stroke(pts, wprof, pd, int(h * 255), dil=4.0 * S, s0=rng.uniform(0, PERIOD * S), period=PERIOD * S)
        # Verzweigungen: feine Haar-Fasern aus der Mitte
        if rng.random() < 0.55:
            k = rng.integers(len(pts) // 4, 3 * len(pts) // 4)
            tgt = pts[k] + rng.normal(0, 1, 2) * rng.uniform(25, 80) * S
            hp = curve(rng, pts[k], tgt, 3.0 * S, 0.3, 0.05)
            cv.stroke(hp, width_profile(len(hp), 0.9 * S, 1.2 * S, rng), pd, int(h * 255), dil=3.0 * S,
                      s0=rng.uniform(0, PERIOD * S), period=PERIOD * S)
    # Synapsenknoten: Verdickung (Schwarz) + Glut-Maske
    for r_ in rows:
        for lo, la in r_:
            c = cv.to_px(lo, la)
            rad = rng.uniform(5.5, 10.0) * S
            for off in (-W, 0, W):
                x = c[0] + off
                if -20 < x < W + 20:
                    cv.dm.ellipse([(x - rad) * 2, (c[1] - rad) * 2, (x + rad) * 2, (c[1] + rad) * 2], fill=255)
                    nd.ellipse([x - rad * 0.7, c[1] - rad * 0.7, x + rad * 0.7, c[1] + rad * 0.7], fill=255)
                    pd.ellipse([x - rad - 2, c[1] - rad - 2, x + rad + 2, c[1] + rad + 2], fill=(128, 128, 0))
    cov = cv.coverage()
    del cv
    nodes = ndimage.gaussian_filter(np.asarray(nodeimg, dtype=F32) / 255.0, 1.4 * S + 0.3)
    del nodeimg
    rim = light_rim(cov, 1.6 * S + 0.6, 1.0)
    lin = rim[..., None] * RIM[None, None, :] * 0.16 + 0.0008 * cov[..., None]
    return lin.astype(F32), cov, pimg, nodes, rng


# ---------------------------------------------------------------------------
# Nahe Ebene: dicke Buendel + Ganglien
# ---------------------------------------------------------------------------
def near_layer(W, H, seed):
    S = W / 8192.0
    rng = np.random.default_rng(seed + 202)
    cv = Canvas(W, H, 2)
    rows = make_nodes(rng, 26.0, -22, 62, 0.42)
    edges = make_edges(rng, rows, 0.75, (0.85, 0.35))
    for e in edges:
        p0, p1 = cv.to_px(e[0], e[1]), cv.to_px(e[2], e[3])
        pts = curve(rng, p0, p1, 8.0 * S, 0.2, 0.05)
        base = rng.uniform(15, 30) * S
        wp = width_profile(len(pts), base, base * 1.5, rng)
        cv.stroke(pts, wp)
        # umwickelnde Nebenstraenge
        for _ in range(rng.integers(1, 3)):
            sh = curve(rng, pts[0], pts[-1], 8.0 * S, 0.2, 0.05)
            n = min(len(sh), len(pts))
            sh = sh[:n] * 0.5 + pts[:n] * 0.5 + np.stack([np.sin(np.linspace(0, 12, n)) * base, np.cos(np.linspace(0, 12, n)) * base], 1) * 0.6
            cv.stroke(sh, width_profile(n, base * 0.32, base * 0.4, rng))
    # Ganglien: unregelmaessige Knollen an den Knoten
    for r_ in rows:
        for lo, la in r_:
            if rng.random() < 0.55:
                c = cv.to_px(lo, la)
                for _ in range(rng.integers(3, 6)):
                    rad = rng.uniform(26, 58) * S
                    o = rng.normal(0, 18, 2) * S
                    for off in (-W, 0, W):
                        x = c[0] + off + o[0]
                        if -80 < x < W + 80:
                            cv.dm.ellipse([(x - rad) * 2, (c[1] + o[1] - rad * 0.85) * 2, (x + rad) * 2, (c[1] + o[1] + rad * 0.85) * 2], fill=255)
    cov = cv.coverage()
    del cv
    # Rundungs-Schattierung aus einer Hoehenkarte: weich geblurrte Deckkraft
    h1 = ndimage.gaussian_filter(cov, 9.0 * S)
    h2 = ndimage.gaussian_filter(cov, 3.0 * S)
    h = 0.6 * h1 + 0.4 * h2
    gy, gx = np.gradient(h)
    lit = -(gx * LDIR[0] + gy * LDIR[1]) * (28.0 / S)  # Hang zur Lichtquelle
    lit = np.clip(lit, 0, 1) ** 1.3
    # fibroese Oberflaeche: horizontal gestreckter Noise moduliert das Licht
    grain = fbm(rng, H, W, 64, 16, 4, 0.55)
    grain = 0.65 + 0.35 * np.clip(grain, -1.5, 1.5) / 1.5
    rimL = light_rim(cov, 3.5 * S + 0.5, 1.0)
    shade = (0.75 * lit + 0.9 * rimL) * grain
    lin = shade[..., None] * RIM[None, None, :] * 0.10 + 0.0010 * cov[..., None]
    return lin.astype(F32), cov, rng


# ---------------------------------------------------------------------------
# Sporen
# ---------------------------------------------------------------------------
def spore_layer(W, H, seed):
    S = W / 8192.0
    rng = np.random.default_rng(seed + 303)
    img = np.zeros((H, W, 3), F32)
    n = int(26000 * S * S * 4)
    lat = np.arcsin(rng.uniform(-0.93, 0.93, n))  # gleichmaessig auf der Kugel
    lon = rng.uniform(-math.pi, math.pi, n)
    x = (lon / (2 * math.pi) + 0.5) * W
    y = (0.5 - lat / math.pi) * H
    amp = rng.uniform(0.04, 0.35, n) ** 1.6 * 2.2
    pick = rng.random(n) < 0.35
    colr = np.where(pick[:, None], BORD[None, :] * 1.3, RIM[None, :] * 0.8).astype(F32)
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    for dx, dy, w in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
        np.add.at(img, ((y0 + dy).clip(0, H - 1), (x0 + dx) % W), (colr * (amp * w)[:, None]).astype(F32))
    # wenige groessere, weiche Sporen mit Hof
    for _ in range(int(380 * S * 1.5)):
        la = math.asin(rng.uniform(-0.8, 0.9))
        lo = rng.uniform(-math.pi, math.pi)
        cx = (lo / (2 * math.pi) + 0.5) * W
        cy = (0.5 - la / math.pi) * H
        r = rng.uniform(2.0, 5.0) * S
        R = int(r * 4) + 2
        yy, xx = np.mgrid[-R:R + 1, -R:R + 1].astype(F32)
        g = np.exp(-(xx ** 2 + yy ** 2) / (r * r)) * rng.uniform(0.12, 0.4)
        g += 0.05 * np.exp(-(xx ** 2 + yy ** 2) / (r * r * 5))
        c = BORD * 1.2 if rng.random() < 0.4 else RIM * 0.9
        ys = (int(cy) + np.arange(-R, R + 1)).clip(0, H - 1)
        xs = (int(cx) + np.arange(-R, R + 1)) % W
        img[np.ix_(ys, xs)] += g[..., None] * c[None, None, :]
    img *= (1.0 - 0.9 * np.exp(-(((np.arange(W, dtype=F32) + 0.5) / W - 0.5) * 2 * math.pi / 0.62) ** 2)[None, :, None]
            * smoothstep(0.22, -0.30, (0.5 - (np.arange(H, dtype=F32) + 0.5) / H) * math.pi)[:, None, None])
    return img, rng


# ---------------------------------------------------------------------------
def build(W, seed, out_dir, preview):
    H = W // 2
    os.makedirs(out_dir, exist_ok=True)
    t0 = time.time()
    rng_e = np.random.default_rng(0)
    far, _ = far_layer(W, H, seed)
    save_webp(os.path.join(out_dir, "nerve_sky.webp"), enc_rgb(far, rng_e), quality=96)
    print("far %.0fs" % (time.time() - t0))
    if preview:
        os.makedirs(preview, exist_ok=True)
        Image.fromarray(enc_rgb(far[::2, ::2], rng_e)).resize((1024, 512)).save(os.path.join(preview, "nerve_far.png"))
    del far

    lin, cov, pimg, nodes, _ = net_layer(W, H, seed)
    rgba = np.dstack([enc_rgb(lin, rng_e, False), np.clip(np.rint(cov * 255), 0, 255).astype(np.uint8)])
    save_webp(os.path.join(out_dir, "nerve_net.webp"), rgba, lossless=True)
    pa = np.asarray(pimg).copy()
    pdat = np.dstack([pa, np.clip(np.rint(nodes * 255), 0, 255).astype(np.uint8)])
    save_webp(os.path.join(out_dir, "nerve_pulse.webp"), pdat, lossless=True)
    print("net %.0fs" % (time.time() - t0))
    if preview:
        Image.fromarray(rgba[::2, ::2]).resize((1024, 512)).save(os.path.join(preview, "nerve_net.png"))
    del lin, cov, pimg, nodes, rgba, pdat, pa

    lin, cov, _ = near_layer(W, H, seed)
    rgba = np.dstack([enc_rgb(lin, rng_e, False), np.clip(np.rint(cov * 255), 0, 255).astype(np.uint8)])
    save_webp(os.path.join(out_dir, "nerve_near.webp"), rgba, lossless=True)
    print("near %.0fs" % (time.time() - t0))
    if preview:
        Image.fromarray(rgba[::2, ::2]).resize((1024, 512)).save(os.path.join(preview, "nerve_near.png"))
    del lin, cov, rgba

    sp, _ = spore_layer(W, H, seed)
    save_webp(os.path.join(out_dir, "nerve_spores.webp"), enc_rgb(sp, rng_e), quality=92)
    print("spores %.0fs" % (time.time() - t0))
    for f in sorted(os.listdir(out_dir)):
        if f.endswith(".webp"):
            print("%s %.2f MB" % (f, os.path.getsize(os.path.join(out_dir, f)) / 1e6))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=8192)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    build(a.width, a.seed, a.out, a.preview)


if __name__ == "__main__":
    main()
