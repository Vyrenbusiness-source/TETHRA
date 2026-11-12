# Orbit: unklare Momente (Lesbarkeit) - Befund und Anzeige

Nutzer: "man versteht manchmal nicht, was man machen muss". Regeln bleiben wie in
`docs/modes/orbit_satellit.md` (Satelliten, Tasten A/B, Akzent, Halten, Runden-Pips).
Dieses Dokument listet die unklaren Situationen (gefunden an Einzelbildern) und die
Antwort der Ansicht (`scripts/orbit/orbit_view.gd`).

## Vorgehen

- Bot-Laeufe mit `--orbit --autoplay --shot --shot-at=<ms>` auf mehreren Maps, je
  1280x720 und 1920x1080 (Monitor 2, Dummy-Audio):
  - Zekk - Fluctuation [Normal] 2550 ms (Akzent), 3000 ms (A/B-Wechsel), 6000 ms
    (Halten erscheint), 6600 ms (Halten laeuft); [Hyper] 6350 ms (schnelle Folge)
  - xi - Happy End of the World [4K Normal] 161500 ms (Stapel), [4K Hard] 144900 ms
    (erstes Ziel nach 3-s-Pause)
  - Purukichi - Luster [Shimmer] 12950 ms (Stapel, 7,2 Sterne)
  - meganeko - The Cyber Grind [Hard] 10150 ms (dicht, 9,3 Sterne)
- Ausschnitte aus `docs/media/orbit.mp4` (Cyber Grind [Easy], alle 2 s ein Bild).
- Stellen per Skript gesucht: erster Akzent, erstes Halten, erster A/B-Wechsel,
  Abstand < 140 ms, Luecke > 3 s, spaeteres Ziel schon sichtbar und naeher als ein
  Zielradius am selben Ort (Stapel).

## Unklare Situationen (vorher)

1. **Welche Taste (A oder B)?** Ab 6 Sternen (Einstellung "auto") traegt auch das
   naechste Ziel keinen Buchstaben (Luster [Shimmer]: naechstes Ziel ein Akzent ohne
   Beschriftung, nur Farbe/Form). Wer die Belegung (z. B. Y/X) nicht auswendig weiss,
   raet.
2. **Akzent nicht eindeutig.** Halb blau / halb orange mit einem weissen Ring; die
   Buchstaben stehen eng als "YX" in der Mitte, der Cursor liegt genau darauf
   (Fluctuation 2550 ms). Der einfache weisse Rand gleicht dem Rand jedes naechsten
   Ziels, "beide Tasten" ist nur aus der Farbaufteilung abzulesen.
3. **Halten erst spaet erkennbar.** Ein spaeteres Halten ist ein blasses Band mit
   kleinem Ring am Ende; das Ende sieht wie ein eigenes Ziel aus, die Richtung (wo
   beginnt es) ist nicht ablesbar (Fluctuation 6000 ms: oranges Band links, Ende oben
   wirkt wie Anfang). Kein Wort/Zeichen "Halten".
4. **Waehrend des Haltens.** Grosser Folgekreis um die Kugel, aber kein Hinweis, dass
   man der Kugel folgen muss und wie lange noch (Fluctuation 6600 ms, 1920x1080:
   Kugel mit Folgekreis, naechstes "X" schon oben, nichts sagt "folgen").
5. **Stapel (mehrere Ziele am selben Ort).** Ein spaeteres Ziel liegt exakt unter dem
   naechsten und ist voellig verdeckt (Happy End [4K Normal] 161500 ms: man sieht nur
   den Akzent, das zweite Ziel darunter gar nicht). Sind beide Ringe sichtbar, kreisen
   zwei Satelliten auf demselben Ring (Luster 12950 ms: zwei Akzente nah beieinander,
   Ringe ueberlappen) - nicht zu sagen, welcher Satellit zu welchem Ziel gehoert und
   dass dort 2 Treffer nacheinander kommen.
6. **Runden-Pips zu klein.** Pips (2,5 px bei 720p) unter dem Ziel sind kaum zu sehen
   und lesen sich wie Deko, nicht wie "noch 2 Runden" (Fluctuation 3000 ms: am
   naechsten "X" gar keine Pips, am Ziel daneben zwei winzige graue Punkte).
7. **Schnelle Folgen / ueberlappende Ringe.** Orbit-Ringe benachbarter Ziele
   ueberlappen (Fluctuation 3000 ms: Ring des blauen Rang-1-Ziels schneidet den Ring
   des naechsten "X"), Treffer-Ring des eben getroffenen Ziels liegt zusaetzlich
   darueber. Das naechste Ziel ist durch weissen Rand + Buchstabe noch am klarsten.
8. **Neustart nach Pause/Break.** Nach einer langen Luecke (Happy End [4K Hard] 144900
   ms) oder nach dem Pausenmenue erscheint das erste Ziel wie jedes andere; nichts zeigt
   "hier geht es weiter, so viel Zeit bleibt".
9. **Erst-Begegnung.** Akzent, Halten und Stapel werden ausserhalb des Tutorials nie
   erklaert; das erste Auftreten in einer Sitzung kommt ohne Hinweis.

## Anzeige (nachher)

Ruhig, ohne Glow; nichts liegt auf dem naechsten Ziel.

1. **Taste**: das naechste Ziel traegt immer den Buchstaben der aktuellen Belegung
   (`key_labels`), ausser `orbit_key_hint` = 2 ("aus"). "auto" zeigt ihn jetzt auf allen
   Maps (vorher nur < 6 Sterne).
2. **Akzent**: Doppelrand (weisser Innenrand + feiner zweiter Ring) und beide Buchstaben
   getrennt, je einer auf seiner Farbhaelfte (links A, rechts B).
3. **Halten beim Erscheinen**: Band mit feinen Pfeilen in Laufrichtung und kleinem
   Wort "HOLD" auf dem Band (bzw. neben dem Ende bei kurzen Baendern).
4. **Halten laeuft**: Folgekreis um die Kugel mit Restzeit-Bogen (leert sich bis zum
   Ende) und kurzem Wort "folgen" ueber dem Kreis in den ersten Momenten bzw. wenn die
   Kugel wegzulaufen droht.
5. **Stapel**: verdeckte spaetere Ziele am selben Ort werden versetzt als "Karten"
   hinter dem vorderen gezeigt (kein eigener Ring/Satellit, solange sie verdeckt sind);
   am vorderen Ziel eine kleine Zahl "x2"/"x3" unten rechts ausserhalb des Rings.
6. **Runden-Pips**: groesser, hell mit dunklem Rand, deutlich als Zaehler.
7. **Neustart**: erstes Ziel nach einer Luecke >= 2,5 s, nach dem Pausenmenue oder am
   Songanfang bekommt einen kurzen Countdown-Ring (aeusserer Bogen, leert sich bis zum
   Treffer).
8. **Erst-Begegnung**: beim ersten Akzent / Halten / Stapel einer Sitzung ein kleiner
   einmaliger Text neben dem Ziel ("beide Tasten Y + X", "halten und der Kugel
   folgen", "2 Treffer hier"); er sucht sich eine freie Seite und weicht anderen Zielen
   aus. Aus mit `orbit_key_hint` = 2.

## Pruefung

Screenshots vorher/nachher je Situation in 1280x720 und 1920x1080 (Scratch, nicht im
Repo), mit Read geprueft; Tests `tests/run_orbit_*_tests.gd` gruen.
