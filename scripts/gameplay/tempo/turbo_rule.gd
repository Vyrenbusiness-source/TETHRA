class_name TurboRule
extends RefCounted

## Turbo (Plan Punkt 15): das Tempo steigt nach jedem fehlerfreien Abschnitt
## um 5 % und faellt bei einem Miss auf das Starttempo zurueck. Ergebnis =
## erreichtes Hoechsttempo + Score, eigene lokale Rangliste (TurboStore).
##
## Abschnitte: Grenzen an Kiai-Anfang/-Ende und an Breaks (Luecke > 4,5 s wie
## die Break-Anzeige), Abschnitte laenger als 16 Takte werden in 8-Takt-Stuecke
## geteilt; ohne Kiai/Breaks also je 8 Takte. Abschnitte ohne Note zaehlen nicht.
##
## Rate-Wechsel laufen ueber RateTrack.schedule (Vorlauf 400 ms): Fenster einer
## Note = Basis x Rate zur Notenzeit, Replays tragen den Verlauf (Mods "TB_track")
## und spielen ihn exakt nach, statt ihn neu zu entscheiden.

const STEP := 0.05
const START := 1.0
## Luecke zwischen Notenende und naechster Note, ab der ein Break zaehlt (ms).
const BREAK_GAP_MS := 4500.0
const BARS_PER_SECTION := 8
const MAX_BARS := 16

## Abschnitte {a, b, i0, i1}: Songzeit [a, b), Notenindex [i0, i1).
var secs: Array = []
var track: RateTrack
var start_rate := START
## Anzahl fehlerfreier Abschnitte, Rueckfaelle.
var clean := 0
var fallbacks := 0
var _k := 0
var _scan := 0
var _miss_sec := {}


func setup(bm: Beatmap, p_start: float = START) -> void:
	start_rate = RateTrack.snap(p_start)
	secs = sections(bm)
	track = RateTrack.constant(start_rate)
	clean = 0
	fallbacks = 0
	_k = 0
	_scan = secs[0].i0 if not secs.is_empty() else 0
	_miss_sec.clear()


## Taktlaenge (ms) zur Zeit t: Beatlaenge x Taktart des aktiven roten Punkts.
static func bar_ms(bm: Beatmap, t: float) -> float:
	var pick: TimingPoint = null
	for tp in bm.timing_points:
		if not tp.uninherited or tp.beat_length <= 0.0:
			continue
		if pick == null or tp.time <= t + 1.0:
			pick = tp
	if pick == null:
		return 2000.0
	return pick.beat_length * float(maxi(pick.meter, 1))


static func sections(bm: Beatmap) -> Array:
	var objs := bm.hit_objects
	if objs.is_empty():
		return []
	var first: float = objs[0].time
	var last_end := -INF
	for o in objs:
		last_end = maxf(last_end, o.end_time())
	var stop := last_end + 1.0
	var cuts: Array[float] = []
	for iv in bm.kiai_intervals:
		for edge in [float(iv.start), float(iv.end)]:
			if edge > first and edge < stop:
				cuts.append(edge)
	var prev_end: float = objs[0].end_time()
	for i in range(1, objs.size()):
		if objs[i].time - prev_end > BREAK_GAP_MS:
			cuts.append((prev_end + objs[i].time) * 0.5)
		prev_end = maxf(prev_end, objs[i].end_time())
	cuts.sort()
	var bounds: Array[float] = [first]
	for c in cuts:
		if c - bounds.back() > 1.0:
			bounds.append(c)
	if stop - bounds.back() > 1.0:
		bounds.append(stop)
	else:
		bounds[bounds.size() - 1] = stop
	# Lange Stuecke in 8-Takt-Abschnitte teilen (Rest unter 4 Takten haengt am letzten).
	var ranges: Array = []
	for bi in bounds.size() - 1:
		var a: float = bounds[bi]
		var b: float = bounds[bi + 1]
		var bar := bar_ms(bm, a)
		if b - a <= MAX_BARS * bar:
			ranges.append([a, b])
			continue
		var x := a
		while b - x > BARS_PER_SECTION * bar * 1.5:
			ranges.append([x, x + BARS_PER_SECTION * bar])
			x += BARS_PER_SECTION * bar
			bar = bar_ms(bm, x)
		ranges.append([x, b])
	var out: Array = []
	var i := 0
	for r in ranges:
		var i0 := i
		while i < objs.size() and objs[i].time < float(r[1]):
			i += 1
		if i > i0:
			out.append({"a": float(r[0]), "b": float(r[1]), "i0": i0, "i1": i})
	return out


## Abschnitt zur Notenzeit t (-1 = keiner).
func section_of(t: float) -> int:
	for k in secs.size():
		if t >= float(secs[k].a) and t < float(secs[k].b):
			return k
	return -1


## Zuletzt angemeldete Rate (auch wenn sie noch nicht wirkt).
func target_rate() -> float:
	return track.rate_at(INF)


## Ein Miss (Note mit Zeit note_t, bemerkt bei Songzeit now_ms): Abschnitt
## gilt als nicht fehlerfrei, das Tempo faellt auf das Starttempo zurueck.
func on_miss(note_t: float, now_ms: float) -> void:
	var k := section_of(note_t)
	if k >= 0:
		_miss_sec[k] = true
	if target_rate() > start_rate + 0.001:
		track.schedule(now_ms, now_ms, start_rate)
		fallbacks += 1


## Pro Frame: fertig gewertete Abschnitte auswerten (is_judged: Callable(idx)).
func tick(now_ms: float, is_judged: Callable) -> void:
	while _k < secs.size():
		var s: Dictionary = secs[_k]
		_scan = maxi(_scan, int(s.i0))
		while _scan < int(s.i1) and bool(is_judged.call(_scan)):
			_scan += 1
		if _scan < int(s.i1):
			return
		if not _miss_sec.has(_k):
			clean += 1
			var up := RateTrack.snap(target_rate() + STEP)
			if up > target_rate() + 0.001:
				track.schedule(now_ms, float(s.b), up)
		_k += 1


## Erreichtes Hoechsttempo: hoechste Rate, die vor dem Ende (letzte Note bzw.
## Fail-Zeitpunkt) wirklich galt.
func peak_rate(end_ms: float) -> float:
	return track.max_rate(-INF, end_ms)


func sections_done() -> int:
	return _k
