# AmFeatures: Liedform, Kiai, erwartete Dichte je Takt (OMEN Auto-Mapper 4K)

Erzeugt von `tests/run_am_features_tests.gd -- --form` in einem Prozess, 256 Sets, 669 s. Alle Zahlen gemessen.
Haelften wie der Pruefstand (`automap_bench.gd split_of`): A = Abstimm-Menge (die Gewichte von Kiai und Dichte
sind nur auf A gelernt), P = Pruef-Menge (nie gesehen). Parameter: DEFAULTS.

| Kennzahl | Ziel | A | P |
|---|---|---|---|
| Sets | - | 180 | 76 |
| Kiai IoU (wie Pruefstand: Map oder Erzeugnis mit Kiai) | >= 0,6 | 0.434 (n=179) | 0.365 (n=75) |
| Sets ohne Kiai auf beiden Seiten (zaehlen nicht) | - | 1 | 1 |
| Kiai-Anteil der Songzeit, erzeugt (Median) | - | 0.34 | 0.33 |
| Korrelation erwartete Dichte (bar_density) gegen Mensch, 2-s-Fenster, alle Profile | >= 0,8 | 0.738 (n=640) | 0.760 (n=285) |
| dasselbe nur Hard | - | 0.758 (n=159) | 0.777 (n=69) |
| Abschnitte je Set (Mittel) | - | 7.4 | 7.8 |
| analyze mit Gitter als Eingabe, auf 4 min, 95. Perzentil | <= 8 s | 1.7 s | 1.8 s |
| analyze ohne Gitter (ruft AmGrid.track selbst), auf 4 min, 95. Perzentil | <= 8 s | 4.3 s | 4.4 s |

## Versatz je Art (Ereignis minus OSU_LEAD minus naechste Menschen-Note, alle Diffs vereinigt, |d| <= 40 ms)

| Art | Median A | Median P | Gipfel A | Gipfel P | n (A+P) |
|---|---|---|---|---|---|
| kick | +2.4 ms | +2.7 ms | -2 ms | +1 ms | 93227 |
| snare | -0.3 ms | -0.3 ms | +0 ms | +0 ms | 57267 |
| hat | +0.6 ms | +0.6 ms | +1 ms | +0 ms | 144016 |
| bass | +1.0 ms | +1.8 ms | -3 ms | +1 ms | 27731 |
| tonal | +0.3 ms | +1.6 ms | -1 ms | +2 ms | 11194 |
| vocal | +0.3 ms | +2.0 ms | +0 ms | +2 ms | 9798 |
| other | +0.6 ms | +1.6 ms | +1 ms | +2 ms | 13695 |

## Vorher (Stand 300f1a3, Abschnitte ueber Lautheits-Neuheit, Kiai ab Intensitaets-Schwelle)

Gemessen auf denselben Sets und mit denselben Definitionen (A / P): Kiai IoU 0,295 / 0,262 (Pruefstand: 0,294 /
0,266); Korrelation der Abschnitts-Intensitaet gegen Mensch 0,498 / 0,547 (Hard 0,511 / 0,543); Ereignisse je Takt
als Dichte 0,639 / 0,679. Versatz (Median, onset_shift_ms = 6): Snare +10,4, Hat +7,1, other +10,5 ms; Gipfel
+11 / +7 / +12 ms; Kick +2,5, Bass +1,3, Ton +0,7, Stimme +0,9 ms.

## Pruefstand end-to-end (tools/automap_bench.gd --mapper new, AmChart unveraendert, 2026-11-14)

P / A vorher (300f1a3) -> nachher: Kiai IoU 0,266 / 0,294 -> 0,368 / 0,431. Dichte-Korrelation der erzeugten Maps
0,544 / 0,523 -> 0,529 / 0,508 (AmChart nutzt bar_density noch nicht, nur die Intensitaet je Abschnitt). Hard auf
Menschen-Note 76,5 % -> 76,3 %, Menschen-Noten getroffen 61,1 % -> 62,1 %. Dauer 95. Perzentil (4 min) 5,5 -> 9,2 s
(Maximum 14,5 s; Rechner durch parallele Laeufe belastet, Laufzeit 1285 s statt 779 s): AutoMapper4K uebergibt das
Gitter noch nicht an analyze, AmGrid.track laeuft darum zweimal.

## Verfahren

- Takte: Taktanfaenge des Gitters (+ OSU_LEAD), unter 1 s Laenge zu Doppeltakten zusammengefasst; ohne Gitter 2-s-Bloecke.
- Merkmale je Takt: Chroma (FFT 4096, 60 Hz..2,1 kHz, Wurzel, L2), Klangfarbe (log-Pegel der 20 Baender, je Band
  z-normiert, L2), Lautheit, perkussiver/harmonischer Pegel, Stimm-Anteil, Ereignisse und Staerke je Art und Sekunde.
- Selbstaehnlichkeit: 0,5 x Kosinus(Chroma) + 0,5 x Kosinus(Klangfarbe). Neuheit: Gauss-Schachbrett-Kern, halbe
  Breite min(8, Takte/4), auf P95 = 1 normiert. 4-Takt-Bloecke auf der Phase mit der groessten Neuheitssumme.
- Kiai je Block: logistisch ueber 58 Merkmale (Block-Mittel und Rang von Lautheit, Pegeln, Ereignissen, Kick, Snare,
  Hat, Stimme; Unterschied zum vorigen, naechsten und vorvorigen Block; beste Wiederholung eines gleich langen Blocks;
  Neuheit am Blockanfang; Lage im Song; Lautheits-Rang des Blocks; Aehnlichkeit mit den lautesten 25 % der Bloecke).
  Kiai ab p > 0,25 (form_kiai_thr). Refrain = wiederkehrender, energiereicher Block.
- Dichte je Takt: linear (Ridge) ueber die z-Werte der 11 Reihen, ihr Mittel ueber 4 und 8 Takte, ihr Block-Mittel,
  Kiai-p und die z-Werte der Ereignisse je Art; density = max(0, 1 + 0,3 x Modell), danach Zeit-Mittel 1.
- Gewichte: gelernt nur auf A (Abstimm-Menge) mit numpy auf einem Merkmals-Auszug aus einem Godot-Lauf (Skript nicht
  im Repo); im Spiel stehen sie als Konstanten in am_features.gd (FORM_KIAI_W, FORM_DENS_W). Port gegen den Prototyp
  geprueft: gleiche Bloecke, |p| und Dichte auf 0,03 gleich (Rundung im Auszug).

## Grenzen

- Rund ein Viertel der Menschen-Maps hat gar kein Kiai; dort zaehlt jedes erzeugte Kiai mit IoU 0. Ob ein Mapper
  Kiai setzt, steht nicht im Audio. Selbst mit perfekter Wahl auf Sets mit Kiai bliebe die IoU dadurch unter ~0,75.
- Mapper waehlen verschiedene Refrains (oft nur den ersten Drop oder nur den letzten Chorus); die Wahl ist Stil.
- Zwei Menschen-Diffs desselben Sets korrelieren in der Dichte (2-s-Fenster) im Mittel mit 0,79 (Prototyp, 1377
  Paare, je Set alle Diff-Paare); das Ziel 0,8 liegt damit an der Grenze dessen, was eine Kurve fuer alle Profile kann.
- Gemessen ist die Kurve selbst. Wie nah die erzeugte Map ihr folgt, entscheidet AmChart (Pruefstand).

