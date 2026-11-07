class_name PlayerStatsCard
extends PanelContainer

## Stats-Karte eines Spielers (Multiplayer-Results, Turnier-Ende): Avatar, Name,
## Platz, Score, Acc, Kombo, Judgement-Verteilung, UR, mittlere Abweichung,
## Frueh/Spaet, Hold-Ergebnisse, Trefferfehler-Histogramm und Acc-Verlauf.
## Gross (alles) oder kompakt (Kennzahlen + Verteilungsbalken). Mit info.ref
## (Paket eines zweiten Spielers) zeigt sie Differenzen und blendet dessen
## Graphen als Schatten ein (Direktvergleich).
##
## Ausserdem die Daten-Seite: pack() baut das kleine Endergebnis-Paket (< 2 KB),
## sanitize() klemmt fremde Pakete, merge() summiert mehrere Runden.
## Paket-Schluessel: score, acc (0..1), grade, combo, failed, n_max, n300, n200,
## n100, n50, n_miss, ur, mean (ms, + = spaet), early, late, h_ok, h_drop,
## mods [str], bins [BINS Zaehler, -RANGE_MS..+RANGE_MS], trace [<= TRACE Promille].

const BINS := 21
const TRACE := 40
const RANGE_MS := 105.0
const MAX_COUNT := 1000000

const TAGS := ["MAX", "300", "200", "100", "50", "MISS"]
const KEYS := ["n_max", "n300", "n200", "n100", "n50", "n_miss"]
const GRADES := ["SS", "S", "A", "B", "C", "D", "F"]
const EARLY_COL := Color(0.45, 0.66, 1.0)
const LATE_COL := Color(1.0, 0.70, 0.42)
const CENTER_COL := Color(0.62, 0.95, 0.88)
const UP_COL := Color(0.50, 0.92, 0.66)
const DOWN_COL := Color(1.0, 0.48, 0.52)
const CAPTION := Color(0.66, 0.69, 0.78)
## Wie ResultsScreen (MAX, 300, 200, 100, 50, MISS) — hier dupliziert, damit die
## Karte ohne Autoload-abhaengige Skripte laedt (Headless-Tests).
const QUALITY_COLOR := [
	Color(1.0, 0.85, 0.42), Color(0.84, 0.97, 1.0), Color(0.47, 0.95, 0.62),
	Color(0.42, 0.64, 1.0), Color(0.64, 0.66, 0.72), Color(1.0, 0.38, 0.42),
]
const GRADE_COLOR := {
	"SS": Color(1.0, 0.94, 0.72), "S": Color(1.0, 0.85, 0.25),
	"A": Color(0.4, 1.0, 0.5), "B": Color(0.35, 0.75, 1.0),
	"C": Color(0.9, 0.6, 1.0), "D": Color(1.0, 0.4, 0.4),
}
const RANK_COLS := [Color(1.0, 0.85, 0.3), Color(0.78, 0.82, 0.9), Color(0.85, 0.55, 0.35)]
## Kartenfarben im Vergleich: A = Akzent (cyan), B = gedaempftes Pink.
const SIDE_A := Color(0.30, 0.82, 1.0)
const SIDE_B := Color(1.0, 0.56, 0.84)

var _compact := false
var _s := 1.0  # Schrift-/Hoehen-Faktor (schmale Karten)
var _accent := SIDE_A
var _top_line := false


# ---------------------------------------------------------------------------
# Daten
# ---------------------------------------------------------------------------

static func _num(v: Variant, lo: float, hi: float, fallback: float = 0.0) -> float:
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return fallback
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return fallback
	return clampf(f, lo, hi)


## Paket aus dem Spielstand bauen. s = ManiaCore.stats(), offsets = Trefferfehler
## in ms (+ = spaet), trace = Genauigkeit (0..1) nach jedem Urteil.
static func pack(s: Dictionary, offsets: PackedFloat32Array, trace: PackedFloat32Array,
		h_ok: int, h_drop: int, failed: bool) -> Dictionary:
	var d := {
		"score": int(s.get("score", 0)), "acc": float(s.get("accuracy", 0.0)),
		"grade": "F" if failed else str(s.get("grade", "D")), "combo": int(s.get("max_combo", 0)),
		"failed": failed, "h_ok": h_ok, "h_drop": h_drop,
		"mods": s.get("mods", []),
	}
	for k in KEYS:
		d[k] = int(s.get(k, 0))
	var n := offsets.size()
	var sum := 0.0
	var early := 0
	var late := 0
	var bins: Array = []
	bins.resize(BINS)
	bins.fill(0)
	for o in offsets:
		sum += o
		if o < 0.0:
			early += 1
		elif o > 0.0:
			late += 1
		var t := (clampf(o, -RANGE_MS, RANGE_MS) + RANGE_MS) / (2.0 * RANGE_MS)
		bins[clampi(int(t * BINS), 0, BINS - 1)] += 1
	var mean := sum / float(n) if n > 0 else 0.0
	var sq := 0.0
	for o in offsets:
		sq += (o - mean) * (o - mean)
	d["ur"] = 10.0 * sqrt(sq / float(n)) if n > 0 else 0.0
	d["mean"] = mean
	d["early"] = early
	d["late"] = late
	d["bins"] = bins
	d["trace"] = resample(trace, TRACE)
	return sanitize(d)


## Verlauf (0..1) auf hoechstens pts Promille-Punkte verdichten (gleichmaessig
## abgetastet, letzter Punkt = Endstand).
static func resample(trace: PackedFloat32Array, pts: int) -> Array:
	var out: Array = []
	var tn := trace.size()
	if tn == 0:
		return out
	# Die ersten Noten (immer ~100 %) ueberspringen, sonst dominiert der Start.
	var start := int(float(tn) * 0.04) if tn > pts * 2 else 0
	var span := tn - start
	var m := mini(span, pts)
	for i in m:
		var idx := start + (0 if m <= 1 else int(round(float(i) * float(span - 1) / float(m - 1))))
		out.append(int(round(clampf(trace[idx], 0.0, 1.0) * 1000.0)))
	return out


## Fremdes Paket pruefen und klemmen: nur bekannte Schluessel, Zahlen im
## Wertebereich, Arrays auf feste Laenge. Erweiterte Felder nur, wenn vorhanden.
static func sanitize(raw: Dictionary) -> Dictionary:
	var d := {
		"score": int(_num(raw.get("score", 0), 0, 2000000000)),
		"acc": _num(raw.get("acc", 0.0), 0.0, 1.0),
		"combo": int(_num(raw.get("combo", 0), 0, MAX_COUNT)),
		"failed": raw.get("failed", false) == true,
	}
	var g := str(raw.get("grade", "D")).left(2)
	d["grade"] = g if g in GRADES else "D"
	for k in KEYS:
		d[k] = int(_num(raw.get(k, 0), 0, MAX_COUNT))
	var mods: Array = []
	var rm: Variant = raw.get("mods", [])
	if rm is Array:
		for m in rm:
			if mods.size() < 6 and (m is String or m is StringName):
				mods.append(str(m).left(8))
	d["mods"] = mods
	if not raw.has("ur"):
		return d
	d["ur"] = _num(raw.get("ur", 0.0), 0.0, 2000.0)
	d["mean"] = _num(raw.get("mean", 0.0), -500.0, 500.0)
	d["early"] = int(_num(raw.get("early", 0), 0, MAX_COUNT))
	d["late"] = int(_num(raw.get("late", 0), 0, MAX_COUNT))
	d["h_ok"] = int(_num(raw.get("h_ok", 0), 0, MAX_COUNT))
	d["h_drop"] = int(_num(raw.get("h_drop", 0), 0, MAX_COUNT))
	var bins: Array = []
	var rb: Variant = raw.get("bins", [])
	for i in BINS:
		bins.append(int(_num(rb[i], 0, MAX_COUNT)) if rb is Array and i < rb.size() else 0)
	d["bins"] = bins
	var tr_out: Array = []
	var rt: Variant = raw.get("trace", [])
	if rt is Array:
		for i in mini(rt.size(), TRACE):
			tr_out.append(int(_num(rt[i], 0, 1000)))
	d["trace"] = tr_out
	return d


static func hits_of(d: Dictionary) -> int:
	return int(d.get("n_max", 0)) + int(d.get("n300", 0)) + int(d.get("n200", 0)) \
			+ int(d.get("n100", 0)) + int(d.get("n50", 0))


static func total_of(d: Dictionary) -> int:
	return hits_of(d) + int(d.get("n_miss", 0))


## Mehrere Pakete (Turnier-Runden) zu Summen: Zaehler addieren, Kombo = Maximum,
## Acc aus den Zaehlern, UR/Abweichung nach Trefferzahl gewichtet, Verlauf = Acc
## je Runde, score = Summe. Leere Eintraege zaehlen nicht.
static func merge(list: Array) -> Dictionary:
	var out := { "score": 0, "acc": 0.0, "combo": 0, "failed": false, "grade": "D", "mods": [] }
	for k in KEYS:
		out[k] = 0
	var bins: Array = []
	bins.resize(BINS)
	bins.fill(0)
	var trace: Array = []
	var ext := false
	var w_ur := 0.0
	var w_mean := 0.0
	var w_n := 0.0
	var early := 0
	var late := 0
	var h_ok := 0
	var h_drop := 0
	var fails := 0
	var rounds := 0
	for e in list:
		var d: Dictionary = e
		if d.is_empty():
			continue
		rounds += 1
		out["score"] += int(d.get("score", 0))
		out["combo"] = maxi(int(out["combo"]), int(d.get("combo", 0)))
		for k in KEYS:
			out[k] += int(d.get(k, 0))
		if bool(d.get("failed", false)):
			fails += 1
		trace.append(int(round(float(d.get("acc", 0.0)) * 1000.0)))
		if d.has("ur"):
			ext = true
			var n := float(hits_of(d))
			w_ur += float(d.ur) * n
			w_mean += float(d.mean) * n
			w_n += n
			early += int(d.early)
			late += int(d.late)
			h_ok += int(d.h_ok)
			h_drop += int(d.h_drop)
			var db: Array = d.get("bins", [])
			for i in mini(BINS, db.size()):
				bins[i] += int(db[i])
	var tot := total_of(out)
	if tot > 0:
		out["acc"] = float(300 * (int(out.n_max) + int(out.n300)) + 200 * int(out.n200)
			+ 100 * int(out.n100) + 50 * int(out.n50)) / float(300 * tot)
	out["grade"] = grade_for(float(out.acc))
	out["fails"] = fails
	out["rounds"] = rounds
	out["trace"] = trace
	if ext:
		out["ur"] = w_ur / w_n if w_n > 0.0 else 0.0
		out["mean"] = w_mean / w_n if w_n > 0.0 else 0.0
		out["early"] = early
		out["late"] = late
		out["h_ok"] = h_ok
		out["h_drop"] = h_drop
		out["bins"] = bins
	return out


static func grade_for(acc: float) -> String:
	if acc >= 1.0:
		return "SS"
	if acc > 0.95:
		return "S"
	if acc > 0.90:
		return "A"
	if acc > 0.80:
		return "B"
	if acc > 0.70:
		return "C"
	return "D"


## Fake-Paket fuer Harness/Tests: skill 0..1 (1 = sehr gut).
static func fake(seed_i: int, skill: float, notes: int = 1400, failed: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	var sd := lerpf(30.0, 9.0, skill)
	var bias := rng.randf_range(-7.0, 7.0)
	var offs := PackedFloat32Array()
	var trace := PackedFloat32Array()
	var c := [0, 0, 0, 0, 0, 0]
	var combo := 0
	var best := 0
	# Schwaechere Phase irgendwo in der Map (macht den Verlauf lebendig).
	var dip := rng.randf_range(0.3, 0.8)
	for i in notes:
		var hard := absf(float(i) / float(notes) - dip) < 0.08
		var o := rng.randfn(bias, sd * (1.5 if hard else 1.0))
		var a := absf(o)
		var q := 0
		if rng.randf() < lerpf(0.05, 0.002, skill) * (3.0 if hard else 1.0):
			q = 5
		elif a < 16.0:
			q = 0
		elif a < 40.0:
			q = 1
		elif a < 73.0:
			q = 2
		elif a < 103.0:
			q = 3
		elif a < 127.0:
			q = 4
		else:
			q = 5
		c[q] += 1
		if q == 5:
			combo = 0
		else:
			offs.append(o)
			combo += 1
			best = maxi(best, combo)
		var tot := i + 1
		trace.append(float(300 * (c[0] + c[1]) + 200 * c[2] + 100 * c[3] + 50 * c[4]) / float(300 * tot))
	var s := { "n_max": c[0], "n300": c[1], "n200": c[2], "n100": c[3], "n50": c[4],
		"n_miss": c[5], "max_combo": best, "mods": ["SV"] }
	var acc := trace[trace.size() - 1]
	s["accuracy"] = acc
	s["grade"] = grade_for(acc)
	s["score"] = int(1000000.0 * pow(acc, 4.0) * 0.97 + float(best) * 12.0)
	var holds := 60 + int(skill * 40.0)
	return pack(s, offs, trace, holds - int((1.0 - skill) * 18.0), int((1.0 - skill) * 18.0), failed)


# ---------------------------------------------------------------------------
# Direktvergleich (zwei Pakete)
# ---------------------------------------------------------------------------

## Kennzahlen fuer den Direktvergleich: je Eintrag cap, a/b (Text), share
## (0..1 Anteil von A am Balken, verstaerkt damit kleine Abstaende sichtbar
## sind) und win (1 = A vorn, -1 = B vorn, 0 = gleich).
static func duel_rows(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	var ta := maxi(total_of(a), 1)
	var tb := maxi(total_of(b), 1)
	# [Ueberschrift, Wert A, Wert B, hoeher besser, Verstaerkung, Format]
	var defs := [
		["Score", float(a.get("score", 0)), float(b.get("score", 0)), true, 6.0, "score"],
		["Genauigkeit", float(a.get("acc", 0.0)), float(b.get("acc", 0.0)), true, 25.0, "pct"],
		["Max. Kombo", float(a.get("combo", 0)), float(b.get("combo", 0)), true, 1.0, "combo"],
		["MAX-Anteil", float(a.get("n_max", 0)) / float(ta), float(b.get("n_max", 0)) / float(tb), true, 2.0, "pct"],
		["Miss", float(a.get("n_miss", 0)), float(b.get("n_miss", 0)), false, 1.0, "int"],
	]
	if a.has("ur") and b.has("ur"):
		defs.insert(3, ["UR", float(a.ur), float(b.ur), false, 1.5, "ur"])
	for d in defs:
		var va: float = d[1]
		var vb: float = d[2]
		var top := maxf(absf(va), absf(vb))
		var rel := 0.0 if top <= 0.0 else (va - vb) / top
		if not d[3]:
			rel = -rel
		var win := 0 if absf(va - vb) < 0.0005 * maxf(top, 1e-6) else (1 if rel > 0.0 else -1)
		out.append({ "cap": d[0], "a": _duel_fmt(va, d[5]), "b": _duel_fmt(vb, d[5]),
			"share": clampf(0.5 + 0.5 * rel * float(d[4]), 0.06, 0.94), "win": win })
	return out


static func _duel_fmt(v: float, kind: String) -> String:
	match kind:
		"score":
			return UiTheme.fmt_score(int(v))
		"pct":
			return UiTheme.fmt_pct(v * 100.0)
		"combo":
			return "%d×" % int(v)
		"ur":
			return "%.1f" % v
	return str(int(v))


static func _dlbl(text: String, size: int, col: Color, heading: bool, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if heading:
		l.add_theme_font_override("font", UiTheme.heading_font(1))
	l.horizontal_alignment = align
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Kompakter Direktvergleich A (links, SIDE_A) gegen B (rechts, SIDE_B):
## Stand der gewonnenen Kennzahlen, dann je Kennzahl Werte + geteilter Balken.
static func duel(a_name: String, a: Dictionary, b_name: String, b: Dictionary, narrow: bool = false) -> Control:
	var rows := duel_rows(a, b)
	var wa := 0
	var wb := 0
	for r in rows:
		wa += 1 if int(r.win) > 0 else 0
		wb += 1 if int(r.win) < 0 else 0
	var p := PanelContainer.new()
	var sb := UiTheme.glass_box(14, 0.50, 0.08)
	sb.shadow_size = 0
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10 if narrow else 14
	sb.content_margin_bottom = 10 if narrow else 14
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3 if narrow else 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var cap := _dlbl(TranslationServer.translate("Direktvergleich").to_upper(), 11 if narrow else 12, CAPTION, true, HORIZONTAL_ALIGNMENT_CENTER)
	cap.add_theme_font_override("font", UiTheme.heading_font(2))
	v.add_child(cap)
	# Kopf: Name A   wa : wb   Name B
	var hd := HBoxContainer.new()
	hd.add_theme_constant_override("separation", 8)
	hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(hd)
	var fs := 15 if narrow else 17
	var na := _dlbl(a_name, fs, SIDE_A, true, HORIZONTAL_ALIGNMENT_LEFT)
	na.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(na)
	var sc := _dlbl("%d : %d" % [wa, wb], fs + 3, UiTheme.TEXT, true, HORIZONTAL_ALIGNMENT_CENTER)
	sc.add_theme_font_override("font", UiTheme.heading_font(2))
	hd.add_child(sc)
	var nb := _dlbl(b_name, fs, SIDE_B, true, HORIZONTAL_ALIGNMENT_RIGHT)
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(nb)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 2 if narrow else 4)
	v.add_child(gap)
	var vs := 13 if narrow else 15
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(line)
		var la := _dlbl(str(r.a), vs, UiTheme.TEXT if int(r.win) > 0 else CAPTION, int(r.win) > 0, HORIZONTAL_ALIGNMENT_LEFT)
		la.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(la)
		var lc := _dlbl(TranslationServer.translate(str(r.cap)).to_upper(), 10 if narrow else 11, Color(CAPTION, 0.85), true, HORIZONTAL_ALIGNMENT_CENTER)
		lc.add_theme_font_override("font", UiTheme.heading_font(2))
		lc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(lc)
		var lb := _dlbl(str(r.b), vs, UiTheme.TEXT if int(r.win) < 0 else CAPTION, int(r.win) < 0, HORIZONTAL_ALIGNMENT_RIGHT)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(lb)
		var bar := _Split.new()
		bar.share = float(r.share)
		bar.win = int(r.win)
		bar.custom_minimum_size = Vector2(0, 4 if narrow else 5)
		v.add_child(bar)
	return p


## Geteilter Balken: A von links, B von rechts, kleine Luecke in der Mitte;
## die vorne liegende Seite leuchtet staerker.
class _Split extends Control:
	var share := 0.5
	var win := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var h := size.y
		var gap := 3.0
		var wa := maxf((size.x - gap) * share, 2.0)
		var wb := maxf(size.x - gap - wa, 2.0)
		var ra := StyleBoxFlat.new()
		ra.bg_color = Color(PlayerStatsCard.SIDE_A, 0.85 if win > 0 else 0.38)
		ra.set_corner_radius_all(int(h * 0.5))
		draw_style_box(ra, Rect2(0, 0, wa, h))
		var rb := StyleBoxFlat.new()
		rb.bg_color = Color(PlayerStatsCard.SIDE_B, 0.85 if win < 0 else 0.38)
		rb.set_corner_radius_all(int(h * 0.5))
		draw_style_box(rb, Rect2(size.x - wb, 0, wb, h))


# ---------------------------------------------------------------------------
# Karte
# ---------------------------------------------------------------------------

## info: name, place (0 = ohne), sub (Zusatzzeile), pending (spielt noch),
## live (Live-Score beim Warten), side ("A"/"B"/""), ref (Paket zum Vergleich),
## ref_name, narrow (schmale Karte), trace_caption (eigene Ueberschrift).
func setup(info: Dictionary, st: Dictionary, compact: bool = false) -> void:
	_compact = compact
	_s = 0.82 if bool(info.get("narrow", false)) else 1.0
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var side := str(info.get("side", ""))
	_accent = SIDE_B if side == "B" else SIDE_A
	_top_line = side != ""
	var sb := UiTheme.glass_box(18, 0.66, 0.10)
	sb.shadow_size = 18
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_offset = Vector2(0, 6)
	sb.content_margin_left = 16 if compact else _px(24)
	sb.content_margin_right = sb.content_margin_left
	sb.content_margin_top = 14 if compact else _px(20)
	sb.content_margin_bottom = 14 if compact else _px(20)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8 if compact else _px(16))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	v.add_child(_header(info, st))
	if bool(info.get("pending", false)) or st.is_empty():
		v.add_child(_pending(info))
		queue_redraw()
		return
	var ref: Dictionary = info.get("ref", {})
	v.add_child(_hero(st, ref))
	v.add_child(_judgements(st))
	if not compact and st.has("ur"):
		v.add_child(_sep())
		v.add_child(_timing(st, ref))
		v.add_child(_graphs(st, ref, info))
	queue_redraw()


func _px(v: float) -> int:
	return int(round(v * _s))


func _draw() -> void:
	if not _top_line:
		return
	# Feine Farbkante oben (A/B im Vergleich), innerhalb der runden Ecken.
	var w := size.x
	var steps := 24
	for i in steps:
		var x0 := 18.0 + (w - 36.0) * float(i) / float(steps)
		var x1 := 18.0 + (w - 36.0) * float(i + 1) / float(steps)
		var t := absf((float(i) + 0.5) / float(steps) - 0.5) * 2.0
		draw_rect(Rect2(x0, 0.5, x1 - x0, 2.0), Color(_accent, 0.85 * (1.0 - t * t)))


func _lbl(text: String, size: int, col: Color, heading: bool = false, spacing: int = 1) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if heading:
		l.add_theme_font_override("font", UiTheme.heading_font(spacing))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _caption(text: String) -> Label:
	var l := _lbl(tr(text).to_upper(), maxi(_px(12), 11), CAPTION, true, 2)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


func _sep() -> Control:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.07)
	c.custom_minimum_size = Vector2(0, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _header(info: Dictionary, st: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", _px(14))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := str(info.get("name", "?"))
	var place := int(info.get("place", 0))
	var av_sz := 36 if _compact else _px(52)
	var av_wrap := Control.new()
	av_wrap.custom_minimum_size = Vector2(av_sz, av_sz)
	av_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var av := avatar(nm, av_sz)
	av_wrap.add_child(av)
	if place > 0:
		var badge := _place_badge(place, maxi(int(av_sz * 0.44), 18))
		badge.position = Vector2(av_sz - badge.custom_minimum_size.x * 0.75, av_sz - badge.custom_minimum_size.y * 0.8)
		av_wrap.add_child(badge)
	h.add_child(av_wrap)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := _lbl(nm, 19 if _compact else _px(27), UiTheme.TEXT, true, 1)
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nv.add_child(nl)
	var parts: Array = []
	if place > 0:
		parts.append(tr("%d. Platz") % place)
	var sub := str(info.get("sub", ""))
	if sub != "":
		parts.append(sub)
	var mods: Array = st.get("mods", [])
	if not mods.is_empty():
		parts.append(" + ".join(mods))
	if not parts.is_empty():
		var sl := _lbl("  ·  ".join(parts), 12 if _compact else _px(14), CAPTION)
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		nv.add_child(sl)
	h.add_child(nv)
	if not st.is_empty() and not bool(info.get("pending", false)):
		var failed := bool(st.get("failed", false))
		if failed:
			h.add_child(_chip(tr("Nicht geschafft"), DOWN_COL, 12 if _compact else _px(13)))
		var g := "F" if failed else str(st.get("grade", "D"))
		var gc: Color = DOWN_COL if failed else GRADE_COLOR.get(g, Color.WHITE)
		var gl := _lbl(g, 34 if _compact else _px(54), gc, true, 0)
		gl.add_theme_color_override("font_shadow_color", Color(gc, 0.25))
		gl.add_theme_constant_override("shadow_offset_y", 0)
		gl.add_theme_constant_override("shadow_outline_size", 14)
		gl.custom_minimum_size.x = 40 if _compact else _px(66)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		gl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		h.add_child(gl)
	return h


## Runder Avatar mit Anfangsbuchstabe (wie TournamentPanel.avatar).
static func avatar(pname: String, sz: int = 28) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.from_hsv(float(pname.hash() % 360) / 360.0, 0.45, 0.62)
	sb.set_corner_radius_all(sz)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.08, 0.09, 0.14, 0.9)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(sz, sz)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = pname.substr(0, 1).to_upper() if pname != "" else "?"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(sz * 0.5))
	l.add_theme_color_override("font_color", UiTheme.TEXT)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	p.add_child(l)
	return p


func _chip(text: String, col: Color, size: int) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.14)
	sb.border_color = Color(col, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(20)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_lbl(text, size, col))
	return p


static func _place_badge(place: int, sz: int) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var rc: Color = RANK_COLS[place - 1] if place <= 3 else Color(0.36, 0.39, 0.48)
	sb.bg_color = Color(rc.darkened(0.15), 1.0)
	sb.set_corner_radius_all(sz)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.06, 0.07, 0.11, 1.0)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(sz, sz)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = str(place)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.heading_font(0))
	l.add_theme_font_size_override("font_size", int(sz * 0.58))
	l.add_theme_color_override("font_color", Color(0.05, 0.06, 0.09) if place <= 3 else UiTheme.TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


func _pending(info: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(0, 90 if _compact else _px(220))
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := _lbl(tr("spielt noch…"), _px(20), UiTheme.TEXT.lerp(CAPTION, 0.4), true, 1)
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(w)
	if info.has("live"):
		var l := _lbl(UiTheme.fmt_score(int(info.live)), _px(30), CAPTION, true, 1)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(l)
	var hint := _lbl(tr("Die Stats erscheinen, sobald die Runde fertig ist."), _px(13), CAPTION)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	return v


func _stat(cap: String, value: String, col: Color, size: int, delta: String = "", delta_col: Color = CAPTION) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_caption(cap))
	var vl := _lbl(value, size, col, true, 0)
	vl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(vl)
	if delta != "":
		var dl := _lbl(delta, maxi(_px(13), 12), delta_col, true, 0)
		dl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(dl)
	return v


## Differenz als Text + Farbe: better = hoeher ist besser (UR: niedriger).
static func _delta(diff: float, text: String, higher_better: bool = true) -> Array:
	if absf(diff) < 0.0005:
		return ["±0", CAPTION]
	var good := (diff > 0.0) == higher_better
	return [("+" if diff > 0.0 else "−") + text, UP_COL if good else DOWN_COL]


func _hero(st: Dictionary, ref: Dictionary) -> Control:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", _px(16))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var big := 22 if _compact else _px(38)
	var mid := 18 if _compact else _px(30)
	var has_ref := not ref.is_empty()
	var sc := int(st.get("score", 0))
	var acc := float(st.get("acc", 0.0))
	var cb := int(st.get("combo", 0))
	var d1 := ["", CAPTION]
	var d2 := ["", CAPTION]
	var d3 := ["", CAPTION]
	if has_ref and not _compact:
		var ds := sc - int(ref.get("score", 0))
		d1 = _delta(float(ds), UiTheme.fmt_score(absi(ds)))
		var da := (acc - float(ref.get("acc", 0.0))) * 100.0
		d2 = _delta(da, UiTheme.fmt_pct(absf(da)))
		var dc := cb - int(ref.get("combo", 0))
		d3 = _delta(float(dc), UiTheme.fmt_score(absi(dc)) + "×")
	var s1 := _stat("Score", UiTheme.fmt_score(sc), UiTheme.TEXT, big, d1[0], d1[1])
	s1.size_flags_stretch_ratio = 1.35
	r.add_child(s1)
	r.add_child(_stat("Genauigkeit", UiTheme.fmt_pct(acc * 100.0), _accent.lerp(UiTheme.TEXT, 0.25), big, d2[0], d2[1]))
	r.add_child(_stat("Max. Kombo", UiTheme.fmt_score(cb) + "×", UiTheme.TEXT, mid, d3[0], d3[1]))
	return r


func _judgements(st: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6 if _compact else _px(10))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tot := float(maxi(total_of(st), 1))
	var b := _Stack.new()
	var fr: Array = []
	for k in KEYS:
		fr.append(float(st.get(k, 0)) / tot)
	b.fracs = fr
	b.custom_minimum_size = Vector2(0, 8 if _compact else _px(10))
	v.add_child(b)
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", 4)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(g)
	for i in KEYS.size():
		var n := int(st.get(KEYS[i], 0))
		var col: Color = PlayerStatsCard.QUALITY_COLOR[i]
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", -3)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tg := _lbl(TAGS[i], 11 if _compact else _px(13), col, true, 1)
		tg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		c.add_child(tg)
		var cl := _lbl(UiTheme.fmt_score(n), 15 if _compact else _px(22), UiTheme.TEXT if n > 0 else CAPTION, true, 0)
		cl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		c.add_child(cl)
		if not _compact:
			var pl := _lbl(UiTheme.fmt_num(100.0 * float(n) / tot, 1) + (" %" if UiTheme.is_german() else "%"), _px(12), CAPTION)
			pl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			c.add_child(pl)
		g.add_child(c)
	if _compact and st.has("ur"):
		var tl := _lbl("UR %s   ·   Ø %s ms   ·   %s" % [UiTheme.fmt_num(float(st.ur), 1),
			_signed(float(st.mean)), _el_text(st)], 12, CAPTION)
		tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(tl)
	return v


static func _signed(v: float) -> String:
	return ("+" if v >= 0.0 else "−") + UiTheme.fmt_num(absf(v), 1)


func _el_text(st: Dictionary) -> String:
	var n := maxi(int(st.early) + int(st.late), 1)
	return "%s %s / %s %s" % [tr("früh"), UiTheme.fmt_num(100.0 * float(st.early) / float(n), 0) + "%",
		tr("spät"), UiTheme.fmt_num(100.0 * float(st.late) / float(n), 0) + "%"]


func _timing(st: Dictionary, ref: Dictionary) -> Control:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", _px(16))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sz := _px(22)
	var ur := float(st.ur)
	var du := ["", CAPTION]
	if ref.has("ur"):
		var d := ur - float(ref.ur)
		du = _delta(d, UiTheme.fmt_num(absf(d), 1), false)
	r.add_child(_stat("UR", UiTheme.fmt_num(ur, 1), UiTheme.TEXT, sz, du[0], du[1]))
	var mean := float(st.mean)
	var mtxt := "%s ms" % _signed(mean)
	var mcol := UiTheme.TEXT
	if absf(mean) >= 3.0:
		mcol = LATE_COL.lerp(UiTheme.TEXT, 0.35) if mean > 0.0 else EARLY_COL.lerp(UiTheme.TEXT, 0.35)
	var mhint := ""
	if absf(mean) >= 1.0:
		mhint = tr("eher spät") if mean > 0.0 else tr("eher früh")
	r.add_child(_stat("Ø Abweichung", mtxt, mcol, sz, mhint, CAPTION))
	var holds := int(st.h_ok) + int(st.h_drop)
	var hv := "–" if holds == 0 else "%s / %s" % [UiTheme.fmt_score(int(st.h_ok)), UiTheme.fmt_score(holds)]
	var hhint := "" if holds == 0 else (tr("alle gehalten") if int(st.h_drop) == 0 else tr("%d losgelassen") % int(st.h_drop))
	r.add_child(_stat("Holds", hv, UiTheme.TEXT, sz, hhint, UP_COL if holds > 0 and int(st.h_drop) == 0 else CAPTION))
	# Frueh/Spaet-Anteil als geteilter Balken.
	var el := VBoxContainer.new()
	el.add_theme_constant_override("separation", _px(5))
	el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	el.size_flags_stretch_ratio = 1.3
	el.mouse_filter = Control.MOUSE_FILTER_IGNORE
	el.add_child(_caption("Früh / Spät"))
	var n := maxi(int(st.early) + int(st.late), 1)
	var fe := float(st.early) / float(n)
	var b := _Stack.new()
	b.fracs = [fe, 1.0 - fe]
	b.cols = [EARLY_COL, LATE_COL]
	b.gap = 3.0
	b.custom_minimum_size = Vector2(0, _px(8))
	el.add_child(b)
	var lr := HBoxContainer.new()
	lr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := _lbl(UiTheme.fmt_num(100.0 * fe, 0) + "%", _px(15), EARLY_COL, true, 0)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lr.add_child(a)
	var z := _lbl(UiTheme.fmt_num(100.0 * (1.0 - fe), 0) + "%", _px(15), LATE_COL, true, 0)
	z.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lr.add_child(z)
	el.add_child(lr)
	r.add_child(el)
	return r


func _graphs(st: Dictionary, ref: Dictionary, info: Dictionary) -> Control:
	# Schmal: nebeneinander, feste Hoehe. Breit: untereinander, fuellen die Karte.
	var wide := _s >= 1.0
	var r: BoxContainer = VBoxContainer.new() if wide else HBoxContainer.new()
	r.add_theme_constant_override("separation", _px(16))
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ghost := SIDE_A if _accent == SIDE_B else SIDE_B
	var hv := _graph_box("Trefferfehler")
	var hg := _Hist.new()
	hg.data = st.get("bins", [])
	hg.ref = ref.get("bins", [])
	hg.ghost = ghost
	hg.range_ms = RANGE_MS
	hg.custom_minimum_size = Vector2(0, _px(104))
	hg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hv.add_child(hg)
	r.add_child(hv)
	var trace: Array = st.get("trace", [])
	if trace.size() > 1:
		var per_round := int(st.get("rounds", 0)) > 0
		var cap := str(info.get("trace_caption", "Genauigkeit je Runde" if per_round else "Genauigkeit im Verlauf"))
		var tv := _graph_box(cap)
		var tg := _Trace.new()
		tg.data = trace
		tg.ref = ref.get("trace", [])
		tg.col = _accent
		tg.ghost = ghost
		tg.dots = per_round
		tg.custom_minimum_size = Vector2(0, _px(104))
		tg.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tv.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tv.add_child(tg)
		r.add_child(tv)
	return r


func _graph_box(cap: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _px(8))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_caption(cap))
	return v


# ---------------------------------------------------------------------------
# Zeichen-Bausteine
# ---------------------------------------------------------------------------

## Gestapelter Anteil-Balken mit runden Enden (Judgements, Frueh/Spaet).
class _Stack extends Control:
	var fracs: Array = []
	var cols: Array = []
	var gap := 2.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var h := size.y
		var r := h * 0.5
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.06)
		bg.set_corner_radius_all(int(r))
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		var segs: Array = []
		for i in fracs.size():
			if float(fracs[i]) > 0.0:
				segs.append(i)
		var free_w := size.x - gap * float(maxi(segs.size() - 1, 0))
		var x := 0.0
		for k in segs.size():
			var i: int = segs[k]
			var w := maxf(free_w * float(fracs[i]), 2.0)
			var c: Color = cols[i] if i < cols.size() else PlayerStatsCard.QUALITY_COLOR[i]
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(c, 0.88)
			var rr := int(minf(r, w * 0.5))
			sb.corner_radius_top_left = rr if k == 0 else 1
			sb.corner_radius_bottom_left = rr if k == 0 else 1
			sb.corner_radius_top_right = rr if k == segs.size() - 1 else 1
			sb.corner_radius_bottom_right = rr if k == segs.size() - 1 else 1
			draw_style_box(sb, Rect2(x, 0, minf(w, size.x - x), h))
			x += w + gap


## Trefferfehler-Histogramm: Balken frueh (blau) -> genau (mint) -> spaet (orange),
## Nulllinie, Achsenbeschriftung; ref = Schatten-Umriss des Vergleichsspielers.
class _Hist extends Control:
	var data: Array = []
	var ref: Array = []
	var ghost := Color.WHITE
	var range_ms := 120.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _norm(a: Array) -> Array:
		var tot := 0.0
		for v in a:
			tot += float(v)
		var out: Array = []
		for v in a:
			out.append(float(v) / tot if tot > 0.0 else 0.0)
		return out

	func _draw() -> void:
		var f := get_theme_default_font()
		var fs := 11
		var axis_h := 16.0
		var w := size.x
		var h := size.y - axis_h
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.035)
		bg.set_corner_radius_all(10)
		draw_style_box(bg, Rect2(0, 0, w, h))
		var n := data.size()
		if n == 0:
			return
		var a := _norm(data)
		var b := _norm(ref) if ref.size() == n else []
		var mx := 0.0001
		for v in a:
			mx = maxf(mx, float(v))
		for v in b:
			mx = maxf(mx, float(v))
		var pad := 8.0
		var top := 10.0
		var bw := (w - pad * 2.0) / float(n)
		var mid := float(n - 1) * 0.5
		for i in n:
			var t := (float(i) - mid) / maxf(mid, 1.0)
			var c: Color = PlayerStatsCard.CENTER_COL.lerp(PlayerStatsCard.EARLY_COL if t < 0.0 else PlayerStatsCard.LATE_COL, minf(absf(t) * 1.6, 1.0))
			var bh := (h - top - 2.0) * float(a[i]) / mx
			if bh <= 0.0:
				continue
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(c, 0.80)
			sb.corner_radius_top_left = 3
			sb.corner_radius_top_right = 3
			draw_style_box(sb, Rect2(pad + i * bw + 2.0, h - bh, maxf(bw - 4.0, 1.0), bh))
		if not b.is_empty():
			var pts := PackedVector2Array()
			for i in n:
				var y := h - (h - top - 2.0) * float(b[i]) / mx
				pts.append(Vector2(pad + i * bw + 1.0, y))
				pts.append(Vector2(pad + (i + 1) * bw - 1.0, y))
			draw_polyline(pts, Color(ghost, 0.75), 1.6, true)
		var cx := pad + (w - pad * 2.0) * 0.5
		for y in range(4, int(h) - 2, 6):
			draw_line(Vector2(cx, y), Vector2(cx, y + 3), Color(1, 1, 1, 0.30), 1.0)
		draw_line(Vector2(pad, h - 0.5), Vector2(w - pad, h - 0.5), Color(1, 1, 1, 0.12), 1.0)
		var lc := Color(0.66, 0.69, 0.78, 0.85)
		var early := TranslationServer.translate("früh")
		var late := TranslationServer.translate("spät")
		draw_string(f, Vector2(pad, size.y - 2), "−%d ms  %s" % [int(range_ms), early], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(PlayerStatsCard.EARLY_COL, 0.85))
		draw_string(f, Vector2(cx - 20, size.y - 2), "0", HORIZONTAL_ALIGNMENT_CENTER, 40, fs, lc)
		draw_string(f, Vector2(w - pad - 160, size.y - 2), "%s  +%d ms" % [late, int(range_ms)], HORIZONTAL_ALIGNMENT_RIGHT, 160, fs, Color(PlayerStatsCard.LATE_COL, 0.85))


## Genauigkeits-Verlauf als Flaeche mit Verlauf-Fuellung, Hilfslinien rechts
## beschriftet, Endwert als Punkt; ref = Schatten-Linie des Vergleichsspielers.
class _Trace extends Control:
	var data: Array = []
	var ref: Array = []
	var col := Color.WHITE
	var ghost := Color.WHITE
	var dots := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _pts(a: Array, lo: float, hi: float, r: Rect2) -> PackedVector2Array:
		var out := PackedVector2Array()
		var n := a.size()
		for i in n:
			var x := r.position.x + r.size.x * (float(i) / float(maxi(n - 1, 1)))
			var t := clampf((float(a[i]) - lo) / (hi - lo), 0.0, 1.0)
			out.append(Vector2(x, r.position.y + r.size.y * (1.0 - t)))
		return out

	func _draw() -> void:
		var f := get_theme_default_font()
		var fs := 11
		var axis_h := 16.0
		var w := size.x
		var h := size.y - axis_h
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.035)
		bg.set_corner_radius_all(10)
		draw_style_box(bg, Rect2(0, 0, w, h))
		if data.size() < 2:
			return
		var lo := 1000.0
		var hi := 0.0
		# Nur ab dem ersten Viertel skalieren: der Anfang schwankt stark.
		var skip := 0 if dots else int(data.size() * 0.15)
		for arr in [data, ref]:
			for i in range(skip if arr.size() > 4 else 0, arr.size()):
				lo = minf(lo, float(arr[i]))
				hi = maxf(hi, float(arr[i]))
		var step := 10.0 if hi - lo < 40.0 else (25.0 if hi - lo < 120.0 else 100.0)
		lo = floorf((lo - 2.0) / step) * step
		hi = minf(ceilf((hi + 2.0) / step) * step, 1000.0)
		if hi - lo < step:
			hi = lo + step
		var label_w := 48.0
		var r := Rect2(10, 10, w - 20 - label_w, h - 20)
		# Hilfslinien + Werte.
		var lines := 3
		for k in lines:
			var v := lo + (hi - lo) * float(k) / float(lines - 1)
			var y := r.position.y + r.size.y * (1.0 - float(k) / float(lines - 1))
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.06), 1.0)
			var txt := UiTheme.fmt_num(v / 10.0, 1 if step < 25.0 else 0) + "%"
			draw_string(f, Vector2(r.end.x + 6, y + 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.66, 0.69, 0.78, 0.8))
		if ref.size() > 1:
			var rp := _pts(ref, lo, hi, r)
			draw_polyline(rp, Color(ghost, 0.55), 1.5, true)
		var pts := _pts(data, lo, hi, r)
		# Flaeche: oben Akzent, unten transparent.
		var poly := PackedVector2Array(pts)
		var cols := PackedColorArray()
		for p in pts:
			var t := (p.y - r.position.y) / r.size.y
			cols.append(Color(col, 0.30 * (1.0 - t) + 0.02))
		poly.append(Vector2(pts[pts.size() - 1].x, r.end.y))
		cols.append(Color(col, 0.0))
		poly.append(Vector2(pts[0].x, r.end.y))
		cols.append(Color(col, 0.0))
		draw_polygon(poly, cols)
		draw_polyline(pts, Color(col, 0.95), 2.2, true)
		if dots:
			for p in pts:
				draw_circle(p, 3.5, Color(0.07, 0.08, 0.12))
				draw_circle(p, 2.5, col)
		var last := pts[pts.size() - 1]
		draw_circle(last, 5.0, Color(col, 0.25))
		draw_circle(last, 3.2, col)
		var lc := Color(0.66, 0.69, 0.78, 0.85)
		if dots:
			draw_string(f, Vector2(r.position.x, size.y - 2), TranslationServer.translate("Runde") + " 1", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lc)
			draw_string(f, Vector2(r.end.x - 100, size.y - 2), str(data.size()), HORIZONTAL_ALIGNMENT_RIGHT, 100, fs, lc)
		else:
			draw_string(f, Vector2(r.position.x, size.y - 2), TranslationServer.translate("Start"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lc)
			draw_string(f, Vector2(r.end.x - 100, size.y - 2), TranslationServer.translate("Ende"), HORIZONTAL_ALIGNMENT_RIGHT, 100, fs, lc)
