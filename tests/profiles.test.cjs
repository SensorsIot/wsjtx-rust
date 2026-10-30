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
function request(origin, method = 'GET', body, headers = {}) {
  return new Promise((resolve, reject) => {
    const req = (origin.startsWith('https') ? https : http).request(origin + '/profile', {method, rejectUnauthorized: false, agent: false, headers: {Origin: origin, ...(body !== undefined ? {'Content-Type': 'application/json'} : {}), ...headers}}, res => {
      let data = ''; res.on('data', b => {data += b;}); res.on('end', () => resolve({status: res.statusCode, body: data ? JSON.parse(data) : null, bodyBytes: Buffer.byteLength(data, 'utf8'), headers: res.headers}));
    }); req.on('error', reject); if (body !== undefined) req.write(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body)); req.end();
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
