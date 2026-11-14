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
Gemessen mit `tests/run_am_grid_tests.gd -- --measure` in einem Prozess: 254 Sets ausgewertet (von 259 .osz, 5 uebersprungen). Wahrheit: rote Timing-Points der Diff mit den meisten Objekten.
Sets mit einem Tempo: 214 · mit Tempowechsel: 19 · mit absichtlich wechselndem Timing (>= 30 rote Linien oder >= 10 Abschnitte, getrennt gewertet): 21.

| Kennzahl (Spec, Zeile Takt) | Ziel | Ist |
|---|---|---|
| Tempo exakt (±0,5 %) gegen die rote Linie, Sets mit einem Tempo | ≥ 95 % | 88.8 % (190 von 214) |
| Tempo exakt oder gemeldete Alternative (x2, x0,5, x1,5, x0,667) trifft | ≥ 99 % | 98.6 % (211 von 214) |
| Offset-Fehler (Betrag, nur richtiges Tempo), Median / 95. Perzentil | ≤ 4 ms / ≤ 12 ms | 3.2 ms / 39.8 ms (n = 190) |
| Drift ueber den Song (letzter gegen ersten Schlag) | ≤ 10 ms | 96.8 % (184 von 190) der Songs ≤ 10 ms; Median 0.0 ms, 95. Perzentil 2.2 ms, Maximum 135.5 ms |
| Tempowechsel: jede Segmentgrenze auf ±1 Schlag und Tempo je Segment exakt (Oktav-Abschnitte als ein Segment, siehe unten) | ≥ 80 % | 21.1 % (4 von 19) |
| Taktanfang (Downbeat) stimmt mit der Map (richtiges Tempo, Map in 4/4 oder 3/4) | ≥ 85 % | 86.1 % (161 von 187) |

Zusatzwerte:

| Wert | Ist |
|---|---|
| Tempo exakt, Haelfte A (gerade Nummer) / Haelfte B (ungerade) | 88.6 % (93 von 105) / 89.0 % (97 von 109) |
| exakt oder die erste gemeldete Alternative trifft | 96.3 % (206 von 214) |
| exakt oder irgendeine gemeldete Alternative trifft (auch x3, x0,333, x0,75, x1,333) | 99.1 % (212 von 214) |
| Offset-Fehler mit Vorzeichen (erkannt minus Map), Median | 0.2 ms (0 = OSU_LEAD_MS stimmt) |
| Streuung um diesen Median, Median / 95. Perzentil (Phase am Maximum) | 3.2 ms / 39.6 ms |
| dasselbe mit Phase am halben Anstieg: Median Vorzeichen, Streuung Median / 95. Perzentil | -3.9 ms, 3.2 ms / 40.5 ms |
| Sets mit einem Tempo, die faelschlich in mehrere Segmente geteilt wurden | 0.0 % (0 von 214) |
| Tempowechsel: Tempo je Map-Segment exakt / Grenze auf ±1 Schlag | 50.0 % (22 von 44) / 0.0 % (0 von 22) |
| 3/4-Maps (richtiges Tempo): Taktart 3 erkannt | 0.0 % (0 von 1) |
| Maps mit anderer Taktart als 3 oder 4 (nicht in der Downbeat-Zeile) | 3 |
| Falscher Taktanfang bei richtiger Taktart | 2 Schlaege daneben: 13 · 1 Schlaege daneben: 6 · 3 Schlaege daneben: 3 · 0 Schlaege daneben: 2 ·  |
| Vertrauen im Mittel: richtiges Tempo / falsches Tempo | 0.82 / 0.62 |
| Sets mit absichtlich wechselndem Timing: Tempo des laengsten Abschnitts exakt | 57.1 % (12 von 21) |
| Rechenzeit track ohne Onset-Fluss, Median / Maximum je Song; je Minute Audio im Median | 925 ms / 2383 ms; 402 ms |
| Rechenzeit track() komplett (Onset-Fluss, Dezimierung, Chroma) fuer 4 min Audio, ein Lauf | 2204 ms |

### Sets mit einem Tempo und falschem Tempo (24)

| Set | Map-BPM | erkannt | Verhaeltnis | Alternative trifft | Vertrauen |
|---|---|---|---|---|---|
| 2326852 Sangatsu no Phantasia - Golden Ray | 243.00 | 121.50 | x0,5 (Oktave) | ja (Platz 1) | 0.52 |
| 315435 UNDEAD CORPORATION - The Empress scream o | 270.00 | 135.00 | x0,5 (Oktave) | ja (Platz 9) | 0.70 |
| mirror_2119120 | 95.00 | 190.31 | x2 (Oktave) | ja (Platz 1) | 0.79 |
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
| mirror_2534361 | 100.00 | 200.00 | x2 (Oktave) | ja (Platz 1) | 0.39 |
| mirror_2541937 | 342.00 | 171.00 | x0,5 (Oktave) | nein | 0.61 |
| mirror_2545184 | 218.00 | 109.00 | x0,5 (Oktave) | ja (Platz 1) | 0.37 |
| mirror_2545208 | 104.00 | 208.00 | x2 (Oktave) | ja (Platz 1) | 0.60 |
| mirror_2552898 | 90.00 | 180.00 | x2 (Oktave) | ja (Platz 8) | 0.15 |
| mirror_2578511 | 108.00 | 216.00 | x2 (Oktave) | ja (Platz 1) | 1.00 |
| mirror_2588413 | 200.00 | 100.00 | x0,5 (Oktave) | ja (Platz 2) | 0.67 |
| mirror_2591197 | 260.00 | 130.00 | x0,5 (Oktave) | ja (Platz 1) | 0.70 |
| mirror_283841 | 200.00 | 100.00 | x0,5 (Oktave) | ja (Platz 1) | 0.26 |
| mirror_349208 | 256.00 | 111.52 | kein einfaches Verhaeltnis (x0.436) | ja (Platz 10) | 0.25 |
| mirror_476691 | 100.00 | 200.00 | x2 (Oktave) | ja (Platz 1) | 0.73 |

### Sets mit Tempowechsel (19)

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
| mirror_2576239 | 4 | 3 | 3 | 0 von 0 | 1 | ja |
| mirror_2584545 | 3 | 2 | 1 | 0 von 1 | 1 | nein |
| mirror_2643833 | 2 | 2 | 1 | 0 von 1 | 1 | nein |
| mirror_332623 | 4 | 3 | 0 | 0 von 2 | 1 | nein |

### Sets mit absichtlich wechselndem Timing (21)

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
| mirror_971561 | 20 | 18 | 320.00 | 160.00 | 1 |

Uebersprungen: mirror_2538892.osz: nicht lesbar; mirror_2556039.osz: nicht lesbar; mirror_2597846.osz: nicht lesbar; mirror_2598366.osz: nicht lesbar; mirror_2600955.osz: nicht lesbar
<!-- MESSUNG:END -->

## Was nicht erreicht ist und warum

- **Tempo exakt 88,8 % statt 95 %**: Fehler fast nur Oktaven (x2 / x0,5), einzelne 3:2. Bei diesen
  Songs ist die Wahl des Mappers musikalisch mehrdeutig (Halbtempo-Feel, 8tel so stark wie der
  Schlag). Weder die Taktstruktur-Merkmale noch die Anschlagsdichte je Schlag trennen sie (siehe
  Runde 2: die Mapper der x2-Faelle waehlen gegen die Dichte). Die richtige Antwort steht fast
  immer als erste Alternative; `scaled(grid, factor)` setzt sie um.
- **Offset 95. Perzentil 39,8 ms statt 12 ms**: 8 der 190 Songs (4 %) liegen noch um einen halben
  Schlag versetzt (vorher 10); dort ist der Gegenschlag im Fluss, in allen vier Baendern
  (Kick, Bass, Mitte, Hats) und im Bass-Akzent gleich stark oder staerker, und der erste deutliche
  Anschlag liegt ebenfalls auf dem Gegenschlag. Ohne sie liegt das Perzentil bei 14,7 ms. Das ist
  die Untergrenze dieses Onset-Masses: selbst mit der Periode und Phase der Map als Startwert
  liegt das Maximum des gefalteten Profils bei p95 13,6 ms (Mittelband 12,0 ms) neben der roten
  Linie, d. h. die Mapper-Offsets selbst streuen so stark.
- **Tempowechsel 21,1 % (4 von 19) statt 80 %**: mit der fairen Zaehlung der Oktav-Abschnitte
  sind 2 Sets dazugekommen. Der Rest: kleine Wechsel (134 -> 132, 162 -> 160, 192 -> 184, 186 <-> 187)
  und kurze Teile (4-12 s mit 141, 199, 146,7 BPM). Die 4-s-Autokorrelation sieht sie nicht oder ordnet
  sie ueber die Familie (x0,75) dem Haupttempo zu; mit Oktav-Familie werden Sets mit einem Tempo
  geteilt, die lokale Phasenverfolgung ist zu verrauscht (Runde 2). Offen: Beat-Tracker mit
  dynamischer Programmierung ueber einzelne Schlaege (Ellis) mit spektralem Onset je Band statt
  Phasensummen ueber Fenster.
- **Drift**: wenige Songs, deren Tempo leicht neben der Map liegt (0,03-0,4 %) und nicht auf eine
  ganze BPM gezogen wird, meist Maps mit Phasenspruengen oder krummen BPM.
- **3/4**: nur eine 3/4-Map in den Daten, nicht erkannt; zu wenig fuer eine Abstimmung.

Rechenzeit: `track()` komplett (Onset-Fluss, Dezimierung, Chroma) fuer 4 min Audio 2,2 s
(Budget 4 s); Zeile in der Tabelle oben.
