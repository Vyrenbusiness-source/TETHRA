extends SceneTree

## Songstart bei SV-Maps: die ersten Noten bekommen ihre volle Anflugzeit.
## Muster der Map "sath4 - <3#006 [Recollectia]": rote Linie erst bei der
## ersten Note (498 ms), danach gruene Linien 2,2x / 0,6x / 1,0x im Takt.
## Ursache des Pop-ins: SyncClock.play() laeuft mitten im Laden der Szene,
## die Ladezeit (1,5 s bei 4788 Timing-Points) frass den Vorlauf.
## Ausfuehren:
##   Godot..._console.exe --headless --path . --script res://tests/run_sv_start_tests.gd

const LEAD := 1500.0
const LOAD_MS := 400

var _passed := 0
var _failed := 0
var _started := false
var _clock: Node
var _phase := 0
var _frames := 0
var _t_resume := 0
var _v_start := 0.0
var _t_start_usec := 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		print("=== OMEN SV-Start-Tests ===")
		_test_lead_math()
		_test_lead_cap()
		_clock = root.get_node_or_null("/root/SyncClock")
		_ok(_clock != null, "SyncClock vorhanden")
		if _clock == null:
			return _done()
		_test_load_then_pause()
		# Ohne Countdown (z. B. --shot): Ladezeit bis zum ersten Frame.
		_clock.play(_silence(4.0), LEAD)
		OS.delay_msec(LOAD_MS)
		return false
	_frames += 1
	if _phase == 0 and _frames >= 2:
		var v: float = _clock.raw_time_ms()
		_ok(v < -LEAD + 250.0, "ohne Pause: Ladezeit frisst den Vorlauf nicht (%.0f ms)" % v)
		_ok(v > -LEAD - 100.0, "ohne Pause: Vorlauf nicht laenger als verlangt (%.0f ms)" % v)
		_t_resume = Time.get_ticks_msec()
		_v_start = v
		_t_start_usec = Time.get_ticks_usec()
		_phase = 1
	elif _phase == 1 and Time.get_ticks_msec() - _t_resume >= 200:
		var v2: float = _clock.raw_time_ms()
		_ok(v2 > -LEAD + 150.0 and v2 < -LEAD + 700.0, "Vorlauf laeuft danach in Echtzeit (%.0f ms)" % v2)
		_phase = 2
	elif _phase == 2 and _clock.raw_time_ms() >= 150.0:
		# Sync: der Fix verschiebt nur den Beginn des Vorlaufs. Songzeit 0 bleibt
		# der Audio-Start, die Uhr laeuft ueber den Wechsel Vorlauf -> Audio
		# ohne Sprung in Echtzeit weiter (Trefferzeiten unveraendert).
		var v3: float = _clock.raw_time_ms()
		var want := _v_start + float(Time.get_ticks_usec() - _t_start_usec) / 1000.0
		_ok(_clock.is_playing(), "nach dem Vorlauf spielt das Audio")
		# Toleranz: Dummy-Audiotreiber mischt in groben Bloecken (30-90 ms gemessen).
		_ok(absf(v3 - want) < 150.0, "Songzeit laeuft ueber den Audio-Start ohne Sprung (%.0f ms, erwartet %.0f)" % [v3, want])
		_clock.stop()
		return _done()
	return false


func _done() -> bool:
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
	return true


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


## Wie mania_3d._ready: play() beim Laden, dann langes Laden, dann pause()
## fuer den Start-Countdown. Nach dem Countdown muss der ganze Vorlauf da sein.
func _test_load_then_pause() -> void:
	print("- Ladezeit zwischen play() und pause() zaehlt nicht zum Vorlauf")
	_clock.play(_silence(4.0), LEAD)
	OS.delay_msec(LOAD_MS)
	var during: float = _clock.raw_time_ms()
	_ok(during < -LEAD + 50.0, "waehrend des Ladens steht die Uhr am Vorlauf-Anfang (%.0f ms)" % during)
	_clock.pause()
	var held: float = _clock.raw_time_ms()
	_ok(held < -LEAD + 50.0, "nach pause(): voller Vorlauf uebrig (%.0f ms)" % held)
	OS.delay_msec(100)
	_ok(absf(_clock.raw_time_ms() - held) < 0.001, "Pause friert die Vorlaufuhr ein")
	_clock.resume()
	OS.delay_msec(100)
	var run: float = _clock.raw_time_ms()
	_ok(run > held + 60.0 and run < held + 300.0, "nach resume() laeuft der Vorlauf (%.0f ms)" % (run - held))
	_clock.stop()


## Vorlauf-Rechnung der Repro-Map: erste Note 498 ms, SV erst ab 499 ms.
func _test_lead_math() -> void:
	print("- start_lead_ms: SV-Muster ab der ersten Note")
	var tps := "498,428.571428571429,4,1,1,40,1,8\n"
	var t := 499.0
	while t < 20000.0:
		tps += "%d,-45.4545454545455,4,1,1,40,0,0\n" % int(t)
		tps += "%d,-166.6666667,4,1,1,40,0,0\n" % int(t + 25.0)
		tps += "%d,-100,4,1,1,40,0,0\n" % int(t + 106.0)
		t += 321.0
	var notes := ""
	for i in 40:
		notes += "%d,192,%d,1,0,0:0:0:0:\n" % [64 + 128 * (i % 4), 498 + i * 107]
	var txt := "osu file format v14\n\n[General]\nMode: 3\n\n[Difficulty]\nHPDrainRate: 5\nCircleSize: 4\nOverallDifficulty: 7\nApproachRate: 5\nSliderMultiplier: 1.4\n\n[TimingPoints]\n" + tps + "\n[HitObjects]\n" + notes
	var bm: Beatmap = OsuParser.parse(txt).beatmap
	for scale in [0.5, 0.836, 1.0, 2.0]:
		var pre := ManiaCore.preempt_for(scale)
		var sm := ManiaCore.build_scroll_map(bm, {})
		_ok(not sm.is_identity(), "Scroll %.2f: Map hat SV" % scale)
		var lead := ManiaCore.start_lead_ms(bm, scale, {})
		# Jede Note muss beim Uhrstart (-lead) noch ausserhalb des Sichtfensters
		# liegen und danach mindestens START_BUFFER_MS Zeit haben.
		var worst := INF
		for o in bm.hit_objects:
			worst = minf(worst, sm.spawn_time(o.time, pre) + lead)
		_ok(worst >= ManiaCore.START_BUFFER_MS - 0.001, "Scroll %.2f: fruehester Spawn %.0f ms nach Uhrstart" % [scale, worst])
		# Erste Note: vor der ersten Linie gilt Tempo 1 -> volle Anflugzeit.
		_ok(absf(sm.spawn_time(498.0, pre) - (498.0 - pre)) < 0.001, "Scroll %.2f: Note 0 volle Anflugzeit %.0f ms" % [scale, pre])
		_ok(absf(sm.visible_lead(498.0, pre, pre) - pre) < 0.001, "Scroll %.2f: Note 0 durchgehend sichtbar" % scale)


## Extrem langsamer Anfang (rote Linie 60000 ms/Beat, Rest 400 ms): ohne Deckel
## laege der frueheste Spawn Minuten vor dem Song. Der Vorlauf bleibt bei
## normaler Anflugzeit + MAX_SV_LEAD_EXTRA_MS.
func _test_lead_cap() -> void:
	print("- start_lead_ms: Deckel bei extrem langsamem Anfang")
	var tps := "0,60000,4,1,1,40,1,0
5000,400,4,1,1,40,1,0
"
	var notes := ""
	for i in 200:
		notes += "%d,192,%d,1,0,0:0:0:0:
" % [64 + 128 * (i % 4), 5000 + i * 200]
	var txt := "osu file format v14

[General]
Mode: 3

[Difficulty]
HPDrainRate: 5
CircleSize: 4
OverallDifficulty: 7
ApproachRate: 5
SliderMultiplier: 1.4

[TimingPoints]
" + tps + "
[HitObjects]
" + notes
	var bm: Beatmap = OsuParser.parse(txt).beatmap
	for scale in [0.104, 1.0, 2.0]:
		var pre := ManiaCore.preempt_for(scale)
		var raw := ManiaCore.START_BUFFER_MS - ManiaCore.first_spawn_ms(bm, scale, {})
		var base := maxf(ManiaCore.START_BUFFER_MS - (5000.0 - pre), 0.0)
		var lead := ManiaCore.start_lead_ms(bm, scale, {})
		_ok(raw > base + 20000.0, "Scroll %.2f: ohne Deckel %.0f ms Vorlauf" % [scale, raw])
		_ok(absf(lead - (base + ManiaCore.MAX_SV_LEAD_EXTRA_MS)) < 0.001, "Scroll %.2f: Vorlauf gedeckelt auf %.0f ms" % [scale, lead])
		_ok(lead >= base, "Scroll %.2f: nie unter der normalen Anflugzeit" % scale)


func _silence(sec: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 48000
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(int(sec * 48000.0) * 2)
	wav.data = data
	return wav
