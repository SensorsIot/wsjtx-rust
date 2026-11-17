import io, re, sys
f, names, n = sys.argv[1], sys.argv[2].split(','), int(sys.argv[3])
t = io.open('docs/sysml/' + f, encoding='utf-8').read()
for name in names:
    m = re.search(r"^\s*\S+(?: def)?\s+'?%s'?[^\n]*\{" % re.escape(name), t, re.M)
    if not m:
        print('##', name, 'NOT FOUND'); continue
    body = re.sub(r"\s+", " ", t[m.end():m.end() + n * 3])
    print('##', f, name); print(body[:n]); print()
