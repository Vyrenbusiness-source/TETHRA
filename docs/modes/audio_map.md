# Audio-Map (Eigene Musik -> Orbit-Map)

`AudioMapper` (`scripts/library/audio_mapper.gd`) macht aus einer .mp3/.ogg/.wav
eine osu!standard-.osz, die nur im Orbit-Modus gedacht ist (Mania bleibt
Original-4K). `generate(audio_path, maps_dir, difficulty)` blockiert (Aufrufer
startet den Thread) und liefert `{ok, osz_path, error, bpm, offset_ms, note_count}`.
Dauer: ca. 1 s pro Song (3-6 Minuten).

## Ablauf

1. ffmpeg (`ClipExporter.find_ffmpeg`, neben der Exe oder PATH) dekodiert zu
   mono 22050 Hz Float. Ohne ffmpeg: Fehler `ok=false`.
2. Onset-Fluss: 3 Baender (IIR, 250 Hz / 2,5 kHz), Log-Energie je 110-Sample-Hop
   (4,99 ms), positiver Fluss mit Band-Gewichten. Spitzen ueber adaptiver
   Schwelle; die Zeit ist der Beginn des Anstiegs (nicht das Maximum).
3. Tempo: Autokorrelation des Flusses (Grundperiode + 2L + Unterteilungen L/2,
   L/4, Oktav-Prior um 130 BPM, Bereich 75-190). Punktierte Muster: ist der
   2/3-Wert fast so stark (0,6), gilt er. Fein: Phasen-Resultierende der Onsets
   bei Grundton + 2. + 4. Oberschwingung (+-3 %), dann gewichtete Regression
   `t = Offset + k * Periode` ueber alle Onsets nahe am Raster (4 Durchlaeufe).
   Die Beat-Position unter den Teilungen waehlt der staerkste Grundton.
4. Noten: Onsets auf 1/2 (Leicht, Normal) oder 1/4 Beat (Schwer) gerastet,
   je Slot der staerkste. Quantil-Schwelle nach Staerke (Taktschlaege duerfen
   darunter), Prioritaet = Staerke x Betonung (Taktanfang 1,9, Beat 1,5,
   Achtel 1,15), Mindestabstand: Leicht 420 ms, Normal 240 ms, Schwer 140 ms.
   Takt-Phase = Beat (mod 4) mit der meisten Staerke.
5. Positionen: Kreis um (256, 192). Winkelschritt = 0,09 Grad/ms Abstand
   (10-34 Grad), Drehrichtung wechselt auf jedem 2. Taktanfang. Taktschlaege
   aussen (Radius 180, Ring B), Rest innen (Radius 90, Ring A). Damit liefert
   `OrbitConverter.convert_std` (POLAR) fluessige Winkel (Test: <= 0,3 Grad/ms).
   Gemessen: Leicht ca. 1,4, Normal 2,6, Schwer 5,2 Ziele/s.
6. Ausgabe: `<Kuenstler> - <Titel> (OMEN Auto).osz` mit `.osu` (Mode 0, ein
   roter Timing-Point) und dem unveraenderten Audio als `audio.<ext>`.
   Kuenstler/Titel aus den Tags (`ffmpeg -f ffmetadata`), sonst aus
   "Kuenstler - Titel" im Dateinamen, sonst Titel = Dateiname, Kuenstler = Unknown.

## Messung gegen echte Maps

`tests/run_audio_map_tests.gd -- --measure <maps-ordner> <anzahl>`: 40 gleichmaessig
gewaehlte Sets aus `maps/`, Audio extrahiert und analysiert, verglichen mit den
Noten der Map mit den meisten Objekten.

| Kennzahl | Wert |
|---|---|
| Tempo exakt (+-1 %) oder Oktave (x2, /2) der Map-BPM | 33 von 40 |
| Onset-Recall (echte Note hat Onset <= 30 ms) | 0,87 |
| Normal-Noten, die auf echte Noten fallen (<= 30 ms) | 0,75 im Mittel, 0,9+ bei klaren Songs |
| Songs mit Raster-Treffer >= 0,9 (echte Noten <= 20 ms am 1/4-Raster) | 22 von 40 |
| Takt-Offset dieser Songs: Mittel / mittlerer Betrag / Maximum | 0 ms / 2,6 ms / < 15 ms (alle 22) |

Synthetischer Klick-Track (128/100/150 BPM): BPM auf 0,05 genau, Offset < 6 ms
(Test), in der Praxis < 1 ms.

Befunde:
- Noten echter Maps liegen ~23 ms vor dem erkannten Anschlag (osu-Konvention,
  Lautstaerke-Anstieg vs. Wahrnehmung). `OSU_LEAD_MS = 23` zieht das in
  Timing-Point und Noten ab; `analyze()` bleibt rein akustisch. Ohne Korrektur
  lag der Versatz bei -10 bis -20 ms.
- Fehltempo (7 von 40): 3/4- oder 3/2-Verhaeltnis zum Map-Tempo (z. B. 183 -> 137)
  und Songs ohne klaren Schlag. Dann stimmt das Raster nicht, die Map ist
  zwar spielbar, aber nicht taktgenau. Verbesserung: Drei-gegen-Vier-Pruefung
  ueber die Taktstruktur, oder dem Nutzer Tempo x2 / x1,5 zur Wahl geben.
- Mehrfach-Tempo (BPM-Wechsel mitten im Song) wird nicht erkannt: ein Raster
  fuer den ganzen Song.
- Der Onset-Precision-Wert (~0,5) ist erwartet niedrig: Musik hat mehr Onsets
  als gemappte Noten.

## Tests

`tests/run_audio_map_tests.gd` (headless, ca. 2 s, braucht ffmpeg sonst SKIP):
Klick-Tracks -> BPM/Offset, Dichte je Schwierigkeit, vollstaendiger Lauf
.wav -> .osz -> `OszImporter` -> `OrbitConverter.convert_std`.
