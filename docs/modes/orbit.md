# Orbit-Modus (Entwurf)

Eigener Modus: zielen mit Maus/Tablet, tippen mit zwei Tasten. Ziele liegen auf
zwei Ringen um die Bildschirmmitte. Der Cursor-**Winkel** zur Mitte waehlt die
Richtung, die **Taste** den Ring (Taste A = innen, Taste B = aussen; Standard
Maus links/rechts und Z/X, umbelegbar). Ein Treffer zaehlt nur, wenn Zeitfenster
**und** Winkel stimmen.

Code: `scripts/orbit/orbit_note.gd` (Ziel), `scripts/orbit/orbit_converter.gd`
(Map-Umwandlung), `scripts/orbit/orbit_core.gd` (Wertung). Tests:
`tests/run_orbit_tests.gd`. Darstellung/Eingabe: Task orbit-play.

## Winkel

0 Grad = oben, im Uhrzeigersinn steigend. `angle_deg` liegt in [0, 360).
`end_angle_deg` ist nicht gefaltet: `end_angle_deg - angle_deg` ist der
vorzeichenbehaftete Bogen (+ = im Uhrzeigersinn). Die Bogen-Spitze zur Zeit t
liefert `OrbitNote.angle_at(t)`.

## Regeln (OrbitCore)

- Zeitfenster, Qualitaeten (MAX/PERFECT/GOOD/OK/MEH/MISS), Score (ScoreV1,
  1.000.000), Acc, Grade, HP und `stats()` wie ManiaCore. OrbitCore nutzt dafuer
  intern ein ManiaCore-Objekt als Zaehler, die Formeln stehen nur dort.
- Tap: Taste des richtigen Rings im 50er-Fenster, Cursor hoechstens
  `ANGLE_TOL_DEG` = 22 Grad neben dem Ziel. Falscher Ring oder falscher Winkel
  = kein Treffer (das Ziel bleibt offen, bis sein Fenster ablaeuft = MISS).
- Zu frueh (zwischen 50er- und Miss-Fenster) **und** richtig gezielt: frisst das
  Ziel als MISS, wie Mania.
- Bogen: Kopf wie ein Tap (`arc_started`). Danach Taste halten und der
  wandernden Spitze folgen (gleiche 22 Grad). Mehr als `ARC_OUT_MS` = 150 ms am
  Stueck ausserhalb oder Loslassen frueher als 1,5x 50er-Fenster vor dem Ende =
  MISS mit `miss_kind` "DROP" (`drop_reason` "OUT" bzw. "RELEASE"). Sonst zaehlt
  am Ende die Qualitaet des Kopfs. Ein Bogen ist ein Acc-Objekt.
- Die Austrittszeit wird exakt berechnet (Spitze laeuft linear, Cursor steht
  zwischen zwei Events still), also unabhaengig von der Framerate.
- `note_judged(index, result)`: `quality`, `dt`, `angle_err`, `ring`,
  `miss_kind`, `late`; Boegen zusaetzlich `hold_end`, `held`, `drop_reason`.

## Umwandlung (OrbitConverter)

Quelle: osu!mania-Maps (gedacht fuer 4K). Kein Zufall: gleiche Map = gleiches
Muster.

1. **Akkord** = Notes mit <= 2 ms Abstand. Ergibt hoechstens zwei Ziele: beide
   Ringe am selben Winkel (niedrigste Spalte innen, hoechste aussen). Die
   Variante "derselbe Ring nebeneinander" wird nicht erzeugt: ein Tastendruck
   trifft nur ein Ziel, zwei gleichzeitige Ziele auf einem Ring waeren
   unspielbar.
2. **Dichte-Reduktion**: ein Akkord weniger als `MIN_GAP_MS` = 75 ms nach dem
   letzten behaltenen wird verworfen. Alles schneller als 1/4 bei 200 BPM wird
   so zusammengefasst (1/6-Bursts, schnelle Jacks, Doppel-Streams).
3. **Winkel**: die Spalten liegen gedanklich auf einem Kreis. Der kreisfoermige
   Spaltenabstand d (4K: -1, 0, +1, +2; +2 folgt der Flussrichtung) mal
   Schrittweite ist der Sprung. Schrittweite = 24 Grad x clamp(Abstand / 150 ms,
   1, 2,5): kleine Abstaende = kleine Spruenge, grosse Abstaende duerfen bis
   120 Grad springen. Jeder Sprung ist gedeckelt auf `MAX_DEG_PER_MS` = 0,6
   Grad/ms x Abstand und `MAX_JUMP_DEG` = 150 Grad. Ergebnis: Rolls drehen im
   Kreis, Trills pendeln, Jacks bleiben stehen (ab 300 ms Abstand wandern sie
   einen Schritt weiter).
4. **Ring**: Einzelnoten im Stream (Abstand < 160 ms) wechseln den Ring, die
   Tasten werden also abgewechselt. In ruhigen Stellen entscheidet die
   Spaltenhaelfte (linke Haelfte innen, rechte aussen). Direkt nach einem
   Bogen-Ende (< 150 ms) kommt das naechste Ziel auf den anderen Ring.
5. **LN -> Bogen**: Winkellaenge = Dauer x 0,12 Grad/ms, gedeckelt auf 270
   Grad, Richtung = aktuelle Flussrichtung. LNs unter 100 ms werden Taps. Bei
   LN-Akkorden laufen beide Boegen gleich schnell (ein Cursor folgt beiden).
6. **Notes waehrend eines Bogens** werden Taps auf dem freien Ring genau an der
   Bogen-Spitze (dort ist der Cursor ohnehin). Laufen zwei Boegen, werden sie
   verworfen.

Damit bleibt die Winkelgeschwindigkeit zwischen allen Cursor-Punkten (Koepfe,
Bogen-Enden) unter 0,6 Grad/ms (bei Ringradius 300 px etwa 3100 px/s).

## Konstanten

| Konstante | Wert | Ort |
|---|---|---|
| `ANGLE_TOL_DEG` | 22 Grad | OrbitCore |
| `ARC_OUT_MS` | 150 ms | OrbitCore |
| `CHORD_EPS_MS` | 2 ms | OrbitConverter |
| `MIN_GAP_MS` | 75 ms | OrbitConverter |
| `MAX_DEG_PER_MS` | 0,6 Grad/ms | OrbitConverter |
| `MAX_JUMP_DEG` | 150 Grad | OrbitConverter |
| `COL_STEP_DEG` | 24 Grad | OrbitConverter |
| `REF_GAP_MS` / `MAX_STEP_SCALE` | 150 ms / 2,5 | OrbitConverter |
| `DRIFT_GAP_MS` | 300 ms | OrbitConverter |
| `STREAM_GAP_MS` | 160 ms | OrbitConverter |
| `MIN_ARC_MS` | 100 ms | OrbitConverter |
| `ARC_DEG_PER_MS` / `ARC_MAX_DEG` | 0,12 Grad/ms / 270 Grad | OrbitConverter |
| `RELEASE_GAP_MS` | 150 ms | OrbitConverter |

## Messwerte (echte Map, Testlauf)

- Billain - Specialist [Advanced]: 1102 Notes (55 LN) -> 1097 Ziele (54 Boegen),
  max 0,558 Grad/ms, Umwandlung 9 ms.
- Billain - Specialist [GoldenJumper's Insane]: 2213 Notes (46 LN) -> 1970 Ziele
  (5 Boegen), max 0,600 Grad/ms, 17 ms.
- Autoplay (perfekter Spieler) erreicht auf beiden SS, also ist jedes Ziel
  erreichbar.
