# AmChart: Notensetzer, Messung

OMEN Auto-Mapper 4K, Modul `scripts/automap/am_chart.gd` (Spec: `docs/automap/spec.md`, Abschnitt AmChart).
Stand 2026-11-13. Alle Zahlen gemessen mit

```
Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . \
  --script res://tests/run_am_chart_tests.gd -- --measure <maps> 110 [--learn]
```

(ein Prozess: 238 Sets / 989 4K-Diffs lesen, 110 Sets erzeugen, rosu einmal fuer alle; gemessen 68.3 s).
`AM_VARIANTS='[{...}, ...]'` misst mehrere Parametersaetze im selben Prozess; so wurden die
Standardwerte gewaehlt.

## Aufbau

- `build(features, grid, profile, params)` wie Spec; `build_all(features, grid, params)` rechnet alle Profile
  in einem Durchgang (Ergaenzung zur Spec, gleiche Ergebnisse wie einzelne `build`-Aufrufe).
- `lint(notes, grid, profile)` prueft die Spielbarkeits-Tabelle der Spec. Seit 2026-11-13 stammen deren
  Werte aus der Statistik der Menschen-Maps je Sterne-Band (`patterns.json`, Obergrenze = Mittel x 1,25):
  Easy 1/2 und 2er-Akkorde auf dem Schlag, Normal 1/4 in Laeufen bis 7 Zeilen und seltene 3er-Akkorde,
  Hard seltene 1/8 und 3er-Akkorde auf dem Schlag, Hold und Note gleichzeitig in Easy/Normal selten.
- Muster aus `data/automap/patterns.json` (nur Statistik, keine Maps): je Band Zeilen-Uebergaenge je
  Abstandsklasse, die 1500 haeufigsten 4er-Muster (Modell: naechste Zeile nach den drei vorigen),
  8er-Muster, Akkord-/3er-/Hold-/Jack-Anteile, Lage der Zeilen (1/1, 1/2, 1/4, feiner), 1/4-Lauflaengen,
  Hold-Ueberlappung, Kiai-Dichteverhaeltnis, Ausgleich der Sterne-Schaetzung.
- Spaltenwahl: 4er-Modell (Gewicht 0,95) statt nur Zeilen-Uebergaengen, Zusatzgewicht fuer die 60
  haeufigsten 4er-Muster des Bands, Spalten-Frische (Menschen laufen ueber alle vier Spalten), Jack-Anteil
  auf den Wert des Bands geregelt, Figuren aus der Musik (Tonhoehe laeuft weiter: Treppe; zwei Toene im
  Wechsel: Triller; Hi-Hat-Lauf: Roll), Tonhoehe bestimmt die Richtung (Gegenrichtung stark bestraft).
- Sterne: mehr Noten statt Akkorde (seltene Teilung bis knapp unter ihre Obergrenze; Akkord-Aufschlag
  hoechstens +15 %). Akkord-, 3er- und Seltene-Teilung-Anteil werden nach dem Setzen nachgerechnet
  (Zeilen in Holds entfallen erst dort) und bei Ueberschuss mit weniger neu gesetzt.
- Holds nur auf gehaltenen Toenen (`sustain_ms`), staerkste zuerst; Budget bis zum 90. Perzentil der
  Menschen-Maps des Bands. Ohne sustain im Testeingang kommen die gehaltenen Toene aus den Holds der
  Menschen-Vorlage. Takt-Vorlagen zaehlen mit ihren Kopien (Akkorde, Holds).
- Wiederholung: Takte mit gleicher Musik uebernehmen Auswahl, Akkorde, Holds und Spalten ihres ersten
  Vorkommens; Spiegelung wie der Vortakt, dann passt der Uebergang. Scheitert es am Uebergang (Jack,
  Abstand), wird die letzte Zeile des Vortakts neu gesetzt, damit die Spalten des Motivanfangs frei sind.
- Sterne-Schaetzung `estimate_stars` = osu!mania-Strain-Formel wie rosu-pp (mittlerer Fehler 0,039 gegen
  rosu ueber 989 Menschen-Diffs, 0,02-0,03 bei den erzeugten Maps).

## Eingabe der Messung

Echte features/grid gibt es im Worktree noch nicht. Gemessen wird mit Eingaben aus Menschen-Maps: je
Set die 4K-Diff mit den meisten Noten liefert Notenzeiten als Ereignisse, mittlere Spalte als Tonhoehe,
Holds als gehaltene Toene (sustain), Akkorde als Akzente, Kiai als Abschnitt; die rote Linie ist das
Gitter. Diese Vorlage begrenzt die Sterne nach oben (Spalte "Vorlage schon unter Band").

## Gemessen (nachher)

### Vergleich erzeugt gegen Mensch je Sterne-Band (110 Sets erzeugt; Mensch: alle 4K-Diffs im Band)
| Kennzahl | Easy Mensch | Easy erzeugt | Normal Mensch | Normal erzeugt | Hard Mensch | Hard erzeugt | Insane Mensch | Insane erzeugt | Expert Mensch | Expert erzeugt |
|---|---|---|---|---|---|---|---|---|---|---|
| Maps | 222 | 110 | 248 | 110 | 238 | 110 | 181 | 110 | 70 | 110 |
| gleiche Spalte in Folge (Einzelnoten) | 4.7 % | 7.5 % | 4.5 % | 6.0 % | 4.1 % | 4.4 % | 4.5 % | 4.6 % | 3.5 % | 4.3 % |
| Nachbarspalte | 48.0 % | 46.2 % | 51.9 % | 50.6 % | 55.9 % | 56.9 % | 55.8 % | 55.4 % | 56.0 % | 54.9 % |
| weiter Sprung | 47.3 % | 46.2 % | 43.6 % | 43.4 % | 40.0 % | 38.7 % | 39.6 % | 40.1 % | 40.6 % | 40.8 % |
| Akkord-Zeilen | 18.3 % | 18.8 % | 32.9 % | 33.8 % | 36.9 % | 38.0 % | 39.6 % | 41.9 % | 41.0 % | 44.6 % |
| 3er/4er-Akkorde | 0.1 % | 0.0 % | 1.6 % | 1.6 % | 5.2 % | 5.2 % | 9.0 % | 9.1 % | 10.6 % | 10.5 % |
| Noten in Jacks (1/4) | 0.0 % | 0.0 % | 0.6 % | 0.0 % | 3.1 % | 3.7 % | 7.1 % | 7.9 % | 11.3 % | 11.6 % |
| Hold-Anteil | 18.2 % | 15.1 % | 18.7 % | 13.9 % | 15.9 % | 15.5 % | 14.0 % | 14.5 % | 18.2 % | 14.3 % |
| Hold-Laenge (Schlaege) | 1.21 | 0.92 | 0.82 | 0.86 | 0.69 | 0.72 | 0.62 | 0.72 | 0.54 | 0.69 |
| Noten/s Mittel | 3.81 | 3.35 | 6.93 | 5.90 | 10.07 | 8.70 | 13.26 | 10.51 | 16.06 | 11.98 |
| Noten/s Spitze | 7.27 | 7.34 | 12.35 | 11.70 | 17.56 | 15.99 | 23.01 | 18.95 | 27.84 | 21.06 |
| linke Hand | 50.0 % | 50.1 % | 49.9 % | 49.9 % | 50.0 % | 50.0 % | 50.0 % | 50.0 % | 49.9 % | 50.0 % |
| Abstand 1/8 und feiner | 0.2 % | 0.0 % | 0.6 % | 0.0 % | 2.2 % | 3.0 % | 8.6 % | 6.9 % | 12.4 % | 8.7 % |
| Abstand 1/4 | 4.6 % | 0.0 % | 21.1 % | 15.3 % | 43.7 % | 32.3 % | 52.9 % | 45.5 % | 57.1 % | 49.8 % |
| Abstand 1/2 | 39.5 % | 41.0 % | 58.2 % | 54.4 % | 45.9 % | 54.2 % | 33.4 % | 39.2 % | 26.7 % | 35.2 % |
| Zeilen auf 1/2 (zwischen den Schlaegen) | 26.9 % | 23.9 % | 35.4 % | 33.0 % | 32.3 % | 36.2 % | 28.0 % | 32.0 % | 26.2 % | 29.4 % |
| Zeilen auf 1/4 | 5.0 % | 0.0 % | 12.7 % | 9.6 % | 21.4 % | 17.6 % | 24.7 % | 25.1 % | 27.7 % | 24.7 % |
| Zeilen feiner als 1/4 | 1.3 % | 0.0 % | 2.6 % | 0.0 % | 8.1 % | 2.5 % | 14.6 % | 4.9 % | 16.3 % | 11.5 % |
| Akkorde auf dem Schlag | 89.4 % | 100.0 % | 81.4 % | 100.0 % | 69.8 % | 86.2 % | 60.1 % | 73.1 % | 53.1 % | 66.7 % |
| 3er/4er-Akkorde auf dem Schlag | 100.0 % | 0.0 % | 90.3 % | 100.0 % | 85.2 % | 100.0 % | 80.9 % | 100.0 % | 72.8 % | 96.8 % |
| Noten waehrend eines Holds | 3.0 % | 1.0 % | 6.9 % | 2.6 % | 7.6 % | 8.3 % | 7.5 % | 8.4 % | 11.5 % | 10.0 % |
| Lauf aus 1/4-Abstaenden, Zeilen (90. / 99. Perzentil) | 5 / 9 | 3 / 3 | 7 / 16 | 5 / 7 | 11 / 16 | 7 / 16 | 15 / 16 | 11 / 16 | 16 / 16 | 13 / 16 |
| Aehnlichkeit der Zeilen-Uebergaenge (0..1) | 1.00 | 0.80 | 1.00 | 0.81 | 1.00 | 0.82 | 1.00 | 0.81 | 1.00 | 0.78 |
| Anteil 4er-Muster in den Top 60 der Menschen | 42.5 % | 49.9 % | 25.9 % | 25.8 % | 20.9 % | 17.2 % | 18.8 % | 13.8 % | 22.4 % | 11.3 % |
### Erzeugt nach rosu-Band (jede erzeugte Diff in dem Band, in dem ihre rosu-Sterne liegen)
| Kennzahl | Easy Mensch | Easy erzeugt | Normal Mensch | Normal erzeugt | Hard Mensch | Hard erzeugt | Insane Mensch | Insane erzeugt | Expert Mensch | Expert erzeugt |
|---|---|---|---|---|---|---|---|---|---|---|
| Maps | 222 | 136 | 248 | 160 | 238 | 133 | 181 | 91 | 70 | 30 |
| Akkord-Zeilen | 18.3 % | 21.5 % | 32.9 % | 36.9 % | 36.9 % | 40.1 % | 39.6 % | 42.8 % | 41.0 % | 42.9 % |
| 3er/4er-Akkorde | 0.1 % | 0.4 % | 1.6 % | 3.9 % | 5.2 % | 6.9 % | 9.0 % | 9.7 % | 10.6 % | 10.3 % |
| Noten in Jacks (1/4) | 0.0 % | 0.0 % | 0.6 % | 1.5 % | 3.1 % | 5.4 % | 7.1 % | 10.0 % | 11.3 % | 14.0 % |
| Hold-Anteil | 18.2 % | 16.4 % | 18.7 % | 17.4 % | 15.9 % | 15.5 % | 14.0 % | 11.4 % | 18.2 % | 13.9 % |
| Noten/s Mittel | 3.81 | 3.45 | 6.93 | 6.76 | 10.07 | 9.58 | 13.26 | 12.70 | 16.06 | 15.55 |
| Noten/s Spitze | 7.27 | 7.42 | 12.35 | 12.79 | 17.56 | 17.35 | 23.01 | 22.65 | 27.84 | 27.70 |
| Anteil 4er-Muster in den Top 60 der Menschen | 42.5 % | 38.8 % | 25.9 % | 19.8 % | 20.9 % | 14.8 % | 18.8 % | 13.5 % | 22.4 % | 12.5 % |
### Sterne-Trefferquote je Profil (110 Sets)
| Profil | Band | rosu im Band | unter Band (davon Vorlage schon unter Band) | ueber Band | ausserhalb, als capped gemeldet | ausserhalb, nicht gemeldet | rosu Median | Schaetzung im Band | Fehler Schaetzung gegen rosu (Mittel) | lint-Verstoesse |
|---|---|---|---|---|---|---|---|---|---|---|
| Easy | 1.3-1.9 | 100 / 110 (90.9 %) | 10 (1) | 0 | 9 | 1 | 1.59 | 100 / 110 | 0.021 | 0 |
| Normal | 2.1-2.8 | 85 / 110 (77.3 %) | 25 (1) | 0 | 25 | 0 | 2.42 | 85 / 110 | 0.025 | 0 |
| Hard | 3.0-3.8 | 77 / 110 (70.0 %) | 33 (19) | 0 | 33 | 0 | 3.35 | 77 / 110 | 0.027 | 0 |
| Insane | 4.0-4.8 | 56 / 110 (50.9 %) | 54 (42) | 0 | 54 | 0 | 4.04 | 55 / 110 | 0.029 | 0 |
| Expert | 5.0-6.0 | 28 / 110 (25.5 %) | 82 (77) | 0 | 82 | 0 | 4.20 | 26 / 110 | 0.032 | 0 |
### Weitere Messwerte
| | Wert |
|---|---|
| lint-Verstoesse gesamt | 0 |
| Stellen im leichteren, die im schwereren Profil fehlen | 0 |
| Rechenzeit build_all je Set: Mittel / Median / Maximum | 364 ms / 331 ms / 948 ms |
| rosu-Ergebnisse erhalten | 110 Sets |
| Hold-Anteil der Vorlagen (Mittel / Median) | 19.5 % / 12.6 % |
| Sterne der Vorlagen (Easy/Normal/Hard/Insane/Expert/darueber oder unbekannt) | [1, 15, 25, 43, 23, 3] |

## Vorher / nachher (Zusammenfassung)

Vorher = Messung des Vorgaengers (Stand 095151c, feste Spec-Tabelle), nachher = diese Messung. "je Profil"
zaehlt jede erzeugte Diff unter ihrem Profil (wie bisher); "nach Band" ordnet sie wie die Menschen-Maps
nach ihren rosu-Sternen ein (fairer fuer die Dichte, weil gedeckelte Diffs sonst im falschen Band zaehlen).
Werte: Mensch / vorher / nachher je Profil / nachher nach Band.

| Kennzahl | Easy | Normal | Hard | Insane | Expert |
|---|---|---|---|---|---|
| Akkord-Zeilen | 18,3 / 0,0 / 18,8 / 21,5 % | 32,9 / 37,8 / 33,8 / 36,9 % | 36,9 / 40,9 / 38,0 / 40,1 % | 39,6 / 45,2 / 41,9 / 42,8 % | 41,0 / 50,0 / 44,6 / 42,9 % |
| 3er/4er-Akkorde | 0,1 / 0,0 / 0,0 / 0,4 % | 1,6 / 0,0 / 1,6 / 3,9 % | 5,2 / 0,0 / 5,2 / 6,9 % | 9,0 / 10,1 / 9,1 / 9,7 % | 10,6 / 12,6 / 10,5 / 10,3 % |
| Noten in Jacks (1/4) | 0,0 / 0,0 / 0,0 / 0,0 % | 0,6 / 0,0 / 0,0 / 1,5 % | 3,1 / 7,0 / 3,7 / 5,4 % | 7,1 / 13,3 / 7,9 / 10,0 % | 11,3 / 18,6 / 11,6 / 14,0 % |
| Hold-Anteil | 18,2 / 6,7 / 15,1 / 16,4 % | 18,7 / 4,3 / 13,9 / 17,4 % | 15,9 / 8,3 / 15,5 / 15,5 % | 14,0 / 7,2 / 14,5 / 11,4 % | 18,2 / 7,9 / 14,3 / 13,9 % |
| Noten/s Mittel | 3,81 / 2,88 / 3,35 / 3,45 | 6,93 / 6,15 / 5,90 / 6,76 | 10,07 / 8,46 / 8,70 / 9,58 | 13,26 / 10,41 / 10,51 / 12,70 | 16,06 / 12,16 / 11,98 / 15,55 |
| 4er-Muster in den Top 60 der Menschen | 42,5 / 43,6 / 49,9 / 38,8 % | 25,9 / 7,9 / 25,8 / 19,8 % | 20,9 / 6,6 / 17,2 / 14,8 % | 18,8 / 5,2 / 13,8 / 13,5 % | 22,4 / 4,2 / 11,3 / 12,5 % |

| Sterne im Band (rosu, 110 Sets) | Easy | Normal | Hard | Insane | Expert |
|---|---|---|---|---|---|
| vorher | 64,5 % | 65,5 % | 68,2 % | 51,8 % | 30,9 % |
| nachher | 90,9 % | 77,3 % | 70,0 % | 50,9 % | 25,5 % |
| nachher ohne Sets, deren Vorlage schon unter dem Band liegt | 100 / 109 | 85 / 109 | 77 / 91 | 56 / 68 | 28 / 33 |

Die Menschen-Statistik wurde neu gelernt (238 statt 228 Sets, 989 statt 949 Diffs); die Menschen-Werte
weichen darum um bis zu 0,5 Punkte vom alten Bericht ab.

## Bewertung (ehrlich)

Gemessen vs. geschlossen: alle Zahlen oben sind gemessen. Geschlossen (erreicht):

- lint = 0 Verstoesse in allen 550 erzeugten Diffs, Auswahl-Eigenschaft ohne Ausnahme, Hand-Balance 50 %.
- Akkord-Zeilen, 3er/4er-Akkorde und Jacks je Profil innerhalb +-25 % der Menschen (groesste Abweichung:
  Hard-Jacks +19 %, Expert-Akkorde +9 %). Ausnahme Normal-Jacks: Menschen 0,6 %, erzeugt 0 (die Regel
  Mindestabstand 1/2 in Normal verbietet 1/4-Jacks).
- Holds je Profil 14-16 % (vorher 4-8 %), nur auf gehaltenen Toenen; Hard und Insane auf Menschen-Niveau.
- Dichte bei gleichen Sternen (nach rosu-Band) 3-10 % unter den Menschen (vorher je Profil 10-25 %).
- Unit-Tests 93/93 gruen, darunter Wiederholung ueber Taktgrenzen: Normal und Hard 12 von 12 Takten gleich
  (vorher Hard 6 von 12; der alte Test verglich Akkord-Noten nach Reihenfolge statt als Menge und zaehlte
  gespiegelte Akkord-Takte darum als verschieden).
- Sterne-Trefferquote Easy 90,9 % (Ziel >= 90 %).

Nicht erreicht:

- **Sterne-Trefferquote** Normal 77,3 %, Hard 70,0 %, Insane 50,9 %, Expert 25,5 % (Ziel >= 90 %). Alle
  Fehltreffer liegen unter dem Band, alle bis auf einen (Easy) als `capped` gemeldet. Hard bis Expert: die
  Vorlage (schwerste Menschen-Diff) liegt meist selbst unter dem Band (19/42/77 Faelle). Normal: 25 Sets
  bleiben unter 2,1, weil die Obergrenzen der Menschen (1/4-Zeilen <= 15,9 %, Laeufe <= 7 Zeilen, keine
  Jacks) bei langsamen Songs nicht reichen.
- **4er-Muster >= 30 % je Band**: erreicht nur Easy (49,9 %); Normal 25,8 %, Hard 17,2 %, Insane 13,8 %,
  Expert 11,3 % (vorher 4-8 %). Die Menschen selbst liegen bei 19-26 %. Ein Parametersatz mit weniger
  Tonhoehen-Gewicht erreichte Normal 39 % / Hard 30 % / Insane 23 %, verletzte aber die Musik-Regel
  "Tonhoehe -> Spaltenrichtung" (Unit-Test rot); die Regel hat Vorrang. Akkord-Zeilen (40 %) liegen selten
  in den Top 60, das begrenzt Insane und Expert.
- **Holds** Easy -17 %, Normal -26 %, Expert -21 % gegen die Menschen: Holds nur, wo die Vorlage gehaltene
  Toene hat (Hold-Anteil der Vorlagen: Median 12,6 %).
- **Dichte je Profil** bleibt bei Insane/Expert 20-25 % unter den Menschen, weil gedeckelte Diffs aus zu
  leichten Vorlagen im Profil-Band mitzaehlen; bei gleichen Sternen (nach rosu-Band) sind es 3-10 %.
- **Seltene Teilung** unter dem Menschen-Wert genutzt: Normal 1/4-Zeilen 9,7 % (Mensch 12,7 %), Hard 1/8
  2,5 % (Mensch feiner als 1/4: 8,1 %; die Vorlage hat dort oft 1/6 oder 1/16, die Hard nicht nutzt).
- **Akkorde auf dem Schlag** haeufiger als bei Menschen (Hard 86 % gegen 70 %): 3er nur auf dem Schlag,
  2er in Easy/Normal nur auf dem Schlag.
