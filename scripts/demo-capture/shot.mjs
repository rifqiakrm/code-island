import { chromium } from 'playwright';
const url = 'file://' + process.argv[2];
const state = process.argv[3] || 'list';
const out = process.argv[4] || 'shot.png';
const theme = process.argv[5] || '';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1100, height: 1000 }, deviceScaleFactor: 2 });
await page.goto(url, { waitUntil: 'networkidle' });
await page.evaluate(({st,th}) => {
  // Kill the page's own auto-cycler so it can't overwrite our forced state.
  let id = setTimeout(()=>{}, 0);
  for (let k = 0; k <= id; k++) clearTimeout(k);
  window.setTimeout = () => 0;
  window.setInterval = () => 0;
  const shape = document.querySelector('.notch-shape');
  const states = ['list','perm','question','finished','plan','themes','mascots','jumpto','sound'];
  const heights = { idle:36 };
  states.forEach(s=>{
    const el = shape.querySelector('.state-'+s); if(!el){heights[s]=380;return;}
    const o=el.style.opacity,v=el.style.visibility,p=el.style.position;
    el.style.opacity='0';el.style.visibility='hidden';el.style.position='absolute';
    heights[s]=el.offsetHeight+4; el.style.opacity=o;el.style.visibility=v;el.style.position=p;
  });
  shape.dataset.state = st;
  shape.style.height = (heights[st]||380)+'px';
  if (th) { shape.dataset.theme = th; const tn = shape.querySelector('.theme-name'); if (tn) tn.textContent = th.charAt(0).toUpperCase()+th.slice(1); }
}, {st:state, th:theme});
await page.waitForTimeout(700);
const el = await page.$('.macbook');
await el.screenshot({ path: out });
await browser.close();
console.log('wrote', out);
