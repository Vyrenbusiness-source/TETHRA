shader_type canvas_item;

// Bildschirmrand-Glut: ab Combo-Stufen gluehen die Raender in Songfarbe,
// bei hoher Combo "brennt" der Rand (Flacker + Feuerton).
//  intensity 0..1  Grundglut (Combo/Kiai)
//  burn      0..1  Brenn-Anteil (hohe Combo): Flacker + warme Toene
//  t               Zeit in Sekunden (fuer Flacker)

uniform vec3 glow_color: source_color = vec3(0.15, 0.75, 1.0);
uniform vec3 burn_color: source_color = vec3(1.0, 0.45, 0.1);
uniform float intensity = 0.0;
uniform float burn = 0.0;
uniform float t = 0.0;

float ign(vec2 p) {
	// Interleaved-Gradient-Noise als Dither gegen Banding.
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float d = max(abs(c.x), abs(c.y));
	// Weicher Auslauf (smootherstep-artig).
	float e = clamp((d - 0.55) / 0.45, 0.0, 1.0);
	float edge = e * e * e * (e * (e * 6.0 - 15.0) + 10.0);
	// Brenn-Flacker: mehrere unsynchrone Sinusse wirken wie zuengelnde Glut.
	float flick = 1.0
		+ burn * 0.30 * sin(t * 37.0 + UV.y * 9.0)
		+ burn * 0.18 * sin(t * 61.0 + UV.x * 13.0)
		+ burn * 0.12 * sin(t * 23.0 + (UV.x + UV.y) * 7.0);
	vec3 col = mix(glow_color, burn_color, burn) * edge * intensity * max(flick, 0.0);
	float a = edge * intensity * (0.5 + 0.35 * burn);
	float dither = (ign(FRAGCOORD.xy) - 0.5) / 255.0;
	COLOR = vec4(max(col + dither * a, vec3(0.0)), clamp(a + dither * a, 0.0, 1.0));
}
