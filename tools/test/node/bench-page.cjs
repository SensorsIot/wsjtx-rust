'use strict';
// The page of a candidate bench (tools/test/powershell/candidate-bench.ps1) for a tester's live test
// on the simulator (harness/project/docs/specifics/deployment-authority.md, Candidate bench): a
// headless Chromium (Playwright, the repository's node_modules) on http://127.0.0.1:<port> only, so
// it never reaches the installed station or anything off this machine. A tester's script in its run
// folder requires this module by its absolute path:
//   const bench = require('D:/Github/wsjtx-rust/tools/test/node/bench-page.cjs');
//   const {page, close} = await bench.open(bench.record(107).url);
//   const rows = await bench.texts(page, '<selector>');      // what the DOM shows, in its order
//   await bench.evidence(page, 'D:/wstx-tmp/live/107/case-2'); // .png and .html beside it
//   await close();
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');

const BENCH = /^http:\/\/127\.0\.0\.1:(\d{1,5})\/?$/;
const LIVE = 'D:/wstx-tmp/live';

// The record of issue `issue`'s running bench (candidate-bench.ps1 -Start writes it).
function record(issue, live = LIVE) {
  const file = path.join(live, String(issue), 'bench', 'bench.json');
  return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
}

// A headless browser on the bench page; refuses every origin but http://127.0.0.1:<port>.
async function open(origin, {timeout = 30000} = {}) {
  const match = BENCH.exec(String(origin));
  if (!match || Number(match[1]) < 1 || Number(match[1]) > 65535) {
    throw new Error(`bench-page opens only a candidate bench on http://127.0.0.1:<port>, not ${origin}`);
  }
  const bench = new URL(origin);
  const blocked = [];
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage();
    // Every request and WebSocket of the page goes to the bench only: a script or link of the page
    // never reaches the installed station or anything off this machine.
    await page.route('**/*', route => {
      const url = route.request().url();
      if (new URL(url).origin === bench.origin) return route.continue();
      blocked.push(url);
      return route.abort('blockedbyclient');
    });
    await page.routeWebSocket(url => new URL(url).host !== bench.host, ws => { blocked.push(ws.url()); ws.close(); });
    await page.goto(origin, {waitUntil: 'load', timeout});
    return {browser, page, blocked, close: () => browser.close()};
  } catch (error) {
    await browser.close();
    throw error;
  }
}

// The text of each element `selector` matches, in document order, as the rendered DOM holds it (after
// the page's scripts ran), whitespace folded.
async function texts(page, selector) {
  return page.$$eval(selector, nodes => nodes.map(node => node.textContent.replace(/\s+/g, ' ').trim()));
}

// The page as evidence: `<base>.png` (the full page) and `<base>.html` (the rendered DOM).
async function evidence(page, base) {
  await page.screenshot({path: `${base}.png`, fullPage: true});
  fs.writeFileSync(`${base}.html`, await page.content());
  return {png: `${base}.png`, html: `${base}.html`};
}

module.exports = {record, open, texts, evidence};
