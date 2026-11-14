class_name OrbitTutorial
extends Control

## Orbit-Einfuehrung fuer die Satelliten (docs/modes/orbit_satellit.md): sieben
## kurze Schritte mit echtem Mitspielen und klarer Erfolgsbedingung.
##   1 Zielen     Cursor auf das Ziel legen und kurz drauf bleiben
##   2 Satellit   Taste A druecken, wenn der Satellit oben ist (Pips zaehlen Runden)
##   3 Tasten     A = kuehle Scheibe, B = warmes Quadrat; falsche Taste = Miss (Anti-Mash)
##   4 Akzent     Scheibe mit weissem Ring = beide Tasten zugleich
##   5 Halten     Taste halten und der Kugel folgen
##   6 Skill      weite Spruenge, dann eine schnelle Folge (Wechselschlag: A, B, A, B)
##   7 Probe      alles zusammen, mit Wertung
## Wertung ueber OrbitCore (wie im Spiel, NF an), Darstellung im eigenen Feld
## (Field) nach der Optik der Spezifikation. Tempo ab 60 BPM steigend (BPMS).
## Neue Runden kommen von selbst, bis die Bedingung erfuellt ist. Fehler nennen
## den Grund am Ort ("daneben", "andere Taste", "zu frueh", ...), oben steht der
## Hinweis dazu. Nach der Probe-Runde: OrbitCareer.offer() (falls vorhanden).
## Tab = Schritt ueberspringen, Esc = beenden. Tasten aus den Settings
## (orbit_key_inner/outer = Taste A/B), dazu immer Maus links/rechts.
## Harness: --shot-tutorial [--shot-out=<ordner>] [--lang=en]: Bot spielt mit
## simulierter Uhr, je Schritt ein Bild, ein Fehlerbild und die Wertung, dann quit.

const BROWSER := "res://scenes/song_select.tscn"
static var seen_path := "user://orbit_tutorial.cfg"
## Karriere-Datei fuer OrbitCareer.offer ("" = Standard; Tests setzen einen Pfad).
static var career_path := ""

enum { AIM, SAT, KEYS, ACCENT, HOLD, SKILL, TRIAL }
const STEP_COUNT := 7
const BPMS: Array[float] = [60.0, 60.0, 66.0, 72.0, 76.0, 84.0, 92.0]
## Erfolge bis zum naechsten Schritt (SKILL: eine gute Runde, TRIAL: eine Runde).
const NEED: Array[int] = [3, 3, 4, 3, 2, 1, 1]
## Vorlauf-Runden je Schritt (Pips beim Erscheinen).
const LAPS: Array[int] = [2, 3, 3, 3, 2, 2, 2]
## Skill-Runde: so viele Treffer von allen Zielen der Runde.
const SKILL_MIN_HITS := 7
const OD := 4.0
## Zielradius (Feld-Einheiten), etwas groesser als im Spiel.
const RADIUS := 0.085  # etwas kleiner als osu! CS 4 (0,095): Tutorial bleibt luftig, Spiel nutzt target_radius(beatmap)
const AIM_DWELL_MS := 650.0
const DONE_PAUSE_MS := 1200.0
const SAY_MS := 2600.0
const FX_MS := 900.0
const BOT_LEAD_MS := 6.0
const BOT_TAP_MS := 40.0
## Bot zielt leicht neben die Mitte (innerhalb des vollen Zielfaktors).
const BOT_AIM_OFFSET := Vector2(0.014, 0.022)
## Kopfzeile (Anteil der Hoehe) und Rand unten fuer das Feld.
const TOP_K := 0.22
const BOTTOM_K := 0.06
const ORBIT_K := 1.6

const COL_A := Color(0.47, 0.78, 0.98)
const COL_B := Color(1.0, 0.70, 0.40)
const TIER_COLS := [
	Color(1.0, 0.96, 0.86), Color(0.85, 0.95, 1.0), Color(0.60, 0.85, 0.65),
	Color(0.85, 0.80, 0.55), Color(0.80, 0.62, 0.50), Color(0.90, 0.48, 0.48),
]
const AIM_SPOTS := [Vector2(0.5, 0.5), Vector2(0.24, 0.3), Vector2(0.78, 0.68),
		Vector2(0.28, 0.74), Vector2(0.74, 0.28)]
const SAT_SPOTS := [Vector2(0.5, 0.5), Vector2(0.36, 0.42), Vector2(0.64, 0.58), Vector2(0.44, 0.62)]

var step := AIM
var success := 0
var t_ms := 0.0
var manual_clock := false
var bot := false
var finished := false
var core: OrbitCore = null
var notes: Array[OrbitNote] = []
## Ergebnis der Probe-Runde (OrbitCore.stats()).
var trial_stats: Dictionary = {}
## Letzter Fehlergrund: aim | key | early | lock | miss | both | release | lost.
var fb_reason := ""
var fb_count := 0

var _field: Field
var _step_lbl: Label
var _title_lbl: Label
var _body_lbl: Label
var _pip_row: HBoxContainer
var _pips: Array[ColorRect] = []
var _feedback: Label
var _bar: HBoxContainer
var _skip_btn: Button
var _quit_btn: Button
var _result: Control
var _tick_player: AudioStreamPlayer
var _hit_player: AudioStreamPlayer
var _start_usec := 0

var _beat_ms := 1000.0
var _t0 := 0.0
var _last_beat := -1
var _round := 0
var _judged_n := 0
var _round_hits := 0
var _round_over := false
var _done_t := -1.0
var _say_t := -INF
var _aim_pos := Vector2(0.5, 0.5)
var _aim_since := -1.0
var _cursor := Vector2(0.5, 0.5)
var _moved := false
## [Taste][Quelle 0 Maus, 1 Tastatur]
var _held := [[false, false], [false, false]]
var _press_signal := ""
var _half_accent_t := -INF
## Index des zuletzt verfehlten Ziels (Anti-Mash: Grund dort anzeigen).
var _miss_idx := -1
## Effekte im Feld: {k: hit|miss|text, p: Feld, t, col, s}
var fx: Array = []
var _bot_idx := 0
var _bot_release := [-1.0, -1.0]


# ---------------------------------------------------------------------------
# Feld: zeichnet Ziele, Satelliten, Pips, Halten, Effekte und den Cursor
# ---------------------------------------------------------------------------

class Field extends Control:
	var tut: OrbitTutorial
	var font: Font = UiTheme.heading_font(0)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	## Feld-Rechteck in Pixeln (4:3, unter der Kopfzeile).
	func field_rect() -> Rect2:
		var s := size
		var top := s.y * OrbitTutorial.TOP_K
		var h := s.y * (1.0 - OrbitTutorial.TOP_K - OrbitTutorial.BOTTOM_K)
		var w := h * 4.0 / 3.0
		if w > s.x * 0.92:
			w = s.x * 0.92
			h = w * 0.75
		return Rect2(Vector2((s.x - w) * 0.5, top), Vector2(w, h))

	func field_to_screen(p: Vector2) -> Vector2:
		var r := field_rect()
		return r.position + p * r.size

	func screen_to_field(px: Vector2) -> Vector2:
		var r := field_rect()
		return (px - r.position) / r.size

	## Grundfarbe des Felds (fuer vorgemischte Flaechen).
	func base_col() -> Color:
		return UiTheme.BG.darkened(0.25).lerp(Color.WHITE, 0.025)

	## Pixel je Feld-Einheit (Hoehe); Radien werden damit gezeichnet.
	func unit() -> float:
		return field_rect().size.y

	func _draw() -> void:
		if tut == null or tut.finished:
			return
		var r := field_rect()
		draw_rect(r, Color(1, 1, 1, 0.025), true)
		draw_rect(r, Color(1, 1, 1, 0.06), false, 1.0)
		var t := tut.t_ms
		var rad := OrbitTutorial.RADIUS * unit()
		if tut.step == OrbitTutorial.AIM:
			_draw_aim(rad)
		else:
			_draw_notes(t, rad)
		_draw_fx(t, rad)
		_draw_legend()
		if tut._moved:
			var c := field_to_screen(tut._cursor)
			draw_arc(c, 9.0, 0.0, TAU, 28, Color(1, 1, 1, 0.92), 2.0, true)
			draw_circle(c, 2.0, Color(1, 1, 1, 0.92), true, -1.0, true)

	func _draw_aim(rad: float) -> void:
		var p := field_to_screen(tut._aim_pos)
		var on := tut.on_target()
		_body(p, rad, OrbitNote.KEY_A, 1.0)
		draw_arc(p, rad * OrbitTutorial.ORBIT_K, 0.0, TAU, 64, Color(1, 1, 1, 0.22), 1.5, true)
		var k := tut.aim_progress()
		if k > 0.0:
			draw_arc(p, rad * OrbitTutorial.ORBIT_K, -PI * 0.5, -PI * 0.5 + TAU * k, 64,
					Color(1, 1, 1, 0.95), 3.0, true)
		if not on:
			_center_text(p + Vector2(0, rad * OrbitTutorial.ORBIT_K + 22.0), tut.tr("hierhin"), 15,
					Color(UiTheme.TEXT, 0.7))

	func _draw_notes(t: float, rad: float) -> void:
		var vis := tut.visible_notes()
		if vis.is_empty():
			return
		var nxt: int = vis[0]
		# Verbindungslinie zum uebernaechsten Ziel (dezent).
		if vis.size() > 1:
			var a := field_to_screen(tut.notes[nxt].pos_at(t) if tut.hold_active(nxt) else tut.notes[nxt].pos)
			var b := field_to_screen(tut.notes[vis[1]].pos)
			var d := a.distance_to(b)
			if d > rad * 3.4:
				var u := (b - a) / d
				draw_line(a + u * rad * 1.7, b - u * rad * 1.7, Color(1, 1, 1, 0.14), 1.5, true)
		for j in range(vis.size() - 1, -1, -1):
			var i: int = vis[j]
			_draw_note(i, t, rad, 1.0 if j == 0 else 0.55, j == 0)

	func _draw_note(i: int, t: float, rad: float, alpha: float, is_next: bool) -> void:
		var n: OrbitNote = tut.notes[i]
		var p := field_to_screen(n.pos)
		var col := OrbitTutorial.key_color(n.key)
		# Erscheinen: kurzer Pop auf dem Beat.
		var since := t - n.spawn_ms
		var pop := clampf(since / 120.0, 0.0, 1.0)
		var a := alpha * pop
		var s := 1.0 + 0.12 * (1.0 - pop)
		if n.is_hold:
			var pts := PackedVector2Array()
			for q in n.path:
				pts.append(field_to_screen(q))
			# Band deckend vorgemischt (keine Naehte durch ueberlappende Deckkraft).
			var band := Color(base_col().lerp(col, 0.24), a)
			draw_polyline(pts, band, rad * 1.8, true)
			draw_circle(pts[0], rad * 0.9, band, true, -1.0, true)
			draw_circle(pts[pts.size() - 1], rad * 0.9, band, true, -1.0, true)
			draw_arc(pts[pts.size() - 1], rad * 0.9, 0.0, TAU, 40, Color(col, 0.6 * a), 1.5, true)
			if tut.hold_active(i):
				var bp := field_to_screen(n.pos_at(t))
				var out := tut.core.hold_out_ms(i, t) > 0.0
				draw_circle(bp, rad * 0.6, Color(1, 1, 1, 0.95), true, -1.0, true)
				draw_arc(bp, rad * OrbitCore.FOLLOW_RADIUS, 0.0, TAU, 64,
						Color(UiTheme.BAD if out else col, 0.85), 2.0, true)
				return
		_body(p, rad * s, n.key, a)
		if is_next:
			_center_text(p + Vector2(0, 7.0), tut.key_caption(n.key), 19 if n.key != 2 else 15,
					Color(UiTheme.BG, 0.95 * a))
		# Orbit-Ring, Marke oben, Satellit.
		var orad := rad * OrbitTutorial.ORBIT_K
		var beat := fposmod((t - tut._t0) / tut._beat_ms, 1.0)
		var pulse := 0.10 * clampf(1.0 - beat * 4.0, 0.0, 1.0)
		var ring_a := (0.18 + pulse) if is_next else 0.10
		draw_arc(p, orad, 0.0, TAU, 64, Color(1, 1, 1, ring_a * a), 1.5, true)
		draw_line(p + Vector2(0, -orad - 6.0), p + Vector2(0, -orad + 6.0), Color(1, 1, 1, 0.9 * a), 2.0, true)
		if t <= n.time_ms + 60.0:
			var deg := deg_to_rad(n.satellite_deg(t))
			var sp := p + Vector2(sin(deg), -cos(deg)) * orad
			draw_circle(sp, 5.0 if n.laps_left(t) == 0 else 4.0, Color(1, 1, 1, a), true, -1.0, true)
		# Pips: verbleibende ganze Runden.
		var left := n.laps_left(t)
		var y := p.y + orad + 11.0
		for k in left:
			var x := p.x + (float(k) - float(left - 1) * 0.5) * 10.0
			draw_circle(Vector2(x, y), 2.6, Color(1, 1, 1, 0.85 * a), true, -1.0, true)

	## Zielkoerper: A Scheibe (kuehl), B abgerundetes Quadrat (warm), Akzent halb/halb + weisser Ring.
	func _body(p: Vector2, rad: float, key: int, a: float) -> void:
		if key == OrbitNote.KEY_B:
			var h := rad * 0.9
			draw_colored_polygon(OrbitTutorial.rsquare(p, h, h * 0.32), Color(OrbitTutorial.COL_B, a))
			var rim := OrbitTutorial.rsquare(p, h, h * 0.32)
			rim.append(rim[0])
			draw_polyline(rim, Color(OrbitTutorial.COL_B.lightened(0.55), a), 2.5, true)
		elif key == OrbitNote.KEY_ACCENT:
			draw_colored_polygon(OrbitTutorial.half_disk(p, rad, true), Color(OrbitTutorial.COL_A, a))
			draw_colored_polygon(OrbitTutorial.half_disk(p, rad, false), Color(OrbitTutorial.COL_B, a))
			draw_arc(p, rad + 1.0, 0.0, TAU, 56, Color(1, 1, 1, a), 3.5, true)
		else:
			draw_circle(p, rad, Color(OrbitTutorial.COL_A, a), true, -1.0, true)
			draw_arc(p, rad, 0.0, TAU, 56, Color(OrbitTutorial.COL_A.lightened(0.55), a), 2.5, true)

	func _draw_fx(t: float, rad: float) -> void:
		for e in tut.fx:
			var age: float = t - float(e.t)
			var p := field_to_screen(e.p)
			var col: Color = e.col
			match str(e.k):
				"hit":
					if age < 140.0:
						var k := age / 140.0
						draw_arc(p, rad * (1.0 + 0.5 * k), 0.0, TAU, 48, Color(col, 1.0 - k), 3.0, true)
				"miss":
					var k := clampf(1.0 - age / 450.0, 0.0, 1.0)
					var d := rad * 0.45
					draw_line(p + Vector2(-d, -d), p + Vector2(d, d), Color(col, k), 3.0, true)
					draw_line(p + Vector2(-d, d), p + Vector2(d, -d), Color(col, k), 3.0, true)
				"text":
					var k := clampf(1.0 - age / OrbitTutorial.FX_MS, 0.0, 1.0)
					_center_text(p + Vector2(0, -rad * OrbitTutorial.ORBIT_K - 14.0 - age * 0.012),
							str(e.s), 17, Color(col, k))

	## Belegung unten links: Form + Taste (echte Belegung aus den Settings).
	func _draw_legend() -> void:
		if tut.step < OrbitTutorial.SAT:
			return
		var r := field_rect()
		var x := 22.0
		var y := size.y - 34.0
		if r.position.x < 220.0:
			y = r.end.y + 20.0
			if y > size.y - 14.0:
				return
		var keys := [OrbitNote.KEY_A]
		if tut.step >= OrbitTutorial.KEYS:
			keys.append(OrbitNote.KEY_B)
		if tut.step >= OrbitTutorial.ACCENT:
			keys.append(OrbitNote.KEY_ACCENT)
		for key in keys:
			_body(Vector2(x + 9.0, y - 5.0), 9.0, key, 0.95)
			var txt := tut.legend_text(key)
			draw_string(font, Vector2(x + 26.0, y + 1.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
					Color(UiTheme.TEXT, 0.8))
			x += 26.0 + font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 26.0

	func _center_text(p: Vector2, text: String, fs: int, col: Color) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(p.x - w * 0.5, p.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# ---------------------------------------------------------------------------
# Formen
# ---------------------------------------------------------------------------

static func key_color(key: int) -> Color:
	return COL_B if key == OrbitNote.KEY_B else COL_A


## Abgerundetes Quadrat (halbe Kantenlaenge h, Eckradius rad) als Polygon.
static func rsquare(c: Vector2, h: float, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var e := h - rad
	var corners := [Vector2(e, -e), Vector2(e, e), Vector2(-e, e), Vector2(-e, -e)]
	for i in 4:
		for j in 7:
			var a := -PI * 0.5 + PI * 0.5 * (float(i) + float(j) / 6.0)
			pts.append(c + corners[i] + Vector2(cos(a), sin(a)) * rad)
	return pts


## Halbe Scheibe: links (A) oder rechts (B).
static func half_disk(c: Vector2, rad: float, left: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var a0 := PI * 0.5 if left else -PI * 0.5
	for j in 25:
		var a := a0 + PI * float(j) / 24.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	return pts


# ---------------------------------------------------------------------------
# Gesehen-Merker (eigene Datei)
# ---------------------------------------------------------------------------

static func is_seen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(seen_path) != OK:
		return false
	return bool(cfg.get_value("tutorial", "seen", false))


static func mark_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("tutorial", "seen", true)
	cfg.save(seen_path)


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark_seen()
	var bg := ColorRect.new()
	bg.color = UiTheme.BG.darkened(0.25)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_field = Field.new()
	_field.tut = self
	add_child(_field)
	_build_ui()
	_build_sound()
	_start_usec = Time.get_ticks_usec()
	var shot := OS.get_cmdline_args().has("--shot-tutorial")
	if shot:
		manual_clock = true
		bot = true
	if DisplayServer.get_name() != "headless" and not shot:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	enter_step(AIM)
	if shot:
		_run_shots.call_deferred()


func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_ui() -> void:
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.custom_minimum_size = Vector2(760, 0)
	top.offset_left = -380
	top.offset_right = 380
	top.offset_top = 18
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_step_lbl = _label(13, UiTheme.DIM)
	_step_lbl.add_theme_font_override("font", UiTheme.heading_font(1))
	top.add_child(_step_lbl)
	_title_lbl = _label(28, UiTheme.TEXT)
	_title_lbl.add_theme_font_override("font", UiTheme.heading_font(0))
	top.add_child(_title_lbl)
	_body_lbl = _label(17, Color(UiTheme.TEXT, 0.86))
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_body_lbl)
	_pip_row = HBoxContainer.new()
	_pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_pip_row.add_theme_constant_override("separation", 8)
	_pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_pip_row)
	_feedback = _label(15, UiTheme.DIM)
	top.add_child(_feedback)

	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 8)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_bar.offset_left = -420
	_bar.offset_top = 14
	_bar.offset_right = -14
	_bar.offset_bottom = 46
	_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_bar.alignment = BoxContainer.ALIGNMENT_END
	add_child(_bar)
	_skip_btn = Button.new()
	_skip_btn.focus_mode = Control.FOCUS_NONE
	UiTheme.style_ghost_button(_skip_btn, 6)
	_skip_btn.pressed.connect(skip_step)
	_bar.add_child(_skip_btn)
	_quit_btn = Button.new()
	_quit_btn.focus_mode = Control.FOCUS_NONE
	UiTheme.style_ghost_button(_quit_btn, 6)
	_quit_btn.pressed.connect(quit_tutorial)
	_bar.add_child(_quit_btn)
	_update_buttons()


func _update_buttons() -> void:
	_skip_btn.text = tr("Schritt überspringen  (Tab)")
	_quit_btn.text = tr("Beenden  (Esc)")


func _label(size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


func _build_sound() -> void:
	_tick_player = AudioStreamPlayer.new()
	_tick_player.stream = _tick_stream()
	_tick_player.volume_db = -14.0
	add_child(_tick_player)
	_hit_player = AudioStreamPlayer.new()
	_hit_player.stream = Sfx.hit_stream()
	_hit_player.volume_db = -7.0
	add_child(_hit_player)


## Leiser Holz-Tick fuer das Metronom (kurzer Sinus mit schnellem Abklingen).
static func _tick_stream() -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * 0.05)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var s := sin(TAU * 1250.0 * t) * exp(-t * 90.0) * minf(t / 0.002, 1.0)
		data.encode_s16(i * 2, int(clampf(s * 0.45, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


# ---------------------------------------------------------------------------
# Texte
# ---------------------------------------------------------------------------

func title_for(s: int) -> String:
	match s:
		AIM: return tr("Zielen")
		SAT: return tr("Der Satellit")
		KEYS: return tr("Zwei Tasten")
		ACCENT: return tr("Akzent")
		HOLD: return tr("Halten")
		SKILL: return tr("Sprung und Folge")
	return tr("Probe-Runde")


func body_for(s: int) -> String:
	match s:
		AIM: return tr("Leg den Cursor auf das Ziel und bleib kurz drauf.")
		SAT: return tr("Der Satellit kreist einmal pro Schlag, die Punkte zählen die Runden. Steht er oben: %s drücken.") % key_label(0)
		KEYS: return tr("Kühle Scheibe: %s.  Warmes Quadrat: %s.  Falsche Taste = Miss.") % [key_label(0), key_label(1)]
		ACCENT: return tr("Scheibe mit weißem Ring: %s und %s zugleich.") % [key_label(0), key_label(1)]
		HOLD: return tr("Drücken, halten und mit dem Cursor der Kugel folgen. Erst am Ende loslassen.")
		SKILL: return tr("Weite Sprünge, dann eine schnelle Folge: dicht folgende Ziele wechseln die Taste, %s %s %s %s.") % [key_label(0), key_label(1), key_label(0), key_label(1)]
	return tr("Alles zusammen, mit Wertung.")


func goal_for(s: int) -> String:
	match s:
		AIM: return tr("3 Ziele")
		SAT, KEYS: return tr("%d Treffer") % NEED[s]
		ACCENT: return tr("3 Akzente")
		HOLD: return tr("2 Halten bis zum Ende")
		SKILL: return tr("%d von %d treffen") % [SKILL_MIN_HITS, pattern(SKILL, 0.0, 1000.0, 0).size()]
	return ""


## Kurzname von Taste A (0) bzw. B (1) aus den Settings.
func key_label(key: int) -> String:
	return UiTheme.key_short(Settings.orbit_key_inner if key == 0 else Settings.orbit_key_outer)


## Beschriftung im naechsten Ziel: "Z", "X", Akzent "Z+X".
func key_caption(key: int) -> String:
	if key == OrbitNote.KEY_ACCENT:
		return "%s+%s" % [key_label(0), key_label(1)]
	return key_label(key)


## Legende: "A  Z · Maus links".
func legend_text(key: int) -> String:
	match key:
		OrbitNote.KEY_A: return "A  %s · %s" % [key_label(0), tr("Maus links")]
		OrbitNote.KEY_B: return "B  %s · %s" % [key_label(1), tr("Maus rechts")]
	return "%s  %s+%s" % [tr("Akzent"), key_label(0), key_label(1)]


## Kurzer Text am Ort und Hinweis oben je Fehlergrund.
func reason_short(code: String) -> String:
	match code:
		"aim": return tr("daneben")
		"key": return tr("falsche Taste")
		"early": return tr("zu früh")
		"lock": return tr("erst das vordere")
		"both": return tr("beide Tasten")
		"release": return tr("losgelassen")
		"lost": return tr("Kugel verloren")
	return tr("verpasst")


func reason_hint(code: String, key: int) -> String:
	match code:
		"aim": return tr("Daneben: erst den Cursor auf das Ziel legen.")
		"key": return tr("Falsche Taste = Miss. Dieses Ziel braucht %s.") % key_caption(key)
		"early": return tr("Zu früh: warte, bis der Satellit oben ist.")
		"lock": return tr("Erst das vordere Ziel (das hellste).")
		"both": return tr("Akzent: beide Tasten zugleich.")
		"release": return tr("Zu früh losgelassen: halte bis zum Ende.")
		"lost": return tr("Kugel verloren: bleib mit dem Cursor auf ihr.")
	return tr("Verpasst: drück, wenn der Satellit oben ist.")


func _update_texts() -> void:
	_step_lbl.text = tr("Schritt %d von %d") % [step + 1, STEP_COUNT]
	_title_lbl.text = title_for(step)
	_body_lbl.text = body_for(step)
	var goal := goal_for(step)
	if _say_t == -INF:
		_feedback.text = goal
		_feedback.add_theme_color_override("font_color", UiTheme.DIM)
	_update_pips()


func _update_pips() -> void:
	var need := NEED[step] if step != TRIAL else 0
	while _pips.size() < need:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(26, 4)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pip_row.add_child(pip)
		_pips.append(pip)
	for i in _pips.size():
		_pips[i].visible = i < need
		_pips[i].color = UiTheme.ACCENT if i < success else Color(UiTheme.TEXT, 0.16)
	_pip_row.visible = need > 1


func _say(text: String, col: Color = UiTheme.TEXT) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", col)
	_say_t = t_ms


# ---------------------------------------------------------------------------
# Schritte und Runden
# ---------------------------------------------------------------------------

func enter_step(s: int) -> void:
	step = clampi(s, AIM, TRIAL)
	success = 0
	_round = 0
	_round_over = false
	_done_t = -1.0
	_aim_since = -1.0
	_say_t = -INF
	fx = []
	trial_stats = {}
	_release_all()
	_bot_idx = 0
	_bot_release = [-1.0, -1.0]
	_feedback.text = ""
	_beat_ms = 60000.0 / BPMS[step]
	_t0 = t_ms + _beat_ms * 0.5
	_last_beat = -1
	core = null
	notes = []
	if step == AIM:
		_aim_pos = AIM_SPOTS[0]
	else:
		_start_round(t_ms)
	_update_texts()


func skip_step() -> void:
	if finished:
		return
	if step == TRIAL:
		_show_result(false)
	else:
		enter_step(step + 1)


func quit_tutorial() -> void:
	mark_seen()
	if manual_clock:
		return
	get_tree().change_scene_to_file.call_deferred(BROWSER)


## Naechster Beat-Tick ab t (Anker _t0).
func next_tick(t: float) -> float:
	return _t0 + ceilf((t - _t0) / _beat_ms - 0.0001) * _beat_ms


func _start_round(t: float) -> void:
	var t0 := next_tick(t) + (_beat_ms if _round > 0 else 0.0)
	notes = pattern(step, t0, _beat_ms, _round)
	_round += 1
	core = OrbitCore.new()
	# Anti-Mash wie im Spiel: falsche Taste auf das offene Ziel = Miss (Hinweis "key").
	core.setup(notes, OD, {"NF": true}, RADIUS)
	core.note_judged.connect(_on_judged)
	core.hold_started.connect(_on_hold_started)
	core.press_missed.connect(_on_press_missed)
	core.key_pressed.connect(_on_key_pressed)
	core.cursor_moved(_cursor, t)
	_judged_n = 0
	_round_hits = 0
	_half_accent_t = -INF
	_bot_idx = 0


## Satelliten-Daten setzen: Runde = ein Beat (unter 330 ms zwei), Erscheinen auf
## dem letzten Beat-Tick <= time - laps * lap.
static func _place(n: OrbitNote, t0: float, bm: float, laps: int) -> OrbitNote:
	n.lap_ms = bm * 2.0 if bm < 330.0 else bm
	n.laps = laps
	var want := n.time_ms - float(laps) * n.lap_ms
	n.spawn_ms = t0 + floorf((want - t0) / bm + 0.0001) * bm
	return n


static func _tap(t0: float, bm: float, laps: int, beat: float, p: Vector2, key: int) -> OrbitNote:
	var lap := bm * 2.0 if bm < 330.0 else bm
	return _place(OrbitNote.make_target(t0 + laps * lap + beat * bm, p, key), t0, bm, laps)


static func _hold(t0: float, bm: float, laps: int, beat: float, beats: float,
		a: Vector2, c: Vector2, b: Vector2, key: int) -> OrbitNote:
	var lap := bm * 2.0 if bm < 330.0 else bm
	var path := PackedVector2Array()
	for j in 13:
		var k := float(j) / 12.0
		path.append(a.lerp(c, k).lerp(c.lerp(b, k), k))
	var t := t0 + laps * lap + beat * bm
	return _place(OrbitNote.make_hold(t, t + beats * bm, path, key), t0, bm, laps)


## Ziele einer Runde. t0 = Beat-Tick, an dem das erste Ziel erscheint;
## bm = Beat (ms); rnd = Rundennummer (Positionen/Tasten wechseln).
static func pattern(s: int, t0: float, bm: float, rnd: int) -> Array[OrbitNote]:
	var out: Array[OrbitNote] = []
	var L: int = LAPS[clampi(s, 0, TRIAL)]
	var flip := rnd % 2 == 1
	var fy := func(p: Vector2) -> Vector2: return Vector2(p.x, 1.0 - p.y) if flip else p
	match s:
		SAT:
			out.append(_tap(t0, bm, L, 0.0, SAT_SPOTS[rnd % SAT_SPOTS.size()], OrbitNote.KEY_A))
		KEYS:
			var y := 0.42 + 0.08 * float(rnd % 3)
			var k0 := OrbitNote.KEY_B if flip else OrbitNote.KEY_A
			out.append(_tap(t0, bm, L, 0.0, Vector2(0.34, y), k0))
			out.append(_tap(t0, bm, L, 2.0, Vector2(0.66, 1.0 - y), 1 - k0))
		ACCENT:
			out.append(_tap(t0, bm, L, 0.0, fy.call(Vector2(0.34, 0.55)),
					OrbitNote.KEY_B if flip else OrbitNote.KEY_A))
			out.append(_tap(t0, bm, L, 2.0, fy.call(Vector2(0.62, 0.42)), OrbitNote.KEY_ACCENT))
		HOLD:
			out.append(_hold(t0, bm, L, 0.0, 2.0, fy.call(Vector2(0.3, 0.6)), fy.call(Vector2(0.5, 0.3)),
					fy.call(Vector2(0.7, 0.58)), OrbitNote.KEY_B if flip else OrbitNote.KEY_A))
		SKILL:
			out.append(_tap(t0, bm, L, 0.0, Vector2(0.16, 0.3), OrbitNote.KEY_A))
			out.append(_tap(t0, bm, L, 1.0, Vector2(0.84, 0.7), OrbitNote.KEY_B))
			out.append(_tap(t0, bm, L, 2.0, Vector2(0.16, 0.7), OrbitNote.KEY_A))
			out.append(_tap(t0, bm, L, 3.0, Vector2(0.84, 0.3), OrbitNote.KEY_B))
			for j in 4:
				out.append(_tap(t0, bm, L, 4.0 + 0.5 * j, Vector2(0.34 + 0.105 * j, 0.55 - 0.08 * (j % 2)),
						OrbitNote.KEY_A if j % 2 == 0 else OrbitNote.KEY_B))
			out.append(_tap(t0, bm, L, 6.0, Vector2(0.5, 0.26), OrbitNote.KEY_ACCENT))
		TRIAL:
			out.append(_tap(t0, bm, L, 0.0, Vector2(0.3, 0.4), OrbitNote.KEY_A))
			out.append(_tap(t0, bm, L, 1.0, Vector2(0.55, 0.28), OrbitNote.KEY_B))
			out.append(_tap(t0, bm, L, 2.0, Vector2(0.76, 0.5), OrbitNote.KEY_A))
			out.append(_tap(t0, bm, L, 3.0, Vector2(0.52, 0.66), OrbitNote.KEY_ACCENT))
			out.append(_hold(t0, bm, L, 4.0, 2.0, Vector2(0.26, 0.7), Vector2(0.2, 0.45),
					Vector2(0.36, 0.3), OrbitNote.KEY_B))
			out.append(_tap(t0, bm, L, 7.0, Vector2(0.62, 0.3), OrbitNote.KEY_A))
			out.append(_tap(t0, bm, L, 7.5, Vector2(0.71, 0.36), OrbitNote.KEY_B))
			out.append(_tap(t0, bm, L, 8.0, Vector2(0.80, 0.42), OrbitNote.KEY_A))
			out.append(_tap(t0, bm, L, 9.0, Vector2(0.5, 0.52), OrbitNote.KEY_B))
			out.append(_tap(t0, bm, L, 10.0, Vector2(0.2, 0.3), OrbitNote.KEY_A))
			out.append(_tap(t0, bm, L, 11.0, Vector2(0.8, 0.72), OrbitNote.KEY_B))
			out.append(_tap(t0, bm, L, 12.0, Vector2(0.5, 0.4), OrbitNote.KEY_ACCENT))
	return out


func _add_success() -> void:
	success += 1
	_update_pips()


func _end_round(t: float) -> void:
	if step == TRIAL:
		trial_stats = core.stats()
		_done_t = t
		return
	if step == SKILL:
		if _round_hits >= SKILL_MIN_HITS:
			_add_success()
		else:
			_say(tr("%d von %d getroffen. Noch einmal.") % [_round_hits, notes.size()], UiTheme.TEXT)
	if success >= NEED[step]:
		_done_t = t
		_say(tr("Geschafft."), UiTheme.GOOD)
		return
	_start_round(t)


# ---------------------------------------------------------------------------
# Uhr
# ---------------------------------------------------------------------------

func _process(_d: float) -> void:
	if manual_clock:
		return
	t_ms = float(Time.get_ticks_usec() - _start_usec) / 1000.0
	tick()


func advance(ms: float) -> void:
	t_ms += ms
	tick()


func tick() -> void:
	if finished:
		return
	var t := t_ms
	if bot:
		_bot_tick(t)
	_metronome(t)
	if core != null:
		core.update(t)
	if step == AIM and _done_t < 0.0:
		_update_aim(t)
	while not fx.is_empty() and t - float(fx[0].t) > FX_MS:
		fx.pop_front()
	if _say_t > -INF and t - _say_t > SAY_MS and _done_t < 0.0:
		_say_t = -INF
		_feedback.text = goal_for(step)
		_feedback.add_theme_color_override("font_color", UiTheme.DIM)
	if _field != null:
		_field.queue_redraw()
	if _done_t >= 0.0:
		if t - _done_t >= DONE_PAUSE_MS:
			if step == TRIAL:
				_show_result(true)
			else:
				enter_step(step + 1)
		return
	if _round_over:
		_round_over = false
		_end_round(t)


func _metronome(t: float) -> void:
	var b := floori((t - _t0) / _beat_ms)
	if b == _last_beat:
		return
	_last_beat = b
	if not manual_clock and _tick_player != null and step != AIM:
		_tick_player.play()


# ---------------------------------------------------------------------------
# Schritt 1: Zielen
# ---------------------------------------------------------------------------

func on_target() -> bool:
	return _moved and _cursor.distance_to(_aim_pos) <= RADIUS * OrbitCore.AIM_RADIUS


func aim_progress() -> float:
	if _aim_since < 0.0:
		return 0.0
	return clampf((t_ms - _aim_since) / AIM_DWELL_MS, 0.0, 1.0)


func _update_aim(t: float) -> void:
	if on_target():
		if _aim_since < 0.0:
			_aim_since = t
		elif t - _aim_since >= AIM_DWELL_MS:
			_aim_since = -1.0
			_play_hit()
			fx.append({"k": "hit", "p": _aim_pos, "t": t, "col": Color.WHITE, "s": ""})
			_add_success()
			if success >= NEED[AIM]:
				_done_t = t
				_say(tr("Geschafft."), UiTheme.GOOD)
			else:
				_aim_pos = AIM_SPOTS[success % AIM_SPOTS.size()]
	else:
		if _aim_since >= 0.0 and t - _aim_since > 200.0:
			_fail("aim", _aim_pos, OrbitNote.KEY_A)
		_aim_since = -1.0


# ---------------------------------------------------------------------------
# Wertung (Signale von OrbitCore)
# ---------------------------------------------------------------------------

## Halten-Ziel index laeuft gerade (Kopf getroffen, Ende offen).
func hold_active(index: int) -> bool:
	return core != null and core.active_holds().has(index)


## Sichtbare Ziele in Zeitordnung: erschienen, nicht gewertet (Halten bis zum Ende).
func visible_notes() -> Array:
	var out := []
	if core == null:
		return out
	for i in notes.size():
		if notes[i].spawn_ms <= t_ms and (not core.is_judged(i) or hold_active(i)):
			out.append(i)
	return out


## Naechstes offenes Ziel (null = keins).
func next_open() -> OrbitNote:
	if core == null:
		return null
	for i in notes.size():
		if not core.is_judged(i):
			return notes[i]
	return null


func _on_judged(index: int, res: Dictionary) -> void:
	_judged_n += 1
	var n := notes[index]
	var q := int(res.get("quality", 5))
	var p := n.pos_at(n.end_ms) if bool(res.get("hold_end", false)) else n.pos
	if q == OrbitCore.Quality.MISS:
		var code := "miss"
		if str(res.get("miss_kind", "")) == "DROP":
			code = "release" if str(res.get("drop_reason", "")) == "release" else "lost"
		elif n.key == OrbitNote.KEY_ACCENT and t_ms - _half_accent_t < 400.0:
			code = "both"
		_miss_idx = index
		_fail(code, p, n.key)
	else:
		_round_hits += 1
		_play_hit()
		var col: Color = TIER_COLS[clampi(q, 0, 5)]
		fx.append({"k": "hit", "p": p, "t": t_ms, "col": key_color(n.key).lightened(0.3), "s": ""})
		_add_text(p, col, tr(OrbitCore.TIER_NAMES[q]))
		match step:
			SAT, KEYS:
				_add_success()
			ACCENT:
				if n.key == OrbitNote.KEY_ACCENT:
					_add_success()
			HOLD:
				if bool(res.get("held", false)):
					_add_success()
	if _judged_n >= notes.size():
		_round_over = true


func _on_hold_started(index: int, _q: int) -> void:
	_play_hit()
	fx.append({"k": "hit", "p": notes[index].pos, "t": t_ms, "col": key_color(notes[index].key), "s": ""})


func _on_press_missed(pos: Vector2, _key: int, reason: String) -> void:
	var n := next_open()
	if reason == "wrong":   # Anti-Mash: das Ziel ist eben Miss geworden, Grund am Ziel nennen
		reason = "key"
		if _miss_idx >= 0 and _miss_idx < notes.size():
			n = notes[_miss_idx]
	_press_signal = reason
	_fail(reason, n.pos if n != null and reason != "aim" else pos, n.key if n != null else 0)


func _on_key_pressed(_key: int, hit: bool) -> void:
	if hit:
		_press_signal = "hit"
	elif _press_signal == "":
		_press_signal = "nohit"


func _fail(code: String, p: Vector2, key: int) -> void:
	fb_reason = code
	fb_count += 1
	if code == "miss" or code == "lost" or code == "release" or code == "both":
		fx.append({"k": "miss", "p": p, "t": t_ms, "col": TIER_COLS[5], "s": ""})
	_add_text(p, UiTheme.BAD.lightened(0.15), reason_short(code))
	_say(reason_hint(code, key), UiTheme.BAD.lightened(0.2))


## Text am Ort; ein neuer Text an derselben Stelle ersetzt den alten.
func _add_text(p: Vector2, col: Color, text: String) -> void:
	fx = fx.filter(func(e): return str(e.k) != "text" or Vector2(e.p).distance_to(p) > RADIUS)
	fx.append({"k": "text", "p": p, "t": t_ms, "col": col, "s": text})


func _play_hit() -> void:
	if not manual_clock and _hit_player != null:
		_hit_player.play()


# ---------------------------------------------------------------------------
# Eingabe (wie OrbitGame: Cursor im Feld, Taste A/B aus den Settings)
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	handle_input(event)


func handle_input(event: InputEvent) -> void:
	if finished:
		return
	if event is InputEventMouseMotion:
		_aim_at(event.position)
	elif event is InputEventMouseButton:
		var key := -1
		if event.button_index == MOUSE_BUTTON_LEFT:
			key = 0
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			key = 1
		if key < 0 or (event.pressed and _bar.get_global_rect().has_point(event.position)):
			return
		_aim_at(event.position)
		_press(key, 0, event.pressed)
	elif event is InputEventKey and not event.echo:
		var key := Settings.orbit_ring_for_key(event.keycode)
		if key >= 0:
			_press(key, 1, event.pressed)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.keycode == KEY_TAB:
			skip_step()
			get_viewport().set_input_as_handled()
		elif event.pressed and event.keycode == KEY_ESCAPE:
			quit_tutorial()
			get_viewport().set_input_as_handled()


## Bildschirmpunkt (global) eines Feldpunkts.
func field_to_global(p: Vector2) -> Vector2:
	return _field.global_position + _field.field_to_screen(p)


func _aim_at(pos: Vector2) -> void:
	_cursor = _field.screen_to_field(pos - _field.global_position)
	_moved = true
	if core != null:
		core.cursor_moved(_cursor, t_ms)


func _press(key: int, source: int, down: bool) -> void:
	var was: bool = _held[key][0] or _held[key][1]
	_held[key][source] = down
	var now: bool = _held[key][0] or _held[key][1]
	if now == was or core == null or step == AIM:
		return
	if not now:
		core.key_up(key, t_ms)
		return
	_press_signal = ""
	core.key_down(key, t_ms)
	if _press_signal == "":
		# Erste Taste eines Akzents: wartet auf die zweite.
		_half_accent_t = t_ms
	elif _press_signal == "nohit":
		var n := next_open()
		if n != null and n.spawn_ms <= t_ms and n.time_ms - t_ms > core.w50:
			_fail("early", n.pos, n.key)


func _release_all() -> void:
	for k in 2:
		var was: bool = _held[k][0] or _held[k][1]
		_held[k] = [false, false]
		if was and core != null:
			core.key_up(k, t_ms)


# ---------------------------------------------------------------------------
# Bot (Test und Harness): spielt ueber echte Eingabe-Events
# ---------------------------------------------------------------------------

func _bot_move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = field_to_global(p + BOT_AIM_OFFSET)
	handle_input(ev)


func _bot_key(key: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = Settings.orbit_key_inner if key == 0 else Settings.orbit_key_outer
	ev.pressed = down
	handle_input(ev)


## Der Bot liegt auf dem naechsten Ziel (bzw. der Kugel) und drueckt zur Zielzeit.
func _bot_tick(t: float) -> void:
	for k in 2:
		if _bot_release[k] >= 0.0 and _bot_release[k] <= t:
			_bot_key(k, false)
			_bot_release[k] = -1.0
	if step == AIM:
		_bot_move(_aim_pos)
		return
	if core == null:
		return
	var holds := core.active_holds()
	if not holds.is_empty():
		_bot_move(notes[int(holds[0])].pos_at(t))
	elif _bot_idx < notes.size():
		_bot_move(notes[_bot_idx].pos)
	while _bot_idx < notes.size() and notes[_bot_idx].time_ms <= t + BOT_LEAD_MS:
		var n := notes[_bot_idx]
		_bot_idx += 1
		_bot_move(n.pos)
		var keys := [0, 1] if n.key == OrbitNote.KEY_ACCENT else [n.key]
		for k in keys:
			_bot_key(k, true)
			_bot_release[k] = n.end_ms + 10.0 if n.is_hold else t + BOT_TAP_MS


# ---------------------------------------------------------------------------
# Ergebnis der Probe-Runde
# ---------------------------------------------------------------------------

## Karriere ist optional: nur anbieten, falls die Klasse existiert.
func _offer_career() -> void:
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "OrbitCareer":
			var s = load(str(c.get("path", "")))
			if s != null and s.has_method("offer"):
				s.offer(career_path)
			return


func trial_accuracy() -> float:
	return float(trial_stats.get("accuracy", 0.0))


func trial_grade() -> String:
	return str(trial_stats.get("grade", "D"))


func _show_result(completed: bool) -> void:
	if finished:
		return
	finished = true
	_release_all()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if completed:
		_offer_career()
	_field.queue_redraw()
	_bar.visible = false
	_step_lbl.text = tr("Probe")
	_title_lbl.text = tr("Probe-Runde geschafft") if completed else tr("Probe-Runde")
	_body_lbl.text = tr("Das war Orbit. Tasten änderst du in den Einstellungen unter Orbit.")
	_pip_row.visible = false
	_feedback.text = ""
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	box.offset_left = -260
	box.offset_right = 260
	box.offset_top = -110
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	_result = box
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 28)
	box.add_child(head)
	var grade := _label(64, UiTheme.ACCENT)
	grade.add_theme_font_override("font", UiTheme.heading_font(0))
	grade.text = trial_grade() if completed else "-"
	head.add_child(grade)
	var acc_box := VBoxContainer.new()
	acc_box.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(acc_box)
	var cap := _label(12, UiTheme.DIM)
	cap.text = tr("GENAUIGKEIT")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	acc_box.add_child(cap)
	var acc := _label(30, UiTheme.TEXT)
	acc.add_theme_font_override("font", UiTheme.heading_font(0))
	acc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	acc.text = UiTheme.fmt_pct(trial_accuracy() * 100.0)
	acc_box.add_child(acc)
	box.add_child(UiTheme.hairline())
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 22)
	box.add_child(grid)
	var counts := ["n_max", "n300", "n200", "n100", "n50", "n_miss"]
	for q in 6:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_l := _label(12, TIER_COLS[q])
		name_l.text = tr("VERFEHLT") if q == 5 else tr(OrbitCore.TIER_NAMES[q])
		cell.add_child(name_l)
		var n_l := _label(22, UiTheme.TEXT)
		n_l.text = str(int(trial_stats.get(counts[q], 0)))
		cell.add_child(n_l)
		grid.add_child(cell)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	box.add_child(gap)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var again := Button.new()
	again.text = tr("Nochmal")
	again.custom_minimum_size = Vector2(150, 40)
	UiTheme.style_ghost_button(again, 6)
	again.pressed.connect(retry_trial)
	row.add_child(again)
	var done := Button.new()
	done.text = tr("Zu den Maps")
	done.custom_minimum_size = Vector2(180, 40)
	UiTheme.style_button(done, true, 6)
	done.pressed.connect(quit_tutorial)
	row.add_child(done)


func retry_trial() -> void:
	if _result != null:
		_result.queue_free()
		_result = null
	finished = false
	_bar.visible = true
	if DisplayServer.get_name() != "headless" and not manual_clock:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	enter_step(TRIAL)


# ---------------------------------------------------------------------------
# Harness: --shot-tutorial (Bot, simulierte Uhr, ein Bild je Schritt)
# ---------------------------------------------------------------------------

func _shot_dir() -> String:
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-out="):
			return a.trim_prefix("--shot-out=")
	return OS.get_user_data_dir()


func _run_shots() -> void:
	var dir := _shot_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var langs: Array = [TranslationServer.get_locale().substr(0, 2)]
	if not Array(OS.get_cmdline_args()).any(func(a): return str(a).begins_with("--lang=")):
		langs = ["de", "en"]
	for lang in langs:
		TranslationServer.set_locale(lang)
		_update_buttons()
		await _shots_one(dir, lang)
	get_tree().quit(0)


func _step_until(cond: Callable, limit: int = 6000) -> void:
	for i in limit:
		if cond.call():
			return
		advance(1000.0 / 60.0)


## Bild je Schritt: nach dem ersten Erfolg, wenn der Satellit gut sichtbar laeuft.
func _shots_one(dir: String, lang: String) -> void:
	if _result != null:
		retry_trial()
	bot = true
	for s in STEP_COUNT:
		enter_step(s)
		match s:
			AIM:
				_step_until(func(): return success >= 1 and aim_progress() > 0.5)
			HOLD:
				_step_until(func(): return core != null and not core.active_holds().is_empty() \
						and t_ms > notes[0].time_ms + _beat_ms * 0.8)
			SKILL:
				_step_until(func(): return _judged_n >= 4 and next_open() != null \
						and next_open().time_ms - t_ms < _beat_ms * 0.3)
			TRIAL:
				_step_until(func(): return _judged_n >= 3 and next_open() != null \
						and next_open().time_ms - t_ms < _beat_ms * 0.5)
			KEYS:
				_step_until(func(): return success >= 2 and visible_notes().size() >= 2 \
						and next_open().time_ms - t_ms < next_open().lap_ms * 0.6)
			ACCENT:
				_step_until(func(): return success >= 1 and next_open() != null \
						and next_open().key == OrbitNote.KEY_ACCENT and visible_notes().size() == 1 \
						and next_open().time_ms - t_ms < next_open().lap_ms * 1.4)
			_:
				_step_until(func(): return success >= 1 and next_open() != null \
						and next_open().time_ms - t_ms < next_open().lap_ms * 1.4 \
						and next_open().time_ms - t_ms > next_open().lap_ms * 1.25)
		await _save("orbit_tut_%s_%d.png" % [lang, s + 1], dir)
	# Fehlerbild: in Schritt 3 die andere Taste druecken.
	bot = false
	enter_step(KEYS)
	var n := notes[0]
	_bot_move(n.pos)
	_step_until(func(): return t_ms >= n.time_ms - 40.0)
	_bot_key(1 - n.key, true)
	_bot_key(1 - n.key, false)
	advance(90.0)
	await _save("orbit_tut_%s_fehler.png" % lang, dir)
	bot = true
	enter_step(TRIAL)
	_step_until(func(): return finished, 9000)
	await _save("orbit_tut_%s_result.png" % lang, dir)


func _save(file: String, dir: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var p := dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(p)
	print("SHOT gespeichert: " + p)
