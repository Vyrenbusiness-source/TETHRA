extends SceneTree
func _init() -> void:
	for p in ["C:/Users/Gexanx/Downloads/# - tekkito2 ft jb the voice tu perfume a chanel.osk", "C:/Users/Gexanx/Downloads/Unknown.osk"]:
		var nm := ManiaSkin.import_skin(p)
		print("IMPORT ", p.get_file(), " -> '", nm, "' err=", ManiaSkin.last_error)
		var s := ManiaSkin.load_skin(nm)
		if s == null:
			print("  load null"); continue
		print("  v=", s.version, " cs=", s.column_start, " has=", s.has_column_start, " hp=", s.hit_position, " w=", s.column_width, " sp=", s.column_spacing, " lw=", s.column_line_width, " body=", s.note_body_style, " kun=", s.keys_under_notes, " sc=", s.score_position, " co=", s.combo_position, " jl=", s.judgement_line, " cols=", s.colours, " hold=", s.colour_hold)
		for k in ["note_0","note_1","head_0","body_0","tail_0","key_0","keyd_0","stage_left","stage_right","stage_hint","stage_bottom","stage_light","lighting_n","lighting_l","hit300g","hit300","hit200","hit100","hit50","hit0"]:
			var t := s.tex(k)
			print("  ", k, " ", s._names.get(k, "?"), " -> ", (str(t.get_width()) + "x" + str(t.get_height())) if t else "null", " s=", s.tex_scale(k))
		for d in 3:
			var r := s.tex_named(s.combo_prefix + "-" + str(d))
			print("  combo ", d, " ", r[0].get_size() if r[0] else null, " ", r[1])
	quit()
