# Marathon (Mania-Variante 14)

Mehrere 4K-Maps am Stück auf **einer** Zeitachse: eine HP-Leiste, eine Kombo, Übergänge auf dem Takt.

## Bedienung

- Song-Browser (Mania): Knopf **Marathon** in der Mods-Zeile. Hauptmenü: Zeile **Marathon** (öffnet den
  Browser mit der Auswahl).
- Quelle: ganze Bibliothek oder eine Sammlung. Länge: 3 / 5 / 8 Maps oder 5 / 10 / 20 Minuten.
  Sterne: Ziel ± 0,3 (Start = Sterne der gewählten Diff). **Neu mischen** = anderer Seed.
- Mods aus der Mods-Zeile (No-Fail, SV, 2D-Extras) gelten für den ganzen Lauf.
- Unter der Auswahl: lokale Rangliste der gewählten Länge mit Replays.

## Auswahl und Reihenfolge (`scripts/marathon/marathon_plan.gd`)

- Je Set die 4K-Diff, deren Sterne am nächsten am Ziel liegen; nur innerhalb ± 0,3, Map ≥ 45 s.
- Kette ab der gewählten Map (sonst Zufall mit festem Seed), jeweils die Map mit den geringsten
  Übergangskosten: Tempo-Abweichung (1:1, 2:1, 1:2) + Energiesprung (Noten/s).
- Danach Reihenfolge per Tauschsuche: Tempo-Weg + Energiebogen (ruhiger Start, Gipfel bei ~70 %).

## Übergang A → B

- **Mitte** = erste Taktgrenze von A, mit der B's erste Note mindestens 1 Schlag (≥ 250 ms) nach A's
  letzter Note kommt; A's Noten enden ≥ ½ Schlag vor der Mitte. Lücke: 1 Schlag bis gut 1 Takt.
- B's Taktgrenze (Takt der ersten Note) liegt genau auf der Mitte.
- Tempo passt (≤ 8 %, auch Doppel-/Halbtakt): B läuft mit Rate ρ (Tonhöhe geht mit), 4 Takte
  Überblendung (gleichmäßige Leistung), **Bass-Tausch** über einen Schlag genau auf der Mitte (EQ je
  Deck), danach 2 Takte Rampe zurück auf Rate 1. Passt es nicht: **Schnitt auf dem Takt** (1 Schlag
  Blende, Originaltempo).
- Intro der ersten Map auf 2 Takte vor der ersten Note gekürzt, Outro: 2 Takte Ausblendung.
- Feld: die zusammengefügte Map hat ein durchgehendes Takt-Raster (rote Linie an jeder Mitte und je
  Rampentakt), SV je Map wie in der eigenen Map. Anzeige: ruhige Zeile oben links
  („MARATHON · MAP 2 / 3“, Titel, Leiste je Map, „NÄCHSTE …“ blendet weich ein).

## Wiedergabe (`marathon_mixer.gd`)

SyncClock spielt eine stumme Master-Spur über die ganze Länge (Uhr, Pause, Lead-In, Skip unverändert).
Zwei Decks (eigener Bus mit EQ) folgen ihr: Abweichung je Bild aus demselben Mix gemessen, grob = Sprung
(nur stumm), fein = Tempo-Nachführung ±0,6 %. Tempo über `pitch_scale` in `_apply_rate()`.
**Später auf die Rate-Grundlage aus mv-tempo (`sync_clock.gd`) umstellen:** dort, wo `_apply_rate()`
`pitch_scale` setzt (Tonhöhe getrennt halten), und `MarathonRun.start_audio()` (Master-Rate).

## Wertung, Replay, Server

- Ergebnis gesamt + Reiter „Maps“ (je Map Sterne, Genauigkeit, Kombo, Fehler, Punkte).
- Lokale Rangliste je Länge: `user://marathon_scores.cfg` (Section = `n3`…`m20`).
- Ein Replay je Lauf: `user://replays/marathon/<id>.json` = `{meta, events}`; `meta.marathon` = Plan
  **mit Zeitachse** (exakt nachspielbar), `meta.mods`, `meta.mode = "marathon"`.
- Nichts geht an ScoreStore/den Server. Vorschlag für den Server-Betreiber: Modus-Schlüssel
  `mania_marathon`, `"ranked": false`, Felder `length`, `maps[{osz, version, stars}]`, `mods`
  (`MarathonStore.online_payload`).

## Prüfen

```
tests/run_mv_marathon_tests.gd                  # Regeln (warmd test mv_marathon)
<godot> --path . --position -1920,0 --audio-driver Dummy res://scenes/mania_3d.tscn --3d --autoplay \
  --marathon-store "--marathon-maps=<osz>|<version>|<sterne>;..." --marathon-harness=<ordner>
<godot> ... res://scenes/mania_3d.tscn --2d --marathon-replay=<id> --marathon-harness=<ordner>
python tools/marathon_sync_check.py <ordner>    # Taktgrenzen-Abweichung aus dem Mitschnitt
<godot> ... res://scenes/song_select.tscn --maps-dir=<ordner> --shot-marathon=<ordner>
```

Eigenes `APPDATA` setzen (Nutzerdaten bleiben unberührt), `tools/test_override.cfg` als `override.cfg`.
