# Kampagne (v1)

Ziel: ein Weg durch alle 13 Welten, der leicht beginnt und stetig schwerer wird.
Alle Spieler spielen dieselben Maps, damit die Scores vergleichbar sind.

## Aufbau

- Je Modus eine eigene Kampagne (Auswahl oben in der Szene). Fortschritt und Sterne je Modus getrennt
  (Stufen-IDs tragen den Modus: `mania-c03s2`).
- Mania 4K: vollstaendig, 13 Kapitel, je Kapitel eine Welt (`WorldTheme`), Finale in der Boss-Welt.
- Orbit, Rally, Dirigent, Trace, Rebound: Start mit je 1 Kapitel (6 Stufen, Band 1.0 - 1.8).
  Ein Modus ohne Kapitel steht in der Auswahl als "Kommt bald".
- Je Kapitel 5 Stufen und 1 Boss-Stufe (schwerste Map des Kapitels). Mania = 78 Stufen.
- Jede Stufe: feste Map + Diff (+ Mod) und drei Ziele.
- Ziel = 1 Stern, Zusatzziel = 2, Meisterziel = 3 (Mania maximal 234 Sterne).
  Zusatz- und Meisterziel zaehlen nur zusammen mit dem Hauptziel. Ein Fail erfuellt nie ein Ziel.
  Erfuellte Ziele bleiben erhalten (Sterne aus mehreren Laeufen addieren sich).
- Freischaltung: naechste Stufe nach dem Hauptziel, naechstes Kapitel nach der Boss-Stufe.
- Die Welt des Kapitels wird fuer die Stufe erzwungen (nur im Speicher, die Einstellung des
  Spielers bleibt). Mods legt die Stufe fest (NF gibt es in der Kampagne nicht).

Mania-Kapitel (Band = osu!mania-Sternwert der 4K-Diff):

| Nr | Welt | Band | Mod |
|----|------|------|-----|
| 1 | galaxy | 1.0 - 1.6 | |
| 2 | aurora | 1.4 - 2.0 | |
| 3 | neon | 1.8 - 2.4 | |
| 4 | eclipse | 2.2 - 2.8 | |
| 5 | abyss | 2.5 - 3.1 | |
| 6 | fractal | 2.8 - 3.4 | |
| 7 | storm | 2.6 - 3.2 | SV |
| 8 | obsidian | 3.2 - 3.8 | |
| 9 | monolith | 3.5 - 4.1 | |
| 10 | rift | 3.8 - 4.4 | |
| 11 | nerve | 4.1 - 4.7 | |
| 12 | singularity | 4.4 - 5.0 | |
| 13 | boss | 4.8 - 5.6 | |

Andere Modi, Kapitel 1: Orbit eclipse, Rally fractal, Dirigent obsidian, Trace aurora, Rebound abyss.

Ziel-Arten (`goals[].type`): `pass` (ohne Fail), `acc` (Genauigkeit ab Wert 0..1),
`grade` (Rang oder besser), `miss` (hoechstens n Misses, 0 = kein Miss).
Die Schwellen steigen linear von Kapitel 1 bis 13.

## Map-Liste (`data/campaign.json`)

Fest und fuer alle gleich, nach Modus gegliedert:
`{version, campaigns: {mania: {chapters: [...]}, orbit: ...}}`. Je Stufe: `id` (`mania-c03s2`), `boss`, `mode`, `mods`, `set_id`,
`beatmap_id`, `diff`, `md5` (der .osu), `artist`, `title`, `creator`, `map_stars`,
`length_s`, `bpm`, `goals`.

Auswahl: ranked osu!mania-Sets vom selben Mirror wie der Online-Browser
(osu.direct, `sort=play_count:desc`, erste 1200 Sets), nur 4K-Diffs (alle Modi spielen 4K),
Laenge 70 - 260 s (Kapitel 1 - 2 hoechstens 150 s), jedes Set nur einmal (ueber alle Modi). Je Stufe die
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

- Orbit, Rally, Dirigent, Trace, Rebound: Kapitel 2 bis 13 fehlen noch. Baender nach Spieltests festlegen.
- Sudden Death gibt es als Mod noch nicht. Das Ziel "Kein Miss" ersetzt es.
