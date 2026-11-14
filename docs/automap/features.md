# AmFeatures: Messung gegen Menschen-Maps (OMEN Auto-Mapper 4K)

Erzeugt von `tests/run_am_features_tests.gd -- --measure` in einem Prozess. Alle Zahlen dieser Datei
sind gemessen; was nur geschlossen ist, steht unter "Grenzen".

- Sets: 153 (von 279 .osz, gleichmaessig verteilt), 371 min Audio, 181511 Map-Noten (alle Diffs je Set vereinigt)
- Parameter: DEFAULTS
- Vorlauf der Maps gegen die erkannten Anschlaege (Median ueber die Sets): 19.2 ms (Ereignis minus Note)

## Ziele und Ist

| Kennzahl | Ziel | Ist | erreicht |
|---|---|---|---|
| Recall der Map-Noten, alle Ebenen zusammen, +-20 ms | >= 0,95 | 0.719 | nein |
| dasselbe bei +-30 ms (alter Mapper: 0,87) | - | 0.788 | - |
| dasselbe, Vorlauf je Set statt global, +-20 ms | - | 0.719 | - |
| Zufallsniveau (Noten um 137 ms verschoben), +-20 ms | - | 0.397 | - |
| Sets mit Recall >= 0,95 | - | 1 von 153 | - |
| Anteil der Ereignisse, die auf einer Map-Note liegen, +-20 ms | - | 0.683 | - |
| Ereignisse je Sekunde (alle Ebenen) | - | 11.4 | - |
| Kiai: IoU gegen die Map (111 Sets mit Kiai) | >= 0,6 | 0.552 | nein |
| Holds (>= 250 ms, 102 Sets mit >= 10 % Holds): Anteil mit sustain-Ereignis am Hold-Beginn (+-40 ms) | - | 0.189 (2572 von 13573) | - |
| sustain-Zeit, die in diesen Sets auf einem Hold liegt | - | 0.530 | - |
| Laengenfehler sustain gegen Hold (Median, getroffene Holds) | - | 156 ms | - |
| Dauer analyze, hochgerechnet auf 4 min (Mittel) | <= 8 s | 4.1 s | ja |
| Dauer analyze, langsamstes Set auf 4 min gerechnet | <= 8 s | 5.4 s | ja |

## Ist-Werte je Ebene

Recall allein = Anteil der Map-Noten, an denen ein Ereignis genau dieser Ebene liegt (+-20 ms).
Zufall = derselbe Wert mit um 137 ms verschobenen Noten. Treffer = Anteil der Ereignisse der Ebene auf einer Map-Note,
Treffer-Zufall dasselbe mit verschobenen Noten. Vorlauf der Ebene = Vorlauf, bei dem die Ebene allein die meisten Treffer hat
(gleich dem globalen Vorlauf = Zeitlage der Ebene stimmt).

| Ebene | Ereignisse/min | Recall allein | Zufall | Treffer | Treffer-Zufall | Vorlauf der Ebene |
|---|---|---|---|---|---|---|
| kick | 193.0 | 0.209 | 0.142 | 0.517 | 0.349 | 28 ms |
| snare | 85.5 | 0.161 | 0.064 | 0.910 | 0.352 | 22 ms |
| hat | 282.7 | 0.428 | 0.198 | 0.730 | 0.331 | 24 ms |
| bass | 49.0 | 0.070 | 0.032 | 0.685 | 0.309 | 26 ms |
| tonal | 21.1 | 0.034 | 0.012 | 0.766 | 0.265 | 26 ms |
| vocal | 19.6 | 0.031 | 0.011 | 0.754 | 0.256 | 26 ms |
| other | 32.4 | 0.039 | 0.022 | 0.573 | 0.315 | 24 ms |

## Hitsounds der Maps als Hinweis (dichteste Diff, nur Sets mit >= 20 Claps)

| Noten mit | Anzahl | snare in +-25 ms | hat in +-25 ms |
|---|---|---|---|
| Clap | 7153 | 0.323 | - |
| Finish | 3083 | - | 0.574 |
| Whistle | 8798 | - | 0.593 |
| ohne Zusatz | 47932 | 0.219 | 0.504 |

## Abschnitte und fuehrende Ebene (Anteil der Songzeit)

Abschnitte je Set im Mittel: 7.6

| lead | Anteil |
|---|---|
| drums | 0.855 |
| bass | 0.000 |
| tonal | 0.004 |
| vocal | 0.141 |

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
- lead der Abschnitte ist eine Heuristik aus Ereignisdichten und Stimm-Anteil, ohne Wahrheit. Kiai und erwartete
  Dichte kommen aus der Liedform (gelernt auf der Abstimm-Menge); Messung je Haelfte in docs/automap/form.md (--form).
- sustain folgt dem harmonischen Pegel im Band des Tons; ob ein Mapper dort einen Hold setzt, ist Stilfrage.

## Songs des Nutzers (nur Zahlen)

### MLAR - AUTOPSIE

Datei `MLAR - AUTOPSIE (Official Video).mp3`, 174 s, analyze 2868 ms (auf 4 min: 3.9 s).

Ereignisse: kick 175, snare 62, hat 897, bass 152, tonal 67, vocal 126, other 152, davon gehalten 134.

| von | bis | Art | Intensitaet | Kiai | lead |
|---|---|---|---|---|---|
| 0.0 s | 14.8 s | intro | 0.19 | - | vocal |
| 14.8 s | 29.6 s | intro | 0.44 | - | vocal |
| 29.6 s | 44.4 s | build | 0.50 | - | vocal |
| 44.4 s | 51.8 s | chorus | 0.61 | ja | drums |
| 51.8 s | 59.1 s | build | 0.57 | - | drums |
| 59.1 s | 66.5 s | chorus | 0.62 | ja | drums |
| 66.5 s | 73.9 s | build | 0.64 | - | drums |
| 73.9 s | 88.7 s | chorus | 0.61 | ja | vocal |
| 88.7 s | 110.8 s | build | 0.48 | - | vocal |
| 110.8 s | 125.6 s | chorus | 0.55 | ja | vocal |
| 125.6 s | 133.0 s | build | 0.54 | - | vocal |
| 133.0 s | 147.8 s | chorus | 0.60 | ja | vocal |
| 147.8 s | 174.3 s | outro | 0.44 | - | vocal |

### MLAR - DEN HAAG

Datei `MLAR - DEN HAAG (Official Video).mp3`, 157 s, analyze 2447 ms (auf 4 min: 3.7 s).

Ereignisse: kick 588, snare 123, hat 824, bass 126, tonal 54, vocal 99, other 149, davon gehalten 105.

| von | bis | Art | Intensitaet | Kiai | lead |
|---|---|---|---|---|---|
| 0.0 s | 17.4 s | intro | 0.40 | - | drums |
| 17.4 s | 46.4 s | build | 0.52 | - | drums |
| 46.4 s | 52.1 s | chorus | 0.57 | ja | vocal |
| 52.1 s | 57.9 s | build | 0.54 | - | vocal |
| 57.9 s | 63.7 s | chorus | 0.58 | ja | drums |
| 63.7 s | 92.6 s | verse | 0.50 | - | drums |
| 92.6 s | 104.2 s | build | 0.54 | - | vocal |
| 104.2 s | 110.0 s | chorus | 0.52 | ja | vocal |
| 110.0 s | 115.7 s | build | 0.53 | - | drums |
| 115.7 s | 133.1 s | chorus | 0.60 | ja | drums |
| 133.1 s | 157.2 s | outro | 0.40 | - | drums |

### c4rl - Immer

Datei `c4rl - Immer.mp3`, 136 s, analyze 2449 ms (auf 4 min: 4.3 s).

Ereignisse: kick 323, snare 213, hat 555, bass 161, tonal 36, vocal 18, other 95, davon gehalten 93.

| von | bis | Art | Intensitaet | Kiai | lead |
|---|---|---|---|---|---|
| 0.0 s | 11.5 s | intro | 0.32 | - | drums |
| 11.5 s | 20.4 s | verse | 0.46 | - | drums |
| 20.4 s | 51.8 s | build | 0.53 | - | drums |
| 51.8 s | 65.3 s | chorus | 0.60 | ja | drums |
| 65.3 s | 74.3 s | verse | 0.46 | - | drums |
| 74.3 s | 101.2 s | build | 0.51 | - | drums |
| 101.2 s | 119.1 s | chorus | 0.62 | ja | drums |
| 119.1 s | 136.0 s | outro | 0.38 | - | drums |

