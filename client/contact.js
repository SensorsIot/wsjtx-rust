'use strict';
// CR #10 standard FT8 contact (WstxContact) in the #37 operating screen
// (WstxOperatingLayout::QsoPane, RxTxStrip, BandActivityView). The server owns the contact,
// its sequence, next message, transmit requests, watchdogs and times; this browser renders
// the confirmed GET /contact snapshot, sends POST /contact/command requests and never runs a
// sequence timer, modem or QSO state machine. The UTC clock, period progress and countdown
// are interpolated locally from station.tick for display only. recording.js builds the
// markup; this client binds it.
(()=>{
const focus=document.querySelector('#rx-focus');
if(!focus||document.body.dataset.profile!=='true')return;
const $=id=>document.getElementById(id);
// SettingsDrawer sections served by this client: MCP/automation, transmit watchdogs and
// Logging & Reporting (each appended at the end of its section).
block('settings-automation','MCP and automation',document.querySelector('#settings-general'),'<p class="op-muted">Automation runs on the station (MCP). Its state shows beside the strategy element; HALT ends it. Strategies (Highlight/Auto) arrive with the strategy engine.</p>');
block('settings-transmit','Transmit',document.querySelector('#settings-radio'),'<label>Tx watchdog (minutes)<input id="watchdog-tx" type="number" min="1" max="99" step="1" disabled></label><label>Tune watchdog (seconds)<input id="watchdog-tune" type="number" min="1" max="300" step="1" disabled></label><p id="watchdog-result" class="op-muted" role="status"></p><p class="op-muted">Watchdogs apply at once, as in WSJT-X. Tx power is set on the transceiver; this station sends no power command. PTT is chosen under CAT.</p>');
block('settings-log','Log',document.querySelector('#settings-logging'),'<p>Each logged QSO is saved in this station profile’s contacts.adi (ADIF). Log QSO opens the log review.</p><button type="button" data-region="logbook">&#9776; Open Logbook</button>');
block('settings-udp','WSJT-X UDP interface',document.querySelector('#settings-logging'),'<p class="op-muted">Not available yet (separate change): targets, message selection and accepted commands.</p>');
block('settings-pskreporter','PSK Reporter',document.querySelector('#settings-logging'),'<p class="op-muted">Not available yet.</p>');
// QsoPane fold-out: Tx1-Tx6, report, period and Auto Seq in place (built with the contact client).
const slotsMarkup=['tx1','tx2','tx3','tx4','tx5','tx6'];
focus.querySelector('.op-contact-body').insertAdjacentHTML('beforeend',`<details id="qso-more"><summary>Messages Tx1&ndash;Tx6, report and period</summary><ol id="contact-messages" class="ct-messages" aria-label="Standard messages Tx1 to Tx6">${slotsMarkup.map((s,i)=>`<li data-slot="${s}"><label class="ct-next"><input type="radio" name="contact-next" value="${s}" aria-label="Next message Tx${i+1}" disabled>Tx${i+1}</label><input class="ct-text" data-slot="${s}" maxlength="37" aria-label="Tx${i+1} message" autocomplete="off" spellcheck="false" disabled>${s==='tx1'?'<label class="op-check"><input type="checkbox" id="contact-tx1-skip" disabled>Skip Tx1</label>':''}${s==='tx4'?'<label class="op-check"><input type="checkbox" id="contact-rr73" disabled>RR73</label>':''}</li>`).join('')}</ol>
<div class="op-frequency-fields ct-fields"><label>Report<input id="contact-report" type="number" min="-50" max="49" step="1" disabled><span>dB</span></label><label>Tx period<select id="contact-parity" disabled><option value="even">Even / 1st</option><option value="odd">Odd / 2nd</option></select></label><label class="op-check"><input type="checkbox" id="contact-auto" disabled aria-label="Auto sequence unavailable">Auto sequence</label><button type="button" id="contact-cancel" disabled>Cancel contact</button><button type="button" id="contact-discard" hidden>Discard log review</button><span id="contact-watchdog" class="op-muted"></span></div></details>`);
const body=focus.querySelector('.op-contact-body'),identity=focus.querySelector('.op-contact-identity');
const slots=['tx1','tx2','tx3','tx4','tx5','tx6'];
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
// The keyboard halt itself (Esc, Alt+H) is sent by recording.js, which is loaded at
// once; this client only shows its outcome and adds the Esc contact cancellation.
addEventListener('keyboard-halt',event=>{
  const h=event.detail?.reply?.halt_state;
  if(h)resultText.textContent=`Halt: ${h==='stopped'?'stopped (confirmed)':h==='idle'?'nothing was transmitting':'pending · not yet confirmed'}`;
  const c=snap?.contact;
  if(event.detail?.escape&&c&&!['idle','cancelled','completed'].includes(c.state))send('cancel',{},'Cancel contact');else load();
});
// ---------------------------------------------------------------- render
const stateText={idle:'Idle',calling:'Calling CQ',replying:'Replying',report:'Sending report',roger_report:'Sending R+report',rogers:'Sending acknowledgement',signoff:'Signing off',completed:'Completed',cancelled:'Cancelled'};
const transmitting=c=>!!c&&!['idle','completed','cancelled'].includes(c.state);
function setValue(input,value){if(document.activeElement!==input)input.value=value??'';}
function render(){
  const c=snap?.contact,t=snap?.transmit,s=snap?.settings,capable=transmitCapable(),armed=t?.arm_state==='armed';
  focus.dataset.contact=c?.dx_call?'true':'';
  const strong=identity.querySelector('strong'),detail=identity.querySelector('div > span');
  if(c?.dx_call){
    const km=c.dx_grid&&typeof distanceKm==='function'?distanceKm(profileData?.settings?.locator,c.dx_grid):null;
    strong.textContent=`${c.dx_call}${c.dx_grid?' · '+c.dx_grid:''}`;
    detail.textContent=`Report sent ${c.report_sent} · received ${c.report_rcvd??'none'}${km!==null?` · ${km} km`:''}${c.saved?' · logged':''}`;
  }
  else if(c){strong.textContent=c.state==='calling'?'Calling CQ':'No contact selected';detail.textContent='Select a decoded station or enter a DX call.';}
  for(const id of ['dx-call','dx-grid','dx-generate','contact-report','contact-parity','contact-tx1-skip','contact-rx','contact-tx','contact-hold','strip-tx-from-rx','strip-rx-from-tx'])$(id).disabled=!snap;
  for(const button of document.querySelectorAll('#rxtx-strip [data-strip-step]'))button.disabled=!snap;
  $('contact-state').textContent=!snap?'Contact state unavailable':c?`${stateText[c.state]??c.state} · next ${c.next_slot.toUpperCase()}${armed?' · transmitting':''}`:'No contact';
  focus.querySelector('.op-contact-badge').textContent=!snap?'Unavailable':armed?(tick?.transmitting?'Transmitting':'Tx on'):c?.state==='completed'?'Completed':capable?'Ready':'Receive only';
  focus.dataset.armed=String(armed);
  for(const [i,slot] of slots.entries()){
    const row=body.querySelector(`li[data-slot="${slot}"]`),text=row.querySelector('.ct-text'),radio=row.querySelector('input[type=radio]');
    const message=c?.messages?.[i]??null;setValue(text,message);text.disabled=!message;radio.disabled=!message;radio.checked=c?.next_slot===slot;
    row.classList.toggle('ct-next-row',c?.next_slot===slot);
  }
  $('contact-tx1-skip').checked=!!s?.tx1_skip;$('contact-rr73').checked=c?.tx4==='rr73';$('contact-rr73').disabled=!c?.dx_call;
  if(s){setValue($('contact-report'),s.report);setValue($('contact-rx'),s.rx_hz);setValue($('contact-tx'),s.tx_hz);$('contact-hold').checked=s.hold_tx;if(document.activeElement!==$('contact-parity'))$('contact-parity').value=s.parity;$('contact-auto').checked=s.auto_seq;
    setValue($('watchdog-tx'),s.tx_minutes);setValue($('watchdog-tune'),s.tune_seconds);}
  $('watchdog-tx').disabled=$('watchdog-tune').disabled=!snap;
  const auto=$('contact-auto');auto.disabled=!capable;auto.setAttribute('aria-label',capable?'Auto sequence':'Auto sequence unavailable');
  // WstxContact::SetEnableTx (#37): no Enable Tx control; the direct buttons start a QSO.
  const prepared=!!c?.dx_call&&transmitting(c);
  $('qso-cq').disabled=!capable||(armed&&c?.state==='calling');
  $('qso-reply').disabled=!capable||!prepared||armed;
  $('qso-rr73').disabled=$('qso-73').disabled=!capable||!c?.dx_call||c.state==='cancelled';
  for(const id of ['qso-cq','qso-reply','qso-rr73','qso-73','contact-tune'])if(capable)$(id).removeAttribute('aria-describedby');else $(id).setAttribute('aria-describedby','transmit-unavailable');
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
  stationTx();countdown();
  paneUpdate();if(activity)for(const tr of activity.querySelectorAll('tr[data-sequence]'))if(!tr.hasAttribute('tabindex'))tr.tabIndex=0;
  const review=snap?.review;
  if(review&&!openedReviews.has(review.contact_id)&&review.outcome!=='saved'&&window.wstxLogbook){openedReviews.add(review.contact_id);window.wstxLogbook.openReview(review.record);}
}
// Compact transmit state in the top bar, shown only while transmission is on or expired.
const stationTxNode=document.createElement('span');stationTxNode.id='station-tx';stationTxNode.className='ct-station-tx';stationTxNode.setAttribute('role','status');stationTxNode.hidden=true;
document.querySelector('#halt-tx')?.before(stationTxNode);
// WstxMcp::AutomationIndicator: the run state sits in the strategy element; HALT ends it.
const automationNode=$('station-automation');
let automationLoading=null;
function loadAutomation(){
  if(automationLoading)return automationLoading;
  automationLoading=stationFetch('/automation',{cache:'no-store',signal:AbortSignal.timeout(10000)}).then(r=>r.ok?r.json():null).then(a=>{
    const run=a?.v===1?a.run:null,active=run&&run.state!=='stopped';
    automationNode.dataset.active=String(!!active);
    automationNode.textContent=active?`Automation ${run.state==='waiting'?'waiting':'in contact'} · run ${String(run.id).slice(0,8)} · HALT ends it`:'Automation idle';
  }).catch(()=>{}).finally(()=>{automationLoading=null;});
  return automationLoading;
}
function stationTx(){
  const t=snap?.transmit,capable=transmitCapable(),wd=snap?.watchdog,armed=t?.arm_state==='armed';
  stationTxNode.hidden=!capable||!(armed||tick?.transmitting||wd?.tx_expired);if(stationTxNode.hidden)return;
  stationTxNode.textContent=`${tick?.transmitting?'TRANSMITTING':armed?'Tx on':'Tx off'}${armed?` · WD:${wd.tx_remaining_minutes}m`:wd.tx_expired?' · Tx watchdog expired':''}${t.last_text?` · last ${t.last_text}`:''}`;
}
// OperatingLayout::OpenRegion: a pointer action outside an open page returns to operation
// (the top bar excepted); the Settings drawer closes the same way (recording.js).
document.addEventListener('pointerdown',event=>{
  if(typeof currentRegion==='undefined'||currentRegion==='operate')return;
  if(event.target.closest?.('.op-secondary,#station-bar,#signal,#splitter,dialog,button,input,select,textarea,a,label,summary,[tabindex]'))return;
  showRegion('operate');
},true);
// ---------------------------------------------------------------- QSO commands
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
// Starting a QSO means transmitting: enable_tx with the safety revision the operator sees,
// so grant, clock, period and revision checks stay with the station.
const arm=label=>send('enable_tx',{enabled:true,safety_revision:snap?.transmit.safety_revision??null},label);
$('qso-cq').addEventListener('click',async()=>{
  const c=snap?.contact;
  if(c?.dx_call&&transmitting(c)){
    if(!await confirmAction(`Abandon the QSO with ${c.dx_call} and call CQ?`,'Call CQ'))return;
    const reply=await send('cancel',{},'Cancel contact');if(!reply||reply.refused)return;
  }
  arm('CQ');
});
$('qso-reply').addEventListener('click',()=>arm('Reply'));
async function finalMessage(slot,label){
  const c=snap?.contact;if(!c?.dx_call)return;
  if(slot==='tx4'&&c.tx4!=='rr73'){const r=await send('set_tx4',{form:'rr73'},'RR73');if(!r||r.refused)return;}
  const r=await send('choose_next',{slot},label);if(!r||r.refused)return;
  if(snap?.transmit.arm_state!=='armed')arm(label);
}
$('qso-rr73').addEventListener('click',()=>finalMessage('tx4','RR73'));
$('qso-73').addEventListener('click',()=>finalMessage('tx5','73'));
body.querySelector('#contact-messages').addEventListener('change',event=>{
  const radio=event.target.closest('input[type=radio]');if(radio){send('choose_next',{slot:radio.value},`Next ${radio.value.toUpperCase()}`);return;}
  const text=event.target.closest('.ct-text');if(text)send('edit_message',{slot:text.dataset.slot,text:text.value},`Edit ${text.dataset.slot.toUpperCase()}`);
});
$('contact-tx1-skip').addEventListener('change',event=>send('set_tx1_skip',{enabled:event.target.checked},'Skip Tx1'));
$('contact-rr73').addEventListener('change',event=>send('set_tx4',{form:event.target.checked?'rr73':'rrr'},'RRR/RR73'));
$('contact-report').addEventListener('change',event=>{const n=Number(event.target.value);if(Number.isInteger(n))send('set_report',{report:n},'Report');else resultText.textContent='Report must be a whole number of dB';});
$('contact-parity').addEventListener('change',event=>send('set_parity',{parity:event.target.value},'Tx period'));
$('contact-auto').addEventListener('change',event=>send('set_auto_seq',{enabled:event.target.checked},'Auto sequence'));
$('contact-tune').addEventListener('click',()=>send('tune',{enabled:!snap?.transmit.tune},'Tune'));
$('contact-cancel').addEventListener('click',()=>send('cancel',{},'Cancel contact'));
// Settings > Radio > Transmit: watchdogs are operative changes and apply at once.
for(const id of ['watchdog-tx','watchdog-tune'])$(id).addEventListener('change',async()=>{
  const tx=Number($('watchdog-tx').value),tune=Number($('watchdog-tune').value);
  if(!Number.isInteger(tx)||!Number.isInteger(tune)){$('watchdog-result').textContent='Watchdogs must be whole numbers';return;}
  await send('set_watchdogs',{tx_minutes:tx,tune_seconds:tune},'Watchdogs');$('watchdog-result').textContent=resultText.textContent;
});
async function logQso(){
  const c=snap?.contact;if(!c?.dx_call)return;
  if(snap.review?.contact_id===c.id&&window.wstxLogbook){window.wstxLogbook.openReview(snap.review.record);return;}
  openedReviews.delete(c.id);await send('open_log',{},'Log QSO');
}
$('contact-log').addEventListener('click',logQso);
// The offered review is the oldest unsaved one; discarding it shows the next.
$('contact-discard').addEventListener('click',()=>{const id=snap?.review?.contact_id;if(id)send('discard_review',{contact_id:id},'Discard log review');});
// WstxOperatingLayout::KeyboardShortcuts (WSJT-X keys where the function exists). Esc and
// Alt+H halt from recording.js in every state; Esc closes no panel.
const typing=target=>!!target?.closest?.('input:not([type=checkbox]):not([type=radio]):not([type=range]),textarea,select,[contenteditable=true]');
function nudge(rx,tx,label){const s=snap?.settings;if(!s)return;send('set_frequency',{rx_hz:rx===null?null:Math.max(0,Math.min(3000,s.rx_hz+rx)),tx_hz:tx===null?null:s.tx_hz+tx},label);}
addEventListener('keydown',event=>{
  if(event.key==='Escape'){event.preventDefault();return;}
  if(event.key==='F4'){event.preventDefault();if(snap?.contact&&!['idle','cancelled'].includes(snap.contact.state))send('cancel',{},'Clear DX');return;}
  if(event.key==='F11'||event.key==='F12'){
    event.preventDefault();const sign=event.key==='F11'?-1:1,ft4=tick?.period===7500;
    if(event.shiftKey)nudge(null,sign*(ft4?90:60),'Tx frequency');else if(event.ctrlKey)nudge(sign,sign,'Rx and Tx frequency');else nudge(sign,null,'Rx frequency');
    return;
  }
  if(!event.altKey||event.ctrlKey||event.metaKey)return;
  const key=event.key.toLowerCase();
  if(key==='q'){event.preventDefault();logQso();}
  else if(key==='t'&&transmitCapable()){event.preventDefault();$('contact-tune').click();}
  else if(/^[1-6]$/.test(key)&&snap?.contact?.messages?.[Number(key)-1]){event.preventDefault();send('choose_next',{slot:'tx'+key},`Next TX${key}`);}
},true);
// ---------------------------------------------------------------- Band Activity selection
// BandActivityView: click selects (prepares, never transmits), double-click replies,
// right-click (or the context-menu key) opens Reply / Select / Set Rx here.
const activity=document.querySelector('#band-activity tbody');
function rowIdentity(row){
  const context=row.dataset.resultId?.split('/');if(!context||context.length<6)return null;
  const sequence=Number(row.dataset.sequence);if(!Number.isSafeInteger(sequence))return null;
  // data-result-id is profile/boot/source/job/generation/sequence of the row's own period.
  const [,,source_id,job_id,generation]=context;if(!source_id||!job_id)return null;
  return {source_id,job_id,generation:Number(generation),sequence};
}
async function selectRow(tr){
  const row=rowIdentity(tr);if(!row)return null;
  const text=tr.children[4]?.firstChild?.textContent??'';
  const reply=await send('select_row',{row,replace:false},'Select station');
  if(reply?.refused==='contact_active')offerChange(()=>send('select_row',{row,replace:true},'Change contact'),text);
  return reply;
}
async function replyRow(tr){const reply=await selectRow(tr);if(reply&&!reply.refused&&transmitCapable())arm('Reply');}
let clickTimer=null;
activity?.addEventListener('click',event=>{const tr=event.target.closest('tr[data-sequence]');if(!tr)return;clearTimeout(clickTimer);clickTimer=setTimeout(()=>selectRow(tr),250);});
activity?.addEventListener('dblclick',event=>{const tr=event.target.closest('tr[data-sequence]');if(!tr)return;clearTimeout(clickTimer);replyRow(tr);});
activity?.addEventListener('keydown',event=>{const tr=event.target.closest('tr[data-sequence]');if(!tr)return;if(event.key==='Enter'){event.preventDefault();selectRow(tr);}else if(event.key==='ContextMenu'||(event.shiftKey&&event.key==='F10')){event.preventDefault();openMenu(tr,tr.getBoundingClientRect().left+20,tr.getBoundingClientRect().bottom);}});
const menu=document.createElement('div');menu.id='ba-menu';menu.className='op-menu';menu.setAttribute('role','menu');menu.hidden=true;
menu.innerHTML='<button type="button" role="menuitem" data-menu="reply">Reply</button><button type="button" role="menuitem" data-menu="select">Select</button><button type="button" role="menuitem" data-menu="rx">Set Rx here</button>';
document.querySelector('main').append(menu);let menuRow=null;
function openMenu(tr,x,y){menuRow=tr;menu.hidden=false;menu.style.left=`${Math.min(x,innerWidth-menu.offsetWidth-8)}px`;menu.style.top=`${Math.min(y,innerHeight-menu.offsetHeight-8)}px`;menu.querySelector('[data-menu=reply]').disabled=!transmitCapable();menu.querySelector('button:not(:disabled)').focus();}
function closeMenu(){menu.hidden=true;menuRow=null;}
activity?.addEventListener('contextmenu',event=>{const tr=event.target.closest('tr[data-sequence]');if(!tr)return;event.preventDefault();openMenu(tr,event.clientX,event.clientY);});
menu.addEventListener('click',event=>{
  const item=event.target.closest('[data-menu]');if(!item||!menuRow)return;const tr=menuRow;closeMenu();
  if(item.dataset.menu==='reply')replyRow(tr);else if(item.dataset.menu==='select')selectRow(tr);
  else{const hz=Math.round(Number(tr.children[3].textContent));if(Number.isFinite(hz))send('set_frequency',{rx_hz:hz,tx_hz:null},'Rx frequency');}
});
menu.addEventListener('keydown',event=>{if(event.key==='Escape'){closeMenu();}});
document.addEventListener('pointerdown',event=>{if(!menu.hidden&&!menu.contains(event.target))closeMenu();},true);
// ---------------------------------------------------------------- QSO dialogue
// WstxContact::RoutesToRxFrequencyPane (sent/received dialogue) plus QsoPaneCrowding: other
// stations within +/-50 Hz of my Rx frequency are shown with a warning sign and counted.
const pane=$('rx-pane-rows'),paneWrap=$('rx-pane').querySelector('.ct-pane-wrap');let paneSeen=new Set(),paneContext=null,paneUnread=0,paneFollow=true;
const myCall=()=>(profileData?.settings?.callsign??'').trim().toUpperCase();
function routes(record){
  const rx=snap?.settings?.rx_hz;const my=myCall(),dx=snap?.contact?.dx_call;
  const f=record.fields,to=f?.type==='standard'&&f.to?.kind==='call'?f.to.text:null;
  if(typeof rx==='number'&&record.frequency_hz>=rx-10&&record.frequency_hz<=rx+10)return true;
  if(my&&to===my)return true;
  return !!(my&&dx&&typeof record.text==='string'&&record.text.split(' ').some((w,i,a)=>w===my&&a[i+1]===dx));
}
function crowding(record){const rx=snap?.settings?.rx_hz,dx=snap?.contact?.dx_call;return typeof rx==='number'&&record.fields?.from?.text!==dx&&record.frequency_hz>=rx-50&&record.frequency_hz<=rx+50;}
function paneAppend(cells,kind,flags={}){
  const tr=document.createElement('tr');tr.dataset.kind=kind;if(flags.crowd)tr.dataset.crowd='true';if(flags.tome)tr.dataset.tome='true';
  for(const text of cells){const td=document.createElement('td');td.textContent=text;tr.append(td);}
  if(flags.crowd)tr.firstElementChild.prepend('⚠ ');
  pane.append(tr);while(pane.children.length>500)pane.firstElementChild.remove();
  if(paneFollow)paneWrap.scrollTop=paneWrap.scrollHeight;else{paneUnread++;showUnread();}
}
function paneTx(text,utc){paneAppend([new Date(utc).toISOString().slice(11,19),'Tx','','',`▸ ${text}`],'tx');}
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
  const ordered=[...resultRows].sort((a,b)=>a.sequence-b.sequence),my=myCall(),dx=snap.contact?.dx_call;
  for(const record of ordered){
    const key=`${liveIdentity(live)}/${record.sequence}`;if(paneSeen.has(key))continue;paneSeen.add(key);
    if(record.status!=='decoded')continue;
    const routed=routes(record),crowd=crowding(record);if(!routed&&!crowd)continue;
    const to=record.fields?.to?.kind==='call'?record.fields.to.text:null,tome=!!my&&to===my&&record.fields?.from?.text!==dx;
    paneAppend([periodLabel(record.period_start_utc,live.job.mode),record.snr_db===null?'—':record.snr_db.toFixed(0),record.dt_seconds===null?'—':record.dt_seconds.toFixed(1),record.frequency_hz.toFixed(0),record.fields?.from?.text===dx&&dx?`◂ ${record.text}`:record.text],routed?'rx':'crowd',{crowd,tome});
    if(dx&&record.fields?.from?.text===dx)body.querySelector('#contact-state').title=record.text;
  }
  const latest=resultRows.filter(r=>r.status==='decoded'&&crowding(r)).length,badge=$('qso-crowd');
  badge.hidden=!latest;badge.textContent=latest?`⚠ ${latest} near Rx`:'';badge.title=`${latest} other station${latest===1?'':'s'} within 50 Hz of my Rx frequency in the latest period`;
}
if(activity)new MutationObserver(()=>{for(const tr of activity.querySelectorAll('tr[data-sequence]'))if(!tr.hasAttribute('tabindex'))tr.tabIndex=0;paneUpdate();}).observe(activity,{childList:true});
// ---------------------------------------------------------------- Rx/Tx strip and markers
// WstxOperatingLayout::RxTxStrip: confirmed values only; 1 Hz steps, Shift 10 Hz.
function setFrequency(key,value,label){if(!Number.isSafeInteger(value)||value<0){resultText.textContent='Frequency must be a whole number of Hz';return;}send('set_frequency',{rx_hz:key==='rx'?value:null,tx_hz:key==='tx'?value:null},label);}
const confirmed=key=>snap?.settings?.[key==='rx'?'rx_hz':'tx_hz'];
for(const key of ['rx','tx']){
  const input=$('contact-'+key),label=key==='rx'?'Rx frequency':'Tx frequency';
  input.addEventListener('change',()=>setFrequency(key,Number(input.value),label));
  input.addEventListener('keydown',event=>{if(!['ArrowUp','ArrowDown'].includes(event.key)||typeof confirmed(key)!=='number')return;event.preventDefault();setFrequency(key,confirmed(key)+(event.key==='ArrowUp'?1:-1)*(event.shiftKey?10:1),label);});
  input.addEventListener('wheel',event=>{if(typeof confirmed(key)!=='number'||input.disabled)return;event.preventDefault();setFrequency(key,confirmed(key)+(event.deltaY<0?1:-1)*(event.shiftKey?10:1),label);},{passive:false});
}
document.querySelector('#rxtx-strip').addEventListener('click',event=>{
  const button=event.target.closest('[data-strip-step]');if(!button)return;
  const [key,step]=button.dataset.stripStep.split(':'),base=confirmed(key);if(typeof base!=='number')return;
  setFrequency(key,base+Number(step)*(event.shiftKey?10:1),key==='rx'?'Rx frequency':'Tx frequency');
});
$('contact-hold').addEventListener('change',event=>send('set_hold_tx',{enabled:event.target.checked},'Hold Tx'));
$('strip-tx-from-rx').addEventListener('click',()=>{const s=snap?.settings;if(s)send('set_frequency',{rx_hz:null,tx_hz:s.rx_hz},'Tx=Rx');});
$('strip-rx-from-tx').addEventListener('click',()=>{const s=snap?.settings;if(s)send('set_frequency',{rx_hz:s.tx_hz,tx_hz:null},'Rx=Tx');});
// WstxContact::PointerEffect: click Rx; shift- or right-click Tx; ctrl-click Rx and Tx;
// right double-click Rx and Tx. A left double-click is two Rx clicks: the full-band decoder
// always runs, so there is no decode-at-point (#37). Markers move only after confirmation,
// can be dragged (release sends one request); no pointer action enables Tx.
const waterfall=document.querySelector('#waterfall'),wrap=document.querySelector('#waterfall-wrap');
const rxMarker=document.createElement('div'),txMarker=document.createElement('div');
rxMarker.className='ct-marker ct-rx';txMarker.className='ct-marker ct-txm';rxMarker.dataset.key='rx';txMarker.dataset.key='tx';
for(const m of [rxMarker,txMarker]){m.setAttribute('role','slider');m.setAttribute('aria-valuemin','0');m.setAttribute('aria-valuemax','3000');m.setAttribute('aria-label',m===rxMarker?'Rx marker, drag to set the Rx frequency':'Tx marker, drag to set the Tx frequency');}
wrap?.append(rxMarker,txMarker);
// Labels only where the waterfall has room for them (no clipped text at 360 px/200 %).
if(wrap)new ResizeObserver(()=>markers()).observe(wrap);
let dragging=null;
function markers(){
  const s=snap?.settings,room=!wrap||wrap.clientHeight>=3*parseFloat(getComputedStyle(rxMarker).fontSize||'14');
  for(const [m,hz,label] of [[rxMarker,s?.rx_hz,'Rx'],[txMarker,s?.tx_hz,'Tx']]){if(dragging===m)continue;m.hidden=typeof hz!=='number';if(typeof hz==='number'){m.style.left=`${hz/30}%`;m.textContent=room?`${label} ${hz}`:'';m.dataset.hz=String(hz);m.title=`${label} ${hz} Hz`;m.setAttribute('aria-valuenow',String(hz));}}
  // Close markers share one label so the texts never overlap.
  if(room&&s&&Math.abs(s.rx_hz-s.tx_hz)<400){rxMarker.textContent=s.rx_hz===s.tx_hz?`Rx/Tx ${s.rx_hz}`:`Rx ${s.rx_hz} · Tx ${s.tx_hz}`;txMarker.textContent='';}
}
const pointerHz=event=>{const box=waterfall.getBoundingClientRect();return Math.max(0,Math.min(3000,Math.round((event.clientX-box.left)/box.width*3000)));};
for(const m of [rxMarker,txMarker]){
  m.addEventListener('pointerdown',event=>{if(event.button!==0||!snap)return;event.preventDefault();event.stopPropagation();dragging=m;m.setPointerCapture(event.pointerId);m.classList.add('ct-dragging');});
  m.addEventListener('pointermove',event=>{if(dragging!==m)return;m.style.left=`${pointerHz(event)/30}%`;m.textContent=`${m.dataset.key==='rx'?'Rx':'Tx'} ${pointerHz(event)}`;});
  m.addEventListener('pointerup',event=>{if(dragging!==m)return;dragging=null;m.classList.remove('ct-dragging');const hz=pointerHz(event);if(String(hz)!==m.dataset.hz)send('set_frequency',{rx_hz:m.dataset.key==='rx'?hz:null,tx_hz:m.dataset.key==='tx'?hz:null},m.dataset.key==='rx'?'Rx frequency':'Tx frequency');else markers();});
  m.addEventListener('click',event=>event.stopPropagation());
}
let lastRight=0;
function pointer(rx,tx,label){send('set_frequency',{rx_hz:rx,tx_hz:tx},label);}
waterfall?.addEventListener('contextmenu',event=>event.preventDefault());
waterfall?.addEventListener('click',event=>{
  if(event.button!==0)return;const hz=pointerHz(event);
  if(event.ctrlKey)pointer(hz,hz,'Rx and Tx frequency');else if(event.shiftKey)pointer(null,hz,'Tx frequency');else pointer(hz,null,'Rx frequency');
});
waterfall?.addEventListener('mouseup',event=>{
  if(event.button!==2)return;const hz=pointerHz(event),now=performance.now();
  if(now-lastRight<400){lastRight=0;pointer(hz,hz,'Rx and Tx frequency');}else{lastRight=now;pointer(null,hz,'Tx frequency');}
});
// ---------------------------------------------------------------- UTC clock, period, Rx level
const period=document.querySelector('#radio-toolbar .op-period'),meter=document.querySelector('#settings-audio .op-input-meter');
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
  meter.querySelector('div').style.setProperty('--ct-level',`${level===null?0:Math.min(100,level/0.9)}%`);
  countdown();
}
// QsoPane "Next": progress of the current period and the countdown to the next period of
// the contact's parity (even = first, odd = second period of each pair).
function countdown(){
  const bar=$('qso-progress'),text=$('qso-countdown');if(!bar||!text)return;
  if(!tick||!snap){bar.style.width='0%';text.textContent='';return;}
  const utc=tick.utc+(performance.now()-tick.at),p=tick.period,index=Math.floor(utc/p),parity=snap.settings.parity==='odd'?1:0;
  bar.style.width=`${Math.min(100,100*(utc%p)/p)}%`;
  const next=(index+1)%2===parity?index+1:index+2,wait=Math.ceil((next*p-utc)/1000),armed=snap.transmit.arm_state==='armed';
  text.textContent=tick.transmitting?'Transmitting':armed?`Tx in ${wait} s`:`next ${parity?'odd':'even'} period in ${wait} s`;
}
setInterval(displays,250);
// ---------------------------------------------------------------- station events
// Reconnect (a new socket) reloads the authoritative snapshot; a status refresh on the
// same socket does not (contact.state announces every change).
let readySocket=null;
addEventListener('station-ready',event=>{if(event.detail===readySocket&&snap&&snap.boot_id===profileData?.boot_id)return;readySocket=event.detail;load();loadAutomation();});
addEventListener('station-stale',()=>{displays();});
addEventListener('station-message',event=>{
  const {message,current}=event.detail;if(current!==socket)return;
  const d=message.data;
  if(message.type==='contact.state'&&d&&(!snap||d.contact_revision!==snap.contact_revision||d.boot_id!==snap.boot_id))load();
  else if(message.type==='automation.state'&&d)loadAutomation();
  else if(message.type==='station.tick'&&d&&Number.isSafeInteger(d.utc_ms)&&[15000,7500].includes(d.period_ms)){
    const changed=tick?.transmitting!==d.transmitting;
    tick={utc:d.utc_ms,at:performance.now(),period:d.period_ms,transmitting:d.transmitting===true,level:Number.isInteger(d.rx_level_db)?d.rx_level_db:null};$('contact-tx').max=d.period_ms===7500?'2916':'2950';
    displays();if(changed)render();else stationTx();
  }
});
render();
if(socket?.readyState===WebSocket.OPEN&&connection.dataset.state==='connected'){readySocket=socket;load();loadAutomation();}
// ---------------------------------------------------------------- browser settings
// KeyboardShortcuts overview (the halt lines are in recording.js from the start).
document.querySelector('#help-keys').insertAdjacentHTML('beforeend','<div><dt>CQ / Reply / double-click a decode</dt><dd>Start the QSO: transmission starts with the next period and ends after RR73/73 or HALT</dd></div><div><dt>F2</dt><dd>Settings</dd></div><div><dt>F4</dt><dd>Clear the DX call (cancel the contact)</dd></div><div><dt>Alt+1 &hellip; Alt+6</dt><dd>Next message Tx1&hellip;Tx6</dd></div><div><dt>Alt+M</dt><dd>Start or stop receive</dd></div><div><dt>Alt+T / Alt+Q</dt><dd>Tune / Log QSO</dd></div><div><dt>F11 / F12</dt><dd>Rx &minus;/+ 1 Hz</dd></div><div><dt>Shift+F11 / Shift+F12</dt><dd>Tx &minus;/+ 60 Hz (FT4 90 Hz)</dd></div><div><dt>Ctrl+F11 / Ctrl+F12</dt><dd>Rx and Tx &minus;/+ 1 Hz</dd></div><div><dt>Waterfall click / Shift+click / Ctrl+click</dt><dd>Set Rx / Tx / both; drag the Rx or Tx marker</dd></div><div><dt>Rx/Tx fields: wheel, arrows, &minus;/+</dt><dd>1 Hz; with Shift 10 Hz</dd></div><div><dt>Band Activity: click / double-click / right-click</dt><dd>Select / Reply / menu</dd></div><div><dt>Separator arrows / Home / End</dt><dd>Resize the spectrum and waterfall</dd></div>');
// WstxOperatingLayout::ThemeChoice: Day / Dark / Night for this browser only, manually, by
// two local times or by sunrise and sunset at the profile locator. No station request.
const themeKey='wstx.theme.v1';
function themeSettings(){let saved=null;try{saved=JSON.parse(localStorage.getItem(themeKey));}catch{}return {theme:['day','dark','night'].includes(saved?.theme)?saved.theme:'dark',mode:['manual','time','sun'].includes(saved?.mode)?saved.mode:'manual',day:/^\d\d:\d\d$/.test(saved?.day)?saved.day:'07:00',night:/^\d\d:\d\d$/.test(saved?.night)?saved.night:'20:00'};}
function sunTimes(locator,date=new Date()){
  // NOAA-style approximation, minutes after UTC midnight; null for polar day/night.
  const position=maidenhead(locator);if(!position)return null;const [lat,lon]=position,r=Math.PI/180;
  const day=Math.floor((Date.UTC(date.getUTCFullYear(),date.getUTCMonth(),date.getUTCDate())-Date.UTC(date.getUTCFullYear(),0,0))/864e5);
  const g=2*Math.PI/365*(day-1),eq=229.18*(0.000075+0.001868*Math.cos(g)-0.032077*Math.sin(g)-0.014615*Math.cos(2*g)-0.040849*Math.sin(2*g));
  const decl=0.006918-0.399912*Math.cos(g)+0.070257*Math.sin(g)-0.006758*Math.cos(2*g)+0.000907*Math.sin(2*g)-0.002697*Math.cos(3*g)+0.00148*Math.sin(3*g);
  const cos=(Math.cos(90.833*r)/(Math.cos(lat*r)*Math.cos(decl)))-Math.tan(lat*r)*Math.tan(decl);if(cos<-1||cos>1)return null;
  const ha=Math.acos(cos)/r;return {rise:720-4*(lon+ha)-eq,set:720-4*(lon-ha)-eq};
}
function themeNow(settings=themeSettings()){
  if(settings.mode==='manual')return settings.theme;
  const now=new Date();
  if(settings.mode==='time'){const minutes=now.getHours()*60+now.getMinutes(),[d,n]=[settings.day,settings.night].map(t=>Number(t.slice(0,2))*60+Number(t.slice(3)));return (d<n?minutes>=d&&minutes<n:minutes>=d||minutes<n)?'day':'night';}
  const sun=sunTimes(profileData?.settings?.locator,now);if(!sun)return settings.theme;
  const utc=now.getUTCHours()*60+now.getUTCMinutes(),rise=(sun.rise+1440)%1440,set=(sun.set+1440)%1440;
  return (rise<set?utc>=rise&&utc<set:utc>=rise||utc<set)?'day':'night';
}
function applyTheme(){
  const settings=themeSettings(),theme=themeNow(settings);document.documentElement.dataset.theme=theme;
  for(const [id,value] of [['theme-choice',settings.theme],['theme-switch',settings.mode],['theme-day-start',settings.day],['theme-night-start',settings.night]]){const node=document.getElementById(id);if(node&&document.activeElement!==node)node.value=value;}
  document.querySelector('#theme-times').hidden=settings.mode!=='time';
  const sun=settings.mode==='sun'?sunTimes(profileData?.settings?.locator):null,clock=m=>`${String(Math.floor(((m%1440)+1440)%1440/60)).padStart(2,'0')}:${String(Math.floor(((m%60)+60)%60)).padStart(2,'0')}`;
  document.querySelector('#theme-status').textContent=`Now ${theme}${settings.mode==='sun'?(sun?` · sunrise ${clock(sun.rise)} UTC, sunset ${clock(sun.set)} UTC at ${profileData?.settings?.locator}`:' · sunrise/sunset unknown for this locator; manual theme used'):''}`;
}
for(const id of ['theme-choice','theme-switch','theme-day-start','theme-night-start'])document.getElementById(id).addEventListener('change',()=>{
  const value={theme:document.querySelector('#theme-choice').value,mode:document.querySelector('#theme-switch').value,day:document.querySelector('#theme-day-start').value,night:document.querySelector('#theme-night-start').value};
  try{localStorage.setItem(themeKey,JSON.stringify(value));}catch{}applyTheme();
});
setInterval(applyTheme,60000);addEventListener('station-ready',applyTheme);applyTheme();
// General > Station > Continent: browser-local until the strategy engine needs it at the
// station; the default derives from the locator (coarse bounding regions).
function continentOf(locator){
  const p=maidenhead(locator);if(!p)return null;const [lat,lon]=p;
  if(lat<-60)return 'AN';if(lon>=-170&&lon<-30)return lat>12||(lon<-77&&lat>7)?'NA':'SA';
  if(lon>=-30&&lon<60&&lat>=35)return lon>40&&lat<42?'AS':'EU';if(lon>=-30&&lon<52&&lat<37)return lon>33&&lat>12?'AS':'AF';
  if(lat>=-11&&lon>=60||lat>=35)return 'AS';return 'OC';
}
const continentKey=()=>`wstx.continent.v1:${profileData?.profile_id??''}`;
function showContinent(){
  const select=document.querySelector('#station-continent');let saved='';try{saved=localStorage.getItem(continentKey())??'';}catch{}
  if(document.activeElement!==select)select.value=saved;
  const derived=continentOf(profileData?.settings?.locator);document.querySelector('#continent-derived').textContent=`From locator: ${derived??'unknown'}${saved?` · using ${saved}`:''}`;
}
document.querySelector('#station-continent').addEventListener('change',event=>{try{if(event.target.value)localStorage.setItem(continentKey(),event.target.value);else localStorage.removeItem(continentKey());}catch{}showContinent();});
addEventListener('station-ready',showContinent);showContinent();
// SettingsDrawer: restart changes (the saved profile) apply only on Apply and, during a QSO or
// transmission, only after a confirmation. Runs before app.js's own submit handler.
let applyConfirmed=false;
serverForm.addEventListener('submit',async event=>{
  if(applyConfirmed){applyConfirmed=false;return;}
  const s=window.wstxContact?.snapshot?.(),c=s?.contact,busy=(c&&!['idle','completed','cancelled'].includes(c.state))||s?.transmit?.arm_state==='armed'||s?.transmit?.tune;
  if(!busy)return;
  event.preventDefault();event.stopImmediatePropagation();
  if(await confirmAction('Applying these settings may restart receive and interrupt the QSO in progress. Apply now?','Apply')){applyConfirmed=true;serverForm.requestSubmit();}
},true);
window.wstxContact=Object.freeze({load,snapshot:()=>snap});
})();
