shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Astro-Nebel v2: Domain-Warped fbm (echte Wolkenwirbel statt Blobs),
// dunkle Staubbaender, diagonales Milchstrassen-Band, eingebauter
// Sternenstaub in zwei Groessenklassen (mit Twinkle) und zentraler
// Abdunklung, damit die Strecke lesbar bleibt.
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
	for (int i = 0; i < 5; i++) {
		v += vnoise(p) * amp;
		p = p * 2.1 + vec2(13.7, 7.3);
		amp *= 0.5;
	}
	return v;
}

// Sternenstaub: pro Zelle max. ein Stern, Helligkeit + Twinkle aus dem Hash.
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
	float twk = 0.72 + 0.28 * sin(tw * (2.0 + 5.0 * b) + r * 40.0);
	float core = exp(-d * d * 90.0);
	// Helle Sterne bekommen feine Kreuz-Spikes (Astro-Foto-Glint).
	float spikes = exp(-(abs(dv.x) + abs(dv.y) * 6.0) * 26.0)
			+ exp(-(abs(dv.y) + abs(dv.x) * 6.0) * 26.0);
	return (core + spikes * 0.35 * b) * (0.35 + 0.65 * b) * twk;
}

void fragment() {
	vec2 uv = UV * vec2(3.4, 1.6) * scale;
	// Domain Warping: der Nebel wirbelt, statt nur zu wabern.
	vec2 q = vec2(fbm(uv + vec2(drift * 0.020, 0.0)),
			fbm(uv + vec2(5.2, 1.3) - vec2(0.0, drift * 0.014)));
	float f1 = fbm(uv + 1.7 * q + vec2(drift * 0.028, drift * 0.008));
	float f2 = fbm(uv * 1.9 - 1.1 * q + 40.0);
	// Dunkle Staubbaender fressen sich durch die hellen Wolken.
	float dust = smoothstep(0.42, 0.72, fbm(uv * 1.45 - q * 1.3 + 90.0));
	// Wolken: dichte Kerne leuchten, Raender verlaufen weich.
	float clouds = smoothstep(0.40, 0.88, f1) * 0.78 + smoothstep(0.52, 0.94, f2) * 0.45;
	clouds *= 1.0 - dust * 0.6;
	// Silberkante: Raender dichter Wolken leuchten fein auf (Astro-Look).
	float rim = smoothstep(0.5, 0.62, f1) * (1.0 - smoothstep(0.62, 0.8, f1));
	clouds += rim * 0.26;
	// Drei-Farb-Verlauf: tiefes Violett -> Songfarbe -> Kiai-Akzente in Kernen.
	vec3 deep = vec3(0.05, 0.03, 0.11);
	vec3 neb = mix(deep, col_a, smoothstep(0.15, 0.8, f1));
	neb = mix(neb, col_b, q.y * smoothstep(0.45, 0.95, f2) * 0.8);
	// Milchstrassen-Band: diagonaler heller Staubguertel.
	float band_d = UV.y - 0.40 - (UV.x - 0.5) * 0.22;
	float band = exp(-band_d * band_d * 34.0);
	vec3 band_col = vec3(0.82, 0.80, 0.95) * band * (0.25 + 0.55 * f2)
			* 0.28 * (1.0 + pulse * 0.7);
	// Randfade des Quads + zentrale Abdunklung (Strecke bleibt lesbar).
	vec2 c = UV * 2.0 - 1.0;
	float vig = (1.0 - smoothstep(0.55, 1.0, abs(c.x))) * (1.0 - smoothstep(0.45, 1.0, abs(c.y)));
	float center = smoothstep(0.12, 0.5, distance(UV, vec2(0.5, 0.62)));
	// Sternenstaub: viele feine + wenige helle.
	float s_small = stars(UV, 210.0, 0.93, drift) * 0.4;
	float s_big = stars(UV + 3.7, 80.0, 0.982, drift) * 0.9;
	vec3 star_col = (vec3(0.75, 0.82, 1.0) * s_small + vec3(0.95, 0.95, 1.0) * s_big)
			* star_amount * vig;
	vec3 col = (neb * clouds * energy + band_col) * vig * (0.45 + 0.55 * center);
	col *= 1.0 + pulse * 0.10;
	ALBEDO = (col * 0.6 + star_col) * alpha_mul;
	ALPHA = clamp(clouds * vig + band * 0.3 + s_small + s_big, 0.0, 1.0) * 0.6 * alpha_mul;
}
