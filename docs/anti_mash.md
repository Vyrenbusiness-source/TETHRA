# Anti-Mash

Ziel: Tastenspam darf in Rebound, Rally, Orbit und Dirigent nicht mehr zu hoher Accuracy fuehren. Mania bleibt unveraendert (osu!mania-Verhalten), Trace regelt trace-fix.

## Regel (je Modus, deterministisch, replay-faehig)

Wrong key: Druck einer Taste/Zone ohne ungewertete Note im Miss-Fenster, waehrend eine andere Taste/Zone eine ungewertete Note im 50er-Fenster hat. Diese Note wird sofort Miss (Kombo bricht, kurzer Text "WRONG KEY"). Bei Akkord, Schmetterball und Akzent zaehlen nur die geforderten Tasten, jede weitere macht die Note zum Miss. Druck ohne Note in irgendeinem Fenster bewirkt nichts. Autoplay und Bot bleiben unberuehrt. Die Replay-Regelversion ist je Modus um 1 erhoeht, alte Replays werden mit Hinweis abgelehnt.

Umsetzung: Rebound in `scripts/rebound/rebound_anti_mash.gd` (duenne Schicht vor ManiaCore, ManiaCore unveraendert). Rally, Orbit, Dirigent in den jeweiligen Cores mit Flag `anti_mash` (Standard an; nur Tests fuer die Vorher-Zahlen und das Dirigent-Tutorial schalten es aus).

## Messwerte (Spam-Bot)

| Modus | Bot | vorher | nachher |
|---|---|---|---|
| Rebound | alle Tasten zu jeder Note | Acc 76.1% | Acc 25.9% |
| Rally | alle Tasten zu jeder Note | Acc 80.4% (11 Misses) | Acc 0.8% (119 Misses) |
| Orbit | A+B spammen, Cursor wie Autoplay | Acc 100.0% (0 Misses) | Acc 50.0% (20 Misses) |
| Dirigent | A+B/Akzent spammen | Einsatz-Acc 100.0% (0 Misses) | Einsatz-Acc 66.7% (8 Misses) |

Die Messungen laufen in den Modus-Tests (`tests/run_rebound_tests.gd`, `run_rally_tests.gd`, `run_orbit_core_tests.gd`, `run_dirigent_tests.gd`).
