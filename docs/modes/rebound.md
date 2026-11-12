# Rebound (neuer Modus, 2026-11-12)

Vier Baelle huepfen ueber vier Trommelfellen. Jeder Ball landet genau auf den Noten seiner
Spalte. Nur osu!mania-4K-Maps (Notenfolge, Zeiten und Holds unveraendert, exakt im Takt).

## Regeln (verbindlich)
- **Wertung = Mania 4K:** `ManiaCore` unveraendert (OD-Fenster, MAX/300/200/100/50/Miss,
  ScoreV1, Holds wie osu!mania stable, Mods wie Mania). Spalte 0-3 = Mania-Tasten 1-4
  (Settings, Standard D F J K). Sterne = Mania-Sterne der Map, keine pp.
- **Baelle:** Je Spalte ein Ball ueber einem Fell (4 Felle in einer Reihe, unteres Bilddrittel,
  Taste darunter). Der Ball fuer Note n startet beim Aufprall der vorigen Note derselben
  Spalte und landet exakt zur Notenzeit: Flugzeit = Abstand. Gipfelhoehe ~ Flugzeit^2,
  gedeckelt (lange Pausen = hoher Bogen bis knapp unter den oberen Rand).
  - Erster Ball / Pause > `MAX_AIR_MS` (1600): Ball faellt von oben herein, Fallzeit =
    Einstellung "Fallzeit" (600-1600 ms, Standard 1000, nur Optik).
  - Jack = schnelles Dribbeln (kleine Huepfer).
  - Hold: Ball bleibt **gequetscht** auf dem Fell liegen (Fell leuchtet, Ring fuellt sich)
    bis zum Hold-Ende, beim Loslassen startet er zur naechsten Note.
- **Lesen:** Landepunkt-Ring auf dem Fell schrumpft bis zur Notenzeit; feiner **Geister-Bogen**
  zeigt den Huepfer danach (uebernaechste Note der Spalte). Ballschatten auf dem Fell wird
  zur Landung kleiner/dunkler. Akkorde: Baelle landen gleichzeitig, kurze Verbindungslinie.
- **Gefuehl:** Squash & Stretch, Fell-Welle beim Treffer in Wertungsfarbe, Miss = Ball prallt
  matt ab und grau; dezente Lichtspur. Nie grell, kein Wackeln.
- Wertung deterministisch, Replays wie Mania (Modus "rebound"), Multiplayer/Turniere wie
  Mania, Online-Submit mode "rebound" (Counts wie Mania), ScoreStore-Modus "rebound".

## Code
scripts/rebound/ (rebound_flight.gd = Bahnen aus Notenliste, rebound_view.gd,
rebound_game.gd), scenes/rebound.tscn, tests/run_rebound_tests.gd.
