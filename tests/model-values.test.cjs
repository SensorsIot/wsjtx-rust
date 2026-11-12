'use strict';
// The JavaScript model-value reader on the fixture tree tests/fixtures/model-values/
// (TC-DOC-014), against the hand-written list of expected values there. Node only.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {openModel,ModelValueError}=require('./model-values.cjs');

const fixture=path.join(__dirname,'fixtures','model-values');
const expected=()=>JSON.parse(fs.readFileSync(path.join(fixture,'expected.json'),'utf8'));

// Copies from to to, every file with the line ends eol.
function copyTree(from,to,eol){
  fs.mkdirSync(to,{recursive:true});
  for(const entry of fs.readdirSync(from,{withFileTypes:true})){
    const source=path.join(from,entry.name),target=path.join(to,entry.name);
    if(entry.isDirectory())copyTree(source,target,eol);
    else fs.writeFileSync(target,fs.readFileSync(source,'utf8').replaceAll('\r\n','\n').replaceAll('\n',eol));
  }
}

// The fixture tree in a scratch folder, with line ends eol and the changes change.
function tree(t,eol,change){
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'wstx-model-values-'));
  t.after(()=>fs.rmSync(scratch,{recursive:true,force:true}));
  const root=path.join(scratch,'model');
  if(change?.folder==='missing')return root;
  if(change?.folder==='empty'){fs.mkdirSync(root);return root;}
  assert.equal(change?.folder,undefined,'unknown folder change');
  copyTree(path.join(fixture,expected().tree),root,eol);
  for(const file of change?.remove??[])fs.rmSync(path.join(root,file));
  const write=(file,data)=>{fs.mkdirSync(path.dirname(path.join(root,file)),{recursive:true});fs.writeFileSync(path.join(root,file),data);};
  for(const [file,text] of Object.entries(change?.write??{}))write(file,text);
  for(const [file,hex] of Object.entries(change?.writeBytes??{}))write(file,Buffer.from(hex,'hex'));
  return root;
}

// The expected value of the list in the form the reader gives it.
function want(expect){
  const [[kind,value]]=Object.entries(expect);
  return kind==='integer'||kind==='real'?{kind:'number',integer:kind==='integer',value}:kind==='null'?{kind:'null'}:kind==='enum'?{kind:'enum',def:value[0],member:value[1]}:{kind,value};
}

// Reads name in the way read names, as {kind,...}: numbers through the unit rule.
function read(model,name,how){
  const number=value=>{
    const raw=model.literal(name);
    return value===null?{kind:'null'}:{kind:'number',integer:raw.integer,value};
  };
  switch(how){
    case 'plain':return number(model.number(name));
    case 'unit':return number(model.numberWithUnit(name));
    case 'string':return {kind:'string',value:model.string(name)};
    case 'boolean':return {kind:'boolean',value:model.boolean(name)};
    case 'enum':{const [def,member]=model.enumValue(name);return {kind:'enum',def,member};}
  }
  throw new Error(`unknown read ${how}`);
}
function readField(usage,field,how){
  const number=value=>value===null?{kind:'null'}:{kind:'number',integer:usage.literal(field).integer,value};
  if(how==='plain')return number(usage.number(field));
  if(how==='unit')return number(usage.numberWithUnit(field));
  if(how==='string')return {kind:'string',value:usage.string(field)};
  throw new Error(`unknown field read ${how}`);
}

// Every value, member list and table of the list, read from the tree with line ends eol.
function accepted(t,eol){
  const list=expected(),model=openModel(tree(t,eol));let count=0;
  for(const c of list.values){assert.deepEqual(read(model,c.name,c.read),want(c.expect),c.name);count++;}
  for(const c of list.members){assert.deepEqual(model.enumMembers(c.name),c.expect,c.name);count++;}
  for(const c of list.tables){
    const usages=model.table(c.container,c.definition);
    assert.deepEqual(usages.map(u=>u.name),c.expect.map(u=>u.name),`${c.container} table of ${c.definition}`);
    usages.forEach((usage,i)=>{
      const fields=c.expect[i].fields;
      assert.deepEqual(usage.fieldNames(),fields.map(([name])=>name),usage.qualified);
      for(const [name,how,expect] of fields){assert.deepEqual(readField(usage,name,how),want(expect),`${usage.qualified}::${name}`);count++;}
    });
  }
  return count;
}

// Proves: CL-014-16; TC-DOC-014 (the JavaScript reader accepts every value of the fixture list).
test('model values: every fixture value is read, in LF and CRLF',t=>{
  const lf=accepted(t,'\n'),crlf=accepted(t,'\r\n');
  assert.ok(lf>0,'the fixture list names no value');
  assert.equal(lf,crlf);
});

// Proves: CL-014-16; TC-DOC-014 (the JavaScript reader refuses every fault of the fixture list).
test('model values: every fixture fault is refused naming the name and the reason',t=>{
  const cases=expected().refused;
  assert.ok(cases.length>0,'the fixture list names no fault');
  for(const eol of ['\n','\r\n']){
    for(const c of cases){
      const model=openModel(tree(t,eol,c.tree));
      const name=c.table?c.table.container:c.name;
      assert.throws(()=>c.table?model.table(c.table.container,c.table.definition):read(model,c.name,c.read),error=>{
        assert.ok(error instanceof ModelValueError,`${name}: ${error}`);
        assert.equal(error.qualifiedName,name,error.message);
        assert.ok(error.reason.includes(c.reason),`${name}: reason ${JSON.stringify(error.reason)}, expected ${JSON.stringify(c.reason)}`);
        return true;
      },`${name}: accepted, expected ${c.reason}`);
    }
  }
});
