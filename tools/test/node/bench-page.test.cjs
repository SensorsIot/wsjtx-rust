'use strict';
// bench-page.cjs: the page check reads what the rendered DOM shows, and opens only a loopback bench.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const {listenBrowser} = require('./support.cjs');
const bench = require('./bench-page.cjs');

// A page whose rows exist only after its script ran, in an order the HTML source does not hold.
const PAGE = `<!doctype html><html><body><ol id="rows"><li class="row">source order</li></ol>
<script>
  const list = document.getElementById('rows'); list.innerHTML = '';
  for (const call of ['K1ABC', 'DL2XYZ', 'JA3QRP']) { const li = document.createElement('li'); li.className = 'row'; li.textContent = ' ' + call + '\\n'; list.appendChild(li); }
</script></body></html>`;

test('the page check reads the rows the rendered DOM shows, in their order', async () => {
  const server = http.createServer((req, res) => { res.setHeader('content-type', 'text/html'); res.end(PAGE); });
  const port = await listenBrowser(server);
  const {page, close} = await bench.open(`http://127.0.0.1:${port}`);
  try {
    assert.deepEqual(await bench.texts(page, '#rows .row'), ['K1ABC', 'DL2XYZ', 'JA3QRP']);
    const base = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'bench-page-')), 'case');
    const files = await bench.evidence(page, base);
    assert.match(fs.readFileSync(files.html, 'utf8'), /DL2XYZ/);
    assert.ok(fs.statSync(files.png).size > 0);
  } finally {
    await close();
    server.close();
  }
});

test('it opens no origin but a candidate bench on 127.0.0.1', async () => {
  for (const origin of ['https://192.168.0.37:18081', 'http://localhost:8080', 'https://127.0.0.1:8080',
                        'http://127.0.0.1', 'http://127.0.0.1:0', 'http://127.0.0.1:8080/../x', 'http://example.com']) {
    await assert.rejects(bench.open(origin), /opens only a candidate bench/, origin);
  }
});

test('a request or WebSocket of the page to any other origin is aborted and never arrives', async () => {
  let reached = 0;
  const other = http.createServer((req, res) => { reached++; res.end('x'); });
  other.on('upgrade', (req, socket) => { reached++; socket.destroy(); });
  const otherPort = await listenBrowser(other);
  const page = `<!doctype html><html><body><img src="http://127.0.0.1:${otherPort}/img.png">
<script>
  fetch('http://127.0.0.1:${otherPort}/fetch').catch(() => {});
  try { new WebSocket('ws://127.0.0.1:${otherPort}/ws'); } catch (e) {}
  fetch('/same').then(r => r.text()).then(t => { document.body.dataset.same = t; });
</script></body></html>`;
  const server = http.createServer((req, res) => res.end(req.url === '/same' ? 'ok' : page));
  const port = await listenBrowser(server);
  const opened = await bench.open(`http://127.0.0.1:${port}`);
  try {
    await opened.page.waitForFunction(() => document.body.dataset.same === 'ok');
    await opened.page.waitForTimeout(500);
    assert.equal(reached, 0, 'the other origin was reached');
    assert.ok(opened.blocked.some(u => u.includes('/fetch')), opened.blocked.join(' '));
    assert.ok(opened.blocked.some(u => u.includes('/img.png')), opened.blocked.join(' '));
    assert.ok(opened.blocked.some(u => u.startsWith('ws://')), opened.blocked.join(' '));
  } finally {
    await opened.close();
    server.close();
    other.close();
  }
});

test('the bench record names the url', () => {
  const live = fs.mkdtempSync(path.join(os.tmpdir(), 'bench-live-'));
  fs.mkdirSync(path.join(live, '7', 'bench'), {recursive: true});
  fs.writeFileSync(path.join(live, '7', 'bench', 'bench.json'), '﻿' + JSON.stringify({url: 'http://127.0.0.1:5'}));
  assert.equal(bench.record(7, live).url, 'http://127.0.0.1:5');
});
