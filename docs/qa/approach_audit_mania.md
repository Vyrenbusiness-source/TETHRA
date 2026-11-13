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

## 2D Pop-in

Stand: Branch `warmd/mania-2d-popin`, Basis v1.30.0. Nutzer: "manche Noten
kommen direkt, man hat keine Chance, sie zu treffen", nur im 2D-Feld.

### Messung

`--debug-popin` (Playfield2D, ohne Flag ein bool-Test je Note): je Note der erste
Frame, in dem der Kopf wirklich im Bild liegt (nach `stage_xf`, im Viewport und
im Clip, Maske > 0, kein deckendes Control darueber), und die sichtbare Zeit bis
zur Trefferzeit. Fund = erst nach 15 % der Strecke sichtbar oder weniger als
70 % der Anflugzeit sichtbar. Ausgabe `POPIN ...` je Fund, `POPIN-SUM ...` am
Ende. Laeufe: Autoplay im Fenster, je 45 s, Maps ohne SV, Nutzer-Einstellungen
(Skin `builtin:Kreise`, Spurbreite 135 %, Scroll Speed 8 = 1436 ms Anflug).

Maps: Uncharted Sky (dichte Streams, 90 Noten im Lauf), Strobe Light
(66 % Holds, 164 Noten), ETERNAL DRAIN [Eternal] (Intro 4,8 s, 658 Noten).

### Ursachen

1. **Intro-/Break-Ring ueber dem Feld.** `BreakOverlay` (240 px, 72 % deckend)
   lag in der Bildmitte und blieb bis zur Trefferzeit der ersten Note plus
   380 ms. Mit mittigem Feld deckte er die mittleren Spalten von 33 % bis 67 %
   der Bildhoehe: die ersten Noten nach Intro und nach jedem Break liefen dort
   40 % ihrer Anflugzeit hinter dem Ring und kamen kurz vor der Linie wieder
   heraus. In 3D liegt an der Stelle der Horizont, darum nur 2D. Passt zu
   "manche Noten" (nur die ersten nach Intro/Break, nur mittlere Spalten).
   Fix: `Playfield2D.overlay_center_x`, der Ring steht in 2D neben dem Feld
   (Bildmitte, wenn das Feld links/rechts steht). Passt er nirgends daneben
   (schmales Fenster), ist er weg, bevor die erste Note ins Feld kommt.
2. **Skalierung > 100 %.** Das Feld wird um die Kante bei der Linie skaliert,
   Feld-Y 0 (Spawn) lag dann ausserhalb des Bildes: bei 150 % erschien JEDE
   Note erst nach 40 % der Strecke. Fix: `Playfield2D.track_top`, `z_to_y` legt
   den Spawn an die sichtbare Bildkante (FadeIn/Cover rechnen ab dort). Volle
   Anflugzeit, Linie unveraendert, bei 100 % und darunter keine Aenderung.

Keine Regelaenderung, SV unveraendert. Test `tests/run_popin_2d_tests.gd`
(vorher 6 FAIL + 2 Skriptfehler, danach 17 bestanden).

### Vorher / nachher

| Lauf | vorher: Funde, kleinste Sichtzeit | nachher |
|---|---|---|
| Intro, 1280x720, Nutzer-Einstellungen | 6 Noten, 59 % (erst-sichtbar 0 %, dann verdeckt) | 0, 99 % |
| Intro, Scroll Speed 30 (383 ms) | 3 Noten, 59 % | 0, 91 % |
| Intro, osu!-Skin BubbleSkinHappyEdit, eigene HitPosition 420 | 7 Noten, 61 % | 0, 98 % |
| Intro, 1920x1061 | 0, 72 % (Ring kleiner im Verhaeltnis) | nicht neu gemessen |
| Skalierung 150 % | 90 von 90, erst bei 40 % der Strecke, 60 % | 0, 100 % |
| Skalierung 150 %, Scroll nach oben, osu!-Skin | 90 von 90, erst bei 35 %, 66 % | 0, 100 % |
| Skalierung 125 %, Holds | nicht gemessen | 0, 100 % |
| Intro, Feld links, eigene Werte | nicht gemessen | 0, 95 % |
| Intro, Fenster 640x720 (Ring passt nicht daneben) | nicht gemessen | 0, 94 % |

### Ohne Fund gemessen (vorher, je 0 Funde, Sichtzeit >= 96 %)

1680x1050 (16:10); eingebauter Look Balken und Kreise (`--skin2d=`);
osu!-Skins BubbleSkinHappyEdit (Holds) und Aoki 1.2; eigene Werte HitPosition
300 und 480 + Feld links; Skalierung 50 %; Scroll nach oben; Scroll nach oben +
Skalierung 70 % (Holds); Spurbreite 70 %; Hidden; Cover von unten (75 %, Wirkung
des Mods); Konstant; Scroll Speed 5 und 30; Holds-Map.

Gewollt, kein Fund: FadeIn (Noten ab 15 % sichtbar, 83 %), Cover 50 % von oben
(ab 38 %, 62 %): das ist die Wirkung des Mods.

### Nicht gemessen

- 2560x1440: der Testmonitor begrenzt das Fenster auf 1061 Zeilen.
- Break mitten im Song: in der Stichprobe keine Map ohne SV mit Break in den
  ersten 45 s. Gleicher Ring, gleicher Code wie beim Intro.
- Pause/Resume, Retry, Intro-Skip: brauchen Eingaben, per Autoplay nicht
  ausgeloest. Im Code: Pause haelt die Uhr, das 3-2-1 ist nur Text.
- Echte Eingaben (Misses, fruehes Druecken): Autoplay trifft alles.

## SV am Songanfang

Bug (Nutzer): "sath4 - <3#006" [Recollectia, w/ [-SVzzZ-]] (mirror_2141771,
4788 Timing-Points, erste Note 498 ms): die ersten Noten stehen beim Start
schon mitten im Feld.

Ursache: nicht das SV. `SyncClock.play()` laeuft in `_ready`, danach laedt die
Szene weiter (`BeatClock.setup` 1,2 s bei 4788 Timing-Points). Die Vorlaufuhr
lief in dieser Zeit schon, der Vorlauf (1538 ms) war beim 3-2-1 verbraucht.
Maps ohne SV haben wenige Timing-Points und laden schnell, darum fiel es nur
bei SV-Maps auf.

Fix: der Vorlauf beginnt mit dem ersten Tick nach `play()` (erster Frame oder
`pause()` des Start-Countdowns), `scripts/audio/sync_clock.gd`. Mania startet
immer mit mindestens 1 ms Vorlauf, damit auch Maps ohne noetigen Vorlauf nicht
waehrend des Ladens Songzeit verlieren (`mania_3d.gd` `_load_beatmap`).
SV-Darstellung, Trefferzeiten und Audio-Start (Songzeit 0) unveraendert.
Test: `tests/run_sv_start_tests.gd`.

Repro (2D, Autoplay, `--debug-popin`): vorher finds=9, min_vis_ratio=0.37,
Note 0 erst 528 ms vor dem Treffer. Nachher finds=0, min_vis_ratio=1.00, Uhr
am Ende des Countdowns bei -1538 ms.

Stichprobe: 20 SV-Maps (4K, meiste SV-Wechsel, erste Note vor 3 s), 2D,
Autoplay, bis 1,3 s nach der ersten Note. "Uhr" = Songzeit am Ende des
Countdowns, muss dem Vorlauf entsprechen.

| Map | Diff | Timing-Points | Ladezeit ms | Vorlauf ms | Uhr ms | finds | min_vis |
|---|---|---|---|---|---|---|---|
| 2280366 rejection - Calling | Hard | 4805 | 1441 | 1842 | -1838 | 0 | 0.96 |
| mirror_2141771 | Recollectia, w/ [-SVzzZ-] | 4788 | 1569 | 1538 | -1536 | 0 | 1.00 |
| mirror_2096660 | Insanity | 3134 | 693 | 1990 | -1981 | 0 | 0.99 |
| mirror_2449429 | TUTORIAL? | 2615 | 651 | 1209 | -1207 | 0 | 0.99 |
| mirror_2485116 | HAHA | 2120 | 371 | 1926 | -1925 | 0 | 0.99 |
| mirror_2426813 | Insane | 1638 | 388 | 1055 | -1053 | 0 | 1.00 |
| mirror_2264736 | Clarity | 1425 | 423 | 106 | -105 | 0 | 1.00 |
| mirror_2398569 | Insane | 476 | 405 | 1794 | -1793 | 0 | 0.99 |
| mirror_2563907 | Expert | 303 | 261 | 1241 | -1239 | 0 | 1.00 |
| mirror_2586880 | #UnnamedCrush (SV) [Swid] | 258 | 1808 | 0 | 2 | 0 | 0.99 |
| mirror_2495730 | Supernova // Insane | 199 | 335 | 2021 | -2019 | 0 | 0.99 |
| 381334 aaaa - Bokutachi no Tabi to Epilogue | Final Voyage | 239 | 413 | 1712 | -1710 | 0 | 0.99 |
| mirror_2541848 | INSANE://MEMORIES_OF_YOUTH | 130 | 559 | 661 | -659 | 0 | 0.97 |
| 171880 xi - Happy End of the World | Fullerene's 4K Catastrophic Shift | 196 | 869 | 1825 | -1824 | 0 | 1.00 |
| 2289293 Tsukasa Kaminose - ruin of opals | Iridescence | 160 | 332 | 986 | -985 | 0 | 1.00 |
| mirror_2563643 | Chocho Chocho | 85 | 406 | 1351 | -1349 | 0 | 0.98 |
| mirror_1178589 | Bakarina | 75 | 306 | 1636 | -1635 | 0 | 0.99 |
| mirror_2564470 | Neon's Easy | 147 | 353 | 1905 | -1904 | 0 | 0.99 |
| mirror_2278487 | Normal | 161 | 239 | 2014 | -2013 | 0 | 1.00 |
| mirror_240415 | puxtu's HD | 63 | 265 | 2000 | -1999 | 0 | 1.00 |

UnnamedCrush braucht keinen Vorlauf (erste Note 2670 ms). Vor dem
1-ms-Mindestvorlauf stand die Uhr am Ende des Countdowns schon bei 477 ms.

### Offen

- mirror_2323003 [Lunatic || Extra] (4517 Timing-Points): `start_lead_ms`
  liefert 107021 ms Vorlauf (fruehester Spawn -106421 ms, SV-Stillstand am
  Anfang). Der Song beginnt erst nach 107 s Stille. Schon vor diesem Fix so,
  nicht geaendert: eine Obergrenze fuer den Vorlauf aendert, wie das SV am
  Anfang aussieht (Nutzer-Entscheidung).
- 3D nicht erneut gemessen (`--debug-popin` misst nur das 2D-Feld). Uhr und
  Vorlauf sind fuer 2D und 3D derselbe Code.
