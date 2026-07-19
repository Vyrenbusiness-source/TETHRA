shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Prozeduraler Planet auf einem Quad: echtes Kugel-Shading (Normale aus der
// Scheibe), Wolkenbaender mit fbm-Verwirbelung, Terminator + Limb-Darkening,
// schmaler Atmosphaeren-Rand und optionaler geneigter Ring.

uniform vec4 base_col: source_color = vec4(0.72, 0.58, 0.45, 1.0);
uniform vec4 band_col: source_color = vec4(0.45, 0.32, 0.22, 1.0);
uniform vec4 atmo_col: source_color = vec4(0.65, 0.75, 0.95, 1.0);
uniform float band_freq = 9.0;
uniform float seed = 0.0;
uniform float ring_amount = 0.0;
// Sonnenrichtung — wandert ueber die Songdauer (Reise-Beleuchtung).
uniform vec3 light_dir = vec3(-0.55, 0.35, 0.75);
// ECHTE Planeten-Texturen (equirectangular): diffuse + Nachtseiten-Emission
// (Stadtlichter/Lava). use_texture schaltet vom prozeduralen Look um.
uniform float use_texture = 0.0;
// Wolkenschicht fuer Erd-/Ozean-Planeten (driftet ueber die Oberflaeche).
uniform float clouds_amount = 0.0;
uniform sampler2D tex_diffuse: source_color, filter_linear_mipmap;
uniform sampler2D tex_emission: source_color, hint_default_black, filter_linear_mipmap;
uniform float intensity = 1.0;
uniform float t = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// Scheibe belegt 62% des Quads; aussen bleibt Platz fuer den Ring.
	vec2 pp = p / 0.62;
	float r = length(pp);
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	vec3 l = normalize(light_dir);
	if (r < 1.0) {
		float z = sqrt(max(1.0 - r * r, 0.0));
		vec3 n = vec3(pp, z);
		// Oberflaeche: verwirbelte Breitengrad-Baender (Domain Warp) mit
		// Detail-Oktave, Wirbelstuermen und dunkleren Polen.
		float drift = t * 0.012 + seed;
		float warp = fbm(vec2(n.x * 2.6 + drift, n.y * 2.6 + seed * 7.0)) - 0.5;
		float band_pos = n.y + warp * 0.42;
		float stripes = sin(band_pos * band_freq + seed * 13.0) * 0.5 + 0.5;
		stripes = mix(stripes, sin(band_pos * band_freq * 2.3 + 1.7) * 0.5 + 0.5, 0.3);
		float storm = smoothstep(0.55, 0.9,
				fbm(vec2(n.x * 5.5 - drift * 2.0, n.y * 5.5 + seed)));
		float detail = fbm(vec2(n.x * 9.0 + drift * 0.5, n.y * 9.0 + seed * 3.0)) - 0.5;
		vec3 surf = mix(base_col.rgb, band_col.rgb, stripes);
		surf = mix(surf, band_col.rgb * 1.3, storm * 0.4);
		surf *= 1.0 + detail * 0.18;
		// Pole leicht abdunkeln (wirkt sofort planetarer).
		surf *= 0.82 + 0.18 * (1.0 - abs(n.y) * abs(n.y));
		// ECHTE Textur: Kugel-UV (equirectangular), langsame Rotation;
		// die Nachtseite zeigt die Emission (Stadtlichter, Lavastroeme).
		vec3 night = vec3(0.0);
		if (use_texture > 0.5) {
			vec2 tuv = vec2(fract(atan(n.x, n.z) / TAU + t * 0.004 + seed * 0.1),
					acos(clamp(n.y, -1.0, 1.0)) / PI);
			surf = texture(tex_diffuse, tuv).rgb;
			night = texture(tex_emission, tuv).rgb;
			if (clouds_amount > 0.01) {
				float cl = fbm(vec2(tuv.x * 8.0 + t * 0.012, tuv.y * 4.0 + seed));
				cl = smoothstep(0.52, 0.78, cl) * clouds_amount;
				surf = mix(surf, vec3(0.98), cl);
				night = mix(night, vec3(0.0), cl * 0.85);
			}
		}
		// Sonne von schraeg links: Terminator + Limb-Darkening.
		float diff = clamp(dot(n, l), 0.0, 1.0);
		float limb = pow(z, 0.45);
		col = surf * (0.05 + diff) * limb + night * (1.0 - diff) * 0.9 * limb;
		// Warmes Streiflicht ENTLANG des Terminators (Daemmerungszone).
		float term = smoothstep(0.02, 0.18, diff) * (1.0 - smoothstep(0.18, 0.5, diff));
		col += atmo_col.rgb * term * 0.22;
		// Atmosphaeren-Rand, auf der Lichtseite staerker.
		float atmo = smoothstep(0.80, 1.0, r);
		col += atmo_col.rgb * atmo * 0.4 * (0.2 + diff * 0.8);
		alpha = 1.0;
	}
	// Geneigter Ring: vor dem Planeten unten sichtbar, oben dahinter verdeckt.
	if (ring_amount > 0.001) {
		vec2 rp = vec2(p.x, p.y * 3.6 - p.x * 0.55);
		float rr = length(rp);
		float ring = smoothstep(0.70, 0.78, rr) * (1.0 - smoothstep(0.95, 1.02, rr));
		ring *= 0.55 + 0.45 * vnoise(vec2(rr * 40.0, 0.0));
		float behind = (r < 1.0 && rp.y > 0.0) ? 0.0 : 1.0;
		float ra = ring * ring_amount * behind;
		col = mix(col, base_col.rgb * 0.9 + vec3(0.08), clamp(ra, 0.0, 1.0));
		alpha = max(alpha, ra * 0.85);
	}
	ALBEDO = col * intensity;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
