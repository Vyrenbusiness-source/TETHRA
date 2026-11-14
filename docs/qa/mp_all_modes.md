# Multiplayer in allen 6 Modi (QA)

Stand: 2026-11-14, Branch `warmd/mp-all-modes`.

Ablauf je Modus: zwei headless Godot-Prozesse (Host + Bot-Client, je eigenes
APPDATA, Nutzerdaten unberuehrt). Direkt (ENet) mit `tools/mp_mode_smoke.sh`,
ueber einen echten Relay-Prozess mit `tools/mp_relay_smoke.sh MODE=<modus>`
(ruft denselben Ablauf mit `RELAY=1` auf). Raum-Mods: `MODS=NF` (`--mp-mods`).

    MODE=<modus> MODS=NF tools/mp_mode_smoke.sh
    MODE=<modus> MODS=NF tools/mp_relay_smoke.sh

## Ergebnis Modus x Fall

| Fall | Mania | Orbit | Rally | Dirigent | Trace | Rebound |
|---|---|---|---|---|---|---|
| Raum + beide bereit | OK | OK | OK | OK | OK | OK |
| Live-Board (Scores beider Seiten) | OK | OK | OK | OK | OK | OK |
| Endergebnis beider Seiten | OK | OK | OK | OK | OK | OK |
| Platzierung | OK | OK | OK | OK | OK | OK |
| Mods im Raum (NF, beide Seiten) | OK | OK | OK | OK | OK | OK |
| Zurueck in den Raum | OK | OK | OK | OK | OK | OK |
| Turnier / naechste Map | OK | OK | OK | OK | OK | OK |
| Relay (ganzer Ablauf) | OK | OK | OK | OK | OK | OK |

Jeder Fall: ein Lauf je Modus und Pfad. Mania wurde nach dem Merge von `main`
(Konflikt in `scripts/gameplay3d/mania_3d.gd` mit `--auto-skip` und
`--shot-on-fail`) noch einmal direkt gespielt (OK). Nach einem Merge mit neuen `class_name`s
braucht der Worktree einmal `godot --headless --import`, sonst Parse-Fehler.

Einschraenkung Trace: `scripts/trace/trace_game.gd` kennt kein `--auto-miss`.
Die Pruefung "Client mit Fehlern" (Miss-Bitfeld) wird dort uebersprungen (SKIP),
alle anderen Faelle laufen.

## Geaendert

- Mania hat einen MP-Bot (`--mp-bot`, `--mp-cut`, `--auto-miss`, `--mp-back`) in
  `scripts/gameplay3d/mania_3d.gd`. Rebound brauchte keine Aenderung.
- `tools/mp_mode_smoke.sh` deckt alle 6 Modi ab, `LIMIT` 150 s.
- Test-Watchdog in `scripts/game_session.gd`: 145 s statt 60 s fuer `--mp-bot`;
  fuer `--mp-relay` nur, wenn schon ein Limit aktiv ist (Testlauf mit
  `override.cfg`). Ein echter Relay-Server laeuft weiter ohne Limit.

## Regelaenderung: Platzierung nach Endergebnis

Vorher konnte die Platzierung einen veralteten Live-Score nutzen: ein spaetes
`cl_score`-Paket nach dem Endergebnis ueberschrieb den Endstand. Jetzt gilt:

- Die Platzierung nutzt den Endscore (`_apply_final_to_live` in
  `scripts/net/lobby.gd`).
- Live-Pakete (`cl_score`), die nach dem Endergebnis eines Spielers ankommen,
  werden ignoriert.

Test: `tests/run_lobby_tests.gd` (vor dem Fix rot, danach gruen).

## ObjectDB-Leak beim Beenden

Ursache (`--verbose`): `AudioStreamPlaybackMP3` und `AudioStreamMP3` blieben
uebrig, wenn das Spiel direkt nach `SyncClock.stop()` beendet wurde. Der
AudioServer gibt gestoppte Playbacks erst in einem spaeteren Mix-Schritt frei.

Fix: `GameSession._exit_tree` in `scripts/game_session.gd` stoppt alle
`AudioStreamPlayer`, `AudioStreamPlayer2D` und `AudioStreamPlayer3D` und wartet
120 ms (`EXIT_AUDIO_DRAIN_MS`).

Ergebnis: Rebound-Retry vorher 2 geleakte Objekte, danach 0. Live-QA fuer
mania3d, orbit und rebound: 0 Log-Fehler. Das war je ein Lauf. Die Warnung ist
in diesen Laeufen weg, aber nicht fuer alle Faelle bewiesen; sie trat vorher nur
gelegentlich auf.
