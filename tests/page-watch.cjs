'use strict';
// What a page kept open must never do, for the driver of the in-process station
// (tests/receive-page.test.cjs) and of the running station (tests/live-page-check.cjs).
// Harness retrospective item 3 (SensorsIot/harness#38), from #22 and #50's live defects.

// What a page shows must never read like a programming accident (#22, "Latest undefined period").
const ACCIDENT=/\bundefined\b|\bNaN\b/;
// A row keeps its tip while it is on screen. The worked-before status joins it once, when the
// period's one query is answered; beside the partner of a contact, nothing else can change a tip while nothing is set.
const WORKED=/ \(worked [^)]*\)/;
// The strategy's verdict ends a tip (#55). It ranks the rows on screen, so it joins when the station
// has evaluated the row and its number moves with every new period (seen live 2026-11-07, "#1" -> "#2").
// That is not the row's reason changing, so it stays out of the comparison, not out of ACCIDENT.
const VERDICT=/(?:^| · )(?:Strategy |Contest |Directed CQ|Dupe in).*$/;
function tipChange(before,after){
  const reason=t=>(t??'').replace(VERDICT,'');
  const was=reason(before),now=reason(after);
  if(was===now)return null;
  const bare=t=>t.replace(WORKED,'');
  return bare(was)===bare(now)&&!WORKED.test(was)?null:`"${before}" -> "${after}"`;
}
const rowKey=row=>`${row.when} ${row.message}`;

function watchPage(page){
  const errors=[],accidents=new Map(),tips=new Map(),firstPeriod=new Map(),changes=[],worked={latest:0,kept:0},commands=[],periods=new Set(),partners=new Set();
  let moved=0;
  page.on('pageerror',e=>errors.push(e.message));
  page.on('request',r=>{if(r.method()!=='GET')commands.push(new URL(r.url()).pathname);});
  const read=()=>page.evaluate(()=>({
    text:document.body.innerText,
    heading:document.querySelector('#band-activity header')?.innerText??'',
    attributes:[...document.querySelectorAll('[title],[aria-label],[aria-description],[data-tip]')].flatMap(el=>['title','aria-label','aria-description','data-tip'].map(a=>el.getAttribute(a)).filter(Boolean)),
    rows:[...document.querySelectorAll('#band-activity tbody tr[data-sequence]')].map(row=>({period:row.dataset.period,tip:row.dataset.tip??null,when:row.querySelector('td')?.textContent,message:row.querySelector('td[data-col=message]')?.textContent,sender:row.dataset.sender,partner:row.classList.contains('ba-partner')})),
    band:typeof operatingState==='undefined'?null:operatingState?.selection?.band??null,on:document.querySelector('#band-activity')?.dataset.hlOn,
    boot:typeof profileData==='undefined'?null:profileData?.boot_id,
    state:document.querySelector('#connection')?.dataset.state,
    job:typeof live==='undefined'?null:live?.job?.id??null,
    generation:typeof live==='undefined'?null:live?.generation??null,
  }));
  const sample=async()=>{
    const seen=await read();
    for(const text of [seen.text,...seen.attributes])if(ACCIDENT.test(text)){const line=text.split('\n').find(l=>ACCIDENT.test(l)).trim();accidents.set(line,(accidents.get(line)??0)+1);}
    for(const row of seen.rows)if(row.partner)partners.add(row.sender);
    for(const row of seen.rows){
      // A contact's partner has its reasons taken off its rows and is worked after it: a cause.
      const key=rowKey(row),change=tips.has(key)&&!partners.has(row.sender)?tipChange(tips.get(key),row.tip):null;
      if(change)changes.push(`${key} (${row.period}): ${change}`);
      tips.set(key,row.tip);periods.add(row.when);
      if(!firstPeriod.has(key))firstPeriod.set(key,row.period);
      else if(firstPeriod.get(key)==='latest'&&row.period!=='latest'){moved++;firstPeriod.set(key,row.period);}
      if(WORKED.test(row.tip??''))worked[row.period==='latest'?'latest':'kept']++;
    }
    return seen;
  };
  const status=seen=>({changes:changes.slice(0,4),accidents:[...accidents.keys()],errors:errors.slice(0,4),heading:seen.heading,state:seen.state,job:seen.job,rows:seen.rows.length,sample:seen.rows.filter(r=>r.tip).slice(0,4),worked,moved,periodsSeen:periods.size,periods:[...new Set(seen.rows.map(r=>r.period))],band:seen.band,on:seen.on});
  const until=async(what,done,timeout)=>{
    const deadline=Date.now()+timeout;
    for(;;){
      const seen=await sample();
      if(done(seen))return seen;
      if(Date.now()>=deadline)throw new Error(`${what}: ${JSON.stringify(status(seen))}`);
      await page.waitForTimeout(500);
    }
  };
  // Null, or why the page failed so far: no accident, no changed tip, no uncaught error.
  const verdict=()=>accidents.size||changes.length||errors.length?JSON.stringify({accidents:[...accidents.keys()],changes,errors}):null;
  return {sample,until,verdict,status,tips,accidents,changes,errors,worked,commands,periods,moved:()=>moved};
}
module.exports={watchPage,tipChange,rowKey,ACCIDENT};
