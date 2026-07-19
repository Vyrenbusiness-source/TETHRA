# HOOKLINE — Masterplan

Grappling-Hook-Rhythm-Game mit Momentum-Physik. Liest osu!-Beatmaps (.osu / .osz). Input: Maus oder Grafiktablett (absolute Pointer-Position), optional 2 frei belegbare Tasten. Timing und Aim sind die Kern-Skills, die Physik ist die Bühne.

---

## 1. Engine & Tech-Stack

- **Engine: Godot 4.x** (GDScript; C# optional, aber GDScript reicht und iteriert schneller)
- **Ziel-Plattform:** Windows/Linux/macOS Desktop, nativ. KEIN Web-Export (Audio-Latenz im Browser disqualifiziert das Spiel).
- **Rendering:** Godot 2D mit Shadern (Glow, Trails, Screen-Shake). Forward+ oder Mobile-Renderer, 2D reicht.
- **Audio:** AudioStreamPlayer mit mp3/ogg aus der Beatmap. Die Audio-Position ist die EINZIGE Zeitquelle des Spiels (siehe Abschnitt 5).
- **Input:** Godot InputEventMouseMotion / InputEventMouseButton. Tablets liefern dieselben Events mit absoluter Position — kein Extra-Code nötig. Raw Input aktivieren (`Input.use_accumulated_input = false` für maximale Präzision in `_input`).

## 2. Core Gameplay Loop

1. Spieler (Komet) ist permanent in Bewegung, Gravitation zieht leicht nach unten, Screen-Wrap gibt es nicht — wer rausfliegt, wird vom Auto-Tether gerettet (Abschnitt 7).
2. Anker (aus HitObjects) erscheinen `preempt` ms vor ihrer Hit-Time an ihrer x/y-Position und schrumpfen einen Approach-Ring (wie osu).
3. **Hit-Bedingung (beides gleichzeitig):**
   - **Aim:** Cursor-Distanz zum Anker-Mittelpunkt ≤ Anker-Radius (aus CS, Abschnitt 4.3)
   - **Timing:** Klick innerhalb des Timing-Windows (aus OD, Abschnitt 4.3)
4. Bei Hit: Hook schießt vom Kometen zum Anker, Komet schwingt physikalisch daran (Pendel um Ankerpunkt, Momentum bleibt erhalten). Loslassen der Maustaste = Release, Komet fliegt tangential weiter.
5. Slider = Schienen (Taste halten, Pfad wird abgefahren), Spinner = Wirbel-Anker (Rotationen sammeln, Release im Beat).

**Fehlerarten (getrennt tracken und anzeigen):**
- Timing-Miss: Klick zu früh/spät, Cursor war korrekt → "LATE"/"EARLY"-Anzeige
- Aim-Miss: Timing korrekt, Cursor daneben → Hook schießt ins Leere Richtung Cursor, sichtbarer Fehlschuss
- Komplett-Miss: gar kein Klick im Window

## 3. .osu-Dateien: Exakte Parsing-Spezifikation

Diese Sektion ist die verbindliche Referenz für den Parser. Format-Referenz ist osu file format v14 (ältere Versionen v9–v13 sind abwärtskompatibel parsbar, fehlende Felder bekommen Defaults).

### 3.1 .osz zuerst

Eine `.osz`-Datei ist ein **ZIP-Archiv** (einfach umbenennen/als ZIP öffnen). Inhalt:
- Eine oder mehrere `.osu`-Dateien (eine pro Schwierigkeitsgrad)
- Die Audio-Datei (mp3 oder ogg)
- Hintergrundbilder, Hitsounds (optional, ignorierbar)

Import-Flow: .osz entpacken → alle .osu-Dateien listen → Spieler wählt Difficulty → zugehörige Audio-Datei laden.

### 3.2 .osu-Dateistruktur

Plaintext, UTF-8. Erste Zeile: `osu file format v14` (Versionsnummer variiert). Danach INI-artige Sektionen. Zeilen mit `//` sind Kommentare. Relevante Sektionen:

```
[General]
AudioFilename: audio.mp3     // Dateiname der Musik, relativ zum Ordner
AudioLeadIn: 0               // ms Stille vor Songstart
PreviewTime: 42000           // ms, für Song-Auswahl-Preview
Mode: 0                      // 0 = osu!standard. NUR Mode 0 akzeptieren!
                             // (1=taiko, 2=catch, 3=mania — ablehnen)

[Metadata]
Title: Songname
Artist: Künstler
Creator: Mapper-Name
Version: Hard                // Name der Difficulty
BeatmapID: 123456

[Difficulty]
HPDrainRate: 5               // HP-Drain, 0–10
CircleSize: 4                // CS → Anker-Radius, 0–10
OverallDifficulty: 7         // OD → Timing-Windows, 0–10
ApproachRate: 8              // AR → Vorlaufzeit der Anker, 0–10
                             // WICHTIG: fehlt AR (alte Maps), gilt AR = OD
SliderMultiplier: 1.4        // Basis-Slider-Geschwindigkeit (100er osupixel pro Beat)
SliderTickRate: 1

[TimingPoints]
// Eine Zeile pro Timing Point, Format:
// time,beatLength,meter,sampleSet,sampleIndex,volume,uninherited,effects
```

### 3.3 TimingPoints — genau lesen!

Format pro Zeile: `time,beatLength,meter,sampleSet,sampleIndex,volume,uninherited,effects`

- `time`: ms-Offset im Song, ab dem dieser Point gilt
- `uninherited = 1` (**rote Linie**): `beatLength` = Millisekunden pro Beat. BPM = `60000 / beatLength`. Setzt das Tempo.
- `uninherited = 0` (**grüne Linie**): `beatLength` ist **negativ** und codiert den Slider-Velocity-Multiplikator: `SV = -100 / beatLength`. Beispiel: `-50` → SV = 2.0 (doppelt so schnelle Slider). Ändert NICHT das Tempo.
- Timing Points gelten ab ihrem `time` bis zum nächsten Point. Für jedes HitObject müssen der **aktuell gültige uninherited-Point** (für beatLength) und der **aktuell gültige inherited-Point** (für SV, Default SV = 1.0 wenn keiner aktiv) ermittelt werden.
- Alte Dateiversionen können weniger Felder pro Zeile haben — Parser muss mit 2+ Feldern klarkommen (dann gilt: nur time und beatLength, uninherited = 1).
- **`effects` ist ein Bitfeld: Bit 0 (`effects & 1`) = Kiai Time.** Kiai markiert die vom Mapper definierten Hype-Passagen des Songs (Drop/Chorus). Beim Parsen daraus eine Liste von Kiai-Intervallen bauen: Kiai beginnt bei einem Point mit gesetztem Bit und endet beim nächsten Point ohne. Diese Intervalle triggern den Tunnel-Modus (Abschnitt 9.1).

### 3.4 HitObjects — das Herzstück

Sektion `[HitObjects]`, eine Zeile pro Objekt:

```
x,y,time,type,hitSound,objectParams,hitSample
```

- `x` ∈ [0, 512], `y` ∈ [0, 384] — **osu-Playfield-Koordinaten.** Auf die eigene Auflösung skalieren: Playfield 4:3 zentriert, `scale = playfieldHeight / 384`.
- `time`: Hit-Zeitpunkt in ms (Audio-Zeit)
- `type`: **Bitfeld!** Per Bit-AND auswerten:
  - Bit 0 (`type & 1`): Hitcircle
  - Bit 1 (`type & 2`): Slider
  - Bit 3 (`type & 8`): Spinner
  - Bit 2 (`type & 4`): New Combo (Combo-Farbwechsel — für uns kosmetisch/Gruppierung)
  - Bits 4–6: Combo-Skip-Anzahl (ignorierbar)
- `hitSound`: Bitfeld für Sounds (ignorierbar in v1)

**Hitcircle** (unser Standard-Anker):
```
x,y,time,type,hitSound,hitSample
// Beispiel: 256,192,11000,1,0,0:0:0:0:
```
Keine objectParams. Fertig geparst mit x, y, time.

**Slider** (unsere Schiene):
```
x,y,time,type,hitSound,curveType|curvePoints,slides,length,edgeSounds,edgeSets,hitSample
// Beispiel: 100,100,12000,2,0,B|200:200|250:100,2,310.5,...
```
- `curveType`: `B` = Bézier, `P` = Perfect Circle (Kreisbogen durch 3 Punkte), `L` = Linear, `C` = Catmull (selten, alte Maps)
- `curvePoints`: pipe-getrennte Kontrollpunkte `x:y` (der Startpunkt x,y der Zeile ist der erste Kurvenpunkt und steht NICHT in dieser Liste). Bei Bézier: doppelte aufeinanderfolgende Punkte = neues Bézier-Segment (Knick).
- `slides`: Anzahl Durchläufe. `1` = einmal hin. `2` = hin und zurück. `3` = hin-zurück-hin. usw.
- `length`: Pfadlänge in osupixeln (die visuelle Kurve auf exakt diese Länge trimmen/strecken)
- **Slider-Dauer (ein Durchlauf):**
  `durationMs = length / (SliderMultiplier * 100 * SV) * beatLength`
  wobei `beatLength` vom gültigen roten Point und `SV` vom gültigen grünen Point kommt. Gesamtdauer = `durationMs * slides`. Endzeit = `time + durationMs * slides`.

**Spinner** (unser Wirbel-Anker):
```
x,y,time,type,hitSound,endTime,hitSample
// x,y sind immer 256,192 — Spinner sind zentriert
```
- `endTime`: ms — Spinner läuft von `time` bis `endTime`.

**Sortierung:** HitObjects sind in der Datei zeitlich sortiert — trotzdem nach dem Parsen defensiv nach `time` sortieren.

### 3.5 Difficulty-Werte in Gameplay-Größen umrechnen

Diese Formeln sind die offiziellen osu!-Formeln — exakt so übernehmen:

**Anker-Radius aus CS (in osupixeln, danach mit Playfield-Scale multiplizieren):**
```
radius = 54.4 - 4.48 * CS
```

**Timing-Windows aus OD (± ms um die Hit-Time):**
```
PERFECT (300): ±(80 - 6 * OD)
GOOD    (100): ±(140 - 8 * OD)
MEH     (50):  ±(200 - 10 * OD)
```
Klick außerhalb des MEH-Fensters, aber innerhalb ±400ms davor: zählt als Miss (Notelock verhindern: nur die zeitlich nächste noch offene Note ist klickbar).

**Approach-Zeit (preempt) aus AR — wann der Anker erscheint:**
```
AR < 5:  preempt = 1200 + 600 * (5 - AR) / 5
AR = 5:  preempt = 1200
AR > 5:  preempt = 1200 - 750 * (AR - 5) / 5
```
Fade-In des Ankers: erste ~2/3 der preempt-Zeit.

### 3.6 Parser-Pseudocode (verbindliche Struktur)

```
parseOsuFile(text):
  version = parse first line
  sections = split by [SectionName] headers
  general = parseKeyValues(sections["General"])
  assert general.Mode == 0 else reject("nur osu!standard-Maps")
  difficulty = parseKeyValues(sections["Difficulty"])
  if difficulty.ApproachRate missing: difficulty.ApproachRate = difficulty.OverallDifficulty
  timingPoints = [parseTimingLine(l) for l in sections["TimingPoints"]]
  hitObjects = []
  for line in sections["HitObjects"]:
    parts = line.split(",")
    x, y, time, type = int(parts[0..3])
    red = latest timingPoint with uninherited==1 and point.time <= time (fallback: erster rote Point)
    green = latest timingPoint with uninherited==0 and point.time <= time (else SV=1.0)
    if type & 2: hitObjects.add(parseSlider(parts, red.beatLength, sv(green), difficulty.SliderMultiplier))
    elif type & 8: hitObjects.add(Spinner(time, endTime=int(parts[5])))
    elif type & 1: hitObjects.add(Circle(x, y, time))
  sort hitObjects by time
  return Beatmap(general, metadata, difficulty, hitObjects)
```

## 4. Physik-Design

- Komet: Punktmasse mit Velocity-Vektor, leichte Gravitation (tunebar, Startwert ~300 px/s²), Luftwiderstand minimal.
- **Hook = Pendel-Constraint:** Bei Hit wird die Distanz Komet↔Anker als Seillänge fixiert. Velocity wird auf die Tangente projiziert (harter Richtungswechsel ist gewollt — das ist der "Snap" bei gutem Timing). Winkelgeschwindigkeit = tangentiale Speed / Seillänge.
- Release (Maustaste loslassen): Komet fliegt mit aktueller Tangentialgeschwindigkeit weiter.
- Timing-Qualität skaliert den Momentum-Erhalt: PERFECT 100%, GOOD 80%, MEH 60% + sichtbarer Ruck.
- Slider: Komet wird auf den Slider-Pfad gesnappt und fährt ihn in exakt der berechneten Slider-Dauer ab (Position = Pfad-Interpolation nach Zeit, keine freie Physik während des Slidens). Release-Timing am Slider-Ende bestimmt Abschuss-Qualität.
- Spinner: Kreisbahn um 256,192; Mausrotation treibt Winkelgeschwindigkeit; Release-Timing im Beat nach endTime-Window gibt Bonus-Speed.
- Physik-Tick fix bei 240 Hz (deterministisch, unabhängig von FPS), Rendering interpoliert.

## 5. Audio-Sync — die wichtigste technische Regel

**Es gibt genau eine Uhr: die Audio-Position.** Niemals delta-Zeit aufsummieren, niemals `Time.get_ticks_msec()` als Spielzeit verwenden.

Godot-Pattern:
```gdscript
var song_time_ms = (audio_player.get_playback_position()
    + AudioServer.get_time_since_last_mix()
    - AudioServer.get_output_latency()) * 1000.0
```
- Diesen Wert jeden Frame berechnen; er ist die Wahrheit für: Anker-Spawns (`time - preempt`), Timing-Judgements, Slider-Progress.
- Klick-Timestamps: im `_input`-Handler sofort die aktuelle song_time_ms erfassen, nicht erst im nächsten `_process`.
- Kalibrierung: globaler User-Offset in ms (Settings-Slider, ±200ms), wird auf alle Judgements addiert. Pflicht-Feature — jedes Audio-Setup hat anderen Latenz-Offset.
- `AudioLeadIn` aus [General] als Stille vor Songstart respektieren.

## 6. Scoring & Wertung

### 6.1 osu-exakte Wertung (verbindlich: 1:1, keine Eigenbauten)

Star Rating, pp und Accuracy müssen exakt den offiziellen osu!-Werten entsprechen. Deshalb:

- **Bibliothek: `rosu-pp`** (Rust) — repliziert den offiziellen osu!-Difficulty- und Performance-Algorithmus exakt. Einbindung in Godot per **GDExtension** (Rust → godot-rust/gdext) oder als schlanke C-FFI-Bibliothek, die GDScript über eine native Extension aufruft. Der Algorithmus wird unter KEINEN Umständen von Hand nachimplementiert.
- **Star Rating:** beim Map-Import pro Difficulty via rosu-pp direkt aus der .osu-Datei berechnen und cachen. Anzeige im Song-Select mit einer Nachkommastelle (z.B. „5.42★"), Farbskala wie osu.
- **Accuracy (offizielle osu-Formel, exakt):**
  `acc = (300*n300 + 100*n100 + 50*n50) / (300 * (n300+n100+n50+nMiss))`
- **pp:** nach Songende das Ergebnis (n300/n100/n50/nMiss, Max-Combo, Mods) an rosu-pp übergeben; die Beatmap-Attribute liefert dieselbe Bibliothek. Ergebnis ist der exakte osu-pp-Wert für diesen Score. Voraussetzung dafür ist, dass die Judgements 1:1 osu entsprechen — die Timing-Windows aus Abschnitt 3.5 sind daher verbindlich und dürfen beim Tuning NICHT verändert werden (getunt wird die Physik, nie die Judgement-Fenster).
- **Versions-Pinning:** rosu-pp-Version fest pinnen und im Results-Screen/Changelog dokumentieren. ppy macht periodisch pp-Reworks; ein Library-Update ändert dann rückwirkend alle Vergleichswerte — Updates nur bewusst, mit Neuberechnung gespeicherter Scores.
- Max-Combo der Map (für pp nötig) ebenfalls aus rosu-pp beziehen, nicht selbst zählen — Slider zählen in osu mehrfach in die Combo (Ticks/Ends), das muss konsistent zur Library sein. Daraus folgt: Slider-Ticks (SliderTickRate) müssen als Combo-Elemente implementiert werden, damit In-Game-Combo und rosu-pp-Max-Combo zusammenpassen.

### 6.2 Arcade-Score (Hookline-eigen, zusätzlich)

- Basis: PERFECT 300, GOOD 100, MEH 50, MISS 0 Punkte pro Anker.
- **Speed-Multiplier:** aktuelle Komet-Geschwindigkeit / Basis-Geschwindigkeit, geclampt auf x1.0–x4.0. Nur PERFECT-Ketten halten hohe Speed (Abschnitt 4) → Timing bleibt der Score-Treiber.
- Combo: +1 pro Hit. GOOD/MEH erhalten Combo, halbieren aber den Speed-Bonus-Aufbau. MISS: Combo → 0.
- Grade S/A/B/C/D nach Accuracy + Miss-Count (S: ≥95% und 0 Miss).
- Results-Screen zeigt beides: osu-Wertung (Acc, pp, Judgement-Verteilung) und Arcade-Score. Leaderboards sortieren nach pp, Arcade-Score als Zweitspalte.

## 7. Miss-Handling (Auto-Tether)

- Miss (egal ob Aim oder Timing): nach Ablauf des MEH-Windows feuert automatisch ein grauer Not-Hook zur übernächsten Note und zieht den Kometen hart auf Kurs.
- Kosten: Combo = 0, beide Notes (verpasste + Rettungsnote) geben 0 Punkte, Speed-Reset auf Basis-Tempo, Trail reißt sichtbar ab und wird grau.
- HP-System: Miss −X HP, PERFECT +kleiner Regen (Drain-Stärke aus HPDrainRate skalieren). HP 0 = Fail. No-Fail-Mode als Option.
- 3 Misses in Folge = Fail (nur im Ranked-Mode).

## 8. Input & Keybinds

- Primär: Maus/Pen absolute Position + Linksklick (Hook) — Klick halten = am Hook bleiben, loslassen = Release.
- 2 optionale, frei belegbare Tasten (Settings-Menü, beliebige Keys):
  - **Boost:** im Beat am Release gedrückt → Extra-Schub, höheres Risiko
  - **Brake/Air-Control:** Flugbahn-Korrektur, kostet Speed-Multiplier
- Beide Tasten optional; ohne sie ist alles spielbar, nur der Top-Speed niedriger.
- Rechtsklick als alternativer Hook-Button (wie osu 2-Button-Klicken) — konfigurierbar.

## 9. Visuals (Richtung, nicht final)

- Neon auf Schwarz. Komet mit additivem Licht-Trail (Länge/Helligkeit ∝ Speed & Combo).
- Anker pulsieren im Beat (Beat-Phase aus aktuellem roten TimingPoint berechnen), Approach-Ring schrumpft über preempt.
- Judgement-Feedback am Anker: PERFECT = weißer Blitz, GOOD = gedämpft, LATE/EARLY-Text bei Timing-Fehlern, Fehlschuss-Funken bei Aim-Miss.
- Screen-Shake bei Miss, leichte Zeitlupe + Kamera-Kick bei Combo-Meilensteinen (50/100/200).
- Kamera: statisch in v1 (Playfield passt auf den Screen, wie osu). Dynamische Kamera erst evaluieren, wenn das Core-Gameplay steht — sie gefährdet die Aim-Lesbarkeit.

### 9.1 Tunnel-Modus (Kiai Time)

Während der Kiai-Intervalle (aus den TimingPoints, Abschnitt 3.3) kippt das Spiel in einen Pseudo-3D-Tunnel. **Eiserne Regel: Die Hit-Ebene bleibt eine flache, frontale 2D-Ebene mit unveränderten Hit-Positionen und -Radien.** Nur Präsentation ändert sich, nie die Aim-Geometrie — sonst wird das Spiel in Kiai-Passagen unfair schwerer.

Aufbau (Godot):
- **Tunnel-Hintergrund:** Fullscreen-Shader (Raymarch- oder klassischer Tunnel-Shader: polare UV-Verzerrung + scrollende Tiefen-Textur). Scroll-Geschwindigkeit und Puls-Helligkeit an die Beat-Phase des aktuellen roten TimingPoints gekoppelt, Grundtempo an die Komet-Geschwindigkeit → schneller fliegen = schneller rasender Tunnel. Alternativ SubViewport mit echter 3D-Szene (Ringe/Tube in Camera3D) als Hintergrund-Layer — Shader-Variante zuerst versuchen, sie ist billiger und ausreichend.
- **Anker-Spawning im Tunnel:** Anker erscheinen nicht per Fade, sondern fliegen während der preempt-Zeit aus dem Tunnel-Fluchtpunkt auf ihre 2D-Zielposition zu (Skalierung klein→voll + Position Fluchtpunkt→Ziel, Easing). Sie erreichen ihre finale Position und volle Größe spätestens bei 50% der preempt-Zeit — ab da stehen sie exakt wie im Normalmodus, damit das Aim-Timing identisch lesbar bleibt.
- **Kamera/Playfield:** maximal 5–8° Perspektiv-Tilt des Playfield-Layers, per Projektions-Korrektur so kompensiert, dass Screen-Positionen der Anker mit den logischen Hit-Positionen übereinstimmen (Input rechnet ohnehin in logischen Playfield-Koordinaten — Render-Transform und Input-Mapping strikt trennen, dann ist der Tilt gameplay-neutral).
- **Komet & Trail:** Trail bekommt Tiefen-Streckung Richtung Fluchtpunkt, Parry- äh Hook-Treffer erzeugen Schockwellen-Ringe, die durch den Tunnel nach hinten laufen.
- **Übergänge:** Kiai-Start = 300–500ms Zoom/Warp-Übergang (Zeitlupe 0.9x für den Übergangsmoment, dann normal), Kiai-Ende = Rückwärts-Warp auf flach. Die Übergänge exakt auf den TimingPoint-Zeitstempel legen — sie sitzen dann automatisch auf dem Drop.
- **Zugänglichkeit/Tuning:** Settings-Toggle "Tunnel-Intensität" (Aus / Dezent / Voll). Motion-Sickness ist bei Tunnel-Shadern real; außerdem Pflicht fürs Testen, ob Kiai-Passagen mit Tunnel dieselbe Accuracy liefern wie ohne — wenn nicht, ist der Effekt zu aggressiv und wird gedrosselt.

## 10. Meilensteine

**M1 — Parser & Playback (Woche 1)**
.osz/.osu-Import, Parser nach Abschnitt 3 inkl. Unit-Tests mit 3 echten Maps (eine alte v9, eine v14, eine mit vielen grünen Linien), Audio-Playback mit Sync-Clock, Debug-Ansicht: Anker erscheinen zur richtigen Zeit an richtiger Position.

**M2 — Core Loop (Woche 2–3)**
Komet-Physik, Hook auf Circles mit Aim+Timing-Judgement, Auto-Tether, Kalibrierungs-Screen. Ziel: eine leichte Map ist von Anfang bis Ende spielbar und fühlt sich im Timing korrekt an. **Hier ausgiebig tunen bevor irgendwas anderes gebaut wird.**

**M3 — Slider & Spinner (Woche 4)**
Bézier/Perfect-Circle/Linear-Pfade rendern und abfahren, Slider-Dauer-Formel verifizieren (gegen osu gegentesten!), Spinner.

**M4 — Scoring, HP, Fail, Results-Screen (Woche 5)**
Inklusive rosu-pp-Anbindung (GDExtension): Star Rating im Song-Select, pp + exakte Acc im Results-Screen. Verifikation: 3 Test-Maps gegen die offiziellen osu-Website-Werte (Star Rating) gegenprüfen und einen bekannten Score durch einen osu-pp-Rechner validieren — Abweichung muss 0 sein.

**M5 — Visuals & Juice (Woche 6+)**
Shader, Trails, Judgement-Feedback, Settings (Keybinds, Offset, Volume), Song-Select mit .osz-Ordner-Scan.

**M6 — Tunnel-Modus (nach M5)**
Kiai-Intervalle aus dem Parser (liegen ab M1 vor, werden hier erst genutzt), Tunnel-Shader, Anker-Fluchtpunkt-Spawning, Übergänge, Intensitäts-Toggle. Abschluss-Kriterium: A/B-Test — gleiche Map, gleiche Spieler-Accuracy mit und ohne Tunnel (±1%). Erst dann gilt der Effekt als fertig.

## 11. Anweisungen an die AI (Cursor/Agent-Regeln)

1. **Abschnitt 3 und 5 sind verbindlich.** Keine eigenen Annahmen über das .osu-Format oder die Zeitmessung — bei Unklarheit die Formeln aus diesem Dokument verwenden, nicht raten.
2. Nur `Mode: 0`-Maps akzeptieren, alles andere mit klarer Fehlermeldung ablehnen.
3. Parser zuerst, mit Unit-Tests gegen echte .osu-Dateien, bevor irgendein Gameplay-Code entsteht.
4. Physik deterministisch (fixer Tick), Spielzeit ausschließlich aus der Audio-Clock.
5. Bestehenden Code vor Änderungen lesen; keine Parallel-Implementierungen derselben Logik.
6. Tuning-Werte (Gravitation, Momentum-Faktoren, HP-Drain) als exportierte Variablen/Config, niemals hardcoden.
7. Keine Features aus M3+ vorziehen, solange M2 nicht spielbar und getunt ist.
8. Tunnel-Modus (Abschnitt 9.1) darf ausschließlich Render-Layer verändern. Hit-Positionen, Radien, Timing-Windows und Input-Mapping bleiben in logischen Playfield-Koordinaten und sind vom Tunnel vollständig entkoppelt. Jede Änderung, die diese Trennung aufweicht, ist abzulehnen.
9. Star Rating, pp und Max-Combo kommen ausschließlich aus rosu-pp (Abschnitt 6.1). Niemals eine eigene Difficulty-/pp-Berechnung schreiben oder „vereinfachte Näherungen" einbauen — bei Integrationsproblemen die GDExtension-Anbindung fixen, nicht den Algorithmus ersetzen. Timing-Windows und Judgement-Logik dürfen nie vom osu-Standard abweichen, sonst ist die pp-Wertung wertlos.
