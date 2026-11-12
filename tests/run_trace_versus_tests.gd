extends SceneTree

## Headless-Tests fuer Trace-Versus: Miss-Bitfeld (Lobby), Paket-Klemmen (PlayerStatsCard),
## Sieger der Versus-Bilder, Live-Leiste (LiveTeamBar trace_mode), Live-Miss-Feld im Score.

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
	_bits(L)
	_sanitize()
	_winner()
	_rows()
	await _pictures()
	_live(L)
	print("FAILED: %d" % _failed)
	quit(1 if _failed > 0 else 0)


func _bits(L) -> void:
	var idx := PackedInt32Array([0, 3, 8, 9, 15, 200])
	var bits: PackedByteArray = L.pack_miss_bits(idx, 17)
	_check(bits.size() == 3, "17 Noten -> 3 Bytes")
	var back: PackedInt32Array = L.unpack_miss_bits(bits)
	_check(back == PackedInt32Array([0, 3, 8, 9, 15]), "Bitfeld hin und zurueck (Index ausserhalb faellt weg)")
	_check(L.pack_miss_bits(PackedInt32Array(), 0).is_empty(), "leere Map -> leeres Feld")
	_check(L.unpack_miss_bits(PackedByteArray()).is_empty(), "leeres Feld -> keine Misses")
	var big := PackedInt32Array()
	for i in range(0, 4000, 7):
		big.append(i)
	var bb: PackedByteArray = L.pack_miss_bits(big, 4000)
	_check(bb.size() == 500 and L.unpack_miss_bits(bb) == big, "4000 Noten: 500 Bytes, verlustfrei")


func _sanitize() -> void:
	var raw := { "score": 1000, "acc": 0.9, "notes": 17,
		"miss_bits": PackedByteArray([9, 131, 0, 255, 255]) }
	var d := PlayerStatsCard.sanitize(raw)
	_check(d.has("miss_bits") and (d.miss_bits as PackedByteArray).size() == 3, "Bitfeld auf ceil(notes/8) gekuerzt")
	_check(int(d.notes) == 17, "Notenzahl bleibt")
	var d2 := PlayerStatsCard.sanitize({ "score": 5, "miss_bits": "boom", "notes": 9 })
	_check(not d2.has("miss_bits"), "fremder Typ fuer miss_bits faellt weg")
	var d3 := PlayerStatsCard.sanitize({ "score": 5, "miss_bits": PackedByteArray([1]), "notes": 99999999 })
	_check(int(d3.notes) == PlayerStatsCard.MAX_NOTES, "Notenzahl geklemmt")
	_check(not PlayerStatsCard.sanitize({ "score": 1 }).has("miss_bits"), "ohne Feld (alte Clients) kein Feld")


func _winner() -> void:
	var e := [
		{ "name": "A", "final": { "score": 500, "n_miss": 3 } },
		{ "name": "B", "final": { "score": 900, "n_miss": 9, "failed": true } },
		{ "name": "C", "final": { "score": 700, "n_miss": 1 } },
	]
	_check(PlayerStatsCard.versus_winner(e) == 2, "Sieger: hoechster Score ohne Fail")
	e[0].final.score = 700
	e[0].final.n_miss = 0
	_check(PlayerStatsCard.versus_winner(e) == 0, "Gleichstand: weniger Fehlknicke gewinnt")
	var all_fail := [{ "final": { "score": 1, "failed": true } }, { "final": { "score": 4, "failed": true } }]
	_check(PlayerStatsCard.versus_winner(all_fail) == 1, "alle gefailt: hoechster Score")
	_check(PlayerStatsCard.versus_winner([{ "final": {} }]) == -1, "ohne Endergebnis kein Sieger")


func _rows() -> void:
	var r := LiveTeamBar.sorted_rows([
		{ "name": "b", "score": 10, "miss": 2 }, { "name": "a", "score": 30, "miss": 5 },
		{ "name": "c", "score": 10, "miss": 0 }])
	_check(r[0].name == "a" and r[1].name == "c" and r[2].name == "b", "Live-Zeilen: Score, dann Fehlknicke")
	var bar := LiveTeamBar.new()
	root.add_child(bar)
	bar.set_rows([{ "name": "x", "score": 1, "acc": 0.95, "combo": 4, "miss": 1, "me": true },
		{ "name": "y", "score": 2, "acc": 0.97, "combo": 9, "miss": -1 }])
	_check(bar.trace_mode and bar.custom_minimum_size.y >= LiveTeamBar.HEAD_H + 2.0 * LiveTeamBar.ROW_H,
		"Leiste waechst je Spieler")
	bar.queue_free()


func _pictures() -> void:
	var times := PackedFloat64Array([1000.0, 1500.0, 2000.0, 2500.0, 3000.0, 3400.0])
	var cols := PackedInt32Array([0, 1, 3, 2, 0, 3])
	var ends := PackedFloat64Array([-1.0, -1.0, 2400.0, -1.0, -1.0, -1.0])
	var path := TracePath.build(times, cols, ends)
	var colors: Array = []
	for c in cols:
		colors.append(Color.from_hsv(float(c) / 4.0, 0.6, 0.9))
	var e := [
		{ "name": "Host", "final": { "score": 900, "acc": 1.0, "n_miss": 0, "notes": 6, "miss_bits": PackedByteArray([0]) } },
		{ "name": "Anna", "final": { "score": 400, "acc": 0.8, "n_miss": 2, "notes": 6, "miss_bits": PackedByteArray([0b100010]) } },
	]
	var row := PlayerStatsCard.versus_pictures(path, colors, e, 120.0)
	root.add_child(row)
	await process_frame
	_check(row.get_child_count() == 2, "ein Bild je Spieler")
	var pics := row.find_children("*", "Control", true, false).filter(func(n): return n is PlayerStatsCard.TracePic)
	_check(pics.size() == 2, "zwei Trace-Bilder")
	if pics.size() == 2:
		_check(pics[0].frays.is_empty() and pics[1].frays.size() == 2, "Misses als Fransen nur beim Verfehlenden")
		var gray := 0
		for sg in pics[1].segs:
			if sg[1] == PlayerStatsCard.PIC_GRAY:
				gray += 1
		_check(gray >= 2, "verfehlte Strecken grau")
	var p0: StyleBoxFlat = (row.get_child(0) as PanelContainer).get_theme_stylebox("panel")
	var p1: StyleBoxFlat = (row.get_child(1) as PanelContainer).get_theme_stylebox("panel")
	_check(p0.border_width_top > p1.border_width_top, "Sieger hervorgehoben")
	var empty := PlayerStatsCard.versus_pictures(TracePath.build(PackedFloat64Array(), PackedInt32Array(),
			PackedFloat64Array()), [], [{ "name": "z", "final": {} }])
	_check(empty.get_child_count() == 1, "leere Map ohne Absturz")
	row.queue_free()
	empty.free()


func _live(L) -> void:
	L._reset()
	L.players = { 1: L._new_player("Host"), 2: L._new_player("Anna") }
	_check(int(L.players[1].miss) == 0, "neuer Spieler: miss = 0")
	_check(L.scene_misses() == -1, "ohne Spielszene: -1")
	var rows := LiveTeamBar.rows_from_lobby()
	_check(rows.size() == 2 and int(rows[0].miss) == 0, "Live-Zeilen aus der Lobby")
	L.players[2].final = { "score": 77, "acc": 0.5, "n_miss": 4 }
	rows = LiveTeamBar.rows_from_lobby()
	_check(int(rows[1].miss) == 4 and int(rows[1].score) == 77 and bool(rows[1].done), "Endergebnis ersetzt Live-Werte")
	_check(LiveTeamBar.ensure_trace(null) == null, "ohne Szene keine Leiste")
	L._reset()
