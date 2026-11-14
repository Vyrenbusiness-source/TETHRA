class_name TurboController
extends TempoMode

## Turbo in der Mania-Szene: TurboRule entscheidet (nur im echten Lauf), der
## Rate-Verlauf steuert Audio (SyncClock.set_rate) und Fenster (core.rate_track).
## Replay: Verlauf aus GameSession.mods["TB_track"], keine eigene Entscheidung.
## Anzeige links neben dem Feld: ruhige Tempo-Zahl, Abschnittszaehler.

var rule := TurboRule.new()
var keep_pitch := false
var replay := false
var _layer: CanvasLayer
var _box: VBoxContainer
var _value: Label
var _sub: Label
var _shown_rate := -1.0
var _tint := 0.0
var _tint_col := UiTheme.TEXT
var _info: Label


func _setup() -> void:
	var bm: Beatmap = host.get("_beatmap")
	rule.setup(bm)
	replay = GameSession.is_replay
	if replay:
		var tr := RateTrack.from_array(GameSession.mods.get("TB_track", []))
		if tr != null:
			rule.track = tr
		keep_pitch = bool(GameSession.mods.get("TB_pitch", false))
	else:
		keep_pitch = TempoPrefs.keep_pitch()
		GameSession.mods["TB_pitch"] = keep_pitch
	var core: ManiaCore = host.get("core")
	core.rate_track = rule.track
	if not replay:
		core.note_judged.connect(_on_judged)
	SyncClock.set_rate(rule.track.rate_at(SyncClock.judgement_time_ms()), keep_pitch)
	_build_hud()


func _on_judged(index: int, result: Dictionary) -> void:
	if int(result.get("quality", 0)) != ManiaCore.Quality.MISS:
		return
	var bm: Beatmap = host.get("_beatmap")
	rule.on_miss(bm.hit_objects[index].time, SyncClock.judgement_time_ms())


func tick(t: float) -> void:
	var core: ManiaCore = host.get("core")
	if not replay:
		rule.tick(t, core.is_judged)
	var r := rule.track.rate_at(t)
	if not is_equal_approx(r, SyncClock.get_rate()):
		SyncClock.set_rate(r, keep_pitch)
	_update_hud(r, get_process_delta_time())


func owns_results(s: Dictionary, is_fail: bool) -> bool:
	var bm: Beatmap = host.get("_beatmap")
	var end_ms: float = bm.duration_ms()
	if is_fail:
		end_ms = minf(end_ms, SyncClock.judgement_time_ms())
	var peak := rule.peak_rate(end_ms)
	GameSession.mods["TB"] = true
	GameSession.mods["TB_track"] = rule.track.to_array()
	GameSession.mods["TB_pitch"] = keep_pitch
	s["unranked"] = true
	s["turbo_peak"] = peak
	s["mod_texts"] = ["Turbo " + RateTrack.pct_text(peak)]
	var rank := 0
	var autoplay: bool = bool(host.get("_autoplay"))
	if not GameSession.is_replay and not autoplay:
		rank = TurboStore.submit(GameSession.osz_path, bm.version_name(), {
			"peak": peak, "score": int(s.score), "accuracy": float(s.accuracy),
			"failed": is_fail, "pitch": keep_pitch,
			"date": Time.get_datetime_string_from_system(),
		})
		ReplayStore.save(GameSession.osz_path, bm.version_name(), host.get("_recorded"), {
			"score": int(s.score), "grade": str(s.grade), "accuracy": float(s.accuracy),
			"date": Time.get_datetime_string_from_system(),
			"mods": GameSession.mods.duplicate(), "turbo_peak": peak,
		})
	if _box != null:
		_box.visible = false
	_show_summary(peak, rank, bm)
	return true


# --- Anzeige ------------------------------------------------------------------

func _build_hud() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 2
	add_child(_layer)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 0)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.anchor_top = 0.38
	_box.anchor_bottom = 0.38
	_box.offset_left = 36
	_box.offset_right = 236
	_layer.add_child(_box)
	var cap := UiTheme.section_label(TranslationServer.translate("Tempo"))
	_box.add_child(cap)
	_value = Label.new()
	_value.add_theme_font_override("font", UiTheme.heading_font(0))
	_value.add_theme_font_size_override("font_size", 44)
	_value.add_theme_color_override("font_color", UiTheme.TEXT)
	_box.add_child(_value)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 13)
	_sub.add_theme_color_override("font_color", UiTheme.DIM)
	_box.add_child(_sub)
	_update_hud(rule.track.rate_at(SyncClock.judgement_time_ms()), 0.0)


func _update_hud(r: float, delta: float) -> void:
	if _value == null:
		return
	if not is_equal_approx(r, _shown_rate):
		# Kein Blitz: Zahl wechselt, Farbe klingt in 0,6 s ruhig aus.
		if _shown_rate > 0.0:
			_tint = 1.0
			_tint_col = UiTheme.ACCENT if r > _shown_rate else UiTheme.DIM
		_shown_rate = r
		_value.text = RateTrack.pct_text(r)
	if _tint > 0.0:
		_tint = maxf(_tint - delta / 0.6, 0.0)
		_value.add_theme_color_override("font_color", UiTheme.TEXT.lerp(_tint_col, _tint))
	_sub.text = TranslationServer.translate("Section %d / %d") % [
			mini(rule.sections_done() + 1, rule.secs.size()), rule.secs.size()] \
			+ "  ·  " + TranslationServer.translate("best %s") % RateTrack.pct_text(
			rule.peak_rate(SyncClock.judgement_time_ms()))


func _show_summary(peak: float, rank: int, bm: Beatmap) -> void:
	var lay := CanvasLayer.new()
	lay.layer = 60
	add_child(lay)
	_info = Label.new()
	_info.anchor_left = 0.5
	_info.anchor_right = 0.5
	_info.offset_left = -400
	_info.offset_right = 400
	_info.offset_top = 14
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_override("font", UiTheme.heading_font(0))
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_color", UiTheme.ACCENT)
	var parts := [TranslationServer.translate("Turbo"),
		TranslationServer.translate("Top tempo %s") % RateTrack.pct_text(peak),
		TranslationServer.translate("%d clean sections") % rule.clean]
	if rank > 0:
		parts.append(TranslationServer.translate("local rank %d of %d") % [rank,
				TurboStore.list_for(GameSession.osz_path, bm.version_name()).size()])
	_info.text = "  ·  ".join(parts)
	lay.add_child(_info)
