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
  - m liegt zwischen 0,1 und 10 und ist immer groesser 0, also nie rueckwaerts.
  - Kein Abschnitt ist kuerzer als 4 ms.
  - Das erste Segment hat m = 1, damit der Anlauf nicht beschleunigt.
  - Noten derselben Spalte (auch Hold-Kopf und Hold-Ende) behalten einen Positionsabstand
    von mindestens 30 % der Zeit bzw. 24 ms. Sonst faellt der Block auf m = 1 zurueck.
- **Map mit eigenem SV** (`MapLibrary.detect_sv`): Ihr SV bleibt unveraendert, es wird nicht doppelt gemischt.

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
