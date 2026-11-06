[![DevConnect](https://devconnectplatform.com/api/badge/vyren)](https://devconnectplatform.com/u/vyren)

<p align="center">
  <img src="docs/media/hero.png" alt="TETHRA - 3D rhythm game" width="100%">
</p>

<p align="center">
  <b>Fly through space to the beat. Play your osu!mania 4K maps in full 3D.</b>
</p>

<p align="center">
  <a href="https://github.com/Vyrenbusiness-source/TETHRA/releases/latest"><img src="https://img.shields.io/badge/%E2%AC%87%20Download-latest%20release-2ea44f?style=for-the-badge" alt="Download"></a>
</p>

<p align="center">
  <a href="https://github.com/Vyrenbusiness-source/TETHRA/releases/latest"><img src="https://img.shields.io/github/v/release/Vyrenbusiness-source/TETHRA?label=release" alt="Release"></a>
  <a href="https://github.com/Vyrenbusiness-source/TETHRA/releases"><img src="https://img.shields.io/github/downloads/Vyrenbusiness-source/TETHRA/total?label=downloads" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/Godot-4.7-478cbf?logo=godotengine&logoColor=white" alt="Godot 4.7">
  <img src="https://img.shields.io/badge/platform-Windows-0078d4?logo=windows&logoColor=white" alt="Windows">
</p>

<p align="center">
  <img src="docs/media/preview.webp" alt="Gameplay preview" width="720">
</p>

## What is TETHRA?

TETHRA is a **3D space-flight rhythm game**. It reads standard **osu!mania 4K** beatmaps (`.osz`) and turns them into a lane you fly down, with exact osu! judgement and scoring.

## Features

- **Plays your maps.** Import any osu!mania 4K `.osz` beatmap.
- **Exact scoring.** osu! judgement windows and ScoreV1.
- **Scroll-speed maps.** SV maps behave exactly like in osu!lazer.
- **Star rating and pp** via rosu-pp.
- **Replays.** Watch your plays again.
- **Multiplayer.** Join friends with a room code.
- **Auto-updater.** New versions install themselves.

## Screenshots

<table>
  <tr>
    <td><img src="docs/media/gameplay.webp" alt="Gameplay"><br><sub>Gameplay</sub></td>
    <td><img src="docs/media/browser.webp" alt="Song browser"><br><sub>Song browser</sub></td>
  </tr>
  <tr>
    <td><img src="docs/media/menu.webp" alt="Main menu"><br><sub>Main menu</sub></td>
    <td><img src="docs/media/settings.webp" alt="Settings"><br><sub>Settings</sub></td>
  </tr>
  <tr>
    <td><img src="docs/media/results.webp" alt="Results"><br><sub>Results</sub></td>
    <td><img src="docs/media/profile.webp" alt="Profile"><br><sub>Profile</sub></td>
  </tr>
</table>

## Controls

| Action | Default key |
| --- | --- |
| Lanes 1-4 (Mania) | `D` `F` `J` `K` |
| Hook | `Z` / `X` or left / right mouse button |
| Fullscreen | `F11` |

All keys can be rebound in Settings.

## Installation

1. Download the latest zip from [Releases](https://github.com/Vyrenbusiness-source/TETHRA/releases/latest).
2. Extract it anywhere.
3. Run `TETHRA.exe`.
4. Import `.osz` maps and play.

## Build from source

1. Install [Godot 4.7](https://godotengine.org/download).
2. Clone this repository and open `project.godot`, or run it directly: `godot --path .`
3. Export a pack: `godot --headless --path . --export-pack "Windows Desktop" TETHRA.pck`

## Credits

- Maps belong to their mappers.
- osu! is a trademark of ppy Pty Ltd. TETHRA is an independent project and is not affiliated with osu!.
- Star rating and pp: [rosu-pp](https://github.com/MaxOhn/rosu-pp).
- Built with [Godot Engine](https://godotengine.org).

## Deutsch

TETHRA ist ein 3D-Raumflug-Rhythmusspiel. Es liest osu!mania-4K-Beatmaps (`.osz`) mit exakter osu!-Wertung (ScoreV1), SV-Maps wie in lazer, Sterne und pp per rosu-pp, Replays, Multiplayer per Raum-Code und Auto-Updater.

**Installation:** Zip aus den [Releases](https://github.com/Vyrenbusiness-source/TETHRA/releases/latest) entpacken, `TETHRA.exe` starten, `.osz`-Maps importieren. Maps gehören ihren Mappern, osu! ist eine Marke von ppy.
