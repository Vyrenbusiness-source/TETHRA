class_name LoginDialog
extends Control

## Ruhiger Login-Dialog beim Spielstart (Hauptmenue) und gemeinsame Login-Logik
## fuer das Profil (Fehlertexte, Upload alter Scores nach dem ersten Login).
## Enter = Anmelden, Esc = Spaeter. "Spaeter" fragt beim naechsten Spielstart
## wieder, "Nicht mehr fragen" speichert in user://online.cfg ([prompt] never).

## logged_in = true nach erfolgreicher Anmeldung, false bei "Spaeter".
signal finished(logged_in: bool)

const WIDTH := 420.0
## Wie lange der Erfolgs-Hinweis stehen bleibt, bevor der Dialog ausblendet.
const SUCCESS_HOLD_S := 1.4

## Pro Spielstart nur einmal fragen (zurueck ins Hauptmenue fragt nicht erneut).
static var shown_this_run := false

## Test-Hook: sonst GameSession.online.
var api: OnlineApi
## Test-Hook: Callable() -> Dictionary (Dateiname -> Pfad) fuer den Upload alter Scores.
var osz_provider := Callable()

var _user: LineEdit
var _pass: LineEdit
var _msg: Label
var _never: CheckButton
var _login_btn: Button
var _register_btn: Button
var _later_btn: Button
var _busy := false
var _closing := false


# --- Gemeinsame Logik (auch ProfilePanel) -------------------------------------

## Dialog zeigen? Nur wenn Online aktiv, nicht angemeldet, kein Headless-/Test-/
## Shot-Lauf, nicht abgeschaltet und in diesem Spielstart noch nicht gefragt.
static func should_show(p_api: OnlineApi, args: PackedStringArray, headless: bool) -> bool:
	if p_api == null or not p_api.enabled() or p_api.logged_in():
		return false
	if headless or shown_this_run or is_harness_run(args):
		return false
	return not p_api.login_prompt_disabled()


## Shot-/Test-/Mess-Lauf (Kommandozeile): keine Dialoge, kein Netz-Upload.
static func is_harness_run(args: PackedStringArray) -> bool:
	for a in args:
		if a.begins_with("--shot") or a in ["--autoplay", "--perf", "--test", "--bench"]:
			return true
	return false


## Angemeldet, aber der automatische Upload alter Scores steht noch aus (z. B. nach
## neuer Merker-Version): beim Spielstart nachholen.
static func should_resume_backfill(p_api: OnlineApi, args: PackedStringArray, headless: bool) -> bool:
	if p_api == null or not p_api.enabled() or not p_api.logged_in():
		return false
	if headless or is_harness_run(args):
		return false
	return not p_api.backfill_auto_done()


## Verstaendlicher Text zu einer Login-Fehlermeldung von OnlineApi.login().
static func error_text(msg: String) -> String:
	var m := msg.strip_edges().to_lower()
	var t := ""
	if m == "":
		t = "Anmelden fehlgeschlagen."
	elif m == "empty":
		t = "Bitte Benutzername und Passwort eingeben."
	elif m == "disabled":
		t = "Online-Konto: noch nicht freigeschaltet."
	elif m == "offline" or m.begins_with("http 5") or m.contains("timeout"):
		t = "Server nicht erreichbar. Prüfe die Internetverbindung oder versuch es später."
	elif m.contains("verif") or m.contains("confirm") or m.contains("bestätig") \
			or m.contains("not_activated") or m.contains("not activated"):
		t = "E-Mail noch nicht bestätigt. Öffne den Link in der Mail von TETHRA und melde dich dann an."
	elif m.contains("credential") or m.contains("password") or m.contains("passwort") \
			or m == "http 401" or m.contains("unauthorized"):
		t = "Benutzername oder Passwort falsch."
	elif m == "http 429" or m.contains("too many") or m.contains("rate"):
		t = "Zu viele Versuche. Warte kurz und versuch es noch einmal."
	else:
		return TranslationServer.translate("Anmelden fehlgeschlagen: %s") % msg.strip_edges()
	return TranslationServer.translate(t)


## Nach erfolgreichem Login: beim ersten Login alte Mania-Bestwerte einmalig
## hochladen. osz_files: Dateiname -> Pfad. true = Upload gestartet.
static func after_login(p_api: OnlineApi, osz_files: Dictionary) -> bool:
	if p_api == null or not p_api.logged_in() or p_api.backfill_auto_done():
		return false
	p_api.set_backfill_auto_done()
	return p_api.start_backfill(osz_files)


## Alle lokalen Maps (Dateiname -> Pfad) fuer den Upload alter Scores.
static func scan_osz_files() -> Dictionary:
	var lib := MapLibrary.new()
	lib.scan()
	var out := {}
	for ms in lib.mapsets:
		out[str(ms.osz_path).get_file()] = str(ms.osz_path)
	return out


# --- Dialog ------------------------------------------------------------------

func _ready() -> void:
	if api == null:
		api = GameSession.online
	shown_this_run = true
	z_index = 60
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	if api != null and api.username != "":
		_user.text = api.username
	(_pass if _user.text != "" else _user).grab_focus.call_deferred()


func _build() -> void:
	var back := UiTheme.modal_backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	var pb := UiTheme.solid_box(UiTheme.SURFACE, 14)
	pb.set_border_width_all(1)
	pb.border_color = UiTheme.LINE
	pb.content_margin_left = 28
	pb.content_margin_right = 28
	pb.content_margin_top = 24
	pb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", pb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var title := Label.new()
	title.text = tr("Online anmelden")
	title.add_theme_font_override("font", UiTheme.heading_font(0))
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UiTheme.TEXT)
	vb.add_child(title)
	var sub := _label(tr("Mit Konto zählen deine Scores in den Online-Ranglisten."), 14, UiTheme.DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	vb.add_child(gap)

	_user = _field(tr("Benutzername"), false)
	_pass = _field(tr("Passwort"), true)
	vb.add_child(_user)
	vb.add_child(_pass)
	_user.text_submitted.connect(func(_t): submit())
	_pass.text_submitted.connect(func(_t): submit())

	_msg = _label("", 13, UiTheme.DIM)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.visible = false
	vb.add_child(_msg)

	_login_btn = _button(tr("Anmelden"), true)
	_login_btn.pressed.connect(submit)
	vb.add_child(_login_btn)
	_register_btn = _button(tr("Registrieren"), false)
	_register_btn.pressed.connect(open_register)
	vb.add_child(_register_btn)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	vb.add_child(foot)
	_never = CheckButton.new()
	_never.text = tr("Nicht mehr fragen")
	_never.focus_mode = Control.FOCUS_NONE
	_never.add_theme_font_size_override("font_size", 13)
	_never.add_theme_color_override("font_color", UiTheme.DIM)
	_never.add_theme_color_override("font_hover_color", UiTheme.TEXT)
	_never.add_theme_color_override("font_pressed_color", UiTheme.DIM)
	_never.add_theme_color_override("font_hover_pressed_color", UiTheme.TEXT)
	foot.add_child(_never)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fill)
	_later_btn = Button.new()
	_later_btn.text = tr("Später")
	_later_btn.flat = true
	_later_btn.focus_mode = Control.FOCUS_NONE
	_later_btn.add_theme_font_size_override("font_size", 14)
	_later_btn.add_theme_color_override("font_color", UiTheme.DIM)
	_later_btn.add_theme_color_override("font_hover_color", UiTheme.TEXT)
	_later_btn.add_theme_color_override("font_pressed_color", UiTheme.TEXT)
	_later_btn.pressed.connect(later)
	foot.add_child(_later_btn)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _field(ph: String, secret: bool) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.secret = secret
	le.custom_minimum_size = Vector2(0, 42)
	le.add_theme_font_size_override("font_size", 15)
	return le


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_override("font", UiTheme.heading_font(0))
	b.add_theme_font_size_override("font_size", 17)
	UiTheme.style_button(b, primary)
	return b


func _show_msg(text: String, col: Color) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", col)
	_msg.visible = text != ""


func _set_busy(on: bool) -> void:
	_busy = on
	_login_btn.disabled = on
	_register_btn.disabled = on
	_user.editable = not on
	_pass.editable = not on


## Anmelden (Knopf, Enter).
func submit() -> void:
	if _busy or _closing:
		return
	var u := _user.text.strip_edges()
	if u == "" or _pass.text == "":
		_show_msg(error_text("empty"), UiTheme.BAD)
		(_user if u == "" else _pass).grab_focus()
		return
	if api == null or not api.enabled():
		_show_msg(error_text("disabled"), UiTheme.BAD)
		return
	_set_busy(true)
	_show_msg(tr("Melde an …"), UiTheme.DIM)
	api.login(u, _pass.text, _on_login)


func _on_login(ok: bool, msg: String) -> void:
	_set_busy(false)
	if not ok:
		_pass.text = ""
		_show_msg(error_text(msg), UiTheme.BAD)
		if is_inside_tree():
			_pass.grab_focus()
		return
	_pass.text = ""
	var files: Dictionary = osz_provider.call() if osz_provider.is_valid() else scan_osz_files()
	var started := after_login(api, files)
	var hint := tr("Angemeldet als %s.") % api.username
	if started:
		hint += " " + tr("Deine alten Bestwerte werden hochgeladen.")
	_show_msg(hint, UiTheme.GOOD)
	_set_busy(true)
	_close(true, SUCCESS_HOLD_S)


## Registrieren: Website im Browser, danach hier einfach anmelden.
func open_register() -> void:
	if api != null:
		api.open_register()
	_show_msg(tr("Konto im Browser anlegen, E-Mail bestätigen, dann hier anmelden."), UiTheme.DIM)
	_user.grab_focus()


## Spaeter (Knopf, Esc). Mit Haken "Nicht mehr fragen" dauerhaft aus.
func later() -> void:
	if _closing:
		return
	if _never.button_pressed and api != null:
		api.set_login_prompt_disabled(true)
	_close(false, 0.0)


func _close(logged_in: bool, delay: float) -> void:
	if _closing:
		return
	_closing = true
	finished.emit(logged_in)
	if not is_inside_tree():
		queue_free()
		return
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(self, "modulate:a", 0.0, 0.16)
	tw.tween_callback(queue_free)


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		later()
