'use strict';
// Cost 2: the compiled candidate executable on a disposable selected HTTPS profile (TLS
// with a throwaway certificate, no radio, audio or RF), the operator credential helper
// tools/wstx-mcp-credential.cjs and an independent MCP client writing literal JSON-RPC.
// Expected values: the fixture profile document and the WstxMcp tool catalog table.
// Proves: CL-012-01, CL-012-02; TC-020-001, TC-020-002.
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const https = require('node:https');
const crypto = require('node:crypto');
const {spawn, execFile} = require('node:child_process');
const {once} = require('node:events');
const selfsigned = require('selfsigned');
const {grant, browserPort} = require('./support.cjs');
const exe = process.env.WSTX_TEST_EXE || path.resolve(process.env.CARGO_TARGET_DIR || 'target', 'debug', 'wstx-rust.exe');
const helper = path.resolve(__dirname, '..', 'tools', 'wstx-mcp-credential.cjs');
let root, app, origin, ca, token, certPath, document;

function send(route, method, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body);
    const request = https.request(origin + route, {method, ca, headers: {...(data !== undefined ? {'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data)} : {}), ...headers}}, response => {
      let text = ''; response.setEncoding('utf8'); response.on('data', c => {text += c;});
      response.on('end', () => {let parsed = null; try {parsed = text ? JSON.parse(text) : null;} catch {parsed = text;} resolve({status: response.statusCode, headers: response.headers, body: parsed});});
    });
    request.on('error', reject); if (data !== undefined) request.write(data); request.end();
  });
}
function credential(command, env) {
  return new Promise(resolve => execFile(process.execPath, [helper, command], {env: {...process.env, NODE_EXTRA_CA_CERTS: certPath, ...env}, windowsHide: true},
    (error, stdout, stderr) => resolve({code: error ? error.code : 0, stdout, stderr})));
}
const meta = {'io.modelcontextprotocol/protocolVersion': '2026-07-28', 'io.modelcontextprotocol/clientInfo': {name: 'wstx-node-test', version: '1'}, 'io.modelcontextprotocol/clientCapabilities': {}};
function modern(bearer, method, params = {}) {
  const headers = {Authorization: bearer, Accept: 'application/json, text/event-stream', 'MCP-Protocol-Version': '2026-07-28', 'Mcp-Method': method};
  if (params.name) headers['Mcp-Name'] = params.name;
  return send('/mcp', 'POST', {jsonrpc: '2.0', id: 1, method, params: {...params, _meta: meta}}, headers);
}

before(async () => {
  assert.ok(await fs.stat(exe), 'compiled candidate is required');
  root = await fs.mkdtemp(path.join(os.tmpdir(), 'wstx-mcp-tests-'));
  const cert = await selfsigned.generate([{name: 'commonName', value: 'localhost'}], {days: 1, keySize: 2048, extensions: [{name: 'subjectAltName', altNames: [{type: 2, value: 'localhost'}]}]});
  certPath = path.join(root, 'cert.pem'); const keyPath = path.join(root, 'key.pem');
  await fs.writeFile(certPath, cert.cert); await fs.writeFile(keyPath, cert.private, {mode: 0o600});
  ca = cert.cert;
  const port = await browserPort(); origin = `https://localhost:${port}`;
  const dir = path.join(root, 'profile');
  document = {schema_version: 1, profile_id: crypto.randomUUID(), revision: 0, display_name: 'MCP station', callsign: 'HB9BLA', locator: 'JN47AA',
    audio: {input_device: null, output_device: null}, control: {mode: 'disabled', endpoint: null, ptt: 'disabled'},
    endpoint: {bind: `127.0.0.1:${port}`, origin}, connection_type: 'standard'};
  await fs.mkdir(dir); await fs.writeFile(path.join(dir, 'profile.json'), JSON.stringify(document));
  token = crypto.randomBytes(32).toString('hex');
  const clean = {...process.env}; for (const key of Object.keys(clean)) if (key.startsWith('WSTX_')) delete clean[key];
  app = spawn(exe, ['--profile', dir], {env: {...clean, WSTX_SNTP_SERVERS: '', WSTX_UDP: 'off', WSTX_TLS_CERT: certPath, WSTX_TLS_KEY: keyPath, WSTX_TOKEN: token}, windowsHide: true});
  let output = ''; app.stdout.on('data', b => {output += b;}); app.stderr.on('data', b => {output += b;});
  const deadline = Date.now() + 10000;
  while (!output.includes(`WSTX listening ${origin}`)) {
    if (app.exitCode !== null || Date.now() > deadline) assert.fail('readiness: ' + output);
    await new Promise(r => setTimeout(r, 20));
  }
});
after(async () => {
  if (app && app.exitCode === null) {app.kill(); await once(app, 'exit');}
  if (root) await fs.rm(root, {recursive: true, force: true});
});

test('TC-020-001 an MCP client with its own auth-v1 grant observes the browser state of the actual executable', {timeout: 60000}, async () => {
  const keyFile = path.join(root, 'mcp-key.json');
  const enrolled = await credential('enroll', {WSTX_MCP_ORIGIN: origin, WSTX_MCP_KEY: keyFile, WSTX_MCP_BOOTSTRAP_TOKEN: token});
  assert.equal(enrolled.code, 0, enrolled.stderr); assert.equal(enrolled.stdout, 'enrolled\n');
  assert.equal((await fs.readFile(keyFile, 'utf8')).includes(token), false, 'the bootstrap token is never stored');
  const issued = await credential('header', {WSTX_MCP_ORIGIN: origin, WSTX_MCP_KEY: keyFile});
  assert.equal(issued.code, 0, issued.stderr);
  const headers = JSON.parse(issued.stdout); assert.deepEqual(Object.keys(headers), ['Authorization']);
  assert.match(headers.Authorization, /^Bearer [A-Za-z0-9_-]{43}$/);
  const list = await modern(headers.Authorization, 'tools/list');
  assert.equal(list.status, 200, JSON.stringify(list.body));
  assert.deepEqual(list.body.result.tools.map(t => t.name), ['wstx_read', 'wstx_results', 'wstx_contact_command', 'wstx_transmit_halt', 'wstx_automation_command']);
  // A browser (its own grant) and the MCP client read the same profile representation.
  const browser = await grant(origin, token, (route, method, body, h) => send(route, method, body, {Origin: origin, ...h}));
  const page = await send('/profile', 'GET', undefined, {Cookie: browser.cookie});
  assert.equal(page.status, 200);
  const read = await modern(headers.Authorization, 'tools/call', {name: 'wstx_read', arguments: {view: 'profile'}});
  assert.equal(read.body.result.isError, false);
  assert.deepEqual(read.body.result.structuredContent.result, page.body);
  assert.equal(read.body.result.structuredContent.result.profile_id, document.profile_id);
  assert.equal(read.body.result.structuredContent.result.settings.callsign, 'HB9BLA');
  const contact = await modern(headers.Authorization, 'tools/call', {name: 'wstx_read', arguments: {view: 'contact'}});
  assert.equal(contact.body.result.structuredContent.result.profile_id, document.profile_id);
  assert.equal(contact.body.result.structuredContent.result.transmit.arm_state, 'disarmed');
  // A legacy-era client of the same endpoint.
  const init = await send('/mcp', 'POST', {jsonrpc: '2.0', id: 1, method: 'initialize', params: {protocolVersion: '2025-11-25', capabilities: {}, clientInfo: {name: 'legacy', version: '1'}}}, {Authorization: headers.Authorization});
  assert.equal(init.body.result.protocolVersion, '2025-11-25');
});

test('TC-020-002 the browser cookie, a foreign key file and a refused grant never authorize MCP', {timeout: 60000}, async () => {
  const browser = await grant(origin, token, (route, method, body, h) => send(route, method, body, {Origin: origin, ...h}));
  const cookieOnly = await send('/mcp', 'POST', {jsonrpc: '2.0', id: 1, method: 'tools/list', params: {_meta: meta}},
    {Cookie: browser.cookie, 'MCP-Protocol-Version': '2026-07-28', 'Mcp-Method': 'tools/list'});
  assert.equal(cookieOnly.status, 401); assert.equal(cookieOnly.headers['www-authenticate'], 'Bearer realm="wstx"');
  const bearerFromCookie = await modern('Bearer ' + browser.cookie.split('=')[1], 'tools/list');
  assert.equal(bearerFromCookie.status, 200, 'the same grant transport is valid only when presented explicitly as a bearer');
  const keyFile = path.join(root, 'foreign-key.json');
  await fs.writeFile(keyFile, JSON.stringify({version: 1, origin: 'https://other.example:1', grant_id: 'x', private_key: 'x'}));
  const foreign = await credential('header', {WSTX_MCP_ORIGIN: origin, WSTX_MCP_KEY: keyFile});
  assert.notEqual(foreign.code, 0); assert.equal(foreign.stdout, '');
  const badToken = await credential('enroll', {WSTX_MCP_ORIGIN: origin, WSTX_MCP_KEY: path.join(root, 'never.json'), WSTX_MCP_BOOTSTRAP_TOKEN: 'wrong'});
  assert.notEqual(badToken.code, 0); assert.match(badToken.stderr, /bootstrap refused \(401\)/);
  await assert.rejects(fs.stat(path.join(root, 'never.json')), 'no key file after a refused enrollment');
});
