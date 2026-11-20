'use strict';
// Cost2: launched by receive_http_tests::live_native_page_kept_across_restart with its actual
// isolated Router and native capture. It never reaches another station: the origin must be
// the suite's own loopback server and every other request of the page is aborted.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {chromium}=require('playwright');
const {watchPage}=require('../../tools/test/node/page-watch.cjs');
const origin=process.env.WSTX_PAGE_ORIGIN,control=process.env.WSTX_PAGE_CONTROL;
const LIVE_STATION_PORT='18081';

// After a real restart with
// no receive job yet the page shows nothing of the previous boot and no undefined or NaN anywhere.
// A row's tip stays the same when
// the next period moves it to the kept period.
// Proves: TC-050-008
test('TC-050-008 a page kept across a restart and periods shows no accident and keeps its row tips',{timeout:300000},async()=>{
  assert.ok(origin&&control,'run through the Rust live native page test');
  const url=new URL(origin);
  assert.equal(url.hostname,'127.0.0.1','only the suite\'s own loopback server');
  assert.notEqual(url.port,LIVE_STATION_PORT,'never the live station');
  const browser=await chromium.launch();
  try{
    const context=await browser.newContext({viewport:{width:1440,height:900}}),page=await context.newPage();
    await context.route('**/*',route=>route.request().url().startsWith(origin)?route.continue():route.abort());
    const {sample,until,accidents,changes,worked,errors,commands}=watchPage(page);
    const start=async band=>{
      await page.locator('#operating-band:enabled').waitFor({timeout:30000});
      await page.selectOption('#operating-band',band);
      await page.waitForFunction(band=>operatingState?.selection.band===band&&operatingState.operation?.result!=='pending'&&live?.job?.state==='running',band,{timeout:30000});
    };
    const periods=seen=>new Set(seen.rows.map(r=>r.when)).size;

    await page.goto(origin);await page.locator('#connection[data-state=connected]').waitFor();
    const firstBoot=(await sample()).boot;
    // Two starts, so that this boot's generation is above the next boot's 0.
    await start('40m');const before=await page.evaluate(()=>live.generation);
    await start('20m');assert.ok(await page.evaluate(()=>live.generation)>before,'the band change raised the generation');
    // Two published periods on screen: the first period's rows have moved to the kept period.
    await until('two periods on screen',seen=>periods(seen)>=2&&seen.rows.some(r=>r.period==='latest')&&seen.rows.some(r=>r.period!=='latest'),120000);
    await until('the worked-before status on a kept row',()=>worked.kept>0,45000);

    // The real restart: every connection, the receive owner and the boot go, on the same port.
    fs.writeFileSync(path.join(control,'restart'),'');
    await until('the page sees the station gone',seen=>seen.state!=='connected',30000);
    await until('the page is back on the new boot',seen=>seen.state==='connected'&&seen.boot&&seen.boot!==firstBoot&&!seen.rows.length,60000);
    assert.ok(fs.existsSync(path.join(control,'restarted')),'the new boot answers only after the restart');
    // No receive job yet: the window where a faulty page shows "Latest undefined period" with the old boot's rows.
    const quiet=Date.now()+8000;
    while(Date.now()<quiet){const seen=await sample();assert.deepEqual([[...accidents.keys()],seen.rows],[[],[]],'no accident and no row of the previous boot');await page.waitForTimeout(500);}

    await start('20m');
    await until('a period of the new boot',seen=>periods(seen)>=1,60000);
    const end=Date.now()+5000;
    while(Date.now()<end){await sample();await page.waitForTimeout(500);}

    assert.ok(worked.latest>0&&worked.kept>0,`the worked-before tip was seen in both periods: ${JSON.stringify(worked)}`);
    assert.deepEqual([...accidents.keys()],[],'no undefined or NaN in text or tips');
    assert.deepEqual(changes,[],'no row tip changed without cause');
    assert.deepEqual(errors,[]);
    // Starting receive and the worked-before query, nothing else: no transmit, contact or radio command.
    assert.deepEqual([...new Set(commands)].filter(p=>!['/receive/select','/contact/worked'].includes(p)),[],'commands the page sent');
  }finally{await browser.close();}
});
