extends SceneTree

## Headless-Tests fuer WorldTheme (Welt-Themen-Wahl nach Song-Charakter).
##   Godot..._console.exe --headless --path . --audio-driver Dummy --script res://tests/run_world_theme_tests.gd

var _failed := 0

const BLUE := Color(0.22, 0.55, 0.90)
const ORANGE := Color(0.92, 0.52, 0.20)
const MAGENTA := Color(0.90, 0.20, 0.80)
const CYAN := Color(0.20, 0.85, 0.90)
const GREY := Color(0.55, 0.55, 0.58)


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _initialize() -> void:
	print("=== WorldTheme-Tests ===")
	_test_pick_from()
	_test_features()
	_test_electro_words()
	_test_resolve()
	_test_palette()
	_test_new_worlds()
	_test_beat_contract()
	print("=== Ergebnis: %d fehlgeschlagen ===" % _failed)
	quit(1 if _failed > 0 else 0)


func _f(bpm: float, nps: float, kiai: float = 0.0, electro: bool = false) -> Dictionary:
	return {"bpm": bpm, "nps": nps, "kiai": kiai, "electro": electro}


func _test_pick_from() -> void:
	_check(WorldTheme.pick_from(_f(150, 6), 5.4, ORANGE) == "boss", "Sterne 5.4 -> Bosskampf")
	_check(WorldTheme.pick_from(_f(100, 2), 5.3, BLUE) == "boss", "Sterne 5.3 schlaegt ruhig")
	_check(WorldTheme.pick_from(_f(210, 9), 3.0, ORANGE) == "boss", "210 BPM dicht -> Bosskampf")
	_check(WorldTheme.pick_from(_f(210, 5, 0.4), 3.0, ORANGE) == "boss", "210 BPM kiai-lastig -> Bosskampf")
	_check(WorldTheme.pick_from(_f(195, 5, 0.1), 3.0, ORANGE) != "neon", "195 BPM mittel ohne Kiai -> dunkle Welt (nie Neon)")
	_check(WorldTheme.pick_from(_f(170, 6), 3.5, MAGENTA) != "neon", "170 BPM Magenta -> nie automatisch Neon")
	_check(WorldTheme.pick_from(_f(150, 5), 3.5, CYAN) != "neon", "150 BPM Cyan -> nie automatisch Neon")
	_check(WorldTheme.pick_from(_f(150, 5), 3.5, ORANGE) != "neon", "150 BPM Orange -> dunkle Welt (nie Neon)")
	_check(WorldTheme.pick_from(_f(128, 5, 0, true), 3.0, ORANGE) != "neon", "electro-Tag -> nie automatisch Neon")
	_check(WorldTheme.pick_from(_f(90, 2.5, 0, true), 2.0, BLUE) == "aurora", "electro aber ruhig -> Aurora")
	_check(WorldTheme.pick_from(_f(100, 3.5), 2.0, BLUE) == "aurora", "100 BPM blau -> Aurora")
	_check(WorldTheme.pick_from(_f(140, 2.5), 2.0, GREY) == "aurora", "duenn + blass -> Aurora")
	_check(WorldTheme.pick_from(_f(110, 4.5), 2.5, ORANGE) != "neon", "110 BPM Orange mittel -> dunkle Welt (nie Neon)")
	_check(WorldTheme.pick_from(_f(90, 3.0), 2.0, ORANGE) == "aurora", "90 BPM sehr ruhig -> Aurora")
	_check(WorldTheme.pick_from(_f(160, 7), 3.8, ORANGE) != "neon", "160 BPM orange -> dunkle Welt (nie Neon)")
	_check(WorldTheme.pick_from(_f(0, 0), -1.0, ORANGE) != "neon", "leere Map -> dunkle Welt (nie Neon)")
	_check(WorldTheme.pick_from(_f(150, 6), -1.0, ORANGE) != "neon", "Sterne unbekannt -> ignoriert, nie Neon")


func _tp(time: float, bl: float, red: bool = true) -> TimingPoint:
	var p := TimingPoint.new()
	p.time = time
	p.beat_length = bl
	p.uninherited = red
	return p


func _map(bpm_bl: float, n: int, step_ms: float, title: String = "", tags: String = "") -> Beatmap:
	var bm := Beatmap.new()
	bm.metadata = {"Title": title, "Artist": "x", "Tags": tags, "Version": "4K"}
	bm.timing_points.append(_tp(0.0, bpm_bl))
	for i in n:
		var h := HitObject.new()
		h.time = 1000.0 + i * step_ms
		bm.hit_objects.append(h)
	return bm


func _test_features() -> void:
	# 200 Noten in 20 s = 10 NPS, 120 BPM.
	var bm := _map(500.0, 201, 100.0)
	var f := WorldTheme.features(bm)
	_check(absf(float(f.bpm) - 120.0) < 0.01, "BPM 120 (%.2f)" % float(f.bpm))
	_check(absf(float(f.nps) - 10.0) < 0.1, "NPS 10 (%.2f)" % float(f.nps))
	_check(float(f.kiai) == 0.0, "kein Kiai")
	bm.kiai_intervals.append({"start": 1000.0, "end": 11000.0})
	f = WorldTheme.features(bm)
	_check(absf(float(f.kiai) - 0.5) < 0.01, "Kiai-Anteil 0.5 (%.2f)" % float(f.kiai))
	# Dominantes BPM nach Dauer: 4 s 100 BPM, 16 s 180 BPM, gruene Linie ignoriert.
	var tps := [_tp(0.0, 600.0), _tp(5000.0, 60000.0 / 180.0), _tp(6000.0, -50.0, false)]
	var b := WorldTheme.dominant_bpm(tps, 1000.0, 21000.0)
	_check(absf(b - 180.0) < 0.6, "dominantes BPM 180 (%.2f)" % b)
	_check(WorldTheme.dominant_bpm([], 0.0, 1.0) == 0.0, "ohne Timing 0 BPM")
	# End-to-end: 200 BPM + 10 NPS -> Bosskampf.
	var boss := _map(300.0, 201, 100.0)
	_check(WorldTheme.pick(boss, 5.4, ORANGE) == "boss", "pick: sehr schwer -> Bosskampf")
	var calm := _map(60000.0 / 90.0, 41, 500.0)
	_check(WorldTheme.pick(calm, 1.5, BLUE) == "aurora", "pick: 90 BPM duenn -> Aurora")
	var edm := _map(60000.0 / 128.0, 101, 200.0, "Song", "edm future bass")
	_check(WorldTheme.pick(edm, 2.8, ORANGE) != "neon", "pick: edm-Tag -> nie automatisch Neon")
	_check(WorldTheme.pick(null, 5.0, ORANGE) == "galaxy", "pick: null -> Galaxie")


func _test_electro_words() -> void:
	_check(WorldTheme.has_electro_word("Electronic Dance"), "electronic")
	_check(WorldTheme.has_electro_word("synthwave retro"), "synthwave")
	_check(WorldTheme.has_electro_word("J-Core HARDCORE"), "hardcore")
	_check(WorldTheme.has_electro_word("Drum & Bass"), "drum & bass")
	_check(WorldTheme.has_electro_word("EDM"), "EDM")
	_check(WorldTheme.has_electro_word("uplifting trance"), "trance")
	_check(not WorldTheme.has_electro_word("medmusic piano ballad"), "medmusic != edm")
	_check(not WorldTheme.has_electro_word("acoustic"), "acoustic")
	_check(not WorldTheme.has_electro_word(""), "leer")


func _test_resolve() -> void:
	var bm := _map(300.0, 201, 100.0)
	_check(WorldTheme.resolve("aurora", bm, 6.0, ORANGE) == "aurora", "Einstellung schlaegt Auto")
	_check(WorldTheme.resolve("", bm, 3.0, ORANGE) == WorldTheme.pick(bm, 3.0, ORANGE), "leer = Automatisch")
	_check(WorldTheme.resolve("quatsch", bm, 3.0, ORANGE) == WorldTheme.pick(bm, 3.0, ORANGE), "unbekannt = Automatisch")
	_check(WorldTheme.resolve("", null, 3.0, ORANGE) == "galaxy", "ohne Map Galaxie")


func _test_palette() -> void:
	_check(WorldTheme.palette("galaxy").is_empty(), "Galaxie ohne Farbsatz")
	for t in ["boss", "aurora", "neon"]:
		var p := WorldTheme.palette(t)
		_check(p.has("line") and p.has("kiai"), "%s hat Farbsatz" % t)
	var boss: Color = WorldTheme.palette("boss").line
	_check(boss.r > boss.g and boss.r > boss.b, "Boss monochrom blutrot")
	var neon: Color = WorldTheme.palette("neon").line
	_check(neon.r > 0.8 and neon.b > 0.6 and neon.g < 0.4, "Neon magenta")
	_check(WorldTheme.shader_path("galaxy") == "", "Galaxie nutzt sky_panorama")
	_check(WorldTheme.shader_path("boss") == "res://shaders/theme_boss.gdshader", "Boss-Shaderpfad")


func _test_new_worlds() -> void:
	for t in ["monolith", "rift", "nerve"]:
		_check(WorldTheme.NAMES.has(t), "%s in NAMES" % t)
		_check(WorldTheme.DARK.has(t) and WorldTheme.VARIETY.has(t), "%s in DARK/VARIETY" % t)
		_check(WorldTheme.LABELS.has(t), "%s hat Anzeige" % t)
		_check(WorldTheme.palette(t).has("line") and WorldTheme.palette(t).has("kiai"), "%s hat Farbsatz" % t)
	_check(WorldTheme.LABELS.rift == "Riss" and WorldTheme.LABELS.nerve == "Nerv", "Anzeige Riss/Nerv")
	var n: Color = WorldTheme.palette("nerve").line
	_check(n.r > n.g * 2.0 and n.r < 0.6, "Nerv dunkles Bordeaux")
	_check(WorldTheme.shader_path("rift") == "res://shaders/theme_rift.gdshader", "Rift-Shaderpfad")


func _test_beat_contract() -> void:
	var D := WorldTheme
	_check(D.drop_env(-1.0, -1.0, false) == 0.0, "Drop: kein Kiai = 0")
	_check(D.drop_env(0.0, -1.0, false) == 0.0, "Drop: Start 0")
	_check(absf(D.drop_env(1.0, -1.0, false) - D.DROP_PEAK) < 0.001, "Drop: Spitze 0.6 nach 1 Beat")
	_check(absf(D.drop_env(5.0, -1.0, false) - D.DROP_HOLD) < 0.001, "Drop: 0.3 nach 5 Beats")
	_check(absf(D.drop_env(40.0, -1.0, false) - D.DROP_HOLD) < 0.001, "Drop: haelt 0.3")
	_check(D.drop_env(0.5, -1.0, false) < D.DROP_PEAK, "Drop: steigt weich")
	_check(D.drop_env(3.0, -1.0, false) < D.drop_env(1.5, -1.0, false), "Drop: faellt nach Spitze")
	_check(D.drop_env(40.0, 2.0, false) < 0.001, "Drop: Kiai-Ende 0 nach 2 Beats")
	_check(absf(D.drop_env(1.0, -1.0, true) - 0.3) < 0.001, "Drop: Komfort x0.5")
	var mx := 0.0
	for i in 400:
		mx = maxf(mx, D.drop_env(i * 0.05, -1.0, false))
	_check(mx <= D.DROP_MAX + 0.0001, "Drop nie ueber DROP_MAX")
	# beat_step: monoton ueber Beats, springt auf dem Schlag, ruht davor.
	var last := -1.0
	var mono := true
	for b in 20:
		for k in 50:
			var v := D.beat_step(b, float(k) / 50.0)
			if v < last - 0.0001:
				mono = false
			last = v
	_check(mono, "beat_step monoton")
	_check(absf(D.beat_step(3, 0.0) - 3.0) < 0.001, "beat_step Beat 3 Phase 0 = 3")
	_check(D.beat_step(3, 0.99) > 3.99, "beat_step ruht vor naechstem Schlag")
	_check(absf(D.beat_step(3, 0.9999) - D.beat_step(4, 0.0)) < 0.001, "beat_step stetig am Schlag")
	_check(D.downbeat_pulse(0.0, 4) == 1.0 and D.downbeat_pulse(0.5, 4) < 0.01, "downbeat_pulse")
