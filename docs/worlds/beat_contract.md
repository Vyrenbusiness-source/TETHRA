# Beat-Vertrag der Welt-Shader (alle `shaders/theme_<name>.gdshader`)

Ziel (Nutzer): Jede Welt reagiert **exakt auf den Beat**, der Drop (Kiai-Start)
ist spürbar, aber **nie zu stark**. Lesbarkeit der Strecke geht vor.

`mania_3d.gd` setzt pro Frame diese Uniforms auf das Himmels-Material (aus
`BeatClock`, Zeitbasis `SyncClock.visual_time_ms()`). Jede Theme-Preview
(`scripts/gameplay3d/fx/theme_<name>_preview.gd`) simuliert sie mit **denselben
Formeln**, damit Preview und Spiel gleich aussehen.

| Uniform | Typ | Bedeutung | Formel (Spiel) |
|---|---|---|---|
| `beat_pulse` | float 0..1 | Helligkeits-Stoß, Attack exakt auf dem Schlag | `peak * exp(-phase*beat_ms/62)` (≈180 ms Decay), Downbeat ×1.15 |
| `beat_phase` | float 0..1 | Sägezahn im Beat (0 = Schlag) | `BeatClock.beat_phase` |
| `bar_phase` | float 0..1 | Sägezahn im Takt (0 = Downbeat) | `BeatClock.bar_phase` |
| `beat_step` | float, monoton | gezählte Beats + Easing: springt **auf** dem Schlag weiter, ruht bis zum nächsten | `beats_total + 1 - pow(1 - beat_phase, 4)` |
| `downbeat_pulse` | float 0..1 | wie `beat_pulse`, nur auf Taktanfängen, langsamer (≈1 Beat) | `exp(-bar_phase*meter*3)` |
| `kiai` | float 0..1 | Kiai-Anteil, weich (Kapitel-Überblendung) | `_ch_kiai_w` |
| `drop` | float 0..`DROP_MAX` | Drop-Hüllkurve: Kiai-Start | siehe unten |
| `energy` | float 0..1 | Musikenergie (über 1 Beat geglättet) | `_music_energy` |
| `comfort` | float 0/1 | Komfort-Modus: Bewegung halbieren, kein Rollen | |

Dazu wie bisher: `tint, brightness, star_brightness, star_hdr, star_speed,
star_phase, warp, readability, palette_mix, tex_a/tex_b, stars_a/stars_b`.
Effekte = Aus → alle Beat-Uniforms 0, Welt steht ruhig.

## Drop-Hüllkurve (gemeinsam, gedeckelt)

- Kiai-Start: `drop` steigt über **1 Beat** (smoothstep) auf `DROP_PEAK = 0.6`,
  fällt über **4 Beats** auf `DROP_HOLD = 0.3` und hält das während des Kiai.
- Kiai-Ende: über **2 Beats** auf 0.
- Komfort: ×0.5. Nie über `DROP_MAX = 0.6`.
- Der Drop **verwandelt** die Welt (z. B. Auge öffnet sich, Ring dreht schneller,
  Korona weitet sich, Splitter rücken näher), er **blendet nicht**.

## Harte Grenzen (Prüfkriterien in jeder Preview)

1. Nie flackern, kein Vollbild-Blitz, nichts vor/über der Strecke.
2. Mitte/unten bleibt dunkel: mittlere Luma der Region x 0.25..0.75, y 0.42..0.87
   steigt im Drop-Spitzen-Frame um **höchstens 20 %** gegenüber dem Ruhe-Frame,
   Hintergrund oben um höchstens **35 %**. Preview druckt beide Werte
   (`[luma] still=… beat=… drop=…`).
3. Beat sichtbar: Frame bei `beat_phase=0.02` vs. `0.5` unterscheidet sich im
   Hintergrund oben messbar (≥ 6 % Luma oder deutliche Bewegung über `beat_step`).
4. Mindestens **eine thementypische Bewegung läuft über `beat_step`**
   (rastet auf dem Schlag ein), eine Akzentuierung über `downbeat_pulse`, der
   Drop über `drop`. Dauerbewegung (Zeit) nur langsam und unterschwellig.
5. Farben: fast monochrom im Farbsatz des Themas, kein Neon (außer Welt „neon").
