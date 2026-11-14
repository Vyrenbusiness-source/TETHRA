class_name RuleMods
extends RefCounted

## Regel-Mods fuer Mania (und Trace/Rebound, die ManiaCore nutzen):
##   "SD" Sudden Death: der erste Miss beendet den Lauf (Fail-Bild "Sudden Death: Miss").
##   "PF" Perfect: schon alles unter 300 beendet den Lauf (MAX und 300 sind ok).
##   "MN" Minen: der Konverter MineGen setzt Minen in freie Spalten; Druck/Halten beim
##        Durchlauf = Miss (Kombo bricht, HP sinkt), Acc unveraendert. "MN_v" = Version
##        des Konverters (Replay-Marke: alte Replays bauen dieselben Minen).
## SD und PF schliessen No Fail aus (und einander: PF enthaelt SD). Wertung: SD/PF normal
## (Faktor 1,0, ranked, pp wie ohne Mod). MN: eigene Rangliste (Score-Modus "mania_mn"),
## keine pp. Gegen ManiaCore nur kleine Haken: setup_core, check, mine_hit-Pfad, Stats.

const SD := "SD"
const PF := "PF"
const MN := "MN"
const MN_VERSION_KEY := "MN_v"
## Schalter im Song-Browser in dieser Reihenfolge.
const KEYS: Array[String] = ["SD", "PF", "MN"]
## Modi, in denen ein Schalter erscheint und wirkt.
const MODES := {
	"SD": ["mania", "trace", "rebound"],
	"PF": ["mania", "trace", "rebound"],
	"MN": ["mania"],
}
## Score-Modus (ScoreStore) fuer Laeufe mit Minen: eigene Rangliste.
const MINES_SCORE_MODE := "mania_mn"


static func has(mods: Dictionary, key: String) -> bool:
	return bool(mods.get(key, false))


## true, wenn der Mod im Spielmodus angeboten wird.
static func available(key: String, play_mode: String) -> bool:
	return (MODES.get(key, []) as Array).has(play_mode)


## Abbruch-Regel aktiv (SD oder PF)?
static func is_rule(mods: Dictionary) -> bool:
	return has(mods, SD) or has(mods, PF)


## Mods bereinigen: PF schlaegt SD, SD/PF schalten NF aus. Neues Dictionary.
static func normalize(mods: Dictionary) -> Dictionary:
	var out := mods.duplicate()
	if has(out, PF):
		out.erase(SD)
	if is_rule(out):
		out.erase("NF")
	if has(out, MN) and not out.has(MN_VERSION_KEY):
		out[MN_VERSION_KEY] = MineGen.VERSION
	return out


## Browser-Schalter umlegen: liefert die neue Regel-Auswahl {SD, PF, MN}. SD und PF
## schliessen einander aus. Ob NF aus muss, sagt clears_nf().
static func toggle(sel: Dictionary, key: String, on: bool) -> Dictionary:
	var out := sel.duplicate()
	out[key] = on
	if on and key == SD:
		out[PF] = false
	elif on and key == PF:
		out[SD] = false
	return out


## Schaltet dieser Mod No Fail aus?
static func clears_nf(key: String) -> bool:
	return key == SD or key == PF


## No Fail an: SD/PF fallen weg.
static func on_no_fail(sel: Dictionary) -> Dictionary:
	var out := sel.duplicate()
	out[SD] = false
	out[PF] = false
	return out


## Regel-Auswahl des Browsers in die Start-Mods des Spielmodus mischen.
static func apply(base: Dictionary, sel: Dictionary, play_mode: String) -> Dictionary:
	var out := base.duplicate()
	for k in KEYS:
		if bool(sel.get(k, false)) and available(k, play_mode):
			out[k] = true
	return normalize(out)


## Mods fuer einen Spielmodus: Regel-Mods, die dort nicht wirken, fallen weg (MN nur in
## Mania), dann normalize(). Lobby-Runden: Raum-Mods -> GameSession.mods.
static func for_mode(mods: Dictionary, play_mode: String) -> Dictionary:
	var out := mods.duplicate()
	for k in KEYS:
		if out.has(k) and not available(k, play_mode):
			out.erase(k)
	if not has(out, MN):
		out.erase(MN_VERSION_KEY)
	return normalize(out)


## Lobby-Raum-Mods bereinigen: SV, NF immer als bool; SD/PF/MN nur, wenn an. PF schlaegt
## SD, SD/PF schalten NF aus. MN traegt die Konverter-Version des Hosts ("MN_v"), damit
## alle im Raum (und ihre Replays) dieselben Minen bauen.
static func lobby_norm(m: Dictionary) -> Dictionary:
	var out := {"SV": bool(m.get("SV", false)), "NF": bool(m.get("NF", false))}
	for k in KEYS:
		if bool(m.get(k, false)):
			out[k] = true
	if has(out, PF):
		out.erase(SD)
	if is_rule(out):
		out["NF"] = false
	if has(out, MN):
		out[MN_VERSION_KEY] = int(m.get(MN_VERSION_KEY, MineGen.VERSION))
	return out


## Lobby-Schalter umlegen (SV, NF, SD, PF, MN): neue Raum-Mods. SD und PF schliessen
## einander und No Fail aus; No Fail an schaltet SD/PF aus.
static func lobby_toggle(mods: Dictionary, key: String) -> Dictionary:
	var out := mods.duplicate()
	var on := not bool(out.get(key, false))
	out[key] = on
	if on and key == "NF":
		out.erase(SD)
		out.erase(PF)
	elif on and clears_nf(key):
		out["NF"] = false
		out.erase(PF if key == SD else SD)
	if not on and key != "SV" and key != "NF":
		out.erase(key)
	return lobby_norm(out)


## Kuerzel aktiver Regel-Mods in fester Reihenfolge (SD, PF, MN) fuer Texte/Listen.
static func keys_on(mods: Dictionary) -> Array:
	var out := []
	for k in KEYS:
		if has(mods, k):
			out.append(k)
	return out


## ManiaCore.setup-Haken: Mods bereinigen, NF aus bei SD/PF, Faktor neu, Minen bauen.
static func setup_core(core: ManiaCore) -> void:
	core.mods = normalize(core.mods)
	if is_rule(core.mods):
		core.no_fail = false
	core.mod_mult = ManiaCore.mod_multiplier(core.mods)
	core.fail_rule = ""
	core.fail_what = ""
	core.n_mine_hit = 0
	core.mines = null
	if has(core.mods, MN) and core.beatmap != null:
		var mm := ManiaMines.new()
		mm.setup(MineGen.generate(core.beatmap, core.columns,
				int(core.mods.get(MN_VERSION_KEY, MineGen.VERSION))), core.columns)
		core.mines = mm


## Bricht diese Wertung die Regel? "" = nein, sonst "SD" bzw. "PF".
static func breaks(mods: Dictionary, quality: int) -> String:
	if has(mods, PF) and quality > ManiaCore.Quality.PERFECT:
		return PF
	if has(mods, SD) and quality == ManiaCore.Quality.MISS:
		return SD
	return ""


## Kurzname der Wertung fuer den Abbruch-Grund (Miss, 200, 100, 50, Mine).
static func what_tag(quality: int, kind: String = "") -> String:
	if kind == "MINE":
		return "Mine"
	if quality >= ManiaCore.Quality.MISS:
		return "Miss"
	return ["MAX", "300", "200", "100", "50"][quality]


## Eine Zeile fuers Fail-Bild ("Sudden Death: Miss", "Perfect: 200"), "" ohne Regel-Abbruch.
static func fail_reason(core: ManiaCore) -> String:
	if core == null or core.fail_rule == "":
		return ""
	_ensure_translations()
	var name := "Sudden Death" if core.fail_rule == SD else "Perfect"
	# Nur "Mine" uebersetzen: "Miss" wird anderswo als "miss" uebersetzt, Zahlen bleiben.
	var what: String = TranslationServer.translate(core.fail_what) if core.fail_what == "Mine" else core.fail_what
	return "%s: %s" % [name, what]


## HUD-Teile ("Sudden Death", "Perfect", "Mines") in fester Reihenfolge.
static func hud_parts(mods: Dictionary) -> Array:
	_ensure_translations()
	var out := []
	if has(mods, SD):
		out.append("Sudden Death")
	if has(mods, PF):
		out.append("Perfect")
	if has(mods, MN):
		out.append(TranslationServer.translate("Mines"))
	return out


## Keine pp fuer diesen Lauf (Minen: Map ist nicht mehr die gewertete Map).
static func no_pp(mods: Dictionary) -> bool:
	return has(mods, MN)


## ScoreStore-Modus eines Mania-Laufs: "" (Mania) oder "mania_mn" (eigene Rangliste).
static func score_mode(mods: Dictionary) -> String:
	return MINES_SCORE_MODE if has(mods, MN) else ""


## Zusatzfelder fuer ManiaCore.stats() (nur mit Minen).
static func extend_stats(core: ManiaCore, d: Dictionary) -> void:
	if core.mines != null:
		d["mines"] = core.mines.count()
		d["mine_hits"] = core.n_mine_hit
	if core.fail_rule != "":
		d["fail_rule"] = core.fail_rule


## Mods fuers Replay: Start-Mods plus die Konverter-Version der Minen aus dem Lauf
## (falls der Start ohne MN_v kam), damit das Replay dieselben Minen baut.
static func replay_mods(session_mods: Dictionary, core_mods: Dictionary) -> Dictionary:
	var out := session_mods.duplicate()
	if has(core_mods, MN) and not out.has(MN_VERSION_KEY):
		out[MN_VERSION_KEY] = int(core_mods.get(MN_VERSION_KEY, MineGen.VERSION))
	return out


## Zusatzfelder fuer POST /score (OnlineApi.build_body): Minen-Zaehler, pp 0.
static func extend_body(body: Dictionary, result: Dictionary) -> void:
	var mods: Array = body.get("mods", [])
	if not mods.has(MN):
		return
	body["pp"] = 0.0
	# Bis der Server "board" kennt: nicht in die normale Mania-Liste (er rechnet pp selbst).
	body["ranked"] = false
	body["board"] = MINES_SCORE_MODE
	body["mines"] = int(result.get("mines", 0))
	body["mine_hits"] = int(result.get("mine_hits", 0))


## Song-Browser: Score-Modus der Liste unter BESTE SCORES. mode_score = bisheriger
## Modus der Liste ("" Mania, "orbit", "trace" ...); Minen nur in Mania.
static func board_mode(mode_score: String, sel: Dictionary) -> String:
	var m := "" if mode_score == "mania" else mode_score
	if m == "" and bool(sel.get(MN, false)):
		return MINES_SCORE_MODE
	return m


static func is_mines_board(score_mode: String) -> bool:
	return score_mode == MINES_SCORE_MODE


## Kennzeichnung der Minen-Liste im Ranglisten-Kopf ("Mania 4K · Mines").
static func board_tag(score_mode: String) -> String:
	_ensure_translations()
	if is_mines_board(score_mode):
		return "Mania 4K · " + TranslationServer.translate("Mines")
	return ScoreStore.mode_label(score_mode)


## Kennt der Server die eigene Liste? Nur wenn seine Antwort "board" zurueckgibt
## (GET /leaderboard?...&board=mania_mn). Sonst kaeme die normale Mania-Liste.
static func online_board_known(reply: Dictionary) -> bool:
	return str(reply.get("board", "")) == MINES_SCORE_MODE


## Hinweise der Minen-Liste (Englisch Quelle, Deutsch in mv_rules.csv).
static func board_text(key: String) -> String:
	_ensure_translations()
	match key:
		"empty":
			return TranslationServer.translate("No Mines score yet. Play the map!")
		"online_soon":
			return TranslationServer.translate("Online leaderboard for Mines coming soon")
		"tip":
			return TranslationServer.translate("Only runs with Mines (own leaderboard, no pp)")
	return ""


## Ruhige Zeile fuer den Ueberblick im Ergebnis ("Minen 42 · ausgeloest 3"), "" ohne Minen.
static func mines_line(stats: Dictionary) -> String:
	if not stats.has("mines"):
		return ""
	_ensure_translations()
	return "%s %s  ·  %s %s" % [TranslationServer.translate("Mines"), UiTheme.fmt_score(int(stats.get("mines", 0))),
		TranslationServer.translate("triggered"), UiTheme.fmt_score(int(stats.get("mine_hits", 0)))]


## Details-Reiter: [Titel, Wert] je Minen-Kennzahl (gesamt, ausgeloest, ausgewichen).
static func mines_cells(stats: Dictionary) -> Array:
	if not stats.has("mines"):
		return []
	_ensure_translations()
	var total := int(stats.get("mines", 0))
	var hits := int(stats.get("mine_hits", 0))
	return [
		[TranslationServer.translate("Mines total"), UiTheme.fmt_score(total)],
		[TranslationServer.translate("triggered"), UiTheme.fmt_score(hits)],
		[TranslationServer.translate("dodged"), UiTheme.fmt_score(maxi(total - hits, 0))],
	]


## Mod-Kennzeichen im Ergebnis-Kopf: "SD", "PF", "Mines".
static func badge_texts(mods: Dictionary) -> Array:
	var out := []
	for k in keys_on(mods):
		out.append(label(k))
	return out


## Full Combo nur ohne Miss UND ohne ausgeloeste Mine.
static func clean_run(stats: Dictionary) -> bool:
	return int(stats.get("n_miss", 1)) == 0 and int(stats.get("mine_hits", 0)) == 0


## Tooltip je Schalter (Englisch als Quelle, Deutsch in translations/mv_rules.csv).
static func tip(key: String) -> String:
	_ensure_translations()
	match key:
		SD:
			return TranslationServer.translate("Sudden Death: the first miss ends the run")
		PF:
			return TranslationServer.translate("Perfect: anything below 300 ends the run")
		MN:
			return TranslationServer.translate("Mines: do not press or hold where a mine passes. Own leaderboard, no pp")
	return ""


## Text auf dem Schalter.
static func label(key: String) -> String:
	_ensure_translations()
	match key:
		SD:
			return "SD"
		PF:
			return "PF"
		MN:
			return TranslationServer.translate("Mines")
	return key


## Text auf dem Lobby-Schalter (ausgeschrieben wie "No-Fail").
static func lobby_label(key: String) -> String:
	_ensure_translations()
	match key:
		SD:
			return "Sudden Death"
		PF:
			return "Perfect"
		MN:
			return TranslationServer.translate("Mines")
	return key


static var _tr_loaded := false


## translations/mv_rules.csv auch ohne Eintrag in project.godot laden (Tests, alte Builds).
static func _ensure_translations() -> void:
	if _tr_loaded:
		return
	_tr_loaded = true
	for loc in ["de", "en"]:
		var path := "res://translations/mv_rules.%s.translation" % loc
		if ResourceLoader.exists(path):
			var tr_res := load(path) as Translation
			if tr_res != null:
				TranslationServer.add_translation(tr_res)
