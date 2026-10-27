'use strict';
// Cost 2: actual isolated station server and Chromium, no radio or external network.
const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const net=require('node:net');
const {once}=require('node:events');
const crypto=require('node:crypto');
const {chromium}=require('playwright');
const {server}=require('./support.cjs');
let browser,root;
before(async()=>{root=await fs.mkdtemp(path.join(os.tmpdir(),'wstx-operating-'));await fs.mkdir('test-results/ui-operating',{recursive:true});browser=await chromium.launch();});
after(async()=>{await browser?.close();await fs.rm(root,{recursive:true,force:true});});
async function fixture(t,viewport,{inputDevice=null,beforeNavigate}={}){
  const listener=net.createServer();listener.listen(0,'127.0.0.1');await once(listener,'listening');const port=listener.address().port;await new Promise(r=>listener.close(r));
  const dir=await fs.mkdtemp(path.join(root,'station-'));
  const doc={schema_version:1,profile_id:crypto.randomUUID(),revision:0,display_name:'HB9BLA <station>',callsign:'HB9BLA',locator:'JN47AA',endpoint:{bind:`127.0.0.1:${port}`,origin:null},connection_type:'standard',audio:{input_device:inputDevice,output_device:null},control:{mode:'disabled',endpoint:null,ptt:'disabled'}};
  await fs.writeFile(path.join(dir,'profile.json'),JSON.stringify(doc));
  const app=await server({},['--profile',dir]),context=await browser.newContext({viewport}),page=await context.newPage();
  t.after(async()=>{await context.close();await app.close();});
  const errors=[],sent=[];page.on('pageerror',e=>errors.push(e.message));
  page.on('websocket',ws=>ws.on('framesent',frame=>sent.push(JSON.parse(frame.payload))));
  await beforeNavigate?.(page,app,doc);
  await page.goto(app.origin);await page.locator('#connection[data-state=connected]').waitFor();
  assert.equal(await page.locator('#operating-workspace').count(),1,'operating workspace is rendered');
  return {page,app,errors,sent};
}

function deferred(){let resolve;const promise=new Promise(r=>{resolve=r;});return {promise,resolve};}
function liveFixture(idle){
  return {...idle,audio:{state:'running',device_id:'test-only-unopened-input',device_name:null,error:null,retry_after_ms:null},
    source:{id:crypto.randomUUID(),kind:'live',sample_rate:12000,channels:1,next_frame:4800,segment:0},
    job:{id:crypto.randomUUID(),mode:'ft8',state:'running',error:null,processed_frames:0,first_sequence:0,next_sequence:0,available_count:0,last_overrun:null,latest_decode:null}};
}
function emptyResults(s){return {v:1,profile_id:s.profile_id,boot_id:s.boot_id,source_id:s.source.id,job_id:s.job.id,generation:s.generation,
  mode:s.job.mode,state:s.job.state,error:null,search_limited:false,first_sequence:0,next_sequence:0,available_count:0,next:0,more:false,records:[],latest_decode:s.job.latest_decode};}

async function chooseDisplay(page,value){
  await page.waitForFunction(()=>profileData&&snapshot&&!syncPending);
  await page.locator('[data-region=client-preferences]').first().click();await page.selectOption('#display-profile',value);
  await page.locator('.op-secondary:not([hidden]) .return-operate').click();
}
// Proves: CL-006-03/04; TC-010-005. Browser preference fixtures, no synthesized source or decoded result.
test('TC-010-005 explicit display choice survives reload and browser storage restoration',{timeout:20000},async t=>{
  const {page,app,errors}=await fixture(t,{width:1440,height:900});
  const profile=(await (await fetch(app.origin+'/profile')).json()).profile_id,key=`wstx.display-profile.v1:${profile}`;
  assert.equal(await page.inputValue('#display-profile'),'detail','cleartext loopback default remains Detailed');
  assert.equal(await page.evaluate(key=>localStorage.getItem(key),key),null,'default is not persisted as an explicit choice');
  for(const choice of ['off','thin','detail']){
    await chooseDisplay(page,choice);await page.reload();await page.locator('#connection[data-state=connected]').waitFor();await page.waitForFunction(()=>profileData&&snapshot&&!syncPending);
    assert.equal(await page.inputValue('#display-profile'),choice);
    assert.equal(await page.evaluate(key=>localStorage.getItem(key),key),choice);
  }
  const restored=await browser.newContext({storageState:await page.context().storageState()});t.after(()=>restored.close());
  const reopened=await restored.newPage();await reopened.goto(app.origin);await reopened.waitForFunction(()=>profileData&&snapshot&&!syncPending);
  assert.equal(await reopened.inputValue('#display-profile'),'detail');
  assert.deepEqual(await reopened.evaluate(()=>Object.entries(localStorage)),[[key,'detail']],'storage contains only versioned profile key and enumerated choice');
  await page.evaluate(key=>localStorage.setItem(key,'invalid-display-value'),key);await page.reload();await page.waitForFunction(()=>profileData&&snapshot&&!syncPending);
  assert.equal(await page.inputValue('#display-profile'),'detail','invalid persisted values use normal default');assert.deepEqual(errors,[]);
});
test('TC-010-005 display preference is isolated by origin and validated profile UUID',{timeout:20000},async t=>{
  const {page,app,errors}=await fixture(t,{width:1440,height:900}),base=await (await fetch(app.origin+'/profile')).json();
  await chooseDisplay(page,'off');let current=base;
  // Profile identity wire fixtures test browser preference identity only; no decoded traffic is injected.
  await page.route('**/profile',route=>route.fulfill({json:current}));
  current={...base,boot_id:crypto.randomUUID(),revision:base.revision+1};await page.reload();await page.waitForFunction(()=>profileData&&snapshot&&!syncPending);
  assert.equal(await page.inputValue('#display-profile'),'off','boot/revision changes preserve explicit choice');
  current={...base,profile_id:crypto.randomUUID()};await page.reload();await page.waitForFunction(()=>profileData&&snapshot&&!syncPending);
  assert.equal(await page.inputValue('#display-profile'),'detail','different profile UUID has its own default');await chooseDisplay(page,'thin');
  current={...base,profile_id:'invalid-profile-id'};await page.reload();await page.waitForFunction(()=>profileData&&snapshot&&!syncPending);await chooseDisplay(page,'thin');assert.equal(await page.evaluate(()=>localStorage.getItem('wstx.display-profile.v1:invalid-profile-id')),null,'invalid UUID is never persisted');
  current=base;await page.reload();await page.waitForFunction(()=>profileData&&snapshot&&!syncPending);assert.equal(await page.inputValue('#display-profile'),'off');
  const other=await fixture(t,{width:1440,height:900}),otherPage=await page.context().newPage();t.after(()=>otherPage.close());
  await otherPage.route('**/profile',route=>route.fulfill({json:base}));await otherPage.goto(other.app.origin);await otherPage.waitForFunction(()=>profileData&&snapshot&&!syncPending);
  assert.equal(await otherPage.inputValue('#display-profile'),'detail','same profile UUID on another origin cannot inherit Off');await chooseDisplay(otherPage,'thin');
  assert.equal(await page.inputValue('#display-profile'),'off');assert.deepEqual(errors,[]);
});
test('TC-010-005 denied browser storage preserves in-memory display selection',{timeout:15000},async t=>{
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async p=>{
    await p.addInitScript(()=>Object.defineProperty(window,'localStorage',{get(){throw new DOMException('Storage disabled','SecurityError');}}));
  }});
  assert.equal(await page.inputValue('#display-profile'),'detail');await chooseDisplay(page,'off');assert.equal(await page.inputValue('#display-profile'),'off');
  await page.reload();await page.waitForFunction(()=>profileData&&snapshot&&!syncPending);assert.equal(await page.inputValue('#display-profile'),'detail');assert.deepEqual(errors,[]);
});
test('TC-010-005 runtime Thin fallback preserves explicit Detailed preference',{timeout:15000},async t=>{
  const {page,errors}=await fixture(t,{width:1440,height:900});await chooseDisplay(page,'off');await chooseDisplay(page,'detail');
  const profile=await page.evaluate(()=>profileData.profile_id),key=`wstx.display-profile.v1:${profile}`;
  await page.evaluate(()=>dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'error',id:detailRequest,data:{code:'unknown_command',message:'fixture unsupported Detailed'}}}})));
  assert.equal(await page.inputValue('#display-profile'),'thin');assert.equal(await page.evaluate(key=>localStorage.getItem(key),key),'detail','automatic fallback does not become a user choice');
  await page.reload();await page.waitForFunction(()=>profileData&&snapshot&&!syncPending);assert.equal(await page.inputValue('#display-profile'),'detail');
  await chooseDisplay(page,'off');await chooseDisplay(page,'thin');await page.reload();await page.waitForFunction(()=>profileData&&snapshot&&!syncPending);
  assert.equal(await page.inputValue('#display-profile'),'thin');assert.deepEqual(errors,[]);
});

// Proves: CL-010-07/08; TC-007-002. Valid empty-state wire fixture only; no decoded messages or decoder-success claim.
test('TC-007-002 empty live receive distinguishes listening from unavailable',{timeout:15000},async t=>{
  let current,idle;
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(p,app)=>{
    idle=await (await fetch(app.origin+'/receive')).json();current=liveFixture(idle);current.job.mode='ft4';
    await p.route('**/receive',async route=>{await p.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:current});});
    await p.route('**/receive/results?*',route=>route.fulfill({json:emptyResults(current)}));
  }});
  const empty=page.locator('#band-activity .empty-messages');
  await empty.filter({hasText:'Listening for FT4'}).waitFor();
  for(const mode of ['ft4','ft8'])for(const state of ['running','cancelling','completed','cancelled','failed']){
    current={...current,job:{...current.job,mode,state}};await page.evaluate(()=>receiveSync());
    const heading=state==='running'?`Listening for ${mode.toUpperCase()}`:state==='cancelling'?`Stopping ${mode.toUpperCase()} receive`:`${mode.toUpperCase()} receive ${state}`;
    assert.equal(await empty.locator('strong').textContent(),heading);
    assert.equal(await empty.locator('span').textContent(),['running','cancelling'].includes(state)?'No verified messages decoded yet.':'No verified messages were decoded.');
    assert.equal(await page.locator('tr[data-result-id]').count(),0,'empty state never inserts a decoded station');
  }
  current={...current,job:{...current.job,mode:'spectrum',state:'running'}};await page.evaluate(()=>receiveSync());
  assert.equal(await empty.locator('strong').textContent(),'Decoder unavailable');
  current={...idle};await page.evaluate(()=>receiveSync());
  assert.equal(await empty.locator('strong').textContent(),'Decoder unavailable');
  assert.deepEqual(errors,[]);
});

// Proves: CL-010-07, CL-010-08; TC-009-004. Negative delayed HTTP fixture; no decoder evidence.
test('receive result race cannot regress a newer cancelled snapshot',{timeout:15000},async t=>{
  const entered=deferred(),release=deferred();let current;
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(p,app)=>{
    current=liveFixture(await (await fetch(app.origin+'/receive')).json());
    await p.route('**/receive',async route=>{await p.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:current});});
    await p.route('**/receive/results?*',async route=>{const previous=emptyResults(current);entered.resolve();await release.promise;await route.fulfill({json:previous});});
  }});
  await entered.promise;
  current={...current,audio:{...current.audio,state:'closed'},job:{...current.job,state:'cancelled'}};
  await page.evaluate(()=>receiveSync());
  assert.equal(await page.evaluate(()=>live.job.state),'cancelled');
  release.resolve();await page.waitForFunction(()=>!resultPending);
  assert.equal(await page.evaluate(()=>live.job.state),'cancelled','old running page must not regress current terminal state');
  assert.match(await page.locator('#receive-status').innerText(),/cancelled.*Partial results retained/);
  assert.deepEqual(errors,[]);
});

// Proves: CL-010-07, CL-010-08; TC-009-004. Negative wire fixture through the actual listener.
test('receive frame race updates its live owner while recording job is absent',{timeout:15000},async t=>{
  let current;
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(p,app)=>{
    current=liveFixture(await (await fetch(app.origin+'/receive')).json());
    await p.route('**/receive',async route=>{await p.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:current});});
    await p.route('**/receive/results?*',route=>route.fulfill({json:emptyResults(current)}));
  }});
  await page.waitForFunction(()=>live?.source&&snapshot&&snapshot.job===null);
  await page.evaluate(()=>window.dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'spectrum.detail.frame',data:{
    boot_id:live.boot_id,source_id:live.source.id,job_id:live.job.id,generation:live.generation,sequence:0,first_frame:0,end_frame:2400,levels_b64:btoa('\0'.repeat(1024))}}}})));
  await page.waitForFunction(()=>document.querySelector('#waterfall').dataset.rows==='1');
  assert.equal(await page.evaluate(()=>live.job.processed_frames),2400);
  assert.equal(await page.evaluate(()=>snapshot.job),null,'live progress cannot mutate independently fetched file state');
  assert.equal(await page.locator('#connection').getAttribute('data-state'),'connected');assert.deepEqual(errors,[]);
});

// Proves: CL-010-07, CL-010-08; TC-009-004. A pre-mutation read is not reconciliation evidence.
test('receive snapshot race preserves unknown mutation until a later read',{timeout:15000},async t=>{
  const entered=deferred(),release=deferred();let hold=false;
  const {page,errors}=await fixture(t,{width:1440,height:900},{inputDevice:'test-only-unopened-input',beforeNavigate:async(p,app)=>{
    const idle=await (await fetch(app.origin+'/receive')).json();
    await p.route('**/receive',async route=>{if(hold){entered.resolve();await release.promise;}await route.fulfill({json:idle});});
    await p.route('**/receive/start',route=>route.abort('failed'));
  }});
  await page.waitForFunction(()=>live&&!livePending&&!document.querySelector('#receive-start').disabled);
  hold=true;await page.evaluate(()=>{void receiveSync();});await entered.promise;
  await page.getByRole('button',{name:'Start receive',exact:true}).click({timeout:2000});
  await page.locator('#receive-status').filter({hasText:'Start outcome unknown'}).waitFor({timeout:2000});
  hold=false;release.resolve();await page.waitForFunction(()=>!livePending);
  assert.equal(await page.evaluate(()=>uncertainMutation),true,'the old idle response cannot clear an unknown newer mutation');
  assert.equal(await page.getByRole('button',{name:'Start receive',exact:true}).isDisabled(),true);
  assert.match(await page.locator('#receive-status').innerText(),/Start outcome unknown/);
  await page.getByRole('button',{name:'Refresh status',exact:true}).click();
  await page.waitForFunction(()=>!uncertainMutation&&!document.querySelector('#receive-start').disabled);
  assert.deepEqual(errors,[]);
});
async function geometry(page){return page.evaluate(()=>{const box=id=>{const r=document.querySelector(id).getBoundingClientRect();return {top:r.top,bottom:r.bottom,height:r.height};};return {bar:box('#station-bar'),signal:box('#signal'),split:box('#splitter'),workspace:box('#controls'),overflow:document.documentElement.scrollWidth>innerWidth};});}

// Proves: CL-010-05, CL-010-07, CL-010-08; TC-007-002 read-only layout subset.
test('TC-007-002 operating screen exposes literal identity and truthful unsupported controls',{timeout:20000},async t=>{
  const {page,errors}=await fixture(t,{width:1440,height:900});
  assert.equal(await page.locator('#operating-station').count(),1,'persistent operating station identity exists');
  assert.equal(await page.locator('#operating-station').textContent(),'HB9BLA <station>');
  assert.equal(await page.locator('#operating-station station').count(),0);
  assert.match(await page.locator('#band-activity').innerText(),/Decoder unavailable/);assert.match(await page.locator('#rx-focus').innerText(),/No station selected/);assert.equal(await page.locator('tr[data-result-id]').count(),0);
  for(const name of ['Enable Tx','Halt Tx','Log contact'])assert.equal(await page.getByRole('button',{name,exact:true}).isDisabled(),true,name);
  assert.equal(await page.getByRole('checkbox',{name:'Auto sequence unavailable',exact:true}).isDisabled(),true);
  await page.getByRole('button',{name:'Station connection details',exact:true}).click();
  assert.match(await page.locator('#operating-capabilities').innerText(),/Audio.*unavailable/is);
  assert.match(await page.locator('#operating-capabilities').innerText(),/CAT.*unavailable/is);
  await page.locator('.op-secondary:not([hidden]) .return-operate').click();
  // Existing server is read-only: verify real table styles without inserting decoded rows.
  for(const width of [360,1440,1499,1500,1600]){
    await page.setViewportSize({width,height:900});
    const style=await page.locator('#band-activity table').evaluate(table=>{
      const header=table.querySelector('th'),cell=table.querySelector('td');
      const a=getComputedStyle(table),b=getComputedStyle(header),c=getComputedStyle(cell);
      return {tableFont:a.fontSize,headerFont:b.fontSize,headerPadding:b.paddingTop,cellPadding:c.paddingTop,wrap:c.overflowWrap,overflow:document.documentElement.scrollWidth>innerWidth};
    });
    assert.equal(style.tableFont,'16px',`Band Activity table at ${width}px`);
    assert.equal(style.headerFont,'14px');assert.equal(style.headerPadding,'8px');
    assert.equal(style.cellPadding,'8px');assert.equal(style.wrap,'anywhere');assert.equal(style.overflow,false);
    assert.equal(await page.locator('#band-activity tr[data-result-id]').count(),0,'no fake decoded rows');
    await page.screenshot({path:`test-results/ui-operating/readability-${width}.png`,fullPage:true});
  }
  await page.setViewportSize({width:1440,height:900});
  const g=await geometry(page);assert.ok(g.bar.bottom<=g.signal.top+1);assert.ok(g.signal.bottom<=g.split.top+1);assert.ok(g.split.bottom<=g.workspace.top+1);assert.equal(g.overflow,false);
  await fs.mkdir('test-results/ui-operating',{recursive:true});await page.screenshot({path:'test-results/ui-operating/desktop.png',fullPage:true});assert.deepEqual(errors,[]);
});

// Proves: CL-010-05, CL-010-08; TC-007-002 desktop/mobile/200% CSS viewport and keyboard.
test('TC-007-002 operating split and secondary regions remain accessible at narrow and zoom equivalent sizes',{timeout:20000},async t=>{
  const {page,errors}=await fixture(t,{width:360,height:800});
  for(const viewport of [{width:360,height:800},{width:720,height:450}]){
    await page.setViewportSize(viewport);const separator=page.getByRole('separator');await separator.focus();
    await page.keyboard.press('Home');const minimum=Number(await separator.getAttribute('aria-valuenow'));
    await page.keyboard.press('ArrowDown');const stepped=Number(await separator.getAttribute('aria-valuenow'));assert.equal(stepped,minimum+16);
    await page.keyboard.press('End');const maximum=Number(await separator.getAttribute('aria-valuenow'));assert.ok(maximum>=stepped);assert.equal(maximum,Number(await separator.getAttribute('aria-valuemax')));
    await page.keyboard.press('Home');let g=await geometry(page);assert.equal(g.overflow,false);assert.ok(g.signal.height>=160);assert.ok(g.signal.bottom<=g.workspace.top,JSON.stringify(g));
    for(const [opener,name] of [['#open-server-settings','Station settings'],['#open-recordings','Recorded input'],['.op-station-button','Connection details']]){
      await page.locator(opener).focus();await page.keyboard.press('Enter');
      const summary=page.locator('summary').filter({hasText:name});assert.equal(await summary.evaluate(el=>el.parentElement.open),true);
      await summary.focus();await page.keyboard.press('Enter');assert.equal(await summary.evaluate(el=>el.parentElement.open),false);
      await page.keyboard.press('Enter');assert.equal(await summary.evaluate(el=>el.parentElement.open),true);
      assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
      await page.keyboard.press('Escape');assert.equal(await page.locator('#operating-workspace').isVisible(),true);
      assert.equal(await page.locator(opener).evaluate(el=>document.activeElement===el),true);
    }
    assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
  }
  await page.setViewportSize({width:360,height:800});await page.reload();await page.locator('#connection[data-state=connected]').waitFor();await page.screenshot({path:'test-results/ui-operating/mobile.png',fullPage:true});assert.deepEqual(errors,[]);
});

// Proves: CL-010-07, CL-010-08; TC-007-002 link loss and no invented commands.
test('TC-007-002 pointer resize and stale link preserve read-only authority',{timeout:20000},async t=>{
  const {page,app,errors,sent}=await fixture(t,{width:1440,height:900});
  const separator=page.getByRole('separator'),before=Number(await separator.getAttribute('aria-valuenow')),box=await separator.boundingBox();
  await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();await page.mouse.move(box.x+box.width/2,box.y+box.height/2-40);await page.mouse.up();
  assert.ok(Number(await separator.getAttribute('aria-valuenow'))<before);
  await app.close();await page.locator('#connection[data-state=stale]').waitFor();
  for(const name of ['Enable Tx','Halt Tx','Log contact'])assert.equal(await page.getByRole('button',{name,exact:true}).isDisabled(),true);
  assert.ok(sent.some(m=>m.type==='station.get'),'recorder observes actual allowed station traffic');
  assert.equal(sent.some(m=>/transmit|qso|log|radio\./.test(m.type)),false);assert.deepEqual(errors,[]);
});


// Proves: CL-010-05, CL-010-07, CL-010-08; TC-007-002 agreed design and authority-preserving regions.
test('TC-007-002 agreed workspace has tuning, band strip, Current QSO and Strategy with truthful state',{timeout:20000},async t=>{
 const {page,errors,sent}=await fixture(t,{width:1200,height:800});
 for(const id of ['radio-toolbar','band-strip','strategy-panel'])assert.equal(await page.locator('#'+id).count(),1,`${id} is part of the agreed operating screen`);
 const composition=await page.evaluate(()=>{
  const rect=id=>{const r=document.querySelector(id).getBoundingClientRect();return {top:r.top,bottom:r.bottom,left:r.left,right:r.right,height:r.height};};
  return Object.fromEntries(['#station-bar','#radio-toolbar','#signal','#splitter','#band-strip','#band-activity','#rx-focus','#strategy-panel'].map(id=>[id,rect(id)]));
 });
 assert.ok(composition['#station-bar'].bottom<=composition['#radio-toolbar'].top+1);
 assert.ok(composition['#radio-toolbar'].bottom<=composition['#signal'].top+1);
 assert.equal(Math.round(composition['#signal'].height),210);
 assert.ok(composition['#splitter'].bottom<=composition['#band-strip'].top+1);
 assert.ok(composition['#band-strip'].bottom<=composition['#band-activity'].top+1);
 assert.ok(composition['#band-activity'].top>=composition['#band-strip'].bottom);
 await page.setViewportSize({width:1600,height:1000});
 const cardOrder=await page.locator('#controls .operating-grid').evaluate(grid=>[...grid.children].map(el=>el.getBoundingClientRect().left));assert.ok(cardOrder[0]<cardOrder[1]&&cardOrder[1]<cardOrder[2],'three cards remain adjacent when readable space permits');
 await page.setViewportSize({width:1200,height:800});
 assert.equal(await page.locator('#focus-heading').textContent(),'Current QSO');
 assert.match(await page.locator('#strategy-heading').textContent(),/Strategy/);
 assert.equal(await page.locator('#band-strip button').count(),13);
 for(const selector of ['#op-dial','#receive-start','#receive-stop','#band-strip button','#strategy-panel button:disabled']){
  for(const control of await page.locator(selector).all())assert.equal(await control.isDisabled(),true);
 }
 assert.equal(await page.locator('#receive-mode').isEnabled(),true,'receive mode is a supported local selection');
 assert.equal(await page.locator('#audio-enumerate').isEnabled(),true,'read-only input listing is supported');
 assert.equal(await page.locator('#op-dial').inputValue(),'');
 assert.match(await page.locator('#signal .op-signal-heading').innerText(),/0\u20133000 Hz/,'fixed-band label retains correct Unicode text');
 assert.match(await page.locator('#radio-toolbar').innerText(),/Timing unavailable/);
 assert.match(await page.locator('#strategy-panel').innerText(),/No active definition/);
 assert.equal(await page.locator('tr[data-result-id]').count(),0);
 for(const width of [360,720,1200,1440,1499,1500,1600]){
  await page.setViewportSize({width,height:900});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`no page overflow ${width}`);
 }
 await page.setViewportSize({width:1200,height:800});
 await page.screenshot({path:'test-results/ui-operating/agreed-design-1200.png',fullPage:true});
 assert.equal(sent.some(m=>/transmit|qso|log|radio\./.test(m.type)),false);assert.deepEqual(errors,[]);
});

// Proves: CL-010-05, CL-010-07, CL-010-08; TC-007-002 actual form state survives region changes.
test('TC-007-002 in-page navigation preserves unsaved profile and selected recording with no command replay',{timeout:20000},async t=>{
 const {page,errors}=await fixture(t,{width:1440,height:950});
 const mutations=[];page.on('request',r=>{if(r.method()!=='GET')mutations.push({method:r.method(),url:r.url()});});
 await page.keyboard.press('F2');assert.equal(await page.locator('#region-server-settings').isVisible(),true);
 await page.locator('#display-name').fill('Unsaved operator edit');
 await page.keyboard.press('Escape');assert.equal(await page.locator('#operating-workspace').isVisible(),true);
 await page.locator('#open-recordings').click();
 await page.locator('#recording-file').setInputFiles({name:'selected-but-not-imported.wav',mimeType:'audio/wav',buffer:Buffer.from('not imported')});
 await page.keyboard.press('Escape');
 for(const name of ['logbook','strategies','client-preferences','help']){
  const button=page.locator(`#station-bar [data-region="${name}"]`);await button.focus();await page.keyboard.press('Enter');
  assert.equal(await page.locator(`#region-${name}`).isVisible(),true);
  assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
  assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isDisabled(),true);
  await page.keyboard.press('Escape');assert.equal(await button.evaluate(el=>document.activeElement===el),true);
 }
 await page.locator('#open-server-settings').click();assert.equal(await page.locator('#display-name').inputValue(),'Unsaved operator edit');
 await page.keyboard.press('Escape');await page.locator('#open-recordings').click();
 assert.equal(await page.locator('#recording-file').evaluate(el=>el.files[0].name),'selected-but-not-imported.wav');
 assert.deepEqual(mutations,[],'navigation does not save/import or issue station mutations');
 assert.deepEqual(errors,[]);
});

// Proves: TC-007-002 readable rem typography and actual 200% text enlargement, every region.
test('TC-007-002 readable text reflows throughout every operating region at 200 percent',{timeout:60000},async t=>{
 const {page,errors,sent}=await fixture(t,{width:1200,height:900});
 const regions=['operate','recordings','server-settings','client-preferences','connection','strategies','logbook','help'];
 const findings=[];
 for(const scale of [1,2])for(const width of [360,1200,1600]){
  await page.setViewportSize({width,height:1000});
  // Root font-size exercises actual rem text enlargement, not device pixels or a screenshot scale.
  await page.evaluate(factor=>document.documentElement.style.fontSize=`${factor*100}%`,scale);
  await page.waitForTimeout(60);
  for(const region of regions){
   await page.locator(`#station-bar button[data-region="${region}"]`).focus();await page.keyboard.press('Enter');
   const container=region==='operate'?'#operating-workspace':`#region-${region}`;
   await page.locator(container).evaluate(async el=>{for(const details of el.querySelectorAll('details'))details.open=true;await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));});
   const result=await page.evaluate(({container,scale})=>{
    const regions=[document.querySelector('#station-bar'),document.querySelector('#radio-toolbar'),document.querySelector('#signal'),document.querySelector('#band-strip'),document.querySelector('#workspace-statusbar'),document.querySelector(container)];
    const violations=[],clipped=[],overlap=[],textBoxes=[];let checked=0;
    const visible=el=>el.getClientRects().length&&getComputedStyle(el).visibility!=='hidden';
    for(const region of regions)for(const el of [region,...region.querySelectorAll('*')]){
     if(!visible(el)||el.matches('canvas,option,script,style'))continue;
     // Responsive rows repeat visible field labels; originals remain accessible. Populated fixture verifies all6label/value and column semantics.
     const responsiveHeader=el.closest('#band-activity thead');if(responsiveHeader&&getComputedStyle(responsiveHeader).clipPath==='inset(50%)')continue;
     const direct=[...el.childNodes].filter(n=>n.nodeType===Node.TEXT_NODE&&n.textContent.trim());
     if(!direct.length&&!el.matches('input:not([type=range]):not([type=checkbox]),select,button'))continue;
     const technical=!!el.closest('#frequency-ruler,#time-ruler');
     const normal=el.matches('button,input:not([type=range]):not([type=checkbox]),select,td')||!!el.closest('td')||(el.matches('p')&&!el.matches('.op-muted,.op-unavailable,#bin-readout,#settings-result')&&!el.closest('.op-candidate,#settings'));
     const minimum=(technical?12:normal?16:14)*scale;
     const computed=getComputedStyle(el),size=parseFloat(computed.fontSize);checked++;
     if(size+0.1<minimum)violations.push({tag:el.tagName,id:el.id,cls:el.className,size,minimum,text:el.textContent.trim().slice(0,55)});
     for(const node of direct){const range=document.createRange();range.selectNodeContents(node);for(const r of range.getClientRects()){
      if(r.width&&r.height){const rendered={left:r.left,right:r.right,top:r.top,bottom:r.bottom};for(let a=el;a&&a!==document.body;a=a.parentElement){const style=getComputedStyle(a),b=a.getBoundingClientRect();if(['hidden','auto','scroll'].includes(style.overflowX)){rendered.left=Math.max(rendered.left,b.left);rendered.right=Math.min(rendered.right,b.right);}if(['hidden','auto','scroll'].includes(style.overflowY)){rendered.top=Math.max(rendered.top,b.top);rendered.bottom=Math.min(rendered.bottom,b.bottom);}}if(rendered.right>rendered.left&&rendered.bottom>rendered.top)textBoxes.push({el,r:rendered,text:node.textContent.trim().slice(0,45)});}
      if(r.width&& (r.left< -1||r.right>innerWidth+1))clipped.push({id:el.id,cls:el.className,text:node.textContent.trim().slice(0,45),left:r.left,right:r.right});
      let verticalScroll=false;for(let ancestor=el;ancestor&&ancestor!==document.body;ancestor=ancestor.parentElement){const style=getComputedStyle(ancestor);if(['auto','scroll'].includes(style.overflowY)&&ancestor.scrollHeight>ancestor.clientHeight)verticalScroll=true;if(style.overflowX==='hidden'||(style.overflowY==='hidden'&&!verticalScroll)){
       const b=ancestor.getBoundingClientRect();if((style.overflowX==='hidden'&&(r.left<b.left-1||r.right>b.right+1))||(style.overflowY==='hidden'&&!verticalScroll&&(r.top<b.top-1||r.bottom>b.bottom+1)))clipped.push({id:el.id,clip:ancestor.id,text:node.textContent.trim().slice(0,45)});
      }}
     }}
    }
    for(let a=0;a<textBoxes.length;a++)for(let b=a+1;b<textBoxes.length;b++){const x=textBoxes[a],y=textBoxes[b];if(x.el===y.el||x.el.contains(y.el)||y.el.contains(x.el))continue;if(Math.min(x.r.right,y.r.right)-Math.max(x.r.left,y.r.left)>1&&Math.min(x.r.bottom,y.r.bottom)-Math.max(x.r.top,y.r.top)>1)overlap.push([x.text,y.text]);}
    return {violations,clipped,overlap,checked,overflow:document.documentElement.scrollWidth>innerWidth,rootFont:getComputedStyle(document.documentElement).fontSize,scrollX,mainLeft:document.querySelector('main').getBoundingClientRect().left,mainScroll:document.querySelector('main').scrollLeft};
   },{container,scale});
   findings.push({width,scale,region,...result});
   await fs.writeFile("test-results/ui-operating/readability-computed.json",JSON.stringify(findings,null,2));
   if(result.clipped.length||result.overflow||result.violations.length)await page.screenshot({path:"test-results/ui-operating/readability-failure.png",fullPage:true});
   assert.equal(result.rootFont,`${16*scale}px`);assert.ok(result.checked>20);
   assert.deepEqual(result.violations,[],`font minima ${region} ${width}px ${scale}x`);
   assert.equal(result.overflow,false,`page overflow ${region} ${width}px ${scale}x`);
   assert.deepEqual(result.clipped,[],`text clipping ${region} ${width}px ${scale}x`);
   assert.deepEqual(result.overlap,[],`text overlap ${region} ${width}px ${scale}x`);
   await page.locator('#halt-tx').scrollIntoViewIfNeeded();assert.equal(await page.locator('#halt-tx').isVisible(),true);assert.equal(await page.locator('#halt-tx').isDisabled(),true);
   if(width===1200&&region==='operate')await page.screenshot({path:`test-results/ui-operating/readable-${scale}x-1200.png`,fullPage:true});
  }
 }
 await fs.writeFile('test-results/ui-operating/readability-computed.json',JSON.stringify(findings,null,2));
 assert.equal(sent.some(m=>/transmit|qso|log|radio\./.test(m.type)),false);assert.deepEqual(errors,[]);
});

// Presentation-only captured FT4/FT8 text plus independent edge cases; no decoder/RF success claim.
const bandPresentationFixture={"purpose":"Presentation-only text fixture; not decoder/RF truth. Captured DT is unavailable and normalized to U+2014. Independent edge rows are explicitly synthetic.","capture_sha256":"030d849cdc8fbc5a62b7251f1dbb1c275fd1485ef11baca297f8eed67dd347ca","rows":[{"kind":"captured-physical-FT4-text-only","values":["64.987 s","10.8","\u2014","2199.2","R4SF LZ2MP KN23","Decoded"]},{"kind":"captured-physical-FT4-text-only","values":["64.916 s","6.5","\u2014","2733.3","DL1LN SP9JBT +00","Decoded"]},{"kind":"captured-physical-FT4-text-only","values":["64.916 s","-15.6","\u2014","1774.9","CQ LB1PI JO49","Decoded"]},{"kind":"captured-physical-FT4-text-only","values":["73.198 s","22.3","\u2014","399.9","CQ LZ2II KN22","Decoded"]},{"kind":"captured-physical-FT8-text-only","values":["6.898 s","22.3","\u2014","1195.0","DB1BC EB4FSM IN80","Decoded"]},{"kind":"captured-physical-FT8-text-only","values":["6.711 s","12.5","\u2014","1454.5","IW1BYR IZ8EYN +17","Decoded"]},{"kind":"captured-physical-FT8-text-only","values":["6.744 s","-6.4","\u2014","449.9","G5ACE/P LA1KKA 73","Decoded"]},{"kind":"captured-physical-FT8-text-only","values":["6.678 s","-7.6","\u2014","1844.3","NF3R SQ8AA 73","Decoded"]},{"kind":"captured-physical-FT8-text-only","values":["6.718 s","-16.3","\u2014","2768.4","CQ AA3B FN20","Decoded"]},{"kind":"independent-presentation-edge","values":["123456.789 s","-60.0","-0.123","3499.9","CQ PJ4/PA3XYZ FK52","Decoded"]},{"kind":"independent-presentation-edge","values":["23:59:59","+23.0","+0.123","1000.0","PJ4/PA3XYZ HB9BLA RR73 THANKS FOR THE CONTACT 73","unsupported"]},{"kind":"independent-presentation-edge","values":["Unknown","\u2014","\u2014","200.0","Payload invalid_payload","invalid_payload"]}],"capture_ft8_sha256":"820f9dfc5744f30f0cb1d30c5aff6843d364e4df44a5961d0e186bdb83f6a353"};
test('TC-007-002 populated Band Activity has dominant width and complete readable field details',{timeout:25000},async t=>{
 const {page,errors}=await fixture(t,{width:1440,height:1000}),rows=bandPresentationFixture.rows;
 await page.locator('#band-activity header .op-muted').evaluate(node=>node.textContent='Presentation fixture: captured FT4/FT8 text and synthetic edge cases; not decoder truth');
 await page.locator('#band-activity tbody').evaluate((tbody,rows)=>{const labels=[...document.querySelectorAll('#band-activity th')].map(th=>th.textContent);tbody.replaceChildren();for(const item of rows){const row=document.createElement('tr');row.dataset.presentationFixture=item.kind;row.setAttribute('role','row');for(const [index,value] of item.values.entries()){const td=document.createElement('td');td.setAttribute('role','cell');td.dataset.label=labels[index];td.textContent=value;row.append(td);}tbody.append(row);}},rows);
 assert.equal(await page.locator('tr[data-result-id]').count(),0,'presentation fixtures never claim production decoder records');
 for(const scale of [1,2])for(const width of [360,720,1200,1440,1600]){
  await page.setViewportSize({width,height:1000});await page.evaluate(scale=>document.documentElement.style.fontSize=`${scale*100}%`,scale);await page.evaluate(()=>new Promise(requestAnimationFrame));
  const cells=await page.locator('#band-activity tbody td').evaluateAll(nodes=>nodes.map((td,index)=>{const box=td.getBoundingClientRect(),range=document.createRange();range.selectNodeContents(td);return {text:td.textContent,font:parseFloat(getComputedStyle(td).fontSize),whiteSpace:getComputedStyle(td).whiteSpace,label:td.dataset.label,generatedLabel:getComputedStyle(td,'::before').content,lines:range.getClientRects().length,inside:[...range.getClientRects()].every(r=>r.left>=box.left-1&&r.right<=box.right+1&&r.top>=box.top-1&&r.bottom<=box.bottom+1)};}));
  assert.deepEqual(cells.map(c=>c.text),rows.flatMap(r=>r.values));
  assert.ok(cells.every(c=>c.font>=16*scale&&c.inside),`literal text stays within its own field ${width}px ${scale}x: ${JSON.stringify(cells.filter(c=>!c.inside))}`);
  assert.ok(cells.every((c,i)=>i%6===4?c.whiteSpace==='normal':c.whiteSpace==='nowrap'&&c.lines===1),`numbers/time/status never split ${width}px ${scale}x`);
  const layout=await page.evaluate(()=>{const b=document.querySelector('#band-activity').getBoundingClientRect(),q=document.querySelector('#rx-focus').getBoundingClientRect(),s=document.querySelector('#strategy-panel').getBoundingClientRect(),g=document.querySelector('.operating-grid'),cs=getComputedStyle(g),available=g.clientWidth-parseFloat(cs.paddingLeft)-parseFloat(cs.paddingRight);return {band:b.width,available,ratio:b.width/(b.width+q.width+s.width),details:getComputedStyle(document.querySelector('#band-activity tbody tr')).display==='grid',overflow:document.documentElement.scrollWidth>innerWidth};});
  assert.equal(layout.overflow,false,`no page overflow ${width}px ${scale}x`);
  if(scale===1&&width>1200)assert.ok(Math.abs(layout.ratio-.55)<.015,`Band Activity owns55% of allocated card widths: ${JSON.stringify(layout)}`);
  else assert.ok(Math.abs(layout.band-layout.available)<2,`Band Activity full width ${width}px ${scale}x`);
  if(layout.details)assert.ok(cells.every(c=>c.generatedLabel.includes(c.label)),`all6 field labels visible ${width}px ${scale}x`);
  assert.equal(await page.getByRole('columnheader').count(),6,'column semantics retained in row-details view');
  const splitCalls=await page.locator('#band-activity td:nth-child(5)').evaluateAll(nodes=>nodes.flatMap(td=>{const word='PJ4/PA3XYZ',at=td.textContent.indexOf(word);if(at<0)return [];const r=document.createRange();r.setStart(td.firstChild,at);r.setEnd(td.firstChild,at+word.length);return r.getClientRects().length===1?[]:[td.textContent];}));assert.deepEqual(splitCalls,[],'long callsign tokens stay intact where they fit');
  await page.locator('#band-activity tbody tr').last().scrollIntoViewIfNeeded();await page.locator('#band-activity tbody tr').first().scrollIntoViewIfNeeded();
  await page.evaluate(()=>{document.querySelector('#controls').scrollTop=0;document.querySelector('#band-activity .op-table-wrap').scrollTop=0;});
  await page.screenshot({path:`test-results/ui-operating/band-activity-${width}-${scale}x.png`,fullPage:true});
 }
 assert.deepEqual(errors,[]);
});

// Proves: CL-010-09; TC-007-006. Explicit presentation/clock fixtures, never modem/RF truth.
test('TC-007-006 latest period spans pages, signed DT and obsolete pages cannot restore old stations',{timeout:45000},async t=>{
  let state,records,held=null,hold=false;const pending=deferred();
  const makeRecord=(sequence,period,dt)=>({sequence,start_frame:186000+sequence,frequency_hz:1000+sequence,snr_db:-12.3,payload77:'0'.repeat(77),i3:0,n3:0,status:'decoded',text:`UI FIXTURE STATION ${sequence}`,fields:{},period_start_utc:period,dt_seconds:dt});
  const period='2026-10-27T12:00:15.0000000Z';
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(page,app)=>{
    state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    records=[makeRecord(0,'2026-10-27T12:00:00.0000000Z',0),...Array.from({length:18},(_,i)=>makeRecord(i+1,period,i===0?-0.2:i===1?0.2:-0.01))];
    Object.assign(state.job,{first_sequence:0,next_sequence:19,available_count:19,latest_decode:{id:1,first_sequence:1,next_sequence:19,period_start_utc:period,complete:true}});
    await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await page.route('**/receive/results?*',async route=>{
      const cursor=Number(new URL(route.request().url()).searchParams.get('cursor')),limit=Number(new URL(route.request().url()).searchParams.get('limit'));
      const batch=records.slice(cursor,cursor+limit),next=cursor+batch.length;
      const response={...emptyResults(state),first_sequence:0,next_sequence:records.length,available_count:records.length,next,more:next<records.length,records:batch,latest_decode:structuredClone(state.job.latest_decode)};
      if(hold&&cursor>=35){held={route,response};pending.resolve();}else await route.fulfill({json:response});
    });
  }});
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-result-id]').length===16);
  await page.selectOption('#activity-direction','desc');
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-result-id]').length===18);
  assert.equal(await page.locator('tr[data-result-id]').first().getAttribute('data-sequence'),'18','new page re-sorts the entire selected view');
  await page.selectOption('#activity-direction','asc');
  assert.doesNotMatch(await page.locator('#band-activity tbody').innerText(),/STATION 0\b/);
  const cells=page.locator('tr[data-result-id]').first().locator('td');assert.equal(await cells.nth(0).textContent(),'12:00:15');assert.equal(await cells.nth(2).textContent(),'-0.2');
  assert.equal(await page.locator('tr[data-result-id]').nth(1).locator('td').nth(2).textContent(),'+0.2');assert.equal(await page.locator('tr[data-result-id]').nth(2).locator('td').nth(2).textContent(),'+0.0');
  for(const width of [1440,360])for(const scale of [1,2]){await page.setViewportSize({width,height:900});await page.evaluate(scale=>document.documentElement.style.fontSize=16*scale+'px',scale);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);assert.deepEqual(await cells.evaluateAll(nodes=>nodes.filter(n=>n.scrollWidth>n.clientWidth+1).map(n=>n.textContent)),[]);await page.screenshot({path:`test-results/ui-operating/latest-period-${width}-${scale}x.png`,fullPage:true});}
  await page.evaluate(()=>document.documentElement.style.fontSize='16px');
  const nextPeriod='2026-10-27T12:00:30.0000000Z';records.push(...Array.from({length:18},(_,i)=>makeRecord(i+19,nextPeriod,0.1)));
  Object.assign(state.job,{next_sequence:37,available_count:37,latest_decode:{id:2,first_sequence:19,next_sequence:37,period_start_utc:nextPeriod,complete:false}});hold=true;
  await page.getByRole('button',{name:'Refresh status',exact:true}).click();await pending.promise;
  assert.equal(await page.locator('tr[data-result-id]').count(),16);assert.match(await page.locator('#band-activity header').innerText(),/Partial.*Loading results/);
  assert.doesNotMatch(await page.locator('#band-activity tbody').innerText(),/STATION 1\b/);
  state.job.latest_decode={id:3,first_sequence:37,next_sequence:37,period_start_utc:'2026-10-27T12:00:45.0000000Z',complete:true};
  await page.getByRole('button',{name:'Refresh status',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('tr[data-result-id]').length===0);
  await held.route.fulfill({json:held.response});held=null;hold=false;
  await page.waitForTimeout(500);assert.equal(await page.locator('tr[data-result-id]').count(),0);assert.match(await page.locator('#band-activity').innerText(),/No stations decoded/);
  assert.equal(await page.evaluate(()=>resultCursor),37,'old period page cannot move new view cursor');assert.deepEqual(errors,[]);
});

// Proves: CL-010-09; TC-007-006. Period identity can be learned from results, not only snapshots.
test('TC-007-006 a page-announced period refetches its prefix instead of skipping it',{timeout:35000},async t=>{
  const oldPeriod='2026-10-27T12:00:00.0000000Z',newPeriod='2026-10-27T12:00:15.0000000Z';let state,announced=false;
  const records=Array.from({length:19},(_,i)=>({sequence:i,start_frame:i?186000:6000,frequency_hz:1000+i,snr_db:0,payload77:'0'.repeat(77),i3:0,n3:0,status:'decoded',text:`PAGE FIXTURE ${i}`,fields:{},period_start_utc:i?newPeriod:oldPeriod,dt_seconds:0}));
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(page,app)=>{
    state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=360000;
    Object.assign(state.job,{next_sequence:19,available_count:19,latest_decode:{id:1,first_sequence:0,next_sequence:1,period_start_utc:oldPeriod,complete:true}});
    await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await page.route('**/receive/results?*',route=>{
      const cursor=Number(new URL(route.request().url()).searchParams.get('cursor')),batch=records.slice(cursor,cursor+16),next=cursor+batch.length;
      if(cursor===19)announced=true;
      const view=announced?{id:2,first_sequence:1,next_sequence:19,period_start_utc:newPeriod,complete:true}:state.job.latest_decode;
      return route.fulfill({json:{...emptyResults(state),next_sequence:19,available_count:19,next,more:next<19,records:batch,latest_decode:view}});
    });
  }});
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-result-id]').length===18);
  assert.ok(announced);assert.equal(await page.locator('tr[data-result-id]').first().locator('td').nth(4).textContent(),'PAGE FIXTURE 1');
  assert.equal(await page.locator('tr[data-result-id]').last().locator('td').nth(4).textContent(),'PAGE FIXTURE 18');assert.deepEqual(errors,[]);
});

// Proves: CL-010-09; TC-007-006. Numeric/literal presentation sorting never selects a station.
test('TC-007-006 selectable ordering is numeric, unknown-last and persists across periods and modes',{timeout:20000},async t=>{
  let state;const period='2026-10-27T12:00:00.0000000Z';
  let records=[
    {frequency_hz:1000,snr_db:-20,dt_seconds:-0.2,text:'CQ Z9ZZ JO00'},
    {frequency_hz:200,snr_db:10,dt_seconds:0.2,text:'cq A1AA IO00'},
    {frequency_hz:3499.9,snr_db:null,dt_seconds:0,text:'CQ B1BB JN00'},
    {frequency_hz:1000,snr_db:-5,dt_seconds:-0.1,text:null},
    {frequency_hz:500,snr_db:0,dt_seconds:0.1,text:' CQ SPACE JO00'},
  ].map((r,sequence)=>({sequence,start_frame:6000,payload77:'0'.repeat(77),i3:0,n3:0,status:r.text===null?'unsupported':'decoded',fields:r.text===null?null:{},period_start_utc:period,...r}));
  const {page,errors,sent}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(page,app)=>{
    state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=180000;
    Object.assign(state.job,{next_sequence:5,available_count:5,latest_decode:{id:1,first_sequence:0,next_sequence:5,period_start_utc:period,complete:true}});
    await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await page.route('**/receive/results?*',route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor')),batch=records.slice(cursor,cursor+16),next=cursor+batch.length;return route.fulfill({json:{...emptyResults(state),next_sequence:5,available_count:5,next,more:next<5,records:batch}});});
  }});
  const order=()=>page.locator('tr[data-result-id]').evaluateAll(rows=>rows.map(r=>Number(r.dataset.sequence)));
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-result-id]').length===5);
  assert.deepEqual(await order(),[1,4,0,3,2],'frequency200 precedes1000, numeric ties retain sequence');
  await page.selectOption('#activity-direction','desc');assert.deepEqual(await order(),[2,0,3,4,1]);
  await page.selectOption('#activity-sort','signal');assert.equal(await page.inputValue('#activity-direction'),'desc');assert.deepEqual(await order(),[1,4,3,0,2]);
  await page.selectOption('#activity-direction','asc');assert.deepEqual(await order(),[0,3,4,1,2],'unknown SNR stays last when ascending');
  await page.selectOption('#activity-sort','dt');assert.deepEqual(await order(),[0,3,2,4,1]);await page.selectOption('#activity-direction','desc');assert.deepEqual(await order(),[1,4,2,3,0]);
  await page.selectOption('#activity-sort','message');assert.deepEqual(await order(),[4,1,2,0,3]);await page.selectOption('#activity-direction','desc');assert.deepEqual(await order(),[0,2,1,4,3]);
  state.job.latest_decode={id:2,first_sequence:5,next_sequence:5,period_start_utc:'2026-10-27T12:00:15.0000000Z',complete:true};await page.getByRole('button',{name:'Refresh status',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('tr[data-result-id]').length===0);
  assert.equal(await page.inputValue('#activity-sort'),'message');assert.equal(await page.inputValue('#activity-direction'),'desc');
  state.generation++;state.source.id=crypto.randomUUID();state.job.id=crypto.randomUUID();state.job.mode='ft4';state.job.latest_decode={id:1,first_sequence:0,next_sequence:5,period_start_utc:null,complete:true};records=records.map(r=>({...r,period_start_utc:null,dt_seconds:null}));
  await page.evaluate(()=>socket.close());await page.locator('#connection[data-state=stale]').waitFor();await page.locator('#connection[data-state=connected]').waitFor();await page.waitForFunction(()=>document.querySelectorAll('tr[data-result-id]').length===5);
  assert.equal(await page.inputValue('#activity-sort'),'message');assert.equal(await page.inputValue('#activity-direction'),'desc');
  await page.selectOption('#activity-sort','dt');assert.deepEqual(await order(),[0,1,2,3,4]);await page.selectOption('#activity-direction','desc');assert.deepEqual(await order(),[0,1,2,3,4],'all unknown DT stays in sequence order');
  for(const width of [1440,360])for(const scale of [1,2]){await page.setViewportSize({width,height:900});await page.evaluate(scale=>document.documentElement.style.fontSize=16*scale+'px',scale);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);}
  await page.evaluate(()=>{profileData.profile_id='not-a-valid-uuid';renderResults();});assert.equal(await page.inputValue('#activity-sort'),'dt','invalid profile cannot reset preference');
  await page.evaluate(()=>{profileData.profile_id='00000000-0000-4000-8000-000000000001';renderResults();});assert.equal(await page.inputValue('#activity-sort'),'frequency');assert.equal(await page.inputValue('#activity-direction'),'asc');
  assert.ok(sent.every(m=>!['radio.operation','receive.start'].includes(m.type)));assert.deepEqual(errors,[]);
});
