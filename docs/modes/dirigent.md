# Dirigent (neuer Modus, 2026-11-11)

Taktfigur mit Maus/Tablet fuehren (Zielen = Takt) und Einsaetze mit zwei Tasten setzen
(Tasten = Noten der .osz-Map).

## Regeln
- **Taktfigur**: feste Punkte je Taktart aus dem roten Timing-Point: 4/4 Schlagfigur
  (1 unten, 2 links, 3 rechts, 4 oben), 3/4 Dreieck (unten, rechts, oben), 2/4 (unten, oben),
  6/8 als 2 Hauptschlaege, ungerade Taktarten als Kreis mit n Punkten. Bei Schlaegen < 300 ms
  zaehlt die Figur halbe Takte (nur betonte Schlaege).
- **Zielen**: auf **jedem Schlag** muss der Cursor im Radius des aktuellen Schlagpunkts sein
  (Trefferradius fest, Zielfaktor 1,0 im inneren Halbradius bis 0,88 am Rand). Eine Leucht-
  spur zeigt die Bewegung vom letzten zum naechsten Punkt (Ideal-Weg), der Zielpunkt pulsiert
  kurz vor dem Schlag. Daneben = "Schlag verfehlt" (zaehlt als Miss im Takt-Anteil).
- **Einsaetze (Tasten)**: Noten der Map (zusammengefasst < 90 ms) als Tasten-Ereignisse:
  A (osu! ohne Whistle/Clap, Mania Spalten 1-2) / B (Whistle/Clap, Spalten 3-4), Finish bzw.
  Akkord ueber beide Seiten = beide. Anzeige: kleine Einsatz-Marken laufen auf einer Leiste
  unter der Figur auf eine Linie zu (wie ein Mini-Taiko-Streifen), Farbe = Taste.
- **Dynamik**: Kiai = Figur 30 % groesser (groessere Armbewegung), sehr leise Stellen kleiner;
  Taktwechsel aendern die Figur auf der naechsten Takt-Eins (eine Taktlaenge vorher angekuendigt).
- Zeitfenster aus OD wie Mania.

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
