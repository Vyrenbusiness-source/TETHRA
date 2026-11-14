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
	print("=== OMEN ManiaSkin-Tests ===")
	_test_parser()
	_test_defaults()
	_test_safe_rel()
	_test_import_zip()
	_test_import_dir()
	_test_patterns()
	_test_real_world()
	_test_builtin()
	_test_builtin_tint()
	_test_hold_geometry()
	_test_display_name()
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
	_ok(s._alts["head_1"].has("Sub\\Custom-Note"), "Kopf faellt auf die Note zurueck")
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
		_ok(s.tex("body_1") != null, "kaputtes PNG -> Balken-Fallback (wie osu!-Standardskin)")
		_ok(s.tex("head_2") != null and s.tex("stage_hint") == null, "fehlende Note -> Balken-Fallback, Stage-Hint -> null")
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


## Alte Farben der Built-in-Skins (vor der Graustufen-Umstellung): [Skin, Schluessel,
## x, y, Farbe, Toleranz]. Heute: Graustufen-Pixel x AutoColor der Spalte muss sie treffen.
## Kreise-Innenring: Verhaeltnis innen/aussen ist jetzt ein Grauwert (Toleranz groesser).
const OLD_SAMPLES := [
	["Balken", "note_0", 80, 10, Color8(236, 240, 248), 2],
	["Balken", "note_0", 80, 28, Color8(207, 211, 218), 2],
	["Balken", "note_0", 80, 36, Color8(168, 171, 177), 3],
	["Balken", "note_1", 80, 10, Color8(96, 150, 224), 2],
	["Balken", "note_1", 80, 28, Color8(84, 132, 197), 2],
	["Balken", "tail_0", 80, 3, Color8(236, 240, 248), 2],
	["Balken", "tail_0", 80, 12, Color8(207, 211, 218), 2],
	["Kreise", "note_0", 80, 12, Color8(126, 196, 214), 2],
	["Kreise", "note_0", 80, 40, Color8(34, 62, 82), 20],
	["Kreise", "note_0", 80, 80, Color8(88, 109, 125), 20],
	["Kreise", "note_1", 80, 12, Color8(196, 150, 214), 2],
	["Kreise", "note_1", 80, 40, Color8(60, 40, 84), 20],
	["Pfeile", "note_0", 80, 80, Color8(150, 190, 232), 2],
	["Pfeile", "note_0", 40, 80, Color8(150, 190, 232), 2],
	["Pfeile", "note_1", 80, 80, Color8(224, 160, 190), 2],
	["Pfeile", "note_3", 80, 80, Color8(232, 200, 140), 2],
]


func _near(a: Color, b: Color, tol: int) -> bool:
	return absi(a.r8 - b.r8) <= tol and absi(a.g8 - b.g8) <= tol and absi(a.b8 - b.b8) <= tol


func _test_builtin_tint() -> void:
	NoteColors.path = _tmp + "_nc.cfg"
	NoteColors.reload()
	NoteColors.reset(true)   # Modus auto
	var skins := {}
	for nm in ["Balken", "Kreise", "Pfeile"]:
		var s := ManiaSkin.load_skin("builtin:" + nm)
		skins[nm] = s
		_ok(s.tintable and s.auto_colors.size() == 4, nm + ": tintable + 4 AutoColors")
		# Noten/Holds/Kappen neutral (Grau): R == G == B an Stichproben.
		var gray_ok := true
		for key in ["note_0", "head_1", "body_2", "tail_3"]:
			var img := s.tex(key).get_image()
			for pt in [Vector2i(80, 4), Vector2i(80, 8), Vector2i(80, 12)]:
				var p := img.get_pixelv(pt)
				if p.a > 0.9 and (absf(p.r - p.g) > 0.01 or absf(p.g - p.b) > 0.01):
					gray_ok = false
		_ok(gray_ok, nm + ": Notenbilder neutral grau")
	# Auto = alte Farben (Graustufe x Palette der Spalte).
	var bad := 0
	for smp in OLD_SAMPLES:
		var s: ManiaSkin = skins[smp[0]]
		var key: String = smp[1]
		var col := ManiaSkin.key_col(key)
		var g := s.tex(key).get_image().get_pixel(int(smp[2]), int(smp[3]))
		var a := s.auto_color(col)
		var got := Color(g.r * a.r, g.g * a.g, g.b * a.b)
		if not _near(got, smp[4], int(smp[5])):
			bad += 1
			print("    ", smp[0], " ", key, " (", smp[2], ",", smp[3], ") alt ", (smp[4] as Color).to_html(false), " neu ", got.to_html(false))
	_ok(bad == 0, "Auto-Modus: Stichproben = alte Farben (%d Abweichungen)" % bad)
	# Toenung: auto -> Palette (+ Hold dunkler); lanes -> uebergebene Farbe, Kopf = Spaltenfarbe.
	var pf: ManiaSkin = skins["Pfeile"]
	var t0 := pf.tints(1, Color.RED, false)
	_ok(_near(t0[0], pf.auto_color(1), 0) and _near(t0[1], NoteColors.hold_of(pf.auto_color(1)), 1), "tints auto: Palette, Hold dunkler")
	NoteColors.apply_preset(true, "neon")
	var t1 := pf.tints(2, NoteColors.hold_color(true, 2), true)
	_ok(_near(t1[0], NoteColors.lane_color(true, 2), 0) and _near(t1[1], NoteColors.hold_color(true, 2), 0), "tints lanes: Kopf = Spaltenfarbe, Koerper = Hold-Farbe")
	var t2 := pf.tints(0, NoteColors.lane_color(true, 0), false)
	_ok(_near(t2[0], NoteColors.lane_color(true, 0), 0) and _near(t2[1], t2[0], 0), "tints lanes: Einzelnote")
	NoteColors.set_mode(true, "snap")
	var sc := NoteColors.snap_color(4)
	var t3 := pf.tints(0, NoteColors.hold_of(sc), true)
	_ok(_near(t3[0], sc, 3) and _near(t3[1], NoteColors.hold_of(sc), 0), "tints snap: Kopf = Takt-Farbe, Koerper dunkler")
	# Fallback-Skin fuer importierte Skins ohne Notenbilder bleibt farbig (eingefaerbt).
	var fb := ManiaSkin.load_skin("builtin:Balken")
	fb.bake_auto = true
	var px := fb.tex("note_1").get_image().get_pixel(80, 10)
	_ok(_near(px, Color8(96, 150, 224), 2), "Fallback-Balken: Noten eingefaerbt (blau)")
	NoteColors.reset(true)
	NoteColors.path = "user://note_colors.cfg"
	NoteColors.reload()


func _test_patterns() -> void:
	var exp := {
		4: ["1", "2", "2", "1"], 5: ["1", "2", "S", "2", "1"],
		6: ["1", "2", "1", "1", "2", "1"], 7: ["1", "2", "1", "S", "1", "2", "1"],
	}
	for n in exp:
		var got: Array = []
		for c in n:
			got.append(ManiaSkin.pattern_name(c, n))
		_ok(got == exp[n], "Standardmuster %dK: %s" % [n, "".join(got)])
	var s5 := ManiaSkin.parse("", 5)
	_ok(String(s5._names["note_2"]) == "mania-noteS" and String(s5._names["keyd_2"]) == "mania-keySD", "5K Mitte = S")


func _write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var wf := FileAccess.open(path, FileAccess.WRITE)
	wf.store_buffer(bytes)
	wf.close()


## Echte-Skin-Faelle: mehrere Bloecke, eingerueckte ini, Unterordner mit
## Backslash, Gross/Klein, Animation, Leerzeichen/Sonderzeichen, Fallbacks.
func _test_real_world() -> void:
	var ini := """[General]
Name: x
[Mania]
	Keys: 4
	ColumnStart: 306
	ColumnWidth: 60,61,62,63
	ColumnSpacing: 1,2,3
	ColumnLineWidth: 0,0,0,0,0
	HitPosition: 467
	NoteImage0: Arrownote\\Left Arrow
	NoteImage0H: Arrownote\\Left Arrow
	NoteImage0L: Arrownote\\LNB
	NoteImage1: ANIM\\Note-X
	KeyImage0: Arrows\\leftReceptor.PNG
	KeyImage0D: Arrows\\leftReceptorD
[Mania]
	Keys: 5
	ColumnWidth: 11
"""
	var dir := _tmp + "/Real #Skin [1.2] (SK)"
	_write(dir + "/skin.ini", ini.to_utf8_buffer())
	_write(dir + "/arrownote/LEFT ARROW.png", _png(Color.RED))
	_write(dir + "/Arrownote/LNB.png", _png(Color.GREEN, 8, 6))
	_write(dir + "/Arrows/leftReceptor.png", _png(Color.BLUE, 10, 10))
	_write(dir + "/Anim/Note-X-0.png", _png(Color.WHITE, 12, 6))
	_write(dir + "/Anim/Note-X-1.png", _png(Color.BLACK, 3, 3))
	_write(dir + "/MANIA-STAGE-HINT.png", _png(Color.GRAY))
	_write(dir + "/mania-note2@2x.png", _png(Color.RED, 20, 10))
	_write(dir + "/mania-key2.png", _png(Color.RED, 5, 5))
	_write(dir + "/junk.png", _png(Color.RED))
	var root := _tmp + "/skins"
	var nm := ManiaSkin.import_skin(ProjectSettings.globalize_path(dir), root)
	_ok(nm == "Real _Skin _1.2_ (SK)", "Sonderzeichen im Namen (" + nm + ")")
	_ok(FileAccess.file_exists(root + "/" + nm + "/Anim/Note-X-0.png") and FileAccess.file_exists(root + "/" + nm + "/Anim/Note-X-1.png"), "Animations-Frames aus Unterordner importiert")
	_ok(FileAccess.file_exists(root + "/" + nm + "/arrownote/LEFT ARROW.png") and FileAccess.file_exists(root + "/" + nm + "/Arrows/leftReceptor.png"), "Unterordner (anderes Case, Leerzeichen) importiert")
	_ok(not FileAccess.file_exists(root + "/" + nm + "/junk.png"), "Unnoetiges nicht importiert")
	var s := ManiaSkin.load_skin(nm, root)
	_ok(s != null and s.has_mania_block and s.keys == 4, "4K-Block trotz davor/danach anderer Bloecke")
	if s == null:
		return
	_ok(s.col_units(1) == 61.0 and s.col_units(3) == 63.0 and s.hit_position == 467.0, "ColumnWidth je Spalte, HitPosition 467")
	_ok(s.column_spacing == [1.0, 2.0, 3.0] and is_equal_approx(s.stage_units(), 246.0 + 6.0), "ColumnSpacing je Luecke")
	_ok(is_equal_approx(s.col_offset_units(2), 60.0 + 1.0 + 61.0 + 2.0), "Spaltenversatz mit Spacing")
	_ok(s.column_start == 306.0, "ColumnStart")
	var n0 := s.tex("note_0")
	_ok(n0 != null and n0.get_width() == 8, "Backslash + Gross/Klein + Leerzeichen, ohne Endung")
	_ok(s.tex("head_0") != null, "Kopf aus ini")
	_ok(s.tex("body_0") != null and s.tex("body_0").get_height() == 6, "Koerper aus Unterordner")
	var n1 := s.tex("note_1")
	_ok(n1 != null and n1.get_width() == 12, "Animation: erstes Frame (-0)")
	_ok(s.tex("key_0") != null and s.tex("key_0").get_width() == 10, "KeyImage mit .PNG-Endung gross")
	_ok(s.tex("keyd_0") != null, "fehlende Gedrueckt-Datei -> Balken-Fallback (nur dieses Element)")
	_ok(s.tex("stage_hint") != null, "mania-stage-hint in Grossbuchstaben")
	_ok(s.tex("head_1") != null and s.tex("head_1").get_width() == 12, "Kopf fehlt -> Note der Spalte")
	_ok(s.tex("note_2") != null and s.tex_scale("note_2") == 0.5, "Standarddatei mania-note2@2x, halbe Groesse")
	_ok(s.tex("key_2") != null and s.tex("key_2").get_width() == 5, "Standard-Key mania-key2 fuer Spalte 3")
	ManiaSkin.delete_skin_in(root, nm)


## Hold-Enden: rundes Bild (Ball) wird weggelassen, deckendes Quadrat / flache Kappe nicht.
func _test_hold_geometry() -> void:
	var disc := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	for y in 40:
		for x in 40:
			if Vector2(x - 19.5, y - 19.5).length() <= 20.0:
				disc.set_pixel(x, y, Color.WHITE)
	_ok(ManiaSkin.image_is_round(disc), "Scheibe = rund (Ball am Hold-Ende entfaellt)")
	var sq := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	sq.fill(Color.BLACK)
	_ok(not ManiaSkin.image_is_round(sq), "deckendes Quadrat (Unknown noteT) ist kein Ball")
	var cap := Image.create(60, 10, false, Image.FORMAT_RGBA8)
	cap.fill(Color.WHITE)
	_ok(not ManiaSkin.image_is_round(cap), "flache Kappe ist kein Ball")
	_ok(not ManiaSkin.image_is_round(null), "null -> nicht rund")
	# Skin ohne eigene Noten-Bilder: Fallback auf eingebaute Balken
	var dir := _tmp + "/skins_nonotes/Leer"
	_write(dir + "/skin.ini", "[Mania]
Keys: 4
".to_utf8_buffer())
	var sk := ManiaSkin.load_skin("Leer", _tmp + "/skins_nonotes")
	_ok(sk != null and sk.tex("note_0") != null and sk.tex("body_0") != null and sk.tex("key_0") != null,
			"Skin ohne Noten-Bilder: Fallback auf Balken")


func _test_display_name() -> void:
	var root := _tmp + "/skins_names"
	_write(root + "/A/skin.ini", "[General]
Name: Schoener Name
".to_utf8_buffer())
	_write(root + "/B/skin.ini", "[General]
Name: Ini
".to_utf8_buffer())
	_write(root + "/B/tethra_name.txt", "Original Datei
".to_utf8_buffer())
	_write(root + "/C/foo.txt", "x".to_utf8_buffer())
	_ok(ManiaSkin.display_name("A", root) == "Schoener Name", "Anzeige-Name aus skin.ini [General] Name")
	_ok(ManiaSkin.display_name("B", root) == "Original Datei", "tethra_name.txt hat Vorrang")
	_ok(ManiaSkin.display_name("C", root) == "C", "sonst Ordnername")

