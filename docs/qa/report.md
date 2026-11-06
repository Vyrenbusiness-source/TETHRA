# QA-Audit 2026-11-06 (Stand main @3003518) — Gesamt 5,8/10
P1 = wirkt kaputt, P2 = Qualitaetsverlust, P3 = Feinschliff.

## 0 Uebergreifend
- P1 Deutsch/Englisch gemischt: PLAY, SCORE/ACCURACY/MISSES/NOTES, MAX COMBO, Retry, Plays/Accuracy/TOP PLAYS, Unlimited/Comma/Period/Scroll-Speed/Hitsounds, stars (song_select.gd:472, mania_3d.gd HUD+Results, profile_panel.gd:149-151,189, settings_panel.gd:95,209, pause_menu.gd:82,88, gameplay_3d.gd).
- P1 Zahlen/Datum: Dezimalkomma (85,09 %, 0,8x), Tausenderpunkt (10.067, 923.412 statt 00923412), Datum einheitlich TT.MM.JJJJ HH:MM. -> zentrale Helfer UiTheme.fmt_num/fmt_score/fmt_date.
- P2 Modal-Titel ohne System (Abstaende 30/80px, Profil ohne Titel) -> UiTheme.modal_header(). Modal-Backdrop uneinheitlich (Settings Blur, Profil nur ColorRect) -> UiTheme.modal_backdrop().
- P2 Zu viele Voll-Cyan-Buttons (Profil 7) -> pro Screen 1 Primary (15% dunkler), Rest Ghost-Buttons. Button-Schrift-Regel einheitlich.
- P3 Tastennamen: Settings zeigt Comma/Period -> zentrales Mapping (UiTheme.key_short).

## 1 Hauptmenue 7: Cover zu hell (abdunkeln ~0.55), Logo-Outline 24->38 Puls zu dick (8-12px, kein Puls), Achse Logo x958 vs Buttons x970, Untertitel ohne Leerzeichen, Profilkarte "Plays"->"Spiele" + groesser, Ecken-Karten gleiche Hoehe/Padding + Lauftext, unteres Drittel leer, Version unlesbar.
## 2 Einstellungen 7: englische Begriffe, Tasten-Buttons ungleich breit (gleiche Keycaps), Zeilenhoehen 44/36/48/34 -> alle 44, Klarheit Toggle vs Bass Slider, Offset-Kalibrierung fehlt, Format 0,8x, Slider bei 0% Fuellstummel.
## 3 Profil 6: Menue scheint durch (Blur-Backdrop), englisch, 7 Cyan-Play-Buttons -> Ghost, Header gequetscht (rechte Spalte leer), Grade-Chips Baseline 2px versetzt, letzte Zeile hart gekappt (Fade), "34pp" vs "331 pp", Scrollbar klebt, Avatar Platzhalter, Diff-Namen strip_edges.
## 4 Song-Browser 5: Suchfeld laeuft rechts raus (einheitlich 24px Rand), PLAY->SPIELEN, stars->Sterne, Auswahlrahmen nimmt Sternfarbe (neon) -> immer ACCENT, Text ueber Cover unlesbar (deckender Verlauf links), aktiver Tab unklar, Mitte 880px leer, Info-Panel unten leer, linke Raender 16/33, CS/AR im 4K sinnlos ("596 Noten · 4 Tasten · OD 6,5"), "NF: Aus" kryptisch (Toggle No-Fail), Sterne doppelt ("★ 7,27"), ASCII-Pfeile -> Chevrons, Vorschau-Balken gruen->cyan, Filter-Chips "<2★ 2–4★ 6★+", letzte Karte ohne Fade, Grade B zu gross.
## 5 Gameplay 6: HUD englisch, Label/Wert 50-60px getrennt, rechte Spalte verstreut; Score formatiert (tabellarische Ziffern); Titelzeile ohne Schatten; zwei Balken oben unklar; gedrueckter Receptor-Glow ueberstrahlt bis x1600 (max Skalierung 1.15, Glow halbieren); Receptor-Farben ungleich (Spur 1 kraeftig, 2-3 blass); Key-Glow-Saeule nicht perspektivisch; 5 Punkte unten unklar; SS riesig vs Combo winzig (umgekehrt); Torus am Himmel Clip-Art.
## 6 Ergebnis 4 (alt, inzwischen durch ResultsScreen ersetzt — neu pruefen): Komposition zerfaellt, PP "—", englisch, Score-Format, Urteilsfarben inkonsistent, Datum ISO, Mikro-Labels 11px.
## 7 Lobby 6: Leerzustand-Zeilenabstand, "Gexanx's Raum" -> "Gexanx' Raum", zwei Primaerbuttons, Felder ungleich (54 vs 40px), Kopfhoerer-Emoji -> Linien-Icon, Leerzustand nicht zentriert, Refresh-Icon zu klein, "z.B." -> "z. B.".
## 8 Tutorial 5: Inhalt abgeschnitten (Tasten unter "Im Song-Browser:" fehlen), Hintergrund mit blockigen Quadrat-Sternen, "->" im Text, Tasten als Fliesstext statt Keycaps, Fortschritt doppelt, Titelstil, Versalien-Mix.
