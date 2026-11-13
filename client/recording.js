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
tuning.innerHTML='<div class="op-dial"><span class="op-dial-label">DIAL MHz</span><input id="op-dial" disabled placeholder="Unknown" aria-label="Dial frequency unavailable" title="CAT readback unavailable"></div><div class="op-period"><span>UTC unavailable</span></div>';
const chips=document.createElement('div');chips.id='exception-chips';chips.className='op-chips';chips.setAttribute('role','group');chips.setAttribute('aria-label','Station exceptions');
const headerActions=document.createElement('div');headerActions.className='op-header-actions';
headerActions.innerHTML='<button type="button" data-region="logbook" id="open-logbook" title="Logbook">&#9776; Logbook</button><button type="button" data-region="server-settings" id="open-server-settings" title="Settings (F2)">&#9881; Settings</button><button type="button" data-region="help" aria-label="Help" title="Keyboard and mouse overview (?)">?</button>';
// WstxOperatingLayout::FullScreenToggle (#96, CL-096-01): left of "?", only where the browser offers element
// full screen (none on Safari on iPhone). The whole page goes full screen; the button follows fullscreenchange,
// however full screen was left. Esc is locked where Keyboard Lock exists, so a short Esc does not leave
// (contact.js: Esc never aborts while full screen). Nothing is stored and nothing is sent to the station.
if(document.fullscreenEnabled===true){
  const corners=(d)=>`<svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="${d}"/></svg>`;
  const expandIcon=corners('M1.5 5.5v-4h4M10.5 1.5h4v4M14.5 10.5v4h-4M5.5 14.5h-4v-4'),collapseIcon=corners('M5.5 1.5v4h-4M14.5 5.5h-4v-4M10.5 14.5v-4h4M1.5 10.5h4v4');
  const fullScreen=document.createElement('button');fullScreen.type='button';fullScreen.id='full-screen';fullScreen.className='op-fullscreen';
  const showFullScreen=()=>{const on=!!document.fullscreenElement;fullScreen.innerHTML=on?collapseIcon:expandIcon;fullScreen.dataset.icon=on?'collapse':'expand';fullScreen.setAttribute('aria-label',on?'Leave full screen':'Full screen');fullScreen.setAttribute('aria-pressed',String(on));fullScreen.title=on?'Leave full screen':'Full screen: hide the browser frame';};
  showFullScreen();
  // A refused request (no user activation, a permissions policy) changes nothing and is no station problem.
  fullScreen.addEventListener('click',()=>{const run=document.fullscreenElement?document.exitFullscreen():document.documentElement.requestFullscreen();run.catch(()=>{});});
  const keyboardLock=on=>{try{const keyboard=navigator.keyboard;if(on)keyboard?.lock?.(['Escape'])?.catch?.(()=>{});else keyboard?.unlock?.();}catch{}};
  document.addEventListener('fullscreenchange',()=>{showFullScreen();keyboardLock(!!document.fullscreenElement);});
  headerActions.querySelector('[data-region=help]').before(fullScreen);
}
const halt=document.createElement('button');halt.id='halt-tx';halt.className='op-halt';halt.disabled=true;halt.innerHTML='<span class="op-square" aria-hidden="true"></span>HALT';halt.setAttribute('aria-label','Halt Tx');halt.title='Halt Tx: emergency stop (Alt+H)';halt.setAttribute('aria-describedby','transmit-unavailable');headerActions.append(halt);
stationBar.replaceChildren(tuning,chips,stationConnectionNode,headerActions);
const strip=document.createElement('section');strip.id='rxtx-strip';strip.className='op-strip';strip.setAttribute('aria-label','Rx and Tx audio frequencies');
const workspace=document.createElement('div');workspace.id='operating-workspace';
const sortHeader=(field,label)=>`<th scope="col" data-sort="${field}" aria-sort="none" tabindex="0" class="op-sort" title="Sort by ${label}">${label}</th>`;
workspace.innerHTML=`<div class="operating-grid op-desk">
<section id="band-activity" class="message-pane op-card op-activity" aria-labelledby="activity-heading"><header><div><h3 id="activity-heading">Band Activity <span class="op-count">0</span></h3><span class="op-muted">Latest decode period</span></div></header><div class="op-table-wrap"><table role="table" aria-label="Decoded messages"><thead role="rowgroup"><tr role="row"><th scope="col">UTC</th>${sortHeader('signal','dB')}${sortHeader('dt','DT')}${sortHeader('frequency','Freq')}${sortHeader('message','Message')}<th scope="col" data-sort="value" aria-sort="none" tabindex="0" class="op-sort" title="Sort by value: calling me, what the strategy would call, new DXCC, zone, grid, call, then strongest">DXCC</th><th scope="col">Dist</th></tr></thead><tbody role="rowgroup"><tr><td colspan="7" class="empty-messages"><strong>Decoder unavailable</strong><span>No decoded messages are available from this server.</span></td></tr></tbody></table></div></section>
<section id="rx-focus" class="message-pane op-card op-qso" aria-labelledby="focus-heading"><header class="op-qso-head"><div class="op-contact-identity"><div><h3 id="focus-heading">QSO</h3><strong>No station selected</strong><span>Select a decoded station or enter a DX call.</span></div></div><span class="op-contact-badge">Unavailable</span></header>
<div class="op-contact-body">
<p id="contact-state" class="ct-state" role="status">Contact state unavailable</p>
</div></section></div>`;
controls.prepend(workspace);
const secondaryRoot=document.createElement('div');secondaryRoot.id='workspace-secondary';secondaryRoot.hidden=true;controls.append(secondaryRoot);
const secondaryRegions=new Map();
function region(id,title,intro){const section=document.createElement('section');section.id='region-'+id;section.className='op-secondary';section.hidden=true;section.setAttribute('aria-labelledby','region-title-'+id);section.innerHTML=`<header><div><span class="op-eyebrow">WSTX / ${title.toUpperCase()}</span><h2 id="region-title-${id}">${title}</h2></div><button type="button" data-region="operate" class="return-operate">&#8592; Back to operation</button></header><div class="op-secondary-body"><p class="op-muted">${intro}</p></div>`;secondaryRoot.append(section);secondaryRegions.set(id,section);return section.querySelector('.op-secondary-body');}
const logRegion=region('logbook','Logbook','Contact history and ADIF operations are unavailable until this station offers contact logging.');
logRegion.insertAdjacentHTML('beforeend','<p>No server-confirmed contacts are available.</p><button type="button" disabled>Import ADIF</button> <button type="button" disabled>Export ADIF</button>');
const helpRegion=region('help','Keyboard and mouse','WSJT-X keys where the function exists. Letter keys and ? are inactive while a text field has focus; Alt+H always halts, Esc aborts the QSO (not in full screen).');
helpRegion.insertAdjacentHTML('beforeend','<dl class="op-keys" id="help-keys"><div><dt>Alt+H / HALT</dt><dd>Emergency stop: halt Tx now, everything off. Panels stay open.</dd></div><div><dt>Esc / Abort QSO</dt><dd>Abort the QSO: the transmission stops now and the contact is cancelled (nothing logged); the station stays ready. Not in full screen.</dd></div><div><dt>Full screen button</dt><dd>Hide the browser frame and show only the app; press again to leave. Esc held: leave full screen.</dd></div><div><dt>F1 / F3 / F5 / ?</dt><dd>This overview</dd></div></dl><p class="op-muted">The interface contains no generated callsigns or simulated radio state.</p>');
function secondary(id,title,element,parent){const detail=document.createElement('details');detail.id=id;const summary=document.createElement('summary');summary.textContent=title;detail.append(summary,element);parent.append(detail);return detail;}
function block(id,title,parent,html=''){const section=document.createElement('section');section.id=id;section.className='op-section';section.setAttribute('aria-labelledby',id+'-title');section.innerHTML=`<h3 id="${id}-title">${title}</h3>${html}`;parent.append(section);return section;}
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
stationFields.insertAdjacentHTML('beforeend','<p class="op-apply-row"><button type="submit" form="settings" class="op-apply">Apply &#10227;</button></p><p id="general-apply-result" class="op-muted" role="status"></p>');
for(const type of ['input','change'])stationFields.addEventListener(type,event=>{if(event.target.form===serverForm&&event.target.id!=='station-continent')serverForm.dispatchEvent(new Event(type));});
generalSection.append(stationFields);
block('settings-clock','Clock',generalSection,'<p id="clock-setting">Station clock: waiting for the station</p>');
const displaySettings=block('settings-display','Display',generalSection,'<p class="op-muted">Display settings affect this browser only and apply at once.</p>');
const browserSettings=block('settings-browsers','Access &amp; grants',generalSection,'<p class="op-muted">This browser holds its own station authorization. Logging out or forgetting the credential needs the station access token to authorize again.</p>');
browserSettings.append(document.querySelector('#authorization-actions'));
chips.after(document.querySelector('#forget'));
const profilePanel=document.querySelector('#profile-panel'),profileMetadata=profilePanel.querySelector('dl');
for(const [name,legendText,ids] of [['radio','CAT &#10227;',['control-mode','control-endpoint','ptt-mode']]]){
  const group=document.createElement('fieldset');group.id='server-fields-'+name;group.className='op-server-fieldset';group.innerHTML=`<legend>${legendText}</legend>`;
  if(name==='radio')group.append(serverForm.querySelector('select:not([id])').closest('label'));
  for(const id of ids)group.append(document.getElementById(id).closest('label'));
  serverForm.insertBefore(group,serverForm.querySelector('p'));
}
document.querySelector('#settings-save').textContent='Apply ⟳';
radioSection.append(profilePanel);
const catSettings=block('settings-cat','CAT receive-only confirmation',radioSection);
// #44 CL-044-08: one Audio section; the selects belong to the profile form (Apply ⟳), their values are endpoint IDs.
const audioSettings=block('settings-audio','Audio &#10227;',radioSection,'<div class="op-audio-input"></div><div class="op-input-meter"><span>Rx level <strong>Unknown</strong></span><div></div></div><div class="op-audio-output"></div><div id="tx-level" hidden><p><button type="button" id="tx-level-set">Set level</button> <span id="tx-level-line" role="status"></span></p><p id="tx-meters" class="op-muted" role="status" hidden></p><label id="tx-level-manual" hidden>Tx level (no ALC over CI-V) <input id="tx-level-slider" type="range" min="-40" max="0" step="1"></label></div><p id="audio-recommend" hidden><span id="audio-recommend-text"></span> <button type="button" id="audio-use-radio">Use IC-7300 audio</button></p><p id="audio-list-status" class="op-muted" role="status"></p>');
for(const [id,slot] of [['audio-input','.op-audio-input'],['audio-output','.op-audio-output']]){const select=document.getElementById(id);select.setAttribute('form','settings');audioSettings.querySelector(slot).append(select.closest('label'));}
for(const type of ['input','change'])audioSettings.addEventListener(type,event=>{if(event.target.form===serverForm)serverForm.dispatchEvent(new Event(type));});
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
localPreferences.innerHTML='<label>Waterfall link <select id="display-profile"><option value="detail">Detailed (fast link, up to 10 KiB/s per viewer)</option><option value="thin">Thin (32 kbit/s link)</option><option value="off">Off</option></select></label><div id="display-levels"><label class="op-check"><input id="display-flatten" type="checkbox"> Flatten (even out the passband across frequency)</label><label class="op-check"><input id="display-spectrum" type="checkbox"> Show spectrum line</label><output id="bin-readout" aria-live="polite">Select a bin with pointer or arrow keys</output></div>';
panel.append(document.querySelector('#signal-meta'));
displaySettings.append(localPreferences);
// #50 WstxBandActivity::BandActivityColours: WSJT-X 3.3 DecodeHighlightingModel slots in its priority order;
// only interesting stations are coloured (operator 2026-11-03, unlike WSJT-X: no CQ slot, New call on by default).
// A slot without data (cty.dat flags #55; grids, LotW) stays inactive until a record carries it. Worked before: none.
const bandSlots=[['mycall','My call',true],['new_continent','New continent',true],['new_continent_band','New continent on band',true],['new_cq_zone','New CQ zone',true],['new_cq_zone_band','New CQ zone on band',true],['new_itu_zone','New ITU zone',false],['new_itu_zone_band','New ITU zone on band',false],['new_dxcc','New DXCC',true],['new_dxcc_band','New DXCC on band',true],['new_grid','New grid',false],['new_grid_band','New grid on band',false],['new_call','New call',true],['new_call_band','New call on band',true],['lotw','LotW user',false]];
const bandFlags=bandSlots.map(([k])=>k).filter(k=>k.startsWith('new_'));
const bandColours=document.createElement('fieldset');bandColours.id='band-colours';bandColours.className='op-server-fieldset';
bandColours.innerHTML='<legend>Band Activity colours (WSJT-X)</legend>'+bandSlots.map(([k,label])=>`<label class="op-check"><input type="checkbox" data-hl-slot="${k}"> <span class="op-swatch" data-hl-swatch="${k}"></span>${label}</label>`).join('');
displaySettings.append(bandColours);
function bandColoursApply(){
  let saved=null;try{saved=JSON.parse(localStorage.getItem('wstx.band-colours.v1'));}catch{}
  const on=bandSlots.filter(([k,,d])=>typeof saved?.[k]==='boolean'?saved[k]:d).map(([k])=>k);
  // WstxSettings::ContestView: with a contest in force only my call keeps its slot; the rest is the all-time log.
  document.querySelector('#band-activity').dataset.hlOn=(window.wstxContestOn?on.filter(k=>k==='mycall'):on).join(' ');
  for(const box of bandColours.querySelectorAll('[data-hl-slot]'))box.checked=on.includes(box.dataset.hlSlot);
  for(const row of document.querySelectorAll('#band-activity tr[data-sequence]'))activityWhy(row);
}
bandColours.addEventListener('change',()=>{const value=Object.fromEntries([...bandColours.querySelectorAll('[data-hl-slot]')].map(b=>[b.dataset.hlSlot,b.checked]));try{localStorage.setItem('wstx.band-colours.v1',JSON.stringify(value));}catch{}bandColoursApply();});
bandColoursApply();
secondary('recorded-input','Recordings and replay',panel,expertSection).open=true;
expertSection.insertAdjacentHTML('afterbegin','<p class="op-muted">Diagnostics that are not needed while operating.</p>');
const sliders=document.createElement('div');sliders.id='presentation-sliders';sliders.className='op-display-controls';
sliders.innerHTML='<label title="WSJT-X Zero: moves the whole colour scale; the noise floor sits lower or higher">Sensitivity <input id="display-sensitivity" type="range" min="-30" max="30" step="1" value="0" aria-label="Waterfall sensitivity (zero)"><output id="sensitivity-value">+0 dB</output></label>'+'<label title="WSJT-X Gain: the dB span from dark blue to red">Range <input id="display-range" type="range" min="10" max="80" step="1" value="50" aria-label="Waterfall range (gain)"><output id="range-value">50 dB</output></label>'+'<label title="Scroll speed in CSS pixels per source second. Replay and received rows per second do not change.">Speed <input id="display-speed" type="range" min="0.5" max="8" step="0.5" value="1" aria-label="Waterfall speed, Slow to Fast"><output id="speed-value">10 px/s</output></label>';
signal.querySelector('.op-signal-heading').append(sliders);
for(const child of [...controls.children]){if(child.matches('h1,.intro,footer'))child.remove();}
const loginView=document.createElement('section');loginView.id='login-view';loginView.className='op-login';loginView.setAttribute('aria-label','Station authorization');loginView.hidden=true;
loginView.innerHTML='<span class="op-eyebrow">WSTX / REMOTE STATION</span><h1>Authorize this browser</h1><p class="op-muted">Enter the station access token. The station is shown once this browser is authorized.</p>';
loginView.append(login);
function confirmAction(text,okLabel){return window.wstxConfirm?window.wstxConfirm(text,okLabel):Promise.resolve(true);}
main.append(stationBar,signal,strip,splitter,controls,drawer,loginView);
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
// #54 WstxSignalArea::DisplayLevels: a fixed dBFS-to-colour mapping (WSJT-X Wide Graph): no level follows the signal
// over time. displayBlack is the fixed -85 dBFS reference; nothing in this page changes it.
let displayBlack=-85, displayRange=50, flatten=false, spectrumLine=false, selectedBin=0, selectedRow=0, pointerColumn=null, pointerTime=null, sensitivity=0, speed=1, fallbackText='', detailRequest;
try{const saved=Number(localStorage.getItem('wstx.waterfall-speed.v1'));if(saved>=.5&&saved<=8&&Number.isInteger(2*saved))speed=saved;}catch{}
try{const zero=localStorage.getItem('wstx.waterfall-zero.v1'),range=localStorage.getItem('wstx.waterfall-range.v1'),z=Number(zero),r=Number(range);if(zero!==null&&Number.isInteger(z)&&z>=-30&&z<=30)sensitivity=z;if(range!==null&&Number.isInteger(r)&&r>=10&&r<=80)displayRange=r;flatten=localStorage.getItem('wstx.waterfall-flatten.v1')==='on';spectrumLine=localStorage.getItem('wstx.spectrum-line.v1')==='on';}catch{}
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
  document.querySelector('#display-range').value=displayRange;document.querySelector('#range-value').textContent=`${displayRange} dB`;
  document.querySelector('#display-speed').value=speed;document.querySelector('#speed-value').textContent=`${10*speed} px/s`;
  document.querySelector('#display-flatten').checked=flatten;document.querySelector('#display-spectrum').checked=spectrumLine;document.querySelector('#spectrum').hidden=!spectrumLine;
}
const storeDisplay=(key,value)=>{try{localStorage.setItem(key,value);}catch{}};
for(const id of ['display-sensitivity','display-range','display-speed'])document.querySelector(`#${id}`).addEventListener('input',event=>{
  const value=Number(event.target.value);if(!Number.isFinite(value))return;
  if(id==='display-sensitivity'){sensitivity=Math.max(-30,Math.min(30,Math.floor(value+.5)));storeDisplay('wstx.waterfall-zero.v1',String(sensitivity));}
  else if(id==='display-range'){displayRange=Math.max(10,Math.min(80,Math.floor(value+.5)));storeDisplay('wstx.waterfall-range.v1',String(displayRange));}
  else{speed=Math.max(.5,Math.min(8,Math.floor(2*value+.5)/2));try{localStorage.setItem('wstx.waterfall-speed.v1',String(speed));}catch{}}
  selectedRow=Math.max(0,Math.min(visibleCount()-1,selectedRow));pointerTime=null;updateSliders();paint();
});

function resetLevels(){selectedBin=0;selectedRow=0;pointerColumn=null;pointerTime=null;updateLevels();}
function updateLevels(){updateSliders();}
// The controls show the restored per-browser values at once, not only after the first snapshot.
updateSliders();
// Flatten (WSJT-X flat4 equivalent): per row, the lower envelope across frequency (20th
// percentile of 32 blocks, linearly interpolated) is subtracted and its median added back, so
// the passband shape evens out while the overall level stays; it never follows time.
function flattenLevels(levels){
  const B=levels.length,n=32,size=B/n,floor=[];
  for(let b=0;b<n;b++){const block=[...levels.slice(b*size,(b+1)*size)].sort((x,y)=>x-y);floor.push(block[Math.floor((size-1)*.2)]);}
  const middle=[...floor].sort((x,y)=>x-y)[n>>1],out=new Uint8Array(B);
  for(let k=0;k<B;k++){const at=Math.max(0,Math.min(n-1,(k+.5)/size-.5)),i=Math.min(n-2,Math.floor(at)),base=floor[i]+(floor[i+1]-floor[i])*(at-i);out[k]=Math.max(0,Math.min(120,Math.floor(levels[k]-base+middle+.5)));}
  return out;
}
const shown=row=>row?.levels?(flatten?row.flat??=flattenLevels(row.levels):row.levels):null;
for(const [id,key] of [['display-flatten','wstx.waterfall-flatten.v1'],['display-spectrum','wstx.spectrum-line.v1']])document.querySelector(`#${id}`).addEventListener('change',event=>{
  if(id==='display-flatten')flatten=event.target.checked;else spectrumLine=event.target.checked;storeDisplay(key,event.target.checked?'on':'off');updateSliders();split(upper);
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
  upper = Math.max(minimum,Math.min(maximum,value ?? Math.min(330,available-490))); // #37: room for the fixed QSO pane (12 dialogue rows), Control and error field
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
// #61 CL-061-05: a run of Tx rows takes one thin band of this height, whatever its source time.
const TX_BAND_CSS_PX=4;
function timeProjection(H=waterfall.height,C=waterfall.getBoundingClientRect().height){
  const groups=Array(H),T=(rows.at(-1)?.end_frame??0)/12000,scale=10*speed*H/Math.max(C,1),txRuns=[];
  let count=0,shift=0;
  const fill=(from,to,newest,oldest)=>{
    for(let y=Math.max(0,from);y<Math.min(H,to);y++){
      if(groups[y])groups[y][1]=oldest;else groups[y]=[newest,oldest];count=Math.max(count,oldest+1);
    }
  };
  for(let r=0;r<rows.length;r++){
    const row=rows.at(-1-r),top=Math.floor((T-row.end_frame/12000)*scale-shift);
    if(top>=H)break;
    if(row.tx){
      let oldest=r;while(rows.at(-2-oldest)?.tx)oldest++;
      const band=Math.max(1,Math.round(TX_BAND_CSS_PX*H/Math.max(C,1))),first=rows.at(-1-oldest).first_frame/12000,end=row.end_frame/12000;
      fill(top,top+band,r,oldest);
      shift+=(end-first)*scale-band;txRuns.push({end,first,top,shift});r=oldest;
    }else{
      const bottom=Math.floor((T-row.first_frame/12000)*scale-shift);
      fill(top,Math.max(top+1,bottom),r,r);
    }
  }
  // The one mapping of source time to canvas row: a time inside a Tx run lies on its band.
  const rowOf=t=>{let before=0;for(const run of txRuns){if(t>=run.end)break;if(t>run.first)return run.top;before=run.shift;}return Math.floor((T-t)*scale-before);};
  return {groups,count,T,capacity:C/(10*speed),txRuns,rowOf,elided:shift/scale};
}
function visibleCount(){return timeProjection().count;}
function groupLevels(first,last,B){
  const q=new Uint8Array(B);
  for(let r=first;r<=last;r++){
    const native=shown(rows.at(-1-r));if(!native)return null;
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
  const projection=timeProjection(),nativeY=projection.rowOf(row.end_frame/12000),group=projection.groups[pointerTime===null?Math.max(0,Math.min(H-1,nativeY)):pointerTime];
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
        const row=rows.at(-1);if(!row?.levels||row.tx||c.hidden)continue;const values=project(shown(row)),E=effectiveBlack();
        ctx.strokeStyle='rgb(180 245 220)';ctx.lineWidth=Math.max(1,devicePixelRatio);ctx.beginPath();
        values.forEach((q,k)=>{const x=Math.floor(k*c.width/values.length),y=Math.max(0,Math.min(c.height-1,(120-q)*c.height/(-E)));k?ctx.lineTo(x,y):ctx.moveTo(x,y);});ctx.stroke();
      }else{
        const W=c.width,H=c.height,projection=timeProjection(H,box.height),R=projection.count;
        if(R){
          const image=ctx.createImageData(W,H),lut=Array.from({length:121},(_,q)=>[...paletteRGB((q-120-effectiveBlack())/displayRange),255]);
          let previous='',line;
          for(let y=0;y<H;y++){
            const group=projection.groups[y],key=group?group.join(','):'none';
            if(key!==previous){
              previous=key;line=new Uint8ClampedArray(W*4);const native=group?groupLevels(...group,B):null,values=native?project(native):null;
              // #61 CL-061-04: rows of a Tx period are Tx rows, never received silence.
              if(group&&rows.slice(rows.length-1-group[1],rows.length-group[0]).some(r=>r.tx)){for(let x=0;x<W;x++)line.set([90,20,30,255],x*4);}
              else if(!values){for(let x=0;x<W;x++)line.set(group?[96,96,96,255]:[0,0,12,255],x*4);}
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
        c.setAttribute('aria-label',`Waterfall, visible source time ${R?`${low.toFixed(1)} to ${high.toFixed(1)} seconds`:''}; newest top, grey groups are unknown, a thin dark red band is a Tx period; arrow keys select native bins and rows`);
        const ruler=document.querySelector('#time-ruler');ruler.replaceChildren();
        if(last){
          const latest=projection.T,times=[latest];let previousY=0;
          // #61 CL-061-05: no label inside a collapsed Tx run; the times beyond it stay exact.
          for(let t=Math.floor(latest/5)*5;t>=Math.max(0,latest-projection.capacity-projection.elided);t-=5){if(projection.txRuns.some(run=>t<run.end&&t>run.first))continue;const y=projection.rowOf(t)/devicePixelRatio;if(y-previousY>=16){times.push(t);previousY=y;}}
          for(const t of times){const label=document.createElement('span');label.textContent=`${t.toFixed(1)}s`;label.style.top=`${projection.rowOf(t)/devicePixelRatio}px`;ruler.append(label);}
        }
        document.querySelector('#speed-value').title=`${projection.capacity.toFixed(1)} s viewport capacity; ${R?`observed source ${low.toFixed(1)}-${high.toFixed(1)} s`:'no observed history'}; replay/network rate unchanged`;
      }
    }
    const ruler=document.querySelector('#frequency-ruler');ruler.replaceChildren();
    const labelStep=500*Math.max(1,Math.ceil(parseFloat(getComputedStyle(ruler).fontSize)*4/Math.max(1,ruler.clientWidth/6)));
    for(let f=0;f<=3000;f+=100){const tick=document.createElement('span');tick.style.left=`${wstxWaterfallAxis.x(f,ruler)}px`;tick.className=f%500?'minor':'major';if(f===0||f===3000||f%labelStep===0)tick.append(Object.assign(document.createElement('b'),{textContent:String(f)}));ruler.append(tick);}
    window.wstxFreeTxSlotMarks?.();
    const legend=document.querySelector('#level-legend'),E=effectiveBlack(),R=visibleCount(),low=R?rows.at(-R).first_frame/12000:0,high=R?rows.at(-1).end_frame/12000:0;
    legend.textContent=`0-3000 Hz | ${B===1024?'2.93 Hz/bin':'23.44 Hz/group'} | WF ${E} to ${E+displayRange} dBFS | Window ${timeProjection().capacity.toFixed(1)} s | Observed ${low.toFixed(1)}-${high.toFixed(1)} s`;
    legend.title=B===1024?'Detailed: 2.9296875 Hz native bins; 5 rows/s; 4096/12000 = 0.341333 s Hann window support':'Thin: 23.4375 Hz groups; 1 row/s; 2048/12000 s Hann window support';
    legend.setAttribute('aria-label',`${legend.textContent}; ${legend.title}`);
    document.querySelector('#spectrum').title=`Spectrum line scale ${effectiveBlack()} to 0 dBFS`;
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
    // #74 PushedStationState: a reply of another boot than the browser's is discarded.
    if(profileData&&data.boot_id!==profileData.boot_id)return;
    const previousImport=snapshot?.import?.id,previousGeneration=snapshot?.generation;
    if(identity(data)!==identity(snapshot)&&!(data.job?.kind==='live'&&snapshot?.job?.kind==='live'&&data.boot_id===snapshot.boot_id)){rows=[];resetLevels();paint();}snapshot=data; // #61: receiveSync decides a live identity change
    if(data.job?.kind!=='live'&&live?.job){live=undefined;resultRows=[];resultView=null;activityHistory=[];renderResults();receiveShow();}
    if(previousImport && !data.import && previousGeneration===data.generation){
      try{const outcome=await request(`/recording/imports/${previousImport}`);if(!stationContext(current,authEpoch))return;importOutcome={...outcome,generation:data.generation};}catch{if(current===socket)progress.textContent='Import outcome unavailable · current source state refreshed';}
    }
    show();
    if(subscribedSocket!==current && current.readyState===WebSocket.OPEN) {subscribedSocket=current;subscribe(current);}
  } catch(error){if(current===socket){statusText.textContent=`Recording state unavailable · ${error.message}`;if(subscribedSocket===current)disconnect(current,'recording-sync-failed');}} finally{syncPending=false;if(syncAgain){syncAgain=false;sync(socket);}}
}
addEventListener('station-ready',event => {if(subscribedSocket!==event.detail || snapshot?.boot_id!==profileData.boot_id)sync(event.detail);});
// WstxStationLink::PushedStationState (#74): a new boot drops the recording and live receive
// state of the previous boot at once; both show their freshly loaded form until the new boot's reads.
addEventListener('station-boot',()=>{
  snapshot=undefined;importOutcome=undefined;rows=[];resetLevels();paint();
  live=undefined;resultRows=[];resultView=null;activityHistory=[];renderResults();receiveShow();show();
});
addEventListener('station-stale',()=>{statusText.textContent='Disconnected · recording data stale';subscribedSocket=undefined;});
addEventListener('station-message',event => {
  const {message,current}=event.detail;
  if(current!==socket)return;
  if(message.type==='recording.state') {
    // Pushed on change (RecordingReceive, PushedStationState): read the snapshot only for what the event does not carry.
    if(!snapshot)return;
    const d=message.data,running=d.import??null,shown=snapshot.import??null;
    if(d.generation!==snapshot.generation || d.state!==(snapshot.job?.state??null) || d.source_id!==(snapshot.job?.kind==='live'?snapshot.job.source_id:(snapshot.recording?.id??null)) || d.job_id!==(snapshot.job?.id??null)) sync(current);
    else if(!uploading){
      if(running?.id!==shown?.id)sync(current); // the event carries the whole import: only another or an ended one needs the snapshot
      else if(running){snapshot.import={...shown,...running};show();}
    }
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
  if(Object.keys(message).sort().join(',')!=='data,type,v'||message.v!==1){stationData('waterfall',false);return;}
  const keys=['boot_id','source_id','job_id','generation','sequence','first_frame','end_frame',detail?'levels_b64':'levels'].sort().join(',');
  // #61 CL-061-04: a live row of a Tx period carries tx true.
  if(Object.keys(f).filter(k=>!(k==='tx'&&f.tx===true&&currentLive)).sort().join(',')!==keys){stationData('waterfall',false);return;}if(!Number.isSafeInteger(f.sequence)||f.sequence<0||(!currentLive&&f.sequence>=cap)||!Number.isSafeInteger(f.first_frame)||!Number.isSafeInteger(f.end_frame)||f.first_frame!==f.sequence*interval||f.end_frame<=f.first_frame)return;
  if(currentLive ? f.end_frame!==f.first_frame+interval : (!snapshot.recording||f.first_frame>=snapshot.recording.frames||f.end_frame!==Math.min(f.first_frame+interval,snapshot.recording.frames)))return;
  let values=f.levels;
  if(detail){
    if(typeof f.levels_b64!=='string'||f.levels_b64.length!==1368||!/^[A-Za-z0-9+/]{1366}==$/.test(f.levels_b64))return;
    try{const raw=atob(f.levels_b64);if(raw.length!==1024||btoa(raw)!==f.levels_b64)return;values=Uint8Array.from(raw,c=>c.charCodeAt(0));}catch{return;}
  }
  if((!detail&&!Array.isArray(values))||values.length!==B||!values.every(q=>Number.isInteger(q)&&q>=0&&q<=120))return;
  const previous=rows.at(-1)?.sequence??-1;if(f.sequence<=previous)return;
  // #54: live Thin is paced to one row per 2 s, so one or two missing sequences are drawn with the next row (held); longer runs are real gaps.
  const held=!detail&&currentLive&&previous>=0&&f.sequence-previous<=3;
  // #61 CL-061-05: a row missing between two Tx rows of one Tx period is a Tx row, not a grey gap.
  const txGap=f.tx===true&&(held||(rows.at(-1)?.tx===true&&f.first_frame-rows.at(-1).end_frame<=90000));
  for(let sequence=Math.max(previous+1,f.sequence-cap+1);sequence<f.sequence;sequence++)rows.push({sequence,first_frame:sequence*interval,end_frame:currentLive?(sequence+1)*interval:Math.min((sequence+1)*interval,snapshot.recording.frames),levels:held?Uint8Array.from(values):null,held,tx:txGap});
  const row={...f,levels:Uint8Array.from(values),tx:f.tx===true};stationData('waterfall',true);rows.push(row);rows=rows.slice(-cap);paint();

  if(currentLive){live.job.processed_frames=Math.max(live.job.processed_frames,f.end_frame);live.source.next_frame=Math.max(live.source.next_frame,f.end_frame);}
  else snapshot.job.processed_frames=f.end_frame;
  show();
});
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

let live,liveFailed=false,resultsAnnounced=null,livePending=false,liveAgain=null,resultPending=false,resultFailed=false,lastResultStart=-Infinity,resultCursor=0,resultRows=[],historyIncomplete=false,mutationPending=false,uncertainMutation=false,receiveFailure='';
let operatingState=null,operatingSupported=null,operatingFailure='',operatingReadPending=false,operatingReadAgain=false,operatingEpoch=0,operatingUnknown=null,operatingIntent=null,operatingSocket=null;
// What this socket's selection.state events hold (WstxStationCommands::SelectionStateEvent).
let operatingHeld=null,operatingHeldSocket=null;
let catStatus=null,catPending=false,catAgain=false,catConfirming=false;

// Mutations supersede earlier reads; accepted snapshots supersede pending pages.
let receiveMutationEpoch=0,liveRevision=0,resultView=null,activityHistory=[],ownReceiveMutationAt=-Infinity,liveOperatingRevision=null,liveEventAt=-Infinity;
let lastReceiveReady=null;
let activitySortProfile=null,activitySortField='value',activitySortDirection='desc';
const liveIdentity=s=>s?`${s.profile_id}/${s.boot_id}/${s.source?.id??''}/${s.job?.id??''}/${s.generation}`:'';const resultsUnread=()=>resultFailed||liveFailed||resultsAnnounced!==null||(!!resultView&&resultCursor<resultView.next_sequence)||(Number.isSafeInteger(live?.job?.next_sequence)&&live.job.next_sequence>resultCursor)||(!!live?.job?.latest_decode&&live.job.latest_decode.id!==resultView?.id);const resultsDue=()=>profileSelect.value==='detail'&&!resultFailed&&!!resultView&&resultCursor<resultView.next_sequence; // #57 CL-057-01: Detailed fetches a published view's records at once, page after page; the next page follows a page that moved the cursor; Thin/Off, the idle poll and a failed read stay at most once/4 s.
const receiveStatus=document.querySelector('#receive-status');
function validPeriodTime(value,mode){
  return typeof value==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$/.test(value)&&Number.isFinite(Date.parse(value))&&new Date(Date.parse(value)).toISOString().slice(0,19)===value.slice(0,19)&&(value.endsWith('.0000000Z')||(mode==='ft4'&&value.endsWith('.5000000Z')))&&Date.parse(value)%(mode==='ft8'?15000:7500)===0;
}
function validLatestDecode(view,mode,end){
  if(view===null)return true;
  // #61 CL-061-04: a Tx period carries transmitted true (no attempt: an empty range, not complete).
  return view&&Object.keys(view).filter(k=>!(k==='transmitted'&&view.transmitted===true&&view.period_start_utc!==null&&!view.complete&&view.first_sequence===view.next_sequence)).sort().join(',')==='complete,first_sequence,id,next_sequence,period_start_utc'&&
    ['id','first_sequence','next_sequence'].every(k=>Number.isSafeInteger(view[k])&&view[k]>=0)&&view.id>0&&
    view.first_sequence<=view.next_sequence&&view.next_sequence<=end&&typeof view.complete==='boolean'&&
    (view.period_start_utc===null||validPeriodTime(view.period_start_utc,mode));
}
function applyLatestDecode(view,first){
  if(resultView&&view&&view.id<resultView.id)return false;
  if(resultView&&view&&view.id===resultView.id){
    // #47: a later window of the same correlated period extends its view in place (same id,
    // period and first_sequence): next_sequence only grows and complete only turns true. Keep
    // the rows and cursor; an older snapshot/page of that view is a prefix. Anything else is an error.
    const same=view.period_start_utc!==null&&view.period_start_utc===resultView.period_start_utc&&view.first_sequence===resultView.first_sequence;
    if(!same&&['first_sequence','next_sequence','period_start_utc','complete'].some(k=>view[k]!==resultView[k]))throw new Error('Changed decode descriptor');
    const grown=view.next_sequence>=resultView.next_sequence&&(view.complete||!resultView.complete),prefix=view.next_sequence<=resultView.next_sequence&&(resultView.complete||!view.complete);
    if(!grown&&!prefix)throw new Error('Changed decode descriptor');
    if(grown){resultView=view;renderResults();}
    return true;
  }
  if(resultView===null&&view===null)return true;
  // #37/#57: only the latest even and odd periods; the replaced period stays below only when it is the other parity.
  const parity=p=>p&&live?.job?Math.round(Date.parse(p)/(live.job.mode==='ft4'?7500:15000))%2:null;
  const other=parity(resultView?.period_start_utc)!==null&&parity(view?.period_start_utc)!==null&&parity(resultView.period_start_utc)!==parity(view.period_start_utc);
  // #61 CL-061-03: the station's Tx period has nothing to show; the period kept below it stays.
  const transmitted=resultView?.transmitted===true;
  activityHistory=resultView===null?activityHistory.filter(h=>Date.parse(view?.period_start_utc??'')-Date.parse(h.period??'')===(live.job.mode==='ft4'?7500:15000)).slice(0,1):transmitted?activityHistory.slice(0,1):other&&resultRows.length?[{id:resultView.id,period:resultView.period_start_utc,mode:live.job.mode,context:liveIdentity(live),rows:[...resultRows]}]:[];
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
    capabilities[0].textContent=live.audio.state==='running'?`Running · ${live.audio.device_name??'selected input'}`:`Unavailable · ${live.audio.error??live.audio.state}`;
    capabilities[2].textContent=live.job&&live.job.mode!=='spectrum'?`${live.job.mode.toUpperCase()} · ${live.job.state}`:'Unavailable · receive stopped';
    document.querySelector('#receive-generation').textContent=`Receive generation ${live.generation} · source ${live.source?.id??'none'} · job ${live.job?.id??'none'}`;
    const c=live.clock;document.querySelector('#clock-detail').textContent=`Clock ${c.basis} · ${c.correlated?`receive periods correlated to UTC anchor ${c.utc_anchor}, uncertainty ${c.uncertainty_ns} ns`:'receive periods not correlated to UTC'} · external accuracy ${c.external_accuracy}`;
    const focus=document.querySelector('#rx-focus .op-contact-identity');
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
  const epoch=receiveMutationEpoch,authEpoch=authorization?.snapshot().epoch,started=performance.now();
  try{
    const data=await request('/receive');
    if(!stationContext(current,authEpoch)||epoch!==receiveMutationEpoch)return;
    if(!validLiveSnapshot(data)){stationData('receive',false);throw new Error('Invalid receive snapshot');}stationData('receive',true);
    if(data.profile_id!==profileData.profile_id||data.boot_id!==profileData.boot_id||(data.boot_id===live?.boot_id&&data.generation<live.generation))return;// a new boot counts its generations from 0
    if(liveIdentity(data)===liveIdentity(live)&&started<liveEventAt)return;// may be older than a receive.state already taken
    if(liveIdentity(data)!==liveIdentity(live)){
      const carry=lossEpoch(data);activityHistory=carry?[...(resultRows.length?[{id:resultView.id,period:resultView.period_start_utc,mode:live.job.mode,context:liveIdentity(live),rows:[...resultRows]}]:[]),...activityHistory].slice(0,2):[];
      resultRows=[];resultView=null;resultCursor=data.job?.first_sequence??0;historyIncomplete=false;if(carry)keepWaterfall();else if(data.job||live?.job){rows=[];resetLevels();paint();}
      renderResults();
    }
    live=data;liveOperatingRevision=operatingState?.operating_revision??null;liveRevision++;applyLatestDecode(data.job?.latest_decode??null,data.job?.first_sequence??0);uncertainMutation=false;receiveFailure='';liveFailed=false;receiveShow();show();
  }catch(error){if(current===socket)liveFailed=true;if(current===socket&&epoch===receiveMutationEpoch){receiveFailure=`Live receive unavailable · ${error.message}`;receiveStatus.textContent=receiveFailure;}}
  finally{livePending=false;const again=liveAgain;liveAgain=null;if(again!==null&&again===receiveMutationEpoch)receiveSync(socket);else if(resultsDue())receiveResults();}
}
function activityOrdering(records=resultRows){
  const id=displayPreferenceId();
  if(id&&id!==activitySortProfile){activitySortProfile=id;activitySortField='value';activitySortDirection='desc';}
  for(const th of document.querySelectorAll('#band-activity th[data-sort]'))th.setAttribute('aria-sort',th.dataset.sort===activitySortField?(activitySortDirection==='asc'?'ascending':'descending'):'none');
  const key=r=>activitySortField==='frequency'?r.frequency_hz:activitySortField==='signal'?r.snr_db:activitySortField==='dt'?r.dt_seconds:r.text?.toUpperCase()??null;
  const missing=v=>v===null||v===undefined||v==='';
  return [...records].sort((a,b)=>{if(activitySortField==='value')return activityValue(a)-activityValue(b)||(missing(a.snr_db)!==missing(b.snr_db)?(missing(a.snr_db)?1:-1):missing(a.snr_db)?0:b.snr_db-a.snr_db)||a.sequence-b.sequence;// #55 CL-055-04: value, strongest SNR (unavailable last), decode order
    const left=key(a),right=key(b);
    if(missing(left)!==missing(right))return missing(left)?1:-1;
    const compared=missing(left)?0:typeof left==='number'?left-right:left<right?-1:left>right?1:0;
    return compared*(activitySortDirection==='asc'?1:-1)||a.sequence-b.sequence;
  });
}
function sortBy(button){
  if(button.dataset.sort===activitySortField){if(activitySortField!=='value')activitySortDirection=activitySortDirection==='asc'?'desc':'asc';}
  else{activitySortField=button.dataset.sort;activitySortDirection=['signal','value'].includes(activitySortField)?'desc':'asc';}
  renderResults();
}
document.querySelector('#band-activity thead').addEventListener('click',event=>{const th=event.target.closest('th[data-sort]');if(th)sortBy(th);});
document.querySelector('#band-activity thead').addEventListener('keydown',event=>{const th=event.target.closest('th[data-sort]');if(th&&(event.key==='Enter'||event.key===' ')){event.preventDefault();sortBy(th);}});
function renderResults(){
  const ordered=activityOrdering(resultRows);
  const body=document.querySelector('#band-activity tbody');
  const loading=resultView&&resultCursor<resultView.next_sequence;
  // #61 CL-061-03: the station's Tx period (CL-061-04) shows its marker row and no empty block;
  // the receive period it replaced stays below its divider.
  const own=resultView?.transmitted===true,mode=live?.job?.mode;
  document.querySelector('#band-activity header .op-muted').textContent=own?`Tx \u00b7 ${mode?.toUpperCase()} period ${periodLabel(resultView.period_start_utc,mode)} UTC \u00b7 this station transmitted, no decode`:resultView?
    `Latest ${live?.job?.mode.toUpperCase()} period ${periodLabel(resultView.period_start_utc,live?.job?.mode)}${resultView.period_start_utc?' UTC':''} \u00b7 ${resultView.complete?'Attempt complete':'Partial'}${loading?' \u00b7 Loading results':''}${historyIncomplete?' \u00b7 Incomplete history':''}`:'Latest decode period';
  document.querySelector('#band-activity header .op-muted').title=resultView?.period_start_utc?'Timing relative to station system clock; external UTC accuracy unknown. DT positive: late; negative: early.':'Station clock correlation unavailable until supplied by this source.';
  const count=own?activityHistory.reduce((n,h)=>n+h.rows.length,0):resultRows.length;
  document.querySelector('#band-activity .op-count').textContent=`${count} message${count===1?'':'s'}`;
  if(own){
    const marker=document.createElement('tr'),cell=document.createElement('td');marker.className='ba-tx';marker.dataset.period='tx';marker.setAttribute('role','row');
    cell.colSpan=7;cell.setAttribute('role','cell');cell.textContent=`Tx ${periodLabel(resultView.period_start_utc,mode)} \u00b7 this station transmitted \u00b7 no decode`;marker.append(cell);
    body.replaceChildren(marker);window.wstxRenderHistory?.(body);partnerFirst(body);return;
  }
  if(!resultRows.length){
    body.innerHTML='<tr><td colspan="7" class="empty-messages"><strong></strong><span></span></td></tr>';
    const decoder=live?.job&&['ft4','ft8'].includes(live.job.mode),job=live?.job;
    let heading='Decoder unavailable',message='No decoded messages are available from this server.';
    if(decoder){
      const mode=job.mode.toUpperCase();
      heading=job.state==='running'?(connection.dataset.state==='connected'?`Listening for ${mode}`:`${mode} receive status stale`):job.state==='cancelling'?`Stopping ${mode} receive`:`${mode} receive ${job.state}`;
      message=['running','cancelling'].includes(job.state)?'No verified messages decoded yet.':'No verified messages were decoded.';
      if(resultView&&!own){heading=loading?'Loading latest decode':resultView.complete?'No stations decoded':'No stations decoded in partial attempt';message=loading?'Latest-period results are being received.':'No verified stations were decoded in this period.';}
    }
    body.querySelector('strong').textContent=heading;body.querySelector('span').textContent=message;window.wstxRenderHistory?.(body);partnerFirst(body);return;
  }
  body.replaceChildren();
  for(const record of ordered)body.append(activityRow(record,'latest',liveIdentity(live),live.job.mode));
  window.wstxRenderHistory?.(body);partnerFirst(body);
}
// #50 CL-050-08: the partner rows of every shown period go to the top, newest period first, above one
// red stripe; a period divider left without rows is dropped.
function partnerFirst(body){
  const rows=[...body.querySelectorAll('tr.ba-partner')];if(!rows.length)return;
  const stripe=document.createElement('tr');stripe.className='ba-divider ba-partner-stripe';stripe.setAttribute('role','row');stripe.setAttribute('aria-label','End of the QSO partner rows');
  const cell=document.createElement('td');cell.colSpan=7;cell.setAttribute('role','cell');stripe.append(cell);body.prepend(...rows,stripe);
  for(const divider of body.querySelectorAll('tr.ba-divider:not(.ba-partner-stripe)')){const next=divider.nextElementSibling;if(!next||next.classList.contains('ba-divider'))divider.remove();}
}
function activityRow(record,period,context,mode){
  const labels=[...document.querySelectorAll('#band-activity th')].map(th=>th.textContent);
  const row=document.createElement('tr');row.setAttribute('role','row');row.dataset.resultId=`${context}/${record.sequence}`;row.dataset.sequence=String(record.sequence);row.dataset.period=period;
  const f=record.fields,decoded=record.status==='decoded',to=recordTo(f),my=(profileData?.settings?.callsign??'').trim().toUpperCase();
  // #50 BandActivityColours: the slots this row matches; the new_* slots from the #55 record flags of
  // every decoded sender (operator decision CL-055-04; WSJT-X: CQ/QRZ lines only). No CQ slot (#50).
  // #50 CL-050-08 BandActivityScheme (operator 2026-11-04): the QSO partner's rows carry the partner
  // marker and no slot; a row to my call from another station is red as a whole; a CQ/QRZ of interest
  // is coloured as a whole; any other row of interest colours only its sender's call.
  const from=decoded?recordFrom(f)?.replace(/^<(.+)>$/,'$1').toUpperCase()??null:null,partner=window.wstxPartner?.()??null,isPartner=!!(partner&&from===partner);
  const hl=decoded&&!isPartner?bandFlags.filter(k=>record.flags?.[k]===true):[];row.dataset.value=String(activityValue(record));
  if(decoded&&/^CQ\b/.test(record.text))row.classList.add('ba-cq');
  if(isPartner)row.classList.add('ba-partner');
  else if(decoded&&my&&to===my){row.classList.add('ba-tome');hl.push('mycall');}
  const cqLike=/^(CQ|QRZ)\b/.test(record.text)||(f?.type==='nonstandard'&&f.cq);
  const senderOnly=hl.length>0&&!row.classList.contains('ba-tome')&&!cqLike;
  // #37 (operator 2026-11-04): a row of a QSO between others cannot start a contact for me.
  if(from)row.dataset.sender=from;
  if(from&&!cqLike&&to!==my)row.dataset.foreign='true';
  if(senderOnly)row.classList.add('ba-sender');
  if(hl.length)row.dataset.hl=hl.join(' ');
  const grid=record.fields?.exchange?.kind==='grid'?record.fields.exchange.value:null,km=grid?window.wstxDistanceKm?.(profileData?.settings?.locator,grid)??null:null,dx=record.dxcc,approx=km===null&&Number.isInteger(dx?.km);
  if(dx?.cont)row.dataset.continent=dx.cont;
  if(!isPartner)row.dataset.reasons=JSON.stringify(activityHover(record));
  if(record.worked){row.dataset.worked=record.worked.status;row.dataset.workedOn=record.worked.on;}
  const cells=[periodLabel(record.period_start_utc,mode),record.snr_db===null?'\u2014':record.snr_db.toFixed(1),record.dt_seconds===null?'\u2014':`${Math.abs(record.dt_seconds)<0.05?'+':record.dt_seconds<0?'-':'+'}${Math.abs(record.dt_seconds).toFixed(1)}`,record.frequency_hz.toFixed(1),decoded?record.text:`Payload ${record.status}`,dx?dx.name:'\u2014',approx?`~${dx.km} km`:km===null?'\u2014':`${km} km`];
  for(const [index,text] of cells.entries()){
    const cell=document.createElement('td');cell.setAttribute('role','cell');cell.dataset.label=labels[index];cell.textContent=text;
    if(index===4){cell.dataset.col='message';
      // The sender's call word (also in < >) of a sender-only row is its own span; the text stays the message.
      const words=text.split(' '),at=senderOnly&&from?[...words.keys()].sort((a,b)=>(a===0)-(b===0)).find(i=>words[i].replace(/^<(.+)>$/,'$1').toUpperCase()===from):undefined;
      if(at!==undefined){const mark=document.createElement('span');mark.className='ba-from';mark.textContent=words[at];cell.replaceChildren(words.slice(0,at).map(w=>w+' ').join(''),mark,words.slice(at+1).map(w=>' '+w).join(''));}
      // #56: WSJT-X's a-priori marker (aN), shown after the message but not part of its text.
      if(decoded&&Number.isInteger(record.a_priori)){cell.dataset.ap=`a${record.a_priori}`;cell.title=`A-priori decode (WSJT-X a${record.a_priori})`;}}
    if(index===5&&dx)cell.title=`${dx.name} \u00b7 ${dx.cont} \u00b7 CQ zone ${dx.cq} \u00b7 ITU zone ${dx.itu} (cty.dat)`;if(index===6&&approx)cell.title='Approximate: from the country position (cty.dat), no grid in the message';
    row.append(cell);
  }
  activityWhy(row);return row;
}
function validRecord(r){
  return r&&Object.keys(r).filter(k=>!(k==='dxcc'&&validDxcc(r.dxcc))&&!(k==='flags'&&validFlags(r.flags))&&!(k==='worked_status'&&['not_worked','worked_other_band_or_mode','worked_this_band_and_mode'].includes(r.worked_status))&&!(k==='a_priori'&&Number.isInteger(r.a_priori)&&r.a_priori>=1&&r.a_priori<=6&&r.status==='decoded')).sort().join(',')==='dt_seconds,fields,frequency_hz,i3,n3,payload77,period_start_utc,sequence,snr_db,start_frame,status,text'&&
    Number.isSafeInteger(r.sequence)&&r.sequence>=0&&Number.isSafeInteger(r.start_frame)&&r.start_frame>=0&&
    ((r.period_start_utc===null&&r.dt_seconds===null)||(validPeriodTime(r.period_start_utc,live.job.mode)&&Number.isFinite(r.dt_seconds)&&r.dt_seconds>=-(live.job.mode==='ft8'?7.5:3.75)&&r.dt_seconds<(live.job.mode==='ft8'?7.5:3.75)))&&
    Number.isFinite(r.frequency_hz)&&r.frequency_hz>=200&&r.frequency_hz<=3500&&
    (r.snr_db===null||(Number.isFinite(r.snr_db)&&r.snr_db>=-60&&r.snr_db<=60))&&
    typeof r.payload77==='string'&&/^[01]{77}$/.test(r.payload77)&&Number.isInteger(r.i3)&&r.i3>=0&&r.i3<=7&&
    (r.i3===0?Number.isInteger(r.n3)&&r.n3>=0&&r.n3<=7:r.n3===null)&&
    (r.status==='decoded'?typeof r.text==='string'&&/^[\x20-\x7e]{1,80}$/.test(r.text)&&r.fields&&typeof r.fields==='object'&&!Array.isArray(r.fields):['unsupported','invalid_payload'].includes(r.status)&&r.text===null&&r.fields===null);
}const FLAG_NAMES=['new_call','new_call_band','new_grid','new_grid_band','new_dxcc','new_dxcc_band','new_continent','new_continent_band','new_cq_zone','new_cq_zone_band','new_itu_zone','new_itu_zone_band'];function validDxcc(d){return !!d&&typeof d==='object'&&!Array.isArray(d)&&Object.keys(d).every(k=>['name','cont','cq','itu','km'].includes(k))&&typeof d.name==='string'&&/^[\x20-\x7e]{1,40}$/.test(d.name)&&['AF','AN','AS','EU','NA','OC','SA'].includes(d.cont)&&Number.isInteger(d.cq)&&d.cq>=0&&d.cq<=40&&Number.isInteger(d.itu)&&d.itu>=0&&d.itu<=90&&(d.km===undefined||(Number.isInteger(d.km)&&d.km>=0&&d.km<=20038));}function validFlags(f){return !!f&&typeof f==='object'&&!Array.isArray(f)&&Object.keys(f).length>0&&Object.entries(f).every(([k,v])=>FLAG_NAMES.includes(k)&&v===true);}
async function receiveResults(){
  if(resultPending||livePending||mutationPending||uncertainMutation||operatingReadPending||operatingBlocked()||refresh.disabled||connection.dataset.state!=='connected'||!live?.source||!['ft4','ft8'].includes(live.job?.mode))return;
  // #10 PushedStationState: Thin/Off read records of an announced or unread view at most once
  // per 4 s; with nothing announced or pending they wait for receive.state (the station pushes
  // each publication) and keep only a safety read at most once per 30 s.
  const now=performance.now();if(now-lastResultStart<(resultsDue()?0:resultsUnread()?4000:30000))return;
  resultPending=true;lastResultStart=now;const started=now;
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
    live.job.state=page.state;live.job.error=page.error;resultFailed=false;if(resultsAnnounced!==null&&started>=resultsAnnounced&&cursor>=page.next_sequence)resultsAnnounced=null;stationData('results',true);renderResults();receiveShow();
  }catch(error){resultFailed=true;if(current===socket&&context===liveIdentity(live)&&revision===liveRevision&&epoch===receiveMutationEpoch){receiveStatus.textContent=`Result state unavailable · ${error.message}`;if(/^Invalid|descriptor/.test(error.message))stationData('results',false);}}
  finally{resultPending=false;if(resultsDue()&&resultCursor!==cursor)setTimeout(receiveResults,0);}
}
async function receiveStart(){
  const active=live?.job&&['running','cancelling'].includes(live.job.state);
  if(!live||active||mutationPending||uncertainMutation||operatingBlocked()||!receiveInputConfigured())return;
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
// #44 CL-044-08: the pickers name the endpoints (GET /audio/endpoints); the ID is only a hover title and in Expert.
let audioView=null,audioRead=-Infinity,audioLoading=null,audioRevision=null;
const audioIds=document.createElement('dl');audioIds.id='audio-endpoint-ids';audioIds.innerHTML='<div><dt>Input</dt><dd id="audio-id-input">none</dd></div><div><dt>Output</dt><dd id="audio-id-output">none</dd></div>';
secondary('audio-ids','Audio endpoint IDs',audioIds,expertSection).open=true;
function audioOption(text,value,disabled=false){const option=new Option(text,value);if(value)option.title=value;option.disabled=disabled;return option;}
function audioRadio(){return [audioView?.inputs.find(e=>e.radio&&e.present),audioView?.outputs.find(e=>e.radio&&e.present)];}
function audioRender(){
  for(const [id,list] of [['audio-input',audioView?.inputs],['audio-output',audioView?.outputs]]){
    const select=document.getElementById(id),current=select.value,options=[audioOption('None','')];
    for(const e of list??[])options.push(audioOption(e.label,e.id,!e.present));
    if(current&&!options.some(o=>o.value===current))options.push(audioOption(audioView?'Unknown device · not present':'Saved device',current,!!audioView));
    select.replaceChildren(...options);select.value=current;
  }
  const saved=profileData?.settings.audio;
  document.getElementById('audio-id-input').textContent=saved?.input_device??'none';document.getElementById('audio-id-output').textContent=saved?.output_device??'none';
  const [input,output]=audioRadio(),radio=(input??output)?.radio;
  document.getElementById('audio-recommend').hidden=!radio;
  if(radio){document.getElementById('audio-recommend-text').textContent=`Recommended: ${input?.label??'no input matched'} / ${output?.label??'no output matched'}`;document.getElementById('audio-use-radio').textContent=`Use ${radio} audio`;}
}
function loadAudio(force=false){
  if(audioLoading||!profileData||(!force&&performance.now()-audioRead<5000))return audioLoading;
  audioRead=performance.now();const status=document.getElementById('audio-list-status');
  audioLoading=request('/audio/endpoints',{cache:'no-store'}).then(v=>{
    const entry=e=>e&&typeof e.id==='string'&&typeof e.label==='string'&&typeof e.present==='boolean';
    if(v?.v!==1||v.profile_id!==profileData?.profile_id||![v.inputs,v.outputs].every(l=>Array.isArray(l)&&l.every(entry)))throw new Error('invalid_listing');
    audioView=v;status.textContent='';
  }).catch(error=>{audioView=null;status.textContent=`Audio devices unavailable · ${error.message}`;}).finally(()=>{audioLoading=null;audioRender();});
  return audioLoading;
}
// A status refresh re-renders only; the listing is read again only for a new saved revision
// (a save) or Reload saved settings, so an open drawer adds no periodic traffic (Thin budget).
addEventListener('profile-fields',()=>{audioRender();const revision=profileData?JSON.stringify([profileData.boot_id,profileData.revision]):null,changed=audioRevision!==null&&revision!==audioRevision;audioRevision=revision;if(changed&&!drawer.hidden)loadAudio(true);});
document.querySelector('#settings-reload').addEventListener('click',()=>{if(!drawer.hidden)loadAudio(true);});
new MutationObserver(()=>{if(!drawer.hidden)loadAudio();}).observe(drawer,{attributes:true,attributeFilter:['hidden']});
document.getElementById('audio-use-radio').addEventListener('click',()=>{
  const [input,output]=audioRadio();
  for(const [id,e] of [['audio-input',input],['audio-output',output]])if(e){const select=document.getElementById(id);select.value=e.id;select.dispatchEvent(new Event('change',{bubbles:true}));}
  serverForm.requestSubmit();
});
function receiveReadyKey(profile){
  const uuid=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value);
  if(!profile||!uuid(profile.profile_id)||!uuid(profile.boot_id)||!Number.isSafeInteger(profile.revision)||profile.revision<0)return null;
  return JSON.stringify([profile.profile_id,profile.boot_id,profile.revision]);
}
function receiveReady(current){
  if(current!==socket||connection.dataset.state!=='connected')return false;
  const key=receiveReadyKey(profileData);
  if(key!==null){
    // WstxRecordingReceive: one read per socket and saved profile; a later status of the socket reads
    // nothing while receive.state holds the state, only after a failed read or an unknown outcome.
    if(lastReceiveReady?.socket===current&&lastReceiveReady.key===key&&!liveFailed&&!uncertainMutation)return false;
    // The synchronous receiveSync entry below necessarily starts or queues this
    // read under the same socket/connection checks; failed HTTP is not replayed.
    lastReceiveReady={socket:current,key};
  }
  receiveSync(current);return true;
}
addEventListener('station-ready',event=>receiveReady(event.detail));
addEventListener('station-stale',()=>{lastReceiveReady=null;receiveShow();receiveStatus.textContent='Disconnected · live receive data stale';});
addEventListener('station-message',event=>{const {current,message}=event.detail;if(current!==socket||message.type!=='receive.state')return;resultsAnnounced=performance.now();
  // WstxRecordingReceive: the event carries the job's progress and the audio; GET /receive only for a new identity or state.
  // After a socket's first event it holds the identity and only the audio, clock and job fields that changed.
  const e=message.data,carried=live?.job&&e&&e.boot_id===live.boot_id&&e.generation===live.generation&&e.job_id===live.job.id&&e.state===live.job.state&&e.source_id===(live.source?.id??null)&&Object.keys(e).every(k=>['profile_id','boot_id','generation','source_id','job_id','state','audio','clock','job'].includes(k));
  const held=carried&&{...live,audio:e.audio??live.audio,clock:{...live.clock,...e.clock},job:{...live.job,...e.job}};
  let shown=false;if(carried&&!mutationPending&&!uncertainMutation&&validLiveSnapshot(held)){try{live=held;liveEventAt=performance.now();liveOperatingRevision=operatingState?.operating_revision??null;if(e.job&&('latest_decode' in e.job||'first_sequence' in e.job))applyLatestDecode(held.job.latest_decode,held.job.first_sequence);receiveFailure='';stationData('receive',true);liveFailed=false;receiveShow();show();shown=true;}catch{}}
  if(!shown)receiveSync(current);else if(resultsDue())receiveResults();
  const d=message.data;if(snapshot&&d&&(d.generation!==snapshot.generation||d.job_id!==(snapshot.job?.id??null)||d.state!==(snapshot.job?.state??null)))sync(current);});
setInterval(receiveResults,250);
if(socket?.readyState===WebSocket.OPEN&&profileData)receiveReady(socket);// this script came after the socket's first status

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
  if(!operatingShape(s,'v,profile_id,boot_id,profile_revision,generation,operating_revision,snapshot_sequence,monotonic_ms,control,selection,available_bands,operation,cancellation,receive,radio')||s.v!==1||!operatingUuid(s.profile_id)||!operatingUuid(s.boot_id)||!['manual','cat','native'].includes(s.control))return false;
  for(const key of ['profile_revision','generation','operating_revision','snapshot_sequence','monotonic_ms'])if(!operatingCounter(s[key]))return false;
  const n=s.selection;
  if(!operatingShape(n,'mode,band,nominal_hz,origin,confirmed_command_id')||!operatingModeValid(n.mode)||!operatingNullable(n.band,v=>operatingBands.includes(v))||!operatingNullable(n.nominal_hz,operatingFrequency)||!['unknown','manual','cat_readback','native_readback'].includes(n.origin)||!operatingNullable(n.confirmed_command_id,operatingUuid)||(n.band===null)!==(n.nominal_hz===null))return false;
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
  const nominal=s.selection.nominal_hz===null?'Nominal frequency unknown':`Nominal ${(s.selection.nominal_hz/1e6).toFixed(6)} MHz · ${s.selection.origin==='manual'?'manual, actual rig unconfirmed':s.selection.origin==='native_readback'?'native slice readback at selection':'CAT readback at selection'}`;
  document.querySelector('#operating-radio').textContent=`${s.control==='native'?'Native':'CAT'} ${s.radio.state}${s.radio.error?' · '+s.radio.error:''} · ${observed} · ${nominal}`;
  const dial=document.querySelector('#op-dial');dial.value=frequency.value!==null?(frequency.value/1e6).toFixed(6):s.selection.nominal_hz!==null?(s.selection.nominal_hz/1e6).toFixed(6):'';dial.title=`${observed}. ${nominal}`;const fresh=connected&&frequency.confirmed;dial.dataset.fresh=String(fresh);dial.setAttribute('aria-label',frequency.value!==null?(fresh?'Observed dial frequency':'Last observed dial frequency, stale/unconfirmed'):'Nominal dial frequency, actual rig unconfirmed');
  const capabilities=document.querySelectorAll('#operating-capabilities dd');capabilities[1].textContent=!connected?'Unavailable · status stale':s.radio.state==='ready'?(s.control==='native'?'Ready · FlexRadio slice readback':'Ready · IC-7300 readback'):`Unavailable · ${s.radio.error??s.radio.state}`;
  const o=s.operation;
  operatingStatus.textContent=operatingFailure||(operatingUnknown?'Selection outcome unknown · refresh or press Monitor to cancel/fence before another action':mutationPending&&operatingIntent?'Selection request pending · waiting for server admission':o?`${o.result==='pending'?'Switching':o.phase} · ${o.requested.mode.toUpperCase()} ${o.requested.band}${o.error?' · '+o.error:''}`:`${s.selection.mode.toUpperCase()} · choose a band to establish nominal frequency`);
}
// A read or an event is accepted when it is not older than the state shown. Only an explicit
// read or the read after an unknown outcome (reconcile) can clear that outcome's barrier.
function operatingAccept(s,reconcile){
  if(operatingState?.boot_id===s.boot_id&&s.snapshot_sequence<operatingState.snapshot_sequence)return;
  const resolved=operatingUnknown&&reconcile&&(s.boot_id!==operatingUnknown.boot_id||s.operation?.command_id===operatingUnknown.command_id||s.operating_revision>operatingUnknown.base_revision);
  if(resolved)operatingUnknown=null;
  if(operatingIntent&&(s.operation?.command_id===operatingIntent.command_id||s.operating_revision>operatingIntent.base_revision))operatingIntent=null;
  const catKey=o=>o&&JSON.stringify([o.boot_id,o.profile_revision,o.radio.connection_generation,o.radio.state,o.radio.error]),changed=catKey(operatingState)!==catKey(s);
  operatingState=s;operatingSupported=true;if(changed||(!catStatus&&!catPending))catSync();if(resolved||operatingFailure.startsWith('Operating state stale')||operatingFailure==='Disconnected · operating data stale')operatingFailure='';
}
async function operatingSync(reconcile=false){
  if(connection.dataset.state!=='connected'||!profileData)return;
  if(operatingReadPending){if(reconcile)operatingReadAgain=true;return;}
  operatingReadPending=true;const epoch=operatingEpoch,current=socket,authEpoch=authorization?.snapshot().epoch;
  let answered=false;
  try{
    const response=await stationFetch('/receive/selection',{signal:AbortSignal.timeout(10000)}),text=await response.text();answered=true;
    if(epoch!==operatingEpoch||!stationContext(current,authEpoch)||connection.dataset.state!=='connected')return;
    let s;try{s=JSON.parse(text);}catch{throw new Error('Invalid operating snapshot');}
    if(response.status===404||response.status===400&&s.error?.code==='unsupported_version'||s&&typeof s.v==='number'&&s.v!==1){operatingSupported=false;operatingFailure='Operating controls unsupported by this server';return;}
    if(!response.ok)throw new Error(s.error?.code||'Operating state unavailable');
    if(new TextEncoder().encode(text).length>3072||!validOperatingState(s)){stationData('selection',false);throw new Error('Invalid operating snapshot');}stationData('selection',true);
    if(s.profile_id!==profileData.profile_id||s.boot_id!==profileData.boot_id||s.profile_revision!==profileData.revision)throw new Error('Operating identity is stale');
    operatingAccept(s,reconcile);
  }catch(error){
    // A read lost on the link, while this socket's own events hold the state, changes nothing.
    if(!answered&&operatingState===operatingHeld&&operatingHeldSocket===current&&!operatingUnknown)return;
    if(epoch===operatingEpoch&&current===socket){operatingFailure=`Operating state stale · ${error.message}`;operatingSupported=null;}}
  finally{operatingReadPending=false;operatingShow();receiveShow();if(operatingReadAgain){operatingReadAgain=false;operatingSync(true);}}
}
async function operatingSelect(action,value){
  if(!operatingState||mutationPending||uncertainMutation||operatingBlocked())return;
  const s=operatingState,command_id=crypto.randomUUID(),epoch=++operatingEpoch,current=socket,authEpoch=authorization?.snapshot().epoch;
  const body={v:1,profile_id:s.profile_id,boot_id:s.boot_id,command_id,action,profile_revision:s.profile_revision,generation:s.generation,operating_revision:s.operating_revision,[action]:value};
  const intent={command_id,base_revision:s.operating_revision,boot_id:s.boot_id};operatingIntent=intent;receiveMutationEpoch++;ownReceiveMutationAt=performance.now();mutationPending=true;operatingFailure='';receiveShow();
  try{
    const response=await stationFetch('/receive/select',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(10000)}),text=await response.text(),ack=JSON.parse(text);
    if(epoch!==operatingEpoch)return;
    if(!stationContext(current,authEpoch))throw new Error('Stale selection completion');
    if(!response.ok){operatingFailure=`Selection refused · ${ack.error?.code??'request_failed'}`;operatingIntent=null;return;}
    if(new TextEncoder().encode(text).length>384||!operatingShape(ack,'v,profile_id,boot_id,command_id,operating_revision,accepted,phase')||ack.v!==1||ack.profile_id!==s.profile_id||ack.boot_id!==s.boot_id||ack.command_id!==command_id||ack.accepted!==true||!operatingCounter(ack.operating_revision)||ack.operating_revision<=s.operating_revision||!['releasing','applying','restarting','applied','failed','release_blocked'].includes(ack.phase))throw new Error('Invalid admission receipt');
  }catch(error){if(epoch===operatingEpoch){operatingUnknown=intent;operatingIntent=null;operatingFailure=`Selection outcome unknown · ${error.message} · refresh or press Monitor to cancel/fence`;}}
  finally{if(epoch===operatingEpoch){mutationPending=false;receiveShow();if(operatingUnknown)await operatingSync(true);await receiveSync();}}
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
  finally{if(epoch===operatingEpoch){mutationPending=false;if(operatingUnknown)await operatingSync(true);await receiveSync();receiveShow();}}
}
// Selects synchronously when nothing is in progress so the epoch moves within the change event.
function restartBusy(){const s=window.wstxContact?.snapshot?.(),c=s?.contact;return (c&&!['idle','completed','cancelled'].includes(c.state))||s?.transmit?.arm_state==='armed'||s?.transmit?.tune;}
function restartSelect(what,action,value){if(!restartBusy())return operatingSelect(action,value);confirmAction(`${what} restarts receive and interrupts the QSO in progress. Continue?`,'Restart receive').then(ok=>ok?operatingSelect(action,value):operatingShow());}
operatingMode.addEventListener('change',()=>restartSelect('Changing the mode','mode',operatingMode.value));
operatingBand.addEventListener('change',()=>{if(operatingBand.value)restartSelect('Changing the band','band',operatingBand.value);});
function receiveTarget(){const s=operatingState;return operatingUnknown?.command_id||operatingIntent?.command_id||((s?.operation?.result==='pending')?s.operation.command_id:null);}
function receiveToggleAvailable(){
  const connected=connection.dataset.state==='connected',active=live?.job&&['running','cancelling'].includes(live.job.state);
  return connected&&(!!receiveTarget()||(!!live&&!mutationPending&&!uncertainMutation&&(active?live.job.state!=='cancelling':(!!live.audio&&receiveInputConfigured()&&operatingState?.receive.owner_released!==false))));
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
  // create a second optional HTTP workload: one read per socket.
  if(operatingSupported!==false&&(reconnected||replaced||edited||(!operatingState&&!operatingReadPending)))operatingSync(reconnected||!!replaced||!!edited);
  operatingShow();
});
addEventListener('station-stale',()=>{operatingFailure='Disconnected · operating data stale';operatingShow();});
// WstxStationCommands::SelectionStateEvent (#10): the socket's first event holds every field,
// each later one what changed. Only events build this view, so a read never mixes into it.
addEventListener('station-message',event=>{
  const {current,message}=event.detail;if(current!==socket||message.type!=='selection.state'||!message.data?.changed)return;
  const d=message.data;if(operatingHeldSocket!==current){operatingHeldSocket=current;operatingHeld=null;}
  operatingHeld={...operatingHeld,...d.changed,v:1,profile_id:d.profile_id,boot_id:d.boot_id,snapshot_sequence:d.snapshot_sequence,monotonic_ms:d.monotonic_ms};
  // A snapshot near its cap comes whole in two events.
  if(Object.keys(operatingHeld).length<15)return;
  const valid=validOperatingState(operatingHeld);stationData('selection',valid);
  // Another identity than the status shown waits for the read station-ready makes for it.
  if(!valid||operatingHeld.profile_id!==profileData?.profile_id||operatingHeld.boot_id!==profileData?.boot_id||operatingHeld.profile_revision!==profileData?.revision)return;
  operatingAccept(operatingHeld,false);operatingShow();receiveShow();
});
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
var chipsReady=false;
function chipsShow(){if(chipsReady)window.wstxChipsShow?.();}
addEventListener('station-stale',()=>chipsShow());
function catShow(){
  const status=document.querySelector('#cat-status');if(!status)return;
  const connected=connection.dataset.state==='connected',v=connected?catStatus:null,confirm=document.querySelector('#cat-confirm');
  const port=String(profileData?.settings.control.endpoint??'').match(/\bCOM[0-9]{1,3}\b/i)?.[0].toUpperCase(),reason=v?.error==='port_in_use'?` · ${port??'serial port'} in use by another program`:v?.error?` · ${v.error}`:'';
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
// #44 CL-044-06 Settings > Radio "Detect radio": one request per button press, no polling.
// Detection writes nothing; "Use this setup" only fills the Radio form, which the operator
// applies with Apply (restart receive) and then the receive-only confirmation above.
const detectSection=block('settings-detect','Detect radio',radioSection,'<p class="op-muted">Detection opens only USB radio bridges (Silicon Labs CP210x) that this station\'s CAT does not hold, reads the CI-V ID and the IC-7300 menu, and writes nothing.</p><p id="discovery-state" class="op-muted" role="status">Radio discovery on start is off until confirmed once: tick the line below and press Detect radio.</p><label class="receive-only-verification"><input type="checkbox" id="detect-ack">USB SEND and USB keying (CW/RTTY) are OFF or the radio is on a dummy load; opening a port can pulse DTR/RTS, also on other CP210x boards</label><p class="op-actions"><button type="button" id="detect-run" disabled>Detect radio</button></p><p id="detect-result" role="status">Not run</p><div id="detect-proposal" hidden><dl id="detect-fields"></dl><p class="op-actions"><button type="button" id="detect-use">Use this setup</button></p></div><div id="detect-settings" hidden><h4>IC-7300 settings</h4><ul id="detect-items"></ul><p class="op-actions"><button type="button" id="radio-settings-apply" disabled>Apply recommended radio settings</button><button type="button" id="radio-settings-undo" disabled>Undo radio settings</button></p><p id="radio-settings-result" role="status"></p></div>');
radioSection.insertBefore(detectSection,profilePanel);
let detectPending=false,detectProposal=null,radioSettingsPending=false;
const detectEl=id=>document.getElementById(id);
function radioSetupShow(){
  const connected=connection.dataset.state==='connected',s=window.wstxContact?.snapshot?.()?.transmit;
  detectEl('detect-run').disabled=!connected||detectPending||!detectEl('detect-ack').checked||!profileData;
  // Writes need the contact client: its confirmation dialog and a known disarmed transmitter.
  const ready=connected&&!!window.wstxConfirm&&!!s&&catStatus?.condition==='ready'&&Number.isSafeInteger(operatingState?.radio?.connection_generation)&&s.arm_state==='disarmed'&&!s.tune;
  for(const id of ['radio-settings-apply','radio-settings-undo'])detectEl(id).disabled=!ready||radioSettingsPending;
}
detectEl('detect-ack').addEventListener('change',radioSetupShow);
setInterval(radioSetupShow,1000);
async function radioSetupPost(path,body){
  const response=await stationFetch(path,{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(60000)});
  let value=null;try{value=await response.json();}catch{}
  if(!response.ok)throw new Error(value?.error?.code??`request_failed ${response.status}`);
  return value;
}
function detectRow(list,term,text,title=''){const dt=document.createElement('dt'),dd=document.createElement('dd');dt.textContent=term;dd.textContent=text;if(title)dd.title=title;list.append(dt,dd);}
function detectShow(v){
  const ports=v.ports??[],radios=ports.flatMap(p=>(p.radios??[]).map(r=>`${p.port} ${r.model??'unknown ID '+r.id} ${r.civ_address}h ${r.baud} baud`));
  detectEl('detect-result').textContent=ports.length?`${ports.length} port(s): ${ports.map(p=>`${p.port} ${p.state}`).join(', ')}${radios.length?' · found '+radios.join('; '):' · no radio answered'}${v.proposal?'':v.supported_radios>1?' · several supported radios: no proposal':''}`:'No COM ports found';
  detectProposal=v.proposal;const fields=detectEl('detect-fields');fields.replaceChildren();
  if(v.proposal){
    const p=v.proposal,a=p.audio;
    detectRow(fields,'Port',p.port);detectRow(fields,'Model',p.model);detectRow(fields,'CI-V address',`${p.civ_address}h`);detectRow(fields,'Baud',String(p.baud));
    detectRow(fields,'Control endpoint',p.control.endpoint);
    detectRow(fields,'Audio input',a.input_device?a.input_name:'not matched (choose manually)',a.input_device??'');
    detectRow(fields,'Audio output',a.output_device?a.output_name:'not matched (choose manually)',a.output_device??'');
  }
  detectEl('detect-proposal').hidden=!v.proposal;
  const items=detectEl('detect-items');items.replaceChildren();
  for(const i of v.settings?.items??[]){const li=document.createElement('li');li.dataset.severity=i.severity;li.textContent=`${i.item} ${i.name.replaceAll('_',' ')}: ${i.label??'unreadable'} · ${i.severity} · ${i.message}`;items.append(li);}
  if(v.settings?.error){const li=document.createElement('li');li.textContent=`Settings read stopped · ${v.settings.error}`;items.append(li);}
  detectEl('detect-settings').hidden=!v.settings;
  if(v.proposal?.radio?.agc)detectRow(fields,'AGC',`${v.proposal.radio.agc} · recommended for FT8/FT4`);
}
detectEl('detect-run').addEventListener('click',async()=>{
  if(detectPending||!profileData||!detectEl('detect-ack').checked)return;
  detectPending=true;radioSetupShow();detectEl('detect-result').textContent='Detecting · this can take several seconds per port';
  try{detectShow(await radioSetupPost('/radio/detect',{v:1,profile_id:profileData.profile_id,boot_id:profileData.boot_id,keying_inhibit_confirmed:true}));}
  catch(error){detectEl('detect-result').textContent=`Detection failed · ${error.message}`;}
  finally{detectPending=false;detectEl('detect-ack').checked=false;radioSetupShow();}
});
detectEl('detect-use').addEventListener('click',()=>{
  const p=detectProposal;if(!p)return;
  const set=(id,value,name)=>{const field=document.getElementById(id);if(value===null||value===undefined)return;if(field.tagName==='SELECT'&&![...field.options].some(o=>o.value===value))field.add(audioOption(name??'Detected device',value));field.value=value;field.dispatchEvent(new Event('input',{bubbles:true}));field.dispatchEvent(new Event('change',{bubbles:true}));};
  set('control-mode',p.control.mode);set('control-endpoint',p.control.endpoint);set('ptt-mode',p.control.ptt);
  set('audio-input',p.audio.input_device,p.audio.input_name);set('audio-output',p.audio.output_device,p.audio.output_name);
  detectEl('detect-result').textContent='Radio section filled · press Apply ⟳, then confirm the receive-only setup';
  document.querySelector('#settings-save').focus();
});
async function radioSettings(action){
  const generation=operatingState?.radio?.connection_generation;if(radioSettingsPending||!profileData||!Number.isSafeInteger(generation)||!window.wstxConfirm)return;
  const text=action==='apply'?'Write the recommended IC-7300 settings by CI-V (USB SEND and USB keying OFF, DATA MOD USB, CI-V transceive OFF)? Each write is read back; the old values are kept for Undo.':'Write the recorded old IC-7300 settings back by CI-V?';
  if(!await window.wstxConfirm(text,action==='apply'?'Apply radio settings':'Undo radio settings'))return;
  radioSettingsPending=true;radioSetupShow();const result=detectEl('radio-settings-result');result.textContent=action==='apply'?'Writing radio settings':'Restoring radio settings';
  try{
    const v=await radioSetupPost(`/radio/settings/${action}`,{v:1,profile_id:profileData.profile_id,boot_id:profileData.boot_id,connection_generation:generation});
    const written=(v.written??[]).map(w=>`${w.item}=${w.value}`).join(', ')||'nothing to change';
    result.textContent=v.result==='done'?`${action==='apply'?'Applied':'Restored'} · ${written}${v.undo?' · undo available':''}`:`Stopped at ${v.failed_item} · ${v.error} · written ${written}`;
  }catch(error){result.textContent=`${action==='apply'?'Apply':'Undo'} refused · ${error.message}`;}
  finally{radioSettingsPending=false;radioSetupShow();}
}
detectEl('radio-settings-apply').addEventListener('click',()=>radioSettings('apply'));
detectEl('radio-settings-undo').addEventListener('click',()=>radioSettings('undo'));
radioSetupShow();
// #44 CL-044-11 AGC is a Radio/CAT setting the station manages: shown only for a radio
// with a known CI-V AGC command, saved with Apply ⟳, applied by the station over CI-V
// (read, write only when it differs, read back) when CAT connects and on each FT8/FT4
// selection. The read-back arrives as the server's radio.agc event; nothing is polled.
const agcRow=document.getElementById('control-agc-row');document.getElementById('server-fields-radio').insertBefore(agcRow,document.getElementById('server-fields-radio').querySelector('.op-apply-row'));
agcRow.insertAdjacentHTML('afterend','<p id="cat-agc" class="op-muted" role="status" hidden></p>');
let agcState=null;
function validAgcEvent(d){
  const agc=v=>v===null||['FAST','MID','SLOW'].includes(v);
  return operatingShape(d,'profile_id,boot_id,target,connection_generation,value,result,trigger')&&agc(d.target)&&agc(d.value)&&
    operatingNullable(d.connection_generation,operatingCounter)&&operatingNullable(d.result,v=>typeof v==='string'&&/^[a-z_]{1,32}$/.test(v))&&operatingNullable(d.trigger,v=>['connect','selection'].includes(v));
}
function agcShow(){
  const managed=agcManaged(),out=document.getElementById('cat-agc'),v=agcState;
  agcRow.hidden=!managed;out.hidden=!managed;if(!managed)return;
  const saved=profileData?.settings.radio?.agc??document.getElementById('control-agc').value;
  out.textContent=!v||!v.target?`Radio AGC ${saved} · set by the station when CAT connects and on each FT8/FT4 selection`:
    v.result===null?`Radio AGC ${v.target} · not yet read from the radio`:
    v.result==='unchanged'?`Radio AGC ${v.value} · read back, already as set`:
    v.result==='written'?`Radio AGC ${v.value} · set to ${v.target} and read back`:
    `Radio AGC ${v.target} not applied · ${v.result}${v.value?` · radio reports ${v.value}`:''}`;
  out.dataset.result=v?.result??'none';
}
addEventListener('station-message',event=>{const {current,message}=event.detail;if(current!==socket||message.type!=='radio.agc'||!validAgcEvent(message.data))return;
  if(profileData&&(message.data.profile_id!==profileData.profile_id||message.data.boot_id!==profileData.boot_id))return;agcState=message.data;agcShow();});
addEventListener('station-ready',()=>{if(agcState&&agcState.boot_id!==profileData?.boot_id)agcState=null;agcShow();});
for(const type of ['input','change'])serverForm.addEventListener(type,agcShow);
// #44 CL-044-13 Tx level: "Set level" (Tune, step up until the ALC rises, back off one step, store,
// stop Tune) is the default; the manual slider exists only without ALC over CI-V. The state arrives as
// the server's radio.tx_level push; nothing is polled.
const powerRow=document.getElementById('control-power-row');document.getElementById('tx-level').append(powerRow);powerRow.hidden=false;
let txLevelState=null;
const txLevelResults={stored:'stored',max_without_alc:'stored at the maximum, ALC did not rise',aborted:'aborted, level unchanged',no_alc:'this radio reports no ALC, set the level by hand',high_swr:'stopped: high SWR, check the antenna'};
function validTxLevelEvent(d){
  const meter=v=>v===null||Number.isSafeInteger(v),m=d?.meters;
  return operatingShape(d,'profile_id,boot_id,managed,level_db,stored,alc,assistant,result,meters,power_limit_pct,warnings,keying_confirmed')&&typeof d.keying_confirmed==='boolean'&&Array.isArray(d.warnings)&&d.warnings.every(w=>typeof w==='string')&&typeof d.managed==='boolean'&&Number.isSafeInteger(d.level_db)&&typeof d.stored==='boolean'&&['unknown','available','unavailable'].includes(d.alc)&&
    typeof d.assistant==='boolean'&&(d.result===null||typeof d.result==='string')&&(d.power_limit_pct===null||Number.isSafeInteger(d.power_limit_pct))&&(m===null||operatingShape(m,'alc,po_pct,swr_x10')&&meter(m.alc)&&meter(m.po_pct)&&meter(m.swr_x10));
}
// #68 CL-068-01: the last pushed SWR at the end of the Rx/Tx strip, red above 2.0; display only.
const SWR_RED_ABOVE_X10=20;
function stripSwrShow(){
  const out=document.getElementById('strip-swr');if(!out)return;
  const v=txLevelState,swr=v?.managed?v.meters?.swr_x10??null:null;
  out.hidden=swr===null;out.textContent=swr===null?'':`SWR ${(swr/10).toFixed(1)}`;out.classList.toggle('op-swr-high',swr!==null&&swr>SWR_RED_ABOVE_X10);
}
function txLevelShow(){
  stripSwrShow();
  document.getElementById('discovery-state').textContent=txLevelState?.keying_confirmed?'Radio discovery on start is on: the station looks for a free radio when it starts.':'Radio discovery on start is off until confirmed once: tick the line below and press Detect radio.';
  const managed=agcManaged(),v=txLevelState;document.getElementById('tx-level').hidden=!managed;if(!managed)return;
  const line=document.getElementById('tx-level-line'),meters=document.getElementById('tx-meters'),slider=document.getElementById('tx-level-slider');
  const level=v?`${v.level_db} dB`:'unknown';
  line.textContent=v?.assistant?`Tune on · stepping up · ${level}`:v?.result?`Tx level ${level} · ${txLevelResults[v.result]??v.result}`:v?.stored?`Tx level ${level}`:'Tx level not set yet';
  document.getElementById('tx-level-set').disabled=!!v?.assistant;
  document.getElementById('tx-level-manual').hidden=v?.alc!=='unavailable';
  if(v&&document.activeElement!==slider)slider.value=v.level_db;
  const m=v?.meters;meters.hidden=!m;if(m)meters.textContent=`ALC ${m.alc??'–'} · Po ${m.po_pct??'–'} % · SWR ${m.swr_x10===null?'–':(m.swr_x10/10).toFixed(1)}`;
}
async function txLevelCommand(params){
  const line=document.getElementById('tx-level-line');
  try{
    const response=await stationFetch('/radio/tx-level',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},signal:AbortSignal.timeout(10000),body:JSON.stringify({v:1,profile_id:profileData.profile_id,boot_id:profileData.boot_id,command_id:crypto.randomUUID(),...params})});
    const data=await response.json().catch(()=>null);
    if(!response.ok)line.textContent=`Tx level refused · ${data?.error?.code??`http_${response.status}`}`;
    else if(!data?.accepted)line.textContent=`Tx level refused · ${data?.refusal}`;
  }catch(error){line.textContent=`Tx level outcome unknown · ${error.message}`;}
}
document.getElementById('tx-level-set').addEventListener('click',()=>txLevelCommand({action:'set_level',tx_offset_hz:Number(document.querySelector('#tx-offset')?.value)||1500}));
document.getElementById('tx-level-slider').addEventListener('change',event=>txLevelCommand({action:'manual',level_db:Number(event.target.value)}));
addEventListener('station-message',event=>{const {current,message}=event.detail;if(current!==socket||message.type!=='radio.tx_level'||!validTxLevelEvent(message.data))return;
  if(profileData&&(message.data.profile_id!==profileData.profile_id||message.data.boot_id!==profileData.boot_id))return;txLevelState=message.data;txLevelShow();window.wstxChipsShow?.();});
// CL-044-14 the persistent Tx trouble the server reports, for the error field.
window.wstxTxWarnings=()=>txLevelState?.warnings??[];
addEventListener('station-ready',()=>{if(txLevelState&&txLevelState.boot_id!==profileData?.boot_id)txLevelState=null;txLevelShow();});
for(const type of ['input','change'])serverForm.addEventListener(type,txLevelShow);
txLevelShow();
detectEl('detect-use').addEventListener('click',()=>{const agc=detectProposal?.radio?.agc;if(agc){const field=document.getElementById('control-agc');field.value=agc;field.dispatchEvent(new Event('change',{bubbles:true}));}agcShow();});
agcShow();
addEventListener('station-stale',catShow);
// WstxTransmitControl::TransmitWire operator panel (#9 slice B). Active only for a profile with
// CAT PTT; the browser renders server-confirmed transmit state and sends explicit
// requests. It runs no transmit timer: the server plans, keys and halts.
const transmitPanel=document.createElement('div');transmitPanel.id='transmit-panel';
transmitPanel.innerHTML='<p id="transmit-status" role="status">Transmit unavailable</p><p id="transmit-result" role="status"></p>';
const transmitDetails=secondary('transmit-details','Transmit test panel',transmitPanel,expertSection);transmitDetails.hidden=true;
let transmitView=null,transmitViewAt=0;
const transmitConfigured=()=>profileData?.settings.control.ptt==='cat';
function transmitBody(extra){return JSON.stringify({v:1,profile_id:profileData.profile_id,boot_id:profileData.boot_id,command_id:crypto.randomUUID(),...extra});}
async function transmitPost(path,extra){
  const response=await stationFetch(path,{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:transmitBody(extra),signal:AbortSignal.timeout(10000)}),text=await response.text();
  if(!response.ok){let code='request_failed';try{code=JSON.parse(text).error?.code??code;}catch{}throw new Error(code);}
  return JSON.parse(text);
}
function transmitShow(){
  const on=transmitConfigured();transmitDetails.hidden=!on;halt.disabled=!on;const qsoHalt=document.querySelector('#qso-halt');if(qsoHalt)qsoHalt.disabled=!on;
  if(on)halt.removeAttribute('aria-describedby');else halt.setAttribute('aria-describedby','transmit-unavailable');
  const v=transmitView,status=document.querySelector('#transmit-status'),ageS=m=>Math.round((m.age_ms+performance.now()-transmitViewAt)/1000);
  chipsShow();
  if(!on||!v){status.textContent='Transmit unavailable';return;}
  const t=v.transmit,m=v.clock_measurement,clock=m?` ${m.offset_ms>=0?'+':''}${m.offset_ms} ms ${m.server} ${ageS(m)} s ago`:'';
  status.textContent=`${t.capability} · ${t.arm_state} (${t.last_disarm_cause}) · PTT ${v.ptt}${v.transmitting?' · TRANSMITTING':''}${t.tune?' · TUNE':''} · clock ${v.clock}${clock} · halt ${t.halt_state}${t.refusal?' · '+t.refusal:''}${t.last_text?' · last '+t.last_text:''}${v.watchdog.tx_remaining_calls==null?'':` · WD ${v.watchdog.tx_remaining_calls} calls`}`;
  const tune=document.querySelector('#tx-tune');if(tune)tune.textContent=t.tune?'Tune off':'Tune';
}
// WstxStationLink::PushedStationState / WstxTransmitControl::TransmitWire (#10): the browser holds
// the transmit state from transmit.state: the socket's first event has every field, each later
// one what changed. It does not read GET /transmit. Ages advance locally; HALT is enabled as
// soon as the station is ready (#57).
let transmitEventSocket=null;
// WstxQsoControl::ContactStateEvent (#10): this client is loaded before the socket opens and the
// contact client is not, so the contact state from the events is held here: every field in the
// socket's first event, what changed after it.
let contactHeld=null,contactHeldSocket=null;
addEventListener('station-message',event=>{const {current,message}=event.detail;if(current!==socket||message.type!=='contact.state'||!message.data?.changed)return;
  if(contactHeldSocket!==current){contactHeldSocket=current;contactHeld=null;}
  const {changed,...identity}=message.data,view={v:1,contact:null,log:null,...contactHeld,...identity};
  for(const [key,value] of Object.entries(changed)){
    if(key==='contact'&&value){
      const whole=value.id!==undefined,{dialogue_from,...rest}=value;
      view.contact=whole?rest:{...view.contact,...rest};
      if(dialogue_from!==undefined)view.contact.dialogue=[...(whole?[]:contactHeld?.contact?.dialogue??[]).slice(0,dialogue_from),...value.dialogue];
    }else view[key]=value&&key!=='log'&&view[key]?{...view[key],...value}:value;
  }
  contactHeld=view;});
function transmitApply(changed){
  const view=transmitView??{};
  for(const [key,value] of Object.entries(changed))view[key]=['transmit','watchdog'].includes(key)&&view[key]?{...view[key],...value}:value;
  transmitView=view;if('clock_measurement' in changed)transmitViewAt=performance.now();
}
// #92 CL-043-01 clock.state (every profile): the browser holds the station clock state from these
// events, without GET /clock and without a timer; the error field and the Clock line read it.
let clockState=null;
function clockSettingShow(){
  const c=clockState?.clock;
  document.querySelector('#clock-setting').textContent=c?`Station clock ${c.state}, correction ${c.correction_ms>0?'+':''}${c.correction_ms} ms`:'Station clock: waiting for the station';
  chipsShow();
}
addEventListener('station-message',event=>{const {current,message}=event.detail;if(current!==socket||message.type!=='clock.state')return;
  const d=message.data;if(!d?.clock||(profileData&&d.profile_id!==profileData.profile_id))return;
  clockState=d;clockSettingShow();});
setInterval(transmitShow,2000);
addEventListener('station-ready',()=>transmitShow());
addEventListener('station-message',event=>{const {current,message}=event.detail;if(current!==socket||message.type!=='transmit.state')return;
  const d=message.data;if(!d?.changed||d.profile_id!==profileData?.profile_id)return;
  if(transmitEventSocket!==current){transmitEventSocket=current;transmitView=null;}
  transmitApply(d.changed);transmitShow();});
halt.addEventListener('click',async()=>{
  const result=document.querySelector('#transmit-result');
  try{const r=await transmitPost('/transmit/halt',{});result.textContent=`Halt: ${r.halt_state}`;}catch(error){result.textContent=`Halt not confirmed · ${error.message}`;}
});
// WstxQsoTransmit::HaltTx: Alt+H sends #9's priority halt (the emergency stop) from this
// always-loaded script, in every page state and focused field. Skipped only when the
// station is known receive-only (the contact snapshot says unsupported); without a
// snapshot it is sent (halt is idempotent). Esc is Abort QSO, handled by contact.js.
function keyboardHaltSkipped(){const s=window.wstxContact?.snapshot?.();return !!s&&s.transmit.capability==='unsupported';}
addEventListener('keydown',event=>{
  const altH=event.altKey&&!event.ctrlKey&&!event.metaKey&&event.key.toLowerCase()==='h';
  if(!altH)return;
  event.preventDefault();
  // 'keyboard-halt' tells contact.js when the halt was answered (or skipped).
  const done=reply=>window.dispatchEvent(new CustomEvent('keyboard-halt',{detail:{reply}}));
  if(!profileData||keyboardHaltSkipped()){done(null);return;}
  const result=document.querySelector('#transmit-result');
  transmitPost('/transmit/halt',{}).then(r=>{result.textContent=`Halt: ${r.halt_state}`;done(r);},error=>{result.textContent=`Halt not confirmed · ${error.message}`;done(null);});
},true);
new ResizeObserver(()=>main.style.setProperty('--op-topbar',`${stationBar.offsetHeight}px`)).observe(stationBar);
document.documentElement.dataset.theme='dark';try{const saved=JSON.parse(localStorage.getItem('wstx.theme.v1'));if(saved?.mode==='manual'&&['day','dark','night'].includes(saved.theme))document.documentElement.dataset.theme=saved.theme;}catch{}
// The log client (WstxContact OfferLogReview) and then the contact client load after this
// browser's first recording and receive snapshots (or 20 s after the station is ready), so
// their bytes never compete with the cold page, authorization or the first state reads on a
// 32 kbit/s link (TC-009-005 and TC-010-002 bounds). Their downloads still hold the station's
// messages behind them on that link, so app.js deferredDownload sets the silence bound (#8).
let clientLoader=null;
function clientsLoad(){
  if(clientLoader||document.querySelector('script[src="/logbook.js"]'))return;
  const since=performance.now();
  clientLoader=setInterval(()=>{
    if(!(snapshot&&live!==undefined)&&performance.now()-since<20000)return;
    clearInterval(clientLoader);
    const load=src=>deferredDownload(new Promise(resolve=>{const script=document.createElement('script');script.src=src;script.onload=script.onerror=resolve;document.head.append(script);}));
    const append=()=>load('/logbook.js').then(()=>load('/contact.js'));
    if(typeof requestIdleCallback==='function')requestIdleCallback(append,{timeout:2000});else setTimeout(append,0);
  },250);
}
// app.js runs first and may already be connected when this script runs (as for sync above).
addEventListener('station-ready',clientsLoad);if(socket?.readyState===WebSocket.OPEN&&connection.dataset.state==='connected')clientsLoad();
chipsReady=true;chipsShow();

// WstxOperatingLayout::PageUpdate (#51). app.js reloads a page whose client build differs
// from the station's, unless this screen holds the reload: a QSO or transmission in
// progress, an open dialog or unsaved settings. A held update and a station snapshot this
// page cannot validate are never silent: one chip names it and reloads on a click.
const stationNotice=document.createElement('button');stationNotice.type='button';stationNotice.id='station-notice';stationNotice.className='op-chip';stationNotice.hidden=true;chips.before(stationNotice);
stationNotice.addEventListener('click',()=>location.reload());
const rejectedData=new Set();let stationUpdate=null;
window.wstxReloadHeld=()=>!!restartBusy()||!!document.querySelector('dialog[open]')||dirty;
function stationNoticeShow(){
  const text=stationUpdate?'Station updated \u00b7 reload':rejectedData.size?`Station data not understood (${[...rejectedData].join(', ')}) \u00b7 reload`:'';
  stationNotice.hidden=!text;stationNotice.dataset.severity=stationUpdate?'warn':'error';
  stationNotice.textContent=text&&`${stationUpdate?'\u26A0':'\u2716'} ${text}`;stationNotice.title=stationUpdate?'The station runs a newer client; reload this page to use it':'This page rejected a station snapshot; reload to load the station\u2019s current client';
}
function stationData(kind,accepted){if(accepted===rejectedData.has(kind)){if(accepted)rejectedData.delete(kind);else rejectedData.add(kind);stationNoticeShow();}}
addEventListener('station-updated',event=>{stationUpdate=event.detail;stationNoticeShow();});
window.wstxStationData=stationData;
// #61 CL-061-01: an unknown-loss source epoch of the same receive brings a fresh source, job and
// generation (results from sequence 0, frames from 0) but is no new receive: loss_epochs grew
// (it restarts at 0 with every receive start), same mode and input, no Start/Stop or band/mode
// change. The display is kept then; anything else clears it.
function lossEpoch(data){
  return !!(live?.job&&data.job&&data.generation>live.generation&&data.job.state==='running'&&data.job.mode===live.job.mode&&data.audio.device_id===live.audio.device_id&&
    data.audio.loss_epochs>live.audio.loss_epochs&&performance.now()-ownReceiveMutationAt>15000&&(operatingState?.operating_revision??null)===liveOperatingRevision);
}
// The kept rows move in front of the new frame origin behind one gap row marking the epoch.
function keepWaterfall(){
  const last=rows.at(-1);if(!last)return;
  const interval=last.end_frame-last.first_frame,shift=last.sequence+2,frames=last.end_frame+interval;
  for(const row of rows){row.sequence-=shift;row.first_frame-=frames;row.end_frame-=frames;}
  rows.push({sequence:-1,first_frame:-interval,end_frame:0,levels:null,held:false});paint();
}

// #55 CL-055-04 WstxBandActivity::BandActivityValue (1 calling me .. 8 no flag; 2, the strategy
// hits, is applied by the value view in contact.js) and BandActivityHover (title and aria-description).
// #24 S1b: the call a decoded message is addressed to, also as a filled-in hash <MYCALL> or the
// 'to' call of a nonstandard i3=4 message; shared by the my-call colour and value 1 (#55).
function recordTo(f){return f?.type==='nonstandard'?(f.cq?null:(f.hash_second?f.full_call:f.hashed_call)?.text??null):['call','hash'].includes(f?.to?.kind)?f.to.text:null;}
// Its sender: the other call of a nonstandard i3=4 message (the full call of a CQ).
function recordFrom(f){return f?.type==='nonstandard'?((!f.cq&&f.hash_second?f.hashed_call:f.full_call)?.text??null):['call','hash'].includes(f?.from?.kind)?f.from.text:null;}
function activityValue(r){
  if(r?.status!=='decoded')return 8;
  const my=(profileData?.settings?.callsign??'').trim().toUpperCase();
  if(my&&recordTo(r.fields)===my)return 1;
  const groups=[[3,['new_dxcc','new_continent']],[4,['new_dxcc_band','new_continent_band']],[5,['new_cq_zone','new_cq_zone_band','new_itu_zone','new_itu_zone_band']],[6,['new_grid','new_grid_band']],[7,['new_call','new_call_band']]];
  return groups.find(([,names])=>names.some(k=>r.flags?.[k]===true))?.[0]??8;
}
function activityReasons(r){
  if(r?.status!=='decoded'||!r.flags)return [];
  const dx=r.dxcc,band=operatingState?.selection?.band||'this band',ex=r.fields?.exchange,grid=ex?.kind==='grid'&&typeof ex.value==='string'?ex.value.slice(0,4).toUpperCase():'';
  const text={new_continent:`New continent ${dx?.cont??''}`,new_continent_band:`New continent on ${band}`,new_dxcc:`New DXCC: ${dx?.name??''}`,new_dxcc_band:`New DXCC on ${band}`,new_cq_zone:`New CQ zone ${dx?.cq??''}`,new_cq_zone_band:`New CQ zone on ${band}`,new_itu_zone:`New ITU zone ${dx?.itu??''}`,new_itu_zone_band:`New ITU zone on ${band}`,new_grid:`New grid ${grid}`,new_grid_band:`New grid on ${band}`,new_call:'New call',new_call_band:`New call on ${band}`};
  return Object.keys(text).filter(k=>r.flags[k]===true).map(k=>text[k].replace(/:?\s+$/,''));
}
// #50 CL-050-08 BandActivityHover (operator 2026-11-04): the row's tip names only the reasons of its
// colour that the row does not show (no country, continent, distance or "Calls you"): per kind
// (continent, DXCC, zone, grid, call) the strongest enabled slot, so "New call" never also says
// "New on 40m"; the call reason carries the worked-before status in parentheses.
function activityHover(r){
  if(r?.status!=='decoded'||!r.flags)return {};
  const dx=r.dxcc,band=operatingState?.selection?.band||'this band',ex=r.fields?.exchange,grid=ex?.kind==='grid'&&typeof ex.value==='string'?ex.value.slice(0,4).toUpperCase():'';
  const text={new_continent:`New continent ${dx?.cont??''}`,new_continent_band:`New continent on ${band}`,new_dxcc:'New DXCC',new_dxcc_band:`New DXCC on ${band}`,new_cq_zone:`New CQ zone ${dx?.cq??''}`,new_itu_zone:`New ITU zone ${dx?.itu??''}`,new_cq_zone_band:`New CQ zone on ${band}`,new_itu_zone_band:`New ITU zone on ${band}`,new_grid:`New grid ${grid}`,new_grid_band:`New grid on ${band}`,new_call:'New call',new_call_band:`New on ${band}`};
  return Object.fromEntries(Object.entries(text).filter(([k])=>r.flags[k]===true).map(([k,t])=>[k,t.trim()]));
}
const HOVER_KINDS=[['new_continent','new_continent_band'],['new_dxcc','new_dxcc_band'],['new_cq_zone','new_itu_zone','new_cq_zone_band','new_itu_zone_band'],['new_grid','new_grid_band'],['new_call','new_call_band']];
// One line, " · " between reasons (operator: "line them up horizontally"), then the strategy verdict. A row without such a reason has no tip. Shown in
// the compact Band Activity tip (data-tip) and as aria-description; no native title, which wraps.
function hoverReasons(reasons,worked){
  const on=new Set((document.querySelector('#band-activity')?.dataset.hlOn??'').split(' '));
  return HOVER_KINDS.map(kind=>{const k=kind.find(k=>reasons[k]&&on.has(k));return !k?'':k==='new_call_band'&&worked?`${reasons[k]} (worked ${worked})`:reasons[k];}).filter(Boolean);
}
function activityWhy(row){
  let reasons={};try{reasons=JSON.parse(row.dataset.reasons??'{}')??{};}catch{}
  const worked=row.dataset.worked==='worked_this_band_and_mode'?`on ${row.dataset.workedOn||'this band and mode'}`:row.dataset.worked==='worked_other_band_or_mode'?'on another band or mode':'';
  const parts=hoverReasons(reasons,worked);
  parts.push(row.dataset.whyStrategy??'');
  const tip=parts.filter(Boolean).join(' · ');
  if(tip){row.dataset.tip=tip;row.setAttribute('aria-description',tip);}else{delete row.dataset.tip;row.removeAttribute('aria-description');}
  const t=window.wstxActivityTip;if(t?.row===row)t.show(row);
}
// The compact one-line tip: at the pointer over a row (not over a cell with its own title: DXCC,
// Distance, an a-priori message), under the row while it has keyboard focus; gone when the row leaves or is redrawn.
{const tip=document.createElement('div');tip.id='ba-tip';tip.className='op-tip';tip.hidden=true;tip.setAttribute('aria-hidden','true');document.querySelector('main').append(tip);
 const state={row:null,show(row,x,y){
  if(!row?.isConnected||!row.dataset.tip){tip.hidden=true;state.row=null;return;}
  state.row=row;tip.textContent=row.dataset.tip;tip.hidden=false;
  if(x===undefined){const b=row.getBoundingClientRect();x=b.left+8;y=b.bottom-16;}
  tip.style.left=`${Math.max(4,Math.min(x+12,innerWidth-tip.offsetWidth-4))}px`;tip.style.top=`${Math.max(4,Math.min(y+16,innerHeight-tip.offsetHeight-4))}px`;}};
 window.wstxActivityTip=state;
 const tbody=document.querySelector('#band-activity tbody');
 tbody.addEventListener('pointermove',event=>{const cell=event.target.closest?.('td'),row=event.target.closest?.('tr[data-sequence]');if(!row||cell?.title)state.show(null);else state.show(row,event.clientX,event.clientY);});
 tbody.addEventListener('pointerleave',()=>state.show(null));
 tbody.addEventListener('focusin',event=>state.show(event.target.closest?.('tr[data-sequence]')));
 tbody.addEventListener('focusout',()=>state.show(null));
 new MutationObserver(()=>{if(state.row&&!state.row.isConnected)state.show(null);}).observe(tbody,{childList:true});}
window.wstxActivityWhy=activityWhy;

// WstxSignalArea::RxTxStrip frequency mapping (#50, CL-050-07): the waterfall canvas's own
// box carries the fixed 0..3000 Hz span (the time ruler beside it is outside). The frequency axis
// ticks, the Rx/Tx lines with their brackets and the pointer frequency all use this one mapping.
// x(hz,container): the CSS px offset of hz in the container's padding box; hz(clientX): the
// integer Hz under a pointer.
const wstxWaterfallAxis={low:0,high:3000,
  x(hz,container){const c=waterfall.getBoundingClientRect(),o=container.getBoundingClientRect();return c.left-o.left-container.clientLeft+(hz-this.low)*c.width/(this.high-this.low);},
  hz(clientX){const c=waterfall.getBoundingClientRect();return Math.max(this.low,Math.min(this.high,Math.round(this.low+(clientX-c.left)*(this.high-this.low)/Math.max(c.width,1))));}};
window.wstxWaterfallAxis=wstxWaterfallAxis;
// FR-023 native FlexRadio status. A native profile receives from its own session stream, so it
// needs no audio device selection. The state arrives as the server's radio.native push; nothing is
// polled, and a standard profile never receives it.
function nativeProfile(){return profileData?.connection_type==='native_flex';}
function receiveInputConfigured(){return nativeProfile()||!!profileData?.settings.audio.input_device;}
let nativeState=null;
const nativeStatus=document.createElement('p');nativeStatus.id='native-status';nativeStatus.setAttribute('role','status');nativeStatus.hidden=true;document.querySelector('#operating-radio').after(nativeStatus);
function validNativeEvent(d){
  return operatingShape(d,'profile_id,boot_id,state,error,radio_code,session,radio,slice,retry_after_ms,transmit')&&operatingUuid(d.profile_id)&&operatingUuid(d.boot_id)&&
    ['unauthorized','discovering','connecting','ready','unavailable','conflict','stopped'].includes(d.state)&&operatingNullable(d.error,v=>typeof v==='string'&&/^[a-z_]{1,32}$/.test(v))&&operatingCounter(d.session)&&
    d.transmit==='unsupported'&&operatingNullable(d.radio,v=>typeof v==='object')&&operatingNullable(d.slice,v=>typeof v==='object');
}
function nativeText(v){
  const slice=v.slice?` · slice ${v.slice.letter??v.slice.index} ${operatingFrequency(v.slice.frequency_hz)?(v.slice.frequency_hz/1e6).toFixed(6)+' MHz':'frequency unknown'} ${v.slice.mode??''} ${v.slice.rx_antenna??''}`:'';
  const radio=v.radio?` · ${v.radio.model??'radio'}${v.radio.firmware?' '+v.radio.firmware:''} ${v.radio.serial} ${v.radio.address}${v.radio.protocol?' API '+v.radio.protocol:''}`:'';
  return `Native FlexRadio ${v.state}${v.error?' · '+v.error:''}${radio}${slice} · transmit unsupported`;
}
function nativeShow(){
  const stale=connection.dataset.state!=='connected';
  nativeStatus.hidden=!nativeProfile();
  nativeStatus.textContent=!nativeProfile()?'':stale?'Native FlexRadio status stale · station disconnected':nativeState?nativeText(nativeState):'Native FlexRadio status not received yet';
  nativeStatus.dataset.state=stale||!nativeState?'unknown':nativeState.state;
  chipsShow();
}
window.wstxNativeProblem=()=>nativeProfile()&&nativeState&&nativeState.state!=='ready'?`FlexRadio ${nativeState.state}${nativeState.error?' · '+nativeState.error.replace(/_/g,' '):''}`:null;
addEventListener('station-message',event=>{const {current,message}=event.detail;if(current!==socket||message.type!=='radio.native'||!validNativeEvent(message.data))return;
  if(profileData&&(message.data.profile_id!==profileData.profile_id||message.data.boot_id!==profileData.boot_id))return;nativeState=message.data;nativeShow();});
addEventListener('station-ready',()=>{if(nativeState&&nativeState.boot_id!==profileData?.boot_id)nativeState=null;nativeShow();});
addEventListener('station-stale',nativeShow);
