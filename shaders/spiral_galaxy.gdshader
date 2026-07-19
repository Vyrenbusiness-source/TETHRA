shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// FERNE SPIRALGALAXIE: leuchtender Kern, zwei log-Spiralarme mit
// Staub-Struktur, rotiert unmerklich langsam. Das Astro-Wahrzeichen.

uniform vec3 col_core: source_color = vec3(1.0, 0.92, 0.78);
uniform vec3 col_arm: source_color = vec3(0.55, 0.68, 1.0);
uniform float intensity = 0.5;
uniform float t = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x),
			mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = p * 2.1 + vec2(9.7, 3.1);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// Leicht gekippte Scheibe (elliptisch = 3D-Anmutung).
	p.y *= 1.55;
	float r = length(p);
	float ang = atan(p.y, p.x);
	// Zwei log-Spiralarme, traege rotierend.
	float arm = sin(ang * 2.0 - log(max(r, 0.02)) * 5.5 + t * 0.045);
	float arms = smoothstep(0.15, 0.95, arm) * smoothstep(1.0, 0.22, r);
	// Staub-Struktur in den Armen.
	float n = fbm(p * 5.0 + vec2(t * 0.01, 0.0));
	arms *= 0.45 + 0.55 * n;
	// Kern + weicher Halo.
	float core = exp(-r * r * 16.0) * 1.7;
	float haze = exp(-r * r * 3.0) * 0.30;
	vec3 col = col_core * core + col_arm * (arms + haze);
	float a = (core + arms + haze) * intensity;
	ALBEDO = col * intensity * 1.4;
	ALPHA = clamp(a, 0.0, 0.85) * smoothstep(1.0, 0.72, r);
}
