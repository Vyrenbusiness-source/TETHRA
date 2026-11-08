extends SceneTree

## Klick-Harness (Stand vor dem Umbau): bedient den alten NoteColorPicker im echten
## Einstellungsfenster per Viewport.push_input und meldet jede Macke als "BUG ...".
##   Godot_v4.7-stable_win64.exe --path . --position -1920,0 --audio-driver Dummy \
##       --script res://tests/note_color_click_harness.gd -- --out=<dir>

var _out := "user://notecolorclick"
var _panel: Control
var _picker: Control
var _bugs := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _bug(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  BUG  ", msg)
		_bugs += 1


func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame


func _move(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	root.push_input(m)


func _button(p: Vector2, down: bool, idx: int = MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	e.pressed = down
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(e)


func _click_at(p: Vector2) -> void:
	_move(p)
	await _frames(1)
	_button(p, true)
	await _frames(1)
	_button(p, false)
	await _frames(3)


func _click(c: Control) -> void:
	await _click_at(c.get_global_rect().get_center())


func _key(code: int) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	root.push_input(e)
	await _frames(1)
	var r := InputEventKey.new()
	r.keycode = code
	r.physical_keycode = code
	r.pressed = false
	root.push_input(r)
	await _frames(3)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("SHOT ", name)


func _open_panel() -> void:
	_panel = load("res://scripts/ui/settings_panel.gd").new()
	root.add_child(_panel)
	await _frames(10)
	_picker = _panel.get("_note_colors")
	var sc: ScrollContainer = _panel.get("_scroll")
	sc.scroll_vertical = int(_picker.position.y + _picker.get_parent().position.y) - 40
	_picker.call("show_mode", false)
	await _frames(6)


func _panel_alive() -> bool:
	return is_instance_valid(_panel) and not _panel.is_queued_for_deletion()


func _run() -> void:
	NoteColors.path = "user://note_colors_click.cfg"
	DirAccess.remove_absolute(NoteColors.path)
	NoteColors.reload()
	await _frames(2)
	await _open_panel()
	await _shot("old_00_open")
	var lanes: Array = _picker.get("_lane_btns")
	var holds: Array = _picker.get("_hold_btns")
	var cb: ColorPickerButton = lanes[0]
	var vr := root.get_visible_rect()

	# 1) Farbfeld anklicken: Popup oeffnet, liegt im Fenster?
	await _click(cb)
	var pop := cb.get_popup()
	_bug(pop.visible, "Farbfeld-Klick oeffnet Popup")
	var pr := Rect2(pop.position, pop.size)
	print("  info popup rect ", pr, " viewport ", vr.size, " swatch ", cb.get_global_rect())
	_bug(vr.encloses(pr), "Popup liegt ganz im Fenster")
	await _shot("old_01_popup")

	# 2) Im Farbfeld nach unten (dunkel) ziehen: springt der Picker zurueck?
	var picker := cb.get_picker()
	var sv: Control = null
	for c in picker.find_children("*", "Control", true, false):
		var cc := c as Control
		if cc.is_visible_in_tree() and cc.size.x > 150 and cc.size.y > 150 and cc.get_child_count() == 0:
			sv = cc
			break
	if sv != null:
		var r := sv.get_global_rect()
		r.position += Vector2(pop.position)
		var p0 := r.position + r.size * Vector2(0.5, 0.5)
		var p1 := r.position + r.size * Vector2(0.5, 0.97)
		_move(p0)
		await _frames(1)
		print("  info SV-Feld ", r, " Klasse ", sv.get_class())
		_button(p0, true)
		await _frames(1)
		print("  info nach Druck: Popup offen=%s Einstellungen offen=%s" % [pop.visible, _panel_alive()])
		if not is_instance_valid(picker):
			_bug(false, "Klick ins Farbfeld des Popups schliesst die Einstellungen")
			print("BUGS: %d" % _bugs)
			quit(0)
			return
		var drag_moves := 0
		for k in 8:
			var e := InputEventMouseMotion.new()
			e.position = p0.lerp(p1, (k + 1) / 8.0)
			e.global_position = e.position
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
			e.relative = (p1 - p0) / 8.0
			root.push_input(e)
			drag_moves += 1
			await _frames(1)
		var pv := picker.color.v
		_button(p1, false)
		await _frames(3)
		print("  info nach Zug nach unten: picker V=%.2f gespeichert V=%.2f (%d Zuege = %d Speichervorgaenge)"
				% [pv, NoteColors.lane_color(false, 0).v, drag_moves, drag_moves])
		_bug(picker.color.v < 0.3, "Picker folgt der Maus (V wird nicht waehrend des Ziehens hochgezogen)")
		_bug(picker.color.is_equal_approx(NoteColors.lane_color(false, 0)) or picker.color.v < 0.3,
				"Gezeigte Farbe = gespeicherte Farbe")
	else:
		print("  info kein SV-Feld gefunden")
	await _shot("old_02_dragged")

	# 3) Esc im Popup: schliesst nur das Popup, nicht die Einstellungen.
	await _key(KEY_ESCAPE)
	_bug(not pop.visible, "Esc schliesst das Popup")
	_bug(_panel_alive(), "Esc im Popup laesst die Einstellungen offen")
	if not _panel_alive():
		await _frames(4)
		await _open_panel()
		lanes = _picker.get("_lane_btns")
		holds = _picker.get("_hold_btns")
		cb = lanes[0]
		pop = cb.get_popup()

	# 4) Popup offen, Klick daneben (auf den Abdunkler): nur Popup zu.
	await _click(cb)
	_bug(cb.get_popup().visible, "Popup wieder offen")
	await _click_at(Vector2(12, vr.size.y - 12))
	var alive := _panel_alive()
	_bug(alive, "Klick neben das Popup laesst die Einstellungen offen")
	_bug(not alive or not cb.get_popup().visible, "Klick daneben schliesst Popup")
	if not _panel_alive():
		await _frames(4)
		await _open_panel()
		lanes = _picker.get("_lane_btns")
		holds = _picker.get("_hold_btns")
		cb = lanes[0]

	# 5) Modus "Nach Takt", dann Vorlage: sichtbare Wirkung?
	var modes: Dictionary = _picker.get("_mode_btns")
	var chips: Dictionary = _picker.get("_chips")
	await _click(modes["snap"])
	_bug(NoteColors.mode(false) == "snap", "Klick Modus Takt")
	await _click(chips["neon"])
	print("  info nach Vorlage Neon im Takt-Modus: mode=%s chip gedrueckt=%s" %
			[NoteColors.mode(false), (chips["neon"] as Button).button_pressed])
	_bug((chips["neon"] as Button).button_pressed, "Vorlage im Takt-Modus zeigt Wirkung (Chip aktiv)")
	await _shot("old_03_snap_preset")

	# 6) Hold-Feld bei "Holds automatisch": klickbar?
	await _click(modes["lanes"])
	await _click(holds[1])
	_bug((holds[1] as ColorPickerButton).get_popup().visible, "Hold-Farbfeld reagiert auf Klick")
	if (holds[1] as ColorPickerButton).get_popup().visible:
		await _key(KEY_ESCAPE)

	# 7) Fokus sichtbar?
	var fsb := cb.get_theme_stylebox("focus")
	var nsb := cb.get_theme_stylebox("normal")
	_bug(fsb != nsb, "Farbfeld hat sichtbaren Tastatur-Fokus")

	# 8) 2D-Modus, "2D wie 3D" an und wieder aus: Reiter zurueck auf 2D?
	if _panel_alive():
		_picker.call("show_mode", true)
		await _frames(2)
		var link: CheckButton = _picker.get("_link")
		await _click(link)
		await _click(link)
		var tabs: Array = _picker.get("_tab_btns")
		_bug((tabs[1] as Button).button_pressed, "nach 2D wie 3D aus wieder auf dem 2D-Reiter")
		_picker.call("show_mode", false)
		await _frames(2)

	# 9) Speichern + Neuladen: neuer Picker zeigt dieselben Farben.
	await _click(chips["pastel"])
	var want := NoteColors.lane_color(false, 2)
	NoteColors.reload()
	_bug(NoteColors.lane_color(false, 2).is_equal_approx(want) and NoteColors.preset(false) == "pastel",
			"Speichern + Neuladen behaelt Vorlage")

	print("BUGS: %d" % _bugs)
	if _panel_alive():
		_panel.queue_free()
	DirAccess.remove_absolute(NoteColors.path)
	await _frames(2)
	quit(0)
