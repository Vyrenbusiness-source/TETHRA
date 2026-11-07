class_name SkinPicker
extends HBoxContainer

## Auswahl fuer den osu!mania-Skin im 2D-Modus: Dropdown ("Standard" + importierte
## Skins), "Importieren…" (.osk/.zip oder Skin-Ordner) und Löschen des gewählten Skins.
## Auswahl setzt Settings.skin_2d und speichert; Signal changed fuer Vorschau-Refresh.

signal changed

var _opt: OptionButton
var _import_btn: Button
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
	_del_btn = Button.new()
	_del_btn.text = "Löschen"
	UiTheme.style_button(_del_btn)
	_del_btn.pressed.connect(_on_delete)
	add_child(_del_btn)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	add_child(_status)


func _ready() -> void:
	refresh()


## Liste neu einlesen und die gespeicherte Auswahl markieren.
func refresh() -> void:
	_opt.clear()
	_opt.add_item("Standard")
	_names = ManiaSkin.list_skins()
	var sel := 0
	for i in _names.size():
		_opt.add_item(_names[i])
		if _names[i] == Settings.skin_2d:
			sel = i + 1
	if sel == 0 and Settings.skin_2d != "":
		Settings.skin_2d = ""
		Settings.save()
	_opt.select(sel)
	_del_btn.disabled = sel == 0


func _on_selected(idx: int) -> void:
	Settings.skin_2d = "" if idx <= 0 or idx > _names.size() else _names[idx - 1]
	Settings.save()
	_del_btn.disabled = idx <= 0
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
		_status.text = "Import fehlgeschlagen"
		return
	Settings.skin_2d = nm
	Settings.save()
	refresh()
	_status.text = "Importiert"
	changed.emit()


func _on_delete() -> void:
	var nm := Settings.skin_2d
	if nm == "":
		return
	ManiaSkin.delete_skin(nm)
	Settings.skin_2d = ""
	Settings.save()
	refresh()
	_status.text = "Gelöscht"
	changed.emit()
