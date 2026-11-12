# Daily Trace: Text fuer den Server-Betreiber

## Stand im Client

Daily Trace laeuft komplett lokal (`scripts/trace/trace_daily.gd`):

- Tagesmap = FNV-1a-Hash von `trace-daily:YYYY-MM-DD` (UTC) modulo Liste der Kandidaten.
  Kandidaten online: erste Seite Ranked-4K-Maps des Map-Browsers (Mirror, Sortierung "Beliebteste"),
  offline: lokale 4K-Maps. Gespeichert wird in `user://trace_daily.cfg` (Tag -> Map, Score).
- Ein Versuch pro Tag zaehlt (Start = Versuch). Serie = Tage in Folge mit Versuch.

## Was der Server heute kann (`scripts/net/online_api.gd`)

- `POST` Score je Lauf (`build_body`): Modus, `beatmap_md5`, Score, Genauigkeit, `date` usw.
- `GET /leaderboard?mode=&md5=&limit=[&beatmap_id=]`: Rangliste je Map und Modus,
  Felder `rank, player, score, accuracy, grade, max_combo, pp, mods, date, player_id`.

Es gibt keinen Endpunkt fuer eine Tages-Map und keine Tagesrangliste. Der Client erfindet keinen.
Trace-Laeufe der Tagesmap landen normal als Trace-Score in der Rangliste der Map (alle Zeiten).

## Vorschlag (nur falls gewuenscht, nichts davon ist im Client verdrahtet)

1. `GET /daily?mode=trace` -> `{ "day": "YYYY-MM-DD", "beatmapset_id": int, "beatmap_md5": str, "difficulty": str }`.
   Der Server legt die Tagesmap fest. Dann sehen alle dieselbe Map, auch wenn sich die
   Mirror-Suchergebnisse aendern (heute leitet jeder Client sie selbst ab; bei gleicher
   Mirror-Liste ist das Ergebnis gleich, bei geaenderter Liste kann es abweichen).
2. `GET /leaderboard?mode=trace&md5=<md5>&since=<YYYY-MM-DD>&until=<YYYY-MM-DD>&limit=50`:
   bestehende Rangliste mit Datumsfilter auf das Feld `date` (UTC). Damit ist die
   Tagesrangliste ohne neue Tabelle moeglich.
3. Pro Spieler und Tag zaehlt der erste Trace-Lauf der Tagesmap (Client sendet `date`).
   Regel serverseitig pruefen, wenn die Wertung fair sein soll.

Die Antwortfelder bleiben wie bei `/leaderboard`, damit `OnlineApi.parse_leaderboard` unveraendert passt.
