# Clip-Export: Geschwindigkeit

Messung: `tools/clip_bench.sh` (zweiter Godot-Prozess wie ClipExporter), Test: `tests/run_clip_tests.gd`.
Rechner: RTX 5070, Replay-Clips aus der Bibliothek. Wall = Klick bis fertige Datei.

## Vorher (1080p-Fenster, 60 FPS, AVI/MJPEG)
| Clip | Film | Wall | Tempo | Datei |
|---|---|---|---|---|
| 27 s-Replay | 32 s | 75 s | 43 % Echtzeit | 107 MB |
| 2-min-Replay | 124 s | 279 s | 44 % Echtzeit | 447 MB |

## Wo die Zeit hingeht
- Start + Map laden: ca. 3 s (Vorwaermen lohnt nicht).
- Pro Frame ca. 12-14 ms, unabhaengig von FPS/Renderer (Mobile = Forward+): Readback + MJPEG-Kodierung (CPU, 1 Thread, Prozess ~92 % einer CPU). Rendern ist nicht der Engpass.
- Ein 1080p-Fenster kostet 2,7x mehr als 720p (74 s vs 27 s bei 60 FPS), das Video ist trotzdem 1280x720 (Projekt-Viewport). `--resolution 1920x1080` brachte also nur Kosten.
- Film-Dauer schwankt je nach Tempo: der Quit-Timer in GameSession (3 s) laeuft in Echtzeit, bei schnellem Rendern sind das ca. 8 Film-Sekunden Results-Bild.
- `editor/movie_writer/mjpeg_quality` (override.cfg und project.godot) hatte in 4.7 keine Wirkung auf die Dateigroesse.

## Nachher (720p-Fenster, 30 FPS, MP4 per ffmpeg)
| Clip | Film | Wall | Tempo | Datei |
|---|---|---|---|---|
| 27 s-Replay | 41 s | 17 s (+2 s MP4) | 256 % Echtzeit | 10 MB MP4 |
| 2-min-Replay | 133 s | 56 s (inkl. MP4) | 2,4x Echtzeit (Wall = 42 % der Filmdauer) | ca. 30 MB MP4 |

Schritte einzeln (27 s, 60 FPS): 1080p 74 s -> 720p 27 s; 720p 30 FPS 17 s. MP4: libx264 ultrafast 2,0 s, nvenc 1,6 s fuer 41 s Film (AVI 83 MB -> MP4 9,9 MB).
Von 279 s auf 56 s (5x) fuer den 2-min-Clip. Ziel 1/3 Echtzeit (44 s) knapp verfehlt: 42 %.

## Audio-Sync
Ton- und Bilddauer im Ergebnis identisch (ffprobe: 132.8 s / 132.8 s; AVI 1990400 Samples = 41.4667 s = 1244 Frames bei 30 FPS). Die MovieClock in `sync_clock.gd` ist sample-genau und erkennt die FPS automatisch (auch 30). Kein Eingriff noetig.

## Offen (Hauptagent, nicht meine Dateien)
1. `scripts/game_session.gd` `_process`: Quit-Verzoegerung `CLIP_QUIT_DELAY` per Frames statt `Time.get_ticks_msec()` (z. B. 3 s * FPS Frames). Spart ca. 3 s Wall und ca. 8 s Results-Bild im Film; Film-Laenge wird reproduzierbar. Damit sollte der 2-min-Clip unter 1/3 kommen. Ebenso Lead-In/Countdown im Clip-Modus verkuerzen.
2. `scripts/gameplay3d/mania_3d.gd` `_on_results_clip`: `_clip_exporter.progress_info.connect(func(f, eta, phase): _results_screen.show_clip_progress(f, eta, phase))` statt des `progress`-Toasts; Exporter an `get_tree().root` haengen (sonst bricht das MP4-Umkodieren ab, wenn man die Szene verlaesst); Ergebnis-Pfad ist jetzt `.mp4` (finished liefert ihn), der uebergebene `.avi`-Pfad nur Basis.
3. Optional Settings-Auswahl: `ClipExporter.fps` = `PRESETS["fast"]` (30) oder `["smooth"]` (60, ca. 1,8x langsamer).
4. ffmpeg: neben der Exe als `ffmpeg.exe` mitliefern, sonst bleibt das AVI (grosse Datei).
5. Neue Uebersetzungen: `translations/clip.csv` (registrieren). `show_toast` nutzt nun `tr("Ordner öffnen")` (Key existiert in game.csv/mp.csv).
