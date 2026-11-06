shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Billboard-Funken: weicher Punkt, Farbe + Alpha pro Instanz (MultiMesh-Color).
uniform float max_bright : hint_range(0.0, 2.0) = 0.8;

varying vec4 v_col;

void vertex() {
	v_col = COLOR;
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	VERTEX *= s;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float core = smoothstep(1.0, 0.0, d);
	core = core * core;
	float a = core * v_col.a;
	ALBEDO = min(v_col.rgb * a, vec3(max_bright));
	ALPHA = 1.0;
}
