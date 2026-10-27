"""Independent additive canonical-float fixture composer. No decoder is called."""
from __future__ import annotations
import argparse
import array
import hashlib
import importlib.util
import json
import math
import os
import uuid
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
BASE = Path(__file__).with_name('generate.py')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(case, output, composer, tables):
    assert case['rate_hz'] == 12000 and case['frames'] == 180000
    g, h = tables
    samples = [0.0]*case['frames']
    channels = []
    for signal in case['signals']:
        channel = composer.channel(signal['payload77'], signal['mode'], g, h)
        x = composer.signal(signal, channel, len(samples))
        drift = case['drift_hz_per_second']
        if drift:
            quadrature_spec = dict(signal, phase_radians=signal['phase_radians']+math.pi/2)
            y = composer.signal(quadrature_spec, channel, len(samples))
            for i in range(signal['start_frame'], signal['start_frame']+len(channel['tones'])*(1920 if signal['mode']=='ft8' else 576)):
                phase = math.pi*drift*((i-signal['start_frame'])/12000)**2
                x[i] = x[i]*math.cos(phase)+y[i]*math.sin(phase)
        samples = [a+b for a,b in zip(samples,x)]
        channels.append(channel)
    rng = composer.Noise(case['seed'])
    sigma = case['noise_std']
    if sigma:
        samples = [x+sigma*rng.gaussian() for x in samples]
    assert max(map(abs,samples))<1, 'no clipping permitted'
    fit = None
    quantization = case['quantization']
    if quantization == 'pcm16':
        samples = [round(x*32767)/32768 for x in samples]
    elif quantization == 'pcm16_best_fit_residual':
        assert sigma == 0 and case['drift_hz_per_second'] == 0 and len(case['signals']) == 1
        source = dict(case['signals'][0], amplitude=0.5, phase_radians=0)
        u = [2*x for x in composer.signal(source, channels[0], len(samples))]
        source['phase_radians'] = math.pi/2
        w = [2*x for x in composer.signal(source, channels[0], len(samples))]
        quantized = [round(x*32767)/32768 for x in samples]
        start=source['start_frame']
        end=start+len(channels[0]['tones'])*(1920 if source['mode']=='ft8' else 576)
        dot=lambda x,y: math.fsum(a*b for a,b in zip(x[start:end],y[start:end]))
        cc,ss,cs=dot(u,u),dot(w,w),dot(u,w)
        xc,xs=dot(u,quantized),dot(w,quantized)
        determinant=cc*ss-cs*cs
        assert determinant>1e-12*cc*ss
        a=(xc*ss-xs*cs)/determinant
        b=(xs*cc-xc*cs)/determinant
        samples=[x-a*c-b*d for x,c,d in zip(quantized,u,w)]
        tolerance=128*math.ulp(1.0)*math.sqrt(max(cc,ss)*dot(quantized,quantized))
        ru,rw=dot(samples,u),dot(samples,w)
        assert max(abs(ru),abs(rw))<=tolerance
        fit=dict(a=a,b=b,real_inner_product=ru,quadrature_inner_product=rw,double_tolerance=tolerance)

    else:
        assert quantization == 'float32'
    samples = array.array('f',(x*case['canonical_gain'] for x in samples))
    if sys.byteorder != 'little':
        samples.byteswap()
    if fit is not None:
        stored=list(samples)
        if sys.byteorder!='little':
            decoded=array.array('f'); decoded.frombytes(samples.tobytes());decoded.byteswap();stored=list(decoded)
        stored_tolerance=4*(2**-23)*math.sqrt(max(cc,ss)*dot(stored,stored))
        ru,rw=dot(stored,u),dot(stored,w)
        assert max(abs(ru),abs(rw))<=stored_tolerance
        fit.update(stored_real_inner_product=ru,stored_quadrature_inner_product=rw,float_tolerance=stored_tolerance)
    raw = samples.tobytes()
    digest = hashlib.sha256(raw).hexdigest()
    if 'samples_sha256' in case:
        assert digest == case['samples_sha256'], f"{case['id']}: independent samples differ from frozen hash"
    output.mkdir(parents=True,exist_ok=True)
    file = output/'samples.f32'
    if file.exists():
        assert sha(file) == digest, f"{case['id']}: cached samples changed"
    else:
        pending=file.with_name(file.name+'.pending-'+uuid.uuid4().hex)
        pending.write_bytes(raw)
        os.replace(pending,file)
    recipe={key:value for key,value in case.items() if key!='samples_sha256'}
    metadata = dict(case=recipe, samples_sha256=digest, composer_sha256=sha(Path(__file__)), base_composer_sha256=sha(BASE), channels=channels, best_fit=fit, format='finite mono f32 little-endian canonical12kHz', expected='fixed manifest only; not decoder output')
    record=output/'fixture.json'
    if record.exists():
        assert json.loads(record.read_text(encoding='utf-8'))==metadata, 'cached fixture metadata changed'
    else:
        record.write_bytes((json.dumps(metadata,indent=2)+'\n').encode('utf-8'))
    return digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--pin-hashes',action='store_true',help='Independent preparation before candidate execution only')
    args=parser.parse_args()
    manifest=ROOT/'synchronization-cases.json'
    document=json.loads(manifest.read_text(encoding='utf-8'))
    assert document['base_composer_sha256'] == sha(BASE)
    if not args.pin_hashes:
        assert document['generator_sha256'] == sha(Path(__file__))
    spec=importlib.util.spec_from_file_location('independent_base_composer',BASE)
    composer=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(composer)
    tables=composer.tables(ROOT/'protocol-data')
    assert len(document['cases'])==14
    for case in document['cases']:
        if not args.pin_hashes:
            assert 'samples_sha256' in case
        digest=generate(case,args.output/case['id'],composer,tables)
        if args.pin_hashes:
            case['samples_sha256']=digest
    if args.pin_hashes:
        document['generator_sha256']=sha(Path(__file__))
        manifest.write_bytes((json.dumps(document,indent=2)+'\n').encode('utf-8'))
    print(json.dumps(dict(cases=14,manifest_sha256=sha(manifest),composer_sha256=sha(Path(__file__)),status='independent canonical inputs; no decoder execution')))


if __name__=='__main__':
    main()
