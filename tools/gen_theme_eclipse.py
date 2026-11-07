#!/usr/bin/env python3
"""TETHRA Welt-Thema "Eklipse": schwarze Sonne ueber verbrannter Ebene.

Duester, gefaehrlich, fast farblos: nur Schwarz/Anthrazit und ein mattes
Gold-Weiss (Korona). Kein Neon, keine Glut.

Erzeugt nach assets_game/themes/eclipse/:
  eclipse_sky.webp  4096x2048 equirektangulares Panorama (RGBA)
      - fast schwarzer Himmel, wenige schwache Sterne
      - riesige schwarze Sonne vorn knapp ueber dem Horizont, duenne kalte
        weiss-goldene Korona (Helm-Streamer seitlich, feine Polfahnen),
        feine Protuberanzen am Rand
      - aufsteigende Asche-/Rauchschleier (vor der Korona, gegenlicht-beleuchtet)
      - Horizont: verbrannte Ebene mit Rissen, zerfallene Ruinen in drei
        Tiefenlagen (ferne im Dunst, nahe schwarz mit Gegenlicht-Kante,
        Fensterhoehlen, durch die die Korona scheint)
      - Alpha = freier Himmel (1) / Ruinen+Boden (0): der Shader zeichnet
        Sonnenrand und Diamantring nur dort.
  eclipse_ash.webp  4096x1024, in beiden Richtungen kachelbar, fuer Parallax:
      RGB (grau) = Ascheflocken, Alpha = weiche Rauchschwaden (lineare Daten).
      shaders/theme_eclipse.gdshader bildet es zylindrisch ab und laesst es
      aufsteigen.

Abbildung identisch zu shaders/sky_panorama.gdshader:
  u = atan(d.x, -d.z) / 2pi + 0.5   (u=0.5 = vorn, -Z)
  v = 0.5 - asin(d.y) / pi          (v=0 = Zenit)
Panorama wurzel-kodiert (gespeichert sqrt(linear) als sRGB), Shader dekodiert
mit textur^2. Sonnen-Lage SUN_LAT/SUN_R muss zu sun_lat/sun_radius im Shader
passen.

Reproduzierbar per Seed:
  python tools/gen_theme_eclipse.py                       # 4096x2048
  python tools/gen_theme_eclipse.py --width 2048 --preview <ordner>
  python tools/gen_theme_eclipse.py --seed 7              # andere Ruinen/Sterne
--preview schreibt die Komfort-Kamera-Ansicht (fov 62, Neigung -16), eine
Seitenansicht und eine verkleinerte Gesamtansicht als PNG.
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
OUT_DIR = os.path.join(ROOT, "assets_game", "themes", "eclipse")

# Sonne (Grad): vorn, Unterkante knapp hinter dem Horizont.
SUN_LON = 0.0
SUN_LAT = 5.0
SUN_R = 6.5
GROUND_H = 3.7  # Kamera ueber der Ebene (mania_3d: Kamera 2.1, Strecke -1.6)


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


def fbm2(rng, H, W, base=(3, 6), octaves=7, gain=0.55):
    """Periodisches fbm (wickelt in beiden Richtungen um), Mittel 0, ~Std 0.5."""
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


def sample_wrap(tex, rows, cols):
    """Bilinear, wickelt in beiden Richtungen (Texturkoordinaten in Pixeln)."""
    return ndimage.map_coordinates(tex, [rows, cols], order=1, mode="grid-wrap").astype(F32)


def ihash(*a):
    """Ganzzahl-Hash -> [0,1) (vektorisiert)."""
    h = np.uint64(1469598103934665603)
    with np.errstate(over="ignore"):
        for x in a:
            x = np.asarray(x).astype(np.int64).astype(np.uint64)
            h = (h ^ x) * np.uint64(1099511628211)
            h ^= h >> np.uint64(29)
            h = h * np.uint64(0x9E3779B97F4A7C15)
            h ^= h >> np.uint64(32)
    return ((h >> np.uint64(11)) & np.uint64(0xFFFFF)).astype(np.float64) / float(0x100000)


# ---------------------------------------------------------------------------
# Farben (sRGB-Hex -> linear). Nur Anthrazit + mattes Gold-Weiss.
WHITE_GOLD = hexcol("#fff3da")   # innere Korona, Sonnenrand
PALE_GOLD = hexcol("#e9d6ad")    # Streamer
MATTE_GOLD = hexcol("#b49660")   # aeussere Korona, Gegenlicht auf Asche
ASH = hexcol("#9a948a")          # beleuchtete Asche (neutral-warmgrau)
ANTHRACITE = hexcol("#1c1c1e")   # Grundton Himmel/Dunst
STAR = hexcol("#e8e6e0")


class Pano:
    def __init__(self, W):
        self.W, self.H = W, W // 2
        self.ppd = W / 360.0  # Pixel pro Grad
        v = (np.arange(self.H) + 0.5) / self.H
        u = (np.arange(self.W) + 0.5) / self.W
        self.lat = ((0.5 - v) * 180.0).astype(F32)  # Grad, +oben
        self.lon = ((u - 0.5) * 360.0).astype(F32)  # Grad, 0 = vorn
        self.img = np.zeros((self.H, self.W, 3), F32)
        self.occ = np.zeros((self.H, self.W), F32)  # 1 = Ruine/Boden
        la = np.radians(self.lat)[:, None]
        lo = np.radians(self.lon)[None, :]
        self.dx = (np.sin(lo) * np.cos(la)).astype(F32)
        self.dy = np.broadcast_to(np.sin(la), (self.H, self.W)).astype(F32)
        self.dz = (-np.cos(lo) * np.cos(la)).astype(F32)
        # Sonnen-Koordinaten: Winkelabstand theta (Grad), Positionswinkel phi
        # (rad, 0 = rechts, +pi/2 = oben), r = theta / SUN_R.
        sl, so = math.radians(SUN_LAT), math.radians(SUN_LON)
        s = np.array([math.sin(so) * math.cos(sl), math.sin(sl), -math.cos(so) * math.cos(sl)])
        e_east = np.array([math.cos(so), 0.0, math.sin(so)])
        e_north = np.array([-math.sin(so) * math.sin(sl), math.cos(sl), math.cos(so) * math.sin(sl)])
        ch = np.sqrt((self.dx - s[0]) ** 2 + (self.dy - s[1]) ** 2 + (self.dz - s[2]) ** 2)
        self.theta = np.degrees(2.0 * np.arcsin(np.clip(ch * 0.5, 0, 1))).astype(F32)
        px = self.dx * e_east[0] + self.dy * e_east[1] + self.dz * e_east[2]
        py = self.dx * e_north[0] + self.dy * e_north[1] + self.dz * e_north[2]
        self.phi = np.arctan2(py, px).astype(F32)
        self.r = (self.theta / SUN_R).astype(F32)

    def row(self, lat):
        return int(round((0.5 - lat / 180.0) * self.H))


def backlight(P):
    """Gegenlicht der Korona (0..1), fuer Asche, Kanten, Dunst."""
    return (np.exp(-np.maximum(P.theta - SUN_R, 0) / 9.0) * 0.75
            + np.exp(-P.theta / 38.0) * 0.25).astype(F32)


# ---------------------------------------------------------------------------
def paint_sky(P, rng):
    lat = P.lat[:, None]
    up = np.clip(lat, 0, 90)
    base = 0.0011 + 0.0042 * np.exp(-up / 11.0) + 0.0016 * np.exp(-up / 40.0)
    # Schwaches Streulicht der Korona in der Atmosphaere (breit, warm).
    glow = 0.022 * np.exp(-P.theta / 13.0) + 0.006 * np.exp(-P.theta / 45.0)
    glow *= np.exp(-up / 30.0) * 0.6 + 0.4
    # Hoher Dunst: grossflaechig, leicht ungleichmaessig.
    n = fbm2(rng, 256, 512, base=(2, 4), octaves=6)
    n = sample_wrap(n, (np.arange(P.H)[:, None] + 0.5) / P.H * 256 - 0.5 + 0 * P.lon[None, :],
                    (np.arange(P.W)[None, :] + 0.5) / P.W * 512 - 0.5 + 0 * lat)
    mod = 1.0 + 0.35 * n
    P.img += (base * mod)[..., None] * ANTHRACITE / ANTHRACITE.max()
    P.img += glow[..., None] * mix3(MATTE_GOLD, ANTHRACITE, 0.35) * mod[..., None]


def mix3(a, b, t):
    return (a * (1 - t) + b * t).astype(F32)


def paint_stars(P, rng):
    W, H = P.W, P.H
    n = int(1700 * (W / 4096.0) ** 0.5)
    z = rng.uniform(math.sin(math.radians(3.0)), 1.0, n)
    lat = np.degrees(np.arcsin(z))
    lon = rng.uniform(-180.0, 180.0, n)
    b = (rng.pareto(2.2, n) + 1.0) * 0.010
    b = np.minimum(b, 0.22)
    # Nahe Korona/Horizont verschluckt Sterne.
    sl, so = math.radians(SUN_LAT), math.radians(SUN_LON)
    la, lo = np.radians(lat), np.radians(lon)
    cosd = np.sin(la) * math.sin(sl) + np.cos(la) * math.cos(sl) * np.cos(lo - so)
    th = np.degrees(np.arccos(np.clip(cosd, -1, 1)))
    b *= smoothstep(4.0, 20.0, lat) * smoothstep(SUN_R * 2.2, SUN_R * 5.0, th)
    b *= 0.5 + 0.5 * rng.random(n)
    tints = np.stack([STAR, hexcol("#dfe3ea"), hexcol("#efe4cf")])
    cols = tints[rng.choice(3, n, p=[0.6, 0.25, 0.15])]
    x = (lon / 360.0 + 0.5) * W - 0.5
    y = (0.5 - lat / 180.0) * H - 0.5
    cl = np.maximum(np.cos(np.radians(lat)), 0.25)
    flat = P.img.reshape(-1, 3)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    parts, acc = [], np.zeros(n)
    sig = 0.55 * W / 4096.0 + 0.25
    for dy in range(-2, 4):
        for dx in range(-2, 4):
            px, py = x0 + dx, y0 + dy
            w = np.exp(-(((px - x) * cl) ** 2 + (py - y) ** 2) / (2 * sig * sig))
            acc += w
            parts.append((px, py, w))
    for px, py, w in parts:
        ok = (py >= 0) & (py < H)
        idx = py[ok] * W + (px[ok] % W)
        np.add.at(flat, idx, ((b[ok] * w[ok] / acc[ok])[:, None] * cols[ok]).astype(F32))


def paint_corona(P, rng):
    """Schwarze Sonne + Korona + Protuberanzen (nur Bereich um die Sonne)."""
    r = P.r
    sel = P.theta < SUN_R * 9.0
    rr = np.maximum(r[sel], 1.0)
    phi = P.phi[sel]
    rho = np.log(rr)

    # Streamer-Rauschen in (log r, phi): fein in phi, grob radial.
    NR, NP = 64, 1536
    sn = fbm2(rng, NR, NP, base=(2, 24), octaves=6, gain=0.6)
    fr = fbm2(rng, 16, 4096, base=(1, 96), octaves=5, gain=0.7)
    bend = phi + 0.10 * np.sin(2.0 * phi + 0.7) * rho  # leicht gekruemmte Streamer
    pc = (bend / (2 * np.pi) % 1.0) * NP - 0.5
    rc = np.clip(rho / math.log(9.0), 0, 1) * (NR - 3) + 0.5
    s1 = np.clip(0.5 + 1.15 * sample_wrap(sn, rc, pc), 0, 1) ** 2
    pr = (phi / (2 * np.pi) % 1.0) * 4096 - 0.5
    rays = np.clip(0.5 + 1.4 * sample_wrap(fr, np.clip(rho * 3.0, 0, 13), pr), 0, 1) ** 3

    eq = math.radians(8.0)  # Korona-Aequator leicht geneigt
    E = np.abs(np.cos(phi - eq)) ** 3
    k_in = rr ** -16.0 * 0.85 + rr ** -6.0 * 0.12
    mid = rr ** -(3.0 - 1.2 * E) * (0.03 + 0.70 * s1 ** 1.4) * 0.34
    plumes = rr ** -3.6 * rays * 0.17 * (1.0 - 0.7 * E)
    helm = np.zeros_like(rr)
    for ang, amp, wid in ((8, 1.0, 26), (188, 0.85, 30), (-28, 0.45, 12),
                          (158, 0.40, 14), (40, 0.30, 9), (222, 0.35, 11)):
        d = np.angle(np.exp(1j * (phi - math.radians(ang))))
        w = math.radians(wid) * (1.5 / (rr + 0.5)) ** 0.9  # verjuengt sich nach aussen
        helm += amp * np.exp(-(d / w) ** 2)
    helm = helm * rr ** -2.15 * 0.30 * (0.55 + 0.45 * s1)
    I = (k_in + mid + plumes + helm) * np.exp(-(rr - 1.0) / 4.5)
    col_t = smoothstep(1.02, 3.2, rr)[:, None]
    tint = WHITE_GOLD * (1 - col_t) + mix3(PALE_GOLD, MATTE_GOLD, 0.55) * col_t
    tint = tint * (1 - smoothstep(0.6, 1.0, col_t)) + MATTE_GOLD * smoothstep(0.6, 1.0, col_t)
    add = (I[:, None] * tint).astype(F32)

    # Protuberanzen: kurze Flammen/Boegen am Rand.
    prom = np.zeros_like(rr)
    pn = fbm2(rng, 64, 2048, base=(4, 64), octaves=4, gain=0.6)
    pv = sample_wrap(pn, np.clip((rr - 1.0) * 400, 0, 62), (phi / (2 * np.pi) % 1.0) * 2048)
    for k in range(9):
        ang = rng.uniform(-math.pi, math.pi)
        hgt = rng.uniform(0.035, 0.11)
        wid = rng.uniform(0.04, 0.12)
        d = np.angle(np.exp(1j * (phi - ang)))
        if rng.random() < 0.35:
            # Bogen: Ring-Segment zwischen zwei Fusspunkten.
            t = d / wid
            arc_h = hgt * np.sqrt(np.clip(1 - t * t, 0, 1))
            band = np.exp(-((rr - 1.0 - arc_h) / 0.006) ** 2) * (np.abs(t) < 1)
            prom += band * rng.uniform(0.5, 0.9)
        else:
            env = np.exp(-(d / wid) ** 2)
            h = hgt * env * (0.6 + 0.6 * np.clip(pv + 0.5, 0, 1))
            body = smoothstep(0.0, 0.25, h - (rr - 1.0)) * (rr >= 1.0)
            prom += body * env * rng.uniform(0.6, 1.1)
    # Feiner Saum aller Protuberanzen + Chromosphaeren-Faden.
    fringe = np.exp(-np.maximum(rr - 1.0, 0) / 0.010) * (0.5 + 0.5 * np.clip(pv + 0.6, 0, 1))
    prom = np.clip(prom, 0, 1.2) * 0.9 + fringe * 0.55
    add += (prom[:, None] * WHITE_GOLD).astype(F32)

    img = P.img.reshape(-1, 3)
    idx = np.flatnonzero(sel)
    # Schwarze Scheibe deckt alles dahinter ab (Hauch von Erdschein).
    aa = smoothstep(1.0 - 0.6 / (SUN_R * P.ppd), 1.0 + 0.6 / (SUN_R * P.ppd), r[sel])
    base = img[idx] * aa[:, None] + (1 - aa[:, None]) * 0.0012 * ANTHRACITE / ANTHRACITE.max()
    img[idx] = base + add * aa[:, None]


def paint_veils(P, rng, plumes):
    """Aufsteigende Asche-/Rauchschleier, vor Korona und fernen Ruinen."""
    lat = P.lat[:, None]
    up = np.clip(lat, -2, 90)
    n = fbm2(rng, 512, 1024, base=(3, 12), octaves=7, gain=0.58)
    warp = fbm2(rng, 128, 256, base=(2, 4), octaves=4)
    rows = (np.arange(P.H)[:, None] + 0.5) / P.H * 512 - 0.5
    cols = (np.arange(P.W)[None, :] + 0.5) / P.W * 1024 - 0.5
    wv = sample_wrap(warp, rows / 4 + 0 * cols, cols / 4 + 0 * rows)
    nv = sample_wrap(n, rows + wv * 30 + 0 * cols, cols + wv * 18 + 0 * rows)
    # Schichtdichte: dicht am Horizont, nach oben duenner.
    layer = np.exp(-np.maximum(up, 0) / 9.0) * 0.55 + np.exp(-np.maximum(up, 0) / 26.0) * 0.18
    dens = np.clip(nv * 1.3 + 0.15, 0, 1) ** 1.6 * layer
    # Rauchsaeulen aus den Ruinen: verbreitern sich, neigen sich mit der Hoehe.
    for lon0, strength, lean in plumes:
        hgt = np.maximum(up, 0)
        c = lon0 + lean * hgt ** 1.25
        w = 0.8 + 0.20 * hgt
        dlon = (P.lon[None, :] - c + 180.0) % 360.0 - 180.0
        col = np.exp(-(dlon / w) ** 2) * np.exp(-hgt / 22.0) * smoothstep(-0.5, 1.5, lat)
        tur = np.clip(0.55 + nv * 1.2, 0, 1.4)
        dens = dens + col * tur * strength
    dens = (np.clip(dens, 0, 1) * smoothstep(-3.0, 0.0, lat)).astype(F32)
    bl = backlight(P)
    occl = 0.62 * dens
    lit = dens * (0.0028 + 0.050 * bl ** 1.5)
    tint = mix3(MATTE_GOLD, ASH, 0.5)
    P.img *= (1.0 - occl)[..., None]
    P.img += lit[..., None] * tint


# ---------------------------------------------------------------------------
# Ruinen: Silhouetten in einem hochaufgeloesten Horizontband (4x supersampled).
class Band:
    def __init__(self, P, lat_top, lat_bot, ss=4):
        self.P, self.ss = P, ss
        self.r0 = P.row(lat_top)
        self.r1 = P.row(lat_bot)
        self.h = (self.r1 - self.r0) * ss
        self.w = P.W * ss
        self.lat = (0.5 - (self.r0 + (np.arange(self.h) + 0.5) / ss) / P.H) * 180.0
        self.dpp = 360.0 / self.w  # Grad pro Hi-Res-Pixel

    def new(self):
        return np.zeros((self.h, self.w), bool)

    def region(self, lon0, lon1):
        c0 = int(math.floor((lon0 / 360.0 + 0.5) * self.w))
        c1 = int(math.ceil((lon1 / 360.0 + 0.5) * self.w))
        cols = np.arange(c0, c1)
        lon = (cols + 0.5) / self.w * 360.0 - 180.0
        return cols % self.w, lon

    def down(self, m):
        ss = self.ss
        return m.reshape(self.h // ss, ss, self.w // ss, ss).mean(axis=(1, 3)).astype(F32)


def draw_building(B, m, rng, c, w, h, kind, base=0.0, holes=0.0, lean=0.0):
    cols, lon = B.region(c - w * 0.8 - abs(lean) * h - 0.3, c + w * 0.8 + abs(lean) * h + 0.3)
    Y = B.lat[:, None] - base
    X = (lon[None, :] - c) - Y * lean
    hw = w * 0.5
    inside = (np.abs(X) < hw) & (Y > 0)
    if kind == "block":
        # Gebrochene Oberkante: stueckweise lineare Bruchlinie mit Zacken.
        k = rng.integers(3, 7)
        kx = np.linspace(-hw, hw, k)
        ky = h * rng.uniform(0.55, 1.0, k)
        ky[rng.integers(0, k)] = h
        top = np.interp(X, kx, ky) - 0.12 * h * (ihash(np.floor(X / (B.dpp * 6)).astype(np.int64) + 77, k) ** 4)
        inside &= Y < top
        tops = top
    elif kind == "spire":
        prof = hw * np.clip(1.0 - Y / h, 0, 1) ** 0.6
        cut = h * rng.uniform(0.7, 0.95) + X * rng.uniform(-0.6, 0.6)
        inside = (np.abs(X) < prof) & (Y < cut) & (Y > 0)
        tops = cut
    elif kind == "frame":
        # Skelett: Pfeiler + Geschoss-Traeger, teils eingestuerzt.
        pil = w * 0.11
        cut = h * rng.uniform(0.75, 1.0) - (X + hw) * rng.uniform(0.0, 0.5) * h / w
        p = (np.abs(X + hw - pil * 0.5) < pil * 0.5) | (np.abs(X - hw + pil * 0.5) < pil * 0.5)
        nmid = rng.integers(0, 3)
        for j in range(nmid):
            xm = -hw + w * (j + 1) / (nmid + 1)
            p |= np.abs(X - xm) < pil * 0.35
        floor_h = rng.uniform(0.45, 0.75)
        fl = (Y % floor_h) < floor_h * 0.16
        fl &= ihash(np.floor(Y / floor_h).astype(np.int64), int(c * 100)) > 0.25
        broken = ihash(np.floor(Y / floor_h).astype(np.int64), np.floor((X + hw) / (w * 0.5)).astype(np.int64) + 9) < 0.3
        inside &= (p | (fl & ~broken)) & (Y < cut)
        inside |= (np.abs(X) < hw) & (Y < 0.25 * floor_h) & (Y > 0)
        tops = cut
    elif kind == "arch":
        top = h - 0.15 * h * (ihash(np.floor(X / (B.dpp * 8)).astype(np.int64), 5) ** 3)
        ow = hw * rng.uniform(0.45, 0.65)
        oh = h * rng.uniform(0.45, 0.65)
        opening = (np.abs(X) < ow) & ((Y < oh) | ((X / ow) ** 2 + ((Y - oh) / (ow * 0.9)) ** 2 < 1.0))
        inside &= (Y < top) & ~opening
        tops = top
    else:  # rubble / column
        top = h * np.clip(1 - (X / hw) ** 2, 0, 1) ** 0.8 * (0.6 + 0.4 * ihash(np.floor(X / (B.dpp * 5)).astype(np.int64), 3))
        inside &= Y < top
        tops = top
    if holes > 0 and kind in ("block", "arch"):
        px, py = rng.uniform(0.22, 0.34), rng.uniform(0.32, 0.5)
        ix = np.floor((X + hw) / px).astype(np.int64)
        iy = np.floor(Y / py).astype(np.int64)
        fx = ((X + hw) / px) % 1.0
        fy = (Y / py) % 1.0
        win = (fx > 0.3) & (fx < 0.75) & (fy > 0.25) & (fy < 0.8) & (ihash(ix, iy, int(c * 37)) < holes)
        win &= (Y > py) & (Y < np.asarray(tops) - py * 0.6) & (np.abs(X) < hw - px * 0.4)
        inside &= ~win
    sub = m[:, cols]
    sub |= inside
    m[:, cols] = sub


def build_layer(B, rng, spec, debris=0.0):
    m = B.new()
    for b in spec:
        draw_building(B, m, rng, *b)
    if debris > 0:
        # Durchgehende Schuttkante: zerklueftet, mit Stahltraeger-Spitzen.
        lon = (np.arange(B.w) + 0.5) / B.w * 360.0 - 180.0
        f = fbm1(rng, B.w, base=24, octaves=10, gain=0.62)
        prof = np.clip(0.45 + f, 0, 1.2) ** 1.4 * debris
        spikes = ihash(np.arange(B.w) // 6, 404) ** 60 * debris * 2.2
        prof = np.maximum(prof, spikes) * (0.55 + 0.45 * smoothstep(3.0, 14.0, np.abs(lon)))
        m |= B.lat[:, None] < (prof - 0.25)[None, :]
    return B.down(m)


def ruin_specs(rng):
    """Drei Tiefenlagen (fern, mitte, nah); Mitte vorn bleibt niedrig."""
    far, mid, near = [], [], []
    lon = -180.0
    while lon < 180.0:
        w = rng.uniform(0.35, 1.6)
        c = lon + w * 0.5
        a = abs(c)
        h = rng.uniform(0.4, 2.3) * (0.35 if a < 11 else 1.0)
        if rng.random() < 0.8:
            kind = rng.choice(["block", "block", "spire", "rubble", "frame"])
            far.append((c, w, h, kind, -0.06, 0.0, rng.uniform(-0.05, 0.05)))
        lon += w * rng.uniform(0.7, 1.6)
    lon = -180.0
    while lon < 180.0:
        w = rng.uniform(0.6, 2.4)
        c = lon + w * 0.5
        a = abs(c)
        lon += w * rng.uniform(0.9, 2.3)
        if a < 12.0:
            if rng.random() < 0.6:
                mid.append((c, w * 1.6, rng.uniform(0.35, 0.8), "rubble", -0.2, 0.0, 0.0))
            continue
        h = rng.uniform(1.0, 4.8) * (0.5 + 0.5 * smoothstep(12, 30, a))
        kind = rng.choice(["block", "block", "frame", "spire", "arch", "rubble"])
        lean = rng.uniform(-0.12, 0.12) if rng.random() < 0.3 else 0.0
        mid.append((c, w, h, kind, -rng.uniform(0.12, 0.35), 0.42, lean))
    # Nahe Wracks: wenige, gross, nur seitlich und hinten.
    for c, w, h, kind, lean in ((-37.5, 3.4, 8.2, "frame", 0.10), (-29.0, 1.6, 3.2, "block", 0.0),
                                (31.0, 4.4, 5.6, "arch", 0.0), (41.5, 1.5, 7.4, "spire", -0.05),
                                (-62.0, 5.0, 4.5, "block", 0.0), (72.0, 3.6, 9.0, "frame", -0.06),
                                (118.0, 4.0, 6.0, "arch", 0.0), (-128.0, 3.0, 7.5, "spire", 0.0),
                                (160.0, 6.0, 3.6, "block", 0.0), (-165.0, 3.2, 5.2, "frame", 0.08),
                                (-88.0, 2.2, 2.4, "rubble", 0.0), (95.0, 3.0, 2.0, "rubble", 0.0),
                                (-23.5, 2.0, 3.6, "block", 0.0), (24.5, 1.1, 3.1, "frame", 0.07),
                                (-45.0, 2.6, 5.2, "arch", 0.0), (17.0, 0.7, 1.9, "spire", 0.0)):
        near.append((c, w, h, kind, -0.6, 0.5, lean))
    for c in (-20.0, 20.5, -50.0, 55.0):
        near.append((c, rng.uniform(4, 7), rng.uniform(1.0, 1.6), "rubble", -0.7, 0.0, 0.0))
    return far, mid, near


def paint_ruins(P, rng):
    B = Band(P, 12.5, -2.6, ss=4)
    far_s, mid_s, near_s = ruin_specs(rng)
    rows = slice(B.r0, B.r1)
    img = P.img[rows]
    bl = backlight(P)[rows]
    lat = P.lat[rows][:, None]

    def rim_of(m):
        er = ndimage.minimum_filter(m, size=3, mode="wrap")
        return np.clip(m - er, 0, 1)

    # Ferne Lage: im Dunst, etwas heller als die nahen (Luftperspektive).
    m = build_layer(B, np.random.default_rng(rng.integers(1 << 30)), far_s)
    haze = (0.0040 + 0.016 * bl ** 1.4)[..., None] * mix3(ASH, MATTE_GOLD, 0.5)
    img[:] = img * (1 - m[..., None]) + haze * m[..., None]
    P.occ[rows] = np.maximum(P.occ[rows], m)
    # Horizont-Dunst vor den fernen Ruinen.
    hz = np.exp(-np.abs(lat) / 1.4) * (0.0025 + 0.030 * bl ** 2)
    img += hz[..., None] * mix3(PALE_GOLD, ASH, 0.5)

    for spec, dark, rim_k, deb in ((mid_s, 0.0018, 0.11, 0.55), (near_s, 0.0006, 0.16, 0.0)):
        m = build_layer(B, np.random.default_rng(rng.integers(1 << 30)), spec, deb)
        rim = rim_of(m) * (lat > -0.2)
        fill = dark * (1 + 2.0 * bl)
        img[:] = img * (1 - m[..., None]) + (fill[..., None] * ANTHRACITE / ANTHRACITE.max()) * m[..., None]
        img += (rim * rim_k * bl ** 1.6)[..., None] * mix3(WHITE_GOLD, MATTE_GOLD, 0.4)
        P.occ[rows] = np.maximum(P.occ[rows], m)
    P.img[rows] = img


def paint_ground(P, rng):
    """Verbrannte Ebene: Schollen mit Rissen, Dunst am Horizont, matter Schein."""
    r0 = P.row(0.0)
    lat = P.lat[r0:][:, None]
    dy = -np.sin(np.radians(np.minimum(lat, -0.02)))
    t = GROUND_H / dy
    lo = np.radians(P.lon)[None, :]
    cl = np.cos(np.radians(lat))
    gx = np.sin(lo) * cl * t
    gz = -np.cos(lo) * cl * t
    # Verzerrte Koordinaten: Schollen unregelmaessig, keine Fliesen.
    wn = fbm2(rng, 256, 256, base=(4, 4), octaves=5)
    wx = sample_wrap(wn, gz / 3.1, gx / 3.1)
    wz = sample_wrap(wn, gz / 3.1 + 97.0, gx / 3.1 + 41.0)
    gxw, gzw = gx + wx * 1.6, gz + wz * 1.6
    pixang = math.pi / P.H
    footprint = t / np.maximum(dy, 1e-3) * pixang  # Bodenlaenge je Pixel

    def worley(cell, seed_k):
        px, pz = gxw / cell, gzw / cell
        ix, iz = np.floor(px), np.floor(pz)
        f1 = np.full(px.shape, 9.0, F32)
        f2 = np.full(px.shape, 9.0, F32)
        idv = np.zeros(px.shape, F32)
        for ox in (-1, 0, 1):
            for oz in (-1, 0, 1):
                cx, cz = (ix + ox).astype(np.int64), (iz + oz).astype(np.int64)
                hx = ihash(cx, cz, 11 + seed_k)
                hz = ihash(cx, cz, 23 + seed_k)
                d = np.sqrt((cx + hx - px) ** 2 + (cz + hz - pz) ** 2).astype(F32)
                closer = d < f1
                f2 = np.where(closer, f1, np.minimum(f2, d))
                idv = np.where(closer, ihash(cx, cz, 5 + seed_k), idv)
                f1 = np.where(closer, d, f1)
        fw = (footprint / cell).astype(F32)
        wcr = 0.03
        crack = 1.0 - smoothstep(wcr * 0.2, wcr + fw, f2 - f1)
        crack *= 1.0 - smoothstep(0.06, 0.4, fw)
        return crack.astype(F32), idv

    crack1, idv = worley(3.2, 0)
    crack2, idv2 = worley(1.05, 50)
    crack = np.maximum(crack1, crack2 * 0.55 * (idv > 0.35))
    n = fbm2(rng, 512, 512, base=(4, 4), octaves=7)
    nv = sample_wrap(n, gz / 1.7, gx / 1.7)
    nv *= 1.0 - smoothstep(0.1, 0.6, footprint / 1.7)
    albedo = (0.0013 + 0.0016 * idv + 0.0005 * idv2) * (1.0 + 0.5 * nv)
    albedo *= 1.0 - 0.55 * crack
    # Brandflecken: grossflaechig dunkler, Naehe zur Kamera im Schatten.
    burn = sample_wrap(wn, gz / 14.0 + 31.0, gx / 14.0 + 7.0)
    albedo *= np.clip(0.75 + 0.6 * burn, 0.35, 1.3) * (0.55 + 0.45 * smoothstep(3.0, 30.0, np.sqrt(gx ** 2 + gz ** 2)))
    # Ascheflecken (hellere Verwehungen).
    ash = np.clip(nv * 1.6 - 0.45, 0, 1) * 0.0016
    gcol = (albedo + ash)[..., None] * ANTHRACITE / ANTHRACITE.max()
    # Matter Schein der Korona (keine Spiegelung, breit) + Horizont-Dunst.
    dist = np.sqrt(gx ** 2 + gz ** 2)
    sheen = 0.010 * np.exp(-(P.lon[None, :] / 26.0) ** 2) * np.exp(-dist / 140.0) * (0.6 + 0.4 * idv)
    sheen *= 1.0 - 0.8 * crack
    gcol += sheen[..., None] * mix3(MATTE_GOLD, ASH, 0.4)
    fog = np.exp(lat / 0.7).astype(F32)
    bl0 = backlight(P)[r0][None, :]
    hcol = ((0.0045 + 0.020 * bl0 ** 1.4)[..., None] * mix3(ASH, MATTE_GOLD, 0.5))
    gcol = gcol * (1 - fog[..., None]) + hcol * fog[..., None]
    P.img[r0:] = gcol
    P.occ[r0:] = 1.0


# ---------------------------------------------------------------------------
def build_ash(W, seed):
    """Kachelbare Asche-Ebene (W x W/4): RGB-Grau = Flocken, A = Schwaden."""
    rng = np.random.default_rng(seed)
    H = W // 4
    flakes = np.zeros((H, W), F32)
    n = int(5200 * (W / 4096.0) ** 2)
    k = W / 4096.0
    xs = rng.uniform(0, W, n)
    ys = rng.uniform(0, H, n)
    size = (rng.pareto(2.6, n) + 1.0) * 0.75 * k
    size = np.minimum(size, 7.0 * k)
    bright = rng.uniform(0.35, 1.0, n) * np.where(size > 3.0 * k, 0.55, 1.0)
    ang = rng.uniform(0, math.pi, n)
    elong = rng.uniform(1.0, 2.6, n)
    for i in range(n):
        s = size[i]
        rad = int(math.ceil(s * elong[i] * 2.2)) + 1
        x0, y0 = int(xs[i]), int(ys[i])
        yy, xx = np.mgrid[y0 - rad:y0 + rad + 1, x0 - rad:x0 + rad + 1]
        dx, dy = xx + 0.5 - xs[i], yy + 0.5 - ys[i]
        ca, sa = math.cos(ang[i]), math.sin(ang[i])
        u = (dx * ca + dy * sa) / elong[i]
        v = -dx * sa + dy * ca
        # Scharfe kleine Flocken, groessere weich (Tiefenunschaerfe).
        soft = 0.45 + 0.35 * min(s / (3.0 * k), 1.5)
        g = np.exp(-(u * u + v * v) / (2 * (s * soft) ** 2))
        np.maximum.at(flakes, (yy % H, xx % W), (g * bright[i]).astype(F32))
    veil = fbm2(rng, H, W, base=(2, 16), octaves=7, gain=0.6)
    warp = fbm2(rng, H // 4, W // 4, base=(2, 8), octaves=4)
    rows = np.arange(H)[:, None] + 0 * np.arange(W)[None, :]
    cols = np.arange(W)[None, :] + 0 * np.arange(H)[:, None]
    wv = sample_wrap(warp, rows / 4.0, cols / 4.0)
    veil = sample_wrap(veil, rows + wv * 40 * k, cols + wv * 25 * k)
    veil = np.clip(veil * 1.5 + 0.05, 0, 1) ** 1.8
    rgb = np.repeat(np.clip(flakes, 0, 1)[..., None], 3, axis=2)
    out = np.concatenate([rgb, veil[..., None]], axis=2)
    return np.clip(np.rint(out * 255.0 + rng.uniform(-0.5, 0.5, out.shape)), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------------------
def tonemap(x):
    k = 0.70
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


def build(W, seed, out_dir, preview, quality):
    t0 = time.time()
    P = Pano(W)
    rng = np.random.default_rng(seed)
    paint_sky(P, np.random.default_rng(seed + 1))
    paint_stars(P, np.random.default_rng(seed + 2))
    paint_corona(P, np.random.default_rng(seed + 3))
    paint_ground(P, np.random.default_rng(seed + 6))
    plumes = ((-33.0, 0.55, 0.05), (24.0, 0.40, -0.04), (68.0, 0.5, 0.06),
              (-104.0, 0.45, -0.05), (148.0, 0.5, 0.04), (-150.0, 0.35, 0.05))
    paint_veils(P, np.random.default_rng(seed + 4), plumes)
    paint_ruins(P, np.random.default_rng(seed + 5))
    lin = tonemap(np.clip(P.img, 0, None))
    os.makedirs(out_dir, exist_ok=True)
    rgb = to_u8(np.sqrt(lin), rng)
    alpha = np.clip(np.rint((1.0 - P.occ) * 255.0), 0, 255).astype(np.uint8)
    path = os.path.join(out_dir, "eclipse_sky.webp")
    Image.fromarray(np.dstack([rgb, alpha])).save(
        path, "WEBP", quality=quality, method=6, exact=True, alpha_quality=100)
    mb = os.path.getsize(path) / 1e6
    print("eclipse_sky: %dx%d  %.1f s  %.2f MB  -> %s" % (W, W // 2, time.time() - t0, mb, path))
    t1 = time.time()
    ash = build_ash(W, seed + 7)
    apath = os.path.join(out_dir, "eclipse_ash.webp")
    Image.fromarray(ash).save(apath, "WEBP", quality=quality, method=6, exact=True, alpha_quality=90)
    amb = os.path.getsize(apath) / 1e6
    print("eclipse_ash: %dx%d  %.1f s  %.2f MB  -> %s" % (W, W // 4, time.time() - t1, amb, apath))
    if preview:
        os.makedirs(preview, exist_ok=True)
        dec = srgb_to_lin(np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255.0) ** 2
        for name, yaw in (("cam_eclipse.png", 0.0), ("cam_eclipse_side.png", 60.0)):
            view = camera_view(dec, yaw=yaw)
            Image.fromarray(to_u8(np.clip(view, 0, 1), rng)).save(os.path.join(preview, name))
        small = Image.fromarray(to_u8(np.clip(lin, 0, 1), rng)).resize((2048, 1024), Image.LANCZOS)
        small.save(os.path.join(preview, "pano_eclipse.png"))
        # Ausschnitt um die Sonne in voller Aufloesung.
        r0, c0 = P.row(SUN_LAT + SUN_R * 2.6), int((SUN_LON - SUN_R * 4.5) / 360 * W + W / 2)
        r1, c1 = P.row(SUN_LAT - SUN_R * 1.6), int((SUN_LON + SUN_R * 4.5) / 360 * W + W / 2)
        Image.fromarray(to_u8(np.clip(lin[r0:r1, c0:c1], 0, 1), rng)).save(
            os.path.join(preview, "sun_eclipse.png"))
        Image.fromarray(ash[:, :1024]).save(os.path.join(preview, "ash_eclipse.png"))
    return mb, amb


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--width", type=int, default=4096)
    ap.add_argument("--seed", type=int, default=1919)
    ap.add_argument("--quality", type=int, default=95)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    mb, amb = build(a.width, a.seed, a.out, a.preview, a.quality)
    if a.width >= 4096 and max(mb, amb) >= 2.5:
        raise SystemExit("WebP zu gross (%.2f / %.2f MB >= 2.5 MB): --quality senken" % (mb, amb))


if __name__ == "__main__":
    main()
