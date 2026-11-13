# Gameplay-Abstimmung Orbit, Rally, Dirigent, Rebound (2026-11-13)

Ziel: leichte Maps fuer Einsteiger schaffbar, schwere fordernd aber fair, Schwierigkeit steigt
mit den Sternen. Gemessen statt geraten: Bots mit menschlichen Grenzen auf der Kartenbibliothek.

## Messung

- Stichprobe: jede 4. .osz der Bibliothek, alle Schwierigkeiten ab 30 Objekten (osu!standard und
  Mania 4K): 245 Diffs je Modus (Rebound nur Mania 4K: 237).
- Baender nach den Sternen des Modus: leicht < 2,5, mittel 2,5-5, schwer 5-8, extrem ab 8.
  Rebound hat keine eigenen Sterne; dort gruppieren die Rally-Sterne (4 Zonen) derselben Map.
- Drei Spieler-Modelle. Jeder Druck hat einen Zeitfehler (Normalverteilung, bei 2,5 Sigma
  gekappt). Jede Taste ist ein Finger: der naechste Druck derselben Taste kommt fruehestens
  nach der Finger-Grenze, sonst spaeter (und wird so gewertet). Orbit und Dirigent tippen mit
  einer Hand: zwischen zwei Druecken liegt mindestens die Hand-Grenze. Orbit: Cursor mit
  festem Tempo von Ziel zu Ziel. Dirigent: Zielfehler der Hand je Schlag.

| Modell | Zeitfehler Sigma | Finger-Grenze | Hand-Grenze | Akkord-Streuung | Orbit-Cursor | Dirigent-Zielfehler |
|---|---|---|---|---|---|---|
| Einsteiger | 25 ms | 170 ms | 110 ms | 16 ms | 2,0 Feld/s | 0,08 |
| Geuebt | 18 ms | 125 ms | 80 ms | 10 ms | 2,5 Feld/s | 0,06 |
| Profi | 12 ms | 95 ms | 55 ms | 6 ms | 3,5 Feld/s | 0,04 |

- Rally, Dirigent und Rebound laufen durch den echten Core (mit Anti-Mash, Rebound durch die
  Schicht vor ManiaCore). Rally: 3 Zonen (Standard), Flugzeit 800 ms. Orbit ist gerechnet wie in
  `tests/run_orbit_qa_tests.gd` (Fenster aus `OrbitCore.tier_windows`, HP wie im Core).
- Spalten: Acc Mittel (schlechteste Map) / Miss-Anteil / Anteil gescheiterter Laeufe (HP leer).
  Jack-Anteil = Druecke, deren Taste weniger als 125 ms vorher schon dran war.
- Grenze des Modells: es misst, ob Finger und Hand die Folge schaffen und ob ein Fehler fair
  bestraft wird. Lesen (viele Baelle zugleich, Muster) misst es nicht; dafuer stehen die Sterne.

## Befunde (vorher)

1. **Schnelle Folgen auf einer Taste.** Orbit (osu!standard: Taste aus dem Klang, ein Strom
   mit einem Klang lag ganz auf A), Dirigent (zwei Tasten tragen die ganze Map) und Rally mit
   3 Zonen (Spalte 2 und 3 der Map liegen beide in der Mitte) verlangten Folgen unter 125 ms auf
   einem Finger. Jack-Anteil im Band schwer: Orbit 33,9 %, Dirigent 53,9 %, Rally 11,7 %
   (Rebound, die Map wie gesetzt: 5,1 %). Folge: Geuebt faellt im Band schwer auf 75 % (Orbit),
   71 % (Dirigent), 79 % (Rally), waehrend Rebound bei 98,8 % bleibt. Das ist kein Koennen,
   das ist nicht greifbar.
2. **Ein Fehler reisst die Map mit.** Kommt ein Druck zu spaet (Ball schon Miss), zaehlte er
   als falsche Taste und machte den naechsten Ball einer anderen Zone zum Miss; dessen Druck
   kam dann wieder ohne Ball und so weiter. Rally: Maps unter 5 Sternen mit 9 % (Einsteiger)
   und 47 % (Geuebt) Acc, im Band extrem 100 % gescheitert. Dasselbe in Rebound und Dirigent,
   dort schwaecher. In Rally frass der spaete Druck dazu den naechsten Ball derselben Zone, und
   eine zu spaete zweite Schmetterball-Taste traf einen fremden Ball.
3. **Dirigent-Akzente im Strom.** Beide Tasten zugleich mit einem Nachbarn naeher als 180 ms
   sind mit zwei Fingern nicht spielbar.
4. HP, Zeitfenster, Vorlauf und Cursor-Wege waren unauffaellig: leichte Baender ohne Scheitern,
   Orbit-Wege schon in `docs/modes/orbit_satellit_qa.md` gemessen. Daran ist nichts geaendert.

## Aenderungen

| Modus | Regel neu | Replay-Regeln |
|---|---|---|
| Orbit | Wechselschlag: Ziel weniger als 180 ms nach dem Ende des vorigen nimmt die andere Taste (auch Halten, auch Mania gleiche Spalte). Akzent mit Nachbar naeher als 180 ms wird einfaches Ziel. Zeiten, Orte, Zahl der Ziele bleiben. | 4 -> 5 |
| Rally | Keine Zone zweimal in weniger als 130 ms: der Ball weicht in die naechste freie Zone aus, Schmetterball mit belegter Zone wird normaler Ball, ohne freie Zone entfaellt er (Stichprobe: 0 von 174030 Baellen entfallen). Nachzuegler: ein Druck im Miss-Fenster um einen verpassten Ball seiner Zone (oder die spaete zweite Schmetterball-Taste) ist frei: keine falsche Taste, frisst den naechsten Ball nicht. | 3 -> 4 |
| Dirigent | Wechselschlag wie Orbit (180 ms); Akzent mit Nachbar naeher als 180 ms wird einfacher Einsatz. Nachzuegler: nach einem verfehlten Einsatz ist ein Druck seiner Taste bis 50er-Fenster + 37 ms frei (einmal). Sterne zaehlen Wechselschlag zusaetzlich (+0,5 je Einsatz unter 180 ms). | 2 -> 3 |
| Rebound | Nachzuegler: war die vorige Note der Spalte ein Miss und liegt der Druck im Miss-Fenster um ihre Zeit, trifft er keine andere Spalte. ManiaCore unveraendert. | 2 -> 3 |

Alte Replays werden in allen vier Modi mit Hinweis abgelehnt. Server: `min_version` fuer Orbit,
Rally, Dirigent und Rebound auf die Client-Version setzen, die diese Regeln ausliefert.

## Messwerte vorher / nachher

### Orbit

Vorher:

| Band | Maps | Einsteiger Acc / Miss / Fail | Geuebt Acc / Miss / Fail | Profi Acc / Miss / Fail | Jack-Anteil (<125 ms) | Spitze Noten/s | Noten behalten | laengste Luecke s |
|---|---|---|---|---|---|---|---|---|
| leicht (0.0-2.5) | 55 | 94.3 % (min 86.1) / 0.1 % / 0 % | 97.7 % (min 96.2) / 0.0 % / 0 % | 99.4 % (min 99.0) / 0.0 % / 0 % | 0.5 % | 5.6 | 68 % | 11.0 |
| mittel (2.5-5.0) | 76 | 83.3 % (min 37.5) / 5.8 % / 21 % | 96.0 % (min 88.3) / 0.1 % / 0 % | 99.1 % (min 98.1) / 0.0 % / 0 % | 4.5 % | 10.6 | 56 % | 7.3 |
| schwer (5.0-8.0) | 94 | 25.4 % (min 0.1) / 67.5 % / 97 % | 75.2 % (min 6.9) / 12.0 % / 34 % | 98.4 % (min 95.1) / 0.1 % / 0 % | 33.9 % | 14.9 | 44 % | 14.0 |
| extrem (8.0-15.0) | 20 | 14.0 % (min 0.1) / 81.9 % / 100 % | 53.3 % (min 0.6) / 36.3 % / 60 % | 91.2 % (min 5.3) / 5.4 % / 15 % | 30.1 % | 16.1 | 57 % | 14.1 |

Nachher:

| Band | Maps | Einsteiger Acc / Miss / Fail | Geuebt Acc / Miss / Fail | Profi Acc / Miss / Fail | Jack-Anteil (<125 ms) | Spitze Noten/s | Noten behalten | laengste Luecke s |
|---|---|---|---|---|---|---|---|---|
| leicht (0.0-2.5) | 55 | 94.7 % (min 91.6) / 0.0 % / 0 % | 97.8 % (min 96.0) / 0.0 % / 0 % | 99.4 % (min 99.0) / 0.0 % / 0 % | 0.0 % | 5.4 | 68 % | 11.0 |
| mittel (2.5-5.0) | 73 | 91.9 % (min 82.1) / 0.3 % / 0 % | 96.8 % (min 94.5) / 0.0 % / 0 % | 99.2 % (min 98.1) / 0.0 % / 0 % | 0.0 % | 8.6 | 57 % | 7.3 |
| schwer (5.0-8.0) | 98 | 73.5 % (min 6.9) / 9.0 % / 55 % | 95.4 % (min 89.0) / 0.2 % / 0 % | 98.6 % (min 94.4) / 0.1 % / 0 % | 0.0 % | 9.8 | 44 % | 14.1 |
| extrem (8.0-15.0) | 19 | 35.7 % (min 0.8) / 53.4 % / 100 % | 87.1 % (min 52.0) / 5.4 % / 16 % | 97.7 % (min 84.3) / 0.5 % / 5 % | 0.0 % | 10.9 | 59 % | 9.8 |

Sterne (Stichprobe): vorher p10 1.65 / p25 2.75 / Median 4.62 / p75 6.66 / p90 7.78 / max 15.00; nachher p10 1.65 / p25 2.71 / Median 4.62 / p75 6.76 / p90 7.78 / max 15.00.

### Rally

Vorher:

| Band | Maps | Einsteiger Acc / Miss / Fail | Geuebt Acc / Miss / Fail | Profi Acc / Miss / Fail | Jack-Anteil (<125 ms) | Spitze Noten/s | Noten behalten | laengste Luecke s |
|---|---|---|---|---|---|---|---|---|
| leicht (0.0-2.5) | 72 | 96.3 % (min 86.0) / 0.3 % / 0 % | 99.6 % (min 94.7) / 0.1 % / 0 % | 100.0 % (min 100.0) / 0.0 % / 0 % | 1.3 % | 7.1 | 68 % | 11.0 |
| mittel (2.5-5.0) | 81 | 85.5 % (min 9.3) / 6.8 % / 7 % | 98.3 % (min 47.4) / 0.8 % / 1 % | 100.0 % (min 99.5) / 0.0 % / 0 % | 2.4 % | 12.2 | 54 % | 6.4 |
| schwer (5.0-8.0) | 52 | 35.9 % (min 2.2) / 57.8 % / 88 % | 78.8 % (min 1.8) / 19.1 % / 35 % | 98.0 % (min 29.8) / 2.0 % / 4 % | 11.7 % | 15.3 | 49 % | 7.3 |
| extrem (8.0-15.0) | 40 | 4.9 % (min 0.5) / 93.4 % / 100 % | 7.3 % (min 0.3) / 91.5 % / 100 % | 69.9 % (min 2.3) / 29.7 % / 50 % | 47.8 % | 20.3 | 39 % | 14.0 |

Nachher:

| Band | Maps | Einsteiger Acc / Miss / Fail | Geuebt Acc / Miss / Fail | Profi Acc / Miss / Fail | Jack-Anteil (<125 ms) | Spitze Noten/s | Noten behalten | laengste Luecke s |
|---|---|---|---|---|---|---|---|---|
| leicht (0.0-2.5) | 73 | 97.1 % (min 90.4) / 0.0 % / 0 % | 99.7 % (min 98.7) / 0.0 % / 0 % | 100.0 % (min 100.0) / 0.0 % / 0 % | 0.0 % | 7.0 | 68 % | 11.0 |
| mittel (2.5-5.0) | 82 | 93.0 % (min 76.1) / 0.3 % / 0 % | 99.4 % (min 98.3) / 0.0 % / 0 % | 100.0 % (min 100.0) / 0.0 % / 0 % | 0.0 % | 11.9 | 54 % | 6.4 |
| schwer (5.0-8.0) | 63 | 91.8 % (min 67.9) / 0.4 % / 0 % | 99.1 % (min 96.6) / 0.0 % / 0 % | 100.0 % (min 100.0) / 0.0 % / 0 % | 0.0 % | 13.6 | 47 % | 13.7 |
| extrem (8.0-15.0) | 27 | 96.2 % (min 94.6) / 0.0 % / 0 % | 99.1 % (min 98.0) / 0.0 % / 0 % | 100.0 % (min 100.0) / 0.0 % / 0 % | 0.0 % | 15.5 | 38 % | 14.0 |

Sterne 3 Zonen (Stichprobe): vorher p10 1.02 / p25 2.16 / Median 4.17 / p75 6.12 / p90 10.36 / max 12.31; nachher p10 1.02 / p25 2.16 / Median 4.17 / p75 6.06 / p90 8.08 / max 9.51. Die Spitze sinkt, weil die unspielbaren Mitte-Folgen weg sind.

### Dirigent

Vorher:

| Band | Maps | Einsteiger Acc / Miss / Fail | Geuebt Acc / Miss / Fail | Profi Acc / Miss / Fail | Jack-Anteil (<125 ms) | Spitze Noten/s | Noten behalten | laengste Luecke s |
|---|---|---|---|---|---|---|---|---|
| leicht (0.0-2.5) | 101 | 94.5 % (min 68.2) / 0.3 % / 0 % | 99.4 % (min 98.3) / 0.0 % / 0 % | 100.0 % (min 99.9) / 0.0 % / 0 % | 1.5 % | 8.7 | 78 % | 11.0 |
| mittel (2.5-5.0) | 92 | 75.2 % (min 46.6) / 6.7 % / 0 % | 97.6 % (min 87.8) / 0.1 % / 0 % | 100.0 % (min 99.9) / 0.0 % / 0 % | 10.4 % | 14.2 | 56 % | 6.4 |
| schwer (5.0-8.0) | 33 | 44.2 % (min 22.5) / 28.6 % / 0 % | 71.4 % (min 44.0) / 7.2 % / 0 % | 100.0 % (min 99.8) / 0.0 % / 0 % | 53.9 % | 19.3 | 46 % | 13.7 |
| extrem (8.0-15.0) | 19 | 25.8 % (min 11.9) / 47.4 % / 0 % | 44.7 % (min 32.8) / 19.0 % / 0 % | 99.9 % (min 99.7) / 0.0 % / 0 % | 81.3 % | 20.7 | 34 % | 14.0 |

Nachher:

| Band | Maps | Einsteiger Acc / Miss / Fail | Geuebt Acc / Miss / Fail | Profi Acc / Miss / Fail | Jack-Anteil (<125 ms) | Spitze Noten/s | Noten behalten | laengste Luecke s |
|---|---|---|---|---|---|---|---|---|
| leicht (0.0-2.5) | 71 | 97.2 % (min 93.8) / 0.0 % / 0 % | 99.6 % (min 98.6) / 0.0 % / 0 % | 100.0 % (min 100.0) / 0.0 % / 0 % | 0.0 % | 6.8 | 80 % | 11.0 |
| mittel (2.5-5.0) | 96 | 96.2 % (min 85.1) / 0.1 % / 0 % | 99.3 % (min 98.4) / 0.0 % / 0 % | 100.0 % (min 99.9) / 0.0 % / 0 % | 0.0 % | 8.7 | 60 % | 6.4 |
| schwer (5.0-8.0) | 46 | 89.9 % (min 61.7) / 0.8 % / 0 % | 99.4 % (min 98.5) / 0.0 % / 0 % | 100.0 % (min 100.0) / 0.0 % / 0 % | 0.0 % | 9.8 | 53 % | 13.6 |
| extrem (8.0-15.0) | 32 | 65.8 % (min 59.0) / 7.4 % / 0 % | 99.4 % (min 98.7) / 0.0 % / 0 % | 100.0 % (min 100.0) / 0.0 % / 0 % | 0.0 % | 10.6 | 40 % | 14.0 |

Acc = Einsatz-Acc; Takt-Acc Geuebt in allen Baendern 99 % (vorher und nachher). Sterne (Stichprobe): vorher p10 0.92 / p25 1.64 / Median 2.93 / p75 4.52 / p90 7.50 / max 9.91; nachher p10 1.11 / p25 2.18 / Median 3.76 / p75 6.20 / p90 8.57 / max 10.98.

### Rebound

Vorher:

| Band | Maps | Einsteiger Acc / Miss / Fail | Geuebt Acc / Miss / Fail | Profi Acc / Miss / Fail | Jack-Anteil (<125 ms) | Spitze Noten/s | Noten behalten | laengste Luecke s |
|---|---|---|---|---|---|---|---|---|
| leicht (0.0-2.5) | 63 | 97.1 % (min 95.8) / 0.0 % / 0 % | 99.6 % (min 98.6) / 0.0 % / 0 % | 100.0 % (min 100.0) / 0.0 % / 0 % | 0.0 % | 7.9 | 100 % | 7.5 |
| mittel (2.5-5.0) | 76 | 95.6 % (min 80.6) / 0.2 % / 1 % | 99.3 % (min 97.8) / 0.0 % / 0 % | 100.0 % (min 100.0) / 0.0 % / 0 % | 0.6 % | 15.6 | 100 % | 6.4 |
| schwer (5.0-8.0) | 55 | 89.2 % (min 52.7) / 3.1 % / 31 % | 98.8 % (min 94.5) / 0.0 % / 0 % | 100.0 % (min 99.9) / 0.0 % / 0 % | 5.1 % | 21.4 | 100 % | 7.3 |
| extrem (8.0-15.0) | 43 | 59.2 % (min 41.4) / 19.0 % / 93 % | 80.5 % (min 58.9) / 5.6 % / 63 % | 100.0 % (min 99.8) / 0.0 % / 0 % | 45.4 % | 34.2 | 100 % | 14.0 |

Nachher:

| Band | Maps | Einsteiger Acc / Miss / Fail | Geuebt Acc / Miss / Fail | Profi Acc / Miss / Fail | Jack-Anteil (<125 ms) | Spitze Noten/s | Noten behalten | laengste Luecke s |
|---|---|---|---|---|---|---|---|---|
| leicht (0.0-2.5) | 63 | 97.1 % (min 95.8) / 0.0 % / 0 % | 99.6 % (min 98.6) / 0.0 % / 0 % | 100.0 % (min 100.0) / 0.0 % / 0 % | 0.0 % | 7.9 | 100 % | 7.5 |
| mittel (2.5-5.0) | 77 | 95.7 % (min 84.1) / 0.1 % / 0 % | 99.3 % (min 97.8) / 0.0 % / 0 % | 100.0 % (min 100.0) / 0.0 % / 0 % | 0.6 % | 15.7 | 100 % | 6.4 |
| schwer (5.0-8.0) | 61 | 89.2 % (min 60.7) / 1.8 % / 13 % | 98.7 % (min 94.5) / 0.0 % / 0 % | 100.0 % (min 99.9) / 0.0 % / 0 % | 6.9 % | 22.4 | 100 % | 7.3 |
| extrem (8.0-15.0) | 36 | 59.1 % (min 42.4) / 17.8 % / 83 % | 80.3 % (min 61.8) / 4.0 % / 39 % | 100.0 % (min 99.8) / 0.0 % / 0 % | 50.1 % | 35.0 | 100 % | 14.0 |

Baender nach Rally-Sternen (4 Zonen); die Grenzen verschieben sich mit den Rally-Regeln leicht.

## Ergebnis

- Leichte und mittlere Baender: kein Einsteiger-Lauf scheitert mehr (Orbit vorher 21 %, Rally 7 %
  im Band mittel). Schlechteste Map unter 5 Sternen, Geuebt: Rally 47 % -> 98 %, Orbit 88 % -> 94 %,
  Dirigent 88 % -> 98 %.
- Schwierigkeit steigt gleichmaessig: Orbit Geuebt 97,8 / 96,8 / 95,4 / 87,1 %, Einsteiger
  94,7 / 91,9 / 73,5 / 35,7 %; Dirigent Einsteiger 97,2 / 96,2 / 89,9 / 65,8 %.
- Rally bleibt fuer das Finger-Modell in allen Baendern greifbar (Einsteiger ab 91,8 %). Was dort
  schwer ist, ist Lesen und Tempo (bis 15 Baelle/s auf 3 Tasten), das misst das Modell nicht.
- Rebound: gleiche Acc, weniger Scheitern nach einem Fehler (schwer Einsteiger 31 % -> 13 %,
  extrem Geuebt 63 % -> 39 %).
- Anti-Mash bleibt wirksam (Spam-Bots in den Modus-Tests: Rally 0,8 %, Rebound 27,6 %,
  Orbit 50,0 %, Dirigent 66,7 % Acc).

Messskript: nicht im Repo (Bot-Modelle oben reichen zum Nachbauen); die Regeln selbst pruefen
`tests/run_orbit_tests.gd`, `run_rally_tests.gd`, `run_dirigent_tests.gd`, `run_rebound_tests.gd`.
