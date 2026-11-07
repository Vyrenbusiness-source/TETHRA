#!/usr/bin/env python3
"""beat_sync_check.py - objektive Messung "liegt die Welt auf dem Beat?".

Rendert per Godot Movie-Maker (--fixed-fps 60) ein paar Sekunden Gameplay
(song_select.tscn --mania --autoplay) als PNG-Frames + WAV, misst pro Frame die
mittlere Helligkeit (Luma) in Bildregionen und berichtet pro Region:

  * Phase der Helligkeitsspitze je Beat relativ zum Beat (Mittel/Streuung, ms)
  * Pulsstaerke (Spitze/Tal je Beat) und Beat-Kopplung (R^2 des beat-gefalteten
    Profils an der trendbereinigten Helligkeit)

Zeitbasis (das Entscheidende):
  * Frame k liegt im Film bei k/60 s. Die Audio-Spur des Films ist frame-genau
    (Movie-Maker mischt pro Frame genau rate/60 Samples). Die Song-Zeit des
    Frames ist darum t_audio(k) = (k - k_play)/60 s + Startposition, wobei
    k_play der Frame ist, in dem der Song (nach dem Lead-In) zu spielen beginnt.
    Lead-In-Stille, Ausgabelatenz und Spiel-Offsets stecken damit NICHT in der
    Referenz: sie ist das, was der Zuschauer im Film hoert.
  * Zum Vergleich wird auch die Spiel-eigene Bildzeit (SyncClock.visual_time_ms,
    inkl. Settings.visual_offset_ms) je Frame mitgeschrieben. So sieht man,
    ob die FX dem Beat-Takt des Spiels folgen (Logik) und ob die Spieluhr
    unter Movie-Maker zur Audio-Spur passt (Uhr).
  * Beat-Raster aus den roten Timing-Points der gespielten Map (Offset = Zeit
    des Timing-Points, im osu-Format bereits Song-Zeit). --bpm/--offset
    ueberschreiben es.

Dafuer schreibt das Werkzeug fuer den Lauf eine temporaere Probe-Autoload
(beat_sync_probe.gd + [autoload] in override.cfg) in den Checkout; nach dem
Lauf wird beides wieder entfernt bzw. zurueckgesetzt. Spiel-Dateien bleiben
unveraendert. Die Probe liest nur (process_priority hoch = nach der Szene).

Aufruf (aus dem Checkout):
  python tools/beat_sync_check.py                    # rendern + messen
  python tools/beat_sync_check.py --seconds 8 --start 1.0
  python tools/beat_sync_check.py --frames-dir D --keep  # Frames behalten
  python tools/beat_sync_check.py --analyze D         # vorhandene Frames
  python tools/beat_sync_check.py --bpm 174 --offset 312
  python tools/beat_sync_check.py --report docs/perf/beat_sync.md

Abhaengigkeiten: Python 3 stdlib; PIL wenn vorhanden (sonst reiner PNG-Leser).
"""
from __future__ import annotations

import argparse
import datetime
import glob
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
import zlib

FPS = 60
MIX_RATE = 48000
MIX_BLOCK = 512
DEFAULT_GODOT = "C:/Users/Gexanx/Desktop/rhyg/Godot_v4.7-stable_win64.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CHECKOUT = os.path.dirname(HERE)

# Regionen als Anteile von Breite/Hoehe: (x0, y0, x1, y1).
REGIONS = [
    ("Hintergrund oben", (0.00, 0.04, 1.00, 0.30)),  # Himmel bis Horizont
    ("Strecke", (0.25, 0.42, 0.75, 0.72)),  # Fahrbahn zwischen Horizont und Pads
    ("Pads", (0.22, 0.74, 0.78, 0.87)),  # 4 Pad-Ringe, ohne Hit-Error-Balken
]

PROBE_NAME = "beat_sync_probe.gd"
PROBE_GD = r'''extends Node
# Temporaere Mess-Probe von tools/beat_sync_check.py (wird wieder geloescht).
var _f: FileAccess
var _k := 0
var _tp_done := false
var _end_ms := 1.0e12
var _players := ""

func _ready() -> void:
	process_priority = 1000000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_f = FileAccess.open(OS.get_environment("BEAT_SYNC_LOG"), FileAccess.WRITE)
	_end_ms = float(OS.get_environment("BEAT_SYNC_END_MS"))
	_f.store_line("# k scene state playing pos_ms smooth_ms vis_off_ms lat_ms lead_ms user_off_ms ticks_us phase lead_elapsed_ms")

func _process(_d: float) -> void:
	var sc := get_tree().current_scene
	var sname := "-"
	if sc != null:
		sname = sc.scene_file_path.get_file()
	var player: AudioStreamPlayer = SyncClock.get("_player")
	var playing := player != null and player.playing
	var pos := player.get_playback_position() * 1000.0 if playing else -1.0
	var sm = SyncClock.get("_smoother")
	var smooth: float = sm.value() if sm != null else 0.0
	var phase := -1.0
	if sc != null and sc.get("_clock") != null:
		phase = float(sc.get("_clock").beat_phase)
		if not _tp_done and sc.get("_beatmap") != null:
			_tp_done = true
			var bm = sc.get("_beatmap")
			_f.store_line("MAP\t%s - %s [%s]" % [bm.metadata.get("Artist", ""),
					bm.metadata.get("Title", ""), bm.version_name()])
			for tp in bm.timing_points:
				if tp.uninherited and tp.beat_length > 0.0:
					_f.store_line("TP\t%f\t%f\t%d" % [tp.time, tp.beat_length, tp.meter])
	_f.store_line("F\t%d\t%s\t%d\t%d\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%d\t%.4f\t%.3f" % [
			_k, sname, int(SyncClock.get("_state")), int(playing), pos, smooth,
			SyncClock.visual_offset_ms(), float(SyncClock.get("_latency_ms")),
			float(SyncClock.get("_lead_in_ms")), float(SyncClock.user_offset_ms),
			Time.get_ticks_usec(), phase, float(SyncClock.get("_lead_in_elapsed_ms"))])
	# Welche Player spielen (Diagnose fuer die Film-Tonspur), nur bei Aenderung.
	var names := PackedStringArray()
	for p in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		if p.playing and not p.stream_paused:
			names.append("%s@%s" % [p.name, p.get_parent().name])
	var cur := ",".join(names)
	if cur != _players:
		_players = cur
		_f.store_line("P\t%d\t%s" % [_k, cur])
	_k += 1
	if playing and pos > _end_ms:
		_f.flush()
		get_tree().quit()
'''


# ---------------------------------------------------------------- PNG lesen

def _png_luma_pure(path):
    """Minimaler PNG-Leser (8 bit RGB/RGBA/Grau, ohne Interlace)."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("kein PNG: " + path)
    pos = 8
    idat = []
    w = h = ctype = 0
    while pos < len(data):
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, depth, ctype, _c, _f, inter = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or inter != 0:
                raise ValueError("PNG-Format nicht unterstuetzt")
        elif typ == b"IDAT":
            idat.append(chunk)
        elif typ == b"IEND":
            break
    bpp = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(b"".join(idat))
    stride = w * bpp
    out = bytearray(w * h)
    prev = bytearray(stride)
    i = 0
    for y in range(h):
        ft = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        if ft == 1:
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x - bpp]) & 255
        elif ft == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif ft == 3:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif ft == 4:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        prev = line
        row = y * w
        if bpp >= 3:
            for x in range(w):
                o = x * bpp
                out[row + x] = (299 * line[o] + 587 * line[o + 1] + 114 * line[o + 2]) // 1000
        else:
            for x in range(w):
                out[row + x] = line[x * bpp]
    return w, h, out


def region_means(path, regions):
    """Mittlere Luma (0..255) je Region."""
    try:
        from PIL import Image  # noqa: WPS433
        im = Image.open(path).convert("L")
        w, h = im.size
        res = []
        for _name, (x0, y0, x1, y1) in regions:
            box = (int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h))
            crop = im.crop(box)
            hist = crop.histogram()
            n = sum(hist)
            res.append(sum(i * c for i, c in enumerate(hist)) / max(n, 1))
        return res
    except ImportError:
        w, h, px = _png_luma_pure(path)
        res = []
        for _name, (x0, y0, x1, y1) in regions:
            xa, xb, ya, yb = int(x0 * w), int(x1 * w), int(y0 * h), int(y1 * h)
            s = 0
            for y in range(ya, yb):
                s += sum(px[y * w + xa:y * w + xb])
            res.append(s / max((xb - xa) * (yb - ya), 1))
        return res


# ---------------------------------------------------------------- Lauf

def render(args, frames_dir):
    checkout = os.path.abspath(args.checkout)
    probe = os.path.join(checkout, PROBE_NAME)
    override = os.path.join(checkout, "override.cfg")
    backup = None
    if os.path.exists(override):
        with open(override, "rb") as fh:
            backup = fh.read()
    with open(os.path.join(checkout, "tools", "test_override.cfg"), "r", encoding="utf-8") as fh:
        base = fh.read()
    log_path = os.path.join(frames_dir, "probe.log")
    env = dict(os.environ)
    env["BEAT_SYNC_LOG"] = log_path
    env["BEAT_SYNC_END_MS"] = str((args.start + args.seconds) * 1000.0 + 500.0)
    cmd = [args.godot, "--path", checkout, "--write-movie",
           os.path.join(frames_dir, "f.png"), "--fixed-fps", str(FPS),
           "--audio-driver", "Dummy", "--position", "-1700,120",
           "--quit-after", str(args.max_frames),
           "res://scenes/song_select.tscn", "--mania", "--autoplay"]
    if getattr(args, "theme", None):
        cmd.append("--theme=" + args.theme)
    try:
        with open(probe, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(PROBE_GD)
        with open(override, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(base.rstrip() + "\n\n[autoload]\n\nBeatSyncProbe=\"*res://"
                     + PROBE_NAME + "\"\n")
        print("Render:", " ".join(cmd))
        with open(os.path.join(frames_dir, "godot.log"), "w", encoding="utf-8",
                  errors="replace") as lf:
            rc = subprocess.call(cmd, env=env, stdout=lf, stderr=subprocess.STDOUT,
                                 timeout=args.timeout)
        print("Godot exit", rc)
    finally:
        for p in (probe, probe + ".uid"):
            if os.path.exists(p):
                os.remove(p)
        if backup is None:
            if os.path.exists(override):
                os.remove(override)
        else:
            with open(override, "wb") as fh:
                fh.write(backup)
    return log_path


def read_probe(log_path):
    frames = {}
    tps = []
    mapname = "?"
    with open(log_path, "r", encoding="utf-8") as fh:
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if p[0] == "F":
                frames[int(p[1])] = {
                    "scene": p[2], "state": int(p[3]), "playing": p[4] == "1",
                    "pos": float(p[5]), "smooth": float(p[6]),
                    "vis_off": float(p[7]), "lat": float(p[8]),
                    "lead": float(p[9]), "user_off": float(p[10]),
                    "ticks": int(p[11]), "phase": float(p[12]),
                    "lead_el": float(p[13]) if len(p) > 13 else None,
                }
            elif p[0] == "TP":
                tps.append((float(p[1]), float(p[2]), int(p[3])))
            elif p[0] == "MAP":
                mapname = p[1]
    return frames, sorted(tps), mapname


def first_nonzero_sample(wav_path, from_frame):
    """Erstes nicht-stilles Sample ab Video-Frame from_frame -> (Index, Rate)."""
    try:
        with wave.open(wav_path, "rb") as w:
            rate, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
            idx = max(int(from_frame * rate / FPS), 0)
            w.setpos(idx)
            while True:
                buf = w.readframes(4800)
                if not buf:
                    return None, rate
                n = len(buf) // (ch * sw)
                for i in range(n):
                    o = i * ch * sw
                    seg = buf[o:o + ch * sw]
                    if any(seg):
                        return idx + i, rate
                idx += n
    except (wave.Error, OSError, EOFError):
        return None, 0


# ---------------------------------------------------------------- Analyse

def beat_grid(tps, t0, t1):
    """Beat-Zeiten (ms) im Bereich [t0, t1] aus roten Timing-Points."""
    beats = []
    for i, (tt, bl, _m) in enumerate(tps):
        end = tps[i + 1][0] if i + 1 < len(tps) else float("inf")
        n = math.ceil((max(t0, tt) - tt) / bl) if t0 > tt else 0
        while True:
            b = tt + n * bl
            if b >= end or b > t1:
                break
            if b >= t0:
                beats.append((b, bl))
            n += 1
    return beats


def beat_len_at(tps, t):
    cur = tps[0]
    for tp in tps:
        if tp[0] <= t:
            cur = tp
    return cur


def mean_std(xs):
    if not xs:
        return float("nan"), float("nan")
    m = sum(xs) / len(xs)
    v = sum((x - m) ** 2 for x in xs) / max(len(xs) - 1, 1)
    return m, math.sqrt(v)


def analyze_series(times, vals, tps):
    """times (ms Song-Zeit) / vals (Luma) -> Kennzahlen fuer eine Region."""
    t0, t1 = times[0], times[-1]
    beats = beat_grid(tps, t0, t1)
    phases, peaks, troughs = [], [], []
    for b, bl in beats:
        lo, hi = b - bl / 2.0, b + bl / 2.0
        if lo < t0 or hi > t1:
            continue
        idx = [i for i, t in enumerate(times) if lo <= t < hi]
        if len(idx) < 3:
            continue
        imax = max(idx, key=lambda i: vals[i])
        phases.append(times[imax] - b)
        peaks.append(vals[imax])
        troughs.append(min(vals[i] for i in idx))
    # Trendbereinigt (gleitendes Mittel ueber genau 1 Beat), nach Beat-Phase falten.
    det, ph = [], []
    for i, t in enumerate(times):
        _tt, bl, _m = beat_len_at(tps, t)
        win = [vals[j] for j, tj in enumerate(times) if abs(tj - t) <= bl / 2.0]
        det.append(vals[i] - sum(win) / len(win))
        tt = beat_len_at(tps, t)[0]
        ph.append(((t - tt) / bl) % 1.0)
    nb = 16
    bins = [[] for _ in range(nb)]
    for d, p in zip(det, ph):
        bins[min(int(p * nb), nb - 1)].append(d)
    prof = [sum(b) / len(b) if b else 0.0 for b in bins]
    resid = sum((d - prof[min(int(p * nb), nb - 1)]) ** 2 for d, p in zip(det, ph))
    tot = sum(d * d for d in det) - len(det) * (sum(det) / len(det)) ** 2
    r2 = 1.0 - resid / tot if tot > 1e-9 else 0.0
    kpk = max(range(nb), key=lambda i: prof[i])
    bl0 = beat_len_at(tps, t0)[1]
    prof_peak_ms = ((kpk + 0.5) / nb) * bl0
    if prof_peak_ms > bl0 / 2.0:
        prof_peak_ms -= bl0
    pm, ps = mean_std(phases)
    strength = (sum(peaks) / len(peaks)) / max(sum(troughs) / len(troughs), 1e-6) if peaks else float("nan")
    return {
        "n": len(phases), "phase_mean": pm, "phase_std": ps,
        "phase_med": sorted(phases)[len(phases) // 2] if phases else float("nan"),
        "strength": strength,
        "mean_luma": sum(vals) / len(vals),
        "r2": r2, "prof_peak_ms": prof_peak_ms,
        "prof_depth": max(prof) - min(prof), "profile": prof,
    }


def verdict(r):
    if r["n"] == 0:
        return "keine Daten"
    if r["r2"] < 0.15 or r["strength"] < 1.02:
        return "kein klarer Beat-Puls"
    if r["phase_std"] > 40:
        return "pulsiert, Phase streut"
    return "pulsiert im Takt"


def run(args):
    if args.analyze:
        frames_dir = os.path.abspath(args.analyze)
        log_path = os.path.join(frames_dir, "probe.log")
    else:
        frames_dir = os.path.abspath(args.frames_dir or tempfile.mkdtemp(prefix="beat_sync_"))
        os.makedirs(frames_dir, exist_ok=True)
        for f in glob.glob(os.path.join(frames_dir, "f*.png")):
            os.remove(f)
        log_path = render(args, frames_dir)
    probe, tps, mapname = read_probe(log_path)
    pngs = sorted(glob.glob(os.path.join(frames_dir, "f*.png")))
    if not probe or not pngs:
        sys.exit("FEHLER: keine Frames/Probe-Daten in " + frames_dir)
    if args.bpm:
        tps = [(args.offset or 0.0, 60000.0 / args.bpm, 4)]
    elif args.offset is not None and tps:
        tps = [(args.offset, bl, m) for (_t, bl, m) in tps[:1]] + tps[1:]
    if not tps:
        sys.exit("FEHLER: kein Timing-Point (Probe) - --bpm/--offset angeben")

    # Song-Start im Film: erster Frame k_play mit spielendem Audio. Movie-Maker
    # mischt pro Frame genau rate/60 Samples, der Audio-Block von Frame k_play
    # beginnt bei der Startposition from_ms (Lead-In-Ueberhang). Damit ist
    #   t_audio(k) = from_ms + (k - k_play) * 1000/60   (exakt, Frame-Raster).
    play_frames = sorted(k for k, f in probe.items() if f["playing"] and f["pos"] >= 0)
    if not play_frames:
        sys.exit("FEHLER: Song hat im Lauf nicht gespielt")
    k_play = play_frames[0]
    fp = probe[k_play]
    # Gegenprobe: get_playback_position() (dekoderblockweise quantisiert).
    ks = play_frames[1:]
    offs = [probe[k]["pos"] - (k * 1000.0 / FPS) for k in ks]
    pos_off, a_std = mean_std(offs)
    slope = float("nan")
    if len(ks) > 2:
        mk = sum(ks) / len(ks)
        mp = sum(probe[k]["pos"] for k in ks) / len(ks)
        slope = (sum((k - mk) * (probe[k]["pos"] - mp) for k in ks)
                 / sum((k - mk) ** 2 for k in ks))
    if fp.get("lead_el") is not None and fp["lead"] > 0:
        from_ms = max(fp["lead_el"] - fp["lead"], 0.0)
        # AudioServer mischt in Bloecken zu MIX_BLOCK Samples: der Song setzt an
        # der ersten Blockgrenze >= Beginn des Audio-Blocks von Frame k_play ein.
        blk = math.ceil(k_play * MIX_RATE / FPS / MIX_BLOCK) * MIX_BLOCK
        a_off = from_ms - blk * 1000.0 / MIX_RATE
        a_src = "Lead-In-Ueberhang %.1f ms, Einsatz bei Sample %d" % (from_ms, blk)
    else:
        a_off = pos_off
        a_src = "Fit get_playback_position"
    song0_frame = -a_off * FPS / 1000.0  # Frame mit Song-Zeit 0
    countdown = sum(1 for f in probe.values() if f["scene"] == "mania_3d.tscn"
                    and f["state"] == 1 and f["smooth"] == 0.0)
    lead_film = sum(1 for f in probe.values() if f["state"] == 1 and f["smooth"] != 0.0)

    wav = os.path.join(frames_dir, "f.wav")
    wav_note = "keine WAV"
    if os.path.exists(wav):
        smp, rate = first_nonzero_sample(wav, max(k_play - 2, 0))
        if smp is not None and rate:
            wav_note = ("erstes Song-Sample in der Film-WAV bei Frame %.3f "
                        "(Audio-Start laut Probe: Frame %d)" % (smp * FPS / rate, k_play))

    t_start, t_end = args.start * 1000.0, (args.start + args.seconds) * 1000.0
    sel = []
    for k in range(len(pngs)):
        if k not in probe:
            continue
        ta = k * 1000.0 / FPS + a_off
        if t_start <= ta <= t_end and probe[k]["scene"] == "mania_3d.tscn":
            sel.append(k)
    if len(sel) < FPS:
        sys.exit("FEHLER: zu wenige Gameplay-Frames im Fenster (%d)" % len(sel))

    t_audio = [k * 1000.0 / FPS + a_off for k in sel]
    t_game = [probe[k]["smooth"] + probe[k]["vis_off"] for k in sel]
    dev = [g - a for g, a in zip(t_game, t_audio)]
    dm, ds = mean_std(dev)
    vals = [[] for _ in REGIONS]
    for k in sel:
        for i, v in enumerate(region_means(pngs[k], REGIONS)):
            vals[i].append(v)

    f0 = probe[sel[0]]
    res = {
        "map": mapname, "tps": tps, "frames_dir": frames_dir,
        "k_play": k_play, "song0_frame": song0_frame, "a_std": a_std,
        "a_src": a_src, "pos_dev": pos_off - a_off, "slope": slope,
        "countdown": countdown,
        "lead_ms": f0["lead"], "lead_frames": lead_film,
        "lat": f0["lat"], "vis_off": f0["vis_off"], "user_off": f0["user_off"],
        "dev_mean": dm, "dev_std": ds, "dev_min": min(dev), "dev_max": max(dev),
        "wav_note": wav_note, "sel": (sel[0], sel[-1]), "n_frames": len(sel),
        "window": (t_start, t_end), "regions": [],
    }
    for (name, box), v in zip(REGIONS, vals):
        res["regions"].append((name, box, analyze_series(t_audio, v, tps),
                               analyze_series(t_game, v, tps)))
    return res


def fmt_table(res):
    bl = res["tps"][0][1]
    lines = []
    lines.append("Map: %s | %.2f BPM | Offset %.1f ms | %d rote Timing-Points"
                 % (res["map"], 60000.0 / bl, res["tps"][0][0], len(res["tps"])))
    lines.append("Fenster: Song-Zeit %.0f..%.0f ms, Frames %d..%d (%d Frames)"
                 % (res["window"][0], res["window"][1], res["sel"][0], res["sel"][1],
                    res["n_frames"]))
    lines.append("Song-Zeit 0 im Film bei Frame %.2f (Audio-Start Frame %d, Quelle: %s)"
                 % (res["song0_frame"], res["k_play"], res["a_src"]))
    lines.append("Gegenprobe Abspielposition: %+.1f ms (Streuung %.1f ms), %.3f ms/Frame (Soll %.3f)"
                 % (res["pos_dev"], res["a_std"], res["slope"], 1000.0 / FPS))
    lines.append("Start-Countdown: %d Frames (%.1f s) vor dem Lead-In"
                 % (res["countdown"], res["countdown"] / FPS))
    lines.append("Lead-In: %.0f ms Soll, %d Frames = %.0f ms im Film | Ausgabelatenz %.1f ms | "
                 "visual_offset %.1f ms | user_offset %.1f ms"
                 % (res["lead_ms"], res["lead_frames"], res["lead_frames"] * 1000.0 / FPS,
                    res["lat"], res["vis_off"], res["user_off"]))
    lines.append("Spieluhr (visual_time) minus Audio-Spur: Mittel %+.1f ms, Streuung %.1f ms, "
                 "min %+.1f, max %+.1f" % (res["dev_mean"], res["dev_std"],
                                            res["dev_min"], res["dev_max"]))
    lines.append("WAV-Check: " + res["wav_note"])
    lines.append("")
    hdr = ("| Region | Bezug | Beats | Phase Mittel | Streuung | Median | Profil-Spitze "
           "| Spitze/Tal | R^2 Beat | Luma | Urteil |")
    lines.append(hdr)
    lines.append("|" + "---|" * 11)
    for name, _box, ra, rg in res["regions"]:
        for ref, r in (("Audio", ra), ("Spieluhr", rg)):
            lines.append("| %s | %s | %d | %+.1f ms | %.1f ms | %+.1f ms | %+.0f ms | %.3f | %.2f | %.1f | %s |"
                         % (name, ref, r["n"], r["phase_mean"], r["phase_std"],
                            r["phase_med"], r["prof_peak_ms"], r["strength"], r["r2"],
                            r["mean_luma"], verdict(r)))
    return "\n".join(lines)


def write_report(res, table, path, cmdline):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    regs = "\n".join("- %s: x %.2f..%.2f, y %.2f..%.2f (Anteil der Bildgroesse)"
                     % (n, b[0], b[2], b[1], b[3]) for n, b in REGIONS)
    prof = []
    for name, _b, ra, _rg in res["regions"]:
        prof.append("- %s: " % name + " ".join("%+.2f" % p for p in ra["profile"]))
    txt = f"""# Beat-Sync-Messung

Stand: {datetime.date.today().isoformat()}, erzeugt von `tools/beat_sync_check.py`.

## Aufruf

```
{cmdline}
```

Rendert `song_select.tscn --mania --autoplay` per Godot Movie-Maker
(`--write-movie <dir>/f.png --fixed-fps 60 --audio-driver Dummy`, Testfenster
via `tools/test_override.cfg`, `--position -1700,120`), misst die mittlere
Luma je Region und Frame und setzt sie gegen das Beat-Raster der Map.
Optionen: `--seconds`, `--start` (Song-Zeit in s), `--frames-dir` + `--keep`,
`--analyze <dir>` (vorhandene Frames erneut messen), `--bpm/--offset`
(Raster ueberschreiben), `--report <md>`.

## Methode

- Zeit je Frame: Frame k liegt im Film bei k/60 s. Die Audio-Spur ist frame-genau
  gemischt; Song-Zeit(k) = k*1000/60 + c, c aus der Abspielposition des Songs
  (Probe-Autoload, nur lesend) gefittet. Lead-In-Stille, Ausgabelatenz und
  Offsets stecken damit nicht in der Referenz: Bezug **Audio** = was man im Film hoert.
- Bezug **Spieluhr**: dieselben Frames gegen `SyncClock.visual_time_ms()` (inkl.
  `visual_offset_ms`), die Zeit, mit der das Spiel seine Beat-FX rechnet.
- Beat-Raster: rote Timing-Points der Map (Offset = Zeitpunkt des Punkts).
- Phase: je Beat das Helligkeits-Maximum im Fenster [Beat - 1/2 Beat, Beat + 1/2 Beat);
  positiv = Spitze nach dem Beat. Frame-Raster 16.7 ms: ein Puls mit Angriff genau
  auf dem Beat hat sein Maximum im ersten Frame danach, ideal also 0..+16.7 ms
  (Mittel ca. +8 ms, Streuung ca. 5 ms).
- Spitze/Tal: Mittel der Beat-Maxima / Mittel der Beat-Minima.
- R^2 Beat: Anteil der Varianz der trendbereinigten Helligkeit (gleitendes Mittel
  ueber 1 Beat abgezogen), den das beat-gefaltete Profil (16 Phasen-Bins) erklaert.
  Nahe 0 = Helligkeit aendert sich nicht im Takt (z. B. nur durch Noten/Kamera).
- Profil-Spitze: Phase des hellsten Bins im gefalteten Profil.

Regionen:
{regs}

## Ergebnis

```
{table}
```

Gefaltetes Profil (Bezug Audio, Luma-Abweichung je 1/16 Beat ab Beat):
{chr(10).join(prof)}
"""
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(txt)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--checkout", default=DEFAULT_CHECKOUT)
    ap.add_argument("--godot", default=DEFAULT_GODOT)
    ap.add_argument("--seconds", type=float, default=8.0, help="Messdauer (s)")
    ap.add_argument("--start", type=float, default=0.5, help="Song-Zeit Messbeginn (s)")
    ap.add_argument("--frames-dir", help="Zielordner fuer Frames (sonst temp)")
    ap.add_argument("--keep", action="store_true", help="Frames nicht loeschen")
    ap.add_argument("--analyze", help="nur messen: Ordner mit f*.png + probe.log")
    ap.add_argument("--bpm", type=float)
    ap.add_argument("--offset", type=float, help="ms, Zeit des ersten Beats")
    ap.add_argument("--max-frames", type=int, default=3000)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--theme", help="Welt erzwingen (z. B. abyss; nicht neon)")
    ap.add_argument("--report", help="Markdown-Bericht schreiben (z. B. docs/perf/beat_sync.md)")
    args = ap.parse_args()
    res = run(args)
    table = fmt_table(res)
    print(table)
    if args.report:
        cmd = "python tools/beat_sync_check.py " + " ".join(
            a for a in sys.argv[1:] if not os.path.isabs(a))
        write_report(res, table, args.report, cmd.strip())
        print("Bericht:", args.report)
    if not args.analyze and not args.keep:
        shutil.rmtree(res["frames_dir"], ignore_errors=True)


if __name__ == "__main__":
    main()
