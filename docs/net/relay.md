# Online-Multiplayer ueber den Relay

Spieler in verschiedenen Netzen brauchen weder UPnP noch Portfreigabe: alle
verbinden sich per WebSocket (TCP) mit dem Relay `wss://butzebot.com/tethra/mp`.
Die Lobby-Logik (`scripts/net/lobby.gd`, Host = Peer 1, RPCs) ist unveraendert,
nur der Transport wechselt: `scripts/net/relay_peer.gd` ist ein
`MultiplayerPeerExtension`, `scripts/net/relay_server.gd` der Server.
LAN / Direkt (ENet + UPnP) bleibt als Option in der Lobby.

## Protokoll

Ein Port, drei Arten von Verkehr:

- **WebSocket** auf jedem Pfad (Spiel). Textframes = JSON-Steuerung, Binaerframes = Spieldaten.
- **HTTP `GET /rooms`** (auch `/tethra/rooms`): JSON-Liste, CORS offen, fuer die Website.
- `GET /health` -> `ok`.

Binaerframe Client -> Relay: `[i32 to LE][u8 mode][u8 channel][payload]`.
Relay -> Client: gleiches Layout, `to` ist dann der Absender (`from`).
Beitretende senden immer nur an den Host (wie ENet). Der Host adressiert
`0` = alle, `>0` = ein Peer, `<0` = alle ausser `-to`.

Steuerung (JSON, Feld `t`):

| Richtung | Nachricht |
|---|---|
| Client -> Relay | `host` `{name, v, map, mode, locked}`, `join` `{code, v}`, `list`, `info` `{name, map, mode, locked}` (Host), `kick` `{id}` (Host), `ping` |
| Relay -> Client | `hosted` `{code, id:1}`, `joined` `{id, host:1}`, `peer+`/`peer-` `{id}` (nur an den Host), `closed`, `rooms` `{rooms}`, `err` `{code, msg, host_v}`, `pong` |

Fehlercodes: `notfound`, `version` (Beitritt nur bei gleicher
`Updater.CURRENT_VERSION` wie der Host, Meldung "Update noetig (Host vX)"),
`full`, `busy`, `rate`. Spieler-IDs: Host 1, Beitretende ab 2.

Raumliste (`GET /rooms`, `list`): `[{code, name, players, max, map, mode, version, locked}]`.
Gesperrte (Passwort-)Raeume erscheinen mit `code: ""`.

## Grenzen

- 6-stelliger Code (`23456789ABCDEFGHJKLMNPQRSTUVWXYZ`), max. 16 Spieler pro Raum, 300 Raeume, 800 Verbindungen.
- Frame max. 64 KiB (groesser = Verbindung getrennt), `RelayPeer` meldet 60000 Byte Paketgroesse.
- Rate-Limit pro Verbindung: 400 Nachrichten/s und 600 kB/s (Token-Bucket, doppelter Burst).
- Heartbeat: Clients senden alle 5 s `ping`; 20 s ohne Daten = Timeout.
- Host weg = Raum zu (alle Mitspieler bekommen `closed`).
- Passwoerter prueft weiter der Host (`srv_register`); der Relay kennt nur das Flag `locked`.

## Server starten (Linux)

```
./Godot_v4.7-stable_linux.x86_64 --headless --main-pack OMEN.pck --mp-relay --port 47900
```

Der Einstieg sitzt in `Lobby._ready` (Autoload); die Hauptszene wird dabei
entschaerft, damit der Prozess nicht endet. Immer die zur Spielversion passende
PCK nehmen: die Version des Relays ist unerheblich, geprueft wird Host gegen Beitretende.

PM2:

```
pm2 start ./Godot_v4.7-stable_linux.x86_64 --name tethra-relay -- \
  --headless --main-pack OMEN.pck --mp-relay --port 47900
pm2 save
```

Cloudflare-Tunnel (`config.yml`):

```
ingress:
  - hostname: butzebot.com
    path: /tethra/mp
    service: http://127.0.0.1:47900
  - hostname: butzebot.com
    path: /tethra/rooms
    service: http://127.0.0.1:47900
  - service: http_status:404
```

WebSockets laufen ueber den Tunnel ohne weitere Einstellung.

## Tests

- `godot --headless --path . -s tests/run_relay_tests.gd` — Protokoll in einem Prozess.
- `tools/mp_relay_smoke.sh` — echter Relay-Prozess + Host + Client ueber `ws://127.0.0.1`, mit Live-Score und Endergebnis.
- Lokal gegen einen eigenen Relay: `--relay-url=ws://127.0.0.1:47900/mp`.

## Beim Merge

`translations/mp_relay.csv` in `project.godot` (internationalization/locale/translations) eintragen.
