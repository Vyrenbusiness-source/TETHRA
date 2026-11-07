#!/bin/bash
# Misst einen Clip-Export (zweiter Prozess wie ClipExporter). Aufruf:
#   [RES=1280x720] [FPS=60] [CFG='[editor]\nmovie_writer/mjpeg_quality=0.5'] \
#     tools/clip_bench.sh <md5> <out.avi> [extra Godot-Args...]
# Gibt Wallzeit und Dateigroesse aus. Nur selbst-beendend (timeout 300).
G=${GODOT:-/c/Users/Gexanx/Desktop/rhyg/Godot_v4.7-stable_win64_console.exe}
md5=$1; out=${2:-/tmp/clip_bench.avi}; shift 2
cd "$(dirname "$0")/.." || exit 1
cp tools/test_override.cfg override.cfg
if [ -n "$CFG" ]; then printf "\n%b\n" "$CFG" >> override.cfg; fi
rm -f "$out"
t0=$(date +%s%N)
timeout 300 "$G" --path . --audio-driver Dummy --write-movie "$out" --fixed-fps "${FPS:-60}" --resolution "${RES:-1920x1080}" --position -1920,0 --clip "$md5" "$@" > /tmp/clip_bench.log 2>&1
t1=$(date +%s%N)
rm -f override.cfg
echo "wall=$(( (t1 - t0) / 1000000 )) ms  size=$(stat -c %s "$out" 2>/dev/null) bytes"
grep "recorded in" /tmp/clip_bench.log
