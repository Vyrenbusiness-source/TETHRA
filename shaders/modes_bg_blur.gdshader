shader_type canvas_item;

// Orbit, Rally, Dirigent: Map-Bild als Vollbild ("cover"), weichgezeichnet nach
// Settings.modes_bg_blur (13 Taps eine Mip-Stufe tiefer, keine Bloecke) und nach
// Deckkraft abgedunkelt. Mania 2D nutzt weiter shaders/bg_blur.gdshader.
uniform sampler2D bg_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 tex_size = vec2(1920.0, 1080.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.2;
// 0 = scharf, 6 = sehr weich (Settings.blur_lod).
uniform float blur_lod : hint_range(0.0, 6.0) = 4.8;

void fragment() {
	vec2 screen = 1.0 / SCREEN_PIXEL_SIZE;
	float sa = screen.x / max(screen.y, 1.0);
	float ta = tex_size.x / max(tex_size.y, 1.0);
	vec2 uv = UV;
	if (sa > ta) {
		uv.y = (uv.y - 0.5) * ta / sa + 0.5;
	} else {
		uv.x = (uv.x - 0.5) * sa / ta + 0.5;
	}
	vec3 c = textureLod(bg_tex, uv, 0.0).rgb;
	if (blur_lod > 0.01) {
		float lod = max(blur_lod - 1.0, 0.0);
		vec2 o = exp2(blur_lod) / tex_size;
		vec3 acc = textureLod(bg_tex, uv, lod).rgb * 0.16;
		for (int i = 0; i < 6; i++) {
			float a = float(i) * 1.0472;
			vec2 d = vec2(cos(a), sin(a));
			acc += textureLod(bg_tex, uv + d * o * 0.6, lod).rgb * 0.08;
			acc += textureLod(bg_tex, uv + vec2(d.y, -d.x) * o * 1.3, lod).rgb * 0.06;
		}
		c = acc;
	}
	COLOR = vec4(c * opacity, 1.0);
}
