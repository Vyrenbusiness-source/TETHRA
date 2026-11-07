# HANDOFF — TETHRA (Stand 2026-11-06 23:25, nach v1.7.1)

Fuer die naechste Session nach dem PC-Neustart. Alles Fertige ist gemergt, gepusht und released (v1.7.1). Keine Agents laufen.

## Sofort erledigen (in dieser Reihenfolge)

1. **warmd-Ship pruefen:** Fix "RAM vor Slot" lief als `warmd ship --release v0.4.25 ram-before-slot` aus dem Worktree `C:/Users/Gexanx/Desktop/.warmd-worktrees/warmd/ram-before-slot`. Pruefen: `warmd --version` (soll 0.4.25 sein) und `gh pr list -R Vyrenbusiness-source/warmd`. Falls nicht gemergt: Konflikte (meist CHANGELOG.md) loesen und neu shippen. Danach Worktrees `owner-prune` und `ram-before-slot` unter `.warmd-worktrees/warmd/` entfernen.
2. **Task integrate-d ausfuehren** (vorbereitet, noch NICHT gestartet): `.warmd/tasks/integrate-d.md` bzw. `.warmd/tasks26.txt`. Baut die vier fertigen Module in `scripts/gameplay3d/mania_3d.gd` ein und entfernt das alte HUD-Gegenstueck:
   - `JudgeDisplay` (`scripts/gameplay3d/fx/judge_display.gd`): Judge-Popups + Kombo, FRUEH/SPAET
   - `HitErrorBar` (`scripts/ui/hit_error_bar.gd`): Timing-Leiste, Fenster aus `core.w*`
   - `HpBar` (`scripts/ui/hp_bar.gd`): HP oben
   - `BreakOverlay` (`scripts/ui/break_overlay.gd`): Intro/Breaks, 3-2-1 exakt auf dem Beat, Skip-Hinweis
   - Beat-FX-Zeit: `_clock.update(t, delta)` -> `_clock.update(SyncClock.visual_time_ms(), delta)` (nur visuell)
   - Vorher neu splitten: `warmd split .warmd/tasks26.txt` (alter Batch ist beendet).
3. **Pruefen + Release v1.7.2** (siehe Release-Ablauf). Danach dem Nutzer kurz melden. Nutzer will danach SPIELEN: keine neuen Aufgaben ohne Auftrag.

## Kleine offene Punkte (nur wenn Zeit / Nutzer will)
- `main_menu.gd`: Fade-out fehlt bei Tutorial/Settings; `_bg_mat` "kick" nutzt noch Spektrum statt Beat-Puls.
- `hp_bar.gd`: Leiste mit/ohne Label beginnt an unterschiedlicher x-Position.
- Results im Lobby-Modus (Rangliste rechts) nie gerendert/geprueft.
- Clip-Export-Button im Results nie im Fenster geklickt.
- README-Bilder (`docs/media/`) zeigen noch alte Pad-Labels/alten Look -> nach integrate-d neu aufnehmen (Autoplay-Shot).
- Social-Preview `docs/media/social_preview.png` muss der NUTZER selbst hochladen (GitHub Settings > Social preview).

## Pruefen ohne warmd-Warteschlange (falls RAM knapp)
Skript-Logik (war `/tmp/verify.sh`, nach Neustart weg) — im Worktree:
```bash
G=/c/Users/Gexanx/Desktop/rhyg/Godot_v4.7-stable_win64_console.exe
git clean -fdq -- '*.import' '*.uid'; git checkout -q -- .
timeout 200 $G --headless --audio-driver Dummy --path . --import >/dev/null 2>&1
timeout 90 $G --headless --audio-driver Dummy --path . --quit 2>&1 | grep -cE "SCRIPT ERROR|Parse Error"   # muss 0 sein
for t in tests/run_*.gd; do timeout 150 $G --headless --audio-driver Dummy --path . --script res://$t >/dev/null 2>&1 || echo "FAIL $t"; done
```
Gameplay-Bild: `./Godot_v4.7-stable_win64.exe --screen 1 --audio-driver Dummy --path . res://scenes/song_select.tscn --mania --autoplay --shot` -> PNG in `C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/mania_3d.png` (mit Read ansehen). Merge danach: `WARMD_BASE=1 warmd merge --no-gate warmd/<task>`.

## Release-Ablauf (bei JEDEM Update, Nutzer-Vorgabe)
1. `CURRENT_VERSION` in `scripts/net/updater.gd` bumpen.
2. `--import`, Parse-Check, `--export-pack "Windows" release/TETHRA.pck` (~7.8 MB; `store/ docs/ release/` haben .gdignore).
3. Smoke: Kopie der Console-Exe + `--main-pack <pck> --headless --audio-driver Dummy --quit-after 200`, 0 Fehler.
4. `TETHRA_v1.zip`: nur den Eintrag `TETHRA.pck` ersetzen (Python zipfile, Rest kopieren).
5. Commit, push, `gh release create vX.Y.Z release/TETHRA.pck TETHRA_v1.zip --title ... --notes ...` (Asset MUSS `TETHRA.pck` heissen).

## Regeln des Nutzers (verbindlich)
- Gameplay ist das Wichtigste; Lesbarkeit vor Glanz; nichts grell, kein Wackeln/Blitze.
- Alles Deutsch mit echten Umlauten, deutsche Zahlen (`UiTheme.fmt_*`).
- Tests lautlos (`--audio-driver Dummy`) und Fenster unsichtbar (`--position -1700,120` (Monitor 2 links) + override.cfg aus tools/test_override.cfg); Szenen-Flags nicht hinter `--`.
- Bis 15 Agents, Budget 300k/500k (`warmd.conf`); Agents als `general-purpose` mit den Regeln aus `.claude/agents/warmd-worker.md` starten (nach Session-Neustart evtl. direkt `warmd-worker`).
- Meldungen kurz, Ergebnis zuerst.

## Technischer Kontext
- Projekt-Memory: `C:/Users/Gexanx/.claude/projects/c--Users-Gexanx-Desktop-rhyg/memory/hookline-projekt.md` (Abschnitt "Grosse Qualitaets-Runde").
- QA-Bericht: `docs/qa/report.md` (Stand vor der Polish-Runde).
- Bekannte Fallen: untracked `.uid`/`.import` in Worktrees blockieren warmd-Pruning und Merges -> generierte UIDs in main einchecken, im Worktree `git clean -fdq -- '*.uid' '*.import'`. Viele Godot-Starts -> Kernel-Pool-Leck, RAM < 2 GB, Godot-"sofortiger Ausnahmefehler"; Neustart hilft. Test-Watchdog in `game_session.gd` beendet Shots nach 45 s, Runner nach 120 s.

## Naechste Runde (Nutzer-Ideen, NOCH NICHT starten — Nutzer will erst spielen)
- Hintergrund "kranker": im Takt durch die Galaxie reisen — Sternenfeld zieht pro Beat sichtbar vorbei (Warp-Puls auf Beat, kein Kamera-Wackeln), Nebel/Galaxien/Planeten wechseln pro Song-Abschnitt (Kiai = neue Galaxie), Tiefe/Parallax, alles ruhig genug fuer Lesbarkeit.
- Groove 2: Feier-Effekte (Meilensteine, Skill-Stufen, Kiai-Start) auf naechsten Beat/Downbeat quantisieren; Intensitaetskurve pro Map vorab aus Notendichte+Kiai; Spurlicht beim Halten im Takt; Hitsounds evtl. standardmaessig an (Nutzer fragen).

## Stand 2026-11-07 (Agents gestoppt, Nutzer spielt v1.7.5)
Offen, beim naechsten "weiter" fortsetzen (Agents per Handoff neu starten, Worktrees haben Commits):
- galaxy-travel (Worktree browser): Kapitel/Vorbeiflug-Szenerie + Strecken-Puls exakt auf Beat (Messung: Strecke 95 ms Streuung).
- clock-fix (Worktree lane-light): sporadisch nicht-monotone Song-Uhr + Movie-Modus-Zeitbasis (Clips ~200 ms versetzt).
- skybox-art (Worktree skybox-art): 4K-Panoramen + shaders/sky_panorama.gdshader.
- beat-sync-check (Worktree beat-sync-check): NameError MIX_RATE/MIX_BLOCK fixen, Bericht docs/perf/beat_sync.md.
- Danach: BeatQuantizer, IntensityMap, LaneLight, MilestoneBurst in mania_3d einbauen.
WICHTIG Testfenster: Worktrees VOR jedem Fensterlauf `git merge --no-edit main` (enthaelt den Fix "bei Tests kein Vollbild + Fenster auf Nicht-Hauptmonitor" in settings.gd), sonst landet das Fenster im Vollbild auf Monitor 1. Dazu override.cfg aus tools/test_override.cfg. `warmd` ist evtl. nicht im PATH: /c/Users/Gexanx/.local/bin/warmd.

## Stand 2026-11-07 spaet (Limit-Stopp, v1.7.9 released)
Gemergt in main, aber NOCH NICHT im Spiel aktiv (Auswahl-Integration fehlt):
- Fertig: Welten boss (Bosskampf, monochrom rot) und aurora (= "Frost", Eis) inkl. Assets/Shader/Preview.
- WIP (Stand beim Stopp gemergt, Assets evtl. unvollstaendig/ungeprueft): eclipse, abyss, fractal, singularity, storm, obsidian (tools/gen_theme_<n>.py, shaders/theme_<n>.gdshader, assets_game/themes/<n>/, scenes/theme_<n>_preview.tscn). Je Thema: Generator laufen lassen falls Bilder fehlen, Preview-Screenshots pruefen, fertig polieren.
- Integration: Task .warmd/tasks40.txt (theme-dark-integrate) — Worktree beat-sync-check hat evtl. WIP-Commit "theme-dark-integrate: WIP (Limit-Stopp)" (nicht gemergt). Inhalt: alle dunklen Welten in world_theme.gd, Auto-Wahl nur vorhandener Themen, Galaxie ~3 %, keine Planeten in dunklen Welten, Spielfeld-Farben je Thema, Neon nur manuell, Settings "Welt"-Liste.
- Danach Release (v1.8.0 "Dunkle Welten").
- Noch nicht eingebaut (Module fertig in main): BeatQuantizer, IntensityMap, LaneLight, MilestoneBurst.
- Bekannt wackelig: tests/run_mastering_tests.gd (sporadisch rot, beim 2. Lauf gruen).

## v1.8.0 released (dunkle Welten aktiv)
- Aktiv im Spiel: boss, aurora(Frost), eclipse, abyss, fractal, obsidian (+ galaxy ~3 %, neon manuell).
- storm und singularity: noch ohne Assets (Generator tools/gen_theme_<n>.py laufen lassen / fertig bauen) — erscheinen automatisch, sobald shaders/theme_<n>.gdshader + assets_game/themes/<n>/*.webp existieren (WorldTheme.is_available).
- Optional Feinschliff: eclipse/abyss/fractal/obsidian Previews nochmal pruefen (wurden beim Limit-Stopp gemergt).

## Welten-Runde 2026-11-07 (Batch tasks42/43/44 laeuft, 8 Agents)
- Gemergt: beat-core (Beat-Vertrag docs/worlds/beat_contract.md im Spiel, Drop gedeckelt, neue Welten monolith/rift/nerve registriert).
- Offen: worlds-storm-sing, worlds-dark-a (boss, eclipse), worlds-dark-b (abyss, fractal, aurora), worlds-new (monolith), world-rift, world-nerve, world-obsidian, mp-check (Multiplayer: Live-Battle links, Kartenwahl, Host geben).
- Nutzer-Vorgaben: Fraktal-Stil (vorbeifliegende 3D-Splitter) ist Referenz; Sturm = Durchflug durch Tornado; maximal scharf (8192, BPTC, anisotrop); extrem viele FPS (<=15 % Verlust ggue. sky_panorama, [perf] in Preview); Drop nicht zu stark; Neon nicht anfassen; max 8 Agents.
- Danach: Merge, Spiel-Shots je Welt, Release (Ablauf oben).
