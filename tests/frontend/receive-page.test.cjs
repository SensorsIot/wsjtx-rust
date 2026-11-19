'use strict';
// Cost2: launched by receive_http_tests::live_native_page_kept_across_restart with its actual
// isolated Router and native capture. It never reaches another station: the origin must be
// the suite's own loopback server and every other request of the page is aborted.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {chromium}=require('playwright');
const {watchPage,tipChange}=require('../page-watch.cjs');
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

// The oracle itself goes red: a fixture page with the accident and the changed tip it must find.
test('the page watch fails on undefined and on a changing tip, and passes what may change',{timeout:60000},async()=>{
  const n='New on 20m',w=`${n} (worked on another band or mode)`;
  assert.equal(tipChange(n,w),null,'the worked-before status joins once');
  assert.ok(tipChange(w,n),'#50: it must not go again');
  assert.ok(tipChange(null,n),'a reason must not appear');
  assert.equal(tipChange(`New call · Strategy New calls: #2`,`New call · Strategy New calls: #4`),null,'the rank moves with the rows on screen');
  assert.equal(tipChange(null,'Strategy New calls: #1'),null,'the verdict joins after the evaluation');
  assert.ok(tipChange(`New call · Strategy New calls: #2`,`Strategy New calls: #2`),'a reason beside the verdict must not go');
  const browser=await chromium.launch();
  try{
    const page=await browser.newPage(),watch=watchPage(page);
    await page.setContent(`<section id="band-activity"><table><tbody><tr data-sequence="1" data-period="latest" data-tip="${n}"><td>08:00:00</td><td data-col="message">CQ K1ABC FN42</td></tr></tbody></table></section>`);
    await watch.sample();
    assert.equal(watch.verdict(),null,'the plain page passes');
    await page.evaluate(()=>{document.querySelector('tr').dataset.tip='New on undefined';});
    await watch.sample();
    assert.match(watch.verdict(),/undefined/);
    assert.equal(watch.changes.length,1);
  }finally{await browser.close();}
});

// The live check's two decisions, without a station: what the page may send, and when it is green.
test('the live page check lets the page send only reads and is green only with both triggers',()=>{
  const {allowed,missingTriggers}=require('../live-page-check.cjs');
  const origin='https://192.168.0.37:18081',at=p=>new URL(origin+p);
  assert.equal(allowed('GET',at('/receive'),origin),'pass');
  for(const p of ['/contact/worked','/strategy/evaluate','/authorization/v1/status'])assert.equal(allowed('POST',at(p),origin),'pass',p);
  for(const p of ['/transmit/command','/transmit/halt','/contact/command','/automation/command','/receive/select','/receive/start','/radio/operation','/radio/settings/apply','/radio/tx-level','/profile','/session'])
    assert.equal(allowed(p==='/profile'?'PUT':'POST',at(p),origin),'refuse',p);
  assert.equal(allowed('GET',new URL('https://example.org/x'),origin),'abort');
  assert.equal(allowed('GET',new URL('https://192.168.0.37:18082/receive'),origin),'abort');
  assert.equal(allowed('GET',at('/authorization.js'),origin),'stub');
  assert.deepEqual(missingTriggers(2,null,true),[],'no job yet on the new boot');
  assert.deepEqual(missingTriggers(2,1,true),[],'below the old generation');
  assert.equal(missingTriggers(1,1,true).length,1,'an equal generation is not the #22 window');
  assert.equal(missingTriggers(null,null,true).length,1,'no old generation seen');
  assert.equal(missingTriggers(2,null,false).length,1,'#50 needs a worked-before kept row');
});

// The live check's wait between its band selection and the stop, on a scripted page.
const row=(when,message)=>({period:'latest',tip:null,when,message,sender:message.split(' ')[1],partner:false});
const shown=(generation,rows)=>({text:'',heading:'',attributes:[],rows,band:'20m',on:'1',boot:'b1',state:'connected',job:'j',generation});
// A page that shows each of `states` once per sample and stays on the last; `rowsAt` is the first
// sample taken once <control>/rows exists.
function scriptedPage(states,control){
  let i=0;const page={rowsAt:null,shownAt:[],on(){},waitForTimeout:ms=>new Promise(r=>setTimeout(r,Math.min(ms,5))),
    evaluate:async()=>{const n=i++;if(page.rowsAt===null&&fs.existsSync(path.join(control,'rows')))page.rowsAt=n;page.shownAt.push(n);return states[Math.min(n,states.length-1)];}};
  return page;
}
// The script's lines: each message once the condition before it holds.
function scriptedLines(steps){return {poll:()=>{if(steps.length&&steps[0][0]()){return steps.shift()[1];}}};}
async function stopAfter(states,messages){
  const {awaitStop}=require('../live-page-check.cjs');
  const control=fs.mkdtempSync(path.join(os.tmpdir(),'wstx-live-page-check-'));
  try{
    const page=scriptedPage(states,control),watch=watchPage(page);
    await watch.sample();
    const rows=()=>fs.existsSync(path.join(control,'rows'));
    const result=await awaitStop({watch,lines:scriptedLines(messages(rows)),control,clean:()=>{},wait:1000,pause:ms=>page.waitForTimeout(ms)});
    return {...result,page,rows:rows()};
  }finally{fs.rmSync(control,{recursive:true,force:true});}
}

test('the live page check lets the station stop only after a raised generation with new rows',async()=>{
  const {raisedWithRows}=require('../live-page-check.cjs');
  const a=row('12:00:00','CQ K1ABC FN42'),b=row('12:00:30','CQ F5RRS JN18'),known=new Set(['12:00:00 CQ K1ABC FN42']);
  assert.equal(raisedWithRows(shown(1,[a,b]),1,known),false,'an equal generation, even with new rows');
  assert.equal(raisedWithRows(shown(2,[a]),1,known),false,'a raised generation with only the rows seen before');
  assert.equal(raisedWithRows(shown(2,[]),1,known),false,'a raised generation without rows');
  assert.equal(raisedWithRows(shown(2,[a,b]),1,known),true);
  // Selected at generation 1: the page shows generation 2 without rows, then with a new row (sample 4).
  const states=[shown(1,[a]),shown(1,[a]),shown(2,[]),shown(2,[]),shown(2,[a,b])];
  const done=await stopAfter(states,rows=>[[()=>true,{selected:{generation:1,ms:30000}}],[rows,{stopping:true}]]);
  assert.deepEqual(done.message,{stopping:true});
  assert.deepEqual(done.unexercised,[]);
  assert.equal(done.last.generation,2);
  assert.ok(done.page.rowsAt>4,`rows reported at sample ${done.page.rowsAt}, the new row first shown at sample 4`);
});

test('the live page check without rows of the raised generation within the wait: not exercised, naming the wait, and the stop goes on',async()=>{
  const a=row('12:00:00','CQ K1ABC FN42');
  const done=await stopAfter([shown(1,[a]),shown(2,[a])],rows=>[[()=>true,{selected:{generation:1,ms:1000}}],[rows,{stopping:true}]]);
  assert.deepEqual(done.message,{stopping:true},'the restart is made');
  assert.deepEqual(done.unexercised,['no rows of a generation above 1 on the page within 1 s of the band selection']);
  const {exerciseMissing}=require('../live-page-check.cjs');
  assert.match(exerciseMissing(done.unexercised,2,1,true).join('\n'),/^#22: no rows of a generation above 1/,'never green');
});

test('the live page check is never green after a band selection not made or not taken',async()=>{
  const {exerciseMissing}=require('../live-page-check.cjs');
  const why='no band selection: Monitor off at startup is set';
  const done=await stopAfter([shown(1,[row('12:00:00','CQ K1ABC FN42')])],()=>[[()=>true,{unexercised:why}],[()=>true,{stopping:true}]]);
  assert.deepEqual(done.message,{stopping:true});
  assert.deepEqual(done.unexercised,[why]);
  assert.equal(done.rows,false,'no wait for rows without a selection');
  // The new boot without a job is the restart-generation window by the generations alone, but nothing was selected.
  assert.deepEqual(exerciseMissing([why],1,null,true),[`#22: ${why}`]);
  assert.deepEqual(exerciseMissing([],2,1,true),[],'a selection that took, generations old 2 and new 1');
});
