# Kampagne (v1)

Ziel: ein Weg durch alle 13 Welten, der leicht beginnt und stetig schwerer wird.
Alle Spieler spielen dieselben Maps, damit die Scores vergleichbar sind.

## Aufbau

- 13 Kapitel, je Kapitel eine Welt (`WorldTheme`). Das Finale ist die Boss-Welt.
- Je Kapitel 5 Stufen und 1 Boss-Stufe (schwerste Map des Kapitels) = 78 Stufen.
- Jede Stufe: feste Map + Diff + Modus (+ Mod) und drei Ziele.
- Ziel = 1 Stern, Zusatzziel = 2, Meisterziel = 3 (maximal 234 Sterne).
  Zusatz- und Meisterziel zaehlen nur zusammen mit dem Hauptziel. Ein Fail erfuellt nie ein Ziel.
  Erfuellte Ziele bleiben erhalten (Sterne aus mehreren Laeufen addieren sich).
- Freischaltung: naechste Stufe nach dem Hauptziel, naechstes Kapitel nach der Boss-Stufe.
- Die Welt des Kapitels wird fuer die Stufe erzwungen (nur im Speicher, die Einstellung des
  Spielers bleibt). Mods legt die Stufe fest (NF gibt es in der Kampagne nicht).

| Nr | Welt | Schwerpunkt | Gast (Stufe 3) | Sterne-Band (4K) | Mod |
|----|------|-------------|----------------|------------------|-----|
| 1 | galaxy | Mania | Trace | 1.0 - 1.6 | |
| 2 | aurora | Trace | Mania | 1.3 - 1.9 | |
| 3 | neon | Mania | Rebound | 1.7 - 2.3 | |
| 4 | eclipse | Orbit | Mania | 1.5 - 2.1 | |
| 5 | abyss | Rebound | Trace | 2.0 - 2.6 | |
| 6 | fractal | Rally | Orbit | 2.0 - 2.6 | |
| 7 | storm | Mania | Rally | 2.6 - 3.2 | SV |
| 8 | obsidian | Dirigent | Mania | 2.2 - 2.8 | |
| 9 | monolith | Orbit | Dirigent | 2.6 - 3.2 | |
| 10 | rift | Trace | Rebound | 3.2 - 3.8 | |
| 11 | nerve | Rebound | Orbit | 3.5 - 4.1 | |
| 12 | singularity | Mania | Trace | 4.0 - 4.7 | |
| 13 | boss | alle Modi, Finale Mania | | 4.3 - 5.2 | |

Das Band ist der osu!mania-Sternwert der 4K-Diff. Kapitel, die einen neuen Modus einfuehren,
setzen das Band bewusst etwas tiefer als das Kapitel davor.

Ziel-Arten (`goals[].type`): `pass` (ohne Fail), `acc` (Genauigkeit ab Wert 0..1),
`grade` (Rang oder besser), `miss` (hoechstens n Misses, 0 = kein Miss).
Die Schwellen steigen linear von Kapitel 1 bis 13.

## Map-Liste (`data/campaign.json`)

Fest und fuer alle gleich. Je Stufe: `id` (`c03s2`), `boss`, `mode`, `mods`, `set_id`,
`beatmap_id`, `diff`, `md5` (der .osu), `artist`, `title`, `creator`, `map_stars`,
`length_s`, `bpm`, `goals`.

Auswahl: ranked osu!mania-Sets vom selben Mirror wie der Online-Browser
(osu.direct, `sort=play_count:desc`, erste 1200 Sets), nur 4K-Diffs (alle Modi spielen 4K),
Laenge 70 - 260 s (Kapitel 1 - 2 hoechstens 150 s), jedes Set nur einmal. Je Stufe die
meistgespielte Map, deren Sterne zum Zielwert im Band passen. Aenderungen an der Liste =
neue `version` (alte Scores bleiben der alten Version zugeordnet).

Fehlende Maps laedt die Kapitelansicht beim Oeffnen automatisch ueber `BeatmapMirror.download`
(gleicher Weg wie der Online-Browser) und zeigt den Fortschritt.
Lokal gefunden wird eine Map ueber die Set-ID im Dateinamen und den Diff-Namen.

## Code

- `scripts/campaign/campaign.gd` (`Campaign`): Logik, statisch, testbar. Fortschritt in
  `user://campaign.json` (`--campaign-path=` fuer Tests/Harness).
- `scripts/campaign/campaign_screen.gd` + `scenes/campaign.tscn`: Kapitelweg, Stufenansicht.
- `GameSession.campaign`: laufende Stufe. `ResultsScreen` traegt den Lauf ein und zeigt
  Ziele, Sterne, "Naechste Stufe".
- Hauptmenue: Zeile "Kampagne" mit Sternestand.

## Ranglisten

- Je Stufe: vorhandene Online-Rangliste der Map (`GET /leaderboard?mode=..&md5=..`).
- Gesamt: lokal (Sterne, Punkte = Summe der Bestwerte). Server-Vorschlag fuer die
  Gesamtrangliste: `docs/net/campaign_server.md`.

## Tests

`tests/run_campaign_tests.gd`: Datenformat, Ziele, Sterne, Freischaltung, Speichern
(nur eigene Testdatei).

## Offen

- Sterne-Baender der Nicht-Mania-Modi sind geschaetzt (Mania-Sterne). Nach Spieltests anpassen.
- Sudden Death gibt es als Mod noch nicht. Das Ziel "Kein Miss" ersetzt es.
