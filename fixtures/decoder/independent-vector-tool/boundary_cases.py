"""Data-only fixed field-boundary proposal; independent of production code."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root/'independent-vectors/manifest.json').read_text())
base = {x['id']: x for x in manifest['vectors'] if x['mode'] == 'ft8'}
cases = []

def field(family, start, width, rows):
    original = base[family]['payload77']
    for value, status, meaning in rows:
        payload = original[:start]+f'{value:0{width}b}'+original[start+width:]
        assert len(payload) == 77
        cases.append(dict(id=f'{family}-{start}-{width}-{value}', modes=['ft4','ft8'],
                          payload77=payload, field_offset=start, field_width=width,
                          raw_value=value, expected_status=status,
                          expected_changed_field=meaning,
                          oracle='QEX field/table definition; current boundary observations where recorded'))

field('standard-fixed',59,15,[(0,'decoded','grid AA00'),(32399,'decoded','grid RR99'),
 (32400,'invalid_payload','reserved'),(32401,'decoded','blank'),(32402,'decoded','RRR'),
 (32403,'decoded','RR73'),(32404,'decoded','73'),(32405,'decoded','report -30'),
 (32435,'decoded','report 0'),(32484,'decoded','report +49'),(32485,'decoded','report +50'),
 (32486,'decoded','report -50'),(32505,'decoded','report -31'),
 (32506,'invalid_payload','noncanonical alias'),(32767,'invalid_payload','noncanonical report')])
field('cq',0,28,[(0,'decoded','DE'),(1,'decoded','QRZ'),(2,'decoded','CQ'),
 (3,'decoded','CQ 000'),(1002,'decoded','CQ 999'),(1003,'invalid_payload','empty CQ modifier'),
 (1004,'decoded','CQ A'),(1029,'decoded','CQ Z'),(1030,'invalid_payload','CQ modifier hole'),
 (1031,'decoded','CQ AA'),(1510,'decoded','CQ RU'),(532443,'decoded','CQ ZZZZ'),
 (532444,'invalid_payload','reserved c28'),(2063591,'invalid_payload','reserved c28'),
 (2063592,'decoded','hash22=0'),(6257895,'decoded','hash22=4194303'),
 (6257896,'invalid_payload','base call has no prefix letter'),(268435455,'decoded','ZZ9ZZZ')])
field('free',0,71,[(0,'invalid_payload','all blank'),(42**13-1,'decoded','?'*13),
 (42**13,'invalid_payload','outside base42 domain'),(2**71-1,'invalid_payload','outside base42 domain')])
field('telemetry',0,71,[(0,'decoded','000000000000000000'),(2**71-1,'decoded','7FFFFFFFFFFFFFFFFF')])
field('rtty-state',61,13,[(0,'decoded','serial0'),(7999,'decoded','serial7999'),
 (8000,'invalid_payload','reserved'),(8001,'decoded','AL'),(8049,'decoded','WI'),
 (8065,'decoded','DC'),(8066,'invalid_payload','outside state table'),(8191,'invalid_payload','outside exchange domain')])
field('rtty-state',58,3,[(0,'decoded','report529'),(7,'decoded','report599')])
for family in ['fieldday6','fieldday17']:
    field(family,64,7,[(0,'invalid_payload','one-based section'),(1,'decoded','AB'),
      (75,'decoded','WCF'),(76,'decoded','WI'),(83,'decoded','WY'),(84,'decoded','DX'),
      (85,'invalid_payload','outside84 sections'),(127,'invalid_payload','outside sections')])
    field(family,61,3,[(0,'decoded','class A'),(5,'decoded','class F'),
      (6,'invalid_payload','reserved class'),(7,'invalid_payload','reserved class')])
    field(family,57,4,[(0,'decoded','transmitters1' if family=='fieldday6' else 'transmitters17'),
      (15,'decoded','transmitters16' if family=='fieldday6' else 'transmitters32')])
field('nonstd-fixed',0,12,[(0,'decoded','hash12=0'),(4095,'decoded','hash12=4095')])
field('nonstd-fixed',12,58,[(0,'invalid_payload','empty full call'),
 (38**11,'invalid_payload','outside11-character base38 domain'),(2**58-1,'invalid_payload','outside base38 domain')])
field('dxpedition-fixed',56,10,[(0,'decoded','hash10=0'),(1023,'decoded','hash10=1023')])
field('dxpedition-fixed',66,5,[(0,'decoded','report-30'),(31,'decoded','report+32')])
field('vhf-fixed',49,25,[(0,'decoded','AA00AA'),(18662399,'decoded','RR99XX'),
 (18662400,'invalid_payload','outside grid6'),(2**25-1,'invalid_payload','outside grid6')])
field('vhf-fixed',38,11,[(0,'decoded','serial0'),(2047,'decoded','serial2047')])
field('vhf-fixed',35,3,[(0,'decoded','report52'),(7,'decoded','report59')])
field('vhf-fixed',0,12,[(0,'decoded','hash12=0'),(4095,'decoded','hash12=4095')])
field('vhf-fixed',12,22,[(0,'decoded','hash22=0'),(4194303,'decoded','hash22=4194303')])
for value in [2,6,7]: field('free',71,3,[(value,'unsupported',f'n3={value}')])
for value in [6,7]: field('standard-fixed',74,3,[(value,'unsupported',f'i3={value}')])
(root/'payload-boundary-cases.json').write_text(json.dumps(dict(schema_version=1,
    status='Reviewable independent expectations; unexecuted against candidate; canonical aliases differ from permissive reference',
    cases=cases),indent=2),encoding='utf-8')
print(f'{len(cases)} fixed boundary payloads; {2*len(cases)} mode cases')
