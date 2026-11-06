shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Kurzer, kleiner Treffer-Puls an der Abfanglinie: duenner Ring mit AA-Kante.
// radius waechst per Tween 0.06 -> 0.46, intensity faedet parallel auf 0.
// LESBARKEIT: Der Ring bleibt klein (radius wird auf 55 % skaliert), faedet
// schneller aus (intensity^1.6) und wird nur auf der Kamera-Seite der Linie
// gezeichnet (UV.y >= 0.5 = naeher zur Kamera nach der -90-Grad-Drehung) ->
// nie ueber anfliegenden Noten.
// beat 0..1: Atmen max +2 %. approach: ohne Wirkung (Kompatibilitaet).

uniform vec3 base_color: source_color = vec3(1.0);
uniform float intensity = 1.0;
uniform float radius = 0.2;
uniform float beat: hint_range(0.0, 1.0) = 0.0;
uniform float approach: hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float d = distance(UV, vec2(0.5));
	float aa = max(fwidth(d), 0.0004);
	float r = radius * 0.55;
	// Schmaler Ring, klare Kante (1-2 px AA), kein weicher Schleier.
	float ring = 1.0 - smoothstep(0.006, 0.006 + aa * 1.5, abs(d - r));
	// Nur die kameraseitige Haelfte (unterhalb der Linie im Bild).
	float near_side = smoothstep(0.49, 0.53, UV.y);
	float k = pow(clamp(intensity / 1.5, 0.0, 1.0), 1.6);
	float a = ring * near_side * k * 0.7;
	a *= 1.0 + 0.02 * clamp(beat, 0.0, 1.0);
	ALBEDO = base_color * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
