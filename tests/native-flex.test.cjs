'use strict';
// Cost 2, Windows PC: real candidate station servers with disposable HTTPS profiles,
// the independent loopback native-API emulator (tests/flex-emulator.cjs) and a real
// browser. No radio, SmartSDR/CAT/DAX application or audio device is used, and every native
// station listens for discovery only on its own loopback port, never on the LAN.
// Independent oracle: the emulator's own resource/ownership/command records and the
// canonical TC-023-001..003 expectations, never values computed by the candidate.
// Proves: FR-023; CL-013-01, CL-013-02, CL-013-03, CL-013-04, CL-013-05, CL-013-06; TC-023-001, TC-023-002, TC-023-003.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises'), os = require('node:os'), path = require('node:path');
const https = require('node:https'), dgram = require('node:dgram');
const {once} = require('node:events');
const {randomUUID} = require('node:crypto');
const {gunzipSync} = require('node:zlib');
const selfsigned = require('selfsigned');
const {chromium} = require('playwright');
const {server, grant, loginPage, browserPort} = require('./support.cjs');
const {FlexEmulator, vita, daxPayload} = require('./flex-emulator.cjs');

const FT8 = {'40m': 7074000, '30m': 10136000, '20m': 14074000, '17m': 18100000};
// Commands that could transmit or disturb other clients are never acceptable here.
const FORBIDDEN = /xmit|transmit|\bptt\b|\btx\b|txant|\btx=|client disconnect|start_persistence on|load_from/;

async function udpPort() {
  const s = dgram.createSocket('udp4'); s.bind(0, '127.0.0.1'); await once(s, 'listening');
  const {port} = s.address(); await new Promise(r => s.close(r)); return port;
}
async function waitFor(predicate, label, timeout = 20000) {
  const end = Date.now() + timeout;
  for (;;) {
    const value = await predicate();
    if (value) return value;
    if (Date.now() > end) throw new Error('timeout: ' + (typeof label === 'function' ? await label() : label));
    await new Promise(r => setTimeout(r, 100));
  }
}

async function station(t, {name, native = true, discovery, granted = true}) {
  // A native station without a loopback discovery port would listen on the LAN's UDP 4992.
  assert.ok(!native || discovery, 'a native test station needs its loopback discovery port');
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-flex-'));
  t.after(() => fs.rm(dir, {recursive: true, force: true}));
  const port = await browserPort();
  const origin = `https://localhost:${port}`, id = randomUUID(), clientId = randomUUID(), token = randomUUID().replaceAll('-', '');
  const cert = await selfsigned.generate([{name: 'commonName', value: 'localhost'}], {days: 1, keySize: 2048, extensions: [{name: 'subjectAltName', altNames: [{type: 2, value: 'localhost'}]}]});
  await fs.writeFile(path.join(dir, 'cert.pem'), cert.cert); await fs.writeFile(path.join(dir, 'key.pem'), cert.private);
  const common = {profile_id: id, revision: 0, display_name: name, callsign: 'HB9BLA', locator: 'JN47AA', endpoint: {bind: `127.0.0.1:${port}`, origin},
    audio: {input_device: null, output_device: null}, control: {mode: 'disabled', endpoint: null, ptt: 'disabled'}};
  const document = native
    ? {schema_version: 2, ...common, connection_type: 'native_flex', native: {client_id: clientId, rx_antenna: 'ANT1'}}
    : {schema_version: 1, ...common, connection_type: 'standard'};
  const text = JSON.stringify(document);
  await fs.writeFile(path.join(dir, 'profile.json'), text);
  const env = {WSTX_TLS_CERT: path.join(dir, 'cert.pem'), WSTX_TLS_KEY: path.join(dir, 'key.pem'), WSTX_TOKEN: token,
    ...(discovery ? {WSTX_FLEX_DISCOVERY: `127.0.0.1:${discovery}`} : {})};
  let app = await server(env, ['--profile', dir]);
  t.after(() => app.close());
  let cookie = '';
  const request = (route, method = 'GET', body, extra = {}) => new Promise((resolve, reject) => {
    const req = https.request(origin + route, {method, ca: cert.cert, agent: false, headers: {Origin: origin, ...(cookie ? {Cookie: cookie} : {}), ...(body === undefined ? {} : {'Content-Type': 'application/json'}), ...extra}}, res => {
      const chunks = []; res.on('data', b => chunks.push(b));
      res.on('end', () => { try { const raw = Buffer.concat(chunks), text = (res.headers['content-encoding'] === 'gzip' ? gunzipSync(raw) : raw).toString('utf8'); resolve({status: res.statusCode, headers: res.headers, text, body: text && (res.headers['content-type'] || '').startsWith('application/json') ? JSON.parse(text) : null}); } catch (error) { reject(error); } });
    });
    req.on('error', reject); if (body !== undefined) req.write(typeof body === 'string' ? body : JSON.stringify(body)); req.end();
  });
  let granted_ = null;
  const authorize = async () => { granted_ = await grant(origin, token, (route, method, body, extra) => request(route, method, body, extra)); cookie = granted_.cookie; return granted_; };
  // A process restart keeps the profile and its grant; the browser side proves it again.
  const restart = async () => { await app.close(); app = await server(env, ['--profile', dir]); cookie = await granted_.prove(); };
  const stop = () => app.close();
  if (granted) await authorize();
  const flex = async () => (await request('/native-flex')).body;
  return {name, dir, origin, id, clientId, token, cert, request, flex, text, native, authorize, restart, stop};
}
const state = async (s, wanted, timeout) => waitFor(async () => { const v = await s.flex(); return v?.state === wanted && v; }, async () => `${s.name} ${wanted}: ${JSON.stringify(await s.flex())}`, timeout);
const failure = async (s, code, timeout) => waitFor(async () => { const v = await s.flex(); return v?.error === code && v; }, async () => `${s.name} ${code}: ${JSON.stringify(await s.flex())}`, timeout);
const envelope = async s => { const v = (await s.request('/receive/selection')).body; return {v: 1, profile_id: v.profile_id, boot_id: v.boot_id}; };
async function selectBand(s, band) {
  const prior = (await s.request('/receive/selection')).body;
  const command_id = randomUUID();
  const ack = await s.request('/receive/select', 'POST', {v: 1, profile_id: s.id, boot_id: prior.boot_id, command_id, action: 'band', profile_revision: prior.profile_revision, generation: prior.generation, operating_revision: prior.operating_revision, band});
  assert.equal(ack.status, 202, `${s.name} select: ${ack.text} from ${JSON.stringify(prior)} now ${JSON.stringify((await s.request('/receive/selection')).body)}`);
  return waitFor(async () => { const v = (await s.request('/receive/selection')).body; return v.operation?.command_id === command_id && v.operation.result !== 'pending' && v; }, `${s.name} selection outcome`);
}
// Every slice command any client sent targeted a slice that client owned at that moment.
function onlyOwnSlices(emulator) {
  for (const e of emulator.log) if (e.target !== undefined) assert.equal(e.target, e.handle, `foreign slice command: ${JSON.stringify(e)}`);
  for (const e of emulator.log) assert.doesNotMatch(e.command, FORBIDDEN);
}

test('TC-023-001 four direct native stations route control, status and samples only to their own slice', {timeout: 120000}, async t => {
  const ports = await Promise.all([0, 1, 2, 3].map(udpPort));
  const emulator = await new FlexEmulator({discoveryPorts: ports, sliceOrder: [5, 2, 7, 0, 1, 3, 4, 6]}).start();
  t.after(() => emulator.stop());
  const stations = await Promise.all(ports.map((discovery, i) => station(t, {name: `Native ${i + 1}`, discovery})));
  for (const s of stations) await state(s, 'ready');
  const owned = stations.map(s => emulator.slicesOf(s.clientId));
  for (const [i, s] of stations.entries()) {
    assert.equal(owned[i].length, 1, `${s.name} owns exactly one slice`);
    assert.equal(emulator.streamsOf(s.clientId).length, 1, `${s.name} owns exactly one stream`);
    const v = await s.flex();
    // The station's informational slice/stream facts equal the emulator's own records.
    assert.equal(v.slice.index, owned[i][0].index);
    assert.equal(v.slice.stream_id, emulator.streamsOf(s.clientId)[0]);
    assert.equal(v.radio.protocol, '1.4.0.0'); assert.equal(v.transmit, 'unsupported');
    assert.equal(emulator.log.filter(e => e.command === `client gui ${s.clientId}`).length, 1);
  }
  assert.equal(new Set(owned.map(o => o[0].index)).size, 4);
  assert.equal(new Set(owned.map(o => o[0].dax)).size, 4, 'each station its own DAX channel');
  // Samples: each station's accepted channel-0 peak is its own slice's tone amplitude;
  // the loud 0.95 interference carrying other clients' stream IDs is never accepted.
  for (const [i, s] of stations.entries()) {
    const v = await waitFor(async () => { const v = await s.flex(); return v.packets.accepted > 100 && v.packets.foreign > 5 && v; }, `${s.name} packets`);
    assert.ok(Math.abs(v.last_peak - owned[i][0].amplitude) < 1e-4, `${s.name} peak ${v.last_peak} expected ${owned[i][0].amplitude}`);
    assert.equal(v.packets.invalid, 0);
  }
  // Concurrent station operations through the shared selection path tune only own slices.
  const bands = Object.keys(FT8);
  const outcomes = await Promise.all(stations.map((s, i) => selectBand(s, bands[i])));
  for (const [i, s] of stations.entries()) {
    assert.equal(outcomes[i].operation.result, 'success', JSON.stringify(outcomes[i].operation));
    assert.equal(outcomes[i].control, 'native'); assert.equal(outcomes[i].selection.origin, 'native_readback');
    assert.equal(emulator.slices.get(owned[i][0].index).hz, FT8[bands[i]], `${s.name} slice frequency`);
    assert.equal(emulator.slices.get(owned[i][0].index).owner, emulator.ownerOf(s.clientId));
    assert.equal((await s.flex()).slice.frequency_hz, FT8[bands[i]]);
  }
  // Read first: selecting the same band again finds the slice there and writes nothing.
  const writes = () => emulator.log.filter(e => /^slice (tune|set) /.test(e.command)).length;
  const before = writes();
  const again = await selectBand(stations[0], bands[0]);
  assert.equal(again.operation.result, 'success', JSON.stringify(again.operation));
  assert.equal(writes(), before, 'no slice write when the status already matches');
  // A radio that accepts the tune but never reports the frequency: the read-back decides.
  emulator.ignoreTune = true;
  const unread = await selectBand(stations[0], bands[1]);
  assert.equal(unread.operation.result, 'failed'); assert.equal(unread.operation.error, 'radio_timeout');
  assert.notEqual(emulator.slices.get(owned[0][0].index).hz, FT8[bands[1]]);
  emulator.ignoreTune = false;
  assert.equal((await selectBand(stations[0], bands[0])).operation.result, 'success');
  // The restarted live receive consumes the native stream through the shared receive owner.
  for (const s of stations) {
    const first = (await s.request('/receive')).body;
    assert.equal(first.audio.device_id, 'native_flex');
    await waitFor(async () => { const r = (await s.request('/receive')).body; return r.job?.state === 'running' && r.source?.next_frame > (first.source?.next_frame ?? 0) + 12000; }, async () => `${s.name} receive frames: ${JSON.stringify(first.source)} now ${JSON.stringify((await s.request('/receive')).body)} ${JSON.stringify(await s.flex())}`);
    // The packet arrival time anchors the epoch, so FT8 periods fall on UTC.
    const {clock, source} = (await s.request('/receive')).body;
    assert.equal(clock.correlated, true, JSON.stringify(clock));
    const newest = Date.parse(clock.utc_anchor) + (source.next_frame - clock.canonical_anchor_frame) / 12;
    assert.ok(Math.abs(newest - Date.now()) < 2000, `anchor ${clock.utc_anchor} frame ${source.next_frame}`);
  }
  // Only the radio's address counts: the own stream ID from another host is never accepted.
  emulator.strangerOnly = true;
  await new Promise(r => setTimeout(r, 500));
  const held = await stations[0].flex();
  await new Promise(r => setTimeout(r, 1000));
  const later = await stations[0].flex();
  assert.equal(later.packets.accepted, held.packets.accepted, 'a stranger cannot feed the station');
  assert.ok(later.packets.foreign > held.packets.foreign + 50);
  emulator.strangerOnly = false;
  onlyOwnSlices(emulator);
});

test('TC-023-002 persisted intent reconciles restarted radios, changed handles and occupied or ambiguous resources', {timeout: 120000}, async t => {
  const ports = await Promise.all([0, 1].map(udpPort));
  let emulator = await new FlexEmulator({discoveryPorts: ports}).start();
  t.after(() => emulator.stop());
  const [a, b] = await Promise.all(ports.map((discovery, i) => station(t, {name: `Native ${'AB'[i]}`, discovery})));
  await state(a, 'ready'); await state(b, 'ready');
  const before = {a: await a.flex(), b: await b.flex()};
  // A's receive job runs through the restart.
  const running = (await a.request('/receive')).body;
  const started = await a.request('/receive/start', 'POST', {v: 1, profile_id: a.id, boot_id: running.boot_id, generation: running.generation, profile_revision: 0, mode: 'spectrum'});
  assert.equal(started.status, 202, started.text);
  const firstFrames = await waitFor(async () => { const r = (await a.request('/receive')).body; return r.source?.next_frame > 12000 && r; }, async () => `receive before the restart: ${JSON.stringify((await a.request('/receive')).body)} ${JSON.stringify(await a.flex())}`);
  const oldStreams = [before.a.slice.stream_id, before.b.slice.stream_id];
  const restart = async options => {
    await emulator.stop();
    emulator = await new FlexEmulator({discoveryPorts: ports, ...options}).start();
  };
  // Radio restart: new handles, reversed slice indices, new stream IDs, old IDs replayed.
  await restart({handleBase: 0x7a000000, sliceOrder: [7, 6, 5, 4, 3, 2, 1, 0], streamBase: 0x08000000, staleStreams: oldStreams});
  await failure(a, 'transport_lost'); await failure(b, 'transport_lost');
  await waitFor(async () => (await a.request('/receive')).body.audio.state === 'unavailable', 'the running job shows its input unavailable');
  await state(a, 'ready', 30000); await state(b, 'ready', 30000);
  for (const s of [a, b]) {
    const v = await s.flex(), own = emulator.slicesOf(s.clientId);
    assert.equal(own.length, 1); assert.equal(v.slice.index, own[0].index);
    assert.ok(v.session > before[s === a ? 'a' : 'b'].session, 'a new session number');
    assert.ok(!oldStreams.includes(v.slice.stream_id), 'a stale stream ID is never authority');
    const later = await waitFor(async () => { const x = await s.flex(); return x.packets.accepted > before[s === a ? 'a' : 'b'].packets.accepted + 100 && x; }, 'new packets');
    assert.ok(Math.abs(later.last_peak - own[0].amplitude) < 1e-4, `${s.name} reconciled to its own new slice`);
  }
  assert.notEqual((await a.flex()).slice.index, before.a.slice.index);
  onlyOwnSlices(emulator);
  // The operator's job continued by itself on a new source epoch of the new session.
  const resumed = await waitFor(async () => { const r = (await a.request('/receive')).body; return r.job?.state === 'running' && r.audio.state === 'running' && r.source && r.source.id !== firstFrames.source.id && r.source.next_frame > 12000 && r; }, async () => `job after the restart: ${JSON.stringify((await a.request('/receive')).body)}`);
  assert.equal(resumed.job.mode, 'spectrum');
  assert.ok(resumed.audio.loss_epochs >= 1, 'the gap is counted'); assert.equal(resumed.audio.last_loss, 'native_discontinuity');
  // Occupied identity: A's saved client identity is already connected elsewhere.
  await restart({externalClients: [a.clientId]});
  const occupied = await failure(a, 'client_identity_in_use', 30000);
  assert.equal(occupied.state, 'conflict');
  await state(b, 'ready', 30000);
  await new Promise(r => setTimeout(r, 1500));
  assert.equal(emulator.log.filter(e => e.command === `client gui ${a.clientId}`).length, 0, 'no takeover registration');
  assert.equal(emulator.slicesOf(a.clientId).length, 0);
  emulator.removeExternal(a.clientId);
  await state(a, 'ready', 30000);
  onlyOwnSlices(emulator);
  // The same when the radio answers the subscription before it lists the clients.
  await restart({externalClients: [a.clientId], replyFirst: true});
  await failure(a, 'client_identity_in_use', 30000);
  assert.equal(emulator.log.filter(e => e.command === `client gui ${a.clientId}`).length, 0, 'no takeover registration');
  emulator.removeExternal(a.clientId);
  await state(a, 'ready', 30000);
  // Ambiguous ownership: a slice is already attributed to A's fresh handle.
  await restart({preassignOnGui: a.clientId});
  assert.equal((await failure(a, 'ownership_ambiguous', 30000)).state, 'conflict');
  await state(b, 'ready', 30000);
  for (const e of emulator.log.filter(e => e.clientId?.toLowerCase() === a.clientId.toLowerCase())) {
    assert.doesNotMatch(e.command, /^slice |^stream /, 'the unprovable slice is left untouched');
  }
  onlyOwnSlices(emulator);
  // Next available: a radio without a free client slot is passed over for one that has one.
  await restart({announceClients: 0});
  const second = await new FlexEmulator({discoveryPorts: ports, serial: '9999-0000-0000-0000', handleBase: 0x20000000}).start();
  t.after(() => second.stop());
  await state(a, 'ready', 30000); await state(b, 'ready', 30000);
  assert.equal(emulator.connections, 0, 'no connection to the full radio');
  assert.equal(second.slicesOf(a.clientId).length, 1);
  assert.equal((await a.flex()).radio.serial, '9999-0000-0000-0000');
  onlyOwnSlices(second);
  await second.stop(); second.stop = async () => {};
  // Nothing announced: nothing is guessed and no connection is made.
  await restart({silent: true});
  await failure(a, 'radio_not_found', 30000); await failure(b, 'radio_not_found', 30000);
  assert.equal(emulator.connections, 0);
  // Without a session a new receive start is refused, visibly.
  const idle = (await b.request('/receive')).body;
  const noSession = await b.request('/receive/start', 'POST', {v: 1, profile_id: b.id, boot_id: idle.boot_id, generation: idle.generation, profile_revision: 0, mode: 'spectrum'});
  assert.equal(noSession.body.error.code, 'radio_unavailable', noSession.text);
  // The persisted intent is unchanged and holds no radio identity, index, handle or stream ID.
  for (const s of [a, b]) {
    const saved = await fs.readFile(path.join(s.dir, 'profile.json'), 'utf8');
    assert.equal(saved, s.text);
    assert.deepEqual(Object.keys(JSON.parse(saved).native).sort(), ['client_id', 'rx_antenna']);
    assert.doesNotMatch(saved, /serial/);
  }
});

test('TC-023-002 a new session goes back to the selected frequency', {timeout: 60000}, async t => {
  const port = await udpPort();
  let emulator = await new FlexEmulator({discoveryPorts: [port]}).start();
  t.after(() => emulator.stop());
  const s = await station(t, {name: 'Retune', discovery: port});
  await state(s, 'ready');
  assert.equal((await selectBand(s, '40m')).operation.result, 'success');
  await emulator.stop();
  emulator = await new FlexEmulator({discoveryPorts: [port], handleBase: 0x30000000}).start();
  await failure(s, 'transport_lost');
  await state(s, 'ready', 30000);
  assert.equal(emulator.slicesOf(s.clientId)[0].hz, FT8['40m'], 'the radio is where the selection says');
  assert.equal((await s.flex()).slice.frequency_hz, FT8['40m']);
  assert.equal((await s.request('/receive/selection')).body.selection.origin, 'native_readback');
});

test('TC-023-001 stations racing for one DAX channel end on different channels', {timeout: 60000}, async t => {
  const ports = await Promise.all([0, 1].map(udpPort));
  const emulator = await new FlexEmulator({discoveryPorts: ports, daxStatusDelay: 300}).start();
  t.after(() => emulator.stop());
  const [a, b] = await Promise.all(ports.map((discovery, i) => station(t, {name: `Race ${i}`, discovery})));
  const settled = () => waitFor(async () => { const [x, y] = await Promise.all([a.flex(), b.flex()]); return x.state === 'ready' && y.state === 'ready' && [x, y]; }, async () => JSON.stringify([await a.flex(), await b.flex()]), 30000);
  await settled();
  await new Promise(r => setTimeout(r, 1500));
  const [x, y] = await settled();
  assert.notEqual(x.slice.dax_channel, y.slice.dax_channel);
  assert.deepEqual(new Set(emulator.slicesOf(a.clientId).concat(emulator.slicesOf(b.clientId)).map(v => v.dax)).size, 2);
});

test('CL-045-02 a native station resumes its receive at startup, waiting a bounded time for its session', {timeout: 150000}, async t => {
  const port = await udpPort();
  let emulator = await new FlexEmulator({discoveryPorts: [port]}).start();
  t.after(() => emulator.stop());
  const s = await station(t, {name: 'Resume', discovery: port});
  await state(s, 'ready');
  const resume = async () => (await s.request('/receive/startup')).body.resume;
  const resumed = wanted => waitFor(async () => (await resume()).state === wanted, async () => `resume ${wanted}: ${JSON.stringify(await resume())}`, 40000);
  // A choice without a band waits for the session too.
  const before = (await s.request('/receive')).body;
  assert.equal((await s.request('/receive/start', 'POST', {v: 1, profile_id: s.id, boot_id: before.boot_id, generation: before.generation, profile_revision: 0, mode: 'spectrum'})).status, 202);
  await s.restart();
  await resumed('started');
  assert.equal((await s.request('/receive')).body.job.mode, 'spectrum');
  // A band choice tunes the new slice through the selection.
  await state(s, 'ready');
  assert.equal((await selectBand(s, '40m')).operation.result, 'success');
  await s.restart();
  await resumed('started');
  assert.equal(emulator.slicesOf(s.clientId)[0].hz, FT8['40m']);
  // No radio: it fails after the 20 s of the clause, not twice that.
  await s.stop();
  await emulator.stop();
  emulator = await new FlexEmulator({discoveryPorts: [port], silent: true}).start();
  const begun = Date.now();
  await s.restart();
  await resumed('failed');
  assert.equal((await resume()).error, 'radio_unavailable');
  assert.ok(Date.now() - begun < 30000, `resume took ${Date.now() - begun} ms`);
  assert.ok(Date.now() - begun > 15000, `resume took ${Date.now() - begun} ms`);
});

test('TC-023-002 a native station reaches no radio without a grant and leaves it when the grant goes', {timeout: 60000}, async t => {
  const port = await udpPort();
  const emulator = await new FlexEmulator({discoveryPorts: [port]}).start();
  t.after(() => emulator.stop());
  const s = await station(t, {name: 'Ungranted', discovery: port, granted: false});
  await new Promise(r => setTimeout(r, 3000));
  assert.equal(emulator.connections, 0, 'no connection before a grant');
  const {scope} = await s.authorize();
  await state(s, 'ready');
  assert.equal(emulator.slicesOf(s.clientId).length, 1);
  const revoked = await s.request('/authorization/v1/revoke', 'POST', {version: 1, operation_id: randomUUID(), scope, all_for_radio: true});
  assert.equal(revoked.status, 200, revoked.text);
  await waitFor(() => emulator.ownerOf(s.clientId) === null, 'the session left the radio');
  assert.equal(emulator.slices.size, 0);
});

test('TC-023-003 capacity, incompatible API and mixed standard/native profiles through the same browser', {timeout: 120000}, async t => {
  // Insufficient slices: two of three stations are served; the third is told, nobody loses.
  const ports = await Promise.all([0, 1, 2].map(udpPort));
  const emulator = await new FlexEmulator({discoveryPorts: ports, maxSlices: 2}).start();
  t.after(() => emulator.stop());
  const three = await Promise.all(ports.map((discovery, i) => station(t, {name: `Capacity ${i + 1}`, discovery})));
  const settled = await waitFor(async () => { const v = await Promise.all(three.map(s => s.flex())); return v.filter(x => x.state === 'ready').length === 2 && v.some(x => x.error === 'capacity_slices') && v; }, async () => JSON.stringify(await Promise.all(three.map(s => s.flex()))), 40000);
  const served = three.filter((s, i) => settled[i].state === 'ready');
  const held = served.map(s => JSON.stringify(emulator.slicesOf(s.clientId)));
  await new Promise(r => setTimeout(r, 3000));
  assert.deepEqual(served.map(s => JSON.stringify(emulator.slicesOf(s.clientId))), held, 'existing ownership preserved');
  assert.equal(emulator.slices.size, 2);
  onlyOwnSlices(emulator);

  // No free GUI client: refused from discovery facts, before any connection.
  const busyPort = await udpPort();
  const busy = await new FlexEmulator({discoveryPorts: [busyPort], announceClients: 0}).start();
  t.after(() => busy.stop());
  const crowded = await station(t, {name: 'No client slot', discovery: busyPort});
  await failure(crowded, 'capacity_clients');
  assert.equal(busy.connections, 0);

  // Incompatible API version: refused before any command is sent.
  const oldPort = await udpPort();
  const newer = await new FlexEmulator({discoveryPorts: [oldPort], protocol: '1.5.0.0'}).start();
  t.after(() => newer.stop());
  const mismatch = await station(t, {name: 'Version mismatch', discovery: oldPort});
  const refusedApi = await failure(mismatch, 'incompatible_api');
  assert.equal(refusedApi.radio.protocol, '1.5.0.0');
  assert.ok(newer.connections >= 1); assert.equal(newer.log.length, 0, 'zero commands to an unadmitted API');

  // Mixed set: a standard station keeps its own path and never touches the native API.
  const standardPort = await udpPort();
  const heard = await new FlexEmulator({discoveryPorts: [standardPort]}).start();
  t.after(() => heard.stop());
  const standard = await station(t, {name: 'Standard', native: false, discovery: standardPort});
  await new Promise(r => setTimeout(r, 2000));
  assert.equal(heard.connections, 0, 'a standard station ignores an announced radio');
  const nativeOne = served[0];
  assert.equal((await standard.request('/native-flex')).status, 404);
  assert.equal((await standard.request('/profile')).body.connection_type, 'standard');
  assert.equal((await nativeOne.request('/profile')).body.connection_type, 'native_flex');
  assert.equal((await standard.request('/receive/selection')).body.control, 'manual');
  assert.equal((await nativeOne.request('/receive/selection')).body.control, 'native');
  const live = (await standard.request('/receive')).body;
  const refused = await standard.request('/receive/start', 'POST', {v: 1, profile_id: standard.id, boot_id: live.boot_id, generation: live.generation, profile_revision: 0, mode: 'ft8'});
  assert.equal(refused.body.error.code, 'audio_unconfigured', 'standard path unchanged');
  // Safety is the server's one transmit owner on both paths: the same answers, and no transmit
  // command reaches the radio (checked by onlyOwnSlices below).
  const safety = async s => {
    const contact = (await s.request('/contact')).body;
    const base = {...await envelope(s), contact_revision: contact.contact_revision};
    const enable = await s.request('/contact/command', 'POST', {...base, command_id: randomUUID(), action: 'enable_tx', enabled: true, safety_revision: null});
    const abort = await s.request('/contact/command', 'POST', {...base, command_id: randomUUID(), action: 'abort'});
    const halt = await s.request('/transmit/halt', 'POST', {...await envelope(s), command_id: randomUUID()});
    const tx = (await s.request('/transmit')).body.transmit;
    return {capability: tx.capability, arm_state: tx.arm_state, enable: [enable.status, enable.body?.error?.code ?? enable.body?.refusal ?? null], abort: abort.status, halt: [halt.status, halt.body?.halt_state]};
  };
  const onStandard = await safety(standard);
  assert.equal(onStandard.capability, 'unsupported');
  assert.deepEqual(await safety(nativeOne), onStandard);
  const nativeLive = (await nativeOne.request('/receive')).body;
  const started = await nativeOne.request('/receive/start', 'POST', {v: 1, profile_id: nativeOne.id, boot_id: nativeLive.boot_id, generation: nativeLive.generation, profile_revision: 0, mode: 'spectrum'});
  assert.equal(started.status, 202, started.text);
  // Native settings keep the standard device/CAT selections empty.
  const profile = (await nativeOne.request('/profile')).body;
  const bad = await nativeOne.request('/profile', 'PUT', {profile_id: nativeOne.id, revision: profile.revision, settings: {...profile.settings, audio: {input_device: 'X', output_device: null}}});
  assert.equal(bad.status, 400); assert.equal(bad.body.error.field, 'audio.input_device');
  const cat = await nativeOne.request('/profile', 'PUT', {profile_id: nativeOne.id, revision: profile.revision, settings: {...profile.settings, control: {mode: 'cat', endpoint: 'icom7300://COM3?baud=9600&radio=94&controller=e0', ptt: 'disabled'}}});
  assert.equal(cat.status, 400); assert.equal(cat.body.error.field, 'control.mode');
  const detect = await nativeOne.request('/radio/detect', 'POST', {...await envelope(nativeOne), keying_inhibit_confirmed: true});
  assert.equal(detect.status, 400, detect.text); assert.equal(detect.body.error.code, 'invalid_request');
  assert.equal(await fs.readFile(path.join(nativeOne.dir, 'profile.json'), 'utf8'), nativeOne.text, 'nothing changed the native profile');

  // The same browser presents both through the shared station UI.
  const browser = await chromium.launch(); t.after(() => browser.close());
  const pages = [];
  for (const s of [standard, nativeOne]) {
    const context = await browser.newContext({ignoreHTTPSErrors: true, viewport: {width: 1280, height: 900}});
    const page = await context.newPage(); page.errors = []; page.on('pageerror', e => page.errors.push(e.message));
    page.polls = 0; page.on('request', r => { if (r.url().includes('/native-flex')) page.polls++; });
    await loginPage(page, s.origin, s.token); pages.push(page);
  }
  const [standardPage, nativePage] = pages;
  assert.equal(await standardPage.locator('#settings select:not([id])').inputValue(), 'standard');
  assert.equal(await nativePage.locator('#settings select:not([id])').inputValue(), 'native_flex');
  await nativePage.locator('#native-status[data-state="ready"]').waitFor({state: 'attached', timeout: 20000});
  assert.match(await nativePage.locator('#native-status').textContent(), /^Native FlexRadio ready .*FLEX-6600.*transmit unsupported$/);
  assert.equal(await standardPage.locator('#native-status').isHidden(), true);
  await nativePage.locator('#operating-radio').waitFor({state: 'attached'});
  // The push alone reports a lost radio, visibly, without a request or a reload.
  await emulator.stop(); emulator.stop = async () => {};
  await nativePage.locator('#native-status[data-state="unavailable"], #native-status[data-state="discovering"]').waitFor({state: 'attached', timeout: 20000});
  await nativePage.locator('#exception-chips [data-chip=native]').waitFor({timeout: 20000});
  assert.equal(await nativePage.locator('#exception-chips').filter({hasText: 'No audio input'}).count(), 0, 'a native profile needs no audio input');
  assert.equal(nativePage.polls + standardPage.polls, 0, 'no client request for the native status');
  assert.deepEqual([...standardPage.errors, ...nativePage.errors], []);
  // A lost station link is not shown as the radio's last state.
  await nativeOne.stop();
  await waitFor(async () => /status stale/.test(await nativePage.locator('#native-status').textContent()), 'stale native status');
  onlyOwnSlices(emulator);
});

test('TC-023-001 emulator encoder reproduces the independent narrow48 preparation vector', () => {
  // The emulator's VITA encoder is checked against the pinned hand-authored bytes, so the
  // candidate is never compared with an emulator that drifted from the fixture truth.
  const payload = Buffer.from('3f000000bf0000003f800000bf800000', 'hex');
  const packet = vita({type: 1, stream: 0x81000001, packetClass: 0x03e4, count: 15, integer: 1, payload});
  assert.equal(packet.toString('hex'), '18ef000b8100000100001c2d534c03e40000000100000000000000003f000000bf0000003f800000bf800000');
  assert.equal(daxPayload(2, 0.5, 12).readFloatBE(0), 0.5);
});
