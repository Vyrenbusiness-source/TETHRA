class_name MineGen
extends RefCounted

## Minen-Konverter (Mod "MN"): setzt Minen in freie Spalten neben dichten Mustern.
## Deterministisch: Seed aus dem Noten-Hash der Map (Zeit, Spalte, Ende je Note),
## dieselbe Map ergibt immer dieselben Minen (Replay-fest; Version in mods.MN_v).
##
## Regel (Version 1):
##  - Kandidaten sind die Zeilen der Map (Zeitpunkte mit Noten). Eine Mine liegt immer
##    auf so einer Zeile, in einer Spalte OHNE Note: sie liest sich als Teil des Musters
##    ("diese druecken, die nicht").
##  - Nur dichte Stellen: Noten im Fenster +-500 ms um die Zeile (= Noten je Sekunde)
##    mindestens DENSE_NPS.
##  - Wie viele: Chance je dichter Zeile p = 0,10 + 0,025 x (nps - DENSE_NPS), hoechstens
##    0,35. Dichtere Abschnitte bekommen also mehr Minen, ruhige keine.
##  - Spalte frei: nie unter GAP_BEFORE_MS (150 ms) vor einer eigenen Note derselben
##    Spalte, nie unter GAP_AFTER_MS nach einer eigenen Note bzw. einem Hold-Ende, nie
##    in einem Hold. Mindestens MINE_GAP_MS zur letzten Mine derselben Spalte und
##    ANY_GAP_MS zur letzten Mine ueberhaupt (keine Minen-Waende).
##  - Hoechstens eine Mine je Zeile (auch neben einem Akkord aus K-1 Noten: gedrueckt
##    wird nur, was eine Note hat).
## Rueckgabe: [[zeit_ms, spalte], ...] nach Zeit, dann Spalte sortiert.

const VERSION := 1
const GAP_BEFORE_MS := 150.0
const GAP_AFTER_MS := 150.0
const DENSE_NPS := 8.0
const DENSITY_WINDOW_MS := 1000.0
const P_BASE := 0.10
const P_PER_NPS := 0.025
const P_MAX := 0.35
const MINE_GAP_MS := 300.0
const ANY_GAP_MS := 120.0
const ROW_EPS_MS := 2.0


## Seed aus dem Noten-Hash (md5 ueber Spaltenzahl und alle Noten, unabhaengig vom Dateinamen).
static func seed_for(bm: Beatmap, columns: int) -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var parts := PackedStringArray([str(columns)])
	for o in bm.hit_objects:
		if o is ManiaNote:
			var n := o as ManiaNote
			parts.append("%d,%d,%d" % [int(round(n.time)), n.column, int(round(n.end_time()))])
	ctx.update(";".join(parts).to_utf8_buffer())
	var h := ctx.finish()
	# 31 Bit, positiv, plattformgleich.
	return (h[0] << 23) | (h[1] << 15) | (h[2] << 7) | (h[3] >> 1)


static func generate(bm: Beatmap, columns: int, version: int = VERSION) -> Array:
	var out: Array = []
	if bm == null or columns <= 1:
		return out
	# version: heute nur 1. Spaetere Regeln bekommen eigene Zweige, Version 1 bleibt.
	var _v := version
	var notes: Array = []
	for o in bm.hit_objects:
		if o is ManiaNote and (o as ManiaNote).column >= 0 and (o as ManiaNote).column < columns:
			notes.append(o)
	if notes.is_empty():
		return out
	notes.sort_custom(func(a, b): return a.time < b.time)
	# Sperrintervalle je Spalte: [start - GAP_BEFORE, ende + GAP_AFTER].
	var blocked: Array = []
	for c in columns:
		blocked.append([])
	for n in notes:
		(blocked[n.column] as Array).append(Vector2(n.time - GAP_BEFORE_MS, n.end_time() + GAP_AFTER_MS))
	# Zeilen: Zeitpunkt + belegte Spalten.
	var rows: Array = []
	for n in notes:
		if rows.is_empty() or n.time - float(rows[-1][0]) > ROW_EPS_MS:
			rows.append([n.time, {}])
		(rows[-1][1] as Dictionary)[n.column] = true
	var times := PackedFloat64Array()
	for n in notes:
		times.append(n.time)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(bm, columns) ^ (version * 7919)
	var last_any := -INF
	var last_col: Array = []
	last_col.resize(columns)
	last_col.fill(-INF)
	var lo := 0
	var hi := 0
	var half := DENSITY_WINDOW_MS * 0.5
	for row in rows:
		var t: float = row[0]
		while lo < times.size() and times[lo] < t - half:
			lo += 1
		while hi < times.size() and times[hi] < t + half:
			hi += 1
		var nps := float(hi - lo) / (DENSITY_WINDOW_MS / 1000.0)
		if nps < DENSE_NPS:
			continue
		# Immer genau zwei Zufallszahlen je dichter Zeile: die Folge haengt nicht davon ab,
		# welche Spalten frei sind (stabil bei kleinen Regel-Aenderungen).
		var roll := rng.randf()
		var pick := rng.randi()
		var p := minf(P_BASE + P_PER_NPS * (nps - DENSE_NPS), P_MAX)
		if roll >= p or t - last_any < ANY_GAP_MS:
			continue
		var free: Array[int] = []
		var used: Dictionary = row[1]
		for c in columns:
			if used.has(c) or t - float(last_col[c]) < MINE_GAP_MS:
				continue
			if _blocked(blocked[c], t):
				continue
			free.append(c)
		if free.is_empty():
			continue
		var col: int = free[pick % free.size()]
		out.append([t, col])
		last_any = t
		last_col[col] = t
	return out


static func _blocked(spans: Array, t: float) -> bool:
	for s in spans:
		var v: Vector2 = s
		if t >= v.x and t <= v.y:
			return true
		if v.x > t:
			break
	return false


## Prueft eine Minenliste gegen die Regeln (Tests, QA): "" = ok, sonst erster Verstoss.
static func violation(bm: Beatmap, columns: int, mines: Array) -> String:
	for m in mines:
		var t: float = m[0]
		var c: int = m[1]
		if c < 0 or c >= columns:
			return "Spalte %d ausserhalb" % c
		for o in bm.hit_objects:
			if not (o is ManiaNote) or (o as ManiaNote).column != c:
				continue
			var n := o as ManiaNote
			if t > n.time - GAP_BEFORE_MS and t <= n.time:
				return "Mine %.0f ms in Spalte %d unter %.0f ms vor Note %.0f" % [t, c, GAP_BEFORE_MS, n.time]
			if t >= n.time and t < n.end_time() + GAP_AFTER_MS:
				return "Mine %.0f ms in Spalte %d direkt nach/in Note %.0f" % [t, c, n.time]
	return ""
