'use strict';
const main = document.querySelector('main'), controls = document.createElement('div');
controls.id = 'controls';
while (main.firstChild) controls.append(main.firstChild);
main.classList.add('op-app');
const signal = document.createElement('section'); signal.id = 'signal'; signal.className='op-signal'; signal.setAttribute('aria-label','Recorded spectrum and waterfall');
signal.innerHTML = '<div class="op-signal-heading"></div><h2 id="signal-status" role="status">Waiting for station snapshot</h2><p id="signal-meta"></p><canvas id="spectrum" aria-label="Spectrum in calibrated dBFS"></canvas><div id="frequency-ruler" aria-label="Fixed frequency span 0 to 3000 Hz"></div><div id="waterfall-wrap"><div id="time-ruler"></div><canvas id="waterfall" tabindex="0" aria-label="Waterfall in source seconds; arrow keys select native bins and rows"></canvas></div><div id="level-legend"></div><canvas id="level-bar" aria-label="Waterfall color scale from navy to red"></canvas>';
const splitter = document.createElement('div'); splitter.id = 'splitter'; splitter.className='op-splitter'; splitter.tabIndex = 0; splitter.innerHTML='<span></span>';
for (const [key,value] of Object.entries({role:'separator','aria-orientation':'horizontal','aria-label':'Resize spectrum and controls','aria-controls':'signal controls'})) splitter.setAttribute(key,value);
main.append(signal,splitter,controls);
// WstxOperatingLayout::OperatingScreen (#37): top bar, waterfall + RxTxStrip, Band Activity, QsoPane.
const stationBar=controls.querySelector('header');stationBar.id='station-bar';stationBar.className='op-header op-topbar';
const stationConnectionNode=document.querySelector('#connection');
const tuning=document.createElement('div');tuning.id='radio-toolbar';tuning.className='op-tuning';tuning.setAttribute('role','group');tuning.setAttribute('aria-label','Radio operation');
tuning.innerHTML='<div class="op-dial"><span class="op-dial-label">DIAL MHz</span><input id="op-dial" disabled placeholder="Unknown" aria-label="Dial frequency unavailable" title="CAT readback unavailable"></div><div class="op-period"><span>Receive period</span><div class="op-period-track"></div><small>Timing unavailable</small></div>';
const chips=document.createElement('div');chips.id='exception-chips';chips.className='op-chips';chips.setAttribute('role','group');chips.setAttribute('aria-label','Station exceptions');
const headerActions=document.createElement('div');headerActions.className='op-header-actions';
headerActions.innerHTML='<button type="button" data-region="logbook" id="open-logbook" title="Logbook">&#9776; Logbook</button><button type="button" data-region="server-settings" id="open-server-settings" title="Settings (F2)">&#9881; Settings</button><button type="button" data-region="help" aria-label="Help" title="Keyboard and mouse overview (?)">?</button>';
const halt=document.createElement('button');halt.id='halt-tx';halt.className='op-halt';halt.disabled=true;halt.innerHTML='<span class="op-square" aria-hidden="true"></span>HALT';halt.setAttribute('aria-label','Halt Tx');halt.title='Halt Tx (Esc, Alt+H)';halt.setAttribute('aria-describedby','transmit-unavailable');headerActions.append(halt);
stationBar.replaceChildren(tuning,chips,stationConnectionNode,headerActions);
const strip=document.createElement('section');strip.id='rxtx-strip';strip.className='op-strip';strip.setAttribute('aria-label','Rx and Tx audio frequencies');
const stepper=(key,label,min,max)=>`<label class="op-strip-field">${label}<input id="contact-${key}" type="number" min="${min}" max="${max}" step="1" disabled inputmode="numeric" aria-label="${label} audio frequency, Hz"><span>Hz</span></label><button type="button" data-strip-step="${key}:-1" aria-label="${label} down 1 Hz (Shift: 10 Hz)" disabled>&minus;</button><button type="button" data-strip-step="${key}:1" aria-label="${label} up 1 Hz (Shift: 10 Hz)" disabled>+</button>`;
strip.innerHTML=stepper('rx','Rx',0,3000)+stepper('tx','Tx',200,2950)+'<label class="op-check"><input type="checkbox" id="contact-hold" disabled>Hold Tx</label><button type="button" id="strip-tx-from-rx" disabled>Tx=Rx</button><button type="button" id="strip-rx-from-tx" disabled>Rx=Tx</button>';
const workspace=document.createElement('div');workspace.id='operating-workspace';
// ActivityOrdering: the focusable header cell is the sort control.
const sortHeader=(field,label)=>`<th scope="col" data-sort="${field}" aria-sort="none" tabindex="0" class="op-sort" title="Sort by ${label}">${label}</th>`;
const qsoButton=(id,label,title,extra='')=>`<button type="button" id="${id}" disabled title="${title}"${extra}>${label}</button>`;
workspace.innerHTML=`<div class="operating-grid op-desk">
<section id="band-activity" class="message-pane op-card op-activity" aria-labelledby="activity-heading"><div id="strategy-element" class="op-strategy-bar" role="group" aria-label="Strategy"><span class="op-strategy-label">Strategy</span><select id="strategy-name" disabled aria-label="Strategy name" title="The strategy engine is not available yet"><option>None</option></select><button type="button" id="strategy-edit" disabled aria-label="Edit strategy" title="The strategy engine is not available yet">&#9998;</button><span class="op-segmented" role="group" aria-label="Strategy mode"><button type="button" id="strategy-highlight" disabled aria-pressed="false" title="The strategy engine is not available yet">Highlight</button><button type="button" id="strategy-auto" disabled aria-pressed="false" title="The strategy engine is not available yet">Auto</button></span><span id="station-automation" class="op-automation" role="status">Automation idle</span></div><header><div><h3 id="activity-heading">Band Activity <span class="op-count">0</span></h3><span class="op-muted">Latest decode period</span></div></header><div class="op-table-wrap"><table role="table" aria-label="Decoded messages"><thead role="rowgroup"><tr role="row"><th scope="col">UTC</th>${sortHeader('signal','dB')}${sortHeader('dt','DT')}${sortHeader('frequency','Freq')}${sortHeader('message','Message')}<th scope="col">DXCC</th><th scope="col">Dist</th></tr></thead><tbody role="rowgroup"><tr><td colspan="7" class="empty-messages"><strong>Decoder unavailable</strong><span>No decoded messages are available from this server.</span></td></tr></tbody></table></div></section>
<section id="rx-focus" class="message-pane op-card op-qso" aria-labelledby="focus-heading"><header class="op-qso-head"><div class="op-contact-identity"><div><h3 id="focus-heading">QSO</h3><strong>No station selected</strong><span>Select a decoded station or enter a DX call.</span></div></div><span id="qso-crowd" class="op-qso-badge" hidden></span><span class="op-contact-badge">Unavailable</span></header>
<div class="op-contact-body">
<p id="contact-state" class="ct-state" role="status">Contact state unavailable</p>
<section id="rx-pane" class="ct-pane" aria-labelledby="rx-pane-heading"><header><h4 id="rx-pane-heading">Dialogue <span id="rx-pane-unread"></span></h4><button type="button" id="rx-pane-resume" hidden>Resume following</button></header><div class="ct-pane-wrap" tabindex="0" aria-label="QSO dialogue and stations near my Rx frequency"><table aria-label="QSO dialogue"><tbody id="rx-pane-rows"></tbody></table></div></section>
<div class="op-qso-next"><span class="op-eyebrow">NEXT &#9656;</span><strong id="contact-next">None</strong><div class="op-qso-progress" aria-hidden="true"><i id="qso-progress"></i></div><span id="qso-countdown" class="op-muted"></span><span class="op-eyebrow">LAST</span><strong id="contact-last">None</strong></div>
<div class="op-qso-buttons" role="group" aria-label="QSO commands">${qsoButton('qso-cq','CQ','Call CQ: transmits from the next period')}${qsoButton('qso-reply','Reply','Answer the selected station: transmits from the next period')}${qsoButton('qso-rr73','RR73','Send RR73 next')}${qsoButton('qso-73','73','Send 73 next')}${qsoButton('contact-tune','Tune','Tune (Alt+T)',' aria-pressed="false"')}<button type="button" id="qso-halt" class="op-halt-small" disabled title="Halt Tx (Esc, Alt+H)">HALT</button>${qsoButton('contact-log','Log QSO','Log QSO (Alt+Q)',' aria-describedby="contact-unavailable"')}</div>
<p id="transmit-unavailable" class="op-unavailable">Transmission unavailable: this server does not offer transmit control.</p><p id="contact-unavailable" class="op-unavailable">Log QSO needs a contact with a DX call.</p><p id="contact-result" class="op-muted" role="status"></p>
</div></section></div>`;
controls.prepend(workspace);
const secondaryRoot=document.createElement('div');secondaryRoot.id='workspace-secondary';secondaryRoot.hidden=true;controls.append(secondaryRoot);
const secondaryRegions=new Map();
function region(id,title,intro){const section=document.createElement('section');section.id='region-'+id;section.className='op-secondary';section.hidden=true;section.setAttribute('aria-labelledby','region-title-'+id);section.innerHTML=`<header><div><span class="op-eyebrow">WSTX / ${title.toUpperCase()}</span><h2 id="region-title-${id}">${title}</h2></div><button type="button" data-region="operate" class="return-operate">&#8592; Back to operation</button></header><div class="op-secondary-body"><p class="op-muted">${intro}</p></div>`;secondaryRoot.append(section);secondaryRegions.set(id,section);return section.querySelector('.op-secondary-body');}
const logRegion=region('logbook','Logbook','Contact history and ADIF operations are unavailable until this station offers contact logging.');
logRegion.insertAdjacentHTML('beforeend','<p>No server-confirmed contacts are available.</p><button type="button" disabled>Import ADIF</button> <button type="button" disabled>Export ADIF</button>');
const helpRegion=region('help','Keyboard and mouse','WSJT-X keys where the function exists. Letter keys and ? are inactive while a text field has focus; Esc and Alt+H always halt.');
helpRegion.insertAdjacentHTML('beforeend','<dl class="op-keys" id="help-keys"><div><dt>Esc / Alt+H / HALT</dt><dd>Halt Tx now (Esc also cancels the contact). Panels stay open.</dd></div><div><dt>F1 / F3 / F5 / ?</dt><dd>This overview</dd></div></dl><p class="op-muted">The interface contains no generated callsigns or simulated radio state.</p>');
function secondary(id,title,element,parent){const detail=document.createElement('details');detail.id=id;const summary=document.createElement('summary');summary.textContent=title;detail.append(summary,element);parent.append(detail);return detail;}
function block(id,title,parent,html=''){const section=document.createElement('section');section.id=id;section.className='op-section';section.setAttribute('aria-labelledby',id+'-title');section.innerHTML=`<h3 id="${id}-title">${title}</h3>${html}`;parent.append(section);return section;}
// ---------------------------------------------------------------- Settings drawer
// WstxOperatingLayout::SettingsDrawer.
const drawer=document.createElement('aside');drawer.id='settings-drawer';drawer.className='op-secondary op-drawer';drawer.hidden=true;drawer.setAttribute('aria-labelledby','drawer-title');
const drawerSections=[['general','General'],['radio','Radio &#10227;'],['logging','Logging &amp; Reporting'],['expert','Expert']];
drawer.innerHTML=`<header><div><span class="op-eyebrow">WSTX / <span id="operating-station">Waiting for station</span></span><h2 id="drawer-title">Settings</h2></div><button type="button" data-region="operate" class="return-operate" aria-label="Close settings">&#10005; Close</button></header><nav class="op-drawer-tabs" aria-label="Settings sections">${drawerSections.map(([key,label],i)=>`<button type="button" id="tab-${key}" data-drawer-tab="${key}" aria-controls="settings-${key}"${i?'':' aria-current="true"'}>${label}</button>`).join('')}</nav><div class="op-drawer-body">${drawerSections.map(([key,label])=>`<section id="settings-${key}" aria-labelledby="settings-${key}-heading" class="op-drawer-section"><h2 id="settings-${key}-heading" class="op-drawer-heading">${label}</h2></section>`).join('')}</div>`;
main.append(drawer);
const [generalSection,radioSection,loggingSection,expertSection]=drawerSections.map(([key])=>drawer.querySelector('#settings-'+key));
function markTab(key){for(const [k] of drawerSections){const tab=drawer.querySelector('#tab-'+k);if(k===key)tab.setAttribute('aria-current','true');else tab.removeAttribute('aria-current');}}
function drawerTab(key){markTab(key);const body=drawer.querySelector('.op-drawer-body'),section=drawer.querySelector('#settings-'+key);body.scrollTop=section.offsetTop-body.offsetTop;}
drawer.querySelector('.op-drawer-tabs').addEventListener('click',event=>{const tab=event.target.closest('[data-drawer-tab]');if(tab){drawerTab(tab.dataset.drawerTab);tab.focus();}});
drawer.querySelector('.op-drawer-body').addEventListener('scroll',event=>{const body=event.currentTarget;let current=drawerSections[0][0];for(const [k] of drawerSections)if(drawer.querySelector('#settings-'+k).offsetTop-body.offsetTop<=body.scrollTop+8)current=k;markTab(current);},{passive:true});
drawer.querySelector('.op-drawer-tabs').addEventListener('keydown',event=>{if(!['ArrowLeft','ArrowRight'].includes(event.key))return;const keys=drawerSections.map(([k])=>k),current=keys.indexOf((event.target.closest('[data-drawer-tab]')??drawer.querySelector('[aria-current=true]')).dataset.drawerTab),next=keys[(current+(event.key==='ArrowRight'?1:keys.length-1))%keys.length];drawerTab(next);drawer.querySelector('#tab-'+next).focus();});
function showSection(id){
  const target=document.getElementById(id);if(!target)return;
  const section=target.closest('.op-drawer-section');if(section)markTab(section.id.slice(9));
  for(let node=target;node;node=node.parentElement)if(node.tagName==='DETAILS')node.open=true;
  target.scrollIntoView({block:'nearest'});
  (target.matches('details')?target.querySelector('summary'):target.querySelector('input:not([type=hidden]):not(:disabled),select:not(:disabled),button:not(:disabled),summary')??target).focus();
}
const serverForm=document.querySelector('#settings');
const stationFields=document.createElement('fieldset');stationFields.id='server-fields-general';stationFields.className='op-server-fieldset';stationFields.innerHTML='<legend>Station &#10227;</legend>';
for(const id of ['display-name','callsign','locator']){const input=document.getElementById(id);input.setAttribute('form','settings');stationFields.append(input.closest('label'));}
stationFields.insertAdjacentHTML('beforeend','<label>Continent<select id="station-continent"><option value="">From locator</option><option value="AF">Africa</option><option value="AN">Antarctica</option><option value="AS">Asia</option><option value="EU">Europe</option><option value="NA">North America</option><option value="OC">Oceania</option><option value="SA">South America</option></select><small id="continent-derived"></small></label><p class="op-apply-row"><button type="submit" form="settings" class="op-apply">Apply &#10227;</button></p><p id="general-apply-result" class="op-muted" role="status"></p>');
// Station fields sit outside the form element; their edits still mark it edited.
for(const type of ['input','change'])stationFields.addEventListener(type,event=>{if(event.target.form===serverForm&&event.target.id!=='station-continent')serverForm.dispatchEvent(new Event(type));});
generalSection.append(stationFields);
block('settings-clock','Clock',generalSection,'<p id="clock-setting">Station clock: system UTC. Measured offset unavailable.</p>');
const displaySettings=block('settings-display','Display',generalSection,'<label>Theme<select id="theme-choice"><option value="dark">Dark</option><option value="day">Day</option><option value="night">Night (dim red)</option></select></label><label>Switch<select id="theme-switch"><option value="manual">Manually</option><option value="time">By time</option><option value="sun">By sunrise and sunset at my locator</option></select></label><span id="theme-times"><label>Day from<input id="theme-day-start" type="time" value="07:00"></label><label>Night from<input id="theme-night-start" type="time" value="20:00"></label></span><p id="theme-status" class="op-muted"></p><p class="op-muted">Display settings affect this browser only and apply at once.</p>');
const browserSettings=block('settings-browsers','Access &amp; grants',generalSection,'<p class="op-muted">This browser holds its own station authorization. Logging out or forgetting the credential needs the station access token to authorize again.</p>');
browserSettings.append(document.querySelector('#authorization-actions'));
// Forget credential is the action of its exception: shown beside the chips while offered.
chips.after(document.querySelector('#forget'));
const profilePanel=document.querySelector('#profile-panel'),profileMetadata=profilePanel.querySelector('dl');
for(const [name,legendText,ids] of [['radio','CAT &#10227;',['control-mode','control-endpoint','ptt-mode']],['audio','Audio &#10227;',['audio-input','audio-output']]]){
  const group=document.createElement('fieldset');group.id='server-fields-'+name;group.className='op-server-fieldset';group.innerHTML=`<legend>${legendText}</legend>`;
  if(name==='radio')group.append(serverForm.querySelector('select:not([id])').closest('label'));
  for(const id of ids)group.append(document.getElementById(id).closest('label'));
  serverForm.insertBefore(group,serverForm.querySelector('p'));
}
document.querySelector('#settings-save').textContent='Apply ⟳';
radioSection.append(profilePanel);
const catSettings=block('settings-cat','CAT receive-only confirmation',radioSection);
block('settings-audio','Audio input',radioSection,'<div class="op-input-meter"><span>Rx level <strong>Unknown</strong></span><div></div></div><p class="op-muted">Listing the inputs reads the device names only; it never opens audio.</p><button type="button" id="audio-enumerate">List audio inputs</button><output id="audio-inputs"></output>');
const connectionPanel=document.createElement('div');connectionPanel.append(controls.querySelector('section[aria-label="Station status"]'),profileMetadata);
const capabilities=document.createElement('dl');capabilities.id='operating-capabilities';capabilities.innerHTML='<div><dt>Audio</dt><dd>Unavailable &#183; capture not offered</dd></div><div><dt>CAT</dt><dd>Unavailable &#183; radio not configured</dd></div><div><dt>Decoder</dt><dd>Unavailable &#183; results not offered</dd></div><div><dt>Transmission</dt><dd>Unavailable &#183; control not offered</dd></div>';connectionPanel.append(capabilities);
const receivePanel=document.createElement('div');receivePanel.id='receive-diagnostics';
receivePanel.append(signal.querySelector('#signal-status'));
receivePanel.insertAdjacentHTML('beforeend','<p id="receive-status" role="status">Live receive unavailable until station snapshot</p><p id="receive-generation">Receive generation unknown</p><p id="clock-detail">Clock detail unavailable until station snapshot</p><p><button type="button" id="receive-toggle" disabled>Start receive</button></p>');
secondary('receive-details','Receive, CAT and timing',receivePanel,expertSection).open=true;
secondary('connection-details','Connection details',connectionPanel,expertSection).open=true;
new MutationObserver(()=>{document.querySelector('#general-apply-result').textContent=document.querySelector('#settings-result').textContent;}).observe(document.querySelector('#settings-result'),{childList:true,characterData:true,subtree:true});
connectionPanel.querySelector('#refresh').textContent='Refresh status';
const updateIdentity=()=>{document.querySelector('#operating-station').textContent=profileData?.settings.display_name??'Waiting for station';};
new MutationObserver(updateIdentity).observe(document.querySelector('#profile-name'),{childList:true,subtree:true,characterData:true});updateIdentity();
const panel = document.createElement('section'); panel.id = 'recording-controls'; panel.setAttribute('aria-label','Recording controls');
panel.innerHTML = '<label>Import mono 12 kHz PCM16 WAV (up to 120 seconds)<input id="recording-file" type="file" accept=".wav,audio/wav"></label><button id="recording-import">Import recording</button><button id="recording-replay" disabled>Replay spectrum</button><button id="recording-cancel" disabled>Cancel operation</button><p>One processing worker per station &#183; no speaker playback</p><p id="recording-progress" role="status"></p>';
const localPreferences=document.createElement('div');localPreferences.id='local-display-preferences';
localPreferences.innerHTML='<label>Waterfall link <select id="display-profile"><option value="detail">Detailed (fast link, up to 10 KiB/s per viewer)</option><option value="thin">Thin (32 kbit/s link)</option><option value="off">Off</option></select></label><div id="display-levels"><label>Black level (dBFS)<input id="display-black" type="number" min="-120" max="-30" step="1" value="-120"></label><label>Range (dB)<input id="display-range" type="number" min="10" max="80" step="1" value="30"></label><label><input id="display-auto" type="checkbox" checked> Auto black</label><output id="bin-readout" aria-live="polite">Select a bin with pointer or arrow keys</output></div>';
panel.append(document.querySelector('#signal-meta'));
displaySettings.append(localPreferences);
secondary('recorded-input','Recordings and replay',panel,expertSection).open=true;
expertSection.insertAdjacentHTML('afterbegin','<p class="op-muted">Diagnostics that are not needed while operating.</p>');
const sliders=document.createElement('div');sliders.id='presentation-sliders';sliders.className='op-display-controls';
sliders.innerHTML='<label>Sensitivity <input id="display-sensitivity" type="range" min="-30" max="30" step="1" value="0" aria-label="Waterfall sensitivity"><output id="sensitivity-value">+0 dB</output></label>'+'<label title="Scroll speed in CSS pixels per source second. Replay and received rows per second do not change.">Speed <input id="display-speed" type="range" min="0.5" max="8" step="0.5" value="2" aria-label="Waterfall speed, Slow to Fast"><output id="speed-value">20 px/s</output></label>';
signal.querySelector('.op-signal-heading').append(sliders);
for(const child of [...controls.children]){if(child.matches('h1,.intro,footer'))child.remove();}
// WstxOperatingLayout::UnauthorizedView.
const loginView=document.createElement('section');loginView.id='login-view';loginView.className='op-login';loginView.setAttribute('aria-label','Station authorization');loginView.hidden=true;
loginView.innerHTML='<span class="op-eyebrow">WSTX / REMOTE STATION</span><h1>Authorize this browser</h1><p class="op-muted">Enter the station access token. The station is shown once this browser is authorized.</p>';
loginView.append(login);
const confirmDialog=document.createElement('dialog');confirmDialog.id='op-confirm';confirmDialog.className='op-dialog';confirmDialog.innerHTML='<form method="dialog"><p id="op-confirm-text"></p><menu><button value="cancel" type="submit">Cancel</button><button value="ok" type="submit" class="op-primary" id="op-confirm-ok">Continue</button></menu></form>';
function confirmAction(text,okLabel='Continue'){
  confirmDialog.querySelector('#op-confirm-text').textContent=text;confirmDialog.querySelector('#op-confirm-ok').textContent=okLabel;
  return new Promise(resolve=>{confirmDialog.returnValue='';confirmDialog.addEventListener('close',()=>resolve(confirmDialog.returnValue==='ok'),{once:true});confirmDialog.showModal();confirmDialog.querySelector('#op-confirm-ok').focus();});
}
main.append(stationBar,signal,strip,splitter,controls,drawer,loginView,confirmDialog);
const authorizationView=()=>{const required=!login.hidden;main.dataset.auth=required?'required':'granted';loginView.hidden=!required;};
new MutationObserver(authorizationView).observe(login,{attributes:true,attributeFilter:['hidden']});authorizationView();
let currentRegion='operate',returnFocus=null;
const drawerAlias={'server-settings':null,connection:'connection-details',recordings:'recorded-input','client-preferences':'settings-display',strategies:'settings-automation',expert:'receive-details'};
function drawerOpen(){return !drawer.hidden;}
function closeDrawer(){if(drawer.hidden)return;drawer.hidden=true;main.dataset.drawer='closed';if(returnFocus?.isConnected&&currentRegion==='operate'){returnFocus.focus();returnFocus=null;}}
function showRegion(name,opener,anchor=null){
  if(name in drawerAlias||anchor){
    if(opener)returnFocus=opener;
    drawer.hidden=false;main.dataset.drawer='open';
    const section=anchor??drawerAlias[name];
    if(section)showSection(section);else drawer.querySelector('[aria-current=true]').focus();
    return;
  }
  if(name!=='operate'&&!secondaryRegions.has(name))return;
  if(name==='operate'&&drawerOpen()){closeDrawer();if(currentRegion==='operate')return;}
  currentRegion=name;main.dataset.region=name;
  if(name!=='operate'&&opener)returnFocus=opener;
  workspace.hidden=name!=='operate';secondaryRoot.hidden=name==='operate';
  for(const [id,node]of secondaryRegions)node.hidden=id!==name;
  for(const node of [signal,splitter,strip])node.hidden=name!=='operate';
  if(name==='operate') {split(upper);if(returnFocus?.isConnected){returnFocus.focus();returnFocus=null;}}
  else secondaryRegions.get(name).querySelector('.return-operate').focus();
}
main.addEventListener('click',event=>{const button=event.target.closest('button[data-region]');if(button&&!button.disabled)showRegion(button.dataset.region,button);});
document.addEventListener('pointerdown',event=>{if(drawer.hidden||event.target.closest?.('#settings-drawer,#station-bar,#signal,#rxtx-strip,#splitter,dialog'))return;closeDrawer();},true);
// WstxOperatingLayout::KeyboardShortcuts (Esc/Alt+H halt is handled at the end of this file).
const typing=target=>!!target?.closest?.('input:not([type=checkbox]):not([type=radio]):not([type=range]):not([type=button]),textarea,select,[contenteditable=true]');
addEventListener('keydown',event=>{
  if(event.defaultPrevented)return;
  if(event.key==='F2'){event.preventDefault();showRegion('server-settings',document.querySelector('#open-server-settings'));return;}
  if(['F1','F3','F5'].includes(event.key)||(event.key==='?'&&!typing(event.target)&&!event.ctrlKey&&!event.altKey)){event.preventDefault();showRegion('help',document.querySelector('#station-bar [data-region=help]'));return;}
  if(event.altKey&&!event.ctrlKey&&!event.metaKey&&event.key.toLowerCase()==='m'){event.preventDefault();receiveToggle();}
});
const profileSelect=document.querySelector('#display-profile');
const defaultDisplayProfile=()=>'detail';
const displayPreferenceKey=id=>`wstx.display-profile.v1:${id}`;
let restoredDisplayProfile;
function displayPreferenceId(){const id=profileData?.profile_id;return typeof id==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id)?id:null;}
function restoreDisplayPreference(){
  const id=displayPreferenceId();if(id===restoredDisplayProfile)return;restoredDisplayProfile=id;
  let saved=null;if(id)try{saved=localStorage.getItem(displayPreferenceKey(id));}catch{}
  profileSelect.value=['detail','thin','off'].includes(saved)?saved:defaultDisplayProfile();
}
restoreDisplayPreference();
let displayBlack=-120, displayRange=30, autoBlack=true, estimateFrozen=false, selectedBin=0, selectedRow=0, pointerColumn=null, pointerTime=null, sensitivity=0, speed=2, fallbackText='', detailRequest;
// The waterfall speed is a per-browser view preference (WstxOperatingLayout::OperatingScreen).
try{const saved=Number(localStorage.getItem('wstx.waterfall-speed.v1'));if(saved>=.5&&saved<=8&&Number.isInteger(2*saved))speed=saved;}catch{}
const palette=[[0,[0,0,12]],[.15,[0,0,80]],[.35,[0,80,220]],[.50,[0,220,240]],[.65,[30,230,80]],[.80,[255,235,0]],[.95,[255,40,0]],[1,[255,0,0]]];
function paletteRGB(t){
  t=Math.max(0,Math.min(1,t));
  const i=Math.max(1,palette.findIndex(([p])=>p>=t)),[lo,a]=palette[i-1],[hi,b]=palette[i];
  return a.map((v,k)=>Math.floor(v+(b[k]-v)*(t-lo)/(hi-lo)+.5));
}
function effectiveBlack(){return Math.max(-120,Math.min(-displayRange,displayBlack-sensitivity));}
function color(q){return `rgb(${paletteRGB((q-120-effectiveBlack())/displayRange).join(' ')})`;}
function updateSliders(){
  document.querySelector('#display-sensitivity').value=sensitivity;document.querySelector('#sensitivity-value').textContent=`${sensitivity>=0?'+':''}${sensitivity} dB`;
  document.querySelector('#display-speed').value=speed;document.querySelector('#speed-value').textContent=`${10*speed} px/s`;
}
for(const id of ['display-sensitivity','display-speed'])document.querySelector(`#${id}`).addEventListener('input',event=>{
  const value=Number(event.target.value);if(!Number.isFinite(value))return;
  if(id==='display-sensitivity')sensitivity=Math.max(-30,Math.min(30,Math.floor(value+.5)));else{speed=Math.max(.5,Math.min(8,Math.floor(2*value+.5)/2));try{localStorage.setItem('wstx.waterfall-speed.v1',String(speed));}catch{}}
  selectedRow=Math.max(0,Math.min(visibleCount()-1,selectedRow));pointerTime=null;updateSliders();paint();
});

function resetLevels(){displayBlack=-120;displayRange=30;autoBlack=true;estimateFrozen=false;selectedBin=0;selectedRow=0;pointerColumn=null;pointerTime=null;updateLevels();}
function updateLevels(){
  document.querySelector('#display-black').value=displayBlack;document.querySelector('#display-black').max=-displayRange;
  document.querySelector('#display-range').value=displayRange;document.querySelector('#display-auto').checked=autoBlack;updateSliders();
}
function estimate(row){
  if(!autoBlack||estimateFrozen||!row?.levels)return;
  const q=[...row.levels].sort((a,b)=>a-b)[Math.floor((row.levels.length-1)/2)];
  if(q>0){displayBlack=Math.max(-120,Math.min(-displayRange,q-123));estimateFrozen=true;updateLevels();}
}
for(const id of ['display-black','display-range'])document.querySelector(`#${id}`).addEventListener('change',e=>{
  if(e.target.value.trim()==='')return;const n=Number(e.target.value);if(!Number.isFinite(n))return;
  if(id==='display-range')displayRange=Math.max(10,Math.min(80,Math.floor(n+.5)));else displayBlack=Math.floor(n+.5);
  displayBlack=Math.max(-120,Math.min(-displayRange,displayBlack));autoBlack=false;estimateFrozen=false;updateLevels();paint();
});
document.querySelector('#display-auto').addEventListener('change',e=>{
  autoBlack=e.target.checked;estimateFrozen=false;if(autoBlack){displayBlack=-120;for(const row of [...rows].reverse()){estimate(row);if(estimateFrozen)break;}}updateLevels();paint();
});
function subscribe(current){
  const id=nextId++,profile=profileSelect.value;if(profile==='detail')detailRequest=id;
  current.send(JSON.stringify({v:1,type:`spectrum.${profile}`,id}));
}


const statusText = document.querySelector('#signal-status'), progress = document.querySelector('#recording-progress');
let upper, snapshot, importOutcome, rows = [], drawPending = false, syncPending = false, syncAgain = false, uploading = false, uploadId, uploadAbort, stopped = false, subscribedSocket;
const identity = s => s ? `${s.boot_id}/${s.job?.source_id}/${s.job?.id}/${s.generation}` : '';
function split(value) {
  const otherHeight=stationBar.offsetHeight+strip.offsetHeight;
  const signalText=[signal.querySelector(".op-signal-heading"),document.querySelector("#frequency-ruler"),document.querySelector("#level-legend")].reduce((height,node)=>height+(node?.offsetHeight||0),0);
  const minimum=Math.max(160,Math.ceil(signalText+60));
  main.style.minHeight=`${minimum+228+otherHeight}px`;
  const available = Math.max(minimum+228,main.clientHeight-otherHeight)-splitter.offsetHeight, maximum = available-200;
  upper = Math.max(minimum,Math.min(maximum,value ?? 210));
  signal.style.height = `${upper}px`;
  for (const [name,value] of [['min',minimum],['max',maximum],['now',Math.round(upper)]]) splitter.setAttribute(`aria-value${name}`,String(value));
  paint();
}
splitter.addEventListener('keydown',event => {
  const values = {ArrowUp:upper-16,ArrowDown:upper+16,Home:160,End:Number(splitter.getAttribute('aria-valuemax'))};
  if (event.key in values) {event.preventDefault();split(values[event.key]);}
});
splitter.addEventListener('pointerdown',event => {splitter.setPointerCapture(event.pointerId);splitter.focus();});
splitter.addEventListener('pointermove',event => {if (splitter.hasPointerCapture(event.pointerId)){const box=signal.getBoundingClientRect();split((event.clientY-box.top-strip.offsetHeight)/(box.height/signal.offsetHeight));}});
addEventListener('resize',() => split(upper));
const textLayoutObserver=new ResizeObserver(()=>split(upper));
for(const node of [stationBar,strip,document.querySelector("#frequency-ruler"),document.querySelector("#level-legend")])textLayoutObserver.observe(node); split();
function timeProjection(H=waterfall.height,C=waterfall.getBoundingClientRect().height){
  const groups=Array(H),T=(rows.at(-1)?.end_frame??0)/12000,scale=10*speed*H/Math.max(C,1);
  let count=0;
  for(let r=0;r<rows.length;r++){
    const row=rows.at(-1-r),top=Math.floor((T-row.end_frame/12000)*scale),bottom=Math.floor((T-row.first_frame/12000)*scale);
    if(top>=H)break;
    for(let y=Math.max(0,top);y<Math.min(H,Math.max(top+1,bottom));y++){
      if(groups[y])groups[y][1]=r;else groups[y]=[r,r];count=Math.max(count,r+1);
    }
  }
  return {groups,count,T,capacity:C/(10*speed)};
}
function visibleCount(){return timeProjection().count;}
function groupLevels(first,last,B){
  const q=new Uint8Array(B);
  for(let r=first;r<=last;r++){
    const native=rows.at(-1-r)?.levels;if(!native)return null;
    for(let k=0;k<B;k++)q[k]=Math.max(q[k],native[k]);
  }
  return q;
}
function readout(){
  const B=profileSelect.value==='detail'?1024:128,R=visibleCount(),text=document.querySelector('#bin-readout');
  selectedBin=Math.max(0,Math.min(B-1,selectedBin));selectedRow=Math.max(0,Math.min(R-1,selectedRow));
  const row=rows.at(-1-selectedRow);if(!row){text.textContent='No measurement';return;}
  const W=waterfall.width,H=waterfall.height,x=pointerColumn===null?Math.floor(selectedBin*W/B):Math.max(0,Math.min(W-1,pointerColumn));
  const first=W<B?Math.ceil(x*B/W):selectedBin,last=W<B?Math.min(B-1,Math.ceil((x+1)*B/W)-1):selectedBin;
  const projection=timeProjection(),nativeY=Math.floor((projection.T-row.end_frame/12000)*10*speed*H/Math.max(waterfall.getBoundingClientRect().height,1)),group=projection.groups[pointerTime===null?Math.max(0,Math.min(H-1,nativeY)):pointerTime];
  if(!group){text.textContent='No measurement (unobserved source time)';return;}
  const [newest,oldest]=group,projected=groupLevels(newest,oldest,B);
  const value=row.levels?`${row.levels[selectedBin]-120} dBFS`:'no measurement (gap)';
  const peak=projected?`${Math.max(...projected.slice(first,last+1))-120} dBFS`:'unknown (gap)';
  const low=rows.at(-1-oldest).first_frame/12000,high=rows.at(-1-newest).end_frame/12000;
  text.textContent=`Native bin ${selectedBin} | ${(selectedBin*3000/B).toFixed(4)} Hz | ${value} | source ${(row.first_frame/12000).toFixed(1)}-${(row.end_frame/12000).toFixed(3)} s | projected bins ${first}-${last}: ${peak} | projected source ${low.toFixed(1)}-${high.toFixed(3)} s`;
}
const waterfall=document.querySelector('#waterfall');
waterfall.addEventListener('pointermove',event=>{
  const box=waterfall.getBoundingClientRect(),B=profileSelect.value==='detail'?1024:128,R=visibleCount();if(!R)return;
  selectedBin=Math.min(B-1,Math.max(0,Math.floor((event.clientX-box.left)/box.width*B+.5)));
  pointerColumn=Math.floor((event.clientX-box.left)/box.width*waterfall.width);
  pointerTime=Math.max(0,Math.min(waterfall.height-1,Math.floor((event.clientY-box.top)/box.height*waterfall.height)));
  const group=timeProjection().groups[pointerTime];if(group)selectedRow=group[0];readout();
});
waterfall.addEventListener('keydown',event=>{
  if(!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key))return;event.preventDefault();pointerColumn=null;pointerTime=null;
  if(event.key==='ArrowLeft')selectedBin--;if(event.key==='ArrowRight')selectedBin++;
  if(event.key==='ArrowUp')selectedRow--;if(event.key==='ArrowDown')selectedRow++;
  selectedRow=Math.max(0,Math.min(visibleCount()-1,selectedRow));readout();
});

function paint() {
  if(drawPending)return;drawPending=true;
  requestAnimationFrame(()=>{
    drawPending=false;
    const B=profileSelect.value==='detail'?1024:128;
    for(const id of ['spectrum','waterfall']){
      const c=document.querySelector(`#${id}`),box=c.getBoundingClientRect();
      c.width=Math.max(1,Math.round(box.width*devicePixelRatio));c.height=Math.max(1,Math.round(box.height*devicePixelRatio));
      const ctx=c.getContext('2d');ctx.imageSmoothingEnabled=false;ctx.fillStyle='rgb(0 0 12)';ctx.fillRect(0,0,c.width,c.height);
      const project=levels=>{
        if(c.width>=B)return levels;
        const q=new Uint8Array(c.width);levels.forEach((v,k)=>{const x=Math.floor(k*c.width/B);q[x]=Math.max(q[x],v);});return q;
      };
      if(id==='spectrum'){
        const row=rows.at(-1);if(!row?.levels)continue;const values=project(row.levels);
        ctx.strokeStyle='rgb(180 245 220)';ctx.lineWidth=Math.max(1,devicePixelRatio);ctx.beginPath();
        values.forEach((q,k)=>{const x=Math.floor(k*c.width/values.length),y=Math.max(0,Math.min(c.height-1,(displayBlack+displayRange-(q-120))*c.height/displayRange));k?ctx.lineTo(x,y):ctx.moveTo(x,y);});ctx.stroke();
      }else{
        const W=c.width,H=c.height,projection=timeProjection(H,box.height),R=projection.count;
        if(R){
          const image=ctx.createImageData(W,H),lut=Array.from({length:121},(_,q)=>[...paletteRGB((q-120-effectiveBlack())/displayRange),255]);
          let previous='',line;
          for(let y=0;y<H;y++){
            const group=projection.groups[y],key=group?group.join(','):'none';
            if(key!==previous){
              previous=key;line=new Uint8ClampedArray(W*4);const native=group?groupLevels(...group,B):null,values=native?project(native):null;
              if(!values){for(let x=0;x<W;x++)line.set(group?[96,96,96,255]:[0,0,12,255],x*4);}
              else for(let k=0;k<values.length;k++){
                const left=Math.floor(k*W/values.length),right=Math.floor((k+1)*W/values.length),rgb=lut[values[k]];
                for(let x=left;x<right;x++)line.set(rgb,x*4);
              }
            }
            image.data.set(line,y*W*4);
          }
          ctx.putImageData(image,0,0);
        }
        const last=rows.at(-1),oldest=R?rows.at(-R):null,low=oldest?.first_frame/12000,high=last?.end_frame/12000;
        c.dataset.rows=String(rows.length);c.dataset.visibleRows=String(R);c.dataset.sequences=rows.map(r=>r.sequence).join(',');c.dataset.bins=String(B);c.dataset.span='0,3000';
        c.setAttribute('aria-label',`Waterfall, visible source time ${R?`${low.toFixed(1)} to ${high.toFixed(1)} seconds`:''}; newest top, grey groups are unknown; arrow keys select native bins and rows`);
        const ruler=document.querySelector('#time-ruler');ruler.replaceChildren();
        if(last){
          const latest=projection.T,times=[latest];let previousY=0;
          for(let t=Math.floor(latest/5)*5;t>=Math.max(0,latest-projection.capacity);t-=5){const y=Math.floor((latest-t)*10*speed*H/box.height)/devicePixelRatio;if(y-previousY>=16){times.push(t);previousY=y;}}
          for(const t of times){const label=document.createElement('span');label.textContent=`${t.toFixed(1)}s`;label.style.top=`${Math.floor((latest-t)*10*speed*H/box.height)/devicePixelRatio}px`;ruler.append(label);}
        }
        document.querySelector('#speed-value').title=`${projection.capacity.toFixed(1)} s viewport capacity; ${R?`observed source ${low.toFixed(1)}-${high.toFixed(1)} s`:'no observed history'}; replay/network rate unchanged`;
      }
    }
    const ruler=document.querySelector('#frequency-ruler');ruler.replaceChildren();
    const labelStep=500*Math.max(1,Math.ceil(parseFloat(getComputedStyle(ruler).fontSize)*4/Math.max(1,ruler.clientWidth/6)));
    for(let f=0;f<=3000;f+=100){const tick=document.createElement('span');tick.style.left=`${f/30}%`;tick.className=f%500?'minor':'major';if(f===0||f===3000||f%labelStep===0)tick.textContent=String(f);ruler.append(tick);}
    const legend=document.querySelector('#level-legend'),E=effectiveBlack(),R=visibleCount(),low=R?rows.at(-R).first_frame/12000:0,high=R?rows.at(-1).end_frame/12000:0;
    legend.textContent=`0-3000 Hz | ${B===1024?'2.93 Hz/bin':'23.44 Hz/group'} | WF ${E} to ${E+displayRange} dBFS | Window ${timeProjection().capacity.toFixed(1)} s | Observed ${low.toFixed(1)}-${high.toFixed(1)} s`;
    legend.title=B===1024?'Detailed: 2.9296875 Hz native bins; 5 rows/s; 4096/12000 = 0.341333 s Hann window support':'Thin: 23.4375 Hz groups; 1 row/s; 2048/12000 s Hann window support';
    legend.setAttribute('aria-label',`${legend.textContent}; ${legend.title}`);
    document.querySelector('#spectrum').title=`Curve base scale ${displayBlack} to ${displayBlack+displayRange} dBFS; Sensitivity changes waterfall colors only`;
    const bar=document.querySelector('#level-bar'),box=bar.getBoundingClientRect();bar.width=Math.max(1,Math.round(box.width*devicePixelRatio));bar.height=Math.max(1,Math.round(box.height*devicePixelRatio));
    const context=bar.getContext('2d'),image=context.createImageData(bar.width,bar.height);
    for(let x=0;x<bar.width;x++){const rgb=[...paletteRGB(x/Math.max(1,bar.width-1)),255];for(let y=0;y<bar.height;y++)image.data.set(rgb,(y*bar.width+x)*4);}context.putImageData(image,0,0);
    readout();
  });
}

function show() {
  const active = snapshot?.import || (snapshot?.job && ['running','cancelling'].includes(snapshot.job.state) ? snapshot.job : null);
  statusText.textContent = snapshot?.source_error ? 'Recording unavailable · import a replacement' : snapshot?.recording ? `Recording ready · ${snapshot.job?.state || 'idle'}` : 'No recording imported';
  if(fallbackText)statusText.textContent+=` | ${fallbackText}`;
  if(snapshot?.storage_error) statusText.textContent += ' · storage unavailable';
  document.querySelector('#signal-meta').textContent = snapshot?.recording ? `${snapshot.recording.id} · ${snapshot.recording.frames/12000} s · 12000 Hz · UTC unavailable` : '';
  document.querySelector('#recording-replay').disabled = !snapshot?.recording || !!active || !!snapshot?.storage_error || uploading;
  document.querySelector('#recording-import').disabled = !snapshot || !!active || !!snapshot?.storage_error || uploading;
  document.querySelector('#recording-cancel').disabled = !active && !uploading;
  if(active) progress.textContent = snapshot.import ? `${active.state} · ${active.total_bytes === null ? 'awaiting upload' : `${active.received_bytes} / ${active.total_bytes} bytes`}` : `${active.state} · ${active.processed_frames} frames`;
  else if(importOutcome && importOutcome.generation===snapshot?.generation) progress.textContent=`Import ${importOutcome.state}${importOutcome.error ? ` · ${importOutcome.error}` : ''}`;
  else if(snapshot?.job) progress.textContent = `${snapshot.job.state}${snapshot.job.error ? ` · ${snapshot.job.error}` : ''} · ${snapshot.job.processed_frames} frames`;
  signal.setAttribute('aria-label',live?.job?'Live spectrum and waterfall':'Recorded spectrum and waterfall');
  if(live?.job){statusText.textContent=`Live ${live.job.mode.toUpperCase()} · ${live.audio.state} · ${live.job.state}${live.job.error?` · ${live.job.error}`:''}`;}
}
async function request(path,options={}) {
  const current=socket,authEpoch=authorization?.snapshot().epoch;
  const response=await stationFetch(path,{...options,signal:options.signal || AbortSignal.timeout(10000)});
  const data=await response.json();if(!stationContext(current,authEpoch))throw new Error('Station response is stale');if(!response.ok) throw new Error(data.error?.code || 'request_failed');return data;
}
async function sync(current=socket) {
  if(current!==socket)return;restoreDisplayPreference();if(syncPending){syncAgain=true;return;}syncPending=true;
  const authEpoch=authorization?.snapshot().epoch;
  try {
    const data=await request('/recording');if(!stationContext(current,authEpoch)) return;
    const previousImport=snapshot?.import?.id,previousGeneration=snapshot?.generation;
    if(identity(data)!==identity(snapshot)){rows=[];resetLevels();paint();}snapshot=data;
    if(data.job?.kind!=='live'&&live?.job){live=undefined;resultRows=[];renderResults();receiveShow();}
    if(previousImport && !data.import && previousGeneration===data.generation){
      try{const outcome=await request(`/recording/imports/${previousImport}`);if(!stationContext(current,authEpoch))return;importOutcome={...outcome,generation:data.generation};}catch{if(current===socket)progress.textContent='Import outcome unavailable · current source state refreshed';}
    }
    show();
    if(subscribedSocket!==current && current.readyState===WebSocket.OPEN) {subscribedSocket=current;subscribe(current);}
  } catch(error){if(current===socket)statusText.textContent=`Recording state unavailable · ${error.message}`;} finally{syncPending=false;if(syncAgain){syncAgain=false;sync(socket);}}
}
addEventListener('station-ready',event => {if(subscribedSocket!==event.detail || snapshot?.boot_id!==profileData.boot_id)sync(event.detail);});
addEventListener('station-stale',()=>{statusText.textContent='Disconnected · recording data stale';subscribedSocket=undefined;});
addEventListener('station-message',event => {
  const {message,current}=event.detail;
  if(current!==socket)return;
  if(message.type==='recording.state') {
    if(snapshot && (message.data.generation!==snapshot.generation || message.data.state!==(snapshot.job?.state??null) || message.data.source_id!==(snapshot.job?.kind==='live'?snapshot.job.source_id:(snapshot.recording?.id??null)) || message.data.job_id!==(snapshot.job?.id??null))) sync(current);
    return;
  }
  if(message.type==='error'&&message.data.code==='unknown_command'){
    if(message.id===detailRequest&&profileSelect.value==='detail'){detailRequest=undefined;profileSelect.value='thin';rows=[];resetLevels();fallbackText='Detailed unavailable; using Thin';subscribe(current);show();paint();}
    else {statusText.textContent='Recording display unavailable on this server';}return;
  }
  const detail=profileSelect.value==='detail';
  if(message.type!==(detail?'spectrum.detail.frame':'spectrum.frame')||profileSelect.value==='off')return;
  const f=message.data, B=detail?1024:128,interval=detail?2400:12000,cap=detail?600:120;
  const currentLive=!!live?.job && !!live?.source;
  if(live?.job&&!live.source)return;
  if(snapshot?.job?.kind==='live'&&!currentLive)return;
  const context=currentLive?{boot_id:live.boot_id,generation:live.generation,job:{...live.job,source_id:live.source.id}}:snapshot;
  if(!f||!context||!['running','completed'].includes(context.job?.state)||f.boot_id!==context.boot_id||f.generation!==context.generation||f.job_id!==context.job?.id||f.source_id!==context.job?.source_id)return;
  if(Object.keys(message).sort().join(',')!=='data,type,v'||message.v!==1)return;
  const keys=['boot_id','source_id','job_id','generation','sequence','first_frame','end_frame',detail?'levels_b64':'levels'].sort().join(',');
  if(Object.keys(f).sort().join(',')!==keys||!Number.isSafeInteger(f.sequence)||f.sequence<0||(!currentLive&&f.sequence>=cap)||!Number.isSafeInteger(f.first_frame)||!Number.isSafeInteger(f.end_frame)||f.first_frame!==f.sequence*interval||f.end_frame<=f.first_frame)return;
  if(currentLive ? f.end_frame!==f.first_frame+interval : (!snapshot.recording||f.first_frame>=snapshot.recording.frames||f.end_frame!==Math.min(f.first_frame+interval,snapshot.recording.frames)))return;
  let values=f.levels;
  if(detail){
    if(typeof f.levels_b64!=='string'||f.levels_b64.length!==1368||!/^[A-Za-z0-9+/]{1366}==$/.test(f.levels_b64))return;
    try{const raw=atob(f.levels_b64);if(raw.length!==1024||btoa(raw)!==f.levels_b64)return;values=Uint8Array.from(raw,c=>c.charCodeAt(0));}catch{return;}
  }
  if((!detail&&!Array.isArray(values))||values.length!==B||!values.every(q=>Number.isInteger(q)&&q>=0&&q<=120))return;
  const previous=rows.at(-1)?.sequence??-1;if(f.sequence<=previous)return;
  for(let sequence=Math.max(previous+1,f.sequence-cap+1);sequence<f.sequence;sequence++)rows.push({sequence,first_frame:sequence*interval,end_frame:currentLive?(sequence+1)*interval:Math.min((sequence+1)*interval,snapshot.recording.frames),levels:null});
  const row={...f,levels:Uint8Array.from(values)};rows.push(row);rows=rows.slice(-cap);estimate(row);paint();

  if(currentLive){live.job.processed_frames=Math.max(live.job.processed_frames,f.end_frame);live.source.next_frame=Math.max(live.source.next_frame,f.end_frame);}
  else snapshot.job.processed_frames=f.end_frame;
  show();
});
setInterval(()=>{if(socket?.readyState===WebSocket.OPEN && snapshot)socket.send(JSON.stringify({v:1,type:'recording.get',id:nextId++}));},2000);
setInterval(()=>{if(socket?.readyState===WebSocket.OPEN && snapshot?.import && !uploading)sync();},5000);
function startBody(){return {v:1,profile_id:snapshot.profile_id,boot_id:snapshot.boot_id,generation:snapshot.generation};}
document.querySelector('#recording-import').addEventListener('click',async()=>{
  const file=document.querySelector('#recording-file').files[0];if(!file){progress.textContent='Choose a WAV recording.';return;}
  if(file.size===0||file.size>3145728){progress.textContent='request_too_large';return;}
  const intentAuth=authorization?.snapshot(),intentProfile=profileData && JSON.stringify([profileData.profile_id,profileData.boot_id,profileData.revision,profileData.settings.control]);
  const requireIntent=()=>{
    const now=authorization?.snapshot();
    if(authorization&&(!now.ready||now.epoch!==intentAuth.epoch||JSON.stringify(now.scope)!==JSON.stringify(intentAuth.scope)) ||
      intentProfile!==JSON.stringify([profileData?.profile_id,profileData?.boot_id,profileData?.revision,profileData?.settings.control]))throw new Error('Import intent changed; review current station before starting again');
  };
  let importFailure;
  uploading=true;stopped=false;show();
  try{
    requireIntent();
    const operation=await request('/recording/imports',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(startBody())});
    uploadId=operation.id;
    if(stopped){requireIntent();const outcome=await request(`/recording/imports/${uploadId}`,{method:'DELETE'});await sync();importOutcome={...outcome,generation:operation.generation};show();return;}
    uploadAbort=new AbortController();await sync();
    for(let offset=0;offset<file.size&&!stopped;offset+=2048){
      requireIntent();
      const end=Math.min(offset+2048,file.size);
      const result=await request(`/recording/imports/${uploadId}`,{method:'PUT',headers:{'Content-Type':'audio/wav','Content-Range':`bytes ${offset}-${end-1}/${file.size}`},body:file.slice(offset,end),signal:uploadAbort.signal});
      progress.textContent=`${result.state} · ${end} / ${file.size} bytes`;
    }
  }catch(error){importFailure=`Import outcome · ${error.message} · refresh state before starting again`;}
  finally{uploading=false;uploadAbort=null;uploadId=null;await sync();if(importFailure)progress.textContent=importFailure;}
});
document.querySelector('#recording-replay').addEventListener('click',async()=>{
  try{await request('/recording/replay',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...startBody(),recording_id:snapshot.recording.id})});await sync();}catch(error){progress.textContent=error.message;await sync();}
});
document.querySelector('#recording-cancel').addEventListener('click',async()=>{
  stopped=true;uploadAbort?.abort();
  const id=uploadId||snapshot?.import?.id;
  if(uploading && !id){progress.textContent='Cancellation requested · awaiting reservation response';return;}
  if(!id && !snapshot?.job){await sync();return;}
  try{const outcome=await request(id?`/recording/imports/${id}`:`/recording/jobs/${snapshot.job.id}`,{method:'DELETE'});await sync();if(id){importOutcome={...outcome,generation:snapshot.generation};show();}}catch(error){progress.textContent=`Cancellation outcome unknown · ${error.message}`;await sync();}
});
profileSelect.addEventListener('change',()=>{const id=displayPreferenceId();if(id&&['detail','thin','off'].includes(profileSelect.value))try{localStorage.setItem(displayPreferenceKey(id),profileSelect.value);}catch{}rows=[];fallbackText='';resetLevels();paint();if(socket?.readyState===WebSocket.OPEN)subscribe(socket);});
if(socket?.readyState===WebSocket.OPEN && profileData && connection.dataset.state==='connected')sync(socket);

let live,livePending=false,liveAgain=null,resultPending=false,lastResultStart=-Infinity,resultCursor=0,resultRows=[],historyIncomplete=false,mutationPending=false,uncertainMutation=false,receiveFailure='';
let operatingState=null,operatingSupported=null,operatingFailure='',operatingReadPending=false,operatingReadAgain=false,operatingEpoch=0,operatingUnknown=null,operatingIntent=null,lastOperatingRead=-Infinity,operatingSocket=null;
let catStatus=null,catPending=false,catAgain=false,catConfirming=false;

// Mutations supersede earlier reads; accepted snapshots supersede pending pages.
let receiveMutationEpoch=0,liveRevision=0,resultView=null,activityHistory=[],ownReceiveMutationAt=-Infinity,liveOperatingRevision=null;
let lastReceiveReady=null;
let activitySortProfile=null,activitySortField='frequency',activitySortDirection='asc';
const liveIdentity=s=>s?`${s.profile_id}/${s.boot_id}/${s.source?.id??''}/${s.job?.id??''}/${s.generation}`:'';
const receiveStatus=document.querySelector('#receive-status');
function validPeriodTime(value,mode){
  return typeof value==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$/.test(value)&&Number.isFinite(Date.parse(value))&&new Date(Date.parse(value)).toISOString().slice(0,19)===value.slice(0,19)&&(value.endsWith('.0000000Z')||(mode==='ft4'&&value.endsWith('.5000000Z')))&&Date.parse(value)%(mode==='ft8'?15000:7500)===0;
}
function validLatestDecode(view,mode,end){
  if(view===null)return true;
  return view&&Object.keys(view).sort().join(',')==='complete,first_sequence,id,next_sequence,period_start_utc'&&
    ['id','first_sequence','next_sequence'].every(k=>Number.isSafeInteger(view[k])&&view[k]>=0)&&view.id>0&&
    view.first_sequence<=view.next_sequence&&view.next_sequence<=end&&typeof view.complete==='boolean'&&
    (view.period_start_utc===null||validPeriodTime(view.period_start_utc,mode));
}
function applyLatestDecode(view,first){
  if(resultView&&view&&view.id<resultView.id)return false;
  if(resultView&&view&&view.id===resultView.id){if(['id','first_sequence','next_sequence','period_start_utc','complete'].some(k=>view[k]!==resultView[k]))throw new Error('Changed decode descriptor');return true;}
  if(resultView===null&&view===null)return true;
  // BandActivityView: the replaced period stays as history; a new identity clears it.
  if(resultView&&resultRows.length&&live?.job){
    activityHistory.unshift({id:resultView.id,period:resultView.period_start_utc,mode:live.job.mode,context:liveIdentity(live),rows:[...resultRows]});
    let total=0;activityHistory=activityHistory.slice(0,20).filter(h=>(total+=h.rows.length)<=2048);
  }
  resultView=view;resultRows=[];resultCursor=Math.max(first,view?.first_sequence??first);
  if(view&&first>view.first_sequence)historyIncomplete=true;
  renderResults();return true;
}
function periodLabel(value,mode){return value?value.slice(11,mode==='ft4'?21:19):'Unknown';}
function validLiveSnapshot(s){
  const shape=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).sort().join(',')===keys;
  const counter=n=>Number.isSafeInteger(n)&&n>=0;
  const nullableText=v=>v===null||(typeof v==='string'&&v.length>0&&new TextEncoder().encode(v).length<=256);
  const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(v);
  if(!shape(s,'audio,boot_id,clock,generation,job,profile_id,source,v')||s.v!==1||!uuid(s.profile_id)||!uuid(s.boot_id)||!counter(s.generation))return false;
  const a=s.audio,c=s.clock,j=s.job,source=s.source;
  if(!shape(a,'device_id,device_name,error,last_loss,loss_epochs,retry_after_ms,state')||!['closed','opening','running','closing','unavailable'].includes(a.state)||![a.device_id,a.device_name,a.error].every(nullableText)||(a.retry_after_ms!==null&&(!counter(a.retry_after_ms)||a.retry_after_ms>8000))||!counter(a.loss_epochs)||(a.last_loss!==null&&(typeof a.last_loss!=='string'||!/^[a-z_]{1,32}$/.test(a.last_loss)))||(a.loss_epochs===0)!==(a.last_loss===null))return false;
  if(source!==null&&(!shape(source,'channels,id,kind,next_frame,sample_rate,segment')||!uuid(source.id)||source.kind!=='live'||source.sample_rate!==12000||source.channels!==1||!counter(source.next_frame)||!counter(source.segment)))return false;
  if(j!==null){
    if(!shape(j,'available_count,error,first_sequence,id,last_overrun,latest_decode,mode,next_sequence,processed_frames,state')||!uuid(j.id)||!['spectrum','ft4','ft8'].includes(j.mode)||!['running','cancelling','completed','cancelled','failed'].includes(j.state)||!nullableText(j.error)||!['first_sequence','next_sequence','available_count','processed_frames'].every(key=>counter(j[key]))||j.available_count!==j.next_sequence-j.first_sequence||j.available_count>2048||!validLatestDecode(j.latest_decode,j.mode,j.next_sequence))return false;
    const o=j.last_overrun;
    if(o!==null&&(!source||!shape(o,'end_frame,first_frame')||!counter(o.first_frame)||!counter(o.end_frame)||o.first_frame>=o.end_frame||o.end_frame>source.next_frame))return false;
  }
  return shape(c,'basis,canonical_anchor_frame,correlated,external_accuracy,uncertainty_ns,utc_anchor')&&c.basis==='system_utc'&&typeof c.correlated==='boolean'&&c.external_accuracy==='unknown'&&(c.canonical_anchor_frame===null||counter(c.canonical_anchor_frame))&&(c.correlated?typeof c.utc_anchor==='string'&&Number.isFinite(Date.parse(c.utc_anchor))&&counter(c.uncertainty_ns)&&c.uncertainty_ns<=2000000:c.utc_anchor===null&&c.uncertainty_ns===null);
}
function receiveShow(){
  if(!resultRows.length)renderResults();
  const connected=connection.dataset.state==='connected',active=live?.job&&['running','cancelling'].includes(live.job.state);
  if(live){
    receiveStatus.textContent=`Audio ${live.audio.state}${live.audio.error?` · ${live.audio.error}`:''}${live.audio.loss_epochs?` · ${live.audio.loss_epochs} audio loss restart${live.audio.loss_epochs===1?'':'s'} (last ${live.audio.last_loss})`:''}${live.job?` · ${live.job.mode.toUpperCase()} ${live.job.state}${live.job.error?` · ${live.job.error}`:''}`:' · receive stopped'}${historyIncomplete?' · Incomplete result history':''}${live.job&&['failed','cancelled'].includes(live.job.state)?' · Partial results retained':''}${receiveFailure?` · ${receiveFailure}`:''}`;
    const capabilities=document.querySelectorAll('#operating-capabilities dd');
    capabilities[0].textContent=live.audio.state==='running'?'Running · selected input':`Unavailable · ${live.audio.error??live.audio.state}`;
    capabilities[2].textContent=live.job&&live.job.mode!=='spectrum'?`${live.job.mode.toUpperCase()} · ${live.job.state}`:'Unavailable · receive stopped';
    document.querySelector('#receive-generation').textContent=`Receive generation ${live.generation} · source ${live.source?.id??'none'} · job ${live.job?.id??'none'}`;
    const c=live.clock;document.querySelector('#clock-detail').textContent=`Clock ${c.basis} · ${c.correlated?`receive periods correlated to UTC anchor ${c.utc_anchor}, uncertainty ${c.uncertainty_ns} ns`:'receive periods not correlated to UTC'} · external accuracy ${c.external_accuracy}`;
    const focus=document.querySelector('#rx-focus .op-contact-identity');
    // A contact rendered by contact.js keeps its own identity text.
    if(!document.querySelector('#rx-focus').dataset.contact){
      if(live.job&&live.job.mode!=='spectrum'){focus.querySelector('strong').textContent='No contact selected';focus.querySelector('div > span').textContent='Select a decoded station or enter a DX call.';}
      else{focus.querySelector('strong').textContent='No station selected';focus.querySelector('div > span').textContent='No station selected. Contact selection requires decoded results.';}
    }
  }
  operatingShow();
}
async function receiveSync(current=socket){
  if(current!==socket||connection.dataset.state!=='connected')return;
  if(livePending){liveAgain=receiveMutationEpoch;return;}livePending=true;
  const epoch=receiveMutationEpoch,authEpoch=authorization?.snapshot().epoch;
  try{
    const data=await request('/receive');
    if(!stationContext(current,authEpoch)||epoch!==receiveMutationEpoch)return;
    if(!validLiveSnapshot(data))throw new Error('Invalid receive snapshot');
    if(data.profile_id!==profileData.profile_id||data.boot_id!==profileData.boot_id||data.generation<(live?.generation??0))return;
    if(liveIdentity(data)!==liveIdentity(live)){
      // ExceptionChip receiveRestarted: a new generation not explained by this browser or a selection.
      if(live?.job&&data.generation>live.generation&&performance.now()-ownReceiveMutationAt>15000&&operatingState&&operatingState.operating_revision===liveOperatingRevision)restartedAt=performance.now();
      resultRows=[];resultView=null;resultCursor=data.job?.first_sequence??0;historyIncomplete=false;activityHistory=[];
      if(data.job||live?.job){rows=[];resetLevels();paint();}
      renderResults();
    }
    live=data;liveOperatingRevision=operatingState?.operating_revision??null;liveRevision++;applyLatestDecode(data.job?.latest_decode??null,data.job?.first_sequence??0);uncertainMutation=false;receiveFailure='';receiveShow();show();
  }catch(error){if(current===socket&&epoch===receiveMutationEpoch){receiveFailure=`Live receive unavailable · ${error.message}`;receiveStatus.textContent=receiveFailure;}}
  finally{livePending=false;const again=liveAgain;liveAgain=null;if(again!==null&&again===receiveMutationEpoch)receiveSync(socket);}
}
function activityOrdering(records=resultRows){
  const id=displayPreferenceId();
  if(id&&id!==activitySortProfile){activitySortProfile=id;activitySortField='frequency';activitySortDirection='asc';}
  for(const th of document.querySelectorAll('#band-activity th[data-sort]'))th.setAttribute('aria-sort',th.dataset.sort===activitySortField?(activitySortDirection==='asc'?'ascending':'descending'):'none');
  const key=r=>activitySortField==='frequency'?r.frequency_hz:activitySortField==='signal'?r.snr_db:activitySortField==='dt'?r.dt_seconds:r.text?.toUpperCase()??null;
  const missing=v=>v===null||v===undefined||v==='';
  return [...records].sort((a,b)=>{
    const left=key(a),right=key(b);
    if(missing(left)!==missing(right))return missing(left)?1:-1;
    const compared=missing(left)?0:typeof left==='number'?left-right:left<right?-1:left>right?1:0;
    return compared*(activitySortDirection==='asc'?1:-1)||a.sequence-b.sequence;
  });
}
function sortBy(button){
  if(button.dataset.sort===activitySortField)activitySortDirection=activitySortDirection==='asc'?'desc':'asc';
  else{activitySortField=button.dataset.sort;activitySortDirection=activitySortField==='signal'?'desc':'asc';}
  renderResults();
}
document.querySelector('#band-activity thead').addEventListener('click',event=>{const th=event.target.closest('th[data-sort]');if(th)sortBy(th);});
document.querySelector('#band-activity thead').addEventListener('keydown',event=>{const th=event.target.closest('th[data-sort]');if(th&&(event.key==='Enter'||event.key===' ')){event.preventDefault();sortBy(th);}});
function renderResults(){
  const ordered=activityOrdering();
  const body=document.querySelector('#band-activity tbody');
  const loading=resultView&&resultCursor<resultView.next_sequence;
  document.querySelector('#band-activity header .op-muted').textContent=resultView?
    `Latest ${live?.job?.mode.toUpperCase()} period ${periodLabel(resultView.period_start_utc,live?.job?.mode)}${resultView.period_start_utc?' UTC':''} \u00b7 ${resultView.complete?'Attempt complete':'Partial'}${loading?' \u00b7 Loading results':''}${historyIncomplete?' \u00b7 Incomplete history':''}`:'Latest decode period';
  document.querySelector('#band-activity header .op-muted').title=resultView?.period_start_utc?'Timing relative to station system clock; external UTC accuracy unknown. DT positive: late; negative: early.':'Station clock correlation unavailable until supplied by this source.';
  document.querySelector('#band-activity .op-count').textContent=`${resultRows.length} message${resultRows.length===1?'':'s'}`;
  if(!resultRows.length){
    body.innerHTML='<tr><td colspan="7" class="empty-messages"><strong></strong><span></span></td></tr>';
    const decoder=live?.job&&['ft4','ft8'].includes(live.job.mode),job=live?.job;
    let heading='Decoder unavailable',message='No decoded messages are available from this server.';
    if(decoder){
      const mode=job.mode.toUpperCase();
      heading=job.state==='running'?(connection.dataset.state==='connected'?`Listening for ${mode}`:`${mode} receive status stale`):job.state==='cancelling'?`Stopping ${mode} receive`:`${mode} receive ${job.state}`;
      message=['running','cancelling'].includes(job.state)?'No verified messages decoded yet.':'No verified messages were decoded.';
      if(resultView){heading=loading?'Loading latest decode':resultView.complete?'No stations decoded':'No stations decoded in partial attempt';message=loading?'Latest-period results are being received.':'No verified stations were decoded in this period.';}
    }
    body.querySelector('strong').textContent=heading;body.querySelector('span').textContent=message;renderHistory(body);return;
  }
  body.replaceChildren();
  for(const record of ordered)body.append(activityRow(record,'latest',liveIdentity(live),live.job.mode));
  renderHistory(body);
}
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
function activityRow(record,period,context,mode){
  const labels=[...document.querySelectorAll('#band-activity th')].map(th=>th.textContent);
  const row=document.createElement('tr');row.setAttribute('role','row');row.dataset.resultId=`${context}/${record.sequence}`;row.dataset.sequence=String(record.sequence);row.dataset.period=period;
  const decoded=record.status==='decoded',to=record.fields?.to?.kind==='call'?record.fields.to.text:null,my=(profileData?.settings?.callsign??'').trim().toUpperCase();
  if(decoded&&/^CQ\b/.test(record.text))row.classList.add('ba-cq');
  if(decoded&&my&&to===my)row.classList.add('ba-tome');
  const grid=record.fields?.exchange?.kind==='grid'?record.fields.exchange.value:null,km=grid?distanceKm(profileData?.settings?.locator,grid):null;
  const cells=[periodLabel(record.period_start_utc,mode),record.snr_db===null?'\u2014':record.snr_db.toFixed(1),record.dt_seconds===null?'\u2014':`${Math.abs(record.dt_seconds)<0.05?'+':record.dt_seconds<0?'-':'+'}${Math.abs(record.dt_seconds).toFixed(1)}`,record.frequency_hz.toFixed(1),decoded?record.text:`Payload ${record.status}`,'\u2014',km===null?'\u2014':`${km} km`];
  for(const [index,text] of cells.entries()){
    const cell=document.createElement('td');cell.setAttribute('role','cell');cell.dataset.label=labels[index];cell.textContent=text;
    if(index===4)cell.dataset.col='message';
    if(index===5)cell.title='DXCC needs the cty.dat prefix table, which this station does not provide yet';
    row.append(cell);
  }
  return row;
}
function renderHistory(body){
  for(const block of activityHistory){
    const divider=document.createElement('tr');divider.className='ba-divider';divider.setAttribute('role','row');
    const cell=document.createElement('td');cell.colSpan=7;cell.setAttribute('role','cell');cell.textContent=`${block.mode.toUpperCase()} period ${periodLabel(block.period,block.mode)}${block.period?' UTC':''}`;divider.append(cell);body.append(divider);
    for(const record of activityOrdering(block.rows))body.append(activityRow(record,'history',block.context,block.mode));
  }
}
function validRecord(r){
  return r&&Object.keys(r).sort().join(',')==='dt_seconds,fields,frequency_hz,i3,n3,payload77,period_start_utc,sequence,snr_db,start_frame,status,text'&&
    Number.isSafeInteger(r.sequence)&&r.sequence>=0&&Number.isSafeInteger(r.start_frame)&&r.start_frame>=0&&
    ((r.period_start_utc===null&&r.dt_seconds===null)||(validPeriodTime(r.period_start_utc,live.job.mode)&&Number.isFinite(r.dt_seconds)&&r.dt_seconds>=-(live.job.mode==='ft8'?7.5:3.75)&&r.dt_seconds<(live.job.mode==='ft8'?7.5:3.75)))&&
    Number.isFinite(r.frequency_hz)&&r.frequency_hz>=200&&r.frequency_hz<=3500&&
    (r.snr_db===null||(Number.isFinite(r.snr_db)&&r.snr_db>=-60&&r.snr_db<=60))&&
    typeof r.payload77==='string'&&/^[01]{77}$/.test(r.payload77)&&Number.isInteger(r.i3)&&r.i3>=0&&r.i3<=7&&
    (r.i3===0?Number.isInteger(r.n3)&&r.n3>=0&&r.n3<=7:r.n3===null)&&
    (r.status==='decoded'?typeof r.text==='string'&&/^[\x20-\x7e]{1,80}$/.test(r.text)&&r.fields&&typeof r.fields==='object'&&!Array.isArray(r.fields):['unsupported','invalid_payload'].includes(r.status)&&r.text===null&&r.fields===null);
}
async function receiveResults(){
  if(resultPending||livePending||mutationPending||uncertainMutation||operatingReadPending||operatingBlocked()||refresh.disabled||connection.dataset.state!=='connected'||!live?.source||!['ft4','ft8'].includes(live.job?.mode))return;
  const now=performance.now();if(now-lastResultStart<4000)return;
  resultPending=true;lastResultStart=now;
  const context=liveIdentity(live),current=socket,cursor=resultCursor,revision=liveRevision,epoch=receiveMutationEpoch,authEpoch=authorization?.snapshot().epoch;
  const query=new URLSearchParams({source_id:live.source.id,job_id:live.job.id,generation:String(live.generation),cursor:String(cursor),limit:profileSelect.value==='thin'?'1':'16'});
  try{
    const response=await stationFetch(`/receive/results?${query}`,{signal:AbortSignal.timeout(10000)}),page=await response.json();
    if(!stationContext(current,authEpoch)||context!==liveIdentity(live)||revision!==liveRevision||epoch!==receiveMutationEpoch)return;
    if(response.status===410){
      if(page.error?.code!=='cursor_expired'||!Number.isSafeInteger(page.first_sequence)||!Number.isSafeInteger(page.next_sequence)||page.first_sequence<0||page.first_sequence>page.next_sequence)throw new Error('Invalid expired cursor');
      historyIncomplete=true;resultCursor=page.first_sequence;receiveShow();return;
    }
    if(!response.ok)throw new Error(page.error?.code??'Result request failed');
    const keys='available_count,boot_id,error,first_sequence,generation,job_id,latest_decode,mode,more,next,next_sequence,profile_id,records,search_limited,source_id,state,v';
    if(Object.keys(page).sort().join(',')!==keys||page.v!==1||page.profile_id!==live.profile_id||page.boot_id!==live.boot_id||page.source_id!==live.source.id||page.job_id!==live.job.id||page.generation!==live.generation||page.mode!==live.job.mode||typeof page.search_limited!=='boolean'||!Array.isArray(page.records)||page.records.length>(profileSelect.value==='thin'?1:16))throw new Error('Invalid result page');
    for(const key of ['first_sequence','next_sequence','available_count','next'])if(!Number.isSafeInteger(page[key])||page[key]<0)throw new Error('Invalid result counter');
    if(page.available_count!==page.next_sequence-page.first_sequence||page.available_count>2048||page.next!==cursor+page.records.length||page.next>page.next_sequence||page.more!==(page.next<page.next_sequence)||cursor<page.first_sequence)throw new Error('Invalid result window');
    if(!validLatestDecode(page.latest_decode,page.mode,page.next_sequence))throw new Error('Invalid decode descriptor');
    for(let i=0;i<page.records.length;i++)if(!validRecord(page.records[i])||page.records[i].sequence!==cursor+i)throw new Error('Invalid decoded record');
    if(!applyLatestDecode(page.latest_decode,page.first_sequence))return;
    if(resultView){
      // A page may announce a period whose prefix was fetched and filtered earlier.
      // Rewind to that descriptor's first cursor; an empty tail is not its full view.
      if(cursor>resultCursor){receiveShow();return;}
      resultCursor=Math.max(resultCursor,page.next);
      const known=new Set(resultRows.map(r=>r.sequence));
      resultRows.push(...page.records.filter(r=>r.sequence>=resultView.first_sequence&&r.sequence<resultView.next_sequence&&(resultView.period_start_utc===null||r.period_start_utc===resultView.period_start_utc)&&!known.has(r.sequence)));
      resultRows=resultRows.slice(-2048);
    }else resultCursor=page.next;
    live.job.state=page.state;live.job.error=page.error;renderResults();receiveShow();
  }catch(error){if(current===socket&&context===liveIdentity(live)&&revision===liveRevision&&epoch===receiveMutationEpoch)receiveStatus.textContent=`Result state unavailable · ${error.message}`;}
  finally{resultPending=false;}
}
// Strict /receive/start and /receive/stop, only from an operator action (chip, Expert, Alt+M),
// never from a timer, reconnect, readiness or snapshot path. Start uses the selection mode.
async function receiveStart(){
  const active=live?.job&&['running','cancelling'].includes(live.job.state);
  if(!live||active||mutationPending||uncertainMutation||operatingBlocked()||!profileData?.settings.audio.input_device)return;
  receiveMutationEpoch++;mutationPending=true;ownReceiveMutationAt=performance.now();receiveShow();
  try{await request('/receive/start',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:live.profile_id,boot_id:live.boot_id,generation:live.generation,profile_revision:profileData.revision,mode:operatingState?.selection.mode??'ft8'})});await sync();await receiveSync();}
  catch(error){receiveMutationEpoch++;uncertainMutation=true;receiveFailure=`Start outcome unknown · ${error.message} · refresh before another action`;}
  finally{mutationPending=false;receiveShow();}
}
async function receiveStop(){
  if(!live?.job||live.job.state==='cancelling'||mutationPending||uncertainMutation)return;
  receiveMutationEpoch++;mutationPending=true;ownReceiveMutationAt=performance.now();receiveShow();
  try{await request('/receive/stop',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:live.profile_id,boot_id:live.boot_id,generation:live.generation,job_id:live.job.id})});await receiveSync();await sync();}
  catch(error){receiveMutationEpoch++;uncertainMutation=true;receiveFailure=`Stop outcome unknown · ${error.message} · refresh before another action`;}
  finally{mutationPending=false;receiveShow();}
}
document.querySelector('#audio-enumerate').addEventListener('click',async()=>{
  const output=document.querySelector('#audio-inputs');
  try{const data=await request('/audio/devices');output.textContent=data.devices.map(d=>`${d.name} [${d.id}]`).join('\n')||'No audio inputs available';}
  catch(error){output.textContent=`Audio inputs unavailable · ${error.message}`;}
});
function receiveReadyKey(profile,statusId){
  const uuid=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value);
  if(!profile||!uuid(profile.profile_id)||!uuid(profile.boot_id)||!Number.isSafeInteger(profile.revision)||profile.revision<0||!Number.isSafeInteger(statusId)||statusId<=0)return null;
  return JSON.stringify([profile.profile_id,profile.boot_id,profile.revision,statusId]);
}
function receiveReady(current){
  if(current!==socket||connection.dataset.state!=='connected')return false;
  const key=receiveReadyKey(profileData,pendingId);
  if(key!==null){
    if(lastReceiveReady?.socket===current&&lastReceiveReady.key===key)return false;
    // The synchronous receiveSync entry below necessarily starts or queues this
    // read under the same socket/connection checks; failed HTTP is not replayed.
    lastReceiveReady={socket:current,key};
  }
  receiveSync(current);return true;
}
addEventListener('station-ready',event=>receiveReady(event.detail));
addEventListener('station-stale',()=>{lastReceiveReady=null;receiveShow();receiveStatus.textContent='Disconnected · live receive data stale';});
addEventListener('station-message',event=>{if(event.detail.current===socket&&event.detail.message.type==='receive.state')receiveSync(event.detail.current);});
setInterval(receiveResults,250);
if(socket?.readyState===WebSocket.OPEN&&profileData&&connection.dataset.state==='connected')receiveSync(socket);

// These controls share the existing station/receive authority. Nominal selection
// and dated CAT observations remain different values throughout a transition.
const operatingControls=document.createElement('div');operatingControls.id='operating-receive-controls';
operatingControls.innerHTML='<label class="op-compact-label">Band &#10227;<select id="operating-band" disabled title="Band: changing it restarts receive"><option value="">Choose band</option></select></label><label class="op-compact-label">Mode &#10227;<select id="operating-mode" disabled title="Mode: changing it restarts receive"><option value="ft8">FT8</option><option value="ft4">FT4</option></select></label>';
tuning.prepend(operatingControls);
const receiveToggleButton=document.querySelector('#receive-toggle');
receivePanel.insertAdjacentHTML('beforeend','<p id="operating-selection-status" role="status">Operating selection unavailable until station snapshot</p><output id="operating-radio">CAT readback unavailable</output><p><button id="operating-refresh" type="button" disabled>Refresh operating state</button></p>');
catSettings.insertAdjacentHTML('beforeend','<div id="cat-lifecycle"><p id="cat-status" role="status">CAT status unavailable</p><div id="cat-confirm" hidden><p id="cat-confirm-summary"></p><label class="receive-only-verification"><input type="checkbox" id="cat-confirm-ack">USB SEND/CW/RTTY keying is OFF or receive inhibit is verified</label><button id="cat-confirm-button" type="button" disabled>Confirm receive-only setup</button></div><p id="cat-confirm-result" role="status"></p></div>');
const operatingMode=document.querySelector('#operating-mode'),operatingBand=document.querySelector('#operating-band'),operatingStatus=document.querySelector('#operating-selection-status');
const operatingBands=['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m','4m'];
const operatingUuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(v);
const operatingCounter=v=>Number.isSafeInteger(v)&&v>=0;
const operatingShape=(v,keys)=>v!==null&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).sort().join(',')===keys.split(',').sort().join(',');
const operatingNullable=(v,valid)=>v===null||valid(v);
const operatingModeValid=v=>['ft4','ft8'].includes(v);
const operatingFrequency=v=>Number.isSafeInteger(v)&&v>=30000&&v<=74800000;
function operatingSelectionBlocked(){return !!operatingUnknown||!!operatingIntent||operatingState?.operation?.result==='pending';}
function operatingBlocked(){return operatingSelectionBlocked();}
function validOperatingState(s){
  if(!operatingShape(s,'v,profile_id,boot_id,profile_revision,generation,operating_revision,snapshot_sequence,monotonic_ms,control,selection,available_bands,operation,cancellation,receive,radio')||s.v!==1||!operatingUuid(s.profile_id)||!operatingUuid(s.boot_id)||!['manual','cat'].includes(s.control))return false;
  for(const key of ['profile_revision','generation','operating_revision','snapshot_sequence','monotonic_ms'])if(!operatingCounter(s[key]))return false;
  const n=s.selection;
  if(!operatingShape(n,'mode,band,nominal_hz,origin,confirmed_command_id')||!operatingModeValid(n.mode)||!operatingNullable(n.band,v=>operatingBands.includes(v))||!operatingNullable(n.nominal_hz,operatingFrequency)||!['unknown','manual','cat_readback'].includes(n.origin)||!operatingNullable(n.confirmed_command_id,operatingUuid)||(n.band===null)!==(n.nominal_hz===null))return false;
  if(n.band===null&&(n.origin!=='unknown'||n.confirmed_command_id!==null))return false;
  if(!Array.isArray(s.available_bands)||new Set(s.available_bands).size!==s.available_bands.length||s.available_bands.some((v,i)=>!operatingBands.includes(v)||(i&&operatingBands.indexOf(s.available_bands[i-1])>=operatingBands.indexOf(v))))return false;
  if(s.operation!==null){const o=s.operation;
    if(!operatingShape(o,'command_id,base_revision,revision,action,requested,phase,result,error,monitor_before,monitor_wanted,old_job_id,new_job_id')||!operatingUuid(o.command_id)||!operatingCounter(o.base_revision)||!operatingCounter(o.revision)||!['mode','band'].includes(o.action)||!['releasing','applying','restarting','applied','failed','release_blocked','cancelled'].includes(o.phase)||!['pending','success','failed','cancelled'].includes(o.result)||!operatingNullable(o.error,v=>typeof v==='string'&&/^[a-z_]{1,32}$/.test(v))||typeof o.monitor_before!=='boolean'||typeof o.monitor_wanted!=='boolean'||!operatingNullable(o.old_job_id,operatingUuid)||!operatingNullable(o.new_job_id,operatingUuid))return false;
    if(!operatingShape(o.requested,'mode,band,nominal_hz')||!operatingModeValid(o.requested.mode)||!operatingBands.includes(o.requested.band)||!operatingFrequency(o.requested.nominal_hz))return false;
  }
  if(s.cancellation!==null){const c=s.cancellation;if(!operatingShape(c,'command_id,target_command_id,revision,result')||!operatingUuid(c.command_id)||!operatingUuid(c.target_command_id)||!operatingCounter(c.revision)||!['cancelled','fenced','already_cancelled'].includes(c.result))return false;}
  const receive=s.receive;
  if(!operatingShape(receive,'job_id,mode,state,audio_state,owner_released')||!operatingNullable(receive.job_id,operatingUuid)||!operatingNullable(receive.mode,v=>['spectrum','ft4','ft8'].includes(v))||!operatingNullable(receive.state,v=>['running','cancelling','completed','cancelled','failed'].includes(v))||!['closed','opening','running','closing','unavailable'].includes(receive.audio_state)||typeof receive.owner_released!=='boolean')return false;
  const r=s.radio;if(!operatingShape(r,'connection_generation,state,error,observations')||!operatingCounter(r.connection_generation)||!['closed','connecting','ready','closing','unavailable'].includes(r.state)||!operatingNullable(r.error,v=>typeof v==='string'&&/^[a-z_]{1,32}$/.test(v))||!operatingShape(r.observations,'frequency,mode,data,rx_tx,split'))return false;
  for(const [key,f]of Object.entries(r.observations)){
    if(!operatingShape(f,'value,query_sequence,observed_at_ms,confirmed')||typeof f.confirmed!=='boolean'||(f.confirmed&&r.state!=='ready'))return false;
    if(f.value===null){if(f.query_sequence!==null||f.observed_at_ms!==null||f.confirmed)return false;continue;}
    if(!operatingCounter(f.query_sequence)||f.query_sequence===0||!operatingCounter(f.observed_at_ms)||f.observed_at_ms>s.monotonic_ms)return false;
    if(key==='frequency'&&!operatingFrequency(f.value))return false;
    if(key==='mode'&&(!operatingShape(f.value,'mode,filter')||typeof f.value.mode!=='string'||!(/^(USB|LSB|[0-9A-F]{2})$/).test(f.value.mode)||!Number.isInteger(f.value.filter)||f.value.filter<0||f.value.filter>255))return false;
    if(key==='data'&&(!operatingShape(f.value,'enabled,filter')||typeof f.value.enabled!=='boolean'||!Number.isInteger(f.value.filter)||f.value.filter<0||f.value.filter>3))return false;
    if(key==='rx_tx'&&!['RX','TX'].includes(f.value))return false;
    if(key==='split'&&typeof f.value!=='boolean')return false;
  }
  return true;
}
function operatingShow(){
  if(!document.querySelector('#operating-receive-controls'))return;
  const connected=connection.dataset.state==='connected',s=operatingState,ready=connected&&operatingSupported===true&&!!s;
  const blocked=!ready||mutationPending||uncertainMutation||operatingBlocked();
  operatingMode.disabled=blocked;operatingBand.disabled=blocked;
  const active=live?.job&&['running','cancelling'].includes(live.job.state),target=operatingUnknown?.command_id||operatingIntent?.command_id||((s?.operation?.result==='pending')?s.operation.command_id:null);
  // With a pending/unknown selection the receive control cancels it (the former Stop).
  receiveToggleButton.disabled=!receiveToggleAvailable();
  receiveToggleButton.textContent=target?'Cancel band/mode change':active?'Stop receive':'Start receive';
  receiveToggleButton.setAttribute('aria-pressed',String(!!active||!!target));
  document.querySelector('#operating-refresh').disabled=!connected||operatingReadPending;
  catShow();
  if(!s){operatingStatus.textContent=operatingFailure||'Operating selection unavailable until station snapshot';return;}
  operatingMode.value=s.selection.mode;
  const listed=operatingBand.querySelectorAll('option');if([...listed].slice(1).map(o=>o.value).join(',')!==s.available_bands.join(',')){
    operatingBand.replaceChildren(new Option('Choose band',''),...s.available_bands.map(b=>new Option(b,b)));
  }
  operatingBand.value=s.selection.band??'';
  const frequency=s.radio.observations.frequency;
  const observed=frequency.value===null?'Actual rig frequency unknown':`Observed ${(frequency.value/1e6).toFixed(6)} MHz · ${connected&&frequency.confirmed?'confirmed query':'stale/unconfirmed'} at ${frequency.observed_at_ms} ms`;
  const nominal=s.selection.nominal_hz===null?'Nominal frequency unknown':`Nominal ${(s.selection.nominal_hz/1e6).toFixed(6)} MHz · ${s.selection.origin==='manual'?'manual, actual rig unconfirmed':'CAT readback at selection'}`;
  document.querySelector('#operating-radio').textContent=`CAT ${s.radio.state}${s.radio.error?' · '+s.radio.error:''} · ${observed} · ${nominal}`;
  const dial=document.querySelector('#op-dial');dial.value=frequency.value!==null?(frequency.value/1e6).toFixed(6):s.selection.nominal_hz!==null?(s.selection.nominal_hz/1e6).toFixed(6):'';dial.title=`${observed}. ${nominal}`;const fresh=connected&&frequency.confirmed;dial.dataset.fresh=String(fresh);dial.setAttribute('aria-label',frequency.value!==null?(fresh?'Observed dial frequency':'Last observed dial frequency, stale/unconfirmed'):'Nominal dial frequency, actual rig unconfirmed');
  const capabilities=document.querySelectorAll('#operating-capabilities dd');capabilities[1].textContent=!connected?'Unavailable · status stale':s.radio.state==='ready'?'Ready · IC-7300 readback':`Unavailable · ${s.radio.error??s.radio.state}`;
  const o=s.operation;
  operatingStatus.textContent=operatingFailure||(operatingUnknown?'Selection outcome unknown · refresh or press Monitor to cancel/fence before another action':mutationPending&&operatingIntent?'Selection request pending · waiting for server admission':o?`${o.result==='pending'?'Switching':o.phase} · ${o.requested.mode.toUpperCase()} ${o.requested.band}${o.error?' · '+o.error:''}`:`${s.selection.mode.toUpperCase()} · choose a band to establish nominal frequency`);
}
async function operatingSync(reconcile=false){
  if(connection.dataset.state!=='connected'||!profileData)return;
  if(operatingReadPending){if(reconcile)operatingReadAgain=true;return;}
  operatingReadPending=true;lastOperatingRead=performance.now();const epoch=operatingEpoch,current=socket,authEpoch=authorization?.snapshot().epoch;
  try{
    const response=await stationFetch('/receive/selection',{signal:AbortSignal.timeout(10000)}),text=await response.text();
    if(epoch!==operatingEpoch||!stationContext(current,authEpoch)||connection.dataset.state!=='connected')return;
    let s;try{s=JSON.parse(text);}catch{throw new Error('Invalid operating snapshot');}
    if(response.status===404||response.status===400&&s.error?.code==='unsupported_version'||s&&typeof s.v==='number'&&s.v!==1){operatingSupported=false;operatingFailure='Operating controls unsupported by this server';return;}
    if(!response.ok)throw new Error(s.error?.code||'Operating state unavailable');
    if(new TextEncoder().encode(text).length>3072||!validOperatingState(s))throw new Error('Invalid operating snapshot');
    if(s.profile_id!==profileData.profile_id||s.boot_id!==profileData.boot_id||s.profile_revision!==profileData.revision)throw new Error('Operating identity is stale');
    if(operatingState?.boot_id===s.boot_id&&s.snapshot_sequence<operatingState.snapshot_sequence)return;
    const resolved=operatingUnknown&&reconcile&&(s.boot_id!==operatingUnknown.boot_id||s.operation?.command_id===operatingUnknown.command_id||s.operating_revision>operatingUnknown.base_revision);
    if(resolved)operatingUnknown=null;
    if(operatingIntent&&(s.operation?.command_id===operatingIntent.command_id||s.operating_revision>operatingIntent.base_revision))operatingIntent=null;
    const catKey=o=>o&&JSON.stringify([o.boot_id,o.profile_revision,o.radio.connection_generation,o.radio.state,o.radio.error]),changed=catKey(operatingState)!==catKey(s);
    operatingState=s;operatingSupported=true;if(changed||!catStatus)catSync();if(resolved||operatingFailure.startsWith('Operating state stale')||operatingFailure==='Disconnected · operating data stale')operatingFailure='';
  }catch(error){if(epoch===operatingEpoch&&current===socket){operatingFailure=`Operating state stale · ${error.message}`;operatingSupported=null;}}
  finally{operatingReadPending=false;operatingShow();receiveShow();if(operatingReadAgain){operatingReadAgain=false;operatingSync(true);}}
}
async function operatingSelect(action,value){
  if(!operatingState||mutationPending||uncertainMutation||operatingBlocked())return;
  const s=operatingState,command_id=crypto.randomUUID(),epoch=++operatingEpoch,current=socket,authEpoch=authorization?.snapshot().epoch;
  const body={v:1,profile_id:s.profile_id,boot_id:s.boot_id,command_id,action,profile_revision:s.profile_revision,generation:s.generation,operating_revision:s.operating_revision,[action]:value};
  operatingIntent={command_id,base_revision:s.operating_revision,boot_id:s.boot_id};receiveMutationEpoch++;ownReceiveMutationAt=performance.now();mutationPending=true;operatingFailure='';receiveShow();
  try{
    const response=await stationFetch('/receive/select',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(10000)}),text=await response.text(),ack=JSON.parse(text);
    if(epoch!==operatingEpoch)return;
    if(!stationContext(current,authEpoch))throw new Error('Stale selection completion');
    if(!response.ok){operatingFailure=`Selection refused · ${ack.error?.code??'request_failed'}`;operatingIntent=null;return;}
    if(new TextEncoder().encode(text).length>384||!operatingShape(ack,'v,profile_id,boot_id,command_id,operating_revision,accepted,phase')||ack.v!==1||ack.profile_id!==s.profile_id||ack.boot_id!==s.boot_id||ack.command_id!==command_id||ack.accepted!==true||!operatingCounter(ack.operating_revision)||ack.operating_revision<=s.operating_revision||!['releasing','applying','restarting','applied','failed','release_blocked'].includes(ack.phase))throw new Error('Invalid admission receipt');
  }catch(error){if(epoch===operatingEpoch){operatingUnknown=operatingIntent;operatingFailure=`Selection outcome unknown · ${error.message} · refresh or press Monitor to cancel/fence`;}}
  finally{if(epoch===operatingEpoch){mutationPending=false;receiveShow();await operatingSync(true);await receiveSync();}}
}
async function operatingStop(){
  const s=operatingState,target=operatingUnknown??operatingIntent??(s?.operation?{command_id:s.operation.command_id,base_revision:s.operation.base_revision,boot_id:s.boot_id}:null);
  if(!target||(!operatingUnknown&&!operatingIntent&&s?.operation?.result!=='pending')){receiveStop();return;}
  const epoch=++operatingEpoch,current=socket,authEpoch=authorization?.snapshot().epoch;receiveMutationEpoch++;mutationPending=true;operatingFailure='';receiveShow();
  try{
    const command_id=crypto.randomUUID();
    const response=await stationFetch('/receive/select',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:profileData.profile_id,boot_id:target.boot_id,command_id,action:'cancel',operating_revision:target.base_revision,target_command_id:target.command_id}),signal:AbortSignal.timeout(10000)}),text=await response.text(),ack=JSON.parse(text);
    if(!stationContext(current,authEpoch))throw new Error('Stale cancellation completion');
    if(!response.ok)throw new Error(ack.error?.code??'Stop refused');
    if(new TextEncoder().encode(text).length>384||!operatingShape(ack,'v,profile_id,boot_id,command_id,operating_revision,accepted,phase')||ack.v!==1||ack.profile_id!==profileData.profile_id||ack.boot_id!==target.boot_id||ack.command_id!==command_id||ack.accepted!==true||ack.phase!=='cancelled'||!operatingCounter(ack.operating_revision))throw new Error('Invalid cancellation receipt');
    if(epoch===operatingEpoch){operatingUnknown=null;operatingIntent=null;}
  }catch(error){if(epoch===operatingEpoch){operatingUnknown=target;operatingFailure=`Stop outcome unknown · ${error.message} · refresh before another action`;}}
  finally{if(epoch===operatingEpoch){mutationPending=false;await operatingSync(true);await receiveSync();receiveShow();}}
}
// Band and mode are restart changes (marked): during a QSO or transmission they ask first.
async function restartAllowed(what){
  const s=window.wstxContact?.snapshot?.(),c=s?.contact,busy=(c&&!['idle','completed','cancelled'].includes(c.state))||s?.transmit?.arm_state==='armed'||s?.transmit?.tune;
  return !busy||await confirmAction(`${what} restarts receive and interrupts the QSO in progress. Continue?`,'Restart receive');
}
operatingMode.addEventListener('change',async()=>{if(await restartAllowed('Changing the mode'))operatingSelect('mode',operatingMode.value);else operatingShow();});
operatingBand.addEventListener('change',async()=>{if(!operatingBand.value)return;if(await restartAllowed('Changing the band'))operatingSelect('band',operatingBand.value);else operatingShow();});
function receiveTarget(){const s=operatingState;return operatingUnknown?.command_id||operatingIntent?.command_id||((s?.operation?.result==='pending')?s.operation.command_id:null);}
function receiveToggleAvailable(){
  const connected=connection.dataset.state==='connected',active=live?.job&&['running','cancelling'].includes(live.job.state);
  return connected&&(!!receiveTarget()||(!!live&&!mutationPending&&!uncertainMutation&&(active?live.job.state!=='cancelling':(!!live.audio&&!!profileData?.settings.audio.input_device&&operatingState?.receive.owner_released!==false))));
}
function receiveToggle(){
  if(!receiveToggleAvailable())return;
  if(operatingState?.operation?.result==='pending'||operatingUnknown||operatingIntent)operatingStop();else if(live?.job&&['running','cancelling'].includes(live.job.state))receiveStop();else receiveStart();
}
receiveToggleButton.addEventListener('click',receiveToggle);
document.querySelector('#operating-refresh').addEventListener('click',()=>operatingSync(true));
refresh.addEventListener('click',()=>{if(operatingUnknown||operatingIntent||operatingFailure.startsWith('Operating state stale')||operatingFailure.startsWith('CAT '))operatingSync(true);});
addEventListener('station-ready',event=>{
  const replaced=operatingState&&operatingState.boot_id!==profileData?.boot_id;
  const edited=operatingState&&operatingState.profile_revision!==profileData?.revision;
  if(replaced||edited){if(operatingIntent)mutationPending=false;operatingState=null;operatingUnknown=null;operatingIntent=null;operatingEpoch++;catStatus=null;}
  const reconnected=operatingSocket!==event.detail;operatingSocket=event.detail;
  // station-ready also follows routine status/profile refreshes. Those must not
  // bypass the selection cadence or create a second optional HTTP workload.
  if(operatingSupported!==false&&(reconnected||replaced||edited||(!operatingState&&!operatingReadPending)))operatingSync(reconnected||!!replaced||!!edited);
  operatingShow();
});
addEventListener('station-stale',()=>{operatingFailure='Disconnected · operating data stale';operatingShow();});
setInterval(()=>{
  if(operatingSupported===false||operatingReadPending||livePending||resultPending||syncPending||mutationPending||uncertainMutation||refresh.disabled||connection.dataset.state!=='connected')return;
  const pending=operatingState?.operation?.result==='pending',slow=profileSelect.value!=='detail',interval=slow?(pending?4000:8000):(pending?500:2000);
  if(performance.now()-lastOperatingRead>=interval)operatingSync(false);
},250);
if(socket?.readyState===WebSocket.OPEN&&profileData&&connection.dataset.state==='connected'){operatingSocket=socket;operatingSync(false);}

// CL-022-03/05: automatic CAT health is read from the additive authorization status
// only when the versioned operating snapshot changes its CAT identity/state/error
// (connection generation advances on every attempt) or after a confirmation, never
// on its own timer. Session, CAT and audio/decoder remain separate observations.
const catConditions=['disabled','unauthorized','commissioningRequired','waitingForDevice','connecting','ready','retryWaiting','closing','quarantined'];
function validCatStatus(v,scope){
  return operatingShape(v,'version,scope,condition,error,retry_after_ms,commissioned,receive_state')&&v.version===1&&
    operatingShape(v.scope,'profile_id,radio_id,safety_revision')&&operatingUuid(v.scope.profile_id)&&operatingUuid(v.scope.radio_id)&&Number.isSafeInteger(v.scope.safety_revision)&&v.scope.safety_revision>0&&
    (!scope||(scope.profile_id===v.scope.profile_id&&scope.radio_id===v.scope.radio_id))&&catConditions.includes(v.condition)&&
    operatingNullable(v.error,e=>typeof e==='string'&&/^[a-z_]{1,32}$/.test(e))&&operatingNullable(v.retry_after_ms,n=>Number.isSafeInteger(n)&&n>=0&&n<=8000)&&
    typeof v.commissioned==='boolean'&&operatingShape(v.receive_state,'audio,decoder');
}
async function catSync(){
  // CAT disabled needs no status read: the saved settings already state it.
  if(!authorization||connection.dataset.state!=='connected'||profileData?.settings.control.mode!=='cat')return;
  if(catPending){catAgain=true;return;}
  catPending=true;const current=socket,authEpoch=authorization.snapshot().epoch;
  try{
    const response=await stationFetch('/authorization/v1/status',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:'{"version":1}',signal:AbortSignal.timeout(10000)}),text=await response.text();
    if(!stationContext(current,authEpoch))return;
    if(!response.ok||new TextEncoder().encode(text).length>1024)throw new Error('CAT status unavailable');
    const v=JSON.parse(text);if(!validCatStatus(v,authorization.snapshot().scope))throw new Error('Invalid CAT status');
    catStatus=v;
  }catch{if(current===socket)catStatus=null;}
  finally{catPending=false;catShow();if(catAgain){catAgain=false;catSync();}}
}
function catModel(endpoint){return typeof endpoint==='string'&&(/^icom7300:\/\//.test(endpoint)||/^COM[0-9]{1,3}$/i.test(endpoint))?'Icom IC-7300 (CI-V)':'unsupported CAT model';}
// WstxOperatingLayout::ExceptionChip: only while a condition holds; each opens its detail.
var chipsReady=false,restartedAt=-Infinity;
function chip(key,severity,text,action){const button=document.createElement('button');button.type='button';button.className='op-chip';button.dataset.chip=key;button.dataset.severity=severity;button.textContent=`${severity==='error'?'\u2716':'\u26A0'} ${text}`;button.title=text;button.addEventListener('click',action);return button;}
function chipsShow(){
  if(!chipsReady)return;
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
addEventListener('station-stale',()=>chipsShow());
setInterval(chipsShow,1000);
function catShow(){
  const status=document.querySelector('#cat-status');if(!status)return;
  const connected=connection.dataset.state==='connected',v=connected?catStatus:null,confirm=document.querySelector('#cat-confirm');
  const reason=v?.error?` · ${v.error}`:'';
  const texts={disabled:'CAT disabled',unauthorized:'CAT waiting for station authorization',commissioningRequired:'CAT waiting · receive-only setup not confirmed',
    waitingForDevice:`CAT waiting for radio${reason}`,connecting:`CAT connecting${reason}`,ready:'CAT ready · fresh readback',
    retryWaiting:`CAT unavailable${reason} · automatic retry in ${Math.ceil((v?.retry_after_ms??0)/1000)} s`,closing:`CAT closing${reason}`,
    quarantined:'CAT quarantined · close failed; check the radio connection and restart the station'};
  status.textContent=!connected?'CAT status stale · station disconnected':profileData?.settings.control.mode!=='cat'?'CAT disabled':!authorization?`CAT ${operatingState?.radio.state??'status unavailable'} · automatic CAT requires the HTTPS station`:v?texts[v.condition]:'CAT status unavailable';
  status.dataset.condition=v?.condition??'unknown';chipsShow();
  const needed=!!v&&v.condition==='commissioningRequired'&&profileData?.settings.control.mode==='cat';
  confirm.hidden=!needed;
  if(needed){
    const c=profileData.settings.control,button=document.querySelector('#cat-confirm-button');
    document.querySelector('#cat-confirm-summary').textContent=`Radio ${v.scope.radio_id} · endpoint ${c.endpoint??'none'} · model ${catModel(c.endpoint)} · PTT ${c.ptt} · setup revision ${v.scope.safety_revision}`;
    button.textContent=v.scope.safety_revision>1?'Confirm changed receive-only setup':'Confirm receive-only setup';
    button.disabled=catConfirming||!authorization?.snapshot().ready||!document.querySelector('#cat-confirm-ack').checked;
  }
}
document.querySelector('#cat-confirm-ack').addEventListener('change',catShow);
document.querySelector('#cat-confirm-button').addEventListener('click',async()=>{
  const v=catStatus,result=document.querySelector('#cat-confirm-result');
  if(!v||v.condition!=='commissioningRequired'||catConfirming||!document.querySelector('#cat-confirm-ack').checked)return;
  catConfirming=true;catShow();const current=socket,authEpoch=authorization.snapshot().epoch,operation_id=crypto.randomUUID();
  try{
    // Confirmation persists the acknowledgement only; it never opens CAT itself.
    const response=await stationFetch('/authorization/v1/commission',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({version:1,operation_id,scope:v.scope,receive_only_confirmed:true}),signal:AbortSignal.timeout(10000)}),text=await response.text();
    if(!stationContext(current,authEpoch))throw new Error('stale completion');
    if(!response.ok){let code='request_failed';try{code=JSON.parse(text).error?.code??code;}catch{}throw new Error(code);}
    const receipt=JSON.parse(text);if(receipt.operation_id!==operation_id||receipt.outcome!=='committed')throw new Error('outcome unknown');
    result.textContent='Receive-only setup confirmed';document.querySelector('#cat-confirm-ack').checked=false;
  }catch(error){result.textContent=`Confirmation not recorded · ${error.message}`;}
  finally{catConfirming=false;catSync();}
});
addEventListener('station-stale',catShow);
// WstxTransmit::TransmitWire operator panel (#9 slice B). Active only for a profile with
// CAT PTT; the browser renders server-confirmed transmit state and sends explicit
// requests. It runs no transmit timer: the server plans, keys and halts.
const transmitPanel=document.createElement('div');transmitPanel.id='transmit-panel';
transmitPanel.innerHTML='<p id="transmit-status" role="status">Transmit unavailable</p><p id="transmit-result" role="status"></p>';
const transmitDetails=secondary('transmit-details','Transmit test panel',transmitPanel,expertSection);transmitDetails.hidden=true;
let transmitView=null,transmitTimer=null;
const transmitConfigured=()=>profileData?.settings.control.ptt==='cat';
function transmitBody(extra){return JSON.stringify({v:1,profile_id:profileData.profile_id,boot_id:profileData.boot_id,command_id:crypto.randomUUID(),...extra});}
async function transmitPost(path,extra){
  const response=await stationFetch(path,{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:transmitBody(extra),signal:AbortSignal.timeout(10000)}),text=await response.text();
  if(!response.ok){let code='request_failed';try{code=JSON.parse(text).error?.code??code;}catch{}throw new Error(code);}
  return JSON.parse(text);
}
function transmitShow(){
  const on=transmitConfigured();transmitDetails.hidden=!on;halt.disabled=!on;document.querySelector('#qso-halt').disabled=!on;
  if(on)halt.removeAttribute('aria-describedby');else halt.setAttribute('aria-describedby','transmit-unavailable');
  const v=transmitView,status=document.querySelector('#transmit-status');
  const setting=document.querySelector('#clock-setting'),m0=v?.clock_measurement;
  setting.textContent=!on||!v?'Station clock: system UTC. Measured offset unavailable (no transmit configuration).':`Station clock: system UTC, ${v.clock}${m0?` · offset ${m0.offset_ms>=0?'+':''}${m0.offset_ms} ms against ${m0.server}, measured ${Math.round(m0.age_ms/1000)} s ago`:' · no SNTP measurement'}`;
  chipsShow();
  if(!on||!v){status.textContent='Transmit unavailable';return;}
  const t=v.transmit,m=v.clock_measurement,clock=m?` ${m.offset_ms>=0?'+':''}${m.offset_ms} ms ${m.server} ${Math.round(m.age_ms/1000)} s ago`:'';
  status.textContent=`${t.capability} · ${t.arm_state} (${t.last_disarm_cause}) · PTT ${v.ptt}${v.transmitting?' · TRANSMITTING':''}${t.tune?' · TUNE':''} · clock ${v.clock}${clock} · halt ${t.halt_state}${t.refusal?' · '+t.refusal:''}${t.last_text?' · last '+t.last_text:''} · WD ${v.watchdog.tx_remaining_minutes} min`;
  const tune=document.querySelector('#tx-tune');if(tune)tune.textContent=t.tune?'Tune off':'Tune';
}
async function transmitSync(){
  if(!transmitConfigured()||!profileData){transmitView=null;transmitShow();return;}
  try{const response=await stationFetch('/transmit',{cache:'no-store',signal:AbortSignal.timeout(5000)});if(response.ok)transmitView=await response.json();}catch{}
  transmitShow();
}
function transmitPoll(){if(transmitConfigured()&&!transmitTimer)transmitTimer=setInterval(transmitSync,1000);else if(!transmitConfigured()&&transmitTimer){clearInterval(transmitTimer);transmitTimer=null;}transmitShow();}
setInterval(transmitPoll,2000);
// The QSO-bar HALT is the same priority halt as the top-bar HALT.
document.querySelector('#qso-halt').addEventListener('click',()=>halt.click());
halt.addEventListener('click',async()=>{
  const result=document.querySelector('#transmit-result');
  try{const r=await transmitPost('/transmit/halt',{});result.textContent=`Halt: ${r.halt_state}`;}catch(error){result.textContent=`Halt not confirmed · ${error.message}`;}
  transmitSync();
});
// WstxContact::HaltTx: Esc and Alt+H send #9's priority halt from this always-loaded
// script, in every page state and focused field. Skipped only when the station is known
// receive-only (the contact snapshot says unsupported); without a snapshot it is sent
// (halt is idempotent). contact.js adds only the contact cancellation for Esc.
function keyboardHaltSkipped(){const s=window.wstxContact?.snapshot?.();return !!s&&s.transmit.capability==='unsupported';}
addEventListener('keydown',event=>{
  const altH=event.altKey&&!event.ctrlKey&&!event.metaKey&&event.key.toLowerCase()==='h';
  if(event.key!=='Escape'&&!altH)return;
  event.preventDefault();
  // 'keyboard-halt' tells contact.js when the halt was answered (or skipped), so the Esc
  // contact cancellation always follows it.
  const done=reply=>window.dispatchEvent(new CustomEvent('keyboard-halt',{detail:{escape:event.key==='Escape',reply}}));
  if(!profileData||keyboardHaltSkipped()){done(null);return;}
  const result=document.querySelector('#transmit-result');
  transmitPost('/transmit/halt',{}).then(r=>{result.textContent=`Halt: ${r.halt_state}`;done(r);},error=>{result.textContent=`Halt not confirmed · ${error.message}`;done(null);}).finally(transmitSync);
},true);
// The drawer starts below the top bar, whose height depends on the window width.
new ResizeObserver(()=>main.style.setProperty('--op-topbar',`${stationBar.offsetHeight}px`)).observe(stationBar);
// ThemeChoice: a manual theme applies at once; contact.js adds the rest.
try{const saved=JSON.parse(localStorage.getItem('wstx.theme.v1'));if(saved?.mode==='manual'&&['day','dark','night'].includes(saved.theme))document.documentElement.dataset.theme=saved.theme;}catch{}
chipsReady=true;chipsShow();
