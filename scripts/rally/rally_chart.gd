class_name RallyChart
extends RefCounted

## Rally: Schlagfolge aus einer Map (osu!standard oder Mania 4K) und die
## Flugbahn des Balls. Alles reine Funktionen der Zeit (kein Zustand), damit
## Core, Ansicht und Tests dieselben Zahlen sehen. Details: docs/modes/rally.md.
##
## Koordinaten der Flugbahn sind normiert (x in Breiten, y in Hoehen, y waechst
## nach unten): die Ansicht skaliert auf ihr Rechteck.

## Standard-Flugzeit (= Settings.RALLY_FLIGHT_DEFAULT); das Spiel uebergibt die Einstellung.
const DEFAULT_FLIGHT_MS := 800.0
const KEY_A := 0
const KEY_B := 1
## Akkord-Toleranz (gleiche Zeit in der Quell-Map).
const CHORD_EPS_MS := 2.0
## Zwei Schlaege naeher als das werden zusammengefasst.
const MERGE_MS := 90.0
## Leichte Maps (Schlaege/s darunter): nur Achtel, also Mindestabstand 1/4 Beat.
const LIGHT_NPS := 2.5
## Kuerzere Slider/Holds bleiben normale Schlaege.
const MIN_CHARGE_MS := 200.0
const MAX_CHARGE_MS := 4000.0
## Ab diesem Abstand gibt es keinen durchgehenden Ballwechsel: Gegner schlaegt neu auf.
const BREAK_MS := 3500.0
const SERVE_LEAD_MS := 1800.0
## Nach dem Schlag vor einer Pause fliegt der Ball so lange zum Gegner und verschwindet.
const EXIT_MS := 800.0

## Layout (normiert).
const X_PLAYER := 0.20
const X_OPP := 0.80
const X_TABLE_L := 0.15
const X_TABLE_R := 0.85
const Y_TABLE := 0.66
const Y_LOW := 0.585     ## Trefferhoehe Taste A (tiefer Ball)
const Y_HIGH := 0.36     ## Trefferhoehe Taste B (hoher Ball)
const Y_OPP := 0.47
## Bruchteil der Flugzeit (x linear), an dem der Ball auf dem Tisch aufkommt.
const F_BOUNCE_OPP := 0.70
const F_BOUNCE_ME := 0.72


class Shot extends RefCounted:
	var t := 0.0            ## Notenzeit (Schlag / Druck)
	var end := 0.0          ## Loslassen (== t bei normalem Schlag)
	var key := 0            ## nur Altlast (alte Flugbahn): 0 = linke, 1 = rechte Haelfte
	var smash := false      ## Schmetterball: beide Tasten
	var serve := false      ## Ball erscheint beim Gegner neu (Start/Pause)
	var m := 0.0            ## Zeit des Gegnerschlags vor diesem Schlag
	var exit_after := false ## nach diesem Schlag folgt eine Pause
	var src := 0            ## Index des Quellobjekts
	# --- Rally v2 (docs/modes/rally.md "Regeln v2"): 4 Zonen ---
	var zones := PackedInt32Array()  ## 1 Zone (0..3) oder 2 Zonen beim Schmetterball
	var launch := 0.0       ## Gegnerschlag = t - Flugzeit (RallyFlight.finalize)
	var arc := 0.0          ## Bogenhoehe 0..1 (nur Optik, RallyFlight.finalize)
	var curve := 0.0        ## Seitwaerts-Effet -1..1 (nur Optik, RallyFlight.finalize)

	func is_charge() -> bool:
		return end > t


static func hit_y(key: int) -> float:
	return Y_HIGH if key == KEY_B else Y_LOW


# ---------------------------------------------------------------------------
# Aufbau aus der Map
# ---------------------------------------------------------------------------

## Zonenzahl des zuletzt gebauten Charts (3 oder 4); die Ansicht liest sie hier.
static var _zones := 4


static func zone_count() -> int:
	return _zones


static func build(beatmap: Beatmap, flight_ms: float = -1.0, zones: int = 4) -> Array[Shot]:
	_zones = 3 if zones == 3 else 4
	var out: Array[Shot] = []
	if beatmap == null or beatmap.hit_objects.is_empty():
		return out
	var raw := _raw_events(beatmap)
	var groups := _group(raw)
	var span := 1000.0
	if groups.size() > 1:
		span = maxf(float(groups[-1][0]) - float(groups[0][0]), 1000.0)
	var light := float(groups.size()) / (span / 1000.0) < LIGHT_NPS
	for g in groups:
		var s := _shot_of(g)
		var gap := MERGE_MS
		if light:
			gap = maxf(MERGE_MS, _beat_ms(beatmap, s.t) * 0.25 - 1.0)
		if not out.is_empty() and s.t - out[-1].end < gap:
			continue
		out.append(s)
	finalize(out)
	if flight_ms <= 0.0:
		flight_ms = DEFAULT_FLIGHT_MS
	finalize_flight(out, flight_ms)
	return out


## Flug-Geometrie (launch/arc/curve) macht RallyFlight (Ansicht-Agent); fehlt die
## Klasse, gilt nur launch = t - flight_ms.
static func finalize_flight(shots: Array[Shot], flight_ms: float) -> void:
	var path := "res://scripts/rally/rally_flight.gd"
	if ResourceLoader.exists(path):
		var scr = load(path)
		if scr != null and scr.has_method("finalize"):
			scr.call("finalize", shots, flight_ms)
			return
	for s in shots:
		s.launch = s.t - flight_ms


## Zone aus Mania-Spalte. 4 Zonen: 4K direkt, sonst gestreckt. 3 Zonen: bei 4K
## Spalte 0 links, 1+2 Mitte, 3 rechts; sonst gestreckt.
static func zone_of_column(column: int, columns: int, n: int = -1) -> int:
	if n < 0:
		n = _zones
	if columns <= 1:
		return 0
	if n == 3 and columns == 4:
		return [0, 1, 1, 2][clampi(column, 0, 3)]
	return clampi(int(floor(float(column) * float(n) / float(columns))), 0, n - 1)


## Zone aus osu!standard-Feld-x (0..512): 4 Streifen (128) bzw. 3 Streifen (171 / 341).
static func zone_of_x(x: float, n: int = -1) -> int:
	if n < 0:
		n = _zones
	return clampi(int(floor(x * float(n) / 512.0)), 0, n - 1)


## Rohliste [t, end, zone, unused, src] aus Mania- oder Standard-Objekten.
static func _raw_events(beatmap: Beatmap) -> Array:
	var list: Array = []
	var k := maxi(beatmap.column_count(), 1)
	for i in beatmap.hit_objects.size():
		var o = beatmap.hit_objects[i]
		if o is ManiaNote:
			var end := 0.0
			if o.is_hold and o.end_time() - o.time >= MIN_CHARGE_MS:
				end = minf(o.end_time(), o.time + MAX_CHARGE_MS)
			list.append([o.time, end, zone_of_column(o.column, k), false, i])
		else:
			var end := 0.0
			if o.kind != HitObject.Kind.CIRCLE and o.end_time() - o.time >= MIN_CHARGE_MS:
				end = minf(o.end_time(), o.time + MAX_CHARGE_MS)
			list.append([o.time, end, zone_of_x(o.x), false, i])
	list.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[4] < b[4])
	return list


## Gleichzeitige Objekte (<= CHORD_EPS_MS) zu Gruppen [t, [raw...]].
static func _group(list: Array) -> Array:
	var groups: Array = []
	for e in list:
		if groups.is_empty() or float(e[0]) - float(groups[-1][0]) > CHORD_EPS_MS:
			groups.append([e[0], []])
		(groups[-1][1] as Array).append(e)
	return groups


## Gruppe -> Schlag: lange Note = Aufladen (Zone der laengsten), sonst >= 2 Zonen =
## Schmetterball (aeusserste 2), sonst normaler Ball.
static func _shot_of(g: Array) -> Shot:
	var s := Shot.new()
	s.t = float(g[0])
	s.end = s.t
	var zmin := 3
	var zmax := 0
	var best_end := 0.0
	var charge_zone := 0
	s.src = int(g[1][0][4])
	for e in g[1]:
		zmin = mini(zmin, int(e[2]))
		zmax = maxi(zmax, int(e[2]))
		if float(e[1]) > best_end:
			best_end = float(e[1])
			charge_zone = int(e[2])
	if best_end > s.t:
		s.end = best_end
		s.zones = PackedInt32Array([charge_zone])
	elif zmax > zmin:
		s.smash = true
		s.zones = PackedInt32Array([zmin, zmax])
	else:
		s.zones = PackedInt32Array([zmin])
	s.key = 0 if s.zones[0] < 2 else 1   # Altlast: alte Flugbahn-Funktionen
	return s


static func _beat_ms(beatmap: Beatmap, t: float) -> float:
	var bl := 500.0
	var found := false
	for tp in beatmap.timing_points:
		if not tp.uninherited or tp.beat_length <= 0.0:
			continue
		if not found or tp.time <= t:
			bl = tp.beat_length
			found = true
	return bl


## Gegnerschlag (m) und Pausen-Marken je Schlag berechnen.
static func finalize(shots: Array[Shot]) -> void:
	for j in shots.size():
		var s := shots[j]
		s.exit_after = false
		if j == 0:
			s.serve = true
			s.m = s.t - SERVE_LEAD_MS
			continue
		var p := shots[j - 1].end
		var gap := s.t - p
		if gap > BREAK_MS:
			s.serve = true
			s.m = s.t - SERVE_LEAD_MS
			shots[j - 1].exit_after = true
		else:
			s.serve = false
			s.m = p + gap * 0.5


# ---------------------------------------------------------------------------
# Flugbahn
# ---------------------------------------------------------------------------

## Hoehe des Bogens (normiert) aus der Gesamtflugzeit: Lob bei grossem Abstand.
static func arc_for(gap_ms: float) -> float:
	return clampf(gap_ms * 0.00016, 0.03, 0.28)


static func _bez(y0: float, y1: float, s: float, arc: float) -> float:
	return lerpf(y0, y1, s) - 4.0 * arc * s * (1.0 - s)


## Ball zwischen Gegnerschlag m und Ankunft bei Schlag j (t > t_j: faellt weiter
## am Schlaeger vorbei). Gueltig ab t = shots[j].m.
static func pos_in(shots: Array[Shot], j: int, t: float) -> Vector2:
	var s := shots[j]
	var span := maxf(s.t - s.m, 1.0)
	var u := (t - s.m) / span
	var x := lerpf(X_OPP, X_PLAYER, u)
	var gap := span if s.serve else span * 2.0
	var a := arc_for(gap)
	var y_h := hit_y(s.key)
	var fb := F_BOUNCE_ME
	var y := 0.0
	if u < fb:
		y = _bez(Y_OPP, Y_TABLE, u / fb, a * 0.4)
	else:
		y = _bez(Y_TABLE, y_h, (u - fb) / (1.0 - fb), a)
	return Vector2(x, y)


## Zeit des Aufpralls auf der Tischhaelfte des Spielers vor Schlag j.
static func bounce_me_time(shots: Array[Shot], j: int) -> float:
	var s := shots[j]
	return s.m + (s.t - s.m) * F_BOUNCE_ME


## Ball nach Schlag i (Loslassen end) bis zum Gegner. Zeit t in [end, out_end].
static func pos_out(shots: Array[Shot], i: int, t: float) -> Vector2:
	var s := shots[i]
	var m_next := out_end(shots, i)
	var span := maxf(m_next - s.end, 1.0)
	var u := (t - s.end) / span
	var x := lerpf(X_PLAYER, X_OPP, u)
	var a := arc_for(span * 2.0)
	var fb := F_BOUNCE_OPP
	var y := 0.0
	if u < fb:
		y = _bez(hit_y(s.key), Y_TABLE, u / fb, a * 0.5)
	else:
		y = _bez(Y_TABLE, Y_OPP, (u - fb) / (1.0 - fb), a)
	return Vector2(x, y)


## Ende des Ausflugs nach Schlag i: Gegnerschlag des naechsten Schlags oder EXIT_MS.
static func out_end(shots: Array[Shot], i: int) -> float:
	if i + 1 < shots.size() and not shots[i + 1].serve:
		return shots[i + 1].m
	return shots[i].end + EXIT_MS


static func bounce_opp_time(shots: Array[Shot], i: int) -> float:
	var s := shots[i]
	return s.end + (out_end(shots, i) - s.end) * F_BOUNCE_OPP


## Erster Schlag mit t >= time (binaere Suche), shots.size() wenn keiner.
static func first_at_or_after(shots: Array[Shot], time: float) -> int:
	var lo := 0
	var hi := shots.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if shots[mid].t < time:
			lo = mid + 1
		else:
			hi = mid
	return lo


# ---------------------------------------------------------------------------
# Sterne 0..15
# ---------------------------------------------------------------------------

const STAR_HOP_MS := 1000.0
const STAR_DENS_K := 0.11
const STAR_DECAY := 0.95
## Zonenwechsel: Zusatzlast je Zonen-Abstand (Sprung ueber 2-3 Zonen zaehlt mehr) bei
## Abstand unter STAR_JUMP_GAP_MS; Stream: Baelle unter STAR_STREAM_GAP_MS.
const STAR_JUMP_W := 0.16
const STAR_JUMP_GAP_MS := 450.0
const STAR_STREAM_W := 0.25
const STAR_STREAM_GAP_MS := 200.0
const STAR_SMASH_W := 0.7
const STAR_CHARGE_W := 0.45
const STAR_MAX := 15.0
const STAR_KNEE := 11.0
const STAR_STRETCH := 0.7


## Mittlere Zonenlage eines Schlags (Schmetterball: Mitte der beiden Zonen).
static func zone_center(s: Shot) -> float:
	if s.zones.is_empty():
		return float(s.key) * 2.0 + 0.5
	var sum := 0.0
	for z in s.zones:
		sum += float(z)
	return sum / float(s.zones.size())


## Sterne fuer den Song-Browser: Chart bauen und bewerten. Zonenzahl aus den
## Einstellungen (Standard 3), ohne Autoload (Tests) 3 Zonen.
static func stars_of_beatmap(beatmap: Beatmap) -> float:
	var z := 3
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var st: Node = (ml as SceneTree).root.get_node_or_null("Settings")
		if st != null and st.get("rally_zones") != null:
			z = 4 if int(st.get("rally_zones")) == 4 else 3
	return stars(build(beatmap, -1.0, z), z)


## Sterne: je 2-s-Fenster Last (Baelle/s; Zonenspruenge, Streams, Schmetterbaelle und
## Aufladen zaehlen extra), die haertesten Fenster zaehlen am meisten.
static func stars(shots: Array[Shot], zones: int = -1) -> float:
	if shots.size() < 2:
		return 0.0
	# Zonenabstand auf 4 Zonen normieren (3 Zonen haben kuerzere Spruenge).
	var jump_k := 3.0 / float(maxi((zones if zones > 0 else _zones) - 1, 1))
	var t0 := shots[0].t
	var t_end := shots[-1].end
	var n_win := maxi(1, int(ceil((t_end - t0) / STAR_HOP_MS)))
	var load_w := PackedFloat32Array()
	load_w.resize(n_win)
	load_w.fill(0.0)
	var last_c := -1.0
	var last_t := -INF
	for s in shots:
		var w := clampi(int((s.t - t0) / STAR_HOP_MS), 0, n_win - 1)
		var x := 1.0
		var c := zone_center(s)
		var gap := s.t - last_t
		if last_c >= 0.0 and gap < STAR_JUMP_GAP_MS:
			x += STAR_JUMP_W * jump_k * absf(c - last_c)
		if last_c >= 0.0 and gap < STAR_STREAM_GAP_MS:
			x += STAR_STREAM_W
		if s.smash:
			x += STAR_SMASH_W
		if s.is_charge():
			x += STAR_CHARGE_W
		load_w[w] += x
		last_c = c
		last_t = s.end if s.is_charge() else s.t
	var vals: Array[float] = []
	for w in n_win:
		var lw := load_w[w] + (load_w[w - 1] if w > 0 else 0.0)
		var per_s := lw / (2.0 * STAR_HOP_MS / 1000.0)
		vals.append(STAR_DENS_K * pow(per_s, 1.55))
	vals.sort()
	vals.reverse()
	var num := 0.0
	var den := 0.0
	var wt := 1.0
	for v in vals:
		num += v * wt
		den += wt
		wt *= STAR_DECAY
		if wt < 0.001:
			break
	var raw := num / maxf(den, 1e-6)
	if raw > STAR_KNEE:
		raw = STAR_KNEE + (raw - STAR_KNEE) * STAR_STRETCH
	return clampf(raw, 0.0, STAR_MAX)
