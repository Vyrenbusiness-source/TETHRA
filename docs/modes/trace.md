# Trace (neuer Modus, 2026-11-12)

Ein Leuchtfaden waechst mit festem Tempo ueber die Flaeche und zeichnet die Map als Bild.
Nur osu!mania-4K-Maps (Notenfolge, Zeiten und Holds unveraendert, exakt im Takt).

## Regeln (verbindlich)
- **Wertung = Mania 4K:** `ManiaCore` unveraendert (OD-Fenster, MAX/300/200/100/50/Miss,
  ScoreV1, Holds wie osu!mania stable, Mods wie Mania). Spalte 0-3 = Mania-Tasten 1-4
  (Settings, Standard D F J K). Sterne = Mania-Sterne der Map, keine pp.
- **Faden:** Der Kopf bewegt sich mit konstantem Tempo `v` (Einstellung "Fadentempo", wie
  Scroll-Speed; nur Optik). Jede Note ist ein **Knick** an der Stelle, an der der Kopf zur
  Notenzeit ist. Neue Richtung absolut: Spalte 0 = links, 1 = runter, 2 = hoch, 3 = rechts
  (Pfeil-Konvention), Pfeil-Symbol in Spaltenfarbe am Knick.
  - Gleiche Richtung wie bisher (Jack/gleiche Spalte): **Knoten** auf gerader Strecke.
  - Gegenrichtung: enge **Haarnadel** (kleiner Halbkreis seitlich versetzt), nie auf
    sich selbst zurueck.
  - Akkord aus 2 Noten: **Diagonale** (z.B. links + hoch = nach links oben); Gegenpaar
    (links + rechts oder runter + hoch): Richtung bleibt, **Kreuzknoten**. 3-4 Noten:
    **Sternknoten**, Richtung bleibt.
  - Hold: Segment ab dem Knick **dick und leuchtend** bis zum Hold-Ende (Loslass-Marke).
- **Lesen:** Der kommende Weg (Vorlauf "Fadentempo"-abhaengig, ~1,2 s) ist fein vorgezeichnet,
  jeder Knick mit Pfeil + Annaeherungsring (schrumpft bis zur Notenzeit). Kamera folgt dem
  Kopf weich, Kopf etwa Bildmitte; Richtung zum kommenden Weg bleibt im Bild.
  Mindest-Segmentlaenge in der Darstellung (Streams) so, dass Pfeile sich nie ueberdecken
  (Tempo wird optisch angehoben, wenn noetig, nur Optik).
- **Gefuehl:** gespielte Strecke leuchtet in Spaltenfarbe nach, Miss = Faden franst/ergraut an
  der Stelle. Am Ende zoomt die Kamera heraus: das ganze Bild der Map (Endbild-Vorschau).
- Wertung deterministisch, Replays wie Mania (Modus "trace"), Multiplayer/Turniere wie
  Mania, Online-Submit mode "trace" (Counts wie Mania), ScoreStore-Modus "trace".

## Code
scripts/trace/ (trace_path.gd = Geometrie aus Notenliste, trace_view.gd, trace_game.gd),
scenes/trace.tscn, tests/run_trace_tests.gd.
