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
Gittersuche mit Kontrolle Haelfte A gegen Haelfte B (auf A abgestimmt trifft B 89 von 103),
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
<!-- MESSUNG:END -->

## Was nicht erreicht ist und warum

- **Tempo exakt 89 % statt 95 %**: Die Fehler sind fast nur Oktaven (x2 / x0,5) und einzelne 3:2.
  Bei diesen Songs ist die Wahl des Mappers musikalisch mehrdeutig (Halbtempo-Feel, 8tel-Hi-Hats
  so stark wie der Schlag); die Merkmale (Kohaerenz je Teilung, Fuellung, Vorwissen) trennen sie
  nicht, auch die beste Gittersuche ueber alle Gewichte kommt nicht ueber rund 89 %. Die richtige
  Antwort steht dann fast immer als erste Alternative (Ziel "exakt oder Alternative" ist erreicht);
  `scaled(grid, factor)` setzt sie um.
- **Offset 95. Perzentil**: Der Median ist im Ziel. Das Perzentil kommt von rund 4 % der Songs,
  bei denen das Gitter um eine halbe (selten eine viertel) Schlaglaenge versetzt liegt: der vom
  Mapper gewaehlte Schlag hat dort weniger Akzent und Bass als der Gegenschlag. Ohne diese Songs
  liegt das 95. Perzentil bei rund 12-15 ms; der Rest ist Streuung der Mapper-Offsets (5-20 ms).
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
