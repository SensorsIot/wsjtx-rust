'use strict';
// The test of the suites' /audio/endpoints route (audio-endpoints-route.cjs), on a station
// started by support.cjs and a real Chromium page.
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {chromium} = require('playwright');
const {server} = require('./support.cjs');
const {routeAudioEndpoints} = require('./audio-endpoints-route.cjs');

let browser;
before(async () => {browser = await chromium.launch();});
after(async () => {await browser?.close();});
const entry = (id, label) => ({id, name: label, label, present: true, radio: null});

// Proves the suite's route for /audio/endpoints: a station stopped with its window open refuses,
// mid-test or at teardown, and is no unhandled rejection after the test ended.
test('suite audio endpoint route refuses for a stopped station', {timeout: 30000}, async t => {
  const app = await server(); t.after(() => app.close());
  const context = await browser.newContext({ignoreHTTPSErrors: true}); t.after(() => context.close());
  await routeAudioEndpoints(context, [entry('fixture-input', 'Fixture input')], [entry('fixture-output', 'Fixture output')]);
  const page = await context.newPage(); await page.goto(app.origin);
  await app.close();
  const outcome = await page.evaluate(() => fetch('/audio/endpoints').then(() => 'answered', () => 'refused'));
  assert.equal(outcome, 'refused');
});
