# SV-Mod: Analyse und Kennzahlen

Mod "SV" (Song-Browser, neben No-Fail; Tooltip "Jede Map mit Tempowechseln").
`GameSession.mods = {"SV": bool, "NF": bool}`. Generator: `scripts/gameplay/sv_mod.gd`,
Einbau: `ManiaCore.build_scroll_map` (liest `GameSession.mods`). Tests:
`tests/run_sv_mod_tests.gd`.

## Score

| Mods | Multiplikator | Max-Score |
|---|---|---|
| keine | x1.00 | 1.000.000 |
| SV | x1.10 | 1.100.000 |
| NF | x0.50 | 500.000 |
| SV + NF | x0.55 | 550.000 |

`ManiaCore.MOD_MULT`, angewendet in `_add_score`. Damit tragen Live-Score, MP-Score
(`Lobby.send_score`), ScoreStore und Replays den Multiplikator. `core.stats()` liefert
zusaetzlich `mods` (z.B. `["SV", "NF"]`) und `mod_mult`. NF setzt in Mania jetzt auch
wirklich `no_fail`. Vorher wurde der Schalter dort ignoriert.

## Wie echte SV-Maps aufgebaut sind (Analyse maps/, 989 Mania-Diffs)

Gemessen mit derselben Multiplikator-Rechnung wie `ScrollMap`
(m = SV * BaseBeatLength / beatLength), zwischen erster Note und letztem Notenende.
30 Diffs haben deutlich SV (mehr als 30 gruene Linien pro Minute und mehr als 10 Spruenge pro Minute).

- **Normierung:** Die mittlere Scroll-Geschwindigkeit liegt bei 0,91 bis 1,04. Die Basis ist die haeufigste BPM.
- **Werte:** Der Median ist immer 1,0. p05 liegt bei 0,1 bis 0,5, p95 bei 1,5 bis 2,5. Die Grenzen sind 0,01 bis 10.
  Werte ueber 3 gibt es nur fuer Millisekunden (Teleport).
- **Abstaende:** Der Median-Abstand zwischen gruenen Linien liegt bei 1/8 bis 1/4 Beat.
  Bei Stutter-Extremen sind es 1/32 Beat.
- **Linien auf Noten:** 26 bis 50 % der gruenen Linien liegen genau auf einer Note.
  Das ist der Akzent bzw. Speed-Up ab dem Treffer.
- **Typisches Stutter** (mirror_2563907 [Expert]): Auf jeder 1/2-Note gilt SV 2,5 fuer 1/3 des
  Intervalls, danach 0,1. Vor dem Abschnittsende kommen 4,5/0,5-Paare im 1/4-Takt.
- **Takt-Mittel:** Die Standardabweichung des 4-Beat-Mittels liegt bei 0,02 bis 0,07 (Ranked-nah).
  Wilde Maps erreichen 0,13 bis 0,27, mit kurzen Teleport-Takten bis 5.

## Generator

Jede gruene Linie bekommt SV = m * beatLength / Base. Damit ist jeder BPM-Wechsel
normalisiert (SV = ModeBPM / BPM). Jeder Block (1 Beat, Ramp mehrere Beats) hat den
Mittelwert m = 1 exakt. Die Noten kommen also an der richtigen Scroll-Position an.

| Muster | Form | Wann |
|---|---|---|
| ACCENT | hi fuer 1/4 Beat ab der Note, danach (1 - f*hi)/(1 - f). Bei Akkord hi + 0,25 | Note auf dem Beat. Volle Staerke auf starken Beats, halbe auf den anderen |
| STUTTER | im 1/2- oder 1/4-Takt: hi fuer f = 1/4 oder 1/3, Rest kompensiert. Variante: erst 0,4 fuer 60 %, dann Burst 1,9 | 1/2 auch ruhig, 1/4 nur im Kiai |
| BOUNCE | 1 - d fuer den halben Beat, dann 1 + d | Downbeat |
| TELEPORT | SV 10 fuer 4 bis 8 ms direkt vor der Note, davor ca. 0,9 | Kiai, starke Beats |
| FREEZE | 0,1 fuer 3/4 Beat, dann Burst 3,7 | letzter Beat vor dem Drop |
| RAMP | 1 bis 2 Takte von lo (0,6 bis 0,75) auf 2 - lo ansteigend | vor dem Drop |

- **Phrasen:** Das Muster wird pro Takt gewuerfelt. Im Kiai ist es lebendiger: Stutter 1/4,
  Teleport, hi 1,75 bis 3. Ruhige Teile haben 40 % keine SV und hi 1,25 bis 1,75.
  In dichten Takten (4 oder mehr Noten pro Beat) ist die Amplitude auf 70 % gedrosselt
  und es gibt kein Stutter 1/4.
- **Maps ohne Kiai:** Die dichtesten 25 % der Takte gelten als lebendig.
- **Drops:** ein Kiai-Beginn oder die erste Note nach 8 oder mehr leeren Beats.
- **Breaks:** Ohne Noten im Umfeld bleibt m = 1.
- **Deterministik:** Seed = md5 aus roten Linien und Noten, dazu `RandomNumberGenerator` (PCG32).
  Das ergibt auf jedem Rechner und fuer jeden MP-Spieler dieselben Linien.
- **Fairness:**
  - m liegt zwischen 0,1 und 10 und ist immer groesser 0, also nie rueckwaerts (Stufe Normal).
  - Kein Abschnitt ist kuerzer als 4 ms.
  - Das erste Segment hat m = 1, damit der Anlauf nicht beschleunigt.
  - Noten derselben Spalte (auch Hold-Kopf und Hold-Ende) behalten einen Positionsabstand
    von mindestens 30 % der Zeit bzw. 24 ms. Sonst faellt der Block auf m = 1 zurueck.
- **Map mit eigenem SV** (`MapLibrary.detect_sv`): Ihr SV bleibt unveraendert, es wird nicht doppelt gemischt.

## Stufe Stark (Standard)

`SvMod.strength` waehlt die Stufe: `STRENGTH_NORMAL` ist der Generator oben (Stand v1.15,
unveraendert). `STRENGTH_STRONG` ("max") ist der Standard. Eine Auswahl im Spiel kommt
spaeter (song_select/settings gehoeren anderen Tasks). Der Cache haengt an Seed und Stufe.

Leitbild: Die Noten tanzen auf dem Beat hoch und runter. Jeder Beat hat einen Ruecklauf
und einen Burst, der genau auf dem naechsten Beat endet.

| Muster | Form | Wann |
|---|---|---|
| BOUNCE | Ruecklauf lo (Kiai 0,08 bis 0,2, Strophe 0,35 bis 0,55; Downbeat x0,6), Burst 15 bis 25 % des Beats bis genau auf den Beat (bis 9,5) | Kiai 75 %, Strophe 50 % der Takte |
| REVERSE | im Ruecklauf m = -k (Kiai 1 bis 2, Strophe 0,6 bis 1) fuer 1/4 bis 1/2 Beat, endet direkt vor dem Burst | nur in freien Luecken, Kiai 70 %, Strophe 35 % der Beats |
| JUMP | Rueck-Sprung m = -10 fuer 5 bis 10 ms direkt vor dem Burst | wenn kein Reverse, Kiai 45 % |
| TELEPORT | SV 10 fuer 5 bis 10 ms direkt vor dem Beat | vor Downbeat/Taktmitte mit Note, Kiai 60 % |
| STUTTER | Bounce im 1/2-Takt | Kiai 20 %, nicht in dichten Takten |
| PULSE | Schub hi 2 bis 4 ab dem Beat, Rest langsamer | Strophe 40 % |
| WAVE | Beat-Mittel 1 + A*sin ueber den Takt (A 0,2 bis 0,35), exakt auf Takt-Mittel 1 normiert | jeder Takt |
| Drop | FREEZE 0,05 fuer 3/4 Beat, Burst 3,85; Drop-Beat 4,0 fuer 1/5 Beat; RAMP ab 0,35 bis 0,5 | wie Normal |

- **Block = Takt:** Der ganze Takt ist ein Block mit Mittel exakt 1. An jeder Taktgrenze
  (ausser in Ramps vor Drops) stimmt die Position bitgenau wie ohne Mod. Die
  Scroll-Speed-Einstellung stimmt im Mittel, jede Note kommt exakt puenktlich an.
- **Reverse fair:**
  - Rueckwaerts nur, wenn keine Note und kein Hold-Koerper naeher als 90 ms liegt
    (Rueck-Sprung 70 ms). Damit ist waehrend der Rueckwaerts-Phase keine Note an der
    Trefferlinie, und jede Note kommt vorwaerts an.
  - Kein Hold laeuft durch eine Rueckwaerts-Phase.
  - Es gilt dieselbe Spalten-Regel wie bei Normal (30 % der Zeit bzw. 24 ms Abstand).
  - Verstoesst ein Takt dagegen, faellt er stufenweise zurueck: erst ohne Reverse und Jump,
    dann ohne Welle (einfacher Puls), zuletzt m = 1.
- **Grenzen Stark:** vorwaerts mindestens 0,05 (`M_MIN_STRONG`), hoechstens 10.
  Rueckwaerts hoechstens -10 (`M_REV_MAX`). Bei hohem Tempo und Bursts darf die
  Sichtzeit einer Note auf 1/3 der Anflugzeit sinken (Normal: 40 %).
- **Darstellung:** Negative Multiplikatoren stehen als Meta `sv_mult` an der gruenen Linie
  (`ScrollMap.SV_META`). Echte .osu-Dateien kennen das nicht, deren Verhalten bleibt 1:1.
  `ScrollMap.position()` ist dann nicht monoton. `time_at()` und `spawn_time()` liefern
  den ersten Zeitpunkt (laufendes Maximum). `ManiaCore` haelt die Spawn-Zeiten nicht fallend.
  3D blendet Noten und Hold-Strahlen hinter dem Horizont aus, 2D zeichnet sie oberhalb des
  Bildes. So verschwindet keine Note, die kurz nach oben laeuft, und keine erscheint doppelt.
- **Treffer-Wertung:** Sie bleibt rein zeitbasiert und unveraendert.

Kennzahlen Stark (`tests/run_sv_mod_tests.gd`):

| Map | Linien | Rueckwaerts | Teleports | m vorwaerts |
|---|---|---|---|---|
| synthetisch 150 BPM, 1/2 + Stream | 533 | 13 | 38 | 0,05 bis 10 |
| 1/1-Map 150 BPM mit Holds | | 19 Rueck-Spruenge, mindestens 10 Reverse | 52 | |
| linear ring - lalabai [Stratosphere / Normal] | 1436 | 196 | 76 | 0,05 bis 10 |
| linear ring - lalabai [Mesosphere / Hyper] | 1275 | 96 | 75 | 0,05 bis 10 |
| linear ring - lalabai [Thermosphere / Another] | 1112 | 59 | 56 | 0,05 bis 10 |
| linear ring - lalabai [Exosphere / Farewell] | 986 | 46 | 53 | 0,05 bis 10 |

In leichten Diffs (mehr Luecken) gibt es mehr Reverse. In dichten Diffs bleiben Bounce,
Teleport und Rueck-Sprung.

Bildfolge im Spiel (Debug):
`song_select.tscn --mania --autoplay --sv [--2d] --shot --shot-rev --shot-lead=<ms> --shot-seq=<n> --shot-step=<ms> --shot-out=<png>`.
`--shot-rev` sucht die erste Rueckwaerts-Phase (Kiai bevorzugt) mit mindestens 4 Noten im Bild.
Das Spiel speichert n Bilder in halber Aufloesung und gibt je Bild Zeit, m und Noten im Bild aus.

## Vergleich generiert und echt

Messung mit demselben Skript fuer beide Seiten.
- `gap` ist der Median-Abstand der gruenen Linien in Beats.
- `on_note` ist der Anteil der Linien auf Noten.
- `bar_sd` ist die Standardabweichung des 4-Beat-Mittels.

| Map | BPM | Linien/min | gap | Mittel | p05 | p50 | p95 | min | max | <0,5 | >2 | on_note | bar_sd |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SV-Mod: linear ring - lalabai call me | 208,5 | 405 | 0,30 | 1,000 | 0,40 | 1,0 | 1,90 | 0,10 | 10 | 9,1 % | 4,0 % | 0,51 | 0,008 |
| SV-Mod: Billain - Specialist | 173 | 427 | 0,20 | 1,000 | 0,40 | 0,96 | 2,00 | 0,25 | 10 | 9,2 % | 5,3 % | 0,41 | 0,000 |
| SV-Mod: Purukichi - Luster | 160 | 272 | 0,33 | 1,000 | 0,48 | 1,0 | 1,75 | 0,30 | 10 | 5,3 % | 1,7 % | 0,55 | 0,023 |
| SV-Mod: Zekk - Fluctuation | 194 | 338 | 0,30 | 1,000 | 0,63 | 1,0 | 1,75 | 0,40 | 10 | 4,5 % | 0,7 % | 0,62 | 0,000 |
| echt: mirror_2563907 [Expert] | 185 | 175 | 0,22 | 0,912 | 0,10 | 1,0 | 2,50 | 0,10 | 4,5 | 22,6 % | 7,4 % | 0,47 | 0,135 |
| echt: Camellia - PLANET//SHAPER [GEOLOGICAL] | 147 | 201 | 0,125 | 0,986 | 0,50 | 1,0 | 1,50 | 0,10 | 10 | 5,2 % | 0,5 % | 0,46 | 0,274 |
| echt: mirror_2323003 [Wicked Hard] | 180 | 812 | 0,165 | 1,006 | 0,33 | 1,0 | 1,67 | 0,01 | 4,0 | 10,2 % | 0,8 % | 0,26 | 0,023 |
| echt: mirror_2586880 [Swid] | 147 | 84 | 0,125 | 1,005 | 0,20 | 1,0 | 1,00 | 0,001 | 10 | 6,8 % | 0,6 % | 0,39 | 0,226 |

Fazit:
- Werteverteilung, Linien auf Noten, Anteil langsamer und schneller Abschnitte und die
  Linien-Dichte liegen im Bereich echter Ranked-SV-Maps.
- Die mittlere Geschwindigkeit ist exakt 1,0. Die Scroll-Speed-Einstellung stimmt also.
- Der Generator ist bewusst etwas zahmer als die wildesten Maps. Er erzeugt keine
  Werte unter 0,1 (echte Maps gehen bis 0,001) und keine Takte mit Mittelwert weit
  ueber 1. Grund: spielbar und fair.
- Kurztest im Spiel: Screenshot mit `res://scenes/song_select.tscn --mania --sv --shot`
  (Flags vor `--`, das Hauptmenue leitet sie nicht weiter). Map Antinomie [toumin's basic],
  242 BPM: Die Noten sind sichtbar, keine ist ueberlagert, der Abstand folgt der SV.

## Offen (Dateien anderer Tasks)

- **Badge "SV" in Results, Rangliste und Replays:** `results_screen.gd`, `score_store.gd`,
  `replay_store.gd` und `mania_3d.gd` muessen `stats.mods` anzeigen bzw. speichern.
  Der Wert steht bereit in `core.stats().mods`.
- **Multiplayer:** Raum-Sync macht der Task sv-mp.
