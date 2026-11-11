# Orbit: Satelliten (Neubau 2026-11-11)

Ersetzt "Bahnen" (Kreis/Acht/Bluete) und "Taktkreis". Gruende (Spieler): schlecht lesbar,
Formen verwirrend, nicht spuerbar im Takt, "schon gesehen". Name bleibt **Orbit**.

## Idee in einem Satz
Ziele erscheinen genau auf einem Schlag an einer Stelle im Feld; um jedes Ziel kreist ein
**Satellit genau eine Runde pro Beat**. Kleine Punkte unter dem Ziel zaehlen die
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

## Regeln
- **Feld**: 4:3, Koordinaten 0..1 x 0..1 (wie osu! 512x384 normiert), zentriert,
  Hoehe = 80 % der Bildschirmhoehe.
- **Ziel** (`OrbitNote`): `pos` (Feld), `key` 0 = A (kuehl, Scheibe), 1 = B (warm,
  abgerundetes Quadrat), 2 = Akzent (beide Tasten, Scheibe mit weissem Ring), Zeit `time_ms`.
- **Erscheinen**: auf dem Beat `spawn_ms` = letzter Beat-Tick <= `time_ms - laps * beat_ms`
  (Beat-Ticks aus den roten Timing-Points). `laps` = Runden (Standard 2, Einstellung
  "Vorlauf" 1-4 Runden). Ist ein Beat kuerzer als 330 ms, zaehlt eine Runde 2 Beats
  (`lap_ms = 2 * beat_ms`), damit der Satellit ruhig bleibt.
- **Satellit**: Winkel `360 * frac((time_ms - t) / lap_ms)` gegen den Uhrzeigersinn
  gerechnet so, dass er bei `t = time_ms` exakt oben steht; Punkte (Pips) unter dem Ziel =
  verbleibende ganze Runden.
- **Treffer**: Taste gedrueckt im Zeitfenster (OD wie Mania: CORE/SHARP/GOOD/FAIR/EDGE/MISS
  = MAX/300/200/100/50/Miss-Fenster) **und** Cursor im Trefferradius (`AIM_RADIUS` = 1,15 x
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
  `[t, EV_DOWN + k]`, `[t, EV_UP + k]`, `meta.orbit_rules = 3`; aeltere Regeln = "aeltere Version".
- `OrbitView` (scripts/orbit/orbit_view.gd) zeichnet nur; liest `notes`, `t_ms`, Cursor,
  `clock`; Feld->Bildschirm `field_to_screen(p)`, `field_scale()`.

## Konverter
- **osu!standard**: `pos` = x/512, y/384; Taste nach osu!taiko-Regel (Whistle oder Clap = B,
  sonst A; Finish = Akzent); Slider = Halten mit Pfad (HitSlider-Kurve, gekuerzt auf
  max. 2 Beats Dauer bei leichten Maps); Spinner = Akzent in der Mitte.
- **Mania 4K**: Positionen erzeugt (deterministisch): Spalten 1-2 = A, 3-4 = B, Akkord ueber
  beide Seiten = Akzent; Positionsfluss: naechstes Ziel in Richtung je Spalte (links/rechts,
  oben/unten), Abstand ~ Zeitabstand (gekappt), bleibt im Feld, kein Ueberlappen mit noch
  sichtbaren Zielen; Holds = Halten mit kurzem geraden/gebogenen Pfad in Flussrichtung.
- **Lesbarkeit**: Mindestabstand 75 ms (sonst zusammenfassen), hoechstens 6 Ziele zugleich
  sichtbar (bei mehr: Vorlauf-Runden fuer dichte Stellen verringern, nie unter 1).
  Leichte Maps (< 2,5 Ziele/s): kleine Spruenge, keine Akzente.
- **Sterne** (0..15): Dichte, Sprungweite pro Zeit (Zielen), Tastenwechsel-Rate, Halten.
  Kalibrieren gegen die Bibliothek: Median ~4, leichte Diffs < 2,5.

## Optik (clean wie osu!, Anti-KI-Look)
- Dunkler ruhiger Grund (Welt-Hintergrund stark abgedunkelt/unscharf), kein Glow, keine Deko.
- Ziel A: kuehle Scheibe mit hellem Rand; Ziel B: warmes abgerundetes Quadrat; Akzent:
  Scheibe mit beiden Farben (halb/halb) und weissem Ring. Naechstes Ziel voll deckend,
  spaetere 55 %, Taste (z. B. "Z"/"X") im naechsten Ziel (Option auto/an/aus).
- Satellit: kleiner weisser Punkt auf duennem Orbit-Ring (1,6 x Zielradius), Marke oben
  (kurzer Strich). Pips (Runden) klein unter dem Ziel. Erscheinen mit kurzem Pop auf dem Beat.
- Duenne Verbindungslinie zum naechsten Ziel (wie Folge-Punkte, dezent).
- Treffer: knapper Ausdehn-und-Ausblend-Effekt in Zielfarbe (< 150 ms); Miss: kleines X.
- Halten: weiches Band entlang des Pfads in Zielfarbe, Kugel + Folgekreis.
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
