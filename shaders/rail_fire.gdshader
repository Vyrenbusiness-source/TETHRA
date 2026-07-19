shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// ON-FIRE-Streckenkanten: prozedurales Feuer, das bei hoher Accuracy
// zuendet. UV.x laeuft entlang der Strecke, UV.y ist die Hoehe (0 unten).
//  intensity: 0..1 (0 = aus) · heat: 0 = Glut, 1 = Perfection-Plasma.

uniform vec3 base_color: source_color = vec3(1.0, 0.5, 0.15);
uniform vec3 hot_color: source_color = vec3(0.55, 0.85, 1.0);
uniform float intensity = 0.0;
uniform float heat = 0.0;
uniform float t = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 3; i++) {
		v += vnoise(p) * amp;
		p = p * 2.15 + vec2(11.3, 5.7);
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// Flammen zuengeln nach oben: Noise scrollt vertikal, leicht horizontal.
	vec2 uv = vec2(UV.x * 30.0, UV.y * 2.4);
	float n = fbm(uv + vec2(t * 0.4, -t * 3.0));
	float n2 = fbm(uv * 1.9 + vec2(-t * 0.25, -t * 4.2) + 17.0);
	// Unten dichte Glut, oben zerrissen ausfransende Zungen.
	float fire = clamp((n * 0.72 + n2 * 0.48) * 1.7 - UV.y * 1.45, 0.0, 1.0)
			* (1.0 - UV.y * 0.55);
	fire = pow(fire, 1.35);
	// Kern heisser (heller/gelber) als die Raender.
	vec3 col = mix(base_color, vec3(1.0, 0.92, 0.62), fire * 0.65);
	col = mix(col, hot_color, heat);
	float a = fire * clamp(intensity, 0.0, 1.0);
	ALBEDO = col * a * 1.7;
	ALPHA = clamp(a, 0.0, 1.0);
}
