# AmChart: Notensetzer, Messung

OMEN Auto-Mapper 4K, Modul `scripts/automap/am_chart.gd` (Spec: `docs/automap/spec.md`, Abschnitt AmChart).
Stand 2026-11-13. Alle Zahlen gemessen mit

```
Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path .   --script res://tests/run_am_chart_tests.gd -- --measure <maps> 110 --learn
```

(ein Prozess, rund 60 s fuer 228 Sets / 949 4K-Diffs lesen, 110 Sets erzeugen, rosu einmal fuer alle).

## Aufbau

- `build(features, grid, profile, params)` wie Spec; `build_all(features, grid, params)` rechnet alle Profile
  in einem Durchgang (Ergaenzung zur Spec, gleiche Ergebnisse wie einzelne `build`-Aufrufe).
- `lint(notes, grid, profile)` prueft die Spielbarkeits-Tabelle der Spec (Teilung, Akkorde, Jacks,
  Hold+Note, Mindestabstand, Hand-Balance, Hold-Ende auf dem Gitter, 1/8-Folgen in Insane).
- Gitter: eigene Funktionen nach den Regeln von `AmGrid.snap/beat_pos` (AmGrid entsteht parallel).
- Muster aus `data/automap/patterns.json` (nur Statistik, keine Maps): je Sterne-Band Zeilen-Uebergaenge
  je Abstandsklasse (16x16), haeufige 4er/8er-Muster, Akkord-, 3er-Akkord-, Hold-Anteil, Holds je Zeile,
  Jack-Laengen, Kiai-Dichteverhaeltnis, Ausgleich der Sterne-Schaetzung.
- Musik: Tonhoehe -> Spaltenrichtung, feste Kick/Snare-Spalten je Abschnitt, Akzente (Taktanfang,
  Becken, mehrere Ebenen) -> Akkorde, gehaltene Toene -> Holds mit Ende auf dem Gitter, Pausen bleiben
  leer, Dichte folgt der Intensitaet, fuehrende Ebene (`lead`) zaehlt voll, die anderen als Stuetze.
- Wiederholung: Takte mit gleicher Musik uebernehmen Auswahl, Akkorde und Holds ihres ersten Vorkommens,
  dann dieselben Spalten (gleich oder gespiegelt; passt es wegen Jack/Abstand nicht, Zeile fuer Zeile).
- Auswahl-Eigenschaft: Kette Expert -> Easy, jedes leichtere Profil waehlt nur aus Stellen des schwereren.
- Sterne: `estimate_stars` ist die osu!mania-Strain-Formel (wie rosu-pp); Nachregelung der Dichte per
  Bisektion auf die Bandmitte. Abgleich: mittlerer Fehler 0,04 Sterne gegen rosu ueber 949 Menschen-Diffs,
  0,025-0,035 bei den erzeugten Maps. Darum kein rosu-Aufruf im Setzer noetig.

## Eingabe der Messung

Echte features/grid gibt es noch nicht (AmFeatures/AmGrid entstehen parallel). Gemessen wird darum mit
Eingaben aus Menschen-Maps: je Set die 4K-Diff mit den meisten Noten liefert Notenzeiten als Ereignisse,
mittlere Spalte als Tonhoehe, Holds als gehaltene Toene, Akkorde als Akzente, Kiai als Abschnitt; die
rote Linie ist das Gitter. Diese Vorlage begrenzt die Sterne nach oben: was sie nicht hergibt, kann das
erzeugte Expert nicht erreichen (Spalte "Vorlage schon unter Band").

## Gemessen

### Sterne-Schaetzung gegen rosu-pp (Menschen-Maps, n = 969)
| | Wert |
|---|---|
| mittlerer Fehler roh | 0.039 |
| Ausgleich rosu = a * est + b | a = 0.9918, b = -0.0133 |
| mittlerer Fehler nach Ausgleich | 0.042 |
patterns.json geschrieben (5 Baender)
Erzeugt: 110 Sets, 58.0 s gesamt
### Vergleich erzeugt gegen Mensch je Sterne-Band (110 Sets erzeugt; Mensch: alle 4K-Diffs im Band)
| Kennzahl | Easy Mensch | Easy erzeugt | Normal Mensch | Normal erzeugt | Hard Mensch | Hard erzeugt | Insane Mensch | Insane erzeugt | Expert Mensch | Expert erzeugt |
|---|---|---|---|---|---|---|---|---|---|---|
| Maps | 219 | 110 | 243 | 110 | 232 | 110 | 178 | 110 | 68 | 110 |
| gleiche Spalte in Folge (Einzelnoten) | 4.7 % | 6.0 % | 4.6 % | 6.2 % | 4.1 % | 4.8 % | 4.6 % | 5.3 % | 3.6 % | 4.5 % |
| Nachbarspalte | 48.0 % | 47.6 % | 51.6 % | 47.8 % | 55.6 % | 55.3 % | 55.7 % | 55.5 % | 55.7 % | 55.5 % |
| weiter Sprung | 47.3 % | 46.4 % | 43.8 % | 45.9 % | 40.3 % | 39.9 % | 39.7 % | 39.2 % | 40.8 % | 40.0 % |
| Akkord-Zeilen | 18.4 % | 0.0 % | 33.3 % | 37.8 % | 37.1 % | 40.9 % | 39.6 % | 45.2 % | 41.0 % | 50.0 % |
| 3er/4er-Akkorde | 0.1 % | 0.0 % | 1.6 % | 0.0 % | 5.2 % | 0.0 % | 9.1 % | 10.1 % | 10.7 % | 12.6 % |
| Noten in Jacks (1/4) | 0.0 % | 0.0 % | 0.6 % | 0.0 % | 3.2 % | 7.0 % | 7.2 % | 13.3 % | 11.5 % | 18.6 % |
| Hold-Anteil | 18.2 % | 6.7 % | 18.8 % | 4.3 % | 16.1 % | 8.3 % | 14.1 % | 7.2 % | 18.5 % | 7.9 % |
| Hold-Laenge (Schlaege) | 1.21 | 1.34 | 0.82 | 1.53 | 0.69 | 1.04 | 0.62 | 1.08 | 0.54 | 0.96 |
| Noten/s Mittel | 3.81 | 2.88 | 6.94 | 6.15 | 10.08 | 8.46 | 13.26 | 10.41 | 16.05 | 12.16 |
| Noten/s Spitze | 7.25 | 5.97 | 12.34 | 9.54 | 17.56 | 15.60 | 22.97 | 19.38 | 27.60 | 22.18 |
| linke Hand | 50.0 % | 50.2 % | 49.9 % | 49.9 % | 50.0 % | 50.1 % | 50.0 % | 50.0 % | 49.9 % | 49.9 % |
| Abstand 1/8 und feiner | 0.2 % | 0.0 % | 0.6 % | 0.0 % | 2.2 % | 0.0 % | 8.7 % | 6.4 % | 12.5 % | 9.8 % |
| Abstand 1/4 | 4.6 % | 0.0 % | 21.0 % | 0.0 % | 43.6 % | 35.2 % | 52.9 % | 43.2 % | 57.2 % | 47.5 % |
| Abstand 1/2 | 39.5 % | 27.8 % | 58.2 % | 81.7 % | 45.9 % | 55.2 % | 33.4 % | 42.4 % | 26.6 % | 36.6 % |
| Aehnlichkeit der Zeilen-Uebergaenge (0..1) | 1.00 | 0.66 | 1.00 | 0.76 | 1.00 | 0.77 | 1.00 | 0.80 | 1.00 | 0.73 |
| Anteil 4er-Muster in den Top 60 der Menschen | 42.4 % | 43.6 % | 25.5 % | 7.9 % | 20.8 % | 6.6 % | 18.8 % | 5.2 % | 22.1 % | 4.2 % |
### Sterne-Trefferquote je Profil (110 Sets)
| Profil | Band | rosu im Band | unter Band (davon Vorlage schon unter Band) | ueber Band | ausserhalb, als capped gemeldet | ausserhalb, nicht gemeldet | rosu Median | Schaetzung im Band | Fehler Schaetzung gegen rosu (Mittel) | lint-Verstoesse |
|---|---|---|---|---|---|---|---|---|---|---|
| Easy | 1.3-1.9 | 71 / 110 (64.5 %) | 39 (1) | 0 | 39 | 0 | 1.38 | 68 / 110 | 0.025 | 0 |
| Normal | 2.1-2.8 | 72 / 110 (65.5 %) | 38 (1) | 0 | 38 | 0 | 2.27 | 70 / 110 | 0.027 | 0 |
| Hard | 3.0-3.8 | 75 / 110 (68.2 %) | 35 (21) | 0 | 35 | 0 | 3.34 | 74 / 110 | 0.032 | 0 |
| Insane | 4.0-4.8 | 57 / 110 (51.8 %) | 53 (43) | 0 | 53 | 0 | 4.14 | 55 / 110 | 0.035 | 0 |
| Expert | 5.0-6.0 | 34 / 110 (30.9 %) | 76 (71) | 0 | 76 | 0 | 4.49 | 34 / 110 | 0.035 | 0 |
### Weitere Messwerte
| | Wert |
|---|---|
| lint-Verstoesse gesamt | 0 |
| Stellen im leichteren, die im schwereren Profil fehlen | 0 |
| Rechenzeit build_all je Set: Mittel / Median / Maximum | 282 ms / 263 ms / 906 ms |
| rosu-Ergebnisse erhalten | 110 Sets |
| Sterne der Vorlagen (Easy/Normal/Hard/Insane/Expert/darueber oder unbekannt) | [1, 20, 18, 43, 28, 0] |
Gesamt: 59.0 s

## Bewertung (ehrlich)

Gemessen vs. geschlossen: Alle Zahlen oben sind gemessen. Geschlossen (erreicht) sind nur: lint = 0
Verstoesse in allen 550 erzeugten Diffs, Auswahl-Eigenschaft ohne Ausnahme, Sterne-Schaetzung trifft rosu
(Fehler <= 0,04), Hand-Balance 50 %, Spaltenbewegungen (gleiche Spalte / Nachbar / Sprung) innerhalb von
1-3 Prozentpunkten der Menschen, Rechenzeit < 1 s je Set fuer alle Profile.

Nicht erreicht:

- **Sterne-Trefferquote** (Ziel >= 90 %): Easy 64,5 %, Normal 65,5 %, Hard 68,2 %, Insane 51,8 %,
  Expert 30,9 %. Alle Fehltreffer liegen unter dem Band und sind als `capped` gemeldet (0 ungemeldet).
  Ohne die Faelle, in denen schon die Vorlage unter dem Band liegt: Hard 75/89, Insane 57/67, Expert
  34/39. Easy und Normal scheitern an der Spec selbst: Easy nur 1/1 (selten 1/2, ohne Akkorde) und Normal
  nur 1/2 reichen bei langsamen Songs nicht fuer 1,3 bzw. 2,1 Sterne. Menschen-Maps in diesen Baendern
  nutzen 1/2 (Easy 40 %) bzw. 1/4 (Normal 21 %) und Akkorde in Easy (18 %). Loesung braucht eine
  Entscheidung: Band oder Teilungsregel lockern.
- **Akkorde und Jacks zu haeufig** in Insane/Expert (Akkord-Zeilen 45/50 % gegen 40/41 %, Jack-Noten
  13/19 % gegen 7/12 %): Die Vorlage hat Zeilen, die Hard/Insane wegen der Teilungsregel nicht nutzen
  darf; die Nachregelung gleicht mit Akkorden aus (gedeckelt auf +30 %). Dazu kommen Jacks aus
  aufeinanderfolgenden Akkorden und aus wiederholten Motiven.
- **Holds zu selten** (7-8 % gegen 14-19 %; Normal 4 %): Holds entstehen nur auf gehaltenen Toenen der
  Eingabe, Easy/Normal lassen waehrend eines Holds keine bzw. kaum andere Noten zu, darum wenige.
- **4er-Muster**: nur 4-8 % der erzeugten 4er-Folgen (ab Normal) gehoeren zu den 60 haeufigsten der
  Menschen (Menschen: 19-26 %). Die Uebergaenge je Zeile sind menschennah (Aehnlichkeit 0,66-0,80),
  laengere Figuren (Treppen, Triller) entstehen noch zu selten.
- **Dichte**: erzeugte Noten/s liegen 10-25 % unter den Menschen-Maps gleicher Stufe (gleiche Sterne
  ueber mehr Akkorde statt mehr Noten).
- **Unit-Tests**: 2 offen (siehe `tests/run_am_chart_tests.gd`): Hard setzt wiederholte Takte nur in
  6 von 12 Faellen gleich (Normal 10 von 12), Normal-Sterne des synthetischen Songs 2,09 knapp unter 2,1.
