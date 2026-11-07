# Welten-QA im Spiel (main @aad14e3)

Messung: Godot 4.7, `song_select.tscn --mania --autoplay --shot --theme=<welt>` (1280x720-Fenster), je Welt 3 Bilder:
ruhig auf dem Beat (20 s), ruhig zwischen den Beats (+150 ms), Drop/Kiai auf dem Beat (60 s). Map: namirin - Mizutamari Tobikoete, Beginner, 194 BPM.
FPS und Ladezeit: `--perf --disable-vsync --print-fps` (10 s Gameplay, gleiche Map, Dummy-Audio). Der PC ist verrauscht (andere Agenten laufen parallel): FPS-Einzelwerte schwanken ~2x, daher Frame-Mittel als Richtwert.
Neon, Storm, Singularity, Obsidian nicht geprueft (in Arbeit / gesperrt).

| Welt | Lesbarkeit | Beat | Drop | FPS (Frame-Mittel) | Ladezeit (SPIELEN -> 1. Frame) | Probleme |
|---|---|---|---|---|---|---|
| galaxy (Referenz) | gut | ja | ok | ~310-430 (2.3-3.2 ms) | 740-810 ms | - |
| boss | sehr gut, rote Strecke, gruene Noten klar | Himmel/Glow pulsiert, Splitter fliegen | ok, nicht zu hell | ~400 (2.5 ms) | 283 ms | - |
| eclipse | gut | Corona + Randbaender pulsieren | ok (schwaecher als Beat-Peak) | ~280 (3.6 ms) | 307 ms | P3: Randbaender links/rechts unten auf dem Beat fast weiss ausgebrannt (Baender kommen aus mania_3d, nicht aus dem Shader) |
| abyss | gut, Saeulen etwas hell links oben | nur Dunst/Glow, Saeulen statisch (schwacher Beat) | ok | ~270 (3.7 ms) | 304 ms | P3: Beat kaum sichtbar im Himmel; 1x Frame 59 ms im Messlauf (einmalig, vermutlich Rauschen); Screenshot-Lauf 19 s Wanduhr 1x (Disk) |
| fractal | sehr gut | ja | ok | ~280 (3.6 ms) | 309 ms | - |
| aurora | gut (nach Fix), Vorhaenge dezent | Glow + Sterne | ok | ~240 (4.2 ms, teuerste Welt) | 326 ms | **P1 behoben:** Welt fiel im Spiel still auf Galaxie zurueck (Panorama `aurora.webp` kollidierte mit Ebenen-Schluessel `aurora` in `_build_theme_sky`, `pano==""`). Fix: `aurora.webp` -> `aurora_sky.webp` (+ .import, Preview, Generator). |
| monolith | mittel: Panele schimmern durch die Strecke, Himmel unruhig/hell grau | ja | ok | ~300-800 (0.8-2.7 ms) | 385 ms | P2: Strecke wirkt grau statt dunkel, Panel-Kanten im unteren Streckendrittel sichtbar (Readability-Maske greift nicht auf der Spur); Splitter/Prismen fliegen sichtbar |
| rift | gut, Strecke dunkel | Splitter + Riss pulsieren | ok | ~450-1300 (1.3 ms, schnellste Welt) | 337 ms | P3: heller Riss quert links das HUD-Label "RANG" (Lesbarkeit des Labels sinkt); gruene Noten auf gruenlicher Strecke etwas weniger Kontrast als in den roten Welten |
| nerve | sehr gut | Adern/Knoten pulsieren, Spuren fliegen vorbei | ok | ~240-480 (2.8 ms) | 342 ms | .uid-Dateien fuer `theme_nerve.gdshader` und Preview-Skript fehlen im Repo (untracked) |

## Ergebnis
- Kein Flackern gesehen (je 3 Frames pro Welt konsistent), kein Element ueber der Strecke, Drop in keiner Welt staerker als der Beat-Peak.
- Ladezeit: alle Welten 280-385 ms bis zum ersten Frame, schneller als Galaxie (~750 ms). Kein Hitch beim Laden der 8192er-Texturen (0 Frames > 50 ms ausser einmal 59 ms in abyss).
- Teuerste Welt: aurora (4.2 ms), dann abyss/eclipse/fractal (3.6-3.7 ms); alle unter Galaxie-Niveau + 1 ms.
- Offen (nicht in dieser Task gefixt): monolith-Streckenkontrast (P2), eclipse/abyss/aurora/monolith Randbaender auf dem Beat sehr hell (mania_3d, beat-core), rift-Riss hinter HUD-Label.
- Hinweis: Neue Worktrees brauchen vor dem ersten Lauf `--headless --import` (sonst "Failed loading resource" fuer alle Welt-Texturen und Rueckfall auf Galaxie).
