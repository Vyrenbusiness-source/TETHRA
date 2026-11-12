#!/bin/bash
# Demo-Video eines Modus aufnehmen (Godot Movie Maker + ffmpeg). Aufruf:
#   tools/record_demo.sh <mania|orbit|rally|dirigent|trace|rebound> <map-teil> <start_ms> [laenge_s=22] [ausgabe=docs/media/<modus>]
# Schreibt <ausgabe>.mp4 (H.264, 1280x720, 60 fps, AAC) und <ausgabe>_anim.webp
# (stumm, 6 s, 640 px). Nur selbst-beendend (timeout), kein Godot danach offen.
# Godot-Rohfilm: /tmp/demo_<modus>.avi (Marker MOVIE_START frame=<n> im Log).
G=${GODOT:-/c/Users/Gexanx/Desktop/rhyg/Godot_v4.7-stable_win64_console.exe}
FF=${FFMPEG:-/c/Users/Gexanx/Desktop/rhyg/release/stage/ffmpeg.exe}
mode=$1; map=$2; from=$3; len=${4:-22}; out=${5:-docs/media/$mode}
cd "$(dirname "$0")/.." || exit 1
avi=/tmp/demo_$mode.avi; log=/tmp/demo_$mode.log
cp tools/test_override.cfg override.cfg
rm -f "$avi"
case $mode in
mania) extra=(--mania --map="$map") ;;  # unveraendert gespielt (45-s-Watchdog), <start_ms> = Filmzeit
orbit) extra=(--orbit-map="$map" --shot --shot-at="$from" --movie-len="$len") ;;
rally) extra=(--rally-map="$map" --shot --shot-at="$from" --movie-len="$len") ;;
trace) extra=(--trace-map="$map" --shot --shot-at="$from" --movie-len="$len") ;;
rebound) extra=(--rebound-map="$map" --shot --shot-at="$from" --movie-len="$len") ;;
dirigent) extra=(--dirigent-map="$map" --movie-from="$from" --movie-len="$len") ;;
esac
timeout 400 "$G" --path . --audio-driver Dummy --write-movie "$avi" --fixed-fps 60 --resolution 1280x720 \
	--position -1920,0 res://scenes/song_select.tscn --mode=$mode --autoplay "${extra[@]}" > "$log" 2>&1
rm -f override.cfg
fr=$(grep -o 'MOVIE_START frame=[0-9]*' "$log" | head -1 | grep -o '[0-9]*$')
if [ "$mode" = mania ]; then ss=$(awk "BEGIN{printf \"%.4f\", $from/1000}")
elif [ -z "$fr" ]; then echo "kein MOVIE_START, siehe $log"; exit 1
else ss=$(awk "BEGIN{printf \"%.4f\", $fr/60}"); fi
"$FF" -v error -y -ss "$ss" -i "$avi" -t "$len" -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p -r 60 \
	-c:a aac -b:a 160k -movflags +faststart "$out.mp4"
"$FF" -v error -y -i "$out.mp4" -ss 4 -t 6 -vf "fps=15,scale=640:-1:flags=lanczos" -an -c:v libwebp_anim -q:v 55 -loop 0 "${out}_anim.webp"
ls -l "$out.mp4" "${out}_anim.webp"
