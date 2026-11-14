class_name PracticeSession
extends RefCounted

## Uebungsmodus (Plan Punkt 3), reine Logik: Abschnitt A..B in Schleife,
## Tempo stufenweise von start_rate bis target_rate (Schritt step), erhoeht
## nach jedem sauberen Durchlauf (kein Miss). Unranked, keine Online-Scores.
##
## Uebergabe Song-Browser -> Spielszene: PracticeSession.current (statisch,
## ueberlebt Szenenwechsel und Neustart mit R; der Song-Browser loescht ihn).

static var current: PracticeSession = null

const STEP_CHOICES := [0.05, 0.10, 0.15, 0.20]

var a_ms := 0.0
var b_ms := 0.0
var start_rate := 0.8
var target_rate := 1.0
var step := 0.05
var keep_pitch := false
## Tempo der laufenden/naechsten Schleife.
var rate := 0.8
var loops := 0
var clean_loops := 0
var streak := 0


static func begin() -> PracticeSession:
	current = PracticeSession.new()
	return current


static func clear() -> void:
	current = null


static func active() -> bool:
	return current != null


## Abschnitt setzen (A < B, mindestens 1 s); setzt das Tempo auf den Start.
func set_range(a: float, b: float) -> void:
	if b < a:
		var x := a
		a = b
		b = x
	a_ms = maxf(a, 0.0)
	b_ms = maxf(b, a_ms + 1000.0)
	reset_tempo()


func set_rates(p_start: float, p_target: float, p_step: float) -> void:
	start_rate = RateTrack.snap(p_start)
	target_rate = maxf(RateTrack.snap(p_target), start_rate)
	step = clampf(snappedf(p_step, 0.05), 0.05, 0.5)
	reset_tempo()


func reset_tempo() -> void:
	rate = start_rate
	streak = 0


func has_range() -> bool:
	return b_ms > a_ms


## Schleife ausgewertet. Rueckgabe {clean, rate_before, rate, reached}.
func after_loop(misses: int) -> Dictionary:
	loops += 1
	var before := rate
	var is_clean := misses == 0
	if is_clean:
		clean_loops += 1
		streak += 1
		if rate < target_rate - 0.001:
			rate = minf(RateTrack.snap(rate + step), target_rate)
	else:
		streak = 0
	return {"clean": is_clean, "rate_before": before, "rate": rate,
		"reached": is_clean and before >= target_rate - 0.001}
