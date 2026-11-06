shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Skill-Lichtstroeme an den Streckenaussenkanten (SkillFx).
// Ein Puls pro Schlag laeuft von der Abfanglinie nach hinten.
//  wall = 0: flaches Band am Boden (PlaneMesh, UV.y = 0 hinten).
//  wall = 1: senkrechte Lichtwand (QuadMesh, rot Y 90, UV.x = 0 vorne).
// Alles additiv und weich: keine Vollflaechen-Blitze, nur wandernde Pulse.

uniform vec3 color: source_color = vec3(0.3, 0.85, 1.0);
uniform float intensity = 0.0;   // 0..1 Gesamtstaerke
uniform float beats = 0.0;       // Schlagzaehler + Phase (kontinuierlich)
uniform float env = 0.0;         // Beat-Huellkurve 0..1
uniform float prism = 0.0;       // 0..1 Prisma-Farbverlauf (Stufe 4)
uniform float side = 1.0;        // -1 links, +1 rechts
uniform float wall = 0.0;
uniform float boost = 0.0;       // sanfte Judge-Energie 0..1
uniform float sweep = -1.0;      // Meilenstein-Welle: Position 0..1.2, <0 aus
uniform float t = 0.0;
uniform float pulses = 6.0;      // sichtbare Pulse auf der ganzen Laenge

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

float pulse_shape(float s, float off) {
	// y = 0 direkt hinter der Pulsfront, waechst nach vorne (Richtung Linie).
	float y = 1.0 - fract(s * pulses - beats - off);
	return smoothstep(0.0, 0.035, y) * exp(-y * 4.2);
}

void fragment() {
	float s;
	float across;
	if (wall > 0.5) {
		s = UV.x;
		across = 1.0 - UV.y;
	} else {
		s = 1.0 - UV.y;
		across = UV.x;
	}

	// Querprofil: Boden = heller duenner Kern + weicher Halo,
	// Wand = von unten nach oben ausblendender Schleier.
	float core;
	float halo;
	if (wall > 0.5) {
		core = exp(-across * 9.0);
		halo = pow(1.0 - across, 2.2);
	} else {
		float d = abs(across - 0.5) * 2.0;
		core = exp(-d * d * 60.0);
		halo = pow(clamp(1.0 - d, 0.0, 1.0), 2.4);
	}

	// Laengs: vorne weich einblenden, hinten im Horizont verlieren.
	float along = smoothstep(0.0, 0.035, s) * (1.0 - smoothstep(0.55, 1.0, s));

	float p = pulse_shape(s, 0.0);
	// Feine Streifen, die mitstroemen: Textur statt glatter Balken.
	float streak = vnoise(vec2(s * 90.0 - beats * 15.0, across * 3.0 + side * 7.0));
	streak = 0.55 + 0.45 * streak;

	float sw = 0.0;
	if (sweep >= 0.0) {
		float ds = (s - sweep) / 0.05;
		sw = exp(-ds * ds) * (1.0 - smoothstep(0.85, 1.2, sweep));
	}

	float base = 0.16 + env * 0.10 + boost * 0.18;
	float energy = (base + p * (0.85 + boost * 0.25)) * streak + sw * 0.65;
	float shape = core * 0.75 + halo * 0.35;
	float a = energy * shape * along * clamp(intensity, 0.0, 1.0);

	// Farbe: Kern heller; Stufe 4 = Prisma-Verlauf entlang des Stroms.
	vec3 c = color;
	if (prism > 0.001) {
		float hue = fract(s * 0.9 - t * 0.06 + (side > 0.0 ? 0.5 : 0.0) + p * 0.05);
		vec3 pc = hsv2rgb(vec3(hue, 0.62, 1.0));
		c = mix(c, pc, clamp(prism, 0.0, 1.0) * 0.85);
	}
	c = mix(c, vec3(1.0), core * p * 0.45);

	ALBEDO = c * a * 1.9;
	ALPHA = clamp(a, 0.0, 1.0);
}
