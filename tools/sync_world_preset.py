"""Schreibt export_presets.cfg neu: Preset "Windows" ohne assets_game/themes/,
Preset "Worlds" nur mit allen Welt-Texturen (assets_game/themes/**.webp/png/jpg).
Nach jeder neuen Welt ausfuehren:  python tools/sync_world_preset.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG = ROOT / "export_presets.cfg"
EXT = {".webp", ".png", ".jpg"}


def world_files():
    base = ROOT / "assets_game" / "themes"
    return sorted("res://" + p.relative_to(ROOT).as_posix()
                  for p in base.rglob("*") if p.suffix.lower() in EXT)


def main():
    s = CFG.read_text(encoding="utf-8")
    # Hauptpaket: Welten-Assets raus.
    s = re.sub(r'exclude_filter="[^"]*"', 'exclude_filter="maps/*, release/*, *.exe, assets_game/themes/*"', s, count=1)
    # Welten-Preset (preset.1) abschneiden und neu anhaengen.
    cut = s.find("\n[preset.1]")
    if cut >= 0:
        s = s[:cut]
    s = s.rstrip("\n") + "\n"
    files = ", ".join('"%s"' % f for f in world_files())
    opts = s[s.index("[preset.0.options]"):]
    opts = opts.replace("[preset.0.options]", "[preset.1.options]")
    p1 = (
        '\n[preset.1]\n\nname="Worlds"\nplatform="Windows Desktop"\nrunnable=false\n'
        'advanced_options=false\ndedicated_server=false\ncustom_features=""\n'
        'export_filter="resources"\nexport_files=PackedStringArray(%s)\n'
        'include_filter=""\nexclude_filter=""\nexport_path="release/TETHRA_worlds.pck"\n'
        'patches=PackedStringArray()\nencryption_include_filters=""\nencryption_exclude_filters=""\n'
        'seed=0\nencrypt_pck=false\nencrypt_directory=false\nscript_export_mode=2\n\n' % files
    )
    CFG.write_text(s + p1 + opts, encoding="utf-8", newline="\n")
    print("Welten-Dateien:", len(world_files()))


main()
