extends Control

## Screenshot-Harness fuer Holds mit osu!mania-Skins: Playfield2D mit festen Fake-Holds
## (kurz, lang, ueberlappend, gehalten, losgelassen, oben angeschnitten) und die
## Einstellungs-Vorschau (PlayfieldPreview) je Skin. Selbst-beendend:
##   godot --path . --position -1920,0 --audio-driver Dummy res://scenes/skin_hold_harness.tscn \
##       -- --out=<dir> [--skins=a|b|c] [--style=0|1]
## Ohne --skins: alle Skins aus user://skins plus Built-ins plus "" (eingebauter Look).

const ZL := 3.0
const ZF := -46.0

var _out := "user://skinholdshots"
var _pf: Playfield2D
var _saved_skin := ""
var _saved_style := 0


func _ready() -> void:
	var names: Array = []
	var style := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--skins="):
			names = Array(a.trim_prefix("--skins=").split("|"))
		elif a.begins_with("--style="):
			style = int(a.trim_prefix("--style="))
	if names.is_empty():
		names = Array(ManiaSkin.list_skins())
		names.append("")
	DirAccess.make_dir_recursive_absolute(_out)
	_saved_skin = Settings.skin_2d
	_saved_style = Settings.note_style_2d
	if style >= 0:
		Settings.note_style_2d = style
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.3, 0.35)   # mittelgrau: Transparenz und schwarze Kanten sichtbar
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for nm in names:
		await _shoot(String(nm))
	Settings.skin_2d = _saved_skin
	Settings.note_style_2d = _saved_style
	get_tree().quit()


func _tag(nm: String) -> String:
	var t := ManiaSkin.safe_name(nm.trim_prefix(ManiaSkin.BUILTIN_PREFIX)).strip_edges()
	t = t.replace(" ", "_")
	return t if t != "" else "none_s%d" % Settings.note_style_2d


func _shoot(nm: String) -> void:
	var tag := _tag(nm)
	# --- Spiel ---
	_pf = Playfield2D.new()
	add_child(_pf)
	var keys := PackedStringArray(["D", "F", "J", "K"])
	_pf.setup(4, Settings.lane_width_2d, ZL, ZF, keys, Color(0.2, 0.85, 1.0), Settings.note_style_2d,
			Settings.note_size_2d)
	_pf.skin = ManiaSkin.load_skin(nm) if nm != "" else null
	await get_tree().process_frame
	feed_fake(_pf)
	for i in 4:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var fr := _pf.field_rect()
	var x0 := clampi(int(fr.position.x) - 160, 0, img.get_width() - 1)
	var x1 := clampi(int(fr.end.x) + 160, x0 + 1, img.get_width())
	img.get_region(Rect2i(x0, 0, x1 - x0, img.get_height())).save_png(_out + "/game_" + tag + ".png")
	_pf.queue_free()
	_pf = null
	# --- Vorschau (wie im Einstellungs-Panel), 2x vergroessert, zwei Phasen ---
	Settings.skin_2d = nm
	var holder := Control.new()
	holder.scale = Vector2(2, 2)
	holder.position = Vector2(20, 20)
	add_child(holder)
	var pv := PlayfieldPreview.new()
	holder.add_child(pv)
	await get_tree().process_frame
	pv.set_process(false)
	var ph := 0
	for t in [1.0, 2.2]:
		pv._t = t
		pv._feed()
		for i in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().get_region(Rect2i(0, 0, 560, 440)) \
				.save_png(_out + "/preview_%s_%d.png" % [tag, ph])
		ph += 1
	holder.queue_free()
	await get_tree().process_frame


## Fake-Holds in Z (ZL = Linie, ZF = Oberkante). Rechnerisch geprueft in run_mania_skin_tests.
static func feed_fake(pf: Playfield2D) -> void:
	var c := Color(0.2, 0.85, 1.0)
	pf.begin_frame()
	# Spalte 0: Einzelnote, sehr kurzer Hold, zwei ueberlappende Holds.
	pf.add_note(0, -4.0, c)
	pf.add_hold(0, -10.0, -11.5, c)
	pf.add_hold(0, -24.0, -34.0, c)
	pf.add_hold(0, -31.0, -42.0, c)
	# Spalte 1: Note knapp ueber der Linie, langer Hold oben angeschnitten.
	pf.add_note(1, 1.0, c)
	pf.add_hold(1, -8.0, -70.0, c)
	# Spalte 2: gehaltener Hold (Kopf schon unter der Linie -> an der Linie).
	pf.add_hold(2, 6.0, -30.0, c, Playfield2D.STATE_HELD)
	pf.add_hold(2, -36.0, -40.0, c)
	# Spalte 3: losgelassener Hold (grau), darueber normaler Hold.
	pf.add_hold(3, 0.0, -22.0, c, Playfield2D.STATE_DEAD)
	pf.add_hold(3, -28.0, -44.0, c)
	pf.set_combo(0)
	pf.set_lanes([false, false, true, false], [], [])
