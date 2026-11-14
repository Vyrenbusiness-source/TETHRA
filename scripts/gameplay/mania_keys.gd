class_name ManiaKeys
extends RefCounted

## Mania mit mehr Tasten (Plan Punkt 6): 4K bis 7K aus echten osu!mania-Maps
## (CircleSize = Spaltenzahl). Hier liegt alles, was von der Tastenzahl abhaengt:
## Standard-Belegung wie osu!, Farbmuster der Spalten (Mitte hervorgehoben),
## 3D-Bahnen (Abstand, Notengroesse, Feldbreite), Online-Modus-Schluessel.
## Andere Modi (Orbit, Rally, Dirigent, Trace, Rebound) bleiben 4K-only.

const MIN_KEYS := 4
const MAX_KEYS := 7
const SUPPORTED: Array[int] = [4, 5, 6, 7]

## Standard-Belegung wie osu!mania (4K: D F J K).
const DEFAULTS := {
	4: [KEY_D, KEY_F, KEY_J, KEY_K],
	5: [KEY_D, KEY_F, KEY_SPACE, KEY_J, KEY_K],
	6: [KEY_S, KEY_D, KEY_F, KEY_J, KEY_K, KEY_L],
	7: [KEY_S, KEY_D, KEY_F, KEY_SPACE, KEY_J, KEY_K, KEY_L],
}

## 3D: Abstand der Bahnen (Welt-Einheiten) und Notengroesse je Tastenzahl. 4K ist
## der bisherige Look (RAIL_X_BASE -2.55 .. 2.55, Rand 3.6). Mehr Spalten: Bahnen
## enger, Noten etwas kleiner, Feld breiter; bei 7K bleibt zwischen zwei Noten
## noch ein Spalt von gut einer halben Notenbreite.
const RAIL_GAP := {4: 1.70, 5: 1.55, 6: 1.44, 7: 1.36}
const NOTE_SCALE := {4: 1.0, 5: 0.93, 6: 0.87, 7: 0.82}
## Rand der Strecke ab der aeusseren Bahn (bei 4K: 3.6 - 2.55).
const EDGE_MARGIN := 1.05
const EDGE_X_4K := 3.6

## Mittlere Spalte (ungerade Tastenzahl ab 5K): bernsteinfarben wie die Mitte in osu!.
const CENTER_COLOR := Color("f2b544")
## Innere Spalten ("2" im osu!-Muster) im Farbmodus "auto": ruhiges Hellblau.
const INNER_COLOR := Color("8fb4ff")


static func supported(keys: int) -> bool:
	return SUPPORTED.has(keys)


## Tastenzahl einer Diff aus den Browser-Metadaten (cs gerundet). Nicht-Mania: 0.
static func keys_of_meta(meta: Dictionary) -> int:
	if int(meta.get("mode", 0)) != 3:
		return 0
	return int(round(float(meta.get("cs", 4.0))))


## Standard-Tasten einer Tastenzahl (Kopie).
static func default_keys(keys: int) -> Array[int]:
	var out: Array[int] = []
	for k in DEFAULTS.get(keys, DEFAULTS[4]):
		out.append(int(k))
	return out


## Kurzname im Browser ("7K").
static func label(keys: int) -> String:
	return "%dK" % keys


# ------------------------------------------------------------------ Wertung

## Online-Modus-Schluessel fuer POST /score und GET /leaderboard: 4K bleibt "mania"
## (alte Scores unveraendert), 5K-7K bekommen eigene Ranglisten "mania5k" ... "mania7k".
static func online_mode(keys: int) -> String:
	return "mania" if keys == 4 or not supported(keys) else "mania%dk" % keys


## Ist das ein Mania-Online-Modus (mit pp)? "mania", "mania5k" ... "mania7k".
static func is_mania_online(mode: String) -> bool:
	return mode == "mania" or keys_of_online_mode(mode) > 4


## Tastenzahl eines Online-Modus ("mania7k" -> 7, "mania" -> 4, sonst 0).
static func keys_of_online_mode(mode: String) -> int:
	if mode == "mania":
		return 4
	if mode.begins_with("mania") and mode.ends_with("k"):
		var n := mode.trim_prefix("mania").trim_suffix("k")
		if n.is_valid_int() and supported(int(n)):
			return int(n)
	return 0


## Tastenzahl eines gespeicherten Score-Eintrags (alte Eintraege ohne Feld: 4K).
static func keys_of_entry(e: Dictionary) -> int:
	return int(e.get("keys", 4))


# ------------------------------------------------------------------ Farben

## osu!-Muster der Spalte: "1" (aussen/hell), "2" (innen/blau), "S" (Mitte).
## 4K: 1 2 2 1; 5K: 1 2 S 2 1; 6K: 1 2 1 1 2 1; 7K: 1 2 1 S 1 2 1.
static func pattern(col: int, keys: int) -> String:
	if keys % 2 == 1 and col == keys / 2:
		return "S"
	var c := col if col < keys / 2 else keys - 1 - col
	return "1" if c % 2 == 0 else "2"


static func is_center(col: int, keys: int) -> bool:
	return pattern(col, keys) == "S"


## Spalte -> Index in der 4er-Farbpalette (Notenfarben "Spalten"), -1 = Mitte.
## 4K unveraendert 0..3. Links nutzt die Farben 0/1, rechts gespiegelt 3/2, wie
## osu! hell/blau abwechselnd von aussen nach innen.
static func palette_index(col: int, keys: int) -> int:
	if keys == 4:
		return clampi(col, 0, 3)
	if is_center(col, keys):
		return -1
	var outer := pattern(col, keys) == "1"
	if col < keys / 2:
		return 0 if outer else 1
	return 3 if outer else 2


## Notenfarbe im Modus "auto" (Map-/Weltfarbe) ab 5K: Spalten nach osu!-Muster
## leicht einfaerben (aussen unveraendert, innen hellblau, Mitte bernstein), damit
## man 7 Spalten auf einen Blick trennt. 4K und Holds bleiben unveraendert.
static func auto_tint(c: Color, col: int, keys: int) -> Color:
	if keys <= 4 or not supported(keys):
		return c
	match pattern(col, keys):
		"S": return c.lerp(CENTER_COLOR, 0.6)
		"2": return c.lerp(INNER_COLOR, 0.5)
	return c

# ------------------------------------------------------------------ 3D-Bahnen

## X-Positionen der Bahnen bei 100 % Spurbreite, symmetrisch um 0.
static func rail_x(keys: int) -> Array[float]:
	var n := maxi(keys, 1)
	var gap: float = RAIL_GAP.get(n, _gap_for(n))
	var out: Array[float] = []
	for i in n:
		out.append((float(i) - float(n - 1) * 0.5) * gap)
	return out


static func note_scale(keys: int) -> float:
	return float(NOTE_SCALE.get(keys, clampf(1.0 - 0.06 * float(keys - 4), 0.6, 1.0)))


## Feldbreite (Strassenrand, Strasse, Beat-Wellen) relativ zu 4K.
static func field_scale(keys: int) -> float:
	var xs := rail_x(keys)
	var edge := absf(xs[0]) + EDGE_MARGIN * note_scale(keys)
	return maxf(edge / EDGE_X_4K, 1.0) if keys > 4 else 1.0


static func _gap_for(n: int) -> float:
	return clampf(1.70 - 0.12 * float(n - 4), 1.1, 1.7)
