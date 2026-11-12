extends SceneTree

## Klick-Harness fuer das Einstellungsfenster: bedient es nur per Viewport.push_input
## (Maus/Tasten) und prueft Kernbedienung (Modus, Kategorie, Regler, Schalter, Auswahl,
## Suche, Zuruecksetzen je Gruppe, Tasten-Aufnahme, Name einmalig) und dass keine
## Einstellung verloren ging (jede bekannte Zeile ist da und per Suche erreichbar).
## Laeuft headless, schreibt nichts: Settings werden am Ende auf den Ausgangsstand
## zurueckgesetzt, das Fenster wird nie ueber "Schliessen" (= Speichern) beendet.
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_settings_panel_tests.gd

## Jede Einstellung, die es vor dem Umbau gab (plus neue), als Zeilen-Beschriftung.
const EXPECTED := {
	"field3d": ["Scroll Speed", "Spurbreite", "Welt", "Kamera", "Effekte"],
	"field2d": ["Scroll Speed", "Notenform", "Spurbreite", "Notengröße", "Hit-Lighting", "Scroll-Richtung",
		"Position", "Skalierung", "Trefferposition", "Spaltenabstand", "Sicht", "Abdeckung von", "Abdeckung",
		"Konstante Geschwindigkeit"],
	"look2d": ["Aktiver Skin", "Hintergrund", "Spielfeld abdunkeln", "Hintergrund-Unschärfe", "Skin-Werte nutzen",
		"Judgement-Position", "Kombo-Position", "Tasten unter den Noten", "Trefferlinie"],
	"orbit": ["Orbit-Tasten: A | B", "Vorlauf", "Tasten in Zielen", "Zielgröße", "Cursor-Größe", "Musik-Reaktion",
		"Hintergrund", "Welt"],
	"notes": ["Notenfarben"],
	"audio": ["Lautstärke", "Klarheit", "Bass", "Treffer-Sounds", "Hitsound", "Treffer-Lautstärke",
		"Audio-Offset", "Offset-Assistent"],
	"gfx": ["Qualität", "FPS-Limit", "Vollbild", "Spur-Leuchten", "Sicherer Grafikmodus"],
	"keys": ["Tasten 1–4", "Rally: Zonen", "Rally-Tasten (3 Zonen)", "Rally keys (4 zones)", "Orbit-Tasten: A | B",
		"Dirigent keys: A | B", "Trace speed", "Rebound drop time"],
	"profile": ["Name", "Spielsprache"],
}
## Optionen der alten Bahnen-Orbit-Seite, die es nicht mehr geben darf.
const ORBIT_GONE := ["Scroll Speed", "Takt-Raster", "Vorschau", "Notengröße", "Bahn-Deckkraft"]

var _panel: Control
var _failed := 0
var _passed := 0
var _saved := {}


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
		print("  ok   ", msg)
	else:
		_failed += 1
		print("  FAIL ", msg)


func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame


func _move(p: Vector2, mask: int = 0) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	m.button_mask = mask
	root.push_input(m)


func _button(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
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
	# Knoepfe weiter unten erst in den sichtbaren Bereich scrollen (Klick per Position).
	var sc: ScrollContainer = _panel.get("_scroll") if _panel != null else null
	if sc != null and sc.is_ancestor_of(c) and not sc.get_global_rect().encloses(c.get_global_rect()):
		sc.ensure_control_visible(c)
		await _frames(3)
	await _click_at(c.get_global_rect().get_center())


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


## Settings-Werte sichern/wiederherstellen (nur Skript-Variablen).
func _snapshot() -> void:
	var s: Node = root.get_node("/root/Settings")
	for p in s.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v = s.get(p.name)
			if v is Array or v is Dictionary:
				v = v.duplicate(true)
			if not (v is Object):
				_saved[p.name] = v


func _restore() -> void:
	var s: Node = root.get_node("/root/Settings")
	for n in _saved:
		s.set(n, _saved[n])


func _row(page: String, cap: String) -> Control:
	for e in _panel.get("_entries"):
		if e.page == page and e.cap == cap:
			return e.row
	return null


func _ctrl(page: String, cap: String) -> Control:
	var r := _row(page, cap)
	return r.get_meta("ctrl", null) if r != null else null


func _nav(id: String) -> Button:
	return (_panel.get("_nav_btns") as Dictionary).get(id)


func _run() -> void:
	print("=== Einstellungen Klick-Harness ===")
	_snapshot()
	var S: Node = root.get_node("/root/Settings")
	S.playfield_2d = false
	root.size = Vector2i(1280, 720)
	_panel = load("res://scripts/ui/settings_panel.gd").new()
	root.add_child(_panel)
	await _frames(8)

	# --- Nichts verloren ---------------------------------------------------------
	for page in EXPECTED:
		for cap in EXPECTED[page]:
			_check(_row(page, cap) != null, "Zeile '%s' auf Seite %s" % [cap, page])

	for cap in ORBIT_GONE:
		_check(_row("orbit", cap) == null, "Alte Bahnen-Option '%s' ist weg" % cap)

	# --- Modus -------------------------------------------------------------------
	var modes: Array = _panel.get("_mode_btns")
	_check(_panel.get("_cur") == "field3d", "Start: Mania 3D, Seite Spielfeld & Welt")
	await _click(modes[1])
	_check(S.playfield_2d and _panel.get("_cur") == "field2d", "Mania 2D: 2D an, Seite Spielfeld")
	_check(_nav("look2d") != null and _nav("field3d") == null, "Mania 2D: nur 2D-Kategorien")
	await _click(modes[2])
	_check(S.playfield_2d and _panel.get("_cur") == "orbit", "Orbit: eigene Seite, 2D-Schalter bleibt")
	await _click(modes[0])
	_check(not S.playfield_2d and _nav("field3d") != null and _nav("field2d") == null, "Mania 3D: 2D aus")

	# --- Orbit-Seite ----------------------------------------------------------------
	await _click(modes[2])
	var laps: OptionButton = _ctrl("orbit", "Vorlauf")
	laps.select(3)
	laps.item_selected.emit(3)
	await _frames(2)
	_check(S.orbit_laps == 3 and S.orbit_laps_for_ar(9.5) == 3, "Vorlauf 3 Runden gilt fest")
	laps.select(0)
	laps.item_selected.emit(0)
	await _frames(2)
	_check(S.orbit_laps == 0 and S.orbit_laps_for_ar(4.0) == 3 and S.orbit_laps_for_ar(7.0) == 2
		and S.orbit_laps_for_ar(9.0) == 1, "Vorlauf Auto folgt AR (3/2/1)")
	var ts: HSlider = _ctrl("orbit", "Zielgröße")
	_check(ts != null and is_equal_approx(ts.min_value, 90.0) and is_equal_approx(ts.max_value, 120.0),
		"Zielgröße 90-120 %")
	ts.value = 115.0
	await _frames(2)
	_check(S.orbit_target_size == 115, "Zielgröße wirkt (%d)" % S.orbit_target_size)
	var cs: HSlider = _ctrl("orbit", "Cursor-Größe")
	cs.value = 70.0
	await _frames(2)
	_check(S.orbit_cursor_size == 70, "Cursor-Größe wirkt (%d)" % S.orbit_cursor_size)
	var pv: Control = _panel.get("_orbit_preview")
	_check(pv != null and pv.is_visible_in_tree() and pv.get_global_rect().size.x > 100.0,
		"Orbit-Vorschau sichtbar (%s)" % ("Standbild" if pv == null or pv.get_script() == null or pv.get_script().resource_path == "" else pv.get_script().resource_path))
	if OS.get_cmdline_args().has("--shot") or OS.get_cmdline_user_args().has("--shot"):
		await _frames(20)
		var img := root.get_texture().get_image()
		img.save_png("user://settings_orbit.png")
		print("SHOT ", ProjectSettings.globalize_path("user://settings_orbit.png"))
	var og: VBoxContainer = _row("orbit", "Zielgröße").get_parent()
	await _click(og.get_meta("reset_btn"))
	_check(S.orbit_target_size == 100 and S.orbit_cursor_size == 100, "Gruppe Darstellung zurueckgesetzt")
	await _click(modes[0])

	# --- Kategorie ----------------------------------------------------------------
	await _click(_nav("audio"))
	_check(_panel.get("_cur") == "audio", "Klick auf Audio zeigt Audio")
	await _click(modes[1])
	_check(_panel.get("_cur") == "audio", "Moduswechsel laesst allgemeine Seite offen")
	await _click(modes[0])

	# --- Regler ---------------------------------------------------------------------
	var sl: HSlider = _ctrl("audio", "Treffer-Lautstärke")
	var r := sl.get_global_rect()
	await _click_at(Vector2(r.position.x + r.size.x * 0.25, r.get_center().y))
	_check(absf(S.hitsound_volume - 0.25) < 0.08, "Klick auf Regler setzt Treffer-Lautstärke (%.2f)" % S.hitsound_volume)
	var val: Label = _row("audio", "Treffer-Lautstärke").get_meta("value")
	_check(val.text.begins_with(str(int(round(S.hitsound_volume * 100.0)))), "Wert rechts folgt (%s)" % val.text)
	var before: float = S.hitsound_volume
	sl.grab_focus()
	await _key(KEY_RIGHT)
	_check(S.hitsound_volume > before, "Pfeiltaste erhoeht den Regler")

	# --- Schalter --------------------------------------------------------------------
	var hs: CheckButton = _ctrl("audio", "Treffer-Sounds")
	var was: bool = S.hitsounds
	await _click(hs)
	_check(S.hitsounds != was, "Klick auf Schalter schaltet Treffer-Sounds")
	var hr := hs.get_global_rect()
	var rr := _row("audio", "Treffer-Sounds").get_global_rect()
	_check(rr.end.x - hr.end.x < 20.0, "Schalter sitzt rechtsbuendig")

	# --- Zuruecksetzen je Gruppe -----------------------------------------------------
	var grp: VBoxContainer = _row("audio", "Treffer-Sounds").get_parent()
	await _click(grp.get_meta("reset_btn"))
	_check(S.hitsounds == true and is_equal_approx(S.hitsound_volume, 0.8), "Gruppe Treffer zurueckgesetzt")
	_check(is_equal_approx(sl.value, 80.0), "Regler zeigt den Standard")

	# --- Auswahl --------------------------------------------------------------------
	await _click(_nav("field3d"))
	var cam: OptionButton = _ctrl("field3d", "Kamera")
	var cam0: int = S.camera_mode
	cam.select(1 - cam0)
	cam.item_selected.emit(1 - cam0)
	await _frames(2)
	_check(S.camera_mode == 1 - cam0, "Auswahl Kamera wirkt")

	# --- Suche ------------------------------------------------------------------------
	var search: LineEdit = _panel.get("_search")
	await _key(KEY_F, true)
	_check(search.has_focus(), "Strg+F fokussiert die Suche")
	await _type("unsch")
	var results: VBoxContainer = _panel.get("_results")
	_check(results.visible and results.get_child_count() >= 1, "Suche zeigt Treffer")
	await _key(KEY_ENTER)
	await _frames(4)
	_check(_panel.get("_cur") == "look2d" and S.playfield_2d, "Enter springt zu Hintergrund-Unschärfe (Mania 2D)")
	var target := _row("look2d", "Hintergrund-Unschärfe")
	var sc: ScrollContainer = _panel.get("_scroll")
	_check(sc.get_global_rect().encloses(target.get_global_rect()), "Gesuchte Zeile ist sichtbar")
	_check(search.text == "" and (_panel.get("_nav") as Control).visible, "Suche danach leer, Kategorien wieder da")

	# --- Tasten-Aufnahme --------------------------------------------------------------
	await _click(_nav("keys"))
	var lanes: Array = _panel.get("_lane_btns")
	await _click(lanes[0])
	_check((lanes[0] as Button).text == "…", "Tastenknopf wartet auf Taste")
	await _key(KEY_Q)
	_check(S.key_lanes[0] == KEY_Q and (lanes[0] as Button).text == "Q", "Taste Q fuer Spur 1")
	await _click(lanes[1])
	await _key(KEY_ESCAPE)
	_check(is_instance_valid(_panel) and not _panel.is_queued_for_deletion(), "Esc bricht die Aufnahme ab, Fenster bleibt")
	var kg: VBoxContainer = _row("keys", "Tasten 1–4").get_parent()
	await _click(kg.get_meta("reset_btn"))
	_check(S.key_lanes == [KEY_D, KEY_F, KEY_J, KEY_K], "Tasten zurueckgesetzt")
	await _test_key_conflicts(S)

	# --- Name einmalig (nur ungueltige Eingabe, nichts gespeichert) ------------------
	await _click(_nav("profile"))
	var edit := _panel.find_child("NameEdit", true, false) as LineEdit
	if edit != null:
		edit.text = "x"
		await _click(_panel.find_child("NameSave", true, false))
		var hint := _panel.find_child("NameHint", true, false) as Label
		_check(hint != null and hint.text != "" and S.can_set_name(), "Zu kurzer Name: Hinweis, nicht gesetzt")
	else:
		_check(not S.can_set_name(), "Name schon festgelegt: nur Anzeige")

	# --- Layout: nichts ragt aus dem Panel -------------------------------------------
	var pr: Rect2 = (_panel.get("_panel") as Control).get_global_rect()
	_check(pr.size.x <= 1280.0 and pr.size.y <= 720.0, "Panel passt in 1280x720 (%s)" % str(pr.size))

	_test_key_roundtrip()

	_restore()
	_panel.queue_free()
	await _frames(2)
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _conflict_shown(base: int) -> bool:
	for l in (_panel.get("_conflict") as Dictionary).get(base, []):
		if (l as Label).is_visible_in_tree() and (l as Label).text != "":
			return true
	return false


## Doppelte Taste innerhalb eines Modus: roter Hinweis, nicht uebernommen;
## dieselbe Taste in einem anderen Modus ist erlaubt. Jede Belegung ist aenderbar.
func _test_key_conflicts(S: Node) -> void:
	# Ausgangsbelegung fest (die echte settings.cfg kann andere Tasten haben).
	S.orbit_key_inner = KEY_Z
	S.orbit_key_outer = KEY_X
	S.dirigent_key_a = KEY_Z
	S.dirigent_key_b = KEY_X
	_panel.call("_refresh_labels")
	var lanes: Array = _panel.get("_lane_btns")
	await _click(lanes[1])
	await _key(KEY_D)
	_check(S.key_lanes[1] == KEY_F and (lanes[1] as Button).text == "…" and _conflict_shown(3),
		"Mania: D doppelt -> Hinweis, Spur 2 bleibt F, Aufnahme laeuft weiter")
	var cl: Label = (_panel.get("_conflict") as Dictionary)[3][0]
	_check(cl.get_theme_color("font_color").r > 0.9 and cl.get_theme_color("font_color").g < 0.6, "Hinweis ist rot")
	await _key(KEY_ESCAPE)
	_check(not _conflict_shown(3) and S.key_lanes[1] == KEY_F, "Esc: Hinweis weg, nichts geaendert")

	# Dirigent: eigene Tasten A|B
	var dir: Array = _panel.get("_dirigent_btns")
	_check(dir.size() == 2 and (dir[0] as Button).text == "Z" and (dir[1] as Button).text == "X", "Dirigent zeigt Z | X")
	await _click(dir[0])
	await _key(KEY_A)
	_check(S.dirigent_key_a == KEY_A and S.dirigent_key_for(KEY_A) == 0 and S.orbit_key_inner == KEY_Z,
		"Dirigent A = A, Orbit bleibt Z")
	await _click(dir[1])
	await _key(KEY_A)
	_check(S.dirigent_key_b == KEY_X and _conflict_shown(50), "Dirigent: A doppelt -> nicht uebernommen")
	await _key(KEY_Z)
	_check(S.dirigent_key_b == KEY_Z and S.dirigent_key_for(KEY_Z) == 1 and not _conflict_shown(50),
		"Dirigent B = Z (Orbit nutzt Z auch: anderer Modus, erlaubt)")
	await _click(_row("keys", "Dirigent keys: A | B").get_parent().get_meta("reset_btn"))
	_check(S.dirigent_key_a == KEY_Z and S.dirigent_key_b == KEY_X, "Dirigent zurueckgesetzt")

	# Orbit
	var orb: Array = _panel.get("_orbit_btns")
	await _click(orb[orb.size() - 1])
	await _key(KEY_Z)
	_check(S.orbit_key_outer == KEY_X and _conflict_shown(20), "Orbit: Z doppelt -> nicht uebernommen")
	await _key(KEY_C)
	_check(S.orbit_key_outer == KEY_C and S.orbit_ring_for_key(KEY_C) == 1, "Orbit B = C")
	S.orbit_key_outer = KEY_X

	# Rally: eigene Belegung je Zonenzahl
	var r3: Array = _panel.get("_rally_btns")
	var r4: Array = _panel.get("_rally4_btns")
	_check(r3.size() == 3 and r4.size() == 4, "Rally: 3 + 4 Tastenknoepfe")
	await _click(r3[0])
	await _key(KEY_J)
	_check(S.rally_keys_3[0] == KEY_F and _conflict_shown(30), "Rally 3: J doppelt -> nicht uebernommen")
	await _key(KEY_A)
	_check(S.rally_keys(3)[0] == KEY_A and S.rally_zone_for_key(KEY_A, 3) == 0, "Rally 3 links = A")
	await _click(r4[3])
	await _key(KEY_L)
	_check(S.rally_keys(4)[3] == KEY_L and S.rally_zone_for_key(KEY_L, 4) == 3 and S.key_lanes[3] == KEY_K,
		"Rally 4 Zone 4 = L, Mania bleibt K")
	await _click(_row("keys", "Rally keys (4 zones)").get_parent().get_meta("reset_btn"))
	_check(S.rally_keys_3 == [KEY_F, KEY_J, KEY_K] and S.rally_keys_4 == [KEY_D, KEY_F, KEY_J, KEY_K],
		"Rally-Tasten zurueckgesetzt")

	# Trace / Rebound
	var ts: HSlider = _ctrl("keys", "Trace speed")
	ts.value = 700.0
	await _frames(2)
	_check(S.trace_speed == 700, "Trace speed wirkt (%d)" % S.trace_speed)
	var rd: HSlider = _ctrl("keys", "Rebound drop time")
	rd.value = 1200.0
	await _frames(2)
	_check(S.rebound_drop_ms == 1200, "Rebound drop time wirkt (%d)" % S.rebound_drop_ms)
	await _click(_row("keys", "Trace speed").get_parent().get_meta("reset_btn"))
	_check(S.trace_speed == 520 and S.rebound_drop_ms == 1000, "Trace / Rebound zurueckgesetzt")
	if OS.get_cmdline_args().has("--shot") or OS.get_cmdline_user_args().has("--shot"):
		await _click(_panel.get("_lane_btns")[1])
		await _key(KEY_D)
		await _frames(20)
		root.get_texture().get_image().save_png("user://settings_keys.png")
		print("SHOT ", ProjectSettings.globalize_path("user://settings_keys.png"))
		await _key(KEY_ESCAPE)


## Neue Felder: Speichern/Laden; alte Configs ohne Eintrag uebernehmen die bisherigen Tasten.
func _test_key_roundtrip() -> void:
	var SettingsScript: GDScript = root.get_node("/root/Settings").get_script()
	var path := "user://test_tmp/keys_all_%d.cfg" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	var a = SettingsScript.new()
	_check(a.dirigent_key_a == KEY_Z and a.dirigent_key_b == KEY_X, "Dirigent Standard Z/X")
	a.dirigent_key_a = KEY_Q
	a.dirigent_key_b = KEY_W
	a.rally_keys_4 = [KEY_A, KEY_S, KEY_K, KEY_L] as Array[int]
	a.save(path)
	var b = SettingsScript.new()
	b.load_settings(path)
	_check(b.dirigent_key_a == KEY_Q and b.dirigent_key_b == KEY_W and b.dirigent_key_for(KEY_W) == 1,
		"Dirigent-Tasten Roundtrip")
	_check(b.rally_keys_4 == [KEY_A, KEY_S, KEY_K, KEY_L], "Rally-4-Tasten Roundtrip")
	var cfg := ConfigFile.new()
	cfg.set_value("keys", "orbit_inner", KEY_C)
	cfg.set_value("keys", "orbit_outer", KEY_V)
	for i in 4:
		cfg.set_value("keys", "lane%d" % i, [KEY_A, KEY_S, KEY_K, KEY_L][i])
	cfg.save(path)
	var c = SettingsScript.new()
	c.load_settings(path)
	_check(c.dirigent_key_a == KEY_C and c.dirigent_key_b == KEY_V, "Alte Config: Dirigent uebernimmt Orbit-Tasten")
	_check(c.rally_keys_4 == [KEY_A, KEY_S, KEY_K, KEY_L], "Alte Config: Rally 4 uebernimmt Mania-Tasten")
	a.free()
	b.free()
	c.free()
	DirAccess.remove_absolute(path)
