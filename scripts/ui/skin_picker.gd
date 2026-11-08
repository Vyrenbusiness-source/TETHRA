class_name SkinPicker
extends HBoxContainer

## Auswahl fuer den osu!mania-Skin im 2D-Modus: Dropdown ("Standard", die 3 eingebauten
## Skins Balken/Kreise/Pfeile, dann importierte), "Importieren…" (.osk/.zip oder Skin-Ordner) und Löschen (nur importierte Skins).
## Auswahl setzt Settings.skin_2d und speichert; Signal changed fuer Vorschau-Refresh.

signal changed

var _opt: OptionButton
var _import_btn: Button
var _osu_btn: MenuButton
var _osu_list: Array = []
var _del_btn: Button
var _dialog: FileDialog
var _status: Label
var _names: PackedStringArray = []


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_opt = OptionButton.new()
	_opt.custom_minimum_size = Vector2(180, 0)
	_opt.item_selected.connect(_on_selected)
	add_child(_opt)
	_import_btn = Button.new()
	_import_btn.text = "Importieren…"
	UiTheme.style_button(_import_btn)
	_import_btn.pressed.connect(_on_import_pressed)
	add_child(_import_btn)
	# Ein Klick: installierte osu!-Skins mit Mania-Grafiken uebernehmen.
	_osu_btn = MenuButton.new()
	_osu_btn.text = "Aus osu!"
	_osu_btn.tooltip_text = "Skin aus deiner osu!-Installation übernehmen"
	UiTheme.style_button(_osu_btn)
	_osu_btn.about_to_popup.connect(_fill_osu_menu)
	_osu_btn.get_popup().id_pressed.connect(func(i: int):
		if i >= 0 and i < _osu_list.size():
			_import(String(_osu_list[i].path)))
	add_child(_osu_btn)
	_del_btn = Button.new()
	_del_btn.text = "Löschen"
	UiTheme.style_button(_del_btn)
	_del_btn.pressed.connect(_on_delete)
	add_child(_del_btn)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	add_child(_status)
	# Leerer Status nimmt keinen Platz ein (eingebettet im Einstellungsfenster).
	_status.visible = false
	_status.draw.connect(func(): pass)


func _ready() -> void:
	refresh()


## Liste neu einlesen und die gespeicherte Auswahl markieren.
func refresh() -> void:
	_opt.clear()
	_opt.add_item("Standard")
	_names = ManiaSkin.list_skins()
	var sel := 0
	for i in _names.size():
		_opt.add_item(ManiaSkin.display_name(_names[i]))
		if _names[i] == Settings.skin_2d:
			sel = i + 1
	if sel == 0 and Settings.skin_2d != "":
		Settings.skin_2d = ""
		Settings.save()
	_opt.select(sel)
	_del_btn.disabled = sel == 0 or ManiaSkin.is_builtin(Settings.skin_2d)


func _on_selected(idx: int) -> void:
	Settings.skin_2d = "" if idx <= 0 or idx > _names.size() else _names[idx - 1]
	Settings.save()
	_del_btn.disabled = idx <= 0 or ManiaSkin.is_builtin(Settings.skin_2d)
	_status.text = ""
	changed.emit()


func _on_import_pressed() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.title = "osu!mania-Skin wählen (.osk, .zip oder Ordner)"
		_dialog.filters = PackedStringArray(["*.osk, *.zip ; osu!-Skin"])
		_dialog.file_selected.connect(_import)
		_dialog.dir_selected.connect(_import)
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.6)


func _import(path: String) -> void:
	var nm := ManiaSkin.import_skin(path)
	if nm == "":
		_status.text = ManiaSkin.last_error if ManiaSkin.last_error != "" else "Import fehlgeschlagen"
		return
	Settings.skin_2d = nm
	Settings.save()
	refresh()
	_status.text = tr("„%s“ aktiv") % nm
	changed.emit()


func _fill_osu_menu() -> void:
	var pm := _osu_btn.get_popup()
	pm.clear()
	_osu_list = ManiaSkin.osu_skins()
	if _osu_list.is_empty():
		pm.add_item("Keine osu!-Skins mit Mania-Grafiken gefunden", -1)
		pm.set_item_disabled(0, true)
		return
	for i in _osu_list.size():
		pm.add_item(String(_osu_list[i].name), i)


func _on_delete() -> void:
	var nm := Settings.skin_2d
	if nm == "" or ManiaSkin.is_builtin(nm):
		return
	ManiaSkin.delete_skin(nm)
	Settings.skin_2d = ""
	Settings.save()
	refresh()
	_status.text = "Gelöscht"
	changed.emit()
