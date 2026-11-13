# TETHRA Bot: Nachrichten und Map-Links im Ingame-Chat

Stand: Client ab dem Chat-Markdown-Fix (`scripts/net/chat_api.gd`, `parse_content`).

## Was der Client heute versteht

Der Chat zeigt Bot-Nachrichten formatiert an:

- `**fett**`, `*kursiv*`, `# Titel`, `- Liste`, `` `code` `` (nur die Zeichen fallen weg).
- `[Text](Link)` und nackte `https://`-Links sind klickbar. Relative Pfade (`/tethra/...`)
  werden mit `https://butzebot.com` geöffnet. Andere Schemata öffnet der Client nicht.
- Emoji werden entfernt (die Spielschrift hat keine Emoji-Glyphen). `⭐` wird zu `★`.
  Zeilen, die nur aus Emoji bestehen, verschwinden ganz.
- Eine Zeile `Filters:` ohne Inhalt wird nicht angezeigt.

Jeder Map-Link mit `set=<Beatmapset-ID>` wird eine Map-Karte (Cover, Titel, Diff,
Vorhören, Herunterladen/Spielen), höchstens 3 Karten je Nachricht. Erkannte Formen,
relativ oder mit `https://butzebot.com` davor, nackt oder als Markdown-Link:

| Form | Quelle |
| --- | --- |
| `/tethra/map/<md5>?set=<id>&b=<beatmap_id>&t=<Titel>&a=<Künstler>&v=<Diff>&s=<Sterne>` | Spieler ("Map teilen") |
| `/tethra/songs?detail=<slug>&difficulty=<slug>&set=<id>` | Bot |
| `/omen/songs?detail=<slug>&difficulty=<slug>&set=<id>` | alte Bot-Nachrichten |

Bei den `songs`-Links rät der Client: Titel und Künstler aus dem Linktext
(`Titel by Künstler`), Diff-Name und Sterne aus der Folgezeile
(`**[4K] Hyper** — 3.39★ | ...`), die Diff beim Spielen über den Slug aus `difficulty=`.
Das klappt, ist aber brüchig: Ändert sich der Text, fehlen der Karte Angaben.
Ohne `set=` gibt es keine Karte.

## Bitte am Bot ändern

1. **Ein Linkformat für Maps**, dasselbe wie bei Spieler-Links:

   ```
   https://butzebot.com/tethra/map/<md5>?set=<beatmapset_id>&b=<beatmap_id>&t=<Titel>&a=<Künstler>&v=<Diff-Name>&s=<Sterne>
   ```

   - `<md5>`: MD5 der `.osu`-Datei der gemeinten Diff. Damit findet der Client die
     Map auch dann lokal, wenn sie nicht über die Set-ID importiert wurde.
   - `set` ist Pflicht (Cover, Vorhören, Download laufen über die Set-ID).
   - `b`, `t` sind erwünscht; `a`, `v`, `s` optional. Alle Werte URL-kodiert
     (`End%20Time`), `s` mit Punkt (`3.39`).
   - `v` ist der echte Diff-Name (`[4K] Hyper`), kein Slug.
   - Volle Adresse mit `https://butzebot.com`, nicht relativ: so ist der Link auch
     außerhalb des Spiels (Discord, Browser) klickbar.
   - Beispiel:
     `https://butzebot.com/tethra/map/0123456789abcdef0123456789abcdef?set=1766740&b=3620000&t=End%20Time&a=Cres&v=%5B4K%5D%20Hyper&s=3.39`

2. **Kein `/omen/...` mehr.** Neue Nachrichten nur mit `/tethra/...`. Alte Nachrichten
   müssen nicht umgeschrieben werden, der Client liest sie weiter.

3. **Keine leeren Zeilen mit Etikett.** `Filters:` nur senden, wenn Filter gesetzt
   sind (`Filters: 4K, Rice`). Dasselbe gilt für jede andere Zeile "Name:" ohne Wert.

4. **Emoji sparsam.** Der Client entfernt sie. Eine Zeile darf nicht nur durch ein
   Emoji verständlich sein (z. B. `🎯 97%`: besser `Acc 97%`).

5. **Ein Map-Link je Zeile**, die Info-Zeile direkt darunter. Mehr als 3 Maps je
   Nachricht zeigt der Client nicht als Karte.

Reihenfolge ohne Bruch: Der Client versteht Punkt 1 schon heute. Der Bot kann also
sofort umstellen, alte Clients zeigen den neuen Link als Karte wie einen Spieler-Link.
