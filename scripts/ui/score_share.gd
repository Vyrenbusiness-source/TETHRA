class_name ScoreShare
extends RefCounted
## "Score teilen": Knopf, der nur sichtbar ist, wenn der Score eine Server-ID
## (online_id) hat. Ruft GameSession.chat.share_score.

## online_id des Laufs (osz_file + Diff + Score) aus den letzten Laeufen, sonst "".
static func find_online_id(osz_file: String, version: String, score: int, mode: String = "") -> String:
	for e in ScoreStore.recent_plays(12, mode):
		if str(e.get("osz_file", "")) == osz_file.get_file() and str(e.get("version", "")) == version \
				and int(e.get("score", 0)) == score:
			var oid := str(e.get("online_id", ""))
			if oid != "":
				return oid
	return ""


static func share(score_id: String, summary: String = "") -> void:
	if score_id == "" or GameSession.chat == null:
		return
	GameSession.chat.call("share_score", score_id, summary)


## Knopf anlegen; zeigt sich, sobald die online_id da ist (Upload laeuft nach dem Lauf).
static func make_button(osz_file: String, version: String, score: int, mode: String,
		summary: String, style_cb: Callable) -> Button:
	var b := Button.new()
	b.name = "ShareScoreButton"
	b.text = b.tr("Score teilen")
	b.tooltip_text = b.tr("Schickt den Score als Link in den Chat")
	b.custom_minimum_size = Vector2(170, 40)
	style_cb.call(b)
	b.visible = false
	var upd := func():
		if not is_instance_valid(b):
			return
		var oid := find_online_id(osz_file, version, score, mode)
		b.visible = oid != ""
		b.set_meta("oid", oid)
	b.pressed.connect(func(): share(str(b.get_meta("oid", "")), summary))
	upd.call()
	var api: OnlineApi = GameSession.online
	if api != null:
		api.state_changed.connect(upd)
		b.tree_exiting.connect(func():
			if api.state_changed.is_connected(upd):
				api.state_changed.disconnect(upd))
	return b
