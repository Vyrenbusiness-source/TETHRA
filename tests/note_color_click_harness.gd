extends SceneTree

## Klick-Harness: bedient den NoteColorPicker im ECHTEN Einstellungsfenster nur per
## Viewport.push_input (Maus/Tasten) und prueft Modus, Vorlagen, Farbwaehler (Ziehen,
## Farbton, Hex, Verwerfen, Klick daneben, Esc), Holds, Reiter, "2D wie 3D",
## Zuruecksetzen, Speichern + Neuladen, Vorschau und Tastatur-Fokus.
## Selbst-beendend (Fenster noetig fuer die Bilder), Exit 1 bei Fehler:
##   Godot_v4.7-stable_win64_console.exe --path . --position -1920,0 --audio-driver Dummy \
##       --script res://tests/note_color_click_harness.gd -- --out=<dir>
## Schreibt nur user://note_colors_click.cfg (wird geloescht), aendert keine Settings.
## Vorher belegte Macken des alten Pickers (Commit 3d3bae0): Ziehen im Godot-Picker
## sprang zurueck (Helligkeit hochgezogen) und speicherte bei jeder Mausbewegung;
## Klick neben das Popup schloss die ganzen Einstellungen; Vorlage im Takt-Modus
## ohne Wirkung; Hold-Felder bei "automatisch" tot; kein Tastatur-Fokus sichtbar;
## "2D wie 3D" aus sprang nicht auf den 2D-Reiter zurueck; Schachbrett-Felder
## (Deckkraft 0.7); Popup durchsichtig, mit HDR-Intensitaet und Pipette.

var _out := "user://notecolorclick"
var _panel: Control
var _picker: Control   ## NoteColorPicker (erst zur Laufzeit laden: braucht die Autoloads)
var _failed := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame


# ------------------------------------------------------------------ Eingabe

func _move(p: Vector2, mask: int = 0) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	m.button_mask = mask
	root.push_input(m)


func _button(p: Vector2, down: bool, idx: int = MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	e.pressed = down
	e.position = p
	e.global_position = p
	if idx == MOUSE_BUTTON_LEFT:
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


func _drag(a: Vector2, b: Vector2, steps: int = 8) -> void:
	_move(a)
	await _frames(1)
	_button(a, true)
	await _frames(1)
	for k in steps:
		_move(a.lerp(b, (k + 1) / float(steps)), MOUSE_BUTTON_MASK_LEFT)
		await _frames(1)
	_button(b, false)
	await _frames(2)


func _key(code: int, ctrl: bool = false, unicode: int = 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.ctrl_pressed = ctrl
		e.unicode = unicode if down else 0
		e.pressed = down
		root.push_input(e)
		await _frames(1)
	await _frames(1)


func _type(text: String) -> void:
	for ch in text:
		await _key(OS.find_keycode_from_string(ch.to_upper()), false, ch.unicode_at(0))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("SHOT ", name)


func _pixel(p: Vector2) -> Color:
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image().get_pixelv(Vector2i(p))


# ------------------------------------------------------------------ Aufbau

func _open_panel() -> void:
	_panel = load("res://scripts/ui/settings_panel.gd").new()
	root.add_child(_panel)
	await _frames(10)
	_picker = _panel.get("_note_colors")
	if _picker == null:
		print("FAIL kein Picker im Einstellungsfenster (Skriptfehler?)")
		quit(1)
		return
	_picker.call("show_mode", false)
	await _frames(2)
	var sc: ScrollContainer = _panel.get("_scroll")
	var y := _picker.get_global_rect().position.y - sc.get_global_rect().position.y + sc.scroll_vertical
	sc.scroll_vertical = int(y) - 40
	await _frames(6)


## Farbvergleich auf 8 Bit (Hex-Eingabe rundet auf ganze Stufen).
func _html(c: Color) -> String:
	return c.to_html(false)


func _alive() -> bool:
	return is_instance_valid(_panel) and not _panel.is_queued_for_deletion()


func _saved_lane(lane: int) -> Color:
	var f := ConfigFile.new()
	if f.load(NoteColors.path) != OK:
		return Color(0, 0, 0, 0)
	return f.get_value("3d", "lane%d" % lane, Color(0, 0, 0, 0))


func _run() -> void:
	NoteColors.path = "user://note_colors_click.cfg"
	DirAccess.remove_absolute(NoteColors.path)
	NoteColors.reload()
	print("=== Notenfarben Klick-Harness ===")
	await _frames(2)
	await _open_panel()
	var vr := root.get_visible_rect()
	print("  info Fenster ", vr.size)
	await _shot("new_00_auto")
	var modes: Dictionary = _picker.get("_mode_btns")
	var chips: Dictionary = _picker.get("_chips")
	var lanes: Array = _picker.get("_lane_sw")
	var holds: Array = _picker.get("_hold_sw")
	var prev3d: Control = _picker.get("_prev3d")
	var pop: Control = _picker.get("_popup")

	# --- Modus ---------------------------------------------------------------
	_check(not (_picker.get("_editor") as Control).visible, "Automatisch: Farbfelder ausgeblendet, Hinweis sichtbar")
	await _click(_picker.find_child("UseOwn", true, false))
	_check(NoteColors.mode(false) == "lanes", "Knopf 'Eigene Farben waehlen' schaltet auf lanes")
	_check((_picker.get("_editor") as Control).visible, "Farbfelder sichtbar")
	await _click(modes["snap"])
	_check(NoteColors.mode(false) == "snap" and (_picker.get("_snap_box") as Control).visible, "Modus Takt + Legende")
	await _frames(4)
	await _shot("new_03_snap")
	await _click(modes["lanes"])
	_check(NoteColors.mode(false) == "lanes", "Modus Eigene Farben per Klick")

	# --- Vorlagen + Vorschau -------------------------------------------------
	await _frames(4)
	var p0: Vector2 = prev3d.get_global_rect().position + prev3d.call("sample_point", 3)
	var before := await _pixel(p0)
	await _click(chips["neon"])
	_check(NoteColors.preset(false) == "neon" and (chips["neon"] as Button).button_pressed, "Vorlage Neon aktiv")
	_check(NoteColors.lane_color(false, 0).is_equal_approx(NoteColors.preset_colors("neon")[0]), "Neon-Farben uebernommen")
	await _frames(4)
	var after := await _pixel(p0)
	var want2 := NoteColors.lane_color(false, 2)
	print("  info Vorschau-Pixel Spalte 3 vorher #%s nachher #%s (Notenfarbe #%s)"
			% [before.to_html(false), after.to_html(false), want2.to_html(false)])
	_check(not before.is_equal_approx(after), "3D-Vorschau aktualisiert sich nach Vorlage")
	_check(absf(after.h - want2.h) < 0.06 or absf(after.h - want2.h) > 0.94, "3D-Vorschau zeigt den Farbton der Spalte")
	await _shot("new_01_lanes")

	# --- Farbwaehler: oeffnen, Lage --------------------------------------------
	await _click(lanes[1])
	_check(pop.visible, "Farbfeld-Klick oeffnet den Farbwaehler")
	var pr := (pop.get("_panel") as Control).get_global_rect()
	print("  info Waehler ", pr, " Feld ", (lanes[1] as Control).get_global_rect(), " Vorschau ", prev3d.get_global_rect())
	_check(vr.encloses(pr), "Waehler liegt ganz im Fenster")
	_check(not pr.intersects(prev3d.get_global_rect()), "Waehler verdeckt die Vorschau nicht")
	_check(not pr.intersects((lanes[1] as Control).get_global_rect()), "Waehler verdeckt das Farbfeld nicht")
	await _shot("new_02_popup")

	# --- Ziehen im Farbfeld: folgt der Maus, speichert erst beim Schliessen ----
	var r := (pop.get("_sv") as Control).get_global_rect()
	var saved0 := _saved_lane(1)
	await _drag(r.position + r.size * Vector2(0.5, 0.5), r.position + r.size * Vector2(0.9, 1.0))
	var cur: Color = pop.call("current")
	print("  info nach Zug: S=%.2f V=%.2f" % [cur.s, cur.v])
	_check(absf(cur.v - NoteColors.MIN_V) < 0.02 and absf(cur.s - 0.9) < 0.03, "Ziehen: Marke folgt der Maus (unten = dunkelste erlaubte Farbe)")
	_check(NoteColors.lane_color(false, 1).is_equal_approx(cur), "Live: Spaltenfarbe folgt waehrend des Ziehens")
	_check(_saved_lane(1).is_equal_approx(saved0), "Waehrend des Ziehens nichts gespeichert")
	var hr := (pop.get("_hue") as Control).get_global_rect()
	await _click_at(hr.position + Vector2(hr.size.x / 3.0, hr.size.y * 0.5))
	cur = pop.call("current")
	_check(absf(cur.h - 1.0 / 3.0) < 0.02, "Farbton-Leiste: Klick bei 1/3 = Gruen (h=%.2f)" % cur.h)

	# --- Hex eintippen ---------------------------------------------------------
	var hex: LineEdit = pop.get("_hex")
	await _click(hex)
	await _key(KEY_A, true)
	await _type("ff3366")
	await _key(KEY_ENTER)
	cur = pop.call("current")
	_check(pop.visible, "Enter im Hex-Feld schliesst den Waehler nicht")
	_check(absf(cur.h - Color("ff3366").h) < 0.01 and cur.v <= NoteColors.MAX_V + 0.001,
			"Hex FF3366 uebernommen (Helligkeit begrenzt): #" + cur.to_html(false))
	await _shot("new_02b_hex")
	await _click(pop.find_child("Done", true, false))
	_check(not pop.visible, "Fertig schliesst")
	_check(_html(_saved_lane(1)) == _html(cur), "Fertig speichert")
	_check(NoteColors.preset(false) == "custom" and not (chips["neon"] as Button).button_pressed, "Eigene Farbe: kein Vorlagen-Chip mehr aktiv")
	_check(_html((lanes[1] as Object).get("color")) == _html(cur), "Farbfeld zeigt die neue Farbe")
	var rec: Array = NoteColors.recent()
	_check(not rec.is_empty() and _html(rec[0]) == _html(cur), "Zuletzt genutzt merkt die Farbe")

	# --- Esc = Verwerfen, Einstellungen bleiben offen --------------------------
	var keep := NoteColors.lane_color(false, 2)
	await _click(lanes[2])
	r = (pop.get("_sv") as Control).get_global_rect()
	await _drag(r.position + r.size * 0.5, r.position + r.size * Vector2(0.1, 0.1))
	_check(not NoteColors.lane_color(false, 2).is_equal_approx(keep), "Ziehen aendert live")
	await _key(KEY_ESCAPE)
	_check(not pop.visible, "Esc schliesst den Waehler")
	_check(_alive(), "Esc im Waehler laesst die Einstellungen offen")
	_check(NoteColors.lane_color(false, 2).is_equal_approx(keep), "Esc stellt die alte Farbe wieder her")
	_check((lanes[2] as Control).has_focus(), "Fokus zurueck auf dem Farbfeld")

	# --- Klick daneben / Mausrad ------------------------------------------------
	await _click(lanes[3])
	_check(pop.visible, "Waehler offen (Spalte 4)")
	var sc: ScrollContainer = _panel.get("_scroll")
	var sv0 := sc.scroll_vertical
	var mid := Vector2(vr.size.x * 0.5, vr.size.y * 0.75)
	_move(mid)
	await _frames(1)
	_button(mid, true, MOUSE_BUTTON_WHEEL_DOWN)
	_button(mid, false, MOUSE_BUTTON_WHEEL_DOWN)
	await _frames(3)
	_check(pop.visible and sc.scroll_vertical == sv0, "Mausrad bei offenem Waehler: nichts verrutscht")
	r = (pop.get("_sv") as Control).get_global_rect()
	await _click_at(r.position + r.size * Vector2(0.2, 0.3))
	var picked: Color = pop.call("current")
	await _click_at(Vector2(12, vr.size.y - 12))
	_check(_alive(), "Klick neben den Waehler laesst die Einstellungen offen")
	_check(_alive() and not pop.visible, "Klick daneben schliesst den Waehler")
	_check(NoteColors.lane_color(false, 3).is_equal_approx(picked) and _saved_lane(3).is_equal_approx(picked),
			"Klick daneben uebernimmt und speichert")
	if not _alive():
		await _open_panel()

	# --- Holds -----------------------------------------------------------------
	_check(NoteColors.hold_auto(false), "Holds automatisch (Standard)")
	await _click(holds[0])
	_check(pop.visible, "Hold-Farbfeld oeffnet den Waehler auch bei 'automatisch'")
	await _click((pop.get("_recent") as Control).get_child(0))
	await _click(pop.find_child("Done", true, false))
	_check(not NoteColors.hold_auto(false), "Eigene Hold-Farbe schaltet 'automatisch' aus")
	_check(not (_picker.get("_hold_auto") as CheckButton).button_pressed, "Schalter zeigt das")
	await _click(_picker.get("_hold_auto"))
	_check(NoteColors.hold_auto(false), "Schalter wieder an: Holds automatisch")
	_check(NoteColors.hold_color(false, 0).is_equal_approx(NoteColors.hold_of(NoteColors.lane_color(false, 0))), "Hold = Note etwas dunkler")

	# --- Tastatur ----------------------------------------------------------------
	(lanes[0] as Control).grab_focus()
	await _frames(2)
	await _shot("new_05_focus")
	await _key(KEY_ENTER)
	_check(pop.visible, "Enter auf dem Farbfeld oeffnet den Waehler")
	_check((pop.get("_sv") as Control).has_focus(), "Waehler hat den Tastatur-Fokus")
	var s0: float = (pop.call("current") as Color).s
	await _key(KEY_LEFT)
	_check((pop.call("current") as Color).s < s0, "Pfeiltaste aendert die Saettigung")
	await _key(KEY_ENTER)
	_check(not pop.visible and _alive(), "Enter uebernimmt, Einstellungen bleiben offen")

	# --- Reiter, 2D wie 3D -------------------------------------------------------
	_picker.call("show_mode", true)
	await _frames(2)
	var tabs: Array = _picker.get("_tab_btns")
	_check((tabs[1] as Button).button_pressed and _picker.get("_is_2d"), "2D-Modus: Reiter 2D")
	await _click(_picker.get("_link"))
	_check(NoteColors.link_2d() and not (tabs[1] as Button).visible, "2D wie 3D: ein gemeinsamer Satz")
	await _click(_picker.get("_link"))
	_check(not NoteColors.link_2d() and (tabs[1] as Button).button_pressed, "2D wie 3D aus: zurueck auf dem 2D-Reiter")
	await _click(modes["lanes"])
	await _click(chips["pastel"])
	_check(NoteColors.mode(true) == "lanes" and NoteColors.preset(true) == "pastel", "2D: eigener Satz Pastell")
	_check(NoteColors.preset(false) != "pastel", "3D bleibt unberuehrt")
	await _frames(30)
	await _shot("new_04_2d")
	await _click(tabs[0])
	_check(not _picker.get("_is_2d"), "Reiter 3D per Klick")

	# --- Zuruecksetzen -----------------------------------------------------------
	await _click(_picker.get("_reset_btn"))
	_check(NoteColors.mode(false) == "auto" and NoteColors.preset(false) == "standard" and NoteColors.hold_auto(false),
			"Zuruecksetzen: Automatisch, Standard")

	# --- Speichern + Neuladen ----------------------------------------------------
	await _click(modes["lanes"])
	await _click(chips["classic"])
	var want := NoteColors.lane_color(false, 1)
	NoteColors.reload()
	var fresh: Control = load("res://scripts/ui/note_color_picker.gd").new()
	fresh.visible = false
	root.add_child(fresh)
	await _frames(2)
	var fl: Array = fresh.get("_lane_sw")
	_check(((fl[1] as Object).get("color") as Color).is_equal_approx(want) and NoteColors.mode(false) == "lanes"
			and NoteColors.mode(true) == "lanes" and NoteColors.preset(true) == "pastel",
			"Neu geladen: neuer Picker zeigt dieselben Farben (3D Klassisch, 2D Pastell)")
	fresh.queue_free()

	# --- Esc ohne Waehler schliesst die Einstellungen (wie immer) -------------------
	await _key(KEY_ESCAPE)
	await _frames(2)
	_check(not _alive(), "Esc ohne offenen Waehler schliesst die Einstellungen")

	DirAccess.remove_absolute(NoteColors.path)
	print("FAILED: %d" % _failed if _failed > 0 else "ALL OK")
	await _frames(2)
	quit(1 if _failed > 0 else 0)
