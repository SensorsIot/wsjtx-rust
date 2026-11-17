"""Text checks of the new model under docs/sysmlV2 (Foundation/1-Finished-Model.md, M8.3).

Usage:  python docs/sysmlV2/_work/check.py [-v] [path-prefix ...]
        -v lists every finding; a path prefix limits the files, e.g. backend/clock

It reads only; it changes nothing. Exit 0 when no finding, 1 otherwise.
"""
import io
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SKIP = ("Foundation", "_work")
LIMIT = 100

RULES = {
    "M2.1": "a model file the target tree does not name, or a target file that is missing",
    "M4.2": "an FR states a status, a code link or a test link",
    "M5.10": 'the word "user"',
    "M6.2a": "a clause without a subject",
    "M6.2b": "a satisfy outside Shack.sysml",
    "M6.4a": "a clause that is not one sentence",
    "M6.4b": "a clause without MUST, SHOULD or MAY",
    "M6.10": "a clause whose sentence names no element defined in its file",
    "M6.11": "a clause no use case step carries and that is not @Debugging",
    "M7.1": "a dependency",
    "M7.3": "a text that restates its own identity",
    "M7.4": "history in a text: a date, an issue number or a history word",
    "M7.5": "a name with an underscore, or a definition not in UpperCamelCase",
    "W100": "a line over 100 characters",
    "C1": "a comment in a model file (// or /* */ outside a doc)",
}

# The entry marker the model tools read (tools/sysml/README.md "Entry file"): the one comment
# a model file may hold, on the first line of Requirements.sysml.
ENTRY_MARKER = "// Canonical authority: SysML"


def comments(text):
    """Offsets of the comments outside strings and outside doc texts."""
    found, i, n = [], 0, len(text)
    while i < n:
        c, two = text[i], text[i:i + 2]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            i = j + 1
        elif two == "/*":
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            if not re.search(r"\bdoc\s*$", text[max(0, i - 40):i]):
                found.append(i)
            i = end
        elif two == "//":
            found.append(i)
            end = text.find("\n", i)
            i = n if end < 0 else end
        else:
            i += 1
    return found

HISTORY = re.compile(
    r"20\d\d-\d\d-\d\d|(?<![A-Za-z0-9])#\d+\b|\bformerly\b|\breplaces\b|\bNot delivered yet\b|\bNot automated yet\b"
    r"|\bremains\b|\bno longer\b|\boperator decision\b", re.I)
DECL = re.compile(
    r"^\s*(?:abstract\s+)?(?:part|attribute|item|action|state|enum|port|interface|calc|constraint|"
    r"metadata|occurrence)\s+(?:def\s+)?([A-Za-z_][A-Za-z0-9_]*)", re.M)
ELEMENT = re.compile(r"^\s*(requirement|verification)\s+(?:def\s+)?(?:<)?'((?:FR|CL|TC)-[^']+)'", re.M)


def target_files():
    path = os.path.join(ROOT, "_work", "files.md")
    names = set()
    for line in io.open(path, encoding="utf-8"):
        m = re.match(r"\| ([^| ]+\.sysml) \|", line)
        if m and "Old file" not in line:
            names.add(m.group(1))
        if line.startswith("# Old files"):
            break
    return names


def model_files():
    out = []
    for folder, dirs, files in os.walk(ROOT):
        rel = os.path.relpath(folder, ROOT).replace("\\", "/")
        if rel.split("/")[0] in SKIP:
            dirs[:] = []
            continue
        for name in files:
            if name.endswith(".sysml"):
                out.append(name if rel == "." else rel + "/" + name)
    return sorted(out)


def body_of(text, start):
    """The text between the braces that open at or after start, and its end offset."""
    i = text.find("{", start)
    if i < 0:
        return "", start
    depth, j, in_comment = 0, i, False
    while j < len(text):
        two = text[j:j + 2]
        if in_comment:
            if two == "*/":
                in_comment = False
                j += 1
        elif two == "/*":
            in_comment = True
            j += 1
        elif text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1:j], j
        j += 1
    return text[i + 1:], len(text)


def doc_of(body):
    m = re.search(r"doc\s*/\*(.*?)\*/", body, re.S)
    return re.sub(r"\s+", " ", m.group(1)).strip() if m else ""


def sentences(doc):
    parts = re.split(r"(?<=[.!?])\s+(?=[A-Z(\"'])", doc)
    return [p for p in parts if p.strip()]


NAMED = re.compile(r"\s*(?:abstract\s+)?(?:in\s+|out\s+|inout\s+)?"
                   r"(?:attribute|enum|item|part|port|action|ref|state|occurrence|connection|"
                   r"interface|flow|calc|constraint|metadata|use case)\s+(def\s+)?([A-Za-z]\w*)")


def check_file(key, findings):
    text = io.open(os.path.join(ROOT, key), encoding="utf-8").read()
    lines = text.split("\n")

    def add(rule, line, what):
        findings.append((rule, key, line, what))

    def line_of(offset):
        return text.count("\n", 0, offset) + 1

    for n, line in enumerate(lines, 1):
        if len(line) > LIMIT:
            add("W100", n, "%d characters" % len(line))
        if re.match(r"\s*dependency\b", line):
            add("M7.1", n, line.strip()[:70])
        if re.match(r"\s*satisfy\b", line) and key != "Shack.sysml":
            add("M6.2b", n, line.strip()[:70])
        if re.search(r"\busers?\b", line, re.I):
            add("M5.10", n, line.strip()[:70])
        d = NAMED.match(line)
        if d and ("_" in d.group(2) or (d.group(1) and not d.group(2)[0].isupper())):
            add("M7.5", n, line.strip()[:70])
        # A quoted value of an attribute or of a source reference names a version of a
        # source (MCP's versions are dates), not history.
        scan = line
        if re.search(r"\battribute\b[^=]*=|\breference\s*=", line):
            scan = re.sub(r'"[^"]*"', '""', line)
        m = HISTORY.search(scan)
        if m:
            add("M7.4", n, m.group(0))

    for offset in comments(text):
        if key == "Requirements.sysml" and offset == 0 and text.startswith(ENTRY_MARKER):
            continue
        add("C1", line_of(offset), text[offset:offset + 60].split("\n")[0])

    names = set(DECL.findall(text))
    for m in ELEMENT.finditer(text):
        kind, ident = m.group(1), m.group(2)
        body, _ = body_of(text, m.end())
        doc = doc_of(body)
        at = line_of(m.start())
        if ident in doc:
            add("M7.3", at, ident)
        if ident.startswith("FR-"):
            if re.search(r"@(Status|ImplementedIn|TestedBy)\b", body):
                add("M4.2", at, ident)
            continue
        if ident.startswith("CL-"):
            if not re.search(r"\bsubject\b", body):
                add("M6.2a", at, ident)
            count = len(sentences(doc))
            if count != 1:
                add("M6.4a", at, "%s: %d sentences" % (ident, count))
            if not re.search(r"\b(MUST|SHOULD|MAY)\b", doc):
                add("M6.4b", at, ident)
            if not any(re.search(r"\b%s\b" % re.escape(name), doc) for name in names):
                add("M6.10", at, ident)


def check_use_cases(files, findings):
    path = os.path.join(ROOT, "UseCases.sysml")
    if not os.path.exists(path):
        return
    carried = set(re.findall(r"requirement :> \w+::'(CL-[\d-]+)'", io.open(path, encoding="utf-8").read()))
    for key in files:
        if key == "UseCases.sysml":
            continue
        text = io.open(os.path.join(ROOT, key), encoding="utf-8").read()
        for m in re.finditer(r"^    requirement '(CL-[\d-]+)' \{(.*?)\n    \}", text, re.S | re.M):
            if m.group(1) not in carried and "@Debugging" not in m.group(2):
                line = text[:m.start()].count("\n") + 1
                findings.append(("M6.11", key, line, m.group(1)))


def main(argv):
    verbose = "-v" in argv
    prefixes = [a for a in argv if not a.startswith("-")]
    findings = []
    files = model_files()
    if not prefixes:
        target = target_files()
        for key in sorted(set(files) - target):
            findings.append(("M2.1", key, 0, "not in the target tree"))
        for key in sorted(target - set(files)):
            findings.append(("M2.1", key, 0, "missing"))
        check_use_cases(files, findings)
    for key in files:
        if prefixes and not any(key.startswith(p) for p in prefixes):
            continue
        check_file(key, findings)

    checked = [k for k in files if not prefixes or any(k.startswith(p) for p in prefixes)]
    print("Checked %d model files under docs/sysmlV2" % len(checked))
    for rule, text in RULES.items():
        hits = [f for f in findings if f[0] == rule]
        print("  %-6s %5d  %s" % (rule, len(hits), text))
        if verbose:
            for _, key, line, what in hits:
                print("           %s:%s  %s" % (key, line or "-", what))
    print("Findings: %d" % len(findings))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
