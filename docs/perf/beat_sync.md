# Beat-Sync-Messung

Stand: 2026-11-07, erzeugt von `tools/beat_sync_check.py`.

## Aufruf

```
python tools/beat_sync_check.py --report docs/perf/beat_sync.md
```

Rendert `song_select.tscn --mania --autoplay` per Godot Movie-Maker
(`--write-movie <dir>/f.png --fixed-fps 60 --audio-driver Dummy`, Testfenster
via `tools/test_override.cfg`, `--position -1700,120`), misst die mittlere
Luma je Region und Frame und setzt sie gegen das Beat-Raster der Map.
Optionen: `--seconds`, `--start` (Song-Zeit in s), `--frames-dir` + `--keep`,
`--analyze <dir>` (vorhandene Frames erneut messen), `--bpm/--offset`
(Raster ueberschreiben), `--report <md>`.

## Methode

- Zeit je Frame: Frame k liegt im Film bei k/60 s. Die Audio-Spur ist frame-genau
  gemischt; Song-Zeit(k) = k*1000/60 + c, c aus der Abspielposition des Songs
  (Probe-Autoload, nur lesend) gefittet. Lead-In-Stille, Ausgabelatenz und
  Offsets stecken damit nicht in der Referenz: Bezug **Audio** = was man im Film hoert.
- Bezug **Spieluhr**: dieselben Frames gegen `SyncClock.visual_time_ms()` (inkl.
  `visual_offset_ms`), die Zeit, mit der das Spiel seine Beat-FX rechnet.
- Beat-Raster: rote Timing-Points der Map (Offset = Zeitpunkt des Punkts).
- Phase: je Beat das Helligkeits-Maximum im Fenster [Beat - 1/2 Beat, Beat + 1/2 Beat);
  positiv = Spitze nach dem Beat. Frame-Raster 16.7 ms: ein Puls mit Angriff genau
  auf dem Beat hat sein Maximum im ersten Frame danach, ideal also 0..+16.7 ms
  (Mittel ca. +8 ms, Streuung ca. 5 ms).
- Spitze/Tal: Mittel der Beat-Maxima / Mittel der Beat-Minima.
- R^2 Beat: Anteil der Varianz der trendbereinigten Helligkeit (gleitendes Mittel
  ueber 1 Beat abgezogen), den das beat-gefaltete Profil (16 Phasen-Bins) erklaert.
  Nahe 0 = Helligkeit aendert sich nicht im Takt (z. B. nur durch Noten/Kamera).
- Profil-Spitze: Phase des hellsten Bins im gefalteten Profil.

Regionen:
- Hintergrund oben: x 0.00..1.00, y 0.04..0.30 (Anteil der Bildgroesse)
- Strecke: x 0.25..0.75, y 0.42..0.72 (Anteil der Bildgroesse)
- Pads: x 0.22..0.78, y 0.74..0.87 (Anteil der Bildgroesse)

## Ergebnis

```
Map: *namirin - Mizutamari Tobikoete (with Nanahira) [Beginner] | 194.00 BPM | Offset 444.0 ms | 1 rote Timing-Points
Fenster: Song-Zeit 500..8500 ms, Frames 51..530 (480 Frames)
Song-Zeit 0 im Film bei Frame 20.25 (Audio-Start Frame 26, Quelle: Lead-In-Ueberhang 99.8 ms, Einsatz bei Sample 20992)
Gegenprobe Abspielposition: +6.4 ms (Streuung 3.2 ms), 16.667 ms/Frame (Soll 16.667)
Start-Countdown: 21 Frames (0.3 s) vor dem Lead-In
Lead-In: 1656 ms Soll, 4 Frames = 67 ms im Film | Ausgabelatenz 0.0 ms | visual_offset 0.0 ms | user_offset 0.0 ms
Spieluhr (visual_time) minus Audio-Spur: Mittel +319.4 ms, Streuung 11.2 ms, min +299.8, max +347.8
WAV-Check: erstes Song-Sample in der Film-WAV bei Frame 24.000 (Audio-Start laut Probe: Frame 26)

| Region | Bezug | Beats | Phase Mittel | Streuung | Median | Profil-Spitze | Spitze/Tal | R^2 Beat | Luma | Urteil |
|---|---|---|---|---|---|---|---|---|---|---|
| Hintergrund oben | Audio | 25 | -0.9 ms | 13.1 ms | -0.1 ms | +10 ms | 1.215 | 0.61 | 72.8 | pulsiert im Takt |
| Hintergrund oben | Spieluhr | 25 | +11.7 ms | 8.1 ms | +11.1 ms | +10 ms | 1.214 | 0.85 | 72.8 | pulsiert im Takt |
| Strecke | Audio | 25 | -10.2 ms | 97.0 ms | -35.4 ms | -48 ms | 1.437 | 0.18 | 29.9 | pulsiert, Phase streut |
| Strecke | Spieluhr | 25 | -2.5 ms | 92.0 ms | -24.3 ms | -29 ms | 1.435 | 0.35 | 29.9 | pulsiert, Phase streut |
| Pads | Audio | 25 | -2.9 ms | 15.3 ms | -0.5 ms | +10 ms | 1.880 | 0.60 | 63.5 | pulsiert im Takt |
| Pads | Spieluhr | 25 | +9.4 ms | 8.7 ms | +8.2 ms | +10 ms | 1.863 | 0.73 | 63.5 | pulsiert im Takt |
```

Gefaltetes Profil (Bezug Audio, Luma-Abweichung je 1/16 Beat ab Beat):
- Hintergrund oben: +7.86 +6.59 +3.82 +2.33 +1.12 +0.22 -0.54 -1.49 -2.01 -2.65 -2.97 -3.47 -3.59 -3.66 -3.11 +2.18
- Strecke: +1.02 +0.58 -0.48 -0.80 -0.61 -0.77 -0.59 -0.88 -0.73 -0.58 -0.74 +0.03 +1.29 +2.60 +1.26 -0.49
- Pads: +21.19 +13.60 +5.27 +2.50 -0.22 -2.84 -5.63 -7.87 -8.98 -9.78 -9.47 -8.44 -7.09 -4.55 +5.37 +18.86
