shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// TETHRA-Note: abgerundete RAUTE (45-Grad-Quadrat) — bewusst kein osu-Kreis.
//  - dunkler Kern (Lesbarkeit auf jedem Hintergrund)
//  - leuchtender Rauten-Rand (rim_boost = Fenster-Flash / Musik)
//  - weicher Aussen-Halo
// Auch fuer Sockets (fill_alpha 0, duenner) und Schockwellen nutzbar.

uniform vec4 base_color: source_color = vec4(0.15, 0.75, 1.0, 1.0);
uniform float rim_boost = 0.0;
uniform float fill_alpha = 0.62;
uniform float thickness = 0.10;
uniform float master_alpha = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// Diamant-SDF mit leicht abgerundeten Spitzen.
	float d = (abs(p.x) + abs(p.y)) * 0.92 + length(p) * 0.08 - 0.84;

	float ring = 1.0 - smoothstep(thickness * 0.5, thickness * 0.5 + 0.05, abs(d));
	float inside = 1.0 - smoothstep(-0.05, 0.02, d);
	float halo = exp(-max(d, 0.0) * 6.5) * step(0.0, d) * 0.6;

	// Bewusst gedimmt: grelle Raender tun in den Augen weh und fressen
	// die Lesbarkeit (Nutzer-Feedback).
	vec3 dark = vec3(0.012, 0.012, 0.025);
	vec3 rim_col = base_color.rgb * (1.1 + rim_boost * 1.3);
	float lit = clamp(ring + halo * 0.6, 0.0, 1.0);
	vec3 col = mix(dark, rim_col, lit);

	float a = max(ring, max(inside * fill_alpha, halo));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * master_alpha;
}
