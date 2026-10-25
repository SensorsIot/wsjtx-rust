'use strict';
// TC-018-001/002 prerequisite integrity; cost 2, offline local files and independent bytes.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const crypto=require('node:crypto');
const {provision,verify,plan}=require('../tools/recording-fixtures.cjs');
function wave(){const b=Buffer.alloc(46);b.write('RIFF');b.writeUInt32LE(38,4);b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(12000,24);b.writeUInt32LE(24000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(2,40);return b;}
const entry=b=>({name:'audio.wav',bytes:b.length,sha256:crypto.createHash('sha256').update(b).digest('hex'),frames:1,url:'https://example.invalid/pinned.wav'});
test('TC-018-001 fixture setup validates full pinned plan and atomic promotion without overwriting',{timeout:10000},async t=>{
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'wstx-fixture-setup-'));t.after(()=>fs.rm(dir,{recursive:true,force:true}));const bytes=wave(),e=entry(bytes);let downloads=0;
  assert.equal(await provision(dir,{entries:[e],fetchFile:async()=>{downloads++;return bytes;}}),1);assert.deepEqual(await fs.readFile(path.join(dir,e.name)),bytes);assert.equal(downloads,1);
  await provision(dir,{entries:[e],verifyOnly:true});await provision(dir,{entries:[e],fetchFile:async()=>{throw Error('must not fetch existing input');}});assert.equal(downloads,1);
  await fs.writeFile(path.join(dir,e.name),Buffer.alloc(bytes.length));await assert.rejects(provision(dir,{entries:[e],fetchFile:async()=>{downloads++;return bytes;}}),/hash mismatch/);assert.equal(downloads,1);
  assert.deepEqual(await fs.readdir(dir),['audio.wav']);const pinned=await plan();assert.equal(pinned.filter(e=>e.frames).length,25);assert.ok(pinned.some(e=>e.name==='ft8_lib-LICENSE.txt'));assert.ok(pinned.some(e=>e.name==='ft4/official-project-COPYING.txt'));
});
test('TC-018-002 fixture setup rejects traversal, repository writes, missing inputs and forged WAV capability',async t=>{
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'wstx-fixture-refusal-'));t.after(()=>fs.rm(dir,{recursive:true,force:true}));const bytes=wave(),e=entry(bytes);let fetched=false;
  await assert.rejects(provision(dir,{entries:[{...e,name:'../escape.wav'}]}),/Unsafe/);
  await assert.rejects(provision(process.cwd(),{entries:[e]}),/outside a Git/);
  await assert.rejects(provision(dir,{entries:[e],verifyOnly:true}),/Missing fixtures.*recording-fixtures/);
  const forged=wave();forged.writeUInt32LE(48000,24);assert.throws(()=>verify(entry(forged),forged),/Unsupported WAV/);
  await assert.rejects(provision(dir,{entries:[e],fetchFile:async()=>{fetched=true;return forged;}}),/hash mismatch/);assert.equal(fetched,true);assert.deepEqual(await fs.readdir(dir),[]);
  const elsewhere=await fs.mkdtemp(path.join(os.tmpdir(),'wstx-fixture-link-'));t.after(()=>fs.rm(elsewhere,{recursive:true,force:true}));await fs.symlink(elsewhere,path.join(dir,'linked'),'junction');await assert.rejects(provision(path.join(dir,'linked'),{entries:[e]}),/ordinary directories/);
});
