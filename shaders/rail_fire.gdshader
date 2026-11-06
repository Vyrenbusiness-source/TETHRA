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

// Groove-Hooks (vom Aufrufer gesetzt, Default 0 = altes Aussehen):
//  beat_flash 0..1 Licht-Schlag auf dem Beat (schnell abklingend)
//  downbeat   0..1 Taktanfang · music_energy 0..1 Musik-Intensitaet
uniform float beat_flash : hint_range(0.0, 1.0) = 0.0;
uniform float downbeat : hint_range(0.0, 1.0) = 0.0;
uniform float music_energy : hint_range(0.0, 1.0) = 0.0;

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
	// Weiche Flammen: niedrigere Frequenz, Noise scrollt nach oben.
	vec2 uv = vec2(UV.x * 18.0, UV.y * 2.0);
	float n = fbm(uv + vec2(t * 0.3, -t * 2.4));
	float n2 = fbm(uv * 1.5 + vec2(-t * 0.2, -t * 3.2) + 17.0);
	float shape = n * 0.7 + n2 * 0.45;
	// Weicher Verlauf statt hartem Clamp: Zungen laufen sanft aus.
	float fire = smoothstep(0.0, 1.0, clamp(shape * 1.6 - UV.y * 1.3, 0.0, 1.0))
			* (1.0 - UV.y * 0.5);
	fire = pow(fire, 1.2);
	// Glut am Fuss, weicher Ausklang nach oben.
	fire *= smoothstep(1.0, 0.55, UV.y);
	vec3 col = mix(base_color, vec3(1.0, 0.9, 0.6), fire * 0.55);
	col = mix(col, hot_color, heat);
	float pulse = 1.0 + beat_flash * 0.5 + downbeat * 0.25 + music_energy * 0.1;
	float a = fire * clamp(intensity, 0.0, 1.0);
	ALBEDO = col * a * 1.5 * pulse;
	ALPHA = clamp(a, 0.0, 1.0);
}
