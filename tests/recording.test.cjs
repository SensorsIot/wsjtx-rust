'use strict';
// Original FSD 4.4/6.4/12.6 oracles; cost 2 on Windows PC with actual server/Chromium, no hardware.
const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const net=require('node:net');
const {once}=require('node:events');
const crypto=require('node:crypto');
const {chromium}=require('playwright');
const selfsigned=require('selfsigned');
const WebSocket=require('ws');
const {receive}=require('./peer.cjs');
const {server,link}=require('./support.cjs');
let root,browser,tls;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
before(async()=>{
  root=await fs.mkdtemp(path.join(os.tmpdir(),'wstx-recording-browser-'));
  browser=await chromium.launch();
  const cert=await selfsigned.generate([{name:'commonName',value:'localhost'}],{days:1,keySize:2048,extensions:[{name:'subjectAltName',altNames:[{type:2,value:'localhost'},{type:7,ip:'127.0.0.1'}]}]});
  await fs.writeFile(path.join(root,'cert.pem'),cert.cert);await fs.writeFile(path.join(root,'key.pem'),cert.private);
  tls={WSTX_TLS_CERT:path.join(root,'cert.pem'),WSTX_TLS_KEY:path.join(root,'key.pem')};
});
after(async()=>{await browser?.close();if(root)await fs.rm(root,{recursive:true,force:true});});
async function port(){const s=net.createServer();s.listen(0,'127.0.0.1');await once(s,'listening');const p=s.address().port;await new Promise(r=>s.close(r));return p;}
async function fixture(t,{thin=false}={}){
  const dir=await fs.mkdtemp(path.join(root,'station-')),p=await port(),profile_id=crypto.randomUUID();
  const proxy=thin?await link({host:'127.0.0.2',port:1}):null;
  if(proxy)proxy.target.port=proxy.port;
  const origin=thin?`https://localhost:${proxy.port}`:`http://127.0.0.1:${p}`;
  const doc={schema_version:1,profile_id,revision:0,display_name:'Recording <station>',callsign:'TEST1',locator:'JN47AA',endpoint:{bind:thin?`127.0.0.2:${proxy.port}`:`127.0.0.1:${p}`,origin:thin?origin:null},connection_type:'standard',audio:{input_device:null,output_device:null},control:{mode:'disabled',endpoint:null,ptt:'disabled'}};
  await fs.writeFile(path.join(dir,'profile.json'),JSON.stringify(doc));
  const token=crypto.randomBytes(32).toString('hex'),env=thin?{...tls,WSTX_TOKEN:token}:{};
  let app=await server(env,['--profile',dir]);
  const context=await browser.newContext({ignoreHTTPSErrors:true});
  if(thin){const res=await context.request.post(origin+'/session',{headers:{Origin:origin},data:token});assert.equal(res.status(),204);}
  t.after(async()=>{await context.close();await app.close();await proxy?.close();});
  async function req(route,method='GET',body,headers={},direct=false){
    const target=direct&&thin?`https://127.0.0.2:${proxy.port}`:origin;
    const response=await context.request.fetch(target+route,{method,headers:{...(method==='GET'?{}:{Origin:origin}),...(direct&&thin?{Cookie:`wstx_session_${profile_id}=${profile_id}.${token}`}:{}) ,...(body&&!Buffer.isBuffer(body)?{'Content-Type':'application/json'}:{}),...headers},data:body});
    const text=await response.text();return {status:response.status(),value:text?JSON.parse(text):null,headers:response.headers()};
  }
  async function snapshot(){const r=await req('/recording');assert.equal(r.status,200);return r.value;}
  const body=s=>({v:1,profile_id:s.profile_id,boot_id:s.boot_id,generation:s.generation});
  async function reserve(){const s=await snapshot();const r=await req('/recording/imports','POST',body(s));assert.equal(r.status,201);return r.value;}
  async function upload(bytes,direct=false){const op=await reserve();for(let offset=0;offset<bytes.length;offset+=2048){const end=Math.min(offset+2048,bytes.length);const r=await req(`/recording/imports/${op.id}`,'PUT',bytes.subarray(offset,end),{'Content-Type':'audio/wav','Content-Range':`bytes ${offset}-${end-1}/${bytes.length}`},direct);assert.equal(r.status,end===bytes.length?201:202,JSON.stringify(r.value));}return snapshot();}
  async function replay(){const s=await snapshot(),r=await req('/recording/replay','POST',{...body(s),recording_id:s.recording.id});assert.equal(r.status,202,JSON.stringify(r.value));return r.value;}
  return {dir,origin,context,proxy,req,snapshot,reserve,upload,replay,body,async restart(){await app.close();app=await server(env,['--profile',dir]);}};
}
function wav(seconds=1,amplitude=.5,frequency=750){
  const count=Math.round(seconds*12000),b=Buffer.alloc(44+count*2);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(12000,24);b.writeUInt32LE(24000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(count*2,40);
  for(let n=0;n<count;n++)b.writeInt16LE(Math.max(-32768,Math.min(32767,Math.round(amplitude*32768*Math.sin(2*Math.PI*frequency*n/12000)))),44+n*2);return b;
}
async function page(f,viewport={width:1100,height:850}){const p=await f.context.newPage();await p.setViewportSize(viewport);await p.goto(f.origin,{timeout:120000});await p.locator('#connection[data-state=connected]').waitFor({timeout:30000});await p.locator('#signal-status').filter({hasText:/No recording|Recording ready|unavailable/}).waitFor({timeout:30000});return p;}
async function terminal(f){for(let n=0;n<30;n++){const s=await f.snapshot();if(['completed','cancelled','failed'].includes(s.job?.state))return s;await sleep(20);}assert.fail('worker did not release in 600 ms');}

// Proves: CL-006-01/02/04; TC-018-001/003, level 2 actual server/browser.
test('TC-018-001/003 import preserves source, jobs change, cancel releases and restart recovers',{timeout:30000},async t=>{
  const f=await fixture(t),bytes=wav(3);let s=await f.upload(bytes);const source=s.recording.id;
  assert.deepEqual(await fs.readFile(path.join(f.dir,'recordings',source+'.wav')),bytes);assert.equal(s.recording.utc_anchor,null);
  const first=await f.replay();assert.equal((await f.req('/recording/jobs/'+first.id,'DELETE')).status,200);s=await terminal(f);assert.equal(s.job.state,'cancelled');
  const second=await f.replay();assert.notEqual(second.id,first.id);assert.ok(second.generation>first.generation);assert.equal((await f.req('/recording/jobs/'+first.id,'DELETE')).status,404);
  const boot=s.boot_id;await f.restart();s=await f.snapshot();assert.equal(s.recording.id,source);assert.notEqual(s.boot_id,boot);assert.equal(s.generation,0);assert.equal(s.job,null);
  assert.equal((await f.req('/recording/jobs/'+second.id,'DELETE')).status,404);
  const p=await page(f);assert.equal(await p.locator('#profile-name').textContent(),'Recording <station>');assert.equal(await p.locator('#profile-name station').count(),0);
});
// Proves: CL-006-01/02/04; TC-018-002/003, level 2 actual boundary/priority vectors.
test('TC-018-002/003 HTTP admission, malformed chunks, busy and partial cancellation',{timeout:30000},async t=>{
  const f=await fixture(t),s=await f.snapshot(),body=f.body(s),unknown=crypto.randomUUID();
  assert.equal((await f.req('/recording/imports','POST',body,{Origin:'http://foreign.invalid'})).value.error.code,'forbidden_origin');
  for(const [edit,code,status] of [[{...body,x:1},'invalid_request',400],[{...body,v:2},'unsupported_version',400],[{...body,profile_id:unknown},'wrong_profile',403],[{...body,boot_id:unknown},'state_conflict',409],[{...body,generation:1},'state_conflict',409]]){const r=await f.req('/recording/imports','POST',edit);assert.equal(r.status,status);assert.equal(r.value.error.code,code);}
  const duplicate=JSON.stringify(body).replace('"v":1','"v":1,"v":1');assert.equal((await f.req('/recording/imports','POST',duplicate,{'Content-Type':'application/json'})).value.error.code,'invalid_request');
  const raced=await Promise.all([f.req('/recording/imports','POST',body),f.req('/recording/imports','POST',body)]);assert.deepEqual(raced.map(r=>r.status).sort(),[201,409]);await f.req('/recording/imports/'+raced.find(r=>r.status===201).value.id,'DELETE');
  const op=await f.reserve(),route='/recording/imports/'+op.id;
  assert.equal((await f.req('/recording/imports','POST',{...body,generation:op.generation})).value.error.code,'busy');
  for(const [range,code,status] of [['bad','invalid_request',400],['bytes 1-2/100','state_conflict',409],['bytes 0-1/3145729','request_too_large',413]]){const r=await f.req(route,'PUT',Buffer.from([1,2]),{'Content-Type':'audio/wav','Content-Range':range});assert.equal(r.status,status);assert.equal(r.value.error.code,code);}
  assert.equal((await f.req(route,'PUT',Buffer.alloc(2049),{'Content-Type':'audio/wav','Content-Range':'bytes 0-2048/3000'})).status,413);
  assert.equal((await f.req(route,'PUT',Buffer.from([1,2]),{'Content-Type':'audio/wav','Content-Range':'bytes 0-1/100'})).status,202);
  const began=performance.now();assert.equal((await f.req(route,'DELETE')).status,200);assert.ok(performance.now()-began<250);
  for(let n=0;n<30;n++){const r=await f.req(route);if(r.value.state==='cancelled')break;await sleep(20);}assert.equal((await f.req(route)).value.state,'cancelled');
  assert.equal((await f.req(route,'PUT',Buffer.from([1,2]),{'Content-Type':'audio/wav','Content-Range':'bytes 2-3/100'})).value.error.code,'cancelled');
  const valid=await f.upload(wav(.1));assert.ok(valid.recording);const malformed=wav(.1);malformed.writeUInt32LE(1,4);const replacement=await f.reserve();const error=await f.req('/recording/imports/'+replacement.id,'PUT',malformed.subarray(0,2048),{'Content-Type':'audio/wav','Content-Range':`bytes 0-2047/${malformed.length}`});assert.equal(error.status,202);
  const end=await f.req('/recording/imports/'+replacement.id,'PUT',malformed.subarray(2048),{'Content-Type':'audio/wav','Content-Range':`bytes 2048-${malformed.length-1}/${malformed.length}`});assert.equal(end.status,422);assert.equal(end.value.error.code,'invalid_recording');assert.equal((await f.snapshot()).recording.id,valid.recording.id);
});

// Proves: CL-006-02/04; TC-018-002, observed transport loss invalidates a partial HTTP body.
test('TC-018-002 aborted partial upload cancels its reservation without publishing source',{timeout:10000},async t=>{
  const f=await fixture(t),op=await f.reserve(),u=new URL(f.origin),socket=net.connect({host:u.hostname,port:Number(u.port)});await once(socket,'connect');
  socket.on('error',()=>{});socket.write(`PUT /recording/imports/${op.id} HTTP/1.1\r\nHost: ${u.host}\r\nOrigin: ${f.origin}\r\nContent-Type: audio/wav\r\nContent-Range: bytes 0-999/2000\r\nContent-Length: 1000\r\n\r\nRIFF`);await sleep(50);socket.destroy();
  for(let n=0;n<50;n++){const r=await f.req('/recording/imports/'+op.id);if(r.value.state==='cancelled')break;await sleep(20);}
  assert.equal((await f.req('/recording/imports/'+op.id)).value.state,'cancelled');assert.equal((await f.snapshot()).recording,null);
});
// Proves: CL-006-01/02; TC-018-003, fresh-browser replacement after each committed-source fault.
test('TC-018-003 missing original, corrupt metadata and manifest remain recoverable',{timeout:30000},async t=>{
  for(const target of ['original','metadata','manifest']){
    const f=await fixture(t);const s=await f.upload(wav(.1));
    const file=path.join(f.dir,'recordings',target==='manifest'?'current.json':s.recording.id+(target==='original'?'.wav':'.json'));
    if(target==='original')await fs.unlink(file);else await fs.writeFile(file,'{}');await f.restart();
    if(target!=='original') {
      assert.deepEqual(await fs.readFile(path.join(f.dir,'recordings',s.recording.id+'.wav')),wav(.1),'source fault must not delete the committed original before replacement');
      const invalid=await f.reserve();const rejected=await f.req('/recording/imports/'+invalid.id,'PUT',Buffer.from('RIFF'),{'Content-Type':'audio/wav','Content-Range':'bytes 0-3/4'});assert.equal(rejected.status,422);
      assert.deepEqual(await fs.readFile(path.join(f.dir,'recordings',s.recording.id+'.wav')),wav(.1),'failed replacement must retain the last committed original');
    }
    const fault=await f.snapshot();assert.equal(fault.source_error,'recording_unavailable');assert.equal(fault.recording,null);
    const r=await f.req('/recording/replay','POST',{...f.body(fault),recording_id:s.recording.id});assert.equal(r.value.error.code,'recording_unavailable');
    const p=await page(f);await p.locator('#signal-status').filter({hasText:/Recording unavailable/}).waitFor();assert.equal(await p.locator('#recording-import').isEnabled(),true);
    const replaced=await f.upload(wav(.1));assert.equal(replaced.source_error,null);const job=await f.replay();await sleep(200);assert.equal((await terminal(f)).job.state,'completed');assert.ok(job.id);
  }
});

// Proves: CL-006-02/04; TC-018-003 review regression, cancellation while reservation response is delayed.
test('TC-018-003 cancel pending reservation response deletes returned reservation without PUT',{timeout:12000},async t=>{
  const f=await fixture(t),p=await page(f),errors=[];p.on('pageerror',e=>errors.push(String(e)));
  let release,observed,puts=0,resource;
  const held=new Promise(r=>release=r),accepted=new Promise(r=>observed=r);t.after(()=>release());
  p.on('request',r=>{if(r.method()==='PUT'&&r.url().includes('/recording/imports/'))puts++;});
  await p.route('**/recording/imports',async route=>{const response=await route.fetch();resource=await response.json();observed();await held;await route.fulfill({response});});
  await p.setInputFiles('#recording-file',{name:'pending.wav',mimeType:'audio/wav',buffer:wav(.1)});await p.locator('#recording-import').click();await accepted;
  assert.equal(await p.evaluate(()=>snapshot.import===null&&snapshot.job===null&&uploading&&!uploadId),true);
  await p.locator('#recording-cancel').click();await p.locator('#recording-progress').filter({hasText:/Cancellation requested/}).waitFor();release();
  await p.locator('#recording-import:enabled').waitFor();assert.equal(puts,0);assert.deepEqual(errors,[]);assert.equal((await f.snapshot()).import,null);assert.equal((await f.req('/recording/imports/'+resource.id)).value.state,'cancelled');
});

// Proves: CL-006-03/04; TC-010-002, actual subscribed stalled peer plus healthy mandatory control path.
test('TC-010-002 stalled thin subscriber is bounded and cannot block healthy status',{timeout:35000},async t=>{
  const f=await fixture(t);await f.upload(wav(30));
  const slow=new WebSocket(f.origin.replace('http','ws')+'/ws','wstx.v1',{origin:f.origin,autoPong:false});await once(slow,'open');
  const healthy=new WebSocket(f.origin.replace('http','ws')+'/ws','wstx.v1',{origin:f.origin});await once(healthy,'open');t.after(()=>{slow.terminate();healthy.terminate();});
  const subscribed=receive(slow);slow.send(JSON.stringify({v:1,type:'spectrum.thin',id:1}));assert.equal((await subscribed).type,'spectrum.subscription');slow._socket.pause();
  const job=await f.replay();
  for(let n=0;n<4;n++){await sleep(1000);const pending=receive(healthy),start=performance.now();healthy.send(JSON.stringify({v:1,type:'station.get',id:n+2}));assert.equal((await pending).type,'station.status');assert.ok(performance.now()-start<2000);}
  await sleep(18000);const closed=once(slow,'close');slow._socket.resume();await Promise.race([closed,sleep(5000).then(()=>{throw Error('stalled thin peer retained past liveness deadline');})]);
  const pending=receive(healthy);healthy.send(JSON.stringify({v:1,type:'station.get',id:99}));assert.equal((await pending).type,'station.status');await f.req('/recording/jobs/'+job.id,'DELETE');await terminal(f);
});

// Proves: CL-006-02; TC-018-003 review regression, JSON media grammar remains the profile grammar.
test('TC-018-003 recording JSON media whitespace parity and malformed parameters',{timeout:10000},async t=>{
  const f=await fixture(t);
  for(const type of ['application/json','application/json ;charset=utf-8','application/json;\tcharset=utf-8',' Application/JSON ; CHARSET=UTF-8 ']){
    const s=await f.snapshot();const r=await f.req('/recording/imports','POST',f.body(s),{'Content-Type':type});assert.equal(r.status,201,type);await f.req('/recording/imports/'+r.value.id,'DELETE');
  }
  for(const type of ['application/json;','application/json; charset=ascii','application/json; charset=utf-8; x=1','text/json','application/json; charset="utf-8"']){
    const s=await f.snapshot();const r=await f.req('/recording/imports','POST',f.body(s),{'Content-Type':type});assert.equal(r.status,415,type);
  }
});
// Proves: CL-006-03; TC-010-001/003, real browser canvas data and desktop/narrow accessible layout.
test('TC-010-001/003 calibrated real spectrum, source rows and accessible splitter',{timeout:30000},async t=>{
  const f=await fixture(t);await f.upload(wav(2));const p=await page(f);const frames=[];
  p.on('websocket',ws=>ws.on('framereceived',e=>{try{const m=JSON.parse(e.payload);if(m.type==='spectrum.frame')frames.push(m);}catch{}}));
  // Inspect through independent peer as well as the actual browser paint.
  const ws=new WebSocket(f.origin.replace('http','ws')+'/ws','wstx.v1',{origin:f.origin});await once(ws,'open');t.after(()=>ws.close());const subscribed=receive(ws);ws.send(JSON.stringify({v:1,type:'spectrum.thin',id:1}));await subscribed;
  const pendingFrame=receive(ws,5000);await p.locator('#recording-replay').click();const frame=await pendingFrame;assert.equal(frame.type,'spectrum.frame');
  assert.equal(frame.data.levels.length,128);assert.equal(frame.data.levels[32],114);assert.equal(frame.data.first_frame,frame.data.sequence*12000);assert.ok(frame.data.end_frame<=24000);assert.ok(Buffer.byteLength(JSON.stringify(frame))<=1024);
  await p.waitForFunction(()=>Number(document.querySelector('#waterfall').dataset.rows)>0,{timeout:8000});
  assert.ok(await p.locator('#signal').innerText().then(s=>s.includes('Hz')&&s.includes('dBFS')));
  const separator=p.getByRole('separator',{name:'Resize spectrum and controls'});await separator.focus();await p.keyboard.press('Home');assert.equal(Number(await separator.getAttribute('aria-valuenow')),160);await p.keyboard.press('ArrowDown');assert.equal(Number(await separator.getAttribute('aria-valuenow')),176);await p.keyboard.press('End');assert.equal(Number(await separator.getAttribute('aria-valuenow')),638);
  const box=await separator.boundingBox();await p.mouse.move(box.x+10,box.y+6);await p.mouse.down();await p.mouse.move(box.x+10,0);await p.mouse.up();assert.equal(Number(await separator.getAttribute('aria-valuenow')),160);
  await fs.mkdir('test-results',{recursive:true});await p.screenshot({path:'test-results/recording-desktop.png',fullPage:true});
  await p.setViewportSize({width:360,height:640});assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);assert.ok((await p.locator('#signal').boundingBox()).height>=160);assert.ok((await p.locator('#controls').boundingBox()).height>=200);assert.equal((await separator.boundingBox()).height,12);
  await p.screenshot({path:'test-results/recording-mobile.png',fullPage:true});
  const touch=await f.context.newCDPSession(p),handle=await separator.boundingBox();
  await touch.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:180,y:handle.y+6}]});
  await touch.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:180,y:300}]});
  await touch.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});assert.ok(Number(await separator.getAttribute('aria-valuenow'))>=280);
  await p.evaluate(()=>document.documentElement.style.zoom='2');assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
});

// Proves: CL-006-01/03; TC-018-001, all pinned real recordings; level 2 read-only acquired inputs.
test('TC-018-001 all 22 FT8 and 3 FT4 originals match provenance and import unchanged',{timeout:90000},async t=>{
  const {execFileSync}=require('node:child_process');
  const common=path.resolve(execFileSync('git',['rev-parse','--git-common-dir'],{encoding:'utf8',windowsHide:true}).trim());
  const samples=process.env.WSTX_SAMPLE_DIR || path.join(common,'harness-parallel','resources','issue-7','downloads');
  const ft8=JSON.parse(await fs.readFile('fixtures/decoder/manifest.json','utf8'));
  const ft4=JSON.parse(await fs.readFile('fixtures/decoder/ft4-manifest.json','utf8'));
  const inputs=[...ft8.files.filter(f=>f.path.endsWith('.wav')).map(f=>({...f,file:path.join(samples,path.basename(f.path))})),...ft4.files.map(f=>({...f,file:path.join(samples,'ft4',f.relative_download_path)}))];
  assert.equal(inputs.length,25);const f=await fixture(t);
  for(const input of inputs){const bytes=await fs.readFile(input.file).catch(error=>{if(error.code==='ENOENT')throw Error('Missing recording fixtures. Run node tools/recording-fixtures.cjs --directory <absolute-cache-directory> and set WSTX_SAMPLE_DIR to that directory.');throw error;});assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),input.sha256);const s=await f.upload(bytes);assert.equal(s.recording.rate_hz,12000);assert.equal(s.recording.file_bytes,bytes.length);assert.deepEqual(await fs.readFile(path.join(f.dir,'recordings',s.recording.id+'.wav')),bytes);}
  const p=await page(f);await p.locator('#recording-replay').click();await p.waitForFunction(()=>Number(document.querySelector('#waterfall').dataset.rows)>0,{timeout:8000});
  await f.req('/recording/jobs/'+(await f.snapshot()).job.id,'DELETE');await terminal(f);
});

// Proves: CL-006-02/04; TC-018-003, four Windows processes with actual maximum-source work.
test('TC-018-003 four stations retain isolated identities and release cancellation within 250 ms',{timeout:30000},async t=>{
  const stations=await Promise.all(Array.from({length:4},()=>fixture(t)));
  await Promise.all(stations.map(f=>f.upload(wav(120))));const jobs=await Promise.all(stations.map(f=>f.replay()));
  for(let n=0;n<4;n++){const f=stations[n],foreign=jobs[(n+1)%4];assert.equal((await f.req('/recording/jobs/'+foreign.id,'DELETE')).status,404);}
  const times=await Promise.all(stations.map(async(f,n)=>{const start=performance.now();await f.req('/recording/jobs/'+jobs[n].id,'DELETE');const s=await terminal(f);assert.equal(s.job.state,'cancelled');assert.ok(s.job.processed_frames<=1440000);return performance.now()-start;}));
  times.forEach(ms=>assert.ok(ms<=250,`cancel + release ${ms} ms`));
});

// Proves: CL-006-03/04; TC-010-002, actual encrypted streams + independent shared 32 kbit/s link.
test('TC-010-002 two thin browsers, full 60 second traffic and simultaneous status latency',{timeout:230000},async t=>{
  const f=await fixture(t,{thin:true});await f.upload(wav(64),true);
  const second=await browser.newContext({ignoreHTTPSErrors:true,storageState:await f.context.storageState()});t.after(()=>second.close());
  const began=performance.now(),coldBefore={...f.proxy.counters};
  const pages=await Promise.all([page(f),page({...f,context:second})]);
  const cold={ms:performance.now()-began,up:f.proxy.counters.up-coldBefore.up,down:f.proxy.counters.down-coldBefore.down};
  const events=[[],[]];for(let n=0;n<2;n++)pages[n].on('websocket',ws=>ws.on('framereceived',e=>{const m=JSON.parse(e.payload);if(m.type==='spectrum.frame')events[n].push({at:performance.now(),message:m});}));
  // Install observers on the existing sockets without relying on transport creation timing.
  for(const p of pages)await p.evaluate(()=>{window.__displayEvents=[];addEventListener('station-message',e=>{if(e.detail.message.type==='spectrum.frame')window.__displayEvents.push({at:performance.now(),message:e.detail.message});});});
  await f.replay();await sleep(2000);const baseline={...f.proxy.counters},start=performance.now(),latencies=[];
  for(let n=0;n<10;n++){
    const due=start+(n+1)*5500;await sleep(Math.max(0,due-performance.now()));
    await Promise.all(pages.map(async p=>{const old=await p.locator('#updated').textContent(),time=performance.now();await p.locator('#refresh').click();await p.waitForFunction(value=>document.querySelector('#updated').textContent!==value,old,{timeout:2000});const ms=performance.now()-time;assert.ok(ms<2000,`status ${ms} ms`);latencies.push(ms);}));
  }
  await sleep(Math.max(0,start+60000-performance.now()));const seconds=(performance.now()-start)/1000;
  const traffic={up:(f.proxy.counters.up-baseline.up)/seconds,down:(f.proxy.counters.down-baseline.down)/seconds};
  // Bounding the positive sum of both clients by the per-client budget proves each client also stays within it.
  assert.ok(traffic.up<=3000);assert.ok(traffic.down<=3000);
  const captured=await Promise.all(pages.map(p=>p.evaluate(()=>window.__displayEvents)));
  for(const frames of captured){assert.ok(frames.length>=45);assert.ok(frames.length<=65);for(let n=0;n<frames.length;n++){assert.ok(Buffer.byteLength(JSON.stringify(frames[n].message))<=1024);if(n)assert.ok(frames[n].message.data.sequence>frames[n-1].message.data.sequence);}}
  for(const p of pages)await p.selectOption('#display-profile','off');
  const offBefore={...f.proxy.counters},offStart=performance.now();await sleep(60000);const offSeconds=(performance.now()-offStart)/1000;
  const off={up:(f.proxy.counters.up-offBefore.up)/offSeconds,down:(f.proxy.counters.down-offBefore.down)/offSeconds};assert.ok(off.up<=1000);assert.ok(off.down<=1000);
  const uploadBefore={...f.proxy.counters},uploadStart=performance.now(),uploadStatus=[];
  await pages[0].setInputFiles('#recording-file',{name:'paced.wav',mimeType:'audio/wav',buffer:wav(.5)});await pages[0].locator('#recording-import').click();
  for(let n=0;n<6;n++){await sleep(700);await Promise.all(pages.map(async p=>{const old=await p.locator('#updated').textContent(),time=performance.now();await p.locator('#refresh').click();await p.waitForFunction(value=>document.querySelector('#updated').textContent!==value,old,{timeout:2000});const ms=performance.now()-time;assert.ok(ms<2000);uploadStatus.push(ms);}));}
  await pages[0].locator('#recording-replay:enabled').waitFor({timeout:30000});
  const upload={ms:performance.now()-uploadStart,up:f.proxy.counters.up-uploadBefore.up,down:f.proxy.counters.down-uploadBefore.down,statusMs:uploadStatus};
  await fs.mkdir('test-results',{recursive:true});await fs.writeFile('test-results/recording-link.json',JSON.stringify({model:'actual TLS streams plus support.cjs fixed TCP/IPv6/ACK overhead; shared 4000 bytes/s each direction, 150 ms one-way',cold,upload,steadySeconds:seconds,sharedBytesPerSecond:traffic,sharedOffBytesPerSecond:off,statusMs:latencies,frames:captured.map(f=>f.length)},null,2));
});

// Proves: CL-006-02/04; TC-018-003, endpoint-wide TLS authentication/Origin priority and WS opt-in.
test('TC-018-003 every recording endpoint retains TLS cookie and exact Origin boundaries',{timeout:45000},async t=>{
  const f=await fixture(t,{thin:true}),s=await f.snapshot(),id=crypto.randomUUID();
  const absent=await browser.newContext({ignoreHTTPSErrors:true});t.after(()=>absent.close());
  for(const [route,method] of [['/recording','GET'],['/recording/imports','POST'],['/recording/imports/'+id,'GET'],['/recording/imports/'+id,'PUT'],['/recording/imports/'+id,'DELETE'],['/recording/replay','POST'],['/recording/jobs/'+id,'DELETE']]){
    const response=await absent.request.fetch(f.origin+route,{method,headers:{Origin:f.origin}});assert.equal(response.status(),401);assert.equal((await response.json()).error.code,'unauthorized');
    const bad=await f.context.request.fetch(f.origin+route,{method,headers:{Origin:'https://foreign.invalid'}});assert.equal(bad.status(),403);assert.equal((await bad.json()).error.code,'forbidden_origin');
    if(method!=='GET'){const missing=await f.context.request.fetch(f.origin+route,{method});assert.equal(missing.status(),403);}
  }
  assert.equal((await f.req('/recording/imports','POST',f.body(s),{'Content-Type':'audio/wav'},true)).status,415);
  assert.equal((await f.req('/recording/imports','POST',Buffer.alloc(1025),{'Content-Type':'application/json'},true)).status,413);
  const plain=await server();t.after(()=>plain.close());
  for(const command of ['recording.get','spectrum.thin','spectrum.off']){
    const ws=new WebSocket(plain.origin.replace('http','ws')+'/ws','wstx.v1',{origin:plain.origin});await once(ws,'open');const pending=receive(ws);ws.send(JSON.stringify({v:1,type:command,id:5}));const result=await pending;assert.equal(result.data.code,'unavailable');ws.close();
  }
});

// Proves: CL-006-03/04; TC-010-002, direct peer measures server cadence independently of link delivery jitter.
test('TC-010-002 optional output is opt-in, bounded, paced and invalidated by cancel',{timeout:15000},async t=>{
  const f=await fixture(t);await f.upload(wav(5));
  const ws=new WebSocket(f.origin.replace('http','ws')+'/ws','wstx.v1',{origin:f.origin});await once(ws,'open');t.after(()=>ws.close());
  const messages=[];ws.on('message',data=>messages.push({at:performance.now(),value:JSON.parse(String(data))}));
  let pending=receive(ws);ws.send(JSON.stringify({v:1,type:'spectrum.thin',id:1}));assert.equal((await pending).type,'spectrum.subscription');
  const job=await f.replay();await sleep(3300);
  const frames=messages.filter(m=>m.value.type==='spectrum.frame');assert.ok(frames.length>=2);for(let n=1;n<frames.length;n++)assert.ok(frames[n].at-frames[n-1].at>=995);
  pending=receive(ws);ws.send(JSON.stringify({v:1,type:'spectrum.off',id:2}));assert.equal((await pending).type,'spectrum.subscription');const off=messages.filter(m=>m.value.type==='spectrum.frame').length;await sleep(1100);assert.equal(messages.filter(m=>m.value.type==='spectrum.frame').length,off);
  await f.req('/recording/jobs/'+job.id,'DELETE');await terminal(f);const snapshot=await f.snapshot();assert.equal(snapshot.job.state,'cancelled');
});

// Proves: CL-006-03/04; TC-010-002/003, browser event boundary under loss/late delivery.
test('TC-010-002 browser caps 120 rows, preserves explicit gaps and rejects obsolete identities',{timeout:15000},async t=>{
  const f=await fixture(t);await f.upload(wav(120));const p=await page(f);await p.selectOption('#display-profile','off');await p.locator('#recording-replay').click();
  await p.locator('#signal-status').filter({hasText:/running/}).waitFor();const s=await f.snapshot();
  const observation=await p.evaluate(async s=>{
    const make=sequence=>({v:1,type:'spectrum.frame',data:{boot_id:s.boot_id,source_id:s.job.source_id,job_id:s.job.id,generation:s.generation,sequence,first_frame:sequence*12000,end_frame:Math.min((sequence+1)*12000,s.recording.frames),levels:Array(128).fill(20)}});
    const deliver=message=>dispatchEvent(new CustomEvent('station-message',{detail:{message,current:socket}}));
    for(const field of ['boot_id','source_id','job_id','generation']){const m=make(0);m.data[field]=field==='generation'?s.generation-1:'00000000-0000-4000-8000-000000000000';deliver(m);}
    await new Promise(requestAnimationFrame);const ignored=Number(document.querySelector('#waterfall').dataset.rows);
    for(let n=0;n<120;n++)if(n!==1)deliver(make(n));
    deliver(make(120));deliver(make(119));
    await new Promise(requestAnimationFrame);
    const c=document.querySelector('#waterfall'),pixel=[...c.getContext('2d').getImageData(0,Math.floor(c.height/120),1,1).data];
    return {ignored,count:Number(c.dataset.rows),sequences:c.dataset.sequences,pixel,label:c.getAttribute('aria-label')};
  },s);
  assert.equal(observation.ignored,0);assert.equal(observation.count,120);assert.equal(observation.sequences,Array.from({length:120},(_,n)=>n).join(','));assert.deepEqual(observation.pixel,[104,104,104,255]);assert.match(observation.label,/0 to 120 seconds/);
  await f.req('/recording/jobs/'+s.job.id,'DELETE');await terminal(f);
});
