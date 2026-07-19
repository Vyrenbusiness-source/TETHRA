extends Control

## TETHRA Main-Menue: animierter Neon-Hintergrund, grosses Logo, PLAY /
## EINSTELLUNGEN / BEENDEN, Profilkarte (Name editierbar, Gesamt-pp, Plays)
## und die letzten Scores.

const COL_ACCENT := Color(0.20, 0.85, 1.0)
const COL_DIM := Color(0.6, 0.63, 0.72)
const GRADE_COLOR := {
	"S": Color(1.0, 0.85, 0.25), "A": Color(0.4, 1.0, 0.5),
	"B": Color(0.35, 0.75, 1.0), "C": Color(0.9, 0.6, 1.0),
	"D": Color(1.0, 0.4, 0.4),
}

var _pp_label: Label
var _plays_label: Label
var _name_label: Label
var _card_avatar: Control
# Interaktive Tutorial-Tour: Pfeil zeigt auf ECHTE Menue-Elemente.
var _profile_card: PanelContainer
var _btn_play: Button
var _btn_mp: Button
var _btn_settings: Button
var _tour_step := -1
var _tour_steps: Array = []
var _tour_overlay: Control
# Leise Menue-Musik: der zuletzt gespielte Song ab seiner Preview-Stelle.
var _music: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Hintergrund: geblurrtes Cover der zuletzt gespielten Map — clean.
	# Fallback (noch nie gespielt): animierter Neon-Hintergrund.
	if not _build_blur_bg():
		var bg := ColorRect.new()
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/menu_bg.gdshader")
		bg.material = mat
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	_build_logo()
	_build_buttons()
	_build_profile_card()
	if DisplayServer.get_name() != "headless":
		_start_menu_music()

	# Update-Banner unten links: zeigt Fortschritt des Auto-Updaters.
	var upd := Label.new()
	upd.anchor_top = 1.0
	upd.anchor_bottom = 1.0
	upd.offset_left = 20
	upd.offset_right = 620
	upd.offset_top = -34
	upd.add_theme_font_size_override("font_size", 13)
	upd.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	upd.text = ""
	add_child(upd)
	Updater.state_changed.connect(func(text, _ratio): upd.text = text)

	# Dezentes Versions-Tag unten rechts.
	var ver := Label.new()
	ver.text = "TETHRA  ·  v" + Updater.CURRENT_VERSION
	ver.anchor_left = 1.0
	ver.anchor_right = 1.0
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = -220
	ver.offset_right = -20
	ver.offset_top = -34
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", Color(0.5, 0.53, 0.62, 0.7))
	add_child(ver)

	if DisplayServer.get_name() == "headless":
		print("=== MainMenu Headless OK (pp=%.1f, plays=%d) ===" % [
			ScoreStore.profile_pp(), ScoreStore.total_plays()])
		get_tree().quit(0)
	elif OS.get_cmdline_args().has("--shot-menu"):
		_capture()
	elif OS.get_cmdline_args().has("--shot-profile"):
		# Harness: Profil-Ansicht oeffnen und abfotografieren.
		add_child(ProfilePanel.new())
		_capture()
	elif OS.get_cmdline_args().has("--shot-settings"):
		add_child(SettingsPanel.new())
		_capture()
	elif OS.get_cmdline_args().has("--autoplay"):
		# Test-Durchreiche in den Song-Browser.
		_play.call_deferred()


## Leise Hintergrundmusik: zuletzt gespielter Song ab der Preview-Stelle,
## mit sanftem Fade-in, endlos geloopt. Kein letzter Song -> Stille.
func _start_menu_music() -> void:
	var last := GameSession.load_last_played()
	if last.is_empty():
		return
	var imp := OszImporter.import(str(last.osz_path))
	if not imp.ok or imp.difficulties.is_empty():
		return
	var idx := clampi(int(last.difficulty_index), 0, imp.difficulties.size() - 1)
	var bm: Beatmap = imp.difficulties[idx].beatmap
	var stream := OszImporter.load_audio_stream(str(last.osz_path), bm)
	if stream == null:
		return
	var from_sec := maxf(float(bm.general.get("PreviewTime", -1.0)), 0.0) / 1000.0
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.bus = "Master"
	_music.volume_db = -40.0
	add_child(_music)
	_music.finished.connect(func():
		if is_instance_valid(_music):
			_music.play(from_sec))
	_music.play(from_sec)
	# Sanft auf "leise" hochfahren statt hart einzusetzen.
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -14.0, 1.6)


## Geblurrtes Hintergrundbild der zuletzt gespielten Map. false wenn keins da.
func _build_blur_bg() -> bool:
	var last := GameSession.load_last_played()
	if last.is_empty():
		return false
	# Schnellpfad: Hintergrund-Dateiname liegt im last_played-Cache — kein Parse.
	var bg_file := str(last.get("bg_file", ""))
	if bg_file != "":
		var fast_tex := OszImporter.load_image_texture(str(last.osz_path), bg_file)
		if fast_tex != null:
			_add_blur_layers(fast_tex)
			return true
	var imp := OszImporter.import(last.osz_path)
	if not imp.ok or imp.difficulties.is_empty():
		return false
	var idx := clampi(int(last.difficulty_index), 0, imp.difficulties.size() - 1)
	var tex := OszImporter.load_background_texture(str(last.osz_path), imp.difficulties[idx].beatmap)
	if tex == null:
		return false
	_add_blur_layers(tex)
	return true


func _add_blur_layers(tex: Texture2D) -> void:
	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.texture = UiTheme.blurred_texture(tex)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.30)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)


func _build_logo() -> void:
	var logo := Label.new()
	logo.text = "TETHRA"
	# Markanter Logo-Font (DIN-artig, gesperrt) statt Standard-Schrift.
	var logo_font := SystemFont.new()
	logo_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI Black", "Impact"])
	logo_font.font_weight = 700
	var logo_fv := FontVariation.new()
	logo_fv.base_font = logo_font
	logo_fv.spacing_glyph = 10
	logo.add_theme_font_override("font", logo_fv)
	logo.anchor_left = 0.5
	logo.anchor_right = 0.5
	logo.anchor_top = 0.16
	logo.anchor_bottom = 0.16
	logo.offset_left = -400
	logo.offset_right = 400
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_font_size_override("font_size", 110)
	logo.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	logo.add_theme_color_override("font_shadow_color", Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.6))
	logo.add_theme_constant_override("shadow_offset_x", 0)
	logo.add_theme_constant_override("shadow_offset_y", 0)
	logo.add_theme_constant_override("shadow_outline_size", 24)
	add_child(logo)

	# Leichter Logo-Effekt: sanftes Atmen (Scale) + pulsierender Glow.
	logo.pivot_offset = Vector2(400, 70)
	var pulse := create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(logo, "scale", Vector2.ONE * 1.018, 2.2)
	pulse.parallel().tween_method(
		func(v): logo.add_theme_constant_override("shadow_outline_size", int(v)), 24.0, 38.0, 2.2)
	pulse.tween_property(logo, "scale", Vector2.ONE, 2.2)
	pulse.parallel().tween_method(
		func(v): logo.add_theme_constant_override("shadow_outline_size", int(v)), 38.0, 24.0, 2.2)

	# Untertitel auf Japanisch (Katakana) — Systemfont, da der Godot-Default
	# keine CJK-Glyphen mitbringt.
	var sub := Label.new()
	sub.text = "テトラ ・ リズムの彼方へ"
	sub.anchor_left = 0.5
	sub.anchor_right = 0.5
	sub.anchor_top = 0.16
	sub.anchor_bottom = 0.16
	sub.offset_left = -300
	sub.offset_right = 300
	sub.offset_top = 138
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var jp_font := SystemFont.new()
	jp_font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "MS Gothic", "Noto Sans CJK JP"])
	sub.add_theme_font_override("font", jp_font)
	sub.add_theme_font_size_override("font_size", 19)
	sub.add_theme_color_override("font_color", COL_DIM)
	add_child(sub)


func _build_buttons() -> void:
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.44
	vb.anchor_bottom = 0.44
	vb.offset_left = -170
	vb.offset_right = 170
	vb.add_theme_constant_override("separation", 14)
	add_child(vb)

	_btn_play = _menu_button("SPIELEN", true)
	_btn_play.pressed.connect(_play)
	vb.add_child(_btn_play)

	_btn_mp = _menu_button("MULTIPLAYER", false)
	_btn_mp.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/mp_lobby.tscn"))
	vb.add_child(_btn_mp)

	var tut := _menu_button("TUTORIAL", false)
	tut.pressed.connect(_start_tour)
	vb.add_child(tut)

	_btn_settings = _menu_button("EINSTELLUNGEN", false)
	_btn_settings.pressed.connect(_open_settings)
	vb.add_child(_btn_settings)

	var quit := _menu_button("BEENDEN", false)
	quit.pressed.connect(func(): get_tree().quit())
	vb.add_child(quit)


func _menu_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 58)
	b.add_theme_font_override("font", UiTheme.heading_font(3))
	b.add_theme_font_size_override("font_size", 20)
	UiTheme.style_button(b, primary)
	return b


func _build_profile_card() -> void:
	# Klickbare Karte: oeffnet die Profil-Ansicht (Bild hochladen, Name, Stats).
	var card := PanelContainer.new()
	_profile_card = card
	card.position = Vector2(24, 20)
	card.custom_minimum_size = Vector2(232, 0)
	var sb := UiTheme.glass_box(12, 0.45)
	sb.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_open_profile())
	add_child(card)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)

	_card_avatar = Control.new()
	_card_avatar.custom_minimum_size = Vector2(44, 44)
	_card_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_card_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_card_avatar)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 17)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_name_label)

	_pp_label = Label.new()
	_pp_label.add_theme_font_size_override("font_size", 17)
	_pp_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.9))
	_pp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_pp_label)

	_plays_label = Label.new()
	_plays_label.add_theme_font_size_override("font_size", 11)
	_plays_label.add_theme_color_override("font_color", COL_DIM)
	_plays_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_plays_label)

	_refresh_profile()


func _open_profile() -> void:
	var panel := ProfilePanel.new()
	panel.closed.connect(_refresh_profile)
	add_child(panel)
	# Tour: nach dem Schliessen des Profils geht es weiter.
	if _tour_step >= 0 and _tour_step < _tour_steps.size() \
			and str(_tour_steps[_tour_step].get("click", "")) == "profile":
		panel.closed.connect(_tour_next, CONNECT_ONE_SHOT)


func _open_settings() -> void:
	var panel := SettingsPanel.new()
	add_child(panel)
	if _tour_step >= 0 and _tour_step < _tour_steps.size() \
			and str(_tour_steps[_tour_step].get("click", "")) == "settings":
		panel.closed.connect(_tour_next, CONNECT_ONE_SHOT)


# ---------------------------------------------------------------------------
# Tutorial-Tour: fuehrt LIVE durchs echte Menue (Pfeil blinkt, User klickt).
# ---------------------------------------------------------------------------

func _start_tour() -> void:
	_tour_steps = [
		{ "target": _profile_card, "click": "profile",
			"text": "Das ist DEIN PROFIL: Name, pp, Profilbild.\nKlick die Karte an — und danach wieder zu!" },
		{ "target": _btn_settings, "click": "settings",
			"text": "Hier stellst du Tasten, Scroll-Speed, Offset und FPS ein.\nKlick auf EINSTELLUNGEN — schau dich um und schliesse wieder!" },
		{ "target": _btn_play, "click": "",
			"text": "SPIELEN oeffnet den Song-Browser.\nDort findest du auch den Online-Tab (Maps laden), ★-Filter und Collections." },
		{ "target": _btn_mp, "click": "",
			"text": "MULTIPLAYER: Raum erstellen, Code an Freunde schicken,\ndie Krone 👑 waehlt die Map — mit Live-Scoreboard!" },
	]
	_tour_step = -1
	_tour_next()


func _tour_next() -> void:
	if _tour_overlay != null:
		_tour_overlay.queue_free()
		_tour_overlay = null
	_tour_step += 1
	if _tour_step >= _tour_steps.size():
		_tour_finish()
		return
	var st: Dictionary = _tour_steps[_tour_step]
	_tour_overlay = Control.new()
	_tour_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tour_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tour_overlay)
	var target := st.target as Control
	var r := target.get_global_rect()
	# Blinkender Pfeil direkt ueber dem echten Element.
	var arrow := Label.new()
	arrow.text = "⬇"
	arrow.custom_minimum_size = Vector2(64, 0)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.position = Vector2(r.get_center().x - 32.0, r.position.y - 96.0)
	arrow.add_theme_font_size_override("font_size", 56)
	arrow.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0))
	arrow.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	arrow.add_theme_constant_override("shadow_outline_size", 10)
	_tour_overlay.add_child(arrow)
	var atw := arrow.create_tween().set_loops()
	atw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	atw.tween_property(arrow, "position:y", r.position.y - 66.0, 0.4)
	atw.tween_property(arrow, "position:y", r.position.y - 96.0, 0.4)
	atw.parallel().tween_property(arrow, "modulate:a", 0.55, 0.4)
	atw.chain().tween_property(arrow, "modulate:a", 1.0, 0.0)
	# Kurzer Text daneben (klickt NICHT weg — das Ziel ist klickbar).
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(12, 0.9)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var px := clampf(r.get_center().x + 60.0, 20.0, get_viewport_rect().size.x - 480.0)
	panel.position = Vector2(px, maxf(r.position.y - 90.0, 16.0))
	_tour_overlay.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var body := Label.new()
	body.text = str(st.text)
	body.add_theme_font_size_override("font_size", 15)
	vb.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	if str(st.get("click", "")) == "":
		var next := Button.new()
		next.text = "Weiter"
		next.custom_minimum_size = Vector2(110, 36)
		UiTheme.style_button(next, true)
		next.pressed.connect(_tour_next)
		row.add_child(next)
	else:
		var hintl := Label.new()
		hintl.text = "→ klick das markierte Element"
		hintl.add_theme_font_size_override("font_size", 12)
		hintl.add_theme_color_override("font_color", COL_ACCENT)
		row.add_child(hintl)
	var skip := Button.new()
	skip.text = "Tour beenden"
	skip.custom_minimum_size = Vector2(0, 36)
	UiTheme.style_button(skip)
	skip.pressed.connect(_tour_finish)
	row.add_child(skip)


func _tour_finish() -> void:
	if _tour_overlay != null:
		_tour_overlay.queue_free()
		_tour_overlay = null
	_tour_step = -1
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(16, 0.9)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var t := Label.new()
	t.text = "Menue-Tour fertig!"
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", COL_ACCENT)
	vb.add_child(t)
	var b := Label.new()
	b.text = "Jetzt die Uebungs-Map: sie haelt an und zeigt dir\nNoten, Holds und Doppelnoten direkt im Spiel."
	b.add_theme_font_size_override("font_size", 15)
	vb.add_child(b)
	var go := Button.new()
	go.text = "🚀 UEBUNGS-MAP STARTEN"
	go.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(go, true)
	go.pressed.connect(_start_practice)
	vb.add_child(go)
	var guide := Button.new()
	guide.text = "📖 Wissens-Guide lesen (pp, Sterne, Acc …)"
	guide.custom_minimum_size = Vector2(0, 42)
	UiTheme.style_button(guide)
	guide.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/tutorial.tscn"))
	vb.add_child(guide)
	var close := Button.new()
	close.text = "Schliessen"
	close.custom_minimum_size = Vector2(0, 38)
	UiTheme.style_button(close)
	close.pressed.connect(overlay.queue_free)
	vb.add_child(close)


## Uebungs-Map (Set 844183) im Tutorial-Modus starten.
func _start_practice() -> void:
	var lib := MapLibrary.new()
	lib.scan()
	for ms in lib.mapsets:
		if not ms.osz_path.get_file().begins_with("844183"):
			continue
		for i in ms.difficulty_count():
			var m := ms.meta_at(i)
			if int(m.get("mode", 0)) != 3:
				continue
			GameSession.tutorial = true
			GameSession.mods = { "NF": true }
			GameSession.is_replay = false
			GameSession.replay_events = []
			GameSession.set_selection(ms.osz_path, i, ms.version_name_at(i),
				str(m.get("osu_filename", "")), ms.stars_at(i))
			get_tree().change_scene_to_file("res://scenes/mania_3d.tscn")
			return


func _refresh_profile() -> void:
	_name_label.text = Settings.profile_name
	_pp_label.text = "%.0f pp" % ScoreStore.profile_pp()
	_plays_label.text = "%d Plays" % ScoreStore.total_plays()
	# Avatar-Kreis: eigenes Bild oder Initial.
	for c in _card_avatar.get_children():
		c.queue_free()
	var tex := Settings.avatar_texture()
	if tex != null:
		var rect := TextureRect.new()
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.texture = tex
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/avatar_circle.gdshader")
		rect.material = m
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_avatar.add_child(rect)
	else:
		var circle := ColorRect.new()
		circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		circle.color = Color(0.16, 0.30, 0.42)
		var m2 := ShaderMaterial.new()
		m2.shader = load("res://shaders/avatar_circle.gdshader")
		circle.material = m2
		circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_avatar.add_child(circle)
		var initial := Label.new()
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.text = Settings.profile_name.substr(0, 1).to_upper()
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.add_theme_font_size_override("font_size", 20)
		initial.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
		initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_avatar.add_child(initial)


func _build_recent() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -420
	panel.offset_right = -28
	panel.offset_top = 24
	var sb := UiTheme.glass_box(14, 0.5)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var head := Label.new()
	head.text = "Letzte Scores"
	head.add_theme_font_size_override("font_size", 17)
	head.add_theme_color_override("font_color", COL_ACCENT)
	vb.add_child(head)

	var recent := ScoreStore.recent_plays(6)
	if recent.is_empty():
		var empty := Label.new()
		empty.text = "Noch keine Plays — leg los!"
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", COL_DIM)
		vb.add_child(empty)
		return
	for e in recent:
		vb.add_child(_recent_row(e))


func _recent_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var grade := Label.new()
	var g := str(e.get("grade", "D"))
	grade.text = "F" if bool(e.get("failed", false)) else g
	grade.custom_minimum_size = Vector2(30, 0)
	grade.add_theme_font_size_override("font_size", 22)
	grade.add_theme_color_override("font_color",
		Color(1.0, 0.3, 0.3) if bool(e.get("failed", false)) else GRADE_COLOR.get(g, Color.WHITE))
	row.add_child(grade)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var map_label := Label.new()
	map_label.text = "%s [%s]" % [str(e.get("map", "?")), str(e.get("version", ""))]
	map_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	map_label.add_theme_font_size_override("font_size", 14)
	info.add_child(map_label)
	var detail := Label.new()
	var pp := float(e.get("pp", -1.0))
	var pp_txt := ("  ·  %.1fpp" % pp) if pp >= 0.0 else ""
	detail.text = "%.2f%%  ·  %d%s" % [float(e.get("accuracy", 0.0)) * 100.0, int(e.get("score", 0)), pp_txt]
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", COL_DIM)
	info.add_child(detail)

	return row


func _play() -> void:
	get_tree().change_scene_to_file("res://scenes/song_select.tscn")


func _capture() -> void:
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := get_viewport().get_texture().get_image()
	var path := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/main_menu.png"
	img.save_png(path)
	print("SHOT gespeichert: " + path)
	get_tree().quit(0)
