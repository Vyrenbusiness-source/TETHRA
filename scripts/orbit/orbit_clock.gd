class_name OrbitClock
extends RefCounted

## Takt-Uhr des Taktkreises: die Hand dreht pro Takt einmal (360 Grad), 12 Uhr
## = Takt-Eins. Segmente kommen aus den roten Timing-Points; ein neuer roter
## Punkt beginnt einen neuen Takt. Takte unter MIN_BAR_MS (1,2 s) drehen mit zwei
## Takten pro Umdrehung (sonst waere die Hand zu schnell; leichte Maps ab 2 s, siehe
## EASY_MIN_BAR_MS). Ohne Timing-Point:
## 120 BPM in 4/4.

const MIN_BAR_MS := 1200.0
## Leichte Maps (wenige Objekte je Sekunde): Hand hoechstens ~0,18 Grad/ms, damit
## erste Maps leichte Erfolge sind (Messung: schwacher Bot scheitert ab ~0,24 Grad/ms).
const EASY_NPS := 2.5
const EASY_MIN_BAR_MS := 2000.0
const DEFAULT_BEAT_MS := 500.0
const DEFAULT_METER := 4

## Segmente: [start_ms, bar_ms (= eine Umdrehung), beats pro Umdrehung].
var segs: Array = []


static func from_beatmap(beatmap: Beatmap) -> OrbitClock:
	var c := OrbitClock.new()
	var min_bar := min_bar_for(beatmap)
	if beatmap != null:
		for tp in OrbitConverter.red_points(beatmap):
			c.segs.append(_seg(float(tp.time), float(tp.beat_length), int(tp.meter), min_bar))
	if c.segs.is_empty():
		c.segs.append(_seg(0.0, DEFAULT_BEAT_MS, DEFAULT_METER, min_bar))
	return c


## Kuerzeste Umdrehung fuer diese Map: leichte Maps (< EASY_NPS Objekte/s) drehen ruhiger.
static func min_bar_for(beatmap: Beatmap) -> float:
	if beatmap == null or beatmap.hit_objects.size() < 2:
		return MIN_BAR_MS
	var objs := beatmap.hit_objects
	var span := (float(objs[objs.size() - 1].time) - float(objs[0].time)) / 1000.0
	if span <= 0.0:
		return MIN_BAR_MS
	return EASY_MIN_BAR_MS if float(objs.size()) / span < EASY_NPS else MIN_BAR_MS


## Feste Uhr (Tests): eine Umdrehung = bar_ms, beats Schlaege.
static func fixed(bar_ms: float, beats: int = 4, start_ms: float = 0.0) -> OrbitClock:
	var c := OrbitClock.new()
	c.segs.append([start_ms, bar_ms, beats])
	return c


static func _seg(t: float, beat_ms: float, meter: int, min_bar: float = MIN_BAR_MS) -> Array:
	var m := maxi(meter, 1)
	var bar := beat_ms * float(m)
	var beats := m
	while bar < min_bar and bar > 0.0:
		bar *= 2.0
		beats *= 2
	return [t, bar, beats]


func _idx(t_ms: float) -> int:
	var k := 0
	for i in segs.size():
		if float(segs[i][0]) <= t_ms:
			k = i
		else:
			break
	return k


func bar_ms_at(t_ms: float) -> float:
	return float(segs[_idx(t_ms)][1])


func beats_at(t_ms: float) -> int:
	return int(segs[_idx(t_ms)][2])


## Drehtempo der Hand in Grad/ms.
func speed_at(t_ms: float) -> float:
	return 360.0 / bar_ms_at(t_ms)


## Winkel der Hand (0 = oben, im Uhrzeigersinn) zur Zeit t_ms.
func angle_at(t_ms: float) -> float:
	var s: Array = segs[_idx(t_ms)]
	return fposmod((t_ms - float(s[0])) / float(s[1]), 1.0) * 360.0


## Nummer des Takts (ab 0 im ersten Segment, danach fortlaufend je Segment-Start
## und Takt) - nur zum Vergleichen: gleiche Zahl = gleiche Umdrehung.
func bar_at(t_ms: float) -> int:
	var i := _idx(t_ms)
	var s: Array = segs[i]
	return i * 100000 + int(floorf((t_ms - float(s[0])) / float(s[1])))


## Beginn des Takts, in dem t_ms liegt.
func bar_start_at(t_ms: float) -> float:
	var s: Array = segs[_idx(t_ms)]
	var k := floorf((t_ms - float(s[0])) / float(s[1]))
	return float(s[0]) + maxf(k, 0.0) * float(s[1])


## Ende (= Beginn des naechsten Takts) des Takts, in dem t_ms liegt. Ein neuer
## roter Punkt beendet den laufenden Takt vorzeitig.
func bar_end_at(t_ms: float) -> float:
	var i := _idx(t_ms)
	var s: Array = segs[i]
	var e := bar_start_at(t_ms) + float(s[1])
	if i + 1 < segs.size():
		e = minf(e, float(segs[i + 1][0]))
	return e


## Phase des Takts (0..1) zur Zeit t_ms.
func phase_at(t_ms: float) -> float:
	return angle_at(t_ms) / 360.0


# --- Orbit "Satelliten" (docs/modes/orbit_satellit.md) -----------------------

## Dauer eines Schlags (ms) zur Zeit t_ms.
func beat_ms_at(t_ms: float) -> float:
	return bar_ms_at(t_ms) / float(maxi(beats_at(t_ms), 1))


## Letzter Beat-Tick <= t_ms (Raster des roten Timing-Points, in dem t_ms liegt).
func beat_tick_at_or_before(t_ms: float) -> float:
	var i := _idx(t_ms)
	var start := float(segs[i][0])
	var beat := beat_ms_at(t_ms)
	if beat <= 0.0:
		return t_ms
	return start + floor((t_ms - start) / beat + 1e-6) * beat
