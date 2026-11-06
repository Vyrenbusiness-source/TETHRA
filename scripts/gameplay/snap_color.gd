class_name SnapColor
extends RefCounted

## Noten nach Beat-Teilung faerben (Timing-Snap wie osu!mania / Quaver).
## divisor_for: Snap relativ zur zugehoerigen roten Linie. color_for: ruhige Palette.

const DIVISORS: Array[int] = [1, 2, 3, 4, 6, 8, 12, 16]
const TOL_MS := 2.0 ## absolute Toleranz
const TOL_BEAT := 1.0 / 24.0 ## Toleranz darf nie groesser als 1/24 Beat sein
const MIX_THEME := 0.12 ## wie stark das Theme die Palette tönt

## Gleiche Helligkeit, gedaempfte Saettigung.
const PALETTE := {
	1: Color("6fd08c"), ## Mintgruen (Koralle war mit Miss-Rot verwechselbar)
	2: Color("5f8ee8"), ## Blau
	3: Color("a57be8"), ## Violett
	4: Color("e0bd58"), ## Gelb-Gold
	6: Color("e87bb0"), ## Pink
	8: Color("e8955a"), ## Orange
	12: Color("55cdc4"), ## Tuerkis
	16: Color("d6d9de"), ## Grau-Weiss
}


## Snap-Teiler (1,2,3,4,6,8,12,16) fuer eine Note bei t_ms. Ohne Treffer 16.
static func divisor_for(t_ms: float, timing_points: Array) -> int:
	var red_t := 0.0
	var bl := 0.0
	var found := false
	var first_t := INF
	var first_bl := 0.0
	for tp in timing_points:
		if not tp.uninherited or tp.beat_length <= 0.0:
			continue
		if tp.time < first_t:
			first_t = tp.time
			first_bl = tp.beat_length
		if tp.time <= t_ms + TOL_MS and (not found or tp.time >= red_t):
			red_t = tp.time
			bl = tp.beat_length
			found = true
	if not found:
		if first_bl <= 0.0:
			return 16
		red_t = first_t
		bl = first_bl
	var tol := minf(TOL_MS, bl * TOL_BEAT)
	var x := (t_ms - red_t) / bl ## Beats seit roter Linie
	for d in DIVISORS:
		var pos := x * float(d)
		var off_ms := absf(pos - roundf(pos)) * bl / float(d)
		if off_ms <= tol:
			return d
	return 16


## Farbe fuer einen Teiler; theme tönt leicht, Helligkeit bleibt stabil.
static func color_for(divisor: int, theme: Color) -> Color:
	var base: Color = PALETTE.get(divisor, PALETTE[16])
	var c := base.lerp(theme, MIX_THEME)
	c.a = base.a
	return c


## Teiler aller hit_objects einmalig berechnen.
static func precompute(beatmap) -> PackedInt32Array:
	var out := PackedInt32Array()
	if beatmap == null:
		return out
	var objs: Array = beatmap.hit_objects
	out.resize(objs.size())
	for i in objs.size():
		out[i] = divisor_for(float(objs[i].time), beatmap.timing_points)
	return out
