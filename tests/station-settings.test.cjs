'use strict';
// Cost 2: launched by contact_http::tests::contact_browser_settings with the actual candidate
// Router and contact step, its PSK Reporter feed on a fake broker and its UDP owner on
// recording sockets (nothing reaches the broker or a UDP port), and Chromium. One station per
// test: each saves a station setting the others would read.
const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const origin=process.env.WSTX_SETTINGS_FIXTURE_ORIGIN,control=process.env.WSTX_SETTINGS_FIXTURE_CONTROL;
let browser;
before(async()=>{assert.ok(origin&&control,'run through contact_http::tests::contact_browser_settings');browser=await chromium.launch();});
after(async()=>{await browser?.close();});
async function fixture(t,viewport,{beforeNavigate}={}){
  const app={origin},context=await browser.newContext({viewport}),page=await context.newPage();
  t.after(async()=>{await context.close();});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await beforeNavigate?.(page,app);
  await page.goto(app.origin);await page.locator('#connection[data-state=connected]').waitFor();
  assert.equal(await page.locator('#operating-workspace').count(),1,'operating workspace is rendered');
  return {page,app,errors};
}
async function inViewport(page,selector){return page.locator(selector).first().evaluate(el=>{const r=el.getBoundingClientRect();return el.checkVisibility({visibilityProperty:true})&&r.width>1&&r.height>1&&r.bottom>0&&r.right>0&&r.top<innerHeight&&r.left<innerWidth;});}
function deferred(){let resolve;const promise=new Promise(r=>{resolve=r;});return {promise,resolve};}
const post=async(route,body)=>(await fetch(control+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body??{})})).json();

// Settings shows the PSK Reporter feed from one snapshot and pushed
// events, against a fake broker written from the 3.1.1 packet tables; nothing reaches the broker.
// Proves: TC-039-021
test('TC-039-021 Settings shows the PSK Reporter status, pushed, and saves the switch',{timeout:60000},async t=>{
  const publish=payload=>post('/publish',payload);
  const received=async()=>(await (await fetch(control+'/received')).json());
  const requests=[];
  const {page,app,errors}=await fixture(t,{width:1366,height:768},{beforeNavigate:page=>{page.on('request',r=>{const p=new URL(r.url()).pathname;if(p==='/pskr')requests.push(r.method());});}});
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  await page.locator('#open-server-settings').click();await page.locator('#tab-logging').click();
  const status=page.locator('#pskr-status'),box=page.locator('#pskr-enabled');
  await page.locator('#pskr-enabled:enabled').waitFor();await box.scrollIntoViewIfNeeded();
  assert.equal(await inViewport(page,'#pskr-enabled'),true,'the switch is in Settings > Logging');
  assert.equal(await box.isChecked(),true,'on by default');
  await status.filter({hasText:'Connected'}).waitFor({timeout:20000});
  assert.equal(await status.textContent(),'Connected · no spot yet');
  await publish({f:7075512,md:'FT8',rp:-5,t:Math.floor(Date.now()/1000)-180,sc:'HB9BLA',rc:'K1ABC',b:'40m'});
  await status.filter({hasText:'last spot'}).waitFor({timeout:10000});
  await page.locator('#pskr-status',{hasText:'last spot 3 min ago'}).waitFor({timeout:10000});
  assert.deepEqual(requests,['GET'],'one snapshot; the rest is pushed');
  // Off: saved, shown, and the peer sees the clean end.
  await box.uncheck();await page.locator('#pskr-result',{hasText:'Saved'}).waitFor();
  await status.filter({hasText:'Off'}).waitFor();
  assert.equal((await (await fetch(app.origin+'/pskr')).json()).enabled,false,'the station stored it');
  for(let i=0;i<100&&!(await received()).includes(0xe0);i++)await page.waitForTimeout(50);
  assert.equal((await received()).includes(0xe0),true,'a clean DISCONNECT');
  assert.deepEqual([...new Set(await received())].filter(type=>![0x10,0x82,0xc0,0xe0].includes(type)),[],'only the handshake, subscribe, ping and disconnect on the wire');
  // On again, with the broker gone: a named status in Settings, no error anywhere else.
  await post('/drop');
  await box.check();await status.filter({hasText:'Not connected'}).waitFor({timeout:30000});
  assert.match(await status.textContent(),/^Not connected · connection_(closed|lost) · retrying$/);
  // The PSK toggle is on the operating screen; a PSK Reporter state never is.
  assert.doesNotMatch(await page.locator('#operating-workspace').textContent(),/connection_(closed|lost)|PSK Reporter/,'never an error on the operating screen');
  assert.deepEqual(errors,[]);
});

// The UDP interface is a Logging & Reporting setting.
// Proves: TC-227-002
test('the UDP editor reads GET /udp when Settings opens and saves the edited targets with one PUT',{timeout:60000},async t=>{
  const {page,app,errors}=await fixture(t,{width:1366,height:768});
  const requests=[],puts=[];
  page.on('request',r=>{const p=new URL(r.url()).pathname;requests.push(`${r.method()} ${p}`);if(r.method()==='PUT'&&p==='/udp')puts.push(JSON.parse(r.postData()));});
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});await page.waitForTimeout(500);
  assert.equal(requests.some(r=>r.endsWith(' /udp')),false,'no /udp request before Settings opens');
  const initial=await (await fetch(app.origin+'/udp')).json();
  // The read stays held until the Logging tab is shown, so that no second read can replace a row while it is edited.
  const hold=deferred();await page.route(url=>url.pathname==='/udp',async route=>{if(route.request().method()!=='GET')return route.fallback();await hold.promise;await route.continue();});
  await page.locator('#open-server-settings').click();await page.locator('#tab-logging').click();hold.resolve();
  const rows=page.locator('#udp-targets .udp-target');await rows.first().waitFor();
  assert.ok(requests.filter(r=>r==='GET /udp').length>=1,'read when the drawer opens');
  // CL-112-01: the instance name is shown as text, with no input.
  assert.equal(await page.locator('#udp-instance').textContent(),initial.instance_name);
  assert.equal(initial.instance_name,'WSTX-Rust');
  assert.equal(await page.locator('#udp-instance').evaluate(e=>e.tagName),'OUTPUT');
  assert.equal(await page.locator('#settings-udp input').evaluateAll(list=>list.filter(i=>!i.closest('.udp-target')).length),0,'no input outside the targets');
  const first=rows.nth(0);assert.equal(await first.locator('[data-f=address]').inputValue(),'127.0.0.1:2237');
  assert.equal(await first.locator('[data-f=enabled]').isChecked(),true);
  assert.deepEqual(await first.locator('[data-m]').evaluateAll(b=>b.filter(x=>x.checked).map(x=>x.dataset.m)),['heartbeat','status','decode','clear','qso_logged','close','logged_adif']);
  assert.equal(await page.locator('#settings-udp [data-f=accept]').count(),0,'send-only: no Accept commands');
  assert.match(await page.locator('#udp-note').textContent(),/Send-only/,'the note says so');
  assert.doesNotMatch(await page.locator('#tab-logging').textContent(),/⟳/,'a setting, not a restart change');
  // Edit: no Decode to the first target; add a multicast target.
  await first.locator('[data-m=decode]').uncheck();
  await page.locator('#udp-add').click();const added=rows.nth(1);
  await added.locator('[data-f=address]').fill('239.255.0.1:2237');
  await added.locator('[data-f=ttl]').fill('3');
  await page.locator('#udp-save').click();await page.locator('#udp-result').filter({hasText:'Saved'}).waitFor();
  const all=['heartbeat','status','decode','clear','qso_logged','close','logged_adif'];
  const expected={targets:[
    {address:'127.0.0.1:2237',enabled:true,multicast_ttl:1,multicast_interface:null,messages:all.filter(m=>m!=='decode')},
    {address:'239.255.0.1:2237',enabled:true,multicast_ttl:3,multicast_interface:null,messages:all}]};
  assert.deepEqual(puts,[{v:1,profile_id:initial.profile_id,boot_id:initial.boot_id,expected_revision:initial.revision,configuration:expected}],'exactly one exact PUT');
  const saved=await (await fetch(app.origin+'/udp')).json();assert.deepEqual(saved.configuration,expected,'the station stored the edited list');assert.equal(saved.revision,initial.revision+1);
  // A refused address keeps the edits and names the field.
  await page.locator('#udp-add').click();await rows.nth(2).locator('[data-f=address]').fill('0.0.0.0:1');
  await page.locator('#udp-save').click();await page.locator('#udp-result').filter({hasText:'Not saved'}).waitFor();
  assert.match(await page.locator('#udp-result').textContent(),/invalid_request \(targets\[2\]\.address\)/);
  assert.equal(await rows.count(),3,'the edits are kept');
  assert.equal(puts.length,2);
  assert.deepEqual(requests.filter(r=>/^POST \/receive\/(start|stop|select)$/.test(r)),[],'no receive mutation');
  assert.equal(requests.filter(r=>r==='GET /udp').length,1,'the opening and the Logging tab share one read');
  assert.deepEqual(errors,[]);
});

// The UDP editor takes an IPv6 multicast group.
// Proves: TC-227-002
test('the UDP editor saves an IPv6 multicast target with hop limit and interface index',{timeout:60000},async t=>{
  const {page,app,errors}=await fixture(t,{width:1366,height:768});
  const puts=[];
  page.on('request',r=>{if(r.method()==='PUT'&&new URL(r.url()).pathname==='/udp')puts.push(JSON.parse(r.postData()));});
  await page.waitForFunction(()=>!!window.wstxContact,null,{timeout:30000});
  const initial=await (await fetch(app.origin+'/udp')).json();
  // The read stays held until the Logging tab is shown, so that no second read can replace a row while it is edited.
  const hold=deferred();let reads=0;await page.route(url=>url.pathname==='/udp',async route=>{if(route.request().method()!=='GET')return route.fallback();reads++;await hold.promise;await route.continue();});
  await page.locator('#open-server-settings').click();await page.locator('#tab-logging').click();hold.resolve();
  const rows=page.locator('#udp-targets .udp-target');await rows.first().waitFor();
  const row=rows.nth(0);
  await row.locator('[data-f=address]').fill('[ff12::5754:5358]:2237');
  assert.match(await row.locator('[data-f=iface-note]').textContent(),/hop limit.*index.*link-local group needs one/s);
  assert.equal(await row.locator('[data-f=iface]').getAttribute('placeholder'),'interface index');
  // Without an interface the station refuses the link-local group and names the field.
  await page.locator('#udp-save').click();await page.locator('#udp-result').filter({hasText:'Not saved'}).waitFor();
  assert.match(await page.locator('#udp-result').textContent(),/invalid_request \(targets\[0\]\.multicast_interface\)/);
  await row.locator('[data-f=ttl]').fill('2');await row.locator('[data-f=iface]').fill('1');
  await page.locator('#udp-save').click();await page.locator('#udp-result').filter({hasText:'Saved'}).waitFor();
  const target={address:'[ff12::5754:5358]:2237',enabled:true,multicast_ttl:2,multicast_interface:'1',
    messages:['heartbeat','status','decode','clear','qso_logged','close','logged_adif']};
  assert.equal(puts.length,2);
  assert.deepEqual(puts[1].configuration,{targets:[target]},'the TTL field is the hop limit, the interface its index');
  const saved=await (await fetch(app.origin+'/udp')).json();
  assert.deepEqual(saved.configuration.targets,[target]);assert.equal(saved.revision,initial.revision+1);
  // A wider-scope group drops the link-local hint.
  await row.locator('[data-f=address]').fill('[ff05::5754:5358]:2237');
  assert.doesNotMatch(await row.locator('[data-f=iface-note]').textContent(),/needs one/);
  assert.equal(reads,1,'the opening and the Logging tab share one read');
  assert.deepEqual(errors,[]);
});
