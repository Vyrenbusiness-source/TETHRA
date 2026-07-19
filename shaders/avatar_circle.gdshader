shader_type canvas_item;

// Rundes Profilbild: alles ausserhalb des Kreises wird weich ausgeblendet,
// optional mit schmalem hellen Rand.

uniform float border = 0.06;
uniform vec4 border_col: source_color = vec4(1.0, 1.0, 1.0, 0.35);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float mask = 1.0 - smoothstep(0.97, 1.0, r);
	float ring = smoothstep(1.0 - border * 2.0, 1.0 - border, r) * mask;
	COLOR.rgb = mix(COLOR.rgb, border_col.rgb, ring * border_col.a);
	COLOR.a *= mask;
}
