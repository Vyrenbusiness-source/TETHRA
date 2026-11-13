extends SceneTree

## Headless-Tests fuer AmFeatures (Task am-features, OMEN Auto-Mapper 4K).
## Unit-Tests mit synthetischen Signalen (Klicks, Sinus-Toene, Rauschen, tiefer Sinus, Mischung):
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_am_features_tests.gd
## Messung gegen Menschen-Maps, ein Prozess fuer alle Sets, schreibt docs/automap/features.md:
##   ... --script res://tests/run_am_features_tests.gd -- --measure <maps-ordner> <anzahl> [ordner eigene songs]
##   optional: --set name=wert,name=wert (Parameter ueberschreiben), --no-report

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
	var mi := args.find("--measure")
	if mi >= 0 and mi + 1 < args.size():
		var own := ""
		if mi + 3 < args.size() and not args[mi + 3].begins_with("--"):
			own = args[mi + 3]
		_measure(args[mi + 1], int(args[mi + 2]) if mi + 2 < args.size() else 150, own, params, args.find("--no-report") < 0)
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
	for t in kk:
		if not _find(an, ["kick"], t, 12.0).is_empty():
			k += 1
	for t in sn:
		if not _find(an, ["snare"], t, 12.0).is_empty():
			s += 1
	for t in ht:
		if not _find(an, ["hat"], t, 12.0).is_empty():
			h += 1
	print("  schlagzeug: kick %d/6, snare %d/6, hat %d/6, %s" % [k, s, h, _count(an)])
	_ok(k == 6, "schlagzeug: tiefer Schlag -> kick innerhalb 12 ms")
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


func _measure(maps_dir: String, count: int, own_dir: String, params: Dictionary, report: bool) -> void:
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
		var d0 := _nearest(rs.notes, ev_t, 0.0)
		print("%3d %s | %.0f s | %d Noten | %d Ereignisse | roh-Recall30 %.2f | %d ms" % [sets.size(), name.left(44),
				float(an.duration_ms) / 1000.0, rs.notes.size(), ev_t.size(), float(_within(d0, 30.0)) / rs.notes.size(), ms])
	var total_s := (Time.get_ticks_msec() - t_start) / 1000.0
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
	for arr: PackedInt32Array in [kind_hit, kind_chance, kind_ev, kind_on]:
		arr.resize(KINDS.size())
		arr.fill(0)
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
	var kiai_var := [[0.5, 0.15], [0.5, 0.25], [0.6, 0.15], [0.6, 0.2], [0.6, 0.3], [0.7, 0.15], [0.7, 0.25], [0.8, 0.1], [0.45, 0.35], [0.55, 0.4]]
	var kiai_var_sum := PackedFloat32Array()
	kiai_var_sum.resize(kiai_var.size())
	kiai_var_sum.fill(0.0)
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
		for t in notes:
			note_shift.append(t + lead)
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
			var intens: Array = []
			for sc in secs:
				intens.append(sc[2])
				if sc[3]:
					own_k.append([sc[0], sc[1]])
			kiai_iou_sum += _iou(own_k, kiai, s.dur)
			for vi in kiai_var.size():
				var fl := AmFeatures.kiai_flags(intens, kiai_var[vi][0], kiai_var[vi][1])
				var vk: Array = []
				for i in secs.size():
					if fl[i]:
						vk.append([secs[i][0], secs[i][1]])
				kiai_var_sum[vi] += _iou(vk, kiai, s.dur)
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
	var best_vi := 0
	for vi in kiai_var.size():
		if kiai_var_sum[vi] > kiai_var_sum[best_vi]:
			best_vi = vi
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
	L.append("Zufall = derselbe Wert mit um 137 ms verschobenen Noten. Treffer = Anteil der Ereignisse der Ebene auf einer Map-Note.")
	L.append("")
	L.append("| Ebene | Ereignisse/min | Recall allein | Zufall | Treffer |")
	L.append("|---|---|---|---|---|")
	for i in KINDS.size():
		L.append("| %s | %.1f | %.3f | %.3f | %.3f |" % [KINDS[i], kind_ev[i] / mins, float(kind_hit[i]) / n_notes,
				float(kind_chance[i]) / n_notes, float(kind_on[i]) / maxi(kind_ev[i], 1)])
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
	L.append("## Kiai-Schwellen (IoU-Mittel, aus denselben Abschnitten nachgerechnet)")
	L.append("")
	L.append("| kiai_abs | kiai_margin | IoU |")
	L.append("|---|---|---|")
	for vi in kiai_var.size():
		L.append("| %.2f | %.2f | %.3f%s |" % [kiai_var[vi][0], kiai_var[vi][1], kiai_var_sum[vi] / maxi(kiai_sets, 1), " (beste)" if vi == best_vi else ""])
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
