shader_type canvas_item;

// Frosted-Glass-Panel: blurrt den Bildschirminhalt dahinter, legt einen
// Tint darueber und schneidet die Flaeche mit abgerundeten Ecken (SDF) frei.
// rect_size/radius werden von GlassPanel bei jeder Groessenaenderung gesetzt.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 rect_size = vec2(200.0, 200.0);
uniform float radius = 16.0;
uniform vec4 tint : source_color = vec4(0.06, 0.07, 0.11, 1.0);
uniform float tint_amount = 0.55;
uniform float blur = 2.5;
uniform float border = 1.2;
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 0.14);

float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	float d = rounded_box(p, rect_size * 0.5, radius);
	float alpha = 1.0 - smoothstep(0.0, 1.5, d);
	if (alpha <= 0.001) {
		discard;
	}

	// Weicher Box-Blur des Hintergrunds (8 Taps + Zentrum).
	vec2 px = SCREEN_PIXEL_SIZE * blur;
	vec4 c = texture(screen_tex, SCREEN_UV) * 0.20;
	c += texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)) * 0.10;
	c += texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)) * 0.10;
	c += texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)) * 0.10;
	c += texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)) * 0.10;
	c += texture(screen_tex, SCREEN_UV + px) * 0.10;
	c += texture(screen_tex, SCREEN_UV - px) * 0.10;
	c += texture(screen_tex, SCREEN_UV + vec2(px.x, -px.y)) * 0.10;
	c += texture(screen_tex, SCREEN_UV + vec2(-px.x, px.y)) * 0.10;

	vec3 glass = mix(c.rgb, tint.rgb, tint_amount);

	// Heller Innen-Rand -> saubere Glaskante.
	float edge = smoothstep(-border - 1.0, -border, d);
	glass = mix(glass, border_color.rgb, edge * border_color.a);

	COLOR = vec4(glass, alpha);
}
