extends Control

## TUTORIAL fuer neue Spieler: ausfuehrlicher Guide in Seiten (Steuerung,
## Judgements, Accuracy, Combo/Score/HP, Star-Rating, pp, Einstellungen,
## Map-Downloads, Multiplayer) — und am Ende startet die Uebungs-Map
## "tatatat - e [4k beginner]", die vor jedem neuen Element anhaelt und es
## direkt im Spiel erklaert.

const COL_ACCENT := Color(0.20, 0.85, 1.0)
const COL_DIM := Color(0.62, 0.64, 0.72)

var _pages: Array = []
var _page := 0
var _title: Label
var _body: RichTextLabel
var _page_label: Label
var _back_btn: Button
var _next_btn: Button
var _start_btn: Button
var _action_btn: Button
var _hint: Label


func _keys() -> Array:
	var k := []
	for code in Settings.key_lanes:
		k.append(OS.get_keycode_string(code))
	return k


func _build_pages() -> void:
	var k := _keys()
	var keytxt := "[b]%s  %s  %s  %s[/b]" % [k[0], k[1], k[2], k[3]]
	_pages = [
	{ "title": "WILLKOMMEN BEI TETHRA",
	"body": "4 Spuren, 4 Ringe. Drohnen fliegen auf dich zu —
druecke die Taste der Spur [b]genau beim Beruehren des Rings[/b].

Dieser Guide ist dein Nachschlagewerk (Wertung, pp, Sterne, Settings).
Die [b]Uebungs-Map[/b] (letzte Seite) zeigt dir alles direkt im Spiel." },
	{ "title": "STEUERUNG",
	"body": "[b]Deine 4 Spur-Tasten (links nach rechts):[/b]\n%s\n(aenderbar unter Einstellungen -> GAMEPLAY -> Tasten 1-4)\n\n[b]Weitere Tasten im Spiel:[/b]\nLEERTASTE — langes Intro ueberspringen\nR — Map sofort neu starten\nESC — Pause (Weiter mit 3-2-1-Countdown)\nF11 — Vollbild\n\n[b]Im Song-Browser:[/b]\nPfeil hoch/runter — Map wechseln\nPfeil links/rechts — Schwierigkeit wechseln\nENTER — Map starten\nF2 — Zufalls-Map" % keytxt },
	{ "title": "TREFFER-WERTUNG (JUDGEMENTS)",
	"body": "Wie praezise du triffst, entscheidet die Wertung — exakt wie in osu!mania:\n\n[b]MAX[/b]  — bis ±16,5 ms daneben (perfekt!)\n[b]300[/b]  — sehr gut\n[b]200[/b]  — gut\n[b]100[/b]  — ok\n[b]50[/b]   — gerade noch\n[b]✕ MISS[/b] — daneben oder gar nicht gedrueckt\n\nDie Fenster haengen von der [b]OD[/b] der Map ab (hoeher = strenger). Viel zu frueh druecken frisst die Note uebrigens auch — also nicht panisch hammern!\n\nDie kleine [b]UR-Leiste[/b] in der Bildmitte zeigt jeden Treffer als Strich: links vom Zentrum = zu frueh, rechts = zu spaet. Der gelbe Pfeil ist dein Trend." },
	{ "title": "ACCURACY — EXAKT ERKLAERT",
	"body": "Deine Accuracy (Acc) berechnet sich EXAKT nach der osu!mania-Formel:\n\n[b]Acc = (300·(MAX+300) + 200·n200 + 100·n100 + 50·n50) / (300 · alle Noten)[/b]\n\nHeisst: MAX und 300 zaehlen voll, ein 200er nur zwei Drittel, ein 100er ein Drittel, ein 50er ein Sechstel, ein Miss null.\n\n[b]Beispiel:[/b] 2 Noten — 1x MAX + 1x 200er:\n(300 + 200) / 600 = [b]83,33%%[/b]\n\n[b]Grades:[/b]\nSS = 100%%   ·   S ueber 95%%   ·   A ueber 90%%\nB ueber 80%%   ·   C ueber 70%%   ·   sonst D" },
	{ "title": "COMBO · SCORE · HP",
	"body": "[b]Combo:[/b] Jeder Treffer +1. Ein Miss — oder das zu fruehe Loslassen einer Hold-Note — setzt sie auf 0. Die Combo steht gross in der Bildmitte.\n\n[b]Score:[/b] Basispunkte je Wertung (MAX 320 … 50er 50), multipliziert mit deinem Combo-Multiplikator (bis [b]x4[/b] ab 300er-Combo). Lange Combos sind also Gold wert.\n\n[b]HP:[/b] Die kleine Leiste oben. Misses ziehen ab, Treffer heilen. Bei 0 -> [b]FAIL[/b]. Im Song-Browser kannst du [b]NF (No Fail)[/b] aktivieren, dann spielst du immer bis zum Ende.\n\nAb Combo 50/100/150 belohnen dich Effekte: Rand-Gluehen, OVERDRIVE-Blitz und mehr (Staerke unter Einstellungen -> Effekt-Intensitaet)." },
	{ "title": "STAR-RATING (★) — SCHWIERIGKEIT",
	"body": "Jede Schwierigkeit (Diff) einer Map hat ein [b]Star-Rating[/b], z.B. ★ 2,20. Es wird mit [b]rosu-pp[/b] berechnet — derselben offiziellen Bibliothek, die auch osu-Tools nutzen. TETHRA erfindet keine eigenen Werte.\n\n[b]Grobe Orientierung:[/b]\nunter 2★ — Einsteiger\n2–4★ — Fortgeschritten\n4–6★ — Schwer\n6★+ — Expert\n\nIm Song-Browser sind die Karten nach Sternen [b]farbcodiert[/b], und oben rechts kannst du nach Sternbereichen [b]filtern[/b] und nach Sternen [b]sortieren[/b].\n\nIm Info-Panel links siehst du ausserdem [b]\"Max N pp bei SS\"[/b] — die maximale pp-Ausbeute der gewaehlten Diff." },
	{ "title": "PP (PERFORMANCE POINTS)",
	"body": "pp messen, wie stark ein einzelner Play war — abhaengig von [b]Star-Rating[/b] und [b]Accuracy[/b].\n\nDie Berechnung laeuft ueber rosu-pp (offizielle Mania-Formel). Wichtig zu wissen: [b]Richtig viele pp gibt es erst ab ~80%% Accuracy[/b] — darueber steigt die Kurve steil an. Darunter sorgt ein TETHRA-Mindestwert dafuer, dass trotzdem jeder Play etwas zaehlt.\n\n[b]Dein Profil-pp[/b] (Hauptmenue, Profilkarte): Deine besten Scores werden sortiert und gewichtet aufsummiert — der beste zaehlt voll, der zweite mit 95%%, der dritte mit 90,25%% usw. (wie bei osu). Nur der [b]beste Score pro Diff[/b] zaehlt.\n\nKurz: Lieber eine Map sauber auf 95%%+ spielen als zehn Maps auf 70%%." },
	{ "title": "EINSTELLUNGEN ERKLAERT", "action": "settings",
	"body": "[b]Deine aktuellen Werte (live):[/b]
Scroll x%.1f  ·  Offset %+d ms  ·  Effekte: %s
Hitsounds: %s (%d%%)  ·  FPS: %s  ·  Vollbild: %s

" % [
		Settings.mania_scroll, int(Settings.offset_ms),
		["Aus", "Dezent", "Voll"][clampi(Settings.tunnel_intensity, 0, 2)],
		"an" if Settings.hitsounds else "aus", int(Settings.hitsound_volume * 100.0),
		["VSync", "Unlimited", "240 FPS", "360 FPS", "480 FPS"][clampi(Settings.fps_mode, 0, 4)],
		"an" if Settings.fullscreen else "aus"] + "[b]Scroll-Speed (x0,5–x3,0):[/b] Wie schnell die Noten anfliegen. REIN VISUELL — die Timing-Fenster bleiben exakt gleich, es ist also nie unfair. Hoeher = weniger Noten gleichzeitig auf dem Schirm (uebersichtlicher bei schnellen Maps).\n\n[b]Audio-Offset (±200 ms):[/b] Gleicht die Latenz deines Audio-Setups aus. Schau nach einem Play auf den [b]Ø-Wert[/b] im Endscreen: steht dort z.B. \"Ø +20 ms (spaet)\", stell den Offset in Richtung -20.\n\n[b]Hitsounds + Lautstaerke:[/b] Klick-Feedback beim Treffen, separat regelbar.\n\n[b]Effekt-Intensitaet:[/b] Aus / Dezent / Voll — dimmt Wellen, Glueh-Effekte, Kamera-Bewegung usw.\n\n[b]FPS-Limit:[/b] [b]Unlimited[/b] = praeziseste Eingaben (empfohlen). VSync = kein Tearing, aber mehr Latenz.\n\n[b]Vollbild:[/b] F11 jederzeit." },
	{ "title": "MAPS BEKOMMEN",
	"body": "[b]1) Online-Browser:[/b] Im Song-Browser oben auf [b]\"⤓ Online\"[/b]. Du siehst sofort Vorschlaege — nur [b]Ranked 4K-Mania[/b]-Maps. Klick auf eine Karte = [b]Anhoeren[/b], \"⤓ Download\" laedt sie direkt in deine Bibliothek. Filter nach Sternen inklusive.\n\n[b]2) Eigene Dateien:[/b] Jede osu!mania-[b].osz[/b]-Datei einfach in den [b]maps[/b]-Ordner legen (neben der TETHRA.exe) — oder per Drag&Drop ins Spielfenster ziehen.\n\n[b]3) Collections:[/b] Im Info-Panel [b]\"+ Sammlung\"[/b] — packe Maps in eigene Listen (z.B. \"Training\", \"Favoriten\") und filtere im Browser ueber den Collections-Tab.\n\nHinweis: Nur [b]4K[/b]-Diffs (4 Spalten) sind spielbar — andere werden automatisch ausgeblendet." },
	{ "title": "MULTIPLAYER",
	"body": "[b]Raum erstellen:[/b] Hauptmenue -> MULTIPLAYER -> \"+ Raum erstellen\". Der Port oeffnet sich automatisch (UPnP) und du bekommst einen kurzen [b]RAUM-CODE[/b] — den schickst du deinen Freunden.\n\n[b]Beitreten:[/b] Code eintippen -> Beitreten. Im selben WLAN erscheinen Raeume sogar automatisch in der Liste.\n\n[b]Die Krone 👑:[/b] Wer sie traegt, waehlt die Map (der Host kann sie per Klick weitergeben). Fehlt dir die gewaehlte Map, laedt sie [b]automatisch[/b] herunter.\n\n[b]Im Spiel:[/b] Links laeuft das [b]Live-Scoreboard[/b] — du siehst sofort, wenn du jemanden ueberholst. Das Intro wird nur uebersprungen, wenn [b]ALLE[/b] die Leertaste druecken. Am Ende zeigt die Rangliste alle Ergebnisse.\n\nBeim ersten Start fragt die Windows-Firewall — [b]\"Zulassen\"[/b] klicken!" },
	{ "title": "BEREIT? ZEIT ZU FLIEGEN!",
	"body": "Jetzt kommt die [b]Uebungs-Map[/b] (\"tatatat - e\", 4K Beginner — schoen langsam).\n\nSie haelt [b]automatisch an[/b], bevor etwas Neues passiert, und erklaert es dir:\n• deine erste [b]Note[/b]\n• deine erste [b]Hold-Note[/b] (halten!)\n• deine erste [b]Doppelnote[/b] (zwei Tasten gleichzeitig)\n• dein [b]HUD[/b]\n\nNach jeder Erklaerung geht es mit einem kurzen 3-2-1 weiter. [b]No Fail ist an[/b] — du kannst nichts falsch machen. Die Map laeuft nicht in deine Statistik.\n\nTipp: Du kannst das Tutorial jederzeit mit R neu starten oder mit ESC -> Song-Browser verlassen." },
	]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_pages()

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/menu_bg.gdshader")
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(18, 0.72)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(760, 600)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var tut := Label.new()
	tut.text = "TUTORIAL"
	tut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tut.add_theme_font_size_override("font_size", 15)
	tut.add_theme_color_override("font_color", COL_DIM)
	head.add_child(tut)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(38, 38)
	UiTheme.style_button(close)
	close.pressed.connect(_back)
	head.add_child(close)

	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.heading_font(2))
	_title.add_theme_font_size_override("font_size", 25)
	_title.add_theme_color_override("font_color", COL_ACCENT)
	vb.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 16)
	_body.add_theme_font_size_override("bold_font_size", 16)
	scroll.add_child(_body)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	_hint.text = ""
	vb.add_child(_hint)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	vb.add_child(nav)
	_back_btn = Button.new()
	_back_btn.text = "← Zurueck"
	_back_btn.custom_minimum_size = Vector2(130, 46)
	UiTheme.style_button(_back_btn)
	_back_btn.pressed.connect(func(): _goto(_page - 1))
	nav.add_child(_back_btn)
	_page_label = Label.new()
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.add_theme_font_size_override("font_size", 14)
	_page_label.add_theme_color_override("font_color", COL_DIM)
	nav.add_child(_page_label)
	_next_btn = Button.new()
	_next_btn.text = "Weiter →"
	_next_btn.custom_minimum_size = Vector2(130, 46)
	UiTheme.style_button(_next_btn, true)
	_next_btn.pressed.connect(func(): _goto(_page + 1))
	nav.add_child(_next_btn)
	_action_btn = Button.new()
	_action_btn.text = "⚙ Einstellungen jetzt oeffnen"
	_action_btn.custom_minimum_size = Vector2(240, 46)
	UiTheme.style_button(_action_btn)
	_action_btn.pressed.connect(func(): add_child(SettingsPanel.new()))
	_action_btn.visible = false
	nav.add_child(_action_btn)
	_start_btn = Button.new()
	_start_btn.text = "🚀 UEBUNGS-MAP STARTEN"
	_start_btn.custom_minimum_size = Vector2(260, 46)
	UiTheme.style_button(_start_btn, true)
	_start_btn.pressed.connect(_start_practice)
	nav.add_child(_start_btn)

	_goto(0)


func _goto(p: int) -> void:
	_page = clampi(p, 0, _pages.size() - 1)
	_title.text = str(_pages[_page].title)
	_body.text = str(_pages[_page].body)
	_page_label.text = "Seite %d / %d" % [_page + 1, _pages.size()]
	_back_btn.disabled = _page == 0
	var last := _page == _pages.size() - 1
	_next_btn.visible = not last
	_start_btn.visible = last
	_action_btn.visible = _pages[_page].has("action")
	_hint.text = ""


## Uebungs-Map suchen (Set 844183) und im Tutorial-Modus starten.
func _start_practice() -> void:
	var lib := MapLibrary.new()
	lib.scan()
	for ms in lib.mapsets:
		if not ms.osz_path.get_file().begins_with("844183"):
			continue
		for i in ms.difficulty_count():
			var m := ms.meta_at(i)
			if int(m.get("mode", 0)) != 3:
				continue
			GameSession.tutorial = true
			GameSession.mods = { "NF": true }
			GameSession.is_replay = false
			GameSession.replay_events = []
			GameSession.set_selection(ms.osz_path, i, ms.version_name_at(i),
				str(m.get("osu_filename", "")), ms.stars_at(i))
			get_tree().change_scene_to_file("res://scenes/mania_3d.tscn")
			return
	_hint.text = "Uebungs-Map nicht gefunden — lege \"844183 tatatat - e.osz\" in den maps-Ordner."


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			_back()
		KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER:
			if _page < _pages.size() - 1:
				_goto(_page + 1)
		KEY_LEFT:
			_goto(_page - 1)
