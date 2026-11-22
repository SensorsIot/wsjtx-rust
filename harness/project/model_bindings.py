#!/usr/bin/env python3
"""The model bindings at a commit, as the harness gate reads them (gate.model_bindings,
harness/general/core/tools/candidate.py), for its binding check and its report-only
candidate selection.

    python harness/project/model_bindings.py --rev REV

It reuses tools/sysml.py: canonical_catalog (TR-10) reads the model files at REV (every
`*.sysml` at any depth below docs/sysml, listed as `docs/sysml/<key>`), and every
binding it resolves is recorded instead of checked (checking them is the
source-model-traces suite's job). A clause's implementation is the module of its own
`@ImplementedIn`; one it inherits from its part definition (TR-13) is not listed, and an
FR has none. A case's state is its `@Automation` run and method; `@DetailTests` are not
listed. A case binds a test in its `@TestedBy` by `path::name`, or by its file: the tests
there whose `Proves:` tag names the case (TR-14), or a JavaScript test whose name does.
A requirement's `digest` is the hash of its declaration without comments, `@Status` and
`@ImplementedIn`, white space folded: what it promises, not how far it is built. Its
`satisfied_by` is the part its `subject` names (M6.2, M6.3), for an FR the part of its
`satisfy` in Shack.sysml. A case is left to Accept (`accept`) when one of its `@TestLevel`
locations is real equipment: station or flexRadio. Its `levels` are its `@TestLevel` pairs, each
with `station` true where the test needs the station (the simulators or the real equipment:
station, simulator, flexRadio) and false on the development PC.
Prints the JSON that candidate.py describes.
"""
import argparse
import hashlib
import io
import json
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "harness" / "general" / "core" / "tools"))
import sysml          # noqa: E402
import reachability   # noqa: E402

MODELS = "docs/sysml"
# The build metadata of a requirement: how far it is built, not what it promises.
BUILD = re.compile(r"@\s*(?:\w+::)*(?:Status|ImplementedIn)\s*\{[^{}]*\}")
REAL_EQUIPMENT = {"station", "flexRadio"}


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, check=True).stdout


def extract(rev, into):
    """The models and the source roots at `rev`, written below `into`."""
    present = set(git("ls-tree", "--name-only", rev).decode().split())
    roots = [r for r in sysml.SOURCE_BINDING_ROOTS if r in present]
    data = git("archive", "--format=tar", rev, "--", *roots, f":(glob){MODELS}/**/*.sysml")
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        tar.extractall(into, filter="data")
    for r in sysml.SOURCE_BINDING_ROOTS:
        (into / r).mkdir(exist_ok=True)


def tests_for(case, binding, root):
    """[{path, name}] of the tests one binding of a verification case names."""
    path, separator, symbol = binding.partition("::")
    if separator:
        return [{"path": path, "name": symbol}]
    try:
        text = (root / path).read_text(encoding="utf-8")
    except (OSError, UnicodeError, ValueError):
        return []
    found = []
    for name, tag, _ in reachability.tests_in(text):
        try:
            tagged = tag is not None and case in sysml.source_proves(tag)
        except ValueError:
            tagged = False
        if tagged or re.search(r"(?<![\w-])" + re.escape(case) + r"(?![\w-])", name):
            found.append({"path": path, "name": name})
    return found


# A token of a model text: a block comment, a line comment, a string, a quoted name or other text.
TOKEN = re.compile(r"""/\*[\s\S]*?\*/|//[^\r\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^/"']+|.""")


def without_notes(text):
    """`text` without its comments; the body of a `doc` stays, since it states the promise."""
    out = []
    for token in TOKEN.finditer(text):
        value = token.group()
        if value.startswith("//") or value.startswith("/*") and not re.search(r"\bdoc\s*$", "".join(out)):
            value = " "
        out.append(value)
    return "".join(out)


def digests(models):
    """{identity: sha256} of every requirement declaration below `models` (what it promises)."""
    out = {}
    for key, path in sysml.model_files(models).items():
        source = path.read_text(encoding="utf-8")
        code = sysml.blanked(source)   # offsets as in source; comments, docs and strings blanked
        for match in sysml.DECLARATION.finditer(code):
            if match[1] != "requirement" or match[2]:
                continue
            body = sysml.declaration_body(code, match.end() - 1)
            whole = source[match.start():match.end() + len(body) + 1]
            text = " ".join(BUILD.sub(" ", without_notes(whole)).split())
            out[match[3]] = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return out


STATION_LOCATIONS = {"station", "simulator", "flexRadio"}


def live_levels(levels):
    """[{cost, location, station}] of a case's @TestLevel (cost, location) pairs."""
    return [{"cost": cost, "location": place, "station": place in STATION_LOCATIONS} for cost, place in levels]


def left_to_accept(levels):
    """True when one of a case's @TestLevel (cost, location) pairs is on real equipment."""
    return any(place in REAL_EQUIPMENT for _cost, place in levels)


def satisfiers(models):
    """{identity: part} of every requirement: a clause's subject type, an FR's Shack satisfier."""
    model = sysml.Model(models)
    out = {}
    for key in model.trees:
        for element in model.elements(key):
            identity = sysml.identity_of(element)
            if element.kind == "requirement" and identity and not identity.startswith("FR-"):
                subject = sysml.subject_of(element)
                if subject is not None and subject.type_name():
                    out[identity] = subject.type_name()
            elif element.kind == "satisfy" and key == sysml.SHACK_FILE:
                found = sysml.SATISFY_FR.match(element.head)
                if found:
                    out.setdefault(found[1], found[2])
    return out


def bindings(rev):
    with tempfile.TemporaryDirectory(prefix="model-bindings-") as tmp:
        root = Path(tmp)
        extract(rev, root)
        seen = []

        def record(identifier, binding, root_, manual=False):
            seen.append((identifier, binding, manual))
            return True
        original, sysml.source_binding = sysml.source_binding, record
        try:
            entries = sysml.canonical_catalog(root / MODELS, root)
        finally:
            sysml.source_binding = original
        digest, satisfied = digests(root / MODELS), satisfiers(root / MODELS)
        cases, promises = {}, {}
        for identifier, entry in entries.items():
            if entry["kind"] == "verification":
                cases[identifier] = {"automated": entry["state"] in ("partial", "implemented"),
                                     "verifies": entry["refs"], "paths": [], "tests": [], "unresolved": [],
                                     "accept": left_to_accept(entry["levels"]),
                                     "levels": live_levels(entry["levels"])}
            else:
                promises[identifier] = {"implementation": [], "digest": digest[identifier]}
                if identifier in satisfied:
                    promises[identifier]["satisfied_by"] = satisfied[identifier]
        for identifier, binding, manual in seen:
            if identifier not in entries:
                continue   # a binding of a model file (`@DetailTests`), named by its key
            if identifier in promises:
                promises[identifier]["implementation"].append(binding.partition("::")[0])
                continue
            case = cases[identifier]
            case["automated"] = case["automated"] and not manual
            case["paths"].append(binding.partition("::")[0])
            tests = tests_for(identifier, binding, root)
            case["tests"].extend(t for t in tests if t not in case["tests"])
            if not tests:
                case["unresolved"].append(binding)
        models = [f"{MODELS}/{key}" for key in sysml.model_files(root / MODELS)]
    return {"models": models, "cases": cases, "promises": promises}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--rev", default="HEAD")
    a = ap.parse_args(argv)
    try:
        print(json.dumps(bindings(a.rev)))
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError) as e:
        print(f"model bindings: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
