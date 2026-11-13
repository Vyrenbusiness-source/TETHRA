# Vorlauf-Audit Orbit und Dirigent

Stand: nach v1.29.0. Anlass: "manche Noten kommen direkt, man hat keine Chance, sie zu treffen".

## Messung

Für jedes Ziel: Zeit von "erstmals gezeichnet" bis Trefferzeit, aus der Logik von Konverter und
Ansicht gerechnet, nicht geschätzt.

- Orbit: `OrbitView.first_shown_ms(notes, i)` bildet die Zeichenregel der Ansicht nach
  (`spawn_ms` und Rang-Grenze `MAX_RANKS`), bei perfektem Spiel (jedes frühere Ziel ist zu seiner
  Zeit gewertet). Spielt jemand schlechter, bleiben frühere Ziele länger offen: der Wert ist
  die Obergrenze des Vorlaufs.
- Dirigent: `DirigentView.beat_lead_ms(chart, i)` (Schlag steht als Zielpunkt da) und
  `BAR_LEAD_MS` (Einsatz in der Leiste).
- Stichprobe: jede 5. Datei aus `maps/` (241 Dateien), alle Diffs: 239 Diffs, Orbit-Sterne von
  unter 3 bis 15, Mania und osu!standard. Orbit je Diff mit Vorlauf aus AR und mit 1 Runde.
- Grenze: 450 ms.

### Orbit, Vorlauf aus AR (139 806 Ziele)

| Sterne | Diffs | Ziele | vorher: erscheint < 450 ms | vorher: gezeichnet < 450 ms | vorher: kleinster Wert | nachher: < 450 ms | nachher: kleinster Wert |
|---|---|---|---|---|---|---|---|
| 0-3 | 70 | 18 673 | 2 | 21 | 387 ms | 0 | 483 ms |
| 3-5 | 80 | 42 630 | 39 | 595 | 300 ms | 0 | 454 ms |
| 5-7 | 62 | 47 282 | 330 | 6 628 | 301 ms | 0 | 450 ms |
| 7+ | 27 | 31 221 | 1 846 | 7 913 | 306 ms | 0 | 453 ms |
| Summe | 239 | 139 806 | 2 217 | 15 157 (10,8 %) | 300 ms | 0 | 450 ms |

Mit 1 Runde (Einstellung `orbit_laps` = 1): vorher 15 177 Ziele unter 450 ms. Nachher nicht
eigens gemessen: beide Untergrenzen (Konverter 450 ms, Ansicht 500 ms) hängen nicht von der
Rundenzahl ab. Zahl der Ziele und Sterne-Bänder sind vorher und nachher gleich.

Ganze Bibliothek nach dem Fix (`tests/run_orbit_tests.gd`, 976 Diffs, 2 Runden): kleinster
Vorlauf 450 ms, höchstens 8 Ziele zugleich erschienen, keine Konverter-Verstöße, Sterne-Median
4,24.

### Dirigent (239 Charts, 62 896 Schläge, 161 254 Einsätze)

| Größe | vorher | nachher |
|---|---|---|
| Einsatz in der Leiste | 1500 ms, immer | unverändert |
| erster Schlag nach einer Pause (39 Stellen) | 0 ms | 1500 ms |
| Schlag als Zielpunkt im Fluss | ein Schlagabstand (>= 340 ms, Regel `FAST_BEAT_MS`) | unverändert |
| Schlag als kleiner nummerierter Punkt | zwei Schlagabstände | unverändert |
| Schläge mit Abstand < 250 ms | 37 (0,06 %) | 37, offen (siehe unten) |

## Funde und Fixes

### 1. Orbit: Ansicht zeichnet nur 4 Ränge (Hauptursache, 12 940 der 15 157 Ziele)

Ursache: `orbit_view.gd` zeichnet ein erschienenes Ziel nur, wenn höchstens 3 frühere
Zeitpunkte offen sind (`MAX_RANKS` = 4). In dichten Folgen (Mindestabstand 75 ms) stand ein
Ziel darum erst 4 Abstände vor dem Treffer da: 300 ms bei 75 ms Abstand, obwohl der Konverter
es längst hatte erscheinen lassen.

Fix: `OrbitView.shown_rank()`. Ein Ziel jenseits von Rang 4 wird ab `READ_MS` = 500 ms vor
seiner Zeit trotzdem gezeichnet, blass wie der letzte Rang (ohne Ring). Keine Regeländerung,
nur Ansicht. Das Bild locker gesetzter Stellen ändert sich nicht.

Test: `tests/run_orbit_tests.gd`, `_test_min_lead` (170/200/260 BPM, 88 ms Abstand) und
Bibliothekstest "jedes Ziel der Bibliothek steht >= 450 ms vor seiner Zeit da".

### 2. Orbit: Teilrunden schneller Songs erscheinen nur einen Beat vorher (2 217 Ziele)

Ursache: `OrbitConverter._assign_laps`. Passt an einer dichten Stelle keine ganze Runde, kommt
das Ziel auf einem späteren Beat mit einer Teilrunde. Die Untergrenze war "halbe Runde und ein
Beat": bei 130-267 BPM ist das ein Beat, also 225-450 ms (gemessen ab 333 ms).

Fix: `MIN_LEAD_MS` = 450. Liegt der zugeteilte Beat-Tick näher an der Trefferzeit, erscheint
das Ziel auf dem Beat-Tick davor, der mindestens 450 ms Vorlauf gibt. Die Zuteilung (welche
Ziele bleiben, höchstens 6 zugleich) rechnet weiter mit dem alten Tick (`OrbitNote.slot_ms`).
Folge: gleiche Ziele, gleiche Zeiten, gleiche Sterne, Replays bleiben gültig. `REPLAY_RULES`
bleibt 5, kein neues `min_version` am Server. Nebenwirkung: an diesen Stellen sind kurz 7 oder
8 statt 6 Ziele erschienen (gezeichnet werden weiter höchstens 4 Ränge plus Fix 1).
`violations().visible` prüft die Zuteilung, der Bibliothekstest die echte Zahl (<= 8).

### 3. Dirigent: Figur ruht bis auf den ersten Schlag nach einer Pause (39 Stellen)

Ursache: `dirigent_view.gd` zeigte ab 700 ms nach dem letzten Schlag vor einer Lücke "Pause"
statt der Figur, und zwar bis der nächste Schlag schon vorbei war. Der erste Schlag nach jeder
Pause (wird gewertet: Hand am Punkt) hatte 0 ms Vorlauf.

Fix: `DirigentView.rest_at()`. Die Pause endet `REST_LEAD_MS` = 1500 ms vor dem nächsten
Schlag: Figur, Zielpunkt und Anflugring (ab 1100 ms) stehen dann da. Nur Ansicht.

Test: `tests/run_dirigent_tests.gd`, `_test_breaks`.

### 4. Orbit: SV gab x1,1 ohne Wirkung

Ursache: `OrbitCore.mod_multiplier` nahm den SV-Faktor aus Mania. SV wirkt in Orbit nicht (kein
Scroll). Der Song-Browser setzt SV in Orbit nicht, aber der Mehrspieler-Raum
(`lobby.gd`, Raum-Mods SV/NF) und das Profil (`profile_panel.gd:874`) reichen SV durch.

Fix: `OrbitCore.normalize_mods()`: SV zählt in Orbit nicht (kein Faktor, kein Badge, nicht in
der Replay-Meta). Betrifft nur die Punktzahl solcher Läufe (10 % weniger), nicht die Wertung
der Treffer: keine neue Replay-Regel. Am Server: Orbit-Scores mit SV nicht mehr mit 1,1 erwarten.

Test: `tests/run_orbit_replay_tests.gd`, `_test_orbit_mods`.

### 5. Orbit: HD und FI zusammen

Der Song-Browser schließt beide gegenseitig aus. Über gespeicherten Zustand, `--orbit-mods=`
oder eine Replay-Meta konnten beide an sein: der Satellit war dann nie zu sehen, Faktor
1,06 x 1,06. Fix: `normalize_mods()` lässt in dem Fall nur HD gelten. Test wie bei 4.

### 6. "Cannot call method 'create_timer' on a null value"

Ursache: Warte-Folgen in `orbit_game.gd` und `dirigent_game.gd` riefen nach einem `await`
`get_tree().create_timer` auf, auch wenn die Szene inzwischen gewechselt hatte (z. B.
`--shot-pause` nach `_wait_until`, das beim Verlassen der Szene nur zurückkehrt).

Fix: `_sleep(sec)` in beiden Spielen: wartet nur im Szenenbaum und meldet `false`, wenn die
Szene weg ist; alle 9 Stellen brechen dann ab. Zusätzlich Abbruch nach `_wait_until` im
Pausen-Shot und vor dem Rang-Klang im Endbild.

Test: `tests/run_orbit_replay_tests.gd`, `_test_rules_marker` (beide Spiele, Knoten ohne Szene).
Der Fehler selbst wurde nicht im Fenster nachgestellt: der Test deckt die Ursache ab, nicht
den genauen Ablauf des gemeldeten Falls.

## Geprüft, kein Fund

- Scroll Speed 1-40: in Orbit ohne Wirkung (`apply_scroll_speed` leer), Dirigent hat keine.
- Songstart: Orbit startet mit Vorlauf der ersten Note + 900 ms, Dirigent mit 1600 ms vor dem
  ersten Schlag, auch ohne AudioLeadIn. Intro-Skip springt auf 2200 ms (Orbit) bzw. 2400 ms
  (Dirigent) vor das erste Ziel.
- Pause/Resume: Countdown 3 x 0,4 s bei stehender Songzeit, Ziele bleiben gezeichnet; Orbit
  zeigt danach den Countdown-Ring am nächsten Ziel.
- Nach Breaks (Orbit): Vorlauf wie überall aus `spawn_ms`, in der Tabelle enthalten.
- Retry, Replay-Start, Mehrspieler-Start: laden dieselbe Szene, gleiche Zeitbasis; Mods
  bleiben in `GameSession.mods` stehen.
- HD: Satellit blendet zwischen 20 % und 55 % des Vorlaufs aus, das Ziel selbst bleibt.
  FI: Satellit erst in der letzten Runde. Beide ändern nicht, wann ein Ziel dasteht.
- PR: Fenster und Radius x 0,7, Faktor 1,12, im Replay aus der Meta (Tests vorhanden, ergänzt).
- NF: Orbit Faktor 0,5 und kein Scheitern. Dirigent hat kein Scheitern und keine Mods:
  NF ist dort ohne Wirkung und ohne Faktor (`mods: []`), also stimmig.
- Dirigent Taktwechsel: nächster Takt wird angekündigt, erster Schlag des neuen Takts steht
  einen Schlag vorher als nummerierter Punkt da.

## Offen

- Dirigent: 37 Schläge (0,06 %) mit weniger als 250 ms Abstand zum vorigen, an Grenzen roter
  Timing-Punkte (z. B. "Dream of You" Beginner bei 108,9 s: 197 ms). Der Punkt steht zwei
  Schläge vorher klein da, als Ziel aber nur 197 ms. Ein Fix ändert das Chart (Schlag
  streichen): Dirigent-`REPLAY_RULES` 3 -> 4 und alle Dirigent-Replays ungültig. Nicht gemacht.
- Orbit: Ring und Satellit (das Zeitmaß) zeigen weiter nur die 2 nächsten Ränge. In Folgen
  mit 75 ms Abstand steht der Ring 150 ms vorher; die Position steht 450 ms vorher. Das ist
  Optik des Modus und blieb unverändert.
- Orbit: bei über 533 BPM (Beat < 112,5 ms) wäre eine ganze Runde kürzer als 450 ms. In der
  Stichprobe kommt das nicht vor.
- Nicht im Fenster gespielt: Autoplay-Durchläufe mit Log-Prüfung, Pause/Retry/Quit mitten im
  Song, Fail, Replay ansehen, Mod-Auswahl-UI, Ergebnis-/Profil-Anzeige, Online-Submit,
  Mehrspieler-Raum. Diese Punkte sind nur am Code gelesen (siehe oben), nicht gelaufen.
- Server: NF/SV-Schalter im Song-Browser und im Raum gehören nicht zu diesem Task. SV im
  Orbit-Raum ist dort weiter wählbar, zählt jetzt aber nicht mehr.
