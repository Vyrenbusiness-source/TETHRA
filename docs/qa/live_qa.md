# Live-QA: Spielablauf in allen 6 Modi (2026-11-13)

Stand: Branch `warmd/qa-live` auf v1.31.0. Alles unten ist per Lauf belegt, nicht am Code gelesen.

## Wie geprüft wurde

- Treiber `tests/live_qa.gd` (Aufruf `tests/live_qa.sh [modus] [flow|retry|mods|fail]`) startet die echten
  Spielszenen in einem Fenster (Monitor 2, Dummy-Audio, `timeout 150`, eigenes `APPDATA`: Nutzer-Einstellungen
  und Scores bleiben unberührt).
- Mania 2D/3D, Trace, Rebound: echte Tastenereignisse (`Input.parse_input_event`) aus einem Plan mit
  ±14 ms Streuung und jeder 5./7./9. Note ausgelassen. Orbit, Rally, Dirigent: eingebauter Bot
  (`--autoplay --auto-jitter=10 --auto-aim=0.5`, Mod-Läufe zusätzlich `--auto-miss=6`).
- Escape, Leertaste und R kommen immer als echte Tastenereignisse.
- Map: erzeugte 4K-Map `QA4K` (38 Noten, 1 Hold, Break 11–18 s, erste Note bei 6 s) und `QAFAIL`
  (129 Noten, HP 10) auf der Audiospur einer echten Map. Dirigent läuft 6 s später (`--qa-shift=6000`),
  weil er vor der ersten Note Schläge vorzählt und der Intro-Skip sonst nicht auslöst.
- Multiplayer: `tools/mp_mode_smoke.sh` (Host + Client mit `--mp-bot`), Raum-Mod NF über die neue
  Debug-Option `--mp-mods=` / `TETHRA_MP_MODS`.
- Jedes Log auf `SCRIPT ERROR`, `ERROR:`, `WARNING:`, `Invalid call/access`, Watchdog durchsucht.

## Ergebnis je Modus und Fall

| Fall | Mania 2D | Mania 3D | Orbit | Rally | Dirigent | Trace | Rebound |
|---|---|---|---|---|---|---|---|
| Intro-Skip (Leertaste) | ok | ok | ok | ok | ok | ok | ok |
| Pause mitten im Song (Uhr steht, Menü da) | ok | ok | ok | ok | ok | ok | ok |
| Resume (Uhr springt nicht, nächste Noten getroffen) | ok | ok | ok | ok | ok | ok | ok |
| Break: Ring/Countdown verdeckt nichts | ok | Bug behoben | Bug behoben | ok (kein Ring) | ok (kein Ring) | ok (kein Ring) | ok (kein Ring) |
| Break: erste Note danach fair | ok | ok | ok | ok | ok | ok | ok |
| Retry Taste R im Song | ok | ok | ok | ok | ok | ok | ok |
| Retry im Pausenmenü | ok | ok | ok | ok | ok | Bug behoben | Bug behoben |
| Retry im Ergebnis | ok | ok | ok | ok | ok | ok | ok |
| Retry: Mods und Einstellungen bleiben, Score/HP zurück | ok | ok | ok | ok | ok | ok | ok |
| Fail ohne Eingabe: Fail-Bild | ok | ok | ok | ok | kein Fail im Modus | ok | ok |
| NF ohne Eingabe: läuft bis zum Ende | ok | nicht gelaufen | ok | ok | ok (NF wirkungslos) | ok | ok |
| Songende -> Ergebnis | ok | ok | ok | ok | ok | ok | ok |
| Replay ansehen = gleiche Wertung | ok | ok | ok | ok | ok | ok | ok |
| Mods: Faktor im Ergebnis | NF 0,5 / SV 1,1 / HD, FI, CS 1,0 ok | NF / SV / CS ok | NF 0,5 / HD 1,06 / FI 1,06 / PR 1,12 ok | NF 0,5 ok | NF ohne Wirkung (Regel) | NF 0,5 / MR 1,0 / HD 1,06 / SS 1,08 ok | NF 0,5 ok, SV wirkungslos (Regel) |
| Multiplayer-Raum mit Bot, Mod NF im Raum | offen (Smoke kennt Mania nicht) | offen | ok | ok | ok (NF wirkungslos) | ok | offen (nicht im Smoke) |
| Log ohne Skriptfehler | ok | ok | ok | ok | ok | ok | ok |

Messwerte (Beispiele): Pause bei 8627 ms, nach 1,2 s unverändert; nach Resume 8633 ms, Sichtuhr gleich,
größter Bildschritt in 40 Bildern 4,7–5,6 ms. Intro-Skip lässt 2,1 s (Mania) bis 2,5 s (Rebound) Vorlauf.
Replay: Score, Genauigkeit, Kombo, Note und alle Zähler identisch (z. B. Mania 2D 639 955 / 89,47 %).
Mod-Faktor: Score = Rohwert × Faktor (Mania/Trace/Rebound) bzw. gleicher Bot-Lauf × Faktor ±2 (Orbit/Rally).
Multiplayer Runde 1 mit NF: Rally 197 674 -> 98 837, Orbit 189 213 -> 94 606, Trace 204 651 -> 102 326
(Host und Client melden `mods=[NF]`); Runden 2 und 3 sind das Turnier mit eigener Mod-Einstellung.

## Behobene Bugs

1. **Chat-Overlay ging im Spiel auf und schluckte Escape** (Rebound, Rally, Trace, Dirigent).
   Taste F ist Chat-Taste und in Rebound/Rally zugleich Spieltaste; `ChatOverlay` kennt nur Mania und Orbit
   als Spielszene. Folge im Lauf: Overlay offen, das nächste Escape schloss den Chat statt zu pausieren.
   Fix: `GameSession._gate_chat` sperrt die Eingabe des Overlays in allen sechs Modi und im Bild des
   Szenenwechsels. Test `tests/run_chat_gate_tests.gd`, im Lauf `chat-zu` und `retry-pausenmenue`.
   Offen für den Besitzer von `scripts/ui/chat_overlay.gd`: `_gameplay_scene` (Zeile 94) um die vier Modi ergänzen.
2. **Break-/Intro-Ring verdeckte anfliegende Noten** (Mania 3D, Orbit). Der Ring lag bis zur Trefferzeit
   mitten auf der Bahn bzw. im Orbit-Feld. Fix: gleiche Regel wie der 2D-Rückfall, `BreakOverlay.clear_alpha`:
   der Ring ist weg, bevor die erste Note nach dem Break sichtbar wird. Test `tests/run_break_clear_tests.gd`,
   im Lauf `break-ring-frei`. Mania 2D unverändert (Ring steht neben dem Feld).
3. **Skriptfehler im Ergebnisbild bei sofortigem Szenenwechsel** (alle Modi):
   `ResultsScreen._play_intro` rief `get_tree()` auf, nachdem der Knoten den Baum verlassen hatte
   (Retry/Replay im ersten Bild). Fix: `_two_frames()` bricht sauber ab. Test `tests/run_results_intro_tests.gd`.

## Neue Debug-Optionen

- `--live-qa`: Test-Watchdog 145 s statt 45/60 s (`scripts/game_session.gd`).
- `--mp-mods=NF,SV` oder Umgebungsvariable `TETHRA_MP_MODS`: Mods eines neuen Raums; mit `--mp-bot`
  meldet die Lobby je Runde `MPLOBBY round mods=[..]` (`scripts/net/lobby.gd`).
- `tests/live_qa.gd`: `--qa-mode=`, `--qa-cases=`, `--qa-src=`, `--qa-out=`, `--qa-shift=`.

## Regeln

Keine Wertungsregel geändert, keine Replay-Regel-Version erhöht. Der Break-Ring ändert nur die Anzeige.

## Offen

- Multiplayer Mania und Rebound: `tools/mp_mode_smoke.sh` deckt beide nicht ab (Mania hat keinen MP-Bot).
- Dirigent: kein Fail und NF ohne Wirkung sind Regel; ob der Browser NF für Dirigent anbietet, ist nicht geprüft.
- Trace MR/HD/SS und Mania HD/FI/CS stehen nicht in `stats.mods`; ob das Ergebnisbild ihr Abzeichen zeigt,
  ist nicht geprüft (Faktor und Wirkung im Lauf sind belegt).
- „Noten nach Resume mit voller Anflugzeit sichtbar“ ist über die Uhr belegt (Spiel- und Sichtuhr laufen
  ohne Sprung weiter, die nächsten Noten werden getroffen), nicht über Pixel.
- Break-Ring in Mania 3D und Orbit: der 3-2-1-Countdown ist jetzt früher weg. Ein Blick eines Menschen fehlt.
- Warnung `2–3 ObjectDB instances were leaked at exit` in manchen Läufen mit Retry/Replay, nicht in jedem.
  Ursache nicht gesucht (tritt beim Beenden mitten im Start-Countdown auf).
- Der bekannte Fehler `Cannot call method 'create_timer' on a null value` trat in keinem Lauf auf.
- Mania 3D: NF ohne Eingabe nicht gelaufen (2D gelaufen, gleicher Core).
