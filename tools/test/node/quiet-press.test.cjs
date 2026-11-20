'use strict';
// The tests of the quiet check of a press (quiet-press.cjs), on a static page served by a local
// HTTP and WebSocket server: the page opens its socket and looks the partner up (GET
// /dxcc?call=K1ABC) as the prepared state does; its button only shows itself pressed.
const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const http=require('node:http');
const {chromium}=require('playwright');
const {WebSocketServer}=require('ws');
const {listenBrowser}=require('./support.cjs');
const {quietPress}=require('./quiet-press.cjs');

const PAGE=`<!doctype html><title>press</title><button id="full-screen" aria-pressed="false">Full screen</button>
<script>const socket=new WebSocket(location.origin.replace('http','ws')+'/ws');
document.querySelector('#full-screen').addEventListener('click',e=>e.currentTarget.setAttribute('aria-pressed','true'));
socket.addEventListener('open',()=>fetch('/dxcc?call=K1ABC',{cache:'no-store'}).then(r=>r.json()));</script>`;
let browser;
before(async()=>{browser=await chromium.launch();});
after(async()=>{await browser?.close();});
// The page, served on a browser-accepted port, watched before its navigation, its lookup finished.
async function pressFixture(t,{init=null}={}){
  const site=http.createServer((request,response)=>{
    if(request.url==='/'){response.writeHead(200,{'content-type':'text/html'});response.end(PAGE);return;}
    response.writeHead(200,{'content-type':'application/json','cache-control':'no-store'});response.end('{}');
  });
  const sockets=new WebSocketServer({server:site});
  await listenBrowser(site);t.after(()=>{sockets.close();site.closeAllConnections();site.close();});
  const context=await browser.newContext();t.after(()=>context.close());
  const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));  if(init)await page.addInitScript(init);
  const watch=quietPress(page,{lookup:r=>{const u=new URL(r.url());return u.pathname==='/dxcc'&&u.searchParams.get('call')==='K1ABC';}});
  await page.goto(`http://127.0.0.1:${site.address().port}/`);
  await watch.opened();
  const button=page.locator('#full-screen');
  return {page,errors,button,requests:watch.requests,quiet:watch.quiet,
    entered:()=>page.waitForFunction(()=>document.querySelector('#full-screen')?.getAttribute('aria-pressed')==='true',null,{timeout:5000})};
}

// The window of quiet opens only after the requests of the prepared state, the partner's DXCC lookup
// among them, have reached the test and finished; a request or frame inside the window still fails.
const lateLookup=()=>{const send=window.fetch;
  window.fetch=(input,...rest)=>/\/dxcc\?/.test(String(input?.url??input))?new Promise(r=>setTimeout(r,200)).then(()=>send(input,...rest)):send(input,...rest);};
test('a partner DXCC lookup the page sends 200 ms late does not count as the full-screen press',{timeout:60000},async t=>{
  const x=await pressFixture(t,{init:lateLookup}),{errors,button}=x;
  await x.quiet(async()=>{await button.click();await x.entered();},'enter');
  assert.deepEqual(x.requests.filter(r=>r==='GET /dxcc'),['GET /dxcc'],'the lookup was sent once, before the press');
  assert.deepEqual(errors,[]);
});
test('Negative: a press that sends GET /dxcc?call=K1ABC fails quiet with no station request',{timeout:60000},async t=>{
  const x=await pressFixture(t),{button}=x;
  await button.evaluate(b=>b.addEventListener('click',()=>{fetch('/dxcc?call=K1ABC',{cache:'no-store'}).catch(()=>{});}));
  await assert.rejects(x.quiet(()=>button.click(),'press'),{message:/^press: no station request\n/});
});
test('Negative: a press that sends a WebSocket frame fails quiet with no WebSocket frame',{timeout:60000},async t=>{
  const x=await pressFixture(t),{button}=x;
  await button.evaluate(b=>b.addEventListener('click',()=>socket.send(JSON.stringify({v:1,type:'station.get',id:0}))));
  await assert.rejects(x.quiet(()=>button.click(),'press'),{message:/^press: no WebSocket frame\n/});
});
