shader_type canvas_item;

// Fullscreen-Post-FX: chromatische Aberration (Bass-Kicks), Overdrive-
// Schockwelle (radiale Bildverzerrung), Vignette und Miss-Glitch.
// Die Bildmitte (Noten-Korridor) bleibt geschuetzt — verzerrt wird aussen.

uniform sampler2D screen_tex: hint_screen_texture, filter_linear_mipmap;
uniform float aberration = 0.0;   // 0..1
uniform float shock = -1.0;       // laufender Wellen-Radius, <0 = aus
uniform float shock_str = 0.0;
uniform float vignette = 0.0;
uniform float glitch = 0.0;
// WARP-TUNNEL beim Galaxiensprung: Sog zur Mitte + rotierende Lichtstreifen.
uniform float warp_tunnel = 0.0;

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float d = length(c);
	// Schutzmaske: innen 0, aussen 1.
	float edge = smoothstep(0.20, 0.62, d);
	// Overdrive-Schockwelle: ein Verzerrungs-Ring laeuft nach aussen.
	if (shock >= 0.0) {
		float ring = exp(-pow((d - shock) * 9.0, 2.0));
		uv -= (c / max(d, 1e-4)) * ring * shock_str * 0.035;
	}
	// Glitch: horizontale Zeilenrisse (Schiff nimmt Schaden).
	if (glitch > 0.001) {
		float row = floor(SCREEN_UV.y * 36.0);
		float tear = step(0.62, hash11(row * 3.7 + floor(TIME * 14.0)));
		uv.x += (hash11(row + floor(TIME * 14.0) * 13.0) - 0.5) * 0.030 * glitch * tear;
	}
	// Warp-Sog: das Bild zieht leicht Richtung Fluchtpunkt.
	if (warp_tunnel > 0.001) {
		float wmask = smoothstep(0.12, 0.7, d);
		uv = vec2(0.5) + (uv - vec2(0.5)) * (1.0 - warp_tunnel * wmask * 0.22);
	}
	// Chromatische Aberration am Rand (RGB-Kanaele trennen sich).
	vec2 off = c * (aberration * 0.012 + glitch * 0.008) * edge;
	float r = texture(screen_tex, uv + off).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - off).b;
	vec3 col = vec3(r, g, b);
	// Warp-Streifen: rotierende Radiallichter um den Fluchtpunkt.
	if (warp_tunnel > 0.001) {
		float ang2 = atan(c.y, c.x);
		float st = pow(0.5 + 0.5 * sin(ang2 * 22.0 + TIME * 26.0), 5.0)
				+ 0.6 * pow(0.5 + 0.5 * sin(ang2 * 11.0 - TIME * 19.0), 7.0);
		col += vec3(0.6, 0.78, 1.0) * st * smoothstep(0.15, 0.75, d) * warp_tunnel * 0.55;
	}
	// Weiche Vignette.
	col *= 1.0 - vignette * smoothstep(0.45, 0.95, d);
	COLOR = vec4(col, 1.0);
}
