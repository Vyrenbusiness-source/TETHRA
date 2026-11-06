extends Control
## Demo: MilestoneBurst im 120-BPM-Takt. Alle 2 s ein Meilenstein, dazwischen
## ein Kapitelname. --shot speichert ein Bild kurz nach dem 100-KOMBO-Pop.

const SHOT_PATH := "C:/Users/Gexanx/AppData/Local/Temp/claude/a8d2df055934fb12/2690cab5-bd8f-418e-ba0f-9da78692e0cd/scratchpad/milestone_preview.png"
const LANES := 4
const LANE_W := 110.0
const STEP_S := 2.0
const SEQ: Array[int] = [50, 100, 200, 300, 500, 1000]
const SECTIONS: Array[String] = ["KIAI", "DROP"]
const SHOT_IDX := 1
const SHOT_AFTER_S := 0.30

var _mb: MilestoneBurst
var _t := 0.0
var _step := -1
var _shot := false
var _shot_done := false
var _shot_at := -1.0


func _ready() -> void:
	_shot = "--shot" in OS.get_cmdline_args() or "shot" in OS.get_cmdline_args()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	add_child(layer)
	_mb = MilestoneBurst.new()
	layer.add_child(_mb)
	_mb.setup(UiTheme.ACCENT)


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.06))
	var w := LANE_W * LANES
	var x0 := (vs.x - w) * 0.5
	draw_rect(Rect2(x0, 0, w, vs.y), Color(0.05, 0.06, 0.09))
	for i in LANES + 1:
		draw_line(Vector2(x0 + i * LANE_W, 0), Vector2(x0 + i * LANE_W, vs.y), Color(1, 1, 1, 0.06), 1.0)
	var ly := vs.y * 0.84
	draw_line(Vector2(x0, ly), Vector2(x0 + w, ly), Color(UiTheme.ACCENT, 0.8), 3.0)
	for k in 10:
		var y := ly - (k + 1 - fmod(_t, 0.25) / 0.25) * 88.0
		if y < 0 or y > ly - 6:
			continue
		draw_rect(Rect2(x0 + ((k * 3 + 1) % LANES) * LANE_W + 10, y - 9, LANE_W - 20, 18),
				Color(0.75, 0.82, 0.95, 0.85))


func _process(delta: float) -> void:
	_t += delta
	var s := int(_t / STEP_S)
	if s != _step:
		_step = s
		_mb.fire(SEQ[s % SEQ.size()])
		_mb.fire_section(SECTIONS[s % SECTIONS.size()])
		if _shot and s == SHOT_IDX:
			_shot_at = _t + SHOT_AFTER_S
	queue_redraw()
	if _shot and not _shot_done and _shot_at > 0.0 and _t >= _shot_at:
		_shot_done = true
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(SHOT_PATH.get_base_dir())
		img.save_png(SHOT_PATH)
		get_tree().quit()
