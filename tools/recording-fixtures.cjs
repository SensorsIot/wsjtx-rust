'use strict';
// Explicit prerequisite acquisition. Offline tests never call this downloader.
const fs=require('node:fs/promises');
const path=require('node:path');
const crypto=require('node:crypto');
const {execFileSync}=require('node:child_process');
const repository=path.resolve(__dirname,'..');
const limit=4*1024*1024;
function safeName(name){return typeof name==='string'&&name.split('/').every(p=>p.length<=128&&/^[a-zA-Z0-9_.-]+$/.test(p)&&!p.endsWith('.')&&!/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)/i.test(p));}
async function cachePath(directory){
  if(!directory||!path.isAbsolute(directory))throw Error('Choose an absolute cache directory outside a Git working tree.');
  const target=path.resolve(directory);if(path.dirname(target)===target)throw Error('Filesystem root is not a fixture cache.');
  if(target===repository||target.startsWith(repository+path.sep))throw Error('Audio cache must be outside a Git working tree.');
  let existing=target;
  while(true){try{const s=await fs.lstat(existing);if(s.isSymbolicLink()||!s.isDirectory())throw Error('Cache path must contain only ordinary directories.');}catch(e){if(e.code!=='ENOENT')throw e;}
    if(path.dirname(existing)===existing)break;existing=path.dirname(existing);
  }
  existing=target;while(true){try{await fs.stat(existing);break;}catch(e){if(e.code!=='ENOENT')throw e;existing=path.dirname(existing);}}
  let inside=false;try{inside=execFileSync('git',['-C',existing,'rev-parse','--is-inside-work-tree'],{encoding:'utf8',stdio:['ignore','pipe','ignore'],windowsHide:true}).trim()==='true';}catch(error){if(error.code==='ENOENT')throw Error('Git is required to verify the cache is outside working trees.');}
  if(inside)throw Error('Audio cache must be outside a Git working tree.');return target;
}
function verify(entry,bytes){
  if(bytes.length!==entry.bytes||crypto.createHash('sha256').update(bytes).digest('hex')!==entry.sha256)throw Error(`Pinned size/hash mismatch: ${entry.name}`);
  if(!entry.frames)return;
  if(bytes.length<12||bytes.toString('ascii',0,4)!=='RIFF'||bytes.toString('ascii',8,12)!=='WAVE'||bytes.readUInt32LE(4)+8!==bytes.length)throw Error(`Invalid WAV: ${entry.name}`);
  let offset=12,count=0,format=false,frames;
  while(offset<bytes.length){
    if(offset+8>bytes.length||++count>64)throw Error(`Invalid WAV chunks: ${entry.name}`);
    const type=bytes.toString('ascii',offset,offset+4),size=bytes.readUInt32LE(offset+4),start=offset+8,end=start+size+(size%2);
    if(end>bytes.length)throw Error(`Truncated WAV: ${entry.name}`);
    if(type==='fmt '){if(format||frames!==undefined||![16,18].includes(size))throw Error(`Invalid WAV format: ${entry.name}`);format=true;
      if(bytes.readUInt16LE(start)!==1||bytes.readUInt16LE(start+2)!==1||bytes.readUInt32LE(start+4)!==12000||bytes.readUInt32LE(start+8)!==24000||bytes.readUInt16LE(start+12)!==2||bytes.readUInt16LE(start+14)!==16||(size===18&&bytes.readUInt16LE(start+16)!==0))throw Error(`Unsupported WAV: ${entry.name}`);
    }else if(type==='data'){if(!format||frames!==undefined||size===0||size%2)throw Error(`Invalid WAV data: ${entry.name}`);frames=size/2;}
    offset=end;
  }
  if(frames!==entry.frames||frames>1440000)throw Error(`WAV frame count mismatch: ${entry.name}`);
}
async function plan(){
  const files=await Promise.all(['manifest.json','ft4-manifest.json'].map(n=>fs.readFile(path.join(repository,'fixtures','decoder',n))));
  const [ft8,ft4]=files.map(b=>JSON.parse(b));
  if(ft8.schema_version!==1||ft4.schema_version!==1)throw Error('Unsupported fixture manifest.');
  const entries=[...ft8.files.filter(f=>f.path.endsWith('.wav')).map(f=>({...f,name:path.posix.basename(f.path),url:f.source_url})),...ft4.files.map(f=>({...f,name:'ft4/'+f.relative_download_path,url:f.source_url})),...ft4.documentation_files.filter(f=>f.file.startsWith('official-')).map(f=>({...f,name:'ft4/'+f.file})),
    {name:'ft8_lib-LICENSE.txt',url:`https://raw.githubusercontent.com/kgoba/ft8_lib/${ft8.source_commit}/LICENSE`,bytes:1069,sha256:'4c816505e73feef31f1ffafcf70d51e2aae65a88296e77d6c37715f31ce63230'},
    ...files.map((bytes,n)=>({name:`provenance/${n?'ft4':'ft8'}-manifest.json`,bytes:bytes.length,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),content:bytes}))];
  if(entries.filter(e=>e.frames).length!==25)throw Error('Expected 25 pinned WAV fixtures.');return entries;
}
async function download(entry){
  const url=new URL(entry.url);if(url.protocol!=='https:'||url.username||url.password)throw Error('Fixture URL must be public HTTPS.');
  const response=await fetch(url,{signal:AbortSignal.timeout(30000)});if(!response.ok)throw Error(`Fixture HTTP ${response.status}: ${entry.name}`);
  if(new URL(response.url).protocol!=='https:')throw Error('Fixture redirects must remain HTTPS.');
  const chunks=[];let length=0;
  for await(const chunk of response.body){length+=chunk.length;if(length>entry.bytes||length>limit)throw Error(`Oversized download: ${entry.name}`);chunks.push(chunk);}
  return Buffer.concat(chunks,length);
}
async function boundedRead(file,expected){
  const stat=await fs.lstat(file);if(!stat.isFile()||stat.isSymbolicLink()||stat.size!==expected)throw Error('Existing fixture is not the pinned ordinary file.');
  const handle=await fs.open(file,'r');try{const bytes=Buffer.alloc(expected+1);let length=0;while(length<bytes.length){const r=await handle.read(bytes,length,bytes.length-length,null);if(!r.bytesRead)break;length+=r.bytesRead;}return bytes.subarray(0,length);}finally{await handle.close();}
}
async function provision(directory,{verifyOnly=false,entries,fetchFile=download}={}){
  const root=await cachePath(directory);entries=entries||await plan();const names=new Set();
  for(const e of entries){if(!safeName(e.name)||names.has(e.name.toLowerCase())||!Number.isSafeInteger(e.bytes)||e.bytes<1||e.bytes>limit||!/^[0-9a-f]{64}$/.test(e.sha256))throw Error('Unsafe fixture manifest entry.');names.add(e.name.toLowerCase());}
  // Refuse changed existing files before starting any download.
  const missing=[];
  for(const e of entries){const file=path.join(root,...e.name.split('/'));await cachePath(path.dirname(file));try{verify(e,await boundedRead(file,e.bytes));}catch(error){if(error.code==='ENOENT')missing.push(e);else throw error;}}
  if(verifyOnly&&missing.length)throw Error('Missing fixtures; run node tools/recording-fixtures.cjs --directory <absolute-cache-directory>.');
  for(const e of missing){const bytes=e.content||await fetchFile(e);verify(e,bytes);const file=path.join(root,...e.name.split('/'));await fs.mkdir(path.dirname(file),{recursive:true});await cachePath(path.dirname(file));
    const temporary=path.join(path.dirname(file),'.'+crypto.randomUUID()+'.tmp');
    try{const handle=await fs.open(temporary,'wx',0o600);try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
      try{await fs.link(temporary,file);}catch(error){if(error.code!=='EEXIST')throw error;verify(e,await boundedRead(file,e.bytes));}
    }finally{await fs.unlink(temporary).catch(error=>{if(error.code!=='ENOENT')throw error;});}
  }
  return entries.length;
}
module.exports={cachePath,verify,plan,provision,download};
if(require.main===module){
  const args=process.argv.slice(2),verifyOnly=args.includes('--verify');const clean=args.filter(a=>a!=='--verify');
  if(clean.length!==2||clean[0]!=='--directory'){console.error('Usage: node tools/recording-fixtures.cjs --directory <absolute-cache-directory> [--verify]');process.exitCode=1;}
  else provision(clean[1],{verifyOnly}).then(n=>console.log(`Verified ${n} pinned fixture/provenance files.`)).catch(error=>{console.error(error.message);process.exitCode=1;});
}
