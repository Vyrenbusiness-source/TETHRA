#!/usr/bin/env python3
"""TETHRA Welt-Thema "Singularitaet": schwarzes Loch als equirektangulares Panorama.

Erzeugt (Standard 4096x2048) nach assets_game/themes/singularity/:
  singularity_sky.webp      Hauptebene (tex_a): Schatten des Lochs, duenne
                            weissgluehende Akkretionsscheibe fast von der Kante,
                            Photonenring, gelinste Rueckseite der Scheibe ("Hut"
                            ueber dem Schatten), wenige Sterne und feiner Staub,
                            durch Gravitationslinse verzerrt (Einstein-Boegen).
  singularity_streaks.webp  Ebene streaks_a: Materie-Schlieren, die spiralfoermig
                            ins Loch gezogen werden (additiv, ohne Linse).
                            shaders/theme_singularity.gdshader laesst sie um das
                            Loch kreisen und einwaerts stroemen.

Physik (vereinfacht, aber echt gerechnet): Schwarzschild-Metrik, Lichtbahnen
u'' = -u + 3u^2 (u = M/r) je Stossparameter b numerisch integriert (RK4,
Tabelle b x Bahnwinkel). Fuer jedes Pixel wird der Strahl rueckwaerts verfolgt:
Durchstoesse der Scheibenebene (direktes Bild, Hut, Photonenring hoeherer
Ordnung), Einfang (Schatten) oder Entkommen (gelinster Sternenhimmel).
Scheibe: Novikov-Thorne-Profil, Keplerbahnen mit Doppler-Beaming +
Gravitationsrotverschiebung (eine Seite heller), Filament-Turbulenz.
Farben nur Schwarz / Silberweiss, minimal warmer Kern in der heissesten Zone.

Abbildung identisch zu shaders/sky_panorama.gdshader / theme_singularity.gdshader:
  u = atan(d.x, -d.z) / 2pi + 0.5   (u=0.5 = vorn, -Z)
  v = 0.5 - asin(d.y) / pi          (v=0 = Zenit)
Lochmitte bei HOLE_LON/HOLE_LAT, Scheibe um DISK_ROLL gerollt - dieselben
Konstanten stehen im Shader (hole_lat, hole_roll, streak_flatten).
Kodierung: wurzel-kodiert (gespeichert sqrt(linear) als sRGB), der Shader
dekodiert mit pow(textur, 2.0) - mehr 8-Bit-Stufen in den dunklen Verlaeufen.

Reproduzierbar per Seed:
  python tools/gen_theme_singularity.py                     # 4096x2048
  python tools/gen_theme_singularity.py --width 2048 --preview <ordner>
--preview schreibt Ansichten wie die Komfort-Kamera (fov 62, Neigung -16,
vorn und 60 Grad seitlich) und eine verkleinerte Gesamtansicht als PNG.
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
OUT_DIR = os.path.join(ROOT, "assets_game", "themes", "singularity")

# Geometrie (Grad) - im Shader gespiegelt.
HOLE_LON = -27.0
HOLE_LAT = -2.0
DISK_ROLL = 10.0        # Rollen der Scheibe um die Blickachse (+ = links hoch)
SHADOW_DEG = 7.5        # scheinbarer Schattenradius
VIEW_ELEV = 8.0         # Beobachter ueber der Scheibenebene (fast Kante)
R_IN, R_OUT = 6.0, 26.0  # Scheibe in M (ISCO .. Aussenrand)
STREAK_FLATTEN = 0.42   # Schlieren-Ellipse (Hoehe/Breite) im Bild
B_C = 3.0 * math.sqrt(3.0)

# Farben (linear): kuehles Silber -> Weiss -> minimal warmer Kern.
SILVER = np.array([0.66, 0.74, 0.86], F32)
WHITE = np.array([1.0, 1.0, 1.0], F32)
WARM = np.array([1.0, 0.86, 0.68], F32)


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def norm(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def aniso_noise(rng, shape, sx, sy, wrap_x=True):
    """Periodisches Gauss-Rauschen mit anisotropem Spektrum (sx, sy = Korrelationslaenge
    in Pixeln, x = Achse 1). Mittel 0, Std 1."""
    h, w = shape
    g = rng.standard_normal(shape)
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    spec = np.exp(-((fx * sx) ** 2 + (fy * sy) ** 2) * 2.0 * math.pi ** 2)
    f = np.real(np.fft.ifft2(np.fft.fft2(g) * spec))
    f -= f.mean()
    return (f / (f.std() + 1e-12)).astype(F32)


def fbm(rng, shape, scales, gain=0.55, aspect=1.0):
    acc = np.zeros(shape, F32)
    amp, tot = 1.0, 0.0
    for s in scales:
        acc += amp * aniso_noise(rng, shape, s * aspect, s)
        tot += amp
        amp *= gain
    return acc / tot


def pano_dirs(H, W, du=0.0, dv=0.0, rows=None):
    """Blickrichtungen je Pixel (optional Teilzeilen, Subpixel-Versatz)."""
    r0, r1 = rows if rows else (0, H)
    v = (np.arange(r0, r1, dtype=np.float64)[:, None] + 0.5 + dv) / H
    u = (np.arange(W, dtype=np.float64)[None, :] + 0.5 + du) / W
    lon = (u - 0.5) * 2 * math.pi
    lat = (0.5 - v) * math.pi
    cl = np.cos(lat)
    return np.stack(np.broadcast_arrays(cl * np.sin(lon), np.sin(lat), -cl * np.cos(lon)), -1)


def dir_of(lon_deg, lat_deg):
    lo, la = math.radians(lon_deg), math.radians(lat_deg)
    return np.array([math.cos(la) * math.sin(lo), math.sin(la), -math.cos(la) * math.cos(lo)])


def sample_pano(img, d):
    """Bilinear aus Panorama (H, W[, C]) in Richtung d (..., 3)."""
    H, W = img.shape[:2]
    u = (np.arctan2(d[..., 0], -d[..., 2]) / (2 * math.pi) + 0.5) * W - 0.5
    v = (0.5 - np.arcsin(np.clip(d[..., 1], -1, 1)) / math.pi) * H - 0.5
    v = np.clip(v, 0, H - 1.001)
    if img.ndim == 2:
        return ndimage.map_coordinates(img, [v, u], order=1, mode="grid-wrap")
    return np.stack([ndimage.map_coordinates(img[..., c], [v, u], order=1, mode="grid-wrap")
                     for c in range(img.shape[2])], -1)


# ---------------------------------------------------------------------------
class Frame:
    """Bildachsen um das Loch: h (Mitte), ex (rechts, gerollt), ey (oben, gerollt)."""

    def __init__(self):
        self.h = dir_of(HOLE_LON, HOLE_LAT)
        up = np.array([0.0, 1.0, 0.0])
        ex = norm(np.cross(self.h, up))
        ey = np.cross(ex, self.h)
        r = math.radians(DISK_ROLL)
        self.ex = math.cos(r) * ex + math.sin(r) * ey
        self.ey = -math.sin(r) * ex + math.cos(r) * ey
        # Beobachter im Unendlichen (Tele-Blick, keine Perspektiv-Verzerrung der
        # Scheibe); S = Bildwinkel je M Stossparameter.
        self.S = math.radians(SHADOW_DEG) / B_C
        self.n_obs = -self.h
        e = math.radians(VIEW_ELEV)
        self.N = math.cos(e) * self.ey + math.sin(e) * self.n_obs  # Scheibennormale
        a1 = norm(self.n_obs - np.dot(self.n_obs, self.N) * self.N)
        self.a1, self.a2 = a1, np.cross(self.N, a1)


class Orbits:
    """Lichtbahn-Tabelle u(b, psi) und u'(b, psi), psi = Bahnwinkel ab Beobachter."""

    def __init__(self, bmax, dpsi=0.0015, psi_max=3.4 * math.pi):
        bc = B_C
        cap = bc * (1 - np.exp(np.linspace(0.0, math.log(1e-7), 420)))
        esc = bc * (1 + np.exp(np.linspace(math.log(1e-7), math.log(bmax / bc - 1), 1300)))
        self.b = np.concatenate([cap[1:], esc]).astype(np.float64)
        self.b[0] = max(self.b[0], 1e-3)
        n = int(psi_max / dpsi) + 2
        self.dpsi = dpsi
        nb = self.b.size
        U = np.zeros((nb, n), F32)
        UP = np.zeros((nb, n), F32)
        u = np.zeros(nb)
        up = 1.0 / self.b
        alive = np.ones(nb, bool)
        self.end = np.full(nb, psi_max)
        self.captured = np.zeros(nb, bool)
        f = lambda uu: -uu + 3 * uu * uu  # noqa: E731
        U[:, 0], UP[:, 0] = u, up
        for k in range(1, n):
            h = dpsi
            k1u, k1p = up, f(u)
            k2u, k2p = up + 0.5 * h * k1p, f(u + 0.5 * h * k1u)
            k3u, k3p = up + 0.5 * h * k2p, f(u + 0.5 * h * k2u)
            k4u, k4p = up + h * k3p, f(u + h * k3u)
            un = u + h / 6 * (k1u + 2 * k2u + 2 * k3u + k4u)
            upn = up + h / 6 * (k1p + 2 * k2p + 2 * k3p + k4p)
            cap_now = alive & (un >= 0.5)
            esc_now = alive & (un <= 0.0)
            psi = k * h
            if cap_now.any():
                self.end[cap_now] = psi - h * (un[cap_now] - 0.5) / np.maximum(un[cap_now] - u[cap_now], 1e-9)
                self.captured[cap_now] = True
            if esc_now.any():
                self.end[esc_now] = psi - h * un[esc_now] / np.minimum(un[esc_now] - u[esc_now], -1e-12)
            alive &= ~(cap_now | esc_now)
            un = np.where(cap_now, 10.0, np.where(esc_now, 0.0, un))
            upn = np.where(cap_now | esc_now, 0.0, upn)
            u = np.where(alive | cap_now | esc_now, un, u)
            up = np.where(alive, upn, 0.0)
            U[:, k], UP[:, k] = u, up
        # Noch kreisend am Tabellenende -> wie eingefangen behandeln.
        self.captured |= alive
        self.U, self.UP = U, UP
        self.bidx = np.arange(nb, dtype=np.float64)

    def lookup(self, b, psi):
        fb = np.interp(b, self.b, self.bidx)
        i0 = np.clip(np.floor(fb).astype(np.int64), 0, self.b.size - 2)
        wb = (fb - i0).astype(F32)
        fk = np.clip(psi / self.dpsi, 0, self.U.shape[1] - 1.001)
        k0 = np.floor(fk).astype(np.int64)
        wk = (fk - k0).astype(F32)
        out = []
        for T in (self.U, self.UP):
            a = T[i0, k0] * (1 - wk) + T[i0, k0 + 1] * wk
            c = T[i0 + 1, k0] * (1 - wk) + T[i0 + 1, k0 + 1] * wk
            out.append(a * (1 - wb) + c * wb)
        return out

    def end_of(self, b):
        fb = np.interp(b, self.b, self.bidx)
        i0 = np.clip(np.floor(fb).astype(np.int64), 0, self.b.size - 2)
        wb = fb - i0
        cap = self.captured[i0] | self.captured[i0 + 1]
        end = self.end[i0] * (1 - wb) + self.end[i0 + 1] * wb
        return end, cap


# ---------------------------------------------------------------------------
def make_background(W, H, rng):
    """Unverzerrter Hintergrund: wenige Sterne (Silber, kaum Farbe) + feiner Staub."""
    img = np.zeros((H, W, 3), F32)
    lat = (0.5 - (np.arange(H) + 0.5) / H) * math.pi
    # Staub: sehr schwache silbergraue Schleier, dunkle Baender dazwischen.
    neb = fbm(rng, (H, W), [W / 9, W / 22, W / 60, W / 160], gain=0.6, aspect=1.6)
    neb2 = fbm(rng, (H, W), [W / 30, W / 90, W / 250], gain=0.6, aspect=2.2)
    dust = np.clip(neb * 0.8 + 0.25, 0, None) ** 2.2 * (0.6 + 0.4 * np.clip(neb2 + 0.5, 0, 1.5))
    dust *= 0.024
    img += dust[..., None] * np.array([0.82, 0.86, 0.95], F32)
    dark = smoothstep(0.1, 0.9, neb2 * 0.9 + neb * 0.5)
    # Sterne: gleichverteilt auf der Kugel, Potenzgesetz, wenige helle.
    def stars(n, lo, hi, alpha, sigma, gain):
        z = rng.uniform(-1, 1, n)
        lo_ = rng.uniform(-math.pi, math.pi, n)
        la = np.arcsin(z)
        x = rng.uniform(0, 1, n)
        mag = lo * (1 - x * (1 - (hi / lo) ** (1 - alpha))) ** (1 / (1 - alpha))
        u = (lo_ / (2 * math.pi) + 0.5) * W
        v = (0.5 - la / math.pi) * H
        tint = rng.uniform(-1, 1, n)
        cols = np.where(tint[:, None] > 0,
                        np.array([0.92, 0.96, 1.0]) * (1 - tint[:, None] * 0.08) + tint[:, None] * np.array([0.0, 0.03, 0.08]),
                        np.array([1.0, 0.97, 0.92]) + tint[:, None] * np.array([0.0, 0.02, 0.06]))
        acc = np.zeros((H, W, 3), F32)
        iu = np.floor(u).astype(int) % W
        iv = np.clip(np.floor(v).astype(int), 0, H - 1)
        for c in range(3):
            np.add.at(acc[..., c], (iv, iu), (mag * cols[:, c]).astype(F32))
        # Zeilenabhaengige Breite (equirekt. Dehnung zum Pol).
        acc = ndimage.gaussian_filter1d(acc, sigma, axis=0, mode="nearest")
        out = np.empty_like(acc)
        band = 32
        for r0 in range(0, H, band):
            s = sigma / max(math.cos(lat[min(r0 + band // 2, H - 1)]), 0.08)
            out[r0:r0 + band] = ndimage.gaussian_filter1d(acc[r0:r0 + band], s, axis=1, mode="wrap")
        return out * gain

    k = W / 4096.0
    img += stars(int(14000 * k * k), 0.02, 0.6, 2.4, 0.55 * k, 1.0) * (1 - 0.8 * dark[..., None])
    img += stars(int(900 * k * k), 0.4, 8.0, 2.0, 0.65 * k, 1.0) * (1 - 0.5 * dark[..., None])
    bright = stars(int(40 * k * k), 3.0, 14.0, 2.0, 0.75 * k, 1.0)
    img += bright
    img += ndimage.gaussian_filter(bright, (2.2 * k, 2.2 * k, 0)) * 0.9  # feine Halos
    return img


def disk_textures(rng):
    """Scheiben-Turbulenz in (ln r, phi): feine Filamente entlang der Bahnen."""
    NR, NP = 384, 4096
    a = aniso_noise(rng, (NR, NP), 90.0, 1.6)
    b = aniso_noise(rng, (NR, NP), 260.0, 5.0)
    c = aniso_noise(rng, (NR, NP), 30.0, 0.9)
    ring = np.interp(np.arange(NR), np.linspace(0, NR, 40), rng.uniform(0.55, 1.0, 40))
    ring = ndimage.gaussian_filter1d(ring, 1.2)
    tex = (0.62 + 0.22 * np.tanh(a * 1.3) + 0.18 * np.tanh(b) + 0.08 * c) * ring[:, None]
    gaps = 1.0 - 0.55 * smoothstep(1.2, 2.4, aniso_noise(rng, (NR, NP), 1400.0, 2.2))
    return np.clip(tex * gaps, 0.04, None).astype(F32)


class Renderer:
    def __init__(self, fr, orb, bg, dtex):
        self.fr, self.orb, self.bg, self.dtex = fr, orb, bg, dtex
        self.lnr0, self.lnr1 = math.log(R_IN * 0.95), math.log(R_OUT * 1.02)

    def disk_emit(self, P, k, r):
        """Emission/Deckkraft eines Scheiben-Durchstosses bei Position P (n,3), Photonen-
        richtung k (zum Beobachter), Radius r."""
        fr = self.fr
        Ph = P / r[:, None]
        phi = np.arctan2(Ph @ fr.a2, Ph @ fr.a1)
        # Turbulenz wickelt mit (differentielle Rotation, leichte Spirale).
        lnr = np.log(r)
        tr = (lnr - self.lnr0) / (self.lnr1 - self.lnr0) * (self.dtex.shape[0] - 1)
        tp = ((phi + 2.2 * lnr) / (2 * math.pi) % 1.0) * self.dtex.shape[1]
        tex = ndimage.map_coordinates(self.dtex, [tr, tp], order=1, mode="grid-wrap")
        # Novikov-Thorne-Flussprofil (Maximum bei ~8 M).
        F = (1 - np.sqrt(R_IN / r)) / r ** 3
        F = F / 2.62e-4
        edge = smoothstep(R_OUT, R_OUT * 0.55, r) * smoothstep(R_IN * 0.98, R_IN * 1.08, r)
        # Kepler-Bahn: Geschwindigkeit (statischer Beobachter), Doppler + Gravitation.
        v = np.sqrt(1.0 / np.maximum(r - 2.0, 0.5))
        v = np.minimum(v, 0.6)
        vh = np.cross(fr.N, Ph)
        cosx = np.sum(vh * k, -1)
        gam = 1 / np.sqrt(1 - v * v)
        g = np.sqrt(1 - 2 / r) / (gam * (1 - v * cosx))
        temp = np.clip(F, 0, None) ** 0.25 * g  # beobachtete "Temperatur"
        inten = F * g ** 3.0 * (0.25 + 0.95 * tex) * edge
        alpha = np.clip((0.35 + 0.75 * tex) * smoothstep(R_OUT * 1.02, R_OUT * 0.7, r), 0, 0.96)
        return inten, alpha, temp

    def color_of(self, temp):
        t = temp[:, None].astype(F32)
        c = SILVER + (WHITE - SILVER) * smoothstep(0.35, 0.95, t)
        return c + (WARM - c) * smoothstep(1.05, 1.55, t) * 0.85

    def trace(self, d):
        """d (n,3) Blickrichtungen -> lineare Farbe (n,3)."""
        fr, orb = self.fr, self.orb
        ch = np.clip(d @ fr.h, -1, 1)
        th = np.arccos(ch)
        e = d - ch[:, None] * fr.h
        en = np.linalg.norm(e, axis=-1)
        e = np.where(en[:, None] > 1e-9, e / np.maximum(en, 1e-12)[:, None], fr.ex)
        b = th / fr.S
        near = th < math.radians(68)
        out = np.zeros(d.shape, F32)
        T = np.ones(d.shape[0], F32)
        end, cap = orb.end_of(b)
        end = end - th  # Bahnwinkel bis Unendlich -> Austrittsrichtung (Bildversatz)
        # Ausserhalb der Tabelle (weit seitlich/hinten): schwache Ablenkung.
        a_wf = 2.0 / np.maximum(b, 1e-3) * (1 + ch)
        end_wf = math.pi - th + a_wf
        w = smoothstep(math.radians(58), math.radians(68), th)
        end = np.where(near, end * (1 - w) + end_wf * w, end_wf)
        cap = cap & near
        # Scheibenebene: cos(psi) n.N + sin(psi) e.N = 0
        nN = float(np.dot(fr.n_obs, fr.N))
        eN = e @ fr.N
        psi0 = np.arctan2(-nN, eN) % math.pi
        nb = near & (th < math.radians(55))
        for kk in range(4):
            psi = psi0 + kk * math.pi
            ok = nb & (psi < end)
            if not ok.any():
                continue
            idx = np.nonzero(ok)[0]
            u, up = orb.lookup(b[idx], psi[idx])
            hit = (u >= 1 / R_OUT) & (u <= 1 / (R_IN * 0.95))
            if not hit.any():
                continue
            idx, u, up = idx[hit], u[hit], up[hit]
            r = 1.0 / u
            ps = psi[idx][:, None]
            ph = np.cos(ps) * fr.n_obs + np.sin(ps) * e[idx]
            dph = -np.sin(ps) * fr.n_obs + np.cos(ps) * e[idx]
            rp = (-up / (u * u))[:, None]
            kdir = -norm(rp * ph + r[:, None] * dph)
            inten, alpha, temp = self.disk_emit(r[:, None] * ph, kdir, r)
            # Hoehere Bilder (Photonenring) leicht gedaempft, sonst Glitzern.
            damp = 1.0 if kk == 0 else (0.85 if kk == 1 else 0.6)
            out[idx] += (T[idx] * alpha * inten * damp)[:, None] * self.color_of(temp)
            T[idx] *= 1 - alpha
        # Entkommene Strahlen: gelinster Hintergrund.
        esc = ~cap
        idx = np.nonzero(esc)[0]
        ps = end[idx][:, None]
        dout = np.cos(ps) * fr.n_obs + np.sin(ps) * e[idx]
        # Sehr eng kreisende Strahlen tragen kaum noch (sonst Rauschen am Rand).
        fade = smoothstep(3.0 * math.pi, 2.2 * math.pi, end[idx])
        out[idx] += (T[idx] * fade)[:, None] * sample_pano(self.bg, dout).astype(F32)
        return out


def render_main(W, seed, rng_bg):
    H = W // 2
    fr = Frame()
    t0 = time.time()
    orb = Orbits(math.radians(70) / fr.S)
    print("  Bahnen: %d b-Werte, %.1f s" % (orb.b.size, time.time() - t0))
    bg = make_background(W, H, rng_bg)
    dtex = disk_textures(np.random.default_rng(seed + 7))
    R = Renderer(fr, orb, bg, dtex)
    img = np.zeros((H, W, 3), F32)
    band = max(16, 2 ** 20 // W)
    hcos = math.cos(math.radians(42))
    ss = [(-1 / 3, -1 / 3), (1 / 3, -1 / 3), (-1 / 3, 1 / 3), (1 / 3, 1 / 3),
          (0, 0), (0, -1 / 3), (0, 1 / 3), (-1 / 3, 0), (1 / 3, 0)]
    for r0 in range(0, H, band):
        r1 = min(H, r0 + band)
        d = pano_dirs(H, W, rows=(r0, r1)).reshape(-1, 3)
        acc = R.trace(d).reshape(r1 - r0, W, 3)
        # Supersampling 3x3 nahe am Loch (Photonenring, Scheibenkante).
        m = (d @ fr.h).reshape(r1 - r0, W) > hcos
        if m.any():
            sub = np.zeros((int(m.sum()), 3), F32)
            for du, dv in ss:
                dd = pano_dirs(H, W, du, dv, rows=(r0, r1))[m]
                sub += R.trace(dd)
            acc[m] = sub / len(ss)
        img[r0:r1] = acc
    print("  Raytracing %.1f s" % (time.time() - t0))
    return img, fr


def bloom(img):
    """Weisse Hitze: mehrstufiger Schein der hellen Scheibe (im Bild, nicht im Shader)."""
    H, W = img.shape[:2]
    hi = np.clip(img - 0.35, 0, None)
    small = ndimage.zoom(hi, (0.25, 0.25, 1), order=1)
    acc = np.zeros_like(small)
    k = W / 4096.0
    for s, g in ((1.5, 0.30), (5.0, 0.16), (16.0, 0.08), (44.0, 0.05)):
        acc += ndimage.gaussian_filter(small, (s * k, s * k, 0), mode=("nearest", "wrap", "nearest")) * g
    up = ndimage.zoom(acc, (H / acc.shape[0], W / acc.shape[1], 1), order=1)
    return img + up[:H, :W]


def readability(img, fr):
    """Vorn-unten (hinter Strecke/Noten) und Unterseite dunkel."""
    H, W = img.shape[:2]
    lat = ((0.5 - (np.arange(H) + 0.5) / H) * 180.0)[:, None]
    lon = (((np.arange(W) + 0.5) / W - 0.5) * 360.0)[None, :]
    low = 1.0 - 0.55 * smoothstep(-2.0, -28.0, lat)
    front = np.exp(-(lon / 22.0) ** 2) * smoothstep(-4.0, -14.0, lat)
    return img * (low * (1.0 - 0.6 * front))[..., None]


def render_streaks(W, fr, rng):
    """Materie-Schlieren: einzelne Stroeme auf Log-Spiralen um das Loch (Bild-Ellipse
    STREAK_FLATTEN), aussen breit und blass, innen eng gewickelt und heller, bis sie
    in der Scheibe verschwinden. Feine Filamente laufen in jedem Strom mit."""
    H = W // 2
    NS, NL = 1024, 640
    LN0, LN1 = math.log(0.6), math.log(14.0)  # ln(rho / Schattenradius)
    fil = aniso_noise(rng, (NL, NS), 2.2, 140.0)
    fil2 = aniso_noise(rng, (NL, NS), 1.2, 50.0)
    tex = np.clip(0.45 + 0.5 * np.tanh(fil * 1.5) + 0.22 * fil2, 0.02, None) ** 1.5
    streams = []
    for i in range(13):
        streams.append(dict(
            k=rng.uniform(1.25, 2.5), ph=rng.uniform(-math.pi, math.pi),
            w=rng.uniform(0.10, 0.32), start=rng.uniform(4.5, 15.0),
            gain=rng.uniform(0.45, 1.0) * (1.0 if i < 7 else 0.5)))
    rs = math.tan(math.radians(SHADOW_DEG))
    band = max(16, 2 ** 19 // W)
    sub = ((-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25))

    def field(d):
        z = d @ fr.h
        X = (d @ fr.ex) / np.maximum(z, 1e-3)
        Y = (d @ fr.ey) / np.maximum(z, 1e-3) / STREAK_FLATTEN
        rho = np.sqrt(X * X + Y * Y) / rs
        phi = np.arctan2(Y, X)
        lr = np.log(np.maximum(rho, 1e-3))
        tl = (lr - LN0) / (LN1 - LN0) * (NL - 1)
        acc = np.zeros(d.shape[0], F32)
        for st in streams:
            si = phi + st["k"] * lr - st["ph"]
            ds = (si + math.pi) % (2 * math.pi) - math.pi
            w = st["w"] * (0.55 + 0.30 * lr)
            prof = np.exp(-(ds / w) ** 2)
            tsp = (si / (2 * math.pi) % 1.0) * NS
            v = ndimage.map_coordinates(tex, [tl, tsp], order=1, mode="grid-wrap")
            rad = smoothstep(st["start"], st["start"] * 0.55, rho)
            acc += st["gain"] * prof * rad * (0.25 + v)
        # Schwacher Materie-Dunst um das Loch (flach, wie die Stroeme).
        haze = np.exp(-rho / 2.6) * 0.20
        env = smoothstep(1.15, 1.9, rho) * (z > 0.12) * smoothstep(0.12, 0.3, z)
        env = env * (rho / 2.0) ** -0.9
        return (acc * 0.8 + haze) * env, rho

    img = np.zeros((H, W, 3), F32)
    for r0 in range(0, H, band):
        r1 = min(H, r0 + band)
        val = np.zeros((r1 - r0) * W, F32)
        for du, dv in sub:
            v, rho = field(pano_dirs(H, W, du, dv, rows=(r0, r1)).reshape(-1, 3))
            val += v / len(sub)
        # Naeher am Loch: heller, minimal waermer; aussen kuehles Silber.
        warm = smoothstep(3.2, 1.4, rho)[:, None]
        col = SILVER[None] * (1 - warm) + (WHITE * 0.95 + WARM * 0.05)[None] * warm
        img[r0:r1] = ((val * 0.08)[:, None] * col).reshape(r1 - r0, W, 3)
    return img


def tonemap(x, k=0.62):
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
    d = norm(np.stack([x3, y2, z3], -1))
    return sample_pano(pano, d)


def save(path, lin, rng, quality):
    Image.fromarray(to_u8(np.sqrt(np.clip(lin, 0, 1)), rng)).save(path, "WEBP", quality=quality, method=6)
    return os.path.getsize(path) / 1e6


def build(W, seed, out_dir, preview, quality):
    t0 = time.time()
    rng = np.random.default_rng(seed)
    main, fr = render_main(W, seed, np.random.default_rng(seed + 1))
    main = readability(tonemap(bloom(main * 0.75)), fr)
    streaks = render_streaks(W, fr, np.random.default_rng(seed + 3))
    streaks = readability(tonemap(streaks), fr)
    os.makedirs(out_dir, exist_ok=True)
    p_main = os.path.join(out_dir, "singularity_sky.webp")
    p_st = os.path.join(out_dir, "singularity_streaks.webp")
    mb = save(p_main, main, rng, quality)
    mb2 = save(p_st, streaks, rng, quality)
    print("singularity: %dx%d  %.1f s  sky %.2f MB  streaks %.2f MB -> %s"
          % (W, W // 2, time.time() - t0, mb, mb2, out_dir))
    if preview:
        os.makedirs(preview, exist_ok=True)

        def dec(p):
            return srgb_to_lin(np.asarray(Image.open(p).convert("RGB"), dtype=np.float64) / 255.0) ** 2
        comb = dec(p_main) + dec(p_st)
        for name, yaw in (("cam_sing.png", 0.0), ("cam_sing_side.png", 60.0)):
            Image.fromarray(to_u8(np.clip(camera_view(comb, yaw=yaw), 0, 1), rng)).save(os.path.join(preview, name))
        small = Image.fromarray(to_u8(np.clip(comb, 0, 1), rng)).resize((2048, 1024), Image.LANCZOS)
        small.save(os.path.join(preview, "pano_sing.png"))
    return max(mb, mb2)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--width", type=int, default=4096)
    ap.add_argument("--seed", type=int, default=6174)
    ap.add_argument("--quality", type=int, default=95)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    mb = build(a.width, a.seed, a.out, a.preview, a.quality)
    if a.width >= 4096 and mb >= 2.5:
        raise SystemExit("WebP zu gross (%.2f MB >= 2.5 MB): --quality senken" % mb)


if __name__ == "__main__":
    main()
