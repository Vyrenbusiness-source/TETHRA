shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Spurlicht: weicher Streifen von der Abfanglinie nach hinten (Quad auf der
// Strasse, UV.y: 0 fern, 1 Linie). Perspektive ergibt sich aus der Kamera.
// Alpha ist hart auf max_alpha begrenzt: dezent, nie heller als die Noten.

uniform vec4 lane_color: source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float intensity = 0.0;   // 0..1 Gesamtstaerke (Fade beim Loslassen)
uniform float beat = 0.0;        // 0..1 Takt-Huellkurve
uniform float max_alpha = 0.18;
uniform float reach = 0.55;      // Anteil der Quad-Laenge, der leuchtet

void fragment() {
	float along = 1.0 - UV.y;                       // 0 an der Linie, 1 fern
	float fade = pow(clamp(1.0 - along / reach, 0.0, 1.0), 1.6);
	float x = abs(UV.x - 0.5) * 2.0;                // 0 Mitte, 1 Rand
	// Streifen verjuengt sich nach hinten, weiche Kanten.
	float half_w = mix(1.0, 0.45, clamp(along / reach, 0.0, 1.0));
	float side = 1.0 - smoothstep(half_w * 0.35, half_w, x);
	float pulse = 0.65 + 0.35 * beat;
	float a = fade * side * pulse * intensity * max_alpha;
	ALBEDO = lane_color.rgb;
	ALPHA = clamp(a, 0.0, max_alpha);
}
