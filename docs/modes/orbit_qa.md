# Orbit-QA (Messungen)

Unabhaengige Pruefung von Orbit mit Messungen statt Bauchgefuehl: Takt,
menschliche Spielbarkeit, Lesbarkeit bei hoher Dichte, Sterne. Alle Zahlen
stammen aus `tests/run_orbit_qa_tests.gd` (headless, ~80 s, `warmd test
orbit_qa`, 16 Pruefungen). Rohdaten je Lauf: `user://orbit_qa/qa.json`
(je Map Ziele, Bot-Ergebnisse, Ursachen).

Code, den die QA geaendert hat: `scripts/orbit/orbit_converter.gd`
(Erreichbarkeits-Regel, Sterne), `scripts/orbit/orbit_view.gd`
(Groessen-Anpassung, Stapel-Hinweis, Geometrie-Helfer fuer den Test).

## Testmaps

23 Maps aus `user://orbit_sources`: 12 osu!standard (Zekk - Fluctuation 5
Diffs, Lime - Aurora 4, goreshit - burn this moment 2, Billain - Specialist 1)
und 11 4K (Billain - Specialist 5, Zekk - Fluctuation 5, goreshit - burn this
moment 1). Zusammen 25 168 Ziele.

## 1. Takt

| Pruefung | Ergebnis |
| --- | --- |
| Zielzeit = Original-Notenzeit (Kopf) | 25 168 von 25 168 exakt, max. Abweichung 0,000 ms |
| Bogen-Ende = Original-Ende (Slider/Hold) | max. Abweichung 0,000 ms |
| Anflug kreuzt den Ring zur Trefferzeit (rechnerisch aus `orbit_view`) | Fehler 0,0 ms |
| Erster 240-FPS-Frame am Ring nach dem Treffer | hoechstens 4,16 ms (< 1 Frame = 4,17 ms) |
| Anflug monoton (kein Ruckeln) | ja |
| Gezeichneter Winkel = Zielwinkel | Fehler 0,00002 Grad |
| Gezeichnete Bogen-Spitze = Wertungs-Spitze (`angle_at`) | Fehler 0,0 Grad |
| Bogen-Ende gezeichnet = gewertet | Fehler 0,0 Grad |

Methode: Fuer jedes Ziel wird die Anflugposition aus `OrbitView` zur Zeit t
berechnet (`radius_at`, `draw_pos`, `arc_tip_deg`). Der Zeitfehler des
Ring-Durchgangs ist der Radiusfehler zur Trefferzeit geteilt durch die
Anfluggeschwindigkeit; dazu 240-FPS-Frames mit wechselnder Phase fuer den
ersten Frame am Ring. Dazu ein synthetischer Bogen mit bekannter Geometrie. Die Wertung (`orbit_core.gd`) liegt seit
den Orbit-Replays auf einem festen 1-ms-Raster; das aendert keine Zielzeit,
die Zeiten sind ganzzahlige Millisekunden der Quelle.

Befund: kein Takt-Fehler. Nichts geaendert.

## 2. Menschlicher Bot

Modell (je Map 2 Seeds, ein Schritt = ein 240-FPS-Frame):

- Druckzeit: Normalverteilung, sigma 25 ms (auf 3 sigma gekappt).
- Zielwinkel: Normalverteilung, sigma 6 Grad.
- Zeigertempo hoechstens 350 Grad/s (Tablet) bzw. 250 Grad/s (Maus). Der
  Zeiger faehrt zum naechsten offenen Ziel, bei Bogen der Spitze nach.
- Kurven schneiden: bei Folgeziel unter 250 ms hoechstens 8 Grad Vorhalt
  in dessen Richtung.
- Vergleich "frei": gleicher Bot ohne Tempogrenze. Was frei trifft und mit
  Grenze nicht, verliert der Mensch wegen der Map, nicht wegen Streuung.
- Ursache je Fehler: `sprung` (noetiges Tempo > Grenze), `dichte` (Abstand
  unter `STREAM_GAP_MS`), `bogen_einstieg`, `bogen_ausstieg` (Ziel kurz nach
  Bogen-Ende), `bogen_release`, `streuung` (Rest).

### Vorher

Fehlerquote gesamt: frei 0,75 %, Tablet 12,19 %, **Maus 27,68 %**.
Ursachen (Maus, Fehler ueber alle Laeufe): sprung 5534, dichte 5182,
bogen_ausstieg 1836, streuung 759, bogen_einstieg 619, bogen_release 2.

Schlechteste 20 Stellen (Maus, Fehler je Lauf ueber dem freien Bot; in
Klammern alle Fehler je Lauf):

| # | Map | Zeit | Fehler | Ursache | Weg / Zeit, noetiges Tempo |
| --- | --- | --- | --- | --- | --- |
| 1 | 4K Billain - Specialist [Humanoid] | 2:04.039 | +21,0 (22,0) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |
| 2 | 4K Zekk - Fluctuation [Hyper] | 1:28.174 | +21,0 (21,0) | dichte | 47 Grad in 77 ms, 0,39 Grad/ms |
| 3 | 4K Billain - Specialist [Humanoid] | 3:02.131 | +20,0 (20,0) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |
| 4 | 4K Zekk - Fluctuation [Hyper] | 1:10.004 | +20,0 (20,0) | dichte | 47 Grad in 77 ms, 0,39 Grad/ms |
| 5 | 4K Billain - Specialist [GoldenJumper's Insane] | 2:38.027 | +20,0 (20,0) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |
| 6 | 4K Billain - Specialist [Humanoid] | 1:30.050 | +19,0 (19,5) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |
| 7 | 4K Billain - Specialist [GoldenJumper's Insane] | 2:46.178 | +19,0 (19,0) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |
| 8 | 4K Billain - Specialist [Humanoid] | 2:06.120 | +18,5 (18,5) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |
| 9 | 4K Billain - Specialist [GoldenJumper's Insane] | 1:44.097 | +18,5 (18,5) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |
| 10 | 4K Billain - Specialist [Humanoid] | 3:38.027 | +18,5 (18,5) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |
| 11 | 4K Billain - Specialist [Humanoid] | 3:40.021 | +17,5 (18,0) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |
| 12 | 4K Billain - Specialist [GoldenJumper's Insane] | 1:34.212 | +17,5 (18,0) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |
| 13 | 4K Billain - Specialist [Humanoid] | 2:14.010 | +17,5 (17,5) | sprung | 48 Grad in 86 ms, 0,37 Grad/ms |
| 14 | 4K Billain - Specialist [Humanoid] | 2:30.137 | +17,5 (17,5) | sprung | 48 Grad in 86 ms, 0,37 Grad/ms |
| 15 | 4K Billain - Specialist [Humanoid] | 3:14.010 | +17,0 (17,5) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |
| 16 | std Zekk - Fluctuation [Last Stand] | 2:12.040 | +17,0 (17,5) | dichte | 92 Grad in 77 ms, 0,50 Grad/ms |
| 17 | 4K Billain - Specialist [Humanoid] | 1:56.062 | +17,0 (17,0) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |
| 18 | 4K Billain - Specialist [Humanoid] | 2:38.027 | +17,0 (17,0) | sprung | 55 Grad in 86 ms, 0,37 Grad/ms |
| 19 | 4K Zekk - Fluctuation [Drago's Oscillation] | 1:44.102 | +17,0 (17,0) | dichte | 50 Grad in 77 ms, 0,39 Grad/ms |
| 20 | 4K Billain - Specialist [GoldenJumper's Insane] | 2:22.160 | +17,0 (17,0) | dichte | 48 Grad in 86 ms, 0,37 Grad/ms |

Ursache gemeinsam: Streams (Abstand 77-86 ms), in denen jeder Schritt
fuer sich innerhalb der alten Tempo-Grenze lag, der Zeiger aber ueber viele
Schritte immer weiter zurueckfiel (0,37-0,50 Grad/ms Dauertempo, Maus
schafft 0,25). Die alten Fairness-Regeln pruefen nur Einzelschritte.

### Behebung (Converter)

`orbit_converter.gd`, Regel `_reach`: ein virtueller Zeiger mit
`HUMAN_DEG_PER_MS` = 0,25 Grad/ms faehrt vom letzten Ziel zum naechsten.
Das neue Ziel liegt hoechstens `HUMAN_REACH_DEG` = 10 Grad neben der so
erreichbaren Stelle (22 Grad Treffer-Toleranz minus 2 sigma Zielstreuung).
Weil der Zeiger mitlaeuft, gilt die Grenze dauerhaft: der Rueckstand kann
in Streams nicht anwachsen. `OrbitConverter.human_reach = false` schaltet
die Regel fuer Vorher-Messungen ab.

### Nachher

| Map | Ziele | frei | Tablet vorher | Tablet nachher | Maus vorher | Maus nachher |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| std Zekk [Collab Extra] | 712 | 0,6 % | 12,4 % | 0,7 % | 26,2 % | 3,2 % |
| std Zekk [Heilia's Hard] | 294 | 0,3 % | 9,2 % | 0,5 % | 16,2 % | 3,1 % |
| std Zekk [Last Stand] | 813 | 0,6 % | 17,2 % | 0,7 % | 34,3 % | 3,6 % |
| std Zekk [Mordred's Normal] | 210 | 0,0 % | 4,0 % | 0,0 % | 6,2 % | 1,0 % |
| std Zekk [hypercyte's Insane] | 476 | 0,4 % | 15,9 % | 0,5 % | 29,3 % | 2,6 % |
| std Lime [Expert] | 804 | 0,4 % | 8,8 % | 0,3 % | 17,7 % | 1,2 % |
| std Lime [Hard] | 390 | 0,3 % | 7,6 % | 0,3 % | 12,6 % | 1,4 % |
| std Lime [Insane] | 569 | 0,1 % | 6,1 % | 0,3 % | 13,3 % | 1,4 % |
| std Lime [Normal] | 273 | 0,0 % | 1,6 % | 0,0 % | 4,2 % | 0,5 % |
| std goreshit [extra] | 1750 | 0,4 % | 21,5 % | 0,7 % | 42,2 % | 4,6 % |
| std goreshit [insane] | 1507 | 0,3 % | 13,1 % | 0,6 % | 29,8 % | 3,3 % |
| std Billain [Fulminant Allusion] | 1590 | 0,7 % | 18,0 % | 0,7 % | 36,0 % | 3,6 % |
| 4K Billain [Advanced] | 1019 | 0,8 % | 6,4 % | 0,5 % | 23,0 % | 2,1 % |
| 4K Billain [GoldenJumper's Insane] | 1677 | 1,1 % | 25,6 % | 0,9 % | 47,2 % | 3,8 % |
| 4K Billain [Humanoid] | 1625 | 1,2 % | 23,6 % | 0,8 % | 54,1 % | 3,6 % |
| 4K Billain [Pairo's Normal] | 676 | 0,1 % | 0,5 % | 0,2 % | 9,9 % | 2,6 % |
| 4K Billain [Yuno's Hard] | 1468 | 1,0 % | 14,9 % | 0,9 % | 39,7 % | 4,1 % |
| 4K Zekk [Drago's Oscillation] | 1327 | 0,9 % | 12,4 % | 0,8 % | 26,4 % | 2,0 % |
| 4K Zekk [Hyper] | 1223 | 1,1 % | 13,2 % | 0,7 % | 30,6 % | 2,7 % |
| 4K Zekk [Insane] | 1295 | 0,9 % | 12,2 % | 0,8 % | 26,4 % | 2,1 % |
| 4K Zekk [Normal] | 830 | 0,8 % | 0,8 % | 0,5 % | 6,4 % | 1,4 % |
| 4K Zekk [Revv's Hard] | 1059 | 0,6 % | 9,3 % | 0,5 % | 22,3 % | 3,1 % |
| 4K goreshit [fear] | 3581 | 0,8 % | 1,2 % | 0,8 % | 9,8 % | 1,5 % |
| **Gesamt** | 25 168 | 0,72 % | 12,19 % | **0,67 %** | 27,68 % | **2,76 %** |

Ursachen nachher (Maus): dichte 902, bogen_ausstieg 228, streuung 132,
bogen_einstieg 105, sprung 21 (vorher 5534). Die schlechteste Stelle hat
nachher +4,0 Fehler je Lauf (vorher +21,0); die Top 20 liegen alle bei
+2,5 bis +4,0, Ursache dichte, noetiges Tempo 0,07-0,25 Grad/ms, also
Zeit-Streuung in 77-138-ms-Streams statt Zeigerweg.

Pruefungen: Tablet-Bot verliert < 3 %, Maus-Bot < 6 % der Ziele (beide
bestanden).

### Preis: Lage-Treue bei osu!standard

Die Regel verschiebt Ziele, die der Zeiger nicht erreicht. Gemessen wird der
Winkel zwischen Orbit-Ziel und der Richtung der osu-Position zur
Bildschirmmitte:

| | Median | p90 |
| --- | ---: | ---: |
| vorher | 0,0 Grad | 50,2 Grad |
| nachher | 1,2 Grad | 91,5 Grad |

Der Median bleibt nahe 0 (die meisten Ziele liegen wie im Original), aber
**10 % der osu!standard-Ziele liegen jetzt 91 Grad oder mehr neben ihrer
Original-Richtung** (vorher 50 Grad). Das sind fast nur schnelle Spruenge
und Streams, die mit 250 Grad/s nicht erreichbar waren. Wer die
Original-Lage dort will, braucht einen schnelleren Zeiger (Tablet) und
muss die Fehlerquote von vorher in Kauf nehmen. Pruefung "Median <= 20 Grad"
bestanden. 4K-Maps haben keine Original-Lage, dort gibt es keinen Preis.

## 3. Lesbarkeit bei hoher Dichte

Je Map die dichtesten 5 s, 1920x1080, Scroll 1,0, alle 50 ms ein Frame.
Gezaehlt werden sichtbare Ziele (Einblendung >= 50 %), deren Kreise sich
ueberschneiden, und Ziele, die ganz unter einem anderen liegen.

### Behebung (View)

- `_fit_sizes`: spaetere Ziele auf demselben Ring schrumpfen, bis sie das
  vorherige nicht mehr ueberdecken (hoechstens bis `FIT_MIN` = 0,3 der
  Groesse, Abstand `FIT_GAP_K`). Das naechste Ziel je Ring behaelt immer
  volle Groesse.
- Stapel-Hinweis (`_halo`, `_draw_halo`): ein Ziel, das trotz Schrumpfen
  unter einem anderen liegt, bekommt einen Randring, damit es als eigenes
  Ziel zaehlbar bleibt.
- `fit_enabled = false` zeigt die alte Darstellung (nur Vorher-Messung).

### Vorher / Nachher

| Map | Ziele/s | verdeckt vorher | verdeckt nachher | Ueberschn./Frame vorher | nachher |
| --- | ---: | ---: | ---: | ---: | ---: |
| std Zekk [Collab Extra] | 8,2 | 18,4 % | 6,1 % | 1,08 | 0,45 |
| std Zekk [Heilia's Hard] | 4,0 | 8,7 % | 4,3 % | 0,17 | 0,05 |
| std Zekk [Last Stand] | 9,2 | 25,9 % | 13,0 % | 2,04 | 1,06 |
| std Zekk [Mordred's Normal] | 3,4 | 5,3 % | 5,3 % | 0,16 | 0,06 |
| std Zekk [hypercyte's Insane] | 5,8 | 9,1 % | 0,0 % | 0,58 | 0,00 |
| std Lime [Expert] | 9,8 | 24,1 % | 13,0 % | 2,41 | 1,20 |
| std Lime [Hard] | 4,4 | 22,2 % | 14,8 % | 0,79 | 0,52 |
| std Lime [Insane] | 6,0 | 14,3 % | 8,6 % | 0,71 | 0,45 |
| std Lime [Normal] | 2,8 | 6,3 % | 6,3 % | 0,19 | 0,19 |
| std goreshit [extra] | 7,4 | 2,3 % | 0,0 % | 0,17 | 0,00 |
| std goreshit [insane] | 6,4 | 0,0 % | 0,0 % | 0,00 | 0,00 |
| std Billain [Fulminant Allusion] | 8,6 | 18,4 % | 6,1 % | 1,19 | 0,25 |
| 4K Billain [Advanced] | 7,6 | 21,7 % | 15,2 % | 1,40 | 0,91 |
| 4K Billain [GoldenJumper's Insane] | 11,6 | 32,4 % | 12,7 % | 3,78 | 1,15 |
| 4K Billain [Humanoid] | 11,2 | 22,1 % | 19,1 % | 2,15 | 1,85 |
| 4K Billain [Pairo's Normal] | 6,0 | 8,6 % | 8,6 % | 0,57 | 0,57 |
| 4K Billain [Yuno's Hard] | 11,0 | 42,4 % | 16,7 % | 4,04 | 1,18 |
| 4K Zekk [Drago's Oscillation] | 12,8 | 35,8 % | 19,4 % | 4,23 | 1,54 |
| 4K Zekk [Hyper] | 12,8 | 35,8 % | 25,4 % | 4,01 | 2,59 |
| 4K Zekk [Insane] | 12,8 | 43,5 % | 31,9 % | 5,58 | 2,78 |
| 4K Zekk [Normal] | 8,4 | 2,0 % | 2,0 % | 0,18 | 0,18 |
| 4K Zekk [Revv's Hard] | 10,8 | 22,8 % | 17,5 % | 1,73 | 0,74 |
| 4K goreshit [fear] | 14,4 | 50,0 % | 45,5 % | 11,65 | 5,44 |
| **Mittel** | | **20,5 %** | **12,7 %** | | |

Ganz verdeckte Ziele ohne Hinweis: 1,02 Paare je Frame vorher, 0,00
nachher. Ring-uebergreifende Ueberschneidungen gibt es praktisch nicht
(hoechstens 4 %), Ueberdeckung entsteht fast nur auf demselben Ring.

Rest-Problem: goreshit [fear] (14,4 Ziele/s, viele Ziele am selben Winkel
hintereinander) bleibt bei 45 % verdeckt. Dort liegen Folgeziele
absichtlich am gleichen Ort (Jacks); der Stapel-Hinweis macht sie zaehlbar.
Behoben durch den Stapel-Versatz im Converter (unten): fear 12,5 %.

### Shots

Fenster-Lauf (selbst-beendend, Monitor 2, Dummy-Audio):

```
cp tools/test_override.cfg override.cfg
ORBIT_QA_FIT=1 ORBIT_QA_TAG=fit1 timeout 90 Godot_v4.7-stable_win64_console.exe \
  --position -1920,0 --audio-driver Dummy --path . \
  --script res://tests/run_orbit_qa_tests.gd -- --shots
rm override.cfg
```

Ergebnis in `user://orbit_qa/shots/` (`fit0_*` = alte Darstellung,
`fit1_*` = mit Groessen-Anpassung und Stapel-Hinweis), je Quelle die
dichteste Diff am Frame mit der staerksten Ueberdeckung:

| Map | Zeitpunkt | verdeckt (5 s) |
| --- | --- | ---: |
| std Zekk [Last Stand] | 2:02.781 | 13 % |
| std Lime [Expert] | 1:50.350 | 13 % |
| std goreshit [extra] | 5:24.728 | 0 % |
| std Billain [Fulminant Allusion] | 3:28.165 | 6 % |
| 4K Billain [GoldenJumper's Insane] | 1:29.547 | 13 % |
| 4K Zekk [Drago's Oscillation] | 1:27.632 | 19 % |
| 4K goreshit [fear] | 5:00.664 | 45 % |

Sichtkontrolle: Streams erscheinen als Kette kleiner werdender Ziele hinter
dem naechsten Ziel, die Reihenfolge ist an der Groesse ablesbar; gestapelte
Ziele tragen den Randring.

### Stapel-Versatz (Converter)

Rest-Problem oben: Folgeziele am selben Winkel (Jacks, osu!standard-Stacks)
lagen auf demselben Ring uebereinander. `orbit_converter.gd` trennt sie
jetzt, die Zeiten bleiben exakt:

- Jack-Zickzack (4K, gleiche Spalte, Abstand < `DRIFT_GAP_MS`): Versatz
  0, 1, 2, 1 Stufen (`STACK_PATTERN`) zu je `STACK_STEP_DEG` = 5 Grad in
  Fluss-Richtung, begrenzt durch das Sprung-Limit.
- `_unstack` (alle Modi, auch Akkorde): liegt ein Ziel naeher als
  `STACK_NEAR_DEG` = 7 Grad an einem der letzten 3 Ziele desselben Rings
  (hoechstens `STACK_WINDOW_MS` = 320 ms davor), rutscht es auf
  `STACK_PUSH_DEG` = 8 Grad neben einen Nachbarn. Kandidaten beidseits jedes
  Nachbarn; nur freie und vom Zeiger erreichbare, der kuerzeste Weg gewinnt,
  bei Gleichstand die Fluss-Richtung. Kein freier erreichbarer Platz: das
  Ziel bleibt, der Stapel-Hinweis (Randring) markiert es.
- Der virtuelle Zeiger von `_reach` folgt dem versetzten Ziel. Ohne das
  rechnete der naechste Schritt vom alten Winkel aus; das kostete den
  Maus-Bot 0,3-0,7 Prozentpunkte (3,1-4,8 % statt 2,8 %).

Ring-Wechsel als Stapel-Mittel ist nicht eingebaut: der Ring folgt weiter
der Spalte bzw. der Ring-Regel (`SAME_RING_MIN_MS`, `RELEASE_GAP_MS`); der
Winkelversatz allein reicht fuer < 15 % auf jeder Map.

Messung (dichteste 5 s, mit Groessen-Anpassung), Versatz-Sweep
STEP/NEAR/PUSH in Grad:

| Versatz | schlechteste 4K-Map | Maus | Tablet |
| --- | ---: | ---: | ---: |
| ohne (Stand vorher) | 45,5 % (fear) | 2,76 % | 0,67 % |
| 0/4/5, ohne Zeiger-Nachfuehrung | 28,4 % | 3,21 % | 0,76 % |
| 3/4/5, ohne Zeiger-Nachfuehrung | 29,5 % | 3,17 % | 0,74 % |
| 4/6/7, ohne Zeiger-Nachfuehrung | 14,8 % | 3,43 % | - |
| 9/14/16, ohne Zeiger-Nachfuehrung | < 15 % | 4,80 % | 1,14 % |
| 4/6/7, mit Zeiger-Nachfuehrung | 15,2 % (Yuno's Hard) | 2,52 % | 0,64 % |
| **5/7/8, mit Zeiger-Nachfuehrung** | **13,6 %** (Yuno's Hard) | **2,52 %** | **0,64 %** |

Gewaehlt 5/7/8. Verdeckt nachher je Map (vorher = Stand ohne Versatz aus
der Tabelle oben):

| Map | verdeckt vorher | verdeckt nachher |
| --- | ---: | ---: |
| std Zekk [Collab Extra] | 6,1 % | 6,1 % |
| std Zekk [Heilia's Hard] | 4,3 % | 4,3 % |
| std Zekk [Last Stand] | 13,0 % | 13,0 % |
| std Zekk [Mordred's Normal] | 5,3 % | 5,3 % |
| std Zekk [hypercyte's Insane] | 0,0 % | 0,0 % |
| std Lime [Expert] | 13,0 % | 13,0 % |
| std Lime [Hard] | 14,8 % | 14,8 % |
| std Lime [Insane] | 8,6 % | 8,6 % |
| std Lime [Normal] | 6,3 % | 6,3 % |
| std goreshit [extra] | 0,0 % | 0,0 % |
| std goreshit [insane] | 0,0 % | 0,0 % |
| std Billain [Fulminant Allusion] | 6,1 % | 6,1 % |
| 4K Billain [Advanced] | 15,2 % | 8,7 % |
| 4K Billain [GoldenJumper's Insane] | 12,7 % | 12,7 % |
| 4K Billain [Humanoid] | 19,1 % | 8,8 % |
| 4K Billain [Pairo's Normal] | 8,6 % | 8,6 % |
| 4K Billain [Yuno's Hard] | 16,7 % | 13,6 % |
| 4K Zekk [Drago's Oscillation] | 19,4 % | 9,0 % |
| 4K Zekk [Hyper] | 25,4 % | 11,9 % |
| 4K Zekk [Insane] | 31,9 % | 10,1 % |
| 4K Zekk [Normal] | 2,0 % | 2,0 % |
| 4K Zekk [Revv's Hard] | 17,5 % | 12,3 % |
| 4K goreshit [fear] | 45,5 % | 12,5 % |
| **Mittel** | **12,7 %** | **8,2 %** |

Bot nachher (fair, 2 Seeds): Tablet 0,64 % (vorher 0,67 %), Maus 2,52 %
(vorher 2,76 %), frei 0,69 %; Ursachen Maus: dichte 785, bogen_ausstieg
229, streuung 129, bogen_einstieg 104, sprung 21. fear: Maus 1,4 %, Tablet
0,7 %. Kein Zielkonflikt zwischen Lesbarkeit und Spielbarkeit: der
Versatz folgt dem Zeigerweg und macht die Wege nicht laenger.

Neue Pruefung: "auf jeder Map unter 15 % verdeckt" (bestanden).
`ORBIT_QA_ONLY=density` misst nur die Dichte (ohne Bot), fuer schnelle
Sweeps.

Shots (`stack0_*` = Converter aus v1.19.0, `stack1_*` = mit Versatz, beide
mit Groessen-Anpassung; `ORBIT_QA_TAG=stack0` bzw. `stack1`, sonst wie
oben):

| Map | vorher (stack0) | verdeckt | nachher (stack1) | verdeckt |
| --- | --- | ---: | --- | ---: |
| 4K goreshit [fear] | 5:00.664 | 45 % | 4:59.264 | 13 % |
| 4K Zekk [Drago's Oscillation] (Jacks) | 1:27.632 | 19 % | 1:27.532 | 9 % |
| 4K Billain [GoldenJumper's Insane] | 1:29.547 | 13 % | 1:30.197 | 13 % |
| std (alle 4 Quellen) | gleich | gleich | gleich | gleich |

Sichtkontrolle: fear vorher ein Knaeuel aus 5-6 Quadraten und Kreisen auf
einem Fleck (nur ueber Groesse und Randring zaehlbar), nachher eine Kette
nebeneinander liegender Ziele, die Reihenfolge laeuft entlang der Kette.
Drago vorher Jack-Quadrate ineinander, nachher eine Treppe aus 4 getrennten
Quadraten auf dem aeusseren Ring. Kein Flackern: der Versatz ist Teil der
Map, nicht der Darstellung. osu!standard-Shots unveraendert (dort greift
der Versatz an den dichtesten Stellen nicht).

## 4. Sterne

Die alten Orbit-Sterne (Dichte 0,32 * Ziele/s^0,8 plus 0,29 * Winkelweg/s,
Fenster 2 s, Gewicht 0,9^k) bewerteten 4K-Maps nach Dichte hoch und
schnelle osu!standard-Spruenge zu niedrig. Rangkorrelation (Spearman, 23
Maps) gegen den Bot-Verlust (Fehlerquote + 1 - Acc):

| | Maus-Bot | Tablet-Bot |
| --- | ---: | ---: |
| vorher | 0,56 | 0,76 |
| nachher | **0,76** | **0,84** |

Neue Formel (`OrbitConverter.stars`): jeder Zeigerzug zaehlt im Wegterm mit
`Weg * min(Tempo / 0,25 Grad/ms, 2)^2`. Langsame Zuege zaehlen kaum, ein
Zug mit Maus-Grenztempo voll, schnellere bis 4-fach. Gewichte:
`STAR_DENS_K` 0,1, `STAR_PATH_K` 1,0, `STAR_SPEED_CAP` 2, `STAR_DECAY` 0,95.
Gefunden per Rastersuche (Dichte-Gewicht, Exponent, Kappe, Abfall) auf den
Rohdaten aus `qa.json`; die reine Wegformel ohne Dichte erreicht 0,80,
die Dichte bleibt bewusst mit kleinem Gewicht drin (Tippen allein kostet
auch Kraft).

| Map | Sterne vorher | nachher | Bot-Verlust Maus |
| --- | ---: | ---: | ---: |
| std Lime [Normal] | 1,07 | 0,97 | 0,066 |
| std Zekk [Mordred's Normal] | 1,09 | 1,06 | 0,065 |
| std Lime [Hard] | 1,37 | 1,63 | 0,090 |
| std Zekk [Heilia's Hard] | 1,41 | 1,83 | 0,122 |
| std Lime [Insane] | 1,80 | 1,87 | 0,103 |
| 4K Billain [Pairo's Normal] | 1,71 | 2,06 | 0,118 |
| 4K Zekk [Normal] | 2,16 | 2,43 | 0,098 |
| std Lime [Expert] | 2,37 | 2,45 | 0,100 |
| std Zekk [hypercyte's Insane] | 1,85 | 2,48 | 0,133 |
| 4K Billain [Advanced] | 2,18 | 2,72 | 0,112 |
| 4K Zekk [Revv's Hard] | 2,68 | 3,08 | 0,135 |
| 4K goreshit [fear] | 2,65 | 3,16 | 0,126 |
| std goreshit [insane] | 2,05 | 3,27 | 0,143 |
| std Zekk [Collab Extra] | 2,40 | 3,42 | 0,150 |
| std Billain [Fulminant Allusion] | 2,41 | 3,62 | 0,162 |
| 4K Zekk [Hyper] | 3,03 | 3,82 | 0,132 |
| std Zekk [Last Stand] | 2,53 | 3,85 | 0,153 |
| std goreshit [extra] | 2,28 | 3,99 | 0,181 |
| 4K Billain [Humanoid] | 3,02 | 4,15 | 0,156 |
| 4K Zekk [Drago's Oscillation] | 3,10 | 4,20 | 0,118 |
| 4K Zekk [Insane] | 3,12 | 4,20 | 0,118 |
| 4K Billain [Yuno's Hard] | 3,00 | 4,45 | 0,162 |
| 4K Billain [GoldenJumper's Insane] | 3,13 | 4,68 | 0,158 |

Die Skala reicht jetzt von etwa 1 (Normal) bis 4,7 (statt 1,1 bis 3,1).
Pruefung "Spearman Maus >= 0,7" bestanden.

## Grenzen

- Der Bot ist ein Modell (feste Streuung, feste Tempogrenze, kein Lesen,
  keine Ermuedung), keine Messung an Menschen. Die Zahlen zeigen, wo die Map
  vom Zeiger mehr verlangt als ein Mensch liefert, nicht wie schwer sie sich
  anfuehlt.
- Die Sterne sind auf denselben 23 Maps geeicht, an denen sie gemessen
  werden (4 freie Parameter). Neue Quellen koennen schwaecher korrelieren.
- 2 Seeds je Map; Unterschiede unter etwa 0,5 Prozentpunkten je Map sind
  Rauschen.
- Ueberdeckung wird geometrisch gezaehlt (Kreise), nicht als Wahrnehmung.
