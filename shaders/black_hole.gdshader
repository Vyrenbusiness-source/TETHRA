shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// SCHWARZES LOCH mit Gravitationslinse: der Hintergrund (Nebel/Sterne)
// wird per Screen-Texture radial um den Kern gebogen, darum rotiert eine
// heisse Akkretionsscheibe. spin steigt im Kiai.

uniform sampler2D screen_tex: hint_screen_texture, filter_linear_mipmap;
uniform float spin = 0.25;
uniform float t = 0.0;
uniform float strength = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 dir = p / max(r, 1e-4);
	// Linse: Screen-UV Richtung Zentrum ziehen (staerker nahe am Kern).
	float bend = strength * 0.055 / (r * r + 0.06) * (1.0 - smoothstep(0.55, 1.0, r));
	vec3 bg = texture(screen_tex, SCREEN_UV - dir * bend * 0.22).rgb;
	// Ereignishorizont: pures Schwarz mit weicher Kante.
	float hole = smoothstep(0.30, 0.235, r);
	// Akkretionsscheibe: rotierender, flackernder Hitzering.
	float ang = atan(p.y, p.x);
	float disk_band = smoothstep(0.58, 0.34, r) * smoothstep(0.235, 0.30, r);
	float swirl = 0.55 + 0.45 * sin(ang * 3.0 - t * spin * 6.0 + r * 16.0);
	swirl *= 0.8 + 0.2 * sin(ang * 9.0 + t * spin * 11.0);
	vec3 disk_col = mix(vec3(1.0, 0.55, 0.20), vec3(0.70, 0.82, 1.0), swirl);
	vec3 col = mix(bg, vec3(0.0), hole) + disk_col * disk_band * swirl * 1.5;
	ALBEDO = col;
	// Rand weich auslaufen lassen (kein sichtbares Quad).
	ALPHA = smoothstep(1.0, 0.62, r);
}
