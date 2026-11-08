extends SceneTree

## Headless-Tests fuer AudioMapper (Task audio-map). Synthetischer Klick-Track mit
## bekannter BPM -> BPM/Offset, lesbare Map, Orbit-Ziele. Braucht ffmpeg (sonst SKIP).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_audio_map_tests.gd
## Messung gegen echte Maps (Bericht docs/modes/audio_map.md):
##   ... --script res://tests/run_audio_map_tests.gd -- --measure <maps-ordner> [anzahl]

var _passed := 0
var _failed := 0
var _done := false


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
	print("=== TETHRA Audio-Map-Tests ===")
	var args := OS.get_cmdline_user_args()
	var mi := args.find("--measure")
	if mi >= 0 and mi + 1 < args.size():
		_measure(args[mi + 1], int(args[mi + 2]) if mi + 2 < args.size() else 8)
		quit(0)
		return
	_test_pure()
	if ClipExporter.find_ffmpeg() == "":
		print("  SKIP: kein ffmpeg, Dateitests uebersprungen")
	else:
		_test_click_track()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Klick-Samples (22050 Hz) mit Beats auf offset + k * 60000/bpm, Takt-Akzent alle 4.
func _click_samples(bpm: float, offset_ms: float, secs: float) -> PackedFloat32Array:
	var n := int(secs * AudioMapper.RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var T := 60000.0 / bpm
	var k := 0
	while true:
		var t := offset_ms + k * T
		var i0 := int(t * AudioMapper.RATE / 1000.0)
		if i0 >= n - 300:
			break
		var amp := 0.9 if k % 4 == 0 else 0.6
		for j in 220:
			s[i0 + j] = amp * sin(TAU * 1800.0 * j / AudioMapper.RATE) * exp(-j / 40.0)
		k += 1
	return s


func _circ_err(a: float, b: float, T: float) -> float:
	var d := fposmod(a - b + T * 0.5, T) - T * 0.5
	return absf(d)


func _test_pure() -> void:
	for cfg in [[128.0, 350.0], [100.0, 120.0], [150.0, 40.0]]:
		var s := _click_samples(cfg[0], cfg[1], 40.0)
		var an := AudioMapper.analyze_samples(s)
		_ok(an.ok, "analyze ok %s" % str(cfg))
		if not an.ok:
			continue
		var T: float = 60000.0 / cfg[0]
		_ok(absf(an.bpm - cfg[0]) < 0.05, "BPM %s -> %s" % [cfg[0], an.bpm])
		var oe := _circ_err(an.offset_ms, cfg[1], T)
		_ok(oe < 6.0, "Offset %s -> %s (Fehler %.2f ms)" % [cfg[1], an.offset_ms, oe])
	# Dichte: jede Schwierigkeit haelt ihren Mindestabstand, Leicht <= Normal <= Schwer.
	var an2 := AudioMapper.analyze_samples(_click_samples(128.0, 350.0, 40.0))
	var counts := {}
	for d in ["Leicht", "Normal", "Schwer"]:
		var notes := AudioMapper.pick_notes(an2, d)
		counts[d] = notes.size()
		var min_gap := INF
		for i in range(1, notes.size()):
			min_gap = minf(min_gap, notes[i][0] - notes[i - 1][0])
		_ok(notes.size() >= 8, "%s: Noten vorhanden (%d)" % [d, notes.size()])
		_ok(min_gap >= AudioMapper.DIFFS[d].gap - 1.0, "%s: Mindestabstand %.0f" % [d, min_gap])
	_ok(counts["Leicht"] <= counts["Normal"] and counts["Normal"] <= counts["Schwer"], "Dichte steigt mit Schwierigkeit")


func _test_click_track() -> void:
	var dir := ProjectSettings.globalize_path("user://audio_map_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var wav := dir.path_join("Testband - Klickspur.wav")
	_write_wav(wav, _click_samples(128.0, 350.0, 40.0))
	var res := AudioMapper.generate(wav, dir, "Normal")
	_ok(res.ok, "generate ok: " + str(res.error))
	if not res.ok:
		return
	_ok(res.osz_path.get_file() == "Testband - Klickspur (TETHRA Auto).osz", "osz-Name: " + res.osz_path.get_file())
	_ok(absf(res.bpm - 128.0) < 0.05, "generate BPM %s" % res.bpm)
	var imp := OszImporter.import(res.osz_path)
	_ok(imp.ok, "OszImporter liest die Map")
	if not imp.ok:
		return
	var bm: Beatmap = imp.difficulties[0].beatmap
	_ok(bm.mode() == 0, "Mode 0")
	_ok(bm.artist() == "Testband" and bm.title() == "Klickspur", "Metadaten aus Dateiname: %s / %s" % [bm.artist(), bm.title()])
	_ok(bm.audio_filename() == "audio.wav", "Audio-Name")
	_ok(OszImporter.read_file_bytes(res.osz_path, "audio.wav").size() == FileAccess.get_file_as_bytes(wav).size(), "Audio unveraendert im osz")
	_ok(bm.hit_objects.size() == res.note_count, "Notenzahl %d" % bm.hit_objects.size())
	var targets := OrbitConverter.convert_std(bm)
	_ok(targets.size() >= bm.hit_objects.size() * 9 / 10, "Orbit-Ziele %d von %d" % [targets.size(), bm.hit_objects.size()])
	# Fluessige Winkel: Winkelgeschwindigkeit zwischen Zielen begrenzt.
	var worst := 0.0
	for i in range(1, targets.size()):
		var gap := targets[i].time_ms - targets[i - 1].time_ms
		var d := absf(OrbitNote.delta_deg(targets[i - 1].angle_deg, targets[i].angle_deg))
		worst = maxf(worst, d / maxf(gap, 1.0))
	_ok(worst <= 0.3, "Winkelgeschwindigkeit max %.3f Grad/ms" % worst)
	DirAccess.remove_absolute(res.osz_path)
	DirAccess.remove_absolute(wav)


func _write_wav(path: String, s: PackedFloat32Array) -> void:
	var pcm := PackedByteArray()
	pcm.resize(s.size() * 2)
	for i in s.size():
		pcm.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + pcm.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(AudioMapper.RATE)
	f.store_32(AudioMapper.RATE * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(pcm.size())
	f.store_buffer(pcm)
	f.close()


# ---------------------------------------------------------------------------
# Messung gegen echte Maps
# ---------------------------------------------------------------------------

func _measure(maps_dir: String, count: int) -> void:
	var files: Array[String] = []
	for f in DirAccess.get_files_at(maps_dir):
		if f.to_lower().ends_with(".osz"):
			files.append(f)
	files.sort()
	var step := maxi(1, files.size() / maxi(count, 1))
	var tmp := ProjectSettings.globalize_path("user://audio_map_measure")
	DirAccess.make_dir_recursive_absolute(tmp)
	print("map | bpm_map bpm_det | off_err_ms | onset_recall30 | onset_prec30 | normal_prec30 | grid20 | grid_bias_ms | zeit")
	var n := 0
	var i := 0
	while i < files.size() and n < count:
		var name := files[i]
		var osz := maps_dir.path_join(name)
		i += step
		var imp := OszImporter.import(osz)
		if not imp.ok:
			continue
		var bm: Beatmap = null
		for d in imp.difficulties:
			if bm == null or d.beatmap.hit_objects.size() > bm.hit_objects.size():
				bm = d.beatmap
		var tp: TimingPoint = null
		for t in bm.timing_points:
			if t.uninherited:
				tp = t
				break
		if tp == null or bm.audio_filename() == "":
			continue
		var apath := tmp.path_join("m_" + bm.audio_filename().get_file())
		var bytes := OszImporter.read_file_bytes(osz, bm.audio_filename())
		if bytes.is_empty():
			continue
		var fh := FileAccess.open(apath, FileAccess.WRITE)
		fh.store_buffer(bytes)
		fh.close()
		var t0 := Time.get_ticks_msec()
		var an := AudioMapper.analyze(apath)
		var ms := Time.get_ticks_msec() - t0
		DirAccess.remove_absolute(apath)
		if not an.ok:
			print(name.left(40), " | analyse fehlgeschlagen")
			continue
		var real: Array[float] = []
		for o in bm.hit_objects:
			real.append(o.time)
		real.sort()
		var bpm_map := 60000.0 / tp.beat_length
		var oe := _circ_err(an.offset_ms, fposmod(tp.time, tp.beat_length), tp.beat_length)
		var ons: Array[float] = []
		for p in an.onsets:
			ons.append(p[0])
		var rec := _hit_frac(real, ons, 30.0)
		var prec := _hit_frac(ons, real, 30.0)
		var nn: Array[float] = []
		for nt in AudioMapper.pick_notes(an, "Normal"):
			nn.append(nt[0])
		var nprec := _hit_frac(nn, real, 30.0)
		# Passt das 1/4-Raster zu den echten Noten? Anteil innerhalb 20 ms + mittlerer Versatz.
		var q: float = 60000.0 / an.bpm / 4.0
		var near := 0
		var bias := 0.0
		for rt in real:
			var d := fposmod(rt - (an.offset_ms - AudioMapper.OSU_LEAD_MS) + q * 0.5, q) - q * 0.5
			bias += d
			if absf(d) <= 20.0:
				near += 1
		print("%s | %.2f %.2f | %.1f | %.2f | %.2f | %.2f | %.2f | %.1f | %d ms" % [name.left(40), bpm_map, an.bpm, oe, rec, prec, nprec, float(near) / real.size(), bias / real.size(), ms])
		n += 1


## Anteil der Zeiten in a mit einem Nachbarn in b innerhalb tol ms.
func _hit_frac(a: Array[float], b: Array[float], tol: float) -> float:
	if a.is_empty() or b.is_empty():
		return 0.0
	var hit := 0
	var j := 0
	for t in a:
		while j < b.size() - 1 and b[j + 1] < t:
			j += 1
		var d := absf(b[j] - t)
		if j + 1 < b.size():
			d = minf(d, absf(b[j + 1] - t))
		if d <= tol:
			hit += 1
	return float(hit) / a.size()
