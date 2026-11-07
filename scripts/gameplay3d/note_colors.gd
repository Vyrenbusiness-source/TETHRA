class_name NoteColors
extends RefCounted

## Einstellbare Notenfarben, getrennt fuer 3D und 2D (eigene Datei, nicht Settings).
## Modus "auto": Farbe nach Map/Welt (map_color wird unveraendert zurueckgegeben).
## "lanes": eigene Farbe je Spalte (Holds eigene oder automatisch etwas dunkler).
## "snap": Farbe nach Takt-Teilung (osu!-Schema: 1/1 rot, 1/2 blau, 1/4 gelb ...).
## CLI (nur Laufzeit, speichert nichts): --notecolors=auto|lanes|snap, --notepreset=<id>.

const MODES: Array[String] = ["auto", "lanes", "snap"]
const LANES := 4
## Holds ohne eigene Farbe: so viel dunkler als die Notenfarbe.
const HOLD_DARKEN := 0.28
## Lesbarkeit auf dem dunklen Feld: Helligkeit (HSV-V) im erlaubten Bereich.
const MIN_V := 0.55
const MAX_V := 0.95

## Reihenfolge der Vorlagen = Reihenfolge der Chips.
const PRESET_IDS: Array[String] = ["standard", "classic", "neon", "pastel", "mono"]
const PRESETS := {
	"standard": [Color("33d9ff"), Color("ff73e0"), Color("8cffbf"), Color("ffcc59")],
	"classic": [Color("f2f2f2"), Color("6aa8ff"), Color("6aa8ff"), Color("f2f2f2")],
	"neon": [Color("19f0ff"), Color("ff2eb8"), Color("a6ff2e"), Color("ffa01f")],
	"pastel": [Color("a8d8f0"), Color("f2b4d4"), Color("b8ecc8"), Color("f2e0a0")],
	"mono": [Color("f0f0f0"), Color("c4c4c4"), Color("c4c4c4"), Color("f0f0f0")],
}
const PRESET_NAMES := {
	"standard": "Standard", "classic": "Klassisch 4K", "neon": "Neon",
	"pastel": "Pastell", "mono": "Monochrom",
}

## Takt-Teilung -> Farbe (osu!-Schema, auf dunklem Grund kraeftig, nicht grell).
const SNAP_PALETTE := {
	1: Color("f2554f"), 2: Color("4f8cf2"), 3: Color("b068f2"), 4: Color("f2cf4a"),
	6: Color("f27ab8"), 8: Color("f2954a"), 12: Color("4fd6c8"), 16: Color("d6d9de"),
}

static var path := "user://note_colors.cfg"
static var _loaded := false
static var _link_2d := false
static var _cfg := {}   ## "3d" / "2d" -> {mode, preset, hold_auto, lanes:Array, holds:Array}


static func _default_set() -> Dictionary:
	return {
		"mode": "auto", "preset": "standard", "hold_auto": true,
		"lanes": preset_colors("standard"), "holds": _auto_holds(preset_colors("standard")),
	}


static func _auto_holds(lanes: Array) -> Array:
	var out := []
	for c in lanes:
		out.append(hold_of(c))
	return out


## Standard-Hold-Farbe zu einer Notenfarbe: etwas dunkler.
static func hold_of(c: Color) -> Color:
	return c.darkened(HOLD_DARKEN)


## Beim ersten Zugriff laden (Datei + CLI). reload() erzwingt Neulesen.
static func ensure_loaded() -> void:
	if _loaded:
		return
	reload()


static func reload() -> void:
	_loaded = true
	_link_2d = false
	_cfg = {"3d": _default_set(), "2d": _default_set()}
	var f := ConfigFile.new()
	if f.load(path) == OK:
		_link_2d = bool(f.get_value("general", "link_2d", false))
		for sec in ["3d", "2d"]:
			var s: Dictionary = _cfg[sec]
			var m := String(f.get_value(sec, "mode", "auto"))
			s.mode = m if MODES.has(m) else "auto"
			s.preset = String(f.get_value(sec, "preset", "standard"))
			s.hold_auto = bool(f.get_value(sec, "hold_auto", true))
			for i in LANES:
				var lc = f.get_value(sec, "lane%d" % i, s.lanes[i])
				var hc = f.get_value(sec, "hold%d" % i, s.holds[i])
				s.lanes[i] = _clamp_col(lc) if lc is Color else s.lanes[i]
				s.holds[i] = _clamp_col(hc) if hc is Color else s.holds[i]
	_apply_cli()


static func _apply_cli() -> void:
	var preset_id := ""
	var m := ""
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--notecolors="):
			m = a.trim_prefix("--notecolors=")
		elif a.begins_with("--notepreset="):
			preset_id = a.trim_prefix("--notepreset=")
	if m == "" and preset_id == "":
		return
	for sec in ["3d", "2d"]:
		if PRESETS.has(preset_id):
			var s: Dictionary = _cfg[sec]
			s.lanes = preset_colors(preset_id)
			s.holds = _auto_holds(s.lanes)
			s.hold_auto = true
			s.preset = preset_id
		if MODES.has(m):
			_cfg[sec].mode = m


static func save() -> void:
	ensure_loaded()
	var f := ConfigFile.new()
	f.set_value("general", "link_2d", _link_2d)
	for sec in ["3d", "2d"]:
		var s: Dictionary = _cfg[sec]
		f.set_value(sec, "mode", s.mode)
		f.set_value(sec, "preset", s.preset)
		f.set_value(sec, "hold_auto", s.hold_auto)
		for i in LANES:
			f.set_value(sec, "lane%d" % i, s.lanes[i])
			f.set_value(sec, "hold%d" % i, s.holds[i])
	f.save(path)


# ------------------------------------------------------------------ Zugriff

## Satz fuer 3D oder 2D; bei "2D wie 3D" gilt immer der 3D-Satz.
static func _set_of(mode_2d: bool) -> Dictionary:
	ensure_loaded()
	return _cfg["3d" if (not mode_2d or _link_2d) else "2d"]


static func link_2d() -> bool:
	ensure_loaded()
	return _link_2d


static func set_link_2d(v: bool) -> void:
	ensure_loaded()
	_link_2d = v


static func mode(mode_2d: bool) -> String:
	return _set_of(mode_2d).mode


static func set_mode(mode_2d: bool, m: String) -> void:
	if MODES.has(m):
		_set_of(mode_2d).mode = m


static func preset(mode_2d: bool) -> String:
	return _set_of(mode_2d).preset


static func hold_auto(mode_2d: bool) -> bool:
	return _set_of(mode_2d).hold_auto


static func set_hold_auto(mode_2d: bool, v: bool) -> void:
	var s := _set_of(mode_2d)
	s.hold_auto = v
	if v:
		s.holds = _auto_holds(s.lanes)


## true, wenn die Farbe NICHT mehr von Map/Welt kommt.
static func is_custom(mode_2d: bool) -> bool:
	return mode(mode_2d) != "auto"


static func lane_color(mode_2d: bool, lane: int) -> Color:
	return _set_of(mode_2d).lanes[posmod(lane, LANES)]


static func hold_color(mode_2d: bool, lane: int) -> Color:
	var s := _set_of(mode_2d)
	var i := posmod(lane, LANES)
	return hold_of(s.lanes[i]) if s.hold_auto else s.holds[i]


static func set_lane_color(mode_2d: bool, lane: int, c: Color) -> void:
	var s := _set_of(mode_2d)
	var i := posmod(lane, LANES)
	s.lanes[i] = _clamp_col(c)
	s.preset = "custom"
	if s.hold_auto:
		s.holds[i] = hold_of(s.lanes[i])


static func set_hold_color(mode_2d: bool, lane: int, c: Color) -> void:
	var s := _set_of(mode_2d)
	s.holds[posmod(lane, LANES)] = _clamp_col(c)
	s.hold_auto = false
	s.preset = "custom"


## Vorlage anwenden. switch_mode: von "auto" auf "lanes" schalten.
static func apply_preset(mode_2d: bool, id: String, switch_mode: bool = true) -> void:
	if not PRESETS.has(id):
		return
	var s := _set_of(mode_2d)
	s.lanes = preset_colors(id)
	s.holds = _auto_holds(s.lanes)
	s.hold_auto = true
	s.preset = id
	if switch_mode and s.mode == "auto":
		s.mode = "lanes"


## Vorlagenfarben, in den lesbaren Bereich gezogen (nicht grell).
static func preset_colors(id: String) -> Array:
	var out := []
	for c in PRESETS[id]:
		out.append(_clamp_col(c))
	return out


## Farbe in den lesbaren Bereich ziehen (nicht zu dunkel, nicht grell).
static func _clamp_col(c: Color) -> Color:
	return Color.from_hsv(c.h, c.s, clampf(c.v, MIN_V, MAX_V), 1.0)


static func snap_color(divisor: int) -> Color:
	return SNAP_PALETTE.get(divisor, SNAP_PALETTE[16])


## Notenfarbe. map_color = Farbe, die das Spiel heute nehmen wuerde (bei "auto"
## kommt sie unveraendert zurueck). snap_div = Takt-Teiler der Note (nur "snap").
static func color_for(lane: int, is_hold: bool, mode_2d: bool, map_color: Color,
		snap_div: int = 0) -> Color:
	match mode(mode_2d):
		"lanes":
			return hold_color(mode_2d, lane) if is_hold else lane_color(mode_2d, lane)
		"snap":
			if snap_div <= 0:
				return map_color
			var c := snap_color(snap_div)
			return hold_of(c) if is_hold else c
	return map_color
