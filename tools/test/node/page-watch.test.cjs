'use strict';
// The test of the page watch (page-watch.cjs) on a fixture page.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const {watchPage,tipChange}=require('./page-watch.cjs');

// The oracle itself goes red: a fixture page with the accident and the changed tip it must find.
test('the page watch fails on undefined and on a changing tip, and passes what may change',{timeout:60000},async()=>{
  const n='New on 20m',w=`${n} (worked on another band or mode)`;
  assert.equal(tipChange(n,w),null,'the worked-before status joins once');
  assert.ok(tipChange(w,n),'the worked-before status must not go again');
  assert.ok(tipChange(null,n),'a reason must not appear');
  assert.equal(tipChange(`New call · Strategy New calls: #2`,`New call · Strategy New calls: #4`),null,'the rank moves with the rows on screen');
  assert.equal(tipChange(null,'Strategy New calls: #1'),null,'the verdict joins after the evaluation');
  assert.ok(tipChange(`New call · Strategy New calls: #2`,`Strategy New calls: #2`),'a reason beside the verdict must not go');
  const browser=await chromium.launch();
  try{
    const page=await browser.newPage(),watch=watchPage(page);
    await page.setContent(`<section id="band-activity"><table><tbody><tr data-sequence="1" data-period="latest" data-tip="${n}"><td>08:00:00</td><td data-col="message">CQ K1ABC FN42</td></tr></tbody></table></section>`);
    await watch.sample();
    assert.equal(watch.verdict(),null,'the plain page passes');
    await page.evaluate(()=>{document.querySelector('tr').dataset.tip='New on undefined';});
    await watch.sample();
    assert.match(watch.verdict(),/undefined/);
    assert.equal(watch.changes.length,1);
  }finally{await browser.close();}
});
