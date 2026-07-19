class_name Beatmap
extends RefCounted

## Ergebnis des Parsers (Abschnitt 3.6). Enthaelt Rohsektionen als Dictionaries
## plus die typisierten Listen fuer Gameplay.

var format_version: int = 14

## Rohsektionen (Key->String), so wie geparst.
var general: Dictionary = {}
var metadata: Dictionary = {}
var difficulty: Dictionary = {}

var timing_points: Array[TimingPoint] = []
var hit_objects: Array[HitObject] = []

## Dateiname des Hintergrundbilds aus [Events] (relativ zum Ordner), falls
## vorhanden. Fuer den Song-Browser (Hintergrund der ausgewaehlten Map).
var background_file: String = ""

## Kiai-Intervalle als Dictionaries {start = ms, end = ms} (Abschnitt 3.3 / 9.1).
var kiai_intervals: Array[Dictionary] = []

# --- Bequeme Getter fuer die haeufig gebrauchten Difficulty-Werte ---

func cs() -> float:
	return float(difficulty.get("CircleSize", 5.0))

func od() -> float:
	return float(difficulty.get("OverallDifficulty", 5.0))

func ar() -> float:
	# Fehlt AR (alte Maps), gilt AR = OD (Abschnitt 3.2). Der Parser setzt das
	# bereits, dieser Fallback ist nur eine zweite Absicherung.
	return float(difficulty.get("ApproachRate", od()))

func hp() -> float:
	return float(difficulty.get("HPDrainRate", 5.0))

func slider_multiplier() -> float:
	return float(difficulty.get("SliderMultiplier", 1.4))

func slider_tick_rate() -> float:
	return float(difficulty.get("SliderTickRate", 1.0))

func audio_filename() -> String:
	return str(general.get("AudioFilename", ""))

func audio_lead_in() -> float:
	return float(general.get("AudioLeadIn", 0.0))

func mode() -> int:
	return int(general.get("Mode", 0))

## osu!mania-Map (Mode 3)?
func is_mania() -> bool:
	return mode() == 3

## Mania: CircleSize = Spaltenzahl.
func column_count() -> int:
	return maxi(int(cs()), 1)

func title() -> String:
	return str(metadata.get("Title", ""))

func artist() -> String:
	return str(metadata.get("Artist", ""))

func version_name() -> String:
	return str(metadata.get("Version", ""))

# --- Abgeleitete Gameplay-Groessen (Abschnitt 3.5) ---

func anchor_radius_osu() -> float:
	return DifficultyCalc.anchor_radius(cs())

func preempt_ms() -> float:
	return DifficultyCalc.preempt(ar())

func window_perfect() -> float:
	return DifficultyCalc.window_perfect(od())

func window_good() -> float:
	return DifficultyCalc.window_good(od())

func window_meh() -> float:
	return DifficultyCalc.window_meh(od())

## Anzahl klickbarer Objekte (Circles + Slider + Spinner).
func note_count() -> int:
	return hit_objects.size()

## Ungefaehre Map-Laenge in ms (Endzeit des letzten Objekts). Die exakte
## Songlaenge ergibt sich erst aus dem Audiostream; fuer die Browser-Anzeige
## reicht die Objekt-Endzeit.
func duration_ms() -> float:
	if hit_objects.is_empty():
		return 0.0
	return hit_objects[hit_objects.size() - 1].end_time()

## Ist Zeitpunkt t (ms) innerhalb eines Kiai-Intervalls?
func is_kiai(t: float) -> bool:
	for iv in kiai_intervals:
		if t >= iv.start and t < iv.end:
			return true
	return false
