'use strict';
// TC-018-001/002 prerequisite integrity; cost 2, offline local files and independent bytes.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const crypto=require('node:crypto');
const {openModel}=require('../../tools/test/node/model-values.cjs');
// A bound of the profile's recordings, WstxRecordingTransfer::RecordingLimits, read from the model.
const recordingLimit=feature=>openModel().numberWithUnit(`WstxRecordingTransfer::RecordingLimits::${feature}`);
// Hand-parsed RIFF header: walks the chunks, independent of the server's and the setup tool's parsers.
function riff(bytes){
  assert.equal(bytes.toString('latin1',0,4),'RIFF');assert.equal(bytes.toString('latin1',8,12),'WAVE');
  const chunks={};
  for(let at=12;at+8<=bytes.length;){const id=bytes.toString('latin1',at,at+4),size=bytes.readUInt32LE(at+4);assert.ok(at+8+size<=bytes.length,`chunk ${id} within the file`);chunks[id]??={at:at+8,size};at+=8+size+(size&1);}
  assert.ok(chunks['fmt ']&&chunks['fmt '].size>=16,'fmt chunk');assert.ok(chunks.data,'data chunk');
  const fmt=chunks['fmt '].at;
  return {format:bytes.readUInt16LE(fmt),channels:bytes.readUInt16LE(fmt+2),rate:bytes.readUInt32LE(fmt+4),bits:bytes.readUInt16LE(fmt+14),data:chunks.data.size};
}
// Proves: TC-018-001
test('TC-018-001 all 22 FT8 and 3 FT4 originals match provenance and fit the PCM capability',{timeout:10000},async()=>{
  const {execFileSync}=require('node:child_process');
  const common=path.resolve(execFileSync('git',['rev-parse','--git-common-dir'],{encoding:'utf8',windowsHide:true}).trim());
  const samples=process.env.WSTX_SAMPLE_DIR || path.join(common,'harness-parallel','resources','issue-7','downloads');
  const ft8=JSON.parse(await fs.readFile(path.join(__dirname,'..','..','fixtures/decoder/manifest.json'),'utf8'));
  const ft4=JSON.parse(await fs.readFile(path.join(__dirname,'..','..','fixtures/decoder/ft4-manifest.json'),'utf8'));
  const inputs=[...ft8.files.filter(f=>f.path.endsWith('.wav')).map(f=>({...f,file:path.join(samples,path.basename(f.path))})),...ft4.files.map(f=>({...f,file:path.join(samples,'ft4',f.relative_download_path)}))];
  assert.equal(inputs.length,25,'22 FT8 and 3 FT4 originals');
  const importCap=recordingLimit('fileBytes'),rate=recordingLimit('rateHz');
  for(const input of inputs){
    const bytes=await fs.readFile(input.file).catch(error=>{if(error.code==='ENOENT')throw Error('Missing recording fixtures. Run node tools/recording-fixtures.cjs --directory <absolute-cache-directory> and set WSTX_SAMPLE_DIR to that directory.');throw error;});
    assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),input.sha256,input.file);
    const header=riff(bytes);
    assert.deepEqual({format:header.format,channels:header.channels,rate:header.rate,bits:header.bits},{format:1,channels:1,rate,bits:16},input.file);
    assert.ok(header.data>0&&header.data<=importCap&&bytes.length<=importCap,`${input.file}: data ${header.data} bytes within the import cap`);
  }
});
