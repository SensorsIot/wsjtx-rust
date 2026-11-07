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
const https = require('node:https'), dgram = require('node:dgram'), net = require('node:net');
const {once} = require('node:events');
const {randomUUID} = require('node:crypto');
const {gunzipSync} = require('node:zlib');
const selfsigned = require('selfsigned');
const {chromium} = require('playwright');
const {server, grant, loginPage, browserPort} = require('./support.cjs');
const {FlexEmulator, vita, daxPayload, FROZEN} = require('./flex-emulator.cjs');
const {run: liveCheck} = require('./flex-live-check.cjs');

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

async function station(t, {name, native = true, discovery, granted = true, radioAddress, registerPort}) {
  // A native station without an address or loopback discovery port would listen on the LAN.
  assert.ok(!native || discovery || (radioAddress && registerPort), 'a native test station needs loopback ports');
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-flex-'));
  t.after(() => fs.rm(dir, {recursive: true, force: true}));
  const port = await browserPort();
  const origin = `https://localhost:${port}`, id = randomUUID(), clientId = randomUUID(), token = randomUUID().replaceAll('-', '');
  const cert = await selfsigned.generate([{name: 'commonName', value: 'localhost'}], {days: 1, keySize: 2048, extensions: [{name: 'subjectAltName', altNames: [{type: 2, value: 'localhost'}]}]});
  await fs.writeFile(path.join(dir, 'cert.pem'), cert.cert); await fs.writeFile(path.join(dir, 'key.pem'), cert.private);
  const common = {profile_id: id, revision: 0, display_name: name, callsign: 'HB9BLA', locator: 'JN47AA', endpoint: {bind: `127.0.0.1:${port}`, origin},
    audio: {input_device: null, output_device: null}, control: {mode: 'disabled', endpoint: null, ptt: 'disabled'}};
  const document = native
    ? {schema_version: 2, ...common, connection_type: 'native_flex', native: {client_id: clientId, rx_antenna: 'ANT1', ...(radioAddress ? {radio_address: radioAddress} : {})}}
    : {schema_version: 1, ...common, connection_type: 'standard'};
  const text = JSON.stringify(document);
  await fs.writeFile(path.join(dir, 'profile.json'), text);
  const env = {WSTX_TLS_CERT: path.join(dir, 'cert.pem'), WSTX_TLS_KEY: path.join(dir, 'key.pem'), WSTX_TOKEN: token,
    ...(discovery ? {WSTX_FLEX_DISCOVERY: `127.0.0.1:${discovery}`} : {}),
    ...(registerPort ? {WSTX_FLEX_REGISTER_PORT: String(registerPort)} : {})};
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
  const emulator = await new FlexEmulator({discoveryPorts: ports, sliceOrder: [5, 2, 7, 0, 1, 3, 4, 6], daxStatusDelay: 300}).start();
  t.after(() => emulator.stop());
  const stations = await Promise.all(ports.map((discovery, i) => station(t, {name: `Native ${i + 1}`, discovery})));
  // Stations choosing a DAX channel together may have to separate first.
  const owned = await waitFor(async () => {
    const views = await Promise.all(stations.map(s => s.flex()));
    const slices = stations.map(s => emulator.slicesOf(s.clientId));
    return views.every(v => v.state === 'ready') && slices.every(o => o.length === 1) && new Set(slices.map(o => o[0].dax)).size === 4 && slices;
  }, async () => JSON.stringify(await Promise.all(stations.map(s => s.flex()))), 40000);
  for (const [i, s] of stations.entries()) {
    assert.equal(owned[i].length, 1, `${s.name} owns exactly one slice`);
    assert.equal(emulator.streamsOf(s.clientId).length, 1, `${s.name} owns exactly one stream`);
    const v = await s.flex();
    // The station's informational slice/stream facts equal the emulator's own records.
    assert.equal(v.slice.index, owned[i][0].index);
    assert.equal(v.slice.stream_id, emulator.streamsOf(s.clientId)[0]);
    assert.equal(v.radio.protocol, '1.4.0.0'); assert.equal(v.transmit, 'unsupported');
    assert.equal([...emulator.clients.values()].filter(c => c.clientId === s.clientId).length, 1, 'one connected client holds the identity');
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
  // Stations choosing a DAX channel together may have to separate first.
  const separated = () => waitFor(async () => { const [x, y] = await Promise.all([a.flex(), b.flex()]); return x.state === 'ready' && y.state === 'ready' && x.slice.dax_channel !== y.slice.dax_channel; }, 'two ready stations on separate channels', 30000);
  await separated();
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
  await separated();
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
  await separated();
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

test('TC-023-001 another model on the admitted API connects, with its announced facts shown', {timeout: 60000}, async t => {
  const port = await udpPort();
  const emulator = await new FlexEmulator({discoveryPorts: [port], model: 'FLEX-8400', serial: '0000-1111-6600-2222'}).start();
  t.after(() => emulator.stop());
  const s = await station(t, {name: 'Other model', discovery: port});
  const v = await state(s, 'ready');
  assert.equal(v.radio.model, 'FLEX-8400'); assert.equal(v.radio.serial, '0000-1111-6600-2222');
  assert.equal(v.radio.firmware, '4.1.3.39644');
});

test('TC-023-001 a saved address reaches a radio no announcement crosses, and the keep-alive holds its stream', {timeout: 60000}, async t => {
  const emulator = await new FlexEmulator({silent: true, needRegister: true, model: 'FLEX-8400', serial: '0000-1111-6600-2222'}).start();
  t.after(() => emulator.stop());
  const s = await station(t, {name: 'Routed', radioAddress: `127.0.0.1:${emulator.port}`, registerPort: emulator.udpPort});
  const v = await state(s, 'ready');
  assert.equal(v.radio.serial, '0000-1111-6600-2222', 'the radio told us itself');
  assert.equal(v.radio.model, 'FLEX-8400'); assert.equal(v.radio.firmware, '4.3.16.42034');
  assert.equal(emulator.slicesOf(s.clientId).length, 1);
  await waitFor(async () => (await s.flex()).packets.accepted > 50, 'the stream arrives only after the registration');
  const client = [...emulator.clients.values()][0];
  const own = emulator.registered.filter(r => r.port === client.udpPort);
  assert.ok(own.length >= 1, 'registered from the port the stream goes to');
  assert.doesNotMatch(emulator.log.map(e => e.command).join('\n'), /127\.0\.0\.1|\bip=/, 'no local address is ever told');
  const before = own.length;
  await waitFor(() => emulator.registered.filter(r => r.port === client.udpPort).length > before, 'the keep-alive repeats', 8000);
});

test('TC-023-001 the live check script decodes real FT8 through the real packet form with some loss and leaves nothing behind', {timeout: 120000}, async t => {
  const vectors = process.env.WSTX_DECODER_VECTORS;
  assert.ok(vectors, 'WSTX_DECODER_VECTORS names the verified vector cache');
  const emulator = await new FlexEmulator({silent: true, dropEvery: 64, periodWav: path.join(vectors, 'ft8-cq', '000000_000000.wav')}).start();
  t.after(() => emulator.stop());
  const out = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-flex-check-test-'));
  t.after(() => fs.rm(out, {recursive: true, force: true}));
  const report = await liveCheck({address: `127.0.0.1:${emulator.port}`, seconds: 40, out, registerPort: emulator.udpPort});
  assert.equal(report.status, 'measured', JSON.stringify(report));
  assert.deepEqual([report.before.clients, report.before.slices], [0, '']);
  assert.deepEqual([report.after.clients, report.after.slices], [0, ''], 'released at the end');
  assert.equal(report.packets.invalid, 0);
  assert.ok(Math.abs(report.loss_percent - 100 / 64) < 0.5, `loss ${report.loss_percent}`);
  assert.ok(report.received_ratio > 0.8, `received ${report.received_ratio}`);
  // Independent oracle: the vector's own manifest text, and a signal on the UTC period.
  const manifest = JSON.parse(await fs.readFile(path.join(__dirname, '..', 'fixtures', 'decoder', 'independent-vectors', 'manifest.json')));
  const expected = manifest.vectors.find(v => v.mode === 'ft8' && v.id === 'cq').expected_receive.text;
  assert.ok(report.texts.includes(expected), JSON.stringify(report.texts));
  // The vector starts 0.5 s into its period, which FT8 calls DT 0; arrival time may add a little.
  assert.ok(Math.abs(report.dt_seconds.median) < 0.3, JSON.stringify(report.dt_seconds));
  assert.equal(typeof report.arrival.jitter_mean_ms, 'number');
  assert.ok((await fs.readdir(path.join(out, 'windows'))).length > 0, 'the windows are saved for offline analysis');
  assert.doesNotMatch(emulator.log.map(e => e.command).join('\n'), /xmit|transmit/);
});

test('TC-023-002 the live check stops when anyone holds the radio or nothing can be verified', {timeout: 60000}, async t => {
  const out = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-flex-check-test-'));
  t.after(() => fs.rm(out, {recursive: true, force: true}));
  const check = async (options, prepare = () => {}) => {
    const emulator = await new FlexEmulator({silent: true, ...options}).start();
    t.after(() => emulator.stop());
    prepare(emulator);
    const report = await liveCheck({address: `127.0.0.1:${emulator.port}`, seconds: 1, out, registerPort: emulator.udpPort});
    assert.equal(emulator.connections, 1, 'only the plain look connected');
    assert.equal(emulator.log.filter(e => /^client gui|^slice create|^stream create/.test(e.command)).length, 0, 'it became no client and created nothing');
    return report;
  };
  assert.equal((await check({externalClients: [randomUUID()]})).status, 'occupied');
  assert.equal((await check({externalClients: [randomUUID()], replyFirst: true})).status, 'occupied', 'whatever the order of the replies');
  assert.equal((await check({}, e => e.createSlice(0, 'ANT1'))).status, 'occupied');
  assert.equal((await check({refuseList: true})).status, 'unverified');
});

test('TC-023-002 the live check waits for late replies and reads an 8-digit zero code', {timeout: 90000}, async t => {
  const out = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-flex-check-test-'));
  t.after(() => fs.rm(out, {recursive: true, force: true}));
  const late = async text => {
    let connections = 0;
    const stub = net.createServer(socket => {
      connections++; socket.on('error', () => {});
      socket.write('V1.4.0.0\nH00000001\n');
      socket.once('data', () => { socket.write('R1|00000000|\n'); setTimeout(() => socket.destroyed || socket.write(text), 3000); });
    }).listen(0, '127.0.0.1');
    await once(stub, 'listening');
    t.after(() => stub.close());
    const report = await liveCheck({address: `127.0.0.1:${stub.address().port}`, seconds: 1, out});
    assert.equal(connections, 1, 'only the plain look connected');
    return report;
  };
  assert.equal((await late('S0|client 0x00000002 connected client_id=x\nR2|00000000|\nR3|00000000|\n')).status, 'occupied');
  assert.equal((await late('')).status, 'unverified');
});

test('TC-023-002 the live check reports a slice left on the radio', {timeout: 60000}, async t => {
  const emulator = await new FlexEmulator({silent: true, keepOnDisconnect: true}).start();
  t.after(() => emulator.stop());
  const out = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-flex-check-test-'));
  t.after(() => fs.rm(out, {recursive: true, force: true}));
  const report = await liveCheck({address: `127.0.0.1:${emulator.port}`, seconds: 2, out, registerPort: emulator.udpPort});
  assert.equal(report.status, 'not_released', JSON.stringify(report.after));
});

test('TC-023-002 the live check does not call a run clean when its closing look fails', {timeout: 60000}, async t => {
  const emulator = await new FlexEmulator({silent: true}).start();
  t.after(() => emulator.stop());
  const out = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-flex-check-test-'));
  t.after(() => fs.rm(out, {recursive: true, force: true}));
  // The station never sends slice list, so this refusal reaches only the closing look.
  const refuse = setInterval(() => { if (emulator.slices.size) { emulator.refuseList = true; clearInterval(refuse); } }, 50);
  t.after(() => clearInterval(refuse));
  const report = await liveCheck({address: `127.0.0.1:${emulator.port}`, seconds: 2, out, registerPort: emulator.udpPort});
  assert.equal(report.after.verified, false);
  assert.equal(report.status, 'not_released');
});

test('TC-023-001 the live check reports the loss it saw', {timeout: 60000}, async t => {
  const emulator = await new FlexEmulator({silent: true, dropEvery: 8}).start();
  t.after(() => emulator.stop());
  const out = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-flex-check-test-'));
  t.after(() => fs.rm(out, {recursive: true, force: true}));
  const report = await liveCheck({address: `127.0.0.1:${emulator.port}`, seconds: 4, out, registerPort: emulator.udpPort});
  assert.equal(report.status, 'measured', JSON.stringify(report.after));
  assert.ok(Math.abs(report.loss_percent - 12.5) < 2, `loss ${report.loss_percent}`);
});

test('TC-023-001 a stall above 200 ms with packets missing opens a new epoch', {timeout: 60000}, async t => {
  const port = await udpPort();
  const emulator = await new FlexEmulator({discoveryPorts: [port], dropEvery: 2}).start();
  t.after(() => emulator.stop());
  const s = await station(t, {name: 'Stalled', discovery: port});
  await state(s, 'ready');
  const r0 = (await s.request('/receive')).body;
  assert.equal((await s.request('/receive/start', 'POST', {v: 1, profile_id: s.id, boot_id: r0.boot_id, generation: r0.generation, profile_revision: 0, mode: 'spectrum'})).status, 202);
  const running = await waitFor(async () => { const r = (await s.request('/receive')).body; return r.source?.next_frame > 12000 && r; }, 'receive runs');
  assert.equal(running.audio.loss_epochs, 0, 'known gaps alone open no epoch');
  emulator.pausedUntil = performance.now() + 400;
  const after = await waitFor(async () => { const r = (await s.request('/receive')).body; return r.audio.loss_epochs >= 1 && r; }, 'a new epoch after the stall', 5000);
  assert.equal(after.audio.last_loss, 'native_discontinuity');
});

test('TC-023-001 a selection is read back on a slow path from a radio that volunteers no tune status', {timeout: 60000}, async t => {
  const emulator = await new FlexEmulator({silent: true, latency: 130}).start();
  t.after(() => emulator.stop());
  const s = await station(t, {name: 'Quiet', radioAddress: `127.0.0.1:${emulator.port}`, registerPort: emulator.udpPort});
  await state(s, 'ready', 30000);
  const selected = await selectBand(s, '20m');
  assert.equal(selected.operation.result, 'success', JSON.stringify(selected.operation));
  assert.equal(selected.selection.origin, 'native_readback');
  assert.equal(emulator.slicesOf(s.clientId)[0].hz, FT8['20m']);
  assert.equal((await s.flex()).slice.frequency_hz, FT8['20m']);
});

// One packet in 60 behind later ones, for 4 s of about 750 packets: `lost` and `late` are what the
// reordering costs, and the timeline keeps its rate with no new epoch either way.
async function reorderedRun(t, name, reorderBy) {
  const port = await udpPort();
  const emulator = await new FlexEmulator({discoveryPorts: [port], reorderEvery: 60, reorderBy}).start();
  t.after(() => emulator.stop());
  const s = await station(t, {name, discovery: port});
  await state(s, 'ready');
  const r0 = (await s.request('/receive')).body;
  assert.equal((await s.request('/receive/start', 'POST', {v: 1, profile_id: s.id, boot_id: r0.boot_id, generation: r0.generation, profile_revision: 0, mode: 'spectrum'})).status, 202);
  const first = await waitFor(async () => { const r = (await s.request('/receive')).body; return r.source?.next_frame > 12000 && {at: Date.now(), frame: r.source.next_frame}; }, 'receive runs');
  await new Promise(r => setTimeout(r, 4000));
  const r1 = (await s.request('/receive')).body, packets = (await s.flex()).packets;
  assert.ok(packets.accepted > 500, JSON.stringify(packets));
  assert.equal(r1.audio.loss_epochs, 0, 'reordering opens no epoch');
  const rate = (r1.source.next_frame - first.frame) / ((Date.now() - first.at) / 1000);
  assert.ok(Math.abs(rate / 12000 - 1) < 0.1, `canonical frames/s ${rate}`);
  return packets;
}

test('TC-023-001 packets delayed within the depth are put back in order, not counted lost', {timeout: 60000}, async t => {
  const packets = await reorderedRun(t, 'Reordered', 4);
  assert.equal(packets.lost, 0, JSON.stringify(packets));
  assert.equal(packets.late, 0, JSON.stringify(packets));
});

test('TC-023-001 packets delayed past the depth count lost once and are dropped as late', {timeout: 60000}, async t => {
  const packets = await reorderedRun(t, 'Too late', 6);
  assert.ok(packets.late >= 10, JSON.stringify(packets));
  assert.ok(Math.abs(packets.lost - packets.late) <= 1, JSON.stringify(packets));
});

test('TC-023-001 lost packets keep the timeline and are counted, and a stall shows as jitter', {timeout: 60000}, async t => {
  const port = await udpPort();
  const emulator = await new FlexEmulator({discoveryPorts: [port], dropEvery: 4}).start();
  t.after(() => emulator.stop());
  const s = await station(t, {name: 'Lossy', discovery: port});
  await state(s, 'ready');
  const r0 = (await s.request('/receive')).body;
  assert.equal((await s.request('/receive/start', 'POST', {v: 1, profile_id: s.id, boot_id: r0.boot_id, generation: r0.generation, profile_revision: 0, mode: 'spectrum'})).status, 202);
  const first = await waitFor(async () => { const r = (await s.request('/receive')).body; return r.source?.next_frame > 12000 && {at: Date.now(), frame: r.source.next_frame, packets: (await s.flex()).packets}; }, 'receive runs');
  await new Promise(r => setTimeout(r, 5000));
  const r1 = (await s.request('/receive')).body, f = await s.flex();
  // One packet in four is missing and becomes silence, so time keeps its full rate.
  const lost = f.packets.lost - first.packets.lost, accepted = f.packets.accepted - first.packets.accepted;
  assert.ok(Math.abs(lost / (lost + accepted) - 0.25) < 0.03, `lost ${lost} accepted ${accepted}`);
  const rate = (r1.source.next_frame - first.frame) / ((Date.now() - first.at) / 1000);
  assert.ok(rate > 12000 * 0.9, `canonical frames/s ${rate}`);
  assert.equal(r1.audio.loss_epochs, 0, 'a known gap opens no new epoch');
  const quiet = f.arrival.jitter_max_ms;
  emulator.pausedUntil = performance.now() + 120;
  const stalled = await waitFor(async () => { const x = await s.flex(); return x.arrival.jitter_max_ms >= 90 && x; }, async () => `jitter ${JSON.stringify((await s.flex()).arrival)} before ${quiet}`, 5000);
  assert.ok(stalled.arrival.jitter_mean_ms < stalled.arrival.jitter_max_ms);
});

test('TC-023-003 a full radio on a saved address is refused visibly', {timeout: 60000}, async t => {
  const emulator = await new FlexEmulator({silent: true, maxGui: 0}).start();
  t.after(() => emulator.stop());
  const s = await station(t, {name: 'Full', radioAddress: `127.0.0.1:${emulator.port}`, registerPort: emulator.udpPort});
  const v = await failure(s, 'radio_refused');
  assert.equal(v.radio_code, '50000005');
  assert.equal(emulator.slices.size, 0);
});

test('TC-023-001 the VITA measurement is reported and belongs to its session', {timeout: 60000}, async t => {
  const port = await udpPort();
  let emulator = await new FlexEmulator({discoveryPorts: [port]}).start();
  t.after(() => emulator.stop());
  const s = await station(t, {name: 'Measured', discovery: port});
  await state(s, 'ready');
  const measured = await waitFor(async () => { const x = await s.flex(); return x.packets.accepted > 50 && x; }, 'packets');
  // The emulator stamps what the radio stamped, a frozen filler, so the offset shows it plainly.
  assert.equal(measured.vita.tsi, 1);
  assert.ok(Math.abs(measured.vita.host_minus_radio_ms - (Date.now() - FROZEN.integer * 1000)) < 5000, JSON.stringify(measured.vita));
  assert.equal(typeof measured.arrival.jitter_mean_ms, 'number'); assert.ok(measured.arrival.jitter_max_ms >= measured.arrival.jitter_mean_ms);
  // A new session whose own packets never arrive shows no measurement from the old one.
  await emulator.stop();
  emulator = await new FlexEmulator({discoveryPorts: [port]}).start();
  emulator.strangerOnly = true;
  await failure(s, 'transport_lost');
  const fresh = await state(s, 'ready', 30000);
  assert.deepEqual(fresh.vita, {tsi: null, host_minus_radio_ms: null});
  assert.deepEqual(fresh.arrival, {jitter_mean_ms: null, jitter_max_ms: null});
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
  assert.match(await nativePage.locator('#native-status').textContent(), /^Native FlexRadio ready .*FLEX-6600 4\.1\.3\.39644.*transmit unsupported$/);
  assert.equal(await standardPage.locator('#native-status').isHidden(), true);
  await nativePage.locator('#operating-radio').waitFor({state: 'attached'});
  // A native station with no receive job is offered Start, never told it lacks an audio input.
  const idleContext = await browser.newContext({ignoreHTTPSErrors: true, viewport: {width: 1280, height: 900}});
  const idlePage = await idleContext.newPage();
  await loginPage(idlePage, served[1].origin, served[1].token);
  await idlePage.locator('#exception-chips [data-chip=receive]').filter({hasText: 'Receive stopped'}).waitFor({timeout: 20000});
  assert.equal(await idlePage.locator('#exception-chips').filter({hasText: 'No audio input'}).count(), 0, 'a native profile needs no audio input');
  // The status line stands in the receive details, not in the top bar of the fixed screen.
  assert.equal(await nativePage.locator('#receive-details #native-status').count(), 1);
  assert.equal(await nativePage.locator('#station-bar #native-status').count(), 0);
  await nativePage.setViewportSize({width: 1366, height: 768});
  assert.equal(await nativePage.evaluate(() => document.documentElement.scrollHeight <= innerHeight), true, 'no page scroll at 1366x768');
  // The push alone reports a lost radio, visibly, without a request or a reload.
  await emulator.stop(); emulator.stop = async () => {};
  await nativePage.locator('#native-status[data-state="unavailable"], #native-status[data-state="discovering"]').waitFor({state: 'attached', timeout: 20000});
  await nativePage.locator('#exception-chips [data-chip=native]').waitFor({timeout: 20000});
  await nativePage.setViewportSize({width: 1280, height: 900});
  await nativePage.locator('#exception-chips [data-chip=native]').click();
  await nativePage.locator('#native-status').waitFor({state: 'visible', timeout: 10000});
  assert.equal(nativePage.polls + standardPage.polls, 0, 'no client request for the native status');
  assert.deepEqual([...standardPage.errors, ...nativePage.errors], []);
  // A lost station link is not shown as the radio's last state.
  await nativeOne.stop();
  await waitFor(async () => /status stale/.test(await nativePage.locator('#native-status').textContent()), 'stale native status');
  onlyOwnSlices(emulator);
});

test('TC-023-001 the emulator sends what a real FLEX-6600 sent', async () => {
  // Its encoder must reproduce the captured packet byte for byte, so the candidate is never
  // compared with an emulator that drifted from what the radio does.
  const real = Buffer.from((await fs.readFile(path.join(__dirname, '..', 'server', 'src', 'flex', 'dax_rx_6600.hex'), 'utf8')).trim(), 'hex');
  const packet = vita({type: 3, stream: 0x04000008, packetClass: 0x03e3, count: 0, time: FROZEN, payload: real.subarray(28)});
  assert.equal(packet.toString('hex'), real.toString('hex'));
  // 1 kHz at 24 kHz: sample 6 is the quarter period's peak, equal in both channels.
  const tone = daxPayload(7, 0.5, 0);
  assert.ok(Math.abs(tone.readFloatBE(6 * 8) - 0.5) < 1e-6); assert.equal(tone.readFloatBE(6 * 8), tone.readFloatBE(6 * 8 + 4));
});
