#!/usr/bin/env bash
# Ausweich-Quelle fuer den Updater: Branch "dist" mit latest.json und TETHRA.pck
# in Teilen unter 20 MB (raw.githubusercontent.com und jsDelivr liefern sie aus,
# auch wenn GitHub-Release-Downloads oder die API haengen).
# Aufruf nach jedem Release:  bash tools/publish_dist.sh "<Release-Notes>"
set -euo pipefail
cd "$(dirname "$0")/.."
PCK=release/TETHRA.pck
[ -f "$PCK" ] || { echo "FAIL $PCK fehlt"; exit 1; }
VER="$(sed -n 's/^const CURRENT_VERSION := "\(.*\)"/\1/p' scripts/net/updater.gd)"
[ -n "$VER" ] || { echo "FAIL Version nicht gefunden"; exit 1; }
NOTES="${1:-}"
PART=$((15 * 1024 * 1024))
WT="$(mktemp -d)"
trap 'git worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"' EXIT
git fetch -q origin dist 2>/dev/null || true
git worktree add -q --detach "$WT"
(
  cd "$WT"
  git checkout -q --orphan dist-new
  git rm -rqf . >/dev/null 2>&1 || true
  rm -rf ./* 2>/dev/null || true
)
split -b "$PART" -d -a 3 "$PCK" "$WT/TETHRA.pck."
SHA="$(sha256sum "$PCK" | cut -d' ' -f1)"
SIZE="$(stat -c %s "$PCK")"
python - "$WT" "$VER" "$SHA" "$SIZE" "$NOTES" <<'PY'
import json, os, sys
wt, ver, sha, size, notes = sys.argv[1:6]
parts = sorted(f for f in os.listdir(wt) if f.startswith("TETHRA.pck."))
d = {"version": ver, "size": int(size), "sha256": sha, "notes": notes,
     "parts": [{"name": f, "size": os.path.getsize(os.path.join(wt, f))} for f in parts]}
assert sum(p["size"] for p in d["parts"]) == int(size)
open(os.path.join(wt, "latest.json"), "w", encoding="utf-8").write(json.dumps(d, ensure_ascii=False, indent=1))
PY
(
  cd "$WT"
  git add -A
  git commit -qm "dist v$VER"
  git push -qf origin HEAD:dist
)
# jsDelivr-Cache fuer den Branch leeren (sonst bis zu 12 h alt)
curl -s -o /dev/null "https://purge.jsdelivr.net/gh/Vyrenbusiness-source/TETHRA@dist/latest.json" || true
echo "OK dist v$VER ($SIZE B, $(ls "$WT"/TETHRA.pck.* | wc -l) Teile)"
