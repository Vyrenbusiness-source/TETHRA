extends SceneTree
func _initialize() -> void:
	var T = load("res://tests/run_orbit_tests.gd").new()
	var ns: Array[OrbitNote] = OrbitConverter.convert(T._mixed_map())
	var p1 = OrbitCore.bot_plan(ns, 7, 24.0, 5.0)
	var sub: Array[OrbitNote] = []
	for j in range(912, 919):
		var n := OrbitNote.new()
		n.time_ms = ns[j].time_ms; n.end_ms = ns[j].end_ms; n.angle_deg = ns[j].angle_deg; n.end_angle_deg = ns[j].end_angle_deg; n.ring = ns[j].ring; n.is_arc = ns[j].is_arc
		sub.append(n)
	var pl = p1.slice(912, 919)
	var c: OrbitCore = T._bot_run(sub, 8.0, 5.0, pl)
	for i in sub.size():
		print(i, " ", c._judged.get(i))
	quit()
