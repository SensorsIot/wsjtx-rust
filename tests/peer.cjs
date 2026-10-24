'use strict';

// Heartbeats may interleave with a response. Keep one total deadline, and let the
// caller's oracle judge every other message rather than hiding unexpected input.
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
      finish(null, value);
    };
    const timer = setTimeout(() => finish(new Error('Message timeout')), milliseconds);
    timer.unref();
    ws.on('message', onMessage); ws.on('error', onError); ws.on('close', onClose);
  });
}
module.exports = {receive};
