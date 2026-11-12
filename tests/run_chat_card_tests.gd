extends SceneTree

## Tests fuer die Score-Karte im Chat (ChatMapCard "score"): Titel/Kuenstler/Diff,
## Genauigkeit 0..1 vs. Prozent, pp nur Mania (sonst Punkte), Knoepfe je nach lokaler Map,
## Layout (gleiche Hoehe wie die Map-Karte, nichts ragt heraus) fuer alle 6 Modi.
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_chat_card_tests.gd

const MODES := ["mania", "orbit", "rally", "dirigent", "trace", "rebound"]
const CARD_W := 340.0

var _passed := 0
var _failed := 0


## Ersatz fuer das ChatOverlay: nur was die Karte abfragt.
class StubOverlay extends Node:
	signal state_changed
	var owned := false
	var dl := -1.0
	var card_notes: Dictionary = {}
	var preview_set := -1
	var calls: Array = []

	func is_owned(_set_id: int) -> bool:
		return owned

	func download_ratio(_set_id: int) -> float:
		return dl

	func local_set(_info: Dictionary) -> MapSet:
		if not owned:
			return null
		var ms := MapSet.new()
		ms.title = "Local"
		return ms

	func play_map(_info: Dictionary) -> void:
		calls.append("play")

	func download_set(_set_id: int) -> void:
		calls.append("download")

	func watch_score_replay(_sid: String, _info: Dictionary) -> void:
		calls.append("replay")


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)


func _initialize() -> void:
	print("=== TETHRA Chat-Score-Karte ===")
	_parse()
	_texts()
	_buttons()
	await _layout()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Antwort wie GET /score/:id vom Server (flach, accuracy 0..1, pp null ausser Mania).
func _server_json(mode: String, set_id: int = 2493125) -> String:
	var mania := mode == "mania"
	return JSON.stringify({"score_id": 1753, "id": 1753, "mode": mode,
		"beatmap_md5": "595c5fc1d6d431fd9977a70760062541", "beatmap_id": 5478106,
		"beatmapset_id": set_id, "player": "Gexanx", "player_id": 2, "artist": "d0tc0mmie",
		"title": "I Can't Wait feat. GUMI", "difficulty": "beginner", "difficulty_name": "Beginner",
		"score": 973268, "accuracy": 0.9912, "grade": "S", "max_combo": 420,
		"pp": 312.4 if mania else null, "orbit_points": null if mania else 2.062,
		"points": null if mania else 2.062, "mods": [], "stars": 0.97, "has_replay": mania})


## Lokaler Score (z.B. aus dem Cache): accuracy schon in Prozent, Feld "version".
func _local_info(mode: String) -> Dictionary:
	return {"player": "Mira", "set_id": 1060425, "md5": "", "title": "Ending Theme",
		"artist": "Nanatsu no Taizai", "difficulty": "4K Hard", "score": 1234567,
		"accuracy": 97.42, "grade": "A", "max_combo": 512, "pp": 188.4 if mode == "mania" else 0.0,
		"points": 0.0 if mode == "mania" else 14.25, "mods": ["NF"], "mode": mode, "has_replay": true}


func _parse() -> void:
	var s := ChatApi.parse_score(_server_json("trace"))
	_ok(s.title == "I Can't Wait feat. GUMI" and s.artist == "d0tc0mmie", "flache Server-Antwort: Titel/Kuenstler")
	_ok(s.difficulty == "Beginner", "Diff aus difficulty_name")
	_ok(s.set_id == 2493125 and s.md5 == "595c5fc1d6d431fd9977a70760062541", "Set-ID und md5 flach gelesen")
	_ok(absf(float(s.accuracy) - 99.12) < 0.001, "accuracy 0..1 -> Prozent")
	_ok(absf(float(s.points) - 2.062) < 0.001 and s.mode == "trace", "points fuer Trace, pp null -> 0")
	_ok(not s.has_replay, "has_replay false")
	var m := ChatApi.parse_score(_server_json("mania"))
	_ok(absf(float(m.pp) - 312.4) < 0.001 and m.has_replay, "Mania: pp + Replay")
	var old := ChatApi.parse_score(JSON.stringify({"player": "Mira", "map": {"beatmap_md5": "m",
		"beatmapset_id": 5, "title": "T", "artist": "A", "difficulty": "D"}, "accuracy": 98.5}))
	_ok(old.title == "T" and old.artist == "A" and old.set_id == 5 and absf(old.accuracy - 98.5) < 0.001,
		"alte Form mit map{} und Prozent bleibt")
	_ok(ChatApi.parse_score("{}").is_empty() and ChatApi.parse_score("x").is_empty(), "leer/kaputt -> {}")
	_ok(absf(ChatApi.acc_percent(1.0) - 100.0) < 0.001 and absf(ChatApi.acc_percent(85.0) - 85.0) < 0.001,
		"acc_percent: 1,0 = 100 %, 85 bleibt")


func _texts() -> void:
	for mode in MODES:
		var online := ChatMapCard.score_texts(ChatApi.parse_score(_server_json(mode)))
		_ok(online.title == "I Can't Wait feat. GUMI" and online.sub.contains("d0tc0mmie")
			and online.sub.contains("Beginner"), "%s online: Titel, Kuenstler, Diff" % mode)
		_ok(online.stats.begins_with(UiTheme.fmt_pct(99.12)), "%s online: Acc %s" % [mode, UiTheme.fmt_pct(99.12)])
		_ok(online.who.contains("Gexanx") and online.who.contains(UiTheme.fmt_score(973268)), "%s online: Spieler + Score" % mode)
		_ok(online.stats.contains("420x"), "%s online: Combo" % mode)
		if mode == "mania":
			_ok(online.stats.contains(UiTheme.fmt_pp(312.4)) and not online.stats.contains(tr("Pkt.")),
				"mania: pp vollstaendig")
		else:
			_ok(online.stats.contains(UiTheme.fmt_num(2.062, 1) + " " + tr("Pkt.")) and not online.stats.contains("pp"),
				"%s: Punkte statt pp" % mode)
		_ok(online.grade == "S" and online.mode == mode, "%s: Rang + Modus" % mode)
		var local := ChatMapCard.score_texts(_local_info(mode))
		_ok(local.title == "Ending Theme" and local.sub == "Nanatsu no Taizai  ·  4K Hard",
			"%s lokal: Titel/Sub" % mode)
		_ok(local.stats.begins_with(UiTheme.fmt_pct(97.42)), "%s lokal: Acc in Prozent bleibt" % mode)
		_ok(local.who.ends_with("+NF"), "%s lokal: Mods" % mode)
	var empty := ChatMapCard.score_texts({"player": "X", "score": 5, "accuracy": 0.5, "mode": "orbit"})
	_ok(empty.title == tr("Unbekannte Map") and empty.sub == "" and not empty.title.contains("[]"),
		"ohne Map-Daten: Unknown map statt '– []'")
	_ok(ChatMapCard.rating_text({"mode": "mania", "pp": 0.0}) == "", "Mania ohne pp: nichts")
	_ok(ChatMapCard.rating_text({"mode": "rally", "points": 0.0}) == "", "Rally ohne Punkte: nichts")


func _buttons() -> void:
	var withr := {"set_id": 7, "has_replay": true}
	var b := ChatMapCard.score_buttons(withr, true, -1.0)
	_ok(b.replay and b.replay_enabled and b.action == "play", "Map da: Replay + Spielen")
	b = ChatMapCard.score_buttons(withr, false, -1.0)
	_ok(b.replay and not b.replay_enabled and b.action == "download", "Map fehlt: Map herunterladen, Replay gesperrt")
	b = ChatMapCard.score_buttons(withr, false, 0.4)
	_ok(b.action == "loading", "Download laeuft: Laedt")
	b = ChatMapCard.score_buttons({"set_id": 0, "has_replay": false}, false, -1.0)
	_ok(not b.replay and b.action == "", "ohne Set-ID und ohne Replay: keine Knoepfe")


func _make(kind: String, inf: Dictionary, ov: StubOverlay, sid: String = "") -> ChatMapCard:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(CARD_W, 0)
	box.size = Vector2(CARD_W, 0)
	root.add_child(box)
	var c := ChatMapCard.new()
	box.add_child(c)
	c.setup(kind, inf, ov, sid)
	return c


func _layout() -> void:
	TranslationServer.set_locale("en")
	var ov := StubOverlay.new()
	root.add_child(ov)
	var map_card := _make("map", {"set_id": 1060425, "title": "Ending Theme", "artist": "Nanatsu no Taizai",
		"version": "4K Hard", "stars": 3.84}, ov)
	var cards: Array = []
	for mode in MODES:
		for owned in [true, false]:
			var o2 := StubOverlay.new()
			o2.owned = owned
			root.add_child(o2)
			var info := ChatApi.parse_score(_server_json(mode)) if owned else _local_info(mode)
			cards.append([mode, owned, _make("score", info, o2, "s-" + mode), o2])
	await process_frame
	await process_frame
	await process_frame
	var mh := map_card.size.y
	for e in cards:
		var mode: String = e[0]
		var owned: bool = e[1]
		var c: ChatMapCard = e[2]
		var tag := "%s %s" % [mode, "Map da" if owned else "Map fehlt"]
		_ok(absf(c.size.y - mh) < 0.5, "%s: gleiche Hoehe wie Map-Karte (%.0f / %.0f)" % [tag, c.size.y, mh])
		_ok(c.size.x <= CARD_W + 0.5, "%s: Karte nicht breiter als Platz (%.0f)" % [tag, c.size.x])
		_ok(not c._title.text.contains("[]") and c._title.text != "", "%s: Titel gesetzt" % tag)
		var font := c._extra.get_theme_font("font")
		var need := font.get_string_size(c._extra.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_ok(need <= c._extra.size.x + 0.5 and not c._extra.clip_text, "%s: Werte ganz sichtbar" % tag)
		need = font.get_string_size(c._who.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_ok(need <= c._who.size.x + 0.5, "%s: Spielerzeile ganz sichtbar" % tag)
		var col_r: float = c._extra.get_global_rect().end.x
		_ok(col_r <= c._side.get_global_rect().position.x + 0.5, "%s: Werte ueberlappen den Rang nicht" % tag)
		_ok(c._grade.text != "" and c._side.visible and c._badge_slot.get_child_count() == 1, "%s: Rang + Modus-Symbol" % tag)
		var rep := bool(c.info.get("has_replay", false))
		_ok(c._btn_a.visible == rep and c._btn_a.text == c.tr("Replay ansehen"),
			"%s: Replay-Knopf nur mit Replay (%s '%s')" % [tag, c._btn_a.visible, c._btn_a.text])
		_ok(c._btn_a.disabled == not owned, "%s: Replay nur mit Map aktiv" % tag)
		if owned:
			_ok(c._btn_b.visible and c._btn_b.text == c.tr("Spielen"),
				"%s: Spielen (%s '%s')" % [tag, c._btn_b.visible, c._btn_b.text])
		else:
			_ok(c._btn_b.visible and c._btn_b.text == ChatMapCard.tr2("Map herunterladen", "Download map"),
				"%s: Map herunterladen (%s '%s')" % [tag, c._btn_b.visible, c._btn_b.text])
		var btn_r: float = c._btn_b.get_global_rect().end.x if c._btn_b.visible else c._btn_a.get_global_rect().end.x
		_ok(btn_r <= c.get_global_rect().end.x - 6.0, "%s: Knoepfe in der Karte" % tag)
		_ok(c._btn_b.text != tr("Herunterladen"), "%s: kein blosses Download" % tag)
		_ok(c._cover_icon.texture != null, "%s: Cover-Platzhalter mit Modus-Symbol" % tag)
	# Knopf-Aktionen
	var c0: ChatMapCard = cards[0][2]
	var o0: StubOverlay = cards[0][3]
	c0._on_b()
	c0._on_a()
	_ok(o0.calls == ["play", "replay"], "Map da: Spielen + Replay rufen das Overlay")
	var c1: ChatMapCard = cards[1][2]
	var o1: StubOverlay = cards[1][3]
	c1._on_b()
	_ok(o1.calls == ["download"], "Map fehlt: Download ruft das Overlay")
	# Laden-Zustand
	var loading := _make("score", {}, ov, "x")
	await process_frame
	_ok(loading._title.text == tr("Score wird geladen …") and not loading._btn_b.visible, "Score laedt noch")
