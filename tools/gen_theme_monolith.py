#!/usr/bin/env python3
"""TETHRA Welt-Thema "Monolith": endlose Reihen schwebender schwarzer Monolithen im Nichts.

Erzeugt in assets_game/themes/monolith/ drei Texturen (4096x2048, WebP):
  sky_monolith.webp        Panorama (equirektangular): schwarzes Nichts, kalter Dunst am
                           Horizont, EINE kalte weisse Kantenlichtquelle (hoher Lichtspalt
                           links vorn), ferne Monolithen-Silhouetten mit Kantenlicht.
  sky_monolith_rows.webp   Tunnel-Textur (RGBA, KEIN Panorama): u = Winkel um die
                           Flugachse (-Z), v = ln(tan(a/2)) ueber EINE Periode (Faktor 4,
                           8 Reihen). Monolithen-Platten mit Kantenlicht (RGB, additiv) und
                           Deckkraft (A). Periodisch in v -> die Reihen ruecken per
                           beat_step ohne Naht und ohne Ueberblendung vor (Shader mit Mips).
  sky_monolith_stars.webp  Panorama: schwebender Staub/Partikel (Parallax-Ebene).

Kodierung der RGB-Kanaele wie sky_panorama (wurzel-kodiert, linear = pow(tex, 2)).
Reproduzierbar per Seed:
  python tools/gen_theme_monolith.py                      # 8192x4096, Seed 0
  python tools/gen_theme_monolith.py --width 2048 --preview <ordner>
"""
import argparse
import math
import os
import sys
import time

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_skybox import smoothstep, hexcol, to_u8, lin_to_srgb  # noqa: E402

F32 = np.float32
D2R = math.pi / 180.0
LN4 = math.log(4.0)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets_game", "themes", "monolith")

# Farbsatz: nur kaltes Weiss auf Schwarz (kein Neon).
COLD = hexcol("#cfdcf0").astype(F32)      # Kantenlicht
COLD_HOT = hexcol("#f4f8ff").astype(F32)  # Lichtspalt-Kern
HAZE = hexcol("#5a6678").astype(F32)      # Dunst
LIGHT_LON = -27.0 * D2R                    # Lichtspalt (Laenge)
LIGHT_LAT = (-5.0 * D2R, 36.0 * D2R)       # Lichtspalt (Hoehe von/bis)
L_SCREEN = np.array([-0.55, 0.83])         # Licht-Richtung im Bild (x rechts, y oben)
L_SCREEN = L_SCREEN / np.linalg.norm(L_SCREEN)


def noise(rng, H, W, gh, gw):
    """Kachelbares Rauschen: Zufallsgitter gh x gw, kubisch hochskaliert (wrap)."""
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


def wrap_pi(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def front_dark(lon, lat):
    """Vorn-mitte/unten (hinter Strecke + Noten) schon im Bild abdunkeln."""
    f = np.exp(-(lon / 0.62) ** 2) * smoothstep(0.22, -0.30, lat)
    return 1.0 - 0.7 * f


def save_rgb(path, lin, rng, quality=96):
    Image.fromarray(to_u8(np.sqrt(np.clip(lin, 0, 1)), rng)).save(path, "WEBP", quality=quality, method=6)


# ---------------------------------------------------------------------------
# Panorama: Nichts, Dunst, Lichtspalt, ferne Silhouetten
# ---------------------------------------------------------------------------
def far_layer(W, H, seed):
    S = W / 4096.0 * 0.7
    rng = np.random.default_rng(seed)
    lon, lat = pano_grid(W, H)
    # Dunst: Band um den Horizont, waagrecht gestreckt gewoelbt.
    band = np.exp(-((lat - 0.05) / 0.17) ** 2)
    n1 = fbm(rng, H, W, 6, 24, 6, 0.55)
    n2 = fbm(rng, H, W, 3, 10, 4, 0.6)
    dens = np.clip(0.55 + 0.30 * n1 + 0.22 * n2, 0, None) ** 1.6
    haze = 0.020 * band * dens + 0.0016 * (0.6 + 0.4 * n2.clip(-1, 1))
    haze *= smoothstep(-0.55, -0.05, lat)  # unten Schwarz
    img = haze[..., None] * HAZE[None, None, :]

    # Der Lichtspalt: duenn, sehr hoch, kalt weiss. Abstand zur Strecke (Segment) im Winkel.
    dx = wrap_pi(lon - LIGHT_LON) * np.cos(np.clip(lat, -1.4, 1.4))
    dseg = np.maximum(0.0, np.maximum(LIGHT_LAT[0] - lat, lat - LIGHT_LAT[1]))
    d = np.hypot(dx, dseg)
    # leicht flackerfreie Struktur: Kern wird zu den Enden hin duenner
    t = np.clip((lat - LIGHT_LAT[0]) / (LIGHT_LAT[1] - LIGHT_LAT[0]), 0, 1)
    w = 0.0016 * (0.35 + 0.65 * np.clip(np.sin(math.pi * t), 0, 1) ** 0.6)
    core = np.exp(-(d / np.maximum(w, 1e-4)) ** 2) * (1.0 - 0.9 * np.abs(2 * t - 1) ** 6)
    halo1 = 0.30 / (1.0 + (d / 0.006) ** 2)
    halo2 = 0.07 * np.exp(-d / 0.09)
    wide = 0.020 * np.exp(-np.abs(dx) / 0.45) * smoothstep(-0.1, 0.4, lat) * (1.0 - 0.6 * dens)
    streak = 0.10 * np.exp(-np.abs(lat - 0.2) / 0.006) * np.exp(-np.abs(dx) / 0.30)
    light = core * 1.0 + halo1 * 0.55 + halo2 * (0.7 + 0.3 * dens) + wide + streak
    # Dunst bricht das Licht: zusaetzliches Streulicht im Dunstband
    img = img * (1.0 + 2.2 * np.exp(-np.abs(dx) / 0.5)[..., None]) + light[..., None] * (
        0.4 * COLD + 0.6 * COLD_HOT)[None, None, :]

    # Ferne Monolithen-Silhouetten: schwarz, mit Kantenlicht zur Quelle hin.
    mask = np.zeros((H, W), F32)
    rim = np.zeros((H, W), F32)
    px_lon = W / (2 * math.pi)
    px_lat = H / math.pi
    for i in range(110):
        c = rng.uniform(-math.pi, math.pi)
        if abs(wrap_pi(c)) < 0.22 and rng.random() < 0.8:
            continue
        hw = rng.uniform(0.004, 0.022) * (1.0 + 2.0 * rng.random() ** 3)
        top = rng.uniform(0.02, 0.32) * (0.6 + 0.8 * rng.random())
        bot = rng.uniform(-0.05, 0.0)
        shear = rng.uniform(-0.25, 0.25)
        x0 = int((c - hw * 2.6) * px_lon + W / 2)
        x1 = int((c + hw * 2.6) * px_lon + W / 2) + 2
        y0 = int((0.5 - top / math.pi) * H) - 2
        y1 = int((0.5 - bot / math.pi) * H) + 2
        xs = np.arange(x0, x1) % W
        ys = np.arange(max(y0, 0), min(y1, H))
        lo = ((np.arange(x0, x1) + 0.5 - W / 2) / px_lon)[None, :]
        la = (0.5 - (ys + 0.5) / H)[:, None] * math.pi
        xloc = lo - c - shear * la
        dl = (xloc + hw) * px_lon
        dr = (hw - xloc) * px_lon
        dt = (top - la) * px_lat
        db = (la - bot) * px_lat
        inside = np.minimum(np.minimum(dl, dr), np.minimum(dt, db))
        m = np.clip(inside / (0.7 * S) + 0.5, 0, 1).astype(F32)
        toward = wrap_pi(LIGHT_LON - c)  # Quelle links (<0) oder rechts (>0) vom Monolith
        dside = dl if toward < 0 else dr
        k = rng.uniform(0.35, 1.0) / (1.0 + 2.5 * abs(toward))
        r = (np.exp(-np.maximum(dside, 0) / (1.2 * S)) + 0.25 * np.exp(-np.maximum(dt, 0) / (1.2 * S))) * (inside > -0.5)
        sub = np.ix_(ys, xs)
        mask[sub] = np.maximum(mask[sub], m)
        rim[sub] = np.maximum(rim[sub], (r * k * m).astype(F32))
    img = img * (1.0 - mask[..., None])
    img += (rim * 0.55)[..., None] * COLD[None, None, :]

    # ganz feine Filmkoernung im Dunst (gegen Banding), vorn-mitte/unten dunkel
    img *= front_dark(lon, lat)[..., None]
    return np.clip(img, 0, 1.0), rng


# ---------------------------------------------------------------------------
# Tunnel-Textur: Monolithen-Reihen (u = Winkel, v = ln r ueber Faktor 4)
# ---------------------------------------------------------------------------
def rows_layer(W, H, seed):
    rng = np.random.default_rng(seed + 11)
    S = W / 4096.0 * 0.7
    q = W / (2 * math.pi)             # Texel pro rad (Winkel)
    sy = q * LN4 / H                   # iso-Einheiten je v-Texel
    RH = H // 8
    rgb = np.zeros((H, W, 3), F32)
    alpha = np.zeros((H, W), F32)
    blocked = {k: [] for k in range(8)}
    for k in range(8):
        cur = rng.uniform(0, 2 * math.pi)
        end = cur + 2 * math.pi
        slabs = []
        while cur < end - 0.03:
            gap = rng.uniform(0.012, 0.10) * (1.8 if rng.random() < 0.15 else 1.0)
            w = float(np.clip(rng.lognormal(math.log(0.115), 0.5), 0.035, 0.42))
            a = cur + gap
            b = a + w
            if b > end:
                break
            cur = b
            c = 0.5 * (a + b)
            # reservierte Winkelbereiche (hohe Platten der Reihe darunter)
            if any(abs(wrap_pi(c - bc)) < (bw + w) * 0.5 + 0.01 for bc, bw in blocked[k]):
                continue
            tall = k < 7 and rng.random() < 0.20
            t0 = rng.uniform(0.10, 0.28)
            t1 = (rng.uniform(1.20, 1.55) if tall else rng.uniform(0.62, 0.90))
            if tall:
                blocked[k + 1].append((c, w))
            slabs.append((c, 0.5 * w, k + t0, k + t1, rng.uniform(-0.55, 0.55) * (1.0 if rng.random() < 0.55 else 0.1),
                          rng.uniform(0.45, 1.25), rng.random() < 0.42))
        for (c, hw, ra, rb, shear, litk, frame) in slabs:
            ya, yb = ra * RH, rb * RH
            yb = min(yb, H - 3)
            hh = (yb - ya)
            mx = int((hw + abs(shear) * (hh / RH) * 0.35 + 0.02) * q) + 4
            cx = int(round((c / (2 * math.pi) + 0.5) * W))
            mx = int(mx * (W / 4096.0)**0 )
            xs = (np.arange(cx - mx, cx + mx + 1)) % W
            ys = np.arange(int(ya) - 2, int(yb) + 3)
            ys = ys[(ys >= 0) & (ys < H)]
            th_rel = (np.arange(cx - mx, cx + mx + 1) + 0.5) / q - c - (W / 2) / q   # rad
            th_rel = wrap_pi(th_rel)[None, :]
            yy = (ys[:, None] + 0.5)
            ycn = (yy - 0.5 * (ya + yb)) / hh   # -0.5..0.5
            xloc = th_rel - shear * ycn * 0.35
            dl = (xloc + hw) * q
            dr = (hw - xloc) * q
            db = (yy - ya) * sy
            dt = (yb - yy) * sy
            ds = (dl, dr, db, dt)
            inside = np.minimum(np.minimum(dl, dr), np.minimum(db, dt))
            m = np.clip(inside / S + 0.5, 0, 1)
            th = th_rel + c
            s, co = np.sin(th), np.cos(th)
            nrm = ((s, -co), (-s, co), (-co, -s), (co, s))
            r = np.zeros(m.shape, F32)
            sheen = np.zeros(m.shape, F32)
            lit_sum = 0.0
            for dist, (nx, ny) in zip(ds, nrm):
                lit = np.clip(nx * L_SCREEN[0] + ny * L_SCREEN[1], 0, 1) ** 1.4
                dd = np.maximum(dist, 0)
                r += lit * (np.exp(-dd / (2.6 * S)) + 0.035 * np.exp(-dd / (8.0 * S)))
                sheen += lit * np.exp(-dd / (46.0 * S))
                r += 0.02 * np.exp(-dd / (1.2 * S))   # Restlicht: unbeleuchtete Kanten bleiben lesbar
            body = 0.0025 * sheen
            if frame:
                inset = (6.5 + 2.5 * (hw * q > 60)) * S / 0.7 * 0.7
                fr = np.exp(-((inside - inset) / (0.9 * S)) ** 2) * (inside > 0)
                r += fr * 0.14 * (0.4 + sheen / (sheen.max() + 1e-6))
            col = (r * litk + body)[..., None] * COLD[None, None, :]
            sub = np.ix_(ys, xs)
            rgb[sub] = np.where((m > 0)[..., None], np.maximum(rgb[sub], col * m[..., None]), rgb[sub])
            alpha[sub] = np.maximum(alpha[sub], m.astype(F32))
    rgb = np.clip(rgb, 0, 1.0)
    return rgb, alpha, rng


# ---------------------------------------------------------------------------
# Staub: schwebende Partikel (Panorama)
# ---------------------------------------------------------------------------
def dust_layer(W, H, seed):
    rng = np.random.default_rng(seed + 29)
    img = np.zeros((H, W, 3), F32)
    n = int(7000 * (W / 4096) ** 2)
    lon = rng.uniform(-math.pi, math.pi, n)
    lat = np.arcsin(rng.uniform(-0.45, 0.62, n))
    lum = 0.55 * rng.random(n) ** 3.2 + 0.015
    sz = (0.5 + 1.1 * rng.random(n) ** 2) * (W / 4096.0)
    px = (lon / (2 * math.pi) + 0.5) * W
    py = (0.5 - lat / math.pi) * H
    KR = int(4 * W / 4096)
    yy, xx = np.mgrid[-KR:KR + 1, -KR:KR + 1].astype(F32)
    for i in range(n):
        cx, cy = int(px[i]), int(py[i])
        fx, fy = px[i] - cx, py[i] - cy
        k = np.exp(-((xx - fx) ** 2 + (yy - fy) ** 2) / (2 * sz[i] ** 2))
        k *= lum[i] / max(k.sum(), 1e-6) * (2.0 * sz[i] ** 2) * 0.45
        ys = np.clip(cy + np.arange(-KR, KR + 1), 0, H - 1)
        xs = (cx + np.arange(-KR, KR + 1)) % W
        img[np.ix_(ys, xs)] += k[..., None] * COLD[None, None, :]
    # wenige unscharfe Bokeh-Scheiben (nahe Partikel)
    for i in range(int(90 * W / 4096)):
        lo, la = rng.uniform(-math.pi, math.pi), math.asin(rng.uniform(-0.3, 0.55))
        cx, cy = int((lo / (2 * math.pi) + 0.5) * W), int((0.5 - la / math.pi) * H)
        R = int(rng.uniform(5, 11) * W / 4096)
        yy2, xx2 = np.mgrid[-R - 2:R + 3, -R - 2:R + 3].astype(F32)
        rr = np.hypot(xx2, yy2)
        disc = smoothstep(R + 1.0, R - 1.0, rr) * (0.6 + 0.4 * smoothstep(R * 0.4, R, rr)) * rng.uniform(0.012, 0.04)
        ys = np.clip(cy + np.arange(-R - 2, R + 3), 0, H - 1)
        xs = (cx + np.arange(-R - 2, R + 3)) % W
        img[np.ix_(ys, xs)] += disc[..., None] * COLD[None, None, :]
    lon_g, lat_g = pano_grid(W, H)
    img *= front_dark(lon_g, lat_g)[..., None]
    return np.clip(img, 0, 1.0), rng



# ---------------------------------------------------------------------------
# Nahe Ebene: grosse schwarze Prismen (RGBA-Panorama), Parallax-Orbit per beat_step
# ---------------------------------------------------------------------------
def prisms_layer(W, H, seed):
    from PIL import ImageDraw
    rng = np.random.default_rng(seed + 53)
    SS = 3
    S = W / 4096.0
    rgb = np.zeros((H, W, 3), F32)
    alpha = np.zeros((H, W), F32)
    px_lon = W / (2 * math.pi)
    px_lat = H / math.pi
    n = 26
    for i in range(n):
        lon = -math.pi + (i + rng.uniform(0.1, 0.9)) / n * 2 * math.pi
        lat = rng.uniform(9.0, 52.0) * D2R
        sc = rng.uniform(0.55, 1.35) * (1.0 + 0.8 * rng.random() ** 3)
        w = rng.uniform(0.02, 0.05) * sc * px_lon
        h = rng.uniform(0.06, 0.16) * sc * px_lat
        if rng.random() < 0.3:
            w, h = h * 0.8, w * 1.4
        ang = rng.uniform(-0.6, 0.6)
        dx, dy = rng.uniform(-0.55, 0.55) * w, rng.uniform(0.25, 0.6) * h * 0.5
        stretch = 1.0 / max(math.cos(lat), 0.35)
        cs, sn = math.cos(ang), math.sin(ang)
        pad = int((w + h + abs(dx) + abs(dy)) * stretch * 0.9) + 8
        size = 2 * pad
        im = Image.new("L", (size * SS, size * SS), 0)      # Deckung
        fc = Image.new("F", (size * SS, size * SS), 0.0)     # Licht
        dm, df = ImageDraw.Draw(im), ImageDraw.Draw(fc)

        def P(x, y):
            xr, yr = x * cs - y * sn, x * sn + y * cs
            return ((pad + xr * stretch) * SS, (pad - yr) * SS)
        # Front: Rechteck (x 0..w, y 0..h), Tiefe: Versatz (dx,dy) nach hinten
        fr = [(0, 0), (w, 0), (w, h), (0, h)]
        bk = [(x + dx, y + dy) for x, y in fr]
        faces = [bk]
        side = dx > 0
        faces.append([fr[1], bk[1], bk[2], fr[2]] if side else [fr[0], bk[0], bk[3], fr[3]])
        faces.append([fr[3], fr[2], bk[2], bk[3]])
        faces.append(fr)
        shade = [0.0, 0.0006, 0.006, 0.0012]
        for fa, sh in zip(faces, shade):
            pts = [P(*q) for q in fa]
            dm.polygon(pts, fill=255)
            df.polygon(pts, fill=sh)
        # Kanten: Licht kommt von links oben (L_SCREEN)
        edge_sets = [(fr[0], fr[3]), (fr[3], fr[2]), (fr[2], fr[1]), (fr[1], fr[0]), (fr[0], bk[0]), (fr[3], bk[3]),
                     (fr[2], bk[2]), (fr[1], bk[1]), (bk[3], bk[2]), (bk[0], bk[3]), (bk[1], bk[2]), (bk[0], bk[1])]
        cx0, cy0 = w / 2 + dx / 2, h / 2 + dy / 2
        for a, b in edge_sets:
            mxp, myp = (a[0] + b[0]) / 2 - cx0, (a[1] + b[1]) / 2 - cy0
            ex, ey = b[0] - a[0], b[1] - a[1]
            nx, ny = -ey, ex
            if nx * mxp + ny * myp < 0:
                nx, ny = -nx, -ny
            nl = math.hypot(nx, ny) + 1e-6
            # Bildschirm-Normale (Rotation + y nach oben)
            sxn, syn = (nx * cs - ny * sn) / nl, (nx * sn + ny * cs) / nl
            lit = max(0.0, sxn * L_SCREEN[0] + syn * L_SCREEN[1]) ** 1.3
            val = 0.02 + 0.95 * lit
            df.line([P(*a), P(*b)], fill=float(val), width=max(1, int(1.6 * SS * S * 0.7)))
        m = np.asarray(im.resize((size, size), Image.LANCZOS), dtype=F32) / 255.0
        li = np.asarray(fc.resize((size, size), Image.BOX), dtype=F32) * 1.0
        cxp = int((lon / (2 * math.pi) + 0.5) * W)
        cyp = int((0.5 - lat / math.pi) * H)
        ys = np.arange(cyp - pad, cyp + pad)
        xs = (np.arange(cxp - pad, cxp + pad)) % W
        ok = (ys >= 0) & (ys < H)
        ys, m, li = ys[ok], m[ok], li[ok]
        sub = np.ix_(ys, xs)
        rgb[sub] = np.maximum(rgb[sub], li[..., None] * COLD[None, None, :])
        alpha[sub] = np.maximum(alpha[sub], m)
    return np.clip(rgb, 0, 1.0), alpha, rng

def build(W, seed, out_dir, preview):
    H = W // 2
    os.makedirs(out_dir, exist_ok=True)
    t0 = time.time()
    far, rng = far_layer(W, H, seed)
    save_rgb(os.path.join(out_dir, "sky_monolith.webp"), far, rng, 96)
    print("far %.0fs" % (time.time() - t0))
    rgb, alpha, rng = rows_layer(W, H, seed)
    enc = to_u8(np.sqrt(rgb), np.random.default_rng(0)) if False else np.clip(np.rint(lin_to_srgb(np.sqrt(rgb)) * 255.0 + 0.0), 0, 255).astype(np.uint8)
    rgba = np.dstack([enc, np.clip(np.rint(alpha * 255), 0, 255).astype(np.uint8)])
    Image.fromarray(rgba).save(os.path.join(out_dir, "sky_monolith_rows.webp"), "WEBP",
                                       lossless=True, exact=True, quality=100, method=4)
    print("rows %.0fs" % (time.time() - t0))
    prgb, palpha, rng = prisms_layer(W, H, seed)
    penc = to_u8(np.sqrt(prgb), rng)
    Image.fromarray(np.dstack([penc, np.clip(np.rint(palpha * 255), 0, 255).astype(np.uint8)])).save(
        os.path.join(out_dir, "sky_monolith_prisms.webp"), "WEBP", lossless=True, exact=True, quality=100, method=4)
    print("prisms %.0fs" % (time.time() - t0))
    dust, rng = dust_layer(W, H, seed)
    save_rgb(os.path.join(out_dir, "sky_monolith_stars.webp"), dust, rng, 92)
    print("dust %.0fs" % (time.time() - t0))
    for f in sorted(os.listdir(out_dir)):
        if f.endswith(".webp"):
            print("%s %.2f MB" % (f, os.path.getsize(os.path.join(out_dir, f)) / 1e6))
    if preview:
        os.makedirs(preview, exist_ok=True)
        Image.fromarray(to_u8(np.sqrt(far[::2, ::2]), rng)).resize((1024, 512)).save(os.path.join(preview, "mono_far.png"))
        Image.fromarray(np.dstack([enc, np.clip(np.rint(alpha * 255), 0, 255).astype(np.uint8)])[..., :3]).resize(
            (1024, 512)).save(os.path.join(preview, "mono_rows.png"))


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
