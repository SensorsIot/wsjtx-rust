'use strict';
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {once, EventEmitter} = require('node:events');
const {setTimeout: sleep} = require('node:timers/promises');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
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
async function contextFor() {
  return browser.newContext({ignoreHTTPSErrors: true});
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
// The hold ends only by state.release(); the page clock is installed before the page loads, so
// the test can drive it (#70).
async function deferredDownloadHold(t) {
  const dir = await fs.mkdtemp(path.join(temporary, 'deferred-')), port = await browserPort();
  const document = {schema_version: 1, profile_id: require('node:crypto').randomUUID(), revision: 0, display_name: 'Deferred', callsign: 'HB9BLA', locator: 'JN37VL',
    endpoint: {bind: `127.0.0.1:${port}`, origin: null}, connection_type: 'standard', audio: {input_device: null, output_device: null}, control: {mode: 'disabled', endpoint: null, ptt: 'disabled'}};
  await fs.writeFile(path.join(dir, 'profile.json'), JSON.stringify(document));
  const app = await server({}, ['--profile', dir]); t.after(() => app.close());
  const context = await contextFor(app.origin); t.after(() => context.close());
  const page = await context.newPage(), state = {held: false, queue: [], sockets: 0, release: null, holding: null, queued: null};
  state.whenHeld = new Promise(resolve => {state.holding = resolve;});
  await page.addInitScript(() => {
    window.__states = [];
    addEventListener('DOMContentLoaded', () => {const c = document.querySelector('#connection'); new MutationObserver(() => window.__states.push({at: Date.now(), state: c.dataset.state})).observe(c, {attributes: true, attributeFilter: ['data-state']});});
  });
  page.on('websocket', () => state.sockets++);
  await page.routeWebSocket(/\/ws$/, ws => {
    const station = ws.connectToServer();
    station.onMessage(message => {const deliver = () => {try {ws.send(message);} catch {}}; if (state.held) {state.queue.push(deliver); state.queued?.();} else deliver();});
  });
  await page.route('**/contact.js', async route => {
    state.held = true;
    await new Promise(resolve => {state.release = resolve; state.holding();});
    await route.continue(); state.held = false; for (const deliver of state.queue.splice(0)) deliver();
  });
  await page.clock.install();
  await page.goto(app.origin);
  await page.locator('#connection[data-state=connected]').waitFor({timeout: 10000});
  return {page, state};
}

// #70: the 16 s hold runs on the page's driven clock (the watchdog is a page setInterval on Date.now()).
// Proves: FR-021; CL-003-04; TC-021-007 case 5 (#8); level 2, profile station, real Chromium.
test('TC-021-007: a deferred client download that holds station messages 16 s is not a lost link', {timeout: 30000}, async t => {
  const {page, state} = await deferredDownloadHold(t);
  await state.whenHeld;
  // A station message while the download is pending: it queues behind the download.
  const queued = new Promise(resolve => {state.queued = resolve;});
  await page.evaluate(() => socket.send(JSON.stringify({v: 1, type: 'station.get', id: 7016})));
  await queued;
  // 16 watchdog ticks: past the 12 s bound without a download, inside the 30 s bound with one.
  await page.clock.runFor(16000);
  assert.ok(state.held && state.queue.length > 0, 'the station messages were held behind the download');
  assert.deepEqual((await page.evaluate(() => window.__states)).filter(s => s.state !== 'connected'), [], 'not stale after 16 s held');
  state.release();
  await page.waitForFunction(() => !!window.wstxContact, null, {timeout: 10000});
  assert.deepEqual((await page.evaluate(() => window.__states)).filter(s => s.state !== 'connected'), [], 'never stale or reconnecting');
  assert.equal(state.sockets, 1, 'the same socket throughout');
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

// #102 evidence (no promise): each path that makes the page stale names itself as the
// station-stale event's detail.path. The labels, from the path list of issue #102.
const stalePaths = ['watchdog', 'message-rejected', 'profile-refresh-failed', 'recording-sync-failed', 'socket-closed', 'opening-timeout',
  'authorization-unavailable', 'authorization-not-ready', 'authorization-retry', 'component-missing', 'login-failed'];
// The argument that carries the label, by the called function.
const labelArgument = {stale: 0, disconnect: 1, loseSocket: 0, showAuthorizationUnavailable: 1};
// The arguments of the call whose '(' is at `open`, split at top-level commas (strings skipped).
function callArguments(text, open) {
  const args = []; let depth = 0, from = open + 1;
  for (let i = open; i < text.length; i++) {
    const c = text[i];
    if (c === '\'' || c === '"' || c === '`') {for (i++; i < text.length && text[i] !== c; i++) if (text[i] === '\\') i++; continue;}
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c) && --depth === 0) {const last = text.slice(from, i).trim(); if (last || args.length) args.push(last); return args;}
    else if (c === ',' && depth === 1) {args.push(text.slice(from, i).trim()); from = i + 1;}
  }
  throw new Error(`unterminated call at ${open}`);
}
function blockEnd(text, open) {
  let depth = 0;
  for (let i = open; i < text.length; i++) {if (text[i] === '{') depth++; else if (text[i] === '}' && --depth === 0) return i;}
  return text.length;
}
// Every call of stale, disconnect, loseSocket and showAuthorizationUnavailable in the served
// client passes a label from the list. The one exception: inside disconnect, loseSocket and
// showAuthorizationUnavailable the inner call passes that function's own path parameter on.
function assertStalePaths(sources) {
  const sites = [], problems = [];
  for (const [file, raw] of Object.entries(sources)) {
    const text = raw.replace(/\r\n/g, '\n'), lineOf = at => `${file}:${text.slice(0, at).split('\n').length}`;
    const forwarding = [];
    for (const [name, pattern] of [['disconnect', /function disconnect\(([^)]*)\)\s*\{/g], ['showAuthorizationUnavailable', /function showAuthorizationUnavailable\(([^)]*)\)\s*\{/g],
      ['loseSocket', /const loseSocket = \(?([^)=]*?)\)? =>\s*\{/g]]) {
      for (const match of text.matchAll(pattern)) {
        const open = match.index + match[0].length - 1;
        forwarding.push({name, start: open, end: blockEnd(text, open), parameter: match[1].split(',').map(p => p.trim())[labelArgument[name]]});
      }
    }
    for (const match of text.matchAll(/(?<![\w.]|function )(stale|disconnect|loseSocket|showAuthorizationUnavailable)\(/g)) {
      const label = callArguments(text, match.index + match[0].length - 1)[labelArgument[match[1]]], where = lineOf(match.index);
      const literal = /^'([^']*)'$/.exec(label ?? '');
      if (literal) {
        if (stalePaths.includes(literal[1])) sites.push({where, label: literal[1]});
        else problems.push(`${where}: ${match[1]} passes an unknown label ${label}`);
        continue;
      }
      const inside = forwarding.find(f => match.index > f.start && match.index < f.end);
      if (inside && /^[A-Za-z_$][\w$]*$/.test(label ?? '') && label === inside.parameter) sites.push({where, forwards: inside.name});
      else problems.push(`${where}: ${match[1]} passes no label from the list (${label ?? 'none'})`);
    }
    // A bare reference (onclose = loseSocket) would hand its event on as the label.
    for (const match of text.matchAll(/(?<![\w.])loseSocket\b(?!\s*\()/g)) if (!text.slice(Math.max(0, match.index - 6), match.index).endsWith('const ')) problems.push(`${lineOf(match.index)}: loseSocket referenced without its label`);
  }
  assert.deepEqual(problems, [], 'every stale call names its path');
  assert.ok(sites.length > 0, 'no call site of the stale paths found');
  const labelled = new Set(sites.map(s => s.label));
  assert.deepEqual(stalePaths.filter(label => !labelled.has(label)), [], 'each stale path label appears at its call site');
  return sites;
}

// Evidence of #102 item 2, source scan of the served client.
test('Stale path labels: every stale call of the served client names its path', async t => {
  const app = await server(); t.after(() => app.close());
  const served = {};
  for (const file of ['app.js', 'recording.js']) {const response = await fetch(`${app.origin}/${file}`); assert.equal(response.status, 200, file); served[file] = await response.text();}
  const sites = assertStalePaths(served);
  assert.deepEqual(sites.filter(s => s.forwards).map(s => s.forwards).sort(), ['disconnect', 'loseSocket', 'showAuthorizationUnavailable', 'showAuthorizationUnavailable'], 'the four forwarding calls');
  // Fault controls: a call without a label, an unknown label, another variable forwarded, the
  // bare onclose binding, a label lost and no call site at all are each refused.
  const source = served['app.js'].replace(/\r\n/g, '\n');
  const variant = (from, to) => {assert.ok(source.includes(from), from); return {...served, 'app.js': source.replace(from, to)};};
  assert.throws(() => assertStalePaths({...served, 'extra.js': 'stale();'}), /passes no label from the list \(none\)/);
  assert.throws(() => assertStalePaths({...served, 'extra.js': 'disconnect(socket, \'gone\');'}), /unknown label 'gone'/);
  assert.throws(() => assertStalePaths(variant('stale(path); current.onclose', 'stale(current); current.onclose')), /stale passes no label from the list \(current\)/);
  const unlabelled = variant('stale(path); current.onclose', 'stale(); current.onclose');
  unlabelled['app.js'] = unlabelled['app.js'].replace('function disconnect(current, path)', 'function disconnect(current)');
  assert.throws(() => assertStalePaths(unlabelled), /stale passes no label from the list \(none\)/, 'a forwarding function without a path parameter');
  assert.throws(() => assertStalePaths(variant('current.onclose = () => loseSocket(\'socket-closed\');', 'current.onclose = loseSocket;')), /loseSocket referenced without its label|socket-closed/);
  assert.throws(() => assertStalePaths(variant('showAuthorizationUnavailable(error, \'login-failed\')', 'showAuthorizationUnavailable(error, \'authorization-unavailable\')')), /each stale path label/);
  assert.throws(() => assertStalePaths({'empty.js': 'const x = 1;'}), /no call site/);
});

// Evidence of #102 item 2, real Chromium against the station: the station side closes the page's
// socket, every station message is held while the page clock runs 13000 ms, and a message of
// another version arrives. Each makes the page stale once, naming its path.
test('Stale path labels: socket closed, silence watchdog and rejected message in real Chromium', {timeout: 60000}, async t => {
  const app = await server(); t.after(() => app.close());
  async function stalePage(clock) {
    const context = await contextFor(); t.after(() => context.close());
    const page = await context.newPage(), route = {ws: null, held: false};
    await page.addInitScript(() => {
      window.__stale = [];
      addEventListener('station-stale', event => window.__stale.push({at: Date.now(), path: event.detail?.path ?? null, silence: Date.now() - lastMessage, readyState: socket?.readyState ?? null}));
    });
    await page.routeWebSocket(/\/ws$/, ws => {
      if (route.ws) {ws.connectToServer(); return;}
      route.ws = ws;
      ws.connectToServer().onMessage(message => {if (!route.held) ws.send(message);});
    });
    if (clock) await page.clock.install();
    await connected(page, app.origin);
    return {page, route, stale: () => page.evaluate(() => window.__stale)};
  }
  const reconnected = page => page.locator('#connection[data-state="connected"]').waitFor({timeout: 10000});

  // (a) The station side closes the page's socket.
  const closed = await stalePage(false);
  await closed.route.ws.close();
  await closed.page.waitForFunction(() => window.__stale.length > 0, null, {timeout: 10000});
  await reconnected(closed.page);
  const [onClose, ...moreClose] = await closed.stale();
  assert.equal(onClose.path, 'socket-closed'); assert.equal(onClose.readyState, 3, 'the ended socket is CLOSED');
  assert.deepEqual(moreClose, [], 'one stale');

  // (b) Every station message held while the page clock runs: the watchdog's 1000 ms check fires
  // at the first tick more than 12000 ms (clientSilenceMs) after the last counted message.
  const silent = await stalePage(true);
  silent.route.held = true;
  for (let ms = 0; ms < 13000 && (await silent.stale()).length === 0; ms += 1000) await silent.page.clock.runFor(1000);
  const [watchdog, ...moreWatchdog] = await silent.stale();
  assert.equal(watchdog?.path, 'watchdog');
  assert.ok(watchdog.silence > 12000 && watchdog.silence <= 13000, `silence ${watchdog.silence} ms`);
  assert.deepEqual(moreWatchdog, [], 'one stale');

  // (c) A message the page refuses (v 2).
  const rejected = await stalePage(false);
  rejected.route.ws.send('{"v":2,"type":"heartbeat"}');
  await rejected.page.waitForFunction(() => window.__stale.length > 0, null, {timeout: 10000});
  await reconnected(rejected.page);
  const [onRejected, ...moreRejected] = await rejected.stale();
  assert.equal(onRejected.path, 'message-rejected');
  assert.deepEqual(moreRejected, [], 'one stale');
});
