shader_type sky;

// Welt-Thema "Bosskampf": monochromes Blutrot auf Schwarz (tools/gen_theme_boss.py).
// Drei Ebenen aus assets_game/themes/boss/:
//   Himmel   (tex_a/tex_b)     sky_boss.webp        Glut-Horizont, Vulkan-Grate,
//                                                   Gewittertuerme, Wolkenbaenke
//   Glut     (stars_a/stars_b) sky_boss_embers.webp aufsteigende Funken (Parallax)
//   Rauch    (veil_tex)        sky_boss_veil.webp   Rauchsaeulen ueber dem Horizont
//                                                   (RGBA: Randlicht add., A = Abdunklung;
//                                                   eigener Parallax, schiebt auf beat_step)
//   Blitz    (flash_tex)       sky_boss_flash.webp  R/G/B = drei Blitz-Gruppen
// Uniform-Interface wie shaders/sky_panorama.gdshader (gleiche Namen, gleiche
// Abbildung u = atan(d.x,-d.z)/2pi+0.5, v = 0.5-asin(d.y)/pi, Wurzel-Kodierung
// linear = pow(textur, 2.0)) -> Austausch des Shaders ohne Aufrufer-Aenderung.
//
// BLITZ (zusaetzlich):
//   lightning 0..1     Blitz-Huellkurve, vom Aufrufer auf Downbeats gesetzt
//                      (z.B. 1.0 auf den Downbeat, dann ~0.25 s abklingen lassen).
//                      Selten einsetzen (z.B. jeder 2.-4. Takt in Kiai/Drops).
//   lightning_cell     0/1/2 = Gruppe (je genau ein Turm im Komfort-Sichtfeld:
//                      0 links, 1 rechts, 2 rechts aussen), -1 = automatisch
//                      wechselnd. Pro Schlag eine andere Gruppe setzen wirkt am besten.
//   lightning_color    stumpfes Rot-Weiss (Standard), lightning_strength Gesamtpegel.
//   Garantien: Blitz-Licht ist in der Textur auf den oberen Himmel begrenzt und
//   wird hier in Weltkoordinaten zusaetzlich gesperrt: nie unter ~3 Grad Hoehe,
//   nie vorn-mitte (|Laenge| < 12 Grad, ueber der Strecke), nie Vollbild
//   (je Gruppe nur einzelne Zellen von wenigen Grad).
// GLUT (zusaetzlich):
//   ember_rise         Aufstiegs-Zyklen/s (0 = steht). Funken steigen ~5 Grad
//                      und blenden dabei weich aus/ein (2 Lagen, Summe = 1).
//   ember_flicker 0..1 Flackern der Funken.
//
// INTEGRATION (z.B. mania_3d.gd _build_sky): wie sky_panorama, nur Pfade:
//   mat.shader = load("res://shaders/theme_boss.gdshader")
//   mat.set_shader_parameter("tex_a", load("res://assets_game/themes/boss/sky_boss.webp"))
//   mat.set_shader_parameter("stars_a", load("res://assets_game/themes/boss/sky_boss_embers.webp"))
//   mat.set_shader_parameter("veil_tex", load("res://assets_game/themes/boss/sky_boss_veil.webp"))
//   mat.set_shader_parameter("flash_tex", load("res://assets_game/themes/boss/sky_boss_flash.webp"))
//   pro Downbeat (selten): mat.set_shader_parameter("lightning_cell", n % 3); _flash = 1.0
//   pro Frame: _flash = move_toward(_flash, 0.0, delta * 4.0)
//              mat.set_shader_parameter("lightning", _flash)
//
// FARBSATZ fuer Strecke/Kanten/Pads (streng monochrom Blutrot, KEIN Orange/Neon):
//   Strecke (Belag)      #070203  fast schwarz, Hauch Rot, Alpha ~0.92
//   Spur-Trennlinien     #3a0609  dunkles Blutrot, Alpha ~0.55
//   Kanten (Rail/Rand)   #8c0610  tiefes Blutrot (= Himmels-Grundton), HDR x1.3
//   Abfanglinie          #c01a1e  helles Blutrot, HDR x1.6 (hellster Strecken-Ton)
//   Pads (Ruhe)          #2a0507  Fuellung, Rand #8c0610
//   Pads (gedrueckt)     #b0141a  Rand, Fuellung #5a080c
//   Noten                #e8d4d4  stumpfes Rot-Weiss (einziges helles Element ->
//                        maximale Lesbarkeit vor dem dunklen Rot)
//   Hold-Strahl          #8c0610 -> #c01a1e Verlauf
//   Treffer-Funken       #c01a1e, Perfect #e8d4d4
//   Umgebungslicht       #140405, Glow-Schwelle wie Spiel (0.92)
//   Theme-Farbe (Hue)    0.99 (fuer _sky_pal_for_hue / UI-Akzente)
//
// NAHE EBENE shards_tex (sky_boss_shards.webp, RGBA): Glut-Brocken/Truemmer im Stil der Fraktal-Splitter;
//   Parallax zur Fernebene, Gier rastet mit beat_step ein, Drop = schneller/naeher/heller
//   (Mitte/unten in Weltkoordinaten frei). Bindung: mat.set_shader_parameter("shards_tex", load("res://assets_game/themes/boss/sky_boss_shards.webp")).
// BEAT-VERTRAG (docs/worlds/beat_contract.md):
//   beat_step       Glut-HERZSCHLAG: die Funken-Ebene springt auf jedem Schlag ein
//                   Stueck aufwaerts und ruht bis zum naechsten (rastet exakt ein).
//   downbeat_pulse  Takt-Akzent: Glut-Horizont und Turm-Raender gluehen eine Spur
//                   heller und laenger als beat_pulse.
//   drop            Verwandlung: Glut-Horizont weitet sich nach oben, Funken werden
//                   hochgesogen und dichter; Luma-Anstieg gedeckelt.
//   kiai, energy    Grundglut atmet minimal mit; comfort halbiert alle Bewegung.
//   beat_phase, bar_phase  Saegezaehne (Preview-Kontrolle, Funken-Flackern).
// Pro Frame (alles optional, wie sky_panorama):
//   beat_pulse 0..1    Glut-Horizont + beleuchtete Wolkenraender atmen auf dem Beat
//   palette_mix 0..1   Ueberblendung tex_a/stars_a -> tex_b/stars_b
//   pano_rotation / stars_rotation / pano_offset / stars_offset
//   star_speed / star_phase / warp   Flug der Glut-Ebene (wie Sterne)
//   tint, brightness, star_brightness, star_hdr, readability
// Kosten: 1-2 Himmel-Fetches + 1 Blitz-Fetch (nur wenn lightning > 0) +
// 2..4 Glut-Fetches (x WARP_TAPS bei warp > 0).

uniform sampler2D tex_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D tex_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D stars_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D stars_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D veil_tex : filter_linear, repeat_enable, hint_default_black;
uniform sampler2D flash_tex : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D shards_tex : source_color, filter_linear, repeat_enable, hint_default_transparent;
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

uniform float lightning : hint_range(0.0, 1.0) = 0.0;
uniform int lightning_cell : hint_range(-1, 2) = -1;
uniform vec3 lightning_color : source_color = vec3(0.80, 0.40, 0.40);
uniform float lightning_strength : hint_range(0.0, 3.0) = 1.0;
uniform float ember_rise = 0.12;
uniform float ember_flicker : hint_range(0.0, 1.0) = 0.6;

const int WARP_TAPS = 12;

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

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// Glut-Ebene an Richtung d mit Versatz rise (x: Lagen-Versatz, y: Aufstieg).
vec3 embers_at(vec3 d, mat3 srot, vec2 rise) {
	vec2 uv = dir_uv(d * srot, stars_offset + rise);
	if (palette_mix <= 0.001) {
		return dec(textureLod(stars_a, uv, 0.0).rgb);
	}
	if (palette_mix >= 0.999) {
		return dec(textureLod(stars_b, uv, 0.0).rgb);
	}
	return mix(dec(textureLod(stars_a, uv, 0.0).rgb), dec(textureLod(stars_b, uv, 0.0).rgb), palette_mix);
}

// Weiches Flackern je Funke (Gitterzellen ~ Funkengroesse, zeitlich glatt).
float flicker(vec2 uv) {
	vec2 c = floor(uv * vec2(1024.0, 512.0));
	float h = hash12(c);
	float s = sin(TIME * (3.0 + 5.0 * h) + h * 40.0) * 0.5 + 0.5;
	return 1.0 - ember_flicker * 0.6 * s * s;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float lon = atan(dir.x, -dir.z);
	float lat = asin(clamp(dir.y, -1.0, 1.0));

	// Himmel
	vec2 puv = dir_uv(dir * euler(pano_rotation), pano_offset);
	vec3 sky_col;
	if (palette_mix <= 0.001) {
		sky_col = dec(textureLod(tex_a, puv, 0.0).rgb);
	} else if (palette_mix >= 0.999) {
		sky_col = dec(textureLod(tex_b, puv, 0.0).rgb);
	} else {
		sky_col = mix(dec(textureLod(tex_a, puv, 0.0).rgb), dec(textureLod(tex_b, puv, 0.0).rgb), palette_mix);
	}
	// Puls hebt die hellen Glut-Bereiche (Horizont, Wolkenraender), Schwarz bleibt.
	float nl = dot(sky_col, vec3(0.2126, 0.7152, 0.0722));
	sky_col *= 1.0 + beat_pulse * (0.12 + 9.0 * nl);
	float mv = 1.0 - 0.5 * comfort;
	// Takt-Akzent und Drop wirken auf den Glut-Horizont (Breitenband), nie auf die Mitte.
	float hband = exp(-max(lat, 0.0) / 0.20) * smoothstep(-0.06, 0.03, lat);
	float dp = drop * (1.0 - 0.5 * comfort);
	sky_col *= 1.0 + downbeat_pulse * mv * (0.06 + 3.5 * nl) * (0.4 + 0.6 * hband);
	sky_col *= 1.0 + dp * (0.12 * hband + 0.9 * nl * (0.3 + hband)) + 0.05 * kiai * hband * (0.6 + energy);
	// Drop weitet die Glut: heller Dunstsaum steigt ueber den Horizont.
	sky_col += vec3(0.020, 0.0010, 0.0016) * dp * 0.8 * exp(-max(lat - 0.02, 0.0) / (0.10 + 0.8 * dp)) * smoothstep(-0.04, 0.03, lat);

	// Tiefenebene Rauch: eigener Versatz (langsame Drift + Schlag-Ruck auf beat_step).
	{
		vec2 vo = pano_offset + vec2(TIME * 0.0012 + beat_step * 0.0016 * mv, 0.0);
		vec4 vl = textureLod(veil_tex, dir_uv(dir * euler(pano_rotation), vo), 0.0);
		vec3 vlight = dec(vl.rgb) * (1.0 + beat_pulse * 0.25 + downbeat_pulse * 0.8 * mv + dp * 0.9);
		sky_col = sky_col * vl.a + vlight;
	}

	// Blitz: eine Gruppe, flackernd, in Weltkoordinaten gesperrt.
	vec3 fl = vec3(0.0);
	if (lightning > 0.001) {
		int cell = lightning_cell;
		if (cell < 0) {
			cell = int(hash11(floor(TIME * 0.45)) * 2.999);
		}
		vec3 f = dec(textureLod(flash_tex, puv, 0.0).rgb);
		float g = cell == 0 ? f.r : (cell == 1 ? f.g : f.b);
		// Mehrfach-Entladung: kurze Aussetzer statt gleichmaessigem Leuchten.
		float st = hash11(floor(TIME * 22.0) + float(cell) * 7.0);
		float strobe = mix(0.45, 1.0, step(0.35, st)) * (0.85 + 0.15 * st);
		float gate = smoothstep(0.045, 0.075, lat) * smoothstep(0.20, 0.28, abs(lon));
		float env = lightning * lightning;
		fl = lightning_color * (g * env * strobe * gate * lightning_strength * 1.15);
	}

	if (AT_CUBEMAP_PASS) {
		COLOR = (sky_col + fl * 0.5) * tint * brightness * 0.5;
	} else {
		// Glut-Ebene: Aufstieg (2 ueberblendete Lagen) x optional Flug-Zoom.
		mat3 srot = euler(stars_rotation);
		float ph = star_phase + TIME * star_speed;
		bool moving = abs(star_speed) > 0.0001 || abs(fract(star_phase)) > 0.0001;
		bool rising = abs(ember_rise) > 0.0001 || abs(beat_step) > 0.0001;
		// Herzschlag: beat_step schiebt die Funken je Schlag ein Stueck hoch (8-Schlag-Zyklus).
		float rp = TIME * ember_rise + beat_step * 0.125 * mv;
		vec3 em = vec3(0.0);
		for (int rl = 0; rl < 2; rl++) {
			float ra = fract(rp + float(rl) * 0.5);
			float rw = 0.5 - 0.5 * cos(ra * TAU);
			if (!rising) {
				ra = 0.5;
				rw = rl == 0 ? 1.0 : 0.0;
			}
			if (rw < 0.002) {
				continue;
			}
			vec2 rise = vec2(float(rl) * 0.37, (ra - 0.5) * 0.03 - dp * 0.012);
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
				if (warp > 0.001) {
					float wsum = 0.0;
					float jit = hash12(FRAGCOORD.xy + float(layer) * 17.0);
					for (int i = 0; i < WARP_TAPS; i++) {
						float k = (float(i) + jit) / float(WARP_TAPS);
						float wk = 1.0 - 0.75 * k;
						acc += embers_at(zoom_dir(dir, s * (1.0 + warp * 0.14 * k)), srot, rise) * wk;
						wsum += wk;
					}
					acc *= (1.0 + warp * 3.0) / wsum;
				} else {
					acc = embers_at(zoom_dir(dir, s), srot, rise);
				}
				em += acc * w * rw;
			}
		}
		if (ember_flicker > 0.001) {
			em *= flicker(dir_uv(dir * srot, stars_offset));
		}
		float el = dot(em, vec3(0.2126, 0.7152, 0.0722));
		em *= star_brightness * mix(1.0, star_hdr, smoothstep(0.12, 0.35, el));
		em *= 1.0 + beat_pulse * 0.6 + downbeat_pulse * 0.35 * mv + dp * 0.9;

		vec3 col = (sky_col + em + fl) * tint * brightness;

		// Nahe Objekt-Ebene (Stil Fraktal-Splitter): Brocken ziehen am Spieler vorbei,
		// Gier rastet mit beat_step auf dem Schlag ein; Drop = schneller/naeher/heller.
		{
			float s_mv = 1.0 - 0.5 * comfort;
			float s_dp = drop * (1.0 - 0.5 * comfort);
			float s_yaw = TIME * 0.004 * s_mv + beat_step * 0.012 * s_mv + s_dp * 0.07;
			vec3 s_d = dir * euler(vec3(0.0, s_yaw, 0.0));
			s_d.y = dir.y + s_dp * 0.03 * (1.0 - abs(dir.y));          // Drop: naeher heran
			vec4 s_sh = textureLod(shards_tex, dir_uv(normalize(s_d), vec2(0.0)), 0.0);
			float s_lon = atan(dir.x, -dir.z);
			float s_lat = asin(clamp(dir.y, -1.0, 1.0));
			float s_gate = smoothstep(0.03, 0.12, s_lat) * (1.0 - exp(-(s_lon / 0.5) * (s_lon / 0.5)) * smoothstep(0.9, 0.5, s_lat));
			vec3 s_c = dec(s_sh.rgb) * (1.0 + beat_pulse * 0.30 + downbeat_pulse * 0.25 * s_mv + s_dp * 0.6);
			col = mix(col, s_c * tint * brightness, s_sh.a * s_gate);
		}

		// Lesbarkeit in Weltkoordinaten: vorn-mitte/unten zusaetzlich dunkler.
		float front = exp(-(lon / 0.62) * (lon / 0.62)) * smoothstep(0.22, -0.30, lat);
		col *= 1.0 - readability * 0.6 * front;

		float h = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
		col = max(col * (1.0 + h * 0.03) + h * 0.00025, vec3(0.0));
		COLOR = col;
	}
}
