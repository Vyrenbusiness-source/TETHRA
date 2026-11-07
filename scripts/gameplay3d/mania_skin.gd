class_name ManiaSkin
extends RefCounted

## osu!mania-Skin fuer den 2D-Modus. Statisch: import_skin / list_skins /
## delete_skin / load_skin. Instanz: geparste skin.ini ([Mania]-Block mit
## Keys: 4) plus lazy geladene Texturen aus user://skins/<name>/.
## Nie Absturz: kaputte oder fehlende Dateien liefern null, der Aufrufer
## (Playfield2D) faellt dann fuer genau dieses Element auf den eingebauten
## Look zurueck. Keine Autoload-Abhaengigkeit (laeuft auch in Headless-Tests).

const SKINS_DIR := "user://skins"
const MAX_FILE_BYTES := 8 * 1024 * 1024
const SCREEN_UNITS := 480.0   ## osu-Koordinaten: 480 Einheiten = Bildhoehe
const DEFAULT_COLUMN_WIDTH := 30.0
const DEFAULT_HIT_POSITION := 402.0

var skin_name := ""
var keys := 4
var column_width: Array = []        ## pro Spalte, osu-Einheiten
var column_line_width: Array = []   ## pro Spalte (Linie links davon), Einheiten
var column_spacing: Array = []      ## zwischen Spalte i und i+1
var column_start := 0.0
var hit_position := DEFAULT_HIT_POSITION   ## Einheiten von oben
var light_position := 413.0
var score_position := 325.0
var colours: Dictionary = {}        ## Spalte (0-basiert) -> Color
var colour_hold: Variant = null     ## Color oder null
var judgement_line := true
var note_body_style := 1            ## 0 gestreckt, 1 gekachelt ab Kopf, 2 gekachelt ab Ende
var keys_under_notes := false
var has_mania_block := false

var _dir := ""
var _names: Dictionary = {}         ## logischer Schluessel -> Dateiname aus skin.ini ("" = Standard)
var _files: Dictionary = {}         ## lowercase relativer Pfad (ohne .png) -> echter relativer Pfad
var _tex: Dictionary = {}           ## logischer Schluessel -> Texture2D oder null


# ---------------------------------------------------------------- Parser

## skin.ini -> Array von Dictionaries {"_section": String, key(lowercase): value}.
static func parse_ini(text: String) -> Array:
	var out: Array = []
	var cur: Dictionary = {}
	if text.begins_with("﻿"):
		text = text.substr(1)
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("//") or line.begins_with(";"):
			continue
		if line.begins_with("["):
			var e := line.find("]")
			if e > 0:
				cur = {"_section": line.substr(1, e - 1).strip_edges().to_lower()}
				out.append(cur)
			continue
		var c := line.find(":")
		if c <= 0 or cur.is_empty():
			continue
		var v := line.substr(c + 1)
		var cm := v.find("//")
		if cm >= 0:
			v = v.substr(0, cm)
		cur[line.substr(0, c).strip_edges().to_lower()] = v.strip_edges()
	return out


## Den [Mania]-Block mit Keys: <keys> nehmen; sonst {} (= Standard-Namen).
static func pick_mania_block(sections: Array, p_keys: int) -> Dictionary:
	for s in sections:
		if String(s.get("_section", "")) == "mania" and int(String(s.get("keys", "0"))) == p_keys:
			return s
	return {}


static func _floats(v: String) -> Array:
	var out: Array = []
	for p in v.split(","):
		var t := p.strip_edges()
		if t.is_valid_float():
			out.append(t.to_float())
	return out


static func _color(v: String) -> Variant:
	var p := _floats(v)
	if p.size() < 3:
		return null
	var a: float = p[3] / 255.0 if p.size() > 3 else 1.0
	return Color(clampf(p[0] / 255.0, 0, 1), clampf(p[1] / 255.0, 0, 1), clampf(p[2] / 255.0, 0, 1), clampf(a, 0, 1))


## Standard-Dateiname-Nummer je Spalte (4K: 1,2,2,1; sonst abwechselnd).
static func pattern_index(col: int, count: int) -> int:
	if count == 4:
		return 1 if (col == 0 or col == 3) else 2
	return 1 if col % 2 == 0 else 2


static func parse(text: String, p_keys: int = 4) -> ManiaSkin:
	var s := ManiaSkin.new()
	s.keys = p_keys
	var m := pick_mania_block(parse_ini(text), p_keys)
	s.has_mania_block = not m.is_empty()
	var cw := _floats(String(m.get("columnwidth", "")))
	var lw := _floats(String(m.get("columnlinewidth", "")))
	var sp := _floats(String(m.get("columnspacing", "")))
	for i in p_keys:
		s.column_width.append(maxf(1.0, float(cw[i] if i < cw.size() else (cw[cw.size() - 1] if not cw.is_empty() else DEFAULT_COLUMN_WIDTH))))
	for i in p_keys + 1:
		s.column_line_width.append(maxf(0.0, float(lw[i] if i < lw.size() else (lw[lw.size() - 1] if not lw.is_empty() else 2.0))))
	for i in maxi(0, p_keys - 1):
		s.column_spacing.append(maxf(0.0, float(sp[i] if i < sp.size() else (sp[sp.size() - 1] if not sp.is_empty() else 0.0))))
	s.column_start = float(String(m.get("columnstart", "0")).to_float())
	s.hit_position = clampf(float(String(m.get("hitposition", str(DEFAULT_HIT_POSITION))).to_float()), 240.0, 479.0)
	s.light_position = String(m.get("lightposition", "413")).to_float()
	s.score_position = String(m.get("scoreposition", "325")).to_float()
	s.judgement_line = String(m.get("judgementline", "1")).strip_edges() != "0"
	s.note_body_style = clampi(int(String(m.get("notebodystyle", "1"))), 0, 2)
	s.keys_under_notes = String(m.get("keysundernotes", "0")).strip_edges() == "1"
	for i in p_keys:
		var col: Variant = _color(String(m.get("colour%d" % (i + 1), "")))
		if col != null:
			s.colours[i] = col
	s.colour_hold = _color(String(m.get("colourhold", "")))
	for i in p_keys:
		var n := "mania-note%d" % pattern_index(i, p_keys)
		var k := "mania-key%d" % pattern_index(i, p_keys)
		s._names["note_%d" % i] = String(m.get("noteimage%d" % i, n))
		s._names["head_%d" % i] = String(m.get("noteimage%dh" % i, ""))
		s._names["body_%d" % i] = String(m.get("noteimage%dl" % i, ""))
		s._names["tail_%d" % i] = String(m.get("noteimage%dt" % i, ""))
		s._names["key_%d" % i] = String(m.get("keyimage%d" % i, k))
		s._names["keyd_%d" % i] = String(m.get("keyimage%dd" % i, k + "D"))
		# Standard-Namen fuer H/L/T, wenn die ini nichts setzt.
		var base := String(s._names["note_%d" % i])
		for suf in ["head", "body", "tail"]:
			if String(s._names["%s_%d" % [suf, i]]).is_empty():
				s._names["%s_%d" % [suf, i]] = base + {"head": "H", "body": "L", "tail": "T"}[suf]
	s._names["stage_left"] = String(m.get("stageleft", "mania-stage-left"))
	s._names["stage_right"] = String(m.get("stageright", "mania-stage-right"))
	s._names["stage_hint"] = String(m.get("stagehint", "mania-stage-hint"))
	s._names["stage_bottom"] = String(m.get("stagebottom", "mania-stage-bottom"))
	return s


# ------------------------------------------------------------ Geometrie

func col_units(col: int) -> float:
	return float(column_width[clampi(col, 0, column_width.size() - 1)])


## Gesamtbreite der Buehne in Einheiten (Spalten + Spacing).
func stage_units() -> float:
	var w := 0.0
	for c in keys:
		w += col_units(c)
	for s in column_spacing:
		w += float(s)
	return w


## Linke Kante der Spalte in Einheiten ab Buehnen-Anfang.
func col_offset_units(col: int) -> float:
	var x := 0.0
	for c in col:
		x += col_units(c)
		if c < column_spacing.size():
			x += float(column_spacing[c])
	return x


# -------------------------------------------------------------- Texturen

## Textur zum logischen Schluessel (note_0, head_0, body_0, tail_0, key_0,
## keyd_0, stage_left/right/hint) oder null (fehlt/kaputt).
func tex(key: String) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var t: Texture2D = null
	_at2x_pending = false
	if not _dir.is_empty() and _names.has(key):
		t = _load_image(String(_names[key]))
	_at2x[key] = t != null and _at2x_pending
	_tex[key] = t
	return t


## @2x-Datei? Dann gelten alle Pixelmasse halbiert.
func tex_scale(key: String) -> float:
	return 0.5 if _at2x.get(key, false) else 1.0

var _at2x: Dictionary = {}


## Pfad aus der ini -> echter relativer Pfad im Skin-Ordner ("" = nicht da).
func resolve(ini_path: String) -> Array:
	var p := ini_path.strip_edges().replace("\\", "/").to_lower()
	while p.begins_with("./"):
		p = p.substr(2)
	if p.ends_with(".png"):
		p = p.substr(0, p.length() - 4)
	if p.is_empty() or p.contains(".."):
		return ["", false]
	if _files.has(p + "@2x"):
		return [_files[p + "@2x"], true]
	if _files.has(p):
		return [_files[p], false]
	return ["", false]


func _load_image(ini_path: String) -> Texture2D:
	var r := resolve(ini_path)
	var rel := String(r[0])
	if rel.is_empty():
		return null
	var f := FileAccess.open(_dir + "/" + rel, FileAccess.READ)
	if f == null or f.get_length() > MAX_FILE_BYTES or f.get_length() <= 0:
		return null
	var img := Image.new()
	if img.load_png_from_buffer(f.get_buffer(f.get_length())) != OK or img.is_empty():
		return null
	if img.get_width() < 1 or img.get_height() < 1 or img.get_width() > 4096 or img.get_height() > 4096:
		return null
	_at2x_pending = bool(r[1])
	return ImageTexture.create_from_image(img)

var _at2x_pending := false


# ------------------------------------------------------- Laden / Verwalten

static func skin_path(skin_name_: String) -> String:
	return SKINS_DIR + "/" + safe_name(skin_name_)


static func safe_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		var o := ch.unicode_at(0)
		var ok := (o >= 48 and o <= 57) or (o >= 65 and o <= 90) or (o >= 97 and o <= 122) \
				or ch in [" ", "_", "-", ".", "(", ")"]
		out += ch if ok else "_"
	out = out.lstrip(".").strip_edges()
	return out if not out.is_empty() else "skin"


static func list_skins() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(SKINS_DIR)
	if d == null:
		return out
	for n in d.get_directories():
		out.append(n)
	out.sort()
	return out


static func delete_skin(p_name: String) -> bool:
	if p_name.is_empty() or p_name != safe_name(p_name):
		return false
	var base := skin_path(p_name)
	if not DirAccess.dir_exists_absolute(base):
		return false
	_remove_tree(base)
	return not DirAccess.dir_exists_absolute(base)


static func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_remove_tree(path + "/" + sub)
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(path)


static func load_skin(p_name: String) -> ManiaSkin:
	if p_name.is_empty() or p_name != safe_name(p_name):
		return null
	var dir := skin_path(p_name)
	if not DirAccess.dir_exists_absolute(dir):
		return null
	var text := ""
	var f := FileAccess.open(dir + "/skin.ini", FileAccess.READ)
	if f != null and f.get_length() <= MAX_FILE_BYTES:
		text = f.get_as_text()
	var s := parse(text, 4)
	s.skin_name = p_name
	s._dir = dir
	for rel in _list_files(dir, ""):
		var low := String(rel).to_lower()
		if low.ends_with(".png"):
			s._files[low.substr(0, low.length() - 4)] = rel
	return s


static func _list_files(base: String, rel: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(base + ("/" + rel if rel != "" else ""))
	if d == null:
		return out
	for f in d.get_files():
		out.append(rel + ("/" if rel != "" else "") + f)
	for sub in d.get_directories():
		out.append_array(_list_files(base, rel + ("/" if rel != "" else "") + sub))
	return out


# --------------------------------------------------------------- Import

## Relativen Pfad pruefen (Zip-Slip): "" wenn absolut, mit "..", Laufwerk usw.
static func safe_rel(path: String) -> String:
	var p := path.replace("\\", "/")
	if p.is_empty() or p.begins_with("/") or p.contains(":"):
		return ""
	var parts: PackedStringArray = []
	for seg in p.split("/"):
		if seg == "" or seg == ".":
			continue
		if seg == "..":
			return ""
		parts.append(seg)
	if parts.is_empty():
		return ""
	return "/".join(parts)


## .osk/.zip oder Skin-Ordner -> user://skins/<name>/. Gibt den Namen zurueck, "" bei Fehler.
static func import_skin(path: String) -> String:
	var entries: Dictionary = {}   # relativer Pfad -> Callable() -> PackedByteArray
	var base_name := path.replace("\\", "/").trim_suffix("/").get_file().get_basename()
	var zr: ZIPReader = null
	if DirAccess.dir_exists_absolute(path):
		base_name = path.replace("\\", "/").trim_suffix("/").get_file()
		for rel in _list_abs(path, ""):
			entries[rel] = path.path_join(rel)
	elif FileAccess.file_exists(path):
		zr = ZIPReader.new()
		if zr.open(path) != OK:
			return ""
		for fn in zr.get_files():
			if not String(fn).ends_with("/"):
				entries[String(fn).replace("\\", "/")] = fn
	else:
		return ""
	# Praefix-Ordner: skin.ini liegt evtl. eine Ebene tiefer.
	var prefix := ""
	var best := 9999
	for rel in entries:
		if String(rel).get_file().to_lower() == "skin.ini":
			var depth := String(rel).count("/")
			if depth < best:
				best = depth
				prefix = String(rel).get_base_dir()
	var files: Dictionary = {}   # sauberer relativer Pfad -> Quelle
	for rel in entries:
		var r := String(rel)
		if prefix != "":
			if not r.begins_with(prefix + "/"):
				continue
			r = r.substr(prefix.length() + 1)
		var clean := safe_rel(r)
		if clean.is_empty():
			continue
		files[clean] = entries[rel]
	var ini_key := ""
	for rel in files:
		if String(rel).to_lower() == "skin.ini":
			ini_key = rel
	var ini_text := ""
	if ini_key != "":
		ini_text = _read_source(files[ini_key], zr).get_string_from_utf8()
	# Referenzierte Bilder aus allen [Mania]-Bloecken.
	var wanted: Dictionary = {}
	for sec in parse_ini(ini_text):
		if String(sec.get("_section", "")) != "mania":
			continue
		for k in sec:
			var ks := String(k)
			if ks.begins_with("noteimage") or ks.begins_with("keyimage") or ks.begins_with("stage"):
				var v := String(sec[k]).strip_edges().replace("\\", "/").to_lower()
				if v.ends_with(".png"):
					v = v.substr(0, v.length() - 4)
				if v != "":
					wanted[v] = true
	var chosen: Array = []
	var stems: Dictionary = {}
	for rel in files:
		var low := String(rel).to_lower()
		if low == "skin.ini":
			chosen.append(rel)
			continue
		if not low.ends_with(".png"):
			continue
		var stem := low.substr(0, low.length() - 4)
		stems[stem] = true
		var plain := stem.trim_suffix("@2x")
		if low.get_file().begins_with("mania-") or wanted.has(stem) or wanted.has(plain):
			chosen.append(rel)
	# @2x bevorzugt: Basisdatei weglassen, wenn die @2x-Variante auch da ist.
	var final: Array = []
	for rel in chosen:
		var low2 := String(rel).to_lower()
		if low2.ends_with(".png") and not low2.ends_with("@2x.png") \
				and stems.has(low2.substr(0, low2.length() - 4) + "@2x"):
			continue
		final.append(rel)
	var png_count := 0
	for rel in final:
		if String(rel).to_lower().ends_with(".png"):
			png_count += 1
	if png_count == 0:
		return ""
	var nm := safe_name(base_name)
	var dest := SKINS_DIR + "/" + nm
	if DirAccess.dir_exists_absolute(dest):
		_remove_tree(dest)
	for rel in final:
		var bytes := _read_source(files[rel], zr)
		if bytes.is_empty() or bytes.size() > MAX_FILE_BYTES:
			continue
		var out_path := dest + "/" + String(rel)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var wf := FileAccess.open(out_path, FileAccess.WRITE)
		if wf == null:
			continue
		wf.store_buffer(bytes)
		wf.close()
	if not DirAccess.dir_exists_absolute(dest):
		return ""
	return nm


static func _read_source(src: Variant, zr: ZIPReader) -> PackedByteArray:
	if zr != null:
		return zr.read_file(String(src))
	var f := FileAccess.open(String(src), FileAccess.READ)
	if f == null or f.get_length() > MAX_FILE_BYTES:
		return PackedByteArray()
	return f.get_buffer(f.get_length())


static func _list_abs(base: String, rel: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(base.path_join(rel) if rel != "" else base)
	if d == null:
		return out
	for f in d.get_files():
		out.append(rel + ("/" if rel != "" else "") + f)
	for sub in d.get_directories():
		out.append_array(_list_abs(base, rel + ("/" if rel != "" else "") + sub))
	return out
