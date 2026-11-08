# Orbit v2: Ring durch Zeigen (Stand 2026-11-08)

## Warum
Spieler nannten Orbit "unspielbar", gemeint war: nicht verstanden. Zwei Entscheidungen
pro Ziel gleichzeitig (Winkel mit der Maus, Ring per Taste) und eine Tastenbelegung,
die man auf dem Feld nicht sieht, waren die Hauptursache.

## Regel
- Der **Cursor-Abstand zur Mitte waehlt den Ring** (Grenze mittig zwischen Innen- und
  Aussenring, `OrbitCore.RING_SPLIT_K`, Hysterese `RING_HYST_K`). Der Winkel waehlt die Richtung.
- **Beide Tasten treffen jedes Ziel** (Wechselschlag fuer Streams). Boegen: beliebige
  Taste halten, der Spitze folgen und auf dem Ring bleiben.
- Innen-Ziele fliegen von der Mitte zum Innenring, Aussen-Ziele **von aussen nach innen**
  zum Aussenring. Kein Ziel entsteht auf einem Trefferring.
- Zu frueher Druck frisst das Ziel nicht mehr. Fehldruck zeigt den Grund am Ort
  (anderer Ring, Winkel, zu frueh).

## Tablet und Maus
Ein Stift zeigt absolut: Tiefe (Ring) und Winkel sind eine Handbewegung. Mit der Maus
ist es freies 2D-Zielen wie in osu!. Zwei Tasten bleiben (Tastatur oder Stifttasten).

## Abgrenzung
- osu!tau: ein Ring, nur der Winkel zaehlt (Paddel).
- osu!: freies Feld, Annaeherungskreise.
- Lanota: Touch auf einem Kreis.
Orbit: zwei Bahnen, Bahnwechsel durch Zeigen in die Tiefe, radialer Anflug aus zwei
Richtungen, Boegen auf dem Ring.

## Konverter
- Ein Zeiger = ein Ziel; Akkorde werden zusammengefasst.
- Ringwechsel nur mit Zeit (`RING_SWITCH_MIN_MS`) und bevorzugt auf starken Beats; leichte
  Diffs (Orbit-Sterne < 2,5) fast nur ein Ring und kleine Winkelspruenge.
- Dichte Folgen auf einem Ring halten Abstand (`SEP_DEG_*` innerhalb `SEP_WINDOW_*_MS`),
  ohne neue grosse Spruenge abseits starker Beats; gewollte Stapel (gleicher Winkel)
  bleiben und bekommen den Stapel-Hinweis.

## Messung (tests/run_orbit_qa_tests.gd)
- Verdeckte Ziele in den dichtesten 5 s je Map: Mittel 32 % -> 7 % (Groessen-Anpassung).
- Maps unter 8 Zielen/s: hoechstens 15 % (schlechteste 5,7 %). Ab 8 Zielen/s auf einem
  Ring sind Beruehrungen im Anflug bei Scroll 1,0 nicht ohne schwer erreichbare Spiralen
  zu vermeiden: Grenze 25 % (schlechteste 23,9 %). Hoeherer Scroll Speed entzerrt.
- Ganz verdeckte Ziele ohne Stapel-Hinweis: 0 je Frame.
- Replays: neues Format mit Cursor-Radius; alte Orbit-Replays werden als "aeltere Version"
  gemeldet.
