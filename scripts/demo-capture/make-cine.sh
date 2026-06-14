#!/bin/bash
set -e
F="$(cd ../../docs && pwd)/index.html"
mkdir -p out
# name W H scale
variants=(
  "cine-1x1  1080 1080 1.5"
  "cine-4x5  1080 1350 1.5"
  "cine-9x16 1080 1920 1.8"
)
for v in "${variants[@]}"; do
  set -- $v; NAME=$1; W=$2; H=$3; SC=$4
  echo "==> $NAME (${W}x${H})"
  rm -rf vid; OUT=$(node record.mjs "$F" $W $H ./vid $SC 0 1)
  WEBM=$(echo "$OUT" | grep WEBM= | cut -d= -f2-); LOOPMS=$(echo "$OUT" | grep LOOPMS= | cut -d= -f2)
  T=$(awk "BEGIN{printf \"%.1f\", $LOOPMS/1000}"); echo "    loop=${T}s"
  ffmpeg -y -ss 0.6 -i "$WEBM" -t $T -vf "fps=30,scale=${W}:${H}:flags=lanczos,format=yuv420p" \
    -c:v libx264 -crf 19 -preset slow -movflags +faststart "out/code-island-${NAME}.mp4" -loglevel error
done
echo "=== done ==="; ls -lah out/code-island-cine-*.mp4 | awk '{print $9,$5}'
