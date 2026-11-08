'use strict';
// TC-018-001/002 prerequisite integrity; cost 2, offline local files and independent bytes.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const crypto=require('node:crypto');
const {provision,verify,plan,download}=require('../tools/recording-fixtures.cjs');
function wave(){const b=Buffer.alloc(46);b.write('RIFF');b.writeUInt32LE(38,4);b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(12000,24);b.writeUInt32LE(24000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(2,40);return b;}
const entry=b=>({name:'audio.wav',bytes:b.length,sha256:crypto.createHash('sha256').update(b).digest('hex'),frames:1,url:'https://example.invalid/pinned.wav'});
test('TC-018-001 fixture setup validates full pinned plan and atomic promotion without overwriting',{timeout:10000},async t=>{
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'wstx-fixture-setup-'));t.after(()=>fs.rm(dir,{recursive:true,force:true}));const bytes=wave(),e=entry(bytes);let downloads=0;
  assert.equal(await provision(dir,{entries:[e],fetchFile:async()=>{downloads++;return bytes;}}),1);assert.deepEqual(await fs.readFile(path.join(dir,e.name)),bytes);assert.equal(downloads,1);
  await provision(dir,{entries:[e],verifyOnly:true});await provision(dir,{entries:[e],fetchFile:async()=>{throw Error('must not fetch existing input');}});assert.equal(downloads,1);
  await fs.writeFile(path.join(dir,e.name),Buffer.alloc(bytes.length));await assert.rejects(provision(dir,{entries:[e],fetchFile:async()=>{downloads++;return bytes;}}),/hash mismatch/);assert.equal(downloads,1);
  assert.deepEqual(await fs.readdir(dir),['audio.wav']);const pinned=await plan();assert.equal(pinned.filter(e=>e.frames).length,25);assert.ok(pinned.some(e=>e.name==='ft8_lib-LICENSE.txt'&&e.url==='https://raw.githubusercontent.com/kgoba/ft8_lib/9fec6ca39886edbf96f4f5e71edc76da5074e871/LICENSE'));assert.ok(pinned.some(e=>e.name==='ft4/official-project-COPYING.txt'));
});
// Import file cap of the recording contract (RecordingReceive fileBytes, CL-006-02).
const importCap=3145728;
// Hand-parsed RIFF header: walks the chunks, independent of the server's and the setup tool's parsers.
function riff(bytes){
  assert.equal(bytes.toString('latin1',0,4),'RIFF');assert.equal(bytes.toString('latin1',8,12),'WAVE');
  const chunks={};
  for(let at=12;at+8<=bytes.length;){const id=bytes.toString('latin1',at,at+4),size=bytes.readUInt32LE(at+4);assert.ok(at+8+size<=bytes.length,`chunk ${id} within the file`);chunks[id]??={at:at+8,size};at+=8+size+(size&1);}
  assert.ok(chunks['fmt ']&&chunks['fmt '].size>=16,'fmt chunk');assert.ok(chunks.data,'data chunk');
  const fmt=chunks['fmt '].at;
  return {format:bytes.readUInt16LE(fmt),channels:bytes.readUInt16LE(fmt+2),rate:bytes.readUInt32LE(fmt+4),bits:bytes.readUInt16LE(fmt+14),data:chunks.data.size};
}
// Proves: CL-006-01, CL-006-02; TC-018-001
test('TC-018-001 all 22 FT8 and 3 FT4 originals match provenance and fit the PCM capability',{timeout:10000},async()=>{
  const {execFileSync}=require('node:child_process');
  const common=path.resolve(execFileSync('git',['rev-parse','--git-common-dir'],{encoding:'utf8',windowsHide:true}).trim());
  const samples=process.env.WSTX_SAMPLE_DIR || path.join(common,'harness-parallel','resources','issue-7','downloads');
  const ft8=JSON.parse(await fs.readFile(path.join(__dirname,'..','fixtures/decoder/manifest.json'),'utf8'));
  const ft4=JSON.parse(await fs.readFile(path.join(__dirname,'..','fixtures/decoder/ft4-manifest.json'),'utf8'));
  const inputs=[...ft8.files.filter(f=>f.path.endsWith('.wav')).map(f=>({...f,file:path.join(samples,path.basename(f.path))})),...ft4.files.map(f=>({...f,file:path.join(samples,'ft4',f.relative_download_path)}))];
  assert.equal(inputs.length,25,'22 FT8 and 3 FT4 originals');
  for(const input of inputs){
    const bytes=await fs.readFile(input.file).catch(error=>{if(error.code==='ENOENT')throw Error('Missing recording fixtures. Run node tools/recording-fixtures.cjs --directory <absolute-cache-directory> and set WSTX_SAMPLE_DIR to that directory.');throw error;});
    assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),input.sha256,input.file);
    const header=riff(bytes);
    assert.deepEqual({format:header.format,channels:header.channels,rate:header.rate,bits:header.bits},{format:1,channels:1,rate:12000,bits:16},input.file);
    assert.ok(header.data>0&&header.data<=importCap&&bytes.length<=importCap,`${input.file}: data ${header.data} bytes within the import cap`);
  }
});
test('TC-018-002 fixture setup rejects traversal, repository writes, missing inputs and forged WAV capability',async t=>{
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'wstx-fixture-refusal-'));t.after(()=>fs.rm(dir,{recursive:true,force:true}));const bytes=wave(),e=entry(bytes);let fetched=false;
  for(const name of ['../escape.wav','CON.wav','sub/abc.','a\\b.wav'])await assert.rejects(provision(dir,{entries:[{...e,name}]}),/Unsafe/);
  await assert.rejects(provision(process.cwd(),{entries:[e]}),/outside a Git/);
  await assert.rejects(provision(dir,{entries:[e],verifyOnly:true}),/Missing fixtures.*recording-fixtures/);
  const forged=wave();forged.writeUInt32LE(48000,24);assert.throws(()=>verify(entry(forged),forged),/Unsupported WAV/);
  await assert.rejects(provision(dir,{entries:[e],fetchFile:async()=>{fetched=true;return forged;}}),/hash mismatch/);assert.equal(fetched,true);assert.deepEqual(await fs.readdir(dir),[]);
  const elsewhere=await fs.mkdtemp(path.join(os.tmpdir(),'wstx-fixture-link-'));t.after(()=>fs.rm(elsewhere,{recursive:true,force:true}));await fs.symlink(elsewhere,path.join(dir,'linked'),'junction');await assert.rejects(provision(path.join(dir,'linked'),{entries:[e]}),/ordinary directories/);
});
test('TC-018-002 fixture downloader refuses HTTP errors, downgrade redirects and oversized streams offline',async t=>{
  const original=global.fetch;t.after(()=>{global.fetch=original;});const e=entry(wave());let calls=0;
  global.fetch=async(_url,options)=>{calls++;assert.ok(options.signal instanceof AbortSignal);return {ok:false,status:403};};
  await assert.rejects(download(e),/HTTP 403/);
  await assert.rejects(download({...e,url:'http://example.invalid/audio.wav'}),/public HTTPS/);assert.equal(calls,1);
  global.fetch=async()=>({ok:true,url:'http://example.invalid/downgrade',body:[]});await assert.rejects(download(e),/remain HTTPS/);
  global.fetch=async()=>({ok:true,url:e.url,body:(async function*(){yield Buffer.alloc(e.bytes+1);})()});await assert.rejects(download(e),/Oversized download/);
});
