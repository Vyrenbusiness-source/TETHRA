class_name TraceDaily
extends RefCounted

## Daily Trace: jeden Tag dieselbe Map fuer alle (rein, ohne Szene, getestet).
##
## Karte = Hash(Tagesdatum UTC) modulo Liste der Kandidaten (nach Schluessel
## sortiert, damit die Reihenfolge nie von Suchlaufzeit oder Ordner abhaengt).
## Online: Kandidaten = Ranked-4K-Treffer des Map-Browsers; offline: nur lokale
## 4K-Maps. Ein Versuch pro Tag zaehlt (Start = Versuch). Serie = Tage in Folge.

const STATE_PATH := "user://trace_daily.cfg"
const SECTION := "daily"
const PIC_SIZE := 96


## Tagesschluessel "YYYY-MM-DD" (UTC) aus Unix-Sekunden.
static func day_key(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


static func today_key() -> String:
	return day_key(int(Time.get_unix_time_from_system()))


## Tage seit 1970-01-01 (fuer "gestern"-Vergleich ueber Monatsgrenzen).
static func day_number(key: String) -> int:
	var p := key.split("-")
	if p.size() != 3:
		return -1
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": int(p[0]), "month": int(p[1]), "day": int(p[2]), "hour": 0, "minute": 0, "second": 0 })
	return int(floor(float(unix) / 86400.0))


static func key_of_number(n: int) -> String:
	return day_key(n * 86400)


## FNV-1a 32 Bit ueber den Text (stabil, unabhaengig von Godot-hash()).
static func fnv(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	return h


## Kandidaten nach "key" sortiert (Kopie). Jeder Eintrag braucht "key" (String).
static func sorted_pool(pool: Array) -> Array:
	var out := pool.duplicate()
	out.sort_custom(func(a, b): return str(a.get("key", "")) < str(b.get("key", "")))
	return out


## Map des Tages oder {} bei leerer Liste. Gleiche Liste + gleicher Tag = gleiche Map.
static func pick(key: String, pool: Array) -> Dictionary:
	if pool.is_empty():
		return {}
	var s := sorted_pool(pool)
	return s[fnv("trace-daily:" + key) % s.size()]


## Lokale Kandidaten: je Set mit mindestens einer 4K-Diff (Mode 3, CS 4).
## Eintrag: {key, osz_path, local: true}.
static func local_pool(mapsets: Array) -> Array:
	var out := []
	for ms in mapsets:
		if not diff_4k_indices(ms).is_empty():
			out.append({ "key": _set_key(str(ms.osz_path).get_file()),
				"osz_path": ms.osz_path, "local": true })
	return out


## Sortierschluessel: fuehrende Set-ID (oder mirror_<id>) numerisch aufgefuellt + Dateiname.
static func _set_key(osz_file: String) -> String:
	var s := osz_file.trim_prefix("mirror_")
	var digits := ""
	for c in s:
		if c >= "0" and c <= "9":
			digits += c
		else:
			break
	return ("%012d" % int(digits)) + osz_file if digits != "" else osz_file


## Online-Kandidaten aus BeatmapMirror-Treffern (parse_item-Dictionaries).
static func online_pool(items: Array) -> Array:
	var out := []
	for it in items:
		var id := int(it.get("id", 0))
		if id <= 0:
			continue
		out.append({ "key": "%012d" % id, "set_id": id, "title": str(it.get("title", "")),
			"artist": str(it.get("artist", "")), "local": false })
	return out


static func diff_4k_indices(ms: Object) -> Array[int]:
	var out: Array[int] = []
	for i in ms.difficulty_count():
		var m: Dictionary = ms.meta_at(i)
		if int(m.get("mode", 0)) == 3 and int(round(float(m.get("cs", 4.0)))) == 4:
			out.append(i)
	return out


## Diff des Tages im Set: mittlere 4K-Diff nach Sternen (Gleichstand: Index). -1 = keine.
static func pick_diff(ms: Object) -> int:
	var idx := diff_4k_indices(ms)
	if idx.is_empty():
		return -1
	idx.sort_custom(func(a, b):
		var sa: float = ms.stars_at(a)
		var sb: float = ms.stars_at(b)
		return a < b if is_equal_approx(sa, sb) else sa < sb)
	return idx[(idx.size() - 1) / 2]


# --- Zustand: Versuche und Serie -------------------------------------------

## state = { "days": { "YYYY-MM-DD": { "key": String, "score": int } } }.
static func has_attempt(state: Dictionary, day: String) -> bool:
	return (state.get("days", {}) as Dictionary).has(day)


## Versuch fuer den Tag eintragen (nur der erste zaehlt). true bei neuem Eintrag.
static func start_attempt(state: Dictionary, day: String, map_key: String) -> bool:
	if not state.has("days"):
		state["days"] = {}
	if has_attempt(state, day):
		return false
	state["days"][day] = { "key": map_key, "score": -1 }
	return true


## Ergebnis des Tagesversuchs setzen (nur einmal, solange score < 0).
static func set_score(state: Dictionary, day: String, score: int) -> bool:
	if not has_attempt(state, day):
		return false
	var e: Dictionary = state.days[day]
	if int(e.get("score", -1)) >= 0:
		return false
	e["score"] = maxi(score, 0)
	return true


## Aktuelle Serie: aufeinanderfolgende Tage mit Versuch, endend heute oder gestern
## (heute noch offen bricht die Serie nicht).
static func streak(state: Dictionary, today: String) -> int:
	var days: Dictionary = state.get("days", {})
	var n := day_number(today)
	if n < 0:
		return 0
	var cur := n if days.has(today) else n - 1
	var count := 0
	while days.has(key_of_number(cur)):
		count += 1
		cur -= 1
	return count


static func best_streak(state: Dictionary) -> int:
	var nums := []
	for k in (state.get("days", {}) as Dictionary).keys():
		nums.append(day_number(str(k)))
	nums.sort()
	var best := 0
	var run := 0
	var prev := -999999
	for v in nums:
		run = run + 1 if v == prev + 1 else 1
		best = maxi(best, run)
		prev = v
	return best


# --- Tages-Bild --------------------------------------------------------------

## Kleines Belohnungsbild: Faden-Linie, deterministisch aus Tag + Serie
## (mehr Serie = mehr helle Knoten).
static func picture(key: String, streak_len: int) -> Image:
	var img := Image.create(PIC_SIZE, PIC_SIZE, false, Image.FORMAT_RGBA8)
	var h := fnv("pic:" + key)
	var hue := float(h % 360) / 360.0
	var bg := Color.from_hsv(hue, 0.55, 0.16)
	var fg := Color.from_hsv(fposmod(hue + 0.08, 1.0), 0.45, 1.0)
	img.fill(bg)
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var pts: Array[Vector2] = []
	var cols := 5
	for i in cols + 1:
		var x := 8.0 + float(i) * (PIC_SIZE - 16.0) / float(cols)
		pts.append(Vector2(x, rng.randf_range(16.0, PIC_SIZE - 16.0)))
	for i in pts.size() - 1:
		_line(img, pts[i], pts[i + 1], fg)
	for i in mini(pts.size(), 1 + streak_len):
		_dot(img, pts[i], 3, Color.WHITE)
	return img


static func _line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) * 2 + 1
	for s in steps + 1:
		_dot(img, a.lerp(b, float(s) / float(steps)), 1, c)


static func _dot(img: Image, p: Vector2, r: int, c: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := int(p.x) + dx
			var y := int(p.y) + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, c)


# --- Speicher ----------------------------------------------------------------

static func load_state(path: String = STATE_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return { "days": {} }
	var d: Variant = cfg.get_value(SECTION, "days", {})
	return { "days": d if d is Dictionary else {} }


static func save_state(state: Dictionary, path: String = STATE_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "days", state.get("days", {}))
	cfg.save(path)
