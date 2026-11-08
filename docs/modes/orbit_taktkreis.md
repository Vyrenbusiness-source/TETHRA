# Orbit "Taktkreis"

Neuentwurf der Orbit-Mechanik (Name bleibt Orbit). Grund: die alte Mechanik
(Ziele fliegen radial an, der Ring wird per Zeigen gewaehlt) liegt zu nah an
osu! und osu!tau. Der Taktkreis ist ein eigener Mix aus vier Teilen.

## Regeln

1. **Der Kreis ist ein Takt.** Ein Zeiger ("Hand") dreht im Songtempo, eine
   Umdrehung pro Takt. 12 Uhr = Takt-Eins. Die Taktart kommt aus dem roten
   Timing-Point (Beats pro Takt x Beat-Laenge); ein neuer roter Punkt beginnt
   einen neuen Takt. Takte unter `MIN_BAR_MS` = 1200 ms drehen mit zwei Takten
   pro Umdrehung (sonst waere die Hand zu schnell). Ohne Timing-Point: 120 BPM
   in 4/4. Tempo-, Taktart- und SV-Wechsel aendern nur die Drehgeschwindigkeit.
2. **Noten sitzen an ihrer Taktposition.** Winkel = Anteil des Takts x 360.
   Es gibt nichts zu verschieben: der Rhythmus liest sich wie eine Partitur.
   Das Raster zeigt Viertel (feine Striche) und Achtel (feiner).
3. **Vorschau.** Hinter der Hand sieht man die Noten des naechsten Takts
   (gedimmt, sie werden heller, je naeher die Hand kommt). Man liest immer
   einen Takt voraus. Sichtbar ist alles im Zeitfenster (t, t + Taktlaenge].
4. **Zwei Ringe, zwei Tasten.** Innerer Ring = Taste A, aeusserer Ring = Taste B
   (Standard Maus links/rechts und Z/X, umbelegbar in den Settings, Zeile
   "Orbit-Tasten": innen | aussen). Akzent = beide Ringe am selben Winkel =
   beide Tasten gleichzeitig. Die Tasten entscheiden den Ring, nicht der
   Cursor-Abstand (nur die Totzone in der Mitte, `DEAD_K`, zaehlt nie).
5. **Zielen ist Pflicht.** Beim Druck muss der Cursor (Maus/Tablet absolut) auf
   der Hand liegen: Winkel-Abstand zum Zeiger hoechstens `ANGLE_TOL_DEG` = 30
   Grad, Radius egal. Daneben = kein Treffer, Fehl-Feedback "neben dem Zeiger"
   (Grund `ANGLE`). Zwischen den Noten folgt man der Hand: kreisende Bewegung im
   Takt. Das ist die Tablet-Fertigkeit.
6. **Boegen (Halten).** Taste halten und den Cursor auf der Hand halten, solange
   die Hand durch den Bogen laeuft. Mehr als `ARC_OUT_MS` = 150 ms am Stueck
   neben der Hand oder zu frueh loslassen = DROP.
7. **Wertung unveraendert** (siehe `orbit.md`): Zeitfenster aus OD, Stufen
   CORE/SHARP/GOOD/FAIR/EDGE/MISS mit 1,00/0,94/0,68/0,40/0,16/0, Zielfaktor 1,0
   bis 9 Grad, 0,88 am Rand. Der "Zielfehler" ist jetzt der Winkel zwischen
   Cursor und Hand beim Druck. Score-Formel und Grades bleiben, damit die
   Server-Regeln gelten.

## Umwandlung

- **osu!standard**: Ring nach osu!taiko-Regel. Whistle (2) oder Clap (8) =
  aussen (Ka), sonst innen (Don). Finish (4) = Akzent (beide Ringe).
  Slider und Spinner (>= `MIN_ARC_MS`) werden Halte, laenger als `MAX_HOLD_MS`
  wird gekappt. Positionen spielen keine Rolle mehr.
- **osu!mania 4K**: Spalten 1-2 innen, 3-4 aussen; Akkord ueber beide Seiten =
  Akzent; LN = Halte. Andere Spaltenzahlen: linke Haelfte innen, rechte aussen,
  mittlere Spalte innen.
- **Dichte**: je Ring `SAME_RING_MIN_MS` = 90 ms zwischen zwei Tasten (nach
  einem Halte `RELEASE_GAP_MS`); waehrend ein Halte den Ring haelt, kommt dort
  nichts. Unter `EASY_STARS` gelten die groeberen Grenzen `EASY_RING_GAP_MS`
  (Ring) und `EASY_GAP_MS` (insgesamt), sonst waeren leichte Diffs zu dicht.
- Zeit exakt: jedes Ziel liegt auf der Zeit seiner Quell-Note.

## Orbit-Sterne

Skala 0 bis 15 wie bisher. Je 2-Sekunden-Fenster: Dichte (Ziele/s, Akkord
zaehlt halb), Ringwechsel (Taste A/B abwechseln, Kosten wie Tastengriff),
Akzente und Halte, dazu das Drehtempo der Hand (Folge-Anspruch: 360 Grad / Takt
gegenueber `HAND_REF_DEG_PER_MS`). Die haertesten Fenster zaehlen am meisten
(`STAR_DECAY`). Kalibriert gegen Bot-Messungen, siehe Messwerte unten.

## Abgrenzung

- **Twin Edge**: zwei Kreise, ein Klick. Hier ein Kreis, zwei Ringe = zwei
  Tasten, und das Zielen auf die Hand ist Pflicht.
- **Chrono Circle** (Arcade): drehender Zeiger, Noten auf dem Kreis. Dort
  keine Taktbindung, kein Vorschau-Takt, kein Zielzwang.
- **osu!tau**: Noten fliegen radial an, Schlaeger dreht. Hier kommt nichts
  angeflogen; die Noten stehen fest, die Hand laeuft.
- **Lanota / Cytus**: Scanlinie bzw. Ring mit freier Notenbewegung; hier
  gilt ein festes Taktraster.

## Look (neu, ruhig, lesbar wie osu!)

Wenige Elemente: dunkle Platte, zwei duenne Ringe, Raster nur als feine Striche,
die Hand als einzige helle Linie (weiss, Spitze am Aussenring), dazu eine sehr
schwache Zielzone (+-30 Grad) hinter der Hand. Innen = kuehle Scheibe, aussen =
warmes Quadrat (Form **und** Farbe). Die naechste Note je Ring ist am groessten
und hat einen hellen Rand; spaetere Noten des Takts etwas kleiner; Vorschau
(naechster Takt) deutlich blasser. Kein Leuchten, keine Partikel, keine Bewegung
ausser Hand und Cursor. Wertung als kurze kleine Marke an der Note und eine
Zeile unten.

## Risiken

- Schnelle Taktarten (3/4 bei 200 BPM = 0,4 Grad/ms): Folgen wird Ausdauer.
  Gegenmittel: `MIN_BAR_MS`, Sterne, Bot-QA (`run_orbit_qa_tests.gd`).
- Hohe Dichte auf einem Ring mit eng liegenden Noten (zwei Noten 90 ms
  auseinander = 5 bis 15 Grad): die Marken ueberlappen; die Ansicht staucht
  die Groesse (`FIT`), die Wertung bleibt zeitbasiert.
- Alte Orbit-Replays (Format 1/2) haben andere Regeln: Meldung "aeltere
  Version" (`REPLAY_RULES` = 3).
- Tutorial (`orbit_tutorial.gd`) erklaert noch die alte Mechanik, siehe
  Abschlussbericht.

## Was Orbit Spass macht (und woran wir es messen)

osu! macht Spass durch klares, knackiges Feedback und enge Eingabe. Hier:

1. **Knackiges Feedback**: jeder Treffer gibt sofort einen Klang je Ring
   (innen und aussen klingen verschieden, Tonhoehe nach Stufe), eine kurze
   Marke an der Note und die Stufe in der Mitte. Kein Nachleuchten.
2. **Enge Eingabe**: Zeitfenster wie Mania (OD), der Druck zaehlt zur
   Tastenzeit, nicht zur Framezeit; die Austrittszeit der Halte wird exakt
   gerechnet. Die Hand-Toleranz (30 Grad) ist grosszuegig genug, dass ein
   Mensch mit 60 ms Nachlauf bei jedem Tempo trifft, das Zielen aber noch
   zaehlt (Zielfaktor 1,0 bis 9 Grad).
3. **Musikalische Muster**: Noten liegen auf dem Taktraster, sichtbar wie eine
   Partitur; der naechste Takt ist als Vorschau da, man liest voraus.
4. **Hand folgen als Groove**: konstante Drehung, nie schneller als
   300 Grad/s; die Bewegung zwischen den Noten ist ein ruhiges Kreisen im
   Takt, kein Springen.
5. **Leichte Maps zuerst**: unter 2,5 Sternen groebere Mindestabstaende,
   Hand bei 120 BPM 4/4 nur 180 Grad/s.

## Messwerte

**Handtempo** (Grad/s), `run_orbit_qa_tests.gd`:

| Taktart | 80 BPM | 120 BPM | 140 BPM | 170 BPM | 200 BPM | 240 BPM |
|---|---|---|---|---|---|---|
| 3/4 | 160 | 240 | 280 | 170 | 200 | 240 |
| 4/4 | 120 | 180 | 210 | 255 | 300 | 180 |
| 6/4 | 80 | 120 | 140 | 170 | 200 | 240 |
| 7/4 | 69 | 103 | 120 | 146 | 171 | 206 |

Hoechstwert 300 Grad/s (0,8 U/s), durch `MIN_BAR_MS` garantiert. Erlaubter
Nachlauf des Cursors hinter der Hand (Toleranz minus 2 sigma Zielstreuung):
120 ms bei 0,15 Grad/ms, 100 ms bei 0,18, 75 ms bei 0,24, 60 ms bei 0,30.

**Bots** (Nachlauf tau / Zeitstreuung / Zielstreuung): Tablet 35 ms / 20 ms /
4 Grad, Maus 60 / 25 / 6, schwach 90 / 32 / 8. Neun Maps von 1,2 bis 11,1
Sternen:

- Tablet: Acc 93 bis 96 %, Rang A/S, 0 bis 10 Misses auf jeder Map.
- Maus: Acc 88 bis 92 %, Rang A/B, 0 bis 10 Misses (bei 22 Grad Toleranz waren
  es 77 bis 82 % und bis 143 Misses: deshalb 30 Grad).
- Schwach: Acc 85 % (B) auf den ersten beiden Maps (Hand 0,165 Grad/ms),
  65 bis 77 % bei Hand ab 0,24 Grad/ms. Fehlerquote 2,6 % bei langsamer, 9,2 %
  bei schneller Hand: das Folgen ist die Huerde, nicht die Dichte.

**Regelmaessigkeit**: 95 % der Ziele liegen auf dem Sechzehntel-Raster (68 bis
100 % je Map), im Mittel 10 % der Takte wiederholen den Rhythmus eines der
letzten 4 Takte.

**Bibliothek** (964 Diffs, 794.089 Ziele): 0 Verstoesse (Zeit, Ring, Winkel,
Akkord), Sterne p10 2,15 / Median 4,35 / p90 7,86 / Max 13,76.

## Tutorial: was es erklaeren muss

(`scripts/orbit/orbit_tutorial.gd`, gehoert Task orbit-tutorial2)
Kreis = ein Takt und die Hand; Tasten = Ringe (innen A, aussen B); Zielen auf
die Hand ist Pflicht; Akzent = beide Tasten; Halte = Taste und Cursor auf der
Hand halten; Vorschau des naechsten Takts. Es nutzte `OrbitCore.ring_for_rho`
und Noten ohne Handtempo (`OrbitNote.speed`).
