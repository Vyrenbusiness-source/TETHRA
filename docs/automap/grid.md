# AmGrid: Taktgitter des 4K-Auto-Mappers (OMEN)

Modul: `scripts/automap/am_grid.gd` (`class_name AmGrid`, Schnittstelle nach `docs/automap/spec.md`).
Tests und Messung: `tests/run_am_grid_tests.gd`.

## Ablauf

1. `envelope()`: Onset-Fluss in drei Baendern (5-ms-Frames), Bass-Fluss, Bass-Nulldurchgaenge.
   `decimate()`: Signal auf ~2756 Hz (zweimal Tiefpass 1000 Hz) fuer die Harmonie-Merkmale.
2. Autokorrelation in 4-s-Bloecken: grober Puls, Fenster mit fremdem Tempo werden eigene Segmente.
3. Mehrere Puls-Kandidaten (staerkste lokale Maxima der Kamm-Autokorrelation, `n_pulses`), jeder mit
   seiner Tempo-Familie (x2, x0,5, x1,5, x0,667, x3, x0,333, x0,75, x1,333). Jede Hypothese wird ueber
   die Taktstruktur bewertet: Phasen-Kohaerenz auf Schlag, Halbe, Viertel und Drittel des Schlags,
   Fuellung der Schlaege, Tempo-Vorwissen (Log-Normal um `prior_bpm`). Folgesegmente pruefen nur
   die Oktaven ihres eigenen Pulses (sonst gewinnt ueber x0,75 / x1,333 wieder das Haupttempo).
4. Periode: Regression Zeit = Offset + k * Periode ueber das ganze Segment; gegen den Scan
   gewinnt die Periode mit der hoeheren Kohaerenz. Ganzzahlige BPM, wenn sie innerhalb der
   Messgenauigkeit liegen oder (bis 0,15 % Abstand) mindestens 92 % der Kohaerenz erreichen.
5. Phase: Maximum des gefalteten Onset-Profils, dann das Viertel des Schlags mit dem hoechsten
   Log-Akzent; das Viertel des ersten deutlichen Anschlags (ab Median-Staerke) bekommt
   `phase_first_w` = 0,1 Bonus (Songs beginnen meist auf einem Schlag; entscheidet die Faelle, in
   denen Schlag und Gegenschlag gleich laut sind).
6. Taktart (4 oder 3): Statistik je Schlagposition im Takt (Bass-Akzent, Bass-Nulldurchgaenge,
   Energiewechsel ueber 4 und 16 Schlaege, erster Bass-Anschlag), Gewichte `db_w_*`.
7. Taktanfang mit Harmonie (`db2_w_*`): je Schlag Chroma ab Schlag + 20 ms per Goertzel auf dem
   dezimierten Signal (Noten 130-1050 Hz, 512 Werte = 186 ms; Bass 41-123 Hz auf halber Rate,
   256 Werte), daraus Akkordwechsel Schlag gegen Vorschlag, Akkordwechsel 2 gegen 2 Schlaege und
   Bass-Grundton-Wechsel; dazu Bass-Akzent, Energiewechsel ueber 4 Schlaege und Bonus fuer den
   Schlag des ersten deutlichen Bass-Anschlags. Je Merkmal z-Wert der Position im Takt, gewichtete
   Summe, bestes Position gewinnt. Bei mehr als `chroma_max_beats` Schlaegen nur gleichmaessig
   verteilte Bloecke zu 32 Schlaegen (Rechenzeit). Ohne dezimiertes Signal die alten Gewichte.
8. Vertrauen aus Abstand zur zweitbesten Hypothese und Kohaerenz; Alternativen mit Faktor und
   relativem Score.

Alle Stellgroessen stehen in `AmGrid.DEFAULTS` und lassen sich ueber `params` bzw.
`data/automap/params.json` (Abschnitt `grid`) ueberschreiben. Abgestimmt auf die Maps in `maps/`
(Python nur zur Auswertung im Scratchpad, nicht im Spiel), immer mit Kontrolle Haelfte A gegen
Haelfte B: Gewichte auf A gelernt und auf B geprueft und umgekehrt.

## Runde 3: Oktave, Gegenschlag, Tempowechsel

Ziel der Runde: Tempo exakt ≥ 95 %, Offset p95 ≤ 12 ms, Tempowechsel ≥ 80 %. Alle Versuche in
Python im Scratchpad auf dem Cache des Messskripts (Onset-Fluss, dezimiertes Signal, Rohaudio
11025 Hz), Haelfte A/B = gerade/ungerade Nummer in `maps/` (271 Sets ohne eigene
Erzeugnisse, 229 mit einem Tempo, 20 mit Tempowechsel). Gelernt auf einer Haelfte, geprueft auf der
anderen. Uebernommen wurde nur, was auf beiden Haelften nicht schadet.

Messskript (`tests/run_am_grid_tests.gd -- --measure`, ein Prozess je Stand, gleicher Cache), Sets
mit einem Tempo. "vorher" = 300f1a3, "nachher" = dieser Stand. "Prüf" = Prüf-Menge des Prüfstands
(sha256-Aufteilung), hier mit der Wahrheit des Messskripts (Diff mit den meisten Objekten).
Eigene Erzeugnisse (`(OMEN Auto).osz` in `maps/`) zaehlen jetzt nicht mehr mit (wie im Prüfstand);
in beiden Spalten herausgerechnet.

| Kennzahl | Ziel | vorher A | vorher B | vorher Prüf | nachher A | nachher B | nachher Prüf |
|---|---|---|---|---|---|---|---|
| Tempo exakt | ≥ 95 % | 85,2 % (92/108) | 90,9 % (110/121) | 88,1 % (59/67) | 85,2 % (92/108) | 90,9 % (110/121) | 88,1 % (59/67) |
| exakt oder Alternative (x2, x0,5, x1,5, x0,667) | ≥ 99 % | 98,1 % | 99,2 % | 98,5 % | 99,1 % | 99,2 % | 100 % |
| Offset 95. Perzentil (ms) | ≤ 12 | 18,5 | 91,4 | 14,5 | 18,5 | 91,4 | 14,5 |
| Offset Median (ms) | ≤ 4 | 3,0 | 3,8 | 3,0 | 3,0 | 3,8 | 3,0 |
| Tempowechsel erfuellt | ≥ 80 % | 3/14 | 2/6 | 0/4 | 3/14 | 2/6 | 0/4 |
| Taktanfang | ≥ 85 % | 83,7 % | 91,6 % | 87,9 % | 83,7 % | 91,6 % | 87,9 % |
| Sets mit einem Tempo geteilt | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Erkanntes Tempo, Offset, Taktanfang und Segmente sind in allen 271 Sets gleich wie vorher; geaendert
haben sich nur die gemeldeten Alternativen (mirror_2541937: 342 BPM jetzt als Alternative x2).

RUNDE3_BENCH

### 1. Oktave (Tempo exakt)

Bei 24 der 27 falschen Sets ist es eine Oktave (12 x2, 12 x0,5), d. h. die Familie stimmt, nur die
Ebene nicht. Gemessen je Hypothese (Gewinner, x2, x0,5), Phase wie `_best_phase`:

- **Snare-Lage / Kick-Snare-Muster**: Baender Kick 35-110 Hz, Mitte 250-2000 Hz, Hoehen
  3-5,2 kHz (Rohaudio) bzw. 250-1000 Hz aus dem dezimierten Signal und die Baender von
  `envelope()`. Je Band Periode 2 und 4 Schlaege auf den Schlaegen (Betrag der DFT-Komponente),
  Schlag gegen Gegenschlag, Gegenlauf Kick/Snare (Kick auf 1/3, Snare auf 2/4). Bedingtes Logit
  ueber die Hypothesen mit dem bisherigen Score als Basis (209 Sets mit Rohaudio): Basis A 93/105,
  B 93/104; alle Merkmale A->B 89/104, B->A 85/105; nur Band-Merkmale A->B 96/104, B->A 84/105; einzeln (Snare-Periode
  Hoehen, Mitte, Kick) jeweils -2 bis +1 Sets. Die gelernten Gewichte wechseln zwischen A und B das
  Vorzeichen. Paarweise Klassifikatoren (Random Forest, Gradient Boosting, Logit) auf allen
  Merkmalen: bester Fall B->A 2 richtig und 1 falsch umgestellt (von 10 richtigen Alternativen),
  A->B 5 richtig und 8 falsch.
- **"Snare nur alle 4 Schlaege"** (Hoehen-Band, Periode 4 deutlich ueber Periode 2): 11 Sets, davon
  2 mit halbem Map-Tempo (216 -> 108, 220 -> 110), 9 mit dem erkannten Tempo (u. a. 120, 180, 192
  BPM: Halftime-Feel, gemappt im schnellen Tempo). Als Regel nicht tragfaehig.
- **Tempo-Vorwissen aus den Maps** (Kern-Dichte der Map-BPM in log2, Breite 0,1-0,5 Oktaven, Gewicht
  0,25-2, statt Log-Normal um 130): Basis A 92/108, B 110/121; auf A gewaehlt -> B 100-104; auf B
  gewaehlt -> A 88-92.
- **Notendichte je Schlag** (Anschlaege je Schlag als Merkmal): A->B -2, B->A -1 (Runde 2: ebenso).
- **Warum**: Fehlerrate je erkanntem Tempo (229 Sets): erkannt 210-225 BPM: 4 von 14 Maps nehmen die
  Haelfte; erkannt 90-105 BPM: 3 von 6 Maps nehmen das Doppelte. In beiden Bereichen waehlen die
  Mapper gleich klingender Songs beide Ebenen; kein Merkmal des Signals trennt sie.

Uebernommen: `bpm_max` 330 -> 360. Vorher fehlte bei 342-BPM-Maps (erkannt 171) die Alternative x2
ganz, weil 342 ausserhalb der Hypothesen lag. Die neuen Hypothesen ueber 330 BPM gewinnen nie
(Tempo-Vorwissen), sie erscheinen nur als Alternative.

### 2. Gegenschlag (Offset p95)

186 Sets mit richtigem Tempo und Rohaudio, davon 6 um einen halben Schlag versetzt. Verglichen:
Merkmal an der Phase der Map gegen Phase + 1/2 Schlag.

- Schlag gegen Gegenschlag je Band (log-Verhaeltnis der Anschlaege): Mitte (200-2500 Hz) bei 94 %
  der Sets an der Map-Phase staerker, Hoehen 94 %, Bass 70 %; in den 6 versetzten Sets uneinheitlich
  (-0,30 bis +0,19). Als Umschalt-Regel mit Schwelle m (umschalten, wenn der Gegenschlag um m
  staerker ist): Mitte m = 0: 4 behoben, 10 neu falsch; m = 0,1: 1 / 3; m = 0,2: 0 / 1; Mitte+Hoehen
  m = 0,2: 1 / 1; kein Band und keine Summe mit mehr behobenen als neu falschen Sets.
- Kick auf 1/3, Snare auf 2/4 (Wechsel der Staerke von Schlag zu Schlag, an beiden Phasen):
  an der Map-Phase nur bei 51-56 % der Sets ausgepraegter als am Gegenschlag, also kein Signal.

Nicht uebernommen. Untergrenze wie in Runde 2: ohne die halben Versaetze liegt p95 bei 14-18 ms,
die Streuung der Mapper-Offsets selbst.

### 3. Tempowechsel

- **Zweiteilung mit eigener Periode und Phase je Seite** (Regression wie `_regress`, Gewinn der
  Ausrichtung durch die Teilung): Sets mit einem Tempo Median 0,0012, 95. Perzentil 0,0066,
  Maximum 0,036; echte Wechsel 0,0001-0,013. Keine Schwelle trennt.
- **Phasen-Rest des Hauptrasters je 4-s-Fenster** (ausgerichtete Phasensumme): Sets mit einem
  Tempo haben Laeufe von 11-17 Fenstern (22-34 s) mit negativer Summe; die Anschlaege auf den
  Schlaegen sind zu verrauscht fuer eine lokale Phase (wie Runde 2).
- **Fremde 8-s-Fenster ohne Familien-Bezug** (Puls nicht auf einem Familien-Lag, Familie schwaecher
  als Anteil r des Pulses, mindestens n Fenster): 0 faelschlich geteilte Sets nur bei Einstellungen,
  die keinen zusaetzlichen Wechsel finden (r ≤ 0,7, oder n ≥ 5); ab r = 0,8 / n = 2 werden 5 Sets
  geteilt, bei r = 0,95 / n = 2 31.
- **Pruefung der Laeufe** (Kohaerenz des eigenen Rasters gegen das Hauptraster ueber den Lauf):
  Schwelle 2,0 laesst nur die Laeufe in mirror_2559592 (170) und mirror_2643833 (155 statt 77,5)
  durch, auf A und B kein Set mit einem Tempo. Beide Sets waeren danach trotzdem nicht erfuellt
  (Grenzen 177,5/185 nicht getroffen bzw. Tempo 155 statt 77,5). Nicht eingebaut.

Offen bleibt ein Beat-Tracker mit besserem Onset-Mass (z. B. gelernte Schlag-Aktivierung); auf
den Anschlaegen dieses Moduls ist weder die lokale Phase noch das lokale Tempo stabil genug.

### Prüfstand (tools/automap_bench.gd): Grenzen der Zeile Tempowechsel

Von den 6 gewerteten Prüf-Sets sind 3 keine Tempowechsel: mirror_2572994 hat nur 3/4-Linien mit
2,6 ms Rundungsversatz (Toleranz des Prüfstands 2 ms), mirror_2541848 Phasenspruenge von 28 ms bei
gleichem Tempo, 315435 einen Phasensprung von 27 ms nach 3,5 s. mirror_2586880 hat eine letzte Note
bei 100 001 999 ms, daher dort Drift 290 ms und Offset +168,8 ms (das Messskript hier: 23,8 ms).

### Kontrolle: Nutzer-Song "c4rl - Immer" (nur lokal, nichts im Repo)

Erkannt 214 BPM (Vertrauen 0,56), erste Alternative x0,5 = 107 BPM mit relativem Score 0,87.
Hoehen-Band (3-5,2 kHz) ueber 8 Schlaege bei 214 gefaltet: Spitzen auf Schlag 3 und 7, also die
Snare alle 4 Schlaege, wie gehoert; 107 BPM ist musikalisch plausibel. Bei 107 ist die
Phasen-Kohaerenz am Schlag 0,026 gegen 0,132 bei 214 (Fuellung 0,94 gegen 0,83). Das Gitter bleibt
bei 214, weil dasselbe Muster in den Maps 9 von 11 Mal mit dem schnellen Tempo gemappt ist (Abschnitt
1); 107 liefert `scaled(grid, 0.5)` ueber die erste Alternative. `track()` 1,7 s fuer 2:16 min.

## Runde 2: Vorher / Nachher je Haelfte

Ein Messprozess, Varianten ueber `--variants` (gleiche Sets, gleiche Wahrheit). Sets mit einem
Tempo; Haelfte A/B = gerade/ungerade Nummer in `maps/`. "Vorher" = Stand abd54ba.

| Kennzahl | Ziel | vorher A | vorher B | nachher A | nachher B |
|---|---|---|---|---|---|
| Tempo exakt | ≥ 95 % | 88,6 % | 89,4 % | 88,2 % | 89,4 % |
| Offset 95. Perzentil (richtiges Tempo) | ≤ 12 ms | 51,2 ms | 66,4 ms | 40,5 ms | 20,4 ms |
| Offset Median | ≤ 4 ms | 3,7 ms | 3,0 ms | 3,6 ms | 2,9 ms |
| Taktanfang (Taktart und Eins richtig) | ≥ 85 % | 75,0 % | 76,9 % | 87,5 % | 86,8 % |
| Sets mit einem Tempo faelschlich geteilt | 0 | 0 | 0 | 0 | 0 |

(Zaehlung je Haelfte aus den Dump-Dateien; "Taktanfang" dort ohne die ±1/4-Schlag-Grenze der
Gesamtzeile, daher wenige Sets Abweichung zur Tabelle unten.)

Je Aenderung einzeln (Variante ohne die Aenderung gegen mit, beide Haelften):

- Phasen-Bonus erster Anschlag: Offset p95 A 134 -> 40,5 ms, B 66,4 -> 20,4 ms; halber/viertel
  Versatz 10 -> 8 Songs. Uebernommen.
- Harmonie-Merkmale fuer den Taktanfang: A 76,0 -> 87,5 %, B 75,8 -> 86,8 %. Uebernommen.
  In Python mit Kreuzvalidierung (A->B, B->A) 90,5 %; die alten Merkmale allein kamen auf 76 %.
- Fremd-Fenster nur ueber Oktaven (`foreign_family` = [1, 2, 0,5]): findet den 140-Teil in
  "Charade" (als 141,5), gewinnt aber keinen Tempowechsel-Set und teilt 5 Sets mit einem Tempo.
  Verworfen (Parameter bleibt, Standard die volle Familie).
- Tempo-Oktave nach Anschlagsdichte je Schlag (Gewicht auf |log2(Dichte / D0)|, D0 und Staerke
  per Gittersuche): auf A abgestimmt A +1, B -1; auf B abgestimmt B 0, A -1. Bei den x2-Fehlern
  liegt die Dichte der Map-BPM bei 7,5-11 Anschlaegen je Schlag (ueber dem 90. Perzentil der
  richtigen Sets), die Mapper waehlen dort also gegen die Dichte. Nicht uebernommen.
- Lokale Phasenverfolgung (Phasen-Rest je 16-Schlag-Fenster gegen das Hauptraster, stueckweise
  lineare Segmentierung per dynamischer Programmierung, Strafe nach Rauschen): bei jeder Strafe,
  die einen echten Wechsel (134 -> 132, 162 -> 160) findet, werden 36-95 von 209 Sets mit einem
  Tempo geteilt; die Phasensumme in 16 Schlaegen streut zu stark. Nicht uebernommen.

## Kennzahl Tempowechsel (Oktav-Abschnitte)

Folgen zwei Map-Abschnitte im Verhaeltnis 2 oder 0,5 aufeinander und liegt der zweite auf dem
Raster des ersten (z. B. 77 -> 154, 140 -> 280 -> 140), bilden sie eine Gruppe. Begruendung: der Puls
im Audio bleibt gleich, der Mapper verdoppelt nur die Notendichte; das ist eine Entscheidung des
Charts (Dichte je Abschnitt), nicht des Taktgitters, und `scaled()` bzw. die Teilung `div` von
`snap()` deckt sie ab. In einer Gruppe zaehlt jeder Abschnitt als richtig, wenn das erkannte Tempo
eines der Gruppen-Tempi trifft; Grenzen innerhalb der Gruppe muessen nicht getroffen werden.
Nicht-Oktav-Verhaeltnisse (165 -> 77,5, 138 -> 298) bleiben echte Wechsel.

## OSU_LEAD_MS

Gemessen als Median des Offset-Fehlers mit Vorzeichen ueber alle Sets mit richtigem Tempo
(Zeile "Offset-Fehler mit Vorzeichen" unten). Er liegt bei rund 0 ms mit `OSU_LEAD_MS = 23`;
der bisherige Wert ist damit fuer dieses Onset-Mass bestaetigt und bleibt. Phase am halben
Anstieg statt am Maximum (`phase_mode = "half"`) streut staerker und wurde verworfen.

## Messung

Wahrheit: rote Timing-Points der Diff mit den meisten Objekten je .osz in `maps/`.
Audio per `OszImporter`, Dekodierung wie `AudioMapper` (ffmpeg), nur im Test; das dezimierte
Signal liegt im Cache neben dem Onset-Fluss (`--aud` liest vorhandenes PCM).

<!-- MESSUNG:BEGIN -->
Gemessen mit `tests/run_am_grid_tests.gd -- --measure` in einem Prozess: 271 Sets ausgewertet (von 279 .osz, 8 uebersprungen). Wahrheit: rote Timing-Points der Diff mit den meisten Objekten.
Sets mit einem Tempo: 229 · mit Tempowechsel: 20 · mit absichtlich wechselndem Timing (>= 30 rote Linien oder >= 10 Abschnitte, getrennt gewertet): 22.

| Kennzahl (Spec, Zeile Takt) | Ziel | Ist |
|---|---|---|
| Tempo exakt (±0,5 %) gegen die rote Linie, Sets mit einem Tempo | ≥ 95 % | 88.2 % (202 von 229) |
| Tempo exakt oder gemeldete Alternative (x2, x0,5, x1,5, x0,667) trifft | ≥ 99 % | 99.1 % (227 von 229) |
| Offset-Fehler (Betrag, nur richtiges Tempo), Median / 95. Perzentil | ≤ 4 ms / ≤ 12 ms | 3.4 ms / 39.8 ms (n = 202) |
| Drift ueber den Song (letzter gegen ersten Schlag) | ≤ 10 ms | 97.0 % (196 von 202) der Songs ≤ 10 ms; Median 0.0 ms, 95. Perzentil 1.6 ms, Maximum 135.5 ms |
| Tempowechsel: jede Segmentgrenze auf ±1 Schlag und Tempo je Segment exakt (Oktav-Abschnitte als ein Segment, siehe unten) | ≥ 80 % | 25.0 % (5 von 20) |
| Taktanfang (Downbeat) stimmt mit der Map (richtiges Tempo, Map in 4/4 oder 3/4) | ≥ 85 % | 86.4 % (172 von 199) |

Zusatzwerte:

| Wert | Ist |
|---|---|
| Tempo exakt, Haelfte A (gerade Nummer) / Haelfte B (ungerade) | 85.2 % (92 von 108) / 90.9 % (110 von 121) |
| exakt oder die erste gemeldete Alternative trifft | 96.1 % (220 von 229) |
| exakt oder irgendeine gemeldete Alternative trifft (auch x3, x0,333, x0,75, x1,333) | 99.6 % (228 von 229) |
| Offset-Fehler mit Vorzeichen (erkannt minus Map), Median | 0.2 ms (0 = OSU_LEAD_MS stimmt) |
| Streuung um diesen Median, Median / 95. Perzentil (Phase am Maximum) | 3.3 ms / 39.6 ms |
| dasselbe mit Phase am halben Anstieg: Median Vorzeichen, Streuung Median / 95. Perzentil | -3.9 ms, 3.2 ms / 40.5 ms |
| Sets mit einem Tempo, die faelschlich in mehrere Segmente geteilt wurden | 0.0 % (0 von 229) |
| Tempowechsel: Tempo je Map-Segment exakt / Grenze auf ±1 Schlag | 51.1 % (23 von 45) / 0.0 % (0 von 22) |
| 3/4-Maps (richtiges Tempo): Taktart 3 erkannt | 0.0 % (0 von 1) |
| Maps mit anderer Taktart als 3 oder 4 (nicht in der Downbeat-Zeile) | 3 |
| Falscher Taktanfang bei richtiger Taktart | 2 Schlaege daneben: 13 · 1 Schlaege daneben: 6 · 3 Schlaege daneben: 3 · 0 Schlaege daneben: 3 ·  |
| Vertrauen im Mittel: richtiges Tempo / falsches Tempo | 0.82 / 0.60 |
| Sets mit absichtlich wechselndem Timing: Tempo des laengsten Abschnitts exakt | 59.1 % (13 von 22) |
| Rechenzeit track ohne Onset-Fluss, Median / Maximum je Song; je Minute Audio im Median | 965 ms / 2447 ms; 403 ms |
| Rechenzeit track() komplett (Onset-Fluss, Dezimierung, Chroma) fuer 4 min Audio, ein Lauf | 2316 ms |

### Sets mit einem Tempo und falschem Tempo (27)

| Set | Map-BPM | erkannt | Verhaeltnis | Alternative trifft | Vertrauen |
|---|---|---|---|---|---|
| 2326852 Sangatsu no Phantasia - Golden Ray | 243.00 | 121.50 | x0,5 (Oktave) | ja (Platz 1) | 0.52 |
| 315435 UNDEAD CORPORATION - The Empress scream o | 270.00 | 135.00 | x0,5 (Oktave) | ja (Platz 9) | 0.70 |
| mirror_2119120 | 95.00 | 190.31 | x2 (Oktave) | ja (Platz 1) | 0.79 |
| mirror_2128157 | 225.00 | 112.49 | x0,5 (Oktave) | ja (Platz 1) | 0.21 |
| mirror_2205779 | 240.00 | 120.00 | x0,5 (Oktave) | ja (Platz 3) | 0.53 |
| mirror_2217940 | 240.00 | 120.00 | x0,5 (Oktave) | ja (Platz 6) | 0.54 |
| mirror_2306091 | 118.00 | 177.00 | x1,5 (3:2) | ja (Platz 3) | 0.76 |
| mirror_2318291 | 270.00 | 135.00 | x0,5 (Oktave) | ja (Platz 1) | 0.40 |
| mirror_2438724 | 390.00 | 97.50 | x0,25 | nein | 0.64 |
| mirror_2442103 | 104.00 | 208.00 | x2 (Oktave) | ja (Platz 1) | 0.62 |
| mirror_2491936 | 110.00 | 220.00 | x2 (Oktave) | ja (Platz 1) | 0.79 |
| mirror_2506453 | 75.00 | 150.00 | x2 (Oktave) | ja (Platz 1) | 0.85 |
| mirror_2506744 | 93.00 | 186.00 | x2 (Oktave) | ja (Platz 1) | 0.89 |
| mirror_2511666 | 185.00 | 92.50 | x0,5 (Oktave) | ja (Platz 1) | 0.66 |
| mirror_2523688 | 105.00 | 210.00 | x2 (Oktave) | ja (Platz 1) | 1.00 |
| mirror_2532288 | 111.00 | 222.00 | x2 (Oktave) | ja (Platz 1) | 0.51 |
| mirror_2534361 | 100.00 | 200.00 | x2 (Oktave) | ja (Platz 1) | 0.39 |
| mirror_2541937 | 342.00 | 171.00 | x0,5 (Oktave) | ja (Platz 2) | 0.61 |
| mirror_2545184 | 218.00 | 109.00 | x0,5 (Oktave) | ja (Platz 1) | 0.37 |
| mirror_2545208 | 104.00 | 208.00 | x2 (Oktave) | ja (Platz 1) | 0.60 |
| mirror_2552898 | 90.00 | 180.00 | x2 (Oktave) | ja (Platz 8) | 0.15 |
| mirror_2578511 | 108.00 | 216.00 | x2 (Oktave) | ja (Platz 1) | 1.00 |
| mirror_2588413 | 200.00 | 100.00 | x0,5 (Oktave) | ja (Platz 2) | 0.67 |
| mirror_2591197 | 260.00 | 130.00 | x0,5 (Oktave) | ja (Platz 1) | 0.70 |
| mirror_283841 | 200.00 | 100.00 | x0,5 (Oktave) | ja (Platz 1) | 0.26 |
| mirror_349208 | 256.00 | 111.52 | kein einfaches Verhaeltnis (x0.436) | ja (Platz 10) | 0.25 |
| mirror_476691 | 100.00 | 200.00 | x2 (Oktave) | ja (Platz 1) | 0.73 |

### Sets mit Tempowechsel (20)

| Set | rote Linien | Map-Segmente (ab 2 s) | Tempo exakt | Grenzen getroffen | erkannte Segmente | erfuellt |
|---|---|---|---|---|---|---|
| 2096416 onoken - zeeros | 9 | 3 | 0 | 0 von 2 | 1 | nein |
| 2298540 Omerta - Charade (feat. Vincente Void _  | 9 | 5 | 2 | 0 von 4 | 1 | nein |
| 2299919 Sasuke Haraguchi feat. Choten-chan - Cub | 7 | 1 | 1 | 0 von 0 | 1 | ja |
| 347453 Igorrr & Ruby My Dear - Figue Folle | 3 | 3 | 2 | 0 von 2 | 1 | nein |
| mirror_1178589 | 4 | 3 | 2 | 0 von 2 | 1 | nein |
| mirror_1294997 | 2 | 2 | 2 | 0 von 0 | 1 | ja |
| mirror_2446560 | 6 | 2 | 0 | 0 von 1 | 1 | nein |
| mirror_2486779 | 7 | 2 | 1 | 0 von 1 | 1 | nein |
| mirror_2511692 | 3 | 2 | 1 | 0 von 1 | 1 | nein |
| mirror_2528018 | 2 | 2 | 0 | 0 von 1 | 1 | nein |
| mirror_2528075 | 2 | 2 | 1 | 0 von 1 | 1 | nein |
| mirror_2543662 | 2 | 1 | 1 | 0 von 0 | 1 | ja |
| mirror_2559592 | 6 | 3 | 2 | 0 von 2 | 3 | nein |
| mirror_2559688 | 4 | 1 | 0 | 0 von 0 | 1 | nein |
| mirror_2563805 | 3 | 2 | 2 | 0 von 1 | 1 | nein |
| mirror_2567618 | 8 | 1 | 1 | 0 von 0 | 2 | ja |
| mirror_2576239 | 4 | 3 | 3 | 0 von 0 | 1 | ja |
| mirror_2584545 | 3 | 2 | 1 | 0 von 1 | 1 | nein |
| mirror_2643833 | 2 | 2 | 1 | 0 von 1 | 1 | nein |
| mirror_332623 | 4 | 3 | 0 | 0 von 2 | 1 | nein |

### Sets mit absichtlich wechselndem Timing (22)

| Set | rote Linien | Abschnitte | BPM laengster Abschnitt | erkannt | erkannte Segmente |
|---|---|---|---|---|---|
| 1692937 Kataoka Tsugumi - Dream of You | 52 | 50 | 172.00 | 114.68 | 1 |
| 171880 xi - Happy End of the World | 60 | 60 | 190.00 | 95.00 | 1 |
| 1787141 Marmalade butcher - Immortality Math Clu | 48 | 9 | 205.00 | 205.00 | 1 |
| 2129944 Dustvoxx_ Loctek - Labyrinth of Mind | 16 | 15 | 190.00 | 190.00 | 3 |
| 2219350 Toromaru - Uncharted Sky | 27 | 14 | 164.00 | 164.00 | 1 |
| 2255741 ABSOLUTE CASTAWAY - step by step | 25 | 22 | 208.00 | 104.04 | 1 |
| 2289293 Tsukasa Kaminose - ruin of opals (Full V | 79 | 79 | 175.00 | 131.29 | 1 |
| 381334 aaaa - Bokutachi no Tabi to Epilogue.[Lon | 119 | 114 | 183.00 | 183.07 | 7 |
| mirror_2036133 | 14 | 14 | 155.00 | 155.39 | 1 |
| mirror_2278487 | 101 | 101 | 126.00 | 123.20 | 1 |
| mirror_240415 | 12 | 11 | 188.00 | 188.00 | 1 |
| mirror_2541305 | 44 | 44 | 145.00 | 145.00 | 1 |
| mirror_2542664 | 15 | 13 | 180.00 | 180.00 | 1 |
| mirror_2555375 | 10 | 10 | 205.00 | 205.00 | 5 |
| mirror_2559655 | 40 | 39 | 200.00 | 132.26 | 1 |
| mirror_2564470 | 78 | 72 | 180.00 | 178.51 | 1 |
| mirror_2593224 | 17 | 16 | 187.00 | 187.00 | 1 |
| mirror_2610887 | 15 | 15 | 157.00 | 117.74 | 1 |
| mirror_2616511 | 141 | 141 | 120.00 | 120.00 | 1 |
| mirror_274111 | 47 | 45 | 132.00 | 132.58 | 1 |
| mirror_576112 | 10 | 10 | 190.00 | 190.00 | 1 |
| mirror_971561 | 20 | 18 | 320.00 | 160.00 | 1 |

Uebersprungen: MLAR - AUTOPSIE (OMEN Auto).osz: eigenes Erzeugnis (OMEN Auto); MLAR - DEN HAAG (OMEN Auto).osz: eigenes Erzeugnis (OMEN Auto); c4rl - Immer (OMEN Auto).osz: eigenes Erzeugnis (OMEN Auto); mirror_2538892.osz: nicht lesbar; mirror_2556039.osz: nicht lesbar; mirror_2597846.osz: nicht lesbar; mirror_2598366.osz: nicht lesbar; mirror_2600955.osz: nicht lesbar
<!-- MESSUNG:END -->

## Was nicht erreicht ist und warum

- **Tempo exakt 88,2 % statt 95 %**: Fehler fast nur Oktaven (24 von 27: x2 / x0,5), einzelne 3:2.
  Bei diesen Songs ist die Wahl des Mappers musikalisch mehrdeutig (Halbtempo-Feel, 8tel so stark
  wie der Schlag). Weder Taktstruktur, Anschlagsdichte je Schlag (Runde 2), Snare-Lage,
  Kick-Snare-Muster noch ein Tempo-Vorwissen aus den Maps trennen sie (Runde 3, A/B-geprueft). Die richtige Antwort steht fast
  immer als erste Alternative; `scaled(grid, factor)` setzt sie um.
- **Offset 95. Perzentil 39,8 ms statt 12 ms**: wenige Songs (4 %) liegen um einen halben Schlag
  versetzt; dort ist der Gegenschlag im Fluss, in allen vier Baendern
  (Kick, Bass, Mitte, Hats) und im Bass-Akzent gleich stark oder staerker, und der erste deutliche
  Anschlag liegt ebenfalls auf dem Gegenschlag. Ohne sie liegt das Perzentil bei 14,7 ms. Das ist
  die Untergrenze dieses Onset-Masses: selbst mit der Periode und Phase der Map als Startwert
  liegt das Maximum des gefalteten Profils bei p95 13,6 ms (Mittelband 12,0 ms) neben der roten
  Linie, d. h. die Mapper-Offsets selbst streuen so stark.
- **Tempowechsel 25,0 % (5 von 20) statt 80 %**: Der Rest: kleine Wechsel (134 -> 132, 162 -> 160, 192 -> 184, 186 <-> 187)
  und kurze Teile (4-12 s mit 141, 199, 146,7 BPM). Die 4-s-Autokorrelation sieht sie nicht oder ordnet
  sie ueber die Familie (x0,75) dem Haupttempo zu; mit Oktav-Familie werden Sets mit einem Tempo
  geteilt, die lokale Phasenverfolgung ist zu verrauscht (Runde 2); Zweiteilung, Phasen-Rest je
  Fenster und fremde Fenster ohne Familien-Bezug trennen ebenfalls nicht (Runde 3). Offen:
  Beat-Tracker auf einem besseren Onset-Mass (gelernte Schlag-Aktivierung).
- **Drift**: wenige Songs, deren Tempo leicht neben der Map liegt (0,03-0,4 %) und nicht auf eine
  ganze BPM gezogen wird, meist Maps mit Phasenspruengen oder krummen BPM.
- **3/4**: nur eine 3/4-Map in den Daten, nicht erkannt; zu wenig fuer eine Abstimmung.

Rechenzeit: `track()` komplett (Onset-Fluss, Dezimierung, Chroma) fuer 4 min Audio 2,3 s
(Budget 4 s); Zeile in der Tabelle oben.
