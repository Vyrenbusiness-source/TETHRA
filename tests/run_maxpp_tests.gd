extends SceneTree

## Max-pp (SS) einer Mania-Diff = rosu-pp mit allen Noten MAX (n_geki).
## Regression: bis v1.32.0 lief die Berechnung mit n300 und lag ~31 % zu tief.

const OSZ := "res://maps/1566829 Purukichi - Luster.osz"
var _failed := 0


func _check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		_failed += 1


func _initialize() -> void:
	print("MaxPP-Tests")
	if not FileAccess.file_exists(OSZ):
		print("  SKIP Test-Map fehlt (maps/ ist nicht im Repo)")
		quit(0)
		return
	var inner := ""
	var zr := ZIPReader.new()
	if zr.open(ProjectSettings.globalize_path(OSZ)) == OK:
		for f in zr.get_files():
			if f.ends_with("[Shimmer].osu"):
				inner = f
		zr.close()
	_check(inner != "", "Test-Diff gefunden")
	if inner != "":
		var notes := 2948
		var ss := StarService.pp_for_mania(OSZ, inner, notes, 0, 0, 0, 0, 0, 0)
		var all300 := StarService.pp_for(OSZ, inner, notes, 0, 0, 0, 0)
		var mx := StarService.max_pp_for(OSZ, inner, notes)
		_check(ss.has("pp") and absf(float(ss.pp) - 274.3) < 1.0, "SS = alle MAX ~ 274,3 pp (rosu-pp stable)")
		_check(absf(mx - float(ss.get("pp", -1.0))) < 0.01, "max_pp_for = SS (%.1f)" % mx)
		_check(mx > float(all300.get("pp", 0.0)) * 1.3, "max_pp_for nicht mehr die n300-Rechnung (%.1f)" % float(all300.get("pp", 0.0)))
	quit(1 if _failed > 0 else 0)
