class_name ManiaSkin
extends RefCounted

## osu!mania-Skin fuer den 2D-Modus. Statisch: import_skin / list_skins /
## delete_skin / load_skin. Instanz: geparste skin.ini ([Mania]-Block mit
## Keys: 4) plus lazy geladene Texturen aus user://skins/<name>/.
## Nie Absturz: kaputte oder fehlende Dateien liefern null, der Aufrufer
## (Playfield2D) faellt dann fuer genau dieses Element auf den eingebauten
## Look zurueck. Keine Autoload-Abhaengigkeit (laeuft auch in Headless-Tests).

const SKINS_DIR := "user://skins"
## Eingebaute Skins (tools/gen_mania_skins.py) liegen unter res://assets_game/skins/<Name>/.
## Export: die PNGs gehen als importierte Texturen ins .pck (load() funktioniert dort,
## Image.load_from_file auf res:// nicht); skin.ini ist eine Rohdatei und kommt ueber
## export_presets.cfg include_filter mit. Die Dateiliste steht in der ini ([TETHRA] Files),
## weil ein Verzeichnis-Listing im .pck die Originalnamen nicht verlaesslich liefert.
const BUILTIN_DIR := "res://assets_game/skins"
const BUILTIN_PREFIX := "builtin:"
const BUILTIN_NAMES: Array = ["Balken", "Kreise", "Pfeile"]
const MAX_FILE_BYTES := 64 * 1024 * 1024   ## echte Skins haben bis ~23 MB grosse Hold-Koerper
const MAX_TEX := 8192
const SCREEN_UNITS := 480.0   ## osu-Koordinaten: 480 Einheiten = Bildhoehe
const DEFAULT_COLUMN_WIDTH := 30.0
const DEFAULT_HIT_POSITION := 402.0

var skin_name := ""
var keys := 4
var version := 999.0                ## [General] Version ("latest" = 999; ini ohne Version = 1.0 wie osu!)
var column_width: Array = []        ## pro Spalte, osu-Einheiten (480er Raum)
var column_line_width: Array = []   ## Spaltenlinien (keys+1), Einheiten im 768er Raum (osu!: ohne Faktor 1,6)
var column_spacing: Array = []      ## zwischen Spalte i und i+1
var column_start := 136.0
var has_column_start := false       ## ColumnStart explizit gesetzt -> Buehne ab dort (sonst mittig)
var hit_position := DEFAULT_HIT_POSITION   ## Einheiten von oben
var light_position := 413.0
var score_position := 300.0         ## Judgement-Mitte (Einheiten von oben), lazer-Standard 300
var combo_position := 111.0         ## Kombo-Mitte (Einheiten von oben)
var width_for_note_height := 0.0    ## WidthForNoteHeightScale (0 = schmalste Spalte)
var lighting_n_width: Array = []    ## je Spalte, 0 = Spaltenbreite
var lighting_l_width: Array = []
var colours: Dictionary = {}        ## Spalte (0-basiert) -> Color (nur explizit gesetzte)
var colour_light: Dictionary = {}   ## Spalte -> Color (StageLight, Doku-Standard 55,255,255)
var colour_hold: Variant = null     ## Color oder null
var colour_column_line := Color(1, 1, 1, 1)
var colour_judgement_line := Color(1, 1, 1, 1)
var colour_break := Color(1, 0, 0, 1)
var barline_height := 1.2
var judgement_line := true
var note_body_style := 1            ## 0 gestreckt, 1 gekachelt ab Kopf, 2 gekachelt ab Ende
var keys_under_notes := false
var upside_down := false
var light_fps := 60
var combo_prefix := "score"         ## [Fonts] ComboPrefix
var combo_overlap := 0.0
var has_mania_block := false

var _dir := ""
var _names: Dictionary = {}         ## logischer Schluessel -> Dateiname aus skin.ini ("" = Standard)
var _files: Dictionary = {}         ## lowercase relativer Pfad (ohne .png) -> echter relativer Pfad
var _alts: Dictionary = {}          ## logischer Schluessel -> Array weiterer Dateinamen (Fallback je Element)
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


## Standard-Dateiname-Suffix je Spalte wie osu!stable: symmetrisch gespiegelt,
## links abwechselnd 1,2,1,...; bei ungerader Spaltenzahl die Mitte "S".
## 4K: 1,2,2,1; 5K: 1,2,S,2,1; 6K: 1,2,1,1,2,1; 7K: 1,2,1,S,1,2,1.
static func pattern_name(col: int, count: int) -> String:
	if count % 2 == 1 and col == count / 2:
		return "S"
	var c := col if col < count / 2 else count - 1 - col
	return "1" if c % 2 == 0 else "2"


static func pattern_index(col: int, count: int) -> int:
	return 2 if pattern_name(col, count) == "2" else 1


static func parse(text: String, p_keys: int = 4) -> ManiaSkin:
	var s := ManiaSkin.new()
	s.keys = p_keys
	var sections := parse_ini(text)
	# osu!: ohne skin.ini "latest", mit skin.ini aber ohne Version 1.0 (Doku [General] Version).
	s.version = 999.0 if text.strip_edges().is_empty() else 1.0
	for sec in sections:
		var sn := String(sec.get("_section", ""))
		if sn == "general" and sec.has("version"):
			var v := String(sec["version"]).strip_edges()
			s.version = 999.0 if v.to_lower() == "latest" else (v.to_float() if v.is_valid_float() else 1.0)
		elif sn == "fonts":
			if sec.has("comboprefix"):
				s.combo_prefix = String(sec["comboprefix"]).strip_edges()
			if sec.has("combooverlap"):
				s.combo_overlap = String(sec["combooverlap"]).to_float()
	var m := pick_mania_block(sections, p_keys)
	s.has_mania_block = not m.is_empty()
	# Listen wie osu!: fehlende Eintraege = Standardwert (nicht der letzte Wert),
	# ungueltige Zahl = 0 (lazer LegacyManiaSkinDecoder.parseArrayValue).
	s.column_width = _list(String(m.get("columnwidth", "")), p_keys, DEFAULT_COLUMN_WIDTH)
	for i in p_keys:
		s.column_width[i] = maxf(1.0, float(s.column_width[i]))
	s.column_line_width = _list(String(m.get("columnlinewidth", "")), p_keys + 1, 2.0)
	s.column_spacing = _list(String(m.get("columnspacing", "")), maxi(0, p_keys - 1), 0.0)
	s.lighting_n_width = _list(String(m.get("lightingnwidth", "")), p_keys, 0.0)
	s.lighting_l_width = _list(String(m.get("lightinglwidth", "")), p_keys, 0.0)
	s.has_column_start = m.has("columnstart")
	s.column_start = String(m.get("columnstart", "136")).to_float()
	s.hit_position = clampf(String(m.get("hitposition", str(DEFAULT_HIT_POSITION))).to_float(), 240.0, 480.0)
	s.light_position = String(m.get("lightposition", "413")).to_float()
	s.score_position = String(m.get("scoreposition", "300")).to_float()
	s.combo_position = String(m.get("comboposition", "111")).to_float()
	s.width_for_note_height = maxf(0.0, String(m.get("widthfornoteheightscale", "0")).to_float())
	s.barline_height = String(m.get("barlineheight", "1.2")).to_float()
	s.judgement_line = String(m.get("judgementline", "1")).strip_edges() != "0"
	s.keys_under_notes = String(m.get("keysundernotes", "0")).strip_edges() == "1"
	s.upside_down = String(m.get("upsidedown", "0")).strip_edges() == "1"
	var fps := int(String(m.get("lightframepersecond", "60")).to_float())
	s.light_fps = fps if fps > 0 else 24
	# NoteBodyStyle: gesetzt -> Wert; sonst ab Version 2.5 gekachelt, davor gestreckt (lazer).
	if m.has("notebodystyle"):
		s.note_body_style = clampi(int(String(m["notebodystyle"])), 0, 2)
	else:
		s.note_body_style = 1 if s.version >= 2.5 else 0
	for i in p_keys:
		var col: Variant = _color(String(m.get("colour%d" % (i + 1), "")))
		if col != null:
			s.colours[i] = col
		var cl: Variant = _color(String(m.get("colourlight%d" % (i + 1), "")))
		s.colour_light[i] = cl if cl != null else Color(55.0 / 255.0, 1.0, 1.0)
	s.colour_hold = _color(String(m.get("colourhold", "")))
	for pair in [["colourcolumnline", "colour_column_line"], ["colourjudgementline", "colour_judgement_line"],
			["colourbreak", "colour_break"]]:
		var cc: Variant = _color(String(m.get(pair[0], "")))
		if cc != null:
			s.set(pair[1], cc)
	for i in p_keys:
		var pn := pattern_name(i, p_keys)
		var n := "mania-note" + pn
		var k := "mania-key" + pn
		var base := String(m.get("noteimage%d" % i, n))
		s._names["note_%d" % i] = base
		# H/L/T ohne eigene Zeile: NoteImage + Suffix (eigene Namensfamilie), sonst Standarddatei.
		s._names["head_%d" % i] = String(m.get("noteimage%dh" % i, base + "H"))
		s._names["body_%d" % i] = String(m.get("noteimage%dl" % i, base + "L"))
		s._names["tail_%d" % i] = String(m.get("noteimage%dt" % i, base + "T"))
		s._names["key_%d" % i] = String(m.get("keyimage%d" % i, k))
		s._names["keyd_%d" % i] = String(m.get("keyimage%dd" % i, k + "D"))
		# Zweite Wahl (Standard-Datei der Spalte; Kopf zuletzt die Note selbst).
		s._alts["head_%d" % i] = [n + "H", String(s._names["note_%d" % i]), n]
		s._alts["body_%d" % i] = [n + "L"]
		s._alts["tail_%d" % i] = [n + "T"]
		s._alts["note_%d" % i] = [n]
		s._alts["key_%d" % i] = [k]
		s._alts["keyd_%d" % i] = [k + "D"]
	s._names["stage_left"] = String(m.get("stageleft", "mania-stage-left"))
	s._names["stage_right"] = String(m.get("stageright", "mania-stage-right"))
	s._names["stage_hint"] = String(m.get("stagehint", "mania-stage-hint"))
	s._names["stage_bottom"] = String(m.get("stagebottom", "mania-stage-bottom"))
	s._names["stage_light"] = String(m.get("stagelight", "mania-stage-light"))
	s._names["lighting_n"] = String(m.get("lightingn", "lightingN"))
	s._names["lighting_l"] = String(m.get("lightingl", "lightingL"))
	for h in HIT_NAMES:
		s._names[h] = String(m.get(h, "mania-" + h))
	return s


## Judgement-Bilder, Index = ManiaCore.Quality (MAX, PERFECT, GOOD, OK, MEH, MISS)
## -> Hit300g, Hit300, Hit200, Hit100, Hit50, Hit0 (lazer ManiaLegacySkinTransformer).
const HIT_NAMES: Array = ["hit300g", "hit300", "hit200", "hit100", "hit50", "hit0"]
## Elemente, die osu! als Animation laedt (erst name-0, dann name; lazer GetAnimation).
## Tasten, Buehnenraender und StageHint sind einfache Texturen (GetTexture).
const ANIMATED_PREFIXES: Array = ["note_", "head_", "body_", "tail_", "hit", "stage_light",
		"stage_bottom", "lighting_"]


static func _list(v: String, n: int, def: float) -> Array:
	var out: Array = []
	out.resize(n)
	out.fill(def)
	if v.strip_edges().is_empty():
		return out
	var parts := v.split(",")
	for i in mini(parts.size(), n):
		var t := parts[i].strip_edges()
		out[i] = t.to_float() if t.is_valid_float() else 0.0
	return out


## Bezugsbreite fuer die Notenhoehe (Einheiten): WidthForNoteHeightScale oder schmalste Spalte.
func note_height_units() -> float:
	if width_for_note_height > 0.0:
		return width_for_note_height
	var mn := INF
	for w in column_width:
		mn = minf(mn, float(w))
	return mn if mn < INF else DEFAULT_COLUMN_WIDTH


## Hat der Skin eigene Judgement-Bilder? (Dann zeigt Playfield2D sie statt der Text-Anzeige.)
func has_judgement_images() -> bool:
	for h in HIT_NAMES:
		if tex(h) != null:
			return true
	return false


static func _animated(key: String) -> bool:
	for p in ANIMATED_PREFIXES:
		if key.begins_with(p):
			return true
	return false


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
	_src_h_pending = 0
	if not _dir.is_empty() and _names.has(key):
		var anim := _animated(key)
		t = _load_image(String(_names[key]), anim)
		for alt in _alts.get(key, []):
			if t != null:
				break
			t = _load_image(String(alt), anim)
	_at2x[key] = t != null and _at2x_pending
	_src_h[key] = float(_src_h_pending) if t != null and _src_h_pending > 0 else (float(t.get_height()) if t != null else 0.0)
	if t == null and _uses_fallback(key):
		# osu! nimmt fuer fehlende Noten-/Tastenbilder den Standard-Skin (BubbleSkinHappyEdit
		# hat gar keine Notenbilder): hier der eingebaute "Balken"-Skin, Muster 1/2 je Spalte.
		var fb := _fallback_skin()
		if fb != null:
			var fkey := _fb_key(key)
			t = fb.tex(fkey)
			_at2x[key] = fb._at2x.get(fkey, false)
			_src_h[key] = fb.tex_src_h(fkey)
	_tex[key] = t
	return t


## Rundes Bild (Ball): etwa quadratisch, Mitte deckend, Ecken durchsichtig. Playfield2D
## laesst solche Hold-Enden weg (Nutzerwunsch: kein Ball am Hold-Ende). Deckende
## Quadrate (Unknown: schwarzes noteT) sind kein Ball und bleiben wie in osu! sichtbar.
func is_round(key: String) -> bool:
	if _round.has(key):
		return _round[key]
	var t := tex(key)
	var r := false
	if t != null:
		r = image_is_round(t.get_image())
	_round[key] = r
	return r

var _round: Dictionary = {}


static func image_is_round(img: Image) -> bool:
	if img == null or img.is_empty():
		return false
	var w := img.get_width()
	var h := img.get_height()
	if float(h) < float(w) * 0.6 or float(w) < float(h) * 0.6:
		return false
	if img.get_pixel(w / 2, h / 2).a < 0.5:
		return false
	var ix := maxi(0, int(w * 0.08))
	var iy := maxi(0, int(h * 0.08))
	for p in [Vector2i(ix, iy), Vector2i(w - 1 - ix, iy), Vector2i(ix, h - 1 - iy), Vector2i(w - 1 - ix, h - 1 - iy)]:
		if img.get_pixelv(p).a > 0.1:
			return false
	return true


const FALLBACK_SKIN := "Balken"
const FALLBACK_PREFIXES: Array = ["note_", "head_", "body_", "tail_", "key_", "keyd_"]
static var _fb_skin: ManiaSkin = null


func _uses_fallback(key: String) -> bool:
	if _dir.is_empty() or _dir.begins_with("res://"):
		return false
	# Ende nur, wenn die Spalte gar keine eigene Note hat (sonst bleibt es wie in osu! leer).
	if key.begins_with("tail_"):
		var nk := "note_" + key.trim_prefix("tail_")
		return tex(nk) != null and _fallback_skin() != null 				and tex(nk) == _fallback_skin().tex(_fb_key(nk))
	for p in FALLBACK_PREFIXES:
		if key.begins_with(p):
			return true
	return false


func _fb_key(key: String) -> String:
	var under := key.rfind("_")
	var col := int(key.substr(under + 1))
	return key.substr(0, under + 1) + ("0" if pattern_name(col, keys) == "1" else "1")


static func _fallback_skin() -> ManiaSkin:
	if _fb_skin == null:
		_fb_skin = _load_builtin(BUILTIN_PREFIX + FALLBACK_SKIN)
	return _fb_skin


## Originalhoehe der Bilddatei in Pixeln (vor dem Abschneiden auf MAX_TEX).
func tex_src_h(key: String) -> float:
	if tex(key) == null:
		return 0.0
	return float(_src_h.get(key, tex(key).get_height()))

var _src_h: Dictionary = {}


## @2x-Datei? Dann gelten alle Pixelmasse halbiert.
func tex_scale(key: String) -> float:
	return 0.5 if _at2x.get(key, false) else 1.0

var _at2x: Dictionary = {}


## Pfad aus der ini -> echter relativer Pfad im Skin-Ordner ("" = nicht da).
## animated: wie osu! (GetAnimation) zuerst das Frame name-0, dann name; sonst umgekehrt
## nur name (Frames als letzte Rettung). Je Datei @2x vor SD.
func resolve(ini_path: String, animated: bool = false) -> Array:
	var p := ini_path.strip_edges().replace("\\", "/").to_lower()
	while p.begins_with("./"):
		p = p.substr(2)
	if p.ends_with(".png"):
		p = p.substr(0, p.length() - 4)
	if p.is_empty() or p.contains(".."):
		return ["", false]
	var order: Array = [p + "-0", p] if animated else [p, p + "-0"]
	for q in order:
		if _files.has(q + "@2x"):
			return [_files[q + "@2x"], true]
		if _files.has(q):
			return [_files[q], false]
	return ["", false]


## Bild unter beliebigem ini-Namen (z. B. Kombo-Ziffern "score-3"): [Texture2D|null, @2x].
func tex_named(ini_path: String) -> Array:
	var ck := "#" + ini_path.to_lower()
	if not _tex.has(ck):
		_at2x_pending = false
		var t := _load_image(ini_path) if not _dir.is_empty() else null
		_tex[ck] = t
		_at2x[ck] = t != null and _at2x_pending
	return [_tex[ck], bool(_at2x.get(ck, false))]


func _load_image(ini_path: String, animated: bool = false) -> Texture2D:
	var r := resolve(ini_path, animated)
	var rel := String(r[0])
	if rel.is_empty():
		return null
	if _dir.begins_with("res://"):
		var path := _dir + "/" + rel
		if not ResourceLoader.exists(path):
			return null
		_at2x_pending = bool(r[1])
		return load(path) as Texture2D
	var f := FileAccess.open(_dir + "/" + rel, FileAccess.READ)
	if f == null or f.get_length() > MAX_FILE_BYTES or f.get_length() <= 0:
		return null
	var res := decode_image(f.get_buffer(f.get_length()))
	var img: Image = res[0]
	if img == null:
		return null
	_src_h_pending = int(res[1])
	_at2x_pending = bool(r[1])
	return ImageTexture.create_from_image(img)

var _at2x_pending := false
var _src_h_pending := 0


## Bilddaten -> [Image|null, Originalhoehe]. osu! (GDI+) laedt auch Dateien, die nur
## .png heissen, aber TIFF/JPEG/BMP sind (tekkito2: holdbody.png ist ein TIFF) -
## daher nach Signatur statt Endung. Bilder hoeher als MAX_TEX werden oben
## abgeschnitten (osu! zeigt bei Hold-Koerpern ohnehin nur den oberen Ausschnitt).
static func decode_image(buf: PackedByteArray) -> Array:
	if buf.size() < 8:
		return [null, 0]
	var img: Image = null
	var src_h := 0
	var b0 := buf[0]
	var b1 := buf[1]
	if (b0 == 0x49 and b1 == 0x49) or (b0 == 0x4D and b1 == 0x4D):
		var t := _decode_tiff(buf)
		img = t[0]
		src_h = int(t[1])
	else:
		img = Image.new()
		var err := ERR_FILE_UNRECOGNIZED
		if b0 == 0x89 and b1 == 0x50:
			err = img.load_png_from_buffer(buf)
		elif b0 == 0xFF and b1 == 0xD8:
			err = img.load_jpg_from_buffer(buf)
		elif b0 == 0x42 and b1 == 0x4D:
			err = img.load_bmp_from_buffer(buf)
		elif b0 == 0x52 and b1 == 0x49:
			err = img.load_webp_from_buffer(buf)
		if err != OK or img.is_empty():
			return [null, 0]
		src_h = img.get_height()
	if img == null or img.get_width() < 1 or img.get_height() < 1 or img.get_width() > MAX_TEX:
		return [null, 0]
	if img.get_height() > MAX_TEX:
		img = img.get_region(Rect2i(0, 0, img.get_width(), MAX_TEX))
	return [img, src_h]


## Minimaler TIFF-Leser: unkomprimiert, 8 Bit, RGB/RGBA/Grau, Streifen (chunky).
## Liest nur die obersten MAX_TEX Zeilen. [Image|null, Originalhoehe].
static func _decode_tiff(buf: PackedByteArray) -> Array:
	var be := buf[0] == 0x4D
	var rd := func(off: int, n: int) -> int:
		if off < 0 or off + n > buf.size():
			return -1
		var v := 0
		for i in n:
			v = (v << 8) | int(buf[off + (i if be else n - 1 - i)])
		return v
	var ifd: int = rd.call(4, 4)
	var cnt: int = rd.call(ifd, 2)
	if ifd < 8 or cnt <= 0:
		return [null, 0]
	var tags: Dictionary = {}
	for i in cnt:
		var e := ifd + 2 + i * 12
		var tag: int = rd.call(e, 2)
		if not tag in [256, 257, 258, 259, 273, 277, 278, 284]:
			continue
		var typ: int = rd.call(e + 2, 2)
		var n: int = rd.call(e + 4, 4)
		var sz := 2 if typ == 3 else 4
		if typ == 1:
			sz = 1
		var off := e + 8 if n * sz <= 4 else int(rd.call(e + 8, 4))
		var vals: Array = []
		for k in mini(n, 65536):
			vals.append(rd.call(off + k * sz, sz))
		tags[tag] = vals
	var w := int(tags.get(256, [0])[0])
	var h := int(tags.get(257, [0])[0])
	var spp := int(tags.get(277, [1])[0])
	var bps := int(tags.get(258, [8])[0])
	if int(tags.get(259, [1])[0]) != 1 or bps != 8 or int(tags.get(284, [1])[0]) != 1:
		return [null, 0]
	if w < 1 or h < 1 or w > MAX_TEX or not spp in [1, 2, 3, 4]:
		return [null, 0]
	var offs: Array = tags.get(273, [])
	var rps := int(tags.get(278, [h])[0])
	var rows := mini(h, MAX_TEX)
	var row_b := w * spp
	var data := PackedByteArray()
	var y := 0
	for so in offs:
		if y >= rows:
			break
		var n_rows := mini(rps, rows - y)
		var start := int(so)
		if start < 0 or start + n_rows * row_b > buf.size():
			return [null, 0]
		data.append_array(buf.slice(start, start + n_rows * row_b))
		y += n_rows
	if y < rows:
		return [null, 0]
	# Graustufen/RGB auf RGBA. Assoziiertes Alpha (ExtraSamples 1) bleibt wie es ist:
	# bei fast deckenden Pixeln (typisch Hold-Koerper) ist der Farbfehler unsichtbar,
	# eine Schleife ueber Millionen Pixel in GDScript waere es nicht.
	var fmt := Image.FORMAT_RGBA8
	if spp == 3:
		fmt = Image.FORMAT_RGB8
	elif spp == 1:
		fmt = Image.FORMAT_L8
	elif spp == 2:
		fmt = Image.FORMAT_LA8
	var img := Image.create_from_data(w, rows, false, fmt, data)
	if fmt != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return [img, h]


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


static func is_builtin(id: String) -> bool:
	return id.begins_with(BUILTIN_PREFIX) and BUILTIN_NAMES.has(id.trim_prefix(BUILTIN_PREFIX))


## Datei im Skin-Ordner mit dem Originalnamen (Dateiname der .osk/.zip bzw. Ordnername).
const NAME_FILE := "tethra_name.txt"


## Anzeige-Name: "builtin:Balken" -> "Balken"; importierte Skins mit Originalnamen
## (tethra_name.txt vom Import, sonst skin.ini [General] Name, sonst Ordnername).
static func display_name(id: String, root: String = SKINS_DIR) -> String:
	if is_builtin(id):
		return id.trim_prefix(BUILTIN_PREFIX)
	if id.is_empty() or id != safe_name(id):
		return id
	var dir := root + "/" + id
	var f := FileAccess.open(dir + "/" + NAME_FILE, FileAccess.READ)
	if f != null and f.get_length() <= 4096:
		var n := f.get_as_text().strip_edges()
		if not n.is_empty():
			return n
	f = FileAccess.open(dir + "/skin.ini", FileAccess.READ)
	if f != null and f.get_length() <= MAX_FILE_BYTES:
		for sec in parse_ini(f.get_as_text()):
			if String(sec.get("_section", "")) == "general":
				var gn := String(sec.get("name", "")).strip_edges()
				if not gn.is_empty():
					return gn
	return id


## IDs: eingebaute ("builtin:Balken", ...) zuerst, dann importierte Ordnernamen.
static func list_skins() -> PackedStringArray:
	var out := PackedStringArray()
	for n in BUILTIN_NAMES:
		out.append(BUILTIN_PREFIX + String(n))
	var d := DirAccess.open(SKINS_DIR)
	if d == null:
		return out
	var own := d.get_directories()
	own.sort()
	out.append_array(own)
	return out


static func delete_skin(p_name: String) -> bool:
	if is_builtin(p_name):
		return false
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


static func _load_builtin(p_name: String) -> ManiaSkin:
	var dir := BUILTIN_DIR + "/" + p_name.trim_prefix(BUILTIN_PREFIX)
	var f := FileAccess.open(dir + "/skin.ini", FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	var s := parse(text, 4)
	s.skin_name = p_name
	s._dir = dir
	for sec in parse_ini(text):
		if String(sec.get("_section", "")).to_lower() == "tethra":
			for fn in String(sec.get("files", "")).split(",", false):
				s._files[fn.strip_edges().to_lower() + "@2x"] = fn.strip_edges() + "@2x.png"
	return s


static func load_skin(p_name: String, root: String = SKINS_DIR) -> ManiaSkin:
	if is_builtin(p_name):
		return _load_builtin(p_name)
	if p_name.is_empty() or p_name != safe_name(p_name):
		return null
	var dir := root + "/" + p_name
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
## Grund des letzten fehlgeschlagenen import_skin() (fuer die Anzeige).
static var last_error := ""


## Installierte osu!stable-Skins mit Mania-Grafiken (%LOCALAPPDATA%/osu!/Skins):
## [{name, path}], alphabetisch. Fuer "Aus osu! übernehmen" mit einem Klick.
static func osu_skins() -> Array:
	var out: Array = []
	var root := OS.get_environment("LOCALAPPDATA").replace("\\", "/").path_join("osu!/Skins")
	var d := DirAccess.open(root)
	if d == null:
		return out
	for sub in d.get_directories():
		var sd := DirAccess.open(root.path_join(sub))
		if sd == null:
			continue
		for f in sd.get_files():
			if f.to_lower().begins_with("mania-") and f.to_lower().ends_with(".png"):
				out.append({"name": sub.strip_edges(), "path": root.path_join(sub)})
				break
	out.sort_custom(func(a, b): return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return out


static func import_skin(path: String, root: String = SKINS_DIR) -> String:
	last_error = ""
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
			last_error = "Datei ist kein gültiges .osk/.zip"
			return ""
		for fn in zr.get_files():
			if not String(fn).ends_with("/"):
				entries[String(fn).replace("\\", "/")] = fn
	else:
		last_error = "Datei nicht gefunden"
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
	# Alle Bild-Schluessel wie lazer LegacyManiaSkinDecoder (NoteImage*, KeyImage*, Hit*,
	# Stage*, Lighting*), dazu die Kombo-Ziffern ([Fonts] ComboPrefix, Standard "score").
	var wanted: Dictionary = {}
	var combo_pre := "score"
	for sec in parse_ini(ini_text):
		if String(sec.get("_section", "")) == "fonts" and sec.has("comboprefix"):
			combo_pre = String(sec["comboprefix"]).strip_edges().replace("\\", "/").to_lower()
		if String(sec.get("_section", "")) != "mania":
			continue
		for k in sec:
			var ks := String(k)
			if ks.begins_with("noteimage") or ks.begins_with("keyimage") or ks.begins_with("stage") \
					or ks.begins_with("hit") or ks.begins_with("lighting") and not ks.ends_with("width"):
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
		var frame := plain
		var dash := frame.rfind("-")
		if dash > 0 and frame.substr(dash + 1).is_valid_int():
			frame = frame.substr(0, dash)   # Animations-Frame name-3 -> name
		var fn := low.get_file()
		var is_digit := plain.begins_with(combo_pre + "-") and plain.substr(combo_pre.length() + 1).is_valid_int()
		if fn.begins_with("mania-") or (low.count("/") == 0 and fn.begins_with("lighting")) or is_digit \
				or wanted.has(stem) or wanted.has(plain) or wanted.has(frame):
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
		last_error = "Kein Mania-Skin (keine mania-Grafiken enthalten)"
		return ""
	var nm := safe_name(base_name)
	var dest := root + "/" + nm
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
	# Originalname fuer die Auswahl merken (Ordner-ID bleibt der bereinigte Name).
	var nf := FileAccess.open(dest + "/" + NAME_FILE, FileAccess.WRITE)
	if nf != null:
		nf.store_string(base_name.strip_edges())
		nf.close()
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


## Skin-Ordner unter einem frei waehlbaren Wurzelordner loeschen (Tests).
static func delete_skin_in(root: String, p_name: String) -> void:
	if p_name == safe_name(p_name):
		_remove_tree(root + "/" + p_name)
