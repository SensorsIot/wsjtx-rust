'use strict';
const {spawn} = require('node:child_process');
const {once} = require('node:events');
const net = require('node:net');
const path = require('node:path');
const fs = require('node:fs');
const {performance} = require('node:perf_hooks');

async function server(env = {}) {
  const exe = process.env.WSTX_TEST_EXE || path.resolve(process.env.CARGO_TARGET_DIR || 'target', 'debug', process.platform === 'win32' ? 'wstx-rust.exe' : 'wstx-rust');
  if (!fs.existsSync(exe)) throw new Error(`Missing candidate ${exe}; run cargo build --locked`);
  const clean = {...process.env};
  for (const key of Object.keys(clean)) if (key.startsWith('WSTX_')) delete clean[key];
  const child = spawn(exe, [], {env: {...clean, WSTX_BIND: '127.0.0.1:0', ...env}, windowsHide: true});
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
  function forward(source, destination, direction) {
    let pendingBytes = 0;
    source.on('data', data => {
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
          } else if (!destination.destroyed) destination.write(part);
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
  listener.listen(0, '127.0.0.1'); await once(listener, 'listening');
  return {port: listener.address().port, counters, target,
    cut() {enabled = false; for (const socket of sockets) socket.destroy();},
    restore() {enabled = true;},
    async close() {enabled = false; for (const socket of sockets) socket.destroy(); for (const timer of timers) clearTimeout(timer); listener.close(); await once(listener, 'close');}
  };
}
module.exports = {server, link};
