'use strict';
// Cost2: launched by receive_http_tests with its actual isolated candidate Router
// and actual native-packet fixture. No browser route interception or fake result.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const {chromium}=require('playwright');
const origin=process.env.WSTX_RECEIVE_FIXTURE_ORIGIN;
const expected=JSON.parse(process.env.WSTX_RECEIVE_FIXTURE_EXPECTED||'null');

// Proves: CL-008-02/03/05; CL-010-05/07/08; TC-009-004.
test('TC-009-004 real native audio reaches Rust manager HTTP and literal browser callsign',{timeout:60000},async()=>{
  assert.ok(origin&&expected,'run through the Rust live_native_fixture_reaches_real_manager_http_and_browser_callsign test');
  const browser=await chromium.launch();
  try{
    const context=await browser.newContext({viewport:{width:1440,height:900}}),page=await context.newPage();
    const errors=[],pages=[];page.on('pageerror',e=>errors.push(e.message));
    page.on('request',request=>{if(request.url().includes('/receive/results'))pages.push({url:request.url(),at:performance.now()});});
    await page.goto(origin);await page.locator('#connection[data-state=connected]').waitFor();
    await page.locator('#recorded-input > summary').click();
    await page.selectOption('#display-profile','thin');
    await page.locator('#recorded-input > summary').click();
    // A refused request is a negative transport fixture, never decoder evidence.
    await page.route('**/receive/start',route=>route.abort('failed'));
    await page.getByRole('button',{name:'Start receive',exact:true}).click();
    await page.locator('#receive-status').filter({hasText:'Start outcome unknown'}).waitFor();
    assert.equal(await page.getByRole('button',{name:'Start receive',exact:true}).isDisabled(),true);
    assert.equal((await (await fetch(origin+'/receive')).json()).job,null,'a refused browser mutation never activates the input');
    await page.unroute('**/receive/start');
    await page.getByRole('button',{name:'Refresh status',exact:true}).click();
    await page.waitForFunction(()=>!document.querySelector('#receive-start').disabled);
    await page.getByRole('button',{name:'Start receive',exact:true}).click();
    const row=page.locator('#band-activity tbody tr[data-result-id]').filter({hasText:'CQ K1ABC FN42'});
    await row.waitFor({timeout:45000});
    assert.equal(await row.count(),1);
    assert.match(await page.locator('#rx-focus').innerText(),/No contact selected/);
    assert.doesNotMatch(await page.locator('#rx-focus').innerText(),/Decoder unavailable/);
    const snapshot=await (await fetch(origin+'/receive')).json();
    const invalidSnapshot=await fetch(origin+'/receive?unexpected=1');assert.equal(invalidSnapshot.status,400);
    const invalidDevices=await fetch(origin+'/audio/devices?unexpected=1');assert.equal(invalidDevices.status,400,'unknown query must fail before physical enumeration');
    assert.equal(snapshot.audio.state,'running');assert.equal(snapshot.source.kind,'live');assert.equal(snapshot.job.mode,'ft8');
    const query=new URLSearchParams({source_id:snapshot.source.id,job_id:snapshot.job.id,generation:String(snapshot.generation),cursor:'0',limit:'1'});
    const response=await fetch(origin+'/receive/results?'+query),raw=await response.text(),result=JSON.parse(raw);
    assert.equal(response.status,200);assert.ok(Buffer.byteLength(raw)<=3072);assert.equal(result.records.length,1);
    assert.equal(result.records[0].text,'CQ K1ABC FN42');assert.equal(result.records[0].payload77,expected.payload77);
    assert.deepEqual(result.records[0].fields,expected.fields);assert.equal(result.records[0].sequence,0);
    assert.ok(Math.abs(result.records[0].start_frame-5968)<=240);assert.ok(Math.abs(result.records[0].frequency_hz-1000)<=1);
    assert.equal(await row.locator('td').nth(2).textContent(),'—','source-relative decode does not invent UTC DT');
    assert.ok((await row.getAttribute('data-result-id')).includes(snapshot.source.id));
    for(const request of pages)assert.equal(new URL(request.url).searchParams.get('limit'),'1');
    for(let i=1;i<pages.length;i++)assert.ok(pages[i].at-pages[i-1].at>=3950,'Thin result requests start at most once per4seconds');
    const headers={Origin:origin,'Content-Type':'application/json'};
    let invalid=await fetch(origin+'/receive/start',{method:'POST',headers,body:JSON.stringify({v:1,profile_id:snapshot.profile_id,boot_id:snapshot.boot_id,generation:snapshot.generation,profile_revision:0,mode:'ft8',unexpected:true})});
    assert.equal(invalid.status,400);
    const wrongProfile=await fetch(origin+'/receive/start',{method:'POST',headers,body:JSON.stringify({v:1,profile_id:'00000000-0000-4000-8000-000000000001',boot_id:snapshot.boot_id,generation:snapshot.generation,profile_revision:999,mode:'ft8'})});
    assert.equal(wrongProfile.status,403,'wrong profile wins over stale saved revision');
    const duplicate=await fetch(origin+'/receive/results?'+query+'&cursor=0');assert.equal(duplicate.status,400);
    const ahead=new URLSearchParams(query);ahead.set('cursor',String(result.next_sequence+1));assert.equal((await fetch(origin+'/receive/results?'+ahead)).status,400);
    const stale=new URLSearchParams(query);stale.set('source_id','00000000-0000-4000-8000-000000000001');assert.equal((await fetch(origin+'/receive/results?'+stale)).status,404);
    await page.getByRole('button',{name:'Stop receive',exact:true}).click();
    await page.locator('#receive-status').filter({hasText:'Partial results retained'}).waitFor();
    assert.equal(await row.count(),1,'accepted partial records survive stop');
    assert.equal((await (await fetch(origin+'/receive/results?'+query)).json()).records[0].text,'CQ K1ABC FN42');
    for(const name of ['Enable Tx','Halt Tx','Auto Seq','Log contact'])assert.equal(await page.getByRole('button',{name,exact:true}).isDisabled(),true);
    await fs.mkdir('test-results/receive-integration',{recursive:true});
    await row.scrollIntoViewIfNeeded();
    await page.screenshot({path:'test-results/receive-integration/real-ft8-callsign.png',fullPage:true});
    assert.deepEqual(errors,[]);
    console.log('ACTUAL PATH: verified48k stereo PCM -> LiveSource -> WindowBuffer -> Rust FT8 -> Recording owner -> /receive/results -> CQ K1ABC FN42');
  }finally{await browser.close();}
});
