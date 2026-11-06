shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Expandierende Shockwave fuer das Hit-Lighting: duenner, weich
// auslaufender Ring mit AA-Kante und feinem Glanzring. radius waechst per
// Tween 0.06 -> 0.46, intensity faedet parallel auf 0.
// beat 0..1: kaum merkliches Atmen (max +4%). approach 0..1: minimal schaerfer.

uniform vec3 base_color: source_color = vec3(1.0);
uniform float intensity = 1.0;
uniform float radius = 0.2;
uniform float beat: hint_range(0.0, 1.0) = 0.0;
uniform float approach: hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float d = distance(UV, vec2(0.5));
	float aa = max(fwidth(d), 0.0004);
	float k = mix(1.0, 0.65, clamp(approach, 0.0, 1.0));
	// Aussenkante haerter als Innenkante -> wirkt wie eine laufende Welle.
	float dist = abs(d - radius) - 0.012;
	float ring = smoothstep(0.055 * k, 0.0, dist);
	// Feiner innerer Glanzring knapp innerhalb der Welle.
	float shine = (1.0 - smoothstep(0.0, 0.004 + aa, abs(d - (radius - 0.02)))) * 0.25;
	// Innenflaeche glimmt schwach nach.
	float fill = smoothstep(radius, radius * 0.2, d) * 0.18;
	float a = (ring + shine + fill) * clamp(intensity, 0.0, 2.0);
	a *= 1.0 + 0.04 * clamp(beat, 0.0, 1.0);
	ALBEDO = base_color * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
