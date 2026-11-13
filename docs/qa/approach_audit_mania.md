# Mania 2D/3D: Anflug-Audit ("Noten kommen direkt")

Stand: Branch `warmd/qa-mania`, Basis v1.29.0.

## Messung

Fuer jede Note: zusammenhaengende Zeit direkt vor dem Treffer, in der sie im
Sichtfenster liegt (`0 <= position(hit) - position(t) <= Anflugzeit`), exakt
aus der Scroll-Tabelle (`ScrollMap.visible_lead`, gleiche Rechnung wie
`mania_3d._note_z`, 2D und 3D teilen sie).

Stichprobe: jede 6. Datei aus `maps/` (241 Sets), je Set die leichteste und die
dichteste Mania-Diff: 75 Diffs, 86 266 Noten (SV-Mod auf 73 Diffs, 2 haben
starkes eigenes SV). Scroll Speed 5, 10, 15, 25, 40 (Anflug 2297 bis 287 ms).

### Kuerzeste Sichtzeit (ms)

| Lauf | Speed | Anflug | kuerzeste Sichtzeit | Stand |
|---|---|---|---|---|
| ohne Mod, Map ohne SV | alle | 287-2297 | = Anflug | unveraendert |
| ohne Mod, Map mit eigenem SV (16 Diffs) | 25 | 459 | 360 | unveraendert, gewollt |
| ohne Mod, Map mit eigenem SV | 40 | 287 | 194 | unveraendert, gewollt |
| SV Normal | 15 / 25 / 40 | 766 / 459 / 287 | 253 / 124 / 78 | unveraendert, gewollt |
| SV Stark | 5-15 / 25 / 40 | 2297-766 / 459 / 287 | 71 / 48 / 30 | unveraendert, gewollt |

Ergebnis: ohne SV-Effekt hat jede Note bei jedem Scroll Speed ihre volle
Anflugzeit. Kuerzer wird sie nur durch SV (Mod oder Map).

### SV bleibt, wie es war (Nutzer-Vorgabe)

Nutzer: "SV-Mod passt, der muss ja so sein." Kurze Sichtzeiten durch SV sind
die Wirkung des Mods bzw. des Mappers. Ein Zwischenstand dieses Tasks
(Commit `bb05c3e`) hatte das SV des Mods je Scroll Speed beruhigt (Bursts bei
Speed 25/40 entfernt, Ruecklauf seltener). Das war kein Rechenfehler, es hat
nur die Staerke geaendert: zurueckgenommen. `scripts/gameplay/sv_mod.gd` ist
wieder identisch mit v1.29.0, `ManiaCore.build_scroll_map` und
`set_scroll_scale` ebenso. Map-eigenes SV wurde nie angefasst.

## Gefundene Bugs (behoben, ohne SV-Staerke zu aendern)

### 1. Songstart mit Konstant-Mod: erste Note ohne volle Anflugzeit

Ursache: `mania_3d._load_beatmap` rechnete den Vorlauf mit dem SV der Map und
vor dem Einmischen der Lauf-Mods. Mit Konstant (CS) fliegt die Note aber mit
voller Anflugzeit an: beginnt die Map mit schnellem SV (x2), fehlte die halbe
Anflugzeit (bei Speed 1-5 mehr als der 600-ms-Puffer). Bei SV-Ruecklauf zaehlte
ausserdem nur die erste Note, obwohl eine spaetere zuerst erscheinen kann.

Fix: `ManiaCore.start_lead_ms(bm, scroll, mods)`: fruehestes Erscheinen aller
Noten mit den Mods des Laufs, plus 600 ms. Test `_test_start_lead`.

### 2. Intro-Skip bei Scroll Speed 1-5: erste Note steht schon im Feld

Ursache: `_do_skip` sprang fest auf 2200 ms vor die erste Note; Speed 5 hat
2297 ms Anflug, Speed 1 hat 11 485 ms.

Fix: `ManiaCore.skip_target_ms`: Ziel ist das Erscheinen der ersten Note minus
600 ms, hoechstens 2200 ms vor der Note. `_can_skip_intro` rechnet mit demselben
Ziel. Test `_test_start_lead`.

### 3. Replay in 2D: Hidden/FadeIn/Cover aus der Einstellung statt aus dem Lauf

Ursache: `Playfield2D.cover_fraction` las `Settings.mod_vis_2d`. Ein
Hidden-Replay lief ohne Abdeckung, wenn die Einstellung inzwischen anders stand
(HUD zeigte trotzdem "Hidden"), und umgekehrt.

Fix: `Playfield2D.set_run_mods(GameSession.mods)` im Replay,
`ManiaCore.vis_mods`. Test `_test_replay_vis`.

Keine Regelaenderung: Wertung, Zeitfenster, Score-Faktoren unveraendert.
Replay-rules bleibt, kein Server-min_version.

## Noten ohne SV-Effekt: geprueft

### 3D: fernes Ende (Shot)

Shot 3D, Welt Frost, Scroll Speed Standard, Songzeit 30 s
(`--mania --3d --autoplay --shot --shot-at=30000`): Noten und Hold-Strahlen
sind bis zum Horizont zu sehen, nichts wird abgeschnitten.

- Kamera-Far-Clip: Godot-Standard (4000), Spawn-Horizont `Z_FAR = -46`.
- Kein Nebel: kein `fog_*`/`volumetric_fog` im Projekt.
- `note_disc.gdshader` blendet ferne Noten nicht aus (`approach` ohne Wirkung).
- Cull-Grenze: `in_view = z >= Z_FAR - 0.5`, Spawn bei Abstand = Anflugzeit,
  also genau bei `Z_FAR`. Keine Note erscheint mitten auf der Strecke.

Beobachtung (kein Fehler in der Rechnung, Optik nicht umgebaut): die
Perspektive staucht das ferne Ende. Gerechnet mit der Standard-Kamera
(y 1,78, z 6,8, Neigung -15,2 Grad, FOV 72, 720p): Horizont bei Bildzeile 256,
Trefferlinie bei 577. Die erste Haelfte der Anflugzeit legt die Note 25 von
321 Zeilen zurueck (11 bis 20 px breit), das letzte Viertel der Zeit 255
Zeilen. Bei Scroll Speed 25 (459 ms) ist eine Note in 3D erst in den letzten
rund 115 bis 230 ms gross im Bild. Das wirkt wie "kommt direkt", obwohl sie
459 ms sichtbar ist. In 2D ist die Bewegung gleichmaessig. Abhilfe waere eine
Design-Entscheidung (laengerer Anflug in 3D bei gleichem Scroll Speed oder
flachere Kamera), hier nicht geaendert.

Nicht per Shot geprueft: die anderen 12 Welten (im Code gibt es keine
weltabhaengige Sichtgrenze, die Horizont-Glut liegt hinter `Z_FAR`).

### Spawn, Zeitbasis, Pause

- Spawn: `ManiaCore.update` spawnt jede Note, sobald ihr Abstand die
  Anflugzeit erreicht; kein Limit je Frame, kein Pool.
- Songstart: Vorlauf = Anflugzeit + 600 ms (`start_lead_ms`), dazu 3-2-1.
- Nach Breaks: kein eigener Pfad, Noten spawnen nach Zeit wie ueberall.
- Pause/Resume: Uhr haelt (`Smoother.hold`), 3-2-1 vor dem Weiterspielen,
  Audio wird auf die gehaltene Zeit gespult, kein Sprung.
- Zeitbasis: `SyncClock` ist monoton und geglaettet. Ein harter Sprung nach
  vorn passiert nur, wenn die Audio-Uhr 40 ms lang mehr als 50 ms voraus ist
  (Seek, Audio-Aussetzer). Nach so einem Aussetzer stehen Noten naeher an der
  Linie, das ist die echte Songzeit. Im Lauf nicht aufgetreten.
- Retry laedt die Szene neu (Vorlauf neu gerechnet, Mods bleiben in
  `GameSession.mods`).
- Scroll Speed live langsamer gestellt (F3/F4): Noten zwischen altem und
  neuem Horizont erscheinen sofort, das ist die Folge der Aenderung.

### 2D

- `z_to_y` legt `Z_FAR` an die Oberkante, auch mit eigener HitPosition, Skin,
  Scroll nach oben: Anflug = Oberkante bis Linie.
- Hidden/FadeIn/Cover: Abdeckung 16-40 % bzw. der gewaehlte Cover-Anteil, das
  ist die Wirkung des Mods.

### Mods

- Score-Faktor: NF x0,5, SV x1,1, Produkt (`_test_score` gruen). FI/HD/CO/CS
  ohne Faktor.
- Replay speichert `GameSession.mods` vollstaendig, Wiedergabe mischt keine
  Einstellungen ein.

## Offen / nicht geprueft

- Multiplayer-Start, Online-Submit und Profil-Anzeige der Mods: nur im Code
  gelesen (Lobby setzt `GameSession.mods`), kein Lauf gegen einen Server.
- Replay mit SV: die Stufe (Normal/Stark) kommt aus `SvMod.strength` der
  aktuellen Einstellung, nicht aus dem Replay. Wertung gleich, Bild anders.
- 3D-Perspektive (oben): Entscheidung des Nutzers, ob 3D mehr Anflug bekommt.
- Fail, Songende und Replay-Wiedergabe nicht in einem Lauf geprueft.

## Laeufe

- Autoplay im Fenster (Monitor 2, Dummy-Audio), je 45 s: 3D `--sv --scroll=40`
  und 2D `--sv --scroll=5`; 3D-Shot bei 30 s. Kein SCRIPT ERROR, kein ERROR.
- Headless: `run_sv_mod_tests.gd` 143 bestanden, `run_sv_tests.gd` 20 bestanden.
