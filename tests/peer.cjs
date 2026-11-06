'use strict';

// Heartbeats may interleave with a response. Keep one total deadline, and let the
// caller's oracle judge every other message rather than hiding unexpected input.
function contactEvent(value, bytes) {
  const keys = (v, list) => v && typeof v === 'object' && !Array.isArray(v) && Object.keys(v).sort().join(',') === [...list].sort().join(',');
  if (!keys(value, ['v', 'type', 'data']) || value.v !== 1) return false;
  if (value.type === 'contact.state') return bytes <= 192 && keys(value.data, ['profile_id', 'boot_id', 'contact_revision']);
  if (value.type === 'transmit.state') return bytes <= 1024 && keys(value.data, ['profile_id', 'boot_id', 'transmit_revision', 'changed']);
  if (value.type === 'recording.state') return bytes <= 1024 && keys(value.data, ['generation', 'source_id', 'job_id', 'state', 'import']);
  if (value.type === 'profile.state') return bytes <= 192 && keys(value.data, ['profile_id', 'boot_id', 'revision']);
  if (value.type === 'station.tick') return bytes <= 224 && keys(value.data, ['profile_id', 'boot_id', 'utc_ms', 'period_ms', 'transmitting', 'rx_level_db']);
  return false;
}
function receive(ws, milliseconds = 3000) {
  return new Promise((resolve, reject) => {
    const finish = (error, value) => {
      clearTimeout(timer);
      ws.off('message', onMessage); ws.off('error', onError); ws.off('close', onClose);
      if (error) reject(error); else resolve(value);
    };
    const onError = error => finish(error);
    const onClose = () => finish(new Error('Connection closed before response'));
    const onMessage = data => {
      let value;
      try { value = JSON.parse(String(data)); } catch (error) {finish(error); return;}
      if (value && typeof value === 'object' && !Array.isArray(value)
          && Object.keys(value).length === 2 && value.v === 1 && value.type === 'heartbeat') return;
      // WstxContact::ContactStateEvent/StationTickEvent WstxTransmit transmit.state and the pushed recording.state are unsolicited optional events of
      // a display-subscribed peer; like heartbeats they interleave with a response. Only
      // the exact versioned shapes within their byte bounds are skipped.
      if (contactEvent(value, Buffer.byteLength(String(data)))) return;
      finish(null, value);
    };
    const timer = setTimeout(() => finish(new Error('Message timeout')), milliseconds);
    timer.unref();
    ws.on('message', onMessage); ws.on('error', onError); ws.on('close', onClose);
  });
}
module.exports = {receive, contactEvent};
