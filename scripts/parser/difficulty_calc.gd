class_name DifficultyCalc
extends RefCounted

## Offizielle osu!-Formeln zur Umrechnung von CS/OD/AR in Gameplay-Groessen
## (Abschnitt 3.5). Diese Werte sind verbindlich und duerfen beim Tuning NICHT
## veraendert werden (Abschnitt 6.1 / Regel 9). Alle Funktionen sind static.

## osu-Playfield-Hoehe in osupixeln (Referenz fuer den Scale).
const PLAYFIELD_HEIGHT := 384.0
const PLAYFIELD_WIDTH := 512.0

## Anker-Radius aus CS in osupixeln (danach mit Playfield-Scale multiplizieren).
static func anchor_radius(cs: float) -> float:
	return 54.4 - 4.48 * cs

## Timing-Window PERFECT (300) in +/- ms.
static func window_perfect(od: float) -> float:
	return 80.0 - 6.0 * od

## Timing-Window GOOD (100) in +/- ms.
static func window_good(od: float) -> float:
	return 140.0 - 8.0 * od

## Timing-Window MEH (50) in +/- ms.
static func window_meh(od: float) -> float:
	return 200.0 - 10.0 * od

# --- osu!mania-Timing-Fenster (OD-basiert, stable) — ALLE 6 Judgements,
# exakt wie im Original: MAX(320) 16.5 konstant, Rest 3ms pro OD enger. ---

static func mania_window_max(_od: float) -> float:
	return 16.5

static func mania_window_300(od: float) -> float:
	return 64.5 - 3.0 * od

static func mania_window_200(od: float) -> float:
	return 97.5 - 3.0 * od

static func mania_window_100(od: float) -> float:
	return 127.5 - 3.0 * od

static func mania_window_50(od: float) -> float:
	return 151.5 - 3.0 * od

## Frueher Druck ausserhalb 50er, aber innerhalb dieses Fensters: frisst die Note.
static func mania_window_miss(od: float) -> float:
	return 188.5 - 3.0 * od


## Approach-Zeit (preempt) aus AR in ms — wann der Anker erscheint.
static func preempt(ar: float) -> float:
	if ar < 5.0:
		return 1200.0 + 600.0 * (5.0 - ar) / 5.0
	elif ar == 5.0:
		return 1200.0
	else:
		return 1200.0 - 750.0 * (ar - 5.0) / 5.0

## Fade-In-Dauer des Ankers: erste ~2/3 der preempt-Zeit.
static func fade_in(ar: float) -> float:
	return preempt(ar) * (2.0 / 3.0)

## Skalierungsfaktor osu-Playfield -> Bildschirm (Abschnitt 3.4):
## Playfield 4:3 zentriert, scale = playfieldHeight / 384.
static func playfield_scale(screen_playfield_height: float) -> float:
	return screen_playfield_height / PLAYFIELD_HEIGHT
