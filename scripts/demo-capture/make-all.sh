#!/bin/bash
set -e
F="$(cd ../../docs && pwd)/index.html"
mkdir -p out
# variant: name  W  H  scale  short(0|1)  makeGif(0|1)
variants=(
  "full-square 1080 1080 1.5 0 0"
  "full-4x5    1080 1350 1.5 0 0"
  "full-9x16   1080 1920 1.8 0 0"
  "short-square 1080 1080 1.5 1 1"
  "short-4x5    1080 1350 1.5 1 1"
  "short-9x16   1080 1920 1.8 1 1"
)
for v in "${variants[@]}"; do
  set -- $v; NAME=$1; W=$2; H=$3; SC=$4; SH=$5; GIF=$6
  echo "==> recording $NAME (${W}x${H} scale=$SC short=$SH)"
  rm -rf vid; OUT=$(node record.mjs "$F" $W $H ./vid $SC $SH)
  WEBM=$(echo "$OUT" | grep WEBM= | cut -d= -f2-)
  LOOPMS=$(echo "$OUT" | grep LOOPMS= | cut -d= -f2)
  T=$(awk "BEGIN{printf \"%.1f\", $LOOPMS/1000}")
  echo "    loop=${T}s -> mp4"
  ffmpeg -y -ss 0.6 -i "$WEBM" -t $T \
    -vf "fps=30,scale=${W}:${H}:flags=lanczos,format=yuv420p" \
    -c:v libx264 -crf 19 -preset slow -movflags +faststart \
    "out/code-island-${NAME// /}.mp4" -loglevel error
  if [ "$GIF" = "1" ]; then
    GW=$((W/2))
    ffmpeg -y -ss 0.6 -i "$WEBM" -t $T -vf "fps=14,scale=${GW}:-1:flags=lanczos,palettegen=stats_mode=diff" out/pal.png -loglevel error
    ffmpeg -y -ss 0.6 -i "$WEBM" -i out/pal.png -t $T \
      -lavfi "fps=14,scale=${GW}:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
      "out/code-island-${NAME// /}.gif" -loglevel error
  fi
done
rm -f out/pal.png
echo "=== done ==="
ls -lah out/*.mp4 out/*.gif 2>/dev/null | awk '{print $9, $5}'
