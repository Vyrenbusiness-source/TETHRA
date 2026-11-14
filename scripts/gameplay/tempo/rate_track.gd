class_name RateTrack
extends RefCounted

## Rate-Verlauf eines Laufs (Tempo-Grundlage fuer Uebung und Turbo).
##
## Eintraege [songzeit_ms, rate], aufsteigend nach Zeit. rate_at(t) = Rate des
## letzten Eintrags mit Zeit <= t (vor dem ersten: 1,0). Alle Map-Zeiten bleiben
## Songzeit; die Uhr laeuft mit rate x Echtzeit (SyncClock.set_rate).
##
## Treffer-Fenster (wie osu!mania): das Fenster einer Note ist in ECHTZEIT gleich
## breit wie bei 1,0x, in Songzeit also Basisfenster x Rate. Grund: der Spieler
## drueckt in Echtzeit; bei 1,5x vergehen in 10 ms Echtzeit 15 ms Songzeit. Ohne
## Skalierung waere jede Rate ueber 1 ein versteckter OD-Anstieg (DT in stable).
## Massgeblich ist die Rate zur NOTENZEIT (rate_at(note.time)): das ist eine
## reine Funktion des Verlaufs und haengt nicht davon ab, in welchem Frame die
## Note gewertet wird. Damit spielt ein Replay exakt nach.
##
## Aenderungen waehrend des Laufs muessen mindestens SCHEDULE_LEAD_MS vor ihrer
## Wirkung angemeldet werden (schedule()): bis dahin ist keine Note mit Zeit >=
## Wirkzeit schon gewertet (groesstes Fenster: Miss 173,5 ms x 2,0 = 347 ms).

const MIN := 0.5
const MAX := 2.0
const STEP := 0.05
## Vorlauf einer Rate-Aenderung (Songzeit), groesser als jedes Fruehfenster.
const SCHEDULE_LEAD_MS := 400.0

var _t := PackedFloat64Array()
var _r := PackedFloat64Array()


## Rate auf das 0,05er-Raster und in 0,5..2,0.
static func snap(rate: float) -> float:
	if is_nan(rate):
		return 1.0
	return clampf(snappedf(rate, STEP), MIN, MAX)


## Rate als Anzeige "1,25x" (Prozent: siehe pct_text).
static func rate_text(rate: float) -> String:
	return UiTheme.fmt_num(rate, 2) + "×"


## Rate als ganze Prozent "125 %".
static func pct_text(rate: float) -> String:
	return "%d %%" % int(round(rate * 100.0))


static func constant(rate: float) -> RateTrack:
	var tr := RateTrack.new()
	tr.set_at(0.0, rate)
	tr._t[0] = -INF
	return tr


## Aus Replay-/Mods-Daten [[t, r], ...]; ungueltig/leer -> null (= 1,0x).
static func from_array(a) -> RateTrack:
	if not (a is Array) or (a as Array).is_empty():
		return null
	var tr := RateTrack.new()
	for e in a:
		if e is Array and (e as Array).size() >= 2:
			var t := float(e[0])
			tr._t.append(-INF if t <= -1.0e12 else t)
			tr._r.append(snap(float(e[1])))
	if tr._t.is_empty():
		return null
	return tr


## Fuer Replay/Mods (JSON-fest: -INF wird -1e15).
func to_array() -> Array:
	var out := []
	for i in _t.size():
		out.append([-1.0e15 if is_inf(_t[i]) else _t[i], _r[i]])
	return out


func size() -> int:
	return _t.size()


func is_empty() -> bool:
	return _t.is_empty()


func time_at(i: int) -> float:
	return _t[i]


func rate_index(i: int) -> float:
	return _r[i]


func rate_at(t_ms: float) -> float:
	var r := 1.0
	for i in _t.size():
		if _t[i] <= t_ms:
			r = _r[i]
		else:
			break
	return r


## Eintrag setzen (ersetzt spaetere Eintraege: der Verlauf wird nur nach vorn
## geschrieben).
func set_at(t_ms: float, rate: float) -> void:
	while not _t.is_empty() and _t[_t.size() - 1] >= t_ms:
		_t.resize(_t.size() - 1)
		_r.resize(_r.size() - 1)
	_t.append(t_ms)
	_r.append(snap(rate))


## Aenderung waehrend des Laufs anmelden: wirkt fruehestens now + Vorlauf.
## Rueckgabe: tatsaechliche Wirkzeit.
func schedule(now_ms: float, at_ms: float, rate: float) -> float:
	var t := maxf(at_ms, now_ms + SCHEDULE_LEAD_MS)
	if not _t.is_empty() and t <= _t[_t.size() - 1]:
		t = _t[_t.size() - 1] + 1.0
	set_at(t, rate)
	return t


## Hoechste Rate im Verlauf ab Songzeit from_ms (Turbo-Ergebnis).
func max_rate(from_ms: float = -INF, to_ms: float = INF) -> float:
	var m := rate_at(from_ms)
	for i in _t.size():
		if _t[i] > from_ms and _t[i] <= to_ms:
			m = maxf(m, _r[i])
	return m


## Rate-Wechsel, deren Wirkzeit in (from_ms, to_ms] liegt (fuer das Audio).
func changes_between(from_ms: float, to_ms: float) -> Array:
	var out := []
	for i in _t.size():
		if _t[i] > from_ms and _t[i] <= to_ms:
			out.append([_t[i], _r[i]])
	return out
