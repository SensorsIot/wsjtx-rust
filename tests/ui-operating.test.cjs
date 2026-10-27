'use strict';
// Cost 2: actual isolated station server and Chromium, no radio or external network.
const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const net=require('node:net');
const {once}=require('node:events');
const crypto=require('node:crypto');
const {chromium}=require('playwright');
const {server}=require('./support.cjs');
let browser,root;
before(async()=>{root=await fs.mkdtemp(path.join(os.tmpdir(),'wstx-operating-'));await fs.mkdir('test-results/ui-operating',{recursive:true});browser=await chromium.launch();});
after(async()=>{await browser?.close();await fs.rm(root,{recursive:true,force:true});});
async function fixture(t,viewport,{inputDevice=null,beforeNavigate}={}){
  const listener=net.createServer();listener.listen(0,'127.0.0.1');await once(listener,'listening');const port=listener.address().port;await new Promise(r=>listener.close(r));
  const dir=await fs.mkdtemp(path.join(root,'station-'));
  const doc={schema_version:1,profile_id:crypto.randomUUID(),revision:0,display_name:'HB9BLA <station>',callsign:'HB9BLA',locator:'JN47AA',endpoint:{bind:`127.0.0.1:${port}`,origin:null},connection_type:'standard',audio:{input_device:inputDevice,output_device:null},control:{mode:'disabled',endpoint:null,ptt:'disabled'}};
  await fs.writeFile(path.join(dir,'profile.json'),JSON.stringify(doc));
  const app=await server({},['--profile',dir]),context=await browser.newContext({viewport}),page=await context.newPage();
  t.after(async()=>{await context.close();await app.close();});
  const errors=[],sent=[];page.on('pageerror',e=>errors.push(e.message));
  page.on('websocket',ws=>ws.on('framesent',frame=>sent.push(JSON.parse(frame.payload))));
  await beforeNavigate?.(page,app,doc);
  await page.goto(app.origin);await page.locator('#connection[data-state=connected]').waitFor();
  assert.equal(await page.locator('#operating-workspace').count(),1,'operating workspace is rendered');
  return {page,app,errors,sent};
}

function deferred(){let resolve;const promise=new Promise(r=>{resolve=r;});return {promise,resolve};}
function liveFixture(idle){
  return {...idle,audio:{state:'running',device_id:'test-only-unopened-input',device_name:null,error:null,retry_after_ms:null},
    source:{id:crypto.randomUUID(),kind:'live',sample_rate:12000,channels:1,next_frame:4800,segment:0},
    job:{id:crypto.randomUUID(),mode:'ft8',state:'running',error:null,processed_frames:0,first_sequence:0,next_sequence:0,available_count:0,last_overrun:null}};
}
function emptyResults(s){return {v:1,profile_id:s.profile_id,boot_id:s.boot_id,source_id:s.source.id,job_id:s.job.id,generation:s.generation,
  mode:'ft8',state:s.job.state,error:null,search_limited:false,first_sequence:0,next_sequence:0,available_count:0,next:0,more:false,records:[]};}

// Proves: CL-010-07, CL-010-08; TC-009-004. Negative delayed HTTP fixture; no decoder evidence.
test('receive result race cannot regress a newer cancelled snapshot',{timeout:15000},async t=>{
  const entered=deferred(),release=deferred();let current;
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(p,app)=>{
    current=liveFixture(await (await fetch(app.origin+'/receive')).json());
    await p.route('**/receive',async route=>{await p.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:current});});
    await p.route('**/receive/results?*',async route=>{const previous=emptyResults(current);entered.resolve();await release.promise;await route.fulfill({json:previous});});
  }});
  await entered.promise;
  current={...current,audio:{...current.audio,state:'closed'},job:{...current.job,state:'cancelled'}};
  await page.evaluate(()=>receiveSync());
  assert.equal(await page.evaluate(()=>live.job.state),'cancelled');
  release.resolve();await page.waitForFunction(()=>!resultPending);
  assert.equal(await page.evaluate(()=>live.job.state),'cancelled','old running page must not regress current terminal state');
  assert.match(await page.locator('#receive-status').innerText(),/cancelled.*Partial results retained/);
  assert.deepEqual(errors,[]);
});

// Proves: CL-010-07, CL-010-08; TC-009-004. Negative wire fixture through the actual listener.
test('receive frame race updates its live owner while recording job is absent',{timeout:15000},async t=>{
  let current;
  const {page,errors}=await fixture(t,{width:1440,height:900},{beforeNavigate:async(p,app)=>{
    current=liveFixture(await (await fetch(app.origin+'/receive')).json());
    await p.route('**/receive',async route=>{await p.waitForFunction(()=>snapshot&&!syncPending);await route.fulfill({json:current});});
    await p.route('**/receive/results?*',route=>route.fulfill({json:emptyResults(current)}));
  }});
  await page.waitForFunction(()=>live?.source&&snapshot&&snapshot.job===null);
  await page.evaluate(()=>window.dispatchEvent(new CustomEvent('station-message',{detail:{current:socket,message:{v:1,type:'spectrum.detail.frame',data:{
    boot_id:live.boot_id,source_id:live.source.id,job_id:live.job.id,generation:live.generation,sequence:0,first_frame:0,end_frame:2400,levels_b64:btoa('\0'.repeat(1024))}}}})));
  await page.waitForFunction(()=>document.querySelector('#waterfall').dataset.rows==='1');
  assert.equal(await page.evaluate(()=>live.job.processed_frames),2400);
  assert.equal(await page.evaluate(()=>snapshot.job),null,'live progress cannot mutate independently fetched file state');
  assert.equal(await page.locator('#connection').getAttribute('data-state'),'connected');assert.deepEqual(errors,[]);
});

// Proves: CL-010-07, CL-010-08; TC-009-004. A pre-mutation read is not reconciliation evidence.
test('receive snapshot race preserves unknown mutation until a later read',{timeout:15000},async t=>{
  const entered=deferred(),release=deferred();let hold=false;
  const {page,errors}=await fixture(t,{width:1440,height:900},{inputDevice:'test-only-unopened-input',beforeNavigate:async(p,app)=>{
    const idle=await (await fetch(app.origin+'/receive')).json();
    await p.route('**/receive',async route=>{if(hold){entered.resolve();await release.promise;}await route.fulfill({json:idle});});
    await p.route('**/receive/start',route=>route.abort('failed'));
  }});
  await page.waitForFunction(()=>live&&!livePending&&!document.querySelector('#receive-start').disabled);
  hold=true;await page.evaluate(()=>{void receiveSync();});await entered.promise;
  await page.getByRole('button',{name:'Start receive',exact:true}).click({timeout:2000});
  await page.locator('#receive-status').filter({hasText:'Start outcome unknown'}).waitFor({timeout:2000});
  hold=false;release.resolve();await page.waitForFunction(()=>!livePending);
  assert.equal(await page.evaluate(()=>uncertainMutation),true,'the old idle response cannot clear an unknown newer mutation');
  assert.equal(await page.getByRole('button',{name:'Start receive',exact:true}).isDisabled(),true);
  assert.match(await page.locator('#receive-status').innerText(),/Start outcome unknown/);
  await page.getByRole('button',{name:'Refresh status',exact:true}).click();
  await page.waitForFunction(()=>!uncertainMutation&&!document.querySelector('#receive-start').disabled);
  assert.deepEqual(errors,[]);
});
async function geometry(page){return page.evaluate(()=>{const box=id=>{const r=document.querySelector(id).getBoundingClientRect();return {top:r.top,bottom:r.bottom,height:r.height};};return {bar:box('#station-bar'),signal:box('#signal'),split:box('#splitter'),workspace:box('#controls'),overflow:document.documentElement.scrollWidth>innerWidth};});}

// Proves: CL-010-05, CL-010-07, CL-010-08; TC-007-002 read-only layout subset.
test('TC-007-002 operating screen exposes literal identity and truthful unsupported controls',{timeout:20000},async t=>{
  const {page,errors}=await fixture(t,{width:1440,height:900});
  assert.equal(await page.locator('#operating-station').count(),1,'persistent operating station identity exists');
  assert.equal(await page.locator('#operating-station').textContent(),'HB9BLA <station>');
  assert.equal(await page.locator('#operating-station station').count(),0);
  assert.match(await page.locator('#band-activity').innerText(),/Decoder unavailable/);assert.match(await page.locator('#rx-focus').innerText(),/No station selected/);assert.equal(await page.locator('tr[data-result-id]').count(),0);
  for(const name of ['Enable Tx','Halt Tx','Log contact'])assert.equal(await page.getByRole('button',{name,exact:true}).isDisabled(),true,name);
  assert.equal(await page.getByRole('checkbox',{name:'Auto sequence unavailable',exact:true}).isDisabled(),true);
  await page.getByRole('button',{name:'Station connection details',exact:true}).click();
  assert.match(await page.locator('#operating-capabilities').innerText(),/Audio.*unavailable/is);
  assert.match(await page.locator('#operating-capabilities').innerText(),/CAT.*unavailable/is);
  await page.locator('.op-secondary:not([hidden]) .return-operate').click();
  // Existing server is read-only: verify real table styles without inserting decoded rows.
  for(const width of [360,1440,1499,1500,1600]){
    await page.setViewportSize({width,height:900});
    const style=await page.locator('#band-activity table').evaluate(table=>{
      const header=table.querySelector('th'),cell=table.querySelector('td');
      const a=getComputedStyle(table),b=getComputedStyle(header),c=getComputedStyle(cell);
      return {tableFont:a.fontSize,headerFont:b.fontSize,headerPadding:b.paddingTop,cellPadding:c.paddingTop,wrap:c.overflowWrap,overflow:document.documentElement.scrollWidth>innerWidth};
    });
    assert.equal(style.tableFont,'16px',`Band Activity table at ${width}px`);
    assert.equal(style.headerFont,'14px');assert.equal(style.headerPadding,'8px');
    assert.equal(style.cellPadding,'8px');assert.equal(style.wrap,'anywhere');assert.equal(style.overflow,false);
    assert.equal(await page.locator('#band-activity tr[data-result-id]').count(),0,'no fake decoded rows');
    await page.screenshot({path:`test-results/ui-operating/readability-${width}.png`,fullPage:true});
  }
  await page.setViewportSize({width:1440,height:900});
  const g=await geometry(page);assert.ok(g.bar.bottom<=g.signal.top+1);assert.ok(g.signal.bottom<=g.split.top+1);assert.ok(g.split.bottom<=g.workspace.top+1);assert.equal(g.overflow,false);
  await fs.mkdir('test-results/ui-operating',{recursive:true});await page.screenshot({path:'test-results/ui-operating/desktop.png',fullPage:true});assert.deepEqual(errors,[]);
});

// Proves: CL-010-05, CL-010-08; TC-007-002 desktop/mobile/200% CSS viewport and keyboard.
test('TC-007-002 operating split and secondary regions remain accessible at narrow and zoom equivalent sizes',{timeout:20000},async t=>{
  const {page,errors}=await fixture(t,{width:360,height:800});
  for(const viewport of [{width:360,height:800},{width:720,height:450}]){
    await page.setViewportSize(viewport);const separator=page.getByRole('separator');await separator.focus();
    await page.keyboard.press('Home');const minimum=Number(await separator.getAttribute('aria-valuenow'));
    await page.keyboard.press('ArrowDown');const stepped=Number(await separator.getAttribute('aria-valuenow'));assert.equal(stepped,minimum+16);
    await page.keyboard.press('End');const maximum=Number(await separator.getAttribute('aria-valuenow'));assert.ok(maximum>=stepped);assert.equal(maximum,Number(await separator.getAttribute('aria-valuemax')));
    await page.keyboard.press('Home');let g=await geometry(page);assert.equal(g.overflow,false);assert.ok(g.signal.height>=160);assert.ok(g.signal.bottom<=g.workspace.top,JSON.stringify(g));
    for(const [opener,name] of [['#open-server-settings','Station settings'],['#open-recordings','Recorded input'],['.op-station-button','Connection details']]){
      await page.locator(opener).focus();await page.keyboard.press('Enter');
      const summary=page.locator('summary').filter({hasText:name});assert.equal(await summary.evaluate(el=>el.parentElement.open),true);
      await summary.focus();await page.keyboard.press('Enter');assert.equal(await summary.evaluate(el=>el.parentElement.open),false);
      await page.keyboard.press('Enter');assert.equal(await summary.evaluate(el=>el.parentElement.open),true);
      assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
      await page.keyboard.press('Escape');assert.equal(await page.locator('#operating-workspace').isVisible(),true);
      assert.equal(await page.locator(opener).evaluate(el=>document.activeElement===el),true);
    }
    assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
  }
  await page.setViewportSize({width:360,height:800});await page.reload();await page.locator('#connection[data-state=connected]').waitFor();await page.screenshot({path:'test-results/ui-operating/mobile.png',fullPage:true});assert.deepEqual(errors,[]);
});

// Proves: CL-010-07, CL-010-08; TC-007-002 link loss and no invented commands.
test('TC-007-002 pointer resize and stale link preserve read-only authority',{timeout:20000},async t=>{
  const {page,app,errors,sent}=await fixture(t,{width:1440,height:900});
  const separator=page.getByRole('separator'),before=Number(await separator.getAttribute('aria-valuenow')),box=await separator.boundingBox();
  await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();await page.mouse.move(box.x+box.width/2,box.y+box.height/2-40);await page.mouse.up();
  assert.ok(Number(await separator.getAttribute('aria-valuenow'))<before);
  await app.close();await page.locator('#connection[data-state=stale]').waitFor();
  for(const name of ['Enable Tx','Halt Tx','Log contact'])assert.equal(await page.getByRole('button',{name,exact:true}).isDisabled(),true);
  assert.ok(sent.some(m=>m.type==='station.get'),'recorder observes actual allowed station traffic');
  assert.equal(sent.some(m=>/transmit|qso|log|radio\./.test(m.type)),false);assert.deepEqual(errors,[]);
});


// Proves: CL-010-05, CL-010-07, CL-010-08; TC-007-002 agreed design and authority-preserving regions.
test('TC-007-002 agreed workspace has tuning, band strip, Current QSO and Strategy with truthful state',{timeout:20000},async t=>{
 const {page,errors,sent}=await fixture(t,{width:1200,height:800});
 for(const id of ['radio-toolbar','band-strip','strategy-panel'])assert.equal(await page.locator('#'+id).count(),1,`${id} is part of the agreed operating screen`);
 const composition=await page.evaluate(()=>{
  const rect=id=>{const r=document.querySelector(id).getBoundingClientRect();return {top:r.top,bottom:r.bottom,left:r.left,right:r.right,height:r.height};};
  return Object.fromEntries(['#station-bar','#radio-toolbar','#signal','#splitter','#band-strip','#band-activity','#rx-focus','#strategy-panel'].map(id=>[id,rect(id)]));
 });
 assert.ok(composition['#station-bar'].bottom<=composition['#radio-toolbar'].top+1);
 assert.ok(composition['#radio-toolbar'].bottom<=composition['#signal'].top+1);
 assert.equal(Math.round(composition['#signal'].height),210);
 assert.ok(composition['#splitter'].bottom<=composition['#band-strip'].top+1);
 assert.ok(composition['#band-strip'].bottom<=composition['#band-activity'].top+1);
 assert.ok(composition['#band-activity'].top>=composition['#band-strip'].bottom);
 await page.setViewportSize({width:1600,height:1000});
 const cardOrder=await page.locator('#controls .operating-grid').evaluate(grid=>[...grid.children].map(el=>el.getBoundingClientRect().left));assert.ok(cardOrder[0]<cardOrder[1]&&cardOrder[1]<cardOrder[2],'three cards remain adjacent when readable space permits');
 await page.setViewportSize({width:1200,height:800});
 assert.equal(await page.locator('#focus-heading').textContent(),'Current QSO');
 assert.match(await page.locator('#strategy-heading').textContent(),/Strategy/);
 assert.equal(await page.locator('#band-strip button').count(),13);
 for(const selector of ['#op-dial','#radio-toolbar select','#radio-toolbar button','#band-strip button','#strategy-panel button:disabled']){
  for(const control of await page.locator(selector).all())assert.equal(await control.isDisabled(),true);
 }
 assert.equal(await page.locator('#op-dial').inputValue(),'');
 assert.match(await page.locator('#signal .op-signal-heading').innerText(),/0\u20133000 Hz/,'fixed-band label retains correct Unicode text');
 assert.match(await page.locator('#radio-toolbar').innerText(),/Timing unavailable/);
 assert.match(await page.locator('#strategy-panel').innerText(),/No active definition/);
 assert.equal(await page.locator('tr[data-result-id]').count(),0);
 for(const width of [360,720,1200,1440,1499,1500,1600]){
  await page.setViewportSize({width,height:900});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`no page overflow ${width}`);
 }
 await page.setViewportSize({width:1200,height:800});
 await page.screenshot({path:'test-results/ui-operating/agreed-design-1200.png',fullPage:true});
 assert.equal(sent.some(m=>/transmit|qso|log|radio\./.test(m.type)),false);assert.deepEqual(errors,[]);
});

// Proves: CL-010-05, CL-010-07, CL-010-08; TC-007-002 actual form state survives region changes.
test('TC-007-002 in-page navigation preserves unsaved profile and selected recording with no command replay',{timeout:20000},async t=>{
 const {page,errors}=await fixture(t,{width:1440,height:950});
 const mutations=[];page.on('request',r=>{if(r.method()!=='GET')mutations.push({method:r.method(),url:r.url()});});
 await page.keyboard.press('F2');assert.equal(await page.locator('#region-server-settings').isVisible(),true);
 await page.locator('#display-name').fill('Unsaved operator edit');
 await page.keyboard.press('Escape');assert.equal(await page.locator('#operating-workspace').isVisible(),true);
 await page.locator('#open-recordings').click();
 await page.locator('#recording-file').setInputFiles({name:'selected-but-not-imported.wav',mimeType:'audio/wav',buffer:Buffer.from('not imported')});
 await page.keyboard.press('Escape');
 for(const name of ['logbook','strategies','client-preferences','help']){
  const button=page.locator(`#station-bar [data-region="${name}"]`);await button.focus();await page.keyboard.press('Enter');
  assert.equal(await page.locator(`#region-${name}`).isVisible(),true);
  assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isVisible(),true);
  assert.equal(await page.getByRole('button',{name:'Halt Tx',exact:true}).isDisabled(),true);
  await page.keyboard.press('Escape');assert.equal(await button.evaluate(el=>document.activeElement===el),true);
 }
 await page.locator('#open-server-settings').click();assert.equal(await page.locator('#display-name').inputValue(),'Unsaved operator edit');
 await page.keyboard.press('Escape');await page.locator('#open-recordings').click();
 assert.equal(await page.locator('#recording-file').evaluate(el=>el.files[0].name),'selected-but-not-imported.wav');
 assert.deepEqual(mutations,[],'navigation does not save/import or issue station mutations');
 assert.deepEqual(errors,[]);
});

// Proves: TC-007-002 readable rem typography and actual 200% text enlargement, every region.
test('TC-007-002 readable text reflows throughout every operating region at 200 percent',{timeout:60000},async t=>{
 const {page,errors,sent}=await fixture(t,{width:1200,height:900});
 const regions=['operate','recordings','server-settings','client-preferences','connection','strategies','logbook','help'];
 const findings=[];
 for(const scale of [1,2])for(const width of [360,1200,1600]){
  await page.setViewportSize({width,height:1000});
  // Root font-size exercises actual rem text enlargement, not device pixels or a screenshot scale.
  await page.evaluate(factor=>document.documentElement.style.fontSize=`${factor*100}%`,scale);
  await page.waitForTimeout(60);
  for(const region of regions){
   await page.locator(`#station-bar button[data-region="${region}"]`).focus();await page.keyboard.press('Enter');
   const container=region==='operate'?'#operating-workspace':`#region-${region}`;
   await page.locator(container).evaluate(async el=>{for(const details of el.querySelectorAll('details'))details.open=true;await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));});
   const result=await page.evaluate(({container,scale})=>{
    const regions=[document.querySelector('#station-bar'),document.querySelector('#radio-toolbar'),document.querySelector('#signal'),document.querySelector('#band-strip'),document.querySelector('#workspace-statusbar'),document.querySelector(container)];
    const violations=[],clipped=[],overlap=[],textBoxes=[];let checked=0;
    const visible=el=>el.getClientRects().length&&getComputedStyle(el).visibility!=='hidden';
    for(const region of regions)for(const el of [region,...region.querySelectorAll('*')]){
     if(!visible(el)||el.matches('canvas,option,script,style'))continue;
     const direct=[...el.childNodes].filter(n=>n.nodeType===Node.TEXT_NODE&&n.textContent.trim());
     if(!direct.length&&!el.matches('input:not([type=range]):not([type=checkbox]),select,button'))continue;
     const technical=!!el.closest('#frequency-ruler,#time-ruler');
     const normal=el.matches('button,input:not([type=range]):not([type=checkbox]),select,td')||!!el.closest('td')||(el.matches('p')&&!el.matches('.op-muted,.op-unavailable,#bin-readout,#settings-result')&&!el.closest('.op-candidate,#settings'));
     const minimum=(technical?12:normal?16:14)*scale;
     const computed=getComputedStyle(el),size=parseFloat(computed.fontSize);checked++;
     if(size+0.1<minimum)violations.push({tag:el.tagName,id:el.id,cls:el.className,size,minimum,text:el.textContent.trim().slice(0,55)});
     for(const node of direct){const range=document.createRange();range.selectNodeContents(node);for(const r of range.getClientRects()){
      if(r.width&&r.height){const rendered={left:r.left,right:r.right,top:r.top,bottom:r.bottom};for(let a=el;a&&a!==document.body;a=a.parentElement){const style=getComputedStyle(a),b=a.getBoundingClientRect();if(['hidden','auto','scroll'].includes(style.overflowX)){rendered.left=Math.max(rendered.left,b.left);rendered.right=Math.min(rendered.right,b.right);}if(['hidden','auto','scroll'].includes(style.overflowY)){rendered.top=Math.max(rendered.top,b.top);rendered.bottom=Math.min(rendered.bottom,b.bottom);}}if(rendered.right>rendered.left&&rendered.bottom>rendered.top)textBoxes.push({el,r:rendered,text:node.textContent.trim().slice(0,45)});}
      if(r.width&& (r.left< -1||r.right>innerWidth+1))clipped.push({id:el.id,cls:el.className,text:node.textContent.trim().slice(0,45),left:r.left,right:r.right});
      let verticalScroll=false;for(let ancestor=el;ancestor&&ancestor!==document.body;ancestor=ancestor.parentElement){const style=getComputedStyle(ancestor);if(['auto','scroll'].includes(style.overflowY)&&ancestor.scrollHeight>ancestor.clientHeight)verticalScroll=true;if(style.overflowX==='hidden'||(style.overflowY==='hidden'&&!verticalScroll)){
       const b=ancestor.getBoundingClientRect();if((style.overflowX==='hidden'&&(r.left<b.left-1||r.right>b.right+1))||(style.overflowY==='hidden'&&!verticalScroll&&(r.top<b.top-1||r.bottom>b.bottom+1)))clipped.push({id:el.id,clip:ancestor.id,text:node.textContent.trim().slice(0,45)});
      }}
     }}
    }
    for(let a=0;a<textBoxes.length;a++)for(let b=a+1;b<textBoxes.length;b++){const x=textBoxes[a],y=textBoxes[b];if(x.el===y.el||x.el.contains(y.el)||y.el.contains(x.el))continue;if(Math.min(x.r.right,y.r.right)-Math.max(x.r.left,y.r.left)>1&&Math.min(x.r.bottom,y.r.bottom)-Math.max(x.r.top,y.r.top)>1)overlap.push([x.text,y.text]);}
    return {violations,clipped,overlap,checked,overflow:document.documentElement.scrollWidth>innerWidth,rootFont:getComputedStyle(document.documentElement).fontSize,scrollX,mainLeft:document.querySelector('main').getBoundingClientRect().left,mainScroll:document.querySelector('main').scrollLeft};
   },{container,scale});
   findings.push({width,scale,region,...result});
   await fs.writeFile("test-results/ui-operating/readability-computed.json",JSON.stringify(findings,null,2));
   if(result.clipped.length||result.overflow||result.violations.length)await page.screenshot({path:"test-results/ui-operating/readability-failure.png",fullPage:true});
   assert.equal(result.rootFont,`${16*scale}px`);assert.ok(result.checked>20);
   assert.deepEqual(result.violations,[],`font minima ${region} ${width}px ${scale}x`);
   assert.equal(result.overflow,false,`page overflow ${region} ${width}px ${scale}x`);
   assert.deepEqual(result.clipped,[],`text clipping ${region} ${width}px ${scale}x`);
   assert.deepEqual(result.overlap,[],`text overlap ${region} ${width}px ${scale}x`);
   await page.locator('#halt-tx').scrollIntoViewIfNeeded();assert.equal(await page.locator('#halt-tx').isVisible(),true);assert.equal(await page.locator('#halt-tx').isDisabled(),true);
   if(width===1200&&region==='operate')await page.screenshot({path:`test-results/ui-operating/readable-${scale}x-1200.png`,fullPage:true});
  }
 }
 await fs.writeFile('test-results/ui-operating/readability-computed.json',JSON.stringify(findings,null,2));
 assert.equal(sent.some(m=>/transmit|qso|log|radio\./.test(m.type)),false);assert.deepEqual(errors,[]);
});

// CSS fixture only: known CQ text exercises populated cells; it is not decoder or RF evidence.
test('TC-007-002 populated message cells wrap without crossing adjacent columns',{timeout:20000},async t=>{
 const {page,errors}=await fixture(t,{width:1200,height:1000});
 const values=['0.497s','23.0','-0.1','1000.0','CQ K1ABC FN42','Decoded'];
 await page.locator('#band-activity tbody').evaluate((tbody,values)=>{const row=document.createElement('tr');for(const value of values){const td=document.createElement('td');td.textContent=value;row.append(td);}tbody.replaceChildren(row);},values);
 for(const scale of [1,2])for(const width of [360,1200,1600]){
  await page.setViewportSize({width,height:1000});await page.evaluate(scale=>document.documentElement.style.fontSize=`${scale*100}%`,scale);
  const cells=await page.locator('#band-activity tbody td').evaluateAll(nodes=>nodes.map(td=>{const box=td.getBoundingClientRect(),range=document.createRange();range.selectNodeContents(td);return {text:td.textContent,font:parseFloat(getComputedStyle(td).fontSize),whiteSpace:getComputedStyle(td).whiteSpace,inside:[...range.getClientRects()].every(r=>r.left>=box.left-1&&r.right<=box.right+1&&r.top>=box.top-1&&r.bottom<=box.bottom+1)};}));
  assert.deepEqual(cells.map(c=>c.text),values);assert.ok(cells.every(c=>c.font>=16*scale&&c.whiteSpace==='normal'&&c.inside),`populated cells stay within their own columns ${width}px ${scale}x`);
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
 }
 assert.deepEqual(errors,[]);
});
