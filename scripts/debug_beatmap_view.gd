extends Node2D

## M1-Debug-Ansicht (Abschnitt 10, M1): Anker erscheinen zur richtigen Zeit an
## der richtigen Position. Approach-Ring schrumpft ueber die preempt-Zeit,
## Fade-In in den ersten ~2/3. Slider/Spinner werden schematisch dargestellt
## (volles Pfad-Rendering ist M3).
##
## Zwei Zeitquellen:
##  - Mit echtem Audio (osz_path gesetzt + Audio ladbar): SyncClock (Abschnitt 5).
##  - Ohne Audio (nur .osu-Fixture): eine als DEBUG markierte Tick-Uhr, damit die
##    Ansicht auch ohne Audiodatei laeuft. Im echten Spiel gilt ausschliesslich
##    die Audio-Clock.

## Optionaler Pfad zu einer .osz (echtes Audio + Sync). Leer -> Fixture ohne Audio.
@export_file("*.osz") var osz_path: String = ""
## Fallback-Fixture, wenn keine .osz gesetzt ist.
@export_file("*.osu") var osu_fixture: String = "res://tests/fixtures/greenlines_kiai.osu"
## Anteil der Bildschirmhoehe, den das Playfield einnimmt.
@export_range(0.3, 1.0, 0.05) var playfield_fraction: float = 0.85

var _beatmap: Beatmap
var _playfield := Playfield.new()
var _use_audio := false

# --- DEBUG-Tick-Uhr (nur ohne Audio; NIE fuer echtes Gameplay-Timing) ---
var _debug_running := false
var _debug_start_usec := 0
var _debug_lead_in_ms := 0.0

var _font: Font
var _font_size := 16

# Headless-Frame-Budget, um den _draw-Pfad unter dem Dummy-Renderer zu testen.
var _headless_frames_left := 0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_playfield.configure(_screen_size(), playfield_fraction)

	if not _load_beatmap():
		return

	var headless := DisplayServer.get_name() == "headless"
	if headless:
		_run_smoke_test()
		# _draw unter dem Dummy-Renderer testen: einige Frames rendern lassen.
		_headless_frames_left = 5
		_start_clock()
		# Uhr auf einen Zeitpunkt vorspulen, an dem Anker aktiv sind, damit der
		# Draw-Test die Anker-/Slider-/HUD-Pfade wirklich durchlaeuft.
		if _beatmap.hit_objects.size() > 0:
			_debug_lead_in_ms = -(_beatmap.hit_objects[0].time)
		set_process(true)
		return

	_start_clock()
	set_process(true)

	if OS.get_cmdline_args().has("--shot"):
		_capture_after_delay()


func _capture_after_delay() -> void:
	# Warten, bis die erste Note aktiv ist (Songzeit >= erste Hit-Time + Puffer),
	# damit Anker garantiert sichtbar sind — unabhaengig von der Intro-Laenge.
	var target := 2000.0
	if _beatmap != null and _beatmap.hit_objects.size() > 0:
		target = _beatmap.hit_objects[0].time + 400.0
	var guard := 0
	while _current_time_ms() < target and guard < 3000:
		guard += 1
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/gameplay_debug.png"
	img.save_png(path)
	print("SHOT gespeichert: " + path)
	get_tree().quit(0)


## Sinnvolle Bildschirmgroesse: Live-Viewport, aber Fallback auf die im Projekt
## konfigurierte Design-Groesse, falls das Viewport degeneriert ist (z.B.
## headless liefert eine winzige Groesse).
func _screen_size() -> Vector2:
	var s := get_viewport().get_visible_rect().size
	if s.x < 200.0 or s.y < 200.0:
		var w := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280))
		var h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
		return Vector2(w, h)
	return s


func _load_beatmap() -> bool:
	# Auswahl aus dem Song-Browser hat Vorrang.
	if GameSession.has_selection():
		return _load_from_session()
	if osz_path != "" and FileAccess.file_exists(osz_path):
		var imp := OszImporter.import(osz_path)
		if not imp.ok:
			push_error("OSZ-Import fehlgeschlagen: " + imp.error)
			return false
		_beatmap = imp.difficulties[0].beatmap
		var stream := OszImporter.load_audio_stream(osz_path, _beatmap)
		if stream != null:
			SyncClock.play(stream, _beatmap.audio_lead_in())
			_use_audio = true
			return true
		# Kein ladbares Audio -> Debug-Uhr.
	# Fixture laden.
	var f := FileAccess.open(osu_fixture, FileAccess.READ)
	if f == null:
		push_error("Fixture nicht ladbar: " + osu_fixture)
		return false
	var res := OsuParser.parse(f.get_as_text())
	if not res.ok:
		push_error("Parse-Fehler: " + res.error)
		return false
	_beatmap = res.beatmap
	return true


func _load_from_session() -> bool:
	var imp := OszImporter.import(GameSession.osz_path)
	if not imp.ok:
		push_error("OSZ-Import fehlgeschlagen: " + imp.error)
		return false
	# Difficulty stabil ueber den Version-Namen abbilden (Sortierung von
	# MapSet und Importer unterscheidet sich), sonst Index als Fallback.
	_beatmap = null
	if GameSession.difficulty_version != "":
		for d in imp.difficulties:
			if d.beatmap.version_name() == GameSession.difficulty_version:
				_beatmap = d.beatmap
				break
	if _beatmap == null:
		var idx := clampi(GameSession.difficulty_index, 0, imp.difficulties.size() - 1)
		_beatmap = imp.difficulties[idx].beatmap
	var stream := OszImporter.load_audio_stream(GameSession.osz_path, _beatmap)
	if stream != null:
		SyncClock.play(stream, _beatmap.audio_lead_in())
		_use_audio = true
	return true


func _start_clock() -> void:
	if _use_audio:
		return
	# DEBUG-Uhr starten (siehe Kopf-Kommentar).
	_debug_lead_in_ms = _beatmap.audio_lead_in()
	_debug_start_usec = Time.get_ticks_usec()
	_debug_running = true


## Aktuelle Song-Zeit in ms. Audio-Clock im Echtbetrieb, sonst DEBUG-Tick-Uhr.
func _current_time_ms() -> float:
	if _use_audio:
		return SyncClock.song_time_ms()
	if not _debug_running:
		return 0.0
	var elapsed := float(Time.get_ticks_usec() - _debug_start_usec) / 1000.0
	return elapsed - _debug_lead_in_ms


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SyncClock.stop()
		get_tree().change_scene_to_file("res://scenes/song_select.tscn")


func _process(_delta: float) -> void:
	queue_redraw()
	if _headless_frames_left > 0:
		_headless_frames_left -= 1
		if _headless_frames_left == 0:
			print("=== _draw-Pfad ueberstanden (Dummy-Renderer) ===")
			get_tree().quit(0)


func _draw() -> void:
	if _beatmap == null:
		return
	var t := _current_time_ms()
	_draw_playfield_frame()
	_draw_hud(t)

	var preempt := _beatmap.preempt_ms()
	var fade := DifficultyCalc.fade_in(_beatmap.ar())
	var radius_osu := _beatmap.anchor_radius_osu()
	var radius_px := _playfield.radius_to_screen(radius_osu)

	# In umgekehrter Zeitreihenfolge zeichnen, damit fruehere Anker oben liegen.
	for i in range(_beatmap.hit_objects.size() - 1, -1, -1):
		var obj := _beatmap.hit_objects[i]
		var appear := obj.time - preempt
		var disappear := obj.end_time() + _beatmap.window_meh()
		if t < appear or t > disappear:
			continue
		_draw_object(obj, t, preempt, fade, radius_px)


func _draw_object(obj: HitObject, t: float, preempt: float, fade: float, radius_px: float) -> void:
	var time_until := obj.time - t  # >0 vor Hit, <0 danach
	# Fade-In: 0 -> 1 ueber die ersten (preempt - fade) ... eigentlich erste ~2/3.
	var since_appear := t - (obj.time - preempt)
	var alpha := clampf(since_appear / maxf(fade, 1.0), 0.0, 1.0)
	var kiai := _beatmap.is_kiai(obj.time)
	var base_col := Color(0.2, 0.9, 1.0) if not kiai else Color(1.0, 0.5, 0.15)
	base_col.a = alpha

	match obj.kind:
		HitObject.Kind.CIRCLE:
			_draw_anchor(obj.position(), radius_px, base_col, time_until, preempt, alpha)
		HitObject.Kind.SLIDER:
			_draw_slider(obj, radius_px, base_col, time_until, preempt, alpha)
		HitObject.Kind.SPINNER:
			_draw_spinner(obj, base_col, alpha)


func _draw_anchor(osu_pos: Vector2, radius_px: float, col: Color, time_until: float, preempt: float, alpha: float) -> void:
	var center := _playfield.to_screen(osu_pos)
	# Gefuellter Anker.
	draw_circle(center, radius_px, Color(col.r, col.g, col.b, alpha * 0.35))
	draw_arc(center, radius_px, 0.0, TAU, 48, col, 2.0, true)
	# Approach-Ring: schrumpft von ~3x auf 1x waehrend der preempt-Zeit.
	if time_until > 0.0:
		var k := clampf(time_until / preempt, 0.0, 1.0)
		var ring_r := radius_px * (1.0 + 2.0 * k)
		draw_arc(center, ring_r, 0.0, TAU, 48, Color(col.r, col.g, col.b, alpha), 2.0, true)


func _draw_slider(obj: HitObject, radius_px: float, col: Color, time_until: float, preempt: float, alpha: float) -> void:
	var s := obj  # HitSlider (Duck-Typing)
	# Schematischer Pfad: Polylinie durch die Kontrollpunkte (volles Kurven-
	# Rendering ist M3). Zeigt Startposition + Richtung.
	if s.curve_points.size() >= 2:
		var pts := PackedVector2Array()
		for p in s.curve_points:
			pts.append(_playfield.to_screen(p))
		draw_polyline(pts, Color(col.r, col.g, col.b, alpha * 0.5), 3.0, true)
	# Startanker wie ein Circle.
	_draw_anchor(obj.position(), radius_px, col, time_until, preempt, alpha)


func _draw_spinner(obj: HitObject, col: Color, alpha: float) -> void:
	var center := _playfield.to_screen(Vector2(256, 192))
	var r := _playfield.radius_to_screen(120.0)
	draw_arc(center, r, 0.0, TAU, 64, Color(col.r, col.g, col.b, alpha), 3.0, true)
	draw_arc(center, r * 0.15, 0.0, TAU, 24, col, 2.0, true)


func _draw_playfield_frame() -> void:
	var r := _playfield.rect()
	draw_rect(r, Color(0.15, 0.15, 0.2, 1.0), false, 1.0)


func _draw_hud(t: float) -> void:
	if _font == null:
		return
	var kiai_txt := "  [KIAI]" if _beatmap.is_kiai(t) else ""
	var lines := [
		"%s — %s [%s]" % [_beatmap.artist(), _beatmap.title(), _beatmap.version_name()],
		"Zeit: %8.1f ms%s" % [t, kiai_txt],
		"CS %.1f  AR %.1f  OD %.1f  | preempt %.0f ms  Radius %.1f osu" % [
			_beatmap.cs(), _beatmap.ar(), _beatmap.od(), _beatmap.preempt_ms(), _beatmap.anchor_radius_osu()],
		"HitObjects: %d   Quelle: %s" % [_beatmap.hit_objects.size(), "Audio" if _use_audio else "DEBUG-Uhr"],
	]
	var y := 24.0
	for line in lines:
		draw_string(_font, Vector2(16, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Color.WHITE)
		y += 22.0


# ---------------------------------------------------------------------------
# Headless-Smoke-Test: bestaetigt Spawn-Zeiten und Bildschirmpositionen.
# ---------------------------------------------------------------------------

func _run_smoke_test() -> void:
	print("=== Debug-View Smoke-Test ===")
	print("Map: %s - %s [%s]" % [_beatmap.artist(), _beatmap.title(), _beatmap.version_name()])
	print("HitObjects: %d, preempt %.0f ms, Radius %.1f osu (%.1f px)" % [
		_beatmap.hit_objects.size(), _beatmap.preempt_ms(),
		_beatmap.anchor_radius_osu(), _playfield.radius_to_screen(_beatmap.anchor_radius_osu())])
	var preempt := _beatmap.preempt_ms()
	var kinds := ["CIRCLE", "SLIDER", "SPINNER"]
	var count := mini(_beatmap.hit_objects.size(), 8)
	for i in range(count):
		var obj := _beatmap.hit_objects[i]
		var screen_pos := _playfield.to_screen(obj.position())
		print("  #%d %-7s hit=%6.0fms spawn=%6.0fms osu=(%.0f,%.0f) screen=(%.0f,%.0f) kiai=%s" % [
			i, kinds[obj.kind], obj.time, obj.time - preempt,
			obj.x, obj.y, screen_pos.x, screen_pos.y, str(_beatmap.is_kiai(obj.time))])
	print("=== Smoke-Test OK ===")
