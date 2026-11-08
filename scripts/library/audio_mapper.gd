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
const BPM_MAX := 175.0
const BPM_PRIOR_CENTER := 120.0
const BPM_PRIOR_SIGMA_OCT := 0.7
## Spitzen werden nur im ersten Teil des Songs fuer den groben Tempo-Scan genutzt.
const SCAN_MAX_PEAKS := 1000
const SCAN_MAX_MS := 100000.0
## Onsets ausserhalb dieses Anteils der Beat-Laenge zaehlen nicht fuer den Raster-Fit.
const FIT_WINDOW := 0.12
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
	var base := "%s - %s (TETHRA Auto)" % [meta.artist, meta.title]
	var osz_path := maps_dir.path_join(_safe_name(base) + ".osz")
	var audio_bytes := FileAccess.get_file_as_bytes(audio_path)
	if audio_bytes.is_empty():
		return _fail("Audiodatei nicht lesbar: " + audio_path)
	var zip := ZIPPacker.new()
	var err := zip.open(osz_path)
	if err != OK:
		return _fail("Konnte .osz nicht schreiben (Fehler %d): %s" % [err, osz_path])
	var osu_name := _safe_name("%s - %s (TETHRA Auto) [%s]" % [meta.artist, meta.title, difficulty]) + ".osu"
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
	var grid := estimate_grid(peaks)
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
		var a := flux[i - 1]
		var c := flux[i + 1]
		var den := a - 2.0 * v + c
		var p := 0.0
		if absf(den) > 1e-9:
			p = clampf(0.5 * (a - c) / den, -0.5, 0.5)
		peaks.append([(i + 0.5 + p) * HOP_MS, v / (lm + gmean * 0.1 + 1e-6)])
	return peaks


## Tempo und Beat-Raster aus den Onsets. {bpm, offset_ms}.
static func estimate_grid(peaks: Array) -> Dictionary:
	# Grober Scan: Resultierende der Onset-Phasen je Periode, mit Oktav-Prior.
	var scan: Array = []
	for p in peaks:
		if p[0] <= SCAN_MAX_MS:
			scan.append(p)
	scan.sort_custom(func(a, b): return a[1] > b[1])
	if scan.size() > SCAN_MAX_PEAKS:
		scan.resize(SCAN_MAX_PEAKS)
	var ts := PackedFloat64Array()
	var ws := PackedFloat64Array()
	for p in scan:
		ts.append(p[0])
		ws.append(sqrt(p[1]))
	var best_score := -1.0
	var best_bpm := 120.0
	var bpm := BPM_MIN
	while bpm <= BPM_MAX:
		var w := _resultant(ts, ws, 60000.0 / bpm)
		var oct := log(bpm / BPM_PRIOR_CENTER) / log(2.0) / BPM_PRIOR_SIGMA_OCT
		var score: float = w[0] * exp(-0.5 * oct * oct)
		if score > best_score:
			best_score = score
			best_bpm = bpm
		bpm += 0.05
	# Fein um den Treffer, dann Regression auf allen Onsets.
	var fine_bpm := best_bpm
	var fine_best := -1.0
	var fb := best_bpm - 0.1
	while fb <= best_bpm + 0.1:
		var r := _resultant(ts, ws, 60000.0 / fb)
		if r[0] > fine_best:
			fine_best = r[0]
			fine_bpm = fb
		fb += 0.005
	var T := 60000.0 / fine_bpm
	var off: float = _resultant(ts, ws, T)[1]
	for _it in 4:
		var fit := _fit(peaks, T, off)
		if not fit.ok:
			break
		T = fit.T
		off = fit.off
	off = fposmod(off, T)
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
		var on_beat := s % 4 == 0
		var mult := 1.0
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
		out.append([off + s * slot_ms, s, taken[s][3], posmod(s / 4 - bar_phase, 4) == 0 and s % 4 == 0])
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
	lines.append("Creator:TETHRA Auto")
	lines.append("Version:" + difficulty)
	lines.append("Source:")
	lines.append("Tags:tethra auto orbit")
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
	lines.append("%.2f,%.6f,4,2,0,60,1,0" % [an.offset_ms, T])
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
