'use strict';
const main = document.querySelector('main'), controls = document.createElement('div');
controls.id = 'controls';
while (main.firstChild) controls.append(main.firstChild);
const signal = document.createElement('section'); signal.id = 'signal'; signal.setAttribute('aria-label','Recorded spectrum and waterfall');
signal.innerHTML = '<h2>Recorded receive</h2><p id="signal-status" role="status">Waiting for station snapshot</p><p id="signal-meta"></p><canvas id="spectrum" aria-label="Peak spectrum in dBFS"></canvas><div class="axes"><span>0 Hz</span><span>1500 Hz</span><span>3000 Hz</span></div><canvas id="waterfall" aria-label="Waterfall, time relative to recording start in seconds"></canvas><div class="axes"><span>Source time (s)</span><span>Level: −120 to 0 dBFS</span></div>';
const splitter = document.createElement('div'); splitter.id = 'splitter'; splitter.tabIndex = 0;
for (const [key,value] of Object.entries({role:'separator','aria-orientation':'horizontal','aria-label':'Resize spectrum and controls','aria-controls':'signal controls'})) splitter.setAttribute(key,value);
main.append(signal,splitter,controls);
const panel = document.createElement('section'); panel.id = 'recording-controls'; panel.setAttribute('aria-label','Recording controls');
panel.innerHTML = '<label>Import mono 12 kHz PCM16 WAV (up to 120 seconds)<input id="recording-file" type="file" accept=".wav,audio/wav"></label><button id="recording-import">Import recording</button><button id="recording-replay" disabled>Replay spectrum</button><button id="recording-cancel" disabled>Cancel operation</button><label>Display <select id="display-profile"><option value="thin">Thin</option><option value="off">Off</option></select></label><p>One processing worker per station · no speaker playback</p><p id="recording-progress" role="status"></p>';
panel.append(document.querySelector('#signal-meta'));
controls.insertBefore(panel,document.querySelector('#profile-panel'));
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
function paint() {
  if (drawPending) return; drawPending = true;
  requestAnimationFrame(() => {
    drawPending = false;
    for (const id of ['spectrum','waterfall']) {
      const canvas = document.querySelector(`#${id}`), box = canvas.getBoundingClientRect();
      canvas.width = Math.max(1,Math.round(box.width*devicePixelRatio)); canvas.height = Math.max(1,Math.round(box.height*devicePixelRatio));
      const c = canvas.getContext('2d'); c.fillStyle='#07131b';c.fillRect(0,0,canvas.width,canvas.height);
      if (id === 'spectrum' && rows.length) {
        const row=rows.at(-1); if (!row.levels) continue;
        c.strokeStyle='#93e4bf';c.beginPath();row.levels.forEach((q,b) => {const x=b*canvas.width/128,y=(120-q)*canvas.height/120;b?c.lineTo(x,y):c.moveTo(x,y);});c.stroke();
        c.fillStyle='#e5efed';c.font=`${12*devicePixelRatio}px sans-serif`;c.fillText('0 dBFS',3,14*devicePixelRatio);c.fillText('−120 dBFS',3,canvas.height-3);
      } else if(id === 'waterfall') {
        rows.forEach((row,r) => {
          const y=Math.floor(r*canvas.height/Math.max(1,rows.length)),h=Math.max(1,Math.floor((r+1)*canvas.height/Math.max(1,rows.length))-y);
          if(row.levels) row.levels.forEach((q,b) => {const x=Math.floor(b*canvas.width/128);c.fillStyle=`hsl(${240-q*2} 85% ${8+q*.55}%)`;c.fillRect(x,y,Math.floor((b+1)*canvas.width/128)-x,h);});
          else {c.fillStyle='#686868';c.fillRect(0,y,canvas.width,h);}
        });
      }
    }
    document.querySelector('#waterfall').dataset.rows=String(rows.length);
    document.querySelector('#waterfall').dataset.sequences=rows.map(r=>r.sequence).join(',');
    document.querySelector('#waterfall').setAttribute('aria-label',rows.length ? `Waterfall, source time ${rows[0].sequence} to ${rows.at(-1).end_frame/12000} seconds; grey rows are gaps` : 'Waterfall, source time in seconds');
    signal.querySelector('.axes:last-child span').textContent=rows.length ? `Source time: ${rows[0].sequence}–${rows.at(-1).end_frame/12000} s` : 'Source time (s)';
  });
}
function show() {
  const active = snapshot?.import || (snapshot?.job && ['running','cancelling'].includes(snapshot.job.state) ? snapshot.job : null);
  statusText.textContent = snapshot?.source_error ? 'Recording unavailable · import a replacement' : snapshot?.recording ? `Recording ready · ${snapshot.job?.state || 'idle'}` : 'No recording imported';
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
    if(identity(data)!==identity(snapshot)){rows=[];paint();}snapshot=data;
    if(previousImport && !data.import && previousGeneration===data.generation){
      try{const outcome=await request(`/recording/imports/${previousImport}`);if(current!==socket)return;importOutcome={...outcome,generation:data.generation};}catch{if(current===socket)progress.textContent='Import outcome unavailable · current source state refreshed';}
    }
    show();
    if(subscribedSocket!==current && current.readyState===WebSocket.OPEN) {subscribedSocket=current;current.send(JSON.stringify({v:1,type:`spectrum.${document.querySelector('#display-profile').value}`,id:nextId++}));}
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
  if(message.type==='error' && message.data.code==='unknown_command'){statusText.textContent='Recording display unavailable on this server';return;}
  if(message.type!=='spectrum.frame')return;
  const f=message.data;
  if(!snapshot || !['running','completed'].includes(snapshot.job?.state) || f.boot_id!==snapshot.boot_id || f.generation!==snapshot.generation || f.job_id!==snapshot.job?.id || f.source_id!==snapshot.job?.source_id)return;
  if(!Number.isSafeInteger(f.sequence)||f.sequence<0||f.sequence>=120||f.first_frame!==f.sequence*12000||f.end_frame!==Math.min(f.first_frame+12000,snapshot.recording?.frames))return;
  if(!Array.isArray(f.levels)||f.levels.length!==128||!f.levels.every(q=>Number.isInteger(q)&&q>=0&&q<=120))return;
  const previous=rows.at(-1)?.sequence??-1;if(f.sequence<=previous)return;
  for(let sequence=Math.max(previous+1,f.sequence-119);sequence<f.sequence;sequence++)rows.push({sequence,levels:null});
  rows.push(f);rows=rows.slice(-120);paint();
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
document.querySelector('#display-profile').addEventListener('change',event=>{if(socket?.readyState===WebSocket.OPEN)socket.send(JSON.stringify({v:1,type:`spectrum.${event.target.value}`,id:nextId++}));});
