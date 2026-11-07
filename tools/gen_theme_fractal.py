#!/usr/bin/env python3
"""TETHRA Welt-Thema "Fraktal": schwarzer Raum voller Obsidian-Splitter.

Erzeugt zwei equirektangulare Panoramen (Standard 4096x2048):
  assets_game/themes/fractal/fractal_sky.webp         fern, RGB
      Schwarzer Raum, kaum Sterne, gedaempfter Karmin-Schein tief am
      Horizont (seitlich/hinten, vorn-mitte dunkel), ein Feld ferner
      Obsidian-Stacheln, die im Dunst verschwinden.
  assets_game/themes/fractal/fractal_sky_shards.webp  nah, RGBA (Alpha = Deckung)
      Riesige, scharfe Obsidian-Splitter und kristalline Stachel-Cluster
      (fraktal: jeder Kristall treibt kleinere Kristalle, 3 Ebenen tief),
      die links/rechts aus dem Abgrund ragen, von oben herabhaengen und
      frei im Raum schweben. Eigene Ebene fuer Parallax/Beat-Bewegung
      (shaders/theme_fractal.gdshader: shards_a).

Echtes 3D: jeder Kristall ist ein konvexes Polyeder (scipy ConvexHull),
pro Pixel wird der Sehstrahl gegen alle Ebenen geschnitten (Z-Puffer,
2x2-Ueberabtastung). Schattierung: schwarzes Vulkanglas (Fresnel, F0 0.04),
Spiegelung zweier Lichter im selben gedaempften Karmin (Schluessellicht
hinten-oben, Kantenlicht vom fernen Horizont) und einer kalten, sehr
dunklen Grau-Kuppel. Kanten: analytischer Abstand zur naechsten Facette
-> haarfeine Glanzkanten, Intensitaet nach Kantenwinkel und Spiegelung
der Fasen-Normale. Unten verschwinden die Kristalle im Dunkel (Hoehen-
Nebel), Ferne im Dunst.

Abbildung identisch zu shaders/sky_panorama.gdshader / theme_fractal.gdshader:
  u = atan(d.x, -d.z) / 2pi + 0.5   (u=0.5 = vorn, -Z)
  v = 0.5 - asin(d.y) / pi          (v=0 = Zenit)
Kodierung: wurzel-kodiert (gespeichert sqrt(linear) als sRGB), der Shader
dekodiert mit pow(textur, 2.0). Die Splitter-Ebene speichert Farbe ohne
Vormultiplikation, Alpha linear.

Reproduzierbar per Seed:
  python tools/gen_theme_fractal.py                        # 4096x2048
  python tools/gen_theme_fractal.py --width 2048 --preview <ordner>
  python tools/gen_theme_fractal.py --seed 7               # andere Kristalle
--preview schreibt Ansichten wie die Komfort-Kamera (fov 62, Neigung -16,
vorn und 70 Grad seitlich) und eine verkleinerte Gesamtansicht als PNG.
"""
import argparse
import math
import os
import time

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import ConvexHull

F32 = np.float32
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets_game", "themes", "fractal")


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


def norm(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def fbm2(rng, H, W, base=(3, 6), octaves=7, gain=0.55):
    """Periodisches fbm (wickelt in Laengsrichtung um), Mittel 0, ~Std 0.5."""
    acc = np.zeros((H, W), F32)
    amp, nrm = 1.0, 0.0
    for o in range(octaves):
        h, w = base[0] << o, base[1] << o
        if h > H // 2 or w > W // 2:
            break
        g = rng.standard_normal((h, w)).astype(F32)
        up = ndimage.zoom(g, (H / h, W / w), order=3, mode="grid-wrap", grid_mode=True)
        acc += amp * up[:H, :W]
        nrm += amp
        amp *= gain
    return acc / nrm


# ---------------------------------------------------------------------------
# Farbsatz (linear). Ein einziger Farbton: gedaempftes Karmin; sonst Neutral.
CARMINE = hexcol("#a3142f")       # Glanzkanten, Lichter
CARMINE_HOT = hexcol("#d8455c")   # hellste Glanzpunkte (gleicher Farbton, heller)
CARMINE_DEEP = hexcol("#4a0814")  # Horizont-Schein, Dunst
COLD = hexcol("#8e949e")          # kalte Grau-Kuppel (Spiegelung, sehr schwach)
VOID = hexcol("#030203")          # Grund des Raums

# Lichter (Weltrichtungen, y oben, -Z vorn)
KEY_DIR = norm(np.array([0.42, 0.62, 0.66]))   # hinten-oben-rechts
RIM_DIR = norm(np.array([-0.10, 0.06, -1.0]))  # ferner Horizont vorn
FOG_DIST = 900.0
KEEP_OUT = None  # Freiraum-Test (lat, lon) -> bool, nur fuer die nahe Ebene


def keep_out_near(lat, lon):
    """Vorn-mitte frei: Strecke, Noten-Horizont und ein Keil darueber."""
    a = np.abs(lon)
    return ((a < 24.0) & (lat < 9.0)) | ((a < 14.0) & (lat < 20.0))


def dirs(lat, lon):
    """lat/lon in Grad (Arrays gleicher Form) -> Einheitsvektoren (..., 3)."""
    la, lo = np.radians(lat), np.radians(lon)
    cl = np.cos(la)
    return np.stack([cl * np.sin(lo), np.sin(la), -cl * np.cos(lo)], -1).astype(F32)


def to_latlon(p):
    p = norm(np.asarray(p, dtype=np.float64))
    lat = np.degrees(np.arcsin(np.clip(p[..., 1], -1, 1)))
    lon = np.degrees(np.arctan2(p[..., 0], -p[..., 2]))
    return lat, lon


def at(lat, lon, dist, y=None):
    """Weltpunkt in Richtung lat/lon im Abstand dist (y optional fest)."""
    d = dirs(np.array(lat, F32), np.array(lon, F32)).astype(np.float64)
    p = d * dist
    if y is not None:
        h = math.hypot(p[0], p[2])
        p = np.array([p[0] / h * dist, y, p[2] / h * dist])
    return p


# ---------------------------------------------------------------------------
class Poly:
    """Konvexes Polyeder: n.x <= c innen (n auswaerts, Einheitslaenge)."""

    def __init__(self, pts, emerge, gloss, ripple, rng):
        hull = ConvexHull(pts)
        eq = hull.equations.copy()  # n.x + off <= 0
        key = np.round(eq, 4)
        _, idx = np.unique(key, axis=0, return_index=True)
        eq = eq[np.sort(idx)]
        self.N = eq[:, :3].astype(F32)
        self.C = (-eq[:, 3]).astype(F32)
        self.ok = bool(np.any(self.C < -0.5))  # Ursprung (Kamera) ausserhalb
        self.pts = pts
        self.edges = []
        for s in hull.simplices:
            for a, b in ((0, 1), (1, 2), (2, 0)):
                self.edges.append((pts[s[a]], pts[s[b]]))
        self.emerge = emerge  # (y_unten, y_oben): darunter im Dunkel
        self.gloss = gloss
        self.ripple = ripple  # (Wellenvektoren (3,3), Phasen (3,), Staerke)
        self.dist = float(np.linalg.norm(pts.mean(0)))

    def samples(self, n=10):
        e = np.array(self.edges)
        k = np.linspace(0.0, 1.0, n)[None, :, None]
        return (e[:, 0:1] * (1 - k) + e[:, 1:2] * k).reshape(-1, 3)

    def blocks(self):
        """Liegt der Kristall im Freiraum vorn ueber/hinter der Strecke?"""
        if KEEP_OUT is None:
            return False
        lat, lon = to_latlon(self.samples(6))
        return bool(np.any(KEEP_OUT(lat, lon)))

    def box(self, W, H):
        """Zeilen-/Spaltenbereich (Pixel) der Projektion, Spalten evtl. > W."""
        lat, lon = to_latlon(self.samples(10))
        clat, clon = to_latlon(self.pts.mean(0))
        dl = (lon - clon + 180.0) % 360.0 - 180.0
        pad = 0.6
        la0, la1 = lat.min() - pad, lat.max() + pad
        lo0, lo1 = clon + dl.min() - pad, clon + dl.max() + pad
        if la1 > 84 or la0 < -84 or lo1 - lo0 > 300:
            la0, la1 = (la0, 90.0) if la1 > 84 else (-90.0, la1) if la0 < -84 else (la0, la1)
            lo0, lo1 = -180.0, 180.0
        r0 = int(max(0, math.floor((0.5 - la1 / 180.0) * H)))
        r1 = int(min(H, math.ceil((0.5 - la0 / 180.0) * H)))
        c0 = int(math.floor((lo0 / 360.0 + 0.5) * W))
        c1 = int(math.ceil((lo1 / 360.0 + 0.5) * W))
        if c1 - c0 >= W:
            c0, c1 = 0, W
        return r0, r1, c0, c1


def frame(axis, rng):
    a = norm(np.asarray(axis, dtype=np.float64))
    t = np.array([0.0, 1.0, 0.0]) if abs(a[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    u = norm(np.cross(a, t))
    v = np.cross(a, u)
    ph = rng.uniform(0, 2 * math.pi)
    return a, u * math.cos(ph) + v * math.sin(ph), -u * math.sin(ph) + v * math.cos(ph)


def crystal_pts(base, axis, L, r, rng, sides=None, flat=1.0, body=None, bottom=0.12):
    """Kristall: Basisring, Schulterring, schiefe Spitze, kurze Gegenspitze."""
    a, u, v = frame(axis, rng)
    sides = sides or int(rng.integers(4, 8))
    body = body if body is not None else rng.uniform(0.25, 0.62)
    ang = np.sort((np.arange(sides) + rng.uniform(-0.28, 0.28, sides)) * 2 * math.pi / sides)
    rad = r * rng.uniform(0.72, 1.12, sides)
    ring = (np.cos(ang)[:, None] * u + flat * np.sin(ang)[:, None] * v) * rad[:, None]
    taper = rng.uniform(0.62, 0.95)
    tw = rng.uniform(-0.25, 0.25)  # leichte Verdrehung der Schulter
    ring2 = (np.cos(ang + tw)[:, None] * u + flat * np.sin(ang + tw)[:, None] * v) * (rad * taper)[:, None]
    tip_off = (u * rng.uniform(-1, 1) + v * rng.uniform(-1, 1) * flat) * r * 0.22
    pts = np.concatenate([
        base + ring,
        base + a * L * body + ring2,
        (base + a * L + tip_off)[None],
        (base - a * L * bottom)[None],
    ])
    return pts


def ripple(rng, scale):
    k = norm(rng.standard_normal((3, 3))) * (2 * math.pi / (scale * rng.uniform(0.6, 1.6, 3)))[:, None]
    return k.astype(F32), rng.uniform(0, 6.3, 3).astype(F32), float(rng.uniform(0.03, 0.09))


def cluster(out, rng, base, axis, L, r, depth, emerge, gloss=1.0, kids=(4, 7), flat=1.0, min_ang=0.25):
    """Fraktaler Kristall-Cluster: Elternkristall treibt kleinere Kristalle."""
    pts = crystal_pts(base, axis, L, r, rng, flat=flat)
    p = Poly(pts, emerge, gloss * rng.uniform(0.8, 1.15), ripple(rng, r * 1.5), rng)
    if not p.ok or p.blocks():
        return
    out.append(p)
    ang_size = math.degrees(r / max(p.dist, 1.0))
    if depth <= 0 or ang_size < min_ang:
        return
    a, u, v = frame(axis, rng)
    n = int(rng.integers(kids[0], kids[1] + 1))
    for _ in range(n):
        f = rng.uniform(0.0, 0.42) ** 1.4
        ph = rng.uniform(0, 2 * math.pi)
        side = u * math.cos(ph) + v * math.sin(ph)
        tilt = math.radians(rng.uniform(14, 48))
        ca = norm(a * math.cos(tilt) + side * math.sin(tilt))
        cb = base + a * L * f + side * r * rng.uniform(0.3, 0.75)
        s = rng.uniform(0.22, 0.55)
        cluster(out, rng, cb, ca, L * s, r * s * rng.uniform(0.75, 1.25), depth - 1, emerge,
                gloss, kids=(max(1, kids[0] - 2), max(2, kids[1] - 3)), flat=flat, min_ang=min_ang)


def druse(out, rng, base, axis, L, r, emerge, n=(5, 9), cone=34.0, flat=1.0):
    """Kristall-Druse: Hauptkristall + Faecher aus einer Wurzel, jeder Ast
    treibt wieder kleinere Kristalle (fraktal, Selbstaehnlichkeit 3 Ebenen)."""
    cluster(out, rng, base, axis, L, r, 1, emerge, kids=(2, 4), flat=flat, min_ang=0.25)
    a, u, v = frame(axis, rng)
    for _ in range(int(rng.integers(n[0], n[1] + 1))):
        ph = rng.uniform(0, 2 * math.pi)
        side = u * math.cos(ph) + v * math.sin(ph)
        tilt = math.radians(rng.uniform(8, cone))
        ca = norm(a * math.cos(tilt) + side * math.sin(tilt))
        s = rng.uniform(0.22, 0.85) ** 1.3
        cb = base + side * r * rng.uniform(0.2, 1.4) + a * L * rng.uniform(0.0, 0.15)
        cluster(out, rng, cb, ca, L * s, r * s * rng.uniform(0.8, 1.3), 2, emerge,
                kids=(2, 4), flat=flat * rng.uniform(0.6, 1.0), min_ang=0.22)


def shard(out, rng, center, axis, L, r, flat, emerge=(-1e9, -1e9 + 1), gloss=1.0):
    """Frei schwebender Splitter: flache, beidseitig spitze Klinge."""
    a, u, v = frame(axis, rng)
    sides = int(rng.integers(4, 7))
    ang = np.sort((np.arange(sides) + rng.uniform(-0.3, 0.3, sides)) * 2 * math.pi / sides)
    rad = r * rng.uniform(0.6, 1.15, sides)
    off = rng.uniform(-0.25, 0.25, sides) * L
    ring = (np.cos(ang)[:, None] * u + flat * np.sin(ang)[:, None] * v) * rad[:, None] + a * off[:, None]
    t1 = center + a * L * rng.uniform(0.45, 0.6) + u * r * rng.uniform(-0.5, 0.5)
    t2 = center - a * L * rng.uniform(0.25, 0.5) + v * r * flat * rng.uniform(-0.5, 0.5)
    pts = np.concatenate([center + ring, t1[None], t2[None]])
    p = Poly(pts, emerge, gloss, ripple(rng, r * 1.2), rng)
    if p.ok and not p.blocks():
        out.append(p)


# ---------------------------------------------------------------------------
def build_scene(rng):
    global KEEP_OUT
    near, far = [], []
    KEEP_OUT = keep_out_near

    def up(lean_lon, lean, outward=0.0, lon=0.0):
        """Achse: nach oben, um 'lean' Grad Richtung lean_lon gekippt."""
        h = dirs(np.array(0.0, F32), np.array(lean_lon, F32)).astype(np.float64)
        a = np.array([0.0, 1.0, 0.0]) * math.cos(math.radians(lean)) + h * math.sin(math.radians(lean))
        return norm(a)

    # Giganten links/rechts: ragen aus dem Abgrund, kippen leicht zur Strecke.
    giants = [
        # lon, dist, base_y, L, r, lean_lon, lean
        (-42.0, 54.0, -66.0, 122.0, 15.0, -20.0, 12.0),
        (45.0, 60.0, -70.0, 130.0, 16.0, 15.0, 10.0),
        (-86.0, 50.0, -58.0, 96.0, 12.0, -70.0, 14.0),
        (92.0, 52.0, -60.0, 100.0, 12.5, 80.0, 12.0),
        (-136.0, 66.0, -62.0, 118.0, 15.0, -150.0, 12.0),
        (140.0, 70.0, -64.0, 124.0, 15.5, 150.0, 12.0),
        (180.0, 80.0, -60.0, 120.0, 15.0, 180.0, 8.0),
    ]
    for lon, dist, by, L, r, llon, lean in giants:
        b = at(0.0, lon, dist, y=by)
        druse(near, rng, b, up(llon, lean), L, r, (by + 0.12 * L, by + 0.62 * L),
              flat=rng.uniform(0.45, 0.8))

    # Von oben haengende Stacheln (Spitzen zeigen auf die Strecke, bleiben oben).
    hangs = [
        (-24.0, 70.0, 88.0, 70.0, 5.0, 30.0),
        (27.0, 76.0, 92.0, 74.0, 5.2, -30.0),
        (-70.0, 60.0, 80.0, 60.0, 4.6, 40.0),
        (74.0, 62.0, 84.0, 62.0, 4.8, -40.0),
        (180.0, 70.0, 90.0, 70.0, 5.0, 0.0),
    ]
    for lon, dist, by, L, r, tilt in hangs:
        b = at(0.0, lon, dist, y=by)
        hb = np.array([-b[0], 0.0, -b[2]])
        ax = norm(np.array([0.0, -1.0, 0.0]) + norm(hb) * math.tan(math.radians(abs(tilt))) * 0.6)
        cluster(near, rng, b, ax, L, r, 2, (-1e9, -1e9 + 1), gloss=0.9, kids=(3, 5), min_ang=0.2)

    # Frei schwebende Splitter (Klingen), seitlich und oben, nie vorn-unten.
    for _ in range(20):
        lon = rng.uniform(-180, 180)
        lat = rng.uniform(4, 62)
        if abs(lon) < 30:
            lat = rng.uniform(24, 60)
        dist = rng.uniform(50, 160)
        c = at(lat, lon, dist)
        L = dist * rng.uniform(0.18, 0.5)
        shard(near, rng, c, norm(rng.standard_normal(3)), L, L * rng.uniform(0.12, 0.22),
              flat=rng.uniform(0.18, 0.45))

    # Fernes Stachelfeld am Horizont (Hintergrund), verschwindet im Dunst.
    KEEP_OUT = None
    for _ in range(70):
        lon = rng.uniform(-180, 180)
        dist = rng.uniform(140, 620)
        L = rng.uniform(40, 170) * (dist / 300.0) ** 0.6
        by = -rng.uniform(0.25, 0.55) * L
        if abs(lon) < 28:
            L *= 0.5
        b = at(0.0, lon, dist, y=by)
        lean = rng.uniform(0, 26)
        cluster(far, rng, b, up(rng.uniform(-180, 180), lean), L, L * rng.uniform(0.06, 0.11), 2,
                (by + 0.15 * L, by + 0.7 * L), gloss=0.45, kids=(2, 4), min_ang=0.3)
    return near, far


# ---------------------------------------------------------------------------
def env(r, rim_k=1.0):
    """Gespiegelte Umgebung (linear) fuer Reflexionsrichtungen r (n, 3)."""
    ry = r[:, 1:2]
    dome = COLD * (0.006 + 0.16 * np.clip(ry, 0, 1) ** 2.2)
    k = r @ KEY_DIR
    key = (np.exp((k - 1.0) * 40.0) * 0.10 + np.exp((k - 1.0) * 420.0) * 2.6)[:, None] * CARMINE
    q = r @ RIM_DIR
    rim = (np.exp((q - 1.0) * 12.0) * 0.05 + np.exp((q - 1.0) * 150.0) * 0.9)[:, None] * CARMINE * rim_k
    hor = (np.exp(-(ry / 0.10) ** 2) * 0.020)[..., :1] * CARMINE_DEEP
    return dome + key + rim + hor


def shade(d, t, p, P, i_in, j_e, ed, px):
    n = P.N[i_in]
    # Muschelbruch-Wellen (Obsidian): Normale leicht wellig.
    kv, ph, amp = P.ripple
    arg = p @ kv.T + ph
    g = (np.cos(arg) @ kv) / np.linalg.norm(kv, axis=1).mean()
    g -= (g * n).sum(1, keepdims=True) * n
    n = norm(n + amp * g)
    ndv = np.clip(-(d * n).sum(1, keepdims=True), 0.0, 1.0)
    r = d + 2.0 * ndv * n
    F = 0.04 + 0.96 * (1.0 - ndv) ** 5
    col = VOID * 0.6 + env(r) * F * 2.2 * P.gloss
    # Glanzkanten: Fase zwischen Sichtflaeche und Nachbarflaeche.
    nj = P.N[j_e]
    cij = (P.N[i_in] * nj).sum(1)
    sharp = smoothstep(0.03, 0.35, 1.0 - cij)[:, None]
    ne = norm(P.N[i_in] + nj)
    nde = np.clip(-(d * ne).sum(1, keepdims=True), 0.0, 1.0)
    re = d + 2.0 * nde * ne
    w = px * t[:, None]
    line = np.exp(-(ed[:, None] / w) ** 2)
    halo = np.exp(-ed[:, None] / (w * 4.0)) * 0.07
    k = re @ KEY_DIR
    q = re @ RIM_DIR
    glint = (0.03 + 0.55 * np.exp((k - 1.0) * 4.0) + 0.45 * np.exp((q - 1.0) * 3.0))[:, None]
    hot = (np.exp((k - 1.0) * 30.0) + np.exp((q - 1.0) * 22.0))[:, None]
    ec = CARMINE * glint * 0.6 + CARMINE_HOT * hot * 1.2
    col = col + ec * (line + halo) * sharp * P.gloss
    # Dunst und Abgrund.
    fog = np.exp(-t / FOG_DIST)[:, None]
    col = col * fog + CARMINE_DEEP * 0.010 * (1.0 - fog)
    y0, y1 = P.emerge
    col *= (smoothstep(y0, y1, p[:, 1]) ** 1.6)[:, None]
    return col


def render(polys, W, H, ss_px=1, tile=256, log=""):
    col = np.zeros((H, W, 3), F32)
    cov = np.zeros((H, W), F32)
    zb = np.full((H, W), np.inf, F32)
    px = math.pi / H * ss_px
    boxes = [P.box(W, H) for P in polys]
    lat_r = ((0.5 - (np.arange(H) + 0.5) / H) * 180.0).astype(F32)
    t0 = time.time()
    for y0 in range(0, H, tile):
        y1 = min(H, y0 + tile)
        for P, (r0, r1, c0, c1) in zip(polys, boxes):
            a, b = max(r0, y0), min(r1, y1)
            if a >= b:
                continue
            cols = np.arange(c0, c1) % W
            lat = lat_r[a:b][:, None].repeat(len(cols), 1)
            lon = (((cols + 0.5) / W - 0.5) * 360.0).astype(F32)[None, :].repeat(b - a, 0)
            d = dirs(lat, lon).reshape(-1, 3)
            D = d @ P.N.T
            with np.errstate(divide="ignore", invalid="ignore"):
                T = P.C[None, :] / D
            ent = D < -1e-7
            ext = D > 1e-7
            par = (~ent & ~ext) & (P.C[None, :] < 0)
            tin = np.where(ent, T, -np.inf)
            i_in = tin.argmax(1)
            tin = tin.max(1)
            tout = np.where(ext, T, np.inf).min(1)
            rr = np.arange(a, b)[:, None].repeat(len(cols), 1).reshape(-1)
            cc = cols[None, :].repeat(b - a, 0).reshape(-1)
            hit = (tin < tout) & (tin > 0) & ~par.any(1) & (tin < zb[rr, cc])
            if not hit.any():
                continue
            d, tin, i_in, rr, cc = d[hit], tin[hit], i_in[hit], rr[hit], cc[hit]
            p = d * tin[:, None]
            S = P.C[None, :] - p @ P.N.T
            S[np.arange(len(S)), i_in] = np.inf
            cij = P.N[i_in] @ P.N.T
            sn = np.sqrt(np.clip(1.0 - cij * cij, 0.0025, 1.0))
            E = S / sn
            j_e = E.argmin(1)
            ed = E[np.arange(len(E)), j_e]
            c = shade(d, tin, p, P, i_in, j_e, ed, px)
            col[rr, cc] = c
            cov[rr, cc] = 1.0
            zb[rr, cc] = tin
        if log:
            print("  %s %4d/%d rows  %.0f s" % (log, y1, H, time.time() - t0), flush=True)
    return col, cov


def down(x, ss):
    if ss == 1:
        return x
    H, W = x.shape[:2]
    return x.reshape(H // ss, ss, W // ss, ss, *x.shape[2:]).mean((1, 3))


# ---------------------------------------------------------------------------
def paint_space(W, H, rng):
    """Schwarzer Raum: Karmin-Schein tief am Horizont, Dunst, wenige Sterne."""
    lat = ((0.5 - (np.arange(H) + 0.5) / H) * 180.0).astype(F32)[:, None]
    lon = (((np.arange(W) + 0.5) / W - 0.5) * 360.0).astype(F32)[None, :]
    img = np.zeros((H, W, 3), F32) + VOID * 0.35
    n1 = fbm2(rng, H, W, base=(3, 8), octaves=8)
    n2 = fbm2(rng, H, W, base=(4, 12), octaves=8, gain=0.6)
    # Schein: seitlich/hinten staerker, vorn-mitte gedimmt (Lesbarkeit).
    side = 0.25 + 0.75 * smoothstep(12.0, 70.0, np.abs(lon))
    band = np.exp(-np.maximum(lat, 0) / 5.5) * np.exp(-np.maximum(-lat, 0) / 1.6)
    band2 = np.exp(-np.maximum(lat, 0) / 22.0) * (lat > -2)
    wisp = np.clip(0.55 + n1, 0, None) ** 2
    glow = (band * 0.055 * (0.5 + 0.8 * wisp) + band2 * 0.010 * wisp) * side
    img += glow[..., None] * CARMINE_DEEP / CARMINE_DEEP.max() * 0.5
    # Kalter, kaum sichtbarer Staub oben.
    dust = np.clip(n2 - 0.15, 0, None) ** 2 * smoothstep(5.0, 40.0, lat) * 0.0035
    img += dust[..., None] * COLD
    # Wenige, kalte Sterne (Leere).
    n = int(W * H / 9000)
    ys = rng.integers(0, H, n)
    xs = rng.integers(0, W, n)
    lum = (rng.pareto(2.2, n) + 1.0) * 0.006
    lum = np.minimum(lum, 0.25) * (lat[ys, 0] > -3)
    np.add.at(img, (ys, xs), lum[:, None] * (COLD * 0.6 + 0.4 * np.ones(3, F32)))
    img = ndimage.gaussian_filter(img, sigma=(0.6, 0.6, 0))
    # Boden unter dem Horizont: Abgrund, schnell schwarz.
    img *= np.where(lat < 0, np.exp(lat / 3.0) * 0.8 + 0.2, 1.0)[..., None]
    return img


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
    out = np.zeros((vh, vw, pano.shape[2]))
    for ch in range(pano.shape[2]):
        out[..., ch] = ndimage.map_coordinates(pano[..., ch], [v - 0.5, u - 0.5], order=1, mode="grid-wrap")
    return out


def build(W, seed, ss, out_dir, preview, quality):
    t0 = time.time()
    H = W // 2
    rng = np.random.default_rng(seed)
    near, far = build_scene(np.random.default_rng(seed + 1))
    print("Kristalle: %d nah, %d fern" % (len(near), len(far)))
    Ws, Hs = W * ss, H * ss
    fc, fa = render(far, Ws, Hs, ss_px=ss * 0.9, log="fern")
    fc, fa = down(fc, ss), down(fa, ss)
    space = paint_space(W, H, np.random.default_rng(seed + 2))
    bg = space * (1.0 - fa[..., None]) + fc
    nc, na = render(near, Ws, Hs, ss_px=ss * 0.9, log="nah")
    nc, na = down(nc, ss), down(na, ss)
    os.makedirs(out_dir, exist_ok=True)
    bg_l = tonemap(np.clip(bg, 0, None))
    p_bg = os.path.join(out_dir, "fractal_sky.webp")
    Image.fromarray(to_u8(np.sqrt(bg_l), rng)).save(p_bg, "WEBP", quality=quality, method=6)
    # Splitter: Farbe ohne Vormultiplikation (Raender in Nachbarfarbe ausbluten).
    straight = nc / np.maximum(na, 1e-4)[..., None]
    hole = na < 1e-3
    if hole.any():
        idx = ndimage.distance_transform_edt(hole, return_distances=False, return_indices=True)
        straight = straight[idx[0], idx[1]]
    sh_l = tonemap(np.clip(straight, 0, None))
    rgb = to_u8(np.sqrt(sh_l), rng)
    alpha = np.clip(np.rint(na * 255.0), 0, 255).astype(np.uint8)
    p_sh = os.path.join(out_dir, "fractal_sky_shards.webp")
    Image.fromarray(np.dstack([rgb, alpha])).save(
        p_sh, "WEBP", quality=quality, alpha_quality=100, method=6, exact=True)
    mb = (os.path.getsize(p_bg) / 1e6, os.path.getsize(p_sh) / 1e6)
    print("fractal: %dx%d ss%d  %.0f s  sky %.2f MB  shards %.2f MB" % (W, H, ss, time.time() - t0, *mb))
    if preview:
        os.makedirs(preview, exist_ok=True)
        dec_bg = srgb_to_lin(np.asarray(Image.open(p_bg).convert("RGB"), dtype=np.float64) / 255.0) ** 2
        sh = np.asarray(Image.open(p_sh).convert("RGBA"), dtype=np.float64) / 255.0
        dec_sh = srgb_to_lin(sh[..., :3]) ** 2
        comp = dec_bg * (1 - sh[..., 3:]) + dec_sh * sh[..., 3:]
        for name, yaw in (("cam_fractal.png", 0.0), ("cam_fractal_side.png", 70.0), ("cam_fractal_back.png", 180.0)):
            view = camera_view(comp, yaw=yaw)
            Image.fromarray(to_u8(np.clip(view, 0, 1), rng)).save(os.path.join(preview, name))
        small = Image.fromarray(to_u8(np.clip(comp, 0, 1), rng)).resize((2048, 1024), Image.LANCZOS)
        small.save(os.path.join(preview, "pano_fractal.png"))
    return max(mb)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--width", type=int, default=4096)
    ap.add_argument("--seed", type=int, default=6661)
    ap.add_argument("--ss", type=int, default=2, help="Ueberabtastung je Achse")
    ap.add_argument("--quality", type=int, default=95)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    mb = build(a.width, a.seed, a.ss, a.out, a.preview, a.quality)
    if a.width >= 4096 and mb >= 2.5:
        raise SystemExit("WebP zu gross (%.2f MB >= 2.5 MB): --quality senken" % mb)


if __name__ == "__main__":
    main()
