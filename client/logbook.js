'use strict';
// CR #10 contact log (WstxContact::OfferLogReview, SaveContact, ContactHistory, ImportAdi,
// ExportAdi, WorkedBeforeQuery). The server owns the log, its identities, times and
// worked-before status; this browser renders confirmed responses and sends requests.
(()=>{
const region=document.querySelector('#region-logbook .op-secondary-body');
if(!region)return;
for(const node of [...region.childNodes].slice(1))node.remove();
region.querySelector('p').textContent='Contacts saved in this station profile\u2019s contacts.adi (ADIF 3.1.8). History is read-only.';
const fieldDefinitions=[['call','DX call'],['gridsquare','DX grid'],['rst_sent','Report sent'],['rst_rcvd','Report received'],['qso_date','Date on (UTC, YYYYMMDD)'],['time_on','Time on (UTC, HHMMSS)'],['qso_date_off','Date off (UTC, YYYYMMDD)'],['time_off','Time off (UTC, HHMMSS)'],['tx_pwr','Power (W)'],['comment','Comment']];
region.insertAdjacentHTML('beforeend',`<section id="log-review" hidden aria-labelledby="log-review-title"><h3 id="log-review-title">Log QSO</h3><p id="log-review-worked" role="status"></p><form id="log-review-form" novalidate>${fieldDefinitions.map(([key,label])=>`<label>${label}<input id="log-field-${key}" name="${key}" autocomplete="off" aria-describedby="log-error-${key}"></label><p id="log-error-${key}" class="log-field-error" role="alert"></p>`).join('')}<p id="log-review-fixed"></p><label class="op-check"><input type="checkbox" id="log-retain-power">Retain power for the next review</label><label class="op-check"><input type="checkbox" id="log-retain-comment">Retain comment for the next review</label><button type="submit" class="op-primary" id="log-review-save">Save contact</button> <button type="button" id="log-review-close">Close review</button><p id="log-review-result" role="status"></p></form></section><h3>Saved contacts</h3><p id="log-history-status" role="status">History not loaded</p><ol id="log-history"></ol><button type="button" id="log-history-older" disabled>Older contacts</button> <button type="button" id="log-history-newer" disabled>Newer contacts</button> <button type="button" id="log-history-refresh">Reload history</button><h3>ADIF interchange</h3><label>ADIF file (.adi)<input id="log-import-file" type="file" accept=".adi,.adif,text/plain"></label><button type="button" id="log-import">Import ADIF</button> <button type="button" id="log-export">Export ADIF</button><p id="log-import-status" role="status"></p>`);
const $=id=>document.getElementById(id);
for(const el of region.querySelectorAll('#log-history,#log-review-fixed,#log-import-status,#log-review-result'))el.style.overflowWrap='anywhere';
const uuid=()=>crypto.randomUUID();
const station=()=>profileData&&{profile_id:profileData.profile_id,boot_id:profileData.boot_id};
async function call(path,options={}){
  const response=await stationFetch(path,{...options,signal:AbortSignal.timeout(options.timeout??10000)});
  const type=response.headers.get('content-type')||'';
  const data=type.startsWith('application/json')?await response.json():null;
  return {response,data};
}
const statusText={worked_this_band_and_mode:'Worked before on this band and mode',worked_other_band_or_mode:'Worked before on another band or mode',not_worked:'Not worked before'};
const statusMark={worked_this_band_and_mode:'\u2713 worked',worked_other_band_or_mode:'\u25d0 worked other band/mode',not_worked:'\u2605 new'};
const statusColor={worked_this_band_and_mode:'#9fb8c9',worked_other_band_or_mode:'#dfb48e',not_worked:'#99e1c3'};
async function worked(band,mode,calls){
  const s=station();if(!s||!band||!calls.length)return null;
  const {response,data}=await call('/contact/worked',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,...s,band,mode,calls})});
  if(!response.ok||!Array.isArray(data?.statuses))throw new Error(data?.error?.code??'worked_unavailable');
  return new Map(data.statuses.map(entry=>[entry.call,entry.status]));
}

// ---------------------------------------------------------------- review
let review=null,retained={tx_pwr:null,comment:null},saving=false;
function input(key){return $(`log-field-${key}`);}
function clearErrors(){for(const [key] of fieldDefinitions){$(`log-error-${key}`).textContent='';input(key).removeAttribute('aria-invalid');}}
function openReview(prefill){
  review={record:{...prefill},commandId:null,outcome:'unsaved'};
  if($('log-retain-power').checked&&retained.tx_pwr!==null)review.record.tx_pwr=retained.tx_pwr;
  if($('log-retain-comment').checked&&retained.comment!==null)review.record.comment=retained.comment;
  for(const [key] of fieldDefinitions)input(key).value=review.record[key]??'';
  const r=review.record;
  $('log-review-fixed').textContent=`Mode ${r.submode??r.mode} \u00b7 Band ${r.band??'unknown'} \u00b7 Frequency ${r.freq===null||r.freq===undefined?'unconfirmed':r.freq+' MHz'} \u00b7 Station ${r.station_callsign}${r.my_gridsquare?' '+r.my_gridsquare:''} \u00b7 Contact ${r.contact_id}`;
  $('log-review-result').textContent='Unsaved';clearErrors();$('log-review').hidden=false;$('log-review-worked').textContent='Worked-before status unknown';
  showRegion('logbook');input('call').focus();
  const mode=r.mode==='MFSK'?r.submode:r.mode;
  worked(r.band,mode,[r.call]).then(map=>{if(map&&review?.record.contact_id===r.contact_id)$('log-review-worked').textContent=statusText[map.get(r.call.toUpperCase())]??'Worked-before status unknown';}).catch(()=>{});
}
$('log-review-close').addEventListener('click',()=>{$('log-review').hidden=true;});
$('log-review-form').addEventListener('submit',async event=>{
  event.preventDefault();if(!review||saving)return;
  const s=station();if(!s){$('log-review-result').textContent='Not saved \u00b7 station profile unavailable';return;}
  const record={...review.record};
  for(const [key] of fieldDefinitions){const value=input(key).value.trim();record[key]=value===''?null:(key==='call'?value.toUpperCase():value);}
  clearErrors();saving=true;$('log-review-save').disabled=true;$('log-review-result').textContent='Saving \u00b7 waiting for the station';
  review.commandId=uuid();
  try{
    const {response,data}=await call('/contacts',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,...s,command_id:review.commandId,record})});
    if(response.status===201||response.status===200){
      review.outcome='saved';retained={tx_pwr:record.tx_pwr,comment:record.comment};
      $('log-review-result').textContent=data.outcome==='already_saved'?'Saved (this contact was already in the log)':'Saved to contacts.adi';
      loadHistory(null);
    }else{
      const code=data?.error?.code??'request_failed',field=data?.error?.field;
      const key=typeof field==='string'&&field.startsWith('record.')?field.slice(7):null;
      if(code==='log_invalid_field'&&key&&input(key)){input(key).setAttribute('aria-invalid','true');$(`log-error-${key}`).textContent='Invalid value';input(key).focus();}
      $('log-review-result').textContent=code==='log_conflict'?'Not saved \u00b7 this contact is already logged with different values':code==='storage_unavailable'?'Not saved \u00b7 storage unavailable \u00b7 retry saves the same contact once':`Not saved \u00b7 ${code}`;
    }
  }catch(error){$('log-review-result').textContent=`Save outcome unknown \u00b7 ${error.message} \u00b7 retry saves the same contact once`;}
  finally{saving=false;$('log-review-save').disabled=false;}
});

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

// ---------------------------------------------------------------- import / export
async function sha256(bytes){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(b=>b.toString(16).padStart(2,'0')).join('');}
$('log-import').addEventListener('click',async()=>{
  const status=$('log-import-status'),file=$('log-import-file').files[0],s=station();
  if(!file){status.textContent='Choose an ADIF file first';return;}
  if(!s){status.textContent='Station profile unavailable';return;}
  if(file.size===0||file.size>67108864){status.textContent='Import refused \u00b7 the file must hold 1 byte to 64 MiB';return;}
  $('log-import').disabled=true;
  try{
    const bytes=new Uint8Array(await file.arrayBuffer()),id=uuid();
    status.textContent='Checking file integrity';
    const reserve=await call('/contacts/imports',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({v:1,...s,import_id:id,total_bytes:bytes.length,sha256:await sha256(bytes)})});
    if(!reserve.response.ok)throw new Error(reserve.data?.error?.code??'import_unavailable');
    let last=reserve;
    for(let start=reserve.data.received_bytes;start<bytes.length;start+=16384){
      const chunk=bytes.subarray(start,Math.min(bytes.length,start+16384));
      last=await call(`/contacts/imports/${id}`,{method:'PUT',headers:{'Content-Type':'application/octet-stream','Content-Range':`bytes ${start}-${start+chunk.length-1}/${bytes.length}`},body:chunk});
      if(last.response.status===422)break;
      if(!last.response.ok)throw new Error(last.data?.error?.code??'import_failed');
      status.textContent=`Uploading \u00b7 ${last.data.received_bytes} of ${bytes.length} bytes`;
    }
    const view=last.response.status===422?(await call(`/contacts/imports/${id}`)).data:last.data;
    const counts=`${view.new} new, ${view.duplicate} duplicate, ${view.conflict} conflicting`;
    status.textContent=view.state==='completed'?`Imported \u00b7 ${counts}`:`Import failed \u00b7 no contacts were added \u00b7 ${view.error?.code??'unknown'}${view.error?.record!==null&&view.error?.record!==undefined?` in record ${view.error.record+1}`:''}${view.error?.field?` field ${view.error.field}`:''} \u00b7 ${counts}`;
    loadHistory(null);
  }catch(error){status.textContent=`Import outcome unknown \u00b7 ${error.message}`;}
  finally{$('log-import').disabled=false;}
});
$('log-export').addEventListener('click',async()=>{
  const status=$('log-import-status');
  try{
    const response=await stationFetch('/contacts/export.adi',{signal:AbortSignal.timeout(60000)});
    if(!response.ok)throw new Error((await response.json()).error?.code??'export_unavailable');
    const link=document.createElement('a');link.href=URL.createObjectURL(await response.blob());link.download='contacts.adi';link.hidden=true;document.body.append(link);link.click();link.remove();
    setTimeout(()=>URL.revokeObjectURL(link.href),10000);status.textContent='Exported contacts.adi';
  }catch(error){status.textContent=`Export unavailable \u00b7 ${error.message}`;}
});

// ---------------------------------------------------------------- Band Activity worked-before
// At most one query per published period with at most 64 distinct concrete calls.
let askedPeriod=null,answered=new Map();
function annotate(body,records){
  const band=operatingState?.selection?.band,mode=live?.job?.mode;
  const period=resultView?`${liveIdentity(live)}/${resultView.first_sequence}/${resultView.period_start_utc}`:null;
  const complete=resultView?.complete&&resultCursor>=resultView.next_sequence;
  const from=r=>r.status==='decoded'&&r.fields?.type==='standard'&&r.fields.from?.kind==='call'&&typeof r.fields.from.text==='string'?r.fields.from.text.toUpperCase():null;
  const decorate=()=>{for(const row of body.querySelectorAll('tr[data-sequence]')){const record=records.find(r=>String(r.sequence)===row.dataset.sequence),c=record&&from(record),status=c&&answered.get(c);const cell=row.lastElementChild;if(!cell||!status||cell.querySelector('.log-worked'))continue;const mark=document.createElement('span');mark.className='log-worked';mark.dataset.worked=status;mark.title=statusText[status];mark.textContent=` \u00b7 ${statusMark[status]}`;mark.style.color=statusColor[status];cell.append(mark);}};
  if(!period||!band||!['ft8','ft4'].includes(mode))return;
  if(period===askedPeriod){decorate();return;}
  if(!complete)return;
  const calls=[...new Set(records.map(from).filter(Boolean))].slice(0,64);
  askedPeriod=period;answered=new Map();if(!calls.length)return;
  worked(band,mode.toUpperCase(),calls).then(map=>{if(map&&askedPeriod===period){answered=map;decorate();}}).catch(()=>{});
}
window.wstxLogbook=Object.freeze({openReview,annotate,loadHistory});
})();
