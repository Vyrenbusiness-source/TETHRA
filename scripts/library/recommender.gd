class_name Recommender
extends RefCounted

## Song-Empfehlungen fuer alle Modi (mania, orbit, rally, dirigent, trace,
## rebound). Rein statisch und deterministisch: gleiche Laeufe + Kandidaten
## + Zeitpunkt -> gleiche Liste. Oberflaeche: song_select.gd ("For you").
## Formeln und Grenzen: docs/recommend.md.
##
## Lauf (run): {set, diff, stars, accuracy 0..1, pp (nur Mania, -1 = unbekannt),
##   failed, unranked, grade, date "YYYY-MM-DDTHH:MM:SS"}
## Kandidat: {set, diff, stars, osu_mode (3 = 4K, 0 = Standard; Standard 3),
##   max_pp (optional, Mania: pp bei SS), last_played (optional), best_grade (optional),
##   artist/title/mapper/genre/language/tags/bpm/length/style/sv (optional, fuer
##   Stilprofil, Stil-Bonus und Grund)}

const LEVEL_EASY := "easy"            # Easy: unter dem Komfort-Level
const LEVEL_CHALLENGE := "challenge"  # Challenge: Komfort bis Grenze (Standard)
const LEVEL_PUSH := "push"            # Push: an/ueber der Grenze, Top-Leistung jagen
const LEVELS: Array[String] = ["easy", "challenge", "push"]
const LEVEL_DEFAULT := LEVEL_CHALLENGE

const MODES: Array[String] = ["mania", "orbit", "rally", "dirigent", "trace", "rebound"]

const PLAY_ACC := 0.90      # Spielbereich: typische Acc am eigenen Level (Mitte von Rang B bis A)
const PLAY_LO := 0.85       # Acc im Band B..A verschiebt das Level nicht
const PLAY_HI := 0.95
const MIN_PUSH_ACC := 0.80  # darunter ist ein Push-Vorschlag aussichtslos (Mania-pp ~ 0)
const ACC_SHIFT := 0.8      # Acc verschiebt das Level eines Laufs hoechstens um +-0,8 Sterne
const FAIL_DROP := 1.0      # Fehlschlag/Abbruch: Level hoechstens Sterne - 1
const FAIL_WEIGHT := 0.5    # Fehlschlaege zaehlen halb (Abbrueche sagen wenig)
const HALF_LIFE_DAYS := 45.0  # Laeufe verlieren je 45 Tage Abstand zum juengsten Lauf die Haelfte
const PRIOR_RUNS := 3.0     # Gewicht der Standardkurve in Laeufen
const MAX_RUNS := 60        # hoechstens so viele juengste Laeufe fuer die Kurve
const SLOPE_MIN := 0.03     # Acc-Verlust je Stern, angepasste Steigung in diesen Grenzen
const SLOPE_MAX := 0.15
const SLOPE_PRIOR := 8.0    # Standard-Steigung zaehlt wie 8 Laeufe
const LIFT_MAX := 0.03      # Push: guter Tag hoechstens +3 % ueber der Kurve
const LIFT_DEFAULT := 0.015
const WEIGHT := 0.95        # Top-Liste: Platz i zaehlt 0,95^i
const K_POINTS := 4.0       # Nicht-Mania: 4 * Sterne^2 * Acc^4
const TOP_N := 10           # Push: Ziel sind die eigenen Top 10
const RECENT_SEC := 86400   # kuerzlich gespielt: letzte 24 h
const MAX_PER_SET := 2
const MAX_PER_ARTIST := 2
const STYLE_W := 0.3        # Stil-Bonus: 1,0 Passung wiegt 0,3 Sterne Abstand (Push: +30 % Gewinn)
const STYLE_MIN_MAPS := 5   # Vorlieben erst ab 5 gespielten Maps mit Merkmalen
const STYLE_SHOW := 0.45    # Grund ("fits: ...") erst ab dieser Passung
const NOVELTY_W := 0.12     # je Mal schon gezeigt (ohne Lauf): 0,12 Sterne Abstand
const NOVELTY_CAP := 4      # hoechstens 4 Mal zaehlen
const PAGE_MAX := 6         # "Show more": hoechstens so viele Seiten
const ONLINE_STAR_PAD := 0.15  # Online-Suche: Sterne-Bereich etwas weiter
const LIKE_MAX := 22        # "like <Titel>": Titel hoechstens so lang
const ONLINE_TTL := 43200   # Online-Antwort 12 h gueltig (eine Anfrage je Suche)
const ONLINE_RETRY := 600   # nach einem Fehler fruehestens in 10 min wieder
const ONLINE_PAGES := 2     # hoechstens 2 Mirror-Seiten je Suche
const ONLINE_KEEP := 8      # so viele Suchen bleiben im Cache

## Stufen relativ zum Level P (Sterne): [lo, hi] und Ziel.
const EASY_LO := -1.3
const EASY_HI := -0.3
const EASY_FLOOR := 1.0     # Easy reicht immer mindestens bis 1 Stern (Anfaenger)
const EASY_TARGET := -0.6
const CHALLENGE_LO := 0.0
const CHALLENGE_HI := 0.6
const CHALLENGE_TARGET := 0.3
const PUSH_LO := 0.4
const PUSH_HI := 1.3
const PUSH_STEP := 0.6      # Push ohne Top-10-Chance: naechster Schritt bei P + 0,6
const PUSH_STEP_HI := 1.0

## Standardkurve je Modus: {comfort (Level in Sternen), slope (Acc-Verlust je Stern)}.
const DEFAULTS := {
	"mania": {"comfort": 2.0, "slope": 0.07},
	"orbit": {"comfort": 1.5, "slope": 0.07},
	"rally": {"comfort": 1.5, "slope": 0.07},
	"dirigent": {"comfort": 1.5, "slope": 0.07},
	"trace": {"comfort": 1.5, "slope": 0.07},
	"rebound": {"comfort": 1.5, "slope": 0.07},
}
## Mania-pp wie rosu-pp: kappa * max(Sterne - 0,15, 0,05)^2,2 * max(0, 5 * Acc - 4).
const MANIA_K := 6.5

## Stil-Merkmale (Anteile 0..1) und ihre Namen im Grund-Text.
const STYLE_LABELS := {
	"stream": "Streams", "jumpstream": "Jumpstream", "jack": "Jacks",
	"chord": "Chords", "hold": "Long notes", "jumps": "Jumps", "dense": "Dense patterns",
}
## Genre und Sprache aus Tags/Quelle einer Map (kleingeschriebene Woerter bzw.
## Wortfolgen). Genre-Namen wie bei osu! (englisch, klein).
const GENRE_WORDS := {
	"electronic": ["electronic", "edm", "dnb", "drum and bass", "dubstep", "techno", "trance", "house",
		"hardcore", "speedcore", "breakcore", "chiptune", "electro", "artcore", "hardstyle", "psytrance", "eurobeat"],
	"rock": ["rock", "punk", "emo", "post-rock", "alternative", "j-rock", "jrock", "indie"],
	"metal": ["metal", "metalcore", "deathcore", "djent"],
	"pop": ["pop", "j-pop", "jpop", "k-pop", "kpop", "idol"],
	"anime": ["anime", "opening", "ending", "tv size"],
	"video game": ["touhou", "videogame", "video game", "game", "ost", "soundtrack", "bms", "arcade",
		"konami", "sdvx", "maimai", "chunithm", "cytus", "deemo", "arcaea", "beatmania", "iidx"],
	"hip hop": ["hip hop", "hip-hop", "hiphop", "rap", "trap"],
	"classical": ["classical", "piano", "orchestra", "orchestral", "symphony"],
	"jazz": ["jazz", "swing", "funk"],
	"folk": ["folk", "celtic"],
}
const LANGUAGE_WORDS := {
	"japanese": ["japanese", "j-pop", "jpop", "j-rock", "jrock", "vocaloid", "anime", "utaite", "touhou", "miku"],
	"korean": ["korean", "k-pop", "kpop"],
	"english": ["english"],
	"chinese": ["chinese", "c-pop", "mandarin"],
	"instrumental": ["instrumental"],
}


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

## Mania-pp-Form (rosu-pp): kappa * max(s - 0,15, 0,05)^2,2 * max(0, 5a - 4).
static func mania_pp(kappa: float, stars: float, acc: float) -> float:
	return kappa * pow(maxf(stars - 0.15, 0.05), 2.2) * acc_factor(acc)


## Acc-Anteil der Mania-pp: 0 bei 80 %, 1 bei 100 %.
static func acc_factor(acc: float) -> float:
	return maxf(0.0, 5.0 * clampf(acc, 0.0, 1.0) - 4.0)


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
		return mania_pp(MANIA_K, st, acc)
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


## Gewichtetes Quantil: pairs = [[Wert, Gewicht], ...], q 0..1.
static func _wquantile(pairs: Array, q: float) -> float:
	if pairs.is_empty():
		return 0.0
	var a: Array = pairs.duplicate()
	a.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var total := 0.0
	for p in a:
		total += float(p[1])
	var acc := 0.0
	for p in a:
		acc += float(p[1])
		if acc >= total * q - 0.000001:
			return float(p[0])
	return float(a[a.size() - 1][0])


static func _failed(r: Dictionary) -> bool:
	return bool(r.get("failed", false)) or str(r.get("grade", "")) == "F" \
			or float(r.get("accuracy", 0.0)) <= 0.01


# --- Koennen ---

## Koennen eines Modus aus Laeufen (Reihenfolge egal; sortiert nach date).
## Level P (comfort) = typischer Spielbereich: Sterne, bei denen der Spieler
## Rang B bis A (85..95 %) erreicht. Gewichteter Median ueber die juengsten
## Laeufe von Sterne + Acc-Abstand zum Band / slope (hoechstens +-0,8; im Band
## 0), Fehlschlaege Sterne - 1.
## Gewicht 0,5^(Abstand zum juengsten Lauf / 45 Tage). Steigung aus den Daten,
## wenn die Sterne genug streuen. Liefert {mode, n, comfort, limit, slope,
## lift, kappa, best (key -> perf), top (absteigend, 1 je Map), rating, runs}.
static func skill(mode: String, runs: Array) -> Dictionary:
	var m := normalize_mode(mode)
	var d: Dictionary = DEFAULTS[m]
	var c0: float = float(d.comfort)
	var valid: Array = []
	var seen: Dictionary = {}
	for r in runs:
		if not (r is Dictionary) or float(r.get("stars", -1.0)) <= 0.0 or bool(r.get("unranked", false)):
			continue
		var dk := "%s|%s|%s" % [_key(r), str(r.get("date", "")), str(r.get("accuracy", 0.0))]
		if seen.has(dk):
			continue
		seen[dk] = true
		valid.append(r)
	valid.sort_custom(func(a, b):
		var da := str(a.get("date", ""))
		var db := str(b.get("date", ""))
		if da != db:
			return da < db
		return _key(a) < _key(b))
	var recent: Array = valid.slice(maxi(0, valid.size() - MAX_RUNS))
	var newest := -1
	if not recent.is_empty():
		newest = _unix(str(recent[recent.size() - 1].get("date", "")))
	var ws: Array = []
	for r in recent:
		var t := _unix(str(r.get("date", "")))
		var age := float(newest - t) / 86400.0 if t > 0 and newest > 0 else 0.0
		ws.append(pow(0.5, maxf(age, 0.0) / HALF_LIFE_DAYS))
	# Steigung: gewichtete Regression Acc ueber Sterne (nur gewertete Laeufe).
	var slope: float = float(d.slope)
	var sw := 0.0
	var ss := 0.0
	var sa := 0.0
	var nf := 0
	for i in recent.size():
		if _failed(recent[i]):
			continue
		nf += 1
		sw += ws[i]
		ss += ws[i] * float(recent[i].stars)
		sa += ws[i] * float(recent[i].accuracy)
	if nf >= 8 and sw > 0.0:
		var ms := ss / sw
		var ma := sa / sw
		var vs := 0.0
		var cv := 0.0
		for i in recent.size():
			if _failed(recent[i]):
				continue
			var ds: float = float(recent[i].stars) - ms
			vs += ws[i] * ds * ds
			cv += ws[i] * ds * (float(recent[i].accuracy) - ma)
		vs /= sw
		cv /= sw
		if vs >= 0.09:
			var fit := clampf(-cv / vs, SLOPE_MIN, SLOPE_MAX)
			slope = (fit * nf + slope * SLOPE_PRIOR) / (nf + SLOPE_PRIOR)
	# Level: gewichteter Median der Einzelschaetzungen, mit Standard gemischt.
	var pairs: Array = []
	var wsum := 0.0
	for i in recent.size():
		var r: Dictionary = recent[i]
		var st: float = float(r.stars)
		var w: float = ws[i]
		var c: float
		if _failed(r):
			c = st - FAIL_DROP
			w *= FAIL_WEIGHT
		else:
			var acc: float = clampf(float(r.get("accuracy", 0.0)), 0.0, 1.0)
			var gap := 0.0
			if acc > PLAY_HI:
				gap = acc - PLAY_HI
			elif acc < PLAY_LO:
				gap = acc - PLAY_LO
			c = st + clampf(gap / slope, -ACC_SHIFT, ACC_SHIFT)
		pairs.append([c, w])
		wsum += w
	var comfort := c0
	if wsum > 0.0:
		comfort = (_wquantile(pairs, 0.5) * wsum + c0 * PRIOR_RUNS) / (wsum + PRIOR_RUNS)
	comfort = maxf(comfort, 0.5)
	# Guter Tag: oberes Quartil der Abweichung von der Kurve (Push).
	var res: Array = []
	for i in recent.size():
		if _failed(recent[i]):
			continue
		var st2: float = float(recent[i].stars)
		var curve := PLAY_ACC + slope * (comfort - st2)
		res.append([float(recent[i].accuracy) - curve, ws[i]])
	var lift := LIFT_DEFAULT
	if res.size() >= 5:
		lift = clampf(_wquantile(res, 0.75), 0.0, LIFT_MAX)
	# Bestwert je Map und Mania-Faktor aus eigenen pp.
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
			if acc2 >= 0.85:
				ratios.append(p / mania_pp(1.0, float(r.stars), acc2))
	var top: Array = best.values()
	top.sort()
	top.reverse()
	return {
		"mode": m, "n": recent.size(), "comfort": comfort, "limit": comfort + PUSH_HI,
		"slope": slope, "lift": lift,
		"kappa": _median(ratios) if ratios.size() >= 3 else MANIA_K,
		"best": best, "top": top, "rating": rating_of(top), "runs": valid,
	}


## Erwartete Acc bei Sternen: PLAY_ACC + slope * (comfort - stars), 0,5..0,995.
static func acc_at(sk: Dictionary, stars: float) -> float:
	var a: float = PLAY_ACC + float(sk.slope) * (float(sk.comfort) - stars)
	return clampf(a, 0.5, 0.995)


## Push: Acc an einem guten Tag (Kurve + oberes Quartil, hoechstens +3 %).
static func push_acc_at(sk: Dictionary, stars: float) -> float:
	return clampf(acc_at(sk, stars) + float(sk.get("lift", LIFT_DEFAULT)), 0.5, 0.995)


## Erwartete Leistung. Mania mit max_pp (>0): max_pp * (5a - 4), sonst
## kappa * (s - 0,15)^2,2 * (5a - 4); andere Modi 4 * s^2 * a^4.
static func perf_at(sk: Dictionary, stars: float, acc: float, max_pp: float = -1.0) -> float:
	if str(sk.mode) == "mania":
		if max_pp > 0.0:
			return max_pp * acc_factor(acc)
		return mania_pp(float(sk.kappa), stars, acc)
	return K_POINTS * stars * stars * pow(acc, 4.0)


## Sterne-Bereich [lo, hi] der Stufe.
static func star_range(sk: Dictionary, level: String) -> Vector2:
	var c: float = float(sk.comfort)
	match normalize_level(level):
		LEVEL_EASY: return Vector2(maxf(0.3, c + EASY_LO), maxf(c + EASY_HI, EASY_FLOOR))
		LEVEL_PUSH: return Vector2(c + PUSH_LO, c + PUSH_HI)
	return Vector2(c + CHALLENGE_LO, c + CHALLENGE_HI)


# --- Stil ---

## Mania-Stil aus der Notenfolge: notes = [[Zeit ms, Spalte, Hold], ...].
## Anteile 0..1: stream (Einzelnoten dicht), jumpstream (2er-Akkorde dicht),
## jack (gleiche Spalte kurz hintereinander), chord (3+ Noten), hold (Long Notes).
static func mania_style(notes: Array) -> Dictionary:
	var groups: Array = []  # [Zeit, {Spalte: true}]
	var holds := 0
	var a: Array = notes.duplicate()
	a.sort_custom(func(x, y): return float(x[0]) < float(y[0]) or \
			(float(x[0]) == float(y[0]) and int(x[1]) < int(y[1])))
	for nt in a:
		if bool(nt[2]):
			holds += 1
		var t: float = float(nt[0])
		if groups.is_empty() or t - float(groups[groups.size() - 1][0]) > 2.0:
			groups.append([t, {}])
		groups[groups.size() - 1][1][int(nt[1])] = true
	var g := groups.size()
	if g < 2:
		return {}
	var stream := 0
	var js := 0
	var jack := 0
	var chord := 0
	for i in g:
		var cols: Dictionary = groups[i][1]
		if cols.size() >= 3:
			chord += 1
		if i == 0:
			continue
		var dt: float = float(groups[i][0]) - float(groups[i - 1][0])
		var prev: Dictionary = groups[i - 1][1]
		var same := false
		for c in cols:
			if prev.has(c):
				same = true
		if same and dt < 180.0:
			jack += 1
		elif dt < 150.0:
			if cols.size() == 1:
				stream += 1
			elif cols.size() == 2:
				js += 1
	var fg := float(g)
	return {"stream": snappedf(stream / fg, 0.001), "jumpstream": snappedf(js / fg, 0.001),
		"jack": snappedf(jack / fg, 0.001), "chord": snappedf(chord / fg, 0.001),
		"hold": snappedf(float(holds) / float(a.size()), 0.001)}


## Grober Stil fuer Standard-Maps: objs = [[Zeit ms, x, y], ...] (osu!-Pixel).
## jumps = Anteil weiter Spruenge (> 140 px in < 300 ms), dense = Dichte (8/s = 1).
static func std_style(objs: Array) -> Dictionary:
	if objs.size() < 2:
		return {}
	var a: Array = objs.duplicate()
	a.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var jumps := 0
	for i in range(1, a.size()):
		var dt: float = float(a[i][0]) - float(a[i - 1][0])
		var dist := Vector2(float(a[i][1]) - float(a[i - 1][1]), float(a[i][2]) - float(a[i - 1][2])).length()
		if dt > 0.0 and dt < 300.0 and dist > 140.0:
			jumps += 1
	var span: float = maxf(1000.0, float(a[a.size() - 1][0]) - float(a[0][0]))
	return {"jumps": snappedf(float(jumps) / float(a.size() - 1), 0.001),
		"dense": snappedf(clampf(float(a.size()) / (span / 1000.0) / 8.0, 0.0, 1.0), 0.001)}


## Genre und Sprache aus Tags + Quelle (Text einer .osu): {genre, language},
## jeweils "" wenn nichts passt. Meiste Treffer gewinnt, Gleichstand nach Name.
static func genre_from_tags(tags: String, source: String = "") -> Dictionary:
	var text := " %s %s " % [tags.to_lower(), source.to_lower()]
	for ch in [",", ";", "/", "(", ")", "[", "]", "\t"]:
		text = text.replace(ch, " ")
	var out := {}
	for pair in [["genre", GENRE_WORDS], ["language", LANGUAGE_WORDS]]:
		var best := ""
		var best_n := 0
		var names: Array = (pair[1] as Dictionary).keys()
		names.sort()
		for name in names:
			var n := 0
			for w in pair[1][name]:
				if text.contains(" %s " % str(w)):
					n += 1
			if n > best_n:
				best_n = n
				best = str(name)
		out[pair[0]] = best
	return out


## Haeufigster Schluessel eines Gewichts-Dictionary ab Anteil min_share, sonst "".
static func top_key(d: Dictionary, total: float, min_share: float) -> String:
	var best := ""
	var best_w := 0.0
	var keys: Array = d.keys()
	keys.sort()
	for k in keys:
		if float(d[k]) > best_w:
			best_w = float(d[k])
			best = str(k)
	return best if total > 0.0 and best_w / total >= min_share else ""


## Stilprofil (Vorlieben) aus dem Spielverhalten eines Modus. runs: Laeufe;
## feats: "set|diff" -> {artist, title?, mapper?, genre?, language?, tags?
## (Array), bpm?, length? (s), style? (Anteile), sv? (bool)};
## plays: "set|diff" -> Anzahl Plays; favs: set -> true (Favoriten/Collections).
## Gewicht je Map: 1 + 0,5 je Wiederholung (bis 4) + 0,5 bei Acc >= 93 % +
## 1,5 Favorit, mal 0,7..1,0 nach Laenge (Spielzeit). {} bei weniger als
## STYLE_MIN_MAPS Maps. Ergebnis: {total, maps, artists, mappers, genres,
## languages, tags, style, sv (Anteil, -1 = unbekannt), bpm, bpm_spread, bpm_lo,
## bpm_hi, stars_lo, stars_hi, length, repeat, examples (Muster -> [Gewicht,
## Titel, Set]), example ([Gewicht, Titel, Set])}.
static func taste(runs: Array, feats: Dictionary, plays: Dictionary = {}, favs: Dictionary = {}) -> Dictionary:
	var best_acc: Dictionary = {}
	var run_stars: Dictionary = {}
	for r in runs:
		if not (r is Dictionary) or _failed(r):
			continue
		var k := _key(r)
		best_acc[k] = maxf(float(best_acc.get(k, 0.0)), float(r.get("accuracy", 0.0)))
		if float(r.get("stars", -1.0)) > 0.0:
			run_stars[k] = float(r.stars)
	for k in plays:
		if int(plays[k]) > 0 and not best_acc.has(k):
			best_acc[k] = 0.0
	var keys: Array = best_acc.keys()
	keys.sort()
	var artists := {}
	var genres := {}
	var langs := {}
	var style := {}
	var style_w := 0.0
	var bpm_pairs: Array = []
	var len_pairs: Array = []
	var star_pairs: Array = []
	var mappers := {}
	var tags := {}
	var sv_w := 0.0
	var sv_n := 0.0
	var examples := {}
	var example: Array = [0.0, "", ""]
	var total := 0.0
	var maps := 0
	for k in keys:
		var f = feats.get(k)
		if not (f is Dictionary):
			continue
		var fd: Dictionary = f
		var set_id := str(k).get_slice("|", 0)
		var w := 1.0 + 0.5 * clampf(float(plays.get(k, 1)) - 1.0, 0.0, 4.0)
		if float(best_acc[k]) >= 0.93:
			w += 0.5
		if favs.has(set_id):
			w += 1.5
		var ln := float(fd.get("length", -1.0))
		if ln > 0.0:
			w *= 0.7 + 0.3 * clampf(ln / 180.0, 0.0, 1.0)
			len_pairs.append([ln, w])
		maps += 1
		total += w
		for pair in [[artists, "artist"], [genres, "genre"], [langs, "language"], [mappers, "mapper"]]:
			var v := str(fd.get(pair[1], "")).strip_edges().to_lower()
			if v != "":
				pair[0][v] = float(pair[0].get(v, 0.0)) + w
		var tg = fd.get("tags", [])
		if tg is Array:
			for one in tg:
				tags[str(one)] = float(tags.get(str(one), 0.0)) + w
		if fd.has("sv"):
			sv_n += w
			if bool(fd.sv):
				sv_w += w
		var stv := float(run_stars.get(k, fd.get("stars", -1.0)))
		if stv > 0.0:
			star_pairs.append([stv, w])
		var title := str(fd.get("title", "")).strip_edges()
		if title != "" and w > float(example[0]):
			example = [w, title, set_id]
		var bpm := float(fd.get("bpm", -1.0))
		if bpm > 0.0:
			bpm_pairs.append([bpm, w])
		var stl = fd.get("style", {})
		if stl is Dictionary and not stl.is_empty():
			style_w += w
			for sk in stl:
				var share := float(stl[sk])
				style[sk] = float(style.get(sk, 0.0)) + w * share
				# Beispiel-Map je Muster: die am staerksten gewichtete mit klarem Anteil.
				if title != "" and share >= 0.2 and w * share > float((examples.get(sk, [0.0]) as Array)[0]):
					examples[sk] = [w * share, title, set_id]
	if maps < STYLE_MIN_MAPS or total <= 0.0:
		return {}
	for sk in style:
		style[sk] = float(style[sk]) / style_w
	var many_bpm := bpm_pairs.size() >= 3
	var many_stars := star_pairs.size() >= 3
	return {"total": total, "maps": maps, "artists": artists, "genres": genres,
		"languages": langs, "style": style, "mappers": mappers, "tags": tags,
		"sv": sv_w / sv_n if sv_n > 0.0 else -1.0,
		"bpm_lo": _wquantile(bpm_pairs, 0.2) if many_bpm else -1.0,
		"bpm_hi": _wquantile(bpm_pairs, 0.8) if many_bpm else -1.0,
		"stars_lo": _wquantile(star_pairs, 0.2) if many_stars else -1.0,
		"stars_hi": _wquantile(star_pairs, 0.8) if many_stars else -1.0,
		"examples": examples, "example": example,
		"bpm": _wquantile(bpm_pairs, 0.5) if bpm_pairs.size() >= 3 else -1.0,
		"bpm_spread": maxf(15.0, absf(_wquantile(bpm_pairs, 0.75) - _wquantile(bpm_pairs, 0.25))) if bpm_pairs.size() >= 3 else 0.0,
		"length": _wquantile(len_pairs, 0.5) if len_pairs.size() >= 3 else -1.0,
		"repeat": plays.values().filter(func(v): return int(v) >= 3).size() > 0}


## Die staerksten Muster des Profils (Anteil >= 0,15), hoechstens n, als Namen.
static func top_patterns(t: Dictionary, n: int = 2) -> Array:
	var st = t.get("style", {})
	if not (st is Dictionary):
		return []
	var keys: Array = (st as Dictionary).keys()
	keys.sort()
	keys.sort_custom(func(a, b): return float(st[a]) > float(st[b]) and not is_equal_approx(float(st[a]), float(st[b])))
	var out: Array = []
	for k in keys:
		if float(st[k]) < 0.15 or out.size() >= n:
			break
		out.append(TranslationServer.translate(str(STYLE_LABELS.get(k, k))))
	return out


static func _range_text(lo: float, hi: float, step: float, fmt: String) -> String:
	var a := snappedf(lo, step)
	var b := snappedf(hi, step)
	if is_equal_approx(a, b):
		return fmt % a
	return "%s-%s" % [fmt % a, fmt % b]


## Teile des Stilprofils, wichtigste zuerst: Muster, SV, BPM-Bereich,
## Sterne-Bereich, Genre, Sprache, Laenge, Mapper. [] ohne Profil.
static func profile_parts(t: Dictionary) -> Array:
	if t.is_empty():
		return []
	var total := float(t.get("total", 0.0))
	var out: Array = top_patterns(t, 2)
	if float(t.get("sv", -1.0)) >= 0.5:
		out.append("SV")
	if float(t.get("bpm_lo", -1.0)) > 0.0:
		out.append(_range_text(float(t.bpm_lo), float(t.bpm_hi), 5.0, "%d") + " BPM")
	if float(t.get("stars_lo", -1.0)) > 0.0:
		out.append(_range_text(float(t.stars_lo), float(t.stars_hi), 0.1, "%.1f") + " ★")
	var genre := top_key(t.get("genres", {}), total, 0.3)
	if genre != "":
		out.append(TranslationServer.translate(genre.capitalize()))
	var lang := top_key(t.get("languages", {}), total, 0.4)
	if lang != "":
		out.append(TranslationServer.translate(lang.capitalize()))
	var ln := float(t.get("length", -1.0))
	if ln > 0.0:
		out.append(TranslationServer.translate("about %d:%02d long") % [int(ln) / 60, int(ln) % 60])
	var mapper := top_key(t.get("mappers", {}), total, 0.25)
	if mapper != "":
		out.append(TranslationServer.translate("mapped by %s") % mapper)
	return out


## Sichtbares Stilprofil, kurz: "Your style: Jumpstream, 170-190 BPM, 2.4-3.1 ★".
## Hoechstens max_parts Teile; "" ohne Profil.
static func profile_text(t: Dictionary, max_parts: int = 4) -> String:
	var parts := profile_parts(t)
	if parts.is_empty():
		return ""
	return TranslationServer.translate("Your style: %s") % ", ".join(parts.slice(0, max_parts))


static func _short(title: String) -> String:
	return title if title.length() <= LIKE_MAX else title.substr(0, LIKE_MAX - 1).strip_edges() + "…"


## Passung eines Kandidaten zum Stilprofil: {bonus 0..1, reason, fits}. Teile
## mit Gewicht: Muster 0,35, Kuenstler 0,2, Genre/Sprache 0,15, BPM 0,15,
## Laenge 0,15, Mapper 0,1, Tags 0,1, SV 0,1; fehlende Merkmale zaehlen nicht
## mit. reason = "fits: 180 BPM, Streams, like <Map>" aus den Teilen, die
## wirklich passen (fits), sonst "".
static func style_match(t: Dictionary, cand: Dictionary) -> Dictionary:
	if t.is_empty():
		return {"bonus": 0.0, "reason": "", "fits": []}
	var parts: Array = []  # [Wert, Gewicht, Art]
	var total: float = float(t.total)
	var stl = cand.get("style", {})
	var dom := ""
	if stl is Dictionary and not stl.is_empty() and not (t.style as Dictionary).is_empty():
		var diff := 0.0
		var nd := 0
		var dom_v := 0.0
		for sk in t.style:
			var tv: float = float(t.style[sk])
			var cv: float = float(stl.get(sk, 0.0))
			diff += absf(tv - cv) / maxf(0.15, maxf(tv, cv))
			nd += 1
			if tv >= 0.12 and cv >= 0.12 and tv * cv > dom_v:
				dom_v = tv * cv
				dom = str(sk)
		var sim := clampf(1.0 - diff / maxf(1.0, float(nd)), 0.0, 1.0)
		parts.append([sim, 0.35, "style"])
	var art := str(cand.get("artist", "")).strip_edges().to_lower()
	if art != "":
		var share: float = float((t.artists as Dictionary).get(art, 0.0)) / total
		parts.append([clampf(share * 4.0, 0.0, 1.0), 0.2, "artist"])
	for g in [["genre", "genres"], ["language", "languages"]]:
		var gv := str(cand.get(g[0], "")).strip_edges().to_lower()
		if gv != "" and not (t[g[1]] as Dictionary).is_empty():
			var gs: float = float((t[g[1]] as Dictionary).get(gv, 0.0)) / total
			parts.append([clampf(gs * 1.5, 0.0, 1.0), 0.075, g[0]])
	var mp := str(cand.get("mapper", "")).strip_edges().to_lower()
	var t_mappers: Dictionary = t.get("mappers", {})
	if mp != "" and not t_mappers.is_empty():
		parts.append([clampf(float(t_mappers.get(mp, 0.0)) / total * 4.0, 0.0, 1.0), 0.1, "mapper"])
	var ctags = cand.get("tags", [])
	var t_tags: Dictionary = t.get("tags", {})
	if ctags is Array and not (ctags as Array).is_empty() and not t_tags.is_empty():
		var hit := 0.0
		for one in ctags:
			hit = maxf(hit, float(t_tags.get(str(one), 0.0)) / total)
		parts.append([clampf(hit * 1.5, 0.0, 1.0), 0.1, "tags"])
	var t_sv := float(t.get("sv", -1.0))
	if cand.has("sv") and t_sv >= 0.0:
		parts.append([1.0 - absf(t_sv - (1.0 if bool(cand.sv) else 0.0)), 0.1, "sv"])
	var bpm := float(cand.get("bpm", -1.0))
	if bpm > 0.0 and float(t.bpm) > 0.0:
		var z := (bpm - float(t.bpm)) / float(t.bpm_spread)
		parts.append([exp(-0.5 * z * z), 0.15, "bpm"])
	var ln := float(cand.get("length", -1.0))
	if ln > 0.0 and float(t.length) > 0.0:
		var zl := (ln - float(t.length)) / maxf(60.0, float(t.length) * 0.4)
		parts.append([exp(-0.5 * zl * zl), 0.15, "length"])
	var sw := 0.0
	var sv := 0.0
	for p in parts:
		sw += float(p[1])
		sv += float(p[0]) * float(p[1])
	if sw < 0.3:  # zu wenig Merkmale fuer eine Aussage
		return {"bonus": 0.0, "reason": "", "fits": []}
	var bonus := sv / sw
	var fits: Array = []
	if bonus >= STYLE_SHOW:
		# Nur Teile, die deutlich passen; hoechstens zwei Merkmale + "like <Map>".
		var val := {}
		for p in parts:
			val[str(p[2])] = float(p[0])
		if bpm > 0.0 and float(val.get("bpm", 0.0)) >= 0.75:
			fits.append("%d BPM" % roundi(bpm))
		if dom != "" and float(val.get("style", 0.0)) >= 0.6:
			fits.append(TranslationServer.translate(str(STYLE_LABELS.get(dom, "Patterns"))))
		if bool(cand.get("sv", false)) and t_sv >= 0.5:
			fits.append("SV")
		if float(val.get("artist", 0.0)) >= 0.75:
			fits.append(str(cand.get("artist", "")))
		elif float(val.get("mapper", 0.0)) >= 0.75:
			fits.append(TranslationServer.translate("mapped by %s") % str(cand.get("mapper", "")))
		elif float(val.get("genre", 0.0)) >= 0.6:
			fits.append(TranslationServer.translate(str(cand.get("genre", "")).capitalize()))
		fits = fits.slice(0, 2)
		var ex = (t.get("examples", {}) as Dictionary).get(dom)
		if dom != "" and float(val.get("style", 0.0)) >= 0.7 and ex is Array \
				and str(ex[2]) != str(cand.get("set", "")):
			fits.append(TranslationServer.translate("like %s") % _short(str(ex[1])))
		elif fits.is_empty() and bonus >= 0.8 and bool(t.get("repeat", false)):
			fits.append(TranslationServer.translate("similar to maps you replay"))
	var reason := ""
	if not fits.is_empty():
		reason = TranslationServer.translate("fits: %s") % ", ".join(fits)
	return {"bonus": bonus, "reason": reason, "fits": fits}


# --- Vorschlaege ---

static func _unix(s: String) -> int:
	if s == "":
		return -1
	return int(Time.get_unix_time_from_datetime_string(s))


## Jetzt als lokale Unix-Zeit (Eintraege nutzen die lokale Systemzeit).
static func now_local() -> int:
	return _unix(Time.get_datetime_string_from_system())


## Vorschlaege fuer Modus und Stufe, sortiert (beste zuerst), hoechstens n.
## runs: Laeufe des Modus (z.B. runs_from_store()). now: Unix-Zeit (0 = jetzt).
## taste: Vorlieben (taste(), {} = ohne Stil-Bonus). seen: "set|diff" -> wie
## oft schon gezeigt, ohne gespielt zu werden (Neuheit: je Mal NOVELTY_W Sterne
## Abstand, hoechstens NOVELTY_CAP Mal; Push: je Mal 8 % weniger Gewinn).
## Rueckgabe: [{set, diff, stars, expected_acc, expected_perf, reason,
## style_reason}]. Seiten: mit n = Seitengroesse * Seiten rufen, page_slice().
static func suggest(mode: String, level: String, cands: Array, n: int = 5,
		runs: Array = [], now: int = 0, tst: Dictionary = {}, seen: Dictionary = {}) -> Array:
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
	var c: float = float(sk.comfort)
	var top: Array = sk.top
	var base_rating: float = float(sk.rating)
	var u := unit(m)
	var scored: Array = []
	var steps: Array = []  # Push ohne Top-10-Chance: naechster Schritt
	for cd in cands:
		if not (cd is Dictionary):
			continue
		var st: float = float(cd.get("stars", -1.0))
		if st <= 0.0 or not playable(m, int(cd.get("osu_mode", 3))):
			continue
		var k := _key(cd)
		if blocked.has(k) or str(cd.get("best_grade", "")) == "SS":
			continue
		var lp := _unix(str(cd.get("last_played", "")))
		if lp > 0 and t_now - lp < RECENT_SEC:
			continue
		if st < rng.x - 0.0001 or st > rng.y + 0.0001:
			continue
		var sm := style_match(tst, cd)
		var bonus: float = float(sm.bonus)
		var stale := float(clampi(int(seen.get(k, 0)), 0, NOVELTY_CAP))
		var acc := acc_at(sk, st)
		var score := 0.0
		var reason := ""
		if lv == LEVEL_PUSH:
			acc = push_acc_at(sk, st)
			if acc < MIN_PUSH_ACC:
				continue
		var perf := perf_at(sk, st, acc, float(cd.get("max_pp", -1.0)))
		var item := {
			"set": cd.get("set", ""), "diff": cd.get("diff", ""), "stars": st,
			"expected_acc": acc, "expected_perf": perf, "reason": "",
			"style_reason": str(sm.reason), "_artist": str(cd.get("artist", "")).to_lower(),
		}
		if lv == LEVEL_PUSH:
			var old: float = float(sk.best.get(k, 0.0))
			var lst: Array = top.duplicate()
			if old > 0.0:
				lst.erase(old)
			lst.append(perf)
			lst.sort()
			lst.reverse()
			var rank := lst.find(perf) + 1
			var gain := rating_of(lst) - base_rating
			if perf <= old or rank > TOP_N or gain < 0.5:
				if st <= c + PUSH_STEP_HI + 0.0001:
					item.reason = TranslationServer.translate("A step up: about %d %% expected") % roundi(acc * 100.0)
					item["_score"] = -absf(st - (c + PUSH_STEP)) + STYLE_W * bonus - NOVELTY_W * stale
					steps.append(item)
				continue
			score = gain * (1.0 + STYLE_W * bonus) * (1.0 - 0.08 * stale)
			if rank == 1 and m == "mania":
				reason = TranslationServer.translate("new top pp: +%d %s") % [roundi(gain), u]
			else:
				reason = TranslationServer.translate("+%d %s, would be top %d") % [roundi(gain), u, rank]
		elif lv == LEVEL_EASY:
			score = -absf(st - (c + EASY_TARGET)) + STYLE_W * bonus - NOVELTY_W * stale
			reason = TranslationServer.translate("Easy: about %d %% expected") % roundi(acc * 100.0)
		else:
			score = -absf(st - (c + CHALLENGE_TARGET)) + STYLE_W * bonus - NOVELTY_W * stale
			reason = TranslationServer.translate("Challenge: about %d %% expected") % roundi(acc * 100.0)
		item.reason = reason
		item["_score"] = score
		scored.append(item)
	# Wertung absteigend, dann Set/Diff als Tiebreak (deterministisch). Push:
	# Top-10-Kandidaten zuerst, "A step up" fuellt auf.
	var by_score := func(a, b):
		if not is_equal_approx(float(a._score), float(b._score)):
			return float(a._score) > float(b._score)
		if str(a.set) != str(b.set):
			return str(a.set) < str(b.set)
		return str(a.diff) < str(b.diff)
	scored.sort_custom(by_score)
	steps.sort_custom(by_score)
	scored.append_array(steps)
	# Abwechslung: erst eine Map je Set und Kuenstler, dann bis MAX_PER_SET /
	# MAX_PER_ARTIST, zuletzt ohne Kuenstler-Grenze auffuellen.
	var out: Array = []
	var per_set: Dictionary = {}
	var per_art: Dictionary = {}
	for caps in [[1, 1], [MAX_PER_SET, MAX_PER_ARTIST], [MAX_PER_SET, 1 << 20]]:
		for s in scored:
			if out.size() >= n:
				break
			var sid := str(s.set)
			var art := str(s._artist)
			if out.has(s) or int(per_set.get(sid, 0)) >= int(caps[0]):
				continue
			if art != "" and int(per_art.get(art, 0)) >= int(caps[1]):
				continue
			per_set[sid] = int(per_set.get(sid, 0)) + 1
			if art != "":
				per_art[art] = int(per_art.get(art, 0)) + 1
			out.append(s)
	for s in out:
		s.erase("_score")
		s.erase("_artist")
	return out


# --- Seiten ---

## Anzahl Seiten fuer total Eintraege (mindestens 1, hoechstens PAGE_MAX).
static func page_count(total: int, per: int) -> int:
	if per <= 0 or total <= 0:
		return 1
	return clampi(int(ceil(float(total) / float(per))), 1, PAGE_MAX)


## Seite page (0-basiert, laeuft nach der letzten wieder bei 0 los).
static func page_slice(items: Array, page: int, per: int) -> Array:
	if per <= 0 or items.is_empty():
		return []
	var p := posmod(page, page_count(items.size(), per))
	return items.slice(p * per, mini(items.size(), (p + 1) * per))


# --- Online-Vorschlaege (nicht heruntergeladene Maps) ---

## Zielsterne der Stufe.
static func level_target(sk: Dictionary, level: String) -> float:
	var c: float = float(sk.comfort)
	match normalize_level(level):
		LEVEL_EASY: return maxf(c + EASY_TARGET, 0.5)
		LEVEL_PUSH: return c + PUSH_STEP
	return c + CHALLENGE_TARGET


## Suchauftrag passend zum Profil: {mode, osu_mode (0 = osu!standard fuer Orbit,
## sonst 3 = 4K), lo, hi, target (osu!-Sterne), shift, genre, bpm, key}.
## star_shift = osu!-Sterne minus Modus-Sterne (Median der eigenen Maps; Mania 0),
## weil der Mirror nur osu!-Sterne kennt. key = Cache-Schluessel (Sterne auf 0,5).
static func online_query(mode: String, level: String, sk: Dictionary, t: Dictionary = {},
		star_shift: float = 0.0) -> Dictionary:
	var m := normalize_mode(mode)
	var rng := star_range(sk, level)
	var lo := maxf(0.0, rng.x + star_shift - ONLINE_STAR_PAD)
	var hi := maxf(lo + 0.3, rng.y + star_shift + ONLINE_STAR_PAD)
	var genre := top_key(t.get("genres", {}), float(t.get("total", 0.0)), 0.35) if not t.is_empty() else ""
	var osu_mode := 0 if m == "orbit" else 3
	return {"mode": m, "osu_mode": osu_mode, "lo": lo, "hi": hi,
		"target": level_target(sk, level) + star_shift, "shift": star_shift,
		"genre": genre, "bpm": float(t.get("bpm", -1.0)) if not t.is_empty() else -1.0,
		"key": "%d|%.1f|%s" % [osu_mode, floorf((lo + hi) * 0.5 * 2.0) / 2.0, genre]}


## Online-Kandidaten ordnen. results: Mirror-Eintraege {id, title, artist,
## creator, stars, star_list, bpm, length_s, plays, genre? (Name), sv?,
## cover_url, preview_url}, schon ohne eigene Maps. seen: "online:<id>" -> wie
## oft gezeigt. Je Set die Diff am naechsten am Ziel im Bereich [lo, hi]; Sets
## ohne solche Diff fallen weg. Eine Map je Kuenstler. Rueckgabe: [{id, title,
## artist, creator, stars (Modus-Skala), osu_stars, bpm, length, reason,
## cover_url, preview_url}], beste zuerst, hoechstens n.
static func online_rank(q: Dictionary, t: Dictionary, results: Array, n: int = 6,
		seen: Dictionary = {}) -> Array:
	var lo := float(q.get("lo", 0.0))
	var hi := float(q.get("hi", 99.0))
	var target := float(q.get("target", (lo + hi) * 0.5))
	var scored: Array = []
	var ids := {}
	for r in results:
		if not (r is Dictionary) or ids.has(int(r.get("id", 0))):
			continue
		var star_list: Array = r.get("star_list", [])
		if star_list.is_empty():
			star_list = [float(r.get("stars", 0.0))]
		var best := -1.0
		for sv in star_list:
			var f := float(sv)
			if f >= lo - 0.0001 and f <= hi + 0.0001 and (best < 0.0 or absf(f - target) < absf(best - target)):
				best = f
		if best < 0.0:
			continue
		ids[int(r.get("id", 0))] = true
		var cand := {"set": "online:%d" % int(r.get("id", 0)), "artist": str(r.get("artist", "")),
			"mapper": str(r.get("creator", "")), "bpm": float(r.get("bpm", -1.0)),
			"length": float(r.get("length_s", -1.0)), "genre": str(r.get("genre", ""))}
		if r.has("sv") and int(q.get("osu_mode", 3)) == 3:
			cand["sv"] = bool(r.sv)
		var sm := style_match(t, cand)
		var stale := float(clampi(int(seen.get(cand.set, 0)), 0, NOVELTY_CAP))
		var popular := clampf(log(float(r.get("plays", 0)) + 1.0) / log(10.0), 0.0, 6.0) * 0.02
		var reason := str(sm.reason)
		if reason == "":
			reason = TranslationServer.translate("in your star range")
		scored.append({"id": int(r.get("id", 0)), "title": str(r.get("title", "")),
			"artist": str(r.get("artist", "")), "creator": str(r.get("creator", "")),
			"stars": maxf(0.1, best - float(q.get("shift", 0.0))), "osu_stars": best,
			"bpm": float(r.get("bpm", -1.0)), "length": float(r.get("length_s", -1.0)),
			"reason": reason, "cover_url": str(r.get("cover_url", "")),
			"preview_url": str(r.get("preview_url", "")),
			"_score": -absf(best - target) + STYLE_W * float(sm.bonus) + popular - NOVELTY_W * stale})
	scored.sort_custom(func(a, b):
		if not is_equal_approx(float(a._score), float(b._score)):
			return float(a._score) > float(b._score)
		return int(a.id) < int(b.id))
	var out: Array = []
	var arts := {}
	for pass_i in 2:
		for s in scored:
			if out.size() >= n:
				break
			var art := str(s.artist).to_lower()
			if out.has(s) or (pass_i == 0 and arts.has(art)):
				continue
			arts[art] = true
			out.append(s)
	for s in out:
		s.erase("_score")
	return out


## Online-Antwort in den Cache legen: cache[key] = {t, pages, end, results}.
## Frischer Eintrag: Seite anhaengen (ohne doppelte Sets); sonst ersetzen.
## end = Mirror hat keine weitere Seite. Aelteste Suchen ueber ONLINE_KEEP fallen weg.
static func online_cache_put(cache: Dictionary, key: String, results: Array, now: int, end: bool = false) -> void:
	var ent = cache.get(key)
	if ent is Dictionary and now - int(ent.get("t", 0)) < ONLINE_TTL:
		var ids := {}
		for r in ent.results:
			ids[int(r.get("id", 0))] = true
		for r in results:
			if not ids.has(int(r.get("id", 0))):
				ent.results.append(r)
		ent["pages"] = int(ent.get("pages", 1)) + 1
		ent["end"] = end
	else:
		cache[key] = {"t": now, "pages": 1, "end": end, "results": results.duplicate()}
	while cache.size() > ONLINE_KEEP:
		var oldest := ""
		for k in cache:
			if k != key and (oldest == "" or int(cache[k].get("t", 0)) < int(cache[oldest].get("t", 0))):
				oldest = str(k)
		if oldest == "":
			break
		cache.erase(oldest)


## Gueltige Cache-Eintraege einer Suche ([] = nichts oder abgelaufen).
static func online_cached(cache: Dictionary, key: String, now: int) -> Array:
	var ent = cache.get(key)
	if ent is Dictionary and now - int(ent.get("t", 0)) < ONLINE_TTL and ent.get("results") is Array:
		return ent.results
	return []


## Welche Mirror-Seite jetzt zu holen ist (0-basiert), -1 = keine Anfrage.
## Sparsam: frischer Cache reicht; eine zweite Seite nur, wenn weniger als want
## Vorschlaege (have) uebrig sind; nach einem Fehler ONLINE_RETRY Pause.
static func online_fetch_page(cache: Dictionary, key: String, now: int, have: int, want: int,
		fail_at: int = 0) -> int:
	if fail_at > 0 and now - fail_at < ONLINE_RETRY:
		return -1
	var ent = cache.get(key)
	if not (ent is Dictionary) or now - int(ent.get("t", 0)) >= ONLINE_TTL:
		return 0
	var pages := int(ent.get("pages", 1))
	if have < want and pages < ONLINE_PAGES and not bool(ent.get("end", false)):
		return pages
	return -1


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
