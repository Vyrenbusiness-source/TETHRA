class_name MapLibrary
extends RefCounted

## Scannt den maps-Ordner und baut die MapSet-Liste fuer den Song-Browser.
## v2 mit Bibliotheks-Cache (user://library.cfg): Jede .osz wird nur EINMAL
## voll geparst (Metadaten + Thumbnail), danach laedt der Browser aus dem
## Cache und oeffnet sofort — auch mit 100+ Maps.

const DEV_MAPS_DIR := "C:/Users/Gexanx/Desktop/rhyg/maps"
const CACHE_PATH := "user://library.cfg"
## Version der "unbrauchbar"-Markierung: hochzaehlen, wenn der Importer neue
## Modi/Keycounts unterstuetzt, damit alte Skip-Eintraege neu geprueft werden.
const SKIP_VERSION := 1
## Version der SV-Erkennung: hochzaehlen -> alle Cache-Eintraege werden einmal
## im Hintergrund nachgerechnet (start_sv_backfill).
const SV_VERSION := 2
## SV-Erkennung ueber die EFFEKTIVE Scrollgeschwindigkeit (ScrollMap):
## Abweichung eines Abschnitts vom Grundtempo, ab der er als "SV" zaehlt.
const SV_DEV := 0.08
## Mindestanteil der Notenspanne mit SV-Abweichung fuer "echte SV".
const SV_MIN_FRAC := 0.15
## Sprung der Geschwindigkeit, der als deutlicher Wechsel zaehlt.
const SV_JUMP := 0.15
## Mindestzahl deutlicher Wechsel fuer "echte SV".
const SV_MIN_JUMPS := 12
## Abschnitte kuerzer als das (und mit weniger Versatz) ignorieren die
## Wechsel-Zaehlung: rote Linie + Ausgleichslinie 1 ms spaeter o.ae.
const SV_SIG_MS := 5.0
## Wechsel naeher als das am letzten gezaehlten zaehlen nicht: ein einzelner
## kurzer SV-Effekt (10 Linien in 0.5 s) macht noch keine SV-Map.
const SV_JUMP_GAP_MS := 250.0
## Starkes eigenes SV (SvMod laesst es unveraendert): mindestens so viele
## deutliche Wechsel pro Minute. Gemessen an 983 Mania-Diffs (docs/qa/sv_real.md):
## schwache "SV"-Maps (nur BPM-Wechsel, z.B. xi - Happy End) liegen bei <= 3,
## die schwaechste echte SV-Map (MX) bei 6,1.
const SV_STRONG_JPM := 5.0

## Sets aus dem Cache ohne aktuelle SV-Erkennung oder ohne Long-Note-/BPM-
## Werte (siehe start_sv_backfill).
var sv_pending: Array[String] = []
var _sv_thread: Thread = null
var _sv_cancel := false

var maps_dir: String = ""
var mapsets: Array[MapSet] = []


## "maps"-Ordner neben der Exe (Release UND Dev — die Godot-Exe liegt im
## Projektordner). Fallback: fester Dev-Pfad. KEIN has_feature("editor"):
## das ist beim Editor-Binary auch im PCK-Release true.
static func default_maps_dir() -> String:
	var local := OS.get_executable_path().get_base_dir().path_join("maps")
	if DirAccess.dir_exists_absolute(local):
		return local
	return DEV_MAPS_DIR


func _init(dir: String = "") -> void:
	maps_dir = dir if dir != "" else default_maps_dir()


## Ordner (neu) scannen. Gibt die Anzahl gefundener Mapsets zurueck.
func scan() -> int:
	mapsets.clear()
	sv_pending.clear()
	var dir := DirAccess.open(maps_dir)
	if dir == null:
		push_warning("MapLibrary: maps-Ordner nicht gefunden: " + maps_dir)
		return 0
	var t0 := Time.get_ticks_usec()
	var cfg := ConfigFile.new()
	cfg.load(CACHE_PATH)
	OszImporter._perf("Library: Cache laden", t0, CACHE_PATH)
	t0 = Time.get_ticks_usec()

	var files := dir.get_files()
	files.sort()
	# Erst aus dem Cache bedienen; nur unbekannte Dateien voll analysieren.
	# Unbrauchbare Sets (keine Standard-/4K-Diff, kaputtes Zip) stehen als
	# {"skip": SKIP_VERSION} im Cache — sonst wuerden sie bei JEDEM Oeffnen neu
	# geparst und loesten jedes Mal den python-Sternelauf aus.
	var fresh: Array[String] = []
	for fname in files:
		if not fname.to_lower().ends_with(".osz"):
			continue
		var path := maps_dir.path_join(fname)
		var key := _cache_key(path)
		var cached = cfg.get_value("sets", key, null) if cfg.has_section_key("sets", key) else null
		if cached is Dictionary:
			if int(cached.get("skip", 0)) == SKIP_VERSION:
				continue
			if not cached.has("skip"):
				var ms := MapSet.from_dict(path, cached)
				if ms.difficulty_count() > 0:
					mapsets.append(ms)
					if ms.sv_ver != SV_VERSION or ms.needs_stats():
						sv_pending.append(path)
				continue
		fresh.append(path)
	OszImporter._perf("Library: %d Sets aus Cache" % mapsets.size(), t0, maps_dir)

	var dirty := false
	if not fresh.is_empty():
		t0 = Time.get_ticks_usec()
		# Nur fuer NEUE Dateien Stars im Batch vorberechnen.
		if fresh.size() >= 2:
			StarService.prefetch_dir(maps_dir)
		for path in fresh:
			var ms := _build_mapset_full(path)
			if ms != null:
				cfg.set_value("sets", _cache_key(path), ms.to_dict())
				if ms.difficulty_count() > 0:
					mapsets.append(ms)
			else:
				cfg.set_value("sets", _cache_key(path), {"skip": SKIP_VERSION})
			dirty = true
		OszImporter._perf("Library: %d neue Dateien analysiert" % fresh.size(), t0, maps_dir)
	if dirty:
		cfg.save(CACHE_PATH)
	mapsets.sort_custom(func(a, b): return a.search_haystack() < b.search_haystack())
	return mapsets.size()


static func _cache_key(osz_path: String) -> String:
	var size := 0
	if FileAccess.file_exists(osz_path):
		var f := FileAccess.open(osz_path, FileAccess.READ)
		size = f.get_length()
	return "%s|%d" % [osz_path.get_file(), size]


## Einmalige Voll-Analyse einer .osz: parsen, Metadaten extrahieren,
## Thumbnail auf Disk legen.
func _build_mapset_full(osz_path: String) -> MapSet:
	var imp := OszImporter.import(osz_path)
	if not imp.ok or imp.difficulties.is_empty():
		return null
	var ms := MapSet.new()
	ms.osz_path = osz_path
	var star_data := StarService.stars_for(osz_path)
	var entries: Array = []
	for d in imp.difficulties:
		var bm: Beatmap = d.beatmap
		# Standard (0) immer; Mania nur als 4K.
		if bm.is_mania() and bm.column_count() != 4:
			continue
		var fname: String = d.osu_filename
		var s := -1.0
		var mc := 0
		if star_data.has(fname):
			s = float(star_data[fname].get("stars", -1.0))
			mc = int(star_data[fname].get("max_combo", 0))
		entries.append({
			"version": bm.version_name(), "osu_filename": fname,
			"stars": s, "max_combo": mc, "mode": bm.mode(),
			"notes": bm.note_count(), "duration_ms": bm.duration_ms(),
			"cs": bm.cs(), "ar": bm.ar(), "od": bm.od(),
			"preview_time": float(bm.general.get("PreviewTime", -1.0)),
			"audio_filename": bm.audio_filename(),
			"_sort_notes": bm.note_count(),
			"sv": detect_sv(bm),
		})
		if ms.background_file == "" and bm.background_file != "":
			ms.background_file = bm.background_file
	if entries.is_empty():
		return null
	entries.sort_custom(func(a, b):
		if float(a.stars) >= 0.0 and float(b.stars) >= 0.0:
			return float(a.stars) < float(b.stars)
		return int(a._sort_notes) < int(b._sort_notes))
	ms.diffs = entries
	ms.sv = false
	for e in entries:
		ms.sv = ms.sv or bool(e.sv)
	ms.sv_ver = SV_VERSION
	var first: Beatmap = imp.difficulties[0].beatmap
	ms.title = first.title()
	ms.artist = first.artist()
	ms.creator = str(first.metadata.get("Creator", ""))
	ms.build_thumb()
	return ms


## Anzahl Long Notes (Mania-Holds; Standard: Slider).
static func hold_count(bm: Beatmap) -> int:
	var n := 0
	for h in bm.hit_objects:
		if h is ManiaNote:
			if (h as ManiaNote).is_hold:
				n += 1
		elif h.kind == HitObject.Kind.SLIDER:
			n += 1
	return n


## Vorherrschendes Tempo: BPM der roten Linie, die die meiste Zeit der
## Notenspanne gilt (0 = keine Timing-Linie).
static func main_bpm(bm: Beatmap) -> float:
	var reds: Array = []
	for tp in bm.timing_points:
		if tp.uninherited and tp.beat_length > 0.0:
			reds.append(tp)
	if reds.is_empty():
		return 0.0
	var end := bm.duration_ms()
	var start: float = bm.hit_objects[0].time if not bm.hit_objects.is_empty() else 0.0
	var best := 0.0
	var best_bpm: float = reds[0].bpm()
	for i in reds.size():
		var a := maxf(float(reds[i].time), start)
		var b := end if i + 1 >= reds.size() else minf(float(reds[i + 1].time), end)
		if b - a > best:
			best = b - a
			best_bpm = reds[i].bpm()
	return snappedf(best_bpm, 0.01)


## Echte SV fuer eine geparste Map (siehe sv_stats).
static func detect_sv(bm: Beatmap) -> bool:
	return bool(sv_stats(bm).sv)


## Eigenes SV stark genug, dass der SV-Mod nichts dazugeneriert.
static func has_strong_sv(bm: Beatmap) -> bool:
	var st := sv_stats(bm)
	return bool(st.sv) and float(st.jpm) >= SV_STRONG_JPM


## SV-Kennzahlen einer Map zwischen erster Note und letztem Notenende:
## { sv: bool, frac: Anteil mit SV-Abweichung, jumps: deutliche Wechsel }.
static func sv_stats(bm: Beatmap) -> Dictionary:
	if bm == null or bm.hit_objects.is_empty():
		return {"sv": false, "frac": 0.0, "jumps": 0, "jpm": 0.0}
	var t0 := INF
	var t1 := -INF
	for obj in bm.hit_objects:
		t0 = minf(t0, obj.time)
		t1 = maxf(t1, obj.end_time())
	return sv_stats_tp(bm.timing_points, t0, t1)


## Kern der Erkennung. Wertet die effektiven Multiplikatoren der ScrollMap
## (SV * BaseBeatLength / beatLength, wie im Spiel) im Fenster [t0, t1] aus.
## Bezug ist das dominante Tempo m_dom (laengste Gesamtdauer), damit eine
## global gesetzte SV (ueberall 0.8) keine SV-Map ist. Ein Abschnitt weicht
## nur ab, wenn |m / m_dom - 1| > SV_DEV UND |m - 1| > SV_DEV (gegen
## zweigipflige Mini-SV wie 0.95/1.05) UND sein gruener Anteil
## g (= m * bl / base) vom neutralen g abweicht: reine BPM-Wechsel ohne
## gruene Linie zaehlen nicht, BPM-Ausgleichslinien (m ~ 1) ebenfalls nicht.
## Wechsel: Sprung |dm| / m_dom > SV_JUMP zwischen signifikanten Abschnitten
## mit unterschiedlichem g, hoechstens einer je SV_JUMP_GAP_MS.
## SV-Map, wenn frac >= SV_MIN_FRAC oder jumps >= SV_MIN_JUMPS.
static func sv_stats_tp(timing_points: Array, t0: float, t1: float) -> Dictionary:
	var res := {"sv": false, "frac": 0.0, "jumps": 0, "jpm": 0.0}
	var span := t1 - t0
	if timing_points.is_empty() or not (span > 0.0):
		return res
	var sm := ScrollMap.new()
	sm.build(timing_points, t1)
	var times: PackedFloat64Array = sm._times
	var mults: PackedFloat64Array = sm._mult
	if times.is_empty():
		return res
	var reds: Array = []
	for tp in timing_points:
		if tp.uninherited:
			reds.append(tp)
	reds.sort_custom(func(a, b): return a.time < b.time)
	# Abschnitte im Fenster: [dauer, m, g, start].
	var segs: Array = []
	var ri := -1
	for i in times.size():
		while ri + 1 < reds.size() and reds[ri + 1].time <= times[i]:
			ri += 1
		var bl := ScrollMap.red_beat_length(reds[maxi(ri, 0)]) if not reds.is_empty() else ScrollMap.DEFAULT_BL
		var s := t0 if i == 0 else maxf(times[i], t0)
		var e := t1 if i == times.size() - 1 else minf(times[i + 1], t1)
		if e <= s:
			continue
		var m: float = mults[i]
		segs.append([e - s, m, m * bl / sm.base_beat_length, s])
	if segs.is_empty():
		return res
	var m_dom := _dominant(segs, 1, 100.0)
	if m_dom <= 0.0:
		return res
	# Neutraler gruener Anteil: der haeufigste g unter den Abschnitten im
	# dominanten Tempo (normal 1.0; bei globaler SV deren Wert).
	var base_segs: Array = []
	for seg in segs:
		if absf(float(seg[1]) - m_dom) < 0.0051:
			base_segs.append(seg)
	var g_dom := _dominant(base_segs, 2, 1000.0) if not base_segs.is_empty() else 1.0
	var dev_ms := 0.0
	var jumps := 0
	var prev: Array = []
	var last_jump := -INF
	for seg in segs:
		var rel: float = seg[1] / m_dom
		var green_off: bool = absf(seg[2] - g_dom) > 0.001
		if green_off and absf(rel - 1.0) > SV_DEV and absf(seg[1] - 1.0) > SV_DEV:
			dev_ms += seg[0]
		var sig: bool = seg[0] >= SV_SIG_MS or absf(rel - 1.0) * seg[0] >= SV_SIG_MS
		if not sig:
			continue
		if not prev.is_empty() and absf(seg[1] - prev[1]) / m_dom > SV_JUMP 				and absf(seg[2] - prev[2]) > 0.001 and seg[3] - last_jump >= SV_JUMP_GAP_MS:
			jumps += 1
			last_jump = seg[3]
		prev = seg
	res.frac = dev_ms / span
	res.jumps = jumps
	res.jpm = jumps / maxf(span / 60000.0, 1.0 / 60.0)
	res.sv = res.frac >= SV_MIN_FRAC or jumps >= SV_MIN_JUMPS
	return res


## Wert (Spalte idx) mit der groessten Gesamtdauer, gerundet auf 1/scale.
static func _dominant(segs: Array, idx: int, scale: float) -> float:
	var durs := {}
	var best_key := 0
	var best := -1.0
	for seg in segs:
		var k := int(roundf(float(seg[idx]) * scale))
		durs[k] = float(durs.get(k, 0.0)) + float(seg[0])
		if durs[k] > best:
			best = durs[k]
			best_key = k
	return best_key / scale


func sv_backfill_running() -> bool:
	return _sv_thread != null


## Rechnet SV-Erkennung, Long Notes und BPM fuer Cache-Eintraege ohne
## aktuelle Werte im Hintergrund nach (ein Parse pro Set). on_done() kommt im Hauptthread, nachdem Sets und
## library.cfg aktualisiert sind.
func start_sv_backfill(on_done: Callable) -> void:
	if _sv_thread != null or sv_pending.is_empty():
		return
	var todo: Array[String] = sv_pending.duplicate()
	sv_pending.clear()
	_sv_cancel = false
	_sv_thread = Thread.new()
	_sv_thread.start(_sv_worker.bind(todo, on_done))


func _sv_worker(paths: Array[String], on_done: Callable) -> void:
	var out := {}
	for path in paths:
		if _sv_cancel:
			break
		var imp := OszImporter._import_uncached(path)
		var by_file := {}
		if imp.get("ok", false):
			for d in imp.difficulties:
				var bm: Beatmap = d.beatmap
				by_file[str(d.osu_filename)] = { "sv": detect_sv(bm), "holds": hold_count(bm), "bpm": main_bpm(bm) }
		out[path] = by_file
	_sv_finish.call_deferred(out, on_done)


func _sv_finish(results: Dictionary, on_done: Callable) -> void:
	if _sv_thread != null:
		_sv_thread.wait_to_finish()
		_sv_thread = null
	if _sv_cancel:
		return
	var cfg := ConfigFile.new()
	cfg.load(CACHE_PATH)
	for ms in mapsets:
		if results.has(ms.osz_path):
			ms.apply_sv(results[ms.osz_path])
			cfg.set_value("sets", _cache_key(ms.osz_path), ms.to_dict())
	cfg.save(CACHE_PATH)
	if on_done.is_valid():
		on_done.call()


## Thread beim Szenenende abwarten.
func shutdown() -> void:
	_sv_cancel = true
	if _sv_thread != null:
		_sv_thread.wait_to_finish()
		_sv_thread = null


## Eine externe .osz in den maps-Ordner importieren (Drag&Drop/Download).
func import_external(source_path: String) -> String:
	if not source_path.to_lower().ends_with(".osz"):
		return ""
	if not FileAccess.file_exists(source_path):
		return ""
	DirAccess.make_dir_recursive_absolute(maps_dir)
	var dest := maps_dir.path_join(source_path.get_file())
	if FileAccess.file_exists(dest):
		var base := source_path.get_file().get_basename()
		var i := 1
		while FileAccess.file_exists(dest):
			dest = maps_dir.path_join("%s (%d).osz" % [base, i])
			i += 1
	var err := DirAccess.copy_absolute(source_path, dest)
	if err != OK:
		push_error("Import fehlgeschlagen (%d): %s" % [err, source_path])
		return ""
	return dest
