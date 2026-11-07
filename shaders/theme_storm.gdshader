shader_type sky;

// Welt-Thema "Sturm": abstrakter Gewitter-Mahlstrom, duester, fast monochrom
// (Anthrazit + kaltes Grau-Violett, kein Neon). Panoramen offline:
// tools/gen_theme_storm.py -> assets_game/themes/storm/
//   storm_sky.webp         tex_a     ferne Wolkenmassen, schwarzes Auge,
//                                    Augenwand innen beleuchtet, Wetterleuchten
//   storm_sky_clouds.webp  clouds_a  nahe Wolkenbaender + Regenschleier (RGBA,
//                                    Farbe vormultipliziert)
// Bewegung: beide Ebenen drehen um die Augen-Achse (nahe schneller = Parallax).
// Weil die Arme logarithmische Spiralen sind, liest sich die Drehung als Sog
// ins Auge - ohne Aufwickeln, ohne Ueberblend-Geister, endlos.
// Beat: der Wirbel atmet ein (zieht sich zum Auge zusammen, innen etwas mehr
// Drehung, die Augenwand gluet gedaempft auf). Die Antwort ist eine weiche
// Glocke 4*p*(1-p) von beat_pulse: auch ein harter Einsatz (1 -> 0) beginnt
// bei 0 - kein Flackern, kein Vollbild-Blitz, nichts ueber der Strecke.
//
// Uniform-Interface wie shaders/sky_panorama.gdshader (gleiche Namen/Bedeutung):
//   tex_a / tex_b / palette_mix   ferne Ebene (wurzel-kodiert, linear = textur^2)
//   clouds_a / clouds_b           nahe Ebene (gleiche Ueberblendung palette_mix)
//   stars_a / stars_b             ungenutzt (nur Interface), Standard schwarz
//   tint, brightness, beat_pulse, readability, pano_rotation/pano_offset
//   star_brightness               Helligkeit der nahen Ebene
//   star_hdr                      Hebt die hellsten Kanten der Augenwand ueber
//                                 die Glow-Schwelle (1 = aus)
//   stars_rotation / stars_offset wirken auf die nahe Ebene
//   star_speed                    zusaetzlicher Sog (rad/s Drehung um das Auge)
//   star_phase                    Drehwinkel (rad), fuer variable Geschwindigkeit
//                                 star_speed = 0 lassen und hochzaehlen
//   warp 0..1                     Sog-Unschaerfe: Wolken verwischen entlang der
//                                 Drehung (8 Abtastungen je Ebene)
//   lightning 0..1                Kiai-Wetterleuchten (wie boss): weiche Glocke,
//                                 nur in der Wolkenwand um das Auge, wandert
// Sturm-eigene Uniforms: eye_* (muessen zu EYE_* im Generator passen),
// swirl_speed, swirl_parallax, breath.
//
// INTEGRATION (wie sky_panorama, mania_3d._build_theme_sky fuellt die Sampler
// per Dateiname: storm_sky -> tex_*, storm_sky_clouds -> clouds_*):
//   var mat := ShaderMaterial.new()
//   mat.shader = load("res://shaders/theme_storm.gdshader")
//   mat.set_shader_parameter("tex_a", load("res://assets_game/themes/storm/storm_sky.webp"))
//   mat.set_shader_parameter("clouds_a", load("res://assets_game/themes/storm/storm_sky_clouds.webp"))
//   pro Frame beat_pulse (z.B. pow(1 - beat_phase, 4)), optional lightning.
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

uniform sampler2D tex_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D tex_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D clouds_a : source_color, filter_linear, repeat_enable, hint_default_transparent;
uniform sampler2D clouds_b : source_color, filter_linear, repeat_enable, hint_default_transparent;
uniform sampler2D stars_a : source_color, filter_linear, repeat_enable, hint_default_black;
uniform sampler2D stars_b : source_color, filter_linear, repeat_enable, hint_default_black;
uniform float palette_mix : hint_range(0.0, 1.0) = 0.0;

uniform vec3 tint : source_color = vec3(1.0);
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_hdr : hint_range(1.0, 4.0) = 1.4;
uniform float beat_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float lightning : hint_range(0.0, 1.0) = 0.0;

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
uniform float swirl_speed = 0.018;    // rad/s der fernen Ebene
uniform float swirl_parallax = 1.9;   // nahe Ebene dreht so viel schneller
uniform float breath : hint_range(0.0, 2.0) = 1.0;
uniform vec3 glow_color : source_color = vec3(0.62, 0.60, 0.74);

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

vec3 dec(vec3 c) {
	return c * c;
}

vec3 sample_far(vec2 uv) {
	if (palette_mix <= 0.001) {
		return dec(textureLod(tex_a, uv, 0.0).rgb);
	}
	if (palette_mix >= 0.999) {
		return dec(textureLod(tex_b, uv, 0.0).rgb);
	}
	return mix(dec(textureLod(tex_a, uv, 0.0).rgb), dec(textureLod(tex_b, uv, 0.0).rgb), palette_mix);
}

// Nahe Ebene: rgb vormultipliziert (wurzel-kodiert), a = Deckung (linear).
vec4 sample_near(vec2 uv) {
	vec4 a = textureLod(clouds_a, uv, 0.0);
	if (palette_mix <= 0.001) {
		return vec4(dec(a.rgb), a.a);
	}
	vec4 b = textureLod(clouds_b, uv, 0.0);
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
	float la = radians(eye_lat), lo = radians(eye_lon);
	vec3 e = vec3(cos(la) * sin(lo), sin(la), -cos(la) * cos(lo));
	vec3 rr = normalize(cross(vec3(0.0, 1.0, 0.0), -e));
	vec3 uu = cross(-e, rr);

	if (AT_CUBEMAP_PASS) {
		COLOR = sample_far(dir_uv(dir * euler(pano_rotation), pano_offset)) * tint * brightness * 0.5;
	} else {
		// Atem: weiche Glocke aus beat_pulse (startet bei 0, Spitze bei p = 0.5).
		float bp = clamp(beat_pulse, 0.0, 1.0);
		float b = 4.0 * bp * (1.0 - bp) * breath;
		float lg = clamp(lightning, 0.0, 1.0);
		float lb = 4.0 * lg * (1.0 - lg);

		float ang = star_phase + TIME * (swirl_speed + star_speed);
		float blur = warp * 0.10;

		// Ferne Ebene (Winkel in der gedrehten Ebene messen).
		vec3 dp = dir * euler(pano_rotation);
		float r = acos(clamp(dot(dp, e), -1.0, 1.0));
		float th = atan(dot(dp, uu), dot(dp, rr));
		float rdeg = degrees(r);
		float inner = exp(-max(rdeg - eye_radius, 0.0) / 9.0);
		float s_far = 1.0 + 0.030 * b * exp(-rdeg / 30.0);
		vec3 far = vec3(0.0);
		if (blur > 0.001) {
			for (int i = 0; i < WARP_TAPS; i++) {
				float k = float(i) / float(WARP_TAPS - 1);
				far += sample_far(dir_uv(funnel_dir(e, rr, uu, r * s_far, th + ang + blur * 0.6 * k), pano_offset));
			}
			far /= float(WARP_TAPS);
		} else {
			far = sample_far(dir_uv(funnel_dir(e, rr, uu, r * s_far, th + ang), pano_offset));
		}

		// Nahe Ebene: schneller, innen beim Einatmen etwas mehr Drehung.
		vec3 dn = dir * euler(stars_rotation);
		float rn = acos(clamp(dot(dn, e), -1.0, 1.0));
		float tn = atan(dot(dn, uu), dot(dn, rr));
		float rndeg = degrees(rn);
		float s_near = 1.0 + 0.045 * b * exp(-rndeg / 26.0);
		float a_near = ang * swirl_parallax + 0.05 * b * exp(-rndeg / 14.0);
		vec4 near = vec4(0.0);
		if (blur > 0.001) {
			for (int i = 0; i < WARP_TAPS; i++) {
				float k = float(i) / float(WARP_TAPS - 1);
				near += sample_near(dir_uv(funnel_dir(e, rr, uu, rn * s_near, tn + a_near + blur * k), stars_offset));
			}
			near /= float(WARP_TAPS);
		} else {
			near = sample_near(dir_uv(funnel_dir(e, rr, uu, rn * s_near, tn + a_near), stars_offset));
		}

		vec3 col = far * (1.0 - near.a) + near.rgb * star_brightness;

		// Augenwand / Wetterleuchten: nur beleuchtete Wolken heben sich (Schwarz
		// bleibt schwarz), begrenzt auf die Wand um das Auge.
		float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
		float litk = smoothstep(0.004, 0.06, l);
		col *= mix(1.0, star_hdr, smoothstep(0.10, 0.30, l) * inner);
		float lon = atan(dir.x, -dir.z);
		float lat = asin(clamp(dir.y, -1.0, 1.0));
		float front = exp(-(lon / 0.62) * (lon / 0.62)) * smoothstep(0.02, -0.30, lat);
		float sector = 0.5 + 0.5 * cos(th - TIME * 0.9);
		float wall = inner * (0.7 + 0.3 * sector) * (1.0 - 0.9 * front);
		col *= 1.0 + litk * (0.42 * b * wall + 0.9 * lb * sector * (1.0 - 0.9 * front) * exp(-max(rdeg - eye_radius, 0.0) / 16.0));
		col += glow_color * (0.006 * b + 0.012 * lb * sector) * inner * smoothstep(eye_radius * 0.95, eye_radius * 1.3, rdeg);

		col *= tint * brightness;

		// Unterer Trichter (unter dem Horizont) abgedunkelt, vorn-mitte zusaetzlich.
		col *= mix(1.0, 0.42, smoothstep(0.0, -0.40, lat));
		col *= 1.0 - readability * 0.6 * front;

		float h = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
		col = max(col * (1.0 + h * 0.03) + h * 0.00025, vec3(0.0));
		COLOR = col;
	}
}
