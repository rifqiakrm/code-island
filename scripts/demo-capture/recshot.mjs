import { chromium } from 'playwright';
const file = process.argv[2];
const state = process.argv[3] || 'list';
const out = process.argv[4] || 'rec.png';
const W = parseInt(process.argv[5]||'1080'), Hh = parseInt(process.argv[6]||'1080');
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: Hh }, deviceScaleFactor: 1 });
await page.goto('file://' + file + '?record', { waitUntil: 'networkidle' });
await page.evaluate((st) => {
  let id = setTimeout(()=>{},0); for (let k=0;k<=id;k++) clearTimeout(k);
  window.setTimeout=()=>0; window.setInterval=()=>0;
  const shape = document.querySelector('.notch-shape');
  const states=['list','perm','question','finished','themes','mascots','jumpto','sound'];
  const h={idle:36};
  states.forEach(s=>{const el=shape.querySelector('.state-'+s);if(!el){h[s]=380;return;}const o=el.style.opacity,v=el.style.visibility,p=el.style.position;el.style.opacity='0';el.style.visibility='hidden';el.style.position='absolute';h[s]=el.offsetHeight+4;el.style.opacity=o;el.style.visibility=v;el.style.position=p;});
  shape.dataset.state=st; shape.style.height=(h[st]||380)+'px';
  const cap=document.querySelector('.rec-cap'); if(cap) cap.innerHTML='<b>'+st+'</b>';
  if(st==='themes'){shape.dataset.theme='glass'; const tn=document.querySelector('.theme-name'); if(tn)tn.textContent='Glass';}
}, state);
await page.waitForTimeout(700);
await page.screenshot({ path: out });
await browser.close();
console.log('wrote', out);
