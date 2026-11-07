shader_type sky;

// Welt-Thema "Fraktal": schwarzer Raum voller Obsidian-Splitter und
// kristalliner Stachel-Cluster, kalte Glanzkanten in gedaempftem Karmin.
// Abstrakt, duester, schneidend, fast monochrom (Schwarz, kaltes Grau, Karmin).
// Panoramen offline: tools/gen_theme_fractal.py -> assets_game/themes/fractal/
//   fractal_sky.webp          fern: Raum, Karmin-Schein am Horizont, fernes Stachelfeld
//   fractal_sky_shards.webp   nah (RGBA, Alpha = Deckung): Riesen-Splitter/-Drusen
//
// Bewegung (thementypisch, nie Flackern, nie Vollbild-Blitz):
//   - Splitter-Ebene kreist langsam um den Spieler (star_phase * shards_drift,
//     Fern-Ebene mit pano_drift = Parallax).
//   - Bruch-Welle auf jedem Beat: ein Lichtband laeuft vom Fluchtpunkt
//     ueber die Kristalle nach aussen und zieht die Glanzkanten nach (nur
//     Lichter werden heller, Schwarz bleibt schwarz).
//   - Kanten atmen mit beat_pulse (sanftes Heben, Bloom ueber edge_hdr).
//   - Schliff-Glanz: ein sehr langsamer Lichtschimmer wandert ueber die Facetten.
// Vorn-mitte/unten (Strecke) bleibt dunkel: readability + Welle/Puls werden
// dort ausgeblendet.
//
// Uniform-Interface wie shaders/sky_panorama.gdshader (gleiche Namen/Bedeutung):
//   tex_a / tex_b / palette_mix   Fern-Panorama (wurzel-kodiert, linear = textur^2)
//   stars_a / stars_b             optionale additive Sternen-Ebene (Standard schwarz)
//   tint, brightness, star_brightness, star_hdr, beat_pulse, readability,
//   pano_rotation/pano_offset, stars_rotation/stars_offset.
//   star_speed / star_phase       hier: Kreisen der Splitter (Phase-Einheiten/s
//                                 bzw. Phase); Winkel = Phase * shards_drift rad.
//                                 Fuer variable Geschwindigkeit star_speed = 0,
//                                 star_phase hochzaehlen.
//   warp 0..1                     Geschwindigkeits-Unschaerfe: die Splitter
//                                 ziehen radiale Schlieren aus dem Fluchtpunkt.
// Fraktal-eigene Uniforms: shards_a / shards_b (Splitter-Ebene, RGBA,
// Ueberblendung mit palette_mix), shards_rotation/shards_offset, shards_drift,
// pano_drift, edge_hdr, wave_*, shimmer.
//
// BEAT-VERTRAG (docs/worlds/beat_contract.md):
//   Signatur "Zahnrad": drei Splitter-Ebenen (fern fractal_sky, Mitte
//   fractal_sky_mid, nah fractal_sky_shards) rasten mit beat_step ruckartig
//   weiter, gegenlaeufig (nah +0.9, Mitte -1.4, fern +0.3 Grad je Beat);
//   Rasten genau auf dem Schlag, Ruhe bis zum naechsten.
//   downbeat_pulse: zweiter, breiterer Bruchring ab Fluchtpunkt (Taktanfang).
//   drop: die Splitter ruecken naeher (Zoom bis +18 %), Kanten gluehen
//   staerker, Nebelschein weitet sich; gedeckelt, kein Blitz.
//   comfort: Rasten halbiert.
//
// beat_pulse: 1 auf dem Schlag, klingt bis zum naechsten ab (beliebige
// monotone Kurve, z.B. exp-Abfall oder pow(1 - beat_phase, 4)). Die Welle
// steht bei beat_pulse = 1 am Fluchtpunkt und erreicht wave_reach (rad), wenn
// beat_pulse gegen 0 geht.
//
// INTEGRATION (wie sky_panorama, mania_3d._build_theme_sky fuellt die Sampler
// per Konvention: tex_a = fractal_sky.webp, shards_a = fractal_sky_shards.webp):
//   var mat := ShaderMaterial.new()
//   mat.shader = load("res://shaders/theme_fractal.gdshader")
//   mat.set_shader_parameter("tex_a", load("res://assets_game/themes/fractal/fractal_sky.webp"))
//   mat.set_shader_parameter("shards_a", load("res://assets_game/themes/fractal/fractal_sky_shards.webp"))
//   sky.sky_material = mat ... pro Frame beat_pulse, star_phase (oder star_speed).
//
// FARBSATZ fuer Strecke / Kanten / Pads (sRGB-Hex; Schwarz + gedaempftes Karmin,
// kein Neon, keine zweite Farbe - Akzente sind hellere Stufen desselben Karmins):
//   Strecke Grund        #050304  (Obsidian-Schwarz, Alpha 0.94)
//   Strecke Welle        #7a1024  (road_wave base_color, tiefes Karmin)
//   Spurlinien           #2a1a1e  (Alpha 0.55, kaltes Dunkelgrau mit Karmin-Stich)
//   Kanten (aussen)      #a3142f  Emission 0.75 (Beat-Spitze -> #d8455c, 1.6)
//   Kanten Kiai          #e0566b  (helleres Karmin, Emission 1.4)
//   Pads Ring            #b5223c  fill_alpha 0.16
//   Pads Treffer         #f2d6da -> #b5223c (fast weiss, kalt, klingt in Karmin aus)
//   Noten                #e6e2e4 (kaltes Weiss) / #c42a45 (Karmin) je Spurpaar,
//                        Kern weiss; Holds #a3142f
//   Kiai                 #d8455c -> #f2d6da (line -> kiai in WorldTheme.PALETTES:
//                        line #a3142f, kiai #e0566b)
//   Funken / Laser       #d8455c / #e6e2e4
//   Ambient              #0a0507, Glow-Schwelle 0.92 wie mania_3d

uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D stars_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D stars_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D shards_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D shards_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
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

// Fraktal
uniform vec3 shards_rotation = vec3(0.0);
uniform vec2 shards_offset = vec2(0.0);
uniform float shards_drift = 0.22;    // rad Gier je Phase-Einheit (nahe Ebene)
uniform float pano_drift = 0.07;      // dito ferne Ebene (Parallax)
uniform float edge_hdr : hint_range(1.0, 6.0) = 2.4;  // Glanzkanten ueber die Glow-Schwelle
uniform vec3 wave_color : source_color = vec3(0.85, 0.27, 0.36);
uniform float wave_intensity : hint_range(0.0, 4.0) = 1.0;
uniform float wave_reach = 1.9;       // rad vom Fluchtpunkt, Endradius der Welle
uniform float wave_width = 0.16;      // rad
uniform float shimmer : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D mid_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D mid_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform float beat_phase : hint_range(0.0, 1.0) = 0.0;
uniform float bar_phase : hint_range(0.0, 1.0) = 0.0;
uniform float beat_step = 0.0;
uniform float downbeat_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float kiai : hint_range(0.0, 1.0) = 0.0;
uniform float drop : hint_range(0.0, 0.6) = 0.0;
uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float comfort : hint_range(0.0, 1.0) = 0.0;
uniform float ratchet_near = 0.9;     // Grad je Beat
uniform float ratchet_mid = -1.4;
uniform float ratchet_far = 0.3;

const int WARP_TAPS = 12;

// Scharf bei Verkleinerung: Mip-Stufe aus dem Winkel je Pixel (aus der
// stetigen Blickrichtung, daher keine Naht am Panorama-Rand).
float afp = 0.0;
vec4 tx(sampler2D t, vec2 uv) {
	float lod = max(log2(max(afp * float(textureSize(t, 0).x), 1.0)), 0.0);
	return textureLod(t, uv, lod);
}

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

vec3 sample_pair(sampler2D a, sampler2D b, vec2 uv) {
	if (palette_mix <= 0.001) {
		return dec(tx(a, uv).rgb);
	}
	if (palette_mix >= 0.999) {
		return dec(tx(b, uv).rgb);
	}
	return mix(dec(tx(a, uv).rgb), dec(tx(b, uv).rgb), palette_mix);
}

// Splitter: Farbe linear vormultipliziert (rgb * a), a = Deckung.
vec4 shard_at(vec2 uv) {
	vec4 s;
	if (palette_mix <= 0.001) {
		s = tx(shards_a, uv);
	} else if (palette_mix >= 0.999) {
		s = tx(shards_b, uv);
	} else {
		s = mix(tx(shards_a, uv), tx(shards_b, uv), palette_mix);
	}
	return vec4(dec(s.rgb) * s.a, s.a);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec4 mid_at(vec2 uv) {
	vec4 s = tx(mid_a, uv);
	return vec4(dec(s.rgb) * s.a, s.a);
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	afp = length(fwidth(dir)) * 0.159155;
	float ph = star_phase + TIME * star_speed;
	float cm = 1.0 - 0.5 * comfort;
	float rk = radians(cm) * beat_step;
	float dk = clamp(drop / 0.6, 0.0, 1.0);
	vec3 prot = pano_rotation + vec3(0.0, ph * pano_drift + rk * ratchet_far, 0.0);
	vec3 srot = shards_rotation + vec3(0.0, ph * shards_drift + rk * ratchet_near, 0.0);
	vec3 mrot = vec3(0.0, ph * (pano_drift + shards_drift) * 0.5 + rk * ratchet_mid, 0.0);
	float zs = 1.0 + 0.18 * dk;
	vec3 pan = sample_pair(tex_a, tex_b, dir_uv(dir * euler(prot), pano_offset));

	if (AT_CUBEMAP_PASS) {
		vec4 sh = shard_at(dir_uv(dir * euler(srot), shards_offset));
		vec4 mh = mid_at(dir_uv(dir * euler(mrot), shards_offset));
		pan = pan * (1.0 - mh.a) + mh.rgb;
		COLOR = (pan * (1.0 - sh.a) + sh.rgb) * tint * brightness * 0.5;
	} else {
		float bp = clamp(beat_pulse, 0.0, 1.0);
		mat3 sm = euler(srot);
		vec4 sh;
		if (warp > 0.001) {
			// Radiale Schlieren: Splitter entlang des Zooms mehrfach abtasten.
			vec4 acc = vec4(0.0);
			float wsum = 0.0;
			float jit = hash12(FRAGCOORD.xy);
			for (int i = 0; i < WARP_TAPS; i++) {
				float k = (float(i) + jit) / float(WARP_TAPS);
				float wk = 1.0 - 0.7 * k;
				acc += shard_at(dir_uv(zoom_dir(dir, 1.0 + warp * 0.10 * k) * sm, shards_offset)) * wk;
				wsum += wk;
			}
			sh = acc / wsum;
		} else {
			sh = shard_at(dir_uv(zoom_dir(dir, zs) * sm, shards_offset));
		}

		// Lesbarkeit in Weltkoordinaten: vorn-mitte/unten (hinter der Strecke).
		float lon = atan(dir.x, -dir.z);
		float lat = asin(clamp(dir.y, -1.0, 1.0));
		float front = exp(-(lon / 0.62) * (lon / 0.62)) * smoothstep(0.02, -0.30, lat);
		float open = 1.0 - front;

		// Glanzkanten: hellste Splitter-Pixel (Karmin) heben sich ueber die
		// Glow-Schwelle; Schwarz bleibt schwarz.
		float sl = luma(sh.rgb);
		float edge = smoothstep(0.012, 0.09, sl);

		// Bruch-Welle vom Fluchtpunkt (Winkelabstand zu -Z) nach aussen.
		float ang = acos(clamp(-dir.z, -1.0, 1.0));
		float wr = wave_reach * (1.0 - bp);
		float band = exp(-pow((ang - wr) / wave_width, 2.0));
		float tail = exp(-max(wr - ang, 0.0) / (wave_width * 3.0)) * step(ang, wr) * 0.35;
		// Taktanfang: breiterer zweiter Ring (langsamer, downbeat_pulse).
		float dbp = clamp(downbeat_pulse, 0.0, 1.0);
		float wr2 = wave_reach * (1.0 - dbp);
		float ring2 = exp(-pow((ang - wr2) / (wave_width * 2.2), 2.0)) * smoothstep(0.0, 0.2, dbp) * 0.6;
		float wave = (band + tail + ring2) * smoothstep(0.0, 0.15, bp) * smoothstep(0.05, 0.4, ang) * open;

		// Schliff-Glanz: langsamer Schimmer ueber die Facetten (ohne Beat).
		vec3 sd = dir * sm;
		float shim = sin(dot(sd, vec3(7.0, 3.0, -5.0)) + TIME * 0.35) * sin(dot(sd, vec3(-4.0, 6.0, 3.0)) - TIME * 0.27);
		shim = 1.0 + shimmer * 0.35 * shim;

		vec3 shc = sh.rgb * (1.0 + edge * (edge_hdr - 1.0) * (0.55 + 0.45 * bp) * open) * shim;
		shc *= 1.0 + bp * 0.35 * edge * open;
		shc += wave_color * wave * edge * sh.a * wave_intensity * 0.9;
		// Facetten fangen den Wellen-Schein schwach (Obsidian spiegelt), Raum nicht.
		shc += wave_color * wave * sh.a * 0.012 * wave_intensity;

		// Fern-Ebene: Horizont-Schein atmet leicht mit, Lichter der Fernkristalle.
		float pl = luma(pan);
		pan *= 1.0 + bp * (0.08 + 4.0 * pl) * open;
		pan += wave_color * wave * smoothstep(0.004, 0.03, pl) * 0.04 * wave_intensity;

		shc *= 1.0 + dk * 0.9 * edge * open;
		// Mittel-Ebene (Zahnrad gegenlaeufig), vor dem Fern-Panorama, hinter den Giganten.
		vec4 mh = mid_at(dir_uv(zoom_dir(dir, 1.0 + 0.10 * dk) * euler(mrot), shards_offset));
		float ml = luma(mh.rgb);
		float medge = smoothstep(0.010, 0.08, ml);
		vec3 mc = mh.rgb * (1.0 + medge * (edge_hdr - 1.0) * (0.45 + 0.4 * bp + 0.6 * dk) * open);
		mc += wave_color * ring2 * medge * mh.a * wave_intensity * 0.5 * open;
		pan = pan * (1.0 - mh.a) + mc;
		vec3 col = pan * (1.0 - sh.a) + shc;
		vec3 st = sample_pair(stars_a, stars_b, dir_uv(dir * euler(stars_rotation), stars_offset));
		float stl = luma(st);
		st *= star_brightness * mix(1.0, star_hdr, smoothstep(0.55, 1.0, stl)) * (1.0 + bp * 0.5);
		col += st * (1.0 - sh.a);
		col *= tint * brightness;
		col *= 1.0 - readability * 0.6 * front;

		float h = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
		col = max(col * (1.0 + h * 0.03) + h * 0.00025, vec3(0.0));
		COLOR = col;
	}
}
