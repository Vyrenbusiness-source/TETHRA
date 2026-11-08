extends SceneTree

## Headless-Tests fuer den Login-Dialog beim Spielstart (Task login-start):
## Wann er erscheint, Spaeter / Nicht mehr fragen, Fehlertexte, Erfolg -> Upload.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_login_dialog_tests.gd

const TMP_CFG := "user://test_tmp/login_dialog_test.cfg"
const TMP_Q := "user://test_tmp/login_dialog_queue.json"

var _failed := 0
var _done := false
var _script: Array = []


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _fake(_method: String, _url: String, _headers: PackedStringArray, _body: String, done: Callable) -> void:
	var r: Array = _script.pop_front() if not _script.is_empty() else [200, "{}"]
	done.call(int(r[0]), str(r[1]))


func _api(logged: bool) -> OnlineApi:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://test_tmp"))
	DirAccess.remove_absolute(TMP_CFG)
	DirAccess.remove_absolute(TMP_Q)
	var a := OnlineApi.new()
	a.cfg_path = TMP_CFG
	a.queue_path = TMP_Q
	a.api_key = "k"
	a.token = "tok" if logged else ""
	a.transport = _fake
	return a


func _dialog(a: OnlineApi) -> LoginDialog:
	var d := LoginDialog.new()
	d.api = a
	d.osz_provider = func() -> Dictionary: return {}
	root.add_child(d)
	return d


func _run() -> void:
	TranslationServer.set_locale("de")
	print("=== Login-Dialog-Tests ===")
	var none := PackedStringArray()

	# --- Wann erscheint der Dialog
	LoginDialog.shown_this_run = false
	var a := _api(false)
	_check(LoginDialog.should_show(a, none, false), "nicht angemeldet -> Dialog")
	_check(not LoginDialog.should_show(a, none, true), "Headless -> kein Dialog")
	_check(not LoginDialog.should_show(a, PackedStringArray(["--shot-menu"]), false), "Shot-Lauf -> kein Dialog")
	_check(not LoginDialog.should_show(a, PackedStringArray(["--autoplay"]), false), "Test-Lauf -> kein Dialog")
	_check(not LoginDialog.should_show(null, none, false), "ohne OnlineApi -> kein Dialog")
	var logged := _api(true)
	_check(not LoginDialog.should_show(logged, none, false), "angemeldet -> kein Dialog")
	logged.free()
	a.api_key = ""
	_check(not LoginDialog.should_show(a, none, false), "Online aus -> kein Dialog")
	a.api_key = "k"

	# --- Spaeter: in diesem Lauf nicht mehr, naechster Start fragt wieder
	var d := _dialog(a)
	_check(LoginDialog.shown_this_run, "gezeigt -> fuer diesen Lauf gemerkt")
	_check(not LoginDialog.should_show(a, none, false), "zurueck ins Menue fragt nicht erneut")
	var res := []
	d.finished.connect(func(ok): res.append(ok))
	d.later()
	_check(res == [false], "Spaeter -> finished(false)")
	_check(not a.login_prompt_disabled(), "Spaeter ohne Haken speichert nichts")
	LoginDialog.shown_this_run = false   # naechster Spielstart
	_check(LoginDialog.should_show(a, none, false), "naechster Start fragt wieder")
	d.queue_free()

	# --- Nicht mehr fragen
	d = _dialog(a)
	d._never.button_pressed = true
	d.later()
	_check(a.login_prompt_disabled(), "Nicht mehr fragen -> online.cfg [prompt] never")
	LoginDialog.shown_this_run = false
	_check(not LoginDialog.should_show(a, none, false), "abgeschaltet -> auch beim naechsten Start kein Dialog")
	# Login/Logout ueberschreibt die Einstellung nicht.
	a.logout()
	_check(a.login_prompt_disabled(), "Abmelden behaelt [prompt]")
	a.set_login_prompt_disabled(false)
	d.queue_free()

	# --- Fehlertexte
	_check(LoginDialog.error_text("Invalid credentials") == "Benutzername oder Passwort falsch.", "falsches Passwort")
	_check(LoginDialog.error_text("HTTP 401").begins_with("Benutzername oder Passwort"), "401 ohne Text")
	_check(LoginDialog.error_text("email_not_verified").begins_with("E-Mail noch nicht bestätigt"), "E-Mail nicht bestaetigt")
	_check(LoginDialog.error_text("Email not confirmed").contains("Mail von TETHRA"), "Hinweis auf Mail")
	_check(LoginDialog.error_text("offline").begins_with("Server nicht erreichbar"), "offline")
	_check(LoginDialog.error_text("HTTP 502").begins_with("Server nicht erreichbar"), "5xx -> Server")
	_check(LoginDialog.error_text("HTTP 429").begins_with("Zu viele Versuche"), "429")
	_check(LoginDialog.error_text("seltsam").contains("seltsam"), "Unbekanntes bleibt lesbar")

	# --- Anmelden: Enter-Pfad mit falschem Passwort, dann Erfolg
	LoginDialog.shown_this_run = false
	d = _dialog(a)
	res.clear()
	d.finished.connect(func(ok): res.append(ok))
	d.submit()
	_check(d._msg.visible and d._msg.text == "Bitte Benutzername und Passwort eingeben.", "leere Felder -> Hinweis, kein Request")
	d._user.text = "Cy"
	d._pass.text = "falsch"
	_script = [[401, "{\"error\":\"Invalid credentials\"}"]]
	d._pass.text_submitted.emit(d._pass.text)
	_check(d._msg.text == "Benutzername oder Passwort falsch." and res.is_empty() and d._pass.text == "",
		"Enter -> Anmelden, 401 -> verstaendlicher Fehler, Passwort geleert")
	d._pass.text = "richtig"
	_script = [[200, "{\"token\":\"T\",\"userId\":\"9\",\"username\":\"Cy\"}"]]
	d.submit()
	_check(a.logged_in() and res == [true], "Erfolg -> angemeldet, finished(true)")
	_check(d._msg.text.contains("Cy"), "Erfolgs-Hinweis nennt den Namen")
	_check(a.backfill_auto_done(), "erster Login -> Upload alter Scores angestossen")
	_check(not LoginDialog.should_show(a, none, false), "angemeldet -> kein Dialog mehr")
	d.queue_free()
	a.free()

	print("FAILED: %d" % _failed if _failed > 0 else "ALL OK")
	quit(1 if _failed > 0 else 0)
