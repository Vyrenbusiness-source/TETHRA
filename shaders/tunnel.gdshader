shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// Neon-Tunnel — exakt der bewaehrte Look: Ringe + Laengsstreben, dunkler
// Fluchtpunkt, schwarzer Rest. Uniforms: scroll, beat_pulse, kiai, intensity.

uniform float scroll = 0.0;
uniform float beat_pulse = 0.0;
uniform float kiai = 0.0;
uniform float intensity = 0.62;
// Streckenkruemmung: das ferne Tunnelende biegt in diese Richtung ab
// (Welt-Einheiten). Wir bleiben immer in der Mitte — nur der Weg vor uns
// kurvt, das erzeugt das Flieg-Gefuehl.
uniform vec2 bend = vec2(0.0, 0.0);
uniform vec3 base_color: source_color = vec3(0.05, 0.32, 0.75);
uniform vec3 kiai_color: source_color = vec3(1.00, 0.45, 0.10);

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float depth = local_pos.y;
	float ang = atan(local_pos.z, local_pos.x);

	// Streckenkruemmung: Ring-Phase pro Wandrichtung verschieben — das ferne
	// Ende scheint abzubiegen, waehrend wir in der Mitte bleiben.
	float depth_k = pow(abs(depth) / 45.0, 2.0);
	float skew = (cos(ang) * bend.x + sin(ang) * bend.y) * depth_k * 0.35;
	float rings = pow(abs(sin(depth * 0.35 - scroll + skew)), 18.0);
	float rails = pow(abs(sin(ang * 6.0)), 42.0) * 0.5;
	float fade = smoothstep(-48.0, -6.0, -abs(depth));
	fade = fade * fade * 0.95 + 0.05;

	vec3 col = mix(base_color, kiai_color, kiai);
	float glow = rings * (0.8 + 0.6 * beat_pulse) + rails * (0.35 + 0.3 * kiai);
	glow *= intensity * fade;

	ALBEDO = col * glow * 2.4;
	ALPHA = clamp(glow, 0.0, 1.0);
}
