# 3D-Tunnel-Gameplay — Implementierungsplan (kompakt)

> Spec: `docs/superpowers/specs/2026-07-17-hookline-3d-tunnel-design.md`
> Auf Nutzerwunsch verkürzt: sichtbares Rhythia-artiges Ergebnis hat Priorität, Ausführung inline in dieser Session. Kein Git-Repo vorhanden → keine Commit-Schritte.

**Ziel:** Spielbarer Loop: Anker fliegen im 3D-Tunnel auf die Hit-Ebene zu, Klick+Aim-Judgement (osu-exakt), Komet schwingt am Hook, HUD, Fail/Results.

**Stack:** Godot 4.7, GDScript. Logik 2D (osu-Koordinaten, headless testbar), Rendering echtes 3D.

## Konstanten / Verträge

- Welt-Skala: `WORLD_SCALE = 1/32` → osu 512×384 ⇒ Ebene 16×12 Welt-Einheiten, zentriert (0,0), z=0.
- osu→Welt: `world = ((osu.x−256)·s, (192−osu.y)·s, 0)`. Maus→osu via `Camera3D.project_position(screen, D)` (Kamera fix bei (0,0,D), Blick −Z) — exakt, da Ebene senkrecht.
- Anflug: `z = −(hitTime−t)/preempt · SPAWN_DEPTH` (SPAWN_DEPTH = 70). Ankunft exakt zur Hit-Time.
- Judgement unverändert Abschnitt 3.5 (DifficultyCalc). Notelock: nächste offene Note; Klick in [−400, −MEH) = Miss.
- Momentum: PERFECT 1.0, GOOD 0.8, MEH 0.6.
- Auto-Tether: Miss ⇒ grauer Hook zur übernächsten Note; verpasste + Rettungsnote = beide MISS (0 Punkte), Combo 0.
- Slider v1 = Head wie Circle (Schiene/Abfahren = G3). Spinner v1 = Auto-300 bei endTime (G3 echt).

## Tasks

### T1 `scripts/gameplay/comet_physics.gd` — CometPhysics (RefCounted)
Punktmasse in osu-px; `gravity=300` (export/Config); `tick(dt)`; `hook_to(anchor, quality_scale)` projiziert Velocity auf Pendel-Tangente; `release()`; Tether-Modus mit schrumpfendem Seil; deterministisch (kein Zufall).

### T2 `scripts/gameplay/gameplay_core.gd` — GameplayCore (RefCounted)
`setup(beatmap)`, `update(t_ms)` (Spawns via `hitTime−preempt`, Expiry via `+MEH`, Spinner-Autoresolve), `handle_click(t_ms, cursor_osu)`, `release()`. Signals: `note_spawned/note_judged/hook_attached/hook_released/auto_tethered/finished`. Stats: n300/n100/n50/nMiss, Combo/Max-Combo, Acc (offizielle Formel), HP, Grade. `preempt` als Parameter (AR-Override-ready).

### T3 `tests/run_gameplay_tests.gd` — Headless-Tests
Fenster-Grenzen (PERFECT/GOOD/MEH exakt an Kante), Aim-Miss (Distanz > Radius), Notelock-Early-Miss, Komplett-Miss+Auto-Tether (beide Notes MISS), Acc-Formel, Physik-Determinismus (2 identische Läufe ⇒ identische Position).

### T4 `scripts/gameplay3d/gameplay_3d.gd` + `scenes/gameplay_3d.tscn` + `shaders/tunnel.gdshader`
Programmatischer Aufbau: WorldEnvironment (Glow, schwarz), Camera3D (0,0,9, fov 70), Tunnel-Tube mit Scroll-Shader (Beat-Phase + Kiai-Intensität als Uniforms), Hit-Ebenen-Grid dezent, Anker = Emissive-Discs + Ring (Label3D-Popups PERFECT/…/LATE/EARLY), Slider-Pfad als Leuchtlinie (reist mit dem Head an), Komet = Emissive-Kugel + Ribbon-Trail (ImmediateMesh), Seil (Linie, cyan/grau), Cursor-Reticle auf der Ebene. HUD (CanvasLayer): Combo, Acc, HP-Balken, Speed. Kiai: Tunnel-Tempo/Farbe/FOV-Kick. Ende/Fail: Overlay mit Stats + Retry/Zurück (Esc = Browser).

### T5 Verdrahtung + Verifikation
`song_select.gd`: PLAY → `gameplay_3d.tscn`. `--shot`-Screenshotpfad in Gameplay3D. Headless: Parser- + Gameplay-Tests grün; windowed `--autoplay --shot` Screenshot prüfen (Tunnel sichtbar, Anker in Tiefenstaffelung, HUD).
