'use strict';
// One page kept open on the running station
// across a real restart and several periods. Red on `undefined` or NaN in what it shows, on a
// row tip that changes, on an uncaught page error or on a page command that is not a read.
//   powershell -File tools/deploy/live-page-check.ps1 -Repo <root> -Shared <git common dir>\harness-parallel -AgentClient <client>
// That script stops and starts the station when this asks for it, in the file <control>/restart,
// and hands the session on stdin, one JSON line each, so that it is on no command line or disk:
//   {"cookies":[{"name","value"}]}  at the start, again when a new login of that script replaced
//                                   it before the stop (the station keeps one session per grant,
//                                   and the page shares that script's), and once the new boot answers
//   {"selected":{"generation","ms"}} it made its band selection at that generation: this waits
//                                   up to ms for a higher generation with new rows on the page,
//                                   then writes the file <control>/rows
//   {"unexercised":"why"}           it made no band selection, or the selection did not take
//   {"stopping":true}               the station is being stopped now
//   {"abort":"why"}                 the station is in use: no restart, exit 3
// Exit 0 green; 1 red; 3 busy; 4 not exercised: nothing went wrong, but the old boot's generation
// was not above the new one's, the band selection was not made or did not take, or no
// kept row had a worked-before tip.
// The page sends no command. Before the restart that script makes one band selection of the band
// and mode the station receives on, so that the old boot's job stands at generation 2 or
// more; the station resumes receive by itself after the restart. A station that does not, or a
// dead band after the restart, ends in a timeout, red.
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

// What a request of the page may do: go to the station (anything else is aborted), get the
// stand-in authorization component, or pass as a GET or a read; any other command is refused.
function allowed(method,at,origin){
  if(at.origin!==origin)return 'abort';
  if(at.pathname==='/authorization.js')return 'stub';
  return method==='GET'||READS.includes(at.pathname)?'pass':'refuse';
}
// Which live trigger was not on screen. The restart generation needs the new boot without a receive job yet
// (generation null: recording.js sync cleared live) or below the old boot's generation; the worked-before tip a
// worked-before tip on a kept row. Without them nothing was shown wrong, but nothing was proven.
function missingTriggers(oldGeneration,newGeneration,workedKept){
  const missing=[];
  if(!(Number.isInteger(oldGeneration)&&(newGeneration===null||newGeneration<oldGeneration)))missing.push('restart generation: the new boot had a job at a generation not below the old one');
  if(!workedKept)missing.push('worked-before tip: no worked-before tip on a kept row');
  return missing;
}
// The same, after why the band selection did not raise the old boot's generation: never green then.
function exerciseMissing(unexercised,oldGeneration,newGeneration,workedKept){
  return [...unexercised.map(why=>`restart generation: ${why}`),...missingTriggers(oldGeneration,newGeneration,workedKept)];
}
// What the page must show after the band selection made at `generation`: a higher generation,
// with a row of a decoded period that was not on screen when the selection was reported.
function raisedWithRows(seen,generation,known){
  return Number.isInteger(seen.generation)&&seen.generation>generation&&seen.rows.some(r=>!known.has(rowKey(r)));
}
// What each side showed when the wait for rows ran out, in one line and without a session value:
// the station's generation and job state (null: it could not be read), then the page's
// generation and job state, its receive status text and whether its station-data notice is shown.
function waitSides(station,seen){
  const side=station?`station generation ${station.generation}, job ${station.job??'none'}`:'the station could not be read';
  const status=String(seen.status??'none').replace(/\s+/g,' ').trim();
  return `${side}; page generation ${seen.generation??'none'}, job ${seen.jobState??'none'}; receive status "${status}"; station-data notice ${seen.notice===true?'shown':seen.notice===false?'not shown':'absent'}`;
}
// The station's side for that line, or null when it cannot be read.
async function readStation(station){
  try{const s=await station();return s&&Number.isInteger(s.generation)?s:null;}catch{return null;}
}
// From the restart request to the stop or the abort. Each message may take as long as the idle
// wait, the selection's retries and its result together (3 x -WaitSeconds), plus a margin.
// `station` reads GET /receive/selection `generation` and GET /receive `job.state` as
// {generation,job}; it is read only for the reason of a wait that runs out.
// `renew` takes a session that replaced the page's before the stop.
async function awaitStop({watch,lines,control,clean,wait,pause,station=async()=>null,renew=async()=>{}}){
  const unexercised=[];
  let message,last;
  for(;;){
    message=undefined;
    await watch.until('the restart is not answered',seen=>{clean('waiting for the restart');last=seen;return (message=lines.poll());},3*wait+3*MINUTES);
    if(message.cookies){await renew(message.cookies);continue;}
    if(message.unexercised){unexercised.push(message.unexercised);continue;}
    if(!message.selected)return {message,last,unexercised};
    const {generation,ms}=message.selected,end=Date.now()+ms;
    last=await watch.sample();clean('at the band selection');
    const known=new Set(watch.tips.keys());
    for(;;){
      if(raisedWithRows(last,generation,known))break;
      if(Date.now()>=end){unexercised.push(`no rows of a generation above ${generation} on the page within ${Math.round(ms/1000)} s of the band selection: ${waitSides(await readStation(station),last)}`);break;}
      await pause(500);
      last=await watch.sample();clean('waiting for the raised generation');
    }
    fs.writeFileSync(path.join(control,'rows'),'');
  }
}

async function run({origin,control,lines}){
  const browser=await chromium.launch();
  try{
    const context=await browser.newContext({viewport:{width:1440,height:900}}),page=await context.newPage();
    const url=new URL(origin),refused=[];
    const setCookies=cookies=>context.addCookies(cookies.map(({name,value})=>({name,value,domain:url.hostname,path:'/',secure:true,httpOnly:true,sameSite:'Strict'})));
    await context.route('**/*',route=>{
      const r=route.request(),at=new URL(r.url()),how=allowed(r.method(),at,url.origin);
      if(how==='stub')return route.fulfill({contentType:'text/javascript',body:AUTHORIZATION});
      if(how==='pass')return route.continue();
      if(how==='refuse')refused.push(`${r.method()} ${at.pathname}`);
      return route.abort();
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
    // Two reads with the session of this browser context, for the reason of a wait that runs out.
    const station=()=>page.evaluate(async()=>{
      const get=async p=>{const r=await fetch(p,{cache:'no-store'});if(!r.ok)throw new Error(`HTTP ${r.status}`);return r.json();};
      const [selection,receive]=await Promise.all([get('/receive/selection'),get('/receive')]);
      return {generation:selection.generation,job:receive.job?.state??null};
    });
    let {message,last,unexercised}=await awaitStop({watch,lines,control,clean,wait:WAIT,pause:ms=>page.waitForTimeout(ms),station,renew:setCookies});
    if(message.abort)return {status:'busy',why:message.abort};
    const gone=await watch.until('the page sees the station gone',seen=>{if(seen.state==='connected'&&seen.boot===firstBoot)last=seen;return seen.state!=='connected'||seen.boot!==firstBoot;},60000);
    // Every row the old boot showed, up to its last period: a page that misses the restart keeps those.
    const old=new Set(watch.tips.keys()),oldGeneration=last.generation;
    await watch.until('the new session',()=>{const m=lines.poll();if(m)message=m;return message.cookies;},4*MINUTES);
    await setCookies(message.cookies);
    const oldRows=seen=>seen.rows.filter(r=>old.has(rowKey(r)));
    // Rows of the old boot may stay until the first reads of the new boot answer.
    const back=await watch.until('the page is back on the new boot',seen=>seen.state==='connected'&&seen.boot&&seen.boot!==firstBoot&&!oldRows(seen).length,2*MINUTES);
    // The window where a faulty page shows "Latest undefined period" with the old boot's rows.
    const quiet=Date.now()+8000;
    while(Date.now()<quiet){
      const seen=await watch.sample();clean('just after the restart');
      if(oldRows(seen).length)throw new Error(`a row of the previous boot: ${JSON.stringify(oldRows(seen).slice(0,4))}`);
      await page.waitForTimeout(500);
    }
    // Several periods of the new boot, again with a row that moved.
    await watch.until('several periods after the restart',()=>{clean('after the restart');return watch.periods.size>=before.periods+PERIODS&&watch.moved()>before.moved;},4*MINUTES);
    clean('at the end');
    // Green only with both live triggers on screen, after a band selection that took.
    const generations={old:oldGeneration,new:back.generation},missing=exerciseMissing(unexercised,oldGeneration,back.generation,watch.worked.kept>0);
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
module.exports={run,allowed,missingTriggers,exerciseMissing,raisedWithRows,awaitStop,READS};
if(require.main===module){
  const origin=process.env.WSTX_LIVE_PAGE_ORIGIN,control=process.env.WSTX_LIVE_PAGE_CONTROL;
  if(!origin?.startsWith('https://')||!control){console.error('run through tools/deploy/live-page-check.ps1');process.exit(2);}
  run({origin,control,lines:stdinLines()}).then(report=>{console.log(`PAGE CHECK ${JSON.stringify(report)}`);process.exit({green:0,busy:3,'not-exercised':4}[report.status]);},e=>{console.log(`PAGE CHECK RED ${e.message}`);process.exit(1);});
}
