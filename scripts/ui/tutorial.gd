extends Control

## TUTORIAL für neue Spieler: ausführlicher Guide in Seiten (Steuerung,
## Judgements, Accuracy, Combo/Score/HP, Star-Rating, pp, Einstellungen,
## Map-Downloads, Multiplayer) — und am Ende startet die Übungs-Map
## "tatatat - e [4k beginner]", die vor jedem neuen Element anhält und es
## direkt im Spiel erklärt.

const COL_ACCENT := UiTheme.ACCENT
const COL_DIM := UiTheme.DIM

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
var _dots: HBoxContainer
var _card: VBoxContainer
var _goal_box: PanelContainer
var _goal: Label
var _keys_row: HBoxContainer
var _fade: Tween
var _scroll: ScrollContainer
var _fade_rect: TextureRect

const SHOT := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/tutorial.png"
const GOALS := [
	"Verstehe das Grundprinzip: Taste drücken, wenn die Drohne den Ring berührt.",
	"Lerne deine Spur-Tasten und die wichtigsten Kurztasten.",
	"Verstehe, wie genau dein Treffer gewertet wird.",
	"Verstehe, wie sich deine Accuracy berechnet.",
	"Verstehe Combo, Score und HP.",
	"Lerne, die Schwierigkeit einer Map einzuschätzen.",
	"Verstehe, wie pp entstehen und was sie wert sind.",
	"Stelle Scroll-Speed, Offset und Effekte passend für dich ein.",
	"Finde neue Maps und bringe eigene ins Spiel.",
	"Spiele mit Freunden im selben Raum.",
	"Starte die Übungs-Map und probiere alles direkt aus.",
]


## Ruhiger Hintergrund: dunkler Verlauf plus weiche, runde Lichtpunkte (kein Pixelraster).
class SoftBg extends Control:
	var _dots: Array = []

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4711
		for i in 70:
			_dots.append([rng.randf(), rng.randf(), rng.randf_range(1.5, 4.5), rng.randf_range(0.04, 0.16)])
		resized.connect(queue_redraw)

	func _draw() -> void:
		var top := UiTheme.SURFACE
		var bot := UiTheme.BG
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
			PackedColorArray([top, top, bot, bot]))
		for d in _dots:
			var c := Vector2(d[0] * size.x, d[1] * size.y)
			for k in 4:
				var r: float = d[2] * (1.0 + k * 1.2)
				draw_circle(c, r, Color(UiTheme.TEXT, d[3] * 0.35 / (1.0 + k * 0.6)))


## Kurze Tastennamen fuer die Keycaps ("," statt Comma).
func _key_names() -> Array:
	var short := { KEY_COMMA: ",", KEY_PERIOD: ".", KEY_SLASH: "/", KEY_SEMICOLON: ";",
		KEY_APOSTROPHE: "'", KEY_SPACE: tr("Leer"), KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
		KEY_MINUS: "-", KEY_EQUAL: "=", KEY_BACKSLASH: "\\", KEY_COLON: ":" }
	var k := []
	for code in Settings.key_lanes:
		k.append(short[code] if short.has(code) else OS.get_keycode_string(code))
	return k


func _build_pages() -> void:
	_pages = [
	{ "title": "Willkommen bei OMEN",
	"body": "4 Spuren, 4 Ringe. Drohnen fliegen auf dich zu —
drücke die Taste der Spur [b]genau beim Berühren des Rings[/b].

Dieser Guide ist dein Nachschlagewerk (Wertung, pp, Sterne, Settings).
Die [b]Übungs-Map[/b] (letzte Seite) zeigt dir alles direkt im Spiel." },
	{ "title": "Steuerung",
	"body": "[b]Deine 4 Spur-Tasten (links nach rechts):[/b]\n(änderbar unter Einstellungen › Gameplay › Tasten 1–4)\n\n[b]Weitere Tasten im Spiel:[/b]\n{Leertaste}  langes Intro überspringen\n{R}  Map sofort neu starten\n{Esc}  Pause (weiter mit 3-2-1-Countdown)\n{F11}  Vollbild\n\n[b]Im Song-Browser:[/b]\n{↑} {↓}  Map wechseln\n{←} {→}  Schwierigkeit wechseln\n{Enter}  Map starten\n{F2}  Zufalls-Map", "keys": true },
	{ "title": "Treffer-Wertung",
	"body": "Wie präzise du triffst, entscheidet die Wertung — exakt wie in osu!mania:\n\n[b]MAX[/b]  — bis ±16,5 ms daneben (perfekt!)\n[b]300[/b]  — sehr gut\n[b]200[/b]  — gut\n[b]100[/b]  — ok\n[b]50[/b]   — gerade noch\n[b]✕ MISS[/b] — daneben oder gar nicht gedrückt\n\nDie Fenster hängen von der [b]OD[/b] der Map ab (höher = strenger). Viel zu früh drücken frisst die Note übrigens auch — also nicht panisch hammern!\n\nDie kleine [b]UR-Leiste[/b] in der Bildmitte zeigt jeden Treffer als Strich: links vom Zentrum = zu früh, rechts = zu spät. Der gelbe Pfeil ist dein Trend." },
	{ "title": "Accuracy genau erklärt",
	"body": "Deine Accuracy (Acc) berechnet sich genau nach der osu!mania-Formel:\n\n[b]Acc = (300·(MAX+300) + 200·n200 + 100·n100 + 50·n50) / (300 · alle Noten)[/b]\n\nHeißt: MAX und 300 zählen voll, ein 200er nur zwei Drittel, ein 100er ein Drittel, ein 50er ein Sechstel, ein Miss null.\n\n[b]Beispiel:[/b] 2 Noten — 1x MAX + 1x 200er:\n(300 + 200) / 600 = [b]83,33 %[/b]\n\n[b]Grades:[/b]\nSS = 100 %   ·   S über 95 %   ·   A über 90 %\nB über 80 %   ·   C über 70 %   ·   sonst D" },
	{ "title": "Combo, Score und HP",
	"body": "[b]Combo:[/b] Jeder Treffer +1. Ein Miss — oder das zu frühe Loslassen einer Hold-Note — setzt sie auf 0. Die Combo steht groß in der Bildmitte.\n\n[b]Score:[/b] genau die osu!mania-Formel (ScoreV1), Maximum [b]1.000.000[/b] pro Map: Die eine Hälfte sind Basispunkte je Wertung (MAX 320 … 50er 50), die andere ein [b]Bonus-Zähler[/b], der mit sauberen Treffern wächst und bei 100ern/50ern/Misses einbricht. Präzision und Konstanz zählen.\n\n[b]HP:[/b] Die kleine Leiste oben. Misses ziehen ab, Treffer heilen. Bei 0 folgt [b]Fail[/b]. Im Song-Browser kannst du [b]NF (No Fail)[/b] aktivieren, dann spielst du immer bis zum Ende.\n\nAb Combo 50/100/150 belohnen dich Effekte: Rand-Glühen, Overdrive-Blitz und mehr (Stärke unter Einstellungen › Effekt-Intensität)." },
	{ "title": "Star-Rating und Schwierigkeit",
	"body": "Jede Schwierigkeit (Diff) einer Map hat ein [b]Star-Rating[/b], z.B. ★ 2,20. Es wird mit [b]rosu-pp[/b] berechnet — derselben offiziellen Bibliothek, die auch osu-Tools nutzen. OMEN erfindet keine eigenen Werte.\n\n[b]Grobe Orientierung:[/b]\nunter 2★ — Einsteiger\n2–4★ — Fortgeschritten\n4–6★ — Schwer\n6★+ — Expert\n\nIm Song-Browser sind die Karten nach Sternen [b]farbcodiert[/b], und oben rechts kannst du nach Sternbereichen [b]filtern[/b] und nach Sternen [b]sortieren[/b].\n\nIm Info-Panel links siehst du außerdem [b]\"Max N pp bei SS\"[/b] — die maximale pp-Ausbeute der gewählten Diff." },
	{ "title": "Performance Points (pp)",
	"body": "pp messen, wie stark ein einzelner Play war — abhängig von [b]Star-Rating[/b] und [b]Accuracy[/b].\n\nDie Berechnung läuft über rosu-pp (offizielle Mania-Formel). Wichtig zu wissen: [b]Richtig viele pp gibt es erst ab ~80 % Accuracy[/b] — darüber steigt die Kurve steil an. Darunter sorgt ein OMEN-Mindestwert dafür, dass trotzdem jeder Play etwas zählt.\n\n[b]Dein Profil-pp[/b] (Hauptmenü, Profilkarte): Deine besten Scores werden sortiert und gewichtet aufsummiert — der beste zählt voll, der zweite mit 95 %, der dritte mit 90,25 % usw. (wie bei osu). Nur der [b]beste Score pro Diff[/b] zählt.\n\nKurz: Lieber eine Map sauber auf 95 %+ spielen als zehn Maps auf 70 %." },
	{ "title": "Einstellungen erklärt", "action": "settings",
	"body": tr("[b]Deine aktuellen Werte (live):[/b]
Scroll x%.1f  ·  Offset %+d ms  ·  Effekte: %s
Hitsounds: %s (%d%%)  ·  FPS: %s  ·  Vollbild: %s

") % [
		Settings.mania_scroll, int(Settings.offset_ms),
		tr(["Aus", "Dezent", "Voll"][clampi(Settings.tunnel_intensity, 0, 2)]),
		tr("an") if Settings.hitsounds else tr("aus"), int(Settings.hitsound_volume * 100.0),
		["VSync", "Unlimited", "240 FPS", "360 FPS", "480 FPS"][clampi(Settings.fps_mode, 0, 4)],
		tr("an") if Settings.fullscreen else tr("aus")] + tr("[b]Scroll-Speed (x0,5–x3,0):[/b] Wie schnell die Noten anfliegen. Rein visuell — die Timing-Fenster bleiben exakt gleich, es ist also nie unfair. Höher = weniger Noten gleichzeitig auf dem Schirm (übersichtlicher bei schnellen Maps).\n\n[b]Audio-Offset (±200 ms):[/b] Gleicht die Latenz deines Audio-Setups aus. Schau nach einem Play auf den [b]Ø-Wert[/b] im Endscreen: steht dort z.B. \"Ø +20 ms (spät)\", stell den Offset in Richtung -20.\n\n[b]Hitsounds + Lautstärke:[/b] Klick-Feedback beim Treffen, separat regelbar.\n\n[b]Effekt-Intensität:[/b] Aus / Dezent / Voll — dimmt Wellen, Glüh-Effekte, Kamera-Bewegung usw.\n\n[b]FPS-Limit:[/b] [b]Unlimited[/b] = präziseste Eingaben (empfohlen). VSync = kein Tearing, aber mehr Latenz.\n\n[b]Vollbild:[/b] {F11} jederzeit.") },
	{ "title": "Maps bekommen",
	"body": "[b]1) Online-Browser:[/b] Im Song-Browser oben auf [b]\"⤓ Online\"[/b]. Du siehst sofort Vorschläge — nur [b]Ranked 4K-Mania[/b]-Maps. Klick auf eine Karte = [b]Anhören[/b], \"⤓ Download\" lädt sie direkt in deine Bibliothek. Filter nach Sternen inklusive.\n\n[b]2) Eigene Dateien:[/b] Jede osu!mania-[b].osz[/b]-Datei einfach in den [b]maps[/b]-Ordner legen (neben der Spiel-Exe) — oder per Drag&Drop ins Spielfenster ziehen.\n\n[b]3) Collections:[/b] Im Info-Panel [b]\"+ Sammlung\"[/b] — packe Maps in eigene Listen (z.B. \"Training\", \"Favoriten\") und filtere im Browser über den Collections-Tab.\n\nHinweis: Nur [b]4K[/b]-Diffs (4 Spalten) sind spielbar — andere werden automatisch ausgeblendet." },
	{ "title": "Multiplayer",
	"body": "[b]Raum erstellen:[/b] Hauptmenü › Multiplayer › \"+ Raum erstellen\". Der Port öffnet sich automatisch (UPnP) und du bekommst einen kurzen [b]Raum-Code[/b] — den schickst du deinen Freunden.\n\n[b]Beitreten:[/b] Code eintippen › Beitreten. Im selben WLAN erscheinen Räume sogar automatisch in der Liste.\n\n[b]Die Krone 👑:[/b] Wer sie trägt, wählt die Map (der Host kann sie per Klick weitergeben). Fehlt dir die gewählte Map, lädt sie [b]automatisch[/b] herunter.\n\n[b]Im Spiel:[/b] Links läuft das [b]Live-Scoreboard[/b] — du siehst sofort, wenn du jemanden überholst. Das Intro wird nur übersprungen, wenn [b]alle[/b] die {Leertaste} drücken. Am Ende zeigt die Rangliste alle Ergebnisse.\n\nBeim ersten Start fragt die Windows-Firewall — [b]\"Zulassen\"[/b] klicken!" },
	{ "title": "Bereit? Zeit zu fliegen!",
	"body": "Jetzt kommt die [b]Übungs-Map[/b] (\"tatatat - e\", 4K Beginner — schön langsam).\n\nSie hält [b]automatisch an[/b], bevor etwas Neues passiert, und erklärt es dir:\n• deine erste [b]Note[/b]\n• deine erste [b]Hold-Note[/b] (halten!)\n• deine erste [b]Doppelnote[/b] (zwei Tasten gleichzeitig)\n• dein [b]HUD[/b]\n\nNach jeder Erklärung geht es mit einem kurzen 3-2-1 weiter. [b]No Fail ist an[/b] — du kannst nichts falsch machen. Die Map läuft nicht in deine Statistik.\n\nTipp: Du kannst das Tutorial jederzeit mit {R} neu starten oder mit {Esc} › Song-Browser verlassen." },
	]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_pages()

	var bg := SoftBg.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(18, 0.72)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(900, minf(840.0, maxf(560.0, get_viewport_rect().size.y - 80.0)))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var tut := Label.new()
	tut.text = "TUTORIAL"
	tut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tut.add_theme_font_override("font", UiTheme.heading_font(3))
	tut.add_theme_font_size_override("font_size", 15)
	tut.add_theme_color_override("font_color", COL_DIM)
	head.add_child(tut)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(38, 38)
	UiTheme.style_button(close)
	close.pressed.connect(_back)
	head.add_child(close)

	# Fortschrittspunkte: aktuelle Seite als Pille, erledigte gedimmt.
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 6)
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_dots)
	for i in _pages.size():
		var d := Panel.new()
		d.custom_minimum_size = Vector2(8, 8)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dots.add_child(d)

	# Schritt-Karte: alles darin blendet beim Seitenwechsel sanft ein.
	_card = VBoxContainer.new()
	_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card.add_theme_constant_override("separation", 12)
	vb.add_child(_card)

	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.heading_font(2))
	_title.add_theme_font_size_override("font_size", 25)
	_title.add_theme_color_override("font_color", COL_ACCENT)
	_card.add_child(_title)

	# Ziel-Zeile der Seite.
	_goal_box = PanelContainer.new()
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.10)
	gsb.set_corner_radius_all(4)
	gsb.set_border_width_all(1)
	gsb.border_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.30)
	gsb.content_margin_left = 14
	gsb.content_margin_right = 14
	gsb.content_margin_top = 8
	gsb.content_margin_bottom = 8
	_goal_box.add_theme_stylebox_override("panel", gsb)
	_card.add_child(_goal_box)
	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 10)
	_goal_box.add_child(grow)
	var gtag := Label.new()
	gtag.text = "ZIEL"
	gtag.add_theme_font_override("font", UiTheme.heading_font(2))
	gtag.add_theme_font_size_override("font_size", 13)
	gtag.add_theme_color_override("font_color", COL_ACCENT)
	grow.add_child(gtag)
	_goal = Label.new()
	_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goal.add_theme_font_size_override("font_size", 15)
	_goal.add_theme_color_override("font_color", UiTheme.TEXT)
	grow.add_child(_goal)

	# Tasten als grosse Keycaps (nur auf der Steuerungs-Seite).
	_keys_row = HBoxContainer.new()
	_keys_row.add_theme_constant_override("separation", 12)
	_keys_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_child(_keys_row)
	var kn := _key_names()
	for i in 4:
		_keys_row.add_child(_make_keycap(kn[i]))

	var wrap := PanelContainer.new()
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_card.add_child(wrap)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrap.add_child(scroll)
	_scroll = scroll
	scroll.get_v_scroll_bar().value_changed.connect(func(_v): _update_fade())
	var fg := Gradient.new()
	fg.set_color(0, Color(UiTheme.SURFACE, 0.0))
	fg.set_color(1, Color(UiTheme.SURFACE, 0.95))
	var fgt := GradientTexture2D.new()
	fgt.gradient = fg
	fgt.fill_from = Vector2(0.5, 0.0)
	fgt.fill_to = Vector2(0.5, 1.0)
	fgt.width = 4
	fgt.height = 64
	_fade_rect = TextureRect.new()
	_fade_rect.texture = fgt
	_fade_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_fade_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade_rect.custom_minimum_size = Vector2(0, 56)
	_fade_rect.size_flags_vertical = Control.SIZE_SHRINK_END
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_fade_rect)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 16)
	_body.add_theme_font_size_override("bold_font_size", 16)
	_body.add_theme_color_override("default_color", UiTheme.TEXT)
	scroll.add_child(_body)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", UiTheme.BAD)
	_hint.text = ""
	vb.add_child(_hint)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	vb.add_child(nav)
	_back_btn = Button.new()
	_back_btn.text = "‹ Zurück"
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
	_next_btn.text = "Weiter ›"
	_next_btn.custom_minimum_size = Vector2(130, 46)
	UiTheme.style_button(_next_btn, true)
	_next_btn.pressed.connect(func(): _goto(_page + 1))
	nav.add_child(_next_btn)
	_action_btn = Button.new()
	_action_btn.text = "⚙ Einstellungen jetzt öffnen"
	_action_btn.custom_minimum_size = Vector2(240, 46)
	UiTheme.style_button(_action_btn)
	_action_btn.pressed.connect(func(): add_child(SettingsPanel.new()))
	_action_btn.visible = false
	nav.add_child(_action_btn)
	_start_btn = Button.new()
	_start_btn.text = UiTheme.sentence(tr("🚀 ÜBUNGS-MAP STARTEN").trim_prefix("🚀 "))
	_start_btn.custom_minimum_size = Vector2(260, 46)
	UiTheme.style_button(_start_btn, true)
	_start_btn.pressed.connect(_start_practice)
	nav.add_child(_start_btn)

	_goto(0, false)
	_next_btn.grab_focus()

	var args := OS.get_cmdline_args()
	if args.has("--shot") or args.has("shot"):
		_shot()


## Eine grosse Taste im Keycap-Look: dunkle Kappe, heller Rand, dickere Unterkante.
func _make_keycap(txt: String) -> PanelContainer:
	var cap := PanelContainer.new()
	var sbk := StyleBoxFlat.new()
	sbk.bg_color = UiTheme.RAISED
	sbk.set_corner_radius_all(6)
	sbk.set_border_width_all(2)
	sbk.border_width_bottom = 6
	sbk.border_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.70)
	cap.add_theme_stylebox_override("panel", sbk)
	cap.custom_minimum_size = Vector2(76, 76)
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.heading_font(1))
	l.add_theme_font_size_override("font_size", 30 if txt.length() <= 2 else 20)
	l.add_theme_color_override("font_color", UiTheme.TEXT)
	cap.add_child(l)
	return cap


## {Taste} im Fliesstext wird zur Keycap-Markierung.
func _keycaps(t: String) -> String:
	var re := RegEx.new()
	re.compile("\\{([^{}]+)\\}")
	return re.sub(t, "[bgcolor=#2b3250][color=#ffffff][b] $1 [/b][/color][/bgcolor]", true)


func _update_fade() -> void:
	if _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	_fade_rect.visible = bar.max_value - bar.page > bar.value + 4.0


func _update_dots() -> void:
	for i in _dots.get_child_count():
		var d: Panel = _dots.get_child(i)
		var cur := i == _page
		var col := Color(1, 1, 1, 0.18)
		if cur:
			col = COL_ACCENT
		elif i < _page:
			col = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.45)
		var dsb := StyleBoxFlat.new()
		dsb.bg_color = col
		dsb.set_corner_radius_all(2)
		d.add_theme_stylebox_override("panel", dsb)
		var tw := d.create_tween()
		tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(d, "custom_minimum_size:x", 26.0 if cur else 8.0, 0.18)


func _goto(p: int, animate: bool = true) -> void:
	_page = clampi(p, 0, _pages.size() - 1)
	var pg: Dictionary = _pages[_page]
	_title.text = tr(str(pg.title))
	_goal.text = tr(str(GOALS[_page])) if _page < GOALS.size() else ""
	_goal_box.visible = _goal.text != ""
	_keys_row.visible = pg.get("keys", false)
	# Fliesstext erst uebersetzen (Schluessel = deutscher Text), dann Keycaps.
	_body.text = _keycaps(tr(str(pg.body)))
	_scroll.scroll_vertical = 0
	_update_fade.call_deferred()
	_page_label.text = ""
	_back_btn.disabled = _page == 0
	var last := _page == _pages.size() - 1
	_next_btn.visible = not last
	_start_btn.visible = last
	_action_btn.visible = pg.has("action")
	_hint.text = ""
	_update_dots()
	if animate:
		if _fade:
			_fade.kill()
		_card.modulate.a = 0.0
		_fade = create_tween()
		_fade.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_fade.tween_property(_card, "modulate:a", 1.0, 0.22)


func _shot() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	await get_tree().create_timer(0.8).timeout
	var pg := 1
	for a in OS.get_cmdline_args():
		if a.begins_with("--page="):
			pg = int(a.substr(7)) - 1
	_goto(pg, false)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SHOT)
	print("SHOT gespeichert: " + SHOT)
	get_tree().quit(0)


## Übungs-Map suchen (Set 844183) und im Tutorial-Modus starten.
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
	_hint.text = "Übungs-Map nicht gefunden — lege \"844183 tatatat - e.osz\" in den maps-Ordner."


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
