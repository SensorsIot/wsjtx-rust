'use strict';
// The tests of the peer helper (peer.cjs).
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {EventEmitter} = require('node:events');
const {receive} = require('./peer.cjs');

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
