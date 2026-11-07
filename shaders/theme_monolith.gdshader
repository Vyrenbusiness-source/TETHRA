shader_type sky;

// Welt-Thema "Monolith": endlose Reihen schwebender schwarzer Monolithen im Nichts,
// eine einzige kalte weisse Kantenlichtquelle (tools/gen_theme_monolith.py).
// Ebenen aus assets_game/themes/monolith/:
//   Panorama (tex_a/tex_b)     sky_monolith.webp        Nichts, Dunst, Lichtspalt, ferne Silhouetten
//   Reihen   (rows_a/rows_b)   sky_monolith_rows.webp   RGBA-TUNNEL-Textur (kein Panorama!):
//                                                      u = Winkel um -Z, v = ln(tan(a/2))/ln 4,
//                                                      periodisch -> naht- und ueberblendungsfreier Flug
//   Prismen  (prisms_a/prisms_b) sky_monolith_prisms.webp nahe RGBA-Ebene: grosse schwarze Prismen,
//                                                      kreisen gleichmaessig (0.69 Grad/s, nie ueber beat_step)
//   Staub    (stars_a/stars_b) sky_monolith_stars.webp  schwebende Partikel (Panorama, Parallax)
// Uniform-Interface wie shaders/sky_panorama.gdshader (Panorama-Abbildung
// u = atan(d.x,-d.z)/2pi+0.5, v = 0.5-asin(d.y)/pi, Wurzel-Kodierung linear = pow(tex, 2)).
// rows_a braucht Mipmaps (Import: mipmaps/generate=true), sonst flimmern ferne Reihen.
//
// BEAT-VERTRAG (docs/worlds/beat_contract.md):
//   beat_step      Signatur: die Reihen fliessen glatt auf den Spieler zu, EINE Reihe je Schlag (Faktor
//                  2^(1/4) in der Tiefe), auf dem Schlag leicht schneller (kein Stop-and-go)
//   downbeat_pulse Kantenlicht aller Platten + Lichtspalt akzentuiert auf dem Taktanfang
//   bar_phase      eine Lichtwelle laeuft pro Takt durch die Reihen nach aussen
//   beat_phase     feine Kantenlicht-Atmung innerhalb des Schlags
//   beat_pulse     Lichtspalt + Kantenlicht atmen auf dem Schlag
//   kiai/energy    Staub und Kantenlicht minimal heller
//   drop           Formation OEFFNET sich: ein Korridor um die Flugachse leert sich,
//                  die Reihen schieben nach aussen, die Kanten am Korridor leuchten auf
//   comfort        Flug halbiert, keine Lichtwelle
//
// FARBSATZ fuer Strecke/Kanten/Pads (streng kaltes Weiss auf Schwarz, KEIN Neon):
//   Strecke (Belag)      #050608  fast schwarz, Alpha ~0.92
//   Spur-Trennlinien     #1a1e26  Alpha ~0.55
//   Kanten (Rail/Rand)   #8c98aa  kaltes Grau, HDR x1.2
//   Abfanglinie          #cfdcf0  Kantenlicht-Weiss, HDR x1.5
//   Pads (Ruhe)          #0e1117  Fuellung, Rand #8c98aa
//   Pads (gedrueckt)     #cfdcf0  Rand, Fuellung #2a313d
//   Noten                #f4f8ff  reines kaltes Weiss (hellstes Element)
//   Hold-Strahl          #8c98aa -> #cfdcf0 Verlauf
//   Treffer-Funken       #cfdcf0, Perfect #f4f8ff
//   Umgebungslicht       #080a0e, Glow-Schwelle wie Spiel (0.92)
//   Theme-Farbe (Hue)    0.60 (Stahlblau, fast ohne Saettigung)

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

// Komfort (beat_contract.md): nur Gier um die Hochachse. x (Nicken) und z (Rollen)
// werden ignoriert, damit der Horizont immer waagerecht bleibt.
mat3 euler(vec3 e) {
	float cy = cos(e.y), sy = sin(e.y);
	return mat3(vec3(cy, 0.0, -sy), vec3(0.0, 1.0, 0.0), vec3(sy, 0.0, cy));
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
	vec3 far_col = pano_at(tex_a, tex_b, puv);
	float fl = dot(far_col, vec3(0.2126, 0.7152, 0.0722));
	float slit = smoothstep(0.08, 0.5, fl);
	far_col *= 1.0 + (0.45 * beat_pulse + 0.35 * downbeat_pulse * mv + 1.1 * drop) * (0.15 + 2.2 * slit);
	far_col *= 1.0 + 0.10 * kiai;

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

		// Nahe Prismen: gleichmaessige Gier ueber TIME (0.69 Grad/s, Komfort halb),
		// nie ueber beat_step/drop (Komfort-Regeln). Drop: naeher (Zoom).
		float yaw = TIME * 0.012 * mv;
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
