shader_type canvas_item;

// Weicher, abgedunkelter Hintergrund (Mipmap-Blur + leichte Streuung).
// Fuer das Main-Menue: Cover der zuletzt gespielten Map.

uniform float lod = 7.0;
uniform float dim = 0.30;

void fragment() {
	// UV leicht einklemmen: verhindert Mip-Bleeding an den Bildraendern.
	vec2 uv = mix(vec2(0.03), vec2(0.97), UV);
	vec2 px = vec2(0.035, 0.035);
	vec4 c = textureLod(TEXTURE, uv, lod) * 0.24;
	c += textureLod(TEXTURE, uv + vec2(px.x, 0.0), lod) * 0.12;
	c += textureLod(TEXTURE, uv - vec2(px.x, 0.0), lod) * 0.12;
	c += textureLod(TEXTURE, uv + vec2(0.0, px.y), lod) * 0.12;
	c += textureLod(TEXTURE, uv - vec2(0.0, px.y), lod) * 0.12;
	c += textureLod(TEXTURE, uv + px * 0.7, lod) * 0.07;
	c += textureLod(TEXTURE, uv - px * 0.7, lod) * 0.07;
	c += textureLod(TEXTURE, uv + vec2(px.x, -px.y) * 0.7, lod) * 0.07;
	c += textureLod(TEXTURE, uv + vec2(-px.x, px.y) * 0.7, lod) * 0.07;
	// Vignette zum Rand.
	float d = length(uv - 0.5);
	float vig = 1.0 - smoothstep(0.35, 0.85, d) * 0.55;
	COLOR = vec4(c.rgb * dim * vig, 1.0);
}
