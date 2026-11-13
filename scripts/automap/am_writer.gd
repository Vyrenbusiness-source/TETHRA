class_name AmWriter
extends RefCounted

## Paket fuer den 4K-Auto-Mapper (docs/automap/spec.md): Gitter + Features +
## Charts -> .osz in maps_dir. Audio unveraendert als audio.<ext>, je Chart eine
## .osu (Mode 3, 4K), Cover als bg.jpg/bg.png, optional Orbit-Diffs (Mode 0).
## Reines GDScript, kein Szenenzugriff, thread-faehig.
##
## meta (Felder ueber die Spec hinaus sind optional):
##   artist, title        Pflicht
##   with_orbit: bool     Orbit-Diffs (osu!standard) auf demselben Gitter mitschreiben
##   ffmpeg: String       Pfad zu ffmpeg; fehlt das Feld, wird ClipExporter.find_ffmpeg()
##                        gefragt, "" = kein eingebettetes Cover, keine Umwandlung
##   waveform: PackedFloat32Array  Huellkurve 0..1 (AmWriter.waveform) fuer das erzeugte
##                        Vorschaubild, wenn kein Bild da ist; fehlt sie, dienen
##                        features.energy bzw. features.events als Quelle
##
## Audio: mp3/ogg unveraendert. Andere Formate (wav, flac ...) spielt das Spiel
## aus der .osz nicht ab (OszImporter kennt nur mp3/ogg), deshalb werden sie per
## ffmpeg zu audio.ogg (Vorbis) gewandelt; ohne ffmpeg schlaegt das Schreiben fehl.

const CREATOR := "OMEN Auto"
const SUFFIX := "(OMEN Auto)"
const IMAGE_EXTS := ["jpg", "jpeg", "png", "webp"]
## Formate, die OszImporter direkt abspielt.
const NATIVE_AUDIO := ["mp3", "ogg"]
const ERR_CONVERT := "cannot convert audio to .ogg"
## Erzeugtes Vorschaubild (ohne Cover): Groesse, Anzahl Balken.
const PREVIEW_W := 1280
const PREVIEW_H := 720
const PREVIEW_BARS := 150
## OD/HP je Profil. Unbekannte Profile bekommen FALLBACK_DIFF.
const PROFILE_DIFF := {
	"Easy": {"od": 5.0, "hp": 5.0},
	"Normal": {"od": 6.5, "hp": 6.0},
	"Hard": {"od": 7.5, "hp": 7.0},
	"Insane": {"od": 8.0, "hp": 7.5},
	"Expert": {"od": 8.5, "hp": 8.0},
}
const FALLBACK_DIFF := {"od": 7.0, "hp": 7.0}
const ORBIT_PREFIX := "Orbit "


static func write_osz(audio_path: String, maps_dir: String, meta: Dictionary, grid: Dictionary,
		features: Dictionary, charts: Array) -> Dictionary:
	var segs: Array = grid.get("segments", [])
	if segs.is_empty():
		return _fail("grid has no segments")
	if charts.is_empty():
		return _fail("no charts to write")
	var audio_bytes := FileAccess.get_file_as_bytes(audio_path)
	if audio_bytes.is_empty():
		return _fail("audio file not readable: " + audio_path)
	var artist := str(meta.get("artist", "Unknown"))
	var title := str(meta.get("title", audio_path.get_file().get_basename()))
	var ext := audio_path.get_extension().to_lower()
	var audio_name := "audio." + ext
	var ff := str(meta["ffmpeg"]) if meta.has("ffmpeg") else ClipExporter.find_ffmpeg()
	if not ext in NATIVE_AUDIO:
		audio_bytes = to_ogg(audio_path, ff)
		if audio_bytes.is_empty():
			return _fail(ERR_CONVERT + ": " + audio_path.get_file())
		audio_name = "audio.ogg"
	var cover := find_cover(audio_path, ff)
	if str(cover.get("name", "")) == "":
		cover = preview_image(meta.get("waveform", PackedFloat32Array()), features)
	var bg_name := str(cover.get("name", ""))

	var files: Array = []   # [name, bytes]
	for c in charts:
		var profile := str(c.get("profile", "Normal"))
		var text := mania_osu(artist, title, profile, grid, features, c.get("notes", []), audio_name, bg_name)
		files.append([osu_name(artist, title, profile), text.to_utf8_buffer()])
	if bool(meta.get("with_orbit", false)):
		for d in AudioMapper.DIFFS:
			var o := orbit_osu(artist, title, str(d), grid, features, audio_name, bg_name)
			if int(o.note_count) >= 8:
				files.append([osu_name(artist, title, ORBIT_PREFIX + str(d)), String(o.text).to_utf8_buffer()])
	files.append([audio_name, audio_bytes])
	if bg_name != "":
		files.append([bg_name, cover.bytes])

	DirAccess.make_dir_recursive_absolute(maps_dir)
	var osz_path := maps_dir.path_join(osz_name(artist, title))
	var tmp := osz_path + ".part"
	var zp := ZIPPacker.new()
	var err := zp.open(tmp)
	if err != OK:
		return _fail("cannot write .osz (error %d): %s" % [err, osz_path])
	for f in files:
		zp.start_file(str(f[0]))
		zp.write_file(f[1])
		zp.close_file()
	zp.close()
	# Vorhandenes Set gleichen Namens ersetzen statt verdoppeln.
	if FileAccess.file_exists(osz_path):
		DirAccess.remove_absolute(osz_path)
	err = DirAccess.rename_absolute(tmp, osz_path)
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return _fail("cannot replace %s (error %d)" % [osz_path, err])
	return {"ok": true, "error": "", "osz_path": osz_path, "background": bg_name}


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "osz_path": ""}


# ---------------------------------------------------------------------------
# Namen
# ---------------------------------------------------------------------------

static func safe_name(s: String) -> String:
	var out := s
	for ch in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		out = out.replace(ch, "_")
	out = out.strip_edges()
	while out.ends_with("."):
		out = out.substr(0, out.length() - 1).strip_edges()
	return out


static func set_base(artist: String, title: String) -> String:
	return safe_name("%s - %s %s" % [artist, title, SUFFIX])


## "<Kuenstler> - <Titel> (OMEN Auto).osz"
static func osz_name(artist: String, title: String) -> String:
	return set_base(artist, title) + ".osz"


static func osu_name(artist: String, title: String, version: String) -> String:
	return safe_name("%s - %s %s [%s]" % [artist, title, SUFFIX, version]) + ".osu"


## Erzeugtes Set (eigene Musik)? Erkennung am Dateinamen.
static func is_auto_set(osz_path: String) -> bool:
	return osz_path.get_file().get_basename().ends_with(SUFFIX)


# ---------------------------------------------------------------------------
# Bild
# ---------------------------------------------------------------------------

## Bild fuer das Set: {name: "bg.jpg"|"bg.png"|"", bytes}. Vorrang: Bild mit
## gleichem Namen neben der Musikdatei (.jpg/.jpeg/.png/.webp, Gross-/Klein-
## schreibung egal; zuerst exakt, dann nur Buchstaben/Ziffern verglichen, z. B.
## "Song_Name.JPG" zu "Song Name.mp3"), dann genau ein Bild im selben Ordner,
## dann das eingebettete Cover (ffmpeg). Unlesbare Bilder werden uebersprungen.
## Ohne Bild: name "" (write_osz erzeugt dann preview_image).
static func find_cover(audio_path: String, ffmpeg: String) -> Dictionary:
	var dir := audio_path.get_base_dir()
	var stem := audio_path.get_file().get_basename()
	var images: Array[String] = []
	var exact: Array[String] = []
	var loose: Array[String] = []
	var d := DirAccess.open(dir)
	if d != null:
		var files := d.get_files()
		files.sort()
		for f in files:
			if not f.get_extension().to_lower() in IMAGE_EXTS:
				continue
			images.append(f)
			if f.get_basename().to_lower() == stem.to_lower():
				exact.append(f)
			elif _loose(f.get_basename()) != "" and _loose(f.get_basename()) == _loose(stem):
				loose.append(f)
	var picks: Array[String] = []
	picks.append_array(exact)
	picks.append_array(loose)
	if images.size() == 1 and picks.is_empty():
		picks.append(images[0])
	for p in picks:
		var r := _as_bg(FileAccess.get_file_as_bytes(dir.path_join(p)))
		if str(r.name) != "":
			return r
	return embedded_cover(audio_path, ffmpeg)


## Name nur aus Kleinbuchstaben und Ziffern (fuer den lockeren Namensvergleich).
static func _loose(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch.unicode_at(0) > 127:
			out += ch
	return out


## Eingebettetes Cover (Album-Art im Tag) unveraendert herausloesen.
static func embedded_cover(audio_path: String, ffmpeg: String) -> Dictionary:
	if ffmpeg == "":
		return {"name": "", "bytes": PackedByteArray()}
	var tmp := ProjectSettings.globalize_path("user://am_cover_%d.jpg" % Time.get_ticks_usec())
	var out := []
	var code := OS.execute(ffmpeg, ["-v", "error", "-y", "-i", audio_path, "-an", "-map", "0:v:0",
		"-c:v", "copy", "-frames:v", "1", "-update", "1", "-f", "image2", tmp], out, true)
	var bytes := PackedByteArray()
	if code == 0 and FileAccess.file_exists(tmp):
		bytes = FileAccess.get_file_as_bytes(tmp)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	return _as_bg(bytes)


## Bytes -> bg.jpg / bg.png. JPEG und PNG bleiben unveraendert, anderes
## (webp, bmp) wird zu JPEG, weil osu! nur jpg/png als Hintergrund nimmt.
static func _as_bg(bytes: PackedByteArray) -> Dictionary:
	var none := {"name": "", "bytes": PackedByteArray()}
	if bytes.size() < 12:
		return none
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		return {"name": "bg.jpg", "bytes": bytes}
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return {"name": "bg.png", "bytes": bytes}
	var img := OszImporter.decode_image_bytes(bytes)
	if img == null:
		return none
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return {"name": "bg.jpg", "bytes": img.save_jpg_to_buffer(0.92)}


## Huellkurve des Songs fuer das Vorschaubild: RMS je Abschnitt, normiert 0..1.
static func waveform(pcm: PackedFloat32Array, bins: int = PREVIEW_BARS) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(bins, 0))
	var n := pcm.size()
	if n == 0 or bins <= 0:
		return out
	for b in bins:
		var i := int(float(b) * n / bins)
		var e := int(float(b + 1) * n / bins)
		var sum := 0.0
		var cnt := 0
		while i < e:
			var v := pcm[i]
			sum += v * v
			cnt += 1
			i += 5
		out[b] = sqrt(sum / maxi(cnt, 1))
	return _normalized(out)


## Huellkurve aus den Features (energy, sonst Summe der Anschlagstaerken).
static func _features_wave(features: Dictionary, bins: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(bins)
	var energy: PackedFloat32Array = features.get("energy", PackedFloat32Array())
	if energy.size() >= bins:
		for b in bins:
			var a := int(float(b) * energy.size() / bins)
			var e := maxi(int(float(b + 1) * energy.size() / bins), a + 1)
			var s := 0.0
			for i in range(a, e):
				s += energy[i]
			out[b] = s / (e - a)
		return _normalized(out)
	var dur := float(features.get("duration_ms", 0.0))
	if dur <= 0.0:
		return out
	for ev in features.get("events", []):
		var b := clampi(int(float(ev.t_ms) / dur * bins), 0, bins - 1)
		out[b] += float(ev.get("strength", 0.5))
	return _normalized(out)


## Auf das 97. Perzentil normieren, leicht glaetten.
static func _normalized(v: PackedFloat32Array) -> PackedFloat32Array:
	if v.is_empty():
		return v
	var s := v.duplicate()
	s.sort()
	var top := maxf(s[int((s.size() - 1) * 0.97)], 0.000001)
	var out := PackedFloat32Array()
	out.resize(v.size())
	for i in v.size():
		var a := v[maxi(i - 1, 0)]
		var c := v[mini(i + 1, v.size() - 1)]
		out[i] = clampf((a * 0.25 + v[i] * 0.5 + c * 0.25) / top, 0.0, 1.0)
	return out


## Ruhiges Vorschaubild ohne Cover: die Huellkurve des Songs als Balken in
## Bernstein auf Graphit (UiTheme), Kiai-Abschnitte voll, der Rest gedaempft,
## darunter ein schwacher Spiegel. Kein Text (Titel zeigt der Browser).
## {name: "bg.jpg", bytes} oder name "" ohne Quelle.
static func preview_image(wave: PackedFloat32Array, features: Dictionary) -> Dictionary:
	var bins := PREVIEW_BARS
	if wave.size() != bins:
		wave = _features_wave(features, bins)
	var any := false
	for v in wave:
		if v > 0.0:
			any = true
			break
	if not any:
		return {"name": "", "bytes": PackedByteArray()}
	var w := PREVIEW_W
	var h := PREVIEW_H
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	# Graphit mit sanft hellerer Mitte.
	for y in h:
		var k := exp(-pow((float(y) - h * 0.5) / (h * 0.33), 2.0))
		img.fill_rect(Rect2i(0, y, w, 1), UiTheme.BG.lerp(UiTheme.SURFACE, k))
	var dur := float(features.get("duration_ms", 0.0))
	var kiai := kiai_ranges(features)
	var x0 := 128
	var span := w - 2 * x0
	var pitch := float(span) / bins
	var bar_w := maxi(int(pitch * 0.58), 2)
	var mid := int(h * 0.56)
	var top_h := h * 0.36
	img.fill_rect(Rect2i(x0, mid, span, 1), UiTheme.BG.lerp(UiTheme.TEXT, 0.10))
	for b in bins:
		var t := (float(b) + 0.5) / bins * dur
		var lit := false
		for k in kiai:
			if t >= float(k[0]) and t < float(k[1]):
				lit = true
		var col := UiTheme.ACCENT if lit else UiTheme.BG.lerp(UiTheme.ACCENT, 0.45)
		var v := pow(clampf(wave[b], 0.0, 1.0), 0.85)
		var up := maxi(int(4.0 + v * top_h), 2)
		var x := x0 + int(b * pitch)
		img.fill_rect(Rect2i(x, mid - up - 2, bar_w, up), col)
		var down := maxi(int(up * 0.35), 1)
		img.fill_rect(Rect2i(x, mid + 3, bar_w, down), UiTheme.BG.lerp(col, 0.28))
	return {"name": "bg.jpg", "bytes": img.save_jpg_to_buffer(0.9)}


## Audio per ffmpeg zu Ogg Vorbis (Stereo bleibt, Laenge und Lage sample-genau).
## Leer bei Fehler oder ohne ffmpeg.
static func to_ogg(audio_path: String, ffmpeg: String) -> PackedByteArray:
	var bytes := PackedByteArray()
	if ffmpeg == "":
		return bytes
	var tmp := ProjectSettings.globalize_path("user://am_audio_%d.ogg" % Time.get_ticks_usec())
	for codec in [["-c:a", "libvorbis", "-q:a", "6"], ["-c:a", "vorbis", "-strict", "-2", "-ac", "2"]]:
		var args: Array = ["-v", "error", "-y", "-i", audio_path, "-vn", "-map", "0:a:0"]
		args.append_array(codec)
		args.append(tmp)
		var code := OS.execute(ffmpeg, PackedStringArray(args), [], true)
		if code == 0 and FileAccess.file_exists(tmp):
			bytes = FileAccess.get_file_as_bytes(tmp)
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		if not bytes.is_empty():
			break
	return bytes


# ---------------------------------------------------------------------------
# Timing
# ---------------------------------------------------------------------------

## Rote Linie je Segment. Erstes Segment: fruehester Taktanfang >= 0 (osu!
## verlaengert die erste Linie nach hinten). Spaetere Segmente: erster Schlag
## des Segments; liegt der nicht auf einem Taktanfang, setzt eine zweite rote
## Linie gleichen Tempos am ersten Taktanfang den Takt zurueck.
## Rueckgabe: Array von {t, beat, meter}.
static func red_points(grid: Dictionary) -> Array:
	var out: Array = []
	var segs: Array = grid.get("segments", [])
	for i in segs.size():
		var s: Dictionary = segs[i]
		var beat := maxf(float(s.get("beat_ms", 500.0)), 1.0)
		var meter := maxi(int(s.get("meter", 4)), 1)
		var start := float(s.get("start_ms", 0.0))
		var down := float(s.get("downbeat_ms", start))
		var bar := beat * meter
		if i == 0:
			out.append({"t": fposmod(down, bar), "beat": beat, "meter": meter})
			continue
		var n := int(floor((down - start) / beat + 0.001))
		var t0 := down - n * beat
		if t0 < start - 0.5:
			t0 += beat
			n -= 1
		out.append({"t": t0, "beat": beat, "meter": meter})
		var rest := posmod(n, meter)
		if rest != 0:
			out.append({"t": t0 + rest * beat, "beat": beat, "meter": meter})
	return out


## Kiai-Abschnitte aus den Features, beruehrende zusammengelegt: [[start, end]].
static func kiai_ranges(features: Dictionary) -> Array:
	var out: Array = []
	for s in features.get("sections", []):
		if not bool(s.get("kiai", false)):
			continue
		var a := float(s.start_ms)
		var b := float(s.end_ms)
		if b <= a:
			continue
		if not out.is_empty() and a <= float(out[-1][1]) + 1.0:
			out[-1][1] = maxf(float(out[-1][1]), b)
		else:
			out.append([a, b])
	return out


## Zeilen fuer [TimingPoints]: rote Linien, gruene nur fuer Kiai an/aus.
static func timing_lines(grid: Dictionary, features: Dictionary) -> Array[String]:
	var kiai := kiai_ranges(features)
	var rows: Array = []   # [t, order, text-ohne-effects, red]
	for r in red_points(grid):
		rows.append({"t": float(r.t), "red": true, "beat": float(r.beat), "meter": int(r.meter)})
	for k in kiai:
		rows.append({"t": float(k[0]), "red": false, "on": true})
		rows.append({"t": float(k[1]), "red": false, "on": false})
	rows.sort_custom(func(a, b):
		if a.t != b.t:
			return a.t < b.t
		return bool(a.red) and not bool(b.red))
	var lines: Array[String] = []
	var meter := 4
	for r in rows:
		if bool(r.red):
			meter = int(r.meter)
			var in_kiai := false
			for k in kiai:
				if float(r.t) >= float(k[0]) and float(r.t) < float(k[1]):
					in_kiai = true
			lines.append("%s,%s,%d,2,0,60,1,%d" % [_num(float(r.t)), _num(float(r.beat), 9), meter, 1 if in_kiai else 0])
		else:
			lines.append("%s,-100,%d,2,0,60,0,%d" % [_num(float(r.t)), meter, 1 if bool(r.on) else 0])
	return lines


## Zahl ohne ueberfluessige Nullen ("1234.5", "500").
static func _num(v: float, decimals: int = 3) -> String:
	var s := ("%." + str(decimals) + "f") % v
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s


## Beginn des staerksten Refrains (sonst Kiai, sonst staerkster Abschnitt, sonst 30 %).
static func preview_time(features: Dictionary) -> int:
	var best_t := -1.0
	var best_score := -1.0
	for s in features.get("sections", []):
		var score := float(s.get("intensity", 0.0))
		if str(s.get("kind", "")) == "chorus":
			score += 2.0
		elif bool(s.get("kiai", false)):
			score += 1.0
		if score > best_score:
			best_score = score
			best_t = float(s.start_ms)
	if best_t < 0.0:
		best_t = float(features.get("duration_ms", 0.0)) * 0.3
	return int(roundf(best_t))


# ---------------------------------------------------------------------------
# .osu
# ---------------------------------------------------------------------------

static func _head(artist: String, title: String, version: String, mode: int, tags: String,
		audio_name: String, bg_name: String, features: Dictionary, diff_lines: Array,
		grid: Dictionary) -> Array[String]:
	var l: Array[String] = []
	l.append("osu file format v14")
	l.append("")
	l.append("[General]")
	l.append("AudioFilename: " + audio_name)
	l.append("AudioLeadIn: 0")
	l.append("PreviewTime: %d" % preview_time(features))
	l.append("Countdown: 0")
	l.append("SampleSet: Soft")
	l.append("StackLeniency: 0.7")
	l.append("Mode: %d" % mode)
	l.append("LetterboxInBreaks: 0")
	if mode == 3:
		l.append("SpecialStyle: 0")
	l.append("WidescreenStoryboard: 0")
	l.append("")
	l.append("[Editor]")
	l.append("DistanceSpacing: 1")
	l.append("BeatDivisor: 4")
	l.append("GridSize: 8")
	l.append("TimelineZoom: 2")
	l.append("")
	l.append("[Metadata]")
	l.append("Title:" + title)
	l.append("TitleUnicode:" + title)
	l.append("Artist:" + artist)
	l.append("ArtistUnicode:" + artist)
	l.append("Creator:" + CREATOR)
	l.append("Version:" + version)
	l.append("Source:")
	l.append("Tags:" + tags)
	l.append("BeatmapID:0")
	l.append("BeatmapSetID:-1")
	l.append("")
	l.append("[Difficulty]")
	for d in diff_lines:
		l.append(str(d))
	l.append("")
	l.append("[Events]")
	l.append("//Background and Video events")
	if bg_name != "":
		l.append("0,0,\"%s\",0,0" % bg_name)
	l.append("")
	l.append("[TimingPoints]")
	l.append_array(timing_lines(grid, features))
	l.append("")
	l.append("[HitObjects]")
	return l


## 4K-Mania-Diff. notes: [{t_ms, col, end_ms}] (end_ms < 0 = kein Hold).
static func mania_osu(artist: String, title: String, profile: String, grid: Dictionary,
		features: Dictionary, notes: Array, audio_name: String, bg_name: String) -> String:
	var pd: Dictionary = PROFILE_DIFF.get(profile, FALLBACK_DIFF)
	var l := _head(artist, title, profile, 3, "auto", audio_name, bg_name, features, [
		"HPDrainRate:" + _num(float(pd.hp), 1),
		"CircleSize:4",
		"OverallDifficulty:" + _num(float(pd.od), 1),
		"ApproachRate:5",
		"SliderMultiplier:1.4",
		"SliderTickRate:1",
	], grid)
	for n in notes:
		var col := clampi(int(n.get("col", 0)), 0, 3)
		var x := col * 128 + 64
		var t := int(roundf(float(n.get("t_ms", 0.0))))
		var end := int(roundf(float(n.get("end_ms", -1.0))))
		if end > t:
			l.append("%d,192,%d,128,0,%d:0:0:0:0:" % [x, t, end])
		else:
			l.append("%d,192,%d,1,0,0:0:0:0:" % [x, t])
	return "\n".join(l) + "\n"


## Orbit-Diff (osu!standard) wie der alte AudioMapper, aber auf dem neuen
## Gitter: je Segment waehlt AudioMapper.pick_notes die Stellen, jede Zeit wird
## auf das Gitter gerastet. {text, note_count}.
static func orbit_osu(artist: String, title: String, difficulty: String, grid: Dictionary,
		features: Dictionary, audio_name: String, bg_name: String) -> Dictionary:
	var cfg: Dictionary = AudioMapper.DIFFS[difficulty]
	var segs: Array = grid.get("segments", [])
	var dur := float(features.get("duration_ms", 0.0))
	var events: Array = features.get("events", [])
	var picked: Array = []   # [t, on_beat, bar_start, slot]
	for i in segs.size():
		var s: Dictionary = segs[i]
		var a := float(s.start_ms) if i > 0 else -INF
		var b := float(segs[i + 1].start_ms) if i + 1 < segs.size() else INF
		var onsets: Array = []
		for e in events:
			var t := float(e.t_ms)
			if t - AudioMapper.OSU_LEAD_MS >= a and t - AudioMapper.OSU_LEAD_MS < b:
				onsets.append([t, float(e.strength)])
		if onsets.is_empty():
			continue
		var an := {"bpm": 60000.0 / float(s.beat_ms), "offset_ms": float(s.downbeat_ms) + AudioMapper.OSU_LEAD_MS,
			"onsets": onsets, "duration_ms": dur}
		for n in AudioMapper.pick_notes(an, difficulty):
			var t := float(n[0])
			if t < a or t >= b:
				continue
			picked.append([AmGrid.snap(grid, t, 4), bool(n[2]), bool(n[3]), int(n[1])])
	var l := _head(artist, title, ORBIT_PREFIX + difficulty, 0, "auto orbit", audio_name, bg_name, features, [
		"HPDrainRate:5",
		"CircleSize:4",
		"OverallDifficulty:" + _num(float(cfg.od), 1),
		"ApproachRate:" + _num(float(cfg.ar), 1),
		"SliderMultiplier:1.4",
		"SliderTickRate:1",
	], grid)
	var angle := 0.0
	var dir := 1.0
	var last_t := -INF
	var bars_seen := 0
	var count := 0
	for n in picked:
		var t: float = n[0]
		if t <= last_t:
			continue
		var gap := minf(t - last_t, 1000.0)
		if n[2]:
			bars_seen += 1
			if bars_seen % 2 == 0:
				dir = -dir
		if last_t > -INF:
			angle += dir * clampf(gap * 0.09, 10.0, 34.0)
		last_t = t
		var r := AudioMapper.RADIUS_OUT if n[1] else AudioMapper.RADIUS_IN
		var rad := deg_to_rad(angle)
		l.append("%d,%d,%d,1,0,0:0:0:0:" % [int(roundf(256.0 + r * sin(rad))), int(roundf(192.0 - r * cos(rad))), int(roundf(t))])
		count += 1
	return {"text": "\n".join(l) + "\n", "note_count": count}
