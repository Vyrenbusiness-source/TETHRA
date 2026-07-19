shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// GOD-RAYS: volumetrisch wirkender Lichtfaecher aus dem Fluchtpunkt.
// Strahlen rotieren traege und atmen mit intensity (Beat/Docking).

uniform vec3 base_color: source_color = vec3(0.3, 0.7, 1.0);
uniform float intensity = 0.08;
uniform float rot = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y *= 0.45;
	float r = length(p);
	float ang = atan(p.y, p.x);
	// Zwei ueberlagerte Strahlen-Frequenzen — wirkt organisch statt Zahnrad.
	float rays = pow(0.5 + 0.5 * sin(ang * 14.0 + rot), 3.0)
			* (0.55 + 0.45 * sin(ang * 5.0 - rot * 0.7));
	float fall = exp(-r * 2.2) * smoothstep(1.0, 0.35, r);
	float a = rays * fall * intensity;
	ALBEDO = base_color * a * 2.2;
	ALPHA = clamp(a, 0.0, 1.0);
}
