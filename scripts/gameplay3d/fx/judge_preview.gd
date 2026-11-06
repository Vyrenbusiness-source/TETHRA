extends Control
## Demo: JudgeDisplay im 150-BPM-Takt (Achtel), Kombo ab 118, ein Miss pro
## Runde. --shot speichert ein Bild kurz nach einem FRUEH-300 und beendet.

const SHOT_PATH := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/judge_preview.png"
const BPM := 150.0
const LANES := 4
const LANE_W := 110.0
## [Qualitaet, Offset ms]; negativ = zu frueh.
const SEQ: Array[Vector2] = [
	Vector2(0, 4), Vector2(0, -9), Vector2(1, 22), Vector2(0, -3),
	Vector2(2, 71), Vector2(0, 12), Vector2(1, -58), Vector2(0, 6),
	Vector2(3, -95), Vector2(0, -14), Vector2(4, 120), Vector2(5, 0),
	Vector2(0, 2), Vector2(1, 31), Vector2(0, -6), Vector2(0, 8),
]
const SHOT_HIT := 6
const SHOT_AFTER_S := 0.11

var _jd: JudgeDisplay
var _t := 0.0
var _hit := -1
var _combo := 117
var _shot := false
var _shot_done := false
var _shot_at := -1.0


func _ready() -> void:
	_shot = "--shot" in OS.get_cmdline_args() or "shot" in OS.get_cmdline_args()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	add_child(layer)
	_jd = JudgeDisplay.new()
	layer.add_child(_jd)
	_jd.setup(UiTheme.ACCENT)
	_jd.place(_line_y())


func _line_y() -> float:
	return get_viewport_rect().size.y * 0.84


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.06))
	var w := LANE_W * LANES
	var x0 := (vs.x - w) * 0.5
	draw_rect(Rect2(x0, 0, w, vs.y), Color(0.05, 0.06, 0.09))
	for i in LANES + 1:
		var x := x0 + i * LANE_W
		draw_line(Vector2(x, 0), Vector2(x, vs.y), Color(1, 1, 1, 0.06), 1.0)
	var ly := _line_y()
	draw_line(Vector2(x0, ly), Vector2(x0 + w, ly), Color(UiTheme.ACCENT, 0.8), 3.0)
	# Anfliegende Noten oben im Feld: Judge darf sie nicht verdecken.
	var period := 60.0 / BPM * 0.5
	for k in 10:
		var y := ly - (k + 1 - fmod(_t, period) / period) * 88.0
		if y < 0 or y > ly - 6:
			continue
		var lane := (k * 3 + 1) % LANES
		draw_rect(Rect2(x0 + lane * LANE_W + 10, y - 9, LANE_W - 20, 18),
				Color(0.75, 0.82, 0.95, 0.85))


func _process(delta: float) -> void:
	_t += delta
	var period := 60.0 / BPM * 0.5
	var h := int(_t / period)
	if h != _hit:
		_hit = h
		var s: Vector2 = SEQ[h % SEQ.size()]
		var q := int(s.x)
		_combo = 0 if q == 5 else _combo + 1
		_jd.show_judge(q, s.y)
		_jd.set_combo(_combo)
		if _shot and h == SHOT_HIT:
			_shot_at = _t + SHOT_AFTER_S
	var beat_phase := fmod(_t, 60.0 / BPM) / (60.0 / BPM)
	_jd.beat(exp(-beat_phase * 6.0))
	queue_redraw()
	if _shot and not _shot_done and _shot_at > 0.0 and _t >= _shot_at:
		_shot_done = true
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(SHOT_PATH.get_base_dir())
		img.save_png(SHOT_PATH)
		get_tree().quit()
