shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Weicher additiver Glow-Punkt (Komet-Kopf, Cursor, Sterne, Hit-Blitze).

uniform vec4 base_color: source_color = vec4(0.8, 0.95, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float master_alpha = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float core = exp(-d * d * 6.0);
	float halo = exp(-d * 2.4) * 0.55;
	vec3 col = base_color.rgb * COLOR.rgb * (core * 2.4 + halo) * intensity;
	ALBEDO = col;
	ALPHA = clamp(core + halo, 0.0, 1.0) * master_alpha;
}
