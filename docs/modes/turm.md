# Turm (neuer Modus, 2026-11-11)

Bloecke im Takt einer normalen .osz-Map auf einen Turm stapeln. Genauigkeit ist sofort
sichtbar: ungenau = Turm wird schmaler.

## Ablauf
- Jede Note der Map ist ein **Block**. Er gleitet von links (Taste A) oder rechts (Taste B)
  waagerecht auf Hoehe der Turmspitze herein, mit konstanter Geschwindigkeit so, dass er
  **genau zur Notenzeit** mittig ueber dem Turm steht. Druck = Block faellt.
- Abweichung in ms -> seitlicher Versatz: der ueberstehende Teil wird abgeschnitten und faellt
  herunter, der Turm wird um diesen Teil schmaler. Stufen wie Mania (MAX/300/200/100/50/Miss
  aus OD): MAX = kein Verlust (+ kleiner Glanz), 300 = kaum, ... 50 = deutlich, Miss/zu spaet =
  Block faellt ganz, Kombo bricht.
- **Erholung**: 8 MAX in Folge machen den Turm wieder etwas breiter (bis zur Startbreite).
- Turm zu schmal (< 8 % Startbreite) = Fail (ausser NF).
- Taste aus der Map: osu! Whistle/Clap = B (von rechts), sonst A (von links); Mania: Spalten
  1-2 = A, 3-4 = B. Akkorde = ein Block, der von oben faellt (beide Tasten).
- Dichte begrenzen: Mindestabstand 1/4 Beat bzw. 90 ms (zusammenfassen), leichte Maps
  (< 2,5 Noten/s) hoechstens Achtel.

## Anzeige (clean)
- Ruhiger dunkler Hintergrund, Turm in der Mitte aus flachen Bloecken (Farbe je Taste),
  Kamera steigt weich mit der Turmspitze. Ankommender Block deutlich, der danach gedimmt
  sichtbar (Vorschau welcher Seite), feine Zielmarke (Mittellinie) ueber dem Turm.
- Treffer: Block setzt mit kurzem Aufprall auf, abgeschnittenes Stueck faellt und verblasst.
- Beat: dezente Pulse der Zielmarke auf jedem Schlag; Kiai etwas heller.
- Ende: Kamera faehrt langsam am ganzen Turm herunter (Ergebnis-Foto), dann Endbild.
- HUD wie Mania.

## Wertung
- Score/Acc/Grades wie Mania (ScoreV1-Formel). Zusatzwert "Turmhoehe" und "Restbreite %" im
  Endbild. Modus-ID "turm".

## Code
- `scripts/turm/turm_chart.gd` (Bloecke aus Beatmap), `scripts/turm/turm_core.gd` (Wertung,
  Breite), `scripts/turm/turm_game.gd` + `scenes/turm.tscn`, `scripts/turm/turm_view.gd`.
- Tests: `tests/run_turm_tests.gd`.
