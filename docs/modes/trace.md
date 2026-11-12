# Trace (neuer Modus, 2026-11-12)

Ein Leuchtfaden waechst mit festem Tempo ueber die Flaeche und zeichnet die Map als Bild.
Nur osu!mania-4K-Maps (Notenfolge, Zeiten und Holds unveraendert, exakt im Takt).

## Regeln (verbindlich)
- **Wertung = Mania 4K:** `ManiaCore` unveraendert (OD-Fenster, MAX/300/200/100/50/Miss,
  ScoreV1, Holds wie osu!mania stable, Mods wie Mania). Spalte 0-3 = **eigene Trace-Tasten**
  (`Settings.trace_keys`, Standard Pfeiltasten LINKS RUNTER HOCH RECHTS, Tasten-Seite der
  Einstellungen, gleiche Konflikt-Pruefung wie andere Modi). Rebound nutzt weiter die
  Mania-Tasten. Sterne = Mania-Sterne der Map, keine pp.
- **Anti-Mash (Regeln 2, `scripts/trace/trace_rules.gd`):** duenne Schicht vor ManiaCore,
  deterministisch und replay-faehig. Druck in einer Spalte ohne ungewertete Note im
  Miss-Fenster, waehrend eine andere Spalte eine ungewertete Note im 50er-Fenster hat =
  **falscher Knick**: diese Note (Akkord: alle Akkordnoten, Abstand <= 2 ms) sofort Miss,
  Kombo bricht, Ansicht franst aus (`on_wrong_turn(idx)`), Text "WRONG TURN". Bei Akkorden
  zaehlen nur Akkord-Spalten, jede weitere Spalte macht den (Rest-)Akkord zum Miss. Druck
  ohne Note in irgendeinem Fenster = nichts. ManiaCore bekommt nur `miss_note`,
  `pending_head`, `lane_busy` (Mania-Verhalten unveraendert). Replay meta `rules` = 2;
  Replays mit rules 1 werden mit Hinweis abgelehnt.
- **Hooks (nur wenn die Datei existiert):** `trace_mods.gd` (`map_column`, `from_session`,
  Spalten der Noten vor Pfad und Wertung umbilden), `trace_sound.gd` (Node: `on_turn(col,
  quality)`, `on_wrong()`, `on_hold(col, on)`), `trace_picture.gd` (`render(path, judgements,
  size)`; Ergebnisdaten `trace_picture` = {path: TracePath, judgements: Array}).
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
scripts/trace/ (trace_path.gd = Geometrie aus Notenliste, trace_view.gd, trace_game.gd,
trace_rules.gd = Anti-Mash),
scenes/trace.tscn, tests/run_trace_tests.gd.
