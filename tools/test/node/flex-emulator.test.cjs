'use strict';
// The test of the loopback FLEX emulator (flex-emulator.cjs) against a captured packet of a
// real FLEX-6600 (fixtures/flex/dax_rx_6600.hex).
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises'), path = require('node:path');
const {vita, daxPayload, FROZEN} = require('./flex-emulator.cjs');

test('the emulator sends what a real FLEX-6600 sent', async () => {
  // Its encoder must reproduce the captured packet byte for byte, so the candidate is never
  // compared with an emulator that drifted from what the radio does.
  const real = Buffer.from((await fs.readFile(path.join(__dirname, '..', '..', '..', 'fixtures', 'flex', 'dax_rx_6600.hex'), 'utf8')).trim(), 'hex');
  const packet = vita({type: 3, stream: 0x04000008, packetClass: 0x03e3, count: 0, time: FROZEN, payload: real.subarray(28)});
  assert.equal(packet.toString('hex'), real.toString('hex'));
  // 1 kHz at 24 kHz: sample 6 is the quarter period's peak, equal in both channels.
  const tone = daxPayload(7, 0.5, 0);
  assert.ok(Math.abs(tone.readFloatBE(6 * 8) - 0.5) < 1e-6); assert.equal(tone.readFloatBE(6 * 8), tone.readFloatBE(6 * 8 + 4));
});
