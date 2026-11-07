shader_type sky;

// Welt-Thema "Eklipse": schwarze Sonne ueber verbrannter Ebene. Duester,
// gefaehrlich, fast farblos (Schwarz/Anthrazit + mattes Gold-Weiss), kein Neon.
// Panorama offline: tools/gen_theme_eclipse.py -> assets_game/themes/eclipse/
//   eclipse_sky.webp  Himmel, Korona, Ascheschleier, Ruinen, Ebene (RGBA,
//                     Alpha = freier Himmel 1 / Ruinen+Boden 0)
//   eclipse_ash.webp  kachelbare Asche-Ebene: RGB-Grau = Flocken, A = Schwaden
//                     (lineare Daten, zylindrisch abgebildet, steigt auf)
// Der Shader zeichnet den Sonnenrand scharf (bildschirmaufgeloest), einen
// Diamantring-Funken, laesst die Korona dezent auf dem Beat pulsieren und
// treibt die Asche in zwei Parallax-Lagen vor Himmel und Ruinen.
//
// Uniform-Interface wie shaders/sky_panorama.gdshader (gleiche Namen/Bedeutung):
//   tex_a / tex_b / palette_mix   Panorama (wurzel-kodiert, linear = textur^2),
//                                 Ueberblendung a->b wie dort.
//   stars_a / stars_b             optionale Sternen-Ebene (Standard schwarz,
//                                 die wenigen Sterne sind im Panorama).
//   tint, brightness, star_brightness, star_hdr, beat_pulse, readability,
//   pano_rotation/pano_offset, stars_rotation/stars_offset.
//   star_speed / star_phase       hier: Asche-Drift (Phase in Asche-Kacheln;
//                                 Spiel zaehlt star_phase hoch, Vorschau nutzt
//                                 star_speed). Asche steigt zusaetzlich stetig
//                                 mit ash_rise.
//   warp 0..1                     Geschwindigkeits-Unschaerfe: Flocken ziehen
//                                 Streifen, Korona-Strahlen gluehen etwas.
// Eklipse-eigene Uniforms: sun_*, corona_hdr, bead_*, ash_*, kiai (0..1,
// Kiai-Gewicht vom Spiel: Korona und Diamantring heller).
//
// beat_pulse: 1 auf dem Schlag, klingt bis zum naechsten auf 0 ab (z.B.
// pow(1 - beat_phase, 4)). Korona hebt sich leicht, eine schwache Welle laeuft
// vom Sonnenrand nach aussen, der Diamantring blitzt (ueber Glow-Schwelle).
// Sonnen-Lage sun_lon/sun_lat/sun_radius muss zum Generator passen
// (SUN_LON/SUN_LAT/SUN_R), sonst sitzt der scharfe Rand neben der Scheibe.
// Cubemap-Pass (Radiance) ohne Asche/Rand.
//
// BEAT-VERTRAG (docs/worlds/beat_contract.md):
//   beat_step       KORONA-SCHOCKRING: auf jedem Schlag schiesst ein Ring vom Sonnenrand
//                   nach aussen (Easing: Anschlag exakt auf dem Schlag, dann Ruhe), der
//                   Diamantring-Funke springt ein Stueck um die Sonne, die Asche stoesst
//                   aufwaerts.
//   downbeat_pulse  Takt-Akzent: Ring und Korona-Fuss kraeftiger, langsamer abklingend.
//   drop            Verwandlung: Korona weitet sich weit nach aussen, Diamantring gleisst
//                   staerker, Asche dichter und schneller; Luma gedeckelt.
//   kiai/energy     wie bisher Korona/Ring heller; comfort halbiert alle Bewegung.
//   beat_phase, bar_phase  Saegezaehne (Preview-Kontrolle).
//
// INTEGRATION (wie sky_panorama):
//   var mat := ShaderMaterial.new()
//   mat.shader = load("res://shaders/theme_eclipse.gdshader")
//   mat.set_shader_parameter("tex_a", load("res://assets_game/themes/eclipse/eclipse_sky.webp"))
//   mat.set_shader_parameter("ash_a", load("res://assets_game/themes/eclipse/eclipse_ash.webp"))
//   sky.sky_material = mat ... pro Frame beat_pulse, star_phase (oder star_speed).
// Import beider WebP: verlustfrei, ohne Mipmaps, process/fix_alpha_border=false
// (sonst ueberschreibt der Import die Farben unter Alpha 0).
//
// FARBSATZ fuer Strecke / Kanten / Pads (sRGB-Hex; mattes Gold-Weiss auf Schwarz,
// keine Saettigung, kein Neon):
//   Strecke Grund        #070707  (Alpha 0.94, fast schwarz)
//   Strecke Welle        #cdb98c  (road_wave base_color, mattes Gold, schwach)
//   Spurlinien           #2b2823  (Alpha 0.55, Anthrazit-warm)
//   Kanten (aussen)      #d8c69c  Emission 0.55 (Beat -> #f3e9d0, 1.2)
//   Kanten Kiai          #fff4dc  (Weiss-Gold, Emission 1.4)
//   Pads Ring            #e6dbc2  fill_alpha 0.16
//   Pads Treffer         #ffffff -> #f3e9d0
//   Noten                #f1ead9 (Weiss-Gold) / #c7a866 (mattes Gold) je Spurpaar,
//                        Kern weiss; Holds #c7a866
//   Kiai / Diamantring   #fff6e2
//   Funken               #f3e4c0 (kurz, wenige), keine farbigen Partikel
//   Ambient              #0a0a0a, Glow-Schwelle 0.92 wie mania_3d

uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D stars_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D stars_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D ash_a : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D ash_b : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D shards_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform float palette_mix : hint_range(0.0, 1.0) = 0.0;

uniform vec3 tint : source_color = vec3(1.0);
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.0;
uniform float star_hdr : hint_range(1.0, 4.0) = 1.5;
uniform float beat_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float kiai : hint_range(0.0, 1.0) = 0.0;
uniform float beat_phase : hint_range(0.0, 1.0) = 0.0;
uniform float bar_phase : hint_range(0.0, 1.0) = 0.0;
uniform float beat_step = 0.0;
uniform float downbeat_pulse : hint_range(0.0, 1.0) = 0.0;
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

// Sonne (Grad, wie Generator) und Korona
uniform float sun_lon = 0.0;
uniform float sun_lat = 5.0;
uniform float sun_radius = 6.5;
uniform vec3 corona_color : source_color = vec3(1.0, 0.955, 0.855);
uniform float corona_hdr : hint_range(1.0, 4.0) = 1.35;
uniform float limb_intensity : hint_range(0.0, 4.0) = 1.1;
uniform float bead_angle = 2.25;     // rad, Positionswinkel (0 rechts, +oben)
uniform float bead_intensity : hint_range(0.0, 6.0) = 2.4;
// Asche
uniform vec3 ash_light : source_color = vec3(0.86, 0.80, 0.68);
uniform float ash_density : hint_range(0.0, 2.0) = 1.0;
uniform float ash_rise = 0.010;      // Kacheln/s aufwaerts
uniform float ash_drift = 0.0025;    // Kacheln/s seitlich

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

// Mip-Sampling mit nahtfreien Gradienten (fract(u) springt an der Naht).
vec4 tg(sampler2D s, vec2 uv) {
	vec2 gx = dFdx(uv);
	vec2 gy = dFdy(uv);
	gx.x -= round(gx.x);
	gy.x -= round(gy.x);
	return textureGrad(s, uv, gx, gy);
}

vec3 dec(vec3 c) {
	return c * c;
}

vec4 sample_pano(vec2 uv) {
	if (palette_mix <= 0.001) {
		vec4 a = tg(tex_a, uv);
		return vec4(dec(a.rgb), a.a);
	}
	if (palette_mix >= 0.999) {
		vec4 b = tg(tex_b, uv);
		return vec4(dec(b.rgb), b.a);
	}
	vec4 a = tg(tex_a, uv);
	vec4 b = tg(tex_b, uv);
	return mix(vec4(dec(a.rgb), a.a), vec4(dec(b.rgb), b.a), palette_mix);
}

vec3 sample_stars(vec2 uv) {
	if (palette_mix <= 0.001) {
		return dec(tg(stars_a, uv).rgb);
	}
	if (palette_mix >= 0.999) {
		return dec(tg(stars_b, uv).rgb);
	}
	return mix(dec(tg(stars_a, uv).rgb), dec(tg(stars_b, uv).rgb), palette_mix);
}

vec4 sample_ash(vec2 uv) {
	if (palette_mix <= 0.001) {
		return tg(ash_a, uv);
	}
	if (palette_mix >= 0.999) {
		return tg(ash_b, uv);
	}
	return mix(tg(ash_a, uv), tg(ash_b, uv), palette_mix);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 sun_vec(float lon_d, float lat_d) {
	float lo = radians(lon_d), la = radians(lat_d);
	return vec3(sin(lo) * cos(la), sin(la), -cos(lo) * cos(la));
}

// Asche-Lage: zylindrische Abbildung (Kachel 4:1 ueber 360 Grad), steigt auf.
// scale = ganzzahlige Wiederholung (naht-frei), rise/drift in Kacheln,
// jit = Pixel-Jitter fuer die Warp-Streifen (FRAGCOORD nur in sky()).
vec4 ash_layer(float u, float h, float scale, float rise, float drift, float seed, float jit) {
	float v = -h / (0.5 * PI);
	vec2 uv = vec2(u * scale + drift + seed, v * scale + rise + seed * 1.7);
	uv.x += 0.004 * sin(uv.y * 9.0 + TIME * 0.21 + seed * 5.0);
	if (warp > 0.01) {
		vec4 acc = vec4(0.0);
		float wsum = 0.0;
		for (int i = 0; i < 6; i++) {
			float k = (float(i) + jit) / 6.0;
			float wk = 1.0 - 0.6 * k;
			acc += sample_ash(uv + vec2(0.0, warp * 0.018 * k)) * wk;
			wsum += wk;
		}
		vec4 a = acc / wsum;
		a.rgb *= 1.0 + warp * 0.8;
		return a;
	}
	return sample_ash(uv);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 pd = dir * euler(pano_rotation);
	vec2 puv = dir_uv(pd, pano_offset);
	vec4 pan4 = sample_pano(puv);
	vec3 pan = pan4.rgb;
	float vis = pan4.a; // 1 = freier Himmel

	// Sonnen-Koordinaten im Panorama-Rahmen.
	vec3 s = sun_vec(sun_lon, sun_lat);
	float lo = radians(sun_lon), la = radians(sun_lat);
	vec3 e_east = vec3(cos(lo), 0.0, sin(lo));
	vec3 e_north = vec3(-sin(lo) * sin(la), cos(la), cos(lo) * sin(la));
	float theta = 2.0 * asin(clamp(length(pd - s) * 0.5, 0.0, 1.0));
	float rad_r = radians(sun_radius);
	float r = theta / rad_r;
	vec2 q = vec2(dot(pd, e_east), dot(pd, e_north)) / sin(rad_r);
	float ph_ang = atan(q.y, q.x);

	// Korona: helle Anteile ueber die Glow-Schwelle, dezent atmend.
	float nl = dot(pan, vec3(0.2126, 0.7152, 0.0722));
	float mv = 1.0 - 0.5 * comfort;
	float dp = drop * (1.0 - 0.5 * comfort);
	float ep = clamp(fract(beat_step - 1e-5), 0.0, 1.0);
	if (beat_step < 0.0001) {
		ep = 0.0;
	}
	float cm = smoothstep(0.99, 1.03, r) * exp(-(r - 1.0) / (1.8 + 2.4 * dp)) * step(theta, 1.2 + 0.5 * dp);
	float bp = clamp(beat_pulse, 0.0, 1.0);
	float shimmer = 1.0 + 0.07 * sin(ph_ang * 11.0 + TIME * 0.35) * sin(ph_ang * 5.0 - TIME * 0.23 + r * 3.0);
	// Schockring auf beat_step: huellt sich mit sin(pi*ep) -> weder Sprung am Schlag noch Rest.
	float wave_r = 1.0 + ep * 2.6;
	float wave = exp(-pow((r - wave_r) / (0.16 + 0.10 * ep), 2.0)) * sin(PI * ep) * mv;
	float lift = 1.0 + cm * (bp * (0.10 + 0.32 * exp(-(r - 1.0) / 0.22)) + wave * (0.55 + 0.7 * downbeat_pulse)
			+ downbeat_pulse * mv * 0.22 * exp(-(r - 1.0) / 0.5) + kiai * 0.30 + dp * 0.55);
	pan *= mix(1.0, corona_hdr, smoothstep(0.30, 0.70, nl) * cm);
	pan *= mix(1.0, shimmer, cm) * lift;

	if (AT_CUBEMAP_PASS) {
		COLOR = pan * tint * brightness * 0.5;
	} else {
		vec3 col = pan;
		vec3 st = sample_stars(dir_uv(dir * euler(stars_rotation), stars_offset));
		float sl = dot(st, vec3(0.2126, 0.7152, 0.0722));
		st *= star_brightness * mix(1.0, star_hdr, smoothstep(0.55, 1.0, sl)) * (1.0 + bp * 0.3);
		col += st * step(0.0, dir.y) * vis * step(1.0, r);

		// Scharfer Sonnenrand (Bildschirmaufloesung) nur vor freiem Himmel.
		float fw = max(fwidth(r), 1e-4);
		float outside = smoothstep(1.0 - fw, 1.0 + fw, r);
		col = mix(col, vec3(0.0003), (1.0 - outside) * vis);
		float ring = outside * exp(-(r - 1.0) / (0.009 + fw * 1.2));
		float limb_n = 0.75 + 0.25 * sin(ph_ang * 23.0 + 1.3) * sin(ph_ang * 9.0 - 0.4);
		col += corona_color * ring * limb_n * limb_intensity * (1.0 + bp * 0.7 + kiai * 0.5) * vis;
		// Diamantring: ein Lichtfunke am Rand.
		float bang = bead_angle + beat_step * 0.30 * mv;     // Funke rastet je Schlag ein Stueck weiter
	vec2 bpos = vec2(cos(bang), sin(bang)) * 1.004;
		float bd = length(q - bpos);
		float bead = exp(-bd * bd / (0.0008 + fw * fw)) * 1.4
				+ exp(-bd / 0.06) * 0.45 + exp(-bd / 0.35) * 0.05;
		col += corona_color * bead * bead_intensity * (0.75 + bp * 0.9 + kiai * 0.8 + dp * 1.1 + downbeat_pulse * 0.5) * mix(0.25, 1.0, outside) * vis;

		// Asche: zwei Lagen (nah grob/schnell, fern fein/langsam) + Schwaden.
		float latd = degrees(asin(clamp(dir.y, -1.0, 1.0)));
		float am = smoothstep(-7.0, 1.0, latd) * (1.0 - smoothstep(22.0, 55.0, latd)) * ash_density * (1.0 + 0.5 * dp);
		if (am > 0.001) {
			float u = atan(dir.x, -dir.z) * (0.5 / PI);
			float h = tan(radians(clamp(latd, -60.0, 60.0)));
			float ph = star_phase + TIME * star_speed;
			float t = TIME * ash_rise + ph * 0.03 + beat_step * 0.003 * mv;   // Asche stoesst je Schlag aufwaerts
			float dr = TIME * ash_drift;
			float jit = hash12(FRAGCOORD.xy);
			vec4 nearl = ash_layer(u, h, 1.0, t, dr, 0.0, jit);
			vec4 farl = ash_layer(u, h, 2.0, t * 0.6 + 0.37, -dr * 0.5, 0.53, fract(jit + 0.5));
			// Gegenlicht der Korona (wie im Generator) beleuchtet Asche.
			float thd = degrees(theta);
			float bl = exp(-max(thd - sun_radius, 0.0) / 9.0) * 0.75 + exp(-thd / 38.0) * 0.25;
			float lit = (0.004 + 0.07 * bl * bl) * mix(0.12, 1.0, outside);
			float fn = nearl.r * am;
			float ff = farl.r * am * 0.6;
			float veil = mix(nearl.a, farl.a, 0.4) * am;
			col *= 1.0 - veil * 0.22;
			col += ash_light * veil * (0.0006 + 0.007 * bl * bl) * mix(0.1, 1.0, outside);
			col = col * (1.0 - ff * 0.6) + ash_light * ff * lit * 0.55 * (1.0 + bp * 0.25);
			col = col * (1.0 - fn * 0.85) + ash_light * fn * lit * (1.0 + bp * 0.35);
		}

		// Nahe Objekt-Ebene (Stil Fraktal-Splitter): Brocken ziehen am Spieler vorbei,
		// Gier rastet mit beat_step auf dem Schlag ein; Drop = schneller/naeher/heller.
		{
			float s_mv = 1.0 - 0.5 * comfort;
			float s_dp = drop * (1.0 - 0.5 * comfort);
			float s_yaw = TIME * 0.004 * s_mv + beat_step * 0.012 * s_mv + s_dp * 0.07;
			vec3 s_d = dir * euler(vec3(0.0, s_yaw, 0.0));
			s_d.y = dir.y + s_dp * 0.03 * (1.0 - abs(dir.y));          // Drop: naeher heran
			vec4 s_sh = tg(shards_tex, dir_uv(normalize(s_d), vec2(0.0)));
			float s_lon = atan(dir.x, -dir.z);
			float s_lat = asin(clamp(dir.y, -1.0, 1.0));
			float s_gate = smoothstep(0.03, 0.12, s_lat) * (1.0 - exp(-(s_lon / 0.5) * (s_lon / 0.5)) * smoothstep(0.9, 0.5, s_lat));
			vec3 s_c = dec(s_sh.rgb) * (1.0 + beat_pulse * 0.30 + downbeat_pulse * 0.25 * s_mv + s_dp * 0.6);
			col = mix(col, s_c, s_sh.a * s_gate * step(0.0, dir.y));
		}
		col *= tint * brightness;

		// Lesbarkeit in Weltkoordinaten: vorn-mitte/unten zusaetzlich dunkler.
		float lon = atan(dir.x, -dir.z);
		float lat = asin(clamp(dir.y, -1.0, 1.0));
		float front = exp(-(lon / 0.62) * (lon / 0.62)) * smoothstep(0.02, -0.30, lat);
		col *= 1.0 - readability * 0.6 * front;

		float hd = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
		col = max(col * (1.0 + hd * 0.03) + hd * 0.00025, vec3(0.0));
		COLOR = col;
	}
}
