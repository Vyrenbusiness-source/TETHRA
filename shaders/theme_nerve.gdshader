shader_type sky;

// Welt-Thema "Nerv": ein unendliches Netz schwarzer Fasern, Synapsen-Impulse in dunklem
// Bordeaux laufen im Takt durch das Netz (tools/gen_theme_nerve.py). Ebenen aus
// assets_game/themes/nerve/ (alle 8192x4096, BPTC + Mipmaps):
//   Ferne    (tex_a/tex_b)     nerve_sky.webp          Dunst, ferne unscharfe Fasern, Bordeaux-Nebel
//   Netz     (net_a)           nerve_net.webp          RGBA mittlere Ebene: Fasern, RGB = Kantenlicht, A = Deckkraft
//   Impulse  (pulse_a)         nerve_pulse.webp        DATEN (nicht sRGB): R/G = cos/sin der Bogenlaenge
//                                                      entlang der Faser, B = Faser-Hash, A = Synapsenknoten
//   Nah      (near_a)          nerve_near.webp         nahe RGBA-Ebene: dicke Faserbuendel + Ganglien (Parallax)
//   Sporen   (stars_a/stars_b) nerve_spores.webp       schwebende Sporen (Panorama, Parallax)
// Uniform-Interface wie shaders/sky_panorama.gdshader (Panorama-Abbildung
// u = atan(d.x,-d.z)/2pi+0.5, v = 0.5-asin(d.y)/pi, Wurzel-Kodierung linear = pow(tex, 2)).
// LOD kommt aus der naht-freien Richtungsableitung (fwidth(dir)), kein Mip-Streifen an der Naht.
//
// BEAT-VERTRAG (docs/worlds/beat_contract.md):
//   beat_step      Signatur: Impulse fliessen glatt die Fasern entlang (eine halbe Periode je
//                  Schlag, auf dem Schlag leicht schneller, kein Stop-and-go). Das Netz giert
//                  nur gleichmaessig ueber TIME (<= 0.8 Grad/s, Parallax), nie ueber beat_step
//   downbeat_pulse alle Impulse + Synapsenknoten akzentuiert auf dem Taktanfang, Nah-Ebene Kantenlicht
//   bar_phase      eine langsame Bordeaux-Welle laeuft pro Takt ueber die Ferne
//   beat_phase     Knoten atmen innerhalb des Schlags
//   beat_pulse     Knoten + Impulse atmen auf dem Schlag
//   kiai/energy    Dunst, Sporen, Impulse minimal heller
//   drop           das Netz zieht sich zur Flugachse zusammen (Zoom 1 -> 0.78 mid, 0.68 nah),
//                  Impulse heller, Knoten gluehen
//   comfort        Bewegung halbiert, keine Welle
//
// FARBSATZ fuer Strecke/Kanten/Pads (Bordeaux auf Schwarz, fast monochrom, KEIN Neon):
//   Strecke (Belag)      #060405  fast schwarz, Alpha ~0.92
//   Spur-Trennlinien     #231318  Alpha ~0.55
//   Kanten (Rail/Rand)   #8a6a72  gedecktes Rosegrau, HDR x1.2
//   Abfanglinie          #c9a2ab  Fasern-Licht, HDR x1.5
//   Pads (Ruhe)          #0f090b  Fuellung, Rand #8a6a72
//   Pads (gedrueckt)     #c9a2ab  Rand, Fuellung #33151d
//   Noten                #f3e6e8  helles Rosaweiss (hellstes Element)
//   Hold-Strahl          #8a6a72 -> #c9a2ab Verlauf
//   Treffer-Funken       #c9a2ab, Perfect #f3e6e8
//   Impulse (Welt)       #5c0f20  dunkles Bordeaux, Knoten #7a1a2e
//   Umgebungslicht       #0a0607, Glow-Schwelle wie Spiel (0.92)
//   Theme-Farbe (Hue)    0.97 (Bordeaux, kaum gesaettigt)

uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D net_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D pulse_a : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D near_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_transparent;
uniform sampler2D stars_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform sampler2D stars_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
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

const vec3 PULSE_COL = vec3(0.115, 0.0045, 0.0143);  // #5c0f20, dunkles Bordeaux
const vec3 NODE_COL = vec3(0.19, 0.010, 0.027);     // #7a1a2e
const float TEX_W = 8192.0;

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

// Stereografischer Zoom um die Flugrichtung (-Z), wie sky_panorama. s < 1 zieht Inhalt zur Achse.
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

// Drehung um die Hochachse (Orbit des Netzes).
vec3 yaw_dir(vec3 d, float a) {
	float cy = cos(a), sy = sin(a);
	return vec3(cy * d.x + sy * d.z, d.y, -sy * d.x + cy * d.z);
}

vec3 dec(vec3 c) {
	return c * c;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 pano_at(sampler2D a, sampler2D b, vec2 uv, float lod) {
	if (palette_mix <= 0.001) {
		return dec(textureLod(a, uv, lod).rgb);
	}
	if (palette_mix >= 0.999) {
		return dec(textureLod(b, uv, lod).rgb);
	}
	return mix(dec(textureLod(a, uv, lod).rgb), dec(textureLod(b, uv, lod).rgb), palette_mix);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float lon = atan(dir.x, -dir.z);
	float lat = asin(clamp(dir.y, -1.0, 1.0));
	float mv = mix(1.0, 0.5, comfort);

	// Naht-freies LOD: Winkelgroesse eines Pixels * Texel pro Radiant, leicht scharf (-0.25).
	float ang = max(length(dFdx(dir)), length(dFdy(dir)));
	float lod = max(log2(max(ang, 1e-6) * (TEX_W / TAU)) - 0.25, 0.0);

	// Ferne: Dunst + unscharfe Fasern. Bordeaux-Welle einmal pro Takt, Atem auf dem Schlag.
	vec2 puv = dir_uv(dir * euler(pano_rotation), pano_offset);
	vec3 far_col = pano_at(tex_a, tex_b, puv, lod);
	float fwave = 0.5 + 0.5 * cos(TAU * (puv.x * 2.0 - bar_phase));
	far_col *= 1.0 + (0.18 * beat_pulse + 0.25 * downbeat_pulse * mv + 0.05 * drop + 0.05 * kiai)
		+ 0.12 * fwave * (1.0 - comfort) * (0.3 + energy);

	if (AT_CUBEMAP_PASS) {
		COLOR = far_col * tint * brightness * 0.5;
	} else {
		// --- Netz (mittlere Ebene): gleichmaessiger Orbit (0.34 Grad/s), Drop zieht das Netz zusammen. ---
		float yaw_m = TIME * 0.006 * mv;
		float s_m = 1.0 - 0.36 * drop * mv;
		vec3 dm = yaw_dir(zoom_dir(dir, s_m), yaw_m);
		vec2 muv = dir_uv(dm, vec2(0.0));
		vec4 net = textureLod(net_a, muv, lod);
		vec4 pd = textureLod(pulse_a, muv, lod);
		float cov = net.a;
		vec3 net_rgb = dec(net.rgb);

		// Impulse: Phase aus cos/sin (mip-sicher), Kopf scharf, Schweif klingt ab.
		// Pro Schlag laeuft jeder Impuls eine halbe Periode (glatter Fluss ueber beat_step).
		// Feste Geschwindigkeit: ein drop-abhaengiger Faktor auf beat_step wuerde die Phase springen lassen.
		float ph = atan(pd.g - 0.5, pd.r - 0.5) * (1.0 / TAU);
		float hsh = pd.b;
		float dirn = hsh > 0.66 ? -1.0 : 1.0;
		float gate = smoothstep(0.30, 0.36, hsh);
		float speed = 0.5;
		float q = fract(ph - dirn * (beat_step * speed * mv) + fract(hsh * 37.0));
		float pulse = smoothstep(0.0, 0.02, q) * exp(-q * 11.0) * gate;
		float pamp = 0.55 + 0.45 * beat_pulse + 0.7 * downbeat_pulse * mv + 0.35 * energy + 0.2 * drop + 0.1 * kiai;
		vec3 pulse_col = PULSE_COL * pulse * pamp * smoothstep(0.35, 0.8, cov);
		// Synapsenknoten: glimmen, atmen mit dem Schlag, gluehen im Drop.
		float breath = 0.35 + 0.65 * exp(-beat_phase * 4.0);
		vec3 node_col = NODE_COL * pd.a * (0.30 + 0.9 * breath * (0.4 + beat_pulse) + 0.9 * downbeat_pulse * mv + 0.25 * drop);

		// --- Nahe Ebene: dicke Buendel + Ganglien, schneller als das Netz (Parallax, 0.8 Grad/s). ---
		float yaw_n = TIME * 0.014 * mv;
		float s_n = 1.0 - 0.52 * drop * mv;
		vec3 dn = yaw_dir(zoom_dir(dir, s_n), yaw_n);
		vec2 nuv = dir_uv(dn, vec2(0.0));
		vec4 nr = textureLod(near_a, nuv, lod);
		// Analytische Kante: Deckkraft um 0.5 mit der Pixelbreite (fwidth) scharf ziehen.
		float nw = max(fwidth(nr.a) * 0.75, 0.05);
		float ncov = smoothstep(0.5 - nw, 0.5 + nw, nr.a) * smoothstep(0.0, 0.18, nr.a);
		vec3 nrim = dec(nr.rgb) * (1.0 + 0.55 * downbeat_pulse * mv + 0.25 * beat_pulse + 0.12 * drop);

		// Sporen: zwei ueberblendete Zoom-Lagen, ein Zyklus = 4 Schlaege.
		mat3 srot = euler(stars_rotation);
		float sph = beat_step * 0.25 * mv + star_phase + TIME * star_speed;
		vec3 st = vec3(0.0);
		for (int layer = 0; layer < 2; layer++) {
			float a = fract(sph + float(layer) * 0.5);
			float w = 0.5 - 0.5 * cos(a * TAU);
			float s = exp2(a - 0.5);
			vec2 suv = dir_uv(zoom_dir(dir, s) * srot, stars_offset + vec2(TIME * 0.0006, 0.0));
			st += pano_at(stars_a, stars_b, suv, lod) * w;
		}
		float sl = dot(st, vec3(0.2126, 0.7152, 0.0722));
		st *= star_brightness * mix(1.0, star_hdr, smoothstep(0.30, 0.8, sl));
		st *= 1.0 + 0.4 * beat_pulse + 0.4 * energy + 0.1 * drop;

		// Schichtung: Ferne -> Netz (schwarz, Kantenlicht) -> Impulse -> Nah -> Sporen.
		vec3 col = far_col * (1.0 - cov) + net_rgb * cov;
		col += (pulse_col + node_col) * cov;
		col = col * (1.0 - ncov) + nrim * ncov;
		col += st * (1.0 - 0.9 * max(cov, ncov));
		col *= tint * brightness;

		// Lesbarkeit in Weltkoordinaten: vorn-mitte/unten zusaetzlich dunkler.
		float front = exp(-(lon / 0.62) * (lon / 0.62)) * smoothstep(0.22, -0.30, lat);
		col *= 1.0 - readability * 0.6 * front;

		// Dither gegen Banding in den dunklen Verlaeufen.
		float h = hash12(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
		col = max(col * (1.0 + h * 0.03) + h * 0.00025, vec3(0.0));
		COLOR = col;
	}
}
