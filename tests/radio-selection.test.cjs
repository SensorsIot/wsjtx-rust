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
      const chunks=[];res.on('data',b=>chunks.push(b));res.on('end',()=>{try{const raw=Buffer.concat(chunks),text=(res.headers['content-encoding']==='gzip'?gunzipSync(raw):raw).toString('utf8');resolve({status:res.statusCode,headers:res.headers,raw,text,body:text&&(res.headers['content-type']||'').startsWith('application/json')?JSON.parse(text):null});}catch(error){reject(error);}});
    });req.on('error',reject);if(body!==undefined)req.write(typeof body==='string'||Buffer.isBuffer(body)?body:JSON.stringify(body));req.end();
  });
  const session=await request('/session','POST',token);assert.equal(session.status,204);cookie=session.headers['set-cookie'][0].split(';')[0];
  return {origin,id,request,cookie};
}

// Proves: CL-008-07; TC-009-005 cases2/5. Parent has no selection route, so this
// fails on actual HTTP404 rather than a build/import error.
if(!process.env.WSTX_SELECTION_FIXTURE){
test('TC-009-005 network lifetime and correlated Off oracle reject true violations',()=>{
  // Frozen52311 CDP finished before the next admission; response.json callbacks overlapped.
  const transfers=[{route:'/receive/selection',started:245504.2448,ended:246268.4788},{route:'/receive/selection',started:246269.0282,ended:247211.7476}];
  assert.equal(selectionNetworkSummary(transfers,245000,248000).maxActive,1);
  const overlap=structuredClone(transfers);overlap[1].started=overlap[0].ended-1;assert.equal(selectionNetworkSummary(overlap,245000,248000).maxActive,2);
  const boundary=structuredClone(transfers);boundary[1].started=boundary[0].ended;assert.equal(selectionNetworkSummary(boundary,245000,248000).maxActive,1);
  assert.ok(41670.0860<41671.8184,'old parsed-body completion would falsely report overlap');
  const requests=[{socket:2,id:17,profile:'off',at:10}],acks=[{socket:2,id:16,profile:'off',at:11},{socket:3,id:17,profile:'off',at:12},{socket:2,id:17,profile:'thin',at:13}];
  assert.equal(correlatedOffAck(requests,acks,9),null);acks.push({socket:2,id:17,profile:'off',at:14});const ack=correlatedOffAck(requests,acks,9);assert.equal(ack.id,17);assert.equal(assertOffAckDeadline({requestedAt:10,ackAt:2010}),2000);assert.throws(()=>assertOffAckDeadline({requestedAt:10,ackAt:2010.001}),/Off acknowledgement/);
  const frames=[{socket:2,type:'spectrum.frame',at:13},{socket:2,type:'heartbeat',at:15}];assert.deepEqual(optionalAfterOff(frames,ack),[]);frames.push({socket:2,type:'spectrum.detail.frame',at:15});assert.equal(optionalAfterOff(frames,ack).length,1);
});

test('TC-009-005 frozen automatic cadence fault controls',async t=>{
  const body=(result='pending')=>({profile_id:'profile-A',boot_id:'boot-A',profile_revision:3,operating_revision:7,generation:11,snapshot_sequence:21,receive:{job_id:'old-job'},operation:{command_id:'command-A',result,new_job_id:null}});
  const previous=()=>({station:'https://station-A',started:1000,ended:1800,kind:'explicit/reconciliation',body:body()});
  const successor=()=>({station:'https://station-A',started:5000,ended:5800,kind:'automatic',body:{...body('success'),snapshot_sequence:22}});
  const pair=(p=previous(),c=successor(),mutations=[])=>cadencePair(p,c,mutations);
  const refused=(p,c,mutations=[])=>{try{assert.equal(pair(p,c,mutations).eligible,false);}catch(error){if(error.code!=='ERR_ASSERTION')throw error;if(!/spacing|transport/.test(error.message))throw error;}};
  await t.test('pending to terminal uses prior state',()=>assert.equal(pair().pendingCoverage,true));
  await t.test('pending to pending remains coverage',()=>{const c=successor();c.body.operation.result='pending';assert.equal(pair(previous(),c).pendingCoverage,true);});
  await t.test('pending below3950 refused',()=>{const c=successor();c.started=4949;assert.throws(()=>pair(previous(),c),/spacing/);});
  await t.test('applied prior state at4s refused',()=>{const p=previous();p.body.operation.result='success';assert.throws(()=>pair(p),/spacing/);});
  await t.test('wrong command refused',()=>{const c=successor();c.body.operation.command_id='command-B';refused(previous(),c);});
  await t.test('each fixed identity refused',()=>{for(const key of ['profile_id','boot_id','profile_revision','operating_revision']){const c=successor();c.body[key]='changed';refused(previous(),c);}const c=successor();c.station='https://station-B';refused(previous(),c);});
  await t.test('explicit and reconcile cannot prove timer coverage',()=>{const c=successor();c.kind='explicit/reconciliation';assert.equal(pair(previous(),c).eligible,false);assert.throws(()=>assertCadenceCoverage([pair(previous(),c)],'explicit'),/missing/);});
  await t.test('overlap refused using network lifetime',()=>{const p=previous();p.ended=5001;assert.throws(()=>pair(p),/transport/);});
  await t.test('same command owns new receive generation',()=>{const c=successor();c.body.generation=12;c.body.receive.job_id='new-job';c.body.operation.new_job_id='new-job';assert.equal(pair(previous(),c).pendingCoverage,true);});
  await t.test('unowned new generation refused',()=>{const c=successor();c.body.generation=12;c.body.receive.job_id='unrelated';refused(previous(),c);c.body.operation.new_job_id='unrelated';c.body.operation.command_id='command-B';refused(previous(),c);});
  await t.test('intervening mutation refused',()=>refused(previous(),successor(),[{started:2000}]));
  await t.test('delayed pending is lawful but cannot prove4s regime',()=>{const c=successor();c.started=9000;assert.equal(pair(previous(),c).eligible,true);assert.equal(pair(previous(),c).pendingCoverage,false);});
  await t.test('every browser and profile needs both regimes',()=>{
    const p=previous();p.body.operation.result='success';const c=successor();c.started=9000;const passive=pair(p,c),pending=pair();
    for(const profile of ['thin','off'])for(const browser of [0,1]){assertCadenceCoverage([pending,passive],`${profile}${browser}`);assert.throws(()=>assertCadenceCoverage([passive],`${profile}${browser}`),/pending-context/);assert.throws(()=>assertCadenceCoverage([pending],`${profile}${browser}`),/passive-context/);}
  });
  await t.test('actual frozen source and exact caller stack',async()=>{
    const mapping=cadenceSource(await fs.readFile(path.join(__dirname,'../client/recording.js'))),origin='https://station-A';
    const initiator=line=>({type:'script',stack:{callFrames:[{url:origin+'/recording.js',functionName:'operatingSync',lineNumber:693},{url:origin+'/recording.js',lineNumber:line}]}});
    assert.equal(cadenceCaller(initiator(772),origin,mapping),'automatic');for(const line of [710,724,738,744,755,757,765,774])assert.equal(cadenceCaller(initiator(line),origin,mapping),'explicit/reconciliation');assert.throws(()=>cadenceCaller(initiator(771),origin,mapping),/unknown/);
    assert.throws(()=>cadenceJoin({transfers:[],reads:[{}]},origin,mapping),/complete ordered/);
  });
  await t.test('source acceptance guards refuse discarded valid-shaped snapshots',async()=>{
    const mapping=cadenceSource(await fs.readFile(path.join(__dirname,'../client/recording.js')));
    const uuid='00000000-0000-4000-8000-000000000001',unknown={value:null,query_sequence:null,observed_at_ms:null,confirmed:false};
    const snapshot={v:1,profile_id:uuid,boot_id:uuid,profile_revision:3,generation:11,operating_revision:7,snapshot_sequence:21,monotonic_ms:100,control:'manual',selection:{mode:'ft8',band:null,nominal_hz:null,origin:'unknown',confirmed_command_id:null},available_bands:[],operation:null,cancellation:null,receive:{job_id:null,mode:null,state:null,audio_state:'closed',owner_released:true},radio:{connection_generation:0,state:'closed',error:null,observations:{frequency:unknown,mode:unknown,data:unknown,rx_tx:unknown,split:unknown}}};
    assert.equal(mapping.valid(snapshot),true,'negative controls begin with a fully valid browser schema');
    const expected={profile_id:uuid,boot_id:uuid,profile_revision:3};
    const event={at:900,epoch:0,connected:true,sameSocket:true,acceptedSequence:20,...expected};
    const q=()=>({expected,events:[event,{...event,at:6000,acceptedSequence:21}]});
    const request={wallStarted:1000,wallEnded:1800},next={wallStarted:5000};
    assert.equal(cadenceAccepted(snapshot,request,next,q()).acceptedSequence,21);
    for(const key of ['profile_id','boot_id','profile_revision']){const wrong=structuredClone(snapshot);wrong[key]=key==='profile_revision'?4:'00000000-0000-4000-8000-000000000002';assert.equal(mapping.valid(wrong),true);assert.throws(()=>cadenceAccepted(wrong,request,next,q()),/expected/);}
    const invalid=q();invalid.events.splice(1,0,{...event,at:1500,epoch:1,acceptedSequence:20});assert.throws(()=>cadenceAccepted(snapshot,request,next,invalid),/discarded|unproven/);
    const socket=q();socket.events.splice(1,0,{...event,at:1500,sameSocket:false});assert.throws(()=>cadenceAccepted(snapshot,request,next,socket),/socket/);
    const unproven=q();unproven.events[1].acceptedSequence=20;assert.throws(()=>cadenceAccepted(snapshot,request,null,unproven),/unproven/);
    const after=q();after.events.splice(1,0,{...event,at:2000,epoch:1,acceptedSequence:21});assert.equal(cadenceAccepted(snapshot,request,next,after).proof,'accepted state at invalidating action');
    const stale=structuredClone(snapshot);stale.snapshot_sequence=19;assert.equal(mapping.valid(stale),true);
    assert.throws(()=>cadenceAccepted(stale,request,next,q()),/stale sequence/);
  });
  const coldSockets=()=>[{index:0,opened:10,closed:12},{index:1,opened:20,closed:22},{index:2,opened:30,closed:null}];
  const socketBaseline=()=>({index:2,count:3,at:40,end:120});
  await t.test('failed Cold attempts precede accepted live socket segment',()=>{cadenceSocketSegment(coldSockets(),socketBaseline());const sockets=coldSockets();sockets[0].closed=100;cadenceSocketSegment(sockets,socketBaseline());});
  await t.test('accepted socket closure or replacement during segment refused',()=>{const sockets=coldSockets();sockets[2].closed=80;assert.throws(()=>cadenceSocketSegment(sockets,socketBaseline()),/remains live/);sockets.push({index:3,opened:81,closed:null});assert.throws(()=>cadenceSocketSegment(sockets,socketBaseline()),/new socket/);});
  await t.test('new measured socket refused despite otherwise valid context',()=>{const sockets=coldSockets();sockets.push({index:3,opened:80,closed:null});assert.throws(()=>cadenceSocketSegment(sockets,socketBaseline()),/new socket/);});
  await t.test('wrong baseline socket index or time refused',()=>{for(const change of [{index:0},{index:3},{at:25},{at:121},{end:null}])assert.throws(()=>cadenceSocketSegment(coldSockets(),{...socketBaseline(),...change}));const sockets=coldSockets();sockets[2].index=1;assert.throws(()=>cadenceSocketSegment(sockets,socketBaseline()),/identity/);});
});

test('TC-009-005 H1 raw TLS gzip snapshots preserve bounded JSON',{timeout:30000},async t=>{
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

// Read the reviewed fixed-shape SysML oracle, never candidate negotiation output.
function canonicalNegotiations(source){
  const lines=source.split(/\r?\n/).map(line=>line.trim()),vectors=[];
  const value=(line,prefix)=>{assert.ok(line?.startsWith(prefix)&&line.endsWith(';'),'malformed canonical negotiation field');return line.slice(prefix.length,-1);};
  for(const [name,expected]of [
    ['negotiationSourceSha256','329bf57ef2a989f3128d96b845c4064dbda01a595b7e2fa1a594de77c18b9e56'],
    ['originalVectorArtifactSha256','d8da8bdb86485cc8691e2ad4f37afcbbaf84969c5b1a145f3a187a86d114a3c9'],
  ]){
    const prefix=`attribute ${name} : String = `,pins=lines.filter(line=>line.startsWith(prefix));
    assert.equal(pins.length,1,'one independently pinned provenance value');assert.equal(JSON.parse(value(pins[0],prefix)),expected);
  }
  for(let index=0;index<lines.length;index++){
    const line=lines[index];if(!line.includes(': NegotiationOracleVector'))continue;
    const match=/^attribute negotiation(\d{2}) : NegotiationOracleVector \{$/.exec(line);
    assert.ok(match,'malformed canonical negotiation declaration');const id=Number(match[1]);
    assert.equal(id,vectors.length+1,'all cases occur once in canonical order');
    assert.equal(value(lines[++index],'attribute :>> caseId = '),String(id),'declaration and case ID agree');
    const encoded=JSON.parse(value(lines[++index],'attribute :>> orderedRawHeaderFieldsJson = '));assert.equal(typeof encoded,'string');
    const fields=JSON.parse(encoded);assert.ok(Array.isArray(fields)&&fields.every(field=>typeof field==='string'),'ordered raw-header string array');
    const outcome=value(lines[++index],'attribute :>> expected = HttpCodingSelection::');assert.ok(['gzip','identity','noAcceptable'].includes(outcome),'known independent outcome');
    assert.equal(lines[++index],'}','no extra or missing oracle fields');
    vectors.push({fields,expected:outcome==='noAcceptable'?'406':outcome});
  }
  assert.equal(vectors.length,49,'all 49 frozen cases must execute');return vectors;
}

test('TC-009-005 SysML negotiation reader refuses missing malformed and duplicate oracles',async()=>{
  const source=await fs.readFile(path.join(__dirname,'../docs/sysml/OperatingReceive.sysml'),'utf8');
  assert.equal(canonicalNegotiations(source).length,49);
  for(const damaged of [
    source.replace('attribute negotiation01 :','attribute omitted01 :'),
    source.replace('attribute :>> caseId = 2;','attribute :>> caseId = 1;'),
    source.replace('attribute :>> orderedRawHeaderFieldsJson = "[]";','attribute :>> orderedRawHeaderFieldsJson = "{bad}";'),
    source.replace('HttpCodingSelection::noAcceptable;','HttpCodingSelection::unknown;'),
    source.replace('329bf57ef2a989f3128d96b845c4064dbda01a595b7e2fa1a594de77c18b9e56','changed'),
  ])assert.throws(()=>canonicalNegotiations(damaged));
});

test('TC-009-005 H1 all 49 ordered header cases use the real authenticated TLS router',{timeout:30000},async t=>{
  const {request}=await station(t),source=await fs.readFile(path.join(__dirname,'../docs/sysml/OperatingReceive.sysml'),'utf8');
  const vectors=canonicalNegotiations(source);
  assert.equal(vectors.length,49);const identity=await request('/profile');assert.equal(identity.status,200);
  for(const [index,vector]of vectors.entries()){
    const actual=await request('/profile','GET',undefined,vector.fields.length?{'Accept-Encoding':vector.fields}:{});
    assert.equal(actual.status,vector.expected==='406'?406:200,`frozen vector${index+1}`);
    assert.equal(actual.headers['content-encoding'],vector.expected==='gzip'?'gzip':undefined,`frozen vector${index+1}`);
    if(vector.expected==='gzip'){assert.deepEqual([...actual.raw.subarray(0,3)],[31,139,8]);assert.equal(gunzipSync(actual.raw).toString('utf8'),identity.text);}
    if(vector.expected==='identity')assert.equal(actual.text,identity.text);
  }
});

test('TC-009-005 H1 authentication errors mutations static and HEAD bypass negotiation',{timeout:30000},async t=>{
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

function selectionNetworkSummary(transfers,start,end){
  const requests=transfers.filter(r=>r.route==='/receive/selection'&&r.started<end&&(r.ended===null||r.ended>start));
  const events=[];
  for(const request of requests){assert.ok(request.ended===null||request.ended>=request.started,'CDP terminal follows admission');const first=Math.max(start,request.started),last=Math.min(end,request.ended??end);if(last>first){events.push({at:first,delta:1},{at:last,delta:-1});}}
  events.sort((a,b)=>a.at-b.at||a.delta-b.delta);
  let active=0,maxActive=0;for(const event of events){active+=event.delta;assert.ok(active>=0);maxActive=Math.max(maxActive,active);}
  return {maxActive,requests,pendingAtEnd:requests.filter(r=>r.ended===null||r.ended>end).length};
}
// Freeze the actual served caller and acceptance guards, not just a function name.
function cadenceSource(bytes){
  const sha256=require('node:crypto').createHash('sha256').update(bytes).digest('hex');
  assert.equal(sha256,'361ed4af3ac7fecfc24cfaee4ee75f77e1660fc1002ddccfa902b7ad01c5f712','review caller/acceptance mapping when recording.js changes');
  const source=bytes.toString('utf8');
  const valid=require('node:vm').runInNewContext(source.slice(source.indexOf('const operatingBands='),source.indexOf('function operatingShow()'))+';validOperatingState');
  return {sha256,valid,fetchLine:693,timerLine:772};
}
function cadenceCaller(initiator,origin,mapping){
  const frames=initiator?.stack?.callFrames;
  assert.equal(initiator?.type,'script','selection read must have script provenance');
  assert.ok(frames?.length>=2,'complete selection caller stack');
  assert.equal(frames[0].url,origin+'/recording.js');assert.equal(frames[0].functionName,'operatingSync');assert.equal(frames[0].lineNumber,mapping.fetchLine);
  const caller=frames[1];assert.equal(caller.url,origin+'/recording.js');
  // All non-timer entry points of this exact frozen source. Unknown stacks fail closed.
  const explicitLines=[710,724,738,744,755,757,765,774];
  if(caller.lineNumber===mapping.timerLine)return 'automatic';
  assert.ok(explicitLines.includes(caller.lineNumber),`unknown selection caller ${caller.lineNumber}`);
  return 'explicit/reconciliation';
}
function cadencePair(previous,current,mutations){
  const gap=current.started-previous.started,p=previous.body,c=current.body;
  const pending=p.operation?.result==='pending';
  const pair={previous,current,gap,priorResult:p.operation?.result??null,minimum:pending?3950:7950,eligible:false,reason:null};
  if(current.kind!=='automatic'){pair.reason='explicit/reconciliation';return pair;}
  assert.ok(previous.ended<=current.started,'sequential actual selection transport');
  // These lower bounds apply to EVERY automatic dispatch, even across an identity change.
  assert.ok(gap>=pair.minimum,`automatic ${pair.priorResult} start spacing ${gap}`);
  if(!c){pair.reason='incomplete trailing response';return pair;}
  const fixed=['station','profile_id','boot_id','profile_revision','operating_revision'];
  if(fixed.some(key=>(key==='station'?previous.station:p[key])!==(key==='station'?current.station:c[key]))||p.operation?.command_id!==c.operation?.command_id){pair.reason='identity/command changed';return pair;}
  if(p.operation&&['base_revision','revision','action','requested','old_job_id'].some(key=>JSON.stringify(p.operation[key])!==JSON.stringify(c.operation[key]))){pair.reason='command context changed';return pair;}
  if(p.radio?.connection_generation!==c.radio?.connection_generation){pair.reason='radio connection changed';return pair;}
  if(mutations.some(m=>m.started>previous.started&&m.started<=current.started)){pair.reason='intervening mutation';return pair;}
  if(c.snapshot_sequence<p.snapshot_sequence){pair.reason='stale successor';return pair;}
  const changed=p.generation!==c.generation||p.receive.job_id!==c.receive.job_id;
  // Only the same owning operation may introduce its newly created receive context.
  if(changed&&!(pending&&c.operation?.command_id===p.operation.command_id&&c.operation.new_job_id&&c.receive.job_id===c.operation.new_job_id&&c.generation>=p.generation)){
    pair.reason='unrelated receive context';return pair;
  }
  pair.eligible=true;pair.pendingCoverage=pending&&gap<7950;pair.passiveCoverage=!pending;return pair;
}
function cadenceAccepted(body,request,next,qualification){
  const {expected,events}=qualification;
  for(const key of ['profile_id','boot_id','profile_revision'])assert.equal(body[key],expected[key],`source acceptance expected ${key}`);
  const before=events.filter(e=>e.at<=request.wallStarted).at(-1);
  assert.ok(before&&before.connected&&before.sameSocket,'proven connected socket at dispatch');
  assert.ok(before.acceptedSequence===null||body.snapshot_sequence>=before.acceptedSequence,'source stale sequence guard');
  const boundary=next?.wallStarted??events.at(-1).at;
  const during=events.filter(e=>e.at>request.wallStarted&&e.at<=boundary);
  for(const event of during){
    assert.ok(event.connected&&event.sameSocket,'source socket context invalidated');
    if(event.epoch!==before.epoch){
      // A synchronous action checkpoint can prove acceptance BEFORE that action
      // increments the epoch. Otherwise network completion alone is insufficient.
      assert.equal(event.acceptedSequence,body.snapshot_sequence,'source epoch discarded or acceptance unproven');
      assert.ok(request.wallEnded!==null&&request.wallEnded<=event.at,'mutation before response completion');
      return {epoch:before.epoch,proof:'accepted state at invalidating action',acceptedSequence:event.acceptedSequence};
    }
  }
  assert.ok(next||events.at(-1).acceptedSequence===body.snapshot_sequence,'final response acceptance unproven');
  return {epoch:before.epoch,proof:next?'frozen guards and next sequential dispatch':'accepted final checkpoint',acceptedSequence:body.snapshot_sequence};
}
function cadenceQualification(seen){
  const q=seen.acceptance,events=q.events;
  assert.ok(events.length>=2);cadenceSocketSegment(seen.sockets,q.socketBaseline);
  let epoch=events[0].epoch,actions=0;
  for(const event of events){
    assert.ok(event.connected&&event.sameSocket,'fixed workload socket/context changed');
    for(const key of ['profile_id','boot_id','profile_revision'])assert.equal(event[key],q.expected[key],`fixed workload expected ${key}`);
    if(event.action){epoch++;actions++;}assert.equal(event.epoch,epoch,'all source epoch changes accounted for');
  }
  for(const {at,body:profile}of seen.profileBodies.filter(p=>p.at>=q.socketBaseline.at))for(const [key,field]of [['profile_id','profile_id'],['boot_id','boot_id'],['profile_revision','revision']])assert.equal(profile[field],q.expected[key],'authoritative profile remains fixed within qualified segment');
  const mutations=seen.transfers.filter(r=>r.wallStarted>=events[0].at&&!['GET','HEAD'].includes(r.method));
  assert.equal(mutations.length,actions,'each epoch action has exactly one actual mutation');
  assert.ok(mutations.every(r=>r.method==='POST'&&r.route==='/receive/select'),'no unaccounted epoch-changing mutation');
  return q;
}
function cadenceSocketSegment(sockets,baseline){
  assert.ok(baseline&&Number.isInteger(baseline.count)&&baseline.count>0,'accepted socket baseline captured');
  assert.equal(baseline.index,baseline.count-1,'accepted baseline is the current socket');
  assert.ok(Number.isFinite(baseline.at)&&baseline.at>=0&&Number.isFinite(baseline.end)&&baseline.at<=baseline.end,'bounded monotonic socket segment');
  assert.equal(sockets.length,baseline.count,'no new socket after accepted baseline');
  const accepted=sockets[baseline.index];assert.ok(accepted,'accepted baseline socket exists');
  assert.equal(accepted.index,baseline.index,'baseline socket identity');
  assert.ok(sockets.every(s=>s.opened<=baseline.at),'all socket creations precede baseline');
  assert.ok(accepted.closed===null||accepted.closed>baseline.end,'accepted socket remains live throughout segment');
}
function cadenceJoin(seen,origin,mapping){
  const network=seen.transfers.filter(r=>r.route==='/receive/selection'&&r.method==='GET');
  assert.equal(network.length,seen.reads.length,'complete ordered page/CDP selection join');
  return network.map((transfer,index)=>{
    const read=seen.reads[index];
    assert.ok(index===0||transfer.started>network[index-1].started,'unambiguous CDP admission order');
    assert.ok(index===0||read.started>seen.reads[index-1].started,'unambiguous page admission order');
    assert.ok(Math.abs(transfer.started-read.started)<1000,'ordered page/CDP admission agrees');
    assert.equal(transfer.failure,undefined);
    if(read.body){assert.equal(read.status,200);assert.ok(mapping.valid(read.body),'actual selection body passes frozen browser schema');assert.ok(Buffer.byteLength(JSON.stringify(read.body))<=3072);}
    else assert.equal(index,network.length-1,'only final in-flight/observer response may be incomplete');
    const previous=network[index-1];if(previous)assert.ok(previous.ended!==null&&previous.ended<=transfer.started,'no transport overlap');
    const priorBody=seen.reads[index-1]?.body;
    if(priorBody&&read.body&&priorBody.boot_id===read.body.boot_id)assert.ok(read.body.snapshot_sequence>=priorBody.snapshot_sequence,'fail closed on a snapshot the browser would reject as old');
    // The source cannot dispatch the next read until response.text, validation and
    // operatingState assignment finish. Observer JSON callbacks may finish later.
    const acceptance=read.body&&transfer.wallStarted>=seen.acceptance.events[0].at?cadenceAccepted(read.body,transfer,network[index+1],seen.acceptance):null;
    return {...transfer,station:origin,kind:cadenceCaller(transfer.initiator,origin,mapping),body:read.body,acceptance,observerParsedAt:read.ended};
  });
}
function assertCadenceCoverage(pairs,label){
  assert.ok(pairs.some(p=>p.eligible&&p.pendingCoverage),`${label}: missing automatic4s pending-context pair`);
  assert.ok(pairs.some(p=>p.eligible&&p.passiveCoverage),`${label}: missing automatic8s passive-context pair`);
}
function correlatedOffAck(requests,acks,after){
  for(const request of requests.filter(r=>r.profile==='off'&&r.at>=after)){
    const ack=acks.find(a=>a.profile==='off'&&a.id===request.id&&a.socket===request.socket&&a.at>=request.at);
    if(ack)return {profile:'off',socket:ack.socket,id:ack.id,requestedAt:request.at,ackAt:ack.at};
  }
  return null;
}
function assertOffAckDeadline(ack){const elapsed=ack.ackAt-ack.requestedAt;assert.ok(Number.isFinite(elapsed)&&elapsed>=0&&elapsed<=2000,`actual Off acknowledgement ${elapsed}ms exceeds2000ms`);return elapsed;}
function optionalAfterOff(frames,ack){return frames.filter(frame=>frame.socket===ack.socket&&frame.at>ack.ackAt&&['spectrum.frame','spectrum.detail.frame'].includes(frame.type));}

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
      const seen={reads:[],profileBodies:[],receive:null,results:[],frames:[],active:0,maxActive:0,gestures:[],failures:[],http:[],sockets:[],transfers:[],wireFrames:[],subscriptionRequests:[],subscriptionAcks:[]};observations.push(seen);
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
        if(route==='/profile'&&response.status()===200)seen.profileBodies.push({at:performance.now(),body:await response.json()});
        const entry={route,status:response.status(),at:performance.now(),bodyBytes:null,contentEncoding:response.headers()['content-encoding']??null};seen.http.push(entry);
        if(!['/receive/selection','/receive','/receive/results'].includes(route)){if((response.headers()['content-type']||'').includes('application/json')){try{entry.bodyBytes=(await response.body()).length;}catch(error){entry.bodyError=error.message;}}return;}
        try{const text=await response.text();entry.bodyBytes=Buffer.byteLength(text);const body=JSON.parse(text);
          if(route==='/receive/selection'){const r=reads.get(response.request());if(r){r.body=body;r.status=response.status();if(r.ended===null){r.ended=performance.now();seen.active--;}}}
          if(route==='/receive')seen.receive=body;
          if(route==='/receive/results')seen.results.push(body);
        }catch(error){errors.push(`actual ${route} response: ${error.message}`);}
      });
      page.on('websocket',socket=>{const session={index:seen.sockets.length,opened:performance.now(),closed:null,messages:[],receivedBytes:0};seen.sockets.push(session);socket.on('close',()=>session.closed=performance.now());socket.on('socketerror',error=>session.error=String(error));socket.on('framesent',event=>{try{const m=JSON.parse(event.payload);if(['spectrum.off','spectrum.thin','spectrum.detail'].includes(m.type)&&Number.isSafeInteger(m.id))seen.subscriptionRequests.push({socket:session.index,at:performance.now(),id:m.id,profile:m.type.slice(9)});}catch{}});socket.on('framereceived',event=>{session.receivedBytes+=Buffer.byteLength(event.payload);try{const m=JSON.parse(event.payload),at=performance.now();seen.wireFrames.push({socket:session.index,at,type:m.type,bytes:Buffer.byteLength(event.payload)});if(m.type==='spectrum.subscription')seen.subscriptionAcks.push({socket:session.index,at,id:m.id,profile:m.data?.profile});if(m.type==='spectrum.frame')seen.frames.push({socket:session.index,at,data:m.data});else session.messages.push({at,type:m.type,id:m.id,radio:m.data?.radio});}catch{}});});
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
    for(const [index,page]of pages.entries()){
      const authoritative=observations[index].profileBodies.at(-1)?.body;assert.ok(authoritative,'authoritative setup profile observed');
      const socketBaseline={index:observations[index].sockets.length-1,count:observations[index].sockets.length,at:performance.now(),end:null};
      observations[index].acceptance={socketBaseline,expected:{profile_id:authoritative.profile_id,boot_id:authoritative.boot_id,profile_revision:authoritative.revision},events:await page.evaluate(()=>{
        const initialSocket=socket,events=[];
        const snapshot=action=>{events.push({at:performance.timeOrigin+performance.now(),action,epoch:operatingEpoch,connected:connection.dataset.state==='connected',sameSocket:socket===initialSocket&&socket.readyState===WebSocket.OPEN,profile_id:profileData.profile_id,boot_id:profileData.boot_id,profile_revision:profileData.revision,acceptedSequence:operatingState?.snapshot_sequence??null});};
        snapshot(false);
        addEventListener('station-ready',()=>snapshot(false));addEventListener('station-stale',()=>snapshot(false));
        // Bubble after the source handler's synchronous epoch increment. This
        // observes only the two existing selections; it does not wrap fetch.
        document.addEventListener('change',event=>{if(['operating-mode','operating-band'].includes(event.target.id))snapshot(true);});
        window.__cadenceAcceptanceCheckpoint=()=>{snapshot(false);return events;};return events;
      })};
    }
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
      const offProofs=[];
      for(const [index,page]of pages.entries()){const after=performance.now();await page.locator('[data-region=client-preferences]').first().click();await page.selectOption('#display-profile',profile);await page.locator('.op-secondary:not([hidden]) .return-operate').click();if(profile==='off'){const deadline=performance.now()+10000;let ack;while(!(ack=correlatedOffAck(observations[index].subscriptionRequests,observations[index].subscriptionAcks,after))){assert.ok(performance.now()<deadline,'actual correlated Off acknowledgement');await sleep(10);}offProofs.push(ack);report.offAcknowledgements=[...offProofs];await save();assertOffAckDeadline(ack);}}
      await sleep(500);const baseline={...proxy.counters},start=performance.now(),readStarts=observations.map(o=>o.reads.length),frameStarts=observations.map(o=>o.frames.length),latencies=[];
      activePhase=profile;report.phases[profile]={state:'running',startedUtc:new Date().toISOString(),representativeSeconds:75};await save();console.log(`Actual ${profile}75s workload started`);
      const status=async()=>{for(let n=1;n<=13;n++){await waitUntil(start+n*5500);await Promise.all(pages.map(async page=>{const previous=await page.locator('#updated').textContent(),began=performance.now();await page.locator('#refresh').click();await page.waitForFunction(value=>document.querySelector('#updated').textContent!==value,previous,{timeout:2000});const ms=performance.now()-began;assert.ok(ms<=2000,`actual ${profile} visible status ${ms}ms`);latencies.push(ms);}));}};
      const controls=async()=>{const commands=[];for(let n=0;n<steps.length;n++){await waitUntil(start+(n?40000:5000));commands.push(await command(...steps[n]));}return commands;};
      const [,commands]=await Promise.all([status(),controls()]);await waitUntil(start+75000);const seconds=(performance.now()-start)/1000;
      assert.ok(seconds>=75,'full predeclared representative window');const traffic={up:(proxy.counters.up-baseline.up)/seconds,down:(proxy.counters.down-baseline.down)/seconds};
      const pathCounts=observations.map(seen=>Object.fromEntries([...new Set(seen.http.filter(r=>r.at>=start).map(r=>r.route))].map(route=>[route,seen.http.filter(r=>r.at>=start&&r.route===route).length])));
      report.phases[profile]={state:'checking',seconds,sharedBytesPerSecond:traffic,statusMs:latencies,pathCounts,offProofs,networkSelection:observations.map(seen=>selectionNetworkSummary(seen.transfers,start,start+seconds*1000)),httpResponses:observations.map(seen=>seen.http.filter(r=>r.at>=start)),browserTransfers:observations.map(seen=>seen.transfers.filter(r=>r.started>=start||r.ended>=start)),websocketFrames:observations.map(seen=>seen.wireFrames.filter(frame=>frame.at>=start)),selectionReads:observations.map((seen,index)=>seen.reads.slice(readStarts[index]).map(r=>({startedMs:r.started-start,completedMs:r.ended===null?null:r.ended-start,phase:r.body?.operation?.phase??null,command:r.body?.operation?.command_id??null}))),frames:observations.map((seen,index)=>seen.frames.length-frameStarts[index])};await save();
      for(const seen of observations){const replies=seen.http.filter(r=>r.at>=start&&r.status===200&&['/receive/selection','/receive','/receive/results','/profile','/radio','/recording'].includes(r.route));assert.ok(replies.length>0);assert.ok(replies.every(r=>r.contentEncoding==='gzip'),'actual browser negotiated gzip on every eligible response');}
      assert.ok(traffic.up<=3000,`${profile} actual counted uplink ${traffic.up}`);assert.ok(traffic.down<=3000,`${profile} actual counted downlink ${traffic.down}`);assert.equal(latencies.length,26);
      for(const [index,page]of pages.entries()){observations[index].acceptance.events=await page.evaluate(()=>window.__cadenceAcceptanceCheckpoint());observations[index].acceptance.socketBaseline.end=performance.now();}
      report.phases[profile].cadenceRaw=observations.map(seen=>({sourceBase64:seen.cadenceSource?.toString('base64'),acceptance:seen.acceptance,profileBodies:seen.profileBodies,reads:seen.reads,transfers:seen.transfers}));await save();
      const evidence=observations.map(seen=>{
        const evidence={joined:[],pairs:[],errors:[]};
        try{
          const mapping=cadenceSource(seen.cadenceSource);evidence.sourceSha256=mapping.sha256;
          cadenceQualification(seen);
          evidence.joined=cadenceJoin(seen,origin,mapping);
          const mutations=observations.flatMap(o=>o.transfers).filter(r=>!['GET','HEAD'].includes(r.method));
          for(let n=1;n<evidence.joined.length;n++){
            const previous=evidence.joined[n-1],current=evidence.joined[n];
            if(previous.started<start||current.started>=start+seconds*1000)continue;
            assert.ok(previous.acceptance,'prior selection acceptance proven');
            if(current.body)assert.ok(current.acceptance,'successor selection acceptance proven');
            try{evidence.pairs.push(cadencePair(previous,current,mutations));}
            catch(error){evidence.errors.push({message:error.message,previous,current});}
          }
        }catch(error){evidence.errors.push({message:error.message});}
        return evidence;
      });
      report.phases[profile].cadenceEvidence=evidence;await save();
      const polling=observations.map((seen,index)=>{
        const network=selectionNetworkSummary(seen.transfers,start,start+seconds*1000);assert.equal(network.maxActive,1,'one actual CDP network selection read pending per browser');
        const proof=evidence[index];assert.deepEqual(proof.errors,[],'complete validated cadence evidence');
        const reads=proof.joined.filter(r=>r.started>=start&&r.started<start+seconds*1000&&r.body);
        const pending=commands.map(id=>reads.filter(r=>r.body.operation?.command_id===id&&r.body.operation.result==='pending'));
        for(const [n,polls]of pending.entries())assert.ok(polls.length>=1,`${profile} browser${index} command${n}: actual pending reads ${polls.length}`);
        assertCadenceCoverage(proof.pairs,`${profile} browser${index}`);
        return {reads,pending:pending.map(p=>p.length),passivePairs:proof.pairs.filter(p=>p.eligible&&p.passiveCoverage).length,pendingPairs:proof.pairs.filter(p=>p.eligible&&p.pendingCoverage).length,frames:seen.frames.length-frameStarts[index]};
      });
      if(profile==='thin')assert.ok(polling.every(p=>p.frames>0),'real optional live spectrum was present, not an idle body-size exercise');
      if(profile==='off'){assert.equal(offProofs.length,2);for(const [index,ack]of offProofs.entries()){assert.ok(ack.ackAt<=start);assert.deepEqual(optionalAfterOff(observations[index].wireFrames,ack),[],'no optional frame after its correlated Off ACK');assert.equal(polling[index].frames,0,'no optional spectrum during actual Off window');}}
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
