'use strict';
const {spawn} = require('node:child_process');
const {once} = require('node:events');
const net = require('node:net');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const {performance} = require('node:perf_hooks');

// Ports no test may hand to a browser or to Node's fetch: Chromium net/base/port_util.cc
// kRestrictedPorts (main branch, read 2026-10-31; a page on one fails with ERR_UNSAFE_PORT)
// united with the Fetch standard's bad ports that Node's fetch (undici) refuses with
// "bad port" (Node v26.13.0, read 2026-11-04; adds 4190 and 6679, #8), plus 0. Windows may
// hand out dynamic ports from 1024, so every port a browser or fetch uses comes from
// listenBrowser/browserPort (#35). The Rust tests that start node read the same file.
const restrictedPorts = new Set(require('./blocked-ports.json'));
// Listens `listener` on an OS-chosen port of `host` that Chromium and fetch accept, closing
// and retrying while the port is restricted. Resolves the port.
async function listenBrowser(listener, host = '127.0.0.1') {
  for (let attempt = 0; attempt < 64; attempt++) {
    listener.listen(0, host); await once(listener, 'listening');
    const {port} = listener.address();
    if (!restrictedPorts.has(port)) return port;
    await new Promise(resolve => listener.close(resolve));
  }
  throw new Error('No browser-accepted port after 64 attempts');
}
// A free port Chromium and fetch accept, released again for a child process to bind.
async function browserPort(host = '127.0.0.1') {
  const held = net.createServer();
  const port = await listenBrowser(held, host);
  await new Promise(resolve => held.close(resolve));
  return port;
}

// Without arguments or WSTX_BIND the server binds 127.0.0.1:0 itself; a restricted port
// it reports is discarded and the server started again.
async function server(env = {}, args = []) {
  for (let attempt = 0; ; attempt++) {
    const started = await serverOnce(env, args);
    if (args.length || 'WSTX_BIND' in env || attempt >= 63 || !restrictedPorts.has(Number(new URL(started.origin).port))) return started;
    await started.close();
  }
}
// The account-local station data of this test process: the profile UUID ownership claims
// and radio-ownership claims a station keeps under LOCALAPPDATA. Every station a test starts
// uses this per-run directory, so suites running at the same time in other checkouts (a push
// gate beside an agent) and the live station never share a claim (harness#28). Removed
// when the process exits.
let stationData;
function stationDataRoot() {
  if (!stationData) {
    stationData = fs.mkdtempSync(path.join(os.tmpdir(), 'wstx-test-station-'));
    process.once('exit', () => { try { fs.rmSync(stationData, {recursive: true, force: true}); } catch {} });
  }
  return stationData;
}
// Environment of a station a test starts: no inherited WSTX_ setting, no public SNTP
// server (WstxTransmitClock::TransmitClock), no UDP interface, and the per-run station data.
function stationEnv(env = {}) {
  const clean = {...process.env};
  // Windows environment names ignore case: no differently cased LOCALAPPDATA may survive.
  for (const key of Object.keys(clean)) if (key.startsWith('WSTX_') || key.toUpperCase() === 'LOCALAPPDATA') delete clean[key];
  return {...clean, WSTX_SNTP_SERVERS: '', WSTX_UDP: 'off', WSTX_PSKR: 'off', WSTX_RADIO_DISCOVERY: 'off', LOCALAPPDATA: stationDataRoot(), ...env};
}
async function serverOnce(env, args) {
  const exe = process.env.WSTX_TEST_EXE || path.resolve(process.env.CARGO_TARGET_DIR || 'target', 'debug', process.platform === 'win32' ? 'wstx-rust.exe' : 'wstx-rust');
  if (!fs.existsSync(exe)) throw new Error(`Missing candidate ${exe}; run cargo build --locked`);
  const child = spawn(exe, args, {env: stationEnv({...(args.length ? {} : {WSTX_BIND: '127.0.0.1:0'}), ...env}), windowsHide: true});
  let output = '';
  const origin = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => { child.kill(); reject(new Error('Server readiness timeout: ' + output)); }, 10000);
    child.stdout.on('data', data => {
      output += data;
      const match = output.match(/WSTX listening (https?:\/\/\S+)/);
      if (match) { clearTimeout(timer); resolve(match[1]); }
    });
    child.stderr.on('data', data => { output += data; });
    child.once('error', error => {clearTimeout(timer); reject(error);});
    child.once('exit', code => {clearTimeout(timer); reject(new Error(`Server exited ${code}: ${output}`));});
  });
  const endpoint = output.match(/WSTX address (https?:\/\/\S+)/)?.[1] || origin;
  return {origin, endpoint, child, async close() { if (child.exitCode === null && child.signalCode === null) { child.kill(); await once(child, 'exit'); } }};
}

// Byte-stream link simulator. TLS/WebSocket bytes are real; network headers are an explicit
// conservative model, NOT packet capture. Each <=512-byte segment is charged 80 bytes
// TCP/IPv6 + 80 bytes reverse ACK; counters and schedules share one bottleneck per direction.
async function link(target, {rate = 4000, latency = 150} = {}) {
  const sockets = new Set();
  const counters = {up: 0, down: 0};
  const next = {up: 0, down: 0};
  const timers = new Set();
  let enabled = true;
  let blackholed = false;
  function forward(source, destination, direction) {
    let pendingBytes = 0;
    source.on('data', data => {
      if (blackholed) return;
      source.pause();
      if (pendingBytes + data.length + destination.writableLength > 128 * 1024) {
        source.destroy(); destination.destroy(); return;
      }
      pendingBytes += data.length;
      for (let offset = 0; offset < data.length; offset += 512) {
        const part = data.subarray(offset, offset + 512);
        const reverse = direction === 'up' ? 'down' : 'up';
        const bytes = part.length + 80;
        counters[direction] += bytes; counters[reverse] += 80;
        const now = performance.now();
        next[direction] = Math.max(now, next[direction]) + bytes / rate * 1000;
        next[reverse] = Math.max(now, next[reverse]) + 80 / rate * 1000;
        const timer = setTimeout(() => {
          timers.delete(timer);
          pendingBytes -= part.length;
          if (pendingBytes + destination.writableLength > 128 * 1024) {
            source.destroy(); destination.destroy();
          } else if (!destination.destroyed && !blackholed) destination.write(part);
        }, Math.max(0, next[direction] + latency - performance.now()));
        timers.add(timer);
      }
      // Propagation is pipelined: it does not reduce the serialized link rate.
      const resume = setTimeout(() => {timers.delete(resume); source.resume();}, Math.max(0, next[direction] - performance.now()));
      timers.add(resume);
    });
  }
  const listener = net.createServer(client => {
    if (!enabled) {client.destroy(); return;}
    const upstream = net.connect(target);
    for (const socket of [client, upstream]) { sockets.add(socket); socket.on('error', () => socket.destroy()); socket.on('close', () => sockets.delete(socket)); }
    client.on('close', () => upstream.destroy()); upstream.on('close', () => client.destroy());
    forward(client, upstream, 'up'); forward(upstream, client, 'down');
  });
  const port = await listenBrowser(listener);
  return {port, counters, target,
    cut() {enabled = false; for (const socket of sockets) socket.destroy();},
    blackhole() {blackholed = true;},
    restore() {enabled = true; blackholed = false;},
    async close() {enabled = false; for (const socket of sockets) socket.destroy(); for (const timer of timers) clearTimeout(timer); listener.close(); await once(listener, 'close');}
  };
}
// Test client of the CL-022-01 auth-v1 flow for raw (non-browser) requests to a selected
// HTTPS profile: bootstrap with the token, enroll a P-256 key, prove it and return the
// transport cookie. `send(route, method, body, headers)` must resolve {status, headers, body}.
async function grant(origin, token, send) {
  const crypto = require('node:crypto');
  const session = await send('/session', 'POST', token, {});
  if (session.status !== 204) throw new Error('bootstrap session ' + session.status);
  const bootstrap = session.headers['set-cookie'][0].split(';')[0];
  const scoped = await send('/authorization/v1/bootstrap-scope', 'POST', {version: 1}, {Cookie: bootstrap});
  if (scoped.status !== 200) throw new Error('bootstrap scope ' + scoped.status);
  const scope = scoped.body.current_scope, {publicKey, privateKey} = crypto.generateKeyPairSync('ec', {namedCurve: 'P-256'});
  const jwk = publicKey.export({format: 'jwk'});
  const public_key = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]).toString('base64url');
  const grant_id = crypto.randomBytes(32).toString('base64url');
  const enrolled = await send('/authorization/v1/enroll', 'POST', {version: 1, operation_id: crypto.randomUUID(), scope, grant_id, public_key}, {Cookie: bootstrap});
  if (enrolled.status !== 200) throw new Error('enroll ' + enrolled.status);
  async function prove() {
    const challenge = await send('/authorization/v1/challenge', 'POST', {version: 1, grant_id}, {});
    if (challenge.status !== 200) throw new Error('challenge ' + challenge.status);
    const c = challenge.body.scope, parts = [Buffer.from('WSTX-AUTH-PROOF'), Buffer.from([1])];
    for (const field of [origin, c.profile_id, c.radio_id, String(c.safety_revision), grant_id].map(v => Buffer.from(v)).concat([Buffer.from(challenge.body.nonce, 'base64url')])) {
      const size = Buffer.alloc(4); size.writeUInt32BE(field.length); parts.push(size, field);
    }
    const signature = crypto.sign('sha256', Buffer.concat(parts), {key: privateKey, dsaEncoding: 'ieee-p1363'}).toString('base64url');
    const proof = await send('/authorization/v1/proof', 'POST', {version: 1, grant_id, nonce: challenge.body.nonce, signature}, {});
    if (proof.status !== 204) throw new Error('proof ' + proof.status);
    return proof.headers['set-cookie'][0].split(';')[0];
  }
  return {cookie: await prove(), prove, scope, grant_id};
}
// Browser side of the same flow: the real token form enrolls this context's nonextractable
// key; later pages of the context recover by retained-key proof without the token.
async function loginPage(page, origin, token, timeout = 30000) {
  await page.goto(origin, {timeout});
  await page.locator('#login').waitFor({state: 'visible', timeout});
  await page.locator('#token').fill(token); await page.locator('#login button').click();
  await page.locator('#connection[data-state="connected"]').waitFor({timeout});
}
module.exports = {server, stationEnv, link, grant, loginPage, restrictedPorts, listenBrowser, browserPort};
