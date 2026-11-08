# Orbit-Modus

Eigener Modus: zielen mit Maus/Tablet, tippen mit zwei Tasten. Ziele liegen auf
zwei Ringen um die Bildschirmmitte. Der Cursor-**Winkel** zur Mitte waehlt die
Richtung, die **Taste** den Ring (Taste A = innen, Taste B = aussen; Standard
Maus links/rechts und Z/X, umbelegbar). Ein Treffer zaehlt nur, wenn Zeitfenster
**und** Winkel stimmen.

Code: `scripts/orbit/orbit_note.gd` (Ziel), `scripts/orbit/orbit_converter.gd`
(Map-Umwandlung), `scripts/orbit/orbit_core.gd` (Wertung),
`scripts/orbit/orbit_view.gd` (Spielfeld), `scripts/orbit/orbit_game.gd`
(Szene: Eingabe, HUD, Pause, Multiplayer), `scripts/orbit/orbit_results.gd`
(Endbild). Tests: `tests/run_orbit_tests.gd`, `tests/run_orbit_play_tests.gd`.

## Winkel

0 Grad = oben, im Uhrzeigersinn steigend. `angle_deg` liegt in [0, 360).
`end_angle_deg` ist nicht gefaltet: `end_angle_deg - angle_deg` ist der
vorzeichenbehaftete Bogen (+ = im Uhrzeigersinn). Die Bogen-Spitze zur Zeit t
liefert `OrbitNote.angle_at(t)`.

## Regeln (OrbitCore)

- Zeitfenster (aus OD, wie Mania), HP und Zaehler kommen aus einem
  ManiaCore-Objekt. **Score, Acc und Grade sind eigene Orbit-Regeln**, siehe
  Wertung. `stats()` liefert dieselben Felder wie ManiaCore plus `aim_err`
  und `mode` = "orbit".
- Tap: Taste des richtigen Rings im 50er-Fenster, Cursor hoechstens
  `ANGLE_TOL_DEG` = 22 Grad neben dem Ziel. Falscher Ring oder falscher Winkel
  = kein Treffer (das Ziel bleibt offen, bis sein Fenster ablaeuft = MISS).
- Zu frueh (zwischen 50er- und Miss-Fenster) **und** richtig gezielt: frisst das
  Ziel als MISS, wie Mania.
- Bogen: Kopf wie ein Tap (`arc_started`). Danach Taste halten und der
  wandernden Spitze folgen (gleiche 22 Grad). Mehr als `ARC_OUT_MS` = 150 ms am
  Stueck ausserhalb oder Loslassen frueher als 1,5x 50er-Fenster vor dem Ende =
  MISS mit `miss_kind` "DROP" (`drop_reason` "OUT" bzw. "RELEASE"). Sonst zaehlt
  am Ende die Qualitaet des Kopfs. Ein Bogen ist ein Acc-Objekt.
- Die Austrittszeit wird exakt berechnet (Spitze laeuft linear, Cursor steht
  zwischen zwei Events still), also unabhaengig von der Framerate.
- `note_judged(index, result)`: `quality`, `dt`, `angle_err`, `ring`,
  `miss_kind`, `late`; Boegen zusaetzlich `hold_end`, `held`, `drop_reason`.

## Wertung

Sechs Stufen, benannt CORE / SHARP / GOOD / FAIR / EDGE / MISS (uebersetzt ueber
`translations/orbit.csv`). Der Index entspricht der Mania-Qualitaet
(MAX/PERFECT/GOOD/OK/MEH/MISS), die Zeitfenster sind also dieselben.

| Stufe | Zeitwert |
|---|---|
| CORE | 1,00 |
| SHARP | 0,94 |
| GOOD | 0,68 |
| FAIR | 0,40 |
| EDGE | 0,16 |
| MISS | 0 |

- **Zielfaktor**: bis `CENTER_DEG` = 9 Grad Zielfehler 1,0, danach linear bis
  `AIM_EDGE_FACTOR` = 0,88 am Rand der Toleranz (22 Grad). Wert eines Treffers
  = Zeitwert x Zielfaktor (`OrbitCore.hit_value`).
- **Acc** = Mittel der Trefferwerte aller bisher gewerteten Ziele (Miss = 0).
- **Score** (0 bis 1.000.000, x Mod-Faktor, z. B. NF):
  `1.000.000 x (0,9 x Summe(Wert)/N + 0,1 x Summe(Wert x min(Kombo/100, 1))/N)`
  mit N = Zahl aller Ziele. 90 % Praezision, 10 % Streak (`STREAK_SHARE`;
  volle Streak-Wertung ab Kombo `STREAK_FULL` = 100). Ein Bogen zaehlt als ein
  Ziel.
- **Grade**: SS ab Acc 98,5 % und ohne Miss, S ab 95 %, A ab 90 %, B ab 82 %,
  C ab 72 %, sonst D. Gescheitert = F (nur Endbild).
- Zielfehler (`aim_err`): mittlerer Winkelfehler aller Treffer in Grad.

## Orbit-Rating (Profil)

Eigene Kennzahl im Profil (Reiter "Orbit"), getrennt von den Mania-pp (die
bleiben unveraendert, nur Sektion `scores`). Code: `ScoreStore.orbit_points`,
`ScoreStore.orbit_rating_of`, `ScoreStore.orbit_rating`; Tests:
`tests/run_orbit_rating_tests.gd`.

- **Punkte eines Laufs** (Bestwert je Map+Diff, Sektion `orbit_scores`):
  `4 x Sterne^2 x Acc^4`. Sterne = Orbit-Sterne des Laufs (Feld `stars`,
  `OrbitConverter.stars`, gekappt auf 0..15), Acc = Genauigkeit 0..1.
  Beispiele: 5 Sterne / 100 % = 100; 3 Sterne / 100 % = 36;
  6 Sterne / 95 % = 117.
- Laeufe ohne `stars` (vor diesem Feld gespeichert) zaehlen wie 5 Sterne, also
  `100 x Acc^4` (die fruehere Orbit-Wertung) - alte Profile bleiben gleich.
- Gescheiterte (`failed`) und ungewertete (`unranked`) Laeufe: 0 Punkte.
- **Rating** = Punkte absteigend sortiert, Platz i (ab 0) zaehlt
  `Punkte_i x 0,95^i` (wie die pp-Gewichtung). Obergrenze: 20 x bester Lauf.
- `ScoreStore.submit` speichert `stars` nur, wenn das Ergebnis-Dictionary es
  traegt (`result["stars"]`, Modus Orbit).
- Profil zeigt dazu die besten Orbit-Laeufe (nach Punkten sortiert), die Zahl
  der Spiele (inkl. Fails), Ø Genauigkeit und den besten Score.
- Einstieg: Hauptmenue-Button "Orbit" (unter "Spielen") setzt
  `user://browser_state.cfg` `browser/play_mode = "orbit"` und oeffnet den
  Song-Browser, der diesen Wert beim Start liest.

## Lesbarkeit (OrbitView)

- Ein `_draw`-Durchgang, keine Nodes pro Ziel, keine Allokation pro Frame.
- Innen = volle Scheibe in kuehlem Blau, aussen = hohle Raute in warmem
  Bernstein: Ring ist an Form **und** Farbe erkennbar.
- Eigene Bahnen: Innen-Ziele fliegen vom Kern zum Innenring, Aussen-Ziele vom
  Innenring zum Aussenring. Konstante Geschwindigkeit, Ankunft genau zur
  Trefferzeit (Anflugzeit = Scroll Speed).
- Nur das naechste Ziel je Ring ist voll deckend, spaetere blasser
  (`FAR_ALPHA`). Winkel-Hilfslinien (Einstellung `orbit_guides`) und der Zeiger
  zeigen 650 ms vor der Ankunft, ob der Cursor auf dem Ziel steht.
- Kein Leuchten, kein Wackeln: Treffer geben kurze, ruhige Marken
  (Fehltreffer ein X), keine Partikel.
- Endbild: links die Orbit-Karte (jedes Ziel an seinem Winkel auf seinem Ring,
  radial um den Zeitfehler versetzt, Farbe = Stufe), rechts Score, Acc,
  Serie, Zielfehler, Stufentabelle und Timing-Histogramm nebeneinander.
  Die Knopfreihe (Nochmal R, Zurueck Esc) steht auch bei 1280x720 im Bild.

## Multiplayer

- Orbit laeuft in der Lobby wie Mania: Live-Stand (Score, Kombo, Acc) 4x pro
  Sekunde ueber `Lobby.send_score`, am Ende `Lobby.send_final` mit der
  Statistik-Karte. Gesendet wird der Orbit-Score.
- Im MP kein Neustart (R und "Nochmal" aus), Leertaste ist eine Skip-Abstimmung
  (springt erst, wenn alle druecken), Zurueck fuehrt in den Raum statt in den
  Song-Browser.
- Autoplay-Flag gilt in der Lobby nie; nur `--mp-bot` spielt dort selbst
  (nur Smoke-Test, siehe unten).

### MP-Smoke (zwei echte Prozesse)

`tools/mp_orbit_smoke.sh` startet Host und Client headless mit je `timeout`
(Standard 300 s) ueber `127.0.0.1:11110` (`--mp-port=<n>`, LAN-Ansage auf n+1;
headless ohne UPnP/Internet). Jeder Prozess bekommt ein eigenes `APPDATA`
(eigenes `user://`), die Maps sind die 4 kleinsten `.osz` aus `maps/` in einem
Testordner (`--maps-dir=`, `--mp-maps=`). Exit 0 = gruen, Logs bleiben bei
Fehler (oder mit `KEEP=1`) liegen.

Ablauf (`mp_lobby.gd _mp_orbit`, Zeilen `MPORBIT <Rolle> s<Stufe> ...`):

1. Raum, Krone stellt Modus Orbit, waehlt Map; beide bereit, beide Darstellung
   "Orbit"; Start.
2. Beide spielen Orbit (`--mp-bot`, Client mit `--auto-miss=6`),
   Intro-Skip per Abstimmung, Abbruch `--mp-cut=<s>` nach der ersten Note.
   `MPORBIT final ... live_seen={peer: score}` = hoechster Live-Score des
   anderen, der VOR dessen Finale ankam.
3. Zurueck im Raum (`in_game=false`, Modus bleibt Orbit), beide Endergebnisse
   in `Lobby.players[*].final`.
4. Orbit-Turnier: je Spieler 2 Maps (Pool 4, Host gibt Auto-Fuellung frei),
   je 1 Ban, 2 Runden mit Host-Autoablauf (Zwischenstand, dann Start), Endstand.

Flags in `orbit_game.gd`: `--mp-bot` (nur mit aktiver Lobby-Runde: Bot spielt,
headless kein Sofort-Ende, nach dem Endscreen nach `--mp-back=<s>` (1,5 s)
zurueck in den Raum), `--mp-cut=<s>`. Der Client bleibt 10 s im Endscreen,
laenger als der Turnier-Autoablauf bis zur naechsten Map.

Gefunden + behoben:

- Freie Runde vor dem Turnier liess `Lobby._tour_peers` stehen, der
  Turnier-Autostart wartete dann ewig (nur der Start-Knopf half).
- Wer beim Kartenwechsel noch im Endscreen war, kam unbereit in den Raum
  zurueck (Turnier hing bis zum Bereit-Klick); `mp_lobby` meldet jetzt bei der
  Rueckkehr bereit, wenn die Map lokal vorliegt.
- `--autoplay` armiert den 45-s-Test-Watchdog (game_session.gd); der Bot im
  Raum laeuft daher ueber `--mp-bot` allein.

## Screenshot-Harness

Szene `scenes/orbit.tscn` mit `--orbit-map=<Teil des osz-Namens>`
`--autoplay --shot --shot-out=<png>` plus eines von `--shot-at=<ms|arc|chord|dense>`,
`--shot-pause`, `--shot-results` (mit `--shot-fail --auto-miss=2` fuer das
Fail-Bild). `--shot-intro` (ohne `--shot`) fotografiert den Countdown.
`--auto-jitter=<ms>` / `--auto-aim=<Grad>` machen den Bot menschlich.

## Umwandlung (OrbitConverter)

Quelle: osu!mania-Maps (gedacht fuer 4K). Kein Zufall: gleiche Map = gleiches
Muster.

1. **Akkord** = Notes mit <= 2 ms Abstand. Ergibt hoechstens zwei Ziele: beide
   Ringe am selben Winkel (niedrigste Spalte innen, hoechste aussen). Die
   Variante "derselbe Ring nebeneinander" wird nicht erzeugt: ein Tastendruck
   trifft nur ein Ziel, zwei gleichzeitige Ziele auf einem Ring waeren
   unspielbar.
2. **Dichte-Reduktion**: ein Akkord weniger als `MIN_GAP_MS` = 75 ms nach dem
   letzten behaltenen wird verworfen. Alles schneller als 1/4 bei 200 BPM wird
   so zusammengefasst (1/6-Bursts, schnelle Jacks, Doppel-Streams).
3. **Winkel**: die Spalten liegen gedanklich auf einem Kreis. Der kreisfoermige
   Spaltenabstand d (4K: -1, 0, +1, +2; +2 folgt der Flussrichtung) mal
   Schrittweite ist der Sprung. Schrittweite = 24 Grad x clamp(Abstand / 150 ms,
   1, 2,5): kleine Abstaende = kleine Spruenge, grosse Abstaende duerfen bis
   120 Grad springen. Jeder Sprung ist gedeckelt auf `MAX_DEG_PER_MS` = 0,6
   Grad/ms x Abstand und `MAX_JUMP_DEG` = 150 Grad. Ergebnis: Rolls drehen im
   Kreis, Trills pendeln, Jacks bleiben stehen (ab 300 ms Abstand wandern sie
   einen Schritt weiter).
4. **Ring**: Einzelnoten im Stream (Abstand < 160 ms) wechseln den Ring, die
   Tasten werden also abgewechselt. In ruhigen Stellen entscheidet die
   Spaltenhaelfte (linke Haelfte innen, rechte aussen). Direkt nach einem
   Bogen-Ende (< 150 ms) kommt das naechste Ziel auf den anderen Ring.
5. **LN -> Bogen**: Winkellaenge = Dauer x 0,12 Grad/ms, gedeckelt auf 270
   Grad, Richtung = aktuelle Flussrichtung. LNs unter 100 ms werden Taps. Bei
   LN-Akkorden laufen beide Boegen gleich schnell (ein Cursor folgt beiden).
6. **Notes waehrend eines Bogens** werden Taps auf dem freien Ring genau an der
   Bogen-Spitze (dort ist der Cursor ohnehin). Laufen zwei Boegen, werden sie
   verworfen.

Damit bleibt die Winkelgeschwindigkeit zwischen allen Cursor-Punkten (Koepfe,
Bogen-Enden) unter 0,6 Grad/ms (bei Ringradius 300 px etwa 3100 px/s).

## Spielbarkeit (2 Tasten + Zeiger)

Grenzen, die der Converter erzwingt (`OrbitConverter.violations` prueft sie):

1. **Zeit exakt**: jedes Ziel liegt auf der Zeit seiner Quell-Note, nichts wird
   verschoben. Nur Akkorde teilen sich die Zeit des ersten Notes (max 2 ms).
2. **Zeigertempo**: zwischen zwei Cursor-Punkten (Koepfe, Bogen-Enden) hoechstens
   `MAX_DEG_PER_MS` = 0,6 Grad/ms; damit hoechstens 150 Grad in 250 ms
   (`MAX_JUMP_DEG`) und hoechstens 90 Grad unter 150 ms Abstand
   (`SHORT_JUMP_DEG`). Zu grosse Spruenge werden verkleinert, nie verzoegert.
3. **Ein Finger pro Ring**: zwei Ziele auf demselben Ring brauchen
   `SAME_RING_MIN_MS` = 90 ms (Tap zu Tap), nach einem Bogen-Ende
   `RELEASE_GAP_MS` = 150 ms; waehrend ein Bogen den Ring haelt, kommt dort
   kein Ziel. Schnellere Folgen wechseln auf den anderen Ring (wenn der frei
   ist), sonst entfaellt das Ziel; ein Akkord schrumpft auf das freie Ziel.
4. **Akkorde** (beide Ringe) liegen immer am selben Winkel.

Pruefung: `tests/run_orbit_tests.gd` wandelt alle 4K-Diffs der Bibliothek
um und zaehlt Verstoesse. Stand: 216 Sets, 899 Diffs, 878.349 Ziele,
Verstoesse Zeit 0, Tempo 0, Flick 0, Ring 0, Akkord 0; hoechstes Tempo
0,600 Grad/ms. Der perfekte Bot spielt die Test-Maps ohne Miss.

## Konstanten

| Konstante | Wert | Ort |
|---|---|---|
| `ANGLE_TOL_DEG` | 22 Grad | OrbitCore |
| `ARC_OUT_MS` | 150 ms | OrbitCore |
| `CHORD_EPS_MS` | 2 ms | OrbitConverter |
| `MIN_GAP_MS` | 75 ms | OrbitConverter |
| `MAX_DEG_PER_MS` | 0,6 Grad/ms | OrbitConverter |
| `MAX_JUMP_DEG` | 150 Grad | OrbitConverter |
| `COL_STEP_DEG` | 24 Grad | OrbitConverter |
| `REF_GAP_MS` / `MAX_STEP_SCALE` | 150 ms / 2,5 | OrbitConverter |
| `DRIFT_GAP_MS` | 300 ms | OrbitConverter |
| `STREAM_GAP_MS` | 160 ms | OrbitConverter |
| `MIN_ARC_MS` | 100 ms | OrbitConverter |
| `ARC_DEG_PER_MS` / `ARC_MAX_DEG` | 0,12 Grad/ms / 270 Grad | OrbitConverter |
| `RELEASE_GAP_MS` | 150 ms | OrbitConverter |
| `SAME_RING_MIN_MS` | 90 ms | OrbitConverter |
| `FLICK_WINDOW_MS` / `SHORT_GAP_MS` / `SHORT_JUMP_DEG` | 250 ms / 150 ms / 90 Grad | OrbitConverter |

## Messwerte (echte Map, Testlauf)

- Billain - Specialist [Advanced]: 1102 Notes (55 LN) -> 1097 Ziele (54 Boegen),
  max 0,558 Grad/ms, Umwandlung 9 ms.
- Billain - Specialist [GoldenJumper's Insane]: 2213 Notes (46 LN) -> 1970 Ziele
  (5 Boegen), max 0,600 Grad/ms, 17 ms.
- Autoplay (perfekter Spieler) erreicht auf beiden SS, also ist jedes Ziel
  erreichbar.
