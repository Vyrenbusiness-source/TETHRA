# Orbit-Modus ("Taktkreis")

Eigener Modus: zielen mit Maus/Tablet, tippen mit zwei Tasten. Der Kreis ist
ein Takt: eine Hand dreht im Songtempo (eine Umdrehung pro Takt, 12 Uhr =
Takt-Eins), die Noten sitzen fest an ihrer Taktposition auf zwei Ringen. Taste A
(Maus links / Z) = innerer Ring, Taste B (Maus rechts / X) = aeusserer Ring,
umbelegbar. Beide Tasten zugleich = Akzent. Der Cursor muss beim Druck auf der
Hand liegen. Entwurf, Abgrenzung und Spass-Begruendung: `orbit_taktkreis.md`.

Code: `scripts/orbit/orbit_clock.gd` (Takt-Uhr: Hand-Winkel zu jeder Zeit),
`orbit_note.gd` (Ziel), `orbit_converter.gd` (Map -> Ziele, Sterne),
`orbit_core.gd` (Wertung), `orbit_view.gd` (Spielfeld), `orbit_game.gd`
(Szene: Eingabe, HUD, Pause, Bot, Multiplayer), `orbit_results.gd` (Endbild).
Tests: `tests/run_orbit_tests.gd` (Unit + Bibliothek), `run_orbit_play_tests.gd`,
`run_orbit_replay_tests.gd`, `run_orbit_qa_tests.gd` (Bots, Messwerte).

## Winkel und Uhr

0 Grad = oben, im Uhrzeigersinn. Die Hand steht zur Zeit t bei
`OrbitClock.angle_at(t)`: eine Umdrehung pro Takt (Beats pro Takt x Beat-Laenge
des roten Timing-Points; ein neuer roter Punkt beginnt einen neuen Takt).
Takte unter `MIN_BAR_MS` = 1200 ms drehen mit zwei Takten pro Umdrehung, die
Hand ist also nie schneller als 0,3 Grad/ms (300 Grad/s). Ohne Timing-Point:
120 BPM, 4/4. Ein Ziel liegt am Winkel seiner Taktposition; der Bogen eines
Halte-Ziels ist der Weg der Hand (`OrbitNote.pointer_at(t)`).

## Regeln (OrbitCore)

- Zeitfenster aus OD (ManiaCore), HP und Zaehler aus einem ManiaCore-Objekt.
  Score, Acc und Grade sind Orbit-Regeln, siehe Wertung. `stats()` wie Mania
  plus `aim_err` und `mode` = "orbit".
- **Die Taste waehlt den Ring** (Taste A innen, B aussen). Der Cursor-Abstand
  zaehlt nicht; nur in der Totzone (`DEAD_K`) in der Mitte gilt der Cursor nie
  als gezielt.
- **Zielen ist Pflicht**: beim Druck muss der Cursor-Winkel hoechstens
  `ANGLE_TOL_DEG` = 30 Grad neben der Hand liegen, Radius egal. Daneben =
  kein Treffer, Grund `ANGLE` ("neben dem Zeiger"), das Ziel bleibt offen bis
  sein Fenster ablaeuft (MISS).
- Zu frueh (zwischen 50er- und Miss-Fenster) und gezielt: frisst das Ziel als
  MISS, wie Mania.
- **Halte** (Bogen): Kopf wie ein Tap. Danach Taste halten und der Hand folgen
  (gleiche Toleranz). Mehr als `ARC_OUT_MS` = 150 ms am Stueck neben der Hand
  oder zu frueh loslassen (1,5x 50er-Fenster vor dem Ende) = MISS,
  `miss_kind` "DROP", `drop_reason` "OUT" bzw. "RELEASE". Sonst zaehlt die
  Qualitaet des Kopfs. Die Austrittszeit wird exakt berechnet (Framerate egal).
- `note_judged(index, result)`: `quality`, `dt`, `angle_err`, `ring`,
  `miss_kind`, `late`; Halte zusaetzlich `hold_end`, `held`, `drop_reason`.
- Replays tragen die Marke `REPLAY_RULES` = 3 (`EV_RULES`). Aeltere Orbit-
  Replays (ohne Marke) werden als "aeltere Version" gemeldet und nicht
  abgespielt.

## Wertung (unveraendert gegenueber dem alten Orbit)

Sechs Stufen CORE / SHARP / GOOD / FAIR / EDGE / MISS (`translations/orbit.csv`),
Zeitfenster wie Mania.

| Stufe | Zeitwert |
|---|---|
| CORE | 1,00 |
| SHARP | 0,94 |
| GOOD | 0,68 |
| FAIR | 0,40 |
| EDGE | 0,16 |
| MISS | 0 |

- **Zielfaktor**: bis `CENTER_DEG` = 9 Grad Winkelfehler 1,0, danach linear bis
  `AIM_EDGE_FACTOR` = 0,88 am Rand der Toleranz (30 Grad). Wert = Zeitwert x
  Zielfaktor (`OrbitCore.hit_value`).
- **Acc** = Mittel der Trefferwerte aller bisher gewerteten Ziele (Miss = 0).
- **Score** (0..1.000.000, x Mod-Faktor): `1.000.000 x (0,9 x Summe(Wert)/N +
  0,1 x Summe(Wert x min(Kombo/100, 1))/N)`. 90 % Praezision, 10 % Streak
  (`STREAK_SHARE`, voll ab Kombo `STREAK_FULL` = 100). Ein Halte = ein Ziel.
- **Grade**: SS ab Acc 98,5 % ohne Miss, S ab 95 %, A ab 90 %, B ab 82 %,
  C ab 72 %, sonst D. Gescheitert = F.
- `aim_err` = mittlerer Winkelfehler (Cursor zur Hand) aller Treffer in Grad.

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

- Ein `_draw`-Durchgang, keine Nodes pro Ziel. Dunkle Platte, zwei duenne Ringe,
  Raster nur als feine Striche (Viertel, Achtel feiner).
- Innen = volle kuehle Scheibe, aussen = warmes Quadrat: Ring an Form **und**
  Farbe lesbar. Die Hand ist die einzige helle Linie, dahinter eine schwache
  Zielzone (+-30 Grad).
- Die naechste Note je Ring ist am groessten, mit hellem Rand; spaetere Noten
  des Takts kleiner; die Noten des naechsten Takts (Vorschau) gedimmt und
  heller, je naeher die Hand kommt.
- Kein Leuchten, keine Partikel. Treffer = kurze Marke an der Note (Stufe in
  der Mitte), Fehltreffer ein X, Hinweis "neben dem Zeiger" bei Zielfehlern.
- Sound: je Ring ein eigener Treffer-Klang (Tonhoehe nach Stufe), Halte-Loop,
  Miss-Klang (`OrbitSound` in `orbit_game.gd`).
- Endbild: links die Orbit-Karte (Ziel an Winkel und Ring, radial um den
  Zeitfehler versetzt, Farbe = Stufe), rechts Score, Acc, Serie, Zielfehler,
  Stufentabelle, Timing-Histogramm. Knopfreihe auch bei 1280x720 im Bild.

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

Quellen: osu!standard und osu!mania. Kein Zufall: gleiche Map = gleiches Muster.
Jedes Ziel liegt exakt auf der Zeit seiner Quell-Note.

- **std**: Ring nach osu!taiko-Regel: Whistle/Clap = aussen, sonst innen;
  Finish = Akzent (beide Ringe). Slider und Spinner (>= `MIN_ARC_MS` = 100 ms)
  werden Halte, gekappt auf `MAX_HOLD_MS` = 6 s. Positionen zaehlen nicht.
  (`HitObject.hit_sound` kommt aus `osu_parser.gd`.)
- **mania 4K**: Spalten 1-2 innen, 3-4 aussen; Akkord ueber beide Seiten =
  Akzent; LN = Halte. Andere Spaltenzahlen: linke Haelfte innen, rechte aussen.
- **Dichte**: je Ring `SAME_RING_MIN_MS` = 90 ms, nach einem Halte
  `RELEASE_GAP_MS` = 150 ms; waehrend ein Halte den Ring haelt, kommt dort
  nichts. Unter `EASY_STARS` = 2,5 gelten `EASY_RING_GAP_MS` = 220 ms (Ring) und
  `EASY_GAP_MS` = 150 ms (gesamt).
- `OrbitConverter.violations` prueft Zeit, Ring, Winkel, Akkord; die Bibliothek
  hat 0 Verstoesse.

## Orbit-Sterne

Skala 0..15. Je Sekunden-Fenster (Paare, `STAR_HOP_MS`): Last = Ziele/s (Akzent
zaehlt `STAR_ACCENT_W`, Halte `STAR_HOLD_W`, Ringwechsel unter 400 ms
`STAR_SWITCH_W`) plus Folge-Anspruch = (Handtempo / `HAND_REF_DEG_PER_MS`)^2
(gekappt `STAR_FOLLOW_CAP`) x min(nps/3, 1). Die haertesten Fenster zaehlen am
meisten (`STAR_DECAY`). Ab `STAR_KNEE` = 3,5 wird mit `STAR_STRETCH` = 3,5
gedehnt, damit die Skala genutzt wird. Bibliothek (964 Diffs): p10 2,15, p25
2,99, Median 4,35, p75 6,37, p90 7,86, p99 10,24, Max 13,76. Rating-Formel
(Profil) siehe oben, unveraendert.

## Konstanten

| Konstante | Wert | Ort |
|---|---|---|
| `ANGLE_TOL_DEG` | 30 Grad | OrbitCore |
| `CENTER_DEG` / `AIM_EDGE_FACTOR` | 9 Grad / 0,88 | OrbitCore |
| `ARC_OUT_MS` | 150 ms | OrbitCore |
| `DEAD_K` | 0,045 | OrbitCore |
| `REPLAY_RULES` | 3 | OrbitCore |
| `MIN_BAR_MS` | 1200 ms | OrbitClock |
| `CHORD_EPS_MS` | 2 ms | OrbitConverter |
| `SAME_RING_MIN_MS` / `RELEASE_GAP_MS` | 90 / 150 ms | OrbitConverter |
| `MIN_ARC_MS` / `MAX_HOLD_MS` | 100 ms / 6 s | OrbitConverter |
| `EASY_STARS` / `EASY_RING_GAP_MS` / `EASY_GAP_MS` | 2,5 / 220 / 150 ms | OrbitConverter |
| `STAR_KNEE` / `STAR_STRETCH` | 3,5 / 3,5 | OrbitConverter |

## Messwerte

Siehe `orbit_taktkreis.md` (Handtempo, Bots, Regelmaessigkeit, Sterne).
