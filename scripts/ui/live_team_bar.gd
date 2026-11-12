class_name LiveTeamBar
extends Control

## Ingame-Leiste oben: Rot gegen Blau als geteilter Balken mit Live-Summen.
## setup({names:[a,b], totals:[a,b]?}); set_totals([a,b]) gleitet ruhig.
## Zeichnet selbst; Styleboxen sind vorab angelegt.
## Trace-Versus (trace_mode): je Spieler eine kleine Zeile (Platz, Name, Acc-Balken,
## Acc, Kombo, Fehlknicke), sortiert nach Score; set_rows(rows) bzw. ensure_trace(szene).

const COLS := [Color(1.0, 0.38, 0.45), Color(0.38, 0.65, 1.0)]
const TEXT := Color(0.95, 0.96, 1.0)
const DIM := Color(0.62, 0.64, 0.72)
const BAR_H := 10.0
const MIN_SHARE := 0.08

var _names: Array = ["Rot", "Blau"]
var _totals: Array = [0, 0]
var _shown_share := 0.5
var _target_share := 0.5
var _shown_vals: Array = [0.0, 0.0]
var _txt: Array = ["0", "0"]
var _lead := ""
var _font: Font
var _tween: Tween
var _sb := [StyleBoxFlat.new(), StyleBoxFlat.new()]

const ROW_H := 21.0
const HEAD_H := 17.0
const PAD := 8.0
const TRACE_W := 300.0
const BAD := Color(0.871, 0.443, 0.384)
const LAYER_NAME := "TraceVersusLayer"
var trace_mode := false
var _rows: Array = []
var _bg := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(560, 46)
	_font = get_theme_default_font()


func setup(d: Dictionary) -> void:
	var nm = d.get("names", null)
	if typeof(nm) == TYPE_ARRAY and nm.size() == 2:
		_names = [str(nm[0]), str(nm[1])]
	var tt = d.get("totals", null)
	if typeof(tt) == TYPE_ARRAY and tt.size() == 2:
		_totals = [maxi(0, int(tt[0])), maxi(0, int(tt[1]))]
	else:
		_totals = [0, 0]
	_shown_vals = [float(_totals[0]), float(_totals[1])]
	_target_share = _share(_totals)
	_shown_share = _target_share
	_refresh_text()
	queue_redraw()


func set_totals(totals: Array) -> void:
	if totals.size() != 2:
		return
	var n := [maxi(0, int(totals[0])), maxi(0, int(totals[1]))]
	if n == _totals:
		return
	_totals = n
	_target_share = _share(n)
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_step_share, _shown_share, _target_share, 0.5)
	_tween.tween_method(_step_val.bind(0), _shown_vals[0], float(n[0]), 0.5)
	_tween.tween_method(_step_val.bind(1), _shown_vals[1], float(n[1]), 0.5)


func _share(t: Array) -> float:
	var sum: int = t[0] + t[1]
	if sum <= 0:
		return 0.5
	return clampf(float(t[0]) / float(sum), MIN_SHARE, 1.0 - MIN_SHARE)


func _step_share(v: float) -> void:
	_shown_share = v
	queue_redraw()


func _step_val(v: float, i: int) -> void:
	_shown_vals[i] = v
	_refresh_text()
	queue_redraw()


func _refresh_text() -> void:
	_txt = [UiTheme.fmt_score(int(_shown_vals[0])), UiTheme.fmt_score(int(_shown_vals[1]))]
	var diff := int(_shown_vals[0]) - int(_shown_vals[1])
	_lead = "" if diff == 0 else "+" + UiTheme.fmt_score(absi(diff))


func _draw() -> void:
	if _font == null:
		_font = get_theme_default_font()
	if trace_mode:
		_draw_trace()
		return
	var w := size.x
	var bar_y := size.y - BAR_H - 2.0
	var split := w * _shown_share
	var gap := 2.0
	var r := BAR_H * 0.5
	# Balken: links Rot, rechts Blau, kleine Luecke in der Mitte
	_pill(Rect2(0, bar_y, maxf(split - gap, 0.0), BAR_H), 0, r)
	_pill(Rect2(split + gap, bar_y, maxf(w - split - gap, 0.0), BAR_H), 1, r)
	# Texte: Name + Summe aussen, Vorsprung in der Mitte
	var fs := 15
	var top := bar_y - 7.0
	draw_string(_font, Vector2(0, top), tr(_names[0]), HORIZONTAL_ALIGNMENT_LEFT, w * 0.4, fs, DIM)
	var s0 := _font.get_string_size(tr(_names[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(s0 + 10.0, top), _txt[0], HORIZONTAL_ALIGNMENT_LEFT, w * 0.4, fs + 3, TEXT)
	draw_string(_font, Vector2(0, top), tr(_names[1]), HORIZONTAL_ALIGNMENT_RIGHT, w, fs, DIM)
	var s1 := _font.get_string_size(tr(_names[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(-(s1 + 10.0), top), _txt[1], HORIZONTAL_ALIGNMENT_RIGHT, w, fs + 3, TEXT)
	if _lead != "":
		var col: Color = COLS[0] if _shown_vals[0] > _shown_vals[1] else COLS[1]
		draw_string(_font, Vector2(0, top), _lead, HORIZONTAL_ALIGNMENT_CENTER, w, fs - 1, col)


func _pill(rect: Rect2, idx: int, radius: float) -> void:
	if rect.size.x <= 0.0:
		return
	var sb: StyleBoxFlat = _sb[idx]
	sb.bg_color = COLS[idx]
	var outer := int(radius)
	sb.corner_radius_top_left = outer if idx == 0 else 2
	sb.corner_radius_bottom_left = outer if idx == 0 else 2
	sb.corner_radius_top_right = 2 if idx == 0 else outer
	sb.corner_radius_bottom_right = 2 if idx == 0 else outer
	draw_style_box(sb, rect)


# ---------------------------------------------------------------------------
# Trace-Versus
# ---------------------------------------------------------------------------

## rows: [{ name, score, acc (0..1), combo, miss (-1 = unbekannt), me, done }].
func set_rows(rows: Array) -> void:
	trace_mode = true
	_rows = sorted_rows(rows)
	var h := HEAD_H + ROW_H * _rows.size() + PAD
	custom_minimum_size = Vector2(TRACE_W if custom_minimum_size.x <= 0.0 else custom_minimum_size.x, h)
	size = Vector2(maxf(size.x, custom_minimum_size.x), h)
	queue_redraw()


## Nach Score absteigend, bei Gleichstand weniger Fehlknicke zuerst (stabil nach Name).
static func sorted_rows(rows: Array) -> Array:
	var out := rows.duplicate()
	out.sort_custom(func(a, b):
		var sa := int(a.get("score", 0))
		var sb := int(b.get("score", 0))
		if sa != sb:
			return sa > sb
		var ma := int(a.get("miss", 0))
		var mb := int(b.get("miss", 0))
		if ma != mb:
			return ma < mb
		return str(a.get("name", "")) < str(b.get("name", "")))
	return out


## Zeilen aus Lobby.players (Endergebnis zaehlt, sobald es da ist).
static func rows_from_lobby() -> Array:
	var out: Array = []
	var lb := _lobby()
	if lb == null:
		return out
	var me: int = lb.multiplayer.get_unique_id() if bool(lb.active) else 0
	for id in lb.players:
		var p: Dictionary = lb.players[id]
		var f: Dictionary = p.get("final", {})
		var done := not f.is_empty()
		out.append({
			"name": str(p.get("name", "?")),
			"score": int(f.get("score", 0)) if done else int(p.get("score", 0)),
			"acc": float(f.get("acc", 0.0)) if done else float(p.get("acc", 1.0)),
			"combo": int(p.get("combo", 0)),
			"miss": int(f.get("n_miss", 0)) if done else int(p.get("miss", -1)),
			"me": int(id) == me, "done": done,
		})
	return out


## Live-Leiste in die laufende Trace-Szene haengen (einmal je Szene, ab 2 Spielern).
## Aktualisiert sich ueber Lobby.scores_changed; verschwindet mit dem eigenen Endergebnis.
static func ensure_trace(scene: Node) -> LiveTeamBar:
	var lb := _lobby()
	if scene == null or lb == null or not bool(lb.active) or (lb.players as Dictionary).size() < 2:
		return null
	var have := scene.get_node_or_null(LAYER_NAME + "/Bar")
	if have != null:
		return have as LiveTeamBar
	var layer := CanvasLayer.new()
	layer.name = LAYER_NAME
	layer.layer = 4
	var bar := LiveTeamBar.new()
	bar.name = "Bar"
	bar.trace_mode = true
	bar.custom_minimum_size = Vector2(TRACE_W, 0)
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -TRACE_W - 24.0
	bar.offset_right = -24.0
	bar.offset_top = 48.0
	layer.add_child(bar)
	scene.add_child(layer)
	lb.scores_changed.connect(bar._on_lobby_scores)
	bar._on_lobby_scores()
	if OS.get_cmdline_args().has("--mp-bot"):
		print("MPTRACE versus bar players=%d" % (lb.players as Dictionary).size())
	return bar


## Autoload "Lobby" ohne Bezeichner (Klassen-Skripte kompilieren auch in -s-Tests).
static func _lobby() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Lobby") if tree != null else null


func _on_lobby_scores() -> void:
	var rows := rows_from_lobby()
	for r in rows:
		if bool(r.me) and bool(r.done):
			visible = false  # eigenes Ergebnis steht: Ergebnisbildschirm uebernimmt
	set_rows(rows)


func _draw_trace() -> void:
	var w := size.x
	_bg.bg_color = Color(0.071, 0.067, 0.063, 0.62)
	_bg.set_corner_radius_all(4)
	draw_style_box(_bg, Rect2(Vector2.ZERO, size))
	var fs := 13
	var x_miss := w - PAD
	var x_combo := w - PAD - 72.0
	var x_acc := w - PAD - 120.0
	var cap_y := PAD + 9.0
	draw_string(_font, Vector2(PAD, cap_y), "VERSUS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
	_rstring(tr("ACC"), x_acc, cap_y, 10, DIM)
	_rstring(tr("KOMBO"), x_combo, cap_y, 10, DIM)
	_rstring(tr("FEHLKNICKE"), x_miss, cap_y, 10, DIM)
	var lead_score := int(_rows[0].get("score", 0)) if not _rows.is_empty() else 0
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var y := HEAD_H + PAD + ROW_H * float(i)
		var base := y + 13.0
		var me := bool(r.get("me", false))
		var lead := i == 0 and lead_score > 0
		var name_col := TEXT if me else DIM
		draw_string(_font, Vector2(PAD, base), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				UiTheme.ACCENT if lead else DIM)
		var name_w := x_acc - 50.0 - (PAD + 16.0)
		draw_string(_font, Vector2(PAD + 16.0, base), str(r.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT,
				maxf(name_w, 20.0), fs, name_col)
		var acc := clampf(float(r.get("acc", 0.0)), 0.0, 1.0)
		# Acc-Balken unter dem Namen: 80 % .. 100 % auf die Namensbreite.
		var bw := maxf(name_w, 20.0)
		var bar_r := Rect2(PAD + 16.0, y + 16.5, bw, 2.0)
		draw_rect(bar_r, Color(1, 1, 1, 0.08))
		var fill := clampf((acc - 0.8) / 0.2, 0.0, 1.0)
		var bar_col: Color = UiTheme.ACCENT if lead else Color(UiTheme.ACCENT2, 0.9)
		draw_rect(Rect2(bar_r.position, Vector2(bw * fill, 2.0)), Color(bar_col, 0.85 if me else 0.6))
		_rstring(UiTheme.fmt_num(acc * 100.0, 1) + "%", x_acc, base, fs, name_col)
		_rstring("%dx" % int(r.get("combo", 0)), x_combo, base, fs, name_col)
		var miss := int(r.get("miss", -1))
		_rstring("–" if miss < 0 else str(miss), x_miss, base, fs, BAD if miss > 0 else name_col)


func _rstring(t: String, right_x: float, base_y: float, fs: int, col: Color) -> void:
	var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(right_x - tw, base_y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
