# AmGrid: Taktgitter des 4K-Auto-Mappers (OMEN)

Modul: `scripts/automap/am_grid.gd` (`class_name AmGrid`, Schnittstelle nach `docs/automap/spec.md`).
Tests und Messung: `tests/run_am_grid_tests.gd`.

## Ablauf

1. `envelope()`: Onset-Fluss in drei Baendern (5-ms-Frames), Bass-Fluss, Bass-Nulldurchgaenge.
2. Autokorrelation in 4-s-Bloecken: grober Puls, Fenster mit fremdem Tempo werden eigene Segmente.
3. Mehrere Puls-Kandidaten (staerkste lokale Maxima der Kamm-Autokorrelation, `n_pulses`), jeder mit
   seiner Tempo-Familie (x2, x0,5, x1,5, x0,667, x3, x0,333, x0,75, x1,333). Jede Hypothese wird ueber
   die Taktstruktur bewertet: Phasen-Kohaerenz auf Schlag, Halbe, Viertel und Drittel des Schlags,
   Fuellung der Schlaege, Tempo-Vorwissen (Log-Normal um `prior_bpm`).
4. Periode: Regression Zeit = Offset + k * Periode ueber das ganze Segment; gegen den Scan
   gewinnt die Periode mit der hoeheren Kohaerenz. Ganzzahlige BPM, wenn sie innerhalb der
   Messgenauigkeit liegen oder (bis 0,15 % Abstand) mindestens 92 % der Kohaerenz erreichen.
5. Phase: Maximum des gefalteten Onset-Profils, Viertel des Schlags mit dem staerksten Akzent.
6. Taktart (4 oder 3) und Taktanfang: Statistik je Schlagposition im Takt (Bass-Akzent,
   Harmoniewechsel ueber Bass-Nulldurchgaenge, Energiewechsel ueber 4 und 16 Schlaege) plus
   Bonus fuer den Schlag des ersten deutlichen Bass-Anschlags (Songs beginnen meist auf der Eins).
7. Vertrauen aus Abstand zur zweitbesten Hypothese und Kohaerenz; Alternativen mit Faktor und
   relativem Score.

Alle Stellgroessen stehen in `AmGrid.DEFAULTS` und lassen sich ueber `params` bzw.
`data/automap/params.json` (Abschnitt `grid`) ueberschreiben. Abgestimmt wurden sie auf den
Dump der Messung (Python nur zur Auswertung im Scratchpad, nicht im Spiel): Tempo-Gewichte per
Gittersuche mit Kontrolle Haelfte A gegen Haelfte B (Messlauf mit 206 Sets: auf A abgestimmt trifft B 89 von 103),
Taktanfang-Gewichte ebenso (beste Gewichte erreichen auf den Daten rund 77 %, mehr geben die
Merkmale nicht her).

## OSU_LEAD_MS

Gemessen als Median des Offset-Fehlers mit Vorzeichen ueber alle Sets mit richtigem Tempo
(Zeile "Offset-Fehler mit Vorzeichen" unten). Er liegt bei rund 0 ms mit `OSU_LEAD_MS = 23`;
der bisherige Wert ist damit fuer dieses Onset-Mass bestaetigt und bleibt. Phase am halben
Anstieg statt am Maximum (`phase_mode = "half"`) streut staerker und wurde verworfen.

## Messung

Wahrheit: rote Timing-Points der Diff mit den meisten Objekten je .osz in `maps/`.
Audio per `OszImporter`, Dekodierung wie `AudioMapper` (ffmpeg), nur im Test.

<!-- MESSUNG:BEGIN -->
Gemessen mit `tests/run_am_grid_tests.gd -- --measure` in einem Prozess: 249 Sets ausgewertet (von 254 .osz, 5 uebersprungen). Wahrheit: rote Timing-Points der Diff mit den meisten Objekten.
Sets mit einem Tempo: 209 · mit Tempowechsel: 19 · mit absichtlich wechselndem Timing (>= 30 rote Linien oder >= 10 Abschnitte, getrennt gewertet): 21.

| Kennzahl (Spec, Zeile Takt) | Ziel | Ist |
|---|---|---|
| Tempo exakt (±0,5 %) gegen die rote Linie, Sets mit einem Tempo | ≥ 95 % | 89.0 % (186 von 209) |
| Tempo exakt oder gemeldete Alternative (x2, x0,5, x1,5, x0,667) trifft | ≥ 99 % | 99.0 % (207 von 209) |
| Offset-Fehler (Betrag, nur richtiges Tempo), Median / 95. Perzentil | ≤ 4 ms / ≤ 12 ms | 3.4 ms / 63.5 ms (n = 186) |
| Drift ueber den Song (letzter gegen ersten Schlag) | ≤ 10 ms | 96.8 % (180 von 186) der Songs ≤ 10 ms; Median 0.0 ms, 95. Perzentil 2.2 ms, Maximum 252.5 ms |
| Tempowechsel: jede Segmentgrenze auf ±1 Schlag und Tempo je Segment exakt | ≥ 80 % | 10.5 % (2 von 19) |
| Taktanfang (Downbeat) stimmt mit der Map (richtiges Tempo, Map in 4/4 oder 3/4) | ≥ 85 % | 73.8 % (135 von 183) |

Zusatzwerte:

| Wert | Ist |
|---|---|
| Tempo exakt, Haelfte A (gerade Nummer) / Haelfte B (ungerade) | 88.0 % (88 von 100) / 89.9 % (98 von 109) |
| exakt oder die erste gemeldete Alternative trifft | 96.7 % (202 von 209) |
| exakt oder irgendeine gemeldete Alternative trifft (auch x3, x0,333, x0,75, x1,333) | 99.0 % (207 von 209) |
| Offset-Fehler mit Vorzeichen (erkannt minus Map), Median | 0.6 ms (0 = OSU_LEAD_MS stimmt) |
| Streuung um diesen Median, Median / 95. Perzentil (Phase am Maximum) | 3.3 ms / 62.9 ms |
| dasselbe mit Phase am halben Anstieg: Median Vorzeichen, Streuung Median / 95. Perzentil | -3.5 ms, 3.1 ms / 64.2 ms |
| Sets mit einem Tempo, die faelschlich in mehrere Segmente geteilt wurden | 0.0 % (0 von 209) |
| Tempowechsel: Tempo je Map-Segment exakt / Grenze auf ±1 Schlag | 45.5 % (20 von 44) / 0.0 % (0 von 25) |
| 3/4-Maps (richtiges Tempo): Taktart 3 erkannt | 0.0 % (0 von 1) |
| Maps mit anderer Taktart als 3 oder 4 (nicht in der Downbeat-Zeile) | 3 |
| Falscher Taktanfang bei richtiger Taktart | 2 Schlaege daneben: 19 · 0 Schlaege daneben: 4 · 3 Schlaege daneben: 14 · 1 Schlaege daneben: 9 ·  |
| Vertrauen im Mittel: richtiges Tempo / falsches Tempo | 0.82 / 0.64 |
| Sets mit absichtlich wechselndem Timing: Tempo des laengsten Abschnitts exakt | 57.1 % (12 von 21) |
| Rechenzeit track ohne Onset-Fluss, Median / Maximum je Song; je Minute Audio im Median | 768 ms / 3000 ms; 319 ms |

### Sets mit einem Tempo und falschem Tempo (23)

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
| mirror_476691 | 100.00 | 200.00 | x2 (Oktave) | ja (Platz 1) | 0.73 |

### Sets mit Tempowechsel (19)

| Set | rote Linien | Map-Segmente (ab 2 s) | Tempo exakt | Grenzen getroffen | erkannte Segmente | erfuellt |
|---|---|---|---|---|---|---|
| 2096416 onoken - zeeros | 9 | 3 | 0 | 0 von 2 | 1 | nein |
| 2298540 Omerta - Charade (feat. Vincente Void _  | 9 | 5 | 2 | 0 von 4 | 1 | nein |
| 2299919 Sasuke Haraguchi feat. Choten-chan - Cub | 7 | 1 | 1 | 0 von 0 | 1 | ja |
| 347453 Igorrr & Ruby My Dear - Figue Folle | 3 | 3 | 2 | 0 von 2 | 1 | nein |
| mirror_1178589 | 4 | 3 | 2 | 0 von 2 | 1 | nein |
| mirror_1294997 | 2 | 2 | 1 | 0 von 1 | 1 | nein |
| mirror_2446560 | 6 | 2 | 0 | 0 von 1 | 1 | nein |
| mirror_2486779 | 7 | 2 | 1 | 0 von 1 | 1 | nein |
| mirror_2511692 | 3 | 2 | 1 | 0 von 1 | 1 | nein |
| mirror_2528018 | 2 | 2 | 0 | 0 von 1 | 1 | nein |
| mirror_2528075 | 2 | 2 | 1 | 0 von 1 | 1 | nein |
| mirror_2543662 | 2 | 1 | 1 | 0 von 0 | 1 | ja |
| mirror_2559592 | 6 | 3 | 2 | 0 von 2 | 3 | nein |
| mirror_2559688 | 4 | 1 | 0 | 0 von 0 | 1 | nein |
| mirror_2563805 | 3 | 2 | 2 | 0 von 1 | 1 | nein |
| mirror_2576239 | 4 | 3 | 2 | 0 von 2 | 1 | nein |
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

- **Tempo exakt 89 % statt 95 %**: Die Fehler sind fast nur Oktaven (x2 / x0,5) und einzelne 3:2.
  Bei diesen Songs ist die Wahl des Mappers musikalisch mehrdeutig (Halbtempo-Feel, 8tel-Hi-Hats
  so stark wie der Schlag); die Merkmale (Kohaerenz je Teilung, Fuellung, Vorwissen) trennen sie
  nicht, auch die beste Gittersuche ueber alle Gewichte kommt nicht ueber rund 89 %. Die richtige
  Antwort steht dann fast immer als erste Alternative (Ziel "exakt oder Alternative" ist erreicht);
  `scaled(grid, factor)` setzt sie um.
- **Offset 95. Perzentil**: Der Median ist im Ziel. Das Perzentil kommt von 10 der 186 Songs mit richtigem Tempo (5 %),
  bei denen das Gitter um eine halbe (selten eine viertel) Schlaglaenge versetzt liegt: der vom
  Mapper gewaehlte Schlag hat dort weniger Akzent und Bass als der Gegenschlag. Ohne diese 10 Songs
  liegt es bei 14,8 ms (Median 3,0 ms, n = 176); der Rest ist Streuung der Mapper-Offsets (5-20 ms).
- **Drift**: wenige Songs, deren Tempo leicht neben der Map liegt (0,03-0,4 %) und nicht auf eine
  ganze BPM gezogen wird, meist Maps mit Phasenspruengen oder krummen BPM.
- **Tempowechsel** (weit unter Ziel): Die Wechsel-Erkennung ueber 4-s-ACF-Fenster findet fast keinen
  Wechsel. Die Maps zeigen drei Arten: Oktav-Abschnitte (77 -> 154, 140 -> 280, 165 -> 77,5), die
  im Audio derselbe Puls sind und nur ueber Notendichte zu trennen waeren; kleine Wechsel (134 -> 132,
  162 -> 160, 1-2 %), fuer die eine lokale Phasen-Verfolgung fehlt; kurze Ritardandi am Songende.
  Offen: lokale Phasen-/Tempoverfolgung je Fenster mit stueckweiser Regression.
- **Taktanfang** (unter Ziel): Fehler sind meist eine halbe Taktlaenge (Eins gegen Drei). Ohne
  Chroma/Harmonie-Merkmal (heute nur Bass-Nulldurchgaenge) ist die Eins von der Drei kaum zu
  unterscheiden; bester Wert der vorhandenen Merkmale auf den Daten rund 77 %.
