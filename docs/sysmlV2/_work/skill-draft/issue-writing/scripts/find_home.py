"""Where does a term live in a SysML model?

Usage:  python find_home.py <model root> <term> [<term> ...]
                            [--show] [--records <dir>] [--tests <dir>]

For each term (case-insensitive; quote a term with spaces) it lists, by file, the
definitions, clauses, test cases and named markers that declare it or mention it.
  --show           also print each matching line with its number
  --records <dir>  also search the text records under <dir> (.md, .csv): decisions,
                   handover lists, reports
  --tests <dir>    list the test files that carry the identities found
A folder of the model without any model file is reported, so that "nothing found" is not
mistaken for "nothing there yet". It reads only.
"""
import io
import os
import re
import sys

# A home is a definition, a clause, a test case or a named marker; a feature inside one
# is reported with it.
DECL = re.compile(
    r"^\s*(?:abstract\s+)?(?:"
    r"(part|attribute|item|action|state|enum|port|interface|calc|constraint|metadata)\s+def\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)"
    r"|(requirement|verification)\s+(?:def\s+)?<?'([^']+)'"
    r"|(metadata)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:)",
    re.M)
IDENT = re.compile(r"(?:FR|CL|TC)-\d+(?:-\d+)*")
SKIP = ("Foundation",)


def elements(text):
    out = []
    for m in DECL.finditer(text):
        kind = m.group(1) or m.group(3) or "marker"
        name = m.group(2) or m.group(4) or m.group(6)
        out.append((m.start(), kind, name))
    return out


def owner(decls, offset):
    best = None
    for start, kind, name in decls:
        if start <= offset:
            best = (kind, name)
        else:
            break
    return best


def take(argv, flag):
    if flag in argv:
        i = argv.index(flag)
        value = argv[i + 1]
        del argv[i:i + 2]
        return value
    return None


def main(argv):
    argv = list(argv)
    records = take(argv, "--records")
    tests = take(argv, "--tests")
    show = "--show" in argv
    args = [a for a in argv if not a.startswith("--")]
    if len(args) < 2:
        print(__doc__)
        return 2
    root, terms = args[0], args[1:]
    files, empty = [], []
    for folder, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if not d.startswith((".", "_")) and d not in SKIP]
        model = [n for n in names if n.endswith(".sysml")]
        files += [os.path.join(folder, n) for n in model]
        if not model and not dirs and folder != root:
            empty.append(os.path.relpath(folder, root).replace("\\", "/"))
    if empty:
        print("folders of the model without a model file (not built yet): " + ", ".join(sorted(empty)))
    found = set()
    for term in terms:
        pat = re.compile(re.escape(term), re.I)
        print("== %s" % term)
        hits = 0
        for path in sorted(files):
            text = io.open(path, encoding="utf-8").read()
            decls = elements(text)
            seen, lines = {}, []
            for m in pat.finditer(text):
                o = owner(decls, m.start()) or ("file", "(before the first element)")
                declared = bool(pat.search(o[1]))
                seen[o] = seen.get(o, False) or declared
                n = text.count("\n", 0, m.start()) + 1
                lines.append((n, text.split("\n")[n - 1].strip()))
            if not seen:
                continue
            print("  %s" % os.path.relpath(path, root).replace("\\", "/"))
            for (kind, name), declared in seen.items():
                print("      %-8s %-12s %s" % ("declares" if declared else "mentions", kind, name))
                if IDENT.fullmatch(name):
                    found.add(name)
                hits += 1
            if show:
                for n, line in sorted(set(lines)):
                    print("        %5d: %s" % (n, line[:150]))
        if not hits:
            print("  (no element)")
        if records:
            for folder, dirs, names in os.walk(records):
                for n in sorted(names):
                    if not n.endswith((".md", ".csv")):
                        continue
                    path = os.path.join(folder, n)
                    text = io.open(path, encoding="utf-8", errors="replace").read().split("\n")
                    got = [i + 1 for i, line in enumerate(text) if pat.search(line)]
                    if got:
                        rel = os.path.relpath(path, records).replace("\\", "/")
                        print("  record %s: lines %s%s" % (
                            rel, ", ".join(str(g) for g in got[:12]), " ..." if len(got) > 12 else ""))
    if tests and found:
        print("== tests that carry %s" % ", ".join(sorted(found)))
        for folder, dirs, names in os.walk(tests):
            dirs[:] = [d for d in dirs if d not in ("target", "node_modules", ".git")]
            for n in names:
                if not n.endswith((".rs", ".py", ".js", ".cjs", ".ts", ".php", ".sh")):
                    continue
                path = os.path.join(folder, n)
                try:
                    text = io.open(path, encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                got = sorted(i for i in found if i in text)
                if got:
                    print("  %s  %s" % (os.path.relpath(path, tests).replace("\\", "/"), " ".join(got)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
