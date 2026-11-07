extends Node

## Autoload "WorldPack": haengt beim Start das Welten-Paket ein (TETHRA_worlds.pck
## neben der Exe, enthaelt assets_game/themes/). Fehlt es, bleibt alles wie es ist:
## WorldTheme.is_available() findet das Verzeichnis nicht und faellt auf galaxy zurueck.
## Muss VOR allen anderen Autoloads stehen, die Welt-Assets laden koennten.

const FILE := "TETHRA_worlds.pck"
const MIN_SIZE := 1024

static var mounted := false


func _init() -> void:
	mounted = mount()


## Pfad des Welten-Pakets neben der Exe.
static func pack_path() -> String:
	return OS.get_executable_path().get_base_dir().path_join(FILE)


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
