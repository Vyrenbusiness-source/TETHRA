extends SceneTree

## Headless-Tests fuer den osu!mania-Skin-Import (2D).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_mania_skin_tests.gd

const INI := """[General]
Name: Test
[Mania]
Keys: 7
ColumnWidth: 10,10,10,10,10,10,10
[Mania]
Keys: 4
ColumnWidth: 40,50,50,40 // Kommentar
ColumnLineWidth: 3,2,2,2,3
HitPosition: 380
LightPosition: 400
NoteBodyStyle: 2
KeysUnderNotes: 1
JudgementLine: 0
NoteImage1: Sub\\Custom-Note
KeyImage0D: mania-keypressed
StageLeft: mania-stage-left
Colour1: 255,0,0
ColourHold: 0,255,0,128
"""

var _passed := 0
var _failed := 0
var _done := false
var _tmp := "user://skin_test_tmp"


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _run() -> void:
	print("=== TETHRA ManiaSkin-Tests ===")
	_test_parser()
	_test_defaults()
	_test_safe_rel()
	_test_import_zip()
	_test_import_dir()
	_test_builtin()
	_cleanup()
	print("--- %d bestanden, %d fehlgeschlagen ---" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(c: bool, msg: String) -> void:
	if c:
		_passed += 1
		print("  ok   ", msg)
	else:
		_failed += 1
		print("  FAIL ", msg)


func _test_parser() -> void:
	var s := ManiaSkin.parse(INI, 4)
	_ok(s.has_mania_block, "4K-Block gefunden (7K uebersprungen)")
	_ok(s.col_units(0) == 40.0 and s.col_units(1) == 50.0 and s.col_units(3) == 40.0, "ColumnWidth je Spalte, Kommentar entfernt")
	_ok(is_equal_approx(s.stage_units(), 180.0), "Buehnenbreite = Summe")
	_ok(s.hit_position == 380.0 and s.light_position == 400.0, "HitPosition/LightPosition")
	_ok(s.note_body_style == 2 and s.keys_under_notes and not s.judgement_line, "BodyStyle/KeysUnderNotes/JudgementLine")
	_ok(s.colours.get(0) == Color(1, 0, 0), "Colour1 -> Spalte 0")
	_ok(s.colour_hold is Color and is_equal_approx(s.colour_hold.a, 128.0 / 255.0), "ColourHold mit Alpha")
	_ok(float(s.column_line_width[0]) == 3.0 and float(s.column_line_width[4]) == 3.0, "ColumnLineWidth")
	_ok(String(s._names["note_1"]) == "Sub\\Custom-Note", "NoteImage1 aus ini")
	_ok(String(s._names["head_1"]) == "Sub\\Custom-NoteH", "Kopf-Standard = NoteImage + H")
	_ok(String(s._names["keyd_0"]) == "mania-keypressed", "KeyImage0D aus ini")


func _test_defaults() -> void:
	var s := ManiaSkin.parse("", 4)
	_ok(not s.has_mania_block, "leere ini: kein Block")
	_ok(s.hit_position == 402.0 and s.col_units(2) == 30.0, "Standardwerte (402, 30)")
	_ok(String(s._names["note_0"]) == "mania-note1" and String(s._names["note_1"]) == "mania-note2"
			and String(s._names["note_2"]) == "mania-note2" and String(s._names["note_3"]) == "mania-note1", "4K-Notenmuster 1/2/2/1")
	_ok(String(s._names["head_0"]) == "mania-note1H" and String(s._names["body_1"]) == "mania-note2L"
			and String(s._names["tail_3"]) == "mania-note1T", "H/L/T-Suffixe")
	_ok(String(s._names["key_1"]) == "mania-key2" and String(s._names["keyd_1"]) == "mania-key2D", "Key-Bilder + D")
	_ok(String(s._names["stage_hint"]) == "mania-stage-hint" and String(s._names["stage_left"]) == "mania-stage-left", "Stage-Namen")
	_ok(s.tex("note_0") == null, "ohne Ordner: Textur null (Fallback)")


func _test_safe_rel() -> void:
	_ok(ManiaSkin.safe_rel("../evil.png") == "", "Zip-Slip ..")
	_ok(ManiaSkin.safe_rel("a/../../evil.png") == "", "Zip-Slip a/../..")
	_ok(ManiaSkin.safe_rel("..\\evil.png") == "", "Zip-Slip Backslash")
	_ok(ManiaSkin.safe_rel("/etc/passwd") == "", "absoluter Pfad")
	_ok(ManiaSkin.safe_rel("C:/x.png") == "", "Laufwerk")
	_ok(ManiaSkin.safe_rel("Sub\\mania-note1.png") == "Sub/mania-note1.png", "Backslash -> /")


func _png(c: Color, w: int = 8, h: int = 4) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img.save_png_to_buffer()


func _make_zip(path: String) -> void:
	var zp := ZIPPacker.new()
	zp.open(path)
	zp.start_file("skin.ini")
	zp.write_file(INI.to_utf8_buffer())
	zp.close_file()
	var items := {
		"mania-note1.png": _png(Color.RED),
		"mania-note1@2x.png": _png(Color.RED, 16, 8),
		"mania-key1.png": _png(Color.BLUE),
		"Sub/Custom-Note.png": _png(Color.GREEN),
		"mania-note2L.png": PackedByteArray([1, 2, 3, 4]),   # kaputt
		"unrelated.png": _png(Color.WHITE),
		"hitcircle.png": _png(Color.WHITE),
		"../evil.png": _png(Color.BLACK),
	}
	for k in items:
		zp.start_file(k)
		zp.write_file(items[k])
		zp.close_file()
	zp.close()


func _test_import_zip() -> void:
	DirAccess.make_dir_recursive_absolute(_tmp)
	var zip := _tmp + "/Mein Skin.osk"
	_make_zip(zip)
	var nm := ManiaSkin.import_skin(ProjectSettings.globalize_path(zip))
	_ok(nm == "Mein Skin", "Import liefert Namen (" + nm + ")")
	_ok(ManiaSkin.list_skins().has("Mein Skin"), "list_skins enthaelt Skin")
	var base := "user://skins/Mein Skin"
	_ok(FileAccess.file_exists(base + "/skin.ini"), "skin.ini kopiert")
	_ok(FileAccess.file_exists(base + "/mania-note1@2x.png") and not FileAccess.file_exists(base + "/mania-note1.png"), "@2x bevorzugt")
	_ok(FileAccess.file_exists(base + "/Sub/Custom-Note.png"), "in ini referenziertes Bild kopiert")
	_ok(not FileAccess.file_exists(base + "/unrelated.png") and not FileAccess.file_exists(base + "/hitcircle.png"), "Unnoetiges nicht kopiert")
	_ok(not FileAccess.file_exists("user://skins/evil.png") and not FileAccess.file_exists("user://evil.png"), "Zip-Slip nicht geschrieben")
	var s := ManiaSkin.load_skin("Mein Skin")
	_ok(s != null and s.skin_name == "Mein Skin", "load_skin")
	if s != null:
		var t := s.tex("note_0")
		_ok(t != null and t.get_width() == 16 and s.tex_scale("note_0") == 0.5, "@2x geladen, Mass halbiert")
		_ok(s.tex("note_1") != null, "Pfad mit Backslash + Gross/Klein + ohne .png aufgeloest")
		_ok(s.tex("body_1") == null, "kaputtes PNG -> null (Fallback)")
		_ok(s.tex("head_2") == null and s.tex("stage_hint") == null, "fehlende Datei -> null")
	_ok(ManiaSkin.load_skin("gibt es nicht") == null, "load_skin unbekannt -> null")
	_ok(ManiaSkin.load_skin("../x") == null, "load_skin Pfadtrick -> null")
	_ok(ManiaSkin.import_skin(_tmp + "/nope.osk") == "", "fehlende Datei -> \"\"")
	var bad := _tmp + "/bad.zip"
	var bf := FileAccess.open(bad, FileAccess.WRITE)
	bf.store_string("kein zip")
	bf.close()
	_ok(ManiaSkin.import_skin(ProjectSettings.globalize_path(bad)) == "", "kaputtes Zip -> \"\"")
	_ok(ManiaSkin.delete_skin("Mein Skin") and not ManiaSkin.list_skins().has("Mein Skin"), "delete_skin")


func _test_import_dir() -> void:
	var dir := _tmp + "/FolderSkin"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in [["skin.ini", INI.to_utf8_buffer()], ["mania-key1.png", _png(Color.BLUE)], ["junk.png", _png(Color.RED)]]:
		var wf := FileAccess.open(dir + "/" + f[0], FileAccess.WRITE)
		wf.store_buffer(f[1])
		wf.close()
	var nm := ManiaSkin.import_skin(ProjectSettings.globalize_path(dir))
	_ok(nm == "FolderSkin", "Ordner-Import")
	_ok(FileAccess.file_exists("user://skins/FolderSkin/mania-key1.png") and not FileAccess.file_exists("user://skins/FolderSkin/junk.png"), "nur noetige Dateien")
	ManiaSkin.delete_skin("FolderSkin")


func _cleanup() -> void:
	ManiaSkin._remove_tree(_tmp)


func _test_builtin() -> void:
	var l := ManiaSkin.list_skins()
	_ok(l.size() >= 3 and l[0] == "builtin:Balken" and l[1] == "builtin:Kreise" and l[2] == "builtin:Pfeile", "eingebaute zuerst in list_skins")
	_ok(ManiaSkin.display_name("builtin:Kreise") == "Kreise", "Anzeige-Name")
	for id in ["builtin:Balken", "builtin:Kreise", "builtin:Pfeile"]:
		var s := ManiaSkin.load_skin(id)
		_ok(s != null and s.has_mania_block, id + " laedt")
		if s == null:
			continue
		var ok := true
		for c in 4:
			for key in ["note_%d", "head_%d", "body_%d", "tail_%d", "key_%d", "keyd_%d"]:
				if s.tex(key % c) == null:
					ok = false
					print("    fehlt: ", id, " ", key % c)
		_ok(ok, id + ": alle Texturen je Spalte vorhanden")
		_ok(s.tex("stage_hint") != null and s.tex_scale("note_0") == 0.5, id + ": Stage-Hint, @2x")
		_ok(not ManiaSkin.delete_skin(id), id + " nicht loeschbar")
	_ok(ManiaSkin.load_skin("builtin:Gibtsnicht") == null, "unbekannter builtin -> null")
