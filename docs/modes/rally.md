# Rally (neuer Modus, 2026-11-11)

Tischtennis im Takt einer normalen .osz-Map (osu!standard oder Mania 4K).

## Regeln v2 (4 Zonen, 2026-11-12, verbindlich)
Alte Fassung (Seitenansicht, A/B) ist ersetzt: sie war langweilig (nichts zu lesen, nichts zu entscheiden).

- **Ansicht hinter dem Spieler:** Kamera knapp hinter und ueber deinem Schlaeger, der Tisch laeuft
  in Perspektive vom unteren Bildrand weg, Netz in der Mitte, Gegner am fernen Ende. Deine
  Tischhaelfte ist in **4 Zonen** (Spalten links nach rechts) geteilt, dezent markiert,
  Tasten wie Mania 4K (Settings, Standard D F J K) unten an den Zonen.
- **Ein Ball je Note.** Jede Note (nach Zusammenfassen) ist ein Ball, der in einer Zone landet
  und zur Notenzeit an deiner Schlaeger-Linie ankommt. Du triffst ihn mit der Zonentaste.
  - Mania 4K: Zone = Spalte (exakt die Notenfolge der Map, perfekt im Takt).
  - osu!standard: Zone = Feld-x in 4 Streifen (x < 128 / 256 / 384 / sonst).
- **Konstante Flugzeit** (wie Scroll-Speed): Jeder Ball wird `FLIGHT_MS` vor seiner Notenzeit
  beim Gegner gespielt (Einstellung "Flugzeit" 450-1400 ms, Standard 800; Mod-unabhaengig
  fuer die Wertung). Darum sind bei Streams mehrere Baelle gleichzeitig in der Luft
  ("Mehrball-Training") – lesbar, weil jeder Ball denselben Weg in derselben Zeit nimmt.
  Bogenhoehe nach Abstand zur vorigen Note (gross = Lob, klein = flacher Drive), nur Optik.
  Zonenwechsel ueber >= 2 Spalten = leichter Seitwaerts-Effet in der Kurve (Topspin-Optik).
- **Akkord** (2+ Noten gleichzeitig) = **Schmetterball**: ein grosser Ball, landet zwischen
  den Zonen; alle beteiligten Zonentasten (max. 2, aeussere) innerhalb 40 ms. >2 Noten: die
  zwei aeussersten Spalten.
- **Lange Note/Slider** = **Aufladen**: Zonentaste halten, Ball bleibt am Schlaeger ("Spin
  aufladen", Ring fuellt sich), am Ende loslassen; Wertung wie Mania-Hold (osu!mania stable).
- **Wertung** wie Mania (OD-Fenster, MAX/300/200/100/50/Miss, ScoreV1), falsche Zone = kein
  Treffer (Taste ohne Ball in der Zone wird ignoriert, kein Notelock zwischen Zonen).
- **Lesbarkeit:** Landepunkt-Ring in der Zone erscheint, wenn der Ball losfliegt, und schrumpft
  bis zur Landung; Ball mit Schatten auf dem Tisch (Schatten zeigt die Zone schon im Flug).
  Schmetterball weiss umrandet + groesser, Aufladen mit Laufband ueber die Zone.
- **Gefuehl:** Gegner spielt sichtbar (Schlaeger schwingt je Ball, bei Streams schneller
  "Mehrball"), Ballwechsel-Zaehler, Publikum/Licht reagiert auf Kombo (nie grell, kein
  Wackeln ausser <= 2 px beim Schmetterball), satter Schlagklang je Zone (tief nach hoch).
- Replays: meta rules = 2 (alte Rally-Replays/Scores < 1.27.0 sind nicht vergleichbar).

## Schnittstelle Chart -> Ansicht
`RallyChart.Shot`: `t` (Notenzeit ms), `zones: PackedInt32Array` (1 oder 2 Zonen 0..3),
`smash: bool`, `charge: bool`, `end` (ms, Aufladen), `launch` (= t - flight_ms),
`arc` (Bogenhoehe 0..1), `curve` (-1..1 Seitwaerts-Effet). `RallyChart.ball_pos(shot, t) ->
Vector3` (Tischkoordinaten: x -1..1 quer, y Hoehe, z 0 = deine Schlaegerlinie .. 1 = Gegner),
`landing_time(shot)`, `zone_x(zone) -> float`. Die Ansicht projiziert Vector3 selbst
(Perspektive) und zeichnet nur; Wertung nur im Core.

## Wettbewerb und Multiplayer (Pflicht)
- Deterministische Wertung (Ereignis-Log, bildratenunabhaengig), Replays (meta rules = 2).
- Score/Acc/Grades wie Mania (ScoreV1, stats() mit n_max..n_miss, max_combo, accuracy, score,
  grade, mode "rally"), Sterne 0..15 (Dichte, Tastenwechsel, Schmetterbaelle, Aufladen),
  ScoreStore-Modus "rally", Online-Submit mode "rally" (Server erweitert sich).
- Multiplayer: Live-Score (Lobby.send_score) und Endergebnis (Lobby.send_final mit
  PlayerStatsCard.pack) wie mania_3d/orbit_game; Turniere ueber Lobby wie die anderen Modi.

## Sterne (v2, Zonen)
`RallyChart.stars`: je 2-s-Fenster Last (Baelle/s), je Ball 1 + Zonensprung (0,16 je Zonen-Abstand,
nur bei Abstand < 450 ms) + Stream (0,25 bei Abstand < 200 ms) + Schmetterball (0,7) + Aufladen
(0,45); Dichte-Kurve `0,15 * x^1,55`, haerteste Fenster zaehlen am meisten (Abklingfaktor 0,95),
weiche Kappe ab 11, Maximum 15. Kalibriert auf der Kartenbibliothek: Median ~4 Sterne
(Messwerte unten).

## Einstellung
`Settings.rally_flight_ms` (Flugzeit, 450-1400 ms, Standard 800, Einstellungen > Steuerung > Rally).
Tasten der Zonen = Mania-4K-Tasten (`Settings.key_lanes`). Replay-Codes: EV_DOWN 1-4, EV_UP 5-8
(je Zone), Regel-Marke 9.

## Code
scripts/rally/ (rally_chart.gd, rally_core.gd, rally_view.gd, rally_game.gd), scenes/rally.tscn,
tests/run_rally_tests.gd.
