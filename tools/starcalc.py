#!/usr/bin/env python3
"""HOOKLINE: Star-Rating / pp / Max-Combo via rosu-pp-py (offizielle Bindings
der rosu-pp-Library — Masterplan Regel 9: NIEMALS Eigenberechnung).

Modi:
  starcalc.py --osz <pfad.osz>
      -> JSON: { "<innerer .osu-Name>": {"stars": .., "max_combo": .., "version": ..}, ... }
  starcalc.py --pp --osz <pfad.osz> --osu <innerer Name> \
      --n300 N --n100 N --n50 N --miss N --combo N
      -> JSON: {"pp": .., "stars": .., "max_combo": ..}

Nur Mode-0-Maps (osu!standard); andere werden uebersprungen/abgelehnt.
"""
import argparse
import json
import sys
import zipfile

import rosu_pp_py as rosu


def _load_beatmap(data: bytes):
    bm = rosu.Beatmap(bytes=data)
    return bm


def _is_osu_mode(bm) -> bool:
    """Standard und Mania werden unterstuetzt (TETHRA-Modi)."""
    try:
        return bm.mode in (rosu.GameMode.Osu, rosu.GameMode.Mania)
    except Exception:
        return True


def cmd_stars(osz_path: str) -> dict:
    out = {}
    with zipfile.ZipFile(osz_path) as z:
        for name in z.namelist():
            if not name.lower().endswith(".osu"):
                continue
            try:
                data = z.read(name)
                bm = _load_beatmap(data)
                if not _is_osu_mode(bm):
                    continue
                attrs = rosu.Difficulty().calculate(bm)
                version = ""
                for line in data.decode("utf-8", errors="replace").splitlines():
                    if line.strip().startswith("Version:"):
                        version = line.split(":", 1)[1].strip()
                        break
                out[name] = {
                    "stars": round(attrs.stars, 4),
                    "max_combo": attrs.max_combo,
                    "version": version,
                }
            except Exception as e:  # eine kaputte Diff soll den Rest nicht killen
                out[name] = {"error": str(e)}
    return out


def cmd_pp(osz_path: str, inner: str, n300: int, n100: int, n50: int,
           miss: int, combo: int, geki: int = 0, katu: int = 0) -> dict:
    with zipfile.ZipFile(osz_path) as z:
        data = z.read(inner)
    bm = _load_beatmap(data)
    diff = rosu.Difficulty().calculate(bm)
    # Mania: geki = MAX/320er (unsere PF), katu = 200er (unsere GD).
    kwargs = dict(n_geki=geki, n_katu=katu, n300=n300, n100=n100, n50=n50,
                  misses=miss, combo=combo)
    try:
        perf = rosu.Performance(lazer=False, **kwargs)  # Stable-Wertung
    except TypeError:
        perf = rosu.Performance(**kwargs)
    attrs = perf.calculate(bm)
    return {
        "pp": round(attrs.pp, 4),
        "stars": round(diff.stars, 4),
        "max_combo": diff.max_combo,
    }


def cmd_stars_dir(dir_path: str) -> dict:
    """Alle .osz eines Ordners in EINEM Prozess (vermeidet 90x Python-Start)."""
    import os
    out = {}
    for name in sorted(os.listdir(dir_path)):
        if not name.lower().endswith(".osz"):
            continue
        full = os.path.join(dir_path, name)
        try:
            out[name] = {"stars": cmd_stars(full), "size": os.path.getsize(full)}
        except Exception as e:
            out[name] = {"error": str(e)}
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--osz", default="")
    p.add_argument("--dir", default="")
    p.add_argument("--pp", action="store_true")
    p.add_argument("--osu", default="")
    p.add_argument("--n300", type=int, default=0)
    p.add_argument("--n100", type=int, default=0)
    p.add_argument("--n50", type=int, default=0)
    p.add_argument("--miss", type=int, default=0)
    p.add_argument("--combo", type=int, default=0)
    p.add_argument("--geki", type=int, default=0)
    p.add_argument("--katu", type=int, default=0)
    a = p.parse_args()
    try:
        if a.dir:
            result = cmd_stars_dir(a.dir)
        elif a.pp:
            result = cmd_pp(a.osz, a.osu, a.n300, a.n100, a.n50, a.miss,
                            a.combo, a.geki, a.katu)
        else:
            result = cmd_stars(a.osz)
        print(json.dumps(result))
        return 0
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
