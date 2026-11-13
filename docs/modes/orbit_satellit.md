# Orbit: Satelliten (Neubau 2026-11-11)

Ersetzt "Bahnen" (Kreis/Acht/Bluete) und "Taktkreis". Gruende (Spieler): schlecht lesbar,
Formen verwirrend, nicht spuerbar im Takt, "schon gesehen". Name bleibt **Orbit**.

## Idee in einem Satz
Ziele erscheinen genau auf einem Schlag an einer Stelle im Feld; um jedes Ziel kreist ein
**Satellit eine Runde pro Beat** (bei schnellen Songs pro 2 bzw. 4 Beats). Kleine Punkte unter dem Ziel zaehlen die
Runden bis zum Treffer herunter (einer verschwindet pro Schlag). Trifft der Satellit in der
letzten Runde die Marke oben (12 Uhr): **zielen (Cursor auf das Ziel) und die richtige Taste
druecken**. Der Takt ist sichtbar und zaehlbar ("drei, zwei, eins, jetzt").

## Abgrenzung (bewusst)
- osu!: Annaeherungskreis schrumpft stufenlos, eine Taste egal welche. Orbit: Satellit zaehlt
  Beats (Runden), zwei Tasten mit Bedeutung (Farbe/Form), Akzente mit beiden Tasten.
- osu!tau, Twin Edge, Chrono Circle: drehender Zeiger auf einem festen Kreis. Orbit: kein
  Spielfeld-Kreis, freie Ziele im Feld, jeder Satellit gehoert zu seinem Ziel.
- Taiko: Don/Ka ohne Zielen. Orbit: Don/Ka-artige Tasten + Zielen.
- jubeat/maimai/Lanota/Cytus: feste Felder bzw. Scan-Linie/Kreisrand, kein Zielen mit Maus.

## Regeln (v5, 2026-11-13; v4 ab Client 1.28.0)
- **Wechselschlag (Regeln 5):** folgt ein Ziel in weniger als `FAST_KEY_MS` = 180 ms auf das
  Ende des vorigen, nimmt es die andere Taste (auch Halten; auch Mania gleiche Spalte). Ein
  Akzent mit einem Nachbarn naeher als 180 ms wird ein einfaches Ziel (A, im Strom die
  Wechseltaste). Zeiten, Orte und Zahl der Ziele bleiben (`OrbitConverter.playable_keys`, nach
  der Sichtbarkeits-Auswahl). Grund: osu!standard-Stroeme mit einem Klang lagen ganz auf einer
  Taste (ein Finger, bis 12 Druecke/s). Ab 180 ms gilt die Taste aus dem Klang wie bisher.
  Replays tragen `orbit_rules = 5`, aeltere werden abgelehnt. Messwerte: docs/modes/gameplay_tune.md.
- **Anti-Mash (Regeln 4):** Falsche Taste auf das offene Ziel (Cursor im Trefferradius,
  50er-Fenster, kein Ziel fuer diese Taste) = "WRONG KEY": Ziel sofort Miss. Akzent zaehlt nur
  mit beiden Tasten, ein A-/B-Ziel nur mit seiner Taste. Richtige Taste zuerst, falsche danach:
  Treffer bleibt. Druck ohne Ziel im Fenster oder Cursor daneben = nichts bzw. "daneben".
- **Feld**: 4:3, Koordinaten 0..1 x 0..1 (wie osu! 512x384 normiert), zentriert,
  Hoehe = 80 % der Bildschirmhoehe.
- **Ziel** (`OrbitNote`): `pos` (Feld), `key` 0 = A (kuehl, Scheibe), 1 = B (warm,
  abgerundetes Quadrat), 2 = Akzent (beide Tasten, Scheibe mit weissem Ring), Zeit `time_ms`.
- **Erscheinen**: auf dem Beat `spawn_ms` = letzter Beat-Tick <= `time_ms - laps * beat_ms`
  (Beat-Ticks aus den roten Timing-Points). `laps` = Runden (Standard 2, Einstellung
  "Vorlauf" 1-4 Runden). **Rundendauer (Regeln 4)**: Beat >= 450 ms: eine Runde = 1 Beat;
  Beat < 450 ms: 2 Beats; Beat < 225 ms: 4 Beats (`OrbitConverter.lap_ms_for`). Vorher
  (bis Regeln 3) erst unter 330 ms 2 Beats - bei schnellen Songs war der Satellit oben zu
  schnell. Der Vorlauf (Zeit sichtbar) bleibt wie vorher: die Runden-Einstellung zaehlt in
  Runden der alten Regel und wird je Ziel umgerechnet (`OrbitConverter.laps_eff`, mindestens
  1; z. B. Beat 400 ms, 2 Runden -> 1 Runde zu 2 Beats). Der Satellit wird langsamer, die
  Ziele bleiben nicht laenger stehen. Sterne lesen den Vorlauf in Runden der alten Regel
  (`read_laps`); Teilrunden zaehlen als schwer lesbar.
  Passt an dichten Stellen selbst eine Runde nicht (hoechstens 6 sichtbar), erscheint
  das Ziel auf einem spaeteren Beat mit einer Teilrunde (`laps = 0`, keine Pips); Vorlauf
  mindestens eine halbe Runde und ein Beat, und nie unter 450 ms (`MIN_LEAD_MS`): liegt der
  zugeteilte Tick naeher, erscheint das Ziel auf dem Beat-Tick davor. Die Zuteilung rechnet
  weiter mit dem zugeteilten Tick (`slot_ms`), dort sind dann kurz bis zu 8 Ziele da. Die
  Ansicht zeichnet 4 Raenge, ein Ziel dahinter ab 500 ms vor seiner Zeit (`READ_MS`).
  So faellt kein Ziel weg, das vor Regeln 4
  da war; neue kommen nicht hinzu.
- **Satellit**: Winkel `360 * frac((time_ms - t) / lap_ms)` gegen den Uhrzeigersinn
  gerechnet so, dass er bei `t = time_ms` exakt oben steht; gleichmaessige Geschwindigkeit
  ohne Spitze, ab `time_ms` bleibt er oben stehen (`OrbitNote.satellite_deg`). Punkte (Pips)
  unter dem Ziel = verbleibende ganze Runden.
- **Zeitfenster (Regeln 4, wie osu!standard)**: std300 = 80 - 6 x OD, std100 = 140 - 8 x OD,
  std50 = 200 - 10 x OD (ms, +-). CORE = std300 / 2, SHARP = std300, GOOD = std100,
  FAIR = (std100 + std50) / 2, EDGE = std50, ausserhalb Miss (`OrbitCore.tier_windows`).
  Beispiel OD 8: 16 / 32 / 76 / 98 / 120 ms. PR: alle Fenster x 0,7 (wie bisher). Vorher
  (bis Regeln 3): Mania-Fenster (MAX/300/200/100/50).
- **Treffer**: Taste gedrueckt im Zeitfenster **und** Cursor im Trefferradius (`AIM_RADIUS` = 1,15 x
  Zielradius) **und** richtige Taste. Akzent: beide Tasten innerhalb `ACCENT_MS` = 40 ms,
  gewertet beim zweiten Druck. Falsche Taste / daneben = kein Treffer (Feedback am Ort:
  "andere Taste", "daneben"); zu frueh (vor dem 50er-Fenster) = nichts (kein Miss).
- **Reihenfolge**: nur das frueheste offene Ziel ist trefferbar (Notelock mit kurzem
  Wackeln), ausser es liegt im selben Zeitpunkt (Akzent) - so bleibt es lesbar.
- **Halten** (`is_hold`): Kopf wie Treffer, dann Taste halten und einer Kugel entlang `path`
  folgen (Folgeradius 2 x Zielradius); mehr als 150 ms ausserhalb oder zu frueh losgelassen
  (vor Ende - 50er-Fenster) = MISS (DROP); sonst zaehlt die Kopf-Qualitaet.
- **Zielfaktor**: bis 50 % Radius 1,0, linear bis 0,88 am Rand (`AIM_EDGE_FACTOR`).
- **Wertung/Score/Grades/Mod-Faktoren unveraendert** (docs/modes/orbit.md, Server prueft):
  Stufenwerte 1,00/0,94/0,68/0,40/0,16/0, Score = 1e6 x (0,9 x Summe(Wert)/N + 0,1 x
  Summe(Wert x min(Kombo/100,1))/N) x Mod-Faktor. N = Zahl der Ziele (Akzent = 1, Halten = 1).

## Datenmodell (verbindlich fuer alle Teil-Aufgaben)
```gdscript
class_name OrbitNote  # scripts/orbit/orbit_note.gd
var time_ms: float
var end_ms: float            # == time_ms bei Tap
var pos: Vector2             # Feld 0..1
var key: int                 # 0 A, 1 B, 2 Akzent
var is_hold: bool
var path: PackedVector2Array # Halten: Feldpunkte, path[0] == pos; Kugel laeuft mit konstanter Geschwindigkeit
var spawn_ms: float          # auf einem Beat
var lap_ms: float            # Dauer einer Satelliten-Runde
var laps: int                # Runden ab spawn_ms (Pips beim Erscheinen)
var source_index: int
static func make(time_ms, pos, key, source := -1) -> OrbitNote
static func make_hold(time_ms, end_ms, path, key, source := -1) -> OrbitNote
func pos_at(t_ms) -> Vector2          # Halten: Kugelposition; Tap: pos
func satellite_deg(t_ms) -> float     # 0 = oben, im Uhrzeigersinn
func laps_left(t_ms) -> int
```
- `OrbitClock` (scripts/orbit/orbit_clock.gd): `beat_ms_at(t)`, `beat_tick_at_or_before(t)`,
  `is_kiai(t)`, `bar_start_at(t)`; aus roten Timing-Points.
- `OrbitConverter.convert(beatmap, laps := 2) -> Array[OrbitNote]` (std + Mania-4K),
  `OrbitConverter.stars(notes) -> float` (0..15), `OrbitConverter.analyze(notes) -> Dictionary`.
- `OrbitCore` (scripts/orbit/orbit_core.gd): `setup(notes, od, mods)`, `update(t)`,
  `cursor_moved(pos: Vector2 /*Feld*/, t)`, `key_down(k: int /*0|1*/, t)`, `key_up(k, t)`;
  Signale `note_judged(index, result)`, `hold_started(index, quality)`,
  `press_missed(pos, key, reason)` mit reason in "aim" | "key" | "early" | "lock";
  `stats()` mit Feldern wie bisher (n_max..n_miss = CORE..MISS, max_combo, accuracy, score,
  grade, aim_err, mode = "orbit"). Replays: Event-Log `[t, EV_CURSOR, x, y]`,
  `[t, EV_DOWN + k]`, `[t, EV_UP + k]`, `meta.orbit_rules = 4`; aeltere Regeln = "aeltere Version"
  (Replay wird mit Hinweis abgelehnt, nicht abgespielt).
- `OrbitView` (scripts/orbit/orbit_view.gd) zeichnet nur; liest `notes`, `t_ms`, Cursor,
  `clock`; Feld->Bildschirm `field_to_screen(p)`, `field_scale()`.

## Konverter
- **osu!standard**: `pos` = x/512, y/384; Taste nach osu!taiko-Regel (Whistle oder Clap = B,
  sonst A; Finish = Akzent); Slider = Halten mit Pfad (HitSlider-Kurve, gekuerzt auf
  max. 2 Beats Dauer bei leichten Maps); Spinner = Akzent in der Mitte.
- **Mania 4K**: Positionen erzeugt (deterministisch): Spalten 1-2 = A, 3-4 = B, Akkord ueber
  beide Seiten = Akzent (Regeln 5: Wechselschlag unter 180 ms, s. o.); Positionsfluss: naechstes Ziel in Richtung je Spalte (links/rechts,
  oben/unten), Abstand ~ Zeitabstand (gekappt), bleibt im Feld, kein Ueberlappen mit noch
  sichtbaren Zielen; Holds = Halten mit kurzem geraden/gebogenen Pfad in Flussrichtung.
- **Lesbarkeit**: Mindestabstand 75 ms (sonst zusammenfassen), hoechstens 6 Ziele zugleich
  sichtbar (bei mehr: Vorlauf-Runden fuer dichte Stellen verringern, zuletzt Teilrunde, s. o.).
  Leichte Maps (< 2,5 Ziele/s): kleine Spruenge, keine Akzente.
- **Sterne** (0..15): Dichte, Sprungweite pro Zeit (Zielen), Tastenwechsel-Rate, Halten.
  Kalibrieren gegen die Bibliothek: Median ~4, leichte Diffs < 2,5.

## Optik (clean wie osu!, Anti-KI-Look)
- Stil TETHRA Graphit + Bernstein (scripts/ui/ui_theme.gd), kein Glow, keine Deko.
- **Buehne** (nur im Spiel, `OrbitView.show_stage`): Graphit-Flaeche ueber die volle Hoehe,
  Feld plus 9 % Feldhoehe Rand je Seite (`stage_rect()`), senkrechter Verlauf, weicher
  Schatten nach aussen, feine Lichtkanten (im Kiai leicht bernstein), feines Raster aus
  Passkreuzen (8 x 6 Felder) und Feld-Ecken. Das Map-Bild bleibt in den Seitenstreifen.
  Vorschau, Tutorial und Endbild zeigen nur die Feld-Ecken.
- Ziel A: kuehle Scheibe mit hellem Rand; Ziel B: warmes abgerundetes Quadrat; Akzent:
  Scheibe mit beiden Farben (halb/halb) und weissem Doppelring. Jedes Ziel von unten:
  weicher Schatten, deckende Platte, Verlauf oben hell / unten dunkel, dunkle Kontur,
  heller Rand, feine Innenkante, Lichtkante oben. Naechstes Ziel voll deckend mit weissem
  Rand, spaetere 62 % (Flaeche kraeftiger als Rand), Taste (z. B. "Z"/"X") im naechsten
  Ziel (Option auto/an/aus). Strichstaerken einheitlich aus dem Zielradius (`_lw`).
- HUD (orbit_game.gd): skaliert mit der Fensterhoehe (720 px = 1). Oben Titel + ORBIT
  (Bernstein), HP, Zeit, Fortschritt; Seitenstreifen links Punkte + Genauigkeit, rechts
  Rang; unten Kombo/Stufe und Timing-Leiste.
- Satellit: kleiner weisser Punkt auf duennem Orbit-Ring (1,6 x Zielradius), Marke oben
  (kurzer Strich). Pips (Runden) klein unter dem Ziel. Erscheinen mit kurzem Pop auf dem Beat.
- Duenne Verbindungslinie zum naechsten Ziel (wie Folge-Punkte, dezent).
- Treffer: Flaeche leuchtet 70 ms in Zielform auf, Umriss in Zielform und Tastenfarbe
  springt in 150 ms nach aussen (Ease-out) und wird duenner, feiner Ring in Stufenfarbe
  leuchtet 210 ms nach; Miss: grauer Umriss + kleines X.
- Halten: Band als Schiene entlang des Pfads (deckend: heller Rand, dunkler Koerper,
  hellere Mittelbahn), Kugel mit Schatten + Folgekreis.
- Musik: Orbit-Ringe pulsieren dezent auf jedem Beat (staerker auf der Takt-Eins), Kiai etwas
  heller; Einstellung "Musik-Reaktion" bleibt.
- HUD wie Mania (gleiche Schrift/Positionen).

## Qualitaets-Ziele (messen, nicht raten)
- Bot "Tablet" (350 Feld-%/s Zielgeschwindigkeit, 25 ms Timing-Streuung) >= 97 % Treffer
  auf Maps < 5 Sterne; Bot "Maus" (250) >= 94 %.
- Hoechstens 6 Ziele gleichzeitig sichtbar, keine Ueberdeckung des naechsten Ziels.
- Jedes Ziel erscheint exakt auf einem Beat-Tick (Fehler < 1 ms).
- Screenshots (leicht, mittel, schwer, Halten, Akzent) muessen auf einen Blick zeigen:
  welches Ziel als Naechstes, wann (Satellit/Pips), welche Taste.

## Skill (einfach zu verstehen, schwer zu meistern - wie osu!)
- **Zielen**: osu!standard-Maps bleiben originalgetreu (Abstaende, Spruenge, Streams,
  Slider-Kurven) - der Skill steckt im Mapping. Nur leichte Maps werden verkleinert.
- **Tempo/Tasten**: A/B-Muster wie Taiko (aus Hitsounds); Streams verlangen Wechselschlag,
  Akzente beide Tasten + Zielen.
- **Lesen**: Vorlauf-Runden aus AR (AR <= 5: 3, 6-8: 2, >= 9: 1), Zielgroesse aus CS wie osu!;
  Mods HD/FI (Satellit/Pips ausblenden), PR (Fenster/Radius enger).
- **Sterne** spiegeln Zielen (Sprung/Zeit, Richtungswechsel), Tempo (Dichte, Wechsel) und
  Lesen (Runden, Ueberlappung) wider: 1 Stern leicht, 8+ schwer.

## Hinweis fuer den Server-Betreiber (Regeln v4 ab Client 1.28.0)
- Orbit-Scores enthalten dieselben Felder wie bisher (n_max..n_miss = CORE..MISS, max_combo,
  accuracy, score, grade, aim_err, mode = "orbit"); Stufenwerte, Score-Formel und
  Mod-Faktoren sind unveraendert, die Server-Pruefung bleibt gleich.
- Neu sind nur die Zeitfenster (wie osu!standard) und die Rundendauer bei schnellen Songs:
  Scores ab Client 1.28.0 (Regeln v4) sind mit aelteren nicht 1:1 vergleichbar. Wer trennen
  will: Client-Version >= 1.28.0 = Regeln v4. Replays tragen `orbit_rules = 4`.
- QA (Bot-Acc je Sterne-Band vorher/nachher): docs/modes/orbit_satellit_qa.md.
- Regeln v5 (Wechselschlag): Felder, Fenster und Score-Formel unveraendert, nur die Tasten der
  Ziele in schnellen Folgen. Replays tragen `orbit_rules = 5`; `min_version` fuer Orbit auf die
  Client-Version setzen, die Regeln v5 ausliefert.
