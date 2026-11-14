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
2. Neue Welt hinzugekommen? `python tools/sync_world_preset.py` (schreibt die Preset-Liste "Worlds"). Nahe Ebenen bleiben `process/size_limit=0` (8192), ferne Panoramen/Nebel/Sterne `4096` in der `.import`.
3. `--import`, Parse-Check, dann ZWEI Pakete: `--export-pack "Windows" release/TETHRA.pck` (klein, ohne `assets_game/themes/`) und `--export-pack "Worlds" release/TETHRA_worlds.pck` (gross, nur Welten). Das Welten-Paket nur neu bauen/hochladen, wenn sich Welt-Assets geaendert haben (der Updater laedt es nur bei geaenderter Signatur).
4. Smoke: Kopie der Console-Exe als `X.console.exe` neben `X.exe` + `--main-pack <pck> --headless --audio-driver Dummy --quit-after 200`, 0 Fehler; mit `TETHRA_worlds.pck` neben der Exe UND ohne (dann faellt WorldTheme auf galaxy zurueck).
5. `TETHRA_v1.zip`: nur den Eintrag `TETHRA.pck` ersetzen; `TETHRA_worlds.pck` kommt als eigene Datei dazu.
6. Commit, push, `gh release create vX.Y.Z release/TETHRA.pck release/TETHRA_worlds.pck TETHRA_v1.zip --title ... --notes ...` (Assets MUESSEN `TETHRA.pck` und `TETHRA_worlds.pck` heissen). Bei einem Release OHNE Welten-Aenderung das Welten-Paket trotzdem anhaengen (gleiche Datei), sonst fehlt es Neuinstallationen.

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

## v1.9.0 released (2026-11-07 abends)
Alles gemergt und released: 11 dunkle Welten (Beat-Vertrag + Komfort-Regeln docs/worlds/beat_contract.md), Noten in Weltfarbe, SV-Mod (x1,10, NF jetzt x0,50), Multiplayer (Live-Board, Kartenwahl wie Song-Browser mit eigenen Scores + Online-Download, Host geben, Mods im Raum, Platzierung), Online-Map-Browser (Genre/Sortierung), 2D-Modus (Balken/Kreis, Map-Hintergrund mit Blur + Deckkraft), Spurbreite 70-120 %, Welt-Vorschau in den Einstellungen, Welten-Paket getrennt (TETHRA_worlds.pck ~820 MB, Haupt-pck ~19 MB).
Offen / ungetestet:
- MP: Download-im-Raum + "Map laden" nie live getestet (Agent lief im Loop) -> Nutzer testet selbst.
- Welten-Paket-Download des Updaters gegen echtes GitHub-Release (HTTP Range ueber Redirect) erstmals mit v1.9.0.
- song_select laedt Welt-Texturen auch im 2D-Modus vor (unnoetig).
- Sturm: Seitenroehren folgen der Spurbreite nicht. Boss-Himmel: harter rosa Streifen oben (alt).
- 5 abgebrochene Downloads in maps/ (mirror_2538892, mirror_2556039, mirror_2597846, ...) - Nutzer entscheidet.
Nutzer-Vorgaben (dauerhaft): Fraktal-Stil = Referenz; nichts kippt/rollt; Drop nie zu stark; maximal scharf; extrem viele FPS; Neon nicht anfassen; Discord nicht; Tests lautlos, nur Monitor 2, Fenster mit timeout; Tests nicht unnoetig wiederholen; bis 10 Agents.

## Stand 2026-11-07 21:10 (Stopp: PC fror ein, Kernel-Speicherleck durch viele Prozessstarts -> NEUSTART)
Released + gepusht: v1.13.0 (Update-Loop-Fix: Welten-Paket ohne Skripte, mount replace_files=false; Digest-Vergleich). README neu + Repo-Beschreibung/Tags. In main (nicht released): i18n-game, i18n-mp (Englisch), Genre-Uebersetzung.
Offen, nach Neustart fortsetzen (Worktree-Commits "WIP (Stopp wegen RAM-Leck)"):
- i18n-core (opus): Rest Menues/Tutorial/Updater-Texte, translations/menus.csv, Screenshots --lang=en, tests/run_ui_format_tests.gd sprachfest. Handoff .git/warmd-handoff/i18n-core.md. Standardsprache Englisch.
- lobby-redesign (opus, Nutzer will das explizit): .warmd/tasks/lobby-redesign.md, neue Texte in translations/lobby.csv (danach in project.godot registrieren).
- note-colors: .warmd/tasks/note-colors.md (NoteColors + NoteColorPicker, translations/colors.csv registrieren, Picker ins Settings-Panel einbauen).
- Danach: Release v1.14.0 NUR TETHRA.pck hochladen; vorher Release-Tag "worlds" mit TETHRA_worlds.pck (+Zip) anlegen (siehe memory release-checks).

## v1.14.0 released (2026-11-07 nach Neustart)
Gemergt (72c97b6) und released: i18n-core (Menues/Tutorial/Updater Englisch, Standardsprache Englisch, Sprachwahl), lobby-redesign (Vollbild-Lobby im Song-Browser-Stil, translations/lobby.csv), note-colors (Notenfarben-Picker in den Einstellungen, translations/colors.csv).
Welten-Paket liegt jetzt im festen Release-Tag "worlds" (TETHRA_worlds.pck + TETHRA_v1.zip); normale Releases haengen nur TETHRA.pck an.
Offen: Raumkarten ohne Cover/Modus/Schloss (Raum-Ankuendigung in lobby.gd traegt nur Name/Spielerzahl/Code); team_board.gd/royale_board.gd nutzen noch gesperrte Titel; mit eingebautem Textur-Skin ersetzen Notenfarben die Skin-Farben nicht.

## Stand 2026-11-08 00:40 (v1.16.0)
Released: Orbit-Modus (Vorschau, Branches orbit-core+orbit-play gemergt), starkes SV (sv_mod Stufe Stark = Standard), davor v1.15.x (Skins exakt wie Original, Scroll Speed 1-40 wie lazer, Clip schnell + ffmpeg im Installer, GPU-Schutz, Turnier-Ueberarbeitung, Detail-Stats).
Offen: Orbit-Pause/Results/Einstellungen/Browser-Umschalter nie per Screenshot geprueft; SV-Stufe waehlbar machen (SvMod hat Normal/Stark intern); Score-Tausch im MP (Nutzer: erstmal egal); 2D-Optionen wie osu! (Richtung, HitPosition, Spaltenabstand, FadeIn/Hidden) noch offen.
Installer: tools/installer/tethra.iss, Setup im Release-Tag "worlds" (siehe memory release-checks).

## Stand 2026-11-08 ~03:40 (Nacht-Session, letztes Release v1.19.1)
Released diese Nacht (v1.14.0 -> v1.19.1): Installer TETHRA_Setup.exe (Release-Tag "worlds", ffmpeg dabei, Stage in release/stage), neues Logo + Identitaet (Graphit + Bernstein, ui_theme.gd), Lobby/Einstellungen/Ergebnis neu, Scores je Modus, 2D-Optionen wie osu!mania, Scroll Speed 1-40, starkes SV (Normal/Stark), Skins exakt wie osu!, Notenfarben neu (auch Built-in-Skins), GPU-Schutz, Clip schnell.
Orbit (eigener Modus, Prioritaet des Nutzers): osu!standard-Maps als Hauptquelle (POLAR), 4K als Fallback, Online-Browser Mania/Orbit, eigene Wertung CORE..MISS, eigenes Endbild, Tutorial, Replays + Clips, Multiplayer + Turnier (Smoke tools/mp_orbit_smoke.sh), 3D-Welten als Hintergrund, Einstellungsseite mit Live-Vorschau. QA: docs/modes/orbit_qa.md (Takt exakt, Bot 2,8 % Maus), Quellenvergleich docs/modes/orbit_sources.md.
Offen:
- warmd/orbit-stacks (Stapel-Verdeckung < 15 %, Bot-Kosten abwaegen) - falls nicht gemergt: Handoff .git/warmd-handoff/orbit-stacks.md.
- Smoke-Skript: Client-Pruefzeilen (Zwischenstand verpasst wegen --mp-back=10, Host beendet zu frueh) - Testablauf, kein Spielfehler.
- Social Preview docs/media/social_preview.png muss der NUTZER hochladen (GitHub Settings > Social preview).
- Installer enthaelt Spiel v1.18.0 (Updater holt Neues) - bei naechster Welt-/exe-Aenderung neu bauen.
- warmd-Luecken: fertige Tasks bleiben in .git/warmd-batch als Dateibesitzer (manuell Zeile loeschen), split vergibt nach batch-done belegte Worktrees, kein Befehl zum Verwerfen eines Tasks -> in warmd selbst beheben.
Nutzer-Regeln neu: max. 4 Agents; kein KI-Look; keine leeren Testfenster; Orbit hat Vorrang; fertige Updates sofort veroeffentlichen.

## Ende Nacht-Session 2026-11-08 04:30 (letztes Release v1.20.3)
Nach 03:40 noch released: v1.19.2 (Orbit-Stapel-Versatz 5/7/8, Verdeckung < 15 %, Bot besser), v1.20.0 (Orbit-Mods HD/FI/PR mit Score-Faktor, Orbit im Hauptmenue, Orbit-Rating im Profil), v1.20.1 (Profil-Schliessen-Knopf, Orbit-Texte via tr()), v1.20.2 (Orbit-Klaenge je Ring, Bogen-Ton), v1.20.3 (Orbit-Sterne im Song-Browser fuer 4K-Diffs, Cache user://orbit_stars.cfg). Installer TETHRA_Setup.exe im Tag "worlds" = v1.20.0. README: neues Orbit-Video (Welt-Hintergrund, Klaenge).
Offen fuer naechste Session:
- Orbit-Sterne im Browser auch fuer osu!standard-Diffs (heute nur 4K).
- warmd: "Godot ended without a result" beim Merge-Gate tritt sporadisch auf (Wiederholen hilft) -> in warmd selbst untersuchen; dazu die Batch-/Besitzer-Luecken (oben).
- Social Preview hochladen (Nutzer).

## Stand 2026-11-08 Vormittag (v1.20.5)
Released: v1.20.4 (ScoreStore Schema 3: alte Mania-Arcade-Scores vor v1.1.5 einmalig auf ScoreV1 umgerechnet, Bestwert/pp neu bestimmt, Fremd-Scores > Maximum beim Empfang umgerechnet; Orbit-Sterne im Browser auch fuer osu!standard), v1.20.5 (Online-Suche: catboy HTTP 403 -> Ausweich auf osu.direct).
Offen (Nutzer-Wuensche, Rueckfrage gestellt):
- Endbild "besser/genauer" (was genau fehlt, offen).
- Logo wirkt billig -> neues Logo (Richtung offen).
- Song-Import einfach (Datei-Dialog / osu!-Songs-Ordner?), 4K nur fuer Mania.
- Orbit verstaendlicher machen (Analyse an Nutzer: ein Ring Standard, Ring per Cursor-Abstand statt Taste, Toleranz-Keil sichtbar, Fehl-Feedback, ruhigerer Konverter). osu!tau ist sehr aehnlich.

## Stand 2026-11-08 Nachmittag (v1.23.0 released, main weiter)
- In main (nicht released): Mod-Zeile bricht um (Orbit-Panel lief unters Cover), Relay-Probe nur bei JSON-Raumliste.
- Laeuft: orbit-taktkreis (Orbit neu: Kreis = Takt, Zeiger, 2 Ringe = 2 Tasten, Zielen Pflicht, Optik wie osu! lesbar), online-sync (API final, Backfill alter Mania-Bestwerte).
- Pausiert: orbit-career, Branch warmd/orbit-career @0f968f8 (Logik + Tests fertig, UI/Browser/Hauptmenue offen; Tutorial ruft OrbitCareer.offer()). Erst nach neuem Orbit fortsetzen, project.godot: orbit_career.en.translation registrieren.
- Tutorial muss nach Taktkreis neu (Agent listet Inhalte im Bericht).
- Server (butzebot.com): Relay + API noch nicht live (Stand 13:55). Key per DM an Nutzer erwartet; min_version 1.23.1 setzen lassen. Infos fuer Kumpel: Artifact https://claude.ai/artifact/8iox8Vm6jXZtjyVyKPtAiW.
- warmd-Luecken (noch in warmd beheben): (a) Worktree eines laufenden Tasks (orbit-bahnen in audio-map) fiel beim naechsten split aus .git/warmd-batch (batch_prune?), Agent musste WARMD_BASE=1 nutzen; (b) `warmd batch-resume` nimmt alle alten Worktrees mit unmergten Commits als "offen" auf (16 statt 2) -> Marker wurde von Hand auf audio-map + login-start gesetzt.
- warmd: Automerge im Haupt-Checkout verwarf eine nicht committete Aenderung (orbit_view.gd, 08.11. 15:40) -> Merge muss bei uncommitted changes abbrechen statt zuruecksetzen.
- warmd (ernst): Der Automerge um 15:40 (career-browser, schon in main) setzte den lokalen main auf einen Stand VOR dem v1.25.0-Commit zurueck (lokal fehlte der schon gepushte Release-Commit; Rollback "bei rot"?). Rebase auf origin/main hat es repariert. Fix in warmd: Automerge darf nie hinter origin/HEAD zuruecksetzen, nie uncommittete Aenderungen verwerfen.

## Stand 2026-11-08 Abend (v1.25.2, alles released, keine Agents)
Released heute: v1.21-v1.25.2: Endbild-Details, Import + eigene Musik (Orbit), Server-Anbindung butzebot.com (Login beim Start, Online-Scores + Replays, Backfill alter Mania-Bestwerte mit combo_unknown, Online-Bestenliste, Profilbild, Chat F mit Map/Score-Karten), Relay-Multiplayer, Orbit neu (Bahnen: Kreis/Ellipse/Acht/Bluete, Spur A/B, Zielen Pflicht, Zuendschnur, 1 Takt sichtbar, Musik-Reaktion, Karriere), Fail-Analyse, Logo "Bahn", Mania-Holds wie osu! stable, Updater-Ausweichquelle (Branch dist, tools/publish_dist.sh nach jedem Release), Setup bei jedem Release neu.
Server: Infoseite fuer Kumpel https://claude.ai/artifact/8iox8Vm6jXZtjyVyKPtAiW, API-Doku vom Kumpel (TETHRA_API.md), min_version 1.24.1.
Offen: menschlicher Spieltest (Orbit-Spass, Chat/Replay/Avatar live, Fail-Bild, Karriere), README-Bild Online-Bestenliste, Social Preview in GitHub-Settings hochladen (Nutzer).

## Stand 2026-11-11 Abend (v1.26.0: Orbit Satelliten, Rally, Dirigent)
- Orbit komplett neu ("Satelliten", Spezifikation docs/modes/orbit_satellit.md, QA docs/modes/orbit_satellit_qa.md): Ziele auf dem Beat, Satellit eine Runde pro Beat, Pips = Runden, Taste A/B/Akzent + Zielen. Replay-Regeln 3, alte Orbit-Scores < 1.26.0 zaehlen online nicht (Server min_version 1.26.0).
- Neue Modi Rally (docs/modes/rally.md, scripts/rally/) und Dirigent (docs/modes/dirigent.md, scripts/dirigent/; Score 40 % Schlaege + 60 % Einsaetze, total_notes = Einsaetze, beats_hit/beats_total extra). Multiplayer, Replays, Online-Bestenlisten, Profil-Reiter je Modus.
- Demo-Videos aller 4 Modi: `bash tools/record_demo.sh <modus> <map-teil> <start_ms>` -> docs/media/<modus>.mp4 + _anim.webp. README mit Modus-Uebersicht.
- Offen/Ideen: Rally-Ansicht kennt die Beat-Laenge nicht (Uebernaechster Ring fest 500 ms); Mania hat keinen MP-Bot (Smoke SKIP); Audio-Sync der Demo-Videos nicht gemessen.

## Stand 2026-11-12 Abend (v1.27.0 released)
- 6 Modi: Mania, Orbit, Rally v2 (Kamera hinter dem Spieler, 3/4 Zonen, docs/modes/rally.md), Dirigent, Trace (docs/modes/trace.md), Rebound (docs/modes/rebound.md); Trace/Rebound werten mit ManiaCore.
- Empfehlungen "For you": scripts/library/recommender.gd, docs/recommend.md (Level = Sterne mit Rang B-A, Easy/Challenge/Push, Stil-Vorlieben).
- Tutorials fuer alle Modi (scenes/<modus>_tutorial.tscn), Tastenbelegung aller Modi in Settings > Controls, Modus-Icons assets_game/icons/modes/*.svg (ModeBadge).
- Map-Hintergrund Orbit/Rally/Dirigent: MapBackdrop (Settings.modes_bg_blur/modes_bg_dim); Mania unveraendert.
- Server: min_version 1.27.0, Modi trace/rebound neu, Relay mit neuer pck neu starten (Raumart in /rooms).

## Stand 2026-11-12 spaet: Neustart wegen RAM-Leck (nur 59 MB frei), alle Agents gestoppt
In main (nicht gepusht, nicht released; letztes Release v1.27.0): Trace komplett ausgebaut (eigene Pfeiltasten Settings.trace_keys, Anti-Mash "Wrong turn" in scripts/trace/trace_rules.gd, Optik/Zeitraffer, TracePicture Speichern/Chat, TraceMods MR/HD/SS, TraceStars, Trace-QA, Trace-Clips, Trace-Versus MP, Daily Trace), Browser nutzt Modus-Sterne in allen 6 Modi (Rally/Dirigent echte Chart-Sterne, Cache v2), Ergebnis Trace/Rebound zeigt Punkte, Clips starten Szene je Modus.
warmd: v0.4.45 installiert (~/.local/bin im PATH erst in neuen Shells; sonst `export PATH="$HOME/.local/bin:$PATH"`).

Offen, in dieser Reihenfolge nach dem Neustart:
1. anti-mash (Branch warmd/anti-mash, Handoff .git/warmd-handoff/anti-mash.md): Rally/Orbit/Dirigent-Tests nachpruefen, docs/anti_mash.md (Rebound 76->26 %, Dirigent 100->67 % schon gemessen), MP-Smokes, warmd check, finish, dann mergen.
2. chat-score-card (warmd/chat-score-card, Handoff vorhanden): Tests gruen (zuletzt 175 ok / 43 rot vor Layout-Fix), Screenshot, check, finish, mergen.
3. Danach (Dateien frei, wenn 1. gemergt): .warmd/tasks108.txt rebound-look (Hold-Baelle eigene Farbe/Form sofort erkennbar, klareres Design), .warmd/tasks110.txt orbit-clarity (unklare Orbit-Momente) + orbit-timing (Fenster wie osu!std, Satellit langsamer, Regeln v4 -> Server min_version beim naechsten Release).
4. warmd-Fix offen (Repo Desktop/warmd, Branch fix/runner-fail-reason, ungeprueft): FAIL-runner-Zeile mit Exit-Code/Timeout-Grund, Runner-Timeout unter Last; Anlass: tests/run_mastering_tests.gd faellt im Gate nach "ALL OK" zufaellig durch.
5. Daily-Trace-Texte noch deutsch als Quelle (sollten englisch sein), FEHLKNICKE in Live-Leiste uebersetzen.
6. Dann Release v1.28.0 (Server: trace/rebound Regeln, Orbit v4, Daily-Text docs/server_daily.md, Relay neu).

## Stand 2026-11-12 nachts (v1.28.0 released, PC danach heruntergefahren)
Released: Trace ausgebaut (eigene Pfeiltasten, Wrong turn, Bild der Runde, Mods MR/HD/SS, TraceStars, QA, Clips, Versus, Daily Trace), Anti-Mash in Rebound/Rally/Orbit/Dirigent, Orbit Regeln v4 (osu!std-Fenster, langsamerer Satellit, laps_eff) + Klarheit (HOLD, Stapel x2/x3, Countdown, Kombo blendet aus), Rebound Hold-Baelle gold, Browser mit Modus-Sternen, Chat-Score-Karte neu, Trailer (docs/media/trailer.mp4, tools/make_trailer.sh, Release-Asset TETHRA_Trailer.mp4).
Server: min_version 1.28.0, Orbit/Trace-Scores < 1.28.0 raus, Relay neu, Daily-Vorschlag (docs/server_daily.md).
Offen/Ideen: Orbit-Pips-Aenderung durch laps_eff (weniger Runden) vom Nutzer bestaetigen lassen; Orbit-Accent-Screenshot nie mit Zielen erwischt; Rally/Orbit/Dirigent-HUD ohne --nohud im Trailer; Lizenzdatei fuers Repo fehlt (nicht "open source" schreiben).
warmd v0.4.48 (~/.local/bin; in alten Shells `export PATH="$HOME/.local/bin:$PATH"`).

## Stand 2026-11-13 Mittag (v1.29.0 released)
Released: neuer Look fuer Orbit/Rally/Dirigent/Rebound (Buehne, Objekte mit Tiefe, Frueh/Spaet-Marke), Hauptmenue neu (Modus-Kacheln mit gezeichneten Spielszenen statt Icons), MapBackdrop ruhiger Verlauf, ein Ergebnis-Bildschirm fuer alle Modi (ResultsScreen + Details-Reiter je Modus, skaliert), Lobby/Pause/Browser poliert, Gameplay-Abstimmung (docs/modes/gameplay_tune.md): Replay-Regeln Orbit 5, Rally 4, Dirigent 3, Rebound 3.
README-Videos laufen ueber GitHub Pages (docs/watch.html?v=<name>, Pages aus main:/docs).
Server: min_version 1.29.0, Scores < 1.29.0 der vier Modi raus, Relay neu (Artifact aktualisiert).
Offen: menschlicher Spieltest der neuen Regeln; Settings-Seite unveraendert (nur angesehen); Lobby/Fail-Bilder Dirigent+Trace/1440p nie selbst geprueft; docs/anti_mash.md nennt Rebound-Spam 25,9 % (jetzt 27,6 %); Uebersetzungs-Keys fuer "Picture"/"In den Chat senden" im Ergebnis fehlen (UiTheme.is_german()).
Agents liefen mit model=fable (Opus/Sonnet-Subagents: API 403 Cloudflare).

## Stand 2026-11-13 Abend (v1.31.0 released)
- v1.30.0: faire Sichtzeit in allen Modi (docs/qa/approach_audit_*.md), Dirigent Regeln 4 (250 ms), SV-Faktor 1,1 nur Mania, neue Medien + Website docs/index.html (SEO/OG/JSON-LD), Repo-Topics/Beschreibung.
- v1.31.0: Mania 2D Pop-in (Intro/Break-Ring neben dem Feld, Spawn an sichtbarer Kante bei stage_scale > 100 %, --debug-popin), Trace-Tutorial/Clips, Einstellungen neu, Uebersetzungen (translations/polish.csv).
- SV-Mod und Map-SV bleiben wie sie sind (Nutzer: "muss so sein").
- Server-Artifact aktuell bis v1.30.0; v1.31.0 ohne Server-Aenderung (nur Relay neu).
- Laeuft: qa-live (Pause/Break/Retry/Fail/Replay/Mods/MP je Modus per Lauf, Bericht docs/qa/live_qa.md).
- Social Preview docs/media/social_preview.png muss der Nutzer in den GitHub-Settings hochladen.
- warmd-Luecke: zweiter `warmd split` waehrend ein Batch laeuft -> beim Ende des zweiten Batches wurde der noch laufende Task des ersten (mania-2d-popin) zu frueh gemergt ("OK batch ended"). In warmd beheben.
- ISCC aus Git Bash: /D-Schalter werden zu Pfaden umgeschrieben -> ISCC ueber PowerShell aufrufen.

## Stand 2026-11-13 Nacht (v1.32.0 released, Limit-Stopp)
- v1.32.0 released: Countdown-Ring verdeckt keine Noten in Mania 3D/Orbit, Escape nach Chat, Ergebnis-Skriptfehler; Live-QA aller Modi (docs/qa/live_qa.md, tests/live_qa.sh).
- Server-Artifact aktuell bis v1.32.0 (min_version bleibt 1.30.0, nur Relay neu). Kumpel-Text wurde dem Nutzer gegeben.
- warmd v0.4.49: wartende Agents (Hintergrundlauf) zaehlen nicht mehr als fertig, kein vorzeitiger Merge. Restluecke: per SendMessage fortgesetzter, schon fertig eingetragener Agent wird nicht wieder offen; batch-resume nimmt alte Worktrees als offen (andere Ursache).
- GESTOPPT (Limit), Task-Dateien unter .warmd/tasks/ (tutorials-v2: noch kein Commit, neu beginnen; mp-all-modes: 1 Commit 20f9f04, Smoke-Skripte + Mania-Bot, ungeprueft):
  - tutorials-v2 (.warmd/tasks122.txt): Tutorials aller Modi an Regeln Orbit 5/Rally 4/Dirigent 4/Rebound 3 + Anti-Mash + neuen Look anpassen, en+de.
  - mp-all-modes (.warmd/tasks122.txt): --mp-bot fuer Mania (lief gerade verbose), Rebound im Smoke, Relay-Smoke alle 6 Modi, ObjectDB-Leak beim Beenden.
  Fortsetzen: Agent je Task mit model=fable (Opus/Sonnet-Subagents hatten API 403), Prompt "Read .warmd/tasks/<task>.md, git log im Worktree, weiter ab WIP". Batch-Marker fehlt evtl. -> nach Ende von Hand mergen: WARMD_BASE=1 warmd merge warmd/<task>.
- Nutzer-Vorgaben neu: Regeln immer aenderbar (memory feedback-rules-change); SV-Mod/Map-SV bleiben wie sie sind; Social Preview docs/media/social_preview.png selbst hochladen.

## Stand 2026-11-13 ~21:00 (letztes Release v1.34.0, Neustart)
Released heute Abend: v1.33.0 (Mania Max-pp = SS mit allen MAX/n_geki, Cache maxpp_v2; Solo neben offenem Raum zaehlt nicht als MP: Lobby.in_round()), v1.34.0 (Collections: Filter blenden nichts aus, Neu/Umbenennen/Loeschen mit Papierkorb, .bak vor jedem Speichern; Chat: Bot-Markdown + Map-Links als Karten, docs/net/bot_links.md).
In main, NICHT gepusht, NICHT released (Merge-Gate wurde beim Neustart abgebrochen, Tests der Branches waren gruen; erster Gate-Lauf scheiterte nur am bekannten Wackel-Test run_mastering_tests.gd):
- e070b3c Merge for-you-v2: Collections je Modus, "For you" mit Stilprofil, Grund je Vorschlag, "Mehr anzeigen", Online-Gruppe (Download/Vorhoeren der Online-Kacheln nie live geklickt; neue Texte als REC_DE/COLL_EN im Code statt translations/).
- 090b2c0 Merge trace-look-v2: Trace ohne Ringe (nur Zielring am naechsten Knoten), schraeger Boden, durchgehende Bahn, Beat-Lichtwelle, Kiai bernstein.
  -> Zuerst: WARMD_BASE=1 warmd check im Haupt-Checkout, dann push + Release v1.35.0.
Offene Branches (WIP, gestoppt):
- warmd/campaign (Worktree .warmd-worktrees/rhyg/campaign, 4 Commits): Kampagne je Modus, Mania 13 Kapitel/78 echte 4K-Maps, andere Modi je 1 Kapitel, data/campaign.json, scenes/campaign.tscn, scripts/campaign/*, docs/campaign.md, docs/net/campaign_server.md. Agent war mitten im Fix "Welt-Zwang darf nicht in settings.cfg haengen bleiben" (roter Test geschrieben, Fix fehlt). Danach: echter Stufenlauf per Harness, Stufe/Ergebnis-Screenshots, warmd check, finish. Handoff .git/warmd-handoff/campaign.md.
- warmd/sv-start-popin (2 Commits): Ursache gefunden "SyncClock: Ladezeit nach play() frisst den Vorlauf" (Repro: maps/mirror_2141771.osz, sath4 <3#006 [Recollectia, w/ [-SVzzZ-]], 2D, --debug-popin -> finds=9, erste Noten erst 528 ms vor Treffer). Fix/Test pruefen, Stichprobe 20 SV-Maps, warmd check, finish.
- warmd/mp-all-modes, warmd/tutorials-v2: gedroppt (spaeter neu starten, Tasks .warmd/tasks122.txt).
Nutzer-Entscheidungen: SV-Mod/Map-SV bleiben wie sie sind; Regeln immer aenderbar; alle 6 Modi bleiben (Loeschen abgesagt); Kampagne je Modus (Mania zuerst), Ranglisten der Teilnehmer.
Offene Fragen an den Nutzer: Trace auf mitfahrende Kamera (nur kommendes Stueck sichtbar, wie im Groove-Coaster-Video, keine Kopie) umbauen? Gewaehlte Mania-Varianten aus TETHRA_Plan_Mania_Varianten.pdf: 3 Uebungsmodus, 4 Minen, 6 echte 7K-Maps, 10 Sudden Death/Perfect, 14 Marathon mit DJ-sauberen Uebergaengen (gleiche Schwierigkeit, Mashup), 15 Turbo -> bauen. 30 gameplay-veraendernde Ideen wurden genannt (Nutzer hat noch nicht gewaehlt).
Server: Artifact aktuell (inkl. Bot-Link-Wuensche); PDF fuer Server-Owner: Desktop/TETHRA_Server_Update_seit_11.11.pdf. Kampagnen-Gesamtrangliste braucht neuen Endpunkt (docs/net/campaign_server.md im campaign-Branch) -> nach Merge ans Artifact.
Offset-Frage Kollege (-31 ms): kein Rechenfehler, Godot meldet nur 10 ms Ausgabelatenz; Vorschlag "Offset aus letztem Lauf uebernehmen" offen.
Agents: model=fable (Opus/Sonnet-Subagents hatten 403). Max ~3 Agents gleichzeitig.

## Stand 2026-11-13 ~21:05 (v1.35.0 released)
- v1.35.0 released + gepusht: for-you-v2 (Stilprofil, Grund je Vorschlag, "Mehr anzeigen", Online-Gruppe, Collections je Modus) und trace-look-v2. Gate im Haupt-Checkout gruen (513 s), Paket-Version per Start geprueft, Smoke 0 Fehler, dist gespiegelt, TETHRA_Setup.exe im Tag "worlds" neu (v1.35.0). Keine Server-Aenderung.
- Laeuft (Agents, model=fable, ab WIP): warmd/campaign (Welt-Zwang-Fix, Stufenlauf, Screenshots) und warmd/sv-start-popin (Fix pruefen, 20er-Stichprobe). Beide standen zuletzt in `warmd check`. Danach von Hand mergen: WARMD_BASE=1 warmd merge warmd/<task>, dann Release v1.36.0; Kampagnen-Endpunkt (docs/net/campaign_server.md) ans Server-Artifact.
- Weiter offen wie im Abschnitt davor: Online-Kacheln von "For you" nie live geklickt; mp-all-modes, tutorials-v2 neu starten; Nutzer-Fragen (Trace-Kamera, Mania-Varianten 3/4/6/10/14/15, 30 Ideen, Offset-Uebernahme).

## Stand 2026-11-13 ~21:40 (v1.36.0 released; Name jetzt OMEN; Auto-Mapper 4K laeuft)
- v1.36.0 released + gepusht + dist + Setup: Kampagne (warmd/campaign), sv-start-popin, Vorlauf-Deckel (ManiaCore.MAX_SV_LEAD_EXTRA_MS = 5000), pp fuer Mitspieler-Scores (ScoreStore.fill_others_pp aus Online-Rangliste, sonst "≈ pp" aus Max-pp x Acc-Anteil; die ≈-Zeile wurde nie im Fenster angesehen).
- NAME: Das Spiel heisst OMEN (Nutzer-Entscheidung, alles auch technisch; memory name-omen). Agent auf warmd/rename-omen (Worktree rename-omen, Auftrag .warmd/tasks/rename-omen.md). Danach durch den Haupt-Agent: mergen, `gh repo rename OMEN`, Release mit beiden Asset-Namen (OMEN.pck + TETHRA.pck, solange alte Installationen leben), Setup OMEN_Setup.exe, Pages-URL/README pruefen. Server soll wieder `omen` heissen (zwei Schritte, steht im Server-Artifact): Client erst umstellen, wenn der Server `omen` zusaetzlich anbietet (mit Rueckfall auf `tethra`).
- AUTO-MAPPER 4K (Nutzer: mp3 reinziehen -> perfekte 4K-Maps in mehreren Schwierigkeiten, exakt im Takt, auf Bass/Instrumente/Stimme/Schlagzeug achten, Cover als Vorschaubild): Spec docs/automap/spec.md (Module, Schnittstellen, Ziel-Tabelle). Batch .warmd/tasks130.txt, 5 Agents (model=fable): am-grid, am-features, am-chart, am-pipeline, am-bench. Danach: der Reihe nach mergen (WARMD_BASE=1 warmd merge warmd/<task>), Platzhalter tests/automap_stubs loeschen, am-bench gegen die echten Module laufen lassen + abstimmen (tools/automap_tune.gd), Ziel-Tabelle in docs/automap/report.md pruefen, dann die 3 Songs in "own songs/" erzeugen (landen nur lokal in maps/) und per Hoerprobe (--click) + Autoplay pruefen. "own songs/" ist gitignoriert, hat .gdignore und ist vom Export ausgeschlossen (war beim ersten v1.36.0-Bau im pck: 41 statt 22 MB, vor dem Upload bemerkt und behoben).
- KAMPAGNE (Nutzer-Kritik an v1.36.0): beachtet 2D/3D und eigene Welt nicht, Ansicht "optisch sehr schlecht", will Song-Bilder als Vorschau. Agent auf warmd/campaign-look (Auftrag .warmd/tasks/campaign-look.md): Einstellungen gelten, Welt-Zwang raus, Ansicht neu.
- Server-Artifact aktuell (Version 14): Endpunkt-Wunsch GET /scores?mode&md5&player (pp alter Laeufe), Kampagnen-Endpunkte, Umstellung auf omen. Text fuer den Kumpel wurde dem Nutzer gegeben (ohne den omen-Teil in der Schritt-Form; Artifact ist massgeblich).
- Platte: C: war voll (4 GB). .godot-Caches von 9 alten Worktrees geloescht (22 GB frei). Rund 150 alte Worktrees unter .warmd-worktrees/rhyg (41 GB) koennten ganz weg: Nutzer fragen.
- Alle Merges von Hand: WARMD_BASE=1 warmd merge warmd/<task> (Gate ~9 min, Haupt-Checkout solange nicht anfassen).

## Stand 2026-11-13 ~23:05 (Limit-Stopp, Nutzer hat nur noch ~7 %)
Released heute: v1.37.0 "OMEN" (Repo heisst Vyrenbusiness-source/OMEN, Pages /OMEN/, Release-Assets OMEN.pck + gleiche Kopie TETHRA.pck, dist gespiegelt, OMEN_Setup.exe im Tag worlds; Installer nie ausgefuehrt). warmd v0.4.50 (unreferenzierte untracked Dateien loesen keinen Voll-Testlauf mehr aus).
In main, NICHT released: 6bb6c9a Merge campaign-look-r1 (Kampagne: eigene Welt/Mods gelten, Ansicht neu mit Covern, Ziele im HUD). Gate lief beim Stopp. -> Release v1.38.0 (Ablauf wie v1.37.0: CURRENT_VERSION, --export-pack "Windows" release/OMEN.pck, Kopie TETHRA.pck, Smoke, gh release create vX OMEN.pck TETHRA.pck, bash tools/publish_dist.sh, Setup via PowerShell ISCC tools/installer/omen.iss).
Laufende/gestoppte Agents (Worktrees unter .warmd-worktrees/rhyg, alle mit WARMD_BASE=1 arbeiten, nie warmd batch-resume):
- campaign-look (nach 7266b89): Skip-Pruefung je Kapitel (Boss eines spaeteren Kapitels, bestanden mit >= 99 % Accuracy, schaltet Kapitel frei; Einstufung am Anfang) + Restpunkte (Orbit-HUD-Lage, leere Rangliste, Ruck, Cover gesperrt, Doppelklick, Online-Vorhoeren).
- am-integrate (Branch warmd/am-integrate, von main + am-grid-r1 + am-features-r1 + am-chart-r2 + am-pipeline-r1, Stubs geloescht): Kette mit echtem Audio messen (tools/automap_bench.gd --mapper new), Uebergaenge fixen, tools/automap_tune.gd -> data/automap/params.json, 3 Songs aus "own songs/" nach maps/ erzeugen + Hoerprobe (--click) + Autoplay-Screenshot. Danach mergen + Release (Auto-Mapper 4K: Musik reinziehen -> 5 Diffs).
- am-grid Runde 2 (Worktree am-grid): Halbschlag-Versatz, Tempowechsel (lokale Verfolgung), Taktanfang (Chroma). Stand Runde 1: Tempo 89 %, mit Alternative 99 %, Offset Median 3,4 ms, Tempowechsel 10 %, Downbeat 74 %. Danach in am-integrate nachziehen.
- Mania-Varianten (Nutzer-Wahl aus Desktop/TETHRA_Plan_Mania_Varianten.pdf, Regeln .warmd/tasks/mania-variants.md): mv-rules (SD/PF + Minen), mv-keys (5K-7K), mv-tempo (Rate-Grundlage + Uebungsmodus + Turbo), mv-marathon (DJ-Uebergaenge). Je fertigem Paket sofort mergen + releasen (Nutzer: alles Fertige direkt updaten).
Fortsetzen: je Worktree `git log main..HEAD` + `.git/warmd-handoff/<task>.md` falls vorhanden; Agent mit model=opus "Read .warmd/tasks/<task>.md (bzw. mania-variants.md), continue".
Server-Artifact v15 aktuell (Relay mit OMEN.pck neu starten, Probe /panel-api/omen/auth/me). Neue Server-Felder kommen mit Varianten (SD/PF/MN, Tastenzahl, Turbo/Marathon-Schluessel) -> ins Artifact.
Offen Nutzer: Social Preview mit OMEN erzeugen (docs/media/social_preview.png, og_image.png, ui_menu.webp) und der Nutzer laedt hoch; Trailer bleibt.
