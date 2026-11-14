#!/usr/bin/env python3
"""marathon_sync_check.py - misst, wie genau ein Marathon-Uebergang auf dem Takt liegt.

Eingabe: Ordner eines Harness-Laufs (MarathonHarness, --marathon-harness=<ordner>):
  report.json      Plan inkl. Zeitachse, Uebergaenge, Mitschnitt-Startzeiten
  trans_<i>.wav    Mitschnitt des Master-Busses um die Mitte von Uebergang i

Messung je Uebergang i (A = Map i-1, B = Map i):
  Aus den Original-Songs (aus den .osz, per ffmpeg dekodiert) wird erwartet, was
  jedes Deck laut Zeitachse spielen soll: x_A(g) = A(song_at(A, g)), x_B(g) =
  B(song_at(B, g)) (Tempo-Angleich und Rampe eingerechnet). Kreuzkorrelation des
  Mitschnitts mit x_A (Bereich vor der Mitte) und x_B (nach der Mitte) liefert
  je Deck den Versatz zum Mitschnitt. Taktgrenzen-Abweichung = Versatz B - Versatz A:
  so weit liegt die Taktgrenze von B neben der von A (positiv = B spaeter).
  Der gemeinsame Versatz (Uhr gegen Mitschnitt-Start) faellt dabei heraus.
  Hochpass 150 Hz: vor der Mitte spielt B ohne Bass (Bass-Tausch).
  Uhr: im Harness spielt die Master-Spur (SyncClock, nach ihr laufen die Noten)
  leise Klicks (3 kHz) alle click_ms globaler Zeit. Versatz der Klicks im
  Mitschnitt = Uhr; Deck - Uhr = wie weit die Musik gegen die Notenuhr liegt.

Aufruf:  python tools/marathon_sync_check.py <harness-ordner> [--json]
Abhaengigkeiten: numpy, scipy, ffmpeg im PATH.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import wave
import zipfile

import numpy as np
from scipy import signal

BIG = 1.0e15


def song_at(seg, g):
    rho, g0, r0, r1 = seg["rho"], seg["g0"], seg["r0"], seg["r1"]
    s_in = seg["s_in"]
    g = np.asarray(g, dtype=np.float64)
    s_r0 = s_in + (r0 - g0) * rho
    dur = r1 - r0
    out = np.where(g <= r0, s_in + (g - g0) * rho, 0.0)
    if dur > 0:
        d = g - r0
        ramp = s_r0 + d * rho + 0.5 * (1.0 - rho) * d * d / dur
        out = np.where((g > r0) & (g <= r1), ramp, out)
    s_r1 = s_r0 + max(dur, 0.0) * (rho + 1.0) * 0.5
    out = np.where(g > max(r1, r0), s_r1 + (g - max(r1, r0)), out)
    return out


def unjson(v):
    if isinstance(v, (int, float)):
        f = float(v)
        if f >= BIG:
            return float("inf")
        if f <= -BIG:
            return float("-inf")
        return f
    if isinstance(v, list):
        return [unjson(x) for x in v]
    return v


def audio_name(z, version):
    for n in z.namelist():
        if not n.endswith(".osu"):
            continue
        t = z.read(n).decode("utf-8", "replace")
        m = re.search(r"^Version:(.*)$", t, re.M)
        if m and m.group(1).strip() == version:
            return re.search(r"^AudioFilename:\s*(.*)$", t, re.M).group(1).strip()
    for n in z.namelist():
        if n.endswith(".osu"):
            t = z.read(n).decode("utf-8", "replace")
            return re.search(r"^AudioFilename:\s*(.*)$", t, re.M).group(1).strip()
    raise RuntimeError("keine .osu")


def decode(osz, version, sr, tmp):
    z = zipfile.ZipFile(osz)
    name = audio_name(z, version)
    real = next(n for n in z.namelist() if n.lower() == name.lower())
    p = os.path.join(tmp, "a_" + str(abs(hash(osz))) + os.path.splitext(real)[1])
    with open(p, "wb") as f:
        f.write(z.read(real))
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", p, "-ac", "1", "-ar", str(sr),
                          "-f", "f32le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def read_wav(p):
    with wave.open(p, "rb") as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64)
    if ch > 1:
        data = data.reshape(-1, ch).mean(axis=1)
    return data / 32768.0, sr


def expected(pcm, seg, g, sr):
    s = song_at(seg, g)
    idx = s / 1000.0 * sr
    return np.interp(idx, np.arange(pcm.size), pcm, left=0.0, right=0.0)


def lag_ms(rec, ref, sr, max_ms=120.0):
    """Versatz (ms), um den ref im Mitschnitt spaeter liegt (Parabel-Feinwert)."""
    c = signal.correlate(rec, ref, mode="full", method="fft")
    lags = np.arange(-ref.size + 1, rec.size)
    lim = int(max_ms / 1000.0 * sr)
    sel = np.abs(lags) <= lim
    c, lags = c[sel], lags[sel]
    k = int(np.argmax(c))
    frac = 0.0
    if 0 < k < c.size - 1:
        y0, y1, y2 = c[k - 1], c[k], c[k + 1]
        den = y0 - 2 * y1 + y2
        if den != 0:
            frac = 0.5 * (y0 - y2) / den
    norm = np.sqrt(np.sum(rec * rec) * np.sum(ref * ref)) or 1.0
    return (lags[k] + frac) / sr * 1000.0, float(c[k] / norm)


def click_template(g, click_ms):
    u = np.mod(g, click_ms)
    n = 0.003 * 1000.0
    win = np.where(u < n, 0.5 - 0.5 * np.cos(2 * np.pi * u / n), 0.0)
    return 0.25 * win * np.sin(2 * np.pi * 3000.0 * u / 1000.0)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    d = sys.argv[1]
    rep = json.load(open(os.path.join(d, "report.json"), encoding="utf-8"))
    segs = [{k: unjson(v) for k, v in s.items()} for s in rep["plan"]["timeline"]]
    maps = rep["plan"]["maps"]
    sos = None
    out = []
    with tempfile.TemporaryDirectory() as tmp:
        cache = {}
        for t in rep["transitions"]:
            i = int(t["i"])
            rec_info = t.get("rec", {})
            wav = os.path.join(d, "trans_%d.wav" % i)
            if not os.path.exists(wav):
                out.append({"i": i, "error": "kein Mitschnitt"})
                continue
            rec, sr = read_wav(wav)
            if sos is None:
                sos = signal.butter(4, 150.0, "highpass", fs=sr, output="sos")
            for j in (i - 1, i):
                if j not in cache:
                    cache[j] = decode(maps[j]["osz"], maps[j].get("version", ""), sr, tmp)
            a, b = segs[i - 1], segs[i]
            mid = float(t["mid"])
            g0 = float(rec_info.get("start_g", mid - 8000.0))
            g = g0 + np.arange(rec.size) / sr * 1000.0
            x_a = expected(cache[i - 1], a, g, sr)
            x_b = expected(cache[i], b, g, sr)
            rf = signal.sosfilt(sos, rec)
            fa = signal.sosfilt(sos, x_a)
            fb = signal.sosfilt(sos, x_b)
            # A: vor der Mitte (B noch leise/ohne Bass), B: nach der Mitte.
            beat = float(t["beat_a"])
            ia = (g >= mid - 6000.0) & (g < mid - beat)
            ib = (g >= mid + beat) & (g < mid + 6000.0)
            la, ca = lag_ms(rf[ia], fa[ia], sr)
            lb, cb = lag_ms(rf[ib], fb[ib], sr)
            # Gegenprobe: A auch nach der Mitte (blendet aus), soweit noch hoerbar.
            fo = a.get("fade_out", [])
            ia2 = (g >= mid) & (g < (fo[1] if len(fo) == 2 else mid))
            la2, ca2 = lag_ms(rf[ia2], fa[ia2], sr) if ia2.sum() > sr // 2 else (float("nan"), 0.0)
            lm, cm = float("nan"), 0.0
            if rep.get("click_ms"):
                bp = signal.butter(4, [2200.0, 4000.0], "bandpass", fs=sr, output="sos")
                tm = click_template(g, float(rep["click_ms"]))
                lm, cm = lag_ms(signal.sosfilt(bp, rec), signal.sosfilt(bp, tm), sr,
                                max_ms=float(rep["click_ms"]) * 0.45)
            out.append({"i": i, "mid_ms": mid, "rho": t["rho"], "tempo_ok": t["tempo_ok"],
                        "lag_a_ms": la, "corr_a": ca, "lag_b_ms": lb, "corr_b": cb,
                        "lag_a_after_mid_ms": la2, "corr_a_after": ca2,
                        "bar_deviation_ms": lb - la, "gap_beats": t["gap_beats"],
                        "lag_clock_ms": lm, "corr_clock": cm,
                        "a_vs_clock_ms": la - lm, "b_vs_clock_ms": lb - lm,
                        "deck_err_p95_ms": t["deck_err_p95"], "deck_err_max_ms": t["deck_err_max"]})
    if "--json" in sys.argv:
        print(json.dumps(out, indent=2))
    else:
        for o in out:
            if "error" in o:
                print("Uebergang %d: %s" % (o["i"], o["error"]))
                continue
            print("Uebergang %d (rho %.4f, %s): Taktgrenzen-Abweichung %+.2f ms "
                  "(A %+.2f ms r=%.2f, B %+.2f ms r=%.2f), Luecke %.2f Schlaege, "
                  "Deck-Fehler p95 %.2f / max %.2f ms" % (
                      o["i"], o["rho"], "angeglichen" if o["tempo_ok"] else "harter Schnitt",
                      o["bar_deviation_ms"], o["lag_a_ms"], o["corr_a"], o["lag_b_ms"], o["corr_b"],
                      o["gap_beats"], o["deck_err_p95_ms"], o["deck_err_max_ms"]))
            if o["corr_clock"] > 0:
                print("    gegen die Notenuhr (Klicks r=%.2f): A %+.2f ms, B %+.2f ms "
                      "(positiv = Musik spaeter als die Noten)" % (
                          o["corr_clock"], o["a_vs_clock_ms"], o["b_vs_clock_ms"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
