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
const {server,browserPort}=require('./support.cjs');
let browser,root;
before(async()=>{root=await fs.mkdtemp(path.join(os.tmpdir(),'wstx-operating-'));await fs.mkdir('test-results/ui-operating',{recursive:true});browser=await chromium.launch();});
after(async()=>{await browser?.close();await fs.rm(root,{recursive:true,force:true});});
async function fixture(t,viewport,{inputDevice=null,beforeNavigate}={}){
  const port=await browserPort();
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
  return {page,app,errors,sent,dir};
}

// #37: the status refreshes itself; the explicit Refresh status is in Settings > Expert.
async function refreshStatus(page){const open=await page.locator('#settings-drawer').isVisible();if(!open)await page.locator('#open-server-settings').click();await page.locator('#refresh').click();if(!open)await page.locator('#settings-drawer .return-operate').click();}
function deferred(){let resolve;const promise=new Promise(r=>{resolve=r;});return {promise,resolve};}
function liveFixture(idle){
  return {...idle,audio:{state:'running',device_id:'test-only-unopened-input',device_name:null,error:null,retry_after_ms:null,loss_epochs:0,last_loss:null},
    source:{id:crypto.randomUUID(),kind:'live',sample_rate:12000,channels:1,next_frame:4800,segment:0},
    job:{id:crypto.randomUUID(),mode:'ft8',state:'running',error:null,processed_frames:0,first_sequence:0,next_sequence:0,available_count:0,last_overrun:null,latest_decode:null}};
}
function emptyResults(s){return {v:1,profile_id:s.profile_id,boot_id:s.boot_id,source_id:s.source.id,job_id:s.job.id,generation:s.generation,
  mode:s.job.mode,state:s.job.state,error:null,search_limited:false,first_sequence:0,next_sequence:0,available_count:0,next:0,more:false,records:[],latest_decode:s.job.latest_decode};}

async function chooseDisplay(page,value){
  await page.waitForFunction(()=>profileData&&snapshot&&!syncPending);
  // Display preferences are a Settings section (WstxOperatingLayout::SettingsSection display).
  await page.locator('#open-server-settings').click();await page.selectOption('#display-profile',value);
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

// Band Activity sorts by its column headers (WstxOperatingLayout::ActivityOrdering): a new
// header chooses its field with its default direction, the active header reverses it.
async function clickSort(page,field){await page.locator(`#band-activity th[data-sort="${field}"]`).click();}
async function sortState(page){return page.evaluate(()=>{const th=document.querySelector('#band-activity th[aria-sort=ascending],#band-activity th[aria-sort=descending]');return th?[th.dataset.sort,th.getAttribute('aria-sort')==='ascending'?'asc':'desc']:null;});}
// Proves: CL-010-07, CL-010-08; TC-009-004. A pre-mutation read is not reconciliation evidence.
test('receive snapshot race preserves unknown mutation until a later read',{timeout:15000},async t=>{
  const entered=deferred(),release=deferred();let hold=false;
  const {page,errors}=await fixture(t,{width:1440,height:900},{inputDevice:'test-only-unopened-input',beforeNavigate:async(p,app)=>{
    const idle=await (await fetch(app.origin+'/receive')).json();
    await p.route('**/receive',async route=>{if(hold){entered.resolve();await release.promise;}await route.fulfill({json:idle});});
    await p.route('**/receive/start',route=>route.abort('failed'));
  }});
  // #37: a stopped receive starts from its exception chip (or Expert / Alt+M).
  const chip=page.locator('#exception-chips [data-chip=receive]');
  await chip.filter({hasText:'Receive stopped'}).waitFor();await page.waitForFunction(()=>live&&!livePending);
  hold=true;await page.evaluate(()=>{void receiveSync();});await entered.promise;
  await chip.click({timeout:2000});
  await page.waitForFunction(()=>document.querySelector('#receive-status').textContent.includes('Start outcome unknown'),null,{timeout:2000});
  hold=false;release.resolve();await page.waitForFunction(()=>!livePending);
  assert.equal(await page.evaluate(()=>uncertainMutation),true,'the old idle response cannot clear an unknown newer mutation');
  assert.equal(await page.locator('#receive-toggle').isDisabled(),true);
  assert.match(await page.locator('#receive-status').textContent(),/Start outcome unknown/);
  await chip.filter({hasText:'Start outcome unknown'}).waitFor();
  await refreshStatus(page);
  await page.waitForFunction(()=>!uncertainMutation&&!document.querySelector('#receive-toggle').disabled);
  await chip.filter({hasText:'Receive stopped'}).waitFor();
  assert.deepEqual(errors,[]);
});
// WstxContact::HaltTx D5 / OperatingLayout escapeClosesRegion=false: Escape halts and
// aborts the contact but closes no panel or drawer; its Back/Close control returns.
async function returnToOperation(page){
  const open=await page.locator('.op-secondary:not([hidden])').count();
  await page.keyboard.press('Escape');
  if(open)assert.equal(await page.locator('.op-secondary:not([hidden])').count(),open,'Escape closes no panel');
  if(open){await page.locator('.op-secondary:not([hidden]) .return-operate').focus();await page.keyboard.press('Enter');}
}
async function geometry(page){return page.evaluate(()=>{const box=id=>{const r=document.querySelector(id).getBoundingClientRect();return {top:r.top,bottom:r.bottom,height:r.height};};return {bar:box('#station-bar'),signal:box('#signal'),split:box('#splitter'),workspace:box('#controls'),overflow:document.documentElement.scrollWidth>innerWidth};});}

// Proves: CL-010-05, CL-010-07, CL-010-08; TC-007-002 read-only layout subset.
test('TC-007-002 operating screen exposes literal identity and truthful unsupported controls',{timeout:20000},async t=>{
  const {page,errors}=await fixture(t,{width:1440,height:900});
  assert.equal(await page.locator('#operating-station').count(),1,'persistent operating station identity exists');
  assert.equal(await page.locator('#operating-station').textContent(),'HB9BLA <station>');
  assert.equal(await page.locator('#operating-station station').count(),0);
  assert.match(await page.locator('#band-activity').innerText(),/Decoder unavailable/);assert.match(await page.locator('#rx-focus').innerText(),/No station selected/);assert.equal(await page.locator('tr[data-result-id]').count(),0);
  await page.waitForFunction(()=>!!window.wstxContact?.snapshot(),null,{timeout:25000});
  for(const name of ['CQ','Reply','RR73','73','Tune','Halt Tx','HALT','Log QSO'])assert.equal(await page.getByRole('button',{name,exact:true}).isDisabled(),true,name);
  assert.equal(await page.locator('#contact-auto').isDisabled(),true);assert.equal(await page.locator('#contact-auto').getAttribute('aria-label'),'Auto sequence unavailable');
  assert.equal(await page.locator('#transmit-unavailable').isVisible(),true,'the reason is next to the disabled transmit buttons');
  await page.locator('#open-server-settings').click();await page.locator('#tab-expert').click();
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
test('TC-007-002 operating split, drawer and pages remain accessible at narrow and zoom equivalent sizes',{timeout:30000},async t=>{
  const {page,errors}=await fixture(t,{width:360,height:800});
  for(const viewport of [{width:360,height:800},{width:720,height:450}]){
    await page.setViewportSize(viewport);const separator=page.getByRole('separator');await separator.focus();
    await page.keyboard.press('Home');const minimum=Number(await separator.getAttribute('aria-valuenow'));
    await page.keyboard.press('ArrowDown');const stepped=Number(await separator.getAttribute('aria-valuenow'));assert.equal(stepped,minimum+16);
    await page.keyboard.press('End');const maximum=Number(await separator.getAttribute('aria-valuenow'));assert.ok(maximum>=stepped);assert.equal(maximum,Number(await separator.getAttribute('aria-valuemax')));
    await page.keyboard.press('Home');let g=await geometry(page);assert.equal(g.overflow,false);assert.ok(g.signal.height>=160);assert.ok(g.signal.bottom<=g.workspace.top,JSON.stringify(g));
    // Settings drawer by keyboard: open, move to Expert with the arrow keys, toggle a section.
    await page.locator('#open-server-settings').focus();await page.keyboard.press('Enter');
    await page.locator('#tab-general').focus();for(let i=0;i<3;i++)await page.keyboard.press('ArrowRight');
    assert.equal(await page.locator('#tab-expert').getAttribute('aria-current'),'true');
    const summary=page.locator('#recorded-input summary');assert.equal(await summary.evaluate(el=>el.parentElement.open),true);
    await summary.focus();await page.keyboard.press('Enter');assert.equal(await summary.evaluate(el=>el.parentElement.open),false);
    await page.keyboard.press('Enter');assert.equal(await summary.evaluate(el=>el.parentElement.open),true);
    assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
    await returnToOperation(page);assert.equal(await page.locator('#settings-drawer').isVisible(),false);
    assert.equal(await page.locator('#open-server-settings').evaluate(el=>document.activeElement===el),true,'focus returns to the opener');
    for(const opener of ['#open-logbook','#station-bar [data-region=help]']){
      await page.locator(opener).focus();await page.keyboard.press('Enter');
      assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
      await returnToOperation(page);assert.equal(await page.locator('#operating-workspace').isVisible(),true);
      assert.equal(await page.locator(opener).evaluate(el=>document.activeElement===el),true);
    }
  }
  await page.setViewportSize({width:360,height:800});await page.reload();await page.locator('#connection[data-state=connected]').waitFor();await page.screenshot({path:'test-results/ui-operating/mobile.png',fullPage:true});assert.deepEqual(errors,[]);
});

// Proves: CL-010-07, CL-010-08; TC-007-002 link loss and no invented commands.
test('TC-007-002 pointer resize and stale link preserve read-only authority',{timeout:20000},async t=>{
  const {page,app,errors,sent}=await fixture(t,{width:1440,height:900});
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  const separator=page.getByRole('separator'),before=Number(await separator.getAttribute('aria-valuenow')),box=await separator.boundingBox();
  await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();await page.mouse.move(box.x+box.width/2,box.y+box.height/2-40);await page.mouse.up();
  assert.ok(Number(await separator.getAttribute('aria-valuenow'))<before);
  await app.close();await page.locator('#connection[data-state=stale]').waitFor();
  for(const name of ['CQ','Reply','Halt Tx','Log QSO'])assert.equal(await page.getByRole('button',{name,exact:true}).isDisabled(),true);
  assert.ok(sent.some(m=>m.type==='station.get'),'recorder observes actual allowed station traffic');
  assert.equal(sent.some(m=>/transmit|qso|log|radio\./.test(m.type)),false);assert.deepEqual(errors,[]);
});


// Proves: CL-010-05, CL-010-07, CL-010-08, CL-010-16; TC-007-002 agreed design and authority-preserving regions.
test('TC-007-002 agreed workspace has the top bar, waterfall with Rx/Tx strip, Band Activity and the QSO pane with truthful state',{timeout:30000},async t=>{
 const {page,errors,sent}=await fixture(t,{width:1200,height:1200});
 assert.equal(Math.round((await page.locator('#signal').boundingBox()).height),210,'sufficiently tall desktop starts with the specified compact signal height');
 await page.setViewportSize({width:1200,height:800});
 const shortSignal=await page.locator('#signal').evaluate(signal=>({height:signal.getBoundingClientRect().height,minimum:Number(document.querySelector('#splitter').getAttribute('aria-valuemin')),maximum:Number(document.querySelector('#splitter').getAttribute('aria-valuemax')),current:Number(document.querySelector('#splitter').getAttribute('aria-valuenow'))}));
 assert.ok(shortSignal.height>=160,'short viewport preserves the signal minimum');
 assert.ok(shortSignal.current>=shortSignal.minimum&&shortSignal.current<=shortSignal.maximum,'short viewport respects the accessible splitter bounds');
 assert.equal(Math.round(shortSignal.height),shortSignal.current,'accessible splitter value matches the displayed signal height');
 assert.equal(await page.getByRole('separator').getAttribute('tabindex'),'0','short viewport retains keyboard resizing');
 // The strategy element and the chips come with the contact client (loaded after the first snapshots).
 await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
 for(const id of ['radio-toolbar','rxtx-strip','strategy-element','band-activity','rx-focus'])assert.equal(await page.locator('#'+id).count(),1,`${id} is part of the operating screen`);
 for(const id of ['band-strip','strategy-panel','workspace-statusbar','rx-frequency'])assert.equal(await page.locator('#'+id).count(),0,`${id} is not on the operating screen`);
 const composition=await page.evaluate(()=>{
  const rect=id=>{const r=document.querySelector(id).getBoundingClientRect();return {top:r.top,bottom:r.bottom,left:r.left,right:r.right,height:r.height};};
  return Object.fromEntries(['#station-bar','#signal','#rxtx-strip','#splitter','#band-activity','#rx-focus'].map(id=>[id,rect(id)]));
 });
 assert.ok(composition['#station-bar'].bottom<=composition['#signal'].top+1);
 assert.ok(composition['#signal'].bottom<=composition['#rxtx-strip'].top+1,'the Rx/Tx strip is directly below the waterfall');
 assert.ok(composition['#rxtx-strip'].bottom<=composition['#splitter'].top+1);
 assert.ok(composition['#splitter'].bottom<=composition['#band-activity'].top+1);
 await page.setViewportSize({width:1600,height:1000});
 const cards=await page.evaluate(()=>Object.fromEntries(['#band-activity','#rx-focus','#strategy-element'].map(id=>{const r=document.querySelector(id).getBoundingClientRect();return [id,{left:r.left,right:r.right,top:r.top,bottom:r.bottom}];})));
 assert.ok(cards['#band-activity'].right<=cards['#rx-focus'].left,'Band Activity left of the QSO pane');
 assert.ok(cards['#strategy-element'].left>=cards['#band-activity'].left&&cards['#strategy-element'].right<=cards['#band-activity'].right,'the strategy element is above Band Activity');
 await page.setViewportSize({width:1200,height:800});
 assert.equal(await page.locator('#focus-heading').textContent(),'QSO');
 assert.deepEqual(await page.locator('#radio-toolbar select').evaluateAll(s=>s.map(e=>e.id)),['operating-band','operating-mode'],'one band and one FT8/FT4 selector');
 assert.match(await page.locator('#radio-toolbar').innerText(),/Band \u27F3[\s\S]*Mode \u27F3/,'band and mode are marked as restart changes');
 assert.equal(await page.locator('#op-dial').isDisabled(),true);assert.equal(await page.locator('#op-dial').inputValue(),'');
 assert.match(await page.locator('#signal .op-signal-heading').innerText(),/Sensitivity/,'Sensitivity stays in the waterfall corner');
 // #39: without a saved strategy only None and the editor are offered; Highlight and Auto wait for a strategy.
 await page.waitForFunction(()=>!document.querySelector('#strategy-edit').disabled,null,{timeout:15000});
 assert.deepEqual(await page.locator('#strategy-name option').allTextContents(),['None']);
 for(const id of ['#strategy-highlight','#strategy-auto'])assert.equal(await page.locator(id).isDisabled(),true,`${id} needs a strategy`);
 assert.equal(await page.locator('#station-automation').textContent(),'Automation idle');
 // WstxContact::OperatorDisplays (D11): server UTC and period progress replace the former 'Timing unavailable'.
 await page.locator('#radio-toolbar .op-period small').filter({hasText:/^\d{1,2}\/15/}).waitFor();assert.match(await page.locator('#radio-toolbar .op-period > span').textContent(),/^UTC \d\d:\d\d:\d\d$/);
 // Without an audio input the only exception is that one, named as such.
 await page.locator('#exception-chips [data-chip=receive]').filter({hasText:'No audio input'}).waitFor();
 assert.equal(await page.locator('#exception-chips button').count(),1);
 assert.equal(await page.locator('tr[data-result-id]').count(),0);
 for(const width of [360,720,1200,1366,1440,1499,1500,1600]){
  await page.setViewportSize({width,height:900});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`no page overflow ${width}`);
 }
 await page.setViewportSize({width:1200,height:800});
 await page.screenshot({path:'test-results/ui-operating/agreed-design-1200.png',fullPage:true});
 assert.equal(sent.some(m=>/transmit|qso|log|radio\./.test(m.type)),false);assert.deepEqual(errors,[]);
});

// ---------------------------------------------------------------- #37 operating screen
// WstxOperatingLayout::OperatingScreen and friends (operator design interview 2026-11-01). The
// expected sets below come from the model's decisions, not from the candidate markup.
const removedControls=['#receive-start','#receive-stop','#receive-mode','#operating-stop','#operating-monitor','#contact-enable','#activity-sort','#activity-direction','#band-strip','#strategy-panel','#workspace-statusbar','#rx-frequency','#region-server-settings','#region-expert'];
const operateItems=['#operating-band','#operating-mode','#op-dial','#radio-toolbar .op-period','#open-logbook','#open-server-settings','#halt-tx','#waterfall','#contact-rx','#contact-tx','#contact-hold','#strip-tx-from-rx','#strip-rx-from-tx','#strategy-element','#band-activity','#rx-focus','#rx-pane','#contact-next','#display-sensitivity','#display-speed','#qso-cq','#qso-reply','#qso-rr73','#qso-73','#contact-tune','#qso-halt','#contact-log'];
const drawerItems={general:['#display-name','#callsign','#locator','#station-continent','#clock-setting','#theme-choice','#theme-switch','#display-profile','#settings-browsers','#settings-automation','#settings-startup'],radio:['#control-mode','#control-endpoint','#ptt-mode','#cat-status','#audio-input','#audio-output','#audio-enumerate','#settings-audio .op-input-meter','#watchdog-tx','#watchdog-tune','#settings-save'],logging:['#settings-log','#settings-udp','#udp-warning','#udp-save','#settings-pskreporter'],expert:['#signal-status','#receive-status','#receive-generation','#operating-selection-status','#operating-radio','#operating-refresh','#clock-detail','#receive-toggle','#version','#operating-capabilities','#recording-file','#recording-import','#recording-replay','#startup-resume']};
const healthyTexts=['#cat-status','#receive-status','#signal-status','#operating-radio','#operating-selection-status','#clock-detail'];
async function inViewport(page,selector){return page.locator(selector).first().evaluate(el=>{const r=el.getBoundingClientRect();return el.checkVisibility({visibilityProperty:true})&&r.width>1&&r.height>1&&r.bottom>0&&r.right>0&&r.top<innerHeight&&r.left<innerWidth;});}
// checkVisibility also treats the content of a closed <details> fold-out as not shown.
async function shown(page,selector){return page.locator(selector).first().evaluate(el=>el.checkVisibility({visibilityProperty:true}));}
function contactSnapshot(base,{contact=null,transmit={},settings={},log=null}={}){
  return {v:1,profile_id:base.profile_id,boot_id:base.boot_id,contact_revision:base.revision??3,snapshot_sequence:base.sequence??3,monotonic_ms:1000,utc_ms:Date.now(),log,
    transmit:{capability:'available',arm_state:'disarmed',last_disarm_cause:'startup',tune:false,pending_sequence:null,last_text:null,last_period_utc:null,halt_state:'idle',safety_revision:7,refusal:null,...transmit},
    settings:{auto_seq:true,tx1_skip:false,tx_minutes:6,tune_seconds:90,rx_hz:1500,tx_hz:1500,hold_tx:false,parity:'even',report:-10,...settings},
    contact,watchdog:{tx_remaining_minutes:6,tx_expired:false,tune_remaining_seconds:0}};
}
const partner=(state='replying',extra={})=>({id:crypto.randomUUID(),origin:'selected_row',dx_call:'K1ABC',dx_grid:'FN42',report_sent:'-12',report_rcvd:null,state,next_slot:'tx1',tx4:'rrr',messages:['K1ABC HB9BLA JN47','K1ABC HB9BLA -12','K1ABC HB9BLA R-12','K1ABC HB9BLA RRR','K1ABC HB9BLA 73','CQ HB9BLA JN47'],start_utc:null,end_utc:null,saved:false,...extra});
// Records a page's contact commands and answers them like the station (202) without effects.
async function contactCommands(page,commands){await page.route('**/contact/command',async route=>{commands.push(JSON.parse(route.request().postData()));await route.fulfill({status:202,json:{v:1,accepted:true}});});}

// Proves: CL-010-16; TC-007-009 one fixed laptop screen and phone safety.
test('TC-007-009 one fixed operating screen at 1366x768 holds only the operating items',{timeout:40000},async t=>{
  const {page,errors}=await fixture(t,{width:1366,height:768},{inputDevice:'test-only-unopened-input'});
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:25000});
  for(const selector of removedControls)assert.equal(await page.locator(selector).count(),0,`${selector} is not part of the page`);
  assert.equal(await page.getByRole('button',{name:/Enable Tx|Monitor|Start receive|Stop receive/}).filter({visible:true}).count(),0,'no Enable Tx or receive control on the screen');
  assert.deepEqual(await page.locator('#band-activity thead th').allTextContents(),['UTC','dB','DT','Freq','Message','DXCC','Dist']);
  const metrics=await page.evaluate(()=>({x:document.documentElement.scrollWidth>innerWidth,y:document.documentElement.scrollHeight>innerHeight,main:document.querySelector('main').scrollHeight>document.querySelector('main').clientHeight+1}));
  assert.deepEqual(metrics,{x:false,y:false,main:false},'1366x768 is one fixed screen; lists scroll inside');
  for(const selector of operateItems)assert.equal(await inViewport(page,selector),true,`${selector} on the 1366x768 screen`);
  for(const selector of [...Object.values(drawerItems).flat(),...healthyTexts])assert.equal(await shown(page,selector),false,`${selector} is not on the operating screen`);
  // Top bar holds only band, mode, dial, UTC/period, chips, Logbook, Settings, HALT (plus the
  // status refresh and "?" overview affordances).
  const allowed=['operating-band','operating-mode','op-dial','open-logbook','open-server-settings','Help','halt-tx'];
  const extra=await page.locator('#station-bar').evaluate((bar,allowed)=>[...bar.querySelectorAll('button,select,input')].filter(n=>n.getClientRects().length&&!n.closest('#exception-chips')&&!allowed.includes(n.id)&&!allowed.includes(n.getAttribute('aria-label'))).map(n=>n.id||n.textContent),allowed);
  assert.deepEqual(extra,[],'the top bar holds only its decided items');
  assert.equal(await page.locator('#station-bar #refresh').count(),0,'no refresh in the top bar: the status refreshes itself');
  // The DX entry and Erase are in the QSO fold-out; the pane shows partner, dialogue, NEXT/LAST and buttons.
  for(const selector of ['#dx-call','#dx-grid','#dx-generate','#rx-pane-erase'])assert.equal(await shown(page,selector),false,`${selector} folded away`);
  await page.locator('#qso-more summary').click();for(const selector of ['#dx-call','#dx-generate','#rx-pane-erase','#contact-messages'])assert.equal(await shown(page,selector),true,`${selector} in the fold-out`);await page.locator('#qso-more summary').click();
  assert.equal(await page.locator('#connection').evaluate(el=>el.getBoundingClientRect().width<=1),true,'a connected link shows no status text');
  await page.screenshot({path:'test-results/ui-operating/operating-screen-1366x768.png'});
  await page.setViewportSize({width:360,height:800});await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'a phone does not overflow horizontally');
  for(const selector of ['#halt-tx','#operating-band','#waterfall','#band-activity','#rx-focus','#qso-cq'])assert.equal(await shown(page,selector),true,`${selector} still present at 360 px`);
  await page.screenshot({path:'test-results/ui-operating/operating-screen-360x800.png',fullPage:true});
  assert.deepEqual(errors,[]);
});

// Proves: CL-010-16, CL-008-03; TC-007-009 exception chips and the explicit receive start/stop.
test('TC-007-009 exception chips appear only for an exception and start, stop and explain receive',{timeout:40000},async t=>{
  let current,idle;const posts=[];
  const {page,errors}=await fixture(t,{width:1366,height:768},{inputDevice:'test-only-unopened-input',beforeNavigate:async(p,app)=>{
    idle=await (await fetch(app.origin+'/receive')).json();current=idle;
    await p.route('**/receive',route=>route.fulfill({json:current}));
    await p.route('**/receive/results?*',route=>route.fulfill({json:emptyResults(current)}));
    await p.route('**/receive/start',async route=>{posts.push(['start',JSON.parse(route.request().postData())]);current=liveFixture({...idle,generation:idle.generation+1});await route.fulfill({status:202,json:current});});
    await p.route('**/receive/stop',async route=>{posts.push(['stop',JSON.parse(route.request().postData())]);current={...current,audio:{...current.audio,state:'closed'},job:{...current.job,state:'cancelled'}};await route.fulfill({status:202,json:current});});
    // The recording snapshot names the same live job as the mocked receive snapshot.
    await p.route('**/recording',async route=>{const real=await (await route.fetch()).json();await route.fulfill({json:{...real,generation:current.generation,job:current.job?{id:current.job.id,source_id:current.source?.id??null,generation:current.generation,kind:'live',state:current.job.state,processed_frames:0,error:null}:null}});});
  }});
  const chipTexts=()=>page.locator('#exception-chips button').allTextContents();
  await page.locator('#exception-chips [data-chip=receive]').filter({hasText:'Receive stopped'}).waitFor();
  const mode=await page.evaluate(()=>operatingState.selection.mode),profile=await page.evaluate(()=>[profileData.profile_id,profileData.boot_id,profileData.revision]);
  await page.locator('#exception-chips [data-chip=receive]').click();
  await page.waitForFunction(()=>live?.job?.state==='running');
  assert.deepEqual(posts[0],['start',{v:1,profile_id:profile[0],boot_id:profile[1],generation:idle.generation,profile_revision:profile[2],mode}],'the chip start is the strict start in the operating mode');
  await page.waitForFunction(()=>document.querySelectorAll('#exception-chips button').length===0);
  assert.deepEqual(await chipTexts(),[],'a healthy receiving station shows no chip');
  // The explicit stop is an Expert action (and Alt+M), never a screen control.
  const job=current.job.id;await page.keyboard.press('Alt+m');
  for(let i=0;i<40&&posts.length<2;i++)await page.waitForTimeout(50);
  // The fixture's real /recording snapshot has no live job; re-read the mocked receive state.
  await page.evaluate(()=>receiveSync());await page.waitForFunction(()=>live?.job?.state==='cancelled');
  assert.deepEqual(posts[1],['stop',{v:1,profile_id:profile[0],boot_id:profile[1],generation:idle.generation+1,job_id:job}],'Alt+M stops the exact running tuple');
  await page.locator('#exception-chips [data-chip=receive]').filter({hasText:'Receive stopped'}).waitFor({timeout:5000}).catch(async e=>{throw new Error(`chips ${await page.locator('#exception-chips').textContent()} ${JSON.stringify(await page.evaluate(()=>[live?.job?.state,live?.audio?.state,mutationPending,uncertainMutation,operatingFailure,String(receiveTarget())]))}`);});
  current={...current,audio:{...current.audio,state:'unavailable',error:'device_lost'}};await page.evaluate(()=>receiveSync());
  await page.locator('#exception-chips [data-chip=audio]').filter({hasText:'Audio unavailable · device_lost'}).waitFor();
  await page.locator('#exception-chips [data-chip=audio]').click();
  assert.equal(await page.locator('#settings-drawer').isVisible(),true,'the chip opens its detail in the Settings drawer');
  assert.equal(await page.locator('#tab-radio').getAttribute('aria-current'),'true');assert.equal(await inViewport(page,'#settings-audio'),true);
  await page.locator('#settings-drawer .return-operate').click();
  await page.evaluate(()=>socket.close());await page.locator('#connection[data-state=stale]').waitFor();
  assert.equal(await page.locator('#connection').evaluate(el=>el.getBoundingClientRect().width>20),true,'a stale link shows its status');
  assert.equal(posts.length,2);assert.deepEqual(errors,[]);
});

// Proves: CL-010-16; TC-007-009 Settings drawer sections and reachability.
test('TC-007-009 the Settings drawer has four sections holding every control moved off the screen',{timeout:60000},async t=>{
  const {page,errors}=await fixture(t,{width:1366,height:768});
  const requests=[];page.on('request',r=>requests.push(`${r.method()} ${new URL(r.url()).pathname}`));
  // The contact client (loaded after the first snapshots) adds the watchdog, MCP and logging sections.
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  await page.locator('#open-server-settings').click();
  assert.deepEqual((await page.locator('#settings-drawer .op-drawer-tabs button').allTextContents()).map(t=>t.replace(/\s*\u27F3$/,'')),['General','Radio','Logging & Reporting','Expert']);
  assert.equal(await page.locator('#settings-drawer .op-drawer-section').count(),4,'exactly four sections');
  assert.match(await page.locator('#tab-radio').textContent(),/\u27F3/,'Radio is marked as a restart section');
  for(const [tab,items] of Object.entries(drawerItems)){
    await page.locator('#tab-'+tab).click();
    for(const selector of items){await page.locator(selector).first().scrollIntoViewIfNeeded();assert.equal(await inViewport(page,selector),true,`${selector} in Settings > ${tab}`);}
    assert.equal(await inViewport(page,'#waterfall'),true,'the waterfall keeps running beside the drawer');
    assert.equal(await inViewport(page,'#halt-tx'),true,'HALT stays reachable');
  }
  assert.equal(await page.locator('#settings-drawer #transmit-details #transmit-panel').count(),1,'the raw #9 transmit panel is an Expert section');
  await page.locator('#tab-radio').click();await page.locator('#audio-enumerate').click();
  await page.locator('#audio-inputs').filter({hasText:/\S/}).waitFor();
  assert.ok(requests.includes('GET /audio/devices'));assert.equal(requests.includes('PUT /profile'),false,'listing inputs is not an Apply');
  await page.keyboard.press('Escape');assert.equal(await page.locator('#settings-drawer').isVisible(),true,'Esc halts and closes no panel');
  await page.locator('#band-activity').click({position:{x:40,y:200}});assert.equal(await page.locator('#settings-drawer').isVisible(),false,'a pointer action outside closes the drawer');
  await page.keyboard.press('F2');assert.equal(await page.locator('#settings-drawer').isVisible(),true,'F2 opens Settings');
  await page.locator('#settings-drawer .return-operate').click();
  await page.locator('#open-logbook').click();assert.equal(await page.locator('#region-logbook').isVisible(),true,'Logbook is a full page');
  assert.equal(await page.locator('#waterfall').isVisible(),false);assert.equal(await page.locator('#halt-tx').isVisible(),true);
  await page.locator('#region-logbook .return-operate').click();assert.equal(await page.locator('#operating-workspace').isVisible(),true);
  assert.deepEqual(errors,[]);
});

// Proves: CL-045-01, CL-010-16; TC-007-009 "Monitor off at startup" is a plain General setting.
test('TC-007-009 Monitor off at startup reads and saves the station setting without touching receive',{timeout:60000},async t=>{
  const {page,app,errors}=await fixture(t,{width:1366,height:768},{inputDevice:'test-only-unopened-input'});
  const requests=[],posts=[];
  page.on('request',r=>{const p=new URL(r.url()).pathname;requests.push(`${r.method()} ${p}`);if(r.method()==='POST'&&p==='/receive/startup')posts.push(JSON.parse(r.postData()));});
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  const initial=await (await fetch(app.origin+'/receive/startup')).json();
  assert.equal(initial.monitor_off_at_startup,false,'the station default is off, as WSJT-X');
  await page.locator('#open-server-settings').click();await page.locator('#tab-general').click();
  const box=page.locator('#monitor-off-startup');await page.locator('#monitor-off-startup:enabled').waitFor();
  await box.scrollIntoViewIfNeeded();assert.equal(await inViewport(page,'#monitor-off-startup'),true,'the setting is in Settings > General');
  assert.equal(await page.locator('#settings-general #monitor-off-startup').count(),1);
  assert.equal(await box.isChecked(),false,'shows the station value');
  assert.doesNotMatch(await page.locator('#settings-startup').textContent(),/\u27F3/,'a plain setting has no restart mark');
  await box.check();await page.locator('#startup-result',{hasText:'Saved'}).filter({hasText:'Saved'}).waitFor();
  assert.deepEqual(posts,[{v:1,profile_id:initial.profile_id,boot_id:initial.boot_id,monitor_off_at_startup:true}],'exactly one exact-key save');
  assert.equal((await (await fetch(app.origin+'/receive/startup')).json()).monitor_off_at_startup,true,'the station stored it');
  await page.route('**/receive/startup',route=>route.request().method()==='POST'?route.fulfill({status:409,json:{error:{code:'state_conflict'}}}):route.continue());
  await box.uncheck();await page.locator('#startup-result').filter({hasText:'Not saved'}).waitFor();
  assert.match(await page.locator('#startup-result').textContent(),/state_conflict/);
  assert.equal(await box.isChecked(),true,'a refusal restores the stored value');
  await page.unroute('**/receive/startup');
  await page.locator('#tab-expert').click();await page.locator('#startup-resume').scrollIntoViewIfNeeded();
  assert.match(await page.locator('#startup-resume').textContent(),/^Nothing to resume at start/,'Expert shows the startup resume state');
  await page.reload();await page.locator('#connection[data-state=connected]').waitFor();await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  await page.waitForFunction(()=>!document.querySelector('#monitor-off-startup').disabled);assert.equal(await page.locator('#monitor-off-startup').isChecked(),true,'the saved value reads back');
  assert.equal(posts.length,2,'one save plus the refused one');
  assert.deepEqual(requests.filter(r=>/^POST \/receive\/(start|stop|select)$/.test(r)),[],'no receive mutation');
  assert.deepEqual(errors,[]);
});

// Proves: CL-040-02, CL-010-16; TC-007-009 the UDP interface is a Logging & Reporting setting.
test('TC-007-009 the UDP editor reads GET /udp when Settings opens and saves the edited targets with one PUT',{timeout:60000},async t=>{
  const {page,app,errors}=await fixture(t,{width:1366,height:768},{inputDevice:'test-only-unopened-input'});
  const requests=[],puts=[];
  page.on('request',r=>{const p=new URL(r.url()).pathname;requests.push(`${r.method()} ${p}`);if(r.method()==='PUT'&&p==='/udp')puts.push(JSON.parse(r.postData()));});
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});await page.waitForTimeout(500);
  assert.equal(requests.some(r=>r.endsWith(' /udp')),false,'no /udp request before Settings opens');
  const initial=await (await fetch(app.origin+'/udp')).json();
  await page.locator('#open-server-settings').click();await page.locator('#tab-logging').click();
  const rows=page.locator('#udp-targets .udp-target');await rows.first().waitFor();
  assert.ok(requests.filter(r=>r==='GET /udp').length>=1,'read when the drawer opens');
  assert.equal(await page.locator('#udp-instance').inputValue(),'WSTX-Rust');
  const first=rows.nth(0);assert.equal(await first.locator('[data-f=address]').inputValue(),'127.0.0.1:2237');
  assert.equal(await first.locator('[data-f=enabled]').isChecked(),true);assert.equal(await first.locator('[data-f=accept]').isChecked(),false);
  assert.deepEqual(await first.locator('[data-m]').evaluateAll(b=>b.filter(x=>x.checked).map(x=>x.dataset.m)),['heartbeat','status','decode','clear','qso_logged','close','logged_adif']);
  assert.match(await first.locator('[data-f=status]').textContent(),/Inactive/,'WSTX_UDP=off opens no socket and the status says so');
  assert.match(await page.locator('#udp-warning').textContent(),/select a QSO.*Tx5.*never key/s,'the accept_commands warning is shown');
  assert.doesNotMatch(await page.locator('#tab-logging').textContent(),/⟳/,'a setting, not a restart change');
  // Edit: no Decode to the first target; add a multicast target, where Accept commands is not offered.
  await first.locator('[data-m=decode]').uncheck();await first.locator('[data-f=accept]').check();
  await page.locator('#udp-add').click();const added=rows.nth(1);
  await added.locator('[data-f=address]').fill('239.255.0.1:2237');assert.equal(await added.locator('[data-f=accept]').isDisabled(),true,'no accept_commands for a multicast group');
  await added.locator('[data-f=ttl]').fill('3');
  await page.locator('#udp-save').click();await page.locator('#udp-result').filter({hasText:'Saved'}).waitFor();
  const all=['heartbeat','status','decode','clear','qso_logged','close','logged_adif'];
  const expected={instance_name:'WSTX-Rust',targets:[
    {address:'127.0.0.1:2237',enabled:true,multicast_ttl:1,multicast_interface:null,messages:all.filter(m=>m!=='decode'),accept_commands:true},
    {address:'239.255.0.1:2237',enabled:true,multicast_ttl:3,multicast_interface:null,messages:all,accept_commands:false}]};
  assert.deepEqual(puts,[{v:1,profile_id:initial.profile_id,boot_id:initial.boot_id,expected_revision:initial.revision,configuration:expected}],'exactly one exact PUT');
  const saved=await (await fetch(app.origin+'/udp')).json();assert.deepEqual(saved.configuration,expected,'the station stored the edited list');assert.equal(saved.revision,initial.revision+1);
  // A refused address keeps the edits and names the field.
  await page.locator('#udp-add').click();await rows.nth(2).locator('[data-f=address]').fill('0.0.0.0:1');
  await page.locator('#udp-save').click();await page.locator('#udp-result').filter({hasText:'Not saved'}).waitFor();
  assert.match(await page.locator('#udp-result').textContent(),/invalid_request \(targets\[2\]\.address\)/);
  assert.equal(await rows.count(),3,'the edits are kept');
  assert.equal(puts.length,2);
  assert.deepEqual(requests.filter(r=>/^POST \/receive\/(start|stop|select)$/.test(r)),[],'no receive mutation');
  assert.deepEqual(errors,[]);
});

// Proves: CL-040-02, CL-040-06, CL-010-16; TC-007-009 the UDP editor takes an IPv6 multicast group (#46).
test('TC-007-009 the UDP editor saves an IPv6 multicast target with hop limit and interface index',{timeout:60000},async t=>{
  const {page,app,errors}=await fixture(t,{width:1366,height:768},{inputDevice:'test-only-unopened-input'});
  const puts=[];
  page.on('request',r=>{if(r.method()==='PUT'&&new URL(r.url()).pathname==='/udp')puts.push(JSON.parse(r.postData()));});
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  const initial=await (await fetch(app.origin+'/udp')).json();
  await page.locator('#open-server-settings').click();await page.locator('#tab-logging').click();
  const rows=page.locator('#udp-targets .udp-target');await rows.first().waitFor();
  const row=rows.nth(0);
  await row.locator('[data-f=accept]').check();
  await row.locator('[data-f=address]').fill('[ff12::5754:5358]:2237');
  assert.equal(await row.locator('[data-f=accept]').isDisabled(),true,'no accept_commands for an IPv6 group');
  assert.equal(await row.locator('[data-f=accept]').isChecked(),false);
  assert.match(await row.locator('[data-f=iface-note]').textContent(),/hop limit.*index.*link-local group needs one/s);
  assert.equal(await row.locator('[data-f=iface]').getAttribute('placeholder'),'interface index');
  // Without an interface the station refuses the link-local group and names the field.
  await page.locator('#udp-save').click();await page.locator('#udp-result').filter({hasText:'Not saved'}).waitFor();
  assert.match(await page.locator('#udp-result').textContent(),/invalid_request \(targets\[0\]\.multicast_interface\)/);
  await row.locator('[data-f=ttl]').fill('2');await row.locator('[data-f=iface]').fill('1');
  await page.locator('#udp-save').click();await page.locator('#udp-result').filter({hasText:'Saved'}).waitFor();
  const target={address:'[ff12::5754:5358]:2237',enabled:true,multicast_ttl:2,multicast_interface:'1',
    messages:['heartbeat','status','decode','clear','qso_logged','close','logged_adif'],accept_commands:false};
  assert.equal(puts.length,2);
  assert.deepEqual(puts[1].configuration,{instance_name:'WSTX-Rust',targets:[target]},'the TTL field is the hop limit, the interface its index');
  const saved=await (await fetch(app.origin+'/udp')).json();
  assert.deepEqual(saved.configuration.targets,[target]);assert.equal(saved.revision,initial.revision+1);
  // A wider-scope group drops the link-local hint.
  await row.locator('[data-f=address]').fill('[ff05::5754:5358]:2237');
  assert.doesNotMatch(await row.locator('[data-f=iface-note]').textContent(),/needs one/);
  assert.deepEqual(errors,[]);
});

// Proves: CL-010-16; TC-007-009 restart changes ask first during a QSO.
test('TC-007-009 band, mode and Apply ask before restarting receive during a QSO',{timeout:40000},async t=>{
  let contact=null;const selects=[],puts=[];
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{contact})}));
    await p.route('**/receive/select',async route=>{selects.push(JSON.parse(route.request().postData()));await route.fulfill({status:409,json:{error:{code:'state_conflict'}}});});
    p.on('request',r=>{if(r.method()==='PUT'&&new URL(r.url()).pathname==='/profile')puts.push(r);});
  }});
  await page.waitForFunction(()=>!!window.wstxContact?.snapshot()&&operatingState&&!document.querySelector('#operating-band').disabled,null,{timeout:25000});
  contact=partner('report');await page.evaluate(()=>window.wstxContact.load());await page.waitForFunction(()=>window.wstxContact.snapshot().contact?.state==='report');
  await page.selectOption('#operating-band','20m');
  await page.locator('#op-confirm[open]').waitFor();assert.match(await page.locator('#op-confirm-text').textContent(),/restarts receive and interrupts the QSO/);
  await page.locator('#op-confirm button[value=cancel]').click();await page.waitForTimeout(300);
  assert.deepEqual(selects,[],'cancelled band change sends nothing');assert.equal(await page.locator('#operating-band').inputValue(),await page.evaluate(()=>operatingState.selection.band??''),'the select shows the confirmed band again');
  await page.selectOption('#operating-band','20m');await page.locator('#op-confirm[open]').waitFor();await page.locator('#op-confirm-ok').click();
  for(let i=0;i<40&&!selects.length;i++)await page.waitForTimeout(50);
  assert.equal(selects.length,1);assert.equal(selects[0].band,'20m');
  await page.locator('#open-server-settings').click();await page.locator('#callsign').fill('HB9BLB');await page.locator('#station-continent').scrollIntoViewIfNeeded();
  await page.locator('#settings-general .op-apply').click();await page.locator('#op-confirm[open]').waitFor();
  await page.locator('#op-confirm button[value=cancel]').click();await page.waitForTimeout(300);assert.equal(puts.length,0,'Apply waits for the confirmation');
  await page.locator('#settings-general .op-apply').click();await page.locator('#op-confirm-ok').click();
  await page.locator('#general-apply-result').filter({hasText:/Saved revision/}).waitFor();assert.equal(puts.length,1);
  contact=null;await page.evaluate(()=>window.wstxContact.load());await page.waitForFunction(()=>!window.wstxContact.snapshot().contact);
  await page.locator('#callsign').fill('HB9BLA');await page.locator('#settings-general .op-apply').click();
  await page.locator('#general-apply-result').filter({hasText:/Saved revision 2/}).waitFor();assert.equal(await page.locator('#op-confirm').evaluate(d=>d.open),false,'without a QSO Apply needs no confirmation');
  assert.deepEqual(errors,[]);
});

// Proves: CL-010-16, CL-010-11; TC-007-009 Rx/Tx strip, markers and keyboard.
test('TC-007-009 the Rx/Tx strip, marker drag and WSJT-X keys send exactly the expected requests',{timeout:70000},async t=>{
  const commands=[];let settings={rx_hz:1500,tx_hz:1200,hold_tx:false};
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{settings})}));
    await contactCommands(p,commands);
  }});
  await page.waitForFunction(()=>window.wstxContact?.snapshot()&&!document.querySelector('#contact-rx').disabled,null,{timeout:45000}).catch(async e=>{throw new Error('strip '+JSON.stringify(await page.evaluate(()=>[!!window.wstxContact,!!window.wstxContact?.snapshot(),document.querySelector('#contact-rx').disabled,typeof live,String(snapshot),connection.dataset.state])));});
  const last=async n=>{for(let i=0;i<40&&commands.length<n;i++)await page.waitForTimeout(50);assert.equal(commands.length,n,`command ${n}: ${JSON.stringify(commands.slice(-3))}`);const c=commands.at(-1);return [c.action,c.rx_hz,c.tx_hz,c.enabled];};
  await page.locator('#rxtx-strip [data-strip-step="rx:1"]').click();assert.deepEqual(await last(1),['set_frequency',1501,null,undefined]);
  await page.locator('#rxtx-strip [data-strip-step="tx:-1"]').click({modifiers:['Shift']});assert.deepEqual(await last(2),['set_frequency',null,1190,undefined],'Shift steps 10 Hz from the confirmed value');
  await page.locator('#contact-rx').hover();await page.mouse.wheel(0,-100);assert.deepEqual(await last(3),['set_frequency',1501,null,undefined],'wheel up +1 Hz');
  await page.locator('#contact-tx').focus();await page.keyboard.press('Shift+ArrowUp');assert.deepEqual(await last(4),['set_frequency',null,1210,undefined]);
  await page.locator('#contact-tx').fill('1650');await page.keyboard.press('Tab');assert.deepEqual(await last(5),['set_frequency',null,1650,undefined],'exact Hz typed');
  await page.locator('#strip-tx-from-rx').click();assert.deepEqual(await last(6),['set_frequency',null,1500,undefined]);
  await page.locator('#strip-rx-from-tx').click();assert.deepEqual(await last(7),['set_frequency',1200,null,undefined]);
  await page.locator('#contact-hold').check();assert.deepEqual(await last(8),['set_hold_tx',undefined,undefined,true]);
  await page.locator('#waterfall').focus();
  await page.keyboard.press('F12');assert.deepEqual(await last(9),['set_frequency',1501,null,undefined],'F12 Rx +1 Hz');
  await page.keyboard.press('Shift+F11');assert.deepEqual(await last(10),['set_frequency',null,1140,undefined],'Shift+F11 Tx -60 Hz (FT8)');
  await page.keyboard.press('Control+F11');assert.deepEqual(await last(11),['set_frequency',1499,1199,undefined]);
  // The Tx marker drags: one request on release, at the released axis frequency.
  const box=await page.locator('#waterfall').boundingBox(),marker=await page.locator('#waterfall-wrap .ct-txm').boundingBox();
  await page.mouse.move(marker.x+2,marker.y+marker.height/2);await page.mouse.down();await page.mouse.move(box.x+box.width*2000/3000,marker.y+marker.height/2,{steps:5});await page.mouse.up();
  const drag=await last(12);assert.equal(drag[0],'set_frequency');assert.equal(drag[1],null);assert.ok(Math.abs(drag[2]-2000)<=2,`dragged Tx ${drag[2]}`);
  // Letters and ? are inactive while typing; outside a field ? opens the overview.
  await page.locator('#qso-more summary').click();await page.locator('#dx-call').focus();await page.keyboard.type('?');assert.equal(await page.locator('#region-help').isVisible(),false);
  await page.locator('#waterfall').focus();await page.keyboard.press('?');assert.equal(await page.locator('#region-help').isVisible(),true);
  await page.locator('#region-help .return-operate').click();
  assert.equal(commands.some(c=>c.action==='enable_tx'||c.action==='redecode'),false,'no strip, pointer or key action enables Tx or re-decodes');
  // The waterfall speed in the corner applies at once and is remembered by this browser.
  await page.locator('#display-speed').fill('4');await page.locator('#display-speed').dispatchEvent('input');assert.equal(await page.locator('#speed-value').textContent(),'40 px/s');
  await page.reload();await page.locator('#connection[data-state=connected]').waitFor();assert.equal(await page.locator('#display-speed').inputValue(),'4');assert.equal(await page.evaluate(()=>speed),4);
  assert.deepEqual(errors,[]);
});

// Proves: CL-010-16, CL-010-01, CL-010-09; TC-007-009 QSO pane, Band Activity history and menu.
test('TC-007-009 QSO pane buttons and a double-click start transmission; Band Activity keeps period history',{timeout:45000},async t=>{
  let state,contact=null,records=[];const commands=[],period=['2026-10-27T12:00:00.0000000Z','2026-10-27T12:00:15.0000000Z'];
  const standard=(from,to='CQ')=>({type:'standard',to:{kind:to==='CQ'?'token':'call',text:to,hash_bits:null,hash_value:null},from:{kind:'call',text:from,hash_bits:null,hash_value:null},ack:false,exchange:{kind:'grid',value:'FN42'}});
  const record=(sequence,text,from,hz,p,to='CQ')=>({sequence,start_frame:6000,frequency_hz:hz,snr_db:-10,dt_seconds:0.1,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text,fields:standard(from,to),period_start_utc:p});
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    state=liveFixture(await (await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    records=[record(0,'CQ K1ABC FN42','K1ABC',1000,period[0]),record(1,'CQ W1XYZ FN42','W1XYZ',1480,period[0])];
    Object.assign(state.job,{first_sequence:0,next_sequence:2,available_count:2,latest_decode:{id:1,first_sequence:0,next_sequence:2,period_start_utc:period[0],complete:true}});
    await p.route('**/receive',async route=>{await p.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await p.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor')),batch=records.slice(cursor),next=cursor+batch.length;await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:records.length,available_count:records.length,next,more:false,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{contact})}));
    await contactCommands(p,commands);
  }});
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===2&&window.wstxContact?.snapshot(),null,{timeout:25000});
  // Independent great-circle distance between the JN47AA and FN42 square centres (R 6371 km).
  const rad=Math.PI/180,[pa,pb]=[[47+1/48,8+1/24],[42.5,-71]],km=Math.round(2*6371*Math.asin(Math.sqrt(Math.sin((pb[0]-pa[0])*rad/2)**2+Math.cos(pa[0]*rad)*Math.cos(pb[0]*rad)*Math.sin((pb[1]-pa[1])*rad/2)**2)));
  assert.deepEqual(await page.locator('tr[data-result-id]').evaluateAll(rows=>rows.map(r=>[r.children[4].textContent,r.children[5].textContent,r.children[6].textContent,r.className])),[['CQ K1ABC FN42','\u2014',`${km} km`,'ba-cq'],['CQ W1XYZ FN42','\u2014',`${km} km`,'ba-cq']],'columns, distance JN47AA-FN42 and the CQ colour');
  // QSO pane: W1XYZ at 1480 Hz is within +/-50 Hz of Rx 1500: marked and counted.
  await page.locator('#qso-crowd').filter({hasText:'1 near Rx'}).waitFor();
  assert.equal(await page.locator('#rx-pane-rows tr[data-crowd=true]').filter({hasText:'CQ W1XYZ FN42'}).count(),1);
  // A new period keeps the previous one below a divider, newest first.
  records.push(record(2,'HB9BLA K1ABC -05','K1ABC',1010,period[1],'HB9BLA'));
  Object.assign(state.job,{next_sequence:3,available_count:3,latest_decode:{id:2,first_sequence:2,next_sequence:3,period_start_utc:period[1],complete:true}});
  await page.evaluate(()=>receiveSync());await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===1&&document.querySelectorAll('tr[data-period=history]').length===2);
  const order=await page.locator('#band-activity tbody tr').evaluateAll(rows=>rows.map(r=>r.classList.contains('ba-divider')?'|'+r.textContent:r.children[4].textContent));
  assert.deepEqual(order,['HB9BLA K1ABC -05','|FT8 period 12:00:00 UTC','CQ K1ABC FN42','CQ W1XYZ FN42']);
  assert.equal(await page.locator('tr[data-period=latest]').getAttribute('class'),'ba-tome','a call to my callsign is highlighted');

  // Right-click menu: Select prepares, Set Rx sets only Rx; neither transmits.
  const k1abc=page.locator('tr[data-period=history]').filter({hasText:'CQ K1ABC FN42'});
  await k1abc.click({button:'right'});await page.locator('#ba-menu [data-menu=select]').click();
  for(let i=0;i<40&&!commands.length;i++)await page.waitForTimeout(50);
  assert.equal(commands.at(-1).action,'select_row');assert.equal(commands.at(-1).row.sequence,0);
  await k1abc.click({button:'right'});await page.locator('#ba-menu [data-menu=rx]').click();for(let i=0;i<40&&commands.length<2;i++)await page.waitForTimeout(50);
  assert.deepEqual([commands[1].action,commands[1].rx_hz,commands[1].tx_hz],['set_frequency',1000,null]);
  assert.equal(commands.some(c=>c.action==='enable_tx'),false,'selection never transmits');
  // Double-click replies: select, then enable_tx with the shown safety revision.
  const n=commands.length;await k1abc.dblclick();for(let i=0;i<60&&commands.length<n+2;i++)await page.waitForTimeout(50);
  assert.deepEqual(commands.slice(n).map(c=>c.action),['select_row','enable_tx'],'one select then arm, no second select from the clicks');
  assert.deepEqual([commands.at(-1).enabled,commands.at(-1).safety_revision],[true,7]);
  // CQ with no contact arms (a new own CQ); with an active contact it asks first.
  let m=commands.length;await page.locator('#qso-cq').click();for(let i=0;i<40&&commands.length<m+1;i++)await page.waitForTimeout(50);
  assert.deepEqual(commands.slice(m).map(c=>[c.action,c.enabled,c.safety_revision]),[['enable_tx',true,7]]);
  contact=partner('replying');await page.evaluate(()=>window.wstxContact.load());await page.waitForFunction(()=>!document.querySelector('#qso-reply').disabled);
  m=commands.length;await page.locator('#qso-reply').click();for(let i=0;i<40&&commands.length<m+1;i++)await page.waitForTimeout(50);
  assert.deepEqual(commands.slice(m).map(c=>[c.action,c.enabled]),[['enable_tx',true]],'Reply arms the prepared contact');
  m=commands.length;await page.locator('#qso-rr73').click();for(let i=0;i<60&&commands.length<m+3;i++)await page.waitForTimeout(50);
  assert.deepEqual(commands.slice(m).map(c=>[c.action,c.form??c.slot??c.enabled]),[['set_tx4','rr73'],['choose_next','tx4'],['enable_tx',true]],'RR73: Tx4 as RR73 next, then transmit');
  m=commands.length;await page.locator('#qso-73').click();for(let i=0;i<60&&commands.length<m+2;i++)await page.waitForTimeout(50);
  assert.deepEqual(commands.slice(m).map(c=>[c.action,c.slot??c.enabled,c.safety_revision]),[['choose_next','tx5',undefined],['enable_tx',true,7]],'73 on a contact in progress: Tx5 next, then transmit');
  // #37 review: on a completed contact Enable Tx would start a fresh CQ, so RR73 and 73 are off.
  contact=partner('completed');await page.evaluate(()=>window.wstxContact.load());await page.waitForFunction(()=>document.querySelector('#qso-73').disabled);
  assert.deepEqual([await page.locator('#qso-rr73').isDisabled(),await page.locator('#qso-73').isDisabled()],[true,true],'RR73 and 73 disabled on a completed contact');
  m=commands.length;await page.locator('#qso-rr73').click({force:true});await page.locator('#qso-73').click({force:true});
  await page.locator('#qso-73').evaluate(b=>{b.disabled=false;b.click();b.disabled=true;});await page.waitForTimeout(500);
  assert.deepEqual(commands.slice(m),[],'a completed contact sends no choose_next or enable_tx');
  contact=partner('replying');await page.evaluate(()=>window.wstxContact.load());await page.waitForFunction(()=>!document.querySelector('#qso-73').disabled);
  m=commands.length;await page.locator('#qso-cq').click();await page.locator('#op-confirm[open]').waitFor();
  assert.match(await page.locator('#op-confirm-text').textContent(),/Abandon the QSO with K1ABC/);await page.locator('#op-confirm button[value=cancel]').click();await page.waitForTimeout(300);
  assert.equal(commands.length,m,'cancelled CQ sends nothing');
  assert.equal(await page.locator('#contact-enable').count(),0);assert.equal(commands.some(c=>c.action==='redecode'),false);
  assert.deepEqual(errors,[]);
});

// Proves: CL-010-16; TC-007-009 themes are browser-local.
test('TC-007-009 Day, Dark and Night themes switch manually and by time without a station request',{timeout:60000},async t=>{
  const {page,errors}=await fixture(t,{width:1366,height:768});
  const mutations=[];page.on('request',r=>{if(r.method()!=='GET')mutations.push(new URL(r.url()).pathname);});
  assert.equal(await page.evaluate(()=>document.documentElement.dataset.theme),'dark');
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  await page.locator('#open-server-settings').click();await page.locator('#tab-general').click();
  for(const theme of ['day','night','dark']){await page.selectOption('#theme-choice',theme);assert.equal(await page.evaluate(()=>document.documentElement.dataset.theme),theme);}
  await page.selectOption('#theme-choice','night');await page.selectOption('#theme-switch','time');
  const expected=await page.evaluate(()=>{const m=new Date().getHours()*60+new Date().getMinutes();return m>=420&&m<1200?'day':'night';});
  assert.equal(await page.evaluate(()=>document.documentElement.dataset.theme),expected,'by time: Day 07:00-20:00, otherwise Night');
  await page.selectOption('#theme-switch','sun');assert.match(await page.locator('#theme-status').textContent(),/sunrise \d\d:\d\d UTC, sunset \d\d:\d\d UTC at JN47AA/);
  await page.reload();await page.locator('#connection[data-state=connected]').waitFor();
  assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('wstx.theme.v1')).mode),'sun','the choice persists in this browser');
  assert.deepEqual(mutations,[],'themes never send a station request');assert.deepEqual(errors,[]);
});

// Proves: CL-008-03, CL-010-16; TC-009-005 case1 (no automatic restart or mutation retry).
// Investigation guard for #37: with a running receive, reconnects, status refreshes, repeated
// readiness and a second tab never send a receive start, stop or selection by themselves.
test('TC-009-005 no receive start, stop or selection without an operator action across reconnects and two tabs',{timeout:90000},async t=>{
  let running;const mutations=[];
  const watch=p=>{p.on('request',r=>{const path=new URL(r.url()).pathname;if(r.method()!=='GET'&&/^\/receive\/(start|stop|select)$/.test(path))mutations.push(path);});};
  const route=async(p,app)=>{
    if(!running)running=liveFixture(await (await fetch(app.origin+'/receive')).json());
    await p.route('**/receive',route=>route.fulfill({json:running}));
    await p.route('**/receive/results?*',route=>route.fulfill({json:emptyResults(running)}));
  };
  const {page,app,errors}=await fixture(t,{width:1366,height:768},{inputDevice:'test-only-unopened-input',beforeNavigate:async(p,app)=>{watch(p);await route(p,app);}});
  const second=await page.context().newPage();watch(second);await route(second,app);await second.goto(app.origin);await second.locator('#connection[data-state=connected]').waitFor();
  const running_=async p=>{for(let i=0;i<80;i++){const state=await p.evaluate(()=>{if(!livePending&&connection.dataset.state==='connected')receiveSync();return live?.job?.state;});if(state==='running')return true;await p.waitForTimeout(250);}return false;};
  for(const p of [page,second])assert.equal(await running_(p),true);
  const until=Date.now()+15000;
  for(let round=0;Date.now()<until;round++){
    const p=round%2?second:page;
    if(round%3===0){await p.evaluate(()=>socket.close());await p.locator('#connection[data-state=connected]').waitFor({timeout:20000});}
    else if(round%3===1)await refreshStatus(p);
    else await p.evaluate(()=>{dispatchEvent(new CustomEvent('station-ready',{detail:socket}));dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'receive.state',data:{}}}}));});
    await p.waitForTimeout(1500);
  }
  assert.deepEqual(mutations,[],'no receive mutation without an operator action');
  for(const p of [page,second])assert.equal(await running_(p),true);
  await second.close();assert.deepEqual(errors,[]);
});

// Proves: CL-010-16, CL-022-01; TC-007-009 unauthorized view.
test('TC-007-009 an unauthorized browser sees only the token form until it is authorized',{timeout:60000},async t=>{
  const selfsigned=require('selfsigned'),dir=await fs.mkdtemp(path.join(root,'secure-')),port=await browserPort(),origin=`https://localhost:${port}`;
  const cert=await selfsigned.generate([{name:'commonName',value:'localhost'}],{days:1,keySize:2048,extensions:[{name:'subjectAltName',altNames:[{type:2,value:'localhost'},{type:7,ip:'127.0.0.1'}]}]});
  await fs.writeFile(path.join(dir,'cert.pem'),cert.cert);await fs.writeFile(path.join(dir,'key.pem'),cert.private);
  const doc={schema_version:1,profile_id:crypto.randomUUID(),revision:0,display_name:'HB9BLA <secure>',callsign:'HB9BLA',locator:'JN47AA',endpoint:{bind:`127.0.0.1:${port}`,origin},connection_type:'standard',audio:{input_device:null,output_device:null},control:{mode:'disabled',endpoint:null,ptt:'disabled'}};
  await fs.writeFile(path.join(dir,'profile.json'),JSON.stringify(doc));
  const token=crypto.randomBytes(32).toString('hex'),app=await server({WSTX_TLS_CERT:path.join(dir,'cert.pem'),WSTX_TLS_KEY:path.join(dir,'key.pem'),WSTX_TOKEN:token},['--profile',dir]);
  const context=await browser.newContext({ignoreHTTPSErrors:true,viewport:{width:1366,height:768}});t.after(async()=>{await context.close();await app.close();});
  const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(origin);await page.locator('#login').waitFor({state:'visible'});
  for(const [width,height] of [[1366,768],[360,800]]){
    await page.setViewportSize({width,height});
    const visible=await page.evaluate(()=>[...document.querySelectorAll('main *')].filter(el=>el.getClientRects().length&&getComputedStyle(el).visibility!=='hidden'&&(el.matches('button,input,select,textarea,a,canvas,table,[tabindex]')||[...el.childNodes].some(n=>n.nodeType===3&&n.textContent.trim()))).map(el=>({id:el.id,inLogin:!!el.closest('#login-view'),connection:el.id==='connection'})).filter(e=>!e.inLogin&&!e.connection));
    assert.deepEqual(visible,[],`only the token form and its status line are shown at ${width}px`);
    assert.equal(await page.locator('#token').isVisible(),true);assert.equal(await page.locator('#login button').isVisible(),true);
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
    await page.screenshot({path:`test-results/ui-operating/unauthorized-${width}.png`});
  }
  await page.setViewportSize({width:1366,height:768});
  await page.locator('#token').fill(token);await page.locator('#login button').click();await page.locator('#connection[data-state="connected"]').waitFor();
  assert.equal(await page.locator('#login-view').isVisible(),false);
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  for(const selector of ['#operating-workspace','#radio-toolbar','#halt-tx','#rxtx-strip','#qso-cq'])assert.equal(await page.locator(selector).isVisible(),true,`${selector} after authorization`);
  assert.deepEqual(errors,[]);
});

// Proves: CL-010-05, CL-010-07, CL-010-08; TC-007-002 actual form state survives region changes.
test('TC-007-002 in-page navigation preserves unsaved profile and selected recording with no command replay',{timeout:20000},async t=>{
 const {page,errors}=await fixture(t,{width:1440,height:950});
 const mutations=[];page.on('request',r=>{if(r.method()!=='GET')mutations.push({method:r.method(),url:r.url()});});
 await page.keyboard.press('F2');assert.equal(await page.locator('#settings-drawer').isVisible(),true);
 await page.locator('#tab-general').click();await page.locator('#display-name').fill('Unsaved operator edit');
 await returnToOperation(page);assert.equal(await page.locator('#settings-drawer').isVisible(),false);
 await page.locator('#open-server-settings').click();await page.locator('#tab-expert').click();
 await page.locator('#recording-file').setInputFiles({name:'selected-but-not-imported.wav',mimeType:'audio/wav',buffer:Buffer.from('not imported')});
 await returnToOperation(page);
 for(const name of ['logbook','help']){
  const button=page.locator(`#station-bar [data-region="${name}"]`);await button.focus();await page.keyboard.press('Enter');
  assert.equal(await page.locator(`#region-${name}`).isVisible(),true);
  assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
  assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isDisabled(),true);
  await returnToOperation(page);assert.equal(await button.evaluate(el=>document.activeElement===el),true);
 }
 await page.locator('#open-server-settings').click();await page.locator('#tab-general').click();assert.equal(await page.locator('#display-name').inputValue(),'Unsaved operator edit');
 await page.locator('#tab-expert').click();
 assert.equal(await page.locator('#recording-file').evaluate(el=>el.files[0].name),'selected-but-not-imported.wav');
 // Escape is the keyboard Halt Tx (WstxContact::HaltTx D5): until the contact snapshot
 // shows a receive-only station it sends the idempotent #9 halt, never anything else.
 assert.deepEqual(mutations.filter(m=>new URL(m.url).pathname!=='/transmit/halt'),[],'navigation does not save/import or issue station mutations');
 assert.ok(mutations.every(m=>m.method==='POST'),'only the keyboard halt POST');
 assert.deepEqual(errors,[]);
});

// Proves: TC-007-002 readable rem typography and actual 200% text enlargement, every region.
test('TC-007-002 readable text reflows throughout every operating region at 200 percent',{timeout:60000},async t=>{
 const {page,errors,sent}=await fixture(t,{width:1200,height:900});
 const regions=['operate','general','radio','logging','expert','logbook','help'];
 const findings=[];
 for(const scale of [1,2])for(const width of [360,1200,1600]){
  await page.setViewportSize({width,height:1000});
  // Root font-size exercises actual rem text enlargement, not device pixels or a screenshot scale.
  await page.evaluate(factor=>document.documentElement.style.fontSize=`${factor*100}%`,scale);
  await page.waitForTimeout(60);
  for(const region of regions){
   const drawerTabs=['general','radio','logging','expert'];
   // Pages open from the top bar; the drawer sections from Settings (navigation itself is tested above).
   await page.evaluate(()=>showRegion('operate'));await page.evaluate(()=>showRegion('operate'));
   if(drawerTabs.includes(region))await page.evaluate(r=>{showRegion('server-settings');drawerTab(r);},region);
   else if(region!=='operate'){await page.locator(`#station-bar button[data-region="${region}"]`).focus();await page.keyboard.press('Enter');}
   const container=region==='operate'?'#operating-workspace':drawerTabs.includes(region)?`#settings-${region}`:`#region-${region}`;
   await page.locator(container).evaluate(async el=>{for(const details of el.querySelectorAll('details'))details.open=true;await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));});
   const result=await page.evaluate(({container,scale})=>{
    // The drawer covers part of the running waterfall by design; its own text is checked.
    const regions=container.startsWith('#settings-')?[document.querySelector('#station-bar'),document.querySelector(container)]:[document.querySelector('#station-bar'),document.querySelector('#signal'),document.querySelector('#rxtx-strip'),document.querySelector(container)];
    const violations=[],clipped=[],overlap=[],textBoxes=[];let checked=0;
    const visible=el=>el.getClientRects().length&&getComputedStyle(el).visibility!=='hidden'&&getComputedStyle(el).clipPath!=='inset(50%)';
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
 // #37 columns: UTC, dB, DT, Freq, Message, DXCC, Dist (the payload status is in the message).
 const {page,errors}=await fixture(t,{width:1440,height:1000}),rows=bandPresentationFixture.rows.map((r,i)=>({...r,values:[...r.values.slice(0,5),'—',i%3?'—':'19999 km']}));
 // The contact client re-renders Band Activity when it arrives; insert the fixture after it.
 await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
 await page.locator('#band-activity header .op-muted').evaluate(node=>node.textContent='Presentation fixture: captured FT4/FT8 text and synthetic edge cases; not decoder truth');
 await page.locator('#band-activity tbody').evaluate((tbody,rows)=>{const labels=[...document.querySelectorAll('#band-activity th')].map(th=>th.textContent);tbody.replaceChildren();for(const item of rows){const row=document.createElement('tr');row.dataset.presentationFixture=item.kind;row.setAttribute('role','row');for(const [index,value] of item.values.entries()){const td=document.createElement('td');td.setAttribute('role','cell');td.dataset.label=labels[index];td.textContent=value;row.append(td);}tbody.append(row);}},rows);
 assert.equal(await page.locator('tr[data-result-id]').count(),0,'presentation fixtures never claim production decoder records');
 for(const scale of [1,2])for(const width of [360,720,1200,1440,1600]){
  await page.setViewportSize({width,height:1000});await page.evaluate(scale=>document.documentElement.style.fontSize=`${scale*100}%`,scale);await page.evaluate(()=>new Promise(requestAnimationFrame));
  const cells=await page.locator('#band-activity tbody td').evaluateAll(nodes=>nodes.map((td,index)=>{const box=td.getBoundingClientRect(),range=document.createRange();range.selectNodeContents(td);return {text:td.textContent,font:parseFloat(getComputedStyle(td).fontSize),whiteSpace:getComputedStyle(td).whiteSpace,label:td.dataset.label,generatedLabel:getComputedStyle(td,'::before').content,lines:range.getClientRects().length,inside:[...range.getClientRects()].every(r=>r.left>=box.left-1&&r.right<=box.right+1&&r.top>=box.top-1&&r.bottom<=box.bottom+1)};}));
  assert.deepEqual(cells.map(c=>c.text),rows.flatMap(r=>r.values));
  assert.ok(cells.every(c=>c.font>=16*scale&&c.inside),`literal text stays within its own field ${width}px ${scale}x: ${JSON.stringify(cells.filter(c=>!c.inside))}`);
  assert.ok(cells.every((c,i)=>i%7===4?c.whiteSpace==='normal':c.whiteSpace==='nowrap'&&c.lines===1),`numbers/time/status never split ${width}px ${scale}x`);
  const layout=await page.evaluate(()=>{const b=document.querySelector('#band-activity').getBoundingClientRect(),q=document.querySelector('#rx-focus').getBoundingClientRect(),g=document.querySelector('.operating-grid'),cs=getComputedStyle(g),available=g.clientWidth-parseFloat(cs.paddingLeft)-parseFloat(cs.paddingRight);return {band:b.width,available,ratio:b.width/(b.width+q.width),details:getComputedStyle(document.querySelector('#band-activity tbody tr')).display==='grid',overflow:document.documentElement.scrollWidth>innerWidth};});
  assert.equal(layout.overflow,false,`no page overflow ${width}px ${scale}x`);
  if(scale===1&&width>1200)assert.ok(layout.ratio>=.55&&layout.ratio<=.6,`Band Activity owns 55-60% of allocated card widths: ${JSON.stringify(layout)}`);
  else assert.ok(Math.abs(layout.band-layout.available)<2,`Band Activity full width ${width}px ${scale}x`);
  if(layout.details)assert.ok(cells.every(c=>c.generatedLabel.includes(c.label)),`all6 field labels visible ${width}px ${scale}x`);
  assert.equal(await page.getByRole('columnheader').count(),7,'column semantics retained in row-details view');
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
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===16);
  await clickSort(page,'frequency');assert.deepEqual(await sortState(page),['frequency','desc']);
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===18);
  assert.equal(await page.locator('tr[data-period=latest]').first().getAttribute('data-sequence'),'18','new page re-sorts the entire selected view');
  await clickSort(page,'frequency');assert.deepEqual(await sortState(page),['frequency','asc']);
  assert.doesNotMatch((await page.locator('tr[data-period=latest]').allInnerTexts()).join('\n'),/STATION 0\b/);

  const cells=page.locator('tr[data-period=latest]').first().locator('td');assert.equal(await cells.nth(0).textContent(),'12:00:15');assert.equal(await cells.nth(2).textContent(),'-0.2');
  assert.equal(await page.locator('tr[data-period=latest]').nth(1).locator('td').nth(2).textContent(),'+0.2');assert.equal(await page.locator('tr[data-period=latest]').nth(2).locator('td').nth(2).textContent(),'+0.0');
  for(const width of [1440,360])for(const scale of [1,2]){await page.setViewportSize({width,height:900});await page.evaluate(scale=>document.documentElement.style.fontSize=16*scale+'px',scale);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);assert.deepEqual(await cells.evaluateAll(nodes=>nodes.filter(n=>n.scrollWidth>n.clientWidth+1).map(n=>n.textContent)),[]);await page.screenshot({path:`test-results/ui-operating/latest-period-${width}-${scale}x.png`,fullPage:true});}
  await page.evaluate(()=>document.documentElement.style.fontSize='16px');
  const nextPeriod='2026-10-27T12:00:30.0000000Z';records.push(...Array.from({length:18},(_,i)=>makeRecord(i+19,nextPeriod,0.1)));
  Object.assign(state.job,{next_sequence:37,available_count:37,latest_decode:{id:2,first_sequence:19,next_sequence:37,period_start_utc:nextPeriod,complete:false}});hold=true;
  await refreshStatus(page);await pending.promise;
  assert.equal(await page.locator('tr[data-period=latest]').count(),16);assert.match(await page.locator('#band-activity header').innerText(),/Partial.*Loading results/);
  assert.doesNotMatch((await page.locator('tr[data-period=latest]').allInnerTexts()).join('\n'),/STATION 1\b/);
  // BandActivityView: the replaced period stays below its divider, never in the latest view.
  assert.equal(await page.locator('tr[data-period=history]').count(),18);assert.match(await page.locator('tr.ba-divider').first().textContent(),/12:00:15 UTC/);
  assert.equal(await page.locator('tr[data-period=history]').filter({hasText:/STATION 1(?!\d)/}).count(),1);
  state.job.latest_decode={id:3,first_sequence:37,next_sequence:37,period_start_utc:'2026-10-27T12:00:45.0000000Z',complete:true};
  await refreshStatus(page);await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===0);
  await held.route.fulfill({json:held.response});held=null;hold=false;
  const history=await page.locator('tr[data-period=history]').count();
  await page.waitForTimeout(500);assert.equal(await page.locator('tr[data-period=latest]').count(),0);assert.match(await page.locator('#band-activity').innerText(),/No stations decoded/);
  assert.equal(await page.locator('tr[data-period=history]').count(),history,'an obsolete page cannot add to the history either');
  assert.equal(await page.evaluate(()=>resultCursor),37,'old period page cannot move new view cursor');assert.deepEqual(errors,[]);
});

// Proves: CL-007-05; TC-004-004. A late window extends the period view in place (#47).
test('TC-004-004 a correlated period view extended in place adds the late starter without an error or a reload',{timeout:35000},async t=>{
  let state,records,requested=[];
  const period='2026-10-27T12:00:15.0000000Z';
  const makeRecord=(sequence,dt)=>({sequence,start_frame:186000+sequence,frequency_hz:1000+sequence,snr_db:-12.3,payload77:'0'.repeat(77),i3:0,n3:0,status:'decoded',text:`LATE FIXTURE ${sequence}`,fields:{},period_start_utc:period,dt_seconds:dt});
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(page,app)=>{
    state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    records=[makeRecord(0,0.1),makeRecord(1,0.2)];
    Object.assign(state.job,{first_sequence:0,next_sequence:2,available_count:2,latest_decode:{id:1,first_sequence:0,next_sequence:2,period_start_utc:period,complete:false}});
    await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await page.route('**/receive/results?*',async route=>{
      const query=new URL(route.request().url()).searchParams,cursor=Number(query.get('cursor')),limit=Number(query.get('limit'));requested.push(cursor);
      const batch=records.slice(cursor,cursor+limit),next=cursor+batch.length;
      await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:records.length,available_count:records.length,next,more:next<records.length,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});
    });
  }});
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===2);
  const before=requested.length;
  // The late window of the same period: same id, period and first_sequence, one more record
  // (DT +1.2 s), and the view completes.
  records.push(makeRecord(2,1.2));
  Object.assign(state.job,{next_sequence:3,available_count:3,latest_decode:{id:1,first_sequence:0,next_sequence:3,period_start_utc:period,complete:true}});
  await refreshStatus(page);
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===3,null,{timeout:15000});
  assert.equal(await page.locator('tr[data-period=latest]').filter({hasText:'LATE FIXTURE 2'}).count(),1);
  assert.equal(await page.locator('tr[data-period=history]').count(),0,'an extended view is not a replaced period');
  assert.ok(requested.slice(before).every(cursor=>cursor>=2),`only the new record is fetched: ${requested.slice(before)}`);
  assert.doesNotMatch(await page.locator('#receive-status').innerText(),/unavailable|Changed decode descriptor/i);
  assert.doesNotMatch(await page.locator('#band-activity header').innerText(),/Partial/);
  // A same-id change of anything else stays an error.
  state.job.latest_decode={id:1,first_sequence:1,next_sequence:3,period_start_utc:period,complete:true};
  await refreshStatus(page);
  await page.waitForFunction(()=>/Changed decode descriptor/.test(document.querySelector('#receive-status').textContent),null,{timeout:15000});
  assert.deepEqual(errors,[]);
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
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===18);
  assert.ok(announced);assert.equal(await page.locator('tr[data-period=latest]').first().locator('td').nth(4).textContent(),'PAGE FIXTURE 1');
  assert.equal(await page.locator('tr[data-period=latest]').last().locator('td').nth(4).textContent(),'PAGE FIXTURE 18');assert.deepEqual(errors,[]);
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
  const order=()=>page.locator('tr[data-period=latest]').evaluateAll(rows=>rows.map(r=>Number(r.dataset.sequence)));
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===5);
  assert.deepEqual(await order(),[1,4,0,3,2],'frequency200 precedes1000, numeric ties retain sequence');
  assert.deepEqual(await sortState(page),['frequency','asc']);
  await clickSort(page,'frequency');assert.deepEqual(await sortState(page),['frequency','desc']);assert.deepEqual(await order(),[2,0,3,4,1]);
  await clickSort(page,'signal');assert.deepEqual(await sortState(page),['signal','desc']);assert.deepEqual(await order(),[1,4,3,0,2]);
  await clickSort(page,'signal');assert.deepEqual(await sortState(page),['signal','asc']);assert.deepEqual(await order(),[0,3,4,1,2],'unknown SNR stays last when ascending');
  await clickSort(page,'dt');assert.deepEqual(await sortState(page),['dt','asc']);assert.deepEqual(await order(),[0,3,2,4,1]);await clickSort(page,'dt');assert.deepEqual(await order(),[1,4,2,3,0]);
  await clickSort(page,'message');assert.deepEqual(await sortState(page),['message','asc']);assert.deepEqual(await order(),[4,1,2,0,3]);await clickSort(page,'message');assert.deepEqual(await order(),[0,2,1,4,3]);
  state.job.latest_decode={id:2,first_sequence:5,next_sequence:5,period_start_utc:'2026-10-27T12:00:15.0000000Z',complete:true};await refreshStatus(page);await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===0);
  assert.deepEqual(await sortState(page),['message','desc']);
  state.generation++;state.source.id=crypto.randomUUID();state.job.id=crypto.randomUUID();state.job.mode='ft4';state.job.latest_decode={id:1,first_sequence:0,next_sequence:5,period_start_utc:null,complete:true};records=records.map(r=>({...r,period_start_utc:null,dt_seconds:null}));
  await page.evaluate(()=>socket.close());await page.locator('#connection[data-state=stale]').waitFor();await page.locator('#connection[data-state=connected]').waitFor();await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===5);
  assert.deepEqual(await sortState(page),['message','desc']);
  await clickSort(page,'dt');assert.deepEqual(await sortState(page),['dt','asc']);assert.deepEqual(await order(),[0,1,2,3,4]);await clickSort(page,'dt');assert.deepEqual(await order(),[0,1,2,3,4],'all unknown DT stays in sequence order');
  for(const width of [1440,360])for(const scale of [1,2]){await page.setViewportSize({width,height:900});await page.evaluate(scale=>document.documentElement.style.fontSize=16*scale+'px',scale);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);}
  await page.evaluate(()=>{profileData.profile_id='not-a-valid-uuid';renderResults();});assert.deepEqual(await sortState(page),['dt','desc'],'invalid profile cannot reset preference');
  await page.evaluate(()=>{profileData.profile_id='00000000-0000-4000-8000-000000000001';renderResults();});assert.deepEqual(await sortState(page),['frequency','asc']);
  assert.ok(sent.every(m=>!['radio.operation','receive.start'].includes(m.type)));assert.deepEqual(errors,[]);
});

// Proves: CL-010-04; TC-011-001 browser subset (#41 DirectLog). Actual server and
// Chromium with the contact snapshot answered by the test: a completed contact opens no
// review form and the browser never saves; Log QSO is one open_log command; the QSO pane
// shows the server's log outcome; an open Logbook page lists a newly logged record by
// itself. The record is stored through the server's own SaveContact route, standing in
// for the server-side DirectLog store, which contact_http/udp tests prove.
test('TC-011-001 completed QSOs log without a review and the open Logbook lists them live',{timeout:30000},async t=>{
 let snapshot={contact:null,log:null};const commands=[],posts=[];
 const {page,app,errors}=await fixture(t,{width:1200,height:900},{beforeNavigate:async(p,app)=>{
   const base=await (await fetch(app.origin+'/profile')).json();
   await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,snapshot)}));
   await contactCommands(p,commands);
   p.on('request',r=>{if(r.method()!=='GET')posts.push(new URL(r.url()).pathname);});
 }});
 await page.waitForFunction(()=>profileData&&window.wstxLogbook&&window.wstxContact?.snapshot(),null,{timeout:25000});
 const profile=await (await fetch(app.origin+'/profile')).json();
 const contact=partner('completed',{report_rcvd:'-05'});
 snapshot={contact,log:null};await page.evaluate(()=>window.wstxContact.load());
 await page.waitForFunction(()=>window.wstxContact.snapshot().contact?.state==='completed');
 assert.equal(await page.locator('#operating-workspace').isVisible(),true,'no review page opens at completion');
 assert.equal(await page.locator('#log-review, #log-review-form, [id^=log-field-]').count(),0,'the review form is retired');
 assert.equal(await page.locator('#contact-discard').count(),0);
 await page.getByRole('button',{name:'Log QSO'}).click();
 await page.locator('#contact-result',{hasText:'Log QSO: accepted'}).waitFor();
 assert.deepEqual(commands.map(c=>c.action),['open_log'],'Log QSO is one open_log command');
 assert.deepEqual(Object.keys(commands[0]).sort(),['action','boot_id','command_id','contact_revision','profile_id','v']);
 assert.equal(await page.locator('#operating-workspace').isVisible(),true,'Log QSO opens no form');
 snapshot={contact,log:{contact_id:contact.id,call:'K1ABC',outcome:'unsaved',error:'storage_unavailable'}};await page.evaluate(()=>window.wstxContact.load());
 await page.locator('#contact-logged',{hasText:'Not logged K1ABC \u00b7 storage unavailable \u00b7 retrying'}).waitFor();
 await page.locator('#station-bar [data-region="logbook"]').click();
 await page.locator('#log-history-status',{hasText:'No contacts saved yet'}).waitFor();
 // The server stores the record; the snapshot then reports it saved.
 const record={contact_id:contact.id,call:'K1ABC',gridsquare:'FN42',mode:'FT8',submode:null,rst_sent:'-12',rst_rcvd:'-05',qso_date:'20261031',time_on:'123015',qso_date_off:'20261031',time_off:'123200',band:'20m',freq:'14.075500',station_callsign:'HB9BLA',my_gridsquare:'JN47AA',tx_pwr:null,comment:null};
 const saved=await fetch(app.origin+'/contacts',{method:'POST',headers:{'Content-Type':'application/json',Origin:app.origin},body:JSON.stringify({v:1,profile_id:profile.profile_id,boot_id:profile.boot_id,command_id:crypto.randomUUID(),record})});
 assert.equal(saved.status,201,await saved.text());
 snapshot={contact:{...contact,saved:true},log:{contact_id:contact.id,call:'K1ABC',outcome:'saved',error:null}};await page.evaluate(()=>window.wstxContact.load());
 await page.locator('#log-history li',{hasText:'K1ABC'}).waitFor({timeout:5000});
 assert.match(await page.locator('#log-history-status').innerText(),/1 contact/);
 assert.match(await page.locator('#contact-logged').textContent(),/^Logged K1ABC \u00b7 contacts\.adi$/);
 assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true,'the Logbook page never hides Halt Tx');
 assert.ok(posts.every(p=>p==='/contact/command'),'the browser never saves a contact: '+posts.join());
 assert.deepEqual(errors,[]);
});

test('TC-011-002 ADI import and export controls publish all-or-nothing and download contacts.adi',{timeout:30000},async t=>{
 const {page,errors}=await fixture(t,{width:1200,height:900});
 await page.waitForFunction(()=>profileData&&window.wstxLogbook);
 await page.locator('#station-bar [data-region="logbook"]').click();
 await page.locator('#log-history-status',{hasText:'No contacts saved yet'}).waitFor();
 const good='<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <band:3>20m <mode:3>FT8 <APP_OTHER_X:2>ok <eor>\n<call:5>W1XYZ <qso_date:8>20261031 <time_on:4>1231 <band:3>40m <mode:3>FT8 <eor>\n';
 await page.locator('#log-import-file').setInputFiles({name:'good.adi',mimeType:'text/plain',buffer:Buffer.from(good)});
 await page.getByRole('button',{name:'Import ADIF'}).click();
 await page.locator('#log-import-status',{hasText:'Imported'}).waitFor();
 assert.match(await page.locator('#log-import-status').innerText(),/2 new, 0 duplicate, 0 conflicting/);
 await page.locator('#log-history-status',{hasText:'2 contacts'}).waitFor();
 assert.match(await page.locator('#log-history').innerText(),/1 other field kept/);
 const bad='<call:5>N0NEW <qso_date:8>20261031 <time_on:4>1300 <mode:3>FT8 <eor>\n<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <band:3>20m <mode:3>FT8 <eor\n';
 await page.locator('#log-import-file').setInputFiles({name:'bad.adi',mimeType:'text/plain',buffer:Buffer.from(bad)});
 await page.getByRole('button',{name:'Import ADIF'}).click();
 await page.locator('#log-import-status',{hasText:'Import failed'}).waitFor();
 assert.match(await page.locator('#log-import-status').innerText(),/no contacts were added .*malformed in record 2/);
 await page.locator('#log-history-status',{hasText:'2 contacts'}).waitFor();
 const [download]=await Promise.all([page.waitForEvent('download'),page.getByRole('button',{name:'Export ADIF'}).click()]);
 assert.equal(download.suggestedFilename(),'contacts.adi');
 const text=await fs.readFile(await download.path(),'utf8');
 assert.match(text,/^ADIF Export\n<adif_ver:5>3\.1\.8\n/);
 assert.match(text,/<call:5>K1ABC <mode:3>FT8 <qso_date:8>20261031 <time_on:4>1230 <band:3>20m <app_wstxrust_contact_id:36>[0-9a-f-]{36} <APP_OTHER_X:2>ok <eor>\n/);
 assert.equal(text.match(/<eor>/g).length,2);
 assert.deepEqual(errors,[]);
});

// Proves: CL-010-13; TC-011-003 browser subset. Actual server log and worked-before query;
// receive pages and the manual band selection are presentation fixtures, not RF truth.
test('TC-011-003 Band Activity shows server worked-before status with one bounded query per period',{timeout:30000},async t=>{
 let state;const queries=[];
 const period='2026-10-27T12:00:15.0000000Z';
 const standard=(from)=>({type:'standard',to:{kind:'token',text:'CQ',hash_bits:null,hash_value:null},from:{kind:'call',text:from,hash_bits:null,hash_value:null},ack:false,exchange:{kind:'grid',value:'FN42'}});
 const records=[['K1ABC',standard('K1ABC')],['W1XYZ',standard('W1XYZ')],['FREE',{}]].map(([call,fields],i)=>({sequence:i,start_frame:186000+i,frequency_hz:1000+i*100,snr_db:-10,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text:call==='FREE'?'FREE TEXT':`CQ ${call} FN42`,fields,period_start_utc:period,dt_seconds:0.1}));
 const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(page,app)=>{
  const profile=await(await fetch(app.origin+'/profile')).json();
  const saved=await fetch(app.origin+'/contacts',{method:'POST',headers:{'Content-Type':'application/json',Origin:app.origin},body:JSON.stringify({v:1,profile_id:profile.profile_id,boot_id:profile.boot_id,command_id:crypto.randomUUID(),record:{contact_id:crypto.randomUUID(),call:'K1ABC',gridsquare:null,mode:'FT8',submode:null,rst_sent:null,rst_rcvd:null,qso_date:'20261027',time_on:'115900',qso_date_off:'20261027',time_off:'120000',band:'20m',freq:null,station_callsign:'HB9BLA',my_gridsquare:'JN47AA',tx_pwr:null,comment:null}})});
  assert.equal(saved.status,201);
  state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
  state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
  Object.assign(state.job,{first_sequence:0,next_sequence:3,available_count:3,latest_decode:{id:1,first_sequence:0,next_sequence:3,period_start_utc:period,complete:true}});
  await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
  await page.route('**/receive/selection',async route=>{const s=await(await route.fetch()).json();s.selection={...s.selection,band:'20m',nominal_hz:14074000,origin:'manual'};await route.fulfill({json:s});});
  await page.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor'));const batch=records.slice(cursor),next=cursor+batch.length;await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:3,available_count:3,next,more:false,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
  page.on('request',r=>{if(new URL(r.url()).pathname==='/contact/worked')queries.push(JSON.parse(r.postData()));});
 }});
 await page.locator('tr[data-result-id] .log-worked').first().waitFor();
 const marks=await page.locator('tr[data-result-id]').evaluateAll(rows=>rows.map(r=>[r.children[4].firstChild.textContent,r.querySelector('.log-worked')?.dataset.worked??null,r.querySelector('.log-worked')?.textContent??null]));
 assert.deepEqual(marks,[['CQ K1ABC FN42','worked_this_band_and_mode',' \u00b7 \u2713 worked'],['CQ W1XYZ FN42','not_worked',' \u00b7 \u2605 new'],['FREE TEXT',null,null]]);
 await clickSort(page,'frequency');await page.waitForTimeout(300);
 await refreshStatus(page);await page.waitForTimeout(500);
 assert.equal(queries.length,1,'one query per published period');
 assert.deepEqual(queries[0].calls,['K1ABC','W1XYZ']);assert.equal(queries[0].band,'20m');assert.equal(queries[0].mode,'FT8');
 assert.equal(await page.locator('.log-worked[data-worked=worked_this_band_and_mode]').getAttribute('title'),'Worked before on this band and mode','text label beside colour');
 assert.deepEqual(errors,[]);
});

// Proves: CL-009-05; TC-006-003. The transmit status line shows the station's SNTP clock
// state and measurement from a GET /transmit fixture (no CAT, PTT or audio: the profile's
// CAT PTT setting is set in the page only, the server keeps transmit unsupported).
test('TC-006-003 transmit status shows the SNTP clock measurement',{timeout:45000},async t=>{
  let view;
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(p,app)=>{
    view=await (await fetch(app.origin+'/transmit')).json();
    await p.route('**/transmit',route=>route.request().method()==='GET'?route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(view)}):route.continue());
  }});
  assert.equal(view.clock,'unknown','isolated server never measured');assert.equal(view.clock_measurement,null);
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  const status=async()=>page.evaluate(async()=>{profileData.settings.control.ptt='cat';await transmitSync();return document.querySelector('#transmit-status').textContent;});
  assert.match(await status(),/ · clock unknown · halt /,'no measurement: state only');
  view={...view,clock:'synchronized',clock_measurement:{server:'ch.pool.ntp.org',offset_ms:12,round_trip_ms:20,age_ms:34400}};
  assert.match(await status(),/ · clock synchronized \+12 ms ch\.pool\.ntp\.org 34 s ago · halt /);
  view={...view,clock:'unsynchronized',clock_measurement:{server:'time.windows.com',offset_ms:-2089,round_trip_ms:22,age_ms:5600}};
  assert.match(await status(),/ · clock unsynchronized -2089 ms time\.windows\.com 6 s ago · halt /);
  assert.deepEqual(errors,[]);
});

// Proves: CL-039-01, CL-039-04, CL-039-05; TC-039-006. The browser shows the
// station's verdicts (it never evaluates), sends exactly the PUT /strategy and automation
// requests below, and keeps HALT reachable in the editor popup. Station replies are
// hand-written fixtures; the expected requests and row order are written here.
test('TC-039-006 Highlight marks and sorts, the editor previews and saves, Auto asks once and starts the strategy run',{timeout:60000},async t=>{
  let state,view,automation={run:null,policy:0,runRevision:0};const puts=[],evaluations=[],autos=[],commands=[];
  const period='2026-10-27T12:00:00.0000000Z';
  const standard=(from,to='CQ',grid='FN42')=>({type:'standard',to:{kind:to.startsWith('CQ')?'token':'call',text:to,hash_bits:null,hash_value:null},from:{kind:'call',text:from,hash_bits:null,hash_value:null},ack:false,exchange:{kind:'grid',value:grid}});
  const record=(sequence,text,from,hz,to,grid)=>({sequence,start_frame:6000,frequency_hz:hz,snr_db:-10,dt_seconds:0.1,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text,fields:standard(from,to,grid),period_start_utc:period});
  const records=[record(0,'CQ K1ABC FN42','K1ABC',1000,'CQ','FN42'),record(1,'CQ NA W1AW FN31','W1AW',1200,'CQ NA','FN31'),record(2,'CQ DL1XYZ JO62','DL1XYZ',1400,'CQ','JO62')];
  const strategy={name:'DX first',rules:[{conditions:[{kind:'message',negate:false,value:'cq'},{kind:'continent',negate:true,values:['NA']}]},{conditions:[{kind:'message',negate:false,value:'cq'}]}],sort:'strongest',treat_73_as_cq:false,apply_to_callers:false,skip_after:5,auto_role:'alternate',switch_after:3};
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    view={v:1,profile_id:base.profile_id,boot_id:base.boot_id,revision:4,configuration:{continent:null,active:'DX first',highlight:false,strategies:[strategy]},configuration_error:null,my_continent:'EU',derived_continent:'EU'};
    state=liveFixture(await (await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:period,canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    Object.assign(state.job,{first_sequence:0,next_sequence:3,available_count:3,latest_decode:{id:1,first_sequence:0,next_sequence:3,period_start_utc:period,complete:true}});
    await p.route('**/receive',async route=>{await p.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await p.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor')),batch=records.slice(cursor);await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:3,available_count:3,next:cursor+batch.length,more:false,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base)}));
    await contactCommands(p,commands);
    await p.route('**/strategy',async route=>{if(route.request().method()==='PUT'){const b=JSON.parse(route.request().postData());puts.push(b);view={...view,revision:view.revision+1,configuration:b.configuration};}await route.fulfill({json:view});});
    await p.route('**/strategy/evaluate',async route=>{const b=JSON.parse(route.request().postData());evaluations.push(b);
      const verdicts=b.explain?[{sequence:2,rank:0,grey:false,why:'matches rule 1'},{sequence:0,rank:1,grey:false,why:'matches rule 2'},{sequence:1,rank:null,grey:true,why:'CQ NA is not addressed to my continent (EU)'}]:[{sequence:2,rank:0,grey:false},{sequence:0,rank:1,grey:false},{sequence:1,rank:null,grey:true}];
      await route.fulfill({json:{v:1,profile_id:view.profile_id,boot_id:view.boot_id,strategy:b.strategy?.name??'DX first',my_continent:'EU',sort:'strongest',verdicts}});});
    await p.route('**/automation',route=>route.fulfill({json:{v:1,profile_id:view.profile_id,boot_id:view.boot_id,policy_revision:automation.policy,run_revision:automation.runRevision,configuration:automation.policy?{strategy:true}:null,run:automation.run}}));
    await p.route('**/automation/command',async route=>{const b=JSON.parse(route.request().postData());autos.push(b);if(b.action==='configure')automation.policy++;if(b.action==='start'){automation.runRevision++;automation.run={id:crypto.randomUUID(),state:'waiting',reason:null,mode:'ft8',completed_contacts:0,unanswered_periods:0,contact_id:null,selected:null,last_decision:null,role:'call',tries:0,skipped:[]};}
      if(b.action==='stop'){automation.runRevision++;automation.run={...automation.run,state:'stopped',reason:'stopped'};}await route.fulfill({status:202,json:{v:1,accepted:true}});});
  }});
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===3&&document.querySelector("#strategy-highlight")?.disabled===false,null,{timeout:25000});
  const message=()=>page.locator('#band-activity tr[data-sequence]').evaluateAll(rows=>rows.map(r=>[r.children[4].textContent,r.className.split(' ').filter(c=>c.startsWith('ba-')&&c!=='ba-cq').join(' '),r.dataset.rank??'']));
  assert.equal(await page.inputValue('#strategy-name'),'DX first');
  assert.equal(await page.locator('#strategy-highlight').getAttribute('aria-pressed'),'false');
  await page.waitForTimeout(600);
  assert.deepEqual(evaluations,[],'Highlight off: the client asks for no verdict');
  assert.deepEqual((await message()).map(r=>r[1]),['','',''],'no strategy marks while Highlight is off');
  // Highlight on: one exact PUT, then one evaluation of the shown sequences.
  await page.locator('#strategy-highlight').click();
  for(let i=0;i<60&&!evaluations.length;i++)await page.waitForTimeout(50);
  assert.deepEqual(puts.map(b=>[b.expected_revision,b.configuration]),[[4,{continent:null,active:'DX first',highlight:true,strategies:[strategy]}]]);
  assert.deepEqual(evaluations.map(b=>[b.source_id,b.job_id,b.generation,b.first_sequence,b.next_sequence,b.strategy,b.explain]),[[state.source.id,state.job.id,state.generation,0,3,null,false]]);
  await page.waitForFunction(()=>document.querySelector('#band-activity tr[data-sequence]').children[4].textContent==='CQ DL1XYZ JO62');
  assert.deepEqual(await message(),[['CQ DL1XYZ JO62','ba-strategy','1'],['CQ K1ABC FN42','ba-strategy','2'],['CQ NA W1AW FN31','ba-grey','']],'matches on top in the station order; the directed CQ greyed');
  assert.equal(await page.locator('#strategy-highlight').getAttribute('aria-pressed'),'true');
  await page.screenshot({path:'test-results/ui-operating/strategy-highlight-1366.png'});
  // Editor popup: a draft preview with the reason per decode, HALT inside, Save applies.
  await page.locator('#strategy-edit').click();await page.locator('#strategy-editor[open]').waitFor();
  assert.equal(await page.locator('#strategy-editor-halt').isDisabled(),await page.locator('#halt-tx').isDisabled(),'the popup HALT has the top-bar HALT state');
  await page.locator('#se-preview tr').nth(2).waitFor();
  assert.deepEqual(await page.locator('#se-preview tr').evaluateAll(rows=>rows.map(r=>[...r.children].map(c=>c.textContent))),[['#1','CQ DL1XYZ JO62','matches rule 1'],['#2','CQ K1ABC FN42','matches rule 2'],['—','CQ NA W1AW FN31','CQ NA is not addressed to my continent (EU)']]);
  await page.screenshot({path:'test-results/ui-operating/strategy-editor-1366.png'});
  // Phone width: the popup fits without horizontal scrolling (text reflows inside it).
  await page.setViewportSize({width:360,height:740});
  assert.deepEqual(await page.evaluate(()=>{const d=document.querySelector('#strategy-editor');return {dialog:d.scrollWidth<=d.clientWidth+1,page:document.documentElement.scrollWidth<=innerWidth,inside:d.getBoundingClientRect().right<=innerWidth};}),{dialog:true,page:true,inside:true});
  await page.screenshot({path:'test-results/ui-operating/strategy-editor-360.png'});await page.setViewportSize({width:1366,height:768});
  const draft=evaluations.at(-1);assert.deepEqual([draft.strategy,draft.explain,draft.first_sequence,draft.next_sequence],[strategy,true,0,3],'the preview evaluates the unsaved draft');
  const n=evaluations.length;await page.selectOption('#se-sort','weakest');
  for(let i=0;i<40&&evaluations.length===n;i++)await page.waitForTimeout(50);
  assert.equal(evaluations.at(-1).strategy.sort,'weakest','an edit re-runs the preview');
  await page.locator('.se-condition').first().locator('[data-f=negate]').check();
  await page.locator('#se-save').click();for(let i=0;i<40&&puts.length<2;i++)await page.waitForTimeout(50);
  const edited={...strategy,sort:'weakest',rules:[{conditions:[{kind:'message',negate:true,value:'cq'},strategy.rules[0].conditions[1]]},strategy.rules[1]]};
  assert.deepEqual(puts[1],{v:1,profile_id:view.profile_id,boot_id:view.boot_id,expected_revision:5,configuration:{continent:null,active:'DX first',highlight:true,strategies:[edited]}});
  await page.locator('#se-result').filter({hasText:'Saved'}).waitFor();
  await page.locator('#strategy-editor button[value=cancel]').click();assert.equal(await page.locator('#strategy-editor').evaluate(d=>d.open),false);
  // Auto: the first use asks; Cancel sends nothing; Start sends configure then start.
  await page.locator('#strategy-auto').click();await page.locator('#op-confirm[open]').waitFor();
  assert.match(await page.locator('#op-confirm-text').textContent(),/Auto transmits without asking: it answers only stations that match "DX first" \(Auto Call and Auto CQ, switching after 3 tries\)\. The Tx watchdog \(6 min\) counts from your last action and is never reset by Auto\. HALT or Esc stops it\./);
  await page.locator('#op-confirm button[value=cancel]').click();await page.waitForTimeout(300);assert.deepEqual(autos,[],'cancelled: no automation request');
  await page.locator('#strategy-auto').click();await page.locator('#op-confirm[open]').waitFor();await page.locator('#op-confirm-ok').click();
  for(let i=0;i<60&&autos.length<2;i++)await page.waitForTimeout(50);
  assert.deepEqual(autos.map(b=>[b.action,b.expected_policy_revision,b.expected_run_revision,b.mode,b.safety_revision]),[['configure',0,undefined,undefined,undefined],['start',1,0,'ft8',7]]);
  assert.deepEqual(autos[0].configuration,{modes:['ft8'],ranking:'first_seen',min_snr_db:null,allowed_calls:[],blocked_calls:[],max_contacts:100,max_unanswered_periods:20,completion_action:'next_candidate',max_run_minutes:480,strategy:true});
  await page.evaluate(()=>dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'automation.state',data:{policy_revision:1,run_revision:1}}}})));
  await page.locator('#strategy-auto[aria-pressed=true]').filter({hasText:'Auto · waiting'}).waitFor();
  assert.equal(await page.locator('#strategy-name').isDisabled(),true,'the strategy is locked while Auto runs');
  assert.match(await page.locator('#station-automation').textContent(),/^Automation waiting · run [0-9a-f]{8} · HALT ends it$/);
  // A second click stops it; a later use asks no more.
  await page.locator('#strategy-auto').click();for(let i=0;i<40&&autos.length<3;i++)await page.waitForTimeout(50);
  assert.deepEqual([autos[2].action,autos[2].run_id],['stop',automation.run.id]);
  assert.equal(commands.some(c=>c.action==='enable_tx'),false,'the browser never arms for Auto; the station run does');
  assert.deepEqual(errors,[]);
});
// Proves: CL-039-01; TC-039-006 the continent is a station setting now.
test('TC-039-006 Settings > General continent saves to the station strategy store',{timeout:40000},async t=>{
  const {page,errors}=await fixture(t,{width:1366,height:768});
  await page.waitForFunction(()=>document.querySelector('#strategy-edit')?.disabled===false,null,{timeout:25000});
  await page.locator('#open-server-settings').click();await page.locator('#tab-general').click();
  assert.equal(await page.locator('#continent-derived').textContent(),'From locator: EU');
  const saved=page.waitForResponse(r=>r.url().endsWith('/strategy')&&r.request().method()==='PUT');
  await page.selectOption('#station-continent','AS');const reply=await (await saved).json();
  assert.deepEqual([reply.revision,reply.configuration.continent,reply.my_continent],[1,'AS','AS']);
  await page.locator('#continent-derived').filter({hasText:'using AS'}).waitFor();
  assert.equal(await page.evaluate(()=>Object.keys(localStorage).some(k=>k.startsWith('wstx.continent'))),false,'not browser-local any more');
  assert.deepEqual(errors,[]);
});

// #51 PageUpdate: the station is restarted on the same profile and its station.status carries
// another client build (a WebSocket proxy stands for the updated station, whose real build is
// this candidate's). Restart, boot id and every other message are real.
async function updatedStation(page,app,dir,t){
  const state={build:null,rewritten:0,navigations:0};
  page.on('framenavigated',frame=>{if(frame===page.mainFrame()){state.navigations++;state.build=null;}});
  await page.routeWebSocket(/\/ws$/,ws=>{
    const station=ws.connectToServer();
    station.onMessage(text=>{const m=JSON.parse(text);if(state.build&&m.type==='station.status'){m.data.build=state.build;state.rewritten++;}ws.send(JSON.stringify(m));});
  });
  // The route serves sockets opened from now on: reconnect once so the proxy carries the link.
  await page.evaluate(()=>socket.close());await page.locator('#connection[data-state=connected]').waitFor();
  return {state,async restart(build){
    const before=await page.evaluate(()=>profileData.boot_id);
    await app.close();state.build=build;state.navigations=0;
    const next=await server({},['--profile',dir]);t.after(()=>next.close());
    return {before,next};
  }};
}
// Proves: CL-051-01, CL-051-02; TC-051-001 an open page reloads itself once after a station update and receives again.
test('TC-051-001 an open page reloads after the station restarts with another client build and receives again',{timeout:60000},async t=>{
  const {page,app,errors,dir}=await fixture(t,{width:1366,height:768});
  await page.evaluate(()=>{localStorage.setItem('wstx.theme.v1',JSON.stringify({theme:'day',mode:'manual',day:'07:00',night:'20:00'}));localStorage.setItem('wstx.waterfall-speed.v1','4');});
  const served=await page.evaluate(()=>document.body.dataset.build);assert.match(served,/^[0-9a-f]{16}$/);
  const {state,restart}=await updatedStation(page,app,dir,t);
  assert.equal(state.navigations,0,'the same build never reloads');
  const {before}=await restart('0123456789abcdef');
  await page.waitForFunction(()=>connection.dataset.state==='connected'&&profileData&&live!==undefined,null,{timeout:30000});
  assert.equal(state.navigations,1,'exactly one reload');assert.equal(state.rewritten,1,'one status of the updated station');
  const after=await page.evaluate(()=>({build:document.body.dataset.build,boot:profileData.boot_id,live:live?.boot_id,theme:document.documentElement.dataset.theme,speed:localStorage.getItem('wstx.waterfall-speed.v1'),reloaded:sessionStorage.getItem('wstx.reloaded-build.v1'),notice:document.querySelector('#station-notice').hidden}));
  assert.notEqual(after.boot,before,'a restarted station');
  assert.deepEqual(after,{build:served,boot:after.boot,live:after.boot,theme:'day',speed:'4',reloaded:'0123456789abcdef',notice:true},'reloaded page receives the new station and keeps its browser settings');
  // A second status for the same reloaded build does not loop: it shows the chip instead.
  state.build='0123456789abcdef';state.navigations=0;await page.evaluate(()=>socket.close());
  await page.locator('#station-notice:not([hidden])').filter({hasText:'Station updated · reload'}).waitFor();
  assert.equal(state.navigations,0,'no second reload for the same build');
  assert.deepEqual(errors,[]);
});
// Proves: CL-051-02, CL-051-03; TC-051-002 an update held by a QSO, a rejected snapshot and the reload chip.
test('TC-051-002 mid-QSO the update shows a reload chip; a rejected snapshot shows an error chip instead of a frozen screen',{timeout:60000},async t=>{
  let contact=partner('calling'),reject=false,receiving;const bad={selection:false,results:false};
  const {page,app,errors,dir}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{contact})}));
    // A live FT8 job (no audio is opened) so result pages and waterfall frames apply.
    await p.route('**/receive',async route=>{const json=await (await route.fetch()).json();if(!receiving||receiving.boot_id!==json.boot_id)receiving=liveFixture(json);await route.fulfill({json:reject?{...receiving,dxcc:null}:receiving});});
    await p.route('**/receive/results?*',route=>route.fulfill({json:bad.results?{...emptyResults(receiving),dxcc:null}:emptyResults(receiving)}));
    await p.route('**/receive/selection',async route=>{const json=await (await route.fetch()).json();await route.fulfill({json:bad.selection?{...json,dxcc:null}:json});});
  }});
  await page.waitForFunction(()=>live?.job?.mode==='ft8'&&live.source);
  await page.waitForFunction(()=>window.wstxContact?.snapshot()?.contact?.state==='calling');
  // A receive snapshot of an unknown shape: visible error chip with the reload action.
  reject=true;await page.evaluate(()=>receiveSync());
  const notice=page.locator('#station-notice:not([hidden])');
  await notice.filter({hasText:'Station data not understood (receive) · reload'}).waitFor();
  assert.equal(await notice.getAttribute('data-severity'),'error');assert.equal(await notice.locator('xpath=..').getAttribute('id'),'station-bar');
  reject=false;await page.evaluate(()=>receiveSync());await page.locator('#station-notice[hidden]').waitFor({state:'attached'});
  // A result page and an operating selection snapshot of an unknown shape are named the same way.
  for(const [kind,read] of [['selection','operatingSync(true)'],['results','(lastResultStart=-Infinity,receiveResults())']]){
    bad[kind]=true;await page.evaluate(read);await notice.filter({hasText:`(${kind})`}).waitFor();
    bad[kind]=false;await page.evaluate(read);await page.locator('#station-notice[hidden]').waitFor({state:'attached'});
  }
  // A waterfall frame of an unknown shape for the current job.
  await page.evaluate(()=>{const ctx={boot_id:live.boot_id,generation:live.generation,job_id:live.job.id,source_id:live.source.id};
    dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:profileSelect.value==='detail'?'spectrum.detail.frame':'spectrum.frame',data:{...ctx,sequence:0,first_frame:0,end_frame:1,dxcc:null}}}}));});
  await notice.filter({hasText:'(waterfall)'}).waitFor();
  await page.evaluate(()=>stationData('waterfall',true));
  // A malformed contact snapshot (an unknown key) is named too and clears with a valid one.
  await page.route('**/contact',route=>route.fulfill({json:{...contactSnapshot({profile_id:'x',boot_id:'y'}),extra:1}}));
  await page.evaluate(()=>window.wstxContact.load());await notice.filter({hasText:'(contact)'}).waitFor();
  const base=await page.evaluate(()=>({profile_id:profileData.profile_id,boot_id:profileData.boot_id}));
  await page.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{contact})}));
  await page.evaluate(()=>window.wstxContact.load());await page.locator('#station-notice[hidden]').waitFor({state:'attached'});
  // The station is updated while calling CQ: no reload, the chip; its click reloads.
  const {state,restart}=await updatedStation(page,app,dir,t);
  await restart('fedcba9876543210');
  await notice.filter({hasText:'Station updated · reload'}).waitFor({timeout:30000});
  await page.waitForTimeout(1500);assert.equal(state.navigations,0,'a QSO in progress holds the reload');
  assert.equal(await notice.getAttribute('data-severity'),'warn');
  contact=null;await notice.click();
  await page.waitForFunction(()=>connection.dataset.state==='connected'&&live!==undefined,null,{timeout:30000});
  assert.equal(state.navigations,1,'the chip reloads the page');
  assert.equal(await page.locator('#station-notice').isHidden(),true);
  // An open dialog also holds the reload.
  await page.waitForFunction(()=>typeof window.wstxConfirm==='function');
  await page.evaluate(()=>{window.wstxConfirm('Test dialog');});
  state.build='0011223344556677';state.navigations=0;await page.evaluate(()=>socket.close());
  await notice.filter({hasText:'Station updated'}).waitFor({timeout:20000});assert.equal(state.navigations,0,'an open dialog holds the reload');
  assert.deepEqual(errors,[]);
});
