class_name TracePicture
extends RefCounted

## "Bild der Runde" fuer Trace: die ganze Map als Faden auf dunklem Grund.
## Gespielte Strecke in Spaltenfarben, Misses / Wrong-Turns als ausgefranste graue Stellen,
## kleine Signatur unten. Rein (Software-Rasterung in einen Byte-Puffer), deterministisch,
## ohne Szene; in --headless fehlen nur die Schriftzeichen (Text-Server ist dort leer).
##
## judgements = Array aus Vector4(t_note_ms, spalte, qualitaet, abweichung) wie das
## _judge_log des Spiels; Qualitaet 5 = Miss / Wrong-Turn. Leer = alles als gespielt.
## meta = {title, version, player, acc (0..1), date, colors?: [4 Farben]}.

const SIZE_SQUARE := Vector2i(1600, 1600)
const SIZE_SHARE := Vector2i(1200, 630)
const MISS_Q := 5
const FOLDER := "user://pictures/"
const GALLERY_MAX := 12
const BG := Color(0.045, 0.052, 0.07)
const GRAY := Color(0.55, 0.57, 0.62)
const TEXT := Color(0.92, 0.93, 0.96)
const DIM := Color(0.58, 0.60, 0.66)
const COL_COLORS := [
	Color(0.95, 0.45, 0.52),  # links
	Color(0.98, 0.78, 0.38),  # runter
	Color(0.45, 0.86, 0.66),  # hoch
	Color(0.42, 0.70, 0.98),  # rechts
]


## Ganzes Bild als RGBA8-Image der Groesse `size`.
static func render(path: TracePath, judgements: Array, size: Vector2i, meta: Dictionary = {}) -> Image:
	var w := maxi(size.x, 64)
	var h := maxi(size.y, 64)
	var buf := PackedByteArray()
	buf.resize(w * h * 4)
	_fill_background(buf, w, h)
	var unit := float(mini(w, h)) / 1600.0
	var band := int(roundf(150.0 * maxf(unit, 0.55)))
	var margin := int(roundf(float(mini(w, h)) * 0.07))
	var area := Rect2(margin, margin, w - 2 * margin, h - band - margin)
	if path != null and path.knots.size() > 0:
		_draw_path(buf, w, h, path, judgements, area, meta)
	_draw_signature(buf, w, h, band, margin, meta)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, buf)


## Beide Standardformate: {"square": Image, "share": Image}.
static func render_both(path: TracePath, judgements: Array, meta: Dictionary = {}) -> Dictionary:
	return {
		"square": render(path, judgements, SIZE_SQUARE, meta),
		"share": render(path, judgements, SIZE_SHARE, meta),
	}


## Speichert als PNG in user://pictures/. Gibt den Pfad zurueck, "" bei Fehler.
static func save(img: Image, meta: Dictionary = {}, folder: String = FOLDER) -> String:
	if img == null:
		return ""
	DirAccess.make_dir_recursive_absolute(folder)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var p := "%strace_%s_%s_%dx%d.png" % [folder, stamp, _slug(str(meta.get("title", ""))),
		img.get_width(), img.get_height()]
	return p if img.save_png(p) == OK else ""


## Die letzten n gespeicherten Bilder (neueste zuerst) als Pfadliste.
static func recent(n: int = GALLERY_MAX, folder: String = FOLDER) -> Array:
	var items: Array = []
	var d := DirAccess.open(folder)
	if d == null:
		return items
	for f in d.get_files():
		if f.ends_with(".png") and f.begins_with("trace_"):
			items.append([FileAccess.get_modified_time(folder + f), folder + f])
	items.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	var out: Array = []
	for it in items.slice(0, n):
		out.append(it[1])
	return out


static func _slug(t: String) -> String:
	var out := ""
	for c in t.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "-"
		if out.length() >= 24:
			break
	out = out.strip_edges().trim_prefix("-").trim_suffix("-")
	return out if out != "" else "map"


# ---------------------------------------------------------------------------
# Zeichnen
# ---------------------------------------------------------------------------

static func _fill_background(buf: PackedByteArray, w: int, h: int) -> void:
	var cx := w * 0.5
	var cy := h * 0.45
	var rmax := sqrt(cx * cx + cy * cy)
	for y in h:
		for x in w:
			var d := sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) / rmax
			var k := 1.0 + 0.55 * (1.0 - clampf(d * 1.15, 0.0, 1.0))
			var i := (y * w + x) * 4
			buf[i] = int(clampf(BG.r * 255.0 * k, 0, 255))
			buf[i + 1] = int(clampf(BG.g * 255.0 * k, 0, 255))
			buf[i + 2] = int(clampf(BG.b * 255.0 * k, 0, 255))
			buf[i + 3] = 255


static func _draw_path(buf: PackedByteArray, w: int, h: int, path: TracePath,
		judgements: Array, area: Rect2, meta: Dictionary) -> void:
	var b := path.bounds()
	var sc := minf(area.size.x / maxf(b.size.x, 1.0), area.size.y / maxf(b.size.y, 1.0))
	var off := area.position + (area.size - b.size * sc) * 0.5 - b.position * sc
	var colors: Array = meta.get("colors", COL_COLORS)
	var unit := float(mini(w, h)) / 1600.0
	var q_by_knot := _knot_quality(path, judgements)
	var have_log := not judgements.is_empty()
	var segs: Array = []
	var prev_s := 0.0
	for i in path.knots.size():
		var kn: TracePath.Knot = path.knots[i]
		var q := int(q_by_knot.get(i, 0 if not have_log else -1))
		segs.append([prev_s, kn.s, kn.cols[0] if kn.cols.size() > 0 else 0, q])
		prev_s = kn.s
	for sg in segs:
		if int(sg[3]) == -1:
			_stroke(buf, w, h, _pts(path, sg[0], sg[1], sc, off, 2.0 * unit), GRAY, 1.0 * unit, 0.22)
	# Erst alle Glows, dann Kerne: so liegen Kerne nie unter fremdem Glow.
	for pass_i in 2:
		for sg in segs:
			var q: int = sg[3]
			if q == MISS_Q or q == -1:
				continue
			var col: Color = colors[clampi(int(sg[2]), 0, colors.size() - 1)]
			var pts := _pts(path, sg[0], sg[1], sc, off, 1.6 * unit)
			if pass_i == 0:
				_stroke(buf, w, h, pts, col, 11.0 * unit, 0.16)
			else:
				_stroke(buf, w, h, pts, col, 3.2 * unit, 0.95)
				_stroke(buf, w, h, pts, col.lerp(Color.WHITE, 0.55), 1.0 * unit, 0.8)
	for sg in segs:
		if int(sg[3]) == MISS_Q:
			_fray(buf, w, h, _pts(path, sg[0], sg[1], sc, off, 1.4 * unit), unit)


## Knoten-Index -> Miss-Markierung (MISS_Q) oder 0 (gespielt); nur beurteilte Knoten.
static func _knot_quality(path: TracePath, judgements: Array) -> Dictionary:
	var out := {}
	for j in judgements:
		var v := j as Vector4
		var ki := path.first_knot_from(v.x - TracePath.CHORD_MS - 1.0)
		if ki < 0 or ki >= path.knots.size():
			continue
		if absf(path.knots[ki].t - v.x) > TracePath.CHORD_MS + 1.0:
			continue
		if int(v.z) >= MISS_Q:
			out[ki] = MISS_Q
		elif not out.has(ki):
			out[ki] = 0
	return out


static func _pts(path: TracePath, s0: float, s1: float, sc: float, off: Vector2,
		step_px: float) -> PackedVector2Array:
	var raw := path.sample(s0, s1, maxf(step_px / maxf(sc, 0.0001), 1.0))
	var out := PackedVector2Array()
	out.resize(raw.size())
	for i in raw.size():
		out[i] = raw[i] * sc + off
	return out


static func _stroke(buf: PackedByteArray, w: int, h: int, pts: PackedVector2Array,
		col: Color, width: float, alpha: float) -> void:
	var r := maxf(width * 0.5, 0.5)
	var last := Vector2(INF, INF)
	var gap := maxf(r * 0.35, 0.45)
	for p in pts:
		if p.distance_to(last) < gap:
			continue
		last = p
		_dot(buf, w, h, p.x, p.y, r, col, alpha)


## Weicher Punkt: harte Kante mit 1 px AA (r <= 3) bzw. quadratischer Abfall (Glow).
static func _dot(buf: PackedByteArray, w: int, h: int, cx: float, cy: float, r: float,
		col: Color, alpha: float) -> void:
	var x0 := maxi(int(floor(cx - r - 1.0)), 0)
	var x1 := mini(int(ceil(cx + r + 1.0)), w - 1)
	var y0 := maxi(int(floor(cy - r - 1.0)), 0)
	var y1 := mini(int(ceil(cy + r + 1.0)), h - 1)
	var soft := r > 3.0
	var cr := col.r * 255.0
	var cg := col.g * 255.0
	var cb := col.b * 255.0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := sqrt((x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy))
			var a: float
			if soft:
				var f := 1.0 - d / (r + 1.0)
				a = f * f if f > 0.0 else 0.0
			else:
				a = clampf(r + 0.5 - d, 0.0, 1.0)
			a *= alpha
			if a <= 0.003:
				continue
			var i := (y * w + x) * 4
			buf[i] = int(buf[i] + (cr - buf[i]) * a)
			buf[i + 1] = int(buf[i + 1] + (cg - buf[i + 1]) * a)
			buf[i + 2] = int(buf[i + 2] + (cb - buf[i + 2]) * a)


## Deterministische Streuung (Ganzzahl-Hash), -1..1.
static func _noise(a: int, b: int) -> float:
	var n: int = ((a * 73856093) ^ (b * 19349663)) & 0x7FFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7FFFFFFF
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 32767.5 - 1.0


## Ausgefranst: duenne, unterbrochene Linie mit seitlich verstreuten Splittern.
static func _fray(buf: PackedByteArray, w: int, h: int, pts: PackedVector2Array, unit: float) -> void:
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var tang := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		var nrm := Vector2(-tang.y, tang.x).normalized() if tang.length() > 0.001 else Vector2.UP
		var gx := int(p.x)
		var gy := int(p.y)
		var n1 := _noise(gx, gy)
		var n2 := _noise(gy + 7, gx + 13)
		if n1 > -0.35:
			_dot(buf, w, h, p.x + nrm.x * n2 * 3.0 * unit, p.y + nrm.y * n2 * 3.0 * unit,
				1.0 * unit, GRAY, 0.75)
		if n2 > 0.55:
			var s := n1 * 7.0 * unit
			_dot(buf, w, h, p.x + nrm.x * s, p.y + nrm.y * s, 0.9 * unit, GRAY, 0.5)


# ---------------------------------------------------------------------------
# Signatur
# ---------------------------------------------------------------------------

static func _draw_signature(buf: PackedByteArray, w: int, h: int, band: int, margin: int,
		meta: Dictionary) -> void:
	var unit := maxf(float(mini(w, h)) / 1600.0, 0.6)
	var y_line := h - band + int(10 * unit)
	for x in range(margin, w - margin):
		var i := (y_line * w + x) * 4
		buf[i] = int(buf[i] + (GRAY.r * 255.0 - buf[i]) * 0.25)
		buf[i + 1] = int(buf[i + 1] + (GRAY.g * 255.0 - buf[i + 1]) * 0.25)
		buf[i + 2] = int(buf[i + 2] + (GRAY.b * 255.0 - buf[i + 2]) * 0.25)
	var big := int(36 * unit)
	var small := int(22 * unit)
	var base_y := y_line + int(big * 1.6)
	var parts: Array = []
	for k in ["version", "player"]:
		if str(meta.get(k, "")) != "":
			parts.append(str(meta[k]))
	if meta.has("acc"):
		parts.append("%.2f%%" % (float(meta.acc) * 100.0))
	var d := str(meta.get("date", "")).substr(0, 10)
	if d != "":
		parts.append(d)
	var right := "TETHRA · Trace"
	var rw := _text_width(right, small)
	_text(buf, w, h, right, w - margin - rw, base_y, small, DIM)
	var max_w := w - 2 * margin - rw - 40
	_text(buf, w, h, _fit(str(meta.get("title", "")), big, max_w), margin, base_y, big, TEXT)
	_text(buf, w, h, _fit("  ·  ".join(parts), small, max_w), margin,
		base_y + int(small * 1.7), small, DIM)


static func _fit(t: String, size: int, max_w: int) -> String:
	if _text_width(t, size) <= max_w:
		return t
	while t.length() > 1:
		t = t.substr(0, t.length() - 1)
		if _text_width(t + "…", size) <= max_w:
			break
	return t + "…"


## [TextServer, RID] des gesetzten Textes; [null, RID()] wenn nicht moeglich.
static func _shape(t: String, size: int) -> Array:
	var font := ThemeDB.fallback_font
	var ts := TextServerManager.get_primary_interface()
	if font == null or ts == null or t == "" or font.get_rids().is_empty():
		return [null, RID()]
	var rid := ts.create_shaped_text()
	ts.shaped_text_add_string(rid, t, font.get_rids(), size, {}, "de")
	ts.shaped_text_shape(rid)
	return [ts, rid]


static func _text_width(t: String, size: int) -> int:
	var s := _shape(t, size)
	if s[1] == RID():
		return 0
	var ts: TextServer = s[0]
	var wd := ts.shaped_text_get_size(s[1]).x
	ts.free_rid(s[1])
	return int(ceil(wd))


## Text per TextServer-Glyphen in den Puffer (Grundlinie bei x, y).
static func _text(buf: PackedByteArray, w: int, h: int, t: String, x: int, y: int, size: int,
		col: Color) -> void:
	var s := _shape(t, size)
	if s[1] == RID():
		return
	var ts: TextServer = s[0]
	var rid: RID = s[1]
	var pen := float(x)
	var cr := col.r * 255.0
	var cg := col.g * 255.0
	var cb := col.b * 255.0
	var fsz := Vector2i(size, 0)
	for g in ts.shaped_text_get_glyphs(rid):
		var frid: RID = g.font_rid
		var gi: int = g.index
		if frid != RID() and gi != 0:
			ts.font_render_glyph(frid, fsz, gi)
			var tex_i := ts.font_get_glyph_texture_idx(frid, fsz, gi)
			if tex_i >= 0:
				var img := ts.font_get_texture_image(frid, fsz, tex_i)
				var uv := ts.font_get_glyph_uv_rect(frid, fsz, gi)
				var go := ts.font_get_glyph_offset(frid, fsz, gi)
				if img != null and not img.is_empty():
					var gx := int(pen + g.offset.x + go.x)
					var gy := int(y + g.offset.y + go.y)
					for yy in int(uv.size.y):
						for xx in int(uv.size.x):
							var px := gx + xx
							var py := gy + yy
							if px < 0 or py < 0 or px >= w or py >= h:
								continue
							var a := img.get_pixel(int(uv.position.x) + xx,
								int(uv.position.y) + yy).a * col.a
							if a <= 0.003:
								continue
							var i := (py * w + px) * 4
							buf[i] = int(buf[i] + (cr - buf[i]) * a)
							buf[i + 1] = int(buf[i + 1] + (cg - buf[i + 1]) * a)
							buf[i + 2] = int(buf[i + 2] + (cb - buf[i + 2]) * a)
		pen += float(g.advance)
	ts.free_rid(rid)
