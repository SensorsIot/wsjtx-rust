'use strict';
// Independent local emulator of the FR-023 native FlexRadio wire subset (TC-023-001..003).
// Written from the SmartSDR TCP/IP API wiki (command/reply/status/handle/version lines,
// slice/stream/client commands) and the VITA-49 field layout recorded in
// WstxProductScope::NativeFlexWireSubset; it shares no code with the Rust candidate.
// Loopback only: it announces by unicast to the test's own ports, never broadcasts and never
// contacts a real radio.
const net = require('node:net');
const dgram = require('node:dgram');
const {once} = require('node:events');

const OUI = 0x001c2d, INFO = 0x534c, DAX48 = 0x03e4, DISCOVERY = 0xffff;

// VITA-49 header: type 31..28, C 27, T 26, TSI 23..22, TSF 21..20, count 19..16, words 15..0.
function vita({type, stream, packetClass, count = 0, integer = 0, payload}) {
  const tsi = type === 1 ? 3 : 0, tsf = type === 1 ? 2 : 0;
  const preamble = 4 + 4 + 8 + (tsi ? 4 : 0) + (tsf ? 8 : 0);
  const padded = Math.ceil(payload.length / 4) * 4, out = Buffer.alloc(preamble + padded);
  const words = out.length / 4;
  out.writeUInt32BE(((type << 28) | (1 << 27) | (tsi << 22) | (tsf << 20) | ((count & 15) << 16) | words) >>> 0, 0);
  out.writeUInt32BE(stream >>> 0, 4);
  out.writeUInt32BE(OUI, 8);
  out.writeUInt32BE(((INFO << 16) | packetClass) >>> 0, 12);
  let at = 16;
  if (tsi) { out.writeUInt32BE(integer >>> 0, at); at += 4; }
  if (tsf) { out.writeUInt32BE(0, at); out.writeUInt32BE(0, at + 4); at += 8; }
  payload.copy(out, at);
  return out;
}
// Stereo big-endian float32 frames; channel 0 carries the slice's tone, channel 1 silence.
function daxPayload(frames, amplitude, phase) {
  const out = Buffer.alloc(frames * 8);
  for (let i = 0; i < frames; i++) {
    out.writeFloatBE(amplitude * Math.sin(2 * Math.PI * 1000 * (phase + i) / 48000), i * 8);
    out.writeFloatBE(0, i * 8 + 4);
  }
  return out;
}
const hex = n => (n >>> 0).toString(16).toUpperCase().padStart(8, '0');
const mhz = hz => `${Math.floor(hz / 1e6)}.${String(hz % 1e6).padStart(6, '0')}`;
function hertz(text) {
  const m = /^(\d{1,5})(?:\.(\d{1,6}))?$/.exec(text);
  return m ? Number(m[1]) * 1e6 + Number((m[2] || '').padEnd(6, '0')) : null;
}

class FlexEmulator {
  constructor(options = {}) {
    this.serial = options.serial ?? '1234-5678-9012-3456';
    this.protocol = options.protocol ?? '1.4.0.0';
    this.model = options.model ?? 'FLEX-6600';
    this.maxSlices = options.maxSlices ?? 8;
    this.maxGui = options.maxGui ?? 4;
    this.announceClients = options.announceClients; // overrides available_clients
    this.silent = options.silent ?? false; // announces nothing
    this.needRegister = options.needRegister ?? false; // sends a stream only to a registered source, as a NAT would
    this.registered = []; // {text, port, at}
    this.ignoreTune = options.ignoreTune ?? false; // accepts slice tune, never reports it
    this.replyFirst = options.replyFirst ?? false; // answers sub client before its statuses
    this.daxStatusDelay = options.daxStatusDelay ?? 0; // ms until a DAX change takes effect
    this.discoveryPorts = options.discoveryPorts ?? [];
    this.handleBase = options.handleBase ?? 0x10000000;
    this.sliceOrder = options.sliceOrder ?? [0, 1, 2, 3, 4, 5, 6, 7];
    this.streamBase = options.streamBase ?? 0x04000000;
    this.staleStreams = options.staleStreams ?? [];
    this.preassignOnGui = options.preassignOnGui ?? null;
    this.external = new Map(); // handle -> clientId of a connected client without socket
    for (const [i, id] of (options.externalClients ?? []).entries()) this.external.set(this.handleBase + 0x100 + i, id);
    this.clients = new Map(); // handle -> {socket, clientId, gui, udpPort, subs:Set}
    this.slices = new Map(); // index -> {owner, hz, mode, rxant, dax, letter, amplitude}
    this.streams = new Map(); // id -> {owner, channel, count, phase}
    this.log = []; // {connection, handle, clientId, command, target}
    this.connections = 0;
    this.nextHandle = this.handleBase + 1;
    this.nextStream = 1;
  }
  async start() {
    this.server = net.createServer(socket => this.accept(socket));
    this.server.listen(0, '127.0.0.1'); await once(this.server, 'listening');
    this.port = this.server.address().port;
    this.udp = dgram.createSocket('udp4'); this.udp.bind(0, '127.0.0.1'); await once(this.udp, 'listening');
    // Another host on the network sending the station's own stream ID.
    this.udp.on('message', (data, from) => this.registered.push({text: data.toString('latin1'), port: from.port, at: performance.now()}));
    this.udpPort = this.udp.address().port;
    this.stranger = dgram.createSocket('udp4'); this.stranger.bind(0, '127.0.0.2'); await once(this.stranger, 'listening');
    this.stranger.unref();
    // Unreferenced: a failed test that never reaches stop() cannot keep node --test alive.
    this.discoveryTimer = setInterval(() => this.announce(), 250).unref();
    this.server.unref(); this.udp.unref();
    this.started = performance.now(); this.sentFrames = 0;
    this.audioTimer = setInterval(() => this.audio(), 10).unref();
    this.announce();
    return this;
  }
  async stop() {
    clearInterval(this.discoveryTimer); clearInterval(this.audioTimer);
    for (const c of this.clients.values()) c.socket.destroy();
    await new Promise(resolve => this.server.close(resolve));
    await new Promise(resolve => this.udp.close(resolve));
    await new Promise(resolve => this.stranger.close(resolve));
  }
  guiCount() { return [...this.clients.values()].filter(c => c.gui).length + this.external.size; }
  announce() {
    if (this.silent) return;
    const available = this.announceClients ?? Math.max(0, this.maxGui - this.guiCount());
    const text = `model=${this.model} serial=${this.serial} version=4.1.3.39644 nickname=Emulator ip=127.0.0.1 port=${this.port} available_clients=${available} available_slices=${this.maxSlices - this.slices.size}`;
    const packet = vita({type: 3, stream: 0x800, packetClass: DISCOVERY, payload: Buffer.from(text)});
    for (const port of this.discoveryPorts) this.udp.send(packet, port, '127.0.0.1');
  }
  audio() {
    const due = Math.floor((performance.now() - this.started) * 48) - this.sentFrames;
    for (let left = due; left >= 128; left -= 128) {
      this.sentFrames += 128;
      const owned = [...this.streams.entries()];
      for (const [id, s] of owned) {
        const client = this.clients.get(s.owner), slice = this.sliceOf(s);
        if (!client?.udpPort || !slice) continue;
        if (this.needRegister && !this.registered.some(r => r.port === client.udpPort && r.text === `client udp_register handle=0x${hex(s.owner)}`)) continue;
        const sender = this.strangerOnly ? this.stranger : this.udp;
        sender.send(vita({type: 1, stream: id, packetClass: DAX48, count: s.count++, integer: 1, payload: daxPayload(128, slice.amplitude, s.phase)}), client.udpPort, '127.0.0.1');
        s.phase += 128;
        // Interference every 8th packet: another client's stream ID and any stale old-session
        // ID, at a loud amplitude a correctly routed station must never accept.
        if (s.count % 8 === 0) {
          this.stranger.send(vita({type: 1, stream: id, packetClass: DAX48, payload: daxPayload(128, 0.95, 0)}), client.udpPort, '127.0.0.1');
          for (const foreign of [...owned.filter(([other]) => other !== id).map(([other]) => other), ...this.staleStreams]) {
            this.udp.send(vita({type: 1, stream: foreign, packetClass: DAX48, payload: daxPayload(128, 0.95, 0)}), client.udpPort, '127.0.0.1');
          }
        }
      }
    }
  }
  // The audio of a DAX channel comes from the lowest slice on it, whoever owns the stream.
  sliceOf(stream) { return [...this.slices.entries()].sort(([a], [b]) => a - b).map(([, v]) => v).find(v => v.dax === stream.channel); }
  publish(topic, line) {
    for (const c of this.clients.values()) if (c.subs.has(topic)) c.socket.write(line + '\n');
  }
  sliceLine(index, s, by) {
    return `S${hex(by)}|slice ${index} in_use=1 client_handle=0x${hex(s.owner)} RF_frequency=${mhz(s.hz)} mode=${s.mode} rxant=${s.rxant} dax=${s.dax} index_letter=${s.letter}`;
  }
  streamLine(id, s, by) {
    const letter = this.sliceOf(s)?.letter ?? 'A';
    return `S${hex(by)}|stream 0x${hex(id)} type=dax_rx dax_channel=${s.channel} slice=${letter} client_handle=0x${hex(s.owner)} dax_clients=1`;
  }
  accept(socket) {
    const connection = ++this.connections, handle = this.nextHandle++;
    const client = {socket, clientId: null, gui: false, udpPort: null, subs: new Set(), connection};
    this.clients.set(handle, client);
    socket.setNoDelay(true);
    socket.on('error', () => {});
    socket.write(`V${this.protocol}\nH${hex(handle)}\n`);
    let pending = '';
    socket.on('data', data => {
      pending += data.toString('latin1');
      let at;
      while ((at = pending.indexOf('\n')) >= 0) { const line = pending.slice(0, at).replace(/\r$/, ''); pending = pending.slice(at + 1); this.command(handle, client, line); }
    });
    socket.on('close', () => this.disconnect(handle));
  }
  disconnect(handle) {
    const client = this.clients.get(handle); if (!client) return;
    this.clients.delete(handle);
    // A GUI client's resources leave with its connection.
    for (const [id, s] of [...this.streams]) if (s.owner === handle) { this.streams.delete(id); this.publish('dax', `S${hex(handle)}|stream 0x${hex(id)} removed`); }
    for (const [i, s] of [...this.slices]) if (s.owner === handle) { this.slices.delete(i); this.publish('slice', `S${hex(handle)}|slice ${i} in_use=0`); }
    this.publish('client', `S0|client 0x${hex(handle)} disconnected forced=0`);
  }
  removeExternal(clientId) {
    for (const [h, id] of this.external) if (id === clientId) { this.external.delete(h); this.publish('client', `S0|client 0x${hex(h)} disconnected forced=0`); }
  }
  command(handle, client, line) {
    const m = /^C(\d+)\|(.*)$/.exec(line);
    if (!m) return;
    const [, seq, text] = m, reply = (code, message = '') => client.socket.write(`R${seq}|${code}|${message}\n`);
    const words = text.split(' '), target = /^slice (?:tune|set|remove|r|t|s) (\d+)/.exec(text);
    this.log.push({connection: client.connection, handle, clientId: client.clientId, command: text, target: target ? (this.slices.get(Number(target[1]))?.owner ?? null) : undefined});
    const kv = Object.fromEntries(words.filter(w => w.includes('=')).map(w => w.split('=')));
    if (text === 'sub client all') {
      client.subs.add('client');
      if (this.replyFirst) reply(0);
      for (const [h, id] of this.external) client.socket.write(`S0|client 0x${hex(h)} connected client_id=${id} program=External station=Other\n`);
      for (const [h, c] of this.clients) if (c.gui) client.socket.write(`S0|client 0x${hex(h)} connected client_id=${c.clientId} program=WSTX station=Station\n`);
      if (!this.replyFirst) reply(0);
      return;
    }
    if (text === 'client start_persistence off' || text === 'ping') return reply(0);
    // The form of a real FLEX-6600's reply, recorded 2026-11-06.
    if (text === 'info') return reply(0, `model="${this.model}",chassis_serial="${this.serial}",name="",callsign="TEST",gps="Not Present",num_slice=${this.maxSlices},num_tx=1,software_ver=4.3.16.42034,ip=127.0.0.1`);
    if (words[0] === 'client' && words[1] === 'gui' && words.length === 3) {
      if (this.guiCount() >= this.maxGui) return reply('50000005');
      client.gui = true; client.clientId = words[2];
      this.publish('client', `S0|client 0x${hex(handle)} connected client_id=${words[2]} program=WSTX station=Station`);
      // Optional persistence-restore fault: a slice already attributed to the new handle.
      if (this.preassignOnGui && words[2].toLowerCase() === this.preassignOnGui.toLowerCase()) this.createSlice(handle, 'ANT1');
      return reply(0, words[2].toUpperCase());
    }
    if (text === 'sub slice all') {
      client.subs.add('slice');
      for (const [i, s] of this.slices) client.socket.write(this.sliceLine(i, s, 0) + '\n');
      return reply(0);
    }
    if (text === 'sub dax all') {
      client.subs.add('dax');
      for (const [id, s] of this.streams) client.socket.write(this.streamLine(id, s, 0) + '\n');
      return reply(0);
    }
    if (words[0] === 'client' && words[1] === 'udpport' && /^\d+$/.test(words[2] ?? '')) { client.udpPort = Number(words[2]); return reply(0); }
    if (words[0] === 'slice' && words[1] === 'create') {
      if (!client.gui) return reply('50000005');
      if (this.slices.size >= this.maxSlices) return reply('50000001');
      return reply(0, String(this.createSlice(handle, kv.rxant ?? 'ANT1', kv.mode)));
    }
    if (target) {
      const index = Number(target[1]), s = this.slices.get(index);
      if (!s) return reply('5000000D');
      if (words[1] === 'remove' || words[1] === 'r') { this.slices.delete(index); this.publish('slice', `S${hex(handle)}|slice ${index} in_use=0`); return reply(0); }
      if (words[1] === 'tune' || words[1] === 't') { const hz = hertz(words[3] ?? ''); if (hz === null) return reply('50000016'); if (this.ignoreTune) return reply(0); s.hz = hz; }
      else if (kv.dax !== undefined && this.daxStatusDelay) {
        setTimeout(() => { s.dax = Number(kv.dax); this.publish('slice', this.sliceLine(index, s, handle)); }, this.daxStatusDelay);
        return reply(0);
      }
      else { if (kv.dax !== undefined) s.dax = Number(kv.dax); if (kv.mode !== undefined) s.mode = kv.mode; }
      this.publish('slice', this.sliceLine(index, s, handle));
      return reply(0);
    }
    if (words[0] === 'stream' && words[1] === 'create' && kv.type === 'dax_rx' && /^[1-8]$/.test(kv.dax_channel ?? '')) {
      const id = this.streamBase + this.nextStream++;
      const s = {owner: handle, channel: Number(kv.dax_channel), count: 0, phase: 0};
      this.streams.set(id, s);
      this.publish('dax', this.streamLine(id, s, handle));
      return reply(0, '0x' + hex(id));
    }
    return reply('50000016');
  }
  createSlice(owner, rxant, mode = 'DIGU') {
    const index = this.sliceOrder.find(i => !this.slices.has(i));
    const letter = String.fromCharCode(65 + [...this.slices.values()].filter(s => s.owner === owner).length);
    // Only ANT1/ANT2 exist here; another request is substituted, as a radio would report it.
    const s = {owner, hz: 7000000, mode, rxant: ['ANT1', 'ANT2'].includes(rxant) ? rxant : 'ANT1', dax: 0, letter, amplitude: Number((0.1 + 0.1 * index).toFixed(1))};
    this.slices.set(index, s);
    this.publish('slice', this.sliceLine(index, s, owner));
    return index;
  }
  // Oracle views.
  ownerOf(clientId) { for (const [h, c] of this.clients) if (c.clientId?.toLowerCase() === clientId.toLowerCase()) return h; return null; }
  slicesOf(clientId) { const h = this.ownerOf(clientId); return [...this.slices].filter(([, s]) => s.owner === h).map(([i, s]) => ({index: i, ...s})); }
  streamsOf(clientId) { const h = this.ownerOf(clientId); return [...this.streams].filter(([, s]) => s.owner === h).map(([id]) => id); }
  commandsOf(clientId) { return this.log.filter(e => e.clientId?.toLowerCase() === clientId.toLowerCase()); }
}
module.exports = {FlexEmulator, vita, daxPayload, hertz, mhz};
