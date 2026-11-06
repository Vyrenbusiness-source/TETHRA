shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Note als flacher 2D-Kreis auf einem Quad (UV-zentriert), auf LESBARKEIT
// bei hoher Scroll-Geschwindigkeit ausgelegt:
//  - voll deckender, heller Kern (kaum Verlauf, Mitte nie dunkel)
//  - dicker, voll deckender Rim-Ring mit klarer AA-Kante (fwidth)
//  - feine dunkle Trennlinie Kern/Ring + dunkle Aussenkontur -> harte
//    Silhouette auch vor hellem Hintergrund, KEIN weicher Halo nach aussen
// fill_alpha 0.0 macht daraus einen reinen Ring (Lande-Socket).
// rim_boost: Lock-On-Aufhellung des Rings (gedeckelt, kein Bloom-Schleier).
// beat 0..1: Atmen max +2 % Helligkeit.
// approach 0..1: bewusst OHNE Wirkung auf Helligkeit/Schaerfe (ferne Noten
// bleiben gleich hell und scharf); Uniform bleibt fuer die Aufrufer erhalten.
// halo_strength: nur noch Staerke der dunklen Kontur (0 = keine).
// min_facing: Ferne Noten liegen sehr flach zur Kamera und kollabieren sonst
// zu duennen Strichen. Der Vertex-Shader kippt das Quad deshalb nur so weit
// zur Kamera, dass sein Blickwinkel-Sinus >= min_facing ist (max 35 Grad).
// An der Abfanglinie (steiler Blick) kippt nichts -> landet exakt aufs Pad.
// Kamera-zugewandte Quads (andere Modi) bleiben unveraendert.
uniform float min_facing: hint_range(0.0, 1.0) = 0.56;

uniform vec4 base_color: source_color = vec4(0.15, 0.75, 1.0, 1.0);
uniform vec4 rim_color: source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float fill_alpha = 0.85;
uniform float rim_boost = 1.0;
uniform float halo_strength = 0.8;
uniform float master_alpha = 1.0;
uniform float beat: hint_range(0.0, 1.0) = 0.0;
uniform float approach: hint_range(0.0, 1.0) = 0.0;

const float R_CORE = 0.70;   // Kern bis hier, danach Ring
const float R_RING = 0.93;   // Aussenkante Ring
const float R_EDGE = 0.995;  // Aussenkante dunkle Kontur

vec3 rotate_axis(vec3 v, vec3 k, float a) {
	return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 n = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - center);
	float g = dot(n, v);
	if (g < 0.0) {
		n = -n;
		g = -g;
	}
	float tilt = clamp(asin(min_facing) - asin(clamp(g, 0.0, 1.0)), 0.0, radians(35.0));
	vec3 axis = cross(n, v);
	float al = length(axis);
	if (tilt > 0.0001 && al > 0.0001) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		wp = center + rotate_axis(wp - center, axis / al, tilt);
		VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	// Pixelbreite im Radialraum: Kante genau ~1 px weich, auch ganz in der Ferne.
	float aa = max(fwidth(d), 0.001);

	// Masken mit harten, AA-geglaetteten Kanten.
	float in_core = 1.0 - smoothstep(R_CORE - aa, R_CORE + aa, d);
	float in_ring = 1.0 - smoothstep(R_RING - aa, R_RING + aa, d);
	float in_all = 1.0 - smoothstep(R_EDGE - aa, R_EDGE, d);
	float ring = in_ring - in_core;
	float outline = in_all - in_ring;

	// Kern: satte Notenfarbe, nur leichter Verlauf (Mitte 88 %).
	float grad = mix(0.88, 1.0, smoothstep(0.0, R_CORE, d));
	vec3 core = base_color.rgb * grad * 0.92;
	// Feine dunkle Trennlinie direkt innen am Ring (klare Innenkante).
	float sep = 1.0 - smoothstep(0.0, 0.035 + aa, abs(d - (R_CORE - 0.03)));
	core *= 1.0 - 0.45 * sep;

	// Ring: hell, deckend; Lock-On hebt nur leicht an (max ~1.15).
	float boost = clamp(rim_boost, 0.0, 1.0);
	vec3 rim = rim_color.rgb * (1.0 + 0.15 * boost);

	// Dunkle Kontur: Notenfarbe stark abgedunkelt, nicht reines Schwarz.
	vec3 edge_col = base_color.rgb * 0.12;
	float edge_a = clamp(halo_strength, 0.0, 1.0) * 0.6 + 0.25;

	float fill = clamp(fill_alpha / 0.7, 0.0, 1.0);
	float ea = edge_a * max(fill, 0.4);
	// Vormultiplizierte Farbe / Deckung -> saubere AA-Kanten ohne Saum.
	vec3 pc = core * in_core * fill + rim * ring + edge_col * outline * ea;
	float a = in_core * fill + ring + outline * ea;
	// Atmen: max +2 % Helligkeit.
	pc *= 1.0 + 0.02 * clamp(beat, 0.0, 1.0);
	ALBEDO = pc / max(a, 0.001);
	ALPHA = clamp(a, 0.0, 1.0) * master_alpha;
}
