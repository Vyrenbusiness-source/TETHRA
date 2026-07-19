shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Huebsche Note-Scheibe auf einem Quad (UV-zentriert):
//  - Kern mit radialem Verlauf (dunkler innen, satter zum Rand)
//  - heller Rim-Ring (rim_boost blitzt im Klick-Fenster auf)
//  - weicher additiver Aussen-Halo
// fill_alpha 0.0 macht daraus einen reinen Ring (Lande-Socket / Schockwelle).

uniform vec4 base_color: source_color = vec4(0.15, 0.75, 1.0, 1.0);
uniform vec4 rim_color: source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float fill_alpha = 0.85;
uniform float rim_boost = 1.0;
uniform float halo_strength = 0.8;
uniform float master_alpha = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);

	// Kern (bis d=0.86): Verlauf von dunkel nach satt.
	float core_mask = 1.0 - smoothstep(0.82, 0.86, d);
	float grad = mix(0.28, 1.0, smoothstep(0.0, 0.82, d));
	vec3 core = base_color.rgb * grad * 1.6;

	// Rim-Ring (0.86..0.98).
	float ring = smoothstep(0.84, 0.90, d) * (1.0 - smoothstep(0.96, 1.0, d));
	vec3 rim = rim_color.rgb * ring * (1.6 + rim_boost * 2.2);

	// Aussen-Halo (weich abfallend ab dem Rand).
	float halo = exp(-(max(d - 0.98, 0.0)) * 6.0) * step(0.98, d);
	vec3 halo_col = base_color.rgb * halo * halo_strength * (1.0 + rim_boost);

	vec3 col = core * fill_alpha + rim + halo_col;
	float a = max(max(core_mask * fill_alpha, ring), halo * halo_strength * 0.8);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * master_alpha;
}
