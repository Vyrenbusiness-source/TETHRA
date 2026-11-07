shader_type sky;

// Welt-Thema "Neon" (Synthwave-Nacht) fuer elektronische Songs mit hoher BPM.
// Panorama offline: tools/gen_theme_neon.py -> assets_game/themes/neon/neon_sky.webp
// (Himmel, Retro-Sonne mit Scanlines, Skyline, Berge, Sterne, dunkler Boden).
// Dieser Shader legt das animierte Neon-Gitter auf den Boden bis zum Horizont:
// es stroemt zum Spieler (Flug), eine Lichtwelle laeuft auf jedem Beat vom
// Horizont zum Spieler (beat_pulse), die Mitte unter der Strecke bleibt frei.
//
// Uniform-Interface wie shaders/sky_panorama.gdshader (gleiche Namen/Bedeutung):
//   tex_a / tex_b / palette_mix   Panorama (wurzel-kodiert, linear = textur^2),
//                                 Ueberblendung a->b wie dort.
//   stars_a / stars_b             optionale Sternen-Ebene (Standard schwarz,
//                                 die Sterne sind schon im Panorama).
//   tint, brightness, star_brightness, star_hdr, beat_pulse, readability,
//   pano_rotation/pano_offset, stars_rotation/stars_offset.
//   star_speed / star_phase       hier: Gitter-Flug in Zellen/s bzw. Phase in
//                                 Zellen (fuer variable Geschwindigkeit
//                                 star_speed = 0 lassen, star_phase hochzaehlen).
//   warp 0..1                     Geschwindigkeits-Unschaerfe: Quer-Linien
//                                 verwischen in Flugrichtung, Laengs-Linien gluehen.
// Neon-eigene Uniforms: grid_* (unten), sun_hdr.
//
// beat_pulse: 1 auf dem Schlag, klingt bis zum naechsten auf 0 ab (z.B.
// pow(1 - beat_phase, 4)). Die Welle startet bei pulse_reach (Welteinheiten)
// und erreicht den Spieler, wenn beat_pulse gegen 0 geht.
//
// Geometrie: Bodenebene grid_height unter der Kamera (mania_3d: Kamera y 2.1,
// Strecke ROAD_Y -1.6 -> 3.7). Gitter-Linien sind analytisch gefiltert
// (fwidth), ferne Zellen gehen glatt in mittleren Schein ueber - kein Moire.
// Cubemap-Pass (Radiance) ohne Gitter.
//
// INTEGRATION (wie sky_panorama):
//   var mat := ShaderMaterial.new()
//   mat.shader = load("res://shaders/theme_neon.gdshader")
//   mat.set_shader_parameter("tex_a", load("res://assets_game/themes/neon/neon_sky.webp"))
//   sky.sky_material = mat ... pro Frame beat_pulse, star_speed (oder star_phase).
//
// FARBSATZ fuer Strecke / Kanten / Pads (sRGB-Hex; Magenta/Cyan):
//   Strecke Grund        #0a0614  (fast schwarz-violett, Alpha 0.92)
//   Strecke Welle        #ff2bd6  (road_wave base_color, Magenta)
//   Spurlinien           #3b2a6e  (Alpha 0.5, dezent)
//   Kanten (aussen)      #ff2bd6  Emission 0.7 (Bass-Spitze -> #ff7ae8)
//   Kanten Kiai          #19f0ff  (Cyan)
//   Pads Ring            #19f0ff  fill_alpha 0.22
//   Pads Treffer         #ffffff -> #19f0ff
//   Noten                #6ff7ff (Cyan) / #ff5ae0 (Magenta) je Spurpaar,
//                        Kern weiss; Holds #ff5ae0
//   Kiai / Sonne         #ffd84a -> #ff7a3c
//   Funken / Laser       #ff7ae8 / #8ff4ff
//   Ambient              #1a0d2e, Glow-Schwelle 0.92 wie mania_3d

uniform sampler2D tex_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D tex_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D stars_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D stars_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform float palette_mix : hint_range(0.0, 1.0) = 0.0;

uniform vec3 tint : source_color = vec3(1.0);
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_hdr : hint_range(1.0, 4.0) = 1.5;
uniform float beat_pulse : hint_range(0.0, 1.0) = 0.0;

uniform vec3 pano_rotation = vec3(0.0);
uniform vec2 pano_offset = vec2(0.0);
uniform vec3 stars_rotation = vec3(0.0);
uniform vec2 stars_offset = vec2(0.0);

uniform float star_speed = 0.0;
uniform float star_phase = 0.0;
uniform float warp : hint_range(0.0, 1.0) = 0.0;
uniform float readability : hint_range(0.0, 1.0) = 0.35;

// Neon-Gitter
uniform vec3 grid_color : source_color = vec3(1.0, 0.17, 0.84);
uniform vec3 grid_color_far : source_color = vec3(0.54, 0.24, 1.0);
uniform vec3 pulse_color : source_color = vec3(0.10, 0.94, 1.0);
uniform float grid_intensity : hint_range(0.0, 4.0) = 0.85;
uniform float grid_height = 3.7;
uniform float grid_cell = 2.6;
uniform float grid_clear = 5.4;      // halbe Breite (x) ohne Gitter unter der Strecke
uniform float grid_clear_soft = 3.5; // Uebergang daneben
uniform float grid_fade = 180.0;     // Abstand, ab dem das Gitter im Dunst verschwindet
uniform float pulse_reach = 150.0;   // Start-Abstand der Beat-Welle
uniform float sun_hdr : hint_range(1.0, 4.0) = 1.3;

mat3 euler(vec3 e) {
	float cx = cos(e.x), sx = sin(e.x);
	float cy = cos(e.y), sy = sin(e.y);
	float cz = cos(e.z), sz = sin(e.z);
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cx, sx), vec3(0.0, -sx, cx));
	mat3 ry = mat3(vec3(cy, 0.0, -sy), vec3(0.0, 1.0, 0.0), vec3(sy, 0.0, cy));
	mat3 rz = mat3(vec3(cz, sz, 0.0), vec3(-sz, cz, 0.0), vec3(0.0, 0.0, 1.0));
	return ry * rx * rz;
}

vec2 dir_uv(vec3 d, vec2 ofs) {
	float u = atan(d.x, -d.z) * (0.5 / PI) + 0.5 + ofs.x;
	float v = 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI + ofs.y;
	return vec2(fract(u), clamp(v, 0.0005, 0.9995));
}

vec3 dec(vec3 c) {
	return c * c;
}

vec3 sample_pair(sampler2D a, sampler2D b, vec2 uv) {
	if (palette_mix <= 0.001) {
		return dec(textureLod(a, uv, 0.0).rgb);
	}
	if (palette_mix >= 0.999) {
		return dec(textureLod(b, uv, 0.0).rgb);
	}
	return mix(dec(textureLod(a, uv, 0.0).rgb), dec(textureLod(b, uv, 0.0).rgb), palette_mix);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Gefilterte Linie: Abstand f (Zellen) zur naechsten Linie, Breite w, Pixelbreite fw.
// Liefert (Kern, Schein); bei grossem fw -> Mittelwert (kein Moire am Horizont).
vec2 grid_line(float c, float w, float glow_w, float fw) {
	float f = abs(fract(c - 0.5) - 0.5);
	fw = max(fw, 1e-5);
	float core = 1.0 - smoothstep(w - fw, w + fw, f);
	float gw = glow_w + fw;
	float glow = exp(-f / gw);
	float avg_core = min(2.0 * w, 1.0);
	float avg_glow = 2.0 * gw * (1.0 - exp(-0.5 / gw));
	float k = smoothstep(0.08, 0.45, fw);
	return vec2(mix(core, avg_core, k), mix(glow, avg_glow, k));
}

vec3 neon_grid(vec3 dir) {
	float dy = -dir.y;
	float t = grid_height / max(dy, 1e-4);
	vec2 p = dir.xz * t;                // Bodenpunkt (x, z), z < 0 = vorn
	float dist = length(p);
	float ph = star_phase + TIME * star_speed;
	vec2 c = vec2(p.x / grid_cell, p.y / grid_cell - ph);
	vec2 fw = fwidth(c);

	// Laengs-Linien (konstantes x, laufen zum Horizont) und Quer-Linien (konstantes z).
	float wz = 0.022;
	vec2 lx = grid_line(c.x, wz, 0.035 + warp * 0.03, fw.x);
	float blur = warp * 0.10;           // Quer-Linien verwischen in Flugrichtung
	vec2 lz = grid_line(c.y, wz + blur * 0.5, 0.035 + blur, fw.y + blur * 0.5);
	lz *= 1.0 - warp * 0.6;
	float core = max(lx.x, lz.x);
	float glow = max(lx.y, lz.y);

	// Masken: Mitte frei, Ferne verblasst in den Horizont-Dunst, Nahbereich weich.
	float side = smoothstep(grid_clear, grid_clear + grid_clear_soft, abs(p.x));
	float far = exp(-dist / grid_fade) * smoothstep(0.0, 0.004, dy);
	float near = smoothstep(1.5, 6.0, dist);
	float m = side * far * near;

	// Beat-Welle: Lichtband laeuft vom Horizont zum Spieler.
	float bp = clamp(beat_pulse, 0.0, 1.0);
	float dw = pulse_reach * sqrt(bp);
	float ww = 2.2 + dist * 0.06;
	float band = exp(-pow((dist - dw) / ww, 2.0)) * smoothstep(0.0, 0.08, bp);
	float trail = exp(-max(dist - dw, 0.0) / (ww * 4.0)) * step(dw, dist) * 0.35 * smoothstep(0.0, 0.08, bp);
	float wave = band + trail;

	vec3 lc = mix(grid_color, grid_color_far, smoothstep(20.0, 120.0, dist));
	float lift = 1.0 + 0.45 * bp;
	vec3 col = lc * (core * 1.25 + glow * 0.16) * lift;
	col = mix(col, pulse_color * (core * 2.0 + glow * 0.35), clamp(band * 0.85, 0.0, 1.0));
	col += pulse_color * (core * 1.6 + glow * 0.25) * trail * 0.5;
	// Bodenschein unter der Welle (auch zwischen den Linien, nur seitlich).
	col += pulse_color * wave * 0.035;
	return col * m * grid_intensity;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec2 puv = dir_uv(dir * euler(pano_rotation), pano_offset);
	vec3 pan = sample_pair(tex_a, tex_b, puv);

	// Sonne/Neon atmen auf dem Beat (Lichter heben sich, Schwarz bleibt schwarz).
	float nl = dot(pan, vec3(0.2126, 0.7152, 0.0722));
	pan *= mix(1.0, sun_hdr, smoothstep(0.30, 0.65, nl));
	pan *= 1.0 + beat_pulse * (0.06 + 0.9 * nl);

	if (AT_CUBEMAP_PASS) {
		COLOR = pan * tint * brightness * 0.5;
	} else {
		vec3 col = pan;
		vec3 st = sample_pair(stars_a, stars_b, dir_uv(dir * euler(stars_rotation), stars_offset));
		float sl = dot(st, vec3(0.2126, 0.7152, 0.0722));
		st *= star_brightness * mix(1.0, star_hdr, smoothstep(0.55, 1.0, sl)) * (1.0 + beat_pulse * 0.55);
		col += st * step(0.0, dir.y);
		if (dir.y < 0.0) {
			col += neon_grid(dir);
		}
		col *= tint * brightness;

		// Lesbarkeit in Weltkoordinaten: vorn-mitte/unten zusaetzlich dunkler.
		float lon = atan(dir.x, -dir.z);
		float lat = asin(clamp(dir.y, -1.0, 1.0));
		float front = exp(-(lon / 0.62) * (lon / 0.62)) * smoothstep(0.02, -0.30, lat);
		col *= 1.0 - readability * 0.6 * front;

		float h = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
		col = max(col * (1.0 + h * 0.03) + h * 0.00025, vec3(0.0));
		COLOR = col;
	}
}
