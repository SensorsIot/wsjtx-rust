'use strict';
// Independent oracle: canonical SysML receive-selection contract. Disposable authenticated TLS station only.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
const net=require('node:net'),https=require('node:https');
const {once}=require('node:events');
const {randomUUID}=require('node:crypto');
const {gunzipSync,gzipSync}=require('node:zlib');
const selfsigned=require('selfsigned');
const {server,grant,loginPage,browserPort}=require('../tools/test/node/support.cjs');
const {selectionNetworkSummary,supersededColdRead,cadenceSource,cadenceQualification,cadenceJoin,failureEvidence,failureHooks,evidenceWindow,correlatedOffAck,assertOffAckDeadline,optionalAfterOff,observeReceiveResponse,abandonedBodiesNotReRead}=require('../tools/test/node/selection-evidence.cjs');

async function station(t,control={mode:'disabled',endpoint:null,ptt:'disabled'}){
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'wstx-selection-'));
  t.after(()=>fs.rm(dir,{recursive:true,force:true}));
  const port=await browserPort();
  const origin=`https://localhost:${port}`,id=randomUUID(),token=randomUUID().replaceAll('-','');
  const cert=await selfsigned.generate([{name:'commonName',value:'localhost'}],{days:1,keySize:2048,extensions:[{name:'subjectAltName',altNames:[{type:2,value:'localhost'}]}]});
  await fs.writeFile(path.join(dir,'cert.pem'),cert.cert);await fs.writeFile(path.join(dir,'key.pem'),cert.private);
  // A managed radio (CAT on a COM port the station can drive) is saved with its radio settings.
  const radio=control.mode==='cat'&&/^(icom7300:\/\/)?COM\d+(\?|$)/i.test(control.endpoint??'')?{radio:{agc:'SLOW'}}:{};
  await fs.writeFile(path.join(dir,'profile.json'),JSON.stringify({schema_version:1,profile_id:id,revision:0,display_name:'Selection fixture',callsign:'HB9BLA',locator:'JN47AA',endpoint:{bind:`127.0.0.1:${port}`,origin},connection_type:'standard',audio:{input_device:null,output_device:null},control,...radio}));
  const app=await server({WSTX_TLS_CERT:path.join(dir,'cert.pem'),WSTX_TLS_KEY:path.join(dir,'key.pem'),WSTX_TOKEN:token},['--profile',dir]);t.after(()=>app.close());
  let cookie='';
  const request=(route,method='GET',body,extra={})=>new Promise((resolve,reject)=>{
    const req=https.request(origin+route,{method,ca:cert.cert,agent:false,headers:{Origin:origin,...(cookie?{Cookie:cookie}:{}),...(body===undefined?{}:{'Content-Type':'application/json'}),...extra}},res=>{
      const chunks=[];res.on('data',b=>chunks.push(b));res.on('end',()=>{try{const raw=Buffer.concat(chunks),text=(res.headers['content-encoding']==='gzip'?gunzipSync(raw):raw).toString('utf8');resolve({status:res.statusCode,headers:res.headers,raw,text,body:text&&(res.headers['content-type']||'').startsWith('application/json')?JSON.parse(text):null});}catch(error){reject(error);}});
    });req.on('error',reject);if(body!==undefined)req.write(typeof body==='string'||Buffer.isBuffer(body)?body:JSON.stringify(body));req.end();
  });
  // Selected HTTPS profile: raw requests use the real grant flow, not the token cookie.
  cookie=(await grant(origin,token,(route,method,body,extra)=>request(route,method,body,extra))).cookie;
  return {origin,id,request,cookie,token};
}

// Parent has no selection route, so this
// fails on actual HTTP404 rather than a build/import error.
if(!process.env.WSTX_SELECTION_FIXTURE){
// Proves: TC-003-003
test('H1 raw TLS gzip snapshots preserve bounded JSON',{timeout:30000},async t=>{
  const {request,cookie}=await station(t);
  for(const route of ['/profile','/receive/selection','/receive','/radio','/recording']){
    const identity=await request(route,'GET',undefined,{'Accept-Encoding':'identity'});
    assert.equal(identity.status,200);assert.equal(identity.headers['content-encoding'],undefined);
    const encoded=await request(route,'GET',undefined,{'Accept-Encoding':'gzip'});
    assert.equal(encoded.status,200);
    assert.equal(encoded.headers['content-encoding'],'gzip',`actual ${route} response must negotiate gzip`);
    assert.deepEqual([...encoded.raw.subarray(0,3)],[0x1f,0x8b,8]);
    const decoded=gunzipSync(encoded.raw);assert.equal(encoded.raw.readUInt32LE(encoded.raw.length-4),decoded.length);
    assert.equal(decoded.toString('utf8'),encoded.text);assert.match(encoded.headers['content-type'],/^application\/json/);
    assert.ok(encoded.headers.vary.split(',').map(v=>v.trim().toLowerCase()).includes('accept-encoding'));
    if(encoded.headers['content-length'])assert.equal(Number(encoded.headers['content-length']),encoded.raw.length);
    const old=structuredClone(identity.body),current=structuredClone(encoded.body);
    if(route==='/receive/selection'){delete old.monotonic_ms;delete current.monotonic_ms;delete old.snapshot_sequence;delete current.snapshot_sequence;}
    assert.deepEqual(current,old,'immutable logical fields survive transfer encoding; monotonic selection facts are temporal');
    assert.ok(!encoded.text.includes(cookie.slice(cookie.indexOf('=')+1)),'credential never enters JSON');
  }
});

// The independent Accept-Encoding vectors of WstxContentCoding::CodingRule, read from the
// fixture that names their source, never from candidate negotiation output.
function negotiationVectors(){
  const fixture=require('./fixtures/http/content-coding-negotiations.json');
  const vectors=fixture.vectors.map(vector=>({fields:vector.accept_encoding,expected:vector.expected}));
  assert.equal(vectors.length,49,'all 49 negotiation vectors must execute');return vectors;
}

test('H1 all 49 ordered header cases use the real authenticated TLS router',{timeout:30000},async t=>{
  const {request}=await station(t);
  const vectors=negotiationVectors();
  assert.equal(vectors.length,49);const identity=await request('/profile');assert.equal(identity.status,200);
  for(const [index,vector]of vectors.entries()){
    const actual=await request('/profile','GET',undefined,vector.fields.length?{'Accept-Encoding':vector.fields}:{});
    assert.equal(actual.status,vector.expected==='406'?406:200,`frozen vector${index+1}`);
    assert.equal(actual.headers['content-encoding'],vector.expected==='gzip'?'gzip':undefined,`frozen vector${index+1}`);
    if(vector.expected==='gzip'){assert.deepEqual([...actual.raw.subarray(0,3)],[31,139,8]);assert.equal(gunzipSync(actual.raw).toString('utf8'),identity.text);}
    if(vector.expected==='identity')assert.equal(actual.text,identity.text);
  }
});

// Proves: TC-003-001, TC-003-003, TC-021-005
test('H1 authentication errors mutations static and HEAD bypass negotiation',{timeout:30000},async t=>{
  const {id,request}=await station(t),forbidden={'Accept-Encoding':'identity;q=0,gzip;q=0'};
  for(const [route,method,body,headers,status]of [
    ['/profile','GET',undefined,{Cookie:''},401],
    ['/profile','GET',undefined,{Origin:'https://invalid.example'},403],
    ['/receive/selection?unexpected=1','GET',undefined,{},400],
    ['/receive/results','GET',undefined,{},400],
    ['/not-a-route','GET',undefined,{},404],
    ['/profile','PUT',{}, {},400],
    ['/receive/select','POST',{}, {},400],
    ['/radio/operation','POST',{}, {},400],
    ['/session','POST','x'.repeat(32),{},401],
    ['/','GET',undefined,{},200],['/app.js','GET',undefined,{},200],
    ['/recording.js','GET',undefined,{},200],['/style.css','GET',undefined,{},200],
    ['/recording.css','GET',undefined,{},200],['/profile','HEAD',undefined,{},200],
  ]){
    const actual=await request(route,method,body,{...forbidden,...headers});assert.equal(actual.status,status,`${method}${route}`);assert.equal(actual.headers['content-encoding'],undefined);
    if(method==='HEAD')assert.equal(actual.raw.length,0);
    assert.equal(actual.headers['cache-control'],'no-store');assert.equal(actual.headers['x-content-type-options'],'nosniff');assert.ok(actual.headers['content-security-policy']);
  }
  const prior=(await request('/receive/selection')).body;
  const intent={v:1,profile_id:id,boot_id:prior.boot_id,command_id:randomUUID(),action:'mode',profile_revision:0,generation:prior.generation,operating_revision:prior.operating_revision,mode:'ft4'};
  const refused=await request('/receive/select','POST',intent,forbidden);assert.equal(refused.status,409);assert.equal(refused.body.error.code,'select_band_first');assert.equal(refused.headers['content-encoding'],undefined);
  const compressedRequest=await request('/receive/select','POST',gzipSync(Buffer.from(JSON.stringify(intent))),{'Content-Encoding':'gzip',...forbidden});assert.equal(compressedRequest.status,415);assert.equal(compressedRequest.headers['content-encoding'],undefined);
  const after=(await request('/receive/selection')).body;assert.equal(after.operating_revision,prior.operating_revision);assert.equal(after.generation,prior.generation);assert.equal(after.receive.job_id,null);
});

// Proves: TC-009-005
test('authenticated TLS selection reports unknown nominal and early refusal',{timeout:30000},async t=>{
  const {id,request}=await station(t);
  const initial=await request('/receive/selection');assert.equal(initial.status,200,'selection route exists');
  const s=initial.body;assert.deepEqual(Object.keys(s).sort(),'v,profile_id,boot_id,profile_revision,generation,operating_revision,snapshot_sequence,monotonic_ms,control,selection,available_bands,operation,cancellation,receive,radio'.split(',').sort());
  assert.equal(s.profile_id,id);assert.equal(s.control,'manual');assert.deepEqual(s.selection,{mode:'ft8',band:null,nominal_hz:null,origin:'unknown',confirmed_command_id:null});
  const command={v:1,profile_id:id,boot_id:s.boot_id,command_id:randomUUID(),action:'mode',profile_revision:0,generation:s.generation,operating_revision:s.operating_revision,mode:'ft4'};
  const refused=await request('/receive/select','POST',command);assert.equal(refused.status,409);assert.deepEqual(refused.body,{error:{code:'select_band_first',field:null}});
  const after=(await request('/receive/selection')).body;assert.equal(after.operating_revision,s.operating_revision);assert.equal(after.operation,null);assert.equal(after.receive.job_id,null);
  const radio=await request('/radio');assert.equal(radio.status,200);assert.equal(radio.body.state,'closed');assert.equal(radio.body.observation,null);
});

// Fixed expectations come from the
// canonical CAS/fence contract, independently of the candidate's state machine.
// Proves: TC-009-005
test('unseen mutation fencing rejects delayed POST without creating operation',{timeout:30000},async t=>{
  const {id,request}=await station(t);const initial=await request('/receive/selection');assert.equal(initial.status,200);
  const s=initial.body,target=randomUUID(),cancel={v:1,profile_id:id,boot_id:s.boot_id,command_id:randomUUID(),action:'cancel',operating_revision:s.operating_revision,target_command_id:target};
  const ack=await request('/receive/select','POST',cancel);assert.equal(ack.status,202);assert.equal(ack.body.phase,'cancelled');assert.equal(ack.body.operating_revision,s.operating_revision+1);assert.ok(Buffer.byteLength(ack.text)<=384);
  const after=await request('/receive/selection');assert.equal(after.body.operation,null);assert.equal(after.body.cancellation.result,'fenced');assert.ok(Buffer.byteLength(after.text)<=3072);
  const delayed=await request('/receive/select','POST',{v:1,profile_id:id,boot_id:s.boot_id,command_id:target,action:'band',profile_revision:0,generation:s.generation,operating_revision:s.operating_revision,band:'40m'});assert.equal(delayed.status,409);assert.equal(delayed.body.error.code,'state_conflict');
  const duplicate=await request('/receive/select','POST',cancel);assert.equal(duplicate.status,200);assert.deepEqual(duplicate.body,ack.body);
  const invalid=await request('/receive/select','POST',{...cancel,target_command_id:randomUUID()});assert.equal(invalid.status,409);assert.equal(invalid.body.error.code,'state_conflict');
  const changedRevision=await request('/receive/select','POST',{...cancel,operating_revision:ack.body.operating_revision});assert.equal(changedRevision.status,409);assert.equal(changedRevision.body.error.code,'state_conflict');
});

// These responses come from the actual
// authenticated router; no serial device or positive response is intercepted.
// Proves: TC-009-005, TC-021-005
test('strict TLS unions, early identity barriers and manual preferred defaults',{timeout:30000},async t=>{
  const {id,request}=await station(t);let s=(await request('/receive/selection')).body;
  const normal={v:1,profile_id:id,boot_id:s.boot_id,command_id:randomUUID(),action:'band',profile_revision:0,generation:s.generation,operating_revision:s.operating_revision,band:'40m'};
  const cases=[
    [{...normal,unexpected:true},400,'invalid_request'],
    [JSON.stringify(normal).replace('"band":"40m"','"band":"40m","band":"20m"'),400,'invalid_request'],
    [{...normal,action:'mode',mode:'ft4'},400,'invalid_request'],
    [{...normal,band:'2m'},400,'invalid_request'],
    [{...normal,operating_revision:9007199254740992},400,'invalid_request'],
    [{...normal,profile_id:randomUUID()},403,'wrong_profile'],
    [{...normal,boot_id:randomUUID()},409,'state_conflict'],
    [{...normal,profile_revision:1},409,'state_conflict'],
    [JSON.stringify({}).padEnd(1024,' '),400,'invalid_request'],
    [JSON.stringify({}).padEnd(1025,' '),413,'request_too_large']
  ];
  for(const [body,status,code]of cases){const r=await request('/receive/select','POST',body);assert.equal(r.status,status,r.text);assert.deepEqual(r.body,{error:{code,field:null}});}
  assert.equal((await request('/receive/selection?unexpected=1')).status,400);
  assert.equal((await request('/receive/selection','GET',undefined,{Cookie:''})).status,401);
  assert.equal((await request('/receive/select','POST',normal,{Origin:'https://foreign.example'})).status,403);
  assert.equal((await request('/receive/select','POST',normal,{'Content-Type':'text/plain'})).status,415);
  assert.equal((await request('/receive/selection')).body.operating_revision,s.operating_revision,'every refusal precedes admission');
  const admitted=await request('/receive/select','POST',normal);assert.equal(admitted.status,202);
  async function terminal(){const deadline=Date.now()+3000;let current;do{current=(await request('/receive/selection')).body;if(current.operation.result!=='pending')return current;await new Promise(r=>setTimeout(r,10));}while(Date.now()<deadline);assert.fail('selection did not become terminal');}
  s=await terminal();assert.equal(s.selection.nominal_hz,7074000);assert.equal(s.selection.origin,'manual');assert.equal(s.radio.observations.frequency.value,null);assert.equal(s.operation.error,'audio_unconfigured');assert.equal(s.receive.job_id,null);
  const ft4=await request('/receive/select','POST',{...normal,command_id:randomUUID(),action:'mode',mode:'ft4',band:undefined,operating_revision:s.operating_revision,generation:s.generation});assert.equal(ft4.status,202);
  s=await terminal();assert.equal(s.selection.nominal_hz,7047500);assert.equal(s.selection.mode,'ft4');assert.equal(s.operation.error,'audio_unconfigured');
  const absent=await request('/receive/select','POST',{...normal,command_id:randomUUID(),band:'160m',operating_revision:s.operating_revision,generation:s.generation});assert.equal(absent.status,409);assert.equal(absent.body.error.code,'selection_unavailable');
  const control={v:1,profile_id:id,boot_id:s.boot_id,connection_generation:0,operation:'read_mode',parameters:{}};
  assert.equal((await request('/radio/operation','POST',control)).body.error.code,'radio_unavailable');
  for(const parameters of [{unexpected:true},{mode:'USB',filter:1,unexpected:true}])assert.equal((await request('/radio/operation','POST',{...control,parameters})).status,400);
  const duplicate=JSON.stringify({...control,operation:'set_frequency',parameters:{frequency_hz:7074000}}).replace('"frequency_hz":7074000','"frequency_hz":7074000,"frequency_hz":14074000');assert.equal((await request('/radio/operation','POST',duplicate)).status,400,'nested duplicate parameters must not disappear');
  // CL-022-03/04: deprecated manual lifecycle routes validate, then refuse with zero CAT I/O.
  for(const verified of [false,true]){const manual=await request('/radio/connect','POST',{v:1,profile_id:id,boot_id:s.boot_id,profile_revision:0,receive_only_verified:verified});assert.equal(manual.status,409);assert.equal(manual.body.error.code,'automatic_lifecycle');}
  const manualClose=await request('/radio/disconnect','POST',{v:1,profile_id:id,boot_id:s.boot_id,connection_generation:0});assert.equal(manualClose.status,409);assert.equal(manualClose.body.error.code,'automatic_lifecycle');
});

// selection.state during a held POST (another client's
// revision, then the command's own) does not take away the barrier of its unknown outcome.
test('an event during a pending command keeps the unknown outcome barrier',{timeout:60000},async t=>{
  const {origin,request,token}=await station(t);const {chromium}=require('playwright');
  const browser=await chromium.launch();t.after(()=>browser.close());
  const page=await (await browser.newContext({ignoreHTTPSErrors:true,viewport:{width:1440,height:900}})).newPage();
  await loginPage(page,origin,token);await page.locator('#operating-band:enabled').waitFor();
  await page.selectOption('#operating-band','40m');await page.waitForFunction(()=>operatingState.operation?.error==='audio_unconfigured');
  await page.locator('#operating-mode:enabled').waitFor();
  const settled=()=>page.waitForFunction(()=>!mutationPending&&!operatingReadPending&&!operatingReadAgain);
  const reads=[];page.on('request',r=>{if(new URL(r.url()).pathname==='/receive/selection')reads.push(performance.now());});
  const held=async mode=>{let release,entered;const gate=new Promise(r=>release=r),reached=new Promise(r=>entered=r);t.after(()=>release());return {gate,release,entered,reached,mode};};
  // Another client's revision while the POST is held; the POST never reaches the station.
  const first=await held('ft4');
  await page.route('**/receive/select',async route=>{await first.entered();await first.gate;await route.abort('failed');},{times:1});
  await page.selectOption('#operating-mode','ft4');await first.reached;
  const s=(await request('/receive/selection')).body;
  const other=await request('/receive/select','POST',{v:1,profile_id:s.profile_id,boot_id:s.boot_id,command_id:require('node:crypto').randomUUID(),action:'band',profile_revision:s.profile_revision,generation:s.generation,operating_revision:s.operating_revision,band:'20m'});
  assert.equal(other.status,202,JSON.stringify(other.body));
  await page.waitForFunction(revision=>operatingState.operating_revision>revision,s.operating_revision,{timeout:5000});
  let before=reads.length;first.release();await page.waitForFunction(n=>operatingFailure===''&&!operatingUnknown&&!mutationPending,before,{timeout:15000}).catch(async e=>{throw new Error(`stuck: ${await page.evaluate(()=>JSON.stringify({operatingFailure,operatingUnknown,operatingIntent}))}; ${e.message}`);});await settled();
  assert.ok(reads.length>before,'a reconciling read resolved the unknown outcome');
  // The command's own event arrives while its reply is held, and the reply is lost.
  await page.locator('#operating-band:enabled').waitFor();
  const second=await held('ft8');
  await page.route('**/receive/select',async route=>{await route.fetch();await second.entered();await second.gate;await route.abort('failed');},{times:1});
  await page.selectOption('#operating-mode','ft8');await second.reached;
  await page.waitForFunction(()=>operatingState.selection.mode==='ft8'||operatingState.operation?.requested?.mode==='ft8',null,{timeout:5000});
  before=reads.length;second.release();await page.waitForFunction(()=>operatingFailure===''&&!operatingUnknown&&!mutationPending,null,{timeout:15000}).catch(async e=>{throw new Error(`stuck: ${await page.evaluate(()=>JSON.stringify({operatingFailure,operatingUnknown,operatingIntent}))}; ${e.message}`);});await settled();
  assert.ok(reads.length>before,'a reconciling read resolved the unknown outcome');
});

// Interception only
// delays a mutation body; all successful replies/state originate in the real server.
// Proves: TC-009-005
test('browser preferred selection and Stop fence a genuinely delayed POST',{timeout:45000},async t=>{
  const {origin,request,token}=await station(t);const {chromium}=require('playwright');
  const browser=await chromium.launch();t.after(()=>browser.close());
  const context=await browser.newContext({ignoreHTTPSErrors:true,viewport:{width:1440,height:900}}),page=await context.newPage();
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await loginPage(page,origin,token);await page.locator('#operating-band:enabled').waitFor();
  // Selection diagnostics and the explicit receive control are in Settings > Expert; the
  // drawer leaves the top-bar band and mode selects reachable.
  await page.locator('#open-server-settings').click();await page.locator('#tab-expert').click();
  await page.selectOption('#operating-band','40m');await page.locator('#operating-selection-status').filter({hasText:'audio_unconfigured'}).waitFor();
  await page.locator('#exception-chips [data-chip=selection]').filter({hasText:'audio_unconfigured'}).waitFor();
  assert.match(await page.locator('#operating-radio').textContent(),/Nominal 7\.074000 MHz.*manual, actual rig unconfirmed/);
  // A refused band change leaves the control on the station's band.
  await page.route('**/receive/select',route=>route.fulfill({status:409,contentType:'application/json',body:JSON.stringify({error:{code:'busy',field:null}})}),{times:1});
  await page.selectOption('#operating-band','20m');await page.locator('#operating-selection-status').filter({hasText:'Selection refused · busy'}).waitFor();
  await page.waitForFunction(()=>document.querySelector('#operating-band').value==='40m'&&!mutationPending);
  await page.selectOption('#operating-mode','ft4');await page.waitForFunction(()=>document.querySelector('#op-dial').value==='7.047500');
  await page.locator('#operating-mode:enabled').waitFor();
  const before=(await request('/receive/selection')).body;
  let release,held;const gate=new Promise(resolve=>release=resolve),captured=new Promise(resolve=>held=resolve);const delayed=[];
  t.after(()=>release());
  page.on('response',response=>{if(response.url().endsWith('/receive/select'))delayed.push(response.status());});
  await page.route('**/receive/select',async route=>{const body=route.request().postDataJSON();if(body.action==='mode'&&body.mode==='ft8'){held();await gate;}await route.continue();});
  await page.selectOption('#operating-mode','ft8');await captured;
  await page.locator('#receive-toggle:enabled').filter({hasText:'Cancel band/mode change'}).click();
  await page.waitForFunction(async()=>{const s=await(await fetch('/receive/selection')).json();return s.cancellation?.result==='fenced';});
  const fenced=(await request('/receive/selection')).body;assert.equal(fenced.operation.command_id,before.operation.command_id);assert.equal(fenced.selection.mode,'ft4');assert.equal(fenced.operating_revision,before.operating_revision+1);
  const refused=page.waitForResponse(response=>response.url().endsWith('/receive/select')&&response.status()===409);release();await refused;await page.waitForFunction(()=>!document.querySelector('#operating-mode').disabled);
  assert.ok(delayed.includes(409),'the delayed original POST is refused by the real server');
  assert.equal((await request('/receive/selection')).body.selection.mode,'ft4');
  for(const width of [360,1440]){await page.setViewportSize({width,height:900});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);}
  await fs.mkdir('test-results/radio-selection',{recursive:true});await page.screenshot({path:'test-results/radio-selection/manual-360.png',fullPage:true});
  await page.setViewportSize({width:1440,height:900});await page.screenshot({path:'test-results/radio-selection/manual-desktop.png',fullPage:true});
  assert.deepEqual(errors,[]);
});

// A status of the socket reads no receive snapshot while receive.state
// holds it; the socket's first status, a changed saved profile and a failed read do, one each.
// Proves: TC-007-005
test('a status on the same socket reads no receive snapshot unless the state is in doubt',{timeout:30000},async t=>{
  const {origin,token}=await station(t),{chromium}=require('playwright');const browser=await chromium.launch();t.after(()=>browser.close());
  const context=await browser.newContext({ignoreHTTPSErrors:true}),page=await context.newPage();
  await loginPage(page,origin,token);await page.locator('#operating-band:enabled').waitFor();await page.waitForFunction(()=>!livePending&&!!live);await page.waitForTimeout(200);
  await page.evaluate(()=>{window.__readyReads=[];addEventListener('station-ready',event=>window.__readyReads.push({sameSocket:event.detail===socket,pendingId,profile:profileData.profile_id,boot:profileData.boot_id,revision:profileData.revision}));});
  const reads=[];page.on('request',request=>{if(new URL(request.url()).pathname==='/receive')reads.push({method:request.method(),at:Date.now()});});
  const prior=await page.locator('#updated').textContent();await refreshStatus(page);await page.waitForFunction(value=>document.querySelector('#updated').textContent!==value,prior);await page.waitForFunction(()=>window.__readyReads.length>=1);await page.waitForTimeout(250);
  const ready=await page.evaluate(()=>window.__readyReads);const evidence={reads,ready};await fs.mkdir('test-results/radio-selection',{recursive:true});await fs.writeFile('test-results/radio-selection/receive-ready.json',JSON.stringify(evidence,null,2));
  assert.equal(ready.length,1,'a status refresh on the socket reads no profile: one readiness notification');
  assert.equal(reads.length,0,'a status of the socket needs no receive snapshot');
  await page.evaluate(()=>{dispatchEvent(new CustomEvent('station-ready',{detail:socket}));dispatchEvent(new CustomEvent('station-ready',{detail:socket}));});await page.waitForTimeout(100);assert.equal(reads.length,0,'the same readiness does not read');
  const keys=await page.evaluate(()=>{
    const p={profile_id:'00000000-0000-4000-8000-000000000001',boot_id:'00000000-0000-4000-8000-000000000002',revision:0};
    return {base:receiveReadyKey(p),profile:receiveReadyKey({...p,profile_id:'00000000-0000-4000-8000-000000000003'}),boot:receiveReadyKey({...p,boot_id:'00000000-0000-4000-8000-000000000003'}),revision:receiveReadyKey({...p,revision:1}),invalid:[receiveReadyKey(null),receiveReadyKey({...p,boot_id:null}),receiveReadyKey({...p,revision:-1})],staleAdmitted:receiveReady({})};
  });
  assert.equal(new Set([keys.base,keys.profile,keys.boot,keys.revision]).size,4,'every independently validated context field changes admission identity');assert.deepEqual(keys.invalid,[null,null,null]);assert.equal(keys.staleAdmitted,false);
  // A changed saved profile reads once, also while a read is pending: one follow-up, never a parallel request.
  let release,entered;const gate=new Promise(resolve=>release=resolve),captured=new Promise(resolve=>entered=resolve);t.after(()=>release());
  let held=false;await page.route('**/receive',async route=>{if(!held){held=true;entered();await gate;}await route.continue();});
  const changed=()=>page.evaluate(()=>{profileData={...profileData,revision:profileData.revision+1};dispatchEvent(new CustomEvent('station-ready',{detail:socket}));});
  await changed();await captured;
  await changed();await page.waitForTimeout(100);
  assert.equal(reads.length,1,'a changed revision while pending queues one follow-up, not another parallel request');release();
  await page.waitForFunction(()=>!livePending);await page.waitForTimeout(100);assert.equal(reads.length,2,'the single legitimate follow-up executes');
  await page.unroute('**/receive');
  // No valid context bypasses the check instead of becoming a shared key.
  await page.evaluate(()=>{const held=profileData;profileData=null;receiveReady(socket);profileData=held;});
  await page.waitForFunction(()=>!livePending);await page.waitForTimeout(100);assert.equal(reads.length,3,'no valid context reads rather than sharing a key');
  await page.evaluate(()=>dispatchEvent(new CustomEvent('station-ready',{detail:socket})));await page.waitForTimeout(100);assert.equal(reads.length,3,'invalid context did not poison the prior admitted valid context');
  // A failed read: the next status reads again, the one after it no more.
  await page.route('**/receive',route=>route.abort(),{times:1});
  await page.evaluate(()=>receiveSync());await page.waitForFunction(()=>liveFailed);
  const failed=reads.length;await refreshStatus(page);await page.waitForFunction(()=>!liveFailed&&!livePending);assert.equal(reads.length,failed+1,'the next status after a failed read reads once');
  await refreshStatus(page);await page.waitForTimeout(250);assert.equal(reads.length,failed+1,'then none again');
});

// Actual TLS server/browser. COM250 is an
// absent exact endpoint (read-only name resolution fails; no UART is opened), so the
// station reports a truthful retry reason and never a fresh frequency.
// Proves: TC-022-009, TC-227-001
test('browser confirms receive-only setup once, has no Connect CAT buttons and shows retry reason',{timeout:60000},async t=>{
  const {origin,token,request}=await station(t,{mode:'cat',endpoint:'COM250',ptt:'disabled'}),{chromium}=require('playwright');
  const browser=await chromium.launch();t.after(()=>browser.close());
  const context=await browser.newContext({ignoreHTTPSErrors:true,viewport:{width:1440,height:900}}),page=await context.newPage();
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  const manual=[];page.on('request',r=>{if(/\/radio\/(connect|disconnect)$/.test(new URL(r.url()).pathname))manual.push(r.url());});
  await loginPage(page,origin,token);
  assert.equal(await page.locator('#radio-connect, #radio-disconnect, #radio-receive-only').count(),0,'normal UI has no Connect/Disconnect CAT controls');
  // An unconfirmed receive-only setup is an exception chip that opens Settings > Radio.
  await page.locator('#exception-chips [data-chip=cat]').filter({hasText:'CAT setup not confirmed'}).click({timeout:20000});
  await page.locator('#cat-status[data-condition="commissioningRequired"]').waitFor({timeout:20000});
  const button=page.locator('#cat-confirm-button');
  await button.waitFor({state:'visible'});assert.equal(await button.textContent(),'Confirm receive-only setup');
  assert.equal(await button.isDisabled(),true,'explicit acknowledgement is required');
  assert.match(await page.locator('#cat-confirm-summary').textContent(),/endpoint COM250 · model Icom IC-7300 \(CI-V\) · PTT disabled · setup revision 1/);
  const before=(await request('/receive/selection')).body;assert.equal(before.radio.connection_generation,0,'no CAT attempt before confirmation');
  await page.locator('#cat-confirm-ack').check();await button.click();
  await page.locator('#cat-confirm-result').filter({hasText:'Receive-only setup confirmed'}).waitFor();
  await page.locator('#cat-confirm').waitFor({state:'hidden',timeout:20000});
  await page.locator('#cat-status[data-condition="retryWaiting"]').waitFor({timeout:30000});
  assert.match(await page.locator('#cat-status').textContent(),/^CAT unavailable · [a-z_]+ · automatic retry in [1-8] s$/);
  // WstxSettings::RadioLine: a serial port held by another program
  // (Windows access denied) is named in the status and its exception chip.
  const held=await page.evaluate(()=>{catStatus={...catStatus,error:'port_in_use'};catShow();return document.querySelector('#cat-status').textContent;});
  assert.match(held,/^CAT unavailable · COM250 in use by another program · automatic retry in [0-8] s$/);
  // The URL endpoint form names its port, not digits inside the icom7300 scheme.
  const url=await page.evaluate(()=>{const c=profileData.settings.control,old=c.endpoint;c.endpoint='icom7300://COM3?baud=9600&radio=94&controller=E0';catShow();const text=document.querySelector('#cat-status').textContent;c.endpoint=old;catShow();return text;});
  assert.match(url,/^CAT unavailable · COM3 in use by another program · automatic retry in [0-8] s$/);
  const s=(await request('/receive/selection')).body;assert.ok(s.radio.connection_generation>=1,'the station attempted automatically');
  assert.equal(s.radio.observations.frequency.confirmed,false);
  assert.equal(await page.locator('#op-dial').getAttribute('data-fresh'),'false');
  assert.match(await page.locator('#operating-radio').textContent(),/Actual rig frequency unknown/);
  assert.deepEqual(manual,[],'the browser never calls the deprecated manual lifecycle routes');
  assert.deepEqual(errors,[]);
});
}else{
  assert.equal(process.env.WSTX_SELECTION_FIXTURE,'1','unknown fixture mode is not a skipped positive');
  liveSelectionFixture();
}

// The status refreshes itself; the explicit Refresh status is in Settings > Expert.
async function refreshStatus(page){const open=await page.locator('#settings-drawer').isVisible();if(!open)await page.locator('#open-server-settings').click();await page.locator('#refresh').click();if(!open)await page.locator('#settings-drawer .return-operate').click();}

function liveSelectionFixture(){
  // Proves: TC-007-005
  test('actual native/CAT/TLS two-browser Thin and Off selection workload',{timeout:510000},async t=>{
    const {performance}=require('node:perf_hooks'),{chromium}=require('playwright');
    const oracle=JSON.parse(process.env.WSTX_SELECTION_EXPECTED),token=process.env.WSTX_SELECTION_TOKEN;
    assert.ok(oracle.ft8&&oracle.ft4&&token,'both independent mode oracles and authentication are mandatory');
    // An unshaped TLS connection; the link budget is judged from the link byte log (TC-080-001).
    const port=await browserPort();
    process.stdout.write(`WSTX_SELECTION_PORT ${port}\n`);
    await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(new Error('real TLS fixture READY deadline')),15000);process.stdin.once('data',data=>{clearTimeout(timeout);if(data.toString().trim()==='READY')resolve();else reject(new Error('invalid real TLS fixture handshake'));});});
    const origin=`https://localhost:${port}`,browser=await chromium.launch();
    const pages=[],contexts=[],observations=[],errors=[],identities=[],report={startedUtc:new Date().toISOString(),clients:2,model:'actual TLS streams, unshaped',phases:{}};
    const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
    const waitUntil=async deadline=>{while(performance.now()<deadline)await sleep(Math.max(1,Math.ceil(deadline-performance.now())));};
    const save=async()=>{await fs.mkdir('test-results/radio-selection',{recursive:true});await fs.writeFile('test-results/radio-selection/live-link.json',JSON.stringify(report,null,2));};
    let activePhase=null;
    // The Thin and Off windows, and the one under way (from its profile switch to its end).
    const windows=[];let underWay=null;
    // A failed run keeps its own copy: the next run (a gate rerun) overwrites live-link.json.
    // A Thin or Off phase that failed at any point prints its evidence, from what Node holds;
    // its window ends at the failure, read before the browser close ends the sockets.
    failureHooks(hook=>t.after(hook),{now:()=>performance.now(),underWay:()=>underWay,close:()=>browser.close(),evidence:async()=>{
      if(!activePhase&&!underWay)return;
      if(underWay){const now=performance.now();report.failureEvidence=failureEvidence({timeOrigin:performance.timeOrigin,now,windows,browsers:observations.map(seen=>({sockets:seen.sockets,staleRecords:seen.staleRecords,frames:seen.wireFrames}))});console.log(report.failureEvidence.join('\n'));}
      if(activePhase){report.phases[activePhase].state='failed';report.phases[activePhase].endedUtc=new Date().toISOString();}
      await save();await fs.copyFile('test-results/radio-selection/live-link.json',`test-results/radio-selection/live-link-failed-${Date.now()}.json`);
    }});
    for(let i=0;i<2;i++){
      const context=await browser.newContext({ignoreHTTPSErrors:true,viewport:{width:1440,height:900}});contexts.push(context);
      const page=await context.newPage();pages.push(page);
      const seen={selectionEvents:[],reads:[],profileBodies:[],receive:null,results:[],frames:[],active:0,maxActive:0,gestures:[],failures:[],http:[],sockets:[],transfers:[],wireFrames:[],subscriptionRequests:[],subscriptionAcks:[],navigations:[],abandonedBodies:[],staleRecords:[]};observations.push(seen);
      // Each station-stale reaches Node as it happens, so it survives a failure before the cadence check.
      await page.exposeFunction('__wstxStaleRecord',record=>{seen.staleRecords.push(record);});
      page.on('framenavigated',frame=>{if(frame===page.mainFrame())seen.navigations.push({url:frame.url(),at:performance.now()});});
      const cdp=await context.newCDPSession(page),transfers=new Map();await cdp.send('Network.enable');
      cdp.on('Network.requestWillBeSent',event=>{const transfer={id:event.requestId,route:new URL(event.request.url).pathname,method:event.request.method,started:performance.now(),browserStarted:event.timestamp,wallStarted:event.wallTime*1000,wallEnded:null,ended:null,encodedBytes:null,initiator:event.initiator};transfers.set(event.requestId,transfer);seen.transfers.push(transfer);});
      cdp.on('Network.loadingFinished',event=>{const transfer=transfers.get(event.requestId);if(transfer&&transfer.ended===null){transfer.ended=performance.now();transfer.browserEnded=event.timestamp;transfer.wallEnded=transfer.wallStarted+(event.timestamp-transfer.browserStarted)*1000;transfer.encodedBytes=event.encodedDataLength;}});
      cdp.on('Network.loadingFailed',event=>{const transfer=transfers.get(event.requestId);if(transfer&&transfer.ended===null){transfer.ended=performance.now();transfer.browserEnded=event.timestamp;transfer.failure=event.errorText;}});
      page.on('pageerror',error=>errors.push(error.message));
      const reads=new Map();
      page.on('request',request=>{
        if(new URL(request.url()).pathname==='/receive/selection'){
          const r={started:performance.now(),ended:null,body:null};seen.reads.push(r);reads.set(request,r);seen.active++;seen.maxActive=Math.max(seen.maxActive,seen.active);
        }
      });
      page.on('requestfailed',request=>{seen.failures.push({route:new URL(request.url()).pathname,error:request.failure()?.errorText,at:performance.now()});const r=reads.get(request);if(r&&r.ended===null){r.ended=performance.now();r.failed=true;seen.active--;}});
      page.on('response',async response=>{
        const route=new URL(response.url()).pathname;
        if(route==='/recording.js'){seen.cadenceSource=await response.body();return;}
        // On the starved cold link Chromium can report a /profile response whose body it does not
        // hold (the request then ends net::ERR_ABORTED). Keep the entry without a body, with how
        // the request ended, as evidence; the qualified segment below still requires every body.
        if(route==='/profile'&&response.status()===200){const entry={at:performance.now(),body:null};try{entry.body=await response.json();}catch(error){entry.bodyError=error.message;entry.finished=await response.finished().then(e=>e?String(e):'finished',e=>String(e));entry.failure=response.request().failure()?.errorText??null;}seen.profileBodies.push(entry);}
        const entry={route,status:response.status(),at:performance.now(),bodyBytes:null,contentEncoding:response.headers()['content-encoding']??null};seen.http.push(entry);
        if(!['/receive/selection','/receive','/receive/results'].includes(route)){if((response.headers()['content-type']||'').includes('application/json')){try{entry.bodyBytes=(await response.body()).length;}catch(error){entry.bodyError=error.message;}}return;}
        await observeReceiveResponse(response,entry,seen,reads,errors);
      });
      page.on('websocket',socket=>{const session={index:seen.sockets.length,opened:performance.now(),closed:null,lastFrameAt:null,messages:[],receivedBytes:0};seen.sockets.push(session);socket.on('close',()=>session.closed=performance.now());socket.on('socketerror',error=>session.error=String(error));socket.on('framesent',event=>{try{const m=JSON.parse(event.payload);if(['spectrum.off','spectrum.thin','spectrum.detail'].includes(m.type)&&Number.isSafeInteger(m.id))seen.subscriptionRequests.push({socket:session.index,at:performance.now(),id:m.id,profile:m.type.slice(9)});}catch{}});socket.on('framereceived',event=>{session.lastFrameAt=performance.now();session.receivedBytes+=Buffer.byteLength(event.payload);try{const m=JSON.parse(event.payload),at=performance.now();seen.wireFrames.push({socket:session.index,at,type:m.type,bytes:Buffer.byteLength(event.payload)});if(m.type==='selection.state')seen.selectionEvents.push({at,socket:session.index,bytes:Buffer.byteLength(event.payload),data:m.data});if(m.type==='spectrum.subscription')seen.subscriptionAcks.push({socket:session.index,at,id:m.id,profile:m.data?.profile});if(m.type==='spectrum.frame')seen.frames.push({socket:session.index,at,data:m.data});else session.messages.push({at,type:m.type,id:m.id,radio:m.data?.radio});}catch{}});});
    }
    const coldStarted=performance.now(),coldDeadline=coldStarted+230000;
    const coldRemaining=()=>{const remaining=Math.floor(coldDeadline-performance.now());assert.ok(remaining>0,'shared 230s Cold phase deadline');return remaining;};
    report.cold={state:'running',startedUtc:new Date().toISOString(),startedMonotonic:coldStarted,deadlineMonotonic:coldDeadline};await save();
    try{await Promise.all(pages.map(async(page,index)=>{
      const seen=observations[index];seen.navigationStarted=performance.now();await page.goto(origin,{timeout:coldRemaining()});seen.navigationCompleted=performance.now();
      // Selected HTTPS profile: each browser enrolls through the real token form.
      // The link has one FIFO bottleneck per direction: while the other browser's cold assets are
      // queued, this browser's 10 s authorization attempts can time out. The client retries a
      // timed-out step itself; only if every attempt fails ("Could not authenticate")
      // does the operator press Connect securely again. Each such press is kept as evidence.
      seen.loginRetries=[];
      for(;;){
        await page.locator('#token').fill(token,{timeout:coldRemaining()});await page.locator('#login button').click({timeout:coldRemaining()});
        const outcome=await Promise.race([page.locator('#connection[data-state=connected]').waitFor({timeout:coldRemaining()}).then(()=>'connected'),
          page.locator('#login-error').filter({hasText:'Could not authenticate'}).waitFor({timeout:coldRemaining()}).then(()=>'refused',()=>new Promise(()=>{}))]);
        if(outcome==='connected')break;
        seen.loginRetries.push(performance.now());assert.ok(seen.loginRetries.length<=5,'at most five operator login retries');
        // The page clears the message only on success; clear it so the next attempt's outcome is its own.
        await page.locator('#login-error').evaluate(e=>{e.textContent='';});
      }
      seen.connectedObserved=performance.now();
      await page.locator('#operating-band:enabled').waitFor({timeout:coldRemaining()});seen.operatingObserved=performance.now();
      await page.locator('#open-server-settings').click({timeout:coldRemaining()});await page.selectOption('#display-profile','thin',{timeout:coldRemaining()});await page.locator('#tab-expert').click({timeout:coldRemaining()});
      assert.equal(await page.locator('#display-profile').inputValue({timeout:coldRemaining()}),'thin');seen.thinConfigured=performance.now();
      // The cold load ends with the log and contact clients, loaded after the first snapshots.
      await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:coldRemaining()});seen.clientsLoaded=performance.now();coldRemaining();
    }));}
    catch(error){
      const state=await Promise.all(pages.map(async(page,i)=>{const state=await page.evaluate(()=>({connection:document.querySelector('#connection')?.textContent,connectionState:document.querySelector('#connection')?.dataset.state,loginHidden:document.querySelector('#login')?.hidden,profileInitialized:typeof profileData==='object',body:document.body.innerText.slice(0,3500)})).catch(e=>({evaluationError:e.message}));await page.screenshot({path:`test-results/radio-selection/cold-failure-${i}.png`,fullPage:true}).catch(()=>{});return {...state,network:observations[i]};}));
      report.cold={state:'failed',elapsedMs:performance.now()-coldStarted,error:error.message,errors,diagnostics:state};await save();throw error;
    }
    coldRemaining();
    for(const [index,page]of pages.entries()){
      const authoritative=observations[index].profileBodies.filter(p=>p.body).at(-1)?.body;assert.ok(authoritative,'authoritative setup profile observed');
      assert.deepEqual(observations[index].navigations.map(n=>n.url),[origin+'/'],'one main-frame navigation (the goto): the client never navigates or reloads');
      // The qualified segment starts once the page has no Cold-load selection read in flight. On the
      // starved cold link both browsers' cold loads can overlap (e.g. after the client retried a
      // timed-out login step itself), so a read can still be queued behind contact.js when the
      // clients arrive; its page timeout would then end just inside the segment. The baseline still
      // refuses every abort that ends after it (supersededColdRead).
      // It also starts only on an established status socket: on the starved link a page can
      // still be reconnecting after a Cold-load socket closed (its last socket closed and the
      // next not yet created), and a baseline taken then counts the reconnect as a new socket
      // inside the segment. The page's current socket must be open, connected
      // and the one the selection reads were synchronized on.
      await page.waitForFunction(()=>connection.dataset.state==='connected'&&socket?.readyState===WebSocket.OPEN&&operatingSocket===socket&&!operatingReadPending&&!operatingReadAgain,null,{timeout:coldRemaining()});
      const socketBaseline={index:observations[index].sockets.length-1,count:observations[index].sockets.length,at:performance.now(),end:null};
      observations[index].acceptance={socketBaseline,expected:{profile_id:authoritative.profile_id,boot_id:authoritative.boot_id,profile_revision:authoritative.revision},events:await page.evaluate(()=>{
        const initialSocket=socket,events=[];
        const snapshot=action=>{events.push({at:performance.timeOrigin+performance.now(),action,epoch:operatingEpoch,connected:connection.dataset.state==='connected',sameSocket:socket===initialSocket&&socket.readyState===WebSocket.OPEN,profile_id:profileData.profile_id,boot_id:profileData.boot_id,profile_revision:profileData.revision,acceptedSequence:operatingState?.snapshot_sequence??null});};
        snapshot(false);
        addEventListener('station-ready',()=>snapshot(false));addEventListener('station-stale',()=>snapshot(false));
        // The stale's path, the page's silence, a pending deferred download, the ended socket's state and the authorization state.
        addEventListener('station-stale',event=>{const at=Date.now();window.__wstxStaleRecord({at,path:event.detail?.path??null,silenceMs:at-lastMessage,deferredPending:deferredDownloads>0,socketState:socket?.readyState??null,authorization:authorization?.snapshot().state??null});});
        // Bubble after the source handler's synchronous epoch increment. This
        // observes only the two existing selections; it does not wrap fetch.
        document.addEventListener('change',event=>{if(['operating-mode','operating-band'].includes(event.target.id))snapshot(true);});
        window.__cadenceAcceptanceCheckpoint=()=>{snapshot(false);return events;};return events;
      })};
    }
    report.cold={state:'passed',elapsedMs:performance.now()-coldStarted,endedUtc:new Date().toISOString(),pages:observations.map(seen=>({navigations:seen.navigations,abortedProfileBodies:seen.profileBodies.filter(p=>!p.body).map(p=>({at:p.at,error:p.bodyError,finished:p.finished,failure:p.failure})),navigationStarted:seen.navigationStarted,navigationCompleted:seen.navigationCompleted,loginRetries:seen.loginRetries,connectedObserved:seen.connectedObserved,operatingObserved:seen.operatingObserved,thinConfigured:seen.thinConfigured,failures:seen.failures,http:seen.http,sockets:seen.sockets})),errors:[...errors]};await save();
    const freshRead=async index=>{
      const seen=observations[index],before=seen.reads.length;seen.gestures.push(performance.now());await pages[index].locator('#operating-refresh:enabled').click();
      const deadline=performance.now()+12000;while(!seen.reads.slice(before).some(r=>r.ended!==null&&r.body?.v===1)){assert.ok(performance.now()<deadline,'actual explicit operating read completed');await sleep(20);}
      // A click during a read in flight is coalesced into a follow-up read (operatingReadAgain),
      // and Node may see that read only after `before`. The operator acts once the page has no
      // selection read pending, so the next action cannot make the page discard its own read.
      await pages[index].waitForFunction(()=>!operatingReadPending&&!operatingReadAgain,null,{timeout:Math.max(1,Math.ceil(deadline-performance.now()))});
    };
    async function command(action,value,mode,hz){
      await freshRead(0);
      const oldJob=observations[0].receive?.job?.id;
      await Promise.all(pages.map(page=>page.locator('#operating-refresh:enabled').waitFor()));
      const admitted=pages[0].waitForResponse(r=>new URL(r.url()).pathname==='/receive/select'&&r.request().method()==='POST',{timeout:15000});
      const sent=pages[0].waitForRequest(r=>new URL(r.url()).pathname==='/receive/select'&&r.method()==='POST');
      observations[0].gestures.push(performance.now());await pages[0].selectOption(action==='mode'?'#operating-mode':'#operating-band',value);
      await sent;const sentAt=performance.now();
      // The second operator explicitly observes the in-flight command. This is
      // one real user read, not a fast polling loop or an invented pending reply.
      const otherRead=(async()=>{await waitUntil(sentAt+400);await freshRead(1);})();
      const response=await admitted,ack=await response.json();assert.equal(response.status(),202,JSON.stringify(ack));
      const started=performance.now();await otherRead;
      const deadline=started+35000;
      let identity;
      while(performance.now()<deadline){
        const current=observations[0].receive;
        if(current?.job?.id&&current.job.id!==oldJob&&current.job.mode===mode&&current.source?.id){
          const row=pages[0].locator('#band-activity tbody tr[data-result-id]').filter({hasText:'CQ K1ABC FN42'});
          if(await row.count()&&((await row.first().getAttribute('data-result-id'))??'').includes('/'+current.job.id+'/')){identity={source:current.source.id,job:current.job.id,generation:current.generation,mode,hz,command:ack.command_id};break;}
        }
        await sleep(100);
      }
      assert.ok(identity,`actual ${mode} CQ appears in a fresh receive context`);
      assert.ok(!identities.some(i=>i.source===identity.source||i.job===identity.job),'each admitted operation owns a genuinely fresh job/source');identities.push(identity);
      for(let i=0;i<2;i++){
        const seen=observations[i];
        await pages[i].locator('#band-activity tbody tr[data-result-id]').filter({hasText:'CQ K1ABC FN42'}).first().waitFor({timeout:12000});
        await pages[i].waitForFunction(job=>[...document.querySelectorAll('#band-activity tbody tr[data-result-id]')].some(r=>r.dataset.resultId.includes('/'+job+'/')&&r.textContent.includes('CQ K1ABC FN42')),identity.job,{timeout:15000});
        const records=seen.results.filter(p=>p.job_id===identity.job&&p.source_id===identity.source).flatMap(p=>p.records??[]);
        assert.ok(records.length>0,'actual manager result page supplied the displayed row');
        for(const record of records){assert.equal(record.payload77,oracle[mode].payload77);assert.equal(record.text,'CQ K1ABC FN42');assert.deepEqual(record.fields,oracle[mode].fields);assert.ok(Math.abs(record.frequency_hz-oracle[mode].expected_receive.frequency_hz)<=oracle[mode].expected_receive.frequency_tolerance_hz);}
        // The state this browser holds (selection.state or its own read) retained the command.
        await pages[i].waitForFunction(({command,hz})=>operatingState?.operation?.command_id===command&&operatingState.selection.nominal_hz===hz&&operatingState.radio.observations.frequency.value===hz,{command:ack.command_id,hz},{timeout:15000});
        const last=await pages[i].evaluate(()=>operatingState);assert.equal(last.radio.observations.mode.value.mode,'USB');assert.equal(last.radio.observations.data.value.enabled,true);
      }
      report.contexts=identities;await save();console.log(`Actual ${mode} CQ context ${identities.length}/5 at ${hz}Hz`);
      return ack.command_id;
    }
    await command('band','40m','ft8',7074000);
    async function measure(profile,steps){
      const offProofs=[],phaseWindow={profile,start:null,end:null};windows.push(phaseWindow);underWay=phaseWindow;
      for(const [index,page]of pages.entries()){const after=performance.now();if(!await page.locator('#settings-drawer').isVisible())await page.locator('#open-server-settings').click();await page.selectOption('#display-profile',profile);await page.locator('#tab-expert').click();if(profile==='off'){const deadline=performance.now()+10000;let ack;while(!(ack=correlatedOffAck(observations[index].subscriptionRequests,observations[index].subscriptionAcks,after))){assert.ok(performance.now()<deadline,'actual correlated Off acknowledgement');await sleep(10);}offProofs.push(ack);report.offAcknowledgements=[...offProofs];await save();assertOffAckDeadline(ack);}}
      await sleep(500);const start=performance.now();phaseWindow.start=start;const readStarts=observations.map(o=>o.reads.length),frameStarts=observations.map(o=>o.frames.length),latencies=[];
      activePhase=profile;report.phases[profile]={state:'running',startedUtc:new Date().toISOString()};await save();console.log(`Actual ${profile} workload started`);
      // The window is as long as its gestures need: the two commands, a status refresh of each
      // browser every 5.5 s while they run (at least one), no padding.
      let done=false;
      const status=async()=>{for(let n=1;n===1||!done;n++){await waitUntil(start+n*5500);await Promise.all(pages.map(async page=>{const previous=await page.locator('#updated').textContent(),began=performance.now();await refreshStatus(page);await page.waitForFunction(value=>document.querySelector('#updated').textContent!==value,previous,{timeout:2000});const ms=performance.now()-began;assert.ok(ms<=2000,`actual ${profile} visible status ${ms}ms`);latencies.push(ms);}));}};
      const controls=async()=>{const commands=[];try{for(const step of steps)commands.push(await command(...step));}finally{done=true;}return commands;};
      // Each CAT poll dates the radio facts anew: that alone goes at most every 30 s below Detailed, on the
      // station's clock. Checked during the window: the extra traffic of a broken pacing would otherwise show
      // first as a missed status wait, not as what it is.
      const undated=radio=>JSON.stringify(radio,(key,value)=>key==='query_sequence'||key==='observed_at_ms'?undefined:value);
      const datesOnly=(seen,index)=>{const lastEvent=new Map(),heldRadio=new Map();let count=0;
        for(const e of seen.selectionEvents){const c=e.data.changed,previous=lastEvent.get(e.socket);
          if(Object.keys(c).join()==='radio'&&undated(c.radio)===undated(heldRadio.get(e.socket))&&e.at>=start){count++;assert.ok(e.data.monotonic_ms-previous>=29900,`${profile} browser${index}: new radio dates alone ${e.data.monotonic_ms-previous} ms after the last event`);}
          if(c.radio)heldRadio.set(e.socket,c.radio);lastEvent.set(e.socket,e.data.monotonic_ms);}
        return count;};
      const pacing=async()=>{while(!done){observations.forEach(datesOnly);await sleep(250);}};
      const [,commands]=await Promise.all([status(),controls(),pacing()]);const seconds=(performance.now()-start)/1000;
      const pathCounts=observations.map(seen=>Object.fromEntries([...new Set(seen.http.filter(r=>r.at>=start).map(r=>r.route))].map(route=>[route,seen.http.filter(r=>r.at>=start&&r.route===route).length])));
      report.phases[profile]={state:'checking',seconds,statusMs:latencies,pathCounts,offProofs,networkSelection:observations.map(seen=>selectionNetworkSummary(seen.transfers,start,start+seconds*1000)),httpResponses:observations.map(seen=>seen.http.filter(r=>r.at>=start)),browserTransfers:observations.map(seen=>seen.transfers.filter(r=>r.started>=start||r.ended>=start)),websocketFrames:observations.map(seen=>seen.wireFrames.filter(frame=>frame.at>=start)),selectionReads:observations.map((seen,index)=>seen.reads.slice(readStarts[index]).map(r=>({startedMs:r.started-start,completedMs:r.ended===null?null:r.ended-start,phase:r.body?.operation?.phase??null,command:r.body?.operation?.command_id??null}))),frames:observations.map((seen,index)=>seen.frames.length-frameStarts[index])};await save();
      for(const seen of observations){const replies=seen.http.filter(r=>r.at>=start&&r.status===200&&['/receive/selection','/receive','/receive/results','/profile','/radio','/recording'].includes(r.route));assert.ok(replies.length>0);assert.ok(replies.every(r=>r.contentEncoding==='gzip'),'actual browser negotiated gzip on every eligible response');}
      assert.ok(latencies.length>=2,'each browser refreshed its status in the window');
      for(const [index,page]of pages.entries()){observations[index].acceptance.events=await page.evaluate(()=>window.__cadenceAcceptanceCheckpoint());observations[index].acceptance.socketBaseline.end=performance.now();}
      report.phases[profile].cadenceRaw=observations.map(seen=>({sourceBase64:seen.cadenceSource?.toString('base64'),acceptance:seen.acceptance,profileBodies:seen.profileBodies,reads:seen.reads,transfers:seen.transfers,sockets:seen.sockets.map(({messages,...s})=>({...s,messages:messages.length,lastMessageAt:messages.at(-1)?.at??null}))}));await save();
      const evidence=observations.map(seen=>{
        const evidence={joined:[],errors:[]};
        try{
          const mapping=cadenceSource(seen.cadenceSource);evidence.sourceSha256=mapping.sha256;
          cadenceQualification(seen);
          evidence.joined=cadenceJoin(seen,origin,mapping);
        }catch(error){evidence.errors.push({message:error.message});}
        return evidence;
      });
      report.phases[profile].cadenceEvidence=evidence;await save();
      const polling=observations.map((seen,index)=>{
        const network=selectionNetworkSummary(seen.transfers,start,start+seconds*1000);assert.equal(network.maxActive,1,'one actual CDP network selection read pending per browser');
        const proof=evidence[index];assert.deepEqual(proof.errors,[],'complete validated cadence evidence');
        const reads=proof.joined.filter(r=>r.started>=start&&r.started<start+seconds*1000&&r.body);
        // What this browser saw of each command while pending, from a read or an event (a whole view per socket).
        const held=new Map(),views=seen.selectionEvents.filter(e=>e.at>=start).map(e=>{const view={...held.get(e.socket),...e.data.changed};held.set(e.socket,view);return view;});
        const pending=commands.map(id=>reads.filter(r=>r.body.operation?.command_id===id&&r.body.operation.result==='pending').length+views.filter(v=>v.operation?.command_id===id&&v.operation.result==='pending').length);
        // No timer: reads only come from an operator's gesture, one each (a click during a read follows it).
        const gestures=seen.gestures.filter(at=>at>=start&&at<start+seconds*1000).length;
        assert.ok(reads.length<=gestures,`${profile} browser${index}: ${reads.length} selection reads for ${gestures} gestures`);
        const events=seen.selectionEvents.filter(e=>e.at>=start&&e.at<start+seconds*1000);
        assert.ok(events.every(e=>e.bytes<=2048),`${profile} browser${index}: selection.state over 2048 B`);
        assert.ok(events.length<=Math.ceil(seconds)+1,`${profile} browser${index}: ${events.length} selection.state in ${seconds} s`);
        return {reads,pending,gestures,events:events.length,datesOnly:datesOnly(seen,index),eventBytes:events.reduce((sum,e)=>sum+e.bytes,0),frames:seen.frames.length-frameStarts[index]};
      });
      // A short command may end between two 1 s checks of one browser, not unseen by both.
      for(const n of commands.keys())assert.ok(polling.some(p=>p.pending[n]>=1),`${profile} command${n}: pending seen by neither browser`);
      if(profile==='thin')assert.ok(polling.every(p=>p.frames>0),'real optional live spectrum was present, not an idle body-size exercise');
      if(profile==='off'){assert.equal(offProofs.length,2);for(const [index,ack]of offProofs.entries()){assert.ok(ack.ackAt<=start);assert.deepEqual(optionalAfterOff(observations[index].wireFrames,ack),[],'no optional frame after its correlated Off ACK');assert.equal(polling[index].frames,0,'no optional spectrum during actual Off window');}}
      report.phases[profile]={...report.phases[profile],state:'passed',seconds,statusMs:latencies,polling,commands,endedUtc:new Date().toISOString()};activePhase=null;await save();console.log(`Actual ${profile} workload completed ${seconds.toFixed(3)}s`);
      // The window's bounds on the UTC clock, in every run.
      phaseWindow.end=performance.now();underWay=null;console.log('WSTX_SELECTION_WINDOW '+JSON.stringify(evidenceWindow(performance.timeOrigin,phaseWindow)));
    }
    await measure('thin',[['mode','ft4','ft4',7047500],['band','20m','ft4',14080000]]);
    await measure('off',[['mode','ft8','ft8',14074000],['band','40m','ft8',7074000]]);
    report.abandonedBodies=observations.map(seen=>seen.abandonedBodies);await save();
    for(const [index,seen]of observations.entries())assert.deepEqual(abandonedBodiesNotReRead(seen),[],`browser${index}: every body the page abandoned is read again complete afterwards`);
    assert.equal(identities.length,5);assert.deepEqual(errors,[]);assert.equal(contexts.length,2);assert.equal(Object.values(report.phases).filter(p=>p.state==='passed').length,2);
    await pages[0].setViewportSize({width:1440,height:900});await pages[0].screenshot({path:'test-results/radio-selection/actual-native-cat-desktop.png',fullPage:true});
    await pages[0].setViewportSize({width:360,height:800});assert.equal(await pages[0].evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await pages[0].screenshot({path:'test-results/radio-selection/actual-native-cat-360.png',fullPage:true});
    console.log('WSTX_SELECTION_COMPLETED 2 5 2');
  });
}
