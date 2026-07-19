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

float band(float x, float center, float width) {
	float d = (x - center) / width;
	return exp(-d * d * 4.0);
}

void fragment() {
	float y = UV.y;
	// Beat-Welle: schmal, dezent.
	float w1 = band(y, beat_phase, 0.055) * 0.28;
	// Takt-Welle: breiter, aber zurueckhaltend.
	float w2 = band(y, bar_phase, 0.10) * 0.5;
	// Naehe zur Linie verstaerkt (Aufmerksamkeit dort).
	float lift = 0.35 + 0.65 * y;
	float glow = (w1 + w2) * wave_amount * lift * energy * (1.0 + punch * 0.8);
	// Spur-Separatoren: drei feine Laengslinien — Struktur ohne Bewegung.
	float sep = exp(-pow((UV.x - 0.25) * 90.0, 2.0))
			+ exp(-pow((UV.x - 0.50) * 90.0, 2.0))
			+ exp(-pow((UV.x - 0.75) * 90.0, 2.0));
	glow += sep * 0.035 * energy;
	// Naehe-Gradient: die Road wird zur Abfanglinie hin sanft heller.
	glow += pow(y, 3.0) * 0.10 * energy;
	// Seitlicher Fade (nicht ueber die Rails hinausbrennen).
	float sx = 1.0 - smoothstep(0.72, 1.0, abs(UV.x * 2.0 - 1.0));
	// Nass-Reflexion: flacher Blick zum Horizont spiegelt den Himmel.
	float refl = pow(1.0 - y, 2.2) * refl_amount;
	ALBEDO = base_color * glow * sx + sky_color * refl * sx;
	ALPHA = clamp(glow * sx + refl * sx * 0.8, 0.0, 1.0) * 0.6;
}
