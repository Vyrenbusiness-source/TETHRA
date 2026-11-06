shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Hold als Energiestrahl: weicher Rand, heller Kern, Fluss entlang der Bahn,
// prozedurale Energie-Textur, gerundete Kappen (Kapsel-SDF in Weltmassen).
// UV.x = quer, UV.y = laengs (0 = Kopf/fern, 1 = Schwanz/nah).

uniform vec4 beam_color: source_color = vec4(1.0, 0.62, 0.22, 1.0);
uniform float width = 0.8;
uniform float length_u = 4.0;
uniform float brightness = 0.6;   // Gesamthelligkeit
uniform float flow_speed = 0.8;   // Fluss in Einheiten/s
uniform float pulse = 0.0;        // Puls-Staerke
uniform float desat = 0.0;        // 0 farbig .. 1 grau
uniform float beat = 0.0;         // Atmen 0..1
uniform float flow_pos = 0.0;     // vom Script integrierter Fluss-Offset

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float hw = width * 0.5;
	float p = (UV.x - 0.5) * width;
	float q = (UV.y - 0.5) * length_u;
	float h = max(length_u * 0.5 - hw, 0.0);
	float sd = length(vec2(p, q - clamp(q, -h, h))) - hw;
	float r = clamp(1.0 + sd / hw, 0.0, 2.0);   // 0 Achse .. 1 Rand
	float body = 1.0 - smoothstep(0.55, 1.0, r);   // weicher Rand
	float core = pow(1.0 - clamp(r, 0.0, 1.0), 2.2);

	// Energie-Textur: gestreckte Noise-Baender, fliessen zum Spieler (+q).
	float fl = flow_pos;
	vec2 np = vec2(p / hw * 1.6, (q - fl) * 1.3);
	float n1 = vnoise(np * vec2(1.0, 0.7));
	float n2 = vnoise(np * vec2(2.3, 1.9) + 7.3);
	float tex = n1 * 0.6 + n2 * 0.4;
	float streak = 0.5 + 0.5 * sin((q - fl) * 5.0 + n1 * 3.0);
	float energy = 0.55 + 0.45 * tex * (0.6 + 0.4 * streak);

	float pul = 1.0 + pulse * (0.5 + 0.5 * sin(TIME * 9.0));
	float b = brightness * pul * (1.0 + beat * 0.25);

	vec3 hot = mix(beam_color.rgb, vec3(1.0), 0.65);
	vec3 col = beam_color.rgb * body * energy * 0.9 + hot * core * (0.6 + 0.4 * energy);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), desat);

	ALBEDO = col * b;
	ALPHA = clamp(body * (0.35 + 0.65 * energy) + core, 0.0, 1.0);
}
