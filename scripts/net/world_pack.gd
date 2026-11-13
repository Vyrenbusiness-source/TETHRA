extends Node

## Autoload "WorldPack": haengt beim Start das Welten-Paket ein (OMEN_worlds.pck
## neben der Exe, enthaelt assets_game/themes/; bestehende Installationen haben es
## als TETHRA_worlds.pck, das zaehlt genauso). Fehlt es, bleibt alles wie es ist:
## WorldTheme.is_available() findet das Verzeichnis nicht und faellt auf galaxy zurueck.
## Muss VOR allen anderen Autoloads stehen, die Welt-Assets laden koennten.

## Neuer Name zuerst. "TETHRA_worlds.pck" = historische Kennung (Installationen bis v1.35.0).
const FILES := ["OMEN_worlds.pck", "TETHRA_worlds.pck"]
const MIN_SIZE := 1024

static var mounted := false


func _init() -> void:
	mounted = mount()


## Dateiname des Welten-Pakets in dir: das vorhandene (neuer Name hat Vorrang),
## sonst der neue Name (dorthin laedt der Updater ein fehlendes Paket).
static func local_name(dir: String) -> String:
	for n in FILES:
		if FileAccess.file_exists(dir.path_join(n)):
			return n
	return FILES[0]


## Pfad des Welten-Pakets neben der Exe.
static func pack_path() -> String:
	var dir := OS.get_executable_path().get_base_dir()
	return dir.path_join(local_name(dir))


## Ist das Paket als Datei da (und gross genug, um eins zu sein)?
static func exists() -> bool:
	return is_valid_file(pack_path())


static func is_valid_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var ok := f.get_length() >= MIN_SIZE and f.get_buffer(4).get_string_from_ascii() == "GDPC"
	f.close()
	return ok


## Paket einhaengen. false = fehlt/kaputt (Spiel laeuft dann ohne Welten-Assets).
static func mount() -> bool:
	if mounted:
		return true
	var p := pack_path()
	if not is_valid_file(p):
		return false
	# replace_files = false: das Welten-Paket darf NIE Dateien des Spiels
	# ueberschreiben (alte Pakete enthielten Autoload-Skripte von v1.9.0 und
	# haben damit Updater/Settings/Lobby zurueckgedreht -> Update-Loop).
	return ProjectSettings.load_resource_pack(p, false)
