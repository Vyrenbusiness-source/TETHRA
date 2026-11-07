# Release-Probelauf v1.9.0 (main aad14e3, ohne Veroeffentlichung)

## Ergebnis
- `--import`: ok. Parse-Check (`--quit`): 0 SCRIPT ERROR / Parse Error / SHADER ERROR.
- `--export-pack "Windows" release/TETHRA.pck`: ok, **1 374 437 396 Byte = 1,37 GB** (vorher ~7,8 MB). Ziel 150 MB um das 9fache ueberschritten.
- Smoke (Kopie von Godot-Exe + Console-Wrapper als `TETHRA.exe`/`TETHRA.console.exe`, `--main-pack`, `--headless --audio-driver Dummy --quit-after 200`): 0 Fehler/Warnungen, Ausgabe `MainMenu Headless OK`.
- Erst-Import 8192er-Texturen: ca. 6 min, `.godot/imported` 2,5 GB. Export dann ca. 1 min.
- Der Wrapper `*_console.exe` braucht den Namen `X.console.exe` neben `X.exe`, sonst "Invalid wrapper executable name" (HANDOFF-Smoke-Schritt entsprechend lesen).

## Blocker vor dem Release
- `assets_game/themes/obsidian/obsidian_waves.webp` ist in main **0 Byte** (valid=false): `load()` meldet "Resource file not found", die Obsidian-Vorschau/-Welt bekommt keine Duenung. Gehoert world-obsidian.

## Groesse je Welt (pck = importierte BPTC-Daten, Quelle = WebP)
Jede 8192x4096-Textur: BPTC + Mipmaps = 44,7 MB (Datei = VRAM, kein Zusatz-RAM nach dem Upload).

| Welt | Texturen | pck MB | Quelle MB |
|---|---|---|---|
| boss | 5 | 223,7 | 2,8 |
| nerve | 5 | 223,7 | 8,0 |
| rift | 4 | 179,0 | 6,0 |
| aurora | 4 | 156,6 | 2,8 |
| monolith | 4 | 134,7 | 4,8 |
| fractal | 3 | 134,2 | 2,6 |
| eclipse | 3 | 111,8 | 4,1 |
| abyss | 3 | 100,7 | 1,5 |
| obsidian | 4 (2 gueltig) | 89,8 | 0,6 |
| neon | 1 | 1,3 | 0,3 |
| Rest (assets_game) | 39 | 17,8 | 5,4 |
| Summe | | 1373 | |

storm/singularity sind noch nicht in main. Mit ihnen wachsen pck und Download weiter (ca. +100 bis +200 MB je Welt).

## VRAM/RAM je Welt beim Map-Start
- VRAM = pck-Spalte der aktiven Welt: **90 bis 224 MB**, schlimmster Fall boss/nerve 224 MB (5 x 44,7). RAM: Godot behaelt bei CompressedTexture2D keine CPU-Kopie, nur Streaming-Puffer beim Laden.
- Die Godot-Monitore (`RENDER_VIDEO_MEM_USED`) hinken beim Freigeben hinterher (negative Deltas), deshalb zaehlt die Dateigroesse als Referenz. Beim Welt-Wechsel muss die alte Welt freigegeben sein, sonst Spitze 2 Welten (bis ~450 MB).
- Karten mit 6 GB VRAM: ok. 4 GB: eng zusammen mit Sky, Schatten, Framebuffer.

## Ladezeit der Welt-Texturen (RTX 5070, Fenster, `load()` im Hauptthread, Dateien im OS-Cache)
| Welt | Texturen | load ms |
|---|---|---|
| abyss | 3 | 45 |
| aurora | 4 | 47 |
| boss | 5 | 76 |
| eclipse | 3 | 33 |
| fractal | 3 | 39 |
| monolith | 4 | 119 |
| neon | 1 | 60 |
| nerve | 5 | 70 |
| obsidian | 3 | 95 |
| rift | 4 | 49 |

- 33 bis 119 ms im Hauptthread = 2 bis 7 verlorene Frames bei 60 fps: spuerbarer Hitch, wenn es beim Map-Start im Spielthread passiert.
- Warm. Kalt von der Platte (HDD/erster Start) liegen 224 MB bei 150 MB/s (HDD) bei ca. 1,5 s, bei SATA-SSD (500 MB/s) ca. 0,45 s, NVMe unter 0,15 s. Die Zeiten oben sind also Untergrenzen.
- Abhilfe ohne Qualitaetsverlust: im Songauswahl-Screen beim Fokus auf eine Map `ResourceLoader.load_threaded_request()` fuer die Welt-Texturen (Kosten: Laden laeuft im Hintergrund, Hitch 0). Beim Map-Start nur `load_threaded_get()`.

## Vorschlag (Zahlen, keine Assets geaendert)
Annahme: 30 Welt-Texturen. 8192x4096 = 44,7 MB, 4096x2048 = 11,2 MB, 2048x1024 = 2,8 MB (BPTC + Mips).

| Variante | pck gesamt | VRAM schlimmste Welt |
|---|---|---|
| Ist: alles 8192 | 1,37 GB | 224 MB |
| Nahe Ebene je Welt 8192, Rest 4096 (9 x 44,7 + 21 x 11,2) | ca. 0,66 GB | ca. 90 MB |
| Alles 4096 | ca. 0,36 GB | ca. 56 MB |
| Alles 4096, ferne Sterne/Dunst 2048 | ca. 0,30 GB | ca. 50 MB |
| Alles 2048 | ca. 0,10 GB | ca. 14 MB |

- 150 MB erreicht man nur mit 2048er Texturen. Das widerspricht "maximal scharf". Realistisch: Ziel "unter 700 MB" (Mischvariante) oder die Schaerfe behalten und den Updater/Download entlasten (unten).
- Quelle WebP verlustbehaftet ist hier kein Hebel: Quellen sind 0,5 bis 8 MB. Die Groesse entsteht aus dem Import. Qualitaet 90+ ist ok, kostet nur Repo-Platz.
- BPTC vs lossless: Lossless (RGBA8) waere 8192x4096x4 = 134 MB + Mips = 179 MB je Textur, 4x groesser und 4x mehr VRAM. BPTC bleibt. Das pck wird nicht weiter komprimiert (BPTC ist schon dicht), ZIP bringt wenig.
- Mipmaps: Ebenen die nur weit weg/unscharf sind brauchen kein 8192 (ab ca. 1/4 Bildschirmbreite entscheiden die Mips).
- Welt-Texturen aus dem Hauptpaket in ein zweites Paket `TETHRA_worlds.pck` (laedt `ProjectSettings.load_resource_pack`). Dann laedt ein normales Update nur ~20 MB statt 1,37 GB.

## Updater (`scripts/net/updater.gd`)
Geprueft gegen ein 1,4 GB pck:
- Fortschritt: ok, `get_downloaded_bytes()/get_body_size()` (Fallback Asset-size), Toast + Menue.
- Chunk 4 MB, Threads an: ok. Datei wird direkt in `TETHRA.pck.new` geschrieben (kein RAM-Puffer).
- Timeout: war 300 s Gesamtzeit. 1,4 GB sind bei 40 Mbit/s ca. 280 s, bei 20 Mbit/s ca. 560 s: **Abbruch bei langsamer Leitung**. Geaendert: Gesamt-Timeout aus (`0`), dafuer Stillstands-Wache `STALL_SECONDS = 45` (kein Byte seit 45 s: abbrechen, Backoff-Retry).
- Tausch: `copy /y` + `del` kopierte 1,4 GB bei geschlossenem Spiel (Sekunden bis Minuten Wartezeit). Geaendert auf `move /y` (gleiche Platte: Umbenennen, sofort).
- Groessenpruefung (`size_ok`) und GDPC-Magic bleiben: ok. GitHub-Asset-Limit 2 GiB: pck + Welten von storm/singularity duerfen 2 GiB nicht erreichen (jetzt 1,37 GiB).
- **Offen: kein Resume.** Fehler loescht das Teilstueck, naechster Versuch beginnt bei 0 (1,4 GB je Versuch). `HTTPRequest` kann nicht anhaengen. Resume braucht Range-Requests in Teilen (z. B. 64 MB-Segmente in `.part`-Dateien). Besser: Welten-Paket trennen (siehe oben), dann ist ein Neustart des Downloads billig.
- Offen: kein Platzcheck vor dem Download (1,4 GB frei auf dem Spielelaufwerk, plus 1,4 GB fuer das alte pck waehrend `.new` liegt = 2,8 GB).

## Nicht gemacht (laut Auftrag)
Kein `gh release`, kein Tag-Push, `CURRENT_VERSION` unveraendert (1.8.1), keine Assets geaendert, `TETHRA_v1.zip` nicht gebaut.
