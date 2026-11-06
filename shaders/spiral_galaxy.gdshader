shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// FERNE SPIRALGALAXIE: leuchtender Kern, zwei log-Spiralarme mit
// Staubadern und Sternhaufen-Koernung, rotiert unmerklich langsam.
// Weiche Kanten, Dither gegen Banding.

uniform vec3 col_core: source_color = vec3(1.0, 0.92, 0.78);
uniform vec3 col_arm: source_color = vec3(0.55, 0.68, 1.0);
uniform float intensity = 0.5;
uniform float t = 0.0;
// Form-Varianten pro Kapitel: Neigung (y-Stauchung), Armzahl, Verdrillung.
uniform float squash = 1.55;
uniform float arm_n = 2.0;
uniform float twist = 5.5;
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
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x),
			mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = rot * p * 2.1 + vec2(9.7, 3.1);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y *= squash;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float spin = t * 0.045;
	// Zwei log-Spiralarme; leichte Phasenverschiebung durch Noise = organisch.
	float ph = ang * arm_n - log(max(r, 0.02)) * twist + spin
			+ (fbm(p * 2.2 + 3.0) - 0.5) * 1.1;
	float arm = sin(ph);
	float arms = smoothstep(-0.1, 0.95, arm) * smoothstep(1.0, 0.18, r);
	// Staubadern: dunkle Kante auf der Innenseite jedes Arms.
	float lane = smoothstep(-0.55, -0.1, arm) * (1.0 - smoothstep(-0.1, 0.25, arm));
	float n = fbm(p * 6.0 + vec2(t * 0.01, 0.0));
	float n2 = fbm(p * 14.0 - vec2(0.0, t * 0.006));
	arms *= 0.4 + 0.6 * n;
	arms *= 1.0 - lane * 0.45 * smoothstep(0.1, 0.5, r);
	// Sternhaufen: feines helles Korn, nur in den Armen.
	float knots = smoothstep(0.62, 0.9, n2) * arms * 0.5;
	float core = exp(-r * r * 20.0) * 1.5;
	float haze = exp(-r * r * 3.2) * 0.26;
	vec3 col = col_core * (core + knots * 0.4) + col_arm * (arms + haze);
	float a = (core + arms + haze + knots) * intensity;
	float edge = smoothstep(1.0, 0.55, r);
	vec3 outc = col * intensity * 1.3 * (1.0 + world_pulse * 0.2);
	float dn = hash12(FRAGCOORD.xy) + hash12(FRAGCOORD.xy + 17.31) - 1.0;
	outc += vec3(dn) * (1.5 / 255.0) * step(0.0005, a);
	ALBEDO = max(outc, vec3(0.0));
	ALPHA = clamp(a, 0.0, 0.85) * edge;
}
