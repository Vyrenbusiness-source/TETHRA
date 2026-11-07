shader_type canvas_item;

// 2D-Modus: Map-Hintergrund als Vollbild ("cover"), leicht weichgezeichnet
// ueber Mip-Stufen (5 Taps, billig) und nach Deckkraft abgedunkelt.
uniform sampler2D bg_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 tex_size = vec2(1920.0, 1080.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.3;
// 0 = scharf; ~3 = leichter Blur.
uniform float blur_lod : hint_range(0.0, 6.0) = 3.0;

void fragment() {
	vec2 screen = 1.0 / SCREEN_PIXEL_SIZE;
	float sa = screen.x / max(screen.y, 1.0);
	float ta = tex_size.x / max(tex_size.y, 1.0);
	vec2 uv = UV;
	// Cover: kuerzere Achse fuellt, laengere wird mittig beschnitten.
	if (sa > ta) {
		uv.y = (uv.y - 0.5) * ta / sa + 0.5;
	} else {
		uv.x = (uv.x - 0.5) * sa / ta + 0.5;
	}
	vec3 c = textureLod(bg_tex, uv, blur_lod).rgb;
	if (blur_lod > 0.01) {
		vec2 o = exp2(blur_lod) / tex_size;
		c = c * 0.4
			+ textureLod(bg_tex, uv + vec2(o.x, o.y), blur_lod).rgb * 0.15
			+ textureLod(bg_tex, uv + vec2(-o.x, o.y), blur_lod).rgb * 0.15
			+ textureLod(bg_tex, uv + vec2(o.x, -o.y), blur_lod).rgb * 0.15
			+ textureLod(bg_tex, uv + vec2(-o.x, -o.y), blur_lod).rgb * 0.15;
	}
	COLOR = vec4(c * opacity, 1.0);
}
