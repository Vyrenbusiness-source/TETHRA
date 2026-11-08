extends SceneTree

## Headless-Tests fuer NoteColors.
##   Godot..._console.exe --headless --path . --audio-driver Dummy --script res://tests/run_note_colors_tests.gd

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _initialize() -> void:
	print("=== NoteColors-Tests ===")
	NoteColors.path = "user://note_colors_test.cfg"
	DirAccess.remove_absolute(NoteColors.path)
	NoteColors.reload()
	_test_auto()
	_test_lanes()
	_test_snap()
	_test_presets()
	_test_reset_snapshot()
	_test_recent()
	_test_save_load()
	DirAccess.remove_absolute(NoteColors.path)
	print("FAILED: %d" % _failed if _failed > 0 else "ALL OK")
	quit(1 if _failed > 0 else 0)


func _test_auto() -> void:
	var m := Color(0.3, 0.4, 0.5)
	_check(NoteColors.mode(false) == "auto" and NoteColors.mode(true) == "auto", "Standard = auto")
	_check(not NoteColors.is_custom(false), "auto nicht custom")
	for lane in 4:
		_check(NoteColors.color_for(lane, false, false, m, 4) == m, "auto 3D Note unveraendert %d" % lane)
		_check(NoteColors.color_for(lane, true, true, m, 2) == m, "auto 2D Hold unveraendert %d" % lane)


func _test_lanes() -> void:
	NoteColors.set_mode(false, "lanes")
	NoteColors.set_lane_color(false, 1, Color("ff0000"))
	var c := NoteColors.color_for(1, false, false, Color.BLACK)
	_check(c.r > 0.9 and c.g < 0.1, "lanes: Spalte 1 rot")
	var h := NoteColors.color_for(1, true, false, Color.BLACK)
	_check(h.v < c.v and absf(h.h - c.h) < 0.02, "lanes: Hold automatisch dunkler, gleicher Farbton")
	NoteColors.set_hold_color(false, 1, Color("00ff00"))
	_check(NoteColors.color_for(1, true, false, Color.BLACK).g > 0.9, "lanes: eigene Hold-Farbe")
	_check(not NoteColors.hold_auto(false), "eigene Hold-Farbe schaltet hold_auto aus")
	NoteColors.set_lane_color(false, 0, Color("000000"))
	_check(NoteColors.lane_color(false, 0).v >= NoteColors.MIN_V - 0.001, "zu dunkel wird angehoben")
	NoteColors.set_lane_color(false, 0, Color("ffffff"))
	_check(NoteColors.lane_color(false, 0).v <= NoteColors.MAX_V + 0.001, "Weiss nicht grell")
	_check(NoteColors.color_for(5, false, false, Color.BLACK) == NoteColors.lane_color(false, 1), "Spalte 5 -> 1 (mod 4)")
	# 2D getrennt von 3D, bis verknuepft.
	_check(NoteColors.mode(true) == "auto", "2D bleibt auto, wenn nur 3D geaendert")
	NoteColors.set_link_2d(true)
	_check(NoteColors.mode(true) == "lanes", "2D wie 3D -> gleicher Satz")
	NoteColors.set_link_2d(false)


func _test_snap() -> void:
	NoteColors.set_mode(true, "snap")
	var c1 := NoteColors.color_for(0, false, true, Color.BLACK, 1)
	var c2 := NoteColors.color_for(0, false, true, Color.BLACK, 2)
	var c4 := NoteColors.color_for(0, false, true, Color.BLACK, 4)
	_check(c1.r > c1.b, "snap 1/1 rot")
	_check(c2.b > c2.r, "snap 1/2 blau")
	_check(c4.r > 0.8 and c4.g > 0.7 and c4.b < 0.4, "snap 1/4 gelb")
	_check(NoteColors.color_for(0, false, true, Color.BLACK, 99) == NoteColors.snap_color(16), "unbekannter Teiler = 1/16")
	_check(NoteColors.color_for(0, false, true, Color.RED, 0) == Color.RED, "snap ohne Teiler = map_color")
	_check(NoteColors.color_for(0, true, true, Color.BLACK, 1).v < c1.v, "snap Hold dunkler")
	NoteColors.set_mode(true, "auto")


func _test_presets() -> void:
	for id in NoteColors.PRESET_IDS:
		_check(NoteColors.PRESETS.has(id) and NoteColors.PRESET_NAMES.has(id), "Vorlage %s vollstaendig" % id)
		var cols: Array = NoteColors.preset_colors(id)
		_check(cols.size() == 4, "Vorlage %s hat 4 Farben" % id)
		for c in cols:
			var lum: float = c.get_luminance()
			_check(lum > 0.25 and c.v <= 0.96, "Vorlage %s lesbar (Luma %.2f V %.2f)" % [id, lum, c.v])
	NoteColors.set_mode(false, "auto")
	NoteColors.apply_preset(false, "classic")
	_check(NoteColors.mode(false) == "lanes", "Vorlage schaltet auto -> lanes")
	_check(NoteColors.lane_color(false, 0).s < 0.1 and NoteColors.lane_color(false, 1).b > 0.9, "Klassisch: weiss/blau/blau/weiss")
	_check(NoteColors.lane_color(false, 3) == NoteColors.lane_color(false, 0), "Klassisch: Spalte 4 = Spalte 1")
	_check(NoteColors.preset(false) == "classic" and NoteColors.hold_auto(false), "Vorlage merkt sich Namen, Holds auto")
	# Hold-Farbe jeder Vorlage ist dunkler als die Note, aber nicht unlesbar.
	for id in NoteColors.PRESET_IDS:
		NoteColors.apply_preset(false, id)
		for i in 4:
			var hv := NoteColors.hold_color(false, i).v
			_check(hv < NoteColors.lane_color(false, i).v and hv > 0.4, "Vorlage %s Hold %d dunkler, lesbar" % [id, i])


func _test_reset_snapshot() -> void:
	NoteColors.set_link_2d(false)
	NoteColors.apply_preset(false, "neon")
	var snap := NoteColors.snapshot(false)
	NoteColors.set_lane_color(false, 0, Color("3366ff"))
	_check(NoteColors.lane_color(false, 0) != NoteColors.preset_colors("neon")[0], "Spalte geaendert")
	NoteColors.restore(false, snap)
	_check(NoteColors.lane_color(false, 0).is_equal_approx(NoteColors.preset_colors("neon")[0]), "restore stellt Spalte wieder her")
	_check(NoteColors.mode(false) == "lanes" and NoteColors.preset(false) == "neon", "restore stellt Modus und Vorlage wieder her")
	NoteColors.restore(false, {})
	_check(NoteColors.mode(false) == "lanes", "restore mit leerem Satz ignoriert")
	# Snapshot ist eine Kopie, kein Verweis.
	snap["lanes"] = []
	_check(NoteColors.lane_color(false, 0).s > 0.0, "Snapshot ist unabhaengige Kopie")
	# apply_preset aus Snapshot-Zustand schaltet immer auf lanes.
	NoteColors.set_mode(false, "snap")
	NoteColors.apply_preset(false, "pastel")
	_check(NoteColors.mode(false) == "lanes", "Vorlage aus Takt-Modus -> lanes")
	NoteColors.set_lane_color(false, 1, Color("ff0000"))
	NoteColors.reset(false)
	_check(NoteColors.mode(false) == "auto" and NoteColors.hold_auto(false), "reset: auto, Holds automatisch")
	_check(NoteColors.preset(false) != "custom", "reset: Vorlage nicht custom")
	# clamp ist idempotent.
	for c in [Color("000000"), Color("ffffff"), Color("3366ff"), Color("ff00ff"), Color("101010")]:
		var a := NoteColors.clamp_color(c)
		_check(NoteColors.clamp_color(a) == a, "clamp idempotent %s" % c.to_html(false))


func _test_recent() -> void:
	for i in 12:
		NoteColors.push_recent(Color.from_hsv(i / 12.0, 0.8, 0.8))
	var r := NoteColors.recent()
	_check(r.size() == NoteColors.RECENT_MAX, "recent: hoechstens %d" % NoteColors.RECENT_MAX)
	_check((r[0] as Color).to_html(false) == Color.from_hsv(11 / 12.0, 0.8, 0.8).to_html(false), "recent: neueste zuerst")
	NoteColors.push_recent(Color.from_hsv(9 / 12.0, 0.8, 0.8))
	r = NoteColors.recent()
	_check(r.size() == NoteColors.RECENT_MAX and (r[0] as Color).to_html(false) == Color.from_hsv(9 / 12.0, 0.8, 0.8).to_html(false), "recent: Duplikat rueckt nach vorn, keine Doppelten")
	var seen := {}
	for c in r:
		seen[(c as Color).to_html(false)] = true
	_check(seen.size() == r.size(), "recent: alle verschieden")
	NoteColors.save()
	var before := NoteColors.recent()
	NoteColors.reload()
	var after := NoteColors.recent()
	var same := after.size() == before.size()
	for i in mini(before.size(), after.size()):
		same = same and (before[i] as Color).to_html(false) == (after[i] as Color).to_html(false)
	_check(same, "recent gespeichert und geladen")


func _test_save_load() -> void:
	NoteColors.apply_preset(false, "neon")
	NoteColors.set_lane_color(false, 2, Color("3366ff"))
	NoteColors.set_mode(false, "lanes")
	NoteColors.set_mode(true, "snap")
	NoteColors.set_link_2d(false)
	NoteColors.save()
	var want := NoteColors.lane_color(false, 2)
	NoteColors.reload()
	_check(NoteColors.mode(false) == "lanes" and NoteColors.mode(true) == "snap", "Modi geladen")
	_check(NoteColors.lane_color(false, 2).is_equal_approx(want), "Spaltenfarbe geladen")
	_check(NoteColors.lane_color(false, 0).is_equal_approx(NoteColors.preset_colors("neon")[0]), "Vorlagenfarbe geladen")
	_check(NoteColors.preset(false) == "custom", "Preset custom nach Aenderung geladen")
	DirAccess.remove_absolute(NoteColors.path)
	NoteColors.reload()
	_check(NoteColors.mode(false) == "auto" and not NoteColors.link_2d(), "ohne Datei: Standard auto")
