# SV-Mod wirkt nicht wie echtes SV: Untersuchung und Fix

Messung: alle 983 Mania-Diffs in `maps/` (221 .osz), headless, Kennzahlen aus der
`ScrollMap` (m = SV * BaseBeatLength / beatLength) zwischen erster Note und letztem Notenende.
"SV-Anteil" = Zeitanteil mit |m - 1| > 0,05. "Wechsel" = Spruenge |dm| > 0,05.

## Befund

| Gruppe | Diffs | SV-Anteil | Wechsel | max m |
|---|---|---|---|---|
| Ohne eigenes SV, vorher (Mod aus) | 922 | 0 % (Median) | 0 | 1 |
| Ohne eigenes SV, mit Mod | 922 | Median 62 % (p10 51 %, p90 71 %) | Median 672 | 10 |
| Starkes eigenes SV (>= 5 Spruenge/min), Mod unveraendert | 32 | 3-89 % (Median 29 %) | 26-4593 | bis 10 |
| Schwaches eigenes SV, vorher mit Mod | 29 | 41 % (nur BPM-Wechsel) | 5-21 | 1,0-2,0 |
| Schwaches eigenes SV, nachher mit Mod | 29 | Median 59 % | 1818-2447 | 10 |

Ursache: Der Generator laeuft fuer alle 922 Maps ohne eigenes SV sauber (SV-Anteil 37-84 %,
Ausnahme: eine 2-Noten-Diff). Das Problem lag in der Erkennung. `detect_sv` meldet "SV" bei
`frac >= 0,15` oder `jumps >= 12`. Die 29 Diffs von **xi - Happy End** (60 rote Linien) erfuellen
`frac` allein durch BPM-Wechsel mit Ausgleichslinien. Sie haben 0-3 Spruenge/min und 1-3 Wechsel/min,
der Mod erzeugte dort **nichts** ("eigenes SV bleibt unveraendert"). Das ist der gemeldete Fall:
gleichmaessige Noten, kein spuerbares SV.

Schwelle: Spruenge pro Minute. Die schwachen Maps liegen bei 0,0-3,0, die schwaechste echte
SV-Map (MX, 14 Spruenge in 2,3 min) bei 6,1. Es gibt keine Map zwischen 3,0 und 6,1.
`MapLibrary.SV_STRONG_JPM = 5.0` liegt in dieser Luecke.

Weitere Verdachtsfaelle geprueft, ohne Befund: viele BPM-Wechsel (Kataoka Tsugumi, 52 rote Linien:
SV-Anteil 47-65 %), sehr langsame/schnelle BPM, Maps ohne Kiai (obere 25 % der Takte gelten als lebendig),
Fairness-Verwurf (kein Fall unter 25 % SV-Anteil, ausser 2-Noten-Diff).

## Fix

- `MapLibrary.sv_stats_tp` liefert zusaetzlich `jpm` (Spruenge/min); neu `MapLibrary.has_strong_sv`.
- `SvMod.has_own_sv` nutzt `has_strong_sv`: schwaches SV zaehlt nicht als eigenes. Der Mod
  ersetzt dort die gruenen Linien durch generiertes SV (BPM-Wechsel werden dabei normalisiert,
  Mittel m = 1 je Block bleibt). Starkes eigenes SV bleibt 1:1. Die Browser-Markierung "SV"
  (`detect_sv`) bleibt unveraendert.
- Fairness-Regeln (nie Noten ueberlagert, Mittel 1 je Block, m > 0) gelten nur fuer generiertes SV.

## Abgleich ScrollMap/ManiaCore mit osu!

| Punkt | Ergebnis |
|---|---|
| SV = 100 / -beatLength, Grenzen 0,01..10 | ok (`green_sv`) |
| Gruene Linie mit beatLength >= 0 oder NaN | SV 1,0, ok |
| BPM-Skalierung relativ zur haeufigsten BPM, keine Normalisierung | ok (`_most_common_beat_length`) |
| Mehrere Linien gleicher Zeit | ok: rot vor gruen, die letzte gewinnt. Rote Linie setzt SV auf 1 zurueck (wie lazer) |
| **SV vor der ersten roten Linie** | **Abweichung, behoben.** Die Tabelle nahm `DEFAULT_BL` (1000 ms) statt dem Tempo der ersten roten Linie. Beispiel: erste rote Linie 400 ms, gruene Linie vor ihr: m war 0,4 * SV statt SV. Gleiche Korrektur in `sv_stats_tp` |
| Scroll-Speed-Einstellung | reiner Faktor: `preempt = BASE_PREEMPT / clamp(scroll, 0.5, 3)`, ok |
| Hold-Koerper | ok: Kopf und Ende laufen ueber `_note_z` (SV-Positionstabelle), der Koerper spannt zwischen beiden Positionen. Keine lineare Zeit |

## Startwege des Mods

`GameSession.mods` wird gesetzt in: Song-Browser (`song_select.gd` Play und Replay), Multiplayer
(`lobby.gd` uebernimmt die Raum-Mods). Neustart aus Pause und 2D/3D laden die Szene neu und lesen
`GameSession.mods` ueber `ManiaCore.session_mods()`: wirkt. Luecken in Dateien ausserhalb dieses Auftrags:

- `scripts/ui/profile_panel.gd:569` setzt `mods = {"NF": false}`: Start aus dem Profil ignoriert SV und NF der Einstellungen.
- `scripts/game_session.gd:99` (Clip-Modus) setzt `mods = {}`.
- Replay aus dem Browser nimmt die aktuell gewaehlten Mods, nicht die des Laufs (Replay-Datei speichert keine Mods).
  Gleiche Map ergibt gleiches generiertes SV (Seed = Map-Hash), nur der Schalter muss passen.

## "Noten gehen nicht nach oben"

Das osu!-Format kennt kein negatives SV: 100 / -beatLength ist immer positiv, die Tabelle klemmt auf 0,01..10.
Rueckwaerts laufende Noten gibt es in osu!mania nicht, auch nicht in den SV-Maps der Bibliothek (min m = 0,01).
Gemeint ist wahrscheinlich "schneller werden, springen" (Speed-Ups), das der Mod jetzt auf jeder Map liefert.
Nicht gebaut.

## Tests

`tests/run_sv_mod_tests.gd`: schwaches SV (BPM-Wechsel mit Ausgleich) bekommt SV (erkannt, aber < 5/min;
43 % der Zeit m != 1, max m 4,5, fair); ScrollMap-Abgleich (SV vor erster roter Linie, gleiche Zeit,
positive gruene Zeit, Grenzen); starkes eigenes SV mit Mod 1:1.
