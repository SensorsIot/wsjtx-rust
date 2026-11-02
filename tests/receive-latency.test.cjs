'use strict';
// Cost2: launched by receive_http_tests::live_native_busy_period_rows_promptly with its
// actual isolated Router and a real-time busy recording through the production live path.
// This browser driver only measures; the Rust test owns the latency and decode-set oracle.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const origin=process.env.WSTX_LATENCY_ORIGIN;

// Proves: CL-057-01; TC-057-001 (#57) browser-side timeline of the Detailed Band Activity.
test('TC-057-001 busy live period painted in Band Activity (Detailed) timeline',{timeout:150000},async()=>{
  assert.ok(origin,'run through the Rust live busy-period test');
  const browser=await chromium.launch();
  try{
    const page=await (await browser.newContext({viewport:{width:1440,height:900}})).newPage();
    const errors=[],frames=[],requests=[];page.on('pageerror',e=>errors.push(e.message));
    page.on('websocket',socket=>socket.on('framereceived',event=>{try{const m=JSON.parse(event.payload);if(m.type==='receive.state')frames.push({t:Date.now(),type:m.type});}catch{}}));
    page.on('request',r=>{const route=new URL(r.url()).pathname;if(['/receive','/receive/results'].includes(route))requests.push({t:Date.now(),route,phase:'start',query:new URL(r.url()).search});});
    page.on('requestfinished',r=>{const route=new URL(r.url()).pathname;if(['/receive','/receive/results'].includes(route))requests.push({t:Date.now(),route,phase:'end'});});
    await page.goto(origin);await page.locator('#connection[data-state=connected]').waitFor();
    assert.equal(await page.locator('#display-profile').inputValue(),'detail','Detailed is the LAN default');
    // Every Band Activity change: the displayed sequences and the header, at the next frame.
    await page.evaluate(()=>{
      window.__activity=[];const region=document.querySelector('#band-activity');
      const note=()=>requestAnimationFrame(()=>window.__activity.push({t:performance.timeOrigin+performance.now(),
        sequences:[...region.querySelectorAll('tbody tr[data-period=latest]')].map(r=>Number(r.dataset.sequence)),
        texts:[...region.querySelectorAll('tbody tr[data-period=latest] td[data-col=message]')].map(c=>c.textContent),
        header:region.querySelector('header .op-muted').textContent}));
      new MutationObserver(note).observe(region,{subtree:true,childList:true,characterData:true});
    });
    await page.locator('#exception-chips [data-chip=receive]').filter({hasText:'Receive stopped'}).click();
    // Two busy periods 30 s apart, each rows of at least 25 stations; then the late window.
    const busy=first=>document.querySelectorAll('#band-activity tbody tr[data-period=latest]').length>=25&&resultView.id!==first;
    await page.waitForFunction(busy,null,{timeout:60000});
    await page.waitForFunction(busy,await page.evaluate(()=>resultView.id),{timeout:60000});
    await page.waitForTimeout(4000);
    const activity=await page.evaluate(()=>window.__activity);
    assert.deepEqual(errors,[]);
    process.stdout.write(`WSTX_LATENCY_BROWSER ${JSON.stringify({activity,frames,requests})}\n`);
  }finally{await browser.close();}
});
