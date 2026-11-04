'use strict';
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {once, EventEmitter} = require('node:events');
const {setTimeout: sleep} = require('node:timers/promises');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const https = require('node:https');
const {chromium} = require('playwright');
const selfsigned = require('selfsigned');
const WebSocket = require('ws');
const {server, link, restrictedPorts, listenBrowser, browserPort} = require('./support.cjs');
const {receive} = require('./peer.cjs');
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

// Test-tool oracle: a protocol fixture proves heartbeat interleaving and a fixed deadline.
// #35: Chromium refuses its kRestrictedPorts with ERR_UNSAFE_PORT; Windows here hands out
// dynamic ports from 1024, so a browser-facing listen(0) can land on one.
test('port helper: browser- and fetch-facing ports are never Chromium restricted or fetch bad ports', async () => {
  // Spot values of Chromium net/base/port_util.cc kRestrictedPorts, including the ones seen on HB9BLA.
  for (const port of [1, 25, 1719, 1720, 1723, 2049, 5060, 5061, 6000, 6665, 6666, 6667, 6668, 6669, 6697, 10080]) assert.ok(restrictedPorts.has(port), String(port));
  for (const port of [80, 443, 1024, 8080, 18001]) assert.equal(restrictedPorts.has(port), false, String(port));
  // #8: Node's fetch (undici) refuses the Fetch standard's bad ports with "bad port"; 4190 and
  // 6679 are not on Chromium's list. Each one is restricted, and this Node refuses each.
  for (const port of [1, 7, 9, 11, 13, 15, 17, 19, 20, 21, 22, 23, 25, 37, 42, 43, 53, 69, 77, 79, 87, 95, 101, 102, 103, 104, 109, 110, 111, 113, 115, 117, 119, 123, 135, 137, 139, 143, 161, 179, 389, 427, 465, 512, 513, 514, 515, 526, 530, 531, 532, 540, 548, 554, 556, 563, 587, 601, 636, 989, 990, 993, 995, 1719, 1720, 1723, 2049, 3659, 4045, 4190, 5060, 5061, 6000, 6566, 6665, 6666, 6667, 6668, 6669, 6679, 6697, 10080]) {
    assert.ok(restrictedPorts.has(port), String(port));
    await assert.rejects(fetch(`http://127.0.0.1:${port}/`), error => error.cause?.message === 'bad port', String(port));
  }
  // A listener that the OS gives restricted ports first: the helper must skip all of them.
  const offered = [1719, 4190, 1723, 6679, 6000, 10080, 40000];
  let closed = 0;
  const fake = Object.assign(new EventEmitter(), {
    listen(port, host) { assert.equal(port, 0); assert.equal(host, '127.0.0.1'); setImmediate(() => this.emit('listening')); },
    address() { return {port: offered[closed]}; },
    close(done) { closed++; setImmediate(done); },
  });
  assert.equal(await listenBrowser(fake), 40000);
  assert.equal(closed, 6, 'each restricted port is released');
  // Only restricted ports: the helper fails instead of returning one.
  const stuck = Object.assign(new EventEmitter(), {listen() { setImmediate(() => this.emit('listening')); }, address() { return {port: 1720}; }, close(done) { setImmediate(done); }});
  await assert.rejects(listenBrowser(stuck), /No browser-accepted port/);
  // Real allocations are free, distinct-enough ports outside the list.
  for (let i = 0; i < 50; i++) {
    const port = await browserPort();
    assert.ok(Number.isInteger(port) && port > 0 && port < 65536 && !restrictedPorts.has(port), String(port));
  }
});
test('peer helper: heartbeat interleaving preserves response and total deadline', {timeout: 2000}, async () => {
  const fixture = new EventEmitter();
  const result = receive(fixture);
  fixture.emit('message', Buffer.from('{"v":1,"type":"heartbeat"}'));
  fixture.emit('message', Buffer.from('{"v":1,"type":"station.status","id":7}'));
  assert.deepEqual(await result, {v: 1, type: 'station.status', id: 7});
  for (const message of [{v: 2, type: 'heartbeat'}, {v: 1, type: 'heartbeat', id: 7}, {v: 1, type: 'unexpected'}]) {
    const unexpected = receive(fixture); fixture.emit('message', JSON.stringify(message));
    assert.deepEqual(await unexpected, message, 'unexpected messages remain visible to the oracle');
  }
  const deadline = receive(fixture, 30);
  const heartbeat = setInterval(() => fixture.emit('message', '{"v":1,"type":"heartbeat"}'), 2);
  try {await assert.rejects(deadline, /Message timeout/);} finally {clearInterval(heartbeat);}
  assert.equal(fixture.listenerCount('message'), 0);
});

// Proves: FR-021; CL-003-02, CL-003-03, CL-051-01; TC-051-001; level 2, Windows PC/CI, isolated local server.
test('TC-021-005: actual-server correlation, negative cases and size boundaries', async t => {
  const app = await server(); t.after(() => app.close());
  const a = await peer(app.origin), b = await peer(app.origin); t.after(() => {a.terminate(); b.terminate();});
  // #51 ClientBuild oracle: SHA-256 over the client files in route order, first 16 hex digits.
  const build = require('node:crypto').createHash('sha256').update(Buffer.concat(await Promise.all(['index.html', 'authorization.js', 'app.js', 'recording.js', 'recording.css', 'contact.js', 'logbook.js', 'style.css'].map(f => fs.readFile(path.join(__dirname, '../client', f)))))).digest('hex').slice(0, 16);
  const expected = id => ({v: 1, type: 'station.status', id, data: {version: '0.1.0', radio: 'unconfigured', build}});
  assert.match(await (await fetch(app.origin + '/')).text(), new RegExp(`<body data-profile="false" data-build="${build}">`), 'the page carries the build it was served with');
  const [ra, rb] = await Promise.all([request(a, '{"v":1,"type":"station.get","id":12}'), request(b, '{"v":1,"type":"station.get","id":24}')]);
  assert.deepEqual(ra, expected(12)); assert.deepEqual(rb, expected(24));
  for (const [input, code] of [['{', 'invalid_json'], ['[]', 'invalid_request'], ['{"v":2,"type":"station.get","id":1}', 'unsupported_version'], ['{"v":1,"type":"unknown","id":1}', 'unknown_command'], ['{"v":1,"type":"station.get"}', 'invalid_request'], ['{"v":1,"type":"station.get","id":"1"}', 'invalid_request'], ['{"v":1,"type":null,"id":1}', 'invalid_request'], ['{"v":2,"type":null,"id":1}', 'invalid_request'], ['{"v":1,"type":"station.get","id":9007199254740992}', 'invalid_request'], ['{"v":1,"type":"station.get","id":1,"extra":0}', 'invalid_request']]) {
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
  for (const page of pages) page.on('response', response => {if (['/', '/app.js', '/style.css'].includes(new URL(response.url()).pathname) && !response.ok()) errors.push(`${response.status()} ${response.url()}`);});
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
  const silentStart = Date.now(); proxy.blackhole();
  await page.locator('#connection[data-state="stale"]').waitFor({timeout: 14000});
  assert.ok(Date.now() - silentStart <= 14000, '13-second detection bound plus 1-second scheduler tolerance');
  const silentRestore = Date.now(); proxy.restore();
  await page.locator('#connection[data-state="connected"]').waitFor({timeout: 10000});
  assert.ok(Date.now() - silentRestore < 10000); assert.equal(requests, 3, 'snapshot after silent failure');
});

// #8: on the shared 32 kbit/s bottleneck the page's own deferred contact client download holds
// the station's WebSocket messages behind it for more than 12 s. Deterministic model: hold
// (delay, never drop) every station-to-page message while /contact.js is pending, then deliver.
async function deferredDownloadHold(t, holdMs) {
  const dir = await fs.mkdtemp(path.join(temporary, 'deferred-')), port = await browserPort();
  const document = {schema_version: 1, profile_id: require('node:crypto').randomUUID(), revision: 0, display_name: 'Deferred', callsign: 'HB9BLA', locator: 'JN37VL',
    endpoint: {bind: `127.0.0.1:${port}`, origin: null}, connection_type: 'standard', audio: {input_device: null, output_device: null}, control: {mode: 'disabled', endpoint: null, ptt: 'disabled'}};
  await fs.writeFile(path.join(dir, 'profile.json'), JSON.stringify(document));
  const app = await server({}, ['--profile', dir]); t.after(() => app.close());
  const context = await contextFor(app.origin); t.after(() => context.close());
  const page = await context.newPage(), state = {held: false, queue: [], lastDelivered: 0, logbookEnded: null, sockets: 0, release: null, heldAt: null};
  await page.addInitScript(() => {
    window.__states = [];
    addEventListener('DOMContentLoaded', () => {const c = document.querySelector('#connection'); new MutationObserver(() => window.__states.push({at: Date.now(), state: c.dataset.state})).observe(c, {attributes: true, attributeFilter: ['data-state']});});
  });
  page.on('websocket', () => state.sockets++);
  // The finished log client download counts as a message too (its end restarts the 12 s bound).
  page.on('requestfinished', request => {if (new URL(request.url()).pathname === '/logbook.js') state.logbookEnded = Date.now();});
  await page.routeWebSocket(/\/ws$/, ws => {
    const station = ws.connectToServer();
    station.onMessage(message => {const deliver = () => {state.lastDelivered = Date.now(); try {ws.send(message);} catch {}}; if (state.held) state.queue.push(deliver); else deliver();});
  });
  await page.route('**/contact.js', async route => {
    state.held = true; state.heldAt = Date.now();
    await new Promise(resolve => {state.release = resolve; setTimeout(resolve, holdMs);});
    await route.continue(); state.held = false; for (const deliver of state.queue.splice(0)) deliver();
  });
  await page.goto(app.origin);
  await page.locator('#connection[data-state=connected]').waitFor({timeout: 10000});
  return {page, state};
}

// Proves: FR-021; CL-003-04; TC-021-007 case 5 (#8); level 2, profile station, real Chromium.
test('TC-021-007: a deferred client download that holds station messages 16 s is not a lost link', {timeout: 60000}, async t => {
  const {page, state} = await deferredDownloadHold(t, 16000);
  await page.waitForFunction(() => !!window.wstxContact, null, {timeout: 45000});
  assert.ok(state.heldAt !== null && state.lastDelivered - state.heldAt >= 15000, 'the station messages were held behind the download');
  await sleep(2000);
  assert.deepEqual((await page.evaluate(() => window.__states)).filter(s => s.state !== 'connected'), [], 'never stale or reconnecting');
  assert.equal(state.sockets, 1, 'the same socket throughout');
});

// Proves: FR-021; CL-003-04; TC-021-007 case 5 (#8); level 2. A download that never completes
// still bounds silent loss: stale after more than 30 s without a message, within 31 s + 1 s.
test('TC-021-007: a pending deferred client download bounds silent loss at 31 s', {timeout: 90000}, async t => {
  const {page, state} = await deferredDownloadHold(t, 60000);
  const deadline = Date.now() + 45000;
  while (!state.held) {assert.ok(Date.now() < deadline, 'deferred download requested'); await sleep(50);}
  await page.locator('#connection[data-state=stale]').waitFor({timeout: 40000});
  const stale = (await page.evaluate(() => window.__states)).find(s => s.state === 'stale').at, silent = stale - Math.max(state.lastDelivered, state.logbookEnded ?? 0);
  assert.ok(silent >= 29900 && silent <= 32000, `stale after ${silent} ms without a message`);
  state.release();
  await page.locator('#connection[data-state=connected]').waitFor({timeout: 10000});
});

// Proves: FR-021; CL-003-05, CL-003-08; level 2, TLS byte-stream link model, not packet capture.
test('TC-021-008: 32 kbit/s shared TLS link and 60-second idle budget', {timeout: 110000}, async t => {
  const proxy = await link({host: '127.0.0.1', port: 1}); t.after(() => proxy.close());
  const origin = `https://127.0.0.1:${proxy.port}`;
  const app = await server({...tlsEnv, WSTX_ORIGIN: origin}); t.after(() => app.close());
  proxy.target.port = Number(new URL(app.endpoint).port);
  const contexts = await Promise.all([contextFor(origin, true), contextFor(origin, true)]); t.after(() => Promise.all(contexts.map(c => c.close())));
  const pages = await Promise.all(contexts.map(c => c.newPage()));
  const started = Date.now();
  const coldPages = await Promise.all(pages.map(async page => {
    await page.goto(origin);
    const pageLoaded = Date.now();
    const resources = await page.evaluate(() => [performance.getEntriesByType('navigation')[0], ...performance.getEntriesByType('resource')].map(entry => ({url: entry.name, transferBytes: entry.transferSize, encodedBodyBytes: entry.encodedBodySize, durationMs: entry.duration})));
    await page.locator('#connection[data-state="connected"]').waitFor({timeout: 10000});
    const statusAfterLoadMs = Date.now() - pageLoaded; assert.ok(statusAfterLoadMs < 10000);
    return {pageLoadMs: pageLoaded - started, statusAfterLoadMs, resources};
  }));
  const cold = {milliseconds: Date.now() - started, bytes: {...proxy.counters}, pages: coldPages};
  const baseline = {...proxy.counters}; const idleStart = Date.now();
  await sleep(60000);
  const seconds = (Date.now() - idleStart) / 1000;
  const mean = {up: (proxy.counters.up - baseline.up) / seconds, down: (proxy.counters.down - baseline.down) / seconds};
  for (const direction of ['up', 'down']) assert.ok(mean[direction] <= 1000, `${direction} ${mean[direction]} bytes/s`);
  const latencies = await Promise.all(pages.map(async page => {
    const previous = await page.locator('#updated').textContent(); const start = Date.now();
    await page.locator('#refresh').click();
    await page.waitForFunction(old => document.querySelector('#updated').textContent !== old, previous, {timeout: 2000});
    const milliseconds = Date.now() - start; assert.ok(milliseconds < 2000); return milliseconds;
  }));
  const result = {model: 'actual TLS stream + modelled TCP/IPv6/ACK overhead; no packet capture', cold, idleMeanBytesPerSecond: mean, concurrentVisibleRefreshMs: latencies};
  console.log(JSON.stringify(result)); await fs.writeFile('test-results/link-budget.json', JSON.stringify(result, null, 2));
});

// Proves: FR-021; CL-003-06; level 2, stalled socket and independent healthy peer.
test('TC-021-008: stalled reader cannot block another client', {timeout: 35000}, async t => {
  const app = await server(); t.after(() => app.close());
  const slow = await peer(app.origin, {autoPong: false}), healthy = await peer(app.origin);
  t.after(() => {slow.terminate(); healthy.terminate();});
  // Listen from the start: when the client's own pending writes fail against the closed
  // server socket (a reset), 'close' is emitted during the stall, before the resume.
  const closed = once(slow, 'close');
  slow._socket.pause();
  const text = '{"v":1,"type":"station.get","id":1}';
  for (let i = 0; i < 100000; i++) slow.send(text);
  const started = Date.now();
  assert.equal((await request(healthy, text)).type, 'station.status');
  assert.ok(Date.now() - started < 2000);
  // Remain unresponsive beyond the contract's 15-second Pong deadline and next
  // five-second heartbeat tick. The OS write buffer may absorb the burst, so this
  // proves bounded liveness disconnection, not that the two-second send timeout ran.
  await sleep(22000);
  slow._socket.resume();
  await Promise.race([closed, sleep(5000, undefined, {ref: false}).then(() => {throw new Error('Unresponsive reader was not disconnected after the liveness deadline');})]);
  assert.equal((await request(healthy, text)).type, 'station.status');
});

// Proves: FR-021; CL-003-07; level 2, disposable local TLS endpoint/credentials.
test('TC-021-009: TLS login, unauthorized/origin denial, plaintext refusal', async t => {
  const app = await server(tlsEnv); t.after(() => app.close());
  const context = await contextFor(app.origin); t.after(() => context.close()); const page = await context.newPage();
  await page.goto(app.origin); await page.locator('#login').waitFor({state: 'visible'});
  await page.locator('#token').fill(token); await page.locator('#login button').click();
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
  async function loginRequest(body, origin) {
    return new Promise((resolve, reject) => {
      const request = https.request(app.origin + '/session', {method: 'POST', rejectUnauthorized: false, headers: origin ? {Origin: origin} : {}}, response => {response.resume(); resolve(response.statusCode);});
      request.on('error', reject); request.end(body);
    });
  }
  assert.equal(await loginRequest(token), 403);
  assert.equal(await loginRequest(token, 'https://untrusted.invalid'), 403);
  assert.equal(await loginRequest('x'.repeat(1024), app.origin), 401);
  assert.equal(await loginRequest('x'.repeat(1025), app.origin), 413);
  await assert.rejects(server({WSTX_BIND: '0.0.0.0:0'}), /Remote binding/);
  await assert.rejects(server({...tlsEnv, WSTX_BIND: '0.0.0.0:0'}), /Remote binding/);
  await assert.rejects(server({...tlsEnv, WSTX_TOKEN: undefined, WSTX_BIND: '0.0.0.0:0', WSTX_ORIGIN: 'https://localhost'}), /Remote binding/);
  await assert.rejects(server({WSTX_TOKEN: token, WSTX_BIND: '0.0.0.0:0', WSTX_ORIGIN: 'https://localhost'}), /Remote binding/);
  await assert.rejects(server({WSTX_TOKEN: token}), /requires TLS/);
  await assert.rejects(server({...tlsEnv, WSTX_ORIGIN: 'https://localhost/extra'}), /WSTX_ORIGIN/);
  for (let i = 0; i < 10; i++) {
    const status = await page.evaluate(async () => (await fetch('/session', {method: 'POST', body: 'invalid'})).status);
    assert.equal(status, i < 8 ? 401 : 429);
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
