shader_type canvas_item;

// Animierter Menue-Hintergrund: dunkler Raum, langsam pulsierende Neon-Ringe
// aus dem Fluchtpunkt + dezente Sterne. Passt zum Tunnel-Look des Gameplays.

uniform vec3 base_color: source_color = vec3(0.06, 0.35, 0.80);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 p = UV - vec2(0.5, 0.46);
	p.x *= 1.78;
	float d = length(p);

	// Ringe, die langsam nach aussen laufen.
	float rings = pow(abs(sin(d * 14.0 - TIME * 0.9)), 24.0);
	float ring_glow = rings * smoothstep(0.05, 0.35, d) * (1.0 - smoothstep(0.55, 0.95, d));

	// Sterne (statisch, leicht flackernd).
	vec2 cell = floor(UV * vec2(160.0, 90.0));
	float star = step(0.985, hash12(cell));
	float tw = 0.5 + 0.5 * sin(TIME * 2.0 + hash12(cell + 7.0) * 6.28);
	float stars = star * tw * 0.5;

	// Vignette + Grundton.
	float vig = 1.0 - smoothstep(0.4, 1.05, d);
	vec3 col = base_color * (ring_glow * 0.55 + 0.035 * vig) + vec3(stars);
	COLOR = vec4(col, 1.0);
}
