# AmFeatures: Messung gegen Menschen-Maps (OMEN Auto-Mapper 4K)

Erzeugt von `tests/run_am_features_tests.gd -- --measure` in einem Prozess. Alle Zahlen dieser Datei
sind gemessen; was nur geschlossen ist, steht unter "Grenzen".

- Sets: 155 (von 254 .osz, gleichmaessig verteilt), 401 min Audio, 196366 Map-Noten (alle Diffs je Set vereinigt)
- Parameter: DEFAULTS
- Vorlauf der Maps gegen die erkannten Anschlaege (Median ueber die Sets): 21.3 ms (Ereignis minus Note)

## Ziele und Ist

| Kennzahl | Ziel | Ist | erreicht |
|---|---|---|---|
| Recall der Map-Noten, alle Ebenen zusammen, +-20 ms | >= 0,95 | 0.704 | nein |
| dasselbe bei +-30 ms (alter Mapper: 0,87) | - | 0.782 | - |
| dasselbe, Vorlauf je Set statt global, +-20 ms | - | 0.698 | - |
| Zufallsniveau (Noten um 137 ms verschoben), +-20 ms | - | 0.372 | - |
| Sets mit Recall >= 0,95 | - | 2 von 155 | - |
| Anteil der Ereignisse, die auf einer Map-Note liegen, +-20 ms | - | 0.679 | - |
| Ereignisse je Sekunde (alle Ebenen) | - | 11.3 | - |
| Kiai: IoU gegen die Map (111 Sets mit Kiai) | >= 0,6 | 0.388 | nein |
| Holds (>= 250 ms, 110 Sets mit >= 10 % Holds): Anteil mit sustain-Ereignis am Hold-Beginn (+-40 ms) | - | 0.188 (2929 von 15604) | - |
| sustain-Zeit, die in diesen Sets auf einem Hold liegt | - | 0.547 | - |
| Laengenfehler sustain gegen Hold (Median, getroffene Holds) | - | 144 ms | - |
| Dauer analyze, hochgerechnet auf 4 min (Mittel) | <= 8 s | 1.2 s | ja |
| Dauer analyze, langsamstes Set auf 4 min gerechnet | <= 8 s | 1.3 s | ja |

## Ist-Werte je Ebene

Recall allein = Anteil der Map-Noten, an denen ein Ereignis genau dieser Ebene liegt (+-20 ms).
Zufall = derselbe Wert mit um 137 ms verschobenen Noten. Treffer = Anteil der Ereignisse der Ebene auf einer Map-Note,
Treffer-Zufall dasselbe mit verschobenen Noten. Vorlauf der Ebene = Vorlauf, bei dem die Ebene allein die meisten Treffer hat
(gleich dem globalen Vorlauf = Zeitlage der Ebene stimmt).

| Ebene | Ereignisse/min | Recall allein | Zufall | Treffer | Treffer-Zufall | Vorlauf der Ebene |
|---|---|---|---|---|---|---|
| kick | 189.6 | 0.214 | 0.135 | 0.540 | 0.335 | 28 ms |
| snare | 94.7 | 0.171 | 0.065 | 0.871 | 0.322 | 34 ms |
| hat | 275.8 | 0.412 | 0.182 | 0.717 | 0.307 | 32 ms |
| bass | 52.5 | 0.076 | 0.036 | 0.696 | 0.318 | 28 ms |
| tonal | 19.5 | 0.030 | 0.011 | 0.743 | 0.275 | 28 ms |
| vocal | 18.8 | 0.029 | 0.010 | 0.741 | 0.247 | 28 ms |
| other | 29.2 | 0.030 | 0.017 | 0.493 | 0.268 | 38 ms |

## Hitsounds der Maps als Hinweis (dichteste Diff, nur Sets mit >= 20 Claps)

| Noten mit | Anzahl | snare in +-25 ms | hat in +-25 ms |
|---|---|---|---|
| Clap | 7661 | 0.370 | - |
| Finish | 2533 | - | 0.539 |
| Whistle | 9125 | - | 0.592 |
| ohne Zusatz | 40297 | 0.235 | 0.525 |

## Kiai-Schwellen (IoU-Mittel, aus denselben Abschnitten nachgerechnet)

| kiai_abs | kiai_margin | IoU |
|---|---|---|
| 0.50 | 0.15 | 0.388 (beste) |
| 0.50 | 0.25 | 0.362 |
| 0.60 | 0.15 | 0.385 |
| 0.60 | 0.20 | 0.373 |
| 0.60 | 0.30 | 0.355 |
| 0.70 | 0.15 | 0.382 |
| 0.70 | 0.25 | 0.383 |
| 0.80 | 0.10 | 0.358 |
| 0.45 | 0.35 | 0.343 |
| 0.55 | 0.40 | 0.340 |

## Abschnitte und fuehrende Ebene (Anteil der Songzeit)

Abschnitte je Set im Mittel: 10.7

| lead | Anteil |
|---|---|
| drums | 0.863 |
| bass | 0.000 |
| tonal | 0.008 |
| vocal | 0.129 |

## Grenzen (geschlossen, nicht gemessen)

- Die Maps sagen nicht, welche Ebene eine Note traegt. "Recall allein" und "Treffer" messen nur, ob Ereignisse einer
  Ebene auf Map-Noten liegen, nicht ob die Art stimmt. Ob ein Kick wirklich ein Kick ist, belegen nur die Unit-Tests
  mit kuenstlichen Signalen; die Hitsound-Tabelle ist ein grober Hinweis (Mapper setzen Clap/Finish/Whistle nach Stil).
- Das Ziel Recall >= 0,95 bei 20 ms ueber die vereinigten Noten aller Diffs ist nicht erreicht: Maps setzen viele Noten
  ohne eigenen Einsatz (Rhythmus fortgefuehrt, Gitter-Fuellung, Streams). Mehr Ereignisse heben den Recall nur auf
  Zufallsniveau (Zeile Zufall), deshalb gilt Treffer gegen Treffer-Zufall als Mass fuer echte Einsaetze.
- Zeitlage: absolut per Klick-Test, die Gruppen Kick/Bass und Ton/Stimme relativ dazu gegen 12 dieser Sets abgestimmt
  (fester Versatz). Mit 512er-FFT (23 ms) schwanken Tiefton-Baender unter Basstoenen; Kick bleibt die schwaechste Ebene.
- vocal gegen tonal: Stimme = gleitende Tonhoehe der staerksten Spektrallinie. In dichter, mehrstimmiger Musik springt
  diese Linie zwischen Instrumenten; Stimme wird dann als tonal erkannt oder umgekehrt. Ohne Wahrheit in den Maps.
- lead der Abschnitte ist eine Heuristik aus Ereignisdichten und Stimm-Anteil, ohne Wahrheit; Kiai folgt Lautheit und
  Dichte, Mapper setzen Kiai nach der Liedform (Refrain), die nicht erkannt wird.
- sustain folgt dem harmonischen Pegel im Band des Tons; ob ein Mapper dort einen Hold setzt, ist Stilfrage.

## Songs des Nutzers (nur Zahlen)

### MLAR - AUTOPSIE

Datei `MLAR - AUTOPSIE (Official Video).mp3`, 174 s, analyze 811 ms (auf 4 min: 1.1 s).

Ereignisse: kick 175, snare 62, hat 897, bass 152, tonal 67, vocal 126, other 157, davon gehalten 134.

| von | bis | Art | Intensitaet | Kiai | lead |
|---|---|---|---|---|---|
| 0.0 s | 16.0 s | intro | 0.04 | - | vocal |
| 16.0 s | 30.0 s | verse | 0.46 | - | vocal |
| 30.0 s | 43.9 s | verse | 0.59 | - | drums |
| 43.9 s | 55.9 s | chorus | 0.78 | ja | drums |
| 55.9 s | 64.4 s | verse | 0.64 | - | drums |
| 64.4 s | 72.4 s | chorus | 0.77 | ja | drums |
| 72.4 s | 88.4 s | chorus | 0.80 | ja | drums |
| 88.4 s | 103.3 s | verse | 0.50 | - | vocal |
| 103.3 s | 118.3 s | chorus | 0.70 | ja | drums |
| 118.3 s | 135.8 s | verse | 0.63 | - | drums |
| 135.8 s | 145.8 s | chorus | 0.75 | ja | drums |
| 145.8 s | 174.3 s | outro | 0.49 | - | vocal |

### MLAR - DEN HAAG

Datei `MLAR - DEN HAAG (Official Video).mp3`, 157 s, analyze 767 ms (auf 4 min: 1.2 s).

Ereignisse: kick 588, snare 123, hat 824, bass 126, tonal 54, vocal 99, other 146, davon gehalten 105.

| von | bis | Art | Intensitaet | Kiai | lead |
|---|---|---|---|---|---|
| 0.0 s | 9.5 s | intro | 0.09 | - | drums |
| 9.5 s | 23.5 s | verse | 0.54 | - | drums |
| 23.5 s | 34.9 s | verse | 0.59 | - | drums |
| 34.9 s | 46.4 s | verse | 0.57 | - | drums |
| 46.4 s | 57.9 s | chorus | 0.75 | ja | drums |
| 57.9 s | 66.9 s | chorus | 0.81 | ja | drums |
| 66.9 s | 80.9 s | verse | 0.56 | - | drums |
| 80.9 s | 92.9 s | verse | 0.58 | - | drums |
| 92.9 s | 103.3 s | chorus | 0.69 | ja | drums |
| 103.3 s | 115.8 s | verse | 0.59 | - | drums |
| 115.8 s | 126.3 s | chorus | 0.79 | ja | drums |
| 126.3 s | 136.8 s | chorus | 0.82 | ja | drums |
| 136.8 s | 157.2 s | outro | 0.14 | - | drums |

### c4rl - Immer

Datei `c4rl - Immer.mp3`, 136 s, analyze 717 ms (auf 4 min: 1.3 s).

Ereignisse: kick 323, snare 213, hat 555, bass 161, tonal 36, vocal 18, other 96, davon gehalten 93.

| von | bis | Art | Intensitaet | Kiai | lead |
|---|---|---|---|---|---|
| 0.0 s | 13.5 s | intro | 0.17 | - | drums |
| 13.5 s | 21.5 s | verse | 0.34 | - | drums |
| 21.5 s | 32.9 s | chorus | 0.72 | ja | drums |
| 32.9 s | 45.9 s | chorus | 0.68 | ja | drums |
| 45.9 s | 64.9 s | verse | 0.59 | - | drums |
| 64.9 s | 73.4 s | chorus | 0.69 | ja | drums |
| 73.4 s | 84.4 s | verse | 0.35 | - | drums |
| 84.4 s | 99.8 s | chorus | 0.69 | ja | drums |
| 99.8 s | 117.8 s | verse | 0.59 | - | drums |
| 117.8 s | 126.8 s | chorus | 0.75 | ja | drums |
| 126.8 s | 136.0 s | outro | 0.13 | - | drums |

