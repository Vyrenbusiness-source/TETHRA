extends Node

## Autoload "GameSession": traegt die Auswahl aus dem Song-Browser in die
## Gameplay-/Debug-Szene. Haelt ausserdem die "zuletzt gespielte" Map fuer den
## Startzustand des Browsers (Hintergrund).

const LAST_PLAYED_PATH := "user://last_played.cfg"

## Aktuelle Auswahl fuer den naechsten Szenenwechsel.
var osz_path: String = ""
var difficulty_index: int = 0
## Stabiler Difficulty-Bezeichner (Version-Name). Robuster als der Index, da
## Song-Browser und Importer unterschiedlich sortieren.
var difficulty_version: String = ""
## Innerer .osu-Dateiname im Archiv (fuer rosu-pp/StarService).
var osu_filename: String = ""
## Star Rating der gewaehlten Difficulty (aus rosu-pp, -1 = unbekannt).
var stars: float = -1.0

## Aktive Mods (kosmetisch/teilweise funktional). z.B. {"NF": true}.
var mods: Dictionary = {}
## Tutorial-Modus: Uebungs-Map mit Erklaer-Stopps, ohne Score-Wertung.
var tutorial := false

## Replay-Wiedergabe: true = aufgezeichnete Inputs abspielen statt Tastatur.
var is_replay := false
var replay_events: Array = []


func set_selection(p_osz_path: String, p_difficulty_index: int, p_difficulty_version: String = "", p_osu_filename: String = "", p_stars: float = -1.0) -> void:
	osz_path = p_osz_path
	difficulty_index = p_difficulty_index
	difficulty_version = p_difficulty_version
	osu_filename = p_osu_filename
	stars = p_stars


func has_selection() -> bool:
	return osz_path != ""


## Zuletzt gespielte Map persistent speichern (Browser-Startzustand).
## bg_file erlaubt dem Menue, das Blur-Cover ohne Vollparse zu laden.
func save_last_played(p_osz_path: String, p_difficulty_index: int, p_bg_file: String = "") -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("last_played", "osz_path", p_osz_path)
	cfg.set_value("last_played", "difficulty_index", p_difficulty_index)
	cfg.set_value("last_played", "bg_file", p_bg_file)
	cfg.save(LAST_PLAYED_PATH)


## Liefert {osz_path, difficulty_index} der zuletzt gespielten Map oder {} .
func load_last_played() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(LAST_PLAYED_PATH) != OK:
		return {}
	var p := str(cfg.get_value("last_played", "osz_path", ""))
	if p == "" or not FileAccess.file_exists(p):
		return {}
	return {
		"osz_path": p,
		"difficulty_index": int(cfg.get_value("last_played", "difficulty_index", 0)),
		"bg_file": str(cfg.get_value("last_played", "bg_file", "")),
	}
