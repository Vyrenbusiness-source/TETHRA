"""TETHRA-Logo-Generator: icon.svg, tools/installer/tethra.ico,
docs/media/logo.svg, docs/media/logo_wordmark.png und LOGO_SVG in
scripts/ui/main_menu.gd aus einer Geometrie.

    python tools/logo/build.py <repo-root>

Braucht Pillow. Form: vier Spuren in Fluchtperspektive + Urteilslinie, eine
Note auf Spur 2; Wortmarke TETHRA aus eigenen Strichformen (keine Schriftdatei).
"""
import io, math, struct, sys
from PIL import Image, ImageDraw, ImageChops

# ---- Geometrie (Polygone, Rendern mit Supersampling) ----

def rect(x, y, w, h):
    return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]

def rrect(x, y, w, h, r, n=12):
    pts = []
    for cx, cy, a0 in ((x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90), (x + r, y + r, 180)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts

def circle(cx, cy, r, n=96):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]

def render(elems, w, h, scale, ss=8, bg=None):
    W, H = int(round(w * scale)), int(round(h * scale))
    k = scale * ss
    out = Image.new("RGBA", (W, H), bg or (0, 0, 0, 0))
    for color, subs in elems:
        m = None
        for sp in subs:
            mm = Image.new("1", (W * ss, H * ss), 0)
            ImageDraw.Draw(mm).polygon([(x * k, y * k) for x, y in sp], fill=1)
            m = mm if m is None else ImageChops.logical_xor(m, mm)
        a = m.convert("L").resize((W, H), Image.BOX)
        layer = Image.new("RGBA", (W, H), color)
        out = Image.composite(layer, out, a) if color[3] == 255 else Image.alpha_composite(out, Image.composite(layer, Image.new("RGBA", (W, H), (0,0,0,0)), a))
    return out

def hexc(c):
    return "#%02x%02x%02x" % c[:3]

def fmt(v):
    s = ("%.2f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s

def svg(elems, w, h, ow=None, oh=None):
    ow = ow or w; oh = oh or h
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s">' % (fmt(ow), fmt(oh), fmt(w), fmt(h))]
    for color, subs in elems:
        d = " ".join("M" + " L".join("%s %s" % (fmt(x), fmt(y)) for x, y in sp) + " Z" for sp in subs)
        op = "" if color[3] == 255 else ' fill-opacity="%s"' % fmt(color[3] / 255)
        rule = ' fill-rule="evenodd"' if len(subs) > 1 else ""
        out.append('  <path fill="%s"%s%s d="%s"/>' % (hexc(color), op, rule, d))
    out.append("</svg>")
    return "\n".join(out) + "\n"

# ---- Wortmarke ----
H=100.0; S=17.0; SH=15.0; C=14.0   # cap height, vertical stroke, horizontal stroke, chamfer
def T(w=84): return [[rect(0,0,w,SH)],[rect(w/2-S/2,0,S,H)]],w
def E(w=68): return [[rect(0,0,S,H)],[rect(0,0,w,SH)],[rect(0,(H-SH)/2,w-8,SH)],[rect(0,H-SH,w,SH)]],w
def Hh(w=78): return [[rect(0,0,S,H)],[rect(w-S,0,S,H)],[rect(0,(H-SH)/2,w,SH)]],w
def R(w=76):
    B=(H+SH)/2  # bowl bottom = bottom of middle bar
    ci=C-S*math.tan(math.radians(22.5))
    outer=[(0,0),(w-C,0),(w,C),(w,B-C),(w-C,B),(0,B)]
    inner=[(S,SH),(w-S-ci,SH),(w-S,SH+ci),(w-S,B-SH-ci),(w-S-ci,B-SH),(S,B-SH)]
    # leg: from bowl bottom (x a) down to (w,H)
    a=w*0.42; dy=H-B; 
    L=S*1.0
    for _ in range(20):
        dx=w-L-a; L=S*math.hypot(dx,dy)/dy
    leg=[(a,B-0.01),(a+L,B-0.01),(w,H),(w-L,H)]
    return [[rect(0,0,S,H)],[outer,inner],[leg]],w
def A(w=86):
    a=S*0.55; cx=w/2
    xo=lambda y:(cx-a)*(1-y/H)
    dx=cx-a; hS=S*math.hypot(dx,H)/H
    xl=lambda y:xo(y)+hS; xr=lambda y:w-xl(y)
    cb0=H*0.62; cb1=cb0+SH
    outer=[(cx-a,0),(cx+a,0),(w,H),(0,H)]
    yap=H*(1-(cx-hS)/(cx-a))
    counter=[(cx,yap),(xr(cb0),cb0),(xl(cb0),cb0)]
    notch=[(xl(cb1),cb1),(xr(cb1),cb1),(xr(H),H),(xl(H),H)]
    return [[outer,counter,notch]],w
def wordmark(color,x0=0,y0=0,track=17.0,scale=1.0):
    els=[]; x=0
    for g in (T(),E(),T(),Hh(),R(),A()):
        parts,w=g
        for subs in parts:
            els.append((color,[[(x0+(px+x)*scale,y0+py*scale) for px,py in sp] for sp in subs]))
        x+=w+track
    return els,(x-track)*scale

# ---- Logo ----
# Farben = UiTheme (scripts/ui/ui_theme.gd): Graphit-Kachel, Spuren in
# Signal-Bernstein, die Note in Elfenbein. CY/PK sind nur noch Rollennamen
# (Spur / Note) aus der ersten Cyan-Pink-Fassung.
TILE=(18,17,16,255)        # UiTheme.BG     #121110
CY=(242,162,58,255)        # UiTheme.ACCENT #F2A23A  (Spuren + Urteilslinie)
PK=(236,230,218,255)       # UiTheme.TEXT   #ECE6DA  (Note)
INK_DARK=(236,230,218,255) # Schrift auf dunklem Grund
INK_LIGHT=(18,17,16,255)   # Schrift auf hellem Grund
def lerp(a,b,t): return a+(b-a)*t

def mark(design="big", tile=True, ox=0, oy=0, k=1.0):
    """Lanes + judgement line. Lane 2 is split around the note, so no overdraw."""
    if design=="big":
        size,r,y0,y1=64,14,9,43
        bot=[(8,17),(20,29),(35,44),(47,56)]; vx,vy=32,-20
        s=(y0-vy)/(y1-vy); top=[(vx+(a-vx)*s,vx+(b-vx)*s) for a,b in bot]
        note=(1,20,26,2.5); base=(8,48,48,6)
    else:  # 16 px pixel-tuned
        size,r,y0,y1=16,3,2,11
        top=[(4,5),(6,7),(9,10),(11,12)]; bot=[(2,4),(5,7),(9,11),(12,14)]
        note=(1,5,7,1); base=(2,12,12,2)
    T=lambda x,y:(ox+x*k,oy+y*k)
    e=[]
    if tile: e.append(("tile",(ox,oy,size*k,r*k)))
    X=lambda i,side,y: lerp(top[i][side],bot[i][side],(y-y0)/(y1-y0))
    q=lambda i,a,b:[T(X(i,0,a),a),T(X(i,1,a),a),T(X(i,1,b),b),T(X(i,0,b),b)]
    ni,na,nb,pad=note
    for i in range(4):
        if i==ni:
            e.append((CY,[q(i,y0,na-pad)])); e.append((PK,[q(i,na,nb)])); e.append((CY,[q(i,nb+pad,y1)]))
        else:
            e.append((CY,[q(i,y0,y1)]))
    bx,by,bw,bh=base
    e.append((CY,[[T(bx,by),T(bx+bw,by),T(bx+bw,by+bh),T(bx,by+bh)]]))
    return e,size*k

def to_poly(e):
    out=[]
    for c,v in e:
        if c=="tile":
            x,y,s,r=v; out.append((TILE,[rrect(x,y,s,s,r,24)]))
        else: out.append((c,v))
    return out

def to_svg(e,w,h,ow,oh,title):
    L=['<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s">'%(fmt(ow),fmt(oh),fmt(w),fmt(h)),
       '  <title>%s</title>'%title]
    for c,v in e:
        if c=="tile":
            x,y,s,r=v
            L.append('  <rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s"/>'%(fmt(x),fmt(y),fmt(s),fmt(s),fmt(r),hexc(TILE)))
            continue
        d=" ".join("M"+" L".join("%s %s"%(fmt(a),fmt(b)) for a,b in sp)+" Z" for sp in v)
        rule=' fill-rule="evenodd"' if len(v)>1 else ""
        L.append('  <path fill="%s"%s d="%s"/>'%(hexc(c),rule,d))
    L.append("</svg>")
    return "\n".join(L)+"\n"

def lockup(ink, tile=True):
    """Mark (128) + wordmark (cap height 64), centred on the mark."""
    m,ms=mark("big",tile,0,0,2.0)
    cap=66.0; sc=cap/100.0; gap=34.0
    w,ww=wordmark(ink,ms+gap,(ms-cap)/2,17.0,sc)
    return m+w, ms+gap+ww, ms

def ico(path):
    imgs=[]
    for s in (16,24,32,48,64,128,256):
        if s<=16: e,sz=mark("small"); im=render(to_poly(e),sz,sz,s/sz,16)
        else: e,sz=mark("big"); im=render(to_poly(e),sz,sz,s/sz,16)
        b=io.BytesIO(); im.save(b,"PNG",optimize=True); imgs.append((s,b.getvalue()))
    hdr=struct.pack("<HHH",0,1,len(imgs)); off=6+16*len(imgs); ent=b""; data=b""
    for s,png in imgs:
        ent+=struct.pack("<BBBBHHII",s%256,s%256,0,0,1,32,len(png),off+len(data)); data+=png
    open(path,"wb").write(hdr+ent+data)

if __name__=="__main__":
    root=sys.argv[1]
    e,sz=mark("big")
    open(root+"/icon.svg","w",newline="\n").write(to_svg(e,64,64,128,128,"TETHRA"))
    ico(root+"/tools/installer/tethra.ico")
    e,w,h=lockup(INK_LIGHT)
    open(root+"/docs/media/logo.svg","w",newline="\n").write(to_svg(e,w,h,w,h,"TETHRA"))
    e,w,h=lockup(INK_DARK)
    render(to_poly(e),w,h,2.0,8).save(root+"/docs/media/logo_wordmark.png",optimize=True)
    # Menue: Lockup ohne Kachel, helle Schrift -> LOGO_SVG in main_menu.gd
    e,w,h=lockup(INK_DARK,tile=False)
    menu=to_svg(e,w,h,w,h,"TETHRA").replace("  <title>TETHRA</title>\n","").rstrip("\n")
    mp=root+"/scripts/ui/main_menu.gd"
    src=open(mp,encoding="utf-8",newline="").read()
    a=src.index('const LOGO_SVG := """')+len('const LOGO_SVG := """')
    b=src.index('"""',a)
    nl="\r\n" if "\r\n" in src else "\n"
    open(mp,"w",encoding="utf-8",newline="").write(src[:a]+menu.replace("\n",nl)+src[b:])
    print("lockup",w,h)
