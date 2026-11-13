#!/bin/bash
# OMEN-Trailer (16:9, 1920x1080, 60 fps). Aufruf:
#   tools/make_trailer.sh [record|cut|all]      (Standard: all)
# Env: WORK=<Ordner fuer Zwischendateien (Rohclips), am Ende loeschen>, ONLY=<Teil des Clip-Namens>
#      MAP=<Teil des osz-Namens>, DIFF=<Version>, OUT=<mp4>
# Ablauf: Clips je (Modus, Welt) per Godot Movie Maker aufnehmen (Autoplay ab exakter
# Songzeit, --nohud, --lang=en), Songzeit pro Clip per Audio-Korrelation gegen das
# Original-Audio aus der osz bestimmen, auf Takt-Grenzen schneiden, EINE Tonspur
# (Original-Audio) darunter. Nur selbst-beendend (timeout), kein Godot danach offen.
set -u
STEP=${1:-all}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G=${GODOT:-/c/Users/Gexanx/Desktop/rhyg/Godot_v4.7-stable_win64_console.exe}
FF=${FFMPEG:-/c/Users/Gexanx/Desktop/rhyg/release/stage/ffmpeg.exe}
export WORK=${WORK:-${TMPDIR:-/tmp}/trailer_work}
export FULLDIFF=${FULLDIFF:-Helpless Resistance: Despair}
export MAP=${MAP:-Calamity} DIFF=${DIFF:-Despair} FF G ROOT ONLY=${ONLY:-}
export OSZ_DIR=${OSZ_DIR:-/c/Users/Gexanx/Desktop/rhyg/maps}
export LOGO=${LOGO:-/c/Users/Gexanx/Desktop/rhyg/docs/media/logo_wordmark.png}
export OUT=${OUT:-C:/Users/Gexanx/Desktop/OMEN_Trailer.mp4}
export STEP
mkdir -p "$WORK"
cd "$ROOT" || exit 1
python -I - <<'PYEOF'
import os, sys, json, subprocess, glob, shutil, zipfile, re, time
import numpy as np
from scipy.signal import fftconvolve

W = os.environ["WORK"]; FF = os.environ["FF"]; G = os.environ["G"]; STEP = os.environ["STEP"]
ONLY = os.environ.get("ONLY", "")
FULLDIFF = os.environ.get("FULLDIFF", "Helpless Resistance: Despair")
SR = 22050
# Takt-Einheit u: 0..8 = 170 BPM ab 1393 ms (je 1411.76 ms), ab u=8 210 BPM ab 12686 ms (je 1142.857 ms)
BAR_A = 60000.0 / 170 * 4
BAR_B = 60000.0 / 210 * 4
def tm(u):
    return 1393.0 + u * BAR_A if u <= 8 else 12686.0 + (u - 8) * BAR_B
B0, B1 = 0, 68                    # Trailer: 1393 ms .. 81257 ms (79,9 s); Drop 30971 = u24, Kiai 40114 = u32, 58400 = u48
T0 = tm(B0)
FPS = 60
bar = tm

def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)

# ---------------------------------------------------------------- Plan
# (start_u, laenge_in_takten, modus, welt, flash)
cuts = []
def add(b, n, mode, world="", flash=False): cuts.append((b, n, mode, world, flash))
add(0, 2, "title")
for i, w in enumerate(["galaxy", "neon", "aurora", "abyss"]):
    add(2 + 2 * i, 2, "3d", w)
add(10, 2, "2d"); add(12, 2, "orbit"); add(14, 2, "rally")
add(16, 2, "dirigent"); add(18, 2, "trace"); add(20, 2, "rebound")
add(22, 2, "3d", "fractal")
seq = ["3d", "2d", "orbit", "rally", "dirigent", "trace", "rebound"]
drop_worlds = ["singularity", "storm", "boss", "obsidian", "rift", "monolith", "nerve", "eclipse"]
st = {"k": 0, "wi": 0}
def nxt():
    m = seq[st["k"] % 7]; st["k"] += 1; w = ""
    if m == "3d": w = drop_worlds[st["wi"] % len(drop_worlds)]; st["wi"] += 1
    return m, w
def run_cuts(a, e, step):
    b = float(a)
    while b < e - 1e-9:
        m, w = nxt()
        add(b, step, m, w, flash=(abs((b - 24) % 4) < 1e-9))
        b += step
run_cuts(24, 32, 1)        # Drop: jeder Takt
run_cuts(32, 38, 0.5)      # Kiai: Beats (2er-Gruppen)
run_cuts(38, 48, 1)
run_cuts(48, 56, 0.5)
run_cuts(56, 62, 1)
add(62, 2, "3d", "galaxy"); add(64, 4, "end")
assert abs(sum(c[1] for c in cuts) - (B1 - B0)) < 1e-9, sum(c[1] for c in cuts)

def spans():
    """Aufnahmen: (modus, welt) -> zusammenhaengende Songzeit-Bereiche (ms)."""
    out = []
    for (b, n, m, w, f) in cuts:
        if m in ("title", "end"): continue
        a, e = bar(b), bar(b + n)
        key = (m, w)
        gap = 600.0 if m == "3d" else 12000.0
        for s in out:
            if s["key"] == key and a - s["end"] <= gap and a >= s["start"]:
                s["end"] = max(s["end"], e); break
        else:
            out.append({"key": key, "start": a, "end": e})
    for i, s in enumerate(out):
        m, w = s["key"]
        s["name"] = "%02d_%s%s" % (i, m, ("_" + w) if w else "")
        s["rs"] = s["start"] - 300.0
        s["len"] = (s["end"] - s["rs"]) / 1000.0 + 0.7
    return out
SP = spans()

# ---------------------------------------------------------------- Audio aus osz
def song_assets():
    d = os.path.join(W, "song"); os.makedirs(d, exist_ok=True)
    osz = [p for p in glob.glob(os.path.join(os.environ["OSZ_DIR"], "*.osz")) if os.environ["MAP"].lower() in os.path.basename(p).lower()][0]
    mp3 = os.path.join(d, "audio.mp3")
    if not os.path.exists(mp3):
        with zipfile.ZipFile(osz) as z:
            z.extract("audio.mp3", d)
            for n in z.namelist():
                if n.lower().endswith(".jpg"): z.extract(n, d)
    wav = os.path.join(d, "audio.wav")
    if not os.path.exists(wav):
        run([FF, "-v", "error", "-y", "-i", mp3, "-ac", "1", "-ar", str(SR), wav])
    return mp3, wav
mp3, songwav = song_assets()
def readwav(p):
    with open(p, "rb") as f: raw = f.read()
    i = raw.index(b"data") + 8
    return np.frombuffer(raw[i:], dtype="<i2").astype(np.float64)
song = readwav(songwav)

def dump_audio(src, dst, ss=0.0, t=None):
    cmd = [FF, "-v", "error", "-y", "-ss", str(ss), "-i", src, "-vn", "-ac", "1", "-ar", str(SR), "-f", "wav"]
    if t: cmd += ["-t", str(t)]
    run(cmd + [dst])

def correlate(clip_wav, expected_ms):
    """Songzeit (ms) bei Clip-Zeit 0 per Kreuzkorrelation mit dem Original."""
    c = readwav(clip_wav)
    seg0 = int(0.4 * SR); seg1 = min(len(c), int(4.4 * SR))
    q = c[seg0:seg1]
    lo = max(0, int((expected_ms / 1000.0 - 3.0) * SR)); hi = min(len(song), int((expected_ms / 1000.0 + 8.0) * SR) + len(q))
    ref = song[lo:hi]
    q = q - q.mean(); ref0 = ref - ref.mean()
    cc = fftconvolve(ref0, q[::-1], mode="valid")
    e = np.sqrt(fftconvolve(ref0 ** 2, np.ones(len(q)), mode="valid").clip(1e-6, None))
    sc = cc / (e * np.sqrt((q ** 2).sum()) + 1e-9)
    j = int(np.argmax(sc))
    pos = (lo + j) / SR * 1000.0                    # Songzeit des Clip-Abschnitts ab 0.4 s
    return pos - 400.0, float(sc[j])

# ---------------------------------------------------------------- Aufnahme
def args_for(s):
    m, w = s["key"]
    shot_at = s["rs"] + 2500.0
    common = ["--autoplay", "--lang=en", "--nohud", "--%s-diff=%s" % (m, FULLDIFF), "--shot",
              "--shot-at=%d" % round(shot_at), "--movie-len=%.2f" % s["len"]]
    scene = ["res://scenes/song_select.tscn"]
    if m in ("3d", "2d"):
        a = ["--mode=mania", "--map=" + os.environ["MAP"], "--diff=" + os.environ["DIFF"], "--shot-lead=0"]
        if m == "2d": a.append("--2d")
        else: a += ["--3d", "--theme=" + w]
        return scene + a + common
    if m == "dirigent":   # eigener Filmmodus: --movie-from (spult auf from-2,5 s), kein --shot
        return scene + ["--mode=dirigent", "--dirigent-map=" + os.environ["MAP"], "--dirigent-diff=" + FULLDIFF, "--autoplay", "--lang=en",
                        "--movie-from=%d" % round(shot_at), "--movie-len=%.2f" % s["len"]]
    return scene + ["--mode=" + m, "--%s-map=%s" % (m, os.environ["MAP"])] + common

def record(s):
    clip = os.path.join(W, s["name"] + ".mp4")
    meta = os.path.join(W, s["name"] + ".json")
    if os.path.exists(meta): return
    avi = os.path.join(W, "raw_" + s["name"] + ".avi"); log = os.path.join(W, s["name"] + ".log")
    if os.path.exists(avi): os.remove(avi)
    shutil.copy("tools/test_override.cfg", "override.cfg")
    with open("override.cfg", "a") as of:
        of.write(chr(10).join(["window/size/window_width_override=1920", "window/size/window_height_override=1080", "window/size/borderless=true", ""]))
    try:
        cmd = [G, "--path", ".", "--audio-driver", "Dummy", "--write-movie", avi,
               "--fixed-fps", str(FPS), "--resolution", "1920x1080", "--position", "-1920,0"] + args_for(s)
        with open(log, "w") as lf:
            try:
                subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT, timeout=400)
            except subprocess.TimeoutExpired:
                subprocess.run(["taskkill", "/F", "/T", "/IM", os.path.basename(G)], capture_output=True)
    finally:
        if os.path.exists("override.cfg"): os.remove("override.cfg")
    txt = open(log, errors="replace").read()
    mm = re.search(r"MOVIE_START frame=(\d+)", txt)
    if not mm or not os.path.exists(avi):
        print("FEHLER kein MOVIE_START:", s["name"], log); return
    f0 = int(mm.group(1))
    n = int(s["len"] * FPS)
    run([FF, "-v", "error", "-y", "-ss", "%.5f" % (f0 / FPS), "-i", avi, "-frames:v", str(n), "-an",
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "10", "-pix_fmt", "yuv420p", "-r", str(FPS), clip])
    # Songzeit bei Clip-Bild 0: Mania druckt sie (MOVIE_START ... t=), sonst aus dem Sprungpunkt
    # (Film-Uhr deterministisch 1/60 s je Bild; gemessen: Sprungpunkt + 2 ms).
    mt = re.search(r"MOVIE_START frame=\d+ t=([0-9.]+)", txt)
    t_song = float(mt.group(1)) if mt else round(s["rs"] + 2500.0) - 2500.0 + 2.0
    score = 1.0 if mt else 0.0
    if not os.environ.get("KEEP"): os.remove(avi)
    json.dump({"s0": t_song, "score": score, "f0": f0}, open(meta, "w"))
    print("clip %s: Songzeit bei Clip 0 = %.1f ms (Sprung ~%.0f, gemessen=%.0f)" % (s["name"], t_song, s["rs"], score), flush=True)

if STEP in ("record", "all"):
    for s in SP:
        if ONLY and ONLY not in s["name"]: continue
        record(s)

# ---------------------------------------------------------------- Karten
def card(kind, path):
    from PIL import Image, ImageDraw, ImageFont
    Wd, Ht = 1920, 1080
    px = np.zeros((Ht, Wd, 3), np.float32)
    yy, xx = np.mgrid[0:Ht, 0:Wd]
    r = np.sqrt(((xx - Wd / 2) / Wd) ** 2 + ((yy - Ht / 2) / Ht) ** 2)
    glow = np.clip(1 - r * 1.6, 0, 1) ** 2
    px[..., 0] = 9 + 26 * glow; px[..., 1] = 11 + 40 * glow; px[..., 2] = 20 + 70 * glow
    bg = Image.fromarray(px.astype(np.uint8))
    lg = Image.open(os.environ["LOGO"]).convert("RGBA")
    sc = 1280 / lg.width
    lg = lg.resize((1280, int(lg.height * sc)), Image.LANCZOS)
    bg.paste(lg, ((Wd - lg.width) // 2, 400), lg)
    d = ImageDraw.Draw(bg)
    if kind == "title":
        f = ImageFont.truetype("C:/Windows/Fonts/segoeuil.ttf", 54)
        t = "SIX WAYS TO PLAY ONE SONG"
    else:
        f = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 50)
        t = "OMEN  \u00b7  free  \u00b7  github.com/Vyrenbusiness-source/OMEN"
    w = d.textlength(t, font=f)
    d.text(((Wd - w) / 2, 400 + lg.height + 70), t, font=f, fill=(190, 205, 235))
    bg.save(path)
for kind in ("title", "end"):
    p = os.path.join(W, "card_%s.png" % kind)
    if not os.path.exists(p): card(kind, p)

# ---------------------------------------------------------------- Schnitt
if STEP in ("cut", "all"):
    segdir = os.path.join(W, "seg"); os.makedirs(segdir, exist_ok=True)
    metas = {}
    for s in SP:
        mp = os.path.join(W, s["name"] + ".json")
        if os.path.exists(mp): metas[s["name"]] = json.load(open(mp))
    def span_for(m, w, a, e):
        for s in SP:
            if s["key"] == (m, w) and s["start"] - 1 <= a and e <= s["end"] + 1: return s
    total = round((bar(B1) - T0) * FPS / 1000.0)
    listing = []; log = []
    for i, (b, n, m, w, flash) in enumerate(cuts):
        a, e = bar(b), bar(b + n)
        fa = round((a - T0) * FPS / 1000.0); fe = round((e - T0) * FPS / 1000.0)
        nf = fe - fa
        out = os.path.join(segdir, "%02d.mp4" % i)
        if m in ("title", "end"):
            png = os.path.join(W, "card_%s.png" % m)
            vf = "format=yuv420p,fade=t=in:st=0:d=0.5" if m == "title" else "format=yuv420p,fade=t=in:st=0:d=0.4,fade=t=out:st=%.3f:d=1.2" % (nf / FPS - 1.2)
            run([FF, "-v", "error", "-y", "-loop", "1", "-framerate", str(FPS), "-i", png, "-frames:v", str(nf),
                 "-vf", vf, "-c:v", "libx264", "-crf", "12", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-r", str(FPS), out])
        else:
            s = span_for(m, w, a, e)
            if s is None or s["name"] not in metas:
                print("FEHLT Clip fuer Schnitt", i, m, w); sys.exit(2)
            s0 = metas[s["name"]]["s0"]
            src = round((a - s0) * FPS / 1000.0)
            err = (s0 + src * 1000.0 / FPS) - a
            log.append("%02d %-8s %-12s bar %5.1f  cutfehler %+.1f ms" % (i, m, w, b, err))
            vf = "format=yuv420p"
            if flash: vf += ",fade=t=in:st=0:d=%.4f:color=white" % (3 / FPS)
            run([FF, "-v", "error", "-y", "-i", os.path.join(W, s["name"] + ".mp4"), "-vf", "select='gte(n,%d)',setpts=PTS-STARTPTS,%s" % (src, vf),
                 "-frames:v", str(nf), "-c:v", "libx264", "-crf", "12", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-r", str(FPS), out])
        listing.append("file '%s'" % out.replace("\\", "/"))
    open(os.path.join(W, "list.txt"), "w").write("\n".join(listing))
    open(os.path.join(W, "cutlog.txt"), "w").write("\n".join(log))
    dur = total / FPS
    out = os.environ["OUT"]
    run([FF, "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", os.path.join(W, "list.txt"),
         "-ss", "%.4f" % (T0 / 1000.0), "-t", "%.4f" % dur, "-i", mp3,
         "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-profile:v", "high", "-preset", "slow", "-crf", "18",
         "-pix_fmt", "yuv420p", "-r", str(FPS), "-af", "afade=t=out:st=%.3f:d=2.0" % (dur - 2.0),
         "-c:a", "aac", "-b:a", "320k", "-movflags", "+faststart", out])
    print("Trailer:", out, "%.2f s, %d Bilder" % (dur, total))
PYEOF
