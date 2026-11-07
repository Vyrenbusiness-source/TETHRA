#!/usr/bin/env python3
"""TETHRA Welt-Thema "Sturm": abstrakter Gewitter-Mahlstrom als Panorama.

Erzeugt (Standard 4096x2048, equirektangular) in assets_game/themes/storm/:
  storm_sky.webp         ferne Ebene: Trichter aus dunklen Wolkenmassen, die
                         spiralfoermig in ein schwarzes Auge vorn am Horizont
                         stuerzen; Augenwand innen gedaempft grau-violett
                         beleuchtet, eingebettetes Wetterleuchten (weiche
                         Lichtherde in den Wolken, nie Blitz-Kanaele).
  storm_sky_clouds.webp  nahe Ebene (RGBA, Farbe vormultipliziert): schaerfere
                         Wolkenbaender mit innen beleuchteten Kanten und
                         Regenschleier, die mit dem Sog ins Auge laufen.
                         Der Shader dreht sie schneller als die ferne Ebene
                         (Parallax) um die Augen-Achse.
Farbfamilie nur Anthrazit + kaltes Grau-Violett, kein Neon.

Geometrie: Trichter-Koordinaten um die Augen-Achse (EYE_LAT/EYE_LON, wie
EYE_* in shaders/theme_storm.gdshader): r = Winkelabstand zur Achse,
theta = Winkel um die Achse (0 = rechts, 90 = oben), rho = ln(r / R_EYE).
Spiralarme sind Linien konstanter phi = theta + TWIST * rho (log. Spirale).
Beide Ebenen sind um die Achse nahezu drehsymmetrisch hell: der Shader
dreht sie, Abdunklung unten/Mitte passiert dort in Weltkoordinaten.
Rauschen wird im (phi, rho)-Raster erzeugt; Oktaven, die am jeweiligen
Abstand feiner als ~2 Pixel waeren, werden ausgeblendet (kein Aliasing am Auge).

Abbildung identisch zu shaders/sky_panorama.gdshader:
  u = atan(d.x, -d.z) / 2pi + 0.5   (u=0.5 = vorn, -Z)
  v = 0.5 - asin(d.y) / pi          (v=0 = Zenit)
Kodierung: wurzel-kodiert (gespeichert sqrt(linear) als sRGB), der Shader
dekodiert mit pow(textur, 2.0). Alpha der Wolken-Ebene linear.

Reproduzierbar per Seed:
  python tools/gen_theme_storm.py                       # 4096x2048
  python tools/gen_theme_storm.py --width 2048 --preview <ordner>
  python tools/gen_theme_storm.py --seed 3              # anderer Wirbel
--preview schreibt Ansichten wie die Komfort-Kamera (fov 62, Neigung -16,
ohne Shader-Abdunklung) und eine verkleinerte Gesamtansicht als PNG.
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
OUT_DIR = os.path.join(ROOT, "assets_game", "themes", "storm")

# Auge (Grad): knapp ueber dem Fluchtpunkt der Strecke, Noten kommen aus der Leere.
EYE_LAT = 1.2
EYE_LON = 0.0
R_EYE = 4.4
TWIST = 2.3          # Windung der Spiralarme (rad je e-Faktor Abstand)
TWIST_RAIN = 1.25    # Regenschleier: steiler, laufen direkt ins Auge
RHO0, RHO1 = -1.2, math.log(181.0 / R_EYE)
NR, NP = 2048, 4096  # (rho, phi)-Raster


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


# ---------------------------------------------------------------------------
# Farben (linear). Anthrazit-Koerper, kaltes Grau-Violett fuer Licht.
VOID = hexcol("#050507")
ANTH_DEEP = hexcol("#0d0d11")
ANTH = hexcol("#1d1e24")
ANTH_LIT = hexcol("#34343f")
VIO_DEEP = hexcol("#3b3852")
VIO = hexcol("#77728f")
VIO_PALE = hexcol("#b4b0c8")


def axis_frame():
    la, lo = math.radians(EYE_LAT), math.radians(EYE_LON)
    e = np.array([math.cos(la) * math.sin(lo), math.sin(la), -math.cos(la) * math.cos(lo)])
    up = np.array([0.0, 1.0, 0.0])
    rr = np.cross(up, -e)
    rr /= np.linalg.norm(rr)
    uu = np.cross(-e, rr)
    return e, rr, uu


class Pano:
    def __init__(self, W):
        self.W, self.H = W, W // 2
        self.ppd = W / 360.0
        v = (np.arange(self.H, dtype=np.float64) + 0.5) / self.H
        u = (np.arange(self.W, dtype=np.float64) + 0.5) / self.W
        lat = ((0.5 - v) * math.pi)[:, None]
        lon = ((u - 0.5) * 2.0 * math.pi)[None, :]
        dx = np.cos(lat) * np.sin(lon)
        dy = np.broadcast_to(np.sin(lat), dx.shape)
        dz = -np.cos(lat) * np.cos(lon)
        e, rr, uu = axis_frame()
        c = np.clip(dx * e[0] + dy * e[1] + dz * e[2], -1.0, 1.0)
        self.r = np.degrees(np.arccos(c)).astype(F32)
        self.th = np.arctan2(dx * uu[0] + dy * uu[1] + dz * uu[2],
                             dx * rr[0] + dy * rr[1] + dz * rr[2]).astype(F32)
        self.rho = np.log(np.maximum(self.r, 0.02) / R_EYE).astype(F32)
        self.lat = np.degrees(lat).astype(F32)


class Raster:
    """(rho, phi)-Raster: Zeile = rho (r fest je Zeile), Spalte = phi (wickelt um)."""

    def __init__(self, ppd):
        self.ppd = ppd
        self.rho = (RHO0 + (np.arange(NR) + 0.5) / NR * (RHO1 - RHO0)).astype(F32)
        self.r = (R_EYE * np.exp(self.rho)).astype(F32)
        self.sinr = np.sin(np.radians(np.minimum(self.r, 179.0))).astype(F32)

    def fbm(self, rng, base, octaves, gain=0.55, twist=TWIST, ridged=False, billow=False, aa=(1.6, 4.0)):
        acc = np.zeros((NR, NP), F32)
        norm, amp = 0.0, 1.0
        for k in range(octaves):
            h, w = base[0] << k, base[1] << k
            if h > NR // 2 or w > NP // 2:
                break
            g = rng.standard_normal((h, w)).astype(F32)
            up = ndimage.zoom(g, (NR / h, NP / w), order=3, mode="grid-wrap", grid_mode=True)[:NR, :NP]
            if ridged:
                up = (0.8 - np.abs(up)) * 1.4
            elif billow:
                up = (np.abs(up) - 0.55) * 1.6
            dphi = 2.0 * math.pi / w
            drho = (RHO1 - RHO0) / h
            px_t = dphi * self.sinr * 57.2958 * self.ppd
            px_s = dphi / max(twist, 0.3) * self.r * self.ppd
            px_r = drho * self.r * self.ppd
            f = smoothstep(aa[0], aa[1], np.minimum(np.minimum(px_t, px_s), px_r)).astype(F32)
            acc += (amp * f)[:, None] * up
            norm += amp
            amp *= gain
        return acc / norm

    def warp(self, field, wr, wp):
        """field an (row + wr, col + wp) abtasten (Domain-Warp, Raster-Einheiten)."""
        rows, cols = np.mgrid[0:NR, 0:NP].astype(F32)
        return ndimage.map_coordinates(field, [rows + wr, cols + wp], order=1, mode="grid-wrap").astype(F32)

    def d_rho(self, field, twist=TWIST):
        """Radiale Ableitung bei festem theta (dphi = twist * drho)."""
        field = ndimage.gaussian_filter(field, (2.0, 2.0), mode="wrap")
        g0 = np.gradient(field, axis=0) / ((RHO1 - RHO0) / NR)
        g1 = np.gradient(field, axis=1) / (2.0 * math.pi / NP)
        return (g0 + twist * g1).astype(F32)


def lookup(P, field, twist=TWIST):
    ir = (P.rho - RHO0) / (RHO1 - RHO0) * NR - 0.5
    ph = (P.th + twist * P.rho) / (2.0 * math.pi)
    ip = (ph - np.floor(ph)) * NP - 0.5
    return ndimage.map_coordinates(field, [np.clip(ir, 0, NR - 1), ip], order=1, mode="grid-wrap").astype(F32)


def col3(x, c):
    return x[..., None] * c


# ---------------------------------------------------------------------------
def heat_blobs(P, rng, n, rmin, rmax):
    """Wetterleuchten: weiche Lichtherde in der Wolkenwand (Winkel-Gauss)."""
    acc = np.zeros(P.r.shape, F32)
    for _ in range(n):
        th0 = rng.uniform(-math.pi, math.pi)
        r0 = math.exp(rng.uniform(math.log(rmin), math.log(rmax)))
        size = r0 * rng.uniform(0.28, 0.5)
        k = rng.uniform(0.45, 1.0)
        dth = np.angle(np.exp(1j * (P.th - th0))).astype(F32)
        arc = dth * np.minimum(P.r, r0 * 1.6) * 0.9
        dr = (P.r - r0) * 1.25
        acc += k * np.exp(-(arc * arc + dr * dr) / (size * size))
    return acc


TWIST_BILLOW = 0.7   # Quellwolken: kaum gewunden (sonst zu Faeden verschert)


def cloud_field(P, R, rng, base, billow, k_billow, warp_amp):
    """Dichte + radiale Ableitung (Licht von der Augenseite) im Pano.
    base wird mit TWIST (Spiralarme), billow mit TWIST_BILLOW (Quellformen)
    abgetastet; beide Raster mit gemeinsamem weichem Domain-Warp."""
    w1 = R.fbm(rng, (2, 5), 4)
    w2 = R.fbm(rng, (2, 5), 4)
    fb = R.fbm(rng, base[0], base[1], gain=base[2])
    fq = R.fbm(rng, billow[0], billow[1], gain=billow[2], twist=TWIST_BILLOW, billow=True)
    fb = R.warp(fb, w1 * warp_amp[0], w2 * warp_amp[1])
    fq = R.warp(fq, w2 * warp_amp[0] * 0.5, w1 * warp_amp[1] * 0.5)
    dens = lookup(P, fb) + k_billow * lookup(P, fq, TWIST_BILLOW)
    grad = lookup(P, R.d_rho(fb)) + k_billow * lookup(P, R.d_rho(fq, TWIST_BILLOW), TWIST_BILLOW)
    return dens, grad


def paint_far(P, R, seed):
    rng = np.random.default_rng(seed)
    dens, grad = cloud_field(P, R, rng, ((3, 9), 9, 0.5), ((5, 6), 8, 0.55), 0.45, (70.0, 140.0))
    r = P.r
    rim = smoothstep(0.0, 1.6, grad)
    # Abdeckung: zur Augenwand hin dichter, weit aussen ruhige Masse.
    cov = smoothstep(-0.18, 0.40, dens + 0.12 * np.exp(-(r - R_EYE) / 10.0))
    thick = smoothstep(0.05, 0.9, dens)

    # Licht kommt aus dem Trichterinneren (Augenwand), faellt nach aussen ab.
    inner = np.exp(-np.maximum(r - R_EYE, 0.0) / 6.0)
    mid = np.exp(-np.maximum(r - R_EYE, 0.0) / 24.0)
    blobs = heat_blobs(P, np.random.default_rng(seed + 50), 12, R_EYE * 1.8, 36.0)
    light = inner * 0.85 + mid * 0.10 + blobs * 0.30
    # Hinter den Wolken: tiefes Anthrazit mit schwachem Innenschein.
    bg = col3(np.ones_like(r), ANTH_DEEP * 0.45) + col3(inner * 0.6 + mid * 0.06, VIO_DEEP * 0.45)
    # Wolken: Koerper dunkel, zur Augenseite hin beleuchtete Kanten,
    # Wetterleuchten scheint durch duenne Stellen.
    body = col3(1.0 - 0.6 * thick, ANTH * 0.8)
    lit = light * (0.06 + 0.94 * rim) * (1.0 - 0.5 * thick)
    glow = (blobs * 0.75 + inner * 0.15) * (1.0 - 0.8 * thick) * smoothstep(-0.1, 0.4, dens)
    cloud = body + col3(lit * 0.85, VIO * 0.55) + col3(glow, VIO * 0.22 + VIO_DEEP * 0.45) \
        + col3(np.clip(lit - 0.5, 0, None) * 0.5, VIO_PALE * 0.4)
    img = bg * (1.0 - cov[..., None]) + cloud * cov[..., None]

    # Augenwand: duenner Lichtsaum, dahinter das schwarze Auge.
    wall = np.exp(-((r - R_EYE * 1.06) / (R_EYE * 0.15)) ** 2) * (0.5 + 0.5 * smoothstep(-0.2, 0.6, dens))
    img += col3(wall * 0.55, VIO * 0.6 + VIO_PALE * 0.15)
    eye = smoothstep(R_EYE * 0.88, R_EYE * 1.12, r)
    img = img * eye[..., None] + col3(1.0 - eye, VOID * 0.25)
    # Ganz aussen (Rueckseite): ruhiger, dunkler.
    img *= (1.0 - 0.55 * smoothstep(70.0, 150.0, r))[..., None]
    return img.astype(F32)


def paint_near(P, R, seed):
    """Nahe Wolkenbaender + Regenschleier -> (rgb vormultipliziert, alpha)."""
    rng = np.random.default_rng(seed)
    dens, grad = cloud_field(P, R, rng, ((2, 7), 9, 0.58), ((7, 8), 8, 0.6), 0.5, (60.0, 160.0))
    rim = smoothstep(0.1, 2.0, grad)

    rain_rng = np.random.default_rng(seed + 7)
    streak = R.fbm(rain_rng, (1, 150), 4, gain=0.7, twist=TWIST_RAIN)
    veil = R.fbm(rain_rng, (2, 9), 4, twist=TWIST_RAIN)
    st = lookup(P, streak, TWIST_RAIN)
    vl = lookup(P, veil, TWIST_RAIN)
    r = P.r

    # Baender erst ab etwas Abstand zum Auge (Tiefe), dann bis weit aussen.
    rad = smoothstep(R_EYE * 1.5, R_EYE * 3.2, r) * (1.0 - 0.5 * smoothstep(90.0, 160.0, r))
    a_cl = smoothstep(0.12, 0.50, dens) * rad
    thick = smoothstep(0.3, 1.0, dens)
    inner = np.exp(-np.maximum(r - R_EYE, 0.0) / 8.0)
    mid = np.exp(-np.maximum(r - R_EYE, 0.0) / 30.0)
    blobs = heat_blobs(P, np.random.default_rng(seed + 60), 9, R_EYE * 2.5, 40.0)
    light = inner * 0.8 + mid * 0.10 + blobs * 0.35
    lit = light * (0.03 + 0.97 * rim) * (1.0 - 0.6 * thick)
    glow = blobs * 0.45 * (1.0 - 0.85 * thick)
    c_cl = col3(1.0 - 0.65 * thick, ANTH * 0.6) + col3(lit, VIO * 0.42) + col3(glow, VIO * 0.2 + VIO_DEEP * 0.3) \
        + col3(np.clip(lit - 0.45, 0, None) * 0.6, VIO_PALE * 0.35)

    # Regenschleier: feine Striche, nur wo ein Schleier haengt, nahe der Baender.
    curtain = smoothstep(0.0, 0.5, vl) * smoothstep(-0.1, 0.35, dens) \
        * smoothstep(R_EYE * 2.0, R_EYE * 4.5, r) * (1.0 - smoothstep(60.0, 110.0, r))
    a_rn = np.clip(smoothstep(0.05, 0.75, st) * curtain * 0.30, 0.0, 1.0)
    c_rn = col3(0.35 + light * 0.9, ANTH_LIT * 0.6 + VIO * 0.12)

    a = a_cl + a_rn * (1.0 - a_cl)
    pm = c_cl * a_cl[..., None] + c_rn * (a_rn * (1.0 - a_cl))[..., None]
    return pm.astype(F32), a.astype(F32)


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
    out = np.zeros((vh, vw, pano.shape[2]))
    for ch in range(pano.shape[2]):
        out[..., ch] = ndimage.map_coordinates(pano[..., ch], [v - 0.5, u - 0.5], order=1, mode="grid-wrap")
    return out


def build(W, seed, out_dir, preview, quality):
    t0 = time.time()
    P = Pano(W)
    R = Raster(P.ppd)
    rng = np.random.default_rng(seed)
    far = tonemap(np.clip(paint_far(P, R, seed + 1), 0, None))
    pm, a = paint_near(P, R, seed + 2)
    pm = tonemap(np.clip(pm, 0, None))
    os.makedirs(out_dir, exist_ok=True)
    p_sky = os.path.join(out_dir, "storm_sky.webp")
    p_cl = os.path.join(out_dir, "storm_sky_clouds.webp")
    Image.fromarray(to_u8(np.sqrt(far), rng)).save(p_sky, "WEBP", quality=quality, method=6)
    rgba = np.concatenate([to_u8(np.sqrt(pm), rng),
                           np.clip(np.rint(a * 255.0), 0, 255).astype(np.uint8)[..., None]], -1)
    Image.fromarray(rgba).save(p_cl, "WEBP", quality=quality, alpha_quality=100, exact=True, method=6)
    mb = [os.path.getsize(p) / 1e6 for p in (p_sky, p_cl)]
    print("storm: %dx%d  %.1f s  sky %.2f MB  clouds %.2f MB  -> %s" % (W, W // 2, time.time() - t0, mb[0], mb[1], out_dir))
    if preview:
        os.makedirs(preview, exist_ok=True)

        def dec(path):
            im = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64) / 255.0
            return np.concatenate([srgb_to_lin(im[..., :3]) ** 2, im[..., 3:]], -1)

        s, c = dec(p_sky), dec(p_cl)
        comp = s[..., :3] * (1.0 - c[..., 3:]) + c[..., :3]
        for name, yaw in (("cam_storm.png", 0.0), ("cam_storm_side.png", 70.0)):
            view = camera_view(comp, yaw=yaw)
            Image.fromarray(to_u8(np.clip(view, 0, 1), rng)).save(os.path.join(preview, name))
        small = Image.fromarray(to_u8(np.clip(comp, 0, 1), rng)).resize((2048, 1024), Image.LANCZOS)
        small.save(os.path.join(preview, "pano_storm.png"))
    return max(mb)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--width", type=int, default=4096)
    ap.add_argument("--seed", type=int, default=1313)
    ap.add_argument("--quality", type=int, default=92)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    mb = build(a.width, a.seed, a.out, a.preview, a.quality)
    if a.width >= 4096 and mb >= 2.5:
        raise SystemExit("WebP zu gross (%.2f MB >= 2.5 MB): --quality senken" % mb)


if __name__ == "__main__":
    main()
