shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Polarlicht-Vorhaenge ueber dem Horizont: feine, senkrechte Strahlen
// (Rays) unter weich wehenden Vorhaengen, helle untere Kante, nach oben
// ausfransend. Songfarben, atmet sanft mit dem Beat. Kein Flackern.

uniform vec3 col_a: source_color = vec3(0.2, 0.9, 0.6);
uniform vec3 col_b: source_color = vec3(0.4, 0.5, 1.0);
uniform float drift = 0.0;
uniform float pulse = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	// Vorhangform: langsame Welle verbiegt die x-Achse (Falten).
	float fold = vnoise(vec2(uv.x * 2.4 + drift * 0.05, drift * 0.02)) - 0.5;
	float x = uv.x + fold * 0.18 * uv.y;
	float wave = vnoise(vec2(x * 6.0 + drift * 0.16, drift * 0.05));
	float wave2 = vnoise(vec2(x * 13.0 - drift * 0.11, 3.7 + drift * 0.04));
	float curtain = smoothstep(0.2, 0.8, wave * 0.7 + wave2 * 0.3);
	// Feine Strahlen: hochfrequent in x, in y gestreckt, langsam wandernd.
	float rays = vnoise(vec2(x * 70.0 + drift * 0.07, uv.y * 1.6));
	rays = mix(0.55, 1.0, smoothstep(0.25, 0.85, rays));
	// Untere Kante hell, oben ausfransend.
	float vert = pow(uv.y, 1.9);
	float base = curtain * vert * rays;
	vec3 col = mix(col_a, col_b, uv.y * 0.85 + wave2 * 0.25) * base;
	col *= 0.5 + pulse * 0.4;
	float sx = 1.0 - smoothstep(0.5, 1.0, abs(uv.x * 2.0 - 1.0));
	vec3 outc = col * sx * 0.45;
	float dn = hash12(FRAGCOORD.xy) + hash12(FRAGCOORD.xy + 17.31) - 1.0;
	outc += vec3(dn) * (1.0 / 255.0) * step(0.0005, base * sx);
	ALBEDO = max(outc, vec3(0.0));
	ALPHA = clamp(base * sx, 0.0, 1.0) * 0.32;
}
