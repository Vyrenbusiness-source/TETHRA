extends SceneTree

## Headless-Tests fuer AmFeatures (Task am-features, OMEN Auto-Mapper 4K).
## Unit-Tests mit synthetischen Signalen (Klicks, Sinus-Toene, Rauschen, tiefer Sinus, Mischung):
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_am_features_tests.gd
## Messung gegen Menschen-Maps, ein Prozess fuer alle Sets, schreibt docs/automap/features.md:
##   ... --script res://tests/run_am_features_tests.gd -- --measure <maps-ordner> <anzahl> [ordner eigene songs]
##   optional: --set name=wert,name=wert (Parameter ueberschreiben), --no-report,
##   --dump <datei.json> (Noten und Ereignisse je Set fuer Auswertungen ausserhalb von Godot)
## Liedform, Kiai, erwartete Dichte je Takt und Versatz je Art gegen die Menschen-Maps (Haelften A = Abstimm-,
## P = Pruef-Menge wie der Pruefstand), ein Prozess, schreibt docs/automap/form.md:
##   ... --script res://tests/run_am_features_tests.gd -- --form <maps-ordner> [anzahl] [--no-report]

const RATE := 22050
const KINDS: Array[String] = ["kick", "snare", "hat", "bass", "tonal", "vocal", "other"]
const PERC: Array[String] = ["kick", "snare", "hat", "other"]

var _passed := 0
var _failed := 0
var _done := false
var _rng := RandomNumberGenerator.new()


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _run() -> void:
	print("=== OMEN AmFeatures-Tests ===")
	_rng.seed = 4711
	var args := OS.get_cmdline_user_args()
	var params := {}
	var si := args.find("--set")
	if si >= 0 and si + 1 < args.size():
		for kv in args[si + 1].split(","):
			var parts := kv.split("=")
			if parts.size() == 2:
				params[parts[0]] = float(parts[1])
	var fi := args.find("--form")
	if fi >= 0 and fi + 1 < args.size():
		var cnt := 0
		if fi + 2 < args.size() and args[fi + 2].is_valid_int():
			cnt = int(args[fi + 2])
		_measure_form(args[fi + 1], cnt, params, args.find("--no-report") < 0)
		quit(0)
		return
	var mi := args.find("--measure")
	if mi >= 0 and mi + 1 < args.size():
		var own := ""
		if mi + 3 < args.size() and not args[mi + 3].begins_with("--"):
			own = args[mi + 3]
		var di := args.find("--dump")
		var dump := args[di + 1] if di >= 0 and di + 1 < args.size() else ""
		_measure(args[mi + 1], int(args[mi + 2]) if mi + 2 < args.size() else 150, own, params, args.find("--no-report") < 0, dump)
		quit(0)
		return
	_test_tags()
	_test_clicks()
	_test_tones()
	_test_noise()
	_test_bass()
	_test_voice()
	_test_mix()
	_test_sections()
	_test_form()
	_test_shift()
	_test_decode()
	_test_speed()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --------------------------------------------------------------------------- Signale

func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * RATE))
	b.fill(0.0)
	return b


func _sine(b: PackedFloat32Array, t0: float, dur: float, hz: float, amp: float, fade: float = 0.004) -> void:
	var s0 := int(t0 * RATE)
	var n := int(dur * RATE)
	var nf := maxi(1, int(fade * RATE))
	for i in n:
		if s0 + i >= b.size():
			break
		var env := minf(1.0, minf(float(i) / nf, float(n - i) / nf))
		b[s0 + i] += amp * env * sin(TAU * hz * i / RATE)


func _click(b: PackedFloat32Array, t0: float, amp: float = 0.9) -> void:
	var s0 := int(t0 * RATE)
	if s0 + 1 < b.size():
		b[s0] += amp
		b[s0 + 1] -= amp


func _noise(b: PackedFloat32Array, t0: float, dur: float, amp: float, high: bool) -> void:
	var s0 := int(t0 * RATE)
	var n := int(dur * RATE)
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		if s0 + i >= b.size():
			break
		var x := _rng.randf_range(-1.0, 1.0)
		var y := x
		if high:
			y = (x - 2.0 * p1 + p2) * 0.4
			p2 = p1
			p1 = x
		b[s0 + i] += amp * y * exp(-3.0 * i / n)


func _kick(b: PackedFloat32Array, t0: float, amp: float = 0.9) -> void:
	var s0 := int(t0 * RATE)
	var n := int(0.11 * RATE)
	var ph := 0.0
	for i in n:
		if s0 + i >= b.size():
			break
		var t := float(i) / RATE
		var hz := 48.0 + 110.0 * exp(-t / 0.018)
		ph += TAU * hz / RATE
		b[s0 + i] += amp * sin(ph) * exp(-t / 0.035)


## Kuenstliche Stimme: Obertonreihe mit Formanten, Vibrato und Gleiten, weicher Einsatz.
func _voice(b: PackedFloat32Array, t0: float, dur: float, f_a: float, f_b: float, amp: float) -> void:
	var s0 := int(t0 * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		if s0 + i >= b.size():
			break
		var t := float(i) / RATE
		var f := lerpf(f_a, f_b, float(i) / n) * (1.0 + 0.045 * sin(TAU * 6.0 * t))
		ph += TAU * f / RATE
		var env := minf(1.0, minf(t / 0.02, (dur - t) / 0.03))
		var v := 0.0
		for h in range(1, 9):
			var fh := f * h
			var w := 0.15 + exp(-pow((fh - 650.0) / 250.0, 2.0)) + 0.6 * exp(-pow((fh - 1300.0) / 350.0, 2.0))
			v += w * sin(ph * h) / h
		b[s0 + i] += amp * env * v * 0.5


func _an(b: PackedFloat32Array, params: Dictionary = {}) -> Dictionary:
	return AmFeatures.analyze(b, RATE, params)


func _count(an: Dictionary) -> Dictionary:
	var c := {}
	for k in KINDS:
		c[k] = 0
	for e: Dictionary in an.events:
		c[e.kind] += 1
	return c


## Naechstes Ereignis einer der Arten um t_ms; {} wenn keins innerhalb tol.
func _find(an: Dictionary, kinds: Array, t_ms: float, tol: float) -> Dictionary:
	var best := {}
	var bd := tol
	for e: Dictionary in an.events:
		if e.kind in kinds and absf(float(e.t_ms) - t_ms) <= bd:
			bd = absf(float(e.t_ms) - t_ms)
			best = e
	return best


## Ereignisse der Arten, die weiter als tol von allen Kanten (ms) entfernt liegen.
func _stray(an: Dictionary, kinds: Array, edges: Array, tol: float) -> int:
	var c := 0
	for e: Dictionary in an.events:
		if not (e.kind in kinds):
			continue
		var near := false
		for x: float in edges:
			if absf(float(e.t_ms) - x) <= tol:
				near = true
				break
		if not near:
			c += 1
	return c


func _check_shape(an: Dictionary, label: String) -> void:
	_ok(an.ok, label + ": ok")
	var sorted := true
	var fields := true
	var prev := -1.0
	for e: Dictionary in an.events:
		if float(e.t_ms) < prev:
			sorted = false
		prev = e.t_ms
		if not (e.kind in KINDS) or float(e.strength) < 0.0 or float(e.strength) > 1.0 or float(e.sustain_ms) < 0.0:
			fields = false
		if e.kind in ["bass", "tonal", "vocal"]:
			if float(e.pitch) < 0.0 or float(e.pitch) > 1.0:
				fields = false
		elif float(e.pitch) != -1.0:
			fields = false
	_ok(sorted, label + ": Ereignisse zeitlich sortiert")
	_ok(fields, label + ": Felder im Wertebereich (kind, strength, pitch, sustain)")
	var gapless: bool = not an.sections.is_empty()
	if gapless:
		gapless = absf(float(an.sections[0].start_ms)) < 0.01 and absf(float(an.sections[-1].end_ms) - float(an.duration_ms)) < 0.01
		for i in range(1, an.sections.size()):
			if absf(float(an.sections[i].start_ms) - float(an.sections[i - 1].end_ms)) > 0.01:
				gapless = false
		for s: Dictionary in an.sections:
			if not (s.kind in ["intro", "verse", "build", "chorus", "break", "outro"]) or not (s.lead in ["drums", "bass", "tonal", "vocal"]):
				gapless = false
	_ok(gapless, label + ": Abschnitte lueckenlos, Art und lead gueltig")
	_ok(an.energy.size() > 0 and absf(an.energy.size() * float(an.frame_ms) - float(an.duration_ms)) < 2.0 * float(an.frame_ms) + 1.0, label + ": energy je Frame")
	# bar_density: lueckenlos ueber den Song, Dichte >= 0, Zeit-Mittel 1; Abschnitte beginnen auf Takten
	var bd: Array = an.get("bar_density", [])
	var bd_ok := not bd.is_empty() and absf(float(bd[0].start_ms)) < 0.01 and absf(float(bd[-1].end_ms) - float(an.duration_ms)) < 0.01
	var wsum := 0.0
	var starts := {}
	for i in bd.size():
		var x: Dictionary = bd[i]
		if float(x.density) < 0.0 or float(x.end_ms) <= float(x.start_ms):
			bd_ok = false
		if i > 0 and absf(float(x.start_ms) - float(bd[i - 1].end_ms)) > 0.01:
			bd_ok = false
		wsum += float(x.density) * (float(x.end_ms) - float(x.start_ms))
		starts[snappedf(float(x.start_ms), 0.01)] = true
	_ok(bd_ok and absf(wsum / maxf(float(an.duration_ms), 1.0) - 1.0) < 0.01, label + ": bar_density lueckenlos, >= 0, Mittel 1")
	var on_bar := true
	for sc: Dictionary in an.sections:
		if not starts.has(snappedf(float(sc.start_ms), 0.01)):
			on_bar = false
	_ok(on_bar, label + ": Abschnitte beginnen auf Taktanfaengen")


# --------------------------------------------------------------------------- Tests

func _test_tags() -> void:
	var t := AmFeatures.tags_from("", "", "Beispiel Band - Nachtfahrt (Official Video)")
	_ok(t.artist == "Beispiel Band" and t.title == "Nachtfahrt", "tags: (Official Video) entfernt, Dateiname geteilt: %s" % [t])
	t = AmFeatures.tags_from("", "", "Wer - Lied [Lyrics] (prod. Jemand)")
	_ok(t.artist == "Wer" and t.title == "Lied", "tags: [Lyrics] und (prod. X) entfernt: %s" % [t])
	t = AmFeatures.tags_from("Tag Artist", "Tag Titel (Official Audio) prod. by X", "egal - anders")
	_ok(t.artist == "Tag Artist" and t.title == "Tag Titel", "tags: Tags haben Vorrang, Zusatz entfernt: %s" % [t])
	t = AmFeatures.tags_from("", "", "Nur Titel (Remix)")
	_ok(t.artist == "Unknown" and t.title == "Nur Titel (Remix)", "tags: (Remix) bleibt, Kuenstler Unknown: %s" % [t])
	t = AmFeatures.tags("Z:/gibt/es/nicht/A - B (Official Music Video) [4K].mp3")
	_ok(t.artist == "A" and t.title == "B", "tags(): Datei fehlt -> Dateiname: %s" % [t])
	_ok(not AmFeatures.decode("Z:/gibt/es/nicht.mp3").ok, "decode: fehlende Datei -> ok=false")
	_ok(not AmFeatures.analyze(PackedFloat32Array(), RATE).ok, "analyze: leeres Signal -> ok=false")
	var sil := _an(_buf(3.0))
	_ok(sil.ok and sil.events.is_empty() and sil.sections.size() == 1, "analyze: Stille -> keine Ereignisse, ein Abschnitt")


func _test_clicks() -> void:
	var b := _buf(8.0)
	var times: Array[float] = []
	var t := 0.5123
	while t < 7.5:
		times.append(t * 1000.0)
		_click(b, t)
		t += 0.4371
	var an := _an(b)
	_check_shape(an, "klicks")
	var hit := 0
	var worst := 0.0
	var sum := 0.0
	for tm in times:
		var e := _find(an, PERC, tm, 30.0)
		if not e.is_empty():
			var d := float(e.t_ms) - tm
			sum += d
			worst = maxf(worst, absf(d))
			if absf(d) <= 8.0:
				hit += 1
	var c := _count(an)
	print("  klicks: %d/%d in 8 ms, groesster Fehler %.1f ms, Mittel %.1f ms, %s" % [hit, times.size(), worst, sum / times.size(), c])
	_ok(hit == times.size(), "klicks: jeder Klick als perkussiver Anschlag innerhalb 8 ms")
	_ok(c.bass + c.tonal + c.vocal <= 1, "klicks: keine Ton-Ereignisse")
	_ok(c.kick + c.snare + c.hat + c.other <= times.size() * 3, "klicks: keine Flut zusaetzlicher Ereignisse")


func _test_tones() -> void:
	var b := _buf(7.0)
	var hz: Array[float] = [330.0, 440.0, 660.0, 880.0, 1320.0]
	var starts: Array[float] = []
	for i in hz.size():
		var t0 := 0.6071 + i * 1.2
		starts.append(t0 * 1000.0)
		_sine(b, t0, 0.7, hz[i], 0.5)
	var an := _an(b)
	_check_shape(an, "toene")
	var found := 0
	var mono := true
	var sus_ok := 0
	var pos_ok := 0
	var prev := -1.0
	var line := ""
	for i in hz.size():
		var e := _find(an, ["tonal"], starts[i], 15.0)
		if e.is_empty():
			continue
		found += 1
		if float(e.pitch) <= prev:
			mono = false
		prev = e.pitch
		var want := log(hz[i] / 130.8) / log(2093.0 / 130.8)
		if absf(float(e.pitch) - want) <= 0.03:
			pos_ok += 1
		if absf(float(e.sustain_ms) - 700.0) <= 60.0:
			sus_ok += 1
		line += " [%.0f Hz: dt %.1f, lage %.3f (soll %.3f), halten %.0f]" % [hz[i], float(e.t_ms) - starts[i], e.pitch, want, e.sustain_ms]
	print("  toene:", line, " ", _count(an))
	_ok(found == hz.size(), "toene: jeder Ton als tonal-Anschlag innerhalb 15 ms")
	_ok(mono, "toene: Lage steigt mit der Tonhoehe")
	_ok(pos_ok == hz.size(), "toene: Lage trifft die bekannte Hoehe (+-0,03)")
	_ok(sus_ok == hz.size(), "toene: sustain_ms trifft die Laenge 700 ms (+-60)")
	var c := _count(an)
	_ok(c.vocal == 0, "toene: feste Tonhoehe ist keine Stimme")
	var edges: Array = []
	for st in starts:
		edges.append(st)
		edges.append(st + 700.0)
	_ok(_stray(an, PERC + ["bass", "tonal"], edges, 40.0) == 0, "toene: keine Ereignisse abseits von Ton-Anfang und -Ende")
	_ok(c.tonal <= hz.size() + 1, "toene: ein tonal-Anschlag je Ton (ist %d)" % c.tonal)


func _test_noise() -> void:
	var b := _buf(8.0)
	var sn: Array[float] = []
	var ht: Array[float] = []
	var kk: Array[float] = []
	for i in 6:
		var t0 := 0.5 + i * 1.2
		kk.append(t0 * 1000.0)
		_kick(b, t0)
		sn.append((t0 + 0.4) * 1000.0)
		_noise(b, t0 + 0.4, 0.09, 0.6, false)
		ht.append((t0 + 0.8) * 1000.0)
		_noise(b, t0 + 0.8, 0.03, 0.5, true)
	var an := _an(b)
	_check_shape(an, "schlagzeug")
	var k := 0
	var s := 0
	var h := 0
	# Kick: Zeitlage gegen die Menschen-Maps abgestimmt (shift_low_ms); echte Kicks bauen den Tiefton
	# langsamer auf als dieser kuenstliche mit sofortigem Einsatz, daher hier 20 ms statt 12 ms.
	for t in kk:
		if not _find(an, ["kick"], t, 20.0).is_empty():
			k += 1
	for t in sn:
		if not _find(an, ["snare"], t, 12.0).is_empty():
			s += 1
	for t in ht:
		if not _find(an, ["hat"], t, 12.0).is_empty():
			h += 1
	print("  schlagzeug: kick %d/6, snare %d/6, hat %d/6, %s" % [k, s, h, _count(an)])
	_ok(k == 6, "schlagzeug: tiefer Schlag -> kick innerhalb 20 ms")
	_ok(s == 6, "schlagzeug: breites Rauschen -> snare innerhalb 12 ms")
	_ok(h == 6, "schlagzeug: hohes Rauschen -> hat innerhalb 12 ms")
	var wrong := 0
	for t in ht:
		if not _find(an, ["kick"], t, 25.0).is_empty():
			wrong += 1
	for t in kk:
		if not _find(an, ["hat"], t, 25.0).is_empty():
			wrong += 1
	_ok(wrong == 0, "schlagzeug: hat und kick nicht verwechselt")


func _test_bass() -> void:
	var b := _buf(8.0)
	var hz: Array[float] = [41.2, 55.0, 82.4, 110.0]
	var starts: Array[float] = []
	for i in hz.size():
		var t0 := 0.7 + i * 1.7
		starts.append(t0 * 1000.0)
		_sine(b, t0, 1.1, hz[i], 0.7, 0.008)
	var an := _an(b)
	_check_shape(an, "bass")
	var found := 0
	var mono := true
	var pos_ok := 0
	var sus_ok := 0
	var prev := -1.0
	var line := ""
	for i in hz.size():
		var e := _find(an, ["bass"], starts[i], 25.0)
		if e.is_empty():
			continue
		found += 1
		if float(e.pitch) <= prev:
			mono = false
		prev = e.pitch
		var want := log(hz[i] / 32.7) / log(261.6 / 32.7)
		if absf(float(e.pitch) - want) <= 0.04:
			pos_ok += 1
		if absf(float(e.sustain_ms) - 1100.0) <= 90.0:
			sus_ok += 1
		line += " [%.0f Hz: dt %.1f, lage %.3f (soll %.3f), halten %.0f]" % [hz[i], float(e.t_ms) - starts[i], e.pitch, want, e.sustain_ms]
	print("  bass:", line, " ", _count(an))
	_ok(found == hz.size(), "bass: tiefer Sinus -> bass-Anschlag innerhalb 25 ms")
	_ok(mono, "bass: Lage steigt mit der Tonhoehe")
	_ok(pos_ok == hz.size(), "bass: Lage trifft die bekannte Hoehe (+-0,04)")
	_ok(sus_ok == hz.size(), "bass: sustain_ms trifft die Laenge 1100 ms (+-90)")
	var c := _count(an)
	var edges: Array = []
	for st in starts:
		edges.append(st)
		edges.append(st + 1100.0)
	_ok(c.tonal + c.vocal + c.hat == 0, "bass: tiefer Ton erzeugt nichts in tonal/vocal/hat (%s)" % [c])
	_ok(_stray(an, KINDS, edges, 40.0) == 0, "bass: keine Ereignisse abseits von Ton-Anfang und -Ende")
	_ok(c.bass <= hz.size() + 1, "bass: ein bass-Anschlag je Ton (ist %d)" % c.bass)


func _test_voice() -> void:
	var b := _buf(8.0)
	var starts: Array[float] = []
	var t := 0.5
	var i := 0
	while t < 7.2:
		starts.append(t * 1000.0)
		var fa := 170.0 + 25.0 * (i % 4)
		_voice(b, t, 0.26, fa, fa * (1.12 if i % 2 == 0 else 0.9), 0.5)
		t += 0.34
		i += 1
	var an := _an(b)
	_check_shape(an, "stimme")
	var hit := 0
	for tm in starts:
		if not _find(an, ["vocal"], tm, 25.0).is_empty():
			hit += 1
	var c := _count(an)
	print("  stimme: %d/%d Silben als vocal in 25 ms, %s" % [hit, starts.size(), c])
	_ok(hit >= int(starts.size() * 0.85), "stimme: Silben-Anschlaege als vocal (>= 85 %)")
	_ok(c.vocal > c.tonal * 3, "stimme: gleitende Tonhoehe ueberwiegend vocal, nicht tonal")
	_ok(an.sections[0].lead == "vocal", "stimme: lead des Abschnitts ist vocal (ist %s)" % an.sections[0].lead)


## 20 s Mischung bei 120 BPM: Kick auf dem Schlag, Hat auf dem Off-Beat, Snare auf 2 und 4,
## Basslinie und Melodie versetzt. Liefert Signal und Soll-Zeiten je Ebene.
func _mix(sec: float) -> Dictionary:
	var b := _buf(sec)
	var kick: Array[float] = []
	var snare: Array[float] = []
	var hat: Array[float] = []
	var bass: Array[float] = []
	var mel: Array[float] = []
	var bass_hz: Array[float] = [55.0, 55.0, 65.4, 49.0]
	var mel_hz: Array[float] = [523.3, 659.3, 784.0, 659.3, 587.3, 698.5, 880.0, 698.5]
	var beat := 0.5
	var n := int((sec - 1.0) / beat)
	for i in n:
		var t0 := 0.25 + i * beat
		kick.append(t0 * 1000.0)
		_kick(b, t0, 0.8)
		hat.append((t0 + 0.25) * 1000.0)
		_noise(b, t0 + 0.25, 0.03, 0.25, true)
		if i % 2 == 1:
			snare.append((t0 + 0.002) * 1000.0)
		if i % 4 == 2:
			bass.append((t0 + 0.125) * 1000.0)
			_sine(b, t0 + 0.125, 1.2, bass_hz[(i >> 2) % 4], 0.45, 0.006)
		mel.append((t0 + 0.375) * 1000.0)
		_sine(b, t0 + 0.375, 0.3, mel_hz[i % 8], 0.22)
	for t in snare:
		_noise(b, t / 1000.0, 0.09, 0.45, false)
	return {"pcm": b, "kick": kick, "snare": snare, "hat": hat, "bass": bass, "tonal": mel}


func _test_mix() -> void:
	var m := _mix(20.0)
	var an := _an(m.pcm)
	_check_shape(an, "mischung")
	var line := ""
	for kind: String in ["kick", "snare", "hat", "bass", "tonal"]:
		var want: Array = m[kind]
		var hit := 0
		for t: float in want:
			# Snare liegt auf dem Kick: dort zaehlt jeder perkussive Anschlag der Trommeln.
			var kinds: Array = ["kick", "snare"] if kind == "snare" else [kind]
			if not _find(an, kinds, t, 20.0).is_empty():
				hit += 1
		var r := float(hit) / want.size()
		line += " %s %.2f" % [kind, r]
		_ok(r >= 0.9, "mischung: Ebene %s getrennt gefunden (Recall %.2f bei 20 ms, Ziel 0,90)" % [kind, r])
	print("  mischung:", line, " ", _count(an))
	var an1 := _an(m.pcm, {"threads": 1})
	_ok(an1.events.size() == an.events.size(), "mischung: gleiches Ergebnis mit threads=1 (%d gegen %d)" % [an1.events.size(), an.events.size()])
	var an2 := _an(m.pcm, {"kick_abs": 1000.0})
	_ok(_count(an2).kick == 0, "mischung: params ueberschreibt DEFAULTS (kick_abs)")


func _test_sections() -> void:
	var b := _buf(40.0)
	# 0..12 s leise Toene, 12..28 s volle Mischung, 28..40 s leise Toene
	var t := 0.5
	var i := 0
	while t < 39.0:
		if t < 12.0 or t >= 28.0:
			_sine(b, t, 0.8, 330.0 if i % 2 == 0 else 392.0, 0.05)
		t += 1.0
		i += 1
	var m := _mix(16.0)
	var off := int(12.0 * RATE)
	var mp: PackedFloat32Array = m.pcm
	for k in mp.size():
		b[off + k] += mp[k]
	var an := _an(b)
	_check_shape(an, "abschnitte")
	var cut_a := false
	var cut_b := false
	var line := ""
	var loud_i := 0.0
	var quiet_i := 1.0
	var kiai_loud := false
	var kiai_quiet := false
	for s: Dictionary in an.sections:
		line += " [%.1f-%.1f %s %.2f%s %s]" % [float(s.start_ms) / 1000.0, float(s.end_ms) / 1000.0, s.kind, s.intensity, " kiai" if s.kiai else "", s.lead]
		if absf(float(s.start_ms) - 12000.0) <= 1500.0:
			cut_a = true
		if absf(float(s.start_ms) - 28000.0) <= 1500.0:
			cut_b = true
		var mid := (float(s.start_ms) + float(s.end_ms)) * 0.5
		if mid > 13000.0 and mid < 27000.0:
			loud_i = maxf(loud_i, s.intensity)
			kiai_loud = kiai_loud or s.kiai
		elif mid < 11000.0 or mid > 29000.0:
			quiet_i = minf(quiet_i, s.intensity)
			kiai_quiet = kiai_quiet or s.kiai
	print("  abschnitte:", line)
	_ok(cut_a and cut_b, "abschnitte: Grenzen bei 12 s und 28 s (+-1,5 s)")
	_ok(loud_i > quiet_i + 0.3, "abschnitte: lauter Teil hat hoehere Intensitaet")
	_ok(kiai_loud and not kiai_quiet, "abschnitte: Kiai nur im lauten Teil")
	_ok(an.sections[0].kind == "intro" and an.sections[-1].kind == "outro", "abschnitte: intro am Anfang, outro am Ende")
	var e_q := 0.0
	var e_l := 0.0
	var fm: float = an.frame_ms
	for f in an.energy.size():
		var ts: float = f * fm
		if ts > 14000.0 and ts < 26000.0:
			e_l = maxf(e_l, an.energy[f])
		if ts > 2000.0 and ts < 10000.0:
			e_q = maxf(e_q, an.energy[f])
	_ok(e_l > e_q + 0.2 and e_l <= 1.0, "abschnitte: energy lauter Teil > leiser Teil (%.2f gegen %.2f)" % [e_l, e_q])


## Liedform: Intro, Strophe, Refrain, Strophe, Refrain, Outro (120 BPM, 2-s-Takte, Taktgitter als Eingabe).
## Der Refrain ist lauter, dichter (Snare, Achtel-Hats) und hat eine eigene Melodie; er kehrt wieder.
func _form_song() -> Dictionary:
	var parts := [["intro", 4], ["verse", 8], ["chorus", 8], ["verse", 8], ["chorus", 8], ["outro", 4]]
	var bars := 0
	for pt in parts:
		bars += int(pt[1])
	var t0 := 0.25
	var b := _buf(t0 + bars * 2.0 + 1.0)
	var verse_hz: Array[float] = [261.6, 329.6, 392.0, 329.6]
	var chorus_hz: Array[float] = [440.0, 554.4, 659.3, 740.0]
	var ranges := {"intro": [], "verse": [], "chorus": [], "outro": []}
	var bar := 0
	for pt in parts:
		var kind: String = pt[0]
		var t_a := t0 + bar * 2.0
		ranges[kind].append([t_a * 1000.0, (t_a + int(pt[1]) * 2.0) * 1000.0])
		for k in int(pt[1]) * 4:
			var t := t_a + k * 0.5
			match kind:
				"intro", "outro":
					if k % 2 == 0:
						_sine(b, t, 0.9, verse_hz[(k >> 1) % 4], 0.05)
				"verse":
					_kick(b, t, 0.45)
					_noise(b, t + 0.25, 0.03, 0.08, true)
					_sine(b, t, 0.45, verse_hz[k % 4], 0.08)
				"chorus":
					_kick(b, t, 0.9)
					if k % 2 == 1:
						_noise(b, t, 0.09, 0.45, false)
					_noise(b, t + 0.25, 0.03, 0.25, true)
					_noise(b, t, 0.03, 0.2, true)
					_sine(b, t, 0.45, chorus_hz[k % 4], 0.2)
					_sine(b, t, 0.45, chorus_hz[k % 4] * 0.5, 0.12)
		bar += int(pt[1])
	var grid := {"ok": true, "segments": [{"start_ms": t0 * 1000.0 - AmGrid.OSU_LEAD_MS, "beat_ms": 500.0, "meter": 4,
			"downbeat_ms": t0 * 1000.0 - AmGrid.OSU_LEAD_MS}]}
	return {"pcm": b, "grid": grid, "ranges": ranges}


## Anteil der Zeit in den Bereichen iv, deren Abschnitt kiai == want_kiai hat.
func _share(an: Dictionary, iv: Array, want_kiai: bool) -> float:
	var on := 0.0
	var tot := 0.0
	for r in iv:
		for sc: Dictionary in an.sections:
			var lo := maxf(float(r[0]), float(sc.start_ms))
			var hi := minf(float(r[1]), float(sc.end_ms))
			if hi > lo:
				tot += hi - lo
				if bool(sc.kiai) == want_kiai:
					on += hi - lo
	return on / maxf(tot, 1.0)


func _mean_density(an: Dictionary, iv: Array) -> float:
	var s := 0.0
	var tot := 0.0
	for r in iv:
		for x: Dictionary in an.bar_density:
			var lo := maxf(float(r[0]), float(x.start_ms))
			var hi := minf(float(r[1]), float(x.end_ms))
			if hi > lo:
				s += float(x.density) * (hi - lo)
				tot += hi - lo
	return s / maxf(tot, 1.0)


func _test_form() -> void:
	var song := _form_song()
	var an := _an(song.pcm, {"grid": song.grid})
	_check_shape(an, "liedform")
	var line := ""
	for sc: Dictionary in an.sections:
		line += " [%.1f-%.1f %s %.2f%s]" % [float(sc.start_ms) / 1000.0, float(sc.end_ms) / 1000.0, sc.kind, sc.intensity, " kiai" if sc.kiai else ""]
	print("  liedform:", line)
	var rg: Dictionary = song.ranges
	var k_ch := _share(an, rg.chorus, true)
	var k_other := 1.0 - _share(an, rg.verse + rg.intro + rg.outro, false)
	_ok(k_ch >= 0.75, "liedform: beide Refrains Kiai (Anteil %.2f, Ziel 0,75)" % k_ch)
	_ok(k_other <= 0.2, "liedform: Strophen/Intro/Outro ohne Kiai (Kiai-Anteil %.2f, hoechstens 0,2)" % k_other)
	# Grenzen auf dem gegebenen Gitter: jeder Abschnitt beginnt auf 250 ms + k * 2000 ms (oder 0)
	var on_grid := true
	for sc: Dictionary in an.sections:
		var t: float = sc.start_ms
		var r := fposmod(t - 250.0, 2000.0)
		if t > 0.0 and r > 0.5 and r < 1999.5:
			on_grid = false
	_ok(on_grid, "liedform: Abschnitte beginnen auf den Taktanfaengen des Eingabe-Gitters")
	var d_ch := _mean_density(an, rg.chorus)
	var d_v := _mean_density(an, rg.verse)
	var d_io := _mean_density(an, rg.intro + rg.outro)
	_ok(d_ch > d_v and d_v > d_io, "liedform: erwartete Dichte Refrain > Strophe > Intro/Outro (%.2f / %.2f / %.2f)" % [d_ch, d_v, d_io])
	_ok(an.sections[0].kind == "intro" and an.sections[-1].kind == "outro", "liedform: intro am Anfang, outro am Ende")
	# ohne Gitter: AmGrid laeuft selbst, Ergebnis bleibt brauchbar
	var an2 := _an(song.pcm)
	_check_shape(an2, "liedform ohne Gitter")
	var k2 := _share(an2, rg.chorus, true)
	_ok(k2 >= 0.5, "liedform ohne Gitter: Refrains ueberwiegend Kiai (%.2f)" % k2)
	var an3 := _an(song.pcm, {"form_track_grid": 0.0})
	_check_shape(an3, "liedform feste Bloecke")


## Versatz je Art: shift_snare_ms verschiebt nur Snares, shift_hat_ms nur Hats.
func _test_shift() -> void:
	var m := _mix(10.0)
	var a := _an(m.pcm, {"shift_snare_ms": 0.0, "shift_hat_ms": 0.0, "shift_other_ms": 0.0})
	var b := _an(m.pcm, {"shift_snare_ms": -6.0, "shift_hat_ms": 4.0, "shift_other_ms": 0.0})
	var d := {"snare": [], "hat": [], "kick": []}
	for kind: String in d:
		var ta: Array = a.events.filter(func(e: Dictionary) -> bool: return e.kind == kind).map(func(e: Dictionary) -> float: return e.t_ms)
		var tb: Array = b.events.filter(func(e: Dictionary) -> bool: return e.kind == kind).map(func(e: Dictionary) -> float: return e.t_ms)
		if ta.size() == tb.size():
			for i in ta.size():
				d[kind].append(float(tb[i]) - float(ta[i]))
	var med := func(v: Array) -> float:
		if v.is_empty():
			return NAN
		var c := v.duplicate()
		c.sort()
		return c[c.size() >> 1]
	var ms: float = med.call(d.snare)
	var mh: float = med.call(d.hat)
	var mk: float = med.call(d.kick)
	_ok(absf(ms + 6.0) < 0.01 and absf(mh - 4.0) < 0.01 and absf(mk) < 0.01,
			"versatz: je Art eigener Wert (Snare %.1f, Hat %.1f, Kick %.1f ms)" % [ms, mh, mk])


func _write_wav(path: String, pcm: PackedFloat32Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	var n := pcm.size()
	f.store_string("RIFF")
	f.store_32(36 + n * 2)
	f.store_string("WAVEfmt ")
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(RATE)
	f.store_32(RATE * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_string("data")
	f.store_32(n * 2)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(pcm[i], -1.0, 1.0) * 32000.0))
	f.store_buffer(bytes)
	f.close()


func _test_decode() -> void:
	if ClipExporter.find_ffmpeg() == "":
		print("  SKIP: kein ffmpeg, decode-Dateitest uebersprungen")
		return
	var b := _buf(3.0)
	_sine(b, 1.0, 1.0, 440.0, 0.5)
	var path := ProjectSettings.globalize_path("user://am_features_test (Official Video).wav")
	_write_wav(path, b)
	var d := AmFeatures.decode(path)
	_ok(d.ok and d.rate == RATE and absf(float(d.duration_ms) - 3000.0) < 30.0, "decode: WAV -> mono 22050 Hz, 3 s (%s, %.0f ms)" % [d.error, d.duration_ms])
	if d.ok:
		var an := AmFeatures.analyze(d.pcm, d.rate)
		_ok(not _find(an, ["tonal"], 1000.0, 15.0).is_empty(), "decode: Ton nach dem Dekodieren an derselben Stelle")
	var t := AmFeatures.tags(path)
	_ok(t.title == "am_features_test", "tags(): Datei ohne Tags -> Dateiname ohne Zusatz (%s)" % [t])
	DirAccess.remove_absolute(path)


func _test_speed() -> void:
	var m := _mix(20.0)
	var one: PackedFloat32Array = m.pcm
	var b := PackedFloat32Array()
	for i in 12:
		b.append_array(one)
	var t0 := Time.get_ticks_msec()
	var an := _an(b)
	var ms := Time.get_ticks_msec() - t0
	print("  dauer: analyze fuer %.0f s Audio: %d ms (%d Ereignisse, %d Kerne)" % [b.size() / float(RATE), ms, an.events.size(), OS.get_processor_count()])
	_ok(an.ok and ms <= 8000, "dauer: analyze <= 8 s fuer 4 min (ist %d ms)" % ms)


# --------------------------------------------------------------------------- Messung

func _parse_osu(text: String) -> Dictionary:
	var res := {"audio": "", "mode": 0, "times": PackedFloat32Array(), "hs": PackedInt32Array(), "holds": [], "kiai": []}
	var sec := ""
	var kiai_on := false
	var kiai_start := 0.0
	var last_t := 0.0
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("//"):
			continue
		if line.begins_with("["):
			sec = line
			continue
		if sec == "[General]":
			if line.begins_with("AudioFilename:"):
				res.audio = line.substr(14).strip_edges()
			elif line.begins_with("Mode:"):
				res.mode = int(line.substr(5).strip_edges())
		elif sec == "[TimingPoints]":
			var p := line.split(",")
			if p.size() >= 8:
				var on := (int(p[7]) & 1) == 1
				var tt := float(p[0])
				if on and not kiai_on:
					kiai_start = tt
				elif kiai_on and not on:
					res.kiai.append([kiai_start, tt])
				kiai_on = on
		elif sec == "[HitObjects]":
			var p := line.split(",")
			if p.size() < 5:
				continue
			var typ := int(p[3])
			var tt := float(p[2])
			last_t = maxf(last_t, tt)
			if typ & 8:
				continue
			res.times.append(tt)
			res.hs.append(int(p[4]))
			if (typ & 128) and p.size() >= 6:
				var en := float(p[5].split(":")[0])
				if en > tt:
					res.holds.append([tt, en])
					last_t = maxf(last_t, en)
	if kiai_on:
		res.kiai.append([kiai_start, last_t])
	return res


## Fuer jedes a (sortiert) der Abstand b - a zum naechsten b (sortiert); 1e9 wenn b leer.
func _nearest(a: PackedFloat32Array, b: PackedFloat32Array, shift: float) -> PackedFloat32Array:
	var res := PackedFloat32Array()
	res.resize(a.size())
	var j := 0
	var nb := b.size()
	for i in a.size():
		var x := a[i] + shift
		if nb == 0:
			res[i] = 1e9
			continue
		while j + 1 < nb and absf(b[j + 1] - x) <= absf(b[j] - x):
			j += 1
		res[i] = b[j] - x
	return res


func _within(d: PackedFloat32Array, tol: float) -> int:
	var c := 0
	for v in d:
		if absf(v) <= tol:
			c += 1
	return c


func _median(v: PackedFloat32Array) -> float:
	if v.is_empty():
		return 0.0
	var c := v.duplicate()
	c.sort()
	return c[c.size() >> 1]


func _iou(a: Array, b: Array, dur: float) -> float:
	var n := int(dur / 100.0) + 1
	var ma := PackedByteArray()
	ma.resize(n)
	ma.fill(0)
	var mb := ma.duplicate()
	for iv in a:
		for i in range(clampi(int(float(iv[0]) / 100.0), 0, n), clampi(int(float(iv[1]) / 100.0), 0, n)):
			ma[i] = 1
	for iv in b:
		for i in range(clampi(int(float(iv[0]) / 100.0), 0, n), clampi(int(float(iv[1]) / 100.0), 0, n)):
			mb[i] = 1
	var inter := 0
	var uni := 0
	for i in n:
		if ma[i] == 1 and mb[i] == 1:
			inter += 1
		if ma[i] == 1 or mb[i] == 1:
			uni += 1
	return float(inter) / uni if uni > 0 else 1.0


func _read_set(osz: String, tmp: String) -> Dictionary:
	var z := ZIPReader.new()
	if z.open(osz) != OK:
		return {}
	var files := z.get_files()
	var diffs: Array = []
	for f in files:
		if f.to_lower().ends_with(".osu"):
			var d := _parse_osu(z.read_file(f).get_string_from_utf8())
			if d.audio != "" and d.times.size() >= 30:
				diffs.append(d)
	if diffs.is_empty():
		z.close()
		return {}
	var top: Dictionary = diffs[0]
	for d: Dictionary in diffs:
		if d.times.size() > top.times.size():
			top = d
	var audio: String = top.audio
	var zname := ""
	for f in files:
		if f.to_lower() == audio.to_lower():
			zname = f
	if zname == "":
		z.close()
		return {}
	var bytes := z.read_file(zname)
	z.close()
	if bytes.is_empty():
		return {}
	var apath := tmp.path_join("a." + audio.get_extension())
	var fh := FileAccess.open(apath, FileAccess.WRITE)
	fh.store_buffer(bytes)
	fh.close()
	var dec := AmFeatures.decode(apath)
	DirAccess.remove_absolute(apath)
	if not dec.ok:
		return {}
	var all := PackedFloat32Array()
	var holds: Array = []
	var hold_notes := 0
	for d: Dictionary in diffs:
		if String(d.audio).to_lower() != audio.to_lower():
			continue
		all.append_array(d.times)
		if d.mode == 3 and d.holds.size() > holds.size():
			holds = d.holds
			hold_notes = d.times.size()
	all.sort()
	var uniq := PackedFloat32Array()
	for t in all:
		if uniq.is_empty() or t - uniq[uniq.size() - 1] > 2.0:
			uniq.append(t)
	return {"pcm": dec.pcm, "notes": uniq, "top": top, "holds": holds, "hold_share": float(holds.size()) / maxi(hold_notes, 1)}


func _measure(maps_dir: String, count: int, own_dir: String, params: Dictionary, report: bool, dump: String = "") -> void:
	var dumped: Array = []
	var files: Array[String] = []
	for f in DirAccess.get_files_at(maps_dir):
		if f.to_lower().ends_with(".osz"):
			files.append(f)
	files.sort()
	var tmp := ProjectSettings.globalize_path("user://am_features_measure")
	DirAccess.make_dir_recursive_absolute(tmp)
	var sets: Array = []
	var stride := maxf(1.0, float(files.size()) / maxi(count, 1))
	var t_start := Time.get_ticks_msec()
	var k := 0
	while sets.size() < count and int(k * stride) < files.size():
		var name := files[int(k * stride)]
		k += 1
		var rs := _read_set(maps_dir.path_join(name), tmp)
		if rs.is_empty():
			print("  uebersprungen: ", name.left(50))
			continue
		var pcm: PackedFloat32Array = rs.pcm
		var t0 := Time.get_ticks_msec()
		var an := AmFeatures.analyze(pcm, RATE, params)
		var ms := Time.get_ticks_msec() - t0
		if not an.ok:
			continue
		var ev_t := PackedFloat32Array()
		var ev_k := PackedByteArray()
		var sus: Array = []
		for e: Dictionary in an.events:
			ev_t.append(e.t_ms)
			ev_k.append(KINDS.find(e.kind))
			if float(e.sustain_ms) > 0.0:
				sus.append([e.t_ms, float(e.t_ms) + float(e.sustain_ms)])
		var secs: Array = []
		for s: Dictionary in an.sections:
			secs.append([s.start_ms, s.end_ms, s.intensity, s.kiai, s.lead, s.kind])
		var top: Dictionary = rs.top
		sets.append({"name": name, "notes": rs.notes, "ev_t": ev_t, "ev_k": ev_k, "sus": sus, "secs": secs,
				"dur": an.duration_ms, "ms": ms, "holds": rs.holds, "hold_share": rs.hold_share,
				"kiai": top.kiai, "top_t": top.times, "top_hs": top.hs})
		if dump != "":
			var evs: Array = []
			for e: Dictionary in an.events:
				evs.append([snappedf(e.t_ms, 0.1), KINDS.find(e.kind), snappedf(e.strength, 0.001), snappedf(e.pitch, 0.001), snappedf(e.sustain_ms, 1.0)])
			dumped.append({"name": name, "notes": Array(rs.notes), "events": evs, "kiai": top.kiai, "holds": rs.holds,
					"secs": secs, "dur": an.duration_ms, "top_t": Array(top.times), "top_hs": Array(top.hs),
					"energy": Array(an.energy), "frame_ms": an.frame_ms})
		var d0 := _nearest(rs.notes, ev_t, 0.0)
		print("%3d %s | %.0f s | %d Noten | %d Ereignisse | roh-Recall30 %.2f | %d ms" % [sets.size(), name.left(44),
				float(an.duration_ms) / 1000.0, rs.notes.size(), ev_t.size(), float(_within(d0, 30.0)) / rs.notes.size(), ms])
	var total_s := (Time.get_ticks_msec() - t_start) / 1000.0
	if dump != "":
		var fd := FileAccess.open(dump, FileAccess.WRITE)
		fd.store_string(JSON.stringify(dumped))
		fd.close()
		print("Dump: ", dump)
	if sets.is_empty():
		print("keine Sets")
		return

	# Vorlauf der Maps gegen die akustischen Anschlaege: Median ueber die Sets
	var leads := PackedFloat32Array()
	for s: Dictionary in sets:
		var d := _nearest(s.notes, s.ev_t, 0.0)
		var near := PackedFloat32Array()
		for v in d:
			if absf(v) <= 40.0:
				near.append(v)
		s["lead"] = _median(near)
		leads.append(s.lead)
	var lead := _median(leads)

	var n_notes := 0
	var hit20 := 0
	var hit30 := 0
	var chance20 := 0
	var hit20_own := 0
	var per_set := PackedFloat32Array()
	var kind_hit := PackedInt32Array()
	var kind_chance := PackedInt32Array()
	var kind_ev := PackedInt32Array()
	var kind_on := PackedInt32Array()
	var kind_on_ch := PackedInt32Array()
	for arr: PackedInt32Array in [kind_hit, kind_chance, kind_ev, kind_on, kind_on_ch]:
		arr.resize(KINDS.size())
		arr.fill(0)
	# Vorlauf je Ebene: der Wert (0..50 ms, 2er-Schritte), bei dem die meisten Ereignisse der Ebene auf Noten liegen
	var lead_k := PackedFloat32Array()
	for i in KINDS.size():
		var best_l := 0.0
		var best_c := -1
		for li in 26:
			var c := 0
			for s: Dictionary in sets:
				var ts := PackedFloat32Array()
				var nts := PackedFloat32Array()
				for t: float in s.notes:
					nts.append(t + li * 2.0)
				for j in s.ev_t.size():
					if s.ev_k[j] == i:
						ts.append(s.ev_t[j])
				c += _within(_nearest(ts, nts, 0.0), 20.0)
			if c > best_c:
				best_c = c
				best_l = li * 2.0
		lead_k.append(best_l)
	var n_ev := 0
	var ev_on := 0
	var dur_sum := 0.0
	var ms_sum := 0.0
	var ms_per_min_max := 0.0
	var hold_n := 0
	var hold_hit := 0
	var hold_len_err := PackedFloat32Array()
	var sus_time := 0.0
	var sus_on := 0.0
	var hold_sets := 0
	var kiai_sets := 0
	var kiai_iou_sum := 0.0
	var clap_n := 0
	var clap_sn := 0
	var plain_n := 0
	var plain_sn := 0
	var fin_n := 0
	var fin_hat := 0
	var plain_hat := 0
	var whi_n := 0
	var whi_hat := 0
	var lead_cnt := {"drums": 0.0, "bass": 0.0, "tonal": 0.0, "vocal": 0.0}
	var sec_cnt := 0
	for s: Dictionary in sets:
		var notes: PackedFloat32Array = s.notes
		var ev_t: PackedFloat32Array = s.ev_t
		var ev_k: PackedByteArray = s.ev_k
		var d := _nearest(notes, ev_t, lead)
		var h20 := _within(d, 20.0)
		n_notes += notes.size()
		hit20 += h20
		hit30 += _within(d, 30.0)
		per_set.append(float(h20) / notes.size())
		chance20 += _within(_nearest(notes, ev_t, lead + 137.0), 20.0)
		hit20_own += _within(_nearest(notes, ev_t, float(s.lead)), 20.0)
		var note_shift := PackedFloat32Array()
		var note_ch := PackedFloat32Array()
		for t in notes:
			note_shift.append(t + lead)
			note_ch.append(t + lead + 137.0)
		ev_on += _within(_nearest(ev_t, note_shift, 0.0), 20.0)
		n_ev += ev_t.size()
		var by_kind: Array[PackedFloat32Array] = []
		for i in KINDS.size():
			by_kind.append(PackedFloat32Array())
		for i in ev_t.size():
			by_kind[ev_k[i]].append(ev_t[i])
		for i in KINDS.size():
			kind_ev[i] += by_kind[i].size()
			kind_hit[i] += _within(_nearest(notes, by_kind[i], lead), 20.0)
			kind_chance[i] += _within(_nearest(notes, by_kind[i], lead + 137.0), 20.0)
			kind_on[i] += _within(_nearest(by_kind[i], note_shift, 0.0), 20.0)
			kind_on_ch[i] += _within(_nearest(by_kind[i], note_ch, 0.0), 20.0)
		dur_sum += float(s.dur)
		ms_sum += float(s.ms)
		ms_per_min_max = maxf(ms_per_min_max, float(s.ms) / (float(s.dur) / 60000.0))
		# Holds
		var holds: Array = s.holds
		var sus: Array = s.sus
		if holds.size() >= 10 and float(s.hold_share) >= 0.1:
			hold_sets += 1
			for h in holds:
				var hs: float = float(h[0]) + lead
				var he: float = float(h[1]) + lead
				if he - hs < 250.0:
					continue
				hold_n += 1
				for u in sus:
					if absf(float(u[0]) - hs) <= 40.0:
						hold_hit += 1
						hold_len_err.append(absf((float(u[1]) - float(u[0])) - (he - hs)))
						break
			var hmask := PackedByteArray()
			var hn := int(float(s.dur) / 20.0) + 2
			hmask.resize(hn)
			hmask.fill(0)
			for h in holds:
				for i in range(clampi(int((float(h[0]) + lead) / 20.0), 0, hn), clampi(int((float(h[1]) + lead) / 20.0), 0, hn)):
					hmask[i] = 1
			for u in sus:
				for i in range(clampi(int(float(u[0]) / 20.0), 0, hn), clampi(int(float(u[1]) / 20.0), 0, hn)):
					sus_time += 1.0
					if hmask[i] == 1:
						sus_on += 1.0
		# Kiai
		var secs: Array = s.secs
		var kiai: Array = s.kiai
		if not kiai.is_empty():
			kiai_sets += 1
			var own_k: Array = []
			for sc in secs:
				if sc[3]:
					own_k.append([sc[0], sc[1]])
			kiai_iou_sum += _iou(own_k, kiai, s.dur)
		for sc in secs:
			lead_cnt[sc[4]] += (float(sc[1]) - float(sc[0]))
			sec_cnt += 1
		# Hitsounds der dichtesten Diff: Clap -> snare, Finish/Whistle -> hat
		var top_t: PackedFloat32Array = s.top_t
		var top_hs: PackedInt32Array = s.top_hs
		var claps := 0
		for hsv in top_hs:
			if hsv & 8:
				claps += 1
		if claps >= 20:
			var order: Array = []
			for i in top_t.size():
				order.append([top_t[i], top_hs[i]])
			order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
			var st := PackedFloat32Array()
			for o in order:
				st.append(o[0])
			var d_sn := _nearest(st, by_kind[1], lead)
			var d_ht := _nearest(st, by_kind[2], lead)
			for i in order.size():
				var hsv: int = order[i][1]
				var is_sn := absf(d_sn[i]) <= 25.0
				var is_ht := absf(d_ht[i]) <= 25.0
				if hsv & 8:
					clap_n += 1
					clap_sn += 1 if is_sn else 0
				if hsv & 4:
					fin_n += 1
					fin_hat += 1 if is_ht else 0
				if hsv & 2:
					whi_n += 1
					whi_hat += 1 if is_ht else 0
				if (hsv & 14) == 0:
					plain_n += 1
					plain_sn += 1 if is_sn else 0
					plain_hat += 1 if is_ht else 0
	var set95 := 0
	for v in per_set:
		if v >= 0.95:
			set95 += 1
	var ms_4min := ms_sum / (dur_sum / 240000.0)
	var mins := dur_sum / 60000.0

	var L: Array[String] = []
	L.append("# AmFeatures: Messung gegen Menschen-Maps (OMEN Auto-Mapper 4K)")
	L.append("")
	L.append("Erzeugt von `tests/run_am_features_tests.gd -- --measure` in einem Prozess. Alle Zahlen dieser Datei")
	L.append("sind gemessen; was nur geschlossen ist, steht unter \"Grenzen\".")
	L.append("")
	L.append("- Sets: %d (von %d .osz, gleichmaessig verteilt), %.0f min Audio, %d Map-Noten (alle Diffs je Set vereinigt)" % [sets.size(), files.size(), mins, n_notes])
	L.append("- Parameter: DEFAULTS%s" % ("" if params.is_empty() else " mit " + str(params)))
	L.append("- Vorlauf der Maps gegen die erkannten Anschlaege (Median ueber die Sets): %.1f ms (Ereignis minus Note)" % lead)
	L.append("")
	L.append("## Ziele und Ist")
	L.append("")
	L.append("| Kennzahl | Ziel | Ist | erreicht |")
	L.append("|---|---|---|---|")
	var rec20 := float(hit20) / n_notes
	L.append("| Recall der Map-Noten, alle Ebenen zusammen, +-20 ms | >= 0,95 | %.3f | %s |" % [rec20, "ja" if rec20 >= 0.95 else "nein"])
	L.append("| dasselbe bei +-30 ms (alter Mapper: 0,87) | - | %.3f | - |" % (float(hit30) / n_notes))
	L.append("| dasselbe, Vorlauf je Set statt global, +-20 ms | - | %.3f | - |" % (float(hit20_own) / n_notes))
	L.append("| Zufallsniveau (Noten um 137 ms verschoben), +-20 ms | - | %.3f | - |" % (float(chance20) / n_notes))
	L.append("| Sets mit Recall >= 0,95 | - | %d von %d | - |" % [set95, sets.size()])
	L.append("| Anteil der Ereignisse, die auf einer Map-Note liegen, +-20 ms | - | %.3f | - |" % (float(ev_on) / maxi(n_ev, 1)))
	L.append("| Ereignisse je Sekunde (alle Ebenen) | - | %.1f | - |" % (n_ev / (dur_sum / 1000.0)))
	var kiai_iou := kiai_iou_sum / maxi(kiai_sets, 1)
	L.append("| Kiai: IoU gegen die Map (%d Sets mit Kiai) | >= 0,6 | %.3f | %s |" % [kiai_sets, kiai_iou, "ja" if kiai_iou >= 0.6 else "nein"])
	var hrec := float(hold_hit) / maxi(hold_n, 1)
	L.append("| Holds (>= 250 ms, %d Sets mit >= 10 %% Holds): Anteil mit sustain-Ereignis am Hold-Beginn (+-40 ms) | - | %.3f (%d von %d) | - |" % [hold_sets, hrec, hold_hit, hold_n])
	L.append("| sustain-Zeit, die in diesen Sets auf einem Hold liegt | - | %.3f | - |" % (sus_on / maxf(sus_time, 1.0)))
	L.append("| Laengenfehler sustain gegen Hold (Median, getroffene Holds) | - | %.0f ms | - |" % _median(hold_len_err))
	L.append("| Dauer analyze, hochgerechnet auf 4 min (Mittel) | <= 8 s | %.1f s | %s |" % [ms_4min / 1000.0, "ja" if ms_4min <= 8000.0 else "nein"])
	L.append("| Dauer analyze, langsamstes Set auf 4 min gerechnet | <= 8 s | %.1f s | %s |" % [ms_per_min_max * 4.0 / 1000.0, "ja" if ms_per_min_max * 4.0 <= 8000.0 else "nein"])
	L.append("")
	L.append("## Ist-Werte je Ebene")
	L.append("")
	L.append("Recall allein = Anteil der Map-Noten, an denen ein Ereignis genau dieser Ebene liegt (+-20 ms).")
	L.append("Zufall = derselbe Wert mit um 137 ms verschobenen Noten. Treffer = Anteil der Ereignisse der Ebene auf einer Map-Note,")
	L.append("Treffer-Zufall dasselbe mit verschobenen Noten. Vorlauf der Ebene = Vorlauf, bei dem die Ebene allein die meisten Treffer hat")
	L.append("(gleich dem globalen Vorlauf = Zeitlage der Ebene stimmt).")
	L.append("")
	L.append("| Ebene | Ereignisse/min | Recall allein | Zufall | Treffer | Treffer-Zufall | Vorlauf der Ebene |")
	L.append("|---|---|---|---|---|---|---|")
	for i in KINDS.size():
		L.append("| %s | %.1f | %.3f | %.3f | %.3f | %.3f | %.0f ms |" % [KINDS[i], kind_ev[i] / mins, float(kind_hit[i]) / n_notes,
				float(kind_chance[i]) / n_notes, float(kind_on[i]) / maxi(kind_ev[i], 1), float(kind_on_ch[i]) / maxi(kind_ev[i], 1), lead_k[i]])
	L.append("")
	L.append("## Hitsounds der Maps als Hinweis (dichteste Diff, nur Sets mit >= 20 Claps)")
	L.append("")
	L.append("| Noten mit | Anzahl | snare in +-25 ms | hat in +-25 ms |")
	L.append("|---|---|---|---|")
	L.append("| Clap | %d | %.3f | - |" % [clap_n, float(clap_sn) / maxi(clap_n, 1)])
	L.append("| Finish | %d | - | %.3f |" % [fin_n, float(fin_hat) / maxi(fin_n, 1)])
	L.append("| Whistle | %d | - | %.3f |" % [whi_n, float(whi_hat) / maxi(whi_n, 1)])
	L.append("| ohne Zusatz | %d | %.3f | %.3f |" % [plain_n, float(plain_sn) / maxi(plain_n, 1), float(plain_hat) / maxi(plain_n, 1)])
	L.append("")
	L.append("## Abschnitte und fuehrende Ebene (Anteil der Songzeit)")
	L.append("")
	L.append("Abschnitte je Set im Mittel: %.1f" % (float(sec_cnt) / sets.size()))
	L.append("")
	L.append("| lead | Anteil |")
	L.append("|---|---|")
	for key: String in ["drums", "bass", "tonal", "vocal"]:
		L.append("| %s | %.3f |" % [key, float(lead_cnt[key]) / dur_sum])
	L.append("")

	L.append("## Grenzen (geschlossen, nicht gemessen)")
	L.append("")
	L.append("- Die Maps sagen nicht, welche Ebene eine Note traegt. \"Recall allein\" und \"Treffer\" messen nur, ob Ereignisse einer")
	L.append("  Ebene auf Map-Noten liegen, nicht ob die Art stimmt. Ob ein Kick wirklich ein Kick ist, belegen nur die Unit-Tests")
	L.append("  mit kuenstlichen Signalen; die Hitsound-Tabelle ist ein grober Hinweis (Mapper setzen Clap/Finish/Whistle nach Stil).")
	L.append("- Das Ziel Recall >= 0,95 bei 20 ms ueber die vereinigten Noten aller Diffs ist nicht erreicht: Maps setzen viele Noten")
	L.append("  ohne eigenen Einsatz (Rhythmus fortgefuehrt, Gitter-Fuellung, Streams). Mehr Ereignisse heben den Recall nur auf")
	L.append("  Zufallsniveau (Zeile Zufall), deshalb gilt Treffer gegen Treffer-Zufall als Mass fuer echte Einsaetze.")
	L.append("- Zeitlage: absolut per Klick-Test, die Gruppen Kick/Bass und Ton/Stimme relativ dazu gegen 12 dieser Sets abgestimmt")
	L.append("  (fester Versatz). Mit 512er-FFT (23 ms) schwanken Tiefton-Baender unter Basstoenen; Kick bleibt die schwaechste Ebene.")
	L.append("- vocal gegen tonal: Stimme = gleitende Tonhoehe der staerksten Spektrallinie. In dichter, mehrstimmiger Musik springt")
	L.append("  diese Linie zwischen Instrumenten; Stimme wird dann als tonal erkannt oder umgekehrt. Ohne Wahrheit in den Maps.")
	L.append("- lead der Abschnitte ist eine Heuristik aus Ereignisdichten und Stimm-Anteil, ohne Wahrheit. Kiai und erwartete")
	L.append("  Dichte kommen aus der Liedform (gelernt auf der Abstimm-Menge); Messung je Haelfte in docs/automap/form.md (--form).")
	L.append("- sustain folgt dem harmonischen Pegel im Band des Tons; ob ein Mapper dort einen Hold setzt, ist Stilfrage.")
	L.append("")

	# Eigene Songs
	if own_dir != "":
		L.append("## Songs des Nutzers (nur Zahlen)")
		L.append("")
		var names: Array[String] = []
		for f in DirAccess.get_files_at(own_dir):
			if f.get_extension().to_lower() in ["mp3", "ogg", "wav", "flac", "m4a", "opus"]:
				names.append(f)
		names.sort()
		for f in names:
			var dec := AmFeatures.decode(own_dir.path_join(f))
			if not dec.ok:
				L.append("- %s: nicht dekodierbar (%s)" % [f, dec.error])
				continue
			var tg := AmFeatures.tags(own_dir.path_join(f))
			var t0 := Time.get_ticks_msec()
			var an := AmFeatures.analyze(dec.pcm, dec.rate, params)
			var ms := Time.get_ticks_msec() - t0
			var c := _count(an)
			var sus_c := 0
			for e: Dictionary in an.events:
				if float(e.sustain_ms) > 0.0:
					sus_c += 1
			L.append("### %s - %s" % [tg.artist, tg.title])
			L.append("")
			L.append("Datei `%s`, %.0f s, analyze %d ms (auf 4 min: %.1f s)." % [f, float(an.duration_ms) / 1000.0, ms, ms / (float(an.duration_ms) / 240000.0) / 1000.0])
			L.append("")
			var cl := ""
			for kd in KINDS:
				cl += "%s %d, " % [kd, c[kd]]
			L.append("Ereignisse: %sdavon gehalten %d." % [cl, sus_c])
			L.append("")
			L.append("| von | bis | Art | Intensitaet | Kiai | lead |")
			L.append("|---|---|---|---|---|---|")
			for sc: Dictionary in an.sections:
				L.append("| %.1f s | %.1f s | %s | %.2f | %s | %s |" % [float(sc.start_ms) / 1000.0, float(sc.end_ms) / 1000.0, sc.kind, sc.intensity, "ja" if sc.kiai else "-", sc.lead])
			L.append("")
			print("eigener Song: %s | %d ms | %s" % [f, ms, c])
	var text := "\n".join(L)
	print(text)
	print("Messung: %d Sets in %.0f s" % [sets.size(), total_s])
	if report:
		var out := FileAccess.open("res://docs/automap/features.md", FileAccess.WRITE)
		out.store_string(text + "\n")
		out.close()
		print("geschrieben: docs/automap/features.md")


# --------------------------------------------------------------------------- Messung Liedform

const BENCH := preload("res://tools/automap_bench.gd")
const PROFILES := ["Easy", "Normal", "Hard", "Insane", "Expert"]


## Erwartete Noten je 2-s-Fenster aus bar_density (akustisch; Map-Zeit = minus OSU_LEAD), Fenster ab 0 bis t_end.
static func form_curve(bar_density: Array, t_end: float, win: float = 2000.0, lead: float = AmGrid.OSU_LEAD_MS) -> Array:
	var n := maxi(int(ceil(t_end / win)), 1)
	var c: Array = []
	c.resize(n)
	c.fill(0.0)
	for x: Dictionary in bar_density:
		var a := maxf(float(x.start_ms) - lead, 0.0)
		var b := float(x.end_ms) - lead
		var d := float(x.density)
		if b <= a:
			continue
		var k := int(a / win)
		while k < n and k * win < b:
			var lo := maxf(a, k * win)
			var hi := minf(b, (k + 1) * win)
			if hi > lo:
				c[k] += d * (hi - lo) / 1000.0
			k += 1
	return c


## Versatz Ereignis (minus OSU_LEAD) gegen die naechste Note der vereinigten Diffs, |d| <= 40 ms, je Art.
static func _kind_offsets(events: Array, union: PackedFloat64Array, out: Dictionary) -> void:
	for e: Dictionary in events:
		var t := float(e.t_ms) - AmGrid.OSU_LEAD_MS
		var i := union.bsearch(t)
		var best := INF
		for j in [i - 1, i]:
			if j >= 0 and j < union.size() and absf(t - union[j]) < absf(best):
				best = t - union[j]
		if absf(best) <= 40.0:
			out[e.kind].append(best)


## Gipfel einer Verteilung (1-ms-Klassen, 5 ms geglaettet), wie im Prototyp der Abstimmung.
static func _mode_ms(v: Array) -> float:
	if v.is_empty():
		return NAN
	var h := PackedFloat32Array()
	h.resize(81)
	h.fill(0.0)
	for x in v:
		var k := int(round(float(x))) + 40
		if k >= 0 and k <= 80:
			h[k] += 1.0
	var best := 0
	var bv := -1.0
	for k in 81:
		var s := 0.0
		for j in range(k - 2, k + 3):
			if j >= 0 and j <= 80:
				s += h[j]
		if s > bv:
			bv = s
			best = k
	return best - 40.0


func _measure_form(maps_dir: String, count: int, params: Dictionary, report: bool) -> void:
	var files: Array = BENCH.list_osz(maps_dir)
	StarService.prefetch_dir(maps_dir)
	var tmp := ProjectSettings.globalize_path("user://am_features_measure")
	DirAccess.make_dir_recursive_absolute(tmp)
	var acc := {}
	for sp: String in ["tune", "test"]:
		var offs := {}
		for k in KINDS:
			offs[k] = []
		acc[sp] = {"iou": [], "dens": [], "dens_hard": [], "sets": 0, "no_kiai": 0, "ms": [], "ms_grid": [], "offs": offs,
				"kiai_share": [], "secs": 0}
	var t_start := Time.get_ticks_msec()
	var n_done := 0
	for f in files:
		if count > 0 and n_done >= count:
			break
		var osz: String = maps_dir.path_join(f)
		var truth: Dictionary = BENCH.load_truth(osz, StarService.stars_for(osz))
		if not truth.ok or (truth.diffs4k as Array).is_empty():
			continue
		var audio: String = BENCH.extract_file(osz, truth.audio_name, tmp.path_join("form_audio_tmp"))
		if audio == "":
			continue
		var dec := AmFeatures.decode(audio)
		DirAccess.remove_absolute(audio)
		if not dec.ok:
			continue
		var t0 := Time.get_ticks_msec()
		var grid := AmGrid.track(dec.pcm, dec.rate, {})
		var ms_grid := Time.get_ticks_msec() - t0
		if not grid.get("ok", false):
			continue
		var p2 := params.duplicate()
		p2["grid"] = grid
		t0 = Time.get_ticks_msec()
		var an := AmFeatures.analyze(dec.pcm, dec.rate, p2)
		var ms := Time.get_ticks_msec() - t0
		if not an.ok:
			continue
		n_done += 1
		var a: Dictionary = acc[BENCH.split_of(f)]
		a.sets += 1
		var to4 := 240000.0 / maxf(float(an.duration_ms), 30000.0)
		a.ms.append(ms * to4)
		a.ms_grid.append(ms_grid * to4)
		a.secs += (an.sections as Array).size()
		# Kiai wie im geschriebenen Set (AmWriter: Map-Zeit, auf Taktanfaenge gelegt), IoU wie der Pruefstand
		var gen: Array = AmWriter.kiai_ranges(an, grid)
		if gen.is_empty() and (truth.kiai as Array).is_empty():
			a.no_kiai += 1
		else:
			var v = BENCH.interval_iou(gen, truth.kiai)
			a.iou.append(0.0 if is_nan(v) else v)
		var ks := 0.0
		for iv in gen:
			ks += float(iv[1]) - float(iv[0])
		a.kiai_share.append(ks / maxf(float(an.duration_ms), 1.0))
		# erwartete Dichte gegen die Vergleichs-Diff je Profil (Auswahl wie Pruefstand)
		var last_ev := 0.0
		if not (an.events as Array).is_empty():
			last_ev = float(an.events[-1].t_ms) - AmGrid.OSU_LEAD_MS
		for prof in PROFILES:
			var hi: int = BENCH.pick_human_diff(truth.diffs4k, prof)
			if hi < 0:
				continue
			var ht: Array = truth.diffs4k[hi].times
			if ht.is_empty():
				continue
			var t_end := maxf(float(ht[-1]), last_ev) + 1.0
			var r := BENCH.pearson(form_curve(an.bar_density, t_end), BENCH.density_curve(ht, t_end))
			if not is_nan(r):
				a.dens.append(r)
				if prof == "Hard":
					a.dens_hard.append(r)
		var union := PackedFloat64Array()
		for d in truth.diffs4k:
			for t in d.times:
				union.append(float(t))
		union.sort()
		_kind_offsets(an.events, union, a.offs)
		print("%3d %s | %s | Kiai %s | %d Abschnitte | analyze %d ms, Gitter %d ms" % [n_done, f.left(40), BENCH.split_of(f),
				"-" if a.iou.is_empty() else "%.2f" % float(a.iou[-1]), (an.sections as Array).size(), ms, ms_grid])
	var L: Array[String] = []
	L.append("# AmFeatures: Liedform, Kiai, erwartete Dichte je Takt (OMEN Auto-Mapper 4K)")
	L.append("")
	L.append("Erzeugt von `tests/run_am_features_tests.gd -- --form` in einem Prozess, %d Sets, %.0f s. Alle Zahlen gemessen." % [n_done, (Time.get_ticks_msec() - t_start) / 1000.0])
	L.append("Haelften wie der Pruefstand (`automap_bench.gd split_of`): A = Abstimm-Menge (die Gewichte von Kiai und Dichte")
	L.append("sind nur auf A gelernt), P = Pruef-Menge (nie gesehen). Parameter: DEFAULTS%s." % ("" if params.is_empty() else " mit " + str(params)))
	L.append("")
	L.append("| Kennzahl | Ziel | A | P |")
	L.append("|---|---|---|---|")
	var A: Dictionary = acc.tune
	var P: Dictionary = acc.test
	L.append("| Sets | - | %d | %d |" % [A.sets, P.sets])
	L.append("| Kiai IoU (wie Pruefstand: Map oder Erzeugnis mit Kiai) | >= 0,6 | %.3f (n=%d) | %.3f (n=%d) |" % [BENCH.mean(A.iou), A.iou.size(), BENCH.mean(P.iou), P.iou.size()])
	L.append("| Sets ohne Kiai auf beiden Seiten (zaehlen nicht) | - | %d | %d |" % [A.no_kiai, P.no_kiai])
	L.append("| Kiai-Anteil der Songzeit, erzeugt (Median) | - | %.2f | %.2f |" % [BENCH.median(A.kiai_share), BENCH.median(P.kiai_share)])
	L.append("| Korrelation erwartete Dichte (bar_density) gegen Mensch, 2-s-Fenster, alle Profile | >= 0,8 | %.3f (n=%d) | %.3f (n=%d) |" % [BENCH.mean(A.dens), A.dens.size(), BENCH.mean(P.dens), P.dens.size()])
	L.append("| dasselbe nur Hard | - | %.3f (n=%d) | %.3f (n=%d) |" % [BENCH.mean(A.dens_hard), A.dens_hard.size(), BENCH.mean(P.dens_hard), P.dens_hard.size()])
	L.append("| Abschnitte je Set (Mittel) | - | %.1f | %.1f |" % [float(A.secs) / maxi(A.sets, 1), float(P.secs) / maxi(P.sets, 1)])
	L.append("| analyze mit Gitter als Eingabe, auf 4 min, 95. Perzentil | <= 8 s | %.1f s | %.1f s |" % [BENCH.percentile(A.ms, 95.0) / 1000.0, BENCH.percentile(P.ms, 95.0) / 1000.0])
	var both_a: Array = []
	var both_p: Array = []
	for i in A.ms.size():
		both_a.append(float(A.ms[i]) + float(A.ms_grid[i]))
	for i in P.ms.size():
		both_p.append(float(P.ms[i]) + float(P.ms_grid[i]))
	L.append("| analyze ohne Gitter (ruft AmGrid.track selbst), auf 4 min, 95. Perzentil | <= 8 s | %.1f s | %.1f s |" % [BENCH.percentile(both_a, 95.0) / 1000.0, BENCH.percentile(both_p, 95.0) / 1000.0])
	L.append("")
	L.append("## Versatz je Art (Ereignis minus OSU_LEAD minus naechste Menschen-Note, alle Diffs vereinigt, |d| <= 40 ms)")
	L.append("")
	L.append("| Art | Median A | Median P | Gipfel A | Gipfel P | n (A+P) |")
	L.append("|---|---|---|---|---|---|")
	for k in KINDS:
		var oa: Array = A.offs[k]
		var op: Array = P.offs[k]
		L.append("| %s | %+.1f ms | %+.1f ms | %+.0f ms | %+.0f ms | %d |" % [k, BENCH.median(oa), BENCH.median(op), _mode_ms(oa), _mode_ms(op), oa.size() + op.size()])
	L.append("")
	L.append("## Vorher (Stand 300f1a3, Abschnitte ueber Lautheits-Neuheit, Kiai ab Intensitaets-Schwelle)")
	L.append("")
	L.append("Gemessen auf denselben Sets und mit denselben Definitionen (A / P): Kiai IoU 0,295 / 0,262 (Pruefstand: 0,294 /")
	L.append("0,266); Korrelation der Abschnitts-Intensitaet gegen Mensch 0,498 / 0,547 (Hard 0,511 / 0,543); Ereignisse je Takt")
	L.append("als Dichte 0,639 / 0,679. Versatz (Median, onset_shift_ms = 6): Snare +10,4, Hat +7,1, other +10,5 ms; Gipfel")
	L.append("+11 / +7 / +12 ms; Kick +2,5, Bass +1,3, Ton +0,7, Stimme +0,9 ms.")
	L.append("")
	L.append("## Pruefstand end-to-end (tools/automap_bench.gd --mapper new, AmChart unveraendert, 2026-11-14)")
	L.append("")
	L.append("P / A vorher (300f1a3) -> nachher: Kiai IoU 0,266 / 0,294 -> 0,368 / 0,431. Dichte-Korrelation der erzeugten Maps")
	L.append("0,544 / 0,523 -> 0,529 / 0,508 (AmChart nutzt bar_density noch nicht, nur die Intensitaet je Abschnitt). Hard auf")
	L.append("Menschen-Note 76,5 % -> 76,3 %, Menschen-Noten getroffen 61,1 % -> 62,1 %. Dauer 95. Perzentil (4 min) 5,5 -> 9,2 s")
	L.append("(Maximum 14,5 s; Rechner durch parallele Laeufe belastet, Laufzeit 1285 s statt 779 s): AutoMapper4K uebergibt das")
	L.append("Gitter noch nicht an analyze, AmGrid.track laeuft darum zweimal.")
	L.append("")
	L.append("## Verfahren")
	L.append("")
	L.append("- Takte: Taktanfaenge des Gitters (+ OSU_LEAD), unter 1 s Laenge zu Doppeltakten zusammengefasst; ohne Gitter 2-s-Bloecke.")
	L.append("- Merkmale je Takt: Chroma (FFT 4096, 60 Hz..2,1 kHz, Wurzel, L2), Klangfarbe (log-Pegel der 20 Baender, je Band")
	L.append("  z-normiert, L2), Lautheit, perkussiver/harmonischer Pegel, Stimm-Anteil, Ereignisse und Staerke je Art und Sekunde.")
	L.append("- Selbstaehnlichkeit: 0,5 x Kosinus(Chroma) + 0,5 x Kosinus(Klangfarbe). Neuheit: Gauss-Schachbrett-Kern, halbe")
	L.append("  Breite min(8, Takte/4), auf P95 = 1 normiert. 4-Takt-Bloecke auf der Phase mit der groessten Neuheitssumme.")
	L.append("- Kiai je Block: logistisch ueber 58 Merkmale (Block-Mittel und Rang von Lautheit, Pegeln, Ereignissen, Kick, Snare,")
	L.append("  Hat, Stimme; Unterschied zum vorigen, naechsten und vorvorigen Block; beste Wiederholung eines gleich langen Blocks;")
	L.append("  Neuheit am Blockanfang; Lage im Song; Lautheits-Rang des Blocks; Aehnlichkeit mit den lautesten 25 % der Bloecke).")
	L.append("  Kiai ab p > 0,25 (form_kiai_thr). Refrain = wiederkehrender, energiereicher Block.")
	L.append("- Dichte je Takt: linear (Ridge) ueber die z-Werte der 11 Reihen, ihr Mittel ueber 4 und 8 Takte, ihr Block-Mittel,")
	L.append("  Kiai-p und die z-Werte der Ereignisse je Art; density = max(0, 1 + 0,3 x Modell), danach Zeit-Mittel 1.")
	L.append("- Gewichte: gelernt nur auf A (Abstimm-Menge) mit numpy auf einem Merkmals-Auszug aus einem Godot-Lauf (Skript nicht")
	L.append("  im Repo); im Spiel stehen sie als Konstanten in am_features.gd (FORM_KIAI_W, FORM_DENS_W). Port gegen den Prototyp")
	L.append("  geprueft: gleiche Bloecke, |p| und Dichte auf 0,03 gleich (Rundung im Auszug).")
	L.append("")
	L.append("## Grenzen")
	L.append("")
	L.append("- Rund ein Viertel der Menschen-Maps hat gar kein Kiai; dort zaehlt jedes erzeugte Kiai mit IoU 0. Ob ein Mapper")
	L.append("  Kiai setzt, steht nicht im Audio. Selbst mit perfekter Wahl auf Sets mit Kiai bliebe die IoU dadurch unter ~0,75.")
	L.append("- Mapper waehlen verschiedene Refrains (oft nur den ersten Drop oder nur den letzten Chorus); die Wahl ist Stil.")
	L.append("- Zwei Menschen-Diffs desselben Sets korrelieren in der Dichte (2-s-Fenster) im Mittel mit 0,79 (Prototyp, 1377")
	L.append("  Paare, je Set alle Diff-Paare); das Ziel 0,8 liegt damit an der Grenze dessen, was eine Kurve fuer alle Profile kann.")
	L.append("- Gemessen ist die Kurve selbst. Wie nah die erzeugte Map ihr folgt, entscheidet AmChart (Pruefstand).")
	L.append("")
	var text := "\n".join(L)
	print(text)
	if report:
		var out := FileAccess.open("res://docs/automap/form.md", FileAccess.WRITE)
		out.store_string(text + "\n")
		out.close()
		print("geschrieben: docs/automap/form.md")
