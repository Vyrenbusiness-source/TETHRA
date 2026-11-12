# Trace-QA (Lesbarkeit, alle lokalen Mania-4K-Maps)

Vergleich vorher (Basis, `main`) gegen nachher (`scripts/trace/trace_path.gd` mit Ausweichen, Backtracking und Haarnadel-Bogen). Notenzeiten bleiben exakt, `MIN_SEG` bleibt 84 px. Erzeugt mit `tools/trace_qa.gd` (Messung in 12 Stuecken, dann `--report`).

## Kurzfassung

| | vorher | nachher |
|---|---|---|
| Maps mit ueberdeckten Pfeilen | 898 von 903 | 3 von 903 |
| Ueberdeckte Paare | 423353 | 64 |
| Fadenkreuzungen im Vorlauf | 336091 | 17778 |
| Pfeile auf fremdem Faden | 148646 | 644 |
| Bot-Acc 0-2 / 2-3 / 3-4 Sterne | 91.6 / 83.2 / 78.8 % | 96.8 / 95.8 / 93.6 % |
| Bot-Acc 4-5 / 5-6 / 6+ Sterne | 75.1 / 72.5 / 81.7 % | 90.7 / 88.4 / 90.7 % |
| Kamera max (px/Bild) | 25.4 | 37.6 (keine Spruenge > 40) |

## Offen

Drei Maps behalten Restueberdeckung (Sackgassen bei dichten Stapeln): `mirror_2295373 [nerves]` (58 Paare), `mirror_2543663 [How to wake up, Anot]` (4), `mirror_2555699 [Nabi's Insane]` (2). Ziel "keine Map mit ueberdeckten Pfeilen" ist damit zu 900 von 903 erreicht.

# Vorher

Messung: `tools/trace_qa.gd` (Standard-Fadentempo 520 px/s, Vorlauf 1.2 s, Pfeil-Halbmesser 18 px, Akkord 36 px). 903 Maps.

### Gesamt

- Maps mit ueberdeckten Pfeilen: **898 von 903** (423353 Paare, 609706 Noten betroffen)
- kleinster Knotenabstand ueberhaupt: 59.9 px
- Fadenkreuzungen im Vorlauf (Ereignisse): 336091, Pfeile auf fremdem Faden: 148646
- Kamera: groesster Schritt 25.4 px je Bild, Spruenge > 40 px/Bild: 0

### Je Sterne-Band

| Sterne | Maps | Bot-Acc Mittel | Acc schlechteste | Segment p5 (px) | Ueberdeckt (Paare/Map) | Kreuzungen/Map | Haarnadeln/10 s | Kamera max (px/Bild) |
|---|---|---|---|---|---|---|---|---|
| 0-2 | 204 | 91.58 % | 79.64 % | 88.0 | 45.3 | 180.2 | 9.19 | 12.3 |
| 2-3 | 258 | 83.24 % | 72.79 % | 67.6 | 265.3 | 306.9 | 12.24 | 15.7 |
| 3-4 | 206 | 78.79 % | 67.91 % | 65.4 | 564.4 | 430.3 | 15.63 | 19.7 |
| 4-5 | 153 | 75.09 % | 61.16 % | 65.1 | 912.7 | 555.4 | 20.04 | 25.4 |
| 5-6 | 52 | 72.47 % | 56.42 % | 65.1 | 1391.8 | 771.8 | 25.30 | 21.9 |
| 6+ | 30 | 81.66 % | 58.77 % | 70.3 | 579.1 | 213.5 | 15.26 | 25.3 |

### Schlechteste 12 Maps (Ueberdeckung, dann Pfeil auf Faden)

| Map | Sterne | NPS | Paare | Noten | Faden-Kreuz | Pfeil auf Faden | Haarn./10 s | Segment min/p5/med | Acc |
|---|---|---|---|---|---|---|---|---|---|
| 2298540 Omerta - Charade ( [sayonara.] | 5.85 | 20.3 | 4770 | 4601 | 2802 | 1266 | 38.0 | 60/65/76 | 64.01 % |
| mirror_2438724 [VERMILLION SCOURGE] | 5.95 | 22.4 | 3842 | 2911 | 2160 | 763 | 61.0 | 60/65/76 | 56.42 % |
| mirror_2541937 [Glory] | 6.68 | 25.4 | 3177 | 2577 | 1154 | 674 | 43.1 | 60/60/76 | 58.77 % |
| mirror_2400881 [O! S! U!] | 5.50 | 20.7 | 3173 | 2779 | 1632 | 701 | 33.0 | 60/65/76 | 64.09 % |
| mirror_2438724 [Hylotl's Extra] | 5.13 | 18.9 | 3167 | 2393 | 1933 | 598 | 53.3 | 60/65/76 | 62.65 % |
| mirror_2541848 [ANOTHER://ERROR_403_] | 4.51 | 12.7 | 3071 | 3589 | 1927 | 1007 | 21.0 | 60/65/77 | 73.42 % |
| mirror_2541848 [INSANE://MEMORIES_OF] | 3.83 | 11.1 | 3064 | 3306 | 2082 | 1038 | 17.7 | 60/65/76 | 74.20 % |
| 2150831 sath4 - _3_006 w_y [Happy Love Expert] | 4.29 | 16.2 | 2707 | 3068 | 1537 | 735 | 20.5 | 60/65/77 | 69.63 % |
| 1895713 meganeko - The Cyb [Sigma Grindset] | 4.09 | 13.5 | 2495 | 2418 | 1355 | 759 | 19.7 | 60/65/76 | 72.55 % |
| mirror_2541937 [Ultra] | 5.99 | 22.7 | 2469 | 2257 | 1122 | 586 | 35.4 | 60/60/76 | 61.78 % |
| mirror_2438724 [Miaurichesu's Insane] | 4.55 | 16.2 | 2235 | 2051 | 1501 | 413 | 51.6 | 60/65/76 | 64.35 % |
| mirror_2617747 [Expert] | 4.06 | 14.1 | 2222 | 2222 | 1411 | 783 | 27.5 | 60/65/76 | 68.34 % |

Bot: Streuung 24 ms + 2,2 ms je Knoten/0,5 s ueber 6; ueberdeckte Pfeile +22 ms und 14 % Fehlleser; Haarnadel +6 ms; Acc mit Mania-Gewichten (OD der Map).
# Nachher
Messung: `tools/trace_qa.gd` (Standard-Fadentempo 520 px/s, Vorlauf 1.2 s, Pfeil-Halbmesser 18 px, Akkord 36 px). 903 Maps.

### Gesamt

- Maps mit ueberdeckten Pfeilen: **3 von 903** (64 Paare, 235 Noten betroffen)
- kleinster Knotenabstand ueberhaupt: 42.0 px
- Fadenkreuzungen im Vorlauf (Ereignisse): 17778, Pfeile auf fremdem Faden: 644
- Kamera: groesster Schritt 37.6 px je Bild, Spruenge > 40 px/Bild: 0

### Je Sterne-Band

| Sterne | Maps | Bot-Acc Mittel | Acc schlechteste | Segment p5 (px) | Ueberdeckt (Paare/Map) | Kreuzungen/Map | Haarnadeln/10 s | Kamera max (px/Bild) |
|---|---|---|---|---|---|---|---|---|
| 0-2 | 204 | 96.78 % | 94.40 % | 92.8 | 0.0 | 27.2 | 6.86 | 12.3 |
| 2-3 | 258 | 95.81 % | 92.23 % | 74.1 | 0.0 | 18.6 | 9.15 | 17.4 |
| 3-4 | 206 | 93.57 % | 86.17 % | 72.2 | 0.0 | 16.0 | 11.25 | 20.8 |
| 4-5 | 153 | 90.69 % | 81.73 % | 71.8 | 0.4 | 17.6 | 14.33 | 29.2 |
| 5-6 | 52 | 88.37 % | 73.33 % | 71.6 | 0.0 | 24.8 | 17.40 | 23.9 |
| 6+ | 30 | 90.66 % | 76.99 % | 76.5 | 0.0 | 5.7 | 9.29 | 37.6 |

### Schlechteste 12 Maps (Ueberdeckung, dann Pfeil auf Faden)

| Map | Sterne | NPS | Paare | Noten | Faden-Kreuz | Pfeil auf Faden | Haarn./10 s | Segment min/p5/med | Acc |
|---|---|---|---|---|---|---|---|---|---|
| mirror_2295373 [nerves] | 4.99 | 16.1 | 58 | 212 | 64 | 13 | 13.2 | 45/72/80 | 86.96 % |
| mirror_2543663 [How to wake up, Anot] | 3.89 | 11.7 | 4 | 17 | 4 | 3 | 7.5 | 67/83/97 | 95.90 % |
| mirror_2555699 [Nabi's Insane] | 3.45 | 11.2 | 2 | 6 | 4 | 0 | 4.9 | 49/77/91 | 96.11 % |
| 1895713 meganeko - The Cyb [Easy] | 1.69 | 3.8 | 0 | 0 | 74 | 7 | 9.6 | 54/72/145 | 96.82 % |
| mirror_2400069 [Easy] | 1.54 | 3.8 | 0 | 0 | 21 | 6 | 6.7 | 66/72/154 | 97.09 % |
| 2299919 Sasuke Haraguchi f [Avel's Easy] | 1.49 | 3.8 | 0 | 0 | 52 | 6 | 6.8 | 60/71/153 | 97.30 % |
| 2211311 Laur - Viyella_s T [EASY] | 1.65 | 3.8 | 0 | 0 | 42 | 6 | 7.4 | 63/73/128 | 96.41 % |
| mirror_2593224 [Easy] | 1.40 | 3.1 | 0 | 0 | 40 | 6 | 6.3 | 70/77/154 | 96.75 % |
| mirror_2545191 [Normal] | 2.23 | 6.4 | 0 | 0 | 28 | 6 | 8.4 | 65/72/82 | 96.93 % |
| mirror_2578511 [Empty heart // Norma] | 1.90 | 5.5 | 0 | 0 | 62 | 6 | 12.9 | 46/70/81 | 96.60 % |
| 1566829 Purukichi - Luster [Shimmer] | 4.93 | 11.9 | 0 | 0 | 34 | 6 | 10.6 | 46/73/81 | 93.55 % |
| 171880 xi - Happy End of t [4K Normal] | 2.17 | 4.3 | 0 | 0 | 52 | 5 | 8.6 | 63/73/148 | 96.22 % |

Bot: Streuung 24 ms + 2,2 ms je Knoten/0,5 s ueber 6; ueberdeckte Pfeile +22 ms und 14 % Fehlleser; Haarnadel +6 ms; Acc mit Mania-Gewichten (OD der Map).
