class_name WorldTheme
extends RefCounted

## Welt-Thema pro Map: waehlt den Himmel/Farbsatz nach Song-Charakter.
##   boss   Bosskampf: hohe Intensitaet (Sterne >= 4.5 oder >= 190 BPM dicht/kiai-lastig)
##   neon   elektronisch/schnell (140-190 BPM, mittlere-hohe Dichte, Magenta/Cyan
##          oder edm/electro/synth/hardcore/dubstep/trance in Titel/Tags)
##   aurora ruhig (< 120 BPM oder niedrige Dichte, weiche/blaue Coverfarbe)
##   galaxy sonst (Standard-Weltraum mit Kapitel-Paletten)
## Rein statisch, keine Szene noetig -> headless testbar (tests/run_world_theme_tests.gd).

const GALAXY := "galaxy"
const BOSS := "boss"
const AURORA := "aurora"
const NEON := "neon"
const ECLIPSE := "eclipse"
const ABYSS := "abyss"
const FRACTAL := "fractal"
const SINGULARITY := "singularity"
const STORM := "storm"
const OBSIDIAN := "obsidian"
const MONOLITH := "monolith"
const RIFT := "rift"
const NERVE := "nerve"
const NAMES: Array[String] = [GALAXY, BOSS, AURORA, NEON, ECLIPSE, ABYSS, FRACTAL, SINGULARITY, STORM, OBSIDIAN, MONOLITH, RIFT, NERVE]
## Dunkle Welten in Rueckfall-Reihenfolge (fehlt eine, nimmt resolve die naechste).
const DARK: Array[String] = [BOSS, ECLIPSE, ABYSS, FRACTAL, OBSIDIAN, STORM, SINGULARITY, MONOLITH, RIFT, NERVE, AURORA]
## Welten fuer die gleichmaessige Verteilung (ohne Boss/Frost, die nach Charakter kommen).
const VARIETY: Array[String] = [ECLIPSE, ABYSS, FRACTAL, OBSIDIAN, STORM, SINGULARITY, MONOLITH, RIFT, NERVE]
## Anzeige-Namen (Einstellungen).
const LABELS := {"galaxy": "Galaxie", "boss": "Bosskampf", "aurora": "Frost", "neon": "Neon",
	"eclipse": "Eklipse", "abyss": "Abgrund", "fractal": "Fraktal", "singularity": "Singularität",
	"storm": "Sturm", "obsidian": "Obsidian", "monolith": "Monolith", "rift": "Riss",
	"nerve": "Nerv"}
## Galaxie (mit Planeten) nur noch extrem selten (Nutzer-Wunsch).
const GALAXY_SHARE := 0.03

## Schwellen (Noten pro Sekunde ueber die Spielzeit, Mania-typisch).
const BOSS_STARS := 5.3
const BOSS_BPM := 205.0
const DENSE_NPS := 8.0
const NEON_BPM_MIN := 140.0
const NEON_NPS := 4.5
const CALM_BPM := 120.0
const CALM_NPS := 3.0
const KIAI_HEAVY := 0.3

## Schluesselwoerter fuer Neon (Token-Anfang: "electronic", "synthwave" passen).
const ELECTRO_WORDS: Array[String] = ["edm", "electro", "synth", "hardcore",
		"dubstep", "trance", "techno", "dnb", "drumandbass", "hardstyle", "cyber"]
## Exakte Tokens (zu kurz fuer Praefix-Suche).
const ELECTRO_EXACT: Array[String] = ["edm", "dnb", "idm", "eurobeat"]

## Farbsatz je Thema: line = Strecke/Pads (Songfarbe), kiai = Akzent im Kiai.
## Galaxie behaelt die Coverfarbe (leeres Dict).
const PALETTES := {
	"boss": {"line": Color(0.78, 0.08, 0.10), "kiai": Color(1.0, 0.30, 0.26),
		"note": Color(1.0, 0.30, 0.18), "hold": Color(1.0, 0.52, 0.14)},
	"aurora": {"line": Color(0.46, 0.72, 0.80), "kiai": Color(0.70, 0.88, 0.92),
		"note": Color(0.62, 0.90, 1.0), "hold": Color(0.42, 0.76, 0.96)},
	"eclipse": {"line": Color(0.86, 0.76, 0.52), "kiai": Color(1.0, 0.94, 0.78),
		"note": Color(1.0, 0.84, 0.48), "hold": Color(1.0, 0.64, 0.28)},
	"abyss": {"line": Color(0.52, 0.60, 0.70), "kiai": Color(0.80, 0.86, 0.94),
		"note": Color(0.46, 0.76, 0.92), "hold": Color(0.30, 0.60, 0.82)},
	"fractal": {"line": Color(0.66, 0.12, 0.22), "kiai": Color(0.92, 0.36, 0.44),
		"note": Color(1.0, 0.32, 0.44), "hold": Color(0.88, 0.14, 0.30)},
	"singularity": {"line": Color(0.80, 0.82, 0.86), "kiai": Color(1.0, 0.96, 0.90),
		"note": Color(1.0, 0.92, 0.78), "hold": Color(1.0, 0.72, 0.38)},
	"storm": {"line": Color(0.52, 0.48, 0.66), "kiai": Color(0.78, 0.74, 0.92),
		"note": Color(0.76, 0.72, 1.0), "hold": Color(0.54, 0.56, 0.96)},
	"obsidian": {"line": Color(0.40, 0.56, 0.72), "kiai": Color(0.66, 0.80, 0.94),
		"note": Color(0.52, 0.78, 1.0), "hold": Color(0.34, 0.60, 0.92)},
	"monolith": {"line": Color(0.70, 0.72, 0.76), "kiai": Color(0.90, 0.92, 0.95),
		"note": Color(0.84, 0.91, 1.0), "hold": Color(0.76, 0.84, 0.96)},
	"rift": {"line": Color(0.56, 0.64, 0.56), "kiai": Color(0.76, 0.84, 0.74),
		"note": Color(0.72, 0.94, 0.74), "hold": Color(0.46, 0.80, 0.54)},
	"nerve": {"line": Color(0.42, 0.08, 0.16), "kiai": Color(0.70, 0.22, 0.32),
		"note": Color(0.94, 0.26, 0.40), "hold": Color(0.74, 0.12, 0.28)},
	"neon": {"line": Color("#ff2bd6"), "kiai": Color("#19f0ff")},
}


## Snap-Staffelung in Weltfarbe: Teiler -> [Farbton-Versatz, Saettigung x, Helligkeit x].
## Farbton bleibt (fast) der der Welt; Unterscheidung ueber Helligkeit/Saettigung.
const SNAP_STYLE := {
	1: [0.0, 0.30, 1.00],
	2: [0.0, 1.00, 0.94],
	3: [0.05, 0.90, 0.74],
	4: [-0.03, 0.78, 0.84],
	6: [0.07, 0.70, 0.64],
	8: [-0.06, 1.00, 0.70],
	12: [0.03, 0.55, 0.78],
	16: [0.0, 0.45, 0.58],
}
const SNAP_V_MIN := 0.50
const SNAP_V_MAX := 0.98


## Hat die Welt einen eigenen Noten-Stil (Galaxie/Neon: nein)?
static func has_note_style(theme: String) -> bool:
	return PALETTES.get(theme, {}).has("note")


## Notenfarbe der Welt (Galaxie/Neon: leer = unveraendert).
static func note_color(theme: String, hold: bool) -> Color:
	var pal: Dictionary = PALETTES.get(theme, {})
	return pal.get("hold" if hold else "note", Color(0, 0, 0, 0))


## Snap-Teiler -> Farbe im Farbsatz der Welt (Helligkeit/Saettigung gestaffelt).
static func snap_style(divisor: int, note: Color) -> Color:
	var st: Array = SNAP_STYLE.get(divisor, SNAP_STYLE[16])
	var v := clampf(maxf(note.v, 0.85) * float(st[2]), SNAP_V_MIN, SNAP_V_MAX)
	return Color.from_hsv(fposmod(note.h + float(st[0]), 1.0),
			clampf(note.s * float(st[1]), 0.0, 0.9), v)


## Asynchron vorladen (Hauptthread bleibt frei): Panorama + Ebenen der Welt.
## Beim Kartenwechsel/Ladebild aufrufen; get_cached() holt sie spaeter ohne Hitch.
static func prefetch(theme: String) -> void:
	if theme == GALAXY or theme == "":
		return
	var dir := asset_dir(theme)
	if not DirAccess.dir_exists_absolute(dir):
		return
	for fname in ResourceLoader.list_directory(dir):
		if fname.get_extension().to_lower() in ["webp", "png", "jpg", "exr", "hdr"]:
			var path := dir.path_join(fname)
			if ResourceLoader.exists(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				AsyncLoad.request(path)


## Resource holen: war sie vorgeladen, wartet das nur auf den Rest.
static func get_cached(path: String) -> Resource:
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return AsyncLoad.fetch(path)
	return load(path)


## Thema fuer die Map. stars < 0 = unbekannt (wird ignoriert).
static func pick(beatmap: Beatmap, stars: float, theme_color: Color) -> String:
	if beatmap == null or beatmap.hit_objects.is_empty():
		return GALAXY
	return pick_from(features(beatmap), stars, theme_color)


## Gewaehltes Thema: forced ("galaxy"/...) gewinnt, "" = automatisch.
static func resolve(forced: String, beatmap: Beatmap, stars: float, theme_color: Color) -> String:
	if NAMES.has(forced):
		return forced
	if beatmap == null:
		return GALAXY
	var t := pick(beatmap, stars, theme_color)
	if t == GALAXY or is_available(t):
		return t
	# Gewaehlte Welt fehlt noch (Assets nicht da): NICHT immer auf dieselbe
	# zurueckfallen, sondern gleichmaessig per Hash ueber alle vorhandenen.
	var avail: Array[String] = []
	for d in VARIETY:
		if is_available(d):
			avail.append(d)
	if avail.is_empty():
		return GALAXY
	var f := features(beatmap)
	return avail[mini(int(_h(f, stars, 13) * avail.size()), avail.size() - 1)]


## Hat das Thema Shader + Assets (spaeter gemergte Welten erscheinen so automatisch)?
static func is_available(theme: String) -> bool:
	var sp := shader_path(theme)
	if sp == "" or not ResourceLoader.exists(sp):
		return false
	var dir := asset_dir(theme)
	if not DirAccess.dir_exists_absolute(dir):
		return false
	for fname in ResourceLoader.list_directory(dir):
		if fname.get_extension().to_lower() in ["webp", "png", "jpg"]:
			return true
	return false


## Deterministischer Wert 0..1 pro Map (gleiche Map = gleiche Welt).
static func _h(f: Dictionary, stars: float, salt: int) -> float:
	var key := "%.2f|%.3f|%.3f|%.2f|%d" % [float(f.get("bpm", 0.0)), float(f.get("nps", 0.0)),
		float(f.get("kiai", 0.0)), stars, salt]
	return float(absi(hash(key)) % 10000) / 10000.0


## Kennzahlen der Map: bpm (dominant, nach Dauer), nps, kiai (Anteil 0..1), electro.
static func features(beatmap: Beatmap) -> Dictionary:
	var f := {"bpm": 0.0, "nps": 0.0, "kiai": 0.0, "electro": false}
	if beatmap == null:
		return f
	var n := beatmap.hit_objects.size()
	var t0 := 0.0
	var t1 := 0.0
	if n > 0:
		t0 = beatmap.hit_objects[0].time
		t1 = maxf(beatmap.duration_ms(), beatmap.hit_objects[n - 1].time)
	var span := t1 - t0
	if span > 1000.0:
		f.nps = float(n) / (span / 1000.0)
		var kiai_ms := 0.0
		for iv in beatmap.kiai_intervals:
			kiai_ms += maxf(0.0, minf(float(iv.end), t1) - maxf(float(iv.start), t0))
		f.kiai = clampf(kiai_ms / span, 0.0, 1.0)
	f.bpm = dominant_bpm(beatmap.timing_points, t0, t1)
	var text := "%s %s %s %s %s %s" % [beatmap.title(), beatmap.artist(),
			str(beatmap.metadata.get("TitleUnicode", "")),
			str(beatmap.metadata.get("Tags", "")),
			str(beatmap.metadata.get("Source", "")), beatmap.version_name()]
	f.electro = has_electro_word(text)
	return f


## BPM, das am laengsten gilt (rote Linien, [t0, t1]). 0 = keine Timing-Linie.
static func dominant_bpm(tps: Array, t0: float, t1: float) -> float:
	var reds: Array = []
	for tp in tps:
		if tp.uninherited and tp.beat_length > 0.0:
			reds.append(tp)
	if reds.is_empty():
		return 0.0
	if reds.size() == 1 or t1 <= t0:
		return reds[0].bpm()
	var dur := {}
	for i in reds.size():
		var a := maxf(float(reds[i].time), t0) if i > 0 else t0
		var b := t1 if i == reds.size() - 1 else minf(float(reds[i + 1].time), t1)
		if b <= a:
			continue
		var key := snappedf(reds[i].bpm(), 0.5)
		dur[key] = float(dur.get(key, 0.0)) + (b - a)
	var best := float(reds[0].bpm())
	var best_d := -1.0
	for k in dur:
		if float(dur[k]) > best_d:
			best_d = float(dur[k])
			best = float(k)
	return best


static func has_electro_word(text: String) -> bool:
	var norm := text.to_lower().replace("&", "and")
	# Tokens: alles ausser a-z/0-9 trennt ("drum & bass" -> "drumandbass" extra).
	var tokens: Array[String] = []
	var cur := ""
	for ch in norm:
		var c := ch.unicode_at(0)
		if (c >= 97 and c <= 122) or (c >= 48 and c <= 57):
			cur += ch
		elif cur != "":
			tokens.append(cur)
			cur = ""
	if cur != "":
		tokens.append(cur)
	for i in tokens.size():
		var tk: String = tokens[i]
		if ELECTRO_EXACT.has(tk):
			return true
		if i + 2 < tokens.size() and tk == "drum" and tokens[i + 1] == "and" and tokens[i + 2] == "bass":
			return true
		for w in ELECTRO_WORDS:
			if w.length() >= 5 and tk.begins_with(w):
				return true
	return false


## Coverfarbe Magenta/Pink oder Cyan (gesaettigt).
static func is_neon_color(c: Color) -> bool:
	if c.s < 0.4:
		return false
	var h := c.h
	return (h >= 0.78 and h <= 0.97) or (h >= 0.46 and h <= 0.54)


## Coverfarbe weich (blass) oder kuehl (Blau/Tuerkis/Gruen-Blau).
static func is_soft_color(c: Color) -> bool:
	if c.s < 0.35 or c.v < 0.25:
		return true
	return c.h >= 0.42 and c.h <= 0.72


## Entscheidung aus den Kennzahlen (reine Funktion, testbar).
static func pick_from(f: Dictionary, stars: float, theme_color: Color) -> String:
	var bpm := float(f.get("bpm", 0.0))
	var nps := float(f.get("nps", 0.0))
	var kiai := float(f.get("kiai", 0.0))
	var electro := bool(f.get("electro", false))
	# Bosskampf: sehr schwer oder sehr schnell + dicht (bzw. schnell + kiai-lastig).
	if stars >= BOSS_STARS:
		return BOSS
	if bpm >= BOSS_BPM and (nps >= DENSE_NPS or (nps >= NEON_NPS and kiai >= KIAI_HEAVY)):
		return BOSS
	# Neon wird NIE automatisch gewaehlt (Nutzer: duestere Welten, kein Neon).
	# Galaxie nur extrem selten.
	if _h(f, stars, 7) < GALAXY_SHARE:
		return GALAXY
	# Frost: ruhig und weiche/kuehle Coverfarbe; sehr ruhig auch ohne Farbe.
	var calm := (bpm > 0.0 and bpm < CALM_BPM) or (nps > 0.0 and nps < CALM_NPS)
	var very_calm := (bpm > 0.0 and bpm < 100.0 and nps < 4.0) or (nps > 0.0 and nps < 2.0)
	if calm and (is_soft_color(theme_color) or very_calm):
		return AURORA
	# Sonst gleichmaessig eine der dunklen Welten (per Hash fest pro Map),
	# damit keine Welt viel oefter kommt als die anderen.
	var avail: Array[String] = []
	for d in VARIETY:
		if is_available(d):
			avail.append(d)
	if avail.is_empty():
		avail = VARIETY
	return avail[mini(int(_h(f, stars, 13) * avail.size()), avail.size() - 1)]


## Farbsatz {line, kiai} oder {} (Galaxie: Coverfarbe bleibt).
static func palette(theme: String) -> Dictionary:
	return PALETTES.get(theme, {})


## Shader-Pfad des Themas ("" = Galaxie / sky_panorama).
static func shader_path(theme: String) -> String:
	if theme == GALAXY or not NAMES.has(theme):
		return ""
	return "res://shaders/theme_%s.gdshader" % theme


static func asset_dir(theme: String) -> String:
	return "res://assets_game/themes/%s" % theme


# ---------------------------------------------------------------- Beat-Vertrag
# docs/worlds/beat_contract.md: statische Huellkurven (headless testbar).

const DROP_PEAK := 0.6
const DROP_HOLD := 0.3
const DROP_MAX := 0.6
const DROP_RISE_BEATS := 1.0
const DROP_FALL_BEATS := 4.0
const DROP_END_BEATS := 2.0


## Drop-Huellkurve. since_start: Beats seit Kiai-Start (<0 = kein Kiai gewesen),
## since_end: Beats seit Kiai-Ende (<0 = Kiai laeuft noch), comfort halbiert.
static func drop_env(since_start: float, since_end: float, comfort: bool) -> float:
	if since_start < 0.0:
		return 0.0
	var up := since_start
	var v: float
	if up < DROP_RISE_BEATS:
		v = DROP_PEAK * smoothstep(0.0, DROP_RISE_BEATS, up)
	elif up < DROP_RISE_BEATS + DROP_FALL_BEATS:
		v = lerpf(DROP_PEAK, DROP_HOLD, smoothstep(0.0, DROP_FALL_BEATS, up - DROP_RISE_BEATS))
	else:
		v = DROP_HOLD
	if since_end >= 0.0:
		v *= 1.0 - smoothstep(0.0, DROP_END_BEATS, since_end)
	if comfort:
		v *= 0.5
	return clampf(v, 0.0, DROP_MAX)


## Monotoner Beat-Zaehler mit Easing: springt auf dem Schlag, ruht bis zum naechsten.
static func beat_step(beats_total: int, beat_phase: float) -> float:
	# Glatt, nie still: Geschwindigkeit 1.25x auf dem Schlag .. 0.75x davor.
	var p := clampf(beat_phase, 0.0, 1.0)
	return float(beats_total) + p + 0.25 * ((1.0 - (1.0 - p) * (1.0 - p)) - p)


## downbeat_pulse: exp(-bar_phase*meter*3), 1 auf dem Takt-Anfang.
static func downbeat_pulse(bar_phase: float, meter: int) -> float:
	return exp(-clampf(bar_phase, 0.0, 1.0) * float(maxi(meter, 1)) * 3.0)
