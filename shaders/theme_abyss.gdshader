shader_type sky;

// Welt-Thema "Abgrund": duestere Leere, riesige Monolithen im Nebel, ein
// einzelner kalter Lichtschacht. Fast monochrom (Schwarz + kaltes
// Grau-Stahlblau), KEIN Neon.
// Panorama offline: tools/gen_theme_abyss.py ->
//   assets_game/themes/abyss/abyss_sky.webp      tex_a (Farbe, wurzel-kodiert)
//   assets_game/themes/abyss/abyss_sky_fog.webp  fog_a (Daten, verlustfrei):
//     R tiefe Nebelbaenke, G hohe Schlieren, B sichtbares Schachtlicht.
// Dieser Shader:
//   - Nebelbaenke rollen langsam seitwaerts (R schneller als G -> Parallax),
//     Oberkante wogt; der Nebel wird am Schacht kalt angeleuchtet.
//   - Lichtschacht atmet auf dem Beat (beat_pulse) und im Kiai (kiai),
//     Staubflocken sinken langsam durch den Strahl.
//   - Platten-Ebenen (abyss_sky_near.webp: R ferne, G nahe Monolithplatten,
//     B Kantenlicht): rutschen mit beat_step ruckartig, exakt auf dem
//     Schlag, weiter (ferne 0.35, nahe 0.8 Grad je Beat; Parallax) und
//     schieben sich durch den Schacht. downbeat_pulse laesst den Schacht
//     und das Kantenlicht aufflammen. Der Drop (drop 0..0.6) lichtet den
//     Nebel und weitet das Schachtlicht: Welt wird sichtbar, nie blendend.
//   - Schwerer Bodennebel auf einer Ebene unter der Strecke, stroemt beim
//     Flug zum Spieler (star_phase / star_speed), Mitte unter der Strecke
//     bleibt dunkel; warp zieht ihn in Flugrichtung.
//
// Uniform-Interface wie shaders/sky_panorama.gdshader (gleiche Namen/Bedeutung):
//   tex_a / tex_b / palette_mix   Panorama (linear = textur^2), Ueberblendung.
//   stars_a / stars_b             optionale Sternen-Ebene (Standard schwarz,
//                                 die wenigen Sterne sind im Panorama).
//   tint, brightness, star_brightness, star_hdr, beat_pulse, readability,
//   pano_rotation/pano_offset, stars_rotation/stars_offset.
//   star_speed / star_phase       hier: Bodennebel-Flug (Phase * fog_flight =
//                                 Welteinheiten; star_speed = Phase/s).
//   warp 0..1                     Bodennebel streckt sich in Flugrichtung.
// Abyss-eigene Uniforms: fog_a/fog_b, kiai, fog_*, shaft_*, ground_*.
// Schacht-Geometrie (shaft_lon ...) = Konstanten in gen_theme_abyss.py.
//
// beat_pulse: 1 auf dem Schlag, klingt bis zum naechsten auf 0 ab. Der
// Schacht folgt weich (Einatmen schnell, Ausatmen lang), Schwarz bleibt schwarz.
// Cubemap-Pass (Radiance) ohne Animation/Bodennebel.
//
// INTEGRATION (wie sky_panorama; mania_3d._build_theme_sky macht das
// automatisch: fog_a/fog_b <- abyss_sky_fog.webp, tex_a/tex_b <- abyss_sky.webp):
//   var mat := ShaderMaterial.new()
//   mat.shader = load("res://shaders/theme_abyss.gdshader")
//   mat.set_shader_parameter("tex_a", load("res://assets_game/themes/abyss/abyss_sky.webp"))
//   mat.set_shader_parameter("fog_a", load("res://assets_game/themes/abyss/abyss_sky_fog.webp"))
//   sky.sky_material = mat ... pro Frame beat_pulse, star_phase, kiai.
//
// FARBSATZ fuer Strecke / Kanten / Pads (sRGB-Hex; kaltes Stahlgrau/Weiss,
// keine Saettigung ueber ~15 %):
//   Strecke Grund        #040507  (fast schwarz, Alpha 0.94)
//   Strecke Welle        #5d6b7c  (road_wave base_color, gedaempft)
//   Spurlinien           #222a33  (Alpha 0.55)
//   Kanten (aussen)      #8e9db0  Emission 0.45 (Beat-Spitze -> #d8e3ef, 1.1)
//   Kanten Kiai          #eef3f8  (kaltes Weiss, Emission 1.3)
//   Pads Ring            #b9c6d4  fill_alpha 0.16
//   Pads Treffer         #ffffff -> #cfdcea
//   Noten                #e6edf5 (Weiss) / #8fa2b8 (Stahlblau) je Spurpaar,
//                        Kern weiss; Holds #7f93aa
//   Kiai / Schacht       #d8e3ef (Schachtlicht), Akzent #ffffff
//   Funken / Staub       #c4d2e2 / #9aabbf
//   Ambient              #07090c, Glow-Schwelle 0.92 wie mania_3d
//   WorldTheme-Palette   line #9aabbf, kiai #e6eef7

uniform sampler2D tex_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D tex_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D stars_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D stars_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D fog_a : filter_linear, repeat_enable, hint_default_black;
uniform sampler2D fog_b : filter_linear, repeat_enable, hint_default_black;
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

// Abgrund
uniform float kiai : hint_range(0.0, 1.0) = 0.0;
// Beat-Vertrag (docs/worlds/beat_contract.md)
uniform float beat_phase : hint_range(0.0, 1.0) = 0.0;
uniform float bar_phase : hint_range(0.0, 1.0) = 0.0;
uniform float beat_step = 0.0;
uniform float downbeat_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float drop : hint_range(0.0, 0.6) = 0.0;
uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float comfort : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D near_a : filter_linear, repeat_enable, hint_default_black;
uniform sampler2D near_b : filter_linear, repeat_enable, hint_default_black;
uniform float slab_mid_deg = 0.35;       // Grad je Beat (ferne Platten)
uniform float slab_near_deg = 0.8;       // Grad je Beat (nahe Platten)
uniform vec3 fog_color : source_color = vec3(0.49, 0.55, 0.63);
uniform vec3 fog_lit_color : source_color = vec3(0.74, 0.79, 0.86);
uniform vec3 shaft_color : source_color = vec3(0.85, 0.89, 0.94);
uniform float fog_density : hint_range(0.0, 2.0) = 1.0;
uniform float fog_roll = 0.0016;         // Nebelbaenke: u/s (R), G rollt 0.45x
uniform float shaft_lon = -27.0;         // Grad, Fuss des Schachts
uniform float shaft_breath : hint_range(0.0, 2.0) = 0.9;
uniform float shaft_gain = 0.55;         // B * shaft_gain = Zusatzlicht bei vollem Atem
uniform float dust : hint_range(0.0, 2.0) = 1.0;
uniform float ground_fog : hint_range(0.0, 2.0) = 1.0;
uniform float ground_height = 3.7;       // Bodenebene unter der Kamera
uniform float ground_clear = 4.6;        // halbe Breite (x) mit duennem Nebel
uniform float ground_clear_soft = 5.0;
uniform float fog_flight = 40.0;         // Welteinheiten je star_phase

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

vec3 fog_tex(vec2 uv) {
	if (palette_mix <= 0.001) {
		return dec(textureLod(fog_a, uv, 0.0).rgb);
	}
	return mix(dec(textureLod(fog_a, uv, 0.0).rgb), dec(textureLod(fog_b, uv, 0.0).rgb), palette_mix);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = r * p * 2.03 + vec2(17.1, 3.7);
		a *= 0.5;
	}
	return s / 0.9375;
}

// Wrap auf (-180, 180].
float wrap_deg(float d) {
	return d - 360.0 * floor((d + 180.0) / 360.0);
}

// Schachtlicht auf Nebel: kalter Fleck am Fuss, breiter Streuschein.
float shaft_lit(float lon, float lat) {
	float db = abs(wrap_deg(lon - shaft_lon));
	return (0.30 * exp(-(db / 4.0) * (db / 4.0)) + 0.085 * exp(-db / 12.0)) * exp(-max(lat, 0.0) / 5.0);
}

// Nebel-Grundlicht (fog_color ist linear ~0.2): kalter Dunst am Horizont.
float fog_amb(float lat) {
	return 0.045 + 0.110 * exp(-abs(lat) / 2.5);
}

// Weicher Atem: schneller Anstieg auf dem Schlag, langes Ausatmen.
float breath() {
	float b = clamp(beat_pulse, 0.0, 1.0);
	return sqrt(b) * 0.75 + b * 0.25;
}

// Staubflocken im Strahl (Grad-Raster, sinken langsam, funkeln).
float shaft_dust(float lon, float lat) {
	float cell = 0.42;
	vec2 q = vec2(lon, lat + TIME * 0.22) / cell;
	vec2 id = floor(q);
	vec2 f = fract(q);
	float acc = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 h = hash22(id + o);
			if (h.x > 0.30) {
				continue;
			}
			vec2 pos = o + vec2(h.y, fract(h.x * 7.13)) + 0.18 * vec2(sin(TIME * 0.4 + h.y * 40.0), 0.0);
			vec2 dd = (f - pos) * cell;          // Grad
			float r2 = dot(dd, dd) / (0.045 * 0.045);
			float tw = 0.45 + 0.55 * sin(TIME * (1.3 + h.y * 2.0) + h.x * 60.0);
			acc += exp(-r2) * tw * (0.4 + 2.0 * h.x);
		}
	}
	return acc;
}

// Bodennebel auf der Ebene ground_height unter der Kamera (x, z Welt).
vec4 ground_fog_layer(vec3 dir, float lon, float bp) {
	float dy = -dir.y;
	float t = ground_height / max(dy, 1e-4);
	vec2 p = dir.xz * t;
	float dist = length(p);
	float flight = (star_phase + TIME * star_speed) * fog_flight;
	float stretch = 1.0 + warp * 5.0;
	vec2 q = vec2(p.x * 0.055 + TIME * 0.012, (p.y + flight) * 0.055 / stretch);
	vec2 w = vec2(fbm(q * 0.6 + vec2(TIME * 0.02, 0.0)), fbm(q * 0.6 + vec2(5.2, 1.3)));
	float n = fbm(q + 1.6 * w);
	// Ferne: Rauschen mittelt sich aus (kein Flimmern am Horizont).
	n = mix(n, 0.5, smoothstep(60.0, 220.0, dist));
	float dens = (1.0 - exp(-dist / 34.0)) * smoothstep(0.25, 0.85, n * 0.85 + 0.25);
	dens = max(dens, (1.0 - exp(-dist / 90.0)) * 0.55);
	float side = smoothstep(ground_clear, ground_clear + ground_clear_soft, abs(p.x));
	dens *= mix(0.22, 1.0, side) * smoothstep(1.0, 6.0, dist);
	float lit = shaft_lit(lon, 0.0) * (0.6 + 0.4 * n) * (1.0 + bp * shaft_breath * 0.6);
	float far = 1.0 - exp(-dist / 120.0);
	vec3 c = fog_color * (0.020 + 0.050 * n + 0.10 * far) + fog_lit_color * lit * 0.35;
	return vec4(c, clamp(dens * ground_fog, 0.0, 0.92));
}

// Plattenebene: lit (Oberflaeche), rim (Kantenlicht), cov (Deckung).
vec3 slab_color(float rim, float v, float lon, float lat, float haze, float atem, float dk, float dbp) {
	float prox = exp(-abs(wrap_deg(lon - shaft_lon)) / 55.0);
	vec3 surf = mix(vec3(0.003, 0.004, 0.006), fog_lit_color * 0.20, v) * (0.30 + 1.1 * prox + 0.5 * dk);
	vec3 rimc = shaft_color * rim * (0.30 + 0.35 * atem + 0.9 * dbp + 0.8 * dk) * 0.9;
	vec3 c = surf + rimc;
	vec3 fc = fog_color * fog_amb(lat) + fog_lit_color * shaft_lit(lon, lat) * 0.5;
	return mix(c, fc, haze);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 pdir = dir * euler(pano_rotation);
	vec2 puv = dir_uv(pdir, pano_offset);
	vec3 pan = sample_pair(tex_a, tex_b, puv);
	float lon = degrees(atan(pdir.x, -pdir.z));
	float lat = degrees(asin(clamp(pdir.y, -1.0, 1.0)));

	float bp = breath();
	float kb = clamp(kiai, 0.0, 1.0);
	float atem = bp * shaft_breath + kb * 0.55;

	if (AT_CUBEMAP_PASS) {
		vec3 fg = fog_tex(puv);
		vec3 fc = fog_color * fog_amb(lat) + fog_lit_color * shaft_lit(lon, lat);
		vec3 c = mix(pan, fc, clamp(fg.r * 0.85 * fog_density, 0.0, 1.0));
		COLOR = c * tint * brightness * 0.5;
	} else {
		vec3 col = pan;
		vec3 st = sample_pair(stars_a, stars_b, dir_uv(dir * euler(stars_rotation), stars_offset));
		col += st * star_brightness * (1.0 + beat_pulse * 0.3) * step(0.0, dir.y);

		// Schacht: B = sichtbares Schachtlicht (normiert).
		vec3 fs = dec(textureLod(fog_a, puv, 0.0).rgb);
		float sb = fs.b;
		col += shaft_color * sb * shaft_gain * atem;
		col += shaft_color * shaft_dust(lon, lat) * smoothstep(0.05, 0.5, sb) * sb * 0.22 * dust * (1.0 + atem);

		// Nebelbaenke: zwei Ebenen rollen verschieden schnell, Oberkante wogt.
		float rt = TIME * fog_roll;
		float wob = 0.0012 * sin(puv.x * 37.0 + TIME * 0.21) + 0.0008 * sin(puv.x * 91.0 - TIME * 0.33);
		float g = fog_tex(vec2(fract(puv.x - rt * 0.45), puv.y + wob * 0.5)).g;
		float r = fog_tex(vec2(fract(puv.x - rt), puv.y + wob)).r;
		float amb = fog_amb(lat);
		float sl = shaft_lit(lon, lat) * (1.0 + atem * 0.5);
		float dk = clamp(drop / 0.6, 0.0, 1.0);
		float dbp = clamp(downbeat_pulse, 0.0, 1.0);
		float cm = 1.0 - 0.5 * comfort;
		float fd = fog_density * (1.0 - 0.40 * dk);
		vec3 fc = fog_color * amb + fog_lit_color * sl;
		col = mix(col, fc, clamp(g * 0.45 * fd, 0.0, 1.0));
		// Platten rutschen mit beat_step (springt auf dem Schlag, ruht dazwischen).
		float su_mid = beat_step * slab_mid_deg * cm / 360.0;
		float su_near = beat_step * slab_near_deg * cm / 360.0;
		vec4 nm = textureLod(near_a, vec2(fract(puv.x + su_mid), puv.y), 0.0);
		float cm_mid = smoothstep(0.0, 0.06, nm.r);
		col = mix(col, slab_color(0.0, nm.r, lon, lat, 0.55 * exp(-max(lat, 0.0) / 6.0) + 0.25, atem, dk, dbp), cm_mid);
		col = mix(col, fc, clamp(r * 0.85 * fd, 0.0, 1.0));
		vec4 nn = textureLod(near_a, vec2(fract(puv.x + su_near), puv.y), 0.0);
		float cm_near = smoothstep(0.0, 0.06, nn.g);
		col = mix(col, slab_color(nn.b, nn.g, lon, lat, 0.30 * exp(-max(lat, 0.0) / 4.0), atem, dk, dbp), cm_near);
		// Schacht flammt auf dem Taktanfang auf und weitet sich im Drop.
		col += shaft_color * sb * shaft_gain * (0.35 * dbp + 0.8 * dk) * (1.0 - cm_near);

		if (dir.y < 0.0) {
			vec4 gf = ground_fog_layer(dir, lon, bp);
			col = mix(col, gf.rgb, gf.a);
		}
		col *= tint * brightness;

		// Lesbarkeit in Weltkoordinaten: vorn-mitte/unten zusaetzlich dunkler.
		float wlon = atan(dir.x, -dir.z);
		float wlat = asin(clamp(dir.y, -1.0, 1.0));
		float front = exp(-(wlon / 0.62) * (wlon / 0.62)) * smoothstep(0.02, -0.30, wlat);
		col *= 1.0 - readability * 0.6 * front;

		// Feines Filmkorn gegen Banding in den tiefen Verlaeufen.
		float h = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
		col = max(col * (1.0 + h * 0.04) + h * 0.0003, vec3(0.0));
		COLOR = col;
	}
}
