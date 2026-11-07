'use strict';
// Harness retrospective item 3 (SensorsIot/harness#38): one page kept open on the running station
// across a real restart and several periods. Red on `undefined` or NaN in what it shows, on a
// row tip that changes, on an uncaught page error or on a page command that is not a read.
//   powershell -File .harness/deploy/live-page-check.ps1
// That script stops and starts the station when this asks for it, in the file <control>/restart,
// and hands the session on stdin, one JSON line each, so that it is on no command line or disk:
//   {"cookies":[{"name","value"}]}  at the start, and again once the new boot answers
//   {"stopping":true}               the station is being stopped now
//   {"abort":"why"}                 the station is in use: no restart, exit 3
// Exit 0 green; 1 red; 3 busy; 4 not exercised: nothing went wrong, but the old boot's generation
// was not above the new one's (#22) or no kept row had a worked-before tip (#50).
// Receive only: it starts nothing and selects nothing. The station resumes receive by itself;
// a station that does not, or a dead band, ends in a timeout, red.
// The page is the station's actual client. Only its authorization component is replaced: a browser
// grant is made with the access token, and this runs on the agent's session instead.
const fs=require('node:fs'),path=require('node:path'),readline=require('node:readline');
const {chromium}=require('playwright');
const {watchPage,rowKey}=require('./page-watch.cjs');

// Reads the page sends by itself. Anything else never reaches the station and fails the check.
const READS=['/contact/worked','/strategy/evaluate','/authorization/v1/status'];
const AUTHORIZATION=`window.stationAuthorization=(()=>{const s=Object.freeze({epoch:1,state:'ready',ready:true,scope:null});
  const no=()=>Promise.reject(new Error('live page check: no authorization action'));
  return Object.freeze({snapshot:()=>s,ensureReady:()=>Promise.resolve(s),fetch:(p,o)=>fetch(p,o),bootstrap:no,logout:no,forget:no});})();`;
const PERIODS=3,MINUTES=60000,WAIT=1000*(Number(process.env.WSTX_LIVE_PAGE_WAIT_SECONDS)||300);

async function run({origin,control,lines}){
  const browser=await chromium.launch();
  try{
    const context=await browser.newContext({viewport:{width:1440,height:900}}),page=await context.newPage();
    const url=new URL(origin),refused=[];
    const setCookies=cookies=>context.addCookies(cookies.map(({name,value})=>({name,value,domain:url.hostname,path:'/',secure:true,httpOnly:true,sameSite:'Strict'})));
    await context.route('**/*',route=>{
      const r=route.request(),at=new URL(r.url());
      if(at.origin!==url.origin)return route.abort();
      if(at.pathname==='/authorization.js')return route.fulfill({contentType:'text/javascript',body:AUTHORIZATION});
      if(r.method()!=='GET'&&!READS.includes(at.pathname)){refused.push(`${r.method()} ${at.pathname}`);return route.abort();}
      return route.continue();
    });
    const watch=watchPage(page);
    const clean=what=>{const why=watch.verdict();if(why||refused.length)throw new Error(`${what}: ${why??''} commands refused: ${JSON.stringify(refused)}`);};
    await setCookies((await lines.next('first session',10000)).cookies);
    await page.goto(origin);
    const first=await watch.until('the page connects',seen=>seen.state==='connected'&&seen.boot,30000);
    const firstBoot=first.boot;
    // Several periods, and a row seen moving from the latest period to the kept ones.
    await watch.until('several periods before the restart',()=>{clean('before the restart');return watch.periods.size>=PERIODS&&watch.moved()>0;},4*MINUTES);
    const before={periods:watch.periods.size,moved:watch.moved()};

    fs.writeFileSync(path.join(control,'restart'),'');
    let message;
    let last;
    await watch.until('the restart is not answered',seen=>{clean('waiting for the restart');last=seen;return (message=lines.poll());},WAIT+3*MINUTES);
    if(message.abort)return {status:'busy',why:message.abort};
    const gone=await watch.until('the page sees the station gone',seen=>{if(seen.state==='connected'&&seen.boot===firstBoot)last=seen;return seen.state!=='connected'||seen.boot!==firstBoot;},60000);
    // Every row the old boot showed, up to its last period: a #22 defect keeps those.
    const old=new Set(watch.tips.keys()),oldGeneration=last.generation;
    await watch.until('the new session',()=>{const m=lines.poll();if(m)message=m;return message.cookies;},4*MINUTES);
    await setCookies(message.cookies);
    const oldRows=seen=>seen.rows.filter(r=>old.has(rowKey(r)));
    // Rows of the old boot may stay until the first reads of the new boot answer.
    const back=await watch.until('the page is back on the new boot',seen=>seen.state==='connected'&&seen.boot&&seen.boot!==firstBoot&&!oldRows(seen).length,2*MINUTES);
    // The window that showed "Latest undefined period" with the old boot's rows.
    const quiet=Date.now()+8000;
    while(Date.now()<quiet){
      const seen=await watch.sample();clean('just after the restart');
      if(oldRows(seen).length)throw new Error(`a row of the previous boot: ${JSON.stringify(oldRows(seen).slice(0,4))}`);
      await page.waitForTimeout(500);
    }
    // Several periods of the new boot, again with a row that moved.
    await watch.until('several periods after the restart',()=>{clean('after the restart');return watch.periods.size>=before.periods+PERIODS&&watch.moved()>before.moved;},4*MINUTES);
    clean('at the end');
    // Green only with both live triggers on screen: #22 needs the old boot's generation above the
    // new one's, #50 a worked-before tip on a kept row. Without them nothing was shown wrong, but
    // nothing was proven either.
    const generations={old:oldGeneration,new:back.generation},missing=[];
    if(!(Number.isInteger(oldGeneration)&&Number.isInteger(back.generation)&&oldGeneration>back.generation))missing.push('#22: the old generation was not above the new one');
    if(!watch.worked.kept)missing.push('#50: no worked-before tip on a kept row');
    return {status:missing.length?'not-exercised':'green',missing,generations,gone:gone.state,before,after:{periods:watch.periods.size,moved:watch.moved()},rowsWatched:watch.tips.size,tipsWatched:[...watch.tips.values()].filter(Boolean).length,worked:watch.worked,commands:[...new Set(watch.commands)]};
  }finally{await browser.close();}
}

// One JSON line at a time from whoever started this: next() waits, poll() does not.
function stdinLines(){
  const queue=[],waiting=[];
  readline.createInterface({input:process.stdin}).on('line',line=>{
    // Windows PowerShell's stdin starts with a byte order mark. The line holds the session, so a
    // bad one is never printed, and neither is the error that would quote it.
    let m;try{m=JSON.parse(line.replace(/^\uFEFF/,''));}catch{console.error('a stdin line is not JSON');process.exit(2);}
    const w=waiting.shift();if(w)w(m);else queue.push(m);
  });
  return {
    poll:()=>queue.shift(),
    next:(what,timeout)=>queue.length?Promise.resolve(queue.shift()):new Promise((resolve,reject)=>{const t=setTimeout(()=>reject(new Error(`no ${what}`)),timeout);waiting.push(m=>{clearTimeout(t);resolve(m);});}),
  };
}
module.exports={run};
if(require.main===module){
  const origin=process.env.WSTX_LIVE_PAGE_ORIGIN,control=process.env.WSTX_LIVE_PAGE_CONTROL;
  if(!origin?.startsWith('https://')||!control){console.error('run through .harness/deploy/live-page-check.ps1');process.exit(2);}
  run({origin,control,lines:stdinLines()}).then(report=>{console.log(`PAGE CHECK ${JSON.stringify(report)}`);process.exit({green:0,busy:3,'not-exercised':4}[report.status]);},e=>{console.log(`PAGE CHECK RED ${e.message}`);process.exit(1);});
}
