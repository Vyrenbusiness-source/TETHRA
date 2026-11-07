#!/usr/bin/env python3
"""TETHRA Welt-Thema "Rift": der Raum reisst. Gigantischer gezackter Spalt aus fahlem
gruen-grauem Licht im Schwarz, Bruchkanten, fliegende Bruchstuecke und Splitterstaub.

Erzeugt in assets_game/themes/rift/ (8192x4096, WebP):
  sky_rift.webp          Panorama, DATEN-Kodierung (kein Farbbild): R = Spalt-Feld
                         (1 im Kern, faellt mit dem Abstand ab; der Shader schneidet es per
                         Schwelle -> Spalt atmet/weitet sich scharf), G = Streulicht/Dunst,
                         B = Bruchkanten-Risse. Wurzel-kodiert (linear = pow(tex, 2)).
  sky_rift_rows.webp     Tunnel-Textur RGBA (u = Winkel um -Z, v = ln(tan(a/2))/ln 4 pro
                         Periode, Reihen rasten per beat_step): schlanke Bruchstuecke/Splitter.
  sky_rift_prisms.webp   nahe Ebene RGBA (Panorama): grosse, kantige schwarze Bruchstuecke.
  sky_rift_stars.webp    Splitterstaub (Panorama).
  python tools/gen_theme_rift.py [--width 8192]
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
OUT_DIR = os.path.join(M.ROOT, "assets_game", "themes", "rift")
PALE = hexcol("#b8d0c0").astype(F32)     # fahles Gruen-Grau (Spalt-Licht)
LIGHT_AT = np.array([0.15, 0.99])        # Licht kommt von oben (Spalt)
LIGHT_AT = LIGHT_AT / np.linalg.norm(LIGHT_AT)


def crack_path(rng, p0, p1, depth=6, rough=0.28):
    """Gezackte Polylinie (Mittelpunkt-Verschiebung), Punkte in (lon, lat) Radiant."""
    pts = [np.array(p0, float), np.array(p1, float)]
    amp = rough
    for _ in range(depth):
        new = [pts[0]]
        for a, b in zip(pts[:-1], pts[1:]):
            m = (a + b) / 2
            d = b - a
            n = np.array([-d[1], d[0]])
            n /= (np.linalg.norm(n) + 1e-9)
            m = m + n * rng.normal(0, amp) * np.linalg.norm(d)
            new += [m, b]
        pts = new
        amp *= 0.78
    return np.array(pts)


def far_layer(W, H, seed):
    rng = np.random.default_rng(seed + 3)
    k = W / 4096.0
    img = Image.new("F", (W, H), 0.0)
    dr = ImageDraw.Draw(img)

    def to_px(pt):
        return ((pt[0] / (2 * math.pi) + 0.5) * W, (0.5 - pt[1] / math.pi) * H)

    def stroke(path, w0, w1, val=1.0):
        n = len(path)
        for i in range(n - 1):
            t = i / max(n - 1, 1)
            w = (w0 * (1 - t) + w1 * t) * (0.55 + 0.9 * abs(math.sin(i * 0.37)))
            dr.line([to_px(path[i]), to_px(path[i + 1])], fill=val, width=max(1, int(w)))

    main = crack_path(rng, (-1.9, 0.10), (1.9, 0.30), 8, 0.30)
    stroke(main, 5.0 * k, 3.0 * k)
    for _ in range(26):
        i0 = rng.integers(20, len(main) - 20)
        a = main[i0]
        ang = rng.uniform(0.5, 1.2) * rng.choice([-1, 1]) + math.pi / 2 * rng.choice([0, 1])
        ln = rng.uniform(0.10, 0.55)
        b = a + ln * np.array([math.cos(ang), math.sin(ang) * 0.7])
        b[1] = np.clip(b[1], -0.05, 1.2)
        br = crack_path(rng, a, b, 6, 0.30)
        stroke(br, 2.6 * k, 0.6 * k, 0.85)
        if rng.random() < 0.5:
            k2 = rng.integers(len(br) // 4, len(br) // 2)
            c = br[k2] + rng.uniform(0.04, 0.2) * np.array([math.cos(ang + 0.8), math.sin(ang + 0.8)])
            stroke(crack_path(rng, br[k2], c, 5, 0.3), 1.4 * k, 0.4 * k, 0.7)
    core = np.asarray(img, dtype=F32)
    f1 = ndimage.gaussian_filter(core, 1.2)
    f2 = ndimage.gaussian_filter(core, 5.0 * k)
    f3 = ndimage.gaussian_filter(core, 22.0 * k)
    f4 = ndimage.gaussian_filter(core, 90.0 * k)
    field = np.maximum(np.clip(f1, 0, 1), np.clip(f2 * 2.2, 0, 1) * 0.55)
    field = np.maximum(field, np.clip(f3 * 3.0, 0, 1) * 0.30)
    lon, lat = M.pano_grid(W, H)
    haze_n = M.fbm(rng, H, W, 4, 16, 5, 0.55)
    haze = np.clip(f4 * 4.0, 0, 1) * (0.55 + 0.35 * haze_n) + np.clip(f3 * 3.0, 0, 1) * 0.5
    fd = M.front_dark(lon, lat)
    haze = haze * smoothstep(-0.5, 0.0, lat) * fd
    cr = Image.new("F", (W, H), 0.0)
    dc = ImageDraw.Draw(cr)
    for _ in range(260):
        i0 = rng.integers(0, len(main))
        a = main[i0] + rng.normal(0, 0.05, 2)
        a[1] = abs(a[1]) + 0.01
        t1, t2 = rng.uniform(0, 6.3, 2)
        b = a + rng.uniform(0.02, 0.12) * np.array([math.cos(t1), math.sin(t2)])
        pp = [to_px(p) for p in crack_path(rng, a, b, 4, 0.35)]
        dc.line(pp, fill=float(rng.uniform(0.4, 1.0)), width=max(1, int(k)))
    cracks = ndimage.gaussian_filter(np.asarray(cr, dtype=F32), 0.7) * fd
    rgb = np.dstack([field * fd, np.clip(haze, 0, 1), np.clip(cracks, 0, 1)])
    return np.clip(rgb, 0, 1), rng


def build(W, seed, out_dir):
    H = W // 2
    os.makedirs(out_dir, exist_ok=True)
    t0 = time.time()
    far, rng = far_layer(W, H, seed)
    Image.fromarray(to_u8(np.sqrt(far), rng)).save(os.path.join(out_dir, "sky_rift.webp"), "WEBP", quality=97, method=6)
    print("far %.0fs" % (time.time() - t0))
    cfg = dict(col=PALE, L=LIGHT_AT, wmean=0.05, shear=1.3, frame=0.05, tall=0.45, rim=0.9, sd=71)
    rgb, alpha, rng = M.rows_layer(W, H, seed, cfg)
    enc = np.clip(np.rint(lin_to_srgb(np.sqrt(rgb)) * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(np.dstack([enc, np.clip(np.rint(alpha * 255), 0, 255).astype(np.uint8)])).save(
        os.path.join(out_dir, "sky_rift_rows.webp"), "WEBP", lossless=True, exact=True, quality=100, method=4)
    print("rows %.0fs" % (time.time() - t0))
    prgb, palpha, rng = M.prisms_layer(W, H, seed, dict(col=PALE, L=LIGHT_AT, jit=0.45, n=30, sd=83))
    penc = to_u8(np.sqrt(prgb), rng)
    Image.fromarray(np.dstack([penc, np.clip(np.rint(palpha * 255), 0, 255).astype(np.uint8)])).save(
        os.path.join(out_dir, "sky_rift_prisms.webp"), "WEBP", lossless=True, exact=True, quality=100, method=4)
    dust, rng = M.dust_layer(W, H, seed, PALE, 97, 1.0)
    M.save_rgb(os.path.join(out_dir, "sky_rift_stars.webp"), dust, rng, 92)
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
