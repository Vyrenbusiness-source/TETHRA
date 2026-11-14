# Auto-Mapper 4K: Uebergaenge der Kette (AmFeatures -> AmGrid -> AmChart -> AmWriter)

Stand 2026-11-14 (Task am-integrate, nach AmGrid Runde 2). Alle Zahlen gemessen mit echtem Audio aus
`maps/`; was nur geschlossen ist, steht unter "Geschlossen".

Messwerkzeuge (je ein Prozess):

```
# Uebergaenge je Ereignis-Art, obere Grenze, Auswahl des Setzers, Dichte, Kiai (40 Sets der Abstimm-Menge)
timeout 3000 ./Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . \
    --script res://tools/automap_chain_diag.gd -- --maps <maps> --set tune --songs 40
# Ziel-Tabelle alt/neu: tools/automap_bench.gd (docs/automap/report.md)
# Abstimmung: tools/automap_tune.gd (Protokoll im Bericht, Abschnitt Abstimmung)
```

## Gemessen: Uebergaenge (34 auswertbare Sets der Abstimm-Menge, Hard)

"vorher" = Standardwerte, "nachher" = `data/automap/params.json` nach der Abstimmung.

| Art | Lage gegen Mensch, Median (vorher / nachher) | Lage gegen Gitter-1/4 (vorher / nachher) | Hard-Noten dieser Art (vorher / nachher) | davon auf Menschen-Note (vorher / nachher) |
|---|---|---|---|---|
| kick | +0,8 / +0,8 ms | -0,4 / -0,4 ms | 7252 / 6326 | 70,1 / 76,9 % |
| snare | +6,6 / +9,4 ms | +5,9 / +8,9 ms | 3647 / 4389 | 92,8 / 90,0 % |
| hat | +3,0 / +5,6 ms | +3,3 / +6,1 ms | 7265 / 8313 | 77,8 / 76,0 % |
| bass | -0,8 / -0,8 ms | -0,2 / -0,2 ms | 1633 / 1752 | 80,2 / 78,0 % |
| tonal | +1,9 / +1,9 ms | +0,2 / +0,2 ms | 608 / 637 | 78,9 / 78,3 % |
| vocal | +0,2 / +0,2 ms | -1,1 / -1,1 ms | 550 / 590 | 82,5 / 81,9 % |
| other | +6,3 / +8,5 ms | +5,7 / +7,9 ms | 695 / 867 | 68,1 / 68,4 % |

| Kennzahl (Mittel ueber Sets) | vorher | nachher |
|---|---|---|
| obere Grenze: Menschen-Hard-Zeilen mit eingerastetem Ereignis (+-15 ms) | 0,806 | 0,803 |
| Hard erzeugt: auf Menschen-Note | 0,714 | 0,720 |
| Hard erzeugt: Menschen-Noten getroffen | 0,553 | 0,581 |
| Notenzahl erzeugt/Mensch | 0,780 | 0,813 |
| Dichte-Korrelation: alle eingerasteten Ereignisse gegen Mensch | 0,600 | 0,600 |
| Dichte-Korrelation: Abschnitts-Intensitaet gegen Mensch | 0,480 | 0,480 |
| Dichte-Korrelation: Hard erzeugt gegen Mensch | 0,495 | 0,495 |
| Kiai IoU roh / auf Taktanfang gelegt | 0,301 / 0,301 | 0,291 / 0,292 |

Befunde:

- **Lead-Versatz**: Gitter (`AmGrid.OSU_LEAD_MS` = 23) und Ereignisse minus 23 ms liegen fuer Kick, Bass,
  Ton und Stimme innerhalb +-2 ms der Menschen-Noten. Snare, Hat und "other" liegen 3-7 ms spaet
  (gemeinsamer Parameter `onset_shift_ms`). Da jede Note auf das Gitter gelegt wird, verschiebt das keine
  Notenzeit; es beeinflusst nur die Wahl 1/4 gegen 1/8 beim Einrasten. Die Abstimmung waehlt
  `onset_shift_ms` = 6 (statt 3), Gewinn in der Zielgroesse +0,0002 (Rauschen); der Versatz von Snare/Hat
  gegen die Menschen-Noten waechst dadurch auf +9 / +6 ms. Offen (siehe unten).
- **Ereignis-Arten im Setzer**: Kick ist die haeufigste Art in Hard und die unsicherste (70 % auf
  Menschen-Noten; schwache Kicks 0-0,5 nur 52 %). Snare liegt bei 93 %. AmFeatures normiert die Staerke
  je Ebene, ein Hi-Hat zaehlte darum so viel wie ein Kick. Neu: Gewicht je Art `w_<art>` in AmChart;
  abgestimmt Kick 0,43, Snare 2,0, Hat 1,1, Stimme 1,5, other 1,2. Kick-Noten 7252 -> 6326 bei 76,9 %
  statt 70,1 % Treffern.
- **Dichte**: die eingerasteten Ereignisse folgen der Dichte der Menschen-Map (0,60) besser als die
  Abschnitts-Intensitaet (0,48) und als die erzeugte Hard-Map (0,495). Neu: `dens_local_gain` (oertliche
  Ereignis-Dichte in +-1 s als Term der Auswahl, Test mit kuenstlichem Signal). Die Abstimmung waehlt 0
  (jeder Wert > 0 senkt die Zielgroesse); die Dichte-Luecke ist damit nicht geschlossen.
- **Kiai -> Dichte**: AmChart nutzt die Kiai-Markierung nicht direkt, nur die Intensitaet
  (`dens_gain` x gelerntes Kiai-Verhaeltnis). Abgestimmt `dens_gain` 0,27 (statt 0,4).
- **Kiai im Set**: AmWriter schrieb die Abschnittsgrenzen akustisch und ungerastet. Neu: Map-Zeit
  (minus OSU_LEAD) und auf den naechsten Taktanfang gelegt, Abschnitte unter einem Takt entfallen.
  IoU unveraendert (0,301 / 0,301): die Luecke liegt in der Auswahl der Abschnitte (AmFeatures), nicht
  in der Lage.
- **Pipeline**: `AutoMapper4K.generate` und der Pruefstand riefen `AmChart.build` je Profil auf; jeder
  Aufruf rechnet alle schwereren Profile mit (15 statt 5 Profil-Laeufe). Jetzt ein `build_all`.
  Dauer 95. Perzentil (4 min) 6,2 -> 5,5 s.
- **Spielbarkeit**: 1 lint-Verstoss in 420 Diffs (Normal, "Hold und Note gleichzeitig" 25 von 265).
  Ursache: Budget in Zeilen, lint zaehlt Noten (Akkorde, kopierte Takte). Jetzt zaehlt AmChart wie lint
  (`overlap_count`) und setzt neu, bis die Obergrenze haelt. Danach 0 in 420 + 935 Diffs.

## Gemessen: Abstimmung (tools/automap_tune.gd)

Abstimm-Menge 28 Songs, Pruef-Menge 16 Songs (Werkzeug-Auswahl), 124 Auswertungen, 16 Stellgroessen
(Gewichte je Art, Taktposition, Staerke, Ebenen-Gewichte, Dichte, onset_shift, Kiai-Schwellen).
Zielgroesse Abstimm-Menge 0,7097 -> 0,7162, Pruef-Menge 0,8188 -> 0,8234. Zweite Runde mit weiteren
Bereichen fuer die Randwerte: keine Verbesserung. Ergebnis in `data/automap/params.json`.

Ganze Pruef-Menge (84 Sets, `tools/automap_bench.gd --mapper new`), vorher = Standardwerte (ohne
Hold-Fix), nachher = abgestimmt (mit Hold-Fix):

| Kennzahl | Ziel | vorher | nachher |
|---|---|---|---|
| auf Menschen-Note (Hard) | >= 85 % | 75,8 % | 76,5 % |
| Menschen-Noten getroffen (Hard) | >= 75 % | 57,1 % | 61,1 % |
| Notenzahl erzeugt/Mensch (Hard) | - | 0,76 | 0,80 |
| Dichte-Korrelation | >= 0,8 | 0,550 | 0,544 |
| Holds | >= 60 % | 52,8 % | 52,8 % |
| Kiai IoU | >= 0,6 | 0,267 | 0,266 |
| Sterne im Band, schlechtestes Profil | >= 90 % | 69,0 % | 69,0 % |
| Sterne Normal | >= 90 % | 78,6 % | 75,0 % |
| Regelverletzungen | 0 | 1 | 0 |
| Dauer 95. Perzentil (4 min) | <= 15 s | 6,2 s | 5,5 s |

Takt-Zeilen sind gleich (AmGrid nicht abgestimmt).

## Geschlossen (nicht gemessen)

- Der hoehere Snare-Gewicht folgt den Menschen-Maps (Snare = sicherster Anschlag); ob es musikalisch
  besser klingt, sagt nur die Hoerprobe.
- `onset_shift_ms` = 6 verbessert die Zielgroesse nur im Rauschen und verschiebt Snare/Hat weiter von den
  Menschen-Noten weg. Besser waere ein Versatz je Art im Setzer, der die Ereignisse auf die Menschen-
  Konvention legt, und danach die Einrast-Schwelle (`snap_quarter_bias_ms`) neu abstimmen. Nicht gemacht.
