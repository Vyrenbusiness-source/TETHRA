extends CanvasLayer

## Szenen-Uebergaenge: SceneFader.go(path) blendet zu Schwarz, wechselt, blendet ein.
## Eingaben sind waehrend des Fades blockiert.

const FADE_OUT := 0.22
const FADE_IN := 0.28

var _rect: ColorRect
var _busy := false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 1)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	add_child(_rect)


func go(path: String) -> void:
	if _busy:
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	Sfx.ui_open()
	var tw := create_tween()
	tw.tween_property(_rect, "modulate:a", 1.0, FADE_OUT)
	await tw.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_rect, "modulate:a", 0.0, FADE_IN)
	await tw2.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func _input(event: InputEvent) -> void:
	if _busy and (event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventJoypadButton):
		get_viewport().set_input_as_handled()
