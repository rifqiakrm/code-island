import { chromium } from 'playwright';
import fs from 'fs';

const file = process.argv[2];
const W = parseInt(process.argv[3] || '1080');
const H = parseInt(process.argv[4] || '1080');
const outDir = process.argv[5] || './vid';
fs.mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: W, height: H },
  deviceScaleFactor: 1,
  recordVideo: { dir: outDir, size: { width: W, height: H } },
});
const page = await context.newPage();
await page.goto('file://' + file + '?record', { waitUntil: 'networkidle' });

// Read the loop duration straight from the page's own sequence so we capture
// exactly one full cycle (sum of all holds).
const loopMs = await page.evaluate(() => window.__loopMs || 0);
const dur = loopMs && loopMs > 1000 ? loopMs : 39500;
console.log('loop duration (ms):', dur);
// settle on first idle, then one full loop, then a hair extra for a clean wrap
await page.waitForTimeout(dur + 1200);

const video = page.video();
await context.close();
await browser.close();
const path = await video.path();
console.log('webm:', path);
