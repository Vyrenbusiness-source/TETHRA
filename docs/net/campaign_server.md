# Kampagne: Server-Vorschlag (noch nicht gebaut)

Stand Client v1: Stufen-Ranglisten kommen aus `GET /leaderboard` (vorhanden).
Die Gesamtrangliste ist nur lokal. Dieser Vorschlag ergaenzt sie auf dem Server.
Der Client sendet bis dahin nichts Neues.

## 1. POST /score: neues optionales Feld

```json
{ "mode": "mania", "beatmap_md5": "...", "score": 912345, "campaign": "v1/mania-c03s2" }
```

- `campaign`: `<version>/<stufe>`. Fehlt bei freien Laeufen. Unbekannte Werte ignorieren.
- Der Server kennt die Stufenliste (Kopie von `data/campaign.json`: `id`, `mode`, `md5`, `mods`, `goals`).
- Annehmen nur, wenn `mode`, `beatmap_md5` und `mods` zur Stufe passen. Sonst Score normal speichern, Kampagne ignorieren.
- Sterne rechnet der Server selbst aus dem Score (nie vom Client uebernehmen):
  - `pass`: nicht `failed`
  - `acc`: `accuracy >= value`
  - `grade`: Rang mindestens `value` (F < D < C < B < A < S < SS)
  - `miss`: `n_miss <= value`
  - Zusatz- und Meisterziel zaehlen nur mit dem Hauptziel. Fail = 0 Sterne.
- Je Spieler und Stufe speichern: erfuellte Ziele (ODER ueber alle Laeufe), bester Score mit erfuelltem Hauptziel.

Antwort (zusaetzlich zu den bisherigen Feldern):

```json
{ "campaign": { "stage": "mania-c03s2", "stars": 2, "total_stars": 41, "total_points": 12345678, "rank": 17 } }
```

## 2. GET /campaign/leaderboard

`GET /campaign/leaderboard?version=v1&mode=mania&limit=50&offset=0`

Je Modus eine eigene Rangliste (`mode` Pflicht). Der Modus steht auch vorn in der Stufen-ID.

```json
{ "version": "v1", "max_stars": 234, "entries": [
  { "rank": 1, "player": "name", "player_id": "id", "stars": 198, "points": 61234567,
    "stages_cleared": 71, "chapter": 12, "updated": "2026-11-13T18:00:00" } ],
  "me": { "rank": 17, "stars": 41, "points": 12345678 } }
```

Sortierung: `stars` absteigend, dann `points` absteigend, dann `updated` aufsteigend.
`me` nur mit Login.

## 3. GET /campaign/progress (optional, Geraetewechsel)

`GET /campaign/progress?version=v1` mit Login:

```json
{ "version": "v1", "stages": { "mania-c01s1": { "met": [true, true, false], "score": 812345, "accuracy": 0.962, "grade": "A" } } }
```

Der Client fuehrt das mit dem lokalen Stand zusammen (Ziele ODER, Score Maximum).

## 4. Regeln

- Neue Map-Liste = neue Version (`v2`). Alte Ranglisten bleiben lesbar.
- Rate-Limit und Replay-Pruefung wie bei `POST /score`.
- Kein Schreiben ohne Login.
