# Auto-Mapper 4K: Musikdatei -> spielbare 4K-Maps in mehreren Schwierigkeiten

Ziel (Nutzer, 2026-11-13): Eine .mp3/.ogg/.wav ins Spiel ziehen und ohne weiteres Zutun ein Set
mit mehreren 4K-Schwierigkeiten bekommen, das exakt im Takt liegt und sich wie eine von Hand
gebaute Map spielt. Muss für beliebige Songs gehen, nicht nur für die Testsongs.

"Perfekt" ist hier messbar gemacht (Abschnitt Ziele). Alles, was die Ziele nicht erreicht,
steht mit Zahl im Bericht `docs/automap/report.md`; nichts wird schöngeredet.

## Daten

- **Lernmaterial**: `maps/` (rund 250 .osz, über 1000 Diffs, von Menschen gemappt, mit Audio).
  Daraus kommen Wahrheit für Takt (rote Timing-Points), Notenzeiten, Holds, Kiai und Muster.
  `maps/` ist nicht in git; nie etwas daraus committen.
- **Zielsongs des Nutzers**: `own songs/` (heute 2 Dateien). Urheberrechtlich geschützt:
  nie committen, nie hochladen, nicht in Tests/Docs einbetten. Erzeugte .osz landen nur lokal
  in `maps/`.
- ffmpeg: `ClipExporter.find_ffmpeg()` (neben der Exe oder PATH).

## Module (alle unter `scripts/automap/`, reines GDScript, kein Szenenzugriff, thread-fähig)

Jedes Modul nimmt als letzten Parameter `params: Dictionary = {}`. Alle Stellgrößen haben einen
Standardwert im Code (`const DEFAULTS := {...}`) und werden mit `params` überschrieben. Zur
Laufzeit lädt die Pipeline `res://data/automap/params.json` (Abschnitte `grid`, `features`,
`chart`). So kann der Benchmark Werte abstimmen, ohne Code zu ändern.

### AmGrid (`am_grid.gd`) — Takt

```gdscript
## pcm: mono, rate Hz (22050). Liefert das Taktgitter des ganzen Songs.
static func track(pcm: PackedFloat32Array, rate: int, params: Dictionary = {}) -> Dictionary
# {
#   "ok": bool, "error": String,
#   "segments": [ { "start_ms": float,      # ab hier gilt das Segment (erstes: Zeit des 1. Schlags)
#                   "beat_ms": float,       # Länge eines Schlags
#                   "meter": int,           # 4 oder 3
#                   "downbeat_ms": float }  # ein Taktanfang innerhalb des Segments
#               ],                          # zeitlich sortiert, mindestens 1
#   "confidence": float,                    # 0..1
#   "alternatives": [ { "factor": float, "score": float } ]   # z. B. 2.0, 0.5, 1.5, 0.667
# }
static func snap(grid: Dictionary, t_ms: float, div: int) -> float      # nächster 1/div-Schlag
static func beat_pos(grid: Dictionary, t_ms: float) -> float            # Schläge seit Songanfang (stetig je Segment)
static func is_downbeat(grid: Dictionary, t_ms: float, tol_ms: float = 8.0) -> bool
static func scaled(grid: Dictionary, factor: float) -> Dictionary        # Tempo x2, x0.5, x1.5 ...
```

Zeiten sind die akustischen Anschläge minus die osu-Konvention (`OSU_LEAD_MS`, heute 23 ms,
neu messen), also direkt als Timing-Point verwendbar.

### AmFeatures (`am_features.gd`) — was in der Musik passiert

```gdscript
static func decode(audio_path: String) -> Dictionary     # {ok, error, pcm: PackedFloat32Array, rate: int, duration_ms: float}
static func tags(audio_path: String) -> Dictionary       # {artist, title} (Tags, sonst Dateiname; Zusätze wie "(Official Video)" entfernt)
static func analyze(pcm: PackedFloat32Array, rate: int, params: Dictionary = {}) -> Dictionary
# {
#   "ok": bool, "error": String, "duration_ms": float,
#   "events": [ { "t_ms": float,          # Beginn des Anschlags (akustisch, ohne OSU_LEAD)
#                 "strength": float,      # 0..1, über den Song normiert
#                 "kind": String,         # "kick" | "snare" | "hat" | "bass" | "tonal" | "vocal" | "other"
#                 "pitch": float,         # 0..1 Lage (tief..hoch) für bass/tonal/vocal, sonst -1
#                 "sustain_ms": float }   # gehaltener Ton ab t_ms, 0 = kurz
#             ],                          # zeitlich sortiert
#   "energy": PackedFloat32Array,        # Lautheit je Frame, 0..1
#   "frame_ms": float,
#   "sections": [ { "start_ms": float, "end_ms": float,
#                   "intensity": float,   # 0..1
#                   "kind": String,       # "intro" | "verse" | "build" | "chorus" | "break" | "outro"
#                   "kiai": bool,
#                   "lead": String } ]    # führende Ebene: "drums" | "bass" | "tonal" | "vocal"; lückenlos über den Song
# }
```

Nutzer-Vorgabe: **Auf alles wird geachtet** — Schlagzeug (Kick, Snare, Becken/Hi-Hat), Bass und tiefe
Parts (808, Sub, Basslinie), Instrumente (Melodie, Akkorde, Synths) und Stimme (Gesang, Rap-Silben).
Jede Ebene wird getrennt erkannt (eigene Bänder bzw. harmonisch/perkussiv getrennt), keine geht in
einem Summen-Signal unter. `lead` sagt je Abschnitt, welche Ebene die Musik trägt: Im Rap-Vers folgt
die Map den Silben und dem Bass, im Drop dem Schlagzeug und der Melodie, im ruhigen Teil dem
Instrument. Ebenen, die gerade nicht führen, bleiben als Stütze hörbar (z. B. Kick auf dem Schlag).

### AmChart (`am_chart.gd`) — Noten setzen

```gdscript
const PROFILES := ["Easy", "Normal", "Hard", "Insane", "Expert"]
static func build(features: Dictionary, grid: Dictionary, profile: String, params: Dictionary = {}) -> Dictionary
# {
#   "ok": bool, "error": String, "profile": String,
#   "notes": [ { "t_ms": float, "col": int (0..3), "end_ms": float } ],   # end_ms = -1 ohne Hold; sortiert
#   "stats": { "nps_avg": float, "nps_peak": float, "holds": int, "chords": int, "max_jack": int }
# }
```

Noten liegen immer exakt auf dem Gitter (`AmGrid.snap`), `t_ms` enthält bereits `OSU_LEAD`.

### AmWriter (`am_writer.gd`) und AutoMapper4K (`auto_mapper_4k.gd`) — Paket und Ablauf

```gdscript
## Blockiert (Aufrufer startet den Thread). progress: Callable(stage: String, frac: float), optional.
static func generate(audio_path: String, maps_dir: String, opts: Dictionary = {}) -> Dictionary
# opts: { "profiles": Array (Standard alle fünf), "tempo_factor": float (1.0), "offset_ms": float (0.0),
#         "with_orbit": bool (true), "progress": Callable }
# -> { ok, error, osz_path, bpm, offset_ms, confidence, diffs: [ {name, notes, stars} ], alternatives }
static func write_osz(audio_path: String, maps_dir: String, meta: Dictionary, grid: Dictionary,
		features: Dictionary, charts: Array) -> Dictionary     # {ok, error, osz_path}
```

.osz-Inhalt: Audio unverändert als `audio.<ext>`; je Profil eine `.osu` (Mode 3, CircleSize 4,
Version = Profilname, Creator `OMEN Auto`, ein roter Timing-Point je Gitter-Segment mit Meter,
grüne Linien nur für Kiai, `PreviewTime` am Beginn des stärksten Refrains, OD/HP je Profil);
bei `with_orbit` zusätzlich die bisherigen Orbit-Diffs (osu!standard) auf dem NEUEN Gitter.
Das Set ist `unranked` (kein Online-Score), wie bisher bei eigener Musik.

**Bild**: Das im Song eingebettete Cover (Album-Art im mp3/ogg-Tag, per ffmpeg herausgelöst) wird
Hintergrund und Vorschaubild des Sets (`bg.jpg`/`bg.png`, in jeder `.osu` unter `[Events]`
eingetragen). Liegt neben der Musikdatei ein Bild mit gleichem Namen (`<Name>.jpg|png|webp`) oder
genau ein Bild im selben Ordner, hat das Vorrang. Ohne Bild: kein Eintrag (Spiel zeigt seinen
Standard).

## Ziele (gemessen vom Benchmark über `maps/`, Mindestwerte)

| Bereich | Kennzahl | Ziel |
|---|---|---|
| Takt | Tempo exakt (±0,5 %) gegen die rote Linie der Map, bei Maps mit einem Tempo | ≥ 95 % der Songs |
| Takt | Tempo exakt oder gemeldete Alternative (x2, x0,5, x1,5, x0,667) trifft | ≥ 99 % |
| Takt | Betrag des Offset-Fehlers gegen die Map (nur Songs mit richtigem Tempo), Median / 95. Perzentil | ≤ 4 ms / ≤ 12 ms |
| Takt | Drift über den Song (letzter gegen ersten Schlag) | ≤ 10 ms |
| Takt | Songs mit Tempowechsel: Segmentgrenze auf ±1 Schlag, Tempo je Segment exakt | ≥ 80 % |
| Takt | Taktanfang (Downbeat) stimmt mit der Map | ≥ 85 % |
| Noten | Anteil erzeugter Noten, die auf einer Note der Menschen-Map gleicher Dichte liegen (±15 ms) | ≥ 85 % (Hard) |
| Noten | Anteil der Menschen-Noten, die getroffen werden, bei gleicher Notenzahl | ≥ 75 % |
| Noten | Korrelation der Dichtekurve (2-s-Fenster) mit der Menschen-Map | ≥ 0,8 |
| Holds | erzeugte Holds liegen auf gehaltenen Tönen; Anteil, der mit Holds der Menschen-Map überlappt (Maps mit ≥ 10 % Holds) | ≥ 60 % |
| Kiai | Überlappung erzeugter Kiai-Abschnitte mit denen der Map (IoU) | ≥ 0,6 |
| Stufen | Sterne je Profil (rosu, `StarService`): Easy 1,3–1,9 · Normal 2,1–2,8 · Hard 3,0–3,8 · Insane 4,0–4,8 · Expert 5,0–6,0; langsame/ruhige Songs dürfen oben weniger erreichen (dann im Ergebnis sagen) | ≥ 90 % der Songs im Band |
| Spielbarkeit | keine Regelverletzung (unten) | 0 |
| Dauer | ganzer Ablauf je Song (4 min), alle Profile | ≤ 15 s |

Spielbarkeits-Regeln je Profil (prüft `AmChart.lint(notes, grid, profile) -> Array[String]`):

| | Easy | Normal | Hard | Insane | Expert |
|---|---|---|---|---|---|
| feinste Teilung | 1/1, selten 1/2 | 1/2 | 1/4 | 1/4, kurz 1/8 | 1/4, 1/6, 1/8 |
| Akkorde (gleichzeitig) | keine | 2 auf Akzent | 2 | 2, 3 auf starken Akzent | bis 3, 4 nur Schlussakkord |
| Jack (gleiche Spalte in Folge, 1/4) | 0 | 0 | ≤ 2 | ≤ 3 | ≤ 4 |
| Hold und Note gleichzeitig | nein | selten | ja | ja | ja |
| Mindestabstand gleiche Spalte | 1/1 | 1/2 | 1/4 | 1/4 | 1/8 |
| Hand-Balance (links/rechts) | 40–60 % | 40–60 % | 42–58 % | 42–58 % | 42–58 % |

Musikalische Regeln für alle Profile: Tonhöhe steigt -> Spalte wandert nach rechts (und umgekehrt);
wiederholte Motive bekommen dasselbe Muster; Kick/Snare bekommen feste, erkennbare Rollen innerhalb
eines Abschnitts; Akzente (Taktanfang, Becken) werden Akkorde; gehaltene Töne werden Holds, deren
Ende auf dem Gitter liegt; Pausen in der Musik bleiben Pausen (keine Füllnoten); die Dichte folgt
der Intensität des Abschnitts; leichtere Profile sind eine Auswahl derselben Stellen (nie Noten, wo
das schwerere Profil keine hat, außer vereinfachte Holds).

## Regeln für alle Agents

- Eigene Dateien nur wie in der Aufgabe genannt. Schnittstellen dieser Spec nicht ändern; wenn eine
  Schnittstelle nicht reicht, im Bericht sagen und abwärtskompatibel ergänzen (neues Feld).
- Kein Python/Node im ausgelieferten Weg. Auswertungs-Skripte laufen als Godot-Skript
  (`--headless --script`), ein Prozess für viele Maps (der PC verliert RAM je Prozessstart).
- Der bisherige `scripts/library/audio_mapper.gd` (Orbit) bleibt lauffähig, bis die Pipeline ihn ersetzt.
- Name des Spiels in neuen Texten: OMEN.
