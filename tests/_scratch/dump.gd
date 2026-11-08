extends SceneTree
func _initialize() -> void:
	var mdir := MapLibrary.default_maps_dir()
	for f in DirAccess.open(mdir).get_files():
		if f.find("goreshit - burn") < 0 or not f.ends_with(".osz"): continue
		var imp := OszImporter.import(mdir.path_join(f))
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if bm.is_mania() and bm.column_count() == 4 and bm.version_name() == "fear":
				var ns := OrbitConverter.convert(bm)
				var prev := 0.0
				for n in ns:
					if n.time_ms > 302000 and n.time_ms < 304500:
						var col = bm.hit_objects[n.source_index].column
						print("%.0f gap %3.0f col %d ang %6.1f ring %d" % [n.time_ms, n.time_ms-prev, col, n.angle_deg, n.ring])
						prev = n.time_ms
	quit(0)
