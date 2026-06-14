import { chromium } from 'playwright';
import fs from 'fs';
// args: file W H outDir scale short(0|1)
const [file, W, H, outDir, scale, short] = [
  process.argv[2], parseInt(process.argv[3]||'1080'), parseInt(process.argv[4]||'1080'),
  process.argv[5]||'./vid', process.argv[6]||'1.5', process.argv[7]==='1'
];
fs.mkdirSync(outDir, { recursive: true });
let q = '?record&scale=' + scale + (short ? '&short' : '');
const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: W, height: H }, deviceScaleFactor: 1,
  recordVideo: { dir: outDir, size: { width: W, height: H } },
});
const page = await context.newPage();
await page.goto('file://' + file + q, { waitUntil: 'networkidle' });
const loopMs = await page.evaluate(() => window.__loopMs || 0);
const dur = loopMs > 1000 ? loopMs : 39500;
await page.waitForTimeout(dur + 1200);
const video = page.video();
await context.close();
await browser.close();
const path = await video.path();
console.log('WEBM=' + path);
console.log('LOOPMS=' + dur);
