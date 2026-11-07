class_name UpdateToast
extends CanvasLayer

## Toast unten rechts im Glas-Stil: Download-Fortschritt, "Update bereit" mit
## Countdown-Neustart und "Neu in vX.Y.Z"-Release-Notes. Wird vom Updater an
## get_tree().root gehaengt, braucht keine Szene.

signal restart_requested
signal postponed

var _panel: PanelContainer
var _title: Label
var _body: Label
var _bar: ProgressBar
var _btn_row: HBoxContainer
var _btn_now: Button
var _btn_later: Button
var _countdown := -1.0
var _tween: Tween


func _init() -> void:
	layer = 100
	_build()
	_panel.visible = false


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _box())
	_panel.custom_minimum_size = Vector2(340, 0)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -24
	_panel.offset_right = -24
	_panel.offset_top = -24
	_panel.offset_bottom = -24
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", UiTheme.TEXT)
	v.add_child(_title)
	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 13)
	_body.add_theme_color_override("font_color", UiTheme.DIM)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(300, 0)
	v.add_child(_body)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	var bg := UiTheme.solid_box(Color(1, 1, 1, 0.08), 3)
	bg.shadow_size = 0
	var fill := UiTheme.solid_box(UiTheme.ACCENT, 3)
	fill.shadow_size = 0
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fill)
	v.add_child(_bar)
	_btn_row = HBoxContainer.new()
	_btn_row.add_theme_constant_override("separation", 8)
	_btn_row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(_btn_row)
	_btn_later = Button.new()
	_btn_later.text = "Später"
	UiTheme.style_button(_btn_later, false)
	_btn_later.pressed.connect(_on_later)
	_btn_row.add_child(_btn_later)
	_btn_now = Button.new()
	_btn_now.text = "Jetzt neu starten"
	UiTheme.style_button(_btn_now, true)
	_btn_now.pressed.connect(func(): restart_requested.emit())
	_btn_row.add_child(_btn_now)


static func _box() -> StyleBoxFlat:
	var sb := UiTheme.glass_box(16, 0.78, 0.16)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


func _show_panel() -> void:
	if _panel.visible:
		return
	_panel.visible = true
	_panel.modulate.a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.25)


func hide_toast() -> void:
	_countdown = -1.0
	if _tween:
		_tween.kill()
	_panel.visible = false


## Download läuft: Fortschrittsbalken, keine Buttons.
func show_progress(version: String, ratio: float, title: String = "") -> void:
	_countdown = -1.0
	_title.text = title if title != "" else "Update v%s wird geladen…" % version
	_body.visible = false
	_bar.visible = true
	_bar.value = clampf(ratio, 0.0, 1.0)
	_btn_row.visible = false
	_show_panel()


## Update liegt bereit; mit countdown_s > 0 startet der Neustart automatisch.
func show_ready(version: String, countdown_s: float, title: String = "") -> void:
	_title.text = title if title != "" else "Update v%s bereit" % version
	_body.visible = true
	_bar.visible = false
	_btn_row.visible = true
	_countdown = countdown_s
	_update_countdown_text()
	_show_panel()


## Update wartet bis zum Songende.
func show_waiting(version: String) -> void:
	_countdown = -1.0
	_title.text = "Update v%s geladen" % version
	_body.text = "Wird nach dem Song angeboten."
	_body.visible = true
	_bar.visible = false
	_btn_row.visible = false
	_show_panel()


## "Neu in vX.Y.Z" mit Release-Notes; schließt sich selbst nach 12 s.
func show_notes(version: String, notes: String) -> void:
	_countdown = -1.0
	_title.text = "Neu in v%s" % version
	_body.text = notes
	_body.visible = true
	_bar.visible = false
	_btn_row.visible = true
	_btn_now.visible = false
	_btn_later.visible = true
	_btn_later.text = "Schließen"
	_show_panel()
	await get_tree().create_timer(12.0).timeout
	if _title.text.begins_with("Neu in"):
		hide_toast()


func show_error(text: String) -> void:
	_countdown = -1.0
	_title.text = "Update fehlgeschlagen"
	_body.text = text
	_body.visible = true
	_bar.visible = false
	_btn_row.visible = false
	_show_panel()
	await get_tree().create_timer(6.0).timeout
	if _title.text == "Update fehlgeschlagen":
		hide_toast()


func _update_countdown_text() -> void:
	if _countdown > 0.0:
		_body.text = "Neustart in %d s — danach geht es ins Hauptmenü." % ceili(_countdown)
	else:
		_body.text = "Neustart ins Hauptmenü."
	_btn_now.visible = true
	_btn_later.text = "Später"


func _on_later() -> void:
	hide_toast()
	postponed.emit()


func _process(delta: float) -> void:
	if _countdown <= 0.0:
		return
	_countdown -= delta
	if _countdown <= 0.0:
		_countdown = -1.0
		restart_requested.emit()
		return
	_update_countdown_text()


func is_counting() -> bool:
	return _panel.visible and _countdown > 0.0
