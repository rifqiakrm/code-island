import { chromium } from 'playwright';
const file = process.argv[2], mode = process.argv[3]||'feature', out = process.argv[4]||'cine.png';
const W = parseInt(process.argv[5]||'1080'), H = parseInt(process.argv[6]||'1080'), SC = process.argv[7]||'1.5';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
await page.goto('file://' + file + '?record&cine&scale=' + SC, { waitUntil: 'networkidle' });
await page.evaluate((mode) => {
  let id=setTimeout(()=>{},0); for(let k=0;k<=id;k++) clearTimeout(k);
  window.setTimeout=()=>0; window.setInterval=()=>0;
  const shape=document.querySelector('.notch-shape');
  const states=['list','perm','question','finished','themes','mascots','jumpto','sound'];
  const h={idle:36};
  states.forEach(s=>{const el=shape.querySelector('.state-'+s);if(!el){h[s]=380;return;}const o=el.style.opacity,v=el.style.visibility,p=el.style.position;el.style.opacity='0';el.style.visibility='hidden';el.style.position='absolute';h[s]=el.offsetHeight+4;el.style.opacity=o;el.style.visibility=v;el.style.position=p;});
  const card=document.querySelector('.cine-card'), head=document.querySelector('.cine-headline');
  if (mode==='intro') {
    shape.style.opacity='0';
    card.innerHTML='<img src="assets/logo.png" alt=""/><div class="ct">Code Island</div><div class="cs">your notch, reimagined.</div>';
    card.classList.add('show');
  } else if (mode==='outro') {
    shape.style.opacity='0';
    card.innerHTML='<img src="assets/logo.png" alt=""/><div class="ct">Code Island</div><div class="cs">17 AI coding agents · one notch</div><div class="cu">free &amp; open source — github.com/rifqiakrm/code-island</div>';
    card.classList.add('show');
  } else {
    shape.style.opacity='1'; shape.dataset.state='mascots'; shape.style.height=h['mascots']+'px';
    head.innerHTML='17 agents.<br>17 mascots.'; head.classList.add('in');
  }
}, mode);
await page.waitForTimeout(1300);
await page.screenshot({ path: out });
await browser.close(); console.log('wrote', out);
