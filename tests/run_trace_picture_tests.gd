extends SceneTree

## Tests fuer das Trace-Bild der Runde (Groessen, Determinismus, leere Map, Misses, Speichern).
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_trace_picture_tests.gd

var _passed := 0
var _failed := 0


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)


static func test_path() -> TracePath:
	var times := PackedFloat64Array()
	var cols := PackedInt32Array()
	var ends := PackedFloat64Array()
	var pattern := [3, 3, 1, 0, 0, 2, 3, 1, 1, 0, 2, 2, 3, 0, 1, 3]
	for i in 64:
		times.append(1000.0 + i * 260.0)
		cols.append(pattern[i % pattern.size()])
		ends.append(times[i])
	return TracePath.build(times, cols, ends)


static func test_judgements(path: TracePath, miss_every: int) -> Array:
	var out: Array = []
	for i in path.knots.size():
		var kn: TracePath.Knot = path.knots[i]
		var q := 5 if miss_every > 0 and i % miss_every == 0 and i > 0 else 1
		out.append(Vector4(kn.t, kn.cols[0], q, 0.0))
	return out


func _initialize() -> void:
	print("=== TETHRA Trace-Bild-Tests ===")
	var path := test_path()
	var meta := {"title": "Testlied", "version": "Hard", "player": "Tester", "acc": 0.9742,
		"date": "2026-11-12T10:00:00"}
	var judge := test_judgements(path, 5)
	var sq := TracePicture.render(path, judge, TracePicture.SIZE_SQUARE, meta)
	_ok(sq.get_width() == 1600 and sq.get_height() == 1600, "Quadrat 1600x1600")
	var sh := TracePicture.render(path, judge, TracePicture.SIZE_SHARE, meta)
	_ok(sh.get_width() == 1200 and sh.get_height() == 630, "Teilen 1200x630")
	var sq2 := TracePicture.render(path, judge, TracePicture.SIZE_SQUARE, meta)
	_ok(sq.get_data() == sq2.get_data(), "deterministisch (gleiche Bytes)")
	var all_hit := TracePicture.render(path, test_judgements(path, 0), Vector2i(800, 800), meta)
	var with_miss := TracePicture.render(path, judge, Vector2i(800, 800), meta)
	_ok(all_hit.get_data() != with_miss.get_data(), "Misses veraendern das Bild")
	var no_log := TracePicture.render(path, [], Vector2i(800, 800), meta)
	_ok(no_log.get_width() == 800, "ohne Log: alles gespielt, kein Absturz")
	var empty_path := TracePath.build(PackedFloat64Array(), PackedInt32Array(), PackedFloat64Array())
	var em := TracePicture.render(empty_path, [], Vector2i(1200, 630), meta)
	_ok(em.get_width() == 1200 and em.get_height() == 630, "leere Map: Bild in richtiger Groesse")
	var nul := TracePicture.render(null, [], Vector2i(640, 640))
	_ok(nul.get_width() == 640, "path = null: Bild")
	_ok(_differs_from_bg(sq, 800, 800, 700), "Bild enthaelt Faden (nicht nur Hintergrund)")
	_ok(not _differs_from_bg(em, 600, 200, 150), "leere Map: nur Hintergrund im Kartenbereich")
	# Speichern / Galerie
	var dir := "user://pictures_test/"
	var p := TracePicture.save(Image.create_from_data(8, 8, false, Image.FORMAT_RGBA8,
		PackedByteArray(Array(range(256)))), meta, dir)
	_ok(p != "" and FileAccess.file_exists(p), "PNG gespeichert")
	_ok(TracePicture.recent(12, dir).has(p), "Galerie listet das Bild")
	_ok(TracePicture.recent(0, dir).is_empty(), "Galerie n=0 leer")
	DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(dir)
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Weicht ein Pixel in der Naehe (cx, cy) +-r stark vom Hintergrundton ab?
func _differs_from_bg(img: Image, cx: int, cy: int, r: int) -> bool:
	for y in range(maxi(cy - r, 0), mini(cy + r, img.get_height()), 2):
		for x in range(maxi(cx - r, 0), mini(cx + r, img.get_width()), 2):
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b > 0.55:
				return true
	return false
