'use strict';
// CR #10 standard FT8 contact (WstxContact, OperatingLayout::ContactWorkspace). The server
// owns the contact, its sequence, next message, transmit requests, watchdogs and times;
// this browser renders the confirmed GET /contact snapshot, sends POST /contact/command
// requests and never runs a sequence timer, modem or QSO state machine. The UTC clock
// and Tx progress are interpolated locally from station.tick for display only.
(()=>{
const focus=document.querySelector('#rx-focus');
if(!focus||document.body.dataset.profile!=='true')return;
const body=focus.querySelector('.op-contact-body');
const identity=body.querySelector('.op-contact-identity');
for(const node of [...body.children])if(!node.matches('.op-contact-identity,.op-qso-steps,.op-receive-bubble'))node.remove();
const slots=['tx1','tx2','tx3','tx4','tx5','tx6'];
body.insertAdjacentHTML('beforeend',`<div class="ct-dx"><label>DX Call<input id="dx-call" maxlength="13" autocomplete="off" spellcheck="false"></label><label>DX Grid<input id="dx-grid" maxlength="6" autocomplete="off" spellcheck="false"></label><button type="button" id="dx-generate">Generate</button></div>
<p id="contact-state" class="ct-state" role="status">No contact</p>
<ol id="contact-messages" class="ct-messages" aria-label="Standard messages Tx1 to Tx6">${slots.map((s,i)=>`<li data-slot="${s}"><label class="ct-next"><input type="radio" name="contact-next" value="${s}" aria-label="Next message Tx${i+1}">Tx${i+1}</label><input class="ct-text" data-slot="${s}" maxlength="37" aria-label="Tx${i+1} message" autocomplete="off" spellcheck="false">${s==='tx1'?'<label class="op-check"><input type="checkbox" id="contact-tx1-skip">Skip Tx1</label>':''}${s==='tx4'?'<label class="op-check"><input type="checkbox" id="contact-rr73">RR73</label>':''}</li>`).join('')}</ol>
<div class="op-frequency-fields ct-fields"><label>Report<input id="contact-report" type="number" min="-50" max="49" step="1"><span>dB</span></label><label>Rx audio<input id="contact-rx" type="number" min="0" max="3000" step="1"><span>Hz</span></label><label>Tx audio<input id="contact-tx" type="number" min="200" max="2950" step="1"><span>Hz</span></label><label class="op-check"><input type="checkbox" id="contact-hold">Hold Tx</label><label>Tx period<select id="contact-parity"><option value="even">Even / 1st</option><option value="odd">Odd / 2nd</option></select></label></div>
<p class="ct-tx"><span>NEXT</span> <strong id="contact-next">None</strong> <span>LAST SENT</span> <strong id="contact-last">None</strong></p>
<div class="op-auto-row"><label class="op-check"><input type="checkbox" id="contact-auto" disabled aria-label="Auto sequence unavailable">Auto sequence</label><button type="button" id="contact-tune" disabled>Tune</button><span id="contact-watchdog" class="op-muted"></span></div>
<div class="op-contact-actions"><button type="button" id="contact-enable" class="op-primary" disabled aria-pressed="false" aria-describedby="transmit-unavailable" title="Enable Tx (Alt+N)"><span aria-hidden="true">&#9655;</span>Enable Tx</button><button type="button" id="contact-cancel" disabled>Cancel contact</button><button type="button" id="contact-log" disabled aria-describedby="contact-unavailable" title="Log QSO (Alt+Q)">Log QSO</button><button type="button" id="contact-discard" hidden>Discard log review</button></div>
<p id="transmit-unavailable" class="op-unavailable">Transmission unavailable: this server does not offer transmit control.</p><p id="contact-unavailable" class="op-unavailable">Log QSO needs a contact with a DX call.</p><p id="contact-result" class="op-muted" role="status"></p>
<section id="rx-pane" class="ct-pane" aria-labelledby="rx-pane-heading"><header><h4 id="rx-pane-heading">Rx Frequency <span id="rx-pane-unread"></span></h4><button type="button" id="rx-pane-resume" hidden>Resume following</button><button type="button" id="rx-pane-erase">Erase</button></header><div class="ct-pane-wrap" tabindex="0" aria-label="Rx Frequency messages"><table aria-label="Rx Frequency messages"><tbody id="rx-pane-rows"></tbody></table></div></section>`);
const $=id=>document.getElementById(id);
const resultText=$('contact-result');
let snap=null,sending=false,openedReviews=new Set(),tick=null,lastTx=null,changeTarget=null;
const valid=s=>s&&s.v===1&&Object.keys(s).sort().join(',')==='boot_id,contact,contact_revision,monotonic_ms,profile_id,review,settings,snapshot_sequence,transmit,utc_ms,v,watchdog'&&Number.isSafeInteger(s.contact_revision);
const transmitCapable=()=>snap&&snap.transmit.capability!=='unsupported';
// One GET /contact at a time; a caller during a pending GET waits for a fresh one.
let loading=null,queued=null;
function load(){
  if(!loading){loading=fetchSnapshot().finally(()=>{loading=null;});return loading;}
  if(!queued)queued=loading.then(()=>{queued=null;return load();});
  return queued;
}
async function fetchSnapshot(){
  try{
    const response=await stationFetch('/contact',{cache:'no-store',signal:AbortSignal.timeout(10000)});
    if(response.ok){const value=await response.json();if(valid(value)&&(!snap||snap.boot_id!==value.boot_id||value.snapshot_sequence>=snap.snapshot_sequence||value.contact_revision>=snap.contact_revision)){snap=value;render();}}
  }catch{}
}
const ids=()=>snap&&{v:1,profile_id:snap.profile_id,boot_id:snap.boot_id};
// Commands are sent one at a time, each with the revision of the latest snapshot.
let sendChain=Promise.resolve();
function send(...args){const run=sendChain.then(()=>sendNow(...args));sendChain=run.catch(()=>{});return run;}
async function sendNow(action,params={},label=action){
  if(!snap){resultText.textContent='Contact state unavailable';return null;}
  const body={...ids(),command_id:crypto.randomUUID(),contact_revision:snap.contact_revision,action,...params};
  resultText.textContent=`${label}: pending · waiting for the station`;sending=true;
  try{
    const response=await stationFetch('/contact/command',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);
    if(response.status===202||response.status===200){resultText.textContent=`${label}: accepted`;return data;}
    const code=data?.error?.code??`http_${response.status}`;
    resultText.textContent=`${label}: refused · ${code}${code==='stale_revision'?' · station state changed, review and retry':''}`;
    return {refused:code};
  }catch(error){resultText.textContent=`${label}: outcome unknown · ${error.message}`;return null;}
  finally{sending=false;await load();}
}
// Halt is skipped only when the station is known to be receive-only; with the contact
// snapshot unknown (not loaded, or GET /contact failing) it is always sent.
async function haltTx(){
  if(snap&&snap.transmit.capability==='unsupported')return false;
  const station=snap?{profile_id:snap.profile_id,boot_id:snap.boot_id}:profileData?{profile_id:profileData.profile_id,boot_id:profileData.boot_id}:null;
  if(!station){resultText.textContent='Halt not sent · station identity unknown';return false;}
  try{
    const response=await stationFetch('/transmit/halt',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,...station,command_id:crypto.randomUUID()}),signal:AbortSignal.timeout(5000)});
    const data=await response.json().catch(()=>null);
    resultText.textContent=response.status===202?`Halt: ${data?.halt_state==='stopped'?'stopped (confirmed)':data?.halt_state==='idle'?'nothing was transmitting':'pending · not yet confirmed'}`:`Halt refused · ${data?.error?.code??response.status}`;
  }catch(error){resultText.textContent=`Halt not confirmed · ${error.message}`;}
  return true;
}
// ---------------------------------------------------------------- render
const stateText={idle:'Idle',calling:'Calling CQ',replying:'Replying',report:'Sending report',roger_report:'Sending R+report',rogers:'Sending acknowledgement',signoff:'Signing off',completed:'Completed',cancelled:'Cancelled'};
function setValue(input,value){if(document.activeElement!==input)input.value=value??'';}
function render(){
  const c=snap?.contact,t=snap?.transmit,s=snap?.settings,capable=transmitCapable(),armed=t?.arm_state==='armed';
  focus.dataset.contact=c?.dx_call?'true':'';
  const strong=identity.querySelector('strong'),detail=identity.querySelector('div > span');
  if(c?.dx_call){strong.textContent=`${c.dx_call}${c.dx_grid?' · '+c.dx_grid:''}`;detail.textContent=`Report sent ${c.report_sent} · received ${c.report_rcvd??'none'}${c.saved?' · logged':''}`;}
  else if(c){strong.textContent=c.state==='calling'?'Calling CQ':'No contact selected';detail.textContent='Select a decoded station or enter a DX call.';}
  $('contact-state').textContent=!snap?'Contact state unavailable':c?`${stateText[c.state]??c.state} · next ${c.next_slot.toUpperCase()}${armed?' · Enable Tx on':' · Enable Tx off'}`:'No contact';
  focus.querySelector('header .op-muted').textContent=c?`${stateText[c.state]??c.state}${c.dx_call?' with '+c.dx_call:''}`:capable?'No active contact':'No active contact · transmission unavailable';
  focus.querySelector('.op-contact-badge').textContent=!snap?'Unavailable':armed?(tick?.transmitting?'Transmitting':'Enable Tx on'):c?.state==='completed'?'Completed':capable?'Ready':'Receive only';
  for(const [i,slot] of slots.entries()){
    const row=body.querySelector(`li[data-slot="${slot}"]`),text=row.querySelector('.ct-text'),radio=row.querySelector('input[type=radio]');
    const message=c?.messages?.[i]??null;setValue(text,message);text.disabled=!message;radio.disabled=!message;radio.checked=c?.next_slot===slot;
    row.classList.toggle('ct-next-row',c?.next_slot===slot);
  }
  $('contact-tx1-skip').checked=!!s?.tx1_skip;$('contact-rr73').checked=c?.tx4==='rr73';$('contact-rr73').disabled=!c?.dx_call;
  if(s){setValue($('contact-report'),s.report);setValue($('contact-rx'),s.rx_hz);setValue($('contact-tx'),s.tx_hz);$('contact-hold').checked=s.hold_tx;if(document.activeElement!==$('contact-parity'))$('contact-parity').value=s.parity;$('contact-auto').checked=s.auto_seq;}
  const auto=$('contact-auto');auto.disabled=!capable;if(capable)auto.setAttribute('aria-label','Auto sequence');else auto.setAttribute('aria-label','Auto sequence unavailable');
  const enable=$('contact-enable');enable.disabled=!capable;enable.setAttribute('aria-pressed',String(armed));enable.classList.toggle('ct-on',armed);
  if(capable)enable.removeAttribute('aria-describedby');else enable.setAttribute('aria-describedby','transmit-unavailable');
  $('transmit-unavailable').hidden=capable;
  $('transmit-unavailable').textContent=!snap?'Transmission unavailable: contact state unknown.':t?.capability==='unavailable'?'Transmission unavailable: radio/authorization not ready.':'Transmission unavailable: this server does not offer transmit control.';
  const tune=$('contact-tune');tune.disabled=!capable;tune.setAttribute('aria-pressed',String(!!t?.tune));tune.textContent=t?.tune?`Tune on · ${snap.watchdog.tune_remaining_seconds} s`:'Tune';
  $('contact-cancel').disabled=!c||['idle','cancelled'].includes(c.state);
  const log=$('contact-log');log.disabled=!c?.dx_call;$('contact-unavailable').hidden=!!c?.dx_call;
  if(c?.dx_call)log.removeAttribute('aria-describedby');else log.setAttribute('aria-describedby','contact-unavailable');
  $('contact-next').textContent=c?(c.messages[slots.indexOf(c.next_slot)]??'None'):'None';
  $('contact-last').textContent=t?.last_text?`${t.last_text}${t.last_period_utc?' · '+new Date(t.last_period_utc).toISOString().slice(11,19)+' UTC':''}`:'None';
  const wd=snap?.watchdog;$('contact-watchdog').textContent=!wd?'':wd.tx_expired?'Tx watchdog expired':armed?`WD:${wd.tx_remaining_minutes}m`:'';
  const problem=t?.refusal?` · refused ${t.refusal}`:'';const halt=t?.halt_state==='pending'?' · halt pending (RF stop not confirmed)':'';
  if(snap)$('contact-state').textContent+=problem+halt;
  markers();
  if(t?.last_text&&t.last_period_utc&&lastTx!==`${t.last_period_utc}/${t.last_text}`){if(lastTx!==null)paneTx(t.last_text,t.last_period_utc);lastTx=`${t.last_period_utc}/${t.last_text}`;}
  const pendingReview=snap?.review&&snap.review.outcome!=='saved';const discard=$('contact-discard');discard.hidden=!pendingReview;
  if(pendingReview)discard.textContent=`Discard log review ${snap.review.record.call}`;
  stationTx();
  paneUpdate();if(activity)for(const tr of activity.querySelectorAll('tr[data-sequence]'))if(!tr.hasAttribute('tabindex'))tr.tabIndex=0;
  const review=snap?.review;
  if(review&&!openedReviews.has(review.contact_id)&&review.outcome!=='saved'&&window.wstxLogbook){openedReviews.add(review.contact_id);window.wstxLogbook.openReview(review.record);}
}
// Compact transmit state in the station bar, visible in every region (review decision 5).
const stationTxNode=document.createElement('span');stationTxNode.id='station-tx';stationTxNode.className='ct-station-tx';stationTxNode.setAttribute('role','status');stationTxNode.hidden=true;
document.querySelector('#halt-tx')?.before(stationTxNode);
function stationTx(){
  const t=snap?.transmit,capable=transmitCapable();stationTxNode.hidden=!capable;if(!capable)return;
  const wd=snap.watchdog,armed=t.arm_state==='armed';
  stationTxNode.textContent=`${tick?.transmitting?'TRANSMITTING':armed?'Tx enabled':'Tx off'}${armed?` · WD:${wd.tx_remaining_minutes}m`:wd.tx_expired?' · Tx watchdog expired':''}${t.last_text?` · last ${t.last_text}`:''}`;
}
// OperatingLayout::OpenRegion: a pointer action outside an open secondary region returns to
// operation (the signal area of Recordings/Preferences and the station bar excepted).
document.addEventListener('pointerdown',event=>{
  if(typeof currentRegion==='undefined'||currentRegion==='operate')return;
  // A control outside the region acts on its own; closing first would move it away
  // from under the pointer.
  if(event.target.closest?.('.op-secondary,#station-bar,#signal,#splitter,button,input,select,textarea,a,label,summary,[tabindex]'))return;
  showRegion('operate');
},true);
// ---------------------------------------------------------------- controls
$('dx-generate').addEventListener('click',()=>enterDx(false));
for(const id of ['dx-call','dx-grid'])$(id).addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();enterDx(false);}});
async function enterDx(replace){
  const call=$('dx-call').value.trim(),grid=$('dx-grid').value.trim();
  if(!call){resultText.textContent='Enter a DX call first';return;}
  const reply=await send('enter_dx',{dx_call:call,dx_grid:grid===''?null:grid,replace},'DX call');
  if(reply?.refused==='contact_active')offerChange(()=>enterDx(true),call.toUpperCase());
}
function offerChange(run,call){
  changeTarget?.remove();const button=document.createElement('button');button.type='button';button.id='contact-change';button.textContent=`Change contact to ${call}`;
  button.addEventListener('click',()=>{button.remove();changeTarget=null;run();});resultText.after(button);changeTarget=button;
}
body.querySelector('#contact-messages').addEventListener('change',event=>{
  const radio=event.target.closest('input[type=radio]');if(radio){send('choose_next',{slot:radio.value},`Next ${radio.value.toUpperCase()}`);return;}
  const text=event.target.closest('.ct-text');if(text)send('edit_message',{slot:text.dataset.slot,text:text.value},`Edit ${text.dataset.slot.toUpperCase()}`);
});
$('contact-tx1-skip').addEventListener('change',event=>send('set_tx1_skip',{enabled:event.target.checked},'Skip Tx1'));
$('contact-rr73').addEventListener('change',event=>send('set_tx4',{form:event.target.checked?'rr73':'rrr'},'RRR/RR73'));
$('contact-report').addEventListener('change',event=>{const n=Number(event.target.value);if(Number.isInteger(n))send('set_report',{report:n},'Report');else resultText.textContent='Report must be a whole number of dB';});
for(const [id,key] of [['contact-rx','rx_hz'],['contact-tx','tx_hz']])$(id).addEventListener('change',event=>{const n=Number(event.target.value);if(!Number.isSafeInteger(n)||n<0){resultText.textContent='Frequency must be a whole number of Hz';return;}send('set_frequency',{rx_hz:key==='rx_hz'?n:null,tx_hz:key==='tx_hz'?n:null},key==='rx_hz'?'Rx frequency':'Tx frequency');});
$('contact-hold').addEventListener('change',event=>send('set_hold_tx',{enabled:event.target.checked},'Hold Tx'));
$('contact-parity').addEventListener('change',event=>send('set_parity',{parity:event.target.value},'Tx period'));
$('contact-auto').addEventListener('change',event=>send('set_auto_seq',{enabled:event.target.checked},'Auto sequence'));
$('contact-enable').addEventListener('click',()=>send('enable_tx',{enabled:snap?.transmit.arm_state!=='armed',safety_revision:snap?.transmit.safety_revision??null},'Enable Tx'));
$('contact-tune').addEventListener('click',()=>send('tune',{enabled:!snap?.transmit.tune},'Tune'));
$('contact-cancel').addEventListener('click',()=>send('cancel',{},'Cancel contact'));
async function logQso(){
  const c=snap?.contact;if(!c?.dx_call)return;
  if(snap.review?.contact_id===c.id&&window.wstxLogbook){window.wstxLogbook.openReview(snap.review.record);return;}
  openedReviews.delete(c.id);await send('open_log',{},'Log QSO');
}
$('contact-log').addEventListener('click',logQso);
// The offered review is the oldest unsaved one; discarding it shows the next.
$('contact-discard').addEventListener('click',()=>{const id=snap?.review?.contact_id;if(id)send('discard_review',{contact_id:id},'Discard log review');});
// Esc halts Tx and aborts the contact in every page state and focused field; it closes
// no panel (D5). On a receive-only station it only cancels. Alt+N/H/Q where delivered.
addEventListener('keydown',event=>{
  if(event.key==='Escape'){
    event.preventDefault();
    (async()=>{await haltTx();const c=snap?.contact;if(c&&!['idle','cancelled','completed'].includes(c.state))await send('cancel',{},'Cancel contact');})();
    return;
  }
  if(!event.altKey||event.ctrlKey||event.metaKey)return;
  const key=event.key.toLowerCase();
  if(key==='h'){event.preventDefault();haltTx();}
  else if(key==='n'&&transmitCapable()){event.preventDefault();$('contact-enable').click();}
  else if(key==='q'){event.preventDefault();logQso();}
},true);
// ---------------------------------------------------------------- Band Activity selection
const activity=document.querySelector('#band-activity tbody');
function rowIdentity(row){
  if(!live?.source||!live?.job)return null;const sequence=Number(row.dataset.sequence);if(!Number.isSafeInteger(sequence))return null;
  return {source_id:live.source.id,job_id:live.job.id,generation:live.generation,sequence};
}
async function selectRow(tr){
  const row=rowIdentity(tr);if(!row)return;
  const text=tr.children[4]?.textContent??'';
  const reply=await send('select_row',{row,replace:false},'Select station');
  if(reply?.refused==='contact_active')offerChange(()=>send('select_row',{row,replace:true},'Change contact'),text);
}
activity?.addEventListener('click',event=>{const tr=event.target.closest('tr[data-sequence]');if(tr)selectRow(tr);});
activity?.addEventListener('keydown',event=>{const tr=event.target.closest('tr[data-sequence]');if(tr&&event.key==='Enter'){event.preventDefault();selectRow(tr);}});
// ---------------------------------------------------------------- Rx Frequency pane
// WstxContact::RoutesToRxFrequencyPane: within +/-10 Hz of the confirmed Rx offset, the
// first call equal to my call, or my call followed by the DX call. At most 500 rows.
const pane=$('rx-pane-rows'),paneWrap=body.querySelector('.ct-pane-wrap');let paneSeen=new Set(),paneContext=null,paneUnread=0,paneFollow=true;
const myCall=()=>(profileData?.settings?.callsign??'').trim().toUpperCase();
function routes(record){
  const rx=snap?.settings?.rx_hz;const my=myCall(),dx=snap?.contact?.dx_call;
  const f=record.fields,to=f?.type==='standard'&&f.to?.kind==='call'?f.to.text:null;
  if(typeof rx==='number'&&record.frequency_hz>=rx-10&&record.frequency_hz<=rx+10)return true;
  if(my&&to===my)return true;
  return !!(my&&dx&&typeof record.text==='string'&&record.text.split(' ').some((w,i,a)=>w===my&&a[i+1]===dx));
}
function paneAppend(cells,kind){
  const tr=document.createElement('tr');tr.dataset.kind=kind;
  for(const text of cells){const td=document.createElement('td');td.textContent=text;tr.append(td);}
  pane.append(tr);while(pane.children.length>500)pane.firstElementChild.remove();
  if(paneFollow)paneWrap.scrollTop=paneWrap.scrollHeight;else{paneUnread++;showUnread();}
}
function paneTx(text,utc){paneAppend([new Date(utc).toISOString().slice(11,19),'Tx','','',text],'tx');}
function showUnread(){$('rx-pane-unread').textContent=paneUnread?`· ${paneUnread} new`:'';$('rx-pane-resume').hidden=paneFollow;}
paneWrap.addEventListener('scroll',()=>{const atEnd=paneWrap.scrollTop+paneWrap.clientHeight>=paneWrap.scrollHeight-4;if(atEnd!==paneFollow){paneFollow=atEnd;if(atEnd)paneUnread=0;showUnread();}});
$('rx-pane-resume').addEventListener('click',()=>{paneFollow=true;paneUnread=0;paneWrap.scrollTop=paneWrap.scrollHeight;showUnread();});
function paneClear(){pane.replaceChildren();paneSeen=new Set();paneUnread=0;paneFollow=true;showUnread();}
$('rx-pane-erase').addEventListener('click',paneClear);
function paneUpdate(){
  // Routing needs the confirmed Rx offset: rows wait until the snapshot is known.
  if(!snap||typeof resultRows==='undefined'||!live?.job)return;
  const context=`${profileData?.profile_id}/${live.job.mode}/${operatingState?.selection?.band??''}`;
  if(context!==paneContext){paneClear();paneContext=context;}
  const ordered=[...resultRows].sort((a,b)=>a.sequence-b.sequence);
  for(const record of ordered){
    const key=`${liveIdentity(live)}/${record.sequence}`;if(paneSeen.has(key))continue;paneSeen.add(key);
    if(record.status!=='decoded'||!routes(record))continue;
    paneAppend([periodLabel(record.period_start_utc,live.job.mode),record.snr_db===null?'—':record.snr_db.toFixed(0),record.dt_seconds===null?'—':record.dt_seconds.toFixed(1),record.frequency_hz.toFixed(0),record.text],'rx');
    const dx=snap?.contact?.dx_call;
    if(dx&&record.fields?.from?.text===dx)body.querySelector('.op-receive-bubble p').textContent=record.text;
  }
}
if(activity)new MutationObserver(()=>{for(const tr of activity.querySelectorAll('tr[data-sequence]'))if(!tr.hasAttribute('tabindex'))tr.tabIndex=0;paneUpdate();}).observe(activity,{childList:true});
// ---------------------------------------------------------------- waterfall pointer actions
// WstxContact::PointerEffect: click Rx; shift- or right-click Tx; ctrl-click Rx and Tx;
// left double-click Rx and Re-decode; right double-click Rx and Tx. Markers move only
// after confirmation; no pointer action enables Tx.
const waterfall=document.querySelector('#waterfall'),wrap=document.querySelector('#waterfall-wrap');
const rxMarker=document.createElement('div'),txMarker=document.createElement('div');
rxMarker.className='ct-marker ct-rx';txMarker.className='ct-marker ct-txm';rxMarker.setAttribute('aria-hidden','true');txMarker.setAttribute('aria-hidden','true');
wrap?.append(rxMarker,txMarker);
// Labels only where the waterfall has room for them (no clipped text at 360 px/200 %).
if(wrap)new ResizeObserver(()=>markers()).observe(wrap);
function markers(){
  const s=snap?.settings,room=!wrap||wrap.clientHeight>=3*parseFloat(getComputedStyle(rxMarker).fontSize||'14');
  for(const [m,hz,label] of [[rxMarker,s?.rx_hz,'Rx'],[txMarker,s?.tx_hz,'Tx']]){m.hidden=typeof hz!=='number';if(typeof hz==='number'){m.style.left=`${hz/30}%`;m.textContent=room?`${label} ${hz}`:'';m.dataset.hz=String(hz);m.title=`${label} ${hz} Hz`;}}
  // Close markers share one label so the texts never overlap.
  if(room&&s&&Math.abs(s.rx_hz-s.tx_hz)<400){rxMarker.textContent=s.rx_hz===s.tx_hz?`Rx/Tx ${s.rx_hz}`:`Rx ${s.rx_hz} · Tx ${s.tx_hz}`;txMarker.textContent='';}
}
const pointerHz=event=>{const box=waterfall.getBoundingClientRect();return Math.max(0,Math.min(3000,Math.round((event.clientX-box.left)/box.width*3000)));};
let lastRight=0,lastLeft={at:-Infinity,x:0};
function pointer(rx,tx,label){send('set_frequency',{rx_hz:rx,tx_hz:tx},label);}
waterfall?.addEventListener('contextmenu',event=>event.preventDefault());
waterfall?.addEventListener('click',event=>{
  if(event.button!==0)return;const hz=pointerHz(event),now=performance.now();
  // Left double-click, detected here (the browser click count also counts other
  // buttons): Rx, then Re-decode.
  const double=now-lastLeft.at<400&&Math.abs(event.clientX-lastLeft.x)<6;lastLeft=double?{at:-Infinity,x:0}:{at:now,x:event.clientX};
  if(double){send('set_frequency',{rx_hz:hz,tx_hz:null},'Rx frequency').then(()=>send('redecode',{},'Re-decode'));return;}
  if(event.ctrlKey)pointer(hz,hz,'Rx and Tx frequency');else if(event.shiftKey)pointer(null,hz,'Tx frequency');else pointer(hz,null,'Rx frequency');
});
waterfall?.addEventListener('mouseup',event=>{
  if(event.button!==2)return;const hz=pointerHz(event),now=performance.now();
  if(now-lastRight<400){lastRight=0;pointer(hz,hz,'Rx and Tx frequency');}else{lastRight=now;pointer(null,hz,'Tx frequency');}
});
// ---------------------------------------------------------------- UTC clock, Tx progress, Rx level
const period=document.querySelector('#radio-toolbar .op-period'),meter=document.querySelector('#radio-toolbar .op-input-meter');
function displays(){
  if(!period||!meter)return;
  const label=period.querySelector('span'),small=period.querySelector('small'),track=period.querySelector('.op-period-track');
  if(!tick){label.textContent='Receive period';small.textContent='Timing unavailable';meter.querySelector('strong').textContent='Unknown';return;}
  const stale=connection.dataset.state!=='connected',utc=tick.utc+(performance.now()-tick.at),seconds=tick.period/1000;
  const elapsed=Math.floor((utc%tick.period)/1000);
  label.textContent=`UTC ${new Date(utc).toISOString().slice(11,19)}${stale?' (stale)':''}`;
  small.textContent=`${elapsed}/${seconds}${tick.transmitting?' · Transmitting':''}${stale?' · stale':''}`;
  period.classList.toggle('ct-transmitting',!!tick.transmitting);
  track.style.setProperty('--ct-progress',`${Math.min(100,100*elapsed/seconds)}%`);
  const level=tick.level,strong=meter.querySelector('strong');
  strong.textContent=level===null?'Unavailable':`${level} dB${level>85?' high':level<15?' low':''}`;
  meter.dataset.level=level===null?'':level>85?'high':level<15?'low':'ok';
}
setInterval(displays,250);
// ---------------------------------------------------------------- station events
// Reconnect (a new socket) reloads the authoritative snapshot; a status refresh on the
// same socket does not (contact.state announces every change).
let readySocket=null;
addEventListener('station-ready',event=>{if(event.detail===readySocket&&snap&&snap.boot_id===profileData?.boot_id)return;readySocket=event.detail;load();});
addEventListener('station-stale',()=>{displays();});
addEventListener('station-message',event=>{
  const {message,current}=event.detail;if(current!==socket)return;
  const d=message.data;
  if(message.type==='contact.state'&&d&&(!snap||d.contact_revision!==snap.contact_revision||d.boot_id!==snap.boot_id))load();
  else if(message.type==='station.tick'&&d&&Number.isSafeInteger(d.utc_ms)&&[15000,7500].includes(d.period_ms)){
    const changed=tick?.transmitting!==d.transmitting;
    tick={utc:d.utc_ms,at:performance.now(),period:d.period_ms,transmitting:d.transmitting===true,level:Number.isInteger(d.rx_level_db)?d.rx_level_db:null};
    displays();if(changed)render();else stationTx();
  }
});
render();
if(socket?.readyState===WebSocket.OPEN&&connection.dataset.state==='connected'){readySocket=socket;load();}
window.wstxContact=Object.freeze({load,snapshot:()=>snap});
})();
