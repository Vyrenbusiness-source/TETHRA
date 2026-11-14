# OMEN-Server: Soll-Stand (immer aktuell)

Diese Datei beschreibt, was der Server (butzebot.com) für den aktuellen OMEN-Client können muss.
Sie wird bei jeder Client-Änderung, die den Server betrifft, im selben Commit angepasst.
Ein Server-Betreiber (oder seine KI) muss nur diese Datei lesen, nicht jede Version einzeln.

Rohdatei zum automatischen Abrufen:
`https://raw.githubusercontent.com/Vyrenbusiness-source/OMEN/main/docs/server/SERVER.md`
Änderungsverlauf: `git log -p -- docs/server/SERVER.md` bzw. GitHub "History" dieser Datei.

Stand: Client v1.43.1 · `min_version` = **1.30.0**

---

## 0. Einmalig einrichten, damit nicht jede Version Arbeit macht

1. **Relay aktualisiert sich selbst** (ab Client v1.44.0): Der Relay-Prozess (`OMEN.exe --headless --mp-relay --port 47900`)
   prüft alle 10 Minuten das neueste GitHub-Release. Gibt es ein neues `OMEN.pck`, lädt er es neben die Exe,
   beendet sich mit Code 75 und wird von pm2 mit der neuen Version neu gestartet. Voraussetzung:
   - pm2 mit `autorestart: true` (Standard) und Schreibrecht im Relay-Ordner.
   - Einmal von Hand auf v1.44.0 oder neuer bringen; danach nie wieder.
   - Abschalten: `--no-self-update`.
2. **Diese Datei beobachten** statt Nachrichten: z. B. täglich die Rohdatei abrufen und bei Änderung
   (ETag/Hash) die KI die neuen Punkte umsetzen lassen. Oder auf GitHub die Datei "watchen".
3. **Neue Modi/Mod-Kürzel generisch annehmen**: Der Client schickt neue Spielarten als neuen `mode`-Wert
   oder als `board`. Wenn der Server unbekannte `mode`/`board`-Werte einfach als eigene Rangliste speichert
   (statt mit 400 abzulehnen), funktioniert jede neue Variante ohne Server-Änderung.

---

## 1. Name: TETHRA → OMEN

Der Client heißt OMEN. Server-Pfade sollen wieder `omen` heißen, in zwei Schritten:

**Schritt 1 (jetzt):** `omen` **zusätzlich** anbieten, `tethra` weiter bedienen.
- API: alles unter `/panel-api/tethra/*` auch unter `/panel-api/omen/*` (gleiche Handler, gleiche Daten).
- Header: `x-omen-api-key` und `x-omen-user-token` gleichwertig zu `x-tethra-*` (gleicher Key, gleiche Tokens).
  Der Client schickt unter `omen` beide Header-Sätze.
- Website: `/omen/player/<name>`, `/omen/score/<id>`, `/omen/map/<md5>` wie `/tethra/…`.
- Relay: zusätzlich `/omen/mp` (WebSocket) und `/omen/rooms` (Port 47900).
- Wichtig: `GET /panel-api/omen/auth/me` ohne Token muss **401 mit JSON** liefern (heute: 404).
  Daran erkennt der Client die neue Route und stellt selbst um. Mit Token muss es die vorhandenen Tokens annehmen.

**Schritt 2 (nach Schritt 1):** sichtbare Namen: Bot-Name „OMEN Bot“, Mail-Texte und Absender,
Discord-Befehl `/omen`, Seitentitel, Embeds.
Bot- und Chat-Links weiter als `https://butzebot.com/tethra/…` senden, bis wir `min_version` auf die erste
Version heben, die `/omen/`-Links kennt (alle ab v1.37.0 kennen beide). Die alten `/tethra/…`-Pfade nicht
abschalten, später per 301 auf `/omen/…`.

Paket fürs Relay: `OMEN.pck` (am Release hängt zusätzlich eine gleiche `TETHRA.pck`).
GitHub: `Vyrenbusiness-source/OMEN`. Modus-Icons:
`https://raw.githubusercontent.com/Vyrenbusiness-source/OMEN/main/assets_game/icons/modes/<mode>.svg`
(`mania, orbit, rally, dirigent, trace, rebound`).

---

## 2. `POST /score`: Modi und Felder

| `mode` | Was | Wertung / Rangliste |
|---|---|---|
| `mania` | osu!mania 4K | ScoreV1, max 1.000.000 × Mod-Faktor, pp (rosu) |
| `mania5k` `mania6k` `mania7k` | Mania mit 5–7 Tasten, dazu `"keys": 5..7` | wie Mania, pp mit echter Spaltenzahl; **eigene Rangliste je Tastenzahl**; kein 4K-Check |
| `orbit` | Orbit (Regeln v5) | keine pp; Punkte = 4 × Sterne² × Acc⁴, gewichtet 0,95^Platz |
| `rally` | Rally (Regeln v4) | wie Orbit |
| `dirigent` | Dirigent (Regeln v4), dazu `beats_hit`, `beats_total` | wie Orbit |
| `trace` | Trace (eigene Sterne) | wie Orbit |
| `rebound` | Rebound (Regeln v3) | wie Orbit |

Pflichtfelder wie bisher (`beatmap_md5`, `beatmap_id`, `beatmapset_id`, `difficulty`, `score`, `mods`,
`mod_mult`, `accuracy`, `grade`, `max_combo`, `count_*`, `stars`, `client_version`), optional
`replay_content` (Base64 gzip-JSON, ≤ 2 MB).

**Mods** (Feld `mods`) und Faktoren:
- `SV` ×1,1 (nur Mania), `NF` ×0,5, Orbit `HD` `FI` ×1,06, `PR` ×1,12, Trace `MR` ×1,0 `HD` ×1,06 `SS` ×1,08.
- `SD` (Sudden Death), `PF` (Perfect): Mania/Trace/Rebound, Faktor 1,0, normal ranked.
- `MN` (Minen, Mania): kommt mit `"board": "mania_mn"`, `"ranked": false`, `"pp": 0`, `"mines"`, `"mine_hits"`.
  **Eigene Rangliste** `board=mania_mn`, nicht in die normale Mania-Liste.

**Nie gesendet:** Auto-Maps aus eigener Musik (Creator „OMEN Auto“), Übungsmodus.
**Vorerst nur lokal** (Vorschlag für später, generisch nach Abschnitt 0.3):
`mania_turbo` (sortiert nach `peak`, dann `score`), `mania_marathon` (`length` n3…m20,
`maps[{osz, version, stars}]`, `score`, `accuracy`, `max_combo`, `n_miss`, `failed`), beide ohne pp.

**Kampagne** (optional): `"campaign": "v1/<stufe>"` (z. B. `v1/mania-c04s4`) und bei der Skip-Prüfung
`"campaign_trial": "mania-c01"`. Gesamtrangliste nur aus echten Sterne-Stufen. Details:
`docs/net/campaign_server.md`.

Gültige Scores nur ab `client_version` ≥ `min_version` (1.30.0).

---

## 3. Lese-Endpunkte

- `GET /leaderboard?mode=<mode>&md5=<md5>[&board=mania_mn]` – je Spieler Bestwert. Bei `board` die Antwort mit
  `"board":"mania_mn"` zurückgeben (sonst zeigt der Client „folgt“).
- `/players`, `/top-plays`, `/recent-plays`, `/game/rankings` mit `?mode=` für alle Modi oben.
- Wunsch: `GET /scores?mode=&md5=&player=&limit=20` – alle Läufe eines Spielers auf einer Map (für pp alter
  Mitspieler-Läufe).
- Wunsch: `GET /campaign/leaderboard?version=v1&mode=mania&limit=50&offset=0`,
  optional `GET /campaign/progress?version=v1` (mit Token).
- Replays: `GET /panel-api/<name>/score/:id/replay` (404 ohne Replay).

---

## 4. Relay und Räume

- Relay: `OMEN.exe --headless --mp-relay --port 47900`, pm2-Name z. B. `omen-relay`.
- `GET /rooms`: Code, Name, Spieler, Map, Modus, Raumart (frei/Teams/Battle Royale/Turnier), Version,
  Raum-Mods (`NF`, `SV`, `SD`, `PF`, `MN`).
- Cloudflare-Ingress: `/tethra/mp` und `/tethra/rooms` (zusätzlich `/omen/mp`, `/omen/rooms`) auf 47900.

---

## 5. Chat-Bot

- Map-Links: `https://butzebot.com/tethra/map/<md5>?set=<beatmapset_id>&b=<beatmap_id>&t=<Titel>&a=<Künstler>&v=<Diff>&s=<Sterne>`
  (`set` Pflicht, URL-kodiert, `s` mit Punkt). Ein Map-Link je Zeile, Info darunter, höchstens 3 Maps.
- Keine leeren Zeilen, Emoji sparsam (Client entfernt sie).
