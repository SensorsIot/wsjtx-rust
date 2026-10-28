'use strict';
// Independent oracle: FSD4.7.5/12.8.1. Disposable authenticated TLS station only.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
const net=require('node:net'),https=require('node:https');
const {once}=require('node:events');
const {randomUUID}=require('node:crypto');
const selfsigned=require('selfsigned');
const {server}=require('./support.cjs');

async function station(t){
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'wstx-selection-'));
  t.after(()=>fs.rm(dir,{recursive:true,force:true}));
  const held=net.createServer();held.listen(0,'127.0.0.1');await once(held,'listening');
  const port=held.address().port;await new Promise(resolve=>held.close(resolve));
  const origin=`https://localhost:${port}`,id=randomUUID(),token=randomUUID().replaceAll('-','');
  const cert=await selfsigned.generate([{name:'commonName',value:'localhost'}],{days:1,keySize:2048,extensions:[{name:'subjectAltName',altNames:[{type:2,value:'localhost'}]}]});
  await fs.writeFile(path.join(dir,'cert.pem'),cert.cert);await fs.writeFile(path.join(dir,'key.pem'),cert.private);
  await fs.writeFile(path.join(dir,'profile.json'),JSON.stringify({schema_version:1,profile_id:id,revision:0,display_name:'Selection fixture',callsign:'HB9BLA',locator:'JN47AA',endpoint:{bind:`127.0.0.1:${port}`,origin},connection_type:'standard',audio:{input_device:null,output_device:null},control:{mode:'disabled',endpoint:null,ptt:'disabled'}}));
  const app=await server({WSTX_TLS_CERT:path.join(dir,'cert.pem'),WSTX_TLS_KEY:path.join(dir,'key.pem'),WSTX_TOKEN:token},['--profile',dir]);t.after(()=>app.close());
  let cookie='';
  const request=(route,method='GET',body,extra={})=>new Promise((resolve,reject)=>{
    const req=https.request(origin+route,{method,ca:cert.cert,agent:false,headers:{Origin:origin,...(cookie?{Cookie:cookie}:{}),...(body===undefined?{}:{'Content-Type':'application/json'}),...extra}},res=>{
      let text='';res.on('data',b=>text+=b);res.on('end',()=>resolve({status:res.statusCode,headers:res.headers,text,body:text?JSON.parse(text):null}));
    });req.on('error',reject);if(body!==undefined)req.write(typeof body==='string'?body:JSON.stringify(body));req.end();
  });
  const session=await request('/session','POST',token);assert.equal(session.status,204);cookie=session.headers['set-cookie'][0].split(';')[0];
  return {origin,id,request,cookie};
}

// Proves: CL-008-07; TC-009-005 cases2/5. Parent has no selection route, so this
// fails on actual HTTP404 rather than a build/import error.
if(!process.env.WSTX_SELECTION_FIXTURE){
test('TC-009-005 authenticated TLS selection reports unknown nominal and early refusal',{timeout:30000},async t=>{
  const {id,request}=await station(t);
  const initial=await request('/receive/selection');assert.equal(initial.status,200,'selection route exists');
  const s=initial.body;assert.deepEqual(Object.keys(s).sort(),'v,profile_id,boot_id,profile_revision,generation,operating_revision,snapshot_sequence,monotonic_ms,control,selection,available_bands,operation,cancellation,receive,radio'.split(',').sort());
  assert.equal(s.profile_id,id);assert.equal(s.control,'manual');assert.deepEqual(s.selection,{mode:'ft8',band:null,nominal_hz:null,origin:'unknown',confirmed_command_id:null});
  const command={v:1,profile_id:id,boot_id:s.boot_id,command_id:randomUUID(),action:'mode',profile_revision:0,generation:s.generation,operating_revision:s.operating_revision,mode:'ft4'};
  const refused=await request('/receive/select','POST',command);assert.equal(refused.status,409);assert.deepEqual(refused.body,{error:{code:'select_band_first',field:null}});
  const after=(await request('/receive/selection')).body;assert.equal(after.operating_revision,s.operating_revision);assert.equal(after.operation,null);assert.equal(after.receive.job_id,null);
  const radio=await request('/radio');assert.equal(radio.status,200);assert.equal(radio.body.state,'closed');assert.equal(radio.body.observation,null);
});

// Proves: CL-008-07; TC-009-005 cases5/6. Fixed expectations come from the
// canonical CAS/fence contract, independently of the candidate's state machine.
test('TC-009-005 unseen mutation fencing rejects delayed POST without creating operation',{timeout:30000},async t=>{
  const {id,request}=await station(t);const initial=await request('/receive/selection');assert.equal(initial.status,200);
  const s=initial.body,target=randomUUID(),cancel={v:1,profile_id:id,boot_id:s.boot_id,command_id:randomUUID(),action:'cancel',operating_revision:s.operating_revision,target_command_id:target};
  const ack=await request('/receive/select','POST',cancel);assert.equal(ack.status,202);assert.equal(ack.body.phase,'cancelled');assert.equal(ack.body.operating_revision,s.operating_revision+1);assert.ok(Buffer.byteLength(ack.text)<=384);
  const after=await request('/receive/selection');assert.equal(after.body.operation,null);assert.equal(after.body.cancellation.result,'fenced');assert.ok(Buffer.byteLength(after.text)<=3072);
  const delayed=await request('/receive/select','POST',{v:1,profile_id:id,boot_id:s.boot_id,command_id:target,action:'band',profile_revision:0,generation:s.generation,operating_revision:s.operating_revision,band:'40m'});assert.equal(delayed.status,409);assert.equal(delayed.body.error.code,'state_conflict');
  const duplicate=await request('/receive/select','POST',cancel);assert.equal(duplicate.status,200);assert.deepEqual(duplicate.body,ack.body);
  const invalid=await request('/receive/select','POST',{...cancel,target_command_id:randomUUID()});assert.equal(invalid.status,409);assert.equal(invalid.body.error.code,'state_conflict');
  const changedRevision=await request('/receive/select','POST',{...cancel,operating_revision:ack.body.operating_revision});assert.equal(changedRevision.status,409);assert.equal(changedRevision.body.error.code,'state_conflict');
});

// Proves: CL-008-07; TC-009-005 cases2/5/7. These responses come from the actual
// authenticated router; no serial device or positive response is intercepted.
test('TC-009-005 strict TLS unions, early identity barriers and manual preferred defaults',{timeout:30000},async t=>{
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
  const unverified=await request('/radio/connect','POST',{v:1,profile_id:id,boot_id:s.boot_id,profile_revision:0,receive_only_verified:false});assert.equal(unverified.body.error.code,'receive_only_unverified');
});

// Proves: CL-008-07; CL-010-05/07/08; TC-009-005 cases1/2/6. Interception only
// delays a mutation body; all successful replies/state originate in the real server.
test('TC-009-005 browser preferred selection and Stop fence a genuinely delayed POST',{timeout:45000},async t=>{
  const {origin,request,cookie}=await station(t);const {chromium}=require('playwright');
  const browser=await chromium.launch();t.after(()=>browser.close());
  const context=await browser.newContext({ignoreHTTPSErrors:true,viewport:{width:1440,height:900}}),page=await context.newPage();
  const separator=cookie.indexOf('=');await context.addCookies([{name:cookie.slice(0,separator),value:cookie.slice(separator+1),url:origin,httpOnly:true,secure:true,sameSite:'Strict'}]);
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(origin);await page.locator('#connection[data-state=connected]').waitFor();await page.locator('#operating-band:enabled').waitFor();
  await page.selectOption('#operating-band','40m');await page.locator('#operating-selection-status').filter({hasText:'audio_unconfigured'}).waitFor();
  assert.match(await page.locator('#operating-radio').textContent(),/Nominal 7\.074000 MHz.*manual, actual rig unconfirmed/);
  await page.selectOption('#operating-mode','ft4');await page.waitForFunction(()=>document.querySelector('#op-dial').value==='7.047500');
  await page.locator('#operating-mode:enabled').waitFor();
  const before=(await request('/receive/selection')).body;
  let release,held;const gate=new Promise(resolve=>release=resolve),captured=new Promise(resolve=>held=resolve);const delayed=[];
  t.after(()=>release());
  page.on('response',response=>{if(response.url().endsWith('/receive/select'))delayed.push(response.status());});
  await page.route('**/receive/select',async route=>{const body=route.request().postDataJSON();if(body.action==='mode'&&body.mode==='ft8'){held();await gate;}await route.continue();});
  await page.selectOption('#operating-mode','ft8');await captured;
  await page.locator('#operating-stop:enabled').click();
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

// Proves: CL-008-03/07; TC-009-005 case7. One actual status response can publish
// the same readiness twice; unchanged context must not duplicate receive reads.
test('TC-009-005 one status refresh coalesces unchanged receive readiness',{timeout:30000},async t=>{
  const {origin,cookie}=await station(t),{chromium}=require('playwright');const browser=await chromium.launch();t.after(()=>browser.close());
  const context=await browser.newContext({ignoreHTTPSErrors:true}),page=await context.newPage();const separator=cookie.indexOf('=');
  await context.addCookies([{name:cookie.slice(0,separator),value:cookie.slice(separator+1),url:origin,httpOnly:true,secure:true,sameSite:'Strict'}]);
  await page.goto(origin);await page.locator('#connection[data-state=connected]').waitFor();await page.locator('#operating-band:enabled').waitFor();await page.waitForTimeout(200);
  await page.evaluate(()=>{window.__readyReads=[];addEventListener('station-ready',event=>window.__readyReads.push({sameSocket:event.detail===socket,pendingId,profile:profileData.profile_id,boot:profileData.boot_id,revision:profileData.revision}));});
  const reads=[];page.on('request',request=>{if(new URL(request.url()).pathname==='/receive')reads.push({method:request.method(),at:Date.now()});});
  const prior=await page.locator('#updated').textContent();await page.locator('#refresh').click();await page.waitForFunction(value=>document.querySelector('#updated').textContent!==value,prior);await page.waitForFunction(()=>window.__readyReads.length>=2);await page.waitForTimeout(250);
  const ready=await page.evaluate(()=>window.__readyReads);const evidence={reads,ready};await fs.mkdir('test-results/radio-selection',{recursive:true});await fs.writeFile('test-results/radio-selection/receive-ready.json',JSON.stringify(evidence,null,2));
  assert.equal(ready.length,2,'the actual before/after-profile readiness notifications were observed');assert.deepEqual(ready[0],ready[1],'the readiness context and status identity were unchanged');
  assert.equal(reads.length,1,'unchanged readiness from one status refresh needs one receive snapshot');
  await page.evaluate(()=>{dispatchEvent(new CustomEvent('station-ready',{detail:socket}));dispatchEvent(new CustomEvent('station-ready',{detail:socket}));});await page.waitForTimeout(100);assert.equal(reads.length,1,'the same completed readiness does not refetch');
  const keys=await page.evaluate(()=>{
    const p={profile_id:'00000000-0000-4000-8000-000000000001',boot_id:'00000000-0000-4000-8000-000000000002',revision:0};
    return {base:receiveReadyKey(p,1),profile:receiveReadyKey({...p,profile_id:'00000000-0000-4000-8000-000000000003'},1),boot:receiveReadyKey({...p,boot_id:'00000000-0000-4000-8000-000000000003'},1),revision:receiveReadyKey({...p,revision:1},1),status:receiveReadyKey(p,2),invalid:[receiveReadyKey(null,1),receiveReadyKey(p,null),receiveReadyKey({...p,boot_id:null},1),receiveReadyKey(p,0)],staleAdmitted:receiveReady({})};
  });
  assert.equal(new Set([keys.base,keys.profile,keys.boot,keys.revision,keys.status]).size,5,'every independently validated context field changes admission identity');assert.deepEqual(keys.invalid,[null,null,null,null]);assert.equal(keys.staleAdmitted,false);
  let release,entered;const gate=new Promise(resolve=>release=resolve),captured=new Promise(resolve=>entered=resolve);t.after(()=>release());
  let held=false;await page.route('**/receive',async route=>{if(!held){held=true;entered();await gate;}await route.continue();});
  await page.locator('#refresh').click();await captured;await page.waitForFunction(()=>window.__readyReads.length>=4);
  const secondUpdate=await page.locator('#updated').textContent();await page.locator('#refresh').click();await page.waitForFunction(value=>document.querySelector('#updated').textContent!==value,secondUpdate);await page.waitForFunction(()=>window.__readyReads.length>=6);await page.waitForTimeout(100);
  assert.equal(reads.length,2,'a changed status while pending queues one follow-up, not another parallel request');release();
  await page.waitForFunction(()=>!livePending);await page.waitForTimeout(100);assert.equal(reads.length,3,'the single legitimate changed-status follow-up executes');
  await page.unroute('**/receive');
  await page.evaluate(()=>{const id=pendingId;pendingId=null;dispatchEvent(new CustomEvent('station-ready',{detail:socket}));dispatchEvent(new CustomEvent('station-ready',{detail:socket}));pendingId=id;});
  await page.waitForFunction(()=>!livePending);await page.waitForTimeout(100);assert.equal(reads.length,5,'missing status identity bypasses dedup instead of becoming a global shared key');
  await page.evaluate(()=>dispatchEvent(new CustomEvent('station-ready',{detail:socket})));await page.waitForTimeout(100);assert.equal(reads.length,5,'invalid context did not poison the prior admitted valid context');
});
}else{
  assert.equal(process.env.WSTX_SELECTION_FIXTURE,'1','unknown fixture mode is not a skipped positive');
  liveSelectionFixture();
}

function liveSelectionFixture(){
  test('TC-009-005 actual native/CAT/TLS two-browser Thin and Off selection workload',{timeout:510000},async t=>{
    const {link}=require('./support.cjs'),{performance}=require('node:perf_hooks'),{chromium}=require('playwright');
    const oracle=JSON.parse(process.env.WSTX_SELECTION_EXPECTED),token=process.env.WSTX_SELECTION_TOKEN;
    assert.ok(oracle.ft8&&oracle.ft4&&token,'both independent mode oracles and authentication are mandatory');
    const proxy=await link({host:'127.0.0.2',port:1});proxy.target.port=proxy.port;t.after(()=>proxy.close());
    process.stdout.write(`WSTX_SELECTION_PROXY ${proxy.port}\n`);
    await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(new Error('real TLS fixture READY deadline')),15000);process.stdin.once('data',data=>{clearTimeout(timeout);if(data.toString().trim()==='READY')resolve();else reject(new Error('invalid real TLS fixture handshake'));});});
    const origin=`https://localhost:${proxy.port}`,browser=await chromium.launch();t.after(()=>browser.close());
    const pages=[],contexts=[],observations=[],errors=[],identities=[],report={startedUtc:new Date().toISOString(),windowSeconds:75,clients:2,model:'actual TLS streams plus unchanged support.cjs shared4000B/s/150ms/headers model',phases:{}};
    const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
    const waitUntil=async deadline=>{while(performance.now()<deadline)await sleep(Math.max(1,Math.ceil(deadline-performance.now())));};
    const save=async()=>{await fs.mkdir('test-results/radio-selection',{recursive:true});await fs.writeFile('test-results/radio-selection/live-link.json',JSON.stringify(report,null,2));};
    let activePhase=null;
    t.after(async()=>{if(activePhase){report.phases[activePhase].state='failed';report.phases[activePhase].endedUtc=new Date().toISOString();await save();}});
    for(let i=0;i<2;i++){
      const context=await browser.newContext({ignoreHTTPSErrors:true,viewport:{width:1440,height:900}});contexts.push(context);
      const session=await context.request.post(origin+'/session',{headers:{Origin:origin},data:token,timeout:20000});assert.equal(session.status(),204);
      const page=await context.newPage();pages.push(page);
      const seen={reads:[],receive:null,results:[],frames:[],active:0,maxActive:0,gestures:[],failures:[],http:[],sockets:[],transfers:[],wireFrames:[]};observations.push(seen);
      const cdp=await context.newCDPSession(page),transfers=new Map();await cdp.send('Network.enable');
      cdp.on('Network.requestWillBeSent',event=>{const transfer={route:new URL(event.request.url).pathname,method:event.request.method,started:performance.now(),ended:null,encodedBytes:null,initiator:event.initiator};transfers.set(event.requestId,transfer);seen.transfers.push(transfer);});
      cdp.on('Network.loadingFinished',event=>{const transfer=transfers.get(event.requestId);if(transfer){transfer.ended=performance.now();transfer.encodedBytes=event.encodedDataLength;}});
      cdp.on('Network.loadingFailed',event=>{const transfer=transfers.get(event.requestId);if(transfer){transfer.ended=performance.now();transfer.failure=event.errorText;}});
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
        const entry={route,status:response.status(),at:performance.now(),bodyBytes:null};seen.http.push(entry);
        if(!['/receive/selection','/receive','/receive/results'].includes(route)){if((response.headers()['content-type']||'').includes('application/json')){try{entry.bodyBytes=(await response.body()).length;}catch(error){entry.bodyError=error.message;}}return;}
        try{const text=await response.text();entry.bodyBytes=Buffer.byteLength(text);const body=JSON.parse(text);
          if(route==='/receive/selection'){const r=reads.get(response.request());if(r){r.body=body;r.status=response.status();if(r.ended===null){r.ended=performance.now();seen.active--;}}}
          if(route==='/receive')seen.receive=body;
          if(route==='/receive/results')seen.results.push(body);
        }catch(error){errors.push(`actual ${route} response: ${error.message}`);}
      });
      page.on('websocket',socket=>{const session={opened:performance.now(),closed:null,messages:[],receivedBytes:0};seen.sockets.push(session);socket.on('close',()=>session.closed=performance.now());socket.on('socketerror',error=>session.error=String(error));socket.on('framereceived',event=>{session.receivedBytes+=Buffer.byteLength(event.payload);try{const m=JSON.parse(event.payload);seen.wireFrames.push({at:performance.now(),type:m.type,bytes:Buffer.byteLength(event.payload)});if(m.type==='spectrum.frame')seen.frames.push({at:performance.now(),data:m.data});else session.messages.push({at:performance.now(),type:m.type,id:m.id,radio:m.data?.radio});}catch{}});});
    }
    const coldStarted=performance.now(),coldDeadline=coldStarted+230000;
    const coldRemaining=()=>{const remaining=Math.floor(coldDeadline-performance.now());assert.ok(remaining>0,'shared 230s Cold phase deadline');return remaining;};
    report.cold={state:'running',startedUtc:new Date().toISOString(),startedMonotonic:coldStarted,deadlineMonotonic:coldDeadline};await save();
    try{await Promise.all(pages.map(async(page,index)=>{
      const seen=observations[index];seen.navigationStarted=performance.now();await page.goto(origin,{timeout:coldRemaining()});seen.navigationCompleted=performance.now();
      await page.locator('#connection[data-state=connected]').waitFor({timeout:coldRemaining()});seen.connectedObserved=performance.now();
      await page.locator('#operating-band:enabled').waitFor({timeout:coldRemaining()});seen.operatingObserved=performance.now();
      await page.locator('[data-region=client-preferences]').first().click({timeout:coldRemaining()});await page.selectOption('#display-profile','thin',{timeout:coldRemaining()});await page.locator('.op-secondary:not([hidden]) .return-operate').click({timeout:coldRemaining()});
      assert.equal(await page.locator('#display-profile').inputValue({timeout:coldRemaining()}),'thin');seen.thinConfigured=performance.now();coldRemaining();
    }));}
    catch(error){
      const state=await Promise.all(pages.map(async(page,i)=>{const state=await page.evaluate(()=>({connection:document.querySelector('#connection')?.textContent,connectionState:document.querySelector('#connection')?.dataset.state,loginHidden:document.querySelector('#login')?.hidden,profileInitialized:typeof profileData==='object',body:document.body.innerText.slice(0,3500)})).catch(e=>({evaluationError:e.message}));await page.screenshot({path:`test-results/radio-selection/cold-failure-${i}.png`,fullPage:true}).catch(()=>{});return {...state,network:observations[i]};}));
      report.cold={state:'failed',elapsedMs:performance.now()-coldStarted,error:error.message,errors,diagnostics:state};await save();throw error;
    }
    coldRemaining();
    report.cold={state:'passed',elapsedMs:performance.now()-coldStarted,endedUtc:new Date().toISOString(),countedBytes:{...proxy.counters},pages:observations.map(seen=>({navigationStarted:seen.navigationStarted,navigationCompleted:seen.navigationCompleted,connectedObserved:seen.connectedObserved,operatingObserved:seen.operatingObserved,thinConfigured:seen.thinConfigured,failures:seen.failures,http:seen.http,sockets:seen.sockets})),errors:[...errors]};await save();
    const freshRead=async index=>{
      const seen=observations[index],before=seen.reads.length;seen.gestures.push(performance.now());await pages[index].locator('#operating-refresh:enabled').click();
      const deadline=performance.now()+12000;while(!seen.reads.slice(before).some(r=>r.ended!==null&&r.body?.v===1)){assert.ok(performance.now()<deadline,'actual explicit operating read completed');await sleep(20);}
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
        const snapshots=seen.reads.filter(r=>r.body?.operation?.command_id===ack.command_id);const last=snapshots.at(-1)?.body;
        assert.ok(last,'actual operating snapshot retained this command');assert.equal(last.selection.nominal_hz,hz);assert.equal(last.radio.observations.frequency.value,hz);assert.equal(last.radio.observations.mode.value.mode,'USB');assert.equal(last.radio.observations.data.value.enabled,true);
      }
      report.contexts=identities;await save();console.log(`Actual ${mode} CQ context ${identities.length}/5 at ${hz}Hz`);
      return ack.command_id;
    }
    await command('band','40m','ft8',7074000);
    async function measure(profile,steps){
      for(const page of pages){await page.locator('[data-region=client-preferences]').first().click();await page.selectOption('#display-profile',profile);await page.locator('.op-secondary:not([hidden]) .return-operate').click();}
      await sleep(500);const baseline={...proxy.counters},start=performance.now(),readStarts=observations.map(o=>o.reads.length),frameStarts=observations.map(o=>o.frames.length),latencies=[];
      activePhase=profile;report.phases[profile]={state:'running',startedUtc:new Date().toISOString(),representativeSeconds:75};await save();console.log(`Actual ${profile}75s workload started`);
      const status=async()=>{for(let n=1;n<=13;n++){await waitUntil(start+n*5500);await Promise.all(pages.map(async page=>{const previous=await page.locator('#updated').textContent(),began=performance.now();await page.locator('#refresh').click();await page.waitForFunction(value=>document.querySelector('#updated').textContent!==value,previous,{timeout:2000});const ms=performance.now()-began;assert.ok(ms<=2000,`actual ${profile} visible status ${ms}ms`);latencies.push(ms);}));}};
      const controls=async()=>{const commands=[];for(let n=0;n<steps.length;n++){await waitUntil(start+(n?40000:5000));commands.push(await command(...steps[n]));}return commands;};
      const [,commands]=await Promise.all([status(),controls()]);await waitUntil(start+75000);const seconds=(performance.now()-start)/1000;
      assert.ok(seconds>=75,'full predeclared representative window');const traffic={up:(proxy.counters.up-baseline.up)/seconds,down:(proxy.counters.down-baseline.down)/seconds};
      const pathCounts=observations.map(seen=>Object.fromEntries([...new Set(seen.http.filter(r=>r.at>=start).map(r=>r.route))].map(route=>[route,seen.http.filter(r=>r.at>=start&&r.route===route).length])));
      report.phases[profile]={state:'checking',seconds,sharedBytesPerSecond:traffic,statusMs:latencies,pathCounts,httpResponses:observations.map(seen=>seen.http.filter(r=>r.at>=start)),browserTransfers:observations.map(seen=>seen.transfers.filter(r=>r.started>=start||r.ended>=start)),websocketFrames:observations.map(seen=>seen.wireFrames.filter(frame=>frame.at>=start)),selectionReads:observations.map((seen,index)=>seen.reads.slice(readStarts[index]).map(r=>({startedMs:r.started-start,completedMs:r.ended===null?null:r.ended-start,phase:r.body?.operation?.phase??null,command:r.body?.operation?.command_id??null}))),frames:observations.map((seen,index)=>seen.frames.length-frameStarts[index])};await save();
      assert.ok(traffic.up<=3000,`${profile} actual counted uplink ${traffic.up}`);assert.ok(traffic.down<=3000,`${profile} actual counted downlink ${traffic.down}`);assert.equal(latencies.length,26);
      const polling=observations.map((seen,index)=>{
        const reads=seen.reads.slice(readStarts[index]).filter(r=>r.started>=start&&r.ended!==null&&r.body);assert.equal(seen.maxActive,1,'one selection read pending per actual browser');
        const pending=commands.map(id=>reads.filter(r=>r.body.operation?.command_id===id&&r.body.operation.result==='pending'));
        for(const [n,polls]of pending.entries()){assert.ok(polls.length>=2,`${profile} browser${index} command${n}: actual pending reads ${polls.length}`);assert.ok(polls.some((r,i)=>i&&r.started-polls[i-1].started>=3950),`${profile} browser${index} observed4s pending cadence`);}
        let passivePairs=0;
        for(let n=1;n<reads.length;n++){
          const previous=reads[n-1],current=reads[n];
          const user=seen.gestures.some(at=>at>=previous.started-200&&at<=current.started+100);
          if(user)continue;
          const pendingBefore=previous.body.operation?.result==='pending';const minimum=pendingBefore?3950:7950;
          assert.ok(current.started-previous.started>=minimum,`${profile} browser${index} actual poll start spacing ${current.started-previous.started}`);
          if(!pendingBefore)passivePairs++;
        }
        assert.ok(passivePairs>=1,'actual passive8s polling observed between user actions');
        return {reads:reads.map(r=>({startedMs:r.started-start,completedMs:r.ended-start,phase:r.body.operation?.phase??null,command:r.body.operation?.command_id??null,snapshotMonotonicMs:r.body.monotonic_ms})),pending:pending.map(p=>p.length),passivePairs,frames:seen.frames.length-frameStarts[index]};
      });
      if(profile==='thin')assert.ok(polling.every(p=>p.frames>0),'real optional live spectrum was present, not an idle body-size exercise');
      report.phases[profile]={...report.phases[profile],state:'passed',seconds,sharedBytesPerSecond:traffic,statusMs:latencies,polling,commands,endedUtc:new Date().toISOString()};activePhase=null;await save();console.log(`Actual ${profile} workload completed ${seconds.toFixed(3)}s ${JSON.stringify(traffic)}`);
    }
    await measure('thin',[['mode','ft4','ft4',7047500],['band','20m','ft4',14080000]]);
    await measure('off',[['mode','ft8','ft8',14074000],['band','40m','ft8',7074000]]);
    assert.equal(identities.length,5);assert.deepEqual(errors,[]);assert.equal(contexts.length,2);assert.equal(Object.values(report.phases).filter(p=>p.state==='passed').length,2);
    await pages[0].setViewportSize({width:1440,height:900});await pages[0].screenshot({path:'test-results/radio-selection/actual-native-cat-desktop.png',fullPage:true});
    await pages[0].setViewportSize({width:360,height:800});assert.equal(await pages[0].evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await pages[0].screenshot({path:'test-results/radio-selection/actual-native-cat-360.png',fullPage:true});
    console.log('WSTX_SELECTION_COMPLETED 2 5 2');
  });
}
