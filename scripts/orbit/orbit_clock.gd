class_name OrbitClock
extends RefCounted

## Takt-Uhr des Taktkreises: die Hand dreht pro Takt einmal (360 Grad), 12 Uhr
## = Takt-Eins. Segmente kommen aus den roten Timing-Points; ein neuer roter
## Punkt beginnt einen neuen Takt. Takte unter MIN_BAR_MS (1,2 s) drehen mit zwei
## Takten pro Umdrehung (sonst waere die Hand zu schnell). Ohne Timing-Point:
## 120 BPM in 4/4.

const MIN_BAR_MS := 1200.0
const DEFAULT_BEAT_MS := 500.0
const DEFAULT_METER := 4

## Segmente: [start_ms, bar_ms (= eine Umdrehung), beats pro Umdrehung].
var segs: Array = []


static func from_beatmap(beatmap: Beatmap) -> OrbitClock:
	var c := OrbitClock.new()
	if beatmap != null:
		for tp in OrbitConverter.red_points(beatmap):
			c.segs.append(_seg(float(tp.time), float(tp.beat_length), int(tp.meter)))
	if c.segs.is_empty():
		c.segs.append(_seg(0.0, DEFAULT_BEAT_MS, DEFAULT_METER))
	return c


## Feste Uhr (Tests): eine Umdrehung = bar_ms, beats Schlaege.
static func fixed(bar_ms: float, beats: int = 4, start_ms: float = 0.0) -> OrbitClock:
	var c := OrbitClock.new()
	c.segs.append([start_ms, bar_ms, beats])
	return c


static func _seg(t: float, beat_ms: float, meter: int) -> Array:
	var m := maxi(meter, 1)
	var bar := beat_ms * float(m)
	var beats := m
	while bar < MIN_BAR_MS and bar > 0.0:
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
