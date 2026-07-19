extends SceneTree

## Validiert den Importer/Parser gegen die echten .osz im maps-Ordner.
## Ausfuehren:
##   Godot..._console.exe --headless --path . --script res://tests/validate_real_maps.gd

const MAPS_DIR := "C:/Users/Gexanx/Desktop/rhyg/maps"

func _initialize() -> void:
	print("=== Echte Maps validieren ===")
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		print("Kann maps-Ordner nicht oeffnen: " + MAPS_DIR)
		quit(1)
		return
	var total_ok := 0
	var total_fail := 0
	for fname in dir.get_files():
		if not fname.to_lower().ends_with(".osz"):
			continue
		var path := MAPS_DIR + "/" + fname
		print("\n[.osz] " + fname)
		var imp := OszImporter.import(path)
		if not imp.ok:
			print("  ABGELEHNT: " + imp.error)
			total_fail += 1
			continue
		total_ok += 1
		print("  Difficulties: %d" % imp.difficulties.size())
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			var circles := 0
			var sliders := 0
			var spinners := 0
			for o in bm.hit_objects:
				match o.kind:
					HitObject.Kind.CIRCLE: circles += 1
					HitObject.Kind.SLIDER: sliders += 1
					HitObject.Kind.SPINNER: spinners += 1
			var last_time := 0.0
			if bm.hit_objects.size() > 0:
				last_time = bm.hit_objects[bm.hit_objects.size() - 1].end_time()
			print("    [%s] v%d | %s - %s | CS%.1f AR%.1f OD%.1f | %d Objs (%dC/%dS/%dSp) | TP:%d Kiai:%d | Ende ~%.1fs | Audio:%s" % [
				bm.version_name(), bm.format_version, bm.artist(), bm.title(),
				bm.cs(), bm.ar(), bm.od(),
				bm.hit_objects.size(), circles, sliders, spinners,
				bm.timing_points.size(), bm.kiai_intervals.size(),
				last_time / 1000.0, bm.audio_filename()])
	print("\n=== %d Archive ok, %d abgelehnt ===" % [total_ok, total_fail])
	quit(0)
