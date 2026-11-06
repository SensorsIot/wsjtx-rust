'use strict';
// Cost 2, timing suite contact-thin: launched by
// contact_http_tests::contact_thin_tests::contact_thin_link_two_clients, which serves the
// actual router (contact engine, logbook, #9 transmit owner on the recording hardware double;
// no audio, PTT or radio)
// over actual rustls TLS on 127.0.0.2 behind this file's tests/support.cjs link simulator
// (4000 B/s = 32 kbit/s per direction, 150 ms one way = 300 ms RTT, headers modelled, not
// captured). Decoded rows are hand-authored and published through a test-only control peer
// that is not on the counted link. The expected values are the TC-007-005 bounds.
// Proves: CL-010-06, CL-010-08, CL-010-15; TC-007-005 thin link and local presentation, two clients.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const {performance}=require('node:perf_hooks');
const {chromium}=require('playwright');
const {link,loginPage}=require('./support.cjs');

const control=process.env.WSTX_THIN_CONTACT_CONTROL,token=process.env.WSTX_THIN_CONTACT_TOKEN;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const waitUntil=async deadline=>{while(performance.now()<deadline)await sleep(Math.max(1,Math.ceil(deadline-performance.now())));};
const publish=async(period_ms,rows)=>{const r=await fetch(control+'/publish',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({period_ms,rows})});assert.equal(r.status,200);return r.json();};
// Distinct standard calls (K/W/N + digit + three letters), packable by the real codec.
const call=n=>`${'KWN'[n%3]}${Math.floor(n/3)%10}${String.fromCharCode(65+Math.floor(n/30)%26)}${String.fromCharCode(65+Math.floor(n/780)%26)}${String.fromCharCode(65+n%26)}`;
const cqs=(from,count)=>Array.from({length:count},(_,i)=>({text:`CQ ${call(from+i)} FN42`,hz:300+((from+i)*37)%2500,snr:-20+(i%25)}));
async function display(page,value){if(!await page.locator('#settings-drawer').isVisible())await page.locator('#open-server-settings').click();await page.selectOption('#display-profile',value);await page.locator('#settings-drawer .return-operate').click();}

if(!process.env.WSTX_THIN_CONTACT_FIXTURE){
  test('TC-007-005 runs only through contact_http_tests::contact_thin_tests::contact_thin_link_two_clients',{skip:'launched by the Rust fixture'},()=>{});
}else test('TC-007-005 two clients on the 32 kbit/s 300 ms TLS link: tick and contact.state pacing, bounded worked-before, log traffic, byte budgets and local presentation',{timeout:760000},async t=>{
  assert.ok(control&&token,'control peer and token are mandatory');
  const proxy=await link({host:'127.0.0.2',port:1});proxy.target.port=proxy.port;t.after(()=>proxy.close());
  process.stdout.write(`WSTX_THIN_CONTACT_PROXY ${proxy.port}\n`);
  await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('fixture READY deadline')),30000);process.stdin.once('data',d=>{clearTimeout(timer);d.toString().trim()==='READY'?resolve():reject(new Error('invalid fixture handshake'));});});
  const origin=`https://localhost:${proxy.port}`,browser=await chromium.launch();t.after(()=>browser.close());
  const report={startedUtc:new Date().toISOString(),model:'actual rustls TLS streams plus unchanged support.cjs shared 4000 B/s, 150 ms one-way, 80+80 B per 512 B segment',phases:{}};
  const save=async()=>{await fs.mkdir('test-results/contact-thin',{recursive:true});await fs.writeFile('test-results/contact-thin/link.json',JSON.stringify(report,null,2));};
  t.after(async()=>{report.serverSocketCloses=await fetch(control+'/socket-closes').then(r=>r.json(),e=>e.message);report.recorder=seen.map(s=>({sockets:s.sockets,requests:s.requests.map(r=>[r.method,r.path,Math.round(r.at),r.end===null?null:Math.round(r.end),r.failed??null,r.bytes??null,r.status??null]),ticks:s.ticks.length,states:s.states.map(x=>[Math.round(x.at),x.revision])}));report.counters={...proxy.counters};await save();});
  // The request recorder: every HTTP request of each page (start/end), every WebSocket frame
  // sent and every station.tick/contact.state received, on the browser's own clock.
  // Every TC-007-005 bound is checked and the run continues, so that one run measures all of
  // them; any missed bound fails the test at the end with the list (no bound is loosened).
  const pages=[],seen=[],errors=[],missed=[];
  // WebSocket bytes per event type, and the most state bytes in any 2 s: a push must not recreate the read burst.
  const frameBytes=frames=>{const byType={};for(const f of frames)byType[f.type]=(byType[f.type]??0)+f.bytes;const state=frames.filter(f=>/[.]state$/.test(f.type));let most=0;for(const f of state){const n=state.filter(o=>o.at>=f.at&&o.at<f.at+2000).reduce((sum,o)=>sum+o.bytes,0);if(n>most)most=n;}return {byType,mostStateBytesIn2s:most};};
  report.missed=missed;const bound=(ok,message)=>{if(!ok){missed.push(message);console.log(`BOUND MISSED: ${message}`);}};
  for(let i=0;i<2;i++){
    const context=await browser.newContext({ignoreHTTPSErrors:true,viewport:{width:1440,height:900},acceptDownloads:true});t.after(()=>context.close());
    const page=await context.newPage();pages.push(page);
    const s={requests:[],sent:[],ticks:[],states:[],events:[],loads:[],sockets:[],frames:[]};seen.push(s);
    // Every socket's end: who closed it, with what, and the connection states around it (#10).
    await page.exposeFunction('__socketEvent',e=>{s.sockets.push({...e,at:Math.round(performance.now()),utc:Date.now()});});
    await page.addInitScript(()=>{
      const W=WebSocket;
      window.WebSocket=class extends W{
        constructor(...args){super(...args);__socketEvent({type:'open'});this.addEventListener('close',e=>__socketEvent({type:'closed',code:e.code,reason:e.reason,clean:e.wasClean}));}
        close(...args){__socketEvent({type:'close-called',caller:new Error().stack.split(String.fromCharCode(10)).slice(2,6).map(l=>l.trim().replace(/https?:[/][/][^/]+/,'')).join(' < ')});super.close(...args);}
      };
      addEventListener('DOMContentLoaded',()=>{const node=document.querySelector('#connection');if(node)new MutationObserver(()=>__socketEvent({type:'state',state:node.dataset.state})).observe(node,{attributes:true,attributeFilter:['data-state']});});
    });
    page.on('pageerror',e=>errors.push(`${i}: ${e.message}`));
    page.on('load',()=>s.loads.push(performance.now()));
    page.on('request',r=>{const u=new URL(r.url());if(u.origin!==origin)return;const e={method:r.method(),path:u.pathname,body:r.postData(),at:performance.now(),end:null};s.requests.push(e);r.__e=e;});
    page.on('response',x=>{const e=x.request().__e;if(e)e.status=x.status();});
    page.on('requestfinished',r=>{if(r.__e){r.__e.end=performance.now();r.sizes().then(z=>{r.__e.bytes=z.responseBodySize+z.responseHeadersSize;}).catch(()=>{});}});
    page.on('requestfailed',r=>{if(r.__e){r.__e.end=performance.now();r.__e.failed=r.failure()?.errorText??'failed';}});
    page.on('websocket',ws=>{
      ws.on('framesent',f=>{try{const m=JSON.parse(f.payload);s.sent.push({at:performance.now(),type:m.type});}catch{s.sent.push({at:performance.now(),type:'binary'});}});
      ws.on('framereceived',f=>{let m;try{m=JSON.parse(f.payload);}catch{return;}const at=performance.now(),bytes=Buffer.byteLength(f.payload);s.frames.push({at,type:m.type,bytes});
        if(['transmit.state','receive.state','contact.state'].includes(m.type))s.events.push({at,type:m.type});
        if(m.type==='station.tick')s.ticks.push({at,bytes,utc:m.data.utc_ms,transmitting:m.data.transmitting});
        else if(m.type==='contact.state')s.states.push({at,bytes,revision:m.data.contact_revision});});
    });
  }
  const between=(list,a,b)=>list.filter(x=>x.at>=a&&x.at<b);
  // Per page: one operator at a time (status refresh, log and contact actions share the drawer).
  const lanes=pages.map(()=>Promise.resolve());
  const act=(i,work)=>{const run=lanes[i].then(work);lanes[i]=run.catch(()=>{});return run;};
  const latencies=[];
  // Timed from the explicit status request (Settings > Refresh status) to its display.
  // The drawer is not opened for it: opening Settings reads the station's settings, which is
  // operator traffic of its own and not part of a status read.
  const status=async(i)=>act(i,async()=>{const p=pages[i],old=await p.locator('#updated').textContent(),began=performance.now();await p.locator('#refresh').evaluate(b=>b.click());const shown=await p.waitForFunction(v=>document.querySelector('#updated').textContent!==v,old,{timeout:15000}).then(()=>true,()=>false);const ms=shown?performance.now()-began:Infinity;latencies.push(ms);bound(ms<=2000,`connected status ${ms} ms`);});

  // ---- Cold load: both uncached browsers enroll through the real token form (CL-022-01).
  const coldStart=performance.now();
  await Promise.all(pages.map(async p=>{await loginPage(p,origin,token,230000);await p.waitForFunction(()=>!!window.wstxContact&&!!window.wstxLogbook,null,{timeout:230000});await display(p,'thin');}));
  report.cold={ms:performance.now()-coldStart,counters:{...proxy.counters}};await save();

  // ---- First status after page load: each client loads the page again (retained-key proof,
  // every asset is no-store) while the other stays connected on the shared link.
  const reloads=[];
  for(const [i,p]of pages.entries()){
    const loadsBefore=seen[i].loads.length,requestsBefore=seen[i].requests.length;
    await p.goto(origin,{timeout:120000});await p.locator('#connection[data-state=connected]').waitFor({timeout:60000});const connected=performance.now();
    const load=seen[i].loads[loadsBefore];await p.waitForFunction(()=>!!window.wstxContact&&!!window.wstxLogbook,null,{timeout:120000});
    reloads.push({firstStatusAfterLoadMs:connected-load,display:await p.inputValue('#display-profile'),requests:seen[i].requests.slice(requestsBefore).map(r=>({route:`${r.method} ${r.path}`,startMs:Math.round(r.at-load),endMs:r.end===null?null:Math.round(r.end-load)}))});
  }
  report.reload=reloads;await save();
  for(const r of reloads){bound(r.firstStatusAfterLoadMs<=10000,`first status ${r.firstStatusAfterLoadMs} ms after page load`);assert.equal(r.display,'thin','the explicit Thin choice survives the reload');}

  // ---- Detailed: station.tick once per second per client, and one bounded worked-before
  // query for a period of 71 distinct CQ callers (Detailed fetches a published view at once;
  // Thin and Off read at most one record per 4 s, CL-057-01).
  for(const p of pages)await display(p,'detail');
  await sleep(3000);
  {const start=performance.now(),wall0=Date.now();
    await publish(Math.floor(Date.now()/15000)*15000-15000,cqs(0,71));
    await waitUntil(start+15000);const wall1=Date.now();
    for(const [i,p]of pages.entries())await p.waitForFunction(()=>document.querySelectorAll('#band-activity tbody tr[data-sequence]').length>=71&&document.querySelector('#band-activity tbody tr[data-worked]'),null,{timeout:60000}).catch(async e=>{throw new Error(`client ${i}: ${await p.locator('#band-activity tbody tr[data-sequence]').count()} rows; ${JSON.stringify(await p.evaluate(async()=>({state:typeof operatingState==='undefined'?'undef':operatingState&&{selection:operatingState.selection,control:operatingState.control},fetched:await (await stationFetch('/receive/selection')).text(),mode:live?.job?.mode,cursor:resultCursor,status:document.querySelector('#operating-status')?.textContent})))}; worked ${JSON.stringify(seen[i].requests.filter(r=>r.path==='/contact/worked').map(r=>[r.body,r.end,r.failed]))}; ${e.message}`);});
    await sleep(3000);const end=performance.now();
    // Counted by the station time each tick carries: link queueing shifts arrival, not cadence.
    const d=seen.map(s=>s.ticks.filter(k=>k.utc>=wall0&&k.utc<wall1)),worked=seen.map(s=>between(s.requests,start,end).filter(r=>r.path==='/contact/worked').map(r=>JSON.parse(r.body).calls.length));
    report.phases.detailed={seconds:(wall1-wall0)/1000,start:Math.round(start),end:Math.round(end),ticks:d.map(x=>x.length),utcSpacingMs:d.map(x=>x.slice(1).map((k,n)=>k.utc-x[n].utc)),worked};await save();
    for(const x of d){bound(x.length>=Math.floor((wall1-wall0)/1000)-1&&x.length<=Math.ceil((wall1-wall0)/1000)+1,`Detailed ticks in ${(wall1-wall0)/1000} s: ${x.length}`);for(let n=1;n<x.length;n++)bound(x[n].utc-x[n-1].utc>=900,`Detailed tick spacing ${x[n].utc-x[n-1].utc} ms`);for(const k of x)bound(k.bytes<=224,`station.tick ${k.bytes} bytes`);}
    for(const [i,w]of worked.entries())bound(w.length===1&&w[0]===64,`client ${i}: worked-before queries for the 71-call period ${JSON.stringify(w)}`);
  }

  // ---- Local presentation: with those 71 rows shown and the station quiet, a baseline window
  // and an equally long window of sorting, colour filtering, resizing, pane switching and scrolling.
  await sleep(2000);
  // Opening Settings reads the station's settings (cty.dat, UDP, clock, ...): the drawer is
  // opened before the baseline, so only its local colour choices fall in the action window.
  for(const p of pages)await p.locator('#open-server-settings').click();
  await sleep(6000);
  const base0=performance.now();await sleep(8000);const base1=performance.now();
  const local=async p=>{
    const slot=p.locator('#band-colours [data-hl-slot=new_call]');assert.equal(await slot.count(),1,'the New call colour slot');
    await slot.uncheck();await slot.check();await p.locator('#settings-drawer .return-operate').click();
    for(const key of ['signal','frequency','message','dt','value'])await p.locator(`#band-activity th[data-sort=${key}]`).click();
    await p.locator('#band-activity .op-table-wrap').evaluate(e=>{e.scrollTop=e.scrollHeight;});
    await p.locator('#rx-focus').evaluate(e=>{e.scrollTop=e.scrollHeight;e.querySelectorAll('*').forEach(c=>{if(c.scrollHeight>c.clientHeight)c.scrollTop=c.scrollHeight;});});
    await p.setViewportSize({width:1000,height:760});await sleep(300);await p.setViewportSize({width:1440,height:900});
    await p.locator('#station-bar [data-region=help]').click();await p.locator('#region-help').waitFor();await p.locator('#region-help .return-operate').click();
    await p.locator('#band-activity .op-table-wrap').evaluate(e=>{e.scrollTop=0;});
  };
  await Promise.all(pages.map(local));const act1=Math.max(performance.now(),base1+8000);await waitUntil(act1);
  // A second idle window after the actions: a background poll slower than one window shows in
  // at least one of the two.
  const after1=act1+(act1-base1);await waitUntil(after1);
  const presentation=seen.map(s=>{const routes=list=>list.reduce((m,r)=>(m[`${r.method} ${r.path}`]=(m[`${r.method} ${r.path}`]??0)+1,m),{});
    // Only the reads still announced by an event: transmit, contact and selection state are carried.
    const announcer={'/receive':'receive.state','/receive/results':'receive.state'};
    const reason=r=>{const previous=s.requests.filter(q=>q.path===r.path&&q.method===r.method&&q.at<r.at).at(-1);
      if(s.events.some(e=>e.type===announcer[r.path]&&e.at<=r.at&&r.at-e.at<=2000))return 'announcement';
      // Only the read with a declared 30 s safety cadence (PushedStationState), at that cadence.
      return r.method==='GET'&&r.path==='/receive/results'&&!!previous&&r.at-previous.at>=29500&&r.at-previous.at<=33000?'safety':'none';};
    // The baseline holds what the idle windows do by themselves: a read an announcement or the safety cadence explains is no baseline for an action.
    const own=(a,b)=>routes(between(s.requests,a,b).filter(r=>reason(r)==='none'));
    const before=own(base0,base1),later=own(act1,after1),baseline={};for(const k of new Set([...Object.keys(before),...Object.keys(later)]))baseline[k]=Math.max(before[k]??0,later[k]??0);
    const unexplained={},explained=[];for(const r of between(s.requests,base1,act1)){const key=`${r.method} ${r.path}`,why=reason(r);
      explained.push({route:key,at:Math.round(r.at-base1),reason:why});
      if(why==='none')unexplained[key]=(unexplained[key]??0)+1;}
    return {baseline,before,after:later,unexplained,explained,actions:routes(between(s.requests,base1,act1)),sentBaseline:[...between(s.sent,base0,base1),...between(s.sent,act1,after1)].map(f=>f.type),sentActions:between(s.sent,base1,act1).map(f=>f.type),seconds:[(base1-base0)/1000,(act1-base1)/1000]};});
  report.phases.presentation=presentation;await save();
  for(const p of presentation){
    for(const [route,count]of Object.entries(p.actions)){
      bound(route.startsWith('GET '),`local presentation sent ${route}`);
      // A read the idle windows lack is the station's, not the presentation's, only if an
      // announcement event preceded it by at most 2 s or it is a /receive/results safety
      // read 29.5-33 s after the previous read of that route.
      const unexplained=p.unexplained[route]??0;
      bound(p.baseline[route]!==undefined||unexplained===0,`local presentation added ${route}, absent from both idle windows (${unexplained} unexplained)`);
      bound(p.baseline[route]===undefined||unexplained<=p.baseline[route]+1,`local presentation added ${route}: ${count} (${unexplained} unexplained) vs baseline ${p.baseline[route]}`);
    }
    for(const type of p.sentActions)bound(p.sentBaseline.includes(type),`local presentation sent a ${type} frame`);
  }

  for(const p of pages)await display(p,'thin');
  await sleep(5000);

  // ---- Active Thin window: published periods, one contact, contact revision churn, log
  // page/update/export and status reads on both clients. It starts on an odd period.
  await sleep((15000-Date.now()%30000+30000)%30000+300);
  const seconds=80,start=performance.now(),wall=Date.now(),baseline={...proxy.counters};
  const E0=Math.floor(wall/30000)*30000; // the even period that has just ended
  assert.equal(((E0%30000)+30000)%30000,0,'the window starts after an even period');
  const publishes=[];const at=s=>start+s*1000;
  const period=async(s,startMs,rows)=>{await waitUntil(at(s));publishes.push({at:performance.now(),rows:rows.length,calls:new Set(rows.map(r=>r.text.split(' ')[1])).size,names:rows.map(r=>r.text.split(' ')[1])});await publish(startMs,rows);};
  report.phases.thin={state:'running',seconds};await save();
  // The station's published periods run on their own schedule; operator steps that cannot
  // complete on the link are recorded as missed bounds and the measurement goes on.
  const soft=(label,work)=>work().catch(e=>bound(false,`${label}: ${e.message.split(String.fromCharCode(10))[0]}`));
  const publisher=(async()=>{
    // Small periods: Thin reads one record per 4 s (CL-057-01), the contact rows first.
    await period(0,E0,[{text:'CQ K1ABC FN42',hz:1234.6,snr:-12},...cqs(80,2)]);
    await period(15,E0+15000,cqs(100,3));
    await period(30,E0+30000,[{text:'HB9BLA K1ABC -05',hz:1240,snr:-7},...cqs(120,2)]);
    await period(45,E0+45000,cqs(140,3));
    await period(60,E0+60000,[{text:'HB9BLA K1ABC RR73',hz:1240,snr:-6},...cqs(160,2)]);
  })();
  const contactRun=(async()=>{
    await waitUntil(at(0.5));
    await soft('reply to CQ K1ABC',()=>act(0,async()=>{const row=pages[0].locator('#band-activity tbody tr[data-sequence]').filter({hasText:'CQ K1ABC FN42'});await row.waitFor({timeout:12000});await row.dblclick();await pages[0].waitForFunction(()=>window.wstxContact.snapshot()?.transmit?.arm_state==='armed',null,{timeout:30000});}));
    // Contact revision churn far above 1/s, made by the station's control peer (not on the
    // counted link): 20 Hold Tx revisions 100 ms apart.
    await waitUntil(at(8));const churnStart=performance.now();
    const churned=await (await fetch(control+'/churn',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({count:20,interval_ms:100})})).json();
    report.churn={start:churnStart,end:performance.now(),revisions:churned.after-churned.before,last:churned.after};
  })();
  const logRun=(async()=>{
    await waitUntil(at(20));
    await soft('log page and export',()=>act(1,async()=>{const p=pages[1];await p.locator('#station-bar [data-region="logbook"]').click();await p.waitForFunction(()=>!['History not loaded','Loading history'].includes(document.querySelector('#log-history-status').textContent),null,{timeout:45000}).catch(async e=>{throw new Error(`log page: ${await p.locator('#log-history-status').textContent()}; visible ${await p.locator('#region-logbook').isVisible()}; ${e.message}`);});
      report.logPage=await p.locator('#log-history-status').textContent();bound(!/unavailable/.test(report.logPage),`log page ${report.logPage}`);
      const [download]=await Promise.all([p.waitForEvent('download',{timeout:20000}),p.getByRole('button',{name:'Export ADIF'}).click()]);assert.equal(download.suggestedFilename(),'contacts.adi');
      await p.locator('#region-logbook .return-operate').click();}));
    await waitUntil(at(35));
    await soft('log update',()=>act(1,async()=>{const p=pages[1];await p.locator('#open-server-settings').click();await p.locator('#tab-logging').click();
      const adi='Log4OM 2 export\n<ADIF_VER:5>3.1.0 <PROGRAMID:7>LOG4OM2 <eoh>\n<CALL:6>DL1ABC <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20261031 <TIME_ON:6>123100 <eor>\n<CALL:5>W9XYZ <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20261030 <TIME_ON:6>101500 <eor>\n';
      await p.locator('#log-import-file').setInputFiles({name:'other.adi',mimeType:'text/plain',buffer:Buffer.from(adi)});await p.locator('#settings-update-log').getByRole('button',{name:'Update logbook'}).click();
      await p.waitForFunction(()=>/^(Logbook updated|Logbook not updated|Update outcome unknown)/.test(document.querySelector('#log-import-status').textContent),null,{timeout:60000}).catch(async e=>{throw new Error(`log update: ${await p.locator('#log-import-status').textContent()}; ${e.message}`);});
      report.logUpdate=await p.locator('#log-import-status').textContent();bound(/^Logbook updated: 2 added/.test(report.logUpdate),`log update ${report.logUpdate}`);await p.locator('#settings-drawer .return-operate').click();}));
  })();
  const statusRun=(async()=>{for(let n=1;n<=14;n++){await waitUntil(start+n*5500);await Promise.all([status(0),status(1)]);}})();
  await Promise.all([publisher,contactRun,logRun,statusRun]);
  // The contact completes after the Tx5 of the odd period that follows RR73 (and logs itself).
  await soft('contact completed',()=>pages[0].waitForFunction(()=>window.wstxContact.snapshot()?.contact?.state==='completed',null,{timeout:Math.max(1000,at(seconds)-performance.now())}));
  await waitUntil(at(seconds));const end=performance.now(),span=(end-start)/1000;
  const traffic={up:(proxy.counters.up-baseline.up)/span,down:(proxy.counters.down-baseline.down)/span};
  const thin=seen.map((s,i)=>{
    const requests=between(s.requests,start,end),worked=requests.filter(r=>r.path==='/contact/worked').map(r=>({at:r.at,calls:JSON.parse(r.body).calls.length,names:JSON.parse(r.body).calls}));
    // A query belongs to the period whose calls it asks about: on the link it can arrive after the next period starts.
    const perPeriod=publishes.map((p,n)=>{const own=p.names.filter(c=>publishes.every((o,m)=>m===n||!o.names.includes(c)));return worked.filter(q=>q.names.some(c=>own.includes(c))).length;});
    const gets=s.requests.filter(r=>r.method==='GET'&&r.path==='/contact'&&r.at<end&&(r.end??end)>start&&(r.end!==null||r.at>=start)); // a read an earlier reload dropped has no end event
    const edges=gets.flatMap(r=>[[r.at,1],[r.end??end,-1]]).sort((a,b)=>a[0]-b[0]||a[1]-b[1]);let open=0,maxPending=0;for(const [,d]of edges){open+=d;maxPending=Math.max(maxPending,open);}
    const ticks=s.ticks.filter(k=>k.utc>=wall&&k.utc<wall+span*1000),states=between(s.states,start,end);
    const churnStates=report.churn?between(s.states,report.churn.start,report.churn.end+2500).length:null;
    return {worked,perPeriod,maxPendingContactGets:maxPending,contactGets:gets.length,ticks:ticks.length,tickUtcSpacingMs:ticks.slice(1).map((k,n)=>k.utc-ticks[n].utc),tickTransmitting:ticks.map(k=>k.transmitting),states:states.length,stateSpacingMs:states.slice(1).map((x,n)=>Math.round(x.at-states[n].at)),churnStates,maxStateBytes:Math.max(0,...states.map(x=>x.bytes)),maxTickBytes:Math.max(0,...ticks.map(x=>x.bytes)),routes:requests.reduce((m,r)=>(m[`${r.method} ${r.path}`]=(m[`${r.method} ${r.path}`]??0)+1,m),{})};
  });
  report.phases.thin={state:'checking',seconds:span,frames:seen.map(s=>frameBytes(between(s.frames,start,end))),sharedBytesPerSecond:traffic,statusMs:latencies.slice(),publishes,churn:report.churn,clients:thin};await save();
  console.log(`Thin ${span.toFixed(1)} s ${JSON.stringify(traffic)}`);
  bound(traffic.up<=3000,`Thin counted uplink ${traffic.up} B/s`);bound(traffic.down<=3000,`Thin counted downlink ${traffic.down} B/s`);
  assert.equal(latencies.length,28);
  for(const [i,c]of thin.entries()){
    bound(c.perPeriod.every(n=>n<=1),`client ${i}: worked-before queries per period ${c.perPeriod}`);
    bound(c.worked.length>=1&&c.worked.every(q=>q.calls<=64),`client ${i}: worked-before calls ${c.worked.map(q=>q.calls)}`);
    bound(c.maxPendingContactGets<=1,`client ${i}: ${c.maxPendingContactGets} GET /contact pending`);
    // Thin: one tick per 5 s plus at most one per transmit start/stop (three transmissions).
    const steady=c.tickUtcSpacingMs.filter((ms,n)=>c.tickTransmitting[n+1]===c.tickTransmitting[n]);
    bound(steady.every(ms=>ms>=4900),`client ${i}: Thin tick spacing ${c.tickUtcSpacingMs}`);
    bound(c.ticks>=Math.floor(span/5)-1&&c.ticks<=Math.ceil(span/5)+1+6,`client ${i}: Thin ticks ${c.ticks} in ${span} s`);
    bound(c.maxTickBytes<=224&&c.maxStateBytes<=2048,`client ${i}: event sizes ${c.maxTickBytes}/${c.maxStateBytes}`);
    // contact.state at most 1/s: coalesced while the revision changes faster.
    bound(c.states<=Math.ceil(span)+1,`client ${i}: ${c.states} contact.state in ${span} s`);
    // Events sent while the revisions change and up to 2.5 s after (link delivery): at most
    // one per second of that span, far fewer than the revisions, and the last revision
    // announced within 1 s plus that delivery allowance.
    const churnSeconds=(report.churn.end+2500-report.churn.start)/1000;
    report.phases.thin.churnSeconds=churnSeconds;
    bound(report.churn.revisions>=20,`churn made ${report.churn.revisions} revisions`);
    bound(c.churnStates<=Math.ceil(churnSeconds)+1,`client ${i}: ${c.churnStates} contact.state during ${churnSeconds.toFixed(1)} s of ${report.churn.revisions} revisions`);
    bound(c.churnStates*3<=report.churn.revisions,`client ${i}: ${c.churnStates} contact.state for ${report.churn.revisions} revisions is not coalesced`);
    bound(seen[i].states.some(x=>x.revision>=report.churn.last&&x.at<=report.churn.end+3500),`client ${i}: the last churn revision ${report.churn.last} not announced in time`);
    bound(c.states>=2,`client ${i}: contact.state announced the contact (${c.states})`);
  }
  await soft('contact log read',async()=>{const final=await pages[0].evaluate(async()=>{const r=await stationFetch('/contacts?cursor=0&limit=10',{signal:AbortSignal.timeout(30000)});return r.json();});
    bound(final.records.filter(r=>r.call==='K1ABC').length===1,`the completed contact is logged once: ${final.records.filter(r=>r.call==='K1ABC').length}`);});
  report.phases.thin.state='passed';await save();

  // ---- Off with two idle clients: within 1000 B/s per direction; one tick per 5 s.
  for(const p of pages)await act(pages.indexOf(p),()=>display(p,'off'));
  await sleep(6000);
  {const start=performance.now(),wallOff=Date.now(),before={...proxy.counters};await waitUntil(start+60000);const end=performance.now(),span=(end-start)/1000;
    const off={up:(proxy.counters.up-before.up)/span,down:(proxy.counters.down-before.down)/span};
    const ticks=seen.map(s=>s.ticks.filter(k=>k.utc>=wallOff&&k.utc<wallOff+60000));
    report.phases.off={seconds:span,frames:seen.map(s=>frameBytes(between(s.frames,start,end))),sharedBytesPerSecond:off,ticks:ticks.map(x=>x.length),utcSpacingMs:ticks.map(x=>x.slice(1).map((k,n)=>k.utc-x[n].utc)),routes:seen.map(s=>between(s.requests,start,end).map(r=>`${r.method} ${r.path}`))};await save();
    console.log(`Off ${span.toFixed(1)} s ${JSON.stringify(off)}`);
    bound(off.up<=1000,`Off idle counted uplink ${off.up} B/s`);bound(off.down<=1000,`Off idle counted downlink ${off.down} B/s`);
    for(const x of ticks){bound(x.length>=11&&x.length<=13,`Off ticks in 60 s: ${x.length}`);for(let n=1;n<x.length;n++)bound(x[n].utc-x[n-1].utc>=4900,`Off tick spacing ${x[n].utc-x[n-1].utc}`);}
  }
  report.missed=missed;assert.deepEqual(errors,[]);assert.deepEqual(missed,[],'every TC-007-005 bound holds');
  report.endedUtc=new Date().toISOString();await save();
  console.log('WSTX_THIN_CONTACT_COMPLETED 2');
});
