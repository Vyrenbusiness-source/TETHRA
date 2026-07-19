class_name TimingPoint
extends RefCounted

## Ein TimingPoint aus der [TimingPoints]-Sektion (Abschnitt 3.3).
## Format: time,beatLength,meter,sampleSet,sampleIndex,volume,uninherited,effects

## ms-Offset im Song, ab dem dieser Point gilt.
var time: float = 0.0

## Rote Linie (uninherited=1): Millisekunden pro Beat.
## Gruene Linie (uninherited=0): negativ, codiert SV-Multiplikator.
var beat_length: float = 0.0

## Taktart (Beats pro Takt). Default 4.
var meter: int = 4

## true = rote Linie (setzt Tempo), false = gruene Linie (SV-Multiplikator).
var uninherited: bool = true

## effects-Bitfeld.
var effects: int = 0

## effects & 1 == Kiai Time.
var kiai: bool = false


## SV-Multiplikator einer gruenen Linie: SV = -100 / beatLength.
## Nur fuer gruene Linien sinnvoll; rote Linien liefern 1.0.
func slider_velocity() -> float:
	if uninherited:
		return 1.0
	if beat_length == 0.0:
		return 1.0
	return -100.0 / beat_length


## BPM einer roten Linie: 60000 / beatLength.
func bpm() -> float:
	if not uninherited or beat_length <= 0.0:
		return 0.0
	return 60000.0 / beat_length
