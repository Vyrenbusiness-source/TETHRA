class_name WorldBackdrop
extends RefCounted

## Gemeinsamer Welten-Aufbau (Mania-3D und Orbit-Hintergrund): Coverfarbe,
## Themen-Dateien, Themen-Himmel (Sky-Shader + Texturen per Konvention) und
## Galaxie-Panorama. Bewusst ohne Autoload-Zugriffe (Settings/GameSession),
## damit --script-Tests die Klasse statisch laden koennen.

const GALAXY_SHADER := "res://shaders/sky_panorama.gdshader"
## Galaxie-Paletten (Reihenfolge = Mania SKY_PALS) und ihr Farbton.
const GALAXY_PALS := ["violet", "azure", "ember", "emerald"]
const GALAXY_HUES := [0.78, 0.58, 0.05, 0.40]


## Coverfarbe aus dem Map-Bild: [Linie, Kiai] oder [] (kein/zu blasses Bild).
static func cover_colors(tex: Texture2D) -> Array[Color]:
	var out: Array[Color] = []
	if tex == null:
		return out
	var img := tex.get_image()
	if img == null:
		return out
	img.resize(32, 24, Image.INTERPOLATE_BILINEAR)
	var acc := Vector2.ZERO
	var total_w := 0.0
	for y in 24:
		for x in 32:
			var c := img.get_pixel(x, y)
			var w := c.s * c.v
			acc += Vector2(cos(c.h * TAU), sin(c.h * TAU)) * w
			total_w += w
	if total_w < 4.0 or acc.length() < 1.0:
		return out
	var hue := fposmod(atan2(acc.y, acc.x) / TAU, 1.0)
	# Satt in der Farbe, aber gedrosselt in der Helligkeit — Entsaettigung
	# wuerde alles nur weisser (= greller) machen.
	out.append(Color.from_hsv(hue, 0.72, 0.84))
	out.append(Color.from_hsv(fposmod(hue + 0.5, 1.0), 0.78, 0.86))
	return out


## Liegt irgendeine Themen-Welt des Welten-Pakets vor (Galaxie zaehlt nicht)?
static func has_world_pack() -> bool:
	for t in WorldTheme.VARIETY:
		if WorldTheme.is_available(t):
			return true
	return false


## Bilddateien des Themas: Stamm -> res-Pfad ({} = Shader oder Panorama fehlt).
static func theme_files(t: String) -> Dictionary:
	var sp := WorldTheme.shader_path(t)
	if sp == "" or not ResourceLoader.exists(sp):
		return {}
	var dir := WorldTheme.asset_dir(t)
	var out := {}
	if not DirAccess.dir_exists_absolute(dir):
		return {}
	for fname in ResourceLoader.list_directory(dir):
		var ext := fname.get_extension().to_lower()
		if ext in ["webp", "png", "jpg", "exr", "hdr"]:
			var path := dir.path_join(fname)
			if ResourceLoader.exists(path):
				out[fname.get_basename()] = path
	return out


## Themen-Himmel: Shader-Uniforms per Konvention mit Texturen fuellen.
## tex_a/tex_b = Panorama (Stamm ohne Ebenen-Suffix), <key>_a/<key>_b =
## Ebene *_<key> (stars, embers, aurora, ...). Slot b = Slot a (palette_mix
## wird bei Themen nicht genutzt). null = Thema nicht baubar.
static func theme_sky_material(theme: String) -> ShaderMaterial:
	var files := theme_files(theme)
	if files.is_empty():
		return null
	var sh: Shader = load(WorldTheme.shader_path(theme))
	if sh == null:
		return null
	var samplers: Array[String] = []
	for u in sh.get_shader_uniform_list():
		if int(u.type) == TYPE_OBJECT:
			samplers.append(str(u.name))
	var keys := {}
	for sn in samplers:
		var base := sn
		if base.ends_with("_a") or base.ends_with("_b"):
			base = base.substr(0, base.length() - 2)
		keys[sn] = base
	# Ebenen-Dateien (Suffix passt zu einem Sampler) vs. Panorama.
	var layer_of := {}
	var pano := ""
	var stems: Array = files.keys()
	stems.sort()
	for stem in stems:
		var hit := ""
		for sn in keys:
			var b: String = keys[sn]
			if b != "tex" and (stem == b or stem.ends_with("_" + b)):
				hit = b
		if hit != "":
			layer_of[hit] = files[stem]
		elif pano == "" or stem.length() < pano.get_file().get_basename().length():
			pano = files[stem]
	if pano == "":
		return null
	var mat := ShaderMaterial.new()
	mat.shader = sh
	for sn in keys:
		var b: String = keys[sn]
		var path: String = pano if b == "tex" else str(layer_of.get(b, ""))
		if path != "":
			mat.set_shader_parameter(sn, WorldTheme.get_cached(path))
	mat.set_shader_parameter("readability", 0.7)
	mat.set_shader_parameter("star_speed", 0.0)
	mat.set_shader_parameter("palette_mix", 0.0)
	print("[world] sky %s: pano=%s layers=%s" % [theme, pano.get_file(), str(layer_of.keys())])
	return mat


## Naechste Galaxie-Palette zum Farbton (zirkulaer).
static func galaxy_pal_for_hue(h: float) -> int:
	var best := 0
	var bd := 9.0
	for i in GALAXY_HUES.size():
		var d := absf(fposmod(h - float(GALAXY_HUES[i]) + 0.5, 1.0) - 0.5)
		if d < bd:
			bd = d
			best = i
	return best


## Galaxie-Panorama (eine Palette, kein Kapitelwechsel). null = Assets fehlen.
static func galaxy_material(hue: float) -> ShaderMaterial:
	if not ResourceLoader.exists(GALAXY_SHADER):
		return null
	var n: String = GALAXY_PALS[galaxy_pal_for_hue(hue)]
	var np := "res://assets_game/space/sky_%s.webp" % n
	var tp := "res://assets_game/space/sky_%s_stars.webp" % n
	if not ResourceLoader.exists(np) or not ResourceLoader.exists(tp):
		return null
	var nt: Texture2D = load(np)
	var st: Texture2D = load(tp)
	if nt == null or st == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = load(GALAXY_SHADER)
	mat.set_shader_parameter(&"tex_a", nt)
	mat.set_shader_parameter(&"stars_a", st)
	mat.set_shader_parameter(&"tex_b", nt)
	mat.set_shader_parameter(&"stars_b", st)
	mat.set_shader_parameter("readability", 0.7)
	mat.set_shader_parameter("star_speed", 0.0)
	mat.set_shader_parameter("palette_mix", 0.0)
	return mat


## Himmel-Material als Hintergrund in env (ohne Umgebungs-/Reflexionslicht).
static func attach_sky(env: Environment, mat: ShaderMaterial) -> void:
	var sky := Sky.new()
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0, 0, 0)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
