'use strict';
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {once} = require('node:events');
const {setTimeout: sleep} = require('node:timers/promises');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const https = require('node:https');
const {chromium} = require('playwright');
const selfsigned = require('selfsigned');
const WebSocket = require('ws');
const {server, link} = require('./support.cjs');
let browser, temporary, tlsEnv;
const token = 'TestOnlyRandomCredential0123456789ABCDEF';
before(async () => {
  temporary = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-tests-'));
  const certificate = await selfsigned.generate([{name: 'commonName', value: 'localhost'}], {days: 1, keySize: 2048, extensions: [{name: 'subjectAltName', altNames: [{type: 7, ip: '127.0.0.1'}]}]});
  await fs.writeFile(path.join(temporary, 'cert.pem'), certificate.cert);
  await fs.writeFile(path.join(temporary, 'key.pem'), certificate.private, {mode: 0o600});
  tlsEnv = {WSTX_TLS_CERT: path.join(temporary, 'cert.pem'), WSTX_TLS_KEY: path.join(temporary, 'key.pem'), WSTX_TOKEN: token};
  browser = await chromium.launch({headless: true});
  await fs.mkdir('test-results', {recursive: true});
});
after(async () => {
  await browser?.close();
  if (temporary) await fs.rm(temporary, {recursive: true, force: true});
});
async function peer(origin, options = {}) {
  const ws = new WebSocket(origin.replace('http', 'ws') + '/ws', 'wstx.v1', {origin, rejectUnauthorized: false, ...options});
  ws.on('error', () => {});
  await once(ws, 'open');
  return ws;
}
async function receive(ws) {
  const message = once(ws, 'message').then(([data]) => JSON.parse(data));
  return Promise.race([message, sleep(3000).then(() => {throw new Error('Message timeout');})]);
}
async function request(ws, text) {const response = receive(ws); ws.send(text); return response;}
async function connected(page, origin) {
  await page.goto(origin);
  await page.locator('#connection').filter({hasText: /^Connected$/}).waitFor({timeout: 10000});
}
async function contextFor(origin, authenticated = false) {
  const context = await browser.newContext({ignoreHTTPSErrors: true});
  if (authenticated) await context.addCookies([{name: 'wstx_session', value: token, url: origin, httpOnly: true, secure: true, sameSite: 'Strict'}]);
  return context;
}

// Proves: FR-021; CL-003-02, CL-003-03; level 2, Windows PC/CI, isolated local server.
test('TC-021-005: actual-server correlation, negative cases and size boundaries', async t => {
  const app = await server(); t.after(() => app.close());
  const a = await peer(app.origin), b = await peer(app.origin); t.after(() => {a.terminate(); b.terminate();});
  const expected = id => ({v: 1, type: 'station.status', id, data: {version: '0.1.0', radio: 'unconfigured'}});
  const [ra, rb] = await Promise.all([request(a, '{"v":1,"type":"station.get","id":12}'), request(b, '{"v":1,"type":"station.get","id":24}')]);
  assert.deepEqual(ra, expected(12)); assert.deepEqual(rb, expected(24));
  for (const [input, code] of [['{', 'invalid_json'], ['[]', 'invalid_request'], ['{"v":2,"type":"station.get","id":1}', 'unsupported_version'], ['{"v":1,"type":"unknown","id":1}', 'unknown_command'], ['{"v":1,"type":"station.get"}', 'invalid_request'], ['{"v":1,"type":"station.get","id":"1"}', 'invalid_request'], ['{"v":1,"type":null,"id":1}', 'invalid_request'], ['{"v":1,"type":"station.get","id":9007199254740992}', 'invalid_request'], ['{"v":1,"type":"station.get","id":1,"extra":0}', 'invalid_request']]) {
    assert.equal((await request(a, input)).data.code, code, input);
  }
  const text = '{"v":1,"type":"station.get","id":12}';
  assert.deepEqual(await request(a, text.padEnd(1024, ' ')), expected(12));
  const closed = once(a, 'close'); a.send(text.padEnd(1025, ' ')); await closed;
  assert.deepEqual(await request(b, text), expected(12));
  const binary = await peer(app.origin); const binaryClosed = once(binary, 'close'); binary.send(Buffer.from([0]));
  assert.equal((await binaryClosed)[0], 1003);
});

// Proves: FR-019, FR-021; CL-003-01; level 2, real Chromium, local candidate server.
test('TC-021-006: real browser, two clients, desktop and mobile layout', async t => {
  const app = await server(); t.after(() => app.close());
  const contexts = await Promise.all([contextFor(app.origin), contextFor(app.origin)]);
  t.after(() => Promise.all(contexts.map(c => c.close())));
  const pages = await Promise.all(contexts.map(c => c.newPage()));
  const errors = []; for (const page of pages) page.on('pageerror', error => errors.push(String(error)));
  await Promise.all(pages.map(p => connected(p, app.origin)));
  for (const page of pages) {assert.equal(await page.locator('#version').textContent(), '0.1.0'); assert.equal(await page.locator('#radio').textContent(), 'Radio not configured');}
  await pages[0].screenshot({path: 'test-results/station-desktop.png', fullPage: true});
  await pages[1].setViewportSize({width: 360, height: 800});
  assert.equal(await pages[1].evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await pages[1].screenshot({path: 'test-results/station-mobile.png', fullPage: true});
  assert.deepEqual(errors, []);
  await app.close();
  await pages[0].locator('#connection[data-state="stale"]').waitFor();
});

// Proves: FR-021; CL-003-04, CL-003-08; level 2, browser and controllable local proxy.
test('TC-021-007: dropped connection, bounded retries, fresh snapshot', async t => {
  const proxy = await link({host: '127.0.0.1', port: 1}, {rate: 1000000, latency: 0});
  t.after(() => proxy.close());
  const origin = `http://127.0.0.1:${proxy.port}`;
  const app = await server({WSTX_ORIGIN: origin}); t.after(() => app.close());
  proxy.target.port = new URL(app.endpoint).port;
  const context = await contextFor(origin); t.after(() => context.close());
  const page = await context.newPage(); let requests = 0; const openings = [];
  page.on('websocket', ws => {openings.push(Date.now()); ws.on('framesent', frame => {if (String(frame.payload).includes('station.get')) requests++;});});
  await connected(page, origin);
  assert.equal(requests, 1); await sleep(5500); assert.equal(requests, 1);
  proxy.cut(); await page.locator('#connection[data-state="stale"]').waitFor();
  await sleep(3500); assert.ok(openings.length <= 4, 'bounded retry count');
  const restored = Date.now(); proxy.restore();
  await page.locator('#connection[data-state="connected"]').waitFor({timeout: 10000});
  assert.ok(Date.now() - restored < 10000); assert.equal(requests, 2, 'fresh snapshot requested');
});

// Proves: FR-021; CL-003-05, CL-003-08; level 2, TLS byte-stream link model, not packet capture.
test('TC-021-008: 32 kbit/s shared TLS link and 60-second idle budget', {timeout: 110000}, async t => {
  const proxy = await link({host: '127.0.0.1', port: 1}); t.after(() => proxy.close());
  const origin = `https://127.0.0.1:${proxy.port}`;
  const app = await server({...tlsEnv, WSTX_ORIGIN: origin}); t.after(() => app.close());
  proxy.target.port = Number(new URL(app.endpoint).port);
  const contexts = await Promise.all([contextFor(origin, true), contextFor(origin, true)]); t.after(() => Promise.all(contexts.map(c => c.close())));
  const pages = await Promise.all(contexts.map(c => c.newPage()));
  const started = Date.now(); await Promise.all(pages.map(p => connected(p, origin)));
  const cold = {milliseconds: Date.now() - started, bytes: {...proxy.counters}};
  const baseline = {...proxy.counters}; const idleStart = Date.now();
  await sleep(60000);
  const seconds = (Date.now() - idleStart) / 1000;
  const mean = {up: (proxy.counters.up - baseline.up) / seconds, down: (proxy.counters.down - baseline.down) / seconds};
  for (const direction of ['up', 'down']) assert.ok(mean[direction] <= 1000, `${direction} ${mean[direction]} bytes/s`);
  for (const page of pages) {
    const latency = await page.evaluate(() => new Promise((resolve, reject) => {
      const start = performance.now(); const ws = new WebSocket(`wss://${location.host}/ws`, 'wstx.v1');
      ws.onopen = () => {window.requestStart = performance.now(); ws.send('{"v":1,"type":"station.get","id":99}');};
      ws.onmessage = event => {if (JSON.parse(event.data).id === 99) {resolve({request: performance.now() - window.requestStart, connect: performance.now() - start}); ws.close();}};
      ws.onerror = reject;
    }));
    assert.ok(latency.request < 2000, JSON.stringify(latency)); assert.ok(latency.connect < 10000);
  }
  const result = {model: 'actual TLS stream + modelled TCP/IPv6/ACK overhead; no packet capture', cold, idleMeanBytesPerSecond: mean};
  console.log(JSON.stringify(result)); await fs.writeFile('test-results/link-budget.json', JSON.stringify(result, null, 2));
});

// Proves: FR-021; CL-003-06; level 2, stalled socket and independent healthy peer.
test('TC-021-008: stalled reader cannot block another client', {timeout: 30000}, async t => {
  const app = await server(); t.after(() => app.close());
  const slow = await peer(app.origin), healthy = await peer(app.origin);
  t.after(() => {slow.terminate(); healthy.terminate();});
  slow._socket.pause();
  const text = '{"v":1,"type":"station.get","id":1}';
  for (let i = 0; i < 100000; i++) slow.send(text);
  const started = Date.now();
  assert.equal((await request(healthy, text)).type, 'station.status');
  assert.ok(Date.now() - started < 2000);
  await sleep(3000);
  const closed = once(slow, 'close'); slow._socket.resume();
  await Promise.race([closed, sleep(20000).then(() => {throw new Error('Stalled reader was not disconnected');})]);
  assert.equal((await request(healthy, text)).type, 'station.status');
});

// Proves: FR-021; CL-003-07; level 2, disposable local TLS endpoint/credentials.
test('TC-021-009: TLS login, unauthorized/origin denial, plaintext refusal', async t => {
  const app = await server(tlsEnv); t.after(() => app.close());
  const context = await contextFor(app.origin); t.after(() => context.close()); const page = await context.newPage();
  await page.goto(app.origin); await page.locator('#login').waitFor({state: 'visible'});
  await page.locator('#token').fill(token); await page.locator('button').click();
  await page.locator('#connection[data-state="connected"]').waitFor();
  const cookie = (await context.cookies()).find(c => c.name === 'wstx_session'); assert.ok(cookie.httpOnly && cookie.secure && cookie.sameSite === 'Strict');
  async function denied(options, status) {
    await new Promise((resolve, reject) => {
      const ws = new WebSocket(app.origin.replace('http', 'ws') + '/ws', 'wstx.v1', {origin: app.origin, rejectUnauthorized: false, ...options});
      ws.on('unexpected-response', (_, response) => {try {assert.equal(response.statusCode, status); resolve();} catch (error) {reject(error);} response.resume(); ws.terminate();});
      ws.on('open', () => {ws.terminate(); reject(new Error('Unauthorized upgrade accepted'));}); ws.on('error', () => {});
    });
  }
  await denied({}, 401); await denied({headers: {Cookie: 'wstx_session=invalid'}}, 401);
  await denied({origin: 'https://untrusted.invalid', headers: {Cookie: `wstx_session=${token}`}}, 403);
  await assert.rejects(fetch(app.origin.replace('https:', 'http:')));
  for (let i = 0; i < 10; i++) {
    const status = await page.evaluate(async () => (await fetch('/session', {method: 'POST', body: 'invalid'})).status);
    assert.equal(status, i < 9 ? 401 : 429);
  }
});

// Test-tool oracle: an independent wall clock checks shared rate and one-way delays.
test('link simulator: shared bulk throughput and RTT', {timeout: 15000}, async t => {
  const echo = net.createServer(socket => socket.pipe(socket)); echo.listen(0, '127.0.0.1'); await once(echo, 'listening');
  t.after(() => new Promise(resolve => echo.close(resolve)));
  const proxy = await link({host: '127.0.0.1', port: echo.address().port}); t.after(() => proxy.close());
  const start = Date.now();
  const roundtrip = amount => new Promise((resolve, reject) => {
    const socket = net.connect(proxy.port, '127.0.0.1'); let bytes = 0;
    socket.on('connect', () => socket.write(Buffer.alloc(amount)));
    socket.on('data', data => {bytes += data.length; if (bytes === amount) {socket.end(); resolve(Date.now());}}); socket.on('error', reject);
  });
  const times = await Promise.all([roundtrip(4000), roundtrip(4000)]);
  assert.ok(Math.max(...times) - start >= 2000, 'shared 8000-byte transfer cannot exceed 4000 bytes/s');
  assert.ok(Math.max(...times) - start < 5000, 'pipelined propagation must not reduce the bulk link far below 32 kbit/s');
  const pingStart = Date.now(); await roundtrip(1); assert.ok(Date.now() - pingStart >= 300, 'RTT is at least 300ms');
});
