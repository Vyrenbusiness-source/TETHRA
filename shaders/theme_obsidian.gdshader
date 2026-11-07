shader_type sky;

// Welt-Thema "Obsidian": abstrakt, duester, schwer. Schwarzes Oel unter fast
// schwarzem Himmel, nur feine kalte Glanzlichter in Stahlblau, kein Neon.
// Panorama offline: tools/gen_theme_obsidian.py ->
//   assets_game/themes/obsidian/obsidian_sky.webp    (Himmel, Tintenschwaden,
//     schwebende Oeltropfen, verborgene kalte Lichter, ferne Oelflaeche)
//   assets_game/themes/obsidian/obsidian_waves.webp  (kachelbare Duenung:
//     R/G = Steigung, B = Hoehe; Sampler waves_a)
// Dieser Shader legt die rollende Oelflaeche live auf den Boden bis zum
// Horizont: zwei Wellen-Massstaebe (Parallax) rollen langsam zum Spieler,
// spiegeln das Panorama mit Fresnel und fangen die drei Lichter als harte
// Glanzlinien. Unter der Strecke bleibt das Oel matt schwarz.
//
// Uniform-Interface wie shaders/sky_panorama.gdshader (gleiche Namen/Bedeutung):
//   tex_a / tex_b / palette_mix   Panorama (wurzel-kodiert, linear = textur^2),
//                                 Ueberblendung a->b wie dort.
//   stars_a / stars_b             optionale Sternen-Ebene (Standard schwarz;
//                                 Obsidian hat keine Sterne).
//   tint, brightness, star_brightness, star_hdr, beat_pulse, readability,
//   pano_rotation/pano_offset, stars_rotation/stars_offset.
//   star_speed / star_phase       hier: Zusatz-Fluss der Wellen in Welteinheiten/s
//                                 bzw. Phase in Welteinheiten (zum Spieler).
//   warp 0..1                     Geschwindigkeits-Unschaerfe: Glanz zieht sich
//                                 in Flugrichtung zu Streifen, Wellen strecken sich.
// Obsidian-eigene Uniforms: waves_a, aurora_flow, flow_speed, sea_*, wave_*,
// gloss_*, light_a/b/c, swell_*.
//
// Zeitbasis: aurora_flow (mania_3d zaehlt es fuer alle Themen hoch, Komfort
// halb so schnell, Kiai schneller); 0 -> TIME. Die Duenung bewegt sich also
// immer, auch wenn star_speed = 0 bleibt.
//
// beat_pulse: 1 auf dem Schlag, klingt bis zum naechsten auf 0 ab, wie Neon:
// pow(1 - beat_phase, 4). Daraus wird die Beat-Phase zurueckgerechnet; das
// Oel ATMET: eine schwere Druckwelle rollt je Schlag vom Horizont
// (swell_reach) zum Spieler, hebt die Oberflaeche seitlich der Strecke an und
// laesst deren Glanz anschwellen. Huelle sin(pi*phase) -> stetig, kein Sprung
// am Schlag, kein Flackern, kein Vollbild-Blitz, nie ueber der Strecke.
//
// Geometrie: Oelflaeche sea_height unter der Kamera (mania_3d: Kamera y 2.1,
// Strecke ROAD_Y -1.6 -> 3.7 darunter, das Oel liegt tiefer). Ferne: Detail
// flacht ab und blendet in die ferne Oelflaeche des Panoramas (kein Moire,
// Wellen-Ebene mit Mipmaps). Cubemap-Pass (Radiance) nur Panorama.
//
// INTEGRATION (wie sky_panorama / theme_neon):
//   var mat := ShaderMaterial.new()
//   mat.shader = load("res://shaders/theme_obsidian.gdshader")
//   mat.set_shader_parameter("tex_a", load("res://assets_game/themes/obsidian/obsidian_sky.webp"))
//   mat.set_shader_parameter("waves_a", load("res://assets_game/themes/obsidian/obsidian_waves.webp"))
//   sky.sky_material = mat ... pro Frame beat_pulse (wie Neon), aurora_flow.
//   (mania_3d._build_theme_sky bindet tex_a/waves_a schon per Dateikonvention.)
//
// FARBSATZ fuer Strecke / Kanten / Pads (sRGB-Hex; Schwarz + Stahlblau-Glanz):
//   Strecke Grund        #040507  (Obsidian-Schwarz, Alpha 0.94)
//   Strecke Welle        #2c3a4a  (road_wave base_color, dunkles Stahlblau)
//   Spurlinien           #1c2530  (Alpha 0.55, kaum sichtbar)
//   Kanten (aussen)      #8fb0d0  Emission 0.55 (Bass-Spitze -> #cfe0f2)
//   Kanten Kiai          #e8f1fb  (kaltes Weiss, Emission 0.9)
//   Pads Ring            #7f9fbf  fill_alpha 0.16
//   Pads Treffer         #ffffff -> #a9c4de
//   Noten                #c8dcf0 (hell) / #6f8fb0 (Stahl) je Spurpaar,
//                        Kern weiss; Holds #5d7c9c
//   Kiai / Glanzkern     #d8e6f5
//   Funken / Laser       #cfe0f2 / #8fb0d0
//   Ambient              #07090c, Glow-Schwelle 0.92 wie mania_3d
//   Kein Neon, keine Saettigung > 0.35: nur Schwarz, Graphit, Stahlblau, Weiss.

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

// Oel-Duenung (R/G Steigung, B Hoehe). Fehlt die Ebene: transparent -> flach.
uniform sampler2D waves_a : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform float aurora_flow = 0.0;
uniform float flow_speed = 1.1;         // Welteinheiten/s zum Spieler
uniform float sea_height = 5.4;
uniform float wave_slope = 1.0;         // Steigungsbereich der Ebene (Generator WAVE_SLOPE)
uniform float wave_tile_a = 96.0;       // grosse Duenung
uniform float wave_tile_b = 34.0;       // mittlere Wellen (gedreht, quer)
uniform float wave_gain_a = 0.85;
uniform float wave_gain_b = 0.55;
uniform float sea_clear = 4.4;          // halbe Breite (x) mattes Oel unter der Strecke
uniform float sea_clear_soft = 6.0;
uniform float sea_center_level = 0.22;  // Restglanz unter der Strecke
uniform float sea_fade = 260.0;         // Abstand, ab dem das Panorama-Oel uebernimmt
uniform float reflect_gain = 3.0;
uniform float swell_amp = 2.4;          // Hoehe der langen Duenung (Welteinheiten)
uniform vec3 gloss_color : source_color = vec3(0.275, 0.43, 0.63);  // #8fb0d0
uniform vec3 gloss_core : source_color = vec3(0.69, 0.79, 0.91);    // #d8e6f5
uniform float gloss_intensity : hint_range(0.0, 4.0) = 1.0;
// Lichter: (Laenge Grad, Breite Grad, Staerke) - wie LIGHTS im Generator.
uniform vec3 light_a = vec3(-42.0, 3.0, 1.0);
uniform vec3 light_b = vec3(46.0, 4.2, 0.8);
uniform vec3 light_c = vec3(172.0, 2.4, 0.45);
// Beat-Atmen
uniform float swell_reach = 120.0;      // Start-Abstand der Druckwelle (vorn)
uniform float swell_height = 2.6;       // Hoehe der Druckwelle (Welteinheiten)
uniform float swell_gloss = 0.35;       // Glanz-Anstieg auf der Welle / im Atem

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

vec3 light_dir(vec3 l, mat3 m) {
	float lo = radians(l.x);
	float la = radians(l.y);
	return m * vec3(sin(lo) * cos(la), sin(la), -cos(lo) * cos(la));
}

// Beat-Phase 0..1 aus beat_pulse = pow(1 - phase, 4); Atem-Huelle sin(pi*phase).
float beat_phase() {
	return clamp(1.0 - pow(clamp(beat_pulse, 0.0, 1.0), 0.25), 0.0, 1.0);
}

// Harter Glanz (Kern) + weicher Schimmer eines Lichts.
vec2 gloss(vec3 n, vec3 v, vec3 l, float k, float sharp) {
	vec3 h = normalize(l + v);
	float nh = max(dot(n, h), 0.0);
	return k * vec2(pow(nh, sharp) * 7.0, pow(nh, sharp * 0.09) * 0.22);
}

// Steigung (dh/dx, dh/dz) einer langen Welle: Richtung d (zum Spieler +z),
// Wellenlaenge lam, Hoehe a, Weg off (Welteinheiten), Ausblendung f0..f1.
vec2 swell(vec2 p, vec2 d, float lam, float a, float off, float f0, float f1) {
	vec2 k = normalize(d) * (TAU / lam);
	float ph = dot(k, p) - off * (TAU / lam);
	float c = 0.5 + 0.5 * cos(ph);
	float dh = a * 1.7 * pow(max(c, 1e-4), 0.7) * (-0.5 * sin(ph));
	return k * dh * (1.0 - smoothstep(f0, f1, length(p)));
}

vec3 oil_sea(vec3 dir, vec3 pan, mat3 prot) {
	float dy = -dir.y;
	float t = sea_height / max(dy, 1e-4);
	vec2 p = dir.xz * t;                // Bodenpunkt (x, z), z < 0 = vorn
	float dist = length(p);
	float fwd = -p.y;

	float tb = aurora_flow > 0.0 ? aurora_flow : TIME;
	float flow = tb * flow_speed + star_phase + TIME * star_speed;

	// Zwei Massstaebe: grosse Duenung rollt gerade zum Spieler, mittlere
	// Wellen gedreht und langsamer quer (Parallax, keine sichtbare Kachel).
	vec2 ua = vec2(p.x + 0.17 * flow, p.y - flow) / wave_tile_a;
	float ca = 0.8, sa = 0.6;
	mat2 rb = mat2(vec2(ca, sa), vec2(-sa, ca));
	vec2 pb = rb * p;
	vec2 ub = (pb + vec2(-0.35, -0.62) * flow) / wave_tile_b + vec2(0.37, 0.11);
	vec4 wa = texture(waves_a, ua);
	vec4 wb = texture(waves_a, ub);
	float has = wa.a;                   // 0 = keine Wellen-Ebene gebunden
	float near_detail = 1.0 - smoothstep(70.0, 210.0, dist);
	vec2 sa_s = (wa.rg - 0.5) * 2.0 * wave_slope * wave_gain_a * (56.0 / wave_tile_a);
	vec2 sb_s = (wb.rg - 0.5) * 2.0 * wave_slope * wave_gain_b * (56.0 / wave_tile_b) * 0.38;
	sb_s = transpose(rb) * sb_s;        // Steigung zurueck in Weltachsen
	float flat_far = 1.0 - smoothstep(120.0, sea_fade, dist) * 0.75;
	vec2 s = (sa_s * flat_far + sb_s * near_detail) * has;

	// Riesige Duenung: drei lange Kaemme rollen zum Spieler (analytisch,
	// trochoidal: runde Kaemme, breite Taeler), Ferne blendet sie aus.
	vec2 sw = vec2(0.0);
	sw += swell(p, vec2(0.12, 1.0), 64.0, swell_amp * 1.0, flow * 1.0, 150.0, 270.0);
	sw += swell(p, vec2(-0.38, 1.0), 39.0, swell_amp * 0.55, flow * 0.8 + 11.0, 110.0, 210.0);
	sw += swell(p, vec2(0.7, 0.75), 23.0, swell_amp * 0.22, flow * 0.6 + 5.0, 70.0, 150.0);
	s += sw;

	// Beat-Druckwelle: gewoelbter Kamm rollt vom Horizont zum Spieler.
	float side = smoothstep(sea_clear, sea_clear + sea_clear_soft, abs(p.x));
	float ph = beat_phase();
	float breath = sin(PI * ph);
	breath *= breath;
	float zr = mix(swell_reach, 4.0, ph);
	float fe = fwd + 0.0045 * p.x * p.x;
	float ww = 5.0 + fe * 0.07;
	float q = (fe - zr) / ww;
	float g = swell_height * breath * exp(-q * q) * side;
	float dg = -2.0 * q / ww * g;       // dg/dfe
	s += vec2(dg * 0.009 * p.x, -dg);   // fe(x, z): dfe/dx = 0.009x, dfe/dz = -1
	float crest = exp(-q * q) * breath * side;

	// Warp: Glanz zieht sich in Flugrichtung zu Streifen.
	s.y *= 1.0 - 0.8 * warp;
	s.x *= 1.0 + 0.25 * warp;

	vec3 n = normalize(vec3(-s.x, 1.0, -s.y));
	vec3 v = -dir;
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	vec3 r = reflect(dir, n);
	float occ = r.y < 0.0 ? 0.25 : 1.0; // Spiegelung in die naechste Welle -> schwarz
	r.y = abs(r.y);
	vec3 env = sample_pair(tex_a, tex_b, dir_uv(r * prot, pano_offset));
	float F = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	vec3 col = env * F * reflect_gain * occ;

	float sharp = mix(1400.0, 160.0, warp);
	vec2 gl = gloss(n, v, light_dir(light_a, prot), light_a.z, sharp)
		+ gloss(n, v, light_dir(light_b, prot), light_b.z, sharp)
		+ gloss(n, v, light_dir(light_c, prot), light_c.z, sharp);
	gl *= mix(0.35, 1.0, smoothstep(5.0, 30.0, dist)); // kein Grell-Fleck vor der Kamera
	float lift = 1.0 + swell_gloss * (crest * 2.0 + breath * 0.3 * side);
	col += (gloss_core * gl.x + gloss_color * gl.y) * mix(0.35, 1.0, F) * gloss_intensity * lift * occ;
	// Kamm der Druckwelle faengt kalten Schimmer (auch ohne Licht dahinter).
	col += gloss_color * crest * F * 0.05 * swell_gloss;

	// Taeler schwerer und dunkler (Hoehe aus B).
	float hgt = mix(0.5, wa.b, has);
	col *= mix(0.45, 1.15, hgt);

	// Unter der Strecke mattes Schwarz, nahe Kamera weich, Ferne -> Panorama.
	col *= mix(sea_center_level, 1.0, side);
	col *= smoothstep(1.0, 5.0, dist);
	float far = smoothstep(sea_fade * 0.6, sea_fade * 2.4, dist);
	return mix(col, pan, clamp(far, 0.0, 1.0));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	mat3 prot = euler(pano_rotation);
	vec2 puv = dir_uv(dir * prot, pano_offset);
	vec3 pan = sample_pair(tex_a, tex_b, puv);

	// Panorama-Glanz (Tropfen, Lichtkerne) atmet mit, Schwarz bleibt schwarz.
	float br = sin(PI * beat_phase());
	br *= br;
	float nl = dot(pan, vec3(0.2126, 0.7152, 0.0722));
	pan *= 1.0 + br * swell_gloss * 0.5 * smoothstep(0.02, 0.25, nl);

	if (AT_CUBEMAP_PASS) {
		COLOR = pan * tint * brightness * 0.5;
	} else {
		vec3 col = pan;
		vec3 st = sample_pair(stars_a, stars_b, dir_uv(dir * euler(stars_rotation), stars_offset));
		float sl = dot(st, vec3(0.2126, 0.7152, 0.0722));
		st *= star_brightness * mix(1.0, star_hdr, smoothstep(0.55, 1.0, sl));
		col += st * step(0.0, dir.y);
		if (dir.y < 0.0) {
			col = oil_sea(dir, pan, prot);
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
