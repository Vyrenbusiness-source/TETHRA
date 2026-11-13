extends SceneTree

## Tests fuer Bot-Nachrichten im Chat ("TETHRA Bot"): Markdown -> BBCode/Klartext,
## Map-Links des Bots (/tethra/songs?...&set=, /omen/songs?..., /tethra/map/<md5>?set=,
## relativ oder mit Host) als Karten-Info, leere "Filters:"-Zeilen, Emoji, Diff-Wahl.
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_chat_markdown_tests.gd

const BOT := "**Found a map for you!**\n\n" \
	+ "[End Time by Cres](/tethra/songs?detail=cres_end_time&difficulty=hyper&set=1766740)\n" \
	+ "**[4K] Hyper** — 3.39★ | 8.1 NPS | Rice | 2:08\n" \
	+ "🎯 🎹\n" \
	+ "Filters:\n"

var _passed := 0
var _failed := 0


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)


func _initialize() -> void:
	print("=== OMEN Chat-Markdown / Bot-Links ===")
	_links()
	_text()
	_markdown()
	_diff()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _links() -> void:
	var p := ChatApi.parse_content(BOT)
	var maps: Array = p.maps
	_ok(maps.size() == 1, "Bot-Nachricht: eine Karte (%d)" % maps.size())
	var m: Dictionary = maps[0] if maps.size() > 0 else {}
	_ok(int(m.get("set_id", 0)) == 1766740, "set-ID aus set=")
	_ok(str(m.get("title", "")) == "End Time" and str(m.get("artist", "")) == "Cres",
		"Titel/Kuenstler aus dem Linktext ('%s' / '%s')" % [m.get("title", ""), m.get("artist", "")])
	_ok(str(m.get("difficulty", "")) == "hyper", "Diff aus difficulty=")
	_ok(str(m.get("version", "")) == "[4K] Hyper", "Diff-Name aus der Folgezeile ('%s')" % m.get("version", ""))
	_ok(is_equal_approx(float(m.get("stars", 0.0)), 3.39), "Sterne aus der Folgezeile")
	_ok(not ChatApi.parse_map_link(BOT).is_empty(), "parse_map_link kennt den Bot-Link")

	var old := ChatApi.parse_content("[Freedom Dive by xi](/omen/songs?detail=xi_fd&difficulty=4k_another&set=39804)")
	_ok(old.maps.size() == 1 and int(old.maps[0].set_id) == 39804, "alter /omen/songs-Pfad")
	_ok(str(old.maps[0].version) == "4k another", "ohne Folgezeile: Diff lesbar aus dem Slug ('%s')" % old.maps[0].version)
	_ok(str(old.text) == "", "Link-Zeile verschwindet aus dem Text")

	var abs_l := ChatApi.parse_content("look https://butzebot.com/tethra/songs?detail=a_b&difficulty=hard&set=12 nice")
	_ok(abs_l.maps.size() == 1 and int(abs_l.maps[0].set_id) == 12, "songs-Link mit Host, ohne Markdown")
	_ok(str(abs_l.text) == "look nice", "Resttext ohne Link ('%s')" % abs_l.text)
	_ok(str(abs_l.maps[0].title) == "A B", "Titel notfalls aus detail ('%s')" % abs_l.maps[0].title)

	var rel := ChatApi.parse_content("[x](/tethra/map/0123abcd?set=7&b=9&t=Hallo%20Welt&v=Hard&s=2.50)")
	_ok(rel.maps.size() == 1 and str(rel.maps[0].md5) == "0123abcd" and int(rel.maps[0].beatmap_id) == 9,
		"relativer /tethra/map/<md5>-Link")
	_ok(str(rel.maps[0].title) == "Hallo Welt" and str(rel.maps[0].version) == "Hard", "t= und v= gewinnen")

	var meta := {"md5": "abc", "set_id": 5, "beatmap_id": 6, "title": "T", "artist": "A", "version": "V", "stars": 1.5}
	var pl := ChatApi.parse_map_link("Schau mal " + ChatApi.map_link(meta) + " gut?")
	_ok(int(pl.get("set_id", 0)) == 5 and str(pl.get("text", "")) == "Schau mal  gut?", "Spieler-Link unveraendert")
	_ok(str(pl.get("link", "")) == ChatApi.map_link(meta), "link = Original-URL")

	_ok(ChatApi.parse_content("/tethra/songs?detail=a&difficulty=b").maps.is_empty(), "ohne set -> keine Karte")
	_ok(ChatApi.parse_content("https://evil.example/tethra/songs?set=4").maps.is_empty(), "fremder Host -> keine Karte")
	var two := ChatApi.parse_content("[A by B](/tethra/songs?detail=a&difficulty=x&set=1)\n[C by D](/tethra/songs?detail=c&difficulty=y&set=2)")
	_ok(two.maps.size() == 2 and str(two.maps[1].title) == "C", "zwei Links -> zwei Karten")
	_ok(ChatApi.absolute_url("/tethra/songs?x=1") == "https://butzebot.com/tethra/songs?x=1", "relativ -> absolut")
	_ok(ChatApi.absolute_url("https://example.com/a") == "https://example.com/a", "absolut bleibt")
	_ok(ChatApi.absolute_url("javascript:alert(1)") == "" and ChatApi.absolute_url("file:///c:/x") == "", "nur http(s)")


func _text() -> void:
	var t := str(ChatApi.parse_content(BOT).text)
	_ok(not t.contains("Filters"), "leere Filters:-Zeile weg")
	_ok(not t.contains("🎯") and not t.contains("🎹"), "Emoji weg")
	_ok(t.contains("3.39★"), "★ bleibt")
	_ok(not t.contains("songs?"), "roher Link weg")
	_ok(t == "**Found a map for you!**\n\n**[4K] Hyper** — 3.39★ | 8.1 NPS | Rice | 2:08", "Resttext sauber: '%s'" % t.c_escape())
	_ok(ChatApi.tidy_text("a\n**Filters:**\nb") == "a\nb", "fette leere Filters-Zeile weg")
	_ok(ChatApi.tidy_text("🔎 Filter: \nb") == "b", "Emoji + leere Filter-Zeile weg")
	_ok(ChatApi.tidy_text("Filters: 4K, Rice") == "Filters: 4K, Rice", "Filters mit Inhalt bleibt")
	_ok(ChatApi.tidy_text("**Filters:** 4K") == "**Filters:** 4K", "fettes Filters mit Inhalt bleibt")
	_ok(str(ChatApi.parse_content("Older:\n[A by B](/tethra/songs?set=1)\nx").text) == "Older:\nx",
		"Link-Zeile hinterlaesst keine Leerzeile")
	_ok(ChatApi.tidy_text("a\n\n\n\nb") =="a\n\nb", "Leerzeilen zusammengefasst")
	_ok(ChatApi.tidy_text("🎵 Song ⭐ 4") == "Song ★ 4", "Emoji mitten im Text, Stern-Emoji -> ★ ('%s')" % ChatApi.tidy_text("🎵 Song ⭐ 4"))
	_ok(ChatApi.tidy_text("gg 👍🏽") == "gg", "Hautton-Emoji ohne Rest")
	_ok(ChatApi.tidy_text("hallo ♪ ✓") == "hallo ♪ ✓", "Symbole der Schrift bleiben")


func _markdown() -> void:
	_ok(ChatApi.md_to_bbcode("plain") == "plain", "ohne Markdown unveraendert")
	_ok(ChatApi.md_to_bbcode("**fett** x") == "[b]fett[/b] x", "fett")
	_ok(ChatApi.md_to_bbcode("**[4K] Hyper**") == "[b][lb]4K] Hyper[/b]", "eckige Klammer maskiert ('%s')" % ChatApi.md_to_bbcode("**[4K] Hyper**"))
	_ok(ChatApi.md_to_bbcode("[b]x[/b]") == "[lb]b]x[lb]/b]", "fremdes BBCode wirkt nicht")
	var l := ChatApi.md_to_bbcode("[Seite](/tethra/users/3)")
	_ok(l.contains("[url=https://butzebot.com/tethra/users/3]Seite[/url]"), "Markdown-Link klickbar ('%s')" % l)
	var u := ChatApi.md_to_bbcode("siehe https://example.com/a?b=1.")
	_ok(u.contains("[url=https://example.com/a?b=1]https://example.com/a?b=1[/url]") and u.ends_with("."),
		"nackte URL klickbar, Satzpunkt draussen ('%s')" % u)
	_ok(not ChatApi.md_to_bbcode("[x](javascript:alert(1))").contains("[url"), "kein javascript-Link")
	_ok(ChatApi.md_to_bbcode("*kursiv*") == "[i]kursiv[/i]", "kursiv")
	_ok(ChatApi.md_to_bbcode("2 * 3 * 4") == "2 * 3 * 4", "Malzeichen bleibt")
	_ok(ChatApi.md_to_bbcode("# Titel\n- eins\n- zwei") == "[b]Titel[/b]\n• eins\n• zwei",
		"Ueberschrift + Liste ('%s')" % ChatApi.md_to_bbcode("# Titel\n- eins\n- zwei").c_escape())
	_ok(ChatApi.md_to_bbcode("`code`") == "code", "Code-Zeichen weg")
	_ok(ChatApi.md_to_plain("**Found** [a](/x) `b`") == "Found a b", "Klartext fuer die Liste ('%s')" % ChatApi.md_to_plain("**Found** [a](/x) `b`"))
	_ok(ChatApi.preview_plain("**Hi** there\nmore") == "Hi there more", "Listen-Vorschau als Klartext")
	_ok(ChatApi.preview_plain(BOT) == "♪ End Time", "Vorschau Bot-Nachricht = Karte")
	_ok(ChatApi.preview_plain("[End Time by Cres](/tethra/songs?detail=x&difficulty=h&set=3)") == "♪ End Time", "Vorschau nur Karte")


func _diff() -> void:
	var names := ["[4K] Easy", "[4K] Hyper", "[7K] Hyper", "Another"]
	_ok(ChatApi.pick_diff(names, "[4K] Hyper", "hyper") == 1, "Diff nach Name")
	_ok(ChatApi.pick_diff(names, "", "another") == 3, "Diff nach Slug")
	_ok(ChatApi.pick_diff(names, "", "4k_hyper") == 1, "Slug mit Tastenzahl")
	_ok(ChatApi.pick_diff(names, "", "hyper") == 1, "Slug als Teil -> erster Treffer")
	_ok(ChatApi.pick_diff(names, "", "gibtsnicht") == 0, "unbekannt -> erste")
	_ok(ChatApi.pick_diff(names, "", "") == 0, "leer -> erste")
