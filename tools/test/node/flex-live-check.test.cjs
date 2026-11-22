'use strict';
// The tests of the FLEX live check (flex-live-check.cjs) against the loopback emulator
// (flex-emulator.cjs) and plain socket stubs; no radio.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises'), os = require('node:os'), path = require('node:path');
const net = require('node:net');
const {once} = require('node:events');
const {randomUUID} = require('node:crypto');
const {FlexEmulator} = require('./flex-emulator.cjs');
const {run: liveCheck} = require('./flex-live-check.cjs');

// Timing: signal
test('the live check script decodes real FT8 through the real packet form with some loss and leaves nothing behind', {timeout: 120000}, async t => {
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
  const manifest = JSON.parse(await fs.readFile(path.join(__dirname, '..', '..', '..', 'fixtures', 'decoder', 'independent-vectors', 'manifest.json')));
  const expected = manifest.vectors.find(v => v.mode === 'ft8' && v.id === 'cq').expected_receive.text;
  assert.ok(report.texts.includes(expected), JSON.stringify(report.texts));
  // The vector starts 0.5 s into its period, which FT8 calls DT 0; arrival time may add a little.
  assert.ok(Math.abs(report.dt_seconds.median) < 0.3, JSON.stringify(report.dt_seconds));
  assert.equal(typeof report.arrival.jitter_mean_ms, 'number');
  assert.ok((await fs.readdir(path.join(out, 'windows'))).length > 0, 'the windows are saved for offline analysis');
  assert.doesNotMatch(emulator.log.map(e => e.command).join('\n'), /xmit|transmit/);
});

test('the live check stops when anyone holds the radio or nothing can be verified', {timeout: 60000}, async t => {
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

test('the live check waits for late replies and reads an 8-digit zero code', {timeout: 90000}, async t => {
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

test('the live check reports a slice left on the radio', {timeout: 60000}, async t => {
  const emulator = await new FlexEmulator({silent: true, keepOnDisconnect: true}).start();
  t.after(() => emulator.stop());
  const out = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-flex-check-test-'));
  t.after(() => fs.rm(out, {recursive: true, force: true}));
  const report = await liveCheck({address: `127.0.0.1:${emulator.port}`, seconds: 2, out, registerPort: emulator.udpPort});
  assert.equal(report.status, 'not_released', JSON.stringify(report.after));
});

test('the live check does not call a run clean when its closing look fails', {timeout: 60000}, async t => {
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

test('the live check reports the loss it saw', {timeout: 60000}, async t => {
  const emulator = await new FlexEmulator({silent: true, dropEvery: 8}).start();
  t.after(() => emulator.stop());
  const out = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-flex-check-test-'));
  t.after(() => fs.rm(out, {recursive: true, force: true}));
  const report = await liveCheck({address: `127.0.0.1:${emulator.port}`, seconds: 4, out, registerPort: emulator.udpPort});
  assert.equal(report.status, 'measured', JSON.stringify(report.after));
  assert.ok(Math.abs(report.loss_percent - 12.5) < 2, `loss ${report.loss_percent}`);
});
