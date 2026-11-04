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
async function fixture(t,viewport,{inputDevice=null,beforeNavigate,deviceScaleFactor=1}={}){
  const port=await browserPort();
  const dir=await fs.mkdtemp(path.join(root,'station-'));
  const doc={schema_version:1,profile_id:crypto.randomUUID(),revision:0,display_name:'HB9BLA <station>',callsign:'HB9BLA',locator:'JN47AA',endpoint:{bind:`127.0.0.1:${port}`,origin:null},connection_type:'standard',audio:{input_device:inputDevice,output_device:null},control:{mode:'disabled',endpoint:null,ptt:'disabled'}};
  await fs.writeFile(path.join(dir,'profile.json'),JSON.stringify(doc));
  const app=await server({},['--profile',dir]),context=await browser.newContext({viewport,deviceScaleFactor}),page=await context.newPage();
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
  await page.waitForFunction(()=>typeof live!=='undefined'&&live?.source&&snapshot&&snapshot.job===null);
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
  for(const name of ['CQ','Tune','HALT','Log QSO'])assert.equal(await page.getByRole('button',{name,exact:true}).isDisabled(),true,name);
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
  for(const name of ['CQ','HALT','Log QSO'])assert.equal(await page.getByRole('button',{name,exact:true}).isDisabled(),true);
  assert.ok(sent.some(m=>m.type==='station.get'),'recorder observes actual allowed station traffic');
  assert.equal(sent.some(m=>/transmit|qso|log|radio\./.test(m.type)),false);assert.deepEqual(errors,[]);
});


// Proves: CL-010-05, CL-010-07, CL-010-08, CL-010-16, CL-050-01; TC-007-002, TC-050-001 agreed design and authority-preserving regions.
test('TC-007-002 agreed workspace has the top bar, waterfall with Rx/Tx strip, Band Activity and the QSO pane with truthful state',{timeout:30000},async t=>{
 const {page,errors,sent}=await fixture(t,{width:1200,height:1200});
 assert.equal(Math.round((await page.locator('#signal').boundingBox()).height),330,'#54: a sufficiently tall desktop starts with the taller signal height (about 2 FT8 periods at 10 px/s)');
 await page.setViewportSize({width:1200,height:800});
 const shortSignal=await page.locator('#signal').evaluate(signal=>({height:signal.getBoundingClientRect().height,minimum:Number(document.querySelector('#splitter').getAttribute('aria-valuemin')),maximum:Number(document.querySelector('#splitter').getAttribute('aria-valuemax')),current:Number(document.querySelector('#splitter').getAttribute('aria-valuenow'))}));
 assert.ok(shortSignal.height>=160,'short viewport preserves the signal minimum');
 assert.ok(shortSignal.current>=shortSignal.minimum&&shortSignal.current<=shortSignal.maximum,'short viewport respects the accessible splitter bounds');
 assert.equal(Math.round(shortSignal.height),shortSignal.current,'accessible splitter value matches the displayed signal height');
 assert.equal(await page.getByRole('separator').getAttribute('tabindex'),'0','short viewport retains keyboard resizing');
 // The strategy element and the chips come with the contact client (loaded after the first snapshots).
 await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
 assert.match(await page.locator('#help-keys').textContent(),/Waterfall click \/ double-click\s*Set Tx \/ Rx and Tx/,'#50 help names the pointer mapping');
 assert.doesNotMatch(await page.locator('#help-keys').textContent(),/Shift\+click|Ctrl\+click/);
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
 // WstxContact::OperatorDisplays (D11): server UTC in the top bar. #50: one period bar only, the QSO pane's NEXT bar.
 await page.locator('#radio-toolbar .op-period > span').filter({hasText:/^UTC \d\d:\d\d:\d\d$/}).waitFor();
 assert.deepEqual(await page.locator('#radio-toolbar .op-period').evaluate(p=>[p.children.length,!!p.querySelector('.op-period-track,small')]),[1,false],'no period bar in the top bar');
 assert.equal(await page.locator('#rx-focus .op-qso-progress #qso-progress').count(),1,'the period bar stays in the QSO pane');
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
const operateItems=['#operating-band','#operating-mode','#op-dial','#radio-toolbar .op-period','#open-logbook','#open-server-settings','#qso-halt','#waterfall','#contact-rx','#contact-tx','#contact-hold','#strip-tx-from-rx','#strip-rx-from-tx','#strategy-element','#band-activity','#rx-focus','#display-sensitivity','#display-speed','#qso-cq','#contact-tune','#qso-halt','#contact-log'];
const drawerItems={general:['#display-name','#callsign','#locator','#station-continent','#clock-setting','#theme-choice','#theme-switch','#display-profile','#settings-browsers','#settings-automation','#settings-startup'],radio:['#detect-run','#control-mode','#control-endpoint','#ptt-mode','#cat-status','#audio-input','#audio-output','#audio-enumerate','#settings-audio .op-input-meter','#watchdog-tx','#watchdog-tune','#settings-save'],logging:['#settings-log','#settings-udp','#udp-warning','#udp-save','#settings-pskreporter'],expert:['#signal-status','#receive-status','#receive-generation','#operating-selection-status','#operating-radio','#operating-refresh','#clock-detail','#receive-toggle','#version','#operating-capabilities','#recording-file','#recording-import','#recording-replay','#startup-resume']};
const healthyTexts=['#cat-status','#receive-status','#signal-status','#operating-radio','#operating-selection-status','#clock-detail'];
async function inViewport(page,selector){return page.locator(selector).first().evaluate(el=>{const r=el.getBoundingClientRect();return el.checkVisibility({visibilityProperty:true})&&r.width>1&&r.height>1&&r.bottom>0&&r.right>0&&r.top<innerHeight&&r.left<innerWidth;});}
// checkVisibility also treats the content of a closed <details> fold-out as not shown.
async function shown(page,selector){return page.locator(selector).first().evaluate(el=>el.checkVisibility({visibilityProperty:true}));}
function contactSnapshot(base,{contact=null,transmit={},settings={},log=null}={}){
  return {v:1,profile_id:base.profile_id,boot_id:base.boot_id,contact_revision:base.revision??3,snapshot_sequence:base.sequence??3,monotonic_ms:1000,utc_ms:Date.now(),log,
    transmit:{capability:'available',arm_state:'disarmed',last_disarm_cause:'startup',tune:false,pending_sequence:null,last_text:null,last_period_utc:null,halt_state:'idle',safety_revision:7,refusal:null,...transmit},
    settings:{auto_seq:true,tx1_skip:false,tx_calls:6,tune_seconds:90,rx_hz:1500,tx_hz:1500,hold_tx:false,parity:'even',report:-10,...settings},
    contact,watchdog:{tx_remaining_calls:6,tx_expired:false,tune_remaining_seconds:0}};
}
const partner=(state='replying',extra={})=>({id:crypto.randomUUID(),origin:'selected_row',dx_call:'K1ABC',dx_grid:'FN42',report_sent:'-12',report_rcvd:null,state,next_slot:'tx1',tx4:'rrr',messages:['K1ABC HB9BLA JN47','K1ABC HB9BLA -12','K1ABC HB9BLA R-12','K1ABC HB9BLA RRR','K1ABC HB9BLA 73','CQ HB9BLA JN47'],start_utc:null,end_utc:null,saved:false,...extra});
// Records a page's contact commands and answers them like the station (202) without effects.
async function contactCommands(page,commands){await page.route('**/contact/command',async route=>{commands.push(JSON.parse(route.request().postData()));await route.fulfill({status:202,json:{v:1,accepted:true}});});}

// Proves: CL-011-03; TC-007-008 (#11 live stall 2026-11-02, IW9FRA): with Auto Seq off the
// QSO pane says so, and the partner's RR73 in roger_report offers 73 as one action.
test('TC-007-008 Auto Seq off is shown on the QSO pane and an RR73 offers 73 next',{timeout:40000},async t=>{
  const commands=[];let contact=null,settings={auto_seq:false};
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{contact,settings})}));
    await contactCommands(p,commands);
  }});
  await page.waitForFunction(()=>!!window.wstxContact?.snapshot(),null,{timeout:25000});
  const iw9fra=['IW9FRA HB9BLA JN37','IW9FRA HB9BLA +10','IW9FRA HB9BLA R+10','IW9FRA HB9BLA RR73','IW9FRA HB9BLA 73','CQ HB9BLA JN37'];
  const show=async next=>{contact=next;await page.evaluate(()=>window.wstxContact.load());await page.waitForFunction(s=>window.wstxContact.snapshot().contact?.suggested_slot===s,next.suggested_slot);};
  await show(partner('roger_report',{dx_call:'IW9FRA',dx_grid:'JM68',report_sent:'+10',report_rcvd:'+10',next_slot:'tx3',tx4:'rr73',messages:iw9fra,suggested_slot:null}));
  assert.equal(await shown(page,'#qso-autoseq'),true,'Auto Seq off is on the pane');
  assert.match(await page.locator('#qso-autoseq-text').textContent(),/^Auto Seq off/);
  assert.equal(await shown(page,'#qso-suggest'),false,'nothing offered before their RR73');
  // Their RR73 was counted: the engine offers Tx5; one click chooses it and arms (Reply).
  await show({...contact,suggested_slot:'tx5'});
  assert.equal(await page.locator('#qso-suggest').textContent(),'Send 73 next');
  assert.equal(await page.locator('#qso-suggest').getAttribute('title'),'Send IW9FRA HB9BLA 73 next');
  assert.match(await page.locator('#qso-autoseq-text').textContent(),/IW9FRA expects$/);
  assert.equal(await page.locator('#qso-autoseq').evaluate(el=>getComputedStyle(el).borderLeftStyle),'solid','styled as a warning on the pane');
  // TC-007-009: still one fixed 1366x768 screen with the line shown.
  const metrics=await page.evaluate(()=>({x:document.documentElement.scrollWidth>innerWidth,y:document.documentElement.scrollHeight>innerHeight}));
  assert.deepEqual(metrics,{x:false,y:false});
  const clipped=selector=>page.locator(selector).first().evaluate(el=>{const r=el.getBoundingClientRect();for(let p=el.parentElement;p;p=p.parentElement){if(/auto|scroll|hidden/.test(getComputedStyle(p).overflowY)){const b=p.getBoundingClientRect();if(r.top<b.top-1||r.bottom>b.bottom+1)return true;}}return r.bottom>innerHeight;});
  // #37 compact pane: the line sits in the pane with the last partner message and the
  // buttons, all fully visible on the 1366x768 screen; there is no dialogue or LAST row.
  assert.equal(await page.locator('#rx-pane,#contact-last').count(),0);
  await page.screenshot({path:'test-results/ui-operating/autoseq-off-1366x768.png'});
  for(const selector of ['#qso-autoseq','#qso-suggest','#qso-halt','#contact-log'])assert.equal(await clipped(selector),false,`${selector} fully visible on the 1366x768 screen`);
  settings={auto_seq:true};await show({...contact,suggested_slot:null});await page.waitForFunction(()=>document.querySelector('#qso-autoseq').hidden);
  settings={auto_seq:false};await show({...contact,suggested_slot:'tx5'});await page.waitForFunction(()=>!document.querySelector('#qso-autoseq').hidden);
  await page.setViewportSize({width:360,height:800});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'no horizontal overflow at 360 px');
  await page.screenshot({path:'test-results/ui-operating/autoseq-off-360x800.png',fullPage:true});
  await page.setViewportSize({width:1366,height:768});
  await page.locator('#qso-suggest').click();
  for(let i=0;i<40&&commands.length<2;i++)await page.waitForTimeout(50);
  assert.deepEqual(commands.map(c=>[c.action,c.slot??c.enabled]),[['choose_next','tx5'],['enable_tx',true]]);
  await page.locator('#qso-autoseq-on').click();
  for(let i=0;i<40&&commands.length<3;i++)await page.waitForTimeout(50);
  assert.deepEqual([commands[2].action,commands[2].enabled],['set_auto_seq',true]);
  // Auto Seq on and nothing offered: the line is gone.
  settings={auto_seq:true};await show({...contact,suggested_slot:null});
  await page.waitForFunction(()=>document.querySelector('#qso-autoseq').hidden);
  assert.doesNotMatch(await page.locator('#contact-state').textContent(),/Auto Seq off/);
  assert.deepEqual(errors,[]);
});

// Proves: CL-010-16, CL-010-06; TC-007-009 the compact QSO pane (#37, operator decisions
// 2026-11-02, items 1-10): the running QSO only, NEXT only while armed, "✓ Logged <call>"
// for a few seconds, nothing of a finished contact, about half the height.
// Proves: CL-050-05, CL-050-06; TC-050-005, TC-050-006 (c) (#37, operator 2026-11-02): the
// Others are only stations calling my call, with time and SNR (⚠ during a QSO within
// ±50 Hz of my Rx or Tx offset, every caller otherwise), below the QSO dialogue.
test('TC-007-009 the compact QSO pane shows only the running QSO and clears when it ends',{timeout:60000},async t=>{
  let state,contact=null,transmit={},log=null,settings={},records=[];const commands=[],period='2026-10-27T12:00:15.0000000Z';
  const standard=(from,to)=>({type:'standard',to:{kind:to==='CQ'?'token':'call',text:to,hash_bits:null,hash_value:null},from:{kind:'call',text:from,hash_bits:null,hash_value:null},ack:false,exchange:{kind:'grid',value:'FN42'}});
  const record=(sequence,text,hz,snr)=>{const [to,from]=text.split(' ');return {sequence,start_frame:6000,frequency_hz:hz,snr_db:snr,dt_seconds:0.1,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text,fields:standard(from,to),period_start_utc:period};};
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    state=liveFixture(await (await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    // Rx and Tx are 1500 Hz. CQs (even near Rx) are never QSO pane lines; DL1ABC calls me at
    // 400 Hz (a candidate idle, not near my frequency during a QSO); SV1DZB calls me at 1530 Hz;
    // the partner IW9FRA is never an Other.
    // During the QSO Tx is 2100 Hz: EA8BIA at 2130 Hz is near my Tx, F1PBZ at 1600 Hz near neither.
    records=[record(0,'CQ K1ABC FN42',1449.9,-3),record(1,'CQ W1XYZ FN42',1480,-10),record(2,'HB9BLA DL1ABC JO31',400,-8),record(3,'CQ YO3GNF KN34',1530,12.4),record(4,'HB9BLA IW9FRA RR73',1505,17),record(5,'HB9BLA SV1DZB KM18',1530,-8),
      record(6,'HB9BLA EA8BIA IL18',2130,0),record(7,'HB9BLA F1PBZ JN18',1600,-10)];
    Object.assign(state.job,{first_sequence:0,next_sequence:8,available_count:8,latest_decode:{id:1,first_sequence:0,next_sequence:8,period_start_utc:period,complete:true}});
    await p.route('**/receive',async route=>{await p.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await p.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor')),batch=records.slice(cursor),next=cursor+batch.length;await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:records.length,available_count:records.length,next,more:false,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{contact,transmit,log,settings})}));
    await contactCommands(p,commands);
  }});
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===8&&window.wstxContact?.snapshot(),null,{timeout:25000});
  const others=()=>page.locator('#qso-others tr').evaluateAll(rows=>rows.map(tr=>[tr.dataset.kind,[...tr.cells].map(td=>td.textContent)]));
  const show=async(next,tx={},l=null)=>{contact=next;transmit=tx;log=l;await page.evaluate(()=>window.wstxContact.load());};
  const waitCommands=async n=>{for(let i=0;i<60&&commands.length<n;i++)await page.waitForTimeout(50);};
  // Removed: the old dialogue history pane, LAST row and crowding badge.
  for(const selector of ['#rx-pane','#rx-pane-rows','#contact-last','#qso-crowd','#rx-pane-erase'])assert.equal(await page.locator(selector).count(),0,`${selector} is gone`);

  // Idle: every station calling my call, on any frequency, oldest first, with its period
  // start and SNR (no DT or Hz); no CQ, even near Rx.
  await page.waitForFunction(()=>document.querySelectorAll('#qso-others tr').length===5);
  assert.deepEqual(await others(),[['candidate',['12:00:15','HB9BLA ◂ DL1ABC','JO31','','−8','']],['candidate',['12:00:15','HB9BLA ◂ IW9FRA','RR73','','+17','']],['candidate',['12:00:15','HB9BLA ◂ SV1DZB','KM18','','−8','']],
    ['candidate',['12:00:15','HB9BLA ◂ EA8BIA','IL18','','0','']],['candidate',['12:00:15','HB9BLA ◂ F1PBZ','JN18','','−10','']]]);
  assert.equal(await shown(page,'#qso-others-none'),false,'no "nobody calling" with callers');
  assert.equal(await page.locator('#rx-focus .op-contact-identity strong').textContent(),'No contact selected');
  for(const selector of ['#qso-heard','#qso-next','#contact-state'])assert.equal(await shown(page,selector),false,`${selector} not shown idle`);
  assert.equal(await page.locator('#contact-log').isDisabled(),true,'no Log QSO without a running QSO');
  // Double-click answers: select (no replace), then enable_tx.
  let m=commands.length;await page.locator('#qso-others tr').nth(1).dblclick();await waitCommands(m+2);
  assert.deepEqual(commands.slice(m).map(c=>[c.action,c.row?.sequence??c.enabled,c.replace]),[['select_row',4,false],['enable_tx',true,undefined]]);

  // Items 1-4 and 10, a running QSO with Enable Tx on: header, the last partner message with
  // SNR and xN, the Others marked ⚠ (a station near Rx and one calling me, not the partner),
  // NEXT with its countdown.
  const iw9fra=['IW9FRA HB9BLA JN47','IW9FRA HB9BLA +10','IW9FRA HB9BLA R+10','IW9FRA HB9BLA RR73','IW9FRA HB9BLA 73','CQ HB9BLA JN47'];
  // TC-050-006 (c): the server-owned dialogue, ten entries (more than the free height).
  const p0=Date.parse('2026-10-27T11:58:00Z'),entry=(i,dir,text,snr=null,count=1)=>({dir,text,snr,period_utc_ms:p0+i*15000,count});
  const dialogue=[entry(1,'tx','IW9FRA HB9BLA JN47',null,2),entry(2,'rx','HB9BLA IW9FRA -05',-5),entry(3,'tx','IW9FRA HB9BLA R+10'),entry(4,'rx','HB9BLA IW9FRA -05',-6),entry(5,'tx','IW9FRA HB9BLA R+10'),
    entry(6,'rx','HB9BLA IW9FRA RR73',17),entry(7,'tx','IW9FRA HB9BLA 73'),entry(8,'rx','HB9BLA IW9FRA RR73',15),entry(9,'tx','IW9FRA HB9BLA 73'),entry(10,'rx','HB9BLA IW9FRA RR73',17,3)];
  const running=partner('signoff',{dx_call:'IW9FRA',dx_grid:'JM68',report_sent:'+10',report_rcvd:'+10',next_slot:'tx5',tx4:'rr73',messages:iw9fra,suggested_slot:null,last_rcvd:{text:'HB9BLA IW9FRA RR73',snr:17,period_utc_ms:Date.parse(period),count:3},dialogue});
  settings={tx_hz:2100};await show(running,{arm_state:'armed'});
  await page.waitForFunction(()=>!document.querySelector('#qso-heard').hidden&&document.querySelector('#qso-others tr')?.dataset.kind==='warn'&&document.querySelectorAll('#qso-others tr').length===2);
  // Independent great-circle distance between the JN47AA and JM68 square centres (R 6371 km).
  const rad=Math.PI/180,[pa,pb]=[[47+1/48,8+1/24],[38.5,13]],km=Math.round(2*6371*Math.asin(Math.sqrt(Math.sin((pb[0]-pa[0])*rad/2)**2+Math.cos(pa[0]*rad)*Math.cos(pb[0]*rad)*Math.sin((pb[1]-pa[1])*rad/2)**2)));
  assert.equal(await page.locator('#rx-focus .op-contact-identity strong').textContent(),'IW9FRA · JM68');
  // #55: the partner's cty.dat entity (shown name and continent) leads the detail line once
  // GET /dxcc answers; with a grid the distance stays the exact one.
  await page.locator('#rx-focus .op-contact-identity div > span').filter({hasText:'Italy'}).waitFor();
  assert.equal(await page.locator('#rx-focus .op-contact-identity div > span').textContent(),`Italy (EU) · ${km} km · sent +10 · rcvd +10`);
  assert.equal(await page.locator('#qso-heard').textContent(),'◂ HB9BLA IW9FRA RR73  +17 dB ×3');
  assert.deepEqual(await others(),[['warn',['12:00:15 ⚠','HB9BLA ◂ SV1DZB','KM18','','−8','']],['warn',['12:00:15 ⚠','HB9BLA ◂ EA8BIA','IL18','','0','']]],'only callers within ±50 Hz of my Rx (1500) or Tx (2100), not the partner');
  const lines=await page.locator('#qso-dialogue tr').evaluateAll(rows=>rows.map(tr=>[...tr.cells].map(td=>td.textContent)));
  // #60 (operator 2026-11-03): Rep in its own column; Rx/Tx SNR the latest received values on every row.
  assert.deepEqual([lines.length,lines[0],lines[1],lines[2],lines.at(-1)],[10,['11:58:15','IW9FRA ◂ HB9BLA','JN47','×2','',''],['11:58:30','HB9BLA ◂ IW9FRA','-05','','−5','−5'],['11:58:45','IW9FRA ◂ HB9BLA','R+10','','−5','−5'],['12:00:30','HB9BLA ◂ IW9FRA','RR73','×3','+17','−5']]);
  // The QSO area scrolls inside the card, kept at its newest line, and grows nothing.
  const area=await page.locator('#qso-area').evaluate(a=>({scrolls:a.scrollHeight>a.clientHeight,bottom:Math.abs(a.scrollTop+a.clientHeight-a.scrollHeight)<=2,overflow:getComputedStyle(a).overflowY}));
  assert.equal(area.overflow,'auto');assert.equal(area.bottom,true,`kept at the newest line ${JSON.stringify(area)}`);
  assert.equal(await shown(page,'#qso-next'),true,'NEXT while armed');
  assert.deepEqual([await page.locator('#qso-next .op-eyebrow').textContent(),await page.locator('#contact-next').textContent()],['▸ next:','IW9FRA HB9BLA 73']);
  assert.equal(await shown(page,'#contact-state'),false,'no status line without an exception');
  assert.equal(await page.locator('#contact-log').isEnabled(),true);
  // Item 8: one fixed 1366x768 screen; the pane fits its content (nothing clipped) and
  // takes about half the workspace height the earlier pane filled.
  const metrics=await page.evaluate(()=>({x:document.documentElement.scrollWidth>innerWidth,y:document.documentElement.scrollHeight>innerHeight}));
  assert.deepEqual(metrics,{x:false,y:false});
  const clipped=selector=>page.locator(selector).first().evaluate(el=>{const r=el.getBoundingClientRect();for(let p=el.parentElement;p;p=p.parentElement){if(/auto|scroll|hidden/.test(getComputedStyle(p).overflowY)){const b=p.getBoundingClientRect();if(r.top<b.top-1||r.bottom>b.bottom+1)return true;}}return r.bottom>innerHeight;});
  for(const selector of ['#qso-heard','#qso-others tr:last-child','#qso-next','#qso-cq','#contact-log'])assert.equal(await clipped(selector),false,`${selector} fully visible`);
  await page.screenshot({path:'test-results/ui-operating/qso-dialogue-1366x768.png'});
  // Content height: the header plus the lines, the QSO area, buttons and fold-out of the pane body.
  const heights=await page.evaluate(()=>{const box=s=>document.querySelector(s).getBoundingClientRect(),body=document.querySelector('#rx-focus .op-contact-body'),cs=getComputedStyle(body);
    const kids=[...body.children].filter(e=>e.getClientRects().length&&getComputedStyle(e).display!=='none'),sum=list=>list.reduce((h,e)=>h+e.getBoundingClientRect().height,0);
    const gaps=parseFloat(cs.rowGap||cs.gap||0)*(kids.length-1)+parseFloat(cs.paddingTop)+parseFloat(cs.paddingBottom);
    const head=box('#rx-focus .op-qso-head').height,row=box('#qso-dialogue tr').height;
    return {content:head+sum(kids)+gaps,withoutArea:head+sum(kids.filter(e=>e.id!=='qso-area'))+gaps-parseFloat(cs.rowGap||cs.gap||0),
      area:box('#qso-area').height,row,pane:box('#rx-focus'),activity:box('#band-activity')};});
  await page.screenshot({path:'test-results/ui-operating/qso-pane-compact-1366x768.png'});
  // The earlier pane needed about 380 px for this contact without the dialogue (at ad2f48bda it
  // filled the 297 px workspace and still clipped the buttons, the result line and the fold-out).
  assert.ok(heights.withoutArea<=250,`compact pane content ${heights.withoutArea} px without the QSO area`);
  // Item 8 (#60, operator 2026-11-03, replacing option C): the pane is its content high at the
  // top of its column, at 1366x768 at most 300 px; the QSO area shows the header row and at
  // most 6 rows (12 entries here, scrolling inside).
  assert.ok(heights.area<=7*heights.row+3,`QSO area ${heights.area} px for rows of ${heights.row} px`);
  assert.ok(Math.abs(heights.pane.height-heights.content)<=3,`pane ${heights.pane.height} px, content ${heights.content} px`);
  assert.ok(heights.pane.height<=300,`pane ${heights.pane.height} px at 1366x768`);
  assert.ok(Math.abs(heights.pane.top-heights.activity.top)<=1,'top of its column');
  // A taller screen: the area is header plus 6 rows, the pane stays content high and the
  // height below it is free (future panels), no longer filled by the card.
  await page.setViewportSize({width:1920,height:1080});
  const tall=await page.evaluate(()=>{const box=s=>document.querySelector(s).getBoundingClientRect();return {area:box('#qso-area').height,row:box('#qso-dialogue tr').height,pane:box('#rx-focus'),activity:box('#band-activity')};});
  assert.ok(Math.abs(tall.area-(7*tall.row+2))<=3,`QSO area ${tall.area} px is the header and 6 rows of ${tall.row} px`);
  assert.ok(tall.pane.height<=340&&tall.activity.bottom-tall.pane.bottom>=100,`pane ${tall.pane.top}-${tall.pane.bottom}, Band Activity ${tall.activity.top}-${tall.activity.bottom}: free height below`);
  await page.screenshot({path:'test-results/ui-operating/qso-pane-compact-1920x1080.png'});
  await page.setViewportSize({width:1366,height:768});
  // Item 3: double-click on a ⚠ line switches the contact to that station and replies.
  m=commands.length;await page.locator('#qso-others tr').first().dblclick();await waitCommands(m+2);
  assert.deepEqual(commands.slice(m).map(c=>[c.action,c.row?.sequence??c.enabled,c.replace]),[['select_row',5,true],['enable_tx',true,undefined]]);
  // Nobody else near my frequencies: one muted line says so.
  settings={rx_hz:2800,tx_hz:2800};await show(running,{arm_state:'armed'});
  await page.locator('#qso-others-none').filter({hasText:'nobody else calling'}).waitFor();
  assert.deepEqual(await others(),[]);
  settings={tx_hz:2100};await show(running,{arm_state:'armed'});await page.waitForFunction(()=>document.querySelectorAll('#qso-others tr').length===2);
  // Not armed: no NEXT.
  await show(running,{arm_state:'disarmed'});await page.waitForFunction(()=>document.querySelector('#qso-next').hidden);
  // Auto Seq off (#11) stays visible in the compact pane.
  await page.setViewportSize({width:360,height:800});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'no horizontal overflow at 360 px');
  await page.locator('#rx-focus').scrollIntoViewIfNeeded();
  await page.screenshot({path:'test-results/ui-operating/qso-pane-compact-360x800.png'});
  await page.setViewportSize({width:1366,height:768});

  // Items 5, 6 and 9: Log QSO completes the contact; it is gone: "✓ Logged IW9FRA", no
  // NEXT, no partner lines (the finished partner's RR73 is not offered again), Others back to
  // plain candidates; the notice goes after a few seconds. The station's completed snapshot is
  // loaded before the 202 arrives: no "accepted" result of the ended QSO stays.
  const done={...running,state:'completed',next_slot:'tx6',saved:true};
  const logged={contact_id:running.id,call:'IW9FRA',outcome:'saved',error:null};
  const early=async route=>{commands.push(JSON.parse(route.request().postData()));contact=done;transmit={arm_state:'disarmed'};log=logged;await page.evaluate(()=>window.wstxContact.load());await new Promise(r=>setTimeout(r,300));await route.fulfill({status:202,json:{v:1,accepted:true}});};
  await page.route('**/contact/command',early);
  m=commands.length;await page.locator('#contact-log').click();await waitCommands(m+1);
  assert.deepEqual(commands.slice(m).map(c=>c.action),['open_log']);
  await page.locator('#contact-logged').filter({hasText:'✓ Logged IW9FRA'}).waitFor();
  await page.waitForTimeout(800);await page.unroute('**/contact/command',early);
  assert.equal(await page.locator('#contact-result').textContent(),'','no accepted result of the ended QSO');
  assert.equal(await page.locator('#contact-logged').textContent(),'✓ Logged IW9FRA');
  assert.equal(await page.locator('#rx-focus .op-contact-identity strong').textContent(),'No contact selected');
  for(const selector of ['#qso-heard','#qso-next','#contact-state'])assert.equal(await shown(page,selector),false,`${selector} gone after completion`);
  assert.deepEqual(await others(),[['candidate',['12:00:15','HB9BLA ◂ DL1ABC','JO31','','−8','']],['candidate',['12:00:15','HB9BLA ◂ SV1DZB','KM18','','−8','']],['candidate',['12:00:15','HB9BLA ◂ EA8BIA','IL18','','0','']],['candidate',['12:00:15','HB9BLA ◂ F1PBZ','JN18','','−10','']]],'the finished partner is not a candidate');
  assert.equal(await shown(page,'#qso-dialogue'),false,'the dialogue goes with the QSO');
  assert.equal(await page.locator('#contact-log').isDisabled(),true,'a finished contact is not offered for Log QSO');
  m=commands.length;await page.locator('body').click({position:{x:5,y:5}});await page.keyboard.press('Alt+q');await page.waitForTimeout(400);
  assert.deepEqual(commands.slice(m),[],'nor by Alt+Q');
  await page.screenshot({path:'test-results/ui-operating/qso-pane-logged-1366x768.png'});
  await page.waitForFunction(()=>document.querySelector('#contact-logged').textContent==='',null,{timeout:12000});
  assert.equal(await shown(page,'#contact-logged'),false,'the notice goes');
  // A cancelled contact is gone at once, without a notice.
  await show(running,{arm_state:'armed'});await page.waitForFunction(()=>!document.querySelector('#qso-heard').hidden);
  await show({...running,state:'cancelled',dx_call:null,dx_grid:null},{arm_state:'disarmed'},{contact_id:running.id,call:'IW9FRA',outcome:'saved',error:null});
  await page.waitForFunction(()=>document.querySelector('#qso-heard').hidden&&document.querySelector('#qso-next').hidden);
  assert.equal(await page.locator('#rx-focus .op-contact-identity strong').textContent(),'No contact selected');
  assert.equal(await page.locator('#contact-logged').textContent(),'','an earlier save is not shown again');
  assert.deepEqual(errors,[]);
});

// Proves: CL-060-01; TC-060-001 (#60, operator 2026-11-03): the QSO dialogue and the Others
// are one table, UTC | Direction | Exchange | Rep | Rx SNR | Tx SNR; Direction is the two calls as on
// the air, recipient first, with "◂" pointing to the recipient; a CQ is "CQ <call>" with its
// grid; free text is all Exchange; Rep is ×N; on every dialogue row Rx SNR (ours) and Tx SNR
// (the partner's report on us) are the latest received values at or before it (2026-11-03).
test('TC-060-001 the QSO pane table shows UTC, Direction with the arrow to the recipient, Exchange, Rep, Rx SNR and Tx SNR',{timeout:60000},async t=>{
  let state,contact=null;const period='2026-10-27T12:00:15.0000000Z';
  const call=text=>({kind:text===null?'hash':'call',text,hash_bits:text===null?22:null,hash_value:text===null?12345:null});
  const record=(sequence,text,from,hz,snr)=>({sequence,start_frame:6000,frequency_hz:hz,snr_db:snr,dt_seconds:0.1,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text,
    fields:{type:'standard',to:call('HB9BLA'),from,ack:false,exchange:{kind:'grid',value:'JO31'}},period_start_utc:period});
  // Callers of my call: known calls, an unknown hashed call and a known hashed call.
  const records=[record(0,'HB9BLA DL1ABC JO31',call('DL1ABC'),400,-8),record(1,'HB9BLA <...> RR73',call(null),700,-12),
    record(2,'HB9BLA <PJ4/K1ABC> -05',{kind:'hash',text:'PJ4/K1ABC',hash_bits:22,hash_value:777},900,-5),record(3,'HB9BLA EA8BIA IL18',call('EA8BIA'),1520,0)];
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    state=liveFixture(await (await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    Object.assign(state.job,{first_sequence:0,next_sequence:records.length,available_count:records.length,latest_decode:{id:1,first_sequence:0,next_sequence:records.length,period_start_utc:period,complete:true}});
    await p.route('**/receive',async route=>{await p.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await p.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor')),batch=records.slice(cursor),next=cursor+batch.length;await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:records.length,available_count:records.length,next,more:false,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{contact,transmit:{arm_state:'armed'}})}));
    await contactCommands(p,[]);
  }});
  await page.waitForFunction(()=>document.querySelectorAll('#qso-others tr').length===4&&window.wstxContact?.snapshot(),null,{timeout:25000});
  const cells=selector=>page.locator(selector).evaluateAll(rows=>rows.map(tr=>[...tr.cells].map(td=>td.textContent)));
  assert.deepEqual((await cells('#qso-table thead tr'))[0],['UTC','Direction','Exchange','Rep','Rx SNR','Tx SNR']);
  // Idle: every caller, a hashed call as decoded; a report is the Tx SNR.
  assert.deepEqual(await cells('#qso-others tr'),[['12:00:15','HB9BLA ◂ DL1ABC','JO31','','−8',''],['12:00:15','HB9BLA ◂ <...>','RR73','','−12',''],
    ['12:00:15','HB9BLA ◂ <PJ4/K1ABC>','-05','','−5','−5'],['12:00:15','HB9BLA ◂ EA8BIA','IL18','','0','']]);
  assert.equal(await shown(page,'#qso-dialogue'),false,'no dialogue rows idle');
  // A running QSO with CT1BFP (the operator's #60 example), with my CQ before it, a repeated
  // 73 with my call hashed and unknown, and a free-text message.
  const p0=Date.parse('2026-11-03T22:51:00Z'),entry=(i,dir,text,snr=null,count=1)=>({dir,text,snr,period_utc_ms:p0+i*15000,count});
  const dialogue=[entry(0,'tx','CQ HB9BLA JN37'),entry(1,'rx','HB9BLA CT1BFP IM59',8),entry(2,'tx','CT1BFP HB9BLA +08'),entry(3,'rx','HB9BLA CT1BFP R-02',7),
    entry(4,'tx','CT1BFP HB9BLA RR73'),entry(5,'rx','<...> CT1BFP 73',9,2),entry(6,'tx','TNX 73 GL')];
  contact=partner('signoff',{dx_call:'CT1BFP',dx_grid:'IM59',report_sent:'+08',report_rcvd:'-02',messages:['CT1BFP HB9BLA JN37','CT1BFP HB9BLA +08','CT1BFP HB9BLA R+08','CT1BFP HB9BLA RR73','CT1BFP HB9BLA 73','CQ HB9BLA JN37'],
    suggested_slot:null,last_rcvd:{text:'<...> CT1BFP 73',snr:9,period_utc_ms:p0+75000,count:2},dialogue});
  await page.evaluate(()=>window.wstxContact.load());
  await page.waitForFunction(()=>document.querySelectorAll('#qso-dialogue tr').length===7&&document.querySelector('#qso-others tr')?.dataset.kind==='warn');
  assert.deepEqual(await cells('#qso-dialogue tr'),[['22:51:00','CQ HB9BLA','JN37','','',''],['22:51:15','HB9BLA ◂ CT1BFP','IM59','','+8',''],['22:51:30','CT1BFP ◂ HB9BLA','+08','','+8',''],
    ['22:51:45','HB9BLA ◂ CT1BFP','R-02','','+7','−2'],['22:52:00','CT1BFP ◂ HB9BLA','RR73','','+7','−2'],['22:52:15','<...> ◂ CT1BFP','73','×2','+9','−2'],['22:52:30','','TNX 73 GL','','+9','−2']]);
  // During the QSO the caller near my Rx is a ⚠ row below a thin separator, same columns.
  assert.deepEqual(await cells('#qso-others tr'),[['12:00:15 ⚠','HB9BLA ◂ EA8BIA','IL18','','0','']]);
  assert.equal(await page.locator('#qso-others tr td').first().evaluate(td=>getComputedStyle(td).borderTopWidth),'1px','separator above the callers');
  assert.deepEqual(await page.evaluate(()=>({x:document.documentElement.scrollWidth>innerWidth,y:document.documentElement.scrollHeight>innerHeight})),{x:false,y:false},'one fixed screen at 1366x768');
  // The header row stays visible while the area is kept at its newest row.
  const headerShown=()=>page.evaluate(()=>{const a=document.querySelector('#qso-area').getBoundingClientRect(),h=document.querySelector('#qso-table th').getBoundingClientRect();return h.top>=a.top-1&&h.bottom<=a.bottom+1;});
  assert.equal(await page.locator('#qso-area').evaluate(a=>a.scrollTop>0),true,'the area is scrolled to its newest row');
  assert.equal(await headerShown(),true,'header row visible');
  await page.screenshot({path:'test-results/ui-operating/qso-table-1366x768.png'});
  await page.setViewportSize({width:360,height:800});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'no horizontal overflow at 360 px');
  const fit=await page.locator('#qso-table').evaluate(t=>({table:t.scrollWidth,pane:t.parentElement.clientWidth,cols:[...t.rows[0].cells].map(c=>Math.round(c.getBoundingClientRect().width))}));
  assert.ok(fit.table<=fit.pane+1,`the table fits the pane at 360 px ${JSON.stringify(fit)}`);
  await page.locator('#qso-area').scrollIntoViewIfNeeded();
  await page.screenshot({path:'test-results/ui-operating/qso-table-360x800.png'});
  assert.deepEqual(errors,[]);
});

// The fixture server's own station.tick runs on the browser's clock; these tests simulate a
// station whose clock differs, so only the test's ticks reach the page.
async function testTicksOnly(page){
  await page.evaluate(()=>addEventListener('station-message',e=>{if(e.detail?.message?.type==='station.tick'&&!e.detail.test)e.stopImmediatePropagation();},true));
}
// A station.tick delivered through the page's actual listener, then the QSO pane read in the
// same task (the tick handler redraws synchronously), so no other tick can interleave.
async function tickAndRead(page,offset,transmitting){
  return page.evaluate(([offset,transmitting])=>{
    const utc=Date.now()+offset;
    dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,test:true,message:{v:1,type:'station.tick',data:{profile_id:profileData.profile_id,boot_id:profileData.boot_id,utc_ms:utc,period_ms:15000,transmitting,rx_level_db:null}}}}));
    const bar=document.querySelector('#qso-progress'),cs=getComputedStyle(bar);
    return {utc,width:parseFloat(bar.style.width),colour:cs.backgroundColor,transition:cs.transitionDuration,
      label:document.querySelector('#qso-next .op-eyebrow').textContent,next:document.querySelector('#contact-next').textContent,countdown:document.querySelector('#qso-countdown').textContent};
  },[offset,transmitting]);
}
// An own CQ (contact calling) with Enable Tx on, Tx parity even (my periods: even index).
function ownCq(){return {id:crypto.randomUUID(),origin:'own_cq',dx_call:null,dx_grid:null,report_sent:null,report_rcvd:null,state:'calling',next_slot:'tx6',tx4:'rrr',
  messages:[null,null,null,null,null,'CQ HB9BLA JN47'],start_utc:null,end_utc:null,saved:false,suggested_slot:null,last_rcvd:null,dialogue:[]};}
const GREEN='rgb(48, 208, 80)',RED='rgb(255, 64, 64)';

// Proves: CL-050-03; TC-050-003. #50 (operator 2026-11-02, CT7BRV): the QSO pane's period bar
// runs on the station's clock (station.tick / snapshot utc_ms over the browser's monotonic
// clock), not the browser's wall clock, and is red in my Tx periods and while transmitting,
// green in receive periods.
test('TC-050-003 the period bar follows the station clock and is red in my Tx periods and green otherwise',{timeout:40000},async t=>{
  const clock={offset:0};
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    await p.route('**/contact',route=>route.fulfill({json:{...contactSnapshot(base,{contact:ownCq(),transmit:{arm_state:'armed'},settings:{parity:'even'}}),utc_ms:Date.now()+clock.offset}}));
  }});
  await page.waitForFunction(()=>!!window.wstxContact?.snapshot()&&!document.querySelector('#qso-next').hidden,null,{timeout:25000});
  await testTicksOnly(page);
  // A station clock ahead of the browser, in an even (my Tx) period 30..60 s ahead, half a
  // period out of phase with the browser's clock.
  const now=Date.now(),even=Math.ceil((now+30000)/30000)*30000+((now%15000)+7500)%15000,offset=even-now;
  clock.offset=offset;let r=await tickAndRead(page,offset,false);
  const phase=u=>100*(((u%15000)+15000)%15000)/15000;
  assert.ok(Math.abs(r.width-phase(r.utc))<=4,`width ${r.width} vs station phase ${phase(r.utc)}`);
  assert.ok(Math.abs(r.width-phase(r.utc-offset))>10,'not the browser-clock phase');
  assert.equal(Math.floor(r.utc/15000)%2,0,'an even station period');
  assert.deepEqual([r.colour,r.transition],[RED,'0s'],'my Tx period while Enable Tx is on: red, no animated width');
  await page.screenshot({path:'test-results/ui-operating/period-bar-tx-1366x768.png'});
  // The station 15 s further: an odd (receive) period; a larger offset is taken at once.
  clock.offset=offset+15000;r=await tickAndRead(page,offset+15000,false);
  assert.equal(Math.floor(r.utc/15000)%2,1,'an odd station period');
  assert.ok(Math.abs(r.width-phase(r.utc))<=4,`width ${r.width} vs station phase ${phase(r.utc)}`);
  assert.equal(r.colour,GREEN,'a receive period: green');
  await page.screenshot({path:'test-results/ui-operating/period-bar-rx-1366x768.png'});
  // Keyed in the odd period (e.g. Tune or a late start): red while the station transmits.
  r=await tickAndRead(page,offset+15000,true);
  assert.equal(r.colour,RED,'transmitting: red');
  // A backward step of the station clock (#43 correction, here 1 s) is taken at once.
  clock.offset=offset+14000;r=await tickAndRead(page,offset+14000,false);
  assert.ok(Math.abs(r.width-phase(r.utc))<=4,`after a 1 s step back: width ${r.width} vs station phase ${phase(r.utc)}`);
  clock.offset=offset+15000;r=await tickAndRead(page,offset+15000,false);
  await page.setViewportSize({width:360,height:800});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'no horizontal overflow at 360 px');
  await page.locator('#qso-next').scrollIntoViewIfNeeded();
  r=await tickAndRead(page,offset+15000,true);assert.equal(r.colour,RED);
  await page.screenshot({path:'test-results/ui-operating/period-bar-tx-360x800.png'});
  r=await tickAndRead(page,offset+15000,false);assert.equal(r.colour,GREEN);
  await page.screenshot({path:'test-results/ui-operating/period-bar-rx-360x800.png'});
  assert.deepEqual(errors,[]);
});

// Proves: CL-050-05; TC-050-005. #37 (operator 2026-11-02, a CQ run on 40 m): while my CQ
// runs the header says "Calling CQ" with the Tx period, also after a receive refresh; the
// message line is "▶ TX now" while the station transmits and "▸ next" otherwise; an empty
// Others list says "nobody calling".
test('TC-050-005 calling CQ shows Calling CQ, TX now while keyed and next otherwise, and nobody calling',{timeout:40000},async t=>{
  const clock={offset:0};let transmit={arm_state:'armed'},watchdog=null;
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    await p.route('**/contact',route=>{const s={...contactSnapshot(base,{contact:ownCq(),transmit,settings:{parity:'even'}}),utc_ms:Date.now()+clock.offset};if(watchdog)s.watchdog=watchdog;return route.fulfill({json:s});});
  }});
  await page.waitForFunction(()=>!!window.wstxContact?.snapshot()&&!document.querySelector('#qso-next').hidden,null,{timeout:25000});
  await testTicksOnly(page);
  const header=()=>page.locator('#rx-focus .op-contact-identity').evaluate(h=>[h.querySelector('strong').textContent,h.querySelector('div > span').textContent]);
  // A receive refresh redraws the receive display; the CQ header stays.
  await page.evaluate(()=>dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'receive.state',data:{}}}})));
  await page.waitForTimeout(800);
  assert.deepEqual(await header(),['Calling CQ','Tx even (1st)']);
  assert.equal(await page.locator('#qso-others-none').textContent(),'nobody calling');
  assert.equal(await shown(page,'#qso-others-none'),true);
  const now=Date.now(),even=Math.ceil((now+30000)/30000)*30000+4000,offset=even-now;
  clock.offset=offset;let r=await tickAndRead(page,offset,true);
  assert.deepEqual([r.label,r.next],['▶ TX now:','CQ HB9BLA JN47']);
  assert.match(r.countdown,/^\d+ s left$/);assert.equal(Number(r.countdown.split(' ')[0]),10,'audio 0.5 s + 12.64 s from the period start, 4 s in: 10 s left');
  await page.screenshot({path:'test-results/ui-operating/qso-tx-now-1366x768.png'});
  // The transmit view's text of this period is what is on the air (here not the next one).
  transmit={arm_state:'armed',last_text:'K1ABC HB9BLA -05',last_period_utc:even-4000};
  await page.evaluate(()=>window.wstxContact.load());
  r=await tickAndRead(page,offset,true);
  assert.deepEqual([r.label,r.next],['▶ TX now:','K1ABC HB9BLA -05']);
  // Tune is a tone: "TX now: Tune" with the Tune time left, never a message.
  transmit={arm_state:'armed',tune:true};watchdog={tx_remaining_calls:6,tx_expired:false,tune_remaining_seconds:80};
  await page.evaluate(()=>window.wstxContact.load());
  r=await tickAndRead(page,offset,true);
  assert.deepEqual([r.label,r.next,r.countdown],['▶ TX now:','Tune','80 s left']);
  transmit={arm_state:'armed'};watchdog=null;await page.evaluate(()=>window.wstxContact.load());
  clock.offset=offset+11000;r=await tickAndRead(page,offset+11000,false);
  assert.deepEqual([r.label,r.next],['▸ next:','CQ HB9BLA JN47']);
  assert.match(r.countdown,/^Tx in \d+ s$/);assert.equal(Number(r.countdown.split(' ')[2]),15,'between periods: the next even period in 15 s');
  await page.screenshot({path:'test-results/ui-operating/qso-between-periods-1366x768.png'});
  await page.screenshot({path:'test-results/ui-operating/qso-calling-cq-1366x768.png'});
  await page.setViewportSize({width:360,height:800});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'no horizontal overflow at 360 px');
  await page.locator('#rx-focus').scrollIntoViewIfNeeded();
  await page.screenshot({path:'test-results/ui-operating/qso-calling-cq-360x800.png'});
  assert.deepEqual(errors,[]);
});

// Proves: CL-010-16, CL-037-03; TC-007-009 one fixed laptop screen and phone safety.
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
  // #37 LowerPanel: the DX entry is in the Control panel below the pane; Tx1-Tx6 in the fold-out.
  for(const selector of ['#dx-call','#dx-grid','#dx-generate'])assert.equal(await inViewport(page,selector),true,`${selector} in the Control panel`);
  assert.equal(await shown(page,'#contact-messages'),false,'Tx1-Tx6 folded away');
  await page.locator('#qso-more summary').click();assert.equal(await shown(page,'#contact-messages'),true,'Tx1-Tx6 in the fold-out');await page.locator('#qso-more summary').click();
  assert.equal(await page.locator('#connection').evaluate(el=>el.getBoundingClientRect().width<=1),true,'a connected link shows no status text');
  // #37 (operator 2026-11-03): one HALT on the screen, the QSO pane's.
  assert.deepEqual(await page.getByRole('button',{name:/^HALT$|^Halt Tx$/}).filter({visible:true}).evaluateAll(list=>list.map(b=>b.id)),['qso-halt'],'one HALT, in the QSO pane');
  await page.screenshot({path:'test-results/ui-operating/operating-screen-1366x768.png'});
  // A pointer HALT is on screen without scrolling at every size (the stacked pane at 1024x768
  // and 360 px is below the fold, so the top-bar HALT shows there).
  const haltOnScreen=async()=>page.waitForFunction(()=>[...document.querySelectorAll('#halt-tx,#qso-halt')].some(b=>{const r=b.getBoundingClientRect();return b.checkVisibility()&&r.top>=0&&r.bottom<=innerHeight&&r.left>=0&&r.right<=innerWidth;}),null,{timeout:3000});
  for(const [width,height] of [[1024,768],[1366,768],[1920,1080]]){await page.setViewportSize({width,height});await haltOnScreen();}
  await page.setViewportSize({width:1024,height:768});await page.waitForFunction(()=>document.querySelector('#halt-tx').checkVisibility(),null,{timeout:3000});
  await page.setViewportSize({width:1366,height:768});await page.waitForFunction(()=>!document.querySelector('#halt-tx').checkVisibility(),null,{timeout:3000});
  await page.setViewportSize({width:360,height:800});await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'a phone does not overflow horizontally');
  await haltOnScreen();
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

// Proves: CL-044-06; TC-044-005. Settings > Radio "Detect radio": the station's /radio routes are
// answered by route fixtures, so no serial port is ever probed or written by this test.
test('TC-044-005 Detect radio confirms keying inhibit, shows the proposal and fills the Radio section',{timeout:60000},async t=>{
  const capture='{0.0.1.00000000}.{6b9f2c1e-1111-4222-8333-944444444444}',render='{0.0.0.00000000}.{f4069c8a-1111-4222-8333-944444444444}';
  const radio=[],requests=[];
  const {page,app,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async p=>{
    p.on('request',r=>requests.push(`${r.method()} ${new URL(r.url()).pathname}`));
    await p.route('**/radio/detect',async route=>{const body=JSON.parse(route.request().postData());radio.push(['detect',body]);await route.fulfill({json:{v:1,profile_id:body.profile_id,boot_id:body.boot_id,
      ports:[{port:'COM250',friendly_name:'Silicon Labs CP210x USB to UART Bridge (COM250)',vid:'10C4',pid:'EA60',instance_id:'USB\\VID_10C4&PID_EA60\\IC-7300',state:'identified',
        radios:[{model:'IC-7300',id:'94',civ_address:'94',baud:19200,station_cat:true,unknown_model:false}],audio:null}],
      manual:['Yaesu','Kenwood','Elecraft'],supported_radios:1,audio_error:null,
      proposal:{port:'COM250',model:'IC-7300',civ_address:'94',baud:19200,control:{mode:'cat',endpoint:'icom7300://COM250?baud=19200&radio=94&controller=e0',ptt:'cat'},
        audio:{input_device:capture,output_device:render,input_name:'Microphone (USB Audio CODEC )',output_name:'Speakers (USB Audio CODEC )'}},
      settings:{port:3,source:'probe',civ_baud:19200,error:null,items:[{item:'0078',name:'usb_send',value:1,label:'DTR',recommended:0,severity:'blocking',message:'USB SEND on DTR/RTS can key the transmitter.'},
        {item:'0067',name:'data_mod',value:3,label:'USB',recommended:3,severity:'ok',message:'DATA MOD takes transmit audio from USB.'}]}}});});
    await p.route('**/radio/settings/*',async route=>{const action=new URL(route.request().url()).pathname.split('/').pop(),body=JSON.parse(route.request().postData());radio.push([action,body]);
      await route.fulfill({json:{v:1,profile_id:body.profile_id,boot_id:body.boot_id,action,result:'done',written:[{item:'0078',name:'usb_send',value:action==='apply'?0:1}],failed_item:null,error:null,undo:null}});});
  }});
  await page.waitForFunction(()=>!!window.wstxContact&&!!profileData,null,{timeout:30000});
  const profile=await (await fetch(app.origin+'/profile')).json();
  await page.locator('#open-server-settings').click();await page.locator('#tab-radio').click();
  await page.locator('#detect-run').scrollIntoViewIfNeeded();assert.equal(await inViewport(page,'#detect-run'),true,'Detect radio is in Settings > Radio');
  await page.waitForTimeout(1500);assert.deepEqual(radio,[],'nothing is fetched before a button press');
  assert.equal(await page.locator('#detect-run').isDisabled(),true,'detection waits for the keying-inhibit confirmation');
  await page.locator('#detect-ack').check();await page.locator('#detect-run:enabled').click();
  await page.locator('#detect-proposal:not([hidden])').waitFor();
  assert.deepEqual(radio,[['detect',{v:1,profile_id:profile.profile_id,boot_id:profile.boot_id,keying_inhibit_confirmed:true}]]);
  const fields=await page.locator('#detect-fields').textContent();
  for(const text of ['COM250','IC-7300','94h','19200','icom7300://COM250?baud=19200&radio=94&controller=e0','Microphone (USB Audio CODEC )',capture,'Speakers (USB Audio CODEC )',render])assert.ok(fields.includes(text),text);
  assert.match(await page.locator('#detect-items').textContent(),/0078 usb send: DTR · blocking/);
  assert.equal(await page.locator('#detect-ack').isChecked(),false,'the confirmation is asked again for the next detection');
  await page.locator('#detect-use').click();
  assert.deepEqual(await page.evaluate(()=>['control-mode','control-endpoint','ptt-mode','audio-input','audio-output'].map(id=>document.getElementById(id).value)),
    ['cat','icom7300://COM250?baud=19200&radio=94&controller=e0','cat',capture,render]);
  assert.equal(requests.includes('PUT /profile'),false,'Use this setup only fills the form');
  // Apply/Undo stay disabled until CAT is ready and the transmitter is disarmed.
  assert.equal(await page.locator('#radio-settings-apply').isDisabled(),true);assert.equal(await page.locator('#radio-settings-undo').isDisabled(),true);
  // The station's own connection generation (from its selection snapshot) is sent; CAT ready is injected.
  await page.waitForFunction(()=>Number.isSafeInteger(operatingState?.radio?.connection_generation));const generation=await page.evaluate(()=>operatingState.radio.connection_generation);
  await page.evaluate(()=>{catStatus={condition:'ready'};radioSetupShow();});
  await page.locator('#radio-settings-apply:enabled').click();await page.locator('#op-confirm[open]').waitFor();
  assert.match(await page.locator('#op-confirm-text').textContent(),/USB SEND and USB keying OFF, DATA MOD USB/);
  await page.locator('#op-confirm button[value=cancel]').click();await page.waitForTimeout(300);assert.equal(radio.length,1,'a cancelled apply sends nothing');
  await page.locator('#radio-settings-apply').click();await page.locator('#op-confirm-ok').click();
  await page.locator('#radio-settings-result').filter({hasText:'Applied'}).waitFor();
  await page.locator('#radio-settings-undo').click();await page.locator('#op-confirm-ok').click();
  await page.locator('#radio-settings-result').filter({hasText:'Restored'}).waitFor();
  const settingsBody={v:1,profile_id:profile.profile_id,boot_id:profile.boot_id,connection_generation:generation};
  assert.deepEqual(radio.slice(1),[['apply',settingsBody],['undo',settingsBody]],JSON.stringify(radio.slice(1)));
  // The filled Radio section is saved by the existing Apply ⟳ with endpoint IDs.
  await page.locator('#settings-save').click();await page.locator('#settings-result').filter({hasText:/Saved revision/}).waitFor();
  const saved=(await (await fetch(app.origin+'/profile')).json()).settings;
  assert.deepEqual([saved.control,saved.audio],[{mode:'cat',endpoint:'icom7300://COM250?baud=19200&radio=94&controller=e0',ptt:'cat'},{input_device:capture,output_device:render}]);
  await page.setViewportSize({width:360,height:800});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'the panel fits a phone');
  await page.locator('#settings-detect').screenshot({path:'test-results/ui-operating/detect-radio-mobile.png'});
  assert.deepEqual(errors,[]);
});

// Proves: CL-044-06; TC-044-005. Before the contact client (confirmation dialog, transmit state)
// is loaded, Apply/Undo radio settings stay disabled and send nothing, even with CAT ready.
test('TC-044-005 radio settings writes wait for the confirmation dialog and a known disarmed transmitter',{timeout:40000},async t=>{
  const radio=[];
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async p=>{
    await p.route('**/contact.js',()=>{});
    await p.route('**/radio/settings/*',async route=>{radio.push(route.request().url());await route.fulfill({status:409,json:{error:{code:'unexpected'}}});});
  }});
  await page.waitForFunction(()=>!!profileData&&Number.isSafeInteger(operatingState?.radio?.connection_generation),null,{timeout:30000});
  assert.equal(await page.evaluate(()=>!!window.wstxConfirm||!!window.wstxContact),false,'contact client held back');
  await page.evaluate(()=>{catStatus={condition:'ready'};radioSetupShow();});
  for(const id of ['#radio-settings-apply','#radio-settings-undo'])assert.equal(await page.locator(id).isDisabled(),true,id);
  await page.evaluate(()=>radioSettings('apply'));await page.waitForTimeout(500);
  assert.deepEqual(radio,[],'no unconfirmed settings write');assert.equal(await page.locator('#op-confirm[open]').count(),0);
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

// Proves: CL-052-01; TC-052-001 the FT8 window dump is an Expert setting, off by default and read on demand.
test('TC-052-001 Save FT8 decode windows reads and saves the station setting in Settings > Expert',{timeout:60000},async t=>{
  const {page,app,errors}=await fixture(t,{width:1366,height:768},{inputDevice:'test-only-unopened-input'});
  const requests=[],posts=[];
  page.on('request',r=>{const p=new URL(r.url()).pathname;requests.push(`${r.method()} ${p}`);if(r.method()==='POST'&&p==='/receive/diagnostics')posts.push(JSON.parse(r.postData()));});
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  assert.deepEqual(requests.filter(r=>r.endsWith('/receive/diagnostics')),[],'not read before Settings opens');
  const initial=await (await fetch(app.origin+'/receive/diagnostics')).json();
  assert.equal(initial.window_dump,false,'off by default');
  await page.locator('#open-server-settings').click();await page.locator('#tab-expert').click();
  const box=page.locator('#window-dump');await page.locator('#window-dump:enabled').waitFor();
  await box.scrollIntoViewIfNeeded();assert.equal(await inViewport(page,'#window-dump'),true,'the setting is in Settings > Expert');
  assert.equal(await page.locator('#settings-expert #window-dump').count(),1);
  assert.equal(await box.isChecked(),false,'shows the station value');
  assert.match(await page.locator('#window-diagnostics').textContent(),/^No window analysed yet/);
  await box.check();await page.waitForFunction(()=>!document.querySelector('#window-dump').disabled);
  assert.deepEqual(posts,[{v:1,profile_id:initial.profile_id,boot_id:initial.boot_id,window_dump:true}],'exactly one exact-key save');
  assert.equal((await (await fetch(app.origin+'/receive/diagnostics')).json()).window_dump,true,'the station stored it');
  await page.route('**/receive/diagnostics',route=>route.request().method()==='POST'?route.fulfill({status:409,json:{error:{code:'state_conflict'}}}):route.continue());
  await box.uncheck();await page.locator('#window-diagnostics').filter({hasText:'Not saved'}).waitFor();
  assert.match(await page.locator('#window-diagnostics').textContent(),/state_conflict/);
  assert.equal(await box.isChecked(),true,'a refusal restores the stored value');
  await page.unroute('**/receive/diagnostics');
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
  // The control shows the remembered value at load, before any station snapshot (held here).
  await page.route('**/recording',()=>{});
  await page.reload();await page.locator('#connection[data-state=connected]').waitFor();assert.equal(await page.locator('#display-speed').inputValue(),'4');assert.equal(await page.evaluate(()=>speed),4);
  assert.deepEqual(errors,[]);
});

// Proves: CL-050-07; TC-050-007 one frequency mapping for the waterfall pointer, the Rx/Tx lines
// and the axis ticks, and the WSJT-X brackets of the lines following the mode.
async function waterfallMappingPass(page,commands,settings,label){
  const wait=async n=>{for(let i=0;i<60&&commands.length<n;i++)await page.waitForTimeout(50);assert.equal(commands.length,n,`${label} command ${n}: ${JSON.stringify(commands.slice(-3))}`);return commands.at(-1);};
  // The oracle: the waterfall canvas's own box carries 0..3000 Hz.
  const axis=async()=>{const b=await page.evaluate(()=>{const r=document.querySelector('#waterfall').getBoundingClientRect();return {x:r.left,w:r.width};});return hz=>b.x+hz*b.w/3000;};
  const tickX=f=>page.evaluate(f=>{const s=document.querySelectorAll('#frequency-ruler > span')[f/100],r=s.getBoundingClientRect();return r.left+.5;},f);
  const centre=key=>page.evaluate(key=>{const r=document.querySelector(`#waterfall-wrap .ct-${key}`).getBoundingClientRect();return r.left+r.width/2;},key);
  const confirm=async(rx,tx)=>{settings.rx_hz=rx;settings.tx_hz=tx;await page.evaluate(()=>window.wstxContact.load());
    await page.waitForFunction(([rx,tx])=>document.querySelector('#waterfall-wrap .ct-rx').dataset.hz===String(rx)&&document.querySelector('#waterfall-wrap .ct-txm').dataset.hz===String(tx),[rx,tx]);};
  await page.waitForTimeout(150);
  let x=await axis();
  for(let f=0;f<=3000;f+=100)assert.ok(Math.abs(await tickX(f)-x(f))<=1,`${label}: axis tick ${f} Hz at ${await tickX(f)}, mapping ${x(f)}`);
  const wf=await page.locator('#waterfall').boundingBox(),y=wf.y+wf.height*.6;
  for(const f of [500,2500,1500]){
    const px=await tickX(f),n=commands.length;await page.mouse.dblclick(px,y);
    const c=await wait(n+1);assert.equal(c.action,'set_frequency');
    assert.ok(Math.abs(c.rx_hz-f)<=2&&Math.abs(c.tx_hz-f)<=2,`${label}: double-click at the ${f} Hz tick sent Rx ${c.rx_hz} Tx ${c.tx_hz}`);
    await confirm(c.rx_hz,c.tx_hz);
    for(const key of ['rx','txm'])assert.ok(Math.abs(await centre(key)-px)<=1,`${label}: ${key} line at ${await centre(key)} for the pointer at ${px} (${f} Hz)`);
  }
  {const px=await tickX(1000),n=commands.length;await page.mouse.click(px,y);const c=await wait(n+1);
    assert.equal(c.rx_hz,null);assert.ok(Math.abs(c.tx_hz-1000)<=2,`${label}: click at the 1000 Hz tick sent Tx ${c.tx_hz}`);
    await confirm(settings.rx_hz,c.tx_hz);assert.ok(Math.abs(await centre('txm')-px)<=1,`${label}: Tx line at ${await centre('txm')} for ${px}`);}
  {const from=await centre('txm'),to=await tickX(2000),n=commands.length;
    await page.mouse.move(from,y);await page.mouse.down();await page.mouse.move(to,y,{steps:6});
    assert.ok(Math.abs(await centre('txm')-to)<=1,`${label}: the dragged Tx line follows the pointer`);await page.mouse.up();
    const c=await wait(n+1);assert.equal(c.rx_hz,null);assert.ok(Math.abs(c.tx_hz-2000)<=2,`${label}: drag to the 2000 Hz tick sent Tx ${c.tx_hz}`);
    await confirm(settings.rx_hz,c.tx_hz);assert.ok(Math.abs(await centre('txm')-to)<=1,`${label}: confirmed Tx line at the drop point`);}
  x=await axis();
  // The brackets: from the line over the occupied width to its right, in the line's colour.
  const brackets=()=>page.evaluate(()=>['rx','txm'].map(key=>{const m=document.querySelector(`#waterfall-wrap .ct-${key}`),g=m.querySelector('.ct-goal');if(!g)return null;const r=g.getBoundingClientRect(),s=getComputedStyle(g);return {hz:Number(m.dataset.hz),left:r.left,right:r.right,top:r.top,height:r.height,colour:s.borderTopColor,visible:s.display!=='none'&&s.visibility!=='hidden'&&r.width>0,pointer:s.pointerEvents};}));
  for(const [period,width] of [[15000,50],[7500,4*12000/576],[15000,50]]){
    await page.evaluate(period=>dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,test:true,message:{v:1,type:'station.tick',data:{profile_id:profileData.profile_id,boot_id:profileData.boot_id,utc_ms:Date.now(),period_ms:period,transmitting:false,rx_level_db:null}}}})),period);
    await page.waitForTimeout(50);
    const got=await brackets();
    for(const [i,colour] of [[0,'rgb(48, 208, 80)'],[1,'rgb(255, 64, 64)']]){const b=got[i];
      assert.ok(b?.visible,`${label}: bracket ${i} shown (${JSON.stringify(b)})`);assert.equal(b.colour,colour);assert.equal(b.pointer,'none');
      assert.ok(Math.abs(b.left-x(b.hz))<=1&&Math.abs(b.right-x(b.hz+width))<=1,`${label} ${period} ms: bracket ${b.left}-${b.right}, mapping ${x(b.hz)}-${x(b.hz+width)}`);
      assert.ok(Math.abs(b.top-wf.y)<=1,`${label}: bracket at the top of the waterfall`);}
  }
  // A click inside a bracket still reaches the waterfall (within 1 px: a click's clientX is whole px).
  {const b=(await brackets())[0],n=commands.length;await page.mouse.click((b.left+b.right)/2,b.top+b.height/2);const c=await wait(n+1);
    assert.equal(c.rx_hz,null);assert.ok(Math.abs(c.tx_hz-(b.hz+25))<=Math.max(2,3000/wf.width),`${label}: click in the Rx bracket sent Tx ${c.tx_hz}`);await confirm(settings.rx_hz,c.tx_hz);}
}
test('TC-050-007 the waterfall pointer, Rx/Tx lines and axis share one frequency mapping; the brackets follow the mode',{timeout:150000},async t=>{
  for(const scale of [1,2]){
    const commands=[],settings={rx_hz:1500,tx_hz:1200,hold_tx:false};
    const {page,errors}=await fixture(t,{width:1366,height:768},{deviceScaleFactor:scale,beforeNavigate:async(p,app)=>{
      const base=await (await fetch(app.origin+'/profile')).json();
      await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{settings})}));
      await contactCommands(p,commands);
    }});
    await page.waitForFunction(()=>window.wstxContact?.snapshot()&&!document.querySelector('#contact-rx').disabled,null,{timeout:45000});
    // The station's own ticks are held back; the test's ticks set the mode.
    await page.evaluate(()=>addEventListener('station-message',e=>{if(e.detail?.message?.type==='station.tick'&&!e.detail.test)e.stopImmediatePropagation();},true));
    await waterfallMappingPass(page,commands,settings,`1366x768 dpr ${scale}`);
    if(scale===2){assert.deepEqual(errors,[]);continue;}
    await page.evaluate(()=>{for(const id of ['display-flatten','display-spectrum']){const box=document.querySelector('#'+id);box.checked=true;box.dispatchEvent(new Event('change'));}});
    await page.locator('#display-speed').fill('4');await page.locator('#display-speed').dispatchEvent('input');
    await waterfallMappingPass(page,commands,settings,'1366x768 Flatten, spectrum line, speed 4');
    for(const [width,height] of [[900,700],[360,800]]){await page.setViewportSize({width,height});await waterfallMappingPass(page,commands,settings,`${width}x${height}`);}
    assert.equal(commands.some(c=>c.action==='enable_tx'),false,'no pointer action enables Tx');
    assert.deepEqual(errors,[]);
  }
});

// Proves: CL-010-16, CL-037-03, CL-010-01, CL-010-09, CL-050-01; TC-007-009, TC-050-001 QSO pane, double-click to call, Band Activity history and menu.
test('TC-007-009 QSO pane buttons and a double-click start transmission; Band Activity keeps period history',{timeout:45000},async t=>{
  let state,contact=null,records=[];const commands=[],period=['2026-10-27T12:00:00.0000000Z','2026-10-27T12:00:15.0000000Z'];
  const standard=(from,to='CQ')=>({type:'standard',to:{kind:to==='CQ'?'token':'call',text:to,hash_bits:null,hash_value:null},from:{kind:'call',text:from,hash_bits:null,hash_value:null},ack:false,exchange:{kind:'grid',value:'FN42'}});
  const record=(sequence,text,from,hz,p,to='CQ')=>({sequence,start_frame:6000,frequency_hz:hz,snr_db:-10,dt_seconds:0.1,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text,fields:standard(from,to),period_start_utc:p});
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    state=liveFixture(await (await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    records=[record(0,'CQ K1ABC FN42','K1ABC',1000,period[0]),{...record(1,'CQ W1XYZ FN42','W1XYZ',1480,period[0]),a_priori:1}];
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
  // #56: an a-priori word (a_priori 1) carries the WSJT-X a1 marker outside the message text.
  assert.deepEqual(await page.locator('tr[data-result-id] td[data-col=message]').evaluateAll(cells=>cells.map(c=>[c.dataset.ap??null,getComputedStyle(c,'::after').content])),[[null,'none'],['a1','" a1"']],'a-priori marker');
  // QSO pane (#37, operator 2026-11-02): a CQ near Rx (W1XYZ at 1480 Hz) is no QSO pane line;
  // nobody calls me yet.
  await page.locator('#qso-others-none').filter({hasText:'nobody calling'}).waitFor();
  assert.deepEqual(await page.locator('#qso-others tr').allTextContents(),[]);
  // A new period keeps the previous one below a divider, newest first.
  records.push(record(2,'HB9BLA K1ABC -05','K1ABC',1010,period[1],'HB9BLA'));
  Object.assign(state.job,{next_sequence:3,available_count:3,latest_decode:{id:2,first_sequence:2,next_sequence:3,period_start_utc:period[1],complete:true}});
  await page.evaluate(()=>receiveSync());await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===1&&document.querySelectorAll('tr[data-period=history]').length===2);
  const order=await page.locator('#band-activity tbody tr').evaluateAll(rows=>rows.map(r=>r.classList.contains('ba-divider')?'|'+r.textContent:r.children[4].textContent));
  assert.deepEqual(order,['HB9BLA K1ABC -05','|FT8 period 12:00:00 UTC','CQ K1ABC FN42','CQ W1XYZ FN42']);
  assert.equal(await page.locator('tr[data-period=latest]').getAttribute('class'),'ba-tome','a call to my callsign is highlighted');
  assert.equal(await page.locator('tr[data-period=latest] td').first().evaluate(td=>getComputedStyle(td).backgroundColor),'rgba(255, 102, 102, 0.32)','#50: WSJT-X My call colour');

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
  contact=partner('replying');await page.evaluate(()=>window.wstxContact.load());await page.locator('#rx-focus .op-contact-identity strong').filter({hasText:'K1ABC'}).waitFor();
  // #37 (operator 2026-11-03): no RR73 or 73 button; the fold-out Now of a Tx line chooses it
  // next and turns Enable Tx on, as WSJT-X Next/Now. No Reply button either since the #50
  // double-click fix is installed: the double-click above replies.
  assert.equal(await page.locator('#qso-rr73,#qso-73,#qso-reply').count(),0,'no Reply, RR73 or 73 button');
  assert.deepEqual(await page.locator('#rx-focus .op-qso-buttons button').allTextContents(),['CQ','Tune','HALT','Log QSO']);
  await page.locator('#qso-more summary').click();
  const now=slot=>page.locator(`#contact-messages .ct-now[data-slot=${slot}]`);
  m=commands.length;await now('tx4').click();for(let i=0;i<60&&commands.length<m+2;i++)await page.waitForTimeout(50);
  assert.deepEqual(commands.slice(m).map(c=>[c.action,c.slot??c.enabled,c.safety_revision]),[['choose_next','tx4',undefined],['enable_tx',true,7]],'Now Tx4: Tx4 next, then transmit');
  m=commands.length;await now('tx5').click();for(let i=0;i<60&&commands.length<m+2;i++)await page.waitForTimeout(50);
  assert.deepEqual(commands.slice(m).map(c=>[c.action,c.slot??c.enabled,c.safety_revision]),[['choose_next','tx5',undefined],['enable_tx',true,7]],'Now Tx5 on a contact in progress: Tx5 next, then transmit');
  // #37 review: on a completed contact Enable Tx would start a fresh CQ, so Now is off.
  contact=partner('completed');await page.evaluate(()=>window.wstxContact.load());await page.waitForFunction(()=>document.querySelector('#contact-messages .ct-now[data-slot=tx5]').disabled);
  assert.deepEqual([await now('tx4').isDisabled(),await now('tx5').isDisabled()],[true,true],'Now disabled on a completed contact');
  m=commands.length;await now('tx4').click({force:true});await now('tx5').click({force:true});
  await now('tx5').evaluate(b=>{b.disabled=false;b.click();b.disabled=true;});await page.waitForTimeout(500);
  assert.deepEqual(commands.slice(m),[],'a completed contact sends no choose_next or enable_tx');
  await page.locator('#qso-more summary').click();
  contact=partner('replying');await page.evaluate(()=>window.wstxContact.load());await page.waitForFunction(()=>!document.querySelector('#contact-messages .ct-now[data-slot=tx5]').disabled);
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
  for(const selector of ['#operating-workspace','#radio-toolbar','#qso-halt','#rxtx-strip','#qso-cq'])assert.equal(await page.locator(selector).isVisible(),true,`${selector} after authorization`);
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
   const haltShown=page.locator('#halt-tx:visible,#qso-halt:visible').first();await haltShown.scrollIntoViewIfNeeded();assert.equal(await haltShown.isVisible(),true);assert.equal(await haltShown.isDisabled(),true);
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
 // The presentation rows are not station records: the page's own render (operatingSync -> receiveShow ->
 // renderResults, every 2 s while Band Activity is empty) would replace them mid-test, so it is held here.
 await page.evaluate(()=>{renderResults=()=>{};});
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
  // Detailed fetches the next page at once (#57), so the second page waits for the first sort.
  let state,records,held=null,hold=false;const pending=deferred(),secondPage=deferred();
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
      if(cursor===17)await secondPage.promise;
      const batch=records.slice(cursor,cursor+limit),next=cursor+batch.length;
      const response={...emptyResults(state),first_sequence:0,next_sequence:records.length,available_count:records.length,next,more:next<records.length,records:batch,latest_decode:structuredClone(state.job.latest_decode)};
      if(hold&&cursor>=35){held={route,response};pending.resolve();}else await route.fulfill({json:response});
    });
  }});
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===16);
  // #55: the default is the value order; Freq once ascending, twice descending.
  await clickSort(page,'frequency');await clickSort(page,'frequency');assert.deepEqual(await sortState(page),['frequency','desc']);secondPage.resolve();
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

// Proves: CL-057-03; TC-057-004 (#37/#57). Band Activity keeps only the latest even and odd
// periods: after three consecutive periods only periods 2 and 3 are shown, the newest on top
// below no divider and the other below one; a same-parity successor (a skipped period) drops
// the older one; result reads never page below the current view.
test('TC-057-004 three consecutive periods leave only the latest even and odd period',{timeout:45000},async t=>{
  let state,records=[];const cursors=[];
  const periods=['2026-10-27T12:00:00.0000000Z','2026-10-27T12:00:15.0000000Z','2026-10-27T12:00:30.0000000Z','2026-10-27T12:01:00.0000000Z'];
  const makeRecord=(sequence,period)=>({sequence,start_frame:186000+sequence,frequency_hz:1000+sequence,snr_db:-12,payload77:'0'.repeat(77),i3:0,n3:0,status:'decoded',text:`PERIOD FIXTURE ${sequence}`,fields:{},period_start_utc:period,dt_seconds:0.1});
  const publish=(id,period,count)=>{const first=records.length;for(let i=0;i<count;i++)records.push(makeRecord(first+i,period));Object.assign(state.job,{first_sequence:0,next_sequence:records.length,available_count:records.length,latest_decode:{id,first_sequence:first,next_sequence:records.length,period_start_utc:period,complete:true}});};
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(page,app)=>{
    state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    publish(1,periods[0],3);
    await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await page.route('**/receive/results?*',async route=>{
      const query=new URL(route.request().url()).searchParams,cursor=Number(query.get('cursor')),limit=Number(query.get('limit'));cursors.push([cursor,state.job.latest_decode.first_sequence]);
      const batch=records.slice(cursor,cursor+limit),next=cursor+batch.length;
      await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:records.length,available_count:records.length,next,more:next<records.length,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});
    });
  }});
  const shown=()=>page.evaluate(()=>[...document.querySelectorAll('#band-activity tbody tr')].map(r=>r.classList.contains('ba-divider')?'|'+r.textContent:`${r.dataset.period}:${r.dataset.sequence}`));
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===3&&window.wstxRenderHistory);// contact.js renders the replaced period
  publish(2,periods[1],2);await page.evaluate(()=>receiveSync());
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===2&&resultView.id===2);
  assert.deepEqual(await shown(),['latest:3','latest:4','|FT8 period 12:00:00 UTC','history:0','history:1','history:2']);
  publish(3,periods[2],2);await page.evaluate(()=>receiveSync());
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===2&&resultView.id===3);
  assert.deepEqual(await shown(),['latest:5','latest:6','|FT8 period 12:00:15 UTC','history:3','history:4'],'only periods 2 and 3 after the third period');
  assert.equal(await page.locator('tr.ba-divider').count(),1,'never more than two periods');
  // 12:01:00 follows 12:00:30 with a skipped period: same parity, so the older one disappears.
  publish(4,periods[3],1);await page.evaluate(()=>receiveSync());
  await page.waitForFunction(()=>resultView.id===4&&document.querySelectorAll('tr[data-period=latest]').length===1);
  assert.deepEqual(await shown(),['latest:7']);
  assert.deepEqual(cursors.filter(([cursor,first])=>cursor<first),[],'no result read below the current view');
  assert.deepEqual(errors,[]);
});

// Proves: CL-061-03; TC-061-004 (#61, operator decision 2026-11-04). The station marks its Tx
// period (latest_decode transmitted true, no records, CL-061-04); Band Activity renders that
// marker and no empty-period block, the receive period before it stays below its divider, and
// the next receive period keeps it. A genuinely empty receive period keeps its note. No
// station.tick says transmitting: the browser does not infer the Tx period.
test('TC-061-004 a Tx period shows the station Tx marker, no empty block, and keeps the receive periods',{timeout:45000},async t=>{
  let state,records=[];
  const makeRecord=(sequence,period)=>({sequence,start_frame:186000+sequence,frequency_hz:1000+sequence,snr_db:-12,payload77:'0'.repeat(77),i3:0,n3:0,status:'decoded',text:`PERIOD FIXTURE ${sequence}`,fields:{},period_start_utc:period,dt_seconds:0.1});
  const publish=(id,period,count,transmitted)=>{const first=records.length;for(let i=0;i<count;i++)records.push(makeRecord(first+i,period));Object.assign(state.job,{first_sequence:0,next_sequence:records.length,available_count:records.length,latest_decode:transmitted?{id,first_sequence:first,next_sequence:first,period_start_utc:period,complete:false,transmitted:true}:{id,first_sequence:first,next_sequence:records.length,period_start_utc:period,complete:true}});};
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(page,app)=>{
    state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    publish(1,'2026-10-27T12:00:00.0000000Z',3);
    await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await page.route('**/receive/results?*',async route=>{
      const query=new URL(route.request().url()).searchParams,cursor=Number(query.get('cursor')),limit=Number(query.get('limit'));
      const batch=records.slice(cursor,cursor+limit),next=cursor+batch.length;
      await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:records.length,available_count:records.length,next,more:next<records.length,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});
    });
  }});
  const shown=()=>page.evaluate(()=>[...document.querySelectorAll('#band-activity tbody tr')].map(r=>r.classList.contains('ba-divider')?'|'+r.textContent:r.querySelector('.empty-messages')?'empty:'+r.textContent:r.dataset.period==='tx'?'tx:'+r.textContent:`${r.dataset.period}:${r.dataset.sequence}`));
  const header=()=>page.locator('#band-activity header .op-muted').textContent();
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===3&&window.wstxRenderHistory);
  // The station transmitted in 12:00:15 and publishes it as a Tx period.
  publish(2,'2026-10-27T12:00:15.0000000Z',0,true);await page.evaluate(()=>receiveSync());
  await page.waitForFunction(()=>resultView?.id===2);await page.waitForTimeout(300);
  assert.deepEqual(await shown(),['tx:Tx 12:00:15 · this station transmitted · no decode','|FT8 period 12:00:00 UTC','history:0','history:1','history:2'],'the Tx marker on top, the receive period below its divider');
  assert.doesNotMatch(await page.locator('#band-activity').innerText(),/No stations decoded|No verified stations/);
  assert.equal(await header(),'Tx · FT8 period 12:00:15 UTC · this station transmitted, no decode');
  assert.match(await page.locator('#band-activity .op-count').textContent(),/^3 messages$/);
  publish(3,'2026-10-27T12:00:30.0000000Z',2);await page.evaluate(()=>receiveSync());
  await page.waitForFunction(()=>resultView?.id===3&&document.querySelectorAll('tr[data-period=latest]').length===2);
  assert.deepEqual(await shown(),['latest:3','latest:4','|FT8 period 12:00:00 UTC','history:0','history:1','history:2'],'the receive period before the transmission stays below; the marker is gone');
  assert.match(await header(),/^Latest FT8 period 12:00:30 UTC/);
  // 12:00:45 is a receive period (no transmission) that decodes nothing: its small note stays.
  publish(4,'2026-10-27T12:00:45.0000000Z',0);await page.evaluate(()=>receiveSync());
  await page.waitForFunction(()=>resultView?.id===4);
  assert.deepEqual(await shown(),['empty:No stations decodedNo verified stations were decoded in this period.','|FT8 period 12:00:30 UTC','history:3','history:4']);
  assert.match(await header(),/^Latest FT8 period 12:00:45 UTC/);
  assert.deepEqual(errors,[]);
});

// Proves: CL-061-04; TC-061-006 (#61, operator decision 2026-11-04). The station measures no Rx
// level in its Tx period (station.tick rx_level_db null) and marks its waterfall rows (tx true);
// the browser shows level warnings for receive periods only and paints Tx rows as Tx.
test('TC-061-006 Tx rows are painted as Tx and level warnings show for receive periods only',{timeout:45000},async t=>{
  const {page,errors}=await liveDisplayFixture(t);
  // Each tick is read in the same task (its handler redraws the meter synchronously and the
  // error field is rebuilt from it), so no other station.tick can interleave.
  const tick=(transmitting,level)=>page.evaluate(([transmitting,level])=>{
    dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,test:true,message:{v:1,type:'station.tick',data:{profile_id:profileData.profile_id,boot_id:profileData.boot_id,utc_ms:Date.now(),period_ms:15000,transmitting,rx_level_db:level}}}}));
    window.wstxChipsShow();
    return [document.querySelector('#settings-audio .op-input-meter strong').textContent,/Audio level low|Audio overdriven/.test(document.querySelector('#error-field').innerText)];
  },[transmitting,level]);
  await page.waitForSelector('#error-field');await testTicksOnly(page);
  assert.deepEqual(await tick(false,5),['5 dB low',true],'a receive period with a low level shows the warning');
  assert.deepEqual(await tick(true,null),['Tx · not measured',false],'on the air: no level, no warning');
  assert.deepEqual(await tick(false,null),['Unavailable',false],'the rest of the Tx period: still no level and no warning');
  assert.deepEqual(await tick(false,5),['5 dB low',true],'the next receive period measures again');
  // Waterfall: two Tx rows, then a receive row.
  const level=q=>Array.from({length:1024},()=>q);
  await liveFrames(page,[{sequence:0,levels:level(60),tx:true},{sequence:1,levels:level(60),tx:true}]);
  assert.deepEqual(await page.evaluate(()=>rows.map(r=>[r.sequence,r.tx])),[[0,true],[1,true]],'the tx rows are accepted');
  assert.deepEqual(await cell(page,500),[90,20,30],'a Tx row is painted as Tx, not with its levels');
  await liveFrames(page,[{sequence:2,levels:level(0)}]);
  assert.deepEqual(await cell(page,500),[0,0,12],'a receive row shows its levels');
  assert.deepEqual(errors,[]);
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
  // #10 PushedStationState: the station announces each publication with receive.state; the
  // page then reads results once more, and that page announces the newer period.
  await page.waitForFunction(()=>resultCursor===19&&!resultPending);
  await page.evaluate(s=>dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'receive.state',data:{profile_id:s.profile_id,boot_id:s.boot_id,generation:s.generation,source_id:s.source.id,job_id:s.job.id,state:'running'}}}})),state);
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
  // #55 CL-055-04: by default the value order (all without a flag here), strongest SNR first, unknown last.
  assert.deepEqual(await order(),[1,4,3,0,2]);assert.deepEqual(await sortState(page),['value','desc']);
  await clickSort(page,'frequency');
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
  await page.evaluate(()=>{profileData.profile_id='00000000-0000-4000-8000-000000000001';renderResults();});assert.deepEqual(await sortState(page),['value','desc'],'a different profile resets to the value order');
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
 // #37: Log QSO is offered while the QSO runs; it logs and closes it (the station completes it).
 const contact=partner('completed',{report_rcvd:'-05'});
 snapshot={contact:{...contact,state:'rogers',next_slot:'tx4'},log:null};await page.evaluate(()=>window.wstxContact.load());
 await page.waitForFunction(()=>window.wstxContact.snapshot().contact?.state==='rogers');
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
 assert.equal(await page.locator('#contact-logged').textContent(),'\u2713 Logged K1ABC');
 assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true,'the Logbook page never hides Halt Tx');
 assert.ok(posts.every(p=>p==='/contact/command'),'the browser never saves a contact: '+posts.join());
 assert.deepEqual(errors,[]);
});

// Proves: CL-010-04; TC-011-002 browser subset (#10 Update logbook from ADIF). Actual server
// and Chromium; a synthetic Log4OM-shaped export (byte order mark, '#' banner, PROGRAMID
// LOG4OM2, a UTF-8 NAME, MFSK/FT4) and hand-counted summaries.
test('TC-011-002 Update logbook from ADIF in Settings consolidates a logger export and Export downloads contacts.adi',{timeout:30000},async t=>{
 const {page,errors}=await fixture(t,{width:1200,height:900});
 await page.waitForFunction(()=>profileData&&window.wstxLogbook);
 await page.locator('#open-server-settings').click();await page.locator('#tab-logging').click();
 const section=page.locator('#settings-update-log');
 await section.getByRole('heading',{name:'Update logbook from ADIF'}).waitFor();
 assert.equal(await page.locator('#settings-log + #settings-update-log').count(),1,'beside the Log block');
 const good='﻿#++++++++\n#   Log4OM 2 test export\n#   created: Dienstag, 3. März 2026\n#++++++++\n\n<ADIF_VER:5>3.1.0 <PROGRAMID:7>LOG4OM2 <PROGRAMVERSION:8>2.42.1.0 <eoh>\n\n'
  +'<CALL:5>K1ABC <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20261031 <TIME_ON:6>123000 <NAME:9>José Test <GRIDSQUARE:5>FN42a <EMAIL:13>k@example.net <eor>\n\n'
  +'<CALL:6>DL1ABC <BAND:3>40m <MODE:4>MFSK <SUBMODE:3>FT4 <QSO_DATE:8>20261031 <TIME_ON:6>123100 <DXCC:3>230 <eor>\n\n'
  +'<BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20261031 <TIME_ON:4>1232 <eor>\n';
 const update=async(name,text,expected)=>{
  await page.locator('#log-import-file').setInputFiles({name,mimeType:'text/plain',buffer:Buffer.from(text)});
  await section.getByRole('button',{name:'Update logbook'}).click();
  await page.locator('#log-import-status',{hasText:expected}).waitFor();
  assert.equal(await page.locator('#log-import-status').innerText(),expected);
 };
 await update('log4om.adi',good,'Logbook updated: 2 added, 0 already present, 1 skipped (1 missing required field call) · fields left out: 1 invalid value gridsquare');
 await update('log4om.adi',good,'Logbook updated: 0 added, 2 already present, 1 skipped (1 missing required field call) · fields left out: 1 invalid value gridsquare');
 const bad='<call:5>N0NEW <qso_date:8>20261031 <time_on:4>1300 <mode:3>FT8 <eor>\n<call:5>W1XYZ <qso_date:8>20261031 <time_on:4>1230 <band:3>20m <mode:3>FT8 <eor\n';
 await update('bad.adi',bad,'Logbook not updated · nothing was added · malformed in record 2');
 await page.setViewportSize({width:360,height:800});
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'no horizontal overflow at 360 px');
 await page.setViewportSize({width:1200,height:900});
 await page.locator('#settings-drawer .return-operate').click();
 await page.locator('#station-bar [data-region="logbook"]').click();
 await page.locator('#log-history-status',{hasText:'2 contacts'}).waitFor();
 assert.doesNotMatch(await page.locator('#log-history').innerText(),/other field/);
 assert.equal(await page.locator('#region-logbook #log-import').count(),0,'the Logbook page only exports');
 const [download]=await Promise.all([page.waitForEvent('download'),page.getByRole('button',{name:'Export ADIF'}).click()]);
 assert.equal(download.suggestedFilename(),'contacts.adi');
 const text=await fs.readFile(await download.path(),'utf8');
 assert.match(text,/^ADIF Export\n<adif_ver:5>3\.1\.8\n/);
 assert.match(text,/<call:5>K1ABC <mode:3>FT8 <qso_date:8>20261031 <time_on:6>123000 <band:3>20m <app_wstxrust_contact_id:36>[0-9a-f-]{36} <app_wstxrust_source:7>LOG4OM2 <eor>\n/);
 assert.match(text,/<call:6>DL1ABC <mode:4>MFSK <submode:3>FT4 <qso_date:8>20261031 <time_on:6>123100 <band:3>40m <app_wstxrust_contact_id:36>[0-9a-f-]{36} <app_wstxrust_source:7>LOG4OM2 <eor>\n/);
 assert.doesNotMatch(text,/Jos|example|dxcc|name/i,'only the log fields are stored');
 assert.equal(text.match(/<eor>/g).length,2);
 assert.match(await page.locator('#log-export-status').innerText(),/Exported contacts\.adi/);
 assert.deepEqual(errors,[]);
});

// Proves: CL-010-13; TC-011-003, TC-050-002 browser subset. Actual server log and worked-before query;
// receive pages and the manual band selection are presentation fixtures, not RF truth.
test('TC-011-003 Band Activity shows server worked-before status with one bounded query per period',{timeout:30000},async t=>{
 let state;const queries=[];
 const period='2026-10-27T12:00:15.0000000Z';
 const standard=(from)=>({type:'standard',to:{kind:'token',text:'CQ',hash_bits:null,hash_value:null},from:{kind:'call',text:from,hash_bits:null,hash_value:null},ack:false,exchange:{kind:'grid',value:'FN42'}});
 const reply={type:'standard',to:{kind:'call',text:'K9XX',hash_bits:null,hash_value:null},from:{kind:'call',text:'W2AB',hash_bits:null,hash_value:null},ack:false,exchange:{kind:'report',value:-5}};
 const records=[['K1ABC',standard('K1ABC')],['W1XYZ',standard('W1XYZ')],['FREE',{}],['W2AB',reply]].map(([call,fields],i)=>({sequence:i,start_frame:186000+i,frequency_hz:1000+i*100,snr_db:-10,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text:call==='FREE'?'FREE TEXT':call==='W2AB'?'K9XX W2AB R-05':`CQ ${call} FN42`,fields,period_start_utc:period,dt_seconds:0.1,...(['W1XYZ','W2AB'].includes(call)?{flags:{new_call:true,new_call_band:true}}:{})}));
 const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(page,app)=>{
  const profile=await(await fetch(app.origin+'/profile')).json();
  const saved=await fetch(app.origin+'/contacts',{method:'POST',headers:{'Content-Type':'application/json',Origin:app.origin},body:JSON.stringify({v:1,profile_id:profile.profile_id,boot_id:profile.boot_id,command_id:crypto.randomUUID(),record:{contact_id:crypto.randomUUID(),call:'K1ABC',gridsquare:null,mode:'FT8',submode:null,rst_sent:null,rst_rcvd:null,qso_date:'20261027',time_on:'115900',qso_date_off:'20261027',time_off:'120000',band:'20m',freq:null,station_callsign:'HB9BLA',my_gridsquare:'JN47AA',tx_pwr:null,comment:null}})});
  assert.equal(saved.status,201);
  state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
  state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
  Object.assign(state.job,{first_sequence:0,next_sequence:4,available_count:4,latest_decode:{id:1,first_sequence:0,next_sequence:4,period_start_utc:period,complete:true}});
  await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
  await page.route('**/receive/selection',async route=>{const s=await(await route.fetch()).json();s.selection={...s.selection,band:'20m',nominal_hz:14074000,origin:'manual'};await route.fulfill({json:s});});
  await page.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor'));const batch=records.slice(cursor),next=cursor+batch.length;await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:4,available_count:4,next,more:false,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
  page.on('request',r=>{if(new URL(r.url()).pathname==='/contact/worked')queries.push(JSON.parse(r.postData()));});
 }});
 await page.locator('tr[data-result-id][data-worked]').first().waitFor();
 // #50: no text marks; the New call slots come from the #55 flags of every sender (CL-055-04) and are on
 // by default. Only interesting stations are coloured (operator 2026-11-03, unlike WSJT-X): no CQ slot, so
 // the CQ of a station worked on this band and mode has no colour; rows in value order.
 const rowsNow=()=>page.locator('tr[data-result-id]').evaluateAll(rows=>rows.map(r=>[r.children[4].textContent,r.dataset.worked??null,r.dataset.hl??null,getComputedStyle(r.children[4]).backgroundColor]));
 const [newCallBand,newCall,none]=['rgba(153, 255, 255, 0.2)','rgba(0, 255, 255, 0.24)','rgba(0, 0, 0, 0)'];
 assert.deepEqual(await rowsNow(),[['CQ W1XYZ FN42','not_worked','new_call new_call_band',newCall],['K9XX W2AB R-05','not_worked','new_call new_call_band',newCall],['CQ K1ABC FN42','worked_this_band_and_mode',null,none],['FREE TEXT',null,null,none]],'no CQ colour; worked before has no colour; New slots on non-CQ senders too (CL-055-04)');
 await page.locator('#open-server-settings').click();
 assert.equal(await page.locator('#band-colours [data-hl-slot=cq]').count(),0,'Settings lists no CQ slot');
 await page.locator('#band-colours [data-hl-slot=new_call]').uncheck();await page.locator('#settings-drawer .return-operate').click();
 assert.deepEqual((await rowsNow()).map(r=>r[3]),[newCallBand,newCallBand,none,none],'with New call off, New call on band remains');
 assert.deepEqual(JSON.parse(await page.evaluate(()=>localStorage.getItem('wstx.band-colours.v1'))).new_call,false,'the choice is per browser');
 // Priority by the WSJT-X order for the #55 flags: My call over New continent over New DXCC; no CQ colour.
 const priority=await page.evaluate(()=>{const tbody=document.querySelector('#band-activity tbody');return ['new_dxcc','new_dxcc new_continent','new_dxcc new_continent mycall','new_grid','new_itu_zone','cq'].map(hl=>{const tr=document.createElement('tr'),td=document.createElement('td');tr.dataset.hl=hl;tr.append(td);tbody.append(tr);const c=getComputedStyle(td).backgroundColor;tr.remove();return c;});});
 assert.deepEqual(priority,['rgba(255, 0, 255, 0.26)','rgba(255, 0, 99, 0.28)','rgba(255, 102, 102, 0.32)',none,none,none],'WSJT-X priority; New grid and ITU zone are off by default; no CQ colour');
 await clickSort(page,'frequency');await page.waitForTimeout(300);
 await refreshStatus(page);await page.waitForTimeout(500);
 assert.equal(queries.length,1,'one query per published period');
 assert.deepEqual(queries[0].calls,['K1ABC','W1XYZ','W2AB']);assert.equal(queries[0].band,'20m');assert.equal(queries[0].mode,'FT8');
 assert.equal(await page.locator('tr[data-worked=worked_this_band_and_mode]').getAttribute('title'),'Worked before on 20m FT8','the status stays readable as the row tooltip (#55 BandActivityHover)');
 assert.deepEqual(errors,[]);
});

// Proves: CL-010-13; TC-011-003 QSO pane subset (#10 2026-11-04). Actual server log and worked-before
// query; receive pages, flags and the manual band selection are presentation fixtures, not RF truth.
// The stations calling me carry the Band Activity marks: only interesting senders coloured, worked
// before on this band and mode no colour, the status as text, and no extra query.
test('TC-011-003 QSO pane callers show worked-before status and only interesting stations are coloured',{timeout:40000},async t=>{
 let state;const queries=[],period='2026-10-27T12:00:15.0000000Z';
 const standard=(from,exchange)=>({type:'standard',to:{kind:'call',text:'HB9BLA',hash_bits:null,hash_value:null},from:{kind:'call',text:from,hash_bits:null,hash_value:null},ack:false,exchange});
 const rows=[['HB9BLA K1ABC FN42','K1ABC',{kind:'grid',value:'FN42'},null],['HB9BLA W1XYZ FN31','W1XYZ',{kind:'grid',value:'FN31'},{new_call:true,new_call_band:true}],['HB9BLA DL1ABC -10','DL1ABC',{kind:'report',value:-10},{new_call_band:true}]];
 const records=rows.map(([text,from,exchange,flags],i)=>({sequence:i,start_frame:186000+i,frequency_hz:1000+i*300,snr_db:-10,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text,fields:standard(from,exchange),period_start_utc:period,dt_seconds:0.1,...(flags?{flags}:{})}));
 const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(page,app)=>{
  const profile=await(await fetch(app.origin+'/profile')).json();
  for(const [call,band] of [['K1ABC','20m'],['DL1ABC','40m']]){
   const saved=await fetch(app.origin+'/contacts',{method:'POST',headers:{'Content-Type':'application/json',Origin:app.origin},body:JSON.stringify({v:1,profile_id:profile.profile_id,boot_id:profile.boot_id,command_id:crypto.randomUUID(),record:{contact_id:crypto.randomUUID(),call,gridsquare:null,mode:'FT8',submode:null,rst_sent:null,rst_rcvd:null,qso_date:'20261027',time_on:'115900',qso_date_off:'20261027',time_off:'120000',band,freq:null,station_callsign:'HB9BLA',my_gridsquare:'JN47AA',tx_pwr:null,comment:null}})});
   assert.equal(saved.status,201);
  }
  state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
  state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
  Object.assign(state.job,{first_sequence:0,next_sequence:3,available_count:3,latest_decode:{id:1,first_sequence:0,next_sequence:3,period_start_utc:period,complete:true}});
  await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
  await page.route('**/receive/selection',async route=>{const s=await(await route.fetch()).json();s.selection={...s.selection,band:'20m',nominal_hz:14074000,origin:'manual'};await route.fulfill({json:s});});
  await page.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor'));const batch=records.slice(cursor),next=cursor+batch.length;await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:3,available_count:3,next,more:false,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
  await page.route('**/contact',route=>route.fulfill({json:contactSnapshot(profile,{contact:null,transmit:{},log:null,settings:{}})}));
  page.on('request',r=>{if(new URL(r.url()).pathname==='/contact/worked')queries.push(JSON.parse(r.postData()));});
 }});
 await page.waitForFunction(()=>document.querySelectorAll('#qso-others tr[data-worked]').length===3,null,{timeout:25000});
 const others=()=>page.locator('#qso-others tr').evaluateAll(rows=>rows.map(tr=>[tr.dataset.text,tr.dataset.worked??null,tr.dataset.hl??null,getComputedStyle(tr.cells[1]).backgroundColor,tr.title,tr.getAttribute('aria-description')]));
 const [newCallBand,newCall,none]=['rgba(153, 255, 255, 0.2)','rgba(0, 255, 255, 0.24)','rgba(0, 0, 0, 0)'];
 const hint='Double-click: answer this station';
 assert.deepEqual(await others(),[
  ['HB9BLA K1ABC FN42','worked_this_band_and_mode',null,none,`Worked before on 20m FT8\n${hint}`,'Worked before on 20m FT8'],
  ['HB9BLA W1XYZ FN31','not_worked','new_call new_call_band',newCall,`New call\nNew call on 20m\n${hint}`,'New call; New call on 20m'],
  ['HB9BLA DL1ABC -10','worked_other_band_or_mode','new_call_band',newCallBand,`New call on 20m\nWorked before on another band or mode\n${hint}`,'New call on 20m; Worked before on another band or mode']],
  'worked before on this band and mode has no colour; the status is text; My call is not a caller colour');
 // The Band Activity colour choice applies here too.
 await page.locator('#open-server-settings').click();
 await page.locator('#band-colours [data-hl-slot=new_call]').uncheck();await page.locator('#settings-drawer .return-operate').click();
 assert.deepEqual((await others()).map(r=>r[3]),[none,newCallBand,newCallBand],'with New call off, New call on band remains');
 await refreshStatus(page);await page.waitForTimeout(500);
 assert.equal(queries.length,1,'the callers add no worked-before query');
 assert.deepEqual(errors,[]);
});

// Proves: CL-055-04; TC-055-006 browser subset. Actual server log and worked-before query;
// the result records (with #55 dxcc and flags), the strategy verdict and the selection band
// are presentation fixtures.
test('TC-055-006 Band Activity colours every sender, names each reason on hover and sorts by value',{timeout:40000},async t=>{
 const period='2026-10-27T12:00:15.0000000Z';
 const fields=(from,to,exchange)=>({type:'standard',to:{kind:to.startsWith('CQ')?'token':'call',text:to,hash_bits:null,hash_value:null},from:{kind:'call',text:from,hash_bits:null,hash_value:null},ack:false,exchange});
 const F=(...names)=>Object.fromEntries(names.map(n=>[n,true]));
 const ro={name:'Romania',cont:'EU',cq:20,itu:28},ja={name:'Japan',cont:'AS',cq:25,itu:45},us={name:'U.S.A.',cont:'NA',cq:5,itu:8},en={name:'England',cont:'EU',cq:14,itu:27};
 // [text, from, to, exchange, snr, flags, dxcc]
 const rows=[
  ['CQ K1ABC FN42','K1ABC','CQ',{kind:'grid',value:'FN42'},-10,null,us],
  ['K9XX YO3ABC -07','YO3ABC','K9XX',{kind:'report',value:-7},-15,F('new_dxcc','new_dxcc_band','new_call','new_call_band'),ro],
  ['HB9BLA W1XYZ -12','W1XYZ','HB9BLA',{kind:'report',value:-12},-18,F('new_call','new_call_band'),us],
  ['CQ JA1AAA PM95','JA1AAA','CQ',{kind:'grid',value:'PM95'},-5,F('new_cq_zone','new_cq_zone_band'),ja],
  ['CQ G4XYZ IO91','G4XYZ','CQ',{kind:'grid',value:'IO91'},-8,F('new_grid','new_grid_band'),en],
  ['K9XX W2AB R-05','W2AB','K9XX',{kind:'report',value:-5},-20,F('new_call','new_call_band'),us],
  ['K1ZZ W3EF RR73','W3EF','K1ZZ',{kind:'roger',value:'RR73'},-4,F('new_call','new_call_band'),us],
  ['FREE TEXT',null,null,null,0,null,null],
  ['W9AA W2CD 73','W2CD','W9AA',{kind:'roger',value:'73'},-12,null,us],
 ];
 const records=rows.map(([text,from,to,exchange,snr,flags,dxcc],i)=>({sequence:i,start_frame:186000+i,frequency_hz:2400-i*150,snr_db:snr,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text,fields:from?fields(from,to,exchange):{},period_start_utc:period,dt_seconds:0.1,...(flags?{flags}:{}),...(dxcc?{dxcc}:{})}));
 const n=records.length;let state,view;
 const strategy={name:'Hover test',rules:[{conditions:[{kind:'message',negate:false,value:'cq'}]}],sort:'strongest',treat_73_as_cq:false,apply_to_callers:false,skip_after:5,auto_role:'call',switch_after:3};
 const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(page,app)=>{
  const profile=await(await fetch(app.origin+'/profile')).json();
  const saved=await fetch(app.origin+'/contacts',{method:'POST',headers:{'Content-Type':'application/json',Origin:app.origin},body:JSON.stringify({v:1,profile_id:profile.profile_id,boot_id:profile.boot_id,command_id:crypto.randomUUID(),record:{contact_id:crypto.randomUUID(),call:'K1ABC',gridsquare:null,mode:'FT8',submode:null,rst_sent:null,rst_rcvd:null,qso_date:'20261027',time_on:'115900',qso_date_off:'20261027',time_off:'120000',band:'20m',freq:null,station_callsign:'HB9BLA',my_gridsquare:'JN47AA',tx_pwr:null,comment:null}})});
  assert.equal(saved.status,201);
  view={v:1,profile_id:profile.profile_id,boot_id:profile.boot_id,revision:1,configuration:{continent:null,active:'Hover test',highlight:true,strategies:[strategy]},configuration_error:null,my_continent:'EU',derived_continent:'EU'};
  state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
  state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
  Object.assign(state.job,{first_sequence:0,next_sequence:n,available_count:n,latest_decode:{id:1,first_sequence:0,next_sequence:n,period_start_utc:period,complete:true}});
  await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
  await page.route('**/receive/selection',async route=>{const s=await(await route.fetch()).json();s.selection={...s.selection,band:'20m',nominal_hz:14074000,origin:'manual'};await route.fulfill({json:s});});
  await page.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor'));const batch=records.slice(cursor),next=cursor+batch.length;await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:n,available_count:n,next,more:false,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
  await page.route('**/strategy',route=>route.fulfill({json:view}));
  // The strategy hits the 73 from W2CD (no flag): value 2, under the row to my call.
  await page.route('**/strategy/evaluate',route=>route.fulfill({json:{v:1,profile_id:view.profile_id,boot_id:view.boot_id,strategy:'Hover test',my_continent:'EU',sort:'strongest',verdicts:[{sequence:8,rank:0,grey:false}]}}));
 }});
 await page.waitForFunction(()=>document.querySelector('tr[data-sequence="0"][data-worked]')&&document.querySelector('tr.ba-strategy'),null,{timeout:25000});
 const shown=()=>page.locator('#band-activity tr[data-sequence]').evaluateAll(rows=>rows.map(r=>[r.children[4].textContent,r.title,getComputedStyle(r.children[4]).backgroundColor,r.getAttribute('aria-description')]));
 const none='rgba(0, 0, 0, 0)';
 const expected=[
  ['HB9BLA W1XYZ -12','Calling me\nNew call\nNew call on 20m','rgba(255, 102, 102, 0.32)'],
  ['W9AA W2CD 73','Strategy Hover test: rule 1',none],
  ['K9XX YO3ABC -07','New DXCC: Romania\nNew DXCC on 20m\nNew call\nNew call on 20m','rgba(255, 0, 255, 0.26)'],
  ['CQ JA1AAA PM95','New CQ zone 25\nNew CQ zone on 20m','rgba(255, 191, 0, 0.26)'],
  ['CQ G4XYZ IO91','New grid IO91\nNew grid on 20m',none],
  ['K1ZZ W3EF RR73','New call\nNew call on 20m','rgba(0, 255, 255, 0.24)'],
  ['K9XX W2AB R-05','New call\nNew call on 20m','rgba(0, 255, 255, 0.24)'],
  ['FREE TEXT','',none],
  ['CQ K1ABC FN42','Worked before on 20m FT8',none],
 ];
 const got=await shown();
 assert.deepEqual(got.map(r=>r.slice(0,3)),expected,'value order, equal values strongest first; a report from a new DXCC is coloured; no flag, no colour');
 assert.deepEqual(got.map(r=>r[3]),expected.map(r=>r[1]?r[1].replaceAll('\n','; '):null),'the same reasons for assistive technology');
 assert.equal(await page.locator('#band-activity th[data-sort=value]').textContent(),'DXCC');
 assert.deepEqual(await sortState(page),['value','desc']);
 await page.screenshot({path:'test-results/ui-operating/band-activity-value-1440.png'});
 // New call (on by default, #50) and an enabled New grid colour the non-CQ senders as well (operator decision, not WSJT-X).
 await page.locator('#open-server-settings').click();await page.locator('#band-colours [data-hl-slot=new_grid]').check();await page.locator('#settings-drawer .return-operate').click();
 assert.deepEqual((await shown()).map(r=>r[2]),['rgba(255, 102, 102, 0.32)',none,'rgba(255, 0, 255, 0.26)','rgba(255, 191, 0, 0.26)','rgba(255, 128, 0, 0.26)','rgba(0, 255, 255, 0.24)','rgba(0, 255, 255, 0.24)',none,none]);
 await page.screenshot({path:'test-results/ui-operating/band-activity-colours-all-senders-1440.png'});
 await clickSort(page,'frequency');assert.deepEqual(await sortState(page),['frequency','asc']);
 assert.deepEqual((await shown()).map(r=>r[0]),[...rows].reverse().map(r=>r[0]),'a column header still sorts by its column');
 await clickSort(page,'value');assert.deepEqual(await sortState(page),['value','desc']);
 assert.deepEqual((await shown()).map(r=>r[0]),expected.map(r=>r[0]),'the DXCC header returns to the value order');
 assert.deepEqual(errors,[]);
});

// Proves: CL-055-05; TC-055-007. Band Activity row density at 1366x768: the result records
// are presentation fixtures; the layout is the actual client.
test('TC-055-007 Band Activity rows are dense and keep the font size',{timeout:30000},async t=>{
 const period='2026-10-27T12:00:15.0000000Z',n=30;
 const records=Array.from({length:n},(_,i)=>{const call=`K${i%10}A${String.fromCharCode(65+i%26)}${String.fromCharCode(65+(i*7)%26)}`;return {sequence:i,start_frame:186000+i,frequency_hz:300+i*90,snr_db:-20+i%15,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text:`CQ ${call} FN42`,fields:{type:'standard',to:{kind:'token',text:'CQ',hash_bits:null,hash_value:null},from:{kind:'call',text:call,hash_bits:null,hash_value:null},ack:false,exchange:{kind:'grid',value:'FN42'}},period_start_utc:period,dt_seconds:0.1};});
 let state;
 const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(page,app)=>{
  state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
  state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
  Object.assign(state.job,{first_sequence:0,next_sequence:n,available_count:n,latest_decode:{id:1,first_sequence:0,next_sequence:n,period_start_utc:period,complete:true}});
  await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
  await page.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor'));const batch=records.slice(cursor,cursor+16),next=cursor+batch.length;await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:n,available_count:n,next,more:next<n,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
 }});
 await page.waitForFunction(n=>document.querySelectorAll('#band-activity tr[data-sequence]').length===n,n,{timeout:25000});
 const measure=()=>page.evaluate(()=>{const wrap=document.querySelector('#band-activity .op-table-wrap').getBoundingClientRect(),rows=[...document.querySelectorAll('#band-activity tr[data-sequence]')],td=rows[0].children[4];
  return {height:rows[0].getBoundingClientRect().height,visible:rows.filter(r=>{const b=r.getBoundingClientRect();return b.top>=wrap.top&&b.bottom<=wrap.bottom;}).length,font:getComputedStyle(td).fontSize};});
 await page.screenshot({path:'test-results/ui-operating/band-activity-density-1366.png'});
 const dense=await measure();
 t.diagnostic(`row ${dense.height}px, ${dense.visible} rows visible, font ${dense.font}`);
 assert.ok(dense.height<=24,`a desktop row is at most 24 px high (${dense.height})`);
 assert.equal(dense.font,'16px','the font size is unchanged (the 16 px operating font, TC-007-002)');
 assert.ok(dense.visible>=8,`at least 8 rows visible at 1366x768, 5 before #55 (${dense.visible})`);
 // Touch: a coarse pointer keeps taller rows (CSS rule under pointer:coarse).
 assert.ok(await page.evaluate(()=>[...document.styleSheets].some(sheet=>{try{return [...sheet.cssRules].some(r=>r.media&&/pointer:\s*coarse/.test(r.media.mediaText)&&[...r.cssRules].some(c=>c.selectorText==='#band-activity td'&&parseFloat(c.style.paddingTop)>=8));}catch{return false;}})),'a coarse pointer keeps tappable rows');
 assert.deepEqual(errors,[]);
});

// Proves: CL-050-02; TC-050-002 (b). Operator 2026-11-03: only interesting stations are coloured. The
// /contact/worked statuses and receive pages (with the #55 flags a station derives from its log,
// CL-055-04) are routed fixtures; the colours are the served client's CSS.
test('TC-050-002 a CQ from a station worked on this band and mode has no colour; My call still applies',{timeout:30000},async t=>{
 let state;const queries=[];
 const period='2026-10-27T12:00:15.0000000Z';
 const call=text=>({kind:'call',text,hash_bits:null,hash_value:null});
 const cq=from=>({type:'standard',to:{kind:'token',text:'CQ',hash_bits:null,hash_value:null},from:call(from),ack:false,exchange:{kind:'grid',value:'FN42'}});
 const rows=[['CQ K1AA FN42',cq('K1AA'),null],['CQ K2BB FN42',cq('K2BB'),{new_call_band:true}],['CQ K3CC FN42',cq('K3CC'),{new_call:true,new_call_band:true}],['HB9BLA K1AA R-05',{type:'standard',to:call('HB9BLA'),from:call('K1AA'),ack:false,exchange:{kind:'report',value:-5}},null]];
 const records=rows.map(([text,fields,flags],i)=>({sequence:i,start_frame:186000+i,frequency_hz:1000+i*100,snr_db:-10,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text,fields,period_start_utc:period,dt_seconds:0.1,...(flags?{flags}:{})}));
 const statuses={K1AA:'worked_this_band_and_mode',K2BB:'worked_other_band_or_mode',K3CC:'not_worked'};
 const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(page,app)=>{
  state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
  state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
  Object.assign(state.job,{first_sequence:0,next_sequence:4,available_count:4,latest_decode:{id:1,first_sequence:0,next_sequence:4,period_start_utc:period,complete:true}});
  await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
  await page.route('**/receive/selection',async route=>{const s=await(await route.fetch()).json();s.selection={...s.selection,band:'20m',nominal_hz:14074000,origin:'manual'};await route.fulfill({json:s});});
  await page.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor'));const batch=records.slice(cursor),next=cursor+batch.length;await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:4,available_count:4,next,more:false,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
  await page.route('**/contact/worked',async route=>{const q=JSON.parse(route.request().postData());queries.push(q);await route.fulfill({json:{v:1,statuses:q.calls.map(c=>({call:c,status:statuses[c]}))}});});
 }});
 await page.locator('tr[data-result-id][data-worked]').first().waitFor();
 const seen=await page.locator('tr[data-result-id]').evaluateAll(rows=>rows.map(r=>[r.children[4].textContent,r.dataset.worked??null,r.dataset.hl??null,getComputedStyle(r.children[4]).backgroundColor]));
 assert.deepEqual(seen,[
  ['HB9BLA K1AA R-05','worked_this_band_and_mode','mycall','rgba(255, 102, 102, 0.32)'],
  ['CQ K2BB FN42','worked_other_band_or_mode','new_call_band','rgba(153, 255, 255, 0.2)'],
  ['CQ K3CC FN42','not_worked','new_call new_call_band','rgba(0, 255, 255, 0.24)'],
  ['CQ K1AA FN42','worked_this_band_and_mode',null,'rgba(0, 0, 0, 0)']],'only interesting stations are coloured; My call still applies; rows in value order (#55)');
 assert.deepEqual(queries.map(q=>q.calls),[['K1AA','K2BB','K3CC']]);
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
// Proves: CL-043-01, CL-009-05; TC-043-003. Settings > General > Clock reads GET /clock only
// when Settings opens, saves the clock source with one exact POST, shows the air estimate
// (offset, stations used, confidence, age), and the clock chips appear only when transmit is
// not synchronized or NTP and air disagree.
test('TC-043-003 the clock source and the clock from the air are shown in Settings and as chips',{timeout:60000},async t=>{
  let view;
  const {page,app,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    view=await (await fetch(app.origin+'/transmit')).json();
    await p.route('**/transmit',route=>route.request().method()==='GET'?route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(view)}):route.continue());
  }});
  const requests=[],posts=[];
  page.on('request',r=>{const p=new URL(r.url()).pathname;requests.push(`${r.method()} ${p}`);if(r.method()==='POST'&&p==='/clock')posts.push(JSON.parse(r.postData()));});
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});await page.waitForTimeout(500);
  assert.equal(requests.some(r=>r.endsWith(' /clock')),false,'no /clock request before Settings opens');
  const initial=await (await fetch(app.origin+'/clock')).json();
  assert.equal(initial.source,'ntp','the default source');
  await page.locator('#open-server-settings').click();await page.locator('#tab-general').click();
  await page.locator('#clock-source:enabled').waitFor();
  assert.equal(await page.locator('#settings-general #settings-clock #clock-source').count(),1,'in Settings > General > Clock');
  assert.equal(await page.locator('#clock-source').inputValue(),'ntp');
  assert.match(await page.locator('#clock-air').textContent(),/^Clock unknown by NTP · from the air: too few stations heard$/);
  await page.locator('#clock-source').selectOption('air');await page.locator('#clock-result').filter({hasText:'Saved'}).waitFor();
  assert.deepEqual(posts,[{v:1,profile_id:initial.profile_id,boot_id:initial.boot_id,source:'air'}],'exactly one exact-key save');
  assert.equal((await (await fetch(app.origin+'/clock')).json()).source,'air','the station stored it');
  const estimate={...initial,source:'air',state:'synchronized',basis:'air',correction_ms:-1980,air:{state:'synchronized',applied_ms:-1980,estimate:{offset_ms:-1985,stations:12,heard:14,confidence_pct:85,age_ms:3400}},disagreement_ms:null,warning:null};
  await page.route('**/clock',route=>route.request().method()==='GET'?route.fulfill({json:estimate}):route.continue());
  await page.locator('#tab-general').click();
  await page.locator('#clock-air').filter({hasText:'12 of 14'}).waitFor();
  assert.equal(await page.locator('#clock-air').textContent(),'Clock synchronized by the air, correction -1980 ms · from the air: -1985 ms, 12 of 14 stations (85 %), 3 s ago, synchronized');
  Object.assign(estimate,{source:'both',basis:'ntp',correction_ms:0,disagreement_ms:340,warning:'ntp_air_disagree'});await page.locator('#tab-general').click();
  await page.locator('#clock-air').filter({hasText:'disagree'}).waitFor();
  assert.match(await page.locator('#clock-air').textContent(),/^Clock synchronized by NTP · from the air: .* · NTP and air disagree by 340 ms$/);
  await page.route('**/clock',route=>route.request().method()==='POST'?route.fulfill({status:409,json:{error:{code:'state_conflict'}}}):route.fallback());
  await page.locator('#clock-source').selectOption('ntp');await page.locator('#clock-result').filter({hasText:'Not saved'}).waitFor();
  assert.match(await page.locator('#clock-result').textContent(),/state_conflict/);
  assert.equal(await page.locator('#clock-source').inputValue(),'both','a refusal restores the shown source');
  await page.locator('#settings-drawer .return-operate').click();
  // Chips from the GET /transmit view (CAT PTT set in the page only).
  const chips=async next=>{view={...view,...next};return page.evaluate(async()=>{profileData.settings.control.ptt='cat';await transmitSync();window.wstxChipsShow();return [...document.querySelectorAll('#exception-chips [data-chip^=clock]')].map(b=>b.textContent);});};
  assert.deepEqual(await chips({clock:'unknown',clock_source:'air',clock_warning:null}),['✖ Clock unknown · Tx blocked'],'air without enough stations refuses transmit');
  assert.match(await page.locator('#clock-setting').textContent(),/^Station clock: system UTC corrected from the air, unknown/);
  assert.deepEqual(await chips({clock:'unknown',clock_source:'ntp'}),[],'NTP unknown keeps no chip, as before');
  assert.deepEqual(await chips({clock:'synchronized',clock_source:'air'}),[],'synchronized: no chip');
  assert.deepEqual(await chips({clock:'synchronized',clock_source:'both',clock_warning:'ntp_air_disagree'}),['⚠ NTP and air clock disagree']);
  assert.deepEqual(await chips({clock:'unsynchronized',clock_source:'both',clock_warning:null}),['✖ Clock off · Tx blocked']);
  assert.equal(posts.length,2,'one save plus the refused one');
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
  assert.match(await page.locator('#op-confirm-text').textContent(),/Auto transmits without asking: it answers only stations that match "DX first" \(Auto Call and Auto CQ, switching after 3 tries\)\. The Tx watchdog stops it after 6 unanswered calls; Auto never resets it\. HALT or Esc stops it\./);
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
  assert.equal(await page.locator('#continent-derived').textContent(),'From callsign: EU');
  const saved=page.waitForResponse(r=>r.url().endsWith('/strategy')&&r.request().method()==='PUT');
  await page.selectOption('#station-continent','AS');const reply=await (await saved).json();
  assert.deepEqual([reply.revision,reply.configuration.continent,reply.my_continent],[1,'AS','AS']);
  await page.locator('#continent-derived').filter({hasText:'using AS'}).waitFor();
  assert.equal(await page.evaluate(()=>Object.keys(localStorage).some(k=>k.startsWith('wstx.continent'))),false,'not browser-local any more');
  assert.deepEqual(errors,[]);
});
// Proves: CL-042-01; TC-042-001 the editor offers the four entity New conditions, each
// with ever / on this band and mode, and the actual isolated station accepts and keeps
// the saved draft. The expected labels and conditions are written here.
test('TC-042-001 Editor offers new DXCC, continent, CQ zone and ITU zone and the station saves them',{timeout:40000},async t=>{
  const {page,errors}=await fixture(t,{width:1366,height:768});
  await page.waitForFunction(()=>document.querySelector('#strategy-edit')?.disabled===false,null,{timeout:25000});
  await page.locator('#strategy-edit').click();await page.locator('#strategy-editor[open]').waitFor();
  const kinds=[['new_dxcc','New DXCC'],['new_continent','New continent'],['new_cq_zone','New CQ zone'],['new_itu_zone','New ITU zone']];
  for(const [i,[kind]] of kinds.entries()){
    await page.locator('#strategy-editor [data-act=add-condition][data-rule="0"]').click();
    await page.locator('.se-condition').nth(i+1).locator('[data-f=kind]').selectOption(kind);
  }
  const offered=await page.locator('.se-condition').nth(1).locator('[data-f=kind] option').evaluateAll(o=>o.map(x=>[x.value,x.textContent]));
  for(const k of kinds)assert.ok(offered.some(o=>o[0]===k[0]&&o[1]===k[1]),`${k[0]} offered as ${k[1]}`);
  for(let i=1;i<=4;i++)assert.deepEqual(await page.locator('.se-condition').nth(i).locator('[data-f=value] option').evaluateAll(o=>o.map(x=>[x.value,x.textContent])),[['ever','ever'],['band','on this band and mode']]);
  await page.locator('.se-condition').nth(1).locator('[data-f=value]').selectOption('band');
  await page.locator('.se-condition').nth(4).locator('[data-f=negate]').check();
  const saved=page.waitForResponse(r=>r.url().endsWith('/strategy')&&r.request().method()==='PUT');
  await page.locator('#se-save').click();const reply=await (await saved).json();
  assert.deepEqual([reply.revision,reply.configuration.strategies[0].rules[0].conditions],[1,[{kind:'message',negate:false,value:'cq'},{kind:'new_dxcc',negate:false,value:'band'},{kind:'new_continent',negate:false,value:'ever'},{kind:'new_cq_zone',negate:false,value:'ever'},{kind:'new_itu_zone',negate:true,value:'ever'}]]);
  await page.locator('#se-result').filter({hasText:'Saved'}).waitFor();
  assert.deepEqual(errors,[]);
});
// Proves: CL-042-02; TC-042-003 Band Activity right-click Ignore / Stop ignoring and the
// Settings > General ignore lists send exactly the requests written here; the station
// replies (snapshots, verdicts) are hand-written fixtures; the row loses its Highlight
// mark only through the station's new verdicts.
test('TC-042-003 Band Activity Ignore and the Settings ignore lists',{timeout:60000},async t=>{
  let state,view;const puts=[],ignores=[],evaluations=[],commands=[];let session=[];
  const period='2026-10-27T12:00:00.0000000Z';
  const standard=(from,to='CQ',grid='FN42')=>({type:'standard',to:{kind:to.startsWith('CQ')?'token':'call',text:to,hash_bits:null,hash_value:null},from:{kind:'call',text:from,hash_bits:null,hash_value:null},ack:false,exchange:{kind:'grid',value:grid}});
  const record=(sequence,text,from,hz,to,grid)=>({sequence,start_frame:6000,frequency_hz:hz,snr_db:-10,dt_seconds:0.1,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text,fields:standard(from,to,grid),period_start_utc:period});
  const records=[record(0,'CQ K1ABC FN42','K1ABC',1000,'CQ','FN42'),record(1,'CQ DL1XYZ JO62','DL1XYZ',1400,'CQ','JO62')];
  const strategy={name:'CQ',rules:[{conditions:[{kind:'message',negate:false,value:'cq'}]}],sort:'strongest',treat_73_as_cq:false,apply_to_callers:false,skip_after:5,auto_role:'call',switch_after:3};
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    view={v:1,profile_id:base.profile_id,boot_id:base.boot_id,revision:2,configuration:{continent:null,active:'CQ',highlight:true,strategies:[strategy],ignore_calls:[],session_ignore_minutes:30},configuration_error:null,my_continent:'EU',derived_continent:'EU',session_ignore:[]};
    state=liveFixture(await (await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:period,canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    Object.assign(state.job,{first_sequence:0,next_sequence:2,available_count:2,latest_decode:{id:1,first_sequence:0,next_sequence:2,period_start_utc:period,complete:true}});
    await p.route('**/receive',async route=>{await p.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await p.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor')),batch=records.slice(cursor);await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:2,available_count:2,next:cursor+batch.length,more:false,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base)}));
    await contactCommands(p,commands);
    await p.route('**/strategy',async route=>{if(route.request().method()==='PUT'){const b=JSON.parse(route.request().postData());puts.push(b);view={...view,revision:view.revision+1,configuration:b.configuration};}await route.fulfill({json:{...view,session_ignore:session}});});
    await p.route('**/strategy/ignore',async route=>{const b=JSON.parse(route.request().postData());ignores.push(b);
      session=b.ignore?[...session.filter(e=>e.call!==b.call),{call:b.call,band:'40m',remaining_s:1800}]:session.filter(e=>e.call!==b.call);
      await route.fulfill({json:{...view,session_ignore:session}});});
    await p.route('**/strategy/evaluate',async route=>{const b=JSON.parse(route.request().postData());evaluations.push(b);
      const ignored=session.some(e=>e.call==='K1ABC');
      await route.fulfill({json:{v:1,profile_id:view.profile_id,boot_id:view.boot_id,strategy:'CQ',my_continent:'EU',sort:'strongest',verdicts:ignored?[{sequence:1,rank:0,grey:false}]:[{sequence:0,rank:0,grey:false},{sequence:1,rank:0,grey:false}]}});});
  }});
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest].ba-strategy').length===2,null,{timeout:25000});
  const row=page.locator('#band-activity tr[data-sequence="0"]');
  const items=()=>page.locator('#ba-menu button:not([hidden])').evaluateAll(b=>b.map(x=>x.textContent));
  await row.click({button:'right'});await page.locator('#ba-menu:not([hidden])').waitFor();
  assert.deepEqual(await items(),['Reply','Select','Set Rx here','Pounce K1ABC','Ignore K1ABC']);
  const n=evaluations.length;
  await page.locator('#ba-menu [data-menu=ignore]').click();
  for(let i=0;i<60&&!ignores.length;i++)await page.waitForTimeout(50);
  assert.deepEqual(ignores,[{v:1,profile_id:view.profile_id,boot_id:view.boot_id,call:'K1ABC',ignore:true}]);
  await page.waitForFunction(()=>!document.querySelector('#band-activity tr[data-sequence="0"]').classList.contains('ba-strategy'),null,{timeout:10000});
  assert.ok(evaluations.length>n,'the shown rows are evaluated again');
  assert.equal(commands.some(c=>c.action==='set_frequency'),false,'Ignore never sets the Rx frequency');
  await row.click({button:'right'});await page.locator('#ba-menu:not([hidden])').waitFor();
  assert.deepEqual(await items(),['Reply','Select','Set Rx here','Pounce K1ABC','Stop ignoring K1ABC']);
  await page.keyboard.press('Escape');
  // Settings > General: the session list with remaining minutes, the permanent list, minutes.
  await page.locator('#open-server-settings').click();await page.locator('#tab-general').click();
  await page.locator('#ignore-session li').first().waitFor();
  assert.deepEqual(await page.locator('#ignore-session li').evaluateAll(l=>l.map(x=>[x.querySelector('.ig-call').textContent,x.querySelector('.ig-left').textContent])),[['K1ABC','30 min']]);
  // One change: leaving the field is the change (a dispatched change plus the blur would be two);
  // the saved list is shown once the station's answer is applied, before the next field (#61 gate race).
  await page.fill('#ignore-calls','dl1xyz, w1aw');await page.locator('#ignore-calls').blur();
  await page.waitForFunction(()=>document.querySelector('#ignore-calls').value==='DL1XYZ W1AW');
  for(let i=0;i<60&&!puts.length;i++)await page.waitForTimeout(50);
  assert.deepEqual(puts.map(b=>[b.expected_revision,b.configuration]),[[2,{continent:null,active:'CQ',highlight:true,strategies:[strategy],ignore_calls:['DL1XYZ','W1AW'],session_ignore_minutes:30}]]);
  await page.fill('#ignore-minutes','45');await page.locator('#ignore-minutes').dispatchEvent('change');
  for(let i=0;i<60&&puts.length<2;i++)await page.waitForTimeout(50);
  assert.deepEqual([puts[1].expected_revision,puts[1].configuration.ignore_calls,puts[1].configuration.session_ignore_minutes],[3,['DL1XYZ','W1AW'],45]);
  await page.locator('#ignore-session button[aria-label="Stop ignoring K1ABC"]').click();
  for(let i=0;i<60&&ignores.length<2;i++)await page.waitForTimeout(50);
  assert.deepEqual(ignores[1],{v:1,profile_id:view.profile_id,boot_id:view.boot_id,call:'K1ABC',ignore:false});
  await page.waitForFunction(()=>!document.querySelector('#ignore-session li'));
  assert.deepEqual(errors,[]);
});
// Proves: CL-042-03; TC-042-005 Band Activity Pounce sends exactly the automation requests
// written here (the station's automation replies are hand-written fixtures); the browser
// never arms for the pounce; the QSO pane and the strategy element show the running pounce.
test('TC-042-005 Band Activity Pounce and the pounce line in the QSO pane',{timeout:60000},async t=>{
  let state,view,automation={run:null,policy:0,runRevision:0,configuration:null};const autos=[],commands=[];
  const period='2026-10-27T12:00:00.0000000Z';
  const standard=(from,to='CQ',grid='FN42')=>({type:'standard',to:{kind:to.startsWith('CQ')?'token':'call',text:to,hash_bits:null,hash_value:null},from:{kind:'call',text:from,hash_bits:null,hash_value:null},ack:false,exchange:{kind:'grid',value:grid}});
  const record=(sequence,text,from,hz,to,grid)=>({sequence,start_frame:6000,frequency_hz:hz,snr_db:-10,dt_seconds:0.1,payload77:'0'.repeat(77),i3:1,n3:null,status:'decoded',text,fields:standard(from,to,grid),period_start_utc:period});
  const records=[record(0,'CQ K1ABC FN42','K1ABC',1000,'CQ','FN42'),record(1,'CQ DL1XYZ JO62','DL1XYZ',1400,'CQ','JO62')];
  const strategy={name:'CQ',rules:[{conditions:[{kind:'message',negate:false,value:'cq'}]}],sort:'strongest',treat_73_as_cq:false,apply_to_callers:false,skip_after:5,auto_role:'call',switch_after:3};
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    view={v:1,profile_id:base.profile_id,boot_id:base.boot_id,revision:2,configuration:{continent:null,active:'CQ',highlight:false,strategies:[strategy],ignore_calls:[],session_ignore_minutes:30},configuration_error:null,my_continent:'EU',derived_continent:'EU',session_ignore:[]};
    state=liveFixture(await (await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:period,canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    Object.assign(state.job,{first_sequence:0,next_sequence:2,available_count:2,latest_decode:{id:1,first_sequence:0,next_sequence:2,period_start_utc:period,complete:true}});
    await p.route('**/receive',async route=>{await p.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await p.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor')),batch=records.slice(cursor);await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:2,available_count:2,next:cursor+batch.length,more:false,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base)}));
    await contactCommands(p,commands);
    await p.route('**/strategy',route=>route.fulfill({json:view}));
    await p.route('**/automation',route=>route.fulfill({json:{v:1,profile_id:view.profile_id,boot_id:view.boot_id,policy_revision:automation.policy,run_revision:automation.runRevision,configuration:automation.configuration,run:automation.run}}));
    await p.route('**/automation/command',async route=>{const b=JSON.parse(route.request().postData());autos.push(b);
      if(b.action==='configure'){automation.policy++;automation.configuration={...b.configuration};}
      if(b.action==='start'){automation.runRevision++;automation.run={id:crypto.randomUUID(),state:'waiting',reason:null,mode:'ft8',completed_contacts:0,unanswered_periods:0,contact_id:null,selected:null,last_decision:null,role:null,tries:0,skipped:[],pounce:{call:automation.configuration.pounce,band:'40m'}};}
      if(b.action==='stop'){automation.runRevision++;automation.run={...automation.run,state:'stopped',reason:'stopped'};}
      await route.fulfill({status:202,json:{v:1,accepted:true}});});
  }});
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===2&&document.querySelector('#strategy-auto')?.disabled===false,null,{timeout:25000});
  const row=page.locator('#band-activity tr[data-sequence="0"]');
  const items=()=>page.locator('#ba-menu button:not([hidden])').evaluateAll(b=>b.map(x=>x.textContent));
  await row.click({button:'right'});await page.locator('#ba-menu:not([hidden])').waitFor();
  assert.deepEqual(await items(),['Reply','Select','Set Rx here','Pounce K1ABC','Ignore K1ABC']);
  await page.locator('#ba-menu [data-menu=pounce]').click();await page.locator('#op-confirm[open]').waitFor();
  assert.match(await page.locator('#op-confirm-text').textContent(),/^Pounce transmits without asking: it answers K1ABC when it calls CQ or ends a QSO with 73 on this band\. The Tx watchdog stops it after 6 unanswered calls; automation never resets it\. HALT or Esc stops it\.$/);
  await page.locator('#op-confirm-ok').click();
  for(let i=0;i<60&&autos.length<2;i++)await page.waitForTimeout(50);
  assert.deepEqual(autos.map(b=>[b.action,b.expected_policy_revision,b.expected_run_revision,b.mode,b.safety_revision]),[['configure',0,undefined,undefined,undefined],['start',1,0,'ft8',7]]);
  assert.deepEqual(autos[0].configuration,{modes:['ft8'],ranking:'first_seen',min_snr_db:null,allowed_calls:[],blocked_calls:[],max_contacts:1,max_unanswered_periods:5,completion_action:'stop',max_run_minutes:480,strategy:false,pounce:'K1ABC'});
  await page.evaluate(()=>dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'automation.state',data:{policy_revision:1,run_revision:1}}}})));
  await page.locator('#qso-pounce:not([hidden])').waitFor();
  assert.equal(await page.locator('#qso-pounce-text').textContent(),'Pouncing on K1ABC (40m) · waiting for CQ or 73');
  assert.match(await page.locator('#station-automation').textContent(),/^Pounce K1ABC waiting · HALT ends it$/);
  assert.equal(await page.locator('#strategy-auto').isDisabled(),true,'no Auto beside the pounce');
  assert.equal(await page.locator('#qso-pounce').evaluate(n=>{const r=n.getBoundingClientRect();return r.bottom<=innerHeight&&r.right<=innerWidth&&n.scrollWidth<=n.clientWidth+1;}),true,'the pounce line is not clipped at 1366x768');
  await page.screenshot({path:'test-results/ui-operating/pounce-1366.png'});
  await row.click({button:'right'});await page.locator('#ba-menu:not([hidden])').waitFor();
  assert.deepEqual(await items(),['Reply','Select','Set Rx here','Stop pouncing K1ABC','Ignore K1ABC']);
  await page.keyboard.press('Escape');
  await page.locator('#qso-pounce-stop').click();
  for(let i=0;i<60&&autos.length<3;i++)await page.waitForTimeout(50);
  assert.deepEqual([autos[2].action,autos[2].run_id],['stop',automation.run.id]);
  await page.evaluate(()=>dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'automation.state',data:{policy_revision:1,run_revision:2}}}})));
  await page.locator('#qso-pounce[hidden]').waitFor({state:'attached'});
  assert.equal(commands.some(c=>c.action==='enable_tx'||c.action==='select_row'),false,'the station run answers; the browser never arms for it');
  assert.deepEqual(errors,[]);
});
// Proves: CL-042-04; TC-042-007 the editor's per-rule Alert checkbox, the Settings > General
// alert history, Sound and Browser notification (off by default; permission asked only on
// the click). The station's alert snapshots are hand-written fixtures; the page's
// Notification and AudioContext are recording doubles; the expected lines, tones and
// notifications are written here from WstxStrategy::Alert.
test('TC-042-007 Alert checkbox, alert history, sound and browser notification',{timeout:60000},async t=>{
  let view;const puts=[],clears=[];let history=[],revision=1;
  const strategy={name:'CQ',rules:[{conditions:[{kind:'message',negate:false,value:'cq'}]}],sort:'strongest',treat_73_as_cq:false,apply_to_callers:false,skip_after:5,auto_role:'call',switch_after:3};
  const alert=(id,call,message,snr,dxcc)=>({id,utc:'2026-10-27T12:00:00.0000000Z',call,message,rule:'CQ rule 1',band:'40m',mode:'ft8',snr_db:snr,dxcc});
  history=[alert(1,'K1ABC','CQ K1ABC FN42',-12,'United States')];
  const doubles=()=>{
    window.__tones=0;window.__notes=[];window.__asks=0;window.__hidden=false;
    class FakeNotification{constructor(title,options){window.__notes.push({title,body:options?.body});}
      static get permission(){return sessionStorage.getItem('fake-permission')??'default';}
      static async requestPermission(){window.__asks++;sessionStorage.setItem('fake-permission','granted');return 'granted';}}
    window.Notification=FakeNotification;
    const param=()=>({value:0,setValueAtTime(){},linearRampToValueAtTime(){},exponentialRampToValueAtTime(){}});
    window.AudioContext=class{constructor(){this.currentTime=0;this.destination={};this.state='running';}
      createOscillator(){return {frequency:param(),type:'sine',connect(){return this;},start(){window.__tones++;},stop(){}};}
      createGain(){return {gain:param(),connect(){return this;}};}resume(){return Promise.resolve();}};
    Object.defineProperty(document,'visibilityState',{configurable:true,get:()=>window.__hidden?'hidden':'visible'});
    Object.defineProperty(document,'hidden',{configurable:true,get:()=>window.__hidden});
  };
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    view={v:1,profile_id:base.profile_id,boot_id:base.boot_id,revision:2,configuration:{continent:null,active:'CQ',highlight:false,strategies:[strategy],ignore_calls:[],session_ignore_minutes:30},configuration_error:null,my_continent:'EU',derived_continent:'EU',session_ignore:[]};
    await p.addInitScript(doubles);
    await p.route('**/strategy',async route=>{if(route.request().method()==='PUT'){const b=JSON.parse(route.request().postData());puts.push(b);view={...view,revision:view.revision+1,configuration:b.configuration};}await route.fulfill({json:view});});
    await p.route('**/strategy/alerts',route=>route.fulfill({json:{v:1,profile_id:view.profile_id,boot_id:view.boot_id,revision,alerts:history}}));
    await p.route('**/strategy/alerts/clear',async route=>{clears.push(JSON.parse(route.request().postData()));history=[];revision++;
      await route.fulfill({json:{v:1,profile_id:view.profile_id,boot_id:view.boot_id,revision,alerts:[]}});});
  }});
  const announce=async(next)=>{history.push(next);revision++;
    await page.evaluate(r=>dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'alert.state',data:{profile_id:'p',boot_id:'b',alert_revision:r}}}})),revision);
    await page.waitForFunction(n=>document.querySelectorAll('#alert-history li').length===n,history.length,{timeout:10000});};
  const counters=()=>page.evaluate(()=>({tones:window.__tones,notes:window.__notes,asks:window.__asks}));
  // The editor: rule 1 marked Alert is saved with alert true.
  await page.waitForFunction(()=>document.querySelector('#strategy-edit')?.disabled===false,null,{timeout:25000});
  await page.locator('#strategy-edit').click();await page.locator('#strategy-editor[open]').waitFor();
  await page.locator('#strategy-editor [data-alert="0"]').check();
  await page.locator('#se-save').click();for(let i=0;i<60&&!puts.length;i++)await page.waitForTimeout(50);
  assert.deepEqual(puts[0].configuration.strategies[0].rules,[{conditions:[{kind:'message',negate:false,value:'cq'}],alert:true}]);
  await page.locator('#se-result').filter({hasText:'Saved'}).waitFor();
  await page.locator('#strategy-editor button[value=cancel]').click();
  // Settings > General: the history, both announcements off by default.
  await page.locator('#open-server-settings').click();await page.locator('#tab-general').click();
  await page.locator('#alert-history li').first().waitFor();
  const lines=()=>page.locator('#alert-history li .al-text').evaluateAll(l=>l.map(x=>x.textContent));
  assert.deepEqual(await lines(),['12:00:00 K1ABC CQ K1ABC FN42 · CQ rule 1 · 40m FT8 · -12 dB · United States']);
  assert.deepEqual([await page.locator('#alert-sound').isChecked(),await page.locator('#alert-notify').isChecked()],[false,false]);
  await announce(alert(2,'DL1XYZ','CQ DL1XYZ JO62',-3,'Fed. Rep. of Germany'));
  assert.deepEqual((await lines())[0],'12:00:00 DL1XYZ CQ DL1XYZ JO62 · CQ rule 1 · 40m FT8 · -3 dB · Fed. Rep. of Germany','newest first');
  assert.deepEqual(await counters(),{tones:0,notes:[],asks:0},'both off: nothing announced, no permission asked');
  await page.locator('#alert-sound').check();
  await announce(alert(3,'W1AW','CQ W1AW FN31',-5,'United States'));
  assert.deepEqual(await counters(),{tones:1,notes:[],asks:0});
  await page.locator('#alert-notify').check();
  for(let i=0;i<40&&(await counters()).asks<1;i++)await page.waitForTimeout(50);
  assert.equal(await page.locator('#alert-notify').isChecked(),true,'granted on the click');
  await announce(alert(4,'JA1XYZ','CQ JA1XYZ PM95',-15,'Japan'));
  for(let i=0;i<40&&!(await counters()).notes.length;i++)await page.waitForTimeout(50);
  assert.deepEqual(await counters(),{tones:2,notes:[{title:'Alert JA1XYZ',body:'CQ JA1XYZ PM95 · CQ rule 1'}],asks:1});
  // A hidden page plays no tone; the notification still shows.
  await page.evaluate(()=>{window.__hidden=true;});
  await announce(alert(5,'VK2ABC','CQ VK2ABC QF56',-20,'Australia'));
  for(let i=0;i<40&&(await counters()).notes.length<2;i++)await page.waitForTimeout(50);
  const c=await counters();assert.deepEqual([c.tones,c.notes.length,c.notes[1].title],[2,2,'Alert VK2ABC']);
  // A reload keeps both choices and announces nothing from the history.
  await page.reload();await page.locator('#connection[data-state=connected]').waitFor();
  await page.locator('#open-server-settings').click();await page.locator('#tab-general').click();
  await page.waitForFunction(()=>document.querySelectorAll('#alert-history li').length===5,null,{timeout:20000});
  assert.deepEqual([await page.locator('#alert-sound').isChecked(),await page.locator('#alert-notify').isChecked()],[true,true]);
  await page.waitForTimeout(300);
  assert.deepEqual(await counters(),{tones:0,notes:[],asks:0},'the history read at load announces nothing');
  await page.locator('#alert-clear').click();
  for(let i=0;i<60&&!clears.length;i++)await page.waitForTimeout(50);
  assert.deepEqual(clears,[{v:1,profile_id:view.profile_id,boot_id:view.boot_id}]);
  await page.waitForFunction(()=>!document.querySelector('#alert-history li'));
  assert.deepEqual(errors,[]);
});
// Proves: CL-055-03; TC-055-003 Settings > General shows the cty.dat in use (its date),
// uploads a replacement to the actual isolated station and returns to the bundled file;
// a file that is no cty.dat is refused with its line and changes nothing.
test('TC-055-003 Settings > General country file shows its date, uploads and restores',{timeout:40000},async t=>{
  const {page,errors}=await fixture(t,{width:1366,height:768});
  await page.locator('#open-server-settings').click();await page.locator('#tab-general').click();
  const status=page.locator('#cty-status');
  await status.filter({hasText:'cty.dat 2025-01-15 \u00b7 bundled with this station \u00b7 346 entities'}).waitFor({timeout:20000});
  assert.equal(await page.locator('#cty-bundled').isDisabled(),true);
  await page.locator('#cty-file').setInputFiles({name:'bad.dat',mimeType:'text/plain',buffer:Buffer.from('Nowhere: 1: 2: XX: 0: 0: 0: NW:\n NW;\n')});
  await page.locator('#cty-upload').click();
  await page.locator('#cty-result').filter({hasText:'Refused \u00b7 not a valid cty.dat (line 1); nothing changed'}).waitFor();
  await page.locator('#cty-file').setInputFiles({name:'cty.dat',mimeType:'text/plain',buffer:Buffer.from('Testland:  14:  28:  EU:  1.00:  -2.00:  -1.0:  TT:\n    TT,HB,=VER20991231;\n')});
  await page.locator('#cty-upload').click();
  await status.filter({hasText:'cty.dat 2099-12-31 \u00b7 uploaded \u00b7 1 entities'}).waitFor();
  assert.equal(await page.locator('#cty-result').textContent(),'Uploaded cty.dat');
  assert.equal((await page.evaluate(async()=>(await (await stationFetch('/dxcc?call=HB9BLA')).json()).entity.name)),'Testland');
  await page.locator('#cty-bundled').click();
  await status.filter({hasText:'cty.dat 2025-01-15 \u00b7 bundled with this station'}).waitFor();
  assert.deepEqual(errors,[]);
});

// Proves: CL-012-03; TC-020-004 MCP clients in Settings > General > Access & grants (#58):
// listed when Settings opens, a new token shown once and cleared, revoke after confirmation.
test('TC-020-004 Settings lists MCP clients, shows a new token once and revokes after confirmation',{timeout:60000},async t=>{
  const {page,errors}=await fixture(t,{width:1366,height:768});
  const posts=[],token='wstx_mcp_'+'A'.repeat(43);
  let clients=[{client_id:'00000000-0000-4000-8000-000000000001',name:'Claude <Code>',created_utc_ms:Date.UTC(2026,10,2,8,0),last_used_utc_ms:null}];
  const listing=()=>({version:1,max_clients:8,clients,recent:[{utc_ms:Date.UTC(2026,10,2,8,5),client_id:clients[0]?.client_id,name:'Claude <Code>',action:'tools/call wstx_read contact',status:200}]});
  await page.route('**/authorization/v1/mcp-clients**',route=>{
    const p=new URL(route.request().url()).pathname,body=route.request().method()==='GET'?null:JSON.parse(route.request().postData());posts.push([route.request().method()+' '+p,body]);
    if(p.endsWith('/create')){clients=[...clients,{client_id:'00000000-0000-4000-8000-000000000002',name:body.name,created_utc_ms:Date.UTC(2026,10,2,9,0),last_used_utc_ms:null}];return route.fulfill({json:{version:1,client_id:'00000000-0000-4000-8000-000000000002',name:body.name,created_utc_ms:Date.UTC(2026,10,2,9,0),token}});}
    if(p.endsWith('/revoke'))clients=clients.filter(c=>c.client_id!==body.client_id);
    return route.fulfill({json:listing()});
  });
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});await page.waitForTimeout(300);
  assert.deepEqual(posts,[],'nothing is read before Settings opens');
  await page.locator('#open-server-settings').click();
  const items=page.locator('#mcp-clients li');await items.first().waitFor();
  assert.equal(await page.locator('#settings-general #settings-browsers #mcp-clients').count(),1,'in Settings > General > Access & grants');
  assert.match(await items.first().textContent(),/^Claude <Code> · created 2026-11-02 08:00 UTC · last used never/,'the name is text, not markup');
  assert.match(await page.locator('#mcp-recent li').first().textContent(),/2026-11-02 08:05 UTC · Claude <Code> · tools\/call wstx_read contact · 200/);
  await page.locator('#mcp-name').fill('Codex');await page.locator('#mcp-create').click();
  await page.locator('#mcp-token:not([hidden])').waitFor();
  assert.equal(await page.locator('#mcp-token-value').textContent(),token,'the new token is shown');
  assert.match(await page.locator('#mcp-token').textContent(),/shown only once/);
  await items.nth(1).waitFor();assert.match(await items.nth(1).textContent(),/^Codex · created/);
  await page.locator('#mcp-token-done').click();
  assert.equal(await page.locator('#mcp-token-value').textContent(),'','Done clears the token from the page');
  assert.equal(await page.locator('#mcp-token').isHidden(),true);
  await items.first().locator('button').click();await page.locator('#op-confirm[open]').waitFor();
  assert.match(await page.locator('#op-confirm-text').textContent(),/Revoke MCP client "Claude <Code>"\? Its token stops working at once/);
  await page.locator('#op-confirm-ok').click();
  await page.locator('#mcp-result',{hasText:'Revoked'}).filter({hasText:'Revoked'}).waitFor();
  assert.equal(await items.count(),1);assert.match(await items.first().textContent(),/^Codex/);
  assert.deepEqual(posts.map(([p,b])=>[p.replace('/authorization/v1/mcp-clients',''),b]),[
    ['GET ',null],['POST /create',{version:1,name:'Codex'}],['GET ',null],['POST /revoke',{version:1,client_id:'00000000-0000-4000-8000-000000000001'}]],'exact requests');
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
  await page.waitForFunction(()=>connection.dataset.state==='connected'&&profileData&&typeof live!=='undefined',null,{timeout:30000});
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
  await page.waitForFunction(()=>typeof live!=='undefined'&&live?.job?.mode==='ft8'&&live.source);
  await page.waitForFunction(()=>window.wstxContact?.snapshot()?.contact?.state==='calling');
  // A receive snapshot of an unknown shape: visible error chip with the reload action.
  reject=true;await page.evaluate(()=>receiveSync());
  const notice=page.locator('#station-notice:not([hidden])');
  await notice.filter({hasText:'Station data not understood (receive) · reload'}).waitFor();
  assert.equal(await notice.getAttribute('data-severity'),'error');assert.equal(await notice.evaluate(n=>!!n.closest('#error-field')),true,'the notice is an error field entry (#37)');
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
  await page.waitForFunction(()=>connection.dataset.state==='connected'&&typeof live!=='undefined',null,{timeout:30000});
  assert.equal(state.navigations,1,'the chip reloads the page');
  assert.equal(await page.locator('#station-notice').isHidden(),true);
  // An open dialog also holds the reload.
  await page.waitForFunction(()=>typeof window.wstxConfirm==='function');
  await page.evaluate(()=>{window.wstxConfirm('Test dialog');});
  state.build='0011223344556677';state.navigations=0;await page.evaluate(()=>socket.close());
  await notice.filter({hasText:'Station updated'}).waitFor({timeout:20000});assert.equal(state.navigations,0,'an open dialog holds the reload');
  assert.deepEqual(errors,[]);
});

// #54: live frames for the current routed live job, injected as the station would announce them.
async function liveFrames(page,frames){
  await page.evaluate(frames=>{for(const {sequence,levels,thin,tx} of frames){
    const data={boot_id:live.boot_id,source_id:live.source.id,job_id:live.job.id,generation:live.generation,sequence,first_frame:sequence*(thin?12000:2400),end_frame:(sequence+1)*(thin?12000:2400)};
    if(tx)data.tx=true;
    if(thin)data.levels=levels;else data.levels_b64=btoa(String.fromCharCode(...levels));
    dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:thin?'spectrum.frame':'spectrum.detail.frame',data}}}));}},frames);
}
// Waterfall RGB at a native bin centre on the newest row (independent column/row mapping of TC-010-005).
async function cell(page,bin){
  await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
  return page.evaluate(bin=>{const c=document.querySelector('#waterfall'),x=Math.floor((bin+.5)*c.width/1024);return [...c.getContext('2d').getImageData(x,0,1,1).data.slice(0,3)];},bin);
}
async function liveDisplayFixture(t){
  let receiving;
  const f=await fixture(t,{width:1366,height:768},{beforeNavigate:async p=>{
    await p.route('**/receive',async route=>{const json=await (await route.fetch()).json();if(!receiving)receiving=liveFixture(json);await route.fulfill({json:receiving});});
    await p.route('**/receive/results?*',route=>route.fulfill({json:emptyResults(receiving)}));
  }});
  await f.page.waitForFunction(()=>typeof live!=='undefined'&&live?.job?.mode==='ft8'&&live.source);
  return {...f,newJob:async()=>{receiving={...receiving,job:{...receiving.job,id:crypto.randomUUID()}};await f.page.evaluate(()=>receiveSync());await f.page.waitForFunction(id=>live.job.id===id,receiving.job.id);}};
}
// Proves: CL-054-02; TC-054-002 a fixed level mapping with Zero/Gain sliders, Flatten and the spectrum line option.
test('TC-054-002 fixed dBFS colours, Sensitivity as Zero, Range as Gain, Flatten and the spectrum line option',{timeout:60000},async t=>{
  const {page,errors,newJob}=await liveDisplayFixture(t);
  // Independent palette anchors (CL-006-03): t=0.1 -> (0,0,57), t=0.9 -> (255,105,0), t=0.3 -> (0,60,185), t=0.5 -> (0,220,240).
  const noise=40,carrier=80,levels=Array.from({length:1024},(_,k)=>k>=498&&k<=502?carrier:noise);
  assert.deepEqual(await page.evaluate(()=>[document.querySelector('#display-sensitivity').value,document.querySelector('#display-range').value,document.querySelector('#display-speed').value,document.querySelector('#speed-value').textContent,document.querySelector('#spectrum').hidden,Math.abs(Math.round(document.querySelector('#signal').getBoundingClientRect().height)-Math.min(330,Number(document.querySelector('#splitter').getAttribute('aria-valuemax'))-200))<=8]),['0','50','1','10 px/s',true,true],'defaults: Zero 0, Gain 50 dB, 10 px/s, no spectrum line, 330 px or the available height less 400 px (#37 LowerPanel)');
  await liveFrames(page,[{sequence:0,levels},{sequence:1,levels}]);
  assert.deepEqual([await cell(page,100),await cell(page,500)],[[0,0,57],[255,105,0]],'noise -80 dBFS and a -40 dBFS carrier on the fixed -85..-35 dBFS scale');
  assert.match(await page.locator('#level-legend').textContent(),/WF -85 to -35 dBFS/);
  for(const [id,value] of [['#display-sensitivity','10']]){await page.locator(id).fill(value);await page.locator(id).dispatchEvent('input');}
  assert.deepEqual(await cell(page,100),[0,60,185],'Sensitivity +10 dB moves the scale to -95 dBFS');
  await page.locator('#display-range').fill('30');await page.locator('#display-range').dispatchEvent('input');
  assert.deepEqual([await cell(page,100),await page.locator('#range-value').textContent()],[[0,220,240],'30 dB'],'Range 30 dB narrows the span');
  // No automatic level: more rows and a new job keep the mapping.
  await liveFrames(page,[{sequence:2,levels:levels.map(q=>q+10)}]);assert.deepEqual(await cell(page,100),[255,192,0],'a louder row is louder, not re-levelled (t=0.833)');
  await newJob();await liveFrames(page,[{sequence:0,levels}]);assert.deepEqual(await cell(page,100),[0,220,240],'a new job keeps the levels');
  await page.reload();await page.waitForFunction(()=>typeof live!=='undefined'&&live?.job?.mode==='ft8'&&live.source);
  assert.deepEqual(await page.evaluate(()=>[sensitivity,displayRange]),[10,30],'per-browser settings survive a reload');
  // Flatten: a 30 dB passband slope is evened out across frequency; the native readout is unchanged.
  const slope=Array.from({length:1024},(_,k)=>30+Math.floor(30*k/1024));
  await liveFrames(page,[{sequence:0,levels:slope}]);
  const [low,high]=[await cell(page,40),await cell(page,980)];assert.notDeepEqual(low,high);
  await page.locator('#open-server-settings').click();await page.locator('#display-flatten').check();await page.locator('#display-spectrum').check();await page.locator('#settings-drawer .return-operate').click();
  assert.deepEqual(await cell(page,40),await cell(page,980),'flattened: the same colour at both band edges');
  assert.equal(await page.evaluate(()=>rows.at(-1).levels[980]),58,'the native level stays');
  assert.equal(await page.locator('#spectrum').isVisible(),true,'the spectrum line on request');
  assert.deepEqual(await page.evaluate(()=>['wstx.waterfall-zero.v1','wstx.waterfall-range.v1','wstx.waterfall-flatten.v1','wstx.spectrum-line.v1'].map(k=>localStorage.getItem(k))),['10','30','on','on']);
  assert.deepEqual(errors,[]);
});
// Proves: CL-054-01; TC-054-001 browser part: only real gaps are grey.
test('TC-054-001 one or two live Thin rows the station paced out are held; only a longer run is a gap',{timeout:60000},async t=>{
  const {page,errors}=await liveDisplayFixture(t);
  await chooseDisplay(page,'thin');
  const row=q=>Array.from({length:128},()=>q);
  await liveFrames(page,[{sequence:0,levels:row(10),thin:true},{sequence:2,levels:row(20),thin:true},{sequence:5,levels:row(30),thin:true},{sequence:6,levels:row(40),thin:true},{sequence:10,levels:row(50),thin:true}]);
  assert.deepEqual(await page.evaluate(()=>rows.map(r=>[r.sequence,r.levels?r.levels[0]:null])),[[0,10],[1,20],[2,20],[3,30],[4,30],[5,30],[6,40],[7,null],[8,null],[9,null],[10,50]]);
  assert.deepEqual(errors,[]);
});

// Proves: CL-024-01; TC-024-004 (#24 S1b). Tx5 takes free text with no message yet (WSJT-X Tx5
// free text), and Band Activity marks rows to <MYCALL> and nonstandard rows to my call as mine;
// the QSO pane Others list them as calling me, without the partner's own rows.
test('TC-024-004 Tx5 free text and <MYCALL> rows in the operating screen',{timeout:45000},async t=>{
  let state,records=[],contact,settings={};const commands=[],period='2026-10-27T12:00:00.0000000Z';
  const call=(kind,text,bits=null)=>({kind,text,hash_bits:bits,hash_value:bits===null?null:1});
  const standard=(to,from)=>({type:'standard',to,from,ack:false,exchange:{kind:'report',value:-12}});
  const nonstandard=(hashed,full,hash_second)=>({type:'nonstandard',full_call:call('call',full),hashed_call:hashed,hash_second,cq:false,roger:''});
  const record=(sequence,text,fields,hz,i3)=>({sequence,start_frame:6000,frequency_hz:hz,snr_db:-10,dt_seconds:0.1,payload77:'0'.repeat(77),i3,n3:null,status:'decoded',text,fields,period_start_utc:period});
  const cq={id:crypto.randomUUID(),origin:'own_cq',dx_call:null,dx_grid:null,report_sent:null,report_rcvd:null,state:'calling',next_slot:'tx6',tx4:'rrr',messages:[null,null,null,null,null,'CQ HB9BLA JN47'],start_utc:null,end_utc:null,saved:false};contact=cq;
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    state=liveFixture(await (await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:period,canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    records=[
      record(0,'<HB9BLA> PJ4/K1ABC',nonstandard(call('hash','HB9BLA',12),'PJ4/K1ABC',false),1000,4),
      record(1,'HB9BLA <PJ4/K1ABC> -12',standard(call('call','HB9BLA'),call('hash','PJ4/K1ABC',22)),1100,1),
      record(2,'<...> PJ4/K1ABC',nonstandard(call('hash',null,12),'PJ4/K1ABC',false),1200,4),
      record(3,'<HB9BLA> K1ABC -12',standard(call('hash','HB9BLA',22),call('call','K1ABC')),1300,1),
    ];
    Object.assign(state.job,{first_sequence:0,next_sequence:4,available_count:4,latest_decode:{id:1,first_sequence:0,next_sequence:4,period_start_utc:period,complete:true}});
    await p.route('**/receive',async route=>{await p.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await p.route('**/receive/results?*',async route=>{const cursor=Number(new URL(route.request().url()).searchParams.get('cursor')),batch=records.slice(cursor),next=cursor+batch.length;await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:records.length,available_count:records.length,next,more:false,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});});
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{contact,settings})}));
    await contactCommands(p,commands);
  }});
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===4&&window.wstxContact?.snapshot(),null,{timeout:25000});
  const marks=await page.locator('tr[data-result-id]').evaluateAll(rows=>rows.map(r=>[r.children[4].textContent,r.classList.contains('ba-tome')]));
  // #55 value order: the three rows to my call (also as <HB9BLA> and nonstandard) are value 1, first.
  assert.deepEqual(marks,[['<HB9BLA> PJ4/K1ABC',true],['HB9BLA <PJ4/K1ABC> -12',true],['<HB9BLA> K1ABC -12',true],['<...> PJ4/K1ABC',false]]);
  // QsoPane Others (#24, the same mycall rule): an own CQ is idle, so every row to my call is
  // listed, oldest first; the unresolved <...> row is not.
  const others=()=>page.locator('#qso-others tr').evaluateAll(rows=>rows.map(r=>r.dataset.text));
  await page.waitForFunction(()=>document.querySelectorAll('#qso-others tr').length===3,null,{timeout:10000}).catch(()=>{});
  assert.deepEqual(await others(),['<HB9BLA> PJ4/K1ABC','HB9BLA <PJ4/K1ABC> -12','<HB9BLA> K1ABC -12']);
  // During a QSO with PJ4/K1ABC (Rx 1000, Tx 1300 Hz): its own nonstandard row at 1000 Hz is the
  // partner's and the row at 1100 Hz is near neither offset, so only K1ABC's row at 1300 Hz stays.
  contact={...cq,origin:'selected_row',dx_call:'PJ4/K1ABC',state:'replying',next_slot:'tx1',messages:['<PJ4/K1ABC> HB9BLA','<PJ4/K1ABC> HB9BLA -12',null,null,null,'CQ HB9BLA JN47']};settings={rx_hz:1000,tx_hz:1300};
  await page.evaluate(()=>window.wstxContact.load());
  await page.waitForFunction(()=>document.querySelector('#qso-others tr')?.dataset.kind==='warn'||document.querySelectorAll('#qso-others tr').length===0,null,{timeout:10000});
  assert.deepEqual(await others(),['<HB9BLA> K1ABC -12']);
  contact=cq;settings={};await page.evaluate(()=>window.wstxContact.load());
  await page.locator('#qso-more summary').click();
  const tx5=page.locator('#contact-messages .ct-text[data-slot=tx5]');
  assert.equal(await tx5.isEnabled(),true,'Tx5 takes free text without a message');
  assert.equal(await page.locator('#contact-messages .ct-text[data-slot=tx4]').isEnabled(),false,'the other empty slots stay disabled');
  assert.equal(await page.locator('#contact-messages li[data-slot=tx5] input[type=radio]').isEnabled(),false,'nothing to choose yet');
  await tx5.fill('tnx 73 gl');await tx5.press('Tab');
  for(let i=0;i<40&&!commands.some(c=>c.action==='edit_message');i++)await page.waitForTimeout(50);
  const edit=commands.find(c=>c.action==='edit_message');
  assert.deepEqual([edit.slot,edit.text],['tx5','tnx 73 gl']);
  assert.equal(commands.some(c=>c.action==='enable_tx'),false,'editing never transmits');
  assert.deepEqual(errors,[]);
});

// Proves: CL-024-02; TC-024-006 (#24 S2a). The QSO fold-out's Activity choice shows the station's
// special activity and sends set_activity.
test('TC-024-006 the Activity choice in the QSO fold-out',{timeout:40000},async t=>{
  const commands=[];
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{contact:partner(),settings:{activity:'ww_digi'}})}));
    await contactCommands(p,commands);
  }});
  await page.waitForFunction(()=>window.wstxContact?.snapshot(),null,{timeout:25000});
  await page.locator('#qso-more summary').click();
  const choice=page.locator('#contact-activity');
  await page.waitForFunction(()=>document.querySelector('#contact-activity')?.value==='ww_digi');
  assert.deepEqual(await choice.locator('option').evaluateAll(o=>o.map(x=>[x.value,x.textContent])),[['none','None'],['na_vhf','NA VHF'],['ww_digi','WW Digi'],['arrl_digi','ARRL Digi'],['field_day','Field Day'],['rtty','RTTY Roundup'],['hound','Hound']]);
  await choice.selectOption('arrl_digi');
  for(let i=0;i<40&&!commands.some(c=>c.action==='set_activity');i++)await page.waitForTimeout(50);
  const sent=commands.find(c=>c.action==='set_activity');
  assert.equal(sent.activity,'arrl_digi');
  assert.equal(commands.some(c=>c.action==='enable_tx'),false,'choosing never transmits');
  assert.deepEqual(errors,[]);
});

// Proves: CL-024-03; TC-024-009 (#24 S2b). Field Day / RTTY Roundup with the Exchange entry:
// the entry and the serial show the station's setting; choosing and changing send the exchange.
test('TC-024-009 the contest choice and its Exchange entry',{timeout:40000},async t=>{
  const commands=[];
  const settings={activity:'rtty',exchange:'DX',serial:7};
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{contact:partner(),settings:{...settings}})}));
    await contactCommands(p,commands);
  }});
  await page.waitForFunction(()=>window.wstxContact?.snapshot(),null,{timeout:25000});
  await page.locator('#qso-more summary').click();
  await page.waitForFunction(()=>document.querySelector('#contact-activity')?.value==='rtty');
  assert.equal(await page.locator('#contact-exchange').inputValue(),'DX');
  assert.equal(await page.locator('#contact-serial').textContent(),'Serial 0007');
  const sentAll=async n=>{for(let i=0;i<40&&commands.filter(c=>c.action==='set_activity').length<n;i++)await page.waitForTimeout(50);return commands.filter(c=>c.action==='set_activity');};
  await page.locator('#contact-exchange').fill('1A EMA');
  await page.locator('#contact-activity').selectOption('field_day');
  let sent=await sentAll(1);
  assert.deepEqual([sent[0].activity,sent[0].exchange],['field_day','1A EMA']);
  Object.assign(settings,{activity:'field_day',exchange:'1A EMA'});
  await page.evaluate(()=>window.wstxContact.load());
  await page.waitForFunction(()=>window.wstxContact.snapshot().settings.activity==='field_day');
  assert.equal(await page.locator('#contact-serial').textContent(),'','no serial for Field Day');
  await page.locator('#contact-exchange').fill('2B WI');
  await page.locator('#contact-exchange').press('Tab');
  sent=await sentAll(2);
  assert.deepEqual([sent.at(-1).activity,sent.at(-1).exchange],['field_day','2B WI']);
  assert.equal(commands.some(c=>c.action==='enable_tx'),false,'choosing never transmits');
  assert.deepEqual(errors,[]);
});

// Proves: CL-024-04; TC-024-013 (#24 S4b). The Hound choice: shown from the settings and sent
// without an exchange.
test('TC-024-013 the Hound choice in the QSO fold-out',{timeout:40000},async t=>{
  const commands=[];
  const settings={activity:'hound',exchange:null,serial:1};
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{contact:partner(),settings:{...settings}})}));
    await contactCommands(p,commands);
  }});
  await page.waitForFunction(()=>window.wstxContact?.snapshot(),null,{timeout:25000});
  await page.locator('#qso-more summary').click();
  await page.waitForFunction(()=>document.querySelector('#contact-activity')?.value==='hound');
  const choice=page.locator('#contact-activity');
  assert.deepEqual(await choice.locator('option').evaluateAll(o=>o.slice(-2).map(x=>[x.value,x.textContent])),[['rtty','RTTY Roundup'],['hound','Hound']]);
  Object.assign(settings,{activity:'none'});
  await page.evaluate(()=>window.wstxContact.load());
  await page.waitForFunction(()=>document.querySelector('#contact-activity')?.value==='none');
  await choice.selectOption('hound');
  for(let i=0;i<40&&!commands.some(c=>c.action==='set_activity');i++)await page.waitForTimeout(50);
  const sent=commands.find(c=>c.action==='set_activity');
  assert.equal(sent.activity,'hound');
  assert.equal('exchange' in sent,false,'Hound takes no exchange');
  assert.equal(commands.some(c=>c.action==='enable_tx'),false,'choosing never transmits');
  assert.deepEqual(errors,[]);
});

// Proves: CL-061-01; TC-061-001. Scripted receive identities, periods and waterfall rows (presentation fixtures, never modem truth).
test('TC-061-001 an audio loss epoch keeps the waterfall and Band Activity; a Stop/Start clears them',{timeout:45000},async t=>{
  let state,records=[];const reads=[];
  const periods=['2026-10-27T12:00:00.0000000Z','2026-10-27T12:00:15.0000000Z','2026-10-27T12:00:30.0000000Z'];
  const makeRecord=(sequence,period)=>({sequence,start_frame:186000+sequence,frequency_hz:1000+sequence,snr_db:-12,payload77:'0'.repeat(77),i3:0,n3:0,status:'decoded',text:`EPOCH FIXTURE ${sequence}`,fields:{},period_start_utc:period,dt_seconds:0.1});
  const publish=(id,period,count)=>{const first=records.length;for(let i=0;i<count;i++)records.push(makeRecord(first+i,period));Object.assign(state.job,{first_sequence:0,next_sequence:records.length,available_count:records.length,latest_decode:{id,first_sequence:first,next_sequence:records.length,period_start_utc:period,complete:true}});};
  // A new receive identity as the station allocates it: fresh source, job and generation, results from sequence 0.
  const renew=lossEpochs=>{records=[];state={...state,generation:state.generation+1,audio:{...state.audio,loss_epochs:lossEpochs,last_loss:lossEpochs?'queue_full':null},source:{...state.source,id:crypto.randomUUID()},job:{...state.job,id:crypto.randomUUID(),first_sequence:0,next_sequence:0,available_count:0,latest_decode:null}};};
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(page,app)=>{
    state=liveFixture(await(await fetch(app.origin+'/receive')).json());state.source.next_frame=720000;
    state.clock={basis:'system_utc',correlated:true,utc_anchor:'2026-10-27T12:00:00.0000000Z',canonical_anchor_frame:0,uncertainty_ns:500,external_accuracy:'unknown'};
    publish(1,periods[0],2);
    await page.route('**/recording',async route=>{const json=await(await route.fetch()).json();await route.fulfill({json:{...json,generation:state.generation,job:{id:state.job.id,source_id:state.source.id,generation:state.generation,kind:'live',state:'running',processed_frames:0,error:null}}});});
    await page.route('**/receive',async route=>{await page.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:state});});
    await page.route('**/receive/results?*',async route=>{
      const query=new URL(route.request().url()).searchParams,cursor=Number(query.get('cursor')),limit=Number(query.get('limit'));reads.push([query.get('job_id'),Number(query.get('generation')),cursor]);
      const batch=records.slice(cursor,cursor+limit),next=cursor+batch.length;
      await route.fulfill({json:{...emptyResults(state),first_sequence:0,next_sequence:records.length,available_count:records.length,next,more:next<records.length,records:batch,latest_decode:structuredClone(state.job.latest_decode)}});
    });
  }});
  const shown=()=>page.evaluate(()=>[...document.querySelectorAll('#band-activity tbody tr[data-period], #band-activity tbody tr.ba-divider')].map(r=>r.classList.contains('ba-divider')?'|'+r.textContent:`${r.dataset.period}:${r.dataset.sequence}`));
  const waterfall=()=>page.evaluate(()=>rows.map(r=>[r.sequence,r.levels?r.levels[0]:null]));
  const level=q=>Array.from({length:1024},()=>q);
  await page.waitForFunction(()=>document.querySelectorAll('tr[data-period=latest]').length===2&&window.wstxRenderHistory);
  publish(2,periods[1],1);await page.evaluate(()=>receiveSync());
  await page.waitForFunction(()=>resultView?.id===2&&document.querySelectorAll('tr[data-period=latest]').length===1);
  await liveFrames(page,[0,1,2,3].map(sequence=>({sequence,levels:level(10*(sequence+1))})));
  assert.deepEqual(await waterfall(),[[0,10],[1,20],[2,30],[3,40]]);
  // The audio loss epoch: the recording.state and receive.state readers both see the new identity.
  renew(1);const generation=state.generation,job=state.job.id;
  await page.evaluate(async()=>{await sync();await receiveSync();});await page.waitForFunction(g=>live.generation===g,generation);
  assert.deepEqual(await shown(),['|FT8 period 12:00:15 UTC','history:2','|FT8 period 12:00:00 UTC','history:0','history:1'],'Band Activity keeps the decoded periods');
  await liveFrames(page,[{sequence:0,levels:level(50)},{sequence:1,levels:level(60)}]);
  assert.deepEqual(await waterfall(),[[-5,10],[-4,20],[-3,30],[-2,40],[-1,null],[0,50],[1,60]],'old rows kept, one gap row, then the new epoch');
  // #37 CL-037-02: a receive restart is informational, no error field entry; the gap row marks the loss.
  assert.equal(await page.locator('#error-field .op-error-entry').count(),0,'the error field stays empty for the epoch');
  publish(1,periods[2],1);await page.evaluate(()=>receiveSync());
  await page.waitForFunction(()=>resultView?.period_start_utc==='2026-10-27T12:00:30.0000000Z'&&document.querySelectorAll('tr[data-period=latest]').length===1);
  assert.deepEqual(await shown(),['latest:0','|FT8 period 12:00:15 UTC','history:2'],'the new period on top, the one before it kept');
  assert.deepEqual(reads.find(([id])=>id===job),[job,generation,0],'the new identity is read from cursor 0');
  // A Stop/Start (loss_epochs restarts at 0) is a new receive: both clear.
  renew(0);await page.evaluate(async()=>{await sync();await receiveSync();});await page.waitForFunction(g=>live.generation===g,state.generation);
  assert.deepEqual([await shown(),await waterfall()],[[],[]],'a new receive clears Band Activity and the waterfall');
  await liveFrames(page,[{sequence:0,levels:level(70)}]);assert.deepEqual(await waterfall(),[[0,70]]);
  assert.deepEqual(errors,[]);
});

// ---------------------------------------------------------------- #37 lower panel
// WstxOperatingLayout::LowerPanel, ControlPanel, ErrorField. Oracle: the operator's #37 comments
// of 2026-11-03 (vertical stack, the QSO card's width, the controls always visible, the error
// field with current problems only and no history), not the candidate markup.
const panelControls=['#dx-call','#dx-grid','#dx-generate','#contact-report','#contact-auto','#contact-call-first','#contact-hold','#contact-parity'];
async function lowerStack(page){return page.evaluate(()=>{
  const box=s=>{const r=document.querySelector(s).getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width};};
  const panel=document.querySelector('#qso-control'),pr=panel.getBoundingClientRect(),controls=[...panel.querySelectorAll('input,select,button')].map(n=>n.closest('label')??n).map(n=>n.getBoundingClientRect());
  const spread=(Math.max(...controls.map(r=>r.right))-Math.min(...controls.map(r=>r.left)))/pr.width;
  return {pane:box('#rx-focus'),control:box('#qso-control'),error:box('#error-field'),spread,scroll:document.documentElement.scrollWidth>innerWidth};
});}
function assertStack(s,label){
  assert.ok(s.pane.bottom<=s.control.top+0.5&&s.control.bottom<=s.error.top+0.5,`${label}: pane, Control and error field stacked top to bottom ${JSON.stringify(s)}`);
  for(const k of ['control','error'])assert.ok(Math.abs(s[k].left-s.pane.left)<=1&&Math.abs(s[k].right-s.pane.right)<=1,`${label}: ${k} has the QSO card's edges ${JSON.stringify(s)}`);
  assert.equal(s.scroll,false,`${label}: no horizontal overflow`);
}
// Proves: CL-037-01; TC-037-001 the Control panel below the QSO pane.
test('TC-037-001 the Control panel sits below the QSO pane at its width with DX call, report, Auto Seq, Call 1st, Hold Tx and Tx period always visible',{timeout:60000},async t=>{
  const commands=[];
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{contact:partner('replying')})}));
    await contactCommands(p,commands);
  }});
  await page.waitForFunction(()=>window.wstxContact?.snapshot()&&!document.querySelector('#contact-report').disabled,null,{timeout:45000});
  assert.equal(await page.locator('#qso-more').evaluate(d=>d.open),false,'the fold-out stays closed');
  for(const selector of panelControls){
    assert.equal(await page.locator(`#qso-control ${selector}`).count(),1,`${selector} in the Control panel`);
    assert.equal(await inViewport(page,selector),true,`${selector} visible without opening the fold-out`);
    assert.equal(await page.locator(`#qso-more ${selector}`).count(),0,`${selector} left the fold-out`);
  }
  assert.equal(await page.locator('#qso-more #contact-messages li').count(),6,'Tx1-Tx6 stay in the fold-out');
  assert.equal(await page.locator('#rxtx-strip #contact-hold').count(),0,'Hold Tx left the Rx/Tx strip');
  for(const selector of ['#contact-rx','#contact-tx'])assert.equal(await page.locator(`#rxtx-strip ${selector}`).count(),1,'the frequencies stay under the waterfall');
  assert.equal(await page.locator('#qso-control .op-input-meter,#qso-control #op-dial,#qso-control #contact-rx,#error-field .op-input-meter').count(),0,'no level meter or frequency in the lower panel');
  const desk=await lowerStack(page);assertStack(desk,'1366x768');
  assert.ok(desk.spread>=0.8,`the controls are laid out across the panel width (${desk.spread})`);
  assert.equal(await page.evaluate(()=>document.documentElement.scrollHeight>innerHeight),false,'no page scroll at 1366x768');
  await page.screenshot({path:'test-results/ui-operating/lower-panel-1366x768.png'});
  // Each control sends its single contact request.
  const last=async n=>{for(let i=0;i<40&&commands.length<n;i++)await page.waitForTimeout(50);assert.equal(commands.length,n,JSON.stringify(commands.slice(-3)));return commands.at(-1);};
  await page.locator('#contact-report').fill('7');await page.locator('#contact-report').press('Tab');assert.deepEqual([(await last(1)).action,commands[0].report],['set_report',7]);
  await page.locator('#contact-auto').uncheck();assert.deepEqual([(await last(2)).action,commands[1].enabled],['set_auto_seq',false]);
  await page.locator('#contact-call-first').uncheck();assert.deepEqual([(await last(3)).action,commands[2].enabled],['set_call_first',false]);
  await page.locator('#contact-hold').check();assert.deepEqual([(await last(4)).action,commands[3].enabled],['set_hold_tx',true]);
  await page.locator('#contact-parity').selectOption('odd');assert.deepEqual([(await last(5)).action,commands[4].parity],['set_parity','odd']);
  await page.locator('#dx-call').fill('W1AW');await page.locator('#dx-call').press('Enter');assert.deepEqual([(await last(6)).action,commands[5].dx_call],['enter_dx','W1AW']);
  await page.setViewportSize({width:1920,height:1080});assertStack(await lowerStack(page),'1920x1080');
  await page.setViewportSize({width:360,height:800});await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
  assertStack(await lowerStack(page),'360x800');
  await page.locator('#error-field').scrollIntoViewIfNeeded();await page.screenshot({path:'test-results/ui-operating/lower-panel-360x800.png'});
  assert.deepEqual(errors,[]);
});
// Proves: CL-037-02; TC-037-002 the error field lists current problems only.
test('TC-037-002 the error field lists only current problems with their time and clears them by itself',{timeout:60000},async t=>{
  let transmit={};
  const {page,errors}=await fixture(t,{width:1366,height:768},{inputDevice:'test-only-unopened-input',beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot(base,{transmit})}));
    // A healthy station: receive runs (the receive snapshot names a running live job).
    const idle=await (await fetch(app.origin+'/receive')).json(),running=liveFixture({...idle,generation:idle.generation+1});
    await p.route('**/receive',route=>route.fulfill({json:running}));
    await p.route('**/receive/results?*',route=>route.fulfill({json:emptyResults(running)}));
    await p.route('**/recording',async route=>{const real=await (await route.fetch()).json();await route.fulfill({json:{...real,generation:running.generation,job:{id:running.job.id,source_id:running.source.id,generation:running.generation,kind:'live',state:'running',processed_frames:0,error:null}}});});
  }});
  await page.waitForFunction(()=>window.wstxContact?.snapshot()&&live?.job?.state==='running',null,{timeout:45000});
  const entries=()=>page.locator('#error-field [role=listitem]').evaluateAll(list=>list.map(e=>[e.querySelector('button').dataset.chip,e.querySelector('button').textContent,e.querySelector('.op-error-since')?.textContent]));
  const show=()=>page.evaluate(()=>window.wstxChipsShow());
  await show();
  assert.deepEqual(await entries(),[],'a healthy station has no entry');
  const none=page.locator('#error-field').getByText('No problems',{exact:true});
  assert.equal(await none.isVisible(),true,'an empty field says No problems');
  assert.equal(await page.locator('#station-bar .op-chip:not([hidden])').count(),0,'no exception chips in the top bar');
  // CAT not ready.
  const hhmm=()=>new Date().toISOString().slice(11,16);
  const before=hhmm();
  await page.evaluate(()=>{profileData.settings.control.mode='cat';catStatus={condition:'radioUnavailable'};document.querySelector('#cat-status').textContent='CAT radio unavailable';});await show();
  let list=await entries();
  assert.equal(list.length,1,JSON.stringify(list));assert.deepEqual(list[0].slice(0,2),['cat','✖ CAT radio unavailable']);
  assert.ok([`since ${before}`,`since ${hhmm()}`].includes(list[0][2]),list[0][2]);
  assert.equal(await none.isVisible(),false);
  // A transmit refusal the operator must fix appears; a transient one does not.
  transmit={refusal:'radio_lost'};await page.evaluate(()=>window.wstxContact.load());await show();
  assert.deepEqual((await entries()).map(e=>e[1]).sort(),['✖ CAT radio unavailable','✖ Tx refused · radio lost']);
  transmit={refusal:'busy'};await page.evaluate(()=>window.wstxContact.load());await show();
  assert.deepEqual((await entries()).map(e=>e[0]),['cat'],'a transient refusal is no entry');
  transmit={refusal:'ptt_timeout'};await page.evaluate(()=>window.wstxContact.load());await show();
  // The CAT condition clears: its entry goes without any operator action, the refusal stays.
  await page.evaluate(()=>{catStatus={condition:'ready'};});await show();
  assert.deepEqual((await entries()).map(e=>e[1]),['✖ Tx refused · ptt timeout']);
  assert.equal(await page.locator('#error-field').getByRole('button',{name:/acknowledge|dismiss|clear|^ok$/i}).count(),0,'no acknowledge control');
  transmit={refusal:null};await page.evaluate(()=>window.wstxContact.load());await show();
  assert.deepEqual(await entries(),[],'no history: a cleared problem leaves nothing');
  assert.equal(await none.isVisible(),true);
  // Connection loss.
  await page.evaluate(()=>socket.close());await page.locator('#connection[data-state=stale]').waitFor();await show();
  assert.deepEqual((await entries()).map(e=>e[1]),['✖ Station connection lost · reconnecting']);
  assert.deepEqual(errors,[]);
});
// Proves: CL-061-02; TC-061-003. Scripted contact snapshots and command replies (presentation fixtures): the CQ
// button retries a stale_revision refusal of its enable_tx with the reloaded revision, at most twice.
test('TC-061-003 CQ retries a stale_revision refusal with the reloaded snapshot',{timeout:40000},async t=>{
  const commands=[];let contact=null,revision=3,stale=0;
  const {page,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:async(p,app)=>{
    const base=await (await fetch(app.origin+'/profile')).json();
    await p.route('**/contact',route=>route.fulfill({json:contactSnapshot({...base,revision,sequence:revision},{contact})}));
    // The station refuses the next `stale` commands (its revision moved: the last 73 period ended) and moves it on.
    await p.route('**/contact/command',async route=>{const b=JSON.parse(route.request().postData());commands.push(b);
      if(stale>0){stale--;revision++;await route.fulfill({status:409,json:{v:1,error:{code:'stale_revision'}}});}else await route.fulfill({status:202,json:{v:1,accepted:true}});});
  }});
  await page.waitForFunction(()=>!!window.wstxContact?.snapshot()&&!document.querySelector('#qso-cq').disabled,null,{timeout:25000});
  const sent=async(m,count)=>{for(let i=0;i<80&&commands.length<m+count;i++)await page.waitForTimeout(50);await page.waitForTimeout(300);return commands.slice(m).map(c=>[c.action,c.enabled,c.contact_revision]);};
  stale=1;let m=commands.length;await page.locator('#qso-cq').click();
  assert.deepEqual(await sent(m,2),[['enable_tx',true,3],['enable_tx',true,4]],'CQ: refused once, sent again with the reloaded revision');
  await page.locator('#contact-result').filter({hasText:'CQ: accepted'}).waitFor();
  // At most two retries: a third refusal stays shown.
  stale=3;m=commands.length;await page.locator('#qso-cq').click();
  assert.deepEqual(await sent(m,3),[['enable_tx',true,4],['enable_tx',true,5],['enable_tx',true,6]]);
  await page.locator('#contact-result').filter({hasText:'CQ: refused · stale_revision'}).waitFor();
  assert.deepEqual(errors,[]);
});
