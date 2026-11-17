"""Is a part of the new model done?  (Foundation/3-Method.md, "What must hold for a finished part")

Usage, from the repository root:
    python docs/archive/sysml-rebuild/_work/part_done.py <part> [-v]

It runs five tests and prints one line each. It reads only.
  1 ledger    every identity of the part is accounted for
  2 rules     check.py finds nothing in the part's files
  3 valid     the pinned validator reports no error in the part's files
  4 code      the model and the code agree, both ways (values, enumerations, names)
  5 tests     every test case names a test that exists: a named test (path::name) is
              defined in its file, a whole file carries the case's number

The part's files and the verdicts on test 4 are in parts.json beside this script.
"""
import io
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
V2 = os.path.join(REPO, "docs", "sysml")
sys.path.insert(0, HERE)
import check  # noqa: E402

UNITS = {"ms": 1, "s": 1000, "seconds": 1000, "secs": 1000}
UNIT_TOKENS = set(UNITS) | {"db", "pct", "percent", "hz"}


def read(path):
    return io.open(path, encoding="utf-8").read()


def tokens(name):
    parts = re.findall(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+", name.replace("_", " "))
    return [p.lower() for p in parts]


def core(name):
    return frozenset(t for t in tokens(name) if t not in UNIT_TOKENS)


def unit(name):
    for t in reversed(tokens(name)):
        if t in UNITS:
            return UNITS[t]
    return None


def norm(name):
    return "".join(tokens(name))


# ---- the model ---------------------------------------------------------------------------

def model_facts(files):
    values, enums, modules, cases, idents = {}, {}, set(), [], set()
    for key in files:
        t = read(os.path.join(V2, key))
        for d in re.finditer(r"(?:attribute|item) def (\w+) \{", t):
            body, _ = check.body_of(t, d.start())
            for m in re.finditer(r"attribute (\w+) : (?:Integer|Real) = (-?\d+(?:\.\d+)?)", body):
                values["%s::%s" % (d.group(1), m.group(1))] = float(m.group(2))
        for m in re.finditer(r"enum def (\w+) \{(.*?)\n    \}", t, re.S):
            enums[m.group(1)] = re.findall(r"^\s*enum '?(\w+)'?;", m.group(2), re.M)
        for m in re.finditer(r"@ImplementedIn\s*\{\s*module\s*=\s*((?:\"[^\"]*\"\s*\+?\s*)+);", t):
            joined = "".join(re.findall(r"\"([^\"]*)\"", m.group(1)))
            modules.update(p.strip() for p in joined.split(";") if p.strip())
        for m in check.ELEMENT.finditer(t):
            idents.add(m.group(2))
            if m.group(1) == "verification":
                body, _ = check.body_of(t, m.end())
                tests = []
                for b in re.finditer(r"@TestedBy\s*\{\s*test\s*=\s*((?:\"[^\"]*\"\s*\+?\s*)+);", body):
                    joined = "".join(re.findall(r"\"([^\"]*)\"", b.group(1)))
                    tests += [p.strip() for p in joined.split(";") if p.strip()]
                cases.append((m.group(2), key, tests))
    return values, enums, sorted(modules), cases, idents


# ---- the code ----------------------------------------------------------------------------

def code_facts(modules):
    consts, enums, wire, env, missing = {}, {}, set(), set(), []
    for mod in modules:
        path = os.path.join(REPO, mod)
        if not os.path.isfile(path):
            missing.append(mod)
            continue
        t = read(path)
        for m in re.finditer(r"pub const (\w+): [^=;]+ = ([^;]+);", t):
            name, raw = m.group(1), m.group(2).strip()
            d = re.match(r"Duration::from_(secs|millis)\((\d[\d_]*)\)", raw)
            if d:
                consts[name] = (float(d.group(2).replace("_", "")), 1000 if d.group(1) == "secs" else 1)
            elif re.match(r"-?\d[\d_]*(\.\d+)?$", raw):
                consts[name] = (float(raw.replace("_", "")), unit(name))
        for m in re.finditer(r"pub enum (\w+) \{([^}]*)\}", t):
            enums[m.group(1)] = re.findall(r"^\s*(\w+)\s*[,({]?", m.group(2), re.M)
        wire.update(re.findall(r"=>\s*\"([a-z][a-z_]+)\"", t))
        env.update(re.findall(r"\"(WSTX_[A-Z_]+)\"", t))
    return consts, enums, wire, env, missing


def compare(part, mv, me, files, modules, verdicts):
    cv, ce, wire, env, missing = code_facts(modules)
    lines = []          # (kind, key, text)   kind: match | fail | open

    def put(kind, key, text):
        verdict = verdicts.get(key)
        if kind == "open" and verdict:
            lines.append(("verdict", key, text + "  -> " + verdict))
        else:
            lines.append((kind, key, text))

    for mod in missing:
        put("fail", "module " + mod, "the model names a module that does not exist: " + mod)

    def equal(name, value, cname):
        cval, cunit = cv[cname]
        munit = unit(name)
        return (value * (munit or 1) == cval * (cunit or 1)) if (munit or cunit) else value == cval

    used = set()
    for full, value in sorted(mv.items()):
        name = full.split("::")[-1]
        if "model value " + full in verdicts:
            # A written verdict says which constant matches; the name guess is not used.
            put("open", "model value " + full, "model value %s = %g" % (full, value))
            continue
        fits = []
        for cname in cv:
            a, b = core(name), core(cname)
            s = len(a & b) / float(len(a | b)) if a | b else 0
            if s >= 0.6:
                fits.append((equal(name, value, cname), s, cname))
        best = max(fits)[2] if fits else None
        score = 1.0 if fits else 0.0
        name = full
        if best and score >= 0.6:
            cval, cunit = cv[best]
            same = equal(full.split("::")[-1], value, best)
            used.add(best)
            if same:
                put("match", "value " + name, "%s = %g  ==  %s" % (name, value, best))
            else:
                put("fail", "value " + name, "%s = %g  but  %s = %g" % (name, value, best, cval))
        else:
            put("open", "model value " + name, "model value %s = %g has no constant in the code" % (name, value))
    for cname in sorted(set(cv) - used):
        put("open", "code const " + cname, "code constant %s = %g is not a value of the model" % (cname, cv[cname][0]))

    model_lits = {norm(l): (e, l) for e, ls in me.items() for l in ls}
    code_names = {}
    for e, vs in ce.items():
        for v in vs:
            code_names[norm(v)] = "%s::%s" % (e, v)
    for w in wire:
        code_names.setdefault(norm(w), 'wire name "%s"' % w)
    for n, (e, l) in sorted(model_lits.items()):
        if n in code_names:
            put("match", "literal %s::%s" % (e, l), "%s::%s  ==  %s" % (e, l, code_names[n]))
        else:
            put("open", "model literal %s::%s" % (e, l), "model literal %s::%s has no name in the code" % (e, l))
    for n, where in sorted(code_names.items()):
        if n not in model_lits:
            put("open", "code name " + where, "code %s is not a literal of the model" % where)

    text = " ".join(read(os.path.join(V2, k)) for k in files)
    for e in sorted(env):
        if e in text:
            put("match", "env " + e, "environment variable %s" % e)
        else:
            put("open", "code env " + e, "code reads %s; the model does not name it" % e)
    return lines


# ---- the five tests ----------------------------------------------------------------------

def test_ledger(part, files, idents):
    rows = []
    for line in read(os.path.join(HERE, "ledger.md")).split("\n"):
        c = [x.strip() for x in line.split("|")]
        if len(c) > 5 and re.match(r"(FR|CL|TC)-", c[1]):
            rows.append(c[1:6])
    mine, problems = [], []
    for ident, kind, old, target, arrived in rows:
        in_part = any(target.startswith(f) for f in files) or os.path.dirname(old) in (
            "backend/%s" % part, "backend/operating/%s" % part, part)
        if ident in idents or in_part:
            mine.append(ident)
            settled = arrived == "yes" or re.match(r"(handed over|not carried|retired)", target)
            if ident in idents and arrived != "yes":
                problems.append("%s stands in the part and the ledger does not say so" % ident)
            elif arrived == "yes" and ident not in idents and any(target.startswith(f) for f in files):
                problems.append("%s is marked arrived and is not in the part's files" % ident)
            elif not settled:
                problems.append("%s is not accounted for (%s)" % (ident, target or "no target"))
    known = {r[0] for r in rows}
    seen = set()
    for r in rows:
        if r[0] in seen and r[0] in mine:
            problems.append("%s has more than one row in the ledger" % r[0])
        seen.add(r[0])
    for ident in sorted(idents - known if isinstance(idents, set) else set(idents) - known):
        problems.append("%s stands in the part and has no row in the ledger" % ident)
    return problems, "%d identities" % len(mine)


def test_rules(files):
    findings = []
    for key in files:
        check.check_file(key, findings)
    return ["%s %s:%s %s" % f for f in findings], "%d files" % len(files)


def test_valid(files, extra):
    args = [os.path.join("docs", "sysml", f) for f in extra + files]
    try:
        out = subprocess.run([sys.executable, "tools/sysml.py", "validate"] + args, cwd=REPO,
                             capture_output=True, text=True, timeout=600)
    except Exception as e:  # the validator is a tool of the old tree; say so and go on
        return ["the validator could not run: %s" % e], ""
    problems = []
    for line in (out.stdout + out.stderr).split("\n"):
        if "ERROR" in line and any(f.replace("/", os.sep) in line or f in line for f in files):
            problems.append(line.strip())
    return problems, "%d files" % len(files)


def test_tests(cases):
    problems = []
    for ident, key, tests in cases:
        if not tests:
            problems.append("%s names no test" % ident)
        found = False
        for t in tests:
            path = os.path.join(REPO, t.split("::")[0])
            if not os.path.isfile(path):
                problems.append("%s names %s, which does not exist" % (ident, t))
            elif "::" in t:
                # A named test: the file defines it. The number in the file is not asked.
                name = t.split("::")[-1]
                if path.endswith((".cjs", ".js")):
                    # A JavaScript test is named by its title: test('title', ...).
                    pattern = r"\btest\(\s*['\"`]%s['\"`]" % re.escape(name)
                else:
                    pattern = r"\bfn %s\b" % re.escape(name)
                if re.search(pattern, read(path)):
                    found = True
                else:
                    problems.append("%s names %s, which the file does not define" % (ident, t))
            elif ident in read(path):
                found = True
        if tests and not found:
            problems.append("%s: none of its test files carries the number" % ident)
    return problems, "%d test cases" % len(cases)


def main(argv):
    verbose = "-v" in argv
    names = [a for a in argv if not a.startswith("-")]
    if not names:
        print(__doc__)
        return 2
    part = names[0]
    cfg = json.loads(read(os.path.join(HERE, "parts.json")))[part]
    files = cfg["files"]
    mv, me, modules, cases, idents = model_facts(files)
    results = []

    p, n = test_ledger(part, files, idents)
    results.append(("1 ledger", p, n))
    p, n = test_rules(files)
    results.append(("2 rules", p, n))
    p, n = test_valid(files, cfg.get("validate_with", []))
    results.append(("3 valid", p, n))
    lines = compare(part, mv, me, files, modules, cfg.get("verdicts", {}))
    fails = [t for k, _, t in lines if k == "fail"]
    opens = [t for k, _, t in lines if k == "open"]
    counts = "%d matched, %d with a verdict" % (
        sum(1 for k, _, _ in lines if k == "match"), sum(1 for k, _, _ in lines if k == "verdict"))
    results.append(("4 code", fails + ["no verdict: " + o for o in opens], counts))
    p, n = test_tests(cases)
    results.append(("5 tests", p, n))

    print("Part %s" % part)
    ok = True
    for name, problems, note in results:
        print("  %-9s %s  %s" % (name, "pass" if not problems else "FAIL (%d)" % len(problems), note))
        if problems:
            ok = False
            for x in problems[:None if verbose else 12]:
                print("              " + x)
    if verbose:
        print("  test 4 in full:")
        for kind, key, text in lines:
            print("    %-8s %s" % (kind, text))
    print("Done: tests 1 to 5 pass." if ok else "Not done.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
