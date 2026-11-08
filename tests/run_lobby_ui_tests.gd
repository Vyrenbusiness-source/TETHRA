extends SceneTree

## Headless-Tests fuer die Lobby-Oberflaeche (scripts/ui/mp_lobby.gd):
## Zustandsspalte, 3D/2D/Orbit-Abzeichen, Format-Reiter, Alleine-Hinweis,
## lobbycraft.csv vollstaendig, kein Ueberlauf bei 1280x720 und 2560x1440.
## Lobby-Zustand wird direkt gesetzt (kein Netz). Szene per load(): Finding
## mania-2d-options (statische Referenzen auf Autoload-Skripte kompilieren nicht).

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _init() -> void:
	await process_frame
	var L = root.get_node("Lobby")
	_csv_tests()
	var ui: Control = load("res://scenes/mp_lobby.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	L.stop_discovery()
	var MM = load("res://scripts/net/match_mode.gd")
	var my_id: int = ui.multiplayer.get_unique_id()

	# Raum mit mir allein.
	L._announce_t = 1.0e9
	L.active = true
	L.is_host = true
	L.crown_id = my_id
	L.room_name = "Testraum"
	L.room_code = "7K3F9-A2QXM"
	L.players = { my_id: L._new_player("Ich") }
	L.sel_map = {}
	L.mm = MM.new()
	ui._show_room()
	await process_frame
	_check(ui._room_box.visible and not ui._browser_box.visible, "Raum-Ansicht sichtbar")
	_check(ui._alone_hint.visible and ui._alone_hint.get_parent() == ui._players_box,
		"allein: Hinweis in der Spielerliste")
	_check(ui._alone_hint.text.contains("7K3F9-A2QXM"), "Hinweis nennt den Raum-Code")
	ui._refresh_room()
	ui._refresh_room()
	_check(is_instance_valid(ui._alone_hint) and ui._alone_hint.get_parent() == ui._players_box,
		"Hinweis ueberlebt mehrfaches Auffrischen")

	# Mehrere Spieler: Hinweis weg, eine Zeile pro Spieler.
	L.players[2] = L._new_player("Anna")
	L.players[2].view = "2D"
	L.players[2].ready = true
	L.players[3] = L._new_player("Ben")
	L.players[3].view = "Orbit"
	L.players[my_id].view = "3D"
	ui._refresh_room()
	_check(ui._alone_hint.get_parent() == null, "mit Mitspielern kein Alleine-Hinweis")
	_check(_live_children(ui._players_box) == 3, "drei Spielerzeilen")
	_check(ui._ready_count.text.contains("1") and ui._ready_count.text.contains("3"), "Bereit-Zaehler 1 / 3")

	# Abzeichen: ruhig, fester Text, nichts bei unbekannter Darstellung.
	for v in ["3D", "2D", "Orbit"]:
		var b: Control = ui._view_badge(v)
		_check(b != null and _first_label_text(b) == v, "Abzeichen " + v)
		if b != null:
			b.free()
	_check(ui._view_badge("") == null, "kein Abzeichen ohne Angabe")
	var row_texts := _all_label_texts(ui._players_box)
	_check(row_texts.has("2D") and row_texts.has("Orbit") and row_texts.has("3D"), "Zeilen zeigen alle drei Abzeichen")

	# Zustandsspalte: Bereit / Wartet / Map fehlt / Laedt Map.
	_check(ui._row_state(2, L.players[2], my_id)[1] == ui.COL_READY, "bereit = gruen")
	_check(ui._row_state(3, L.players[3], my_id)[1] == ui.COL_DIM, "wartet = gedimmt")
	L.sel_map = { "set_id": 987654321, "file": "987654321 fehlt.osz", "version": "X", "title": "Fehlt", "stars": 3.0 }
	_check(L.resolve_local_path() == "", "Test-Map fehlt lokal")
	ui._downloading = false
	_check(ui._row_state(my_id, L.players[my_id], my_id)[1] == ui.COL_WARN, "eigene Zeile: Map fehlt")
	ui._downloading = true
	_check(ui._row_state(my_id, L.players[my_id], my_id)[1] == ui.COL_ACCENT, "eigene Zeile: laedt Map")
	ui._downloading = false
	_check(ui._row_state(2, L.players[2], my_id)[1] == ui.COL_READY, "fremde Zeile: kein Map-fehlt-Zustand")
	L.sel_map = {}

	# Host/Krone in der eigenen Zeile.
	ui._refresh_room()
	_check(_all_label_texts(ui._players_box).has(TranslationServer.translate("Host")), "Host-Kennung sichtbar")

	# Format-Reiter folgen dem Raum-Modus, Spielmodus-Reiter dem Spielmodus.
	for k in 3:
		L.mm = MM.new(k) if k == 1 else MM.new()
		if k == 1:
			for id in L.players:
				L.mm.add_player(id)
		elif k == 2:
			L.mm.start_royale(L.players.keys())
		ui._refresh_room()
		var on := []
		for b in ui._mode_btns:
			on.append(b.button_pressed)
		_check(on == [k == 0, k == 1, k == 2], "Format-Reiter %d aktiv" % k)
		_check(ui._players_scroll.visible == (k == 0) and ui._board_holder.visible == (k != 0),
			"Liste/Tafel passt zu Format %d" % k)
	if ui._team_board != null:
		_check(_max_radius(ui._team_board) <= ui.R, "Teams-Tafel flach (Ecken <= R)")
	if ui._royale_board != null:
		_check(_max_radius(ui._royale_board) <= ui.R, "Royale-Tafel flach (Ecken <= R)")
	L.mm = MM.new()
	L.play_mode = "orbit"
	ui._refresh_room()
	_check(ui._play_btns["orbit"].button_pressed and not ui._play_btns["mania"].button_pressed, "Spielmodus-Reiter Orbit")
	L.play_mode = "mania"

	# Kein Ueberlauf: alles Sichtbare liegt im Fenster.
	for sz in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		root.size = sz
		ui.size = Vector2(sz)
		ui._refresh_room()
		await process_frame
		await process_frame
		var bad := _overflow(ui, Rect2(Vector2.ZERO, Vector2(sz)).grow(1.0))
		_check(bad == "", "Raum ohne Ueberlauf bei %dx%d %s" % [sz.x, sz.y, bad])
		ui._show_browser()
		L.stop_discovery()
		await process_frame
		bad = _overflow(ui, Rect2(Vector2.ZERO, Vector2(sz)).grow(1.0))
		_check(bad == "", "Raumliste ohne Ueberlauf bei %dx%d %s" % [sz.x, sz.y, bad])
		ui._show_room()

	L.set_meta("harness", true)
	L._reset()
	ui.queue_free()
	await process_frame
	print("lobby ui: %s" % ("FAIL %d" % _failed if _failed > 0 else "ok"))
	quit(1 if _failed > 0 else 0)


## Jeder tr("...")-Text aus mp_lobby.gd steht in einer CSV; lobbycraft.csv hat de+en.
func _csv_tests() -> void:
	var keys := {}
	for f in DirAccess.get_files_at("res://translations"):
		if not f.ends_with(".csv"):
			continue
		var fa := FileAccess.open("res://translations/" + f, FileAccess.READ)
		var head := fa.get_csv_line()
		while not fa.eof_reached():
			var row := fa.get_csv_line()
			if row.size() < 2 or row[0] == "":
				continue
			keys[row[0]] = true
			if f == "lobbycraft.csv":
				_check(row.size() == head.size() and row[1] != "" and row[2] != "",
					"lobbycraft.csv: de+en fuer '%s'" % row[0])
	var src := FileAccess.get_file_as_string("res://scripts/ui/mp_lobby.gd")
	var re := RegEx.new()
	re.compile("tr\\(\"((?:[^\"\\\\]|\\\\.)*)\"\\)")
	var missing: Array = []
	for m in re.search_all(src):
		var k := m.get_string(1).c_unescape()
		if not keys.has(k) and not missing.has(k):
			missing.append(k)
	_check(missing.is_empty(), "alle tr()-Texte uebersetzt %s" % str(missing))


func _live_children(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if not ch.is_queued_for_deletion() and ch is Control and ch.visible:
			c += 1
	return c


func _first_label_text(n: Node) -> String:
	if n is Label:
		return n.text
	for ch in n.get_children():
		var t := _first_label_text(ch)
		if t != "":
			return t
	return ""


func _all_label_texts(n: Node) -> Array:
	var out: Array = []
	if n is Label and n.is_visible_in_tree():
		out.append(n.text)
	for ch in n.get_children():
		out.append_array(_all_label_texts(ch))
	return out


func _max_radius(n: Node) -> int:
	var r := 0
	if n is Control:
		var c := n as Control
		var w := c.custom_minimum_size.x
		for slot in ["panel", "normal"]:
			if c.has_theme_stylebox_override(slot):
				var sb := c.get_theme_stylebox(slot) as StyleBoxFlat
				# Runde Avatare duerfen rund bleiben.
				if sb != null and not (w > 0.0 and w == c.custom_minimum_size.y and sb.corner_radius_top_left * 2 >= int(w)):
					r = maxi(r, sb.corner_radius_top_left)
	for ch in n.get_children():
		r = maxi(r, _max_radius(ch))
	return r


## Erster sichtbarer Knopf/Text, der aus dem Fenster ragt ("" = keiner).
func _overflow(n: Node, area: Rect2) -> String:
	if n is CanvasItem and not n.is_visible_in_tree():
		return ""
	if n is ScrollContainer:
		var sr := (n as Control).get_global_rect()
		return "" if area.encloses(sr) else str(n.get_path()) + " " + str(sr)
	if (n is Button or n is Label or n is LineEdit) and (n as Control).size.x > 0.0:
		var r := (n as Control).get_global_rect()
		if not area.encloses(r):
			return str(n.get_path()) + " " + str(r)
	for ch in n.get_children():
		var b := _overflow(ch, area)
		if b != "":
			return b
	return ""
