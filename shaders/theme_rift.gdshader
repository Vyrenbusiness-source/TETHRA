shader_type sky;

// Welt-Thema "Rift": der Raum reisst. Gigantischer gezackter Spalt aus fahlem gruen-grauem
// Licht im Schwarz (tools/gen_theme_rift.py). Ebenen aus assets_game/themes/rift/:
//   Spalt    (tex_a/tex_b)     sky_rift.webp         DATEN-Panorama: R = Spalt-Feld (Schwelle im Shader),
//                                                    G = Streulicht, B = Bruchkanten-Haarrisse
//   Bruchstuecke (rows_a/rows_b) sky_rift_rows.webp  RGBA-TUNNEL-Textur (u = Winkel um -Z, v = ln(tan(a/2))/ln 4):
//                                                    schlanke Splitter, rasten per beat_step Reihe fuer Reihe
//   Brocken  (prisms_a/prisms_b) sky_rift_prisms.webp nahe RGBA-Ebene: grosse kantige Bruchstuecke,
//                                                    kreisen per beat_step (Parallax zur Ferne)
//   Staub    (stars_a/stars_b) sky_rift_stars.webp   Splitterstaub (Panorama)
// Uniform-Interface wie shaders/sky_panorama.gdshader. rows_a braucht Mipmaps.
//
// BEAT-VERTRAG (docs/worlds/beat_contract.md):
//   beat_step      Signatur: Bruchstueck-Reihen ruecken pro Schlag eine Reihe vor, Brocken kreisen
//                  in festen Schritten, rasten exakt auf dem Schlag ein
//   beat_pulse     der Spalt ATMET: Schwelle sinkt kurz, der Riss wird auf dem Schlag etwas breiter
//   downbeat_pulse breiterer Atemzug + Licht der Bruchkanten auf dem Taktanfang
//   bar_phase      eine Lichtwelle laeuft pro Takt durch die Bruchstueck-Reihen
//   beat_phase     feine Atmung der Kantenlichter innerhalb des Schlags
//   kiai/energy    Haarrisse und Staub minimal heller
//   drop           Riss WEITET sich (Schwelle -0.30), Korridor um die Achse leert sich, Brocken naeher
//   comfort        Flug halbiert, keine Lichtwelle
//
// FARBSATZ fuer Strecke/Kanten/Pads (fahles Gruen-Grau auf Schwarz, kein Neon):
//   Strecke (Belag)      #050706  fast schwarz, Alpha ~0.92
//   Spur-Trennlinien     #1a211d  Alpha ~0.55
//   Kanten (Rail/Rand)   #7f9486  Grau-Gruen, HDR x1.2
//   Abfanglinie          #b8d0c0  Spalt-Licht, HDR x1.5
//   Pads (Ruhe)          #0d120f  Fuellung, Rand #7f9486
//   Pads (gedrueckt)     #b8d0c0  Rand, Fuellung #28332c
//   Noten                #eef6f0  kaltes Weiss mit Gruenstich (hellstes Element)
//   Hold-Strahl          #7f9486 -> #b8d0c0 Verlauf
//   Treffer-Funken       #b8d0c0, Perfect #eef6f0
//   Umgebungslicht       #070a08, Glow-Schwelle wie Spiel (0.92)
//   Theme-Farbe (Hue)    0.40 (Graugruen, fast ohne Saettigung)

uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D rows_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D rows_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D stars_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D stars_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D prisms_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D prisms_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform float palette_mix : hint_range(0.0, 1.0) = 0.0;

uniform vec3 tint : source_color = vec3(1.0);
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_hdr : hint_range(1.0, 4.0) = 1.4;
uniform float beat_pulse : hint_range(0.0, 1.0) = 0.0;

uniform float beat_phase : hint_range(0.0, 1.0) = 0.0;
uniform float bar_phase : hint_range(0.0, 1.0) = 0.0;
uniform float beat_step = 0.0;
uniform float downbeat_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float kiai : hint_range(0.0, 1.0) = 0.0;
uniform float drop : hint_range(0.0, 0.6) = 0.0;
uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float comfort : hint_range(0.0, 1.0) = 0.0;

uniform vec3 pano_rotation = vec3(0.0);
uniform vec2 pano_offset = vec2(0.0);
uniform vec3 stars_rotation = vec3(0.0);
uniform vec2 stars_offset = vec2(0.0);

uniform float star_speed = 0.0;
uniform float star_phase = 0.0;
uniform float warp : hint_range(0.0, 1.0) = 0.0;
uniform float readability : hint_range(0.0, 1.0) = 0.35;

const float LN4 = 1.3862944;

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

// Stereografischer Zoom um die Flugrichtung (-Z), wie sky_panorama.
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

vec3 pano_at(sampler2D a, sampler2D b, vec2 uv) {
	if (palette_mix <= 0.001) {
		return dec(textureLod(a, uv, 0.0).rgb);
	}
	if (palette_mix >= 0.999) {
		return dec(textureLod(b, uv, 0.0).rgb);
	}
	return mix(dec(textureLod(a, uv, 0.0).rgb), dec(textureLod(b, uv, 0.0).rgb), palette_mix);
}

// Monolithen-Reihen: rgb = Kantenlicht (linear), a = Deckkraft.
vec4 rows_at(vec2 uv, float lod) {
	vec4 a = textureLod(rows_a, uv, lod);
	if (palette_mix <= 0.001) {
		return vec4(dec(a.rgb), a.a);
	}
	vec4 b = textureLod(rows_b, uv, lod);
	if (palette_mix >= 0.999) {
		return vec4(dec(b.rgb), b.a);
	}
	return vec4(mix(dec(a.rgb), dec(b.rgb), palette_mix), mix(a.a, b.a, palette_mix));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float lon = atan(dir.x, -dir.z);
	float lat = asin(clamp(dir.y, -1.0, 1.0));
	float mv = mix(1.0, 0.5, comfort);

	// Ferne Ebene: Nichts + Lichtspalt. Der Spalt atmet auf dem Schlag, oeffnet sich im Drop.
	vec2 puv = dir_uv(dir * euler(pano_rotation), pano_offset);
	vec3 fd = pano_at(tex_a, tex_b, puv);   // R = Feld, G = Streulicht, B = Haarrisse (Daten, linear)
	// Schwelle: der Riss atmet auf dem Schlag und weitet sich im Drop.
	float thr = 0.56 - 0.10 * beat_pulse * mv - 0.08 * downbeat_pulse * mv - 0.30 * drop;
	float core = smoothstep(thr - 0.035, thr + 0.035, fd.r);
	vec3 pale = vec3(0.47, 0.64, 0.52);
	vec3 far_col = pale * (core * 1.25 + fd.r * fd.r * 0.30 * (1.0 + 0.8 * drop))
		+ vec3(0.20, 0.27, 0.22) * fd.g * 0.10 * (1.0 + 0.6 * beat_pulse + 0.5 * drop)
		+ pale * fd.b * 0.32 * (0.5 + 0.5 * beat_pulse + 0.5 * downbeat_pulse * mv + 0.3 * kiai);

	if (AT_CUBEMAP_PASS) {
		COLOR = far_col * tint * brightness * 0.5;
	} else {
		// Reihen-Tunnel: v = Tiefe. beat_step -> eine Reihe pro Schlag nach aussen (Faktor 2^(1/4)).
		float a_ang = acos(clamp(-dir.z, -1.0, 1.0));
		float r = tan(0.5 * a_ang);
		float th = atan(dir.y, dir.x);
		float rho = log(max(r, 1e-4));
		float flight = beat_step * 0.125 * mv + TIME * 0.0015 + drop * 0.20 * mv;
		vec2 ruv = vec2(th * (0.5 / PI) + 0.5, rho / LN4 - flight);
		float lod = clamp(log2(1.56 / max(r, 1e-3)), 0.0, 7.0);
		vec4 rw = rows_at(ruv, lod);

		// Tiefe: Ferne verschwimmt im Dunst, nahe Platten tragen mehr Kantenlicht.
		float fog = smoothstep(0.012, 0.11, r);
		float near_k = mix(0.20, 1.0, smoothstep(0.03, 0.34, r));
		// Drop: ein Korridor um die Flugachse leert sich, die Kante am Rand leuchtet auf.
		float r_open = drop * 0.30;
		float open_m = smoothstep(r_open, r_open + 0.035, r);
		float edge_open = exp(-pow((r - r_open - 0.02) / 0.03, 2.0)) * (drop > 0.001 ? 1.0 : 0.0);
		float cover = rw.a * fog * open_m;

		// Lichtwelle: einmal pro Takt von innen nach aussen durch die Reihen.
		float wave = pow(0.5 + 0.5 * cos(TAU * (rho / LN4 * 1.0 - bar_phase)), 6.0) * (1.0 - comfort);
		float breath = 0.80 + 0.20 * exp(-beat_phase * 5.0);
		float rim_gain = near_k * breath
			* (1.0 + 0.55 * downbeat_pulse * mv + 0.30 * beat_pulse + 0.30 * wave * (0.4 + energy)
				+ 0.10 * kiai + 0.5 * drop * edge_open * 3.0);
		vec3 rim = rw.rgb * rim_gain * fog * open_m;

		// Staub: zwei ueberblendete Zoom-Lagen, ein Zyklus = 4 Schlaege.
		mat3 srot = euler(stars_rotation);
		float ph = beat_step * 0.25 * mv + star_phase + TIME * star_speed;
		vec3 st = vec3(0.0);
		for (int layer = 0; layer < 2; layer++) {
			float a = fract(ph + float(layer) * 0.5);
			float w = 0.5 - 0.5 * cos(a * TAU);
			float s = exp2(a - 0.5);
			vec3 d2 = zoom_dir(dir, s);
			vec2 suv = dir_uv(d2 * srot, stars_offset + vec2(TIME * 0.0006, 0.0));
			st += pano_at(stars_a, stars_b, suv) * w;
		}
		float sl = dot(st, vec3(0.2126, 0.7152, 0.0722));
		st *= star_brightness * mix(1.0, star_hdr, smoothstep(0.30, 0.8, sl));
		st *= 1.0 + 0.5 * beat_pulse + 0.4 * energy + 0.4 * drop;

		// Nahe Prismen: Orbit per beat_step (rastet auf dem Schlag ein), schneller als die Ferne.
		// Drop: naeher (Zoom) und etwas schneller.
		float yaw = (beat_step * 0.045 + drop * 0.12) * mv + TIME * 0.0025;
		float cy = cos(yaw), sy = sin(yaw);
		vec3 pd = zoom_dir(dir, 1.0 + 0.45 * drop * mv);
		pd = vec3(cy * pd.x + sy * pd.z, pd.y, -sy * pd.x + cy * pd.z);
		vec2 pruv = dir_uv(pd, vec2(0.0));
		vec4 pr = textureLod(prisms_a, pruv, 0.0);
		if (palette_mix > 0.001) {
			pr = mix(pr, textureLod(prisms_b, pruv, 0.0), palette_mix);
		}
		float pcov = pr.a * (1.0 - smoothstep(0.0, 0.5, -lat + 0.05) * 0.0);
		vec3 prim = dec(pr.rgb) * (1.0 + 0.5 * downbeat_pulse * mv + 0.25 * beat_pulse + 0.4 * drop);
		far_col = far_col * (1.0 - pcov);
		rim *= 1.0 - pcov;
		st *= 1.0 - pcov;

		vec3 col = (far_col * (1.0 - cover) + prim * pcov + rim + st * (1.0 - 0.85 * cover)) * tint * brightness;

		// Lesbarkeit in Weltkoordinaten: vorn-mitte/unten zusaetzlich dunkler.
		float front = exp(-(lon / 0.62) * (lon / 0.62)) * smoothstep(0.22, -0.30, lat);
		col *= 1.0 - readability * 0.6 * front;

		// Dither gegen Banding in den dunklen Verlaeufen.
		float h = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
		col = max(col * (1.0 + h * 0.03) + h * 0.00025, vec3(0.0));
		COLOR = col;
	}
}
