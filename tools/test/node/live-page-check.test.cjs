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
  let i=0;const page={rowsAt:null,shownAt:[],on(){},waitForTimeout:ms=>new Promise(r=>setTimeout(r,Math.min(ms,5))),
    evaluate:async()=>{const n=i++;if(page.rowsAt===null&&fs.existsSync(path.join(control,'rows')))page.rowsAt=n;page.shownAt.push(n);return states[Math.min(n,states.length-1)];}};
  return page;
}
// The script's lines: each message once the condition before it holds.
function scriptedLines(steps){return {poll:()=>{if(steps.length&&steps[0][0]()){return steps.shift()[1];}}};}
async function stopAfter(states,messages){
  const {awaitStop}=require('./live-page-check.cjs');
  const control=fs.mkdtempSync(path.join(os.tmpdir(),'wstx-live-page-check-'));
  try{
    const page=scriptedPage(states,control),watch=watchPage(page);
    await watch.sample();
    const rows=()=>fs.existsSync(path.join(control,'rows'));
    const result=await awaitStop({watch,lines:scriptedLines(messages(rows)),control,clean:()=>{},wait:1000,pause:ms=>page.waitForTimeout(ms)});
    return {...result,page,rows:rows()};
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

test('the live page check without rows of the raised generation within the wait: not exercised, naming the wait, and the stop goes on',async()=>{
  const a=row('12:00:00','CQ K1ABC FN42');
  const done=await stopAfter([shown(1,[a]),shown(2,[a])],rows=>[[()=>true,{selected:{generation:1,ms:1000}}],[rows,{stopping:true}]]);
  assert.deepEqual(done.message,{stopping:true},'the restart is made');
  assert.deepEqual(done.unexercised,['no rows of a generation above 1 on the page within 1 s of the band selection']);
  const {exerciseMissing}=require('./live-page-check.cjs');
  assert.match(exerciseMissing(done.unexercised,2,1,true).join('\n'),/^restart generation: no rows of a generation above 1/,'never green');
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
