class_name TempoMode
extends Node

## Haken der Mania-Szene fuer Tempo-Varianten (mv-tempo): Uebungsmodus
## (PracticeController) und Turbo (TurboController). mania_3d.gd ruft nur diese
## vier Methoden auf; ohne Variante bleibt _tempo_mode null und nichts aendert sich.

## Mania-Szene (mania_3d.gd).
var host: Node


## Passende Variante fuer diesen Lauf an die Szene haengen (oder null).
static func attach(p_host: Node) -> TempoMode:
	if GameSession.tutorial or Lobby.in_round():
		return null
	var m: TempoMode = null
	if PracticeSession.active() and not GameSession.is_replay:
		m = PracticeController.new()
	elif bool(GameSession.mods.get("TB", false)):
		m = TurboController.new()
	if m == null:
		return null
	m.host = p_host
	p_host.add_child(m)
	m._setup()
	return m


func _setup() -> void:
	pass


## true = Variante uebernimmt den Start (kein normaler Countdown).
func take_start() -> bool:
	return false


## Pro Frame nach core.update(t) (t = Judgement-Zeit).
func tick(_t: float) -> void:
	pass


## Escape im Spiel; true = verbraucht.
func on_escape() -> bool:
	return false


## Ergebnis eines Laufs; true = Variante wertet selbst (keine normale
## Rangliste, kein Online-Score, keine pp).
func owns_results(_s: Dictionary, _is_fail: bool) -> bool:
	return false
