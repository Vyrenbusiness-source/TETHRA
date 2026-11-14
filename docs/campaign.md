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
- Eine Stufe startet wie ein Start aus dem Song-Browser: eigene Einstellungen (2D/3D, Welt
  inklusive Auto, Scroll Speed, Skin, Notenfarben, Spurbreite, Hintergrund ...) und eigene Mods
  des Modus (Mania SV, Orbit HD/FI/PR, Trace MR/HD/SS). Dazu kommen die Mods der Stufe.
  No Fail gibt es in der Kampagne nicht (`Campaign.start_mods`, `Campaign.player_mods`).
- Die Kapitel-Welt ist nur Thema der Kampagnen-Ansicht (Kapitelbild, Name), im Spiel laeuft
  die Welt des Spielers.

## Skip-Pruefung und Einstufung

- Jedes Kapitel ausser dem letzten hat oben eine optionale Stufe "Skip-Pruefung": die Boss-Stufe
  zwei Kapitel weiter, im letzten Drittel die des letzten Kapitels (`Campaign.trial_target`).
  Modi mit nur einem Kapitel haben keine.
- Bestanden mit mindestens 99 % Accuracy (`TRIAL_ACC`) in einem Lauf, ohne Fail und ohne Mods,
  die die Wertung erleichtern (`EASY_MODS`: NF, CS/Konstant). Gilt fuer jeden Modus auf seine
  eigene Accuracy. Ungewertete Laeufe (`unranked`, z. B. eigene AR in Orbit) zaehlen auch nicht;
  Konstant kommt bei Mania aus `Settings.mod_constant`. Sonst passiert nichts; beliebig oft versuchbar, das Ergebnis nennt, was fehlte.
- Bestanden: alle Kapitel bis einschliesslich des Pruefungs-Kapitels sind offen, ihre Stufen alle
  spielbar. Weil der Lauf auch als Lauf der Boss-Stufe zaehlt, ist deren Hauptziel meist erfuellt
  und damit nach der normalen Regel auch das Kapitel danach offen.
- Sterne: Der Lauf zaehlt nur zur Boss-Stufe (keine doppelten). Uebersprungene Stufen haben keine
  Sterne, bis man sie nachholt. Stand: `skips[modus] = {to, from, stage, accuracy}`; die
  Gesamtzahl zaehlt nur echte Sterne. Ein spaeteres kleineres Bestehen senkt `to` nie.
- Einstufung: Ist ein Modus leer (kein Stern, kein Sprung), bietet der Kapitelweg "Einstufen" an.
  Pruefung von Kapitel 1, bestanden -> Pruefung des erreichten Kapitels usw.
  (`Campaign.placement_next`, Folge `placement_chain`, bei Mania 5 Pruefungen: Kapitel 1, 3, 5,
  7, 9), bis eine nicht bestanden ist oder das letzte Kapitel erreicht ist. Die Ansicht zeigt
  "Einstufung n von m". Ergebnis: hoechstes offenes Kapitel (`highest_open`), im Ergebnis
  "Einstufung beendet: Kapitel n". Abbrechen: Esc / Zur Kampagne (bestanden: zur neuen Front).
- Anzeige: Kapitelweg nennt "Skip-Pruefung: 99 % Accuracy · bis Kapitel n", uebersprungene
  Kapitel tragen "Uebersprungen" (ACCENT2, ruhiges Blaugrau); Sperrgrund nennt die Pruefung als
  zweiten Weg. HUD zeigt die Grenze mit der aktuellen Accuracy, das Ergebnis die erreichte
  Accuracy und welche Kapitel frei wurden.

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
Lokal gefunden wird eine Map ueber die Set-ID im Dateinamen und den Diff-Namen. Die Online-Quelle
setzt bei Mania die Tastenzahl vor den Namen (`[4K] Easy`), in der .osu steht nur `Easy`:
`Campaign.diff_matches` nimmt beides.

## Code

- `scripts/campaign/campaign.gd` (`Campaign`): Logik, statisch, testbar. Fortschritt in
  `user://campaign.json` (`--campaign-path=` fuer Tests/Harness).
- `scripts/campaign/campaign_screen.gd` + `scenes/campaign.tscn`: Kapitelweg, Stufenansicht.
  - Kapitelweg: 13 Weltbilder als Weg, je Kapitel Sterne und sechs Striche (geschafft/offen/
    gesperrt); unten das gewaehlte Kapitel mit den Covern seiner sechs Stufen (Boss mit
    Bernstein-Kante), Stand oder Sperrgrund.
  - Kapitel: links der Weg der Stufen (Wegpunkt, Cover, Titel, Sperrgrund, Sterne; Boss als
    Raute und groesser), darunter das naechste Kapitel. Rechts die gewaehlte Stufe: grosses Bild
    mit Titel, Schwierigkeit/Laenge/BPM/Diff, Ziele mit Stand (erfuellt oder Wert des Bestlaufs),
    Bestwert, Online-Rangliste mit Avataren, Start.
  - Bilder: lokales Thumbnail (`MapSet.thumb_texture`), sonst Online-Cover ueber die Set-ID
    (`Mirror.fetch_cover`, `assets.ppy.sh/.../card@2x.jpg`), sonst Platzhalter in Kapitel-Farbe.
    Gewaehlte Stufe: `GameSession.preload_selection` (wie der Song-Browser), dann grosses Bild,
    weichgezeichneter Hintergrund und Vorschau des Songs (Bus Music, weich ein/aus).
  - Bedienung: Maus waehlt, Start-Knopf startet; Pfeile waehlen, Enter oeffnet/startet, Esc
    zurueck. Weltbilder entstehen im WorkerThreadPool. Nicht geladene Map: Vorhoeren ueber
    `b.ppy.sh/preview/<set>.mp3` wie im Online-Browser.
- `scripts/campaign/campaign_hud.gd` (`CampaignHud`): Ziele im Spiel, links unter den Werten der
  Szene, live gehalten/offen/verloren (`Campaign.goals_live`) mit aktuellem Wert. GameSession
  haengt es an jede Spielszene einer Stufe (auch Neustart); beim Ergebnis blendet es sich aus.
- `GameSession.campaign`: laufende Stufe. `ResultsScreen` traegt den Lauf ein und zeigt
  Ziele, Sterne, "Naechste Stufe".
- Hauptmenue: Zeile "Kampagne" mit Sternestand.
- Autoplay (Testflag) traegt nie in den echten Stand ein, nur in eine `--campaign-path`-Datei.
- Harness Ansicht: `res://scenes/campaign.tscn --shot-campaign=<Praefix> [--maps-dir=<Ordner>]`
  speichert `_path.png`, `_path_locked.png`, `_stage.png`, `_locked.png`, `_trial.png`,
  `_result.png`, `_result_trial.png`, `_result_trial_fail.png`, `_path_skipped.png`, `_skipped.png`,
  `_placement.png`, `_placement_trial.png`
  (Demo-Stand, nichts wird gespeichert).
- Harness echter Stufenlauf (`--autoplay` vor einem `--`, sonst spielt niemand): `res://scenes/campaign.tscn --autoplay --shot-campaign-run=<Praefix>
  [--shot-campaign-stage=<Stufe>] [--shot-campaign-trial] --campaign-path=<Testdatei>` startet die Stufe, spielt sie,
  traegt ein, speichert `<Praefix>_stage.png`, `_game.png`, `_result.png` und beendet sich
  (Watchdog 145 s, aussen `timeout 150`).

## Ranglisten

- Je Stufe: vorhandene Online-Rangliste der Map (`GET /leaderboard?mode=..&md5=..`).
- Gesamt: lokal (Sterne, Punkte = Summe der Bestwerte). Server-Vorschlag fuer die
  Gesamtrangliste: `docs/net/campaign_server.md`.

## Tests

`tests/run_campaign_tests.gd`: Datenformat, Ziele, Sterne, Freischaltung, Speichern
(nur eigene Testdatei), Live-Ziele und Sperrgruende, Stufenstart mit eigenen Einstellungen in allen 6 Modi
(`_test_own_settings`) und eigenen Mods (`_test_start_mods`).

## Offen

- Orbit, Rally, Dirigent, Trace, Rebound: Kapitel 2 bis 13 fehlen noch. Baender nach Spieltests festlegen.
- Sudden Death gibt es als Mod noch nicht. Das Ziel "Kein Miss" ersetzt es.
