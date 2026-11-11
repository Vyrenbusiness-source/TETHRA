<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/logo_wordmark.png">
    <img src="docs/media/logo.svg" alt="TETHRA" width="420">
  </picture>
</p>

<p align="center">
  <b>A free rhythm game for Windows. Play osu!mania 4K maps in 3D or 2D, turn any map into an SV map, or play Orbit, Rally and Dirigent, three rhythm modes of their own.</b>
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
  <img src="docs/media/play_3d_hero.webp" alt="TETHRA in 3D: four lanes flying through a world that pulses with the beat" width="100%">
</p>

## Four modes

<table>
  <tr>
    <td width="50%" align="center"><a href="docs/media/mania.mp4"><img src="docs/media/mania_anim.webp" alt="Mania gameplay" width="100%"></a><br><b>Mania</b><br><sub>osu!mania 4K in 3D worlds or the classic 2D field.<br><a href="docs/media/mania.mp4">▶ Watch with sound</a></sub></td>
    <td width="50%" align="center"><a href="docs/media/orbit.mp4"><img src="docs/media/orbit_anim.webp" alt="Orbit gameplay" width="100%"></a><br><b>Orbit</b><br><sub>Aim at targets, count the satellite laps, hit on the beat.<br><a href="docs/media/orbit.mp4">▶ Watch with sound</a></sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><a href="docs/media/rally.mp4"><img src="docs/media/rally_anim.webp" alt="Rally gameplay" width="100%"></a><br><b>Rally</b><br><sub>Table tennis in the rhythm of the map.<br><a href="docs/media/rally.mp4">▶ Watch with sound</a></sub></td>
    <td width="50%" align="center"><a href="docs/media/dirigent.mp4"><img src="docs/media/dirigent_anim.webp" alt="Dirigent gameplay" width="100%"></a><br><b>Dirigent</b><br><sub>Conduct the beat with the cursor, play the cues with two keys.<br><a href="docs/media/dirigent.mp4">▶ Watch with sound</a></sub></td>
  </tr>
</table>

Every mode plays regular osu! maps and has its own star rating, scores, leaderboards, replays and multiplayer.

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

Side view: you on the left, the opponent on the right, one ball. Every note of the map is your stroke, at exactly the note time. The ball flies to the opponent, bounces, comes back and reaches your racket on the next note. Long gaps give a slow high lob, streams give fast flat exchanges.

- **Keys.** A low ball is key A, a high ball is key B. A smash (finish or chord) needs both keys together. A long note is a charge: hold the key and release at the end.
- **Timing.** A ring on the bounce mark on your side shrinks to the note time, its colour shows the key.
- **Miss.** The ball flies past and the opponent serves again for the next note.

<p align="center">
  <a href="docs/media/rally.mp4"><img src="docs/media/rally_anim.webp" alt="Rally gameplay: table, racket and a ball with the landing ring" width="420"></a><br>
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
    <td width="50%"><a href="docs/media/ui_browser.webp"><img src="docs/media/ui_browser.webp" alt="Song browser"></a><br><sub>Song browser per mode (Mania, Orbit, Rally, Dirigent), each with its own star rating; pp for Mania, collections, star ranges, SV, played / unplayed and rank filters, and sorting.</sub></td>
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

**Which maps?** osu!mania 4K for Mania (3D and 2D), osu!standard and 4K for Orbit, Rally and Dirigent.

**Keys?** Mania lanes default to `D` `F` `J` `K`, Orbit, Rally and Dirigent use the left/right mouse button or `Z` / `X` for key A / B. `F` opens the chat. Everything can be rebound in Settings.

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

TETHRA ist ein kostenloses Rhythmusspiel für Windows: osu!mania-4K-Maps in 3D oder 2D, jede Map per SV-Mod als SV-Map (Noten tanzen auf dem Beat) und drei eigene Modi mit normalen osu!-Maps: Orbit (Ziele erscheinen auf dem Beat, ein Satellit kreist eine Runde pro Beat, Punkte zählen die Runden herunter; im letzten Umlauf zielst du auf das Ziel und drückst Taste A, B oder beide beim Akzent), Rally (Tischtennis im Takt der Map) und Dirigent (Taktfigur mit der Maus führen, Einsätze mit zwei Tasten spielen). Zu jedem Modus gibt es oben ein Video mit Ton. Dazu Online-Konto mit Bestenlisten, Web-Profilen und Chat, Replays, Multiplayer über den Server, eigene Musik als Orbit-Map, Online-Map-Browser, osu!-Skins, Clips und Turniere. Installation: **[TETHRA_Setup.exe](https://github.com/Vyrenbusiness-source/TETHRA/releases/download/worlds/TETHRA_Setup.exe)** herunterladen, ausführen, spielen. Meldet Windows „Der Computer wurde durch Windows geschützt“: **Weitere Informationen** → **Trotzdem ausführen**. Updates kommen automatisch. Maps gehören ihren Mappern, osu! ist eine Marke von ppy.
