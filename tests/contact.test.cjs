'use strict';
// Cost2: launched by contact_http_tests::contact_browser_operating_flow with the actual
// candidate Router, contact engine and #9 transmit owner on a recording hardware double
// (no audio, PTT or radio). Decoded rows are hand-authored and published through the
// test-only control peer; expected values below are the independent TC tables.
// Proves: CL-010-01, CL-010-02, CL-010-03, CL-010-06, CL-010-11, CL-010-14; TC-007-001,
// TC-007-003, TC-007-004, TC-010-008, TC-010-009.
// Proves: CL-055-02; TC-055-004 (DXCC column, approximate distance, QSO header).
const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const origin=process.env.WSTX_CONTACT_FIXTURE_ORIGIN,control=process.env.WSTX_CONTACT_FIXTURE_CONTROL;
let browser,page,requests=[];
const publish=async(period_ms,rows)=>(await fetch(control+'/publish',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({period_ms,rows})})).json();
const commands=()=>requests.filter(r=>r.method==='POST'&&r.path==='/contact/command').map(r=>JSON.parse(r.body));
const mutations=()=>requests.filter(r=>r.method!=='GET');
const snapshot=async()=>(await fetch(origin+'/contact')).json();
async function waitFor(predicate,label,timeout=8000){const end=Date.now()+timeout;for(;;){const value=await predicate();if(value)return value;if(Date.now()>end)throw new Error('timeout: '+(typeof label==='function'?await label():label));await new Promise(r=>setTimeout(r,100));}}
before(async()=>{
  assert.ok(origin&&control,'run through contact_http_tests::contact_browser_operating_flow');
  browser=await chromium.launch();
  const context=await browser.newContext({viewport:{width:1440,height:1000}});
  page=await context.newPage();
  page.errors=[];page.on('pageerror',e=>page.errors.push(e.message));
  page.on('request',r=>{const u=new URL(r.url());const e={method:r.method(),path:u.pathname,body:r.postData(),at:performance.now(),end:null};requests.push(e);r.__e=e;});
  page.on('requestfinished',r=>{if(r.__e)r.__e.end=Math.round(performance.now());});page.on('requestfailed',r=>{if(r.__e)r.__e.end='failed';});
  await page.goto(origin);await page.locator('#connection[data-state=connected]').waitFor();
  // contact.js loads after the first recording/receive snapshots (idle link).
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
});
after(async()=>{await browser?.close();});

const evenNow=()=>Math.floor(Date.now()/30000)*30000;
test('TC-007-003 Rx Frequency pane routing and TC-007-001 selection without transmit',{timeout:90000},async()=>{
  const period=evenNow();
  await publish(period,[
    {text:'CQ K1ABC FN42',hz:1234.6,snr:-12.4},{text:'CQ W1AA FN31',hz:1489.9,snr:-1},{text:'CQ W2BB FN31',hz:1490.0,snr:-2},
    {text:'CQ W3CC FN31',hz:1510.0,snr:-3},{text:'CQ W4DD FN31',hz:1510.1,snr:-4},{text:'HB9BLA W1XYZ -10',hz:400,snr:-10},
    {text:'HB9BL K1ABC -01',hz:2600,snr:-9},{text:'CQ DL1ABC JO62',hz:800,snr:-3}]);
  const rows=page.locator('#band-activity tbody tr[data-sequence]');
  await waitFor(async()=>await rows.count()===8,'eight Band Activity rows',30000);
  // #55 TC-055-004: the DXCC column from the station's cty.dat entity (United States
  // 37.60 N 91.87 W, Germany; cty.dat lines 1251/669) and, without a grid in the
  // message, the distance from the country position, marked approximate (~): JN47AA to
  // 37.60 N 91.87 W is 7706 km by hand haversine.
  const dxcc=text=>rows.filter({hasText:text}).first().evaluate(tr=>[tr.children[5].textContent,tr.children[5].title,tr.children[6].textContent]);
  assert.deepEqual(await dxcc('HB9BLA W1XYZ -10'),['U.S.A.','U.S.A. \u00b7 NA \u00b7 CQ zone 5 \u00b7 ITU zone 8 (cty.dat)','~7706 km']);
  assert.equal((await dxcc('CQ DL1ABC JO62'))[0],'Germany');
  assert.doesNotMatch((await dxcc('CQ K1ABC FN42'))[2],/~/,'a message grid gives the exact distance');
  const pane=async()=>page.locator('#rx-pane-rows tr').evaluateAll(trs=>trs.map(tr=>[tr.dataset.kind,tr.children[3].textContent,tr.children[4].textContent]));
  // Rx 1500 Hz: exactly 1490.0 and 1510.0 within +/-10 Hz and the row to my call.
  await waitFor(async()=>(await pane()).length===5,async()=>`QSO pane ${JSON.stringify(await pane())}`);
  assert.deepEqual((await pane()).filter(r=>r[0]==='rx').map(r=>r[2]).sort(),['CQ W2BB FN31','CQ W3CC FN31','HB9BLA W1XYZ -10']);
  // #37 QsoPaneCrowding: other stations within +/-50 Hz (1489.9 and 1510.1) are shown marked.
  assert.deepEqual((await pane()).filter(r=>r[0]==='crowd').map(r=>r[2]).sort(),['CQ W1AA FN31','CQ W4DD FN31']);
  assert.deepEqual(await page.locator('#rx-pane-rows tr[data-crowd=true]').evaluateAll(trs=>trs.map(tr=>tr.children[4].textContent).sort()),['CQ W1AA FN31','CQ W2BB FN31','CQ W3CC FN31','CQ W4DD FN31']);
  assert.equal(await page.locator('#qso-crowd').textContent(),'\u26A0 4 near Rx');
  // Local sorting/clearing: no request.
  const before=requests.length;
  // #37: Erase and the DX entry are in the QSO fold-out.
  await page.locator('#band-activity th[data-sort=signal]').click();await page.locator('#qso-more summary').click();await page.locator('#rx-pane-erase').click();
  assert.equal(await page.locator('#rx-pane-rows tr').count(),0);
  assert.equal(requests.slice(before).filter(r=>r.method!=='GET'||r.path==='/receive/results').length,0,'local presentation sends no request');
  // Selection by Enter on the focused row sends the exact identity.
  const k1abc=rows.filter({hasText:'CQ K1ABC FN42'});
  await k1abc.focus();await page.keyboard.press('Enter');
  const select=await waitFor(()=>commands().find(c=>c.action==='select_row'),'select_row');
  const live=await (await fetch(origin+'/receive')).json();
  assert.deepEqual(Object.keys(select.row).sort(),['generation','job_id','sequence','source_id']);
  assert.equal(select.row.source_id,live.source.id);assert.equal(select.row.job_id,live.job.id);assert.equal(select.row.generation,live.generation);
  assert.equal(String(select.row.sequence),await k1abc.getAttribute('data-sequence'));
  await page.locator('#rx-focus .op-contact-identity strong').filter({hasText:'K1ABC'}).waitFor();
  // #55 TC-055-004: the QSO pane header names the partner's country and continent.
  await page.locator('#rx-focus .op-contact-identity strong').filter({hasText:'K1ABC \u00b7 FN42 \u00b7 U.S.A. (NA)'}).waitFor();
  const texts=await page.locator('#contact-messages .ct-text').evaluateAll(inputs=>inputs.map(i=>i.value));
  assert.deepEqual(texts,['K1ABC HB9BLA JN47','K1ABC HB9BLA -12','K1ABC HB9BLA R-12','K1ABC HB9BLA RRR','K1ABC HB9BLA 73','CQ HB9BLA JN47']);
  assert.equal(await page.locator('input[name=contact-next][value=tx1]').isChecked(),true);
  assert.equal(await page.locator('#contact-rx').inputValue(),'1235');assert.equal(await page.locator('#contact-tx').inputValue(),'1235');
  assert.equal(await page.locator('#contact-parity').inputValue(),'odd');
  assert.equal(await page.locator('#waterfall-wrap .ct-rx').textContent(),'Rx/Tx 1235');
  assert.equal((await snapshot()).transmit.arm_state,'disarmed','selection alone never arms');
  assert.equal(requests.some(r=>r.method==='POST'&&r.path.startsWith('/transmit')),false,'no transmit request from selection');
  assert.equal(commands().some(c=>c.action==='enable_tx'),false);
  assert.deepEqual(page.errors,[]);
});

test('TC-007-001 Reply starts transmission, partner report advances to Tx3, Esc halts first and cancels with a panel open',{timeout:90000},async()=>{
  // #37 WstxContact::SetEnableTx: no Enable Tx control; Reply arms the prepared contact.
  assert.equal(await page.locator('#contact-enable').count(),0);
  const shown=(await snapshot()).transmit.safety_revision;
  await page.getByRole('button',{name:'Reply',exact:true}).click();
  await waitFor(async()=>(await snapshot()).transmit.arm_state==='armed','armed');
  const enable=commands().filter(c=>c.action==='enable_tx');assert.equal(enable.length,1);assert.deepEqual([enable[0].enabled,enable[0].safety_revision],[true,shown]);
  await page.locator('#rx-focus[data-armed=true]').waitFor();
  // The compact transmit state stays in the top bar while transmission is on.
  await page.locator('#station-bar #station-tx').filter({hasText:/Tx on|TRANSMITTING/}).waitFor();
  // One TransmitRequest: pending, or already started when armed inside an own period.
  const armed=await waitFor(async()=>{const v=await snapshot();return (Number.isSafeInteger(v.transmit.pending_sequence)||v.transmit.last_text)&&v;},'one TransmitRequest');assert.ok(armed);
  await publish(evenNow(),[{text:'HB9BLA K1ABC -05',hz:1240,snr:-7}]);
  await waitFor(async()=>(await snapshot()).contact.state==='roger_report','roger_report',15000);
  await page.locator('#contact-next').filter({hasText:'K1ABC HB9BLA R-12'}).waitFor();
  assert.equal(await page.locator('input[name=contact-next][value=tx3]').isChecked(),true);
  assert.notEqual(await page.locator('#contact-next').textContent(),await page.locator('#contact-last').textContent(),'next and last sent are distinct');
  await page.locator('#rx-pane-rows tr').filter({hasText:'HB9BLA K1ABC -05'}).waitFor();
  // #37 review: the confirmation popup is modal, so it carries HALT; clicking it halts at once.
  const popupMark=requests.length;
  await page.locator('#qso-cq').click();await page.locator('#op-confirm[open]').waitFor();
  assert.equal(await page.locator('#op-confirm-halt').isEnabled(),true,'popup HALT enabled like the top-bar HALT');
  await page.locator('#op-confirm-halt').click();
  await waitFor(()=>requests.slice(popupMark).some(r=>r.method==='POST'&&r.path==='/transmit/halt'),'halt from the confirmation popup');
  await waitFor(async()=>(await snapshot()).transmit.arm_state==='disarmed','disarmed by the popup HALT');
  assert.equal(await page.locator('#op-confirm[open]').count(),0,'HALT closes the popup');
  await new Promise(r=>setTimeout(r,300));
  assert.deepEqual(requests.slice(popupMark).filter(r=>r.method==='POST').map(r=>r.path),['/transmit/halt'],'the popup HALT sends only the halt; the CQ is not sent');
  // A panel is open; Esc in a text field halts (priority route) before cancelling and closes nothing.
  await page.locator('#station-bar [data-region=help]').click();
  assert.equal(await page.locator('#region-help').isVisible(),true);
  await page.locator('[data-region=operate]').first().focus();
  const mark=requests.length;
  await page.keyboard.press('Escape');
  await waitFor(async()=>(await snapshot()).contact.state==='cancelled','cancelled');
  await waitFor(()=>requests.slice(mark).some(r=>r.path==='/contact/command'),'cancel request observed');
  const after=requests.slice(mark).filter(r=>r.method==='POST');
  assert.deepEqual(after.map(r=>r.path),['/transmit/halt','/contact/command']);
  assert.equal(JSON.parse(after[1].body).action,'cancel');
  assert.equal(await page.locator('#region-help').isVisible(),true,'Esc closes no panel');
  assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
  const s=await snapshot();assert.equal(s.transmit.arm_state,'disarmed');assert.equal(s.contact.dx_call,null);
  const keys=await (await fetch(control+'/keys')).json();assert.ok(keys.length===0||keys.at(-1)===false,'PTT released after halt');
  await page.locator('.op-secondary:not([hidden]) .return-operate').click();
  assert.deepEqual(page.errors,[]);
});

test('TC-010-008 waterfall pointer actions and numeric frequency inputs',{timeout:60000},async()=>{
  const canvas=page.locator('#waterfall');
  // Measured at every action: station-bar text changes may move the signal area.
  let box;const at=hz=>({x:box.x+box.width*hz/3000,y:box.y+box.height/2});
  const clickAt=async(hz,options)=>{box=await canvas.boundingBox();const p=at(hz);await page.mouse.click(p.x,p.y,options);};
  const dblAt=async hz=>{box=await canvas.boundingBox();const p=at(hz);await page.mouse.dblclick(p.x,p.y);};
  const last=async(n=1)=>{await waitFor(()=>commands().length>=n,()=>`command ${n} ${JSON.stringify(requests.slice(-8).map(r=>[r.method,r.path,Math.round(r.at),r.end]))} now ${Math.round(performance.now())}`);return commands().at(-1);};
  const settle=async(field,hz)=>waitFor(async()=>(await snapshot()).settings[field]===hz,async()=>`${field} ${hz}: ${await page.locator('#contact-result').textContent()}`);
  let n=commands().length;
  await clickAt(1500);
  assert.deepEqual([(await last(n+1)).action,(await last(n+1)).rx_hz,(await last(n+1)).tx_hz],['set_frequency',1500,null]);await settle('rx_hz',1500);
  await page.locator('#waterfall-wrap .ct-rx').filter({hasText:/^Rx 1500/}).waitFor();
  n=commands().length;await page.keyboard.down('Shift');await clickAt(200);await page.keyboard.up('Shift');
  let c=await last(n+1);assert.deepEqual([c.rx_hz,c.tx_hz],[null,200]);await settle('tx_hz',200);
  n=commands().length;await page.keyboard.down('Control');await clickAt(2950);await page.keyboard.up('Control');
  c=await last(n+1);assert.deepEqual([c.rx_hz,c.tx_hz],[2950,2950]);await settle('tx_hz',2950);
  // Hold Tx only blocks implicit moves: an explicit right-click still moves Tx.
  await page.locator('#contact-hold').check();await waitFor(async()=>(await snapshot()).settings.hold_tx,'hold');
  n=commands().length;await clickAt(1000,{button:'right'});
  c=await last(n+1);assert.deepEqual([c.rx_hz,c.tx_hz],[null,1000]);await settle('tx_hz',1000);
  const prevented=await canvas.evaluate(el=>{const e=new MouseEvent('contextmenu',{bubbles:true,cancelable:true});el.dispatchEvent(e);return e.defaultPrevented;});
  assert.equal(prevented,true,'no context menu over the waterfall');
  await new Promise(r=>setTimeout(r,500));
  // #37 decision 7: a left double-click is two Rx clicks; no decode-at-point request.
  const dbl=performance.now();n=commands().length;await dblAt(700);
  await waitFor(()=>commands().slice(n).some(x=>x.action==='set_frequency'&&x.rx_hz===700),async()=>`redecode after ${JSON.stringify(commands().slice(n).map(x=>[x.action,x.rx_hz,x.tx_hz]))}: ${await page.locator('#contact-result').textContent()} ${JSON.stringify(requests.slice(-12).map(r=>[r.method,r.path,Math.round(r.at),r.end]))} now ${Math.round(performance.now())} ${JSON.stringify(await page.evaluate(()=>{const c=document.querySelector('#waterfall').getBoundingClientRect();const e=document.elementFromPoint(c.left+c.width*700/3000,c.top+c.height/2);return [e?.id||e?.className||e?.tagName,c.width,c.height];}))}`);
  const after=commands().slice(n).filter(x=>x.action!=='set_frequency'||x.rx_hz===700);
  assert.ok(after.some(x=>x.action==='set_frequency'&&x.rx_hz===700&&x.tx_hz===null));
  await new Promise(r=>setTimeout(r,800));assert.equal(commands().slice(n).some(x=>x.action==='redecode'),false,'no re-decode request');
  // Numeric inputs: 199/2951 refused with the domain, 200/2950 accepted.
  for(const [value,ok] of [[199,false],[200,true],[2951,false],[2950,true]]){
    await page.locator('#contact-tx').fill(String(value));await page.locator('#contact-tx').press('Tab');
    await page.locator('#contact-result').filter({hasText:ok?'Tx frequency: accepted':'out_of_range'}).waitFor();
  }
  assert.equal(commands().some(x=>x.action==='enable_tx'&&x.enabled),true,'only the earlier explicit Enable Tx');
  assert.equal(commands().filter(x=>x.action==='enable_tx'&&x.enabled).length,1,'no pointer action enables Tx');
  assert.deepEqual(page.errors,[]);
});

test('TC-010-009 UTC clock, Tx progress and Rx level from station.tick',{timeout:30000},async()=>{
  const label=page.locator('#radio-toolbar .op-period > span');
  await label.filter({hasText:/^UTC \d\d:\d\d:\d\d$/}).waitFor();
  const shown=(await label.textContent()).slice(4),now=new Date(),seconds=t=>{const [h,m,s]=t.split(':').map(Number);return h*3600+m*60+s;};
  const delta=Math.abs(seconds(shown)-seconds(now.toISOString().slice(11,19)));assert.ok(delta<=2||delta>=86398,`server UTC ${shown}`);
  assert.match(await page.locator('#radio-toolbar .op-period small').textContent(),/^\d{1,2}\/15/);
  // #37: the Rx level meter is in Settings > Radio > Audio; the top bar shows only a low/high chip.
  assert.equal(await page.locator('#settings-audio .op-input-meter strong').textContent(),'47 dB');
  assert.equal(await page.locator('#exception-chips [data-chip=level]').count(),0,'a normal level shows no chip');
  assert.deepEqual(page.errors,[]);
});

// #41 DirectLog: Log QSO logs at once on the actual server, without a review form.
test('TC-007-004 manual DX entry and Log QSO log the contact at once without hiding Halt Tx',{timeout:30000},async()=>{
  if(!await page.locator('#qso-more').evaluate(el=>el.open))await page.locator('#qso-more summary').click();
  await page.locator('#dx-call').fill('dl1abc');await page.locator('#dx-grid').fill('JO62');await page.locator('#dx-grid').press('Enter');
  await page.locator('#rx-focus .op-contact-identity strong').filter({hasText:'DL1ABC'}).waitFor();
  await page.locator('#dx-call').fill('AB1');await page.locator('#dx-call').press('Enter');
  await page.locator('#contact-result').filter({hasText:'invalid_call'}).waitFor();
  await page.getByRole('button',{name:'Log QSO'}).click();
  await page.locator('#contact-logged',{hasText:'Logged DL1ABC'}).waitFor();
  const log=await (await fetch(origin+'/contacts')).json();
  const id=(await snapshot()).contact.id;
  const records=log.records.filter(r=>r.contact_id===id);
  assert.equal(records.length,1,'exactly one record for the contact');
  assert.deepEqual([records[0].call,records[0].gridsquare,records[0].mode,records[0].station_callsign],['DL1ABC','JO62','FT8','HB9BLA']);
  assert.equal(await page.locator('#log-review').count(),0,'no review form');
  assert.equal(await page.locator('#operating-workspace').isVisible(),true,'the operating screen stays');
  assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
  assert.equal(mutations().some(r=>r.path==='/contacts'),false,'the server logs; the browser never saves');
  assert.deepEqual(page.errors,[]);
});

// Review finding P2-2: with the contact snapshot unavailable (GET /contact failing),
// Esc still sends the #9 halt; only a station known to be receive-only skips it.
test('TC-007-004 Esc halts even when the contact snapshot is unavailable',{timeout:60000},async()=>{
  await page.route('**/contact',route=>route.abort('failed'));
  await page.reload();await page.locator('#connection[data-state=connected]').waitFor();
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  const mark=requests.length;
  await page.keyboard.press('Escape');
  await waitFor(()=>requests.slice(mark).some(r=>r.method==='POST'&&r.path==='/transmit/halt'),'halt without snapshot');
  await new Promise(r=>setTimeout(r,500));
  assert.equal(requests.slice(mark).filter(r=>r.method==='POST'&&r.path==='/transmit/halt').length,1,'exactly one halt per Esc');
  const halt=JSON.parse(requests.slice(mark).find(r=>r.path==='/transmit/halt').body);
  const live=await (await fetch(origin+'/receive')).json();
  assert.equal(halt.profile_id,live.profile_id);assert.equal(halt.boot_id,live.boot_id);
  await page.unroute('**/contact');
  await page.reload();await page.locator('#connection[data-state=connected]').waitFor();
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000}).catch(async e=>{throw new Error(`contact client not loaded: ${JSON.stringify(await page.evaluate(()=>({scripts:[...document.scripts].map(s=>s.src),snapshot:typeof snapshot!=='undefined'&&!!snapshot,live:typeof live!=='undefined'?String(live):'undef'})))} errors ${JSON.stringify(page.errors)} requests ${JSON.stringify(requests.filter(r=>r.path.startsWith('/contact')).slice(-6).map(r=>[r.method,r.path,r.end]))}`);});
});

// Review decision 6 (OpenRegion) / #37 SettingsDrawer: a pointer action outside the drawer closes it.
test('TC-007-002 a pointer action outside the Settings drawer returns to operation',{timeout:30000},async()=>{
  if(await page.locator('#region-logbook').isVisible())await page.locator('#region-logbook .return-operate').click();
  await page.locator('#operating-workspace').waitFor({state:'visible'});
  await page.locator('#open-server-settings').click();
  assert.equal(await page.locator('#settings-drawer').isVisible(),true);
  await page.locator('#band-activity > header').click({timeout:5000});
  await page.locator('#settings-drawer').waitFor({state:'hidden'});
  assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
});

// Re-check item 2: the keyboard halt does not wait for contact.js (loaded after the first
// state reads); one Esc sends exactly one halt before and after that load.
test('TC-007-004 Esc halts once before and once after the contact client loads',{timeout:60000},async()=>{
  // Hold /contact.js so the first Esc happens deterministically before it loads.
  let release;const held=new Promise(r=>release=r);
  await page.route('**/contact.js',route=>held.then(()=>route.continue()).catch(()=>{}));
  await page.reload();await page.locator('#connection[data-state=connected]').waitFor();
  await waitFor(()=>requests.some(r=>r.path==='/contact.js'&&r.end===null),'contact.js requested and held');
  assert.equal(await page.evaluate(()=>!!window.wstxContact),false,'contact.js not loaded yet');
  const start=requests.length;
  await page.keyboard.press('Escape');
  await waitFor(()=>requests.slice(start).some(r=>r.method==='POST'&&r.path==='/transmit/halt'),'halt before contact.js');
  await new Promise(r=>setTimeout(r,500));
  assert.equal(requests.slice(start).filter(r=>r.method==='POST'&&r.path==='/transmit/halt').length,1);
  release();
  await waitFor(()=>page.evaluate(()=>!!window.wstxContact),'contact.js loaded');
  await page.unroute('**/contact.js');
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  const mark=requests.length;
  await page.keyboard.press('Escape');
  await waitFor(()=>requests.slice(mark).some(r=>r.method==='POST'&&r.path==='/transmit/halt'),'halt after contact.js');
  await new Promise(r=>setTimeout(r,800));
  assert.equal(requests.slice(mark).filter(r=>r.method==='POST'&&r.path==='/transmit/halt').length,1,'contact.js sends no second halt');
  assert.deepEqual(page.errors,[]);
});
