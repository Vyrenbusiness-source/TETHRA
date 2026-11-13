extends SceneTree

## Headless-Tests: Mania 2D, jede Note ist ueber ihre ganze Anflugzeit im Bild.
## 1. Skalierung > 100 %: der Spawn-Horizont liegt an der sichtbaren Bildkante,
##    nicht ausserhalb des Bildes (vorher fehlten bei 150 % 40 % der Strecke).
## 2. Intro-/Break-Anzeige liegt neben dem Feld statt ueber den mittleren Spalten.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_popin_2d_tests.gd

const EXPECTED := 17
const Z_LINE := 3.0
const Z_FAR := -46.0
const VIEW := Vector2(1920, 1080)

var S: Node
var PF: GDScript
var _passed := 0
var _failed := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _run() -> void:
	print("=== TETHRA Mania-2D-Pop-in-Tests ===")
	S = root.get_node("/root/Settings")
	PF = load("res://scripts/gameplay3d/playfield_2d.gd")
	var keep := [S.stage_scale_2d, S.scroll_up_2d, S.skin_values_2d, S.hit_position_2d, S.mod_vis_2d,
			S.cover_pct_2d, S.cover_from_bottom_2d, S.stage_pos_2d]
	S.skin_values_2d = true
	S.stage_pos_2d = 1
	S.mod_vis_2d = 0
	_scale()
	_mask()
	_overlay()
	S.stage_scale_2d = keep[0]
	S.scroll_up_2d = keep[1]
	S.skin_values_2d = keep[2]
	S.hit_position_2d = keep[3]
	S.mod_vis_2d = keep[4]
	S.cover_pct_2d = keep[5]
	S.cover_from_bottom_2d = keep[6]
	S.stage_pos_2d = keep[7]
	if _passed + _failed != EXPECTED:
		_failed += 1
		print("  FAIL nur %d von %d Pruefungen gelaufen (Skriptfehler?)" % [_passed + _failed - 1, EXPECTED])
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(c: bool, msg: String) -> void:
	if c:
		_passed += 1
		print("  ok   ", msg)
	else:
		_failed += 1
		print("  FAIL ", msg)


func _pf() -> Object:
	var pf = PF.new()
	pf.setup(4, 1.0, Z_LINE, Z_FAR, PackedStringArray(["D", "F", "J", "K"]), Color.WHITE)
	pf.preview_size = VIEW
	return pf


## Bild-Y einer Note mit Strecken-Anteil k (0 = Spawn, 1 = Linie).
func _sy(pf: Object, k: float) -> float:
	return pf.to_screen(Vector2(0.0, pf.z_to_y(lerpf(Z_FAR, Z_LINE, k)))).y


func _scale() -> void:
	var pf = _pf()
	for up in [false, true]:
		S.scroll_up_2d = up
		for sc in [0.5, 1.0, 1.25, 1.5]:
			S.stage_scale_2d = sc
			var y0 := _sy(pf, 0.0)
			var name := "%d %% %s" % [int(sc * 100.0), "oben" if up else "unten"]
			_ok(y0 >= -0.5 and y0 <= VIEW.y + 0.5, "Skalierung %s: Spawn im Bild (y=%.0f)" % [name, y0])
	S.scroll_up_2d = false
	S.stage_scale_2d = 1.5
	_ok(absf(_sy(pf, 0.0)) < 0.5, "150 %: Spawn genau an der Bildoberkante")
	_ok(is_equal_approx(_sy(pf, 1.0), pf.screen_line_y()), "150 %: Trefferzeit bleibt auf der Linie")
	var mid := _sy(pf, 0.5)
	_ok(is_equal_approx(mid, pf.screen_line_y() * 0.5), "150 %: Strecke linear (halbe Zeit = halber Weg)")
	S.stage_scale_2d = 1.0
	_ok(is_equal_approx(pf.z_to_y(Z_FAR), 0.0) and is_equal_approx(pf.track_top(), 0.0),
			"100 %: unveraendert, Spawn bei Feld-Y 0")
	pf.free()


func _mask() -> void:
	var pf = _pf()
	S.stage_scale_2d = 1.5
	S.mod_vis_2d = S.VIS_COVER
	S.cover_pct_2d = 50
	S.cover_from_bottom_2d = false
	pf._update_mask()
	var half: float = pf.z_to_y(lerpf(Z_FAR, Z_LINE, 0.5))
	_ok(pf.mask_alpha(half + 2.0) >= 0.99 and pf.mask_alpha(pf.z_to_y(lerpf(Z_FAR, Z_LINE, 0.3))) <= 0.01,
			"150 % + Cover 50 %: Abdeckung = halbe sichtbare Strecke")
	S.mod_vis_2d = 0
	S.stage_scale_2d = 1.0
	pf.free()


func _overlay() -> void:
	# Feld mittig (4K, 135 %): Anzeige mittig laege ueber den Spalten 2 und 3.
	var field := Rect2(660.0, 0.0, 600.0, 1080.0)
	var x: float = PF.overlay_center_x(field, VIEW.x, 320.0)
	_ok(not is_nan(x) and (x - 160.0 >= field.end.x or x + 160.0 <= field.position.x),
			"Break-Anzeige neben dem mittigen Feld (x=%.0f)" % x)
	_ok(x - 160.0 >= 0.0 and x + 160.0 <= VIEW.x, "Break-Anzeige ganz im Bild")
	# Feld am linken Rand: Bildmitte ist frei, Anzeige bleibt dort.
	var left := Rect2(136.0, 0.0, 400.0, 1080.0)
	_ok(is_equal_approx(PF.overlay_center_x(left, VIEW.x, 320.0), VIEW.x * 0.5), "Feld links: Anzeige bleibt mittig")
	# Kein Platz daneben (schmales Fenster): NAN, Aufrufer blendet vor der ersten Note aus.
	_ok(is_nan(PF.overlay_center_x(Rect2(100.0, 0.0, 600.0, 600.0), 800.0, 320.0)), "Kein Platz: NAN")
