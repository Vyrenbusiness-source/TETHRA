shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Hold-Koerper im VSRG-Skin-Stil (Kopf = Notenring, Koerper laeuft UNTER ihm):
//  - Form = Kapsel (runde Kappen, Radius = halbe Koerperbreite), Breite
//    ~0.62 x Ringdurchmesser -> harmonisch zum Kopf, schmaler als der Ring.
//  - Kopfseite: Kreis-Ausschnitt um die Ringmitte (cut_radius liegt im
//    deckenden Ringband). Der Strahl beginnt dadurch sauber HINTER dem Ring:
//    nichts im Ringkern, nichts ragt vorne heraus, keine Querkante/Naht.
//    Der Ausschnitt wird exakt auf die (hoeher liegende) Ringebene
//    projiziert (Kamerastrahl), damit er bei jeder Perspektive deckt.
//  - Weicher Lichtverlauf Kopf -> Koerper (kein harter Uebergang), gehalten
//    staerker: der Strahl wirkt vom Ring "eingesaugt".
//  - Ende = klare runde Kappe mit heller Kontur, dunkle Aussenkontur wie bei
//    den Noten (Silhouette vor hellem Hintergrund).
// Lokale Quad-Koordinaten (PlaneMesh 1x1, skaliert auf width x length_u).

uniform vec4 beam_color: source_color = vec4(1.0, 0.62, 0.22, 1.0);
uniform float width = 0.8;        // Quad-Breite (Welt)
uniform float length_u = 4.0;     // Kopfmitte .. Ende (Welt)
uniform float quad_len = 4.1;     // Quad-Laenge (length_u + Rand fuer die Kontur)
uniform float body_w = 0.65;      // Koerperbreite (Welt)
uniform float head_sign = 1.0;    // +1: Kopf am +z-Ende des Quads
uniform float cut_radius = 0.46;  // Ausschnitt um die Kopfmitte (0 = aus)
uniform float head_dy = 0.04;     // Ringebene liegt so viel hoeher
uniform float head_glow = 0.18;   // Lichtverlauf am Kopf (gehalten mehr)
uniform float brightness = 1.0;   // 1 normal, ~1.12 gehalten
uniform float desat = 0.0;        // 0 farbig .. 1 grau (losgelassen)
uniform float beat = 0.0;         // Atmen 0..1 (max +2 %)
uniform float body_alpha = 0.92;  // Deckung Koerper
// Alt-Uniforms (ohne Wirkung, nur damit bestehende Aufrufer nicht brechen).
uniform float flow_speed = 0.0;
uniform float pulse = 0.0;
uniform float flow_pos = 0.0;

const float BORDER = 0.045;   // helle Randlinie (Welt)
const float CONTOUR = 0.035;  // dunkle Aussenkontur (Welt)
const float GLOW_LEN = 1.6;   // Laenge des Lichtverlaufs hinter dem Ring

varying vec3 v_local;
varying vec3 v_cam;

void vertex() {
	v_local = VERTEX;
	v_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

// Lokale Quad-Position -> (quer, Abstand von der Kopfmitte) in Weltmassen.
vec2 beam_space(vec3 lp) {
	return vec2(lp.x * width, (0.5 - lp.z * head_sign) * quad_len);
}

void fragment() {
	vec2 p = beam_space(v_local);
	float r = body_w * 0.5;
	float len = length_u;

	// Kapsel von der Kopfmitte bis zum Ende.
	float sc = clamp(p.y, r, max(len - r, r));
	float sd = length(vec2(p.x, p.y - sc)) - r;
	float aa = max(fwidth(sd), 0.002);
	float inside = 1.0 - smoothstep(-aa, aa, sd);
	float halo = 1.0 - smoothstep(CONTOUR - aa, CONTOUR + aa, sd);

	// Kopf-Ausschnitt in der Ringebene (Kamerastrahl -> Ebene y = head_dy).
	float vis = 1.0;
	if (cut_radius > 0.0) {
		float k = (v_cam.y - head_dy) / max(v_cam.y - v_local.y, 0.0001);
		vec3 hit = v_cam + (v_local - v_cam) * k;
		float dh = length(beam_space(hit));
		float ah = max(fwidth(dh), 0.002);
		vis = smoothstep(cut_radius - ah, cut_radius + ah, dh);
	}

	// Koerper: flache Farbe, sanfte Woelbung quer.
	float across = clamp(abs(p.x) / r, 0.0, 1.0);
	vec3 body = beam_color.rgb * (0.78 - 0.10 * across * across);
	vec3 light = mix(beam_color.rgb, vec3(1.0), 0.45);

	// Lichtverlauf direkt hinter dem Ring (weich, keine Kante).
	float from_head = max(p.y - cut_radius, 0.0);
	float g = exp(-from_head / (GLOW_LEN * 0.45)) * (1.0 - 0.6 * across * across);
	body = mix(body, light, clamp(head_glow * g * 2.2, 0.0, 0.85));

	// Helle Randlinie entlang der gesamten Kontur (Seiten + Endkappe).
	float border = smoothstep(-BORDER - aa, -BORDER + aa, sd);
	vec3 col = mix(body, light, border);
	// Endkappe: Innenflaeche leicht aufgehellt, radial weich.
	float tail_c = max(len - r, r);
	float in_tail = step(tail_c, p.y) * (1.0 - smoothstep(0.0, r, length(vec2(p.x, p.y - tail_c))));
	col = mix(col, light, 0.18 * in_tail * (1.0 - border));

	col *= brightness * (1.0 + 0.02 * clamp(beat, 0.0, 1.0));
	// Losgelassen: klar grau (Helligkeit vom Farbwert entkoppelt).
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum * 0.62 + 0.06), clamp(desat, 0.0, 1.0));

	// Dunkle Aussenkontur (Notenfarbe abgedunkelt, halbtransparent).
	vec3 edge_col = beam_color.rgb * 0.12;
	float a_body = mix(body_alpha, 1.0, border);
	a_body *= mix(1.0, 0.8, clamp(desat, 0.0, 1.0));
	float a_edge = (halo - inside) * 0.45;
	float a = inside * a_body + a_edge;
	vec3 pc = col * inside * a_body + edge_col * a_edge;
	ALBEDO = pc / max(a, 0.001);
	ALPHA = clamp(a * vis, 0.0, 1.0);
}
