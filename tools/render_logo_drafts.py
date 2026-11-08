#!/usr/bin/env python3
"""TETHRA Logo-Entwuerfe: erzeugt SVGs (Handgeometrie, Wortmarke als Pfade),
rendert PNGs per Chrome headless (nichts wird installiert) und baut overview.png.
Aufruf: python tools/render_logo_drafts.py   (benoetigt Pillow + Chrome)"""
import math, os, subprocess, sys, tempfile, shutil
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "brand", "drafts"))
INK, AMB, BG = "#ECE6DA", "#F2A23A", "#121110"
INK_L, AMB_L, BG_L = "#1B1A18", "#C77D12", "#F4F0E8"
CHROME = next((p for p in [r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                           r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                           r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"] if os.path.exists(p)), None)
WORD = "TETHRA"


def f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def glyph(ch, X, Y, w, h, style=""):
    """Mittellinien-Pfade: (haupt, detail). Detail = Querbalken von E/H/A."""
    m, d = "", ""
    if ch == "T":
        m = f"M{f(X)} {f(Y)}H{f(X+w)}M{f(X+w/2)} {f(Y)}V{f(Y+h)}"
        if style == "serif":
            m += f"M{f(X+w*.28)} {f(Y+h)}H{f(X+w*.72)}"
    elif ch == "E":
        m = f"M{f(X+w)} {f(Y)}H{f(X)}V{f(Y+h)}H{f(X+w)}"
        d = f"M{f(X)} {f(Y+h/2)}H{f(X+w*.85)}"
        if style == "serif":
            m += f"M{f(X+w)} {f(Y)}V{f(Y+h*.14)}M{f(X+w)} {f(Y+h)}V{f(Y+h*.86)}"
    elif ch == "H":
        m = f"M{f(X)} {f(Y)}V{f(Y+h)}M{f(X+w)} {f(Y)}V{f(Y+h)}"
        d = f"M{f(X)} {f(Y+h/2)}H{f(X+w)}"
        if style == "serif":
            for sx in (X, X + w):
                m += f"M{f(sx-w*.2)} {f(Y)}H{f(sx+w*.2)}M{f(sx-w*.2)} {f(Y+h)}H{f(sx+w*.2)}"
    elif ch == "R":
        r = h * .26
        m = (f"M{f(X)} {f(Y+h)}V{f(Y)}H{f(X+w-r)}A{f(r)} {f(r)} 0 0 1 {f(X+w-r)} {f(Y+2*r)}H{f(X)}"
             f"M{f(X+w*.42)} {f(Y+2*r)}L{f(X+w)} {f(Y+h)}")
        if style == "serif":
            m += f"M{f(X-w*.2)} {f(Y+h)}H{f(X+w*.2)}M{f(X+w*.8)} {f(Y+h)}H{f(X+w*1.2)}"
    elif ch == "A":
        m = f"M{f(X)} {f(Y+h)}L{f(X+w/2)} {f(Y)}L{f(X+w)} {f(Y+h)}"
        d = f"M{f(X+w*.2)} {f(Y+h*.64)}H{f(X+w*.8)}"
        if style == "serif":
            m += f"M{f(X-w*.15)} {f(Y+h)}H{f(X+w*.3)}M{f(X+w*.7)} {f(Y+h)}H{f(X+w*1.15)}"
    return m, d


def layout(w, h, sw, gap, total=1000, H=250):
    adv = w + sw + gap
    tw = adv * len(WORD) - gap
    x0 = (total - tw) / 2 + sw / 2
    y0 = (H - h) / 2
    return [(c, x0 + i * adv, y0) for i, c in enumerate(WORD)], y0


def svg(vw, vh, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {vw} {vh}" '
            f'width="{vw}" height="{vh}">\n{body}\n</svg>\n')


def stroke(d, sw, col=INK, cap="butt", join="miter"):
    return (f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{f(sw)}" '
            f'stroke-linecap="{cap}" stroke-linejoin="{join}"/>')


def rect(x, y, w, h, col):
    return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" fill="{col}"/>'


# ---------- Entwuerfe: je (Bildmarke 200x200, Wortmarke 1000x250) ----------
def d1():  # Anschlag: Vollmonogramm, T ausgespart, Landeblock in Bernstein
    mark = (f'<path fill-rule="evenodd" fill="{INK}" d="M25 25H175V175H25ZM52 52H148V80H114V150H86V80H52Z"/>\n'
            + rect(86, 118, 28, 32, AMB))
    sw, w, h = 26, 84, 128
    L, y0 = layout(w, h, sw, 34)
    out = []
    for c, x, y in L:
        m, dd = glyph(c, x, y, w, h)
        if c == "T" and x == L[0][1]:
            out.append(stroke(f"M{f(x-sw/2)} {f(y)}H{f(x+w+sw/2)}M{f(x+w/2)} {f(y)}V{f(y+h*.55)}", sw))
            out.append(stroke(f"M{f(x+w/2)} {f(y+h*.55)}V{f(y+h)}", sw, AMB))
            continue
        out.append(stroke(m, sw))
        if dd:
            out.append(stroke(dd, sw))
    return mark, "\n".join(out)


def d2():  # Metrum: ein Takt zwischen Taktstrichen, Zaehlzeit 1 betont
    parts = [rect(22, 36, 8, 128, INK), rect(170, 36, 8, 128, INK)]
    parts.append(rect(48, 62, 22, 76, AMB))
    parts += [rect(82 + i * 32, 116, 20, 22, INK) for i in range(3)]
    w, h, sw = 70, 120, 10
    L, y0 = layout(w, h, sw, 56)
    out = []
    for c, x, y in L:
        m, dd = glyph(c, x, y, w, h)
        out.append(stroke(m, sw))
        if dd:
            out.append(stroke(dd, sw, AMB if c == "A" else INK))
    return "\n".join(parts), "\n".join(out)


def lemn(t, a=82, cx=100, cy=100):
    den = 1 + math.sin(t) ** 2
    return cx + a * math.cos(t) / den, cy + a * math.sin(t) * math.cos(t) / den


def d3():  # Bahn: gekreuzter Riemen um zwei Scheiben, Laeufer im Kreuzungspunkt
    r1, r2, c1, c2 = 46, 28, 60, 150
    ph = math.acos((r1 + r2) / (c2 - c1))
    co, si = math.cos(ph), math.sin(ph)
    p1u = (c1 + r1 * co, 100 - r1 * si); p1l = (c1 + r1 * co, 100 + r1 * si)
    p2u = (c2 - r2 * co, 100 - r2 * si); p2l = (c2 - r2 * co, 100 + r2 * si)
    dd = (f"M{f(p1u[0])} {f(p1u[1])}L{f(p2l[0])} {f(p2l[1])}A{r2} {r2} 0 1 0 {f(p2u[0])} {f(p2u[1])}"
          f"L{f(p1l[0])} {f(p1l[1])}A{r1} {r1} 0 1 1 {f(p1u[0])} {f(p1u[1])}Z")
    xk = c1 + r1 / (r1 + r2) * (c2 - c1)
    mark = stroke(dd, 12, INK, "round", "round") + f'\n<circle cx="{f(xk)}" cy="100" r="13" fill="{AMB}"/>'
    w, h, sw = 66, 118, 13
    L, y0 = layout(w, h, sw, 40)
    out = []
    for c, x, y in L:
        m, d2_ = glyph(c, x, y, w, h)
        out.append(stroke(m, sw, INK, "round", "round"))
        if d2_:
            out.append(stroke(d2_, sw, INK, "round", "round"))
    xe = L[-1][1] + w + sw / 2 + 30
    out.append(f'<circle cx="{f(xe)}" cy="{f(y0+h-8)}" r="10" fill="{AMB}"/>')
    return mark, "\n".join(out)


def d4():  # Leine: Zeichen stehen auf einer Linie, Bernsteinkugel am Ende
    mark = stroke("M24 40H176", 12) + "\n" + stroke("M100 40V118", 12) + f'\n<circle cx="100" cy="144" r="26" fill="{AMB}"/>'
    w, h, sw = 76, 108, 12
    L, _ = layout(w, h, sw, 44)
    yb = 190
    yt = yb - 30 - h
    x_a, x_b = L[0][1] - 44, L[-1][1] + w + 44
    out = [stroke(f"M{f(x_a)} {yb}H{f(x_b)}", sw), f'<circle cx="{f(x_b+14)}" cy="{yb}" r="15" fill="{AMB}"/>']
    for c, x, _ in L:
        m, dd = glyph(c, x, yt, w, h)
        out.append(stroke(m, sw))
        if dd:
            out.append(stroke(dd, sw))
    return mark, "\n".join(out)


BITS = {
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
}


def d5():  # Raster: Pixel-T, eine Note ausgerueckt
    c, g = 26, 4
    p = c + g
    x0, y0 = (200 - (5 * c + 4 * g)) / 2, 36
    cells = [rect(x0 + k * p, y0 + r * p, c, c, INK) for r in range(5) for k in range(5) if r == 0 or k == 2]
    cells.append(rect(x0 + 4 * p, y0 + 3 * p + 15, c, c, AMB))
    c, g = 24, 3
    p = c + g
    lw = 5 * c + 4 * g
    gw = 30
    ox = (1000 - (6 * lw + 5 * gw)) / 2
    oy = (250 - (7 * c + 6 * g)) / 2
    out = []
    for i, ch in enumerate(WORD):
        for r, row in enumerate(BITS[ch]):
            for k, b in enumerate(row):
                if b == "1":
                    col = AMB if (ch == "A" and r == 0) else INK
                    out.append(rect(ox + i * (lw + gw) + k * p, oy + r * p, c, c, col))
    return "\n".join(cells), "\n".join(out)


def d6():  # Emblem: ruhiger Ring, Laeufer, schlankes T
    r = 76
    a0, a1 = math.radians(-72), math.radians(-30)
    pt = lambda a: (100 + r * math.cos(a), 100 + r * math.sin(a))
    s, e = pt(a1), pt(a0 + 2 * math.pi)
    ring = f"M{f(s[0])} {f(s[1])}A{r} {r} 0 1 1 {f(e[0])} {f(e[1])}"
    ax, ay = pt((a0 + a1) / 2)
    mark = (stroke(ring, 7) + "\n" + stroke("M72 72H128M100 72V136", 7) +
            f'\n<circle cx="{f(ax)}" cy="{f(ay)}" r="11" fill="{AMB}"/>')
    w, h, sw = 64, 112, 8
    L, _ = layout(w, h, sw, 46)
    out = []
    for c, x, y in L:
        m, dd = glyph(c, x, y, w, h, "serif")
        out.append(stroke(m, sw))
        if dd:
            out.append(stroke(dd, sw, AMB if c == "H" else INK))
    return mark, "\n".join(out)


DRAFTS = [("01_anschlag", "Anschlag", d1), ("02_metrum", "Metrum", d2), ("03_bahn", "Bahn", d3),
          ("04_leine", "Leine", d4), ("05_raster", "Raster", d5), ("06_emblem", "Emblem", d6)]


def icon_svg(mark):
    s = 0.68
    t = 128 - 100 * s
    return svg(256, 256, f'<rect width="256" height="256" rx="56" fill="{BG}"/>\n'
                         f'<g transform="translate({f(t)} {f(t)}) scale({s})">\n{mark}\n</g>')


def write_svgs():
    os.makedirs(ROOT, exist_ok=True)
    for key, _, fn in DRAFTS:
        mark, word = fn()
        for suf, txt in (("mark", svg(200, 200, mark)), ("wordmark", svg(1000, 250, word)), ("icon", icon_svg(mark))):
            with open(os.path.join(ROOT, f"{key}_{suf}.svg"), "w", encoding="utf-8", newline="\n") as fh:
                fh.write(txt)


def render_pngs():
    if not CHROME:
        sys.exit("kein Chrome/Edge gefunden")
    ROW = 530
    base = ROOT.replace("\\", "/")
    html = ['<html><body style="margin:0;background:transparent">']
    for i, (key, _, _) in enumerate(DRAFTS):
        for suf, x, yy, wd, ht in (("mark", 0, 0, 512, 512), ("icon", 520, 0, 256, 256), ("wordmark", 520, 264, 1000, 250)):
            html.append(f'<img src="file:///{base}/{key}_{suf}.svg" style="position:absolute;left:{x}px;'
                        f'top:{i*ROW+yy}px;width:{wd}px;height:{ht}px">')
    html.append("</body></html>")
    tmp = tempfile.mkdtemp()
    page, shot = os.path.join(tmp, "p.html"), os.path.join(tmp, "s.png")
    with open(page, "w") as fh:
        fh.write("\n".join(html))
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    "--default-background-color=00000000", "--allow-file-access-from-files",
                    f"--window-size=1530,{ROW*len(DRAFTS)+140}", f"--screenshot={shot}",
                    "file:///" + page.replace("\\", "/")],
                   check=True, timeout=120, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    im = Image.open(shot).convert("RGBA")
    for i, (key, _, _) in enumerate(DRAFTS):
        y = i * ROW
        im.crop((0, y, 512, y + 512)).save(os.path.join(ROOT, f"{key}_mark.png"))
        im.crop((520, y, 776, y + 256)).save(os.path.join(ROOT, f"{key}_icon.png"))
        im.crop((520, y + 264, 1520, y + 514)).save(os.path.join(ROOT, f"{key}_wordmark.png"))
    shutil.rmtree(tmp, ignore_errors=True)


def recolor(im):
    """Hell-auf-dunkel -> dunkel-auf-hell; Alpha bleibt (Antialias)."""
    px = im.load()
    src = [(0xEC, 0xE6, 0xDA), (0xF2, 0xA2, 0x3A)]
    dst = [(0x1B, 0x1A, 0x18), (0xC7, 0x7D, 0x12)]
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            di = sum((c - s) ** 2 for c, s in zip((r, g, b), src[0]))
            da = sum((c - s) ** 2 for c, s in zip((r, g, b), src[1]))
            px[x, y] = (*(dst[0] if di <= da else dst[1]), a)
    return im


def overview():
    try:
        fb = ImageFont.load_default(size=28)
        fs = ImageFont.load_default(size=18)
    except TypeError:
        fb = fs = ImageFont.load_default()
    CW, CH, PAD = 1000, 640, 24
    cols, rows = 2, 3
    out = Image.new("RGB", (cols * CW + (cols + 1) * PAD, rows * CH + (rows + 1) * PAD), (70, 68, 64))
    d = ImageDraw.Draw(out)
    for i, (key, name, _) in enumerate(DRAFTS):
        cx, cy = PAD + (i % cols) * (CW + PAD), PAD + (i // cols) * (CH + PAD)
        mark = Image.open(os.path.join(ROOT, f"{key}_mark.png"))
        word = Image.open(os.path.join(ROOT, f"{key}_wordmark.png"))
        icon = Image.open(os.path.join(ROOT, f"{key}_icon.png"))
        for half, light in enumerate((False, True)):
            hx, hw = cx + half * CW // 2, CW // 2
            d.rectangle((hx, cy, hx + hw - 1, cy + CH - 1), fill=BG_L if light else BG)
            m, w_ = mark.copy(), word.copy()
            if light:
                m, w_ = recolor(m), recolor(w_)
            mm = m.resize((260, 260), Image.LANCZOS)
            out.paste(mm, (hx + (hw - 260) // 2, cy + 56), mm)
            ww = w_.resize((440, 110), Image.LANCZOS)
            out.paste(ww, (hx + (hw - 440) // 2, cy + 340), ww)
            x = hx + hw // 2 - 100
            for sz in (16, 32):
                for im in (m, icon):
                    t = im.resize((sz, sz), Image.LANCZOS)
                    out.paste(t, (x, cy + 506 + (32 - sz) // 2), t)
                    x += sz + 14
                x += 14
            ink = (27, 26, 24) if light else (236, 230, 218)
            d.text((hx + 16, cy + 12), f"{i+1}  {name}" if not light else "hell", fill=ink, font=fb)
            d.text((hx + 16, cy + CH - 30), "16 / 32 px: Marke, Icon", fill=(157, 151, 141), font=fs)
    out.save(os.path.join(ROOT, "overview.png"))


# ======================= Endfassung: Entwurf 3 "Bahn" =======================
# Aufruf: python tools/render_logo_drafts.py --final
# Schreibt docs/brand/*, docs/media/*, icon.svg/png, Boot-Splash, tethra.ico und
# die LOGO_SVG-Konstante in scripts/ui/main_menu.gd.
REPO = os.path.normpath(os.path.join(ROOT, "..", "..", ".."))
BRAND = os.path.join(REPO, "docs", "brand")
MONO = "#121110"


def belt(c1, r1, c2, r2, cy=100):
    """Gekreuzter Riemen um zwei Scheiben. Rueckgabe: (Pfad, x des Kreuzungspunkts)."""
    ph = math.acos((r1 + r2) / (c2 - c1))
    co, si = math.cos(ph), math.sin(ph)
    p1u = (c1 + r1 * co, cy - r1 * si); p1l = (c1 + r1 * co, cy + r1 * si)
    p2u = (c2 - r2 * co, cy - r2 * si); p2l = (c2 - r2 * co, cy + r2 * si)
    d = (f"M{f(p1u[0])} {f(p1u[1])}L{f(p2l[0])} {f(p2l[1])}A{r2} {r2} 0 1 0 {f(p2u[0])} {f(p2u[1])}"
         f"L{f(p1l[0])} {f(p1l[1])}A{r1} {r1} 0 1 1 {f(p1u[0])} {f(p1u[1])}Z")
    return d, c1 + r1 / (r1 + r2) * (c2 - c1)


def pal(kind):
    """(Tinte, Bernstein, Grund) je Fassung."""
    return {"dunkel": (INK, AMB, BG), "hell": (INK_L, AMB_L, BG_L), "mono": (MONO, MONO, BG_L)}[kind]


def mark_parts(ink, amb):
    """Bildmarke, Box 8..184 x 48..152 (inkl. Strich)."""
    d, xk = belt(60, 46, 150, 28)
    return stroke(d, 12, ink, "round", "round") + f'\n<circle cx="{f(xk)}" cy="100" r="13" fill="{amb}"/>', (8, 48, 184, 152)


def word_parts(ink, amb):
    w, h, sw = 66, 118, 13
    L, y0 = layout(w, h, sw, 40)
    out = []
    for c, x, y in L:
        m, dd = glyph(c, x, y, w, h)
        out.append(stroke(m + dd, sw, ink, "round", "round"))
    xe = L[-1][1] + w + sw / 2 + 30
    out.append(f'<circle cx="{f(xe)}" cy="{f(y0+h-8)}" r="10" fill="{amb}"/>')
    return "\n".join(out), (L[0][1] - sw / 2, y0 - sw / 2, xe + 10, y0 + h + sw / 2)


def tight(vb, body, pad=0):
    x0, y0, x1, y1 = vb
    x0 -= pad; y0 -= pad; x1 += pad; y1 += pad
    w, h = x1 - x0, y1 - y0
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{f(x0)} {f(y0)} {f(w)} {f(h)}" '
            f'width="{f(w)}" height="{f(h)}">\n<title>TETHRA</title>\n{body}\n</svg>\n'), w, h


def lockup_parts(ink, amb):
    """Marke links, Wortmarke rechts, Ursprung oben links. Rueckgabe (Koerper, Breite, Hoehe)."""
    m, (mx0, my0, mx1, my1) = mark_parts(ink, amb)
    w_, (wx0, wy0, wx1, wy1) = word_parts(ink, amb)
    gap = 46
    H = max(my1 - my0, wy1 - wy0)
    mw = mx1 - mx0
    body = (f'<g transform="translate({f(-mx0)} {f((H-(my1-my0))/2-my0)})">\n{m}\n</g>\n'
            f'<g transform="translate({f(mw+gap-wx0)} {f((H-(wy1-wy0))/2-wy0)})">\n{w_}\n</g>')
    return body, mw + gap + (wx1 - wx0), H


def small_icon(kind="dunkel"):
    """Vereinfachte Variante fuer 16-48 px: dickere Linie, grosser Punkt, der den Kreuzungsspalt deckt."""
    ink, amb, bg = pal(kind)
    d, xk = belt(22.5, 13, 46.5, 8, 32)
    body = (f'<rect width="64" height="64" rx="12" fill="{bg}"/>\n'
            + stroke(d, 9, ink, "round", "round")
            + f'\n<circle cx="{f(xk)}" cy="32" r="9.5" fill="{amb}"/>')
    return svg(64, 64, body)


def big_icon(kind="dunkel"):
    ink, amb, bg = pal(kind)
    m, _ = mark_parts(ink, amb)
    s = 1.15
    # Marke (Mitte 96,100) mittig in Kachel 256
    return svg(256, 256, f'<rect width="256" height="256" rx="56" fill="{bg}"/>\n'
                         f'<g transform="translate({f(128-96*s)} {f(128-100*s)}) scale({s})">\n{m}\n</g>')


def chrome_png(svg_path, out_png, w, h, bg="00000000"):
    tmp = tempfile.mkdtemp()
    page = os.path.join(tmp, "p.html")
    with open(page, "w") as fh:
        fh.write(f'<html><body style="margin:0;background:transparent"><img src="file:///{svg_path.replace(chr(92), "/")}" '
                 f'style="position:absolute;left:0;top:0;width:{w}px;height:{h}px"></body></html>')
    shot = os.path.join(tmp, "s.png")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--default-background-color={bg}", "--allow-file-access-from-files",
                    f"--window-size={w},{h+120}", f"--screenshot={shot}", "file:///" + page.replace("\\", "/")],
                   check=True, timeout=120, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    Image.open(shot).convert("RGBA").crop((0, 0, w, h)).save(out_png)
    shutil.rmtree(tmp, ignore_errors=True)


def ld(p):
    with Image.open(p) as im:
        return im.convert("RGBA")


def wr(path, txt):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(txt)


def write_ico(path, pngs):
    import io, struct
    items = sorted(pngs.items())
    blobs = []
    for sz, im in items:
        bio = io.BytesIO()
        im.save(bio, "PNG")
        blobs.append(bio.getvalue())
    head = struct.pack("<HHH", 0, 1, len(items))
    off = 6 + 16 * len(items)
    ent = b""
    for (sz, _), bl in zip(items, blobs):
        ent += struct.pack("<BBBBHHII", sz % 256, sz % 256, 0, 0, 1, 32, len(bl), off)
        off += len(bl)
    with open(path, "wb") as fh:
        fh.write(head + ent + b"".join(blobs))


def final():
    import re
    if not CHROME:
        sys.exit("kein Chrome/Edge gefunden")
    sfx = {"dunkel": "", "hell": "_hell", "mono": "_mono"}
    for kind, sf in sfx.items():
        ink, amb, _ = pal(kind)
        m, vb = mark_parts(ink, amb)
        wr(os.path.join(BRAND, f"logo{sf}.svg"), tight(vb, m, 4)[0])
        w_, vb = word_parts(ink, amb)
        wr(os.path.join(BRAND, f"wordmark{sf}.svg"), tight(vb, w_, 4)[0])
        body, lw, lh = lockup_parts(ink, amb)
        wr(os.path.join(BRAND, f"lockup{sf}.svg"), tight((0, 0, lw, lh), body, 4)[0])
        wr(os.path.join(BRAND, f"icon{sf}.svg"), big_icon(kind))
        wr(os.path.join(BRAND, f"icon_klein{sf}.svg"), small_icon(kind))
    body, lw, lh = lockup_parts(INK, AMB)
    LW, LH = lw + 8, lh + 8
    # README-Kopf: dunkle Tinte als SVG (heller Grund), helle Tinte als PNG (Dark Mode)
    wr(os.path.join(REPO, "docs", "media", "logo.svg"), open(os.path.join(BRAND, "lockup_hell.svg"), encoding="utf-8").read())
    chrome_png(os.path.join(BRAND, "lockup.svg"), os.path.join(REPO, "docs", "media", "logo_wordmark.png"),
               int(LW * 1.5), int(LH * 1.5))
    # Spiel-Icon
    wr(os.path.join(REPO, "icon.svg"), big_icon("dunkel").replace('width="256" height="256"', 'width="128" height="128"', 1))
    chrome_png(os.path.join(BRAND, "icon.svg"), os.path.join(REPO, "icon.png"), 256, 256)
    # ICO: 16-48 vereinfachte Variante, ab 64 volle Marke
    pngs, tmp = {}, os.path.join(BRAND, "_t.png")
    for sz in (16, 24, 32, 48):
        chrome_png(os.path.join(BRAND, "icon_klein.svg"), tmp, sz, sz)
        pngs[sz] = ld(tmp)
    for sz in (64, 128, 256):
        chrome_png(os.path.join(BRAND, "icon.svg"), tmp, sz, sz)
        pngs[sz] = ld(tmp)
    os.remove(tmp)
    write_ico(os.path.join(REPO, "tools", "installer", "tethra.ico"), pngs)
    # Pruefblatt kleine Groessen (4x vergroessert, harte Pixel)
    sheet = Image.new("RGB", (240, 80), BG)
    x = 10
    for sz in (16, 24, 32, 48):
        sheet.paste(pngs[sz], (x, 10), pngs[sz])
        x += sz + 12
    sheet.resize((960, 320), Image.NEAREST).save(os.path.join(BRAND, "icon_klein_pruefblatt.png"))
    # Boot-Splash
    ui = os.path.join(REPO, "assets_game", "ui")
    os.makedirs(ui, exist_ok=True)
    chrome_png(os.path.join(BRAND, "lockup.svg"), tmp, 640, int(round(640 * LH / LW)))
    lg = ld(tmp)
    sp = Image.new("RGBA", (1280, 720), BG)
    sp.alpha_composite(lg, ((1280 - lg.width) // 2, (720 - lg.height) // 2))
    sp.convert("RGB").save(os.path.join(ui, "boot_splash.png"))
    # Social Preview
    chrome_png(os.path.join(BRAND, "lockup.svg"), tmp, 800, int(round(800 * LH / LW)))
    lg = ld(tmp)
    soc = Image.new("RGBA", (1280, 640), BG)
    y0 = 200
    soc.alpha_composite(lg, ((1280 - lg.width) // 2, y0))
    d = ImageDraw.Draw(soc)
    try:
        ft = ImageFont.truetype(r"C:\Windows\Fonts\segoeui.ttf", 30)
    except OSError:
        ft = ImageFont.load_default()
    txt = "Free rhythm game for Windows. osu!mania maps in 3D, 2D and Orbit."
    d.text(((1280 - d.textlength(txt, font=ft)) / 2, y0 + lg.height + 50), txt, font=ft, fill=(157, 151, 141, 255))
    soc.convert("RGB").save(os.path.join(REPO, "docs", "media", "social_preview.png"))
    os.remove(tmp)
    # Menue: LOGO_SVG
    mm = os.path.join(REPO, "scripts", "ui", "main_menu.gd")
    src = open(mm, encoding="utf-8").read()
    k = 600 / LW
    mw_, mh_ = int(round(LW * k)), int(round(LH * k))
    ms = tight((0, 0, lw, lh), body, 4)[0].replace("<title>TETHRA</title>\n", "").strip()
    ms = re.sub(r'width="[\d.]+" height="[\d.]+"', f'width="{mw_}" height="{mh_}"', ms, count=1)
    a = src.index("const LOGO_SIZE")
    b = src.index('</svg>"""', a) + len('</svg>"""')
    new = f'const LOGO_SIZE := Vector2({mw_}, {mh_})\nconst LOGO_SVG := """{ms}"""'
    with open(mm, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(src[:a] + new + src[b:])
    print("final ok", LW, LH)


if __name__ == "__main__":
    if "--final" in sys.argv:
        final()
    else:
        write_svgs()
        render_pngs()
        overview()
        print("ok")
