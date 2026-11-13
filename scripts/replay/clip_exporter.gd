class_name ClipExporter
extends Node

## Clips teilen: exportiert ein gespeichertes Replay als Video ueber Godots
## Movie-Maker-Modus. Dafuer startet der Exporter einen ZWEITEN Prozess des
## Spiels (--write-movie ... --clip <md5>); GameSession erkennt "--clip" beim
## Start, spielt das Replay automatisch ab und beendet sich nach den Results.
## Der Movie-Maker rendert mit fester FPS so schnell wie CPU/GPU koennen (kein
## Warten auf Echtzeit). Gemessen (docs/perf/clip_speed.md): die Zeit pro Frame
## geht in Readback + MJPEG-Kodierung, nicht ins Rendern -> Fenster = Viewport
## (1280x720; ein 1080p-Fenster kostete 2,7x mehr) und 30 FPS als Standard.
## Ist ffmpeg vorhanden, wird das AVI (MJPEG, ~100 MB/30 s) danach in ~2 s zu
## einem kleinen MP4 (H.264/AAC) umkodiert und das AVI geloescht.
##
## API fuer den Results-Button (Signal clip_pressed):
##   var exporter := ClipExporter.new()
##   add_child(exporter)                      # braucht den SceneTree zum Pollen
##   exporter.progress_info.connect(func(frac, eta, phase): ...)  # Restzeit
##   exporter.finished.connect(func(ok, path): ...)
##   clip_btn.pressed.connect(func():         # bzw. results.clip_pressed
##       exporter.export_clip(("%s|%s" % [osz_path.get_file(), version]).md5_text())
##   )
## Die md5 ist der Replay-Schluessel (= Dateiname in user://replays ohne .json).
## Orbit: export_clip(md5, out, "orbit") -> Kindprozess mit --clip <md5>
## --clip-mode orbit, Replay aus user://replays/orbit (ReplayStore).
## Trace: export_clip(md5, out, "trace") wie Orbit (--clip-mode trace). Zusaetzlich
## export_timelapse(md5, out, "trace"): 8-s-Zeitraffer 1080x1080 fuer Social (das
## ganze Replay wird gerendert, danach per ffmpeg auf 8 s gerafft, mittig
## quadratisch zugeschnitten; Ton = 8-s-Musikausschnitt mit Ein-/Ausblendung).
## Der Results-Knopf fragt ClipExporter.supports_mode(modus) ab.

## Elapsed Sekunden seit Start.
signal progress(elapsed_s: float)
## Anteil 0..1 und geschaetzte Restzeit in s (-1 = noch unbekannt). phase ist
## "render" oder "encode". Fuer die Fortschrittsanzeige mit Restzeit.
signal progress_info(fraction: float, eta_s: float, phase: String)
## ok = Datei existiert und ist nicht leer. out_path = fertige Datei (MP4 oder AVI).
signal finished(ok: bool, out_path: String)

## Qualitaetsstufen -> FPS. "fast" ist der Standard.
const PRESETS := {"fast": 30, "smooth": 60}
const RESOLUTION := "1280x720"
## Gemessene Frame-Groesse (MJPEG, 720p) fuer die Fortschrittsschaetzung.
const BYTES_PER_FRAME := 65000.0
## Erwartete Film-Laenge = letzter Tastendruck + Auslauf (Lead-In, Ende, Results).
const TAIL_S := 6.0

## Zeitraffer-Clip: Dauer, Kantenlaenge (quadratisch).
const TIMELAPSE_S := 8.0
const TIMELAPSE_SIZE := 1080
## Modi (ReplayStore-Basismodus), die sich als Clip exportieren lassen.
const CLIP_MODES := ["mania", "orbit", "trace"]
## Szene je Basismodus fuer den Clip-Kindprozess (GameSession._start_clip).
const CLIP_SCENES := {"mania": "res://scenes/mania_3d.tscn", "orbit": "res://scenes/orbit.tscn",
	"trace": "res://scenes/trace.tscn"}

## Fenster = Viewport-Groesse des Projekts (siehe Kopf).
var resolution: String = RESOLUTION
var fps: int = 30
## true = nach dem Rendern per ffmpeg zu MP4 umkodieren, falls ffmpeg da ist.
var convert_mp4: bool = true
## Letzter Fehlertext (leer = ok), fuer den Toast.
var last_error: String = ""
var pid: int = -1
var out_path: String = ""
## Fertige Datei (nach dem Umkodieren das MP4).
var final_path: String = ""
var _render_path: String = ""
var _encode_pid: int = -1
var _t0_ms: int = 0
var _expected_bytes: float = 0.0
var _enc_t0_ms: int = 0
var _enc_expected_s: float = 2.0
var _ffmpeg: String = ""
## "full" = ganzes Replay, "timelapse" = 8-s-Quadrat-Zeitraffer.
var style: String = "full"
var _len_s: float = 0.0


## Zielordner: Editor/Dev -> user://clips, Release -> Dokumente/OMEN Clips.
## Gibt es schon "TETHRA Clips" (Name bis v1.35.0), bleibt es bei dem Ordner:
## die Clips des Nutzers liegen dort.
static func clips_dir() -> String:
	var d: String
	if OS.has_feature("editor"):
		d = ProjectSettings.globalize_path("user://clips")
	else:
		d = clips_dir_in(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))
	DirAccess.make_dir_recursive_absolute(d)
	return d


## Clip-Ordner unter docs: der alte, falls vorhanden, sonst der neue.
static func clips_dir_in(docs: String) -> String:
	var old := docs.path_join("TETHRA Clips")
	if DirAccess.dir_exists_absolute(old):
		return old
	return docs.path_join("OMEN Clips")


## ffmpeg suchen: neben der Exe (mitgeliefert), sonst im PATH. "" = keins.
static func find_ffmpeg() -> String:
	var local := OS.get_executable_path().get_base_dir().path_join("ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg")
	if FileAccess.file_exists(local):
		return local
	var out := []
	if OS.execute("ffmpeg", ["-version"], out, true) == 0:
		return "ffmpeg"
	return ""


## Kann der Results-Knopf fuer diesen Modus (Spiel- oder Replay-Modus, z. B.
## "trace" / "trace_last") einen Clip exportieren?
static func supports_mode(mode: String) -> bool:
	return ReplayStore.base_mode(mode) in CLIP_MODES


## Szenenpfad fuer den Clip-Prozess eines Replay-Modus ("" = nicht unterstuetzt).
static func scene_for_mode(mode: String) -> String:
	return CLIP_SCENES.get(ReplayStore.base_mode(mode), "")


## Standard-Zielpfad: clip_<md5>.avi bzw. timelapse_<md5>.avi (Ergebnis .mp4).
static func default_out_path(md5: String, p_style: String = "full") -> String:
	var prefix := "timelapse_" if p_style == "timelapse" else "clip_"
	return clips_dir().path_join("%s%s.avi" % [prefix, md5])


## Start des Musikausschnitts im Film (s): ab ca. 35 % der Filmlaenge, so dass
## der Ausschnitt noch ganz hineinpasst.
static func timelapse_audio_start_s(movie_len_s: float, dur_s: float = TIMELAPSE_S) -> float:
	return clampf(movie_len_s * 0.35, 0.0, maxf(0.0, movie_len_s - dur_s))


## ffmpeg-Argumente fuer den Zeitraffer (rein, testbar): Film in dur_s raffen,
## mittig quadratisch schneiden, auf size x size skalieren, Musikausschnitt.
static func timelapse_args(src: String, dst: String, movie_len_s: float,
		dur_s: float = TIMELAPSE_S, size: int = TIMELAPSE_SIZE) -> PackedStringArray:
	var factor := dur_s / maxf(movie_len_s, 0.1)
	var a0 := timelapse_audio_start_s(movie_len_s, dur_s)
	var vf := "[0:v]setpts=%.6f*PTS,crop='min(iw,ih)':'min(iw,ih)',scale=%d:%d,fps=30[v]" % [factor, size, size]
	var af := "[0:a]atrim=start=%.3f:duration=%.3f,asetpts=PTS-STARTPTS,afade=t=in:d=0.4,afade=t=out:st=%.3f:d=0.8[a]" % [
		a0, dur_s, maxf(0.0, dur_s - 0.8)]
	return PackedStringArray(["-v", "error", "-y", "-i", src,
		"-filter_complex", vf + ";" + af, "-map", "[v]", "-map", "[a]", "-t", "%.3f" % dur_s,
		"-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p",
		"-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", dst])


## Filmdauer in s aus der ffmpeg-Ausgabe (ffprobe liegt nicht bei; 0 = unbekannt).
static func probe_duration_s(path: String, ffmpeg: String) -> float:
	var out := []
	OS.execute(ffmpeg if ffmpeg != "" else "ffmpeg", ["-hide_banner", "-i", path], out, true)
	return parse_duration_s(String(out[0]) if not out.is_empty() else "")


## "Duration: 00:01:34.42," aus ffmpeg-Text -> Sekunden (0 = nicht gefunden).
static func parse_duration_s(text: String) -> float:
	var i := text.find("Duration: ")
	if i < 0:
		return 0.0
	var parts := text.substr(i + 10, 11).split(":")
	if parts.size() < 3:
		return 0.0
	return parts[0].to_float() * 3600.0 + parts[1].to_float() * 60.0 + parts[2].to_float()


## Zeitraffer exportieren (Quadrat, 8 s). Braucht ffmpeg (sonst Fehler).
## Zielpfad leer = <clips_dir>/timelapse_<md5>.avi (Ergebnis .mp4).
func export_timelapse(md5: String, p_out_path: String = "", mode: String = "trace") -> bool:
	if find_ffmpeg() == "":
		last_error = "ffmpeg fehlt (Zeitraffer braucht es)"
		finished.emit(false, p_out_path)
		return false
	if is_running():
		return false
	style = "timelapse"
	convert_mp4 = true
	return _export(md5, p_out_path, mode)


## Letzter Tastendruck des Replays in s (0 = unbekannt).
## Mania-Events sind {t, ...}, Orbit-Events [t, code, ...].
static func replay_length_s(md5: String, mode: String = "mania") -> float:
	var f := FileAccess.open(ReplayStore.path_for_key(md5, mode), FileAccess.READ)
	if f == null:
		return 0.0
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return 0.0
	var last := 0.0
	for e in data.get("events", []):
		if e is Dictionary:
			last = maxf(last, float(e.get("t", 0.0)))
		elif e is Array and not e.is_empty():
			last = maxf(last, float(e[0]))
	return last / 1000.0


## Restzeit aus Anteil und Laufzeit (rein, testbar). -1 = zu frueh fuer eine Schaetzung.
static func eta_s(fraction: float, elapsed_s: float) -> float:
	if fraction < 0.05 or elapsed_s < 1.0:
		return -1.0
	return elapsed_s * (1.0 - fraction) / fraction


## Startet den Export. out_path leer = <clips_dir>/clip_<md5>.avi; bei MP4-
## Umkodierung heisst die Ergebnisdatei .mp4 (final_path).
## Gibt false zurueck, wenn der Prozess nicht startet oder schon einer laeuft.
## mode: "mania" (Standard), "orbit" oder "trace".
func export_clip(md5: String, p_out_path: String = "", mode: String = "mania") -> bool:
	if is_running():
		return false
	style = "full"
	return _export(md5, p_out_path, mode)


func _export(md5: String, p_out_path: String, mode: String) -> bool:
	if is_running():
		return false
	last_error = ""
	if not supports_mode(mode):
		last_error = "Modus ohne Clip-Export: " + mode
		finished.emit(false, p_out_path)
		return false
	out_path = p_out_path if p_out_path != "" else default_out_path(md5, style)
	out_path = ProjectSettings.globalize_path(out_path)
	final_path = out_path
	if not FileAccess.file_exists(ReplayStore.path_for_key(md5, mode)):
		last_error = "Kein gespeichertes Replay"
		finished.emit(false, out_path)
		return false
	_ffmpeg = find_ffmpeg() if convert_mp4 else ""
	_render_path = out_path
	if _ffmpeg != "":
		final_path = out_path.get_basename() + ".mp4"
		_render_path = out_path.get_basename() + ".part.avi"
	for p in [out_path, final_path, _render_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var args := PackedStringArray()
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	else:
		# Paket der laufenden Exe (OMEN.exe -> OMEN.pck, alte Installation TETHRA.exe -> TETHRA.pck).
		var pck := OS.get_executable_path().get_basename() + ".pck"
		if FileAccess.file_exists(pck):
			args.append_array(["--main-pack", pck])
	# Fensterposition: wie der Elternprozess, falls der eine bekam (Testlaeufe auf
	# Monitor 2), sonst weit ausserhalb des Bildes.
	var pos := "-10000,-10000"
	var pa := OS.get_cmdline_args()
	var pi := pa.find("--position")
	if pi >= 0 and pi + 1 < pa.size():
		pos = pa[pi + 1]
	var res := resolution
	if style == "timelapse":
		res = "%dx%d" % [TIMELAPSE_SIZE, TIMELAPSE_SIZE]
	args.append_array(["--write-movie", _render_path, "--fixed-fps", str(fps),
		"--resolution", res, "--position", pos, "--clip", md5])
	if mode != "mania":
		args.append_array(["--clip-mode", mode])
	pid = OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		pid = -1
		last_error = "Prozess konnte nicht gestartet werden"
		finished.emit(false, out_path)
		return false
	_t0_ms = Time.get_ticks_msec()
	var len_s := replay_length_s(md5, mode)
	_len_s = len_s
	_expected_bytes = (len_s + TAIL_S) * fps * BYTES_PER_FRAME if len_s > 0.0 else 0.0
	_enc_expected_s = maxf(1.0, (len_s + TAIL_S) / 20.0)
	set_process(true)
	return true


func is_running() -> bool:
	return (pid > 0 and OS.is_process_running(pid)) or (_encode_pid > 0 and OS.is_process_running(_encode_pid))


func _ready() -> void:
	set_process(pid > 0)


func _process(_dt: float) -> void:
	if pid > 0:
		_poll_render()
	elif _encode_pid > 0:
		_poll_encode()
	else:
		set_process(false)


func _poll_render() -> void:
	var elapsed := (Time.get_ticks_msec() - _t0_ms) / 1000.0
	if OS.is_process_running(pid):
		progress.emit(elapsed)
		var frac := -1.0
		if _expected_bytes > 0.0 and FileAccess.file_exists(_render_path):
			var f := FileAccess.open(_render_path, FileAccess.READ)
			if f != null:
				frac = clampf(float(f.get_length()) / _expected_bytes, 0.0, 0.98)
		if frac >= 0.0:
			var eta := eta_s(frac, elapsed)
			if eta >= 0.0 and _ffmpeg != "":
				eta += _enc_expected_s
			progress_info.emit(frac, eta, "render")
		return
	pid = -1
	if not _file_ok(_render_path):
		last_error = "Prozess abgebrochen, kein Video erzeugt"
		finished.emit(false, out_path)
		set_process(false)
		return
	if _ffmpeg == "":
		finished.emit(true, final_path)
		set_process(false)
		return
	# AVI -> MP4: H.264 ultrafast (~20x Echtzeit), Audio AAC, yuv420p fuer alle Player.
	var enc_args := PackedStringArray(["-v", "error", "-y", "-i", _render_path,
		"-c:v", "libx264", "-preset", "ultrafast", "-crf", "26", "-pix_fmt", "yuv420p",
		"-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", final_path])
	if style == "timelapse":
		var movie_s := probe_duration_s(_render_path, _ffmpeg)
		if movie_s <= 0.0:
			movie_s = _len_s + TAIL_S
		enc_args = timelapse_args(_render_path, final_path, movie_s)
	_encode_pid = OS.create_process(_ffmpeg, enc_args)
	if _encode_pid <= 0:
		# Kein Umkodieren moeglich: AVI bleibt das Ergebnis.
		_encode_pid = -1
		_keep_avi()
		return
	_enc_t0_ms = Time.get_ticks_msec()


func _poll_encode() -> void:
	var elapsed := (Time.get_ticks_msec() - _enc_t0_ms) / 1000.0
	if OS.is_process_running(_encode_pid):
		progress.emit((Time.get_ticks_msec() - _t0_ms) / 1000.0)
		var frac := clampf(elapsed / _enc_expected_s, 0.0, 0.98)
		progress_info.emit(frac, maxf(0.0, _enc_expected_s - elapsed), "encode")
		return
	_encode_pid = -1
	if _file_ok(final_path):
		DirAccess.remove_absolute(_render_path)
		finished.emit(true, final_path)
		set_process(false)
	else:
		_keep_avi()


## ffmpeg fehlgeschlagen: das AVI ist das Ergebnis.
func _keep_avi() -> void:
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	final_path = out_path
	DirAccess.rename_absolute(_render_path, out_path)
	finished.emit(_file_ok(out_path), out_path)
	set_process(false)


static func _file_ok(p: String) -> bool:
	if not FileAccess.file_exists(p):
		return false
	var f := FileAccess.open(p, FileAccess.READ)
	return f != null and f.get_length() > 0
