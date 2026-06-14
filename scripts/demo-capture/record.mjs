import { chromium } from 'playwright';
import fs from 'fs';
// args: file W H outDir scale short(0|1) cine(0|1)
const file = process.argv[2];
const W = parseInt(process.argv[3]||'1080'), H = parseInt(process.argv[4]||'1080');
const outDir = process.argv[5]||'./vid', scale = process.argv[6]||'1.5';
const short = process.argv[7]==='1', cine = process.argv[8]==='1';
fs.mkdirSync(outDir, { recursive: true });
let q = '?record&scale=' + scale + (short ? '&short' : '') + (cine ? '&cine' : '');
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
await context.close(); await browser.close();
console.log('WEBM=' + await video.path());
console.log('LOOPMS=' + dur);
