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
async function fixture(t,viewport){
  const listener=net.createServer();listener.listen(0,'127.0.0.1');await once(listener,'listening');const port=listener.address().port;await new Promise(r=>listener.close(r));
  const dir=await fs.mkdtemp(path.join(root,'station-'));
  const doc={schema_version:1,profile_id:crypto.randomUUID(),revision:0,display_name:'HB9BLA <station>',callsign:'HB9BLA',locator:'JN47AA',endpoint:{bind:`127.0.0.1:${port}`,origin:null},connection_type:'standard',audio:{input_device:null,output_device:null},control:{mode:'disabled',endpoint:null,ptt:'disabled'}};
  await fs.writeFile(path.join(dir,'profile.json'),JSON.stringify(doc));
  const app=await server({},['--profile',dir]),context=await browser.newContext({viewport}),page=await context.newPage();
  t.after(async()=>{await context.close();await app.close();});
  const errors=[],sent=[];page.on('pageerror',e=>errors.push(e.message));
  page.on('websocket',ws=>ws.on('framesent',frame=>sent.push(JSON.parse(frame.payload))));
  await page.goto(app.origin);await page.locator('#connection[data-state=connected]').waitFor();
  assert.equal(await page.locator('#operating-workspace').count(),1,'operating workspace is rendered');
  return {page,app,errors,sent};
}
async function geometry(page){return page.evaluate(()=>{const box=id=>{const r=document.querySelector(id).getBoundingClientRect();return {top:r.top,bottom:r.bottom,height:r.height};};return {bar:box('#station-bar'),signal:box('#signal'),split:box('#splitter'),workspace:box('#controls'),overflow:document.documentElement.scrollWidth>innerWidth};});}

// Proves: CL-010-05, CL-010-07, CL-010-08; TC-007-002 read-only layout subset.
test('TC-007-002 operating screen exposes literal identity and truthful unsupported controls',{timeout:20000},async t=>{
  const {page,errors}=await fixture(t,{width:1440,height:900});
  assert.equal(await page.locator('#operating-station').count(),1,'persistent operating station identity exists');
  assert.equal(await page.locator('#operating-station').textContent(),'HB9BLA <station>');
  assert.equal(await page.locator('#operating-station station').count(),0);
  for(const id of ['band-activity','rx-focus']){assert.match(await page.locator('#'+id).innerText(),/Decoder unavailable/);assert.equal(await page.locator('#'+id+' tbody tr[data-result-id]').count(),0);}
  for(const name of ['Enable Tx','Halt Tx','Auto Seq','Log contact'])assert.equal(await page.getByRole('button',{name,exact:true}).isDisabled(),true,name);
  assert.match(await page.locator('#operating-capabilities').innerText(),/Audio.*unavailable/is);
  assert.match(await page.locator('#operating-capabilities').innerText(),/CAT.*unavailable/is);
  // Existing server is read-only: verify real table styles without inserting decoded rows.
  for(const width of [360,1440,1499,1500,1600]){
    await page.setViewportSize({width,height:900});
    const style=await page.locator('#band-activity table').evaluate(table=>{
      const header=table.querySelector('th'),cell=table.querySelector('td');
      const a=getComputedStyle(table),b=getComputedStyle(header),c=getComputedStyle(cell);
      return {tableFont:a.fontSize,headerFont:b.fontSize,headerPadding:b.paddingTop,cellPadding:c.paddingTop,wrap:c.overflowWrap,overflow:document.documentElement.scrollWidth>innerWidth};
    });
    assert.equal(style.tableFont,width>=1500?'14px':'13px',`Band Activity table at ${width}px`);
    assert.equal(style.headerFont,'11px');assert.equal(style.headerPadding,'8px');
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
    for(const name of ['Station settings','Recorded input','Connection details']){
      const summary=page.locator('summary').filter({hasText:name});await summary.focus();await page.keyboard.press('Enter');assert.equal(await summary.evaluate(el=>el.parentElement.open),true);
      await summary.focus();await page.keyboard.press('Enter');assert.equal(await summary.evaluate(el=>el.parentElement.open),false);
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
  for(const name of ['Enable Tx','Halt Tx','Auto Seq','Log contact'])assert.equal(await page.getByRole('button',{name,exact:true}).isDisabled(),true);
  assert.ok(sent.some(m=>m.type==='station.get'),'recorder observes actual allowed station traffic');
  assert.equal(sent.some(m=>/transmit|qso|log|radio\./.test(m.type)),false);assert.deepEqual(errors,[]);
});
