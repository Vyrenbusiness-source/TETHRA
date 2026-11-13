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
- **Lesbarkeit:** Je Zone ein fester Umriss in Ballgroesse am Treffpunkt ueber der Schlaglinie; ein
  Ring erscheint, wenn der Ball losfliegt, und zieht sich bis zur Notenzeit auf den Umriss zusammen
  (naechster Schlag kraeftig, folgende duenn und erst ab einer Beat-Laenge). Der Aufsetzpunkt ist
  nur eine feste, leise Marke (schrumpft nicht, kein zweites Zeitsignal); Ball mit Schatten auf dem Tisch (Schatten zeigt die Zone schon im Flug). Raum: Rueckwand, Boden und Leuchte ueber dem Tisch (nur Optik); Baelle als Kugeln mit weichem Schatten.
  Schmetterball weiss umrandet + max. 1,4x Ball, Aufladen mit Laufband ueber die Zone.
- **Gefuehl:** Gegner spielt sichtbar (Schlaeger schwingt je Ball, bei Streams schneller
  "Mehrball"), Ballwechsel-Zaehler, dezente unscharfe Publikums-Silhouetten, Licht reagiert leise auf Kombo (nie grell, kein
  Wackeln ausser <= 2 px beim Schmetterball), satter Schlagklang je Zone (tief nach hoch).
- Replays: meta rules = 2 (alte Rally-Replays/Scores < 1.27.0 sind nicht vergleichbar).
- **Anti-Mash (Regeln v3):** Druck in einer Zone ohne Ball im Miss-Fenster, waehrend eine
  andere Zone einen ungewerteten Ball im 50er-Fenster hat = "WRONG KEY": dieser Ball ist
  sofort Miss (Kombo bricht). Schmetterball: nur seine zwei Zonen zaehlen, eine dritte Zone
  macht ihn zum Miss. Richtige Taste zuerst, falsche danach: Treffer bleibt. Druck ohne Ball
  in irgendeinem Fenster = nichts. Replays: meta rules = 3 (rules 2 wird abgelehnt). Messwerte: docs/anti_mash.md.

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
(0,45); Dichte-Kurve `0,11 * x^1,55`, haerteste Fenster zaehlen am meisten (Abklingfaktor 0,95),
weiche Kappe ab 11, Maximum 15. Kalibriert auf der Kartenbibliothek: Median ~4 Sterne.
Messwerte (1101 Schwierigkeiten aus 239 Maps, Flugzeit 800): 4 Zonen p10 1,1 / p25 2,3 / Median 4,1 / p75 5,7 /
p90 7,4 / max 12,4; 3 Zonen Median 3,9 (p90 7,2). Bei 3 Zonen sind Zonensprung-Abstaende auf 4 Zonen normiert.

## 3 oder 4 Zonen
`Settings.rally_zones` (3 oder 4, Standard **3**: links / Mitte / rechts; Einstellungen > Steuerung > Rally).
- Mania 4K: Spalte 0 = links, Spalte 1 und 2 = Mitte, Spalte 3 = rechts. Akkord Spalte 1+2 ist dann
  ein normaler Ball (kein Schmetterball); links+rechts bleibt Schmetterball (Zonen 0 und 2).
  Andere Spaltenzahlen werden gleichmaessig auf die Zonen verteilt.
- osu!standard: Feld-x in 3 Streifen (x < 171 / < 341 / sonst); bei 4 Zonen 4 Streifen zu 128.
- Tasten: 3 Zonen = `Settings.rally_keys_3` (Standard F J K), 4 Zonen = Mania-4K-Tasten.
- `RallyChart.build(..., zones)` merkt die Zonenzahl (`RallyChart.zone_count()`), `RallyCore.zones`
  uebernimmt sie. Sie steht in der Regel-Marke des Replays (`[0, 9, 2, zonen]`), das Abspielen
  nutzt die Zonenzahl der Aufnahme, nicht die aktuelle Einstellung.

## Einstellung
`Settings.rally_flight_ms` (Flugzeit, 450-1400 ms, Standard 800, Einstellungen > Steuerung > Rally).
Tasten der Zonen = Mania-4K-Tasten (`Settings.key_lanes`). Replay-Codes: EV_DOWN 1-4, EV_UP 5-8
(je Zone), Regel-Marke 9 (mit Zonenzahl).

## Code
scripts/rally/ (rally_chart.gd, rally_core.gd, rally_view.gd, rally_game.gd), scenes/rally.tscn,
tests/run_rally_tests.gd.
