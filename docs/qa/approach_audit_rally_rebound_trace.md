# Vorlauf-Audit Rally, Rebound, Trace

Stand: nach v1.29.0. Frage des Nutzers: "manche Noten kommen direkt, man hat keine Chance, sie zu treffen".

## Messung

Fuer jede Note: Zeit von "erstmals lesbar" bis zur Trefferzeit, berechnet aus der Spawn- und Ansichtslogik des Spiels.
Fund = weniger als 450 ms.

Stichprobe: jede 24. Datei aus `maps/` (241 Sets), je Set bis zu 3 Mania-4K-Diffs: 25 Diffs, 21 353 Noten (Rally: 11 448 Schlaege).
Baender nach Notendichte (Noten je Sekunde): unter 4, 4 bis 8, ueber 8.

Was "lesbar" heisst:

- Rally: Ball und Landemarke erscheinen beim Gegnerschlag (`launch = t - Flugzeit`).
- Rebound: Ball im Flug zur Note (ab Ende der vorigen Note derselben Spalte bzw. ab Fallbeginn) oder Geister-Bogen.
- Trace: Knoten ist eingeblendet (ab 1200 ms, halb sichtbar ab 1070 ms) und liegt im Bild (Rand 40 Welt-px). Kamera aus `TraceView._camera`, Schritt 20 ms.

### Ergebnis vorher / nachher

| Modus, Einstellung | Noten | kleinster Vorlauf vorher | unter 450 ms vorher | kleinster Vorlauf nachher | unter 450 ms nachher |
|---|---|---|---|---|---|
| Rally, Flugzeit 450 / 800 / 1400, 3 und 4 Zonen | 11 448 | 450 / 800 / 1400 | 0 | unveraendert | 0 |
| Rebound, Fallzeit 1000 | 21 353 | 37 ms | 10 674 (49,99 %) | 900 ms | 0 |
| Trace, Dichte unter 4, Tempo 300 | 1 473 | 1040 ms | 0 | 1040 ms | 0 |
| Trace, Dichte unter 4, Tempo 520 | 1 473 | 419 ms | 7 (0,48 %) | 591 ms | 0 |
| Trace, Dichte unter 4, Tempo 900, 1920x1080 | 1 473 | 128 ms | 302 (20,50 %) | 591 ms | 0 |
| Trace, Dichte unter 4, Tempo 900, 1024x768 | 1 473 | 128 ms | 357 (24,24 %) | 591 ms | 0 |
| Trace, Dichte 4 bis 8, Tempo 300 | 3 771 | 433 ms | 2 (0,05 %) | 593 ms | 0 |
| Trace, Dichte 4 bis 8, Tempo 520 | 3 771 | 307 ms | 4 (0,11 %) | 591 ms | 0 |
| Trace, Dichte 4 bis 8, Tempo 900, 1920x1080 | 3 771 | 137 ms | 332 (8,80 %) | 591 ms | 0 |
| Trace, Dichte 4 bis 8, Tempo 900, 1024x768 | 3 771 | 137 ms | 410 (10,87 %) | 591 ms | 0 |
| Trace, Dichte ueber 8, Tempo 300, 1920x1080 | 9 490 | 51 ms | 181 (1,91 %) | 451 ms | 0 |
| Trace, Dichte ueber 8, Tempo 520, 1920x1080 | 9 490 | 51 ms | 201 (2,12 %) | 451 ms | 0 |
| Trace, Dichte ueber 8, Tempo 900, 1920x1080 | 9 490 | 62 ms | 1 066 (11,23 %) | 451 ms | 0 |
| Trace, Dichte ueber 8, Tempo 900, 1024x768 | 9 490 | 62 ms | 1 199 (12,63 %) | 451 ms | 0 |

Rebound "nachher" ist der Beginn der Vorschau. Der Geister-Bogen blendet ueber 200 ms ein, voll sichtbar ist er ab 700 ms.

## Funde und Fixes

### 1. Trace: Knoten erscheinen erst kurz vor der Trefferzeit im Bild

Ursache: Die Kamera (`TraceView._camera`) mittelt ihr Ziel ueber etwa 1 s und haelt nur den Kopf im Bild.
Nach einem Richtungswechsel haengt sie nach, der naechste Knoten liegt dann ausserhalb des Bildes.
Bei Tempo 900 legt der Faden in 450 ms 405 px zurueck, die halbe Bildhoehe ist 360 px.
Bei dichten Maps erzwingt `TracePath.MIN_SEG` laengere Wege, darum trifft es dort auch Tempo 300.

Fix: `TraceRules.fair_camera` schiebt die ruhige Kamera nur so weit, dass der Kopf und jeder Knoten der naechsten 600 ms im Bild liegen.
Zwischen 900 und 600 ms vor dem Knoten wird die Grenze weich angezogen, es gibt keinen Kamerasprung.
Ohne Zustand: gleiche Zeit ergibt gleiche Kamera (Pause, Seek, Replay).
Das Spiel nutzt dafuer `FairView` (Unterklasse von `TraceView` in `scripts/trace/trace_game.gd`).

Test: `tests/run_trace_mods_tests.gd`, 240 Knoten, Tempo 300 / 520 / 900, 1920x1080 und 1024x768: jeder Knoten mindestens 450 ms im Bild, Kamera hoechstens 60 px je 20 ms.

### 2. Rebound: schnelle Folgen in einer Spalte und die Note nach einem Hold ohne Vorschau

Ursache: Ein Ball fliegt erst los, wenn die vorige Note derselben Spalte vorbei ist.
Der Geister-Bogen zeigte nur den einen Huepfer nach der aktuellen Landung, und nur wenn er hoeher als 0,07 war (Flug ueber 317 ms).
Eine Folge mit 100 ms Abstand war darum nur 100 ms vorher zu sehen. Nach einem Hold begann der Flug erst am Hold-Ende.

Fix: `ReboundFlight.preview_range` liefert alle Fluege, die lueckenlos anschliessen und binnen 900 ms landen.
`ReboundView._draw_target` zeichnet sie als Geister-Boegen mit Ring am Landepunkt, auch flache Huepfer und den Huepfer nach einem liegenden Hold.
`ReboundFlight.readable_from` ist die Messgroesse dazu.

Test: `tests/run_rebound_tests.gd` `_test_preview` (Folge mit 100 ms, Note 80 ms nach Hold-Ende, Pause).

### 3. Trace: Mirror spiegelt doppelt, Pfeil und Tastenbuchstabe zeigen die falsche Taste

Ursache: `trace_game._apply_mods` tauscht die Notenspalten 0 und 3. `TraceView` spiegelte zusaetzlich das Bild und bildete den Tastenbuchstaben nochmal um.
Das Bild sah aus wie ohne Mirror, die Wertung verlangte aber die getauschte Taste. Wer dem Pfeil folgte, bekam "WRONG TURN".

Fix: `TraceMods.view_mods` gibt der Ansicht die Mods ohne MR, `FairView.setup` schaltet die zweite Spiegelung ab.
Der Weg laeuft jetzt gespiegelt, Pfeil und Buchstabe passen zur Taste. Wertung und Replay-Format sind unveraendert.

Test: `tests/run_trace_mods_tests.gd` (`view_mods`).

### 4. SV gibt in Rally, Rebound und Trace x1,1 ohne Wirkung

Ursache: Der Mehrspieler-Raum bietet NF und SV fuer jeden Modus an (`mp_lobby.gd`). Die drei Modi uebernahmen `ManiaCore.mod_multiplier` samt SV.
SV aendert dort nichts am Spiel, gab aber x1,1 und ein SV-Badge.

Fix: `RallyCore.setup`, `rebound_game._ready` und `trace_game._ready` (`TraceMods.strip_foreign`) entfernen SV vor Faktor und Badge.
Solo war nicht betroffen (`song_select._current_mods` setzt dort kein SV).

Test: `tests/run_rally_tests.gd` `_test_qa_fair`, `tests/run_trace_mods_tests.gd`.

### 5. Songstart ohne Audio: erster Ball mitten im Flug

Ursache: Laedt das Audio nicht, startet die Ersatzuhr fest bei -1000 ms.
Rally-Flugzeit geht bis 1400 ms, Rebound-Fallzeit bis 1600 ms, Trace zeigt 1200 ms Weg.
Der Lead-In galt nur fuer den Audio-Pfad.

Fix: `RallyChart.lead_in_ms`, `ReboundFlight.lead_in_ms`, `TraceRules.lead_in_ms` gelten fuer beide Pfade.
Mit Audio bleibt das Verhalten gleich (AudioLeadIn der Map, sonst Flugzeit + 900 / Fallzeit + 600 / 1900 ms vor der ersten Note).

Test: je Modus in den drei Testdateien.

## Geprueft ohne Fund

- Rally Flugzeit: fuer jeden Ball konstant gleich der Einstellung (450 bis 1400 ms, Standard 800). Schmetterbaelle, Aufladen, 3 und 4 Zonen gleich.
- Rally "Ausweichen in freie Zone": `spread_jacks` laeuft einmal beim Aufbau. Ball und Landemarke zielen vom Gegnerschlag an auf die endgueltige Zone. Kein Sprung im Flug, nicht reproduzierbar.
- Pause / Resume: Uhr steht, Countdown 3-2-1, kein Zeitsprung in den drei Modi.
- Retry: Szene wird neu geladen, gleicher Lead-In wie beim ersten Start.
- Replay-Start und Mehrspieler-Start: gleicher Ladepfad (`_load_beatmap`), gleicher Lead-In.
- Intro ueberspringen: springt auf 2500 ms vor der ersten Note bzw. dem ersten Gegnerschlag, mehr als jeder Vorlauf.
- Nach Breaks: Rally schlaegt neu auf (volle Flugzeit), Rebound laesst den Ball neu hereinfallen (Fallzeit 600 bis 1600 ms).
- Rebound Hereinfallen: der Ball ist schon bei Fallbeginn im Bild (Starthoehe 1,12 liegt bei 16:9 unter der Bildoberkante).
- Scroll Speed 1-40, SV-Mod Normal/Stark, FI, Cover: gibt es in diesen drei Modi nicht (nur Mania).
- Trace HD und SS: wirken nur auf die Wegpunkte (`TraceMods.path_alpha`). Knoten und Pfeile blenden immer ab 1200 ms ein. SS ist darum nie unfair.
- Mods im Replay: `GameSession._replay_mods` uebernimmt alle gespeicherten Mods (MR/HD/SS/NF), Trace liest sie beim Abspielen gleich.
- Mod-Faktoren: Trace MR 1,0, HD 1,06, SS 1,08, NF 0,5 (Produkt). Rally und Rebound: nur NF 0,5.

## Offen (nicht in den Dateien dieses Tasks)

- `TraceView` selbst behaelt die doppelte Spiegelung und die alte Kamera. Tutorial, Versus-Ansicht und Clips nutzen `TraceView` direkt. Sauber waere, `fair_camera` und `view_mods` in `scripts/trace/trace_view.gd` einzubauen und `FairView` zu entfernen.
- Trace SS: Beschreibung "nur 500 ms Weg voraus" stimmt nur fuer die Wegpunkte, die Pfeile bleiben 1200 ms sichtbar. x1,08 ist dafuer grosszuegig. Entscheidung des Nutzers.
- `mp_lobby.gd` bietet SV fuer alle Modi an. Der Schalter sollte ausserhalb von Mania ausgeblendet sein.
- Trace-Mods (MR/HD/SS) lassen sich im Mehrspieler-Raum nicht waehlen (nur NF/SV).

## Regeln und Server

Keine Aenderung an Wertungsfenstern oder Replay-Format: Rally `REPLAY_RULES` 4, Rebound 3, Trace `RULES` 2 bleiben. Kein neues `min_version` noetig.
Score-Aenderung nur im Mehrspieler mit SV in Rally, Rebound, Trace: Faktor 1,0 statt 1,1.

## Laeufe (Teil C)

Map `2280366 rejection - Calling [Hard]` (925 Noten), Fenster auf Monitor 2, Dummy-Audio.

| Lauf | Ergebnis |
|---|---|
| Rally, Rebound, Trace je `--autoplay`, 45 s (Test-Watchdog beendet den Lauf) | kein SCRIPT ERROR, kein Push-Error |
| Rally, Rebound, Trace je `--shot --shot-results` (Songende, Ergebnis-Bildschirm) | kein SCRIPT ERROR, Exit 0 |

Einzige Log-Zeile: `ERROR: File does not exist in zip archive:` (leerer Dateiname, `zip_reader.cpp:99`) beim Laden der Map in allen drei Modi. Kommt aus dem Import (nicht in den Dateien dieses Tasks), ohne Folgen im Spiel.

Nicht reproduziert: `Cannot call method create_timer on a null value` (Orbit, gehoert zum Orbit-Task).
Nicht gelaufen: ein ganzer Song per Autoplay in Echtzeit (Test-Watchdog 45 s), Pause / Retry / Quit / Fail per Hand im Fenster. Diese Pfade sind nur am Code geprueft.
