'use strict';
// The tests of the suite support (support.cjs): its browser ports, its per-run station data
// and the isolation settings of the stations it starts.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {once, EventEmitter} = require('node:events');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const {server, stationEnv, spawnStation, isolateProfile, restrictedPorts, listenBrowser, browserPort} = require('./support.cjs');

const exe = process.env.WSTX_TEST_EXE || path.resolve(process.env.CARGO_TARGET_DIR || 'target', 'debug', process.platform === 'win32' ? 'wstx-rust.exe' : 'wstx-rust');
const settings = i => ({display_name: `Station ${i}`, callsign: `TEST${i}`, locator: 'JN47AA', audio: {input_device: `{0.0.1.00000000}.{00000000-0000-4000-8000-${String(i).padStart(12, '0')}}`, output_device: `{0.0.0.00000000}.{00000000-0000-4000-8000-${String(i).padStart(12, '0')}}`}, control: {mode: 'disabled', endpoint: null, ptt: 'disabled'}});
// n distinct browser-accepted ports, all held until each is chosen.
async function ports(n) {
  const held = [];
  try {for (let i = 0; i < n; i++) {const s = net.createServer(); held.push(s); await listenBrowser(s);} return held.map(s => s.address().port);}
  finally {await Promise.all(held.map(s => new Promise(resolve => s.close(resolve))));}
}
// GET `route` (default /profile) of a plaintext station, with its own Origin.
function request(origin, route = '/profile') {
  return new Promise((resolve, reject) => {
    const req = http.request(origin + route, {headers: {Origin: origin}, agent: false}, res => {
      let data = ''; res.on('data', b => {data += b;}); res.on('end', () => {try {resolve({status: res.statusCode, body: JSON.parse(data)});} catch (error) {reject(error);}});
    });
    req.on('error', reject); req.end();
  });
}

// Test-tool oracle: a protocol fixture proves heartbeat interleaving and a fixed deadline.
// Chromium refuses its kRestrictedPorts with ERR_UNSAFE_PORT; Windows here hands out
// dynamic ports from 1024, so a browser-facing listen(0) can land on one.
test('port helper: browser- and fetch-facing ports are never Chromium restricted or fetch bad ports', async () => {
  // Spot values of Chromium net/base/port_util.cc kRestrictedPorts, including the ones seen on HB9BLA.
  for (const port of [1, 25, 1719, 1720, 1723, 2049, 5060, 5061, 6000, 6665, 6666, 6667, 6668, 6669, 6697, 10080]) assert.ok(restrictedPorts.has(port), String(port));
  for (const port of [80, 443, 1024, 8080, 18001]) assert.equal(restrictedPorts.has(port), false, String(port));
  // Node's fetch (undici) refuses the Fetch standard's bad ports with "bad port"; 4190 and
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

// Test isolation: a station a suite starts claims its profile
// UUID in the run's own account-local data, never in the account's shared one: the same
// UUID held there by a concurrent run (another checkout's suite or gate, started with the
// account's environment) does not refuse it with profile_in_use.
test('suite stations own profile UUIDs in per-run station data', {timeout: 30000}, async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-support-tests-')); t.after(() => fs.rm(root, {recursive: true, force: true}));
  const base = await fs.mkdtemp(path.join(root, 'isolation-')), [heldPort, ownPort] = await ports(2), id = crypto.randomUUID();
  const profile = async (name, port) => {
    const dir = path.join(base, name), origin = `http://127.0.0.1:${port}`;
    await fs.mkdir(dir); await fs.writeFile(path.join(dir, 'profile.json'), JSON.stringify({schema_version: 1, profile_id: id, revision: 0, ...settings(1), endpoint: {bind: `127.0.0.1:${port}`, origin: null}, connection_type: 'standard'}));
    return {dir, origin};
  };
  const account = {...process.env}; for (const key of Object.keys(account)) if (key.startsWith('WSTX_')) delete account[key];
  const held = await profile('held', heldPort), heldLock = path.join(process.env.LOCALAPPDATA || os.tmpdir(), 'wstx-rust-profile-locks', `${id}.lock`);
  const other = spawnStation(exe, ['--profile', held.dir], {env: {...account, WSTX_SNTP_SERVERS: ''}, windowsHide: true});
  let otherOutput = ''; other.stdout.on('data', b => {otherOutput += b;}); other.stderr.on('data', b => {otherOutput += b;});
  t.after(async () => {if (other.exitCode === null && other.signalCode === null) {other.kill(); await once(other, 'exit');} await fs.rm(heldLock, {force: true});});
  const deadline = Date.now() + 10000;
  while (!otherOutput.includes(`WSTX listening ${held.origin}`)) {
    assert.ok(other.exitCode === null && Date.now() < deadline, 'concurrent run readiness failed: ' + otherOutput);
    await new Promise(r => setTimeout(r, 20));
  }
  const app = await server({}, ['--profile', (await profile('own', ownPort)).dir]); t.after(() => app.close());
  assert.equal((await request(`http://127.0.0.1:${ownPort}`)).body.profile_id, id);
});

// Test isolation: a station a suite starts runs on its profile's own settings, written where
// absent: PSK Reporter off, no UDP target, no radio discovery at start.
test('stations a suite starts hold the profile\'s own isolation settings', {timeout: 30000}, async t => {
  // The stations stop before their folders go: a running station holds them.
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-support-isolation-')), stops = [];
  t.after(async () => {for (const stop of stops.reverse()) await stop(); await fs.rm(root, {recursive: true, force: true});});
  const profile = async (dir, port) => {
    const id = crypto.randomUUID();
    await fs.mkdir(dir, {recursive: true});
    await fs.writeFile(path.join(dir, 'profile.json'), JSON.stringify({schema_version: 1, profile_id: id, revision: 0, ...settings(2), endpoint: {bind: `127.0.0.1:${port}`, origin: null}, connection_type: 'standard'}));
    return id;
  };
  const read = async (dir, name) => JSON.parse(await fs.readFile(path.join(dir, name), 'utf8'));
  const exists = file => fs.access(file).then(() => true, () => false);
  const [serverPort, directPort] = await ports(2);
  // A station started by server() on a new profile folder.
  const fresh = path.join(root, 'fresh'), id = await profile(fresh, serverPort);
  const app = await server({}, ['--profile', fresh]); stops.push(() => app.close());
  const origin = `http://127.0.0.1:${serverPort}`;
  const pskr = (await request(origin, '/pskr')).body;
  assert.deepEqual([pskr.enabled, pskr.state], [false, 'off'], JSON.stringify(pskr));
  assert.deepEqual((await request(origin, '/udp')).body.configuration.targets, []);
  assert.deepEqual(await read(fresh, 'radio-discovery.json'), {schema_version: 1, profile_id: id, at_start: false});
  assert.deepEqual(await read(fresh, 'pskr.json'), {schema_version: 2, profile_id: id, enabled: false, use: true});
  assert.deepEqual(await read(fresh, 'udp.json'), {schema_version: 1, profile_id: id, revision: 0, targets: []});
  // spawnStation directly, with a folder relative to its cwd: the files land below cwd only.
  const relative = `relative-${crypto.randomUUID()}`, below = path.join(root, relative);
  const directId = await profile(below, directPort);
  const direct = spawnStation(exe, ['--profile', relative], {cwd: root, env: stationEnv(), windowsHide: true});
  stops.push(async () => {if (direct.exitCode === null && direct.signalCode === null) {direct.kill(); await once(direct, 'exit');}});
  assert.deepEqual(await read(below, 'radio-discovery.json'), {schema_version: 1, profile_id: directId, at_start: false});
  assert.deepEqual(await read(below, 'pskr.json'), {schema_version: 2, profile_id: directId, enabled: false, use: true});
  assert.deepEqual(await read(below, 'udp.json'), {schema_version: 1, profile_id: directId, revision: 0, targets: []});
  assert.equal(await exists(path.resolve(relative)), false, 'nothing in the process folder');
  // A folder whose udp.json exists keeps its bytes; a folder without profile.json gets nothing.
  const kept = path.join(root, 'kept'); await profile(kept, directPort);
  const bytes = '{"schema_version":1, "kept":true}';
  await fs.writeFile(path.join(kept, 'udp.json'), bytes);
  isolateProfile(['--profile', kept]);
  assert.equal(await fs.readFile(path.join(kept, 'udp.json'), 'utf8'), bytes);
  assert.ok(await exists(path.join(kept, 'pskr.json')));
  const bare = path.join(root, 'bare'); await fs.mkdir(bare);
  isolateProfile(['--profile', bare]);
  assert.deepEqual(await fs.readdir(bare), []);
});
