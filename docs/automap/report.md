# OMEN Auto-Mapper 4K: Prüfstand-Bericht

Erzeugt von `tools/automap_bench.gd` am 2026-11-13. Nicht von Hand ändern; neu erzeugen (Befehle unten).

Der Bericht bewertet gegen die Ziel-Tabelle aus `docs/automap/spec.md`. Maßgeblich ist die **Prüf-Menge** (30 % der Maps, wird nie zum Abstimmen benutzt). „nicht messbar“ heißt: Für diese Zeile gibt es keinen Wert; sie gilt nicht als erreicht.

## Mapper „alt“: alter Mapper (`AudioMapper`, Orbit) über Adapter

- Gemessen: 170 Sets (Prüf-Menge 48, Abstimm-Menge 122); 0 ohne rote Linie übersprungen; Erzeugung fehlgeschlagen bei 0 (Prüf) / 0 (Abstimm).
- Maps-Ordner: 259 .osz
- Weg: Stufen einzeln (decode, Gitter, Features, Noten)

### Ziel-Tabelle, Prüf-Menge

| Bereich | Kennzahl | Ziel | Ist (Prüf-Menge) | erreicht | Ist (Abstimm-Menge) |
|---|---|---|---|---|---|
| Takt | Tempo exakt (±0,5 %), Maps mit einem Tempo | ≥ 95 % | 64.9 % (n=37) | **nein** | 55.7 % (n=106) |
| Takt | Tempo exakt oder gemeldete Alternative trifft | ≥ 99 % | 64.9 % (n=37) | **nein** | 55.7 % (n=106) |
| Takt | Offset-Fehler, Median / 95. Perzentil (nur richtiges Tempo) | ≤ 4 ms / ≤ 12 ms | 10.1 ms / 155.5 ms (n=24) | **nein** | 4.7 ms / 120.2 ms (n=59) |
| Takt | Drift über den Song, 95. Perzentil (Median / Maximum / Anteil ≤ 10 ms) | ≤ 10 ms | 4.8 ms (1.3 ms / 5.2 ms / 100.0 %; n=24) | ja | 19.2 ms (1.6 ms / 54.8 ms / 93.2 %; n=59) |
| Takt | Tempowechsel: Grenzen ±1 Schlag und Tempo je Segment | ≥ 80 % | 0.0 % (n=1; 10 Maps mit Effekt-Linien nicht gewertet) | **nein** | 0.0 % (n=11; 5 Maps mit Effekt-Linien nicht gewertet) |
| Takt | Taktanfang (Downbeat) stimmt | ≥ 85 % | 33.3 % (n=24) | **nein** | 40.7 % (n=59) |
| Noten | erzeugte Noten auf Menschen-Note (±15 ms), Hard | ≥ 85 % | 68.3 % (n=36, Notenzahl erzeugt/Mensch 0.5) | **nein** | 72.4 % (n=102, Notenzahl erzeugt/Mensch 0.52) |
| Noten | Menschen-Noten getroffen (±15 ms), Hard | ≥ 75 % | 35.4 % (n=36) | **nein** | 38.3 % (n=102) |
| Noten | Korrelation der Dichtekurve (2-s-Fenster), alle Profile | ≥ 0,8 | 0.246 (n=102 Paare) | **nein** | 0.272 (n=293 Paare) |
| Holds | erzeugte Holds überlappen Holds der Map (Maps ≥ 10 % Holds) | ≥ 60 % | nicht messbar, weil dieser Mapper keine Holds erzeugt | **nein** (fehlt) | nicht messbar, weil dieser Mapper keine Holds erzeugt |
| Kiai | Überlappung der Kiai-Abschnitte (IoU) | ≥ 0,6 | nicht messbar, weil dieser Mapper kein Kiai erzeugt | **nein** (fehlt) | nicht messbar, weil dieser Mapper kein Kiai erzeugt |
| Stufen | Sterne im Band, schlechtestes Profil | ≥ 90 % | nicht messbar, weil dieser Mapper keine 4K-Map erzeugt (Orbit ohne Spalten; nur 3 Stufen) | **nein** (fehlt) | nicht messbar, weil dieser Mapper keine 4K-Map erzeugt (Orbit ohne Spalten; nur 3 Stufen) |
| Spielbarkeit | Regelverletzungen (AmChart.lint), Summe | 0 | nicht messbar, weil die Noten keine Spalten haben | **nein** (fehlt) | nicht messbar, weil die Noten keine Spalten haben |
| Dauer | ganzer Ablauf je Song, auf 4 min umgerechnet, 95. Perzentil (Maximum) | ≤ 15 s | 2.1 s (2.5 s; Median roh 0.9 s; n=48) | ja | 2.1 s (3.8 s; Median roh 0.9 s; n=122) |

**2 von 14 Zielen erreicht.**

Zusatzwerte (Prüf-Menge): systematischer Versatz (Median mit Vorzeichen, + = erzeugt zu spät) -5.1 ms; Noten auf dem eigenen Gitter 100.0 %.

### Noten je Profil, Prüf-Menge

| Profil | Paare | auf Menschen-Note | Menschen-Noten getroffen | Dichte-Korrelation | Notenzahl erzeugt/Mensch | Sterne im Band | Hinweis |
|---|---|---|---|---|---|---|---|
| Easy | 31 | 40.9 % | 15.6 % | 0.216 | 0.37 | – |  |
| Normal | 35 | 53.8 % | 21.3 % | 0.247 | 0.35 | – |  |
| Hard | 36 | 68.3 % | 35.4 % | 0.271 | 0.5 | – |  |
| Insane | 0 | – | – | – | – | – | Profil fehlt in diesem Mapper |
| Expert | 0 | – | – | – | – | – | Profil fehlt in diesem Mapper |

### Schlechteste 20 Songs je Kennzahl

(P) = Prüf-Menge, (A) = Abstimm-Menge. Ursache = aus den Messwerten abgeleitete Einordnung, keine Hörprüfung.

### Tempo falsch (Maps mit einem Tempo)

| Song | BPM Map | BPM erzeugt | Ursache |
|---|---|---|---|
| mirror_2438724 (A) | 390.0 | 113.21 | daneben: erzeugt 113.21 BPM, Map 390.00 BPM |
| mirror_2506453 (A) | 75.0 | 150.02 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
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
| mirror_2096660 (A) | 185.0 | 92.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2454631 (A) | 182.0 | 91.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_1746870 (A) | 215.0 | 107.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2292728 (A) | 202.0 | 101.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2400069 (A) | 185.0 | 92.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2489537 (A) | 200.0 | 100.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |

### Offset-Fehler

| Song | Fehler ms (+ = zu spät) | Ursache |
|---|---|---|
| mirror_2295373 (P) | +162.2 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2079518 (A) | -162.1 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_155749 (P) | -161.2 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2425501 (A) | -158.1 | Viertelschlag versetzt |
| 2246587 Mitsukiyo - Mikansei Romantic (feat. kotono) (A) | +139.5 | Viertelschlag versetzt |
| mirror_2269020 (P) | -123.5 | Viertelschlag versetzt |
| mirror_206887 (A) | -118.1 | Viertelschlag versetzt |
| mirror_2398569 (A) | -113.7 | Viertelschlag versetzt |
| mirror_2485116 (A) | +112.9 | Viertelschlag versetzt |
| mirror_2490158 (P) | -112.6 | Viertelschlag versetzt |
| mirror_2338601 (P) | -110.0 | Viertelschlag versetzt |
| mirror_126752 (A) | -108.3 | Viertelschlag versetzt |
| mirror_105186 (A) | -105.8 | Viertelschlag versetzt |
| 1614100 FROL - BEAKER (roop remix) (P) | -103.9 | Viertelschlag versetzt |
| 2032982 MYUKKE. - Anti Safety Zone (A) | -97.8 | Viertelschlag versetzt |
| mirror_2483415 (A) | -97.5 | Viertelschlag versetzt |
| mirror_2468221 (P) | -94.3 | Viertelschlag versetzt |
| mirror_200552 (A) | -91.7 | Viertelschlag versetzt |
| mirror_176446 (A) | -90.4 | Viertelschlag versetzt |
| mirror_2417924 (A) | -90.2 | Viertelschlag versetzt |

### Drift

| Song | Drift ms | Ursache |
|---|---|---|
| mirror_2426813 (A) | -54.8 | Tempo um 0.0831 % daneben (erzeugt 130.108, Map 130.000 BPM) |
| mirror_2017220 (A) | -43.8 | Tempo um 0.0103 % daneben (erzeugt 145.015, Map 145.000 BPM) |
| mirror_2514525 (A) | +19.8 | Tempo um -0.0213 % daneben (erzeugt 136.171, Map 136.200 BPM) |
| mirror_206887 (A) | -19.1 | Tempo um 0.0252 % daneben (erzeugt 135.034, Map 135.000 BPM) |
| mirror_157896 (A) | +8.8 | Tempo um -0.0071 % daneben (erzeugt 139.990, Map 140.000 BPM) |
| mirror_126752 (A) | +6.3 | Tempo um -0.0062 % daneben (erzeugt 129.992, Map 130.000 BPM) |
| mirror_2119120 (A) | -6.2 | Tempo um 0.0158 % daneben (erzeugt 95.015, Map 95.000 BPM) |
| mirror_2288732 (A) | +6.2 | Tempo um -0.0061 % daneben (erzeugt 179.989, Map 180.000 BPM) |
| mirror_2515013 (A) | +6.1 | Tempo um -0.0065 % daneben (erzeugt 122.132, Map 122.140 BPM) |
| mirror_2417924 (A) | -5.8 | Tempo um 0.0054 % daneben (erzeugt 168.009, Map 168.000 BPM) |
| 2134137 Akiri feat. InabaYap - Tonight We Fly (A) | -5.3 | Tempo um 0.0037 % daneben (erzeugt 161.006, Map 161.000 BPM) |
| mirror_2490158 (P) | -5.2 | Tempo um 0.0059 % daneben (erzeugt 135.008, Map 135.000 BPM) |
| mirror_159068 (A) | -5.0 | Tempo um 0.0034 % daneben (erzeugt 176.006, Map 176.000 BPM) |
| 2355814 NANAOAKARI - Ashita no Watashi ni Sachi Are (P) | +4.8 | Tempo um -0.0023 % daneben (erzeugt 131.997, Map 132.000 BPM) |
| mirror_2496763 (A) | -4.8 | Tempo um 0.0054 % daneben (erzeugt 184.010, Map 184.000 BPM) |
| mirror_2493152 (P) | +4.5 | Tempo um -0.0046 % daneben (erzeugt 173.992, Map 174.000 BPM) |
| mirror_2436239 (A) | -4.4 | Tempo um 0.0040 % daneben (erzeugt 174.007, Map 174.000 BPM) |
| mirror_2225653 (A) | +4.0 | Tempo um -0.0019 % daneben (erzeugt 156.997, Map 157.000 BPM) |
| mirror_2481624 (A) | +4.0 | Tempo um -0.0024 % daneben (erzeugt 169.996, Map 170.000 BPM) |
| 2134266 Akiri - Beyond Wood (P) | -3.9 | Tempo um 0.0035 % daneben (erzeugt 171.006, Map 171.000 BPM) |

### Tempowechsel nicht getroffen

| Song | Segmente Map | Segmente erzeugt | Ursache |
|---|---|---|---|
| 1787141 Marmalade butcher - Immortality Math Club (A) | 12 | 1 | kein Tempowechsel erkannt; Tempo in Segment 12 falsch (Map 210.00 BPM, erzeugt 134.67) |
| 315435 UNDEAD CORPORATION - The Empress scream off ver (P) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 270.00 BPM, erzeugt 135.14) |
| 347453 Igorrr & Ruby My Dear - Figue Folle (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 3 falsch (Map 188.00 BPM, erzeugt 94.00) |
| mirror_1178589 (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 3 falsch (Map 192.00 BPM, erzeugt 143.97) |
| mirror_2511692 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 186.70 BPM, erzeugt 93.33) |
| mirror_2528018 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 210.00 BPM, erzeugt 105.00) |
| 2298540 Omerta - Charade (feat. Vincente Void _ Hash Gordon) (A) | 8 | 1 | kein Tempowechsel erkannt; Tempo in Segment 8 falsch (Map 120.00 BPM, erzeugt 179.96) |
| mirror_1294997 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 77.00 BPM, erzeugt 154.01) |
| mirror_2528075 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 134.00 BPM, erzeugt 131.94) |
| 2155333 pan - Pastel Sprinkles (A) | 2 | 1 | kein Tempowechsel erkannt; Grenze bei 108608 ms fehlt |
| 2219350 Toromaru - Uncharted Sky (A) | 14 | 1 | kein Tempowechsel erkannt; Grenze bei 13709 ms fehlt |
| mirror_2198573 (A) | 3 | 1 | kein Tempowechsel erkannt; Grenze bei 80159 ms fehlt |

### Taktanfang falsch

| Song | Ursache |
|---|---|
| mirror_2295373 (P) | um -1 Schlag/Schläge verschoben |
| mirror_155749 (P) | um -1 Schlag/Schläge verschoben |
| mirror_2269020 (P) | um 1 Schlag/Schläge verschoben |
| mirror_206887 (A) | um 1 Schlag/Schläge verschoben |
| mirror_2398569 (A) | um 1 Schlag/Schläge verschoben |
| mirror_2485116 (A) | um -2 Schlag/Schläge verschoben |
| 1614100 FROL - BEAKER (roop remix) (P) | um -1 Schlag/Schläge verschoben |
| 2032982 MYUKKE. - Anti Safety Zone (A) | um 1 Schlag/Schläge verschoben |
| mirror_2483415 (A) | um -1 Schlag/Schläge verschoben |
| mirror_2468221 (P) | um 1 Schlag/Schläge verschoben |
| mirror_200552 (A) | um -1 Schlag/Schläge verschoben |
| mirror_176446 (A) | um 1 Schlag/Schläge verschoben |
| mirror_2417924 (A) | um 1 Schlag/Schläge verschoben |
| mirror_2407955 (A) | um -1 Schlag/Schläge verschoben |
| mirror_2513755 (P) | um 1 Schlag/Schläge verschoben |
| mirror_2493152 (P) | um 1 Schlag/Schläge verschoben |
| 2375072 Lime - Aurora (A) | um -1 Schlag/Schläge verschoben |
| mirror_2426813 (A) | um -2 Schlag/Schläge verschoben |
| mirror_2496763 (A) | um 1 Schlag/Schläge verschoben |
| 2290237 Junk - Life is PIANO (P) | um -2 Schlag/Schläge verschoben |

### Noten: erzeugte Noten ohne Menschen-Note (Hard)

| Song | Anteil auf Menschen-Note | Menschen-Diff | Ursache |
|---|---|---|---|
| mirror_2096660 (A) | 0.0 % | Revv's Hard | Tempo falsch (x0.500) |
| mirror_2426813 (A) | 9.2 % | Insane | Versatz +37 ms |
| mirror_2523688 (P) | 13.8 % | Insane | Tempo falsch (x1.371) |
| 309328 xi - Hesperides (A) | 14.7 % | Zan's Hard | Tempo falsch (x0.762) |
| mirror_240415 (P) | 20.1 % | puxtu's HD | Map mit Effekt-Linien |
| mirror_2488299 (A) | 21.7 % | HARD JUMP!! | Tempo falsch (x0.756) |
| mirror_2422509 (A) | 21.9 % | hard | Tempo falsch (x1.468) |
| mirror_2504508 (A) | 22.2 % | ~=H / Illusions=~ | Tempo falsch (x0.674) |
| mirror_2378766 (A) | 22.4 % | hard... | Tempo falsch (x0.657) |
| 362395 sweet ARMS - Installation (P) | 23.1 % | Emperor of Time | Tempo falsch (x0.759) |
| 2081438 Hino Isuka - Dreamin_ attraction__ (A) | 23.6 % | Present!! | Tempo falsch (x0.665) |
| 315435 UNDEAD CORPORATION - The Empress scream off ver (P) | 25.5 % | MX | Tempowechsel nicht getroffen |
| mirror_2511692 (A) | 26.7 % | Maiiy's Insane | Tempowechsel nicht getroffen |
| mirror_2491936 (A) | 27.0 % | fall into the sky | Tempo falsch (x1.373) |
| mirror_2240934 (P) | 34.4 % | dragon's obsession | Tempo falsch (x1.500) |
| mirror_2532676 (A) | 34.4 % | Good Afternoon | Tempo falsch (x1.500) |
| mirror_2438724 (A) | 34.7 % | Hyper | Tempo falsch (x0.290) |
| mirror_2182334 (A) | 39.6 % | HYPER | Tempo falsch (x0.750) |
| 1606431 Zekk - Fluctuation (P) | 39.7 % | Hyper | Tempo falsch (x0.750) |
| mirror_1178589 (A) | 42.3 % | _VK's Hard | Tempowechsel nicht getroffen |

### Noten: Menschen-Noten nicht getroffen (Hard)

| Song | Anteil getroffen | Menschen-Diff | Ursache |
|---|---|---|---|
| mirror_2096660 (A) | 0.0 % | Revv's Hard | Tempo falsch (x0.500) |
| mirror_2426813 (A) | 3.7 % | Insane | Versatz +37 ms |
| mirror_2523688 (P) | 7.0 % | Insane | Tempo falsch (x1.371) |
| 2081438 Hino Isuka - Dreamin_ attraction__ (A) | 8.5 % | Present!! | Tempo falsch (x0.665) |
| 309328 xi - Hesperides (A) | 8.5 % | Zan's Hard | Tempo falsch (x0.762) |
| mirror_2504508 (A) | 9.4 % | ~=H / Illusions=~ | Tempo falsch (x0.674) |
| mirror_2378766 (A) | 9.6 % | hard... | Tempo falsch (x0.657) |
| 315435 UNDEAD CORPORATION - The Empress scream off ver (P) | 9.6 % | MX | Tempowechsel nicht getroffen |
| mirror_2491936 (A) | 9.6 % | fall into the sky | Tempo falsch (x1.373) |
| mirror_2438724 (A) | 9.8 % | Hyper | Tempo falsch (x0.290) |
| mirror_240415 (P) | 10.1 % | puxtu's HD | Map mit Effekt-Linien |
| 362395 sweet ARMS - Installation (P) | 10.3 % | Emperor of Time | Tempo falsch (x0.759) |
| mirror_2488299 (A) | 10.4 % | HARD JUMP!! | Tempo falsch (x0.756) |
| mirror_2422509 (A) | 11.3 % | hard | Tempo falsch (x1.468) |
| mirror_2511692 (A) | 12.3 % | Maiiy's Insane | Tempowechsel nicht getroffen |
| 1606431 Zekk - Fluctuation (P) | 14.0 % | Hyper | Tempo falsch (x0.750) |
| mirror_2182334 (A) | 15.8 % | HYPER | Tempo falsch (x0.750) |
| mirror_2485116 (A) | 16.2 % | HAHA | Versatz +113 ms |
| mirror_2278487 (P) | 17.8 % | 29/16 | Map mit Effekt-Linien |
| mirror_2509473 (A) | 19.6 % | S4 E3: INSANE delusions | Tempo falsch (x0.750) |

### Dichtekurve

| Song | Profil | Korrelation | Ursache |
|---|---|---|---|
| mirror_2240934 (P) | Hard | -0.467 | Tempo falsch (x1.500) |
| 2280366 rejection - Calling (osu_ edit) (P) | Normal | -0.236 | Notenzahl erzeugt/Mensch = 0.31 |
| mirror_2506453 (A) | Normal | -0.174 | Tempo falsch (x2.000) |
| mirror_126752 (A) | Easy | -0.162 | Versatz -108 ms |
| mirror_2434745 (A) | Easy | -0.161 | Tempo falsch (x0.500) |
| mirror_2489537 (A) | Normal | -0.142 | Tempo falsch (x0.500) |
| mirror_2240934 (P) | Normal | -0.14 | Tempo falsch (x1.500) |
| mirror_2198573 (A) | Normal | -0.14 | Tempowechsel nicht getroffen |
| 2310809 Trina Lydia - TETRATONE ALTiSSiMO (P) | Hard | -0.138 | Versatz -77 ms |
| mirror_2407955 (A) | Normal | -0.138 | Versatz +90 ms |
| mirror_2458045 (A) | Easy | -0.127 | Notenzahl erzeugt/Mensch = 0.49 |
| mirror_2403887 (P) | Normal | -0.121 | Notenzahl erzeugt/Mensch = 0.35 |
| mirror_200552 (A) | Easy | -0.095 | Versatz -92 ms |
| mirror_126752 (A) | Normal | -0.094 | Versatz -108 ms |
| mirror_2119120 (A) | Normal | -0.09 | Notenzahl erzeugt/Mensch = 0.30 |
| 2303845 splitter - NERF THIS_ (P) | Hard | -0.088 | Notenzahl erzeugt/Mensch = 0.35 |
| mirror_2489520 (A) | Easy | -0.086 | Notenzahl erzeugt/Mensch = 0.38 |
| mirror_2509473 (A) | Hard | -0.086 | Tempo falsch (x0.750) |
| 2081438 Hino Isuka - Dreamin_ attraction__ (A) | Easy | -0.083 | Tempo falsch (x0.665) |
| mirror_200552 (A) | Hard | -0.068 | Versatz -92 ms |

### Holds

Entfällt: dieser Mapper erzeugt keine Holds.

### Kiai

Entfällt: dieser Mapper erzeugt kein Kiai.

### Sterne, Regelverletzungen

Entfällt: dieser Mapper erzeugt keine 4K-Map (keine Spalten).

### Dauer

| Song | s auf 4 min | s roh | Songlänge s | Ursache |
|---|---|---|---|---|
| mirror_2305676 (A) | 3.8 | 1.5 | 95 | größter Anteil: decode (0.9 s) |
| mirror_2506744 (P) | 2.5 | 0.4 | 34 | größter Anteil: grid (0.2 s) |
| mirror_2294669 (P) | 2.5 | 0.7 | 63 | größter Anteil: grid (0.5 s) |
| mirror_2079518 (A) | 2.3 | 0.7 | 68 | größter Anteil: grid (0.5 s) |
| mirror_2422509 (A) | 2.3 | 0.4 | 41 | größter Anteil: grid (0.3 s) |
| mirror_105186 (A) | 2.2 | 0.4 | 43 | größter Anteil: grid (0.3 s) |
| mirror_2516512 (A) | 2.1 | 0.5 | 63 | größter Anteil: grid (0.4 s) |
| mirror_2278487 (P) | 2.1 | 0.6 | 69 | größter Anteil: grid (0.5 s) |
| mirror_2496763 (A) | 2.1 | 0.8 | 90 | größter Anteil: grid (0.6 s) |
| mirror_2306091 (A) | 2.1 | 0.8 | 96 | größter Anteil: grid (0.7 s) |
| mirror_2511692 (A) | 2.1 | 0.5 | 59 | größter Anteil: grid (0.3 s) |
| mirror_2039039 (P) | 2.0 | 0.8 | 91 | größter Anteil: grid (0.6 s) |
| mirror_2182334 (A) | 2.0 | 0.8 | 93 | größter Anteil: grid (0.6 s) |
| mirror_2092603 (A) | 2.0 | 0.8 | 98 | größter Anteil: grid (0.7 s) |
| mirror_2323003 (A) | 2.0 | 1.3 | 159 | größter Anteil: grid (1.1 s) |
| mirror_2521712 (A) | 2.0 | 0.7 | 91 | größter Anteil: grid (0.6 s) |
| mirror_2119120 (A) | 2.0 | 0.4 | 48 | größter Anteil: grid (0.3 s) |
| mirror_2396967 (A) | 2.0 | 0.8 | 102 | größter Anteil: grid (0.7 s) |
| mirror_2509474 (A) | 2.0 | 0.9 | 111 | größter Anteil: grid (0.7 s) |
| mirror_2514525 (A) | 1.9 | 0.8 | 99 | größter Anteil: grid (0.6 s) |

## Mapper „neu“: neue Module (AmGrid, AmFeatures, AmChart, AutoMapper4K)

- Gemessen: 255 Sets (Prüf-Menge 79, Abstimm-Menge 176); 0 ohne rote Linie übersprungen; Erzeugung fehlgeschlagen bei 0 (Prüf) / 0 (Abstimm).
- Laufzeit: 895 s für 260 Sets
- Maps-Ordner: 260 .osz
- Nicht gemessen: 5 Sets nicht lesbar oder ohne Diff mit Noten, zählen in keiner Kennzahl: mirror_2538892 (Konnte .osz nicht oeffnen (Fehler 1)), mirror_2556039 (Konnte .osz nicht oeffnen (Fehler 1)), mirror_2597846 (Konnte .osz nicht oeffnen (Fehler 1)), mirror_2598366 (Konnte .osz nicht oeffnen (Fehler 1)), mirror_2600955 (Konnte .osz nicht oeffnen (Fehler 1))
- Weg: AutoMapper4K.generate, erzeugtes Set zurückgelesen

### Ziel-Tabelle, Prüf-Menge

| Bereich | Kennzahl | Ziel | Ist (Prüf-Menge) | erreicht | Ist (Abstimm-Menge) |
|---|---|---|---|---|---|
| Takt | Tempo exakt (±0,5 %), Maps mit einem Tempo | ≥ 95 % | 87.9 % (n=58) | **nein** | 89.3 % (n=150) |
| Takt | Tempo exakt oder gemeldete Alternative trifft | ≥ 99 % | 98.3 % (n=58) | **nein** | 99.3 % (n=150) |
| Takt | Offset-Fehler, Median / 95. Perzentil (nur richtiges Tempo) | ≤ 4 ms / ≤ 12 ms | 3.0 ms / 163.6 ms (n=51) | **nein** | 3.9 ms / 132.2 ms (n=134) |
| Takt | Drift über den Song, 95. Perzentil (Median / Maximum / Anteil ≤ 10 ms) | ≤ 10 ms | 0.4 ms (0.0 ms / 290.5 ms / 98.0 %; n=51) | ja | 8.2 ms (0.0 ms / 332.0 ms / 95.5 %; n=134) |
| Takt | Tempowechsel: Grenzen ±1 Schlag und Tempo je Segment | ≥ 80 % | 0.0 % (n=6; 15 Maps mit Effekt-Linien nicht gewertet) | **nein** | 0.0 % (n=15; 11 Maps mit Effekt-Linien nicht gewertet) |
| Takt | Taktanfang (Downbeat) stimmt | ≥ 85 % | 70.6 % (n=51) | **nein** | 75.4 % (n=134) |
| Noten | erzeugte Noten auf Menschen-Note (±15 ms), Hard | ≥ 85 % | 75.3 % (n=64, Notenzahl erzeugt/Mensch 0.74) | **nein** | 71.2 % (n=148, Notenzahl erzeugt/Mensch 0.78) |
| Noten | Menschen-Noten getroffen (±15 ms), Hard | ≥ 75 % | 56.0 % (n=64) | **nein** | 55.6 % (n=148) |
| Noten | Korrelation der Dichtekurve (2-s-Fenster), alle Profile | ≥ 0,8 | 0.558 (n=264 Paare) | **nein** | 0.525 (n=600 Paare) |
| Holds | erzeugte Holds überlappen Holds der Map (Maps ≥ 10 % Holds) | ≥ 60 % | 53.8 % (n=157 Paare) | **nein** | 50.8 % (n=330 Paare) |
| Kiai | Überlappung der Kiai-Abschnitte (IoU) | ≥ 0,6 | 0.258 (n=79) | **nein** | 0.285 (n=176) |
| Stufen | Sterne im Band, schlechtestes Profil | ≥ 90 % | 68.4 % (Easy 89.9 %, Normal 78.5 %, Hard 92.4 %, Insane 81.0 %, Expert 68.4 %; n=395 Diffs) | **nein** | 70.5 % (Easy 92.6 %, Normal 75.0 %, Hard 90.9 %, Insane 81.3 %, Expert 70.5 %; n=880 Diffs) |
| Spielbarkeit | Regelverletzungen (AmChart.lint), Summe | 0 | 0 in 395 Diffs | ja | 0 in 880 Diffs |
| Dauer | ganzer Ablauf je Song, auf 4 min umgerechnet, 95. Perzentil (Maximum) | ≤ 15 s | 7.5 s (10.7 s; Median roh 3.2 s; n=79) | ja | 7.4 s (8.3 s; Median roh 3.2 s; n=176) |

**3 von 14 Zielen erreicht.**

Zusatzwerte (Prüf-Menge): systematischer Versatz (Median mit Vorzeichen, + = erzeugt zu spät) 0.9 ms; Noten auf dem eigenen Gitter 100.0 %.

### Noten je Profil, Prüf-Menge

| Profil | Paare | auf Menschen-Note | Menschen-Noten getroffen | Dichte-Korrelation | Notenzahl erzeugt/Mensch | Sterne im Band | Hinweis |
|---|---|---|---|---|---|---|---|
| Easy | 54 | 68.7 % | 50.7 % | 0.397 | 0.75 | 89.9 % (Median 1.55, n=79) |  |
| Normal | 62 | 74.9 % | 54.9 % | 0.5 | 0.74 | 78.5 % (Median 2.32, n=79) |  |
| Hard | 64 | 75.3 % | 56.0 % | 0.585 | 0.74 | 92.4 % (Median 3.36, n=79) |  |
| Insane | 54 | 73.3 % | 57.2 % | 0.667 | 0.79 | 81.0 % (Median 4.33, n=79) |  |
| Expert | 30 | 70.9 % | 55.7 % | 0.711 | 0.81 | 68.4 % (Median 5.43, n=79) |  |

### Schlechteste 20 Songs je Kennzahl

(P) = Prüf-Menge, (A) = Abstimm-Menge. Ursache = aus den Messwerten abgeleitete Einordnung, keine Hörprüfung.

### Tempo falsch (Maps mit einem Tempo)

| Song | BPM Map | BPM erzeugt | Ursache |
|---|---|---|---|
| mirror_2438724 (A) | 390.0 | 97.5 | daneben: erzeugt 97.50 BPM, Map 390.00 BPM |
| mirror_349208 (A) | 256.0 | 111.52 | daneben: erzeugt 111.52 BPM, Map 256.00 BPM |
| mirror_2119120 (A) | 95.0 | 190.31 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2511666 (A) | 185.0 | 92.5 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2552898 (A) | 90.0 | 180.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2491936 (A) | 110.0 | 220.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2523688 (P) | 105.0 | 210.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2506744 (P) | 93.0 | 186.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_476691 (A) | 100.0 | 200.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_283841 (A) | 200.0 | 100.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2588413 (P) | 200.0 | 100.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2534361 (A) | 100.0 | 200.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2506453 (A) | 75.0 | 150.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2217940 (A) | 240.0 | 120.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2545184 (P) | 218.0 | 109.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2578511 (P) | 108.0 | 216.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |
| mirror_2318291 (P) | 270.0 | 135.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2591197 (A) | 260.0 | 130.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2541937 (P) | 342.0 | 171.0 | Vielfaches: erzeugtes Tempo x2.0 wäre richtig |
| mirror_2545208 (A) | 104.0 | 208.0 | Vielfaches: erzeugtes Tempo x0.5 wäre richtig |

### Offset-Fehler

| Song | Fehler ms (+ = zu spät) | Ursache |
|---|---|---|
| mirror_2537768 (P) | +247.2 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_206887 (A) | -217.7 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2400881 (A) | +199.6 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2513755 (P) | -174.9 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2586880 (P) | +168.8 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_126752 (A) | +161.8 | Gitter später als die Map |
| mirror_155749 (P) | -158.4 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_368064 (A) | +152.8 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2388455 (A) | -150.7 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| 2081438 Hino Isuka - Dreamin_ attraction__ (A) | +143.9 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| 309881 goreshit - burn this moment into the retina of my eye (A) | -133.7 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2607616 (A) | -131.5 | halber Schlag versetzt (Gitter auf dem Off-Beat) |
| mirror_2079518 (A) | +64.1 | Viertelschlag versetzt |
| mirror_2422509 (A) | +45.2 | Gitter später als die Map |
| mirror_2573147 (A) | +39.8 | Gitter später als die Map |
| 2134137 Akiri feat. InabaYap - Tonight We Fly (A) | -21.6 | Gitter früher als die Map |
| 2246587 Mitsukiyo - Mikansei Romantic (feat. kotono) (A) | +19.5 | Gitter später als die Map |
| mirror_407186 (A) | -19.2 | Gitter früher als die Map |
| mirror_324288 (A) | +18.5 | Gitter später als die Map |
| mirror_2096660 (A) | -17.3 | Gitter früher als die Map |

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
| mirror_2528018 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 210.00 BPM, erzeugt 105.00) |
| 315435 UNDEAD CORPORATION - The Empress scream off ver (P) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 270.00 BPM, erzeugt 135.00) |
| mirror_2555375 (A) | 10 | 9 | Grenze bei 78415 ms fehlt |
| mirror_2559592 (P) | 3 | 5 | Tempo in Segment 1 falsch (Map 170.00 BPM, erzeugt 170.00) |
| 2298540 Omerta - Charade (feat. Vincente Void _ Hash Gordon) (A) | 8 | 1 | kein Tempowechsel erkannt; Tempo in Segment 8 falsch (Map 120.00 BPM, erzeugt 180.00) |
| mirror_1294997 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 77.00 BPM, erzeugt 154.00) |
| mirror_2643833 (P) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 77.50 BPM, erzeugt 165.00) |
| mirror_2511692 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 146.70 BPM, erzeugt 186.64) |
| mirror_2528075 (A) | 2 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 134.00 BPM, erzeugt 132.00) |
| 347453 Igorrr & Ruby My Dear - Figue Folle (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 141.00 BPM, erzeugt 188.00) |
| mirror_1178589 (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 184.00 BPM, erzeugt 192.00) |
| mirror_2584545 (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 1 falsch (Map 162.00 BPM, erzeugt 160.32) |
| mirror_2576239 (A) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 280.00 BPM, erzeugt 140.00) |
| mirror_2563805 (P) | 3 | 1 | kein Tempowechsel erkannt; Tempo in Segment 2 falsch (Map 168.00 BPM, erzeugt 180.00) |
| 1787141 Marmalade butcher - Immortality Math Club (A) | 12 | 1 | kein Tempowechsel erkannt; Tempo in Segment 12 falsch (Map 210.00 BPM, erzeugt 205.00) |
| mirror_2572994 (P) | 2 | 1 | kein Tempowechsel erkannt; Grenze bei 129049 ms fehlt |
| mirror_2541848 (P) | 4 | 1 | kein Tempowechsel erkannt; Grenze bei 12073 ms fehlt |
| 2155333 pan - Pastel Sprinkles (A) | 2 | 1 | kein Tempowechsel erkannt; Grenze bei 108608 ms fehlt |
| mirror_2198573 (A) | 3 | 1 | kein Tempowechsel erkannt; Grenze bei 80159 ms fehlt |

### Taktanfang falsch

| Song | Ursache |
|---|---|
| mirror_206887 (A) | um -1 Schlag/Schläge verschoben |
| mirror_2400881 (A) | um -2 Schlag/Schläge verschoben |
| mirror_2513755 (P) | um -1 Schlag/Schläge verschoben |
| mirror_155749 (P) | um 1 Schlag/Schläge verschoben |
| mirror_368064 (A) | um -1 Schlag/Schläge verschoben |
| mirror_2388455 (A) | um 2 Schlag/Schläge verschoben |
| mirror_2607616 (A) | um 1 Schlag/Schläge verschoben |
| mirror_2422509 (A) | um -1 Schlag/Schläge verschoben |
| mirror_2573147 (A) | um 1 Schlag/Schläge verschoben |
| 2246587 Mitsukiyo - Mikansei Romantic (feat. kotono) (A) | um -2 Schlag/Schläge verschoben |
| 2375072 Lime - Aurora (A) | um -1 Schlag/Schläge verschoben |
| mirror_2493125 (A) | um 2 Schlag/Schläge verschoben |
| mirror_2539716 (A) | um -2 Schlag/Schläge verschoben |
| 844183 tatatat - e (A) | Taktart 4 statt 6 |
| mirror_79038 (P) | um -2 Schlag/Schläge verschoben |
| mirror_2398569 (A) | um -2 Schlag/Schläge verschoben |
| 309328 xi - Hesperides (A) | um 1 Schlag/Schläge verschoben |
| 1708332 MisoilePunch _pan soe_ - MeTear_n TruX (P) | um -2 Schlag/Schläge verschoben |
| mirror_2617747 (P) | um -1 Schlag/Schläge verschoben |
| mirror_2587256 (A) | um -2 Schlag/Schläge verschoben |

### Noten: erzeugte Noten ohne Menschen-Note (Hard)

| Song | Anteil auf Menschen-Note | Menschen-Diff | Ursache |
|---|---|---|---|
| mirror_2096660 (A) | 0.0 % | Revv's Hard | Versatz -17 ms |
| mirror_407186 (A) | 0.4 % | 4K Hard | Versatz -19 ms |
| mirror_2506453 (A) | 16.4 % | Your blurred shape, behind the cold mist // Insane | Tempo falsch (x2.000) |
| mirror_2555375 (A) | 19.1 % | insane | Tempowechsel nicht getroffen |
| mirror_126752 (A) | 24.5 % | 4K HD | Versatz +162 ms |
| mirror_2422509 (A) | 24.8 % | hard | Versatz +45 ms |
| mirror_2036133 (P) | 26.3 % | Insane | Map mit Effekt-Linien |
| mirror_349208 (A) | 27.8 % | ADVANCED | Tempo falsch (x0.436) |
| mirror_2573147 (A) | 29.4 % | NEVER ENDING SLEEPLESS CYCLE | Versatz +40 ms |
| 171880 xi - Happy End of the World (P) | 29.9 % | 4K Hard | Map mit Effekt-Linien |
| mirror_2079518 (A) | 30.6 % | tapperruiii's Ascension | Versatz +64 ms |
| mirror_2559655 (A) | 30.7 % | hard | Map mit Effekt-Linien |
| mirror_2564470 (A) | 33.3 % | Fading Memories. | Map mit Effekt-Linien |
| mirror_2584545 (A) | 34.4 % | I AM A LARPITECT | Tempowechsel nicht getroffen |
| mirror_2278487 (P) | 34.5 % | 29/16 | Map mit Effekt-Linien |
| mirror_274111 (P) | 38.0 % | Feru's HD | Map mit Effekt-Linien |
| mirror_2119120 (A) | 41.9 % | Moyai | Tempo falsch (x2.003) |
| mirror_324288 (A) | 44.1 % | Starry's 4K Lv.15 | Versatz +19 ms |
| mirror_2240934 (P) | 53.5 % | dragon's obsession | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_2329176 (A) | 53.9 % | rinstea's Hard | Notenzahl erzeugt/Mensch = 0.68 |

### Noten: Menschen-Noten nicht getroffen (Hard)

| Song | Anteil getroffen | Menschen-Diff | Ursache |
|---|---|---|---|
| mirror_2096660 (A) | 0.0 % | Revv's Hard | Versatz -17 ms |
| mirror_407186 (A) | 0.5 % | 4K Hard | Versatz -19 ms |
| mirror_2555375 (A) | 8.4 % | insane | Tempowechsel nicht getroffen |
| mirror_2278487 (P) | 15.6 % | 29/16 | Map mit Effekt-Linien |
| mirror_2422509 (A) | 16.5 % | hard | Versatz +45 ms |
| 2150831 sath4 - _3_006 w_yax03 (A) | 16.5 % | Happy Love Expert | Notenzahl erzeugt/Mensch = 0.19 |
| mirror_349208 (A) | 17.9 % | ADVANCED | Tempo falsch (x0.436) |
| mirror_2506453 (A) | 18.3 % | Your blurred shape, behind the cold mist // Insane | Tempo falsch (x2.000) |
| mirror_2036133 (P) | 19.4 % | Insane | Map mit Effekt-Linien |
| mirror_126752 (A) | 19.7 % | 4K HD | Versatz +162 ms |
| mirror_2119120 (A) | 20.4 % | Moyai | Tempo falsch (x2.003) |
| mirror_2559655 (A) | 24.3 % | hard | Map mit Effekt-Linien |
| mirror_2079518 (A) | 24.3 % | tapperruiii's Ascension | Versatz +64 ms |
| mirror_2573147 (A) | 25.6 % | NEVER ENDING SLEEPLESS CYCLE | Versatz +40 ms |
| mirror_2584545 (A) | 25.8 % | I AM A LARPITECT | Tempowechsel nicht getroffen |
| mirror_2141771 (A) | 27.2 % | Insane, | Notenzahl erzeugt/Mensch = 0.32 |
| 171880 xi - Happy End of the World (P) | 30.2 % | 4K Hard | Map mit Effekt-Linien |
| mirror_274111 (P) | 30.4 % | Feru's HD | Map mit Effekt-Linien |
| mirror_324288 (A) | 30.5 % | Starry's 4K Lv.15 | Versatz +19 ms |
| mirror_2351212 (A) | 31.3 % | Hard | Notenzahl erzeugt/Mensch = 0.43 |

### Dichtekurve

| Song | Profil | Korrelation | Ursache |
|---|---|---|---|
| mirror_2119120 (A) | Easy | -0.602 | Tempo falsch (x2.003) |
| mirror_2555375 (A) | Normal | -0.438 | Tempowechsel nicht getroffen |
| mirror_2555375 (A) | Hard | -0.392 | Tempowechsel nicht getroffen |
| mirror_2119120 (A) | Hard | -0.375 | Tempo falsch (x2.003) |
| mirror_2489537 (A) | Insane | -0.36 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_2119120 (A) | Normal | -0.326 | Tempo falsch (x2.003) |
| 2280366 rejection - Calling (osu_ edit) (P) | Easy | -0.289 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_2489537 (A) | Hard | -0.247 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_2555375 (A) | Insane | -0.186 | Tempowechsel nicht getroffen |
| mirror_2489537 (A) | Normal | -0.164 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_2561773 (P) | Normal | -0.149 | Notenzahl erzeugt/Mensch = 0.69 |
| mirror_2527829 (A) | Normal | -0.138 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_159068 (A) | Normal | -0.135 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_2561773 (P) | Easy | -0.133 | Notenzahl erzeugt/Mensch = 0.63 |
| mirror_2217940 (A) | Normal | -0.131 | Tempo falsch (x0.500) |
| mirror_105186 (A) | Normal | -0.128 | Notenzahl erzeugt/Mensch = 0.63 |
| mirror_2338601 (P) | Normal | -0.09 | andere Stellen gewählt als der Mensch (Takt stimmt) |
| mirror_283841 (A) | Easy | -0.088 | Tempo falsch (x0.500) |
| mirror_2490158 (P) | Easy | -0.073 | Notenzahl erzeugt/Mensch = 0.69 |
| mirror_476221 (A) | Normal | -0.061 | andere Stellen gewählt als der Mensch (Takt stimmt) |

### Holds

| Song | Profil | Anteil überlappend | Ursache |
|---|---|---|---|
| mirror_2512348 (P) | Easy | 0.0 % | Holds an anderen Stellen (10 erzeugt) |
| mirror_349208 (A) | Easy | 0.0 % | Holds an anderen Stellen (3 erzeugt) |
| mirror_2545184 (P) | Easy | 0.0 % | Holds an anderen Stellen (1 erzeugt) |
| mirror_2610887 (P) | Hard | 4.3 % | Holds an anderen Stellen (94 erzeugt) |
| mirror_2553525 (A) | Normal | 5.9 % | Holds an anderen Stellen (34 erzeugt) |
| mirror_2327005 (A) | Insane | 6.8 % | Holds an anderen Stellen (146 erzeugt) |
| mirror_2610887 (P) | Insane | 7.2 % | Holds an anderen Stellen (138 erzeugt) |
| mirror_2591197 (A) | Expert | 8.0 % | Holds an anderen Stellen (113 erzeugt) |
| mirror_2591197 (A) | Hard | 8.7 % | Holds an anderen Stellen (92 erzeugt) |
| mirror_2591197 (A) | Insane | 9.1 % | Holds an anderen Stellen (110 erzeugt) |
| mirror_2481624 (A) | Easy | 9.5 % | Holds an anderen Stellen (74 erzeugt) |
| mirror_2610887 (P) | Normal | 9.8 % | Holds an anderen Stellen (51 erzeugt) |
| mirror_2446560 (A) | Insane | 10.5 % | Holds an anderen Stellen (57 erzeugt) |
| mirror_476221 (A) | Easy | 11.1 % | Holds an anderen Stellen (81 erzeugt) |
| 2289293 Tsukasa Kaminose - ruin of opals (Full Ver.) (P) | Insane | 11.2 % | Holds an anderen Stellen (223 erzeugt) |
| mirror_2327005 (A) | Hard | 12.1 % | Holds an anderen Stellen (124 erzeugt) |
| mirror_2545191 (A) | Easy | 12.8 % | Holds an anderen Stellen (78 erzeugt) |
| mirror_2396967 (A) | Insane | 13.3 % | Holds an anderen Stellen (75 erzeugt) |
| mirror_2403887 (P) | Hard | 13.6 % | Holds an anderen Stellen (162 erzeugt) |
| mirror_2583521 (A) | Normal | 13.7 % | Holds an anderen Stellen (51 erzeugt) |

### Kiai

| Song | IoU | Ursache |
|---|---|---|
| mirror_2417924 (A) | 0.0 | Kiai erzeugt (69 s), Map hat keins |
| mirror_2415880 (P) | 0.0 | Kiai erzeugt (61 s), Map hat keins |
| mirror_2540169 (P) | 0.0 | Kiai erzeugt (52 s), Map hat keins |
| mirror_2541305 (A) | 0.0 | Kiai erzeugt (91 s), Map hat keins |
| mirror_2541937 (P) | 0.0 | Kiai erzeugt (23 s), Map hat keins |
| mirror_2396967 (A) | 0.0 | Kiai erzeugt (64 s), Map hat keins |
| mirror_2389146 (A) | 0.0 | Kiai erzeugt (111 s), Map hat keins |
| mirror_2381413 (A) | 0.0 | Kiai erzeugt (32 s), Map hat keins |
| mirror_2542664 (P) | 0.0 | Abschnitte an anderer Stelle |
| mirror_2543663 (P) | 0.0 | Kiai erzeugt (49 s), Map hat keins |
| mirror_2331207 (A) | 0.0 | Kiai erzeugt (98 s), Map hat keins |
| mirror_2329176 (A) | 0.0 | Kiai erzeugt (36 s), Map hat keins |
| mirror_2306554 (A) | 0.0 | Abschnitte an anderer Stelle |
| mirror_2551467 (A) | 0.0 | Kiai erzeugt (42 s), Map hat keins |
| mirror_2552898 (A) | 0.0 | Abschnitte an anderer Stelle |
| mirror_2278487 (P) | 0.0 | Kiai erzeugt (48 s), Map hat keins |
| mirror_2553525 (A) | 0.0 | Abschnitte an anderer Stelle |
| mirror_2555143 (A) | 0.0 | Kiai erzeugt (81 s), Map hat keins |
| mirror_2240934 (P) | 0.0 | Kiai erzeugt (60 s), Map hat keins |
| mirror_2555375 (A) | 0.0 | Kiai erzeugt (64 s), Map hat keins |

### Sterne außerhalb des Bands

| Song | Profil | Sterne | Band | Ursache |
|---|---|---|---|---|
| 844183 tatatat - e (A) | Expert | 1.69 | 5.0–6.0 | zu leicht (70 BPM) |
| 844183 tatatat - e (A) | Insane | 1.48 | 4.0–4.8 | zu leicht (70 BPM) |
| mirror_2551467 (A) | Expert | 2.83 | 5.0–6.0 | zu leicht (144 BPM) |
| 844183 tatatat - e (A) | Hard | 1.2 | 3.0–3.8 | zu leicht (70 BPM) |
| mirror_2561773 (P) | Expert | 3.31 | 5.0–6.0 | zu leicht (149 BPM) |
| mirror_2506744 (P) | Expert | 3.33 | 5.0–6.0 | zu leicht (93 BPM) |
| mirror_2275128 (A) | Expert | 3.42 | 5.0–6.0 | zu leicht (120 BPM) |
| mirror_2278487 (P) | Expert | 3.59 | 5.0–6.0 | zu leicht (126 BPM) |
| mirror_2425501 (A) | Expert | 3.62 | 5.0–6.0 | zu leicht (96 BPM) |
| mirror_2278487 (P) | Insane | 2.66 | 4.0–4.8 | zu leicht (126 BPM) |
| mirror_2551467 (A) | Insane | 2.66 | 4.0–4.8 | zu leicht (144 BPM) |
| mirror_2539345 (A) | Expert | 3.72 | 5.0–6.0 | zu leicht (135 BPM) |
| mirror_2119120 (A) | Expert | 3.72 | 5.0–6.0 | zu leicht (95 BPM) |
| mirror_2493125 (A) | Expert | 3.73 | 5.0–6.0 | zu leicht (128 BPM) |
| mirror_2515013 (A) | Expert | 3.75 | 5.0–6.0 | zu leicht (122 BPM) |
| mirror_2543663 (P) | Expert | 3.78 | 5.0–6.0 | zu leicht (155 BPM) |
| mirror_2620660 (P) | Expert | 3.78 | 5.0–6.0 | zu leicht (160 BPM) |
| mirror_2493125 (A) | Insane | 2.79 | 4.0–4.8 | zu leicht (128 BPM) |
| mirror_2544540 (A) | Expert | 3.82 | 5.0–6.0 | zu leicht (147 BPM) |
| mirror_2526405 (P) | Expert | 3.85 | 5.0–6.0 | zu leicht (122 BPM) |

### Regelverletzungen

Keine Einträge.

### Dauer

| Song | s auf 4 min | s roh | Songlänge s | Ursache |
|---|---|---|---|---|
| 2290237 Junk - Life is PIANO (P) | 10.7 | 5.6 | 126 | – |
| mirror_105186 (A) | 8.3 | 1.5 | 44 | – |
| mirror_2278487 (P) | 8.3 | 2.4 | 70 | – |
| mirror_200552 (A) | 8.2 | 4.0 | 117 | – |
| 2255741 ABSOLUTE CASTAWAY - step by step (P) | 7.9 | 6.5 | 198 | – |
| mirror_2422509 (A) | 7.8 | 1.2 | 36 | – |
| mirror_1294997 (A) | 7.8 | 2.9 | 89 | – |
| mirror_2536648 (A) | 7.7 | 2.7 | 83 | – |
| 1614100 FROL - BEAKER (roop remix) (P) | 7.7 | 3.5 | 109 | – |
| mirror_2288732 (A) | 7.6 | 3.3 | 104 | – |
| mirror_2092603 (A) | 7.6 | 2.8 | 88 | – |
| 2155333 pan - Pastel Sprinkles (A) | 7.6 | 4.7 | 148 | – |
| mirror_2388455 (A) | 7.5 | 5.3 | 168 | – |
| mirror_2506744 (P) | 7.5 | 1.0 | 33 | – |
| 2246587 Mitsukiyo - Mikansei Romantic (feat. kotono) (A) | 7.4 | 8.0 | 262 | – |
| mirror_157896 (A) | 7.4 | 3.9 | 126 | – |
| mirror_2381413 (A) | 7.3 | 4.1 | 135 | – |
| mirror_123456 (A) | 7.3 | 3.6 | 118 | – |
| mirror_2561773 (P) | 7.2 | 1.2 | 40 | – |
| mirror_2378766 (A) | 7.2 | 3.9 | 129 | – |

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
