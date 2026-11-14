extends Control

## Song-Browser (Rhythia-Vorlage): Vollbild-Hintergrund der Auswahl, Info-Panel
## links (Sterne, Bestwert, SPIELEN), Mitte Cover-Buehne mit Visualizer, rechts
## Karten mit Cover und Grade-Badge. Kopfzeile: Profil, Tabs, Suche, Einstellungen.
## Sterne kommen ausschliesslich aus rosu-pp (StarService, Regel 9).
## Neue .osz einfach ins Fenster ziehen -> Import + Neuscan.

const COL_BG := Color(0.03, 0.03, 0.05)
const COL_PANEL := Color(0.07, 0.07, 0.10, 0.92)
const COL_CARD := Color(0.08, 0.08, 0.11, 0.94)
const COL_CARD_SEL := Color(0.13, 0.13, 0.18, 0.98)
const COL_ACCENT := UiTheme.ACCENT
const COL_TEXT := UiTheme.TEXT
const COL_DIM := UiTheme.DIM
# Raster: 24 px Aussenrand, rechte Spalte (Toolbar, Filter, Liste) gleich breit.
const M := 24
const INFO_W := 400
const RIGHT_W := 640
const HEAD_Y := 24
const HEAD_H := 40
const FILTER_Y := 76
const FILTER_H := 32
## Zweite Filterreihe: Bestwert (mit/ohne) und Bestwert-Note, je Modus.
const SCORE_Y := FILTER_Y + FILTER_H + 8
const SCORE_H := 30
const CHIPS_Y := SCORE_Y + SCORE_H + 8
const CHIPS_H := 30
const GRADE_COLOR := {
	"S": Color(1.0, 0.85, 0.25), "A": Color(0.4, 1.0, 0.5),
	"B": Color(0.35, 0.75, 1.0), "C": Color(0.9, 0.6, 1.0),
	"D": Color(1.0, 0.4, 0.4),
}

var _library: MapLibrary
var _filtered: Array[MapSet] = []
var _selected_set: MapSet = null
var _selected_diff := 0

var _bg: TextureRect
var _cover: TextureRect
var _stage: Control
var _stage_shadow: Panel
var _stage_mask: Panel
var _stage_viz: AudioVisualizer
var _title_label: Label
var _artist_label: Label
var _mapper_label: Label
var _diff_label: Label
var _stats_label: Label
var _star_label: Label
var _best_label: Label
var _lb_box: VBoxContainer
var _list_box: VBoxContainer
var _search: LineEdit
var _count_label: Label
var _card_buttons: Array[Button] = []
# Bass-Reaktion der Vorschau (dezent): Onset gegen gleitenden Mittelwert.
var _pulse_card: Button = null
var _play_btn: Button
# Glow der ausgewaehlten Karte: dieselbe StyleBox wird pro Frame nur
# skalar angepasst (keine Allokation).
var _sel_box: StyleBoxFlat = null
# Info-Panel: BPM/Laenge-Chips, Diff-Farbbalken, Vorschau-Fortschritt.
var _bpm_label: Label
var _len_label: Label
var _diff_bar: HBoxContainer
var _progress_bg: Control
var _progress_fill: ColorRect
var _preview_len := 0.0
var _bpm_cache: Dictionary = {}
# Weiches Scrollen der Liste beim Kartenwechsel.
var _scroll_tween: Tween
const CARD_H := 76.0
const CARD_RADIUS := 6
var _frame_idle: StyleBoxFlat
var _frame_hover: StyleBoxFlat
var _frame_sel: StyleBoxFlat
var _glow_box: StyleBoxFlat
var _card_cover_mat: ShaderMaterial
var _card_cover_size := Vector2.ZERO
const CARD_SLIDE := 8.0
const LIST_PAD := 16
const LIST_TOP := SCORE_Y + SCORE_H
const LIST_EDGE := 6
var _list_mask: TextureRect
var _list_grad: Gradient
var _preview: AudioStreamPlayer
var _preview_fade: Tween
var _preview_gain_db := 0.0
# Vorschau ~3 dB unter Gameplay-Pegel, mit sanfter Einblendung.
const PREVIEW_DB := -3.0
const PREVIEW_SILENT_DB := -60.0
const PREVIEW_FADE_OUT := 0.12
const PREVIEW_FADE_IN := 0.25
var _beat := BeatClock.new()
var _preview_set: MapSet = null
var _tp_cache: Dictionary = {}

## Aktiver No-Fail-Mod: Health kann nicht auf 0 fallen, Play zaehlt unranked.
var _nf_enabled := Settings.mod_nf
var _nf_btn: Button
## SV-Mod: jede Map mit generierten Tempowechseln (SvMod), Score x1.10.
var _sv_enabled := Settings.mod_sv
var _sv_btn: Button
var _sv_level_box: Control
## Orbit-Mods (OrbitCore.ORBIT_MODS): nur im Orbit-Modus sichtbar und aktiv,
## dort statt SV. HD und FI schliessen sich aus. Gespeichert im Browser-Zustand.
var _orbit_mods := {"HD": false, "FI": false, "PR": false}
var _orbit_mod_btns := {}
## Trace-Mods (TraceMods.MODS): nur im Trace-Modus sichtbar, neben No-Fail.
var _trace_mods := {"MR": false, "HD": false, "SS": false}
var _trace_mod_btns := {}
## Regel-Mods (RuleMods.KEYS: SD, PF, MN), sichtbar je RuleMods.MODES. Browser-Zustand.
var _rule_mods := {"SD": false, "PF": false, "MN": false}
var _rule_mod_btns := {}
const TRACE_MOD_TIPS := {
	"MR": "Mirror: links und rechts getauscht (Score x1,0)",
	"HD": "Hidden: der Weg blendet zum Kopf hin aus (Score x1,06)",
	"SS": "Short Sight: nur 500 ms Weg voraus (Score x1,08)",
}
const ORBIT_MOD_TIPS := {
	"HD": "Hidden: Ziele verblassen kurz vor dem Ring (Score x1,06)",
	"FI": "Fade-In: Ziele erscheinen erst spät (Score x1,06)",
	"PR": "Präzision: Zeit- und Zielfenster 30 % enger (Score x1,12)",
}
## SV-Stufe (SvMod.strength): kleine Auswahl Normal | Stark am SV-Chip.
var _sv_level_btns: Array[Button] = []
## Ranglisten-Kopf: Titel + Modus-Tag (Mania 4K / Orbit).
var _lb_title: Label
var _lb_mode_tag: Label
## Beste Scores: false = lokal, true = Online-Rangliste (OnlineApi).
var _lb_online := false
var _lb_src_btns: Array[Button] = []
var _online_gen := 0
var _online_md5_cache: Dictionary = {}
## Maps, für die der pp-Nachtrag aus der Online-Rangliste schon versucht wurde.
var _pp_fill_tried: Dictionary = {}

# Lazy-Loading der Karten-Thumbnails (2 pro Frame).
var _thumb_queue: Array = []
# Lade-Messung (--perf): Startzeit von _ready bzw. der letzten Auswahl.
var _perf_ready_t := 0
var _perf_select_t := 0
# Hintergrund-Vorbereitung der Auswahl (Parse + Audio + Cover), entprellt:
# erst wenn die Auswahl PREPARE_DELAY_MS stabil ist (schnelles Scrollen
# startet keine Task-Lawine). Full-Res-Cover kommt danach aus dem Cache.
const PREPARE_DELAY_MS := 100
const THUMB_BUDGET_USEC := 4000
var _prep_due := 0
var _bg_wait_set: MapSet = null
# Gameplay-Szenen + ihre schweren Assets im Hintergrund vorladen
# (ResourceLoader-Threads): SPIELEN wechselt dann per change_scene_to_packed,
# ohne mania_3d.gd erst zu kompilieren und die Stationen zu laden. Statisch
# gehalten -> bleiben im ResourceCache, auch fuer Retry/naechsten Song.
const GAME_SCENES := ["res://scenes/mania_3d.tscn", "res://scenes/gameplay_3d.tscn", "res://scenes/orbit.tscn"]
const GAME_ASSET_DIRS := ["res://assets_game/stations"]
const GAME_PRELOAD_DELAY := 0.3
static var _game_res: Dictionary = {}
static var _game_req: Array[String] = []   # laufende Requests (ueberleben Szenenwechsel)
var _game_preload_t := 0
# scores.cfg einmal pro Kartenaufbau lesen (statt pro Karte und Diff).
var _scores_cfg: ConfigFile = null
var _replay_btn: Button

# Collections-Ansicht.
var _collection_mode := false
var _active_collection := ""
var _chips_row: HFlowContainer
var _coll_undo := ""  # zuletzt geloeschte Sammlung (Rueckgaengig-Chip)
var _coll_unplayable: Array = []  # Maps der Sammlung ohne Diff fuer den Modus (markierte Karten)
# Lokale Filter: Sterne-Bereich + Sortierung (clean als Chip-Reihe).
var _star_filter := 0
## Sortierung (SORT_*) und Bestwert-Filter je Spielmodus getrennt:
## {"mania": {"sort": int, "best": BEST_*, "grades": Array[String]}, "orbit": {...}}
var _mode_filters := {}
var _sort_btn: OptionButton
var _best_chips: Array[Button] = []
var _grade_chips := {}
## Je Modus einmal aus scores.cfg gebaut (build_score_index), nicht pro Karte.
var _score_index := {}
## Aenderungszeit der .osz (Sortierung "Zuletzt heruntergeladen"), je Pfad einmal.
var _mtime_cache := {}
var _star_chips: Array[Button] = []
var _sv_filter := false
## Filter/Sortierung/Sammlung/Suche bleiben ueber Map-Ende und Neustart erhalten.
const BROWSER_STATE_PATH := "user://browser_state.cfg"
var _state_ready := false
## Spielmodus fuer 4K-Diffs: "mania" (Standard, unveraendert) oder "orbit"
## (zusaetzlicher Modus). Wird mit dem Browser-Zustand gemerkt.
const PLAY_MODES := ["mania", "orbit", "rally", "dirigent", "trace", "rebound"]
var _play_mode := "mania"
var _mode_btns: Array[Button] = []
## Kleiner "Tutorial"-Knopf neben dem Modus-Umschalter (nur wenn der Modus eins hat).
var _tutorial_btn: Button = null
## Orbit-Einfuehrung: dezenter Hinweis beim ersten Wechsel auf Orbit, bis
## das Tutorial einmal gesehen (gestartet oder weggeklickt) ist.
const ORBIT_TUTORIAL_SCENE := "res://scenes/orbit_tutorial.tscn"
const ORBIT_TUTORIAL_SCRIPT := "res://scripts/orbit/orbit_tutorial.gd"
var _orbit_hint: PanelContainer
var _orbit_hint_force := false  # Harness: auch wenn schon gesehen
var _hint_kind := ""            # "teach" (Tutorial) | "offer" (Karriere)
## Filter-Reihen als ein Stapel: die Listen-Oberkante folgt seiner echten Hoehe.
var _filter_stack: VBoxContainer
var _filter_row: HBoxContainer
var _score_chips_row: HBoxContainer
## Orbit-Karriere (scripts/orbit/orbit_career.gd): Umschalter Karriere | Frei,
## Panel statt Liste, Empfehlungen im Frei-Modus.
var _career_row: HBoxContainer
var _career_btns: Array[Button] = []
var _career_level_lbl: Label
var _career_panel: OrbitCareerPanel
var _career_state := {}
var _career_items: Array = []        # aktuelle Vorschlaege (Reihenfolge wie im Panel)
var _career_dirty := false           # Panel-Neuaufbau steht aus (entprellt)
var _share_btn: Button
var _marathon_btn: Button
var _saved_search := ""
var _sv_chip: Button
# Max-pp (SS) der ausgewaehlten Diff — rosu-pp im Hintergrund-Thread.
var _maxpp_label: Label
var _maxpp_thread: Thread
var _tab_collections: Button
var _tab_downloaded: Button
var _tab_online: Button
var _scroll: ScrollContainer

# Online-Tab (Mirror catboy.best): eigener Browser, bleibt versteckt am Leben.
var _online: OnlineBrowser = null
# Schwierigkeits-Filter der Bibliothek (client-seitig).
const SORT_TITLE := 0
const SORT_STARS_UP := 1
const SORT_STARS_DOWN := 2
const SORT_RECENT := 3
const SORT_DOWNLOADED := 4
const SORT_MOST_PLAYED := 5
const SORT_NAMES := ["Titel", "Sterne aufsteigend", "Sterne absteigend",
	"Zuletzt gespielt", "Zuletzt heruntergeladen", "Meistgespielt"]
const BEST_ALL := 0
const BEST_WITH := 1
const BEST_WITHOUT := 2
const BEST_NAMES := ["Alle", "Mit Bestwert", "Ohne Bestwert"]
## Noten-Chips; "D" umfasst auch "F".
const GRADE_CHIPS := ["SS", "S", "A", "B", "C", "D"]
const STAR_FILTERS := [
	["Alle", 0.0, 999.0],
	["<2★", 0.0, 2.0],
	["2–4★", 2.0, 4.0],
	["4–6★", 4.0, 6.0],
	["6★+", 6.0, 999.0],
]
func _ready() -> void:
	_perf_ready_t = Time.get_ticks_usec()
	MarathonRun.end()  # zurueck im Browser: kein Marathon mehr aktiv
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_library = MapLibrary.new()
	_library.scan()
	GameSession.perf_since("Browser: Library-Scan gesamt", _perf_ready_t)
	# SV-Erkennung fuer alte Cache-Eintraege im Hintergrund nachrechnen.
	_library.start_sv_backfill(_on_sv_backfill_done)

	_preview = AudioStreamPlayer.new()
	_preview.bus = "Music"
	_preview.volume_db = PREVIEW_DB
	add_child(_preview)

	var t_ui := Time.get_ticks_usec()
	var restore := _load_browser_state()
	if OS.get_cmdline_args().has("--orbit"):
		_play_mode = "orbit"  # Debug/Shots: Orbit vorwaehlen (nie gespeichert)
	for a in OS.get_cmdline_args():
		if a.begins_with("--mode=") and PLAY_MODES.has(a.trim_prefix("--mode=")):
			_play_mode = a.trim_prefix("--mode=")  # Debug/Shots: Modus vorwaehlen (nie gespeichert)
	for a in OS.get_cmdline_args():
		# Debug/Shots: --filter=sort=3,best=1,grades=S+A fuer den aktiven Modus (nie gespeichert).
		if a.begins_with("--filter="):
			var d := {}
			for part in a.trim_prefix("--filter=").split(","):
				var kv := part.split("=")
				if kv.size() == 2:
					d[kv[0]] = Array(kv[1].split("+")) if kv[0] == "grades" else int(kv[1])
			_mode_filters[_play_mode] = sanitize_mode_filter(d)
	for a in OS.get_cmdline_args():
		# Debug/Shots: --rec-level=push, --rec-hidden, --rec-collapsed (nie gespeichert).
		if a.begins_with("--rec-level="):
			_rec = rec_sanitize(_rec)
			_rec.levels[_play_mode] = Recommender.normalize_level(a.trim_prefix("--rec-level="))
		elif a == "--rec-hidden" or a == "--rec-collapsed":
			_rec[a.trim_prefix("--rec-")] = true
	_career_state = OrbitCareer.load_state()
	if OS.get_cmdline_args().has("--career"):
		_career_state["mode"] = OrbitCareer.MODE_CAREER  # Debug/Shots: nie gespeichert
	elif OS.get_cmdline_args().has("--career-free"):
		_career_state["mode"] = OrbitCareer.MODE_FREE
	_coll_translations()
	_build_ui()
	GameSession.perf_since("Browser: UI aufbauen", t_ui)
	t_ui = Time.get_ticks_usec()
	if restore:
		_search.text = _saved_search
		if _collection_mode:
			_set_collection_mode(true)
	for a in OS.get_cmdline_args():
		# Harness: --shot-coll oder --shot-coll=<Name> startet in der Sammlungs-Ansicht
		# (nie gespeichert; Daten aus --collections-path=<Test-Kopie>).
		if a == "--shot-coll" or a.begins_with("--shot-coll="):
			var cn := a.trim_prefix("--shot-coll").trim_prefix("=")
			_active_collection = cn if CollectionStore.exists(cn) else ""
			_set_collection_mode(true)
		# Harness: dazu den Dialog "Neue Sammlung" (Modus-Wahl) oeffnen; speichert nichts.
		if a == "--shot-coll-dialog":
			_collection_name_dialog.call_deferred(tr("Neue Sammlung"), "", tr("Anlegen"),
				func(_n: String, _m: String) -> bool: return true, _play_mode)
	_apply_career_layout()
	_refresh_filter(_search.text)
	_state_ready = restore
	_career_start.call_deferred()
	GameSession.perf_since("Browser: %d Karten bauen" % _filtered.size(), t_ui)
	get_window().files_dropped.connect(_on_files_dropped)
	_offer_own_songs.call_deferred()
	t_ui = Time.get_ticks_usec()
	_select_initial()
	_recs_refresh.call_deferred()
	GameSession.perf_since("Browser: Startauswahl (Info, Cover, Vorschau)", t_ui)
	GameSession.perf_since("Browser: _ready gesamt", _perf_ready_t)
	get_tree().create_timer(GAME_PRELOAD_DELAY).timeout.connect(_begin_game_preload)

	if OS.get_cmdline_args().has("--sv"):
		_on_sv_toggled(true)  # Debug/Shots: SV-Mod vorwaehlen
	for a in OS.get_cmdline_args():
		if a.begins_with("--rule-mods="):
			# Debug/Shots: --rule-mods=SD,MN nur fuer diesen Lauf (nie gespeichert).
			_state_ready = false
			for k in RuleMods.KEYS:
				_rule_mods[k] = k in a.trim_prefix("--rule-mods=").to_upper().split(",")
			if RuleMods.is_rule(_rule_mods):
				_nf_enabled = false
				_update_nf_button()
			_sync_rule_mod_buttons()
			if _selected_set != null:
				_update_info_panel()   # Minen-Liste unter BESTE SCORES
	if DisplayServer.get_name() == "headless":
		_headless_report()
	elif GameSession.perf_enabled:
		_perf_flow.call_deferred()
	elif OS.get_cmdline_args().has("--orbit") and OS.get_cmdline_args().has("--autoplay"):
		# Debug/Shots: erste 4K-Diff im Orbit-Modus automatisch starten.
		# --orbit-mods=HD,PR setzt Orbit-Mods nur fuer diesen Lauf (nie gespeichert).
		_play_mode = "orbit"
		for a in OS.get_cmdline_args():
			if a.begins_with("--orbit-mods="):
				_state_ready = false  # Debug-Mods nie in browser_state.cfg
				for k in OrbitCore.ORBIT_MODS:
					_orbit_mods[k] = k in a.trim_prefix("--orbit-mods=").to_upper().split(",")
		var pk := _debug_pick()
		if not pk.is_empty():
			_select_set(pk[0], pk[1])
			_selected_diff = pk[1]
			_on_play_pressed.call_deferred()
			return
		push_warning("--orbit: keine passende 4K-Diff gefunden")
	elif OS.get_cmdline_args().has("--mania"):
		# Debug: erste 4K-Mania-Diff automatisch starten.
		var pk := _debug_pick()
		if not pk.is_empty():
			_select_set(pk[0], pk[1])
			_selected_diff = pk[1]
			_on_play_pressed.call_deferred()
			return
		push_warning("--mania: keine passende 4K-Diff gefunden")
	elif OS.get_cmdline_args().has("--autoplay"):
		_on_play_pressed.call_deferred()
	elif OS.get_cmdline_args().has("--shot-sv"):
		_shot_sv.call_deferred()
	elif _arg_value("--shot-recs") != null:
		# Harness: "For you" mit Beispiel-Profil und Online-Gruppe (ohne Netz) als PNG.
		_shot_recs.call_deferred()
	elif OS.get_cmdline_args().has("--shot-modes"):
		# Harness: Scores je Modus (Browser, Results, Profil) als PNGs.
		_shot_modes.call_deferred()
	elif OS.get_cmdline_args().has("--shot-online"):
		# Harness: Online-Tab (Raster, Genre, Download, Fehler) als PNGs.
		_shot_online.call_deferred()
	elif GameSession.has_meta(&"open_marathon") or MarathonPanel.shot_dir() != "":
		# Hauptmenue "Marathon" bzw. Harness: Marathon-Auswahl gleich oeffnen.
		GameSession.remove_meta(&"open_marathon")
		_open_marathon.call_deferred()
	elif OS.get_cmdline_args().has("--shot-import"):
		# Harness: Import-Fenster mit Fortschritt und Drop-Hinweis als PNGs.
		_shot_import.call_deferred()
	elif OS.get_cmdline_args().has("--shot-orbit-hint"):
		# Harness: Hinweis "Orbit lernen" beim Wechsel auf Orbit als PNG.
		_shot_orbit_hint.call_deferred()
	elif OS.get_cmdline_args().has("--shot-settings"):
		# Harness: Einstellungen oeffnen, das Panel fotografiert seine Reiter selbst.
		# --skin2d=<Ordnername>: Skin fuer die Vorschau (nur im Speicher, nicht gespeichert).
		for a in OS.get_cmdline_args():
			if a.begins_with("--skin2d="):
				Settings.skin_2d = a.trim_prefix("--skin2d=")
		add_child.call_deferred(SettingsPanel.new())
	elif OS.get_cmdline_args().has("--rules-harness"):
		RuleModsHarness.run_browser(self)   # Harness: Regel-Mods per Klick, Minen-Liste, Replay
	elif OS.get_cmdline_args().has("--shot"):
		_capture_screenshot_and_quit()


## Debug (--mania/--orbit): erste im Modus sichtbare Diff (Orbit auch osu!standard), optional gefiltert. --map=<text>
## sucht in "artist - title [version]", --diff=<text> in der Version (beides
## ohne Gross/Klein). Nur fuer Harness/Videos, nie gespeichert. [] = keine.
func _debug_pick() -> Array:
	var map_q := ""
	var diff_q := ""
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map_q = a.trim_prefix("--map=").to_lower()
		elif a.begins_with("--diff="):
			diff_q = a.trim_prefix("--diff=").to_lower()
	for ms in _library.mapsets if map_q != "" else _filtered:
		for i in ms.difficulty_count():
			if not MapSet.mode_shows(ms.meta_at(i), _vm()):
				continue
			var ver := ms.version_name_at(i)
			var full := ("%s - %s [%s]" % [ms.artist, ms.title, ver]).to_lower()
			if map_q != "" and not full.contains(map_q):
				continue
			if diff_q != "" and not ver.to_lower().contains(diff_q):
				continue
			return [ms, i]
	return []


## Lade-Messung: Map wechseln (Auswahl -> Vorschau-Ton), kurz warten, SPIELEN.
func _perf_flow() -> void:
	var picks: Array = []
	for ms in _filtered:
		for i in ms.difficulty_count():
			if int(ms.meta_at(i).get("mode", 0)) == 3:
				picks.append([ms, i])
				break
	var at := 0
	for k in picks.size():
		if picks[k][0] == _selected_set:
			at = k
	for step in 2:
		await get_tree().create_timer(1.5).timeout
		if picks.is_empty():
			_move_selection(1)
		else:
			var pk: Array = picks[(at + 1 + step) % picks.size()]
			_select_set(pk[0], pk[1])
	await get_tree().create_timer(2.0).timeout
	GameSession.perf_request("SPIELEN -> Gameplay")
	_on_play_pressed()


## Harness: Browser mit aktivem SV-Chip, danach Online-Panel mit SV-Chip.
func _shot_sv() -> void:
	var dir := OS.get_environment("SV_SHOT_DIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	# Backfill abwarten (max. 60 s).
	var waited := 0.0
	while _library.sv_backfill_running() and waited < 60.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	_sv_filter = true
	_restyle_star_chips()
	_refresh_filter(_search.text)
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("sv_browser.png"))
	print("SV-Sets lokal: %d von %d" % [_filtered.size(), _library.mapsets.size()])
	_open_download_panel()
	await get_tree().create_timer(1.0).timeout
	_online._set_sv(true)
	await _online._wait_loaded(120.0)
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("sv_online.png"))
	print("SV-DL-KARTEN: %d" % _online._rows.size())
	get_tree().quit(0)


func _shot_online() -> void:
	var dir := OS.get_environment("ONLINE_SHOT_DIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	_open_download_panel()
	await _online.run_shot_harness(dir)
	get_tree().quit(0)


## Harness --shot-modes: Demo-Scores (Mania, Mania+SV, Orbit) fuer die erste
## 4K-Diff, dann Browser in beiden Modi, Results mit Modus-Abzeichen und
## Profil in beiden Modi als PNGs (MODES_SHOT_DIR). Laeuft NUR mit
## --scores-path=<Test-Kopie>, nie gegen user://scores.cfg; speichert weder
## Browser-Zustand noch Settings.
func _shot_modes() -> void:
	var has_path := false
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--scores-path="):
			has_path = true
	if not has_path or ScoreStore.PATH == "user://scores.cfg":
		push_error("--shot-modes braucht --scores-path=<Test-Kopie>")
		get_tree().quit(1)
		return
	_state_ready = false  # nichts in browser_state.cfg schreiben
	var dir := OS.get_environment("MODES_SHOT_DIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	var pick: Array = []
	for ms in _filtered:
		for i in ms.difficulty_count():
			if pick.is_empty() and int(ms.meta_at(i).get("mode", 0)) == 3:
				pick = [ms, i]
	if pick.is_empty():
		push_error("--shot-modes: keine 4K-Diff gefunden")
		get_tree().quit(1)
		return
	var ms: MapSet = pick[0]
	var di: int = pick[1]
	var osz: String = ms.osz_path
	var ver: String = ms.version_name_at(di)
	var label := "%s - %s" % [ms.artist, ms.title]
	var demo := [
		[{ "score": 912340, "grade": "S", "accuracy": 0.9712, "max_combo": 611, "pp": 182.4 }, ""],
		[{ "score": 874015, "grade": "A", "accuracy": 0.9433, "max_combo": 402, "pp": 151.0,
			"mods": ["SV"], "sv_level": "strong" }, ""],
		[{ "score": 801220, "grade": "A", "accuracy": 0.9301, "max_combo": 377, "pp": 139.2,
			"mods": ["SV", "NF"], "sv_level": "normal" }, ""],
		[{ "score": 951880, "grade": "S", "accuracy": 0.9821, "max_combo": 640, "mode": "orbit" }, ScoreStore.MODE_ORBIT],
		[{ "score": 702115, "grade": "B", "accuracy": 0.8874, "max_combo": 210, "mode": "orbit",
			"mods": ["SV"], "sv_level": "strong" }, ScoreStore.MODE_ORBIT],
		[{ "score": 883400, "grade": "A", "accuracy": 0.9520, "max_combo": 498, "mode": "trace" }, ScoreStore.MODE_TRACE],
		[{ "score": 905120, "grade": "S", "accuracy": 0.9655, "max_combo": 530, "mode": "rebound" }, ScoreStore.MODE_REBOUND],
	]
	for d in demo:
		ScoreStore.submit(osz, ver, d[0], d[1])
		ScoreStore.log_play(osz, ver, label, d[0], d[1])
	# SV-Chip mit Stufe sichtbar, ohne Settings zu speichern.
	_sv_enabled = true
	if _sv_btn != null:
		_sv_btn.set_pressed_no_signal(true)
	_restyle_sv_level()
	for mode in PLAY_MODES:
		_play_mode = mode
		_restyle_mode_switch()
		_refresh_card_grades()
		_select_set(ms, di)
		_selected_diff = di
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("modes_browser_%s.png" % mode))
	# Results (Mania + Orbit): Fake-Daten, previous_best explizit (kein Speichern).
	GameSession.osz_path = osz
	GameSession.difficulty_version = ver
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var offs: Array = []
	for _i in 300:
		offs.append(rng.randfn(3.2, 17.0))
	for mode in PLAY_MODES:
		var orbit: bool = mode == "orbit"
		var s := { "score": 958210 if orbit else 931400, "grade": "S", "accuracy": 0.9764,
			"max_combo": 655, "combo": 0, "n_max": 700, "n300": 640, "n200": 41, "n100": 9,
			"n50": 2, "n_miss": 8, "pp": -1.0 if orbit else 190.6, "sv_level": "normal" if orbit else "strong" }
		if mode != "mania":
			s["mode"] = mode
		var rs := ResultsScreen.new()
		add_child(rs)
		rs.show_results({
			"s": s, "pp": float(s.pp), "new_best": true,
			"title": ms.title, "artist": ms.artist,
			"version": ver, "cover_path": "", "offsets": offs, "player": Settings.profile_name,
			"date": Time.get_datetime_string_from_system(), "allow_retry": true, "can_replay": false,
			"mods": { "SV": true, "NF": false },
			"previous_best": ScoreStore.best(osz, ver, "" if mode == "mania" else mode),
		})
		await get_tree().create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("modes_results_%s.png" % mode))
		rs.queue_free()
		await get_tree().process_frame
	# Profil in beiden Modi.
	var pp := ProfilePanel.new()
	add_child(pp)
	for mode in ["", ScoreStore.MODE_ORBIT]:
		pp._set_mode(mode)
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			dir.path_join("modes_profile_%s.png" % ("orbit" if mode != "" else "mania")))
	print("MODES-SHOTS: " + dir)
	get_tree().quit(0)


func _capture_screenshot_and_quit() -> void:
	# Orbit: Sterne werden asynchron berechnet, darum laenger warten.
	var wait := 1.0 if _play_mode == "mania" else 4.0
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-wait="):
			wait = float(a.trim_prefix("--shot-wait="))  # Orbit-Karriere: Sterne brauchen laenger
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_user_data_dir().path_join("song_select.png")
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-out="):
			path = a.trim_prefix("--shot-out=")
	img.save_png(path)
	print("SHOT gespeichert: " + path)
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# UI-Aufbau
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_bg = TextureRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.modulate = Color(0.30, 0.29, 0.28)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(UiTheme.BG.r, UiTheme.BG.g, UiTheme.BG.b, 0.60)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_init_card_styles()
	_build_header()
	_build_info_panel()
	_build_stage()
	_build_list()
	_build_career_panel()
	_update_list_top()


func _build_header() -> void:
	# Profil-Ecke links oben: Name + pp in einer Zeile, Zahnrad daneben.
	var left := HBoxContainer.new()
	left.position = Vector2(M, HEAD_Y)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	var profile_panel := PanelContainer.new()
	var pbox := UiTheme.glass_box(10, 0.5)
	pbox.content_margin_left = 14
	pbox.content_margin_right = 14
	profile_panel.add_theme_stylebox_override("panel", pbox)
	profile_panel.custom_minimum_size = Vector2(0, HEAD_H)
	left.add_child(profile_panel)
	var pv := HBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	profile_panel.add_child(pv)
	var profile := Label.new()
	profile.text = Settings.profile_name
	profile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	profile.add_theme_font_size_override("font_size", 16)
	profile.add_theme_color_override("font_color", COL_TEXT)
	pv.add_child(profile)
	var sub := Label.new()
	sub.text = UiTheme.fmt_pp(ScoreStore.profile_pp())
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", UiTheme.ACCENT2)
	pv.add_child(sub)

	var gear := Button.new()
	gear.text = "⚙"
	gear.tooltip_text = "Einstellungen"
	gear.custom_minimum_size = Vector2(HEAD_H, HEAD_H)
	gear.add_theme_font_size_override("font_size", 18)
	UiTheme.style_ghost_button(gear, 10)
	_square_margins(gear)
	gear.pressed.connect(func(): add_child(SettingsPanel.new()))
	left.add_child(gear)

	# Rechte Spalte: Tabs + Online + Suche. Gleiche Kanten wie Filter und Liste.
	var top_right := HBoxContainer.new()
	_place_right(top_right, HEAD_Y, HEAD_H)
	top_right.add_theme_constant_override("separation", 8)
	add_child(top_right)

	_tab_downloaded = _make_toggle("Heruntergeladen", 15)
	_tab_downloaded.custom_minimum_size = Vector2(0, HEAD_H)
	_tab_downloaded.pressed.connect(func(): _set_collection_mode(false))
	top_right.add_child(_tab_downloaded)

	_tab_collections = _make_toggle("Sammlungen", 15)
	_tab_collections.custom_minimum_size = Vector2(0, HEAD_H)
	_tab_collections.pressed.connect(func(): _set_collection_mode(true))
	top_right.add_child(_tab_collections)
	_style_tabs()

	_tab_online = Button.new()
	_tab_online.text = "Online"
	_tab_online.tooltip_text = "Maps online suchen und laden"
	_tab_online.icon = _download_icon()
	_tab_online.custom_minimum_size = Vector2(0, HEAD_H)
	_tab_online.add_theme_font_size_override("font_size", 15)
	_tab_online.add_theme_constant_override("h_separation", 8)
	UiTheme.style_ghost_button(_tab_online, 10)
	_tab_online.pressed.connect(_open_download_panel)
	top_right.add_child(_tab_online)

	_import_btn = Button.new()
	_import_btn.text = "Importieren"
	_import_btn.tooltip_text = "Maps, Musik oder den osu!-Songs-Ordner übernehmen"
	_import_btn.custom_minimum_size = Vector2(0, HEAD_H)
	_import_btn.add_theme_font_size_override("font_size", 15)
	UiTheme.style_ghost_button(_import_btn, 10)
	_import_btn.pressed.connect(_open_import_panel)
	top_right.add_child(_import_btn)

	# Filter-Reihen stehen in einem Stapel: wird eine Reihe hoeher oder kommt eine
	# dazu (Orbit: Karriere/Frei, Sammlungen), rutscht die Liste mit.
	_filter_stack = VBoxContainer.new()
	_place_right(_filter_stack, FILTER_Y, 0.0)
	_filter_stack.add_theme_constant_override("separation", 8)
	_filter_stack.minimum_size_changed.connect(_update_list_top)
	add_child(_filter_stack)
	_build_career_row()

	# Filter-Reihe: Anzahl links, Sterne-Chips + Sortierung rechtsbuendig.
	var filter_row := HBoxContainer.new()
	filter_row.custom_minimum_size = Vector2(0, FILTER_H)
	filter_row.add_theme_constant_override("separation", 6)
	_filter_stack.add_child(filter_row)
	_filter_row = filter_row

	_count_label = Label.new()
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.add_theme_color_override("font_color", COL_DIM)
	filter_row.add_child(_count_label)
	for fi in STAR_FILTERS.size():
		var chip := _make_toggle(STAR_FILTERS[fi][0], 13, 16)
		chip.custom_minimum_size = Vector2(0, FILTER_H)
		chip.pressed.connect(func():
			_star_filter = fi
			_restyle_star_chips()
			_refresh_filter(_search.text))
		filter_row.add_child(chip)
		_star_chips.append(chip)
	_sv_chip = _make_toggle("SV", 13, 16)
	_sv_chip.custom_minimum_size = Vector2(0, FILTER_H)
	_sv_chip.tooltip_text = "Nur Maps mit Scroll-Velocity-Wechseln (SV)"
	_sv_chip.pressed.connect(func():
		_sv_filter = not _sv_filter
		_restyle_star_chips()
		_refresh_filter(_search.text))
	filter_row.add_child(_sv_chip)
	_restyle_star_chips()
	_sort_btn = OptionButton.new()
	for si in SORT_NAMES.size():
		_sort_btn.add_item(tr(SORT_NAMES[si]), si)
	_sort_btn.select(_sort_mode())
	_sort_btn.tooltip_text = tr("Sortierung (je Modus gemerkt)")
	# Feste Breite (laengster Eintrag): die Reihe springt beim Wechsel nicht.
	_sort_btn.fit_to_longest_item = true
	_sort_btn.custom_minimum_size = Vector2(120, FILTER_H)
	_sort_btn.add_theme_font_size_override("font_size", 13)
	_sort_btn.add_theme_stylebox_override("normal", _toggle_box(false, 10))
	_sort_btn.add_theme_stylebox_override("hover", _toggle_box(false, 10, true))
	_sort_btn.add_theme_stylebox_override("pressed", _toggle_box(false, 10, true))
	_sort_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_sort_btn.add_theme_color_override("font_color", COL_TEXT)
	_sort_btn.item_selected.connect(func(i):
		_mode_filter()["sort"] = i
		_refresh_filter(_search.text))
	filter_row.add_child(_sort_btn)

	# Zweite Reihe: Bestwert-Filter (Segment) + Noten-Chips, je Modus gemerkt.
	var score_row := HBoxContainer.new()
	score_row.custom_minimum_size = Vector2(0, SCORE_H)
	score_row.alignment = BoxContainer.ALIGNMENT_END
	score_row.add_theme_constant_override("separation", 6)
	_filter_stack.add_child(score_row)
	_score_chips_row = score_row
	# "For you" an/aus (Vorschlaege oberhalb der Liste), links in der Reihe.
	_rec_chip = _make_toggle(tr("For you"), 13, 15)
	_rec_chip.custom_minimum_size = Vector2(0, SCORE_H)
	_rec_chip.tooltip_text = tr("Show suggestions")
	_rec_chip.pressed.connect(func(): _set_recs_hidden(not bool(_rec.hidden)))
	score_row.add_child(_rec_chip)
	var rec_gap := Control.new()
	rec_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_row.add_child(rec_gap)
	# Mit/Ohne Bestwert wie der SV-Chip: erneut klicken = wieder alle Maps.
	for bi in [BEST_WITH, BEST_WITHOUT]:
		var chip := _make_toggle(tr(BEST_NAMES[bi]), 13, 15)
		chip.custom_minimum_size = Vector2(0, SCORE_H)
		chip.pressed.connect(func():
			var mf := _mode_filter()
			mf["best"] = BEST_ALL if int(mf["best"]) == bi else bi
			if int(mf["best"]) != BEST_WITH:
				mf["grades"] = []  # Raenge gibt es nur mit Bestwert
			_restyle_score_chips()
			_refresh_filter(_search.text))
		score_row.add_child(chip)
		_best_chips.append(chip)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	score_row.add_child(gap)
	var grade_lbl := Label.new()
	grade_lbl.text = tr("Rang")
	grade_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grade_lbl.add_theme_font_size_override("font_size", 13)
	grade_lbl.add_theme_color_override("font_color", COL_DIM)
	score_row.add_child(grade_lbl)
	for g in GRADE_CHIPS:
		var gchip := _make_toggle(g, 13, 15)
		gchip.custom_minimum_size = Vector2(46, SCORE_H)
		gchip.tooltip_text = tr("Nur Maps mit Bestwert-Rang %s (mehrere möglich)") % g
		var grade: String = g
		gchip.pressed.connect(func():
			var mf := _mode_filter()
			var gs: Array = mf["grades"]
			if gs.has(grade):
				gs.erase(grade)
			else:
				gs.append(grade)
			mf["best"] = BEST_WITH if not gs.is_empty() else mf["best"]
			_restyle_score_chips()
			_refresh_filter(_search.text))
		score_row.add_child(gchip)
		_grade_chips[g] = gchip
	_restyle_score_chips()

	# Chip-Reihe fuer Sammlungen (nur im Collections-Modus sichtbar).
	# Flow: viele Sammlungen brechen um, statt die Spalte zu sprengen.
	_chips_row = HFlowContainer.new()
	_chips_row.custom_minimum_size = Vector2(0, CHIPS_H)
	_chips_row.alignment = FlowContainer.ALIGNMENT_END
	_chips_row.add_theme_constant_override("h_separation", 6)
	_chips_row.add_theme_constant_override("v_separation", 6)
	_chips_row.visible = false
	_filter_stack.add_child(_chips_row)
	_build_recs()

	_search = LineEdit.new()
	_search.placeholder_text = "Map suchen"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(140, HEAD_H)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_stylebox_override("normal", _toggle_box(false, 10))
	var search_focus := _toggle_box(false, 10, true)
	search_focus.border_color = Color(COL_ACCENT, 0.55)
	_search.add_theme_stylebox_override("focus", search_focus)
	_search.text_changed.connect(_refresh_filter)
	top_right.add_child(_search)


## Rechte Spalte: feste Breite RIGHT_W, rechter Rand M (Toolbar = Liste).
func _place_right(c: Control, y: float, h: float) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.offset_left = -M - RIGHT_W
	c.offset_right = -M
	c.offset_top = y
	c.offset_bottom = y + h


func _square_margins(b: Button) -> void:
	for st in ["normal", "hover", "pressed"]:
		var sb := b.get_theme_stylebox(st) as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = 0
			sb.content_margin_right = 0


## Ein Stil fuer aktiv (Akzent-Toenung, Akzentschrift), einer fuer inaktiv (Ghost).
func _toggle_box(active: bool, radius: int, hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(mini(radius, UiTheme.R_MAX))
	sb.set_border_width_all(1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	if active:
		sb.bg_color = Color(COL_ACCENT, 0.24 if hover else 0.16)
		sb.border_color = Color(COL_ACCENT, 0.60)
	else:
		sb.bg_color = Color(1, 1, 1, 0.09 if hover else 0.04)
		sb.border_color = Color(1, 1, 1, 0.22 if hover else 0.12)
	return sb


func _make_toggle(text: String, font_size: int, radius: int = 10) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.set_meta("radius", radius)
	UiTheme._attach_sounds(b)
	_apply_toggle(b, false)
	return b


func _apply_toggle(b: Button, active: bool) -> void:
	var r: int = b.get_meta("radius", 10)
	var n := _toggle_box(active, r)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", _toggle_box(active, r, true))
	b.add_theme_stylebox_override("pressed", n)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fg := COL_ACCENT if active else COL_DIM
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_hover_color", COL_ACCENT if active else COL_TEXT)


## Download-Symbol (Pfeil nach unten auf Linie), einmal gezeichnet.
var _dl_icon_tex: ImageTexture
func _download_icon() -> ImageTexture:
	if _dl_icon_tex == null:
		_dl_icon_tex = _line_icon(16, [
			[Vector2(8, 2), Vector2(8, 10.5)], [Vector2(4.5, 7.5), Vector2(8, 11)],
			[Vector2(11.5, 7.5), Vector2(8, 11)], [Vector2(3, 14), Vector2(13, 14)]])
	return _dl_icon_tex


## Chevron links (dir -1) / rechts (dir 1) fuer die Diff-Auswahl.
func _chevron_icon(dir: int) -> ImageTexture:
	var a := 6.0 if dir > 0 else 10.0
	var b := 10.0 if dir > 0 else 6.0
	return _line_icon(16, [[Vector2(a, 3.5), Vector2(b, 8)], [Vector2(b, 8), Vector2(a, 12.5)]])


## Kleines Linien-Icon (weiss, ~1,6 px, kantengeglaettet) aus Segmenten.
func _line_icon(size: int, segs: Array) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half_w := 0.85
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d := 99.0
			for s in segs:
				var a: Vector2 = s[0]
				var b: Vector2 = s[1]
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				d = minf(d, p.distance_to(a + ab * t))
			var al := clampf(half_w - d + 0.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, al))
	return ImageTexture.create_from_image(img)


func _build_info_panel() -> void:
	# Hoehe folgt dem Inhalt: kein leerer Glasbereich unter der Bestenliste.
	var panel := PanelContainer.new()
	panel.position = Vector2(M, HEAD_Y + HEAD_H + M)
	panel.custom_minimum_size = Vector2(INFO_W, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.glass_box(18, 0.5))
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, M)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	_title_label = _add_label(vb, "", 26, COL_TEXT)
	_title_label.add_theme_font_override("font", UiTheme.heading_font(1))
	_title_label.mouse_filter = Control.MOUSE_FILTER_PASS  # Tooltip mit dem vollen Titel
	var by := VBoxContainer.new()
	by.add_theme_constant_override("separation", 0)
	vb.add_child(by)
	_artist_label = _add_label(by, "", 15, COL_TEXT.darkened(0.12))
	_mapper_label = _add_label(by, "", 13, COL_DIM)

	# Lange Titel kuerzen statt das Panel zu weiten: es bleibt INFO_W breit.
	for lbl in [_title_label, _artist_label, _mapper_label]:
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF  # Umbruch und Kuerzen schliessen sich aus
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_artist_label.mouse_filter = Control.MOUSE_FILTER_PASS

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 2)
	vb.add_child(gap)

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	vb.add_child(diff_row)
	var prev := _icon_button(_chevron_icon(-1), "Vorherige Schwierigkeit")
	prev.pressed.connect(func(): _cycle_difficulty(-1))
	diff_row.add_child(prev)
	_diff_label = Label.new()
	_diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diff_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_diff_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diff_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_diff_label.add_theme_font_size_override("font_size", 16)
	_diff_label.add_theme_color_override("font_color", COL_TEXT)
	diff_row.add_child(_diff_label)
	var next := _icon_button(_chevron_icon(1), "Naechste Schwierigkeit")
	next.pressed.connect(func(): _cycle_difficulty(1))
	diff_row.add_child(next)

	# Diff-Farbbalken: ein Segment pro Difficulty in Sternfarbe, Auswahl hell.
	# Einziger Ort mit Sternfarbe im Panel.
	_diff_bar = HBoxContainer.new()
	_diff_bar.custom_minimum_size = Vector2(0, 8)
	_diff_bar.add_theme_constant_override("separation", 4)
	vb.add_child(_diff_bar)

	# Sterne + BPM + Laenge als ruhige Glas-Chips in einer Reihe.
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	vb.add_child(chip_row)
	_star_label = _info_chip(chip_row)
	_bpm_label = _info_chip(chip_row)
	_len_label = _info_chip(chip_row)

	_stats_label = _add_label(vb, "", 14, COL_DIM)
	_maxpp_label = _add_label(vb, "", 14, UiTheme.ACCENT2)
	for lbl in [_stats_label, _maxpp_label]:
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF  # Umbruch und Kuerzen schliessen sich aus
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var play := Button.new()
	play.text = "Spielen"
	play.custom_minimum_size = Vector2(0, 54)
	play.add_theme_font_size_override("font_size", 22)
	UiTheme.style_button(play, true)
	play.add_theme_font_override("font", UiTheme.heading_font(4))
	# Hover-Glow: weicher Akzent-Schein statt hartem Farbsprung.
	var play_hover := play.get_theme_stylebox("hover") as StyleBoxFlat
	if play_hover != null:
		play_hover = play_hover.duplicate()
		play_hover.shadow_color = Color(COL_ACCENT, 0.35)
		play_hover.shadow_size = 14
		play_hover.shadow_offset = Vector2.ZERO
		play.add_theme_stylebox_override("hover", play_hover)
		play.add_theme_stylebox_override("focus", play_hover)
	play.pressed.connect(_on_play_pressed)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Modus-Umschalter (3x2) mit Tutorial-Knopf als eigene Zeile, SPIELEN darunter.
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	vb.add_child(mode_row)
	var sw := _build_mode_switch()
	sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(sw)
	_tutorial_btn = _make_toggle(tr("Tutorial"), 12, 6)
	_tutorial_btn.custom_minimum_size = Vector2(72, 0)
	_tutorial_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tutorial_btn.pressed.connect(_start_mode_tutorial)
	mode_row.add_child(_tutorial_btn)
	_apply_tutorial_btn()
	vb.add_child(play)
	_play_btn = play

	# Mods + Sammlung: No-Fail als Schalter, Sammlung als Ghost-Button.
	# Umbrechend: im Orbit-Modus kommen HD/FI/PR dazu; eine starre Zeile machte das
	# Panel breiter als INFO_W und es lief unter das Cover in der Mitte.
	var mods_row := HFlowContainer.new()
	mods_row.add_theme_constant_override("h_separation", 8)
	mods_row.add_theme_constant_override("v_separation", 8)
	vb.add_child(mods_row)

	var nf := CheckButton.new()
	nf.text = "No-Fail"
	nf.tooltip_text = "Kein Abbruch bei leerer Lebensleiste"
	nf.focus_mode = Control.FOCUS_NONE
	nf.button_pressed = _nf_enabled
	nf.custom_minimum_size = Vector2(0, 40)
	nf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nf.add_theme_font_size_override("font_size", 14)
	var nf_box := _toggle_box(false, 10)
	nf.add_theme_stylebox_override("normal", nf_box)
	nf.add_theme_stylebox_override("pressed", nf_box)
	nf.add_theme_stylebox_override("hover", _toggle_box(false, 10, true))
	nf.add_theme_stylebox_override("hover_pressed", _toggle_box(false, 10, true))
	nf.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for fc in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		nf.add_theme_color_override(fc, COL_TEXT)
	UiTheme._attach_sounds(nf)
	nf.toggled.connect(_on_nf_toggled)
	mods_row.add_child(nf)
	_nf_btn = nf

	var sv := CheckButton.new()
	sv.text = "SV"
	sv.tooltip_text = "Jede Map mit Tempowechseln"
	sv.focus_mode = Control.FOCUS_NONE
	sv.button_pressed = _sv_enabled
	sv.custom_minimum_size = Vector2(0, 40)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_font_size_override("font_size", 14)
	var sv_box := _toggle_box(false, 10)
	sv.add_theme_stylebox_override("normal", sv_box)
	sv.add_theme_stylebox_override("pressed", sv_box)
	sv.add_theme_stylebox_override("hover", _toggle_box(false, 10, true))
	sv.add_theme_stylebox_override("hover_pressed", _toggle_box(false, 10, true))
	sv.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for fc in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		sv.add_theme_color_override(fc, COL_TEXT)
	UiTheme._attach_sounds(sv)
	sv.toggled.connect(_on_sv_toggled)
	mods_row.add_child(sv)
	_sv_btn = sv
	_sv_level_box = _build_sv_level()
	mods_row.add_child(_sv_level_box)
	for k in OrbitCore.ORBIT_MODS:
		var ob := _make_orbit_mod_button(k)
		mods_row.add_child(ob)
		_orbit_mod_btns[k] = ob
	for k in TraceMods.MODS:
		var tb := _make_trace_mod_button(k)
		mods_row.add_child(tb)
		_trace_mod_btns[k] = tb
	for k in RuleMods.KEYS:
		var rb := _make_rule_mod_button(k)
		mods_row.add_child(rb)
		_rule_mod_btns[k] = rb
	TempoBrowserRow.build(self, mods_row)  # mv-tempo: Turbo, Tonhoehe, Ueben
	_apply_mod_visibility()
	_apply_play_state()

	var coll_btn := Button.new()
	coll_btn.text = "+ Sammlung"
	coll_btn.tooltip_text = "Map zu einer Sammlung hinzufuegen"
	coll_btn.custom_minimum_size = Vector2(0, 40)
	coll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coll_btn.add_theme_font_size_override("font_size", 14)
	UiTheme.style_ghost_button(coll_btn, 10)
	coll_btn.pressed.connect(_open_collection_popup)
	mods_row.add_child(coll_btn)

	_share_btn = Button.new()
	_share_btn.text = tr("An Freund schicken")
	_share_btn.tooltip_text = tr("Schickt die Map als Link in den Chat")
	_share_btn.custom_minimum_size = Vector2(0, 40)
	_share_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_share_btn.add_theme_font_size_override("font_size", 14)
	UiTheme.style_ghost_button(_share_btn, 10)
	_share_btn.pressed.connect(_share_selected_map)
	mods_row.add_child(_share_btn)

	# Marathon (scripts/marathon): mehrere Maps am Stueck, nur Mania.
	_marathon_btn = Button.new()
	_marathon_btn.text = tr("Marathon")
	_marathon_btn.tooltip_text = tr("Several maps in a row, one HP bar, one combo")
	_marathon_btn.custom_minimum_size = Vector2(0, 40)
	_marathon_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_marathon_btn.add_theme_font_size_override("font_size", 14)
	UiTheme.style_ghost_button(_marathon_btn, 10)
	_marathon_btn.pressed.connect(_open_marathon)
	_marathon_btn.visible = _play_mode == "mania"
	mods_row.add_child(_marathon_btn)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(1, 1, 1, 0.08)
	vb.add_child(sep)

	# BESTE SCORES: Top 5 dieser Diff (pp + Datum) + Replay-Zugriff.
	var lb_head := HBoxContainer.new()
	lb_head.add_theme_constant_override("separation", 8)
	lb_head.custom_minimum_size = Vector2(0, 28)
	vb.add_child(lb_head)
	var lb_title := Label.new()
	lb_title.text = "BESTE SCORES"
	lb_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lb_title.add_theme_font_size_override("font_size", 13)
	lb_title.add_theme_color_override("font_color", COL_DIM)
	lb_head.add_child(lb_title)
	_lb_title = lb_title
	# Modus-Tag: die Liste zeigt NUR Scores dieses Modus.
	var tag_box := PanelContainer.new()
	tag_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag_box.mouse_filter = Control.MOUSE_FILTER_PASS
	lb_head.add_child(tag_box)
	_lb_mode_tag = Label.new()
	_lb_mode_tag.add_theme_font_size_override("font_size", 11)
	tag_box.add_child(_lb_mode_tag)
	var lb_fill := Control.new()
	lb_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb_head.add_child(lb_fill)
	_lb_src_btns.clear()
	for src_i in 2:
		var sb := _make_toggle(tr("Lokal") if src_i == 0 else tr("Online"), 12, 8)
		sb.custom_minimum_size = Vector2(56, 26)
		sb.pressed.connect(_set_lb_online.bind(src_i == 1))
		lb_head.add_child(sb)
		_lb_src_btns.append(sb)
	_restyle_lb_src()
	_replay_btn = Button.new()
	_replay_btn.text = "Replay"
	_replay_btn.custom_minimum_size = Vector2(0, 28)
	_replay_btn.add_theme_font_size_override("font_size", 12)
	UiTheme.style_ghost_button(_replay_btn, 8)
	_replay_btn.visible = false
	_replay_btn.pressed.connect(_watch_replay)
	lb_head.add_child(_replay_btn)

	_lb_box = VBoxContainer.new()
	_lb_box.add_theme_constant_override("separation", 6)
	vb.add_child(_lb_box)


## Buehne in der Mitte: grosses Cover (abgerundet, Schatten), Vorschau-Linie,
## Spektrum der Vorschau-Musik. Passt sich der freien Breite an.
func _build_stage() -> void:
	_stage = Control.new()
	_stage.anchor_right = 1.0
	_stage.anchor_bottom = 1.0
	_stage.offset_left = M + INFO_W + M
	_stage.offset_right = -(M + RIGHT_W + M)
	_stage.offset_top = HEAD_Y + HEAD_H + M
	_stage.offset_bottom = -M
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	_stage_shadow = Panel.new()
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0.35)
	sh.set_corner_radius_all(8)
	sh.shadow_color = Color(0, 0, 0, 0.45)
	sh.shadow_size = 28
	sh.shadow_offset = Vector2(0, 10)
	_stage_shadow.add_theme_stylebox_override("panel", sh)
	_stage_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_stage_shadow)

	# Abgerundete Maske: Panel zeichnet nur Alpha, das Cover wird darauf geclippt.
	_stage_mask = Panel.new()
	var mk := StyleBoxFlat.new()
	mk.bg_color = Color.WHITE
	mk.set_corner_radius_all(8)
	mk.anti_aliasing = true
	_stage_mask.add_theme_stylebox_override("panel", mk)
	_stage_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_stage_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_stage_mask)
	_cover = TextureRect.new()
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_mask.add_child(_cover)
	# Feiner Glasrand ueber dem Cover.
	var rim := Panel.new()
	var rb := StyleBoxFlat.new()
	rb.bg_color = Color(0, 0, 0, 0)
	rb.set_corner_radius_all(8)
	rb.set_border_width_all(1)
	rb.border_color = Color(1, 1, 1, 0.14)
	rim.add_theme_stylebox_override("panel", rb)
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_mask.add_child(rim)

	# Vorschau-Fortschritt: duenne cyanfarbene Linie unter dem Cover.
	_progress_bg = Control.new()
	_progress_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_progress_bg)
	var track := ColorRect.new()
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.color = Color(1, 1, 1, 0.08)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bg.add_child(track)
	_progress_fill = ColorRect.new()
	_progress_fill.position = Vector2.ZERO
	_progress_fill.size = Vector2(0, 3)
	_progress_fill.color = COL_ACCENT
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bg.add_child(_progress_fill)

	# Spektrum der Vorschau-Musik (ruht bei Stille von selbst).
	_stage_viz = AudioVisualizer.new()
	_stage_viz.name = "VisualizerSlot"
	_stage_viz.bars = 48
	_stage_viz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_viz.modulate.a = 0.5
	_stage_viz.set_color(COL_ACCENT)
	_stage.add_child(_stage_viz)

	_stage.resized.connect(_layout_stage)
	_layout_stage.call_deferred()


func _layout_stage() -> void:
	var avail := _stage.size
	var w := minf(avail.x - 2.0 * M, 760.0)
	var viz_h := 64.0
	var gap := 18.0
	var h := w * 9.0 / 16.0
	var max_h := avail.y - (gap + 3.0 + gap + viz_h)
	if h > max_h:
		h = max_h
		w = h * 16.0 / 9.0
	var fits := w >= 240.0
	for c in _stage.get_children():
		(c as CanvasItem).visible = fits
	if not fits:
		return
	var total := h + gap + 3.0 + gap + viz_h
	# Optisch etwas ueber der Mitte: ruhiger Schwerpunkt.
	var top := maxf((avail.y - total) * 0.42, 0.0)
	var x := (avail.x - w) * 0.5
	_stage_shadow.position = Vector2(x, top)
	_stage_shadow.size = Vector2(w, h)
	_stage_mask.position = Vector2(x, top)
	_stage_mask.size = Vector2(w, h)
	_progress_bg.position = Vector2(x, top + h + gap)
	_progress_bg.size = Vector2(w, 3)
	_stage_viz.position = Vector2(x, top + h + gap + 3.0 + gap)
	_stage_viz.size = Vector2(w, viz_h)


func _info_chip(parent: Node) -> Label:
	var p := PanelContainer.new()
	var sb := _rounded_box(Color(1, 1, 1, 0.06), 8, Color(1, 1, 1, 0.10), 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", COL_TEXT)
	p.add_child(l)
	return l


func _build_list() -> void:
	# Maske mit Alpha-Verlauf: Karten blenden oben/unten weich aus statt hart
	# abzuschneiden (clip_children nutzt das Alpha der Maske).
	_list_grad = Gradient.new()
	_list_grad.offsets = PackedFloat32Array([0.0, 0.02, 0.98, 1.0])
	_list_grad.colors = PackedColorArray([
		Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = _list_grad
	gtex.width = 4
	gtex.height = 512
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	_list_mask = TextureRect.new()
	_list_mask.texture = gtex
	_list_mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_list_mask.stretch_mode = TextureRect.STRETCH_SCALE
	_list_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_list_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Karten-Kante = Toolbar-Kante: links Innenabstand + Hover-Slide, rechts
	# Scrollbalken im Aussenrand.
	_list_mask.anchor_left = 1.0
	_list_mask.anchor_right = 1.0
	_list_mask.anchor_bottom = 1.0
	_list_mask.offset_left = -M - RIGHT_W - LIST_PAD - CARD_SLIDE
	_list_mask.offset_right = -LIST_EDGE
	_list_mask.offset_top = LIST_TOP
	_list_mask.offset_bottom = -(M - LIST_PAD)
	_list_mask.resized.connect(_update_list_fade)
	add_child(_list_mask)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_mask.add_child(_scroll)

	# Innenabstand, damit Glow/Schatten und der Hover-Slide nach links nicht
	# vom Scroll-Clip abgeschnitten werden (vorher: oberste Karte gekappt).
	var sbw := int(_scroll.get_v_scroll_bar().get_combined_minimum_size().x)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_top", LIST_PAD)
	pad.add_theme_constant_override("margin_bottom", LIST_PAD)
	pad.add_theme_constant_override("margin_left", LIST_PAD + int(CARD_SLIDE))
	pad.add_theme_constant_override("margin_right", maxi(M - LIST_EDGE - sbw, 0))
	_scroll.add_child(pad)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	pad.add_child(_list_box)


## Fade-Laenge in Pixeln konstant halten (Gradient-Offsets nach Hoehe).
func _update_list_fade() -> void:
	var h := maxf(_list_mask.size.y, 1.0)
	var f := clampf(float(LIST_PAD) / h, 0.0, 0.45)
	_list_grad.offsets = PackedFloat32Array([0.0, f, 1.0 - f, 1.0])


# ---------------------------------------------------------------------------
# Collections
# ---------------------------------------------------------------------------

func _style_tabs() -> void:
	_apply_toggle(_tab_collections, _collection_mode)
	_apply_toggle(_tab_downloaded, not _collection_mode)


func _set_collection_mode(on: bool) -> void:
	_collection_mode = on
	_coll_undo = ""
	if on and not CollectionStore.list_for(_play_mode).has(_active_collection):
		var names := CollectionStore.list_for(_play_mode)
		_active_collection = names[0] if not names.is_empty() else ""
	_chips_row.visible = on
	_apply_career_layout()
	_style_tabs()
	_rebuild_chips()
	_refresh_filter(_search.text)


## Englische Texte der Sammlungs-Ansicht (Quelle Deutsch = Schluessel), ohne
## Eintrag in translations/.
static var _coll_tr_loaded := false
const COLL_EN := {
	"+ Neu": "+ New",
	"Neue Sammlung anlegen": "Create a new collection",
	"Neue Sammlung": "New collection",
	"Name der Sammlung": "Collection name",
	"Umbenennen": "Rename",
	"Löschen": "Delete",
	"Sammlung \"%s\" umbenennen": "Rename collection \"%s\"",
	"Sammlung \"%s\" löschen (lässt sich zurückholen)": "Delete collection \"%s\" (can be restored)",
	"\"%s\" gelöscht": "\"%s\" deleted",
	"Rückgängig": "Undo",
	"Papierkorb (%d)": "Trash (%d)",
	"Gelöschte Sammlungen": "Deleted collections",
	"Wiederherstellen": "Restore",
	"Noch keine Sammlung.": "No collections yet.",
	"Diesen Namen gibt es schon.": "That name already exists.",
	"Anlegen": "Create",
	"Speichern": "Save",
	"Abbrechen": "Cancel",
	"Schließen": "Close",
	"Alle Maps zeigen": "Show all maps",
	"  ·  %d in anderem Modus": "  ·  %d in another mode",
	"alle Modi": "all modes",
	"Alle Modi": "All modes",
	"Gilt für": "Used in",
	"Nur %s": "%s only",
	"Bearbeiten": "Edit",
	"Sammlung \"%s\" bearbeiten": "Edit collection \"%s\"",
	"Name oder Modus von \"%s\" ändern": "Change name or mode of \"%s\"",
	"Nicht in %s spielbar": "Not playable in %s",
	"Nur osu!standard-Diffs. Spielbar in %s.": "osu!standard difficulties only. Playable in %s.",
	"Diese Map hat keine Diff für %s. Sie bleibt in der Sammlung.":
		"This map has no difficulty for %s. It stays in the collection.",
	"Noch keine Sammlung für %s.": "No collection for %s yet.",
	"Noch keine Sammlung für %s. Lege oben mit \"+ Neu\" eine an oder nutze \"+ Sammlung\" im Info-Panel.":
		"No collection for %s yet. Create one with \"+ New\" above, or use \"+ Collection\" in the info panel.",
	"\"%s\" in Sammlungen": "\"%s\" in collections",
	"Neue Sammlung…": "New collection…",
	"Noch keine Sammlung. Lege oben mit \"+ Neu\" eine an oder nutze \"+ Sammlung\" im Info-Panel.":
		"No collections yet. Create one with \"+ New\" above, or use \"+ Collection\" in the info panel.",
	"\"%s\" ist noch leer. Unter \"Heruntergeladen\" eine Map wählen, dann \"+ Sammlung\" im Info-Panel.":
		"\"%s\" is empty. Pick a map under \"Downloaded\", then use \"+ Collection\" in the info panel.",
	"Die Maps in \"%s\" sind in diesem Modus nicht spielbar.":
		"The maps in \"%s\" cannot be played in this mode.",
	"Kein Treffer für die Suche in \"%s\".": "No search match in \"%s\".",
	"Die Maps in \"%s\" liegen nicht mehr im maps-Ordner.":
		"The maps in \"%s\" are no longer in the maps folder.",
}


static func _coll_translations() -> void:
	if _coll_tr_loaded:
		return
	_coll_tr_loaded = true
	var t := Translation.new()
	t.locale = "en"
	for k in COLL_EN:
		t.add_message(k, COLL_EN[k])
	TranslationServer.add_translation(t)


## Sammlungs-Ansicht: was von den Eintraegen einer Sammlung zu sehen ist.
## files = .osz-Namen der Sammlung, vm = Sicht-Modus (MapSet.mode_shows),
## q = Suchtext (klein, "" = keine Suche). Sterne-, Bestwert-, Noten- und
## SV-Filter zaehlen hier bewusst nicht. Getestet in tests/run_collection_tests.gd.
static func collection_view(mapsets: Array, files: Array, vm: String, q: String) -> Dictionary:
	var want := {}
	for f in files:
		want[str(f)] = true
	var found := {}
	var shown: Array = []
	var unplayable: Array = []
	var other_mode := 0
	var search_hidden := 0
	for ms in mapsets:
		var f: String = ms.osz_path.get_file()
		if not want.has(f):
			continue
		found[f] = true
		if ms.visible_diffs(vm).is_empty():
			# Ohne Diff fuer den Modus: nicht versteckt, sondern markiert gezeigt.
			other_mode += 1
			if q == "" or ms.search_haystack().contains(q):
				unplayable.append(ms)
		elif q != "" and not ms.search_haystack().contains(q):
			search_hidden += 1
		else:
			shown.append(ms)
	return {"shown": shown, "unplayable": unplayable, "other_mode": other_mode,
		"search_hidden": search_hidden, "missing": want.size() - found.size()}


## Kleiner Modus-Hinweis einer Sammlung: Modus-Name bzw. "alle Modi".
static func collection_mode_hint(mode: String) -> String:
	_coll_translations()
	var m := CollectionStore.normalize_mode(mode)
	if m == CollectionStore.MODE_ALL:
		return TranslationServer.translate("alle Modi")
	return ScoreStore.mode_label("" if m == "mania" else m)


## Modi, in denen das Set mindestens eine Diff hat.
static func playable_modes(ms: MapSet) -> Array:
	var out: Array = []
	for m in PLAY_MODES:
		if not ms.visible_diffs("mania" if ScoreStore.is_mania_like(m) else "orbit").is_empty():
			out.append(m)
	return out


## Grund fuer eine leere Sammlungs-Liste: "none" (keine Sammlung), "empty",
## "search", "other_mode", "missing"; "" = es gibt Maps zu zeigen.
static func collection_empty_reason(active: String, view: Dictionary) -> String:
	if active == "":
		return "none"
	if not (view.get("shown", []) as Array).is_empty():
		return ""
	if int(view.get("search_hidden", 0)) > 0:
		return "search"
	if int(view.get("other_mode", 0)) > 0:
		return "other_mode"
	if int(view.get("missing", 0)) > 0:
		return "missing"
	return "empty"


func _collection_empty_text() -> String:
	var files := CollectionStore.maps_in(_active_collection) if _active_collection != "" else []
	var view := collection_view(_library.mapsets, files, _vm(), _search.text.strip_edges().to_lower())
	match collection_empty_reason(_active_collection, view):
		"none":
			if not CollectionStore.list_names().is_empty():
				return tr("Noch keine Sammlung für %s. Lege oben mit \"+ Neu\" eine an oder nutze \"+ Sammlung\" im Info-Panel.") \
						% collection_mode_hint(_play_mode)
			return tr("Noch keine Sammlung. Lege oben mit \"+ Neu\" eine an oder nutze \"+ Sammlung\" im Info-Panel.")
		"search":
			return tr("Kein Treffer für die Suche in \"%s\".") % _active_collection
		"other_mode":
			return tr("Die Maps in \"%s\" sind in diesem Modus nicht spielbar.") % _active_collection
		"missing":
			return tr("Die Maps in \"%s\" liegen nicht mehr im maps-Ordner.") % _active_collection
	return tr("\"%s\" ist noch leer. Unter \"Heruntergeladen\" eine Map wählen, dann \"+ Sammlung\" im Info-Panel.") % _active_collection


func _coll_action(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, CHIPS_H)
	b.add_theme_font_size_override("font_size", 13)
	UiTheme.style_ghost_button(b, 15)
	b.pressed.connect(on_press)
	_chips_row.add_child(b)
	return b


func _coll_changed() -> void:
	_rebuild_chips()
	_refresh_filter(_search.text)


func _rebuild_chips() -> void:
	for c in _chips_row.get_children():
		_chips_row.remove_child(c)
		c.queue_free()
	if not _collection_mode:
		return
	# Nur Sammlungen des aktuellen Modus und "alle Modi".
	var names := CollectionStore.list_for(_play_mode)
	if not names.has(_active_collection):
		_active_collection = names[0] if not names.is_empty() and _coll_undo == "" else ""
	if _coll_undo != "":
		# Gerade geloescht: sofort zurueckholbar.
		var gone := Label.new()
		gone.text = tr("\"%s\" gelöscht") % _coll_undo
		gone.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		gone.add_theme_font_size_override("font_size", 13)
		gone.add_theme_color_override("font_color", COL_DIM)
		_chips_row.add_child(gone)
		var undo_name := _coll_undo
		var ub := _coll_action(tr("Rückgängig"), "", func():
			CollectionStore.restore(undo_name)
			_coll_undo = ""
			_active_collection = undo_name
			_coll_changed())
		ub.add_theme_color_override("font_color", COL_ACCENT)
	elif names.is_empty():
		var hint := Label.new()
		hint.text = tr("Noch keine Sammlung.") if CollectionStore.list_names().is_empty() \
				else tr("Noch keine Sammlung für %s.") % collection_mode_hint(_play_mode)
		hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", COL_DIM)
		_chips_row.add_child(hint)
	var have := {}
	for ms in _library.mapsets:
		have[ms.osz_path.get_file()] = true
	for name in names:
		var present := 0
		for f in CollectionStore.maps_in(name):
			if have.has(f):
				present += 1
		var chip := _make_toggle("%s (%d)" % [name, present], 13, 15)
		chip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		chip.custom_minimum_size = Vector2(0, CHIPS_H)
		_apply_toggle(chip, name == _active_collection)
		chip.pressed.connect(func():
			_active_collection = name
			_coll_undo = ""
			_coll_changed())
		_chips_row.add_child(chip)
		_coll_chip_hint(chip, CollectionStore.mode_of(name), name == _active_collection)
	_coll_action(tr("+ Neu"), tr("Neue Sammlung anlegen"), func():
		_collection_name_dialog(tr("Neue Sammlung"), "", tr("Anlegen"), func(n: String, mode: String) -> bool:
			if not CollectionStore.create(n, mode):
				return false
			_active_collection = n.strip_edges()
			_coll_undo = ""
			_coll_changed()
			return true, _play_mode))
	if _active_collection != "":
		var act := _active_collection
		_coll_action(tr("Bearbeiten"), tr("Name oder Modus von \"%s\" ändern") % act, func():
			_collection_name_dialog(tr("Sammlung \"%s\" bearbeiten") % act, act, tr("Speichern"), func(n: String, mode: String) -> bool:
				var nn := n.strip_edges()
				if nn != act and not CollectionStore.rename(act, nn):
					return false
				CollectionStore.set_mode(nn, mode)
				_active_collection = nn
				_coll_changed()
				return true, CollectionStore.mode_of(act)))
		_coll_action(tr("Löschen"), tr("Sammlung \"%s\" löschen (lässt sich zurückholen)") % act, func():
			CollectionStore.delete(act)
			_coll_undo = act
			_active_collection = ""
			_coll_changed())
	var trash := CollectionStore.deleted_names()
	if _coll_undo == "" and not trash.is_empty():
		_coll_action(tr("Papierkorb (%d)") % trash.size(), tr("Gelöschte Sammlungen"), _open_collection_trash)


## Kleines Overlay mit Titel; liefert [overlay, VBox fuer den Inhalt].
func _coll_overlay(title_text: String) -> Array:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", _rounded_box(Color(0.07, 0.07, 0.11, 0.98), 14))
	center.add_child(panel)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(pad)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pad.add_child(vb)
	var title := Label.new()
	title.text = title_text
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)
	return [overlay, vb]


## Kleiner Modus-Hinweis rechts im Sammlungs-Chip (Chip haengt schon im Baum).
func _coll_chip_hint(chip: Button, mode: String, active: bool) -> void:
	var hl := Label.new()
	hl.text = collection_mode_hint(mode)
	hl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hl.add_theme_font_size_override("font_size", 11)
	var own := CollectionStore.normalize_mode(mode) != CollectionStore.MODE_ALL
	var col := UiTheme.ACCENT2 if own else COL_DIM
	hl.add_theme_color_override("font_color", Color(col, 0.95 if active or own else 0.75))
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(hl)
	var text_w := chip.get_minimum_size().x
	var hint_w := hl.get_minimum_size().x
	chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip.custom_minimum_size = Vector2(text_w + hint_w + 6.0, CHIPS_H)
	hl.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	hl.offset_left = -(hint_w + 13.0)
	hl.offset_right = -13.0
	hl.offset_top = 1.0


## Name und Modus eingeben (Neu / Bearbeiten). on_ok(name, modus) -> bool:
## false = Name abgelehnt. mode0 = vorgewaehlter Modus ("" = alle Modi).
func _collection_name_dialog(title_text: String, initial: String, ok_text: String, on_ok: Callable,
		mode0: String = "") -> void:
	var ov := _coll_overlay(title_text)
	var overlay: Control = ov[0]
	var vb: VBoxContainer = ov[1]
	var edit := LineEdit.new()
	edit.text = initial
	edit.placeholder_text = tr("Name der Sammlung")
	edit.max_length = 40
	edit.custom_minimum_size = Vector2(0, 40)
	vb.add_child(edit)
	# Modus der Sammlung: "Alle Modi" oder genau einer.
	var cap := Label.new()
	cap.text = tr("Gilt für")
	cap.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", COL_DIM)
	vb.add_child(cap)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	vb.add_child(flow)
	var picked := [CollectionStore.normalize_mode(mode0)]
	var pick_btns: Array = []
	var options: Array = [CollectionStore.MODE_ALL]
	options.append_array(PLAY_MODES)
	for opt in options:
		var mb := _make_toggle(tr("Alle Modi") if opt == "" else collection_mode_hint(opt), 13, 13)
		mb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		mb.custom_minimum_size = Vector2(0, 30)
		_apply_toggle(mb, opt == picked[0])
		var o: String = opt
		mb.pressed.connect(func():
			picked[0] = o
			for j in pick_btns.size():
				_apply_toggle(pick_btns[j], options[j] == o))
		flow.add_child(mb)
		pick_btns.append(mb)
	var err := Label.new()
	err.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	err.add_theme_font_size_override("font_size", 13)
	err.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	err.visible = false
	vb.add_child(err)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var cancel := Button.new()
	cancel.text = tr("Abbrechen")
	cancel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cancel.custom_minimum_size = Vector2(110, 40)
	cancel.pressed.connect(overlay.queue_free)
	row.add_child(cancel)
	var ok := Button.new()
	ok.text = ok_text
	ok.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ok.custom_minimum_size = Vector2(110, 40)
	row.add_child(ok)
	var submit := func():
		if edit.text.strip_edges() == "":
			return
		if on_ok.call(edit.text, str(picked[0])):
			overlay.queue_free()
		else:
			err.text = tr("Diesen Namen gibt es schon.")
			err.visible = true
	ok.pressed.connect(submit)
	edit.text_submitted.connect(func(_t): submit.call())
	edit.grab_focus.call_deferred()
	edit.select_all.call_deferred()


## Papierkorb: geloeschte Sammlungen zurueckholen.
func _open_collection_trash() -> void:
	var ov := _coll_overlay(tr("Gelöschte Sammlungen"))
	var overlay: Control = ov[0]
	var vb: VBoxContainer = ov[1]
	for name in CollectionStore.deleted_names():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vb.add_child(row)
		var lbl := Label.new()
		lbl.text = str(name)
		lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		row.add_child(lbl)
		var rb := Button.new()
		rb.text = tr("Wiederherstellen")
		rb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		rb.pressed.connect(func():
			CollectionStore.restore(str(name))
			_active_collection = str(name)
			overlay.queue_free()
			_coll_changed())
		row.add_child(rb)
	var close := Button.new()
	close.text = tr("Schließen")
	close.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(overlay.queue_free)
	vb.add_child(close)


## Overlay: gewaehlte Map in Sammlungen packen / entfernen / neue anlegen.
func _open_collection_popup() -> void:
	if _selected_set == null:
		return
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", _rounded_box(Color(0.07, 0.07, 0.11, 0.98), 14))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = tr("\"%s\" in Sammlungen") % _selected_set.title
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)

	var boxes := VBoxContainer.new()
	vb.add_child(boxes)
	var fill_boxes := func():
		for c in boxes.get_children():
			c.queue_free()
		for name in CollectionStore.list_for(_play_mode):
			var cb := CheckBox.new()
			cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			cb.text = "%s  ·  %s" % [name, collection_mode_hint(CollectionStore.mode_of(name))]
			cb.button_pressed = CollectionStore.contains(name, _selected_set.osz_path)
			cb.toggled.connect(func(_on):
				CollectionStore.toggle(name, _selected_set.osz_path)
				_rebuild_chips())
			boxes.add_child(cb)
	fill_boxes.call()

	var new_row := HBoxContainer.new()
	new_row.add_theme_constant_override("separation", 8)
	vb.add_child(new_row)
	var new_edit := LineEdit.new()
	new_edit.placeholder_text = "%s  ·  %s" % [tr("Neue Sammlung…"), tr("Nur %s") % collection_mode_hint(_play_mode)]
	new_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_child(new_edit)
	var new_btn := Button.new()
	new_btn.text = tr("Anlegen")
	var add_new := func():
		if CollectionStore.create(new_edit.text, _play_mode):
			CollectionStore.toggle(new_edit.text.strip_edges(), _selected_set.osz_path)
			new_edit.text = ""
			fill_boxes.call()
			_rebuild_chips()
	new_btn.pressed.connect(add_new)
	new_edit.text_submitted.connect(func(_t): add_new.call())
	new_row.add_child(new_btn)

	var close := Button.new()
	close.text = tr("Schließen")
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(func():
		overlay.queue_free()
		_rebuild_chips()
		_refresh_filter(_search.text))
	vb.add_child(close)


# ---------------------------------------------------------------------------
# Liste / Karten
# ---------------------------------------------------------------------------

func _restyle_star_chips() -> void:
	for i in _star_chips.size():
		_apply_toggle(_star_chips[i], i == _star_filter)
	if _sv_chip != null:
		_apply_toggle(_sv_chip, _sv_filter)


## Filter des aktiven Modus (Sortierung, Bestwert, Noten); legt fehlende an.
func _mode_filter() -> Dictionary:
	if not _mode_filters.has(_play_mode):
		_mode_filters[_play_mode] = default_mode_filter()
	return _mode_filters[_play_mode]


func _sort_mode() -> int:
	return int(_mode_filter()["sort"])


## Sortier-Auswahl und Bestwert-Chips auf den aktiven Modus setzen.
func _restyle_score_chips() -> void:
	var mf := _mode_filter()
	for i in _best_chips.size():
		_apply_toggle(_best_chips[i], i + BEST_WITH == int(mf["best"]))
	for g in _grade_chips:
		_apply_toggle(_grade_chips[g], (mf["grades"] as Array).has(g))
	if _sort_btn != null and _sort_btn.selected != int(mf["sort"]):
		_sort_btn.select(int(mf["sort"]))


## Gespeicherte Browser-Filter laden (nicht in Test-/Shot-Laeufen: die brauchen den Standard).
func _load_browser_state() -> bool:
	var force := OS.get_cmdline_args().has("--browser-state")  # Harness: Wiederherstellung pruefen
	if not force and (Settings.is_test_run() or DisplayServer.get_name() == "headless"):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(BROWSER_STATE_PATH) == OK:
		_star_filter = clampi(int(cfg.get_value("browser", "star_filter", 0)), 0, STAR_FILTERS.size() - 1)
		_sv_filter = bool(cfg.get_value("browser", "sv_filter", false))
		var old_sort := clampi(int(cfg.get_value("browser", "sort_mode", 0)), 0, SORT_NAMES.size() - 1)
		var mfs = cfg.get_value("browser", "mode_filters", {})
		for m in PLAY_MODES:
			var raw = mfs.get(m, {}) if mfs is Dictionary else {}
			var mf := sanitize_mode_filter(raw if raw is Dictionary else {})
			if not (raw is Dictionary and raw.has("sort")):
				mf["sort"] = old_sort  # alter Stand ohne Modus-Trennung
			_mode_filters[m] = mf
		_saved_search = str(cfg.get_value("browser", "search", ""))
		var coll := str(cfg.get_value("browser", "collection", ""))
		_active_collection = coll if CollectionStore.list_names().has(coll) else ""
		_collection_mode = bool(cfg.get_value("browser", "collection_mode", false))
		var pm := str(cfg.get_value("browser", "play_mode", "mania"))
		_play_mode = pm if PLAY_MODES.has(pm) else "mania"
		SvMod.strength = SvMod.level_from_name(str(cfg.get_value("browser", "sv_level", "strong")))
		_rec = rec_sanitize(cfg.get_value("browser", "recs", {}))
		var om = cfg.get_value("browser", "orbit_mods", {})
		if om is Dictionary:
			for k in OrbitCore.ORBIT_MODS:
				_orbit_mods[k] = bool(om.get(k, false))
		var tmd = cfg.get_value("browser", "trace_mods", {})
		if tmd is Dictionary:
			for k in TraceMods.MODS:
				_trace_mods[k] = bool(tmd.get(k, false))
		var rmd = cfg.get_value("browser", "rule_mods", {})
		if rmd is Dictionary:
			for k in RuleMods.KEYS:
				_rule_mods[k] = bool(rmd.get(k, false))
	return true


func _save_browser_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("browser", "star_filter", _star_filter)
	cfg.set_value("browser", "sv_filter", _sv_filter)
	cfg.set_value("browser", "sort_mode", _sort_mode())
	var mfs := {}
	for m in PLAY_MODES:
		mfs[m] = sanitize_mode_filter(_mode_filters.get(m, {}))
	cfg.set_value("browser", "mode_filters", mfs)
	cfg.set_value("browser", "search", _search.text if _search != null else "")
	cfg.set_value("browser", "collection", _active_collection)
	cfg.set_value("browser", "collection_mode", _collection_mode)
	cfg.set_value("browser", "play_mode", _play_mode)
	cfg.set_value("browser", "sv_level", SvMod.level_name())
	cfg.set_value("browser", "orbit_mods", _orbit_mods.duplicate())
	cfg.set_value("browser", "trace_mods", _trace_mods.duplicate())
	cfg.set_value("browser", "rule_mods", _rule_mods.duplicate())
	cfg.set_value("browser", "recs", rec_sanitize(_rec))
	cfg.save(BROWSER_STATE_PATH)


func _refresh_filter(query: String) -> void:
	if _state_ready:
		_save_browser_state()
	var q := query.strip_edges().to_lower()
	var lo: float = STAR_FILTERS[_star_filter][1]
	var hi: float = STAR_FILTERS[_star_filter][2]
	var mf := _mode_filter()
	var best_f := int(mf["best"])
	var grades: Array = mf["grades"]
	var sort_m := int(mf["sort"])
	# Sammlungs-Ansicht zeigt IMMER alle ihre Maps: Sterne-, Bestwert-, Noten- und
	# SV-Filter gelten dort nicht (ihre Chips sind dann ausgeblendet).
	var coll := _collection_mode
	var star_f := _star_filter != 0 and not coll
	var by_best := (best_f != BEST_ALL or not grades.is_empty()) and not coll
	var need_scores := by_best or sort_m == SORT_RECENT or sort_m == SORT_MOST_PLAYED
	var idx: Dictionary = _scores_for_mode() if need_scores else {}
	var rows: Array = []
	_filtered.clear()
	_coll_unplayable.clear()
	var coll_files := {}
	if coll and _active_collection != "":
		for f in CollectionStore.maps_in(_active_collection):
			coll_files[str(f)] = true
	for ms in _library.mapsets:
		if q != "" and not ms.search_haystack().contains(q):
			continue
		if _collection_mode:
			if not coll_files.has(ms.osz_path.get_file()):
				continue
		if _sv_filter and not coll and not ms.has_sv():
			continue
		# Modus-Filter: osu!standard-Diffs nur im Orbit-Modus (MapSet.mode_shows).
		var vis := ms.visible_diffs(_vm())
		if vis.is_empty():
			if coll:
				_coll_unplayable.append(ms)  # bleibt sichtbar, als nicht spielbar markiert
			continue
		# Sterne des aktiven Modus (fehlende vorlaeufig Mania-Sterne).
		var smap := _mode_star_map(ms) if star_f \
				or sort_m == SORT_STARS_UP or sort_m == SORT_STARS_DOWN else {}
		# Sterne-Filter: Set passt, wenn IRGENDEINE sichtbare Diff im Bereich liegt.
		if star_f:
			var in_range := false
			for i in vis:
				var st := ms.star_or_base(i, smap)
				if st >= lo and st < hi:
					in_range = true
					break
			if not in_range:
				continue
		var row := {"ms": ms, "i": rows.size()}
		if need_scores:
			# Bestwert/Plays nur der im Modus sichtbaren Diffs (wie das Rang-Badge).
			var info: Dictionary = idx.get(ms.osz_path.get_file(), {})
			var versions: Array = []
			for i in vis:
				versions.append(ms.version_name_at(i))
			if by_best and not passes_best_filter(set_best_grade(info, versions), best_f, grades):
				continue
			row["last"] = set_last_played(info, versions)
			row["plays"] = set_plays(info, versions)
		if sort_m == SORT_STARS_UP or sort_m == SORT_STARS_DOWN:
			row["stars"] = ms.max_visible_stars(_vm(), smap)
		elif sort_m == SORT_DOWNLOADED:
			if not _mtime_cache.has(ms.osz_path):
				_mtime_cache[ms.osz_path] = FileAccess.get_modified_time(ms.osz_path)
			row["mtime"] = _mtime_cache[ms.osz_path]
		rows.append(row)
	sort_rows(rows, sort_m)
	for r in rows:
		_filtered.append(r["ms"])
	_rebuild_cards()
	var count_txt := tr("%d Maps") % _filtered.size()
	if _collection_mode and _active_collection != "":
		# Was fehlt, klar ausweisen: anderer Modus bzw. .osz nicht mehr im maps-Ordner.
		var view := collection_view(_library.mapsets, CollectionStore.maps_in(_active_collection), _vm(), "")
		if int(view.other_mode) > 0:
			count_txt += tr("  ·  %d in anderem Modus") % int(view.other_mode)
		if int(view.missing) > 0:
			count_txt += tr("  ·  %d fehlen (gelöscht?)") % int(view.missing)
	_count_label.text = count_txt


## Score-Index des aktiven Modus: scores.cfg einmal lesen, danach aus dem Cache.
func _scores_for_mode() -> Dictionary:
	if not _score_index.has(_play_mode):
		var cfg := ConfigFile.new()
		var mode := _pm()
		_score_index[_play_mode] = build_score_index(cfg, mode) 			if cfg.load(ScoreStore.PATH) == OK else {}
	return _score_index[_play_mode]


# ---------------------------------------------------------------------------
# Filterlogik (statisch, ohne UI; getestet in tests/run_browser_filter_tests.gd)
# ---------------------------------------------------------------------------

static func default_mode_filter() -> Dictionary:
	return {"sort": SORT_TITLE, "best": BEST_ALL, "grades": []}


## Gespeicherten Modus-Filter pruefen: Werte begrenzen, unbekannte Noten weg.
static func sanitize_mode_filter(d: Dictionary) -> Dictionary:
	var out := default_mode_filter()
	out["sort"] = clampi(int(d.get("sort", SORT_TITLE)), 0, SORT_NAMES.size() - 1)
	out["best"] = clampi(int(d.get("best", BEST_ALL)), 0, BEST_NAMES.size() - 1)
	var gs: Array = []
	var raw = d.get("grades", [])
	if raw is Array:
		for g in raw:
			if GRADE_CHIPS.has(str(g)) and not gs.has(str(g)):
				gs.append(str(g))
	if not gs.is_empty():
		out["best"] = BEST_WITH  # Noten gibt es nur mit Bestwert
	out["grades"] = gs
	return out


## Index aus scores.cfg fuer einen Modus ("" = Mania, "orbit"; Sektionen per
## ScoreStore._sec): {osz-Datei: {Version: {"grade", "last", "plays"}}}.
## "last" = juengstes Datum aus History/Recent (ISO, also als Text vergleichbar).
static func build_score_index(cfg: ConfigFile, mode: String) -> Dictionary:
	var idx := {}
	var at := func(key: String) -> Dictionary:
		var parts := key.split("|", true, 1)
		var f := parts[0].get_file()
		var v := parts[1] if parts.size() > 1 else ""
		if not idx.has(f):
			idx[f] = {}
		if not idx[f].has(v):
			idx[f][v] = {"grade": "", "last": "", "plays": 0}
		return idx[f][v]
	var sec := ScoreStore._sec("scores", mode)
	if cfg.has_section(sec):
		for key in cfg.get_section_keys(sec):
			var b = cfg.get_value(sec, key, {})
			if b is Dictionary and not b.is_empty():
				var e: Dictionary = at.call(key)
				e["grade"] = str(b.get("grade", ""))
				e["last"] = maxs(e["last"], str(b.get("date", "")))
	sec = ScoreStore._sec("plays", mode)
	if cfg.has_section(sec):
		for key in cfg.get_section_keys(sec):
			at.call(key)["plays"] = int(cfg.get_value(sec, key, 0))
	sec = ScoreStore._sec("history", mode)
	if cfg.has_section(sec):
		for key in cfg.get_section_keys(sec):
			var hist = cfg.get_value(sec, key, [])
			if hist is Array:
				var e: Dictionary = at.call(key)
				for h in hist:
					if h is Dictionary:
						e["last"] = maxs(e["last"], str(h.get("date", "")))
	var recent = cfg.get_value(ScoreStore._sec("recent", mode), "plays", [])
	if recent is Array:
		for r in recent:
			if r is Dictionary and str(r.get("osz_file", "")) != "":
				var e: Dictionary = at.call("%s|%s" % [r.get("osz_file", ""), r.get("version", "")])
				e["last"] = maxs(e["last"], str(r.get("date", "")))
	return idx


static func maxs(a: String, b: String) -> String:
	return b if b > a else a


## Note auf einen Chip abbilden: "SS"/"SSH"/"X" -> SS, "SH" -> S, D und F -> D.
static func grade_bucket(grade: String) -> String:
	var g := grade.strip_edges().to_upper()
	if g == "":
		return ""
	if g.begins_with("SS") or g.begins_with("X"):
		return "SS"
	var c := g.left(1)
	if c == "F":
		return "D"
	return c if GRADE_CHIPS.has(c) else ""


## Beste Note (als Chip) ueber die gegebenen Versionen eines Sets, "" = kein Bestwert.
static func set_best_grade(info: Dictionary, versions: Array) -> String:
	var best := ""
	for v in versions:
		var g := grade_bucket(str(info.get(v, {}).get("grade", "")))
		if g != "" and (best == "" or GRADE_CHIPS.find(g) < GRADE_CHIPS.find(best)):
			best = g
	return best


static func set_last_played(info: Dictionary, versions: Array) -> String:
	var last := ""
	for v in versions:
		last = maxs(last, str(info.get(v, {}).get("last", "")))
	return last


static func set_plays(info: Dictionary, versions: Array) -> int:
	var n := 0
	for v in versions:
		n += int(info.get(v, {}).get("plays", 0))
	return n


## grade = set_best_grade(); grades leer = jede Note.
static func passes_best_filter(grade: String, best_f: int, grades: Array) -> bool:
	if best_f == BEST_WITHOUT:
		return grade == ""
	if grade == "" and (best_f == BEST_WITH or not grades.is_empty()):
		return false
	return grades.is_empty() or grades.has(grade)


## Zeilen {"i": Bibliotheks-Reihenfolge, "stars", "last", "plays", "mtime"}
## sortieren. Gleichstand und fehlende Werte: Bibliotheks-Reihenfolge (Titel).
static func sort_rows(rows: Array, sort_m: int) -> void:
	match sort_m:
		SORT_STARS_UP:
			rows.sort_custom(func(a, b): return _cmp(a, b, -float(a.get("stars", 0.0)), -float(b.get("stars", 0.0))))
		SORT_STARS_DOWN:
			rows.sort_custom(func(a, b): return _cmp(a, b, float(a.get("stars", 0.0)), float(b.get("stars", 0.0))))
		SORT_RECENT:
			rows.sort_custom(func(a, b): return _cmp(a, b, str(a.get("last", "")), str(b.get("last", ""))))
		SORT_DOWNLOADED:
			rows.sort_custom(func(a, b): return _cmp(a, b, int(a.get("mtime", 0)), int(b.get("mtime", 0))))
		SORT_MOST_PLAYED:
			rows.sort_custom(func(a, b): return _cmp(a, b, int(a.get("plays", 0)), int(b.get("plays", 0))))


## Groesserer Wert zuerst, bei Gleichstand kleinerer Index.
static func _cmp(a: Dictionary, b: Dictionary, va: Variant, vb: Variant) -> bool:
	if va != vb:
		return va > vb
	return int(a["i"]) < int(b["i"])


func _process(delta: float) -> void:
	_beat_react(delta)
	_loudness_step()
	_prepare_step()
	_game_preload_step()
	# Thumbnails haeppchenweise laden (Zeitbudget pro Frame) — Browser bleibt fluessig.
	var t_end := Time.get_ticks_usec() + THUMB_BUDGET_USEC
	var budget := 2
	while (budget > 0 or Time.get_ticks_usec() < t_end) and not _thumb_queue.is_empty():
		var job: Dictionary = _thumb_queue.pop_front()
		var bg_rect: TextureRect = job.bg
		if not is_instance_valid(bg_rect):
			continue
		var tex: Texture2D = (job.ms as MapSet).thumb_texture()
		if tex != null:
			bg_rect.texture = tex
		budget -= 1
		if _thumb_queue.is_empty() and _perf_ready_t > 0:
			GameSession.perf_since("Browser: alle Thumbnails sichtbar (seit _ready)", _perf_ready_t)
			_perf_ready_t = 0


## Lautheitsmessung der Vorschau; nach >= 6 s Gain speichern und anwenden.
func _loudness_step() -> void:
	if not SongLoudness.is_measuring() or _preview == null or not _preview.playing:
		return
	SongLoudness.poll(_preview.volume_db)
	if SongLoudness.measured_sec() < SongLoudness.MIN_MEASURE_SEC:
		return
	var g := SongLoudness.measure_stop()
	if not is_nan(g):
		_preview_gain_db = g
		_preview_fade = create_tween()
		_preview_fade.tween_property(_preview, "volume_db", PREVIEW_DB + g, 0.5)


## Auswahl-Karte, Hintergrund und SPIELEN pulsen exakt auf dem Beat der
## Vorschau (BeatClock aus den Timing-Points, keine Spektrum-Verzoegerung).
## Keine Allokation: nur Skalare, Scale/Modulate bestehender Nodes.
func _beat_react(delta: float) -> void:
	var p := 0.0
	var t := _preview_ms()
	if t >= 0.0:
		_beat.update(t, delta)
		# Huellkurve aus der Beat-Phase (Downbeat voll, Zwischenschlaege leiser).
		p = _beat.beat_env
	if _bg != null:
		_bg.pivot_offset = _bg.size * 0.5
		var s := 1.0  # steht still, nur die Helligkeit atmet leicht
		_bg.scale = Vector2(s, s)
		var b := 0.30 + 0.03 * p
		_bg.modulate = Color(b, b * 0.97, b * 0.93)
	var idx := _filtered.find(_selected_set)
	var card: Button = null
	if idx >= 0 and idx < _card_buttons.size() and is_instance_valid(_card_buttons[idx]):
		card = _card_buttons[idx]
	if card != _pulse_card:
		if _pulse_card != null and is_instance_valid(_pulse_card):
			_pulse_card.modulate = Color.WHITE
			var old_bg := _pulse_card.get_child(0) as TextureRect
			if old_bg != null:
				old_bg.self_modulate = Color.WHITE
		_pulse_card = card
	if card != null:
		var c := 1.0 + 0.04 * p
		card.modulate = Color(c, c, c)
		var cbg := card.get_child(0) as TextureRect
		if cbg != null:
			var g := 1.0 + 0.25 * p
			cbg.self_modulate = Color(g, g, g)
	# Glow der Auswahl atmet mit dem Beat (nur Skalar auf bestehender StyleBox).
	if _sel_box != null:
		var gs := 10 + int(round(6.0 * p))
		if _sel_box.shadow_size != gs:
			_sel_box.shadow_size = gs
	# SPIELEN: dezenter Beat-Puls (nur Helligkeit, kein Wackeln).
	if _play_btn != null:
		var pb := 1.0 + 0.08 * p
		_play_btn.self_modulate = Color(pb, pb, pb)
	# Vorschau-Fortschritt (Position im Song).
	if _progress_fill != null:
		var frac := 0.0
		if _preview != null and _preview.playing and _preview_len > 0.0:
			frac = clampf(_preview.get_playback_position() / _preview_len, 0.0, 1.0)
		var w := _progress_bg.size.x * frac
		if not is_equal_approx(_progress_fill.size.x, w):
			_progress_fill.size = Vector2(w, _progress_bg.size.y)


func _begin_game_preload() -> void:
	if not is_inside_tree():
		return
	var paths: Array[String] = []
	paths.append_array(GAME_SCENES)
	for d in GAME_ASSET_DIRS:
		for f in ResourceLoader.list_directory(d):
			var ext := f.get_extension().to_lower()
			if ext in ["obj", "webp", "png", "jpg", "glb", "tres", "res"]:
				paths.append(d.path_join(f))
	for p in paths:
		if _game_res.has(p) or _game_req.has(p) or not ResourceLoader.exists(p):
			continue
		if ResourceLoader.load_threaded_request(p, "", true) == OK:
			_game_req.append(p)
	_game_preload_t = Time.get_ticks_usec()


func _game_preload_step() -> void:
	if _game_req.is_empty():
		return
	for p in _game_req.duplicate():
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_game_res[p] = ResourceLoader.load_threaded_get(p)
			_game_req.erase(p)
		elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_game_req.erase(p)
	if _game_req.is_empty() and _game_preload_t > 0:
		GameSession.perf_since("Browser: Gameplay-Szenen vorgeladen (Hintergrund)", _game_preload_t)
		_game_preload_t = 0


## Szenenwechsel ins Gameplay: vorgeladene PackedScene nutzen (laeuft der
## Ladevorgang noch, auf ihn warten statt doppelt zu laden).
func _change_to_game(path: String) -> void:
	if not _game_res.has(path) and _game_req.has(path):
		_game_req.erase(path)
		var r := ResourceLoader.load_threaded_get(path)
		if r != null:
			_game_res[path] = r
	var ps := _game_res.get(path) as PackedScene
	if ps != null:
		get_tree().change_scene_to_packed(ps)
	else:
		get_tree().change_scene_to_file(path)


## Auswahl im Hintergrund vorbereiten, sobald sie stabil ist; das Full-Res-
## Cover erst uebernehmen, wenn der Worker es dekodiert hat.
func _prepare_step() -> void:
	if _selected_set == null:
		return
	if _prep_due > 0 and Time.get_ticks_msec() >= _prep_due:
		_prep_due = 0
		var m := _selected_set.meta_at(_selected_diff)
		GameSession.preload_selection(_selected_set.osz_path, str(m.get("audio_filename", "")),
			_selected_set.background_file, _selected_set.version_name_at(_selected_diff))
		_bg_wait_set = _selected_set
	if _bg_wait_set != null and OszImporter.is_prepared(_bg_wait_set.osz_path):
		var target := _bg_wait_set
		_bg_wait_set = null
		_load_fullres_bg(target)


func _rebuild_cards() -> void:
	_scores_cfg = ConfigFile.new()
	if _scores_cfg.load(ScoreStore.PATH) != OK:
		_scores_cfg = null
	_pulse_card = null
	_thumb_queue.clear()
	for c in _list_box.get_children():
		c.queue_free()
	_card_buttons.clear()
	for i in _filtered.size():
		var card := _make_card(_filtered[i])
		# Halter (vom VBox gelayoutet) -> Slider (frei verschiebbar fuer den
		# Hover-Slide) -> [Glow-Panel hinter der Karte, Karte].
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(0, CARD_H)
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slider := Control.new()
		slider.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(slider)
		var glow := Panel.new()
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.visible = false
		slider.add_child(glow)
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slider.add_child(card)
		_list_box.add_child(holder)
		_card_buttons.append(card)
		card.mouse_entered.connect(_slide_card.bind(card, true))
		card.mouse_exited.connect(_slide_card.bind(card, false))
	if _collection_mode:
		for ms in _coll_unplayable:
			_list_box.add_child(_make_unplayable_card(ms))
	if _filtered.is_empty() and (_coll_unplayable.is_empty() or not _collection_mode) \
			and (_collection_mode or not _library.mapsets.is_empty()):
		var empty := Label.new()
		empty.text = _collection_empty_text() if _collection_mode else tr("Keine Maps für diese Filter")
		empty.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(0, CARD_H)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", COL_DIM)
		_list_box.add_child(empty)
		if _collection_mode:
			# Klarer Rueckweg aus einer leeren Sammlung.
			var back := Button.new()
			back.text = tr("Alle Maps zeigen")
			back.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			back.custom_minimum_size = Vector2(0, 40)
			back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			back.add_theme_font_size_override("font_size", 14)
			UiTheme.style_ghost_button(back, 10)
			back.pressed.connect(func(): _set_collection_mode(false))
			_list_box.add_child(back)
	_scores_cfg = null
	if _selected_set != null:
		_apply_card_highlight()
	_refresh_recommended()


## Sammlungs-Ansicht: Map ohne Diff fuer den aktuellen Modus. Bleibt sichtbar,
## gedimmt und klar markiert; nicht waehlbar.
func _make_unplayable_card(ms: MapSet) -> Control:
	var mode_name := collection_mode_hint(_play_mode)
	var names: Array = []
	for m in playable_modes(ms):
		names.append(collection_mode_hint(m))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, CARD_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_box(Color(COL_CARD, 0.55), Color(COL_DIM, 0.35)))
	card.tooltip_text = tr("Diese Map hat keine Diff für %s. Sie bleibt in der Sammlung.") % mode_name
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 16)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pad)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(hb)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var t := Label.new()
	t.text = "%s - %s" % [ms.artist, ms.title]
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", Color(COL_TEXT, 0.55))
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)
	var sub := Label.new()
	sub.text = tr("Nur osu!standard-Diffs. Spielbar in %s.") % ", ".join(names)
	sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", COL_DIM)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sub)
	var tag := Label.new()
	tag.text = tr("Nicht in %s spielbar") % mode_name
	tag.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", COL_ACCENT)
	var tb := _rounded_box(Color(COL_ACCENT, 0.08), 4, Color(COL_ACCENT, 0.45), 1)
	tb.content_margin_left = 8
	tb.content_margin_right = 8
	tb.content_margin_top = 3
	tb.content_margin_bottom = 3
	tag.add_theme_stylebox_override("normal", tb)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tag)
	return card


## "An Freund schicken": Map-Link ins Chat-Overlay (GameSession.chat).
func _share_selected_map() -> void:
	if _selected_set == null or GameSession.chat == null:
		return
	var file := _selected_set.osu_filename_at(_selected_diff)
	var key := _selected_set.osz_path + "|" + file
	if not _online_md5_cache.has(key):
		_online_md5_cache[key] = OnlineApi._md5_bytes(OszImporter.read_file_bytes(_selected_set.osz_path, file))
	var stars := _selected_set.stars_at(_selected_diff)
	var mode_st := _mode_stars_known(_selected_set, _selected_diff)
	if mode_st > 0.0:
		stars = mode_st
	var sid := ScoreStore.set_id_of(_selected_set.osz_path.get_file())
	GameSession.chat.call("share_map", {
		"md5": _online_md5_cache[key], "set_id": sid, "beatmapset_id": sid,
		"beatmap_id": int(_selected_set.meta_at(_selected_diff).get("beatmap_id", 0)),
		"title": _selected_set.title, "artist": _selected_set.artist,
		"version": _selected_set.version_name_at(_selected_diff), "stars": stars,
	})


## Hover-Slide: Karte gleitet 8 px nach links (ausgewaehlte bleibt draussen).
func _slide_card(card: Button, hovered: bool) -> void:
	if not is_instance_valid(card):
		return
	var slider := card.get_parent() as Control
	if slider == null:
		return
	var idx := _card_buttons.find(card)
	var is_sel := idx >= 0 and idx < _filtered.size() and _filtered[idx] == _selected_set
	_update_card_frame(card, hovered, is_sel)
	var target := -CARD_SLIDE if (hovered or is_sel) else 0.0
	if is_equal_approx(slider.offset_left, target):
		return
	if slider.has_meta("tw"):
		var old := slider.get_meta("tw") as Tween
		if old != null and old.is_valid():
			old.kill()
	var tw := slider.create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(slider, "offset_left", target, 0.16)
	tw.tween_property(slider, "offset_right", target, 0.16)
	slider.set_meta("tw", tw)


## Rechtsklick auf eine Karte: .osz nach Bestaetigung loeschen.
func _confirm_delete(ms: MapSet) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Map löschen"
	dlg.dialog_text = tr("\"%s — %s\" wirklich löschen?\nDie .osz-Datei wird vom Datenträger entfernt.") % [ms.artist, ms.title]
	dlg.ok_button_text = "Löschen"
	dlg.cancel_button_text = "Abbrechen"
	add_child(dlg)
	dlg.confirmed.connect(func():
		if FileAccess.file_exists(ms.osz_path):
			DirAccess.remove_absolute(ms.osz_path)
		var was_selected := _selected_set == ms
		_library.scan()
		_refresh_filter(_search.text)
		if was_selected and not _filtered.is_empty():
			_select_set(_filtered[0], _easiest(_filtered[0]))
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _sv_badge() -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bb := UiTheme.solid_box(Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.9), 8)
	bb.content_margin_left = 7
	bb.content_margin_right = 7
	bb.content_margin_top = 2
	bb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", bb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.tooltip_text = "Enthält Scroll-Velocity-Wechsel (SV)"
	var l := Label.new()
	l.text = "SV"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.03, 0.05, 0.08))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	return pc


func _make_card(ms: MapSet) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, CARD_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	# Schmaler Diff-Streifen in Sternfarbe (einziger Farbakzent der Karte).
	var base := _card_box(COL_CARD, _star_color(_mode_max(ms)))
	for st in ["normal", "hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(st, base)
	card.pressed.connect(func(): _on_card_pressed(ms))
	# Rechtsklick: Map nach Bestaetigung vom Datenträger loeschen.
	card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed \
				and e.button_index == MOUSE_BUTTON_RIGHT:
			_confirm_delete(ms))

	# Cover als Kartenhintergrund — LAZY: Thumbnails werden ueber Frames
	# verteilt geladen (UI erscheint sofort, kein Ruckeln). Kind 0 (Beat-Puls).
	# Shader: abgerundete Ecken + deckender Verlauf links (Text lesbar).
	var card_bg := TextureRect.new()
	card_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_bg.offset_left = 4
	card_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card_bg.material = _card_cover_mat
	card_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_bg.resized.connect(_on_card_bg_resized.bind(card_bg))
	card.add_child(card_bg)
	_thumb_queue.append({ "ms": ms, "bg": card_bg })

	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 20
	hb.offset_right = -16
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)

	var t := Label.new()
	t.text = "%s - %s" % [ms.artist, ms.title]
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", COL_TEXT)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	t.add_theme_constant_override("shadow_offset_y", 1)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)

	var m := Label.new()
	m.text = _card_info_text(ms)
	card.set_meta("info_lbl", m)
	m.add_theme_font_size_override("font_size", 13)
	m.add_theme_color_override("font_color", Color(0.78, 0.80, 0.88))
	m.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(m)

	# SV-Badge: Set enthaelt mindestens eine Diff mit echter SV.
	if ms.has_sv():
		hb.add_child(_sv_badge())

	# Orbit/Frei: dezente Marke "Empfohlen", wenn die Map zur Karriere-Stufe passt.
	var rec := Label.new()
	rec.text = tr("Empfohlen")
	rec.visible = false
	rec.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rec.add_theme_font_size_override("font_size", 11)
	rec.add_theme_color_override("font_color", UiTheme.ACCENT2)
	rec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(rec)
	card.set_meta("rec_lbl", rec)

	# Grade-Badge des besten Scores im aktiven Modus: klein, fester Platz,
	# Notenfarbe. Beim Moduswechsel per _refresh_card_grades() neu.
	var g := Label.new()
	g.custom_minimum_size = Vector2(28, 0)
	g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.add_theme_font_override("font", UiTheme.heading_font(0))
	g.add_theme_font_size_override("font_size", 18)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(g)
	card.set_meta("grade_lbl", g)
	card.set_meta("ms", ms)
	_set_card_grade(g, _best_grade_badge(ms))

	# Rahmen oben drauf (Auswahl = ACCENT, Hover = hell, sonst fein).
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _frame_idle)
	card.add_child(frame)
	card.set_meta("frame", frame)

	return card

## Bester Rang des Sets im aktiven Modus (Orbit: nur 4K-Diffs, eigene
## Orbit-Sektion; Mania: wie bisher "scores"). "" ohne Score.
func _best_grade_badge(ms: MapSet) -> String:
	if _scores_cfg == null:
		return ""
	var orbit := _play_mode != "mania"
	var sec := ScoreStore._sec("scores", _pm())
	var best_g := ""
	var best_rank := 999
	for i in range(ms.difficulty_count() - 1, -1, -1):
		if not ms.diff_visible(i, _vm()) or (not orbit and int(ms.meta_at(i).get("mode", 0)) != 3):
			continue
		# Gleiche Abfrage wie ScoreStore.best(), aber ohne scores.cfg pro Aufruf neu zu lesen.
		var best = _scores_cfg.get_value(sec, ScoreStore._key(ms.osz_path, ms.version_name_at(i)), {})
		if best is Dictionary and not best.is_empty():
			var gr := str(best.get("grade", ""))
			var r := ScoreStore.GRADES.find(gr)
			if r < 0:
				r = ScoreStore.GRADES.find(gr.left(1))
			if r < 0:
				r = 99
			if best_g == "" or r < best_rank:
				best_g = gr
				best_rank = r
	return best_g


func _set_card_grade(g: Label, grade: String) -> void:
	g.text = grade
	g.visible = grade != ""
	g.add_theme_color_override("font_color", GRADE_COLOR.get(grade.left(1), COL_TEXT))
	g.tooltip_text = (tr("Bester Rang (%s)") % ScoreStore.mode_label(_pm())) if grade != "" else ""


## Rang-Badges aller Karten fuer den aktiven Modus neu setzen (ohne Neuaufbau).
func _refresh_card_grades() -> void:
	_scores_cfg = ConfigFile.new()
	if _scores_cfg.load(ScoreStore.PATH) != OK:
		_scores_cfg = null
	for card in _card_buttons:
		if is_instance_valid(card) and card.has_meta("grade_lbl"):
			_set_card_grade(card.get_meta("grade_lbl"), _best_grade_badge(card.get_meta("ms")))
	_scores_cfg = null


# ---------------------------------------------------------------------------
# Auswahl / Play
# ---------------------------------------------------------------------------

func _select_initial() -> void:
	var last := GameSession.load_last_played()
	if not last.is_empty():
		for ms in _filtered:
			if ms.osz_path == last.osz_path:
				_select_set(ms, clampi(int(last.difficulty_index), 0, ms.difficulty_count() - 1))
				_scroll_to_selected.call_deferred()
				return
	if not _filtered.is_empty():
		_select_set(_filtered[0], _easiest(_filtered[0]))


func _on_card_pressed(ms: MapSet) -> void:
	if _selected_set == ms:
		_on_play_pressed()
		return
	_select_set(ms, _hardest(ms))


func _select_set(ms: MapSet, diff_index: int) -> void:
	_perf_select_t = Time.get_ticks_usec()
	_selected_set = ms
	_selected_diff = clampi(diff_index, 0, ms.difficulty_count() - 1)
	_selected_diff = maxi(ms.nearest_visible(_selected_diff, _vm()), 0)
	_update_info_panel()
	Sfx.select_chime()
	_play_preview()


func _cycle_difficulty(dir: int) -> void:
	if _selected_set == null:
		return
	# Pfeile folgen der Diff-Leiste: Reihenfolge nach Modus-Sternen.
	var order := _mode_order(_selected_set)
	if order.is_empty():
		return
	_selected_diff = MapSet.cycle_in(order, _selected_diff, dir)
	_update_info_panel()


func _update_info_panel() -> void:
	if _selected_set == null:
		return
	if _career_panel != null:
		_career_panel.set_selected(_selected_set, _selected_diff)
	_recs_mark_selected()
	var m := _selected_set.meta_at(_selected_diff)
	# Sofort das schnelle Thumbnail zeigen, das Full-Res-Cover einen Frame
	# spaeter nachladen (Klicks fuehlen sich sofort an).
	var quick := _selected_set.thumb_texture()
	# Hintergrund: nur ein weicher Farbverlauf des Covers, kein erkennbares Motiv.
	_bg.texture = UiTheme.blurred_texture(quick, 8) if quick != null else null
	_cover.texture = quick
	_prep_due = Time.get_ticks_msec() + PREPARE_DELAY_MS
	_bg_wait_set = null
	_title_label.text = _selected_set.title
	_title_label.tooltip_text = _selected_set.title
	_artist_label.text = _selected_set.artist
	_artist_label.tooltip_text = _selected_set.artist
	_mapper_label.text = tr("Map von %s") % _selected_set.creator
	var is_mania := int(m.get("mode", 0)) == 3
	var keys := int(round(float(m.get("cs", 4.0))))
	_diff_label.text = _selected_set.version_name_at(_selected_diff).strip_edges() 		+ (("  ·  %dK" % keys) if is_mania else "  ·  osu!standard")
	_refresh_star_label()
	var src := _star_src()
	if src != "mania" and src != "trace" and _orbit_diff_ok(_selected_set, _selected_diff):
		_orbit_stars_request(_selected_set.osz_path, _selected_set.version_name_at(_selected_diff))
	_bg_front_set(_selected_set)
	var notes := tr("%d Noten") % int(m.get("notes", 0))
	var od := "OD " + UiTheme.fmt_num(float(m.get("od", 0.0)))
	if is_mania:
		# Mania: CS ist die Tastenzahl, AR gibt es nicht.
		_stats_label.text = tr("%s  ·  %d Tasten  ·  %s") % [notes, keys, od]
	else:
		_stats_label.text = "%s  ·  CS %s  ·  AR %s  ·  %s" % [notes,
			UiTheme.fmt_num(float(m.get("cs", 0.0))), UiTheme.fmt_num(float(m.get("ar", 0.0))), od]
	_bpm_label.text = "%s BPM" % _bpm_text(_selected_set, _selected_diff)
	_len_label.text = _format_time(float(m.get("duration_ms", 0.0)))
	_rebuild_diff_bar()
	if _preview_set == _selected_set:
		_setup_beat_clock()
	_update_max_pp(m)
	# BESTE SCORES: Top 5 dieser Difficulty als cleane Rows.
	for c in _lb_box.get_children():
		c.queue_free()
	# Eigene + Scores von Mitspielern (Multiplayer-Sync), beste zuerst.
	# Orbit-Modus (nur 4K-Diffs): nur Orbit-Scores, getrennt von Mania.
	var orbit := _play_mode != "mania" and int(m.get("mode", 0)) in [0, 3]
	var score_mode := _pm() if orbit else ""
	# Mods-Schalter "Mines" an: eigene Liste "mania_mn" (RuleMods), Kopf zeigt "Mines".
	if _play_mode == "mania":
		score_mode = RuleMods.board_mode(score_mode, _rule_mods)
	_style_lb_mode_tag(score_mode)
	_online_gen += 1
	if _lb_online:
		_replay_btn.visible = false
		_show_online_scores(m, score_mode)
		_apply_card_highlight()
		return
	var tops := ScoreStore.top_scores_all(_selected_set.osz_path,
		_selected_set.version_name_at(_selected_diff), 5, score_mode)
	if tops.is_empty():
		var empty := Label.new()
		empty.text = RuleMods.board_text("empty") if RuleMods.is_mines_board(score_mode) 				else tr("Noch kein %s-Score — spiel die Map!") % ScoreStore.mode_label(score_mode)
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", COL_DIM)
		_lb_box.add_child(empty)
	for i in tops.size():
		_lb_box.add_child(_score_row(i, tops[i]))
	_fill_missing_pp(tops, score_mode)
	# Replay-Button nur zeigen, wenn fuer diese Diff ein Replay existiert.
	# Orbit: Replay des besten Orbit-Laufs (ReplayStore-Modus "orbit").
	if _replay_btn != null:
		var ver := _selected_set.version_name_at(_selected_diff)
		if orbit:
			# Replay des besten Laufs; Rally/Dirigent nur, sobald ihre Szene da ist.
			_replay_btn.visible = ScoreStore.mode_ready(score_mode) 					and ReplayStore.exists(_selected_set.osz_path, ver, ReplayStore.best_mode_of(score_mode))
		else:
			_replay_btn.visible = int(m.get("mode", 0)) == 3 				and ReplayStore.exists(_selected_set.osz_path, ver)
	_apply_card_highlight()


## Auswahl-Hervorhebung: Rahmen immer in ACCENT + weicher Glow dahinter.
## Sternfarbe bleibt im schmalen Diff-Streifen.
func _apply_card_highlight() -> void:
	_sel_box = null
	for i in _card_buttons.size():
		var card := _card_buttons[i]
		if not is_instance_valid(card):
			continue
		var is_sel := _filtered[i] == _selected_set
		var glow := card.get_parent().get_child(0) as Panel
		if glow != null:
			glow.visible = is_sel
			if is_sel:
				glow.add_theme_stylebox_override("panel", _glow_box)
				_sel_box = _glow_box
		_slide_card(card, card.is_hovered())


## Rahmen-Stil je nach Zustand (geteilte StyleBoxen, keine Allokation).
func _update_card_frame(card: Button, hovered: bool, is_sel: bool) -> void:
	var frame := card.get_meta("frame", null) as Panel
	if frame == null:
		return
	var box := _frame_sel if is_sel else (_frame_hover if hovered else _frame_idle)
	frame.add_theme_stylebox_override("panel", box)


const _CARD_COVER_CODE := "shader_type canvas_item;
uniform vec2 rect_size = vec2(600.0, 76.0);
uniform float radius = 12.0;
uniform vec3 shade_col : source_color = vec3(0.06, 0.06, 0.09);
varying vec2 local;
void vertex() { local = VERTEX; }
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float x = clamp(local.x / rect_size.x, 0.0, 1.0);
	c.rgb = mix(c.rgb, shade_col, mix(0.93, 0.30, smoothstep(0.35, 1.0, x)));
	vec2 q = abs(local - rect_size * 0.5) - (rect_size * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	c.a *= clamp(0.5 - d, 0.0, 1.0);
	COLOR = c;
}
"


## Alle Karten teilen ein Material; nur bei Layout-Aenderung neu setzen.
func _on_card_bg_resized(bg: TextureRect) -> void:
	if bg.size.x > 0.0 and not bg.size.is_equal_approx(_card_cover_size):
		_card_cover_size = bg.size
		_card_cover_mat.set_shader_parameter("rect_size", bg.size)


func _init_card_styles() -> void:
	var sh := Shader.new()
	sh.code = _CARD_COVER_CODE
	_card_cover_mat = ShaderMaterial.new()
	_card_cover_mat.shader = sh
	_card_cover_mat.set_shader_parameter("radius", float(CARD_RADIUS))
	_frame_idle = _frame_box(Color(1, 1, 1, 0.07), 1)
	_frame_hover = _frame_box(Color(1, 1, 1, 0.24), 1)
	_frame_sel = _frame_box(COL_ACCENT, 2)
	_glow_box = StyleBoxFlat.new()
	_glow_box.bg_color = Color(0, 0, 0, 0)
	_glow_box.set_corner_radius_all(CARD_RADIUS)
	_glow_box.shadow_color = Color(COL_ACCENT, 0.22)
	_glow_box.shadow_size = 10
	_glow_box.shadow_offset = Vector2.ZERO


func _frame_box(col: Color, w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(CARD_RADIUS)
	sb.set_border_width_all(w)
	sb.border_color = col
	return sb


## Ein Segment pro Difficulty in Sternfarbe; Klick waehlt die Diff.
func _rebuild_diff_bar() -> void:
	for c in _diff_bar.get_children():
		c.queue_free()
	if _diff_bar == null or _selected_set == null:
		return
	for i in _mode_order(_selected_set):
		var seg := ColorRect.new()
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sel := i == _selected_diff
		seg.custom_minimum_size = Vector2(0, 8 if sel else 4)
		var st := _mode_stars(_selected_set, i)
		var col := _star_color(st)
		seg.color = col.lightened(0.15) if sel else Color(col, 0.40)
		seg.tooltip_text = "%s  %s" % [_selected_set.version_name_at(i), _stars_text(st)]
		seg.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		seg.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_selected_diff = i
				_update_info_panel())
		_diff_bar.add_child(seg)


## BPM der Diff aus den roten Timing-Linien (einmal pro Diff, gecacht).
## Bereich "min–max", wenn die Map das Tempo wechselt.
func _bpm_text(ms: MapSet, diff: int) -> String:
	var key := ms.osz_path + "|" + ms.osu_filename_at(diff)
	if _bpm_cache.has(key):
		return str(_bpm_cache[key])
	var txt := "—"
	var lo := INF
	var hi := 0.0
	for tp in _timing_points(ms, diff):
		if tp.uninherited and tp.beat_length > 0.0:
			var b: float = 60000.0 / tp.beat_length
			lo = minf(lo, b)
			hi = maxf(hi, b)
	if hi > 0.0:
		txt = ("%d" % roundi(hi)) if roundi(lo) == roundi(hi) \
			else "%d–%d" % [roundi(lo), roundi(hi)]
	_bpm_cache[key] = txt
	return txt


## Timing-Points der Diff (einmal gelesen, gecacht) — fuer BPM und BeatClock.
func _timing_points(ms: MapSet, diff: int) -> Array:
	var key := ms.osz_path + "|" + ms.osu_filename_at(diff)
	if _tp_cache.has(key):
		return _tp_cache[key]
	var out: Array = []
	var bytes := OszImporter.read_file_bytes(ms.osz_path, ms.osu_filename_at(diff))
	if not bytes.is_empty():
		var in_tp := false
		for raw_line in bytes.get_string_from_utf8().split("\n"):
			var line := raw_line.strip_edges()
			if line.begins_with("["):
				if in_tp:
					break
				in_tp = line == "[TimingPoints]"
				continue
			if not in_tp or line == "":
				continue
			var tp := OsuParser._parse_timing_line(line)
			if tp != null:
				out.append(tp)
	_tp_cache[key] = out
	return out


## Beat-Phase der Vorschau neu aufsetzen (bei Map- oder Diff-Wechsel).
func _setup_beat_clock() -> void:
	if _selected_set == null:
		return
	_beat.setup(_timing_points(_selected_set, _selected_diff))


## Hoerbare Position der Vorschau in ms (Mix-Puffer + Ausgabelatenz korrigiert).
func _preview_ms() -> float:
	if _preview == null or not _preview.playing:
		return -1.0
	return (_preview.get_playback_position() + AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()) * 1000.0


func _restyle_lb_src() -> void:
	for i in _lb_src_btns.size():
		_apply_toggle(_lb_src_btns[i], (i == 1) == _lb_online)


func _set_lb_online(on: bool) -> void:
	if _lb_online == on:
		return
	_lb_online = on
	_restyle_lb_src()
	_update_info_panel()


func _lb_hint(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", COL_DIM)
	_lb_box.add_child(l)


## Online-Rangliste der gewaehlten Diff (asynchron). Ohne Key/Login: klarer Hinweis.
func _show_online_scores(m: Dictionary, score_mode: String) -> void:
	var api: OnlineApi = GameSession.online
	if api == null or not api.enabled():
		_lb_hint(tr("Online-Ranglisten sind noch nicht freigeschaltet."))
		return
	if not api.logged_in():
		_lb_hint(tr("Melde dich im Profil an, um Online-Ranglisten zu sehen."))
		return
	var file := _selected_set.osu_filename_at(_selected_diff)
	var key := _selected_set.osz_path + "|" + file
	if not _online_md5_cache.has(key):
		_online_md5_cache[key] = OnlineApi._md5_bytes(OszImporter.read_file_bytes(_selected_set.osz_path, file))
	var md5: String = _online_md5_cache[key]
	if md5 == "":
		_lb_hint(tr("Für diese Map gibt es keine Online-Rangliste."))
		return
	_lb_hint(tr("Lade Rangliste …"))
	var gen := _online_gen
	if RuleMods.is_mines_board(score_mode):
		_show_online_mines(api, md5, gen)
		return
	api.leaderboard(ScoreStore.mode_name(score_mode), md5, 0, func(ok: bool, entries: Array, msg: String):
		if gen != _online_gen or not is_inside_tree():
			return
		for c in _lb_box.get_children():
			c.queue_free()
		if not ok:
			_lb_hint(tr("Rangliste nicht erreichbar.") + (" (%s)" % msg if msg != "" else ""))
		elif entries.is_empty():
			_lb_hint(tr("Noch kein Online-Score auf dieser Map."))
		for i in mini(entries.size(), 10):
			var oe: Dictionary = entries[i] if entries[i] is Dictionary else {}
			if str(oe.get("mode", "")) == "":
				oe["mode"] = ScoreStore.mode_name(score_mode)
			_lb_box.add_child(_online_row(oe)))


## Online-Minen-Liste ("mania_mn"): nur zeigen, wenn der Server "board" kennt; sonst
## ein ruhiger Hinweis statt der normalen Mania-Liste (die er ohne board liefert).
func _show_online_mines(api: OnlineApi, md5: String, gen: int) -> void:
	var board := RuleMods.MINES_SCORE_MODE
	api.leaderboard_board("mania", board, md5, func(ok: bool, entries: Array, msg: String, known: bool):
		if gen != _online_gen or not is_inside_tree():
			return
		for c in _lb_box.get_children():
			c.queue_free()
		if ok and not known:
			_lb_hint(RuleMods.board_text("online_soon"))
			return
		if not ok:
			_lb_hint(tr("Rangliste nicht erreichbar.") + (" (%s)" % msg if msg != "" else ""))
		elif entries.is_empty():
			_lb_hint(RuleMods.board_text("empty"))
		for i in mini(entries.size(), 10):
			var oe: Dictionary = entries[i] if entries[i] is Dictionary else {}
			oe["mode"] = "mania"
			oe["pp"] = 0.0   # Minen: keine pp
			_lb_box.add_child(_online_row(oe)))


## Online-Zeile: Rang, Grade, Spielername (Klick = Web-Profil), Score, Acc, pp.
func _online_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	var num := Label.new()
	num.text = "#%d" % int(e.get("rank", 0))
	num.custom_minimum_size = Vector2(30, 0)
	num.add_theme_font_size_override("font_size", 12)
	num.add_theme_color_override("font_color", COL_TEXT if int(e.get("rank", 0)) == 1 else COL_DIM)
	row.add_child(num)
	var g := str(e.get("grade", "?"))
	var grade := Label.new()
	grade.text = g
	grade.custom_minimum_size = Vector2(28, 0)
	grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade.add_theme_font_override("font", UiTheme.heading_font(0))
	grade.add_theme_font_size_override("font_size", 15)
	grade.add_theme_color_override("font_color", GRADE_COLOR.get(g.left(1), COL_TEXT))
	row.add_child(grade)
	row.add_child(ModeBadge.make(str(e.get("mode", "mania")), 14))
	var who := str(e.get("player", "?"))
	row.add_child(_online_avatar(who))
	var name_btn := LinkButton.new()
	name_btn.text = who
	name_btn.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	name_btn.tooltip_text = tr("Profil im Browser öffnen")
	name_btn.add_theme_font_size_override("font_size", 13)
	name_btn.add_theme_color_override("font_color", COL_TEXT)
	name_btn.pressed.connect(func(): GameSession.online.open_profile(who))
	row.add_child(name_btn)
	var main := Label.new()
	main.text = "%s · %s" % [UiTheme.fmt_score(int(e.get("score", 0))),
		UiTheme.fmt_pct(float(e.get("accuracy", 0.0)) * 100.0)]
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	main.add_theme_font_size_override("font_size", 13)
	main.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	row.add_child(main)
	var pp_val := float(e.get("pp", 0.0))
	if pp_val > 0.0:
		var pp_lbl := Label.new()
		pp_lbl.text = UiTheme.fmt_pp(pp_val)
		pp_lbl.add_theme_font_size_override("font_size", 13)
		pp_lbl.add_theme_color_override("font_color", UiTheme.ACCENT2)
		row.add_child(pp_lbl)
	return row


## Kleiner runder Avatar fuer die Online-Rangliste: Initiale, bis das Bild von der
## Website da ist (OnlineApi.player_avatar, Speicher-Cache je Spieler).
func _online_avatar(who: String) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(20, 20)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle := ColorRect.new()
	circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	circle.color = Color(0.16, 0.30, 0.42)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/avatar_circle.gdshader")
	circle.material = m
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(circle)
	var initial := Label.new()
	initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initial.text = who.strip_edges().substr(0, 1).to_upper()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_size_override("font_size", 11)
	initial.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(initial)
	var api: OnlineApi = GameSession.online
	if api == null:
		return slot
	api.player_avatar(who, func(tex: Texture2D):
		if tex == null or not is_instance_valid(slot):
			return
		var rect := TextureRect.new()
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.texture = tex
		var m2 := ShaderMaterial.new()
		m2.shader = m.shader
		rect.material = m2
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(rect))
	return slot


## Eine Leaderboard-Zeile: Rang, Grade, Score/Acc, pp, Datum.
## Mitspieler-Scores ohne pp (Live-Endergebnis im Multiplayer): pp aus der
## Online-Rangliste der Map nachtragen (gleicher Spieler + Score) und die Liste
## neu aufbauen. Je Map/Modus nur ein Versuch pro Sitzung.
func _fill_missing_pp(tops: Array, score_mode: String) -> void:
	if score_mode != "" or _selected_set == null:
		return  # pp gibt es nur in Mania
	var missing := false
	for e in tops:
		if not bool(e.get("is_self", true)) and float(e.get("pp", -1.0)) <= 0.0:
			missing = true
			break
	var api: OnlineApi = GameSession.online
	if not missing or api == null or not api.enabled() or not api.logged_in():
		return
	var file := _selected_set.osu_filename_at(_selected_diff)
	var key := _selected_set.osz_path + "|" + file
	if _pp_fill_tried.has(key):
		return
	_pp_fill_tried[key] = true
	if not _online_md5_cache.has(key):
		_online_md5_cache[key] = OnlineApi._md5_bytes(OszImporter.read_file_bytes(_selected_set.osz_path, file))
	var md5: String = _online_md5_cache[key]
	if md5 == "":
		return
	var map_key := ScoreStore.map_id(_selected_set.osz_path, _selected_set.version_name_at(_selected_diff))
	var gen := _online_gen
	api.leaderboard(ScoreStore.mode_name(score_mode), md5, 0, func(ok: bool, entries: Array, _msg: String):
		if not ok:
			_pp_fill_tried.erase(key)  # Server nicht erreichbar: später erneut
			return
		if ScoreStore.fill_others_pp(map_key, entries) > 0 and gen == _online_gen 				and is_inside_tree() and not _lb_online:
			_update_info_panel())


## Geschätzte pp eines Fremd-Scores ohne pp: Max-pp der Diff mal Acc-Anteil
## (0 bei 80 %, 1 bei 100 %). -1, wenn Max-pp noch nicht berechnet ist.
func _estimate_pp(e: Dictionary) -> float:
	if _selected_set == null or bool(e.get("unranked", false)):
		return -1.0
	var max_pp := StarService.max_pp_cached(_selected_set.osz_path,
		_selected_set.osu_filename_at(_selected_diff))
	if max_pp <= 0.0:
		return -1.0
	return max_pp * Recommender.acc_factor(float(e.get("accuracy", 0.0)))


func _score_row(rank: int, e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	var num := Label.new()
	num.text = "#%d" % (rank + 1)
	num.custom_minimum_size = Vector2(24, 0)
	num.add_theme_font_size_override("font_size", 12)
	num.add_theme_color_override("font_color", COL_TEXT if rank == 0 else COL_DIM)
	row.add_child(num)
	var g := str(e.get("grade", "?"))
	var grade := Label.new()
	grade.text = g
	grade.custom_minimum_size = Vector2(28, 0)
	grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade.add_theme_font_override("font", UiTheme.heading_font(0))
	grade.add_theme_font_size_override("font_size", 15)
	grade.add_theme_color_override("font_color", GRADE_COLOR.get(g.left(1), COL_TEXT))
	row.add_child(grade)
	# Modus-Symbol: jeder Score zeigt, in welchem Modus er gespielt wurde.
	row.add_child(ModeBadge.make(str(e.get("mode", "mania")), 14))
	var main := Label.new()
	var is_self := bool(e.get("is_self", true))
	main.text = "%s · %s · %dx" % [
		UiTheme.fmt_score(int(e.get("score", 0))),
		UiTheme.fmt_pct(float(e.get("accuracy", 0.0)) * 100.0), int(e.get("max_combo", 0))]
	if not is_self:
		# Mitspieler: Name vorne, Combo weglassen (Platz).
		main.text = "%s · %s · %s" % [str(e.get("player", "?")),
			UiTheme.fmt_score(int(e.get("score", 0))),
			UiTheme.fmt_pct(float(e.get("accuracy", 0.0)) * 100.0)]
		main.tooltip_text = tr("Score von %s (Multiplayer)") % str(e.get("player", "?"))
		main.mouse_filter = Control.MOUSE_FILTER_PASS
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	main.add_theme_font_size_override("font_size", 13)
	main.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	row.add_child(main)
	# Mods des Scores (SV mit Stufe), klein vor pp.
	var mods_txt := ScoreStore.mods_label(e)
	if mods_txt != "":
		var ml := Label.new()
		ml.text = mods_txt
		ml.add_theme_font_size_override("font_size", 11)
		ml.add_theme_color_override("font_color", COL_ACCENT.lerp(COL_TEXT, 0.3))
		row.add_child(ml)
	var pp_lbl := Label.new()
	var pp_val := float(e.get("pp", -1.0))
	pp_lbl.text = UiTheme.fmt_pp(pp_val) if pp_val > 0.0 else "—"
	if pp_val <= 0.0 and not is_self and str(e.get("mode", "mania")) == "mania":
		var est := _estimate_pp(e)
		if est > 0.0:
			pp_lbl.text = "≈ " + UiTheme.fmt_pp(est)
			pp_lbl.tooltip_text = tr("Geschätzt aus Accuracy (Multiplayer-Score ohne pp)")
			pp_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
			pp_lbl.modulate.a = 0.7
	if str(e.get("mode", "")) == ScoreStore.MODE_ORBIT:
		pp_lbl.visible = false  # Orbit hat keine pp
	pp_lbl.add_theme_font_size_override("font_size", 13)
	pp_lbl.add_theme_color_override("font_color", UiTheme.ACCENT2)
	row.add_child(pp_lbl)
	var oid := str(e.get("online_id", ""))
	if oid != "" and is_self and GameSession.chat != null:
		var sh := Button.new()
		sh.text = "⇪"
		sh.tooltip_text = tr("Score teilen")
		sh.custom_minimum_size = Vector2(26, 22)
		sh.add_theme_font_size_override("font_size", 12)
		UiTheme.style_ghost_button(sh, 6)
		sh.pressed.connect(func(): ScoreShare.share(oid))
		row.add_child(sh)
	var date := Label.new()
	var d := str(e.get("date", "")).split("T")[0]
	var parts := d.split("-")
	if parts.size() != 3:
		date.text = ""
	elif UiTheme.is_german():
		date.text = "%s.%s.%s" % [parts[2], parts[1], parts[0].substr(2)]
	else:
		date.text = "%s/%s/%s" % [parts[1], parts[2], parts[0].substr(2)]
	date.custom_minimum_size = Vector2(58, 0)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date.add_theme_font_size_override("font_size", 12)
	date.add_theme_color_override("font_color", COL_DIM)
	row.add_child(date)
	return row


## Modus-Umschalter Mania 4K | Orbit | Rally / Dirigent | Trace | Rebound als 3x2-Raster
## (gleiche Toggle-Optik wie die Filter-Chips).
const MODE_TIPS := {
	"mania": "Klassisch: vier Spuren",
	"orbit": "Zielen mit Maus/Tablet, Ring per Taste (osu!standard- und 4K-Maps)",
	"rally": "Tischtennis im Takt: Schläge auf die Noten, zwei Tasten",
	"dirigent": "Taktfigur mit der Maus führen, Einsätze per Taste",
	"trace": "Ein Leuchtfaden zeichnet die Map: jede Note ein Knick (4K-Maps)",
	"rebound": "Vier Bälle springen auf ihre Noten (4K-Maps)",
}


func _build_mode_switch() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.custom_minimum_size = Vector2(0, 58)
	_mode_btns.clear()
	for m in PLAY_MODES:
		var b := _make_toggle(ScoreStore.mode_label("" if m == "mania" else m), 13, 6)
		b.custom_minimum_size = Vector2(0, 27)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.tooltip_text = tr(MODE_TIPS[m])
		var mode: String = m
		b.pressed.connect(func(): _set_play_mode(mode))
		grid.add_child(b)
		_mode_btns.append(b)
	_restyle_mode_switch()
	return grid


## Sichtbarkeits-Modus fuer MapSet: Orbit/Rally/Dirigent zeigen 4K und osu!standard,
## Mania/Trace/Rebound nur Mania-4K.
func _vm() -> String:
	return "mania" if _mania_like() else "orbit"


## Aktiver Modus wertet wie Mania 4K auf Mania-Maps (Mania, Trace, Rebound).
func _mania_like() -> bool:
	return ScoreStore.is_mania_like(_play_mode)


## Tutorial-Knopf nur zeigen, wenn scenes/<modus>_tutorial.tscn existiert.
func _apply_tutorial_btn() -> void:
	if _tutorial_btn == null:
		return
	var path := ScoreStore.mode_tutorial(_play_mode)
	_tutorial_btn.visible = path != ""
	_tutorial_btn.tooltip_text = tr("Tutorial: %s") % ScoreStore.mode_label(_pm())


func _start_mode_tutorial() -> void:
	if _play_mode == "orbit":
		_start_orbit_tutorial()
		return
	var path := ScoreStore.mode_tutorial(_play_mode)
	if path == "":
		return
	_preview.stop()
	SceneFader.go(path)


## ScoreStore-Modus des aktiven Browser-Modus ("" = Mania).
func _pm() -> String:
	return "" if _play_mode == "mania" else _play_mode


## Play-Knopf: ohne Szene des Modus "Kommt bald" statt Absturz.
func _apply_play_state() -> void:
	if _play_btn == null:
		return
	var ready := ScoreStore.mode_ready(_play_mode)
	_play_btn.disabled = not ready
	_play_btn.text = tr("Spielen") if ready else tr("Kommt bald")
	_play_btn.tooltip_text = "" if ready else tr("Dieser Modus wird gerade gebaut.")


func _set_play_mode(mode: String) -> void:
	if not PLAY_MODES.has(mode) or mode == _play_mode:
		return
	_play_mode = mode
	_bg_drop_other_modes()
	_restyle_mode_switch()
	_apply_play_state()
	_restyle_score_chips()  # Sortierung/Bestwert-Filter sind je Modus gemerkt
	_apply_mod_visibility()
	if mode == "orbit":
		_show_orbit_hint()
	_apply_career_layout()
	_career_start()
	_recs_refresh()
	if _collection_mode:
		_rebuild_chips()  # Sammlungen haengen am Modus
	# Sichtbare Maps haengen am Modus (osu!standard nur im Orbit-Modus).
	var keep := _selected_set
	_refresh_filter(_search.text)
	_refresh_card_grades()
	if keep != null and not _filtered.has(keep):
		_selected_set = null
		if not _filtered.is_empty():
			_select_set(_filtered[0], _hardest(_filtered[0]))
	elif _selected_set != null:
		_selected_diff = maxi(_selected_set.nearest_visible(_selected_diff, _vm()), 0)
		_update_info_panel()
	if _state_ready:
		_save_browser_state()


## Hinweis ueber dem Modus-Umschalter: "Orbit lernen (1 Min.)", bis das Tutorial
## gesehen ist; danach einmalig "Karriere starten" (Angebot nach dem Tutorial).
func _show_orbit_hint() -> void:
	if _orbit_hint != null or _mode_btns.is_empty():
		return
	var tut: GDScript = load(ORBIT_TUTORIAL_SCRIPT)
	var teach := _orbit_hint_force or not bool(tut.is_seen())
	var offer := not teach and bool(_career_state.get("offer", false)) 			and str(_career_state.get("mode", "")) != OrbitCareer.MODE_CAREER
	if not teach and not offer:
		return
	_hint_kind = "teach" if teach else "offer"
	var p := PanelContainer.new()
	var sb := UiTheme.glass_box(8, 0.96, 0.22)
	sb.content_margin_left = 14
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)
	var tick := ColorRect.new()
	tick.color = UiTheme.ACCENT
	tick.custom_minimum_size = Vector2(3, 0)
	row.add_child(tick)
	var txt := Label.new()
	txt.text = tr("Neu in Orbit?") if teach else tr("Orbit in kleinen Schritten lernen?")
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.add_theme_font_size_override("font_size", 13)
	txt.add_theme_color_override("font_color", COL_TEXT)
	row.add_child(txt)
	var learn := Button.new()
	learn.text = tr("Orbit lernen (1 Min.)") if teach else tr("Karriere starten")
	learn.tooltip_text = tr("Eine kurze Einführung zeigt Zielen, Ringe und Bögen.") if teach 			else tr("Empfiehlt dir passende Maps und steigert die Schwierigkeit mit dir.")
	learn.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(learn, true, 8)
	learn.pressed.connect(_start_orbit_tutorial if teach else _accept_career_offer)
	row.add_child(learn)
	var later := Button.new()
	later.text = tr("Später")
	later.focus_mode = Control.FOCUS_NONE
	UiTheme.style_ghost_button(later, 8)
	later.pressed.connect(_dismiss_orbit_hint)
	row.add_child(later)
	p.modulate.a = 0.0
	add_child(p)
	_orbit_hint = p
	_place_orbit_hint.call_deferred()
	create_tween().tween_property(p, "modulate:a", 1.0, 0.25)


## Ueber den Modus-Umschalter setzen, im Bild gehalten.
func _place_orbit_hint() -> void:
	if _orbit_hint == null or _mode_btns.is_empty():
		return
	# So breit wie die Zeile Modus-Umschalter + Spielen.
	var anchor := (_mode_btns[0].get_parent() as Control).get_global_rect()
	if _play_btn != null:
		anchor = anchor.merge(_play_btn.get_global_rect())
	var sz := _orbit_hint.get_combined_minimum_size()
	sz.x = maxf(sz.x, anchor.size.x)
	_orbit_hint.size = sz
	var vp := get_viewport_rect().size
	var pos := Vector2(anchor.position.x, anchor.position.y - sz.y - 10.0)
	_orbit_hint.position = Vector2(clampf(pos.x, 8.0, maxf(vp.x - sz.x - 8.0, 8.0)), maxf(pos.y, 8.0))


func _dismiss_orbit_hint() -> void:
	if _hint_kind == "offer":
		_career_state["offer"] = false  # Angebot nur einmal zeigen
		OrbitCareer.save_state(_career_state)
	else:
		(load(ORBIT_TUTORIAL_SCRIPT) as GDScript).mark_seen()
	if _orbit_hint == null:
		return
	var p := _orbit_hint
	_orbit_hint = null
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 0.0, 0.18)
	tw.tween_callback(p.queue_free)


func _start_orbit_tutorial() -> void:
	(load(ORBIT_TUTORIAL_SCRIPT) as GDScript).mark_seen()
	_preview.stop()
	SceneFader.go(ORBIT_TUTORIAL_SCENE)


## Harness --shot-orbit-hint [--shot-out=<ordner>]: Wechsel Mania -> Orbit,
## Hinweis de und en fotografieren.
## Speichert den Browser-Zustand nicht (Modus des Nutzers bleibt).
func _shot_orbit_hint() -> void:
	_state_ready = false
	_play_mode = "mania"
	_orbit_hint_force = true
	_set_play_mode("orbit")
	var dir := OS.get_user_data_dir()
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-out="):
			dir = a.trim_prefix("--shot-out=")
	# Beide Sprachen in einem Lauf: Hinweis je Sprache neu bauen.
	for lang in ["de", "en"]:
		TranslationServer.set_locale(lang)
		if _orbit_hint != null:
			_orbit_hint.free()
			_orbit_hint = null
		_show_orbit_hint()
		await get_tree().create_timer(0.9).timeout
		await RenderingServer.frame_post_draw
		var out := dir.path_join("orbit_hint_%s.png" % lang)
		get_viewport().get_texture().get_image().save_png(out)
		print("SHOT gespeichert: " + out)
	get_tree().quit(0)


## Modus-Tag im Ranglisten-Kopf (Mania 4K = ACCENT, Orbit = ACCENT2).
func _style_lb_mode_tag(score_mode: String) -> void:
	if _lb_mode_tag == null:
		return
	var col := UiTheme.ACCENT2 if score_mode == ScoreStore.MODE_ORBIT else COL_ACCENT
	_lb_mode_tag.text = RuleMods.board_tag(score_mode).to_upper()   # Minen: "MANIA 4K · MINES"
	_lb_mode_tag.add_theme_color_override("font_color", col.lerp(COL_TEXT, 0.25))
	var box := _lb_mode_tag.get_parent() as PanelContainer
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.16)
	sb.border_color = Color(col, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	box.add_theme_stylebox_override("panel", sb)
	box.tooltip_text = RuleMods.board_text("tip") if RuleMods.is_mines_board(score_mode) 			else tr("Nur Scores im Modus %s") % ScoreStore.mode_label(score_mode)


## SV-Stufe: zwei Mini-Schalter Normal | Stark (Standard Stark) neben dem SV-Mod.
func _build_sv_level() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size = Vector2(62, 40)
	_sv_level_btns.clear()
	for lv in [SvMod.STRENGTH_NORMAL, SvMod.STRENGTH_STRONG]:
		var b := _make_toggle("Normal" if lv == SvMod.STRENGTH_NORMAL else "Stark", 11, 6)
		b.custom_minimum_size = Vector2(62, 19)
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "SV-Stufe: klassische Muster" if lv == SvMod.STRENGTH_NORMAL \
				else "SV-Stufe: Beat-Tanz mit Rücklauf und Sprüngen (Standard)"
		var level: int = lv
		b.pressed.connect(func(): _set_sv_level(level))
		box.add_child(b)
		_sv_level_btns.append(b)
	_restyle_sv_level()
	return box


func _set_sv_level(level: int) -> void:
	SvMod.strength = level
	_restyle_sv_level()
	if not _sv_enabled:
		_on_sv_toggled(true)  # Stufe waehlen schaltet SV ein
	if _state_ready:
		_save_browser_state()


func _restyle_sv_level() -> void:
	for i in _sv_level_btns.size():
		var lv := SvMod.STRENGTH_NORMAL if i == 0 else SvMod.STRENGTH_STRONG
		_apply_toggle(_sv_level_btns[i], lv == SvMod.strength and _sv_enabled)


func _restyle_mode_switch() -> void:
	for i in _mode_btns.size():
		_apply_toggle(_mode_btns[i], PLAY_MODES[i] == _play_mode)
	_apply_tutorial_btn()


func _on_play_pressed() -> void:
	if _selected_set == null:
		return
	GameSession.mods = _current_mods()
	GameSession.is_replay = false
	GameSession.replay_events = []
	GameSession.replay_mode = "mania"
	GameSession.set_selection(
		_selected_set.osz_path, _selected_diff,
		_selected_set.version_name_at(_selected_diff),
		_selected_set.osu_filename_at(_selected_diff),
		_selected_set.stars_at(_selected_diff))
	if not GameSession.perf_enabled:   # Messlauf veraendert den Startzustand nicht
		GameSession.save_last_played(_selected_set.osz_path, _selected_diff, _selected_set.background_file)
	_preview.stop()
	# Auto-Erkennung: Mania-Diffs (Mode 3) starten die 4K-Szene.
	var mode := int(_selected_set.meta_at(_selected_diff).get("mode", 0))
	if (mode == 3 or mode == 0) and _play_mode != "mania":
		# Orbit/Rally/Dirigent spielen 4K-Mania und osu!standard (eigene Szene je Modus).
		if not ScoreStore.mode_ready(_play_mode):
			_apply_play_state()
			return
		_change_to_game(ScoreStore.mode_scene(_play_mode))
	elif mode == 3:
		_change_to_game("res://scenes/mania_3d.tscn")
	else:
		_change_to_game("res://scenes/gameplay_3d.tscn")


## Orbit-Mod-Schalter im Stil der NF/SV-Schalter.
func _make_orbit_mod_button(key: String) -> CheckButton:
	var b := CheckButton.new()
	b.text = key
	b.tooltip_text = str(ORBIT_MOD_TIPS.get(key, ""))  # Trace-Mods (MR/SS) setzen ihren Tipp selbst
	b.focus_mode = Control.FOCUS_NONE
	b.button_pressed = bool(_orbit_mods.get(key, false))
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 14)
	var box := _toggle_box(false, 10)
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("pressed", box)
	b.add_theme_stylebox_override("hover", _toggle_box(false, 10, true))
	b.add_theme_stylebox_override("hover_pressed", _toggle_box(false, 10, true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for fc in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(fc, COL_TEXT)
	UiTheme._attach_sounds(b)
	b.toggled.connect(func(on: bool): _on_orbit_mod_toggled(key, on))
	return b


## Trace-Mod-Schalter (MR/HD/SS) im Stil der NF/SV-Schalter.
func _make_trace_mod_button(key: String) -> CheckButton:
	var b := _make_orbit_mod_button(key)
	b.tooltip_text = TRACE_MOD_TIPS[key]
	b.button_pressed = bool(_trace_mods.get(key, false))
	for c in b.toggled.get_connections():
		b.toggled.disconnect(c["callable"])
	b.toggled.connect(func(on: bool): _on_trace_mod_toggled(key, on))
	return b


## Regel-Mod-Schalter (SD/PF/MN) im Stil der NF/SV-Schalter.
func _make_rule_mod_button(key: String) -> CheckButton:
	var b := _make_orbit_mod_button(key)
	b.text = RuleMods.label(key)
	b.tooltip_text = RuleMods.tip(key)
	b.button_pressed = bool(_rule_mods.get(key, false))
	for c in b.toggled.get_connections():
		b.toggled.disconnect(c["callable"])
	b.toggled.connect(func(on: bool): _on_rule_mod_toggled(key, on))
	return b


## SD und PF schliessen einander und No-Fail aus.
func _on_rule_mod_toggled(key: String, on: bool) -> void:
	_rule_mods = RuleMods.toggle(_rule_mods, key, on)
	if on and RuleMods.clears_nf(key) and _nf_enabled:
		_on_nf_toggled(false)
	_sync_rule_mod_buttons()
	if key == RuleMods.MN and _selected_set != null:
		_update_info_panel()   # BESTE SCORES: Minen-Liste bzw. normale Liste
	if _state_ready:
		_save_browser_state()


func _sync_rule_mod_buttons() -> void:
	for k in _rule_mod_btns:
		var b := _rule_mod_btns[k] as CheckButton
		b.visible = RuleMods.available(k, _play_mode)
		b.set_pressed_no_signal(bool(_rule_mods.get(k, false)))


func _on_trace_mod_toggled(key: String, on: bool) -> void:
	_trace_mods[key] = on
	if _state_ready:
		_save_browser_state()


func _on_orbit_mod_toggled(key: String, on: bool) -> void:
	_orbit_mods[key] = on
	# HD und FI zusammen liessen nur ein schmales Band sichtbar: einer von beiden.
	var other := "FI" if key == "HD" else ("HD" if key == "FI" else "")
	if on and other != "":
		_orbit_mods[other] = false
	for k in _orbit_mod_btns:
		(_orbit_mod_btns[k] as CheckButton).set_pressed_no_signal(bool(_orbit_mods[k]))
	if _state_ready:
		_save_browser_state()


## Mania zeigt SV (+ Stufe), Orbit stattdessen HD/FI/PR; No-Fail in beiden.
func _apply_mod_visibility() -> void:
	var orbit := _play_mode == "orbit"
	if _sv_btn != null:
		_sv_btn.visible = _play_mode == "mania"
	if _sv_level_box != null:
		_sv_level_box.visible = _play_mode == "mania"
	if _marathon_btn != null:
		_marathon_btn.visible = _play_mode == "mania"
	for k in _orbit_mod_btns:
		(_orbit_mod_btns[k] as CheckButton).visible = orbit
		(_orbit_mod_btns[k] as CheckButton).set_pressed_no_signal(bool(_orbit_mods[k]))
	for k in _trace_mod_btns:
		(_trace_mod_btns[k] as CheckButton).visible = _play_mode == "trace"
		(_trace_mod_btns[k] as CheckButton).set_pressed_no_signal(bool(_trace_mods[k]))
	_sync_rule_mod_buttons()
	TempoBrowserRow.set_visible(_play_mode == "mania")


func _on_sv_toggled(pressed: bool) -> void:
	_sv_enabled = pressed
	Settings.mod_sv = pressed
	Settings.save()
	if _sv_btn != null:
		_sv_btn.set_pressed_no_signal(_sv_enabled)
	_restyle_sv_level()


## Mods fuer den naechsten Start (Schnittstelle GameSession.mods): Grund-Mods des
## Modus plus Regel-Mods (SD/PF/MN, RuleMods.apply).
func _current_mods() -> Dictionary:
	return RuleMods.apply(_base_mods(), _rule_mods, _play_mode)


## Orbit: NF + Orbit-Mods (SV wirkt im Orbit nicht und zaehlt dort nicht).
func _base_mods() -> Dictionary:
	if _play_mode == "trace":
		var tm := {"NF": _nf_enabled}
		for k in TraceMods.MODS:
			tm[k] = bool(_trace_mods.get(k, false))
		return tm
	if _play_mode in ["rally", "dirigent", "rebound"]:
		return {"NF": _nf_enabled}
	if _play_mode == "orbit":
		var m := {"NF": _nf_enabled}
		for k in OrbitCore.ORBIT_MODS:
			m[k] = bool(_orbit_mods.get(k, false))
		return m
	return TempoBrowserRow.add_mods({"NF": _nf_enabled, "SV": _sv_enabled})


func _on_nf_toggled(pressed: bool) -> void:
	_nf_enabled = pressed
	Settings.mod_nf = pressed
	Settings.save()
	_update_nf_button()
	if pressed:
		_rule_mods = RuleMods.on_no_fail(_rule_mods)
		_sync_rule_mod_buttons()


func _update_nf_button() -> void:
	if _nf_btn == null:
		return
	_nf_btn.set_pressed_no_signal(_nf_enabled)


## Full-Res-Cover nachladen (nur wenn die Auswahl noch aktuell ist).
func _load_fullres_bg(target_set: MapSet) -> void:
	if _selected_set != target_set:
		return
	var tex := target_set.background_texture()
	if tex != null and _selected_set == target_set:
		_cover.texture = tex


## Gespeichertes Replay der gewaehlten Diff ansehen.
func _watch_replay() -> void:
	if _selected_set == null:
		return
	var orbit := _play_mode == "orbit" 		and int(_selected_set.meta_at(_selected_diff).get("mode", 0)) in [0, 3]
	var rg := _play_mode != "mania" and _play_mode != "orbit" 			and int(_selected_set.meta_at(_selected_diff).get("mode", 0)) in [0, 3]
	if rg and not ScoreStore.mode_ready(_play_mode):
		return
	var rmode := ReplayStore.best_mode_of(_play_mode) if (orbit or rg) else "mania"
	var data := ReplayStore.load_replay(_selected_set.osz_path,
		_selected_set.version_name_at(_selected_diff), rmode)
	if data.is_empty():
		return
	# Orbit-Replays tragen auch HD/FI/PR (sonst liefe die Wertung anders);
	# Trace/Rebound speichern Mania-Mods (SV/NF ...) wie Mania.
	var orbit_mods := (orbit or rg) and not _mania_like()
	GameSession.mods = OrbitCore.replay_mods(data) if orbit_mods else GameSession._replay_mods(data)
	GameSession.set_selection(
		_selected_set.osz_path, _selected_diff,
		_selected_set.version_name_at(_selected_diff),
		_selected_set.osu_filename_at(_selected_diff),
		_selected_set.stars_at(_selected_diff))
	GameSession.is_replay = true
	GameSession.replay_events = data.events
	GameSession.replay_mode = rmode
	GameSession.replay_end_ms = float(data.get("meta", {}).get("end_ms", -1.0))
	_preview.stop()
	_change_to_game(ScoreStore.mode_scene(_play_mode) if (orbit or rg) else "res://scenes/mania_3d.tscn")


## Marathon-Auswahl (MarathonPanel): Start bzw. Replay ueber die Spielszene.
func _open_marathon() -> void:
	if _library == null or get_node_or_null("MarathonPanel") != null:
		return
	var p := MarathonPanel.new()
	p.name = "MarathonPanel"
	add_child(p)
	var has_sel := _selected_set != null
	p.setup(_library.mapsets, _selected_set.osz_path if has_sel else "",
		_selected_set.stars_at(_selected_diff) if has_sel else 3.0, CollectionStore.list_for("mania"))
	p.start_requested.connect(func(plan: Dictionary) -> void:
		GameSession.mods = _current_mods()
		GameSession.is_replay = false
		GameSession.replay_events = []
		GameSession.replay_mode = "mania"
		MarathonRun.begin(plan)
		_preview.stop()
		_change_to_game("res://scenes/mania_3d.tscn"))
	p.replay_requested.connect(func(data: Dictionary) -> void:
		if MarathonRun.start_replay(data):
			_preview.stop()
			_change_to_game("res://scenes/mania_3d.tscn"))


## Max-pp (SS) der aktuellen Diff anzeigen; Berechnung laeuft im Thread,
## damit der Browser nie ruckelt. Ergebnis wird dauerhaft gecacht.
func _update_max_pp(m: Dictionary) -> void:
	if _selected_set == null:
		return
	# pp gibt es nur in Mania; Orbit/Rally/Dirigent werten ohne pp.
	if _play_mode != "mania":
		_maxpp_label.text = ""
		return
	var inner := _selected_set.osu_filename_at(_selected_diff)
	var cached := StarService.max_pp_cached(_selected_set.osz_path, inner)
	if cached >= 0.0:
		_maxpp_label.text = tr("Max. %s bei SS") % UiTheme.fmt_pp(cached)
		return
	if cached > -900.0:
		_maxpp_label.text = ""
		return
	_maxpp_label.text = "Max. pp wird berechnet …"
	if _maxpp_thread != null:
		return  # laeuft bereits — fertige Berechnung triggert Refresh
	var osz := _selected_set.osz_path
	var notes := int(m.get("notes", 0))
	_maxpp_thread = Thread.new()
	# Der Thread kennt nur die Instanz-ID: der Browser kann frei werden, waehrend er rechnet
	# (Start direkt nach der Auswahl, --mania/--rule-mods-Shots). Frueher griff das Lambda
	# auf das freigegebene self zu ("_on_maxpp_done" auf 'previously freed').
	_maxpp_thread.start(Callable(get_script(), "_maxpp_job").bind(
			get_script(), get_instance_id(), osz, inner, notes))


## Thread-Teil der Max-pp-Rechnung: statisch, ohne Zugriff auf den Browser.
static func _maxpp_job(script: Script, owner_id: int, osz: String, inner: String, notes: int) -> void:
	var v := StarService.max_pp_for(osz, inner, notes)
	Callable(script, "_maxpp_deliver").call_deferred(owner_id, osz, inner, v)


## Hauptthread: Ergebnis nur an einen noch lebenden Browser geben.
static func _maxpp_deliver(owner_id: int, osz: String, inner: String, v: float) -> void:
	var o: Object = instance_from_id(owner_id)
	if o != null and is_instance_valid(o) and o.has_method("_on_maxpp_done"):
		o.call("_on_maxpp_done", osz, inner, v)


func _on_maxpp_done(osz: String, inner: String, v: float) -> void:
	if _maxpp_thread != null:
		_maxpp_thread.wait_to_finish()
		_maxpp_thread = null
	if _selected_set == null or not is_inside_tree():
		return
	if _play_mode != "mania":
		_maxpp_label.text = ""
	elif _selected_set.osz_path == osz and _selected_set.osu_filename_at(_selected_diff) == inner:
		_maxpp_label.text = (tr("Max. %s bei SS") % UiTheme.fmt_pp(v)) if v >= 0.0 else ""
	else:
		# Auswahl hat gewechselt — fuer die neue Diff nachziehen.
		_update_max_pp(_selected_set.meta_at(_selected_diff))


func _on_sv_backfill_done() -> void:
	if is_inside_tree() and _search != null:
		_refresh_filter(_search.text)


func _exit_tree() -> void:
	if _import_job != null and _import_job.is_running():
		_import_job.cancel()
		_import_job.wait()
	if _library != null:
		_library.shutdown()
	if _maxpp_thread != null:
		_maxpp_thread.wait_to_finish()
		_maxpp_thread = null
	if _os_thread != null:
		_os_thread.wait_to_finish()
		_os_thread = null
	if _rec_thread != null:
		_rec_thread.wait_to_finish()
		_rec_thread = null
	_bg_queue.clear()
	if _bg_thread != null:
		_bg_thread.wait_to_finish()
		_bg_thread = null


func _play_preview() -> void:
	if _selected_set == null:
		return
	var m := _selected_set.meta_at(_selected_diff)
	var stream := OszImporter.load_audio_stream_named(
		_selected_set.osz_path, str(m.get("audio_filename", "")))
	if stream == null:
		_stop_preview_soft()
		return
	var song_key := SongLoudness.make_key(_selected_set.osz_path, str(m.get("audio_filename", "")))
	var preview_ms := float(m.get("preview_time", -1.0))
	if preview_ms < 0:
		preview_ms = float(m.get("duration_ms", 0.0)) * 0.4
	_switch_preview(stream, preview_ms / 1000.0, song_key)


## Klickfreier Wechsel: alte Vorschau 120 ms ausblenden, dann neue starten
## und 250 ms einblenden. Nie hart stoppen/starten, solange etwas klingt.
## song_key leer = keine Lautheitsmessung (Online-Vorschau).
func _switch_preview(stream: AudioStream, from_sec: float, song_key: String) -> void:
	if _preview_fade != null and _preview_fade.is_valid():
		_preview_fade.kill()
	_preview_fade = create_tween()
	if _preview.playing and _preview.volume_db > PREVIEW_SILENT_DB + 1.0:
		_preview_fade.tween_property(_preview, "volume_db", PREVIEW_SILENT_DB, PREVIEW_FADE_OUT)
	_preview_fade.tween_callback(_start_preview.bind(stream, from_sec, song_key))


func _start_preview(stream: AudioStream, from_sec: float, song_key: String) -> void:
	if not is_inside_tree():
		return
	_preview.stop()
	_preview.stream = stream
	_preview_len = stream.get_length()
	if song_key == "":
		SongLoudness.measure_stop()
		_preview_gain_db = 0.0
	else:
		_preview_gain_db = SongLoudness.gain_db_for(song_key)
		if is_equal_approx(_preview_gain_db, 0.0) and not SongLoudness.has_key(song_key):
			SongLoudness.measure_start(song_key)
		else:
			SongLoudness.measure_stop()
	if song_key == "":
		_preview_set = null
		_beat.setup([])
	else:
		_preview_set = _selected_set
		_setup_beat_clock()
	_preview.volume_db = PREVIEW_SILENT_DB
	_preview.play(from_sec)
	if _perf_select_t > 0:
		GameSession.perf_since("Map-Auswahl -> Vorschau-Ton", _perf_select_t)
		_perf_select_t = 0
	_preview_fade = create_tween()
	_preview_fade.tween_property(_preview, "volume_db", PREVIEW_DB + _preview_gain_db, PREVIEW_FADE_IN)


## Vorschau weich ausblenden und erst dann anhalten.
func _stop_preview_soft() -> void:
	if _preview_fade != null and _preview_fade.is_valid():
		_preview_fade.kill()
	if not _preview.playing:
		return
	_preview_fade = create_tween()
	_preview_fade.tween_property(_preview, "volume_db", PREVIEW_SILENT_DB, PREVIEW_FADE_OUT)
	_preview_fade.tween_callback(_preview.stop)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if _automap_check != null:
		return
	if event.keycode == KEY_ESCAPE:
		if _import_overlay != null:
			_close_import_panel()
			return
		if _online_open():
			_close_download_panel()
			return
		_preview.stop()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	if _online_open() or _import_overlay != null or event.echo:
		return
	# Tastatur-Navigation wie in osu: hoch/runter Map, links/rechts Diff,
	# Enter startet, F2 = Zufallsmap.
	match event.keycode:
		KEY_DOWN:
			_move_selection(1)
			get_viewport().set_input_as_handled()
		KEY_UP:
			_move_selection(-1)
			get_viewport().set_input_as_handled()
		KEY_LEFT:
			_cycle_difficulty(-1)
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_cycle_difficulty(1)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			_on_play_pressed()
			get_viewport().set_input_as_handled()
		KEY_F2:
			if _career_on():
				if not _career_items.is_empty():
					var ci: Dictionary = _career_items[randi() % _career_items.size()]
					_select_set(ci.ms, int(ci.diff))
			elif not _filtered.is_empty():
				var pick: MapSet = _filtered[randi() % _filtered.size()]
				_select_set(pick, _hardest(pick))
				_scroll_to_selected.call_deferred()
			get_viewport().set_input_as_handled()


func _move_selection(dir: int) -> void:
	if _career_on():
		_move_career_selection(dir)
		return
	if _filtered.is_empty():
		return
	var idx := _filtered.find(_selected_set)
	idx = clampi(idx + dir, 0, _filtered.size() - 1) if idx >= 0 else 0
	_select_set(_filtered[idx], _hardest(_filtered[idx]))
	_scroll_to_selected()


## Karriere: Pfeil hoch/runter geht durch die Vorschlaege.
func _move_career_selection(dir: int) -> void:
	if _career_items.is_empty():
		return
	var at := -1
	for i in _career_items.size():
		if _career_items[i].ms == _selected_set:
			at = i
	var n := clampi(at + dir, 0, _career_items.size() - 1) if at >= 0 else 0
	_select_set(_career_items[n].ms, int(_career_items[n].diff))


## Liste zur ausgewaehlten Karte scrollen (Auswahl bleibt immer sichtbar).
func _scroll_to_selected() -> void:
	var idx := _filtered.find(_selected_set)
	if idx < 0 or idx >= _card_buttons.size() or not is_instance_valid(_card_buttons[idx]):
		return
	var holder := _card_buttons[idx].get_parent().get_parent() as Control
	if holder.size.y <= 0.0:
		# Layout noch nicht fertig (erster Frame): einen Frame warten.
		await get_tree().process_frame
		if not is_instance_valid(holder):
			return
	# Ziel: Karte mittig im sichtbaren Bereich, weich eingeblendet.
	var top := holder.position.y + float(LIST_PAD)
	var target := top + holder.size.y * 0.5 - _scroll.size.y * 0.5
	var vbar := _scroll.get_v_scroll_bar()
	var max_v := maxf(vbar.max_value - vbar.page, 0.0)
	target = clampf(target, 0.0, max_v)
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_property(_scroll, "scroll_vertical", int(target), 0.30)


# ---------------------------------------------------------------------------
# Drag & Drop
# ---------------------------------------------------------------------------

func _on_files_dropped(files: PackedStringArray) -> void:
	_import_paths(files)


# ---------------------------------------------------------------------------
# Import (scripts/library/song_import.gd): Knopf, Dialog, osu!-Uebernahme,
# Drag & Drop. Ruhig: eine Akzentfarbe, Text statt Symbole.
# ---------------------------------------------------------------------------

const LAZER_NOTE := "osu!lazer wird nicht unterstützt: lazer speichert Maps nicht als Ordner. Exportiere sie dort als .osz und wähle die Dateien oben."

var _import_btn: Button
var _import_job: SongImport = null
var _import_overlay: Control = null
var _import_prog_box: VBoxContainer
var _import_prog_label: Label = null
var _import_prog_bar: ProgressBar
var _import_cancel_btn: Button
var _import_osu_note: Label
var _import_files_btn: Button
var _import_osu_btn: Button
var _import_notice: PanelContainer = null
var _import_notice_label: Label
var _import_notice_tween: Tween
var _import_pending_notes: Array[String] = []


## Gemischte Pfade (Datei-Dialog, Drop): .osz und Map-Ordner im Thread,
## Audio ueber SongImport.import_audio, Rest -> Hinweis "nicht unterstuetzt".
func _import_paths(paths: PackedStringArray) -> void:
	var c := SongImport.classify(paths)
	var notes: Array[String] = []
	if not c.unsupported.is_empty():
		if c.unsupported.size() == 1:
			notes.append(tr("Nicht unterstützt: %s") % String(c.unsupported[0]).get_file())
		else:
			notes.append(tr("%d Dateien nicht unterstützt") % c.unsupported.size())
	if c.osz.is_empty() and c.folders.is_empty() and c.audio.is_empty():
		if notes.is_empty():
			notes.append(tr("Nicht unterstützt"))
		_show_import_notice("  ·  ".join(notes), false)
		return
	if _start_import_job(c.folders, c.osz, c.audio):
		_import_pending_notes = notes


func _start_import_job(folders: Array, osz_files: Array, audio_files: Array = [], audio_opts: Dictionary = {}) -> bool:
	if _import_job != null and _import_job.is_running():
		_show_import_notice(tr("Import läuft schon"), false)
		return false
	_import_pending_notes = []
	_import_job = SongImport.new()
	_import_job.audio_opts = audio_opts
	_import_job.progress.connect(_on_import_progress)
	_import_job.stage.connect(_on_import_stage)
	_import_job.finished.connect(_on_import_finished)
	_import_job.start(folders, osz_files, _library.maps_dir, audio_files)
	_set_import_busy(true)
	_on_import_progress(0, folders.size() + osz_files.size() + audio_files.size(), SongImport.PHASE_COPY)
	return true


func _import_progress_text(done: int, total: int, phase: String) -> String:
	if phase == SongImport.PHASE_ANALYSE:
		return tr("Bibliothek wird aktualisiert  %d / %d") % [done, total]
	return tr("Maps werden übernommen  %d / %d") % [done, total]


func _on_import_progress(done: int, total: int, phase: String) -> void:
	var txt := _import_progress_text(done, total, phase)
	if _import_prog_label != null:
		_import_prog_label.text = txt
		_import_prog_bar.max_value = maxi(total, 1)
		_import_prog_bar.value = done
	else:
		_show_import_notice(txt, true, 0.0)


# ---------------------------------------------------------------------------
# Eigene Musik -> 4K-Set (AutoMapper4K): Fortschritt, "Takt pruefen",
# Ordner "own songs". Texte: translations/automap.csv.
# ---------------------------------------------------------------------------

const AUTOMAP_STAGES := {
	"decode": "Decoding audio", "grid": "Finding the beat", "features": "Listening to the music",
	"chart": "Placing notes", "write": "Writing the set", "done": "Writing the set",
}

var _automap_check: AutomapCheck = null
var _own_offer: PanelContainer = null


## Fortschritt der Erzeugung: Song, Stufe und Prozent.
func _on_import_stage(song: String, stage_name: String, frac: float) -> void:
	var txt := "%s  ·  %s  %d %%" % [song, tr(str(AUTOMAP_STAGES.get(stage_name, stage_name))), int(round(frac * 100.0))]
	if _import_prog_label != null:
		_import_prog_label.text = txt
		_import_prog_bar.max_value = 1.0
		_import_prog_bar.value = frac
	else:
		_show_import_notice(txt, true, 0.0)


## Schritt "Takt pruefen" fuer ein gerade erzeugtes Set (nur eigene Musik).
func _open_automap_check(info: Dictionary) -> void:
	if _automap_check != null:
		_automap_check.queue_free()
	if _import_overlay != null:
		_close_import_panel()
	_preview.stop()
	_automap_check = AutomapCheck.open(self, info)
	_automap_check.closed.connect(func():
		_automap_check = null
		_play_preview())
	_automap_check.regenerate.connect(func(opts: Dictionary):
		_automap_check.queue_free()
		_automap_check = null
		_start_import_job([], [], [str(info.get("audio_path", ""))], opts))


## Einmalig beim Start: Musik im Ordner "own songs" anbieten, die noch nie
## angeboten wurde. Antwort (erzeugen oder nicht) wird gemerkt.
func _offer_own_songs() -> void:
	var pending := SongImport.pending_own_songs(SongImport.own_songs_dir())
	if pending.is_empty() or _own_offer != null:
		return
	_own_offer = PanelContainer.new()
	var sb := UiTheme.solid_box(UiTheme.SURFACE, 10)
	sb.set_border_width_all(1)
	sb.border_color = Color(COL_ACCENT, 0.55)
	sb.content_margin_left = 18
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_own_offer.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_own_offer.add_child(row)
	var text := tr("%d songs in “own songs” have no map yet") % pending.size()
	if pending.size() == 1:
		text = tr("1 song in “own songs” has no map yet")
	var l := _add_label(row, text, 14, COL_TEXT)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	var done := func(create: bool):
		SongImport.mark_own_songs(pending)
		_own_offer.queue_free()
		_own_offer = null
		if create:
			_start_import_job([], [], pending)
	var later := Button.new()
	later.text = tr("Not now")
	later.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	later.custom_minimum_size = Vector2(0, 34)
	UiTheme.style_ghost_button(later, 10)
	later.pressed.connect(done.bind(false))
	row.add_child(later)
	var go := Button.new()
	go.text = tr("Create 4K maps")
	go.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	go.custom_minimum_size = Vector2(0, 34)
	UiTheme.style_button(go, true, 10)
	go.pressed.connect(done.bind(true))
	row.add_child(go)
	# Unten rechts ueber der Liste: verdeckt weder die Aktionen links noch den Import-Hinweis.
	_own_offer.anchor_left = 1.0
	_own_offer.anchor_right = 1.0
	_own_offer.anchor_top = 1.0
	_own_offer.anchor_bottom = 1.0
	_own_offer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_own_offer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_own_offer.offset_left = -24
	_own_offer.offset_right = -24
	_own_offer.offset_bottom = -24
	_own_offer.offset_top = -24
	add_child(_own_offer)


func _on_import_finished(res: Dictionary) -> void:
	var imported: Array = res.get("imported", [])
	var last := ""
	var orbit_only := 0
	if not imported.is_empty():
		# Cache ist im Thread vorgebaut (MapLibrary.prebuild): scan liest nur noch.
		_library.scan()
		_refresh_filter(_search.text)
		last = String(imported[imported.size() - 1])
		for ms in _library.mapsets:
			if imported.has(ms.osz_path) and ms.visible_diffs("mania").is_empty():
				orbit_only += 1
	var parts: Array[String] = []
	if bool(res.get("cancelled", false)):
		parts.append(tr("Abgebrochen"))
	if imported.size() == 1:
		parts.append(tr("1 Map importiert"))
	else:
		parts.append(tr("%d Maps importiert") % imported.size())
	if int(res.get("dup", 0)) > 0:
		parts.append(tr("%d schon vorhanden") % int(res.dup))
	if int(res.get("skipped", 0)) > 0:
		parts.append(tr("%d ohne 4K oder Standard") % int(res.skipped))
	if int(res.get("failed", 0)) > 0:
		parts.append(tr("%d fehlgeschlagen") % int(res.failed))
	for e in res.get("errors", []):
		if str(e) == AutoMapper4K.ERR_NO_FFMPEG:
			parts.append(tr("ffmpeg is missing, so music cannot be analysed"))
			break
	if orbit_only > 0 and _mania_like():
		parts.append(tr("%d nur im Orbit-Modus") % orbit_only)
	parts.append_array(_import_pending_notes)
	_import_pending_notes = []
	var summary := "  ·  ".join(parts)
	_set_import_busy(false)
	if _import_prog_label != null:
		_import_prog_label.text = summary
		_import_prog_bar.max_value = 1
		_import_prog_bar.value = 1
	else:
		_show_import_notice(summary, not imported.is_empty())
	if last != "":
		for ms in _filtered:
			if ms.osz_path == last:
				_select_set(ms, _easiest(ms))
				break
	var auto: Array = res.get("auto", [])
	if not auto.is_empty() and not bool(res.get("cancelled", false)):
		_open_automap_check(auto[auto.size() - 1])


func _set_import_busy(busy: bool) -> void:
	if _import_btn != null:
		_import_btn.disabled = busy
	if _import_overlay == null:
		return
	_import_files_btn.disabled = busy
	_import_osu_btn.disabled = busy
	if busy:
		_import_prog_box.visible = true
	_import_cancel_btn.text = tr("Abbrechen") if busy else tr("Fertig")


## Kurzer Hinweis unten mittig. hold = 0: bleibt stehen (Fortschritt).
func _show_import_notice(text: String, good: bool, hold: float = 3.2) -> void:
	if _import_notice == null:
		_import_notice = PanelContainer.new()
		_import_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := UiTheme.solid_box(UiTheme.SURFACE, 10)
		sb.set_border_width_all(1)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		_import_notice.add_theme_stylebox_override("panel", sb)
		_import_notice_label = Label.new()
		_import_notice_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_import_notice_label.add_theme_font_size_override("font_size", 14)
		_import_notice.add_child(_import_notice_label)
		_import_notice.anchor_left = 0.5
		_import_notice.anchor_right = 0.5
		_import_notice.anchor_top = 1.0
		_import_notice.anchor_bottom = 1.0
		_import_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_import_notice.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_import_notice.offset_bottom = -28
		add_child(_import_notice)
	var sbx := _import_notice.get_theme_stylebox("panel") as StyleBoxFlat
	sbx.border_color = Color(COL_ACCENT, 0.55) if good else UiTheme.LINE
	_import_notice_label.text = text
	_import_notice_label.add_theme_color_override("font_color", COL_TEXT if good else COL_DIM)
	_import_notice.offset_left = 0
	_import_notice.offset_right = 0
	_import_notice.offset_top = -28
	_import_notice.visible = true
	_import_notice.modulate.a = 1.0
	move_child(_import_notice, get_child_count() - 1)
	if _import_notice_tween != null:
		_import_notice_tween.kill()
		_import_notice_tween = null
	if hold > 0.0:
		_import_notice_tween = create_tween()
		_import_notice_tween.tween_interval(hold)
		_import_notice_tween.tween_property(_import_notice, "modulate:a", 0.0, 0.4)
		_import_notice_tween.tween_callback(func(): _import_notice.visible = false)


## Import-Fenster: Dateien waehlen oder aus osu! uebernehmen, darunter Fortschritt.
func _open_import_panel() -> void:
	if _import_overlay != null:
		return
	if _import_notice != null:
		_import_notice.visible = false
	_stop_preview_soft()
	_import_overlay = UiTheme.modal_backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_import_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	var pb := UiTheme.solid_box(UiTheme.SURFACE, 14)
	pb.set_border_width_all(1)
	pb.border_color = UiTheme.LINE
	pb.content_margin_left = 28
	pb.content_margin_right = 28
	pb.content_margin_top = 24
	pb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", pb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	vb.add_child(UiTheme.modal_header("Songs importieren", _close_import_panel))

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 18)
	vb.add_child(actions)
	_import_files_btn = _import_row(actions, "Dateien wählen",
		tr("osu!-Maps (.osz) oder eigene Musik (.mp3, .ogg, .wav). Mehrere auf einmal gehen."))
	_import_files_btn.pressed.connect(_open_import_file_dialog)
	var osu_dir := SongImport.find_stable_songs_dir()
	var osu_sub := tr("Gefunden: %s") % osu_dir if osu_dir != "" else tr("osu! nicht gefunden. Du wählst den Songs-Ordner selbst.")
	_import_osu_btn = _import_row(actions, "Aus osu! übernehmen",
		osu_sub + "\n" + tr("Nur 4K-Mania und osu!standard, schon vorhandene Maps bleiben, wie sie sind."))
	_import_osu_btn.pressed.connect(_import_from_osu)
	_import_osu_note = _add_label(actions, "", 13, UiTheme.BAD)
	_import_osu_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_import_osu_note.visible = false
	if osu_dir == "" and SongImport.find_lazer_dir() != "":
		_import_osu_note.text = tr(LAZER_NOTE)
		_import_osu_note.visible = true
	vb.add_child(UiTheme.hairline())
	var tip := _add_label(vb, "Dateien und Ordner kannst du auch einfach ins Fenster ziehen.", 13, COL_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_import_prog_box = VBoxContainer.new()
	_import_prog_box.add_theme_constant_override("separation", 10)
	_import_prog_box.visible = false
	vb.add_child(_import_prog_box)
	_import_prog_label = _add_label(_import_prog_box, "", 15, COL_TEXT)
	_import_prog_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_import_prog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_import_prog_bar = ProgressBar.new()
	_import_prog_bar.show_percentage = false
	_import_prog_bar.custom_minimum_size = Vector2(0, 4)
	_import_prog_bar.add_theme_stylebox_override("background", UiTheme.solid_box(UiTheme.RAISED, 2))
	_import_prog_bar.add_theme_stylebox_override("fill", UiTheme.solid_box(COL_ACCENT, 2))
	_import_prog_box.add_child(_import_prog_bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	_import_prog_box.add_child(row)
	_import_cancel_btn = Button.new()
	_import_cancel_btn.text = "Abbrechen"
	_import_cancel_btn.custom_minimum_size = Vector2(120, 36)
	UiTheme.style_ghost_button(_import_cancel_btn, 10)
	_import_cancel_btn.pressed.connect(func():
		if _import_job != null and _import_job.is_running():
			_import_job.cancel()
			_import_prog_label.text = tr("Wird abgebrochen …")
		else:
			_close_import_panel())
	row.add_child(_import_cancel_btn)
	if _import_job != null and _import_job.is_running():
		_set_import_busy(true)
		_on_import_progress(_import_job.done, _import_job.total, _import_job.phase)


## Eine Aktion: Knopf links, Erklaerung (schon uebersetzt) darunter in DIM.
func _import_row(parent: Node, label: String, sub: String) -> Button:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 42)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", 15)
	UiTheme.style_button(b, false, 10)
	col.add_child(b)
	var l := _add_label(col, sub, 13, COL_DIM)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return b


func _close_import_panel() -> void:
	if _import_overlay == null:
		return
	_import_overlay.queue_free()
	_import_overlay = null
	_import_prog_label = null
	if _import_job != null and _import_job.is_running():
		_on_import_progress(_import_job.done, _import_job.total, _import_job.phase)
	_play_preview()


func _make_import_dialog(mode: FileDialog.FileMode, title: String) -> FileDialog:
	var fd := FileDialog.new()
	fd.file_mode = mode
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = tr(title)
	fd.use_native_dialog = true
	fd.min_size = Vector2i(820, 520)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	return fd


func _open_import_file_dialog() -> void:
	var fd := _make_import_dialog(FileDialog.FILE_MODE_OPEN_FILES, "Maps oder Musik wählen")
	fd.filters = PackedStringArray([
		"*.osz, *.mp3, *.ogg, *.wav ; " + tr("Maps und Musik"),
		"*.osz ; " + tr("osu!-Maps"),
		"*.mp3, *.ogg, *.wav ; " + tr("Musik"),
	])
	fd.files_selected.connect(func(paths: PackedStringArray):
		fd.queue_free()
		_import_paths(paths))
	fd.popup_centered()


## osu!stable-Songs-Ordner uebernehmen; nicht gefunden -> Ordner waehlen.
func _import_from_osu() -> void:
	var dir := SongImport.find_stable_songs_dir()
	if dir != "":
		_import_from_folder(dir)
		return
	var fd := _make_import_dialog(FileDialog.FILE_MODE_OPEN_DIR, "osu!-Songs-Ordner wählen")
	fd.dir_selected.connect(func(p: String):
		fd.queue_free()
		_import_from_folder(p))
	fd.popup_centered()


func _import_from_folder(dir: String) -> void:
	dir = dir.replace("\\", "/")
	if SongImport.is_lazer_dir(dir):
		_import_osu_note.text = tr(LAZER_NOTE)
		_import_osu_note.visible = true
		return
	var folders := SongImport.list_map_folders(dir)
	if folders.is_empty():
		_import_osu_note.text = tr("In diesem Ordner liegen keine osu!-Maps.")
		_import_osu_note.visible = true
		return
	_import_osu_note.visible = false
	_start_import_job(folders, [])


## Harness: Import-Fenster mit laufendem Fortschritt (beide Sprachen) und
## Drop-Hinweis als PNGs. Kein echter Import.
func _shot_import() -> void:
	_state_ready = false
	var dir := OS.get_user_data_dir()
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-out="):
			dir = a.trim_prefix("--shot-out=")
	for lang in ["de", "en"]:
		TranslationServer.set_locale(lang)
		_close_import_panel()
		await get_tree().process_frame
		_open_import_panel()
		_import_prog_box.visible = true
		_import_files_btn.disabled = true
		_import_osu_btn.disabled = true
		_import_cancel_btn.text = tr("Abbrechen")
		_on_import_progress(12, 340, SongImport.PHASE_COPY)
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var out := dir.path_join("import_%s.png" % lang)
		get_viewport().get_texture().get_image().save_png(out)
		print("SHOT gespeichert: " + out)
	_close_import_panel()
	_show_import_notice(tr("%d Maps importiert") % 3 + "  ·  " + tr("%d schon vorhanden") % 2, true, 0.0)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var out2 := dir.path_join("import_notice.png")
	get_viewport().get_texture().get_image().save_png(out2)
	print("SHOT gespeichert: " + out2)
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# Online-Tab (scripts/ui/online_browser.gd)
# ---------------------------------------------------------------------------

## Online-Browser anlegen (unsichtbar): Suche, Vorhoeren und Download laufen
## ueber ihn, auch fuer die Online-Vorschlaege in "For you".
func _ensure_online() -> void:
	if _online != null:
		return
	_online = OnlineBrowser.new(_library)
	_online.visible = false
	add_child(_online)
	_online.preview_stream.connect(func(st: AudioStream): _switch_preview(st, 0.0, ""))
	_online.preview_stop.connect(_stop_preview_soft)
	_online.preview_stop.connect(_rec_mark_preview)
	_online.map_downloaded.connect(_on_online_downloaded)
	_online.closed.connect(_on_online_closed)
	_online.quiet_done.connect(_on_rec_online)


func _open_download_panel() -> void:
	_ensure_online()
	_stop_preview_soft()
	_online.open()


func _close_download_panel() -> void:
	if _online != null:
		_online.close()


func _online_open() -> bool:
	return _online != null and _online.visible


## Online-Tab zu: Vorschau der gewaehlten Map wieder aufnehmen.
func _on_online_closed() -> void:
	_play_preview()


## Download fertig: Bibliothek neu scannen, damit die Map sofort im Tab
## "Heruntergeladen" steht; Einzel-Downloads direkt anwaehlen (Pack nicht).
func _on_online_downloaded(_set_id: int, osz_path: String, select: bool) -> void:
	_library.scan()
	_refresh_filter(_search.text)
	if _career_on():
		_career_refresh()
	_career_start()
	_recs_refresh()
	if not select:
		return
	for ms in _filtered:
		if ms.osz_path == osz_path:
			_select_set(ms, _hardest(ms))
			break


# ---------------------------------------------------------------------------
# Style-Helfer
# ---------------------------------------------------------------------------

func _rounded_box(bg: Color, radius: int, border_col: Color = Color.TRANSPARENT, border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_col
	return sb


func _card_box(bg: Color, accent: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(CARD_RADIUS)
	if accent.a > 0.0:
		sb.border_width_left = 4
		sb.border_color = accent
	sb.anti_aliasing = true
	sb.set_content_margin_all(6)
	return sb


func _add_label(parent: Node, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _icon_button(icon: Texture2D, tip: String) -> Button:
	var b := Button.new()
	b.icon = icon
	b.tooltip_text = tip
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(40, 36)
	b.focus_mode = Control.FOCUS_NONE
	UiTheme.style_ghost_button(b, 10)
	_square_margins(b)
	b.add_theme_color_override("icon_normal_color", COL_DIM)
	b.add_theme_color_override("icon_hover_color", COL_TEXT)
	b.add_theme_color_override("icon_pressed_color", COL_ACCENT)
	return b


## osu-aehnliche Farbskala fuer Star Rating (nur Anzeige).
func _star_color(stars: float) -> Color:
	if stars < 0.0:
		return Color(0.5, 0.5, 0.55)
	var stops: Array = [
		[0.0, Color(0.31, 0.75, 1.0)], [2.0, Color(0.31, 1.0, 0.84)],
		[2.7, Color(0.49, 1.0, 0.31)], [3.3, Color(0.96, 0.94, 0.36)],
		[4.2, Color(1.0, 0.50, 0.41)], [4.9, Color(1.0, 0.31, 0.44)],
		[5.8, Color(0.78, 0.27, 0.72)], [6.7, Color(0.40, 0.39, 0.87)],
		[8.0, Color(0.15, 0.13, 0.56)],
	]
	for i in range(stops.size() - 1):
		if stars <= stops[i + 1][0]:
			var k: float = (stars - stops[i][0]) / (stops[i + 1][0] - stops[i][0])
			return (stops[i][1] as Color).lerp(stops[i + 1][1], clampf(k, 0.0, 1.0))
	return stops[stops.size() - 1][1]


# ---------------------------------------------------------------------------
# Orbit-Karriere (Logik: scripts/orbit/orbit_career.gd, Panel: scripts/ui/orbit_career_panel.gd)
# ---------------------------------------------------------------------------

## Hintergrund-Nachrechnung fehlender Orbit-Sterne: ein Thread, eine Diff nach
## der anderen mit Pause, hoechstens BG_BUDGET pro Besuch, niedrige Prioritaet.
const BG_BUDGET := 240
const BG_PAUSE := 0.4
var _os_cache: Dictionary = {}
var _os_cache_loaded := false
var _okey_cache: Dictionary = {}
var _bg_queue: Array = []        # {key, osz, ver}
var _bg_queued: Dictionary = {}  # key -> true (steht in der Warteschlange)
var _bg_failed: Dictionary = {}
var _bg_thread: Thread
var _bg_spent := 0


func _career_on() -> bool:
	return _play_mode == "orbit" and str(_career_state.get("mode", "")) == OrbitCareer.MODE_CAREER


## Reihe unter der Kopfzeile: Umschalter Karriere | Frei, rechts der Hinweis.
func _build_career_row() -> void:
	_career_row = HBoxContainer.new()
	_career_row.custom_minimum_size = Vector2(0, CHIPS_H)
	_career_row.add_theme_constant_override("separation", 6)
	_career_row.visible = false
	_filter_stack.add_child(_career_row)
	for m in [OrbitCareer.MODE_CAREER, OrbitCareer.MODE_FREE]:
		var is_career: bool = m == OrbitCareer.MODE_CAREER
		var b := _make_toggle(tr("Karriere") if is_career else tr("Frei"), 13, 15)
		b.custom_minimum_size = Vector2(0, CHIPS_H)
		b.tooltip_text = tr("Schlägt passende Maps vor und steigert die Schwierigkeit mit dir") if is_career \
				else tr("Alle Maps, empfohlene sind markiert")
		b.pressed.connect(_set_career_mode.bind(m))
		_career_row.add_child(b)
		_career_btns.append(b)
	_career_level_lbl = Label.new()
	_career_level_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_career_level_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_career_level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_career_level_lbl.add_theme_font_size_override("font_size", 13)
	_career_level_lbl.add_theme_color_override("font_color", COL_DIM)
	_career_row.add_child(_career_level_lbl)


func _build_career_panel() -> void:
	_career_panel = OrbitCareerPanel.new()
	_career_panel.anchor_left = 1.0
	_career_panel.anchor_right = 1.0
	_career_panel.anchor_bottom = 1.0
	_career_panel.offset_left = -M - RIGHT_W
	_career_panel.offset_right = -M
	_career_panel.offset_bottom = -M
	_career_panel.visible = false
	_career_panel.picked.connect(_on_career_picked)
	_career_panel.online_requested.connect(_career_online)
	add_child(_career_panel)


## Listen-Oberkante = echte Unterkante der Filter-Reihen (auch wenn eine Reihe
## hoeher wird oder eine dazukommt).
func _update_list_top() -> void:
	if _filter_stack == null or _list_mask == null:
		return
	var top := FILTER_Y + _filter_stack.get_combined_minimum_size().y
	_list_mask.offset_top = top
	if _career_panel != null:
		_career_panel.offset_top = top + 12.0


func _apply_career_layout() -> void:
	if _career_row == null or _filter_row == null:
		return
	var orbit := _play_mode == "orbit"
	var career := _career_on()
	_career_row.visible = orbit
	for i in _career_btns.size():
		_apply_toggle(_career_btns[i], (i == 0) == (str(_career_state.get("mode", "")) == OrbitCareer.MODE_CAREER))
	_career_level_lbl.visible = orbit and not career
	_career_level_lbl.text = tr("Empfohlen: %s ★") % OrbitCareer.range_text(float(_career_state.get("level", OrbitCareer.START_LEVEL)))
	_filter_row.visible = not career
	# Sammlungs-Ansicht: Filter, die dort nicht gelten, gar nicht erst zeigen.
	_score_chips_row.visible = not career and not _collection_mode
	for sc in _star_chips:
		sc.visible = not _collection_mode
	if _sv_chip != null:
		_sv_chip.visible = not _collection_mode
	_chips_row.visible = _collection_mode and not career
	if _list_mask != null:
		_list_mask.visible = not career
	if _career_panel != null:
		_career_panel.visible = career
	_apply_recs_visibility()
	_update_list_top()
	if career:
		_career_refresh()
	else:
		_career_items = []
		_refresh_recommended()


func _set_career_mode(m: String) -> void:
	if str(_career_state.get("mode", "")) == m and bool(_career_state.get("chosen", false)):
		return
	_career_state["mode"] = m
	_career_state["chosen"] = true
	_career_state["offer"] = false
	OrbitCareer.save_state(_career_state)
	if _hint_kind == "offer" and _orbit_hint != null:
		_orbit_hint.queue_free()
		_orbit_hint = null
	_apply_career_layout()
	_career_start()
	_recs_refresh()


func _accept_career_offer() -> void:
	_set_career_mode(OrbitCareer.MODE_CAREER)


## Nach Moduswechsel/Start: Angebot nach dem Tutorial zeigen, fehlende Sterne rechnen.
func _career_start() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_bg_scan()  # fehlende Modus-Sterne (alle Modi ausser Mania/Rebound)
	_bg_pump()
	if _play_mode != "orbit":
		return
	if bool(_career_state.get("offer", false)) and _orbit_hint == null:
		_show_orbit_hint()


func _on_career_picked(ms: MapSet, diff: int) -> void:
	if _selected_set == ms and _selected_diff == diff:
		_on_play_pressed()
		return
	_select_set(ms, diff)


## Online-Suche mit dem Sterne-Filter, der die Stufe abdeckt.
func _career_online() -> void:
	_open_download_panel()
	if _online != null:
		_online.call("_set_star_filter", OrbitCareer.online_star_filter(float(_career_state.get("level", OrbitCareer.START_LEVEL))))


func _os_cache_get() -> Dictionary:
	if not _os_cache_loaded:
		_os_cache = orbit_stars_cache_all()
		_os_cache_loaded = true
	return _os_cache


## Modus, dessen Sterne gerade gezeigt werden (Mania zeigt Orbit-Sterne nur intern).
func _stars_mode() -> String:
	return "orbit" if _play_mode == "mania" else _play_mode


# ---------------------------------------------------------------------------
# Modus-Sterne im Browser: Diff-Leiste, Pfeile, Standard-Auswahl, Kartenliste,
# Sterne-Filter, Sortierung und Empfehlungen nutzen die Sterne des aktiven Modus.
# Fehlende rechnet der Hintergrund-Thread (_bg_*), bis dahin zaehlen vorlaeufig
# die Mania-Sterne; neue Werte sortieren entprellt nach (_resort_later).
# ---------------------------------------------------------------------------

const RESORT_DELAY := 2.0
var _trace_cache: Dictionary = {}
var _trace_cache_loaded := false
var _tbase: Dictionary = {}       # osz_path -> StarService._cache_key
var _front_token := 0
var _resort_due := false


## Sternquelle je Modus: "mania" (Mania, Rebound: Mania-Sterne), "trace"
## (TraceStars ueber StarService), sonst der Modus selbst (Orbit, Rally,
## Dirigent: orbit_stars.cfg).
static func star_src(play_mode: String) -> String:
	if play_mode == "" or play_mode == "mania" or play_mode == "rebound":
		return "mania"
	return play_mode


func _star_src() -> String:
	return star_src(_play_mode)


func _trace_cache_get() -> Dictionary:
	if not _trace_cache_loaded:
		_trace_cache_loaded = true
		var cfg := ConfigFile.new()
		if cfg.load(StarService.CACHE_PATH) == OK and cfg.has_section("trace_stars"):
			for k in cfg.get_section_keys("trace_stars"):
				_trace_cache[k] = float(cfg.get_value("trace_stars", k, -1.0))
	return _trace_cache


## Cache-Schluessel der Modus-Sterne einer Diff ("" = Mania-Sterne/kein Cache).
func _mode_star_key(ms: MapSet, i: int) -> String:
	var src := _star_src()
	if src == "mania":
		return ""
	if src == "trace":
		if not _tbase.has(ms.osz_path):
			_tbase[ms.osz_path] = StarService._cache_key(ms.osz_path)
		var base: String = _tbase[ms.osz_path]
		var inner := ms.osu_filename_at(i)
		return "" if base == "" or inner == "" else StarService._trace_key(base, inner)
	return _mkey(ms, ms.version_name_at(i), src)


## Modus-Sterne einer Diff; -1 = noch nicht berechnet (Mania/Rebound: Mania-Sterne).
func _mode_stars_known(ms: MapSet, i: int) -> float:
	var src := _star_src()
	if src == "mania":
		return ms.stars_at(i)
	var key := _mode_star_key(ms, i)
	if key == "":
		return -1.0
	var cache := _trace_cache_get() if src == "trace" else _os_cache_get()
	return float(cache.get(key, -1.0))


## Diff-Index -> bekannte Modus-Sterne der sichtbaren Diffs (Rest: MapSet nimmt
## vorlaeufig die Mania-Sterne).
func _mode_star_map(ms: MapSet) -> Dictionary:
	var out := {}
	if _star_src() == "mania":
		return out
	for i in ms.visible_diffs(_vm()):
		var st := _mode_stars_known(ms, i)
		if st >= 0.0:
			out[i] = st
	return out


## Anzeige-/Sortierwert: Modus-Sterne, sonst vorlaeufig Mania-Sterne.
func _mode_stars(ms: MapSet, i: int) -> float:
	var st := _mode_stars_known(ms, i)
	return st if st >= 0.0 else ms.stars_at(i)


## Sichtbare Diffs nach Modus-Sternen (leicht -> schwer).
func _mode_order(ms: MapSet) -> Array[int]:
	return ms.visible_by_stars(_vm(), _mode_star_map(ms))


func _mode_max(ms: MapSet) -> float:
	return ms.max_visible_stars(_vm(), _mode_star_map(ms))


## Standard-Auswahl: schwerste bzw. leichteste Diff nach Modus-Sternen.
func _hardest(ms: MapSet) -> int:
	var order := _mode_order(ms)
	return order[-1] if not order.is_empty() else maxi(ms.difficulty_count() - 1, 0)


func _easiest(ms: MapSet) -> int:
	var order := _mode_order(ms)
	return order[0] if not order.is_empty() else 0


func _card_info_text(ms: MapSet) -> String:
	return "%s  ·  %s  ·  %s" % [_stars_text(_mode_max(ms)), _format_time(ms.length_ms()), ms.creator]


## Sterne-Anzeige der gewaehlten Diff (Modus-Sterne mit Modus-Name).
func _refresh_star_label() -> void:
	if _star_label == null or _selected_set == null:
		return
	var src := _star_src()
	var std := int(_selected_set.meta_at(_selected_diff).get("mode", 0)) != 3
	if src == "mania" or not _orbit_diff_ok(_selected_set, _selected_diff) or (src == "trace" and std):
		_star_label.text = _stars_text(_selected_set.stars_at(_selected_diff))
		return
	var st := _mode_stars_known(_selected_set, _selected_diff)
	_star_label.text = ScoreStore.mode_label(src) + " " + (_stars_text(st) if st >= 0.0 else "★ …")


## Neue Modus-Sterne: Diff-Leiste des gewaehlten Sets sofort, Liste entprellt.
func _mode_stars_arrived(osz: String) -> void:
	if _selected_set != null and _selected_set.osz_path == osz:
		_rebuild_diff_bar()
		_refresh_star_label()
	_resort_later()


func _resort_later() -> void:
	if _resort_due or not is_inside_tree():
		return
	_resort_due = true
	await get_tree().create_timer(RESORT_DELAY).timeout
	_resort_due = false
	if is_inside_tree():
		_resort_keep()


## Liste mit den neuen Sternen aktualisieren. Haengt die Reihenfolge an den
## Sternen (Sortierung/Sterne-Filter), neu aufbauen und die gewaehlte Karte an
## ihrer Bildschirmstelle halten; sonst nur Sterne/Farbe der Karten setzen.
func _resort_keep() -> void:
	var sort_m := int(_mode_filter()["sort"])
	if _star_filter == 0 and sort_m != SORT_STARS_UP and sort_m != SORT_STARS_DOWN:
		for card in _card_buttons:
			if not is_instance_valid(card) or not card.has_meta("info_lbl"):
				continue
			var ms: MapSet = card.get_meta("ms")
			(card.get_meta("info_lbl") as Label).text = _card_info_text(ms)
			var base := _card_box(COL_CARD, _star_color(_mode_max(ms)))
			for st in ["normal", "hover", "pressed", "focus"]:
				card.add_theme_stylebox_override(st, base)
		return
	var off := NAN
	var old_i := _filtered.find(_selected_set)
	if old_i >= 0 and old_i < _card_buttons.size() and is_instance_valid(_card_buttons[old_i]):
		var h := _card_buttons[old_i].get_parent().get_parent() as Control
		off = h.position.y - float(_scroll.scroll_vertical)
	_refresh_filter(_search.text)
	if is_nan(off):
		return
	await get_tree().process_frame
	var new_i := _filtered.find(_selected_set)
	if not is_inside_tree() or new_i < 0 or new_i >= _card_buttons.size() \
			or not is_instance_valid(_card_buttons[new_i]):
		return
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	var h2 := _card_buttons[new_i].get_parent().get_parent() as Control
	_scroll.scroll_vertical = int(h2.position.y - off)


func _orbit_key(ms: MapSet, ver: String) -> String:
	return _mkey(ms, ver, _stars_mode())


## Cache-Schluessel (orbit_stars.cfg) der Sterne von mode, gemerkt.
func _mkey(ms: MapSet, ver: String, mode: String) -> String:
	var k := mode + "|" + ms.osz_path + "|" + ver
	if not _okey_cache.has(k):
		_okey_cache[k] = orbit_stars_key(ms.osz_path, ver, mode)
	return _okey_cache[k]


func _orbit_diff_ok(ms: MapSet, i: int) -> bool:
	var m := ms.meta_at(i)
	return int(m.get("mode", 0)) != 3 or int(round(float(m.get("cs", 4.0)))) == 4


## Orbit-Sterne einer Diff aus dem Cache (-1 = noch nicht berechnet).
func _orbit_stars_known(ms: MapSet, i: int) -> float:
	return float(_os_cache_get().get(_orbit_key(ms, ms.version_name_at(i)), -1.0))


## Lauf-Historie in den Karriere-Zustand ziehen. Beim allerersten Mal zaehlt die
## alte Historie nicht (Start auf Stufe 1,5), nur Laeufe ab jetzt.
func _career_sync() -> void:
	var recent := ScoreStore.recent_plays(30, ScoreStore.MODE_ORBIT)
	recent.reverse()  # aelteste zuerst
	if recent.is_empty():
		return
	var s: Dictionary = _career_state
	if str(s.get("stamp", "")) == "":
		s["stamp"] = str((recent[recent.size() - 1] as Dictionary).get("date", ""))
		OrbitCareer.save_state(s)
		return
	var by_file := {}
	for ms in _library.mapsets:
		by_file[ms.osz_path.get_file()] = ms
	var runs: Array = []
	for e in recent:
		if str(e.get("date", "")) <= str(s.stamp):
			continue
		var st := 0.0  # Map fehlt in der Bibliothek: Lauf zaehlt nicht
		var ms: MapSet = by_file.get(str(e.get("osz_file", "")))
		if ms != null:
			var key := _orbit_key(ms, str(e.get("version", "")))
			st = float(_os_cache_get().get(key, -1.0))
			if st < 0.0 and not _bg_failed.has(key):
				_bg_enqueue({"key": key, "osz": ms.osz_path, "ver": str(e.get("version", ""))}, true)
				break  # Reihenfolge wahren: erst weiter, wenn die Sterne da sind
			st = maxf(st, 0.0)
		runs.append({"date": str(e.get("date", "")), "stars": st,
			"accuracy": float(e.get("accuracy", 0.0)), "grade": str(e.get("grade", "")),
			"failed": bool(e.get("failed", false))})
	if runs.is_empty():
		return
	var n: Dictionary = OrbitCareer.sync_runs(s, runs)
	_career_state = n
	OrbitCareer.save_state(n)


func _career_refresh() -> void:
	if _career_panel == null or not _career_on():
		return
	_career_dirty = false
	_career_sync()
	var level := float(_career_state.get("level", OrbitCareer.START_LEVEL))
	var idx := _scores_for_mode()
	var cands: Array = []
	var missing: Array = []
	var cache := _os_cache_get()
	for ms in _library.mapsets:
		var info: Dictionary = idx.get(ms.osz_path.get_file(), {})
		for i in ms.visible_diffs("orbit"):
			if not _orbit_diff_ok(ms, i):
				continue
			var ver := ms.version_name_at(i)
			var key := _orbit_key(ms, ver)
			var st := float(cache.get(key, -1.0))
			if st < 0.0:
				if not _bg_failed.has(key):
					missing.append({"key": key, "osz": ms.osz_path, "ver": ver, "osu": ms.stars_at(i)})
				continue
			cands.append({"ms": ms, "diff": i, "stars": st,
				"played": int(info.get(ver, {}).get("plays", 0)) > 0})
	var items: Array = []
	var seen := {}
	for c in OrbitCareer.suggest(cands, level, cands.size()):
		if seen.has(c.ms):
			continue
		seen[c.ms] = true
		items.append(c)
		if items.size() >= 5:
			break
	_career_items = items
	_bg_enqueue_list(missing, level)
	_career_panel.set_data({
		"level": level, "next_text": OrbitCareer.next_text(_career_state),
		"good": int(_career_state.get("good", 0)), "need": OrbitCareer.GOOD_NEED,
		"event": str(_career_state.get("event", "")), "items": items,
		"pending": _bg_queue.size() + (1 if _bg_thread != null else 0),
		"range_text": OrbitCareer.range_text(level),
	})
	_career_panel.set_selected(_selected_set, _selected_diff)


## Panel erst nach Ruhe neu bauen (viele Ergebnisse kurz nacheinander).
func _career_refresh_later() -> void:
	if _career_dirty:
		return
	_career_dirty = true
	await get_tree().create_timer(0.6).timeout
	if is_inside_tree() and _career_dirty:
		if _career_on():
			_career_refresh()
		else:
			_career_dirty = false
			_refresh_recommended()


## Empfohlen-Marke der Karten (nur Orbit + Frei): Orbit-Sterne einer sichtbaren
## Diff liegen im Fenster der Stufe.
func _refresh_recommended() -> void:
	var on := _play_mode == "orbit" and not _career_on()
	var level := float(_career_state.get("level", OrbitCareer.START_LEVEL))
	for card in _card_buttons:
		if not is_instance_valid(card) or not card.has_meta("rec_lbl"):
			continue
		var lbl: Label = card.get_meta("rec_lbl")
		var rec := false
		if on:
			var ms: MapSet = card.get_meta("ms")
			for i in ms.visible_diffs("orbit"):
				if _orbit_diff_ok(ms, i) and OrbitCareer.recommended(_orbit_stars_known(ms, i), level):
					rec = true
					break
		lbl.visible = rec


## Fehlende Sterne fuer die Bibliothek vormerken (Frei und Karriere).
func _bg_scan() -> void:
	var level := float(_career_state.get("level", OrbitCareer.START_LEVEL))
	var missing: Array = []
	if _star_src() == "mania":
		return
	for ms in _library.mapsets:
		for i in ms.visible_diffs(_vm()):
			var item := _bg_item(ms, i)
			if not item.is_empty():
				missing.append(item)
	_bg_enqueue_list(missing, level)


## Auftrag fuer fehlende Modus-Sterne einer Diff ({} = vorhanden, unmoeglich
## oder fehlgeschlagen). Nur 4K-Mania- und osu!standard-Diffs (Trace: nur 4K).
func _bg_item(ms: MapSet, i: int) -> Dictionary:
	var src := _star_src()
	if src == "mania" or not _orbit_diff_ok(ms, i) or _mode_stars_known(ms, i) >= 0.0:
		return {}
	if src == "trace" and int(ms.meta_at(i).get("mode", 0)) != 3:
		return {}
	var key := _mode_star_key(ms, i)
	if key == "" or _bg_failed.has(key):
		return {}
	return {"key": key, "osz": ms.osz_path, "ver": ms.version_name_at(i),
		"inner": ms.osu_filename_at(i), "osu": ms.stars_at(i), "mode": src}


## Gewaehltes Set zuerst: fehlende Modus-Sterne seiner Diffs vorn einreihen
## (entprellt wie die Einzel-Rechnung, Scrollen startet nichts).
func _bg_front_set(ms: MapSet) -> void:
	if ms == null or _star_src() == "mania" or not is_inside_tree() \
			or DisplayServer.get_name() == "headless":
		return
	_front_token += 1
	var tok := _front_token
	await get_tree().create_timer(ORBIT_STARS_DELAY).timeout
	if tok != _front_token or not is_inside_tree() or _selected_set != ms:
		return
	var order := _mode_order(ms)
	order.reverse()  # push_front: am Ende steht die leichteste vorn
	for i in order:
		var item := _bg_item(ms, i)
		if not item.is_empty() and item.key != _os_want:
			_bg_enqueue(item, true)
	_bg_pump()


## Moduswechsel: wartende Auftraege anderer Modi verwerfen.
func _bg_drop_other_modes() -> void:
	var src := _star_src()
	var keep: Array = []
	for it in _bg_queue:
		if str(it.get("mode", "orbit")) == src:
			keep.append(it)
		else:
			_bg_queued.erase(it.key)
	_bg_queue = keep


func _bg_enqueue_list(missing: Array, level: float) -> void:
	missing.sort_custom(func(a, b):
		return absf(float(a.osu) - level - 0.1) < absf(float(b.osu) - level - 0.1))
	for m in missing:
		_bg_enqueue(m, false)
	_bg_pump()


func _bg_enqueue(item: Dictionary, front: bool) -> void:
	var key: String = item.key
	if _bg_queued.has(key):
		return
	if not front and _bg_spent + _bg_queue.size() >= BG_BUDGET:
		return
	_bg_queued[key] = true
	if front:
		_bg_queue.push_front(item)
	else:
		_bg_queue.append(item)


func _bg_pump() -> void:
	if _bg_thread != null or _bg_queue.is_empty() or not is_inside_tree() \
			or DisplayServer.get_name() == "headless":
		return
	var item: Dictionary = _bg_queue.pop_front()
	_bg_spent += 1
	_bg_thread = Thread.new()
	_bg_thread.start(_bg_work.bind(item), Thread.PRIORITY_LOW)


func _bg_work(item: Dictionary) -> void:
	var mode := str(item.get("mode", "orbit"))
	var st := StarService.trace_stars_for(item.osz, str(item.get("inner", ""))) if mode == "trace" \
			else orbit_stars_compute(item.osz, item.ver, mode)
	_bg_finished.call_deferred(item, st)


func _bg_finished(item: Dictionary, st: float) -> void:
	if _bg_thread != null:
		_bg_thread.wait_to_finish()
		_bg_thread = null
	_bg_queued.erase(item.key)
	var mode := str(item.get("mode", "orbit"))
	if st >= 0.0:
		if mode == "trace":
			_trace_cache_get()[item.key] = st  # StarService hat schon gespeichert
		else:
			_os_cache_get()[item.key] = st
			orbit_stars_store(item.key, st)
	else:
		_bg_failed[item.key] = true
	if st >= 0.0 and mode == _star_src():
		_mode_stars_arrived(str(item.osz))
	if _play_mode == "orbit":
		_career_refresh_later()
	if str(item.get("mode", "orbit")) == _stars_mode():
		_recs_refresh_later()
	await get_tree().create_timer(BG_PAUSE).timeout
	if is_inside_tree():
		_bg_pump()


## Orbit-Sterne: nur fuer die gewaehlte Diff, im Thread, Ergebnis je
## Datei+Aenderungszeit+Version im Cache user://orbit_stars.cfg.
const ORBIT_STARS_PATH := "user://orbit_stars.cfg"
## Version hochzaehlen, sobald sich die Orbit-Sterne-Formel aendert: alte
## Werte fallen aus dem Schluessel und werden neu berechnet.
const ORBIT_STARS_VER := 2
const ORBIT_STARS_DELAY := 0.25
var _os_thread: Thread
var _os_key := ""        # Key der laufenden Berechnung
var _os_want := ""       # Key der aktuell gewaehlten Diff
var _os_want_args := []
var _os_token := 0


## mode "orbit": bisheriger Schluessel; Rally/Dirigent haengen die Modus-ID vorn an.
static func orbit_stars_key(osz: String, version: String, mode: String = "orbit") -> String:
	var base := "v%d|%s|%d|%s" % [ORBIT_STARS_VER, osz.get_file(), FileAccess.get_modified_time(osz), version]
	# Rally/Dirigent v2: echte Chart-Sterne statt Dichte-Schaetzung (alte Werte neu rechnen).
	if mode == "rally" or mode == "dirigent":
		return "%s2|%s" % [mode, base]
	return base if mode == "orbit" else "%s|%s" % [mode, base]


static func orbit_stars_cached(key: String, path: String = ORBIT_STARS_PATH) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return -1.0
	return float(cfg.get_value("stars", key, -1.0))


static func orbit_stars_store(key: String, stars: float, path: String = ORBIT_STARS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("stars", key, stars)
	cfg.save(path)


## Alle Eintraege des Caches auf einmal (Schluessel -> Sterne), fuer Listen.
static func orbit_stars_cache_all(path: String = ORBIT_STARS_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	var out := {}
	if cfg.load(path) != OK or not cfg.has_section("stars"):
		return out
	for k in cfg.get_section_keys("stars"):
		out[k] = float(cfg.get_value("stars", k, -1.0))
	return out


## Orbit-Sterne einer 4K- oder osu!standard-Diff berechnen (teuer: Import + Konvertierung).
## mode "rally"/"dirigent": Sterne 0..15 aus dem Modus-Chart, wenn dessen Skript
## static stars_of_beatmap(bm) kennt, sonst Dichte-Schaetzung (mode_stars_fallback).
static func orbit_stars_compute(osz: String, version: String, mode: String = "orbit") -> float:
	var imp := OszImporter.import(osz)
	if not imp.ok:
		return -1.0
	for d in imp.difficulties:
		var bm: Beatmap = d.beatmap
		if (bm.is_mania() or bm.mode() == 0) and bm.version_name() == version:
			if mode == "orbit":
				return OrbitConverter.stars(OrbitConverter.convert(bm))
			if mode == "trace":
				# Trace-Sterne: TraceStars (Browser nutzt StarService.trace_stars_for).
				if bm.is_mania() and bm.column_count() == 4:
					return TraceStars.from_beatmap(bm)
			var path := "res://scripts/%s/%s_chart.gd" % [mode, mode]
			if ResourceLoader.exists(path):
				var sc: GDScript = load(path)
				if sc != null and sc.has_method("stars_of_beatmap"):
					return float(sc.call("stars_of_beatmap", bm))
			return mode_stars_fallback(bm)
	return -1.0


## Platzhalter-Sterne ohne Modus-Chart: Spitzen-Notendichte (5-s-Fenster) und
## Durchschnitt, 0..15. Gilt nur, bis scripts/<modus>/<modus>_chart.gd echte liefert.
static func mode_stars_fallback(bm: Beatmap) -> float:
	var ts: Array[float] = []
	for h in bm.hit_objects:
		ts.append(h.time)
	if ts.size() < 2:
		return 0.0
	ts.sort()
	var peak := 0.0
	var j := 0
	for i in ts.size():
		while ts[i] - ts[j] > 5000.0:
			j += 1
		peak = maxf(peak, float(i - j + 1) / 5.0)
	var avg := float(ts.size()) / maxf((ts[-1] - ts[0]) / 1000.0, 1.0)
	return clampf(0.55 * peak + 0.45 * avg * 1.4, 0.0, 15.0) * 0.8


func _orbit_stars_request(osz: String, version: String) -> void:
	var key := orbit_stars_key(osz, version, _stars_mode())
	_os_want = key
	_os_want_args = [osz, version, _stars_mode()]
	var hit := orbit_stars_cached(key)
	if hit >= 0.0:
		_star_label.text = ScoreStore.mode_label(_stars_mode()) + " " + _stars_text(hit)
		return
	_star_label.text = ScoreStore.mode_label(_stars_mode()) + " ★ …"
	_os_token += 1
	var tok := _os_token
	await get_tree().create_timer(ORBIT_STARS_DELAY).timeout  # Scrollen: erst nach Ruhe rechnen
	if tok != _os_token or not is_inside_tree():
		return
	_orbit_stars_start()


func _orbit_stars_start() -> void:
	if _os_thread != null or _os_want == "":
		return
	_os_key = _os_want
	_os_thread = Thread.new()
	_os_thread.start(_orbit_stars_work.bind(_os_key, _os_want_args[0], _os_want_args[1], _os_want_args[2]))


func _orbit_stars_work(key: String, osz: String, version: String, mode: String) -> void:
	var st := orbit_stars_compute(osz, version, mode)
	_orbit_stars_done.call_deferred(key, st)


func _orbit_stars_done(key: String, st: float) -> void:
	if _os_thread != null:
		_os_thread.wait_to_finish()
		_os_thread = null
	if st >= 0.0:
		orbit_stars_store(key, st)
		_os_cache_get()[key] = st
		if _selected_set != null and _mode_star_key(_selected_set, _selected_diff) == key:
			_mode_stars_arrived(_selected_set.osz_path)
	if key == _os_want:
		if st >= 0.0 and _play_mode != "mania":
			_star_label.text = ScoreStore.mode_label(_stars_mode()) + " " + _stars_text(st)
	elif _os_want != "":
		_orbit_stars_start()


## Sterne fuer die Anzeige: "★ 7,27" (ein Stern, Dezimalkomma).
func _stars_text(stars: float) -> String:
	return ("★ " + UiTheme.fmt_num(stars, 2)) if stars >= 0.0 else "★ —"


func _fmt_stars(stars: float) -> String:
	return ("%.2f" % stars) if stars >= 0.0 else "—"


func _format_time(ms: float) -> String:
	var total := int(ms / 1000.0)
	return "%02d:%02d" % [total / 60, total % 60]


# ---------------------------------------------------------------------------
# Headless-Selbsttest
# ---------------------------------------------------------------------------

func _headless_report() -> void:
	print("=== Song-Select Headless-Report ===")
	print("Mapsets gefunden: %d" % _library.mapsets.size())
	for ms in _library.mapsets:
		var star_txt := ""
		for i in ms.difficulty_count():
			star_txt += "%s=%s " % [ms.version_name_at(i), _fmt_stars(ms.stars_at(i))]
		print("  %s - %s | %d Diffs | %s" % [ms.artist, ms.title, ms.difficulty_count(), star_txt])
	if _selected_set != null:
		print("Ausgewaehlt: %s [%s] %s★" % [
			_selected_set.title, _selected_set.version_name_at(_selected_diff),
			_fmt_stars(_selected_set.stars_at(_selected_diff))])
	print("=== Report OK ===")
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# "For you": Vorschlaege je Modus (Recommender, docs/recommend.md)
# ---------------------------------------------------------------------------
# Ruhiger Block ueber der Liste: Kopf "For you" + Stufe Easy/Challenge/Push,
# darunter 3 Kacheln (720p) bzw. 5 Zeilen (ab 900 px Hoehe). Klick waehlt die
# Map. Stufe je Modus, Ein-/Ausklappen und Ausblenden in browser_state.cfg.
# Rechnen im Thread (Laeufe aus ScoreStore, Max-pp-Cache, Recommender).

const REC_MIN_RUNS := 5          # darunter: Start-Vorschlaege nach leichten Sternen
const REC_STARTER_MIN := 1.0     # Start-Vorschlaege: leichteste Maps ab 1 Stern
const REC_TALL_H := 900.0        # ab dieser Fensterhoehe 5 Zeilen statt 3 Kacheln
const REC_TILE_H := 62.0
const REC_ROW_H := 54.0
const REC_COVER := 44.0
const REC_MAXPP_CAP := 400       # hoechstens so viele Max-pp-Abfragen je Rechnung
const REC_STYLE_PATH := "user://rec_style.cfg"  # Stil-Merkmale je Diff (Notenfolge), gecacht
const REC_STYLE_CAP := 60        # hoechstens so viele neue Diffs je Rechnung auswerten
const REC_SEEN_PATH := "user://rec_seen.cfg"      # wie oft ein Vorschlag schon gezeigt wurde
const REC_SEEN_DAYS := 21        # aeltere Eintraege verfallen
const REC_ONLINE_PATH := "user://rec_online.cfg"  # Antworten der Online-Suche (12 h)
const REC_ONLINE_N := 2          # Online-Kacheln je Seite (breit genug fuer Grund + "Get")

var _rec := {"levels": {}, "collapsed": false, "hidden": false}
var _rec_box: VBoxContainer
var _rec_sub: Label
var _rec_level_btns: Array[Button] = []
var _rec_fold_btn: Button
var _rec_hide_btn: Button
var _rec_body: Control
var _rec_chip: Button
var _rec_thread: Thread
var _rec_token := 0
var _rec_again := false
var _rec_dirty := false
var _rec_res := {}               # {mode, starter, items, comfort}
var _rec_lookup := {}            # "datei|version" -> [MapSet, diff]
var _rec_rows: Array = []        # {btn, ms, diff}
var _rec_cover_mat: ShaderMaterial
var _rec_page := 0               # Seite ("Show more"), gilt fuer lokale und Online-Vorschlaege
var _rec_frozen := false         # Harness: festes Beispiel, keine Rechnung
var _rec_seen := {}              # "modus|datei|version" bzw. "modus|online:<id>" -> [Anzahl, Tag]
var _rec_seen_loaded := false
var _rec_on_cache := {}          # Suche -> {t, pages, end, results} (Recommender.online_cache_put)
var _rec_on_loaded := false
var _rec_on_list: Array = []     # geordnete Online-Vorschlaege der aktuellen Suche
var _rec_on_rows := {}           # Set-ID -> {cover, get, sub, text}
var _rec_on_fail_at := 0
var _rec_on_offset := 0
var _rec_blank: ImageTexture
static var _rec_tr_loaded := false

## Deutsche Texte der Vorschlaege (Quelle Englisch = Schluessel), ohne Eintrag
## in translations/.
const REC_DE := {
	"Your style: %s": "Dein Stil: %s",
	"fits: %s": "passt: %s",
	"like %s": "wie %s",
	"mapped by %s": "Mapper %s",
	"about %d:%02d long": "etwa %d:%02d lang",
	"in your star range": "in deinem Sterne-Bereich",
	"Show more": "Mehr anzeigen",
	"Show more suggestions": "Weitere Vorschläge zeigen",
	"Not in your library yet": "Noch nicht in deiner Bibliothek",
	"Get": "Laden",
	"Retry": "Nochmal",
	"Download and play right away": "Herunterladen und sofort spielen",
	"Click to listen": "Klicken zum Vorhören",
	"Playing preview": "Vorschau läuft",
	"From the maps you play in %s": "Aus den Maps, die du in %s spielst",
	"Electronic": "Elektronisch",
	"Video game": "Videospiel",
	"Classical": "Klassik",
	"Hip hop": "Hip-Hop",
	"Japanese": "Japanisch",
	"Korean": "Koreanisch",
	"Chinese": "Chinesisch",
}


## Zustand bereinigen: Stufe je Modus (unbekannt -> Challenge), zwei Schalter.
static func rec_sanitize(d) -> Dictionary:
	var src: Dictionary = d if d is Dictionary else {}
	var raw = src.get("levels", {})
	var lv := {}
	for m in PLAY_MODES:
		lv[m] = Recommender.normalize_level(str(raw.get(m, ""))) if raw is Dictionary \
				else Recommender.LEVEL_DEFAULT
	return {"levels": lv, "collapsed": bool(src.get("collapsed", false)),
		"hidden": bool(src.get("hidden", false))}


static func rec_level(state: Dictionary, mode: String) -> String:
	var lv = state.get("levels", {})
	return Recommender.normalize_level(str(lv.get(mode, ""))) if lv is Dictionary \
			else Recommender.LEVEL_DEFAULT


## 3 Kacheln nebeneinander, ab REC_TALL_H Fensterhoehe 5 Zeilen.
static func rec_count(view_h: float) -> int:
	return 5 if view_h >= REC_TALL_H else 3


## Wenig Daten: leichteste spielbare Maps (ab REC_STARTER_MIN), eine je Set, ohne SS.
static func rec_starters(mode: String, cands: Array, n: int) -> Array:
	var pool: Array = []
	for c in cands:
		if not (c is Dictionary):
			continue
		var st := float(c.get("stars", -1.0))
		if st <= 0.0 or str(c.get("best_grade", "")) == "SS" \
				or not Recommender.playable(mode, int(c.get("osu_mode", 3))):
			continue
		pool.append(c)
	pool.sort_custom(func(a, b):
		var la := float(a.stars) < REC_STARTER_MIN
		var lb := float(b.stars) < REC_STARTER_MIN
		if la != lb:
			return lb  # zu leichte Maps (< 1 Stern) nur zum Auffuellen
		if not is_equal_approx(float(a.stars), float(b.stars)):
			return float(a.stars) < float(b.stars)
		if str(a.set) != str(b.set):
			return str(a.set) < str(b.set)
		return str(a.diff) < str(b.diff))
	var out: Array = []
	var seen := {}
	for c in pool:
		if out.size() >= n:
			break
		if seen.has(str(c.set)):
			continue
		seen[str(c.set)] = true
		out.append({"set": c.set, "diff": c.diff, "stars": float(c.stars),
			"reason": TranslationServer.translate("Easy start")})
	return out


## Vorschlaege oder (unter REC_MIN_RUNS Laeufen) Start-Vorschlaege.
static func rec_compute(mode: String, level: String, cands: Array, runs: Array,
		n: int, now: int = 0, tst: Dictionary = {}, seen: Dictionary = {}) -> Dictionary:
	var sk := Recommender.skill(mode, runs)
	if runs.size() < REC_MIN_RUNS:
		return {"starter": true, "items": rec_starters(mode, cands, n), "comfort": float(sk.comfort)}
	return {"starter": false, "items": Recommender.suggest(mode, level, cands, n, runs, now, tst, seen),
		"comfort": float(sk.comfort)}


## osu!-Sterne minus Modus-Sterne (Median der eigenen Maps des Such-Modus):
## der Mirror kennt nur osu!-Sterne. Mania 0.
static func rec_star_shift(mode: String, cands: Array) -> float:
	if mode == "mania":
		return 0.0
	var want := 0 if mode == "orbit" else 3
	var d: Array = []
	for c in cands:
		var b := float(c.get("base_stars", -1.0))
		if b > 0.0 and float(c.get("stars", -1.0)) > 0.0 and int(c.get("osu_mode", 3)) == want:
			d.append(b - float(c.stars))
	return Recommender._median(d) if d.size() >= 3 else 0.0


## Gezeigt-Zaehler: keys (ohne Praefix) heute einmal hochzaehlen. seen:
## "praefix|key" -> [Anzahl, Tag]. true = etwas geaendert.
static func rec_seen_note(seen: Dictionary, prefix: String, keys: Array, day: int) -> bool:
	var changed := false
	for k in keys:
		var full := "%s|%s" % [prefix, k]
		var cur = seen.get(full)
		if cur is Array and cur.size() == 2 and int(cur[1]) == day:
			continue
		seen[full] = [(int(cur[0]) if cur is Array and cur.size() == 2 else 0) + 1, day]
		changed = true
	return changed


## Zaehler eines Modus fuer den Recommender ("key" -> Anzahl); verfallene
## Eintraege (aelter als REC_SEEN_DAYS) fliegen dabei aus seen.
static func rec_seen_counts(seen: Dictionary, prefix: String, day: int) -> Dictionary:
	var out := {}
	for full in seen.keys():
		var cur = seen[full]
		if not (cur is Array) or cur.size() != 2 or day - int(cur[1]) > REC_SEEN_DAYS:
			seen.erase(full)
			continue
		if str(full).begins_with(prefix + "|"):
			out[str(full).substr(prefix.length() + 1)] = int(cur[0])
	return out


## Stil-Merkmale der Kandidaten aus der Notenfolge (Recommender.mania_style /
## std_style), gecacht in REC_STYLE_PATH je "datei|osu" mit Aenderungszeit der
## .osz. Laeuft im Rechen-Thread; je Aufruf hoechstens REC_STYLE_CAP neue Diffs.
static func rec_fill_style(cands: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.load(REC_STYLE_PATH)
	var fresh := 0
	var zips := {}
	for c in cands:
		var osz := str(c.get("osz", ""))
		var inner := str(c.get("inner", ""))
		if osz == "" or inner == "":
			continue
		var key := "%s|%s" % [osz.get_file(), inner]
		var mt := FileAccess.get_modified_time(osz)
		var hit = cfg.get_value("style", key) if cfg.has_section_key("style", key) else null
		if hit is Array and hit.size() == 3 and int(hit[0]) == mt:
			c["style"] = hit[1]
			rec_apply_meta(c, hit[2])
			continue
		if fresh >= REC_STYLE_CAP:
			continue
		fresh += 1
		if not zips.has(osz):
			var z := ZIPReader.new()
			zips[osz] = z if z.open(osz) == OK else null
		var st := {}
		var meta := {}
		if zips[osz] != null:
			var text := (zips[osz] as ZIPReader).read_file(inner).get_string_from_utf8()
			st = rec_style_of_text(text)
			meta = rec_meta_of_text(text)
		cfg.set_value("style", key, [mt, st, meta])
		c["style"] = st
		rec_apply_meta(c, meta)
	for z in zips.values():
		if z != null:
			(z as ZIPReader).close()
	if fresh > 0:
		cfg.save(REC_STYLE_PATH)


## Genre, Sprache und Tags aus dem Kopf einer .osu-Datei (Tags + Source).
static func rec_meta_of_text(text: String) -> Dictionary:
	var tags := ""
	var source := ""
	for raw in text.substr(0, 8000).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("Tags:"):
			tags = line.trim_prefix("Tags:").strip_edges()
		elif line.begins_with("Source:"):
			source = line.trim_prefix("Source:").strip_edges()
		elif line == "[Difficulty]":
			break
	var g := Recommender.genre_from_tags(tags, source)
	var words: Array = []
	for w in tags.to_lower().split(" ", false):
		if w.length() >= 3 and not words.has(w):
			words.append(w)
		if words.size() >= 8:
			break
	return {"genre": str(g.genre), "language": str(g.language), "tags": words}


static func rec_apply_meta(c: Dictionary, meta) -> void:
	if not (meta is Dictionary):
		return
	for k in ["genre", "language"]:
		if str(meta.get(k, "")) != "":
			c[k] = str(meta[k])
	if meta.get("tags") is Array and not (meta.tags as Array).is_empty():
		c["tags"] = meta.tags


## Stil einer .osu-Datei (Text): Mania (Mode 3) -> mania_style, sonst std_style.
static func rec_style_of_text(text: String) -> Dictionary:
	var mode := 0
	var keys := 4
	var sec := ""
	var objs: Array = []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("["):
			sec = line
			continue
		if sec == "[General]" and line.begins_with("Mode:"):
			mode = int(line.get_slice(":", 1).strip_edges())
		elif sec == "[Difficulty]" and line.begins_with("CircleSize:"):
			keys = maxi(1, roundi(float(line.get_slice(":", 1).strip_edges())))
		elif sec == "[HitObjects]" and line != "":
			var p := line.split(",")
			if p.size() < 4:
				continue
			var x := float(p[0])
			var t := float(p[2])
			var typ := int(p[3])
			if mode == 3:
				objs.append([t, clampi(floori(x * keys / 512.0), 0, keys - 1), (typ & 128) != 0])
			elif (typ & 8) == 0:  # Spinner ueberspringen
				objs.append([t, x, float(p[1])])
	return Recommender.mania_style(objs) if mode == 3 else Recommender.std_style(objs)


## Vorlieben des Modus: Merkmale aller Kandidaten, Plays je Diff, Favoriten
## (Maps in Collections). Rechen-Thread.
static func rec_taste(mode: String, cands: Array, runs: Array) -> Dictionary:
	var feats := {}
	for c in cands:
		feats["%s|%s" % [c.set, c.diff]] = c
	var sid := "" if mode == "mania" else mode
	var plays := {}
	for e in ScoreStore.most_played(2000, sid):
		var k := "%s|%s" % [str(e.get("osz_file", "")), str(e.get("version", "")).strip_edges()]
		plays[k] = int(plays.get(k, 0)) + int(e.get("count", 0))
	var favs := {}
	for name in CollectionStore.list_names():
		for f in CollectionStore.maps_in(str(name)):
			favs[str(f).get_file()] = true
	return Recommender.taste(runs, feats, plays, favs)


## Laeufe an die Bibliothek binden: Version ohne Rand-Leerzeichen (Bestwerte
## speichern "Hard ", die Liste "Hard"), "Diff | Zusatz" der letzten Laeufe auf
## "Diff" kuerzen, Sterne aus stars ("datei|version" -> Sterne, wie der Browser
## sie zeigt). Laeufe ohne bekannte Sterne fallen weg (sie verzerren die Kurve).
static func rec_runs(runs: Array, stars: Dictionary) -> Array:
	var out: Array = []
	for r in runs:
		var f := str(r.get("set", ""))
		var v := str(r.get("diff", "")).strip_edges()
		var v2 := v.get_slice(" | ", 0).strip_edges()
		var st := float(r.get("stars", -1.0))
		if stars.has("%s|%s" % [f, v]):
			st = float(stars["%s|%s" % [f, v]])
		elif stars.has("%s|%s" % [f, v2]):
			v = v2
			st = float(stars["%s|%s" % [f, v2]])
		if st <= 0.0:
			continue
		var c: Dictionary = r.duplicate()
		c["diff"] = v
		c["stars"] = st
		out.append(c)
	return out


## Mania + Push: Max-pp (SS) aus dem StarService-Cache an Kandidaten im
## Push-Fenster haengen; ohne Cache-Eintrag schaetzt der Recommender.
static func rec_fill_max_pp(cands: Array, runs: Array) -> void:
	var rng := Recommender.star_range(Recommender.skill("mania", runs), Recommender.LEVEL_PUSH)
	var cfg := ConfigFile.new()  # einmal laden (max_pp_cached liest je Aufruf neu)
	if cfg.load(StarService.CACHE_PATH) != OK or not cfg.has_section(StarService.MAXPP_SECTION):
		return
	var base := {}
	var asked := 0
	for c in cands:
		var st := float(c.get("stars", -1.0))
		var osz := str(c.get("osz", ""))
		if st < rng.x or st > rng.y or osz == "":
			continue
		asked += 1
		if asked > REC_MAXPP_CAP:
			return
		if not base.has(osz):
			base[osz] = StarService._cache_key(osz)
		var key := "%s|%s" % [base[osz], c.get("inner", "")]
		var v := float(cfg.get_value(StarService.MAXPP_SECTION, key, -1.0))
		if v >= 0.0:
			c["max_pp"] = v


## modes.csv (Quelle Englisch) auch auf Deutsch, ohne Eintrag in project.godot.
static func _rec_translations() -> void:
	if _rec_tr_loaded:
		return
	_rec_tr_loaded = true
	var path := "res://translations/modes.de.translation"
	if ResourceLoader.exists(path):
		var t := load(path) as Translation
		if t != null:
			TranslationServer.add_translation(t)
	# Auch Englisch eintragen: ohne Eintrag greift die Rueckfall-Sprache (de).
	var de := Translation.new()
	de.locale = "de"
	var en := Translation.new()
	en.locale = "en"
	for k in REC_DE:
		de.add_message(k, REC_DE[k])
		en.add_message(k, k)
	TranslationServer.add_translation(de)
	TranslationServer.add_translation(en)


func _build_recs() -> void:
	_rec_translations()
	_rec_box = VBoxContainer.new()
	_rec_box.add_theme_constant_override("separation", 8)
	_filter_stack.add_child(_rec_box)
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, 28)
	head.add_theme_constant_override("separation", 6)
	_rec_box.add_child(head)
	_rec_fold_btn = Button.new()
	_rec_fold_btn.flat = true
	_rec_fold_btn.focus_mode = Control.FOCUS_NONE
	_rec_fold_btn.text = tr("For you")
	_rec_fold_btn.add_theme_font_override("font", UiTheme.heading_font(1))
	_rec_fold_btn.add_theme_font_size_override("font_size", 15)
	for k in ["font_color", "font_pressed_color", "font_focus_color"]:
		_rec_fold_btn.add_theme_color_override(k, COL_TEXT)
	_rec_fold_btn.add_theme_color_override("font_hover_color", COL_ACCENT)
	_rec_fold_btn.add_theme_color_override("icon_normal_color", COL_DIM)
	_rec_fold_btn.add_theme_color_override("icon_hover_color", COL_ACCENT)
	_rec_fold_btn.add_theme_constant_override("h_separation", 6)
	_rec_fold_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_rec_fold_btn.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rec_fold_btn.tooltip_text = tr("Collapse or expand suggestions")
	_rec_fold_btn.pressed.connect(func():
		_rec["collapsed"] = not bool(_rec.collapsed)
		_apply_recs_visibility()
		if _state_ready:
			_save_browser_state())
	head.add_child(_rec_fold_btn)
	_rec_sub = Label.new()
	_rec_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rec_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rec_sub.clip_text = true
	_rec_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_rec_sub.add_theme_font_size_override("font_size", 12)
	_rec_sub.add_theme_color_override("font_color", COL_DIM)
	_rec_sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_rec_sub.mouse_filter = Control.MOUSE_FILTER_PASS  # Tooltip: ganzes Stilprofil
	head.add_child(_rec_sub)
	var mir := get_node_or_null("/root/Mirror")
	if mir != null:
		mir.cover_ready.connect(_on_rec_cover)
		mir.download_progress.connect(_on_rec_dl_progress)
		mir.download_failed.connect(_on_rec_dl_failed)
	_rec_level_btns.clear()
	for lv in Recommender.LEVELS:
		var b := _make_toggle(Recommender.level_label(lv), 12, 13)
		b.custom_minimum_size = Vector2(0, 26)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = tr(_rec_level_tip(lv))
		var level: String = lv
		b.pressed.connect(func(): _set_rec_level(level))
		head.add_child(b)
		_rec_level_btns.append(b)
	_rec_hide_btn = Button.new()
	_rec_hide_btn.text = tr("Hide")
	_rec_hide_btn.tooltip_text = tr("Hide suggestions")
	_rec_hide_btn.flat = true
	_rec_hide_btn.focus_mode = Control.FOCUS_NONE
	_rec_hide_btn.add_theme_font_size_override("font_size", 12)
	_rec_hide_btn.add_theme_color_override("font_color", COL_DIM)
	_rec_hide_btn.add_theme_color_override("font_hover_color", COL_TEXT)
	_rec_hide_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_rec_hide_btn.pressed.connect(func(): _set_recs_hidden(true))
	head.add_child(_rec_hide_btn)
	var sh := Shader.new()
	sh.code = OrbitCareerPanel._COVER_SHADER
	_rec_cover_mat = ShaderMaterial.new()
	_rec_cover_mat.shader = sh
	_rec_cover_mat.set_shader_parameter("rect_size", Vector2(REC_COVER, REC_COVER))
	_rec_cover_mat.set_shader_parameter("radius", 8.0)
	get_viewport().size_changed.connect(func():
		if is_inside_tree() and not _rec_res.is_empty():
			_recs_render())
	_restyle_rec_levels()


static func _rec_level_tip(lv: String) -> String:
	match lv:
		Recommender.LEVEL_EASY: return "Below your comfort level: relaxed maps"
		Recommender.LEVEL_PUSH: return "At your limit: maps that can set a new top score"
	return "From your comfort level up to your limit"


func _restyle_rec_levels() -> void:
	var cur := rec_level(_rec, _play_mode)
	for i in _rec_level_btns.size():
		_apply_toggle(_rec_level_btns[i], Recommender.LEVELS[i] == cur)


func _set_rec_level(lv: String) -> void:
	_rec.levels[_play_mode] = Recommender.normalize_level(lv)
	_restyle_rec_levels()
	if _state_ready:
		_save_browser_state()
	_recs_refresh()


func _set_recs_hidden(on: bool) -> void:
	_rec["hidden"] = on
	if not on:
		_rec["collapsed"] = false
	_apply_recs_visibility()
	if _state_ready:
		_save_browser_state()
	if not on:
		_recs_refresh()


## Sichtbarkeit: aus (Hide), eingeklappt (nur Kopf), offen. Nie im Karriere-Modus.
func _apply_recs_visibility() -> void:
	if _rec_box == null:
		return
	var hidden := bool(_rec.hidden)
	var career := _career_on()
	# Sammlungs-Ansicht: keine Vorschlaege, dort zaehlt nur die eigene Liste.
	var off := career or _collection_mode
	_rec_box.visible = not hidden and not off
	if _rec_chip != null:
		_rec_chip.visible = hidden and not off  # nur zum Wieder-Einblenden
	var open := not bool(_rec.collapsed)
	if _rec_body != null:
		_rec_body.visible = open
	_rec_fold_btn.icon = _rec_fold_icon(open)
	var starter := bool(_rec_res.get("starter", false))
	for b in _rec_level_btns:
		b.visible = open and not starter
	_rec_hide_btn.visible = open
	_restyle_rec_levels()
	_update_list_top()


## Chevron unten (offen) / rechts (zu).
func _rec_fold_icon(open: bool) -> ImageTexture:
	if open:
		return _line_icon(16, [[Vector2(4, 6.5), Vector2(8, 10.5)], [Vector2(8, 10.5), Vector2(12, 6.5)]])
	return _chevron_icon(1)


## Neu rechnen (nach Start, Lauf, Moduswechsel, Stufe, neuen Sternen).
func _recs_refresh() -> void:
	if _rec_box == null or DisplayServer.get_name() == "headless" or _rec_frozen:
		return
	_apply_recs_visibility()
	if bool(_rec.hidden) or _career_on():
		return
	if _rec_thread != null:
		_rec_again = true
		return
	if _star_src() != "mania":
		_bg_scan()  # fehlende Modus-Sterne im Hintergrund
		_bg_pump()
	var job := _recs_job()
	_rec_token += 1
	_rec_thread = Thread.new()
	_rec_thread.start(_recs_work.bind(job, _rec_token), Thread.PRIORITY_LOW)


## Entprellt: viele neue Sterne kurz nacheinander -> eine Rechnung.
func _recs_refresh_later() -> void:
	if _rec_dirty:
		return
	_rec_dirty = true
	await get_tree().create_timer(0.8).timeout
	_rec_dirty = false
	if is_inside_tree():
		_recs_refresh()


## Kandidaten (nur lokale Maps des Modus) und Sterne fuer die Laeufe, im
## Hauptthread aus Bibliothek und Caches (keine Berechnung).
func _recs_job() -> Dictionary:
	var mode := _play_mode
	var idx := _scores_for_mode()
	var cands: Array = []
	var stars := {}
	_rec_lookup = {}
	if not _rec_seen_loaded:
		_rec_seen_loaded = true
		var scfg := ConfigFile.new()
		if scfg.load(REC_SEEN_PATH) == OK:
			var sv = scfg.get_value("seen", "all", {})
			_rec_seen = sv if sv is Dictionary else {}
	for ms in _library.mapsets:
		var file := ms.osz_path.get_file()
		var info: Dictionary = idx.get(file, {})
		for i in ms.visible_diffs(_vm()):
			var osu_mode := int(ms.meta_at(i).get("mode", 0))
			if not Recommender.playable(mode, osu_mode) or not _orbit_diff_ok(ms, i):
				continue
			var ver := ms.version_name_at(i)
			var st := _mode_stars_known(ms, i)  # dieselben Modus-Sterne wie der Browser
			var k := "%s|%s" % [file, ver.strip_edges()]
			stars[k] = st
			if st <= 0.0:
				continue
			_rec_lookup[k] = [ms, i]
			var vi: Dictionary = info.get(ver, {})
			var meta := ms.meta_at(i)
			var dur := float(meta.get("duration_ms", 0.0))
			var last := str(vi.get("last", ""))
			if last != "" and _rec_seen.has("%s|%s" % [mode, k]) \
					and Recommender._unix(last) / 86400 >= int((_rec_seen["%s|%s" % [mode, k]] as Array)[1]):
				_rec_seen.erase("%s|%s" % [mode, k])  # seither gespielt: wieder neu
			cands.append({"set": file, "diff": ver.strip_edges(), "stars": st, "osu_mode": osu_mode,
				"last_played": last, "best_grade": str(vi.get("grade", "")),
				"osz": ms.osz_path, "inner": ms.osu_filename_at(i), "artist": ms.artist,
				"title": ms.title, "mapper": ms.creator, "sv": bool(meta.get("sv", false)),
				"base_stars": ms.stars_at(i),
				"bpm": float(meta.get("bpm", -1.0)), "length": dur / 1000.0 if dur > 0.0 else -1.0})
	var per := rec_count(get_viewport_rect().size.y)
	return {"mode": mode, "level": rec_level(_rec, mode), "n": per * Recommender.PAGE_MAX, "cands": cands,
		"stars": stars, "seen": rec_seen_counts(_rec_seen, mode, Recommender.now_local() / 86400)}


func _recs_work(job: Dictionary, tok: int) -> void:
	var runs := rec_runs(Recommender.runs_from_store(str(job.mode)), job.stars)
	if job.mode == "mania" and job.level == Recommender.LEVEL_PUSH and runs.size() >= REC_MIN_RUNS:
		rec_fill_max_pp(job.cands, runs)
	var tst := {}
	if runs.size() >= REC_MIN_RUNS:
		rec_fill_style(job.cands)
		tst = rec_taste(str(job.mode), job.cands, runs)
	var res := rec_compute(str(job.mode), str(job.level), job.cands, runs, int(job.n), 0, tst,
		job.get("seen", {}))
	res["mode"] = job.mode
	# Stilprofil (sichtbar) und Suchauftrag fuer Online-Vorschlaege.
	res["taste"] = tst
	res["profile"] = Recommender.profile_text(tst, 6)
	res["profile_parts"] = Recommender.profile_parts(tst)
	var lv := Recommender.LEVEL_EASY if bool(res.starter) else str(job.level)
	res["query"] = Recommender.online_query(str(job.mode), lv, Recommender.skill(str(job.mode), runs), tst,
		rec_star_shift(str(job.mode), job.cands))
	_recs_done.call_deferred(res, tok)


func _recs_done(res: Dictionary, tok: int) -> void:
	if _rec_thread != null:
		_rec_thread.wait_to_finish()
		_rec_thread = null
	if not is_inside_tree():
		return
	if _rec_again:
		_rec_again = false
		_recs_refresh()
		return
	if tok != _rec_token or str(res.get("mode", "")) != _play_mode or _rec_frozen:
		return
	_rec_res = res
	_rec_page = 0
	_rec_online_update()
	_recs_render()


func _recs_render() -> void:
	if _rec_box == null:
		return
	if _rec_body != null:
		_rec_body.queue_free()
		_rec_body = null
	_rec_rows.clear()
	_rec_on_rows.clear()
	var n := rec_count(get_viewport_rect().size.y)
	var tall := n > 3
	var starter := bool(_rec_res.get("starter", false))
	var comfort := float(_rec_res.get("comfort", -1.0))
	var profile := str(_rec_res.get("profile", ""))
	var level_txt := (tr("Your level: about %s") % _stars_text(comfort)) if comfort > 0.0 else ""
	if starter:
		_rec_sub.text = tr("Play a few maps to get suggestions")
		_rec_sub.tooltip_text = ""
	else:
		_rec_sub.text = level_txt
		_rec_sub.tooltip_text = ""
	if starter:
		profile = ""
	var valid: Array = []
	for it in _rec_res.get("items", []):
		var hit = _rec_lookup.get("%s|%s" % [it.set, it.diff])
		if hit == null:
			continue
		valid.append({"ms": hit[0], "diff": hit[1], "stars": float(it.stars),
			"reason": str(it.get("reason", "")), "acc": float(it.get("expected_acc", -1.0)),
			"style": str(it.get("style_reason", "")), "key": "%s|%s" % [it.set, it.diff]})
	# Seiten: "Show more" blaettert, gerechnet ist schon alles (kein Ruckeln).
	var pages := maxi(Recommender.page_count(valid.size(), n),
		Recommender.page_count(_rec_on_list.size(), REC_ONLINE_N))
	_rec_page = posmod(_rec_page, pages)
	var items := Recommender.page_slice(valid, _rec_page, n)
	var online := Recommender.page_slice(_rec_on_list, _rec_page, REC_ONLINE_N)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	if profile != "" or pages > 1:
		body.add_child(_rec_profile_row(profile, pages))
	if items.is_empty():
		var empty := Label.new()
		empty.custom_minimum_size = Vector2(0, 30)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", COL_DIM)
		var pending := _star_src() != "mania" and (_bg_thread != null or not _bg_queue.is_empty())
		empty.text = tr("Calculating stars …") if pending \
				else tr("No fitting map in your library. Try another level or get maps online.")
		body.add_child(empty)
	elif tall:
		for it in items:
			body.add_child(_rec_card(it, true))
	else:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		for it in items:
			hb.add_child(_rec_card(it, false))
		for i in range(items.size(), n):
			hb.add_child(_rec_spacer())  # kurze letzte Seite: Kacheln behalten ihre Breite
		body.add_child(hb)
	if not online.is_empty():
		body.add_child(_rec_online_caption())
		var ob := HBoxContainer.new()
		ob.add_theme_constant_override("separation", 8)
		for o in online:
			ob.add_child(_rec_online_card(o))
		for i in range(online.size(), REC_ONLINE_N):
			ob.add_child(_rec_spacer())
		body.add_child(ob)
	var gap := Control.new()  # Luft zur Liste
	gap.custom_minimum_size = Vector2(0, 2)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(gap)
	_rec_body = body
	_rec_box.add_child(_rec_body)
	_apply_recs_visibility()
	_recs_mark_selected()
	_rec_mark_preview()
	# Neuheit: was heute gezeigt wurde, zaehlt einmal.
	var shown: Array = []
	for it in items:
		shown.append(str(it.key))
	for o in online:
		shown.append("online:%d" % int(o.id))
	if not _rec_frozen and _rec_box.is_visible_in_tree() and not bool(_rec.collapsed) \
			and rec_seen_note(_rec_seen, _play_mode, shown, Recommender.now_local() / 86400):
		var scfg := ConfigFile.new()
		scfg.set_value("seen", "all", _rec_seen)
		scfg.save(REC_SEEN_PATH)


func _rec_spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Zeile ueber den Vorschlaegen: links das Stilprofil ("Your style: ..."),
## rechts Seite und "Show more".
func _rec_profile_row(profile: String, pages: int) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 20)
	row.add_theme_constant_override("separation", 10)
	var pl := _rec_label(row, profile, 12, Color(0.78, 0.80, 0.88))
	pl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if profile != "":
		pl.mouse_filter = Control.MOUSE_FILTER_PASS  # Tooltip: alle Teile des Profils
		var parts: Array = _rec_res.get("profile_parts", [])
		pl.tooltip_text = "%s\n%s" % [tr("Your style: %s") % ", ".join(parts),
			tr("From the maps you play in %s") % collection_mode_hint(_play_mode)]
	if pages > 1:
		var pg := _rec_label(row, "%d / %d" % [_rec_page + 1, pages], 12, COL_DIM)
		pg.clip_text = false
		pg.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		pg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var more := Button.new()
		more.text = tr("Show more")
		more.tooltip_text = tr("Show more suggestions")
		more.flat = true
		more.focus_mode = Control.FOCUS_NONE
		more.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		more.add_theme_font_size_override("font_size", 12)
		more.add_theme_color_override("font_color", COL_ACCENT)
		more.add_theme_color_override("font_hover_color", COL_TEXT)
		more.add_theme_color_override("font_pressed_color", COL_TEXT)
		more.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UiTheme._attach_sounds(more)
		more.pressed.connect(func():
			_rec_page += 1
			_recs_render())
		row.add_child(more)
	return row


## Ueberschrift der Online-Gruppe.
func _rec_online_caption() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 18)
	row.add_theme_constant_override("separation", 8)
	var cap := _rec_label(row, "Online", 13, COL_TEXT)
	cap.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cap.add_theme_font_override("font", UiTheme.heading_font(1))
	cap.clip_text = false
	cap.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hint := _rec_label(row, tr("Not in your library yet"), 12, COL_DIM)
	hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


# --- Online-Vorschlaege: Maps, die noch nicht in der Bibliothek liegen ---

## Liste der Online-Vorschlaege aus dem Cache ordnen und, wenn noetig und
## erlaubt, eine Mirror-Seite holen (still; ohne Netz bleibt die Gruppe weg).
func _rec_online_update() -> void:
	_rec_on_list = []
	var q: Dictionary = _rec_res.get("query", {})
	if q.is_empty() or _rec_frozen or _rec_net_off():
		return
	if not _rec_on_loaded:
		_rec_on_loaded = true
		var cfg := ConfigFile.new()
		if cfg.load(REC_ONLINE_PATH) == OK:
			var cv = cfg.get_value("online", "cache", {})
			_rec_on_cache = cv if cv is Dictionary else {}
	var key := str(q.key)
	var now := int(Time.get_unix_time_from_system())
	var cached := Recommender.online_cached(_rec_on_cache, key, now)
	if not cached.is_empty():
		var owned := OnlineBrowser.owned_set_ids(_library)
		var free: Array = []
		for r in cached:
			if OnlineBrowser.visible_result(r, owned, 0.0, 99.0, 0):
				free.append(r)
		_rec_on_list = Recommender.online_rank(q, _rec_res.get("taste", {}), free,
			REC_ONLINE_N * Recommender.PAGE_MAX,
			rec_seen_counts(_rec_seen, _play_mode, Recommender.now_local() / 86400))
	var page := Recommender.online_fetch_page(_rec_on_cache, key, now, _rec_on_list.size(), REC_ONLINE_N,
		_rec_on_fail_at)
	if page < 0:
		return
	_ensure_online()
	var osu_mode := int(q.osu_mode)
	var text := str(q.get("genre", ""))
	if text == "":
		text = "4k" if osu_mode == BeatmapMirror.MODE_MANIA else "a"
	_online.quiet_search(key, text, osu_mode, page * BeatmapMirror.PAGE_SIZE)


## Harness-Laeufe (--shot-...) und --no-rec-online fragen den Mirror nie;
## --rec-online erlaubt es einem Harness-Lauf ausdruecklich (Live-Pruefung).
func _rec_net_off() -> bool:
	if _arg_value("--rec-online") != null:
		return false
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot") or a == "--no-rec-online" or a == "--screenshot":
			return true
	return false


func _on_rec_online(tag: String, results: Array, ok: bool, raw_count: int) -> void:
	var now := int(Time.get_unix_time_from_system())
	if not ok:
		_rec_on_fail_at = now  # kein Netz: Gruppe bleibt einfach weg
		return
	_rec_on_fail_at = 0
	Recommender.online_cache_put(_rec_on_cache, tag, results, now, raw_count < BeatmapMirror.PAGE_SIZE)
	var cfg := ConfigFile.new()
	cfg.set_value("online", "cache", _rec_on_cache)
	cfg.save(REC_ONLINE_PATH)
	if not is_inside_tree() or _rec_box == null:
		return
	_rec_online_update()
	if str((_rec_res.get("query", {}) as Dictionary).get("key", "")) == tag:
		_recs_render()


func _rec_blank_tex() -> ImageTexture:
	if _rec_blank == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(UiTheme.RAISED)
		_rec_blank = ImageTexture.create_from_image(img)
	return _rec_blank


## Online-Kachel: Cover, Titel, Sterne + BPM, Grund. Klick = vorhoeren,
## "Get" laedt die Map ueber den Online-Browser (danach sofort gewaehlt).
func _rec_online_card(o: Dictionary) -> Control:
	var id := int(o.id)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, REC_TILE_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = true
	btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	btn.tooltip_text = "%s - %s\n%s\n%s" % [str(o.artist), str(o.title), str(o.reason), tr("Click to listen")]
	UiTheme._attach_sounds(btn)
	OrbitCareerPanel._style_row(btn, false)
	btn.pressed.connect(_rec_online_preview.bind(o))
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 9
	hb.offset_right = -9
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hb)
	var mir := get_node_or_null("/root/Mirror")
	var cover := TextureRect.new()
	var tex: Texture2D = mir.cached_cover(id) if mir != null and id > 0 else null
	cover.texture = tex if tex != null else _rec_blank_tex()
	cover.custom_minimum_size = Vector2(REC_COVER, REC_COVER)
	cover.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.material = _rec_cover_mat
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(cover)
	if tex == null and mir != null and id > 0 and str(o.get("cover_url", "")) != "":
		mir.fetch_cover(id, str(o.cover_url))
	var tb := VBoxContainer.new()
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tb.add_theme_constant_override("separation", 0)
	tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tb)
	_rec_label(tb, str(o.title), 13, COL_TEXT)
	var info := _stars_text(float(o.stars))
	if float(o.get("bpm", -1.0)) > 0.0:
		info += "  ·  %d BPM" % roundi(float(o.bpm))
	_rec_label(tb, info, 11, Color(0.78, 0.80, 0.88))
	var sub := _rec_label(tb, str(o.reason), 11, UiTheme.ACCENT2)
	var get_btn := Button.new()
	get_btn.text = tr("Get")
	get_btn.tooltip_text = tr("Download and play right away")
	get_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	get_btn.focus_mode = Control.FOCUS_NONE
	get_btn.custom_minimum_size = Vector2(52, 26)
	get_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	get_btn.add_theme_font_size_override("font_size", 12)
	UiTheme.style_ghost_button(get_btn, 13)
	get_btn.pressed.connect(_rec_online_get.bind(id))
	hb.add_child(get_btn)
	_rec_on_rows[id] = {"cover": cover, "get": get_btn, "sub": sub, "text": str(o.reason)}
	if mir != null and id > 0 and mir.is_downloading(id):
		_on_rec_dl_progress(id, mir.active_ratio(id))
	return btn


func _rec_online_preview(o: Dictionary) -> void:
	if int(o.id) <= 0:
		return
	_ensure_online()
	_online.preview_toggle({"id": int(o.id), "preview_url": str(o.get("preview_url", ""))})
	_rec_mark_preview()


## Kachel, deren Vorschau laeuft, zeigt das statt des Grundes.
func _rec_mark_preview() -> void:
	var cur := _online.preview_id() if _online != null else -1
	for id in _rec_on_rows:
		var row: Dictionary = _rec_on_rows[id]
		if is_instance_valid(row.sub):
			(row.sub as Label).text = tr("Playing preview") if cur > 0 and int(id) == cur else str(row.text)


func _rec_online_get(id: int) -> void:
	if id <= 0:
		return
	_ensure_online()
	_online.start_download(id)  # gleicher Weg wie im Online-Tab; fertig -> _on_online_downloaded
	_on_rec_dl_progress(id, 0.0)


func _on_rec_cover(set_id: int, texture: Texture2D) -> void:
	var row = _rec_on_rows.get(set_id)
	if row != null and is_instance_valid(row.cover) and texture != null:
		(row.cover as TextureRect).texture = texture


func _on_rec_dl_progress(set_id: int, ratio: float) -> void:
	var row = _rec_on_rows.get(set_id)
	if row != null and is_instance_valid(row.get):
		(row.get as Button).disabled = true
		(row.get as Button).text = "%d %%" % roundi(clampf(ratio, 0.0, 1.0) * 100.0)


func _on_rec_dl_failed(set_id: int, message: String) -> void:
	var row = _rec_on_rows.get(set_id)
	if row != null and is_instance_valid(row.get):
		(row.get as Button).disabled = false
		(row.get as Button).text = tr("Retry")
		(row.get as Button).tooltip_text = message


## Harness --shot-recs[=Seite] [--shot-out=<png>]: "For you" mit festem
## Beispiel (Maps der Bibliothek, Beispiel-Profil, Online-Gruppe ohne Netz).
func _shot_recs() -> void:
	_rec_frozen = true
	_state_ready = false  # nichts speichern
	_rec["hidden"] = false
	_rec["collapsed"] = false
	var t := {"total": 10.0, "maps": 12, "style": {"jumpstream": 0.42, "stream": 0.2, "jack": 0.05},
		"sv": -1.0, "bpm_lo": 172.0, "bpm_hi": 188.0, "stars_lo": 2.4, "stars_hi": 3.1,
		"genres": {"electronic": 6.0}, "languages": {"japanese": 5.0}, "mappers": {"kira": 3.0},
		"length": 142.0}
	var fits := [
		tr("fits: %s") % ", ".join(["180 BPM", tr("Jumpstream"), tr("like %s") % "Night Drive"]),
		tr("fits: %s") % ", ".join(["176 BPM", tr("Streams")]),
		tr("fits: %s") % ", ".join([tr("Jumpstream"), tr("mapped by %s") % "Kira"]),
		"",
	]
	var job := _recs_job()
	var items: Array = []
	var sets := {}
	for c in job.cands:
		if sets.has(c.set) or items.size() >= 18:
			continue
		sets[c.set] = true
		items.append({"set": c.set, "diff": c.diff, "stars": float(c.stars),
			"expected_acc": 0.91 - 0.004 * items.size(), "reason": "",
			"style_reason": fits[items.size() % fits.size()]})
	_rec_res = {"mode": _play_mode, "starter": false, "items": items, "comfort": 2.6, "taste": t,
		"profile": Recommender.profile_text(t, 6), "profile_parts": Recommender.profile_parts(t), "query": {}}
	_rec_on_list = []
	var names := ["Glass Harbor", "Second Sun", "Paper Planes at Night", "Low Tide", "Amber Signal",
		"Slow Circuit", "Northern Line", "Quiet Engine", "Field Notes"]
	for i in names.size():
		_rec_on_list.append({"id": -(i + 1), "title": names[i], "artist": "Artist %d" % (i + 1),
			"creator": "Mapper", "stars": 2.6 + 0.1 * (i % 5), "osu_stars": 2.6 + 0.1 * (i % 5),
			"bpm": 170.0 + 4.0 * (i % 4), "length": 140.0, "cover_url": "", "preview_url": "",
			"reason": fits[i % 3] if i % 3 != 2 else tr("in your star range")})
	_rec_page = int(str(_arg_value("--shot-recs")))
	_recs_render()
	_capture_screenshot_and_quit()


## Wert von --name bzw. --name=<wert> auf der Kommandozeile; null = fehlt.
func _arg_value(name: String) -> Variant:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == name:
			return ""
		if a.begins_with(name + "="):
			return a.trim_prefix(name + "=")
	return null


## Karte wie die Orbit-Karriere "Up next": Cover, Titel, Diff, Sterne, Grund.
## wide = volle Zeile (hohe Fenster), sonst Kachel (drei nebeneinander).
func _rec_card(it: Dictionary, wide: bool) -> Control:
	var ms: MapSet = it.ms
	var diff := int(it.diff)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, REC_ROW_H if wide else REC_TILE_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_stretch_ratio = 1.0
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = true
	btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	btn.tooltip_text = "%s - %s [%s]\n%s" % [ms.artist, ms.title, ms.version_name_at(diff).strip_edges(),
		_rec_reason(it)]
	UiTheme._attach_sounds(btn)
	OrbitCareerPanel._style_row(btn, false)
	btn.pressed.connect(_on_rec_picked.bind(ms, diff))
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 9
	hb.offset_right = -12
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hb)
	var cover := TextureRect.new()
	cover.texture = ms.thumb_texture()
	cover.custom_minimum_size = Vector2(REC_COVER, REC_COVER)
	cover.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.material = _rec_cover_mat
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(cover)
	var tb := VBoxContainer.new()
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tb.add_theme_constant_override("separation", 1 if wide else 0)
	tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tb)
	var reason := _rec_reason(it)
	var push := rec_level(_rec, _play_mode) == Recommender.LEVEL_PUSH \
			and not bool(_rec_res.get("starter", false))
	var reason_col := COL_ACCENT if push else UiTheme.ACCENT2
	var stars_txt := _stars_text(float(it.stars))
	var ver := ms.version_name_at(diff).strip_edges()
	if wide:
		_rec_label(tb, "%s - %s" % [ms.artist, ms.title], 15, COL_TEXT)
		_rec_label(tb, ver, 12, COL_DIM)
		var right := VBoxContainer.new()
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		right.add_theme_constant_override("separation", 1)
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(right)
		var st := _rec_label(right, stars_txt, 15, COL_TEXT)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		st.clip_text = false
		st.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		var rs := _rec_label(right, reason, 11, reason_col)
		rs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rs.clip_text = false
		rs.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	else:
		# Kachel: Titel + Sterne, darunter der Grund auf bis zu zwei Zeilen.
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tb.add_child(top)
		var tl := _rec_label(top, ms.title, 13, COL_TEXT)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sl := _rec_label(top, stars_txt, 11, Color(0.78, 0.80, 0.88))
		sl.clip_text = false
		sl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var rl := _rec_label(tb, _rec_reason_short(it), 11, reason_col)
		rl.clip_text = false
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.max_lines_visible = 2
		rl.add_theme_constant_override("line_spacing", 0)
	_rec_rows.append({"btn": btn, "ms": ms, "diff": diff})
	return btn


func _rec_label(parent: Node, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Grund kurz: Push behaelt den Recommender-Text ("+14 pp, would be top 3"),
## Easy/Challenge zeigen nur die erwartete Genauigkeit.
func _rec_reason(it: Dictionary) -> String:
	var base := str(it.reason)
	if not (bool(_rec_res.get("starter", false)) or float(it.acc) < 0.0 \
			or rec_level(_rec, _play_mode) == Recommender.LEVEL_PUSH):
		base = tr("expected %d %%") % roundi(float(it.acc) * 100.0)
	return rec_join_reason(base, str(it.get("style", "")))


## Grund fuer die schmale Kachel: "89 %  ·  fits: 180 BPM, Streams" statt
## "expected 89 %  ·  fits: ...".
func _rec_reason_short(it: Dictionary) -> String:
	var style := str(it.get("style", ""))
	if style == "" or bool(_rec_res.get("starter", false)) or float(it.acc) < 0.0 \
			or rec_level(_rec, _play_mode) == Recommender.LEVEL_PUSH:
		return _rec_reason(it)
	return "%d %%  ·  %s" % [roundi(float(it.acc) * 100.0), style]


## Grund + Stil-Grund ("expected 89 %  ·  fits: 180 BPM, Jumpstream").
static func rec_join_reason(base: String, style: String) -> String:
	if style == "":
		return base
	return style if base == "" else "%s  ·  %s" % [base, style]


func _on_rec_picked(ms: MapSet, diff: int) -> void:
	if _selected_set == ms and _selected_diff == diff:
		_on_play_pressed()
		return
	_select_set(ms, diff)
	if _filtered.has(ms):
		_scroll_to_selected()


func _recs_mark_selected() -> void:
	for r in _rec_rows:
		if is_instance_valid(r.btn):
			OrbitCareerPanel._style_row(r.btn as Button,
				r.ms == _selected_set and int(r.diff) == _selected_diff)
