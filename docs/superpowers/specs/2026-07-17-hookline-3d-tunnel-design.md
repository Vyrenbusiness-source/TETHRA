# HOOKLINE — Design: 3D-Tunnel-Gameplay & Browser-Upgrade

Datum: 2026-07-17 · Status: vom Nutzer freigegeben · Ergänzt `HOOKLINE_MASTERPLAN.md`

## Nutzer-Entscheidungen (Grundlage dieses Designs)

1. **3D-Umfang:** 3D-Look mit logisch flacher 2D-Hit-Ebene („3D-Look, 2D-Aim"). Kein echtes 3D-Gameplay.
2. **Kern-Loop:** Masterplan-Loop (Klick im Timing-Window + Cursor-Aim + Hook-Schwung) — aber **permanent** im 3D-Tunnel statt nur bei Kiai. Grund: Das Spiel soll sich nicht wie osu anfühlen.
3. **Browser:** Deutlich näher an der Rhythia-Vorlage (Karten mit Cover-Hintergrund, Sterne, Tabs, Profil-Ecke).
4. **Priorität:** Gameplay zuerst, Browser danach.
5. **AR-Override:** Später als Setting einstellbar (nur Anflugzeit, nie Timing-Windows; Scores damit „unranked").

Diese Entscheidungen überstimmen den Masterplan dort, wo sie ihm widersprechen (2D-Rendering, Tunnel nur bei Kiai). **Nicht** überstimmt und weiterhin verbindlich: Abschnitt 3 (Parsing), 3.5 (Formeln), 5 (Audio-Clock), 6.1 (rosu-pp/Regel 9), Regel 8 (Render/Input-Trennung).

## Architektur: zwei Schichten

### Logik-Schicht (2D, headless testbar)

Vorhanden und unverändert: `OsuParser`, `Beatmap`, `SyncClock`, `DifficultyCalc`, `OszImporter`, `MapLibrary`.

Neu — `GameplayCore` (reine Logik, keine Render-Nodes):

- **NoteScheduler:** liefert pro Frame die aktiven Objekte; Spawn bei `hitTime − preempt`. `preempt` ist Parameter (Basis: AR-Formel; AR-Override ersetzt nur diesen Wert).
- **JudgementEngine:** Klick-Bewertung in osu-Koordinaten. Hit = Cursor-Distanz ≤ Radius(CS) UND |Klickzeit − hitTime| ≤ Window(OD). Fenster exakt Abschnitt 3.5, unveränderlich. Notelock: nur die zeitlich nächste offene Note ist klickbar; Klick außerhalb MEH aber innerhalb −400 ms = Miss. Miss-Arten getrennt: Timing-Miss (LATE/EARLY), Aim-Miss (Hook ins Leere), Komplett-Miss.
- **CometPhysics:** Punktmasse, Gravitation ~300 osu-px/s² (exportiert/Config), fixer 240-Hz-Tick, deterministisch. Hook = Pendel-Constraint (Seillänge = Distanz bei Hit, Velocity auf Tangente projiziert). Momentum-Erhalt: PERFECT 100 %, GOOD 80 %, MEH 60 % + Ruck. Release = tangentialer Abflug.
- **AutoTether:** nach Miss grauer Not-Hook zur übernächsten Note; Combo 0, beide Notes 0 Punkte, Speed-Reset.
- **HP/Fail:** Drain aus HPDrainRate, Miss −X, PERFECT +Regen; HP 0 = Fail; No-Fail-Mod (NF-Toggle im Browser wird real).
- Alle Zeiten aus `SyncClock.judgement_time_ms()` (inkl. Kalibrierungs-Offset). Klick-Timestamps sofort im `_input`.

### Render-Schicht (neu, echtes 3D)

`Gameplay3D`-Szene (ersetzt die 2D-Debug-View als Spielszene; Debug-View bleibt Werkzeug):

- Fixe `Camera3D` blickt entlang −Z. **Hit-Ebene bei z = 0**, bildet das osu-Playfield 512×384 ab und füllt das Bild wie das bisherige 2D-Playfield.
- **Maus-Mapping:** Bildschirm → osu-Koordinate ist eine konstante affine Transformation (Kamera fix, Ebene senkrecht). Einmal berechnet, exakt, keine Verzerrung. Input rechnet ausschließlich in osu-Koordinaten (Regel 8).
- **Tiefe ersetzt Approach-Ring:** Anker spawnen bei finaler x/y, aber bei `z = −(hitTime − songTime)/preempt × SPAWN_DEPTH` und erreichen die Ebene exakt zur Hit-Time. x/y wandern nie → Aim bleibt die ganze Anflugzeit lesbar. Optional dezenter Ring auf der Ebene als Landepunkt-Marker.
- **Objekte:** Anker = leuchtende Scheiben/Ringe (Emissive + Glow); Slider = Leucht-Schienen auf der Ebene, reisen aus der Tiefe an; Spinner = Wirbel im Zentrum; Komet = Leuchtkugel + Trail (Länge/Helligkeit ∝ Speed & Combo), schwingt auf z = 0.
- **Tunnel:** Shader-Tube um die Spielachse + `WorldEnvironment`-Glow; Scroll an Beat-Phase (roter TimingPoint) und Komet-Speed gekoppelt.
- **Kiai:** eskaliert nur Präsentation — Tunneltempo, Farbe, FOV-Kick, Übergangs-Warp auf dem TimingPoint-Zeitstempel. Nie Geometrie/Aim.
- **HUD:** Combo, Accuracy, Judgement-Popups (PERFECT/GOOD/MEH/LATE/EARLY/MISS), HP-Balken, Speed-Multiplier.

## Gameplay-Regeln (verbindlich)

Wie Masterplan Abschnitte 2, 4, 7, 8 — Klick halten = schwingen, loslassen = Release; 2 optionale Zusatztasten (Boost/Brake) später; Rechtsklick als Alt-Hook. Slider: Snap auf Schiene, Abfahrt in exakter berechneter Dauer, Release-Qualität am Ende. Spinner: Kreisbahn, Mausrotation, Release im Beat.

## Song-Browser (Phase B1)

- Karten mit Cover als Kartenhintergrund (Gradient-Abdunklung), kräftiger Farbrahmen, Titel/„Mapped by", Sterne-Zeile (Platzhalter „—" bis rosu-pp in M4; niemals Eigenberechnung), Dauer.
- Kopf: Profil-Ecke links; rechts Tabs (Downloaded aktiv, Collections deaktiviert), Suche, Sortierung.
- Auswahl: Karte leuchtet/rückt heraus; Info-Panel mit Cover-Glow und Beat-Puls zur Preview.
- Zahnrad → Settings: Kalibrierungs-Offset (±200 ms), **AR-Override (Aus/0–10)**, Tunnel-Intensität (Aus/Dezent/Voll), Keybinds, Volume. AR-Override markiert Scores als „unranked" (kein pp).
- Drag&Drop-Import bleibt.

## Phasen

1. **G1:** `GameplayCore` rein logisch + Headless-Tests.
2. **G2:** 3D-Szene auf Core verdrahtet; eine leichte Map von Anfang bis Ende spielbar; Tuning-Pass.
3. **G3:** Slider-Schienen + Spinner in 3D (Pfad-Geometrie: Bézier/Perfect-Circle/Linear aus Abschnitt 3.4).
4. **B1:** Browser-Umbau + Settings-Screen.

rosu-pp/Star-Rating bleibt M4 (nach G3/B1), unverändert nach Masterplan 6.1.

## Fehlerbehandlung

- Map ohne ladbares Audio oder ohne HitObjects: Fehlermeldung, zurück zum Browser.
- Fail: Fail-Screen mit Retry/Zurück. Esc = Abbruch zurück zum Browser.

## Tests

- **Headless:** JudgementEngine (Fenster-Grenzen, Notelock, Miss-Arten), NoteScheduler (Spawn-Zeiten inkl. AR-Override), CometPhysics-Determinismus (identischer Input-Replay ⇒ bitgleicher Zustand), AutoTether.
- **Maus-Mapping:** Round-Trip Bildschirm↔osu exakt (Toleranz < 0,01 px).
- **Visuell:** `--shot`-Screenshots der 3D-Szene zu definierten Songzeiten.
- **A/B-Kriterium (aus 9.1):** gleiche Map, gleiche Accuracy mit Tunnel Voll vs. Dezent (±1 %), sonst Effekt drosseln.
