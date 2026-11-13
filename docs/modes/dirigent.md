# Dirigent (neuer Modus, 2026-11-11)

Taktfigur mit Maus/Tablet fuehren (Zielen = Takt) und Einsaetze mit zwei Tasten setzen
(Tasten = Noten der .osz-Map).

## Regeln
- **Anti-Mash (Regeln 2):** Taste, die kein offener Einsatz verlangt, waehrend ein Einsatz im
  50er-Fenster eine andere Taste verlangt = "WRONG KEY": dieser Einsatz ist sofort Miss. Akzent
  (beide) zaehlt nur mit beiden Tasten; ein A-/B-Einsatz wird mit seiner Taste gewertet. Richtige
  Taste zuerst, Zusatztaste danach: Treffer bleibt. Replay-Marke rules = 2.
- **Regeln 3 (2026-11-13, spielbar mit zwei Fingern):**
  - *Wechselschlag:* folgt ein Einsatz in weniger als `FAST_KEY_MS` = 180 ms auf den vorigen,
    nimmt er die andere Taste; ein Akzent (beide) mit einem Nachbarn naeher als 180 ms wird ein
    einfacher Einsatz (`DirigentChart.playable_keys`). Zeiten und Zahl der Einsaetze bleiben.
    Ab 180 ms gilt die Taste aus der Map (Klang bzw. Spaltenseite).
  - *Nachzuegler:* nach einem verfehlten Einsatz ist ein Druck seiner Taste bis 50er-Fenster +
    37 ms frei (einmal): er macht den naechsten Einsatz nicht zum Miss.
  - Sterne: jeder Einsatz unter 180 ms Abstand zaehlt +0,5 (`STAR_FAST_W`).
  - Replay-Marke rules = 3 (rules 2 wird abgelehnt). Messwerte: docs/modes/gameplay_tune.md.
- **Taktfigur**: feste Punkte je Taktart aus dem roten Timing-Point: 4/4 Schlagfigur
  (1 unten, 2 links, 3 rechts, 4 oben), 3/4 Dreieck (unten, rechts, oben), 2/4 (unten, oben),
  6/8 als 2 Hauptschlaege, ungerade Taktarten als Kreis mit n Punkten. Bei Schlaegen < 340 ms
  bleibt die **volle Figur**: jeder Punkt bekommt mehr Zeit (2 oder mehr Beats je Punkt,
  Punktabstand >= 340 ms), die Figur dauert dann mehrere Takte. Nie hektisch: Sprung-Tempo
  der Hand <= 5 Einheiten/s im Mittel (Test + Bot-Messung, Spitze <= 8,5).
- **Zielen**: auf **jedem Schlag** muss der Cursor im Radius des aktuellen Schlagpunkts sein
  (Trefferradius fest, Zielfaktor 1,0 im inneren Halbradius bis 0,88 am Rand). Anzeige: der
  aktuelle Zielpunkt gross mit Anflugring (schrumpft bis zum Schlag), der naechste klein
  nummeriert, die uebrigen Punkte nur als kleine Marken; Leuchtspur nur fuer den Weg zum
  Zielpunkt (Ideal-Weg); die Figur liegt auf einer runden Buehne (Graphit-Scheibe), an deren Rand die Takt-Uhr laeuft (ein Strich je Schlag der Figur, Schlag 1 oben, Bernstein-Bogen = Stelle im Takt). Daneben = "Schlag verfehlt" (zaehlt als Miss im Takt-Anteil).
- **Einsaetze (Tasten)**: Noten der Map (zusammengefasst < 90 ms) als Tasten-Ereignisse:
  A (osu! ohne Whistle/Clap, Mania Spalten 1-2) / B (Whistle/Clap, Spalten 3-4), Finish bzw.
  Akkord ueber beide Seiten = beide. Anzeige: kleine Einsatz-Marken laufen auf einer Leiste
  unter der Figur auf eine deutliche Trefferlinie zu (wie ein Mini-Taiko-Streifen), Farbe + Form
  = Taste (A = Kreis, B = Raute, Legende links in denselben Formen). Schlag-Ticks auf der Leiste
  zeigen das Raster der Figur: Einsaetze auf Off-Beats und Gleichzeitigkeit mit der Hand
  sind direkt lesbar. Die Taktart steht klein an der Leiste.
- **Dynamik**: Kiai = erweiterte 4/4-Figur (weiteres Ausholen) und 15 % groesser, sehr leise
  Stellen 20 % kleiner; Figur und Groesse stehen je Figurdurchlauf fest;
  Taktwechsel aendern die Figur auf der naechsten Takt-Eins (eine Taktlaenge vorher angekuendigt).
- Zeitfenster aus OD wie Mania. HUD wie Mania (Rang + Genauigkeit links, Punkte/Takt/Einsaetze rechts).

## Wertung
- Zwei Anteile: Takt (alle Schlaege: getroffen + Zielfaktor) 40 %, Einsaetze (Stufen wie
  Mania) 60 %; Score max 1.000.000 x Mod-Faktor; Acc = gewichtetes Mittel; Grades wie Mania.
- stats(): n_max..n_miss (Einsaetze), beats_hit, beats_total, aim_err, max_combo (gemeinsame
  Kombo aus Schlaegen und Einsaetzen), accuracy, score, grade, mode "dirigent".

## Wettbewerb und Multiplayer (Pflicht)
- Deterministisch, Ereignis-Log-Replays, Sterne 0..15 (Tempo der Figur, Einsatz-Dichte,
  Gleichzeitigkeit), ScoreStore-Modus "dirigent", Online-Submit mode "dirigent".
- Multiplayer: Live-Score und Endergebnis ueber Lobby wie mania_3d/orbit_game, Turniere.

## Code
scripts/dirigent/ (dirigent_chart.gd, dirigent_core.gd, dirigent_view.gd, dirigent_game.gd),
scenes/dirigent.tscn, tests/run_dirigent_tests.gd.
