extends SceneTree

## Headless-Tests fuer den Bild-Decoder des OSZ-Importers (Magic-Bytes statt Endung).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_osz_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA OSZ-Tests ===")
	var src := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	src.fill(Color(0.2, 0.6, 0.9))
	var png := src.save_png_to_buffer()
	var jpg := src.save_jpg_to_buffer(0.9)
	var webp := src.save_webp_to_buffer(true)
	_ok(not png.is_empty() and not jpg.is_empty() and not webp.is_empty(), "Testbilder erzeugt")
	_ok(png[0] == 0x89 and jpg[0] == 0xFF and webp[0] == 0x52, "Magic-Bytes wie erwartet")
	for pair in [["PNG", png], ["JPEG", jpg], ["WebP", webp], ["BMP", _bmp()]]:
		var img := OszImporter.decode_image_bytes(pair[1])
		_ok(img != null and img.get_width() == 8 and img.get_height() == 8, pair[0] + " dekodiert (8x8)")
	# Endung egal: PNG-Bytes bleiben PNG (Fall bg.jpg = PNG), Decoder sieht keinen Namen.
	var cut := png.slice(0, 20)
	_ok(OszImporter.decode_image_bytes(cut) == null, "abgeschnittenes PNG -> null")
	_ok(OszImporter.decode_image_bytes(PackedByteArray()) == null, "leer -> null")
	var junk := PackedByteArray()
	junk.resize(64)
	_ok(OszImporter.decode_image_bytes(junk) == null, "unbekannte Bytes -> null")
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Minimales 24-Bit-BMP, 8x8, einfarbig.
func _bmp() -> PackedByteArray:
	var b := PackedByteArray()
	var row := 24  # 8*3 Bytes, schon 4er-ausgerichtet
	var size := 54 + row * 8
	b.resize(size)
	b[0] = 0x42
	b[1] = 0x4D
	b.encode_u32(2, size)
	b.encode_u32(10, 54)
	b.encode_u32(14, 40)
	b.encode_s32(18, 8)
	b.encode_s32(22, 8)
	b.encode_u16(26, 1)
	b.encode_u16(28, 24)
	b.encode_u32(34, row * 8)
	for i in range(54, size):
		b[i] = 0x80
	return b


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)
