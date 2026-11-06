shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Hold-Koerper auf LESBARKEIT ausgelegt (VSRG-Stil):
//  - gleichmaessig deckender Koerper in klarer Hold-Farbe, KEIN Nebel,
//    KEINE Fluss-Animation (flimmert bei hoher Scroll-Geschwindigkeit)
//  - scharfe Seitenkanten (abgerundetes Rechteck-SDF in Weltmassen, AA per
//    fwidth) mit heller Randlinie
//  - deutliche helle Kappe an beiden Enden (Kopfseite liegt unter der Note)
//    mit dunkler Trennfuge zum Koerper
// UV.x = quer, UV.y = laengs. Koerper ist schmaler als die Note (body_frac),
// damit der Kopf als Note klar heraussticht.

uniform vec4 beam_color: source_color = vec4(1.0, 0.62, 0.22, 1.0);
uniform float width = 0.8;
uniform float length_u = 4.0;
uniform float brightness = 1.0;   // 1 normal, ~1.12 gehalten
uniform float desat = 0.0;        // 0 farbig .. 1 grau (losgelassen)
uniform float beat = 0.0;         // Atmen 0..1 (max +2 %)
uniform float body_alpha = 0.94;  // Deckung Koerper
// Alt-Uniforms (ohne Wirkung, nur damit bestehende Aufrufer nicht brechen).
uniform float flow_speed = 0.0;
uniform float pulse = 0.0;
uniform float flow_pos = 0.0;

const float BODY_FRAC = 0.84;  // Koerperbreite relativ zur Quad-Breite
const float CORNER = 0.07;     // Eckradius (Welt)
const float BORDER = 0.055;    // helle Randlinie (Welt)
const float CAP = 0.16;        // Kappenlaenge (Welt)

void fragment() {
	float bhw = width * 0.5 * BODY_FRAC;
	float hl = length_u * 0.5;
	vec2 pq = vec2((UV.x - 0.5) * width, (UV.y - 0.5) * length_u);

	// Abgerundetes Rechteck.
	vec2 dq = abs(pq) - vec2(bhw, hl) + CORNER;
	float sd = length(max(dq, 0.0)) + min(max(dq.x, dq.y), 0.0) - CORNER;
	float aa = max(fwidth(sd), 0.002);
	float inside = 1.0 - smoothstep(-aa, aa, sd);

	// Randlinie entlang der Seiten (scharf, ~1 px AA).
	float border = smoothstep(-BORDER - aa, -BORDER + aa, sd);
	// Kappen an beiden Enden + dunkle Fuge davor.
	float aq = max(fwidth(pq.y), 0.002);
	float from_end = hl - abs(pq.y);
	float cap = 1.0 - smoothstep(CAP - aq, CAP + aq, from_end);
	float seam = 1.0 - smoothstep(0.0, 0.025 + aq, abs(from_end - CAP - 0.02));

	// Koerper: flache Farbe, nur sehr leichte Woelbung quer (+-4 %).
	float across = clamp(abs(pq.x) / bhw, 0.0, 1.0);
	vec3 body = beam_color.rgb * (0.80 - 0.06 * across * across);
	vec3 light = mix(beam_color.rgb, vec3(1.0), 0.5);
	vec3 col = body;
	col = mix(col, light, border);
	col = mix(col, mix(beam_color.rgb, vec3(1.0), 0.6), cap);
	col *= 1.0 - 0.55 * seam * (1.0 - cap);

	col *= brightness * (1.0 + 0.02 * clamp(beat, 0.0, 1.0));
	// Losgelassen: klar grau (Helligkeit vom Farbwert entkoppelt).
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum * 0.62 + 0.06), clamp(desat, 0.0, 1.0));

	float a = mix(body_alpha, 1.0, max(border, cap));
	a *= mix(1.0, 0.8, clamp(desat, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(inside * a, 0.0, 1.0);
}
