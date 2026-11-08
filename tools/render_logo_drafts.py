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


if __name__ == "__main__":
    write_svgs()
    render_pngs()
    overview()
    print("ok")
