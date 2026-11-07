shader_type sky;

// Welt-Thema "Sturm": abstrakter Gewitter-Mahlstrom, duester, fast monochrom
// (Anthrazit + kaltes Grau-Violett, kein Neon). Panoramen offline:
// tools/gen_theme_storm.py -> assets_game/themes/storm/
//   storm_sky.webp         tex_a     ferne Wolkenmassen, schwarzes Auge,
//                                    Augenwand innen beleuchtet, Wetterleuchten
//   storm_sky_clouds.webp  clouds_a  mittlere Ebene: Wolkenbaender (RGBA,
//                                    Farbe vormultipliziert)
//   storm_sky_rain.webp    rain_a    nahe Ebene: Regenschleier (RGBA)
//   storm_sky_debris.webp  debris_a  naheste Ebene: Wolkenfetzen + Truemmer (RGBA)
//                                    kreisen wie die Fraktal-Splitter um den
//                                    Spieler (Gier) und ziehen mit Parallax vorbei
// Drei Parallax-Ebenen drehen um die Augen-Achse (fern langsam, Mitte, nah
// schnell). Weil die Arme logarithmische Spiralen sind, liest sich die
// Drehung als Sog ins Auge - ohne Aufwickeln, ohne Ueberblend-Geister, endlos.
//
// BEAT-VERTRAG (docs/worlds/beat_contract.md):
//   beat_step      SIGNATUR (Durchflug im Tornado): die Wolkenwand RASTET pro
//                  Schlag eine Kerbe um die Strecke weiter (Ratsche), die nahen
//                  Truemmer schwingen (Gier) mit mehr Kerbe an der Kamera vorbei:
//                  Winkel = beat_step * Kerbe je Ebene. beat_step
//                  springt auf dem Schlag und ruht danach (Easing im Vertrag).
//   beat_pulse     Aufleuchten der beleuchteten Wolkenkanten an der Augenwand
//                  (Attack exakt auf dem Schlag, nur Lichter, Schwarz bleibt
//                  schwarz) + wenige Prozent Einziehen des Trichters.
//   downbeat_pulse Akzent: Augenwand gluet kurz staerker, Trichter zieht mehr ein.
//   drop           Verwandlung: der Trichter zieht sich ENGER (bis ca. 30 %), die
//                  Truemmer kommen naeher (bis +28 % groesser), Wetterleuchten
//                  wandert in der Wand, der Trichter dreht (Pendel) bis ~0.3 rad/s
//                  schneller. Gedeckelt, kein Blitz (Luma Mitte/unten
//                  <= +20 %, oben <= +35 %).
//   kiai           weiches Wetterleuchten in der Wand, getaktet mit downbeat_pulse.
//   energy         Regenschleier + Wandglut etwas kraeftiger (0.85..1.15).
//   comfort        Kerben und Einziehen halbiert, keine Drehung durch Takt.
//   beat_phase / bar_phase  feine Modulation (Wandglut wandert mit dem Takt).
//
// Uniform-Interface wie shaders/sky_panorama.gdshader (gleiche Namen/Bedeutung):
//   tex_a / tex_b / palette_mix   ferne Ebene (wurzel-kodiert, linear = textur^2)
//   clouds_a / clouds_b           mittlere Ebene (gleiche Ueberblendung palette_mix)
//   rain_a / rain_b               naheste Ebene (Regenschleier, dito)
//   stars_a / stars_b             ungenutzt (nur Interface), Standard schwarz
//   tint, brightness, readability, pano_rotation/pano_offset
//   star_brightness               Helligkeit der mittleren/nahen Ebene
//   star_hdr                      Hebt die hellsten Kanten der Augenwand ueber
//                                 die Glow-Schwelle (1 = aus)
//   stars_rotation / stars_offset wirken auf mittlere + nahe Ebene
//   star_speed                    zusaetzlicher Sog (rad/s Drehung um das Auge)
//   star_phase                    Drehwinkel (rad), fuer variable Geschwindigkeit
//                                 star_speed = 0 lassen und hochzaehlen
//   warp 0..1                     Sog-Unschaerfe: Wolken verwischen entlang der
//                                 Drehung (3 Abtastungen je Ebene)
// Sturm-eigene Uniforms: eye_* (muessen zu EYE_* im Generator passen),
// swirl_speed (Dauerdrift, sehr langsam), swirl_parallax, notch_far/mid/near
// (rad je Schlag), breath.
//
// INTEGRATION (wie sky_panorama, mania_3d._build_theme_sky fuellt die Sampler
// per Dateiname: storm_sky -> tex_*, storm_sky_clouds -> clouds_*,
// storm_sky_rain -> rain_*):
//   var mat := ShaderMaterial.new()
//   mat.shader = load("res://shaders/theme_storm.gdshader")
//   mat.set_shader_parameter("tex_a", load("res://assets_game/themes/storm/storm_sky.webp"))
//   mat.set_shader_parameter("clouds_a", load("res://assets_game/themes/storm/storm_sky_clouds.webp"))
//   mat.set_shader_parameter("rain_a", load("res://assets_game/themes/storm/storm_sky_rain.webp"))
//   pro Frame die Beat-Uniforms des Vertrags (mania_3d.gd).
//
// FARBSATZ fuer Strecke / Kanten / Pads (sRGB-Hex; Anthrazit + Grau-Violett):
//   Strecke Grund        #0b0b0f  (Anthrazit-Schwarz, Alpha 0.94)
//   Strecke Welle        #5d5878  (road_wave base_color, gedaempftes Grau-Violett)
//   Spurlinien           #2a2936  (Alpha 0.55)
//   Kanten (aussen)      #8e89a8  Emission 0.55 (Bass-Spitze -> #c9c5dc)
//   Kanten Kiai          #d6d2e8  (fahles Lavendel-Weiss, Emission 0.9)
//   Pads Ring            #a29dbb  fill_alpha 0.16
//   Pads Treffer         #ffffff -> #b4b0c8
//   Noten                #e4e1ef (hell) / #8e89a8 (Grau-Violett) je Spurpaar,
//                        Kern weiss; Holds #8e89a8
//   Kiai-Akzent          #c9c5dc (kein Farbton-Wechsel, nur heller)
//   Funken / Regen       #b4b0c8 / #6f6c80
//   Ambient              #0e0e14, Glow-Schwelle 0.92 wie mania_3d
//   WorldTheme-Palette:  {"line": Color("#8e89a8"), "kiai": Color("#d6d2e8")}

uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D clouds_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D clouds_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D rain_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D rain_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D debris_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D debris_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D stars_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D stars_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform float palette_mix : hint_range(0.0, 1.0) = 0.0;

uniform vec3 tint : source_color = vec3(1.0);
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_hdr : hint_range(1.0, 4.0) = 1.4;

// Beat-Vertrag
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

// Sturm
uniform float eye_lat = 1.2;          // Grad, = EYE_LAT im Generator
uniform float eye_lon = 0.0;          // Grad, = EYE_LON
uniform float eye_radius = 4.4;       // Grad, = R_EYE
uniform float swirl_speed = 0.020;    // rad/s Dauerdrift der fernen Ebene (unterschwellig)
uniform float swirl_parallax = 1.9;   // mittlere/nahe Ebene driften so viel schneller
uniform float notch_far = 0.030;      // rad je Schlag (Ratsche), ferne Ebene
uniform float notch_mid = 0.062;      // mittlere Ebene
uniform float notch_near = 0.115;     // Regenschleier
uniform float notch_debris = 0.075;   // Gier der Truemmer je Schlag (rad)
uniform float breath : hint_range(0.0, 2.0) = 1.0;
uniform vec3 glow_color : source_color = vec3(0.62, 0.60, 0.74);

// Mip-Stufe aus der Pixelgroesse (Bogen je Pixel / Bogen je Texel): scharf bei
// 1:1, ruhig beim Verkleinern. Wird je Pixel in sky() gesetzt.

#define sample_far(uv) sample_far_l(uv, g_lod)
#define sample_mid(uv) sample_mid_l(uv, g_lod)
#define sample_rain(uv) sample_rain_l(uv, g_lod)
#define sample_debris(uv) sample_debris_l(uv, g_lod)

const int WARP_TAPS = 3;
const float TAU_ = 6.28318530718;
const float DROP_PEAK_ = 0.6;

mat3 euler(vec3 e) {
	e = vec3(0.0, e.y, 0.0);   // Komfort: nur Yaw, nie Roll/Kippen (beat_contract.md)
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

vec3 sample_far_l(vec2 uv, float g_lod) {
	if (palette_mix <= 0.001) {
		return dec(textureLod(tex_a, uv, g_lod).rgb);
	}
	if (palette_mix >= 0.999) {
		return dec(textureLod(tex_b, uv, g_lod).rgb);
	}
	return mix(dec(textureLod(tex_a, uv, g_lod).rgb), dec(textureLod(tex_b, uv, g_lod).rgb), palette_mix);
}

// Nahe Ebenen: rgb vormultipliziert (wurzel-kodiert), a = Deckung (linear).
vec4 sample_mid_l(vec2 uv, float g_lod) {
	vec4 a = textureLod(clouds_a, uv, g_lod);
	if (palette_mix <= 0.001) {
		return vec4(dec(a.rgb), a.a);
	}
	vec4 b = textureLod(clouds_b, uv, g_lod);
	if (palette_mix >= 0.999) {
		return vec4(dec(b.rgb), b.a);
	}
	return mix(vec4(dec(a.rgb), a.a), vec4(dec(b.rgb), b.a), palette_mix);
}

vec4 sample_rain_l(vec2 uv, float g_lod) {
	vec4 a = textureLod(rain_a, uv, g_lod);
	if (palette_mix <= 0.001) {
		return vec4(dec(a.rgb), a.a);
	}
	vec4 b = textureLod(rain_b, uv, g_lod);
	if (palette_mix >= 0.999) {
		return vec4(dec(b.rgb), b.a);
	}
	return mix(vec4(dec(a.rgb), a.a), vec4(dec(b.rgb), b.a), palette_mix);
}

vec4 sample_debris_l(vec2 uv, float g_lod) {
	vec4 a = textureLod(debris_a, uv, g_lod);
	if (palette_mix <= 0.001) {
		return vec4(dec(a.rgb), a.a);
	}
	vec4 b = textureLod(debris_b, uv, g_lod);
	if (palette_mix >= 0.999) {
		return vec4(dec(b.rgb), b.a);
	}
	return mix(vec4(dec(a.rgb), a.a), vec4(dec(b.rgb), b.a), palette_mix);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Richtung aus Trichter-Koordinaten (r = Abstand zur Achse, th = Winkel).
vec3 funnel_dir(vec3 e, vec3 rr, vec3 uu, float r, float th) {
	return e * cos(r) + (rr * cos(th) + uu * sin(th)) * sin(r);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float g_lod = clamp(log2(max(length(fwidth(dir)), 1e-6) * float(textureSize(tex_a, 0).x) / 6.28318530718), 0.0, 6.0);
	float la = radians(eye_lat), lo = radians(eye_lon);
	vec3 e = vec3(cos(la) * sin(lo), sin(la), -cos(la) * cos(lo));
	vec3 rr = normalize(cross(vec3(0.0, 1.0, 0.0), -e));
	vec3 uu = cross(-e, rr);

	if (AT_CUBEMAP_PASS) {
		COLOR = sample_far(dir_uv(dir * euler(pano_rotation), pano_offset)) * tint * brightness * 0.5;
	} else {
		float cf = 1.0 - 0.5 * comfort;
		float bp = clamp(beat_pulse, 0.0, 1.0) * cf;
		float dbp = clamp(downbeat_pulse, 0.0, 1.0);
		float dn = clamp(drop / DROP_PEAK_, 0.0, 1.0);
		float kg = clamp(kiai, 0.0, 1.0);
		float en = 0.85 + 0.30 * clamp(energy, 0.0, 1.0);

		// Komfort-Regeln (beat_contract.md): kein Rollen, Tornado dreht gleichmaessig
		// <= 4 Grad/s (hier max ~3.3 Grad/s in der naechsten Ebene), keine Beat-Spruenge.
		// beat_step nur als sanftes Atmen (periodisch je Schlag), nie als Winkel.
		float ratch = 0.0;
		float drift = TIME * swirl_speed;
		float a_far = drift;
		float a_mid = drift * swirl_parallax;
		float a_near = drift * swirl_parallax * 1.5;
		float flow = sin(beat_step * TAU_) * cf;
		float blur = warp * 0.10;

		// Drop: Trichter zieht sich enger (Quellradius waechst = Muster rueckt zum Auge).
		float open_k = 1.0 + 0.24 * dn;
		// Einziehen auf dem Schlag, mehr auf dem Taktanfang.
		float pull = (0.045 * bp + 0.040 * dbp * cf) * breath;

		// Ferne Ebene (Winkel in der gedrehten Ebene messen).
		vec3 dp = dir * euler(pano_rotation);
		float r = acos(clamp(dot(dp, e), -1.0, 1.0));
		float th = atan(dot(dp, uu), dot(dp, rr));
		float rdeg = degrees(r);
		float inner = exp(-max(rdeg - eye_radius, 0.0) / 9.0);
		float s_far = open_k * (1.0 + pull * exp(-rdeg / 30.0) + 0.006 * flow * breath);
		vec3 far = vec3(0.0);
		if (blur > 0.001) {
			for (int i = 0; i < WARP_TAPS; i++) {
				float k = float(i) / float(WARP_TAPS - 1);
				far += sample_far(dir_uv(funnel_dir(e, rr, uu, r * s_far, th + a_far + blur * 0.6 * k), pano_offset));
			}
			far /= float(WARP_TAPS);
		} else {
			far = sample_far(dir_uv(funnel_dir(e, rr, uu, r * s_far, th + a_far), pano_offset));
		}

		// Mittlere Ebene: Wolkenbaender, innen etwas staerker eingezogen.
		vec3 dn3 = dir * euler(stars_rotation);
		float rn = acos(clamp(dot(dn3, e), -1.0, 1.0));
		float tn = atan(dot(dn3, uu), dot(dn3, rr));
		float rndeg = degrees(rn);
		float s_mid = open_k * (1.0 + 1.4 * pull * exp(-rndeg / 26.0) + 0.012 * flow * breath);
		float s_rain = open_k * (1.0 + 2.0 * pull * exp(-rndeg / 22.0) + 0.020 * flow * breath);
		vec4 mid = vec4(0.0);
		vec4 rain = vec4(0.0);
		if (blur > 0.001) {
			for (int i = 0; i < WARP_TAPS; i++) {
				float k = float(i) / float(WARP_TAPS - 1);
				mid += sample_mid(dir_uv(funnel_dir(e, rr, uu, rn * s_mid, tn + a_mid + blur * k), stars_offset));
				rain += sample_rain(dir_uv(funnel_dir(e, rr, uu, rn * s_rain, tn + a_near + blur * 1.3 * k), stars_offset));
			}
			mid /= float(WARP_TAPS);
			rain /= float(WARP_TAPS);
		} else {
			mid = sample_mid(dir_uv(funnel_dir(e, rr, uu, rn * s_mid, tn + a_mid), stars_offset));
			rain = sample_rain(dir_uv(funnel_dir(e, rr, uu, rn * s_rain, tn + a_near), stars_offset));
		}

		vec3 col = far * (1.0 - mid.a) + mid.rgb * star_brightness;
		col = col * (1.0 - rain.a) + rain.rgb * star_brightness * (en + 0.25 * dn);

		// Truemmer: Gier um den Spieler (Ratsche), Parallax durch eigene Rate,
		// Drop holt sie naeher (Zoom um vorn). Nur ueber dem Horizont gezeichnet.
		float yaw = drift * 2.6;
		float s_d = 1.0 + 0.28 * dn + 0.030 * flow * breath;
		vec2 uv0 = dir_uv(dir * euler(stars_rotation), stars_offset);
		vec2 ud = vec2(fract(0.5 + (uv0.x - 0.5) / s_d + yaw / TAU_), clamp(0.43 + (uv0.y - 0.43) / s_d, 0.0005, 0.9995));
		vec4 deb = sample_debris(ud);
		col = col * (1.0 - deb.a) + deb.rgb * star_brightness * (1.0 + 0.90 * bp + 0.30 * dn) * en;

		// Augenwand / Wetterleuchten: nur beleuchtete Wolken heben sich (Schwarz
		// bleibt schwarz), begrenzt auf die Wand um das Auge.
		float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
		float litk = smoothstep(0.004, 0.06, l);
		col *= mix(1.0, star_hdr, smoothstep(0.10, 0.30, l) * inner);
		float lon = atan(dir.x, -dir.z);
		float lat = asin(clamp(dir.y, -1.0, 1.0));
		float front = exp(-(lon / 0.62) * (lon / 0.62)) * smoothstep(0.02, -0.30, lat);
		float sector = 0.5 + 0.5 * cos(th - TIME * 0.35 - TAU_ * bar_phase);
		float wall = inner * (0.7 + 0.3 * sector) * (1.0 - 0.9 * front);
		float outer = exp(-max(rdeg - eye_radius, 0.0) / 16.0) * (1.0 - 0.9 * front);
		// Beat: Lichter der Wand; Takt: Akzent; Drop: Wolken leuchten innen mit;
		// Kiai: Wetterleuchten wandert im Sektor, atmet mit dem Taktanfang.
		float flash = 0.80 * bp + 0.60 * dbp * cf;
		float storm = (0.20 * dn + kg * (0.18 + 0.55 * dbp)) * sector * outer;
		col *= 1.0 + litk * ((flash * wall + 0.16 * dn * wall) * en + storm);
		col += glow_color * (0.006 * (bp + dbp * cf) * en + 0.010 * dn + 0.012 * kg * dbp) * inner
			* smoothstep(eye_radius * 0.95, eye_radius * 1.3, rdeg * open_k);

		// Drop: der engere Trichter zoeht dunkle Wolken nach oben (Himmel wurde dunkler).
		// Oben gedeckelt aufhellen (+35 % Vertrag), Mitte/unten unberuehrt.
		col *= 1.0 + 0.55 * dn * smoothstep(-0.40, 0.05, lat);

		col *= tint * brightness;

		// Unterer Trichter (unter dem Horizont) abgedunkelt, vorn-mitte zusaetzlich.
		col *= mix(1.0, 0.42, smoothstep(0.0, -0.40, lat));
		col *= 1.0 - readability * 0.6 * front;

		float h = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
		col = max(col * (1.0 + h * 0.03) + h * 0.00025, vec3(0.0));
		COLOR = col;
	}
}
