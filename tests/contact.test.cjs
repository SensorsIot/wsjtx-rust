'use strict';
// Cost2: launched by contact_http_tests::contact_browser_operating_flow with the actual
// candidate Router, contact engine and #9 transmit owner on a recording hardware double
// (no audio, PTT or radio). Decoded rows are hand-authored and published through the
// test-only control peer; expected values below are the independent TC tables.
// Proves: CL-010-01, CL-010-02, CL-010-03, CL-010-06, CL-010-11, CL-010-14; TC-007-001,
// TC-007-003, TC-007-004, TC-010-008, TC-010-009; CL-050-01, TC-050-001; CL-050-04, TC-050-004.
// Proves: CL-055-02; TC-055-004 (DXCC column, approximate distance, QSO header).
const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const crypto=require('node:crypto');
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
test('TC-007-003 QSO pane candidates and TC-007-001 selection without transmit',{timeout:90000},async()=>{
  const period=evenNow();
  await publish(period,[
    {text:'CQ K1ABC FN42',hz:1234.6,snr:-12.4},{text:'CQ W1AA FN31',hz:1449.9,snr:-1},{text:'CQ W2BB FN31',hz:1450.0,snr:-2},
    {text:'CQ W3CC FN31',hz:1489.9,snr:-3},{text:'CQ W4DD FN31',hz:1510.1,snr:-4},{text:'CQ W5EE FN31',hz:1550.0,snr:4.6},
    {text:'HB9BLA W1XYZ -10',hz:400,snr:-10},{text:'HB9BL K1ABC -01',hz:2600,snr:-9},{text:'CQ DL1ABC JO62',hz:800,snr:-3}]);
  const rows=page.locator('#band-activity tbody tr[data-sequence]');
  await waitFor(async()=>await rows.count()===9,'nine Band Activity rows',30000);
  // #55 TC-055-004: the DXCC column from the station's cty.dat entity (United States
  // 37.60 N 91.87 W, Germany; cty.dat lines 1251/669) and, without a grid in the
  // message, the distance from the country position, marked approximate (~): JN47AA to
  // 37.60 N 91.87 W is 7706 km by hand haversine.
  const dxcc=text=>rows.filter({hasText:text}).first().evaluate(tr=>[tr.children[5].textContent,tr.children[5].title,tr.children[6].textContent]);
  assert.deepEqual(await dxcc('HB9BLA W1XYZ -10'),['U.S.A.','U.S.A. \u00b7 NA \u00b7 CQ zone 5 \u00b7 ITU zone 8 (cty.dat)','~7706 km']);
  assert.equal((await dxcc('CQ DL1ABC JO62'))[0],'Germany');
  assert.doesNotMatch((await dxcc('CQ K1ABC FN42'))[2],/~/,'a message grid gives the exact distance');
  // #37 QsoPane, no contact (operator 2026-11-02): only the stations calling my call, on any
  // frequency, with their period start and SNR; never the CQs near Rx or HB9BL.
  // Proves: CL-050-05; TC-050-005 (Others).
  const others=async()=>page.locator('#qso-others tr').evaluateAll(rows=>rows.map(tr=>[tr.dataset.kind,[...tr.cells].map(td=>td.textContent)]));
  await waitFor(async()=>(await others()).length===1,async()=>`QSO pane ${JSON.stringify(await others())}`);
  const recv=String.fromCharCode(0x25C2),minus=String.fromCharCode(0x2212),hms=new Date(period).toISOString().slice(11,19);
  assert.deepEqual(await others(),[['candidate',[hms,`HB9BLA ${recv} W1XYZ`,'-10','',`${minus}10`,`${minus}10`]]]);
  assert.equal(await page.locator('#qso-others-none').isVisible(),false);
  // Local sorting: no request. The DX entry is in the QSO fold-out.
  const before=requests.length;
  await page.locator('#band-activity th[data-sort=signal]').click();await page.locator('#qso-more summary').click();
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
  // #55 TC-055-004: the QSO pane header names the partner's country and continent, first on
  // its detail line; the header line stays call and grid.
  await page.locator('#rx-focus .op-contact-identity div > span').filter({hasText:/^U\.S\.A\. \(NA\) \u00b7 \d+ km \u00b7 sent /}).waitFor();
  assert.equal(await page.locator('#rx-focus .op-contact-identity strong').textContent(),'K1ABC · FN42');
  const texts=await page.locator('#contact-messages .ct-text').evaluateAll(inputs=>inputs.map(i=>i.value));
  assert.deepEqual(texts,['K1ABC HB9BLA JN47','K1ABC HB9BLA -12','K1ABC HB9BLA R-12','K1ABC HB9BLA RRR','K1ABC HB9BLA 73','CQ HB9BLA JN47']);
  assert.equal(await page.locator('input[name=contact-next][value=tx1]').isChecked(),true);
  assert.equal(await page.locator('#contact-rx').inputValue(),'1235');assert.equal(await page.locator('#contact-tx').inputValue(),'1235');
  assert.equal(await page.locator('#contact-parity').inputValue(),'odd');
  assert.deepEqual(await page.locator('#waterfall-wrap .ct-marker').evaluateAll(ms=>ms.map(m=>[m.dataset.key,m.getAttribute('aria-valuenow'),m.textContent])),[['rx','1235',''],['tx','1235','']],'#50: unlabelled lines at the selected frequency');
  assert.equal((await snapshot()).transmit.arm_state,'disarmed','selection alone never arms');
  assert.equal(requests.some(r=>r.method==='POST'&&r.path.startsWith('/transmit')),false,'no transmit request from selection');
  assert.equal(commands().some(c=>c.action==='enable_tx'),false);
  assert.deepEqual(page.errors,[]);
});

test('TC-007-001 double-click starts transmission, partner report advances to Tx3, Esc aborts the QSO (no halt) with a panel open',{timeout:90000},async()=>{
  // #37 WstxContact::SetEnableTx: no Enable Tx control and no Reply button (gone since the #50
  // double-click fix); a double-click on the decoded row selects it again and arms.
  assert.equal(await page.locator('#contact-enable,#qso-reply').count(),0);
  const shown=(await snapshot()).transmit.safety_revision;
  await page.locator('#band-activity tbody tr[data-sequence]').filter({hasText:'CQ K1ABC FN42'}).dblclick();
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
  // #37: the partner's report is the pane's last partner message, with its SNR.
  await page.locator('#qso-heard').filter({hasText:`HB9BLA K1ABC -05  ${String.fromCharCode(0x2212)}7 dB`}).waitFor();
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
  // #39 Abort QSO: a panel is open; Esc in a text field aborts the QSO (one contact
  // command, no halt) and closes nothing.
  await page.locator('#station-bar [data-region=help]').click();
  assert.equal(await page.locator('#region-help').isVisible(),true);
  await page.locator('[data-region=operate]').first().focus();
  const mark=requests.length,haltBefore=(await snapshot()).transmit.halt_state;
  await page.keyboard.press('Escape');
  await waitFor(async()=>(await snapshot()).contact.state==='cancelled','cancelled');
  await waitFor(()=>requests.slice(mark).some(r=>r.path==='/contact/command'),'cancel request observed');
  const after=requests.slice(mark).filter(r=>r.method==='POST');
  assert.deepEqual(after.map(r=>r.path),['/contact/command'],'Esc sends no halt');
  assert.equal(JSON.parse(after[0].body).action,'abort');
  assert.equal(await page.locator('#region-help').isVisible(),true,'Esc closes no panel');
  assert.equal((await snapshot()).transmit.halt_state,haltBefore,'not halted');
  assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
  const s=await snapshot();assert.equal(s.transmit.arm_state,'disarmed');assert.equal(s.contact.dx_call,null);
  const keys=await (await fetch(control+'/keys')).json();assert.ok(keys.length===0||keys.at(-1)===false,'PTT released after the abort');
  await page.locator('.op-secondary:not([hidden]) .return-operate').click();
  // #39 Abort QSO: the visible button beside HALT does the same, and the station stays ready.
  await page.locator('#band-activity tbody tr[data-sequence]').filter({hasText:'CQ K1ABC FN42'}).dblclick();
  await waitFor(async()=>(await snapshot()).transmit.arm_state==='armed','armed again');
  const button=page.getByRole('button',{name:'Abort QSO (Esc)',exact:true}).locator('visible=true');
  await button.first().waitFor();assert.equal(await button.first().isEnabled(),true);
  const buttonMark=requests.length;
  await button.first().click();
  await waitFor(async()=>(await snapshot()).contact.state==='cancelled','cancelled by the button');
  const sent=requests.slice(buttonMark).filter(r=>r.method==='POST');
  assert.deepEqual(sent.map(r=>r.path),['/contact/command'],'the button sends no halt');assert.equal(JSON.parse(sent[0].body).action,'abort');
  assert.equal((await snapshot()).transmit.arm_state,'disarmed');
  await page.locator('#band-activity tbody tr[data-sequence]').filter({hasText:'CQ K1ABC FN42'}).dblclick();
  await waitFor(async()=>(await snapshot()).transmit.arm_state==='armed','ready: the next QSO arms');
  await page.keyboard.press('Escape');
  await waitFor(async()=>(await snapshot()).transmit.arm_state==='disarmed','disarmed by Esc');
  assert.deepEqual(page.errors,[]);
});

test('TC-010-008 TC-050-001 waterfall click sets Tx, double-click sets Rx and Tx, 3 px lines and numeric inputs',{timeout:60000},async()=>{
  const canvas=page.locator('#waterfall');
  // Measured at every action: station-bar text changes may move the signal area.
  let box;const at=hz=>({x:box.x+box.width*hz/3000,y:box.y+box.height/2});
  const clickAt=async(hz,options)=>{box=await canvas.boundingBox();const p=at(hz);await page.mouse.click(p.x,p.y,options);};
  const dblAt=async hz=>{box=await canvas.boundingBox();const p=at(hz);await page.mouse.dblclick(p.x,p.y);};
  const last=async(n=1)=>{await waitFor(()=>commands().length>=n,()=>`command ${n} ${JSON.stringify(requests.slice(-8).map(r=>[r.method,r.path,Math.round(r.at),r.end]))} now ${Math.round(performance.now())}`);return commands().at(-1);};
  const settle=async(field,hz)=>waitFor(async()=>(await snapshot()).settings[field]===hz,async()=>`${field} ${hz}: ${await page.locator('#contact-result').textContent()}`);
  // #50 PointerEffect: click sets Tx (after the 250 ms double-click wait), double-click sets Rx and Tx.
  let n=commands().length;
  await clickAt(1500);
  let c=await last(n+1);assert.deepEqual([c.action,c.rx_hz,c.tx_hz],['set_frequency',null,1500]);await settle('tx_hz',1500);
  const tx=page.locator('#waterfall-wrap .ct-txm');await page.waitForFunction(()=>document.querySelector('#waterfall-wrap .ct-txm').getAttribute('aria-valuenow')==='1500');
  assert.deepEqual(await tx.evaluate(m=>[m.textContent,getComputedStyle(m).borderLeftWidth,getComputedStyle(m).borderLeftColor]),['','3px','rgb(255, 64, 64)'],'a 3 px red Tx line without text');
  assert.deepEqual(await page.locator('#waterfall-wrap .ct-rx').evaluate(m=>[m.textContent,getComputedStyle(m).borderLeftWidth,getComputedStyle(m).borderLeftColor]),['','3px','rgb(48, 208, 80)'],'a 3 px green Rx line without text');
  // A double-click sends exactly one request for both, none for its two clicks.
  n=commands().length;await dblAt(700);
  c=await last(n+1);assert.deepEqual([c.rx_hz,c.tx_hz],[700,700]);await settle('rx_hz',700);
  await new Promise(r=>setTimeout(r,600));assert.equal(commands().length,n+1,'one request for a double-click');
  assert.equal(commands().slice(n).some(x=>x.action==='redecode'),false,'no re-decode request');
  // Modifiers no longer change the effect; Hold Tx only blocks implicit moves, so a click still moves Tx.
  await page.locator('#contact-hold').check();await waitFor(async()=>(await snapshot()).settings.hold_tx,'hold');
  n=commands().length;await page.keyboard.down('Shift');await clickAt(1000);await page.keyboard.up('Shift');
  c=await last(n+1);assert.deepEqual([c.rx_hz,c.tx_hz],[null,1000]);await settle('tx_hz',1000);
  n=commands().length;await clickAt(2950,{button:'right'});await new Promise(r=>setTimeout(r,600));
  assert.equal(commands().length,n,'a right-click sets nothing');
  const prevented=await canvas.evaluate(el=>{const e=new MouseEvent('contextmenu',{bubbles:true,cancelable:true});el.dispatchEvent(e);return e.defaultPrevented;});
  assert.equal(prevented,true,'no context menu over the waterfall');
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
  // #50: the period progress is the QSO pane's NEXT bar only (its width follows the period).
  assert.equal(await page.locator('#radio-toolbar .op-period small, #radio-toolbar .op-period-track').count(),0);
  assert.match(await page.locator('#qso-progress').evaluate(b=>b.style.width),/^\d+(\.\d+)?%$/);
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
  assert.equal(await page.getByRole('button',{name:'HALT',exact:true}).isVisible(),true,'the QSO pane HALT, the one HALT of the operating view (#37)');
  assert.equal(mutations().some(r=>r.path==='/contacts'),false,'the server logs; the browser never saves');
  assert.deepEqual(page.errors,[]);
});

// Review finding P2-2: with the contact snapshot unavailable (GET /contact failing),
// Alt+H still sends the #9 halt; only a station known to be receive-only skips it.
test('TC-007-004 Alt+H halts even when the contact snapshot is unavailable',{timeout:60000},async()=>{
  await page.route('**/contact',route=>route.abort('failed'));
  await page.reload();await page.locator('#connection[data-state=connected]').waitFor();
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  const mark=requests.length;
  await page.keyboard.press('Alt+h');
  await waitFor(()=>requests.slice(mark).some(r=>r.method==='POST'&&r.path==='/transmit/halt'),'halt without snapshot');
  await new Promise(r=>setTimeout(r,500));
  assert.equal(requests.slice(mark).filter(r=>r.method==='POST'&&r.path==='/transmit/halt').length,1,'exactly one halt per Alt+H');
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
  assert.equal(await page.getByRole('button',{name:'HALT',exact:true}).isVisible(),true,'the QSO pane HALT, the one HALT of the operating view (#37)');
});

// Re-check item 2: the keyboard halt does not wait for contact.js (loaded after the first
// state reads); one Alt+H sends exactly one halt before and after that load.
test('TC-007-004 Alt+H halts once before and once after the contact client loads',{timeout:60000},async()=>{
  // Hold /contact.js so the first Esc happens deterministically before it loads.
  let release;const held=new Promise(r=>release=r);
  await page.route('**/contact.js',route=>held.then(()=>route.continue()).catch(()=>{}));
  await page.reload();await page.locator('#connection[data-state=connected]').waitFor();
  await waitFor(()=>requests.some(r=>r.path==='/contact.js'&&r.end===null),'contact.js requested and held');
  assert.equal(await page.evaluate(()=>!!window.wstxContact),false,'contact.js not loaded yet');
  const start=requests.length;
  await page.keyboard.press('Alt+h');
  await waitFor(()=>requests.slice(start).some(r=>r.method==='POST'&&r.path==='/transmit/halt'),'halt before contact.js');
  await new Promise(r=>setTimeout(r,500));
  assert.equal(requests.slice(start).filter(r=>r.method==='POST'&&r.path==='/transmit/halt').length,1);
  release();
  await waitFor(()=>page.evaluate(()=>!!window.wstxContact),'contact.js loaded');
  await page.unroute('**/contact.js');
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  const mark=requests.length;
  await page.keyboard.press('Alt+h');
  await waitFor(()=>requests.slice(mark).some(r=>r.method==='POST'&&r.path==='/transmit/halt'),'halt after contact.js');
  await new Promise(r=>setTimeout(r,800));
  assert.equal(requests.slice(mark).filter(r=>r.method==='POST'&&r.path==='/transmit/halt').length,1,'contact.js sends no second halt');
  assert.deepEqual(page.errors,[]);
});

// #55 live defect 2026-11-02: K1WY's RR73 arrived packed as the grid square RR73 (32373) and
// showed an exact 5435 km (JN37VL to RR73). RR73 is the roger, never a grid: that row shows
// the entity distance marked approximate like the report row; only the CQ grid is exact.
// JN47AA to FN31 is 6188 km by hand haversine; U.S.A. is ~7706 km (see TC-007-003 above).
test('TC-055-004 RR73 sent as a grid square is no grid for the distance, in either order',{timeout:60000},async()=>{
  const rows3=[{text:'KW8CW K1WY RR73',hz:1620.6,snr:-14,exchange_raw:32373},{text:'CQ K1WY FN31',hz:1620.6,snr:-19},{text:'SP6E K1WY +00',hz:1620.6,snr:-14}];
  const expected={'KW8CW K1WY RR73':'~7706 km','CQ K1WY FN31':'6188 km','SP6E K1WY +00':'~7706 km'};
  for(const [offset,order] of [[0,rows3],[15000,[...rows3].reverse()]]){
    const {sequences}=await publish(evenNow()+offset,order);
    for(const [i,row] of order.entries()){
      const tr=page.locator(`#band-activity tbody tr[data-sequence="${sequences[i]}"]`);
      await tr.waitFor({timeout:30000});
      assert.deepEqual(await tr.evaluate(t=>[t.children[4].textContent,t.children[5].textContent,t.children[6].textContent]),[row.text,'U.S.A.',expected[row.text]],JSON.stringify(order.map(r=>r.text)));
    }
  }
  assert.deepEqual(page.errors,[]);
});

// Proves: CL-050-04; TC-050-004 (b). #50 (operator 2026-11-02, US5WFL then YO3GNF;
// TC2TR): as WSJT-X (handleDecodeSelection with quick_call), a double-click on another
// station mid-QSO or during my CQ switches at once, without a confirmation, keeps Enable Tx
// on, and the next own period calls the new station; Auto Seq then runs that QSO to its
// completion and it is logged once. The station runs on the real clock, so each step
// waits for the transmission (#9 transmit view last_text, set when its audio starts).
const sentTo=async text=>(await snapshot()).transmit.last_text===text;
async function dblclickRow(text,hz,snr){
  const {sequences}=await publish(evenNow(),[{text,hz,snr}]);
  const tr=page.locator(`#band-activity tbody tr[data-sequence="${sequences[0]}"]`);await tr.waitFor({timeout:30000});
  const mark=requests.length;await tr.dblclick();
  return mark;
}
async function completes(call,report){
  const period=30000+15000;
  await waitFor(()=>sentTo(`${call} HB9BLA JN47`),`Tx1 to ${call}`,period);
  await publish(evenNow(),[{text:`HB9BLA ${call} -05`,hz:900,snr:-5}]);
  await waitFor(()=>sentTo(`${call} HB9BLA R${report}`),`Tx3 to ${call}`,period);
  await publish(evenNow(),[{text:`HB9BLA ${call} RR73`,hz:900,snr:-5}]);
  await waitFor(()=>sentTo(`${call} HB9BLA 73`),`Tx5 to ${call}`,period);
  const done=await waitFor(async()=>{const s=await snapshot();return s.contact?.state==='completed'&&s;},'completed',period);
  assert.equal(done.contact.dx_call,call);
  const log=await (await fetch(origin+'/contacts')).json();
  assert.equal(log.records.filter(r=>r.contact_id===done.contact.id).length,1,`${call} logged once`);
  // The pane shows the completion (its snapshot is current) before the next action.
  await page.locator('#contact-logged').filter({hasText:`Logged ${call}`}).waitFor({timeout:15000});
}
// The browser part (b)/(c) runs as two tests, mid-QSO (then CQ right after the completed
// contact, the #61 stale_revision path) and from-CQ (then (c) after the completed contact),
// each on its own station and browser started by contact_browser_operating_flow, so that
// their real-clock periods elapse concurrently (harness#28); every step and assertion is kept.
// Proves: CL-010-15; TC-007-005 (#10 pushed transmit state, browser subset). The actual
// station pushes transmit.state; the page reads GET /transmit once per socket, once per
// announced change and not on a timer while the view is unchanged.
test('TC-007-005 transmit state is pushed: one GET /transmit per socket, one per announced change, no 1 s poll',{timeout:60000},async()=>{
  const frames=[];page.on('websocket',ws=>ws.on('framereceived',e=>{try{const m=JSON.parse(e.payload);if(m.type==='transmit.state')frames.push({at:performance.now(),revision:m.data.transmit_revision});}catch{}}));
  const reads=since=>requests.filter(r=>r.method==='GET'&&r.path==='/transmit'&&r.at>=since);
  const sleep=ms=>new Promise(r=>setTimeout(r,ms));
  const loaded=performance.now();await page.reload();await page.locator('#connection[data-state=connected]').waitFor();
  await sleep(8000);
  assert.equal(reads(loaded).length,1,'one snapshot read per socket');
  assert.ok(frames.some(f=>f.at>=loaded),'transmit.state at the first step');
  const idle=performance.now();await sleep(10000);
  assert.equal(reads(idle).length,0,'no timer read while the view is unchanged');
  const live=await (await fetch(origin+'/receive')).json();
  const watchdogs=async tx_calls=>{const r=await fetch(origin+'/transmit/command',{method:'POST',headers:{'Content-Type':'application/json',Origin:origin},body:JSON.stringify({v:1,profile_id:live.profile_id,boot_id:live.boot_id,command_id:crypto.randomUUID(),action:'set_watchdogs',tx_calls,tune_seconds:90})});assert.equal(r.status,200,await r.text());};
  const changed=performance.now();await watchdogs(8);
  await waitFor(async()=>await page.evaluate(()=>transmitView?.watchdog?.tx_calls)===8,'pushed change read',5000);
  assert.ok(frames.some(f=>f.at>=changed),'the change is announced');
  await sleep(1500);
  assert.equal(reads(changed).length,1,'one read per announced change');
  await watchdogs(6);await waitFor(async()=>await page.evaluate(()=>transmitView?.watchdog?.tx_calls)===6,'restored',5000);
  assert.deepEqual(page.errors,[]);
});

test('TC-050-004 mid-QSO: a double-click switches mid-QSO with Tx kept on, the new QSO completes, and CQ right after it calls',{timeout:420000},async()=>{
  // Mid-QSO: calling K1ABC (armed), K1ABC does not answer, double-click DL1ABC.
  let mark=await dblclickRow('CQ K1ABC FN42',1234.6,-12);
  await waitFor(async()=>{const s=await snapshot();return s.transmit.arm_state==='armed'&&s.contact?.dx_call==='K1ABC';},'armed with K1ABC',15000);
  await waitFor(()=>sentTo('K1ABC HB9BLA JN47'),'Tx1 to K1ABC',45000);
  mark=await dblclickRow('CQ DL1ABC JO62',800,-3);
  await waitFor(async()=>(await snapshot()).contact?.dx_call==='DL1ABC',async()=>`switched to DL1ABC: ${await page.locator('#contact-result').textContent()} ${JSON.stringify(commands().slice(-3))} ${JSON.stringify((await snapshot()).contact)}`,15000);
  const switched=requests.slice(mark).filter(r=>r.method==='POST'&&r.path==='/contact/command').map(r=>JSON.parse(r.body));
  await waitFor(async()=>requests.slice(mark).some(r=>r.path==='/contact/command'&&JSON.parse(r.body).action==='enable_tx'),'enable_tx after the switch');
  // A stale_revision refusal (the revision moves with every transmit step) is retried, so a
  // request may repeat; the sequence is select_row (replace) then enable_tx.
  assert.deepEqual(requests.slice(mark).filter(r=>r.method==='POST'&&r.path==='/contact/command').map(r=>JSON.parse(r.body)).map(c=>[c.action,c.replace??c.enabled]).filter((c,i,a)=>i===0||JSON.stringify(c)!==JSON.stringify(a[i-1])),[['select_row',true],['enable_tx',true]],JSON.stringify(switched));
  assert.equal(await page.locator('#contact-change').count(),0,'no confirmation button');
  const s=await snapshot();assert.equal(s.transmit.arm_state,'armed','Enable Tx stays on');
  assert.notEqual(s.transmit.last_disarm_cause,'contact_cancelled');
  await completes('DL1ABC','-03');
  // CQ right after the completed contact, while its revision still moves (#61 CL-061-02).
  await page.locator('#qso-cq').click();
  await waitFor(async()=>{const v=await snapshot();return v.transmit.arm_state==='armed'&&v.contact?.state==='calling';},async()=>`calling CQ after DL1ABC: ${await page.locator('#contact-result').textContent()} ${JSON.stringify(commands().slice(-2))} ${JSON.stringify((await snapshot()).transmit)} ${JSON.stringify((await snapshot()).contact?.state)}`,15000);
  assert.deepEqual(page.errors,[]);
});
test('TC-050-004 from-CQ: a double-click from my CQ switches with Tx kept on, the new QSO completes, and a double-click after it replies',{timeout:420000},async()=>{
  let mark;
  // From my CQ: CQ (arms, calling), then double-click another station's CQ.
  await page.locator('#qso-cq').click();
  await waitFor(async()=>{const v=await snapshot();return v.transmit.arm_state==='armed'&&v.contact?.state==='calling';},async()=>`calling CQ: ${await page.locator('#contact-result').textContent()} ${JSON.stringify(commands().slice(-2))} ${JSON.stringify((await snapshot()).transmit)} ${JSON.stringify((await snapshot()).contact?.state)}`,15000);
  await page.locator('#rx-focus .op-contact-identity strong').filter({hasText:'Calling CQ'}).waitFor();
  mark=await dblclickRow('CQ EA8BIA IL18',1595,0);
  await waitFor(async()=>(await snapshot()).contact?.dx_call==='EA8BIA','answered EA8BIA',15000);
  assert.equal((await snapshot()).transmit.arm_state,'armed');
  assert.equal(await page.locator('#contact-change').count(),0,'no confirmation button');
  await completes('EA8BIA','+00');
  // (c) #50 operator 2026-11-03 (G8KHF after the completed G6WCX): after a completed
  // contact (disarmed, contact_completed) a double-click whose second press sees the Band
  // Activity rows redrawn (a result page arrived; the browser then drops that click and the
  // dblclick) still replies: select_row with replace true, then enable_tx, then Tx1.
  const done=await snapshot();assert.equal(done.transmit.arm_state,'disarmed');assert.equal(done.transmit.last_disarm_cause,'contact_completed');
  const {sequences}=await publish(evenNow(),[{text:'CQ G8KHF IO92',hz:1888,snr:3}]);
  const g8=page.locator(`#band-activity tbody tr[data-sequence="${sequences[0]}"]`);await g8.waitFor({timeout:30000});
  const box=await g8.locator('td[data-col=message]').boundingBox(),x=box.x+box.width/2,y=box.y+box.height/2;
  mark=requests.length;
  await page.mouse.move(x,y);await page.mouse.down({clickCount:1});await page.mouse.up({clickCount:1});
  await page.mouse.down({clickCount:2});await page.evaluate(()=>renderResults());await page.mouse.up({clickCount:2});
  await waitFor(async()=>requests.slice(mark).some(r=>r.path==='/contact/command'&&JSON.parse(r.body).action==='enable_tx'),async()=>`enable_tx after the double-click: ${JSON.stringify(commands().slice(-3))}`);
  assert.deepEqual(requests.slice(mark).filter(r=>r.method==='POST'&&r.path==='/contact/command').map(r=>JSON.parse(r.body)).map(c=>[c.action,c.replace??c.enabled]).filter((c,i,a)=>i===0||JSON.stringify(c)!==JSON.stringify(a[i-1])),[['select_row',true],['enable_tx',true]]);
  await waitFor(async()=>{const s=await snapshot();return s.transmit.arm_state==='armed'&&s.contact?.dx_call==='G8KHF';},'armed with G8KHF',15000);
  await waitFor(()=>sentTo('G8KHF HB9BLA JN47'),'Tx1 to G8KHF',45000);
  assert.deepEqual(page.errors,[]);
});

// Proves: CL-040-08; TC-012-008. #40: inbound UDP Highlight Callsign and Clear reach Band
// Activity and the QSO pane as WSJT-X 3.3 applies them (widgets/displaytext.cpp
// highlight_callsign; Clear windows 0/1/2), sent as real NetworkMessage datagrams from two
// loopback peers to the station's own UDP owner (contact_browser_operating_flow starts it for
// this test only, with no target): one with accept_commands on (the tool), one with it off.
// Datagrams are packed here by hand (QDataStream big-endian), not by the station's codec.
const dgram=require('node:dgram');
const qstring=s=>{const b=Buffer.from(s,'utf8'),n=Buffer.alloc(4);n.writeUInt32BE(b.length);return Buffer.concat([n,b]);};
const nmDatagram=(type,body)=>{const h=Buffer.alloc(12);h.writeUInt32BE(0xADBCCBDA,0);h.writeUInt32BE(2,4);h.writeUInt32BE(type,8);return Buffer.concat([h,qstring('WSTX-Rust'),...body]);};
// QColor: spec (1 Rgb, 0 invalid), alpha, red, green, blue (16 bit), pad.
const qcolor=hex=>{const b=Buffer.alloc(11);if(hex){b.writeUInt8(1,0);b.writeUInt16BE(0xffff,1);for(let i=0;i<3;i++)b.writeUInt16BE(parseInt(hex.slice(1+2*i,3+2*i),16)*257,3+2*i);}return b;};
const highlightCall=(call,bg,fg,last=false)=>nmDatagram(13,[qstring(call),qcolor(bg),qcolor(fg),Buffer.from([last?1:0])]);
const clearWindow=w=>nmDatagram(3,[Buffer.from([w])]);
test('TC-012-008 UDP Highlight Callsign colours Band Activity rows and Clear empties its view, only from an accepting target',{timeout:120000},async()=>{
  const open=()=>new Promise(r=>{const s=dgram.createSocket('udp4');s.bind(0,'127.0.0.1',()=>r(s));});
  const tool=await open(),other=await open();
  try{
    const stationPort=s=>new Promise(r=>s.once('message',(m,info)=>r(info.port)));
    const toolPort=stationPort(tool),otherPort=stationPort(other);
    const udp=await (await fetch(origin+'/udp')).json();
    const target=(s,accept)=>({address:`127.0.0.1:${s.address().port}`,enabled:true,multicast_ttl:1,multicast_interface:null,messages:['heartbeat'],accept_commands:accept});
    const put=await fetch(origin+'/udp',{method:'PUT',headers:{'Content-Type':'application/json',Origin:origin},body:JSON.stringify({v:1,profile_id:udp.profile_id,boot_id:udp.boot_id,expected_revision:udp.revision,configuration:{instance_name:'WSTX-Rust',targets:[target(other,false),target(tool,true)]}})});
    assert.equal(put.status,200,await put.text());
    const ports=new Map([[tool,await toolPort],[other,await otherPort]]);
    const send=(s,bytes)=>new Promise((resolve,reject)=>s.send(bytes,ports.get(s),'127.0.0.1',e=>e?reject(e):resolve()));
    const lastCommand=async i=>(await (await fetch(origin+'/udp')).json()).status[i].last_command;
    const row=seq=>page.locator(`#band-activity tbody tr[data-sequence="${seq}"]`);
    const look=seq=>row(seq).evaluate(tr=>({udp:tr.dataset.udp??null,hl:tr.dataset.hl??null,bg:getComputedStyle(tr.children[4]).backgroundColor,fg:getComputedStyle(tr.children[4]).color}));
    const until=async(seq,predicate,label)=>waitFor(async()=>{const v=await look(seq);return predicate(v)&&v;},async()=>`${label}: ${JSON.stringify(await look(seq))}`,10000);

    const p1=evenNow();
    const {sequences:[k1,w1,d1]}=await publish(p1,[{text:'CQ K1ABC FN42',hz:1000,snr:-10},{text:'CQ W1AW FN31',hz:1200,snr:-8},{text:'HB9BLA DL1XYZ JO62',hz:1400,snr:-6}]);
    for(const s of [k1,w1,d1])await row(s).waitFor({timeout:30000});
    const base={k1:await look(k1),w1:await look(w1),d1:await look(d1)};
    assert.match(base.d1.hl??'',/\bmycall\b/,'the row calling me carries the My call slot');

    // accept_commands off: the station refuses it and the row keeps its colour.
    await send(other,highlightCall('K1ABC','#ff0000','#ffffff'));
    await waitFor(async()=>(await lastCommand(0))?.outcome==='not_accepted','not_accepted from the other target');
    // Highlight last period only, background only: the period of the latest decode.
    await send(tool,highlightCall('W1AW','#00ff00',null,true));
    const w1lit=await until(w1,v=>v.udp==='W1AW','W1AW highlighted');
    assert.deepEqual([w1lit.bg,w1lit.fg],['rgb(0, 255, 0)',base.w1.fg],'background set, foreground left as it was');
    assert.deepEqual(await look(k1),base.k1,'nothing from the target without accept_commands');
    // A map entry (case-insensitive) wins over the My call slot: background and foreground.
    await send(tool,highlightCall('dl1xyz','#0000ff','#ffff00'));
    const d1lit=await until(d1,v=>v.udp==='DL1XYZ','DL1XYZ highlighted');
    assert.deepEqual([d1lit.hl,d1lit.bg,d1lit.fg],[null,'rgb(0, 0, 255)','rgb(255, 255, 0)']);

    // The next period: the map entry colours the new row too, the last-period one does not.
    const {sequences:[w2,d2]}=await publish(p1+15000,[{text:'CQ W1AW FN31',hz:1200,snr:-7},{text:'HB9BLA DL1XYZ R-05',hz:1400,snr:-5}]);
    for(const s of [w2,d2])await row(s).waitFor({timeout:30000});
    assert.equal((await look(w2)).udp,null,'last period only: not the newer period');
    assert.equal((await look(w1)).bg,'rgb(0, 255, 0)','the older period below keeps it');
    assert.deepEqual(await look(d2).then(v=>[v.udp,v.bg]),['DL1XYZ','rgb(0, 0, 255)']);
    // Highlight last without colours: a reset in the latest period only; the map entry stays.
    await send(tool,highlightCall('DL1XYZ',null,null,true));
    const d2reset=await until(d2,v=>v.udp===null,'DL1XYZ reset in the latest period');
    assert.match(d2reset.hl??'',/\bmycall\b/,'the reset row has its slot colour');
    assert.deepEqual(await look(d1).then(v=>[v.udp,v.bg]),['DL1XYZ','rgb(0, 0, 255)'],'the earlier period keeps the map colour');
    // Both colours invalid: the highlight is removed and the slot colour returns.
    await send(tool,highlightCall('DL1XYZ',null,null));
    await until(d1,v=>v.udp===null,'DL1XYZ removed');
    assert.deepEqual(await look(d1),base.d1,'the My call slot colour is back');
    // A station restart (another boot) drops the earlier boot's display state.
    await send(tool,highlightCall('K1ABC','#ff00ff',null));
    await until(k1,v=>v.udp==='K1ABC','K1ABC highlighted');
    await page.evaluate(()=>{profileData={...profileData,boot_id:'00000000-0000-4000-8000-000000000000'};renderResults();});
    assert.deepEqual(await look(k1),base.k1,'no highlight of another boot');
    await page.evaluate(b=>{profileData={...profileData,boot_id:b};renderResults();},udp.boot_id);
    assert.equal((await look(k1)).udp,'K1ABC');
    await send(tool,highlightCall('K1ABC',null,null));
    await until(k1,v=>v.udp===null,'K1ABC removed');

    // Clear window 1 (Rx Frequency): the QSO pane's callers go, Band Activity stays.
    const others=page.locator('#qso-others tr');
    await waitFor(async()=>await others.count()>0,'DL1XYZ calls me in the QSO pane');
    await send(tool,clearWindow(1));
    await waitFor(async()=>await others.count()===0,'Rx Frequency cleared');
    assert.equal(await page.locator('#band-activity tbody tr[data-sequence]').count(),5,'Band Activity kept');
    // Clear window 0 (Band Activity): its rows go; a later decode shows again.
    await send(tool,clearWindow(0));
    await waitFor(async()=>await page.locator('#band-activity tbody tr[data-sequence]').count()===0,'Band Activity cleared');
    const {sequences:[k3]}=await publish(p1+30000,[{text:'CQ K1ABC FN42',hz:1000,snr:-9}]);
    await row(k3).waitFor({timeout:30000});
    assert.equal(await page.locator('#band-activity tbody tr[data-sequence]').count(),1);
    assert.deepEqual(page.errors,[]);
  }finally{tool.close();other.close();}
});
