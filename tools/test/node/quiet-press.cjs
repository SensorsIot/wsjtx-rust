'use strict';
// The quiet check of a press that must reach no station: the press causes no request and no
// WebSocket frame of the page. The window of quiet opens only after the requests of the prepared
// state, the lookup that `lookup` names among them, have reached the test and finished; a request
// or frame inside the window still fails.
const assert=require('node:assert/strict');

// Watches `page` (before its navigation): every request's method and path, every WebSocket frame
// it sends, and the end of the lookup.
function quietPress(page,{lookup}){
  const requests=[],sent=[];
  let lookupDone;const lookupFinished=new Promise(r=>{lookupDone=r;});
  page.on('request',r=>requests.push(`${r.method()} ${new URL(r.url()).pathname}`));
  page.on('websocket',ws=>ws.on('framesent',frame=>sent.push(JSON.parse(frame.payload))));
  for(const event of ['requestfinished','requestfailed'])page.on(event,r=>{if(lookup(r))lookupDone();});
  return {requests,sent,
    // The window of quiet opens only after that lookup has reached the test and finished.
    opened:async()=>{let timer;await Promise.race([lookupFinished,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('the partner DXCC lookup did not finish')),15000);})]).finally(()=>clearTimeout(timer));},
    // The button's press causes no station request and no WebSocket frame.
    quiet:async(action,label)=>{const r=requests.length,s=sent.length;await action();await page.waitForTimeout(300);
      assert.deepEqual(requests.slice(r),[],`${label}: no station request`);assert.deepEqual(sent.slice(s),[],`${label}: no WebSocket frame`);},
  };
}

module.exports={quietPress};
