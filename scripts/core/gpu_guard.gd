extends Node

## Autoload "GpuGuard": Absturz-Waechter + sicherer Grafikmodus.
##
## Beim Start liegt eine Marker-Datei (user://gpu_running.marker), beim
## sauberen Beenden (Fenster schliessen, get_tree().quit(), Updater-Neustart)
## wird sie geloescht. Findet der naechste Start den Marker, endete die letzte
## Sitzung hart (GPU-Haenger, Treiber-Timeout, Kill). Dann gilt der sichere
## Modus: OpenGL-Renderer ueber override.cfg NEBEN der exportierten exe,
## niedrigere Grafikqualitaet, FPS-Cap 240 mit VSync. Der sichere Modus bleibt,
## bis der Nutzer ihn in den Einstellungen abschaltet (auch nach dem zweiten
## Absturz in Folge). Gespeicherte Nutzereinstellungen werden nie veraendert.
## override.cfg wird nie im Projektordner oder Editor geschrieben.

const MARKER_PATH := "user://gpu_running.marker"
const STATE_PATH := "user://gpu_guard.cfg"
const OVERRIDE_NAME := "override.cfg"

signal safe_mode_changed

## Sicherer Modus aktiv (persistiert in STATE_PATH).
var safe_mode: bool = false
## Absturz-Hinweis fuer das Hauptmenue steht noch aus.
var notice_pending: bool = false
## Abstuerze in Folge (zaehlt hoch bis zum naechsten sauberen Ende).
var crash_streak: int = 0
## Diese Sitzung hat nach einem Absturz gestartet.
var started_after_crash: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(true)
	_load_state()
	if evaluate_start(MARKER_PATH):
		started_after_crash = true
		crash_streak += 1
		safe_mode = true
		notice_pending = true
		_save_state()
		sync_override()
	elif crash_streak != 0:
		# Letzte Sitzung sauber beendet: Serie zu Ende (sicherer Modus bleibt).
		crash_streak = 0
		_save_state()
	if should_write_marker():
		write_marker(MARKER_PATH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		clear_marker(MARKER_PATH)


func _exit_tree() -> void:
	clear_marker(MARKER_PATH)


## Marker nur im echten Spielbetrieb: nicht im Editor, nicht headless, nicht in
## Test-/Screenshot-Laeufen (die werden per Timeout beendet = kein Absturz).
func should_write_marker() -> bool:
	if OS.has_feature("editor") or DisplayServer.get_name() == "headless":
		return false
	return not _is_test_run()


## Wie Settings.is_test_run (hier gespiegelt: Settings referenziert GpuGuard,
## ein Preload waere ein Zyklus).
static func _is_test_run() -> bool:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot") or a == "--autoplay" or a == "--write-movie" or a == "--clip" or a == "--perf":
			return true
	return false


## Hinweis genau einmal abholen (Hauptmenue).
func take_notice() -> bool:
	var n := notice_pending
	if n:
		notice_pending = false
		_save_state()
	return n


## Schalter in den Einstellungen. true = sicherer Modus, false = normal.
func set_safe_mode(on: bool) -> void:
	if safe_mode == on:
		return
	safe_mode = on
	if not on:
		crash_streak = 0
		notice_pending = false
	_save_state()
	sync_override()
	safe_mode_changed.emit()


## override.cfg an den Modus angleichen. Nur im exportierten Spiel.
func sync_override() -> void:
	if not can_write_override():
		return
	var p := override_path()
	if safe_mode:
		write_override(p)
	else:
		remove_override(p)


## Nur exportierte Builds (Feature "template"), nie der Editor.
static func can_write_override() -> bool:
	return OS.has_feature("template") and not OS.has_feature("editor")


static func override_path() -> String:
	return OS.get_executable_path().get_base_dir().path_join(OVERRIDE_NAME)


## Inhalt der override.cfg fuer den sicheren Modus (Godot 4.7: Keys geprueft).
static func override_text() -> String:
	return "\n".join([
		"; OMEN: Sicherer Grafikmodus (automatisch erzeugt, in den Einstellungen abschaltbar).",
		"[rendering]",
		"",
		"renderer/rendering_method=\"gl_compatibility\"",
		"renderer/rendering_method.mobile=\"gl_compatibility\"",
		"gl_compatibility/driver.windows=\"opengl3\"",
		"",
	])


static func write_override(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(override_text())
	f.close()
	return true


static func remove_override(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## true = Marker einer frueheren Sitzung gefunden (harter Absturz).
static func evaluate_start(marker: String) -> bool:
	return FileAccess.file_exists(marker)


static func write_marker(marker: String) -> void:
	var f := FileAccess.open(marker, FileAccess.WRITE)
	if f != null:
		f.store_string(str(Time.get_unix_time_from_system()))
		f.close()


static func clear_marker(marker: String) -> void:
	if FileAccess.file_exists(marker):
		DirAccess.remove_absolute(marker)


## Effektive Grafikqualitaet: im sicheren Modus hoechstens 2x MSAA, kein SSAA.
static func effective_quality(q: int, safe: bool) -> int:
	return mini(q, 1) if safe else q


func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(STATE_PATH) != OK:
		return
	safe_mode = bool(cfg.get_value("guard", "safe_mode", false))
	crash_streak = int(cfg.get_value("guard", "crash_streak", 0))
	notice_pending = bool(cfg.get_value("guard", "notice", false))


func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("guard", "safe_mode", safe_mode)
	cfg.set_value("guard", "crash_streak", crash_streak)
	cfg.set_value("guard", "notice", notice_pending)
	cfg.save(STATE_PATH)
