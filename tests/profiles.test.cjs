'use strict';
// Independent oracle: approved FSD 4.2/6.2/12.5, NOT the product/model serializers.
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const net = require('node:net');
const http = require('node:http');
const https = require('node:https');
const {spawn, execFileSync} = require('node:child_process');
const {once} = require('node:events');
const crypto = require('node:crypto');
const {chromium} = require('playwright');
const selfsigned = require('selfsigned');
const WebSocket = require('ws');
const {receive} = require('./peer.cjs');
let root, browser, tls, retainFixtureRoot = false;
const exe = process.env.WSTX_TEST_EXE || path.resolve(process.env.CARGO_TARGET_DIR || 'target', 'debug', 'wstx-rust.exe');
const uuid = i => `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`;
const settings = i => ({display_name: `Station ${i}`, callsign: `TEST${i}`, locator: 'JN47AA', audio: {input_device: `fixture-input-${i}`, output_device: `fixture-output-${i}`}, control: {mode: 'disabled', endpoint: null, ptt: 'disabled'}});
before(async () => {
  assert.equal(['DEBUG', 'PWDEBUG', 'DEBUG_FILE', 'PLAYWRIGHT_TRACE_DIR', 'NODE_DEBUG', 'NODE_DEBUG_NATIVE', 'NODE_OPTIONS'].some(key => Boolean(process.env[key])), false, 'Credential-sensitive tracing and Node preloads are unsupported before fixture setup');
  assert.ok(await fs.stat(exe), 'compiled candidate is required');
  root = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-profile-tests-'));
  const cert = await selfsigned.generate([{name: 'commonName', value: 'localhost'}], {days: 1, keySize: 2048, extensions: [{name: 'subjectAltName', altNames: [{type: 2, value: 'localhost'}, {type: 7, ip: '127.0.0.1'}]}]});
  const certPath = path.join(root, 'cert.pem'), keyPath = path.join(root, 'key.pem');
  await fs.writeFile(certPath, cert.cert); await fs.writeFile(keyPath, cert.private, {mode: 0o600});
  tls = {WSTX_TLS_CERT: certPath, WSTX_TLS_KEY: keyPath};
  browser = await chromium.launch();
});
after(async () => {
  await browser?.close();
  if (root && !retainFixtureRoot) await fs.rm(root, {recursive: true, force: true});
  else if (root) console.error('Retained owned fixture root after unqualified persistent cleanup:', root);
});
async function ports(n) {
  const held = [];
  try {for (let i = 0; i < n; i++) {const s = net.createServer(); s.listen(0, '127.0.0.1'); await once(s, 'listening'); held.push(s);} return held.map(s => s.address().port);}
  finally {await Promise.all(held.map(s => new Promise(resolve => s.close(resolve))));}
}
function launch(args, env = {}, cwd) {
  const clean = {...process.env}; for (const key of Object.keys(clean)) if (key.startsWith('WSTX_')) delete clean[key];
  const child = spawn(exe, args, {cwd, env: {...clean, ...env}, windowsHide: true});
  let output = ''; child.stdout.on('data', b => {output = (output + b).slice(-16384);}); child.stderr.on('data', b => {output = (output + b).slice(-16384);});
  const done = once(child, 'exit');
  return {child, get output() {return output;}, done, async close() {if (child.exitCode === null && child.signalCode === null) {child.kill(); await done;}}};
}
async function start(profile, env = {}, cwd) {
  const app = launch(['--profile', profile.dir], env, cwd);
  const deadline = Date.now() + 10000;
  while (!app.output.includes(`WSTX listening ${profile.origin}`)) {
    if (app.child.exitCode !== null || app.child.signalCode !== null || Date.now() > deadline) {await app.close(); assert.fail('Profile readiness failed: ' + app.output);}
    await new Promise(r => setTimeout(r, 20));
  }
  return app;
}
async function refusal(args, category, env = {}, cwd) {
  const app = launch(args, env, cwd); const timer = setTimeout(() => app.child.kill(), 10000);
  try {const [code, signal] = await app.done; assert.equal(signal, null, 'must fail explicitly, not time out'); assert.notEqual(code, 0); assert.match(app.output, new RegExp(`\\b${category}\\b`)); assert.doesNotMatch(app.output, /WSTX listening/);}
  finally {clearTimeout(timer); await app.close();}
}
async function fixture(t, secured = false) {
  const base = await fs.mkdtemp(path.join(root, 'case-')), selectedPorts = await ports(4);
  const profiles = [];
  for (let i = 1; i <= 4; i++) {
    const port = selectedPorts[i - 1], dir = path.join(base, `profile-${i}`), origin = `${secured ? 'https://localhost' : 'http://127.0.0.1'}:${port}`;
    const document = {schema_version: 1, profile_id: uuid(i), revision: 0, ...settings(i), endpoint: {bind: `127.0.0.1:${port}`, origin: secured ? origin : null}, connection_type: 'standard'};
    await fs.mkdir(dir); await fs.writeFile(path.join(dir, 'profile.json'), JSON.stringify(document));
    const env = secured ? {...tls, WSTX_TOKEN: crypto.randomBytes(32).toString('hex')} : {};
    profiles.push({dir, origin, document, env});
  }
  const apps = []; t.after(async () => {await Promise.all(apps.map(app => app.close())); for (const p of profiles) if (p.env.WSTX_TOKEN && p.app) {assert.equal(p.app.output.includes(p.env.WSTX_TOKEN), false); assert.equal((await fs.readFile(path.join(p.dir, 'profile.json'), 'utf8')).includes(p.env.WSTX_TOKEN), false);}});
  for (const p of profiles) {const app = await start(p, p.env); apps.push(app); p.app = app;}
  return {profiles, apps, base};
}
function request(origin, method = 'GET', body, headers = {}, pathname = '/profile') {
  return new Promise((resolve, reject) => {
    const proof = ['/authorization/v1/proof', '/authorization/v1/enroll', '/authorization/v1/receipt'].includes(pathname);
    if (pathname !== '/profile' && !proof) {reject(new Error('Unsupported test request path')); return;}
    if (proof) {
      const expected = new URL(origin), originHeaders = Object.entries(headers).filter(([name]) => name.toLowerCase() === 'origin');
      const mediaHeaders = Object.entries(headers).filter(([name]) => name.toLowerCase() === 'content-type');
      if (expected.protocol !== 'https:' || expected.origin !== origin || !['localhost', '127.0.0.1', '[::1]'].includes(expected.hostname) ||
          method !== 'POST' || !Buffer.isBuffer(body) || !body.length || body.length > 1024 ||
          originHeaders.length !== 1 || originHeaders[0][1] !== origin || mediaHeaders.length !== 1 || mediaHeaders[0][1] !== 'application/json') {
        reject(new Error('Invalid proof forwarding context')); return;
      }
    }
    let timer;
    const fail = error => {if (proof) {clearTimeout(timer); reject(new Error('Proof forwarding failed'));} else reject(error);};
    const req = (origin.startsWith('https') ? https : http).request(origin + pathname, {method, rejectUnauthorized: false, agent: false, headers: {Origin: origin, ...(body !== undefined ? {'Content-Type': 'application/json'} : {}), ...headers}}, res => {
      let data = '', bytes = 0;
      res.on('data', b => {bytes += b.length; if (proof && bytes > 1024) {req.destroy(); res.destroy(); fail(); return;} data += b;});
      res.on('end', () => {
        const completedAt = performance.now();
        if (proof) clearTimeout(timer);
        if (proof) {try {resolve({status: res.statusCode, body: data ? JSON.parse(data) : null, bodyBytes: bytes, headers: res.headers, rawBody: data, completedAt});} catch {fail();}}
        else resolve({status: res.statusCode, body: data ? JSON.parse(data) : null, bodyBytes: Buffer.byteLength(data, 'utf8'), headers: res.headers});
      });
      if (proof) {res.on('error', fail); res.on('aborted', () => fail());}
    });
    req.on('error', fail);
    if (proof) {timer = setTimeout(() => {req.destroy(); fail();}, 10000); req.end(body);}
    else {if (body !== undefined) req.write(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body)); req.end();}
  });
}
const edit = (i, revision, value = settings(i), id = uuid(i)) => ({profile_id: id, revision, settings: value});
async function browserWindows(t, profiles) {
  const context = await browser.newContext({ignoreHTTPSErrors: true}); t.after(() => context.close());
  const launcher = await context.newPage(), pages = [];
  for (const p of profiles) {const opened = context.waitForEvent('page'); await launcher.evaluate(({url, name}) => {window.open(url, name, 'popup,width=1100,height=850');}, {url: p.origin, name: p.document.profile_id}); pages.push(await opened);}
  await launcher.close(); return {context, pages};
}
async function connected(page) {
  await page.locator('#connection[data-state="connected"]').waitFor({timeout: 10000});
  if(await page.locator('#open-server-settings').count())await page.locator('#open-server-settings').click();
  const settings=page.locator('#station-settings');
  if(await settings.count() && !await settings.evaluate(el=>el.open))await settings.locator('summary').click();
}
async function savedBytes(profiles) {return Promise.all(profiles.map(p => fs.readFile(path.join(p.dir, 'profile.json'), 'utf8')));}

// Proves the CL-022-01 browser proof path against independent cryptographic bytes.
test('TC-022-006: retained HTTPS browser authorization', {timeout: 45000}, async t => {
  const {profiles} = await fixture(t, true), p = profiles[0];
  const context = await browser.newContext({ignoreHTTPSErrors: true}); t.after(() => context.close());
  const page = await context.newPage(), proofs = [], challenges = [], enrollments = [], sessions = [];
  page.on('request', request => {
    if (request.url().endsWith('/authorization/v1/proof')) proofs.push(JSON.parse(request.postData()));
    if (request.url().endsWith('/authorization/v1/enroll')) enrollments.push(JSON.parse(request.postData()));
    if (request.url().endsWith('/session')) sessions.push(request.method());
  });
  page.on('response', response => {
    if (response.url().endsWith('/authorization/v1/challenge') && response.status() === 200) challenges.push(response.json());
  });
  await page.goto(p.origin);
  await page.locator('#login').waitFor({state: 'visible'});
  await page.locator('#token').fill(p.env.WSTX_TOKEN); await page.locator('#login button').click();
  await connected(page);
  assert.equal(await page.locator('#token').inputValue(), '');
  assert.equal(enrollments.length, 1); assert.equal(proofs.length, 1); assert.equal(sessions.length, 1);
  const enrolled = enrollments[0], challenge = await challenges[0], proof = proofs[0];
  assert.equal(challenge.grant_id, enrolled.grant_id); assert.equal(challenge.public_key, enrolled.public_key);
  const expected = [Buffer.from('WSTX-AUTH-PROOF'), Buffer.from([1])];
  for (const part of [Buffer.from(p.origin), Buffer.from(challenge.scope.profile_id), Buffer.from(challenge.scope.radio_id),
    Buffer.from(String(challenge.scope.safety_revision)), Buffer.from(enrolled.grant_id), Buffer.from(challenge.nonce, 'base64url')]) {
    const length = Buffer.alloc(4); length.writeUInt32BE(part.length); expected.push(length, part);
  }
  const raw = Buffer.from(enrolled.public_key, 'base64url');
  const key = crypto.createPublicKey({format: 'jwk', key: {kty: 'EC', crv: 'P-256', x: raw.subarray(1, 33).toString('base64url'), y: raw.subarray(33).toString('base64url')}});
  const signed = Buffer.concat(expected), signature = Buffer.from(proof.signature, 'base64url');
  assert.equal(signature.length, 64);
  assert.equal(crypto.verify('sha256', signed, {key, dsaEncoding: 'ieee-p1363'}, signature), true);
  const tampered = Buffer.from(signed); tampered[0] ^= 1;
  assert.equal(crypto.verify('sha256', tampered, {key, dsaEncoding: 'ieee-p1363'}, signature), false);
  await context.clearCookies(); await page.reload(); await connected(page);
  assert.equal(enrollments.length, 1, 'transport recovery does not enroll another grant');
  assert.equal(sessions.length, 1, 'transport recovery never resubmits the bootstrap token');
  assert.equal(proofs.length, 2); assert.equal(proofs[1].grant_id, enrolled.grant_id);
  assert.notEqual(proofs[1].nonce, proof.nonce);
  assert.equal(await page.evaluate(async () => {
    const db = await new Promise((resolve, reject) => {const request = indexedDB.open('wstx-authorization-v1', 1); request.onsuccess = () => resolve(request.result); request.onerror = reject;});
    const value = await new Promise((resolve, reject) => {const request = db.transaction('credential').objectStore('credential').get('current'); request.onsuccess = () => resolve(request.result); request.onerror = reject;});
    db.close();
    try {await crypto.subtle.exportKey('pkcs8', value.key); return false;} catch {return value.key.extractable === false && value.key.usages.join(',') === 'sign';}
  }), true);
});

// Proves CL-022-01/02/05 ordinary cross-tab transport rotation; response-order faults remain separate.
test('TC-022-006: actual two tabs share retained authorization and rotated transport', {timeout: 45000}, async t => {
  const {profiles} = await fixture(t, true), p = profiles[0];
  const context = await browser.newContext({ignoreHTTPSErrors: true}); t.after(() => context.close());
  const counts = {session: 0, enroll: 0, bootstrapScope: 0, challenge: 0, proof: 0, status: 0, profile: 0};
  const timeline = [], peers = [], snapshots = [];
  function observe(page, label) {
    page.on('request', request => {
      const url = new URL(request.url()); if (url.origin !== p.origin) return;
      const key = {'/session': 'session', '/authorization/v1/enroll': 'enroll', '/authorization/v1/bootstrap-scope': 'bootstrapScope',
        '/authorization/v1/challenge': 'challenge', '/authorization/v1/proof': 'proof', '/authorization/v1/status': 'status', '/profile': 'profile'}[url.pathname];
      if (key) {counts[key]++; timeline.push({label, method: request.method(), path: url.pathname, at: performance.now()});}
    });
    page.on('response', response => {
      const url = new URL(response.url());
      if (url.origin === p.origin && (url.pathname.startsWith('/authorization/v1/') || url.pathname === '/profile' || url.pathname === '/session'))
        timeline.push({label, path: url.pathname, status: response.status(), at: performance.now()});
    });
    page.on('websocket', ws => {
      const peer = {label, ws, frames: 0, errors: 0}; peers.push(peer);
      ws.on('framereceived', () => {peer.frames++;}); ws.on('socketerror', () => {peer.errors++;});
    });
  }
  async function credential(page) {
    return page.evaluate(async () => {
      const db = await new Promise((resolve, reject) => {const request = indexedDB.open('wstx-authorization-v1', 1); request.onupgradeneeded = () => request.transaction.abort(); request.onerror = () => reject(new Error('Retained credential missing')); request.onsuccess = () => resolve(request.result);});
      try {
        const value = await new Promise((resolve, reject) => {const request = db.transaction('credential').objectStore('credential').get('current'); request.onsuccess = () => resolve(request.result); request.onerror = () => reject(new Error('Retained credential unavailable'));});
        if (!value || !(value.key instanceof CryptoKey)) throw new Error('Retained signing key missing');
        return {grant_id: value.grant_id, public_key: value.public_key, enrollment_id: value.enrollment_id,
          scope: value.scope, extractable: value.key.extractable, usages: value.key.usages};
      } finally {db.close();}
    });
  }
  const fileHashes = async () => Object.fromEntries(await Promise.all(['profile.json', 'authorization.json'].map(async name => [name, crypto.createHash('sha256').update(await fs.readFile(path.join(p.dir, name))).digest('hex')])));
  const a = await context.newPage(); observe(a, 'A'); await a.goto(p.origin);
  await a.locator('#login').waitFor({state: 'visible'});
  await a.locator('#token').fill(p.env.WSTX_TOKEN); await a.locator('#login button').click(); await connected(a);
  await a.evaluate(() => {window.__twoTabOriginalSocket = socket;});
  const firstCredential = await credential(a), beforeFiles = await fileHashes();
  const cookieName = `wstx_session_${p.document.profile_id}`;
  const oldCookie = (await context.cookies(p.origin)).find(cookie => cookie.name === cookieName);
  assert.ok(oldCookie, 'initial selected transport cookie exists');
  const b = await context.newPage(); observe(b, 'B');
  // Observe B's real post-proof status; the later extra request is the explicit11th-attempt boundary.
  const bStatusResponse = b.waitForResponse(response => response.url() === p.origin + '/authorization/v1/status' &&
    response.request().method() === 'POST', {timeout: 10000}).catch(() => null);
  await b.goto(p.origin); await connected(b);
  await b.evaluate(() => {window.__twoTabOriginalSocket = socket;});
  const secondCredential = await credential(b), newCookie = (await context.cookies(p.origin)).find(cookie => cookie.name === cookieName);
  assert.ok(newCookie, 'rotated selected transport cookie exists');
  const oldProfile = await request(p.origin, 'GET', undefined, {Cookie: `${cookieName}=${oldCookie.value}`});
  const currentProfiles = [], statuses = []; let rateLimitedStatus;
  for (const page of [a, b]) {
    currentProfiles.push(await page.evaluate(async () => {
      const response = await window.stationAuthorization.fetch('/profile', {cache: 'no-store'}), value = await response.json();
      return {status: response.status, profile: value.profile_id, boot: value.boot_id};
    }));
    const observedStatus = await page.evaluate(async () => {
      const response = await window.stationAuthorization.fetch('/authorization/v1/status', {method: 'POST', cache: 'no-store',
        headers: {'Content-Type': 'application/json'}, body: JSON.stringify({version: 1})});
      const text = await response.text(); return {status: response.status, bytes: new TextEncoder().encode(text).length, value: JSON.parse(text)};
    });
    if (page === a) statuses.push(observedStatus);
    else {
      rateLimitedStatus = observedStatus;
      const response = await bStatusResponse; assert.ok(response, 'actual B post-proof status observed within original10s');
      const text = await response.text(); statuses.push({status: response.status(), bytes: Buffer.byteLength(text), value: JSON.parse(text)});
    }
    snapshots.push(await page.evaluate(() => ({connection: connection.dataset.state, sameSocket: socket === window.__twoTabOriginalSocket,
      originalState: window.__twoTabOriginalSocket?.readyState, currentState: socket?.readyState, boot: profileData?.boot_id,
      authorization: window.stationAuthorization.snapshot(), loginHidden: document.querySelector('#login').hidden,
      tokenEmpty: document.querySelector('#token').value === '', localKeys: Object.keys(localStorage), sessionKeys: Object.keys(sessionStorage)})));
  }
  const afterFiles = await fileHashes(), sameFiles = JSON.stringify(beforeFiles) === JSON.stringify(afterFiles);
  const sameCredential = JSON.stringify(firstCredential) === JSON.stringify(secondCredential);
  const authResponses = timeline.filter(item => item.status !== undefined && (item.path === '/session' || item.path.startsWith('/authorization/v1/')));
  const peerEvidence = peers.map(peer => ({label: peer.label, frames: peer.frames, errors: peer.errors, closed: peer.ws.isClosed()}));
  t.diagnostic(JSON.stringify({scope: 'ordinary two actual tabs only; no lost/reordered response claim', counts, timeline,
    cookieChanged: oldCookie.value !== newCookie.value, oldCookieStatus: oldProfile.status, currentProfiles, statuses, rateLimitedStatus,
    snapshots, sameCredential, sameFiles, peerEvidence}));
  assert.equal(oldCookie.value === newCookie.value, false, 'second retained proof rotates shared transport');
  assert.equal(oldProfile.status, 401, 'replaced transport cannot authorize a new protected request');
  assert.equal(sameCredential, true, 'same origin retains one key/grant/operation tuple across real tabs');
  assert.equal(firstCredential.extractable, false); assert.deepEqual(firstCredential.usages, ['sign']);
  assert.deepEqual(Object.keys(firstCredential.scope).sort(), ['profile_id', 'radio_id', 'safety_revision']);
  assert.equal(firstCredential.scope.profile_id, p.document.profile_id); assert.equal(firstCredential.scope.safety_revision, 1);
  assert.match(firstCredential.scope.radio_id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(sameFiles, true, 'ordinary proof/status does not rewrite durable verifier/settings/receipt bytes');
  assert.equal(counts.session, 1); assert.equal(counts.enroll, 1); assert.equal(counts.bootstrapScope, 1);
  assert.equal(counts.challenge, 2); assert.equal(counts.proof, 2); assert.equal(counts.status, 4);
  const authV1Requests = counts.bootstrapScope + counts.enroll + counts.challenge + counts.proof + counts.status;
  assert.equal(authV1Requests, 10); assert.equal(authV1Requests + counts.session, 11, 'session shares original10/60 budget; final extra status is11th');
  assert.deepEqual(authResponses.map(item => item.status), [204, 200, 200, 200, 204, 200, 200, 204, 200, 200, 429], 'first10 actual admissions accepted, only11th refused');
  assert.equal(authResponses.at(-1).label, 'B'); assert.equal(authResponses.at(-1).path, '/authorization/v1/status');
  assert.equal(rateLimitedStatus.status, 429); assert.equal(rateLimitedStatus.bytes <= 1024, true);
  assert.deepEqual(rateLimitedStatus.value, {error: {code: 'rate_limited', field: null}});
  assert.equal(peers.length, 2);
  for (const peer of peerEvidence) {assert.equal(peer.closed, false); assert.equal(peer.frames > 0, true); assert.equal(peer.errors, 0);}
  for (let i = 0; i < 2; i++) {
    const snapshot = snapshots[i], status = statuses[i];
    assert.equal(currentProfiles[i].status, 200); assert.equal(currentProfiles[i].profile, p.document.profile_id);
    assert.equal(currentProfiles[i].boot, snapshots[0].boot); assert.equal(snapshot.boot, snapshots[0].boot);
    assert.equal(snapshot.connection, 'connected'); assert.equal(snapshot.sameSocket, true);
    assert.equal(snapshot.originalState, 1); assert.equal(snapshot.currentState, 1); assert.equal(snapshot.authorization.ready, true);
    assert.deepEqual(snapshot.authorization.scope, firstCredential.scope); assert.equal(snapshot.loginHidden, true); assert.equal(snapshot.tokenEmpty, true);
    assert.deepEqual(snapshot.localKeys, []); assert.deepEqual(snapshot.sessionKeys, []);
    assert.equal(status.status, 200); assert.equal(status.bytes <= 1024, true);
    assert.deepEqual(Object.keys(status.value).sort(), ['commissioned', 'condition', 'error', 'receive_state', 'retry_after_ms', 'scope', 'version']);
    assert.equal(status.value.version, 1); assert.deepEqual(status.value.scope, firstCredential.scope);
    assert.equal(status.value.condition, 'disabled'); assert.equal(status.value.commissioned, false);
    assert.equal(status.value.error, null); assert.equal(status.value.retry_after_ms, null);
    assert.deepEqual(Object.keys(status.value.receive_state).sort(), ['audio', 'decoder']);
    assert.equal(status.value.receive_state.audio, 'closed'); assert.equal(status.value.receive_state.decoder, null, 'no live job has no decoder state');
  }
});

// Proves CL-022-01/02: a real proof commit is distinct from delivery of its cookie.
test('TC-022-006: real proof cookie waits for browser delivery', {timeout: 45000}, async t => {
  const {profiles} = await fixture(t, true), p = profiles[0];
  const context = await browser.newContext({ignoreHTTPSErrors: true}), page = await context.newPage();
  const cookieName = `wstx_session_${p.document.profile_id}`, timeline = [], frames = [];
  let observer, openTimer, closeTimer, deliveryTimer, routeWork, pendingRoute, forwarded;
  let routeFailed = false, fulfilled = false, handled = false, observerForced = false;
  const proofObservation = {phase: 'waiting', actualStatus: null, responseBytes: null, cookieCount: null};
  let jarAbsent = null, jarMatches = null;
  const fileHashes = async () => Object.fromEntries(await Promise.all(['profile.json', 'authorization.json'].map(async name => [name, crypto.createHash('sha256').update(await fs.readFile(path.join(p.dir, name))).digest('hex')])));
  page.on('request', request => {const url = new URL(request.url()); if (url.origin === p.origin && !url.pathname.startsWith('/assets/')) timeline.push({path: url.pathname, method: request.method(), at: performance.now()});});
  page.on('response', response => {const url = new URL(response.url()); if (url.origin === p.origin && (url.pathname === '/session' || url.pathname.startsWith('/authorization/v1/') || url.pathname.startsWith('/receive/') || url.pathname === '/profile')) timeline.push({path: url.pathname, status: response.status(), at: performance.now()});});
  const handler = route => {
    if (handled) return route.continue(); handled = true; pendingRoute = route;
    routeWork = (async () => {
      try {
        const original = route.request(), headers = await original.allHeaders(), body = original.postDataBuffer();
        if (original.url() !== p.origin + '/authorization/v1/proof' || original.method() !== 'POST' ||
            headers.origin !== p.origin || headers['content-type'] !== 'application/json' || !Buffer.isBuffer(body) || !body.length || body.length > 1024) throw new Error('Invalid original proof request');
        proofObservation.phase = 'original-validated'; proofObservation.proofBytes = body.length;
        const beforeFiles = await fileHashes(); // Enrollment has committed before this genuine proof exists.
        const response = await request(p.origin, 'POST', body, {Origin: headers.origin, 'Content-Type': headers['content-type'], ...(headers.cookie ? {Cookie: headers.cookie} : {})}, '/authorization/v1/proof');
        const cookies = response.headers['set-cookie'];
        proofObservation.phase = 'server-replied'; proofObservation.actualStatus = response.status; proofObservation.responseBytes = response.bodyBytes; proofObservation.cookieCount = Array.isArray(cookies) ? cookies.length : 0;
        if (response.status !== 204 || response.bodyBytes !== 0 || !Array.isArray(cookies) || cookies.length !== 1) throw new Error('Invalid actual proof response');
        const pair = cookies[0].split(';')[0], prefix = cookieName + '=';
        if (!pair.startsWith(prefix) || !/^[A-Za-z0-9_-]{43}$/.test(pair.slice(prefix.length))) throw new Error('Invalid actual transport cookie');
        forwarded = {response, beforeFiles, cookie: pair.slice(prefix.length), proofBytes: body.length, heldAt: performance.now()};
        deliveryTimer = setTimeout(() => {routeFailed = true; route.abort('failed').catch(() => {});}, 5000);
        const beforeDelivery = (await context.cookies(p.origin)).filter(cookie => cookie.name === cookieName);
        jarAbsent = beforeDelivery.length === 0;
        if (!jarAbsent || routeFailed || performance.now() - forwarded.heldAt > 5000) throw new Error('Proof delivery qualification expired');
        await route.fulfill({status: response.status, body: '', headers: {'set-cookie': cookies[0], ...(response.headers['cache-control'] ? {'cache-control': response.headers['cache-control']} : {}), ...(response.headers['content-type'] ? {'content-type': response.headers['content-type']} : {})}});
        fulfilled = true; proofObservation.phase = 'browser-fulfilled';
      } catch {
        routeFailed = true; await route.abort('failed').catch(() => {});
      } finally {clearTimeout(deliveryTimer); pendingRoute = null;}
    })();
    return routeWork;
  };
  try {
    await page.route(p.origin + '/authorization/v1/proof', handler); await page.goto(p.origin);
    await page.locator('#login').waitFor({state: 'visible'});
    const statusResponse = page.waitForResponse(response => response.url() === p.origin + '/authorization/v1/status' && response.request().method() === 'POST', {timeout: 10000}).catch(() => null);
    const selectionResponse = page.waitForResponse(response => response.url() === p.origin + '/receive/selection' && response.request().method() === 'GET', {timeout: 10000}).catch(() => null);
    await page.locator('#token').fill(p.env.WSTX_TOKEN); await page.locator('#login button').click();
    await connected(page); // Original browser readiness predicate must fail first on pre-client product source.
    if (routeWork) await routeWork;
    assert.equal(Boolean(forwarded), true, 'a real server proof reply was captured');
    assert.equal(jarAbsent, true, 'Node proof completion must not mutate the browser cookie jar');
    assert.equal(routeFailed, false); assert.equal(fulfilled, true);
    const actualStatus = await statusResponse; assert.ok(actualStatus, 'actual post-delivery status must be observed');
    const statusText = await actualStatus.text(), status = JSON.parse(statusText);
    const actualSelection = await selectionResponse; assert.ok(actualSelection, 'normal default DETAIL selection read observed');
    const cookies = (await context.cookies(p.origin)).filter(cookie => cookie.name === cookieName);
    const cookieMatches = cookies.length === 1 && cookies[0].value === forwarded.cookie; jarMatches = cookieMatches;
    const afterFiles = await fileHashes(), sameFiles = JSON.stringify(afterFiles) === JSON.stringify(forwarded.beforeFiles);
    const state = await page.evaluate(async () => {
      const db = await new Promise((resolve, reject) => {const request = indexedDB.open('wstx-authorization-v1', 1); request.onupgradeneeded = () => request.transaction.abort(); request.onerror = () => reject(new Error('Retained store missing')); request.onsuccess = () => resolve(request.result);});
      let credential;
      try {credential = await new Promise((resolve, reject) => {const request = db.transaction('credential').objectStore('credential').get('current'); request.onsuccess = () => resolve(request.result); request.onerror = () => reject(new Error('Retained store unavailable'));});} finally {db.close();}
      return {connection: connection.dataset.state, socketState: socket?.readyState, profile: profileData?.profile_id, boot: profileData?.boot_id,
        authorization: window.stationAuthorization.snapshot(), keyPresent: credential?.key instanceof CryptoKey, extractable: credential?.key?.extractable,
        usages: credential?.key?.usages, algorithm: credential?.key?.algorithm, pendingEnrollment: credential?.pending_enrollment,
        loginHidden: document.querySelector('#login').hidden, tokenEmpty: document.querySelector('#token').value === '', localKeys: Object.keys(localStorage), sessionKeys: Object.keys(sessionStorage)};
    });
    assert.equal(actualStatus.status(), 200); assert.equal(Buffer.byteLength(statusText) <= 1024, true);
    assert.deepEqual(Object.keys(status).sort(), ['commissioned', 'condition', 'error', 'receive_state', 'retry_after_ms', 'scope', 'version']);
    assert.equal(status.version, 1); assert.deepEqual(Object.keys(status.scope).sort(), ['profile_id', 'radio_id', 'safety_revision']);
    assert.equal(status.scope.profile_id, p.document.profile_id); assert.equal(status.scope.safety_revision, 1);
    assert.match(status.scope.radio_id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    assert.equal(status.condition, 'disabled'); assert.equal(status.commissioned, false); assert.equal(status.error, null); assert.equal(status.retry_after_ms, null);
    assert.deepEqual(status.receive_state, {audio: 'closed', decoder: null}); // Strict no-job observer prerequisite.
    const observerReply = await new Promise((resolve, reject) => {
      observer = new WebSocket(p.origin.replace('https:', 'wss:') + '/ws', 'wstx.v1', {origin: p.origin, rejectUnauthorized: false, headers: {Cookie: cookieName + '=' + forwarded.cookie}});
      observer.on('error', () => {});
      observer.once('error', () => {clearTimeout(openTimer); reject(new Error('Owned observer upgrade failed'));});
      observer.once('close', () => {clearTimeout(openTimer); reject(new Error('Owned observer closed before reply'));});
      observer.on('message', data => {let value; try {value = JSON.parse(String(data));} catch {value = {};}
        frames.push({bytes: Buffer.byteLength(data), type: value.type, id: value.id, heartbeat: value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).length === 2 && value.v === 1 && value.type === 'heartbeat'});});
      observer.once('open', () => {clearTimeout(openTimer); receive(observer, 2000).then(resolve, () => reject(new Error('Owned observer response failed'))); observer.send(JSON.stringify({v: 1, type: 'station.get', id: 7901}));});
      openTimer = setTimeout(() => {observer.terminate(); reject(new Error('Owned observer upgrade exceeded5s'));}, 5000);
    });
    const authResponses = timeline.filter(item => item.status !== undefined && (item.path === '/session' || item.path.startsWith('/authorization/v1/')));
    t.diagnostic(JSON.stringify({scope: 'real proof delivery baseline only; no reordering/loss claim', proofBytes: forwarded.proofBytes,
      absentBeforeDelivery: jarAbsent, cookieMatches, sameFiles, timeline, state, status, selectionStatus: actualSelection.status(), observerFrames: frames}));
    assert.equal(cookieMatches, true); assert.equal(cookies[0].httpOnly, true); assert.equal(cookies[0].secure, true); assert.equal(cookies[0].sameSite, 'Strict');
    assert.equal(sameFiles, true, 'proof/status do not rewrite the already-enrolled verifier or profile');
    assert.deepEqual(authResponses.map(item => item.status), [204, 200, 200, 200, 204, 200], 'exact6 shared admissions, including session');
    assert.equal(actualSelection.status(), 200); assert.equal(state.connection, 'connected'); assert.equal(state.socketState, 1);
    assert.equal(state.profile, p.document.profile_id); assert.deepEqual(state.authorization.scope, status.scope); assert.equal(state.authorization.ready, true);
    assert.equal(state.keyPresent, true); assert.equal(state.extractable, false); assert.deepEqual(state.usages, ['sign']);
    assert.equal(state.algorithm.name, 'ECDSA'); assert.equal(state.algorithm.namedCurve, 'P-256'); assert.equal(state.pendingEnrollment, false);
    assert.equal(state.loginHidden, true); assert.equal(state.tokenEmpty, true); assert.deepEqual(state.localKeys, []); assert.deepEqual(state.sessionKeys, []);
    assert.equal(observerReply.v, 1); assert.equal(observerReply.type, 'station.status'); assert.equal(observerReply.id, 7901);
    assert.equal(observerReply.data.radio, 'unconfigured'); assert.equal(typeof observerReply.data.version, 'string');
    assert.equal(frames.every(frame => frame.bytes <= 1024 && (frame.heartbeat || frame.type === 'station.status' && frame.id === 7901)), true);
  } finally {
    clearTimeout(deliveryTimer); clearTimeout(openTimer);
    if (pendingRoute) await pendingRoute.abort('failed').catch(() => {});
    if (routeWork) await routeWork;
    try {
      if (observer && observer.readyState !== WebSocket.CLOSED) await new Promise((resolve, reject) => {
        observer.once('close', () => {clearTimeout(closeTimer); resolve();});
        closeTimer = setTimeout(() => {observerForced = true; observer.terminate(); reject(new Error('Owned observer close exceeded5s'));}, 5000);
        observer.close();
      });
    } finally {clearTimeout(closeTimer); await context.close(); t.diagnostic(JSON.stringify({scope: 'owned delivery baseline cleanup', observerForced, proofObservation, routeFailed, fulfilled, jarAbsent, jarMatches, timeline, observerFrames: frames}));}
  }
});

// Proves CL-022-01/02/05: actual record corruption/erasure is distinct from server-grant revocation.
test('TC-022-006: actual browser reports corrupt and erased retained credentials', {timeout: 45000}, async t => {
  const {profiles} = await fixture(t, true); let completed = 0;
  for (const mode of [1, 2]) { // Corrupt present record FIRST; erased record second, in independent profile/process buckets.
    const p = profiles[mode - 1], context = await browser.newContext({ignoreHTTPSErrors: true});
    const cookieName = `wstx_session_${p.document.profile_id}`, assets = [], assetWork = [], setup = [];
    const report = {storage_mode: mode, stage: 0, qualified: false, assertions_passed: false, asset_error: false, assets,
      auth_requests: 0, protected_requests: 0, mutation_requests: 0, websocket_creates: 0, foreign_requests: 0};
    let oldPage, page, beforeFiles, cookie, metadataHash, observeNetwork = true;
    const hashes = async () => Object.fromEntries(await Promise.all(['profile.json', 'authorization.json'].map(async name => [name, crypto.createHash('sha256').update(await fs.readFile(path.join(p.dir, name))).digest('hex')])));
    const captureAssets = (target, generation) => target.on('response', response => {
      const url = new URL(response.url()), code = url.pathname === '/app.js' ? 1 : url.pathname === '/authorization.js' ? 2 : 0;
      if (url.origin !== p.origin || !code) return;
      assetWork.push((async () => {try {const body = await response.body(); if (assets.length >= 8 || body.length > 131072) {report.asset_error = true; return;} assets.push([generation, code, response.status(), crypto.createHash('sha256').update(body).digest('hex')]);} catch {report.asset_error = true;}})());
    });
    const profileControl = async () => {try {return (await request(p.origin, 'GET', undefined, {Cookie: cookieName + '=' + cookie})).status === 200;} catch {throw new Error('Independent retained-cookie control failed');}};
    try {
      oldPage = await context.newPage(); captureAssets(oldPage, 1);
      oldPage.on('response', response => {const u = new URL(response.url()); if (u.origin !== p.origin) return; const code = ({'/session': 1, '/authorization/v1/bootstrap-scope': 2, '/authorization/v1/enroll': 3, '/authorization/v1/challenge': 4, '/authorization/v1/proof': 5, '/authorization/v1/status': 6})[u.pathname]; if (code) setup.push([code, response.status()]);});
      await oldPage.goto(p.origin); await oldPage.locator('#login').waitFor({state: 'visible'});
      try {await oldPage.locator('#token').fill(p.env.WSTX_TOKEN); await oldPage.locator('#login button').click();} catch {throw new Error('Controlled bootstrap input failed');}
      await connected(oldPage); await Promise.all(assetWork);
      report.setup_six = JSON.stringify(setup) === JSON.stringify([[1, 204], [2, 200], [3, 200], [4, 200], [5, 204], [6, 200]]);
      report.setup_selection = await oldPage.evaluate(async () => (await window.stationAuthorization.fetch('/receive/selection')).status === 200);
      const selected = (await context.cookies(p.origin)).filter(value => value.name === cookieName);
      if (selected.length !== 1) throw new Error('Selected transport prerequisite failed');
      cookie = selected[0].value; report.cookie_flags = selected[0].httpOnly && selected[0].secure && selected[0].sameSite === 'Strict';
      beforeFiles = await hashes(); report.server_cookie_before = await profileControl(); report.stage = 1;
      const fault = await oldPage.evaluate(async mode => {
        const db = await new Promise((resolve, reject) => {const r = indexedDB.open('wstx-authorization-v1', 1); r.onupgradeneeded = () => r.transaction.abort(); r.onerror = () => reject(new Error('Controlled credential read failed')); r.onsuccess = () => resolve(r.result);});
        const read = () => new Promise((resolve, reject) => {const tx = db.transaction('credential', 'readonly'); let value; tx.objectStore('credential').get('current').onsuccess = e => {value = e.target.result;}; tx.oncomplete = () => resolve(value); tx.onabort = tx.onerror = () => reject(new Error('Controlled credential read failed'));});
        const keyValid = v => Boolean(v?.key instanceof CryptoKey && v.key.type === 'private' && !v.key.extractable && v.key.algorithm.name === 'ECDSA' && v.key.algorithm.namedCurve === 'P-256' && v.key.usages.join(',') === 'sign');
        const digest = async v => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify([v.origin, v.scope, v.grant_id, v.public_key, v.enrollment_id, v.pending_enrollment])))), b => b.toString(16).padStart(2, '0')).join('');
        try {
          const before = await read(); const initial = Boolean(before?.version === 1 && before.origin === location.origin && before.pending_enrollment === false && keyValid(before));
          if (!initial) throw new Error('Controlled credential prerequisite failed');
          const metadataHash = await digest(before);
          await new Promise((resolve, reject) => {const tx = db.transaction('credential', 'readwrite'), store = tx.objectStore('credential'); if (mode === 1) store.put({...before, version: 0}, 'current'); else store.delete('current'); tx.oncomplete = resolve; tx.onabort = tx.onerror = () => reject(new Error('Controlled credential fault failed'));});
          const after = await read();
          return {initial, committed: true, present: after !== undefined, actual_fault: mode === 1 ? after?.version === 0 && keyValid(after) && await digest(after) === metadataHash : after === undefined, metadata_hash: metadataHash};
        } finally {db.close();}
      }, mode);
      metadataHash = fault.metadata_hash;
      report.fault_committed = fault.initial && fault.committed && fault.actual_fault && fault.present === (mode === 1);
      await oldPage.close(); report.old_page_closed = oldPage.isClosed(); report.stage = 2;
      page = await context.newPage(); captureAssets(page, 2);
      page.on('websocket', () => {if (observeNetwork) report.websocket_creates++;});
      page.on('request', req => {if (!observeNetwork) return; const u = new URL(req.url()); if (u.origin !== p.origin) {report.foreign_requests++; return;} if (u.pathname === '/session' || u.pathname.startsWith('/authorization/v1/')) report.auth_requests++; if (u.pathname === '/profile' || u.pathname.startsWith('/receive/') || u.pathname.startsWith('/recordings')) report.protected_requests++; if (!['GET', 'HEAD'].includes(req.method())) report.mutation_requests++;});
      await page.addInitScript(mode => {
        const probe = window.__actualStorageFault = {mode, installed: false, observer_error: false, start: null, end: null, frozen: false,
          opens: 0, reads: 0, writes: 0, generates: 0, initial_classification_ms: null, ready_seen: false, connected_seen: false,
          invalid_prompt_seen: false, eligibility_changed_after_classification: false, token_input_seen: false, events: [], overflow: false, last: null, terminal: null};
        const observing = () => !probe.frozen && (probe.start === null || performance.now() <= probe.end);
        const sample = () => {
          if (!observing()) return;
          const auth = window.stationAuthorization?.snapshot(), connection = document.querySelector('#connection'), login = document.querySelector('#login'), token = document.querySelector('#token');
          const connected = connection?.dataset.state === 'connected', hidden = Boolean(login?.hidden), reason = Boolean(connection?.textContent.includes(mode === 1 ? 'Browser credential invalid' : 'Browser credential missing'));
          probe.ready_seen ||= Boolean(auth?.ready); probe.connected_seen ||= connected; probe.invalid_prompt_seen ||= mode === 1 && Boolean(login && !hidden); probe.token_input_seen ||= Boolean(token?.value);
          const now = performance.now(), classified = Boolean(auth?.state === 'unavailable' && !auth.ready && !connected && login && hidden === (mode === 1) && reason);
          if (probe.start !== null && classified && probe.initial_classification_ms === null) probe.initial_classification_ms = Math.max(0, now - probe.start);
          if (probe.initial_classification_ms !== null && login && hidden !== (mode === 1)) probe.eligibility_changed_after_classification = true;
          const state = ({unavailable: 1, recovering: 2, authorizing: 3, ready: 4})[auth?.state] || 0;
          const value = [probe.start === null ? -1 : Math.round(now - probe.start), state, Number.isSafeInteger(auth?.epoch) ? auth.epoch : -1, Boolean(auth?.ready), connected, hidden, reason];
          const last = probe.events.at(-1); if (!last || value.slice(1).some((v, i) => v !== last[i + 1])) {if (probe.events.length < 128) probe.events.push(value); else probe.overflow = true;}
          if (probe.start !== null) probe.terminal = {at_ms: now - probe.start, ready: Boolean(auth?.ready), connected, login_hidden: hidden, reason, state};
        };
        try {
          const open = IDBFactory.prototype.open; IDBFactory.prototype.open = function(...args) {if (observing() && args[0] === 'wstx-authorization-v1') probe.opens++; return Reflect.apply(open, this, args);};
          for (const method of ['get', 'add', 'put', 'delete', 'clear']) {const original = IDBObjectStore.prototype[method]; IDBObjectStore.prototype[method] = function(...args) {try {if (observing() && this.transaction.db.name === 'wstx-authorization-v1' && this.name === 'credential') {if (method === 'get' && args[0] === 'current') probe.reads++; else if (method !== 'get') probe.writes++;}} catch {probe.observer_error = true;} return Reflect.apply(original, this, args);};}
          const generate = SubtleCrypto.prototype.generateKey; SubtleCrypto.prototype.generateKey = function(...args) {if (observing()) probe.generates++; return Reflect.apply(generate, this, args);};
          probe.installed = true;
        } catch {probe.observer_error = true;}
        addEventListener('station-authorization', sample);
        addEventListener('DOMContentLoaded', () => {
          probe.start = performance.now(); probe.end = probe.start + 10000;
          for (const element of [document.querySelector('#connection'), document.querySelector('#login')]) if (element) new MutationObserver(sample).observe(element, {attributes: true, childList: true, subtree: true, characterData: true});
          sample();
          const timer = setInterval(() => {if (performance.now() > probe.end) {probe.frozen = true; probe.collected_at_ms = performance.now() - probe.start; clearInterval(timer);} else sample();}, 25);
        }, {once: true});
      }, mode);
      await page.goto(p.origin, {waitUntil: 'domcontentloaded'}); report.stage = 3;
      await page.waitForFunction(() => window.__actualStorageFault?.frozen === true, null, {timeout: 12000});
      const view = await page.evaluate(() => {const p = window.__actualStorageFault; return {installed: p.installed, observer_error: p.observer_error, frozen: p.frozen, start_valid: Number.isFinite(p.start) && p.end === p.start + 10000, collected_at_ms: p.collected_at_ms, opens: p.opens, reads: p.reads, writes: p.writes, generates: p.generates, initial_classification_ms: p.initial_classification_ms, ready_seen: p.ready_seen, connected_seen: p.connected_seen, invalid_prompt_seen: p.invalid_prompt_seen, eligibility_changed_after_classification: p.eligibility_changed_after_classification, token_input_seen: p.token_input_seen, events: p.events, overflow: p.overflow, terminal: p.terminal};});
      report.observation = view; observeNetwork = false; report.stage = 4; // Freeze counters before readonly record/server diagnostics; browser samples ended at the fixed deadline.
      report.record_preserved = await page.evaluate(async ({mode, expected}) => {
        const db = await new Promise((resolve, reject) => {const r = indexedDB.open('wstx-authorization-v1', 1); r.onupgradeneeded = () => r.transaction.abort(); r.onerror = () => reject(new Error('Final credential inspection failed')); r.onsuccess = () => resolve(r.result);});
        try {const value = await new Promise((resolve, reject) => {const tx = db.transaction('credential', 'readonly'); let v; tx.objectStore('credential').get('current').onsuccess = e => {v = e.target.result;}; tx.oncomplete = () => resolve(v); tx.onabort = tx.onerror = () => reject(new Error('Final credential inspection failed'));});
          if (mode === 2) return value === undefined;
          if (!value || value.version !== 0 || !(value.key instanceof CryptoKey) || value.key.type !== 'private' || value.key.extractable || value.key.algorithm.name !== 'ECDSA' || value.key.algorithm.namedCurve !== 'P-256' || value.key.usages.join(',') !== 'sign') return false;
          const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify([value.origin, value.scope, value.grant_id, value.public_key, value.enrollment_id, value.pending_enrollment])))), b => b.toString(16).padStart(2, '0')).join(''); return hash === expected;
        } finally {db.close();}
      }, {mode, expected: metadataHash});
      report.cookie_unchanged = (await context.cookies(p.origin)).some(value => value.name === cookieName && value.value === cookie);
      report.files_unchanged = JSON.stringify(await hashes()) === JSON.stringify(beforeFiles); report.server_cookie_after = await profileControl();
      await Promise.all(assetWork); report.assets_complete = [1, 2].every(generation => [1, 2].every(code => assets.filter(v => v[0] === generation && v[1] === code && v[2] === 200).length === 1));
      report.qualified = report.setup_six && report.setup_selection && report.cookie_flags && report.server_cookie_before && report.fault_committed && report.old_page_closed && view.installed && !view.observer_error && view.frozen && view.start_valid && view.collected_at_ms >= 10000 && view.terminal?.at_ms <= 10000 && view.opens >= 2 && view.reads >= 2 && !view.overflow && !report.asset_error && report.assets_complete;
      assert.equal(report.qualified, true, 'real storage fault and complete observation must qualify');
      assert.equal(report.cookie_unchanged, true, 'local credential failure does not silently replace its retained transport'); assert.equal(report.server_cookie_after, true, 'local credential failure does not revoke the retained server grant');
      assert.equal(view.terminal.login_hidden, mode === 1, 'present-invalid credentials cannot offer token replacement; missing credentials permit explicit authorization');
      assert.equal(view.initial_classification_ms !== null && view.initial_classification_ms <= 2000, true, 'fresh-document credential classification remains explicit within2s');
      assert.equal(view.terminal.reason && view.terminal.state !== 4, true); assert.equal(view.ready_seen || view.connected_seen, false); assert.equal(view.invalid_prompt_seen, false); assert.equal(view.eligibility_changed_after_classification, false); assert.equal(view.token_input_seen, false);
      assert.equal(report.auth_requests + report.protected_requests + report.mutation_requests + report.websocket_creates + report.foreign_requests, 0);
      assert.equal(view.writes + view.generates, 0); assert.equal(report.record_preserved, true); assert.equal(report.files_unchanged, true);
      report.assertions_passed = true; completed++;
    } finally {
      await Promise.all(assetWork); t.diagnostic(JSON.stringify(report)); await context.close();
    }
  }
  assert.equal(completed, 2); t.diagnostic(JSON.stringify({storage_modes_completed: completed}));
});
// Executes the actual authorization owner against independent platform boundaries; the browser cases separately prove real authority.
test('TC-022-006: authorization owner distinguishes credential lookup and retained failures', {timeout: 45000}, async t => {
  const vm = require('node:vm'), source = await fs.readFile(path.resolve('client/authorization.js'), 'utf8');
  const pair = await crypto.webcrypto.subtle.generateKey({name: 'ECDSA', namedCurve: 'P-256'}, false, ['sign', 'verify']);
  const origin = 'https://localhost:18443', scope = {profile_id: uuid(1), radio_id: uuid(2), safety_revision: 1};
  const credential = {version: 1, origin, key: pair.privateKey, public_key: Buffer.from(await crypto.webcrypto.subtle.exportKey('raw', pair.publicKey)).toString('base64url'),
    grant_id: Buffer.alloc(32, 7).toString('base64url'), enrollment_id: uuid(3), scope, pending_enrollment: false};
  const cases = [
    ['absent', 'credential-missing'], ['empty', 'credential-missing'], ['blocked-late-upgrade', 'credential-storage-unavailable'],
    ['blocked-late-success', 'credential-storage-unavailable'], ['error', 'credential-storage-unavailable'], ['open-throw', 'credential-storage-unavailable'], ['read-error', 'credential-storage-unavailable'], ['missing-store', 'credential-storage-unavailable'], ['old-version', 'credential-storage-unavailable'],
    ['invalid', 'credential-invalid'], ['network', 'retained-transient'], ['null-rejection', 'retained-transient'],
    ['rate', 'retained-transient'], ['persistence', 'retained-transient'], ['unauthorized', 'retained-rejected'],
    ['forbidden', 'retained-rejected'], ['identity', 'retained-rejected'], ['pending', 'enrollment-pending'], ['explicit', 'explicit-in-progress'],
    ['retry-success', null], ['retry-repeat401', 'retained-rejected'], ['retry-challenge401', 'retained-rejected'], ['retry-proof401', 'retained-rejected'],
    ['retry-lost204', 'retained-transient'], ['retry-proof200', 'retained-transient'], ['retry-second-proof200', 'retained-transient'],
    ['retry-status403', 'retained-rejected'], ['retry-status429', 'retained-transient'], ['retry-status503', 'retained-transient'],
    ['retry-status-scope', 'retained-rejected'], ['retry-second-challenge-scope', 'retained-rejected'], ['retry-second-status-scope', 'retained-rejected'],
    ['retry-pending', 'enrollment-pending'], ['retry-bootstrap', undefined], ['retry-aborted', 'retained-rejected'], ['retry-abort-challenge', 'retained-transient'], ['retry-stale', 'retained-transient']
  ];
  let checked = 0;
  for (const [fault, expected] of cases) {
    let opens = 0, aborts = 0, closes = 0, writes = 0, fetches = 0, finishBootstrap, bootstrap, challenges = 0, proofs = 0, statuses = 0, verified = 0, proofBodyReads = 0;
    let record = fault === 'empty' || fault === 'retry-bootstrap' ? undefined : fault === 'invalid' ? null : {...credential, pending_enrollment: fault === 'pending' || fault === 'retry-pending'};
    const calls = [], controllers = [], timeoutValues = [], proofNonces = new Set(); let activeNonce;
    const indexedDB = {open() {
      opens++; if (fault === 'open-throw') throw new DOMException('Injected storage failure', 'SecurityError'); const request = {}, db = {objectStoreNames: {contains: name => fault !== 'missing-store' && name === 'credential'}, close() {closes++;},
        createObjectStore() {writes++; throw new Error('Lookup must not create a store');},
        transaction() {const transaction = {objectStore: () => ({get() {const read = {}; queueMicrotask(() => {if (fault === 'read-error') {transaction.onerror(); return;} read.result = record; read.onsuccess(); transaction.oncomplete();}); return read;},
          add(value) {writes++; record = value; const write = {}; queueMicrotask(() => {write.result = value; write.onsuccess(); transaction.oncomplete();}); return write;},
          put(value) {writes++; record = value; const write = {}; queueMicrotask(() => {write.result = value; write.onsuccess(); transaction.oncomplete();}); return write;}})}; return transaction;}};
      request.result = db; request.transaction = {abort() {aborts++; queueMicrotask(() => request.onerror?.());}};
      queueMicrotask(() => {
        if (fault === 'absent' || fault === 'old-version') request.onupgradeneeded({oldVersion: fault === 'absent' ? 0 : 1});
        else if (fault === 'blocked-late-upgrade') {request.onblocked(); request.onupgradeneeded({oldVersion: 0});}
        else if (fault === 'blocked-late-success') {request.onblocked(); request.onsuccess();}
        else if (fault === 'error') request.onerror();
        else request.onsuccess();
      }); return request;
    }};
    const response = (status, value) => ({ok: status >= 200 && status < 300, status, text: async () => JSON.stringify(value)});
    const fetch = async (path, options) => {
      fetches++; calls.push({path, signal: options?.signal});
      if (path === '/session' && (fault === 'explicit' || fault === 'retry-stale')) return new Promise(resolve => {finishBootstrap = () => resolve({status: 401});});
      if (fault === 'network') throw new TypeError('Injected network failure');
      if (fault === 'null-rejection') throw null;
      const status = ({rate: 429, persistence: 503, unauthorized: 401, forbidden: 403, pending: 401})[fault];
      if (status) return {ok: false, status};
      if (fault === 'identity') return response(200, {version: 1, grant_id: Buffer.alloc(32, 8).toString('base64url'), public_key: credential.public_key, scope, nonce: Buffer.alloc(32, 9).toString('base64url'), lifetime_seconds: 60});
      if (!fault.startsWith('retry-')) throw new Error('Unexpected network boundary');
      const body = path === '/session' ? null : JSON.parse(options.body);
      if (path === '/session') return response(204);
      if (path.endsWith('/bootstrap-scope')) return response(200, {version: 1, current_scope: scope});
      if (path.endsWith('/enroll')) return response(200, {version: 1, operation_id: body.operation_id, grant_id: body.grant_id, outcome: 'committed', scope});
      if (path.endsWith('/challenge')) {
        challenges++;
        if (fault === 'retry-challenge401') return response(401);
        activeNonce = Buffer.alloc(32, challenges + 9).toString('base64url');
        if (fault === 'retry-abort-challenge' && challenges === 2) controllers[0].abort();
        return response(200, {version: 1, grant_id: record.grant_id, public_key: record.public_key,
          scope: fault === 'retry-second-challenge-scope' && challenges === 2 ? {...scope, radio_id: uuid(99)} : scope, nonce: activeNonce, lifetime_seconds: 60});
      }
      if (path.endsWith('/proof') || path.endsWith('/receipt')) {
        const receipt = path.endsWith('/receipt'); if (!receipt) proofs++;
        assert.equal(body.nonce === activeNonce, true, 'each proof uses its actual fresh challenge');
        assert.equal(proofNonces.has(body.nonce), false, 'an already consumed proof nonce is not replayed'); proofNonces.add(body.nonce);
        // Independent canonical signing oracle: domain/version, U32BE-length-prefixed fields, raw nonce.
        const fields = [origin, scope.profile_id, scope.radio_id, String(scope.safety_revision), record.grant_id]; if (receipt) fields.push(record.enrollment_id);
        const parts = [Buffer.from(receipt ? 'WSTX-AUTH-RECEIPT' : 'WSTX-AUTH-PROOF'), Buffer.from([1])];
        for (const field of [...fields.map(value => Buffer.from(value)), Buffer.from(body.nonce, 'base64url')]) {const length = Buffer.alloc(4); length.writeUInt32BE(field.length); parts.push(length, field);}
        const publicKey = await crypto.webcrypto.subtle.importKey('raw', Buffer.from(record.public_key, 'base64url'), {name: 'ECDSA', namedCurve: 'P-256'}, false, ['verify']);
        assert.equal(await crypto.webcrypto.subtle.verify({name: 'ECDSA', hash: 'SHA-256'}, publicKey, Buffer.from(body.signature, 'base64url'), Buffer.concat(parts)), true, 'proof signs the independent canonical identity/nonce payload');
        if (!receipt) verified++;
        if (receipt) return response(200, {version: 1, operation_id: record.enrollment_id, grant_id: record.grant_id, outcome: 'committed', scope});
        if (fault === 'retry-lost204') throw new TypeError('Injected unacknowledged proof response');
        if (fault === 'retry-proof401') return response(401);
        if (fault === 'retry-proof200' || fault === 'retry-second-proof200' && proofs === 2) return {ok: true, status: 200, text: async () => {proofBodyReads++; return 'null';}};
        return response(204);
      }
      if (path.endsWith('/status')) {
        statuses++;
        if (fault === 'retry-status-scope' || fault === 'retry-second-status-scope' && statuses === 2) return response(200, {version: 1, scope: {...scope, radio_id: uuid(99)}});
        if (statuses === 1) {
          if (fault === 'retry-aborted') controllers[0].abort();
          return response(({ 'retry-status403': 403, 'retry-status429': 429, 'retry-status503': 503 })[fault] || 401);
        }
        return response(fault === 'retry-repeat401' ? 401 : 200, {version: 1, scope});
      }
      throw new Error('Unexpected retry boundary');
    };
    const window = {dispatchEvent(event) {if (fault === 'retry-stale' && event.detail.state === 'recovering' && !bootstrap) bootstrap = window.stationAuthorization.bootstrap('fixture-bootstrap-input').then(() => false, () => true);}};
    const deadlineSource = {timeout(milliseconds) {timeoutValues.push(milliseconds); const controller = new AbortController(); controllers.push(controller); return controller.signal;}};
    const realm = vm.createContext({window, location: {origin}, indexedDB, fetch, TextEncoder, Uint8Array,
      CryptoKey: pair.privateKey.constructor, crypto: crypto.webcrypto, atob, btoa, AbortSignal: deadlineSource, CustomEvent: class {constructor(type, init) {this.type = type; this.detail = init.detail;}}});
    vm.runInContext(source, realm, {timeout: 1000});
    if (fault === 'explicit') bootstrap = window.stationAuthorization.bootstrap('fixture-bootstrap-input').then(() => false, () => true);
    let timer, failure;
    try {failure = await Promise.race([(fault === 'retry-bootstrap' ? window.stationAuthorization.bootstrap('fixture-bootstrap-input') : window.stationAuthorization.ensureReady()).then(() => null, error => ({condition: error.authorizationCondition, status: error.status})),
      new Promise((_, reject) => {timer = setTimeout(() => reject(new Error('Owner boundary did not settle')), 1000);})]);}
    finally {clearTimeout(timer); if (finishBootstrap) finishBootstrap(); if (bootstrap) await bootstrap;}
    assert.equal(failure?.condition ?? null, expected ?? null, 'actual owner classifies the independently injected boundary');
    assert.equal(window.stationAuthorization.snapshot().ready, fault === 'retry-success'); assert.equal(writes, fault === 'retry-pending' ? 1 : fault === 'retry-bootstrap' ? 2 : 0);
    if (fault === 'absent' || fault === 'old-version' || fault === 'blocked-late-upgrade') assert.equal(aborts, 1);
    if (fault === 'blocked-late-success') assert.equal(closes, 1, 'settled failure closes a later delivered DB handle');
    if (['absent', 'empty', 'blocked-late-upgrade', 'blocked-late-success', 'error', 'open-throw', 'read-error', 'missing-store', 'old-version', 'invalid'].includes(fault)) assert.equal(fetches, 0);
    if (fault === 'rate' || fault === 'retry-status429') assert.equal(failure.status, 429); if (fault === 'persistence' || fault === 'retry-status503') assert.equal(failure.status, 503);
    if (fault.startsWith('retry-')) {
      const counts = {'retry-success': 6, 'retry-repeat401': 6, 'retry-challenge401': 1, 'retry-proof401': 2, 'retry-lost204': 2, 'retry-proof200': 2, 'retry-second-proof200': 5,
        'retry-status403': 3, 'retry-status429': 3, 'retry-status503': 3, 'retry-status-scope': 3, 'retry-second-challenge-scope': 4, 'retry-second-status-scope': 6,
        'retry-pending': 5, 'retry-bootstrap': 6, 'retry-aborted': 3, 'retry-abort-challenge': 4, 'retry-stale': 1};
      assert.equal(fetches, counts[fault], 'retry bounds match the independent call-count oracle'); assert.equal(verified, proofs); assert.equal(proofBodyReads, 0);
      assert.equal(timeoutValues.every(value => value === 10000), true);
      assert.equal(timeoutValues.length, ['retry-bootstrap', 'retry-stale'].includes(fault) ? 2 : 1, 'retry never creates a replacement deadline');
      if (!['retry-bootstrap', 'retry-stale'].includes(fault)) assert.equal(calls.every(call => call.signal === controllers[0].signal), true, 'all triplets retain the original signal object');
      if (fault === 'retry-success' || fault === 'retry-repeat401') assert.equal(challenges, 2);
    }
    if (fault !== 'explicit' && !['retry-success', 'retry-bootstrap', 'retry-stale'].includes(fault)) {
      const priorOpens = opens, priorFetches = fetches;
      const retry = await window.stationAuthorization.ensureReady().then(() => null, error => ({condition: error.authorizationCondition, status: error.status}));
      assert.equal(retry?.condition, expected, 'backoff preserves the owner failure classification'); assert.equal(opens, priorOpens); assert.equal(fetches, priorFetches);
    }
    checked++;
  }
  t.diagnostic(JSON.stringify({owner_boundary_cases: checked, expected_cases: 37}));
});

// Proves CL-022-01/02/05: real overlapping proof delivery must not create a false-ready UI or replay Save.
for (const deliveryMode of ['reverse', 'lost']) test(`TC-022-006: two tabs recover after ${deliveryMode} proof delivery`, {timeout: 45000}, async t => {
  const {profiles, apps} = await fixture(t, true), p = profiles[0], context = await browser.newContext({ignoreHTTPSErrors: true});
  const held = {}, firstSeen = {}, firstHandled = {}, captured = {}, ended = {}, wire = [], inFlightProofs = new Set(), requestInfo = new WeakMap();
  const statusReplies = {A: [], B: []}, pages = {}, truth = [], frames = [], counts = {A: 0, B: 0}, testProbe = {}, protectedReads = [], expectedObserverIds = new Set(), seenObserverIds = new Set();
  // Safe timeline tuples: wall time, kind, document(1/2)/observer(3), path/id, status/count, Boolean, request id.
  // Kinds: request/response/finish/fail=1..4, actual forwarded proof=5, watchdog=6, UI truth=7/8, socket create/close/error=9..11, action=12, terminal probe=13.
  const timeline = []; let timelineOverflow = false, liveSockets = 0, socketSerial = 0, maxSockets = 0, requestSerial = 0;
  const event = (kind, label, code = 0, status = 0, ok = false, requestId = 0) => {if (timeline.length < 512) timeline.push([Date.now(), kind, label === 'A' ? 1 : label === 'B' ? 2 : 3, code, status, Boolean(ok), requestId]); else timelineOverflow = true;};
  const cookieName = `wstx_session_${p.document.profile_id}`, pendingTimers = new Set();
  let phase = 0, armed = false, t0 = -1, deadline = -1, deadlineWall = -1, zeroAtT0 = false, taggedAt = -1, observer, observerForced = false, originalFrozen = false;
  const metrics = {mode: deliveryMode === 'reverse' ? 1 : 2, qualified: false, recovered: false, route_error: false, a_pending_before_action: false, save_clicked: false, save_blocked: false, observer_before: false, observer_after: false, observer_final: false};
  const authCode = path => ({'/session': 1, '/authorization/v1/bootstrap-scope': 2, '/authorization/v1/enroll': 3, '/authorization/v1/challenge': 4, '/authorization/v1/proof': 5, '/authorization/v1/status': 6}[path] || 0);
  const hashes = async () => Object.fromEntries(await Promise.all(['profile.json', 'authorization.json'].map(async name => [name, crypto.createHash('sha256').update(await fs.readFile(path.join(p.dir, name))).digest('hex')])));
  const identity = app => JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-Command', `Get-CimInstance Win32_Process -Filter 'ProcessId=${app.child.pid}' | Select-Object ProcessId,CreationDate | ConvertTo-Json -Compress`], {encoding: 'utf8', windowsHide: true, timeout: 5000}).trim());
  async function keyMetadata(page) {
    return page.evaluate(async () => {
      const db = await new Promise((resolve, reject) => {const r = indexedDB.open('wstx-authorization-v1', 1); r.onupgradeneeded = () => r.transaction.abort(); r.onerror = () => reject(new Error('Retained credential unavailable')); r.onsuccess = () => resolve(r.result);});
      try {return await new Promise((resolve, reject) => {const r = db.transaction('credential').objectStore('credential').get('current'); r.onerror = () => reject(new Error('Retained credential unavailable')); r.onsuccess = () => {const v = r.result; resolve({grant: v?.grant_id, public: v?.public_key, scope: v?.scope, extractable: v?.key?.extractable, usages: v?.key?.usages});};});} finally {db.close();}
    });
  }
  const publicStatusValid = (value, scope) => Boolean(value && Object.keys(value).sort().join(',') === 'commissioned,condition,error,receive_state,retry_after_ms,scope,version' && value.version === 1 && value.scope && Object.keys(value.scope).sort().join(',') === 'profile_id,radio_id,safety_revision' && value.scope.profile_id === scope.profile_id && value.scope.radio_id === scope.radio_id && value.scope.safety_revision === scope.safety_revision && value.condition === 'disabled' && value.commissioned === false && value.error === null && value.retry_after_ms === null && value.receive_state && Object.keys(value.receive_state).sort().join(',') === 'audio,decoder' && value.receive_state.audio === 'closed' && value.receive_state.decoder === null);
  function watchTruth(page, at) {
    const label = page === pages.A ? 'A' : 'B'; event(7, label, 0, 0, false);
    const record = {at, done: false, ok: false}; truth.push(record);
    page.waitForFunction(() => !window.stationAuthorization.snapshot().ready && document.querySelector('#connection').dataset.state !== 'connected', null, {timeout: 2000}).then(() => {record.done = true; record.ok = performance.now() - at <= 2000; event(8, label, Math.round(performance.now() - at), 0, record.ok);}, () => {record.done = true; event(8, label, Math.round(performance.now() - at), 0, false);});
  }
  async function instrument(page, label, retained) {
    pages[label] = page; captured[label] = {}; captured[label].promise = new Promise(resolve => {captured[label].resolve = resolve;}); ended[label] = {}; ended[label].promise = new Promise(resolve => {ended[label].resolve = resolve;});
    await page.addInitScript(known => {
      window.__cookieFault = {retained: known, prompt: false, tokenSubmits: 0, submits: [], events: [], overflow: false, windowEnd: 0, terminal: null};
      const sample = () => {
        const f = window.__cookieFault, now = Date.now(), auth = window.stationAuthorization?.snapshot(), login = document.querySelector('#login'), connection = document.querySelector('#connection');
        const prompt = Boolean(f.retained && login && !login.hidden); if (prompt && (!f.windowEnd || now <= f.windowEnd)) f.prompt = true;
        const value = [now, Number.isSafeInteger(auth?.epoch) ? auth.epoch : -1, ({unavailable: 1, recovering: 2, authorizing: 3, ready: 4})[auth?.state] || 0, Boolean(auth?.ready), prompt, ({connected: 1, connecting: 2, disconnected: 3})[connection?.dataset.state] || 0];
        const last = f.events.at(-1); if (!last || value.slice(1).some((v, i) => v !== last[i + 1])) {if (f.events.length < 256) f.events.push(value); else f.overflow = true;}
        if (f.windowEnd && now <= f.windowEnd) f.terminal = {at: now, ready: Boolean(auth?.ready && connection?.dataset.state === 'connected' && typeof socket !== 'undefined' && socket?.readyState === WebSocket.OPEN), boot: typeof profileData !== 'undefined' ? profileData?.boot_id : null};
      };
      addEventListener('station-authorization', sample);
      addEventListener('DOMContentLoaded', () => {for (const node of [document.querySelector('#login'), document.querySelector('#connection')]) if (node) new MutationObserver(sample).observe(node, {attributes: true}); sample(); setInterval(sample, 25);});
      addEventListener('submit', event => {if (event.target.id === 'login' && (!window.__cookieFault.windowEnd || Date.now() <= window.__cookieFault.windowEnd)) window.__cookieFault.tokenSubmits++; if (event.target.id === 'settings') window.__cookieFault.submits.push({trusted: event.isTrusted, ready: window.stationAuthorization.snapshot().ready, loaded: Boolean(profileData), at: performance.now()});}, true);
    }, retained);
    page.on('websocket', ws => {const id = ++socketSerial; liveSockets++; maxSockets = Math.max(maxSockets, liveSockets); event(9, label, id, liveSockets, true); ws.on('close', () => {liveSockets--; event(10, label, id, liveSockets, true);}); ws.on('socketerror', () => event(11, label, id, liveSockets, false));});
    page.on('request', request => {
      const url = new URL(request.url()); if (url.origin !== p.origin) return;
      const code = authCode(url.pathname), controlled = armed && code === 5 && !firstSeen[label];
      if (controlled) firstSeen[label] = request;
      const requestId = ++requestSerial; requestInfo.set(request, {requestId, label, phase, code, controlled, path: url.pathname, testProbe: Boolean(testProbe[label] && code === 6)});
      event(1, label, code || (url.pathname === '/profile' ? 7 : url.pathname === '/receive/selection' ? 8 : 99), phase, controlled, requestId);
      if (label === 'A' && code === 6 && held.A?.intentional && held.A.actualStatus === 204 && !held.A.firstStatus) held.A.firstStatus = request;
      if (code === 5) inFlightProofs.add(request);
      if (request.method() === 'PUT' && url.pathname === '/profile' && (deadline < 0 || performance.now() <= deadline)) counts[label]++;
    });
    page.on('response', response => {
      const request = response.request(), info = requestInfo.get(request); if (!info) return;
      const at = performance.now(), status = response.status(); event(2, label, info.code || (info.path === '/profile' ? 7 : info.path === '/receive/selection' ? 8 : 99), status, info.controlled, info.requestId);
      if (label === 'A' && held.A?.firstStatus === request) held.A.firstStatus401 = status === 401;
      if (info.code && !info.controlled) wire.push({label, phase: info.phase, code: info.code, status, at});
      if (info.code === 6) statusReplies[label].push({response, at, status});
      if (info.phase === 2 && !info.code && (info.path === '/profile' || info.path.startsWith('/receive/') || info.path.startsWith('/recordings'))) protectedReads.push({label, code: info.path === '/profile' ? 7 : info.path === '/receive/selection' ? 8 : 99, status, at});
      if (info.phase === 2 && status === 401 && !info.testProbe) watchTruth(page, at);
      if (info.controlled && held[label]?.request === request) held[label].actualStatus = status;
    });
    const finish = (request, failed) => {
      const info = requestInfo.get(request); if (info) event(failed ? 4 : 3, label, info.code, info.phase, info.controlled, info.requestId);
      inFlightProofs.delete(request);
      const h = held[label]; if (h?.request !== request) return;
      h.endedAt = performance.now(); h.failed = failed; h.expectedAbort = failed && request.failure()?.errorText === 'net::ERR_FAILED'; clearTimeout(h.timer); ended[label].resolve();
      if (label === 'A' && failed && taggedAt >= 0 && h.intentional && !h.expired) watchTruth(page, h.endedAt);
      if (taggedAt >= 0 && t0 < 0 && held.A?.endedAt >= 0 && held.B?.endedAt >= 0) {t0 = Math.max(held.A.endedAt, held.B.endedAt); deadline = t0 + 10000; deadlineWall = Date.now() + 10000; zeroAtT0 = inFlightProofs.size === 0;}
    };
    page.on('requestfinished', request => finish(request, false)); page.on('requestfailed', request => finish(request, true));
  }
  async function intercept(page, label) {
    await page.route(p.origin + '/authorization/v1/proof', async route => {
      if (firstHandled[label]) {try {await route.continue();} catch {metrics.route_error = true;} return;}
      firstHandled[label] = true;
      const request = route.request(), headers = await request.allHeaders(), body = request.postDataBuffer();
      const h = {route, request, headers, body, endedAt: -1, failed: false, expired: false, intentional: false, reply: null}; held[label] = h;
      h.pending = new Promise(resolve => {h.release = resolve;}); captured[label].resolve();
      await h.pending;
    });
  }
  async function forward(label) {
    const h = held[label];
    if (!h || firstSeen[label] !== h.request || h.endedAt >= 0 || h.request.method() !== 'POST' || h.request.url() !== p.origin + '/authorization/v1/proof' || h.headers.origin !== p.origin || h.headers['content-type'] !== 'application/json' || !Buffer.isBuffer(h.body) || !h.body.length || h.body.length > 1024) throw new Error('Original pending proof prerequisite failed');
    h.reply = await request(p.origin, 'POST', h.body, {Origin: h.headers.origin, 'Content-Type': h.headers['content-type'], ...(h.headers.cookie ? {Cookie: h.headers.cookie} : {})}, '/authorization/v1/proof');
    wire.push({label, phase: 2, code: 5, status: h.reply.status, at: performance.now()}); event(5, label, 5, h.reply.status, true, requestInfo.get(h.request).requestId);
    const values = h.reply.headers['set-cookie'], prefix = cookieName + '=';
    if (h.endedAt >= 0 || h.reply.status !== 204 || h.reply.bodyBytes !== 0 || !Array.isArray(values) || values.length !== 1 || !values[0].split(';')[0].startsWith(prefix) || !/^[A-Za-z0-9_-]{43}$/.test(values[0].split(';')[0].slice(prefix.length))) throw new Error('Actual proof reply prerequisite failed');
    h.cookie = values[0].split(';')[0].slice(prefix.length); h.cookieHeader = values[0];
    h.timer = setTimeout(() => {if (h.endedAt < 0) {h.expired = true; event(6, label, 5, 0, false); h.route.abort('failed').catch(() => {});}}, 5000); pendingTimers.add(h.timer);
  }
  async function deliver(label) {
    const h = held[label]; try {await h.route.fulfill({status: h.reply.status, body: '', headers: {'set-cookie': h.cookieHeader, ...(h.reply.headers['cache-control'] ? {'cache-control': h.reply.headers['cache-control']} : {})}});} catch {throw new Error('Controlled delivery failed');} h.release();
  }
  async function probe(id) {
    if (observer.readyState !== WebSocket.OPEN) return false;
    const response = receive(observer, 2000); expectedObserverIds.add(id); observer.send(JSON.stringify({v: 1, type: 'station.get', id}));
    const value = await response;
    return Boolean(value?.v === 1 && value.type === 'station.status' && value.id === id && value.data?.radio === 'unconfigured' && typeof value.data?.version === 'string' && frames.every(frame => frame.bytes <= 1024 && (frame.heartbeat || frame.expected)));
  }
  let seedMetadata, beforeFiles, oldServer, newServer, oldBoot, currentBoot, transitionReplies = 0;
  try {
    const a = await context.newPage(); await instrument(a, 'A', false); await a.goto(p.origin); await a.locator('#login').waitFor({state: 'visible'});
    try {await a.locator('#token').fill(p.env.WSTX_TOKEN); await a.locator('#login button').click();} catch {throw new Error('Fixture bootstrap input failed');}
    await connected(a); // Meaningful pre-client RED remains the original browser readiness predicate.
    const seedSelection = await a.evaluate(async () => {const r = await window.stationAuthorization.fetch('/receive/selection'); return r.status;});
    if (seedSelection !== 200) throw new Error('Default selection read prerequisite failed');
    metrics.seed_auth_count = wire.filter(value => value.phase === 0).length;
    if (metrics.seed_auth_count !== 6 || wire.some(value => value.phase === 0 && ![200, 204].includes(value.status))) throw new Error('Exact seed admission prerequisite failed');
    oldBoot = await a.locator('#profile-boot').textContent();
    seedMetadata = await keyMetadata(a); beforeFiles = await hashes(); oldServer = identity(p.app);
    await a.locator('#display-name').fill('Retained unsent Save');
    await a.evaluate(() => {window.__cookieFault.tokenSubmits = 0; window.__cookieFault.retained = true; window.__cookieFault.prompt = !document.querySelector('#login').hidden;});
    armed = true; await intercept(a, 'A'); phase = 1;
    await p.app.close(); assert.notEqual(p.app.child.exitCode ?? p.app.child.signalCode, null);
    await context.clearCookies({name: cookieName});
    const restarted = await start(p, p.env); apps.push(restarted); p.app = restarted; newServer = identity(restarted); phase = 2;
    metrics.new_process = oldServer.ProcessId !== newServer.ProcessId || oldServer.CreationDate !== newServer.CreationDate;
    const b = await context.newPage(); await instrument(b, 'B', true); await intercept(b, 'B'); await b.goto(p.origin);
    let captureTimer;
    try {await Promise.race([Promise.all([captured.A.promise, captured.B.promise]), new Promise((_, reject) => {captureTimer = setTimeout(() => reject(new Error('Original proof overlap prerequisite failed')), 5000);})]);} finally {clearTimeout(captureTimer);}
    await forward('A'); await forward('B');
    metrics.jar_untouched_after_node = (await context.cookies(p.origin)).every(cookie => cookie.name !== cookieName);
    const oldHandle = await request(p.origin, 'GET', undefined, {Cookie: cookieName + '=' + held.A.cookie});
    const currentHandle = await request(p.origin, 'GET', undefined, {Cookie: cookieName + '=' + held.B.cookie});
    metrics.old_handle_401 = oldHandle.status === 401; metrics.current_handle_200 = currentHandle.status === 200;
    await deliver('B'); await ended.B.promise; await connected(b);
    const bStatus = statusReplies.B.find(value => value.status === 200); if (!bStatus) throw new Error('Actual B status prerequisite missing');
    let bValue; try {bValue = JSON.parse(await bStatus.response.text());} catch {throw new Error('Actual B status invalid');} if (!publicStatusValid(bValue, seedMetadata.scope)) throw new Error('No-job observer prerequisite failed');
    currentBoot = await b.locator('#profile-boot').textContent(); metrics.new_boot = Boolean(currentBoot && currentBoot !== oldBoot);
    metrics.jar_b_after_delivery = (await context.cookies(p.origin)).some(cookie => cookie.name === cookieName && cookie.value === held.B.cookie);
    await new Promise((resolve, reject) => {
      observer = new WebSocket(p.origin.replace('https:', 'wss:') + '/ws', 'wstx.v1', {origin: p.origin, rejectUnauthorized: false, headers: {Cookie: cookieName + '=' + held.B.cookie}});
      observer.on('error', () => {}); let timer = setTimeout(() => {observer.terminate(); reject(new Error('Observer upgrade exceeded5s'));}, 5000); pendingTimers.add(timer);
      observer.once('error', () => {clearTimeout(timer); reject(new Error('Observer upgrade failed'));});
      observer.on('message', data => {let v; try {v = JSON.parse(String(data));} catch {v = {};}
        const expected = v.v === 1 && v.type === 'station.status' && expectedObserverIds.has(v.id) && !seenObserverIds.has(v.id);
        if (expected) seenObserverIds.add(v.id);
        frames.push({bytes: Buffer.byteLength(data), expected, heartbeat: v && typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 2 && v.v === 1 && v.type === 'heartbeat'});});
      observer.once('open', () => {liveSockets++; maxSockets = Math.max(maxSockets, liveSockets); event(9, 'N', 0, liveSockets, true); observer.once('close', () => {liveSockets--; event(10, 'N', 0, liveSockets, true);}); clearTimeout(timer); expectedObserverIds.add(8101); receive(observer, 2000).then(value => {metrics.observer_before = value?.v === 1 && value.type === 'station.status' && value.id === 8101 && value.data?.radio === 'unconfigured' && typeof value.data?.version === 'string'; resolve();}, () => reject(new Error('Observer first response failed'))); observer.send(JSON.stringify({v: 1, type: 'station.get', id: 8101}));});
    });
    const actionable = await a.locator('#settings-save').isVisible() && await a.locator('#settings-save').isEnabled();
    if (!actionable || await a.evaluate(() => window.stationAuthorization.snapshot().ready || !profileData)) throw new Error('Loaded recovering Save prerequisite failed');
    try {await a.locator('#settings-save').click({timeout: 1000}); metrics.save_clicked = true;} catch {throw new Error('Recovering Save click prerequisite failed');}
    const submit = await a.evaluate(() => window.__cookieFault.submits.at(-1));
    metrics.save_blocked = Boolean(submit && submit.trusted && !submit.ready && submit.loaded && counts.A === 0);
    metrics.a_pending_before_action = held.A.endedAt < 0 && firstSeen.A === held.A.request;
    if (!metrics.a_pending_before_action || !metrics.save_blocked) throw new Error('Original pending proof or Save qualification failed');
    metrics.a_prompt_before_fault = await a.evaluate(() => window.__cookieFault.prompt); metrics.b_prompt_before_fault = await b.evaluate(() => window.__cookieFault.prompt);
    metrics.a_pending_before_action = held.A.endedAt < 0 && !held.A.expired && firstSeen.A === held.A.request;
    if (!metrics.a_pending_before_action) throw new Error('Held proof expired before deliberate action');
    taggedAt = performance.now(); held.A.intentional = true; event(12, 'A', deliveryMode === 'reverse' ? 1 : 2, 0, true);
    if (deliveryMode === 'reverse') {await deliver('A'); metrics.jar_a_after_delivery = (await context.cookies(p.origin)).some(cookie => cookie.name === cookieName && cookie.value === held.A.cookie);}
    else {try {await held.A.route.abort('failed');} catch {throw new Error('Controlled loss failed');} held.A.release();}
    await ended.A.promise;
    metrics.zero_proofs_at_fixed_t0 = zeroAtT0; metrics.action_tag_before_end = held.A.endedAt >= taggedAt;
    metrics.controlled_action_expected = deliveryMode === 'reverse' ? !held.A.failed && held.A.actualStatus === 204 : held.A.failed && held.A.expectedAbort && held.A.endedAt >= taggedAt;
    metrics.qualified = held.A.intentional && !held.A.expired && !held.B.expired && metrics.new_boot && !held.B.failed && held.B.actualStatus === 204 && metrics.new_process && metrics.jar_untouched_after_node && metrics.old_handle_401 && metrics.current_handle_200 && metrics.jar_b_after_delivery && metrics.observer_before && metrics.save_blocked && metrics.a_pending_before_action && metrics.controlled_action_expected && zeroAtT0 && t0 >= taggedAt;
    if (!metrics.qualified) throw new Error('Controlled response completion qualification failed');
    await Promise.all([a, b].map(page => page.evaluate(end => {window.__cookieFault.windowEnd = end;}, deadlineWall)));
    try {metrics.observer_after = await probe(8102);} catch {metrics.observer_after = false;} // t0/deadline were already frozen in the completion event, before this await.
    let bothReady = false;
    try {await Promise.all([a, b].map(page => page.waitForFunction(boot => window.stationAuthorization.snapshot().ready && document.querySelector('#connection').dataset.state === 'connected' && socket?.readyState === WebSocket.OPEN && profileData?.boot_id === boot, currentBoot, {timeout: Math.max(1, deadline - performance.now())}))); bothReady = true;} catch {}
    const freshProof = wire.some(value => value.phase === 2 && value.code === 5 && value.status === 204 && value.at > t0);
    let statusesValid = true;
    for (const [label, page] of [['A', a], ['B', b]]) {
      const reply = statusReplies[label].find(value => value.status === 200 && value.at > t0);
      if (reply) {try {statusesValid &&= publicStatusValid(JSON.parse(await reply.response.text()), seedMetadata.scope);} catch {statusesValid = false;}}
      else if (bothReady && performance.now() < deadline) {
        let result; testProbe[label] = true;
        try {result = await page.evaluate(async remaining => {try {const r = await fetch('/authorization/v1/status', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({version: 1}), signal: AbortSignal.timeout(Math.max(1, remaining))}); const text = await r.text(); return {status: r.status, bytes: new TextEncoder().encode(text).length, value: JSON.parse(text)};} catch {return null;}}, Math.max(1, Math.floor(deadline - performance.now())));} finally {testProbe[label] = false;}
        statusesValid &&= Boolean(result && result.status === 200 && result.bytes <= 1024 && publicStatusValid(result.value, seedMetadata.scope));
      } else statusesValid = false;
    }
    metrics.early_recovery_ms = performance.now() - t0;
    const inWindowReady = bothReady && freshProof && statusesValid && inFlightProofs.size === 0 && performance.now() <= deadline;
    await new Promise(resolve => setTimeout(resolve, Math.max(0, deadline - performance.now()))); // Observe the SAME original window; never reset retry/admission/deadline.
    const terminalProofs = inFlightProofs.size;
    const terminal = await Promise.all([a, b].map(page => page.evaluate(() => window.__cookieFault.terminal)));
    metrics.recovery_elapsed_ms = performance.now() - t0; metrics.recovered = inWindowReady && terminalProofs === 0 && terminal.every(value => value?.ready && value.boot === currentBoot && value.at <= deadlineWall);
    metrics.terminal_proofs = terminalProofs; metrics.terminal_ready_count = terminal.filter(value => value?.ready && value.boot === currentBoot).length;
    originalFrozen = true; // A later probe/diagnostic can never turn this original fixed-window result into PASS.
    try {metrics.observer_final = await probe(8103);} catch {metrics.observer_final = false;} // Diagnostic on BOTH frozen outcomes; cannot heal recovery.
    event(13, 'N', 8103, 0, metrics.observer_final);
    const [aView, bView] = await Promise.all([a, b].map(page => page.evaluate(() => ({events: window.__cookieFault.events, overflow: window.__cookieFault.overflow, prompt: window.__cookieFault.prompt, ready: window.stationAuthorization.snapshot().ready, submitCount: window.__cookieFault.submits.length, tokenSubmits: window.__cookieFault.tokenSubmits, dirty: document.querySelector('#display-name').value === 'Retained unsent Save', saved: document.querySelector('#settings-result').textContent.startsWith('Saved revision')}))));
    const sameKeys = JSON.stringify(await keyMetadata(a)) === JSON.stringify(seedMetadata) && JSON.stringify(await keyMetadata(b)) === JSON.stringify(seedMetadata);
    const sameFiles = JSON.stringify(await hashes()) === JSON.stringify(beforeFiles);
    transitionReplies = wire.filter(value => value.phase === 1).length;
    Object.assign(metrics, {a_prompt_seen: aView.prompt, b_prompt_seen: bView.prompt, a_ready: aView.ready, b_ready: bView.ready, a_submit_count: aView.submitCount, token_submits: aView.tokenSubmits + bView.tokenSubmits, dirty_preserved: aView.dirty, saved_ack: aView.saved, a_put_count: counts.A, b_put_count: counts.B, same_keys: sameKeys, same_files: sameFiles, transition_auth_responses: transitionReplies,
      new_auth_replies: wire.filter(value => value.phase === 2).length, new_429_replies: wire.filter(value => value.phase === 2 && value.status === 429).length,
      a_wire_proof_replies: wire.filter(value => value.phase === 2 && value.label === 'A' && value.code === 5).length, b_wire_proof_replies: wire.filter(value => value.phase === 2 && value.label === 'B' && value.code === 5).length,
      a_status_401: Boolean(held.A.firstStatus401), b_selection_401_count: protectedReads.filter(value => value.label === 'B' && value.code === 8 && value.status === 401).length, b_profile_401_count: protectedReads.filter(value => value.label === 'B' && value.code === 7 && value.status === 401).length, protected_read_count: protectedReads.length, observer_frame_count: frames.length, observer_frames_valid: frames.every(frame => frame.bytes <= 1024 && (frame.heartbeat || frame.expected)), wire_history_sha256: crypto.createHash('sha256').update(JSON.stringify(wire.map(value => [value.label === 'A' ? 1 : 2, value.phase, value.code, value.status, value.at]))).digest('hex')});
    metrics.max_sockets = maxSockets; metrics.timeline_overflow = timelineOverflow || aView.overflow || bView.overflow;
    t.diagnostic(JSON.stringify({timeline, a_ui: aView.events, b_ui: bView.events, truth: truth.map(value => [value.at, value.done, value.ok])}));
    t.diagnostic(JSON.stringify(metrics));
    assert.equal(metrics.recovered, true, 'original fixed10s automatic recovery must finish with proof and protected status');
    if (deliveryMode === 'reverse') {assert.equal(metrics.jar_a_after_delivery, true); assert.equal(metrics.a_status_401, true, 'late204 cannot substitute for current protected status');}
    assert.equal(metrics.token_submits, 0); assert.equal(metrics.dirty_preserved, true); assert.equal(metrics.saved_ack, false); assert.equal(metrics.route_error, false); assert.equal(metrics.observer_frames_valid, true); assert.equal(metrics.a_prompt_seen, false); assert.equal(metrics.b_prompt_seen, false);
    assert.equal(metrics.same_keys, true); assert.equal(metrics.same_files, true); assert.equal(metrics.a_put_count, 0); assert.equal(metrics.b_put_count, 0);
    assert.equal(wire.filter(value => value.phase === 2 && [1, 2, 3].includes(value.code)).length, 0, 'no new bootstrap/enrollment after ordinary restart');
    assert.equal(transitionReplies, 0, 'server process admission attribution must be qualified');
    assert.equal(metrics.observer_after, true);
    assert.equal(metrics.observer_final, true); assert.equal(metrics.timeline_overflow, false); assert.ok(metrics.max_sockets <= 3);
    assert.equal(truth.every(value => value.done && value.ok), true, 'actual rejection/loss UI truth stays within2s');
  } finally {
    const ui = []; for (const [label, page] of Object.entries(pages)) {try {ui.push({label: label === 'A' ? 1 : 2, value: await page.evaluate(() => ({events: window.__cookieFault.events, overflow: window.__cookieFault.overflow}))});} catch {ui.push({label: label === 'A' ? 1 : 2, unavailable: true});}}
    t.diagnostic(JSON.stringify({timeline, ui, truth: truth.map(value => [value.at, value.done, value.ok]), metrics}));
    for (const timer of pendingTimers) clearTimeout(timer);
    for (const h of Object.values(held)) {if (h.endedAt < 0) await h.route.abort('failed').catch(() => {}); h.release();}
    try {
      if (observer && observer.readyState !== WebSocket.CLOSED) await new Promise((resolve, reject) => {let timer = setTimeout(() => {observerForced = true; observer.terminate(); reject(new Error('Observer close exceeded5s'));}, 5000); observer.once('close', () => {clearTimeout(timer); resolve();}); observer.close();});
    } finally {await context.close(); t.diagnostic(JSON.stringify({mode: deliveryMode === 'reverse' ? 1 : 2, original_frozen: originalFrozen, observer_forced: observerForced, t0_ms: t0, tagged_ms: taggedAt, route_error: metrics.route_error}));}
  }
});

test('TC-022-006: missing selected authorization asset fails closed', {timeout: 45000}, async t => {
  const {profiles} = await fixture(t, true), p = profiles[0];
  const context = await browser.newContext({ignoreHTTPSErrors: true}); t.after(() => context.close());
  const page = await context.newPage(); await page.goto(p.origin);
  await page.locator('#login').waitFor({state: 'visible'});
  await page.locator('#token').fill(p.env.WSTX_TOKEN); await page.locator('#login button').click(); await connected(page);
  let blockedAssets = 0, websocketAttempts = 0, profileReads = 0, bootstrapPosts = 0;
  page.on('websocket', () => websocketAttempts++);
  page.on('request', request => {
    if (request.url().endsWith('/profile')) profileReads++;
    if (request.url().endsWith('/session') && request.method() === 'POST') bootstrapPosts++;
  });
  await page.route('**/authorization.js', async route => {blockedAssets++; await route.abort();});
  await page.reload();
  try {await page.locator('#connection').filter({hasText: 'Authorization component unavailable'}).waitFor();}
  catch (error) {
    t.diagnostic(JSON.stringify({blockedAssets, websocketAttempts, profileReads, bootstrapPosts,
      connection: await page.locator('#connection').textContent()}));
    assert.equal(websocketAttempts, 0, 'missing selected manager must never initiate a socket'); throw error;
  }
  assert.equal(blockedAssets, 1);
  assert.equal(websocketAttempts, 0); assert.equal(profileReads, 0); assert.equal(bootstrapPosts, 0);
  assert.equal(await page.locator('#connection').getAttribute('data-state'), 'stale');
  assert.equal(await page.locator('#login').isHidden(), true, 'a missing component cannot fall back to transient login');
});

for (const action of ['reload', 'save']) test(`TC-022-006: held ${action} body cannot cross authorization renewal`, {timeout: 45000}, async t => {
  const {profiles} = await fixture(t, true), p = profiles[0];
  const context = await browser.newContext({ignoreHTTPSErrors: true}); t.after(() => context.close());
  const page = await context.newPage(); await page.goto(p.origin);
  await page.locator('#login').waitFor({state: 'visible'});
  await page.locator('#token').fill(p.env.WSTX_TOKEN); await page.locator('#login button').click(); await connected(page);
  let putCount = 0;
  page.on('request', request => {if (request.url().endsWith('/profile') && request.method() === 'PUT') putCount++;});
  await page.evaluate(method => {
    const originalFetch = window.fetch;
    const gate = window.profileBodyCompletion = {held: false, released: false, timedOut: false};
    let armed = true;
    window.fetch = async (...args) => {
      const response = await originalFetch(...args);
      if (armed && String(args[0]) === '/profile' && (args[1]?.method || 'GET') === method && response.status === 200) {
        armed = false;
        const nativeJson = response.json.bind(response);
        response.json = async () => {
          const actual = await nativeJson();
          gate.method = method; gate.status = response.status; gate.profile_id = actual.profile_id; gate.revision = actual.revision;
          gate.oldSocket = socket;
          gate.held = true;
          await new Promise(resolve => {
            const timer = setTimeout(() => {gate.timedOut = true; resolve();}, 10000);
            gate.release = () => {clearTimeout(timer); gate.released = true; resolve();};
          });
          return actual;
        };
      }
      return response;
    };
  }, action === 'save' ? 'PUT' : 'GET');
  t.after(async () => {try {await page.evaluate(() => window.profileBodyCompletion.release?.());} catch {}});
  const intendedName = action === 'save' ? 'Committed before lost completion' : 'Operator unsaved value';
  await page.locator('#display-name').fill(intendedName);
  const oldEpoch = await page.evaluate(() => window.stationAuthorization.snapshot().epoch);
  await page.locator(action === 'save' ? '#settings-save' : '#settings-reload').click();
  await page.waitForFunction(() => window.profileBodyCompletion.held);
  const heldIdentity = await page.evaluate(() => {
    const gate = window.profileBodyCompletion; return {method: gate.method, status: gate.status, profile_id: gate.profile_id, revision: gate.revision};
  });
  assert.deepEqual(heldIdentity, {method: action === 'save' ? 'PUT' : 'GET', status: 200, profile_id: p.document.profile_id, revision: action === 'save' ? 1 : 0});
  await context.clearCookies();
  await page.evaluate(async () => {try {await window.stationAuthorization.fetch('/profile');} catch {}});
  await page.waitForFunction(previous => {const now = window.stationAuthorization.snapshot(); return now.ready && now.epoch > previous;}, oldEpoch);
  await connected(page);
  assert.equal(await page.evaluate(() => socket !== window.profileBodyCompletion.oldSocket && socket.readyState === WebSocket.OPEN && window.profileBodyCompletion.oldSocket.readyState === WebSocket.CLOSED), true);
  assert.equal(await page.locator('#display-name').inputValue(), intendedName, 'new socket preserves the in-progress form');
  await page.evaluate(() => window.profileBodyCompletion.release());
  await page.locator('#settings-result').filter({hasText: action === 'save' ? 'Save outcome unknown' : 'Could not load saved settings'}).waitFor();
  assert.equal(await page.locator('#display-name').inputValue(), intendedName, 'old completion must not overwrite the form');
  assert.equal(await page.evaluate(() => window.profileBodyCompletion.timedOut), false, 'the controlled completion was released explicitly');
  assert.equal(putCount, action === 'save' ? 1 : 0, 'no automatic mutation replay');
  const committed = JSON.parse(await fs.readFile(path.join(p.dir, 'profile.json'), 'utf8'));
  assert.equal(committed.revision, action === 'save' ? 1 : 0);
  assert.equal(committed.display_name, action === 'save' ? intendedName : 'Station 1');
  if (action === 'save') assert.equal(await page.locator('#settings-save').isDisabled(), true, 'unknown save needs explicit reload');
});

// Client continuation only: the reservation success is simulated; backend mutation guards remain intact.
test('TC-022-006: simulated reservation upload intent cannot cross authorization renewal', {timeout: 45000}, async t => {
  const {profiles} = await fixture(t, true), p = profiles[0];
  const context = await browser.newContext({ignoreHTTPSErrors: true}); t.after(() => context.close());
  const page = await context.newPage(); await page.goto(p.origin);
  await page.locator('#login').waitFor({state: 'visible'});
  await page.locator('#token').fill(p.env.WSTX_TOKEN); await page.locator('#login button').click(); await connected(page);
  await page.locator('#open-recordings').click();
  await page.locator('#recording-import').waitFor({state: 'visible'});
  await page.waitForFunction(() => !document.querySelector('#recording-import').disabled);
  const baseline = await page.evaluate(async () => (await window.stationAuthorization.fetch('/recording')).json());
  const resource = `/recording/imports/${uuid(999)}`;
  let reservationRequests = 0, reservationAccepted = false, chunks = 0, heldRoute;
  let markHeld; const held = new Promise(resolve => {markHeld = resolve;});
  page.on('request', request => {
    if (request.url() === p.origin + resource && request.method() === 'PUT') chunks++;
  });
  await page.route('**/recording/imports', async route => {
    const request = route.request(); assert.equal(request.method(), 'POST'); reservationRequests++;
    assert.deepEqual(JSON.parse(request.postData()), {v: 1, profile_id: baseline.profile_id, boot_id: baseline.boot_id, generation: baseline.generation});
    assert.equal(request.headers().origin, p.origin);
    assert.equal(await page.evaluate(() => window.stationAuthorization.snapshot().ready), true);
    reservationAccepted = true;
    await route.fulfill({status: 201, headers: {'Content-Type': 'application/json', Location: resource},
      body: JSON.stringify({v: 1, id: uuid(999), generation: baseline.generation + 1, state: 'reserved'})});
  });
  await page.route('**/recording', async route => {
    if (reservationAccepted && !heldRoute) {heldRoute = route; markHeld();} else await route.continue();
  });
  t.after(async () => {try {await heldRoute?.continue();} catch {}});
  // The bytes must never be dispatched; this is an intent-fence fixture, not a WAV generator.
  await page.locator('#recording-file').setInputFiles({name: 'not-dispatched.wav', mimeType: 'audio/wav', buffer: Buffer.from([0])});
  await page.locator('#recording-import').click(); await held;
  assert.equal(reservationRequests, 1); assert.equal(reservationAccepted, true);
  const oldEpoch = await page.evaluate(() => window.stationAuthorization.snapshot().epoch);
  await context.clearCookies();
  await page.evaluate(async () => {try {await window.stationAuthorization.fetch('/profile');} catch {}});
  await page.waitForFunction(previous => {
    const current = window.stationAuthorization.snapshot(); return current.ready && current.epoch > previous;
  }, oldEpoch);
  await heldRoute.continue();
  try {await page.locator('#recording-progress').filter({hasText: 'Import intent changed'}).waitFor();}
  catch (error) {
    t.diagnostic(JSON.stringify({chunks, reservationRequests, reservationAccepted, oldEpoch, progress: await page.locator('#recording-progress').textContent(),
      authorization: await page.evaluate(() => window.stationAuthorization.snapshot())}));
    assert.equal(chunks, 0, 'independent count even if the progress oracle failed'); throw error;
  }
  assert.equal(chunks, 0, 'no upload chunk from the old explicit intent may be sent after proof');
});

// Proves: FR-001, FR-019, FR-021, FR-022; CL-005-01..03/05; TC-022-001.
// Actual process persistence only; uses the existing TLS/profile fixture and its retained child handles.
test('TC-022-006: actual browser and server process restart', {timeout: 90000}, async t => {
  const {profiles, apps, base} = await fixture(t, true), p = profiles[0];
  const profileDir = path.join(base, 'owned-persistent-chromium');
  const idlePeers = [];
  const tracked = new Map(), counts = {session: 0, enroll: 0, challenge: 0, proof: 0, status: 0, bootstrapScope: 0, profile: 0, ws: 0, wsErrors: 0};
  let context;
  function browserProcesses() {
    const quoted = profileDir.replaceAll("'", "''");
    const command = `@(Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('chrome.exe','chrome-headless-shell.exe') } | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CreationDate,@{Name='OwnProfile';Expression={$_.CommandLine -like '*${quoted}*'}}) | ConvertTo-Json -Compress`;
    const output = execFileSync('powershell.exe', ['-NoProfile', '-Command', command], {encoding: 'utf8', windowsHide: true, timeout: 5000}).trim();
    const parsed = output ? JSON.parse(output) : [], all = Array.isArray(parsed) ? parsed : [parsed];
    const owned = all.filter(item => item.OwnProfile || tracked.get(item.ProcessId) === item.CreationDate);
    for (let i = 0; i < owned.length; i++) for (const child of all.filter(item => item.ParentProcessId === owned[i].ProcessId)) if (!owned.some(item => item.ProcessId === child.ProcessId)) owned.push(child);
    for (const item of owned) tracked.set(item.ProcessId, item.CreationDate);
    return owned;
  }
  function serverIdentity(app) {
    assert.ok(Number.isInteger(app.child.pid) && app.child.pid > 0);
    return JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-Command', `Get-CimInstance Win32_Process -Filter 'ProcessId=${app.child.pid}' | Select-Object ProcessId,ParentProcessId,CreationDate,ExecutablePath | ConvertTo-Json -Compress`], {encoding: 'utf8', windowsHide: true, timeout: 5000}).trim());
  }
  async function openBrowser() {
    context = await chromium.launchPersistentContext(profileDir, {headless: true, ignoreHTTPSErrors: true});
    context.on('request', request => {
      const url = new URL(request.url()); if (url.origin !== p.origin) return;
      const key = {'/session': 'session', '/authorization/v1/enroll': 'enroll', '/authorization/v1/challenge': 'challenge', '/authorization/v1/proof': 'proof', '/authorization/v1/status': 'status', '/authorization/v1/bootstrap-scope': 'bootstrapScope', '/profile': 'profile'}[url.pathname];
      if (key) counts[key]++;
    });
    const page = context.pages()[0] || await context.newPage();
    page.on('websocket', ws => {
      counts.ws++; const peer = {ws, createdAt: performance.now(), frames: 0, closedAt: null, errors: 0}; idlePeers.push(peer);
      ws.on('framereceived', () => {peer.frames++;}); ws.on('close', () => {peer.closedAt = performance.now();});
      ws.on('socketerror', () => {counts.wsErrors++; peer.errors++;});
    });
    await page.addInitScript(() => {
      window.__idleAuthorizationTimeline = [];
      addEventListener('station-authorization', event => window.__idleAuthorizationTimeline.push({state: event.detail.state, at: performance.now()}));
    });
    await page.goto(p.origin);
    return page;
  }
  async function metadata(page) {
    return page.evaluate(async () => {
      const db = await new Promise((resolve, reject) => {const request = indexedDB.open('wstx-authorization-v1', 1); request.onupgradeneeded = () => request.transaction.abort(); request.onerror = () => reject(new Error('Retained credential database missing')); request.onsuccess = () => resolve(request.result);});
      try {
        const value = await new Promise((resolve, reject) => {const request = db.transaction('credential').objectStore('credential').get('current'); request.onsuccess = () => resolve(request.result); request.onerror = () => reject(new Error('Retained credential unavailable'));});
        if (!value || !(value.key instanceof CryptoKey)) throw new Error('Retained credential missing');
        return {grant_id: value.grant_id, public_key: value.public_key, enrollment_id: value.enrollment_id, scope: value.scope, extractable: value.key.extractable, usages: value.key.usages};
      } finally {db.close();}
    });
  }
  const fileHashes = async () => Object.fromEntries(await Promise.all(['profile.json', 'authorization.json'].map(async name => [name, crypto.createHash('sha256').update(await fs.readFile(path.join(p.dir, name))).digest('hex')])));
  t.after(async () => {
    const cleanupErrors = [];
    try {await context?.close();} catch (error) {cleanupErrors.push(error);}
    finally {
      try {assert.equal(browserProcesses().length, 0, 'all owned persistent-browser processes must exit');}
      catch (error) {cleanupErrors.push(error);}
    }
    if (cleanupErrors.length) {
      retainFixtureRoot = true;
      t.diagnostic('Persistent browser shutdown unqualified; retaining owned fixture root: ' + root);
      throw new AggregateError(cleanupErrors, 'Persistent cleanup failed; owned fixture root retained');
    }
  });
  assert.equal(await fs.stat(profileDir).then(() => true, () => false), false, 'fresh exclusively owned browser profile');
  let page = await openBrowser();
  await page.locator('#login').waitFor({state: 'visible'});
  await page.locator('#token').fill(p.env.WSTX_TOKEN); await page.locator('#login button').click(); await connected(page);
  assert.equal(await page.locator('#token').inputValue(), '');
  const originalMetadata = await metadata(page), originalBoot = await page.locator('#profile-boot').textContent();
  assert.equal(originalMetadata.extractable, false); assert.deepEqual(originalMetadata.usages, ['sign']);
  assert.equal(counts.session, 1); assert.equal(counts.enroll, 1);
  // Proves CL-022-01/02/05: initial authorization must not leave an extra reconnect/socket owner.
  const idleBefore = {...counts}, idleStart = await page.evaluate(() => {
    window.__idleOriginalSocket = socket;
    return {at: performance.now(), timeline: window.__idleAuthorizationTimeline.slice(), epoch: window.stationAuthorization.snapshot().epoch};
  });
  const unavailableAt = idleStart.timeline.find(item => item.state === 'unavailable')?.at;
  const idleQualified = Number.isFinite(unavailableAt) && idleStart.at < unavailableAt + 4000;
  await page.waitForTimeout(5500);
  const idleObservation = await page.evaluate(() => ({sameSocket: socket === window.__idleOriginalSocket,
    originalState: window.__idleOriginalSocket?.readyState, currentState: socket?.readyState,
    state: connection.dataset.state, boot: profileData?.boot_id, authorization: window.stationAuthorization.snapshot(),
    loginHidden: document.querySelector('#login').hidden, timeline: window.__idleAuthorizationTimeline.slice()}));
  const idlePeerEvidence = idlePeers.map(peer => ({createdAt: peer.createdAt, frames: peer.frames,
    closedAt: peer.closedAt, errors: peer.errors, closed: peer.ws.isClosed()}));
  t.diagnostic(JSON.stringify({scope: 'fresh authorization stable idle only', idleQualified, idleStart,
    elapsedMs: performance.now() - idlePeers[0]?.createdAt, idleBefore, counts: {...counts}, idleObservation, idlePeerEvidence}));
  assert.equal(idleQualified, true, 'initial authorization must finish before original4s timer boundary; otherwise reproduction unqualified, no retry');
  assert.equal(counts.ws, 1, 'stable initial authorization must create only one actual WebSocket');
  assert.equal(idlePeerEvidence.filter(peer => !peer.closed).length, 1, 'one live observed peer');
  assert.equal(idlePeerEvidence[0].frames > 0, true, 'actual first peer received station frames');
  assert.equal(idleObservation.sameSocket, true); assert.equal(idleObservation.originalState, 1); assert.equal(idleObservation.currentState, 1);
  assert.equal(idleObservation.state, 'connected'); assert.equal(idleObservation.boot, originalBoot);
  assert.equal(idleObservation.authorization.epoch, idleStart.epoch); assert.equal(idleObservation.authorization.ready, true);
  assert.equal(idleObservation.loginHidden, true);
  for (const key of ['session', 'enroll', 'challenge', 'proof', 'status']) assert.equal(counts[key], idleBefore[key], 'stable idle does not repeat ' + key);
  const firstBrowser = browserProcesses(); assert.ok(firstBrowser.some(item => item.OwnProfile), 'actual first persistent browser generation observed');
  // Leave only about:blank in the owned profile, avoiding an unobserved restored-page request on relaunch.
  await page.goto('about:blank'); await context.clearCookies();
  assert.equal((await context.cookies(p.origin)).length, 0, 'transport removed without deleting IndexedDB');
  await context.close(); context = null;
  assert.equal(browserProcesses().length, 0, 'first browser process exits before relaunch');
  page = await openBrowser(); await connected(page);
  const secondBrowser = browserProcesses(); assert.ok(secondBrowser.some(item => item.OwnProfile), 'actual second persistent browser generation observed');
  assert.ok(secondBrowser.filter(item => item.OwnProfile).every(item => !firstBrowser.some(old => old.ProcessId === item.ProcessId && old.CreationDate === item.CreationDate)), 'new process creation identities, not same-page reload');
  assert.deepEqual(await metadata(page), originalMetadata, 'same retained origin key/grant, no injected store');
  assert.equal(await page.locator('#profile-boot').textContent(), originalBoot, 'browser restart does not restart server');
  assert.equal(counts.session, 1); assert.equal(counts.enroll, 1);
  assert.equal(counts.bootstrapScope + counts.enroll + counts.challenge + counts.proof + counts.status, 8, 'five fresh plus three retained auth-v1 admissions');
  const oldApp = p.app, oldServer = serverIdentity(oldApp), durableBefore = await fileHashes(), beforeRestart = {...counts};
  const originalEpoch = await page.evaluate(() => window.stationAuthorization.snapshot().epoch);
  await oldApp.close(); assert.notEqual(oldApp.child.exitCode ?? oldApp.child.signalCode, null, 'retained child has actually exited');
  const restarted = await start(p, p.env); apps.push(restarted); p.app = restarted;
  const restoredAt = performance.now(), deadline = restoredAt + 10000, newServer = serverIdentity(restarted);
  assert.ok(newServer.ProcessId !== oldServer.ProcessId || newServer.CreationDate !== oldServer.CreationDate, 'actual new server process identity');
  let recovered = true;
  try {await page.waitForFunction(oldBoot => connection.dataset.state === 'connected' && socket?.readyState === WebSocket.OPEN && profileData?.boot_id !== oldBoot, originalBoot, {timeout: Math.max(1, deadline - performance.now())});}
  catch {recovered = false;}
  const observation = await page.evaluate(() => ({connection: connection.textContent, state: connection.dataset.state, socketState: socket?.readyState, boot: profileData?.boot_id, authorization: window.stationAuthorization.snapshot()}));
  t.diagnostic(JSON.stringify({scope: 'actual browser/server process restart only', originalBoot, originalEpoch, observation, recovered, recoveryElapsedMs: performance.now() - restoredAt, counts, beforeRestart, firstBrowser, secondBrowser, oldServer, newServer}));
  assert.deepEqual(await fileHashes(), durableBefore, 'ordinary restart/proof does not rewrite settings or verifier record');
  assert.equal(counts.session, 1, 'no second token submission'); assert.equal(counts.enroll, 1, 'no enrollment replay');
  assert.equal(recovered, true, 'actual server restart must recover fresh correlated profile readiness within original10s');
  assert.notEqual(observation.boot, originalBoot); assert.equal(observation.authorization.ready, true);
  assert.deepEqual(await metadata(page), originalMetadata);
  assert.ok(counts.challenge > beforeRestart.challenge && counts.proof > beforeRestart.proof && counts.status > beforeRestart.status, 'new server transport map requires real retained proof/status');
});


// Proves CL-022-01/02/05, partial TC-022-006: browser/store loss, not native CAT or durable-write failure.
for (const committed of [true, false]) test(`TC-022-006: ${committed ? 'committed' : 'undelivered'} enrollment survives actual process restart`, {timeout: 90000}, async t => {
  const assets = [], assetWork = [];
  // Completed stages: 1 initial pending/store/auth, 2 pending UI, 3 cookie, 4 processes, 5 DCL, 6 window, 7 all assertions.
  const observation = {enrollment_observation: committed ? 1 : 2, stage: 0, assertions_passed: false, asset_error: false, assets,
    initial_store_checked: false, initial_auth_context_checked: false, pending_ui_checked: false, cookie_checked: false,
    process_restart_checked: false, restarted_navigation_checked: false, observation_complete: false, final_assertions_passed: false};
  try {
  let context, fixtureValue, releaseInitial;
  const initialClosed = new Promise(resolve => {releaseInitial = resolve;});
  try {fixtureValue = await fixture(t, true);} catch {throw new Error('Enrollment fixture setup unavailable');}
  const {profiles, apps, base} = fixtureValue, p = profiles[0], profileDir = path.join(base, 'owned-enrollment-chromium');
  const captureAssets = (target, generation) => target.on('response', response => {
    let url, code;
    try {url = new URL(response.url()); code = url.pathname === '/app.js' ? 1 : url.pathname === '/authorization.js' ? 2 : 0;}
    catch {observation.asset_error = true; return;}
    if (url.origin !== p.origin || !code) return;
    assetWork.push((async () => {try {
      const body = await response.body();
      if (assets.length >= 8 || body.length > 131072) {observation.asset_error = true; return;}
      assets.push([generation, code, response.status(), crypto.createHash('sha256').update(body).digest('hex')]);
    } catch {observation.asset_error = true;}})());
  });
  const tracked = new Map(), counts = {session: 0, enroll: 0, followup: 0, mutation: 0, sockets: 0, protectedBeforeReceipt: 0}, replies = [];
  let initial = true, routeError = false, forwarded = false, enrollFailed = false, enrollment, retained, receiptHeld = false, receiptReleased = false;
  let holdSnapshot = false, rejectedIntent = false, holdNoEffects = false, readyEarly = false, connectedEarly = false;
  let resolveEnrollment;
  const enrollmentSeen = new Promise(resolve => {resolveEnrollment = resolve;});
  const wire = [Array(9).fill(0), Array(9).fill(0)], attempts = [Array(9).fill(0), Array(9).fill(0)];
  const authCode = pathname => ({'/session': 1, '/authorization/v1/bootstrap-scope': 2, '/authorization/v1/enroll': 3, '/authorization/v1/challenge': 4, '/authorization/v1/proof': 5, '/authorization/v1/status': 6, '/authorization/v1/receipt': 7}[pathname] || 8);
  let holdElapsed = -1, holdWithinDeadline = false, holdQualified = false, guardMs = -1;
  const observedBoots = new Set(); let earlySocket = false;
  const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  function processes() {
    const quoted = profileDir.replaceAll("'", "''");
    const command = `@(Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('chrome.exe','chrome-headless-shell.exe') } | Select-Object ProcessId,ParentProcessId,CreationDate,@{Name='OwnProfile';Expression={$_.CommandLine -like '*${quoted}*'}}) | ConvertTo-Json -Compress`;
    let all; try {const out = execFileSync('powershell.exe', ['-NoProfile', '-Command', command], {encoding: 'utf8', windowsHide: true, timeout: 5000}).trim(); const parsed = out ? JSON.parse(out) : []; all = Array.isArray(parsed) ? parsed : [parsed];} catch {throw new Error('Owned browser identity unavailable');}
    const own = all.filter(v => v.OwnProfile || tracked.get(v.ProcessId) === v.CreationDate);
    for (let i = 0; i < own.length; i++) for (const child of all.filter(v => v.ParentProcessId === own[i].ProcessId)) if (!own.some(v => v.ProcessId === child.ProcessId)) own.push(child);
    for (const v of own) tracked.set(v.ProcessId, v.CreationDate);
    return own;
  }
  function serverIdentity(app) {
    try {const value = JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-Command', `Get-CimInstance Win32_Process -Filter 'ProcessId=${app.child.pid}' | Select-Object ProcessId,CreationDate | ConvertTo-Json -Compress`], {encoding: 'utf8', windowsHide: true, timeout: 5000}).trim()); return {pid: value.ProcessId, created: value.CreationDate};} catch {throw new Error('Owned server identity unavailable');}
  }
  async function metadata(page) {
    try {return await page.evaluate(async () => {
      const db = await new Promise((resolve, reject) => {const r = indexedDB.open('wstx-authorization-v1', 1); r.onupgradeneeded = () => r.transaction.abort(); r.onerror = () => reject(new Error('Retained store unavailable')); r.onsuccess = () => resolve(r.result);});
      try {const v = await new Promise((resolve, reject) => {const r = db.transaction('credential').objectStore('credential').get('current'); r.onerror = () => reject(new Error('Retained credential unavailable')); r.onsuccess = () => resolve(r.result);});
        return {grant: v?.grant_id, operation: v?.enrollment_id, public: v?.public_key, scope: v?.scope, pending: v?.pending_enrollment, keyValid: v?.key instanceof CryptoKey && v.key.extractable === false && v.key.type === 'private' && v.key.usages.join(',') === 'sign'};
      } finally {db.close();}
    });} catch {throw new Error('Retained metadata unavailable');}
  }
  async function store() {try {return JSON.parse(await fs.readFile(path.join(p.dir, 'authorization.json'), 'utf8'));} catch {throw new Error('Enrollment store inspection unavailable');}}
  function storeValid(value, expected) {
    const grants = value.grants.filter(v => v.grant_id === enrollment.grant_id), entries = value.operation_receipts.filter(v => v.operation_id === enrollment.operation_id);
    if (!expected) return grants.length === 0 && entries.length === 0 && value.grants.length === 0 && value.operation_receipts.length === 0;
    const scope = {wire: enrollment.scope, https_origin: p.origin};
    return value.grants.length === 1 && value.operation_receipts.length === 1 && grants.length === 1 && entries.length === 1 &&
      grants[0].public_key === enrollment.public_key && grants[0].enrollment_operation_id === enrollment.operation_id && equal(grants[0].scope, scope) &&
      entries[0].kind === 'enroll' && entries[0].grant_id === enrollment.grant_id && equal(entries[0].scope, scope) && equal(entries[0].owner_verifier, grants[0]);
  }
  async function openBrowser() {
    try {context = await chromium.launchPersistentContext(profileDir, {headless: true, ignoreHTTPSErrors: true});} catch {throw new Error('Owned browser launch unavailable');}
    const page = context.pages()[0] || await context.newPage();
    captureAssets(page, initial ? 1 : 2);
    await page.addInitScript(watchUnknown => {
      window.__enrollmentDcl = 0; window.__enrollmentReleased = false;
      window.__enrollmentSafety = {earlyReady: false, earlyConnected: false, earlySocket: false, loginExposed: false, watchUnknown};
      const NativeWebSocket = window.WebSocket;
      window.WebSocket = new Proxy(NativeWebSocket, {construct(target, args, newTarget) {if (!window.__enrollmentReleased) window.__enrollmentSafety.earlySocket = true; return Reflect.construct(target, args, newTarget);}});
      const inspect = records => {
        const v = window.__enrollmentSafety, connection = document.querySelector('#connection'), login = document.querySelector('#login');
        if (!window.__enrollmentReleased && (connection?.dataset.state === 'connected' || records.some(r => r.target === connection && r.attributeName === 'data-state' && r.oldValue === 'connected'))) v.earlyConnected = true;
        if (v.watchUnknown && (login && !login.hidden || records.some(r => r.target === login && r.attributeName === 'hidden' && r.oldValue === null))) v.loginExposed = true;
      };
      new MutationObserver(inspect).observe(document, {subtree: true, childList: true, attributes: true, attributeOldValue: true, attributeFilter: ['data-state','hidden']});
      window.__enrollmentInspect = () => inspect([]);
      addEventListener('DOMContentLoaded', () => {window.__enrollmentDcl = performance.now(); inspect([]);}, {once: true});
      addEventListener('station-authorization', event => {if (event.detail.ready && !window.__enrollmentReleased) window.__enrollmentSafety.earlyReady = true;});
    }, !initial);
    page.on('request', req => {const u = new URL(req.url()); if (u.origin !== p.origin) return;
      if (u.pathname === '/session' || u.pathname.startsWith('/authorization/v1/')) {const code = authCode(u.pathname); attempts[initial ? 0 : 1][code]++; if (u.pathname === '/session') wire[initial ? 0 : 1][code]++;}
      if (u.pathname === '/session') counts.session++;
      if (u.pathname === '/authorization/v1/enroll') counts.enroll++;
      if (initial && ['/authorization/v1/challenge','/authorization/v1/proof','/authorization/v1/receipt'].includes(u.pathname)) counts.followup++;
      if (req.method() === 'PUT') counts.mutation++;
      if (!receiptReleased && (u.pathname === '/profile' || u.pathname.startsWith('/receive/') || u.pathname.startsWith('/recordings'))) counts.protectedBeforeReceipt++;
    });
    page.on('requestfailed', req => {if (initial && new URL(req.url()).pathname === '/authorization/v1/enroll') enrollFailed = true;});
    page.on('response', res => {const u = new URL(res.url()); if (u.origin !== p.origin) return;
      if (u.pathname === '/session' || u.pathname.startsWith('/authorization/v1/')) replies.push({path: u.pathname, status: res.status(), initial});
      if (!initial && u.pathname === '/profile' && res.status() === 200) res.json().then(value => {if (typeof value.boot_id === 'string') observedBoots.add(value.boot_id);}, () => {routeError = true;});
    });
    page.on('websocket', () => {counts.sockets++; if (!receiptReleased) earlySocket = true;});
    await page.route(p.origin + '/authorization/v1/**', async route => {
      const req = route.request(), pathname = new URL(req.url()).pathname;
      try {
        if (initial && ['/authorization/v1/challenge','/authorization/v1/proof','/authorization/v1/receipt'].includes(pathname)) {await initialClosed; try {await route.abort('failed');} catch {} return;}
        if (initial && pathname.endsWith('/enroll')) {
          enrollment = JSON.parse(req.postData()); retained = await metadata(page);
          if (committed) {
            const headers = await req.allHeaders(); wire[initial ? 0 : 1][authCode(pathname)]++; const result = await request(p.origin, 'POST', req.postDataBuffer(), {Origin: p.origin, 'Content-Type': 'application/json', Cookie: headers.cookie || ''}, pathname);
            replies.push({path: pathname, status: result.status, initial});
            forwarded = result.status === 200 && result.body?.version === 1 && result.body?.outcome === 'committed' && result.body?.operation_id === enrollment.operation_id && result.body?.grant_id === enrollment.grant_id && equal(result.body?.scope, enrollment.scope) && !result.headers['set-cookie'] && storeValid(await store(), true);
          }
          await route.abort('failed'); resolveEnrollment(); return;
        }
        if (!initial && committed && pathname.endsWith('/receipt')) {
          const headers = await req.allHeaders(); wire[initial ? 0 : 1][authCode(pathname)]++; const result = await request(p.origin, 'POST', req.postDataBuffer(), {Origin: p.origin, 'Content-Type': 'application/json', Cookie: headers.cookie || ''}, pathname);
          replies.push({path: pathname, status: result.status, initial});
          const valid = result.status === 200 && result.body?.version === 1 && result.body?.outcome === 'committed' && result.body?.operation_id === enrollment.operation_id && result.body?.grant_id === enrollment.grant_id && equal(result.body?.scope, enrollment.scope) && !result.headers['set-cookie'];
          if (!valid) {routeError = true; await route.abort('failed'); return;}
          receiptHeld = true;
          const target = result.completedAt + 500;
          const release = new Promise(resolve => {setTimeout(async () => {
            try {
              await page.evaluate(() => {window.__enrollmentInspect(); window.__enrollmentReleased = true;});
              const elapsed = await page.evaluate(() => performance.now() - window.__enrollmentDcl);
              holdElapsed = performance.now() - result.completedAt; holdWithinDeadline = elapsed < 10000;
              holdQualified = holdElapsed >= 500 && holdElapsed < 1000 && holdWithinDeadline;
              receiptReleased = true;
              await route.fulfill({status: result.status, contentType: 'application/json', body: result.rawBody});
            } catch {routeError = true; try {await route.abort('failed');} catch {}}
            finally {resolve();}
          }, Math.max(0, target - performance.now()));});
          const guard = await page.evaluate(async body => {
            const start = performance.now(); let timer;
            const operation = window.stationAuthorization.fetch('/profile', {method: 'PUT', headers: {'Content-Type': 'application/json'}, body}).then(() => 1, () => 2);
            const outcome = await Promise.race([operation, new Promise(resolve => {timer = setTimeout(() => resolve(3), 0);})]);
            clearTimeout(timer);
            return {unknown: !window.stationAuthorization.snapshot().ready, rejected: outcome === 2 && !window.__enrollmentReleased, elapsed: performance.now() - start};
          }, JSON.stringify(edit(1, 0)));
          holdSnapshot = guard.unknown; rejectedIntent = guard.rejected; guardMs = guard.elapsed;
          await release;
          holdNoEffects = counts.mutation === 0 && counts.protectedBeforeReceipt === 0;
          return;
        }
        wire[initial ? 0 : 1][authCode(pathname)]++; await route.continue();
      } catch {routeError = true; resolveEnrollment(); try {await route.abort('failed');} catch {}}
    });
    return page;
  }
  t.after(async () => {releaseInitial(); try {await context?.close(); if (processes().length) throw new Error('Owned process survives');} catch {retainFixtureRoot = true; throw new Error('Enrollment browser cleanup unqualified');}});
  let page = await openBrowser(); const firstBrowser = processes();
  assert.equal(firstBrowser.length > 0 && firstBrowser.some(v => v.OwnProfile && v.ProcessId > 0 && Boolean(v.CreationDate)), true);
  const profileBefore = await fs.readFile(path.join(p.dir, 'profile.json'));
  await page.goto(p.origin); await page.locator('#login').waitFor({state: 'visible', timeout: 10000});
  try {await page.locator('#token').fill(p.env.WSTX_TOKEN); await page.locator('#login button').click();} catch {throw new Error('Enrollment bootstrap interaction unavailable');}
  let enrollmentTimer;
  try {await Promise.race([enrollmentSeen, new Promise((_, reject) => {enrollmentTimer = setTimeout(() => reject(new Error('Enrollment interception unavailable')), 10000);})]);} finally {clearTimeout(enrollmentTimer);}
  await page.waitForFunction(() => window.stationAuthorization?.snapshot().state === 'unavailable', null, {timeout: 10000});
  assert.equal(routeError, false); assert.equal(enrollFailed, true); assert.equal(committed ? forwarded : !forwarded, true);
  assert.equal(retained?.keyValid && retained.pending && retained.grant === enrollment.grant_id && retained.operation === enrollment.operation_id && retained.public === enrollment.public_key && equal(retained.scope, enrollment.scope), true);
  assert.equal((await metadata(page)).pending, true); assert.equal(await page.evaluate(() => !window.stationAuthorization.snapshot().ready), true);
  assert.equal(replies.some(v => v.path === '/session' && v.status === 204), true);
  assert.equal(replies.some(v => v.path.endsWith('/bootstrap-scope') && v.status === 200), true);
  assert.equal(replies.some(v => v.path.endsWith('/receipt') && v.status === 200), false);
  assert.equal(storeValid(await store(), committed), true);
  observation.initial_store_checked = true; observation.initial_auth_context_checked = true; observation.stage = 1;
  const durableBefore = await fs.readFile(path.join(p.dir, 'authorization.json'));
  await page.evaluate(() => {window.__enrollmentSafety.watchUnknown = true; window.__enrollmentInspect();});
  let pendingUi = false;
  try {await page.waitForFunction(() => document.querySelector('#login').hidden && /enrollment outcome unknown/i.test(document.querySelector('#connection').textContent), null, {timeout: 2000}); pendingUi = true;} catch {}
  assert.equal(pendingUi, true, 'pending enrollment must remain explicitly unknown without replacement login');
  const initialSafety = await page.evaluate(() => window.__enrollmentSafety);
  assert.equal(initialSafety.earlyReady || initialSafety.earlyConnected || initialSafety.earlySocket || initialSafety.loginExposed || earlySocket, false);
  observation.pending_ui_checked = true; observation.stage = 2;
  const cookieName = `wstx_session_${p.document.profile_id}`;
  const cookies = await context.cookies(p.origin), bootstrapName = `wstx_bootstrap_${p.document.profile_id}`, cookie = cookies.find(v => v.name === bootstrapName);
  assert.equal(Boolean(cookie?.value) && cookie.secure && cookie.httpOnly, true);
  assert.equal(cookies.some(v => v.name === cookieName), false);
  // No transport exists before proof: this narrow clear is deliberately a no-op, not expiry coverage.
  await context.clearCookies({name: cookieName, domain: 'localhost'});
  const afterClear = await context.cookies(p.origin);
  assert.equal(afterClear.some(v => v.name === cookieName), false);
  assert.equal(afterClear.some(v => v.name === bootstrapName && v.value === cookie.value), true);
  assert.equal(equal(await metadata(page), retained), true);
  observation.cookie_checked = true; observation.stage = 3;
  releaseInitial(); await context.close(); context = null; const closedBrowser = processes(); assert.equal(closedBrowser.length, 0);
  assert.equal(firstBrowser.every(v => !closedBrowser.some(n => n.ProcessId === v.ProcessId && n.CreationDate === v.CreationDate)), true);
  const oldServer = serverIdentity(p.app); await p.app.close();
  assert.equal(p.app.child.exitCode !== null || p.app.child.signalCode !== null, true);
  try {p.app = await start(p, p.env); apps.push(p.app);} catch {throw new Error('Owned enrollment server restart unavailable');}
  const nextServer = serverIdentity(p.app); assert.equal(oldServer.pid !== nextServer.pid || oldServer.created !== nextServer.created, true);
  assert.equal((await fs.readFile(path.join(p.dir, 'authorization.json'))).equals(durableBefore), true);
  initial = false; page = await openBrowser(); const secondBrowser = processes();
  assert.equal(secondBrowser.length > 0 && secondBrowser.some(v => v.OwnProfile && v.ProcessId > 0 && Boolean(v.CreationDate)), true);
  assert.equal(secondBrowser.filter(v => v.OwnProfile).every(v => firstBrowser.every(old => old.ProcessId !== v.ProcessId || old.CreationDate !== v.CreationDate)), true);
  observation.process_restart_checked = true; observation.stage = 4;
  await page.goto(p.origin, {waitUntil: 'domcontentloaded'});
  const anchor = await page.evaluate(() => window.__enrollmentDcl); assert.equal(anchor > 0, true);
  observation.restarted_navigation_checked = true; observation.stage = 5;
  const deadline = performance.now() + await page.evaluate(at => Math.max(0, at + 10000 - performance.now()), anchor);
  let recovered = false, recoveredMs = -1, unknownSeen = false, unknownLost = false;
  while (performance.now() < deadline) {
    const state = await page.evaluate(() => ({ready: window.stationAuthorization.snapshot().ready, elapsed: performance.now() - window.__enrollmentDcl, open: typeof socket !== 'undefined' && socket?.readyState === WebSocket.OPEN, boot: typeof profileData !== 'undefined' && profileData?.boot_id, pendingUi: document.querySelector('#login').hidden && /enrollment outcome unknown/i.test(document.querySelector('#connection').textContent)}));
    const connectedNow = await page.locator('#connection').getAttribute('data-state') === 'connected';
    if (state.ready && connectedNow && state.open && /^[0-9a-f]{8}-[0-9a-f-]{27}$/.test(state.boot) && observedBoots.has(state.boot) && !recovered) {recovered = true; recoveredMs = state.elapsed;}
    if (!committed) {readyEarly ||= state.ready; connectedEarly ||= connectedNow; if (state.pendingUi) unknownSeen = true; else if (unknownSeen && state.elapsed >= 2000) unknownLost = true;}
    await new Promise(r => setTimeout(r, Math.min(25, Math.max(0, deadline - performance.now()))));
  }
  observation.observation_complete = true; observation.stage = 6;
  if (committed && receiptHeld) assert.equal(holdQualified, true, 'receipt hold timing instrumentation must qualify before product verdict');
  const after = await metadata(page), safety = await page.evaluate(() => {window.__enrollmentInspect(); return window.__enrollmentSafety;});
  assert.equal(safety.earlyReady || safety.earlyConnected || safety.earlySocket || safety.loginExposed || earlySocket, false);
  assert.equal(wire.every(bucket => bucket.reduce((sum, n) => sum + n, 0) <= 10 && bucket[8] === 0), true);
  assert.equal(replies.some(v => v.status === 429), false);
  assert.equal(wire[0][1] === 1 && wire[0][2] === 1 && wire[0][3] === (committed ? 1 : 0), true);
  assert.equal(routeError, false); assert.equal(counts.session, 1); assert.equal(counts.enroll, 1); assert.equal(counts.mutation, 0);
  assert.equal(after.keyValid && after.grant === retained.grant && after.public === retained.public && after.operation === retained.operation && equal(after.scope, retained.scope), true);
  assert.equal(storeValid(await store(), committed), true);
  assert.equal((await fs.readFile(path.join(p.dir, 'authorization.json'))).equals(durableBefore), true);
  assert.equal((await fs.readFile(path.join(p.dir, 'profile.json'))).equals(profileBefore), true);
  const finalTransport = (await context.cookies(p.origin)).filter(v => v.name === cookieName);
  if (committed) {
    assert.equal(finalTransport.length === 1 && Boolean(finalTransport[0].value) && finalTransport[0].secure && finalTransport[0].httpOnly, true);
    assert.equal(receiptHeld && receiptReleased && holdSnapshot && rejectedIntent && holdNoEffects, true);
    assert.equal(readyEarly || connectedEarly, false); assert.equal(recovered && recoveredMs >= 0 && recoveredMs < 10000, true); assert.equal(after.pending, false);
    assert.equal(replies.some(v => !v.initial && v.path.endsWith('/proof') && v.status === 204), true);
    assert.equal(replies.some(v => !v.initial && v.path.endsWith('/status') && v.status === 200), true);
  } else {
    assert.equal(finalTransport.length, 0);
    assert.equal(readyEarly || connectedEarly || recovered, false); assert.equal(after.pending, true); assert.equal(unknownSeen && !unknownLost, true); assert.equal(counts.sockets, 0); assert.equal(counts.protectedBeforeReceipt, 0);
    assert.equal(replies.some(v => !v.initial && ['/authorization/v1/proof','/authorization/v1/receipt'].includes(v.path) && v.status >= 200 && v.status < 300), false);
  }
  observation.final_assertions_passed = true; observation.assertions_passed = true; observation.stage = 7;
  t.diagnostic(JSON.stringify({enrollment_loss: committed ? 1 : 2, qualified: true, recovered, recovered_ms: recoveredMs, bootstrap_count: counts.session, enrollment_count: counts.enroll, queued_mutations: counts.mutation, receipt_held: receiptHeld, native_observed: false, hold_ms: holdElapsed, hold_qualified: holdQualified, guard_ms: guardMs, auth_wire_counts: wire, auth_attempt_counts: attempts}));
  } finally {
    // Reporting must not replace the original product assertion; a missing report remains collector failure.
    try {await Promise.all(assetWork); t.diagnostic(JSON.stringify(observation));} catch {}
  }
});

test('TC-022-001: four real windows, independent edits and HTTP input boundaries', {timeout: 60000}, async t => {
  const {profiles} = await fixture(t), beforeBytes = await savedBytes(profiles);
  const {pages, context} = await browserWindows(t, profiles);
  await Promise.all(pages.map(connected));
  const boots = new Set();
  for (let i = 0; i < 4; i++) {
    const snapshot = (await request(profiles[i].origin)).body;
    assert.deepEqual(Object.keys(snapshot).sort(), ['boot_id','connection_type','endpoint','profile_id','revision','settings']); assert.equal(snapshot.profile_id, uuid(i + 1)); assert.deepEqual(snapshot.settings, settings(i + 1)); assert.equal(snapshot.endpoint, profiles[i].origin); boots.add(snapshot.boot_id);
    assert.equal(await pages[i].locator('#profile-id').textContent(), uuid(i + 1)); assert.match(await pages[i].title(), new RegExp(`Station ${i + 1}`));
  }
  assert.equal(boots.size, 4);
  const page = pages[0];
  await page.locator('#display-name').fill('Edited station 1'); await page.locator('#audio-input').fill('changed-input-1'); await page.locator('#control-mode').selectOption('cat'); await page.locator('#control-endpoint').fill('fixture-cat-1');
  await page.locator('#settings-save').click(); await page.locator('#settings-result').filter({hasText: 'Saved revision 1'}).waitFor();
  const second = await context.newPage(); await second.goto(profiles[0].origin); await connected(second); assert.equal(await second.locator('#display-name').inputValue(), 'Edited station 1'); await second.close();
  for (let i = 1; i < 4; i++) assert.equal((await savedBytes(profiles))[i], beforeBytes[i]);
  assert.equal(await page.locator('#native-option').isDisabled(), true); assert.equal(await page.locator('#native-reserved').isVisible(), true);
  assert.equal(await page.locator('#radio').textContent(), 'Radio not configured');
  let revision = 1;
  async function invalid(body, status = 400, code = 'invalid_settings', headers) {const before = await savedBytes(profiles); const r = await request(profiles[0].origin, 'PUT', body, headers); assert.equal(r.status, status); assert.equal(r.body.error.code, code); assert.deepEqual(await savedBytes(profiles), before);}
  for (const [field, badValues] of Object.entries({display_name: ['', 'X'.repeat(65), ' leading', 'trailing ', 'bad\nname', 1], callsign: ['AB', 'A'.repeat(13), 'abc1', 'ABC', '123', '<BAD>'], locator: ['JN4', 'SN47', 'JN47YY', 'JN47AA9', 1]})) {
    for (const value of badValues) {const values = settings(1); values[field] = value; await invalid(edit(1, revision, values));}
  }
  for (const bad of [{audio: {input_device: '', output_device: null}}, {audio: {input_device: 'X'.repeat(257), output_device: null}}, {audio: {input_device: 'bad\u0085', output_device: null}}, {control: {mode: 'disabled', endpoint: null, ptt: 'cat'}}, {control: {mode: 'cat', endpoint: null, ptt: 'disabled'}}, {control: {mode: 'native_flex', endpoint: null, ptt: 'disabled'}}]) await invalid(edit(1, revision, {...settings(1), ...bad}));
  for (const body of ['{', '[]', {...edit(1, revision), extra: true}, {revision, settings: settings(1)}, {...edit(1, revision), revision: '1'}, JSON.stringify(edit(1, revision)).replace('"revision":1', '"revision":1,"revision":1')]) await invalid(body);
  const missingAudio = edit(1, revision); delete missingAudio.settings.audio.input_device;
  const missingOutput = edit(1, revision); delete missingOutput.settings.audio.output_device;
  const missingControl = edit(1, revision); delete missingControl.settings.control.endpoint;
  for (const value of [missingAudio, missingOutput, missingControl, {...edit(1, revision), profile_id: 'bad'}, {...edit(1, revision), revision: -1}, {...edit(1, revision), revision: 1.5}, {...edit(1, revision), revision: Number.MAX_SAFE_INTEGER + 1}, {...edit(1, revision), connection_type: 'native_flex'}, {...edit(1, revision), settings: {...settings(1), native: true}}, Buffer.from([0xff])]) await invalid(value);
  await invalid(edit(1, revision, settings(1), uuid(2)), 403, 'wrong_profile');
  await invalid(edit(1, 0), 409, 'revision_conflict'); await invalid(edit(1, revision), 415, 'unsupported_media_type', {'Content-Type': 'text/plain'});
  await invalid(JSON.stringify(edit(1, revision)).padEnd(8193, ' '), 413, 'request_too_large');
  const maximum = settings(1); maximum.display_name = 'X'.repeat(64); maximum.callsign = 'A12345678901'; maximum.locator = 'RR99XX99'; maximum.audio = {input_device: 'X'.repeat(256), output_device: null};
  assert.equal((await request(profiles[0].origin, 'PUT', JSON.stringify(edit(1, revision, maximum)).padEnd(8192, ' '))).status, 200); revision++;
  for (const patch of [{display_name: 'X', callsign: '', locator: '', audio: {input_device: null, output_device: null}}, {callsign: 'A1B', locator: 'JN47'}, {locator: 'JN47AA', audio: {input_device: null, output_device: 'X'.repeat(256)}}, {control: {mode: 'cat', endpoint: 'X'.repeat(256), ptt: 'cat'}}]) {
    assert.equal((await request(profiles[0].origin, 'PUT', edit(1, revision, {...settings(1), ...patch}))).status, 200); revision++;
  }
  assert.equal((await request(profiles[0].origin, 'DELETE')).status, 405);
  assert.equal((await request(profiles[0].origin, 'GET', undefined, {Origin: 'http://unrelated.invalid'})).status, 403);
  await page.reload(); await connected(page); await page.setViewportSize({width: 360, height: 900});
  await page.locator('#display-name').fill('X'.repeat(64)); await page.locator('#audio-output').fill('Y'.repeat(256));
  await page.locator('#settings-save').click(); await page.locator('#settings-result').filter({hasText: `Saved revision ${revision + 1}`}).waitFor(); revision++;
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, 'maximum name and identifiers wrap or remain within inputs');
  await fs.mkdir('test-results', {recursive: true}); await page.screenshot({path: 'test-results/profile-boundary-mobile.png', fullPage: true});
  const competing = await Promise.all([request(profiles[0].origin, 'PUT', edit(1, revision)), request(profiles[0].origin, 'PUT', edit(1, revision))]); assert.deepEqual(competing.map(r => r.status).sort(), [200, 409]); revision++;
  await page.reload(); await connected(page); await page.locator('#callsign').fill('bad'); await page.locator('#settings-save').click();
  await page.locator('#settings-result').filter({hasText: 'Invalid callsign'}).waitFor(); assert.equal(await page.locator('#callsign').inputValue(), 'bad');
  await page.locator('#refresh').click(); await connected(page); assert.equal(await page.locator('#callsign').inputValue(), 'bad', 'refresh preserves unsaved input');
  await page.locator('#settings-reload').click(); await page.locator('#settings-result').filter({hasText: 'Loaded saved settings.'}).waitFor();
  const staleWindow = await context.newPage(); await staleWindow.goto(profiles[0].origin); await connected(staleWindow);
  await staleWindow.locator('#display-name').fill('Unsaved concurrent edit');
  assert.equal((await request(profiles[0].origin, 'PUT', edit(1, revision))).status, 200); revision++;
  await staleWindow.locator('#settings-save').click(); await staleWindow.locator('#settings-result').filter({hasText: 'Reload saved settings before saving.'}).waitFor();
  assert.equal(await staleWindow.locator('#settings-save').isDisabled(), true); assert.equal(await staleWindow.locator('#display-name').inputValue(), 'Unsaved concurrent edit');
  await staleWindow.locator('#settings-reload').click(); await staleWindow.locator('#settings-result').filter({hasText: 'Loaded saved settings.'}).waitFor(); assert.equal(await staleWindow.locator('#settings-save').isEnabled(), true); await staleWindow.close();
  const literal = {...settings(1), display_name: '<img src=x onerror=alert(1)>', audio: {input_device: '<script>alert(1)</script>', output_device: null}};
  assert.equal((await request(profiles[0].origin, 'PUT', edit(1, revision, literal))).status, 200);
  let dialog = false; page.on('dialog', d => {dialog = true; d.dismiss();}); await page.reload(); await connected(page);
  assert.equal(await page.locator('#display-name').inputValue(), literal.display_name); assert.equal(await page.locator('#audio-input').inputValue(), literal.audio.input_device); assert.equal(await page.locator('#profile-name').textContent(), literal.display_name); assert.equal(await page.locator('img').count(), 0); assert.equal(dialog, false);
  await fs.mkdir('test-results', {recursive: true});
  await page.setViewportSize({width: 1100, height: 850});
  await page.screenshot({path: 'test-results/profile-desktop.png', fullPage: true});
  await page.setViewportSize({width: 360, height: 900}); assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true); assert.equal(await page.locator('#settings-save').isVisible(), true);
  await page.screenshot({path: 'test-results/profile-mobile.png', fullPage: true});
});

// Proves: FR-001, FR-016, FR-022; CL-005-02/04/05; TC-022-002.
test('TC-022-002: acknowledged persistence, defaults, strict files and recovery', {timeout: 60000}, async t => {
  const {profiles, apps, base} = await fixture(t);
  const created = path.join(base, 'created'), creating = launch(['--create-profile', created]); assert.equal((await creating.done)[0], 0); assert.doesNotMatch(creating.output, /WSTX listening/);
  const defaults = JSON.parse(await fs.readFile(path.join(created, 'profile.json'), 'utf8')); assert.match(defaults.profile_id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.deepEqual({...defaults, profile_id: 'identity'}, {schema_version: 1, profile_id: 'identity', revision: 0, display_name: 'New station', callsign: '', locator: '', endpoint: {bind: '127.0.0.1:8080', origin: null}, connection_type: 'standard', audio: {input_device: null, output_device: null}, control: {mode: 'disabled', endpoint: null, ptt: 'disabled'}});
  const originalBoots = [];
  for (let i = 0; i < 4; i++) {originalBoots.push((await request(profiles[i].origin)).body.boot_id); assert.equal((await request(profiles[i].origin, 'PUT', edit(i + 1, 0, {...settings(i + 1), display_name: `Persisted ${i + 1}`}))).status, 200);}
  const {pages} = await browserWindows(t, profiles); await Promise.all(pages.map(connected));
  let putCount = 0, releasePut, observedPut;
  const heldPut = new Promise(resolve => {releasePut = resolve;}), putStarted = new Promise(resolve => {observedPut = resolve;});
  await pages[0].route('**/profile', async route => {
    if (route.request().method() === 'PUT') {putCount++; observedPut(); await heldPut; const result = await route.fetch(); assert.equal(result.status(), 200); await route.abort();}
    else await route.continue();
  });
  await pages[0].locator('#display-name').fill('Committed despite lost response'); await pages[0].locator('#settings-save').click();
  await putStarted; try {assert.equal(await pages[0].locator('#display-name').isDisabled(), true); assert.equal(await pages[0].locator('#settings-reload').isDisabled(), true);} finally {releasePut();}
  await pages[0].locator('#settings-result').filter({hasText: 'Save outcome unknown'}).waitFor();
  assert.equal((await request(profiles[0].origin)).body.revision, 2); assert.equal(putCount, 1);
  await pages[0].locator('#settings-reload').click(); await pages[0].locator('#settings-result').filter({hasText: 'Loaded saved settings.'}).waitFor();
  assert.equal(await pages[0].locator('#display-name').inputValue(), 'Committed despite lost response'); assert.equal(putCount, 1, 'reload must not replay the lost-response save');
  await pages[0].unroute('**/profile');
  const persisted = await savedBytes(profiles); await Promise.all(apps.map(a => a.close()));
  for (let i = 0; i < 4; i++) {const app = await start(profiles[i]); apps.push(app); profiles[i].app = app; const snapshot = (await request(profiles[i].origin)).body; assert.equal(snapshot.revision, i === 0 ? 2 : 1); assert.equal(snapshot.settings.display_name, i === 0 ? 'Committed despite lost response' : `Persisted ${i + 1}`); assert.notEqual(snapshot.boot_id, originalBoots[i]);}
  assert.deepEqual(await savedBytes(profiles), persisted);
  await profiles[0].app.close(); const file = path.join(profiles[0].dir, 'profile.json');
  await fs.writeFile(path.join(profiles[0].dir, '.orphan.tmp'), 'invalid');
  const invalid = [
    ['{', 'invalid_profile'], [Buffer.from([0xff]), 'invalid_profile'], [{...profiles[0].document, schema_version: -1}, 'unsupported_schema'], [{...profiles[0].document, schema_version: 0}, 'unsupported_schema'], [{...profiles[0].document, schema_version: 2}, 'unsupported_schema'],
    [{...profiles[0].document, profile_id: 'bad'}, 'invalid_profile'], [{...profiles[0].document, extra: 1}, 'invalid_profile'], [{...profiles[0].document, connection_type: 'native_flex'}, 'unsupported_connection_type'],
    [{...profiles[0].document, endpoint: {bind: '127.0.0.1:0', origin: null}}, 'invalid_profile'], [{...profiles[0].document, endpoint: {bind: '127.0.0.1:65536', origin: null}}, 'invalid_profile'],
    [JSON.stringify(profiles[0].document).replace('"revision":0', '"revision":0,"revision":0'), 'invalid_profile'], [JSON.stringify(profiles[0].document).padEnd(16385, ' '), 'invalid_profile']
  ];
  for (const [value, category] of invalid) {const raw = Buffer.isBuffer(value) || typeof value === 'string' ? value : JSON.stringify(value); await fs.writeFile(file, raw); const before = await fs.readFile(file); await refusal(['--profile', profiles[0].dir], category); assert.deepEqual(await fs.readFile(file), before);}
  await fs.unlink(file); await refusal(['--profile', profiles[0].dir], 'resource_unavailable');
  await fs.writeFile(file, persisted[0].padEnd(16384, ' ')); const recovered = await start(profiles[0]); apps.push(recovered); assert.equal((await request(profiles[0].origin)).body.revision, 2); await recovered.close();
  await fs.writeFile(file, persisted[0]); const fromOtherCwd = await start({...profiles[0], dir: path.relative(base, profiles[0].dir)}, {}, base); apps.push(fromOtherCwd); await fromOtherCwd.close();
  const exhausted = {...JSON.parse(persisted[0]), revision: Number.MAX_SAFE_INTEGER}; await fs.writeFile(file, JSON.stringify(exhausted)); const last = await start(profiles[0]); apps.push(last); assert.equal((await request(profiles[0].origin, 'PUT', edit(1, Number.MAX_SAFE_INTEGER))).body.error.code, 'revision_exhausted'); await last.close();
  await fs.writeFile(file, persisted[0]);
  await refusal(['--create-profile', created], 'resource_unavailable'); const empty = path.join(base, 'empty'); await fs.mkdir(empty); await refusal(['--create-profile', empty], 'resource_unavailable'); await refusal(['--create-profile', path.join(base, 'absent', 'nested')], 'resource_unavailable');
  for (const args of [['--unknown'], ['--profile', profiles[0].dir, '--profile', profiles[0].dir], ['--create-profile', created, '--profile', profiles[0].dir]]) await refusal(args, 'invalid_runtime_configuration');
  for (const env of [{WSTX_BIND: '127.0.0.1:0'}, {WSTX_ORIGIN: 'http://localhost:8080'}]) await refusal(['--profile', profiles[0].dir], 'invalid_runtime_configuration', env);
});

// Proves: FR-021, FR-022; CL-005-03/04; TC-022-003.
test('TC-022-003: lifecycle, ownership aliases/copies, ports and unavailable resources', {timeout: 60000}, async t => {
  const {profiles, apps, base} = await fixture(t), before = await savedBytes(profiles);
  const {pages} = await browserWindows(t, profiles); await Promise.all(pages.map(connected));
  for (const other of profiles.slice(1)) assert.equal((await request(other.origin)).status, 200);
  await profiles[0].app.close(); await pages[0].locator('#connection[data-state="stale"]').waitFor();
  for (const page of pages.slice(1)) {const old = await page.locator('#updated').textContent(); const start = Date.now(); await page.locator('#refresh').click(); await page.waitForFunction(value => document.querySelector('#updated').textContent !== value, old, {timeout: 2000}); assert.ok(Date.now() - start <= 2000);}
  for (const other of profiles.slice(1)) assert.equal((await request(other.origin)).status, 200);
  profiles[0].app = await start(profiles[0]); apps.push(profiles[0].app); await connected(pages[0]);
  await refusal(['--profile', profiles[0].dir], 'profile_in_use');
  const alias = path.join(base, 'alias'); await fs.symlink(profiles[0].dir, alias, 'junction'); await refusal(['--profile', alias], 'profile_in_use');
  const copy = path.join(base, 'copy'); await fs.cp(profiles[0].dir, copy, {recursive: true}); await refusal(['--profile', copy], 'profile_in_use');
  const copyFile = path.join(copy, 'profile.json'); await fs.writeFile(copyFile, JSON.stringify({...profiles[0].document, profile_id: uuid(99)})); await refusal(['--profile', copy], 'endpoint_in_use');
  await profiles[0].app.close();
  for (const env of [{WSTX_TLS_CERT: tls.WSTX_TLS_CERT}, {...tls}, {WSTX_TOKEN: 'X'.repeat(32)}, {...tls, WSTX_TOKEN: 'short'}, {...tls, WSTX_TOKEN: 'X'.repeat(129)}, {...tls, WSTX_TOKEN: 'X'.repeat(31) + '!'}]) await refusal(['--profile', profiles[0].dir], 'invalid_runtime_configuration', env);
  await refusal(['--profile', profiles[0].dir], 'resource_unavailable', {...tls, WSTX_TLS_CERT: path.join(base, 'missing'), WSTX_TOKEN: 'X'.repeat(32)});
  const file = path.join(profiles[0].dir, 'profile.json');
  // Git Bash also ships whoami; this fixture needs the Windows SID/ACL tools.
  const system32 = path.join(process.env.SystemRoot, 'System32');
  const whoami = path.join(system32, 'whoami.exe'), icacls = path.join(system32, 'icacls.exe');
  const sid = execFileSync(whoami, ['/user', '/fo', 'csv', '/nh'], {encoding: 'utf8'}).match(/S-1-[0-9-]+/)[0];
  const readableBytes = await fs.readFile(file);
  // Deny data reads while preserving ACL read access needed by the finally cleanup.
  execFileSync(icacls, [file, '/deny', `*${sid}:(RD)`], {stdio: 'pipe'});
  try {
    await assert.rejects(fs.readFile(file), error => error.code === 'EACCES' || error.code === 'EPERM');
    await refusal(['--profile', profiles[0].dir], 'resource_unavailable');
  }
  finally {execFileSync(icacls, [file, '/remove:d', `*${sid}`], {stdio: 'pipe'});}
  assert.deepEqual(await fs.readFile(file), readableBytes);
  const port = new URL(profiles[0].origin).port;
  await fs.writeFile(file, JSON.stringify({...profiles[0].document, endpoint: {bind: `127.0.0.1:${port}`, origin: `http://localhost:${Number(port) + 1}`}})); await refusal(['--profile', profiles[0].dir], 'invalid_profile');
  await fs.writeFile(file, JSON.stringify({...profiles[0].document, endpoint: {bind: `127.0.0.1:${port}`, origin: `https://localhost:${port}`}})); await refusal(['--profile', profiles[0].dir], 'invalid_runtime_configuration');
  await fs.writeFile(file, JSON.stringify({...profiles[0].document, endpoint: {bind: '0.0.0.0:' + new URL(profiles[0].origin).port, origin: null}})); await refusal(['--profile', profiles[0].dir], 'invalid_runtime_configuration'); await fs.writeFile(file, before[0]);
  profiles[0].app = await start(profiles[0]); apps.push(profiles[0].app);
  await fs.chmod(file, 0o444); const failed = await request(profiles[0].origin, 'PUT', edit(1, 0)); await fs.chmod(file, 0o666); assert.equal(failed.status, 503); assert.equal(failed.body.error.code, 'storage_unavailable'); assert.equal((await request(profiles[0].origin)).body.revision, 0);
  assert.deepEqual(await savedBytes(profiles), before);
  await profiles[0].app.close();
  await fs.copyFile(tls.WSTX_TLS_CERT, path.join(base, 'cert.pem')); await fs.copyFile(tls.WSTX_TLS_KEY, path.join(base, 'key.pem'));
  const secured = {...profiles[0], origin: profiles[0].origin.replace('http:', 'https:')};
  const relativeTls = await start(secured, {WSTX_TLS_CERT: 'cert.pem', WSTX_TLS_KEY: 'key.pem', WSTX_TOKEN: 'X'.repeat(128)}, base); apps.push(relativeTls);
  assert.equal((await request(secured.origin)).status, 401);
});

async function login(p, value = p.env.WSTX_TOKEN, origin = p.origin) {
  return new Promise((resolve, reject) => {const req = https.request(p.origin + '/session', {method: 'POST', rejectUnauthorized: false, agent: false, headers: origin ? {Origin: origin} : {}}, res => {res.resume(); res.on('end', () => resolve({status: res.statusCode, cookie: res.headers['set-cookie']?.[0].split(';')[0], setCookie: res.headers['set-cookie']?.[0]}));}); req.on('error', reject); req.end(value);});
}
async function upgradeStatus(p, cookie, origin = p.origin) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(p.origin.replace('https', 'wss') + '/ws', 'wstx.v1', {origin, rejectUnauthorized: false, headers: cookie ? {Cookie: cookie} : {}});
    const timer = setTimeout(() => {ws.terminate(); reject(new Error('Upgrade timeout'));}, 5000);
    const finish = status => {clearTimeout(timer); ws.terminate(); resolve(status);};
    ws.on('error', () => {});
    ws.on('unexpected-response', (_req, res) => {res.on('error', () => {}); res.resume(); finish(res.statusCode);});
    ws.on('open', () => finish(101));
  });
}
// Proves: FR-019, FR-021, FR-022; CL-005-03/04; TC-022-004.
test('TC-022-004: same-host four-port TLS cookies, reconnect, negatives and rotation', {timeout: 60000}, async t => {
  const {profiles, apps} = await fixture(t, true); const {context, pages} = await browserWindows(t, profiles);
  for (let i = 0; i < 4; i++) {const p = profiles[i]; assert.equal((await request(p.origin)).status, 401); assert.equal((await request(p.origin, 'PUT', edit(i + 1, 0))).status, 401); assert.equal(await upgradeStatus(p), 401); if (i === 0) {await pages[i].route('**/session', route => route.abort()); await pages[i].locator('#token').fill(p.env.WSTX_TOKEN); await pages[i].locator('#login button').click(); await pages[i].locator('#login-error').filter({hasText: 'Could not authenticate'}).waitFor(); assert.equal(await pages[i].locator('#token').inputValue(), ''); await pages[i].unroute('**/session');} await pages[i].locator('#token').fill(p.env.WSTX_TOKEN); await pages[i].locator('#login button').click(); await connected(pages[i]);}
  for (let i = 3; i >= 0; i--) {const loggedIn = await login(profiles[i]); assert.equal(loggedIn.status, 204); assert.equal(/(?:^|;)\s*Domain=/i.test(loggedIn.setCookie), false); await pages[i].reload(); await connected(pages[i]); assert.equal(await pages[i].evaluate(async () => (await fetch('/profile')).status), 200);}
  const cookies = await context.cookies(); assert.equal(cookies.filter(c => c.name.startsWith('wstx_session_')).length, 4);
  for (const c of cookies) {assert.equal(c.secure, true); assert.equal(c.httpOnly, true); assert.equal(c.sameSite, 'Strict'); assert.equal(c.path, '/'); assert.equal(c.domain, 'localhost'); assert.ok(c.expires > Date.now() / 1000 + 28700);}
  const a = profiles[0], b = profiles[1], ca = cookies.find(c => c.name.endsWith(uuid(1))), cb = cookies.find(c => c.name.endsWith(uuid(2)));
  assert.equal((await login(b, a.env.WSTX_TOKEN)).status, 401);
  for (const bad of [`${ca.name}=${ca.value}`, `${cb.name}=${ca.value}`, `wstx_session=${b.env.WSTX_TOKEN}`, `${cb.name}=${cb.value}; ${cb.name}=${cb.value}`]) {assert.equal(await upgradeStatus(b, bad), 401); assert.equal((await request(b.origin, 'GET', undefined, {Cookie: bad})).status, 401); assert.equal((await request(b.origin, 'PUT', edit(2, 0), {Cookie: bad})).status, 401);}
  for (const origin of [a.origin, 'https://unrelated.invalid', null]) {assert.equal((await login(b, b.env.WSTX_TOKEN, origin)).status, 403); assert.equal((await request(b.origin, 'PUT', edit(2, 0), {Cookie: `${cb.name}=${cb.value}`, Origin: origin || ''})).status, 403); assert.equal(await upgradeStatus(b, `${cb.name}=${cb.value}`, origin || ''), 403);}
  assert.equal((await request(b.origin, 'PUT', edit(2, 0, settings(2), uuid(1)), {Cookie: `${cb.name}=${cb.value}`})).status, 403);
  const expired = {...ca, expires: Math.floor(Date.now() / 1000) - 10}; await context.addCookies([expired]);
  await pages[0].reload(); await pages[0].locator('#token').fill(a.env.WSTX_TOKEN); await pages[0].locator('#login button').click(); await connected(pages[0]);
  assert.equal((await context.cookies()).filter(c => c.name.startsWith('wstx_session_')).length, 4);
  const c = profiles[2], d = profiles[3];
  assert.equal((await login(c, 'X'.repeat(1024))).status, 401); assert.equal((await login(c, 'X'.repeat(1025))).status, 413);
  for (let i = 0; i < 8; i++) assert.equal((await login(d, 'W'.repeat(32))).status, 401);
  assert.equal((await login(d)).status, 429); assert.equal((await login(c)).status, 204, 'rate budgets belong to their profiles');
  const own = cookies.find(cookie => cookie.name.endsWith(uuid(3)));
  const ws = new WebSocket(c.origin.replace('https', 'wss') + '/ws', 'wstx.v1', {origin: c.origin, rejectUnauthorized: false, headers: {Cookie: `${own.name}=${own.value}`}}); ws.on('error', () => {}); await once(ws, 'open');
  const status = receive(ws); ws.send('{"v":1,"type":"station.get","id":17}'); assert.equal((await status).id, 17); ws.terminate();
  const oldToken = a.env.WSTX_TOKEN;
  await a.app.close(); a.env.WSTX_TOKEN = crypto.randomBytes(32).toString('hex'); a.app = await start(a, a.env); apps.push(a.app);
  assert.equal(await upgradeStatus(a, `${ca.name}=${ca.value}`), 401); assert.equal((await login(a, oldToken)).status, 401); await pages[0].locator('#token').fill(a.env.WSTX_TOKEN); await pages[0].locator('#login button').click(); await connected(pages[0]);
  for (let i = 1; i < 4; i++) {await pages[i].reload(); await connected(pages[i]);}
  for (const page of pages) {assert.deepEqual(await page.evaluate(() => [Object.keys(localStorage), Object.keys(sessionStorage)]), [[], []]); assert.equal(await page.locator('#token').inputValue(), '');}
});

// Proves: FR-019, FR-022; CL-005-02, CL-005-03; TC-022-001.
test('TC-022-001 review regression: Refresh cannot reopen a pending save', {timeout: 30000}, async t => {
  const {profiles} = await fixture(t), {pages} = await browserWindows(t, profiles);
  await Promise.all(pages.map(connected)); const page = pages[0];
  await page.evaluate(() => {
    const original = window.fetch; window.observedProfilePuts = 0;
    window.fetch = (...args) => {if (args[0] === '/profile' && args[1]?.method === 'PUT') window.observedProfilePuts++; return original(...args);};
  });
  let releaseGet, releasePut, observedGet, observedPut, getHeld = false, putCount = 0;
  const holdGet = new Promise(r => {releaseGet = r;}), holdPut = new Promise(r => {releasePut = r;});
  const gotGet = new Promise(r => {observedGet = r;}), gotPut = new Promise(r => {observedPut = r;});
  await page.route('**/profile', async route => {
    if (route.request().method() === 'GET' && !getHeld) {
      getHeld = true; const response = await route.fetch(); observedGet(); await holdGet; await route.fulfill({response});
    } else if (route.request().method() === 'PUT') {
      putCount++; observedPut(); await holdPut; await route.continue();
    } else await route.continue();
  });
  try {
    await page.locator('#display-name').fill('One pending save');
    const previousUpdate = await page.locator('#updated').textContent(); await page.locator('#refresh').click(); await gotGet;
    await page.locator('#settings-save').click(); await gotPut;
    releaseGet(); await page.waitForFunction(old => document.querySelector('#updated').textContent !== old, previousUpdate);
    const stayedDisabled = await page.locator('#settings-save').isDisabled();
    // requestSubmit also exercises the explicit submission guard, independently of
    // a disabled button. The observer counts real fetch invocations synchronously.
    await page.evaluate(() => document.querySelector('#settings').requestSubmit());
    assert.equal(stayedDisabled, true, 'Refresh must retain the pending Save disable');
    assert.equal(await page.evaluate(() => window.observedProfilePuts), 1, 'one form must issue only one pending PUT');
    releasePut(); await page.locator('#settings-result').filter({hasText: 'Saved revision 1'}).waitFor();
    assert.equal(putCount, 1); assert.equal((await request(profiles[0].origin)).body.revision, 1);
    for (const selector of ['#display-name', '#settings-save', '#settings-reload']) assert.equal(await page.locator(selector).isEnabled(), true);
    assert.equal(await page.locator('#settings select').first().isDisabled(), true);
  } finally {releaseGet(); releasePut();}

  // Inverse completion order: a real revision-0 Refresh response arrives only after
  // the save and its own revision-1 GET have already been acknowledged/rendered.
  const inverse = pages[1]; let releaseOld, observedOld, oldHeld = false;
  const oldResponse = new Promise(r => {releaseOld = r;}), oldStarted = new Promise(r => {observedOld = r;});
  await inverse.route('**/profile', async route => {
    if (route.request().method() === 'GET' && !oldHeld) {
      oldHeld = true; const response = await route.fetch(); observedOld(); await oldResponse; await route.fulfill({response});
    } else await route.continue();
  });
  try {
    await inverse.locator('#display-name').fill('Acknowledged revision 1');
    const beforeRefresh = await inverse.locator('#updated').textContent(); await inverse.locator('#refresh').click(); await oldStarted;
    await inverse.locator('#settings-save').click(); await inverse.locator('#settings-result').filter({hasText: 'Saved revision 1'}).waitFor();
    assert.equal(await inverse.locator('#profile-revision').textContent(), '1');
    releaseOld(); await inverse.waitForFunction(old => document.querySelector('#updated').textContent !== old, beforeRefresh);
    assert.equal(await inverse.locator('#profile-revision').textContent(), '1');
    assert.equal(await inverse.locator('#display-name').inputValue(), 'Acknowledged revision 1');
    assert.equal(await inverse.locator('#profile-name').textContent(), 'Acknowledged revision 1');
    assert.equal(await inverse.locator('#settings-result').textContent(), 'Saved revision 1');
    assert.equal(await inverse.locator('#settings-save').isEnabled(), true);
  } finally {releaseOld();}
});

// Proves: FR-016, FR-022; CL-005-02, CL-005-04; TC-022-002.
test('TC-022-002 review regression: admit the complete worst-case response budget', {timeout: 30000}, async t => {
  const {profiles, apps} = await fixture(t); const selected = profiles[0]; await selected.app.close();
  const file = path.join(selected.dir, 'profile.json'), port = new URL(selected.origin).port;
  // Independently authored from FSD12.5; never read from the candidate admission helper.
  const maximum = {display_name: '\\'.repeat(64), callsign: 'A12345678901', locator: 'RR99XX99', audio: {input_device: '\\'.repeat(256), output_device: '\\'.repeat(256)}, control: {mode: 'cat', endpoint: '\\'.repeat(256), ptt: 'disabled'}};
  const oracle = {profile_id: uuid(1), boot_id: uuid(2), revision: Number.MAX_SAFE_INTEGER, endpoint: '', connection_type: 'standard', settings: maximum};
  assert.equal(Buffer.byteLength(JSON.stringify(oracle), 'utf8'), 2018);
  const originFor = extra => 'http://' + 'a'.repeat(6174 - Buffer.byteLength(`http://:${port}`) + extra) + `:${port}`;
  const atBoundary = originFor(0), document = {...selected.document, ...maximum, revision: Number.MAX_SAFE_INTEGER - 1, endpoint: {bind: selected.document.endpoint.bind, origin: atBoundary}};
  assert.equal(Buffer.byteLength(JSON.stringify({...oracle, endpoint: atBoundary})), 8192);
  await fs.writeFile(file, JSON.stringify(document));
  const admitted = await start({...selected, origin: atBoundary}); apps.push(admitted);
  let result = await request(selected.origin, 'GET', undefined, {Origin: atBoundary}); assert.equal(result.status, 200); assert.equal(result.bodyBytes, 8192);
  result = await request(selected.origin, 'PUT', edit(1, Number.MAX_SAFE_INTEGER - 1, maximum), {Origin: atBoundary}); assert.equal(result.status, 200); assert.equal(result.bodyBytes, 8192);
  await admitted.close();
  for (const origin of [originFor(1), `http://${'a'.repeat(9000)}:${port}`]) {
    // The initial settings are small; admission must reserve future valid maximums.
    const bad = {...selected.document, revision: Number.MAX_SAFE_INTEGER - 1, endpoint: {bind: selected.document.endpoint.bind, origin}};
    await fs.writeFile(file, JSON.stringify(bad)); const before = await fs.readFile(file);
    const rejected = launch(['--profile', selected.dir]); apps.push(rejected);
    const deadline = Date.now() + 10000;
    while (rejected.child.exitCode === null && rejected.child.signalCode === null && !rejected.output.includes('WSTX listening ') && Date.now() < deadline) await new Promise(r => setTimeout(r, 10));
    if (rejected.output.includes('WSTX listening ')) {
      const reproduced = await request(selected.origin, 'PUT', edit(1, Number.MAX_SAFE_INTEGER - 1, maximum), {Origin: origin});
      assert.ok(reproduced.bodyBytes > 8192, 'old-code reproduction must observe the oversized response');
      await rejected.close(); assert.fail('Over-budget profile reached readiness and returned an oversized save response');
    }
    const [code, signal] = await rejected.done; assert.equal(signal, null); assert.notEqual(code, 0); assert.match(rejected.output, /invalid_profile/); assert.deepEqual(await fs.readFile(file), before);
  }
  for (const other of profiles.slice(1)) assert.equal((await request(other.origin)).status, 200);
});
// Proves: FR-022; CL-005-02, CL-005-03, CL-006-04; TC-022-005.
test('TC-022-005: status readiness survives held settings HTTP with bounded refresh', {timeout: 45000}, async t => {
  const {profiles} = await fixture(t), {pages, context} = await browserWindows(t, profiles);
  await Promise.all(pages.map(connected)); const page = pages[0];
  let release, entered, gets = 0;
  const held = new Promise(r => {release = r;}), started = new Promise(r => {entered = r;});
  await page.route('**/profile', async route => {
    gets++;
    if (gets === 1) {const response = await route.fetch(); entered(); await held; await route.fulfill({response});}
    else await route.continue();
  });
  // Existing socket was opened before the observer; observe its actual messages in
  // the browser too, independently of HTTP and the updated-label assertion.
  await page.evaluate(() => {window.statusReplies = 0; addEventListener('station-message', e => {if (e.detail.message.type === 'station.status') window.statusReplies++;});});
  async function refreshWithinBound() {
    const previous = await page.locator('#updated').textContent(), replies = await page.evaluate(() => window.statusReplies);
    await page.locator('#refresh').click();
    await page.waitForFunction(({previous, replies}) => window.statusReplies > replies && document.querySelector('#updated').textContent !== previous && !document.querySelector('#refresh').disabled, {previous, replies}, {timeout: 2000});
  }
  try {
    await page.locator('#callsign').fill('DIRTY');
    await refreshWithinBound(); await started;
    await refreshWithinBound(); await refreshWithinBound();
    assert.equal(gets, 1, 'held HTTP must coalesce concurrent Refresh requests');
    assert.equal((await request(profiles[0].origin, 'PUT', edit(1, 0, {...settings(1), display_name: 'New revision'}))).status, 200);
    release();
    await page.locator('#profile-name').filter({hasText: 'New revision'}).waitFor();
    assert.equal(gets, 2, 'exactly one queued follow-up obtains latest saved profile');
    assert.equal(await page.locator('#callsign').inputValue(), 'DIRTY');
  } finally {release();}
  await page.unroute('**/profile');

  // A closed old socket's late successful HTTP must not replace the new boot/form.
  let releaseOld, oldEntered;
  const oldHeld = new Promise(r => {releaseOld = r;}), oldStarted = new Promise(r => {oldEntered = r;});
  let oldGet = true;
  await page.route('**/profile', async route => {
    if (oldGet) {oldGet = false; const response = await route.fetch(); oldEntered(); await oldHeld; await route.fulfill({response});}
    else await route.continue();
  });
  try {
    await refreshWithinBound(); await oldStarted;
    assert.equal((await request(profiles[0].origin, 'PUT', edit(1, 1, {...settings(1), display_name: 'Newest socket'}))).status, 200);
    await page.evaluate(() => socket.close());
    await page.locator('#connection[data-state="stale"]').waitFor();
    await connected(page); await page.locator('#profile-name').filter({hasText: 'Newest socket'}).waitFor();
    await page.locator('#callsign').fill('NEWERDIRTY');
    releaseOld(); await page.waitForTimeout(100);
    assert.equal(await page.locator('#profile-name').textContent(), 'Newest socket');
    assert.equal(await page.locator('#callsign').inputValue(), 'NEWERDIRTY');
    assert.equal(await page.locator('#connection').getAttribute('data-state'), 'connected');
  } finally {releaseOld();}
  await page.unroute('**/profile');

  const initial = await context.newPage(); let releaseInitial, initialEntered;
  const initialHeld = new Promise(r => {releaseInitial = r;}), initialStarted = new Promise(r => {initialEntered = r;});
  let releaseReplacement, replacementEntered, initialGets = 0;
  const replacementHeld = new Promise(r => {releaseReplacement = r;}), replacementStarted = new Promise(r => {replacementEntered = r;});
  await initial.addInitScript(() => {window.readyEvents = 0; addEventListener('station-ready', () => {window.readyEvents++;});});
  await initial.route('**/profile', async route => {
    const first = ++initialGets === 1, response = await route.fetch();
    if (first) {initialEntered(); await initialHeld;} else {replacementEntered(); await replacementHeld;}
    await route.fulfill({response});
  });
  try {
    await initial.goto(profiles[0].origin); await initialStarted;
    assert.notEqual(await initial.locator('#connection').getAttribute('data-state'), 'connected');
    assert.equal(await initial.evaluate(() => window.readyEvents), 0);
    assert.equal(await initial.locator('#signal-status').textContent(), 'Waiting for station snapshot');
    await initial.evaluate(() => socket.close()); await replacementStarted;
    releaseInitial(); await initial.waitForTimeout(100);
    assert.notEqual(await initial.locator('#connection').getAttribute('data-state'), 'connected', 'late old-socket HTTP cannot initialize a replacement');
    assert.equal(await initial.locator('#profile-panel').isHidden(), true);
    assert.equal(await initial.evaluate(() => window.readyEvents), 0);
    releaseReplacement(); await connected(initial); assert.equal(await initial.evaluate(() => window.readyEvents), 1);
  } finally {releaseInitial(); releaseReplacement();}
  await initial.close();
  await page.route('**/profile', route => route.fulfill({status: 503, contentType: 'application/json', body: '{}'}));
  await page.locator('#refresh').click();
  await page.locator('#settings-result').filter({hasText: 'Could not load saved settings.'}).waitFor();
  await page.locator('#connection[data-state="stale"]').waitFor();
  const failed = await context.newPage();
  await failed.route('**/profile', route => route.fulfill({status: 503, contentType: 'application/json', body: '{}'}));
  await failed.goto(profiles[0].origin);
  await failed.locator('#connection').filter({hasText: 'could not load saved settings.'}).waitFor();
  assert.notEqual(await failed.locator('#connection').getAttribute('data-state'), 'connected');
});
