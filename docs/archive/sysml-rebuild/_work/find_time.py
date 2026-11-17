import io, re, os, collections
root = 'docs/sysml'
pat = re.compile(r"\b(clock|UTC|SNTP|NTP|drift|period boundar|station time|system time|monotonic|DT\b|time source|time server|re-anchor|epoch|PeriodTiming|period start|period progress|slot boundar)", re.I)
decl = re.compile(r"^\s*(requirement|verification|attribute def|action def|state def|item def|enum def|part def|port def|interface def|calc def)\s+'?([A-Za-z0-9_-]+)'?[^\n]*\{", re.M)
rows = []
for d, _, fs in os.walk(root):
    for f in fs:
        if not f.endswith('.sysml'):
            continue
        p = os.path.join(d, f).replace(os.sep, '/')
        t = io.open(p, encoding='utf-8').read()
        key = p[len(root) + 1:]
        for m in decl.finditer(t):
            i = m.end(); depth = 1; j = i
            while j < len(t) and depth:
                if t[j:j + 2] == '/*':
                    e = t.find('*/', j)
                    j = len(t) if e < 0 else e + 2
                    continue
                if t[j] == '{': depth += 1
                elif t[j] == '}': depth -= 1
                j += 1
            body = t[i:j]
            hits = len(pat.findall(body))
            if hits >= 3 and m.group(1) != 'verification':
                rows.append((key, m.group(1).split()[0], m.group(2), hits, len(body)))
byf = collections.defaultdict(list)
for r in rows:
    byf[r[0]].append(r)
for k in sorted(byf, key=lambda k: -sum(r[3] for r in byf[k])):
    print(k)
    for r in sorted(byf[k], key=lambda r: -r[3])[:9]:
        print('   ', r[1], r[2], 'hits', r[3], 'chars', r[4])
