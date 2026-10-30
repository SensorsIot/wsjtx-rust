'use strict';
const main = document.querySelector('main'), controls = document.createElement('div');
controls.id = 'controls';
while (main.firstChild) controls.append(main.firstChild);
main.classList.add('op-app');
const signal = document.createElement('section'); signal.id = 'signal'; signal.className='op-signal'; signal.setAttribute('aria-label','Recorded spectrum and waterfall');
signal.innerHTML = '<div class="op-signal-heading"><div><span class="op-live-dot" aria-hidden="true"></span><h2 id="signal-status" role="status">Waiting for station snapshot</h2><span>0&ndash;3000 Hz</span></div></div><p id="signal-meta"></p><canvas id="spectrum" aria-label="Spectrum in calibrated dBFS"></canvas><div id="frequency-ruler" aria-label="Fixed frequency span 0 to 3000 Hz"></div><div id="waterfall-wrap"><div id="time-ruler"></div><canvas id="waterfall" tabindex="0" aria-label="Waterfall in source seconds; arrow keys select native bins and rows"></canvas></div><div id="level-legend"></div><canvas id="level-bar" aria-label="Waterfall color scale from navy to red"></canvas>';
const splitter = document.createElement('div'); splitter.id = 'splitter'; splitter.className='op-splitter'; splitter.tabIndex = 0; splitter.innerHTML='<span></span>';
for (const [key,value] of Object.entries({role:'separator','aria-orientation':'horizontal','aria-label':'Resize spectrum and controls','aria-controls':'signal controls'})) splitter.setAttribute(key,value);
main.append(signal,splitter,controls);
const stationBar=controls.querySelector('header');stationBar.id='station-bar';stationBar.className='op-header';
const stationIdentity=document.createElement('button');stationIdentity.type='button';stationIdentity.className='op-station-button';stationIdentity.dataset.region='connection';stationIdentity.setAttribute('aria-label','Station connection details');
stationIdentity.innerHTML='<span><span class="op-eyebrow">WSTX / REMOTE STATION</span><strong id="operating-station">Waiting for station</strong></span><span aria-hidden="true">&#8964;</span>';
const stationConnectionNode=document.querySelector('#connection');
stationBar.replaceChildren(stationIdentity);
const nav=document.createElement('nav');nav.className='op-nav';nav.setAttribute('aria-label','Workspace');
nav.innerHTML='<button type="button" data-region="operate" class="active" aria-current="page">Operate</button><button type="button" data-region="recordings" id="open-recordings">Recordings</button><button type="button" data-region="logbook">Logbook</button>';
const headerActions=document.createElement('div');headerActions.className='op-header-actions';
headerActions.innerHTML='<button type="button" data-region="strategies" id="open-strategies">&#10023; Strategies</button><button type="button" data-region="server-settings" id="open-server-settings" title="Server settings (F2)">&#9881; Server settings</button><button type="button" data-region="client-preferences" id="open-client-preferences" title="Client preferences">Preferences</button><button type="button" data-region="help" aria-label="Help">?</button>';
headerActions.prepend(stationConnectionNode);
const halt=document.createElement('button');halt.id='halt-tx';halt.className='op-halt';halt.disabled=true;halt.innerHTML='<span class="op-square" aria-hidden="true"></span>Halt Tx';halt.setAttribute('aria-describedby','transmit-unavailable');headerActions.append(halt);
stationBar.append(nav,headerActions);
const tuning=document.createElement('section');tuning.id='radio-toolbar';tuning.className='op-tuning';tuning.setAttribute('aria-label','Radio operation');
tuning.innerHTML='<div class="op-dial"><label for="op-dial">DIAL FREQUENCY <span>MHz</span></label><input id="op-dial" disabled placeholder="Unknown" aria-label="Dial frequency unavailable" title="CAT readback unavailable"></div><label class="op-compact-label">Mode<select disabled aria-label="Operating mode unavailable"><option>Unavailable</option></select></label><div class="op-divider"></div><button type="button" class="op-monitor" disabled title="This server does not offer live audio capture">&#8545; Monitor</button><div class="op-decode-group"><button type="button" disabled title="This server does not offer live decoding">&#10227; Decode</button><select disabled aria-label="Decoding depth unavailable"><option>Depth</option></select></div><div class="op-period"><span>Receive period</span><div class="op-period-track"></div><small>Timing unavailable</small></div><div class="op-input-meter"><span>Rx level <strong>Unknown</strong></span><div></div></div>';
const bands=document.createElement('section');bands.id='band-strip';bands.className='op-band-row';bands.setAttribute('aria-label','Band selection');
bands.innerHTML='<span class="op-eyebrow">BAND</span>'+['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m','2m','70cm'].map(band=>`<button type="button" disabled title="CAT tuning unavailable">${band}</button>`).join('');
const workspace=document.createElement('div');workspace.id='operating-workspace';
workspace.innerHTML=`<div class="operating-grid op-desk">
<section id="band-activity" class="message-pane op-card op-activity" aria-labelledby="activity-heading"><header><div><h3 id="activity-heading">Band Activity <span class="op-count">0</span></h3><span class="op-muted">Latest decode period</span></div><div class="op-order-controls"><label>Sort<select id="activity-sort" aria-label="Band Activity sort"><option value="frequency">Frequency</option><option value="signal">Signal strength</option><option value="dt">DT</option><option value="message">Callsign/message</option></select></label><label>Direction<select id="activity-direction" aria-label="Band Activity sort direction"><option value="asc">Ascending</option><option value="desc">Descending</option></select></label></div></header><div class="op-search"><input disabled aria-label="Find a callsign or message" placeholder="Find callsign or message&#8230;"><span>Unavailable</span></div><div class="op-table-wrap"><table role="table" aria-label="Decoded messages"><thead role="rowgroup"><tr role="row"><th scope="col">Time</th><th scope="col">SNR</th><th scope="col">DT</th><th scope="col">Hz</th><th scope="col">Message</th><th scope="col">Status</th></tr></thead><tbody role="rowgroup"><tr><td colspan="6" class="empty-messages"><strong>Decoder unavailable</strong><span>No decoded messages are available from this server.</span></td></tr></tbody></table></div><footer><span class="op-selection-dot"></span>Station selection requires decoded results<span class="op-muted">No sample data</span></footer></section>
<section id="rx-focus" class="message-pane op-card op-contact" aria-labelledby="focus-heading"><header><div><h3 id="focus-heading">Current QSO</h3><span class="op-muted">No active contact &#183; transmission unavailable</span></div><span class="op-contact-badge">Unavailable</span></header><div class="op-contact-body"><div class="op-contact-identity"><div><strong>No station selected</strong><span>Contact selection requires decoded results</span></div></div><ol class="op-qso-steps" aria-label="QSO progression"><li><span>1</span>Call</li><li><span>2</span>Report</li><li><span>3</span>Confirm</li><li><span>4</span>Log</li></ol><div class="op-receive-bubble"><span>LAST RECEIVED <time>Unknown</time></span><p>No received contact message</p></div><div class="op-frequency-fields"><label>Rx audio<input disabled placeholder="Unknown"><span>Hz</span></label><label>Tx audio<input disabled placeholder="Unknown"><span>Hz</span></label><button type="button" disabled title="Tuning unavailable">Rx &#8594; Tx</button></div><div class="op-next-label"><span>NEXT MESSAGE</span><select disabled aria-label="Transmit period unavailable"><option>Period</option></select></div><select class="op-message-select" disabled aria-label="Next outgoing message unavailable"><option>No outgoing message</option></select><div class="op-auto-row"><label class="op-check"><input type="checkbox" disabled aria-label="Auto sequence unavailable">Auto sequence</label><button type="button" class="op-text-button" disabled>Prepare CQ</button></div><div class="op-contact-actions"><button type="button" class="op-primary" disabled aria-describedby="transmit-unavailable"><span aria-hidden="true">&#9655;</span>Enable Tx</button><button type="button" disabled aria-describedby="contact-unavailable">Log contact</button></div><p id="transmit-unavailable" class="op-unavailable">Transmission unavailable: this server does not offer transmit control.</p><p id="contact-unavailable" class="op-unavailable">Contact workflow and logging are unavailable.</p></div></section>
<section id="strategy-panel" class="op-card op-strategy" aria-labelledby="strategy-heading"><header><div><h3 id="strategy-heading">&#10023; Strategy</h3><span class="op-muted">Server execution</span></div><span class="op-state">Unavailable</span></header><div class="op-strategy-body"><div class="op-strategy-name"><strong>No active definition</strong></div><p class="op-muted op-strategy-description">The station does not yet offer strategy execution. No browser-side selection or automation is running.</p><div class="op-rule-chips"><span>Filters unavailable</span><span>Ranking unavailable</span></div><div class="op-candidate"><span class="op-eyebrow">SELECTED CANDIDATE</span><strong>None</strong><p>No server-confirmed candidate or decision.</p></div><div class="op-policy-summary"><span>Reply attempts<strong>Unavailable</strong></span><span>Stop condition<strong>Unavailable</strong></span><span>Transmission<strong>Unavailable</strong></span></div><button type="button" class="op-primary" disabled title="Strategy service unavailable">&#9655; Resume strategy</button><button type="button" class="op-edit-definition" data-region="strategies">View definition <span>&#8594;</span></button></div></section></div>`;
controls.prepend(workspace);
const secondaryRoot=document.createElement('div');secondaryRoot.id='workspace-secondary';secondaryRoot.hidden=true;controls.append(secondaryRoot);
const secondaryRegions=new Map();
function region(id,title,intro){const section=document.createElement('section');section.id='region-'+id;section.className='op-secondary';section.hidden=true;section.setAttribute('aria-labelledby','region-title-'+id);section.innerHTML=`<header><div><span class="op-eyebrow">WSTX / ${title.toUpperCase()}</span><h2 id="region-title-${id}">${title}</h2></div><button type="button" data-region="operate" class="return-operate">&#8592; Back to operation</button></header><div class="op-secondary-body"><p class="op-muted">${intro}</p></div>`;secondaryRoot.append(section);secondaryRegions.set(id,section);return section.querySelector('.op-secondary-body');}
const settingsRegion=region('server-settings','Server settings','Saved station definitions and actual interface state remain separate. Saving a profile does not activate radio hardware.');
const preferencesRegion=region('client-preferences','Client preferences','Display controls affect this browser view only. They do not change station configuration or run automation.');
const recordingsRegion=region('recordings','Recordings','Inspect a real recording with the station spectrum service. This is not offline decoding.');
const connectionRegion=region('connection','Station connection','Confirmed station identity and capabilities. Unknown hardware state is not inferred from saved settings.');
const strategiesRegion=region('strategies','Strategy definition','The server validates, stores and executes strategy definitions. This server does not yet offer that service.');
strategiesRegion.insertAdjacentHTML('beforeend','<div class="op-definition-grid"><fieldset disabled><legend>Eligibility filters</legend><label>Name<input placeholder="No saved definition"></label><label>Minimum signal &#183; dB<input type="number" placeholder="Unavailable"></label><label class="op-check"><input type="checkbox">Calling CQ only</label><label class="op-check"><input type="checkbox">Exclude stations already worked</label></fieldset><fieldset disabled><legend>Ranking &amp; QSO policy</legend><label>Priority<select><option>Unavailable</option></select></label><label>Maximum reply attempts<input type="number" placeholder="Unavailable"></label><p class="op-muted">No active revision, candidate or decision. Definition editing and activation require the station service.</p></fieldset></div><button type="button" disabled title="Strategy service unavailable">Save definition</button>');
const logRegion=region('logbook','Logbook','Contact history and ADIF operations are unavailable until this station offers contact logging.');
logRegion.insertAdjacentHTML('beforeend','<p>No server-confirmed contacts are available.</p><button type="button" disabled>Import ADIF</button> <button type="button" disabled>Export ADIF</button>');
const helpRegion=region('help','Help','Operating controls use confirmed station capabilities. Unavailable controls do not send radio commands.');
helpRegion.insertAdjacentHTML('beforeend','<dl><div><dt>F2</dt><dd>Open Server settings</dd></div><div><dt>Escape</dt><dd>Return to operation and restore focus</dd></div><div><dt>Separator arrows / Home / End</dt><dd>Resize the actual spectrum/waterfall</dd></div><div><dt>Waterfall arrows</dt><dd>Inspect measured bins and source time</dd></div></dl><p class="op-muted">The interface contains no generated callsigns or simulated radio state.</p>');
function secondary(id,title,element,parent){const detail=document.createElement('details');detail.id=id;const summary=document.createElement('summary');summary.textContent=title;detail.append(summary,element);parent.append(detail);return detail;}
secondary('station-settings','Station settings',document.querySelector('#profile-panel'),settingsRegion).open=true;
const connectionDetails=secondary('connection-details','Connection details',controls.querySelector('section[aria-label="Station status"]'),connectionRegion);connectionDetails.open=true;
const operatingRefresh=document.querySelector('#refresh');operatingRefresh.className='op-icon-button';operatingRefresh.setAttribute('aria-label','Refresh status');operatingRefresh.title='Refresh status';operatingRefresh.innerHTML='&#10227;';headerActions.insertBefore(operatingRefresh,headerActions.firstChild);
const profileMetadata=document.querySelector('#profile-panel>dl');connectionRegion.append(profileMetadata);
const serverForm=document.querySelector('#settings'),serverFieldGroups=[];
for(const [name,ids] of [['General',['display-name','callsign','locator']],['Radio',['control-mode','control-endpoint','ptt-mode']],['Audio',['audio-input','audio-output']]]){
  const group=document.createElement('fieldset');group.id='server-fields-'+name.toLowerCase();group.className='op-server-fieldset';
  const legend=document.createElement('legend');legend.textContent=name;group.append(legend);
  if(name==='Radio')group.append(serverForm.querySelector('select:not([id])').closest('label'));
  for(const id of ids)group.append(document.getElementById(id).closest('label'));
  serverFieldGroups.push(group);
}
serverForm.prepend(...serverFieldGroups);
const settingsGrid=document.createElement('div');settingsGrid.className='op-settings-grid';
const settingsSide=document.createElement('nav');settingsSide.className='op-settings-sidebar';settingsSide.setAttribute('aria-label','Server settings sections');
settingsSide.innerHTML='<span class="op-eyebrow">SERVER DEFINITIONS</span>'+['General','Radio','Audio'].map(name=>`<button type="button" data-settings-section="${name.toLowerCase()}">${name}</button>`).join('')+'<button type="button" data-region="connection">Connection</button><hr><button type="button" data-region="client-preferences">Client preferences</button>';
settingsGrid.append(settingsSide,document.querySelector('#station-settings'));settingsRegion.append(settingsGrid);
settingsSide.addEventListener('click',event=>{const button=event.target.closest('button[data-settings-section]');if(!button)return;for(const entry of settingsSide.querySelectorAll('[data-settings-section]')){entry.classList.toggle('active',entry===button);}const group=document.querySelector('#server-fields-'+button.dataset.settingsSection);group.querySelector('input,select').focus();group.scrollIntoView({block:'nearest'});});
const capabilities=document.createElement('dl');capabilities.id='operating-capabilities';capabilities.innerHTML='<div><dt>Audio</dt><dd>Unavailable &#183; capture not offered</dd></div><div><dt>CAT</dt><dd>Unavailable &#183; radio not configured</dd></div><div><dt>Decoder</dt><dd>Unavailable &#183; results not offered</dd></div><div><dt>Transmission</dt><dd>Unavailable &#183; control not offered</dd></div>';connectionRegion.append(capabilities);
const profileHeading=document.querySelector('#profile-name');
const updateIdentity=()=>{document.querySelector('#operating-station').textContent=profileData?.settings.display_name??'Waiting for station';};
new MutationObserver(updateIdentity).observe(profileHeading,{childList:true,subtree:true,characterData:true});updateIdentity();
const panel = document.createElement('section'); panel.id = 'recording-controls'; panel.setAttribute('aria-label','Recording controls');
panel.innerHTML = '<label>Import mono 12 kHz PCM16 WAV (up to 120 seconds)<input id="recording-file" type="file" accept=".wav,audio/wav"></label><button id="recording-import">Import recording</button><button id="recording-replay" disabled>Replay spectrum</button><button id="recording-cancel" disabled>Cancel operation</button><p>One processing worker per station &#183; no speaker playback</p><p id="recording-progress" role="status"></p>';
const localPreferences=document.createElement('div');localPreferences.id='local-display-preferences';
localPreferences.innerHTML='<label>Display <select id="display-profile"><option value="detail">Detailed (fast link, up to 10 KiB/s per viewer)</option><option value="thin">Thin (32 kbit/s link)</option><option value="off">Off</option></select></label><div id="display-levels"><label>Black level (dBFS)<input id="display-black" type="number" min="-120" max="-30" step="1" value="-120"></label><label>Range (dB)<input id="display-range" type="number" min="10" max="80" step="1" value="30"></label><label><input id="display-auto" type="checkbox" checked> Auto black</label><output id="bin-readout" aria-live="polite">Select a bin with pointer or arrow keys</output></div>';
panel.append(localPreferences,document.querySelector('#signal-meta'));
secondary('recorded-input','Recorded input',panel,recordingsRegion).open=true;
const sliders=document.createElement('div');sliders.id='presentation-sliders';sliders.className='op-display-controls';
sliders.innerHTML='<label>Sensitivity <input id="display-sensitivity" type="range" min="-30" max="30" step="1" value="0" aria-label="Waterfall sensitivity"><output id="sensitivity-value">+0 dB</output></label><label title="Scroll speed in CSS pixels per source second. Replay and received rows per second do not change.">Speed <input id="display-speed" type="range" min="0.5" max="8" step="0.5" value="2" aria-label="Waterfall speed, Slow to Fast"><output id="speed-value">20 px/s</output></label><button type="button" data-region="client-preferences" title="Display preferences" aria-label="Display preferences">Display</button>';
signal.querySelector('.op-signal-heading').append(sliders);
const statusBar=document.createElement('footer');statusBar.id='workspace-statusbar';statusBar.className='op-statusbar';statusBar.innerHTML='<span>Profile-mode preview &#183; capabilities shown explicitly</span><span>Audio / CAT / decoder unavailable</span><span>No radio transmission</span>';
for(const child of [...controls.children]){if(child.matches('h1,.intro,footer'))child.remove();}
main.append(stationBar,tuning,signal,splitter,bands,controls,statusBar);
let currentRegion='operate',returnFocus=null;
function showRegion(name,opener){
  if(name!=='operate'&&!secondaryRegions.has(name))return;
  currentRegion=name;main.dataset.region=name;
  if(name!=='operate'&&opener)returnFocus=opener;
  workspace.hidden=name!=='operate';secondaryRoot.hidden=name==='operate';
  for(const [id,section]of secondaryRegions)section.hidden=id!==name;
  const keepSignal=['operate','recordings','client-preferences'].includes(name);
  for(const node of [signal,splitter,tuning])node.hidden=!keepSignal;
  bands.hidden=name!=='operate';
  (name==='client-preferences'?preferencesRegion:panel).append(localPreferences);
  for(const button of nav.querySelectorAll('[data-region]')){button.classList.toggle('active',button.dataset.region===name);if(button.dataset.region===name)button.setAttribute('aria-current','page');else button.removeAttribute('aria-current');}
  if(name==='operate') {split(upper);if(returnFocus?.isConnected){returnFocus.focus();returnFocus=null;}}
  else secondaryRegions.get(name).querySelector('.return-operate').focus();
}
main.addEventListener('click',event=>{const button=event.target.closest('button[data-region]');if(button&&!button.disabled)showRegion(button.dataset.region,button);});
addEventListener('keydown',event=>{if(event.key==='F2'){event.preventDefault();showRegion('server-settings',document.querySelector('#open-server-settings'));}else if(event.key==='Escape'&&currentRegion!=='operate'){event.preventDefault();showRegion('operate');}});
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
  if(id==='display-sensitivity')sensitivity=Math.max(-30,Math.min(30,Math.floor(value+.5)));else speed=Math.max(.5,Math.min(8,Math.floor(2*value+.5)/2));
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
  const otherHeight=stationBar.offsetHeight+tuning.offsetHeight+bands.offsetHeight+statusBar.offsetHeight;
  const signalText=[signal.querySelector(".op-signal-heading"),document.querySelector("#signal-meta"),document.querySelector("#frequency-ruler"),document.querySelector("#level-legend")].reduce((height,node)=>height+(node?.offsetHeight||0),0);
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
splitter.addEventListener('pointermove',event => {if (splitter.hasPointerCapture(event.pointerId)){const box=signal.getBoundingClientRect();split((event.clientY-box.top)/(box.height/signal.offsetHeight));}});
addEventListener('resize',() => split(upper));
const textLayoutObserver=new ResizeObserver(()=>split(upper));
for(const node of [stationBar,signal.querySelector(".op-signal-heading"),document.querySelector("#level-legend")])textLayoutObserver.observe(node); split();
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
  const response=await stationFetch(path,{...options,signal:options.signal || AbortSignal.timeout(10000)});
  const data=await response.json();if(!response.ok) throw new Error(data.error?.code || 'request_failed');return data;
}
async function sync(current=socket) {
  if(current!==socket)return;restoreDisplayPreference();if(syncPending){syncAgain=true;return;}syncPending=true;
  try {
    const data=await request('/recording');if(current!==socket) return;
    const previousImport=snapshot?.import?.id,previousGeneration=snapshot?.generation;
    if(identity(data)!==identity(snapshot)){rows=[];resetLevels();paint();}snapshot=data;
    if(data.job?.kind!=='live'&&live?.job){live=undefined;resultRows=[];renderResults();receiveShow();}
    if(previousImport && !data.import && previousGeneration===data.generation){
      try{const outcome=await request(`/recording/imports/${previousImport}`);if(current!==socket)return;importOutcome={...outcome,generation:data.generation};}catch{if(current===socket)progress.textContent='Import outcome unavailable · current source state refreshed';}
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

const receiveControls=document.createElement('div');receiveControls.id='live-receive-controls';
receiveControls.innerHTML='<label>Next receive mode<select id="receive-mode"><option value="ft8">FT8</option><option value="ft4">FT4</option><option value="spectrum">Spectrum only</option></select></label><button id="receive-start" disabled>Start receive</button><button id="receive-stop" disabled>Stop receive</button><button id="audio-enumerate">List audio inputs</button><output id="audio-inputs"></output><p id="receive-status" role="status">Live receive unavailable until station snapshot</p>';
// The shared receive operations occupy the agreed operating toolbar.
// These are modem receive controls, not CAT mode or RF-transmit controls.
tuning.querySelector('.op-compact-label').remove();
tuning.querySelector('.op-monitor').remove();
tuning.querySelector('.op-decode-group').remove();
tuning.insertBefore(receiveControls,tuning.querySelector('.op-period'));
let live,livePending=false,liveAgain=null,resultPending=false,lastResultStart=-Infinity,resultCursor=0,resultRows=[],historyIncomplete=false,mutationPending=false,uncertainMutation=false,receiveFailure='';
let operatingState=null,operatingSupported=null,operatingFailure='',operatingReadPending=false,operatingReadAgain=false,operatingEpoch=0,operatingUnknown=null,operatingRadioUnknown=null,operatingIntent=null,lastOperatingRead=-Infinity,lastOperatingCommit=null,operatingSocket=null;
// Mutations supersede earlier reads; accepted snapshots supersede pending pages.
let receiveMutationEpoch=0,liveRevision=0,resultView=null;
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
  if(!shape(a,'device_id,device_name,error,retry_after_ms,state')||!['closed','opening','running','closing','unavailable'].includes(a.state)||![a.device_id,a.device_name,a.error].every(nullableText)||(a.retry_after_ms!==null&&(!counter(a.retry_after_ms)||a.retry_after_ms>8000)))return false;
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
  document.querySelector('#receive-start').disabled=!connected||!live||!!active||mutationPending||uncertainMutation||operatingBlocked()||!profileData?.settings.audio.input_device;
  document.querySelector('#receive-stop').disabled=!connected||!active||mutationPending||uncertainMutation||operatingSelectionBlocked()||live.job.state==='cancelling';
  if(live){
    receiveStatus.textContent=`Audio ${live.audio.state}${live.audio.error?` · ${live.audio.error}`:''}${live.job?` · ${live.job.mode.toUpperCase()} ${live.job.state}${live.job.error?` · ${live.job.error}`:''}`:' · receive stopped'}${historyIncomplete?' · Incomplete result history':''}${live.job&&['failed','cancelled'].includes(live.job.state)?' · Partial results retained':''}${receiveFailure?` · ${receiveFailure}`:''}`;
    const capabilities=document.querySelectorAll('#operating-capabilities dd');
    capabilities[0].textContent=live.audio.state==='running'?'Running · selected input':`Unavailable · ${live.audio.error??live.audio.state}`;
    capabilities[2].textContent=live.job&&live.job.mode!=='spectrum'?`${live.job.mode.toUpperCase()} · ${live.job.state}`:'Unavailable · receive stopped';
    statusBar.children[1].textContent=`Audio ${live.audio.state} \u00b7 ${live.job?`${live.job.mode.toUpperCase()} ${live.job.state}`:'Receive stopped'} \u00b7 CAT unavailable`;
    const focus=document.querySelector('#rx-focus .op-contact-identity');
    if(live.job&&live.job.mode!=='spectrum'){focus.querySelector('strong').textContent='No contact selected';focus.querySelector('div > span').textContent='Contact selection and QSO workflow are unavailable on this server.';}
    else{focus.querySelector('strong').textContent='No station selected';focus.querySelector('div > span').textContent='No station selected. Contact selection requires decoded results.';}
  }
  operatingShow();
}
async function receiveSync(current=socket){
  if(current!==socket||connection.dataset.state!=='connected')return;
  if(livePending){liveAgain=receiveMutationEpoch;return;}livePending=true;
  const epoch=receiveMutationEpoch;
  try{
    const data=await request('/receive');
    if(current!==socket||epoch!==receiveMutationEpoch)return;
    if(!validLiveSnapshot(data))throw new Error('Invalid receive snapshot');
    if(data.profile_id!==profileData.profile_id||data.boot_id!==profileData.boot_id||data.generation<(live?.generation??0))return;
    if(liveIdentity(data)!==liveIdentity(live)){
      resultRows=[];resultView=null;resultCursor=data.job?.first_sequence??0;historyIncomplete=false;
      if(data.job||live?.job){rows=[];resetLevels();paint();}
      renderResults();
    }
    live=data;liveRevision++;applyLatestDecode(data.job?.latest_decode??null,data.job?.first_sequence??0);uncertainMutation=false;receiveFailure='';receiveShow();show();
  }catch(error){if(current===socket&&epoch===receiveMutationEpoch){receiveFailure=`Live receive unavailable · ${error.message}`;receiveStatus.textContent=receiveFailure;}}
  finally{livePending=false;const again=liveAgain;liveAgain=null;if(again!==null&&again===receiveMutationEpoch)receiveSync(socket);}
}
const activitySort=document.querySelector('#activity-sort'),activityDirection=document.querySelector('#activity-direction');
function activityOrdering(){
  const id=displayPreferenceId();
  if(id&&id!==activitySortProfile){activitySortProfile=id;activitySortField='frequency';activitySortDirection='asc';}
  activitySort.value=activitySortField;activityDirection.value=activitySortDirection;
  const key=r=>activitySortField==='frequency'?r.frequency_hz:activitySortField==='signal'?r.snr_db:activitySortField==='dt'?r.dt_seconds:r.text?.toUpperCase()??null;
  const missing=v=>v===null||v===undefined||v==='';
  return [...resultRows].sort((a,b)=>{
    const left=key(a),right=key(b);
    if(missing(left)!==missing(right))return missing(left)?1:-1;
    const compared=missing(left)?0:typeof left==='number'?left-right:left<right?-1:left>right?1:0;
    return compared*(activitySortDirection==='asc'?1:-1)||a.sequence-b.sequence;
  });
}
activitySort.addEventListener('change',()=>{activitySortField=activitySort.value;activitySortDirection=activitySortField==='signal'?'desc':'asc';renderResults();});
activityDirection.addEventListener('change',()=>{activitySortDirection=activityDirection.value;renderResults();});
function renderResults(){
  const ordered=activityOrdering();
  const body=document.querySelector('#band-activity tbody');
  const loading=resultView&&resultCursor<resultView.next_sequence;
  document.querySelector('#band-activity header .op-muted').textContent=resultView?
    `Latest ${live?.job?.mode.toUpperCase()} period ${periodLabel(resultView.period_start_utc,live?.job?.mode)}${resultView.period_start_utc?' UTC':''} \u00b7 ${resultView.complete?'Attempt complete':'Partial'}${loading?' \u00b7 Loading results':''}${historyIncomplete?' \u00b7 Incomplete history':''}`:'Latest decode period';
  document.querySelector('#band-activity header .op-muted').title=resultView?.period_start_utc?'Timing relative to station system clock; external UTC accuracy unknown. DT positive: late; negative: early.':'Station clock correlation unavailable until supplied by this source.';
  document.querySelector('#band-activity .op-count').textContent=`${resultRows.length} message${resultRows.length===1?'':'s'}`;
  if(!resultRows.length){
    body.innerHTML='<tr><td colspan="6" class="empty-messages"><strong></strong><span></span></td></tr>';
    const decoder=live?.job&&['ft4','ft8'].includes(live.job.mode),job=live?.job;
    let heading='Decoder unavailable',message='No decoded messages are available from this server.';
    if(decoder){
      const mode=job.mode.toUpperCase();
      heading=job.state==='running'?(connection.dataset.state==='connected'?`Listening for ${mode}`:`${mode} receive status stale`):job.state==='cancelling'?`Stopping ${mode} receive`:`${mode} receive ${job.state}`;
      message=['running','cancelling'].includes(job.state)?'No verified messages decoded yet.':'No verified messages were decoded.';
      if(resultView){heading=loading?'Loading latest decode':resultView.complete?'No stations decoded':'No stations decoded in partial attempt';message=loading?'Latest-period results are being received.':'No verified stations were decoded in this period.';}
    }
    body.querySelector('strong').textContent=heading;body.querySelector('span').textContent=message;return;
  }
  body.replaceChildren();
  const labels=[...document.querySelectorAll('#band-activity th')].map(th=>th.textContent);
  for(const record of ordered){
    const row=document.createElement('tr');row.setAttribute('role','row');row.dataset.resultId=`${liveIdentity(live)}/${record.sequence}`;row.dataset.sequence=String(record.sequence);
    for(const [index,text] of [periodLabel(record.period_start_utc,live.job.mode),record.snr_db===null?'—':record.snr_db.toFixed(1),record.dt_seconds===null?'—':`${Math.abs(record.dt_seconds)<0.05?'+':record.dt_seconds<0?'-':'+'}${Math.abs(record.dt_seconds).toFixed(1)}`,record.frequency_hz.toFixed(1),record.status==='decoded'?record.text:`Payload ${record.status}`,record.status==='decoded'?'Decoded':record.status].entries()){
      const cell=document.createElement('td');cell.setAttribute('role','cell');cell.dataset.label=labels[index];cell.textContent=text;row.append(cell);
    }
    body.append(row);
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
  const context=liveIdentity(live),current=socket,cursor=resultCursor,revision=liveRevision,epoch=receiveMutationEpoch;
  const query=new URLSearchParams({source_id:live.source.id,job_id:live.job.id,generation:String(live.generation),cursor:String(cursor),limit:profileSelect.value==='thin'?'1':'16'});
  try{
    const response=await stationFetch(`/receive/results?${query}`,{signal:AbortSignal.timeout(10000)}),page=await response.json();
    if(current!==socket||context!==liveIdentity(live)||revision!==liveRevision||epoch!==receiveMutationEpoch)return;
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
document.querySelector('#receive-start').addEventListener('click',async()=>{
  if(!live||mutationPending)return;receiveMutationEpoch++;mutationPending=true;receiveShow();
  try{await request('/receive/start',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:live.profile_id,boot_id:live.boot_id,generation:live.generation,profile_revision:profileData.revision,mode:document.querySelector('#receive-mode').value})});await sync();await receiveSync();}
  catch(error){receiveMutationEpoch++;uncertainMutation=true;receiveFailure=`Start outcome unknown · ${error.message} · refresh before another action`;}
  finally{mutationPending=false;receiveShow();}
});
document.querySelector('#receive-stop').addEventListener('click',async()=>{
  if(!live?.job||mutationPending)return;receiveMutationEpoch++;mutationPending=true;receiveShow();
  try{await request('/receive/stop',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:live.profile_id,boot_id:live.boot_id,generation:live.generation,job_id:live.job.id})});await receiveSync();await sync();}
  catch(error){receiveMutationEpoch++;uncertainMutation=true;receiveFailure=`Stop outcome unknown · ${error.message} · refresh before another action`;}
  finally{mutationPending=false;receiveShow();}
});
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
operatingControls.innerHTML='<label>Operating mode<select id="operating-mode" disabled><option value="ft8">FT8</option><option value="ft4">FT4</option></select></label><label>Band<select id="operating-band" disabled><option value="">Choose band</option></select></label><button id="operating-monitor" disabled aria-pressed="false">Monitor</button><button id="operating-stop" disabled>Stop</button><button id="operating-refresh" disabled>Refresh operating state</button><label class="receive-only-verification"><input type="checkbox" id="radio-receive-only">Receive-only keying/inhibit verified</label><button id="radio-connect" disabled>Connect CAT</button><button id="radio-disconnect" disabled>Disconnect CAT</button><output id="operating-radio">CAT readback unavailable</output><p id="operating-selection-status" role="status">Operating selection unavailable until station snapshot</p>';
receiveControls.before(operatingControls);
const operatingMode=document.querySelector('#operating-mode'),operatingBand=document.querySelector('#operating-band'),operatingStatus=document.querySelector('#operating-selection-status');
const operatingBands=['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m','4m'];
const operatingUuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(v);
const operatingCounter=v=>Number.isSafeInteger(v)&&v>=0;
const operatingShape=(v,keys)=>v!==null&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).sort().join(',')===keys.split(',').sort().join(',');
const operatingNullable=(v,valid)=>v===null||valid(v);
const operatingModeValid=v=>['ft4','ft8'].includes(v);
const operatingFrequency=v=>Number.isSafeInteger(v)&&v>=30000&&v<=74800000;
function operatingSelectionBlocked(){return !!operatingUnknown||!!operatingIntent||operatingState?.operation?.result==='pending';}
function operatingBlocked(){return operatingSelectionBlocked()||!!operatingRadioUnknown;}
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
  document.querySelector('#operating-monitor').disabled=!connected||!live||mutationPending||uncertainMutation||!!operatingUnknown||(active?live.job.state==='cancelling':(!!operatingRadioUnknown||!live.audio||!profileData?.settings.audio.input_device||s?.receive.owner_released===false));
  document.querySelector('#operating-monitor').setAttribute('aria-pressed',String(!!active));
  document.querySelector('#operating-stop').disabled=!connected||(!target&&(!active||mutationPending||uncertainMutation));
  document.querySelector('#operating-refresh').disabled=!connected||operatingReadPending;
  document.querySelector('#radio-connect').disabled=!ready||mutationPending||operatingBlocked()||s.control!=='cat'||['ready','connecting','closing'].includes(s.radio.state)||!document.querySelector('#radio-receive-only').checked;
  document.querySelector('#radio-disconnect').disabled=!ready||s.radio.connection_generation===0||s.radio.state==='closed';
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
  const dial=document.querySelector('#op-dial');dial.value=frequency.value!==null?(frequency.value/1e6).toFixed(6):s.selection.nominal_hz!==null?(s.selection.nominal_hz/1e6).toFixed(6):'';dial.title=`${observed}. ${nominal}`;dial.setAttribute('aria-label',frequency.value!==null?'Observed dial frequency':'Nominal dial frequency, actual rig unconfirmed');
  const capabilities=document.querySelectorAll('#operating-capabilities dd');capabilities[1].textContent=!connected?'Unavailable · status stale':s.radio.state==='ready'?'Ready · IC-7300 readback':`Unavailable · ${s.radio.error??s.radio.state}`;
  if(live)statusBar.children[1].textContent=`Audio ${live.audio.state} · ${live.job?live.job.mode.toUpperCase()+' '+live.job.state:'Receive stopped'} · CAT ${s.radio.state}`;
  const o=s.operation;
  operatingStatus.textContent=operatingFailure||(operatingUnknown?'Selection outcome unknown · refresh or Stop to cancel/fence before another action':mutationPending&&operatingIntent?'Selection request pending · waiting for server admission':o?`${o.result==='pending'?'Switching':o.phase} · ${o.requested.mode.toUpperCase()} ${o.requested.band}${o.error?' · '+o.error:''}`:`${s.selection.mode.toUpperCase()} · choose a band to establish nominal frequency`);
}
async function operatingSync(reconcile=false){
  if(connection.dataset.state!=='connected'||!profileData)return;
  if(operatingReadPending){if(reconcile)operatingReadAgain=true;return;}
  operatingReadPending=true;lastOperatingRead=performance.now();const epoch=operatingEpoch,current=socket;
  try{
    const response=await stationFetch('/receive/selection',{signal:AbortSignal.timeout(10000)}),text=await response.text();
    if(epoch!==operatingEpoch||current!==socket||current.readyState!==WebSocket.OPEN||connection.dataset.state!=='connected')return;
    let s;try{s=JSON.parse(text);}catch{throw new Error('Invalid operating snapshot');}
    if(response.status===404||response.status===400&&s.error?.code==='unsupported_version'||s&&typeof s.v==='number'&&s.v!==1){operatingSupported=false;operatingFailure='Operating controls unsupported by this server';return;}
    if(!response.ok)throw new Error(s.error?.code||'Operating state unavailable');
    if(new TextEncoder().encode(text).length>3072||!validOperatingState(s))throw new Error('Invalid operating snapshot');
    if(s.profile_id!==profileData.profile_id||s.boot_id!==profileData.boot_id||s.profile_revision!==profileData.revision)throw new Error('Operating identity is stale');
    if(operatingState?.boot_id===s.boot_id&&s.snapshot_sequence<operatingState.snapshot_sequence)return;
    const resolved=operatingUnknown&&reconcile&&(s.boot_id!==operatingUnknown.boot_id||s.operation?.command_id===operatingUnknown.command_id||s.operating_revision>operatingUnknown.base_revision);
    if(resolved)operatingUnknown=null;
    if(operatingRadioUnknown&&reconcile){const unknown=operatingRadioUnknown;
      if(s.boot_id!==unknown.boot_id||s.profile_revision!==unknown.profile_revision||s.radio.connection_generation>unknown.connection_generation||(unknown.action==='disconnect'&&s.radio.state==='closed')){operatingRadioUnknown=null;operatingFailure='';}
    }
    if(operatingIntent&&(s.operation?.command_id===operatingIntent.command_id||s.operating_revision>operatingIntent.base_revision))operatingIntent=null;
    operatingState=s;operatingSupported=true;if(resolved||operatingFailure.startsWith('Operating state stale')||operatingFailure==='Disconnected · operating data stale')operatingFailure='';
    if(s.selection.confirmed_command_id&&s.selection.confirmed_command_id!==lastOperatingCommit){lastOperatingCommit=s.selection.confirmed_command_id;document.querySelector('#receive-mode').value=s.selection.mode;}
  }catch(error){if(epoch===operatingEpoch&&current===socket){operatingFailure=`Operating state stale · ${error.message}`;operatingSupported=null;}}
  finally{operatingReadPending=false;operatingShow();receiveShow();if(operatingReadAgain){operatingReadAgain=false;operatingSync(true);}}
}
async function operatingSelect(action,value){
  if(!operatingState||mutationPending||uncertainMutation||operatingBlocked())return;
  const s=operatingState,command_id=crypto.randomUUID(),epoch=++operatingEpoch;
  const body={v:1,profile_id:s.profile_id,boot_id:s.boot_id,command_id,action,profile_revision:s.profile_revision,generation:s.generation,operating_revision:s.operating_revision,[action]:value};
  operatingIntent={command_id,base_revision:s.operating_revision,boot_id:s.boot_id};receiveMutationEpoch++;mutationPending=true;operatingFailure='';receiveShow();
  try{
    const response=await stationFetch('/receive/select',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(10000)}),text=await response.text(),ack=JSON.parse(text);
    if(epoch!==operatingEpoch)return;
    if(!response.ok){operatingFailure=`Selection refused · ${ack.error?.code??'request_failed'}`;operatingIntent=null;return;}
    if(new TextEncoder().encode(text).length>384||!operatingShape(ack,'v,profile_id,boot_id,command_id,operating_revision,accepted,phase')||ack.v!==1||ack.profile_id!==s.profile_id||ack.boot_id!==s.boot_id||ack.command_id!==command_id||ack.accepted!==true||!operatingCounter(ack.operating_revision)||ack.operating_revision<=s.operating_revision||!['releasing','applying','restarting','applied','failed','release_blocked'].includes(ack.phase))throw new Error('Invalid admission receipt');
  }catch(error){if(epoch===operatingEpoch){operatingUnknown=operatingIntent;operatingFailure=`Selection outcome unknown · ${error.message} · refresh or Stop to cancel/fence`;}}
  finally{if(epoch===operatingEpoch){mutationPending=false;receiveShow();await operatingSync(true);await receiveSync();}}
}
async function operatingStop(){
  const s=operatingState,target=operatingUnknown??operatingIntent??(s?.operation?{command_id:s.operation.command_id,base_revision:s.operation.base_revision,boot_id:s.boot_id}:null);
  if(!target||(!operatingUnknown&&!operatingIntent&&s?.operation?.result!=='pending')){document.querySelector('#receive-stop').click();return;}
  const epoch=++operatingEpoch;receiveMutationEpoch++;mutationPending=true;operatingFailure='';receiveShow();
  try{
    const command_id=crypto.randomUUID();
    const response=await stationFetch('/receive/select',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,profile_id:profileData.profile_id,boot_id:target.boot_id,command_id,action:'cancel',operating_revision:target.base_revision,target_command_id:target.command_id}),signal:AbortSignal.timeout(10000)}),text=await response.text(),ack=JSON.parse(text);
    if(!response.ok)throw new Error(ack.error?.code??'Stop refused');
    if(new TextEncoder().encode(text).length>384||!operatingShape(ack,'v,profile_id,boot_id,command_id,operating_revision,accepted,phase')||ack.v!==1||ack.profile_id!==profileData.profile_id||ack.boot_id!==target.boot_id||ack.command_id!==command_id||ack.accepted!==true||ack.phase!=='cancelled'||!operatingCounter(ack.operating_revision))throw new Error('Invalid cancellation receipt');
    if(epoch===operatingEpoch){operatingUnknown=null;operatingIntent=null;}
  }catch(error){if(epoch===operatingEpoch){operatingUnknown=target;operatingFailure=`Stop outcome unknown · ${error.message} · refresh before another action`;}}
  finally{if(epoch===operatingEpoch){mutationPending=false;await operatingSync(true);await receiveSync();receiveShow();}}
}
operatingMode.addEventListener('change',()=>operatingSelect('mode',operatingMode.value));
operatingBand.addEventListener('change',()=>{if(operatingBand.value)operatingSelect('band',operatingBand.value);});
document.querySelector('#operating-monitor').addEventListener('click',()=>{if(operatingState?.operation?.result==='pending'||operatingUnknown||operatingIntent)operatingStop();else if(live?.job&&['running','cancelling'].includes(live.job.state))document.querySelector('#receive-stop').click();else document.querySelector('#receive-start').click();});
document.querySelector('#operating-stop').addEventListener('click',operatingStop);
document.querySelector('#operating-refresh').addEventListener('click',()=>operatingSync(true));
document.querySelector('#radio-receive-only').addEventListener('change',operatingShow);
for(const action of ['connect','disconnect'])document.querySelector('#radio-'+action).addEventListener('click',async()=>{
  const s=operatingState;if(!s||mutationPending)return;const epoch=++operatingEpoch;receiveMutationEpoch++;mutationPending=true;receiveShow();
  try{const response=await stationFetch('/radio/'+action,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(action==='connect'?{v:1,profile_id:s.profile_id,boot_id:s.boot_id,profile_revision:s.profile_revision,receive_only_verified:document.querySelector('#radio-receive-only').checked}:{v:1,profile_id:s.profile_id,boot_id:s.boot_id,connection_generation:s.radio.connection_generation}),signal:AbortSignal.timeout(10000)}),text=await response.text(),ack=JSON.parse(text);
    if(!response.ok){if(!operatingShape(ack,'error')||!operatingShape(ack.error,'code,field')||typeof ack.error.code!=='string'||ack.error.field!==null)throw new Error('Invalid CAT refusal');operatingFailure=`CAT ${action} refused · ${ack.error.code}`;return;}
    if(new TextEncoder().encode(text).length>2048)throw new Error('Invalid CAT receipt size');
    if(!operatingShape(ack,'v,profile_id,boot_id,connection_generation,state,error,device_id,effective_baud,observation')||ack.v!==1||ack.profile_id!==s.profile_id||ack.boot_id!==s.boot_id||!operatingCounter(ack.connection_generation))throw new Error('Invalid CAT receipt');
  }
  catch(error){if(epoch===operatingEpoch){operatingRadioUnknown={action,connection_generation:s.radio.connection_generation,profile_revision:s.profile_revision,boot_id:s.boot_id};operatingFailure=`CAT ${action} outcome unknown · ${error.message} · refresh before another action`;}}
  finally{if(epoch===operatingEpoch){mutationPending=false;await operatingSync(true);receiveShow();}}
});
refresh.addEventListener('click',()=>{if(operatingUnknown||operatingIntent||operatingFailure.startsWith('Operating state stale')||operatingFailure.startsWith('CAT '))operatingSync(true);});
addEventListener('station-ready',event=>{
  const replaced=operatingState&&operatingState.boot_id!==profileData?.boot_id;
  const edited=operatingState&&operatingState.profile_revision!==profileData?.revision;
  if(replaced||edited){if(operatingIntent||operatingRadioUnknown)mutationPending=false;operatingState=null;operatingUnknown=null;operatingRadioUnknown=null;operatingIntent=null;operatingEpoch++;}
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
