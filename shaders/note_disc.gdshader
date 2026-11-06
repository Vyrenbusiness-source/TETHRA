shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Flacher 2D-Ring auf einem Quad (UV-zentriert):
//  - Kern mit radialem Verlauf + dezentem Innen-Glow
//  - heller Rim-Ring (rim_boost blitzt im Klick-Fenster auf), AA ueber fwidth
//  - feiner innerer Glanzring
//  - weicher additiver Aussen-Halo
// fill_alpha 0.0 macht daraus einen reinen Ring (Lande-Socket / Schockwelle).
// beat 0..1: kaum merkliches Atmen (max +4% Helligkeit).
// approach 0..1: Ring wird zur Linie hin minimal schaerfer.

uniform vec4 base_color: source_color = vec4(0.15, 0.75, 1.0, 1.0);
uniform vec4 rim_color: source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float fill_alpha = 0.85;
uniform float rim_boost = 1.0;
uniform float halo_strength = 0.8;
uniform float master_alpha = 1.0;
uniform float beat: hint_range(0.0, 1.0) = 0.0;
uniform float approach: hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	// Pixelbreite im Radialraum fuer sauberes AA; approach schaerft minimal.
	float aa = max(fwidth(d), 0.0005) * mix(1.4, 1.0, clamp(approach, 0.0, 1.0));
	float soft = mix(0.035, 0.02, clamp(approach, 0.0, 1.0));

	// Kern (bis d=0.86): Verlauf von dunkel nach satt.
	float core_mask = 1.0 - smoothstep(0.86 - aa * 1.5, 0.86 + aa, d);
	float grad = mix(0.28, 1.0, smoothstep(0.0, 0.82, d));
	vec3 core = base_color.rgb * grad * 1.6;
	// Dezenter Innen-Glow: leichte Aufhellung kurz vor dem Rim.
	float inner_glow = exp(-pow((d - 0.80) / 0.14, 2.0)) * 0.22;
	core += base_color.rgb * inner_glow;

	// Rim-Ring (0.86..0.98) mit AA-Kanten.
	float r_in = smoothstep(0.86 - soft - aa, 0.86 + soft + aa, d);
	float r_out = 1.0 - smoothstep(0.98 - soft - aa, 0.98 + soft + aa, d);
	float ring = clamp(r_in * r_out, 0.0, 1.0);
	vec3 rim = rim_color.rgb * ring * (1.6 + rim_boost * 2.2);

	// Feiner innerer Glanzring knapp innerhalb des Rims.
	float shine = (1.0 - smoothstep(0.0, 0.012 + aa, abs(d - 0.76))) * 0.35;
	vec3 shine_col = mix(base_color.rgb, rim_color.rgb, 0.7) * shine * fill_alpha;

	// Aussen-Halo (weich abfallend ab dem Rand).
	float halo = exp(-(max(d - 0.98, 0.0)) * 6.0) * step(0.98, d);
	vec3 halo_col = base_color.rgb * halo * halo_strength * (1.0 + rim_boost);

	vec3 col = core * fill_alpha * core_mask + shine_col + rim + halo_col;
	// Atmen: max +4% Helligkeit.
	col *= 1.0 + 0.04 * clamp(beat, 0.0, 1.0);
	float a = max(max(core_mask * fill_alpha, ring), halo * halo_strength * 0.8);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * master_alpha;
}
