'use strict';
// Original FSD 4.4/6.4/12.6 oracles; cost 2 on Windows PC with actual server/Chromium, no hardware.
const {test,describe,before,after}=require('node:test');
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
async function closeAll(closers){
  const results=await Promise.allSettled(closers.map(close=>Promise.resolve().then(close)));
  const errors=results.filter(result=>result.status==='rejected').map(result=>result.reason);
  if(errors.length)throw new AggregateError(errors,'Disposable fixture cleanup failed');
}
async function fixture(t,{thin=false,secure=false}={}){
  let proxy,app,context,released=false;
  t.after(async()=>{released=true;await closeAll([()=>context?.close(),()=>app?.close(),()=>proxy?.close()]);});
  async function retained(resource){if(released){await resource?.close();throw Error('Disposable fixture was released during setup');}}
  const dir=await fs.mkdtemp(path.join(root,'station-')),p=await port(),profile_id=crypto.randomUUID();
  proxy=thin?await link({host:'127.0.0.2',port:1}):null;
  await retained(proxy);
  if(proxy)proxy.target.port=proxy.port;
  const origin=thin?`https://localhost:${proxy.port}`:secure?`https://localhost:${p}`:`http://127.0.0.1:${p}`;
  const doc={schema_version:1,profile_id,revision:0,display_name:'Recording <station>',callsign:'TEST1',locator:'JN47AA',endpoint:{bind:thin?`127.0.0.2:${proxy.port}`:`127.0.0.1:${p}`,origin:thin||secure?origin:null},connection_type:'standard',audio:{input_device:null,output_device:null},control:{mode:'disabled',endpoint:null,ptt:'disabled'}};
  await fs.writeFile(path.join(dir,'profile.json'),JSON.stringify(doc));
  await retained();
  const token=crypto.randomBytes(32).toString('hex'),env=thin||secure?{...tls,WSTX_TOKEN:token}:{};
  app=await server(env,['--profile',dir]);
  await retained(app);
  context=await browser.newContext({ignoreHTTPSErrors:true});
  await retained(context);
  if(thin||secure){const res=await context.request.post(origin+'/session',{headers:{Origin:origin},data:token});assert.equal(res.status(),204);}
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
async function page(f,viewport={width:1100,height:850}){const p=await f.context.newPage();await p.setViewportSize(viewport);await p.goto(f.origin,{timeout:120000});await p.locator('#connection[data-state=connected]').waitFor({timeout:30000});await p.locator('#signal-status').filter({hasText:/No recording|Recording ready|unavailable/}).waitFor({timeout:30000});if(await p.locator('#open-recordings').count())await p.locator('#open-recordings').click();const recording=p.locator('#recorded-input');if(await recording.count()&&!await recording.evaluate(el=>el.open))await recording.locator('summary').click();return p;}
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
test('TC-018-003 review: missing original, corrupt metadata and manifest remain recoverable',{timeout:30000},async t=>{
  for(const target of ['original','metadata','manifest','missing_manifest']){
    const f=await fixture(t);const s=await f.upload(wav(.1));
    const file=path.join(f.dir,'recordings',['manifest','missing_manifest'].includes(target)?'current.json':s.recording.id+(target==='original'?'.wav':'.json'));
    if(target==='original'||target==='missing_manifest')await fs.unlink(file);else await fs.writeFile(file,'{}');await f.restart();
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
test('TC-018-003 review: cancel pending reservation response deletes returned reservation without PUT',{timeout:12000},async t=>{
  const f=await fixture(t),p=await page(f),errors=[];p.on('pageerror',e=>errors.push(String(e)));
  let release,observed,puts=0,resource;
  const held=new Promise(r=>release=r),accepted=new Promise(r=>observed=r);t.after(()=>release());
  p.on('request',r=>{if(r.method()==='PUT'&&r.url().includes('/recording/imports/'))puts++;});
  await p.route('**/recording/imports',async route=>{const response=await route.fetch();resource=await response.json();observed();await held;await route.fulfill({response});});
  await p.setInputFiles('#recording-file',{name:'pending.wav',mimeType:'audio/wav',buffer:wav(.1)});await p.locator('#recording-import').click();await accepted;
  assert.equal(await p.evaluate(()=>snapshot.import===null&&snapshot.job===null&&uploading&&!uploadId),true);
  await p.locator('#open-client-preferences').click();
  await p.keyboard.press('Escape');await p.locator('#open-recordings').click();
  assert.equal(await p.locator('#recording-file').evaluate(el=>el.files[0].name),'pending.wav');
  assert.equal(await p.evaluate(()=>uploading&&!uploadId),true,'navigation preserves pending reservation state');
  await p.locator('#recording-cancel').click();release();
  await p.waitForFunction(()=>!uploading,null,{timeout:3000});assert.equal(puts,0);assert.deepEqual(errors,[]);assert.equal((await f.snapshot()).import,null);assert.equal((await f.req('/recording/imports/'+resource.id)).value.state,'cancelled');
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
test('TC-018-003 review: recording JSON media whitespace parity and malformed parameters',{timeout:10000},async t=>{
  const f=await fixture(t);
  for(const type of ['application/json','application/json ;charset=utf-8','application/json;\tcharset=utf-8',' Application/JSON ; CHARSET=UTF-8 ']){
    const s=await f.snapshot();const r=await f.req('/recording/imports','POST',f.body(s),{'Content-Type':type});assert.equal(r.status,201,type);await f.req('/recording/imports/'+r.value.id,'DELETE');
  }
  for(const type of ['application/json;','application/json; charset=ascii','application/json; charset=utf-8; x=1','text/json','application/json; charset="utf-8"']){
    const s=await f.snapshot();const r=await f.req('/recording/imports','POST',f.body(s),{'Content-Type':type});assert.equal(r.status,415,type);
  }
});

// Proves: CL-006-03/04; TC-010-002/003, bootstrap after station-ready preceded the deferred recording asset.
test('TC-010-003 late recording asset bootstraps an already connected station once',{timeout:12000},async t=>{
  const f=await fixture(t),p=await f.context.newPage();let release,snapshots=0,subscriptions=0;
  const held=new Promise(r=>release=r);t.after(()=>release());
  p.on('request',r=>{if(new URL(r.url()).pathname==='/recording')snapshots++;});
  p.on('websocket',ws=>ws.on('framesent',event=>{try{if(JSON.parse(event.payload).type==='spectrum.detail')subscriptions++;}catch{}}));
  await p.route('**/recording.js',async route=>{await held;await route.continue();});
  const navigation=p.goto(f.origin);await p.locator('#connection[data-state=connected]').waitFor({timeout:5000});
  assert.equal(snapshots,0,'status/profile is ready while the recording module is still unavailable');release();await navigation;
  await p.locator('#signal-status').filter({hasText:'No recording imported'}).waitFor({timeout:2000});assert.equal(await p.locator('#recording-import').isEnabled(),true);
  await p.evaluate(()=>{dispatchEvent(new CustomEvent('station-ready',{detail:socket}));dispatchEvent(new CustomEvent('station-ready',{detail:socket}));});
  await p.waitForTimeout(100);assert.equal(snapshots,1);assert.equal(subscriptions,1);
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
  assert.match(await p.locator('#signal-status').innerText(),/Recording ready \u00b7 (running|completed)/,'receive status preserves its actual Unicode separator');
  const separator=p.getByRole('separator',{name:'Resize spectrum and controls'});await separator.focus();await p.keyboard.press('Home');assert.equal(Number(await separator.getAttribute('aria-valuenow')),160);await p.keyboard.press('ArrowDown');assert.equal(Number(await separator.getAttribute('aria-valuenow')),176);await p.keyboard.press('End');const expectedMaximum=await p.evaluate(()=>document.querySelector('main').clientHeight-['#station-bar','#radio-toolbar','#band-strip','#workspace-statusbar','#splitter'].reduce((height,id)=>height+document.querySelector(id).offsetHeight,0)-200);assert.equal(Number(await separator.getAttribute('aria-valuenow')),expectedMaximum);
  const box=await separator.boundingBox();await p.mouse.move(box.x+10,box.y+6);await p.mouse.down();await p.mouse.move(box.x+10,0);await p.mouse.up();assert.equal(Number(await separator.getAttribute('aria-valuenow')),160);
  await fs.mkdir('test-results',{recursive:true});await p.screenshot({path:'test-results/recording-desktop.png',fullPage:true});
  await p.setViewportSize({width:360,height:640});assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);assert.ok((await p.locator('#signal').boundingBox()).height>=160);assert.ok((await p.locator('#controls').boundingBox()).height>=200);assert.equal((await separator.boundingBox()).height,7);
  await p.screenshot({path:'test-results/recording-mobile.png',fullPage:true});
  await separator.scrollIntoViewIfNeeded();const touch=await f.context.newCDPSession(p),handle=await separator.boundingBox(),targetY=await p.evaluate(()=>document.querySelector('#signal').getBoundingClientRect().top+Math.min(Number(document.querySelector("#splitter").getAttribute("aria-valuemin"))+16,Number(document.querySelector('#splitter').getAttribute('aria-valuemax'))));
  await touch.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:180,y:handle.y+3}]});
  await touch.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:180,y:targetY}]});
  await touch.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});const resizedSignal=await p.locator('#signal').boundingBox();assert.ok(Math.abs(resizedSignal.y+resizedSignal.height-targetY)<=10,'touch drag follows its viewport coordinate below the station bar');
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
describe('TC-010-002 two thin browsers',{concurrency:false},()=>{
  let f,pages,prepared=false,closing,writing=Promise.resolve();
  const cleanups=[],dispose=()=>closing??=closeAll(cleanups);
  after(dispose);
  const report={runId:crypto.randomUUID(),startedUtc:new Date().toISOString(),model:'actual TLS streams plus support.cjs fixed TCP/IPv6/ACK overhead; shared 4000 bytes/s each direction, 150 ms one-way',phases:{}};
  function progress(phase,details,metrics={}){
    writing=writing.then(async()=>{
      if(report.phases[phase]?.state==='cancelled'&&details.state!=='cancelled')return;
      Object.assign(report,metrics);report.phases[phase]={...report.phases[phase],...details};
      await fs.mkdir('test-results',{recursive:true});await fs.writeFile('test-results/recording-link.json',JSON.stringify(report,null,2));
    });
    return writing;
  }
  async function runPhase(t,name,work){
    let passed=false,failure;const began=performance.now();
    t.after(async()=>{if(!passed){try{await progress(name,{state:t.signal.aborted?'cancelled':'failed',elapsedMs:performance.now()-began,error:failure||t.signal.reason?.message});}finally{await dispose();}}});
    try{await progress(name,{state:'running',startedUtc:new Date().toISOString()});t.signal.throwIfAborted();await work();t.signal.throwIfAborted();await progress(name,{state:'passed',elapsedMs:performance.now()-began});t.signal.throwIfAborted();passed=true;}
    catch(error){failure=error.message;throw error;}
  }
  test('TC-010-002 cold load in two independent uncached browsers',{timeout:230000},async t=>{
    await runPhase(t,'cold',async()=>{
      f=await fixture({after:cleanup=>cleanups.push(cleanup)},{thin:true});await f.upload(wav(64),true);
      const second=await browser.newContext({ignoreHTTPSErrors:true,storageState:await f.context.storageState()});cleanups.push(()=>second.close());
      if(closing){await second.close();throw Error('Cold-load fixture was released during setup');}
      const began=performance.now(),coldBefore={...f.proxy.counters};
      pages=await Promise.all([page(f),page({...f,context:second})]);
      for(const p of pages)await p.selectOption('#display-profile','thin'); // Explicit32kbit/s mode; default Detailed has no such promise.
      const cold={ms:performance.now()-began,up:f.proxy.counters.up-coldBefore.up,down:f.proxy.counters.down-coldBefore.down};
      await progress('cold',{step:'pages connected'}, {cold});
    });
    prepared=true;
  });
  test('TC-010-002 full 60 second connected traffic and simultaneous status latency',{timeout:230000},async t=>{
    const delay=require('node:timers/promises').setTimeout,sleep=ms=>delay(ms,undefined,{signal:t.signal});
    const waitUntil=async deadline=>{while(performance.now()<deadline)await sleep(Math.max(1,Math.ceil(deadline-performance.now())));};
    await runPhase(t,'connected',async()=>{
      assert.ok(prepared,'Cold-load phase must complete successfully before connected measurements');
      const events=[[],[]];for(let n=0;n<2;n++)pages[n].on('websocket',ws=>ws.on('framereceived',e=>{const m=JSON.parse(e.payload);if(m.type==='spectrum.frame')events[n].push({at:performance.now(),message:m});}));
      // Install observers on the existing sockets without relying on transport creation timing.
      for(const p of pages)await p.evaluate(()=>{window.__displayEvents=[];addEventListener('station-message',e=>{if(e.detail.message.type==='spectrum.frame')window.__displayEvents.push({at:performance.now(),message:e.detail.message});});});
      const playback=await f.replay();await sleep(2000);const baseline={...f.proxy.counters},start=performance.now(),latencies=[];
      // TC-009-005: actual selection polling shares the counted link. A band
      // intent must not quiet or replace the original recorded frame workload.
      await pages[0].locator('#operating-refresh:enabled').click();
      await pages[0].waitForFunction(generation=>operatingState?.generation===generation,playback.generation);
      const operatingBefore=await pages[0].evaluate(()=>({revision:operatingState.operating_revision,operation:operatingState.operation}));
      const bandResponse=pages[0].waitForResponse(r=>new URL(r.url()).pathname==='/receive/select'&&r.request().method()==='POST');
      await pages[0].selectOption('#operating-band','40m');const band=await bandResponse;assert.equal(band.status(),409);assert.equal((await band.json()).error.code,'busy');
      await pages[0].locator('#operating-band:enabled').waitFor();
      const operatingAfter=await pages[0].evaluate(()=>({revision:operatingState.operating_revision,operation:operatingState.operation}));
      assert.deepEqual(operatingAfter,operatingBefore,'refused intent changes no selection revision or record');
      const stillPlaying=await f.snapshot();assert.equal(stillPlaying.generation,playback.generation);assert.equal(stillPlaying.job.id,playback.job.id);assert.equal(stillPlaying.job.state,'running');
      for(let n=0;n<10;n++){
        const due=start+(n+1)*5500;await sleep(Math.max(0,due-performance.now()));
        await Promise.all(pages.map(async p=>{const old=await p.locator('#updated').textContent(),time=performance.now();await p.locator('#refresh').click();await p.waitForFunction(value=>document.querySelector('#updated').textContent!==value,old,{timeout:2000});const ms=performance.now()-time;assert.ok(ms<2000,`status ${ms} ms`);latencies.push(ms);}));
      }
      await waitUntil(start+60000);const seconds=(performance.now()-start)/1000;
      assert.ok(seconds>=60,'Thin measurement covers at least60 complete seconds');
      const traffic={up:(f.proxy.counters.up-baseline.up)/seconds,down:(f.proxy.counters.down-baseline.down)/seconds};
      // Bounding the positive sum of both clients by the per-client budget proves each client also stays within it.
      assert.ok(traffic.up<=3000);assert.ok(traffic.down<=3000);
      const captured=await Promise.all(pages.map(p=>p.evaluate(()=>window.__displayEvents)));
      for(const frames of captured){assert.ok(frames.length>=45);assert.ok(frames.length<=65);for(let n=0;n<frames.length;n++){assert.ok(Buffer.byteLength(JSON.stringify(frames[n].message))<=1024);if(n)assert.ok(frames[n].message.data.sequence>frames[n-1].message.data.sequence);}}
      await progress('connected',{step:'Thin measurement complete'},{steadySeconds:seconds,sharedBytesPerSecond:traffic,statusMs:latencies,frames:captured.map(f=>f.length)});
      for(const p of pages)await p.selectOption('#display-profile','off');
      await progress('connected',{step:'Off measurement started'});
      const offBefore={...f.proxy.counters},offStart=performance.now();await waitUntil(offStart+60000);const offSeconds=(performance.now()-offStart)/1000;
      assert.ok(offSeconds>=60,'Off measurement covers at least60 complete seconds');
      const off={up:(f.proxy.counters.up-offBefore.up)/offSeconds,down:(f.proxy.counters.down-offBefore.down)/offSeconds};assert.ok(off.up<=1000);assert.ok(off.down<=1000);
      await progress('connected',{step:'Off measurement complete'},{sharedOffBytesPerSecond:off,offSeconds});
      const uploadBefore={...f.proxy.counters},uploadStart=performance.now(),uploadStatus=[];
      await progress('connected',{step:'Upload and status measurement started'});
      await pages[0].setInputFiles('#recording-file',{name:'paced.wav',mimeType:'audio/wav',buffer:wav(.5)});await pages[0].locator('#recording-import').click();
      for(let n=0;n<6;n++){await sleep(700);await Promise.all(pages.map(async p=>{const old=await p.locator('#updated').textContent(),time=performance.now();await p.locator('#refresh').click();await p.waitForFunction(value=>document.querySelector('#updated').textContent!==value,old,{timeout:2000});const ms=performance.now()-time;assert.ok(ms<2000);uploadStatus.push(ms);}));}
      await pages[0].locator('#recording-replay:enabled').waitFor({timeout:30000});
      const upload={ms:performance.now()-uploadStart,up:f.proxy.counters.up-uploadBefore.up,down:f.proxy.counters.down-uploadBefore.down,statusMs:uploadStatus};
      await progress('connected',{step:'Upload and status measurement complete'},{upload});
    });
  });
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
  const f=await fixture(t),initial=await f.upload(wav(5));
  const ws=new WebSocket(f.origin.replace('http','ws')+'/ws','wstx.v1',{origin:f.origin});await once(ws,'open');t.after(()=>ws.close());
  const messages=[];ws.on('message',data=>messages.push({at:performance.now(),value:JSON.parse(String(data))}));
  let pending=receive(ws);ws.send(JSON.stringify({v:1,type:'spectrum.thin',id:1}));assert.equal((await pending).type,'spectrum.subscription');
  const job=await f.replay();await sleep(3300);
  const frames=messages.filter(m=>m.value.type==='spectrum.frame');assert.ok(frames.length>=2);for(let n=1;n<frames.length;n++)assert.ok(frames[n].at-frames[n-1].at>=995);
  // FIFO may deliver an already buffered optional frame before the correlated Off ACK.
  // FSD12.6 allows bounded buffered output; it does not allow a frame after that ACK.
  const offStart=messages.length,offSent=performance.now();ws.send(JSON.stringify({v:1,type:'spectrum.off',id:2}));
  let ackIndex=-1;
  while(performance.now()-offSent<2000){ackIndex=messages.findIndex((m,i)=>i>=offStart&&!['spectrum.frame','heartbeat'].includes(m.value.type));if(ackIndex>=0)break;await sleep(5);}
  assert.ok(ackIndex>=offStart,'correlated Off ACK arrives within the existing2s control deadline');
  const ack=messages[ackIndex].value;assert.ok(messages[ackIndex].at-offSent<=2000);assert.deepEqual(ack,{v:1,type:'spectrum.subscription',id:2,data:{profile:'off'}});
  for(const m of messages.slice(offStart,ackIndex))if(m.value.type==='heartbeat')assert.deepEqual(m.value,{v:1,type:'heartbeat'});
  const buffered=messages.slice(offStart,ackIndex).filter(m=>m.value.type!=='heartbeat');
  assert.ok(buffered.length<=Math.floor((messages[ackIndex].at-offSent)/995)+1,'buffered prefix remains bounded by Thin cadence and the control deadline');
  for(const m of buffered){assert.deepEqual(Object.keys(m.value).sort(),['data','type','v']);assert.equal(m.value.v,1);const f=m.value.data;assert.deepEqual(Object.keys(f).sort(),['boot_id','end_frame','first_frame','generation','job_id','levels','sequence','source_id']);assert.equal(m.value.type,'spectrum.frame');assert.equal(f.boot_id,initial.boot_id);assert.equal(f.source_id,initial.recording.id);assert.equal(f.job_id,job.id);assert.equal(f.generation,job.generation);assert.ok(Number.isSafeInteger(f.sequence)&&f.sequence>=0&&f.sequence<5);assert.ok(f.first_frame<f.end_frame&&f.end_frame<=60000);assert.equal(f.first_frame,f.sequence*12000);assert.equal(f.end_frame,Math.min(f.first_frame+12000,60000));assert.equal(f.levels.length,128);assert.ok(f.levels.every(q=>Number.isInteger(q)&&q>=0&&q<=120));assert.ok(Buffer.byteLength(JSON.stringify(m.value))<=1024);}
  const throughAck=messages.slice(0,ackIndex+1).filter(m=>m.value.type==='spectrum.frame');for(let n=1;n<throughAck.length;n++)assert.ok(throughAck[n].at-throughAck[n-1].at>=995);
  const noPostAckFrames=()=>assert.equal(messages.slice(ackIndex+1).filter(m=>m.value.type==='spectrum.frame').length,0,'no optional frame may follow the Off ACK');noPostAckFrames();await sleep(1100);noPostAckFrames();
  await f.req('/recording/jobs/'+job.id,'DELETE');await terminal(f);const snapshot=await f.snapshot();assert.equal(snapshot.job.state,'cancelled');
});

// Proves: CL-006-03/04; TC-010-002/003, browser event boundary under loss/late delivery.
test('TC-010-002 browser caps 120 rows, preserves explicit gaps and rejects obsolete identities',{timeout:15000},async t=>{
  const f=await fixture(t);await f.upload(wav(120));const p=await page(f);await p.selectOption('#display-profile','off');await p.evaluate(()=>{document.querySelector('#display-profile').value='thin';});await p.locator('#recording-replay').click();
  await p.locator('#signal-status').filter({hasText:/running/}).waitFor();const s=await f.snapshot();
  await p.getByRole('separator').focus();await p.keyboard.press('End');
  const observation=await p.evaluate(async s=>{
    const make=sequence=>({v:1,type:'spectrum.frame',data:{boot_id:s.boot_id,source_id:s.job.source_id,job_id:s.job.id,generation:s.generation,sequence,first_frame:sequence*12000,end_frame:Math.min((sequence+1)*12000,s.recording.frames),levels:Array(128).fill(20)}});
    const deliver=message=>dispatchEvent(new CustomEvent('station-message',{detail:{message,current:socket}}));
    for(const field of ['boot_id','source_id','job_id','generation']){const m=make(0);m.data[field]=field==='generation'?s.generation-1:'00000000-0000-4000-8000-000000000000';deliver(m);}
    await new Promise(requestAnimationFrame);const ignored=Number(document.querySelector('#waterfall').dataset.rows);
    for(let n=0;n<120;n++)if(n!==118)deliver(make(n));
    deliver(make(120));deliver(make(119));
    await new Promise(requestAnimationFrame);
    const c=document.querySelector('#waterfall'),pixel=[...c.getContext('2d').getImageData(0,Math.floor(20*c.height/c.getBoundingClientRect().height),1,1).data];
    return {ignored,count:Number(c.dataset.rows),sequences:c.dataset.sequences,pixel,label:c.getAttribute('aria-label')};
  },s);
  assert.equal(observation.ignored,0);assert.equal(observation.count,120);assert.equal(observation.sequences,Array.from({length:120},(_,n)=>n).join(','));assert.deepEqual(observation.pixel,[96,96,96,255]);assert.match(observation.label,/visible source time/);
  await f.req('/recording/jobs/'+s.job.id,'DELETE');await terminal(f);
});

// Proves: CL-006-03/04; TC-010-005. Actual fast TLS server and browser; no source or decoded-message fixture.
test('TC-010-005 HTTPS defaults to native Detailed and honors saved Thin or Off',{timeout:15000},async t=>{
  const f=await fixture(t,{secure:true});await f.upload(wav(1));const p=await page(f);
  assert.equal(await p.inputValue('#display-profile'),'detail','every origin defaults to the finest existing profile');
  await p.evaluate(()=>{window.__fineFrames=[];addEventListener('station-message',e=>{if(e.detail.message.type==='spectrum.detail.frame')window.__fineFrames.push(e.detail.message);});});
  await p.locator('#recording-replay').click();await p.waitForFunction(()=>window.__fineFrames.length>0);
  const native=await p.evaluate(()=>window.__fineFrames[0].data);assert.equal(Buffer.from(native.levels_b64,'base64').length,1024);assert.equal(native.end_frame-native.first_frame,2400);
  for(const choice of ['thin','off']){
    await p.locator('[data-region=client-preferences]').first().click();await p.selectOption('#display-profile',choice);await p.reload();await p.waitForFunction(()=>profileData&&snapshot&&!syncPending);
    assert.equal(await p.inputValue('#display-profile'),choice,'explicit saved reduced-bandwidth/Off choice is honored');
  }
  await p.evaluate(()=>localStorage.setItem(`wstx.display-profile.v1:${profileData.profile_id}`,'invalid'));await p.reload();await p.waitForFunction(()=>profileData&&snapshot&&!syncPending);
  assert.equal(await p.inputValue('#display-profile'),'detail','invalid saved choice returns to finest existing default');
});

// Proves: CL-006-03/04; TC-010-005, real native detail wire and independent pixel/geometry oracle.
test('TC-010-005 detailed native wire, fixed span, projection, palette and top-entry cells',{timeout:30000},async t=>{
  const f=await fixture(t);await f.upload(wav(4,.25,756.25));const p=await page(f);
  assert.equal(await p.inputValue('#display-profile'),'detail');
  await p.evaluate(()=>{window.testWire=[];addEventListener('station-message',e=>{if(e.detail.message.type==='spectrum.detail.frame')window.testWire.push(e.detail.message);});});
  await p.locator('#recording-replay').click();await p.waitForFunction(()=>Number(document.querySelector('#waterfall').dataset.rows)>1,{timeout:5000});
  const s=await f.snapshot(),wire=await p.evaluate(()=>window.testWire);assert.ok(wire.length);const m=wire[0];assert.ok(Buffer.byteLength(JSON.stringify(m))<=2048);assert.equal(m.data.levels_b64.length,1368);assert.equal(Buffer.from(m.data.levels_b64,'base64').length,1024);assert.equal(m.data.first_frame,m.data.sequence*2400);
  await p.selectOption('#display-profile','off');
  // Keep network Off while selecting the pure browser fixture profile; no fake data reaches the server.
  await p.evaluate(()=>{document.querySelector('#display-profile').value='detail';rows=[];resetLevels();});
  for(const width of [1100,360]){
    await p.setViewportSize({width,height:850});
    const result=await p.evaluate(async s=>{
      const values=Array.from({length:1024},(_,k)=>k%2?120:0), bytes=String.fromCharCode(...values);
      const frame=sequence=>({v:1,type:'spectrum.detail.frame',data:{boot_id:s.boot_id,source_id:s.job.source_id,job_id:s.job.id,generation:s.generation,sequence,first_frame:sequence*2400,end_frame:Math.min((sequence+1)*2400,s.recording.frames),levels_b64:btoa(bytes)}});
      rows=[];displayBlack=-120;displayRange=80;autoBlack=false;
      const deliver=message=>dispatchEvent(new CustomEvent('station-message',{detail:{message,current:socket}}));
      deliver(frame(0));deliver(frame(2));await new Promise(requestAnimationFrame);
      const c=document.querySelector('#waterfall'),ctx=c.getContext('2d'),h=Math.floor(.2*20*c.height/c.getBoundingClientRect().height),pix=(x,y)=>[...ctx.getImageData(x,y,1,1).data];
      const expected=Array(c.width).fill(0);for(let k=0;k<1024;k++)if(c.width<1024)expected[Math.floor(k*c.width/1024)]=Math.max(expected[Math.floor(k*c.width/1024)],values[k]);else for(let x=Math.floor(k*c.width/1024);x<Math.floor((k+1)*c.width/1024);x++)expected[x]=values[k];
      const cells=expected.every((q,x)=>JSON.stringify(pix(x,0))===JSON.stringify(q?[255,0,0,255]:[0,0,12,255]));
      const before=c.dataset.rows;
      for(const edit of [{levels_b64:'!'.repeat(1368)},{levels_b64:btoa(String.fromCharCode(...Array(1024).fill(121)))},{levels_b64:btoa('x')},{sequence:999},{extra:1},{generation:s.generation-1}]){const m=frame(3);Object.assign(m.data,edit);deliver(m);}
      await new Promise(requestAnimationFrame);
      return {cells,gap:pix(0,h),bottom:pix(0,c.height-1),narrow:c.width<1024,before,after:c.dataset.rows,unmodified:rows.at(-1).levels.every((q,k)=>q===values[k]),overflow:document.documentElement.scrollWidth>innerWidth,axis:document.querySelector('#frequency-ruler').textContent};
    },s);
    assert.ok(result.cells);assert.deepEqual(result.gap,[96,96,96,255]);assert.deepEqual(result.bottom,[0,0,12,255]);assert.equal(result.before,result.after);assert.ok(result.unmodified);assert.equal(result.overflow,false);assert.match(result.axis,/3000/);assert.match(result.axis,/0/);
  }
  await f.req('/recording/jobs/'+s.job.id,'DELETE');
});

// Proves: CL-006-03; TC-010-005 actual licensed FT8 recording, two real DPRs, local controls and screenshots.
test('TC-010-005 actual FT8 desktop and DPR2 mobile presentation and local level controls',{timeout:35000},async t=>{
  const samples=process.env.WSTX_SAMPLE_DIR;assert.ok(samples,'WSTX_SAMPLE_DIR required for real-recording acceptance');
  const f=await fixture(t);await f.upload(await fs.readFile(path.join(samples,'websdr_test1.wav')));
  const desktop=await page(f);
  const context=await browser.newContext({deviceScaleFactor:2});t.after(()=>context.close());
  const mobile=await page({...f,context},{width:360,height:640});
  for(const p of [desktop,mobile])assert.equal(await p.inputValue('#display-profile'),'detail');
  await desktop.locator('#recording-replay').click();
  for(const p of [desktop,mobile])await p.waitForFunction(()=>Number(document.querySelector('#waterfall').dataset.rows)>=45,{timeout:15000});
  await fs.mkdir('test-results',{recursive:true});
  for(const p of [desktop,mobile]){await p.locator('#display-sensitivity').fill('6');await p.locator('#display-sensitivity').dispatchEvent('input');await p.locator('#display-sensitivity').fill('0');await p.locator('#display-sensitivity').dispatchEvent('input');await p.locator('#display-speed').fill('2');await p.locator('#display-speed').dispatchEvent('input');}
  await desktop.screenshot({path:'test-results/cr6-sliders-ft8-desktop.png',fullPage:true});
  await mobile.screenshot({path:'test-results/cr6-sliders-ft8-mobile-dpr2.png',fullPage:true});
  for(const p of [desktop,mobile]){
    assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
    for(const key of ['Home','End']){await p.getByRole('separator').focus();await p.keyboard.press(key);await p.waitForTimeout(30);const g=await p.evaluate(()=>{const a=document.querySelector('#spectrum').getBoundingClientRect(),b=waterfall.getBoundingClientRect();return {ratio:b.height-5*a.height,pixels:waterfall.height,expected:Math.round(b.height*devicePixelRatio)};});assert.ok(Math.abs(g.ratio)<=2,JSON.stringify(g));assert.equal(g.pixels,g.expected);}
    const before=await p.evaluate(()=>({black:displayBlack,range:displayRange,auto:autoBlack,frozen:estimateFrozen,copy:[...rows.at(-1).levels]}));
    assert.equal(before.auto,true);assert.equal(before.frozen,true);assert.equal(before.range,30);
    await p.locator('#display-black').fill('-90');await p.locator('#display-black').dispatchEvent('change');
    assert.equal(await p.isChecked('#display-auto'),false);
    await p.locator('#display-range').fill('50');await p.locator('#display-range').dispatchEvent('change');
    assert.equal(await p.inputValue('#display-range'),'50');
    await p.evaluate(()=>{const original=rows.at(-1);window.originalLevelCheck=original.levels;estimateFrozen=false;autoBlack=true;displayBlack=-120;estimate({levels:new Uint8Array(1024)});window.silenceWait=!estimateFrozen;estimate({levels:new Uint8Array(1024).fill(40)});});
    assert.deepEqual(await p.evaluate(()=>[window.silenceWait,displayBlack,estimateFrozen]),[true,-83,true]);
    await p.locator('#waterfall').focus();await p.keyboard.press('ArrowRight');assert.match(await p.locator('#bin-readout').innerText(),/Native bin 1/);
    await p.evaluate(()=>{document.body.style.zoom='200%';dispatchEvent(new Event('resize'));});
    await p.waitForTimeout(40);assert.equal(await p.locator('#waterfall').getAttribute('data-span'),'0,3000');
    await p.evaluate(()=>{document.body.style.zoom='';dispatchEvent(new Event('resize'));});
  }
  const s=await f.snapshot();await f.req('/recording/jobs/'+s.job.id,'DELETE');
});

// Proves: CL-006-03/04; TC-010-005 pointer native bin and projected column are independent.
test('TC-010-005 review pointer column boundary uses actual projected pixels',{timeout:10000},async t=>{
  const f=await fixture(t);await f.upload(wav(4));const p=await page(f);await p.locator('#recording-replay').click();await p.locator('#signal-status').filter({hasText:/running/}).waitFor();await p.selectOption('#display-profile','off');const s=await f.snapshot();
  const text=await p.evaluate(async s=>{
    profileSelect.value='detail';rows=[];const levels=new Uint8Array(1024);levels[4]=120;
    dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'spectrum.detail.frame',data:{boot_id:s.boot_id,source_id:s.job.source_id,job_id:s.job.id,generation:s.generation,sequence:0,first_frame:0,end_frame:2400,levels_b64:btoa(String.fromCharCode(...levels))}}}}));
    waterfall.style.setProperty('width','300px','important');paint();await new Promise(requestAnimationFrame);
    const b=waterfall.getBoundingClientRect();waterfall.dispatchEvent(new PointerEvent('pointermove',{clientX:b.left+1.01,clientY:b.top+.5}));return document.querySelector('#bin-readout').textContent;
  },s);
  assert.match(text,/Native bin 3 /);assert.match(text,/projected bins 4-6: 0 dBFS/);await f.req('/recording/jobs/'+s.job.id,'DELETE');
});
// Proves: CL-006-03/04; TC-010-005 a bounded sequence beyond a short source is still invalid.
test('TC-010-005 review short source rejects inverted out-of-source interval',{timeout:10000},async t=>{
  const f=await fixture(t);await f.upload(wav(4));const p=await page(f);await p.locator('#recording-replay').click();await p.locator('#signal-status').filter({hasText:/running/}).waitFor();await p.selectOption('#display-profile','off');const s=await f.snapshot();
  const count=await p.evaluate(async s=>{
    profileSelect.value='detail';rows=[];
    const data={boot_id:s.boot_id,source_id:s.job.source_id,job_id:s.job.id,generation:s.generation,sequence:0,first_frame:0,end_frame:2400,levels_b64:btoa(String.fromCharCode(...new Uint8Array(1024)))};
    dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'spectrum.detail.frame',data}}}));
    if(rows.length!==1)throw Error('valid frame must be accepted before negative case');
    dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'spectrum.detail.frame',data:{boot_id:s.boot_id,source_id:s.job.source_id,job_id:s.job.id,generation:s.generation,sequence:100,first_frame:240000,end_frame:s.recording.frames,levels_b64:btoa(String.fromCharCode(...new Uint8Array(1024)))}}}}));
    await new Promise(requestAnimationFrame);return rows.length;
  },s);assert.equal(count,1);await f.req('/recording/jobs/'+s.job.id,'DELETE');
});
// Proves: CL-006-03/04; TC-010-005 actual Detailed cadence and independent control responsiveness.
test('TC-010-005 review real Detailed peer cadence and control priority',{timeout:10000},async t=>{
  const f=await fixture(t);await f.upload(wav(3));
  const ws=new WebSocket(f.origin.replace('http','ws')+'/ws','wstx.v1',{origin:f.origin});await once(ws,'open');t.after(()=>ws.close());
  const stamps=[];ws.on('message',raw=>{const m=JSON.parse(String(raw));if(m.type==='spectrum.detail.frame')stamps.push(performance.now());});
  let pending=receive(ws);ws.send(JSON.stringify({v:1,type:'spectrum.detail',id:1}));assert.equal((await pending).data.profile,'detail');await f.replay();
  await sleep(1700);const started=performance.now();pending=receive(ws);ws.send(JSON.stringify({v:1,type:'station.get',id:2}));assert.equal((await pending).type,'station.status');assert.ok(performance.now()-started<2000);
  assert.ok(stamps.length>=5);for(let k=1;k<stamps.length;k++)assert.ok(stamps[k]-stamps[k-1]>=195,JSON.stringify(stamps));
  const s=await f.snapshot();await f.req('/recording/jobs/'+s.job.id,'DELETE');
});

// Proves: CL-006-03; TC-010-006 independent palette endpoints before any slider-dependent assertion.
test('TC-010-006 exact strong red and no-signal navy palette',{timeout:10000},async t=>{
  const f=await fixture(t),p=await page(f);
  const colors=await p.evaluate(()=>[color(120),color(0)]);assert.deepEqual(colors,['rgb(255 0 0)','rgb(0 0 12)']);
  const actual=await p.evaluate(async()=>{paint();await new Promise(requestAnimationFrame);const bar=document.querySelector('#level-bar'),ctx=bar.getContext('2d');return {first:[...ctx.getImageData(0,0,1,1).data],last:[...ctx.getImageData(bar.width-1,0,1,1).data]};});
  assert.deepEqual(actual.first,[0,0,12,255]);assert.deepEqual(actual.last,[255,0,0,255]);
});
// Proves: CL-006-03/04; TC-010-007 independent source-time movement, clipping and unobserved pixels.
test('TC-010-007 waterfall moves at fixed source-time speed and exits the bottom',{timeout:30000},async t=>{
  const f=await fixture(t);await f.upload(wav(120));const p=await page(f,{width:1100,height:1050});await p.selectOption('#display-profile','off');await p.locator('#recording-replay').click();await p.locator('#signal-status').filter({hasText:/running/}).waitFor();const s=await f.snapshot();
  // Three Thin rows at80px/s need a tall plot; default workspace is intentionally compact.
  const movementSeparator=p.getByRole('separator');await movementSeparator.focus();await p.keyboard.press('End');
  assert.ok((await p.locator('#waterfall').boundingBox()).height>=240,'fixture observes all three row positions before testing exit');
  const result=await p.evaluate(async s=>{
    profileSelect.value='detail';rows=[];displayBlack=-120;displayRange=30;autoBlack=false;
    const frame=sequence=>{const detail=profileSelect.value==='detail',interval=detail?2400:12000,levels=new Uint8Array(detail?1024:128).fill(sequence===0?120:0);return {v:1,type:detail?'spectrum.detail.frame':'spectrum.frame',data:{boot_id:s.boot_id,source_id:s.job.source_id,job_id:s.job.id,generation:s.generation,sequence,first_frame:sequence*interval,end_frame:(sequence+1)*interval,...(detail?{levels_b64:btoa(String.fromCharCode(...levels))}:{levels:[...levels]})}};};
    const send=sequence=>dispatchEvent(new CustomEvent('station-message',{detail:{message:frame(sequence),current:socket}}));
    const draw=async()=>{paint();await new Promise(requestAnimationFrame);};
    const pixel=y=>[...waterfall.getContext('2d').getImageData(0,y,1,1).data];
    const checks=[];
    for(const profile of ['detail','thin'])for(const v of [.5,1,2,8]){
      profileSelect.value=profile;const dt=profile==='detail'?.2:1;
      rows=[];const input=document.querySelector('#display-speed');input.value=v;input.dispatchEvent(new Event('input'));send(0);await draw();
      const H=waterfall.height,C=waterfall.getBoundingClientRect().height,scale=10*v*H/C,positions=[];
      for(let seq=0;seq<3;seq++){
        if(seq){send(seq);await draw();}
        const T=(seq+1)*(profile==='detail'?2400:12000)/12000,top=Math.floor((T-dt)*scale),bottom=Math.max(top+1,Math.floor(T*scale));
        positions.push({top,bottom,red:pixel(top),after:bottom<H?pixel(bottom):null});
      }
      const exit=Math.ceil(C/(10*v*dt))+1;for(let seq=3;seq<=exit;seq++)send(seq);await draw();
      const data=[...waterfall.getContext('2d').getImageData(0,0,1,H).data];
      checks.push({profile,v,actual:Number(input.value),positions,exited:!data.some((q,k)=>k%4===0&&q===255)});
    }
    profileSelect.value='detail';rows=[];speed=.5;send(0);await draw();const b=waterfall.getBoundingClientRect();waterfall.dispatchEvent(new PointerEvent('pointermove',{clientX:b.left+1,clientY:b.bottom-1}));
    const emptyReadout=document.querySelector('#bin-readout').textContent;
    const frozen=[...waterfall.getContext('2d').getImageData(0,0,1,waterfall.height).data];await new Promise(r=>setTimeout(r,100));await draw();
    const unchanged=frozen.every((q,k)=>q===waterfall.getContext('2d').getImageData(0,0,1,waterfall.height).data[k]);
    waterfall.parentElement.style.flex='none';waterfall.parentElement.style.height='30.4px';rows=[];send(0);send(1);await draw();
    waterfall.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowLeft'}));const alias=document.querySelector('#bin-readout').textContent;
    rows[1].levels=null;await draw();const gap=pixel(0);
    return {checks,emptyReadout,unchanged,alias,gap};
  },s);
  for(const check of result.checks){for(const pos of check.positions){assert.deepEqual(pos.red,[255,0,0,255],JSON.stringify(check));if(pos.after)assert.deepEqual(pos.after,[0,0,12,255],JSON.stringify(check));}assert.equal(check.actual,check.v);assert.ok(check.exited,JSON.stringify(check));}
  assert.match(result.emptyReadout,/No measurement/i);assert.ok(result.unchanged);
  assert.match(result.alias,/Native bin 0 .* -120 dBFS/);assert.match(result.alias,/projected bins 0-0: 0 dBFS/);assert.match(result.alias,/projected source 0.0-0.400 s/);assert.deepEqual(result.gap,[96,96,96,255]);
  await f.req('/recording/jobs/'+s.job.id,'DELETE');
});
// Proves: CL-006-03/04; TC-010-006 full canvas geometry with fixed source-time rows.
test('TC-010-006 complete canvas, speed projection, gaps and geometry',{timeout:30000},async t=>{
  const f=await fixture(t);await f.upload(wav(120));const p=await page(f);await p.locator('#recording-replay').click();await p.locator('#signal-status').filter({hasText:/running/}).waitFor();await p.selectOption('#display-profile','off');const s=await f.snapshot();
  const result=await p.evaluate(async s=>{
    profileSelect.value='detail';rows=[];displayBlack=-120;displayRange=30;autoBlack=false;
    const send=(sequence,q)=>dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'spectrum.detail.frame',data:{boot_id:s.boot_id,source_id:s.job.source_id,job_id:s.job.id,generation:s.generation,sequence,first_frame:sequence*2400,end_frame:(sequence+1)*2400,levels_b64:btoa(String.fromCharCode(...new Uint8Array(1024).fill(q)))}}}}));
    send(0,120);send(1,0);await new Promise(requestAnimationFrame);
    const c=waterfall,ctx=c.getContext('2d'),pixel=y=>[...ctx.getImageData(0,y,1,1).data];
    return {top:pixel(0),bottom:pixel(c.height-1),box:c.getBoundingClientRect().height,height:c.height};
  },s);
  assert.deepEqual(result.top,[0,0,12,255]);assert.deepEqual(result.bottom,[0,0,12,255]);
  const matrix=await p.evaluate(async s=>{
    window.presentationFrame=async(N,gap=-1)=>{
      rows=[];
      for(let seq=0;seq<N;seq++)rows.push({sequence:seq,first_frame:seq*2400,end_frame:(seq+1)*2400,levels:seq===gap?null:new Uint8Array(1024).fill(seq%2?0:120)});
      paint();await new Promise(requestAnimationFrame);
    };
    const observations=[];
    for(const N of [2,75,600])for(const v of [1,2,8]){
      await presentationFrame(N);document.querySelector('#display-speed').value=v;document.querySelector('#display-speed').dispatchEvent(new Event('input'));await new Promise(requestAnimationFrame);
      const c=waterfall,H=c.height,C=c.getBoundingClientRect().height,scale=10*v*H/C,T=N*2400/12000,data=c.getContext('2d').getImageData(0,0,1,H).data;
      let correct=true;const visible=new Set();
      for(let y=0;y<H;y++){
        let strong=false;for(let seq=0;seq<N;seq++){const top=Math.floor((T-(seq+1)*2400/12000)*scale),bottom=Math.max(top+1,Math.floor((T-seq*2400/12000)*scale));if(y>=top&&y<bottom){visible.add(seq);if(seq%2===0)strong=true;}}
        const expected=strong?[255,0,0,255]:[0,0,12,255];if(expected.some((q,k)=>data[y*4+k]!==q))correct=false;
      }
      observations.push({N,v,R:visible.size,actual:Number(c.dataset.visibleRows),correct});
    }
    document.querySelector('#display-speed').value=1;document.querySelector('#display-speed').dispatchEvent(new Event('input'));
    waterfall.parentElement.style.setProperty('flex','none');waterfall.parentElement.style.height='10px';
    await presentationFrame(75,70);
    const c=waterfall,H=c.height,data=c.getContext('2d').getImageData(0,0,1,H).data;
    const greyY=Math.floor((15-14.2)*10*H/c.getBoundingClientRect().height),grey=[...data.slice(greyY*4,greyY*4+4)];
    waterfall.parentElement.style.height='30px';rows=Array.from({length:75},(_,sequence)=>({sequence,first_frame:sequence*2400,end_frame:(sequence+1)*2400,levels:new Uint8Array(1024)}));rows[71].levels.fill(120);paint();await new Promise(requestAnimationFrame);
    const b=waterfall.getBoundingClientRect();waterfall.dispatchEvent(new PointerEvent('pointermove',{clientX:b.left+.1,clientY:b.top+6.01*b.height/waterfall.height}));
    const boundary={native:selectedRow,pixel:[...waterfall.getContext('2d').getImageData(0,6,1,1).data],text:document.querySelector('#bin-readout').textContent};
    document.querySelector('#display-speed').value=8;document.querySelector('#display-speed').dispatchEvent(new Event('input'));for(let k=0;k<15;k++)waterfall.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown'}));
    return {observations,grey,boundary,clamped:selectedRow};
  },s);
  for(const o of matrix.observations){assert.equal(o.actual,o.R,JSON.stringify(o));assert.ok(o.correct,JSON.stringify(o));}assert.deepEqual(matrix.grey,[96,96,96,255]);assert.equal(matrix.boundary.native,3);assert.deepEqual(matrix.boundary.pixel,[255,0,0,255]);assert.match(matrix.boundary.text,/source 14.2-14.400 s/);assert.match(matrix.boundary.text,/projected source 14.2-14.400 s/);assert.equal(matrix.clamped,1);
  await p.evaluate(()=>{waterfall.parentElement.style.removeProperty('flex');waterfall.parentElement.style.removeProperty('height');dispatchEvent(new Event('resize'));});
  for(const viewport of [{width:1100,height:850},{width:360,height:640}]){
    await p.setViewportSize(viewport);await p.waitForTimeout(40);
    const geometry=await p.evaluate(()=>{const a=document.querySelector('#spectrum').getBoundingClientRect(),b=waterfall.getBoundingClientRect();return {a:a.height,b:b.height,bitmap:waterfall.height,expected:Math.round(b.height*devicePixelRatio),overflow:document.documentElement.scrollWidth>innerWidth,span:waterfall.dataset.span};});
    assert.ok(Math.abs(geometry.b-5*geometry.a)<=2,JSON.stringify(geometry));assert.equal(geometry.bitmap,geometry.expected);assert.equal(geometry.overflow,false);assert.equal(geometry.span,'0,3000');
  }
  await f.req('/recording/jobs/'+s.job.id,'DELETE');
});
// Proves: CL-006-03/04; TC-010-006 live local sensitivity/speed do not change calibrated data, Auto or job.
test('TC-010-006 live sensitivity and speed sliders preserve original data and reset semantics',{timeout:15000},async t=>{
  const f=await fixture(t),p=await page(f);
  assert.equal(await p.locator('#display-sensitivity[type=range]').count(),1);assert.equal(await p.locator('#display-speed[type=range]').count(),1);
  const observations=await p.evaluate(async()=>{
    rows=[{sequence:0,first_frame:0,end_frame:2400,levels:new Uint8Array(1024).fill(40)}];displayBlack=-83;displayRange=30;autoBlack=true;estimateFrozen=true;
    const original=[...rows[0].levels],curve=()=>[...document.querySelector('#spectrum').getContext('2d').getImageData(0,0,document.querySelector('#spectrum').width,document.querySelector('#spectrum').height).data];
    paint();await new Promise(requestAnimationFrame);const beforeCurve=curve();
    const results=[];
    for(const g of [-30,0,10,30]){const input=document.querySelector('#display-sensitivity');input.value=g;input.dispatchEvent(new Event('input'));await new Promise(requestAnimationFrame);results.push({g,E:effectiveBlack(),auto:autoBlack,frozen:estimateFrozen,label:document.querySelector('#sensitivity-value').textContent,unchanged:rows[0].levels.every((q,k)=>q===original[k]),curve:curve().every((q,k)=>q===beforeCurve[k])});}
    document.querySelector('#display-speed').value=8;document.querySelector('#display-speed').dispatchEvent(new Event('input'));resetLevels();
    return {results,persist:[sensitivity,speed],reset:[displayBlack,displayRange,autoBlack],speedLabel:document.querySelector('#speed-value').textContent};
  });
  for(const o of observations.results){assert.equal(o.E,Math.max(-120,Math.min(-30,-83-o.g)));assert.ok(o.auto&&o.frozen&&o.unchanged&&o.curve);assert.match(o.label,/dB/);}
  assert.deepEqual(observations.persist,[30,8]);assert.deepEqual(observations.reset,[-120,30,true]);assert.equal(observations.speedLabel,'80 px/s');
  await p.selectOption('#display-profile','thin');assert.equal(await p.inputValue('#display-sensitivity'),'30');assert.equal(await p.inputValue('#display-speed'),'8');
  await p.locator('#display-sensitivity').focus();await p.keyboard.press('Home');assert.equal(await p.inputValue('#display-sensitivity'),'-30');await p.keyboard.press('End');assert.equal(await p.inputValue('#display-sensitivity'),'30');
});
