extends SceneTree

## Headless-Tests fuer den Multiplayer-Map-Picker (scripts/ui/map_picker.gd):
## Filter, Sortierung, Zuordnung der eigenen Bestwerte, BPM/Tags-Parser.

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _mk(file: String, artist: String, title: String, creator: String, diffs: Array) -> MapSet:
	return MapSet.from_dict("C:/maps/" + file, {
		"title": title, "artist": artist, "creator": creator, "diffs": diffs,
	})


func _d(version: String, stars: float, mode: int = 3, dur: float = 120000.0) -> Dictionary:
	return { "version": version, "stars": stars, "mode": mode, "duration_ms": dur,
		"osu_filename": version + ".osu" }


func _titles(arr: Array) -> Array:
	var out := []
	for e in arr:
		out.append((e.ms as MapSet).title)
	return out


func _init() -> void:
	var sets := [
		_mk("1 a.osz", "Camellia", "Ghost", "Mapper1", [_d("Easy", 1.5), _d("Hard", 4.2, 3, 200000.0)]),
		_mk("2 b.osz", "Akira", "Blue Sky", "Zelda", [_d("Normal", 2.5)]),
		_mk("3 c.osz", "Nobody", "Std Only", "X", [_d("Std", 3.0, 0)]),
		_mk("4 d.osz", "Zeta", "Apex", "Mapper1", [_d("Insane", 6.4, 3, 90000.0), _d("Std", 2.0, 0, 90000.0)]),
	]
	var scores := {
		"best": {
			"1 a.osz|Hard": { "score": 912345, "accuracy": 0.9712, "grade": "S", "date": "2026-11-01T10:00:00",
				"mods": ["SV"] },
			"1 a.osz|Easy": { "score": 999000, "accuracy": 1.0, "grade": "SS", "date": "2026-10-01T10:00:00" },
			"4 d.osz|Insane": { "score": 700000, "accuracy": 0.88, "grade": "B", "date": "2026-11-05T10:00:00",
				"unranked": true },
		},
		"last": {
			"1 a.osz|Hard": "2026-11-01T10:00:00",
			"1 a.osz|Easy": "2026-10-01T10:00:00",
			"4 d.osz|Insane": "2026-11-05T10:00:00",
		},
	}
	var extra := {
		"1 a.osz": { "bpm": 180.0, "tags": "dubstep hardcore" },
		"2 b.osz": { "bpm": 128.0, "tags": "anime" },
		"4 d.osz": { "bpm": 200.0, "tags": "" },
	}
	var entries := MapPicker.build_entries(sets, scores, extra)

	# Nur 4K-Mania
	_check(entries.size() == 3, "Std-only-Set faellt raus (%d)" % entries.size())
	var apex: Dictionary = entries[2]
	_check(apex.diffs.size() == 1 and apex.diffs[0].version == "Insane", "nur Mania-Diffs im Set")
	_check(apex.diffs[0].idx == 0, "Diff-Index zeigt auf MapSet-Diff")

	# Score-Zuordnung
	var ghost: Dictionary = entries[0]
	_check(int(ghost.diffs[1].best.get("score", 0)) == 912345, "Bestwert je Diff (Hard)")
	_check(str(ghost.diffs[0].best.get("grade", "")) == "SS", "Bestwert je Diff (Easy)")
	_check(ghost.grade == "SS", "Set-Badge = bester Rang")
	_check((entries[1].diffs[0].best as Dictionary).is_empty(), "ohne Score: leer")
	_check(entries[1].grade == "", "ohne Score: kein Badge")
	_check(ghost.last == "2026-11-01T10:00:00", "zuletzt gespielt = neueste Diff")
	_check(MapPicker.mods_badge(ghost.diffs[1].best) == "SV", "Mods-Badge aus Liste")
	_check(MapPicker.mods_badge(apex.diffs[0].best) == "UR", "Unranked-Badge")
	_check(MapPicker.mods_badge({ "mods": { "NF": true, "SV": false } }) == "NF", "Mods aus Dictionary")
	_check(MapPicker.better_grade("A", "S") == "S" and MapPicker.better_grade("", "D") == "D"
		and MapPicker.better_grade("SS", "") == "SS", "Rang-Vergleich")
	var sc := MapPicker.load_scores("user://gibt_es_nicht.cfg")
	_check((sc.best as Dictionary).is_empty(), "fehlende scores.cfg: leer")

	# Filter
	_check(MapPicker.filter_entries(entries, "", 0).size() == 3, "leere Suche: alles")
	_check(_titles(MapPicker.filter_entries(entries, "camellia", 0)) == ["Ghost"], "Suche Artist")
	_check(_titles(MapPicker.filter_entries(entries, "SKY", 0)) == ["Blue Sky"], "Suche Titel, Grossschreibung egal")
	_check(_titles(MapPicker.filter_entries(entries, "mapper1", 0)) == ["Ghost", "Apex"], "Suche Mapper")
	_check(_titles(MapPicker.filter_entries(entries, "anime", 0)) == ["Blue Sky"], "Suche Tags")
	_check(_titles(MapPicker.filter_entries(entries, "mapper1 dubstep", 0)) == ["Ghost"], "mehrere Woerter = UND")
	_check(MapPicker.filter_entries(entries, "  ", 0).size() == 3, "nur Leerzeichen: alles")
	_check(_titles(MapPicker.filter_entries(entries, "", 1)) == ["Ghost"], "Sterne <2: irgendeine Diff")
	_check(_titles(MapPicker.filter_entries(entries, "", 2)) == ["Blue Sky"], "Sterne 2-4 (4,2 liegt drueber)")
	_check(_titles(MapPicker.filter_entries(entries, "", 4)) == ["Apex"], "Sterne 6+ (Std-Diff zaehlt nicht)")
	_check(MapPicker.filter_entries(entries, "ghost", 4).is_empty(), "Suche + Sterne kombiniert")
	var coll := ["1 a.osz", "4 d.osz"]
	_check(_titles(MapPicker.filter_entries(entries, "", 0, coll)) == ["Ghost", "Apex"], "Sammlung: nur ihre Sets")
	_check(MapPicker.filter_entries(entries, "", 0, []).is_empty(), "leere Sammlung: nichts")
	_check(MapPicker.filter_entries(entries, "", 0, null).size() == 3, "keine Sammlung: alles")
	_check(_titles(MapPicker.filter_entries(entries, "mapper1", 4, coll)) == ["Apex"], "Sammlung + Suche + Sterne")
	_check(MapPicker.filter_entries(entries, "anime", 0, coll).is_empty(), "Sammlung + Suche ohne Treffer")

	# Sortierung
	var arr := entries.duplicate()
	MapPicker.sort_entries(arr, MapPicker.Sort.TITLE, false)
	_check(_titles(arr) == ["Apex", "Blue Sky", "Ghost"], "Titel A-Z")
	MapPicker.sort_entries(arr, MapPicker.Sort.TITLE, true)
	_check(_titles(arr) == ["Ghost", "Blue Sky", "Apex"], "Titel Z-A")
	MapPicker.sort_entries(arr, MapPicker.Sort.ARTIST, false)
	_check(_titles(arr) == ["Blue Sky", "Ghost", "Apex"], "Artist A-Z")
	MapPicker.sort_entries(arr, MapPicker.Sort.STARS, true)
	_check(_titles(arr) == ["Apex", "Ghost", "Blue Sky"], "Sterne hoch zuerst")
	MapPicker.sort_entries(arr, MapPicker.Sort.BPM, true)
	_check(_titles(arr) == ["Apex", "Ghost", "Blue Sky"], "BPM hoch zuerst")
	MapPicker.sort_entries(arr, MapPicker.Sort.LENGTH, true)
	_check(_titles(arr) == ["Ghost", "Blue Sky", "Apex"], "Laenge lang zuerst")
	MapPicker.sort_entries(arr, MapPicker.Sort.RECENT, true)
	_check(_titles(arr) == ["Apex", "Ghost", "Blue Sky"], "zuletzt gespielt zuerst, nie gespielt am Ende")
	MapPicker.sort_entries(arr, MapPicker.Sort.LENGTH, false)
	_check(_titles(arr) == ["Apex", "Blue Sky", "Ghost"], "Laenge kurz zuerst")

	# BPM/Tags-Parser
	var osu := "osu file format v14\n[Metadata]\nTitle:X\nTags:  jump stream  \n\n[TimingPoints]\n" \
		+ "0,500,4,1,0,100,1,0\n1000,-50,4,1,0,100,0,0\n10000,300,4,1,0,100,1,0\n\n[HitObjects]\n64,192,500,1,0\n"
	var ex := MapPicker.parse_extra(osu, 120000.0)
	_check(str(ex.tags) == "jump stream", "Tags gelesen")
	_check(is_equal_approx(float(ex.bpm), 200.0), "dominante BPM = laengste rote Linie (%s)" % str(ex.bpm))
	var ex2 := MapPicker.parse_extra("[TimingPoints]\n0,333.33,4,1,0,100,1,0\n", 60000.0)
	_check(is_equal_approx(float(ex2.bpm), 180.0), "BPM gerundet auf 0,1 (%s)" % str(ex2.bpm))
	_check(float(MapPicker.parse_extra("", 0.0).bpm) == 0.0, "leere Datei: 0 BPM")

	# Grosse Bibliothek: Filtern + Sortieren schnell genug fuer jede Taste.
	var many: Array = []
	for i in 2000:
		many.append(_mk("%d m.osz" % i, "Artist %d" % (i % 97), "Song %d" % i, "Mapper %d" % (i % 13),
			[_d("A", float(i % 70) / 10.0), _d("B", float(i % 50) / 8.0)]))
	var big := MapPicker.build_entries(many, scores, {})
	var t0 := Time.get_ticks_usec()
	var res := MapPicker.filter_entries(big, "artist 1", 2)
	MapPicker.sort_entries(res, MapPicker.Sort.STARS, true)
	var ms_used := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  info filter+sort 2000 Sets: %.1f ms (%d Treffer)" % [ms_used, res.size()])
	_check(ms_used < 40.0, "Filter+Sortierung 2000 Sets < 40 ms")

	if _failed == 0:
		print("MAP-PICKER-TESTS OK")
	else:
		print("MAP-PICKER-TESTS FAILED: %d" % _failed)
	quit(0 if _failed == 0 else 1)
