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
<section id="band-activity" class="message-pane op-card op-activity" aria-labelledby="activity-heading"><header><div><h3 id="activity-heading">Band Activity <span class="op-count">0</span></h3><span class="op-muted">Latest receive periods</span></div><button type="button" class="op-filter" disabled title="Server filtering unavailable">&#9663; All decodes</button></header><div class="op-search"><input disabled aria-label="Find a callsign or message" placeholder="Find callsign or message&#8230;"><span>Unavailable</span></div><div class="op-table-wrap"><table><thead><tr><th>UTC</th><th>dB</th><th>DT</th><th>Hz</th><th>Message</th><th>Status</th></tr></thead><tbody><tr><td colspan="6" class="empty-messages"><strong>Decoder unavailable</strong><span>No decoded messages are available from this server.</span></td></tr></tbody></table></div><footer><span class="op-selection-dot"></span>Station selection requires decoded results<span class="op-muted">No sample data</span></footer></section>
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
profileSelect.value=location.protocol==='http:'&&['localhost','127.0.0.1','[::1]'].includes(location.hostname)?'detail':'thin';
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
}
async function request(path,options={}) {
  const response=await fetch(path,{...options,signal:options.signal || AbortSignal.timeout(10000)});
  const data=await response.json();if(!response.ok) throw new Error(data.error?.code || 'request_failed');return data;
}
async function sync(current=socket) {
  if(current!==socket)return;if(syncPending){syncAgain=true;return;}syncPending=true;
  try {
    const data=await request('/recording');if(current!==socket) return;
    const previousImport=snapshot?.import?.id,previousGeneration=snapshot?.generation;
    if(identity(data)!==identity(snapshot)){rows=[];resetLevels();paint();}snapshot=data;
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
    if(snapshot && (message.data.generation!==snapshot.generation || message.data.state!==(snapshot.job?.state??null) || message.data.source_id!==(snapshot.recording?.id??null) || message.data.job_id!==(snapshot.job?.id??null))) sync(current);
    return;
  }
  if(message.type==='error'&&message.data.code==='unknown_command'){
    if(message.id===detailRequest&&profileSelect.value==='detail'){detailRequest=undefined;profileSelect.value='thin';rows=[];resetLevels();fallbackText='Detailed unavailable; using Thin';subscribe(current);show();paint();}
    else {statusText.textContent='Recording display unavailable on this server';}return;
  }
  const detail=profileSelect.value==='detail';
  if(message.type!==(detail?'spectrum.detail.frame':'spectrum.frame')||profileSelect.value==='off')return;
  const f=message.data, B=detail?1024:128,interval=detail?2400:12000,cap=detail?600:120;
  if(!f||!snapshot||!['running','completed'].includes(snapshot.job?.state)||f.boot_id!==snapshot.boot_id||f.generation!==snapshot.generation||f.job_id!==snapshot.job?.id||f.source_id!==snapshot.job?.source_id)return;
  if(Object.keys(message).sort().join(',')!=='data,type,v'||message.v!==1)return;
  const keys=['boot_id','source_id','job_id','generation','sequence','first_frame','end_frame',detail?'levels_b64':'levels'].sort().join(',');
  if(Object.keys(f).sort().join(',')!==keys||!Number.isSafeInteger(f.sequence)||f.sequence<0||f.sequence>=cap||f.first_frame!==f.sequence*interval||f.first_frame>=snapshot.recording.frames||f.end_frame<=f.first_frame||f.end_frame!==Math.min(f.first_frame+interval,snapshot.recording?.frames))return;
  let values=f.levels;
  if(detail){
    if(typeof f.levels_b64!=='string'||f.levels_b64.length!==1368||!/^[A-Za-z0-9+/]{1366}==$/.test(f.levels_b64))return;
    try{const raw=atob(f.levels_b64);if(raw.length!==1024||btoa(raw)!==f.levels_b64)return;values=Uint8Array.from(raw,c=>c.charCodeAt(0));}catch{return;}
  }
  if((!detail&&!Array.isArray(values))||values.length!==B||!values.every(q=>Number.isInteger(q)&&q>=0&&q<=120))return;
  const previous=rows.at(-1)?.sequence??-1;if(f.sequence<=previous)return;
  for(let sequence=Math.max(previous+1,f.sequence-cap+1);sequence<f.sequence;sequence++)rows.push({sequence,first_frame:sequence*interval,end_frame:Math.min((sequence+1)*interval,snapshot.recording.frames),levels:null});
  const row={...f,levels:Uint8Array.from(values)};rows.push(row);rows=rows.slice(-cap);estimate(row);paint();

  snapshot.job.processed_frames=f.end_frame;show();
});
setInterval(()=>{if(socket?.readyState===WebSocket.OPEN && snapshot)socket.send(JSON.stringify({v:1,type:'recording.get',id:nextId++}));},2000);
setInterval(()=>{if(socket?.readyState===WebSocket.OPEN && snapshot?.import && !uploading)sync();},5000);
function startBody(){return {v:1,profile_id:snapshot.profile_id,boot_id:snapshot.boot_id,generation:snapshot.generation};}
document.querySelector('#recording-import').addEventListener('click',async()=>{
  const file=document.querySelector('#recording-file').files[0];if(!file){progress.textContent='Choose a WAV recording.';return;}
  if(file.size===0||file.size>3145728){progress.textContent='request_too_large';return;}
  uploading=true;stopped=false;show();
  try{
    const operation=await request('/recording/imports',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(startBody())});
    uploadId=operation.id;
    if(stopped){const outcome=await request(`/recording/imports/${uploadId}`,{method:'DELETE'});await sync();importOutcome={...outcome,generation:operation.generation};show();return;}
    uploadAbort=new AbortController();await sync();
    for(let offset=0;offset<file.size&&!stopped;offset+=2048){
      const end=Math.min(offset+2048,file.size);
      const result=await request(`/recording/imports/${uploadId}`,{method:'PUT',headers:{'Content-Type':'audio/wav','Content-Range':`bytes ${offset}-${end-1}/${file.size}`},body:file.slice(offset,end),signal:uploadAbort.signal});
      progress.textContent=`${result.state} · ${end} / ${file.size} bytes`;
    }
  }catch(error){progress.textContent=`Import outcome · ${error.message} · refresh state before starting again`;}
  finally{uploading=false;uploadAbort=null;uploadId=null;await sync();}
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
profileSelect.addEventListener('change',()=>{rows=[];fallbackText='';resetLevels();paint();if(socket?.readyState===WebSocket.OPEN)subscribe(socket);});
if(socket?.readyState===WebSocket.OPEN && profileData && connection.dataset.state==='connected')sync(socket);
