class_name MarathonHud
extends Control

## Marathon-Anzeige im Spiel (2D und 3D): ruhige Zeile oben links unter dem
## Songtitel. "MARATHON · MAP 2 / 3", Titel der laufenden Map, schmale
## Fortschrittsleiste je Map (Graphit, laufende Map in Bernstein). Kurz vor einem
## Uebergang blendet "NÄCHSTE: <Titel>" weich ein und nach dem Wechsel wieder aus.
## Kein Blinken, kein Wackeln: nur Deckkraft, langsam.
## results_table() baut die Tabelle "je Map" fuer den Ergebnis-Reiter.

const X := 24.0
const Y := 56.0
const W := 320.0
## Vorschau "Naechste" ab so vielen ms vor der Uebergangsmitte, bis so lange danach.
const NEXT_BEFORE_MS := 6000.0
const NEXT_AFTER_MS := 1500.0
## Deckkraft-Aenderung je Sekunde (ruhig).
const FADE_PER_S := 1.6

var _run: MarathonRun
var _host: Node
var _cap: Label
var _title: Label
var _next: Label
var _bar: Control
var _cur := -1
var _next_a := 0.0
var _t := 0.0


func setup(run: MarathonRun, host: Node) -> void:
	_run = run
	_host = host
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(X, Y)
	size = Vector2(W, 80)
	_cap = _label(11, UiTheme.DIM)
	_cap.add_theme_font_override("font", UiTheme.heading_font(2))
	_cap.position = Vector2(0, 0)
	_title = _label(14, UiTheme.TEXT)
	_title.position = Vector2(0, 16)
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.position = Vector2(0, 40)
	_bar.size = Vector2(W, 4)
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_next = _label(12, UiTheme.DIM)
	_next.position = Vector2(0, 50)
	_next.modulate.a = 0.0
	_refresh(0)


func _label(fs: int, col: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)
	l.size = Vector2(W, 18)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(l)
	return l


func _now() -> float:
	var clock := MarathonRun.autoload("SyncClock")
	return float(clock.song_time_ms()) if clock != null else 0.0


func _process(delta: float) -> void:
	if _run == null:
		return
	_t = _now()
	var i := _run.map_at(_t)
	if i != _cur:
		_refresh(i)
	# Naechste Map: weich ein- und ausblenden um die Uebergangsmitte.
	var want := 0.0
	var n := _run.segs.size()
	if i + 1 < n:
		var mid := float(_run.segs[i + 1].mid_in)
		if _t >= mid - NEXT_BEFORE_MS:
			want = 1.0
	if i > 0:
		var mid0 := float(_run.segs[i].mid_in)
		if _t < mid0 + NEXT_AFTER_MS:
			want = 1.0
	_next_a = move_toward(_next_a, want, delta * FADE_PER_S)
	_next.modulate.a = _next_a * 0.9
	_bar.queue_redraw()


func _refresh(i: int) -> void:
	_cur = i
	var n: int = _run.segs.size()
	_cap.text = "%s  ·  %s" % [tr("MARATHON"), tr("MAP %d / %d") % [i + 1, n]]
	var m := _run.map_info(i)
	_title.text = "%s — %s" % [str(m.get("artist", "")), str(m.get("title", ""))]
	if i + 1 < n:
		_next.text = "%s  %s" % [tr("NEXT"), str(_run.map_info(i + 1).get("title", ""))]
	elif i > 0:
		_next.text = tr("Last map")


## Leiste: je Map ein Abschnitt (Breite = Anteil an der Gesamtzeit), gespielte
## Abschnitte hell, laufender anteilig in Bernstein.
func _draw_bar() -> void:
	var n: int = _run.segs.size()
	if n == 0:
		return
	var bounds := map_bounds(_run.segs)
	var total := maxf(float(bounds.back()) - float(bounds[0]), 1.0)
	var gap := 3.0
	var x := 0.0
	var w_all := W - gap * float(n - 1)
	for i in n:
		var a := float(bounds[i])
		var b := float(bounds[i + 1])
		var w := w_all * (b - a) / total
		var r := Rect2(x, 0, maxf(w, 1.0), 4)
		_bar.draw_rect(r, Color(1, 1, 1, 0.10))
		var k := clampf((_t - a) / maxf(b - a, 1.0), 0.0, 1.0)
		if k > 0.0:
			var col := UiTheme.ACCENT if i == _cur else Color(UiTheme.TEXT, 0.45)
			_bar.draw_rect(Rect2(x, 0, r.size.x * k, 4), Color(col, 0.8))
		x += w + gap


## Grenzen der Maps auf der Zeitachse (global, ms): [Start, Mitte 1, ..., Ende].
static func map_bounds(segs: Array) -> Array:
	var out: Array = [0.0]
	for i in range(1, segs.size()):
		out.append(float(segs[i].mid_in))
	out.append(maxf(MarathonPlan.timeline_end(segs), float(out.back()) + 1.0))
	return out


## Ergebnis-Reiter "Maps": eine Zeile je Map (Titel, Sterne, Genauigkeit, Kombo,
## Fehler, Punkte). Graphit + Bernstein, Zahlen ueber UiTheme.fmt_*.
static func results_table(run: MarathonRun) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_row([TranslationServer.translate("MAP"), TranslationServer.translate("STARS"),
		TranslationServer.translate("ACCURACY"), TranslationServer.translate("COMBO"),
		TranslationServer.translate("MISSES"), TranslationServer.translate("SCORE")], true, false))
	box.add_child(UiTheme.hairline())
	for i in run.per_map.size():
		var pm: Dictionary = run.per_map[i]
		var m := run.map_info(i)
		var played := int(pm.judged) > 0
		var done := int(pm.judged) >= int(pm.notes)
		var acc := UiTheme.fmt_pct(MarathonRun.map_accuracy(pm)) if played else "–"
		box.add_child(_row([
			"%d  %s" % [i + 1, str(m.get("title", ""))],
			UiTheme.fmt_num(float(m.get("stars", 0.0)), 2),
			acc,
			"%s×" % UiTheme.fmt_score(int(pm.max_combo)) if played else "–",
			UiTheme.fmt_score(int(pm.n_miss)) if played else "–",
			UiTheme.fmt_score(int(pm.score)) if played else "–",
		], false, played and not done))
	return box


static func _row(cells: Array, head: bool, partial: bool) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var widths := [250, 60, 90, 80, 70, 100]
	for c in cells.size():
		var l := Label.new()
		l.text = str(cells[c])
		l.custom_minimum_size = Vector2(widths[c], 0)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if c == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		l.add_theme_font_size_override("font_size", 12 if head else 15)
		var col := UiTheme.DIM if head or partial else UiTheme.TEXT
		l.add_theme_color_override("font_color", col)
		if head:
			l.add_theme_font_override("font", UiTheme.heading_font(1))
		h.add_child(l)
	return h
