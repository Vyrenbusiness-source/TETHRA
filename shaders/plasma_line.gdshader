shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Plasma-Band an der Abfanglinie (SkillFx, Stufe 2) und Aura dahinter
// (Stufe 3). PlaneMesh am Boden: UV.x quer ueber die Bahnen,
// UV.y = 0 hinten (Richtung Noten), 1 vorne (Richtung Kamera).
//  mode = 0: schmales Band mit fliessenden Plasma-Faeden.
//  mode = 1: weiche Aura, die von der Linie zur Kamera hin ausblendet.

uniform vec3 color: source_color = vec3(0.3, 0.85, 1.0);
uniform vec3 color2: source_color = vec3(1.0, 0.45, 0.85);
uniform float intensity = 0.0;
uniform float env = 0.0;
uniform float flow = 0.0;        // wird von GDScript hochgezaehlt (Tempo-gekoppelt)
uniform float prism = 0.0;
uniform float mode = 0.0;

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
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * amp;
		p = p * 2.07 + vec2(13.1, 7.3);
		amp *= 0.5;
	}
	return v;
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	float x = UV.x;
	float y = UV.y;
	float edge_x = smoothstep(0.0, 0.10, x) * smoothstep(1.0, 0.90, x);
	float a;
	vec3 c;

	if (mode < 0.5) {
		// Domain-Warp: zwei gegenlaeufige Stroemungen verdrillen sich zu Faeden.
		vec2 q = vec2(x * 9.0, y * 2.2);
		float w = fbm(q * 0.7 + vec2(flow * 0.35, -flow * 0.12));
		float n1 = fbm(q + vec2(-flow * 0.9, 0.0) + w * 1.6);
		float n2 = fbm(q * 1.35 + vec2(flow * 0.7, flow * 0.2) + 31.0 - w);
		float ridge1 = 1.0 - abs(n1 * 2.0 - 1.0);
		float ridge2 = 1.0 - abs(n2 * 2.0 - 1.0);
		float fil = pow(ridge1, 7.0) * 0.9 + pow(ridge2, 9.0) * 0.6;
		float dy = (y - 0.5) * 2.0;
		float band = exp(-dy * dy * 3.2);
		float core = exp(-dy * dy * 28.0);
		a = (fil * band * 1.6 + core * 0.4 + band * 0.07) * edge_x;
		a *= 0.88 + env * 0.12;
		c = mix(color, color2, clamp(ridge2 * 0.6 + w * 0.3 - 0.2, 0.0, 1.0) * 0.55);
		c = mix(c, vec3(1.0), clamp(fil * core, 0.0, 1.0) * 0.5);
	} else {
		// Aura: an der Linie am staerksten, zur Kamera hin weich weg.
		float fall = pow(1.0 - y, 2.6) * smoothstep(0.0, 0.3, y);
		float n = fbm(vec2(x * 4.0 - flow * 0.15, y * 3.0 + flow * 0.1));
		a = fall * (0.55 + 0.45 * n) * edge_x * 0.55;
		c = mix(color, color2, n * 0.4);
	}

	if (prism > 0.001) {
		float hue = fract(x * 0.75 + flow * 0.02);
		c = mix(c, hsv2rgb(vec3(hue, 0.55, 1.0)), clamp(prism, 0.0, 1.0) * 0.6);
	}

	a *= clamp(intensity, 0.0, 1.0);
	ALBEDO = c * a * 3.2;
	ALPHA = clamp(a, 0.0, 1.0);
}
