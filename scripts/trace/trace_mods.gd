class_name TraceMods
extends RefCounted

## Mods fuer Trace (statisch, deterministisch). Schluessel in GameSession.mods:
##   "MR" Mirror: links<->rechts (Spalte 0<->3, Pfeile gespiegelt), Faktor 1,0
##   "HD" Hidden: der Vorlauf blendet zum Kopf hin aus, Faktor 1,06
##   "SS" Short Sight: nur 500 ms Vorlauf sichtbar, Faktor 1,08
## Faktoren wie Mania-Konvention. ManiaCore bleibt unberuehrt: trace-fix ruft
## TraceMods.mod_multiplier(mods) zusaetzlich zu ManiaCore.mod_multiplier auf
## (Produkt), TraceMods.mod_list(mods) haengt MR/HD/SS an die Badge-Liste.

const MODS := ["MR", "HD", "SS"]
const MOD_ORDER := ["MR", "HD", "SS", "NF"]
const MOD_MULT := {"MR": 1.0, "HD": 1.06, "SS": 1.08}
const SHORT_SIGHT_MS := 500.0
## Hidden: Anteil des Vorlaufs ab Kopf, der voll sichtbar bleibt / ab dem nichts mehr zu sehen ist.
const HIDDEN_FADE_START := 0.15
const HIDDEN_FADE_END := 0.55


static func has(mods: Dictionary, key: String) -> bool:
	return bool(mods.get(key, false))


static func from_session() -> Dictionary:
	var m := ManiaCore.session_mods()
	var out := {}
	for k in MODS:
		if bool(m.get(k, false)):
			out[k] = true
	return out


## Spalte nach Mods (Mirror: 0<->3, 1 und 2 bleiben).
static func map_column(col: int, mods: Dictionary) -> int:
	if has(mods, "MR"):
		if col == 0:
			return 3
		if col == 3:
			return 0
	return col


## Pfeilwinkel gespiegelt an der senkrechten Achse (links<->rechts).
static func map_angle(a: float, mods: Dictionary) -> float:
	return wrapf(PI - a, -PI, PI) if has(mods, "MR") else a


## Sichtbarer Vorlauf in ms (Short Sight kappt auf 500 ms).
static func look_ms(full_ms: float, mods: Dictionary) -> float:
	return minf(full_ms, SHORT_SIGHT_MS) if has(mods, "SS") else full_ms


## Deckkraft des Wegs bei ahead_ms vor dem Kopf (0 = Kopf). 1 = voll sichtbar,
## 0 = weg. Ohne HD und ohne SS immer 1; SS: 0 jenseits der 500 ms.
static func path_alpha(ahead_ms: float, mods: Dictionary, full_ms: float = 1200.0) -> float:
	if ahead_ms < 0.0:
		return 1.0
	var a := 1.0
	if has(mods, "SS") and ahead_ms > SHORT_SIGHT_MS:
		return 0.0
	if has(mods, "HD"):
		# Hidden: nahe am Kopf unsichtbar, nach vorn hin voll sichtbar.
		var span := look_ms(full_ms, mods)
		var f := clampf(ahead_ms / maxf(span, 1.0), 0.0, 1.0)
		a = clampf((f - HIDDEN_FADE_START) / (HIDDEN_FADE_END - HIDDEN_FADE_START), 0.0, 1.0)
	return a


static func mod_multiplier(mods: Dictionary) -> float:
	var m := 1.0
	for k in MODS:
		if has(mods, k):
			m *= float(MOD_MULT[k])
	return m


## Aktive Mods als Badge-Liste in fester Reihenfolge (inkl. NF).
static func mod_list(mods: Dictionary) -> Array:
	var out := []
	for k in MOD_ORDER:
		if has(mods, k):
			out.append(k)
	return out
