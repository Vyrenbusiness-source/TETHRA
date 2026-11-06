shader_type sky;

// Premium-Weltraum-Himmel: offline erzeugte Panoramen (tools/gen_skybox.py)
// statt Laufzeit-Rauschen. Zwei Ebenen, getrennt dreh-/verschiebbar:
//   Nebel-Ebene  (tex_a/tex_b)     sky_<name>.webp       fern, ruhig
//   Sternen-Ebene (stars_a/stars_b) sky_<name>_stars.webp nah, Parallax/Flug
// Paletten: violet, azure, ember, emerald (assets_game/space/).
//
// Abbildung (identisch zum Generator): u = atan(d.x, -d.z)/2pi + 0.5,
// v = 0.5 - asin(d.y)/pi -> Bildmitte des Panoramas liegt vorn (-Z).
// Vorn-unten (hinter Strecke/Noten) ist schon im Bild abgedunkelt,
// `readability` dunkelt dort zusaetzlich in Weltkoordinaten ab (bleibt auch
// bei gedrehtem Panorama hinter der Strecke).
//
// INTEGRATION (z.B. mania_3d.gd _build_world):
//   var mat := ShaderMaterial.new()
//   mat.shader = load("res://shaders/sky_panorama.gdshader")
//   mat.set_shader_parameter("tex_a", load("res://assets_game/space/sky_violet.webp"))
//   mat.set_shader_parameter("stars_a", load("res://assets_game/space/sky_violet_stars.webp"))
//   var sky := Sky.new()
//   sky.sky_material = mat
//   sky.radiance_size = Sky.RADIANCE_SIZE_32          # Radiance wird nicht gebraucht
//   sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
//   env.background_mode = Environment.BG_SKY
//   env.sky = sky
//   env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
//   env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
// Die bisherigen Nebel-Quads (space_bg) verdecken den Himmel -> ausblenden
// oder nur noch als dezente Vordergrund-Schicht nutzen.
//
// Pro Frame (alles optional):
//   beat_pulse 0..1    Welt-Puls auf dem Beat (Nebel-Lichter + Sterne heben sich)
//   palette_mix 0..1   Ueberblendung tex_a/stars_a -> tex_b/stars_b (z.B. Kiai):
//                      tex_b/stars_b setzen, palette_mix hochfahren, danach
//                      b nach a kopieren und palette_mix = 0.
//   pano_rotation      Euler (rad, x=Neigung, y=Gier, z=Rollen) der Nebel-Ebene
//   stars_rotation     dito Sternen-Ebene (andere Rate = Parallax)
//   pano_offset / stars_offset  UV-Versatz (x wickelt um, y klemmt)
//   star_speed         Flug nach vorn: Zoom-Zyklen/s (Sterne stroemen aus dem
//                      Fluchtpunkt). Fuer variable Geschwindigkeit star_speed=0
//                      lassen und star_phase selbst hochzaehlen.
//   warp 0..1          radiale Streckung der Sterne (Hyperraum-Streifen)
//   tint, brightness, star_brightness, star_hdr (Kerne ueber Glow-Schwelle).
// Kosten: 1-2 Nebel-Fetches + 1..24 Sternen-Fetches je Pixel (warp>0 und
// palette_mix zwischen 0 und 1 sind die teuren Faelle). Cubemap-Pass billig.

uniform sampler2D tex_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D tex_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D stars_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D stars_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform float palette_mix : hint_range(0.0, 1.0) = 0.0;

uniform vec3 tint : source_color = vec3(1.0);
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_hdr : hint_range(1.0, 4.0) = 1.8;
uniform float beat_pulse : hint_range(0.0, 1.0) = 0.0;

uniform vec3 pano_rotation = vec3(0.0);
uniform vec2 pano_offset = vec2(0.0);
uniform vec3 stars_rotation = vec3(0.0);
uniform vec2 stars_offset = vec2(0.0);

uniform float star_speed = 0.0;
uniform float star_phase = 0.0;
uniform float warp : hint_range(0.0, 1.0) = 0.0;
uniform float readability : hint_range(0.0, 1.0) = 0.35;

const int WARP_TAPS = 8;

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

// Stereografischer Zoom um die Flugrichtung (-Z): s>1 vergroessert,
// Sterne wandern aus dem Fluchtpunkt nach aussen; Rueckseite bleibt fix.
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

vec3 stars_at(vec3 d, mat3 srot) {
	vec2 uv = dir_uv(d * srot, stars_offset);
	if (palette_mix <= 0.001) {
		return textureLod(stars_a, uv, 0.0).rgb;
	}
	if (palette_mix >= 0.999) {
		return textureLod(stars_b, uv, 0.0).rgb;
	}
	return mix(textureLod(stars_a, uv, 0.0).rgb, textureLod(stars_b, uv, 0.0).rgb, palette_mix);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	// Nebel-Ebene
	vec2 puv = dir_uv(dir * euler(pano_rotation), pano_offset);
	vec3 neb;
	if (palette_mix <= 0.001) {
		neb = textureLod(tex_a, puv, 0.0).rgb;
	} else if (palette_mix >= 0.999) {
		neb = textureLod(tex_b, puv, 0.0).rgb;
	} else {
		neb = mix(textureLod(tex_a, puv, 0.0).rgb, textureLod(tex_b, puv, 0.0).rgb, palette_mix);
	}
	// Puls hebt vor allem die hellen Gas-Kerne (Lichter atmen, Schwarz bleibt schwarz).
	float nl = dot(neb, vec3(0.2126, 0.7152, 0.0722));
	neb *= 1.0 + beat_pulse * (0.10 + 2.2 * nl);

	if (AT_CUBEMAP_PASS) {
		COLOR = neb * tint * brightness * 0.5;
	} else {
		// Sternen-Ebene: zwei ueberblendete Zoom-Lagen (Hann-Fenster, Summe = 1).
		mat3 srot = euler(stars_rotation);
		float ph = star_phase + TIME * star_speed;
		vec3 st = vec3(0.0);
		bool moving = abs(star_speed) > 0.0001 || abs(fract(star_phase)) > 0.0001;
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
				// Strahlenfoermige Streifen: entlang des Zooms mehrfach abtasten.
				float wsum = 0.0;
				for (int i = 0; i < WARP_TAPS; i++) {
					float k = float(i) / float(WARP_TAPS - 1);
					float wk = 1.0 - 0.75 * k;
					acc += stars_at(zoom_dir(dir, s * (1.0 + warp * 0.32 * k)), srot) * wk;
					wsum += wk;
				}
				acc *= (1.0 + warp * 2.2) / wsum;
			} else {
				acc = stars_at(zoom_dir(dir, s), srot);
			}
			st += acc * w;
		}
		// Helle Kerne ueber die Glow-Schwelle heben, schwache Sterne bleiben fein.
		float sl = dot(st, vec3(0.2126, 0.7152, 0.0722));
		st *= star_brightness * mix(1.0, star_hdr, smoothstep(0.35, 0.9, sl));
		st *= 1.0 + beat_pulse * 0.55;

		vec3 col = (neb + st) * tint * brightness;

		// Lesbarkeit in Weltkoordinaten: vorn-mitte/unten zusaetzlich dunkler.
		float lon = atan(dir.x, -dir.z);
		float lat = asin(clamp(dir.y, -1.0, 1.0));
		float front = exp(-(lon / 0.62) * (lon / 0.62)) * smoothstep(0.22, -0.30, lat);
		col *= 1.0 - readability * 0.6 * front;

		// Dither gegen Banding in den dunklen Verlaeufen.
		float h = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
		col = max(col * (1.0 + h * 0.03) + h * 0.00025, vec3(0.0));
		COLOR = col;
	}
}
