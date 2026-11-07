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
const NAMES: Array[String] = [GALAXY, BOSS, AURORA, NEON]

## Schwellen (Noten pro Sekunde ueber die Spielzeit, Mania-typisch).
const BOSS_STARS := 4.5
const BOSS_BPM := 190.0
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
	"boss": {"line": Color(0.96, 0.30, 0.10), "kiai": Color(1.0, 0.80, 0.42)},
	"aurora": {"line": Color(0.42, 0.80, 0.98), "kiai": Color(0.45, 0.98, 0.76)},
	"neon": {"line": Color("#ff2bd6"), "kiai": Color("#19f0ff")},
}


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
	return pick(beatmap, stars, theme_color)


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
	# Neon wird NIE automatisch gewaehlt (Nutzer: duestere Welten, kein Neon) —
	# nur noch manuell in den Einstellungen.
	# Aurora: ruhig und weiche/kuehle Coverfarbe; sehr ruhig auch ohne Farbe.
	var calm := (bpm > 0.0 and bpm < CALM_BPM) or (nps > 0.0 and nps < CALM_NPS)
	var very_calm := (bpm > 0.0 and bpm < 100.0 and nps < 4.0) or (nps > 0.0 and nps < 2.0)
	if calm and (is_soft_color(theme_color) or very_calm):
		return AURORA
	return GALAXY


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
