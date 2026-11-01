#!/usr/bin/env node
'use strict';
// WstxMcp::McpCredential helper: holds one auth-v1 (CL-022-01) grant key for an MCP client
// and turns it into the `Authorization: Bearer <grant transport>` header of POST /mcp.
//   enroll  once, with the station's bootstrap token: creates a P-256 key, enrolls its
//           public verifier through the station's normal bootstrap/enroll routes and
//           writes the private key to WSTX_MCP_KEY (owner read/write only).
//   header  (default) proves the key with a fresh one-use challenge and prints
//           {"Authorization":"Bearer ..."}: the Claude Code `headersHelper` output.
// Environment: WSTX_MCP_ORIGIN (exact station HTTPS origin), WSTX_MCP_KEY (key file),
// WSTX_MCP_BOOTSTRAP_TOKEN (enroll only, never stored or printed). Trust the station's
// certificate with NODE_EXTRA_CA_CERTS. No dependency beyond Node itself.
const crypto = require('node:crypto');
const fs = require('node:fs');

function fail(message) {
  process.stderr.write(`wstx-mcp-credential: ${message}\n`);
  process.exit(1);
}
const origin = process.env.WSTX_MCP_ORIGIN, keyFile = process.env.WSTX_MCP_KEY;
if (!origin || !/^https:\/\/[^/]+$/.test(origin)) fail('WSTX_MCP_ORIGIN must be the station https origin');
if (!keyFile) fail('WSTX_MCP_KEY must name the key file');

async function post(route, body, cookie) {
  const headers = {'Content-Type': 'application/json', Origin: origin};
  if (cookie) headers.Cookie = cookie;
  const response = await fetch(origin + route, {method: 'POST', headers, body: typeof body === 'string' ? body : JSON.stringify(body), redirect: 'error'});
  const text = await response.text();
  return {status: response.status, cookie: (response.headers.get('set-cookie') || '').split(';')[0], body: text ? JSON.parse(text) : null};
}
async function enroll() {
  const token = process.env.WSTX_MCP_BOOTSTRAP_TOKEN;
  if (!token) fail('WSTX_MCP_BOOTSTRAP_TOKEN is required for enroll');
  if (fs.existsSync(keyFile)) fail('key file exists; remove it to enroll again');
  const session = await post('/session', token);
  if (session.status !== 204) fail(`bootstrap refused (${session.status})`);
  const scoped = await post('/authorization/v1/bootstrap-scope', {version: 1}, session.cookie);
  if (scoped.status !== 200) fail(`bootstrap scope refused (${scoped.status})`);
  const {publicKey, privateKey} = crypto.generateKeyPairSync('ec', {namedCurve: 'P-256'});
  const jwk = publicKey.export({format: 'jwk'});
  const public_key = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]).toString('base64url');
  const grant_id = crypto.randomBytes(32).toString('base64url');
  const enrolled = await post('/authorization/v1/enroll', {version: 1, operation_id: crypto.randomUUID(), scope: scoped.body.current_scope, grant_id, public_key}, session.cookie);
  if (enrolled.status !== 200 || enrolled.body?.outcome !== 'committed') fail(`enroll refused (${enrolled.status})`);
  const stored = {version: 1, origin, grant_id, private_key: privateKey.export({format: 'pem', type: 'pkcs8'})};
  fs.writeFileSync(keyFile, JSON.stringify(stored), {mode: 0o600, flag: 'wx'});
  process.stdout.write('enrolled\n');
}
async function header() {
  let stored;
  try {stored = JSON.parse(fs.readFileSync(keyFile, 'utf8'));} catch {fail('key file unreadable; run enroll');}
  if (stored.version !== 1 || stored.origin !== origin) fail('key file belongs to another station origin');
  const challenge = await post('/authorization/v1/challenge', {version: 1, grant_id: stored.grant_id});
  if (challenge.status !== 200) fail(`challenge refused (${challenge.status}); the grant may be revoked`);
  const c = challenge.body.scope, parts = [Buffer.from('WSTX-AUTH-PROOF'), Buffer.from([1])];
  for (const field of [origin, c.profile_id, c.radio_id, String(c.safety_revision), stored.grant_id].map(v => Buffer.from(v)).concat([Buffer.from(challenge.body.nonce, 'base64url')])) {
    const size = Buffer.alloc(4); size.writeUInt32BE(field.length); parts.push(size, field);
  }
  const signature = crypto.sign('sha256', Buffer.concat(parts), {key: stored.private_key, dsaEncoding: 'ieee-p1363'}).toString('base64url');
  const proof = await post('/authorization/v1/proof', {version: 1, grant_id: stored.grant_id, nonce: challenge.body.nonce, signature});
  const transport = proof.cookie.split('=')[1];
  if (proof.status !== 204 || !transport) fail(`proof refused (${proof.status})`);
  process.stdout.write(JSON.stringify({Authorization: `Bearer ${transport}`}) + '\n');
}
const command = process.argv[2] || 'header';
(command === 'enroll' ? enroll() : command === 'header' ? header() : Promise.resolve(fail('usage: enroll | header'))).catch(error => fail(error.message));
