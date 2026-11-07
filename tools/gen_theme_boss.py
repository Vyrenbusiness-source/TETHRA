#!/usr/bin/env python3
"""TETHRA Welt-Thema "Bosskampf": rotes Inferno-Panorama (offline, numpy+PIL).

Erzeugt in assets_game/themes/boss/ drei equirektangulare Texturen (4096x2048):
  sky_boss.webp         Himmel: blutrot bis schwarz, gluehender Horizont (ferne
                        Feuer), von unten angestrahlte Wolkenbaenke, ferne
                        Gewittertuerme (Cumulonimbus mit Amboss, aus Kugel-
                        Quellwolken als Hoehenfeld aufgebaut, von unten beleuchtet).
  sky_boss_embers.webp  Glut-Ebene ohne Himmel (Parallax): aufsteigende Funken
                        mit kurzem Schweif, wenige unscharfe Bokeh-Glutflocken.
  sky_boss_flash.webp   Blitz-Licht (NUR additiv, Shader-Uniform `lightning`):
                        R/G/B = drei getrennte Blitz-Gruppen (je wenige Zellen
                        in Tuermen/Wolken + Blitzkanaele), Graustufen-Intensitaet.
                        Nur oberer Himmel, nie vorn-mitte ueber der Strecke.

Abbildung wie tools/gen_skybox.py / shaders/sky_panorama.gdshader:
  u = atan(d.x, -d.z) / 2pi + 0.5   (u=0.5 = vorn, -Z),  v = 0.5 - asin(d.y) / pi
Kodierung: wurzel-kodiert (Shader: linear = pow(textur, 2.0)).
Vorn-mitte/unten (hinter Strecke + Noten) ist im Bild schon abgedunkelt.

Reproduzierbar per Seed:
  python tools/gen_theme_boss.py                          # 4096x2048, Seed 0
  python tools/gen_theme_boss.py --width 1024 --preview <ordner>
--preview schreibt Kamera-Ansichten wie die Komfort-Kamera (fov 62, Neigung
-16 Grad) ohne/mit Blitz + verkleinerte Panoramen als PNG.
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_skybox import (Noise3, smoothstep, ramp, hexcol, srgb_to_lin, dir_to_px,  # noqa: E402
                        splat, tonemap, to_u8, lonlat_dir)

F32 = np.float32
D2R = math.pi / 180.0
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets_game", "themes", "boss")

# ---------------------------------------------------------------------------
# Art-Direction (sRGB-Hex, intern linear). Rampen sind reine Farbtoene (auf
# Maximal-Kanal normiert), die Helligkeit kommt getrennt dazu.
# ---------------------------------------------------------------------------
# Streng monochrom: EIN tiefes Blutrot (Schattierungen davon) auf Fast-Schwarz.
# Keine Orange-/Gelb-Toene; nur die hellsten Lichter werden minimal entsaettigt.
BLOOD = "#8c0610"
GLOW_HUE = ["#7a0410", "#86060f", "#8c0610", "#94080f", "#a01214"]
CLOUD_HUE = ["#70040e", "#80050f", "#8c0610", "#9a0c12", "#a81816"]
CLOUD_DARK = "#050102"
ZENITH = "#030001"
ABYSS = "#010000"
EMBER_HUE = ["#7a040e", "#8c0610", "#9e0a12", "#b41a18", "#c8302a"]

# Gewittertuerme: (Laenge Grad, halbe Basisbreite Grad, Hoehe Grad, Neigung Grad,
# Amboss-Breite x Basis, Dunst 0..1 = Entfernung). Komfort-Kamera sieht vorn
# ca. +-47 Grad und bis ca. 15 Grad Hoehe: -34, -17, 27, 43 sind die Helden.
TOWERS = [
    (-34.0, 5.5, 23.0, 3.0, 2.6, 0.15),
    (-17.5, 2.4, 10.0, -1.0, 2.3, 0.55),
    (25.0, 4.2, 15.0, -2.5, 2.8, 0.40),
    (42.0, 7.0, 29.0, 4.0, 2.4, 0.05),
    (-60.0, 8.5, 34.0, -5.0, 2.2, 0.10),
    (78.0, 7.5, 25.0, 3.0, 2.6, 0.25),
    (112.0, 9.5, 37.0, -4.0, 2.3, 0.05),
    (150.0, 5.5, 18.0, 2.0, 2.7, 0.45),
    (-168.0, 10.0, 39.0, 5.0, 2.2, 0.05),
    (-128.0, 6.5, 23.0, -3.0, 2.6, 0.30),
    (-92.0, 4.5, 15.0, 2.0, 2.5, 0.50),
    (-150.0, 3.2, 11.0, 0.0, 2.0, 0.60),
    (8.0, 1.6, 6.0, 0.5, 2.0, 0.75),
]

# Blitz-Zellen: (Gruppe 0..2, Laenge, Breite, Radius Grad, Blitzkanaele).
# Gruppe = Farbkanal der Flash-Textur. Je Gruppe genau eine Zelle im Komfort-
# Sichtfeld (vorn), der Rest liegt seitlich/hinten.
FLASH_CELLS = [
    (0, -33.0, 12.0, 6.0, 2),
    (0, 112.0, 22.0, 9.0, 2),
    (0, -150.0, 7.0, 4.5, 0),
    (1, 25.5, 9.5, 5.0, 1),
    (1, -128.0, 14.0, 7.0, 1),
    (1, 78.0, 16.0, 7.0, 0),
    (2, 42.5, 15.0, 7.0, 2),
    (2, -17.5, 6.5, 3.4, 0),
    (2, -168.0, 23.0, 9.0, 1),
    (2, 150.0, 12.0, 5.5, 0),
]


def hue(h):
    c = hexcol(h)
    return c / c.max()


def lin(h):
    return hexcol(h).astype(F32)


def wrap_pi(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def grid(W, H, r0, r1):
    lon = ((np.arange(W, dtype=F32) + 0.5) / W - 0.5) * F32(2 * math.pi)
    lat = (0.5 - (np.arange(r0, r1, dtype=F32) + 0.5) / H) * F32(math.pi)
    lon, lat = np.meshgrid(lon, lat)
    cl = np.cos(lat)
    return np.stack([cl * np.sin(lon), np.sin(lat), -cl * np.cos(lon)]), lon, lat


def front_mask(lon, lat):
    """1 = voll, klein = vorn-mitte/unten abgedunkelt (hinter Strecke + Noten)."""
    front = np.exp(-(lon / F32(0.55)) ** 2) * smoothstep(F32(0.16), F32(-0.20), lat)
    low = smoothstep(F32(0.0), F32(-0.50), lat)
    return np.clip(1 - 0.80 * front - 0.55 * low, 0.05, 1)


def sky_glow(up, fire):
    """Helligkeit (linear) des Himmels ueber dem Horizont, ohne Wolken."""
    # Azimut-Variation (Feuer-Flecken) nur am Horizont, oben gleichmaessig
    # (sonst senkrechte Baender bis in den Zenit).
    f = F32(1) + (fire - F32(1)) * np.exp(-up / F32(0.12))
    return (F32(0.30) * np.exp(-up / F32(0.035)) + F32(0.065) * np.exp(-up / F32(0.14))
            + F32(0.013) * np.exp(-up / F32(0.60))) * f + F32(0.0015)


# ---------------------------------------------------------------------------
# Felder je Zeilenblock (parallel): Hintergrund, Wolkenbaenke, Rauschen
# ---------------------------------------------------------------------------
def field_rows(args):
    W, H, r0, r1, seed = args
    nz = Noise3(seed + 11)
    d, lon, lat = grid(W, H, r0, r1)
    up = np.maximum(lat, 0)
    deg = lat / F32(D2R)

    # Feuer-Flecken entlang des Horizonts (Azimut-Variation der Glut).
    fire = nz.fbm([d[0], d[1] * F32(0.3), d[2]], 1.7, 4)
    fire = F32(0.45) + F32(1.1) * smoothstep(-0.35, 0.45, fire)
    fire *= F32(1) - F32(0.5) * np.exp(-(lon / F32(0.40)) ** 2)  # vorn-mitte ruhiger

    g = sky_glow(up, fire)
    t = np.clip(g / F32(0.33), 0, 1) ** F32(0.6)
    bg = ramp([hue(h) for h in GLOW_HUE], t) * g[..., None]
    # Unter dem Horizont: Abgrund, nur ein schmaler Glutsaum + schwacher Dunst.
    below = np.minimum(lat, 0)
    gb = fire * (F32(0.28) * np.exp(below / F32(0.010)) + F32(0.010) * np.exp(below / F32(0.12)))
    tb = np.clip(gb / F32(0.3), 0, 1) ** F32(0.6)
    bgb = ramp([hue(h) for h in GLOW_HUE], tb) * gb[..., None] + lin(ABYSS)
    bg = np.where((lat >= 0)[..., None], bg + lin(ZENITH) * smoothstep(0.2, 1.4, lat)[..., None], bgb)

    # Wolkenbaenke: horizontal gestreckt, leicht verbogen, weiche Quellformen.
    ps = [d[0], d[1] * F32(3.0), d[2]]
    q = [nz.fbm([ps[i] + F32(k * 5.1) for i in range(3)], 1.2, 3) for k in range(3)]
    pw = [ps[i] + F32(0.22) * q[i] for i in range(3)]
    n = nz.fbm(pw, 2.6, 7, gain=0.52)
    # Bedeckung nach Hoehe: tiefe Bank (vor den Turm-Fuessen), mittlere, hohe Decke.
    cov = (F32(0.36) * smoothstep(0.8, 2.5, deg) * smoothstep(7.0, 3.5, deg)
           + F32(0.20) * smoothstep(14.0, 22.0, deg) * smoothstep(40.0, 28.0, deg)
           + F32(0.34) * smoothstep(42.0, 58.0, deg) * smoothstep(89.0, 72.0, deg))
    dc = np.clip((n - (F32(0.36) - cov)) * F32(3.2), 0, None) ** F32(1.25)
    dc *= smoothstep(0.3, 1.5, deg)

    # Feines Rauschen fuer Quellwolken-Raender (Tuerme) und Blitz-Struktur.
    det = nz.fbm([d[i] + F32(31.0) for i in range(3)], 34.0, 4)
    fn = F32(0.5) + F32(0.5) * smoothstep(-0.35, 0.45, nz.fbm([d[i] + F32(41.0) for i in range(3)], 9.0, 4))

    fl = np.zeros((3,) + lat.shape, dtype=F32)
    for grp, lo, la, rad, _nb in FLASH_CELLS:
        c = lonlat_dir(lo, la).astype(F32)
        ang2 = 2 * (1 - (c[0] * d[0] + c[1] * d[1] + c[2] * d[2]))
        r2 = F32((rad * D2R) ** 2)
        fl[grp] += np.exp(-ang2 / r2) * F32(0.85) + np.exp(-ang2 / (r2 * F32(5.0))) * F32(0.15)
    fl *= fn

    return r0, bg.astype(F32), dc.astype(F32), det.astype(F32), fl, fire.astype(F32)


def ridges(sky, bg, fire, lonv, latv, seed):
    nz = Noise3(seed + 61)
    cs, sn = np.cos(lonv), np.sin(lonv)
    flat = F32(1) - F32(0.88) * np.exp(-(lonv / F32(0.36)) ** 2)
    out = sky
    for k, (amp, base, haze, f) in enumerate(((1.5, 0.25, 0.55, 3.4), (2.6, 0.10, 0.0, 2.1))):
        p = [sn * F32(f), np.full_like(lonv, F32(3.7 * k + 1.3)), cs * F32(f)]
        rg = nz.ridged(p, 1.0, 6, gain=0.5)
        top = (F32(base) + F32(amp) * np.clip(rg - 0.15, 0, None) ** F32(1.4)) * flat * F32(D2R)
        lat = latv[:, None]
        m = smoothstep(F32(0.0006), F32(-0.0006), lat - top[None, :])  # unter der Kante
        # Kantenleuchten (Glut dahinter), Fels sonst fast schwarz; ferne Staffel im Dunst.
        edge = np.exp(-np.clip(top[None, :] - lat, 0, None) / F32(0.0025)) * F32(0.35)
        rock = lin(ABYSS) + bg * (F32(haze) * F32(0.55) + edge[..., None] * F32(0.6))
        rock = rock * (1 + F32(0.0) * fire[..., None])
        out = out * (1 - m)[..., None] + rock * m[..., None]
    return out


def upward_tau(D, decay_px, ds):
    """Optische Tiefe Richtung Licht (unten): exponentiell gewichtete Summe."""
    H = D.shape[0]
    tau = np.zeros_like(D)
    k = F32(math.exp(-1.0 / decay_px))
    for r in range(H - 2, -1, -1):
        tau[r] = tau[r + 1] * k + D[r + 1] * F32(ds)
    return tau


# ---------------------------------------------------------------------------
# Gewittertuerme: Kugel-Quellwolken als Hoehenfeld (Normalen -> Licht von unten)
# ---------------------------------------------------------------------------
def tower_puffs(rng, lo, w, h, lean, anv):
    P = []  # (lon, lat, rx, ry, zc) in Grad

    def add(plo, pla, r, sq=1.0, z=0.0, kids=True):
        P.append((plo, pla, r, r * sq, z))
        if kids and r > 0.5:
            for _ in range(rng.integers(2, 5)):
                a = rng.uniform(0, 2 * math.pi)
                kr = r * rng.uniform(0.28, 0.48)
                P.append((plo + math.cos(a) * r * 0.82, pla + math.sin(a) * r * 0.82 * sq,
                          kr, kr * sq, z + r * 0.35))

    # Breiter Fuss (Schuerze), dann Saeule, nach oben schlanker.
    for _ in range(int(8 + 1.2 * w)):
        r = w * rng.uniform(0.35, 0.6)
        add(lo + rng.normal(0, w * 0.85), rng.uniform(-0.2, 0.6) * r, r, 0.8, rng.normal(0, w * 0.3))
    nb = int(26 + 3.0 * h)
    for _ in range(nb):
        t = rng.random() ** 0.9 * 0.80
        r = w * rng.uniform(0.30, 0.62) * (1.0 - 0.28 * t)
        x = rng.normal(0, w * (0.50 - 0.18 * t))
        add(lo + lean * t + x, t * h + r * 0.2, r, 1.0, rng.normal(0, w * 0.2))
    # Ueberschiessende Kuppe.
    for _ in range(4):
        r = w * rng.uniform(0.3, 0.45)
        add(lo + lean * 0.85 + rng.normal(0, w * 0.25), h * rng.uniform(0.80, 0.9), r, 0.9, w * 0.3)
    # Amboss: flach, breit, zur Neigungsseite ausgezogen, glatter als der Koerper.
    na = int(22 + 3.0 * anv * w)
    side = 1.0 if lean >= 0 else -1.0
    for _ in range(na):
        s = rng.uniform(-1.0, 1.0)
        s = s + side * 0.4 * abs(s)
        r = w * rng.uniform(0.30, 0.55) * (1.0 - 0.45 * min(abs(s), 1.2))
        add(lo + lean * 0.9 + s * w * anv, h * rng.uniform(0.86, 0.95) - abs(s) * h * 0.035,
            r, 0.32, rng.normal(0, w * 0.15), kids=abs(s) < 0.4)
    return P


def render_towers(W, H, det, seed):
    rng = np.random.default_rng(seed + 303)
    pxa = math.pi / H
    hf = np.full((H, W), -1.0, dtype=F32)     # Hoehe (rad, zum Betrachter)
    al = np.zeros((H, W), dtype=F32)          # Deckung
    hz = np.zeros((H, W), dtype=F32)          # Dunst (Entfernung) je Pixel
    for lo, w, h, lean, anv, haze in TOWERS:
        for plo, pla, rx, ry, zc in tower_puffs(rng, lo, w, h, lean, anv):
            la0 = pla * D2R
            rxr, ryr, z0 = rx * D2R, ry * D2R, zc * D2R
            v0 = (0.5 - la0 / math.pi) * H
            u0 = (plo * D2R / (2 * math.pi) + 0.5) * W
            hh = int(ryr * 1.5 / pxa) + 2
            hw = int(rxr * 1.5 / pxa / max(math.cos(la0 + math.copysign(ryr, la0)), 0.2)) + 2
            ys = np.arange(max(0, int(v0) - hh), min(H, int(v0) + hh + 1))
            if len(ys) == 0:
                continue
            xs = np.arange(int(u0) - hw, int(u0) + hw + 1)
            xw = xs % W
            lat = (0.5 - (ys + 0.5) / H) * math.pi
            lon = ((xs + 0.5) / W - 0.5) * 2 * math.pi
            dx = (lon[None, :] - plo * D2R) * np.cos(lat)[:, None]
            dy = (lat[:, None] - la0) + 0 * dx
            dpat = det[ys[0]:ys[-1] + 1][:, xw]
            qq = np.sqrt((dx / rxr) ** 2 + (dy / ryr) ** 2) * (1.0 + 0.22 * dpat)
            inside = qq < 1.0
            if not inside.any():
                continue
            hgt = (z0 + min(rxr, ryr) * np.sqrt(np.clip(1 - qq * qq, 0, 1))).astype(F32)
            a = smoothstep(1.0, 0.72, qq).astype(F32)
            sub = np.ix_(ys, xw)
            cur = hf[sub]
            win = inside & (hgt > cur)
            hf[sub] = np.where(win, hgt, cur)
            hz[sub] = np.where(win, F32(haze), hz[sub])
            al[sub] = np.maximum(al[sub], a)
    return hf, al, hz


def shade_towers(hf, al, hz, fire, W, H):
    pxa = math.pi / H
    sc = W / 4096.0
    base = np.where(al > 0, hf, 0.0).astype(F32)
    gy, gx = np.gradient(ndimage.gaussian_filter(base, 1.6 * sc + 0.3))
    gx = np.clip(gx / pxa, -4, 4)
    gy = np.clip(-gy / pxa, -4, 4)  # Zeilen laufen nach unten, Breite nach oben
    nl = np.sqrt(gx * gx + gy * gy + 1)
    nx, ny, nzv = -gx / nl, -gy / nl, 1 / nl
    # Licht: Feuer am Horizont (von unten, leicht von vorn), weich umlaufend.
    L = np.array([0.0, -0.80, 0.60])
    ndl = nx * L[0] + ny * L[1] + nzv * L[2]
    diff = np.clip(ndl * 0.6 + 0.4, 0, 1) ** 1.4
    # Ritzen zwischen den Quellwolken dunkler (Hoehen-AO).
    blur = ndimage.gaussian_filter(base, 6.0 * sc + 0.5)
    ao = np.clip(1.0 - (blur - base) / (1.6 * D2R), 0.25, 1.0)
    lat = (0.5 - (np.arange(H, dtype=F32) + 0.5) / H)[:, None] * F32(math.pi)
    up = np.maximum(lat, 0)
    # Feuer strahlt nur von unten: Kuppen bleiben fast schwarze Silhouetten.
    src = (F32(0.008) + F32(1.3) * np.exp(-up / F32(0.05)) + F32(0.03) * np.exp(-up / F32(0.25))) * fire
    e = diff * ao * src
    col = lin(CLOUD_DARK) + ramp([hue(h) for h in CLOUD_HUE], np.clip(e * 1.4, 0, 1) ** 0.7) * (e * F32(0.42))[..., None]
    # Gegenlicht-Rand: duenne, nach unten zeigende Raender lassen das Feuer durch.
    rim = (al * (1 - al) * 4.0) ** 1.2 * src * F32(0.35) * (F32(0.3) + F32(0.7) * np.clip(-ny, 0, 1))
    col += ramp([hue(h) for h in CLOUD_HUE], np.clip(rim * 3, 0, 1)) * rim[..., None]
    return col.astype(F32), ao.astype(F32)


# ---------------------------------------------------------------------------
# Blitzkanaele (Random-Walk mit Verzweigungen), additiv in die Flash-Gruppen
# ---------------------------------------------------------------------------
def draw_bolts(W, H, rng):
    layers = np.zeros((3, H, W), dtype=F32)
    px = math.pi / H

    def stroke(img, lo, la, ang, steps, step, inten, depth):
        for i in range(steps):
            ang += rng.normal(0, 0.6)
            ang = max(-2.5, min(-0.65, ang))  # grob nach unten (-pi/2)
            nlo = lo + math.cos(ang) * step / max(math.cos(la), 0.2)
            nla = la + math.sin(ang) * step
            if nla < 2.0 * D2R or abs(wrap_pi(nlo)) < 12 * D2R:
                break
            seg = max(2, int(step / px * 3))
            t = np.linspace(0, 1, seg, endpoint=False)
            uu = ((lo + (nlo - lo) * t) / (2 * math.pi) + 0.5) * W
            vv = (0.5 - (la + (nla - la) * t) / math.pi) * H
            fade = inten * (1.0 - 0.6 * i / steps)
            x0 = np.floor(uu - 0.5).astype(np.int64)
            y0 = np.floor(vv - 0.5).astype(np.int64)
            fx, fy = uu - 0.5 - x0, vv - 0.5 - y0
            for dx, dy, wt in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)),
                               (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
                yy = np.clip(y0 + dy, 0, H - 1)
                np.add.at(img, (yy, (x0 + dx) % W), (wt * fade).astype(F32))
            if depth < 2 and rng.random() < 0.18:
                stroke(img, nlo, nla, ang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.0),
                       int(steps * rng.uniform(0.15, 0.4)), step * 0.75, inten * 0.5, depth + 1)
            lo, la = nlo, nla

    for grp, lo, la, rad, nb in FLASH_CELLS:
        for _ in range(nb):
            slo = (lo + rng.uniform(-0.4, 0.4) * rad) * D2R
            sla = (la - rng.uniform(0.1, 0.5) * rad) * D2R
            stroke(layers[grp], slo, sla, -math.pi / 2 + rng.normal(0, 0.35),
                   int(rng.integers(30, 55)), 0.26 * D2R, 1.0, 0)
    scale = W / 4096.0
    out = np.zeros_like(layers)
    for g in range(3):
        core = ndimage.gaussian_filter(layers[g], 0.55 * scale + 0.15)
        halo = ndimage.gaussian_filter(layers[g], 6.0 * scale)
        out[g] = core * 1.6 + halo * 10.0
    return out


# ---------------------------------------------------------------------------
# Glut-Ebene: aufsteigende Funken + Bokeh
# ---------------------------------------------------------------------------
def ember_dirs(rng, n):
    # Hoehe: dicht um den Horizont, nach oben/unten duenner; vorn-mitte-unten frei.
    lon = rng.uniform(-math.pi, math.pi, n * 3)
    lat = rng.normal(0.05, 0.30, n * 3)
    keep = np.abs(lat) < 1.3
    front = np.exp(-(lon / 0.6) ** 2) * (lat < 0.12)
    keep &= rng.random(n * 3) > 0.95 * front
    lon, lat = lon[keep][:n], lat[keep][:n]
    cl = np.cos(lat)
    return np.stack([cl * np.sin(lon), np.sin(lat), -cl * np.cos(lon)], -1)


def ember_layer(W, H, seed):
    rng = np.random.default_rng(seed + 501)
    img = np.zeros((H, W, 3), dtype=F32)
    ramp_c = [hue(h) for h in EMBER_HUE]
    px = math.pi / 2048  # Referenz-Texel bei 4096x2048
    n = 1700
    dirs = ember_dirs(rng, n)
    sizes = rng.pareto(3.2, n) + 1.0
    for i in range(n):
        s = min(sizes[i], 4.0)
        r_core = (0.45 + 0.30 * s) * px
        streak = r_core * (rng.uniform(1.0, 1.6) if rng.random() < 0.85 else rng.uniform(2.0, 3.5))
        tilt = rng.normal(0.35, 0.22)  # gemeinsamer Wind + etwas Wirbel
        heat = np.clip(rng.beta(2.2, 3.0) + 0.10 * (s - 1), 0, 0.97)
        inten = (0.25 + 0.75 * rng.random() ** 2.2) * (0.9 + 0.5 * s)
        col = ramp(ramp_c, np.array([heat]))[0] * inten * (0.35 + 1.2 * heat)

        def prof(x, y, r=r_core, st=streak, tl=tilt):
            xr = x - y * tl
            yt = np.where(y > 0, y / r, y / st)  # Kopf oben, Schweif nach unten
            core = np.exp(-(xr / r) ** 2 - yt ** 2)
            glow = np.exp(-(xr / (r * 3.0)) ** 2 - (y / (st * 1.2 + r * 2.5)) ** 2) * 0.05
            return core + glow

        splat(img, dirs[i], max(streak, r_core) * 4.5 + 3 * px, prof, col, W, H)
    nb = 18
    bd = ember_dirs(rng, nb)
    for i in range(nb):
        r = rng.uniform(4, 9) * px
        col = ramp(ramp_c, np.array([rng.uniform(0.0, 0.45)]))[0] * rng.uniform(0.015, 0.04)

        def bprof(x, y, r=r):
            q = np.sqrt(x * x + y * y) / r
            return smoothstep(1.0, 0.80, q) * (0.7 + 0.3 * q * q)

        splat(img, bd[i], r * 1.2, bprof, col, W, H)
    lonv = ((np.arange(W, dtype=F32) + 0.5) / W - 0.5) * F32(2 * math.pi)
    latv = (0.5 - (np.arange(H, dtype=F32) + 0.5) / H) * F32(math.pi)
    lo2, la2 = np.meshgrid(lonv, latv)
    img *= (0.3 + 0.7 * front_mask(lo2, la2))[..., None]
    return img


# ---------------------------------------------------------------------------
# Zusammensetzen
# ---------------------------------------------------------------------------
def build(W, seed, out_dir, preview, jobs):
    H = W // 2
    t0 = time.time()
    s = 7300 + seed * 1000
    rows = max(16, (1 << 19) // W)
    work = [(W, H, r, min(H, r + rows), s) for r in range(0, H, rows)]
    bg = np.zeros((H, W, 3), dtype=F32)
    dc = np.zeros((H, W), dtype=F32)
    det = np.zeros((H, W), dtype=F32)
    fl = np.zeros((3, H, W), dtype=F32)
    fire = np.zeros((H, W), dtype=F32)
    with Pool(jobs) as pool:
        for r0, b, c, dt_, f, fi in pool.imap_unordered(field_rows, work):
            r1 = r0 + b.shape[0]
            bg[r0:r1], dc[r0:r1], det[r0:r1], fl[:, r0:r1], fire[r0:r1] = b, c, dt_, f, fi
    t1 = time.time()

    lonv = ((np.arange(W, dtype=F32) + 0.5) / W - 0.5) * F32(2 * math.pi)
    latv = (0.5 - (np.arange(H, dtype=F32) + 0.5) / H) * F32(math.pi)
    lon, lat = np.meshgrid(lonv, latv)
    up = np.maximum(lat, 0)
    sc = W / 4096.0

    # 1) Ferne Tuerme vor dem Glut-Himmel, mit Luftperspektive.
    hf, al, hz = render_towers(W, H, det, s)
    tcol, tao = shade_towers(hf, al, hz, fire, W, H)
    haze_t = np.clip(0.6 * hz + 0.5 * np.exp(-up / F32(0.04)), 0, 0.9)
    tcol = tcol * (1 - haze_t)[..., None] + bg * (0.9 * haze_t)[..., None]
    sky = bg * (1 - al)[..., None] + tcol * al[..., None]

    # 2) Wolkenbaenke davor: Licht von unten (feine + grobe Selbstabschattung).
    dc = dc * F32(float(os.environ.get("BOSS_DC", "1")))
    tau_f = upward_tau(dc, 6.0 * sc, 1.0 / (6.0 * sc))
    tau_b = upward_tau(dc, 80.0 * sc, 1.0 / (80.0 * sc))
    lit = np.exp(-F32(1.5) * tau_f - F32(0.9) * tau_b)
    src = (F32(0.05) + F32(0.85) * np.exp(-up / F32(0.07)) + F32(0.20) * np.exp(-up / F32(0.35))) * fire
    e = lit * src
    ccol = lin(CLOUD_DARK) + ramp([hue(h) for h in CLOUD_HUE], np.clip(e * 1.4, 0, 1) ** 0.7) * (e * F32(0.40))[..., None]
    calpha = 1 - np.exp(-dc * F32(2.4))
    haze_c = F32(0.6) * np.exp(-up / F32(0.035))
    ccol = ccol * (1 - haze_c)[..., None] + bg * haze_c[..., None]
    sky = sky * (1 - calpha)[..., None] + ccol * calpha[..., None]
    # 3) Ferne Vulkan-Grate als Silhouette vor der Glut (zwei Staffeln), vorn
    #    flach, damit der Fluchtpunkt der Strecke frei bleibt.
    sky = ridges(sky, bg, fire, lonv, latv, s)
    sky *= front_mask(lon, lat)[..., None]

    # 4) Blitz-Licht: Innenleuchten (Tuerme + Baenke), Kanaele, harte Sperre.
    # Quellwolken-Struktur bleibt sichtbar: Kuppen hell, Ritzen dunkel.
    dens = np.clip(al * (0.12 + 0.88 * tao * tao) + (1 - np.exp(-dc * F32(1.6))) * 0.6, 0, 1)
    flash = fl ** F32(1.4) * (F32(0.03) + F32(1.0) * dens)[None]
    bolts = draw_bolts(W, H, np.random.default_rng(s + 77))
    occl = 1 - 0.65 * np.maximum(al, 1 - np.exp(-dc * F32(2.0)))
    flash += bolts * occl[None]
    gate = smoothstep(1.5 * D2R, 4.5 * D2R, lat) * smoothstep(9.0 * D2R, 16.0 * D2R, np.abs(lon))
    flash *= gate[None]

    embers = ember_layer(W, H, s)
    t2 = time.time()

    rng = np.random.default_rng(s + 9)
    os.makedirs(out_dir, exist_ok=True)
    pa = os.path.join(out_dir, "sky_boss.webp")
    pe = os.path.join(out_dir, "sky_boss_embers.webp")
    pf = os.path.join(out_dir, "sky_boss_flash.webp")
    sky_t = tonemap(sky, 1.0)
    emb_t = tonemap(embers, 1.0)
    fl_t = tonemap(np.moveaxis(flash, 0, -1), 1.0)
    Image.fromarray(to_u8(np.sqrt(sky_t), rng)).save(pa, "WEBP", quality=96, method=6)
    Image.fromarray(to_u8(np.sqrt(emb_t), rng)).save(pe, "WEBP", quality=90, method=6)
    Image.fromarray(to_u8(np.sqrt(fl_t), rng)).save(pf, "WEBP", quality=90, method=6)
    print("boss: %dx%d  fields %.1f s  compose %.1f s  sky %.2f MB  embers %.2f MB  flash %.2f MB" % (
        W, H, t1 - t0, t2 - t1, os.path.getsize(pa) / 1e6, os.path.getsize(pe) / 1e6,
        os.path.getsize(pf) / 1e6), flush=True)

    if preview:
        os.makedirs(preview, exist_ok=True)
        dec = [srgb_to_lin(np.asarray(Image.open(f).convert("RGB"), dtype=np.float64) / 255.0) ** 2
               for f in (pa, pe, pf)]
        for name, pitch, yaw, fov, fgain in (("cam", -16.0, 0.0, 62.0, 0.0),
                                             ("cam_flash", -16.0, 0.0, 62.0, 1.0),
                                             ("cam_flash2", -16.0, 0.0, 62.0, 2.0),
                                             ("cam_flash3", -16.0, 0.0, 62.0, 3.0),
                                             ("cam_up", 10.0, 0.0, 80.0, 0.0),
                                             ("cam_back", 8.0, 180.0, 80.0, 1.0)):
            # fgain = Blitz-Gruppe 1..3 (0 = kein Blitz), wie Shader lightning_cell.
            v = view(dec, W, H, pitch, yaw, fov, fgain)
            Image.fromarray(to_u8(np.clip(v, 0, 1), rng)).save(os.path.join(preview, "boss_%s.png" % name))
        small = Image.fromarray(to_u8(np.clip(sky_t + emb_t, 0, 1), rng)).resize((2048, 1024), Image.LANCZOS)
        small.save(os.path.join(preview, "boss_pano.png"))
        fsmall = Image.fromarray(to_u8(np.clip(fl_t, 0, 1), rng)).resize((2048, 1024), Image.LANCZOS)
        fsmall.save(os.path.join(preview, "boss_flash_pano.png"))


FLASH_RGB = np.array(hexcol("#d88c8c"))  # stumpfes Rot-Weiss (wie Shader lightning_color)


def view(dec, W, H, pitch, yaw, fov, fgain, vw=960, vh=540):
    th = math.tan(math.radians(fov) * 0.5)
    ys, xs = np.mgrid[0:vh, 0:vw].astype(np.float64)
    x = (2 * (xs + 0.5) / vw - 1) * th * vw / vh
    y = (1 - 2 * (ys + 0.5) / vh) * th
    z = -np.ones_like(x)
    p = math.radians(pitch)
    y2 = y * math.cos(p) - z * math.sin(p)
    z2 = y * math.sin(p) + z * math.cos(p)
    a = math.radians(yaw)
    x3 = x * math.cos(a) - z2 * math.sin(a)
    z3 = x * math.sin(a) + z2 * math.cos(a)
    d = np.stack([x3, y2, z3], -1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    u, v = dir_to_px(d, W, H)
    out = np.zeros((vh, vw, 3))

    def samp(img, ch):
        return ndimage.map_coordinates(img[..., ch], [v - 0.5, u - 0.5], order=1, mode="grid-wrap")
    for ch in range(3):
        out[..., ch] = samp(dec[0], ch) + samp(dec[1], ch)
    if fgain > 0:
        f = samp(dec[2], int(fgain) - 1)
        out += f[..., None] * FLASH_RGB * 1.6
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--width", type=int, default=4096)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default="", help="Ordner fuer Kamera-/Panorama-PNGs")
    ap.add_argument("--jobs", type=int, default=6)
    a = ap.parse_args()
    build(a.width, a.seed, a.out, a.preview, a.jobs)


if __name__ == "__main__":
    main()
