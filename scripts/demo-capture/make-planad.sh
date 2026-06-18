#!/bin/bash
# Plan-mode Apple-style commercial in 3 aspect ratios, with the 8-bit soundtrack.
# The track (71s) is longer than the ad (~32s), so we just take the first T
# seconds + fades — perfectly seamless, no loop boundary. Override MUSIC= to swap.
set -e
F="$(cd ../../docs && pwd)/index.html"
MUSIC="${MUSIC:-$HOME/Downloads/djartmusic-the-return-of-the-8-bit-era-301292.mp3}"
mkdir -p out
[ -f "$MUSIC" ] || { echo "music not found: $MUSIC (set MUSIC=...)"; exit 1; }
# name W H scale
variants=(
  "1x1  1080 1080 1.5"
  "4x5  1080 1350 1.5"
  "9x16 1080 1920 1.8"
)
for v in "${variants[@]}"; do
  set -- $v; NAME=$1; W=$2; H=$3; SC=$4
  echo "==> planad $NAME (${W}x${H})"
  rm -rf vid
  OUT=$(PLANAD=1 node record.mjs "$F" $W $H ./vid $SC 0 1)
  WEBM=$(echo "$OUT" | grep WEBM= | cut -d= -f2-)
  LOOPMS=$(echo "$OUT" | grep LOOPMS= | cut -d= -f2)
  T=$(awk "BEGIN{printf \"%.1f\", $LOOPMS/1000}")
  FO=$(awk "BEGIN{printf \"%.1f\", $LOOPMS/1000 - 2.0}")
  echo "    loop=${T}s -> mp4 + 8-bit bg"
  ffmpeg -y -ss 0.6 -i "$WEBM" -i "$MUSIC" -t "$T" \
    -vf "fps=30,scale=${W}:${H}:flags=lanczos,format=yuv420p" \
    -af "afade=t=in:st=0:d=0.5,afade=t=out:st=${FO}:d=2.0,volume=0.5" \
    -map 0:v:0 -map 1:a:0 \
    -c:v libx264 -crf 19 -preset slow -movflags +faststart \
    -c:a aac -b:a 160k -shortest \
    "out/code-island-planad-${NAME}.mp4" -loglevel error
done
echo "=== done ==="
ls -lah out/code-island-planad-*.mp4 | awk '{print $9, $5}'
