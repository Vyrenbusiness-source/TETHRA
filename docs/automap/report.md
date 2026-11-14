# OMEN Auto-Mapper 4K: Prüfstand-Bericht

Erzeugt von `tools/automap_bench.gd` am 2026-11-13. Nicht von Hand ändern; neu erzeugen (Befehle unten).

Der Bericht bewertet gegen die Ziel-Tabelle aus `docs/automap/spec.md`. Maßgeblich ist die **Prüf-Menge** (30 % der Maps, wird nie zum Abstimmen benutzt). „nicht messbar“ heißt: Für diese Zeile gibt es keinen Wert; sie gilt nicht als erreicht.

## Mapper „alt“: alter Mapper (`AudioMapper`, Orbit) über Adapter

- Gemessen: 249 Sets (Prüf-Menge 77, Abstimm-Menge 172); 0 ohne rote Linie übersprungen; Erzeugung fehlgeschlagen bei 0 (Prüf) / 0 (Abstimm).
- Laufzeit: 243 s für 254 Sets
- Maps-Ordner: 254 .osz
- Neue Module: fehlen noch (grid, features, chart, mapper), deshalb Ausgangswerte des alten Mappers
- Nicht gemessen: 5 Sets nicht lesbar oder ohne Diff mit Noten, zählen in keiner Kennzahl: mirror_2538892 (Konnte .osz nicht oeffnen (Fehler 1)), mirror_2556039 (Konnte .osz nicht oeffnen (Fehler 1)), mirror_2597846 (Konnte .osz nicht oeffnen (Fehler 1)), mirror_2598366 (Konnte .osz nicht oeffnen (Fehler 1)), mirror_2600955 (Konnte .osz nicht oeffnen (Fehler 1))
- Sterne: nicht berechnet (Mapper ohne Spalten)
- Weg: Stufen einzeln (decode, Gitter, Features, Noten)

### Ziel-Tabelle, Prüf-Menge

| Bereich | Kennzahl | Ziel | Ist (Prüf-Menge) | erreicht | Ist (Abstimm-Menge) |
|---|---|---|---|---|---|
| Takt | Tempo exakt (±0,5 %), Maps mit einem Tempo | ≥ 95 % | 67.9 % (n=56) | **nein** | 54.1 % (n=146) |
| Takt | Tempo exakt oder gemeldete Alternative trifft | ≥ 99 % | 67.9 % (n=56) | **nein** | 54.1 % (n=146) |
| Takt | Offset-Fehler, Median / 95. Perzentil (nur richtiges Tempo) | ≤ 4 ms / ≤ 12 ms | 7.5 ms / 121.1 ms (n=38) | **nein** | 4.2 ms / 127.7 ms (n=79) |
| Takt | Drift über den Song, 95. Perzentil (Median / Maximum / Anteil ≤ 10 ms) | ≤ 10 ms | 4.5 ms (1.2 ms / 5.2 ms / 100.0 %; n=38) | ja | 11.9 ms (1.4 ms / 54.8 ms / 92.4 %; n=79) |
| Takt | Tempowechsel: Grenzen ±1 Schlag und Tempo je Segment | ≥ 80 % | 0.0 % (n=6; 15 Maps mit Effekt-Linien nicht gewertet) | **nein** | 0.0 % (n=15; 11 Maps mit Effekt-Linien nicht gewertet) |
| Takt | Taktanfang (Downbeat) stimmt | ≥ 85 % | 44.7 % (n=38) | **nein** | 48.1 % (n=79) |
| Noten | erzeugte Noten auf Menschen-Note (±15 ms), Hard | ≥ 85 % | 70.3 % (n=62, Notenzahl erzeugt/Mensch 0.48) | **nein** | 70.6 % (n=144, Notenzahl erzeugt/Mensch 0.52) |
| Noten | Menschen-Noten getroffen (±15 ms), Hard | ≥ 75 % | 35.0 % (n=62) | **nein** | 37.8 % (n=144) |
| Noten | Korrelation der Dichtekurve (2-s-Fenster), alle Profile | ≥ 0,8 | 0.249 (n=174 Paare) | **nein** | 0.274 (n=410 Paare) |
| Holds | erzeugte Holds überlappen Holds der Map (Maps ≥ 10 % Holds) | ≥ 60 % | nicht messbar, weil dieser Mapper keine Holds erzeugt | **nein** (fehlt) | nicht messbar, weil dieser Mapper keine Holds erzeugt |
| Kiai | Überlappung der Kiai-Abschnitte (IoU) | ≥ 0,6 | nicht messbar, weil dieser Mapper kein Kiai erzeugt | **nein** (fehlt) | nicht messbar, weil dieser Mapper kein Kiai erzeugt |
| Stufen | Sterne im Band, schlechtestes Profil | ≥ 90 % | nicht messbar, weil dieser Mapper keine 4K-Map erzeugt (Orbit ohne Spalten; nur 3 Stufen) | **nein** (fehlt) | nicht messbar, weil dieser Mapper keine 4K-Map erzeugt (Orbit ohne Spalten; nur 3 Stufen) |
| Spielbarkeit | Regelverletzungen (AmChart.lint), Summe | 0 | nicht messbar, weil die Noten keine Spalten haben | **nein** (fehlt) | nicht messbar, weil die Noten keine Spalten haben |
| Dauer | ganzer Ablauf je Song, auf 4 min umgerechnet, 95. Perzentil (Maximum) | ≤ 15 s | 2.1 s (2.4 s; Median roh 0.9 s; n=77) | ja | 2.1 s (3.6 s; Median roh 0.9 s; n=172) |

**2 von 14 Zielen erreicht.**

Zusatzwerte (Prüf-Menge): systematischer Versatz (Median mit Vorzeichen, + = erzeugt zu spät) -1.8 ms; Noten auf dem eigenen Gitter 100.0 %.

### Noten je Profil, Prüf-Menge

| Profil | Paare | auf Menschen-Note | Menschen-Noten getroffen | Dichte-Korrelation | Notenzahl erzeugt/Mensch | Sterne im Band | Hinweis |
|---|---|---|---|---|---|---|---|
| Easy | 52 | 43.1 % | 16.1 % | 0.208 | 0.35 | – |  |
| Normal | 60 | 56.3 % | 21.3 % | 0.248 | 0.37 | – |  |
| Hard | 62 | 70.3 % | 35.0 % | 0.286 | 0.48 | – |  |
| Insane | 0 | – | – | – | – | – | Profil fehlt in diesem Mapper |
| Expert | 0 | – | – | – | – | – | Profil fehlt in diesem Mapper |

### Schlechteste 20 Songs je Kennzahl

(P) = Prüf-Menge, (A) = Abstimm-Menge. Ursache = aus den Messwerten abgeleitete Einordnung, keine Hörprüfung.

### Tempo falsch (Maps mit einem Tempo)

| Song | BPM Map | BPM erzeugt | Ursache |
|---|---|---|---|
| mirror_2438724 (A) | 390.0 | 113.21 | daneben: erzeugt 113.21 BPM, Map 390.00 BPM |
| mirror_2506453 (A) | 75.0 | 150.02 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_476221 (A) | 195.0 | 97.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2555699 (A) | 166.0 | 83.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2527829 (A) | 180.0 | 90.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2351212 (A) | 200.0 | 100.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_187154 (A) | 200.0 | 100.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2327005 (A) | 202.0 | 101.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2318291 (P) | 270.0 | 135.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2521385 (A) | 178.0 | 89.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2511666 (A) | 185.0 | 92.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2388455 (A) | 191.0 | 95.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2306554 (A) | 195.0 | 97.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2403016 (A) | 199.0 | 99.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2264736 (A) | 200.0 | 100.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2449429 (P) | 213.0 | 106.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2607616 (A) | 204.82 | 102.41 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2096660 (A) | 185.0 | 92.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_1746870 (A) | 215.0 | 107.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2540169 (P) | 230.0 | 115.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |

### Offset-Fehler

| Song | Fehler ms (+ = zu spät) | Ursache |
|---|---|---|
| mirror_2295373 (P) | +162.2 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2079518 (A) | -162.1 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2425501 (A) | -158.1 | Viertelschlag versetzt |
| mirror_2534361 (A) | -144.3 | Viertelschlag versetzt |
| 2246587 Mitsukiyo - Mikansei Romantic (feat. kotono) (A) | +139.5 | Viertelschlag versetzt |
| mirror_2639744 (A) | -126.4 | Viertelschlag versetzt |
| mirror_2269020 (P) | -123.5 | Viertelschlag versetzt |
| mirror_2537768 (P) | +120.7 | Viertelschlag versetzt |
| mirror_2398569 (A) | -113.7 | Viertelschlag versetzt |
| mirror_2485116 (A) | +112.9 | Viertelschlag versetzt |
| mirror_2490158 (P) | -112.6 | Viertelschlag versetzt |
| mirror_2338601 (P) | -110.0 | Viertelschlag versetzt |
| mirror_126752 (A) | -108.3 | Viertelschlag versetzt |
| mirror_105186 (A) | -105.8 | Viertelschlag versetzt |
| 1614100 FROL - BEAKER (roop remix) (P) | -103.9 | Viertelschlag versetzt |
| mirror_2551467 (A) | -102.8 | Viertelschlag versetzt |
| mirror_2555988 (A) | -101.9 | Viertelschlag versetzt |
| mirror_2553092 (P) | -101.4 | Viertelschlag versetzt |
| 2032982 MYUKKE. - Anti Safety Zone (A) | -97.8 | Viertelschlag versetzt |
| mirror_2483415 (A) | -97.5 | Viertelschlag versetzt |

### Drift

| Song | Drift ms | Ursache |
|---|---|---|
| mirror_2426813 (A) | -54.8 | Tempo um 0.0831 % daneben (erzeugt 130.108, Map 130.000 BPM) |
| mirror_2017220 (A) | -43.8 | Tempo um 0.0103 % daneben (erzeugt 145.015, Map 145.000 BPM) |
| mirror_2514525 (A) | +19.8 | Tempo um -0.0213 % daneben (erzeugt 136.171, Map 136.200 BPM) |
| mirror_2540935 (A) | -16.8 | Tempo um 0.0093 % daneben (erzeugt 107.010, Map 107.000 BPM) |
| mirror_2560261 (A) | -11.3 | Tempo um 0.0135 % daneben (erzeugt 178.024, Map 178.000 BPM) |
| mirror_2555143 (A) | +10.2 | Tempo um -0.0076 % daneben (erzeugt 171.537, Map 171.550 BPM) |
| mirror_157896 (A) | +8.8 | Tempo um -0.0071 % daneben (erzeugt 139.990, Map 140.000 BPM) |
| mirror_126752 (A) | +6.3 | Tempo um -0.0062 % daneben (erzeugt 129.992, Map 130.000 BPM) |
| mirror_2119120 (A) | -6.2 | Tempo um 0.0158 % daneben (erzeugt 95.015, Map 95.000 BPM) |
| mirror_2288732 (A) | +6.2 | Tempo um -0.0061 % daneben (erzeugt 179.989, Map 180.000 BPM) |
| mirror_2515013 (A) | +6.1 | Tempo um -0.0065 % daneben (erzeugt 122.132, Map 122.140 BPM) |
| mirror_2417924 (A) | -5.8 | Tempo um 0.0054 % daneben (erzeugt 168.009, Map 168.000 BPM) |
| mirror_2545208 (A) | +5.7 | Tempo um -0.0038 % daneben (erzeugt 103.996, Map 104.000 BPM) |
| 2134137 Akiri feat. InabaYap - Tonight We Fly (A) | -5.3 | Tempo um 0.0037 % daneben (erzeugt 161.006, Map 161.000 BPM) |
| mirror_2490158 (P) | -5.2 | Tempo um 0.0059 % daneben (erzeugt 135.008, Map 135.000 BPM) |
| mirror_159068 (A) | -5.0 | Tempo um 0.0034 % daneben (erzeugt 176.006, Map 176.000 BPM) |
| 2355814 NANAOAKARI - Ashita no Watashi ni Sachi Are (P) | +4.8 | Tempo um -0.0023 % daneben (erzeugt 131.997, Map 132.000 BPM) |
| mirror_2496763 (A) | -4.8 | Tempo um 0.0054 % daneben (erzeugt 184.010, Map 184.000 BPM) |
| mirror_2493152 (P) | +4.5 | Tempo um -0.0046 % daneben (erzeugt 173.992, Map 174.000 BPM) |
| mirror_2436239 (A) | -4.4 | Tempo um 0.0040 % daneben (erzeugt 174.007, Map 174.000 BPM) |

### Tempowechsel nicht getroffen

| Song | Segmente Map | Segmente erzeugt | Ursache |
|---|---|---|---|
| mirror_332623 (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 3 falsch (Map 278.00 BPM, erzeugt 138.95) |
| mirror_2559592 (P) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 3 falsch (Map 185.00 BPM, erzeugt 92.49) |
| mirror_2555375 (A) | 10 | 1 | kein Tempowechsel erkannt; Tempo in Segment 10 falsch (Map 160.00 BPM, erzeugt 140.33) |
| mirror_2528018 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 210.00 BPM, erzeugt 105.00) |
| mirror_2511692 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 186.70 BPM, erzeugt 93.33) |
| mirror_1178589 (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 3 falsch (Map 192.00 BPM, erzeugt 143.97) |
| 347453 Igorrr & Ruby My Dear - Figue Folle (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 3 falsch (Map 188.00 BPM, erzeugt 94.00) |
| 315435 UNDEAD CORPORATION - The Empress scream off ver (P) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 270.00 BPM, erzeugt 135.14) |
| 1787141 Marmalade butcher - Immortality Math Club (A) | 12 | 1 | kein Tempowechsel erkannt; Tempo in Segment 12 falsch (Map 210.00 BPM, erzeugt 134.67) |
| mirror_1294997 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 77.00 BPM, erzeugt 154.01) |
| 2298540 Omerta - Charade (feat. Vincente Void _ Hash Gordon) (A) | 8 | 1 | kein Tempowechsel erkannt; Tempo in Segment 8 falsch (Map 120.00 BPM, erzeugt 179.96) |
| mirror_2528075 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 134.00 BPM, erzeugt 131.94) |
| mirror_2643833 (P) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 77.50 BPM, erzeugt 165.00) |
| mirror_2563805 (P) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 168.00 BPM, erzeugt 180.01) |
| mirror_2576239 (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 280.00 BPM, erzeugt 140.00) |
| mirror_2584545 (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 162.00 BPM, erzeugt 160.00) |
| mirror_2198573 (A) | 3 | 1 | kein Tempowechsel erkannt; Grenze bei 80159 ms fehlt |
| mirror_2541848 (P) | 4 | 1 | kein Tempowechsel erkannt; Grenze bei 12073 ms fehlt |
| 2219350 Toromaru - Uncharted Sky (A) | 14 | 1 | kein Tempowechsel erkannt; Grenze bei 13709 ms fehlt |
| 2155333 pan - Pastel Sprinkles (A) | 2 | 1 | kein Tempowechsel erkannt; Grenze bei 108608 ms fehlt |

### Taktanfang falsch

| Song | Ursache |
|---|---|
| mirror_2295373 (P) | um -1 Schlag/Schläge verschoben |
| mirror_2639744 (A) | um 1 Schlag/Schläge verschoben |
| mirror_2269020 (P) | um 1 Schlag/Schläge verschoben |
| mirror_2537768 (P) | um -1 Schlag/Schläge verschoben |
| mirror_2398569 (A) | um 1 Schlag/Schläge verschoben |
| mirror_2485116 (A) | um -2 Schlag/Schläge verschoben |
| 1614100 FROL - BEAKER (roop remix) (P) | um -1 Schlag/Schläge verschoben |
| mirror_2555988 (A) | um 1 Schlag/Schläge verschoben |
| 2032982 MYUKKE. - Anti Safety Zone (A) | um 1 Schlag/Schläge verschoben |
| mirror_2483415 (A) | um -1 Schlag/Schläge verschoben |
| mirror_2468221 (P) | um 1 Schlag/Schläge verschoben |
| mirror_200552 (A) | um -1 Schlag/Schläge verschoben |
| mirror_2563643 (A) | um -1 Schlag/Schläge verschoben |
| mirror_176446 (A) | um 1 Schlag/Schläge verschoben |
| mirror_2417924 (A) | um 1 Schlag/Schläge verschoben |
| mirror_2407955 (A) | um -1 Schlag/Schläge verschoben |
| mirror_2513755 (P) | um 1 Schlag/Schläge verschoben |
| mirror_2533221 (P) | um -1 Schlag/Schläge verschoben |
| mirror_2493152 (P) | um 1 Schlag/Schläge verschoben |
| 2375072 Lime - Aurora (A) | um -1 Schlag/Schläge verschoben |

### Noten: erzeugte Noten ohne Menschen-Note (Hard)

| Song | Anteil auf Menschen-Note | Menschen-Diff | Ursache |
|---|---|---|---|
| mirror_2096660 (A) | 0.0 % | Revv's Hard | Tempo falsch (x0.500) |
| mirror_2426813 (A) | 9.2 % | Insane | Versatz +37 ms |
| mirror_2523688 (P) | 13.8 % | Insane | Tempo falsch (x1.371) |
| 309328 xi - Hesperides (A) | 14.7 % | Zan's Hard | Tempo falsch (x0.762) |
| mirror_2552898 (A) | 17.3 % | Collab Insane | Tempo falsch (x1.531) |
| mirror_2539716 (A) | 17.5 % | Journey | Tempo falsch (x1.189) |
| mirror_2555375 (A) | 18.7 % | insane | Tempowechsel nicht getroffen |
| mirror_240415 (P) | 20.1 % | puxtu's HD | Map mit Effekt-Linien |
| mirror_2488299 (A) | 21.7 % | HARD JUMP!! | Tempo falsch (x0.756) |
| mirror_2559688 (A) | 21.8 % | Falling Up | Map mit Effekt-Linien |
| mirror_2422509 (A) | 21.9 % | hard | Tempo falsch (x1.468) |
| mirror_2504508 (A) | 22.2 % | ~=H / Illusions=~ | Tempo falsch (x0.674) |
| mirror_2378766 (A) | 22.4 % | hard... | Tempo falsch (x0.657) |
| 362395 sweet ARMS - Installation (P) | 23.1 % | Emperor of Time | Tempo falsch (x0.759) |
| 2081438 Hino Isuka - Dreamin_ attraction__ (A) | 23.6 % | Present!! | Tempo falsch (x0.665) |
| mirror_2536648 (A) | 25.4 % | alone | Tempo falsch (x1.372) |
| 315435 UNDEAD CORPORATION - The Empress scream off ver (P) | 25.5 % | MX | Tempowechsel nicht getroffen |
| mirror_2511692 (A) | 26.7 % | Maiiy's Insane | Tempowechsel nicht getroffen |
| mirror_2491936 (A) | 27.0 % | fall into the sky | Tempo falsch (x1.373) |
| mirror_2545184 (P) | 29.0 % | INSANE | Tempo falsch (x0.750) |

### Noten: Menschen-Noten nicht getroffen (Hard)

| Song | Anteil getroffen | Menschen-Diff | Ursache |
|---|---|---|---|
| mirror_2096660 (A) | 0.0 % | Revv's Hard | Tempo falsch (x0.500) |
| mirror_2426813 (A) | 3.7 % | Insane | Versatz +37 ms |
| mirror_2523688 (P) | 7.0 % | Insane | Tempo falsch (x1.371) |
| mirror_2555375 (A) | 8.5 % | insane | Tempowechsel nicht getroffen |
| 2081438 Hino Isuka - Dreamin_ attraction__ (A) | 8.5 % | Present!! | Tempo falsch (x0.665) |
| mirror_2552898 (A) | 8.5 % | Collab Insane | Tempo falsch (x1.531) |
| 309328 xi - Hesperides (A) | 8.5 % | Zan's Hard | Tempo falsch (x0.762) |
| mirror_2504508 (A) | 9.4 % | ~=H / Illusions=~ | Tempo falsch (x0.674) |
| mirror_2378766 (A) | 9.6 % | hard... | Tempo falsch (x0.657) |
| mirror_2536648 (A) | 9.6 % | alone | Tempo falsch (x1.372) |
| 315435 UNDEAD CORPORATION - The Empress scream off ver (P) | 9.6 % | MX | Tempowechsel nicht getroffen |
| mirror_2559688 (A) | 9.6 % | Falling Up | Map mit Effekt-Linien |
| mirror_2491936 (A) | 9.6 % | fall into the sky | Tempo falsch (x1.373) |
| mirror_2438724 (A) | 9.8 % | Hyper | Tempo falsch (x0.290) |
| mirror_240415 (P) | 10.1 % | puxtu's HD | Map mit Effekt-Linien |
| 362395 sweet ARMS - Installation (P) | 10.3 % | Emperor of Time | Tempo falsch (x0.759) |
| mirror_2488299 (A) | 10.4 % | HARD JUMP!! | Tempo falsch (x0.756) |
| mirror_2539716 (A) | 11.0 % | Journey | Tempo falsch (x1.189) |
| mirror_2422509 (A) | 11.3 % | hard | Tempo falsch (x1.468) |
| mirror_2616511 (P) | 11.5 % | Insane | Map mit Effekt-Linien |

### Dichtekurve

| Song | Profil | Korrelation | Ursache |
|---|---|---|---|
| mirror_2240934 (P) | Hard | -0.467 | Tempo falsch (x1.500) |
| mirror_2563907 (P) | Hard | -0.277 | Tempo falsch (x0.750) |
| mirror_2545191 (A) | Easy | -0.253 | Tempo falsch (x0.500) |
| mirror_2610887 (P) | Normal | -0.252 | Map mit Effekt-Linien |
| 2280366 rejection - Calling (osu_ edit) (P) | Normal | -0.236 | Notenzahl erzeugt/Mensch = 0.31 |
| mirror_2563805 (P) | Hard | -0.224 | Tempowechsel nicht getroffen |
| mirror_283841 (A) | Easy | -0.213 | Tempo falsch (x0.500) |
| mirror_2641034 (A) | Easy | -0.208 | Notenzahl erzeugt/Mensch = 0.26 |
| mirror_2540935 (A) | Normal | -0.204 | Drift -17 ms |
| mirror_476691 (A) | Normal | -0.179 | Notenzahl erzeugt/Mensch = 0.45 |
| mirror_2506453 (A) | Normal | -0.174 | Tempo falsch (x2.000) |
| mirror_126752 (A) | Easy | -0.162 | Versatz -108 ms |
| mirror_2434745 (A) | Easy | -0.161 | Tempo falsch (x0.500) |
| mirror_2541848 (P) | Normal | -0.148 | Tempowechsel nicht getroffen |
| mirror_2489537 (A) | Normal | -0.142 | Tempo falsch (x0.500) |
| mirror_2240934 (P) | Normal | -0.14 | Tempo falsch (x1.500) |
| mirror_2198573 (A) | Normal | -0.14 | Tempowechsel nicht getroffen |
| 2310809 Trina Lydia - TETRATONE ALTiSSiMO (P) | Hard | -0.138 | Versatz -77 ms |
| mirror_2407955 (A) | Normal | -0.138 | Versatz +90 ms |
| mirror_2458045 (A) | Easy | -0.127 | Notenzahl erzeugt/Mensch = 0.49 |

### Holds

Entfällt: dieser Mapper erzeugt keine Holds.

### Kiai

Entfällt: dieser Mapper erzeugt kein Kiai.

### Sterne, Regelverletzungen

Entfällt: dieser Mapper erzeugt keine 4K-Map (keine Spalten).

### Dauer

| Song | s auf 4 min | s roh | Songlänge s | Ursache |
|---|---|---|---|---|
| mirror_283841 (A) | 3.6 | 1.5 | 101 | größter Anteil: decode (0.9 s) |
| mirror_2561773 (P) | 2.4 | 0.4 | 38 | größter Anteil: grid (0.3 s) |
| mirror_2294669 (P) | 2.3 | 0.6 | 63 | größter Anteil: grid (0.5 s) |
| mirror_2079518 (A) | 2.3 | 0.7 | 68 | größter Anteil: grid (0.5 s) |
| mirror_2564470 (A) | 2.3 | 0.7 | 79 | größter Anteil: grid (0.6 s) |
| mirror_2553140 (A) | 2.3 | 0.6 | 59 | größter Anteil: grid (0.4 s) |
| mirror_2422509 (A) | 2.2 | 0.4 | 41 | größter Anteil: grid (0.3 s) |
| mirror_2559655 (A) | 2.2 | 0.5 | 57 | größter Anteil: grid (0.4 s) |
| mirror_2563805 (P) | 2.2 | 0.7 | 80 | größter Anteil: grid (0.6 s) |
| mirror_2551467 (A) | 2.2 | 0.5 | 55 | größter Anteil: grid (0.4 s) |
| mirror_2560261 (A) | 2.1 | 0.8 | 93 | größter Anteil: grid (0.7 s) |
| mirror_105186 (A) | 2.1 | 0.4 | 43 | größter Anteil: grid (0.3 s) |
| mirror_2545184 (P) | 2.1 | 0.7 | 85 | größter Anteil: grid (0.6 s) |
| mirror_2516512 (A) | 2.1 | 0.5 | 63 | größter Anteil: grid (0.4 s) |
| mirror_2542664 (P) | 2.1 | 0.8 | 90 | größter Anteil: grid (0.6 s) |
| mirror_2559426 (A) | 2.1 | 0.4 | 41 | größter Anteil: grid (0.2 s) |
| mirror_2496763 (A) | 2.0 | 0.8 | 90 | größter Anteil: grid (0.6 s) |
| mirror_274111 (P) | 2.0 | 0.9 | 107 | größter Anteil: grid (0.8 s) |
| mirror_2506744 (P) | 2.0 | 0.3 | 34 | größter Anteil: grid (0.2 s) |
| mirror_2039039 (P) | 2.0 | 0.7 | 91 | größter Anteil: grid (0.6 s) |

## Letzte Abstimmung (`tools/automap_tune.gd`)

- Stand: 2026-11-13T21:55:01, Mapper „alt“, 14 Songs Abstimm-Menge, 8 Songs Prüf-Menge, 9 Auswertungen, 23 s.
- Zielgröße (0..1, 1 = alle Ziele erreicht; ohne Sterne und Dauer): Abstimm-Menge 0.2613 -> 0.2613, **Prüf-Menge 0.4292 -> 0.4292**.
- Durchgang 1, post.offset_shift_ms: 0.0 -> 0.0 (Zielgröße 0.2613)

| Kennzahl (Prüf-Menge, nur die geladenen Songs) | Ziel | vorher | nachher | erreicht nachher |
|---|---|---|---|---|
| Tempo exakt (±0,5 %), Maps mit einem Tempo | ≥ 95 % | 60.0 % (n=5) | 60.0 % (n=5) | **nein** |
| Tempo exakt oder gemeldete Alternative trifft | ≥ 99 % | 60.0 % (n=5) | 60.0 % (n=5) | **nein** |
| Offset-Fehler, Median / 95. Perzentil (nur richtiges Tempo) | ≤ 4 ms / ≤ 12 ms | 86.2 ms / 93.5 ms (n=3) | 86.2 ms / 93.5 ms (n=3) | **nein** |
| Drift über den Song, 95. Perzentil (Median / Maximum / Anteil ≤ 10 ms) | ≤ 10 ms | 1.2 ms (0.0 ms / 1.4 ms / 100.0 %; n=3) | 1.2 ms (0.0 ms / 1.4 ms / 100.0 %; n=3) | ja |
| Tempowechsel: Grenzen ±1 Schlag und Tempo je Segment | ≥ 80 % | 0.0 % (n=2; 1 Maps mit Effekt-Linien nicht gewertet) | 0.0 % (n=2; 1 Maps mit Effekt-Linien nicht gewertet) | **nein** |
| Taktanfang (Downbeat) stimmt | ≥ 85 % | 33.3 % (n=3) | 33.3 % (n=3) | **nein** |
| erzeugte Noten auf Menschen-Note (±15 ms), Hard | ≥ 85 % | 69.4 % (n=8, Notenzahl erzeugt/Mensch 0.46) | 69.4 % (n=8, Notenzahl erzeugt/Mensch 0.46) | **nein** |
| Menschen-Noten getroffen (±15 ms), Hard | ≥ 75 % | 34.1 % (n=8) | 34.1 % (n=8) | **nein** |
| Korrelation der Dichtekurve (2-s-Fenster), alle Profile | ≥ 0,8 | 0.263 (n=22 Paare) | 0.263 (n=22 Paare) | **nein** |
| erzeugte Holds überlappen Holds der Map (Maps ≥ 10 % Holds) | ≥ 60 % | nicht messbar, weil dieser Mapper keine Holds erzeugt | nicht messbar, weil dieser Mapper keine Holds erzeugt | **nein** (fehlt) |
| Überlappung der Kiai-Abschnitte (IoU) | ≥ 0,6 | nicht messbar, weil dieser Mapper kein Kiai erzeugt | nicht messbar, weil dieser Mapper kein Kiai erzeugt | **nein** (fehlt) |
| Sterne im Band, schlechtestes Profil | ≥ 90 % | nicht messbar, weil dieser Mapper keine 4K-Map erzeugt (Orbit ohne Spalten; nur 3 Stufen) | nicht messbar, weil dieser Mapper keine 4K-Map erzeugt (Orbit ohne Spalten; nur 3 Stufen) | **nein** (fehlt) |
| Regelverletzungen (AmChart.lint), Summe | 0 | nicht messbar, weil die Noten keine Spalten haben | nicht messbar, weil die Noten keine Spalten haben | **nein** (fehlt) |
| ganzer Ablauf je Song, auf 4 min umgerechnet, 95. Perzentil (Maximum) | ≤ 15 s | – s (– s; Median roh – s; n=0) | – s (– s; Median roh – s; n=0) | nicht messbar, weil keine Laufzeit gemessen (Abstimmung nutzt Zwischenergebnisse) |

`data/automap/params.json` unverändert: Der alte Mapper hat keine params. Gefundener gemeinsamer Versatz für Gitter und Noten: 0.0 ms (Hinweis für `OSU_LEAD_MS`).

## So wird gemessen

- **Wahrheit**: rote Linien, Noten, Holds und Kiai der Menschen-Maps in `maps/`. Zeitbezug je Set: die 4K-Diff mit den meisten Noten, sonst die Diff mit den meisten Objekten. Rote Linien mit gleichem Tempo (0,05 %), die auf dem laufenden Gitter liegen (2 ms), gelten nicht als neues Segment. Bewertet wird zwischen erster und letzter Note.
- **Aufteilung**: `sha256(Dateiname klein)`, erste 8 Hex-Stellen, modulo 100: unter 70 = Abstimm-Menge, sonst Prüf-Menge. Fest, unabhängig von Reihenfolge und Lauf.
- **Tempo exakt**: Auf mindestens 95 % der Strecke weicht das erzeugte Tempo höchstens 0,5 % ab. Zählt nur Maps mit genau einem Segment. Fehlgeschlagene Erzeugung zählt als falsch.
- **Alternative**: Zusätzlich gilt ein Song als getroffen, wenn ein vom Mapper **gemeldeter** Faktor das Tempo richtig macht. Faktoren, die der Mapper nicht meldet, zählen nicht (stehen nur als Ursache in der Liste).
- **Offset-Fehler**: Für jeden Schlag der Map der Abstand zum nächsten erzeugten Schlag, über den Song fortlaufend verfolgt; Median, gefaltet auf ± halben Schlag. Ein um einen halben Schlag versetztes Gitter zählt also mit vollem Fehler. Nur Songs mit exaktem Tempo.
- **Drift**: Abstand am letzten Schlag minus Abstand am ersten Schlag. Als erreicht gilt die Zeile, wenn das 95. Perzentil ≤ 10 ms ist; Maximum und Anteil stehen daneben.
- **Tempowechsel**: Jede Segmentgrenze der Map braucht eine erzeugte Grenze auf ±1 Schlag, und jedes Segment (ohne je einen Schlag Rand) hat zu ≥ 90 % das richtige Tempo. Maps, die rote Linien als Effekt benutzen (Segment kürzer als 2 Schläge, BPM unter 15 oder über 1000), werden nicht gewertet und gezählt ausgewiesen.
- **Taktanfang**: gleiche Taktart und erzeugter Taktanfang weniger als einen halben Schlag neben dem der Map (rote Linie = Taktanfang). Nenner: Songs mit exaktem Tempo; ein falscher Offset zählt hier ebenfalls als falsch.
- **Noten**: Vergleichspartner je Profil ist die 4K-Diff des Sets, deren Sterne der Bandmitte am nächsten sind und höchstens 0,5 Sterne außerhalb des Bands liegen; sonst gibt es kein Paar. Zuordnung eins zu eins nach Zeit (±15 ms), Spalte egal; ein Akkord braucht also einen Akkord. Die Notenzahl wird nicht künstlich angeglichen; das Verhältnis steht daneben, weil es beide Werte begrenzt. Mittelwert über Songs. Ein angebotenes Profil ohne brauchbare Map zählt 0.
- **Dichtekurve**: Noten je 2-s-Fenster ab 0 ms, Pearson-Korrelation je Paar, Mittel über alle Paare.
- **Holds**: nur Paare, deren Menschen-Diff ≥ 10 % Holds hat. Ein erzeugter Hold zählt, wenn mindestens die Hälfte seiner Länge unter einem Hold der Map liegt (Spalte egal). Keine erzeugten Holds = 0.
- **Kiai**: IoU der Zeitabschnitte je Song; Songs, bei denen weder Map noch Erzeugnis Kiai haben, zählen nicht; hat nur eine Seite Kiai, ist der Wert 0.
- **Sterne**: rosu-pp über `StarService`/`tools/starcalc.py`, ein Aufruf für alle erzeugten Diffs. Gewertet wird das schlechteste Profil. Die Ausnahme der Spec für ruhige Songs wird nicht angerechnet (der Prüfstand kann sie nicht beurteilen).
- **Regelverletzungen**: Summe der Meldungen von `AmChart.lint` über alle erzeugten Diffs.
- **Dauer**: Zeit im Prozess je Song, umgerechnet auf 4 Minuten Songlänge. Beim alten Mapper: Dekodieren, Analyse und drei Notenlisten, ohne Schreiben der .osz.

## Grenzen der Messung

- Die Menschen-Maps sind selbst nicht fehlerfrei: Ihr Offset streut um einige Millisekunden. Wie stark, misst der Prüfstand nicht; ein Median-Ziel von 4 ms liegt nahe an dieser Streuung.
- Noten-Kennzahlen messen Übereinstimmung mit **einer** Menschen-Map. Zwei gute Mapper wählen nicht dieselben Stellen; 100 % sind nicht zu erwarten. Wie hoch zwei Menschen-Maps desselben Songs übereinstimmen, ist hier nicht gemessen.
- Ob sich eine Map gut spielt und ob Muster zur Musik passen, misst keine dieser Zahlen. Dafür ist die Hörprobe da.

## Aufruf

```
# Prüfstand, alle Maps (ein Prozess; schreibt docs/automap/report.md)
timeout 7200 ./Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tools/automap_bench.gd -- --maps <maps-ordner>
#   --mapper old|new|auto   --limit N   --set tune|test   --stages   --no-stars   --resume   --report-only
# Abstimmung (sucht params, schreibt data/automap/params.json, Protokoll vorher/nachher auf der Prüf-Menge)
timeout 7200 ./Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tools/automap_tune.gd -- --maps <maps-ordner> [--songs 16] [--test-songs 8] [--passes 2] [--points 5] [--knobs grid.x:0.1:0.9,...]
# Hörprobe: Klick je Note (Tonhöhe je Spalte) und je Schlag über dem Song -> user://automap_check/<name>.ogg
timeout 600 ./Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tools/automap_bench.gd -- --click <audio-datei oder -> <set.osz> [Diff-Teilname]
# Tests der Kennzahlen
timeout 300 ./Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tests/run_am_bench_tests.gd
```
