<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/logo_wordmark.png">
    <img src="docs/media/logo.svg" alt="TETHRA" width="420">
  </picture>
</p>

<p align="center">
  <b>A free rhythm game for Windows. Play osu!mania 4K maps in 3D or 2D, turn any map into an SV map, or play Orbit, Rally, Dirigent, Trace and Rebound, five rhythm modes of their own.</b>
</p>

<p align="center">
  <a href="https://github.com/Vyrenbusiness-source/TETHRA/releases/download/worlds/TETHRA_Setup.exe"><img src="https://img.shields.io/badge/Download%20for%20Windows-TETHRA__Setup.exe-E9A23B?style=for-the-badge&labelColor=1B1A18" alt="Download TETHRA_Setup.exe for Windows" height="48"></a>
</p>

<p align="center">
  <sub>One installer, everything included: game, 13 worlds, sample maps. No osu! or Godot needed. Updates install themselves.</sub>
</p>

<p align="center">
  <a href="https://github.com/Vyrenbusiness-source/TETHRA/releases/latest"><img src="https://img.shields.io/github/v/release/Vyrenbusiness-source/TETHRA?label=version&color=E9A23B" alt="Version"></a>
  <a href="https://github.com/Vyrenbusiness-source/TETHRA/releases"><img src="https://img.shields.io/github/downloads/Vyrenbusiness-source/TETHRA/total?label=downloads&color=E9A23B" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/platform-Windows-555?logo=windows&logoColor=white" alt="Windows">
</p>

<p align="center">
  <a href="docs/media/trailer.mp4"><img src="docs/media/trailer_thumb.webp" alt="TETHRA trailer: six modes, one game" width="100%"></a><br>
  <sub><a href="docs/media/trailer.mp4"><b>▶ Watch the trailer</b></a> (79 s, all six modes)</sub>
</p>

<p align="center">
  <img src="docs/media/play_3d_hero.webp" alt="TETHRA in 3D: four lanes flying through a world that pulses with the beat" width="100%">
</p>

## Six modes

<table>
  <tr>
    <td width="33%" align="center"><a href="docs/media/mania.mp4"><img src="docs/media/mania_anim.webp" alt="Mania gameplay" width="100%"></a><br><b>Mania</b><br><sub>osu!mania 4K in 3D worlds or the classic 2D field.<br><a href="docs/media/mania.mp4">▶ Watch with sound</a></sub></td>
    <td width="33%" align="center"><a href="docs/media/orbit.mp4"><img src="docs/media/orbit_anim.webp" alt="Orbit gameplay" width="100%"></a><br><b>Orbit</b><br><sub>Aim at targets, count the satellite laps, hit on the beat.<br><a href="docs/media/orbit.mp4">▶ Watch with sound</a></sub></td>
    <td width="33%" align="center"><a href="docs/media/rally.mp4"><img src="docs/media/rally_anim.webp" alt="Rally gameplay" width="100%"></a><br><b>Rally</b><br><sub>Table tennis in the rhythm of the map.<br><a href="docs/media/rally.mp4">▶ Watch with sound</a></sub></td>
  </tr>
  <tr>
    <td width="33%" align="center"><a href="docs/media/dirigent.mp4"><img src="docs/media/dirigent_anim.webp" alt="Dirigent gameplay" width="100%"></a><br><b>Dirigent</b><br><sub>Conduct the beat with the cursor, play the cues with two keys.<br><a href="docs/media/dirigent.mp4">▶ Watch with sound</a></sub></td>
    <td width="33%" align="center"><a href="docs/media/trace.mp4"><img src="docs/media/trace_anim.webp" alt="Trace gameplay" width="100%"></a><br><b>Trace</b><br><sub>A glowing thread draws the map as you play it.<br><a href="docs/media/trace.mp4">▶ Watch with sound</a></sub></td>
    <td width="33%" align="center"><a href="docs/media/rebound.mp4"><img src="docs/media/rebound_anim.webp" alt="Rebound gameplay" width="100%"></a><br><b>Rebound</b><br><sub>Four balls bounce on four drums and land on your notes.<br><a href="docs/media/rebound.mp4">▶ Watch with sound</a></sub></td>
  </tr>
</table>

Every mode plays regular osu! maps (Trace and Rebound: osu!mania 4K maps) and has its own star rating, scores, leaderboards, replays and multiplayer.

## Orbit: aim at the target, count the laps

Targets appear on a beat at a place in the field. A satellite circles each target, exactly one lap per beat. Small pips under the target count the laps left, one disappears per beat. When the satellite crosses the mark at 12 o'clock in the last lap, it is time: put the cursor on the target and press the right key.

- **Beat.** Count it: "three, two, one, now". The target shows up on a beat, so the rhythm is visible before it is audible.
- **Keys.** Key A (mouse left or `Z`) hits cool discs. Key B (mouse right or `X`) hits warm rounded squares. A disc with a white ring is an accent: press both keys together.
- **Aim.** A press only counts when the cursor is on the target. The wrong key or a miss of the target gives no hit.
- **Holds.** Hit the head, keep the key down and follow the ball along the band to the end.
- **Maps.** Orbit plays regular osu! maps (osu!standard and 4K). Timing is the map's own, to the millisecond, and the converter keeps every target reachable.

Mods: Hidden, Fade-In and Precision (tighter windows). Your best Orbit runs add up to an Orbit rating in your profile. Settings: laps ahead, target size and cursor size.

<p align="center">
  <a href="docs/media/orbit.mp4"><img src="docs/media/orbit_anim.webp" alt="Orbit gameplay: targets with circling satellites and lap pips" width="420"></a><br>
  <sub><a href="docs/media/orbit.mp4"><b>▶ Watch with sound</b></a> · New to Orbit? The game offers a short tutorial the first time you switch to it.</sub>
</p>

<p align="center">
  <a href="docs/media/ui_orbit_results.webp"><img src="docs/media/ui_orbit_results.webp" alt="Orbit result screen" width="420"></a><br>
  <sub>Result: every hit on the timeline with timing. Grades CORE to MISS.</sub>
</p>

## Rally: table tennis to the beat

You look over the shoulder of your player: the camera sits behind and above your racket, the table runs away from you and the opponent stands at the far end. Every note of the map is one ball. It flies to the opponent, bounces and comes back, and reaches your racket at exactly the note time.

- **Zones.** Your half of the table has 4 zones, one per column (the Mania 4K keys, default `D` `F` `J` `K`). Maps with 3 zones use `F` `J` `K`. A ball lands in the zone of its note and you hit it with the key of that zone. The wrong zone gives no hit.
- **Smash.** A finish or a chord is a smash, ringed in white: press the zone keys together.
- **Charge.** A long note is a charge: hold the key and release at the end.
- **Timing.** A ring in the landing zone shrinks to the note time. The shadow of the ball shows the zone while it is still in the air.
- **Miss.** The ball flies past and the opponent serves again for the next note.

<p align="center">
  <a href="docs/media/rally.mp4"><img src="docs/media/rally_anim.webp" alt="Rally gameplay: the table seen from behind the player, three zones and a ball with the landing ring" width="420"></a><br>
  <sub><a href="docs/media/rally.mp4"><b>▶ Watch with sound</b></a></sub>
</p>

## Dirigent: conduct the beat, play the cues

You do two things at once. With the mouse or pen you lead a conducting pattern: on every beat the cursor must be at the current point (4/4 goes down, left, right, up). With two keys you play the cues of the map: cues run along a strip under the pattern towards a hit line. Circles are key A, diamonds are key B, both together for a finish.

- **Pattern.** It follows the time signature of the map. Fast songs get a slower, longer pattern. Kiai sections swing wider.
- **Score.** 40 % beat (aim at each point), 60 % cues. One combo counts both.
- **Read.** The big point is the current beat with a ring that shrinks to the beat. The next point is small and numbered.

<p align="center">
  <a href="docs/media/dirigent.mp4"><img src="docs/media/dirigent_anim.webp" alt="Dirigent gameplay: conducting pattern and the cue strip" width="420"></a><br>
  <sub><a href="docs/media/dirigent.mp4"><b>▶ Watch with sound</b></a></sub>
</p>


## Trace: draw the beat

A glowing thread grows across the field at a steady speed. Every note is a bend of the thread, placed where the thread is at the note time. The arrow at the bend shows the direction: column 1 goes left, 2 down, 3 up, 4 right. The same column twice is a knot on a straight line, the opposite direction is a tight hairpin, a chord of two notes is a diagonal, 3 or 4 notes are a star. A hold is a thick glowing part of the thread until the release mark.

- **Read.** The path of the next 1.2 s is drawn ahead. A ring at each bend shrinks to the note time.
- **Keys.** Mania 4K keys, default `D` `F` `J` `K`. Judgement, holds, mods and star rating are the same as in Mania.
- **End.** After the last note the camera zooms out and shows the whole picture of the map.

<p align="center">
  <a href="docs/media/trace.mp4"><img src="docs/media/trace_anim.webp" alt="Trace gameplay: a glowing thread with arrows at every bend" width="420"></a><br>
  <sub><a href="docs/media/trace.mp4"><b>▶ Watch with sound</b></a></sub>
</p>

## Rebound: bounce on the beat

Four drums in a row, one ball over each. A ball lands on its drum exactly at the note time and bounces on to the next note of its column. Long pauses give a high arc, a jack is a quick dribble. A hold squashes the ball on the drum until the end of the note.

- **Read.** A ring on the drum shrinks to the note time. A faint ghost arc shows the next bounce. Chords land together and are joined by a thin line.
- **Keys.** The key under each drum, default `D` `F` `J` `K`. Judgement, holds, mods and star rating are the same as in Mania. Only osu!mania 4K maps.

<p align="center">
  <a href="docs/media/rebound.mp4"><img src="docs/media/rebound_anim.webp" alt="Rebound gameplay: four balls bouncing on four drums" width="420"></a><br>
  <sub><a href="docs/media/rebound.mp4"><b>▶ Watch with sound</b></a></sub>
</p>

## Suggestions for you

The song browser has a **For you** block above the list, in every mode. It picks maps by your own level, which it learns from your runs in that mode. Three levels:

- **Easy** is a little below your level, for a relaxed run.
- **Challenge** is at your level and a bit above. This is the default.
- **Push** is a step up, with maps that could enter your top 10.

Each card says why it was picked, for example the star range or a style you play well. Players with few runs get careful suggestions. Hide the block with **Hide**.

<p align="center">
  <a href="docs/media/ui_browser.webp"><img src="docs/media/ui_browser.webp" alt="Song browser with the For you block and the six mode buttons" width="640"></a>
</p>

## Tutorials for every mode

Every mode has a short interactive tutorial. The game offers it the first time you switch to a mode. You can start it later from the **?** next to the mode in the main menu or from **Tutorial** in the song browser.

<p align="center">
  <a href="docs/media/ui_menu.webp"><img src="docs/media/ui_menu.webp" alt="Main menu with the six modes" width="640"></a>
</p>

## Any map becomes an SV map

Switch on **SV** in the song browser. The mod writes scroll changes from the map's own beat grid: notes bounce on every beat in the chorus, surge, hold, run backwards for a moment and jump on strong beats. They still arrive exactly on time. Two levels: Normal and Strong.

<p align="center">
  <a href="docs/media/sv_mod.mp4"><img src="docs/media/sv_mod_anim.webp" alt="SV mod in the chorus of The Cyber Grind" width="360"></a><br>
  <sub>meganeko – The Cyber Grind, a map without its own SV. <a href="docs/media/sv_mod.mp4"><b>▶ Watch with sound</b></a></sub>
</p>

## 3D worlds and the classic 2D field

<p align="center">
  <a href="docs/media/play_3d_worlds.webp"><img src="docs/media/play_3d_worlds.webp" alt="The 13 worlds of TETHRA" width="100%"></a><br>
  <sub>13 worlds that move with the music: Galaxy, Boss, Aurora, Neon, Eclipse, Abyss, Fractal, Obsidian, Storm, Singularity, Monolith, Rift, Nerve.</sub>
</p>

<table>
  <tr>
    <td width="50%"><a href="docs/media/play_2d.webp"><img src="docs/media/play_2d.webp" alt="2D playfield"></a><br><sub>2D with the options you know from osu!mania: scroll speed 1–40, direction, hit position, column spacing, Hidden / Fade-In / Cover.</sub></td>
    <td width="50%"><a href="docs/media/play_2d_skins.webp"><img src="docs/media/play_2d_skins.webp" alt="osu! skins in 2D"></a><br><sub>Import your osu! skins (.osk), or use one of 3 built-in skins in your own note colours.</sub></td>
  </tr>
</table>

## Maps, scores and friends

<table>
  <tr>
    <td width="50%"><a href="docs/media/ui_browser.webp"><img src="docs/media/ui_browser.webp" alt="Song browser"></a><br><sub>Song browser per mode (Mania, Orbit, Rally, Dirigent, Trace, Rebound), each with its own star rating; pp for Mania, collections, star ranges, SV, played / unplayed and rank filters, and sorting.</sub></td>
    <td width="50%"><a href="docs/media/ui_online.webp"><img src="docs/media/ui_online.webp" alt="Online map browser"></a><br><sub>Search and download ranked maps in the game, for Mania and for Orbit.</sub></td>
  </tr>
  <tr>
    <td width="50%"><a href="docs/media/ui_results.webp"><img src="docs/media/ui_results.webp" alt="Results"></a><br><sub>Results with judgements, UR, early/late, hit error and accuracy over time. Replays and video clips.</sub></td>
    <td width="50%"><a href="docs/media/ui_orbit_fail.webp"><img src="docs/media/ui_orbit_fail.webp" alt="Failed Orbit run"></a><br><sub>A failed run still shows every hit and miss on the timeline. In Mania the fail screen also names the likely cause (a lag spike, early releases, a burst of misses).</sub></td>
  </tr>
  <tr>
    <td width="50%"><a href="docs/media/ui_lobby.webp"><img src="docs/media/ui_lobby.webp" alt="Multiplayer room"></a><br><sub>Multiplayer by room code: free, teams, battle royale, in all four modes.</sub></td>
    <td width="50%"><a href="docs/media/ui_tournament_pick.webp"><img src="docs/media/ui_tournament_pick.webp" alt="Tournament picks and bans"></a><br><sub>Tournaments with picks, bans and auto-pick filters.</sub></td>
  </tr>
  <tr>
    <td width="50%"><a href="docs/media/ui_tournament_end.webp"><img src="docs/media/ui_tournament_end.webp" alt="Tournament end screen"></a><br><sub>Tournament standings with every player's stats.</sub></td>
    <td width="50%"><a href="docs/media/ui_chat.webp"><img src="docs/media/ui_chat.webp" alt="Chat overlay with a map card and a score card"></a><br><sub>Chat: press <code>F</code> anywhere. Maps and scores arrive as cards you can preview, download or replay.</sub></td>
  </tr>
</table>

## Online account

Sign in or register in the game (or on [butzebot.com](https://butzebot.com/tethra)). The account is optional; without it everything works offline.

<table>
  <tr>
    <td width="50%"><a href="docs/media/ui_login.webp"><img src="docs/media/ui_login.webp" alt="Sign-in dialog"></a></td>
    <td valign="top">
      <ul>
        <li><b>Leaderboards</b> per map and mode (Mania, Orbit). Your best runs count.</li>
        <li><b>Web profiles</b> on butzebot.com with your scores, rating and profile picture.</li>
        <li><b>Chat</b> with other players (<code>F</code>). Share a map or one of your scores.</li>
        <li><b>Replays</b> upload with your score. Others can watch them from the leaderboard or from a chat card.</li>
        <li><b>Multiplayer</b> runs through the server, so you need no port forwarding. LAN stays an option.</li>
      </ul>
    </td>
  </tr>
</table>

## Your own music

Drop an `.mp3`, `.ogg` or `.wav` onto the song browser, or pick it with **Import**. TETHRA finds the tempo and beats and builds an Orbit map in about a second. It is playable in Orbit only. It needs FFmpeg next to the game or on your PATH. Import also takes `.osz` files and a whole osu! `Songs` folder (4K Mania and osu!standard maps).

## Install

1. Download **[TETHRA_Setup.exe](https://github.com/Vyrenbusiness-source/TETHRA/releases/download/worlds/TETHRA_Setup.exe)** (about 430 MB).
2. Run it. If Windows shows "Windows protected your PC", click **More info**, then **Run anyway**. The game is not code-signed.
3. Start TETHRA from the desktop or the start menu. New versions install themselves.

Graphics problems? Start "TETHRA (Kompatibilitätsmodus)" from the start menu (OpenGL instead of Vulkan). After a crash the game starts in a safe graphics mode by itself.

The `TETHRA.pck` files on the [release pages](https://github.com/Vyrenbusiness-source/TETHRA/releases) are the update packages the game downloads on its own. You do not need them.

## FAQ

**Do I need osu!?** No. TETHRA plays `.osz` files on its own and downloads maps in the game.

**Which maps?** osu!mania 4K for Mania (3D and 2D), Trace and Rebound, osu!standard and 4K for Orbit, Rally and Dirigent.

**Keys?** Mania lanes default to `D` `F` `J` `K`, Orbit and Dirigent use the left/right mouse button or `Z` / `X` for key A / B. Rally (4 zones), Trace and Rebound use the Mania keys, Rally with 3 zones uses `F` `J` `K`. `F` opens the chat. Everything can be rebound in Settings.

**Mac or Linux?** Windows only for now. You can build from source with Godot 4.7.

## Build from source

1. Install [Godot 4.7](https://godotengine.org/download).
2. Clone this repository and open `project.godot`, or run `godot --path .`
3. Export a pack: `godot --headless --path . --export-pack "Windows" TETHRA.pck`

## Credits

- osu! is a trademark of ppy Pty Ltd. TETHRA is an independent project and is not affiliated with osu!.
- Maps belong to their mappers. The online browser downloads through a public mirror.
- Star rating and pp: [rosu-pp](https://github.com/MaxOhn/rosu-pp). Clips are encoded with [FFmpeg](https://ffmpeg.org) (GPL, shipped as a separate program).
- Built with [Godot Engine](https://godotengine.org).

## Deutsch

TETHRA ist ein kostenloses Rhythmusspiel für Windows: osu!mania-4K-Maps in 3D oder 2D, jede Map per SV-Mod als SV-Map (Noten tanzen auf dem Beat) und fünf eigene Modi mit normalen osu!-Maps: Orbit (Ziele erscheinen auf dem Beat, ein Satellit kreist eine Runde pro Beat, Punkte zählen die Runden herunter; im letzten Umlauf zielst du auf das Ziel und drückst Taste A, B oder beide beim Akzent), Rally (Tischtennis im Takt der Map), Dirigent (Taktfigur mit der Maus führen, Einsätze mit zwei Tasten spielen), Trace (ein Leuchtfaden zeichnet die Map, jede Note ist ein Knick in Richtung ihrer Spalte) und Rebound (vier Bälle hüpfen auf vier Trommelfellen und landen genau auf den Noten; beide nur mit 4K-Maps). Rally läuft mit Blick hinter den Spieler und 4 Zonen (oder 3). Der Browser schlägt unter „For you“ passende Maps vor (Easy, Challenge, Push) und lernt dein Level und deinen Stil, und jeder Modus hat ein kurzes Tutorial. Zu jedem Modus gibt es oben ein Video mit Ton. Dazu Online-Konto mit Bestenlisten, Web-Profilen und Chat, Replays, Multiplayer über den Server, eigene Musik als Orbit-Map, Online-Map-Browser, osu!-Skins, Clips und Turniere. Installation: **[TETHRA_Setup.exe](https://github.com/Vyrenbusiness-source/TETHRA/releases/download/worlds/TETHRA_Setup.exe)** herunterladen, ausführen, spielen. Meldet Windows „Der Computer wurde durch Windows geschützt“: **Weitere Informationen** → **Trotzdem ausführen**. Updates kommen automatisch. Maps gehören ihren Mappern, osu! ist eine Marke von ppy.
