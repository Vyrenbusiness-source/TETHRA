shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Expandierende Shockwave fuer das Hit-Lighting: duenner, weich
// auslaufender Ring. radius waechst per Tween 0.06 -> 0.46, intensity
// faedet parallel auf 0.

uniform vec3 base_color: source_color = vec3(1.0);
uniform float intensity = 1.0;
uniform float radius = 0.2;

void fragment() {
	float d = distance(UV, vec2(0.5));
	// Aussenkante haerter als Innenkante -> wirkt wie eine laufende Welle.
	float ring = smoothstep(0.055, 0.0, abs(d - radius) - 0.012);
	// Innenflaeche glimmt schwach nach.
	float fill = smoothstep(radius, radius * 0.2, d) * 0.18;
	float a = (ring + fill) * clamp(intensity, 0.0, 2.0);
	ALBEDO = base_color * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
