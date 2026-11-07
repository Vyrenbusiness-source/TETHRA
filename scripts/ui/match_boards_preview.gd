extends Control

## Testszene fuer TeamBoard, RoyaleBoard und LiveTeamBar mit Fake-Daten.
## Flag --shot (oder shot) speichert Bilder und beendet sich selbst.

const SHOT_DIR := "C:/Users/Gexanx/AppData/Local/Temp/claude/a8d2df055934fb12/ae75c784-ae79-4c4a-9f0e-4dc40caac225/scratchpad/"
const NAMES := ["Mika", "Jonas", "Lea", "Tom", "Nora", "Ben"]


func _ready() -> void:
	get_window().theme = UiTheme.build_theme()
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.06, 0.11)
	add_child(bg)

	var bar := LiveTeamBar.new()
	add_child(bar)
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.offset_left = -300.0
	bar.offset_right = 300.0
	bar.offset_top = 16.0
	bar.offset_bottom = 62.0
	bar.setup({"names": ["Rot", "Blau"], "totals": [412300, 398100]})

	var tb := TeamBoard.new()
	add_child(tb)
	tb.position = Vector2(24, 90)
	tb.size = Vector2(600, 590)
	var players: Array = []
	for i in 5:
		players.append({"peer": i + 1, "name": NAMES[i], "team": 0 if i < 3 else 1, "score": 120000 + i * 31000})
	tb.setup({"names": ["Rot", "Blau"], "players": players, "totals": [412300, 398100],
			"hint": "Ungleiche Teams: 3 gegen 2."})
	tb.team_requested.connect(func(peer, team):
		for p in players:
			if p.peer == peer:
				p.team = team
		tb.setup({"names": ["Rot", "Blau"], "players": players, "hint": ""}))

	var rb := RoyaleBoard.new()
	add_child(rb)
	rb.position = Vector2(656, 90)
	rb.size = Vector2(600, 590)
	var rp: Array = []
	for i in 6:
		rp.append({"peer": i + 1, "name": NAMES[i], "alive": i != 5, "out_round": 1 if i == 5 else 0, "score": 900000 - i * 80000})
	rb.setup({"round": 2, "players": rp, "danger": 5, "final": false})

	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		_eliminate(rb, rp)
		await get_tree().process_frame
		bar.set_totals([500000, 410000])
		tb.set_totals([500000, 410000])
		await get_tree().process_frame
		print("=== MatchBoardsPreview Headless OK ===")
		get_tree().quit(0)
	elif OS.get_cmdline_args().has("--shot") or OS.get_cmdline_args().has("shot"):
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		_save("match_boards_a.png")
		_eliminate(rb, rp)
		bar.set_totals([520000, 430000])
		tb.set_totals([520000, 430000])
		await get_tree().create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		_save("match_boards_b.png")
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		_save("match_boards_c.png")
		get_tree().quit(0)


func _eliminate(rb: RoyaleBoard, rp: Array) -> void:
	rp[4].alive = false
	rp[4].out_round = 2
	rb.setup({"round": 3, "players": rp, "danger": 3, "final": false})


func _save(fname: String) -> void:
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + fname)
	print("SHOT gespeichert: " + SHOT_DIR + fname)
