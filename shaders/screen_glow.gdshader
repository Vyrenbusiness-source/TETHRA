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

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float d = max(abs(c.x), abs(c.y));
	float edge = smoothstep(0.60, 1.0, d);
	// Brenn-Flacker: mehrere unsynchrone Sinusse wirken wie zuengelnde Glut.
	float flick = 1.0
		+ burn * 0.35 * sin(t * 37.0 + UV.y * 9.0)
		+ burn * 0.22 * sin(t * 61.0 + UV.x * 13.0)
		+ burn * 0.15 * sin(t * 23.0 + (UV.x + UV.y) * 7.0);
	vec3 col = mix(glow_color, burn_color, burn) * edge * intensity * max(flick, 0.0);
	COLOR = vec4(col, edge * intensity * (0.5 + 0.35 * burn));
}
