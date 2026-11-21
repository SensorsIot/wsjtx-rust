'use strict';
// The tests of the receive-selection evidence readers (selection-evidence.cjs), on fixed
// records, the served client source and a local fixture page; no station.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises'),path=require('node:path');
const {listenBrowser}=require('./support.cjs');
const {selectionNetworkSummary,cadenceSource,cadenceCaller,cadenceQualification,cadenceSocketSegment,failureEvidence,failureHooks,
  cadenceJoin,correlatedOffAck,assertOffAckDeadline,optionalAfterOff,observeReceiveResponse,abandonedBodiesNotReRead}=require('./selection-evidence.cjs');

// The page's own request timeout can abandon a /receive body after its headers, in the live
// Thin/Off workload. The real Chromium page here abandons one the same way, and the same
// evidence reader must keep it aside only until the route is read complete again, while a
// completed malformed body, and an abandoned body never read again, stay refused.
test('evidence reader tolerates only a page-abandoned receive body that is read again',{timeout:30000},async t=>{
  const {chromium}=require('playwright'),http=require('node:http');
  const fixture=http.createServer((request,response)=>{
    if(request.url==='/'){response.end('<!doctype html><title>x</title>');return;}
    response.writeHead(200,{'content-type':'application/json','cache-control':'no-store'});
    if(request.url.startsWith('/receive?stall'))response.write('{"v":');
    else if(request.url.startsWith('/receive/results?malformed'))response.end('{"v":');
    else response.end('{"v":1}');
  });
  await listenBrowser(fixture);t.after(()=>{fixture.closeAllConnections();fixture.close();});
  const browser=await chromium.launch();t.after(()=>browser.close());
  const page=await browser.newPage(),seen={http:[],abandonedBodies:[],receive:null,results:[],active:0},errors=[],pending=[];
  page.on('response',response=>{const route=new URL(response.url()).pathname;if(route==='/')return;
    const entry={route,status:response.status(),at:performance.now(),bodyBytes:null};seen.http.push(entry);pending.push(observeReceiveResponse(response,entry,seen,new Map(),errors));});
  await page.goto(`http://127.0.0.1:${fixture.address().port}/`);
  // recording.js request(): one AbortSignal.timeout covers the headers and the body.
  const read=path=>page.evaluate(async path=>{try{return await (await fetch(path,{signal:AbortSignal.timeout(400)})).json();}catch(error){return error.name;}},path);
  const settle=async count=>{for(const deadline=performance.now()+5000;seen.http.length<count;)assert.ok(performance.now()<deadline,'response observed'),await new Promise(r=>setTimeout(r,20));await Promise.all(pending);};
  assert.equal(await read('/receive?stall'),'TimeoutError','the page abandons the body after the headers');await settle(1);
  assert.deepEqual(errors,[],'an abandoned body is not an evidence error');
  assert.equal(seen.abandonedBodies.length,1);assert.equal(seen.abandonedBodies[0].failure,'net::ERR_ABORTED');
  assert.deepEqual(abandonedBodiesNotReRead(seen).map(a=>a.route),['/receive'],'until it is read again it is refused');
  assert.deepEqual(await read('/receive?again'),{v:1});await settle(2);
  assert.deepEqual(abandonedBodiesNotReRead(seen),[],'a later complete read of the route clears it');assert.deepEqual(seen.receive,{v:1});
  assert.deepEqual(await read('/receive/results?ok'),{v:1});await settle(3);
  assert.equal(await read('/receive/results?malformed'),'SyntaxError');await settle(4);
  assert.equal(errors.length,1,'a completed malformed body stays an evidence error');assert.match(errors[0],/^actual \/receive\/results response: /);
  assert.equal(seen.abandonedBodies.length,1,'a malformed body is never kept aside as abandoned');
});
test('network lifetime and correlated Off oracle reject true violations',()=>{
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

// Evidence (no promise): the failure output of a Thin or Off window, from fixed
// sockets, stale records and frames. Each record appears exactly once, on the one UTC-ms clock.
test('Failure evidence of a Thin or Off window lists each socket, stale and close once in UTC ms',async()=>{
  const parse=lines=>{assert.equal(lines[0],'WSTX_EVIDENCE a Thin or Off window failed: from the lines below');assert.equal(lines.filter(l=>l.includes('a Thin or Off window failed')).length,1,'one header line');return lines.slice(1).map(l=>{assert.match(l,/^WSTX_EVIDENCE \{/);return JSON.parse(l.slice('WSTX_EVIDENCE '.length));});};
  // Hand calculation: origin 1800000000000.5 ms; Node 1000 -> 1800000001000.5, 61000.25 -> 1800000061000.75.
  const timeOrigin=1800000000000.5,windows=[{profile:'thin',start:1000,end:61000.25}];
  // (a) No socket ended in the window: the output states none.
  const quiet=parse(failureEvidence({timeOrigin,now:70000,windows,browsers:[{sockets:[{index:0,opened:500.25,closed:null,lastFrameAt:60000}],staleRecords:[],frames:[]}]}));
  // (f) Node times converted by the stated origin.
  assert.deepEqual(quiet.filter(e=>e.kind==='window'),[{kind:'window',profile:'thin',startUtc:1800000001000.5,endUtc:1800000061000.75}]);
  assert.deepEqual(quiet.filter(e=>e.kind==='socket'),[{kind:'socket',browser:0,index:0,openedUtc:1800000000500.75,closedUtc:null,error:null,lastFrameUtc:1800000060000.5}]);
  assert.deepEqual(quiet.filter(e=>e.kind==='in-window'),[{kind:'in-window',browser:0,socketCloses:'none',staleRecords:'none'}]);
  assert.deepEqual(quiet.filter(e=>e.kind==='stale'||e.kind==='frames-before-close'),[]);
  // A window still running when the phase failed ends at the failure time.
  assert.equal(parse(failureEvidence({timeOrigin,now:70000,windows:[{profile:'off',start:1000,end:null}],browsers:[]}))[0].endUtc,1800000070000.5);
  // The fixture's after hooks, in their order: the failed window ends at the failure (Node 40000),
  // not at the teardown (90000) whose browser close ends the socket at 89000, outside the window.
  const hooks=[],failed={profile:'thin',start:1000,end:null};let clock=40000,printed=null;
  failureHooks(hook=>hooks.push(hook),{now:()=>clock,underWay:()=>failed,close:()=>{clock=90000;},
    evidence:()=>{printed=parse(failureEvidence({timeOrigin,now:clock,windows:[failed],browsers:[{sockets:[{index:0,opened:500,closed:89000,lastFrameAt:null}],staleRecords:[],frames:[]}]}));}});
  for(const hook of hooks)await hook();
  assert.equal(printed[0].endUtc,1800000040000.5,'the failure time, not the teardown time');
  assert.equal(printed.find(e=>e.kind==='in-window').socketCloses,'none','the teardown close lies after the failed window');  // (b) browser 0: a watchdog close at C = 30000 (UTC 1800000030000.5); (c) browser 1: a socket the
  // station ended at 30400; (d) both within the same second.
  // (e) Frames around C: C-12000 included, C-12001 excluded, C included; another socket's never.
  const stale0={at:1800000030000,path:'watchdog',silenceMs:12500,deferredPending:false,socketState:1,authorization:'ready'};
  const stale1={at:1800000030401,path:'socket-closed',silenceMs:3000,deferredPending:false,socketState:3,authorization:'ready'};
  const lines=failureEvidence({timeOrigin,now:70000,windows,browsers:[
    {sockets:[{index:0,opened:500,closed:30000,lastFrameAt:30000},{index:1,opened:31000,closed:null,lastFrameAt:null}],staleRecords:[stale0],
      frames:[{socket:0,at:17999,type:'heartbeat',bytes:26},{socket:0,at:18000,type:'heartbeat',bytes:26},{socket:0,at:30000,type:'station.status',bytes:90},{socket:1,at:29000,type:'heartbeat',bytes:26}]},
    {sockets:[{index:0,opened:600,closed:30400,lastFrameAt:29000,error:'Error: reset'}],staleRecords:[stale1],frames:[{socket:0,at:29000,type:'heartbeat',bytes:26}]}]});
  const shown=parse(lines),of=(kind,browser)=>shown.filter(e=>e.kind===kind&&e.browser===browser);
  assert.equal(shown.filter(e=>e.kind==='window').length,1,'the window once');
  assert.deepEqual(of('socket',0).map(s=>[s.index,s.openedUtc,s.closedUtc]),[[0,1800000000500.5,1800000030000.5],[1,1800000031000.5,null]]);
  assert.deepEqual(of('socket',1),[{kind:'socket',browser:1,index:0,openedUtc:1800000000600.5,closedUtc:1800000030400.5,error:'Error: reset',lastFrameUtc:1800000029000.5}]);
  assert.deepEqual(of('stale',0),[{kind:'stale',browser:0,...stale0}]);assert.deepEqual(of('stale',1),[{kind:'stale',browser:1,...stale1}]);
  assert.deepEqual(of('in-window',0),[{kind:'in-window',browser:0,socketCloses:[0],staleRecords:[1800000030000]}]);
  assert.deepEqual(of('in-window',1),[{kind:'in-window',browser:1,socketCloses:[0],staleRecords:[1800000030401]}]);
  assert.deepEqual(of('frames-before-close',0),[{kind:'frames-before-close',browser:0,socket:0,closedUtc:1800000030000.5,
    frames:[{atUtc:1800000018000.5,type:'heartbeat',bytes:26},{atUtc:1800000030000.5,type:'station.status',bytes:90}]}]);
  assert.deepEqual(of('frames-before-close',1),[{kind:'frames-before-close',browser:1,socket:0,closedUtc:1800000030400.5,frames:[{atUtc:1800000029000.5,type:'heartbeat',bytes:26}]}]);
  assert.equal(shown.length,1+3+2+2+2,'nothing more: window, sockets, stale records, in-window and close lines');
});

test('no timer reads the selection: source and caller fault controls',async t=>{
  await t.test('actual source: every selection read has an explicit caller, an unknown stack is refused',async()=>{
    const mapping=cadenceSource(await fs.readFile(path.join(__dirname,'../../../client/recording.js'))),origin='https://station-A';
    const initiator=line=>({type:'script',stack:{callFrames:[{url:origin+'/recording.js',functionName:'operatingSync',lineNumber:mapping.fetchLine},{url:origin+'/recording.js',lineNumber:line}]}});
    assert.ok(mapping.explicitLines.length>0,'the reconnect and explicit reads stay');
    for(const line of mapping.explicitLines)assert.equal(cadenceCaller(initiator(line),origin,mapping),'explicit/reconciliation');
    const unknown=mapping.explicitLines[0]-1;assert.ok(!mapping.explicitLines.includes(unknown));assert.throws(()=>cadenceCaller(initiator(unknown),origin,mapping),/unknown selection caller.*review the cadence/);
    const wrongFetch=initiator(mapping.explicitLines[0]);wrongFetch.stack.callFrames[0].lineNumber=mapping.fetchLine+1;assert.throws(()=>cadenceCaller(wrongFetch,origin,mapping),/review the cadence/);
    const wrapped={type:'script',stack:{callFrames:[{url:origin+'/authorization.js',functionName:'protectedFetch',lineNumber:1},{url:origin+'/app.js',functionName:'stationFetch',lineNumber:1},...initiator(mapping.explicitLines[0]).stack.callFrames]}};
    assert.equal(cadenceCaller(wrapped,origin,mapping),'explicit/reconciliation');
    wrapped.stack.callFrames[1].functionName='other';assert.throws(()=>cadenceCaller(wrapped,origin,mapping));
  });
  await t.test('caller mapping is derived from the source and line-ending neutral',async()=>{
    const lf=(await fs.readFile(path.join(__dirname,'../../../client/recording.js'),'utf8')).replace(/\r\n/g,'\n'),crlf=lf.replace(/\n/g,'\r\n');
    const lines=({fetchLine,explicitLines})=>({fetchLine,explicitLines}),base=lines(cadenceSource(Buffer.from(lf)));
    assert.notEqual(lf,crlf);assert.deepEqual(lines(cadenceSource(Buffer.from(crlf))),base);
    // A change that only moves lines (a comment above the fetch) moves the mapping with it.
    const at=lf.indexOf("    const response=await stationFetch('/receive/selection'"),shifted=lines(cadenceSource(Buffer.from(lf.slice(0,at)+'    // shifted\n'+lf.slice(at))));
    assert.deepEqual(shifted,{fetchLine:base.fetchLine+1,explicitLines:base.explicitLines.map(n=>n+1)});
    // A timer read coming back, or an ambiguous or lost fetch, needs review, not a renewal.
    const src=lf.split('\n'),fetch=src[base.fetchLine];
    const variant=(index,replacement)=>Buffer.from([...src.slice(0,index),...replacement,...src.slice(index+1)].join('\n'));
    assert.throws(()=>cadenceSource(Buffer.from(lf+'\nsetInterval(()=>operatingSync(false),2000);\n')),/a timer reads the selection/);
    assert.throws(()=>cadenceSource(Buffer.from(lf+'\nsetInterval(()=>{\n  if(ok)operatingSync(false);\n},250);\n')),/a timer reads the selection/);
    assert.throws(()=>cadenceSource(variant(base.fetchLine,['    const response=await fetch(\'/x\'),text=await response.text();'])),/review the cadence caller mapping: the selection fetch matched 0 lines/);
    assert.throws(()=>cadenceSource(variant(base.fetchLine,[fetch,fetch])),/review the cadence caller mapping: the selection fetch matched 2 lines/);
  });
  const coldSockets=()=>[{index:0,opened:10,closed:12},{index:1,opened:20,closed:22},{index:2,opened:30,closed:null}];
  const socketBaseline=()=>({index:2,count:3,at:40,end:120});
  await t.test('failed Cold attempts precede accepted live socket segment',()=>{cadenceSocketSegment(coldSockets(),socketBaseline());const sockets=coldSockets();sockets[0].closed=100;cadenceSocketSegment(sockets,socketBaseline());});
  await t.test('accepted socket closure or replacement during segment refused',()=>{const sockets=coldSockets();sockets[2].closed=80;assert.throws(()=>cadenceSocketSegment(sockets,socketBaseline()),/remains live/);sockets.push({index:3,opened:81,closed:null});assert.throws(()=>cadenceSocketSegment(sockets,socketBaseline()),/new socket/);});
  await t.test('new measured socket refused despite otherwise valid context',()=>{const sockets=coldSockets();sockets.push({index:3,opened:80,closed:null});assert.throws(()=>cadenceSocketSegment(sockets,socketBaseline()),/new socket/);});
  await t.test('wrong baseline socket index or time refused',()=>{for(const change of [{index:0},{index:3},{at:25},{at:121},{end:null}])assert.throws(()=>cadenceSocketSegment(coldSockets(),{...socketBaseline(),...change}));const sockets=coldSockets();sockets[2].index=1;assert.throws(()=>cadenceSocketSegment(sockets,socketBaseline()),/identity/);});
  // catSync's automatic CAT status read (POST, no operator action) can land after the
  // acceptance baseline; it is no station mutation.
  const expectedIdentity={profile_id:'profile-A',boot_id:'boot-A',profile_revision:3};
  const qualified=(transfers,withAction=true)=>{
    const event={action:false,epoch:0,connected:true,sameSocket:true,acceptedSequence:20,...expectedIdentity};
    const events=[{...event,at:1000},...(withAction?[{...event,at:2000,action:true,epoch:1}]:[]),{...event,at:9000,epoch:withAction?1:0}];
    return {acceptance:{socketBaseline:{index:0,count:1,at:40,end:120},expected:expectedIdentity,events},sockets:[{index:0,opened:10,closed:null}],profileBodies:[],transfers};
  };
  const select={method:'POST',route:'/receive/select',wallStarted:2001},catStatusRead={method:'POST',route:'/authorization/v1/status',wallStarted:1500};
  await t.test('automatic CAT status read after baseline is not a station mutation',()=>{
    cadenceQualification(qualified([select]));
    cadenceQualification(qualified([catStatusRead,select]));
    cadenceQualification(qualified([catStatusRead],false));
  });
  await t.test('real unaccounted mutations still refused beside a CAT status read',()=>{
    assert.throws(()=>cadenceQualification(qualified([catStatusRead,select,{...select,wallStarted:3000}])),/exactly one/);
    assert.throws(()=>cadenceQualification(qualified([catStatusRead,{method:'POST',route:'/receive/start',wallStarted:1500}],false)),/exactly one/);
    assert.throws(()=>cadenceQualification(qualified([{method:'POST',route:'/receive/start',wallStarted:1500}])),/unaccounted/);
    assert.throws(()=>cadenceQualification(qualified([{method:'PUT',route:'/profile',wallStarted:1500}],false)),/exactly one/);
    assert.throws(()=>cadenceQualification(qualified([select],false)),/exactly one/);
  });
  // A Cold-load selection read can hit the page's own 10 s timeout (net::ERR_ABORTED) before
  // the baseline; the page supersedes it, so it does not fail the join.
  await t.test('Cold selection read the page timed out before baseline is superseded, not a failure',async()=>{
    const mapping=cadenceSource(await fs.readFile(path.join(__dirname,'../../../client/recording.js'))),origin='https://station-A';
    const initiator={type:'script',stack:{callFrames:[{url:origin+'/recording.js',functionName:'operatingSync',lineNumber:mapping.fetchLine},{url:origin+'/recording.js',lineNumber:mapping.explicitLines[0]}]}};
    const uuid='00000000-0000-4000-8000-000000000001',unknown={value:null,query_sequence:null,observed_at_ms:null,confirmed:false};
    const snapshot={v:1,profile_id:uuid,boot_id:uuid,profile_revision:3,generation:11,operating_revision:7,snapshot_sequence:21,monotonic_ms:100,control:'manual',selection:{mode:'ft8',band:null,nominal_hz:null,origin:'unknown',confirmed_command_id:null},available_bands:[],operation:null,cancellation:null,receive:{job_id:null,mode:null,state:null,audio_state:'closed',owner_released:true},radio:{connection_generation:0,state:'closed',error:null,observations:{frequency:unknown,mode:unknown,data:unknown,rx_tx:unknown,split:unknown}}};
    const seen=(abort={})=>{
      const a={route:'/receive/selection',method:'GET',started:1000,ended:11000,wallStarted:1000,wallEnded:null,failure:'net::ERR_ABORTED',initiator,...abort};
      const ok={route:'/receive/selection',method:'GET',started:a.ended+200,ended:a.ended+800,wallStarted:a.ended+200,wallEnded:a.ended+800,initiator};
      return {transfers:[a,ok],reads:[{started:a.started,ended:a.ended,body:null,failed:true},{started:ok.started,ended:ok.ended,body:snapshot,status:200}],acceptance:{socketBaseline:{at:20000},events:[{at:90000}]}};
    };
    assert.equal(cadenceJoin(seen(),origin,mapping).length,2);
    assert.throws(()=>cadenceJoin(seen({started:15000,ended:25000,wallStarted:15000}),origin,mapping),/ERR_ABORTED/,'abort ending inside the qualified segment');
    assert.throws(()=>cadenceJoin(seen({ended:1300}),origin,mapping),/ERR_ABORTED/,'abort before the page timeout is not the page superseding its read');
    assert.throws(()=>cadenceJoin(seen({failure:'net::ERR_CONNECTION_RESET'}),origin,mapping),/ERR_CONNECTION_RESET/);
    const last=seen();last.transfers.pop();last.reads.pop();assert.throws(()=>cadenceJoin(last,origin,mapping),/followed by a new read/);
  });
});
