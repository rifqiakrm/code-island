# Demo capture

Tooling to record the website's live notch recreation (`docs/index.html`) as a
social-ready video. The page has a `?record` mode that hides all chrome and
shows only the notch morphing through every state on a clean wallpaper canvas.

## Setup

```bash
npm install
npx playwright install chromium
```

## Record a square (1080×1080) loop → MP4 + GIF

```bash
F="$(cd ../../docs && pwd)/index.html"
node record.mjs "$F" 1080 1080 ./vid          # captures one full loop → vid/*.webm
WEBM=$(ls vid/*.webm | head -1)
mkdir -p out
ffmpeg -y -ss 0.6 -i "$WEBM" -t 39.5 -vf "fps=30,scale=1080:1080:flags=lanczos,format=yuv420p" \
  -c:v libx264 -crf 19 -preset slow -movflags +faststart out/code-island-demo-1080.mp4
ffmpeg -y -ss 0.6 -i "$WEBM" -t 39.5 -vf "fps=14,scale=540:-1:flags=lanczos,palettegen=stats_mode=diff" out/pal.png
ffmpeg -y -ss 0.6 -i "$WEBM" -i out/pal.png -t 39.5 \
  -lavfi "fps=14,scale=540:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" out/code-island-demo.gif
```

Adjust `-t` if you change the sequence holds in `docs/index.html` (the page
exposes the exact loop length as `window.__loopMs`).

- `shot.mjs <file> <state> <out.png> [theme]` — single still of one state.
- `recshot.mjs <file> <state> <out.png> [W] [H]` — still of the `?record` canvas.

Portrait: pass `1080 1350` to `record.mjs` and scale the mp4 to `1080:1350`.
