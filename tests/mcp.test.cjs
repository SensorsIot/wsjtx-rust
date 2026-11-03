'use strict';
// Cost 2: the compiled candidate executable on a disposable selected HTTPS profile (TLS
// with a throwaway certificate, no radio, audio or RF), a browser-style grant that creates
// an MCP client token in Settings (#58) and an independent MCP client writing literal
// JSON-RPC. Expected values: the fixture profile document and the WstxMcp tool catalog table.
// Proves: CL-012-01, CL-012-02, CL-012-03; TC-020-001, TC-020-002, TC-020-004.
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const https = require('node:https');
const crypto = require('node:crypto');
const {spawn} = require('node:child_process');
const {once} = require('node:events');
const selfsigned = require('selfsigned');
const {grant, browserPort} = require('./support.cjs');
const exe = process.env.WSTX_TEST_EXE || path.resolve(process.env.CARGO_TARGET_DIR || 'target', 'debug', 'wstx-rust.exe');
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
const browserGrant = () => grant(origin, token, (route, method, body, h) => send(route, method, body, {Origin: origin, ...h}));
// Settings > General > Access & grants > MCP clients, as the browser does it.
const settings = (cookie, action, body) => action ? send('/authorization/v1/mcp-clients/' + action, 'POST', {version: 1, ...body}, {Origin: origin, Cookie: cookie})
  : send('/authorization/v1/mcp-clients', 'GET', undefined, {Cookie: cookie});
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

test('TC-020-001 an MCP client with its own MCP client token observes the browser state of the actual executable', {timeout: 60000}, async () => {
  const browser = await browserGrant();
  const created = await settings(browser.cookie, 'create', {name: 'Claude Code'});
  assert.equal(created.status, 200, JSON.stringify(created.body));
  assert.match(created.body.token, /^wstx_mcp_[A-Za-z0-9_-]{43}$/);
  assert.equal(created.headers['cache-control'], 'no-store');
  const headers = {Authorization: 'Bearer ' + created.body.token};
  const list = await modern(headers.Authorization, 'tools/list');
  assert.equal(list.status, 200, JSON.stringify(list.body));
  assert.deepEqual(list.body.result.tools.map(t => t.name), ['wstx_read', 'wstx_results', 'wstx_contact_command', 'wstx_transmit_halt', 'wstx_automation_command', 'wstx_strategy_evaluate']);
  // The browser (its own grant) and the MCP client read the same profile representation.
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
  // The strategy view (#39) the browser reads, unchanged through MCP.
  const strategyPage = await send('/strategy', 'GET', undefined, {Cookie: browser.cookie});
  assert.equal(strategyPage.status, 200);
  const strategy = await modern(headers.Authorization, 'tools/call', {name: 'wstx_read', arguments: {view: 'strategy'}});
  assert.equal(strategy.body.result.isError, false, JSON.stringify(strategy.body));
  assert.deepEqual(strategy.body.result.structuredContent.result, strategyPage.body);
  assert.equal(strategy.body.result.structuredContent.result.profile_id, document.profile_id);
  // A legacy-era client of the same endpoint.
  const init = await send('/mcp', 'POST', {jsonrpc: '2.0', id: 1, method: 'initialize', params: {protocolVersion: '2025-11-25', capabilities: {}, clientInfo: {name: 'legacy', version: '1'}}}, {Authorization: headers.Authorization});
  assert.equal(init.body.result.protocolVersion, '2025-11-25');
});

test('TC-020-002 TC-020-004 browser credentials never authorize MCP, an MCP token never opens a browser route and revocation is immediate', {timeout: 60000}, async () => {
  const browser = await browserGrant();
  const cookieOnly = await send('/mcp', 'POST', {jsonrpc: '2.0', id: 1, method: 'tools/list', params: {_meta: meta}},
    {Cookie: browser.cookie, 'MCP-Protocol-Version': '2026-07-28', 'Mcp-Method': 'tools/list'});
  assert.equal(cookieOnly.status, 401); assert.equal(cookieOnly.headers['www-authenticate'], 'Bearer realm="wstx"');
  // Configurations from before #58 (the grant transport or the station access token as
  // the bearer) are refused with the hint to the MCP client token.
  for (const legacy of [browser.cookie.split('=')[1], token]) {
    const refused = await modern('Bearer ' + legacy, 'tools/list');
    assert.equal(refused.status, 401);
    assert.equal(refused.body.error.data.reason, 'mcp_token_required');
    assert.match(refused.body.error.data.hint, /Settings > General > Access & grants > MCP clients/);
  }
  const created = await settings(browser.cookie, 'create', {name: 'agent'});
  assert.equal(created.status, 200, JSON.stringify(created.body));
  const mcpToken = created.body.token, bearer = 'Bearer ' + mcpToken;
  assert.equal((await modern(bearer, 'tools/list')).status, 200);
  // The MCP token on a browser route, as the session cookie or a bearer: refused.
  const cookieName = browser.cookie.split('=')[0];
  for (const h of [{Cookie: `${cookieName}=${mcpToken}`}, {Authorization: bearer}]) {
    assert.equal((await send('/contact', 'GET', undefined, {Origin: origin, ...h})).status, 401);
    assert.equal((await send('/authorization/v1/mcp-clients', 'GET', undefined, {Origin: origin, ...h})).status, 401);
  }
  const session = await send('/session', 'POST', mcpToken, {Origin: origin});
  assert.equal(session.status, 401); assert.equal(session.headers['set-cookie'], undefined, 'no browser session for an MCP token');
  // Listed by name; the token is never shown again; the use is audited.
  const listed = await settings(browser.cookie, '', {});
  const mine = listed.body.clients.find(c => c.client_id === created.body.client_id);
  assert.equal(mine.name, 'agent'); assert.equal(typeof mine.last_used_utc_ms, 'number');
  assert.equal(JSON.stringify(listed.body).includes(mcpToken.slice(9)), false);
  assert.equal(listed.body.recent[0].name, 'agent'); assert.equal(listed.body.recent[0].action, 'tools/list');
  // Revoked in Settings: refused at the next request.
  const revoked = await settings(browser.cookie, 'revoke', {client_id: created.body.client_id});
  assert.equal(revoked.status, 200);
  const after = await modern(bearer, 'tools/list');
  assert.equal(after.status, 401); assert.equal(after.body.error.data.reason, 'mcp_token_invalid');
});
