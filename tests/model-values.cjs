'use strict';
// The model-value reader of the JavaScript tests (Project-Specifics, "Model values read by
// tests"; CL-014-16). A contract test names a value the model holds as data by its qualified
// name `Package::Element(::Feature)*`, and this module finds it in the `.sysml` text at run
// time. It reads only the subset of that section and throws on anything else; the pinned
// Pilot of `tools/sysml.py check` validates the SysML itself. The Rust reader
// server/src/model_values.rs gives the same values and the same reasons. Node built-ins only.
const fs=require('node:fs'),path=require('node:path');

const UNIT_SUFFIXES='WstxUnits::UnitSuffix';
// Words that lead a declaration of a named element, and words that may stand before them.
const KINDS=new Set(['package','library','standard','part','attribute','enum','item','port','action','state','requirement','verification','constraint','calc','interface','connection','metadata','occurrence','flow','view','viewpoint','use','case','analysis','concern','allocation','rendering','def','actor','stakeholder','subject','objective','exhibit','perform','snapshot','timeslice','event','message']);
const MODIFIERS=new Set(['private','public','protected','abstract','readonly','derived','constant','ref','in','out','inout','end','variation','individual','nonunique','ordered','var','composite','portion']);
const PUNCT=[':>>','::',':>',':=','==','!=','<=','>=','..','->','=>'];

// A read failure: the qualified name asked for and the reason.
class ModelValueError extends Error{
  constructor(name,reason){super(`${name}: ${reason}`);this.name='ModelValueError';this.qualifiedName=name;this.reason=reason;}
}
const fail=(name,reason)=>{throw new ModelValueError(name,reason);};

// Tokens: {t:'word'|'quoted'|'str'|'num'|'punct'|'comment', v}.
function tokens(source){
  const text=source.replaceAll('\r\n','\n'),out=[];
  let i=0;
  const digit=c=>c!==undefined&&c>='0'&&c<='9';
  while(i<text.length){
    const c=text[i];
    if(/\s/.test(c))i++;
    else if(c==='/'&&text[i+1]==='/'){while(i<text.length&&text[i]!=='\n')i++;}
    else if(c==='/'&&text[i+1]==='*'){const e=text.indexOf('*/',i+2);i=e<0?text.length:e+2;out.push({t:'comment'});}
    else if(c==='"'||c==="'"){
      const start=i;i++;
      while(i<text.length){const d=text[i++];if(d==='\\')i++;else if(d===c)break;}
      out.push({t:c==='"'?'str':'quoted',v:text.slice(start,Math.min(i,text.length))});
    }else if(digit(c)){
      const start=i;while(digit(text[i]))i++;
      if(text[i]==='.'&&digit(text[i+1])){i++;while(digit(text[i]))i++;}
      if(text[i]==='e'||text[i]==='E'){const sign=text[i+1]==='+'||text[i+1]==='-'?1:0;if(digit(text[i+1+sign])){i+=1+sign;while(digit(text[i]))i++;}}
      out.push({t:'num',v:text.slice(start,i)});
    }else if(/[A-Za-z_]/.test(c)){
      const start=i;while(i<text.length&&/[A-Za-z0-9_]/.test(text[i]))i++;
      out.push({t:'word',v:text.slice(start,i)});
    }else{
      const p=PUNCT.find(p=>text.startsWith(p,i))??String.fromCodePoint(text.codePointAt(i));
      i+=p.length;out.push({t:'punct',v:p});
    }
  }
  return out;
}
const isP=(t,v)=>t?.t==='punct'&&t.v===v;
const isW=(t,v)=>t?.t==='word'&&t.v===v;
const nameOf=t=>t&&(t.t==='word'||t.t==='quoted')?t.v:null;

// The statements of the body toks[start..end): {head, body:[s,e]|null, doc}.
function statements(toks,start,end){
  const out=[];let i=start;
  while(i<end){
    if(toks[i].t==='comment'||isP(toks[i],';')){i++;continue;}
    if(isW(toks[i],'doc')||isW(toks[i],'comment')){
      const head=[];while(i<end&&toks[i].t!=='comment'&&!isP(toks[i],';'))head.push(toks[i++]);
      i++;out.push({head,body:null,doc:true});continue;
    }
    const head=[];let body=null,depth=0;
    while(i<end){
      const t=toks[i];
      if(t.t==='comment')i++;
      else if(isP(t,';')&&depth===0){i++;break;}
      else if(isP(t,'{')){
        const open=i;let braces=0;
        for(;i<end;i++){if(isP(toks[i],'{'))braces++;else if(isP(toks[i],'}')&&--braces===0)break;}
        body=[open+1,Math.min(i,end)];i++;break;
      }else if(isP(t,'}')){i++;break;}
      else{if(isP(t,'(')||isP(t,'['))depth++;else if(isP(t,')')||isP(t,']'))depth=Math.max(0,depth-1);head.push(t);i++;}
    }
    if(head.length||body)out.push({head,body,doc:false});
  }
  return out;
}

// What a statement declares: {kinds, name, redefinition, rest}.
function declaration(stmt){
  const head=stmt.head,decl={kinds:[],name:null,redefinition:false,rest:head.length};
  if(stmt.doc)return decl;
  let i=0;
  for(;;){
    if(head[i]?.t==='word'&&MODIFIERS.has(head[i].v))i++;
    else if(isP(head[i],'#')){i+=2;while(isP(head[i],'::'))i+=2;}
    else break;
  }
  while(head[i]?.t==='word'&&KINDS.has(head[i].v))decl.kinds.push(head[i++].v);
  if(!decl.kinds.length)return decl;
  if(isP(head[i],'<')){while(head[i]&&!isP(head[i],'>'))i++;i++;}
  const redefinition=isP(head[i],':>>')||isW(head[i],'redefines');
  if(redefinition)i++;
  const name=nameOf(head[i]);
  if(name!==null&&!isP(head[i+1],'::'))Object.assign(decl,{name,redefinition,rest:i+1});
  return decl;
}
const isAttribute=decl=>decl.kinds.length===1&&decl.kinds[0]==='attribute'&&decl.name!==null;

// A qualified name read from head[i..]: [name, index after it] or null.
function qualified(head,i){
  let name=nameOf(head[i]);if(name===null)return null;i++;
  while(isP(head[i],'::')){const next=nameOf(head[i+1]);if(next===null)return null;name+='::'+next;i+=2;}
  return [name,i];
}
// The type of an attribute declaration and the index after its type and multiplicity.
function declaredType(head,rest){
  let i=rest,type=null;
  if(isP(head[i],':')){const q=qualified(head,i+1);if(q)[type,i]=q;}
  if(isP(head[i],'[')){while(head[i]&&!isP(head[i],']'))i++;i++;}
  return [type,i];
}

// Literals: {kind:'number', integer:true|false, value} | {kind:'string', value} |
// {kind:'boolean', value} | {kind:'null'} | {kind:'enum', def, member}. A refusal is {error}.
function literal(toks){
  const number=(sign,raw)=>{
    const text=sign+raw;
    if(/^\d+$/.test(raw)){
      const n=Number(text);
      return Number.isSafeInteger(n)?{kind:'number',integer:true,value:n}:{error:'not one literal: an integer out of range'};
    }
    return {kind:'number',integer:false,value:Number(text)};
  };
  if(!toks.length)return {error:'value missing'};
  if(toks.length===1){
    const [t]=toks;
    if(t.t==='str'){try{const v=JSON.parse(t.v);if(typeof v==='string')return {kind:'string',value:v};}catch{}return {error:'not one literal: an unreadable string'};}
    if(t.t==='num')return number('',t.v);
    if(isW(t,'true')||isW(t,'false'))return {kind:'boolean',value:t.v==='true'};
    if(isW(t,'null'))return {kind:'null'};
  }
  if(toks.length===2&&(isP(toks[0],'-')||isP(toks[0],'+'))&&toks[1].t==='num')return number(toks[0].v,toks[1].v);
  const q=qualified(toks,0);
  if(q&&q[1]===toks.length&&q[0].includes('::')){const at=q[0].lastIndexOf('::');return {kind:'enum',def:q[0].slice(0,at),member:q[0].slice(at+2)};}
  const shape=toks.some(t=>isP(t,'+'))&&toks.some(t=>t.t==='str')?'a + join':isP(toks[0],'(')?'a list':toks.some(t=>isP(t,'['))?'a unit expression':'an expression';
  return {error:`not one literal: ${shape}`};
}

// The value of an attribute declaration: `= <literal>` after its name and type.
function attributeValue(stmt,decl){
  if(!isAttribute(decl))return {error:'not an attribute value'};
  const [,i]=declaredType(stmt.head,decl.rest);
  if(i>=stmt.head.length)return {error:'value missing'};
  if(!isP(stmt.head[i],'='))return {error:'not one literal: the declaration is not in the read form'};
  return literal(stmt.head.slice(i+1));
}

// Splits a qualified name at `::` outside quoted names.
function segments(name){
  const out=[''];let quoted=false;
  for(let i=0;i<name.length;i++){
    const c=name[i];
    if(c==="'")quoted=!quoted;
    else if(c===':'&&!quoted&&name[i+1]===':'){i++;out.push('');continue;}
    out[out.length-1]+=c;
  }
  return out;
}

// Whether name ends in suffix: its last characters are the suffix and the character before
// them is a lowercase letter or a digit.
const endsIn=(name,suffix)=>name.length>suffix.length&&name.endsWith(suffix)&&/[a-z0-9]/.test(name[name.length-suffix.length-1]);

function file(key,text){
  const toks=tokens(text);let pkg=null;
  for(let i=0;i<toks.length&&!pkg;i++){
    if(!isW(toks[i],'package')||toks[i+1]?.t!=='word')continue;
    let open=i+2;while(toks[open]?.t==='comment')open++;
    if(!isP(toks[open],'{'))continue;
    let j=open,braces=0;
    for(;j<toks.length;j++){if(isP(toks[j],'{'))braces++;else if(isP(toks[j],'}')&&--braces===0)break;}
    pkg={name:toks[i+1].v,start:open+1,end:j};
  }
  return {key,text,toks,pkg};
}

function readFiles(dir){
  let stat=null;try{stat=fs.statSync(dir);}catch{}
  if(!stat?.isDirectory())return {error:`model folder missing: ${dir}`};
  const found=[];
  try{
    const walk=at=>{
      for(const entry of fs.readdirSync(at,{withFileTypes:true})){
        const full=path.join(at,entry.name);
        if(entry.isDirectory())walk(full);
        else if(entry.isFile()&&entry.name.endsWith('.sysml'))found.push([path.relative(dir,full).split(path.sep).join('/'),full]);
      }
    };
    walk(dir);
  }catch(error){return {error:`model folder unreadable: ${dir}: ${error.message}`};}
  if(!found.length)return {error:`model folder holds no model file: ${dir}`};
  found.sort(([a],[b])=>a<b?-1:a>b?1:0);
  const files=[];
  for(const [key,full] of found){
    let bytes;try{bytes=fs.readFileSync(full);}catch(error){return {error:`model file unreadable: ${key}: ${error.message}`};}
    let text;try{text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);}catch{return {error:`model file not UTF-8: ${key}`};}
    files.push(file(key,text));
  }
  return {files};
}

function asNumberLiteral(name,value){
  if(value.kind==='null')return null;
  if(value.kind!=='number')fail(name,`value is ${kindOf(value)}, not a number`);
  return value.value;
}
const kindOf=v=>({number:'a number',string:'a string',boolean:'a Boolean',null:'null',enum:'an enumeration value'})[v.kind];
const asString=(name,v)=>v.kind==='string'?v.value:fail(name,`value is ${kindOf(v)}, not a string`);
const asBoolean=(name,v)=>v.kind==='boolean'?v.value:fail(name,`value is ${kindOf(v)}, not a Boolean`);
const asEnum=(name,v)=>v.kind==='enum'?[v.def,v.member]:fail(name,`value is ${kindOf(v)}, not an enumeration value`);

class Model{
  constructor(loaded){this.loaded=loaded;this.suffixList=undefined;}
  files(name){if(this.loaded.error)fail(name,this.loaded.error);return this.loaded.files;}
  packageFile(pkg,name){
    const holding=this.files(name).filter(f=>f.pkg?.name===pkg);
    if(!holding.length)fail(name,`no model file has the package ${pkg}`);
    if(holding.length>1)fail(name,`more than one model file has the package ${pkg}: ${holding.map(f=>f.key).join(', ')}`);
    return holding[0];
  }
  // The text of the model file whose package is pkg.
  packageText(pkg){return this.packageFile(pkg,pkg).text;}
  // This model with the file of pkg replaced by text (a damaged copy).
  withPackageText(pkg,text){
    const key=this.packageFile(pkg,pkg).key;
    return new Model({files:this.files(pkg).map(f=>f.key===key?file(f.key,text):f)});
  }
  resolve(name){
    const parts=segments(name);
    if(parts.length<2||parts.some(p=>!p))fail(name,'not a qualified name Package::Element');
    const f=this.packageFile(parts[0],name);
    let start=f.pkg.start,end=f.pkg.end;
    for(let k=1;k<parts.length;k++){
      const found=statements(f.toks,start,end).filter(s=>declaration(s).name===parts[k]);
      if(found.length>1)fail(name,`declared twice in one body: ${parts.slice(0,k+1).join('::')}`);
      if(!found.length)fail(name,`not declared: ${parts.slice(0,k+1).join('::')}`);
      if(k+1===parts.length)return {toks:f.toks,stmt:found[0]};
      if(!found[0].body)fail(name,`not declared: ${parts.slice(0,k+2).join('::')}`);
      [start,end]=found[0].body;
    }
  }
  // The literal value of an attribute.
  literal(name){
    const {stmt}=this.resolve(name),value=attributeValue(stmt,declaration(stmt));
    if(value.error)fail(name,value.error);
    return value;
  }
  string(name){return asString(name,this.literal(name));}
  boolean(name){return asBoolean(name,this.literal(name));}
  // An enumeration value: [the definition as written, the member].
  enumValue(name){return asEnum(name,this.literal(name));}
  // A number without a unit; null for null.
  number(name){return this.judge(name,this.literal(name),false);}
  // A number with its unit, named by its last segment; null for null.
  numberWithUnit(name){return this.judge(name,this.literal(name),true);}
  // The members of an enum def, in declaration order.
  enumMembers(name){
    const {toks,stmt}=this.resolve(name),decl=declaration(stmt);
    if(decl.kinds.join(' ')!=='enum def')fail(name,'not an enumeration definition');
    if(!stmt.body)return [];
    const members=[];
    for(const member of statements(toks,...stmt.body)){
      if(member.doc)continue;
      const h=member.head;
      const short=h.length===1?nameOf(h[0]):h.length===2&&isW(h[0],'enum')?nameOf(h[1]):null;
      const docOnly=!member.body||statements(toks,...member.body).every(m=>m.doc);
      if(short===null||!docOnly)fail(name,'not an enumeration member in the read form');
      members.push(short);
    }
    return members;
  }
  // The attribute usages declared directly in container (a package or a named element) and
  // typed by definition (its qualified name; a usage may name it short or qualified), in
  // declaration order.
  table(container,definition){
    let toks,start,end;
    if(segments(container).length===1){const f=this.packageFile(container,container);({toks}=f);({start,end}=f.pkg);}
    else{const r=this.resolve(container);toks=r.toks;[start,end]=r.stmt.body??[0,0];}
    const usages=[];
    for(const stmt of statements(toks,start,end)){
      const decl=declaration(stmt);
      if(!isAttribute(decl)||decl.redefinition)continue;
      const [type]=declaredType(stmt.head,decl.rest);
      if(type===null||(type!==definition&&!definition.endsWith('::'+type)))continue;
      const fields=stmt.body?statements(toks,...stmt.body).map(s=>[s,declaration(s)]).filter(([,d])=>isAttribute(d)).map(([s,d])=>[d.name,attributeValue(s,d)]):[];
      usages.push(new Usage(this,`${container}::${decl.name}`,decl.name,fields));
    }
    if(!usages.length)fail(container,`table has no usage of ${definition}`);
    return usages;
  }
  suffixes(){
    if(this.suffixList===undefined){
      try{
        const members=this.enumMembers(UNIT_SUFFIXES);
        this.suffixList=members.length?{members}:{error:`unit suffixes: ${UNIT_SUFFIXES} has no member`};
      }catch(error){
        if(!(error instanceof ModelValueError))throw error;
        this.suffixList={error:`unit suffixes: ${UNIT_SUFFIXES}: ${error.reason}`};
      }
    }
    return this.suffixList;
  }
  judge(name,value,withUnit){
    const number=asNumberLiteral(name,value),list=this.suffixes();
    if(list.error)fail(name,list.error);
    const last=segments(name).pop(),hasUnit=list.members.some(s=>endsIn(last,s));
    if(withUnit&&!hasUnit)fail(name,'unit suffix not on the list');
    if(!withUnit&&hasUnit)fail(name,'value has a unit; read it with its unit');
    return number;
  }
}

class Usage{
  constructor(model,qualifiedName,name,fields){this.model=model;this.qualified=qualifiedName;this.name=name;this.fields=fields;}
  // The names of the attributes the usage's own body declares, in order.
  fieldNames(){return this.fields.map(([n])=>n);}
  literal(field){
    const name=`${this.qualified}::${field}`,found=this.fields.filter(([n])=>n===field);
    if(!found.length)fail(name,`not declared: ${name}`);
    if(found.length>1)fail(name,`declared twice in one body: ${name}`);
    if(found[0][1].error)fail(name,found[0][1].error);
    return found[0][1];
  }
  string(field){return asString(`${this.qualified}::${field}`,this.literal(field));}
  boolean(field){return asBoolean(`${this.qualified}::${field}`,this.literal(field));}
  enumValue(field){return asEnum(`${this.qualified}::${field}`,this.literal(field));}
  number(field){return this.model.judge(`${this.qualified}::${field}`,this.literal(field),false);}
  numberWithUnit(field){return this.model.judge(`${this.qualified}::${field}`,this.literal(field),true);}
}

// The model folder docs/sysml of this checkout.
const modelDir=path.join(__dirname,'..','docs','sysml');
// The model files below dir (default: this checkout's model). A folder that cannot be read
// fails every read.
const openModel=(dir=modelDir)=>new Model(readFiles(dir));

module.exports={openModel,modelDir,ModelValueError};
