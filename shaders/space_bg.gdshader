shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Astro-Nebel v3: mehrschichtiges, domain-warptes fbm (zwei Warp-Stufen),
// weiche Farbverlaeufe aus den Song-Uniforms, dunkle Staubadern, feiner
// Staub (Korn) in mehreren Groessenklassen, Milchstrassen-Band, Tiefe ueber
// zwei gegenlaeufig driftende Schichten (Parallax) und Dither-Noise gegen
// Banding. Mitte hinter der Strecke bleibt dunkel (Noten-Lesbarkeit).
//  col_a: Songfarbe · col_b: Kiai/Komplementaer · energy: Bass/Kiai
//  scale/alpha_mul/star_amount: fuer Parallaxe-Layer.

uniform vec3 col_a: source_color = vec3(0.10, 0.45, 0.95);
uniform vec3 col_b: source_color = vec3(0.85, 0.25, 0.60);
uniform float drift = 0.0;
uniform float energy = 0.6;
uniform float scale = 1.0;
uniform float alpha_mul = 1.0;
uniform float star_amount = 1.0;
uniform float pulse = 0.0;

// Groove-Hooks (vom Aufrufer gesetzt, Default 0 = altes Aussehen):
//  beat_flash 0..1 Licht-Schlag auf dem Beat (schnell abklingend)
//  downbeat   0..1 Taktanfang · music_energy 0..1 Musik-Intensitaet
uniform float beat_flash : hint_range(0.0, 1.0) = 0.0;
uniform float downbeat : hint_range(0.0, 1.0) = 0.0;
uniform float music_energy : hint_range(0.0, 1.0) = 0.0;
// WELT-PULS: gemeinsame Beat-Huellkurve der ganzen Umgebung (Attack auf
// dem Schlag, ~180 ms Decay) — Himmel, Galaxien, Planeten atmen als eines.
uniform float world_pulse = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Rotation pro Oktave bricht das Gitter auf (keine achsenparallelen Falten).
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.55;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += vnoise(p) * amp;
		p = rot * p * 2.03 + vec2(13.7, 7.3);
		amp *= 0.5;
	}
	return v;
}

// Sterne: pro Zelle max. ein Stern, weicher Kern, leises Twinkle.
float stars(vec2 uv, float n, float thresh, float tw) {
	vec2 g = floor(uv * n);
	vec2 f = fract(uv * n);
	float r = hash12(g);
	if (r < thresh) {
		return 0.0;
	}
	vec2 sp = vec2(hash12(g + 11.0), hash12(g + 27.0)) * 0.6 + 0.2;
	vec2 dv = f - sp;
	float d = length(dv);
	float b = (r - thresh) / (1.0 - thresh);
	float twk = 0.8 + 0.2 * sin(tw * (1.5 + 3.0 * b) + r * 40.0);
	float core = exp(-d * d * 110.0);
	float spikes = exp(-(abs(dv.x) + abs(dv.y) * 7.0) * 30.0)
			+ exp(-(abs(dv.y) + abs(dv.x) * 7.0) * 30.0);
	return (core + spikes * 0.28 * b) * (0.3 + 0.7 * b) * twk;
}

void fragment() {
	vec2 uv = UV * vec2(3.4, 1.6) * scale;
	// Zwei Tiefenschichten driften gegenlaeufig und verschieden schnell.
	vec2 uv_far = uv * 0.8 + vec2(drift * 0.006, 0.0);
	vec2 uv_near = uv * 1.25 - vec2(drift * 0.014, drift * 0.004);

	// Erste Warp-Stufe (grosse Wirbel) ...
	vec2 q = vec2(fbm(uv + vec2(drift * 0.020, 0.0)),
			fbm(uv + vec2(5.2, 1.3) - vec2(0.0, drift * 0.014)));
	// ... zweite Stufe verwirbelt das Ergebnis nochmals (Filamente).
	vec2 r2 = vec2(fbm(uv + 2.0 * q + vec2(1.7, 9.2) + drift * 0.010),
			fbm(uv + 2.0 * q + vec2(8.3, 2.8) - drift * 0.008));
	float f1 = fbm(uv + 1.9 * r2 + vec2(drift * 0.028, drift * 0.008));
	float f2 = fbm(uv * 1.9 - 1.1 * q + 40.0);
	float f3 = fbm(uv_far * 1.3 + r2 * 1.2 + 71.0);
	float f4 = fbm(uv_near * 1.6 - q * 0.9 + 17.0);

	// Staubadern: fadendunkle Gaenge, weich ausgeblendet.
	float dust = smoothstep(0.40, 0.74, fbm(uv * 1.45 - r2 * 1.3 + 90.0));
	float lanes = smoothstep(0.46, 0.5, f4) * (1.0 - smoothstep(0.5, 0.58, f4));
	float absorb = 1.0 - dust * 0.55 - lanes * 0.18;

	// Wolkenkoerper: weiche Verlaeufe, nirgends harte Kanten.
	float body = smoothstep(0.34, 0.92, f1) * 0.66
			+ smoothstep(0.46, 0.96, f2) * 0.34
			+ smoothstep(0.40, 0.95, f3) * 0.22;
	body *= absorb;
	// Silberkante an Wolkenraendern, dezent.
	float rim = smoothstep(0.48, 0.60, f1) * (1.0 - smoothstep(0.60, 0.82, f1));
	body += rim * 0.15;

	// Farbverlauf: tiefes Indigo -> Songfarbe -> Kiai-Akzent, plus eine
	// leichte Ton-in-Ton-Aufhellung (kein Neon).
	vec3 deep = vec3(0.035, 0.025, 0.09);
	vec3 neb = mix(deep, col_a, smoothstep(0.12, 0.85, f1));
	neb = mix(neb, col_a * 1.15 + vec3(0.03, 0.02, 0.05), smoothstep(0.5, 0.95, f3) * 0.4);
	neb = mix(neb, col_b, r2.y * smoothstep(0.42, 0.95, f2) * 0.75);

	// Milchstrassen-Band: diagonal, mit Staubstruktur.
	float band_d = UV.y - 0.40 - (UV.x - 0.5) * 0.22;
	float band = exp(-band_d * band_d * 30.0);
	float band_tex = 0.25 + 0.75 * smoothstep(0.3, 0.8, f2) * (1.0 - dust * 0.7);
	vec3 band_col = vec3(0.80, 0.80, 0.96) * band * band_tex
			* 0.26 * (1.0 + pulse * 0.6);

	// Randfade des Quads + zentrale Abdunklung (Strecke bleibt lesbar).
	vec2 c = UV * 2.0 - 1.0;
	float vig = (1.0 - smoothstep(0.55, 1.0, abs(c.x))) * (1.0 - smoothstep(0.45, 1.0, abs(c.y)));
	float center = smoothstep(0.12, 0.5, distance(UV, vec2(0.5, 0.62)));

	// Feiner Sternenstaub in drei Groessenklassen.
	float s_dust = stars(UV + 1.3, 340.0, 0.945, drift * 0.6) * 0.22;
	float s_small = stars(UV, 210.0, 0.93, drift) * 0.38;
	float s_big = stars(UV + 3.7, 80.0, 0.982, drift) * 0.85;
	vec3 star_col = (vec3(0.75, 0.82, 1.0) * (s_small + s_dust) + vec3(0.95, 0.94, 1.0) * s_big)
			* star_amount * vig;

	vec3 col = (neb * body * energy + band_col) * vig * (0.45 + 0.55 * center);
	col *= 1.0 + pulse * 0.10;
	// Nebel hebt auf Downbeats ganz leicht an.
	col *= 1.0 + downbeat * 0.10 + beat_flash * 0.03 + music_energy * 0.05;

	// Dither: +-0.5 LSB triangulaeres Rauschen bricht Banding in dunklen Verlaeufen.
	float dn = hash12(FRAGCOORD.xy) + hash12(FRAGCOORD.xy + 17.31) - 1.0;
	vec3 outc = (col * 0.6 + star_col) * alpha_mul * (1.0 + world_pulse * 0.17);
	outc += vec3(dn) * (1.5 / 255.0) * step(0.0005, dot(outc, vec3(1.0)));
	ALBEDO = max(outc, vec3(0.0));
	ALPHA = clamp(body * vig + band * 0.3 + s_small + s_big + s_dust, 0.0, 1.0) * 0.6 * alpha_mul;
}
