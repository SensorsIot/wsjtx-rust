'use strict';
// The evidence readers of the receive-selection suite (tests/radio-selection.test.cjs): the
// selection network summary, the cadence caller mapping and join, the correlated Off
// acknowledgement, the failure evidence of a Thin or Off window and the receive body observer.
const assert=require('node:assert/strict');

// A read the client sends as POST is not a station mutation: /authorization/v1/status (catSync, sent on a CAT identity/state change, never by an
// operator action) only reads the CAT condition and receive state (authorization_http.rs
// Operation::Status). Every other non-GET request, including /receive/select, counts.
const readOnlyPosts=['/authorization/v1/status'];
function stationMutation(r){return !['GET','HEAD'].includes(r.method)&&!(r.method==='POST'&&readOnlyPosts.includes(r.route));}
// A Cold-load selection read the page itself abandoned: its frozen AbortSignal.timeout(10000)
// fired (CDP lifetime >= 9500 ms, net::ERR_ABORTED) and the read ended before the accepted
// baseline, so the page's next read superseded it and nothing it carried reaches the qualified
// segment. Any other failure, any abort ending inside the segment, or an abort with no later read
// fails the join.
function supersededColdRead(transfer,read,baseline){
  return transfer.failure==='net::ERR_ABORTED'&&read?.failed===true&&!read.body&&transfer.ended!==null&&Number.isFinite(baseline?.at)&&transfer.ended<baseline.at&&transfer.ended-transfer.started>=9500;
}
// Map the actual served caller sites and acceptance guards, not just a function name. The
// mapping is derived from the served source, so a change that only moves lines needs no
// renewal; a site that is missing or ambiguous fails and asks for a review.
function cadenceSource(bytes){
  // The station serves working-tree bytes, whose line endings depend on the checkout
  // (autocrlf CRLF or LF). Derive from the LF-normalized text, the same as git's content.
  const source=Buffer.from(bytes).toString('utf8').replace(/\r\n/g,'\n'),lines=source.split('\n');
  // CDP line numbers are 0-based, the same as these indices.
  const single=(what,hits)=>{assert.equal(hits.length,1,`review the cadence caller mapping: ${what} matched ${hits.length} lines of recording.js (${hits.map(n=>n+1).join(',')||'none'})`);return hits[0];};
  const fetchLine=single('the selection fetch',lines.flatMap((line,n)=>line.includes("stationFetch('/receive/selection'")?[n]:[]));
  // Every call of operatingSync (not its definition); selection.state carries the state, so none
  // may sit inside a top-level setInterval( timer (its statement starts at the nearest unindented line).
  const callers=lines.flatMap((line,n)=>/(?<!function )\boperatingSync\(/.test(line)?[n]:[]);
  const inTimer=n=>{while(n>0&&/^\s/.test(lines[n]))n--;return lines[n].startsWith('setInterval(');};
  const timers=callers.filter(inTimer);assert.equal(timers.length,0,`review the cadence caller mapping: a timer reads the selection (${timers.map(n=>n+1)})`);
  assert.ok(source.includes("stationFetch('/receive/selection',{signal:AbortSignal.timeout(10000)})"),'frozen 10 s selection read timeout');
  const valid=require('node:vm').runInNewContext(source.slice(source.indexOf('const operatingBands='),source.indexOf('function operatingShow()'))+';validOperatingState');
  // The digest is report evidence of which source was served, not a gate.
  const sha256=require('node:crypto').createHash('sha256').update(source,'utf8').digest('hex');
  return {sha256,valid,fetchLine,explicitLines:callers};
}
function cadenceCaller(initiator,origin,mapping){
  let frames=initiator?.stack?.callFrames;
  assert.equal(initiator?.type,'script','selection read must have script provenance');
  // A selected HTTPS profile reads through the exact station authorization wrapper first.
  if(frames?.[0]?.url===origin+'/authorization.js'){
    assert.equal(frames[0].functionName,'protectedFetch');assert.equal(frames[1]?.url,origin+'/app.js');assert.equal(frames[1].functionName,'stationFetch');
    frames=frames.slice(2);
  }
  assert.ok(frames?.length>=2,'complete selection caller stack');
  assert.equal(frames[0].url,origin+'/recording.js');assert.equal(frames[0].functionName,'operatingSync');assert.equal(frames[0].lineNumber,mapping.fetchLine,`selection read from line ${frames[0].lineNumber}, not the selection fetch ${mapping.fetchLine}: review the cadence caller mapping`);
  const caller=frames[1];assert.equal(caller.url,origin+'/recording.js');
  // Every operatingSync call of the served source is explicit or reconciliation.
  // Unknown stacks fail closed. catSync never reads selection (CL-022-03).
  assert.ok(mapping.explicitLines.includes(caller.lineNumber),`unknown selection caller line ${caller.lineNumber}: review the cadence caller mapping`);
  return 'explicit/reconciliation';
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
  for(const {at,body:profile,bodyError}of seen.profileBodies.filter(p=>p.at>=q.socketBaseline.at)){assert.ok(profile,`profile body read within the qualified segment ${bodyError??''}`);for(const [key,field]of [['profile_id','profile_id'],['boot_id','boot_id'],['profile_revision','revision']])assert.equal(profile[field],q.expected[key],'authoritative profile remains fixed within qualified segment');}
  const mutations=seen.transfers.filter(r=>r.wallStarted>=events[0].at&&stationMutation(r));
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
// The evidence a failed Thin or Off window prints (stdout, so the gate log keeps it) and the
// report keeps. One clock, UTC ms: Node times are performance.now() values converted by the stated
// origin (performance.timeOrigin), page times are Date.now(); the station's own socket records are
// printed by the Rust test. Frames count before a close C when C-12000 <= t <= C (clientSilenceMs).
const clientSilenceMs=12000;
function evidenceUtc(timeOrigin,t){return t===null||t===undefined?null:Math.round((timeOrigin+t)*1000)/1000;}
function evidenceWindow(timeOrigin,w,now){return {kind:'window',profile:w.profile,startUtc:evidenceUtc(timeOrigin,w.start),endUtc:evidenceUtc(timeOrigin,w.end??now)};}
function failureEvidence({timeOrigin,now,windows,browsers}){
  const lines=['WSTX_EVIDENCE a Thin or Off window failed: from the lines below and the WSTX_STATION_SOCKET lines'];
  const out=value=>lines.push('WSTX_EVIDENCE '+JSON.stringify(value)),utc=t=>evidenceUtc(timeOrigin,t);
  const bounds=windows.map(w=>evidenceWindow(timeOrigin,w,now));for(const w of bounds)out(w);
  const inWindow=t=>t!==null&&bounds.some(w=>w.startUtc!==null&&t>=w.startUtc&&t<=w.endUtc);
  for(const [browser,{sockets,staleRecords,frames}]of browsers.entries()){
    const shown=sockets.map(s=>({kind:'socket',browser,index:s.index,openedUtc:utc(s.opened),closedUtc:utc(s.closed),error:s.error??null,lastFrameUtc:utc(s.lastFrameAt)}));
    for(const s of shown)out(s);
    for(const record of staleRecords)out({kind:'stale',browser,...record});
    const closes=shown.filter(s=>inWindow(s.closedUtc)).map(s=>s.index),stale=staleRecords.filter(r=>inWindow(r.at)).map(r=>r.at);
    out({kind:'in-window',browser,socketCloses:closes.length?closes:'none',staleRecords:stale.length?stale:'none'});
    for(const s of shown.filter(s=>s.closedUtc!==null))out({kind:'frames-before-close',browser,socket:s.index,closedUtc:s.closedUtc,
      frames:frames.filter(f=>f.socket===s.index).map(f=>({atUtc:utc(f.at),type:f.type,bytes:f.bytes})).filter(f=>f.atUtc>=s.closedUtc-clientSilenceMs&&f.atUtc<=s.closedUtc)});
  }
  return lines;
}
// After hooks run in registration order. The first ends a failed window at the failure time,
// before the browser close ends both browsers' sockets; the evidence is printed after the close.
function failureHooks(after,{now,underWay,close,evidence}){
  after(()=>{const w=underWay();if(w&&w.end===null)w.end=now();});
  after(close);
  after(evidence);
}
function cadenceJoin(seen,origin,mapping){
  const network=seen.transfers.filter(r=>r.route==='/receive/selection'&&r.method==='GET');
  assert.equal(network.length,seen.reads.length,'complete ordered page/CDP selection join');
  return network.map((transfer,index)=>{
    const read=seen.reads[index];
    assert.ok(index===0||transfer.started>network[index-1].started,'unambiguous CDP admission order');
    assert.ok(index===0||read.started>seen.reads[index-1].started,'unambiguous page admission order');
    assert.ok(Math.abs(transfer.started-read.started)<1000,'ordered page/CDP admission agrees');
    const superseded=transfer.failure!==undefined&&supersededColdRead(transfer,read,seen.acceptance?.socketBaseline);
    if(superseded)assert.ok(index<network.length-1,'a superseded Cold read is followed by a new read');
    else assert.equal(transfer.failure,undefined);
    if(read.body){assert.equal(read.status,200);assert.ok(mapping.valid(read.body),'actual selection body passes frozen browser schema');assert.ok(Buffer.byteLength(JSON.stringify(read.body))<=3072);}
    else if(!superseded)assert.equal(index,network.length-1,'only final in-flight/observer response may be incomplete');
    const previous=network[index-1];if(previous)assert.ok(previous.ended!==null&&previous.ended<=transfer.started,'no transport overlap');
    const priorBody=seen.reads[index-1]?.body;
    if(priorBody&&read.body&&priorBody.boot_id===read.body.boot_id)assert.ok(read.body.snapshot_sequence>=priorBody.snapshot_sequence,'fail closed on a snapshot the browser would reject as old');
    return {...transfer,station:origin,kind:cadenceCaller(transfer.initiator,origin,mapping),body:read.body,observerParsedAt:read.ended};
  });
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
// Reads the body of one /receive, /receive/selection or /receive/results response into the
// evidence. On the starved link the page's own 10 s request timeout (AbortSignal.timeout in
// recording.js request()) can fire after the headers arrived but before the body did: the request
// ends net::ERR_ABORTED, the client drops that read and reads again, and Chromium holds no body
// (Network.getResponseBody "No data found ..."; Playwright's hint about navigation is generic).
// Only that page-abandoned body is kept aside, as evidence; abandonedBodiesNotReRead then requires
// a later complete read of the same route. A completed response whose body is unreadable or not
// JSON, or a body failure of any other kind, stays an evidence error.
async function observeReceiveResponse(response,entry,seen,reads,errors){
  const route=entry.route;
  try{let text;
    try{text=await response.text();}
    catch(error){const failure=response.request().failure()?.errorText??null;if(failure!=='net::ERR_ABORTED')throw error;seen.abandonedBodies.push({route,status:entry.status,responseAt:entry.at,at:performance.now(),error:error.message,failure});return;}
    entry.bodyBytes=Buffer.byteLength(text);const body=JSON.parse(text);entry.parsed=true;
    if(route==='/receive/selection'){const r=reads.get(response.request());if(r){r.body=body;r.status=response.status();if(r.ended===null){r.ended=performance.now();seen.active--;}}}
    if(route==='/receive')seen.receive=body;
    if(route==='/receive/results')seen.results.push(body);
  }catch(error){errors.push(`actual ${route} response: ${error.message}`);}
}
function abandonedBodiesNotReRead(seen){return seen.abandonedBodies.filter(a=>!seen.http.some(e=>e.route===a.route&&e.parsed&&e.at>a.at));}
function selectionNetworkSummary(transfers,start,end){
  const requests=transfers.filter(r=>r.route==='/receive/selection'&&r.started<end&&(r.ended===null||r.ended>start));
  const events=[];
  for(const request of requests){assert.ok(request.ended===null||request.ended>=request.started,'CDP terminal follows admission');const first=Math.max(start,request.started),last=Math.min(end,request.ended??end);if(last>first){events.push({at:first,delta:1},{at:last,delta:-1});}}
  events.sort((a,b)=>a.at-b.at||a.delta-b.delta);
  let active=0,maxActive=0;for(const event of events){active+=event.delta;assert.ok(active>=0);maxActive=Math.max(maxActive,active);}
  return {maxActive,requests,pendingAtEnd:requests.filter(r=>r.ended===null||r.ended>end).length};
}

module.exports={selectionNetworkSummary,readOnlyPosts,stationMutation,supersededColdRead,cadenceSource,cadenceCaller,
  cadenceQualification,cadenceSocketSegment,clientSilenceMs,evidenceUtc,evidenceWindow,failureEvidence,failureHooks,
  cadenceJoin,correlatedOffAck,assertOffAckDeadline,optionalAfterOff,observeReceiveResponse,abandonedBodiesNotReRead};
