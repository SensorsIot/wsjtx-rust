Ã¯Â»Â¿"""Independent preparation-only FT4/FT8 channel/PCM fixture composer.
Protocol: Franke/Somerville/Taylor, QEX July/August 2020 Ã‚Â§Ã‚Â§3Ã¢â‚¬â€œ5, Appendix A.
Input is fixed independently reviewed payload77, NOT production encoder output.
No WSJT-X/Hamlib source algorithms are imported. Python stdlib implementation.
Use: python generate.py --case case.json --out CASE_DIRECTORY --protocol-data DIR
"""
from __future__ import annotations
import argparse, array, hashlib, json, math, pathlib, re, sys, wave
MASK = '01001010010111101000100110110100101100001000101001111001010101011011111000101'
EXPECTED = {'generator.dat': '9c87ad79b96d3ba07fa83875d44d777312b00e0a1a64243d2ae49b64ab90db19', 'parity.dat': 'bfee9dee04bb7b59a45c8ee61f0dd524dc85d4de777a631a3d66511948c1075a'}

def tables(directory):
    for name, want in EXPECTED.items():
        assert hashlib.sha256((directory/name).read_bytes()).hexdigest() == want
    g = [list(map(int, s.strip())) for s in (directory/'generator.dat').read_text().splitlines() if re.fullmatch('[01]{91}', s.strip())]
    h = [list(map(int, s.split())) for s in (directory/'parity.dat').read_text().splitlines() if re.fullmatch(r'\s*\d+\s+\d+\s+\d+\s*', s)]
    assert len(g) == 83 and len(h) == 174
    return g, h

def channel(payload, mode, g, h, corrupt_crc=False):
    assert re.fullmatch('[01]{77}', payload) and mode in ('ft4','ft8')
    b = payload if mode == 'ft8' else ''.join(str(int(a)^int(z)) for a,z in zip(payload,MASK))
    rem = int(b+'0'*19, 2)
    for power in range(95,13,-1):
        if (rem >> power) & 1: rem ^= 0x6757 << (power-14)
    # A separate augmented bit-stream recurrence checks orientation and zero extension.
    feedback = 0
    for bit in b+'0'*19:
        feedback = feedback*2 + int(bit)
        if feedback & 0x4000: feedback ^= 0x6757
    assert feedback == rem
    if corrupt_crc: rem ^= 1
    crc = f'{rem:014b}'; message = list(map(int,b+crc))
    word = message + [sum(x*y for x,y in zip(row,message))%2 for row in g]
    syndrome = [0]*83
    for bit,rows in zip(word,h):
        for row in rows: syndrome[row-1] ^= bit
    assert not any(syndrome)
    stride = 3 if mode == 'ft8' else 2
    mapping = [0,1,3,2,5,6,4,7] if stride == 3 else [0,1,3,2]
    a = [mapping[int(''.join(map(str,word[i:i+stride])),2)] for i in range(0,174,stride)]
    if mode == 'ft8':
        s = [3,1,4,0,6,5,2]; tones = s+a[:29]+s+a[29:]+s
    else: tones = [0,0,1,3,2]+a[:29]+[1,0,2,3]+a[29:58]+[2,3,1,0]+a[58:]+[3,2,0,1,0]
    return dict(payload77=payload,channel_payload77=b,crc14=crc,codeword174=''.join(map(str,word)),tones=''.join(map(str,tones)),syndrome_zero=True,crc_intentionally_invalid=corrupt_crc)

class Noise:
    """Specified SplitMix64 state transition and Box-Muller; no library RNG defaults."""
    def __init__(self, seed): self.state = seed & ((1<<64)-1)
    def uniform(self):
        mask=(1<<64)-1; self.state=(self.state+0x9E3779B97F4A7C15)&mask
        z=self.state; z=((z^(z>>30))*0xBF58476D1CE4E5B9)&mask
        z=((z^(z>>27))*0x94D049BB133111EB)&mask; z ^= z>>31
        return ((z>>11)+0.5)/(1<<53)
    def gaussian(self):
        return math.sqrt(-2*math.log(self.uniform()))*math.cos(2*math.pi*self.uniform())

def signal(spec, result, total):
    mode=spec['mode']; ns=1920 if mode=='ft8' else 576; bt=2 if mode=='ft8' else 1
    tones=list(map(int,result['tones'])); n=len(tones)*ns
    start=spec['start_frame']; assert 0<=start and start+n<=total
    amplitude=spec['amplitude']; f0=spec['frequency_hz']; assert 0<amplitude<=0.5
    dev=[0.0]*n; span=2*ns; k=math.pi*math.sqrt(2/math.log(2)); duration=ns/12000
    pulse=[]
    for index in range(-span,span):
        t=(index+0.5)/ns
        pulse.append((math.erf(k*bt*(t+0.5))-math.erf(k*bt*(t-0.5)))/(2*duration))
    for j,tone in enumerate(tones):
        center=j*ns+ns//2
        for i in range(max(0,center-span),min(n,center+span)):
            dev[i] += tone*pulse[i-center+span]
    ramp=ns//8 if mode=='ft8' else ns
    rise=[0.5*(1-math.cos(math.pi*i/ramp)) for i in range(ramp)]
    phase=spec.get('phase_radians',0.0); output=[0.0]*total
    for i,d in enumerate(dev):
        phase += 2*math.pi*(f0+d)/12000
        envelope=rise[i] if i<ramp else rise[n-1-i] if i>=n-ramp else 1.0
        output[start+i]=amplitude*math.cos(phase)*envelope
    return output

def generate(case, output, protocol):
    assert case['rate_hz']==12000 and 1<=case['frames']<=1440000
    g,h=tables(protocol); out=[0.0]*case['frames']; vectors=[]
    for source in case['signals']:
        v=channel(source['payload77'],source['mode'],g,h,source.get('corrupt_crc',False))
        x=signal(source,v,len(out)); out=[a+b for a,b in zip(out,x)]; vectors.append(v)
    sigma=case.get('noise_std',0.0); rng=Noise(case.get('seed',0))
    if sigma: out=[x+sigma*rng.gaussian() for x in out]
    peak=max(map(abs,out)); assert peak<1, 'fixture would clip; amplitude/noise must be reduced'
    pcm=array.array('h',(round(x*32767) for x in out))
    if sys.byteorder!='little': pcm.byteswap()
    output.mkdir(parents=True,exist_ok=True); wav=output/'000000_000000.wav'
    with wave.open(str(wav),'wb') as file:
        file.setparams((1,2,12000,0,'NONE','not compressed')); file.writeframes(pcm.tobytes())
    record=dict(case=case,vectors=vectors,peak_real=peak,wav_sha256=hashlib.sha256(wav.read_bytes()).hexdigest(),generator_sha256=hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),runtime=dict(python=sys.version,platform=sys.platform),pcm_quantization='ties-to-even round(real*32767), signed16 LE; assert no clipping')
    (output/'fixture.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    return record

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--case',type=pathlib.Path,required=True); parser.add_argument('--out',type=pathlib.Path,required=True); parser.add_argument('--protocol-data',type=pathlib.Path,required=True); args=parser.parse_args()
    result=generate(json.loads(args.case.read_text(encoding='utf-8-sig')),args.out,args.protocol_data)
    print(json.dumps(dict(wav_sha256=result['wav_sha256'],vectors=len(result['vectors']))))
