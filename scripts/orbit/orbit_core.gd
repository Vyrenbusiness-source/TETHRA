class_name OrbitCore
extends RefCounted

## Orbit-Wertung: Ziele auf zwei Ringen um die Mitte. Der Cursor-WINKEL
## waehlt die Richtung, die Taste den Ring (0 = innen, 1 = aussen). Ein
## Treffer zaehlt nur, wenn Zeitfenster UND Winkel (+-ANGLE_TOL_DEG) stimmen.
## Bogen: Kopf wie ein Tap, danach Taste halten und der wandernden Spitze
## folgen. Zu frueh loslassen oder laenger als ARC_OUT_MS ausserhalb der
## Toleranz = Miss (DROP), wie Mania-Holds.
##
## Zeitfenster, Qualitaeten, Score, Acc, Grade, HP und stats() kommen aus
## ManiaCore: ein internes ManiaCore-Objekt (_tally) zaehlt alles, damit die
## Formeln nur an einer Stelle stehen. Keine Szenen/Autoloads noetig (Mods
## kommen optional aus GameSession, falls vorhanden).

signal note_spawned(index: int)
signal note_judged(index: int, result: Dictionary)
signal arc_started(index: int, quality: int)
signal ring_pressed(ring: int, hit: bool)
## Druck ohne Treffer: Ort (Winkel, Radius in Bildhoehen), gewaehlter Ring und
## Grund: "ANGLE" (Ziel im Fenster, Winkel daneben), "RING" (Ziel im Fenster,
## aber auf dem anderen Ring), "EARLY" (Ziel noch zu weit weg, frisst nichts),
## "NONE" (nichts in der Naehe).
signal press_missed(deg: float, rho: float, ring: int, reason: String)
signal hp_changed(hp: float)
signal finished(stats: Dictionary)

## Gleiche Staffel wie ManiaCore (MAX, PERFECT, GOOD, OK, MEH, MISS).
const Quality := ManiaCore.Quality
const RINGS := 2
## Winkel-Toleranz fuer Taps, Bogen-Koepfe und das Folgen eines Bogens.
const ANGLE_TOL_DEG := 22.0
## Ringwahl durch Zeigen: Radien der Ringe in Bildhoehen (OrbitView nutzt
## dieselben Werte) und die Grenze genau dazwischen. Hysterese: der Zeiger
## muss RING_HYST_K ueber/unter die Grenze, bevor der Ring wechselt.
const R_INNER_K := 0.215
const R_OUTER_K := 0.37
const RING_SPLIT_K := (R_INNER_K + R_OUTER_K) * 0.5
const RING_HYST_K := 0.012
## So lange darf der Cursor beim Bogen ausserhalb der Toleranz sein.
const ARC_OUT_MS := 150.0
## Zielmitte: nur so nah am Ziel (Grad) gibt es die beste Stufe CORE.
const CENTER_DEG := 9.0

## --- Orbit-Mods (Schluessel im Mod-Dictionary, neben NF/SV aus ManiaCore) ---
## HD Hidden: Ziele verblassen auf den letzten ~40 % des Anflugs (OrbitView).
## FI Fade-In: Ziele erscheinen erst nach gut der Haelfte des Anflugs.
## PR Praezision: Zeit- und Winkelfenster x PR_SCALE.
const ORBIT_MODS := ["HD", "FI", "PR"]
## Anzeige-Reihenfolge aller Mods im Orbit (Badge oben links, Score-Eintrag).
const ORBIT_MOD_ORDER := ["HD", "FI", "PR", "NF", "SV"]
## Faktoren: HD und FI nehmen je eine Haelfte der Lesezeit weg (wie osu! HD
## 1,06); PR verengt beide Fenster um 30 %, also Zeit UND Ziel, darum doppelt
## (1,12). NF 0,5 und SV 1,1 kommen aus ManiaCore.MOD_MULT.
const ORBIT_MOD_MULT := {"HD": 1.06, "FI": 1.06, "PR": 1.12}
const PR_SCALE := 0.7

## --- Eigene Orbit-Wertung (nicht Mania): Stufen, Wert, Acc, Grade ---
## Stufen-Index = Quality-Index (0 CORE .. 5 MISS), damit HP/Zaehler/HUD
## weiter funktionieren. Namen (uebersetzt ueber translations/orbit.csv):
const TIER_NAMES: Array[String] = ["CORE", "SHARP", "GOOD", "FAIR", "EDGE", "MISS"]
## Zeitwert je Stufe.
const TIER_VALUE: Array[float] = [1.0, 0.94, 0.68, 0.40, 0.16, 0.0]
## Zielfaktor: in der Mitte 1,0, am Rand der Toleranz AIM_EDGE_FACTOR.
const AIM_EDGE_FACTOR := 0.88
## Anteil der Kombo-Wertung am Score (Rest = Praezision).
const STREAK_SHARE := 0.1
## Kombo, ab der ein Treffer vollen Streak-Wert hat.
const STREAK_FULL := 100
## Grade-Schwellen (Orbit-Acc): SS braucht ausserdem keinen Miss.
const GRADE_SS := 0.985
const GRADE_STEPS := [[0.95, "S"], [0.90, "A"], [0.82, "B"], [0.72, "C"]]

## Replays (Aufnahme + Wiedergabe) brauchen exakt dieselbe Wertung. Im
## deterministischen Modus laeuft die Zeit-Logik (Ablauf, Bogen-Pruefung) auf
## einem festen 1-ms-Raster statt auf Bild-Zeiten, Eingaben werden auf ganze ms
## und 0.1 Grad gerundet und nie vor den letzten Raster-Schritt gelegt. Damit
## haengt die Wertung nur von der Eingabe-Liste ab, nicht von der Bildrate.
const TICK_MS := 1.0
## Cursor-Aufnahme: neuer Winkel nur bei Aenderung > REC_MIN_DEG und
## fruehestens REC_GAP_MS nach dem letzten Eintrag (hoechstens 125/s). Der
## Core sieht beim Aufnehmen nur die aufgezeichneten Winkel; Tasten-Events
## tragen den exakten Winkel selbst (Treffer-Winkel bleibt genau).
const REC_MIN_DEG := 0.5
const REC_GAP_MS := 8.0
## Neuer Radius nur bei Aenderung > REC_MIN_RHO (Tausendstel Bildhoehe).
const REC_MIN_RHO := 3
## Replay-Format: 2 = Ring durch Zeigen (Events mit Radius). Replays ohne
## meta.orbit_rules (Format 1: Taste = Ring) sind "alte Version".
const REPLAY_RULES := 2
## Replay-Event-Codes: [t_ms, EV_CURSOR, a, r] / [t_ms, EV_DOWN + taste, a, r] /
## [t_ms, EV_UP + taste]; t in ganzen ms, a = Winkel in 0.1 Grad (0..3599),
## r = Cursor-Abstand zur Mitte in Tausendstel Bildhoehe. Taste 0/1 = beide
## treffen jedes Ziel.
const EV_CURSOR := 0
const EV_DOWN := 1
const EV_UP := 3

var notes: Array[OrbitNote] = []
var preempt: float = ManiaCore.BASE_PREEMPT

var _tally := ManiaCore.new()
var _spawn_order: Array[int] = []
var _next_spawn := 0
var _ring_notes: Array = []
var _ring_head: Array[int] = []
var _active_arc: Array[int] = [-1, -1]
var _arc_quality: Array[int] = [0, 0]
## Seit wann der Cursor ausserhalb der Bogen-Toleranz ist (INF = innerhalb).
var _out_since: Array[float] = [INF, INF]
## Zeit der letzten Bogen-Pruefung je Ring (Cursor stand seitdem still).
var _last_check: Array[float] = [0.0, 0.0]
var _judged: Dictionary = {}
var _judged_count := 0
var _finished_emitted := false
var _cursor := 0.0
## Cursor-Abstand zur Mitte (Bildhoehen) und der daraus gewaehlte Ring.
var _rho := 0.0
var _sel_ring := 0
## Welche der zwei Tasten gerade unten sind.
var _held: Array[bool] = [false, false]
## Orbit-Wertung: Summe der Trefferwerte, Streak-Summe, gewertete Ziele.
var _val_sum := 0.0
var _streak_sum := 0.0
var _n_done := 0
var _aim_sum := 0.0
var _aim_n := 0
## Deterministischer Modus (Replays), siehe TICK_MS. recording = Eingaben in
## replay_log mitschreiben (kompakt, siehe EV_*).
var deterministic := false
var recording := false
var replay_log: Array = []
var _tick := -INF
var _rec_a := -1
var _rec_r := -1
var _rec_t := -INF

# --- Zaehler und Fenster: alles liegt im ManiaCore-Zaehler ---
var combo: int:
	get: return _tally.combo
var max_combo: int:
	get: return _tally.max_combo
var n_max: int:
	get: return _tally.n_max
var n300: int:
	get: return _tally.n300
var n200: int:
	get: return _tally.n200
var n100: int:
	get: return _tally.n100
var n50: int:
	get: return _tally.n50
var n_miss: int:
	get: return _tally.n_miss
var score: int:
	get: return orbit_score()
var hp: float:
	get: return _tally.hp
var failed: bool:
	get: return _tally.failed
var no_fail: bool:
	get: return _tally.no_fail
var mods: Dictionary:
	get: return _tally.mods
var mod_mult: float:
	get: return _tally.mod_mult
var w_max: float:
	get: return _tally.w_max
var w300: float:
	get: return _tally.w300
var w200: float:
	get: return _tally.w200
var w100: float:
	get: return _tally.w100
var w50: float:
	get: return _tally.w50
var w_miss: float:
	get: return _tally.w_miss
## Winkel-Toleranz und CORE-Mitte dieses Laufs (PR: x PR_SCALE).
var angle_tol := ANGLE_TOL_DEG
var center_tol := CENTER_DEG


## p_notes: Ergebnis von OrbitConverter.convert (nach time_ms sortiert).
## od: OverallDifficulty der Map (gleiche Fenster wie Mania).
## scroll_scale: wie ManiaCore (teilt nur die Anflugzeit, rein visuell).
## hp_drain: HPDrainRate der Map. p_mods: Mod-Dictionary, null = GameSession.
func setup(p_notes: Array[OrbitNote], od: float, scroll_scale: float = 1.0,
		hp_drain: float = 5.0, p_mods = null) -> void:
	notes = p_notes
	_tally = ManiaCore.new()
	_tally.w_max = DifficultyCalc.mania_window_max(od)
	_tally.w300 = DifficultyCalc.mania_window_300(od)
	_tally.w200 = DifficultyCalc.mania_window_200(od)
	_tally.w100 = DifficultyCalc.mania_window_100(od)
	_tally.w50 = DifficultyCalc.mania_window_50(od)
	_tally.w_miss = DifficultyCalc.mania_window_miss(od)
	_tally._hp_miss_damage = 0.04 + 0.04 * (hp_drain / 10.0)
	var m: Dictionary = p_mods if p_mods is Dictionary else ManiaCore.session_mods()
	_tally.mods = m.duplicate()
	_tally.mod_mult = mod_multiplier(m)
	_tally.no_fail = bool(m.get("NF", false))
	var k := window_scale(m)
	_tally.w_max *= k
	_tally.w300 *= k
	_tally.w200 *= k
	_tally.w100 *= k
	_tally.w50 *= k
	_tally.w_miss *= k
	angle_tol = ANGLE_TOL_DEG * k
	center_tol = CENTER_DEG * k
	_tally._total_notes = notes.size()
	preempt = ManiaCore.preempt_for(scroll_scale)
	_ring_notes = []
	_ring_head = []
	for r in RINGS:
		_ring_notes.append([])
		_ring_head.append(0)
	_spawn_order = []
	for i in notes.size():
		_spawn_order.append(i)
		_ring_notes[clampi(notes[i].ring, 0, RINGS - 1)].append(i)
	var by_time := func(a: int, b: int) -> bool:
		if notes[a].time_ms != notes[b].time_ms:
			return notes[a].time_ms < notes[b].time_ms
		return a < b
	_spawn_order.sort_custom(by_time)
	for r in RINGS:
		(_ring_notes[r] as Array).sort_custom(by_time)
	_active_arc = [-1, -1]
	_arc_quality = [0, 0]
	_out_since = [INF, INF]
	_last_check = [0.0, 0.0]
	_judged = {}
	_judged_count = 0
	_next_spawn = 0
	_finished_emitted = false
	_cursor = 0.0
	_rho = 0.0
	_sel_ring = 0
	_held = [false, false]
	_rec_r = -1
	_val_sum = 0.0
	_streak_sum = 0.0
	_n_done = 0
	_aim_sum = 0.0
	_aim_n = 0
	_tick = -INF
	_rec_a = -1
	_rec_t = -INF
	replay_log = []


## Fenster-Faktor eines Mod-Dictionarys (PR: PR_SCALE, sonst 1).
static func window_scale(p_mods: Dictionary) -> float:
	return PR_SCALE if bool(p_mods.get("PR", false)) else 1.0


## Score-Faktor im Orbit: ManiaCore (NF, SV) mal Orbit-Mods (HD, FI, PR).
static func mod_multiplier(p_mods: Dictionary) -> float:
	var m := ManiaCore.mod_multiplier(p_mods)
	for k in ORBIT_MOD_MULT:
		if bool(p_mods.get(k, false)):
			m *= float(ORBIT_MOD_MULT[k])
	return m


## Aktive Mods als Liste in Anzeige-Reihenfolge, z.B. ["HD", "PR", "NF"].
static func mod_list(p_mods: Dictionary) -> Array:
	var out := []
	for k in ORBIT_MOD_ORDER:
		if bool(p_mods.get(k, false)):
			out.append(k)
	return out


## Badge-Text, z.B. "HD PR NF" ("" ohne Mods).
static func mods_text(p_mods: Dictionary) -> String:
	return " ".join(mod_list(p_mods))


## Mods eines gespeicherten Orbit-Replays (aeltere ohne Eintrag: keine Mods).
static func replay_mods(data: Dictionary) -> Dictionary:
	var meta = data.get("meta", {})
	var m = meta.get("mods", {}) if meta is Dictionary else {}
	var out := {}
	for k in ORBIT_MOD_ORDER:
		out[k] = bool(m.get(k, false)) if m is Dictionary else false
	return out


## Replay-Modus einschalten (nach setup): record = Eingaben mitschreiben.
func set_replay_mode(record: bool) -> void:
	deterministic = true
	recording = record


## Scroll-Faktor waehrend des Spiels aendern (nur Anflugzeit).
func set_scroll_scale(scroll_scale: float) -> void:
	preempt = ManiaCore.preempt_for(scroll_scale)


func update(t_ms: float) -> void:
	while _next_spawn < _spawn_order.size() \
			and notes[_spawn_order[_next_spawn]].time_ms - preempt <= t_ms:
		note_spawned.emit(_spawn_order[_next_spawn])
		_next_spawn += 1
	if deterministic:
		_advance(floorf(t_ms))
	else:
		_check_arcs(t_ms)
		for r in RINGS:
			_expire_ring(r, t_ms)
	if _judged_count >= notes.size() and _next_spawn >= _spawn_order.size() \
			and not _finished_emitted:
		_finished_emitted = true
		finished.emit(stats())


## Cursor zur Event-Zeit t_ms: Winkel (0 = oben, im Uhrzeigersinn) und Abstand
## zur Mitte rho (in Bildhoehen). Bis t_ms stand der Cursor noch am alten Ort.
func cursor_moved(cursor_deg: float, rho: float, t_ms: float) -> void:
	if not deterministic:
		_do_cursor(cursor_deg, rho, t_ms)
		return
	if _tally.failed or notes.is_empty():
		return
	var a := _q_deg(cursor_deg)
	var r := _q_rho(rho)
	var te := _q_time(t_ms)
	if a == _rec_a and r == _rec_r:
		return
	if recording and _rec_a >= 0:
		var d := absi(a - _rec_a)
		d = mini(d, 3600 - d)
		if (d <= int(REC_MIN_DEG * 10.0) and absi(r - _rec_r) <= REC_MIN_RHO) \
				or te - _rec_t < REC_GAP_MS:
			return
	apply_event([int(te), EV_CURSOR, a, r])


func _do_cursor(cursor_deg: float, rho: float, t_ms: float) -> void:
	_check_arcs(t_ms)
	_cursor = OrbitNote.wrap_deg(cursor_deg)
	_rho = rho
	_sel_ring = ring_for_rho(rho, _sel_ring)
	_check_arcs(t_ms)


## Gewaehlter Ring zum Cursor-Abstand rho; zwischen den Grenzen (Hysterese)
## bleibt der bisherige Ring prev.
static func ring_for_rho(rho: float, prev: int) -> int:
	if rho > RING_SPLIT_K + RING_HYST_K:
		return 1
	if rho < RING_SPLIT_K - RING_HYST_K:
		return 0
	return prev


## Ring, den der Cursor gerade waehlt (0 innen, 1 aussen).
func cursor_ring() -> int:
	return _sel_ring


func cursor_rho() -> float:
	return _rho


## Taste (0 oder 1, beide gleichwertig) gedrueckt; Cursor bei cursor_deg/rho.
## Getroffen wird ein Ziel auf dem Ring, den der Cursor-Abstand waehlt.
func key_down(key: int, t_ms: float, cursor_deg: float, rho: float) -> void:
	if key < 0 or key >= RINGS or notes.is_empty():
		return
	if deterministic:
		if not _tally.failed:
			apply_event([int(_q_time(t_ms)), EV_DOWN + key, _q_deg(cursor_deg), _q_rho(rho)])
		return
	_do_key_down(key, t_ms, cursor_deg, rho)


func _do_key_down(key: int, t_ms: float, cursor_deg: float, rho: float) -> void:
	_do_cursor(cursor_deg, rho, t_ms)
	_held[key] = true
	var ring := _sel_ring
	for r in RINGS:
		_expire_ring(r, t_ms)
	var lane: Array = _ring_notes[ring]
	var idx := -1
	var dt := 0.0
	var err := 0.0
	var reason := "NONE"
	for j in range(_ring_head[ring], lane.size()):
		var i: int = lane[j]
		if _judged.has(i):
			continue
		var n := notes[i]
		var d := t_ms - n.time_ms
		if d < -w50:
			# Zu frueh: frisst das Ziel NICHT, der Druck zaehlt nur als Fehldruck.
			if d >= -w_miss and reason == "NONE":
				reason = "EARLY"
			break
		if d > w50:
			continue
		var e := OrbitNote.dist_deg(_cursor, n.angle_at(t_ms))
		if e > angle_tol:
			reason = "ANGLE"
			continue
		idx = i
		dt = d
		err = e
		break
	if idx < 0:
		if reason == "NONE" and _target_waiting(1 - ring, t_ms):
			reason = "RING"
		ring_pressed.emit(ring, false)
		press_missed.emit(_cursor, _rho, ring, reason)
		return
	var q: int = _tally._quality_for(absf(dt))
	if q == Quality.MAX and err > center_tol:
		q = Quality.PERFECT  # Zeit perfekt, aber nicht mittig: SHARP statt CORE
	_aim_sum += err
	_aim_n += 1
	if notes[idx].is_arc:
		_active_arc[ring] = idx
		_arc_quality[ring] = q
		_out_since[ring] = INF
		_last_check[ring] = t_ms
		_tally.combo += 1
		_tally.max_combo = maxi(_tally.max_combo, _tally.combo)
		_judged[idx] = {"pending": true, "dt": dt, "angle_err": err}
		arc_started.emit(idx, q)
	else:
		_apply_hit(idx, q, dt, err)
	ring_pressed.emit(ring, true)


## Wartet auf ring ein offenes Ziel im Trefferfenster (Zeit, egal welcher Winkel)?
func _target_waiting(ring: int, t_ms: float) -> bool:
	var lane: Array = _ring_notes[ring]
	for j in range(_ring_head[ring], lane.size()):
		var i: int = lane[j]
		if _judged.has(i):
			continue
		var d := t_ms - notes[i].time_ms
		if d < -w_miss:
			break
		if d <= w50:
			return true
	return false


## Taste losgelassen. Ein Bogen laeuft, solange IRGENDEINE Taste unten ist.
func key_up(key: int, t_ms: float) -> void:
	if key < 0 or key >= RINGS or notes.is_empty():
		return
	if deterministic:
		if not _tally.failed:
			apply_event([int(_q_time(t_ms)), EV_UP + key])
		return
	_do_key_up(key, t_ms)


func _do_key_up(key: int, t_ms: float) -> void:
	_check_arcs(t_ms)
	_held[key] = false
	if _held[0] or _held[1]:
		return
	for r in RINGS:
		var h: int = _active_arc[r]
		if h < 0:
			continue
		# Kurz vor dem Ende loslassen ist ok (1.5x 50er-Fenster, wie Mania).
		var ok := t_ms >= notes[h].end_ms - w50 * 1.5
		_finish_arc(r, ok, "" if ok else "RELEASE")


func accuracy() -> float:
	if _n_done == 0:
		return 1.0
	return _val_sum / float(_n_done)


func grade() -> String:
	var acc := accuracy()
	if acc >= GRADE_SS and _tally.n_miss == 0:
		return "SS"
	for g in GRADE_STEPS:
		if acc >= float(g[0]):
			return str(g[1])
	return "D"


## Orbit-Score 0..1.000.000 (x Mod-Faktor): 90 % Praezision (Zeitwert x
## Zielfaktor je Ziel), 10 % Streak (Trefferwert x Kombo-Anteil bis 100).
func orbit_score() -> int:
	var n := float(maxi(notes.size(), 1))
	var raw := (1.0 - STREAK_SHARE) * _val_sum / n + STREAK_SHARE * _streak_sum / n
	return int(round(1000000.0 * raw * _tally.mod_mult))


## Wert eines Treffers: Zeitstufe x Zielfaktor (mittig 1,0, Rand 0,88).
## tol/center: Fenster des Laufs (PR enger), Standard ohne Mods.
static func hit_value(q: int, angle_err: float, tol: float = ANGLE_TOL_DEG,
		center: float = CENTER_DEG) -> float:
	var tv: float = TIER_VALUE[clampi(q, 0, 5)]
	var k := clampf((angle_err - center) / maxf(tol - center, 0.001), 0.0, 1.0)
	return tv * lerpf(1.0, AIM_EDGE_FACTOR, k)


## Mittlerer Zielfehler (Grad) aller Treffer.
func mean_aim_err() -> float:
	return _aim_sum / float(maxi(_aim_n, 1))


## Wie ManiaCore.stats() (gleiche Felder fuer Results/Scores/Lobby), aber
## Score, Acc und Grade nach Orbit-Regeln; "mode": "orbit".
func stats() -> Dictionary:
	var s: Dictionary = _tally.stats()
	s["score"] = orbit_score()
	s["accuracy"] = accuracy()
	s["grade"] = grade()
	s["aim_err"] = mean_aim_err()
	s["mode"] = "orbit"
	s["mods"] = mod_list(_tally.mods)
	return s


func _count_value(q: int, err: float) -> void:
	var v := hit_value(q, err, angle_tol, center_tol) if q != Quality.MISS else 0.0
	_val_sum += v
	_streak_sum += v * minf(float(_tally.combo) / float(STREAK_FULL), 1.0)
	_n_done += 1


func is_judged(index: int) -> bool:
	return _judged.has(index)


## Index des laufenden Bogens auf ring, sonst -1.
func active_arc(ring: int) -> int:
	return _active_arc[ring]


## Letzter bekannter Cursor-Winkel (0-360).
func cursor_deg() -> float:
	return _cursor


## Wie lange der Cursor beim Bogen auf ring schon ausserhalb ist (0 = innen).
func arc_out_ms(ring: int, t_ms: float) -> float:
	if _active_arc[ring] < 0 or _out_since[ring] == INF:
		return 0.0
	return maxf(t_ms - _out_since[ring], 0.0)


## Zeitfehler des Bogen-Kopfs (ms, + = spaet), solange er laeuft; sonst 0.
func arc_head_dt(index: int) -> float:
	var j: Dictionary = _judged.get(index, {})
	return float(j.get("dt", 0.0))


## Laufende Boegen pruefen: Cursor ausserhalb > ARC_OUT_MS = DROP, Ende
## erreicht = Kopf-Qualitaet einloesen.
func _check_arcs(t_ms: float) -> void:
	for r in RINGS:
		var h: int = _active_arc[r]
		if h < 0:
			continue
		var n := notes[h]
		var tc := minf(t_ms, n.end_ms)
		# Draussen: Winkel neben der Spitze ODER der Cursor auf dem anderen Ring.
		if OrbitNote.dist_deg(_cursor, n.angle_at(tc)) > angle_tol or _sel_ring != r:
			if _out_since[r] == INF:
				_out_since[r] = _exit_time(n, r, tc)
			if tc - _out_since[r] > ARC_OUT_MS:
				_finish_arc(r, false, "OUT")
				continue
		else:
			_out_since[r] = INF
		_last_check[r] = tc
		if t_ms >= n.end_ms:
			_finish_arc(r, true, "")


## Genauer Zeitpunkt, an dem die Spitze den still stehenden Cursor verlassen
## hat (zwischen letzter Pruefung und tc; die Spitze laeuft linear).
func _exit_time(n: OrbitNote, r: int, tc: float) -> float:
	var t0 := clampf(_last_check[r], n.time_ms, tc)
	var d0 := OrbitNote.delta_deg(_cursor, n.angle_at(t0))
	if absf(d0) > angle_tol or n.duration_ms() <= 0.0:
		return t0
	var v := n.span_deg() / n.duration_ms()
	if v == 0.0:
		return tc
	var edge := angle_tol if v > 0.0 else -angle_tol
	return clampf(t0 + (edge - d0) / v, t0, tc)


func _expire_ring(r: int, t_ms: float) -> void:
	var lane: Array = _ring_notes[r]
	while _ring_head[r] < lane.size():
		var idx: int = lane[_ring_head[r]]
		if _judged.has(idx):
			_ring_head[r] += 1
			continue
		if t_ms > notes[idx].time_ms + w50 and _active_arc[r] != idx:
			_miss(idx, t_ms - notes[idx].time_ms,
					OrbitNote.dist_deg(_cursor, notes[idx].angle_deg))
			continue
		break


func _finish_arc(r: int, held_to_end: bool, reason: String) -> void:
	var idx: int = _active_arc[r]
	_active_arc[r] = -1
	_out_since[r] = INF
	if idx < 0:
		return
	var head: Dictionary = _judged.get(idx, {})
	var dt := float(head.get("dt", 0.0))
	var err := float(head.get("angle_err", 0.0))
	if not held_to_end:
		_lose_hp_and_combo()
		var dropped := {
			"quality": Quality.MISS, "dt": dt, "angle_err": err, "ring": r,
			"hold_end": true, "held": false, "miss_kind": "DROP",
			"drop_reason": reason, "late": false,
		}
		_store(idx, dropped)
		return
	var q: int = _arc_quality[r]
	_tally._count_quality(q)
	_tally._add_score(q)
	_count_value(q, err)
	_heal(q)
	_store(idx, {
		"quality": q, "dt": dt, "angle_err": err, "ring": r,
		"hold_end": true, "held": true, "miss_kind": "", "late": dt > 0.0,
	})


func _apply_hit(idx: int, q: int, dt: float, err: float) -> void:
	_tally._count_quality(q)
	_tally.combo += 1
	_tally.max_combo = maxi(_tally.max_combo, _tally.combo)
	_tally._add_score(q)
	_count_value(q, err)
	_heal(q)
	_store(idx, {
		"quality": q, "dt": dt, "late": dt > 0.0, "angle_err": err,
		"ring": notes[idx].ring, "miss_kind": "",
	})


func _miss(idx: int, dt: float, err: float) -> void:
	_lose_hp_and_combo()
	_store(idx, {
		"quality": Quality.MISS, "dt": dt, "angle_err": err,
		"ring": notes[idx].ring, "miss_kind": "FULL", "late": false,
	})


func _lose_hp_and_combo() -> void:
	_count_value(Quality.MISS, 0.0)
	_tally.n_miss += 1
	_tally.combo = 0
	_tally._add_score(Quality.MISS)
	_tally.hp = maxf(_tally.hp - _tally._hp_miss_damage, 0.0)
	hp_changed.emit(_tally.hp)
	if _tally.hp <= 0.0 and not _tally.no_fail:
		_tally.failed = true


func _heal(q: int) -> void:
	_tally.hp = minf(_tally.hp + float(_tally._hp_heal[q]), 1.0)
	hp_changed.emit(_tally.hp)


func _store(idx: int, result: Dictionary) -> void:
	_judged[idx] = result
	_judged_count += 1
	note_judged.emit(idx, result)


# ---------------------------------------------------------------------------
# Replay (deterministischer Modus)
# ---------------------------------------------------------------------------

## Ein Replay-Event einspeisen (Wiedergabe) bzw. eine gerundete Live-Eingabe
## ausfuehren und mitschreiben. Vorher laeuft das Raster bis t (einschliesslich).
func apply_event(ev: Array) -> void:
	if ev.size() < 2 or notes.is_empty() or _tally.failed:
		return
	var te := float(ev[0])
	var code := int(ev[1])
	_advance(te)
	if _tally.failed:
		return
	if recording:
		replay_log.append(ev.duplicate())
	if code == EV_CURSOR and ev.size() >= 3:
		_rec_a = int(ev[2])
		_rec_r = int(ev[3]) if ev.size() >= 4 else 0
		_rec_t = te
		_do_cursor(float(_rec_a) / 10.0, float(_rec_r) / 1000.0, te)
	elif code >= EV_DOWN and code < EV_DOWN + RINGS and ev.size() >= 3:
		_rec_a = int(ev[2])
		_rec_r = int(ev[3]) if ev.size() >= 4 else 0
		_rec_t = te
		_do_key_down(code - EV_DOWN, te, float(_rec_a) / 10.0, float(_rec_r) / 1000.0)
	elif code >= EV_UP and code < EV_UP + RINGS:
		_do_key_up(code - EV_UP, te)


## Ganze ms, nie vor dem letzten Raster-Schritt (sonst haengt die Reihenfolge
## an der Bildrate).
func _q_time(t_ms: float) -> float:
	return maxf(roundf(t_ms), _tick)


static func _q_rho(rho: float) -> int:
	return clampi(int(roundf(rho * 1000.0)), 0, 2000)


static func _q_deg(deg: float) -> int:
	return int(roundf(fposmod(deg, 360.0) * 10.0)) % 3600


## Raster-Schritte bis einschliesslich target. Ohne laufenden Bogen springt es
## direkt zum naechsten Ablauf-Zeitpunkt (dazwischen passiert nichts). Nach
## einem Fail steht alles (Wiedergabe endet am selben Stand).
func _advance(target: float) -> void:
	while _tick < target and not _tally.failed:
		if _active_arc[0] < 0 and _active_arc[1] < 0:
			var due := _next_due_tick()
			if due > target:
				_tick = target
				return
			_tick = maxf(due, _tick + TICK_MS)
		else:
			_tick += TICK_MS
		_check_arcs(_tick)
		for r in RINGS:
			_expire_ring(r, _tick)


## Erster Raster-Schritt, an dem ein offenes Ziel ablaeuft (t > time + w50).
func _next_due_tick() -> float:
	var best := INF
	for r in RINGS:
		var lane: Array = _ring_notes[r]
		for j in range(_ring_head[r], lane.size()):
			var i: int = lane[j]
			if _judged.has(i):
				continue
			best = minf(best, floorf(float(notes[i].time_ms) + w50) + TICK_MS)
			break
	return best


## Kompakter Replay-Inhalt: Anzahl Cursor- und Tasten-Events.
static func count_events(events: Array) -> Dictionary:
	var c := 0
	var k := 0
	for e in events:
		if e is Array and e.size() >= 2:
			if int(e[1]) == EV_CURSOR:
				c += 1
			else:
				k += 1
	return {"cursor": c, "keys": k}


# ---------------------------------------------------------------------------
# Bot (Autoplay-Varianten, Tests)
# ---------------------------------------------------------------------------

## Plan fuer einen "menschlichen" Bot: je Ziel [Zeitversatz ms (+ = spaet),
## Zielfehler Grad, auslassen]. Deterministisch ueber seed. sigma_t/sigma_a =
## Streuung (Normalverteilung, auf 3 sigma gedeckelt); miss_every > 0 laesst
## jedes n-te Ziel aus. sigma 0 = perfekt.
static func bot_plan(p_notes: Array, seed: int, sigma_t: float, sigma_a: float,
		miss_every: int = 0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	out.resize(p_notes.size())
	for i in p_notes.size():
		var ot := 0.0
		var oa := 0.0
		if sigma_t > 0.0:
			ot = clampf(rng.randfn(0.0, sigma_t), -3.0 * sigma_t, 3.0 * sigma_t)
		if sigma_a > 0.0:
			oa = clampf(rng.randfn(0.0, sigma_a), -3.0 * sigma_a, 3.0 * sigma_a)
		out[i] = [ot, oa, miss_every > 0 and i % miss_every == miss_every - 1]
	return out
