class_name AudioMapper
extends RefCounted

## Eigene Musikdatei -> spielbare ORBIT-Map (osu!standard-.osz, nur Orbit).
## Ablauf: ffmpeg dekodiert zu PCM mono 22050 Hz, ein 3-Band-Spektralfluss
## liefert Onsets, aus ihnen werden Tempo und Beat-Raster geschaetzt, die Onsets
## werden auf 1/2 bzw. 1/4 Beat gerastet und je Schwierigkeit ausgeduennt. Die
## Positionen laufen in Kreisen um die Mitte, damit OrbitConverter.convert_std
## (POLAR) fluessige Winkel liefert; die Drehrichtung wechselt am Taktanfang.
## generate() blockiert (Aufrufer startet einen Thread).
## Bericht und Messwerte: docs/modes/audio_map.md

const RATE := 22050
## Frame-Hop in Samples (110 = 4,99 ms).
const HOP := 110
const HOP_MS := HOP * 1000.0 / RATE
const BPM_MIN := 75.0
const BPM_MAX := 190.0
const BPM_PRIOR_CENTER := 130.0
const BPM_PRIOR_SIGMA_OCT := 0.8
## Spitzen werden nur im ersten Teil des Songs fuer den groben Tempo-Scan genutzt.
const SCAN_MAX_PEAKS := 1000
const SCAN_MAX_MS := 100000.0
## Onsets ausserhalb dieses Anteils der Beat-Laenge zaehlen nicht fuer den Raster-Fit.
## Anstieg zurueckverfolgen: max. Frames, Schwelle relativ zum Maximum.
const RISE_BACK := 8
const RISE_FRAC := 0.2
const FAST_BEAT_RATIO := 0.6
const FIT_WINDOW := 0.12
## Gemessen an echten Maps: deren Noten liegen ~23 ms vor dem erkannten Anschlag.
const OSU_LEAD_MS := 23.0
const MIN_NOTE_MS := 700.0

## Schwierigkeiten: min. Abstand, feinste Teilung (Slots je Beat), Anteil der
## behaltenen Onsets, Radius-Faktor der Bewegung.
const DIFFS := {
	"Leicht": {"gap": 420.0, "sub": 2, "keep": 0.45, "ar": 7.0, "od": 4.0},
	"Normal": {"gap": 240.0, "sub": 2, "keep": 0.70, "ar": 8.0, "od": 6.0},
	"Schwer": {"gap": 140.0, "sub": 4, "keep": 0.90, "ar": 9.0, "od": 8.0},
}
const RADIUS_OUT := 180.0
const RADIUS_IN := 90.0


## Hauptweg. Rueckgabe {ok, osz_path, error, bpm, offset_ms, note_count}.
static func generate(audio_path: String, maps_dir: String, difficulty: String = "Normal") -> Dictionary:
	if not DIFFS.has(difficulty):
		return _fail("Unbekannte Schwierigkeit: " + difficulty)
	if not FileAccess.file_exists(audio_path):
		return _fail("Audiodatei fehlt: " + audio_path)
	var an := analyze(audio_path)
	if not an.ok:
		return _fail(an.error)
	var meta := read_meta(audio_path)
	var ext := audio_path.get_extension().to_lower()
	var audio_name := "audio." + ext
	var osu := build_osu(an, meta, difficulty, audio_name)
	if osu.note_count < 8:
		return _fail("Zu wenige Noten erkannt (%d). Ist die Datei Musik?" % osu.note_count)
	DirAccess.make_dir_recursive_absolute(maps_dir)
	var base := "%s - %s (OMEN Auto)" % [meta.artist, meta.title]
	var osz_path := maps_dir.path_join(_safe_name(base) + ".osz")
	var audio_bytes := FileAccess.get_file_as_bytes(audio_path)
	if audio_bytes.is_empty():
		return _fail("Audiodatei nicht lesbar: " + audio_path)
	var zip := ZIPPacker.new()
	var err := zip.open(osz_path)
	if err != OK:
		return _fail("Konnte .osz nicht schreiben (Fehler %d): %s" % [err, osz_path])
	var osu_name := _safe_name("%s - %s (OMEN Auto) [%s]" % [meta.artist, meta.title, difficulty]) + ".osu"
	zip.start_file(osu_name)
	zip.write_file(osu.text.to_utf8_buffer())
	zip.close_file()
	zip.start_file(audio_name)
	zip.write_file(audio_bytes)
	zip.close_file()
	zip.close()
	return {"ok": true, "osz_path": osz_path, "error": "", "bpm": an.bpm,
			"offset_ms": an.offset_ms, "note_count": osu.note_count}


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "osz_path": "", "error": msg, "bpm": 0.0, "offset_ms": 0.0, "note_count": 0}


static func _safe_name(s: String) -> String:
	var out := s
	for ch in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		out = out.replace(ch, "_")
	return out.strip_edges()


# ---------------------------------------------------------------------------
# Analyse
# ---------------------------------------------------------------------------

## Audio analysieren. {ok, error, bpm, offset_ms, onsets: Array[[t_ms, strength]],
## duration_ms}. offset_ms liegt in [0, Beat-Laenge).
static func analyze(audio_path: String) -> Dictionary:
	var samples := decode(audio_path)
	if samples.size() < RATE * 4:
		return {"ok": false, "error": "Audio nicht dekodierbar oder kuerzer als 4 s (ffmpeg gefunden?)"}
	return analyze_samples(samples)


static func analyze_samples(samples: PackedFloat32Array) -> Dictionary:
	var flux := onset_flux(samples)
	var peaks := pick_peaks(flux)
	var dur := samples.size() * 1000.0 / RATE
	if peaks.size() < 8:
		return {"ok": false, "error": "Keine Onsets gefunden (Stille?)"}
	var grid := estimate_grid(peaks, flux)
	return {"ok": true, "error": "", "bpm": grid.bpm, "offset_ms": grid.offset_ms,
			"onsets": peaks, "duration_ms": dur}


## ffmpeg: Datei -> mono 22050 Hz Float-Samples. Leer bei Fehler.
static func decode(audio_path: String) -> PackedFloat32Array:
	var ff := ClipExporter.find_ffmpeg()
	if ff == "":
		return PackedFloat32Array()
	var tmp := ProjectSettings.globalize_path("user://audio_mapper_%d.raw" % Time.get_ticks_usec())
	var out := []
	var code := OS.execute(ff, ["-v", "error", "-y", "-i", audio_path, "-vn", "-ac", "1",
			"-ar", str(RATE), "-f", "f32le", tmp], out, true)
	var res := PackedFloat32Array()
	if code == 0 and FileAccess.file_exists(tmp):
		res = FileAccess.get_file_as_bytes(tmp).to_float32_array()
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	return res


## Kuenstler/Titel aus den Tags (ffmpeg), sonst aus dem Dateinamen.
static func read_meta(audio_path: String) -> Dictionary:
	var artist := ""
	var title := ""
	var ff := ClipExporter.find_ffmpeg()
	if ff != "":
		var out := []
		if OS.execute(ff, ["-v", "error", "-i", audio_path, "-f", "ffmetadata", "-"], out, false) == 0 and out.size() > 0:
			for line in String(out[0]).split("\n"):
				var kv := line.strip_edges().split("=", true, 1)
				if kv.size() != 2:
					continue
				var k := kv[0].to_lower()
				if k == "artist" and artist == "":
					artist = kv[1].strip_edges()
				elif k == "title" and title == "":
					title = kv[1].strip_edges()
	var stem := audio_path.get_file().get_basename()
	if title == "":
		var parts := stem.split(" - ", true, 1)
		if parts.size() == 2:
			if artist == "":
				artist = parts[0].strip_edges()
			title = parts[1].strip_edges()
		else:
			title = stem
	if artist == "":
		artist = "Unknown"
	return {"artist": artist, "title": title}


## Onset-Staerke je Hop-Frame: 3-Band-Energie (Log), positiver Fluss.
static func onset_flux(samples: PackedFloat32Array) -> PackedFloat32Array:
	var n := samples.size() / HOP
	var flux := PackedFloat32Array()
	flux.resize(n)
	var a1 := 1.0 - exp(-TAU * 250.0 / RATE)
	var a2 := 1.0 - exp(-TAU * 2500.0 / RATE)
	var l1 := 0.0
	var l2 := 0.0
	var pv0 := 0.0
	var pv1 := 0.0
	var pv2 := 0.0
	var wl := 0.6
	var wm := 1.0
	var wh := 1.4
	for f in n:
		var e0 := 0.0
		var e1 := 0.0
		var e2 := 0.0
		var base := f * HOP
		for k in HOP:
			var x := samples[base + k]
			l1 += a1 * (x - l1)
			l2 += a2 * (x - l2)
			var m := l2 - l1
			var h := x - l2
			e0 += l1 * l1
			e1 += m * m
			e2 += h * h
		var v0 := log(1.0 + 60.0 * sqrt(e0 / HOP))
		var v1 := log(1.0 + 60.0 * sqrt(e1 / HOP))
		var v2 := log(1.0 + 60.0 * sqrt(e2 / HOP))
		flux[f] = wl * maxf(0.0, v0 - pv0) + wm * maxf(0.0, v1 - pv1) + wh * maxf(0.0, v2 - pv2)
		pv0 = v0
		pv1 = v1
		pv2 = v2
	return flux


## Lokale Maxima ueber adaptiver Schwelle. Array aus [t_ms, Staerke] (Staerke
## relativ zum lokalen Mittel), nach Zeit sortiert.
static func pick_peaks(flux: PackedFloat32Array) -> Array:
	var n := flux.size()
	var pre := PackedFloat64Array()
	pre.resize(n + 1)
	for i in n:
		pre[i + 1] = pre[i] + flux[i]
	var half := 100
	var dom := 6
	var peaks: Array = []
	var gmean := pre[n] / maxf(n, 1)
	for i in range(1, n - 1):
		var v := flux[i]
		if v <= flux[i - 1] or v < flux[i + 1]:
			continue
		var lo := maxi(0, i - half)
		var hi := mini(n, i + half + 1)
		var lm := (pre[hi] - pre[lo]) / (hi - lo)
		var thr := lm * 1.6 + gmean * 0.15
		if v < thr:
			continue
		var best := true
		for j in range(maxi(0, i - dom), mini(n, i + dom + 1)):
			if flux[j] > v:
				best = false
				break
		if not best:
			continue
		# Zeit = Beginn des Anstiegs (Mapper setzen auf den Anschlag, nicht aufs Maximum).
		var j := i
		while j > 0 and i - j < RISE_BACK and flux[j - 1] < flux[j] and flux[j - 1] > RISE_FRAC * v:
			j -= 1
		var p := 0.0
		if j == i:
			var a := flux[i - 1]
			var c := flux[i + 1]
			var den := a - 2.0 * v + c
			if absf(den) > 1e-9:
				p = clampf(0.5 * (a - c) / den, -0.5, 0.5)
		peaks.append([(j + 0.5 + p) * HOP_MS, v / (lm + gmean * 0.1 + 1e-6)])
	return peaks


static func _lag_score(acf: PackedFloat32Array, lag: int, max_lag: int) -> float:
	var bpm := 60000.0 / (lag * HOP_MS)
	var oct := log(bpm / BPM_PRIOR_CENTER) / log(2.0) / BPM_PRIOR_SIGMA_OCT
	var sc := acf[lag]
	if 2 * lag <= max_lag:
		sc += 0.5 * acf[2 * lag]
	# Unterteilungen (Achtel, Sechzehntel) stuetzen den Schlag.
	sc += 0.5 * maxf(acf[lag / 2], maxf(acf[(lag + 1) / 2], acf[lag / 2 - 1]))
	sc += 0.25 * maxf(acf[lag / 4], maxf(acf[(lag + 2) / 4], acf[lag / 4 - 1]))
	return sc * exp(-0.5 * oct * oct)


## Grobes Tempo (BPM) aus der Autokorrelation des Onset-Flusses, mit
## Oberschwingungen (2L, 4L) und Oktav-Prior.
static func coarse_bpm(flux: PackedFloat32Array) -> float:
	var n := mini(flux.size(), int(SCAN_MAX_MS / HOP_MS))
	var env := PackedFloat32Array()
	env.resize(n)
	var win := 100
	# Lokales Mittel abziehen (gleitend, einfach ueber Bloecke).
	var block := 2 * win
	var i0 := 0
	while i0 < n:
		var i1 := mini(n, i0 + block)
		var m := 0.0
		for i in range(i0, i1):
			m += flux[i]
		m /= (i1 - i0)
		for i in range(i0, i1):
			env[i] = maxf(0.0, flux[i] - m)
		i0 = i1
	var lag_lo := int(60000.0 / BPM_MAX / HOP_MS) - 1
	var lag_hi := int(60000.0 / BPM_MIN / HOP_MS) + 2
	var acf := PackedFloat32Array()
	acf.resize(lag_hi * 4 + 1)
	var max_lag := mini(lag_hi * 2 + 1, n / 2)
	for lag in range(maxi(lag_lo / 4 - 1, 3), max_lag + 1):
		var sum := 0.0
		for i in range(n - lag):
			sum += env[i] * env[i + lag]
		acf[lag] = sum / (n - lag)
	var best := -1.0
	var best_lag := lag_lo
	for lag in range(lag_lo, lag_hi + 1):
		var sc := _lag_score(acf, lag, max_lag)
		if sc > best:
			best = sc
			best_lag = lag
	# Punktierte Muster (3 gegen 4): die 1,5-fache Periode ist oft nur ein
	# Begleitrhythmus. Ist der schnellere Schlag (2/3 der Periode) fast so
	# stark, gilt er.
	var fast := int(roundf(best_lag * 2.0 / 3.0))
	if fast >= lag_lo and fast < best_lag and _lag_score(acf, fast, max_lag) > FAST_BEAT_RATIO * best:
		best_lag = fast
	# Parabel-Verfeinerung.
	var ya := acf[best_lag - 1]
	var yb := acf[best_lag]
	var yc := acf[best_lag + 1]
	var den := ya - 2.0 * yb + yc
	var frac := 0.0
	if absf(den) > 1e-12:
		frac = clampf(0.5 * (ya - yc) / den, -0.5, 0.5)
	return 60000.0 / ((best_lag + frac) * HOP_MS)


## Tempo und Beat-Raster aus den Onsets. {bpm, offset_ms}.
static func estimate_grid(peaks: Array, flux: PackedFloat32Array) -> Dictionary:
	var coarse := coarse_bpm(flux)
	var ts := PackedFloat64Array()
	var ws := PackedFloat64Array()
	var scan: Array = []
	for p in peaks:
		if p[0] <= SCAN_MAX_MS:
			scan.append(p)
	scan.sort_custom(func(a, b): return a[1] > b[1])
	if scan.size() > SCAN_MAX_PEAKS:
		scan.resize(SCAN_MAX_PEAKS)
	for p in scan:
		ts.append(p[0])
		ws.append(sqrt(p[1]))
	# Fein um den groben Wert (+-3 %): Summe von Grundton und Oberschwingungen
	# (Schlag, Achtel, Sechzehntel stuetzen dasselbe Tempo; bei reinen
	# Achtelketten ist der Grundton allein schwach).
	var fine_bpm := coarse
	var fine_best := -1.0
	var fb := coarse * 0.97
	while fb <= coarse * 1.03:
		var sc := 0.0
		for h in [1, 2, 4]:
			sc += _resultant(ts, ws, 60000.0 / fb / h)[0]
		if sc > fine_best:
			fine_best = sc
			fine_bpm = fb
		fb += 0.02
	var T0 := 60000.0 / fine_bpm
	# Feinste tragende Teilung h: Raster der Periode T0/h fuer die Regression.
	var h_use := 1
	var h_best: float = _resultant(ts, ws, T0)[0]
	for h in [2, 4]:
		var m: float = _resultant(ts, ws, T0 / h)[0]
		if m > h_best * 1.1:
			h_best = m
			h_use = h
	var pd := T0 / h_use
	var off: float = _resultant(ts, ws, pd)[1]
	for _it in 4:
		var fit := _fit(peaks, pd, off)
		if not fit.ok:
			break
		pd = fit.T
		off = fit.off
	var T := pd * h_use
	# Schlagposition unter den h Kandidaten: der, bei dem der Grundton am staerksten ist.
	var fund := _resultant(ts, ws, T)
	var best_k := 0
	var best_c := -2.0
	for k in h_use:
		var c := cos(TAU * (fund[1] - (off + k * pd)) / T)
		if c > best_c:
			best_c = c
			best_k = k
	off = fposmod(off + best_k * pd, T)
	return {"bpm": snappedf(60000.0 / T, 0.001), "offset_ms": snappedf(off, 0.01)}


## [Betrag, Offset in ms] der gewichteten Phasensumme bei Periode T.
static func _resultant(ts: PackedFloat64Array, ws: PackedFloat64Array, T: float) -> Array:
	var sc := 0.0
	var ss := 0.0
	var k := TAU / T
	for i in ts.size():
		var th := ts[i] * k
		sc += ws[i] * cos(th)
		ss += ws[i] * sin(th)
	var phase := atan2(ss, sc)
	return [sqrt(sc * sc + ss * ss), fposmod(phase / TAU * T, T)]


## Gewichtete lineare Regression t = off + k * T ueber alle Onsets nahe am Raster.
static func _fit(peaks: Array, T: float, off: float) -> Dictionary:
	var s := 0.0
	var sk := 0.0
	var skk := 0.0
	var st := 0.0
	var skt := 0.0
	var cnt := 0
	var k0 := roundf((peaks[0][0] - off) / T)
	for p in peaks:
		var k := roundf((p[0] - off) / T)
		var r: float = p[0] - off - k * T
		if absf(r) > FIT_WINDOW * T:
			continue
		var w: float = sqrt(p[1])
		var kk := k - k0
		s += w
		sk += w * kk
		skk += w * kk * kk
		st += w * p[0]
		skt += w * kk * p[0]
		cnt += 1
	var det := s * skk - sk * sk
	if cnt < 6 or absf(det) < 1e-6:
		return {"ok": false}
	var b := (s * skt - sk * st) / det
	var a := (st - b * sk) / s
	return {"ok": true, "T": b, "off": a}


# ---------------------------------------------------------------------------
# Map bauen
# ---------------------------------------------------------------------------

## Noten-Slots {slot -> Staerke} aus den Onsets, je Schwierigkeit ausgeduennt.
## Liefert Array von [t_ms, slot, on_beat] nach Zeit sortiert.
static func pick_notes(an: Dictionary, difficulty: String) -> Array:
	var cfg: Dictionary = DIFFS[difficulty]
	var T := 60000.0 / float(an.bpm)
	var off: float = an.offset_ms
	var sub: int = cfg.sub
	var slot_ms := T / 4.0
	var step := 4 / sub
	# Onsets auf Slots rasten, je Slot die staerkste behalten.
	var cand := {}
	for p in an.onsets:
		var s := int(roundf((p[0] - off) / (slot_ms * step))) * step
		var t := off + s * slot_ms
		if t < MIN_NOTE_MS or t > an.duration_ms - 300.0:
			continue
		if not cand.has(s) or cand[s] < p[1]:
			cand[s] = p[1]
	if cand.is_empty():
		return []
	# Takt-Phase: welcher Beat (mod 4) traegt die meiste Staerke.
	var phase_sum := [0.0, 0.0, 0.0, 0.0]
	for s in cand:
		if s % 4 == 0:
			phase_sum[posmod(s / 4, 4)] += cand[s]
	var bar_phase := 0
	for i in 4:
		if phase_sum[i] > phase_sum[bar_phase]:
			bar_phase = i
	var items: Array = []
	for s in cand:
		var on_beat: bool = s % 4 == 0
		var mult: float = 1.0
		if on_beat:
			mult = 1.5
			if posmod(s / 4 - bar_phase, 4) == 0:
				mult = 1.9
		elif s % 2 == 0:
			mult = 1.15
		items.append([s, cand[s], cand[s] * mult, on_beat])
	# Staerke-Schwelle (Quantil) -- Taktschlaege duerfen darunter liegen.
	var strengths: Array = []
	for it in items:
		strengths.append(it[1])
	strengths.sort()
	var q := clampi(int(floor((1.0 - float(cfg.keep)) * strengths.size())), 0, strengths.size() - 1)
	var thr: float = strengths[q]
	var pool: Array = []
	for it in items:
		if it[1] >= thr or (it[3] and it[1] >= thr * 0.5):
			pool.append(it)
	pool.sort_custom(func(a, b): return a[2] > b[2])
	var taken := {}
	var reach := int(ceil(float(cfg.gap) / slot_ms))
	for it in pool:
		var s: int = it[0]
		var ok := true
		for d in range(1, reach + 1):
			if d * slot_ms >= float(cfg.gap):
				break
			if taken.has(s - d) or taken.has(s + d):
				ok = false
				break
		if ok:
			taken[s] = it
	var slots: Array = taken.keys()
	slots.sort()
	var out: Array = []
	for s in slots:
		out.append([off + s * slot_ms - OSU_LEAD_MS, s, taken[s][3], posmod(s / 4 - bar_phase, 4) == 0 and s % 4 == 0])
	return out


## .osu-Text fuer die Analyse. {text, note_count}.
static func build_osu(an: Dictionary, meta: Dictionary, difficulty: String, audio_name: String) -> Dictionary:
	var cfg: Dictionary = DIFFS[difficulty]
	var notes := pick_notes(an, difficulty)
	var T := 60000.0 / float(an.bpm)
	var lines: Array[String] = []
	lines.append("osu file format v14")
	lines.append("")
	lines.append("[General]")
	lines.append("AudioFilename: " + audio_name)
	lines.append("AudioLeadIn: 0")
	lines.append("PreviewTime: %d" % int(an.duration_ms * 0.3))
	lines.append("Countdown: 0")
	lines.append("Mode: 0")
	lines.append("")
	lines.append("[Metadata]")
	lines.append("Title:" + meta.title)
	lines.append("TitleUnicode:" + meta.title)
	lines.append("Artist:" + meta.artist)
	lines.append("ArtistUnicode:" + meta.artist)
	lines.append("Creator:OMEN Auto")
	lines.append("Version:" + difficulty)
	lines.append("Source:")
	lines.append("Tags:omen auto orbit")
	lines.append("")
	lines.append("[Difficulty]")
	lines.append("HPDrainRate:5")
	lines.append("CircleSize:4")
	lines.append("OverallDifficulty:%s" % str(cfg.od))
	lines.append("ApproachRate:%s" % str(cfg.ar))
	lines.append("SliderMultiplier:1.4")
	lines.append("SliderTickRate:1")
	lines.append("")
	lines.append("[Events]")
	lines.append("")
	lines.append("[TimingPoints]")
	lines.append("%.2f,%.6f,4,2,0,60,1,0" % [an.offset_ms - OSU_LEAD_MS, T])
	lines.append("")
	lines.append("[HitObjects]")
	var angle := 0.0
	var dir := 1.0
	var last_t := -INF
	var last_bar := -1
	var bars_seen := 0
	for n in notes:
		var t: float = n[0]
		var s: int = n[1]
		var gap := minf(t - last_t, 1000.0)
		var bar := int(floor(s / 16.0))
		if n[3] and bar != last_bar:
			bars_seen += 1
			if bars_seen % 2 == 0:
				dir = -dir
		if n[3]:
			last_bar = bar
		if last_t > -INF:
			angle += dir * clampf(gap * 0.09, 10.0, 34.0)
		last_t = t
		var r := RADIUS_OUT if n[2] else RADIUS_IN
		var rad := deg_to_rad(angle)
		var x := int(roundf(256.0 + r * sin(rad)))
		var y := int(roundf(192.0 - r * cos(rad)))
		lines.append("%d,%d,%d,1,0,0:0:0:0:" % [x, y, int(roundf(t))])
	return {"text": "\n".join(lines) + "\n", "note_count": notes.size()}
