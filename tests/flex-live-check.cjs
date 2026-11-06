'use strict';
// FR-023 one-shot receive check through the real station: one slice, one DAX stream, receive
// only, released at the end. It measures what the radio's path delivers (loss, jitter, packet
// rate, timestamps) and what the station's own decoder makes of it (rows, DT).
//   node tests/flex-live-check.cjs <radio address:port> [seconds=180] [band=20m] [out directory]
// Only with the operator's consent for that run, for a radio named on the command line. It
// stops before connecting as a client if anyone else holds the radio, and it has no transmit
// path. tests/native-flex.test.cjs runs it against the emulator.
const fs = require('node:fs/promises'), os = require('node:os'), path = require('node:path');
const https = require('node:https'), net = require('node:net');
const {randomUUID} = require('node:crypto'), {gunzipSync} = require('node:zlib');
const selfsigned = require('selfsigned');
const {server, grant, browserPort} = require('./support.cjs');

const PACKETS_PER_SECOND = 24000 / 128;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const stats = values => { const s = [...values].sort((a, b) => a - b); return s.length ? {n: s.length, min: s[0], median: s[s.length >> 1], max: s[s.length - 1]} : {n: 0}; };

// A plain look at the radio: who holds it. Sends only slice list and sub client all.
function look(address) {
  return new Promise((resolve, reject) => {
    const [host, port] = address.split(':');
    const socket = net.connect(Number(port), host);
    let text = '';
    socket.setTimeout(8000, () => socket.destroy(new Error('radio connection timeout')));
    socket.on('error', reject);
    socket.on('connect', () => socket.write('C1|slice list\nC2|sub client all\n'));
    socket.on('data', data => { text += data.toString('latin1'); });
    setTimeout(() => {
      socket.destroy();
      const lines = text.split('\n');
      const slices = /^R1\|0\|(.*)$/m.exec(text)?.[1]?.trim() ?? null;
      resolve({reachable: lines.some(l => l.startsWith('V')), slices, clients: lines.filter(l => /\|client 0x\S+ connected/.test(l)).length});
    }, 2000);
  });
}

async function run({address, seconds = 180, band = '20m', out, registerPort, antenna = 'ANT1'}) {
  if (!/^\d+\.\d+\.\d+\.\d+:\d+$/.test(address ?? '')) throw new Error('radio address:port required');
  const report = {started: new Date().toISOString(), seconds, band, status: 'not_started'};
  const directory = out ?? await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-flex-check-'));
  await fs.mkdir(directory, {recursive: true});
  const finish = async () => { await fs.writeFile(path.join(directory, 'report.json'), JSON.stringify(report, null, 1)); return report; };
  report.before = await look(address);
  if (!report.before.reachable) { report.status = 'unreachable'; return finish(); }
  if (report.before.clients || report.before.slices) { report.status = 'occupied'; return finish(); }
  const dir = path.join(directory, 'profile'), port = await browserPort();
  await fs.mkdir(dir, {recursive: true});
  const origin = `https://localhost:${port}`, token = randomUUID().replaceAll('-', ''), id = randomUUID();
  const cert = await selfsigned.generate([{name: 'commonName', value: 'localhost'}], {days: 1, keySize: 2048, extensions: [{name: 'subjectAltName', altNames: [{type: 2, value: 'localhost'}]}]});
  await fs.writeFile(path.join(dir, 'cert.pem'), cert.cert); await fs.writeFile(path.join(dir, 'key.pem'), cert.private);
  await fs.writeFile(path.join(dir, 'profile.json'), JSON.stringify({schema_version: 2, profile_id: id, revision: 0, display_name: 'Flex live check', callsign: 'HB9BLA', locator: 'JN37VL', endpoint: {bind: `127.0.0.1:${port}`, origin}, audio: {input_device: null, output_device: null}, control: {mode: 'disabled', endpoint: null, ptt: 'disabled'}, connection_type: 'native_flex', native: {client_id: randomUUID(), rx_antenna: antenna, radio_address: address}}));
  const app = await server({WSTX_TLS_CERT: path.join(dir, 'cert.pem'), WSTX_TLS_KEY: path.join(dir, 'key.pem'), WSTX_TOKEN: token, ...(registerPort ? {WSTX_FLEX_REGISTER_PORT: String(registerPort)} : {})}, ['--profile', dir]);
  let cookie = '';
  const request = (route, method = 'GET', body, extra = {}) => new Promise((resolve, reject) => {
    const req = https.request(origin + route, {method, ca: cert.cert, agent: false, headers: {Origin: origin, ...(cookie ? {Cookie: cookie} : {}), ...(body === undefined ? {} : {'Content-Type': 'application/json'}), ...extra}}, res => {
      const chunks = []; res.on('data', b => chunks.push(b));
      res.on('end', () => { const raw = Buffer.concat(chunks), text = (res.headers['content-encoding'] === 'gzip' ? gunzipSync(raw) : raw).toString(); resolve({status: res.statusCode, headers: res.headers, text, body: text && (res.headers['content-type'] || '').startsWith('application/json') ? JSON.parse(text) : null}); });
    });
    req.on('error', reject); if (body !== undefined) req.write(typeof body === 'string' ? body : JSON.stringify(body)); req.end();
  });
  try {
    cookie = (await grant(origin, token, (route, method, body, extra) => request(route, method, body, extra))).cookie;
    let session;
    for (let i = 0; i < 60; i++) { session = (await request('/native-flex')).body; if (session.state === 'ready' || session.state === 'conflict') break; await sleep(500); }
    report.session = {state: session.state, error: session.error, radio_code: session.radio_code, radio: session.radio, slice: session.slice};
    if (session.state !== 'ready') { report.status = 'no_session'; return await finish(); }
    const prior = (await request('/receive/selection')).body, command_id = randomUUID();
    const envelope = {v: 1, profile_id: prior.profile_id, boot_id: prior.boot_id};
    await request('/receive/diagnostics', 'POST', {...envelope, window_dump: true});
    const ack = await request('/receive/select', 'POST', {...envelope, command_id, action: 'band', profile_revision: prior.profile_revision, generation: prior.generation, operating_revision: prior.operating_revision, band});
    if (ack.status !== 202) { report.status = 'selection_refused'; report.selection = ack.text; return await finish(); }
    let selected;
    for (let i = 0; i < 80; i++) { selected = (await request('/receive/selection')).body; if (selected.operation?.result !== 'pending') break; await sleep(250); }
    report.selection = {result: selected.operation?.result, error: selected.operation?.error, frequency_hz: selected.radio.observations.frequency.value, origin: selected.selection.origin};
    if (selected.operation?.result !== 'success') { report.status = 'selection_failed'; return await finish(); }
    const started = Date.now(), before = (await request('/native-flex')).body.packets, end = started + seconds * 1000;
    const dts = [], texts = []; let rows = 0, key = '', cursor = 0, last;
    while (Date.now() < end) {
      await sleep(1000);
      const r = (await request('/receive')).body;
      last = r;
      if (!r.source || !r.job) continue;
      const k = r.source.id + r.job.id; if (k !== key) { key = k; cursor = r.job.first_sequence ?? 0; }
      for (;;) {
        const page = await request(`/receive/results?source_id=${r.source.id}&job_id=${r.job.id}&generation=${r.generation}&cursor=${cursor}&limit=16`);
        if (page.status !== 200 || !page.body.records?.length) break;
        for (const record of page.body.records) {
          rows++; if (record.text && texts.length < 40) texts.push(record.text);
          if (typeof record.dt_seconds === 'number') dts.push(record.dt_seconds);
          cursor = record.sequence + 1;
        }
        if (!page.body.more) break;
      }
    }
    const elapsed = (Date.now() - started) / 1000, f = (await request('/native-flex')).body;
    const accepted = f.packets.accepted - before.accepted, lost = f.packets.lost - before.lost;
    Object.assign(report, {elapsed_s: elapsed, packets: {accepted, lost, foreign: f.packets.foreign - before.foreign, invalid: f.packets.invalid - before.invalid},
      loss_percent: accepted + lost ? 100 * lost / (accepted + lost) : null, received_ratio: accepted / (elapsed * PACKETS_PER_SECOND),
      arrival: f.arrival, vita: f.vita, audio: last?.audio, clock: last?.clock, rows, texts, dt_seconds: stats(dts), session_end: {state: f.state, error: f.error}});
    report.status = 'measured';
  } finally {
    await app.close();
    await sleep(2500);
    report.after = await look(address).catch(error => ({error: error.message}));
    await fs.cp(path.join(dir, 'diagnostic-windows'), path.join(directory, 'windows'), {recursive: true}).catch(() => {});
    await fs.rm(dir, {recursive: true, force: true}).catch(() => {});
    await finish();
  }
  return report;
}
module.exports = {run};
if (require.main === module) {
  const [address, seconds, band, out] = process.argv.slice(2);
  run({address, seconds: Number(seconds) || 180, band: band || '20m', out}).then(report => { console.log(JSON.stringify(report, null, 1)); process.exitCode = report.status === 'measured' ? 0 : 1; }, error => { console.error(error); process.exitCode = 1; });
}
