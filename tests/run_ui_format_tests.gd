extends SceneTree

## Headless-Tests fuer UiTheme.fmt_* / key_short.
##   Godot..._console.exe --headless --path . --audio-driver Dummy --script res://tests/run_ui_format_tests.gd

var _failed := 0


func _eq(got, want, msg: String) -> void:
	if got == want:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg, " got=", got, " want=", want)
		_failed += 1


func _init() -> void:
	_eq(UiTheme.fmt_num(0.8, 1), "0,8", "fmt_num 1")
	_eq(UiTheme.fmt_num(6.5, 1), "6,5", "fmt_num OD")
	_eq(UiTheme.fmt_num(7.274, 2), "7,27", "fmt_num rundet")
	_eq(UiTheme.fmt_num(3.0, 0), "3", "fmt_num 0 Stellen")
	_eq(UiTheme.fmt_score(0), "0", "fmt_score 0")
	_eq(UiTheme.fmt_score(999), "999", "fmt_score 3 Stellen")
	_eq(UiTheme.fmt_score(10067), "10.067", "fmt_score 10.067")
	_eq(UiTheme.fmt_score(923412), "923.412", "fmt_score ohne fuehrende Nullen")
	_eq(UiTheme.fmt_score(1234567), "1.234.567", "fmt_score Mio")
	_eq(UiTheme.fmt_score(-1500), "-1.500", "fmt_score negativ")
	_eq(UiTheme.fmt_pct(85.09), "85,09 %", "fmt_pct")
	_eq(UiTheme.fmt_pct(100.0), "100,00 %", "fmt_pct 100")
	_eq(UiTheme.fmt_date("2026-11-06T14:30:00"), "06.11.2026 14:30", "fmt_date ISO T")
	_eq(UiTheme.fmt_date("2026-01-02 03:04:05"), "02.01.2026 03:04", "fmt_date ISO Leerzeichen")
	_eq(UiTheme.fmt_date(""), "—", "fmt_date leer")
	_eq(UiTheme.fmt_date(0), "—", "fmt_date 0")
	_eq(UiTheme.fmt_date(1762439400).length(), 16, "fmt_date Unix Laenge")
	_eq(UiTheme.fmt_pp(33.6), "34 pp", "fmt_pp")
	_eq(UiTheme.fmt_pp(331.2), "331 pp", "fmt_pp 331")
	_eq(UiTheme.key_short("Comma"), ",", "key Comma")
	_eq(UiTheme.key_short("Period"), ".", "key Period")
	_eq(UiTheme.key_short("y"), "Y", "key y")
	_eq(UiTheme.key_short(KEY_COMMA), ",", "key keycode Comma")
	_eq(UiTheme.key_short(KEY_Y), "Y", "key keycode Y")
	_eq(UiTheme.key_short("Space"), "Leertaste", "key Space")
	print("FAILED: ", _failed)
	quit(1 if _failed > 0 else 0)
