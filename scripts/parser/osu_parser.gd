class_name OsuParser
extends RefCounted

## Parser fuer das osu file format v14 (abwaertskompatibel v9-v13).
## Verbindliche Referenz: Abschnitt 3 des Masterplans. Keine eigenen Annahmen —
## bei Unklarheit gelten ausschliesslich die Formeln aus dem Dokument.
##
## parse(text) liefert ein Dictionary:
##   { ok: bool, error: String, beatmap: Beatmap }
## Nur Mode 0 (osu!standard) wird akzeptiert; alles andere wird mit klarer
## Fehlermeldung abgelehnt (Regel 2).

const KEYVALUE_SECTIONS := ["General", "Metadata", "Difficulty", "Editor", "Colours"]


static func parse(text: String) -> Dictionary:
	var beatmap := Beatmap.new()

	# BOM entfernen und in Zeilen zerlegen (CRLF-tolerant).
	text = text.lstrip("﻿")
	var raw_lines := text.split("\n")
	var lines: Array[String] = []
	for l in raw_lines:
		lines.append(l.rstrip("\r"))

	if lines.is_empty():
		return _fail("Leere Datei.")

	# Erste (nicht-leere) Zeile: "osu file format vN".
	var version_line := ""
	for l in lines:
		if l.strip_edges() != "":
			version_line = l.strip_edges()
			break
	beatmap.format_version = _parse_format_version(version_line)
	if beatmap.format_version == -1:
		return _fail("Keine gueltige 'osu file format vN'-Kopfzeile gefunden.")

	# In Sektionen aufteilen.
	var sections := _split_sections(lines)

	# Key-Value-Sektionen parsen.
	beatmap.general = _parse_key_values(_section(sections, "General"))
	beatmap.metadata = _parse_key_values(_section(sections, "Metadata"))
	beatmap.difficulty = _parse_key_values(_section(sections, "Difficulty"))

	# Mode-Pruefung: osu!standard (0) und osu!mania (3). Taiko/Catch abgelehnt.
	var mode := int(beatmap.general.get("Mode", 0))
	if mode != 0 and mode != 3:
		var mode_name := _mode_name(mode)
		return _fail("Nur osu!standard (0) und osu!mania (3) werden unterstuetzt. Diese Map ist Mode %d (%s)." % [mode, mode_name])

	# Difficulty-Defaults und AR-Fallback (Abschnitt 3.2): fehlt AR, gilt AR = OD.
	_apply_difficulty_defaults(beatmap.difficulty)

	# TimingPoints parsen.
	for line in _section(sections, "TimingPoints"):
		var tp := _parse_timing_line(line)
		if tp != null:
			beatmap.timing_points.append(tp)
	# Defensiv nach time sortieren.
	beatmap.timing_points.sort_custom(func(a, b): return a.time < b.time)

	# Kiai-Intervalle aus den TimingPoints ableiten (Abschnitt 3.3).
	beatmap.kiai_intervals = _build_kiai_intervals(beatmap.timing_points)

	# Hintergrundbild aus [Events] (fuer den Song-Browser).
	beatmap.background_file = _parse_background(_section(sections, "Events"))

	# HitObjects parsen (Mania: Spalten-Notes; Standard: Circle/Slider/Spinner).
	var slider_mult := float(beatmap.difficulty.get("SliderMultiplier", 1.4))
	var columns := maxi(int(float(beatmap.difficulty.get("CircleSize", 4))), 1)
	for line in _section(sections, "HitObjects"):
		var obj: HitObject = null
		if mode == 3:
			obj = _parse_mania_note(line, columns)
		else:
			obj = _parse_hit_object(line, beatmap.timing_points, slider_mult)
		if obj != null:
			beatmap.hit_objects.append(obj)
	# Defensiv nach time sortieren (Abschnitt 3.4).
	beatmap.hit_objects.sort_custom(func(a, b): return a.time < b.time)

	return { "ok": true, "error": "", "beatmap": beatmap }


# ---------------------------------------------------------------------------
# Kopfzeile / Sektionen
# ---------------------------------------------------------------------------

static func _parse_format_version(line: String) -> int:
	# Erwartet z.B. "osu file format v14".
	var idx := line.find("format v")
	if idx == -1:
		return -1
	var num := line.substr(idx + "format v".length()).strip_edges()
	if num.is_valid_int():
		return int(num)
	# Nur fuehrende Ziffern nehmen.
	var digits := ""
	for c in num:
		if c >= "0" and c <= "9":
			digits += c
		else:
			break
	return int(digits) if digits != "" else -1


## Liefert die Zeilen einer Sektion als typisiertes Array[String], oder ein
## leeres typisiertes Array wenn die Sektion fehlt (verhindert Typfehler beim
## Uebergeben an typisierte Parameter).
static func _section(sections: Dictionary, name: String) -> Array[String]:
	if sections.has(name):
		return sections[name]
	var empty: Array[String] = []
	return empty


static func _split_sections(lines: Array[String]) -> Dictionary:
	var sections := {}
	var current := ""
	for line in lines:
		var stripped := line.strip_edges()
		if stripped == "":
			continue
		# Volle Kommentarzeilen (Abschnitt 3.2). Kein Inline-Stripping, da echte
		# .osu-Werte kein '//' enthalten und wir Daten nicht beschaedigen wollen.
		if stripped.begins_with("//"):
			continue
		if stripped.begins_with("[") and stripped.ends_with("]"):
			current = stripped.substr(1, stripped.length() - 2)
			if not sections.has(current):
				sections[current] = ([] as Array[String])
			continue
		if current != "":
			(sections[current] as Array[String]).append(line)
	return sections


static func _parse_key_values(section_lines: Array[String]) -> Dictionary:
	var result := {}
	for line in section_lines:
		var idx := line.find(":")
		if idx == -1:
			continue
		var key := line.substr(0, idx).strip_edges()
		var value := line.substr(idx + 1).strip_edges()
		if key != "":
			result[key] = value
	return result


static func _apply_difficulty_defaults(difficulty: Dictionary) -> void:
	# Fehlt AR (alte Maps), gilt AR = OD (Abschnitt 3.2).
	if not difficulty.has("ApproachRate"):
		if difficulty.has("OverallDifficulty"):
			difficulty["ApproachRate"] = difficulty["OverallDifficulty"]
		else:
			difficulty["ApproachRate"] = "5"


# ---------------------------------------------------------------------------
# TimingPoints (Abschnitt 3.3)
# ---------------------------------------------------------------------------

static func _parse_timing_line(line: String) -> TimingPoint:
	var parts := line.split(",")
	if parts.size() < 2:
		return null
	var tp := TimingPoint.new()
	tp.time = float(parts[0].strip_edges())
	tp.beat_length = float(parts[1].strip_edges())
	# Alte Versionen: nur 2 Felder -> uninherited = 1.
	tp.meter = int(parts[2].strip_edges()) if parts.size() > 2 else 4
	if tp.meter <= 0:
		tp.meter = 4
	tp.uninherited = (int(parts[6].strip_edges()) == 1) if parts.size() > 6 else true
	tp.effects = int(parts[7].strip_edges()) if parts.size() > 7 else 0
	tp.kiai = (tp.effects & 1) == 1
	return tp


## Hintergrundbild aus der [Events]-Sektion. Format der Background-Zeile:
## 0,0,"BG.jpg",0,0  (Event-Typ 0 = Background). Video (Typ 1/"Video") wird
## ignoriert. Es zaehlt der erste Background-Eintrag.
static func _parse_background(events: Array[String]) -> String:
	for line in events:
		var parts := line.split(",")
		if parts.size() < 3:
			continue
		var ev := parts[0].strip_edges()
		if ev == "0" or ev.to_lower() == "background":
			var name := parts[2].strip_edges()
			# Umschliessende Anfuehrungszeichen entfernen.
			if name.begins_with("\""):
				name = name.substr(1)
			if name.ends_with("\""):
				name = name.substr(0, name.length() - 1)
			return name
	return ""


static func _build_kiai_intervals(timing_points: Array[TimingPoint]) -> Array[Dictionary]:
	# Kiai beginnt bei einem Point mit gesetztem Bit und endet beim naechsten
	# Point ohne (Abschnitt 3.3). Offen bleibende Kiai laeuft bis INF.
	var intervals: Array[Dictionary] = []
	var in_kiai := false
	var start := 0.0
	for tp in timing_points:
		if tp.kiai and not in_kiai:
			in_kiai = true
			start = tp.time
		elif not tp.kiai and in_kiai:
			in_kiai = false
			intervals.append({ "start": start, "end": tp.time })
	if in_kiai:
		intervals.append({ "start": start, "end": INF })
	return intervals


# ---------------------------------------------------------------------------
# HitObjects (Abschnitt 3.4)
# ---------------------------------------------------------------------------

static func _parse_hit_object(line: String, timing_points: Array[TimingPoint], slider_mult: float) -> HitObject:
	var parts := line.split(",")
	if parts.size() < 4:
		return null
	var x := float(parts[0].strip_edges())
	var y := float(parts[1].strip_edges())
	var time := float(parts[2].strip_edges())
	var type := int(parts[3].strip_edges())

	# Slider zuerst, dann Spinner, dann Circle — Reihenfolge wie im Pseudocode.
	if (type & 2) != 0:
		return _parse_slider(parts, x, y, time, type, timing_points, slider_mult)
	elif (type & 8) != 0:
		return _parse_spinner(parts, x, y, time, type)
	elif (type & 1) != 0:
		return _parse_circle(x, y, time, type)
	# Unbekannter Typ -> ignorieren.
	return null


## Mania-Note (Mode 3): column = floor(x * columns / 512); Hold = type & 128,
## endTime steht in objectParams als "endTime:hitSample".
static func _parse_mania_note(line: String, columns: int) -> ManiaNote:
	var parts := line.split(",")
	if parts.size() < 4:
		return null
	var n := ManiaNote.new()
	n.x = float(parts[0].strip_edges())
	n.y = float(parts[1].strip_edges())
	n.time = float(parts[2].strip_edges())
	n.type = int(parts[3].strip_edges())
	n.column = clampi(int(n.x * float(columns) / 512.0), 0, columns - 1)
	if (n.type & 128) != 0 and parts.size() > 5:
		n.is_hold = true
		n.hold_end = float(parts[5].split(":")[0].strip_edges())
	return n


static func _parse_circle(x: float, y: float, time: float, type: int) -> HitCircle:
	var c := HitCircle.new()
	c.x = x
	c.y = y
	c.time = time
	c.type = type
	c.new_combo = (type & 4) != 0
	return c


static func _parse_spinner(parts: PackedStringArray, x: float, y: float, time: float, type: int) -> Spinner:
	var s := Spinner.new()
	s.x = x
	s.y = y
	s.time = time
	s.type = type
	s.new_combo = (type & 4) != 0
	# x,y,time,type,hitSound,endTime,hitSample -> endTime an Index 5.
	s.spin_end_time = float(parts[5].strip_edges()) if parts.size() > 5 else time
	return s


static func _parse_slider(parts: PackedStringArray, x: float, y: float, time: float, type: int, timing_points: Array[TimingPoint], slider_mult: float) -> HitSlider:
	var s := HitSlider.new()
	s.x = x
	s.y = y
	s.time = time
	s.type = type
	s.new_combo = (type & 4) != 0

	# Index 5: curveType|curvePoints
	if parts.size() > 5:
		var curve_field := parts[5].strip_edges()
		var tokens := curve_field.split("|")
		if tokens.size() > 0 and tokens[0].length() > 0:
			s.curve_type = tokens[0]
		# Startpunkt ist der erste Kurvenpunkt und steht NICHT in der Liste.
		var pts := PackedVector2Array()
		pts.append(Vector2(x, y))
		for i in range(1, tokens.size()):
			var pt := tokens[i].split(":")
			if pt.size() >= 2:
				pts.append(Vector2(float(pt[0]), float(pt[1])))
		s.curve_points = pts

	# Index 6: slides, Index 7: length
	s.slides = int(parts[6].strip_edges()) if parts.size() > 6 else 1
	if s.slides < 1:
		s.slides = 1
	s.length = float(parts[7].strip_edges()) if parts.size() > 7 else 0.0

	# Dauer eines Durchlaufs (Abschnitt 3.4):
	# durationMs = length / (SliderMultiplier * 100 * SV) * beatLength
	var beat_length := _active_beat_length(time, timing_points)
	var sv := _active_slider_velocity(time, timing_points)
	var denom := slider_mult * 100.0 * sv
	if denom != 0.0 and beat_length > 0.0:
		s.single_duration_ms = s.length / denom * beat_length
	else:
		s.single_duration_ms = 0.0

	return s


# ---------------------------------------------------------------------------
# Aktive TimingPoints ermitteln
# ---------------------------------------------------------------------------

static func _active_beat_length(time: float, timing_points: Array[TimingPoint]) -> float:
	# Letzter roter Point mit time <= object.time; Fallback: erster roter Point.
	var result := 0.0
	var first_red := 0.0
	var found_first := false
	var found := false
	for tp in timing_points:
		if tp.uninherited:
			if not found_first:
				first_red = tp.beat_length
				found_first = true
			if tp.time <= time:
				result = tp.beat_length
				found = true
	if found:
		return result
	return first_red if found_first else 0.0


static func _active_slider_velocity(time: float, timing_points: Array[TimingPoint]) -> float:
	# Letzter gruener Point mit time <= object.time; sonst SV = 1.0.
	var sv := 1.0
	for tp in timing_points:
		if not tp.uninherited and tp.time <= time:
			sv = tp.slider_velocity()
	return sv


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

static func _mode_name(mode: int) -> String:
	match mode:
		1: return "taiko"
		2: return "catch"
		3: return "mania"
		_: return "unbekannt"


static func _fail(msg: String) -> Dictionary:
	return { "ok": false, "error": msg, "beatmap": null }
