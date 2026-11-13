'use strict';
// CR #10 contact log (WstxLogbook::ContactHistory, UpdateLogbook, ExportAdi, WorkedBeforeQuery).
// The server owns the log, its identities, times and worked-before status, and logs each
// completed QSO itself (DirectLog, #41: no review form); this browser renders confirmed
// responses and sends requests.
(()=>{
const region=document.querySelector('#region-logbook .op-secondary-body');
if(!region)return;
for(const node of [...region.childNodes].slice(1))node.remove();
region.querySelector('p').textContent='Contacts logged in this station profile\u2019s contacts.adi (ADIF 3.1.8). Each completed QSO is logged automatically; history is read-only.';
region.insertAdjacentHTML('beforeend',`<h3>Logged contacts</h3><p id="log-history-status" role="status">History not loaded</p><ol id="log-history"></ol><button type="button" id="log-history-older" disabled>Older contacts</button> <button type="button" id="log-history-newer" disabled>Newer contacts</button> <button type="button" id="log-history-refresh">Reload history</button><h3>ADIF export</h3><button type="button" id="log-export">Export ADIF</button><p id="log-export-status" role="status"></p><p class="op-muted">To add the QSOs of another logger, use Settings \u203a Logging &amp; Reporting \u203a Update logbook from ADIF.</p>`);
const $=id=>document.getElementById(id);
for(const el of region.querySelectorAll('#log-history,#log-export-status'))el.style.overflowWrap='anywhere';
const uuid=()=>crypto.randomUUID();
const station=()=>profileData&&{profile_id:profileData.profile_id,boot_id:profileData.boot_id};
async function call(path,options={}){
  const response=await stationFetch(path,{...options,signal:AbortSignal.timeout(options.timeout??10000)});
  const type=response.headers.get('content-type')||'';
  const data=type.startsWith('application/json')?await response.json():null;
  return {response,data};
}
// ---------------------------------------------------------------- history
let cursor=null,total=0;const page=10;
function describe(r){
  const parts=[`#${r.index+1}`,`${r.qso_date} ${r.time_on}`,r.call,r.submode??r.mode,r.band??(r.freq?`${r.freq} MHz`:'band unknown')];
  if(r.gridsquare)parts.push(r.gridsquare);
  parts.push(`sent ${r.rst_sent??'\u2014'} rcvd ${r.rst_rcvd??'\u2014'}`);
  if(r.tx_pwr)parts.push(`${r.tx_pwr} W`);
  if(r.comment)parts.push(r.comment);
  if(r.unknown_field_count)parts.push(`${r.unknown_field_count} other field${r.unknown_field_count===1?'':'s'} kept`);
  return parts.join(' \u00b7 ');
}
async function loadHistory(at){
  const status=$('log-history-status');status.textContent='Loading history';
  try{
    let target=at;
    if(target===null){const first=await call('/contacts?cursor=0&limit=1');if(!first.response.ok)throw new Error(first.data?.error?.code??'history_unavailable');target=Math.max(0,first.data.total-page);}
    const {response,data}=await call(`/contacts?cursor=${target}&limit=${page}`);
    if(!response.ok)throw new Error(data?.error?.code??'history_unavailable');
    cursor=data.cursor;total=data.total;
    const list=$('log-history');list.replaceChildren(...data.records.slice().reverse().map(r=>{const li=document.createElement('li');li.textContent=describe(r);li.dataset.contactId=r.contact_id;return li;}));
    status.textContent=total?`${total} contact${total===1?'':'s'} \u00b7 showing ${data.cursor+1}\u2013${data.next}`:'No contacts saved yet';
    $('log-history-older').disabled=cursor===0;$('log-history-newer').disabled=!data.more;
  }catch(error){status.textContent=`History unavailable \u00b7 ${error.message}`;}
}
$('log-history-older').addEventListener('click',()=>loadHistory(Math.max(0,cursor-page)));
$('log-history-newer').addEventListener('click',()=>loadHistory(Math.min(total,cursor+page)));
$('log-history-refresh').addEventListener('click',()=>loadHistory(null));
document.addEventListener('click',event=>{if(event.target.closest?.('button[data-region="logbook"]'))loadHistory(null);});
document.addEventListener('keydown',event=>{if(event.key==='Enter'&&event.target.closest?.('button[data-region="logbook"]'))loadHistory(null);});

// ---------------------------------------------------------------- update logbook / export
// #10 WstxLogbook::UpdateLogbook in Settings > Logging & Reporting: another logger's ADIF
// export (for example Log4OM) is consolidated into this log. The station decides what is
// added, already present or skipped; this browser uploads the file and shows the summary.
async function sha256(bytes){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(b=>b.toString(16).padStart(2,'0')).join('');}
const groups=list=>list.map(g=>`${g.count} ${g.code.replaceAll('_',' ')}${g.field?` ${g.field}`:''}`).join(', ');
function updated(v){
  if(v.state==='completed')return `Logbook updated: ${v.added} added, ${v.present} already present (${v.confirmed} confirmation${v.confirmed===1?'':'s'} updated), ${v.skipped} skipped${v.reasons.length?` (${groups(v.reasons)})`:''}${v.dropped.length?` · fields left out: ${groups(v.dropped)}`:''}`;
  const e=v.error;
  return `Logbook not updated · nothing was added · ${e?.code?.replaceAll('_',' ')??'storage unavailable'}${e&&e.record!==null&&e.record!==undefined?` in record ${e.record+1}`:''}${e?.field?` field ${e.field}`:''}`;
}
const logging=document.querySelector('#settings-logging');
if(logging&&typeof block==='function'){
  const section=block('settings-update-log','Update logbook from ADIF',logging,'<p class="op-muted">Adds the QSOs of another logger’s ADIF export (for example Log4OM) that this logbook does not have yet, so worked-before, DXCC and grid status know them. A QSO already here (same call, band and mode, start within 2 minutes) stays as it is. Only the log fields are kept; nothing is sent to other programs. Repeat it after new QSOs in the other logger.</p><label>ADIF file (.adi)<input id="log-import-file" type="file" accept=".adi,.adif,text/plain"></label><p class="op-actions"><button type="button" id="log-import">Update logbook</button></p><p id="log-import-status" class="op-muted" role="status"></p>');
  document.getElementById('settings-log')?.after(section); // contact.js moves it there when it loads later
  $('log-import-status').style.overflowWrap='anywhere';
  $('log-import').addEventListener('click',async()=>{
    const status=$('log-import-status'),file=$('log-import-file').files[0],s=station();
    if(!file){status.textContent='Choose an ADIF file first';return;}
    if(!s){status.textContent='Station profile unavailable';return;}
    if(file.size===0||file.size>67108864){status.textContent='Logbook not updated · the file must hold 1 byte to 64 MiB';return;}
    $('log-import').disabled=true;
    try{
      const bytes=new Uint8Array(await file.arrayBuffer()),id=uuid();
      status.textContent='Checking file integrity';
      const reserve=await call('/contacts/imports',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,...s,import_id:id,total_bytes:bytes.length,sha256:await sha256(bytes)})});
      if(!reserve.response.ok)throw new Error(reserve.data?.error?.code??'update_unavailable');
      let last=reserve;
      for(let start=reserve.data.received_bytes;start<bytes.length;start+=16384){
        const chunk=bytes.subarray(start,Math.min(bytes.length,start+16384));
        last=await call(`/contacts/imports/${id}`,{method:'PUT',headers:{'Content-Type':'application/octet-stream','Content-Range':`bytes ${start}-${start+chunk.length-1}/${bytes.length}`},body:chunk,timeout:60000});
        if(last.response.status===422)break;
        if(!last.response.ok)throw new Error(last.data?.error?.code??'import_failed');
        status.textContent=`Uploading · ${Math.floor(100*last.data.received_bytes/bytes.length)} % of ${bytes.length} bytes`;
      }
      status.textContent=updated(last.response.status===422?(await call(`/contacts/imports/${id}`)).data:last.data);
      loadHistory(null);
    }catch(error){status.textContent=`Update outcome unknown · ${error.message}`;}
    finally{$('log-import').disabled=false;}
  });
}
$('log-export').addEventListener('click',async()=>{
  const status=$('log-export-status');
  try{
    const response=await stationFetch('/contacts/export.adi',{signal:AbortSignal.timeout(60000)});
    if(!response.ok)throw new Error((await response.json()).error?.code??'export_unavailable');
    const link=document.createElement('a');link.href=URL.createObjectURL(await response.blob());link.download='contacts.adi';link.hidden=true;document.body.append(link);link.click();link.remove();
    setTimeout(()=>URL.revokeObjectURL(link.href),10000);status.textContent='Exported contacts.adi';
  }catch(error){status.textContent=`Export unavailable \u00b7 ${error.message}`;}
});

// ---------------------------------------------------------------- Band Activity worked-before
// #55 CL-055-04: the New call slots come from the record flags; worked_status, which the station
// sets on each record, feeds only the row's hover text (WstxBandActivity::BandActivityHover), never a colour.
// The statuses of the latest and the previous period also mark the QSO pane's callers
// (CL-010-13, WstxQsoPane::QsoPane item 3).
let askedPeriod=null,answered=new Map(),previous=new Map(),answeredOn='';
window.wstxWorkedOf=call=>{const status=answered.get(call)??previous.get(call);return status?{status,on:answeredOn}:null;};
function annotate(body,records){
  const band=operatingState?.selection?.band,mode=live?.job?.mode;
  const period=resultView?`${liveIdentity(live)}/${resultView.first_sequence}/${resultView.period_start_utc}`:null;
  const from=r=>r.status==='decoded'&&r.fields?.type==='standard'&&r.fields.from?.kind==='call'&&typeof r.fields.from.text==='string'?r.fields.from.text.toUpperCase():null;
  // The answer stays on its record: the record moves to the kept period and is drawn again there (#50 BandActivityHover).
  const decorate=()=>{for(const row of body.querySelectorAll('tr[data-period=latest][data-sequence]')){const record=records.find(r=>String(r.sequence)===row.dataset.sequence),c=record&&from(record),status=c&&answered.get(c);if(!status||row.dataset.worked)continue;record.worked={status,on:`${band} ${mode.toUpperCase()}`};row.dataset.worked=status;row.dataset.workedOn=record.worked.on;window.wstxActivityWhy?.(row);}};
  if(!period||!band||!['ft8','ft4'].includes(mode))return;
  if(period!==askedPeriod){const on=`${band} ${mode.toUpperCase()}`;previous=on===answeredOn?answered:new Map();askedPeriod=period;answered=new Map();answeredOn=on;}
  let added=false;for(const r of records){const c=from(r);if(c&&r.worked_status&&!answered.has(c)){answered.set(c,r.worked_status);added=true;}}
  decorate();if(added)document.dispatchEvent(new Event('wstx-worked'));
}
// Observe the rendered rows instead of changing recording.js (its served source is pinned).
const activity=document.querySelector('#band-activity tbody');
if(activity)new MutationObserver(()=>annotate(activity,resultRows)).observe(activity,{childList:true});
window.wstxLogbook=Object.freeze({annotate,loadHistory});

// ---------------------------------------------------------------- country file (#55)
// WstxDxcc::CountryFile in Settings > General: the cty.dat in use, an upload replaces it
// (the station validates it), "Use bundled file" removes the upload. No automatic download.
const general=document.querySelector('#settings-general');
if(general&&typeof block==='function'){
  block('settings-cty','Country file (cty.dat)',general,'<p id="cty-status" class="op-muted" role="status">Country file not loaded</p><label>cty.dat file<input id="cty-file" type="file" accept=".dat,text/plain"></label><p class="op-actions"><button type="button" id="cty-upload">Upload cty.dat</button> <button type="button" id="cty-bundled">Use bundled file</button></p><p id="cty-result" class="op-muted" role="status"></p><p class="op-muted">DXCC country, continent and CQ/ITU zones come from AD1C\u2019s cty.dat (country-files.com), resolved as in WSJT-X. Update it here with a newer file; nothing is downloaded automatically.</p>');
  const show=v=>{const date=/^VER(\d{4})(\d{2})(\d{2})$/.exec(v.version??'');$('cty-status').textContent=`cty.dat ${date?`${date[1]}-${date[2]}-${date[3]}`:'version unknown'} \u00b7 ${v.source==='uploaded'?'uploaded':'bundled with this station'} \u00b7 ${v.entities} entities${v.upload_unreadable?' \u00b7 the uploaded file is unreadable, the bundled file is used':''}`;$('cty-bundled').disabled=v.source!=='uploaded';};
  const loadCty=()=>call('/dxcc').then(({response,data})=>{if(response.ok&&data?.v===1)show(data);}).catch(()=>{});
  const replace=async(text,label)=>{
    const s=station(),result=$('cty-result');if(!s){result.textContent='Station profile unavailable';return;}
    for(const id of ['cty-upload','cty-bundled'])$(id).disabled=true;
    try{
      const {response,data}=await call('/dxcc',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,...s,text}),timeout:30000});
      if(response.ok&&data?.v===1){show(data);result.textContent=label;}
      else result.textContent=data?.error?.code==='invalid_cty'?`Refused \u00b7 not a valid cty.dat (line ${data.error.line}); nothing changed`:`Refused \u00b7 ${data?.error?.code??response.status}; nothing changed`;
    }catch(error){result.textContent=`Outcome unknown \u00b7 ${error.message}`;}
    finally{$('cty-upload').disabled=false;loadCty();}
  };
  $('cty-upload').addEventListener('click',async()=>{
    const file=$('cty-file').files[0];
    if(!file){$('cty-result').textContent='Choose a cty.dat file first';return;}
    if(file.size===0||file.size>1048576){$('cty-result').textContent='Refused \u00b7 the file must hold 1 byte to 1 MiB';return;}
    replace(await file.text(),`Uploaded ${file.name}`);
  });
  $('cty-bundled').addEventListener('click',()=>replace(null,'Using the bundled cty.dat'));
  // Read only when Settings > General is shown, not at page load (Thin link).
  document.addEventListener('click',event=>{if(event.target.closest?.('#open-server-settings,#tab-general'))loadCty();},true);
  if($('settings-cty').getClientRects().length)loadCty();
}
// Annotate rows already shown when this client arrives.
if(activity)annotate(activity,resultRows);
})();
