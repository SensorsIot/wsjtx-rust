"""For each FR of the old model: the parts whose files hold the clauses derived from it.
Run from the repository root. Reads only."""
import collections
import glob
import io
import os
import re

home = {}
deps = collections.defaultdict(list)
for f in glob.glob('docs/sysml/**/*.sysml', recursive=True):
    t = io.open(f, encoding='utf-8').read()
    k = f.replace(os.sep, '/')[len('docs/sysml/'):]
    seg = k.split('/')
    if k.startswith('backend/operating/'):
        part = seg[2]
    elif k.startswith('backend/'):
        part = seg[1]
    else:
        part = seg[0]
    for m in re.finditer(r"requirement '(CL-[^']+)'", t):
        home[m.group(1)] = part
    for m in re.finditer(r"dependency \S+ from '(CL-[^']+)' to '(FR-\d+)'", t):
        deps[m.group(2)].append(m.group(1))
    for m in re.finditer(r"#derivation connection \{\s*end #original ::> '(FR-\d+)';((?:\s*end #derive ::> '[^']+';)+)", t):
        for c in re.findall(r"'(CL-[^']+)'", m.group(2)):
            deps[m.group(1)].append(c)
for fr in sorted(deps):
    c = collections.Counter(home.get(x, '?') for x in deps[fr])
    print(fr, dict(c.most_common()))
