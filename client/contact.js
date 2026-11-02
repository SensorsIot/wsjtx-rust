'use strict';
// (WstxOperatingLayout::QsoPane, RxTxStrip, BandActivityView). The server owns the contact,
(()=>{
const focus=document.querySelector('#rx-focus');
if(!focus||document.body.dataset.profile!=='true')return;
const $=id=>document.getElementById(id);
// #45 CL-045-01: a plain setting, saved on change; it acts at the next station start.
block('settings-startup','Receive at startup',document.querySelector('#settings-general'),'<label class="op-check"><input type="checkbox" id="monitor-off-startup" disabled>Monitor off at startup</label><p id="startup-result" class="op-muted" role="status"></p><p class="op-muted">Saved at once; it takes effect at the next station start and does not restart receive.</p>');
block('settings-startup-resume','Startup resume',document.querySelector('#settings-expert'),'<p id="startup-resume" class="op-muted" role="status">Startup resume unknown</p>');
block('settings-automation','MCP and automation',document.querySelector('#settings-general'),'<p class="op-muted">Automation runs on the station (MCP). Its state shows beside the strategy element; HALT ends it. Strategies (Highlight/Auto) arrive with the strategy engine.</p>');
block('settings-transmit','Transmit',document.querySelector('#settings-radio'),'<label>Tx watchdog (minutes)<input id="watchdog-tx" type="number" min="1" max="99" step="1" disabled></label><label>Tune watchdog (seconds)<input id="watchdog-tune" type="number" min="1" max="300" step="1" disabled></label><p id="watchdog-result" class="op-muted" role="status"></p><p class="op-muted">Watchdogs apply at once, as in WSJT-X. Tx power is set on the transceiver; this station sends no power command. PTT is chosen under CAT.</p>');
block('settings-log','Log',document.querySelector('#settings-logging'),'<p>Each completed QSO is logged at once, as in WSJT-X: saved in this station profile’s contacts.adi (ADIF) and sent to the UDP targets that select QSO Logged / Logged ADIF. There is no review step; Log QSO logs the current contact now.</p><button type="button" data-region="logbook">&#9776; Open Logbook</button>');
block('settings-udp','WSJT-X UDP interface',document.querySelector('#settings-logging'),'<p id="udp-warning" class="op-warning">Accept commands lets that program select a QSO (like a click) and edit the Tx5 text. It can never key the transmitter; Halt Tx from any program always halts.</p><label>Instance name<input id="udp-instance" maxlength="64" autocomplete="off" disabled></label><h4 id="udp-targets-title">UDP targets</h4><div id="udp-targets" role="list" aria-labelledby="udp-targets-title"></div><p class="op-actions"><button type="button" id="udp-add" disabled>Add target</button><button type="button" id="udp-reload">Reload</button><button type="button" id="udp-save" class="op-primary" disabled>Save UDP settings</button></p><p id="udp-result" class="op-muted" role="status">Read when Settings opens</p><p class="op-muted">Applies on Save; it does not restart receive.</p>');
block('settings-pskreporter','PSK Reporter',document.querySelector('#settings-logging'),'<p class="op-muted">Not available yet.</p>');
const stepper=(key,label,min,max)=>`<label class="op-strip-field">${label}<input id="contact-${key}" type="number" min="${min}" max="${max}" step="1" disabled inputmode="numeric" aria-label="${label} audio frequency, Hz"><span>Hz</span></label><button type="button" data-strip-step="${key}:-1" aria-label="${label} down 1 Hz (Shift: 10 Hz)" disabled>&minus;</button><button type="button" data-strip-step="${key}:1" aria-label="${label} up 1 Hz (Shift: 10 Hz)" disabled>+</button>`;
document.querySelector('#rxtx-strip').innerHTML=stepper('rx','Rx',0,3000)+stepper('tx','Tx',200,2950)+'<label class="op-check"><input type="checkbox" id="contact-hold" disabled>Hold Tx</label><button type="button" id="strip-tx-from-rx" disabled>Tx=Rx</button><button type="button" id="strip-rx-from-tx" disabled>Rx=Tx</button>';
const qsoButton=(id,label,title,extra='')=>`<button type="button" id="${id}" disabled title="${title}"${extra}>${label}</button>`;
document.querySelector('#contact-state').insertAdjacentHTML('afterend',`<section id="rx-pane" class="ct-pane" aria-labelledby="rx-pane-heading"><header><h4 id="rx-pane-heading">Dialogue <span id="rx-pane-unread"></span></h4><button type="button" id="rx-pane-resume" hidden>Resume following</button></header><div class="ct-pane-wrap" tabindex="0" aria-label="QSO dialogue and stations near my Rx frequency"><table aria-label="QSO dialogue"><tbody id="rx-pane-rows"></tbody></table></div></section>
<div class="op-qso-next"><span class="op-eyebrow">NEXT &#9656;</span><strong id="contact-next">None</strong><div class="op-qso-progress" aria-hidden="true"><i id="qso-progress"></i></div><span id="qso-countdown" class="op-muted"></span><span class="op-eyebrow">LAST</span><strong id="contact-last">None</strong></div>
<div class="op-qso-buttons" role="group" aria-label="QSO commands">${qsoButton('qso-cq','CQ','Call CQ: transmits from the next period')}${qsoButton('qso-reply','Reply','Answer the selected station: transmits from the next period')}${qsoButton('qso-rr73','RR73','Send RR73 next')}${qsoButton('qso-73','73','Send 73 next')}${qsoButton('contact-tune','Tune','Tune (Alt+T)',' aria-pressed="false"')}<button type="button" id="qso-halt" class="op-halt-small" disabled title="Halt Tx (Esc, Alt+H)">HALT</button>${qsoButton('contact-log','Log QSO','Log QSO (Alt+Q)',' aria-describedby="contact-unavailable"')}</div>
<p id="transmit-unavailable" class="op-unavailable">Transmission unavailable: this server does not offer transmit control.</p><p id="contact-unavailable" class="op-unavailable">Log QSO needs a contact with a DX call.</p><p id="contact-result" class="op-muted" role="status"></p><p id="contact-logged" class="op-muted" role="status"></p>
`);
const confirmDialog=document.createElement('dialog');confirmDialog.id='op-confirm';confirmDialog.className='op-dialog';confirmDialog.innerHTML='<form method="dialog"><p id="op-confirm-text"></p><menu><button type="button" class="op-halt-small" id="op-confirm-halt" title="Halt Tx (Esc, Alt+H)">HALT</button><button value="cancel" type="submit">Cancel</button><button value="ok" type="submit" class="op-primary" id="op-confirm-ok">Continue</button></menu></form>';
window.wstxConfirm=function(text,okLabel='Continue'){
  confirmDialog.querySelector('#op-confirm-text').textContent=text;confirmDialog.querySelector('#op-confirm-ok').textContent=okLabel;
  return new Promise(resolve=>{confirmDialog.returnValue='';confirmDialog.querySelector('#op-confirm-halt').disabled=halt.disabled;confirmDialog.addEventListener('close',()=>resolve(confirmDialog.returnValue==='ok'),{once:true});confirmDialog.showModal();confirmDialog.querySelector('#op-confirm-ok').focus();});
}
// The modal popup makes the page inert, so it carries HALT itself (same action and state).
confirmDialog.querySelector('#op-confirm-halt').addEventListener('click',()=>{confirmDialog.close('cancel');halt.click();});
main.append(confirmDialog);
document.querySelector('#band-activity').insertAdjacentHTML('afterbegin','<div id="strategy-element" class="op-strategy-bar" role="group" aria-label="Strategy"><span class="op-strategy-label">Strategy</span><select id="strategy-name" disabled aria-label="Strategy name" title="The strategy engine is not available yet"><option>None</option></select><button type="button" id="strategy-edit" disabled aria-label="Edit strategy" title="The strategy engine is not available yet">&#9998;</button><span class="op-segmented" role="group" aria-label="Strategy mode"><button type="button" id="strategy-highlight" disabled aria-pressed="false" title="The strategy engine is not available yet">Highlight</button><button type="button" id="strategy-auto" disabled aria-pressed="false" title="The strategy engine is not available yet">Auto</button></span><span id="station-automation" class="op-automation" role="status">Automation idle</span></div>');
const slotsMarkup=['tx1','tx2','tx3','tx4','tx5','tx6'];
focus.querySelector('.op-contact-body').insertAdjacentHTML('beforeend',`<details id="qso-more"><summary>DX call, messages Tx1&ndash;Tx6, report and period</summary><div class="ct-dx"><label>DX Call<input id="dx-call" maxlength="13" autocomplete="off" spellcheck="false" disabled></label><label>DX Grid<input id="dx-grid" maxlength="6" autocomplete="off" spellcheck="false" disabled></label><button type="button" id="dx-generate" disabled>Generate</button></div><p class="ct-more-row"><button type="button" id="rx-pane-erase">Erase dialogue</button></p><ol id="contact-messages" class="ct-messages" aria-label="Standard messages Tx1 to Tx6">${slotsMarkup.map((s,i)=>`<li data-slot="${s}"><label class="ct-next"><input type="radio" name="contact-next" value="${s}" aria-label="Next message Tx${i+1}" disabled>Tx${i+1}</label><input class="ct-text" data-slot="${s}" maxlength="37" aria-label="Tx${i+1} message" autocomplete="off" spellcheck="false" disabled>${s==='tx1'?'<label class="op-check"><input type="checkbox" id="contact-tx1-skip" disabled>Skip Tx1</label>':''}${s==='tx4'?'<label class="op-check"><input type="checkbox" id="contact-rr73" disabled>RR73</label>':''}</li>`).join('')}</ol>
<div class="op-frequency-fields ct-fields"><label>Report<input id="contact-report" type="number" min="-50" max="49" step="1" disabled><span>dB</span></label><label>Tx period<select id="contact-parity" disabled><option value="even">Even / 1st</option><option value="odd">Odd / 2nd</option></select></label><label class="op-check"><input type="checkbox" id="contact-auto" disabled aria-label="Auto sequence unavailable">Auto sequence</label><button type="button" id="contact-cancel" disabled>Cancel contact</button><span id="contact-watchdog" class="op-muted"></span></div></details>`);
const body=focus.querySelector('.op-contact-body'),identity=focus.querySelector('.op-contact-identity');
const slots=['tx1','tx2','tx3','tx4','tx5','tx6'];
const resultText=$('contact-result');
let snap=null,sending=false,tick=null,lastTx=null,changeTarget=null,lastLog=null;
const valid=s=>s&&s.v===1&&Object.keys(s).sort().join(',')==='boot_id,contact,contact_revision,log,monotonic_ms,profile_id,settings,snapshot_sequence,transmit,utc_ms,v,watchdog'&&Number.isSafeInteger(s.contact_revision);
const transmitCapable=()=>snap&&snap.transmit.capability!=='unsupported';
// One GET /contact at a time; a caller during a pending GET waits for a fresh one.
// contactMissing: this station has no contact engine (404); routine refreshes then skip /contact.
let loading=null,queued=null,contactMissing=false;
function load(){
  if(!loading){loading=fetchSnapshot().finally(()=>{loading=null;});return loading;}
  if(!queued)queued=loading.then(()=>{queued=null;return load();});
  return queued;
}
async function fetchSnapshot(){
  try{
    const response=await stationFetch('/contact',{cache:'no-store',signal:AbortSignal.timeout(10000)});
    contactMissing=response.status===404;
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
  // RR73/73 only while the contact is in progress: on a completed one Enable Tx starts a new CQ.
  $('qso-rr73').disabled=$('qso-73').disabled=!capable||!prepared;
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
  stationTx();countdown();
  paneUpdate();if(activity)for(const tr of activity.querySelectorAll('tr[data-sequence]'))if(!tr.hasAttribute('tabindex'))tr.tabIndex=0;
  logShow();
}
// WstxContact::DirectLog (#41): the server logs each completed QSO and every Log QSO; the
// pane shows the latest outcome, and an open Logbook page lists a newly saved record.
const logReasons={storage_unavailable:'storage unavailable · retrying',log_queue_full:'too many unsaved QSOs · the oldest was not logged',log_invalid_field:'the station profile is incomplete'};
function logShow(){
  const l=snap?.log,node=$('contact-logged');
  node.textContent=!l?'':l.outcome==='saved'?`Logged ${l.call} · contacts.adi`:`Not logged ${l.call} · ${logReasons[l.error]??l.error??'saving'}`;
  const key=l&&`${l.contact_id}/${l.outcome}`;
  if(key&&key!==lastLog&&l.outcome==='saved'&&lastLog!==null&&main.dataset.region==='logbook')window.wstxLogbook?.loadHistory(null);
  if(key)lastLog=key;else if(lastLog===null&&snap)lastLog='';
}
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
document.addEventListener('pointerdown',event=>{
  if(typeof currentRegion==='undefined'||currentRegion==='operate')return;
  if(event.target.closest?.('.op-secondary,#station-bar,#signal,#splitter,dialog,button,input,select,textarea,a,label,summary,[tabindex]'))return;
  showRegion('operate');
},true);
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
$('qso-halt').addEventListener('click',()=>halt.click());$('qso-halt').disabled=halt.disabled;
async function finalMessage(slot,label){
  const c=snap?.contact;if(!c?.dx_call||!transmitting(c))return;
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
for(const id of ['watchdog-tx','watchdog-tune'])$(id).addEventListener('change',async()=>{
  const tx=Number($('watchdog-tx').value),tune=Number($('watchdog-tune').value);
  if(!Number.isInteger(tx)||!Number.isInteger(tune)){$('watchdog-result').textContent='Watchdogs must be whole numbers';return;}
  await send('set_watchdogs',{tx_minutes:tx,tune_seconds:tune},'Watchdogs');$('watchdog-result').textContent=resultText.textContent;
});
// #40 WstxUdp settings (CL-040-02): read when the drawer opens (at most every 30 s), on the
// Logging tab or Reload; Save sends one PUT /udp. A setting: it restarts nothing.
const UDP_MESSAGES=[['heartbeat','Heartbeat'],['status','Status'],['decode','Decode'],['clear','Clear'],['qso_logged','QSO Logged'],['close','Close'],['logged_adif','Logged ADIF']];
const UDP_DEFAULT={instance_name:'WSTX-Rust',targets:[{address:'127.0.0.1:2237',enabled:true,multicast_ttl:1,multicast_interface:null,messages:UDP_MESSAGES.map(m=>m[0]),accept_commands:false}]};
let udpView=null,udpDirty=false,udpRead=-Infinity,udpLoading=null;
const udpMulticast=address=>{const m=/^(\d+)\./.exec(address.trim());return !!m&&Number(m[1])>=224&&Number(m[1])<=239;};
const utcTime=ms=>new Date(ms).toISOString().slice(11,19)+' UTC';
function udpStatusText(s){
  if(!s)return 'Not saved yet';
  const parts=[s.active?'Active':'Inactive'];if(s.schema)parts.push(`schema ${s.schema}`);
  parts.push(s.last_send_utc_ms?`last send ${utcTime(s.last_send_utc_ms)}`:'nothing sent yet');if(s.error)parts.push(`error ${s.error}`);
  const c=s.last_command;if(c)parts.push(`last command ${c.type} ${c.outcome}${c.code?` (${c.code})`:''} at ${utcTime(c.utc_ms)}`);
  return parts.join(' · ');
}
function udpRow(t,status){
  const row=document.createElement('fieldset');row.className='udp-target';row.setAttribute('role','listitem');
  row.innerHTML=`<legend>Target</legend><label>Address:port<input data-f="address" autocomplete="off" spellcheck="false"></label><label class="op-check"><input type="checkbox" data-f="enabled">Enabled</label><label>Multicast TTL<input type="number" data-f="ttl" min="1" max="255" step="1"></label><label>Multicast interface<input data-f="iface" placeholder="default" autocomplete="off" spellcheck="false"></label><fieldset class="udp-messages"><legend>Messages sent</legend>${UDP_MESSAGES.map(([k,l])=>`<label class="op-check"><input type="checkbox" data-m="${k}">${l}</label>`).join('')}</fieldset><label class="op-check"><input type="checkbox" data-f="accept">Accept commands</label><span class="op-muted" data-f="accept-note"></span><button type="button" data-f="remove">Remove target</button><p class="op-muted" data-f="status" role="status"></p>`;
  const f=k=>row.querySelector(`[data-f=${k}]`);
  f('address').value=t.address;f('enabled').checked=t.enabled;f('ttl').value=t.multicast_ttl;f('iface').value=t.multicast_interface??'';f('accept').checked=t.accept_commands;
  for(const box of row.querySelectorAll('[data-m]'))box.checked=t.messages.includes(box.dataset.m);
  f('status').textContent=udpStatusText(status);
  const multicast=()=>{const on=udpMulticast(f('address').value);f('accept').disabled=on;if(on)f('accept').checked=false;f('accept-note').textContent=on?'Not for a multicast group: commands come from a host.':'';};
  f('address').addEventListener('input',multicast);multicast();
  f('remove').addEventListener('click',()=>{row.remove();udpDirty=true;udpButtons();});
  return row;
}
function udpButtons(){const n=$('udp-targets').children.length;$('udp-add').disabled=!udpView||n>=16;$('udp-save').disabled=!udpView;}
function udpShow(){
  const v=udpView;$('udp-instance').disabled=!v;if(!v)return udpButtons();
  const config=v.configuration??UDP_DEFAULT,status=new Map((v.status??[]).map(s=>[s.address,s]));
  $('udp-instance').value=config.instance_name;
  $('udp-targets').replaceChildren(...config.targets.map(t=>udpRow(t,v.configuration?status.get(t.address):null)));
  $('udp-result').textContent=v.configuration_error?`Saved UDP settings unreadable (${v.configuration_error}); Save replaces them`:`Revision ${v.revision}${v.received?` · ${v.received} received`:''}${v.ignored?` · ${v.ignored} ignored`:''}`;
  udpDirty=false;udpButtons();
}
function loadUdp(force=false){
  if(udpLoading||udpDirty||(!force&&performance.now()-udpRead<30000))return udpLoading;
  udpRead=performance.now();
  udpLoading=stationFetch('/udp',{cache:'no-store',signal:AbortSignal.timeout(10000)}).then(async r=>{const v=r.ok?await r.json():null;if(v?.v===1&&!udpDirty){udpView=v;udpShow();}else if(!r.ok)$('udp-result').textContent=`UDP settings unavailable (${r.status})`;}).catch(()=>{$('udp-result').textContent='UDP settings unavailable';}).finally(()=>{udpLoading=null;});
  return udpLoading;
}
function udpConfiguration(){
  return {instance_name:$('udp-instance').value,targets:[...$('udp-targets').children].map(row=>{const f=k=>row.querySelector(`[data-f=${k}]`);
    return {address:f('address').value.trim(),enabled:f('enabled').checked,multicast_ttl:Number(f('ttl').value),multicast_interface:f('iface').value.trim()||null,
      messages:[...row.querySelectorAll('[data-m]')].filter(b=>b.checked).map(b=>b.dataset.m),accept_commands:f('accept').checked};})};
}
$('settings-udp').addEventListener('input',event=>{if(event.target.closest('#udp-instance,.udp-target'))udpDirty=true;});
$('udp-add').addEventListener('click',()=>{const n=$('udp-targets').children.length;if(n>=16)return;$('udp-targets').append(udpRow({...UDP_DEFAULT.targets[0],address:''},null));udpDirty=true;udpButtons();$('udp-targets').lastElementChild.querySelector('[data-f=address]').focus();});
$('udp-reload').addEventListener('click',()=>{udpDirty=false;loadUdp(true);});
$('udp-save').addEventListener('click',async()=>{
  const v=udpView;if(!v)return;$('udp-save').disabled=true;$('udp-result').textContent='Saving';
  try{
    const response=await stationFetch('/udp',{method:'PUT',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:v.profile_id,boot_id:v.boot_id,expected_revision:v.revision,configuration:udpConfiguration()}),signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);
    if(!response.ok||data?.v!==1){const e=data?.error;$('udp-result').textContent=`Not saved · ${e?.code??response.status}${e?.field?` (${e.field})`:''}${e?.code==='stale_revision'?' · changed elsewhere: Reload to see it':''}`;return;}
    udpView=data;udpShow();$('udp-result').textContent=`Saved · revision ${data.revision}`;
  }catch(error){$('udp-result').textContent=`Not saved · ${error.message}`;}
  finally{udpButtons();}
});
new MutationObserver(()=>{if(!document.querySelector('#settings-drawer').hidden)loadUdp();}).observe(document.querySelector('#settings-drawer'),{attributes:true,attributeFilter:['hidden']});
document.querySelector('#tab-logging')?.addEventListener('click',()=>loadUdp(true));
let startupView=null,startupLoading=null;
const resumeText={idle:'Nothing to resume at start',off:'Monitor off at startup',waiting:'Resuming receive',started:'Resumed at start',started_untuned:'Resumed at start on the present dial',skipped:'Resume skipped: receive was already chosen',failed:'Resume failed'};
function startupShow(){
  const v=startupView,box=$('monitor-off-startup');box.disabled=!v;if(!v)return;box.checked=v.monitor_off_at_startup;
  const last=v.last_receive,choice=last?` · last ${[last.band,last.mode.toUpperCase()].filter(Boolean).join(' ')}`:'';
  $('startup-resume').textContent=`${resumeText[v.resume.state]??v.resume.state}${v.resume.error?` · ${v.resume.error}`:''}${choice}${v.storage_error?` · ${v.storage_error}`:''}`;
}
function loadStartup(){
  if(startupLoading)return startupLoading;
  startupLoading=stationFetch('/receive/startup',{cache:'no-store',signal:AbortSignal.timeout(10000)}).then(r=>r.ok?r.json():null).then(v=>{if(v?.v===1){startupView=v;startupShow();}}).catch(()=>{}).finally(()=>{startupLoading=null;});
  return startupLoading;
}
$('monitor-off-startup').addEventListener('change',async event=>{
  const box=event.target,v=startupView;if(!v)return;box.disabled=true;$('startup-result').textContent='Saving';
  try{
    const response=await stationFetch('/receive/startup',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:v.profile_id,boot_id:v.boot_id,monitor_off_at_startup:box.checked}),signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);
    if(!response.ok||data?.v!==1)throw new Error(data?.error?.code||'request_failed');
    startupView=data;$('startup-result').textContent='Saved';
  }catch(error){$('startup-result').textContent=`Not saved · ${error.message}`;}
  startupShow();
});
// Log QSO: log the current contact now, without a form (DirectLog).
async function logQso(){if(snap?.contact?.dx_call)await send('open_log',{},'Log QSO');}
$('contact-log').addEventListener('click',logQso);
// WstxOperatingLayout::KeyboardShortcuts (WSJT-X keys where the function exists). Esc and
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
const activity=document.querySelector('#band-activity tbody');
function rowIdentity(row){
  const context=row.dataset.resultId?.split('/');if(!context||context.length<6)return null;
  const sequence=Number(row.dataset.sequence);if(!Number.isSafeInteger(sequence))return null;
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
// WstxContact::RoutesToRxFrequencyPane (sent/received dialogue) plus QsoPaneCrowding: other
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
// The automation state is read once per socket (then announced by automation.state).
addEventListener('station-ready',event=>{const fresh=event.detail!==readySocket;if(!fresh&&(contactMissing||snap&&snap.boot_id===profileData?.boot_id))return;readySocket=event.detail;load();if(fresh){loadAutomation();loadStartup();}});
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
if(socket?.readyState===WebSocket.OPEN&&connection.dataset.state==='connected'){readySocket=socket;load();loadAutomation();loadStartup();}
// WstxTransmit::TransmitWire: explicit requests only; the server plans, keys and halts.
document.querySelector('#transmit-status').insertAdjacentHTML('afterend','<label>Message<input id="tx-message" maxlength="37" value="CQ"></label><label>Mode<select id="tx-mode" disabled title="Follows the station operating mode"><option value="ft8">FT8</option><option value="ft4">FT4</option></select></label><label>Tx offset Hz<input id="tx-offset" type="number" min="200" max="2950" value="1500"></label><label>Period<select id="tx-parity"><option value="even">Even / 1st</option><option value="odd">Odd / 2nd</option></select></label><p><button type="button" id="tx-arm">Arm (Enable Tx)</button> <button type="button" id="tx-disarm">Disarm</button> <button type="button" id="tx-send">Send next period</button> <button type="button" id="tx-tune">Tune</button></p>');
let transmitSequence=0;
addEventListener('station-message',event=>{const m=event.detail?.message;if(m?.type==='station.tick'&&[15000,7500].includes(m.data?.period_ms)){const ft4=m.data.period_ms===7500;document.querySelector('#tx-mode').value=ft4?'ft4':'ft8';document.querySelector('#tx-offset').max=ft4?'2916':'2950';}});
async function transmitAction(extra,label){
  const result=document.querySelector('#transmit-result');
  try{const reply=await transmitPost('/transmit/command',extra),r=reply.result;result.textContent=`${label}: ${r.kind??(r.accepted?'accepted':'refused')}${r.refusal?' · '+r.refusal:''}${r.failure?' · '+r.failure:''}`;}
  catch(error){result.textContent=`${label} not sent · ${error.message}`;}
  transmitSync();
}
$('tx-arm').addEventListener('click',()=>{const revision=catStatus?.scope?.safety_revision;if(!revision){document.querySelector('#transmit-result').textContent='Arm needs the current setup revision (CAT status)';return;}transmitAction({action:'arm',safety_revision:revision},'Arm');});
$('tx-disarm').addEventListener('click',()=>transmitAction({action:'disarm'},'Disarm'));
$('tx-send').addEventListener('click',()=>{
  const mode=document.querySelector('#tx-mode').value,period=mode==='ft4'?7500:15000,wanted=document.querySelector('#tx-parity').value==='even'?0:1;
  let start=Math.floor(Date.now()/period)*period;if(Date.now()-start>=period*0.75-1000||(start/period)%2!==wanted)start+=period;if((start/period)%2!==wanted)start+=period;
  transmitSequence=Math.max(transmitSequence+1,Date.now());
  transmitAction({action:'request',request_sequence:transmitSequence,mode,period_start_utc_ms:start,message_text:document.querySelector('#tx-message').value,tx_offset_hz:Number(document.querySelector('#tx-offset').value)},'Send');
});
$('tx-tune').addEventListener('click',()=>{const on=transmitView?.transmit.tune;transmitAction(on?{action:'tune',enabled:false}:{action:'tune',enabled:true,tx_offset_hz:Number(document.querySelector('#tx-offset').value)},'Tune');});
document.querySelector('#server-fields-general .op-apply-row').insertAdjacentHTML('beforebegin','<label>Continent<select id="station-continent"><option value="">From locator</option><option value="AF">Africa</option><option value="AN">Antarctica</option><option value="AS">Asia</option><option value="EU">Europe</option><option value="NA">North America</option><option value="OC">Oceania</option><option value="SA">South America</option></select><small id="continent-derived"></small></label>');
document.querySelector('#settings-display h3').insertAdjacentHTML('afterend','<label>Theme<select id="theme-choice"><option value="dark">Dark</option><option value="day">Day</option><option value="night">Night (dim red)</option></select></label><label>Switch<select id="theme-switch"><option value="manual">Manually</option><option value="time">By time</option><option value="sun">By sunrise and sunset at my locator</option></select></label><span id="theme-times"><label>Day from<input id="theme-day-start" type="time" value="07:00"></label><label>Night from<input id="theme-night-start" type="time" value="20:00"></label></span><p id="theme-status" class="op-muted"></p>');
const maidenhead=grid=>{
  if(typeof grid!=='string'||!/^[A-R]{2}[0-9]{2}([A-X]{2})?$/i.test(grid))return null;
  const g=grid.toUpperCase(),sub=g.length===6;
  const lon=(g.charCodeAt(0)-65)*20-180+Number(g[2])*2+(sub?(g.charCodeAt(4)-65)*(2/24)+1/24:1);
  const lat=(g.charCodeAt(1)-65)*10-90+Number(g[3])+(sub?(g.charCodeAt(5)-65)*(1/24)+1/48:.5);
  return [lat,lon];
};
function distanceKm(from,to){
  const a=maidenhead(from),b=maidenhead(to);if(!a||!b)return null;
  const r=Math.PI/180,h=Math.sin((b[0]-a[0])*r/2)**2+Math.cos(a[0]*r)*Math.cos(b[0]*r)*Math.sin((b[1]-a[1])*r/2)**2;
  return Math.round(12742*Math.asin(Math.min(1,Math.sqrt(h))));
}
window.wstxRenderHistory=function renderHistory(body){
  for(const block of activityHistory){
    const divider=document.createElement('tr');divider.className='ba-divider';divider.setAttribute('role','row');
    const cell=document.createElement('td');cell.colSpan=7;cell.setAttribute('role','cell');cell.textContent=`${block.mode.toUpperCase()} period ${periodLabel(block.period,block.mode)}${block.period?' UTC':''}`;divider.append(cell);body.append(divider);
    for(const record of activityOrdering(block.rows))body.append(activityRow(record,'history',block.context,block.mode));
  }
}
window.wstxDistanceKm=distanceKm;
function chip(key,severity,text,action){const button=document.createElement('button');button.type='button';button.className='op-chip';button.dataset.chip=key;button.dataset.severity=severity;button.textContent=`${severity==='error'?'\u2716':'\u26A0'} ${text}`;button.title=text;button.addEventListener('click',action);return button;}
window.wstxChipsShow=function(){
  const list=[],connected=connection.dataset.state==='connected',open=section=>()=>showRegion('server-settings',null,section);
  if(connected){
    const mode=profileData?.settings.control.mode,radio=operatingState?.radio.state;
    if(mode==='cat'&&catStatus?.condition==='commissioningRequired')list.push(chip('cat','warn','CAT setup not confirmed',open('settings-cat')));
    else if(mode==='cat'&&catStatus&&catStatus.condition!=='ready')list.push(chip('cat','error',document.querySelector('#cat-status').textContent,open('settings-cat')));
    else if(mode==='cat'&&!catStatus&&radio&&radio!=='ready')list.push(chip('cat','error',`CAT ${radio}`,open('receive-details')));
    const a=live?.audio,active=live?.job&&['running','cancelling'].includes(live.job.state);
    if(a?.state==='unavailable')list.push(chip('audio','error',`Audio unavailable${a.error?' \u00b7 '+a.error:''}`,open('settings-audio')));
    const level=document.querySelector('#settings-audio .op-input-meter')?.dataset.level;
    if(active&&level==='low')list.push(chip('level','warn','Audio level low',open('settings-audio')));
    if(active&&level==='high')list.push(chip('level','warn','Audio overdriven',open('settings-audio')));
    if(transmitConfigured()&&transmitView?.clock==='unsynchronized')list.push(chip('clock','error','Clock off \u00b7 Tx blocked',open('settings-clock')));
    if(uncertainMutation)list.push(chip('receive','warn',receiveFailure||'Receive outcome unknown',open('receive-details')));
    else if(operatingFailure&&operatingSupported!==false)list.push(chip('selection','warn',operatingFailure,open('receive-details')));
    else if(operatingUnknown)list.push(chip('selection','warn','Band/mode outcome unknown',open('receive-details')));
    else if(operatingState?.operation?.result==='failed')list.push(chip('selection','error',`Band/mode change failed${operatingState.operation.error?' \u00b7 '+operatingState.operation.error:''}`,open('receive-details')));
    else if(live&&!active&&!mutationPending&&!receiveTarget()&&a?.state!=='unavailable'){
      if(profileData?.settings.audio.input_device)list.push(chip('receive','warn','Receive stopped \u00b7 start',()=>receiveToggle()));
      else list.push(chip('receive','warn','No audio input',open('server-fields-audio')));
    }
    if(performance.now()-restartedAt<60000)list.push(chip('restart','warn','Receive restarted',open('receive-details')));
  }
  const key=list.map(b=>b.dataset.chip+b.textContent).join('|');
  if(chips.dataset.key!==key){chips.dataset.key=key;chips.replaceChildren(...list);}
}
setInterval(()=>window.wstxChipsShow(),1000);
window.wstxChipsShow();if(typeof renderResults==='function')renderResults();
document.querySelector('#help-keys').insertAdjacentHTML('beforeend','<div><dt>CQ / Reply / double-click a decode</dt><dd>Start the QSO: transmission starts with the next period and ends after RR73/73 or HALT</dd></div><div><dt>F2</dt><dd>Settings</dd></div><div><dt>F4</dt><dd>Clear the DX call (cancel the contact)</dd></div><div><dt>Alt+1 &hellip; Alt+6</dt><dd>Next message Tx1&hellip;Tx6</dd></div><div><dt>Alt+M</dt><dd>Start or stop receive</dd></div><div><dt>Alt+T / Alt+Q</dt><dd>Tune / Log QSO</dd></div><div><dt>F11 / F12</dt><dd>Rx &minus;/+ 1 Hz</dd></div><div><dt>Shift+F11 / Shift+F12</dt><dd>Tx &minus;/+ 60 Hz (FT4 90 Hz)</dd></div><div><dt>Ctrl+F11 / Ctrl+F12</dt><dd>Rx and Tx &minus;/+ 1 Hz</dd></div><div><dt>Waterfall click / Shift+click / Ctrl+click</dt><dd>Set Rx / Tx / both; drag the Rx or Tx marker</dd></div><div><dt>Rx/Tx fields: wheel, arrows, &minus;/+</dt><dd>1 Hz; with Shift 10 Hz</dd></div><div><dt>Band Activity: click / double-click / right-click</dt><dd>Select / Reply / menu</dd></div><div><dt>Separator arrows / Home / End</dt><dd>Resize the spectrum and waterfall</dd></div>');
// WstxOperatingLayout::ThemeChoice: Day / Dark / Night for this browser only, manually, by
const themeKey='wstx.theme.v1';
function themeSettings(){let saved=null;try{saved=JSON.parse(localStorage.getItem(themeKey));}catch{}return {theme:['day','dark','night'].includes(saved?.theme)?saved.theme:'dark',mode:['manual','time','sun'].includes(saved?.mode)?saved.mode:'manual',day:/^\d\d:\d\d$/.test(saved?.day)?saved.day:'07:00',night:/^\d\d:\d\d$/.test(saved?.night)?saved.night:'20:00'};}
function sunTimes(locator,date=new Date()){
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
