shader_type sky;

// Welt-Thema "Singularitaet": riesiges schwarzes Loch mit duenner weissgluehender
// Akkretionsscheibe, Gravitationslinse und hineingezogener Materie. Schwarz +
// Weiss-Silber, minimal warmer Kern in der heissesten Zone, kein Neon.
// Panoramen offline: tools/gen_theme_singularity.py ->
// assets_game/themes/singularity/
//   singularity_sky.webp      tex_a      Schatten, Scheibe, Photonenring, gelinste
//                                        Rueckseite, Sterne (fern, Linse fest eingebacken)
//   singularity_streaks.webp  streaks_a  Materie-Schlieren auf Log-Spiralen (mittlere Ebene)
//   singularity_dust.webp     dust_a     feine Staubkoerner nahe am Loch (nahe Ebene)
//   singularity_chunks.webp   chunks_a   naheste Ebene (RGBA): Materie-Brocken, kreisen
//                                        wie die Fraktal-Splitter um den Spieler (Gier)
//                                        und ziehen mit Parallax vorbei
// Konstanten hole_*/streak_flatten/shadow_deg muessen zu HOLE_*, STREAK_FLATTEN,
// SHADOW_DEG im Generator passen.
// Weil die Schlieren Log-Spiralen sind, ist jede Drehung um das Loch (in der
// Bild-Ellipse) ein Einwaerts-Stroemen: Schlieren und Staub werden ohne Wickeln
// und ohne Ueberblend-Geister hineingezogen, endlos.
//
// BEAT-VERTRAG (docs/worlds/beat_contract.md):
//   beat_step      SIGNATUR: (1) Gravitationswelle: auf dem Schlag laeuft ein
//                  Linsenring vom Schatten nach aussen (Radius = fract(beat_step),
//                  glatte Formel aus dem Vertrag, Amplitude klingt bis zum naechsten
//                  Schlag auf 0, kein Ruck). KOMFORT: Schlieren und Staub wirbeln
//                  gleichmaessig ueber TIME ins Loch (2 / 3.4 Grad/s, Wirbel <= 4),
//                  die Brocken gieren gleichmaessig (0.69 Grad/s); nie ueber beat_step,
//                  nie ueber star_phase (dessen Beat-Schub wuerde stocken).
//   beat_pulse     Scheibe/Ring (nur Helles) gluet auf dem Schlag auf.
//   downbeat_pulse Akzent: groessere Welle, Photonenring + Kern gluehen heller.
//   drop           Verwandlung: Linse vertieft sich, Schlieren, Staub und Brocken werden
//                  naeher gezogen (Brocken bis +28 % groesser) (Materie verdichtet sich), Scheibe
//                  gluet staerker. Gedeckelt (Luma Mitte/unten <= +20 %, oben <= +35 %).
//   kiai           Schlieren/Staub etwas heller, Kern minimal waermer.
//   energy         Helligkeit der Materie 0.85..1.15.
//   comfort        Welle, Wirbel und Pulse halbiert.
//   beat_phase / bar_phase  Feinmodulation (Funkeln der Scheibenkante).
//
// Uniform-Interface wie shaders/sky_panorama.gdshader (gleiche Namen/Bedeutung):
//   tex_a / tex_b / palette_mix   ferne Ebene (wurzel-kodiert, linear = textur^2)
//   streaks_a / streaks_b         Schlieren (additiv, dito)
//   dust_a / dust_b               Staub (additiv, dito)
//   stars_a / stars_b             ungenutzt (nur Interface), Standard schwarz
//   tint, brightness, readability, pano_rotation/pano_offset
//   star_brightness               Helligkeit Schlieren + Staub
//   star_hdr                      hebt die hellsten Scheibenstellen ueber die
//                                 Glow-Schwelle (1 = aus)
//   stars_rotation / stars_offset wirken auf Schlieren + Staub
//   star_speed / star_phase       zusaetzlicher Sog (rad/s) / Drehwinkel (rad)
//   warp 0..1                     Sog-Unschaerfe der Schlieren (6 Abtastungen)
//
// INTEGRATION (mania_3d._build_theme_sky fuellt die Sampler per Dateiname:
// singularity_sky -> tex_*, singularity_streaks -> streaks_*,
// singularity_dust -> dust_*): Beat-Uniforms des Vertrags pro Frame setzen.
//
// FARBSATZ fuer Strecke / Kanten / Pads (sRGB-Hex; Schwarz + Weiss-Silber):
//   Strecke Grund        #070709  (fast Schwarz, Alpha 0.94)
//   Strecke Welle        #6c7078  (road_wave base_color, Silbergrau)
//   Spurlinien           #25262b  (Alpha 0.55)
//   Kanten (aussen)      #9aa0aa  Emission 0.55 (Bass-Spitze -> #e6e9ee)
//   Kanten Kiai          #f2f4f7  (Weiss, Emission 0.9)
//   Pads Ring            #b8bec8  fill_alpha 0.16
//   Pads Treffer         #ffffff -> #c9ced6
//   Noten                #f0f2f5 (hell) / #9aa0aa (Silbergrau) je Spurpaar,
//                        Kern weiss; Holds #9aa0aa
//   Kiai-Akzent          #fff3e2  (minimal warmes Weiss, Kern der Scheibe)
//   Funken / Regen       #d6dae0 / #7c828c
//   Ambient              #0b0b0d, Glow-Schwelle 0.92 wie mania_3d
//   WorldTheme-Palette:  {"line": Color("#9aa0aa"), "kiai": Color("#f2f4f7")}

uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D streaks_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D streaks_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D dust_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D dust_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D chunks_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D chunks_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
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

// Singularitaet (= Konstanten im Generator)
uniform float hole_lon = -27.0;       // Grad, = HOLE_LON
uniform float hole_lat = -2.0;        // Grad, = HOLE_LAT
uniform float hole_roll = 10.0;       // Grad, = DISK_ROLL
uniform float streak_flatten = 0.42;  // = STREAK_FLATTEN
uniform float shadow_deg = 7.5;       // = SHADOW_DEG
uniform float whirl_streak = 0.035;   // rad/s Wirbel der Schlieren (2 Grad/s, Komfort: <= 4)
uniform float whirl_dust = 0.06;      // rad/s Wirbel des Staubs (3.4 Grad/s, nah = schneller)
uniform float chunk_yaw = 0.012;      // rad/s Gier der Brocken (0.69 Grad/s, Komfort: <= 1)
uniform float wave_amp = 0.055;       // Linsenwelle: Auslenkung (relativ zum Winkel)

// Mip-Stufe aus der Pixelgroesse (Bogen je Pixel / Bogen je Texel): scharf bei
// 1:1, ruhig beim Verkleinern. Wird je Pixel in sky() gesetzt.
#define samp(a, b, uv) samp_l(a, b, uv, g_lod)

const int WARP_TAPS = 3;
const float TAU_ = 6.28318530718;
const float DROP_PEAK_ = 0.6;

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

vec3 dec(vec3 c) {
	return c * c;
}

vec3 samp_l(sampler2D a, sampler2D b, vec2 uv, float g_lod) {
	if (palette_mix <= 0.001) {
		return dec(textureLod(a, uv, g_lod).rgb);
	}
	if (palette_mix >= 0.999) {
		return dec(textureLod(b, uv, g_lod).rgb);
	}
	return mix(dec(textureLod(a, uv, g_lod).rgb), dec(textureLod(b, uv, g_lod).rgb), palette_mix);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 dir_of(float lon_deg, float lat_deg) {
	float lo = radians(lon_deg), la = radians(lat_deg);
	return vec3(cos(la) * sin(lo), sin(la), -cos(la) * cos(lo));
}

// Drehung um das Loch in der Bild-Ellipse (wie render_streaks im Generator),
// danach Skalierung des Abstands. Positiver Winkel = Muster stroemt einwaerts.
vec3 spiral_dir(vec3 d, vec3 h, vec3 ex, vec3 ey, float ang, float sc) {
	float z = dot(d, h);
	if (z < 0.12) {
		return d;
	}
	float X = dot(d, ex) / z;
	float Y = dot(d, ey) / z / streak_flatten;
	float c = cos(ang), s = sin(ang);
	vec2 q = vec2(c * X - s * Y, s * X + c * Y) * sc;
	vec3 w = normalize(h + q.x * ex + q.y * streak_flatten * ey);
	return mix(d, w, smoothstep(0.12, 0.30, z));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float g_lod = clamp(log2(max(length(fwidth(dir)), 1e-6) * float(textureSize(tex_a, 0).x) / 6.28318530718), 0.0, 6.0);
	vec3 d0 = dir * euler(pano_rotation);

	if (AT_CUBEMAP_PASS) {
		COLOR = samp(tex_a, tex_b, dir_uv(d0, pano_offset)) * tint * brightness * 0.5;
	} else {
		// Bildachsen um das Loch (wie Frame im Generator).
		vec3 h = dir_of(hole_lon, hole_lat);
		vec3 ex0 = normalize(cross(h, vec3(0.0, 1.0, 0.0)));
		vec3 ey0 = cross(ex0, h);
		float rl = radians(hole_roll);
		vec3 ex = cos(rl) * ex0 + sin(rl) * ey0;
		vec3 ey = -sin(rl) * ex0 + cos(rl) * ey0;

		float cf = 1.0 - 0.5 * comfort;
		float bp = clamp(beat_pulse, 0.0, 1.0) * cf;
		float dbp = clamp(downbeat_pulse, 0.0, 1.0) * cf;
		float dn = clamp(drop / DROP_PEAK_, 0.0, 1.0);
		float kg = clamp(kiai, 0.0, 1.0);
		float en = 0.85 + 0.30 * clamp(energy, 0.0, 1.0);

		// Gravitationswelle: Linsenring vom Schatten nach aussen. fract(beat_step)
		// ist 0 auf dem Schlag, steigt glatt auf 1. Komfort: die Linse setzt sanft ein
		// (smoothstep ueber 1/4 Beat, kein Verzerrungs-Ruck auf dem Schlag) und klingt auf 0.
		float e = fract(beat_step);
		float th_w = radians(shadow_deg) * 1.15 + e * radians(40.0);
		float amp = wave_amp * smoothstep(0.0, 0.25, e) * pow(1.0 - e, 0.8) * cf * (0.75 + 0.9 * dbp);
		float cth = clamp(dot(d0, h), -1.0, 1.0);
		float th = acos(cth);
		float wd = (th - th_w) / (0.05 + 0.10 * e);
		float bump = exp(-wd * wd);
		// Drop: Linse vertieft sich dauerhaft (Bilder werden zum Loch gezogen).
		float pull = amp * bump + 0.10 * dn * exp(-th / 0.35);
		float th2 = th * (1.0 - pull);
		vec3 tg = d0 - h * cth;
		float tl = length(tg);
		vec3 d1 = d0;
		if (tl > 1e-4) {
			d1 = h * cos(th2) + (tg / tl) * sin(th2);
		}

		// Ferne Ebene.
		vec3 far = samp(tex_a, tex_b, dir_uv(d1, pano_offset));

		// Schlieren / Staub: gleichmaessiger Wirbel um das Loch (Komfort: nur TIME, kein Ruck).
		vec3 d2 = d1 * euler(stars_rotation);
		float wt = TIME * cf;
		float ang_s = mod(wt * min(whirl_streak, 0.0698) + TIME * star_speed, TAU_);
		float ang_d = mod(wt * min(whirl_dust, 0.0698) + TIME * star_speed * 2.2, TAU_);
		float sc_s = 1.0 + 0.30 * dn;
		float sc_d = 1.0 + 0.55 * dn;
		float blur = warp * 0.07;
		vec3 st = vec3(0.0);
		if (blur > 0.001) {
			for (int i = 0; i < WARP_TAPS; i++) {
				float k = float(i) / float(WARP_TAPS - 1);
				st += samp(streaks_a, streaks_b, dir_uv(spiral_dir(d2, h, ex, ey, ang_s + blur * k, sc_s), stars_offset));
			}
			st /= float(WARP_TAPS);
		} else {
			st = samp(streaks_a, streaks_b, dir_uv(spiral_dir(d2, h, ex, ey, ang_s, sc_s), stars_offset));
		}
		vec3 du = samp(dust_a, dust_b, dir_uv(spiral_dir(d2, h, ex, ey, ang_d, sc_d), stars_offset));

		// Brocken: gleichmaessige Gier um den Spieler (<= 1 Grad/s), Drop holt sie naeher.
		float yaw = mod(wt * min(chunk_yaw, 0.01745), TAU_);
		float s_c = 1.0 + 0.28 * dn;
		vec2 uvc = dir_uv(d2, stars_offset);
		vec2 uc = vec2(fract(0.5 + (uvc.x - 0.5) / s_c + yaw / TAU_), clamp(0.43 + (uvc.y - 0.43) / s_c, 0.0005, 0.9995));
		vec4 chunk;
		if (palette_mix <= 0.001) {
			vec4 c = textureLod(chunks_a, uc, g_lod);
			chunk = vec4(dec(c.rgb), c.a);
		} else {
			vec4 c0 = textureLod(chunks_a, uc, g_lod);
			vec4 c1 = textureLod(chunks_b, uc, g_lod);
			chunk = mix(vec4(dec(c0.rgb), c0.a), vec4(dec(c1.rgb), c1.a), palette_mix);
		}

		float matter = star_brightness * en * (1.0 + 0.30 * bp + 0.30 * kg + 0.28 * dn);
		vec3 col = far + st * matter + du * matter * 1.15;
		col = col * (1.0 - chunk.a) + chunk.rgb * matter * (1.0 + 0.4 * bp);

		// Helles gluet auf (Scheibe, Photonenring, Kern): nie Schwarz, nie Vollbild.
		float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
		float hot = smoothstep(0.22, 0.85, l);
		float core = smoothstep(0.55, 1.0, l);
		float spark = 0.5 + 0.5 * sin(TAU_ * (bar_phase * 4.0 + beat_phase) + 40.0 * dot(dir, vec3(0.31, 0.71, 0.63)));
		col *= 1.0 + hot * (0.30 * bp + 0.20 * dn) * en + core * (0.35 * dbp + 0.10 * dn) + 0.04 * hot * spark * bp;
		col *= mix(1.0, star_hdr, core);
		// Kiai: Kern minimal waermer (nur im sehr Hellen), kein Farbwechsel sonst.
		col += vec3(0.020, 0.010, 0.000) * core * (kg * 0.5 + dn * 0.5 + dbp * 0.3) * l;

		col *= tint * brightness;

		float lon = atan(dir.x, -dir.z);
		float lat = asin(clamp(dir.y, -1.0, 1.0));
		float front = exp(-(lon / 0.62) * (lon / 0.62)) * smoothstep(0.02, -0.30, lat);
		col *= mix(1.0, 0.55, smoothstep(0.0, -0.40, lat));
		col *= 1.0 - readability * 0.6 * front;

		float hh = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
		col = max(col * (1.0 + hh * 0.03) + hh * 0.00025, vec3(0.0));
		COLOR = col;
	}
}
