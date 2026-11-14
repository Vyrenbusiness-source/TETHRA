class_name TempoBrowserRow
extends RefCounted

## Song-Browser (mv-tempo): Schalter "Turbo" (+ "Tonhoehe halten") in der
## Mods-Zeile neben SV/No-Fail und ein eigener Knopf "Ueben" fuer den
## Uebungsmodus. Nur im Mania-Modus sichtbar. song_select.gd ruft build(),
## set_visible(), add_mods() und beim Oeffnen PracticeSession.clear().

## Turbo an/aus (fuer die Sitzung, nicht in settings.cfg).
static var turbo_on := false
static var _btns: Array = []


static func _t(s: String) -> String:
	return TranslationServer.translate(s)


static func build(browser: Control, row: Control) -> void:
	PracticeSession.clear()
	_btns = []
	var tb := _toggle(browser, "Turbo",
			_t("Tempo rises 5 % after every clean section and falls back on a miss. Own local ranking."))
	tb.button_pressed = turbo_on
	tb.toggled.connect(func(on): turbo_on = on)
	row.add_child(tb)
	var kp := _toggle(browser, _t("Keep pitch"),
			_t("Turbo and practice: on = time-stretch, the song keeps its key; off = nightcore sound."))
	kp.button_pressed = TempoPrefs.keep_pitch()
	kp.toggled.connect(func(on): TempoPrefs.set_keep_pitch(on))
	row.add_child(kp)
	var pb := Button.new()
	pb.text = _t("Practice")
	pb.tooltip_text = _t("Loop a section, raise the tempo step by step, jump to your error spots. Unranked.")
	pb.custom_minimum_size = Vector2(0, 40)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.add_theme_font_size_override("font_size", 14)
	UiTheme.style_ghost_button(pb, 10)
	pb.pressed.connect(_start_practice.bind(browser))
	row.add_child(pb)
	_btns = [tb, kp, pb]


static func _toggle(browser: Control, text: String, tip: String) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 14)
	var box: StyleBox = browser.call("_toggle_box", false, 10)
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("pressed", box)
	b.add_theme_stylebox_override("hover", browser.call("_toggle_box", false, 10, true))
	b.add_theme_stylebox_override("hover_pressed", browser.call("_toggle_box", false, 10, true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for fc in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(fc, UiTheme.TEXT)
	UiTheme._attach_sounds(b)
	return b


static func set_visible(mania: bool) -> void:
	for b in _btns:
		if is_instance_valid(b):
			(b as Control).visible = mania


## Mania-Mods um Turbo ergaenzen.
static func add_mods(m: Dictionary) -> Dictionary:
	if turbo_on:
		m["TB"] = true
	return m


## Uebungsmodus starten: wie Spielen, aber ohne Turbo und mit Uebungs-Sitzung.
static func _start_practice(browser: Control) -> void:
	var s := PracticeSession.begin()
	s.keep_pitch = TempoPrefs.keep_pitch()
	browser.call("_on_play_pressed")
	# Ueben = nur die Noten: ohne Turbo und ohne Regel-Mods (SD/PF brechen ab,
	# Minen-Ansicht haengt am ersten Core). Szenenwechsel ist verzoegert.
	GameSession.mods.erase("TB")
	for k in RuleMods.KEYS:
		GameSession.mods.erase(k)
