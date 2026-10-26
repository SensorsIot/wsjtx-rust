'use strict';
const main = document.querySelector('main'), controls = document.createElement('div');
controls.id = 'controls';
while (main.firstChild) controls.append(main.firstChild);
const signal = document.createElement('section'); signal.id = 'signal'; signal.setAttribute('aria-label','Recorded spectrum and waterfall');
signal.innerHTML = '<h2>Recorded receive</h2><p id="signal-status" role="status">Waiting for station snapshot</p><p id="signal-meta"></p><canvas id="spectrum" aria-label="Spectrum in calibrated dBFS"></canvas><div id="frequency-ruler" aria-label="Fixed frequency span 0 to 3000 Hz"></div><div id="waterfall-wrap"><div id="time-ruler"></div><canvas id="waterfall" tabindex="0" aria-label="Waterfall in source seconds; arrow keys select native bins and rows"></canvas></div><div id="level-legend"></div>';

const splitter = document.createElement('div'); splitter.id = 'splitter'; splitter.tabIndex = 0;
for (const [key,value] of Object.entries({role:'separator','aria-orientation':'horizontal','aria-label':'Resize spectrum and controls','aria-controls':'signal controls'})) splitter.setAttribute(key,value);
main.append(signal,splitter,controls);
const panel = document.createElement('section'); panel.id = 'recording-controls'; panel.setAttribute('aria-label','Recording controls');
panel.innerHTML = '<label>Import mono 12 kHz PCM16 WAV (up to 120 seconds)<input id="recording-file" type="file" accept=".wav,audio/wav"></label><button id="recording-import">Import recording</button><button id="recording-replay" disabled>Replay spectrum</button><button id="recording-cancel" disabled>Cancel operation</button><label>Display <select id="display-profile"><option value="detail">Detailed (fast link, up to 10 KiB/s per viewer)</option><option value="thin">Thin (32 kbit/s link)</option><option value="off">Off</option></select></label><p>One processing worker per station · no speaker playback</p><p id="recording-progress" role="status"></p>';
const localLevels=document.createElement('div');localLevels.id='display-levels';
localLevels.innerHTML='<label>Black level (dBFS)<input id="display-black" type="number" min="-120" max="-30" step="1" value="-120"></label><label>Range (dB)<input id="display-range" type="number" min="10" max="80" step="1" value="30"></label><label><input id="display-auto" type="checkbox" checked> Auto black</label><output id="bin-readout" aria-live="polite">Select a bin with pointer or arrow keys</output>';
panel.append(localLevels,document.querySelector('#signal-meta'));
controls.insertBefore(panel,document.querySelector('#profile-panel'));
const profileSelect=document.querySelector('#display-profile');
profileSelect.value=location.protocol==='http:'&&['localhost','127.0.0.1','[::1]'].includes(location.hostname)?'detail':'thin';
let displayBlack=-120, displayRange=30, autoBlack=true, estimateFrozen=false, selectedBin=0, selectedRow=0, fallbackText='', detailRequest;
const palette=[[0,[0,0,12]],[.15,[0,0,80]],[.35,[0,80,220]],[.50,[0,220,240]],[.65,[30,230,80]],[.80,[255,235,0]],[.95,[255,40,0]],[1,[255,255,255]]];
function color(q) {
  const t=Math.max(0,Math.min(1,(q-120-displayBlack)/displayRange));
  const i=Math.max(1,palette.findIndex(([p])=>p>=t)),[lo,a]=palette[i-1],[hi,b]=palette[i];
  return `rgb(${a.map((v,k)=>Math.floor(v+(b[k]-v)*(t-lo)/(hi-lo)+.5)).join(' ')})`;
}
function resetLevels(){displayBlack=-120;displayRange=30;autoBlack=true;estimateFrozen=false;selectedBin=0;selectedRow=0;updateLevels();}
function updateLevels(){
  document.querySelector('#display-black').value=displayBlack;document.querySelector('#display-black').max=-displayRange;
  document.querySelector('#display-range').value=displayRange;document.querySelector('#display-auto').checked=autoBlack;
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
  const available = Math.max(372,innerHeight)-12, maximum = available-200;
  upper = Math.max(160,Math.min(maximum,value ?? available/2));
  signal.style.height = `${upper}px`;
  for (const [name,value] of [['min',160],['max',maximum],['now',Math.round(upper)]]) splitter.setAttribute(`aria-value${name}`,String(value));
  paint();
}
splitter.addEventListener('keydown',event => {
  const values = {ArrowUp:upper-16,ArrowDown:upper+16,Home:160,End:Math.max(372,innerHeight)-212};
  if (event.key in values) {event.preventDefault();split(values[event.key]);}
});
splitter.addEventListener('pointerdown',event => {splitter.setPointerCapture(event.pointerId);splitter.focus();});
splitter.addEventListener('pointermove',event => {if (splitter.hasPointerCapture(event.pointerId)) split(event.clientY);});
addEventListener('resize',() => split(upper)); split();
function readout(){
  const row=rows.at(-1-selectedRow), B=profileSelect.value==='detail'?1024:128;
  selectedBin=Math.max(0,Math.min(B-1,selectedBin));selectedRow=Math.max(0,Math.min(rows.length-1,selectedRow));
  const text=document.querySelector('#bin-readout');
  if(!row?.levels){text.textContent='Gap: no measurement';return;}
  const W=document.querySelector('#waterfall').width,x=Math.floor(selectedBin*W/B);
  const first=W<B?Math.ceil(x*B/W):selectedBin,last=W<B?Math.min(B-1,Math.ceil((x+1)*B/W)-1):selectedBin;
  const peak=Math.max(...row.levels.slice(first,last+1));
  text.textContent=`Native bin ${selectedBin} | ${(selectedBin*3000/B).toFixed(4)} Hz | ${row.levels[selectedBin]-120} dBFS | source ${(row.first_frame/12000).toFixed(1)}-${(row.end_frame/12000).toFixed(3)} s${W<B?` | projected bins ${first}-${last}: ${peak-120} dBFS`:''}`;
}
const waterfall=document.querySelector('#waterfall');
waterfall.addEventListener('pointermove',e=>{
  const box=waterfall.getBoundingClientRect(),B=profileSelect.value==='detail'?1024:128,h=Math.max(1,Math.round(2*devicePixelRatio));
  selectedBin=Math.min(B-1,Math.max(0,Math.floor((e.clientX-box.left)/box.width*B+.5)));
  selectedRow=Math.min(rows.length-1,Math.max(0,Math.floor((e.clientY-box.top)*devicePixelRatio/h)));readout();
});
waterfall.addEventListener('keydown',e=>{
  if(!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key))return;e.preventDefault();
  if(e.key==='ArrowLeft')selectedBin--;if(e.key==='ArrowRight')selectedBin++;
  if(e.key==='ArrowUp')selectedRow--;if(e.key==='ArrowDown')selectedRow++;
  selectedRow=Math.max(0,Math.min(rows.length-1,selectedRow));readout();
});
function paint() {
  if(drawPending)return;drawPending=true;
  requestAnimationFrame(()=>{
    drawPending=false;
    const B=profileSelect.value==='detail'?1024:128,h=Math.max(1,Math.round(2*devicePixelRatio));
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
        const visible=Math.min(rows.length,Math.ceil(c.height/h));
        for(let r=0;r<visible;r++){
          const row=rows.at(-1-r),y=r*h;if(!row.levels){ctx.fillStyle='rgb(96 96 96)';ctx.fillRect(0,y,c.width,h);continue;}
          const values=project(row.levels);values.forEach((q,k)=>{
            const x=Math.floor(k*c.width/values.length),right=Math.floor((k+1)*c.width/values.length);
            ctx.fillStyle=color(q);ctx.fillRect(x,y,right-x,h);
          });
        }
        const last=rows.at(-1),oldest=rows.at(-visible),range=last?`${(oldest.first_frame/12000).toFixed(1)} to ${(last.end_frame/12000).toFixed(1)} seconds`:'';
        c.dataset.rows=String(rows.length);c.dataset.sequences=rows.map(r=>r.sequence).join(',');c.dataset.bins=String(B);c.dataset.span='0,3000';
        c.setAttribute('aria-label',`Waterfall, visible source time ${range}; newest top, grey rows are gaps; arrow keys select native bins and rows`);
        const ruler=document.querySelector('#time-ruler');ruler.replaceChildren();
        if(last){
          const latest=last.first_frame/12000,step=B===1024?.2:1,times=[latest];
          for(let t=Math.floor(latest/5)*5;t>=oldest.first_frame/12000;t-=5)if(latest-t>=16*devicePixelRatio/h*step)times.push(t);
          for(const t of times){const label=document.createElement('span');label.textContent=`${t.toFixed(1)}s`;label.style.top=`${(latest-t)/step*h/devicePixelRatio}px`;ruler.append(label);}
        }
      }
    }
    const ruler=document.querySelector('#frequency-ruler');ruler.replaceChildren();
    for(let f=0;f<=3000;f+=100){const tick=document.createElement('span');tick.style.left=`${f/30}%`;tick.className=f%500?'minor':'major';if(f%500===0)tick.textContent=String(f);ruler.append(tick);}
    const legend=document.querySelector('#level-legend');
    legend.textContent=`0-3000 Hz | ${B===1024?'2.93 Hz/bin | 5 rows/s':'23.44 Hz/group | 1 row/s'} | Display ${displayBlack} to ${displayBlack+displayRange} dBFS`;
    legend.title=B===1024?'Detailed: 2.9296875 Hz native bins; 0.2 s rows; 4096/12000 = 0.341333 s Hann window support':'Thin: 23.4375 Hz groups; 1 s rows; 2048/12000 s Hann window support';
    legend.setAttribute('aria-label',`${legend.textContent}; ${legend.title}`);
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
  if(Object.keys(f).sort().join(',')!==keys||!Number.isSafeInteger(f.sequence)||f.sequence<0||f.sequence>=cap||f.first_frame!==f.sequence*interval||f.end_frame!==Math.min(f.first_frame+interval,snapshot.recording?.frames))return;
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
