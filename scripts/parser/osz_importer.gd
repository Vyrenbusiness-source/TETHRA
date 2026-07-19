class_name OszImporter
extends RefCounted

## Import einer .osz-Datei (Abschnitt 3.1). Eine .osz ist ein ZIP-Archiv:
## eine oder mehrere .osu-Dateien (eine pro Difficulty), die Audio-Datei
## (mp3/ogg) und optional Hintergrundbilder/Hitsounds (ignorierbar).
##
## Import-Flow: entpacken -> .osu-Dateien listen -> Difficulty waehlen ->
## zugehoerige Audio-Datei laden.

## import(path) liefert:
##   {
##     ok: bool, error: String,
##     difficulties: Array[Dictionary]  # { osu_filename, beatmap: Beatmap }
##   }
## Nur Mode-0-.osu-Dateien landen in difficulties; abgelehnte werden uebersprungen.
static func import(osz_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	var err := reader.open(osz_path)
	if err != OK:
		return { "ok": false, "error": "Konnte .osz nicht oeffnen (Fehler %d): %s" % [err, osz_path], "difficulties": [] }

	var files := reader.get_files()
	var difficulties: Array[Dictionary] = []
	var rejected: Array[String] = []

	for fname in files:
		if not fname.to_lower().ends_with(".osu"):
			continue
		var bytes := reader.read_file(fname)
		var text := bytes.get_string_from_utf8()
		var res := OsuParser.parse(text)
		if res.ok:
			difficulties.append({ "osu_filename": fname, "beatmap": res.beatmap })
		else:
			rejected.append("%s: %s" % [fname, res.error])

	reader.close()

	if difficulties.is_empty():
		var reason := "Keine gueltigen osu!standard-Difficulties im Archiv."
		if not rejected.is_empty():
			reason += " (" + ", ".join(rejected) + ")"
		return { "ok": false, "error": reason, "difficulties": [] }

	# Nach Difficulty-Name sortieren waere ideal nach Star Rating (kommt via
	# rosu-pp in M4); vorerst alphabetisch nach Version-Name.
	difficulties.sort_custom(func(a, b):
		return String(a.beatmap.version_name()) < String(b.beatmap.version_name()))

	return { "ok": true, "error": "", "difficulties": difficulties }


## Rohe Bytes einer Datei aus dem Archiv lesen (z.B. die Audio-Datei).
static func read_file_bytes(osz_path: String, inner_name: String) -> PackedByteArray:
	var reader := ZIPReader.new()
	if reader.open(osz_path) != OK:
		return PackedByteArray()
	var data := reader.read_file(inner_name)
	reader.close()
	return data


## Audio-Datei einer Difficulty als AudioStream laden.
static func load_audio_stream(osz_path: String, beatmap: Beatmap) -> AudioStream:
	return load_audio_stream_named(osz_path, beatmap.audio_filename())


## Audio direkt per Dateiname laden (fuer den Browser-Cache, ohne Beatmap).
static func load_audio_stream_named(osz_path: String, target: String) -> AudioStream:
	if target == "":
		return null
	var reader := ZIPReader.new()
	if reader.open(osz_path) != OK:
		return null
	var match_name := ""
	for fname in reader.get_files():
		if fname.get_file().to_lower() == target.to_lower():
			match_name = fname
			break
	if match_name == "":
		reader.close()
		return null
	var bytes := reader.read_file(match_name)
	reader.close()
	return _stream_from_bytes(bytes, match_name)


## Hintergrundbild einer Difficulty als Texture2D laden (aus [Events]).
static func load_background_texture(osz_path: String, beatmap: Beatmap) -> Texture2D:
	if beatmap.background_file == "":
		return null
	return load_image_texture(osz_path, beatmap.background_file)


## Beliebige Bilddatei aus dem Archiv als Texture2D laden (case-insensitiv,
## Suche nur ueber den Basisnamen, da .osu-Pfade Unterordner enthalten koennen).
static func load_image_texture(osz_path: String, inner_name: String) -> Texture2D:
	var reader := ZIPReader.new()
	if reader.open(osz_path) != OK:
		return null
	var target := inner_name.get_file().to_lower()
	var match_name := ""
	for fname in reader.get_files():
		if fname.get_file().to_lower() == target:
			match_name = fname
			break
	if match_name == "":
		reader.close()
		return null
	var bytes := reader.read_file(match_name)
	reader.close()

	var img := Image.new()
	var lower := match_name.to_lower()
	var err := ERR_FILE_UNRECOGNIZED
	if lower.ends_with(".jpg") or lower.ends_with(".jpeg"):
		err = img.load_jpg_from_buffer(bytes)
	elif lower.ends_with(".png"):
		err = img.load_png_from_buffer(bytes)
	elif lower.ends_with(".bmp"):
		err = img.load_bmp_from_buffer(bytes)
	elif lower.ends_with(".webp"):
		err = img.load_webp_from_buffer(bytes)
	if err != OK:
		return null
	# Mipmaps erlauben weichen Blur (textureLod) z.B. im Main-Menue.
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _stream_from_bytes(bytes: PackedByteArray, filename: String) -> AudioStream:
	var lower := filename.to_lower()
	if lower.ends_with(".mp3"):
		var mp3 := AudioStreamMP3.new()
		mp3.data = bytes
		return mp3
	elif lower.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_buffer(bytes)
	elif lower.ends_with(".wav"):
		# WAV-Rohladen ist aufwendiger; in v1 nicht Pflicht.
		return null
	return null
