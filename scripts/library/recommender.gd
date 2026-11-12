class_name Recommender
extends RefCounted

## Song-Empfehlungen fuer alle Modi (mania, orbit, rally, dirigent, trace,
## rebound). Rein statisch und deterministisch: gleiche Laeufe + Kandidaten
## + Zeitpunkt -> gleiche Liste. Keine Oberflaeche (kommt als eigener Task).
## Formeln und Grenzen: docs/recommend.md.
##
## Lauf (run): {set, diff, stars, accuracy 0..1, pp (nur Mania, -1 = unbekannt),
##   failed, unranked, grade, date "YYYY-MM-DDTHH:MM:SS"}
## Kandidat: {set, diff, stars, osu_mode (3 = 4K, 0 = Standard; Standard 3),
##   max_pp (optional, Mania: pp bei SS), last_played (optional), best_grade (optional)}

const LEVEL_EASY := "easy"            # Easy: unter dem Komfort-Level
const LEVEL_CHALLENGE := "challenge"  # Challenge: Komfort bis Grenze (Standard)
const LEVEL_PUSH := "push"            # Push: an/ueber der Grenze, Top-Leistung jagen
const LEVELS: Array[String] = ["easy", "challenge", "push"]
const LEVEL_DEFAULT := LEVEL_CHALLENGE

const MODES: Array[String] = ["mania", "orbit", "rally", "dirigent", "trace", "rebound"]

const COMFORT_ACC := 0.97   # Komfort: erwartete Acc >= 97 %
const LIMIT_ACC := 0.915    # Grenze: Acc ~ 91,5 % (Mitte von 90-93 %)
const FAIL_ACC := 0.80      # ein Fail zaehlt hoechstens als 80 % - 5 Punkte
const WEIGHT := 0.95        # Top-Liste: Platz i zaehlt 0,95^i
const K_POINTS := 4.0       # Nicht-Mania: 4 * Sterne^2 * Acc^4
const PRIOR_RUNS := 3.0     # Gewicht der Standardkurve in Laeufen
const MAX_RUNS := 30        # hoechstens so viele juengste Laeufe fuer die Kurve
const TOP_N := 10           # Push: Ziel sind die eigenen Top 10
const RECENT_SEC := 86400   # kuerzlich gespielt: letzte 24 h
const MIN_PUSH_ACC := 0.85  # darunter ist ein Push-Vorschlag aussichtslos
const MAX_PER_SET := 2

## Standardkurve je Modus: {comfort (Sterne), slope (Acc-Verlust je Stern)}.
const DEFAULTS := {
	"mania": {"comfort": 2.5, "slope": 0.020},
	"orbit": {"comfort": 1.5, "slope": 0.020},
	"rally": {"comfort": 1.5, "slope": 0.020},
	"dirigent": {"comfort": 1.5, "slope": 0.020},
	"trace": {"comfort": 1.5, "slope": 0.020},
	"rebound": {"comfort": 1.5, "slope": 0.020},
}
## Mania ohne eigene Daten: pp bei SS ~ MANIA_K * Sterne^2.
const MANIA_K := 10.0


static func normalize_level(level: String) -> String:
	return level if LEVELS.has(level) else LEVEL_DEFAULT


static func normalize_mode(mode: String) -> String:
	return mode if MODES.has(mode) else "mania"


static func level_label(level: String) -> String:
	match level:
		LEVEL_EASY: return TranslationServer.translate("Easy")
		LEVEL_PUSH: return TranslationServer.translate("Push")
	return TranslationServer.translate("Challenge")


## Einheit der Leistung: Mania pp, sonst Punkte.
static func unit(mode: String) -> String:
	return "pp" if normalize_mode(mode) == "mania" else "pts"


## Diff fuer den Modus spielbar? trace/rebound/mania: nur 4K (osu_mode 3);
## orbit/rally/dirigent: 4K und Standard (0).
static func playable(mode: String, osu_mode: int) -> bool:
	if osu_mode == 3:
		return true
	return osu_mode == 0 and ["orbit", "rally", "dirigent"].has(normalize_mode(mode))


# --- Leistung ---

## Leistung eines Laufs: Mania pp, sonst 4 * Sterne^2 * Acc^4. Fail/unranked 0.
static func run_perf(mode: String, run: Dictionary) -> float:
	if bool(run.get("failed", false)) or bool(run.get("unranked", false)):
		return 0.0
	var st: float = float(run.get("stars", -1.0))
	var acc: float = clampf(float(run.get("accuracy", 0.0)), 0.0, 1.0)
	if normalize_mode(mode) == "mania":
		var pp: float = float(run.get("pp", -1.0))
		if pp > 0.0:
			return pp
		if st <= 0.0:
			return 0.0
		return MANIA_K * st * st * pow(acc, 4.0)
	if st <= 0.0:
		return 0.0
	return K_POINTS * st * st * pow(acc, 4.0)


## Gewichtete Summe einer absteigend sortierten Liste: sum(p[i] * 0,95^i).
static func rating_of(sorted_desc: Array) -> float:
	var t := 0.0
	for i in sorted_desc.size():
		t += float(sorted_desc[i]) * pow(WEIGHT, i)
	return t


static func _key(r: Dictionary) -> String:
	return "%s|%s" % [str(r.get("set", "")), str(r.get("diff", ""))]


static func _median(v: Array) -> float:
	var a: Array = v.duplicate()
	a.sort()
	var n := a.size()
	if n == 0:
		return 0.0
	if n % 2 == 1:
		return float(a[n / 2])
	return (float(a[n / 2 - 1]) + float(a[n / 2])) * 0.5


# --- Koennen ---

## Koennen eines Modus aus Laeufen (Reihenfolge egal; sortiert nach date).
## Liefert {mode, n, comfort, limit, slope, kappa, best (key -> perf),
## top (Leistungen absteigend, 1 je Map), rating, runs}.
static func skill(mode: String, runs: Array) -> Dictionary:
	var m := normalize_mode(mode)
	var d: Dictionary = DEFAULTS[m]
	var slope: float = float(d.slope)
	var c0: float = float(d.comfort)
	var valid: Array = []
	for r in runs:
		if r is Dictionary and float(r.get("stars", -1.0)) > 0.0 and not bool(r.get("unranked", false)):
			valid.append(r)
	valid.sort_custom(func(a, b): return str(a.get("date", "")) < str(b.get("date", "")))
	var recent: Array = valid.slice(maxi(0, valid.size() - MAX_RUNS))
	# Jeder Lauf schaetzt ein Komfort-Level: Sterne + Acc-Luecke / Steigung.
	var implied: Array = []
	for r in recent:
		var st: float = float(r.stars)
		var acc: float = clampf(float(r.get("accuracy", 0.0)), 0.0, 1.0)
		if bool(r.get("failed", false)) or str(r.get("grade", "")) == "F":
			acc = minf(acc, FAIL_ACC) - 0.05
		var c: float = st + (acc - COMFORT_ACC) / slope
		implied.append(clampf(c, st - 4.0, st + 3.0))
	var n := implied.size()
	var comfort := c0
	if n > 0:
		comfort = (_median(implied) * n + c0 * PRIOR_RUNS) / (n + PRIOR_RUNS)
	comfort = maxf(comfort, 0.5)
	var limit := comfort + (COMFORT_ACC - LIMIT_ACC) / slope
	# Bestwert je Map (mit Sternen) und Mania-Faktor aus eigenen pp.
	var best: Dictionary = {}
	var ratios: Array = []
	for r in valid:
		var p := run_perf(m, r)
		if p <= 0.0:
			continue
		var k := _key(r)
		if not best.has(k) or p > float(best[k]):
			best[k] = p
		if m == "mania" and float(r.get("pp", -1.0)) > 0.0:
			var acc2: float = float(r.get("accuracy", 0.0))
			if acc2 > 0.5:
				ratios.append(p / (float(r.stars) * float(r.stars) * pow(acc2, 4.0)))
	var top: Array = best.values()
	top.sort()
	top.reverse()
	return {
		"mode": m, "n": n, "comfort": comfort, "limit": limit, "slope": slope,
		"kappa": _median(ratios) if ratios.size() >= 3 else MANIA_K,
		"best": best, "top": top, "rating": rating_of(top), "runs": valid,
	}


## Erwartete Acc bei Sternen: COMFORT_ACC - slope * (stars - comfort), 0,5..0,995.
static func acc_at(sk: Dictionary, stars: float) -> float:
	var a: float = COMFORT_ACC - float(sk.slope) * (stars - float(sk.comfort))
	return clampf(a, 0.5, 0.995)


## Erwartete Leistung. Mania mit max_pp (>0): max_pp * acc^4, sonst kappa * s^2 * acc^4.
static func perf_at(sk: Dictionary, stars: float, acc: float, max_pp: float = -1.0) -> float:
	var a4: float = pow(acc, 4.0)
	if str(sk.mode) == "mania":
		if max_pp > 0.0:
			return max_pp * a4
		return float(sk.kappa) * stars * stars * a4
	return K_POINTS * stars * stars * a4


## Sterne-Bereich [lo, hi] der Stufe.
static func star_range(sk: Dictionary, level: String) -> Vector2:
	var c: float = float(sk.comfort)
	var l: float = float(sk.limit)
	match normalize_level(level):
		LEVEL_EASY: return Vector2(maxf(0.3, c - 1.5), c)
		LEVEL_PUSH: return Vector2(c, l + 1.5)
	return Vector2(c, l)


# --- Vorschlaege ---

static func _unix(s: String) -> int:
	if s == "":
		return -1
	return int(Time.get_unix_time_from_datetime_string(s))


## Jetzt als lokale Unix-Zeit (Eintraege nutzen die lokale Systemzeit).
static func now_local() -> int:
	return _unix(Time.get_datetime_string_from_system())


## Vorschlaege fuer Modus und Stufe, sortiert (beste zuerst), hoechstens n.
## runs: Laeufe des Modus (siehe oben, z.B. runs_from_store()). now: Unix-Zeit
## (0 = jetzt). Rueckgabe: [{set, diff, stars, expected_acc, expected_perf, reason}].
static func suggest(mode: String, level: String, cands: Array, n: int = 5,
		runs: Array = [], now: int = 0) -> Array:
	var m := normalize_mode(mode)
	var lv := normalize_level(level)
	if cands.is_empty() or n <= 0:
		return []
	var sk := skill(m, runs)
	var t_now := now if now > 0 else now_local()
	# Gesperrte Maps: kuerzlich gespielt (24 h) oder SS.
	var blocked: Dictionary = {}
	for r in sk.runs:
		var k := _key(r)
		if str(r.get("grade", "")) == "SS" and not bool(r.get("failed", false)):
			blocked[k] = true
		var t := _unix(str(r.get("date", "")))
		if t > 0 and t_now - t < RECENT_SEC:
			blocked[k] = true
	var rng := star_range(sk, lv)
	var top: Array = sk.top
	var base_rating: float = float(sk.rating)
	var scored: Array = []
	for c in cands:
		if not (c is Dictionary):
			continue
		var st: float = float(c.get("stars", -1.0))
		if st <= 0.0 or not playable(m, int(c.get("osu_mode", 3))):
			continue
		var k := _key(c)
		if blocked.has(k) or str(c.get("best_grade", "")) == "SS":
			continue
		var lp := _unix(str(c.get("last_played", "")))
		if lp > 0 and t_now - lp < RECENT_SEC:
			continue
		if st < rng.x - 0.0001 or st > rng.y + 0.0001:
			continue
		var acc := acc_at(sk, st)
		var perf := perf_at(sk, st, acc, float(c.get("max_pp", -1.0)))
		var score := 0.0
		var reason := ""
		var u := unit(m)
		if lv == LEVEL_PUSH:
			if acc < MIN_PUSH_ACC:
				continue
			var old: float = float(sk.best.get(k, 0.0))
			if perf <= old:
				continue
			var lst: Array = top.duplicate()
			if old > 0.0:
				lst.erase(old)
			lst.append(perf)
			lst.sort()
			lst.reverse()
			var rank := lst.find(perf) + 1
			if rank > TOP_N:
				continue
			var gain := rating_of(lst) - base_rating
			score = gain
			if rank == 1 and m == "mania":
				reason = TranslationServer.translate("new top pp: +%d %s") % [roundi(gain), u]
			else:
				reason = TranslationServer.translate("+%d %s, would be top %d") % [roundi(gain), u, rank]
		elif lv == LEVEL_EASY:
			var tgt: float = float(sk.comfort) - 0.8
			score = -absf(st - tgt)
			reason = TranslationServer.translate("Easy: about %d %% expected") % roundi(acc * 100.0)
		else:
			var tgt2: float = float(sk.comfort) + 0.4 * (float(sk.limit) - float(sk.comfort))
			score = -absf(st - tgt2)
			reason = TranslationServer.translate("Challenge: about %d %% expected") % roundi(acc * 100.0)
		scored.append({
			"set": c.get("set", ""), "diff": c.get("diff", ""), "stars": st,
			"expected_acc": acc, "expected_perf": perf, "reason": reason,
			"_score": score,
		})
	# Wertung absteigend, dann Set/Diff als Tiebreak (deterministisch).
	scored.sort_custom(func(a, b):
		if not is_equal_approx(float(a._score), float(b._score)):
			return float(a._score) > float(b._score)
		if str(a.set) != str(b.set):
			return str(a.set) < str(b.set)
		return str(a.diff) < str(b.diff))
	# Abwechslung: erst eine Map je Set, dann (bis MAX_PER_SET) auffuellen.
	var out: Array = []
	var per_set: Dictionary = {}
	for cap in range(1, MAX_PER_SET + 1):
		for s in scored:
			if out.size() >= n:
				break
			var sid := str(s.set)
			if int(per_set.get(sid, 0)) >= cap or out.has(s):
				continue
			per_set[sid] = int(per_set.get(sid, 0)) + 1
			out.append(s)
	for s in out:
		s.erase("_score")
	return out


# --- Anbindung an ScoreStore ---

## Laeufe eines Modus aus ScoreStore (Bestwerte + letzte Laeufe, ohne Duplikate).
## stars_of: Callable(entry: Dictionary) -> float (-1 = unbekannt); entry hat
## osz_file, version, accuracy, pp, ... Fehlt stars_of, zaehlt entry.stars.
static func runs_from_store(mode: String, stars_of: Callable = Callable()) -> Array:
	var m := normalize_mode(mode)
	var sid := "" if m == "mania" else m
	var entries: Array = ScoreStore.best_plays(500, sid)
	entries.append_array(ScoreStore.recent_plays(ScoreStore.RECENT_CAP, sid))
	var seen: Dictionary = {}
	var out: Array = []
	for e in entries:
		var ed: Dictionary = e
		var stars: float = float(ed.get("stars", -1.0))
		if stars_of.is_valid():
			stars = float(stars_of.call(ed))
		var run := {
			"set": str(ed.get("osz_file", "")), "diff": str(ed.get("version", "")),
			"stars": stars, "accuracy": float(ed.get("accuracy", 0.0)),
			"pp": float(ed.get("pp", -1.0)), "failed": bool(ed.get("failed", false)),
			"unranked": bool(ed.get("unranked", false)),
			"grade": str(ed.get("grade", "")), "date": str(ed.get("date", "")),
		}
		var dk := "%s|%s|%s" % [_key(run), run.date, run.accuracy]
		if seen.has(dk):
			continue
		seen[dk] = true
		out.append(run)
	return out
