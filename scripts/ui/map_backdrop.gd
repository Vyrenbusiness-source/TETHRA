class_name MapBackdrop
extends ColorRect

## Map-Bild als Vollbild-Hintergrund ("cover") fuer Orbit, Rally, Dirigent (Mania
## bleibt bei shaders/bg_blur.gdshader): weich nach Settings.modes_bg_blur (0 = scharf), abgedunkelt
## nach Deckkraft (0 = kein Bild, dann bleibt nur der dunkle Grund).
##   var bg := MapBackdrop.create(texture)            # Werte aus Settings
##   var bg := MapBackdrop.create(texture, 0.15, 80)  # feste Werte (Vorschau/Shots)

const MAX_W := 960  ## klein genug fuer billige Mips, gross genug fuer "scharf"

var _mat: ShaderMaterial


static func create(tex: Texture2D, opacity := -1.0, blur_amount := -1) -> MapBackdrop:
	var r := MapBackdrop.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = Color(0, 0, 0, 1)
	var op := opacity if opacity >= 0.0 else float(Settings.modes_bg_dim)
	var amt := blur_amount if blur_amount >= 0 else int(Settings.modes_bg_blur)
	r.set_texture(tex, op, amt)
	return r


## Bild/Werte setzen; tex == null oder opacity 0 = nur dunkler Grund.
func set_texture(tex: Texture2D, opacity: float, blur_amount: int) -> void:
	if tex == null or opacity <= 0.001:
		material = null
		_mat = null
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		material = null
		return
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() > MAX_W:
		img.resize(MAX_W, maxi(1, int(float(MAX_W) * img.get_height() / img.get_width())), Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/modes_bg_blur.gdshader")
	_mat.set_shader_parameter("bg_tex", ImageTexture.create_from_image(img))
	_mat.set_shader_parameter("tex_size", Vector2(img.get_width(), img.get_height()))
	set_values(opacity, blur_amount)
	material = _mat


func set_values(opacity: float, blur_amount: int) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("opacity", clampf(opacity, 0.0, 1.0))
	_mat.set_shader_parameter("blur_lod", Settings.blur_lod(blur_amount))
