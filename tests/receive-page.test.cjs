'use strict';
// Cost2: launched by receive_http_tests::live_native_page_kept_across_restart with its actual
// isolated Router and native capture. It never reaches another station: the origin must be
// the suite's own loopback server and every other request of the page is aborted.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {chromium}=require('playwright');
const origin=process.env.WSTX_PAGE_ORIGIN,control=process.env.WSTX_PAGE_CONTROL;
const LIVE_STATION_PORT='18081';

// What a page shows must never read like a programming accident (#22, "Latest undefined period").
const ACCIDENT=/\bundefined\b|\bNaN\b/;
// A row keeps its tip while it is on screen. The worked-before status joins it once, when the
// period's one query is answered; nothing else in this test can change a tip (no QSO, no setting).
const WORKED=/ \(worked [^)]*\)/;
function tipChange(before,after){
  if(before===after)return null;
  const bare=t=>(t??'').replace(WORKED,'');
  return bare(before)===bare(after)&&!WORKED.test(before??'')?null:`"${before}" -> "${after}"`;
}

// Proves: CL-057-03; TC-007-002 (#22, live 2026-11-06, "Latest undefined period"): after a real restart with
// no receive job yet the page shows nothing of the previous boot and no undefined or NaN anywhere.
// Proves: CL-050-08; TC-050-008 (#50, live 2026-11-06, M7OZL UT4PA KO20): a row's tip stays the same when
// the next period moves it to the kept period.
test('TC-007-002 TC-050-008 a page kept across a restart and periods shows no accident and keeps its row tips',{timeout:300000},async()=>{
  assert.ok(origin&&control,'run through the Rust live native page test');
  const url=new URL(origin);
  assert.equal(url.hostname,'127.0.0.1','only the suite\'s own loopback server');
  assert.notEqual(url.port,LIVE_STATION_PORT,'never the live station');
  const browser=await chromium.launch();
  try{
    const context=await browser.newContext({viewport:{width:1440,height:900}}),page=await context.newPage();
    const errors=[],accidents=new Map(),tips=new Map(),changes=[],worked={latest:0,kept:0},commands=[];
    await context.route('**/*',route=>route.request().url().startsWith(origin)?route.continue():route.abort());
    page.on('pageerror',e=>errors.push(e.message));
    page.on('request',r=>{if(r.method()!=='GET')commands.push(new URL(r.url()).pathname);});
    const read=()=>page.evaluate(()=>({
      text:document.body.innerText,
      heading:document.querySelector('#band-activity header')?.innerText??'',
      attributes:[...document.querySelectorAll('[title],[aria-label],[aria-description],[data-tip]')].flatMap(el=>['title','aria-label','aria-description','data-tip'].map(a=>el.getAttribute(a)).filter(Boolean)),
      rows:[...document.querySelectorAll('#band-activity tbody tr[data-sequence]')].map(row=>({period:row.dataset.period,tip:row.dataset.tip??null,when:row.querySelector('td')?.textContent,message:row.querySelector('td[data-col=message]')?.textContent})),
      band:typeof operatingState==='undefined'?null:operatingState?.selection?.band??null,on:document.querySelector('#band-activity')?.dataset.hlOn,
      boot:typeof profileData==='undefined'?null:profileData?.boot_id,
      state:document.querySelector('#connection')?.dataset.state,
      job:typeof live==='undefined'?null:live?.job?.id??null,
    }));
    const sample=async()=>{
      const seen=await read();
      for(const text of [seen.text,...seen.attributes])if(ACCIDENT.test(text)){const line=text.split('\n').find(l=>ACCIDENT.test(l)).trim();accidents.set(line,(accidents.get(line)??0)+1);}
      for(const row of seen.rows){
        const key=`${row.when} ${row.message}`,change=tips.has(key)?tipChange(tips.get(key),row.tip):null;
        if(change)changes.push(`${key} (${row.period}): ${change}`);
        tips.set(key,row.tip);
        if(WORKED.test(row.tip??''))worked[row.period==='latest'?'latest':'kept']++;
      }
      return seen;
    };
    const until=async(what,done,timeout)=>{
      const deadline=Date.now()+timeout;
      for(;;){
        const seen=await sample();
        if(done(seen))return seen;
        assert.ok(Date.now()<deadline,`${what}: ${JSON.stringify({changes:changes.slice(0,4),accidents:[...accidents.keys()],heading:seen.heading,state:seen.state,job:seen.job,rows:seen.rows.length,sample:seen.rows.filter(r=>r.tip).slice(0,4),worked,periods:[...new Set(seen.rows.map(r=>r.period))],band:seen.band,on:seen.on})}`);
        await page.waitForTimeout(500);
      }
    };
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
    // No receive job yet: this window showed "Latest undefined period" with the old boot's rows.
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
