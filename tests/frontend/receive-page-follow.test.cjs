'use strict';
// Cost2: launched by receive_http_tests::live_native_page_follows_another_selection with its actual
// isolated Router and native capture, no restart. It never reaches another station: the origin must
// be the suite's own loopback server and every other request of the pages is aborted.
// Page A stays open on FT8 20m. Page B, in its own browser context and on its own socket, makes one
// band selection of that band as the live page check does: one POST /receive/select with action
// band, no mode, and the profile, boot, revisions and generation it reads from its own operating
// state. The tests run in order on the same boot: without a selection first, then with one, then a
// selection that does not end in success.
const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const {watchPage,rowKey}=require('../../tools/test/node/page-watch.cjs');
const origin=process.env.WSTX_PAGE_ORIGIN;
const LIVE_STATION_PORT='18081',BAND='20m',WINDOW=60000;

let browser,pageA,watchA,pageB;
const open=async()=>{
  const context=await browser.newContext({viewport:{width:1440,height:900}}),page=await context.newPage();
  await context.route('**/*',route=>route.request().url().startsWith(origin)?route.continue():route.abort());
  await page.goto(origin);await page.locator('#connection[data-state=connected]').waitFor();
  return page;
};
const generationOf=page=>page.evaluate(()=>typeof live==='undefined'?null:live?.generation??null);

before(async()=>{
  assert.ok(origin,'run through the Rust live native page test');
  const url=new URL(origin);
  assert.equal(url.hostname,'127.0.0.1','only the suite\'s own loopback server');
  assert.notEqual(url.port,LIVE_STATION_PORT,'never the live station');
  browser=await chromium.launch();
  pageA=await open();watchA=watchPage(pageA);
  // Page A starts receive on FT8 20m, as an operator does, and shows rows of a decoded period.
  await pageA.locator('#operating-band:enabled').waitFor({timeout:30000});
  await pageA.selectOption('#operating-band',BAND);
  await pageA.waitForFunction(band=>operatingState?.selection.band===band&&operatingState.selection.mode==='ft8'&&operatingState.operation?.result!=='pending'&&live?.job?.state==='running',BAND,{timeout:30000});
  await watchA.until('rows on page A',seen=>seen.rows.length>0,60000);
});
after(async()=>{await browser?.close();});

// Page B's one band selection of `band`, read from its own operating state; `change` alters the
// body before it is sent. Resolves once the operation ends in success; otherwise rejects naming
// the refusal's code or the operation's result and error.
async function selectFromB(page,band,change={}){
  await page.waitForFunction(band=>operatingState?.selection.band===band&&operatingState.operation?.result!=='pending'&&operatingState.receive.state==='running',band,{timeout:30000});
  const sent=await page.evaluate(async({band,change})=>{
    const s=operatingState;
    const body={v:1,profile_id:s.profile_id,boot_id:s.boot_id,command_id:crypto.randomUUID(),action:'band',profile_revision:s.profile_revision,generation:s.generation,operating_revision:s.operating_revision,band,...change};
    const response=await stationFetch('/receive/select',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
    return {status:response.status,reply:await response.json().catch(()=>null),command:body.command_id};
  },{band,change});
  if(sent.status!==202)throw new Error(`page B's selection was refused: ${sent.reply?.error?.code??`HTTP ${sent.status}`}`);
  const deadline=Date.now()+30000;
  for(;;){
    const op=await page.evaluate(async()=>(await (await stationFetch('/receive/selection',{cache:'no-store'})).json()).operation);
    if(op?.command_id===sent.command&&op.result!=='pending'){
      if(op.result==='success')return;
      throw new Error(`page B's selection ended ${op.result}: ${op.error??'no error named'}`);
    }
    if(Date.now()>=deadline)throw new Error(`page B's selection had no result within 30 s: ${JSON.stringify(op)}`);
    await page.waitForTimeout(250);
  }
}

// Without a selection page A's generation stays as it is while new rows arrive: new rows alone
// never meet the next test.
test('an open page without another session\'s selection keeps its generation while new rows arrive',{timeout:WINDOW+60000},async()=>{
  const generation=await generationOf(pageA),known=new Set(watchA.tips.keys());
  assert.ok(Number.isInteger(generation),`page A's generation: ${generation}`);
  let fresh=false;
  const end=Date.now()+WINDOW;
  while(Date.now()<end){
    const seen=await watchA.sample();
    assert.equal(seen.generation,generation,'page A\'s generation without a selection');
    if(seen.rows.some(r=>!known.has(rowKey(r))))fresh=true;
    await pageA.waitForTimeout(500);
  }
  assert.ok(fresh,'new rows arrived on page A');
});

// The path of the live page check: another session selects the band the station receives on.
test('an open page shows the generation raised by another session\'s band selection, with a new row',{timeout:WINDOW+120000},async()=>{
  pageB=await open();
  const generation=await generationOf(pageA),known=new Set(watchA.tips.keys());
  // Page A is judged only after page B's operation ended in success.
  await selectFromB(pageB,BAND);
  await watchA.until(`page A shows a generation above ${generation} with a new row`,seen=>Number.isInteger(seen.generation)&&seen.generation>generation&&seen.rows.some(r=>!known.has(rowKey(r))),WINDOW);
  assert.equal(watchA.verdict(),null,'nothing on page A reads like an accident');
});

// A selection by page B that does not end in success is a harness failure naming why, and page A
// is not judged: a stale generation is refused by the station.
test('a selection by the other session that does not end in success fails naming why and judges nothing',{timeout:60000},async()=>{
  assert.ok(pageB,'page B is open');
  let judged=false;
  await assert.rejects(selectFromB(pageB,BAND,{generation:0}).then(()=>{judged=true;}),/^Error: page B's selection was refused: state_conflict$/);
  assert.equal(judged,false);
});
