'use strict';
// (WstxOperatingLayout::QsoPane, RxTxStrip, BandActivityView). The server owns the contact,
(()=>{
const focus=document.querySelector('#rx-focus');
if(!focus||document.body.dataset.profile!=='true')return;
const $=id=>document.getElementById(id);
// #45 CL-045-01: a plain setting, saved on change; it acts at the next station start.
block('settings-startup','Receive at startup',document.querySelector('#settings-general'),'<label class="op-check"><input type="checkbox" id="monitor-off-startup" disabled>Monitor off at startup</label><p id="startup-result" class="op-muted" role="status"></p><p class="op-muted">Saved at once; it takes effect at the next station start and does not restart receive.</p>');
block('settings-startup-resume','Startup resume',document.querySelector('#settings-expert'),'<p id="startup-resume" class="op-muted" role="status">Startup resume unknown</p>');
// #52 CL-052-01: off by default; read when Settings opens (at most every 30 s) or on Refresh, never polled.
block('settings-window-diagnostics','Decode window diagnostics',document.querySelector('#settings-expert'),'<label class="op-check"><input type="checkbox" id="window-dump" disabled>Save FT8 decode windows</label><p id="window-diagnostics" class="op-muted" role="status">Window counters unknown</p><button type="button" id="window-diagnostics-refresh">Refresh</button><p class="op-muted">Keeps the last 20 FT8 prompt windows (12 kHz WAV and JSON) in the profile folder diagnostic-windows. Saved at once; it acts from the next window.</p>');
block('settings-automation','MCP and automation',document.querySelector('#settings-general'),'<p class="op-muted">Automation runs on the station: a strategy or contest selected in the strategy element transmits only while Auto (beside CQ) is on, or an MCP client runs it. Its state shows beside the strategy element; HALT ends it and turns Auto off; Esc aborts the current QSO. A strategy keeps running through a page reload; with no browser or MCP client connected for 60 s, or 8 hours after Auto went on also with a browser open, it starts nothing new, finishes the QSO in progress and stops with Auto off (switch Auto on again to restart). The Tx watchdog stops transmitting when one message would be sent more often than its limit. A different message or a new contact starts the count again; after a stop only Enable Tx, a strategy selection or Auto on in this browser transmits again, automation never does.</p>');
block('settings-transmit','Transmit',document.querySelector('#settings-radio'),'<label>Tx watchdog (repetitions of one message)<input id="watchdog-tx" type="number" min="1" max="99" step="1" disabled></label><label>Tune watchdog (seconds)<input id="watchdog-tune" type="number" min="1" max="300" step="1" disabled></label><p id="watchdog-result" class="op-muted" role="status"></p><p class="op-muted">Watchdogs apply at once, as in WSJT-X. Tx power is set on the transceiver; this station sends no power command. PTT is chosen under CAT.</p>');
block('settings-log','Log',document.querySelector('#settings-logging'),'<p>Each completed QSO is logged at once, as in WSJT-X: saved in this station profile’s contacts.adi (ADIF) and sent to the UDP targets that select QSO Logged / Logged ADIF. There is no review step; Log QSO logs the current contact now.</p><button type="button" data-region="logbook">&#9776; Open Logbook</button>');
// #10 logbook.js (loaded first) made Update logbook from ADIF; it belongs below the Log block.
{const update=document.querySelector('#settings-update-log');if(update)document.querySelector('#settings-log')?.after(update);}
block('settings-udp','WSJT-X UDP interface',document.querySelector('#settings-logging'),'<p id="udp-note" class="op-muted">Send-only: programs listen; the station takes no command over UDP.</p><label>Instance name<input id="udp-instance" maxlength="64" autocomplete="off" disabled></label><h4 id="udp-targets-title">UDP targets</h4><div id="udp-targets" role="list" aria-labelledby="udp-targets-title"></div><p class="op-actions"><button type="button" id="udp-add" disabled>Add target</button><button type="button" id="udp-reload">Reload</button><button type="button" id="udp-save" class="op-primary" disabled>Save UDP settings</button></p><p id="udp-result" class="op-muted" role="status">Read when Settings opens</p><p class="op-muted">Applies on Save; it does not restart receive.</p>');
block('settings-pskreporter','PSK Reporter',document.querySelector('#settings-logging'),'<label class="op-check"><input type="checkbox" id="pskr-enabled" disabled>Listen to PSK Reporter spots</label><p id="pskr-status" class="op-muted" role="status">PSK Reporter status unknown</p><p id="pskr-result" class="op-muted" role="status"></p><p class="op-muted">Read-only, from mqtt.pskreporter.info: spots of my call and of the current strategy target. The station sends only its call in the client id and these two subscriptions. A strategy run uses them to choose between keeping and changing its Tx slot; everything works without them.</p>');
const stepper=(key,label,min,max)=>`<label class="op-strip-field">${label}<input id="contact-${key}" type="number" min="${min}" max="${max}" step="1" disabled inputmode="numeric" aria-label="${label} audio frequency, Hz"><span>Hz</span></label><button type="button" data-strip-step="${key}:-1" aria-label="${label} down 1 Hz (Shift: 10 Hz)" disabled>&minus;</button><button type="button" data-strip-step="${key}:1" aria-label="${label} up 1 Hz (Shift: 10 Hz)" disabled>+</button>`;
document.querySelector('#rxtx-strip').innerHTML=stepper('rx','Rx',0,3000)+stepper('tx','Tx',200,2950)+'<button type="button" id="strip-tx-from-rx" disabled>Tx=Rx</button><button type="button" id="strip-rx-from-tx" disabled>Rx=Tx</button><span id="strip-swr" hidden></span>';
const qsoButton=(id,label,title,extra='')=>`<button type="button" id="${id}" disabled title="${title}"${extra}>${label}</button>`;
document.querySelector('#contact-state').insertAdjacentHTML('afterend',`<p id="qso-heard" class="ct-line" hidden></p>
<p id="qso-autoseq" class="op-warning ct-autoseq" role="status" hidden><span id="qso-autoseq-text"></span> <button type="button" id="qso-suggest" hidden></button> <button type="button" id="qso-autoseq-on" title="Turn Auto Seq on">Auto Seq on</button></p>
<div id="qso-pskr-lines" class="ct-pskr-lines" role="status" hidden><p id="qso-hears" class="ct-line"></p><p id="qso-txslot" class="ct-line" hidden></p></div>
<div id="qso-next" class="op-qso-next" hidden><span id="qso-next-label" class="op-eyebrow">&#9656; next:</span><strong id="contact-next">None</strong><span id="qso-countdown" class="op-muted"></span><div class="op-qso-progress" aria-hidden="true"><i id="qso-progress"></i></div></div>
<p id="transmit-unavailable" class="op-unavailable">Transmission unavailable: this server does not offer transmit control.</p><p id="contact-unavailable" class="op-unavailable" hidden>Log QSO needs a running QSO.</p><p id="contact-result" class="op-muted" role="status"></p><p id="contact-logged" class="op-muted" role="status"></p>
`);
// WstxOperatingLayout::QsoPane item 8 (#37, operator 2026-11-04): the pane has a fixed height so
// the Control panel below it never moves. Its two sections have fixed heights and scroll inside:
// QSO (the #60 dialogue table, kept at its newest row) and Calling me (every station calling my
// call except the partner). The lines above them take the rest of the pane and scroll inside.
focus.querySelector('.op-contact-body').insertAdjacentHTML('afterend',`<section id="qso-section" class="ct-section" aria-label="QSO dialogue"><div id="qso-area" class="ct-qso-area"><table id="qso-table" class="ct-qso-table" hidden><thead><tr><th scope="col">UTC</th><th scope="col" data-short="Dir">Direction</th><th scope="col" data-short="Exch">Exchange</th><th scope="col" title="How often the identical message repeated">Rep</th><th scope="col" title="Our measured SNR of the partner's latest decode at or before this line" data-short="Rx">Rx SNR</th><th scope="col" title="The partner's latest report on us at or before this line" data-short="Tx">Tx SNR</th></tr></thead><tbody id="qso-dialogue" class="ct-dialogue" aria-label="QSO dialogue"></tbody></table><p id="qso-none" class="op-muted ct-placeholder">No QSO</p></div></section>
<section id="qso-calling" class="ct-section" aria-labelledby="calling-heading"><div id="calling-area" class="ct-calling-area"><table id="calling-table" class="ct-qso-table ct-calling-table"><thead><tr><th scope="col" id="calling-heading" title="Double-click a station to answer it (during a QSO: switch the contact to it)">Calling me</th><th scope="col">SNR</th><th scope="col">Grid</th><th scope="col">Country</th></tr></thead><tbody id="qso-others" class="ct-others" aria-label="Stations calling me (double-click or Enter answers)"></tbody></table><p id="qso-others-none" class="op-muted ct-placeholder">Nobody is calling</p></div></section>
<div class="op-qso-buttons" role="group" aria-label="QSO commands">${qsoButton('qso-cq','CQ','Call CQ: keys at once for the rest of my Tx period when it is early enough, otherwise from my next Tx period')}${qsoButton('qso-auto','Auto','Strategies are loading',' aria-pressed="false"')}${qsoButton('qso-pskr','PSK','Use PSK Reporter',' aria-pressed="false"')}${qsoButton('contact-tune','Tune','Tune (Alt+T)',' aria-pressed="false"')}<button type="button" id="qso-halt" class="op-halt-small" disabled title="Halt Tx: emergency stop (Alt+H)">HALT</button><button type="button" id="qso-abort" disabled title="Abort QSO (Esc): stop the transmission now and cancel the contact, without HALT">Abort QSO (Esc)</button>${qsoButton('contact-log','Log QSO','Log QSO (Alt+Q)',' aria-describedby="contact-unavailable"')}</div>`);
const confirmDialog=document.createElement('dialog');confirmDialog.id='op-confirm';confirmDialog.className='op-dialog';confirmDialog.innerHTML='<form method="dialog"><p id="op-confirm-text"></p><menu><button type="button" class="op-halt-small" id="op-confirm-halt" title="Halt Tx: emergency stop (Alt+H)">HALT</button><button value="cancel" type="submit">Cancel</button><button value="ok" type="submit" class="op-primary" id="op-confirm-ok">Continue</button></menu></form>';
window.wstxConfirm=function(text,okLabel='Continue'){
  confirmDialog.querySelector('#op-confirm-text').textContent=text;confirmDialog.querySelector('#op-confirm-ok').textContent=okLabel;
  return new Promise(resolve=>{confirmDialog.returnValue='';confirmDialog.querySelector('#op-confirm-halt').disabled=halt.disabled;confirmDialog.addEventListener('close',()=>resolve(confirmDialog.returnValue==='ok'),{once:true});confirmDialog.showModal();confirmDialog.querySelector('#op-confirm-ok').focus();});
}
// The modal popup makes the page inert, so it carries HALT itself (same action and state).
confirmDialog.querySelector('#op-confirm-halt').addEventListener('click',()=>{confirmDialog.close('cancel');halt.click();});
main.append(confirmDialog);
document.querySelector('#band-activity').insertAdjacentHTML('afterbegin','<div id="strategy-element" class="op-strategy-bar" role="group" aria-label="Strategy"><span class="op-strategy-label">Strategy</span><select id="strategy-name" disabled aria-label="Strategy name" title="Strategies are loading"><option value="">None</option></select><button type="button" id="strategy-edit" disabled aria-label="Edit strategy" title="Strategies are loading">&#9998;</button><button type="button" id="activity-value" aria-pressed="true" title="Sort Band Activity by value">Value</button><button type="button" id="strategy-contest" disabled title="Contest strategies are loading">Contest</button><button type="button" id="activity-show-all" aria-pressed="false" hidden title="Also show the stations a contest strategy cannot call">Show all</button><span id="station-automation" class="op-automation" role="status">Automation idle</span></div>');
const slotsMarkup=['tx1','tx2','tx3','tx4','tx5','tx6'];
focus.querySelector('.op-contact-body').insertAdjacentHTML('beforeend',`<details id="qso-more"><summary title="Messages Tx1&ndash;Tx6 and activity" aria-label="Messages Tx1&ndash;Tx6 and activity">Tx1&ndash;Tx6</summary><div class="ct-more-body"><div class="ct-dx"><label>Activity<select id="contact-activity" disabled><option value="none">None</option><option value="na_vhf">NA VHF</option><option value="eu_vhf">EU VHF</option><option value="ww_digi">WW Digi</option><option value="arrl_digi">ARRL Digi</option><option value="field_day">Field Day</option><option value="rtty">RTTY Roundup</option><option value="hound">Hound</option></select></label><label title="Field Day: class and section, e.g. 1A EMA. RTTY Roundup: state or province, or DX or # for a serial number">Exchange<input id="contact-exchange" maxlength="8" autocomplete="off" spellcheck="false" disabled></label><span id="contact-serial" class="op-muted"></span></div><ol id="contact-messages" class="ct-messages" aria-label="Standard messages Tx1 to Tx6">${slotsMarkup.map((s,i)=>`<li data-slot="${s}"><label class="ct-next"><input type="radio" name="contact-next" value="${s}" aria-label="Next message Tx${i+1}" disabled>Tx${i+1}</label><button type="button" class="ct-now" data-slot="${s}" aria-label="Send Tx${i+1} now" title="Send Tx${i+1} from the next own period (turns Enable Tx on)" disabled>Now</button><input class="ct-text" data-slot="${s}" maxlength="37" aria-label="Tx${i+1} message" autocomplete="off" spellcheck="false" disabled>${s==='tx1'?'<label class="op-check"><input type="checkbox" id="contact-tx1-skip" disabled>Skip Tx1</label>':''}${s==='tx4'?'<label class="op-check"><input type="checkbox" id="contact-rr73" disabled>RR73</label>':''}</li>`).join('')}</ol>
<div class="op-frequency-fields ct-fields"><button type="button" id="contact-cancel" disabled>Cancel contact</button><span id="contact-watchdog" class="op-muted"></span></div></div></details>`);
// QsoPane item 8 (#37, 2026-11-04): the header holds the partner line and the badge, then the
// partner's last message, the direct buttons and the Tx1-Tx6 fold-out, which opens over the pane
// (it moves nothing). NEXT leads the message lines below it.
{const head=focus.querySelector('.op-qso-head'),tools=document.createElement('div');tools.className='ct-head-tools';
  tools.append(focus.querySelector('.op-qso-buttons'),$('qso-more'));head.append($('qso-heard'),tools);}
// WstxOperatingLayout::LowerPanel (#37, operator 2026-11-03): one vertical column on the right,
// the QSO pane, the Control panel and the error field, each the width of the QSO pane card.
const qsoColumn=document.createElement('div');qsoColumn.id='qso-column';qsoColumn.className='op-qso-column';
focus.before(qsoColumn);qsoColumn.append(focus);
qsoColumn.insertAdjacentHTML('beforeend',`<section id="qso-control" class="op-card op-lower" aria-labelledby="control-heading"><h3 id="control-heading" class="op-lower-head">Control</h3><div class="op-control-grid"><div class="op-control-row"><label>DX Call<input id="dx-call" maxlength="13" autocomplete="off" spellcheck="false" disabled></label><label>DX Grid<input id="dx-grid" maxlength="6" autocomplete="off" spellcheck="false" disabled></label><button type="button" id="dx-generate" disabled>Generate</button><label>Report<input id="contact-report" type="number" min="-50" max="49" step="1" disabled><span>dB</span></label></div><div class="op-control-row"><label class="op-check"><input type="checkbox" id="contact-auto" disabled aria-label="Auto sequence unavailable">Auto Seq</label><label class="op-check" title="While calling CQ, answer the first station that calls me (WSJT-X Call 1st)"><input type="checkbox" id="contact-call-first" disabled>Call 1st</label><label class="op-check" title="Keep the Tx audio frequency when a station is selected"><input type="checkbox" id="contact-hold" disabled>Hold Tx</label><label>Tx<select id="contact-parity" disabled aria-label="Tx period"><option value="even">Even / 1st</option><option value="odd">Odd / 2nd</option></select></label></div></div></section>
<section id="error-field" class="op-card op-lower" aria-labelledby="error-heading"><h3 id="error-heading" class="op-lower-head">Problems</h3><div class="op-error-body"><p class="op-muted op-error-none" role="status">No problems</p></div></section>`);
// WstxOperatingLayout::ErrorField (CL-037-02): the former top-bar exception chips, current only.
const errorBody=qsoColumn.querySelector('#error-field .op-error-body');
// A wheel notch moves by at most the visible height, so no line is skipped where the block has only one (1366x768).
errorBody.addEventListener('wheel',event=>{if(errorBody.scrollHeight<=errorBody.clientHeight||errorBody.clientHeight>=Math.abs(event.deltaY))return;event.preventDefault();errorBody.scrollTop+=Math.sign(event.deltaY)*errorBody.clientHeight;},{passive:false});
chips.setAttribute('role','list');chips.setAttribute('aria-label','Problems the operator must act on');chips.className='op-error-list';
errorBody.prepend(chips);const notice=document.querySelector('#station-notice');if(notice)errorBody.prepend(notice);
const body=focus.querySelector('.op-contact-body'),identity=focus.querySelector('.op-contact-identity');
const slots=['tx1','tx2','tx3','tx4','tx5','tx6'];
const resultText=$('contact-result');
let dxLookup={call:null,entity:null},snap=null,sending=false,tick=null,changeTarget=null,lastLog=null,loggedTimer=null,wasRunning=false,lastPartner=null,bandPartner=null;
// #50 CL-050-08: the QSO partner of Band Activity, from the contact snapshot this page already holds.
window.wstxPartner=()=>bandPartner;
const valid=s=>s&&s.v===1&&Object.keys(s).sort().join(',')==='boot_id,contact,contact_revision,log,monotonic_ms,profile_id,settings,snapshot_sequence,transmit,utc_ms,v,watchdog'&&Number.isSafeInteger(s.contact_revision);
const transmitCapable=()=>snap&&snap.transmit.capability!=='unsupported';
// What the station can key now: unavailable is #9's radio/authorization not ready (CL-010-07).
const transmitReady=()=>snap?.transmit.capability==='available';
// One GET /contact at a time; a caller during a pending GET waits for a fresh one.
// contactMissing: this station has no contact engine (404); routine refreshes then skip /contact.
let loading=null,queued=null,contactMissing=false;
function load(){
  if(!loading){loading=fetchSnapshot().finally(()=>{loading=null;});return loading;}
  if(!queued)queued=loading.then(()=>{queued=null;return load();});
  return queued;
}
// WstxContact::OperatorDisplays StationPeriodClock (#50): the station's UTC (the clock the
// transmitter keys on), never the browser's wall clock. Each station observation gives an
// offset over this browser's monotonic clock; a late delivery only lowers it, so the largest
// offset of the last 20 s is the estimate. An offset more than 500 ms below the estimate is a
// backward step of the station clock (#43 correction), which restarts the estimate at once.
let clockSamples=[];
const CLOCK_STEP_MS=500;
function stationSample(utc){
  if(!Number.isSafeInteger(utc))return;const at=performance.now(),offset=utc-at,now=stationNow();
  clockSamples=now!==null&&offset<now-at-CLOCK_STEP_MS?[]:clockSamples.filter(s=>at-s[0]<=20000);
  clockSamples.push([at,offset]);
}
function stationNow(){
  if(!clockSamples.length)return null;const at=performance.now(),recent=clockSamples.filter(s=>at-s[0]<=20000);
  return at+Math.max(...(recent.length?recent:clockSamples.slice(-1)).map(s=>s[1]));
}
async function fetchSnapshot(){
  try{
    const response=await stationFetch('/contact',{cache:'no-store',signal:AbortSignal.timeout(10000)});
    contactMissing=response.status===404;
    // #51: a contact snapshot this page cannot validate shows the reload chip.
    // #74 PushedStationState: a reply of another boot than the browser's is discarded.
    if(response.ok){const value=await response.json();window.wstxStationData?.('contact',valid(value));if(valid(value))stationSample(value.utc_ms);if(valid(value)&&value.boot_id===profileData?.boot_id&&(!snap||snap.boot_id!==value.boot_id||value.snapshot_sequence>=snap.snapshot_sequence)){snap=value;render();}heldWake();}
  }catch{}
}
// WstxContact::ContactStateEvent (#10): show what recording.js holds from the station's events,
// unless this client's own read is newer.
function stateShow(){
  const view=contactHeld;if(!view)return;
  window.wstxStationData?.('contact',valid(view));
  if(valid(view)&&view.boot_id===profileData?.boot_id){stationSample(view.utc_ms);if(!snap||snap.boot_id!==view.boot_id||view.snapshot_sequence>=snap.snapshot_sequence){snap=view;render();}}
  heldWake();
}
// WstxStationProtocol::PushedStationState (#74): a new boot drops the contact state at once;
// the QSO pane shows its freshly loaded form until the new boot's read or first event.
addEventListener('station-boot',()=>{snap=null;render();});
// #10 PushedStationState: an accepted command's result comes in contact.state; the next command
// waits for the revision of its receipt there. Only a receipt that does not come in time reads GET /contact.
let heldWaiters=[];
function heldWake(){heldWaiters=heldWaiters.filter(w=>{if(snap&&snap.boot_id===w.boot&&snap.contact_revision>=w.revision){w.resolve(true);return false;}return true;});}
// The newest receipt of this browser's commands: the station's own statement of its revision.
let receiptSeen=null;
const revisionOf=s=>Math.max(s.contact_revision,receiptSeen?.boot===s.boot_id?receiptSeen.revision:-1);
// Resolves once no accepted command's result is still on its way: a choice made from the held state
// (Log QSO, a row's double-click) waits for it, a command itself does not.
const settled=()=>Promise.all(heldWaiters.map(w=>w.done));
function held(boot,revision,ms=5000){let w;const done=new Promise(resolve=>{w={boot,revision,resolve};});w.done=done;heldWaiters.push(w);heldWake();setTimeout(()=>{if(heldWaiters.includes(w)){heldWaiters=heldWaiters.filter(x=>x!==w);w.resolve(false);}},ms);return done;}
const ids=()=>snap&&{v:1,profile_id:snap.profile_id,boot_id:snap.boot_id};
// Commands are sent one at a time, each with the revision of the latest snapshot.
let sendChain=Promise.resolve();
function send(...args){const run=sendChain.then(()=>sendNow(...args));sendChain=run.catch(()=>{});return run;}
async function sendNow(action,params={},label=action){
  if(!snap){resultText.textContent='Contact state unavailable';return null;}
  const body={...ids(),command_id:crypto.randomUUID(),contact_revision:revisionOf(snap),action,...params},before=running(snap.contact);
  resultText.textContent=`${label}: pending · waiting for the station`;sending=true;let receipt=null,refused=false;
  try{
    const response=await stationFetch('/contact/command',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);
    if(response.status===202||response.status===200){resultText.textContent=`${label}: accepted`;if(Number.isSafeInteger(data?.contact_revision)){receipt=data;if(!(receiptSeen?.boot===body.boot_id&&receiptSeen.revision>=data.contact_revision))receiptSeen={boot:body.boot_id,revision:data.contact_revision};}return data;}
    const code=data?.error?.code??`http_${response.status}`;refused=data?.error?.code==='stale_revision'?`stale_${data.error.field??'contact_revision'}`:data?.error?.code??false;
    resultText.textContent=`${label}: refused · ${code}${code==='stale_revision'?' · station state changed, review and retry':''}`;
    return {refused:code,reason:data?.error?.reason,field:data?.error?.field??null,sent:body.contact_revision,boot:body.boot_id};
  }catch(error){resultText.textContent=`${label}: outcome unknown · ${error.message}`;return null;}
  // The next command goes with the receipt's revision at once; contact.state brings the result, and only
  // when it does not within 5 s is the snapshot read. A refusal changed nothing: a stale contact revision
  // waits up to 2.5 s for a newer one before a retry, any other stale field (safety_revision) is read at once,
  // as is an unknown outcome. A command that ended the QSO (Log QSO) leaves no accepted result in the idle pane.
  finally{sending=false;
    const ended=()=>{if(before&&!running(snap?.contact)&&/: accepted$/.test(resultText.textContent))resultText.textContent='';};
    if(receipt)held(body.boot_id,receipt.contact_revision).then(async ok=>{if(!ok)await load();ended();});
    // A stale contact revision waits in sendExplicit, outside this chain, so an abort behind it is not held.
    else{if(refused!=='stale_contact_revision'&&(!refused||refused.startsWith('stale_')))await load();ended();}}
}
// The keyboard halt itself (Alt+H) is sent by recording.js, which is loaded at once;
// this client only shows its outcome.
addEventListener('keyboard-halt',event=>{
  const h=event.detail?.reply?.halt_state;
  if(h)resultText.textContent=`Halt: ${h==='stopped'?'stopped (confirmed)':h==='idle'?'nothing was transmitting':'pending · not yet confirmed'}`;
  load();
});
// WstxContact::AbortQso (#39): Esc and the Abort QSO button stop the transmission now
// and cancel the contact; the station is not halted. The server decides what stops.
const abortButton=document.createElement('button');abortButton.type='button';abortButton.id='abort-qso';abortButton.className='op-abort';abortButton.textContent='Abort QSO (Esc)';abortButton.title='Abort QSO (Esc): stop the transmission now and cancel the contact, without HALT';abortButton.disabled=true;
document.querySelector('#halt-tx')?.after(abortButton);
const abortable=()=>{const c=snap?.contact,t=snap?.transmit;return !!snap&&((c&&!['idle','cancelled','completed'].includes(c.state))||t?.arm_state==='armed'||!!tick?.transmitting);};
// Each Esc or Abort QSO counts: what a gesture queued before it (a retry, its Enable Tx) is then not sent.
let aborts=0;
function abortQso(){aborts++;if(abortable()||sending||heldWaiters.length)send('abort',{},'Abort QSO');}
abortButton.addEventListener('click',abortQso);
// ---------------------------------------------------------------- render
const transmitting=c=>!!c&&!['idle','completed','cancelled'].includes(c.state);
// #37 QsoPane: a running QSO is a contact with a partner in replying..signoff; a completed,
// logged or cancelled contact is gone from the pane.
const running=c=>!!c?.dx_call&&['replying','report','roger_report','rogers','signoff'].includes(c.state);
const snrText=snr=>typeof snr==='number'?`${snr>0?'+':snr<0?'\u2212':''}${Math.abs(Math.round(snr))} dB`:'';
function setValue(input,value){if(document.activeElement!==input)input.value=value??'';}
function render(){
  const c=snap?.contact,t=snap?.transmit,s=snap?.settings,ready=transmitReady(),armed=t?.arm_state==='armed';
  const qso=running(c);
  focus.dataset.contact=qso?'true':c?.state==='calling'?'calling':'';
  // Nothing of a finished contact stays: an accepted command's result goes with it.
  if(wasRunning&&!qso&&/: accepted$/.test(resultText.textContent))resultText.textContent='';
  wasRunning=qso;
  // #50 CL-050-08: from the preparation (replying) until logged (completed) or cancelled; a change redraws Band Activity.
  const partner=qso?String(c.dx_call).toUpperCase():null;if(partner!==bandPartner){bandPartner=partner;if(typeof renderResults==='function')renderResults();}
  // The partner of the last running QSO stays out of the Others until another contact runs.
  if(qso||(c?.state==='completed'&&c.dx_call))lastPartner=c.dx_call;
  const strong=identity.querySelector('strong'),detail=identity.querySelector('div > span');
  if(qso){
    const km=c.dx_grid&&typeof distanceKm==='function'?distanceKm(profileData?.settings?.locator,c.dx_grid):null;
    strong.textContent=`${c.dx_call}${c.dx_grid?' · '+c.dx_grid:''}`;
    const approx=km===null&&Number.isInteger(dxLookup.entity?.km)&&dxLookup.call===c.dx_call?`~${dxLookup.entity.km} km`:null;
    detail.textContent=`${dxEntity(c.dx_call)}${km!==null?`${km} km · `:approx?`${approx} · `:''}sent ${c.report_sent??'none'} · rcvd ${c.report_rcvd??'none'}`;
  }
  else if(c){const cq=c.state==='calling';strong.textContent=cq?'Calling CQ':'No contact selected';detail.textContent=cq?(s?.parity==='odd'?'Tx odd (2nd)':'Tx even (1st)'):'Select a decoded station or enter a DX call.';}
  for(const id of ['dx-call','dx-grid','dx-generate','contact-activity','contact-exchange','contact-report','contact-parity','contact-tx1-skip','contact-rx','contact-tx','contact-hold','strip-tx-from-rx','strip-rx-from-tx'])$(id).disabled=!snap;
  for(const button of document.querySelectorAll('#rxtx-strip [data-strip-step]'))button.disabled=!snap;
  focus.querySelector('.op-contact-badge').textContent=!snap?'Unavailable':armed?(tick?.transmitting?'Transmitting':'Tx on'):ready?'Ready':'Receive only';
  focus.dataset.armed=String(armed);
  for(const [i,slot] of slots.entries()){
    const row=focus.querySelector(`li[data-slot="${slot}"]`),text=row.querySelector('.ct-text'),radio=row.querySelector('input[type=radio]');
    const message=c?.messages?.[i]??null;setValue(text,message);text.disabled=!message&&!(slot==='tx5'&&c);radio.disabled=!message;radio.checked=c?.next_slot===slot;
    row.classList.toggle('ct-next-row',c?.next_slot===slot);
  }
  $('contact-tx1-skip').checked=!!s?.tx1_skip;$('contact-rr73').checked=c?.tx4==='rr73';$('contact-rr73').disabled=!c?.dx_call;
  if(s){setValue($('contact-report'),s.report);setValue($('contact-rx'),s.rx_hz);setValue($('contact-tx'),s.tx_hz);$('contact-hold').checked=s.hold_tx;if(document.activeElement!==$('contact-parity'))$('contact-parity').value=s.parity;if(document.activeElement!==$('contact-activity'))$('contact-activity').value=s.activity??'none';if(document.activeElement!==$('contact-exchange')&&s.exchange!==shownExchange){shownExchange=s.exchange;$('contact-exchange').value=s.exchange??'';}$('contact-serial').textContent=s.activity==='eu_vhf'||(s.activity==='rtty'&&(s.exchange==='DX'||s.exchange==='#'))?`Serial ${String(s.serial??1).padStart(4,'0')}`:'';$('contact-auto').checked=s.auto_seq;$('contact-call-first').checked=s.call_first!==false;
    setValue($('watchdog-tx'),s.tx_calls);setValue($('watchdog-tune'),s.tune_seconds);}
  $('watchdog-tx').disabled=$('watchdog-tune').disabled=!snap;
  $('contact-call-first').disabled=!transmitCapable();
  const auto=$('contact-auto');auto.disabled=!ready;auto.setAttribute('aria-label',ready?'Auto sequence':'Auto sequence unavailable');
  // WstxContact::SetEnableTx (#37): no Enable Tx control; CQ or a double-click starts a QSO
  // (no Reply button since the #50 double-click fix).
  $('qso-cq').disabled=!ready||(armed&&c?.state==='calling');
  // #37: no RR73/73 buttons; a fold-out Now is the manual override. Not on a finished contact:
  // there Enable Tx would start a new CQ.
  const finished=['completed','cancelled'].includes(c?.state);
  for(const button of focus.querySelectorAll('.ct-now'))button.disabled=!ready||finished||!c?.messages?.[slots.indexOf(button.dataset.slot)];
  for(const id of ['qso-cq','contact-tune'])if(ready)$(id).removeAttribute('aria-describedby');else $(id).setAttribute('aria-describedby','transmit-unavailable');
  $('transmit-unavailable').hidden=ready;
  $('transmit-unavailable').textContent=!snap?'Transmission unavailable: contact state unknown.':t?.capability==='unavailable'?'Transmission unavailable: radio/authorization not ready.':'Transmission unavailable: this server does not offer transmit control.';
  const tune=$('contact-tune');tune.disabled=!ready&&!t?.tune;tune.setAttribute('aria-pressed',String(!!t?.tune));tune.textContent=t?.tune?`Tune on · ${snap.watchdog.tune_remaining_seconds} s`:'Tune';
  $('contact-cancel').disabled=!c||['idle','cancelled'].includes(c.state);
  abortButton.disabled=!abortable();$('qso-abort').disabled=abortButton.disabled;
  // Log QSO while a QSO runs (it also closes it); a finished contact is gone from the pane.
  // The reason stays the disabled button's description without taking a line.
  const log=$('contact-log');log.disabled=!qso;$('contact-unavailable').hidden=true;
  if(qso)log.removeAttribute('aria-describedby');else log.setAttribute('aria-describedby','contact-unavailable');
  // NEXT only while Enable Tx is on for a CQ or a running QSO.
  $('qso-next').hidden=!(armed&&(qso||c?.state==='calling'));
  $('contact-next').textContent=c?(c.messages[slots.indexOf(c.next_slot)]??'None'):'None';
  // The partner's latest message to me, with SNR and the repeat count (ContactSnapshot last_rcvd).
  const h=qso?c.last_rcvd:null,heard=$('qso-heard');heard.hidden=!h;
  heard.textContent=h?`\u25C2 ${h.text}  ${snrText(h.snr)}${h.count>1?` \u00D7${h.count}`:''}`.trimEnd():'';
  const wd=snap?.watchdog;$('contact-watchdog').textContent=!wd?'':wd.tx_expired?`Tx watchdog: same message sent ${snap.settings.tx_calls} times`:armed?watchdogText(wd):'';
  // The status line is for exceptions only: unknown state, a refusal, a pending halt.
  const problems=!snap?['Contact state unavailable']:[t?.refusal?`Refused ${t.refusal}`:'',t?.halt_state==='pending'?'Halt pending (RF stop not confirmed)':''].filter(Boolean);
  $('contact-state').textContent=problems.join(' · ');$('contact-state').hidden=!problems.length;
  autoSeqShow(c,s);
  dialogueShow(qso?c:null);
  markers();
  stationTx();countdown();
  othersShow();if(activity)for(const tr of activity.querySelectorAll('tr[data-sequence]'))if(!tr.hasAttribute('tabindex'))tr.tabIndex=0;
  logShow();
  // The Auto toggle (strategy client) is disabled without transmit capability.
  dispatchEvent(new CustomEvent('wstx-contact-render'));
}
// #37 QsoPane item 7: the server-owned dialogue of the running QSO, oldest first, kept at
// its newest line; it scrolls inside its fixed-height section (#qso-area) and goes with the QSO.
const hhmmss=ms=>Number.isFinite(ms)?new Date(ms).toISOString().slice(11,19):'--:--:--';
// #60 QsoPane QSO table: UTC | Direction | Exchange | Rep | Rx SNR | Tx SNR. Direction is the two
// calls as on the air, recipient first, with "◂" pointing to the recipient (a hashed call
// as decoded, "<...>" too); a CQ is "CQ [DX] <call>" with its grid as the exchange; another
// message is all exchange. Rep is ×N for a repeated message. On every dialogue row Rx SNR
// (ours) and Tx SNR (the partner's report on us, R-02 → −2) are the latest received values at
// or before it (operator 2026-11-03); an Others row shows its own.
const signedDb=n=>typeof n==='number'?(n=Math.round(n),n>0?`+${n}`:n<0?`−${-n}`:'0'):'';
const isCall=w=>/^<[^>]+>$/.test(w)||/^(?=.*[A-Z])(?=.*\d)[A-Z0-9/]+$/.test(w);
function qsoParts(text){
  const w=(text??'').trim().split(/\s+/).filter(Boolean);let direction='',exchange=text??'';
  if(w[0]==='CQ'){const grid=w.length>2&&/^[A-R]{2}\d{2}$/.test(w.at(-1));direction=(grid?w.slice(0,-1):w).join(' ');exchange=grid?w.at(-1):'';}
  else if(w.length>=2&&isCall(w[0])&&isCall(w[1])){direction=`${w[0]} ◂ ${w[1]}`;exchange=w.slice(2).join(' ');}
  return {direction,exchange};
}
// The report a received message carries (R-02 → −2, -05 → −5), else null.
const qsoReport=text=>{const m=/^R?([+-]\d{2})$/.exec(qsoParts(text).exchange);return m?Number(m[1]):null;};
function qsoRow(utc,text,rxSnr,txSnr,count){
  const {direction,exchange}=qsoParts(text);
  const tr=document.createElement('tr');
  for(const cell of [utc,direction,exchange,count>1?`×${count}`:'',signedDb(rxSnr),signedDb(txSnr)]){const td=document.createElement('td');td.textContent=cell;tr.append(td);}
  return tr;
}
function dialogueShow(c){
  const list=$('qso-dialogue'),entries=Array.isArray(c?.dialogue)?c.dialogue:[];
  const key=JSON.stringify(entries);if(list.dataset.key===key)return;list.dataset.key=key;
  let rxSnr=null,txSnr=null;// the latest received values so far, oldest entry first
  list.replaceChildren(...entries.map(e=>{
    if(e.dir==='rx'){if(typeof e.snr==='number')rxSnr=e.snr;txSnr=qsoReport(e.text)??txSnr;}
    const tr=qsoRow(hhmmss(e.period_utc_ms),e.text,rxSnr,txSnr,e.count);tr.dataset.dir=e.dir;return tr;
  }));
  // The section keeps its height: "No QSO" in place of an empty table.
  $('qso-table').hidden=!entries.length;$('qso-none').hidden=!!entries.length;
  const area=$('qso-area');area.scrollTop=area.scrollHeight;
}
// #55 WstxDxcc: the partner's country and continent in the QSO pane header (first on its
// detail line, so the compact header keeps one row), looked up
// once per DX call (GET /dxcc?call=).
function dxEntity(call){
  if(dxLookup.call!==call){
    dxLookup={call,entity:null};
    // The call is A-Z 0-9 / only: sent as it is (the station refuses an encoded slash).
    stationFetch(`/dxcc?call=${call}`,{cache:'no-store',signal:AbortSignal.timeout(10000)}).then(r=>r.ok?r.json():null).then(v=>{if(dxLookup.call===call&&v?.entity){dxLookup.entity=v.entity;render();}}).catch(()=>{});
  }
  const e=dxLookup.entity;return e?`${e.name} (${e.cont}) · `:'';
}
// #11: Auto Seq off is shown on the QSO pane while a contact or CQ runs, and the step Auto
// Seq would take after the partner's latest message (suggested_slot, e.g. 73 after their
// RR73) is offered as one button instead of repeating the previous message silently.
function autoSeqShow(c,s){
  const node=$('qso-autoseq'),suggest=$('qso-suggest'),off=!!s&&!s.auto_seq&&transmitting(c);
  const slot=c?.suggested_slot,message=slot&&transmitting(c)?c.messages?.[slots.indexOf(slot)]:null;
  node.hidden=!off&&!message;
  $('qso-autoseq-text').textContent=off?`Auto Seq off${message?` · ${c.dx_call} expects`:''}`:message?`${c.dx_call} expects`:'';
  node.title=off?'Auto Seq is off: received messages do not advance the QSO':'';
  // The exchange word only ("Send 73 next"), so the line stays one row; the title has the text.
  const word=message?message.split(' ').slice(2).join(' ')||message:'';
  suggest.hidden=!message;suggest.textContent=message?`Send ${word} next`:'';suggest.title=message?`Send ${message} next`:'';suggest.dataset.slot=slot??'';
  $('qso-autoseq-on').hidden=!off||!transmitReady();
}
$('qso-suggest').addEventListener('click',async()=>{
  const slot=$('qso-suggest').dataset.slot;if(!slot)return;
  const from=aborts,r=await send('choose_next',{slot},`Next ${slot.toUpperCase()}`);if(!r||r.refused||from!==aborts)return;
  if(snap?.transmit.arm_state!=='armed'&&transmitReady())arm('Reply');
});
$('qso-autoseq-on').addEventListener('click',()=>send('set_auto_seq',{enabled:true},'Auto sequence'));
// WstxContact::DirectLog (#41): the server logs each completed QSO and every Log QSO; the
// pane shows the latest outcome, and an open Logbook page lists a newly saved record.
const logReasons={storage_unavailable:'storage unavailable · retrying',log_queue_full:'too many unsaved QSOs · the oldest was not logged',log_invalid_field:'the station profile is incomplete'};
const LOGGED_NOTICE_MS=8000;
function logShow(){
  const l=snap?.log,node=$('contact-logged');
  const key=l&&`${l.contact_id}/${l.outcome}`,fresh=!!key&&key!==lastLog&&lastLog!==null;
  if(l&&l.outcome!=='saved'){clearTimeout(loggedTimer);loggedTimer=null;node.textContent=`Not logged ${l.call} · ${logReasons[l.error]??l.error??'saving'}`;}
  else if(fresh){node.textContent=`\u2713 Logged ${l.call}`;clearTimeout(loggedTimer);loggedTimer=setTimeout(()=>{loggedTimer=null;node.textContent='';node.hidden=true;},LOGGED_NOTICE_MS);}
  else if(!loggedTimer)node.textContent='';
  node.hidden=!node.textContent;
  if(fresh&&l.outcome==='saved'&&main.dataset.region==='logbook')window.wstxLogbook?.loadHistory(null);
  if(key)lastLog=key;else if(lastLog===null&&snap)lastLog='';
}
const stationTxNode=document.createElement('span');stationTxNode.id='station-tx';stationTxNode.className='ct-station-tx';stationTxNode.setAttribute('role','status');stationTxNode.hidden=true;
document.querySelector('#halt-tx')?.before(stationTxNode);
// WstxMcp::AutomationIndicator: the run state sits in the strategy element (its line is drawn by
// the strategy client from both snapshots, #74 D1); HALT ends it. GET /automation is read only
// after an automation.state event (#74): null is the never-used state, held without a request.
let automationLoading=null,automationView=null;
function loadAutomation(){
  if(automationLoading)return automationLoading;
  const loading=automationLoading=stationFetch('/automation',{cache:'no-store',signal:AbortSignal.timeout(10000)}).then(r=>r.ok?r.json():null).then(a=>{
    // WstxStationProtocol::PushedStationState: a reply of another boot is discarded.
    if(loading!==automationLoading||a?.v!==1||a.boot_id!==profileData?.boot_id)return;
    automationView=a;freeTxSlotsRead(a);pskrLinesShow();leaveShow();dispatchEvent(new CustomEvent('wstx-automation',{detail:a}));
  }).catch(()=>{}).finally(()=>{if(loading===automationLoading)automationLoading=null;});
  return loading;
}
// #97 WstxStrategy::LeaveCountLabel (#91): WD:n is the Tx watchdog only; in a strategy run's own
// contact (tx_remaining_calls null) the run's leave label stands where WD:n stood.
function leaveLabel(){
  const run=automationView?.run,l=run?.leave;
  if(!l||run.contact_id!==snap?.contact?.id)return '';
  const n=l.remaining;
  return l.mode==='calls'?`Leave in ${n} calls`:l.mode==='until_logged'?(n==null?'Until logged':`Until logged · leave if gone ${n} min`):l.staying?'Stay · most valuable':`Leave in ${n} Tx changes`;
}
// #97 WstxContact::BusyPartner: while the partner is busy " · <call> busy with <other>, not
// counted (<k>/<N>)" follows WD:n (k the paused calls of the message due) or, in a run's own
// contact, the leave label (k the run's paused calls).
function busySuffix(wd,k){
  const other=wd?.busy_with,call=snap?.contact?.dx_call;
  return other&&call?` · ${call} busy with ${other}, not counted (${k}/${snap.settings.tx_calls})`:'';
}
function watchdogText(wd){
  if(typeof wd.tx_remaining_calls==='number')return `WD:${wd.tx_remaining_calls}${busySuffix(wd,wd.paused_calls??0)}`;
  const label=leaveLabel(),l=automationView?.run?.leave;
  return label&&l?.busy?label+busySuffix(wd,l.paused):label;
}
/// A new run snapshot redraws the leave label (the QSO pane's watchdog line and the station bar).
function leaveShow(){
  const wd=snap?.watchdog;
  if(wd&&!wd.tx_expired&&snap.transmit?.arm_state==='armed')$('contact-watchdog').textContent=watchdogText(wd);
  stationTx();
}
function stationTx(){
  const t=snap?.transmit,capable=transmitCapable(),wd=snap?.watchdog,armed=t?.arm_state==='armed';
  stationTxNode.hidden=!capable||!(armed||tick?.transmitting||wd?.tx_expired);if(stationTxNode.hidden)return;
  const count=armed?watchdogText(wd):'';
  stationTxNode.textContent=`${tick?.transmitting?'TRANSMITTING':armed?'Tx on':'Tx off'}${count?` · ${count}`:!armed&&wd.tx_expired?` · Tx watchdog: same message sent ${snap.settings.tx_calls} times`:''}${t.last_text?` · last ${t.last_text}`:''}`;
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
  const from=aborts;await sendChain;await settled();const c=snap?.contact;
  if(c?.dx_call&&transmitting(c)){
    if(!await confirmAction(`Abandon the QSO with ${c.dx_call} and call CQ?`,'Call CQ'))return;
    const reply=await send('cancel',{},'Cancel contact');if(!reply||reply.refused)return;
  }
  // #61 CL-061-02: an explicit choice, retried after stale_revision like the double-click.
  sendExplicit(()=>arm('CQ'),from);
});
$('qso-halt').addEventListener('click',()=>halt.click());$('qso-halt').disabled=halt.disabled;
$('qso-abort').addEventListener('click',abortQso);
// #37 one HALT: the top-bar HALT hides only while the QSO pane HALT is fully on screen.
new IntersectionObserver(([entry])=>{document.body.dataset.qsoHaltShown=String(entry.isIntersecting&&entry.intersectionRatio>=0.99);},{threshold:[0,0.99,1]}).observe($('qso-halt'));
// #37 fold-out Now (operator 2026-11-03, WSJT-X Next/Now): choose the line next and turn Enable
// Tx on, so it goes from the next own period (never into a waveform already on the air).
async function nowMessage(slot){
  const c=snap?.contact;if(['completed','cancelled'].includes(c?.state)||!transmitReady())return;
  const from=aborts,label=`Now ${slot.toUpperCase()}`,r=await send('choose_next',{slot},label);if(!r||r.refused||from!==aborts)return;
  if(snap?.transmit.arm_state!=='armed')arm(label);
}
focus.querySelector('#contact-messages').addEventListener('click',event=>{const now=event.target.closest('.ct-now');if(now&&!now.disabled)nowMessage(now.dataset.slot);});
focus.querySelector('#contact-messages').addEventListener('change',event=>{
  const radio=event.target.closest('input[type=radio]');if(radio){send('choose_next',{slot:radio.value},`Next ${radio.value.toUpperCase()}`);return;}
  const text=event.target.closest('.ct-text');if(text)send('edit_message',{slot:text.dataset.slot,text:text.value},`Edit ${text.dataset.slot.toUpperCase()}`);
});
$('contact-tx1-skip').addEventListener('change',event=>send('set_tx1_skip',{enabled:event.target.checked},'Skip Tx1'));
$('contact-rr73').addEventListener('change',event=>send('set_tx4',{form:event.target.checked?'rr73':'rrr'},'RRR/RR73'));
$('contact-report').addEventListener('change',event=>{const n=Number(event.target.value);if(Number.isInteger(n))send('set_report',{report:n},'Report');else resultText.textContent='Report must be a whole number of dB';});
$('contact-parity').addEventListener('change',event=>send('set_parity',{parity:event.target.value},'Tx period'));
let shownExchange;
// A refused choice (e.g. EU VHF without a 6-character locator, #99) returns to the station's setting.
const sendActivity=()=>{const activity=$('contact-activity').value,contest=activity==='field_day'||activity==='rtty';send('set_activity',contest?{activity,exchange:$('contact-exchange').value}:{activity},'Activity').then(r=>{if(r?.refused)$('contact-activity').value=snap?.settings?.activity??'none';});};
$('contact-activity').addEventListener('change',sendActivity);
$('contact-exchange').addEventListener('change',()=>{if(['field_day','rtty'].includes($('contact-activity').value))sendActivity();});
$('contact-auto').addEventListener('change',event=>send('set_auto_seq',{enabled:event.target.checked},'Auto sequence'));
$('contact-call-first').addEventListener('change',event=>send('set_call_first',{enabled:event.target.checked},'Call 1st'));
$('contact-tune').addEventListener('click',()=>send('tune',{enabled:!snap?.transmit.tune},'Tune'));
$('contact-cancel').addEventListener('click',()=>send('cancel',{},'Cancel contact'));
for(const id of ['watchdog-tx','watchdog-tune'])$(id).addEventListener('change',async()=>{
  const tx=Number($('watchdog-tx').value),tune=Number($('watchdog-tune').value);
  if(!Number.isInteger(tx)||!Number.isInteger(tune)){$('watchdog-result').textContent='Watchdogs must be whole numbers';return;}
  await send('set_watchdogs',{tx_calls:tx,tune_seconds:tune},'Watchdogs');$('watchdog-result').textContent=resultText.textContent;
});
// #40 WstxUdp settings (CL-040-02): read when the drawer opens (at most every 30 s), on the
// Logging tab or Reload; Save sends one PUT /udp. A setting: it restarts nothing.
const UDP_MESSAGES=[['heartbeat','Heartbeat'],['status','Status'],['decode','Decode'],['clear','Clear'],['qso_logged','QSO Logged'],['close','Close'],['logged_adif','Logged ADIF']];
const UDP_DEFAULT={instance_name:'WSTX-Rust',targets:[{address:'127.0.0.1:2237',enabled:true,multicast_ttl:1,multicast_interface:null,messages:UDP_MESSAGES.map(m=>m[0])}]};
let udpView=null,udpDirty=false,udpRead=-Infinity,udpLoading=null;
// An IPv6 group [ffXY::...]: Y is its scope (WstxUdp D6); scope 1 and 2 need an interface index.
const udpIpv6Group=address=>{const m=/^\[\s*ff[0-9a-f]([0-9a-f])(:|\])/i.exec(address.trim());return m?{scope:parseInt(m[1],16)}:null;};
const utcTime=ms=>new Date(ms).toISOString().slice(11,19)+' UTC';
function udpStatusText(s){
  if(!s)return 'Not saved yet';
  const parts=[s.active?'Active':'Inactive'];if(s.schema)parts.push(`schema ${s.schema}`);
  parts.push(s.last_send_utc_ms?`last send ${utcTime(s.last_send_utc_ms)}`:'nothing sent yet');if(s.error)parts.push(`error ${s.error}`);
  return parts.join(' · ');
}
function udpRow(t,status){
  const row=document.createElement('fieldset');row.className='udp-target';row.setAttribute('role','listitem');
  row.innerHTML=`<legend>Target</legend><label>Address:port<input data-f="address" autocomplete="off" spellcheck="false"></label><label class="op-check"><input type="checkbox" data-f="enabled">Enabled</label><label>Multicast TTL / hop limit<input type="number" data-f="ttl" min="1" max="255" step="1"></label><label>Multicast interface<input data-f="iface" placeholder="default" autocomplete="off" spellcheck="false"></label><span class="op-muted" data-f="iface-note"></span><fieldset class="udp-messages"><legend>Messages sent</legend>${UDP_MESSAGES.map(([k,l])=>`<label class="op-check"><input type="checkbox" data-m="${k}">${l}</label>`).join('')}</fieldset><button type="button" data-f="remove">Remove target</button><p class="op-muted" data-f="status" role="status"></p>`;
  const f=k=>row.querySelector(`[data-f=${k}]`);
  f('address').value=t.address;f('enabled').checked=t.enabled;f('ttl').value=t.multicast_ttl;f('iface').value=t.multicast_interface??'';
  for(const box of row.querySelectorAll('[data-m]'))box.checked=t.messages.includes(box.dataset.m);
  f('status').textContent=udpStatusText(status);
  const multicast=()=>{const v6=udpIpv6Group(f('address').value);
    f('iface').placeholder=v6?'interface index':'default';
    f('iface-note').textContent=v6?`IPv6 group: TTL is the hop limit; the interface is its index (netsh interface ipv6 show interfaces)${v6.scope===1||v6.scope===2?'; this interface- or link-local group needs one':''}.`:'';};
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
  $('udp-result').textContent=v.configuration_error?`Saved UDP settings unreadable (${v.configuration_error}); Save replaces them`:`Revision ${v.revision}`;
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
      messages:[...row.querySelectorAll('[data-m]')].filter(b=>b.checked).map(b=>b.dataset.m)};})};
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
new MutationObserver(()=>{if(!document.querySelector('#settings-drawer').hidden){loadUdp();loadDiagnostics();}}).observe(document.querySelector('#settings-drawer'),{attributes:true,attributeFilter:['hidden']});
document.querySelector('#tab-logging')?.addEventListener('click',()=>loadUdp(true));
// #58 MCP clients (Settings > General > Access & grants): an MCP client uses a token of
// its own, never this browser's credential; the token is shown once, the station keeps
// only its hash. Loaded when the drawer opens, never on the operating path.
$('settings-browsers').insertAdjacentHTML('beforeend','<h4 id="mcp-clients-title">MCP clients</h4><p class="op-muted">An MCP client (an AI agent or script) uses its own token, never this browser\'s authorization. Its requests never count as your action for the Tx watchdog.</p><ul id="mcp-clients" aria-labelledby="mcp-clients-title"></ul><label>Client name<input id="mcp-name" maxlength="32" autocomplete="off" placeholder="e.g. Claude Code"></label><button type="button" id="mcp-create">Create token</button><div id="mcp-token" hidden><p class="op-warning">Copy this token now: it is shown only once. Configure it in the MCP client as Authorization: Bearer &lt;token&gt;.</p><code id="mcp-token-value"></code> <button type="button" id="mcp-token-copy">Copy</button> <button type="button" id="mcp-token-done">Done</button></div><p id="mcp-result" class="op-muted" role="status"></p><details id="mcp-recent-box"><summary>Recent MCP use</summary><ol id="mcp-recent"></ol></details>');
// The page CSP admits no style attribute; CSSOM wraps the 52-character token at 360 px.
Object.assign($('mcp-token-value').style,{display:'block',wordBreak:'break-all',userSelect:'all'});
let mcpLoading=null;
const mcpTime=ms=>ms==null?'never':new Date(ms).toISOString().slice(0,16).replace('T',' ')+' UTC';
const mcpPost=(path,body)=>stationFetch('/authorization/v1/mcp-clients'+path,{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({version:1,...body}),signal:AbortSignal.timeout(10000)});
const mcpRead=()=>stationFetch('/authorization/v1/mcp-clients',{cache:'no-store',signal:AbortSignal.timeout(10000)});
function mcpShow(v){
  const list=$('mcp-clients');list.replaceChildren();
  for(const c of v.clients){
    const item=document.createElement('li'),text=document.createElement('span'),revoke=document.createElement('button');
    text.textContent=`${c.name} · created ${mcpTime(c.created_utc_ms)} · last used ${mcpTime(c.last_used_utc_ms)} `;
    revoke.type='button';revoke.textContent='Revoke';revoke.setAttribute('aria-label',`Revoke MCP client ${c.name}`);
    revoke.addEventListener('click',async()=>{
      if(!await window.wstxConfirm(`Revoke MCP client "${c.name}"? Its token stops working at once.`,'Revoke'))return;
      revoke.disabled=true;mcpAnswer(await mcpPost('/revoke',{client_id:c.client_id}).catch(()=>null),'Revoked');
    });
    item.append(text,revoke);list.append(item);
  }
  if(!v.clients.length)list.innerHTML='<li class="op-muted">No MCP clients</li>';
  $('mcp-create').disabled=v.clients.length>=v.max_clients;
  $('mcp-recent').replaceChildren(...v.recent.map(e=>{const li=document.createElement('li');li.textContent=`${mcpTime(e.utc_ms)} · ${e.name} · ${e.action} · ${e.status}`;return li;}));
}
async function mcpAnswer(response,done){
  const data=await response?.json().catch(()=>null);
  if(!response?.ok||data?.version!==1){$('mcp-result').textContent=`MCP clients unavailable (${data?.error?.code??response?.status??'no answer'})`;return;}
  mcpShow(data);$('mcp-result').textContent=done;
}
function loadMcp(){
  if(!mcpLoading)mcpLoading=mcpRead().then(r=>mcpAnswer(r,'')).catch(()=>{$('mcp-result').textContent='MCP clients unavailable';}).finally(()=>{mcpLoading=null;});
  return mcpLoading;
}
$('mcp-create').addEventListener('click',async()=>{
  const name=$('mcp-name').value.trim();if(!name){$('mcp-result').textContent='Name the MCP client first';$('mcp-name').focus();return;}
  $('mcp-create').disabled=true;
  try{
    const response=await mcpPost('/create',{name}),data=await response.json().catch(()=>null);
    if(!response.ok||!data?.token){$('mcp-result').textContent=`Not created · ${data?.error?.code??response.status}`;return;}
    $('mcp-name').value='';$('mcp-token-value').textContent=data.token;$('mcp-token').hidden=false;$('mcp-result').textContent=`Created ${data.name}`;
  }catch(error){$('mcp-result').textContent=`Not created · ${error.message}`;}
  finally{$('mcp-create').disabled=false;loadMcp();}
});
$('mcp-token-copy').addEventListener('click',()=>navigator.clipboard?.writeText($('mcp-token-value').textContent).then(()=>{$('mcp-result').textContent='Token copied';},()=>{$('mcp-result').textContent='Copy failed: select the token and copy it';}));
$('mcp-token-done').addEventListener('click',()=>{$('mcp-token-value').textContent='';$('mcp-token').hidden=true;});
new MutationObserver(()=>{if(!document.querySelector('#settings-drawer').hidden)loadMcp();else $('mcp-token-done').click();}).observe(document.querySelector('#settings-drawer'),{attributes:true,attributeFilter:['hidden']});
// #43 CL-043-01: the clock source, saved at once. The clock view is read on demand when the
// drawer opens (at most every 10 s) or on the General tab, never polled on the thin link.
$('settings-clock').insertAdjacentHTML('beforeend','<label>Clock source<select id="clock-source" disabled><option value="ntp">NTP (default)</option><option value="air">From the air</option><option value="both">Both: NTP, air as fallback</option></select></label><p id="clock-air" class="op-muted" role="status">Clock from the air unknown</p><p id="clock-result" class="op-muted" role="status"></p>');
let clockView=null,clockRead=-Infinity,clockLoading=null;
const signedMs=ms=>`${ms>=0?'+':''}${ms} ms`;
function clockShow(){
  const v=clockView,select=$('clock-source');select.disabled=!v;if(!v)return;select.value=v.source;const e=v.air.estimate;
  $('clock-air').textContent=`Clock ${v.state} by ${v.basis==='air'?'the air':'NTP'}${v.correction_ms?`, correction ${signedMs(v.correction_ms)}`:''} \u00b7 from the air: ${e?`${signedMs(e.offset_ms)}, ${e.stations} of ${e.heard} stations (${e.confidence_pct} %), ${Math.round(e.age_ms/1000)} s ago, ${v.air.state}`:'too few stations heard'}${v.warning?` \u00b7 NTP and air disagree by ${v.disagreement_ms} ms`:''}${v.storage_error?` \u00b7 ${v.storage_error}`:''}`;
}
function loadClock(force=false){
  if(clockLoading||(!force&&performance.now()-clockRead<10000))return clockLoading;
  clockRead=performance.now();
  clockLoading=stationFetch('/clock',{cache:'no-store',signal:AbortSignal.timeout(10000)}).then(r=>r.ok?r.json():null).then(v=>{if(v?.v===1){clockView=v;clockShow();}}).catch(()=>{}).finally(()=>{clockLoading=null;});
  return clockLoading;
}
$('clock-source').addEventListener('change',async event=>{
  const select=event.target,v=clockView;if(!v)return;select.disabled=true;$('clock-result').textContent='Saving';
  try{
    const response=await stationFetch('/clock',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:v.profile_id,boot_id:v.boot_id,source:select.value}),signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);
    if(!response.ok||data?.v!==1)throw new Error(data?.error?.code??String(response.status));
    clockView=data;$('clock-result').textContent='Saved';
  }catch(error){$('clock-result').textContent=`Not saved \u00b7 ${error.message}`;}
  clockShow();
});
new MutationObserver(()=>{if(!document.querySelector('#settings-drawer').hidden)loadClock();}).observe(document.querySelector('#settings-drawer'),{attributes:true,attributeFilter:['hidden']});
document.querySelector('#tab-general')?.addEventListener('click',()=>loadClock(true));
let startupView=null,startupLoading=null;
const resumeText={idle:'Nothing to resume at start',off:'Monitor off at startup',waiting:'Resuming receive',started:'Resumed at start',started_untuned:'Resumed at start on the present dial',skipped:'Resume skipped: receive was already chosen',failed:'Resume failed'};
function startupShow(){
  const v=startupView,box=$('monitor-off-startup');box.disabled=!v;if(!v)return;box.checked=v.monitor_off_at_startup;
  const last=v.last_receive,choice=last?` · last ${[last.band,last.mode.toUpperCase()].filter(Boolean).join(' ')}`:'';
  $('startup-resume').textContent=`${resumeText[v.resume.state]??v.resume.state}${v.resume.error?` · ${v.resume.error}`:''}${choice}${v.storage_error?` · ${v.storage_error}`:''}`;
}
// #39 WstxStrategy::HearingFeed: one snapshot per connection, then pskr.state events; the
// age counts on with the station tick. Nothing is polled and no state here is an error chip.
let pskrView=null,pskrUtcMs=null;
function pskrShow(){
  const v=pskrView,box=$('pskr-enabled');box.disabled=!v;pskrToggleShow();pskrLinesShow();if(!v)return;box.checked=v.enabled;
  const age=v.last_spot_utc_s===null||pskrUtcMs===null?null:Math.floor((pskrUtcMs/1000-v.last_spot_utc_s)/60);
  const spot=v.last_spot_utc_s===null?'no spot yet':age===null||age<1?'last spot under 1 min ago':`last spot ${age} min ago`;
  const text={off:'Off',connecting:v.error?`Connecting · last try ${v.error}`:'Connecting',connected:`Connected · ${spot}`,error:`Not connected · ${v.error} · retrying`}[v.state]??v.state;
  $('pskr-status').textContent=`${text}${v.storage_error?` · ${v.storage_error}`:''}`;$('pskr-status').dataset.state=v.state;
}
// #39 WstxStrategy::PskrUse: the PSK toggle beside Auto shows only the station's pushed use; the
// Settings switch is the master (off: disabled, counts as off). A click sends one POST /pskr/use.
const pskrUse=()=>!!pskrView?.enabled&&pskrView.use===true;
let pskrPosting=false;
function pskrToggleShow(){
  const button=$('qso-pskr'),on=pskrUse();button.setAttribute('aria-pressed',String(on));button.dataset.on=String(on);
  button.disabled=!pskrView||!pskrView.enabled||pskrPosting;
  button.title=!pskrView?'Use PSK Reporter · status unknown':!pskrView.enabled?'PSK Reporter is off in Settings':'Use PSK Reporter';
}
// The freshly loaded form is the same as after a new boot (#74): drawn by the one rule above.
pskrToggleShow();
$('qso-pskr').addEventListener('click',async()=>{
  const v=pskrView;if(!v?.enabled||pskrPosting)return;pskrPosting=true;pskrToggleShow();
  try{
    const response=await stationFetch('/pskr/use',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:v.profile_id,boot_id:v.boot_id,use:!(v.use===true)}),signal:AbortSignal.timeout(10000)});
    // The toggle follows pskr.state; a refusal says why.
    if(!response.ok){const data=await response.json().catch(()=>null);resultText.textContent=`PSK Reporter use not saved · ${data?.error?.code??response.status}`;}
  }catch(error){resultText.textContent=`PSK Reporter use not saved · ${error.message}`;}
  finally{pskrPosting=false;pskrToggleShow();}
});
// The two PSK Reporter lines (QsoPane, PskrUse): while Use is on and a strategy or contest run's
// own contact has a target; from the run snapshot of GET /automation (read on automation.state)
// and the age from station.tick. Hidden otherwise.
const pskrAge=s=>s<120?`${s} s`:`${Math.floor(s/60)} min`;
function pskrLinesShow(){
  const a=automationView,run=a?.run,lines=$('qso-pskr-lines');
  const target=pskrUse()&&!!a?.configuration?.strategy&&!!run&&!run.pounce&&run.state==='contact_active'&&!!run.selected?.call;
  lines.hidden=!target;if(!target)return;
  const h=run.hearing,now=pskrUtcMs??stationNow();
  const age=h?.state==='heard'&&Number.isFinite(h.spot_utc_s)&&now!==null?Math.max(0,Math.floor(now/1000-h.spot_utc_s)):null;
  $('qso-hears').textContent=h?.state==='heard'?`Hears us: ${age===null?'?':pskrAge(age)} ago · ${typeof h.snr_db==='number'?signedDb(h.snr_db):'?'} dB`:h?.state==='no'?'Hears us: no':'Hears us: unknown';
  const slot=run.tx_slot,tx=$('qso-txslot');tx.hidden=!Number.isInteger(slot?.hz);
  tx.textContent=tx.hidden?'':`Tx ${slot.hz} Hz · open at his end: ${['yes','no'].includes(slot.his_end)?slot.his_end:'unknown'}`;
}
const currentBoot=v=>v?.boot_id===profileData?.boot_id;
function loadPskr(){stationFetch('/pskr',{cache:'no-store',signal:AbortSignal.timeout(10000)}).then(r=>r.ok?r.json():null).then(v=>{if(v?.v===1&&currentBoot(v)){pskrView=v;pskrShow();}}).catch(()=>{});}
$('pskr-enabled').addEventListener('change',async event=>{
  const box=event.target,v=pskrView;if(!v)return;box.disabled=true;$('pskr-result').textContent='Saving';
  try{
    const response=await stationFetch('/pskr',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:v.profile_id,boot_id:v.boot_id,enabled:box.checked}),signal:AbortSignal.timeout(10000)});
    const data=await response.json();if(!response.ok)throw new Error(data?.error?.code||'connection error');
    if(currentBoot(data)){pskrView=data;$('pskr-result').textContent='Saved';}
  }catch(error){$('pskr-result').textContent=`Not saved · ${error.message}`;}
  pskrShow();
});
addEventListener('station-message',event=>{const m=event.detail?.message;
  if(m?.type==='station.tick'&&Number.isSafeInteger(m.data?.utc_ms)){pskrUtcMs=m.data.utc_ms;if(pskrView?.state==='connected')pskrShow();else pskrLinesShow();}
  else if(m?.type==='pskr.state'&&m.data?.v===1&&m.data.boot_id===profileData?.boot_id){pskrView=m.data;pskrShow();}});
function loadStartup(){
  if(startupLoading)return startupLoading;
  const loading=startupLoading=stationFetch('/receive/startup',{cache:'no-store',signal:AbortSignal.timeout(10000)}).then(r=>r.ok?r.json():null).then(v=>{if(loading===startupLoading&&v?.v===1&&currentBoot(v)){startupView=v;startupShow();}}).catch(()=>{}).finally(()=>{if(loading===startupLoading)startupLoading=null;});
  return loading;
}
// WstxStationProtocol::PushedStationState (#74): a new boot drops the automation, Free Tx slots,
// PSK Reporter and Monitor off at startup state of the previous boot at once; each view shows
// the form of a freshly loaded page until its own read or event of the new boot.
let bootReads=false;
addEventListener('station-boot',()=>{
  automationLoading=null;automationView=null;freeTxSlots=null;freeTxSlotMarks();
  pskrView=null;startupView=null;startupLoading=null;bootReads=true;
  const status=$('pskr-status');status.textContent='PSK Reporter status unknown';delete status.dataset.state;
  $('pskr-enabled').checked=false;$('pskr-result').textContent='';pskrShow();
  $('monitor-off-startup').checked=false;$('startup-result').textContent='';$('startup-resume').textContent='Startup resume unknown';startupShow();
});
$('monitor-off-startup').addEventListener('change',async event=>{
  const box=event.target,v=startupView;if(!v)return;box.disabled=true;$('startup-result').textContent='Saving';
  try{
    const response=await stationFetch('/receive/startup',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:v.profile_id,boot_id:v.boot_id,monitor_off_at_startup:box.checked}),signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);
    if(!response.ok||data?.v!==1)throw new Error(data?.error?.code||'request_failed');
    if(currentBoot(data)){startupView=data;$('startup-result').textContent='Saved';}
  }catch(error){$('startup-result').textContent=`Not saved · ${error.message}`;}
  startupShow();
});
let diagnosticsView=null,diagnosticsRead=-Infinity;
function diagnosticsShow(){
  const v=diagnosticsView,box=$('window-dump');box.disabled=!v;if(!v)return;box.checked=v.window_dump;
  const w=v.windows.at(-1),fill=w?.zero_filled_frames??'unknown',glitch=w?.glitch_frames??'unknown';
  $('window-diagnostics').textContent=w?`Last window ${w.period_start_utc??w.origin}: ${w.zero_samples} zero samples (longest run ${w.longest_zero_run}, early buffer ${w.early_buffer_zero_samples??'unknown'}), zero-filled ${fill}, glitch ${glitch}${v.window_dump?` · ${v.dumped_windows} saved`:''}${v.dump_error?` · ${v.dump_error}`:''}${v.storage_error?` · ${v.storage_error}`:''}`:`No window analysed yet${v.storage_error?` · ${v.storage_error}`:''}`;
}
function loadDiagnostics(force=false){
  if(!force&&performance.now()-diagnosticsRead<30000)return;
  diagnosticsRead=performance.now();
  return stationFetch('/receive/diagnostics',{cache:'no-store',signal:AbortSignal.timeout(10000)}).then(r=>r.ok?r.json():null).then(v=>{if(v?.v===1){diagnosticsView=v;diagnosticsShow();}}).catch(()=>{});
}
$('window-diagnostics-refresh').addEventListener('click',()=>loadDiagnostics(true));
$('window-dump').addEventListener('change',async event=>{
  const box=event.target,v=diagnosticsView;if(!v)return;box.disabled=true;$('window-diagnostics').textContent='Saving';
  try{
    const response=await stationFetch('/receive/diagnostics',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:v.profile_id,boot_id:v.boot_id,window_dump:box.checked}),signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);
    if(!response.ok||data?.v!==1)throw new Error(data?.error?.code||'request_failed');
    diagnosticsView=data;
  }catch(error){diagnosticsShow();$('window-diagnostics').textContent=`Not saved · ${error.message}`;return;}
  diagnosticsShow();
});
// Log QSO: log the current contact now, without a form (DirectLog).
async function logQso(){await sendChain;await settled();if(running(snap?.contact))await send('open_log',{},'Log QSO');}
$('contact-log').addEventListener('click',logQso);
// WstxOperatingLayout::KeyboardShortcuts (WSJT-X keys where the function exists). Esc is Abort QSO;
// Alt+H (the emergency halt) is sent by recording.js.
const typing=target=>!!target?.closest?.('input:not([type=checkbox]):not([type=radio]):not([type=range]),textarea,select,[contenteditable=true]');
function nudge(rx,tx,label){const s=snap?.settings;if(!s)return;send('set_frequency',{rx_hz:rx===null?null:Math.max(0,Math.min(3000,s.rx_hz+rx)),tx_hz:tx===null?null:s.tx_hz+tx},label);}
addEventListener('keydown',event=>{
  // Esc first closes an open dialog or menu; only otherwise it aborts the QSO. #96 (CL-096-01): never while
  // the page is full screen, and never by a repeated keydown (the key held: Chrome leaves full screen while
  // Esc is still down and the auto-repeat then reaches the page).
  if(event.key==='Escape'){if(event.defaultPrevented||event.repeat||document.fullscreenElement||document.querySelector('dialog[open],#ba-menu:not([hidden])'))return;event.preventDefault();abortQso();return;}
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
  const row=rowIdentity(tr);if(!row)return null;await sendChain;await settled();
  // #37: during a contact only a row that can start a contact for me offers the change; a foreign
  // QSO's row or a CQ directed elsewhere (the station's refusal, DirectedCqRule) offers nothing.
  const qso=running(snap?.contact);
  const reply=qso?await send('select_row',{row,replace:false},'Select station'):await selectConfirmed(row,false,'Select station');
  if(qso&&(reply?.refused==='directive_not_answerable'||(reply?.refused==='contact_active'&&tr.dataset.foreign))){changeTarget?.remove();changeTarget=null;resultText.textContent='';}
  else if(reply?.refused==='contact_active')offerChange(()=>send('select_row',{row,replace:true,directive_confirmed:true},'Change contact'),tr.dataset.sender);
  return reply;
}
// WstxStrategy::DirectedCqRule: the station decides; a CQ that is not answerable is a warning
// the operator may confirm (a declined warning sends nothing further).
async function selectConfirmed(row,replace,label,from=aborts){
  const reply=await sendExplicit(()=>send('select_row',{row,replace},label),from);
  if(reply?.refused!=='directive_not_answerable')return reply;
  if(!await window.wstxConfirm(`${reply.reason}. Answer anyway?`,'Answer anyway'))return {refused:'declined'};
  return sendExplicit(()=>send('select_row',{row,replace,directive_confirmed:true},label),from);
}
// A double-click (or the Reply menu) is the explicit ChangeContact (#50, WSJT-X
// handleDecodeSelection with quick_call): replace true, no confirmation, then Enable Tx on;
// the replacement itself keeps Enable Tx as it is.
// The contact revision moves with every transmit step: a stale_revision refusal of this
// explicit choice is retried, at most twice, with the reloaded snapshot (send reloads it).
async function sendExplicit(run,from=aborts){
  let reply=from===aborts?await run():null;
  for(let i=0;i<2&&reply?.refused==='stale_revision'&&from===aborts;i++){
    // A stale contact revision waits up to 2.5 s for a newer one in contact.state; another field was read at once.
    if((reply.field??'contact_revision')==='contact_revision'&&!await held(reply.boot,reply.sent+1,2500))await load();
    reply=from===aborts?await run():{refused:'aborted'};
  }
  return reply;
}
async function replyRow(tr){
  const row=rowIdentity(tr);if(!row)return;
  // #37: a deliberate double-click on a foreign QSO's row calls its sender, and says so.
  const label=tr.dataset.foreign?`Call ${tr.dataset.sender}`:'Reply';
  const from=aborts,reply=await selectConfirmed(row,true,label,from);
  if(reply&&!reply.refused&&from===aborts&&transmitReady())await sendExplicit(()=>arm(label),from);
}
let clickTimer=null;
// The double-click is the row's second press (click count 2), not the dblclick event: the
// rows are redrawn with every result page, and the browser drops a click, and its dblclick,
// whose pressed row was redrawn before the release (#50, 2026-11-03: G8KHF only selected).
// A click of a double-click never starts the single-click selection.
const secondPress=(event,selector)=>event.button===0&&event.detail===2?event.target.closest(selector):null;
activity?.addEventListener('click',event=>{const tr=event.target.closest('tr[data-sequence]');if(!tr||event.detail>1)return;clearTimeout(clickTimer);clickTimer=setTimeout(()=>selectRow(tr),250);});
activity?.addEventListener('mousedown',event=>{const tr=secondPress(event,'tr[data-sequence]');if(!tr)return;clearTimeout(clickTimer);replyRow(tr);});
activity?.addEventListener('keydown',event=>{const tr=event.target.closest('tr[data-sequence]');if(!tr)return;if(event.key==='Enter'){event.preventDefault();selectRow(tr);}else if(event.key==='ContextMenu'||(event.shiftKey&&event.key==='F10')){event.preventDefault();openMenu(tr,tr.getBoundingClientRect().left+20,tr.getBoundingClientRect().bottom);}});
const menu=document.createElement('div');menu.id='ba-menu';menu.className='op-menu';menu.setAttribute('role','menu');menu.hidden=true;
menu.innerHTML='<button type="button" role="menuitem" data-menu="reply">Reply</button><button type="button" role="menuitem" data-menu="select">Select</button><button type="button" role="menuitem" data-menu="rx">Set Rx here</button>';
document.querySelector('main').append(menu);let menuRow=null;
// The row's own items (#42 Pounce, Ignore) are set first, so the menu is placed at its real size.
function openMenu(tr,x,y){menuRow=tr;menu.hidden=false;menu.querySelector('[data-menu=reply]').disabled=!transmitReady();dispatchEvent(new CustomEvent('wstx-row-menu',{detail:tr}));menu.style.left=`${Math.max(0,Math.min(x,innerWidth-menu.offsetWidth-8))}px`;menu.style.top=`${Math.max(0,Math.min(y,innerHeight-menu.offsetHeight-8))}px`;menu.querySelector('button:not(:disabled):not([hidden])').focus();}
function closeMenu(){menu.hidden=true;menuRow=null;}
activity?.addEventListener('contextmenu',event=>{const tr=event.target.closest('tr[data-sequence]');if(!tr)return;event.preventDefault();openMenu(tr,event.clientX,event.clientY);});
menu.addEventListener('click',event=>{
  const item=event.target.closest('[data-menu]');if(!item||!menuRow)return;const tr=menuRow;closeMenu();
  if(item.dataset.menu==='reply')replyRow(tr);else if(item.dataset.menu==='select')selectRow(tr);
  else if(item.dataset.menu==='rx'){const hz=Math.round(Number(tr.children[3].textContent));if(Number.isFinite(hz))send('set_frequency',{rx_hz:hz,tx_hz:null},'Rx frequency');}
});
menu.addEventListener('keydown',event=>{if(event.key==='Escape'){event.preventDefault();closeMenu();}});
document.addEventListener('pointerdown',event=>{if(!menu.hidden&&!menu.contains(event.target))closeMenu();},true);
// WstxOperatingLayout::QsoPane Calling me (#37, operator 2026-11-04): every station calling my
// call from the latest two published periods except the partner, one line per station (its
// newest decode): call, SNR, grid and country. While a QSO runs a double-click switches the
// contact to that station and replies (⚠ marks one within ±50 Hz of my Rx or Tx offset,
// QsoPaneCrowding); otherwise a double-click answers.
const myCall=()=>(profileData?.settings?.callsign??'').trim().toUpperCase();
const othersList=$('qso-others');
function recentRows(){
  if(typeof resultRows==='undefined'||!live?.job)return [];
  const context=liveIdentity(live),len=live.job.mode==='ft4'?7500:15000,latest=Date.parse(resultView?.period_start_utc??'');
  const rows=resultRows.map(record=>({record,context}));
  const previous=activityHistory[0];
  if(previous&&previous.context===context&&Number.isFinite(latest)&&latest-Date.parse(previous.period??'')<=len)rows.push(...previous.rows.map(record=>({record,context})));
  return rows;
}
const OTHER_LINES=8;
// The caller as decoded: the word of the two calls that is not mine (a hashed call as "<...>").
function callerText(record){
  const my=myCall(),w=(record.text??'').trim().split(/\s+/),mine=x=>x===my||x===`<${my}>`;
  return w.length>=2&&mine(w[0])&&isCall(w[1])?w[1]:w.length>=2&&mine(w[1])&&isCall(w[0])?w[0]:recordFrom(record.fields)??'';
}
// The compact caller tip: the #50 BandActivityHover rule of Band Activity; the line shows the country.
function callerTip(record,w){
  const worked=w?.status==='worked_this_band_and_mode'?`on ${w.on}`:w?.status==='worked_other_band_or_mode'?'on another band or mode':'';
  return hoverReasons(activityHover(record),worked).join(' · ');
}
function othersShow(){
  const rx=snap?.settings?.rx_hz,tx=snap?.settings?.tx_hz,c=snap?.contact,qso=running(c),dx=qso?c.dx_call:lastPartner,my=myCall();
  const near=f=>[rx,tx].some(o=>typeof o==='number'&&f>=o-50&&f<=o+50);
  const newest=(snap&&my?recentRows():[]).filter(({record})=>{
    if(record.status!=='decoded')return false;
    // #24: addressed to me as in Band Activity (recordTo: also <MYCALL> and nonstandard i3=4).
    const from=recordFrom(record.fields),to=recordTo(record.fields);
    return to===my&&!(dx&&from===dx);
  }).sort((a,b)=>(b.record.period_start_utc??'').localeCompare(a.record.period_start_utc??'')||b.record.sequence-a.record.sequence);
  // One line per station, its newest decode (an unresolved hashed call is its own line); oldest
  // first, the newest at the bottom.
  const seen=new Set(),lines=newest.filter(({record,context})=>{const from=recordFrom(record.fields),k=from?from.toUpperCase():`${context}/${record.sequence}`;if(seen.has(k))return false;seen.add(k);return true;}).slice(0,OTHER_LINES).reverse();
  $('qso-others-none').hidden=!!lines.length;$('calling-table').hidden=!lines.length;
  // CL-010-13 (WstxOperatingLayout::QsoPane item 3): each caller carries the Band Activity
  // marks of its sender: the enabled new_* slot colours of its #55 flags (My call is not used,
  // every line calls me), the reasons and the worked-before status as text; worked before on
  // this band and mode adds no colour.
  const workedOf=record=>{const from=recordFrom(record.fields);return from?window.wstxWorkedOf?.(from.toUpperCase())??null:null;};
  const key=JSON.stringify([qso,document.querySelector('#band-activity')?.dataset.hlOn??'',lines.map(l=>`${l.context}/${l.record.sequence}/${near(l.record.frequency_hz)}/${workedOf(l.record)?.status??''}`)]);
  if(othersList.dataset.key===key)return;othersList.dataset.key=key;
  othersList.replaceChildren(...lines.map(({record,context})=>{
    const warn=qso&&near(record.frequency_hz),grid=record.fields?.exchange?.kind==='grid'?record.fields.exchange.value??'':'';
    const tr=document.createElement('tr');
    for(const cell of [`${callerText(record)}${warn?' ⚠':''}`,signedDb(record.snr_db),grid,record.dxcc?.name??'']){const td=document.createElement('td');td.textContent=cell;tr.append(td);}
    tr.tabIndex=0;tr.dataset.kind=warn?'warn':'candidate';tr.dataset.qso=String(qso);
    tr.dataset.row=JSON.stringify(rowOf(context,record.sequence));tr.dataset.text=record.text;tr.dataset.call=callerText(record);
    const hl=bandFlags.filter(k=>record.flags?.[k]===true),w=workedOf(record);if(hl.length)tr.dataset.hl=hl.join(' ');
    if(w)tr.dataset.worked=w.status;
    // #50 BandActivityHover rule (operator 2026-11-04, "too much information"): only the colour
    // reasons the line does not show, the strongest enabled one per kind, on one line.
    const tip=callerTip(record,w);
    if(tip){tr.title=tip;tr.setAttribute('aria-description',tip);}
    return tr;
  }));
  const area=$('calling-area');area.scrollTop=area.scrollHeight;
}
function rowOf(context,sequence){const [,,source_id,job_id,generation]=context.split('/');return {source_id,job_id,generation:Number(generation),sequence};}
async function answerOther(li){
  const row=JSON.parse(li.dataset.row),qso=li.dataset.qso==='true',from=aborts;
  const reply=await selectConfirmed(row,qso,qso?'Change contact':'Select station',from);
  if(from!==aborts)return;
  if(reply?.refused==='contact_active'){offerChange(()=>{const confirmed=aborts;return send('select_row',{row,replace:true,directive_confirmed:true},'Change contact').then(r=>{if(r&&!r.refused&&confirmed===aborts&&transmitReady())arm('Reply');});},li.dataset.call);return;}
  if(reply&&!reply.refused&&transmitReady())arm('Reply');
}
othersList.addEventListener('mousedown',event=>{const li=secondPress(event,'tr[data-row]');if(li)answerOther(li);});
othersList.addEventListener('keydown',event=>{const li=event.target.closest('tr[data-row]');if(li&&event.key==='Enter'){event.preventDefault();answerOther(li);}});
if(activity)new MutationObserver(()=>{for(const tr of activity.querySelectorAll('tr[data-sequence]'))if(!tr.hasAttribute('tabindex'))tr.tabIndex=0;othersShow();}).observe(activity,{childList:true});
document.addEventListener('wstx-worked',()=>othersShow());
// The Band Activity colour choice (Settings > General > Display) applies to the callers too.
const bandActivity=document.querySelector('#band-activity');
if(bandActivity){const mirror=()=>{focus.dataset.hlOn=bandActivity.dataset.hlOn??'';othersShow();};mirror();new MutationObserver(mirror).observe(bandActivity,{attributes:true,attributeFilter:['data-hl-on']});}
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
// WstxContact::PointerEffect (#50): click Tx; double-click Rx and Tx; drag a marker;
const waterfall=document.querySelector('#waterfall'),wrap=document.querySelector('#waterfall-wrap');
const rxMarker=document.createElement('div'),txMarker=document.createElement('div');
rxMarker.className='ct-marker ct-rx';txMarker.className='ct-marker ct-txm';rxMarker.dataset.key='rx';txMarker.dataset.key='tx';
for(const m of [rxMarker,txMarker]){m.setAttribute('role','slider');m.setAttribute('aria-valuemin','0');m.setAttribute('aria-valuemax','3000');m.setAttribute('aria-label',m===rxMarker?'Rx marker, drag to set the Rx frequency':'Tx marker, drag to set the Tx frequency');}
for(const m of [rxMarker,txMarker]){const goal=document.createElement('span');goal.className='ct-goal';m.append(goal);}
wrap?.append(rxMarker,txMarker);
// #50: 3 px green Rx and red Tx lines without text; the Rx/Tx strip below shows the values.
// CL-050-07: the lines, their brackets and the pointer use the waterfall's one frequency
// mapping (recording.js wstxWaterfallAxis, the canvas box), as the frequency axis does. Each
// line is the lowest tone; its WSJT-X bracket spans the occupied width of the station's mode.
let dragging=null;
const occupiedHz=()=>(tick?tick.period===7500:typeof live!=='undefined'&&live?.job?.mode==='ft4')?4*12000/576:8*12000/1920;
function place(m,hz){const axis=window.wstxWaterfallAxis,x=axis.x(hz,wrap);m.style.left=`${x}px`;m.firstChild.style.width=`${axis.x(hz+occupiedHz(),wrap)-x}px`;}
function markers(){
  const s=snap?.settings;
  for(const [m,hz,label] of [[rxMarker,s?.rx_hz,'Rx'],[txMarker,s?.tx_hz,'Tx']]){if(dragging===m)continue;m.hidden=typeof hz!=='number';if(typeof hz==='number'){place(m,hz);m.dataset.hz=String(hz);m.title=`${label} ${hz} Hz`;m.setAttribute('aria-valuenow',String(hz));}}
}
const pointerHz=event=>window.wstxWaterfallAxis.hz(event.clientX);
if(waterfall)new ResizeObserver(()=>markers()).observe(waterfall);
addEventListener('station-message',event=>{if(event.detail?.message?.type==='station.tick')queueMicrotask(markers);});
for(const m of [rxMarker,txMarker]){
  m.addEventListener('pointerdown',event=>{if(event.button!==0||!snap)return;event.preventDefault();event.stopPropagation();dragging=m;m.setPointerCapture(event.pointerId);m.classList.add('ct-dragging');});
  m.addEventListener('pointermove',event=>{if(dragging!==m)return;place(m,pointerHz(event));m.title=`${m.dataset.key==='rx'?'Rx':'Tx'} ${pointerHz(event)} Hz`;});
  m.addEventListener('pointerup',event=>{if(dragging!==m)return;dragging=null;m.classList.remove('ct-dragging');const hz=pointerHz(event);if(String(hz)!==m.dataset.hz)send('set_frequency',{rx_hz:m.dataset.key==='rx'?hz:null,tx_hz:m.dataset.key==='tx'?hz:null},m.dataset.key==='rx'?'Rx frequency':'Tx frequency');else markers();});
  m.addEventListener('click',event=>event.stopPropagation());
}
// #50 WstxContact::PointerEffect: click sets Tx, double-click sets Rx and Tx. The click waits
// 250 ms (as in Band Activity) so a double-click sends only its one request.
let pointerTimer=null;
function pointer(rx,tx,label){send('set_frequency',{rx_hz:rx,tx_hz:tx},label);}
waterfall?.addEventListener('contextmenu',event=>event.preventDefault());
waterfall?.addEventListener('click',event=>{
  if(event.button!==0)return;const hz=pointerHz(event);clearTimeout(pointerTimer);
  pointerTimer=setTimeout(()=>pointer(null,hz,'Tx frequency'),250);
});
waterfall?.addEventListener('dblclick',event=>{clearTimeout(pointerTimer);const hz=pointerHz(event);pointer(hz,hz,'Rx and Tx frequency');});
// #82 WstxOperatingLayout::FreeTxSlotMarks: part of the waterfall, no setting. Each open range
// [lo, hi) of the latest held free_tx_slots is a bar over lo..hi in the frequency ruler, on the
// waterfall's one mapping (CL-050-07), with or without a run (no run_id match). The held value:
// each free_tx_slots.state replaces it in socket order; a GET /automation reply (read only after
// automation.state, #74) only with a later at_utc_ms; a new boot drops it. No other request.
let freeTxSlots=null;
const freeTxLayer=document.createElement('div');freeTxLayer.id='free-tx-slots';freeTxLayer.setAttribute('aria-hidden','true');freeTxLayer.hidden=true;
const freeTxValue=v=>v===null||!!v&&typeof v==='object'&&Number.isSafeInteger(v.at_utc_ms)&&Array.isArray(v.open)&&['ft8','ft4'].includes(v.mode);
// A reply's null or older value never replaces the held one (the event is pushed every period).
function freeTxSlotsRead(a){
  const v=a.free_tx_slots;
  if(v&&freeTxValue(v)&&!(freeTxSlots&&v.at_utc_ms<=freeTxSlots.at_utc_ms)){freeTxSlots=v;freeTxSlotMarks();}
}
function freeTxSlotsPushed(v){if(freeTxValue(v)){freeTxSlots=v;freeTxSlotMarks();}}
// #76 look: no text on the marks; each bar is shortened by 2 px at each end, so touching ranges
// show a 4 px gap. A range narrower than both insets (a phone) draws no bar.
const freeTxInsetPx=2;
function freeTxSlotMarks(){
  const ruler=document.querySelector('#frequency-ruler'),axis=window.wstxWaterfallAxis;if(!ruler||!axis)return;
  if(freeTxLayer.parentNode!==ruler)ruler.append(freeTxLayer);
  const v=freeTxSlots,show=!!v&&v.open.length>0;
  freeTxLayer.replaceChildren();freeTxLayer.hidden=!show;if(!show)return;
  for(const r of v.open){
    if(!Array.isArray(r)||!Number.isInteger(r[0])||!Number.isInteger(r[1])||r[1]<=r[0])continue;
    const left=axis.x(r[0],ruler)+freeTxInsetPx,right=axis.x(r[1],ruler)-freeTxInsetPx;
    const bar=document.createElement('div');bar.className='fts-bar';bar.dataset.lo=String(r[0]);bar.dataset.hi=String(r[1]);bar.style.left=`${left}px`;bar.style.width=`${Math.max(0,right-left)}px`;
    freeTxLayer.append(bar);
  }
}
window.wstxFreeTxSlotMarks=freeTxSlotMarks;
// An Off page has no waterfall and gets no value: its held value goes (a peer coming back from Off
// gets the current value once, PushedStationState).
document.querySelector('#display-profile')?.addEventListener('change',event=>{if(event.target.value==='off'){freeTxSlots=null;freeTxSlotMarks();}});
{const ruler=document.querySelector('#frequency-ruler');if(ruler)new ResizeObserver(()=>freeTxSlotMarks()).observe(ruler);}
const period=document.querySelector('#radio-toolbar .op-period'),meter=document.querySelector('#settings-audio .op-input-meter');
function displays(){
  if(!period||!meter)return;
  const label=period.querySelector('span');
  if(!tick){label.textContent='UTC unavailable';meter.querySelector('strong').textContent='Unknown';return;}
  const stale=connection.dataset.state!=='connected',utc=stationNow()??tick.utc;
  label.textContent=`UTC ${new Date(utc).toISOString().slice(11,19)}${stale?' (stale)':''}`;
  // #61 CL-061-04: the station measures no level in its Tx period (rx_level_db null); a level
  // and its low/high entry refer to receive periods only.
  const level=tick.level,strong=meter.querySelector('strong');
  strong.textContent=level===null?(tick.transmitting?'Tx \u00b7 not measured':'Unavailable'):`${level} dB${level>85?' high':level<15?' low':''}`;
  meter.dataset.level=level===null?'':level>85?'high':level<15?'low':'ok';
  meter.querySelector('div').style.setProperty('--ct-level',`${level===null?0:Math.min(100,level/0.9)}%`);
  countdown();
}
// QsoPane NEXT (#37/#50): "TX now" while the station reports transmitting, else "next";
// the period bar on the station clock, red in my Tx periods (Enable Tx on) and while
// transmitting, green otherwise.
function countdown(){
  const bar=$('qso-progress'),text=$('qso-countdown'),label=$('qso-next-label'),line=$('qso-next');if(!bar||!text)return;
  const utc=stationNow();
  if(!tick||!snap||utc===null){bar.style.width='0%';bar.dataset.phase='rx';text.textContent='';return;}
  const p=tick.period,index=Math.floor(utc/p),start=index*p,parity=snap.settings.parity==='odd'?1:0,armed=snap.transmit.arm_state==='armed';
  bar.style.width=`${Math.min(100,100*(utc-start)/p)}%`;
  bar.dataset.phase=tick.transmitting||(armed&&index%2===parity)?'tx':'rx';
  const c=snap.contact,next=c?(c.messages[slots.indexOf(c.next_slot)]??'None'):'None';
  line.dataset.now=String(tick.transmitting);
  if(tick.transmitting&&snap.transmit.tune){
    // Tune is a tone, not a message: its own line and the Tune time left.
    label.textContent='▶ TX now:';$('contact-next').textContent='Tune';
    text.textContent=`${snap.watchdog?.tune_remaining_seconds??0} s left`;
    return;
  }
  if(tick.transmitting){
    const t=snap.transmit,end=start+(p===7500?300+5040:500+12640);
    label.textContent='\u25B6 TX now:';$('contact-next').textContent=t.last_period_utc===start&&t.last_text?t.last_text:next;
    text.textContent=`${Math.max(0,Math.ceil((end-utc)/1000))} s left`;
    return;
  }
  label.textContent='\u25B8 next:';$('contact-next').textContent=next;
  const following=(index+1)%2===parity?index+1:index+2,wait=Math.ceil((following*p-utc)/1000);
  text.textContent=armed?`Tx in ${wait} s`:`next ${parity?'odd':'even'} period in ${wait} s`;
}
setInterval(displays,250);setInterval(countdown,100);
// ---------------------------------------------------------------- station events
// Reconnect (a new socket) reloads the authoritative snapshot; a status refresh on the
// same socket does not (contact.state announces every change).
let readySocket=null;
// The PSK Reporter and startup states are read once per socket and after a new boot; the
// automation state only after automation.state (#74: never on connect).
addEventListener('station-ready',event=>{const fresh=event.detail!==readySocket;if(!fresh&&!bootReads&&(contactMissing||snap&&snap.boot_id===profileData?.boot_id))return;readySocket=event.detail;load();if(fresh||bootReads){bootReads=false;loadStartup();loadPskr();}});
addEventListener('station-stale',()=>{displays();});
addEventListener('station-message',event=>{
  const {message,current}=event.detail;if(current!==socket)return;
  const d=message.data;
  if(message.type==='contact.state'&&d?.changed)stateShow();
  else if(message.type==='automation.state'&&d)loadAutomation();
  // #82 free_tx_slots.state carries its state: no read after it.
  else if(message.type==='free_tx_slots.state'&&d)freeTxSlotsPushed(d.free_tx_slots);
  else if(message.type==='station.tick'&&d&&Number.isSafeInteger(d.utc_ms)&&[15000,7500].includes(d.period_ms)){
    const changed=tick?.transmitting!==d.transmitting;stationSample(d.utc_ms);
    tick={utc:d.utc_ms,at:performance.now(),period:d.period_ms,transmitting:d.transmitting===true,level:Number.isInteger(d.rx_level_db)?d.rx_level_db:null};$('contact-tx').max=d.period_ms===7500?'2916':'2950';
    displays();if(changed)render();else stationTx();
  }
});
render();
// This client loads after the first snapshots: an automation.state the socket already carried is read now.
if(socket?.readyState===WebSocket.OPEN&&connection.dataset.state==='connected'){readySocket=socket;load();loadStartup();loadPskr();if(automationAnnounced===socket)loadAutomation();}
// #82: a free_tx_slots.state the socket carried before this client loaded is drawn now.
if(freeTxSlotsHeld&&freeTxSlotsHeld.current===socket)freeTxSlotsPushed(freeTxSlotsHeld.value);
// WstxTransmit::TransmitWire: explicit requests only; the server plans, keys and halts.
document.querySelector('#transmit-status').insertAdjacentHTML('afterend','<label>Message<input id="tx-message" maxlength="37" value="CQ"></label><label>Mode<select id="tx-mode" disabled title="Follows the station operating mode"><option value="ft8">FT8</option><option value="ft4">FT4</option></select></label><label>Tx offset Hz<input id="tx-offset" type="number" min="200" max="2950" value="1500"></label><label>Period<select id="tx-parity"><option value="even">Even / 1st</option><option value="odd">Odd / 2nd</option></select></label><p><button type="button" id="tx-arm">Arm (Enable Tx)</button> <button type="button" id="tx-disarm">Disarm</button> <button type="button" id="tx-send">Send next period</button> <button type="button" id="tx-tune">Tune</button></p>');
let transmitSequence=0;
addEventListener('station-message',event=>{const m=event.detail?.message;if(m?.type==='station.tick'&&[15000,7500].includes(m.data?.period_ms)){const ft4=m.data.period_ms===7500;document.querySelector('#tx-mode').value=ft4?'ft4':'ft8';document.querySelector('#tx-offset').max=ft4?'2916':'2950';}});
async function transmitAction(extra,label){
  const result=document.querySelector('#transmit-result');
  try{const reply=await transmitPost('/transmit/command',extra),r=reply.result;result.textContent=`${label}: ${r.kind??(r.accepted?'accepted':'refused')}${r.refusal?' · '+r.refusal:''}${r.failure?' · '+r.failure:''}`;}
  catch(error){result.textContent=`${label} not sent · ${error.message}`;}
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
document.querySelector('#server-fields-general .op-apply-row').insertAdjacentHTML('beforebegin','<label>Continent<select id="station-continent"><option value="">From callsign</option><option value="AF">Africa</option><option value="AN">Antarctica</option><option value="AS">Asia</option><option value="EU">Europe</option><option value="NA">North America</option><option value="OC">Oceania</option><option value="SA">South America</option></select><small id="continent-derived"></small></label>');
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
window.wstxRenderHistory=function renderHistory(body,blocks=activityHistory){
  for(const block of blocks){
    if(!block.rows.length)continue;
    const divider=document.createElement('tr');divider.className='ba-divider';divider.setAttribute('role','row');
    const cell=document.createElement('td');cell.colSpan=7;cell.setAttribute('role','cell');cell.textContent=`${block.mode.toUpperCase()} period ${periodLabel(block.period,block.mode)}${block.period?' UTC':''}`;divider.append(cell);body.append(divider);
    for(const record of activityOrdering(block.rows))body.append(activityRow(record,'history',block.context,block.mode));
  }
}
window.wstxDistanceKm=distanceKm;
function chip(key,severity,text,action){const button=document.createElement('button');button.type='button';button.className='op-chip';button.dataset.chip=key;button.dataset.severity=severity;button.textContent=`${severity==='error'?'\u2716':'\u26A0'} ${text}`;button.title=text;button.addEventListener('click',action);return button;}
// ErrorField: since when this page sees each condition hold (UTC HH:MM); a cleared one is forgotten.
const errorSince=new Map();
// Transmit refusals that are transient or retried by the station: no entry (CL-037-02).
const transientRefusals=new Set(['not_armed','audio_started','duplicate_sequence','stale_request','misaligned_period','stale_period','busy','not_authorized','authority_changed','state_conflict','stale_revision']);
window.wstxChipsShow=function(){
  const list=[],connected=connection.dataset.state==='connected',open=section=>()=>showRegion('server-settings',null,section);
  if(connection.dataset.state==='stale')list.push(chip('link','error','Station connection lost \u00b7 reconnecting',open('settings-expert')));
  if(connected){
    const refusal=snap?.transmit?.refusal;
    if(refusal&&!transientRefusals.has(refusal))list.push(chip('transmit','error',`Tx refused \u00b7 ${refusal.replace(/_/g,' ')}`,open('settings-radio')));
    const txWarnings={alc_high:['warn','ALC too high \u00b7 Tx level lowered'],po_low:['warn','Tx power low'],swr_high:['warn','SWR high'],swr_fault:['error','SWR too high \u00b7 Tx stopped, check the antenna']};
    for(const w of window.wstxTxWarnings?.()??[])if(txWarnings[w])list.push(chip(`tx-${w}`,txWarnings[w][0],txWarnings[w][1],open('settings-audio')));
    const mode=profileData?.settings.control.mode,radio=operatingState?.radio.state;
    if(mode==='cat'&&catStatus?.condition==='commissioningRequired')list.push(chip('cat','warn','CAT setup not confirmed',open('settings-cat')));
    else if(mode==='cat'&&catStatus&&catStatus.condition!=='ready')list.push(chip('cat','error',document.querySelector('#cat-status').textContent,open('settings-cat')));
    else if(mode==='cat'&&!catStatus&&radio&&radio!=='ready')list.push(chip('cat','error',`CAT ${radio}`,open('receive-details')));
    const nativeProblem=window.wstxNativeProblem?.();
    if(nativeProblem)list.push(chip('native','error',nativeProblem,open('receive-details')));
    const a=live?.audio,active=live?.job&&['running','cancelling'].includes(live.job.state);
    if(a?.state==='unavailable')list.push(chip('audio','error',`Audio unavailable${a.error?' \u00b7 '+a.error:''}`,open('settings-audio')));
    const level=document.querySelector('#settings-audio .op-input-meter')?.dataset.level;
    if(active&&level==='low')list.push(chip('level','warn','Audio level low',open('settings-audio')));
    if(active&&level==='high')list.push(chip('level','warn','Audio overdriven',open('settings-audio')));
    if(transmitConfigured()&&transmitView?.clock==='unsynchronized')list.push(chip('clock','error','Clock off \u00b7 Tx blocked',open('settings-clock')));
    else if(transmitConfigured()&&transmitView?.clock==='unknown'&&['air','both'].includes(transmitView.clock_source))list.push(chip('clock','error','Clock unknown \u00b7 Tx blocked',open('settings-clock')));
    if(transmitConfigured()&&transmitView?.clock_warning)list.push(chip('clock-warning','warn','NTP and air clock disagree',open('settings-clock')));
    if(uncertainMutation)list.push(chip('receive','warn',receiveFailure||'Receive outcome unknown',open('receive-details')));
    else if(operatingFailure&&operatingSupported!==false)list.push(chip('selection','warn',operatingFailure,open('receive-details')));
    else if(operatingUnknown)list.push(chip('selection','warn','Band/mode outcome unknown',open('receive-details')));
    else if(operatingState?.operation?.result==='failed')list.push(chip('selection','error',`Band/mode change failed${operatingState.operation.error?' \u00b7 '+operatingState.operation.error:''}`,open('receive-details')));
    else if(live&&!active&&!mutationPending&&!receiveTarget()&&a?.state!=='unavailable'){
      if(receiveInputConfigured())list.push(chip('receive','warn','Receive stopped \u00b7 start',()=>receiveToggle()));
      else list.push(chip('receive','warn','No audio input',open('settings-audio')));
    }
  }
  const now=new Date(),keys=new Set(list.map(b=>b.dataset.chip));
  for(const k of [...errorSince.keys()])if(!keys.has(k))errorSince.delete(k);
  for(const k of keys)if(!errorSince.has(k))errorSince.set(k,now.toISOString().slice(11,16));
  const key=list.map(b=>b.dataset.chip+b.textContent+errorSince.get(b.dataset.chip)).join('|');
  if(chips.dataset.key!==key){chips.dataset.key=key;chips.replaceChildren(...list.map(b=>{const entry=document.createElement('div');entry.className='op-error-entry';entry.setAttribute('role','listitem');entry.dataset.severity=b.dataset.severity;const since=document.createElement('span');since.className='op-error-since';since.textContent=`since ${errorSince.get(b.dataset.chip)}`;entry.append(b,since);return entry;}));}
}
setInterval(()=>window.wstxChipsShow(),1000);
window.wstxChipsShow();if(typeof renderResults==='function')renderResults();
document.querySelector('#help-keys').insertAdjacentHTML('beforeend','<div><dt>CQ / double-click a decode</dt><dd>Start the QSO: transmission starts with the next period and ends after RR73/73 or HALT</dd></div><div><dt>F2</dt><dd>Settings</dd></div><div><dt>F4</dt><dd>Clear the DX call (cancel the contact)</dd></div><div><dt>Alt+1 &hellip; Alt+6</dt><dd>Next message Tx1&hellip;Tx6</dd></div><div><dt>Alt+M</dt><dd>Start or stop receive</dd></div><div><dt>Alt+T / Alt+Q</dt><dd>Tune / Log QSO</dd></div><div><dt>F11 / F12</dt><dd>Rx &minus;/+ 1 Hz</dd></div><div><dt>Shift+F11 / Shift+F12</dt><dd>Tx &minus;/+ 60 Hz (FT4 90 Hz)</dd></div><div><dt>Ctrl+F11 / Ctrl+F12</dt><dd>Rx and Tx &minus;/+ 1 Hz</dd></div><div><dt>Waterfall click / double-click</dt><dd>Set Tx / Rx and Tx; drag the green Rx or red Tx line</dd></div><div><dt>Rx/Tx fields: wheel, arrows, &minus;/+</dt><dd>1 Hz; with Shift 10 Hz</dd></div><div><dt>Band Activity: click / double-click / right-click</dt><dd>Select / Reply / menu</dd></div><div><dt>Separator arrows / Home / End</dt><dd>Resize the spectrum and waterfall</dd></div>');
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
// The continent (Settings > General) is a station setting of WstxStrategy (#39), below.
let applyConfirmed=false;
serverForm.addEventListener('submit',async event=>{
  if(applyConfirmed){applyConfirmed=false;return;}
  const s=window.wstxContact?.snapshot?.(),c=s?.contact,busy=(c&&!['idle','completed','cancelled'].includes(c.state))||s?.transmit?.arm_state==='armed'||s?.transmit?.tune;
  if(!busy)return;
  event.preventDefault();event.stopImmediatePropagation();
  if(await confirmAction('Applying these settings may restart receive and interrupt the QSO in progress. Apply now?','Apply')){applyConfirmed=true;serverForm.requestSubmit();}
},true);
window.wstxContact=Object.freeze({load,snapshot:()=>snap});
stateShow();
})();
// #39 WstxStrategy: the strategy element (selector, editor, Value), the marks and value order in
// Band Activity and the editor popup. The station evaluates every strategy (POST
// /strategy/evaluate) and decides the run; this client only sends the selection and shows verdicts.
(()=>{
const $=id=>document.getElementById(id);
const nameSelect=$('strategy-name'),editButton=$('strategy-edit'),valueButton=$('activity-value'),statusNode=$('station-automation'),contestButton=$('strategy-contest'),showAllButton=$('activity-show-all');
if(!nameSelect)return;
const autoButton=$('qso-auto');let autoPosting=false;
let view=null,viewLoading=null,viewAgain=false,strategyMissing=false,automation=null,run=null,refusal=null,pounceConfirmed=false,verdicts=new Map(),evaluatedKey='',evaluating=false,evaluateAgain=false;
const config=()=>view?.configuration??null;
const builtins=()=>view?.builtin_strategies??[];
// WstxStrategy::AutoToggle: station state, read from the snapshot only (never a local guess).
const auto=()=>view?.auto===true;
const active=()=>{const c=config();return [...(c?.strategies??[]),...builtins()].find(s=>s.name===c?.active)??null;};
// #63 WstxContest: the contest in force and the profiles of GET /strategy/contests.
let contests=[],contestsAsked=false,contestSummary=null,showAll=false;
const selection=()=>config()?.contest??null;
const selectedProfile=()=>contests.find(p=>p.id===selection()?.profile)??null;
// Read only for the prompt or a contest in force: the profiles are several kB on a thin link.
async function loadContests(){
  contestsAsked=true;
  try{const r=await stationFetch('/strategy/contests',{cache:'no-store',signal:AbortSignal.timeout(10000)});const d=r.ok?await r.json():null;if(d?.v===1){contests=d.profiles;show();}}catch{}
  return contests;
}
const runActive=()=>!!run&&run.state!=='stopped';
const strategyRun=()=>runActive()&&run.strategy;
function loadStrategy(){
  // A change announced during a read reads again: it must not leave an older view.
  if(viewLoading){viewAgain=true;return viewLoading;}
  // WstxStationProtocol::PushedStationState: a reply of another boot (or of a read a new boot
  // dropped) is discarded.
  const loading=viewLoading=stationFetch('/strategy',{cache:'no-store',signal:AbortSignal.timeout(10000)}).then(r=>{if(loading===viewLoading)strategyMissing=r.status===404;return r.ok?r.json():null;}).then(v=>{if(loading!==viewLoading||v?.v!==1||v.boot_id!==profileData?.boot_id)return;if(view?.revision!==v.revision){verdicts=new Map();evaluatedKey='';}view=v;show();evaluateShown();}).catch(()=>{}).finally(()=>{if(loading!==viewLoading)return;viewLoading=null;if(viewAgain){viewAgain=false;loadStrategy();}});
  return loading;
}
// WstxStrategy::StrategySelector (#74): a new boot drops the strategy snapshot, its verdicts and
// the automation snapshot at once; the element shows the freshly loaded form until GET /strategy.
addEventListener('station-boot',()=>{
  view=null;viewLoading=null;viewAgain=false;strategyMissing=false;automation=null;run=null;refusal=null;
  verdicts=new Map();evaluatedKey='';contests=[];contestsAsked=false;contestSummary=null;show();
});
async function saveConfiguration(configuration,label){
  if(!view)return false;
  try{
    const response=await stationFetch('/strategy',{method:'PUT',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:view.profile_id,boot_id:view.boot_id,expected_revision:view.revision,configuration}),signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);
    if(!response.ok||data?.v!==1){const e=data?.error;statusNode.textContent=`${label} not saved · ${e?.code??response.status}${e?.field?` (${e.field})`:''}${e?.code==='stale_revision'?' · changed elsewhere, reloaded':''}`;if(e?.code==='stale_revision')await loadStrategy();return false;}
    // A saved configuration is evaluated at once, not at the next publication.
    if(data.boot_id!==profileData?.boot_id)return false;
    view=data;verdicts=new Map();evaluatedKey='';show();evaluateShown();return true;
  }catch(error){statusNode.textContent=`${label} not saved · ${error.message}`;return false;}
}
const words_=t=>String(t).replace(/_/g,' ');
// WstxMcp::AutomationIndicator: the automation snapshot's own text (null: never used, idle).
function automationLine(){
  const r=automation?.run,active=!!r&&r.state!=='stopped';
  statusNode.dataset.active=String(active);
  // #42 a pounce run names its call (WstxStrategy::Pounce).
  statusNode.textContent=active&&r.pounce?`Pounce ${r.pounce.call} ${r.state==='waiting'?'waiting':'in QSO'} · HALT ends it`:active?`Automation ${{waiting:'waiting',manual:'paused for your QSO'}[r.state]??'in contact'} · run ${String(r.id).slice(0,8)} · HALT ends it`:r?.reason&&r.reason!=='stopped'?`Automation stopped · ${words_(r.reason)}`:'Automation idle';
}
// WstxStrategy::StrategySelector (#74 D1): the one writer of the #station-automation line, drawn
// from the current strategy snapshot and the current automation snapshot (GET /automation,
// read on automation.state only) together at each change of either.
function showRun(){
  const name=config()?.active;
  // WstxContest::ContestView: the contest, its period and the log inside it.
  const contest=selection(),on=auto()&&!refusal&&strategyRun();
  // A run that ended turned Auto off with its stop reason (StrategyRun); a plain stop says nothing more.
  const stopped=!auto()&&run?.strategy&&run.state==='stopped'&&run.reason&&run.reason!=='stopped'?` · stopped · ${words_(run.reason)}`:'';
  const doing=()=>run.state==='contact_active'?run.selected?.call??'in QSO':run.state==='calling_cq'?'calling CQ':run.state==='manual'?'your QSO':null;
  if(contest){
    const when=t=>`${t.slice(5,10)} ${t.slice(11,16)}`,tally=contestSummary?` · ${contestSummary.qsos} QSOs · ${contestSummary.multipliers} mult · score ${contestSummary.score}`:'';
    // WstxContest::ContestView, ContestRun: the operation, Auto (off is colouring only) and the run
    // state from GET /automation, read on automation.state only.
    const state=refusal?` · not started · ${words_(refusal)}`:on?` · ${doing()??`waiting${run.reason?` · ${words_(run.reason)}`:''}`}`:stopped;
    statusNode.dataset.active=String(!!on);statusNode.textContent=`Contest ${selectedProfile()?.name??contest.profile} · ${when(contest.start)} to ${when(contest.end)} UTC · ${config()?.active??''} · Auto ${auto()?'on':'off'}${state}${tally}`;
    return;
  }
  // None (or no strategy snapshot yet): a strategy run the HALT or a selection ended; without a
  // strategy run the automation snapshot's text, "Automation idle" without a run.
  if(!name){if(run?.strategy){statusNode.dataset.active='false';statusNode.textContent=run.reason&&run.reason!=='stopped'?`Strategy stopped · ${words_(run.reason)}`:'Strategy None';}else automationLine();return;}
  if(refusal){statusNode.textContent=`Strategy ${name} not started · ${words_(refusal)}`;statusNode.dataset.active='false';return;}
  if(runActive()&&run.pounce){automationLine();return;}
  statusNode.dataset.active=String(!!on);
  // WstxStrategy::StrategySelector: with Auto off a selection only marks.
  statusNode.textContent=!auto()?`Strategy ${name} · Auto off${stopped}`:!on?`Strategy ${name} · Auto on`:doing()?`Strategy ${name} · ${doing()}`:`Strategy ${name} waiting${run.reason?` · ${words_(run.reason)}`:''}`;
}
function show(){
  const c=config();
  const contest=selection(),contestValue=contest?`contest:${contest.profile}`:null;
  const options=[['','None'],...builtins().map(s=>[s.name,s.name]),...(c?.strategies??[]).map(s=>[s.name,s.name]),...(contest?[[contestValue,`${selectedProfile()?.name??contest.profile} (contest)`]]:[])];
  const key=options.map(o=>o.join('|')).join('\n');
  if(nameSelect.dataset.key!==key){nameSelect.dataset.key=key;nameSelect.replaceChildren(...options.map(([value,label])=>{const o=document.createElement('option');o.value=value;o.textContent=label;return o;}));}
  // Always the station's: a HALT's None must show also while the selector has the focus.
  nameSelect.value=contestValue??c?.active??'';
  if(contest&&!contestsAsked)loadContests();
  contestButton.disabled=!c;contestButton.title=c?'Choose a contest strategy and its period':'Contest strategies unavailable';
  if(window.wstxContestOn!==!!contest){window.wstxContestOn=!!contest;if(typeof bandColoursApply==='function')bandColoursApply();}
  showAllButton.hidden=!contest;showAllButton.setAttribute('aria-pressed',String(showAll));
  nameSelect.disabled=!c;nameSelect.title=c?'Selecting a strategy marks its candidates; it transmits only while Auto is on. None turns Auto off':(view?.configuration_error?`Saved strategies unreadable (${view.configuration_error}); the editor's Save replaces them`:'Strategies unavailable');
  editButton.disabled=!view;editButton.title='Edit strategies (the station keeps receiving)';
  showContinent();showIgnore();showPounce();showMostWanted();showRun();showAuto();
  decorate();
}
// ---------------------------------------------------------------- Auto (QsoPane direct buttons)
// WstxStrategy::AutoToggle: green while the station says on, grey while off; a click sends one
// POST /strategy/auto with the other value, for a contest whose rules forbid automatic operation
// after its warning. Switching off is always possible; on needs a selection and transmit.
const selected=()=>!!config()?.active||!!selection();
function showAuto(){
  if(!autoButton)return;const on=auto(),ready=window.wstxContact?.snapshot()?.transmit?.capability==='available';
  autoButton.setAttribute('aria-pressed',String(on));autoButton.dataset.on=String(on);
  const reason=!view?'Strategies are loading':on?'':!ready?'Receive only':!selected()?'Select a strategy or a contest first':'';
  autoButton.disabled=autoPosting||!!reason;
  // #81 WstxStrategy::StartedQso: Auto off ends the run, a QSO already started is finished.
  autoButton.title=reason||(on?'Auto on: the selection transmits. Click to switch Auto off; a QSO already started is finished':'Auto off: the selection only marks. Click to let it transmit');
}
addEventListener('wstx-contact-render',showAuto);
autoButton?.addEventListener('click',async()=>{
  if(!view||autoPosting)return;const on=!auto();let confirmed=false;
  if(on&&selection()){
    // WstxContest::AutomationClause: a contest whose rules forbid it asks first; declined sends nothing.
    if(!selectedProfile())await loadContests();const p=selectedProfile();
    if(p?.automation==='forbidden'){if(!await window.wstxConfirm(`The rules of ${p.name} forbid automatic operation: ${p.automation_text} Transmit automatically anyway?`,'Transmit automatically'))return;confirmed=true;}
  }
  autoPosting=true;showAuto();
  try{
    const response=await stationFetch('/strategy/auto',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:view.profile_id,boot_id:view.boot_id,auto:on,...(confirmed?{automation_confirmed:true}:{})}),signal:AbortSignal.timeout(10000)});
    // The toggle follows strategy.state, not this reply; a refusal says why.
    if(!response.ok){const e=(await response.json().catch(()=>null))?.error;statusNode.textContent=`Auto not switched · ${e?.code??response.status}${e?.field?` (${e.field})`:''}`;}
  }catch(error){statusNode.textContent=`Auto not switched · ${error.message}`;}
  finally{autoPosting=false;showAuto();}
});
// ---------------------------------------------------------------- marks and value order
const tbody=document.querySelector('#band-activity tbody');
const identity=()=>typeof live!=='undefined'&&live?.job?liveIdentity(live):'';
function marksOn(){return (!!active()||!!selection())&&!!identity();}
const valueSort=()=>typeof activitySortField!=='undefined'&&activitySortField==='value';
let reordering=false;
function decorate(){
  if(!tbody)return;
  valueButton.setAttribute('aria-pressed',String(valueSort()));
  const on=marksOn(),rows=[...tbody.querySelectorAll('tr[data-sequence]')];
  for(const tr of rows){
    const v=on?verdicts.get(tr.dataset.resultId):null;
    const ranked=v?.rank!==null&&v?.rank!==undefined;
    tr.classList.toggle('ba-strategy',ranked);tr.classList.toggle('ba-grey',!!v?.grey);
    // WstxContest::ContestView: only what can be called, unless Show all; the partner and rows to me stay.
    tr.classList.toggle('ba-contest-mult',!!v?.new_multiplier);tr.classList.toggle('ba-dupe',!!v?.dupe);
    tr.classList.toggle('ba-hidden',on&&!!selection()&&!showAll&&!ranked&&!tr.classList.contains('ba-tome')&&!tr.classList.contains('ba-partner'));
    if(v&&v.rank!==null)tr.dataset.rank=String(v.rank+1);else delete tr.dataset.rank;
    // #55 BandActivityHover: the verdict joins the row's other reasons.
    if(v?.grey)tr.dataset.whyStrategy='Directed CQ, not calling us: the strategy skips it, a double-click warns';else if(v?.dupe)tr.dataset.whyStrategy='Dupe in the contest period';else if(selection()&&v&&v.rank!==null)tr.dataset.whyStrategy=[`Contest ${selectedProfile()?.name??selection().profile}: #${v.rank+1}`,v.new_multiplier?'new multiplier':'',v.points!==null&&v.points!==undefined?`${v.points} points`:''].filter(Boolean).join(' · ');else if(v&&v.rank!==null)tr.dataset.whyStrategy=`Strategy ${config().active}: #${v.rank+1}`;else delete tr.dataset.whyStrategy;window.wstxActivityWhy?.(tr);
  }
  // WstxStrategy::ValueView: in the value sort the ranked rows go up in the station's order; a
  // column click sorts by the column until Value is chosen again (the marks stay).
  if(!on||!valueSort())return;
  reordering=true;
  let block=[];
  const flush=()=>{
    const ranked=block.filter(tr=>tr.classList.contains('ba-strategy')).sort((a,b)=>verdicts.get(a.dataset.resultId).rank-verdicts.get(b.dataset.resultId).rank);
    if(!ranked.length)return;
    const anchor=block.at(-1).nextSibling;
    // #55 BandActivityValue: rows calling me stay above the candidates (value 1), also when ignored.
    const first=block.filter(r=>r.classList.contains('ba-tome')),order=[...ranked.filter(r=>first.includes(r)),...first.filter(r=>!ranked.includes(r)),...ranked.filter(r=>!first.includes(r))];
    for(const tr of [...order,...block.filter(r=>!order.includes(r))])tbody.insertBefore(tr,anchor);
  };
  for(const tr of [...tbody.children]){if(tr.classList.contains('ba-divider')){flush();block=[];}else if(tr.dataset.sequence)block.push(tr);}
  flush();observer.takeRecords();reordering=false;
}
function wanted(){
  // The sequences shown for the current receive identity, evaluated once each.
  const id=identity();if(!marksOn()||!id)return null;
  const seqs=[...tbody.querySelectorAll('tr[data-sequence]')].filter(tr=>tr.dataset.resultId.startsWith(id+'/')).map(tr=>Number(tr.dataset.sequence)).filter(Number.isSafeInteger);
  if(!seqs.length)return null;
  const first=Math.min(...seqs),next=Math.max(...seqs)+1;
  return {first:Math.max(first,next-2048),next,id};
}
// Asked after a new publication event (its rows have arrived) and after a save or an ignore;
// never on a timer.
async function evaluateShown(){
  // Rows that arrive during an evaluation are asked for when it ends (no timer).
  if(evaluating){evaluateAgain=true;return;}
  const w=wanted();if(!w)return;
  const key=`${view.revision}/${window.wstxContact?.snapshot()?.settings?.activity??''}/${w.id}/${w.first}/${w.next}`;if(key===evaluatedKey)return;
  if(!(typeof resultView!=='undefined'&&resultView&&resultCursor>=resultView.next_sequence))return;
  evaluating=true;
  try{
    const [,,source_id,job_id,generation]=w.id.split('/');
    const response=await stationFetch('/strategy/evaluate',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:view.profile_id,boot_id:view.boot_id,source_id,job_id,generation:Number(generation),first_sequence:w.first,next_sequence:w.next,strategy:null,explain:false}),signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);
    if(response.ok&&data?.v===1&&w.id===identity()){
      const map=new Map();data.verdicts.forEach(v=>map.set(`${w.id}/${v.sequence}`,{rank:v.rank,grey:v.grey,dupe:v.dupe,new_multiplier:v.new_multiplier,points:v.points}));
      verdicts=map;evaluatedKey=key;decorate();
      contestSummary=data.contest??null;showRun();
    }
  }catch{}finally{evaluating=false;if(evaluateAgain){evaluateAgain=false;evaluateShown();}}
}
const observer=new MutationObserver(()=>{if(reordering)return;decorate();evaluateShown();});
if(tbody)observer.observe(tbody,{childList:true});
nameSelect.addEventListener('change',()=>{const c=config();if(!c||nameSelect.value.startsWith('contest:'))return;const {contest:_,...rest}=c;contestSummary=null;saveConfiguration({...rest,active:nameSelect.value||null},'Strategy').then(ok=>{if(!ok)show();});});
showAllButton.addEventListener('click',()=>{showAll=!showAll;show();});
valueButton.addEventListener('click',()=>{if(typeof sortBy==='function')sortBy({dataset:{sort:'value'}});show();});
document.querySelector('#band-activity thead')?.addEventListener('click',()=>valueButton.setAttribute('aria-pressed',String(valueSort())));
// ---------------------------------------------------------------- run state
addEventListener('wstx-automation',event=>{automation=event.detail??null;const r=automation?.run??null;run=r&&{...r,strategy:!!automation.configuration?.strategy};refusal=automation?.strategy_refusal??null;show();});
async function automationCommand(action,extra){
  const s=window.wstxContact?.snapshot();if(!s)throw new Error('contact state unavailable');
  const response=await stationFetch('/automation/command',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:s.profile_id,boot_id:s.boot_id,command_id:crypto.randomUUID(),action,...extra}),signal:AbortSignal.timeout(10000)});
  const data=await response.json().catch(()=>null);
  if(response.status!==202&&response.status!==200)throw new Error(`${data?.error?.code??response.status}${data?.error?.field?` (${data.error.field})`:''}`);
  return data;
}
async function readAutomation(){const r=await stationFetch('/automation',{cache:'no-store',signal:AbortSignal.timeout(10000)});if(!r.ok)throw new Error(`automation ${r.status}`);return r.json();}
// WstxStrategy::StrategyHttp strategy.state: a HALT's None or another browser's selection.
addEventListener('station-message',event=>{const m=event.detail?.message;if(m?.type==='contact.state'){show();evaluateShown();}else if(m?.type==='strategy.state'&&event.detail?.current===socket&&m.data?.strategy_revision!==view?.revision)loadStrategy();});
// ---------------------------------------------------------------- continent (Settings > General)
const continentSelect=$('station-continent');
function showContinent(){
  if(!continentSelect)return;const c=config();continentSelect.disabled=!c;
  if(document.activeElement!==continentSelect)continentSelect.value=c?.continent??'';
  $('continent-derived').textContent=`From callsign: ${view?.derived_continent??'unknown'}${c?.continent?` · using ${c.continent}`:''}`;
}
continentSelect?.addEventListener('change',()=>{const c=config();if(c)saveConfiguration({...c,continent:continentSelect.value||null},'Continent');});
// ---------------------------------------------------------------- #42 ignore lists
// WstxStrategy::IgnoreLists: the station keeps both lists and applies them; this client
// only edits them (PUT /strategy for the permanent list, POST /strategy/ignore for the
// session list) and shows the session list the station returns.
continentSelect?.closest('label')?.insertAdjacentHTML('afterend','<label>Always ignore (calls)<input id="ignore-calls" spellcheck="false" autocomplete="off" placeholder="K1ABC DL1XYZ" aria-describedby="ignore-help"></label><label>Session ignore (minutes)<input id="ignore-minutes" type="number" min="1" max="720" step="1"></label><div class="op-ignore-session"><small id="ignore-help">Ignored stations are never marked or answered by a strategy. Band Activity right-click adds a station for this session; a band change clears the session list.</small><ul id="ignore-session" aria-label="Ignored this session"></ul></div>');
const ignoreCalls=$('ignore-calls'),ignoreMinutes=$('ignore-minutes'),ignoreList=$('ignore-session');
const sessionIgnored=call=>(view?.session_ignore??[]).some(e=>e.call===call);
function showIgnore(){
  if(!ignoreCalls)return;const c=config();ignoreCalls.disabled=ignoreMinutes.disabled=!c;
  if(document.activeElement!==ignoreCalls)ignoreCalls.value=(c?.ignore_calls??[]).join(' ');
  if(document.activeElement!==ignoreMinutes)ignoreMinutes.value=c?String(c.session_ignore_minutes??30):'';
  const list=view?.session_ignore??[],key=list.map(e=>`${e.call}/${Math.ceil(e.remaining_s/60)}`).join(',');
  if(ignoreList.dataset.key===key)return;ignoreList.dataset.key=key;
  ignoreList.replaceChildren(...list.map(e=>{const li=document.createElement('li');li.innerHTML=`<span class="ig-call"></span> <small class="ig-left"></small> <button type="button" class="op-icon-button">&times;</button>`;
    li.querySelector('.ig-call').textContent=e.call;li.querySelector('.ig-left').textContent=`${Math.ceil(e.remaining_s/60)} min`;
    const b=li.querySelector('button');b.setAttribute('aria-label',`Stop ignoring ${e.call}`);b.addEventListener('click',()=>ignore(e.call,false));return li;}));
}
async function ignore(call,on){
  if(!view)return;
  try{
    const response=await stationFetch('/strategy/ignore',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:view.profile_id,boot_id:view.boot_id,call,ignore:on}),signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);
    if(!response.ok||data?.v!==1){const e=data?.error;statusNode.textContent=`Ignore not saved · ${e?.code??response.status}${e?.field?` (${e.field})`:''}`;return;}
    // The shown rows are evaluated again with the station's new list (#74: of this boot only).
    if(data.boot_id!==profileData?.boot_id)return;
    view=data;verdicts=new Map();evaluatedKey='';show();evaluateShown();
  }catch(error){statusNode.textContent=`Ignore not saved · ${error.message}`;}
}
// A change that leaves the saved value as it is (a repeated change on blur) sends nothing.
ignoreCalls?.addEventListener('change',()=>{const c=config(),calls=[...new Set(words(ignoreCalls.value,false))];if(c&&calls.join(' ')!==(c.ignore_calls??[]).join(' '))saveConfiguration({...c,ignore_calls:calls},'Ignore list');});
ignoreMinutes?.addEventListener('change',()=>{const c=config(),n=Number(ignoreMinutes.value);if(c&&Number.isInteger(n)&&n!==c.session_ignore_minutes)saveConfiguration({...c,session_ignore_minutes:n},'Session ignore');});
// Station strategy settings, not profile fields: they never mark the profile form unsaved,
// and Enter saves the list instead of submitting (applying) the profile form.
for(const el of [ignoreCalls,ignoreMinutes]){for(const type of ['input','change'])el?.addEventListener(type,event=>event.stopPropagation());
  el?.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();el.dispatchEvent(new Event('change'));}});}
// The session list ends by time and band change at the station: read it when Settings opens.
const settingsDrawer=document.querySelector('#settings-drawer');
if(settingsDrawer)new MutationObserver(()=>{if(!settingsDrawer.hidden)loadStrategy();}).observe(settingsDrawer,{attributes:true,attributeFilter:['hidden']});
// Band Activity right-click: Ignore <call> / Stop ignoring <call> for a row with a resolved sender.
const rowMenu=document.querySelector('#ba-menu');
const pounceItem=document.createElement('button');pounceItem.type='button';pounceItem.setAttribute('role','menuitem');pounceItem.dataset.menu='pounce';pounceItem.hidden=true;
const ignoreItem=document.createElement('button');ignoreItem.type='button';ignoreItem.setAttribute('role','menuitem');ignoreItem.dataset.menu='ignore';ignoreItem.hidden=true;rowMenu?.append(pounceItem,ignoreItem);
function rowSender(tr){
  const id=tr.dataset.resultId??'',cut=id.lastIndexOf('/'),context=id.slice(0,cut),sequence=Number(tr.dataset.sequence);
  const pools=[typeof live!=='undefined'&&live?.job&&liveIdentity(live)===context?resultRows:[],...(typeof activityHistory!=='undefined'?activityHistory.filter(h=>h.context===context).map(h=>h.rows):[])];
  const record=pools.flat().find(r=>r.sequence===sequence);
  return record?.status==='decoded'&&record.fields?.from?.kind==='call'?record.fields.from.text:null;
}
addEventListener('wstx-row-menu',event=>{
  const call=view?rowSender(event.detail):null;ignoreItem.hidden=!call;ignoreItem.dataset.call=call??'';
  if(call)ignoreItem.textContent=sessionIgnored(call)?`Stop ignoring ${call}`:`Ignore ${call}`;
  // #42 Pounce: offered for any resolved sender; stopping only the running pounce on it.
  const on=!!call&&pouncing(call);pounceItem.hidden=!call;pounceItem.dataset.call=call??'';
  if(call){pounceItem.textContent=on?`Stop pouncing ${call}`:`Pounce ${call}`;
    const capable=window.wstxContact?.snapshot()?.transmit?.capability==='available',mode=typeof live!=='undefined'?live?.job?.mode:null;
    pounceItem.disabled=!on&&(runActive()||!capable||!['ft8','ft4'].includes(mode));
    pounceItem.title=on?'Stop waiting for this station':runActive()?'Another automation run is active':!capable?'Transmission unavailable':!['ft8','ft4'].includes(mode)?'Pounce needs FT8/FT4 receive':`Answer ${call} when it calls CQ or ends a QSO with 73 (transmits)`;}
});
ignoreItem.addEventListener('click',()=>{const call=ignoreItem.dataset.call;if(call)ignore(call,!sessionIgnored(call));});
// ---------------------------------------------------------------- #42 Alert
// WstxStrategy::Alert: the station records an alert for each new candidate of the active strategy; this client
// lists the history and announces new alerts as the operator chose (both off by default):
// a short tone while the page is visible, a browser notification also while it is hidden.
ignoreList?.closest('.op-ignore-session')?.insertAdjacentHTML('afterend','<div class="op-alerts" style="min-width:0"><strong>Alerts</strong> <small>Each new station the active strategy would call records an alert; alerts never transmit.</small><br><label class="op-check"><input type="checkbox" id="alert-sound">Sound</label> <label class="op-check"><input type="checkbox" id="alert-notify">Browser notification</label> <small id="alert-note" role="status"></small><ul id="alert-history" aria-label="Alert history" style="margin:4px 0 0;padding-left:1.2em;max-height:12em;overflow:auto;overflow-wrap:anywhere"></ul><button type="button" id="alert-clear">Clear alerts</button></div>');
const alertSound=$('alert-sound'),alertNotify=$('alert-notify'),alertList=$('alert-history'),alertNote=$('alert-note');
let alertView=null,alertSeen=null,alertSocket=null,alertSeq=0,audio=null;
const alertKey=()=>`wstx.alerts.v1:${alertView?.profile_id??view?.profile_id??''}`;
function alertPrefs(){try{const p=JSON.parse(localStorage.getItem(alertKey())??'null');return {sound:p?.sound===true,notify:p?.notify===true};}catch{return {sound:false,notify:false};}}
function saveAlertPrefs(p){try{localStorage.setItem(alertKey(),JSON.stringify({sound:p.sound,notify:p.notify}));}catch{}}
const notifyGranted=()=>typeof Notification!=='undefined'&&Notification.permission==='granted';
function showAlertPrefs(){if(!alertSound)return;const p=alertPrefs();alertSound.checked=p.sound;alertNotify.checked=p.notify&&notifyGranted();alertNotify.disabled=typeof Notification==='undefined';if(alertNotify.disabled)alertNote.textContent='This browser offers no notifications here';}
function alertLine(a){
  return [`${String(a.utc??'').slice(11,19)} ${a.call} ${a.message}`,a.rule,[a.band,a.mode?String(a.mode).toUpperCase():null].filter(Boolean).join(' '),Number.isFinite(a.snr_db)?`${Math.round(a.snr_db)} dB`:null,a.dxcc].filter(Boolean).join(' \u00b7 ');
}
function showAlerts(){
  if(!alertList)return;const list=[...(alertView?.alerts??[])].reverse(),key=list.map(a=>a.id).join(',');
  alertClear.disabled=!list.length;if(alertList.dataset.key===key)return;alertList.dataset.key=key;
  alertList.replaceChildren(...list.map(a=>{const li=document.createElement('li'),span=document.createElement('span');span.className='al-text';span.textContent=alertLine(a);li.append(span);return li;}));
}
function alertAudio(){try{audio??=new AudioContext();if(audio.state==='suspended')audio.resume?.();}catch{audio=null;}return audio;}
function tone(){const a=alertAudio();if(!a)return;try{const o=a.createOscillator(),g=a.createGain(),t=a.currentTime;o.frequency.value=880;g.gain.setValueAtTime(0.15,t);g.gain.exponentialRampToValueAtTime(0.001,t+0.15);o.connect(g).connect(a.destination);o.start(t);o.stop(t+0.16);}catch{}}
function announce(a){
  const p=alertPrefs();
  if(p.sound&&document.visibilityState==='visible')tone();
  if(p.notify&&notifyGranted()){try{new Notification(`Alert ${a.call}`,{body:`${a.message} \u00b7 ${a.rule}`,tag:`wstx-alert-${a.id}`});}catch{}}
}
// quiet: the history read at page load or on a new socket announces nothing.
async function loadAlerts(quiet){
  const seq=++alertSeq;
  try{
    const response=await stationFetch('/strategy/alerts',{cache:'no-store',signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);
    if(seq!==alertSeq||!response.ok||data?.v!==1||!Array.isArray(data.alerts)||data.boot_id!==profileData?.boot_id)return;
    const known=alertSeen!==null&&alertView?.boot_id===data.boot_id&&!quiet;
    const fresh=known?data.alerts.filter(a=>a.id>alertSeen):[];
    alertView=data;alertSeen=Math.max(known?alertSeen:0,...data.alerts.map(a=>a.id));
    showAlertPrefs();showAlerts();for(const a of fresh)announce(a);
  }catch{}
}
const alertClear=$('alert-clear');
alertClear?.addEventListener('click',async()=>{
  if(!alertView)return;
  try{
    const response=await stationFetch('/strategy/alerts/clear',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:alertView.profile_id,boot_id:alertView.boot_id}),signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);
    if(!response.ok||data?.v!==1){alertNote.textContent=`Not cleared \u00b7 ${data?.error?.code??response.status}`;return;}
    if(data.boot_id!==profileData?.boot_id)return;
    alertSeq++;alertView=data;showAlerts();
  }catch(error){alertNote.textContent=`Not cleared \u00b7 ${error.message}`;}
});
alertSound?.addEventListener('change',()=>{saveAlertPrefs({...alertPrefs(),sound:alertSound.checked});if(alertSound.checked)alertAudio();});
// The notification permission is asked only here, on the operator's click.
alertNotify?.addEventListener('change',async()=>{
  const p=alertPrefs();alertNote.textContent='';
  if(!alertNotify.checked){saveAlertPrefs({...p,notify:false});return;}
  let permission=typeof Notification==='undefined'?'unavailable':Notification.permission;
  if(permission==='default'){try{permission=await Notification.requestPermission();}catch{permission='denied';}}
  if(permission!=='granted'){alertNotify.checked=false;saveAlertPrefs({...p,notify:false});alertNote.textContent=`Notifications not allowed (${permission}); allow them in the browser's site settings`;return;}
  saveAlertPrefs({...p,notify:true});
});
// Station settings, not profile fields: they never mark the profile form unsaved.
for(const el of [alertSound,alertNotify])for(const type of ['input','change'])el?.addEventListener(type,event=>event.stopPropagation());
// A suspended audio context (autoplay rules) resumes with the operator's next action.
addEventListener('pointerdown',()=>{if(audio?.state==='suspended')audio.resume?.();},true);
addEventListener('station-message',event=>{const {message,current}=event.detail;if(current===socket&&message?.type==='alert.state')loadAlerts(false);});
addEventListener('station-ready',event=>{if(event.detail===alertSocket)return;alertSocket=event.detail;loadAlerts(true);});
// WstxStationProtocol::PushedStationState (#74): a new boot drops the previous boot's history at once.
addEventListener('station-boot',()=>{alertSeq++;alertView=null;alertSeen=null;showAlerts();});
if(settingsDrawer)new MutationObserver(()=>{if(!settingsDrawer.hidden)loadAlerts(false);}).observe(settingsDrawer,{attributes:true,attributeFilter:['hidden']});
if(socket?.readyState===WebSocket.OPEN&&connection.dataset.state==='connected'){alertSocket=socket;loadAlerts(true);}
// ---------------------------------------------------------------- #42 Pounce
// WstxStrategy::Pounce: the station runs it as an automation run with pounce <call>; this
// client only starts and stops it and shows it (QSO pane line, strategy element status).
const pouncing=call=>runActive()&&run.pounce?.call===call;
document.querySelector('#contact-state')?.insertAdjacentHTML('afterend','<p id="qso-pounce" class="ct-line op-pounce" role="status" hidden><span id="qso-pounce-text"></span> <button type="button" id="qso-pounce-stop" title="Stop waiting for this station">Stop pounce</button></p>');
const pounceLine=$('qso-pounce');
function showPounce(){
  if(!pounceLine)return;const p=runActive()?run.pounce:null;pounceLine.hidden=!p;if(!p)return;
  $('qso-pounce-text').textContent=`Pouncing on ${p.call} (${p.band}) · ${run.state==='waiting'?'waiting for CQ or 73':'in QSO'}`;
}
async function stopPounce(){if(!runActive()||!run.pounce)return;try{await automationCommand('stop',{run_id:run.id});}catch(error){statusNode.textContent=`Pounce stop refused · ${error.message}`;}}
$('qso-pounce-stop')?.addEventListener('click',stopPounce);
async function startPounce(call){
  const c=window.wstxContact?.snapshot(),mode=typeof live!=='undefined'?live?.job?.mode:null;
  if(!c||!['ft8','ft4'].includes(mode)){statusNode.textContent='Pounce needs FT8/FT4 receive';return;}
  // Asked once per page session.
  if(!pounceConfirmed){
    const ok=await window.wstxConfirm(`Pounce transmits without asking: it answers ${call} when it calls CQ or ends a QSO with 73 on this band. The Tx watchdog stops it when one message would be sent more than ${c.settings.tx_calls} times. HALT stops it; Esc aborts the current QSO.`,'Pounce');
    if(!ok)return;pounceConfirmed=true;
  }
  try{
    let a=await readAutomation();
    await automationCommand('configure',{expected_policy_revision:a.policy_revision,configuration:{modes:[mode],ranking:'first_seen',min_snr_db:null,allowed_calls:[],blocked_calls:[],max_contacts:1,max_unanswered_periods:5,completion_action:'stop',max_run_minutes:480,strategy:false,pounce:call}});
    a=await readAutomation();
    await automationCommand('start',{expected_policy_revision:a.policy_revision,expected_run_revision:a.run_revision,mode,safety_revision:window.wstxContact.snapshot()?.transmit?.safety_revision??null});
  }catch(error){statusNode.textContent=`Pounce not started · ${error.message}`;}
  finally{show();}
}
pounceItem.addEventListener('click',()=>{const call=pounceItem.dataset.call;if(!call)return;if(pouncing(call))stopPounce();else startPounce(call);});
// ---------------------------------------------------------------- #39 Most Wanted list
// WstxStrategy::MostWantedList in Settings > General: status with the source attribution, an upload
// the station validates, and Download now, one fetch on the operator's click. No automatic refresh.
if(typeof block==='function'&&document.querySelector('#settings-general'))block('settings-most-wanted','Most Wanted list',document.querySelector('#settings-general'),'<p class="op-actions"><span id="mw-status" class="op-muted" role="status">No list</span> <button type="button" id="mw-update" title="Fetches the list from clublog.org once, now">Update Most Wanted</button></p><p id="mw-result" class="op-muted" role="status"></p><p id="mw-attribution" class="op-muted"></p><p class="op-muted">A strategy calls the stations on this list first, by their rank, then the strongest; without a list the strongest first. It only changes when you click: Club Log states no terms for it.</p>');
function showMostWanted(){
  const status=$('mw-status');if(!status)return;const m=view?.most_wanted;
  status.textContent=m?`List from ${m.date} · ${m.entries} entries${m.unmapped?` · ${m.unmapped} not mapped to an entity`:''}`:view?.most_wanted_unreadable?'The stored list is unreadable; strategies call the strongest first':'No list; strategies call the strongest first';
  $('mw-attribution').textContent=view?.most_wanted_attribution??'';
}
$('mw-update')?.addEventListener('click',async()=>{
  if(!view)return;const result=$('mw-result'),button=$('mw-update');button.disabled=true;result.textContent='';
  try{
    const response=await stationFetch('/strategy/most-wanted/download',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:view.profile_id,boot_id:view.boot_id}),signal:AbortSignal.timeout(40000)});
    const data=await response.json().catch(()=>null);
    // A failure keeps the list and says why, in one line.
    if(!response.ok||data?.v!==1){result.textContent=`Update failed · ${data?.error?.reason??data?.error?.code??response.status}; the list stays as it was`;return;}
    if(data.boot_id!==profileData?.boot_id)return;
    view=data;verdicts=new Map();evaluatedKey='';show();evaluateShown();result.textContent='Updated';
  }catch(error){result.textContent=`Update failed · ${error.message}; the list stays as it was`;}
  finally{button.disabled=false;}
});
// ---------------------------------------------------------------- editor popup
const CONTINENTS=[['AF','Africa'],['AN','Antarctica'],['AS','Asia'],['EU','Europe'],['NA','North America'],['OC','Oceania'],['SA','South America']];
const GOALS=[['dxcc','DXCC'],['dxcc_band','DXCC per band'],['dxcc_slot','DXCC slot (band and mode)'],['waz','WAZ (CQ zones)'],['wpx','WPX (prefixes)'],['grid','Grids'],['new_call','New call'],['new_call_band','New call on band']];
// WstxStrategy::ValueCriterion in the model's order, with the editor's labels (StrategyEditor).
const CRITERIA=[['new_dxcc','New DXCC'],['new_dxcc_band','New DXCC on band'],['new_dxcc_slot','New DXCC on band and mode'],['new_grid','New grid'],['new_grid_band','New grid on band'],['new_call','New call'],['new_call_band','New call on band'],['most_wanted','Most Wanted rank'],['distance','Distance (farther first)'],['snr','SNR (stronger first)']];
const criterionLabel=v=>CRITERIA.find(c=>c[0]===v)?.[1]??v;
// WstxContest::ContestPrompt: choose the contest, its period (pre-filled from the schedule rule)
// and the operation; the station keeps receiving and HALT stays reachable.
const contestPrompt=document.createElement('dialog');contestPrompt.id='contest-prompt';contestPrompt.className='op-dialog op-strategy-editor';contestPrompt.setAttribute('aria-labelledby','contest-prompt-title');
contestPrompt.innerHTML=`<form method="dialog"><header class="se-head"><h2 id="contest-prompt-title">Contest strategy</h2><button type="button" class="op-halt-small" id="contest-prompt-halt" title="Halt Tx: emergency stop (Alt+H)">HALT</button></header>
<div class="se-options"><label>Contest<select id="cp-profile"></select></label><label>Start (UTC)<input id="cp-start" type="datetime-local" step="60"></label><label>End (UTC)<input id="cp-end" type="datetime-local" step="60"></label></div>
<p id="cp-schedule" class="op-muted"></p><p id="cp-activity" class="op-muted"></p>
<div class="se-options"><label>Strategy<select id="cp-strategy"></select></label></div>
<p class="op-muted">Band Activity follows the contest rules. It transmits only while Auto (beside CQ) is on; with Auto off you operate.</p>
<ul id="cp-notes" class="op-muted"></ul><p id="cp-result" class="op-muted" role="status"></p><menu><button value="cancel" type="submit">Cancel</button><button type="button" class="op-primary" id="cp-go">Start</button></menu></form>`;
document.querySelector('main').append(contestPrompt);
function contestFill(keep){
  const p=contests.find(x=>x.id===$('cp-profile').value)??contests[0];if(!p)return;
  const minute=t=>t?t.slice(0,16):'';
  // #97 WstxContest::ContestPrompt: the profile's contest built-in first (the default), then every
  // saved contest strategy of that profile; the active one when a selection of it is in force.
  const ofProfile=[...builtins(),...(config()?.strategies??[])].filter(s=>s.class==='contest'&&s.contest===p.id);
  $('cp-strategy').replaceChildren(...ofProfile.map(s=>{const o=document.createElement('option');o.value=s.name;o.textContent=s.name;return o;}));
  const active=config()?.active;if(keep&&ofProfile.some(s=>s.name===active))$('cp-strategy').value=active;
  $('cp-start').value=minute(keep?.start??p.period?.start);$('cp-end').value=minute(keep?.end??p.period?.end);
  $('cp-schedule').textContent=`${p.schedule}${p.period?.band?` · this round ${p.period.band}`:''}${p.period?'':' · enter the date'}`;
  const on=window.wstxContact?.snapshot()?.settings?.activity??'none';
  $('cp-activity').textContent=on===p.activity?'':`This contest uses the activity ${words_(p.activity)}; the station is on ${words_(on)} (Tx1-Tx6). A CQ with the contest's word is only answerable in its activity.`;
  $('cp-notes').replaceChildren(...[p.automation_text,...p.notes].map(n=>{const li=document.createElement('li');li.textContent=n;return li;}));
  $('cp-result').textContent='';
}
contestButton.addEventListener('click',async()=>{
  await loadContests();if(!contests.length){statusNode.textContent='Contest strategies unavailable';return;}
  const now=selection();
  $('cp-profile').replaceChildren(...contests.map(p=>{const o=document.createElement('option');o.value=p.id;o.textContent=p.name;return o;}));
  $('cp-profile').value=now?.profile??contests[0].id;contestFill(now);contestPrompt.showModal();
});
$('cp-profile').addEventListener('change',()=>contestFill(null));
$('contest-prompt-halt').addEventListener('click',()=>{contestPrompt.close('cancel');document.querySelector('#halt-tx')?.click();});
$('cp-go').addEventListener('click',async()=>{
  const c=config();if(!c)return;const start=$('cp-start').value,end=$('cp-end').value;
  if(!start||!end){$('cp-result').textContent='Enter the start and the end of the contest period';return;}
  const utc=t=>`${t.slice(0,16)}Z`;contestSummary=null;
  // Start only selects: whether it transmits is the Auto toggle's, which asks a forbidden clause's
  // warning (WstxStrategy::AutoToggle); the clause is on screen here.
  const profile=$('cp-profile').value,active=$('cp-strategy').value;
  const contest={profile,start:utc(start),end:utc(end)};
  const ok=await saveConfiguration({...c,active,contest},'Contest');
  if(ok)contestPrompt.close('ok');else $('cp-result').textContent=statusNode.textContent;
});
// WstxStrategy::Strategy: the browser's new strategy.
const newStrategy=name=>({name,class:'award',goals:['new_call'],needed:'not_worked',region:{kind:'all'},min_snr_db:null,value:['most_wanted'],callers_first:true,cq_when_no_target:false,repetitions:4,quiet_minutes:10,treat_73_as_cq:true,window:{kind:'all'}});
const editor=document.createElement('dialog');editor.id='strategy-editor';editor.className='op-dialog op-strategy-editor';editor.setAttribute('aria-labelledby','strategy-editor-title');
editor.innerHTML=`<form method="dialog"><header class="se-head"><h2 id="strategy-editor-title">Strategies</h2><button type="button" class="op-halt-small" id="strategy-editor-halt" title="Halt Tx: emergency stop (Alt+H)">HALT</button></header>
<div class="se-pick"><label>Edit<select id="se-which"></select></label><button type="button" id="se-new">New</button><button type="button" id="se-copy">Duplicate</button><button type="button" id="se-delete">Delete</button></div>
<div id="se-body"></div>
<section class="se-preview" aria-labelledby="se-preview-title"><h3 id="se-preview-title">Live preview · latest period</h3><p id="se-preview-status" class="op-muted" role="status"></p><div class="se-preview-wrap"><table><tbody id="se-preview"></tbody></table></div></section>
<p id="se-result" class="op-muted" role="status"></p><menu><button value="cancel" type="submit">Close</button><button type="button" class="op-primary" id="se-save">Save</button></menu></form>`;
document.querySelector('main').append(editor);
let drafts=[],current=0,previewTimer=null,previewSeq=0;
function editorOpen(){
  const c=config();drafts=structuredClone(c?.strategies??[]);
  // WstxStrategy::BuiltinStrategies: after the user's, read-only; Save never sends them.
  drafts.push(...structuredClone(builtins()));current=Math.max(0,drafts.findIndex(s=>s.name===c?.active));
  editor.querySelector('#strategy-editor-halt').disabled=document.querySelector('#halt-tx')?.disabled??true;
  $('se-result').textContent=c?`My continent ${view.my_continent??'unknown'} (Settings > General) · Save applies at once; selecting marks, Auto transmits`:'Saved strategies unreadable: Save replaces them';
  renderEditor();editor.showModal();
}
editButton.addEventListener('click',editorOpen);
// The modal popup makes the page inert, so it carries HALT itself (same action and state).
editor.querySelector('#strategy-editor-halt').addEventListener('click',()=>{editor.close('cancel');document.querySelector('#halt-tx')?.click();});
function option(value,label,selected){return `<option value="${value}"${selected?' selected':''}>${label}</option>`;}
const esc=t=>String(t).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function renderEditor(){
  $('se-which').innerHTML=drafts.map((s,i)=>option(i,esc(s.name)+(s.builtin?' (built-in)':''),i===current)).join('');
  $('se-delete').disabled=!drafts[current]||!!drafts[current].builtin;
  const s=drafts[current];if(!s){$('se-body').innerHTML='<p class="op-muted">No strategy. Choose New.</p>';preview();return;}
  const w=s.window,continents=s.region.continents??[],value=Array.isArray(s.value)?s.value:[],left=CRITERIA.filter(([v])=>!value.includes(v));
  $('se-body').innerHTML=`<label>Name<input id="se-name" maxlength="32" value="${esc(s.name)}" autocomplete="off"></label>
<h3 class="se-part">Filter</h3>
<fieldset class="se-goals"><legend>Goals (a station is called when at least one is needed)</legend>${GOALS.map(([v,l])=>`<label class="op-check"><input type="checkbox" data-goal="${v}"${s.goals.includes(v)?' checked':''}>${l}</label>`).join('')}</fieldset>
<div class="se-options"><label>Needed<select id="se-needed">${[['not_worked','Not worked'],['not_confirmed','Not worked or not confirmed']].map(([v,l])=>option(v,l,s.needed===v)).join('')}</select></label>
<label>Region<select id="se-region">${[['all','All'],['dx','DX only (other continents)'],['selected','Selected continents']].map(([v,l])=>option(v,l,s.region.kind===v)).join('')}</select></label>
${s.region.kind==='selected'?`<span class="se-continents" role="group" aria-label="Continents">${CONTINENTS.map(([v,l])=>`<label class="op-check" title="${l}"><input type="checkbox" data-continent="${v}"${continents.includes(v)?' checked':''}>${v}</label>`).join('')}</span>`:''}
<label>Minimum SNR (dB)<input id="se-snr" type="number" min="-50" max="49" step="1" value="${s.min_snr_db??''}" placeholder="none"></label>
<label class="op-check"><input type="checkbox" id="se-73"${s.treat_73_as_cq?' checked':''}>Treat 73 as CQ (answer a station that just ended a QSO; my Tx frequency is held)</label>
<label>Worked window<select id="se-window">${[['all','All time'],['today','Today (UTC)'],['from_to','From - to (UTC dates)']].map(([v,l])=>option(v,l,w.kind===v)).join('')}</select></label>
${w.kind==='from_to'?`<label>From<input id="se-from" type="date" min="1930-01-01" max="2099-12-31" value="${esc(w.from)}"></label><label>To<input id="se-to" type="date" min="1930-01-01" max="2099-12-31" value="${esc(w.to)}"></label>`:''}</div>
<h3 class="se-part">Value</h3>
<ol id="se-value" class="se-value" aria-label="Value order: the first decides, the next breaks a tie">${value.map((v,i)=>`<li data-criterion="${esc(v)}"><span>${esc(criterionLabel(v))}</span><button type="button" class="se-up" data-index="${i}" aria-label="Move ${esc(criterionLabel(v))} up"${i===0?' disabled':''}>&uarr;</button><button type="button" class="se-down" data-index="${i}" aria-label="Move ${esc(criterionLabel(v))} down"${i===value.length-1?' disabled':''}>&darr;</button><button type="button" class="se-remove" data-index="${i}" aria-label="Remove ${esc(criterionLabel(v))}">&times;</button></li>`).join('')}<li id="se-then" class="se-then op-muted">then SNR</li></ol>
<div class="se-options"><label>Add a criterion<select id="se-value-new">${left.map(([v,l])=>option(v,l,false)).join('')}</select></label><button type="button" id="se-value-add"${left.length?'':' disabled'}>Add</button>
<label class="op-check"><input type="checkbox" id="se-callers-first"${s.callers_first?' checked':''}>Callers of my call first</label></div>
<h3 class="se-part">Exit</h3>
<div class="se-options"><label>Repetitions before leaving<input id="se-repetitions" type="number" min="1" max="20" step="1" value="${s.repetitions}"></label>
<label>Quiet time (minutes)<input id="se-quiet" type="number" min="1" max="120" step="1" value="${s.quiet_minutes}"></label></div>
<label class="op-check" title="Call CQ after two periods with nothing to call; callers are answered"><input type="checkbox" id="se-cq"${s.cq_when_no_target?' checked':''}>CQ when no target</label>
<p class="op-muted">${s.builtin?'Built-in: read-only; Duplicate makes your own copy. ':''}Stations calling me are always answered, whatever these settings say. CQs directed elsewhere (another continent, CQ DX from my own, any other word) are never called.</p>`;
  if(s.builtin)for(const e of $('se-body').querySelectorAll('input,select,button'))e.disabled=true;
  preview();
}
function words(text,lower){return text.split(/[\s,]+/).map(w=>lower?w.toLowerCase():w.toUpperCase()).filter(Boolean);}
const todayUtc=()=>new Date().toISOString().slice(0,10);
editor.addEventListener('input',event=>{
  const s=drafts[current];if(!s)return;const t=event.target;
  if(t.id==='se-which'){current=Number(t.value);renderEditor();return;}
  if(s.builtin)return;
  if(t.dataset.goal){s.goals=GOALS.map(g=>g[0]).filter(g=>editor.querySelector(`[data-goal="${g}"]`).checked);}
  else if(t.dataset.continent){s.region={kind:'selected',continents:[...editor.querySelectorAll('[data-continent]')].filter(b=>b.checked).map(b=>b.dataset.continent)};}
  else if(t.id==='se-name')s.name=t.value;
  else if(t.id==='se-needed')s.needed=t.value;
  else if(t.id==='se-region'){s.region=t.value==='selected'?{kind:'selected',continents:[view?.my_continent==='EU'?'NA':'EU']}:{kind:t.value};renderEditor();return;}
  else if(t.id==='se-snr')s.min_snr_db=t.value===''?null:Number(t.value);
  else if(t.id==='se-value-new')return;
  else if(t.id==='se-callers-first')s.callers_first=t.checked;
  else if(t.id==='se-repetitions')s.repetitions=Number(t.value);
  else if(t.id==='se-quiet')s.quiet_minutes=Number(t.value);
  else if(t.id==='se-cq')s.cq_when_no_target=t.checked;
  else if(t.id==='se-73')s.treat_73_as_cq=t.checked;
  else if(t.id==='se-window'){s.window=t.value==='from_to'?{kind:'from_to',from:todayUtc(),to:todayUtc()}:{kind:t.value};renderEditor();return;}
  else if(t.id==='se-from')s.window.from=t.value;
  else if(t.id==='se-to')s.window.to=t.value;
  schedulePreview();
});
editor.addEventListener('click',event=>{
  // WstxStrategy::ValueOrder in the editor: add, remove, up and down; SNR stays the hidden last.
  const v=event.target.closest('#se-value-add,.se-up,.se-down,.se-remove'),d=drafts[current];
  if(v&&d&&!d.builtin&&!v.disabled){
    const list=[...(d.value??[])],i=Number(v.dataset.index);
    if(v.id==='se-value-add'){const add=$('se-value-new').value;if(add&&!list.includes(add)&&list.length<10)list.push(add);}
    else if(v.classList.contains('se-remove'))list.splice(i,1);
    else{const j=v.classList.contains('se-up')?i-1:i+1;if(j>=0&&j<list.length)[list[i],list[j]]=[list[j],list[i]];}
    d.value=list;renderEditor();schedulePreview();return;
  }
  const b=event.target.closest('#se-new,#se-copy,#se-delete');if(!b)return;const s=drafts[current];
  if(b.id==='se-new'){let n=1;while(drafts.some(d=>d.name.toLowerCase()===`strategy ${n}`))n++;addDraft(newStrategy(`Strategy ${n}`));}
  else if(b.id==='se-copy'&&s){const {builtin,...copy}=structuredClone(s);copy.name=`${s.name} copy`.slice(0,32);addDraft(copy);}
  else if(b.id==='se-delete'&&s&&!s.builtin){drafts.splice(current,1);current=Math.max(0,current-1);}
  renderEditor();
});
// The user's strategies come first, the built-ins after them.
function addDraft(draft){const at=drafts.filter(d=>!d.builtin).length;drafts.splice(at,0,draft);current=at;}
function schedulePreview(){clearTimeout(previewTimer);previewTimer=setTimeout(preview,400);}
async function preview(){
  const body=$('se-preview'),status=$('se-preview-status'),s=drafts[current],id=identity();
  const latest=typeof resultView!=='undefined'&&resultView&&id?resultView:null;
  if(!s||!latest||!view){body.replaceChildren();status.textContent=!latest?'No decoded period yet: the preview follows the latest period.':'';return;}
  const seq=++previewSeq,[,,source_id,job_id,generation]=id.split('/');
  try{
    const response=await stationFetch('/strategy/evaluate',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:view.profile_id,boot_id:view.boot_id,source_id,job_id,generation:Number(generation),first_sequence:latest.first_sequence,next_sequence:latest.next_sequence,strategy:(({builtin,...draft})=>draft)(s),explain:true}),signal:AbortSignal.timeout(10000)});
    const data=await response.json().catch(()=>null);if(seq!==previewSeq)return;
    if(!response.ok||data?.v!==1){status.textContent=`Preview unavailable · ${data?.error?.code??response.status}${data?.error?.field?` (${data.error.field})`:''}`;return;}
    const text=new Map(resultRows.map(r=>[r.sequence,r.text]));
    body.replaceChildren(...data.verdicts.map(v=>{const tr=document.createElement('tr');tr.className=v.rank!==null?'ba-strategy':v.grey?'ba-grey':'';
      for(const t of [v.rank!==null?`#${v.rank+1}`:v.grey?'—':'',text.get(v.sequence)??`#${v.sequence}`,v.why]){const td=document.createElement('td');td.textContent=t;tr.append(td);}return tr;}));
    status.textContent=`${data.verdicts.filter(v=>v.rank!==null).length} of ${data.verdicts.length} decodes would be called · ${periodLabel(latest.period_start_utc,live.job.mode)} UTC`;
  }catch(error){if(seq===previewSeq)status.textContent=`Preview unavailable · ${error.message}`;}
}
$('se-save').addEventListener('click',async()=>{
  const c=config()??{continent:null,active:null,ignore_calls:[],session_ignore_minutes:30};
  // Save never selects. A deleted active one is None.
  const mine=drafts.filter(d=>!d.builtin),names=[...mine,...builtins()].map(d=>d.name);
  const ok=await saveConfiguration({...c,continent:c.continent??null,active:names.includes(c.active)?c.active:null,strategies:mine},'Strategies');
  $('se-result').textContent=ok?`Saved · revision ${view.revision} · applies now`:statusNode.textContent;
  if(ok){const name=drafts[current]?.name;drafts=[...structuredClone(config().strategies),...structuredClone(builtins())];current=Math.max(0,drafts.findIndex(d=>d.name===name));renderEditor();}
});
// Read once per socket (a status refresh on the same socket reads nothing: Thin link).
let strategySocket=null;
addEventListener('station-ready',event=>{if(event.detail===strategySocket&&(view||strategyMissing))return;strategySocket=event.detail;contestsAsked=false;loadStrategy();});
if(socket?.readyState===WebSocket.OPEN&&connection.dataset.state==='connected'){strategySocket=socket;loadStrategy();}
show();
})();
