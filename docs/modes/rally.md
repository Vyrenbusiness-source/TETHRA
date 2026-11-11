# Rally (neuer Modus, 2026-11-11)

Tischtennis im Takt einer normalen .osz-Map (osu!standard oder Mania 4K).

## Regeln
- Seitenansicht: Spieler links, Gegner rechts, Tisch, **ein** Ball.
- Jede Note der Map (nach Zusammenfassen) ist **dein Schlag** genau zur Notenzeit. Nach deinem
  Schlag fliegt der Ball zum Gegner, prallt auf dessen Tischhaelfte, der Gegner schlaegt zur
  Mitte der Zeit bis zur naechsten Note zurueck, der Ball prallt auf deiner Haelfte und
  erreicht deinen Schlaeger exakt zur naechsten Notenzeit. Flugzeit = Notenabstand: grosse
  Abstaende = hoher langsamer Lob, Streams = flacher schneller Wechsel.
- Tasten: tiefer Ball = A, hoher Ball = B (osu!: Whistle/Clap = B, sonst A; Mania: Spalten
  1-2 = A, 3-4 = B). Finish bzw. Akkord ueber beide Seiten = **Schmetterball**: beide Tasten
  (innerhalb 40 ms). Lange Note/Slider = **Aufladen**: Taste halten, am Ende loslassen.
- Zeitfenster aus OD wie Mania (MAX/300/200/100/50/Miss), Zusammenfassen < 90 ms bzw. 1/4 Beat
  bei leichten Maps (< 2,5 Noten/s nur Achtel).
- Lesbarkeit: Aufprallmarke + Schatten auf deiner Seite zeigt WANN (Ring schrumpft auf die
  Notenzeit) und WELCHE Taste (Farbe A kuehl / B warm, Schmetterball weiss umrandet).
  Naechster Ball deutlich, sonst nichts Bewegtes im Weg.
- Fehlschlag: Ball fliegt vorbei, kurzer Neuaufschlag des Gegners (Ball erscheint fuer die
  naechste Note neu).

## Wettbewerb und Multiplayer (Pflicht)
- Deterministische Wertung (Ereignis-Log, bildratenunabhaengig), Replays (meta rules = 1).
- Score/Acc/Grades wie Mania (ScoreV1, stats() mit n_max..n_miss, max_combo, accuracy, score,
  grade, mode "rally"), Sterne 0..15 (Dichte, Tastenwechsel, Schmetterbaelle, Aufladen),
  ScoreStore-Modus "rally", Online-Submit mode "rally" (Server erweitert sich).
- Multiplayer: Live-Score (Lobby.send_score) und Endergebnis (Lobby.send_final mit
  PlayerStatsCard.pack) wie mania_3d/orbit_game; Turniere ueber Lobby wie die anderen Modi.

## Code
scripts/rally/ (rally_chart.gd, rally_core.gd, rally_view.gd, rally_game.gd), scenes/rally.tscn,
tests/run_rally_tests.gd.
