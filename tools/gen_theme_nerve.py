#!/usr/bin/env python3
"""TETHRA Welt-Thema "Nerve": organisch-abstraktes, unendliches Netz schwarzer Fasern;
Synapsen-Impulse in dunklem Bordeaux laufen im Takt durch das Netz.

Erzeugt in assets_game/themes/nerve/ (8192x4096, WebP):
  sky_nerve.webp         Panorama RGBA, DATEN-Kodierung: R = Kantenlicht (wurzel-kodiert,
                         linear = pow(tex, 2)), G = Impuls-Phase entlang der Faser (0..1 Saege-
                         zahn, Laenge ~29 Grad, je Faser anderer Versatz; linear kodiert, der
                         Shader laesst Impulse per beat_step ueber die Phase laufen),
                         B = Faserkern-Gewicht (linear), A = Deckung (schwarze Faser).
  sky_nerve_haze.webp    Panorama RGB: dunkler Bordeaux-Dunst hinter dem Netz (Farbe).
  sky_nerve_rows.webp    Tunnel-Textur RGBA (u = Winkel, v = ln(tan(a/2))/ln 4): runde
                         Zellkoerper, Reihen rasten per beat_step.
  sky_nerve_prisms.webp  nahe Ebene RGBA (Panorama): Faser-Knoten mit Auslaeufern.
  sky_nerve_stars.webp   Sporen/Staub (Panorama).
  python tools/gen_theme_nerve.py [--width 8192]
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
from gen_skybox import hexcol, to_u8, smoothstep, lin_to_srgb  # noqa: E402
import gen_theme_monolith as M  # noqa: E402

F32 = np.float32
OUT_DIR = os.path.join(M.ROOT, "assets_game", "themes", "nerve")
RIMC = hexcol("#b49aa6").astype(F32)      # Kantenlicht (grau mit Bordeaux-Hauch)
HAZEC = hexcol("#7a1030").astype(F32)     # Bordeaux-Dunst
LIGHT = np.array([-0.55, 0.83]) / np.linalg.norm([-0.55, 0.83])
LAMBDA = 0.50                              # Phasenlaenge in Radiant (~29 Grad)


def bez(p0, c, p1, n):
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * c + t ** 2 * p1


def emboss(cover, d):
    """Kantenlicht: Deckung dort, wo die Kante zur Lichtquelle (oben links) zeigt."""
    sh = np.roll(cover, (int(round(-LIGHT[1] * d)), int(round(LIGHT[0] * d))), axis=(0, 1))
    return np.clip(cover - sh, 0, 1)


def net_layer(W, H, seed):
    rng = np.random.default_rng(seed + 5)
    k = W / 4096.0
    cov = Image.new("L", (W, H), 0)
    core = Image.new("L", (W, H), 0)
    ph = Image.new("L", (W, H), 0)
    dc, dk, dp = ImageDraw.Draw(cov), ImageDraw.Draw(core), ImageDraw.Draw(ph)

    def px(p):
        return ((p[0] / (2 * math.pi) + 0.5) * W % W, (0.5 - p[1] / math.pi) * H)

    # Knoten: oben (lat 6..62 Grad) und seitlich (|lon| > 55 Grad auch tiefer)
    nodes = []
    for _ in range(95):
        lon = rng.uniform(-math.pi, math.pi)
        lat = rng.uniform(0.10, 1.05) if abs(lon) < 1.0 else rng.uniform(-0.45, 1.05)
        nodes.append(np.array([lon, lat]))
    nodes = np.array(nodes)

    def dist(a, b):
        dl = (a[0] - b[0] + math.pi) % (2 * math.pi) - math.pi
        return math.hypot(dl * math.cos(0.5 * (a[1] + b[1])), a[1] - b[1])

    edges = set()
    for i, a in enumerate(nodes):
        ds = sorted(range(len(nodes)), key=lambda j: dist(a, nodes[j]))[1:4]
        for j in ds:
            edges.add((min(i, j), max(i, j)))

    def fiber(a, b, wmax, off, bend=0.28):
        dl = (b[0] - a[0] + math.pi) % (2 * math.pi) - math.pi
        b2 = np.array([a[0] + dl, b[1]])
        mid = (a + b2) / 2
        nrm = np.array([-(b2[1] - a[1]), dl])
        nrm /= (np.linalg.norm(nrm) + 1e-9)
        c = mid + nrm * rng.normal(0, bend) * np.linalg.norm(b2 - a)
        n = max(24, int(np.linalg.norm(b2 - a) / 0.004))
        pts = bez(a, c, b2, n)
        s = 0.0
        for i in range(n - 1):
            t = i / (n - 1)
            w = wmax * (0.45 + 0.55 * math.sin(math.pi * t) ** 0.5) * (0.85 + 0.15 * math.sin(i * 0.21))
            s += np.linalg.norm(pts[i + 1] - pts[i])
            ph_v = int(((off + s / LAMBDA) % 1.0) * 255)
            seg = [px(pts[i]), px(pts[i + 1])]
            if abs(seg[0][0] - seg[1][0]) > W / 2:
                continue
            dc.line(seg, fill=255, width=max(2, int(w * k)))
            dk.line(seg, fill=255, width=max(1, int(w * k * 0.35)))
            dp.line(seg, fill=ph_v, width=max(2, int(w * k)))
        return pts

    for (i, j) in edges:
        fiber(nodes[i], nodes[j], rng.uniform(5, 11), rng.random())
    # Haarfasern: kleine Verzweigungen entlang der Hauptfasern
    for _ in range(260):
        a = nodes[rng.integers(len(nodes))] + rng.normal(0, 0.06, 2)
        ang = rng.uniform(0, 6.3)
        b = a + rng.uniform(0.04, 0.16) * np.array([math.cos(ang), math.sin(ang)])
        fiber(a, b, rng.uniform(1.8, 3.8), rng.random(), 0.4)
    for p in nodes:   # Knotenverdickung
        r = rng.uniform(7, 17) * k
        x, y = px(p)
        dc.ellipse([x - r, y - r * 0.8, x + r, y + r * 0.8], fill=255)
        dk.ellipse([x - r * 0.45, y - r * 0.36, x + r * 0.45, y + r * 0.36], fill=255)
        dp.ellipse([x - r, y - r * 0.8, x + r, y + r * 0.8], fill=int(rng.random() * 255))
    lon, lat = M.pano_grid(W, H)
    fd = M.front_dark(lon, lat)
    cover = ndimage.gaussian_filter(np.asarray(cov, dtype=F32) / 255.0, 0.9 * k) * 1.0
    cover = np.clip(cover * 1.15, 0, 1)
    corew = ndimage.gaussian_filter(np.asarray(core, dtype=F32) / 255.0, 0.8 * k)
    phase = np.asarray(ph, dtype=F32) / 255.0
    rim = ndimage.gaussian_filter(emboss(cover, 2.2 * k), 0.5 * k)
    rim = rim * (0.35 + 0.65 * fd) * fd
    # Vorn-mitte/unten: Netz ausblenden (Strecke), weich
    cover *= smoothstep(0.0, 0.5, fd)
    corew *= fd
    return rim, phase, corew, cover, rng


def haze_layer(W, H, seed):
    rng = np.random.default_rng(seed + 9)
    lon, lat = M.pano_grid(W, H)
    band = np.exp(-((lat - 0.35) / 0.55) ** 2)
    n1 = M.fbm(rng, H, W, 5, 20, 6, 0.55)
    n2 = M.fbm(rng, H, W, 3, 8, 4, 0.6)
    dens = np.clip(0.55 + 0.32 * n1 + 0.2 * n2, 0, None) ** 1.5
    h = band * dens * 0.10 + 0.004
    h *= smoothstep(-0.55, 0.0, lat) * M.front_dark(lon, lat)
    return np.clip(h[..., None] * HAZEC[None, None, :], 0, 1), rng


def knots_layer(W, H, seed):
    rng = np.random.default_rng(seed + 61)
    k = W / 4096.0
    cov = Image.new("L", (W, H), 0)
    dc = ImageDraw.Draw(cov)
    for i in range(22):
        lon = -math.pi + (i + rng.uniform(0.1, 0.9)) / 22 * 2 * math.pi
        lat = rng.uniform(0.17, 0.95)
        cx, cy = (lon / (2 * math.pi) + 0.5) * W, (0.5 - lat / math.pi) * H
        rx = rng.uniform(26, 70) * k * (1 + rng.random() ** 3)
        ry = rx * rng.uniform(0.6, 1.0)
        n = 48
        ang = np.linspace(0, 2 * math.pi, n, endpoint=False)
        wob = 1 + sum(rng.normal(0, 0.10 / (h + 1)) * np.cos(h * ang + rng.uniform(0, 6.3)) for h in range(1, 6))
        dc.polygon([(cx + rx * wob[j] * math.cos(ang[j]), cy + ry * wob[j] * math.sin(ang[j])) for j in range(n)], fill=255)
        for _ in range(rng.integers(4, 8)):
            a0 = rng.uniform(0, 6.3)
            p = np.array([cx + rx * 0.8 * math.cos(a0), cy + ry * 0.8 * math.sin(a0)])
            d = np.array([math.cos(a0), math.sin(a0)])
            wdt = rx * rng.uniform(0.28, 0.45)
            for step in range(int(rng.uniform(40, 120))):
                d = d + rng.normal(0, 0.16, 2)
                d /= np.linalg.norm(d)
                q = p + d * 6 * k
                dc.line([tuple(p), tuple(q)], fill=255, width=max(2, int(wdt * (1 - step / 130.0))))
                p = q
    cover = ndimage.gaussian_filter(np.asarray(cov, dtype=F32) / 255.0, 0.8 * k)
    cover = np.clip(cover * 1.15, 0, 1)
    rim = ndimage.gaussian_filter(emboss(cover, 2.4 * k), 0.5 * k)
    # sanfte Binnenlichtung (Kern) fuer Plastizitaet
    inner = ndimage.gaussian_filter(cover, 9 * k)
    rim = np.clip(rim * 1.0 + 0.02 * np.clip(cover - inner, 0, 1), 0, 1)
    return rim, cover, rng


def save_rgba(path, rgb_lin, alpha, rng, lossless=True):
    enc = np.clip(np.rint(lin_to_srgb(np.sqrt(np.clip(rgb_lin, 0, 1))) * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(np.dstack([enc, np.clip(np.rint(alpha * 255), 0, 255).astype(np.uint8)])).save(
        path, "WEBP", lossless=True, exact=True, quality=100, method=4)


def build(W, seed, out_dir):
    H = W // 2
    os.makedirs(out_dir, exist_ok=True)
    t0 = time.time()
    rim, phase, corew, cover, rng = net_layer(W, H, seed)
    # R: Kantenlicht wurzel-kodiert; G/B direkt (linear -> sRGB-kodiert, Shader liest linear)
    r = lin_to_srgb(np.sqrt(rim))
    g = lin_to_srgb(phase)
    b = lin_to_srgb(corew)
    arr = np.rint(np.dstack([r, g, b]) * 255.0).clip(0, 255).astype(np.uint8)
    Image.fromarray(np.dstack([arr, np.rint(cover * 255).astype(np.uint8)])).save(
        os.path.join(out_dir, "sky_nerve.webp"), "WEBP", lossless=True, exact=True, quality=100, method=4)
    print("net %.0fs" % (time.time() - t0))
    haze, rng = haze_layer(W // 2, H // 2, seed)
    Image.fromarray(to_u8(np.sqrt(haze), rng)).save(os.path.join(out_dir, "sky_nerve_haze.webp"), "WEBP", quality=96, method=6)
    cfg = dict(col=RIMC, L=LIGHT, wmean=0.10, shear=0.25, frame=0.0, tall=0.12, shape="blob", rim=0.85, sd=41)
    rgb, alpha, rng = M.rows_layer(W, H, seed, cfg)
    save_rgba(os.path.join(out_dir, "sky_nerve_rows.webp"), rgb, alpha, rng)
    print("rows %.0fs" % (time.time() - t0))
    krim, kcov, rng = knots_layer(W, H, seed)
    save_rgba(os.path.join(out_dir, "sky_nerve_prisms.webp"), krim[..., None] * RIMC[None, None, :], kcov, rng)
    dust, rng = M.dust_layer(W, H, seed, RIMC * np.array([1.0, 0.7, 0.8], F32), 37, 0.7)
    M.save_rgb(os.path.join(out_dir, "sky_nerve_stars.webp"), dust, rng, 92)
    for f in sorted(os.listdir(out_dir)):
        if f.endswith(".webp"):
            print("%s %.2f MB" % (f, os.path.getsize(os.path.join(out_dir, f)) / 1e6))
    print("done %.0fs" % (time.time() - t0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=8192)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default=OUT_DIR)
    a = ap.parse_args()
    build(a.width, a.seed, a.out)


if __name__ == "__main__":
    main()
