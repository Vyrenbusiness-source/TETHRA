# Echo (neuer Modus, 2026-11-11)

Ruf und Antwort im Takt einer normalen .osz-Map (osu!standard oder Mania).

## Ablauf
- Der Song laeuft normal. Die Map wird in **Phrasen** geteilt: je ein Takt (rote Timing-
  Points, Taktart aus dem Timing-Point; bei Takten < 1,6 s zwei Takte je Phrase).
- Phrasen wechseln: **Hoeren** (Ruf) und **Du** (Antwort). In einer Hoeren-Phrase zeigt die
  Taktleiste die Noten der Map dieses Abschnitts: jede Note leuchtet auf ihrem Zeitpunkt auf
  und spielt ihren Hitsound (hoch = Taste B, tief = Taste A). In der folgenden Du-Phrase ist
  die Leiste leer: der Spieler spielt **denselben Rhythmus um genau eine Phrase versetzt** nach.
- Gewertet wird jede Antwort-Note gegen die Ruf-Note + Phrasenlaenge (Zeitfenster aus OD,
  Stufen wie Mania MAX/300/200/100/50/Miss) und die richtige Taste.
- Die Noten fuer den Ruf kommen aus der Map: Noten dieser Phrase (Mindestabstand 1/4 Beat,
  hoechstens 8 Noten pro Phrase, leichte Maps hoechstens 4 und nur Viertel/Achtel; ueberzaehlige
  werden nach Beat-Staerke ausgewaehlt). Taste: osu!-Hitsound Whistle/Clap = B, sonst A;
  Mania: Spalten 1-2 = A, 3-4 = B. Phrasen ohne Noten: Pause (Leiste zeigt "Pause").
- Die Antwort-Phrase ignoriert die Noten der Map in diesem Abschnitt (die Musik spielt weiter).

## Anzeige (clean, gut lesbar)
- Eine breite **Taktleiste** in der Bildmitte: Raster mit Takt-Eins dick, Schlaege mittel,
  Achtel fein; ein **Spielkopf** laeuft genau im Tempo von links nach rechts.
- Ruf-Noten: Punkte in Tastenfarbe (A kuehl unten, B warm oben auf der Leiste), leuchten beim
  Spielkopf auf. In der Du-Phrase erscheinen die Treffer des Spielers an ihrer Stelle; nach
  der Phrase wird kurz der Vergleich gezeigt (Geister der Ruf-Noten, Abweichung als feiner Strich).
- Grosser ruhiger Status ueber der Leiste: "HOEREN" bzw. "DU", mit 4er-Vorzaehler im letzten
  Takt vor dem ersten Ruf.
- HUD wie Mania (Score, Genauigkeit, Kombo, HP).

## Wertung
- Score/Acc/Grades wie Mania (ScoreV1-Formel, Genauigkeit wie Mania). HP: Miss zieht ab.
- Modus-ID "echo" (eigene ScoreStore-Sektionen, Bestenliste lokal; Online folgt mit Server).

## Code
- `scripts/echo/echo_chart.gd` (Phrasen + Ruf-Noten aus Beatmap, statisch testbar),
  `scripts/echo/echo_core.gd` (Wertung), `scripts/echo/echo_game.gd` + `scenes/echo.tscn`
  (Szene, Eingabe, HUD, Endbild mit vorhandenem Results-Baustein), `scripts/echo/echo_view.gd`.
- Tests: `tests/run_echo_tests.gd`.
