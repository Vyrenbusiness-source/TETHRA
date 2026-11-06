shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Beat-Wellen auf dem Highway: weiche Leuchtbaender rollen zur Abfanglinie
// und treffen sie EXAKT auf dem Schlag. UV.y: 0 = fern, 1 = Linie.
//  beat_phase 0..1  -> kleine Welle pro Beat
//  bar_phase  0..1  -> breitere, hellere Welle pro Takt
//  punch            -> Bass-Kick verstaerkt kurz alles

uniform vec3 base_color: source_color = vec3(0.15, 0.75, 1.0);
uniform float beat_phase = 0.0;
uniform float bar_phase = 0.0;
uniform float punch = 0.0;
uniform float energy = 1.0;
uniform float wave_amount = 1.0;
// NASSE BAHN: der Himmel spiegelt sich Richtung Horizont (Fresnel-artig).
uniform vec3 sky_color: source_color = vec3(0.2, 0.4, 0.8);
uniform float refl_amount = 0.0;

// Groove-Hooks (vom Aufrufer gesetzt, Default 0 = altes Aussehen):
//  beat_flash 0..1 Licht-Schlag auf dem Beat (schnell abklingend)
//  downbeat   0..1 Taktanfang · music_energy 0..1 Musik-Intensitaet
uniform float beat_flash : hint_range(0.0, 1.0) = 0.0;
uniform float downbeat : hint_range(0.0, 1.0) = 0.0;
uniform float music_energy : hint_range(0.0, 1.0) = 0.0;

float band(float x, float center, float width) {
	// Glockenform mit weichem Auslauf (kein harter Rand).
	float d = (x - center) / width;
	return exp(-d * d * 3.0);
}

// Antialiaste feine Linie: Breite folgt der Pixelableitung.
float aa_line(float x, float center, float w) {
	float fw = max(fwidth(x), 1e-5);
	float d = abs(x - center);
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + fw * 1.5, d);
}

void fragment() {
	float y = UV.y;
	// Beat-Welle: schmal, weich.
	float w1 = band(y, beat_phase, 0.07) * 0.26;
	// Takt-Welle: breiter, zurueckhaltend.
	float w2 = band(y, bar_phase, 0.12) * 0.46;
	// Naehe zur Linie verstaerkt (Aufmerksamkeit dort).
	float lift = 0.35 + 0.65 * y;
	float glow = (w1 + w2) * wave_amount * lift * energy * (1.0 + punch * 0.7);
	// Spur-Separatoren: drei feine, antialiaste Laengslinien.
	float sep = aa_line(UV.x, 0.25, 0.012) + aa_line(UV.x, 0.50, 0.012) + aa_line(UV.x, 0.75, 0.012);
	glow += sep * 0.03 * energy * (1.0 + beat_flash * 2.0 + downbeat * 0.8);
	// Beat-Querschlag: sitzt auf der Abfanglinie und laeuft in ~0.15 s
	// nach hinten (beat_flash 1 -> 0 = Linie -> 0.28 UV zurueck).
	float bar_y = 1.0 - (1.0 - beat_flash) * 0.28;
	float bar = band(y, bar_y, 0.035) * beat_flash * (0.16 + 0.10 * downbeat);
	glow += bar * (0.5 + 0.5 * y) * (1.0 + music_energy * 0.4);
	// Sehr dezentes Energie-Gitter (Querlinien, wandern mit der Beat-Phase).
	float gy = fract(y * 14.0);
	float gfw = max(fwidth(y * 14.0), 1e-5);
	float grid = 1.0 - smoothstep(0.02, 0.02 + gfw * 1.5, min(gy, 1.0 - gy));
	glow += grid * 0.012 * energy * lift;
	// Naehe-Gradient: die Road wird zur Abfanglinie hin sanft heller.
	glow += pow(y, 3.0) * 0.09 * energy * (1.0 + music_energy * 0.25);
	// Tiefen-Fade zum Horizont.
	glow *= smoothstep(0.0, 0.18, y);
	// Seitlicher Fade (nicht ueber die Rails hinausbrennen).
	float sx = 1.0 - smoothstep(0.70, 1.0, abs(UV.x * 2.0 - 1.0));
	// Nass-Reflexion: flacher Blick zum Horizont spiegelt den Himmel.
	float refl = pow(1.0 - y, 2.2) * refl_amount;
	ALBEDO = base_color * glow * sx + sky_color * refl * sx;
	ALPHA = clamp(glow * sx + refl * sx * 0.8, 0.0, 1.0) * 0.6;
}
