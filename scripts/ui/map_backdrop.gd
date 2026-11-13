class_name MapBackdrop
extends ColorRect

## Map-Bild als Vollbild-Hintergrund ("cover") fuer Orbit, Rally, Dirigent, Rebound, Trace
## und das Hauptmenue (Mania bleibt bei shaders/bg_blur.gdshader): weich nach
## Settings.modes_bg_blur (0 = scharf), abgedunkelt nach Deckkraft (0 = kein Bild, dann
## bleibt nur der Graphit-Grund).
##   var bg := MapBackdrop.create(texture)            # Werte aus Settings
##   var bg := MapBackdrop.create(texture, 0.15, 80)  # feste Werte (Vorschau/Shots)
## Behandlung (ein Durchgang, 8 Abrufe je Pixel): das Bild wird ueber die Mip-Kette
## mit einem B-Spline-Filter gelesen (glatt, keine Bloecke, keine Flecken), leicht
## entsaettigt, auf einen warmen Graphit-Grund gelegt, zum Rand und nach unten ruhig
## abgedunkelt und mit feinem Korn gerastert (kein Banding in den dunklen Verlaeufen).

const MAX_W := 960  ## klein genug fuer billige Mips, gross genug fuer "scharf"
## Anteil der vollen Weichheit: das Bild bleibt als Form lesbar statt als Fleck.
const LOD_SCALE := 0.70

const SHADER_CODE := """shader_type canvas_item;
uniform sampler2D bg_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 tex_size = vec2(1920.0, 1080.0);
uniform float has_tex = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.2;
uniform float blur_lod : hint_range(0.0, 8.0) = 3.0;
uniform float saturation : hint_range(0.0, 1.0) = 0.72;
uniform float vignette : hint_range(0.0, 1.0) = 0.62;

vec3 smooth_tap(vec2 uv, int lod) {
	vec2 ts = vec2(textureSize(bg_tex, lod));
	vec2 p = uv * ts - 0.5;
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 w2 = 1.0 - w0 - w1 - w3;
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 h0 = (i + w1 / g0 - 0.5) / ts;
	vec2 h1 = (i + w3 / g1 + 1.5) / ts;
	float l = float(lod);
	vec3 a = textureLod(bg_tex, vec2(h0.x, h0.y), l).rgb * g0.x + textureLod(bg_tex, vec2(h1.x, h0.y), l).rgb * g1.x;
	vec3 b = textureLod(bg_tex, vec2(h0.x, h1.y), l).rgb * g0.x + textureLod(bg_tex, vec2(h1.x, h1.y), l).rgb * g1.x;
	return a * g0.y + b * g1.y;
}

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	vec2 screen = 1.0 / SCREEN_PIXEL_SIZE;
	float sa = screen.x / max(screen.y, 1.0);
	vec3 img = vec3(0.0);
	if (has_tex > 0.5) {
		float ta = tex_size.x / max(tex_size.y, 1.0);
		vec2 uv = UV;
		if (sa > ta) {
			uv.y = (uv.y - 0.5) * ta / sa + 0.5;
		} else {
			uv.x = (uv.x - 0.5) * sa / ta + 0.5;
		}
		if (blur_lod < 0.01) {
			img = textureLod(bg_tex, uv, 0.0).rgb;
		} else {
			float fl = floor(blur_lod);
			img = mix(smooth_tap(uv, int(fl)), smooth_tap(uv, int(fl) + 1), blur_lod - fl);
		}
		float l = dot(img, vec3(0.299, 0.587, 0.114));
		img = mix(vec3(l), img, saturation);
		// Lichter leicht stauchen: helle Bilder ueberstrahlen das Spielfeld nicht.
		img = img / (1.0 + 0.35 * l);
	}
	// Warmer Graphit-Grund, oben eine Spur heller (Raum statt Schwarz).
	vec3 base = mix(vec3(0.050, 0.047, 0.044), vec3(0.026, 0.024, 0.023), smoothstep(0.0, 1.0, UV.y));
	vec3 c = base + img * opacity * 1.25;
	vec2 d = (UV - 0.5) * vec2(min(sa, 2.0) / 1.78, 1.0);
	float v = smoothstep(0.28, 0.98, length(d) * 1.25);
	c *= 1.0 - vignette * v;
	c *= 1.0 - 0.22 * smoothstep(0.55, 1.0, UV.y);
	// Feines Korn: Struktur im Grund, bricht Stufen in den dunklen Verlaeufen.
	float n = hash(FRAGCOORD.xy) + hash(FRAGCOORD.xy + 17.0) - 1.0;
	c += n * (1.6 / 255.0);
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
"""

static var _shader: Shader

var _mat: ShaderMaterial
var _lod_bias := 0.0


static func create(tex: Texture2D, opacity := -1.0, blur_amount := -1) -> MapBackdrop:
	var r := MapBackdrop.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = Color(0, 0, 0, 1)
	var op := opacity if opacity >= 0.0 else float(Settings.modes_bg_dim)
	var amt := blur_amount if blur_amount >= 0 else int(Settings.modes_bg_blur)
	r.set_texture(tex, op, amt)
	return r


func _ensure_material() -> void:
	if _mat != null:
		return
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("has_tex", 0.0)
	material = _mat


## Bild/Werte setzen; tex == null oder opacity 0 = nur der Graphit-Grund.
func set_texture(tex: Texture2D, opacity: float, blur_amount: int) -> void:
	_ensure_material()
	_mat.set_shader_parameter("has_tex", 0.0)
	if tex == null or opacity <= 0.001:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() > MAX_W:
		img.resize(MAX_W, maxi(1, int(float(MAX_W) * img.get_height() / img.get_width())), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	_mat.set_shader_parameter("bg_tex", ImageTexture.create_from_image(img))
	_mat.set_shader_parameter("tex_size", Vector2(img.get_width(), img.get_height()))
	_mat.set_shader_parameter("has_tex", 1.0)
	set_values(opacity, blur_amount)


func set_values(opacity: float, blur_amount: int) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("opacity", clampf(opacity, 0.0, 1.0))
	var lod := Settings.blur_lod(blur_amount) * LOD_SCALE
	_mat.set_shader_parameter("blur_lod", clampf(lod + (_lod_bias if blur_amount > 0 else 0.0), 0.0, 8.0))


## Ruhigere Fassung fuer Menues: noch weicher (lod_bias in Mip-Stufen), weniger Farbe,
## staerkere Vignette. Nach create() aufrufen.
func set_calm(lod_bias: float, sat: float, vig: float, opacity: float, blur_amount: int) -> void:
	_ensure_material()
	_lod_bias = lod_bias
	_mat.set_shader_parameter("saturation", clampf(sat, 0.0, 1.0))
	_mat.set_shader_parameter("vignette", clampf(vig, 0.0, 1.0))
	set_values(opacity, blur_amount)
