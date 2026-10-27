"""Independent Decimal80 exhaustive physical-metric oracles; never imports Rust."""
from decimal import Decimal, localcontext
from itertools import product
from pathlib import Path
import hashlib
import json
import struct

D = Decimal
GRAY = {"ft8": [0, 1, 3, 2, 5, 6, 4, 7], "ft4": [0, 1, 3, 2]}

def magnitude(rows, first, values, gray):
    re = sum((rows[first+j][gray[v]][0] for j,v in enumerate(values)), D(0))
    im = sum((rows[first+j][gray[v]][1] for j,v in enumerate(values)), D(0))
    return (re*re+im*im).sqrt()

def bitscores(rows, first, count, gray):
    width = 3 if len(gray)==8 else 2
    alternatives = [(values, magnitude(rows,first,values,gray)) for values in product(range(len(gray)),repeat=count)]
    result=[]
    for position in range(count*width):
        symbol,bit=divmod(position,width)
        maxima=[max(power for values,power in alternatives if (values[symbol]>>(width-1-bit))&1==value) for value in (0,1)]
        result.append((maxima[1]-maxima[0],max(maxima)))
    return result

def normalize(raw):
    mean=sum(raw)/len(raw); square=sum(x*x for x in raw)/len(raw)
    variance=square-mean*mean
    sigma=(variance if variance>0 else square).sqrt()
    if not sigma: return None
    return [-D("2.83")*x/sigma for x in raw]

def metrics(rows,mode):
    if mode=="ft8":
        raw=[[D(0)]*174 for _ in range(5)]
        for n in (1,2,3):
            for half,first in enumerate((7,43)):
                for k in range(0,29,n):
                    for bit,(value,maximum) in enumerate(bitscores(rows,first+k,n,GRAY[mode])):
                        index=87*half+3*k+bit
                        if index<174:
                            raw[n-1][index]=value
                            if n==1: raw[3][index]=value/maximum if maximum else D(0)
        for bit in range(174): raw[4][bit]=max((raw[i][bit] for i in range(3)),key=abs)
        return [normalize(row) for row in raw]
    raw=[[D(0)]*206 for _ in range(3)]
    for family,n in enumerate((1,2,4)):
        for first in range(0,104-n,n):
            for bit,(value,_) in enumerate(bitscores(rows,first,n,GRAY[mode])): raw[family][2*first+bit]=value
    raw[1][204:206]=raw[0][204:206]
    raw[2][200:204]=raw[1][200:204]
    raw[2][204:206]=raw[0][204:206]
    answer=[]
    for row in raw:
        normalized=normalize(row)
        answer.append(None if normalized is None else normalized[8:66]+normalized[74:132]+normalized[140:198])
    return answer

def rows_for(mode,kind):
    rows=[]
    for s in range(79 if mode=="ft8" else 103):
        row=[]
        for t in range(len(GRAY[mode])):
            if kind=="rational": re=D((17*s+11*t)%23-11)/8;im=D((13*s-5*t)%19-9)/16
            elif kind=="opposition":
                phase=((1,0),(-1,0),(0,1),(0,-1))[s%4];re=D(phase[0]*(t+1))/8;im=D(phase[1]*(t+1))/8
            else:
                selected=GRAY[mode][(s*3+1)%len(GRAY[mode])]
                re=D(1+(s%5))/4 if t==selected else D(0);im=D((s%3)-1)/8 if t==selected else D(0)
            row.append((re,im))
        rows.append(row)
    return rows

def f32(value): return struct.unpack("<f",struct.pack("<f",float(value)))[0]

def main():
    output=[]
    with localcontext() as context:
        context.prec=80
        for mode in ("ft8","ft4"):
            for kind in ("rational","opposition","basis"):
                rows=rows_for(mode,kind)
                expected=metrics(rows,mode)
                output.append(dict(id=mode+"-"+kind,mode=mode,rows=[[[float(re),float(im)]for re,im in row]for row in rows],expected_f32=[None if row is None else list(map(f32,row))for row in expected]))
    data=dict(producer_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),oracle="Decimal80 exhaustive Cartesian tone tuples; no candidate implementation or decoder called",cases=output)
    Path(__file__).resolve().parents[1].joinpath("physical-metric-cases.json").write_text(json.dumps(data,indent=2,allow_nan=False)+"\n",encoding="utf-8",newline="\n")
    print("Generated",len(output),"independent metric cases")
if __name__=="__main__": main()
