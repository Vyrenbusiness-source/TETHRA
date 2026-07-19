shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Polarlicht-Vorhaenge ueber dem Horizont: langsam wehende, x-verzerrte
// Lichtbahnen in Songfarben, die mit dem Beat sanft aufatmen.

uniform vec3 col_a: source_color = vec3(0.2, 0.9, 0.6);
uniform vec3 col_b: source_color = vec3(0.4, 0.5, 1.0);
uniform float drift = 0.0;
uniform float pulse = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	// Wehende Vorhaenge: zwei Noise-Ebenen verzerren die Bahnen.
	float wave = vnoise(vec2(uv.x * 6.0 + drift * 0.16, drift * 0.05));
	float wave2 = vnoise(vec2(uv.x * 13.0 - drift * 0.11, 3.7 + drift * 0.04));
	float curtain = smoothstep(0.18, 0.78, wave * 0.7 + wave2 * 0.3);
	// Unten dicht, nach oben ausfransend.
	float vert = pow(uv.y, 1.7);
	float base = curtain * vert;
	vec3 col = mix(col_a, col_b, uv.y * 0.8 + wave2 * 0.3) * base;
	col *= 0.55 + pulse * 0.45;
	// Seiten weich ausblenden.
	float sx = 1.0 - smoothstep(0.55, 1.0, abs(uv.x * 2.0 - 1.0));
	ALBEDO = col * sx * 0.5;
	ALPHA = clamp(base * sx, 0.0, 1.0) * 0.35;
}
