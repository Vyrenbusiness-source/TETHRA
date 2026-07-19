shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Slider-Roehre als Energie-Leitbahn (kein osu-Balken):
//  - dunkle, halbtransparente Fuellung in der Mitte (Kontrast-Kern)
//  - zwei helle Kanten-Baender (Rand) die auf dem Beat aufblitzen
//  - fliessende Energie-Streifen entlang der Bahn (flow)
// UV.x = Laengsrichtung (0..1), UV.y = Querrichtung (0..1, Mitte 0.5).

uniform vec4 body_color: source_color = vec4(0.15, 0.75, 1.0, 1.0);
uniform vec4 edge_color: source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float master_alpha = 1.0;
uniform float beat = 0.0;      // 0..1 Beat-Puls (Kanten heller)
uniform float flow = 0.0;      // fortlaufender Fluss-Offset
uniform float energy = 1.0;    // globale Helligkeit (Bass/Kiai)

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;      // 0 Mitte .. 1 Rand
	// Kanten-Baender.
	float edge = smoothstep(0.55, 0.92, across);
	// Fuellung faellt zum Rand hin ab, bleibt aber sichtbar (Kontrast-Kern).
	float fill = 1.0 - smoothstep(0.86, 1.0, across);

	// Fliessende Streifen entlang der Bahn.
	float stripe = 0.5 + 0.5 * sin((UV.x * 26.0) - flow);
	stripe = pow(stripe, 3.0);

	vec3 core = body_color.rgb * (0.28 + stripe * 0.35);
	vec3 rim = edge_color.rgb * edge * (0.9 + beat * 1.1);
	vec3 col = (core * fill + rim) * energy;

	float a = max(fill * 0.5, edge) ;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * master_alpha;
}
