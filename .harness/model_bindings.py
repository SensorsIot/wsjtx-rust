#!/usr/bin/env python3
"""The model bindings at a commit, as the harness gate reads them (gate.model_bindings,
harness/core/tools/candidate.py), for its binding check and its report-only candidate
selection (harness#40).

    python .harness/model_bindings.py --rev REV

It reuses tools/sysml.py: canonical_catalog reads the canonical models at REV, and every
binding it resolves is recorded instead of checked (checking them is the
source-model-traces suite's job). A verification case binds a test by `path::name`, or
by its file: the tests there whose `Proves:` tag names the case, or a JavaScript test
whose name does. Prints the JSON that candidate.py describes.
"""
import argparse
import io
import json
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "harness" / "core" / "tools"))
import sysml          # noqa: E402
import reachability   # noqa: E402

MODELS = "docs/sysml"


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, check=True).stdout


def extract(rev, into):
    """The models and the source roots at `rev`, written below `into`."""
    present = set(git("ls-tree", "--name-only", rev).decode().split())
    roots = [r for r in sysml.SOURCE_BINDING_ROOTS if r in present]
    data = git("archive", "--format=tar", rev, "--", *roots, f":(glob){MODELS}/*.sysml")
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
        cases, promises = {}, {}
        for identifier, entry in entries.items():
            if entry["kind"] == "verification":
                cases[identifier] = {"automated": entry["state"] in ("partial", "implemented"),
                                     "verifies": entry["refs"], "paths": [], "tests": [], "unresolved": []}
            else:
                promises[identifier] = {"implementation": []}
        for identifier, binding, manual in seen:
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
        models = sorted(f"{MODELS}/{p.name}" for p in (root / MODELS).glob("*.sysml"))
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
