# Mania 2D/3D: Anflug-Audit ("Noten kommen direkt")

Stand: Branch `warmd/qa-mania`, Basis v1.29.0.

## Messung

Fuer jede Note: zusammenhaengende Zeit direkt vor dem Treffer, in der sie im
Sichtfenster liegt (`0 <= position(hit) - position(t) <= Anflugzeit`), exakt
aus der Scroll-Tabelle (`ScrollMap.visible_lead`, gleiche Rechnung wie
`mania_3d._note_z`, 2D und 3D teilen sie). Eine Note, die ein Ruecklauf kurz
vor dem Treffer hinter die Linie oder ueber die Oberkante schiebt, zaehlt erst
ab dem Wiedereintritt.

Stichprobe: jede 6. Datei aus `maps/` (241 Sets), je Set die leichteste und die
dichteste Mania-Diff: 75 Diffs, 86 266 Noten (SV-Mod auf 73 Diffs, 2 haben
starkes eigenes SV). Scroll Speed 5, 10, 15, 25, 40 (Anflug 2297 bis 287 ms).

Schwelle "Fund": weniger als 450 ms, bei kuerzerem Anflug weniger als 50 % des
Anflugs.

### Kuerzeste Sichtzeit (ms) und Noten unter 50 % / 450 ms

| Lauf | Speed | vorher min | vorher Funde | nachher min | nachher Funde |
|---|---|---|---|---|---|
| ohne Mod, Map ohne SV | alle | = Anflug | 0 | = Anflug | 0 |
| ohne Mod, Map mit eigenem SV (16 Diffs) | 25 | 360 | 0 | 360 | 0 |
| ohne Mod, Map mit eigenem SV | 40 | 194 | 0 | 194 | 0 |
| SV Normal | 15 | 253 | 6 | 352 | 3 |
| SV Normal | 25 | 124 | 47 | 184 | 27 |
| SV Normal | 40 | 78 | 290 | 150 | 0 |
| SV Stark | 5 | 71 | 592 | >= 600 | 0 |
| SV Stark | 10 | 71 | 595 | 390 | 1 |
| SV Stark | 15 | 71 | 899 | 253 | 168 |
| SV Stark | 25 | 48 | 2522 | 152 | 590 |
| SV Stark | 40 | 30 | 7174 | 150 | 0 |

"nachher Funde" sind Noten zwischen der neuen Untergrenze und 50 %: SV kuerzt
die Sichtzeit absichtlich, die Untergrenze steht unten. SV-Anteil der Songzeit
(Speed 25): Normal 61,1 % -> 60,9 %, Stark 72,9 % -> 67,7 %, Rueckwaerts-Phasen
Stark 2645 -> 1326.

## Gefundene Bugs

### 1. SV-Mod: Noten erst 30-124 ms vor dem Treffer im Bild

Ursache: `SvMod.generate` erzeugte ein SV fuer alle Scroll Speeds. Die
Fairness-Pruefung (Test `_test_fair`) lief nur mit 600/1200/2400 ms Anflug; der
Standard (Speed 25) hat 459 ms, Speed 40 hat 287 ms. Ein Burst, der bei 600 ms
harmlos ist, holt bei 459 ms eine Note erst im Burst ins Bild. SV Stark: der
Ruecklauf schob Noten bis 71 ms vor dem Treffer hinter die Linie (bei jedem
Scroll Speed, auch 5).

Fix (`scripts/gameplay/sv_mod.gd`, `scroll_map.gd`, `mania_core.gd`): das SV
wird fuer die Anflugzeit des Spielers erzeugt (`timing_points_for(bm, view)`,
`ManiaCore.build_scroll_map(bm, mods, preempt)`). Jede Note liegt vor dem
Treffer ununterbrochen `SvMod.fair_need(view)` ms im Bild:
`min(450, max(Anteil * view, min(150, 0.8 * view)))`, Anteil 0,40 Normal und
0,33 Stark. Verletzt eine Note das, wird erst der Block direkt vor ihr ruhiger,
dann das Fenster, zuletzt m = 1. Scroll Speed live (F3/F4, Pausenmenue):
`ManiaCore.set_scroll_scale` erzeugt das SV neu.

Folge: bei Speed 40 ist SV Stark deutlich ruhiger, bei Speed 25 fallen Bursts
weg, nach denen eine Note in weniger als 152 ms faellig waere (synthetische
Kiai-Map: 15 statt 44 von 64 Beats mit Burst in den Beat), ab Speed 15 bleibt
der Beat-Tanz unveraendert (43 von 64).

Test: `tests/run_sv_mod_tests.gd` `_test_lead` (rot vor dem Fix: 9 Faelle,
schlechteste 16 %), `_test_live_speed`.

Keine Regelaenderung: Wertung, Zeitfenster, Score-Faktor (SV x1,1) unveraendert,
das SV ist nur Anzeige. Replay-rules bleibt, kein Server-min_version.
`docs/qa/sv_mod.md` (nicht in diesem Task) nennt noch die alte Regel.

### 2. Songstart mit Konstant-Mod: erste Note ohne volle Anflugzeit

Ursache: `mania_3d._load_beatmap` rechnete den Vorlauf mit dem SV der Map und
vor dem Einmischen der Lauf-Mods. Mit Konstant (CS) fliegt die Note aber mit
voller Anflugzeit an: beginnt die Map mit schnellem SV (x2), fehlte die halbe
Anflugzeit (bei Speed 1-5 mehr als der 600-ms-Puffer). Bei SV-Ruecklauf zaehlte
ausserdem nur die erste Note, obwohl eine spaetere zuerst erscheinen kann.

Fix: `ManiaCore.start_lead_ms(bm, scroll, mods)`: fruehestes Erscheinen aller
Noten mit den Mods des Laufs, plus 600 ms. Test `_test_start_lead`.

### 3. Intro-Skip bei Scroll Speed 1-5: erste Note steht schon im Feld

Ursache: `_do_skip` sprang fest auf 2200 ms vor die erste Note; Speed 5 hat
2297 ms Anflug, Speed 1 hat 11 485 ms.

Fix: `ManiaCore.skip_target_ms`: Ziel ist das Erscheinen der ersten Note minus
600 ms, hoechstens 2200 ms vor der Note. `_can_skip_intro` rechnet mit demselben
Ziel. Test `_test_start_lead`.

### 4. Replay in 2D: Hidden/FadeIn/Cover aus der Einstellung statt aus dem Lauf

Ursache: `Playfield2D.cover_fraction` las `Settings.mod_vis_2d`. Ein
Hidden-Replay lief ohne Abdeckung, wenn die Einstellung inzwischen anders stand
(HUD zeigte trotzdem "Hidden"), und umgekehrt.

Fix: `Playfield2D.set_run_mods(GameSession.mods)` im Replay,
`ManiaCore.vis_mods`. Test `_test_replay_vis`.

## Geprueft, kein Fund

- Ohne Mod, Map ohne SV: Sichtzeit = Anflugzeit, bei jedem Scroll Speed.
- Map mit eigenem SV: kuerzeste Sichtzeit 78 % (Speed 25) bzw. 68 % (Speed 40)
  des Anflugs, das ist das SV des Mappers (wie lazer), nicht veraendert.
- 3D: `note_disc.gdshader` blendet ferne Noten nicht aus (`approach` ohne
  Wirkung), sichtbar ab `Z_FAR - 0.5`. 2D: `z_to_y` legt `Z_FAR` an die
  Oberkante, auch mit eigener HitPosition, Skin, Scroll nach oben.
- Hidden/FadeIn/Cover (nur 2D): Abdeckung 16-40 % bzw. der gewaehlte
  Cover-Anteil, das ist die Wirkung des Mods.
- Pause/Resume: Uhr haelt, 3-2-1 vor dem Weiterspielen. Retry laedt die Szene
  neu (Vorlauf neu gerechnet, Mods bleiben in `GameSession.mods`).
- Score-Faktor: NF x0,5, SV x1,1, Produkt (`_test_score` gruen). FI/HD/CO/CS
  ohne Faktor.
- Replay speichert `GameSession.mods` vollstaendig, Wiedergabe mischt keine
  Einstellungen ein.

## Offen / nicht geprueft

- Multiplayer-Start, Online-Submit und Profil-Anzeige der Mods: nur im Code
  gelesen (Lobby setzt `GameSession.mods`), kein Lauf gegen einen Server.
- Replay mit SV: die Stufe (Normal/Stark) kommt aus `SvMod.strength` der
  aktuellen Einstellung, nicht aus dem Replay. Wertung gleich, Bild anders.
- Sichtzeit-Untergrenze 152 ms bei Speed 25 mit SV Stark liegt unter den
  450 ms der Aufgabe: mehr geht nur mit ruhigerem SV (Entscheidung offen).

## Laeufe

- Autoplay im Fenster (Monitor 2, Dummy-Audio), je 45 s bis zum Test-Watchdog:
  3D `--sv --scroll=40` und 2D `--sv --scroll=5`. Kein SCRIPT ERROR, kein
  ERROR im Log. Nicht bis zum Songende gespielt (Watchdog), Fail, Pause und
  Replay-Wiedergabe nicht im Lauf geprueft.
- Headless: `run_sv_mod_tests.gd` 157 bestanden, `run_sv_tests.gd` 20 bestanden.
