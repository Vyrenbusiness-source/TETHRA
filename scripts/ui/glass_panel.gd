class_name GlassPanel
extends Control

## Wiederverwendbares Frosted-Glass-Panel (clean glassy design). Blurrt den
## Hintergrund dahinter ueber shaders/glass_panel.gdshader und haelt die
## Shader-Groesse/Ecken synchron. Inhalte kommen in `content` (MarginContainer).

var content: MarginContainer
var radius: float = 16.0

var _rect: ColorRect
var _mat: ShaderMaterial


func _init(corner: float = 16.0, padding: int = 18, tint_amount: float = 0.55) -> void:
	radius = corner

	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/glass_panel.gdshader")
	_mat.set_shader_parameter("radius", radius)
	_mat.set_shader_parameter("tint_amount", tint_amount)
	_rect.material = _mat
	add_child(_rect)

	content = MarginContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", padding)
	content.add_theme_constant_override("margin_right", padding)
	content.add_theme_constant_override("margin_top", padding)
	content.add_theme_constant_override("margin_bottom", padding)
	add_child(content)

	resized.connect(_sync)


func _ready() -> void:
	_sync()


func _sync() -> void:
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("radius", radius)


## Bequemer Zugriff: fuegt einen Node in den Inhalt ein.
func add(node: Node) -> void:
	content.add_child(node)
