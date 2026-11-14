# OMEN Auto-Mapper 4K: Prüfstand-Bericht

Erzeugt von `tools/automap_bench.gd` am 2026-11-14. Nicht von Hand ändern; neu erzeugen (Befehle unten).

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

## Mapper „neu“: neue Module (AmGrid, AmFeatures, AmChart, AutoMapper4K)

- Gemessen: 271 Sets (Prüf-Menge 84, Abstimm-Menge 187); 0 ohne rote Linie übersprungen; Erzeugung fehlgeschlagen bei 0 (Prüf) / 0 (Abstimm).
- Laufzeit: 779 s für 276 Sets
- Maps-Ordner: 276 .osz
- Nicht gemessen: 5 Sets nicht lesbar oder ohne Diff mit Noten, zählen in keiner Kennzahl: mirror_2538892 (Konnte .osz nicht oeffnen (Fehler 1)), mirror_2556039 (Konnte .osz nicht oeffnen (Fehler 1)), mirror_2597846 (Konnte .osz nicht oeffnen (Fehler 1)), mirror_2598366 (Konnte .osz nicht oeffnen (Fehler 1)), mirror_2600955 (Konnte .osz nicht oeffnen (Fehler 1))
- Weg: AutoMapper4K.generate, erzeugtes Set zurückgelesen

### Ziel-Tabelle, Prüf-Menge

| Bereich | Kennzahl | Ziel | Ist (Prüf-Menge) | erreicht | Ist (Abstimm-Menge) |
|---|---|---|---|---|---|
| Takt | Tempo exakt (±0,5 %), Maps mit einem Tempo | ≥ 95 % | 88.9 % (n=63) | **nein** | 88.1 % (n=159) |
| Takt | Tempo exakt oder gemeldete Alternative trifft | ≥ 99 % | 98.4 % (n=63) | **nein** | 99.4 % (n=159) |
| Takt | Offset-Fehler, Median / 95. Perzentil (nur richtiges Tempo) | ≤ 4 ms / ≤ 12 ms | 3.1 ms / 52.3 ms (n=56) | **nein** | 3.9 ms / 49.6 ms (n=140) |
| Takt | Drift über den Song, 95. Perzentil (Median / Maximum / Anteil ≤ 10 ms) | ≤ 10 ms | 0.3 ms (0.0 ms / 290.5 ms / 98.2 %; n=56) | ja | 7.7 ms (0.0 ms / 332.0 ms / 95.7 %; n=140) |
| Takt | Tempowechsel: Grenzen ±1 Schlag und Tempo je Segment | ≥ 80 % | 0.0 % (n=6; 15 Maps mit Effekt-Linien nicht gewertet) | **nein** | 0.0 % (n=16; 12 Maps mit Effekt-Linien nicht gewertet) |
| Takt | Taktanfang (Downbeat) stimmt | ≥ 85 % | 87.5 % (n=56) | ja | 87.1 % (n=140) |
| Noten | erzeugte Noten auf Menschen-Note (±15 ms), Hard | ≥ 85 % | 76.5 % (n=69, Notenzahl erzeugt/Mensch 0.8) | **nein** | 71.1 % (n=159, Notenzahl erzeugt/Mensch 0.83) |
| Noten | Menschen-Noten getroffen (±15 ms), Hard | ≥ 75 % | 61.1 % (n=69) | **nein** | 59.0 % (n=159) |
| Noten | Korrelation der Dichtekurve (2-s-Fenster), alle Profile | ≥ 0,8 | 0.544 (n=285 Paare) | **nein** | 0.523 (n=640 Paare) |
| Holds | erzeugte Holds überlappen Holds der Map (Maps ≥ 10 % Holds) | ≥ 60 % | 52.8 % (n=166 Paare) | **nein** | 50.5 % (n=340 Paare) |
| Kiai | Überlappung der Kiai-Abschnitte (IoU) | ≥ 0,6 | 0.266 (n=84) | **nein** | 0.294 (n=187) |
| Stufen | Sterne im Band, schlechtestes Profil | ≥ 90 % | 69.0 % (Easy 90.5 %, Normal 75.0 %, Hard 92.9 %, Insane 79.8 %, Expert 69.0 %; n=420 Diffs) | **nein** | 71.1 % (Easy 93.0 %, Normal 79.1 %, Hard 91.4 %, Insane 81.8 %, Expert 71.1 %; n=935 Diffs) |
| Spielbarkeit | Regelverletzungen (AmChart.lint), Summe | 0 | 0 in 420 Diffs | ja | 0 in 935 Diffs |
| Dauer | ganzer Ablauf je Song, auf 4 min umgerechnet, 95. Perzentil (Maximum) | ≤ 15 s | 5.5 s (6.2 s; Median roh 2.5 s; n=84) | ja | 5.5 s (6.2 s; Median roh 2.6 s; n=187) |

**4 von 14 Zielen erreicht.**

Zusatzwerte (Prüf-Menge): systematischer Versatz (Median mit Vorzeichen, + = erzeugt zu spät) 0.6 ms; Noten auf dem eigenen Gitter 100.0 %.

### Noten je Profil, Prüf-Menge

| Profil | Paare | auf Menschen-Note | Menschen-Noten getroffen | Dichte-Korrelation | Notenzahl erzeugt/Mensch | Sterne im Band | Hinweis |
|---|---|---|---|---|---|---|---|
| Easy | 59 | 69.8 % | 51.0 % | 0.368 | 0.71 | 90.5 % (Median 1.58, n=84) |  |
| Normal | 67 | 74.8 % | 59.0 % | 0.485 | 0.8 | 75.0 % (Median 2.36, n=84) |  |
| Hard | 69 | 76.5 % | 61.1 % | 0.588 | 0.8 | 92.9 % (Median 3.4, n=84) |  |
| Insane | 58 | 74.2 % | 60.0 % | 0.652 | 0.81 | 79.8 % (Median 4.36, n=84) |  |
| Expert | 32 | 70.6 % | 59.6 % | 0.706 | 0.82 | 69.0 % (Median 5.44, n=84) |  |

### Schlechteste 20 Songs je Kennzahl

(P) = Prüf-Menge, (A) = Abstimm-Menge. Ursache = aus den Messwerten abgeleitete Einordnung, keine Hörprüfung.

### Tempo falsch (Maps mit einem Tempo)

| Song | BPM Map | BPM erzeugt | Ursache |
|---|---|---|---|
| mirror_2438724 (A) | 390.0 | 97.5 | daneben: erzeugt 97.50 BPM, Map 390.00 BPM |
| mirror_349208 (A) | 256.0 | 111.52 | daneben: erzeugt 111.52 BPM, Map 256.00 BPM |
| mirror_2119120 (A) | 95.0 | 190.31 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2128157 (A) | 225.0 | 112.49 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2511666 (A) | 185.0 | 92.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2552898 (A) | 90.0 | 180.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2491936 (A) | 110.0 | 220.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2532288 (A) | 111.0 | 222.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2523688 (P) | 105.0 | 210.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2506744 (P) | 93.0 | 186.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_476691 (A) | 100.0 | 200.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_283841 (A) | 200.0 | 100.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2588413 (P) | 200.0 | 100.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2534361 (A) | 100.0 | 200.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2506453 (A) | 75.0 | 150.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2217940 (A) | 240.0 | 120.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2205779 (A) | 240.0 | 120.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2545184 (P) | 218.0 | 109.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2578511 (P) | 108.0 | 216.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2318291 (P) | 270.0 | 135.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |

### Offset-Fehler

| Song | Fehler ms (+ = zu spät) | Ursache |
|---|---|---|
| mirror_206887 (A) | -217.7 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2400881 (A) | +199.6 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2513755 (P) | -174.9 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2039039 (P) | -172.0 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2586880 (P) | +168.8 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_126752 (A) | +161.8 | Gitter später als die Map |
| mirror_256623 (A) | +153.5 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2388455 (A) | -150.7 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2079518 (A) | +147.7 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| 309881 goreshit - burn this moment into the retina of my eye (A) | -133.7 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2422509 (A) | +45.2 | Gitter später als die Map |
| mirror_2573147 (A) | +39.8 | Gitter später als die Map |
| 2134137 Akiri feat. InabaYap - Tonight We Fly (A) | -21.6 | Gitter früher als die Map |
| 2246587 Mitsukiyo - Mikansei Romantic (feat. kotono) (A) | +19.5 | Gitter später als die Map |
| mirror_407186 (A) | -19.2 | Gitter früher als die Map |
| mirror_324288 (A) | +18.5 | Gitter später als die Map |
| mirror_375365 (A) | +17.9 | Gitter später als die Map |
| mirror_2096660 (A) | -17.3 | Gitter früher als die Map |
| mirror_2506807 (A) | +15.4 | Gitter später als die Map |
| mirror_2607616 (A) | +15.0 | Gitter später als die Map |

### Drift

| Song | Drift ms | Ursache |
|---|---|---|
| mirror_126752 (A) | +332.0 | Tempo um -0.3244 % daneben (erzeugt 129.578, Map 130.000 BPM) |
| mirror_2586880 (P) | +290.5 | Tempo um -0.0003 % daneben (erzeugt 154.219, Map 154.219 BPM) |
| mirror_2079518 (A) | +232.3 | Tempo um -0.3635 % daneben (erzeugt 179.346, Map 180.000 BPM) |
| mirror_2422509 (A) | +129.0 | Tempo um -0.3877 % daneben (erzeugt 104.593, Map 105.000 BPM) |
| mirror_324288 (A) | -60.8 | Tempo um 0.0555 % daneben (erzeugt 183.602, Map 183.500 BPM) |
| mirror_2607616 (A) | +40.8 | Tempo um -0.0242 % daneben (erzeugt 204.775, Map 204.825 BPM) |
| mirror_2514525 (A) | +20.6 | Tempo um -0.0222 % daneben (erzeugt 136.170, Map 136.200 BPM) |
| mirror_2555143 (A) | +9.2 | Tempo um -0.0069 % daneben (erzeugt 171.538, Map 171.550 BPM) |
| mirror_2536648 (A) | +7.6 | Tempo um -0.0095 % daneben (erzeugt 112.859, Map 112.870 BPM) |
| mirror_2515013 (A) | +5.6 | Tempo um -0.0060 % daneben (erzeugt 122.133, Map 122.140 BPM) |
| mirror_2561773 (P) | -2.3 | Tempo um 0.0060 % daneben (erzeugt 149.309, Map 149.300 BPM) |
| 1343787 linear ring - lalabai call me (A) | -1.6 | Tempo um 0.0011 % daneben (erzeugt 208.502, Map 208.500 BPM) |
| mirror_2493125 (A) | -1.0 | Tempo um 0.0011 % daneben (erzeugt 128.381, Map 128.380 BPM) |
| mirror_155749 (P) | -0.6 | Tempo um 0.0004 % daneben (erzeugt 178.501, Map 178.500 BPM) |
| mirror_2508959 (P) | +0.2 | Tempo um -0.0002 % daneben (erzeugt 202.600, Map 202.600 BPM) |
| 2150831 sath4 - _3_006 w_yax03 (A) | -0.0 | Tempo um 0.0000 % daneben (erzeugt 140.000, Map 140.000 BPM) |
| mirror_2306554 (A) | -0.0 | Tempo um 0.0000 % daneben (erzeugt 195.000, Map 195.000 BPM) |
| mirror_2378766 (A) | -0.0 | Tempo um 0.0000 % daneben (erzeugt 210.000, Map 210.000 BPM) |
| mirror_2096660 (A) | +0.0 | Tempo um -0.0000 % daneben (erzeugt 185.000, Map 185.000 BPM) |
| mirror_2331207 (A) | +0.0 | Tempo um -0.0000 % daneben (erzeugt 155.000, Map 155.000 BPM) |

### Tempowechsel nicht getroffen

| Song | Segmente Map | Segmente erzeugt | Ursache |
|---|---|---|---|
| mirror_332623 (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 3 falsch (Map 278.00 BPM, erzeugt 138.95) |
| 315435 UNDEAD CORPORATION - The Empress scream off ver (P) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 270.00 BPM, erzeugt 135.00) |
| mirror_2528018 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 210.00 BPM, erzeugt 105.00) |
| mirror_2555375 (A) | 10 | 8 | Grenze bei 78415 ms fehlt |
| mirror_2559592 (P) | 3 | 5 | Tempo in Segment 1 falsch (Map 170.00 BPM, erzeugt 170.00) |
| mirror_576112 (A) | 10 | 1 | kein Tempowechsel erkannt; Tempo in Segment 10 falsch (Map 192.00 BPM, erzeugt 190.00) |
| mirror_2643833 (P) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 77.50 BPM, erzeugt 165.00) |
| mirror_2528075 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 134.00 BPM, erzeugt 132.00) |
| mirror_2511692 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 146.70 BPM, erzeugt 186.64) |
| mirror_1294997 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 77.00 BPM, erzeugt 154.00) |
| 2298540 Omerta - Charade (feat. Vincente Void _ Hash Gordon) (A) | 8 | 1 | kein Tempowechsel erkannt; Tempo in Segment 8 falsch (Map 120.00 BPM, erzeugt 180.00) |
| mirror_1178589 (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 184.00 BPM, erzeugt 192.00) |
| 347453 Igorrr & Ruby My Dear - Figue Folle (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 141.00 BPM, erzeugt 188.00) |
| mirror_2563805 (P) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 168.00 BPM, erzeugt 180.00) |
| mirror_2576239 (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 280.00 BPM, erzeugt 140.00) |
| mirror_2584545 (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 162.00 BPM, erzeugt 160.32) |
| 1787141 Marmalade butcher - Immortality Math Club (A) | 12 | 1 | kein Tempowechsel erkannt; Tempo in Segment 12 falsch (Map 210.00 BPM, erzeugt 205.00) |
| mirror_2198573 (A) | 3 | 1 | kein Tempowechsel erkannt; Grenze bei 80159 ms fehlt |
| mirror_2541848 (P) | 4 | 1 | kein Tempowechsel erkannt; Grenze bei 12073 ms fehlt |
| mirror_2572994 (P) | 2 | 1 | kein Tempowechsel erkannt; Grenze bei 129049 ms fehlt |

### Taktanfang falsch

| Song | Ursache |
|---|---|
| mirror_206887 (A) | um 1 Schlag/Schläge verschoben |
| mirror_2039039 (P) | um 1 Schlag/Schläge verschoben |
| mirror_2388455 (A) | um 1 Schlag/Schläge verschoben |
| 309881 goreshit - burn this moment into the retina of my eye (A) | um 1 Schlag/Schläge verschoben |
| mirror_2573147 (A) | um -2 Schlag/Schläge verschoben |
| 2246587 Mitsukiyo - Mikansei Romantic (feat. kotono) (A) | um -2 Schlag/Schläge verschoben |
| mirror_140097 (A) | um -1 Schlag/Schläge verschoben |
| mirror_2493125 (A) | um 2 Schlag/Schläge verschoben |
| mirror_2539716 (A) | um -2 Schlag/Schläge verschoben |
| 844183 tatatat - e (A) | Taktart 4 statt 6 |
| mirror_2398569 (A) | um -2 Schlag/Schläge verschoben |
| mirror_2536648 (A) | um 2 Schlag/Schläge verschoben |
| mirror_2561773 (P) | um -1 Schlag/Schläge verschoben |
| mirror_2527334 (P) | um -2 Schlag/Schläge verschoben |
| mirror_2623104 (A) | Taktart 4 statt 6 |
| mirror_2017220 (A) | um 1 Schlag/Schläge verschoben |
| mirror_2537768 (P) | um -1 Schlag/Schläge verschoben |
| mirror_176446 (A) | um 2 Schlag/Schläge verschoben |
| mirror_2515013 (A) | um -2 Schlag/Schläge verschoben |
| mirror_2351212 (A) | um -2 Schlag/Schläge verschoben |

### Noten: erzeugte Noten ohne Menschen-Note (Hard)

| Song | Anteil auf Menschen-Note | Menschen-Diff | Ursache |
|---|---|---|---|
| mirror_2096660 (A) | 0.0 % | Revv's Hard | Versatz -17 ms |
| mirror_375365 (A) | 0.0 % | Advanced | Versatz +18 ms |
| mirror_407186 (A) | 0.3 % | 4K Hard | Versatz -19 ms |
| mirror_2506453 (A) | 16.1 % | Your blurred shape, behind the cold mist // Insane | Tempo falsch (x2.000) |
| mirror_576112 (A) | 16.5 % | Live the Moment | Tempowechsel nicht getroffen |
| mirror_2555375 (A) | 18.9 % | insane | Tempowechsel nicht getroffen |
| mirror_126752 (A) | 22.5 % | 4K HD | Versatz +162 ms |
| mirror_2422509 (A) | 23.6 % | hard | Versatz +45 ms |
| mirror_2079518 (A) | 24.2 % | tapperruiii's Ascension | Versatz +148 ms |
| mirror_2036133 (P) | 26.0 % | Insane | Map mit Effekt-Linien |
| mirror_349208 (A) | 28.4 % | ADVANCED | Tempo falsch (x0.436) |
| 171880 xi - Happy End of the World (P) | 29.5 % | 4K Hard | Map mit Effekt-Linien |
| mirror_2573147 (A) | 29.6 % | NEVER ENDING SLEEPLESS CYCLE | Versatz +40 ms |
| mirror_2559655 (A) | 29.6 % | hard | Map mit Effekt-Linien |
| mirror_2584545 (A) | 33.3 % | I AM A LARPITECT | Tempowechsel nicht getroffen |
| mirror_2278487 (P) | 35.1 % | 29/16 | Map mit Effekt-Linien |
| mirror_2564470 (A) | 35.6 % | Fading Memories. | Map mit Effekt-Linien |
| mirror_274111 (P) | 37.7 % | Feru's HD | Map mit Effekt-Linien |
| mirror_2119120 (A) | 40.5 % | Moyai | Tempo falsch (x2.003) |
| mirror_324288 (A) | 44.9 % | Starry's 4K Lv.15 | Versatz +19 ms |

### Noten: Menschen-Noten nicht getroffen (Hard)

| Song | Anteil getroffen | Menschen-Diff | Ursache |
|---|---|---|---|
| mirror_2096660 (A) | 0.0 % | Revv's Hard | Versatz -17 ms |
| mirror_375365 (A) | 0.0 % | Advanced | Versatz +18 ms |
| mirror_407186 (A) | 0.3 % | 4K Hard | Versatz -19 ms |
| mirror_2555375 (A) | 9.6 % | insane | Tempowechsel nicht getroffen |
| mirror_576112 (A) | 12.4 % | Live the Moment | Tempowechsel nicht getroffen |
| mirror_2422509 (A) | 15.7 % | hard | Versatz +45 ms |
| mirror_2278487 (P) | 15.7 % | 29/16 | Map mit Effekt-Linien |
| mirror_2079518 (A) | 18.3 % | tapperruiii's Ascension | Versatz +148 ms |
| mirror_126752 (A) | 19.1 % | 4K HD | Versatz +162 ms |
| mirror_2506453 (A) | 19.2 % | Your blurred shape, behind the cold mist // Insane | Tempo falsch (x2.000) |
| mirror_2119120 (A) | 19.6 % | Moyai | Tempo falsch (x2.003) |
| mirror_349208 (A) | 19.7 % | ADVANCED | Tempo falsch (x0.436) |
| mirror_2036133 (P) | 20.1 % | Insane | Map mit Effekt-Linien |
| mirror_2559655 (A) | 23.6 % | hard | Map mit Effekt-Linien |
| mirror_2584545 (A) | 25.1 % | I AM A LARPITECT | Tempowechsel nicht getroffen |
| mirror_2573147 (A) | 26.8 % | NEVER ENDING SLEEPLESS CYCLE | Versatz +40 ms |
| 2150831 sath4 - _3_006 w_yax03 (A) | 28.0 % | Happy Love Expert | Notenzahl erzeugt/Mensch = 0.33 |
| mirror_274111 (P) | 29.7 % | Feru's HD | Map mit Effekt-Linien |
| 171880 xi - Happy End of the World (P) | 30.5 % | 4K Hard | Map mit Effekt-Linien |
| mirror_2616511 (P) | 32.5 % | Insane | Map mit Effekt-Linien |

### Dichtekurve

| Song | Profil | Korrelation | Ursache |
|---|---|---|---|
| mirror_2119120 (A) | Easy | -0.574 | Tempo falsch (x2.003) |
| mirror_2119120 (A) | Hard | -0.457 | Tempo falsch (x2.003) |
| mirror_2555375 (A) | Normal | -0.396 | Tempowechsel nicht getroffen |
| mirror_2489537 (A) | Insane | -0.367 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_2119120 (A) | Normal | -0.335 | Tempo falsch (x2.003) |
| mirror_2563805 (P) | Easy | -0.326 | Tempowechsel nicht getroffen |
| mirror_2555375 (A) | Hard | -0.299 | Tempowechsel nicht getroffen |
| mirror_576112 (A) | Easy | -0.264 | Tempowechsel nicht getroffen |
| mirror_2563805 (P) | Normal | -0.241 | Tempowechsel nicht getroffen |
| 2219350 Toromaru - Uncharted Sky (A) | Easy | -0.201 | Tempowechsel nicht getroffen |
| mirror_476221 (A) | Normal | -0.178 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_105186 (A) | Normal | -0.165 | Notenzahl erzeugt/Mensch = 0.63 |
| mirror_2561773 (P) | Normal | -0.148 | Notenzahl erzeugt/Mensch = 0.70 |
| mirror_2489537 (A) | Hard | -0.144 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_159068 (A) | Normal | -0.142 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| 1708332 MisoilePunch _pan soe_ - MeTear_n TruX (P) | Normal | -0.14 | Notenzahl erzeugt/Mensch = 0.59 |
| mirror_206887 (A) | Easy | -0.134 | Versatz -218 ms |
| mirror_2527829 (A) | Normal | -0.12 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_2493152 (P) | Easy | -0.117 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_2561773 (P) | Easy | -0.109 | Notenzahl erzeugt/Mensch = 0.65 |

### Holds

| Song | Profil | Anteil überlappend | Ursache |
|---|---|---|---|
| mirror_349208 (A) | Easy | 0.0 % | Holds an anderen Stellen (3 erzeugt) |
| mirror_2545184 (P) | Easy | 0.0 % | Holds an anderen Stellen (1 erzeugt) |
| mirror_2512348 (P) | Easy | 0.0 % | Holds an anderen Stellen (10 erzeugt) |
| mirror_2610887 (P) | Hard | 4.1 % | Holds an anderen Stellen (97 erzeugt) |
| mirror_576112 (A) | Easy | 4.5 % | Holds an anderen Stellen (22 erzeugt) |
| mirror_2553525 (A) | Normal | 5.9 % | Holds an anderen Stellen (34 erzeugt) |
| mirror_2610887 (P) | Insane | 6.6 % | Holds an anderen Stellen (137 erzeugt) |
| mirror_2327005 (A) | Insane | 7.9 % | Holds an anderen Stellen (139 erzeugt) |
| mirror_2591197 (A) | Expert | 8.9 % | Holds an anderen Stellen (124 erzeugt) |
| mirror_2591197 (A) | Hard | 9.1 % | Holds an anderen Stellen (88 erzeugt) |
| mirror_2610887 (P) | Normal | 9.8 % | Holds an anderen Stellen (51 erzeugt) |
| mirror_2591197 (A) | Insane | 9.8 % | Holds an anderen Stellen (112 erzeugt) |
| mirror_2545191 (A) | Easy | 10.0 % | Holds an anderen Stellen (70 erzeugt) |
| mirror_2481624 (A) | Easy | 10.8 % | Holds an anderen Stellen (74 erzeugt) |
| mirror_476221 (A) | Easy | 11.4 % | Holds an anderen Stellen (79 erzeugt) |
| mirror_480769 (P) | Easy | 11.6 % | Holds an anderen Stellen (129 erzeugt) |
| 2289293 Tsukasa Kaminose - ruin of opals (Full Ver.) (P) | Insane | 13.0 % | Holds an anderen Stellen (254 erzeugt) |
| mirror_2327005 (A) | Hard | 13.1 % | Holds an anderen Stellen (130 erzeugt) |
| mirror_2403887 (P) | Hard | 13.3 % | Holds an anderen Stellen (158 erzeugt) |
| mirror_2446560 (A) | Insane | 13.3 % | Holds an anderen Stellen (60 erzeugt) |

### Kiai

| Song | IoU | Ursache |
|---|---|---|
| mirror_2455211 (A) | 0.0 | Kiai erzeugt (33 s), Map hat keins |
| mirror_2458045 (A) | 0.0 | Abschnitte an anderer Stelle |
| mirror_2467187 (A) | 0.0 | Kiai erzeugt (23 s), Map hat keins |
| mirror_2485116 (A) | 0.0 | Kiai erzeugt (42 s), Map hat keins |
| mirror_2486779 (A) | 0.0 | Kiai erzeugt (96 s), Map hat keins |
| mirror_2491936 (A) | 0.0 | Kiai erzeugt (109 s), Map hat keins |
| mirror_2493125 (A) | 0.0 | Kiai erzeugt (34 s), Map hat keins |
| mirror_2506744 (P) | 0.0 | Kiai erzeugt (10 s), Map hat keins |
| mirror_2508953 (A) | 0.0 | Kiai erzeugt (65 s), Map hat keins |
| mirror_2509474 (A) | 0.0 | Kiai erzeugt (28 s), Map hat keins |
| mirror_2511692 (A) | 0.0 | Kiai erzeugt (49 s), Map hat keins |
| mirror_2514525 (A) | 0.0 | Abschnitte an anderer Stelle |
| mirror_2521385 (A) | 0.0 | Abschnitte an anderer Stelle |
| mirror_2523377 (P) | 0.0 | Abschnitte an anderer Stelle |
| mirror_2523688 (P) | 0.0 | Kiai erzeugt (49 s), Map hat keins |
| mirror_2527829 (A) | 0.0 | Kiai erzeugt (24 s), Map hat keins |
| mirror_2532676 (A) | 0.0 | Kiai erzeugt (40 s), Map hat keins |
| mirror_2533221 (P) | 0.0 | Kiai erzeugt (56 s), Map hat keins |
| mirror_2205779 (A) | 0.0 | Kiai erzeugt (128 s), Map hat keins |
| mirror_2240934 (P) | 0.0 | Kiai erzeugt (61 s), Map hat keins |

### Sterne außerhalb des Bands

| Song | Profil | Sterne | Band | Ursache |
|---|---|---|---|---|
| 844183 tatatat - e (A) | Expert | 1.68 | 5.0–6.0 | zu leicht (70 BPM) |
| 844183 tatatat - e (A) | Insane | 1.4 | 4.0–4.8 | zu leicht (70 BPM) |
| mirror_2551467 (A) | Expert | 2.86 | 5.0–6.0 | zu leicht (144 BPM) |
| 844183 tatatat - e (A) | Hard | 1.21 | 3.0–3.8 | zu leicht (70 BPM) |
| mirror_2561773 (P) | Expert | 3.32 | 5.0–6.0 | zu leicht (149 BPM) |
| mirror_2506744 (P) | Expert | 3.33 | 5.0–6.0 | zu leicht (93 BPM) |
| mirror_2275128 (A) | Expert | 3.37 | 5.0–6.0 | zu leicht (120 BPM) |
| mirror_2425501 (A) | Expert | 3.55 | 5.0–6.0 | zu leicht (96 BPM) |
| mirror_2119120 (A) | Expert | 3.69 | 5.0–6.0 | zu leicht (95 BPM) |
| mirror_2539345 (A) | Expert | 3.69 | 5.0–6.0 | zu leicht (135 BPM) |
| mirror_2278487 (P) | Expert | 3.69 | 5.0–6.0 | zu leicht (126 BPM) |
| mirror_2493125 (A) | Expert | 3.7 | 5.0–6.0 | zu leicht (128 BPM) |
| mirror_2551467 (A) | Insane | 2.7 | 4.0–4.8 | zu leicht (144 BPM) |
| mirror_2620660 (P) | Expert | 3.71 | 5.0–6.0 | zu leicht (160 BPM) |
| mirror_2537768 (P) | Expert | 3.76 | 5.0–6.0 | zu leicht (120 BPM) |
| mirror_2278487 (P) | Insane | 2.77 | 4.0–4.8 | zu leicht (126 BPM) |
| mirror_2543663 (P) | Expert | 3.78 | 5.0–6.0 | zu leicht (155 BPM) |
| mirror_1294997 (A) | Expert | 3.79 | 5.0–6.0 | zu leicht (77 BPM) |
| mirror_2493125 (A) | Insane | 2.79 | 4.0–4.8 | zu leicht (128 BPM) |
| mirror_2544540 (A) | Expert | 3.8 | 5.0–6.0 | zu leicht (147 BPM) |

### Regelverletzungen

Keine Einträge.

### Dauer

| Song | s auf 4 min | s roh | Songlänge s | Ursache |
|---|---|---|---|---|
| mirror_2536648 (A) | 6.2 | 2.1 | 83 | – |
| mirror_682518 (P) | 6.2 | 0.8 | 30 | – |
| mirror_2422509 (A) | 6.1 | 0.9 | 36 | – |
| mirror_2506744 (P) | 5.9 | 0.8 | 33 | – |
| mirror_2553140 (A) | 5.9 | 1.3 | 53 | – |
| mirror_2294669 (P) | 5.9 | 1.4 | 57 | – |
| mirror_332623 (A) | 5.8 | 2.2 | 90 | – |
| mirror_2561773 (P) | 5.6 | 0.9 | 40 | – |
| mirror_2079518 (A) | 5.6 | 1.6 | 66 | – |
| mirror_2092603 (A) | 5.6 | 2.1 | 88 | – |
| mirror_2559426 (A) | 5.6 | 0.9 | 38 | – |
| mirror_2288732 (A) | 5.5 | 2.4 | 104 | – |
| mirror_105186 (A) | 5.5 | 1.0 | 44 | – |
| mirror_2545184 (P) | 5.5 | 1.6 | 70 | – |
| mirror_1294997 (A) | 5.5 | 2.0 | 89 | – |
| mirror_2400069 (A) | 5.5 | 2.9 | 129 | – |
| mirror_108577 (A) | 5.4 | 1.9 | 86 | – |
| mirror_2527829 (A) | 5.4 | 1.0 | 45 | – |
| mirror_2434745 (A) | 5.4 | 2.1 | 92 | – |
| mirror_2559655 (A) | 5.3 | 1.2 | 53 | – |

## Letzte Abstimmung (`tools/automap_tune.gd`)

- Stand: 2026-11-14T11:21:36, Mapper „neu“, 28 Songs Abstimm-Menge, 16 Songs Prüf-Menge, 124 Auswertungen, 1618 s.
- Zielgröße (0..1, 1 = alle Ziele erreicht; ohne Sterne und Dauer): Abstimm-Menge 0.7097 -> 0.7162, **Prüf-Menge 0.8188 -> 0.8234**.
- Durchgang 1, chart.w_kick: <null> -> 0.3 (Zielgröße 0.7116)
- Durchgang 1, chart.w_snare: <null> -> 1.53333333333333 (Zielgröße 0.7124)
- Durchgang 1, chart.w_hat: <null> -> 1.1 (Zielgröße 0.7130)
- Durchgang 1, chart.w_bass: <null> -> <null> (Zielgröße 0.7130)
- Durchgang 1, chart.w_tonal: <null> -> <null> (Zielgröße 0.7130)
- Durchgang 1, chart.w_vocal: <null> -> <null> (Zielgröße 0.7130)
- Durchgang 1, chart.w_other: <null> -> <null> (Zielgröße 0.7130)
- Durchgang 1, chart.w_metric: <null> -> 1.5 (Zielgröße 0.7134)
- Durchgang 1, chart.w_strength: <null> -> 0.5 (Zielgröße 0.7146)
- Durchgang 1, chart.dens_gain: <null> -> 0.26666666666667 (Zielgröße 0.7146)
- Durchgang 1, chart.dens_local_gain: <null> -> <null> (Zielgröße 0.7146)
- Durchgang 1, chart.support_weight: <null> -> 0.2 (Zielgröße 0.7148)
- Durchgang 1, chart.support_drum_weight: <null> -> 0.8 (Zielgröße 0.7150)
- Durchgang 1, features.onset_shift_ms: <null> -> 6.0 (Zielgröße 0.7152)
- Durchgang 1, features.kiai_abs: <null> -> <null> (Zielgröße 0.7152)
- Durchgang 1, features.kiai_margin: <null> -> 0.13333333333333 (Zielgröße 0.7157)
- Durchgang 2, chart.w_kick: 0.3 -> 0.43333333333333 (Zielgröße 0.7157)
- Durchgang 2, chart.w_snare: 1.53333333333333 -> 2.0 (Zielgröße 0.7160)
- Durchgang 2, chart.w_hat: 1.1 -> 1.1 (Zielgröße 0.7160)
- Durchgang 2, chart.w_bass: <null> -> <null> (Zielgröße 0.7160)
- Durchgang 2, chart.w_tonal: <null> -> <null> (Zielgröße 0.7160)
- Durchgang 2, chart.w_vocal: <null> -> 1.5 (Zielgröße 0.7160)
- Durchgang 2, chart.w_other: <null> -> 1.2 (Zielgröße 0.7162)
- Durchgang 2, chart.w_metric: 1.5 -> 1.5 (Zielgröße 0.7162)
- Durchgang 2, chart.w_strength: 0.5 -> 0.5 (Zielgröße 0.7162)
- Durchgang 2, chart.dens_gain: 0.26666666666667 -> 0.26666666666667 (Zielgröße 0.7162)
- Durchgang 2, chart.dens_local_gain: <null> -> <null> (Zielgröße 0.7162)
- Durchgang 2, chart.support_weight: 0.2 -> 0.2 (Zielgröße 0.7162)
- Durchgang 2, chart.support_drum_weight: 0.8 -> 0.8 (Zielgröße 0.7162)
- Durchgang 2, features.onset_shift_ms: 6.0 -> 6.0 (Zielgröße 0.7162)
- Durchgang 2, features.kiai_abs: <null> -> <null> (Zielgröße 0.7162)
- Durchgang 2, features.kiai_margin: 0.13333333333333 -> 0.13333333333333 (Zielgröße 0.7162)

| Kennzahl (Prüf-Menge, nur die geladenen Songs) | Ziel | vorher | nachher | erreicht nachher |
|---|---|---|---|---|
| Tempo exakt (±0,5 %), Maps mit einem Tempo | ≥ 95 % | 90.9 % (n=11) | 90.9 % (n=11) | **nein** |
| Tempo exakt oder gemeldete Alternative trifft | ≥ 99 % | 100.0 % (n=11) | 100.0 % (n=11) | ja |
| Offset-Fehler, Median / 95. Perzentil (nur richtiges Tempo) | ≤ 4 ms / ≤ 12 ms | 1.5 ms / 10.6 ms (n=10) | 1.5 ms / 10.6 ms (n=10) | ja |
| Drift über den Song, 95. Perzentil (Median / Maximum / Anteil ≤ 10 ms) | ≤ 10 ms | 0.0 ms (0.0 ms / 0.0 ms / 100.0 %; n=10) | 0.0 ms (0.0 ms / 0.0 ms / 100.0 %; n=10) | ja |
| Tempowechsel: Grenzen ±1 Schlag und Tempo je Segment | ≥ 80 % | 0.0 % (n=3; 2 Maps mit Effekt-Linien nicht gewertet) | 0.0 % (n=3; 2 Maps mit Effekt-Linien nicht gewertet) | **nein** |
| Taktanfang (Downbeat) stimmt | ≥ 85 % | 100.0 % (n=10) | 100.0 % (n=10) | ja |
| erzeugte Noten auf Menschen-Note (±15 ms), Hard | ≥ 85 % | 75.2 % (n=12, Notenzahl erzeugt/Mensch 0.72) | 75.5 % (n=12, Notenzahl erzeugt/Mensch 0.76) | **nein** |
| Menschen-Noten getroffen (±15 ms), Hard | ≥ 75 % | 54.4 % (n=12) | 58.3 % (n=12) | **nein** |
| Korrelation der Dichtekurve (2-s-Fenster), alle Profile | ≥ 0,8 | 0.591 (n=57 Paare) | 0.58 (n=57 Paare) | **nein** |
| erzeugte Holds überlappen Holds der Map (Maps ≥ 10 % Holds) | ≥ 60 % | 50.4 % (n=20 Paare) | 49.8 % (n=20 Paare) | **nein** |
| Überlappung der Kiai-Abschnitte (IoU) | ≥ 0,6 | 0.24 (n=16) | 0.243 (n=16) | **nein** |
| Sterne im Band, schlechtestes Profil | ≥ 90 % | – (Easy –, Normal –, Hard –, Insane –, Expert –; n=0 Diffs) | – (Easy –, Normal –, Hard –, Insane –, Expert –; n=0 Diffs) | nicht messbar, weil keine Sterne berechnet (starcalc/python fehlt oder --no-stars) |
| Regelverletzungen (AmChart.lint), Summe | 0 | 1 in 80 Diffs | 1 in 80 Diffs | **nein** |
| ganzer Ablauf je Song, auf 4 min umgerechnet, 95. Perzentil (Maximum) | ≤ 15 s | – s (– s; Median roh – s; n=0) | – s (– s; Median roh – s; n=0) | nicht messbar, weil keine Laufzeit gemessen (Abstimmung nutzt Zwischenergebnisse) |

`data/automap/params.json` geschrieben.

- Zweite Runde (weitere Bereiche fuer die Randwerte w_snare 1,5-3,5, w_metric 1,2-2,5, w_strength 0,2-0,7, support_weight 0,05-0,3, w_kick 0,2-0,6, onset_shift_ms 4-10; 24 Auswertungen): keine Verbesserung, Werte der ersten Runde bleiben.

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
#   --onsets: Abstand Klick -> Anschlag im Audio (Median / 95. Perzentil)
timeout 600 ./Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tools/automap_bench.gd -- --click <audio-datei oder -> <set.osz> [Diff-Teilname] [--onsets]
# Tests der Kennzahlen
timeout 300 ./Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tests/run_am_bench_tests.gd
```
