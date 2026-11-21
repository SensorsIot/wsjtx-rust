'use strict';
// The tests of the live page check (live-page-check.cjs): its decisions and its wait before
// the stop, on scripted pages; no station.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {watchPage}=require('./page-watch.cjs');

// The live check's two decisions, without a station: what the page may send, and when it is green.
test('the live page check lets the page send only reads and is green only with both triggers',()=>{
  const {allowed,missingTriggers}=require('./live-page-check.cjs');
  const origin='https://192.168.0.37:18081',at=p=>new URL(origin+p);
  assert.equal(allowed('GET',at('/receive'),origin),'pass');
  for(const p of ['/contact/worked','/strategy/evaluate','/authorization/v1/status'])assert.equal(allowed('POST',at(p),origin),'pass',p);
  for(const p of ['/transmit/command','/transmit/halt','/contact/command','/automation/command','/receive/select','/receive/start','/radio/operation','/radio/settings/apply','/radio/tx-level','/profile','/session'])
    assert.equal(allowed(p==='/profile'?'PUT':'POST',at(p),origin),'refuse',p);
  assert.equal(allowed('GET',new URL('https://example.org/x'),origin),'abort');
  assert.equal(allowed('GET',new URL('https://192.168.0.37:18082/receive'),origin),'abort');
  assert.equal(allowed('GET',at('/authorization.js'),origin),'stub');
  assert.deepEqual(missingTriggers(2,null,true),[],'no job yet on the new boot');
  assert.deepEqual(missingTriggers(2,1,true),[],'below the old generation');
  assert.equal(missingTriggers(1,1,true).length,1,'an equal generation is not the restart-generation window');
  assert.equal(missingTriggers(null,null,true).length,1,'no old generation seen');
  assert.equal(missingTriggers(2,null,false).length,1,'the worked-before tip needs a worked-before kept row');
});

// The live check's wait between its band selection and the stop, on a scripted page.
const row=(when,message)=>({period:'latest',tip:null,when,message,sender:message.split(' ')[1],partner:false});
const shown=(generation,rows)=>({text:'',heading:'',attributes:[],rows,band:'20m',on:'1',boot:'b1',state:'connected',job:'j',generation});
// A page that shows each of `states` once per sample and stays on the last; `rowsAt` is the first
// sample taken once <control>/rows exists.
function scriptedPage(states,control){
  let i=0;const page={rowsAt:null,shownAt:[],navigations:[],on(){},waitForTimeout:ms=>new Promise(r=>setTimeout(r,Math.min(ms,5))),
    goto:async url=>{page.navigations.push(`goto ${url}`);},reload:async()=>{page.navigations.push('reload');},
    context:()=>({newPage:async()=>{page.navigations.push('new page');}}),
    evaluate:async()=>{const n=i++;if(page.rowsAt===null&&fs.existsSync(path.join(control,'rows')))page.rowsAt=n;page.shownAt.push(n);return states[Math.min(n,states.length-1)];}};
  return page;
}
// The script's lines: each message once the condition before it holds.
function scriptedLines(steps){return {poll:()=>{if(steps.length&&steps[0][0]()){return steps.shift()[1];}}};}
async function stopAfter(states,messages,station,renew){
  const {awaitStop}=require('./live-page-check.cjs');
  const control=fs.mkdtempSync(path.join(os.tmpdir(),'wstx-live-page-check-'));
  try{
    const page=scriptedPage(states,control),watch=watchPage(page);
    await watch.sample();
    const rows=()=>fs.existsSync(path.join(control,'rows'));
    let reads=0;
    const result=await awaitStop({watch,lines:scriptedLines(messages(rows)),control,clean:()=>{},wait:1000,pause:ms=>page.waitForTimeout(ms),...station&&{station:()=>{reads++;return station();}},...renew&&{renew}});
    return {...result,page,rows:rows(),reads};
  }finally{fs.rmSync(control,{recursive:true,force:true});}
}

test('the live page check lets the station stop only after a raised generation with new rows',async()=>{
  const {raisedWithRows}=require('./live-page-check.cjs');
  const a=row('12:00:00','CQ K1ABC FN42'),b=row('12:00:30','CQ F5RRS JN18'),known=new Set(['12:00:00 CQ K1ABC FN42']);
  assert.equal(raisedWithRows(shown(1,[a,b]),1,known),false,'an equal generation, even with new rows');
  assert.equal(raisedWithRows(shown(2,[a]),1,known),false,'a raised generation with only the rows seen before');
  assert.equal(raisedWithRows(shown(2,[]),1,known),false,'a raised generation without rows');
  assert.equal(raisedWithRows(shown(2,[a,b]),1,known),true);
  // Selected at generation 1: the page shows generation 2 without rows, then with a new row (sample 4).
  const states=[shown(1,[a]),shown(1,[a]),shown(2,[]),shown(2,[]),shown(2,[a,b])];
  const done=await stopAfter(states,rows=>[[()=>true,{selected:{generation:1,ms:30000}}],[rows,{stopping:true}]]);
  assert.deepEqual(done.message,{stopping:true});
  assert.deepEqual(done.unexercised,[]);
  assert.equal(done.last.generation,2);
  assert.ok(done.page.rowsAt>4,`rows reported at sample ${done.page.rowsAt}, the new row first shown at sample 4`);
});

// The page's side of a wait that runs out: its generation, job state, receive status and notice.
const status='Audio running · FT8 running';
const page=(generation,rows,more={})=>({...shown(generation,rows),jobState:'running',status,notice:false,...more});
const waitOut=rows=>[[()=>true,{selected:{generation:1,ms:1000}}],[rows,{stopping:true}]];
const WAITED='no rows of a generation above 1 on the page within 1 s of the band selection';

test('the live page check without rows of the raised generation within the wait: not exercised, naming what the station and the page showed, and the stop goes on',async()=>{
  const a=row('12:00:00','CQ K1ABC FN42');
  const done=await stopAfter([page(1,[a])],waitOut,async()=>({generation:2,job:'running'}));
  assert.deepEqual(done.message,{stopping:true},'the restart is made');
  assert.deepEqual(done.unexercised,[`${WAITED}: station generation 2, job running; page generation 1, job running; receive status "${status}"; station-data notice not shown`]);
  assert.equal(done.reads,1,'the station is read once, when the wait runs out');
  const {exerciseMissing}=require('./live-page-check.cjs');
  assert.match(exerciseMissing(done.unexercised,2,1,true).join('\n'),/^restart generation: no rows of a generation above 1/,'never green');
  // A shown notice and a status over several lines still give one line.
  const noticed=await stopAfter([page(1,[a],{notice:true,status:'Audio running\n · FT8 running'})],waitOut,async()=>({generation:2,job:'running'}));
  assert.deepEqual(noticed.unexercised,[`${WAITED}: station generation 2, job running; page generation 1, job running; receive status "${status}"; station-data notice shown`]);
});

test('the live page check with the station unreadable when the wait runs out: the reason says so and names the page\'s side',async()=>{
  const a=row('12:00:00','CQ K1ABC FN42');
  for(const station of [async()=>{throw new Error('HTTP 401 wstx_session_p=secret');},async()=>null,async()=>({error:{code:'busy'}})]){
    const done=await stopAfter([page(1,[a])],waitOut,station);
    assert.deepEqual(done.message,{stopping:true},'the restart is made');
    assert.deepEqual(done.unexercised,[`${WAITED}: the station could not be read; page generation 1, job running; receive status "${status}"; station-data notice not shown`]);
  }
});

test('the live page check with the page\'s live absent when the wait runs out: the page\'s generation is none',async()=>{
  const done=await stopAfter([page(null,[],{jobState:null,status:'Live receive unavailable until station snapshot'})],waitOut,async()=>({generation:2,job:'running'}));
  assert.deepEqual(done.message,{stopping:true},'the restart is made');
  assert.deepEqual(done.unexercised,[`${WAITED}: station generation 2, job running; page generation none, job none; receive status "Live receive unavailable until station snapshot"; station-data notice not shown`]);
});

// The station keeps one session per grant: when the script's new login replaced the page's
// session before the stop, the page takes the new one and the wait goes on.
test('the live page check takes a session that replaced the page\'s before the stop, and waits on',async()=>{
  const a=row('12:00:00','CQ K1ABC FN42'),b=row('12:00:30','CQ F5RRS JN18'),renewed=[];
  const cookies=[{name:'wstx_session_p',value:'v'}];
  const done=await stopAfter([...Array(6).fill(page(1,[a])),page(2,[a,b])],rows=>[[()=>true,{cookies}],[()=>true,{selected:{generation:1,ms:30000}}],[rows,{stopping:true}]],async()=>({generation:2,job:'running'}),async c=>{renewed.push(c);});
  assert.deepEqual(renewed,[cookies]);
  assert.deepEqual(done.message,{stopping:true});
  assert.deepEqual(done.unexercised,[]);
  assert.equal(done.last.generation,2);
});

test('the live page check never works around a page stuck at the old generation',async()=>{
  const a=row('12:00:00','CQ K1ABC FN42'),b=row('12:00:15','CQ F5RRS JN18');
  // New rows keep coming, but the page stays at the generation of the selection.
  const done=await stopAfter([page(1,[a]),page(1,[a,b])],waitOut,async()=>({generation:2,job:'running'}));
  assert.deepEqual(done.page.navigations,[],'no reload, no navigation and no second page');
  assert.equal(done.reads,1,'the station is read only for the reason, after the wait');
  assert.equal(done.unexercised.length,1);
  assert.match(done.unexercised[0],/^no rows of a generation above 1 on the page within 1 s of the band selection: /);
  const {exerciseMissing}=require('./live-page-check.cjs');
  assert.ok(exerciseMissing(done.unexercised,1,null,true).length>0,'never green');
});

test('the live page check is never green after a band selection not made or not taken',async()=>{
  const {exerciseMissing}=require('./live-page-check.cjs');
  const why='no band selection: Monitor off at startup is set';
  const done=await stopAfter([shown(1,[row('12:00:00','CQ K1ABC FN42')])],()=>[[()=>true,{unexercised:why}],[()=>true,{stopping:true}]]);
  assert.deepEqual(done.message,{stopping:true});
  assert.deepEqual(done.unexercised,[why]);
  assert.equal(done.rows,false,'no wait for rows without a selection');
  // The new boot without a job is the restart-generation window by the generations alone, but nothing was selected.
  assert.deepEqual(exerciseMissing([why],1,null,true),[`restart generation: ${why}`]);
  assert.deepEqual(exerciseMissing([],2,1,true),[],'a selection that took, generations old 2 and new 1');
});
