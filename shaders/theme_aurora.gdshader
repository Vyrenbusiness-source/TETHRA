shader_type sky;

// Welt-Thema "Aurora" / Stil "Frost": dunkle, kalte Polarnacht. Bedrohliches
// Gletscher-Massiv an den Seiten, Eisberge, spiegelndes Eismeer, kalter Nebel,
// ganz fahle Polarlicht-Baender in EINER Farbfamilie (Eis-Tuerkis/Stahlgrau).
// Offline erzeugt: tools/gen_theme_aurora.py -> assets_game/themes/aurora/
//   aurora.webp         (tex_a/tex_b)       Szene RGBA. Alpha oben = Himmel
//                                           sichtbar, unten = Spiegel-Staerke.
//   aurora_stars.webp   (stars_a/stars_b)   Sterne, Parallax/Flug wie sky_panorama
//   aurora_aurora.webp  (aurora_a/aurora_b) Polarlicht-Ebene (obere Halbkugel),
//                                           weht hier im Shader, wird gespiegelt.
// Uniform-Interface wie shaders/sky_panorama.gdshader (tint, brightness,
// beat_pulse, star_speed/star_phase/warp, tex_a/tex_b/palette_mix, ...) plus:
//   aurora_flow 0..2      Staerke des Wehens (0 = starr)
//   aurora_speed          Zeitfaktor des Wehens (ruhige Songs ~0.6..1.0)
//   aurora_phase          Zeit-Versatz (fuer Screenshots/Sync)
//   aurora_intensity      Helligkeit der Baender
//   aurora_pulse 0..1     wie stark die Baender auf dem Beat atmen
//   fog_amount, fog_speed treibender kalter Nebel am Horizont
//   reflection 0..1       Spiegelung der Baender/Sterne im Wasser
// Abbildung + Kodierung wie sky_panorama (u = atan(d.x,-d.z)/2pi+0.5,
// Texturen wurzel-kodiert: linear = textur^2, Alpha ebenso). Die
// aurora.webp.import muss process/fix_alpha_border=false behalten (Alpha 0
// hinter Eisbergen traegt echte Farbe).
//
// FARBSATZ "Frost" fuer Strecke/Kanten/Pads (sRGB, keine Neon-Toene):
//   Strecke (road base_color)   #05080A  fast schwarz, kalt
//   Kanten / Spur-Licht         #8FB3B8  Stahl-Eis (Emission ~0.6)
//   Pads / Receptor             #A9C4C8  fahles Eis
//   Noten                       #D6E6E8  Eis-Weiss (heller als alles im Himmel)
//   Akzent / Treffer            #6F9AA0  gedecktes Tuerkis
//   Kiai / Puls                 #CFE3E5  Frost-Weiss, nur heller, nie bunter
//   Umgebungslicht              #0C1215
//
// INTEGRATION wie sky_panorama (Sky + ShaderMaterial, radiance 32, incremental).

uniform sampler2D tex_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D tex_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D stars_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D stars_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D aurora_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D aurora_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform float palette_mix : hint_range(0.0, 1.0) = 0.0;

uniform vec3 tint : source_color = vec3(1.0);
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_hdr : hint_range(1.0, 4.0) = 1.3;
uniform float beat_pulse : hint_range(0.0, 1.0) = 0.0;

uniform vec3 pano_rotation = vec3(0.0);
uniform vec2 pano_offset = vec2(0.0);
uniform vec3 stars_rotation = vec3(0.0);
uniform vec2 stars_offset = vec2(0.0);

uniform float star_speed = 0.0;
uniform float star_phase = 0.0;
uniform float warp : hint_range(0.0, 1.0) = 0.0;
uniform float readability : hint_range(0.0, 1.0) = 0.35;

uniform float aurora_flow : hint_range(0.0, 2.0) = 1.0;
uniform float aurora_speed : hint_range(0.0, 4.0) = 1.0;
uniform float aurora_phase = 0.0;
uniform float aurora_intensity : hint_range(0.0, 4.0) = 1.0;
uniform float aurora_pulse : hint_range(0.0, 1.0) = 0.35;
uniform vec3 aurora_tint : source_color = vec3(1.0);
uniform float fog_amount : hint_range(0.0, 2.0) = 1.0;
uniform float fog_speed : hint_range(0.0, 4.0) = 1.0;
uniform float reflection : hint_range(0.0, 1.0) = 1.0;

const int WARP_TAPS = 16;
const vec3 FOG_COL = vec3(0.0075, 0.0168, 0.0232); // #15232A linear

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

vec3 zoom_dir(vec3 d, float s) {
	float c = -d.z;
	vec2 perp = d.xy;
	float l = length(perp);
	if (l < 1e-5) {
		return d;
	}
	float t = l / (1.0 + c) / s;
	float t2 = t * t;
	float sn = 2.0 * t / (1.0 + t2);
	float cs = (1.0 - t2) / (1.0 + t2);
	return vec3(perp / l * sn, -cs);
}

vec3 dec(vec3 c) {
	return c * c;
}

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

vec4 scene_at(vec2 uv) {
	vec4 a = textureLod(tex_a, uv, 0.0);
	if (palette_mix > 0.001) {
		a = mix(a, textureLod(tex_b, uv, 0.0), palette_mix);
	}
	return vec4(dec(a.rgb), a.a * a.a);
}

vec3 stars_at(vec3 d, mat3 srot) {
	vec2 uv = dir_uv(d * srot, stars_offset);
	vec3 s = dec(textureLod(stars_a, uv, 0.0).rgb);
	if (palette_mix > 0.001) {
		s = mix(s, dec(textureLod(stars_b, uv, 0.0).rgb), palette_mix);
	}
	return s;
}

// Sternen-Ebene mit Flug/Warp wie sky_panorama (zwei Hann-ueberblendete Zoom-Lagen).
vec3 star_field(vec3 dir, mat3 srot, bool allow_warp, vec2 fc) {
	float ph = star_phase + TIME * star_speed;
	bool moving = abs(star_speed) > 0.0001 || abs(fract(star_phase)) > 0.0001;
	vec3 st = vec3(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float a = fract(ph + float(layer) * 0.5);
		float w = 0.5 - 0.5 * cos(a * TAU);
		if (!moving) {
			a = 0.5;
			w = layer == 0 ? 1.0 : 0.0;
		}
		if (w < 0.002) {
			continue;
		}
		float s = exp2(a - 0.5);
		vec3 acc = vec3(0.0);
		if (allow_warp && warp > 0.001) {
			float wsum = 0.0;
			float jit = hash12(fc + float(layer) * 17.0);
			for (int i = 0; i < WARP_TAPS; i++) {
				float k = (float(i) + jit) / float(WARP_TAPS);
				float wk = 1.0 - 0.75 * k;
				acc += stars_at(zoom_dir(dir, s * (1.0 + warp * 0.14 * k)), srot) * wk;
				wsum += wk;
			}
			acc *= (1.0 + warp * 3.0) / wsum;
		} else {
			acc = stars_at(zoom_dir(dir, s), srot);
		}
		st += acc * w;
	}
	float sl = dot(st, vec3(0.2126, 0.7152, 0.0722));
	st *= star_brightness * mix(1.0, star_hdr, smoothstep(0.55, 1.0, sl));
	return st * (1.0 + beat_pulse * 0.35);
}

// Polarlicht-Ebene: u wie Panorama, v = 1 - Hoehe/90 Grad. Wehen = begrenzte,
// langsam laufende Verschiebungen (kein Aufziehen ueber die Zeit), oben staerker.
vec3 aurora_at(vec3 d, float tt) {
	float u = atan(d.x, -d.z) * (0.5 / PI) + 0.5 + pano_offset.x;
	float h = asin(clamp(d.y, 0.0, 1.0)) / (0.5 * PI);
	float sway = 0.35 + 0.65 * clamp(h * 5.0, 0.0, 1.0);
	float du = aurora_flow * sway * (
			0.0040 * sin(TAU * u * 3.0 + tt * 0.21 + 1.7 * sin(TAU * u * 2.0 - tt * 0.11))
			+ 0.0016 * sin(TAU * u * 9.0 - tt * 0.43));
	float dv = aurora_flow * 0.0055 * sin(TAU * u * 5.0 + tt * 0.27 + sin(TAU * u * 13.0 + tt * 0.5));
	vec2 uv = vec2(fract(u + du), clamp(1.0 - h + dv, 0.001, 0.999));
	vec3 c = dec(textureLod(aurora_a, uv, 0.0).rgb);
	if (palette_mix > 0.001) {
		c = mix(c, dec(textureLod(aurora_b, uv, 0.0).rgb), palette_mix);
	}
	// Strahlen-Schimmer wandert seitlich, langsames Atmen entlang des Bandes.
	float sh = 0.86 + 0.14 * sin(TAU * u * 180.0 + tt * 0.9 + 3.0 * sin(TAU * u * 37.0 - tt * 0.6));
	float br = 0.82 + 0.18 * sin(tt * 0.31 + TAU * u * 2.0);
	c *= mix(1.0, sh * br, clamp(aurora_flow, 0.0, 1.0));
	return c * aurora_tint * aurora_intensity * (1.0 + beat_pulse * aurora_pulse);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 pd = dir * euler(pano_rotation);
	vec4 sc = scene_at(dir_uv(pd, pano_offset));
	vec3 col = sc.rgb * (1.0 + beat_pulse * 0.04);

	if (AT_CUBEMAP_PASS) {
		COLOR = col * tint * brightness * 0.5;
	} else {
		float tt = TIME * aurora_speed + aurora_phase;
		mat3 srot = euler(stars_rotation);
		float lon = atan(pd.x, -pd.z);
		float lat = asin(clamp(pd.y, -1.0, 1.0));
		if (pd.y >= 0.0) {
			// Himmel: Baender + Sterne hinter Bergen/Eis (Alpha = Himmel sichtbar).
			float ext = smoothstep(0.0, 0.16, pd.y); // Extinktion am Horizont
			vec3 st = star_field(dir, srot, true, FRAGCOORD.xy) * ext;
			col += (aurora_at(pd, tt) + st) * sc.a;
		} else if (sc.a > 0.002 && reflection > 0.001) {
			// Spiegelung im Eismeer: gespiegelte Richtung + ruhige, wandernde Wellen
			// (in Bodenkoordinaten, am Horizont ausgeblendet gegen Flimmern).
			float dep = -lat;
			float r = 1.0 / max(tan(dep), 1e-3);
			vec2 g = vec2(sin(lon), cos(lon)) * r;
			float rip = sin(g.x * 1.9 + tt * 0.55 + sin(g.y * 0.7 - tt * 0.3))
					* sin(g.y * 2.6 - tt * 0.42) + 0.5 * sin(g.x * 4.3 - g.y * 3.1 + tt * 0.8);
			float fade = smoothstep(0.004, 0.06, dep);
			float ml = dep + rip * 0.0045 * fade;
			float mlon = lon + rip * 0.0015 * fade;
			vec3 m = vec3(cos(ml) * sin(mlon), sin(ml), -cos(ml) * cos(mlon));
			vec3 rc = aurora_at(m, tt) * 0.85;
			vec3 mw = m * transpose(euler(pano_rotation)); // zurueck in Weltrichtung
			rc += star_field(mw, srot, false, FRAGCOORD.xy) * smoothstep(0.0, 0.06, m.y) * 0.55;
			col += rc * sc.a * reflection;
		}

		// Kalter Nebel: treibende Baenke am Horizont (ueber und unter der Kimm).
		if (fog_amount > 0.001) {
			float la = abs(lat) * (180.0 / PI);
			float band = exp(-la / 1.4) * 0.55 + exp(-la / 5.0) * 0.18;
			if (band > 0.004) {
				float ft = tt * 0.012 * fog_speed / max(aurora_speed, 0.001);
				vec2 fp = vec2(lon * 9.0 + ft * 6.0, lat * 40.0 - ft);
				float n = vnoise(fp) * 0.6 + vnoise(fp * 2.3 + vec2(ft * 9.0, 3.1)) * 0.4;
				float f = clamp(band * (0.25 + 1.1 * n) * fog_amount * 0.45, 0.0, 0.6);
				col = mix(col, FOG_COL * (1.0 + beat_pulse * 0.06), f);
			}
		}

		col *= tint * brightness;

		// Lesbarkeit in Weltkoordinaten: vorn-mitte/unten zusaetzlich dunkler.
		float wlon = atan(dir.x, -dir.z);
		float wlat = asin(clamp(dir.y, -1.0, 1.0));
		float front = exp(-(wlon / 0.62) * (wlon / 0.62)) * smoothstep(0.22, -0.30, wlat);
		col *= 1.0 - readability * 0.6 * front;

		float hd = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
		col = max(col * (1.0 + hd * 0.03) + hd * 0.00025, vec3(0.0));
		COLOR = col;
	}
}
