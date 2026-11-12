shader_type canvas_item;

// Orbit: Map-Bild als ruhiger Hintergrund wie osu! - echter weicher Gauss-Blur
// (6x6 Taps auf passender Mip-Stufe, keine Bloecke), stark abgedunkelt,
// leichte Vignette, feines Dithering gegen Stufen im dunklen Verlauf.
// Erwartet eine kleine Textur mit Mipmaps (OrbitGame.blurred) und
// texture_filter LINEAR_WITH_MIPMAPS am TextureRect.

// Deckkraft des Bilds ueber Schwarz (Settings.bg_dim x 0,6).
uniform float dim : hint_range(0.0, 1.0) = 0.12;
// Gauss-Sigma als Anteil der Texturhoehe.
uniform float sigma_k : hint_range(0.0, 0.1) = 0.03;
// Abdunklung zum Bildrand (0 = keine).
uniform float vignette : hint_range(0.0, 1.0) = 0.4;
// Grundfarbe unter dem Bild (OrbitBackdrop.BLACK).
uniform vec3 floor_col = vec3(0.008, 0.01, 0.018);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 ts = vec2(textureSize(TEXTURE, 0));
	float sigma = max(sigma_k * ts.y, 0.5);
	// Abstand der Taps = 0,75 Sigma; Mip-Texel gleich gross -> lueckenlos weich.
	float step_px = sigma * 0.75;
	float lod = max(log2(step_px), 0.0);
	vec2 texel = 1.0 / ts;
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int y = 0; y < 6; y++) {
		for (int x = 0; x < 6; x++) {
			vec2 o = (vec2(float(x), float(y)) - 2.5) * step_px;
			float w = exp(-dot(o, o) / (2.0 * sigma * sigma));
			vec2 uv = clamp(UV + o * texel, texel * 0.5, 1.0 - texel * 0.5);
			acc += textureLod(TEXTURE, uv, lod).rgb * w;
			wsum += w;
		}
	}
	vec3 c = acc / max(wsum, 1e-4);
	// Vignette: rund (seitenrichtig), innen unveraendert.
	vec2 sp = SCREEN_UV - 0.5;
	sp.x *= SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 1e-6);
	float vig = 1.0 - vignette * smoothstep(0.3, 0.95, length(sp));
	vec3 col = mix(floor_col, c, dim) * vig;
	col += (hash(FRAGCOORD.xy) - 0.5) / 255.0;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
