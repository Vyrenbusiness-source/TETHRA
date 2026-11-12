# Rebound (neuer Modus, 2026-11-12)

Vier Baelle huepfen ueber vier Trommelfellen. Jeder Ball landet genau auf den Noten seiner
Spalte. Nur osu!mania-4K-Maps (Notenfolge, Zeiten und Holds unveraendert, exakt im Takt).

## Regeln (verbindlich)
- **Anti-Mash (Replay-Regeln 2):** duenne Schicht in `rebound_game.gd` vor `ManiaCore`
  (unveraendert). Druck auf eine Spalte ohne Note im Miss-Fenster, waehrend eine andere Spalte
  eine ungewertete Note im 50er-Fenster hat = "WRONG KEY": die naechste solche Note ist sofort
  Miss. Richtige Taste zuerst, falsche danach: Treffer bleibt. Druck ohne Note im Fenster =
  nichts. Replays tragen als erstes Ereignis `{lane:-1, rules:2}`; Replays ohne Marke werden
  mit Hinweis abgelehnt. Messwerte: docs/anti_mash.md.
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
- **Hold-Ball (Optik):** vom ersten Moment des Flugs an Gold (in keiner Spaltenfarbe; Spalten
  sind kuehl Blau/Stahlblau), andere Form (dunkler Kern in Goldring, Mittelpunkt, Aussenring),
  duenner Faden ueber dem Ball (Laenge = Hold-Dauer, schmilzt beim Halten). Landering und
  Geister-Bogen sind doppelt/Ringe in Gold. Beim Halten: Fortschrittsring, Fell und Tastenplatte
  leuchten Gold. Normale Baelle: flache Scheibe. Felle flach mit klarer Kante, grosse Tastenplatte.
- **WRONG KEY:** `ReboundView.on_wrong_key(col)` zeigt kurz (0,8 s) einen dezenten Hinweis
  ueber der Spalte (rein optisch).
- **Gefuehl:** Squash & Stretch, Fell-Welle beim Treffer in Wertungsfarbe, Miss = Ball prallt
  matt ab und grau; dezente Lichtspur. Nie grell, kein Wackeln.
- Wertung deterministisch, Replays wie Mania (Modus "rebound"), Multiplayer/Turniere wie
  Mania, Online-Submit mode "rebound" (Counts wie Mania), ScoreStore-Modus "rebound".

## Code
scripts/rebound/ (rebound_flight.gd = Bahnen aus Notenliste, rebound_view.gd,
rebound_game.gd), scenes/rebound.tscn, tests/run_rebound_tests.gd.
