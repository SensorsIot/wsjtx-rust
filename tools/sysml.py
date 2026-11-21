"""The model tool of the product contract `docs/sysml`: the canonical authority, the catalog
of identities and bindings, the real OMG Pilot validation and the rules of the finished
model (`harness/project/docs/Finished-Model.md`).

traces checks the authority, the catalog, the Proves tags against the bindings, the code
links, the model values against the code and the code structure. check adds the Pilot
validation, the architecture oracle, the identity history and the structure and writing
rules. status prints each FR's status computed from its clauses; markers lists the
WstxModelNotes markers; equivalence compares two revisions by meaning and identities lists
their identity diff; oracle writes the architecture oracle file; paths rewrites the code
paths of a rename list in the model. Only oracle and paths write a file. None executes
modelled behaviour.

The code proof reads one revision and never the working tree: tests <rev> prints the test
inventory, check <rev> checks the model of the revision, and traces <rev> checks its traces
and prints the trace listing. Without a revision, check and traces read the working tree.
"""
from __future__ import annotations

import argparse
import ast
import bisect
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import contextlib
import hashlib
import io
import json
import operator
import os
from pathlib import Path
import posixpath
import re
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import tokenize
import urllib.request
import urllib.parse
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FSD = ROOT / "docs/WSTX Rust FSD.md"
MODELS = ROOT / "docs/sysml"
TOOLCHAIN = Path(__file__).with_name("sysml") / "toolchain.json"
# The architecture oracle. `check` compares it with the inventory; only `oracle` writes it,
# after the Pilot validation and the fixed rules pass (TR-09).
ORACLE = Path(__file__).with_name("sysml") / "architecture-oracle.json"
ID = re.compile(r"\b(?:FR-\d{3}|CL-\d{3}-\d{2}|TC-\d{3}-\d{3})\b")
CANONICAL_MARKER = "// Canonical authority: SysML"
SOURCE_BINDING_ROOTS = ("client", "server", "tests")
# Each required package is the package of exactly one model file (TR-03).
REQUIRED_PACKAGES = {"WstxRequirements", "WstxShack", "WstxContext"}
CONTEXT_FILE = "Context.sysml"
CONTEXT_PACKAGE = "WstxContext"
# The package whose `metadata def` names are the marker kinds that `markers` lists.
MARKER_PACKAGE = "WstxModelNotes"
IDENTITY = r"(?:FR-\d{3}|CL-\d{3}-\d{2}|TC-\d{3}-\d{3})"
# A declaration the catalog reads: `requirement '<ID>' {` or `verification '<ID>' {`. A `def`
# or a typed declaration with an identity is another form and refused (TR-10).
DECLARATION = re.compile(r"\b(requirement|verification)(\s+def)?\s+'(" + IDENTITY + r")'\s*(?::\s*((?:\w+::)*\w+)\s*)?\{")
# A requirement or verification whose name or short name is a stable identity, in any form.
IDENTITY_DECLARATION = re.compile(r"\b(?:requirement|verification)(?:\s+def)?\s+(?:<\s*'(" + IDENTITY + r")'\s*>|(?:<[^<>{};]*>\s*)?'(" + IDENTITY + r")')")
# A verification definition without identity.
CASE_DEFINITION = re.compile(r"\bverification\s+def\s+(?:<[^<>{};]*>\s*)?(\w+|'[^']*')[^{};]*\{")
STRING = r'"(?:\\.|[^"\\])*"'


def authority(directory: Path, fsd: Path) -> str:
    """Admit only canonical SysML; refuse an active FSD; never inspect archived Markdown."""
    entry = directory / "Requirements.sysml"
    text = entry.read_text(encoding="utf-8") if entry.is_file() else ""
    markers = re.findall(r"^// Canonical authority:[^\r\n]*$", text, re.MULTILINE)
    if markers and markers != [CANONICAL_MARKER]:
        raise ValueError("Invalid or duplicate canonical-authority declaration")
    if fsd.exists():
        if markers:
            raise ValueError("Two functional authorities: canonical SysML and active FSD")
        raise ValueError("Retired Markdown FSD is not a functional authority: archive it and declare canonical SysML")
    if not markers:
        raise ValueError("No declared functional authority: canonical SysML marker required")
    return "sysml"


def without_comments(text: str) -> str:
    """Strip comments while retaining quoted names/strings for profile checks.

    The pinned Pilot remains the syntax/name/semantic validator. This narrow lexer
    only keeps comment examples from masquerading as catalog declarations.
    """
    tokens = re.finditer(r'/\*[\s\S]*?\*/|//[^\r\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[^/"\']+|.', text)
    return "".join(" " if token.group().startswith(("/*", "//")) else token.group() for token in tokens)


def blanked(text: str, strings: bool = True) -> str:
    """`text` with every comment, and with `strings` the inside of every string literal,
    replaced by spaces. Line breaks and every offset are kept, so a position found here
    is the same position in `text`."""
    def spaces(value: str) -> str:
        return re.sub(r"[^\r\n]", " ", value)

    parts = []
    for token in re.finditer(r'/\*[\s\S]*?\*/|//[^\r\n]*|' + STRING + r'|\'(?:\\.|[^\'\\])*\'|[^/"\']+|.', text):
        value = token.group()
        if value.startswith(("/*", "//")):
            value = spaces(value)
        elif strings and len(value) > 1 and value.startswith('"'):
            value = '"' + spaces(value[1:-1]) + '"'
        parts.append(value)
    return "".join(parts)


def assignments(text: str, code: str) -> list[tuple[str, str]]:
    """The `feature = value;` statements of an annotation body, as written. `code` is
    `text` with its strings blanked, so a semicolon inside a string ends nothing. A
    non-blank statement in another spelling is reported with the feature name ""."""
    found, start = [], 0
    for end in [index for index, character in enumerate(code) if character == ";"] + [len(code)]:
        if statement := re.fullmatch(r"\s*(\w+)\s*=\s*([\s\S]*?)\s*", text[start:end]):
            found.append((statement[1], statement[2]))
        elif text[start:end].strip():
            found.append(("", text[start:end].strip()))
        start = end + 1
    return found


def annotations(text: str, code: str, name: str) -> list[tuple[int, list[tuple[str, str]]]]:
    """Every `@Name { ... }` and `@Name;` of comment-free `text`, with or without package
    names, as (offset of `@`, assignments). `code` is `blanked(text)`."""
    found = []
    for match in re.finditer(r"@\s*(?:\w+::)*" + name + r"\b(?!::)\s*(\{)?", code):
        if match[1]:
            opening = match.end() - 1
            body = declaration_body(text, opening)
            found.append((match.start(), assignments(body, code[opening + 1:opening + 1 + len(body)])))
        else:
            found.append((match.start(), []))
    return found



JOINED = re.compile(r'\s*"[^"\r\n]*"(?:\s*\+\s*"[^"\r\n]*")*\s*')


def string_literal(value: str):
    """The text of a value that is one string literal, or string literals joined by `+`,
    which are one value; None for anything else."""
    if not JOINED.fullmatch(value):
        return None
    return "".join(re.findall(r'"([^"\r\n]*)"', value))


def stated(body: str, code: str, kind: str) -> tuple[list, list, list, set]:
    """What one declaration body states in its metadata: (states, bindings, methods,
    unread). An invalid state is "", a binding or method that is not one string value is
    None. `unread` holds each of "state", "binding" and "method" that the body states in a
    form that is not read: the `metadata` keyword form or another feature."""
    if kind == "verification":
        enum, status, state_feature, bound, bound_feature = "AutomationState", "Automation", "run", "TestedBy", "test"
    else:
        enum, status, state_feature, bound, bound_feature = "ImplementationState", "Status", "build", "ImplementedIn", "module"
    states, bindings, methods, unread = [], [], [], set()
    if re.search(r"\bmetadata\b[^;{}]*\b" + status + r"\b", code):
        unread.update(("state", "method"))
    if re.search(r"\bmetadata\b[^;{}]*\b" + bound + r"\b", code):
        unread.add("binding")
    for _offset, pairs in annotations(body, code, status):
        for feature, value in pairs:
            if feature == state_feature:
                state = re.fullmatch(r"(?:\w+::)*" + enum + r"::(\w+)", value)
                states.append(state[1] if state else "")
            elif feature == "method" and kind == "verification":
                methods.append(string_literal(value))
            else:
                unread.update(("state", "method"))
    for _offset, pairs in annotations(body, code, bound):
        bindings.extend(string_literal(value) for feature, value in pairs if feature == bound_feature)
        if any(feature != bound_feature for feature, _value in pairs):
            unread.add("binding")
    return states, bindings, methods, unread


def file_bindings(key: str, value, root: Path) -> None:
    """Check a binding that belongs to a model file (a function binding, detail tests):
    existing files under the source roots, no `Proves:` tag; messages name the key."""
    if value is None:
        raise ValueError("Invalid verification/implementation metadata: " + key)
    for binding in value.split(";"):
        source_binding(key, binding.strip(), root, manual=True)


def owning_bodies(code: str, offsets: list[int]) -> dict[int, int]:
    """For each offset, the offset of the `{` of the innermost body that holds it; -1 for
    the top level of the file. `code` is blanked, so a brace in a comment or string counts
    for nothing."""
    owners, stack, wanted = {}, [], sorted(set(offsets))
    position = 0
    for offset in wanted:
        for index in range(position, offset):
            if code[index] == "{":
                stack.append(index)
            elif code[index] == "}" and stack:
                stack.pop()
        position = offset
        owners[offset] = stack[-1] if stack else -1
    return owners


def declaration_body(text: str, opening: int) -> str:
    depth = 0
    for token in re.finditer(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}]', text[opening:]):
        value = token.group()
        if value == "{":
            depth += 1
        elif value == "}":
            depth -= 1
            if depth == 0:
                return text[opening + 1:opening + token.start()]
    raise ValueError("Unclosed canonical catalog declaration")


def source_binding(identifier: str, binding: str, root: Path, manual: bool = False):
    path_text, separator, symbol = binding.partition("::")
    path = Path(path_text)
    resolved = (root / path).resolve()
    if path.is_absolute() or ".." in path.parts or not resolved.is_relative_to(root.resolve()) or not resolved.is_file():
        raise ValueError(f"Missing or out-of-scope implementation/test binding: {identifier}: {binding}")
    if path.parts[0] not in SOURCE_BINDING_ROOTS:
        raise ValueError(f"Binding outside declared source inputs: {identifier}: {binding}; update HOW input coverage before admitting a new root")
    if not identifier.startswith("TC-") or (manual and not separator):
        return True
    source = resolved.read_text(encoding="utf-8")
    # The symbol of a `path::symbol` binding must exist, for a manual case too.
    if separator:
        if not symbol or not re.search(r"\bfn\s+" + re.escape(symbol) + r"\s*\(|\btest\s*\(\s*['\"]" + re.escape(symbol) + r"['\"]", source):
            raise ValueError(f"Missing executable test symbol: {identifier}: {binding}")
        return True
    else:
        named = re.search(r"\btest\s*\(\s*['\"][^'\"\r\n]*\b" + re.escape(identifier) + r"\b", source)
        return identifier in source_proves(" ".join(attached_proves(source))) or bool(named)


PROVES_TAG = re.compile(r"^\s*(?://|#)\s*Proves:([^\r\n]+)")
# A Proves comment binds only when the next non-comment line is a test: Rust
# #[test]/#[tokio::test], JS test( or Python def test_. Other Rust attributes and
# Python decorators belong to the test they precede.
ATTACHED_TEST = re.compile(r"\s*(?:#\[(?:tokio::)?test\b|test\s*\(|(?:async\s+)?def\s+test_)")
SKIPPED_LINE = re.compile(r"\s*(?://|#(?!\[)|#\[(?!(?:tokio::)?test\b)|@)")


def attached_proves(source: str) -> list[str]:
    lines = source.splitlines()
    tags = []
    for index, line in enumerate(lines):
        if not (tag := PROVES_TAG.match(line)):
            continue
        following = (code for code in lines[index + 1:] if not SKIPPED_LINE.match(code))
        if ATTACHED_TEST.match(next(following, "")):
            tags.append(tag[1])
    return tags


RUST_TEST_FN = re.compile(r"\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+(\w+)")
JS_TEST_NAME = re.compile(r"\s*test\s*\(\s*(['\"])((?:\\.|(?!\1)[^\r\n])*)\1")


PYTHON_TEST_DEF = re.compile(r"\s*(?:async\s+)?def\s+test_\w+")


def naming_tests(source: str) -> list[tuple[str, set[str]]]:
    """(test name, case identities) of every test of `source` that names a case: by the
    `Proves:` tag attached to it (as `attached_proves` reads it, shorthand expanded) or, for
    a JavaScript test, by its name. A Rust test is named by its function, a Python test as
    `python_tests` names it."""
    lines = source.splitlines()
    named = {}
    for index, line in enumerate(lines):
        if tag := PROVES_TAG.match(line):
            following = ((number, code) for number, code in enumerate(lines[index + 1:], index + 1)
                         if not SKIPPED_LINE.match(code))
            test, code = next(following, (None, ""))
            if ATTACHED_TEST.match(code):
                named.setdefault(test, set()).update(ref for ref in source_proves(tag[1]) if ref.startswith("TC-"))
        elif script := JS_TEST_NAME.match(line):
            named.setdefault(index, set()).update(re.findall(r"\bTC-\d{3}-\d{3}\b", script[2]))
    found, python = [], None
    for test, cases in sorted(named.items()):
        if script := JS_TEST_NAME.match(lines[test]):
            name = re.sub(r"\\(.)", r"\1", script[2])
        elif PYTHON_TEST_DEF.match(lines[test]):
            if python is None:
                try:
                    python = python_test_lines(ast.parse(source))
                except (SyntaxError, ValueError):
                    python = {}
            name = python.get(test + 1)
        else:
            name = next((function[1] for code in lines[test:test + 12] if (function := RUST_TEST_FN.match(code))), None)
        if name is not None and cases:
            found.append((name, cases))
    return found


def binding_agreement(entries: dict[str, dict], root: Path) -> None:
    """Refuse every test below the source roots that names a case outside that case's
    binding: neither its file nor `path::<its name>` is bound. One message names every
    such pair, sorted by case, path and test name."""
    outside = set()
    for directory_name in SOURCE_BINDING_ROOTS:
        for path in sorted((root / directory_name).rglob("*")):
            if not path.is_file() or path.suffix not in {".rs", ".js", ".cjs"}:
                continue
            key = path.relative_to(root).as_posix()
            for name, cases in naming_tests(path.read_text(encoding="utf-8")):
                for case in cases:
                    bound = entries.get(case, {}).get("bindings", [])
                    if key not in bound and f"{key}::{name}" not in bound:
                        outside.add((case, key, name))
    if outside:
        raise ValueError("Proves tag outside the verification binding: "
                         + "; ".join(f"{case}: {key}::{name}" for case, key, name in sorted(outside)))



def model_files(directory: Path) -> dict[str, Path]:
    """Every model file below `directory`, by key and sorted by key.

    A model file is a `*.sysml` file at any depth; no folder is excluded. Its key is its
    path relative to `directory` with forward slashes on every platform, so a file
    directly in `directory` has its name as key.
    """
    found = {path.relative_to(directory).as_posix(): path
             for path in directory.rglob("*.sysml") if path.is_file() and path.name.endswith(".sysml")}
    return dict(sorted(found.items()))


def file_package(code: str):
    """The package of a model file: the name of the first package declaration of its
    comment-free text `code`; None for a file without one. A package nested in it or
    declared after it is not the file's package."""
    package = re.search(r"\bpackage\s+(\w+)\s*\{", code)
    return package[1] if package else None


# A derivation of the pinned model library (Requirement Derivation): `#derivation
# connection { end #original ::> <FR>; end #derive ::> <clause>; }`, with or without
# package names on the metadata and the ends.
DERIVATION = re.compile(r"#\s*(?:\w+::)*derivation\s+connection\b[^{};]*\{")
DERIVATION_END = re.compile(r"\bend\s+#\s*(?:\w+::)*(original|derive)\s*::>\s*(?:(?:\w+|'[^']*')::)*'([^']+)'\s*;")


def file_derivations(key: str, clean: str) -> list[tuple[str, list[str]]]:
    """The derivation connections of one comment-free model file, in file order, as
    (original, derived). A body holding anything but one `#original` end and one or more
    `#derive` ends is refused: `Invalid canonical derivation: <key>:<line>`."""
    code = blanked(clean)
    found = []
    for match in DERIVATION.finditer(code):
        body = declaration_body(clean, match.end() - 1)
        ends = list(DERIVATION_END.finditer(body))
        rest = DERIVATION_END.sub(" ", blanked(body, strings=False))
        originals = [end[2] for end in ends if end[1] == "original"]
        derived = [end[2] for end in ends if end[1] == "derive"]
        if rest.strip() or len(originals) != 1 or not derived:
            raise ValueError(f"Invalid canonical derivation: {key}:{code.count(chr(10), 0, match.start()) + 1}")
        found.append((originals[0], derived))
    return found


# TR-19: the places a test runs, the members of `WstxModelBindings::TestLocation`.
TEST_LOCATIONS = ("developmentPc", "station", "simulator", "flexRadio")
TEST_LEVEL_FORM = re.compile(r"\bmetadata(?!\s+def\b)\s+[^;{}]*\bTestLevel\b(?!::)")
VERIFICATION_USAGE = re.compile(r"\bverification\s+(?!def\b)(?:<[^<>{};]*>\s*)?(\w+|'[^']*')")
OWNER_NAME = re.compile(r"(?:\b(?:abstract|ref|in|out|inout|private|public|protected|variation|individual|derived|"
                        r"readonly|end|doc)\s+)*(?:\w+\s+)?(?:def\s+)?(?:<[^<>{};]*>\s*)?(\w+|'[^']*')")


def file_levels(key: str, clean: str) -> dict[int, list[tuple[int, str]]]:
    """TR-19: the `@TestLevel` pairs of one comment-free model file, by the offset of
    the `{` of the body that states them, each list sorted. Only a verification case,
    definition or usage states them; every other owner, and every form other than
    `@TestLevel { cost = <1..5>; location = TestLocation::<place>; }` once per pair, is
    refused: `Invalid test level: <identity>`, or `Invalid test level: <name>: <key>`."""
    code = blanked(clean)
    found = [(offset, pairs) for offset, pairs in annotations(clean, code, "TestLevel")]
    found += [(match.start(), None) for match in TEST_LEVEL_FORM.finditer(code)]
    if not found:
        return {}
    owners = owning_bodies(code, [offset for offset, _pairs in found])
    identities = {match.end() - 1: match[3] for match in DECLARATION.finditer(clean)}
    kinds = {match.end() - 1: match[1] for match in DECLARATION.finditer(clean)}
    definitions = {match.end() - 1 for match in CASE_DEFINITION.finditer(code)}
    levels = {}
    for offset, pairs in sorted(found, key=lambda item: item[0]):
        opening = owners[offset]
        if opening in identities:
            name, verification = identities[opening], kinds[opening] == "verification"
            invalid = ValueError("Invalid test level: " + name)
        else:
            start = max(code.rfind(character, 0, opening) for character in ";{}") + 1 if opening >= 0 else 0
            header = clean[start:opening] if opening >= 0 else ""
            verification = opening in definitions or bool(VERIFICATION_USAGE.search(blanked(header)))
            named = OWNER_NAME.search(header)
            invalid = ValueError(f"Invalid test level: {named[1]}: {key}" if named else f"Invalid test level: {key}")
        if not verification or pairs is None:
            raise invalid
        values = dict(pairs)
        if sorted(feature for feature, _value in pairs) != ["cost", "location"]:
            raise invalid
        cost = re.fullmatch(r"[1-5]", values["cost"])
        place = re.fullmatch(r"(?:\w+::)*TestLocation::(\w+)", values["location"])
        if not cost or not place or place[1] not in TEST_LOCATIONS:
            raise invalid
        pair = (int(cost[0]), place[1])
        if pair in levels.get(opening, []):
            raise invalid
        levels.setdefault(opening, []).append(pair)
    return {opening: sorted(pairs) for opening, pairs in levels.items()}


def computed_status(states: list[str]) -> str:
    """TR-12: implemented when all clauses are, target when all are or there is none,
    partial in every other case."""
    if all(state == "target" for state in states):
        return "target"
    if all(state == "implemented" for state in states):
        return "implemented"
    return "partial"


def source_proves(text: str) -> set[str]:
    """The identities a tag text names, shorthand expanded as `references` reads it."""
    return set(references(text))


def canonical_catalog(directory: Path, root: Path) -> dict[str, dict]:
    """The catalog (TR-10, TR-12, TR-19): every FR, clause and case of the model with its
    state, bindings and links, each checked; raises on the first fault. A clause's entry
    holds its own code link (`own`), the FRs it derives from (`frs`) and the cases that
    verify it (`cases`); an FR's its computed status (TR-12)."""
    files = model_files(directory)
    sources = {key: path.read_text(encoding="utf-8") for key, path in files.items()}
    clean_models = {key: without_comments(source) for key, source in sources.items()}
    packages = {key: file_package(clean) for key, clean in clean_models.items()}
    keys_of = {}
    for key, package in packages.items():
        if package in REQUIRED_PACKAGES:
            keys_of.setdefault(package, []).append(key)
    if missing := REQUIRED_PACKAGES - keys_of.keys():
        raise ValueError("Canonical model packages missing: " + ", ".join(sorted(missing)))
    for package in sorted(REQUIRED_PACKAGES):
        if len(keys_of[package]) > 1:
            raise ValueError("Duplicate canonical model package: " + package + ": " + ", ".join(sorted(keys_of[package])))
    entries, derivations = {}, []
    for key, path in files.items():
        source = sources[key]
        if re.search(r"Canonical FSD|\bFSD(?:\s+(?:chapter|section))?\s*\d|WSTX(?:%20| )Rust(?:%20| )FSD", source):
            raise ValueError("Canonical model retains a retired FSD dependency: " + key)
        for target in re.findall(r"\]\(([^)]+)\)", source):
            target = target.strip("<>")
            if target.startswith(("https://", "http://", "#")):
                continue
            target = urllib.parse.unquote(target.split("#", 1)[0])
            if target and not (path.parent / target).resolve().is_file():
                raise ValueError("Dangling model documentation link: " + key + ": " + target)
        clean = clean_models[key]
        code = blanked(clean)
        declarations = [match for match in DECLARATION.finditer(clean) if not match[2] and not match[4]]
        read = {match.start() for match in declarations}
        for match in IDENTITY_DECLARATION.finditer(code):
            if match.start() not in read:
                raise ValueError(f"Unreadable canonical declaration: {match[1] or match[2]}: {key}")
        for _offset, pairs in annotations(clean, code, "DetailTests"):
            for feature, value in pairs:
                if feature == "tests":
                    file_bindings(key, string_literal(value), root)
        levels = file_levels(key, clean)
        for match in declarations:
            kind, identifier = match[1], match[3]
            if identifier in entries:
                raise ValueError("Duplicate canonical identity: " + identifier)
            if kind != ("verification" if identifier.startswith("TC-") else "requirement"):
                raise ValueError("Wrong canonical identity kind: " + identifier)
            start = match.end()
            body = declaration_body(clean, start - 1)
            states, bindings, methods, unread = stated(body, code[start:start + len(body)], kind)
            refs = re.findall(r"\bverify\s+(?:\w+::)*'([^']+)'\s*;", body)
            if identifier.startswith("FR-"):
                # An FR states nothing of its delivery: its status is computed (TR-12).
                if states or bindings or methods or unread:
                    raise ValueError("FR states a status or a binding: " + identifier)
            else:
                allowed = {"planned", "partial", "implemented"} if kind == "verification" else {"target", "partial", "implemented"}
                if "state" in unread or len(states) != 1 or states[0] not in allowed:
                    raise ValueError("Missing or invalid declared model state: " + identifier)
            if "binding" in unread or len(bindings) > 1 or len(methods) > 1 or None in bindings \
                    or (methods and methods[0] not in {"manual", "automated"}):
                raise ValueError("Invalid verification/implementation metadata: " + identifier)
            paths = [binding.strip() for binding in bindings[0].split(";")] if bindings else []
            if kind == "verification":
                if states[0] in {"partial", "implemented"} and not any(paths):
                    raise ValueError("Delivered declaration lacks implementation/test binding: " + identifier)
                matched = [source_binding(identifier, binding, root, manual=methods == ["manual"]) for binding in paths]
                if unbound := [binding for binding, bound in zip(paths, matched) if not bound]:
                    raise ValueError(f"No Proves tag or named-test identity for {identifier}: {'; '.join(unbound)}")
            else:
                for binding in paths:
                    source_binding(identifier, binding, root, manual=True)
            entries[identifier] = {"kind": kind, "state": states[0] if states else None, "refs": refs,
                                   "bindings": paths, "manual": methods == ["manual"], "file": key,
                                   "line": clean.count("\n", 0, match.start()) + 1}
            if kind == "verification":
                entries[identifier]["levels"] = levels.get(match.end() - 1, [])
        derivations.extend(file_derivations(key, clean))
    derived = {}
    for original, clauses in derivations:
        for clause in clauses:
            if clause not in entries or original not in entries or not clause.startswith("CL-") or not original.startswith("FR-"):
                raise ValueError("Invalid canonical clause derivation: " + clause + " -> " + original)
            derived.setdefault(clause, []).append(original)
    cases = {}
    for identifier, entry in entries.items():
        if entry["kind"] == "verification":
            if not entry["refs"] or any(ref not in entries or not ref.startswith("CL-") for ref in entry["refs"]):
                raise ValueError("Undefined or absent verification target: " + identifier)
            for ref in entry["refs"]:
                cases.setdefault(ref, []).append(identifier)
    for identifier, entry in entries.items():
        if identifier.startswith("CL-"):
            if identifier not in derived:
                raise ValueError("Canonical clause lacks requirement ownership: " + identifier)
            entry["frs"] = sorted(derived[identifier])
            entry["cases"] = sorted(cases.get(identifier, []))
            entry["own"] = entry.pop("bindings")
    for identifier, entry in entries.items():
        if identifier.startswith("FR-"):
            clauses = sorted(clause for clause in entries if identifier in derived.get(clause, []))
            entry["clauses"] = clauses
            entry["status"] = entry["state"] = computed_status([entries[clause]["state"] for clause in clauses])
    return entries


# A tag is `// Proves: TC-ddd-ddd`, several joined by `, ` (TR-14).
TAG_FORM = re.compile(r"\s*// Proves: TC-\d{3}-\d{3}(?:, TC-\d{3}-\d{3})*\s*")


def source_files(root: Path):
    """The code and test files below the source roots, by repository path, sorted."""
    for directory_name in SOURCE_BINDING_ROOTS:
        for path in sorted((root / directory_name).rglob("*")):
            if path.is_file() and path.suffix in {".rs", ".js", ".cjs"}:
                yield path.relative_to(root).as_posix(), path


def tag_faults(entries: dict[str, dict], root: Path) -> list[str]:
    """TR-14: every `Proves:` line below the source roots is a tag of the one form, stands on
    a test, and names only declared cases. One line per fault, sorted."""
    faults = []
    for key, path in source_files(root):
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            if not PROVES_TAG.match(line):
                continue
            following = (code for code in lines[index + 1:] if not SKIPPED_LINE.match(code))
            if not TAG_FORM.fullmatch(line) or not ATTACHED_TEST.match(next(following, "")):
                faults.append(f"Invalid Proves tag: {key}:{index + 1}")
                continue
            for case in re.findall(r"TC-\d{3}-\d{3}", line):
                if entries.get(case, {}).get("kind") != "verification":
                    faults.append(f"Proves tag names an undeclared case: {case}: {key}:{index + 1}")
    return sorted(faults)


def status_lines(entries: dict[str, dict]) -> list[str]:
    """The lines of `status` (TR-12): one per FR in identity order, then the summary."""
    lines, counts = [], Counter()
    for identifier in sorted(identifier for identifier in entries if identifier.startswith("FR-")):
        entry = entries[identifier]
        states = Counter(entries[clause]["state"] for clause in entry["clauses"])
        line = (f"{identifier} {entry['status']}: {len(entry['clauses'])} clauses, {states['implemented']} implemented, "
                f"{states['partial']} partial, {states['target']} target")
        lines.append(line)
        counts[entry["status"]] += 1
    lines.append(f"{len(lines)} FRs: {counts['implemented']} implemented, {counts['partial']} partial, {counts['target']} target")
    return lines


def markers(directory: Path, kinds=()) -> list[str]:
    """The lines of the marker listing: one per marker, then the summary.

    The kinds are the `metadata def` names of the model file whose package is
    `ModelNotes`. Reads the model files only; checks nothing else and writes nothing.
    """
    texts = {key: path.read_text(encoding="utf-8") for key, path in model_files(directory).items()}
    codes = {key: blanked(text) for key, text in texts.items()}
    known = set()
    for code in codes.values():
        if file_package(code) == MARKER_PACKAGE:
            known.update(re.findall(r"\bmetadata\s+def\s+(\w+)", code))
    for name in kinds:
        if name not in known:
            raise ValueError("Unknown marker kind: " + name)
    selected = sorted(set(kinds) or known)
    use = re.compile(r"(?:@\s*|\bmetadata\s+(?!def\b)\w+\s*:\s*)(?:" + MARKER_PACKAGE + r"::)?(\w+)\b(?!::)"
                     r"\s*(?:about\s+([^{};]+?)\s*)?(\{|;)")
    lines, counts = [], dict.fromkeys(selected, 0)
    for key in sorted(texts):
        text, code = blanked(texts[key], strings=False), codes[key]
        for match in use.finditer(code):
            kind = match[1]
            if kind not in counts:
                continue
            values = []
            if match[3] == "{":
                body = declaration_body(text, match.end() - 1)
                for _feature, value in assignments(body, code[match.end():match.end() + len(body)]):
                    if re.fullmatch(STRING + r"(?:\s*\+\s*" + STRING + r")*", value):
                        values.append("".join(re.sub(r'\\(["\'\\])', r"\1", part[1:-1]) for part in re.findall(STRING, value)))
            about = " about " + ", ".join(target.strip() for target in match[2].split(",")) if match[2] else ""
            line = code.count("\n", 0, match.start()) + 1
            lines.append(f"{key}:{line}: {kind}{about}: {'; '.join(values)}".rstrip())
            counts[kind] += 1
    summary = f"{len(lines)} markers"
    if selected:
        summary += ": " + ", ".join(f"{counts[kind]} {kind}" for kind in selected)
    return lines + [summary]


# TR-20: `paths` rewrites the code paths the model names from a rename list.
RENAME_LINE = re.compile(r"(\S+) -> (\S+)")
# The binding features of (a): each metadata form with its feature.
BINDING_METADATA = {"ImplementedIn": "module", "TestedBy": "test", "DetailTests": "tests"}
# The binding form a declaration's own binding is read from, by declaration kind (`stated`).
DECLARATION_BINDINGS = {"requirement": ("ImplementedIn",), "verification": ("TestedBy",)}
PATH_CHARACTER = re.compile(r"[\w/-]|\.[\w/-]")
URL_OR_ANCHOR = re.compile(r"[A-Za-z][\w+.-]*:|#")


def path_character(text: str, index: int) -> bool:
    """Whether a path character stands at `index` of `text`: a letter, a digit, `_`, `-`,
    `/`, or a `.` followed by one of these."""
    return 0 <= index < len(text) and PATH_CHARACTER.match(text, index) is not None


def binding_paths(source: str) -> tuple[list[tuple[int, int]], list[tuple[int, int, bool, str]]]:
    """The (a) bindings of one model file outside comments: (spans of the insides of their
    string literals, and for each path in them without its `::symbol` its span, whether the
    catalog checks it and its text), in file order. The catalog checks a declaration's own
    binding (its kind's metadata, inside the body of a declaration it reads), every
    `@ImplementedIn` outside the declaration bodies and every `@DetailTests`. A value joined
    by `+` is one value: its literals are read as one text, so a path or its `::symbol` may
    cross the end of a literal, and the span of such a path holds the joins."""
    text, code = blanked(source, strings=False), blanked(source)
    bodies = []
    for match in DECLARATION.finditer(text):
        if not match[4] or (match[1] == "verification" and not match[2]):
            bodies.append((match.end(), match.end() + len(declaration_body(text, match.end() - 1)), match[1]))

    def inside(offset: int, form: str | None = None) -> bool:
        return any(start <= offset < end and (form is None or form in DECLARATION_BINDINGS[kind])
                   for start, end, kind in bodies)

    values = []
    for name, feature in BINDING_METADATA.items():
        for match in re.finditer(r"@\s*(?:\w+::)*" + name + r"\b(?!::)\s*\{", code):
            if name == "ImplementedIn":
                checked = inside(match.start(), name) or not inside(match.start())
            else:
                checked = name != "TestedBy" or inside(match.start(), name)
            start = match.end()
            body = declaration_body(text, start - 1)
            for item in re.finditer(r"\b" + feature + r'\s*=\s*"[^"\r\n]*"(?:\s*\+\s*"[^"\r\n]*")*', code[start:start + len(body)]):
                values.append(([(start + item.start() + literal.start(1), start + item.start() + literal.end(1))
                                for literal in re.finditer(r'"([^"\r\n]*)"', item[0])], checked))
    values.sort()
    paths = []
    for spans, checked in values:
        offsets = [index for begin, end in spans for index in range(begin, end)]
        value, position = "".join(source[begin:end] for begin, end in spans), 0
        for part in value.split(";"):
            lead = len(part) - len(part.lstrip())
            path = part.strip().partition("::")[0].rstrip()
            if path:
                paths.append((offsets[position + lead], offsets[position + lead + len(path) - 1] + 1, checked, path))
            position += len(part) + 1
    return [span for spans, _checked in values for span in spans], paths


def link_targets(source: str, key: str) -> tuple[list[tuple[int, int]], list[tuple[int, int, str]]]:
    """The Markdown links of one model file: (spans of every link's label and target, and
    for each relative link the span of its path without `#fragment` and the repository path
    it resolves to from the file's folder)."""
    excluded, found = [], []
    folder = posixpath.join("docs/sysml", posixpath.dirname(key))
    for match in LINK.finditer(source):
        line_start = source.rfind("\n", 0, match.start()) + 1
        opening = source.rfind("[", line_start, match.start())
        if opening >= 0 and "]" not in source[opening + 1:match.start()]:
            excluded.append((opening + 1, match.start()))
        excluded.append(match.span(1))
        target = match[1]
        if URL_OR_ANCHOR.match(target):
            continue
        path = target.partition("#")[0]
        if path:
            found.append((match.start(1), match.start(1) + len(path),
                          posixpath.normpath(posixpath.join(folder, urllib.parse.unquote(path)))))
    return excluded, found


def renamed(path: str, entries: list[tuple[str, str, bool]]):
    """`path` after the renames, or None when no entry covers it; with the entry's index."""
    for index, (old, new, folder) in enumerate(entries):
        if path == old:
            return new, index
        if folder and path.startswith(old + "/"):
            return new + path[len(old):], index
    return None


def file_rewrites(source: str, key: str, entries: list[tuple[str, str, bool]]) -> list[tuple[int, int, str, int, str]]:
    """The rewrites of one model file as (start, end, new text, entry index, old path),
    sorted. A path of a joined value that crosses a literal's end becomes one literal."""
    _literals, bindings = binding_paths(source)
    excluded, links = link_targets(source, key)
    rewrites = []
    for begin, end, _checked, path in bindings:
        if result := renamed(path, entries):
            rewrites.append((begin, end, *result, path))
    # (c) reads the rest of each (a) string too, such as the paths in a command line; only
    # the spans (a) rewrote are left to it.
    excluded += [(begin, end) for begin, end, _new, _index, _old in rewrites]
    folder = posixpath.join("docs/sysml", posixpath.dirname(key))
    for begin, end, resolved in links:
        if result := renamed(resolved, entries):
            relative = posixpath.relpath("/" + result[0], "/" + folder)
            written = source[begin:end]
            if urllib.parse.unquote(written) != written:
                relative = urllib.parse.quote(relative, safe="/")
            rewrites.append((begin, end, relative, result[1], source[begin:end]))
    for index, (old, new, folder_entry) in enumerate(entries):
        for match in re.finditer(re.escape(old), source):
            begin, end = match.span()
            if path_character(source, begin - 1) or any(start < end and begin < stop for start, stop in excluded):
                continue
            if folder_entry:
                if end >= len(source) or source[end] != "/":
                    continue
                while path_character(source, end):
                    end += 1
            elif path_character(source, end):
                continue
            rewrites.append((begin, end, new + source[match.end():end], index, source[begin:end]))
    return sorted(rewrites)


def rename_list(text: str) -> tuple[list[tuple[str, str]], list[str]]:
    """The entries of a rename list as (old, new) without a trailing `/`, and the faults
    of its form."""
    entries, faults, invalid = [], set(), False
    for number, line in enumerate(text.split("\n"), 1):
        line = line.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        pair = RENAME_LINE.fullmatch(line.strip())
        if not pair or "\\" in line:
            faults.add(f"Invalid rename line {number}")
            invalid = True
            continue
        valid = True
        for written in pair.groups():
            plain = written.rstrip("/")
            if written.startswith("/") or re.match(r"[A-Za-z]:", written) or not plain or ".." in plain.split("/") \
                    or plain == "docs/sysml" or plain.startswith("docs/sysml/"):
                faults.add("Invalid rename path: " + written)
                valid = False
        if valid:
            entries.append((pair[1].rstrip("/"), pair[2].rstrip("/")))
    if not entries and not invalid and not faults:
        faults.add("Empty rename list")
    olds = [old for old, _new in entries]
    for old in olds:
        if olds.count(old) > 1:
            faults.add("Duplicate rename: " + old)
    for outer in set(olds):
        for inner in set(olds):
            if inner.startswith(outer + "/"):
                faults.add(f"Overlapping renames: {outer}, {inner}")
    for index, (old, new) in enumerate(entries):
        if old == new:
            faults.add("Rename to itself: " + old)
        if any(old == other_new for other, (_old, other_new) in enumerate(entries) if other != index):
            faults.add("Chained rename: " + old)
    return entries, sorted(faults)


def rewrite_paths(listing: Path, directory: Path, root: Path) -> tuple[int, list[str]]:
    """TR-20: rewrite the code paths of the model below `directory` from the rename list
    `listing`, after the files were moved below `root`. Returns (exit code, lines); on a
    refusal no file is written. The faults are judged in three steps, each only on a list
    the step before admitted: the list's form, the moved files, then the model."""
    pairs, faults = rename_list(listing.read_bytes().decode("utf-8"))
    if not faults:
        for old, new in pairs:
            if os.path.lexists(root / old):
                faults.append("Old path still present: " + old)
            if not (root / new).exists():
                faults.append("New path missing: " + new)
    if faults:
        return 2, sorted(faults) + [f"Path rewrite refused: {len(faults)} faults"]
    entries = [(old, new, (root / new).is_dir()) for old, new in pairs]
    sources = {key: path.read_bytes().decode("utf-8") for key, path in model_files(directory).items()}
    results, lines, named = {}, [], set()
    for key, source in sources.items():
        rewrites = file_rewrites(source, key, entries)
        parts, position = [], 0
        for begin, end, new, index, old in rewrites:
            named.add(index)
            line_start = source.rfind("\n", 0, begin) + 1
            lines.append((key, source.count("\n", 0, begin) + 1, begin - line_start, old, new))
            parts += [source[position:begin], new]
            position = end
        results[key] = "".join(parts) + source[position:]
    faults = {"Path not named by the model: " + old for index, (old, _new, _folder) in enumerate(entries) if index not in named}
    for key, text in results.items():
        _literals, bindings = binding_paths(text)
        for begin, _end, checked, path in bindings:
            if not checked:
                continue
            try:
                source_binding("paths", path, root, manual=True)
            except ValueError:
                faults.add(f"Path missing after rename: {key}:{text.count(chr(10), 0, begin) + 1} {path}")
        for begin, end, resolved in link_targets(text, key)[1]:
            if resolved == ".." or resolved.startswith("../") or not (root / resolved).exists():
                faults.add(f"Path missing after rename: {key}:{text.count(chr(10), 0, begin) + 1} {text[begin:end]}")
    if faults:
        return 2, sorted(faults) + [f"Path rewrite refused: {len(faults)} faults"]
    changed = [key for key in results if results[key] != sources[key]]
    for key in changed:
        (directory / key).write_bytes(results[key].encode("utf-8"))
    output = [f"rewrote {key}:{line} {old} -> {new}" for key, line, _column, old, new in sorted(lines)]
    return 0, output + [f"Path rewrite: {len(lines)} rewrites in {len(changed)} model files"]


def digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def library_digest(directory: Path) -> str:
    fingerprint = hashlib.sha256()
    for path in sorted(p for p in directory.rglob("*") if p.suffix in (".sysml", ".kerml")):
        fingerprint.update(path.relative_to(directory).as_posix().encode("utf-8") + b"\0")
        fingerprint.update(hashlib.sha256(path.read_bytes()).digest())
    return fingerprint.hexdigest()


def references(text: str) -> list[str]:
    """Expand complete identities and same-prefix numeric suffix shorthand."""
    for candidate in re.findall(r"\b(?:FR|CL|TC)-[A-Za-z0-9-]+", text):
        if not ID.fullmatch(candidate):
            raise ValueError("Malformed reference identity: " + candidate)
    found = []
    pattern = re.compile(ID.pattern + r"(?P<tail>(?:(?:/|,\s*|\.\.|[\u2013])\d+(?![\w-]))*)")
    for match in pattern.finditer(text):
        remainder = text[match.end():]
        if re.match(r"/(?!" + ID.pattern + r")|\.\.|,\s*\d|\u2013\d", remainder):
            raise ValueError("Ambiguous reference shorthand after: " + match[0])
        first = ID.match(match[0])[0]
        found.append(first)
        prefix, number = first.rsplit("-", 1)
        previous = int(number)
        for separator, suffix in re.findall(r"(/|,\s*|\.\.|[\u2013])(\d+)", match["tail"]):
            if len(suffix) != len(number):
                raise ValueError("Ambiguous reference shorthand: " + match[0])
            value = int(suffix)
            if separator in ("..", "\u2013"):
                if value <= previous or value - previous > 100:
                    raise ValueError("Invalid reference range: " + match[0])
                found.extend(f"{prefix}-{item:0{len(number)}d}" for item in range(previous + 1, value + 1))
            else:
                found.append(prefix + "-" + suffix)
            previous = value
    return sorted(set(found))


def setup(cache: Path):
    packages = json.loads(TOOLCHAIN.read_text(encoding="utf-8"))
    if sys.platform != "win32" and not os.environ.get("WSTX_SYSML_JAVA"):
        raise ValueError("Portable bootstrap targets Windows x64; provide WSTX_SYSML_JAVA for an existing Java 21+ on another platform")
    cache.mkdir(parents=True, exist_ok=True)
    for name, package in packages.items():
        if name.startswith("jdk") and os.environ.get("WSTX_SYSML_JAVA"):
            continue
        archive = cache / package["archive"]
        if not archive.exists():
            with urllib.request.urlopen(package["url"], timeout=60) as response, archive.open("wb") as output:
                while block := response.read(1024 * 1024):
                    output.write(block)
        with archive.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != package["sha256"]:
            raise ValueError(f"Official SHA256 mismatch: {archive}; remove the failed download before retrying")
        destination = cache / package["directory"]
        if not destination.exists():
            with zipfile.ZipFile(archive) as bundle:
                for member in bundle.infolist():
                    target = (destination / member.filename).resolve()
                    if not target.is_relative_to(destination.resolve()) or stat.S_ISLNK(member.external_attr >> 16):
                        raise ValueError(f"Unsafe archive member: {member.filename}")
                bundle.extractall(destination)
        print(f"Verified {package['archive']} SHA256 {actual}")
    tool_paths(cache)


def tool_paths(cache: Path) -> tuple[Path, Path, Path]:
    packages = json.loads(TOOLCHAIN.read_text(encoding="utf-8"))
    pilot = cache / packages["pilot"]["directory"] / "sysml"
    java = Path(os.environ["WSTX_SYSML_JAVA"]) if os.environ.get("WSTX_SYSML_JAVA") else cache / packages["jdk_windows_x64"]["directory"] / packages["jdk_windows_x64"]["executable"]
    jar = pilot / "jupyter-sysml-kernel-0.62.0-all.jar"
    library = pilot / "sysml.library"
    if not java.is_file() or not jar.is_file() or not library.is_dir():
        raise FileNotFoundError("Semantic validator unavailable; run python tools/sysml.py setup (no regex/lint fallback)")
    with jar.open("rb") as stream:
        jar_digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if jar_digest != packages["pilot"]["jar_sha256"] or library_digest(library) != packages["pilot"]["library_sha256"]:
        raise ValueError("Pinned semantic validator or model-library contents differ from the verified Pilot archive")
    return java, jar, library


ORACLE_SECTIONS = ("root", "parts", "references", "contracts", "ports", "connections", "bindings")
QUALIFIED = re.compile(r"(?:\w+::)+\w+")
POPULATION = re.compile(r"(0|[1-9][0-9]*)\.\.(0|[1-9][0-9]*|\*)")

ORACLE_ABOUT = "The architecture oracle, written by python tools/sysml.py oracle from the resolved inventory"


def architecture_oracle(path: Path) -> dict:
    """The oracle file at `path`, refused whole when its form is wrong. Reads only."""
    def invalid(what: str, key: str) -> ValueError:
        return ValueError(f"Architecture integrity: Invalid architecture oracle: {what}: {key}")

    def unique(pairs):
        found = {}
        for key, value in pairs:
            if key in found:
                raise invalid("key stated twice", key)
            found[key] = value
        return found

    try:
        oracle = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise ValueError(f"Architecture integrity: Architecture oracle unavailable: {path}") from None
    if not isinstance(oracle, dict):
        raise invalid("entry of another shape", "file")
    for key in oracle:
        if key not in ORACLE_SECTIONS and key != "about":
            raise invalid("unknown key", key)
    for key in ORACLE_SECTIONS:
        if key not in oracle:
            raise invalid("missing section", key)
    if not isinstance(oracle.get("about", ""), str):
        raise invalid("entry of another shape", "about")
    if not isinstance(oracle["root"], str) or not QUALIFIED.fullmatch(oracle["root"]):
        raise invalid("entry of another shape", "root")
    root = oracle["root"].rsplit("::", 1)[1]

    def dotted(key, owner=False) -> bool:
        """A dot path below the root; an owner of edges may be the root itself."""
        return isinstance(key, str) and (owner and key == root or key.startswith(root + ".")
                                         and all(re.fullmatch(r"[^.\s]+", name) for name in key.split(".")))

    def qualified(value) -> bool:
        return isinstance(value, str) and bool(QUALIFIED.fullmatch(value))

    def section(name: str) -> dict:
        if not isinstance(oracle[name], dict):
            raise invalid("entry of another shape", name)
        return oracle[name]

    def entry(key: str, value, required: tuple, optional: tuple = ()) -> None:
        if not isinstance(value, dict):
            raise invalid("entry of another shape", key)
        for name in value:
            if name not in required + optional:
                raise invalid("unknown key", key + ": " + name)
        if any(name not in value for name in required):
            raise invalid("entry of another shape", key)

    def pairs(key: str, connections, bindings) -> None:
        seen = set()
        for listed in (connections, bindings):
            if not isinstance(listed, list):
                raise invalid("entry of another shape", key)
            for pair in listed:
                if not (isinstance(pair, list) and len(pair) == 2 and all(isinstance(end, str) and end for end in pair)
                        and pair[0] != pair[1]):
                    raise invalid("entry of another shape", key)
                if frozenset(pair) in seen:
                    raise invalid("pair listed twice", key + ": " + " <-> ".join(pair))
                seen.add(frozenset(pair))

    for name, required, optional in (("parts", ("type", "population"), ("variation",)),
                                     ("references", ("type", "population", "target"), ())):
        for key, value in section(name).items():
            entry(key, value, required, optional)
            if not dotted(key) or not qualified(value["type"]) or value.get("variation", True) is not True \
                    or "target" in value and not dotted(value["target"]):
                raise invalid("entry of another shape", key)
            bounds = POPULATION.fullmatch(value["population"]) if isinstance(value["population"], str) else None
            if not bounds or bounds[2] != "*" and int(bounds[1]) > int(bounds[2]):
                raise invalid("malformed population", key)
    contracts = section("contracts")
    for name, contract in contracts.items():
        entry(name, contract, ("items",), ("bindings", "connections"))
        if not qualified(name) or not isinstance(contract["items"], dict):
            raise invalid("entry of another shape", name)
        for item, signature in contract["items"].items():
            if not isinstance(signature, list) or len(signature) != 2 or not qualified(signature[1]):
                raise invalid("entry of another shape", name + ": " + item)
            if signature[0] not in ("in", "out"):
                raise invalid("direction other than in or out", name + ": " + item)
        pairs(name, contract.get("connections", []), contract.get("bindings", []))
    for key, typed in section("ports").items():
        if not dotted(key) or not isinstance(typed, str) or not qualified(typed.removeprefix("~")):
            raise invalid("entry of another shape", key)
        if typed.removeprefix("~") not in contracts:
            raise invalid("port names an absent contract", key)
    connections, bindings = section("connections"), section("bindings")
    for owner in sorted(set(connections) | set(bindings)):
        if not dotted(owner, owner=True):
            raise invalid("entry of another shape", owner)
        pairs(owner, connections.get(owner, []), bindings.get(owner, []))
    return oracle


def population(bounds: str) -> str:
    """An inventory multiplicity `lower:upper`, upper -1 for unbounded, in the oracle's form."""
    lower, _, upper = bounds.partition(":")
    return lower + ".." + ("*" if upper == "-1" else upper)


def inventory_records(output: str) -> dict[str, list[list[str]]]:
    """The rows of the resolved Pilot inventory in `output` by kind; refused when empty."""
    rows = [line.split("\t")[1:] for line in output.splitlines() if line.startswith("AST\t")]
    if not rows:
        raise ValueError("Architecture integrity: missing resolved Pilot inventory")
    return {kind: [row[1:] for row in rows if row[0] == kind] for kind in {row[0] for row in rows}}



def end_resolver(root: str, refs: dict):
    """The deployment path of a connection end, written relative to its owner path (or from
    the root): an end reached through a reference resolves to the referenced part."""
    targets = {path: values[3] for path, values in refs.items() if len(values) > 3 and values[3]}

    def resolved(owner: str, end: str) -> str:
        path = end if end.startswith(root + ".") else owner + "." + end
        for _ in range(len(targets) + 1):
            prefix = next((ref for ref in sorted(targets, key=len, reverse=True)
                           if path == ref or path.startswith(ref + ".")), None)
            if prefix is None:
                break
            path = targets[prefix] + path[len(prefix):]
        return path

    return resolved


def architecture_integrity(output: str, path: Path | None = None) -> dict[str, int]:
    """TR-09: the deployment against the oracle file.

    Input is the pinned Pilot's resolved semantic inventory, not SysML source or a
    viewer graph. The oracle is the file `path`, by default `ORACLE`, which only `oracle`
    writes; the inventory and the file must agree exactly. The fixed rules hold whatever
    the file lists. Only the first difference is reported.
    """
    oracle = architecture_oracle(path or ORACLE)
    records = inventory_records(output)
    fixed_rules(records, oracle["root"])
    refs = {row[0]: row[1:] for row in records.get("REF", [])}
    parts = {row[0]: row[1:] for row in records.get("PART", [])}
    ports = {row[0]: row[1] for row in records.get("PORT", [])}

    for path, listed in oracle["references"].items():
        actual = refs.get(path, [])
        if len(actual) < 4 or [actual[0], population(actual[1]), actual[3]] != [listed["type"], listed["population"], listed["target"]]:
            raise ValueError("Architecture integrity: invalid endpoint/resource/authority association " + path)

    # Each edge a contract declares counts at every port typed by the contract.
    expected_edges = set()
    for kind in ("connection", "binding"):
        for owner, listed in oracle[kind + "s"].items():
            expected_edges.update((owner, kind, frozenset(pair)) for pair in listed)
        for path, typed in oracle["ports"].items():
            listed = oracle["contracts"][typed.removeprefix("~")].get(kind + "s", [])
            expected_edges.update((path, kind, frozenset(pair)) for pair in listed)
    actual_edges = {(owner, kind, frozenset(endpoints.split("|"))) for owner, _name, kind, endpoints in records.get("EDGE", [])}
    missing = expected_edges - actual_edges
    extra = actual_edges - expected_edges
    if missing:
        owner, kind, endpoints = sorted(missing, key=lambda entry: (entry[0], entry[1], sorted(entry[2])))[0]
        raise ValueError("Architecture integrity: missing required " + kind + " at " + owner + " " + " <-> ".join(sorted(endpoints)))
    if extra:
        owner, kind, endpoints = sorted(extra, key=lambda entry: (entry[0], entry[1], sorted(entry[2])))[0]
        raise ValueError("Architecture integrity: unexpected " + kind + "/bypass at " + owner + " " + " <-> ".join(sorted(endpoints)))
    items = {}
    for path, name, direction, types in records.get("ITEM", []):
        items.setdefault(path, {})[name] = (direction, types)
    # Delegation may join equal directions; each port is checked against its own contract
    # instead of imposing a blanket opposite-directions rule on edges.
    role_contracts = oracle["ports"]
    if set(ports) != set(role_contracts):
        raise ValueError("Architecture integrity: missing or unexpected boundary port roles " + str(sorted(set(ports) ^ set(role_contracts))))
    for path, role in role_contracts.items():
        signature = oracle["contracts"][role.removeprefix("~")]["items"]
        actual = items.get(path, {})
        if set(actual) != set(signature):
            raise ValueError("Architecture integrity: semantic exchange signature mismatch " + path)
        for item, (direction, semantic_type) in signature.items():
            if role.startswith("~"):
                direction = {"in": "out", "out": "in"}[direction]
            actual_direction, actual_type = actual[item]
            if actual_direction != direction:
                raise ValueError("Architecture integrity: wrong exchange direction " + path + "." + item)
            if actual_type != semantic_type:
                raise ValueError("Architecture integrity: wrong semantic item type " + path + "." + item)
    for path, role in sorted(role_contracts.items()):
        if ports[path] != role:
            raise ValueError("Architecture integrity: wrong port definition " + path)
    root = oracle["root"].rsplit("::", 1)[1]
    deployed = {path: values for path, values in parts.items() if path != root}
    listed_parts = oracle["parts"]
    if absent := sorted(set(listed_parts) - set(deployed)):
        raise ValueError("Architecture integrity: missing part " + absent[0])
    if unlisted := sorted(set(deployed) - set(listed_parts)):
        raise ValueError("Architecture integrity: unexpected part " + unlisted[0])
    for path, listed in sorted(listed_parts.items()):
        values = deployed[path]
        if values[0] != listed["type"] or population(values[1]) != listed["population"] \
                or values[2] != ("true" if listed.get("variation") else "false"):
            raise ValueError("Architecture integrity: wrong part type or population " + path)
    if unlisted := sorted(set(refs) - set(oracle["references"])):
        raise ValueError("Architecture integrity: unexpected reference " + unlisted[0])
    # Every port joins a function: it is an end of a connection, an end reached through a
    # reference resolving to the referenced part's port. A binding joins no port.
    resolved = end_resolver(root, refs)
    joined = {resolved(owner, end) for owner, kind, endpoints in actual_edges if kind == "connection"
              for end in endpoints}
    if unjoined := sorted(set(ports) - joined):
        raise ValueError("Architecture integrity: port joined to no function " + unjoined[0])
    return {"parts": len(parts), "references": len(refs), "ports": len(ports), "connections": len(actual_edges)}


def inventory_oracle(records: dict, about: str) -> dict:
    """The oracle file's content for the inventory `records`, whose fixed rules passed:
    every part, reference, port, contract, connection and binding, in the file's form."""
    root = records["ROOTPART"][0][0]
    name = root.rsplit("::", 1)[1]
    oracle = {"about": about, "root": root, "parts": {}, "references": {}, "contracts": {}, "ports": {},
              "connections": {}, "bindings": {}}
    for path, *values in records.get("PART", []):
        if path != name:
            oracle["parts"][path] = {"type": values[0], "population": population(values[1])}
            if values[2] == "true":
                oracle["parts"][path]["variation"] = True
    for path, *values in records.get("REF", []):
        oracle["references"][path] = {"type": values[0], "population": population(values[1]), "target": values[3]}
    for path, typed in records.get("PORT", []):
        oracle["ports"][path] = typed
        oracle["contracts"].setdefault(typed.removeprefix("~"), {"items": {}})
    for path, item, direction, types in records.get("ITEM", []):
        typed = oracle["ports"][path]
        if typed.startswith("~"):
            direction = {"in": "out", "out": "in"}.get(direction, direction)
        oracle["contracts"][typed.removeprefix("~")]["items"][item] = [direction, types]
    for owner, _name, kind, ends in records.get("EDGE", []):
        pair = ends.split("|")
        if owner in oracle["ports"]:
            listed = oracle["contracts"][oracle["ports"][owner].removeprefix("~")].setdefault(kind + "s", [])
        else:
            listed = oracle[kind + "s"].setdefault(owner, [])
        if frozenset(pair) not in map(frozenset, listed):
            listed.append(pair)
    for holder in [*oracle["contracts"].values(), oracle["connections"], oracle["bindings"]]:
        for key, value in holder.items():
            if isinstance(value, list):
                value.sort()
    return oracle


def oracle_text(oracle: dict) -> str:
    """The file text: sections and keys sorted, one entry or pair per line."""
    def dump(value) -> str:
        return json.dumps(value, sort_keys=True)

    lines = ["{"]
    keys = sorted(oracle)
    for index, key in enumerate(keys):
        value, comma = oracle[key], "," if index + 1 < len(keys) else ""
        if not isinstance(value, dict) or not value:
            lines.append(f"  {dump(key)}: {dump(value)}{comma}")
            continue
        lines.append(f"  {dump(key)}: {{")
        entries = sorted(value)
        for position, entry in enumerate(entries):
            inner, separator = value[entry], "," if position + 1 < len(entries) else ""
            if isinstance(inner, list) and inner:
                lines.append(f"    {dump(entry)}: [")
                lines.extend(f"      {dump(pair)}" + ("," if row + 1 < len(inner) else "") for row, pair in enumerate(inner))
                lines.append("    ]" + separator)
            else:
                lines.append(f"    {dump(entry)}: {dump(inner)}{separator}")
        lines.append("  }" + comma)
    return "\n".join(lines + ["}"]) + "\n"


def oracle_changes(old: dict, new: dict) -> list[str]:
    """One line per difference from `old` to `new`, sorted: parts, ports and connections
    added or removed, and `changed <section> <key>` for every other difference."""
    lines = []
    for kind, section in (("part", "parts"), ("port", "ports")):
        before, after = old.get(section, {}), new[section]

        def typed(value):
            return value["type"] if isinstance(value, dict) else value

        lines += [f"added {kind} {key} {typed(after[key])}" for key in after.keys() - before.keys()]
        lines += [f"removed {kind} {key} {typed(before[key])}" for key in before.keys() - after.keys()]
        lines += [f"changed {section} {key}" for key in before.keys() & after.keys() if before[key] != after[key]]

    def pairs(section: dict) -> dict:
        return {(owner, frozenset(pair)): pair for owner, listed in section.items() for pair in listed}

    before, after = pairs(old.get("connections", {})), pairs(new["connections"])
    lines += [f"added connection {key[0]} {' <-> '.join(after[key])}" for key in after.keys() - before.keys()]
    lines += [f"removed connection {key[0]} {' <-> '.join(before[key])}" for key in before.keys() - after.keys()]

    def contract(value: dict) -> tuple:
        return value["items"], *(frozenset(map(frozenset, value.get(kind, []))) for kind in ("bindings", "connections"))

    for section, normal in (("references", lambda value: value), ("contracts", contract),
                            ("bindings", lambda value: frozenset(map(frozenset, value)))):
        before, after = old.get(section, {}), new[section]
        lines += [f"changed {section} {key}" for key in before.keys() | after.keys()
                  if key not in before or key not in after or normal(before[key]) != normal(after[key])]
    if old.get("root") != new["root"]:
        lines.append(f"changed root {new['root']}")
    return sorted(lines)


def write_architecture_oracle(cache: Path) -> list[str]:
    """`oracle` (TR-09): the Pilot validation and the fixed rules on the working tree's
    model, then the file `ORACLE` written from the resolved inventory, keeping its `about`.
    A refusal raises and leaves the file as it was; an equal file is not rewritten."""
    entry = "Requirements.sysml"
    paths = [MODELS / entry, *(path for key, path in model_files(MODELS).items() if key != entry)]
    result = validate(paths, cache, inventory=True)
    if result.returncode:
        for line in result.stdout.splitlines():
            if not line.startswith(("Reading ", "AST\t")):
                print(line)
        print(result.stderr, file=sys.stderr, end="")
        raise ValueError("Semantic validation failed; architecture oracle not written")
    records = inventory_records(result.stdout)
    fixed_rules(records)
    try:
        old = architecture_oracle(ORACLE)
    except ValueError:
        old = {}
    text = oracle_text(inventory_oracle(records, old.get("about", ORACLE_ABOUT)))
    with tempfile.TemporaryDirectory(prefix="sysml-oracle-") as folder:
        written = Path(folder) / ORACLE.name
        written.write_bytes(text.encode("utf-8"))
        new = architecture_oracle(written)
    lines = oracle_changes(old, new)
    # A checkout's CRLF line ends are the same text.
    if not lines and ORACLE.is_file() and ORACLE.read_bytes().replace(b"\r\n", b"\n") == text.encode("utf-8"):
        return ["Architecture oracle unchanged"]
    ORACLE.write_bytes(text.encode("utf-8"))
    counts = {section: len(new[section]) for section in ("parts", "references", "contracts", "ports")}
    counts.update({section: sum(map(len, new[section].values())) for section in ("connections", "bindings")})
    return lines + ["Architecture oracle written: " + ", ".join(f"{count} {kind}" for kind, count in counts.items())]



# The time limit of one Pilot validation run, in seconds (TR-02).
VALIDATOR_SECONDS = 600


def validate(paths: list[Path], cache: Path, inventory: bool = False) -> subprocess.CompletedProcess:
    java, jar, library = tool_paths(cache)
    if not paths or any(not path.is_file() for path in paths):
        raise ValueError("Semantic validation requires existing model files")
    limit = VALIDATOR_SECONDS
    started = time.monotonic()

    def duration() -> None:
        print(f"validator: {time.monotonic() - started:.1f} s (limit {limit:g} s)", file=sys.stderr, flush=True)

    # Cap the heap: the JVM default (a quarter of RAM) let parallel checks take
    # gigabytes next to the real-time station; 512 MB with the serial collector passes.
    # Without performance data the JVM leaves no folder in the temporary folder (TR-23).
    try:
        result = subprocess.run([str(java), "-Xmx512m", "-XX:+UseSerialGC", "-XX:-UsePerfData", "-classpath", str(jar), str(Path(__file__).with_name("sysml") / "Validate.java"), str(library), *(["--inventory"] if inventory else []), *map(str, paths)], text=True, capture_output=True, timeout=limit)
    except subprocess.TimeoutExpired:
        duration()
        raise ValueError(f"validator timed out after {limit:g} s") from None
    duration()
    if result.returncode == 0 and "OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed." not in result.stdout:
        raise ValueError("Validator returned no semantic completion marker")
    return result


# ---- equivalence and identities (TR-21) ----

# A qualified name as written in text: two or more segments, each a word or a quoted name.
QNAME = re.compile(r"(?<![\w':])(?:[A-Za-z_]\w*|'[^'\r\n]+')(?:::(?:[A-Za-z_]\w*|'[^'\r\n]+'))+")
QNAME_SEGMENT = re.compile(r"(?:[A-Za-z_]\w*|'[^'\r\n]+')(?:::|$)")
MODEL_PATH = re.compile(r"docs/sysml/[\w./-]*[\w/]")
LINK = re.compile(r"\]\(\s*<?([^)\s>]+)>?\s*\)")
# The tracked files at <head> whose model citations `equivalence` checks.
CITATION_ROOTS = ("server", "client", "tests", "tools", "fixtures", "harness/project", "docs/harness", ".harness", "README.md")
# P6: the tests below READERS that judge their own fixture model.
READERS = "tools/sysml/tests/"
FIXTURE_PACKAGE = re.compile(r"\bpackage\s+([A-Za-z_]\w*)\s*\{")
MOVE_TRAILER = re.compile(r"(?m)^Model-Move:\s*pure\s*$")
EXPORT_WORKERS = 2


class Unreadable(ValueError):
    """A revision that cannot be compared: exit 2 with the reason."""


def git(*args: str) -> str:
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    result = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, encoding="utf-8",
                            errors="replace", env=env)
    if result.returncode:
        raise Unreadable(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


def commit_of(revision: str) -> str:
    try:
        return git("rev-parse", "--verify", "--quiet", revision + "^{commit}").strip()
    except Unreadable:
        raise Unreadable("unknown revision: " + revision) from None


def extract(commit: str, destination: Path, paths=()) -> None:
    """The tree of `commit` (or only `paths` of it) written below `destination` with `git
    archive`; links are left out. Nothing in the repository is written."""
    destination.mkdir(parents=True, exist_ok=True)
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    # The whole archive is read before it is unpacked: a stream reader stops at the
    # end-of-archive blocks and leaves git blocked on the rest of its output.
    try:
        result = subprocess.run(["git", "-C", str(ROOT), "archive", "--format=tar", commit, *paths],
                                stdin=subprocess.DEVNULL, capture_output=True, env=env, timeout=600)
    except subprocess.TimeoutExpired:
        raise Unreadable(f"git archive {commit} {' '.join(paths)}: timed out") from None
    if result.returncode:
        raise Unreadable(f"git archive {commit} {' '.join(paths)}: {result.stderr.decode('utf-8', 'replace').strip()}")
    try:
        with tarfile.open(fileobj=io.BytesIO(result.stdout), mode="r:") as archive:
            for member in archive:
                if member.isfile() or member.isdir():
                    archive.extract(member, destination, filter="data")
    except tarfile.TarError as error:
        raise Unreadable(f"git archive {commit} {' '.join(paths)}: {error}") from None


def citation_reader(path: str, text: str):
    """P6 (TR-21): which model the tracked file `path` with `text` reads. A file below
    READERS that declares `package <Top> {` is a fixture reader: ("fixture", {Top, ...}).
    Else None."""
    if not path.startswith(READERS):
        return None
    tops = set(FIXTURE_PACKAGE.findall(text.replace("\r\n", "\n").replace("\r", "\n")))
    return ("fixture", tops) if tops else None


def in_tree(commit: str, path: str) -> bool:
    """Whether `path` (a file or folder) is in the tree of `commit`."""
    try:
        git("cat-file", "-e", f"{commit}:{path.rstrip('/')}")
        return True
    except Unreadable:
        return False


def top_packages(code: str) -> set[str]:
    """The packages declared at the top level of blanked model text."""
    matches = list(re.finditer(r"\b(?:(?:standard\s+)?library\s+)?package\s+(\w+|'[^']*')\s*[{;]", code))
    owners = owning_bodies(code, [match.start() for match in matches])
    return {match[1] for match in matches if owners[match.start()] == -1}


def line_notes(source: str) -> list[str]:
    """The texts of the line notes (`// ...`) of a model file, in order."""
    tokens = re.finditer(r'/\*[\s\S]*?\*/|//[^\r\n]*|' + STRING + r'|\'(?:\\.|[^\'\\])*\'|[^/"\']+|.', source)
    return [token.group()[2:].strip() for token in tokens if token.group().startswith("//")]


class Side:
    """One revision of the model: a commit extracted below a temporary folder, or the
    working tree (`commit` None), read in place."""

    def __init__(self, label: str, root: Path, commit):
        self.label, self.root, self.commit = label, root, commit
        self.models = root / "docs/sysml"
        files = model_files(self.models) if self.models.is_dir() else {}
        entry = "Requirements.sysml"
        self.keys = ([entry] if entry in files else []) + [key for key in files if key != entry]
        self.paths = [files[key] for key in self.keys]
        self.sources = {key: files[key].read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
                        for key in self.keys}
        codes = {key: blanked(source) for key, source in self.sources.items()}
        self.package_of = {key: file_package(code) for key, code in codes.items()}
        self.tops = set().union(*(top_packages(code) for code in codes.values())) if codes else set()
        self.export = None

    def tracked(self) -> list[str]:
        """The tracked files below the citation roots, as repository paths."""
        if self.commit:
            listing = git("ls-tree", "-r", "--name-only", "-z", self.commit, "--", *CITATION_ROOTS)
        else:
            listing = git("ls-files", "-z", "--", *CITATION_ROOTS)
        return sorted(path for path in listing.split("\0") if path)

    def citations(self, tops: set[str]) -> list[tuple[str, int, str, str]]:
        """(file, line, kind, citation) of each model citation in the tracked files: a
        qualified name starting with one of `tops`, or a `docs/sysml/...` path."""
        found = set()
        for path in self.tracked():
            file = self.root / path
            try:
                if not file.is_file() or file.stat().st_size > 2_000_000:
                    continue
                data = file.read_bytes()
            except OSError:
                continue
            if b"\0" in data[:8192]:
                continue
            lines = data.decode("utf-8", "replace").splitlines(keepends=True)
            # Each line with one "\n" as its end: the offsets of the string reader are line offsets.
            lines = [line.rstrip("\r\n\v\f\x1c\x1d\x1e\x85  ") + "\n" for line in lines]
            starts = [0]
            for line in lines:
                starts.append(starts[-1] + len(line))
            strings = string_lookups(path, "".join(lines), tops) if strings_read(path) else None
            spans = strings[0] if strings else []
            for number, line in enumerate(lines, 1):
                for match in QNAME.finditer(line):
                    at = starts[number - 1] + match.start()
                    if match[0].split("::", 1)[0] in tops and not any(begin <= at < end for begin, end in spans):
                        found.add((path, number, "name", match[0]))
                for match in MODEL_PATH.finditer(line):
                    found.add((path, number, "path", match[0].rstrip(".")))
            if strings:
                for kind, cited in (("lookup", strings[1]), ("joined", strings[2])):
                    for at, name in cited:
                        number = bisect.bisect_right(starts, at)
                        if (path, number, "lookup", name) not in found:
                            found.add((path, number, kind, name))
        return sorted(found)


# P6 in test and tool strings: a lookup prefix (a qualified name ending in `::`), a name or a
# relative qualified name, and the characters that open or close a string.
LOOKUP_PREFIX = re.compile(r"(?<![\w':])(?:[A-Za-z_]\w*|'[^'\r\n]+')(?:::(?:[A-Za-z_]\w*|'[^'\r\n]+'))*::")
RELATIVE_NAME = re.compile(r"(?:[A-Za-z_]\w*|'[^'\r\n]+')(?:::(?:[A-Za-z_]\w*|'[^'\r\n]+'))*")
STRING_QUOTES = "'\"`“”„‘’‚‛"


def string_lookups(path: str, source: str, tops: set[str]):
    """P6 (TR-21) in the strings of the test or tool code `source` ("\\n" line ends):
    ([(start, end)] of its string contents, [(offset, whole name)], [(offset, joined name)]), or
    None when its strings cannot be read. A whole name is a qualified name starting with one of
    `tops` inside a string's contents. A lookup prefix is a qualified name ending in `::` whose first segment is
    in `tops`, followed by a `${` or `{` placeholder (`{{` is none) or by the end of its string;
    each string literal whose whole text is a name or a relative qualified name not starting
    with one of `tops` is joined to each prefix of the file, at the literal's offset."""
    try:
        spans = [(begin, end) for kind, begin, end in source_segments(path, source)[0] if kind == "string"]
    except (SourceUnreadable, RecursionError):
        return None
    prefixes, literals, whole = set(), [], []
    for begin, end in spans:
        content = source[begin:end]
        whole.extend((begin + match.start(), match[0]) for match in QNAME.finditer(content)
                     if match[0].split("::", 1)[0] in tops)
        for match in LOOKUP_PREFIX.finditer(content):
            if match[0].split("::", 1)[0] not in tops:
                continue
            after = begin + match.end()
            brace = source[after:after + 1] == "{" and source[after + 1:after + 2] != "{"
            if brace or after == end and (source.startswith("${", after) or source[after:after + 1] in STRING_QUOTES):
                prefixes.add(match[0])
        if RELATIVE_NAME.fullmatch(content) and content.split("::", 1)[0] not in tops \
                and begin > 0 and source[begin - 1] in STRING_QUOTES and source[end:end + 1] in STRING_QUOTES:
            literals.append((begin, content))
    return spans, whole, [(at, prefix + literal) for at, literal in literals for prefix in sorted(prefixes)]


def declared(side: Side, citation: str) -> bool:
    """Whether `citation` names an element declared on an exported side under that qualified
    name: an entry of its export. A quoted segment names the element whose name it quotes."""
    segments = re.findall(r"[A-Za-z_]\w*|'[^'\r\n]+'", citation)
    key = "::".join(segment[1:-1] if segment.startswith("'") and re.fullmatch(r"[A-Za-z_]\w*", segment[1:-1])
                    else segment for segment in segments)
    return key in side.export["entries"]


def run_export(side: Side, names: list[str], cache: Path, folder: Path) -> dict:
    """The Pilot export of one side: packages, entries, package-level items and the
    resolution of `names`. A side that fails the Pilot validation is Unreadable."""
    java, jar, library = tool_paths(cache)
    if not side.paths:
        raise Unreadable(f"{side.label}: no model files below docs/sysml")
    listing = folder / f"names-{id(side)}.txt"
    listing.write_text("\n".join(names) + "\n", encoding="utf-8")
    result = subprocess.run([str(java), "-Xmx1g", "-XX:+UseSerialGC", "-classpath", str(jar),
                             str(Path(__file__).with_name("sysml") / "Validate.java"), str(library), "--export", str(listing),
                             *map(str, side.paths)],
                            capture_output=True, encoding="utf-8", errors="replace", timeout=900)
    if result.returncode or "OMG Pilot 0.62.0 syntax/name/semantic validation passed" not in result.stdout:
        messages = [line for line in result.stdout.splitlines() if not line.startswith(("Reading ", "EXPORT\t"))]
        messages += result.stderr.strip().splitlines()[:5]
        raise Unreadable(f"{side.label} fails the Pilot validation: " + "; ".join(messages[:5]))
    export = {"packages": {}, "entries": {}, "items": [], "resolved": {}}

    def facts(rows) -> tuple:
        return tuple((path, kind, feature, tuple(value) if isinstance(value, list) else value)
                     for path, kind, feature, value in rows)

    def file_key(index: int) -> str:
        return side.keys[index] if 0 <= index < len(side.keys) else "?"

    for line in result.stdout.splitlines():
        if not line.startswith("EXPORT\t"):
            continue
        _, kind, body = line.split("\t", 2)
        data = json.loads(body)
        if kind == "PACKAGE":
            export["packages"][data["name"]] = file_key(data["file"])
        elif kind == "ITEM":
            export["items"].append({"file": file_key(data["file"]), "facts": facts(data["facts"])})
        elif kind == "ENTRY":
            segments = data["key"]
            key = "::".join(segments)
            while key in export["entries"]:
                key += "~"
            owner = "::".join(segments[:-1]) if len(segments) > 2 else None
            export["entries"][key] = {"key": key, "rel": "::".join(segments[1:]), "package": segments[0], "owner": owner,
                                      "file": file_key(data["file"]), "facts": facts(data["facts"])}
        elif kind == "RESOLVE":
            export["resolved"][data["name"]] = data["id"]
    return export


def resolve_links(text: str, file_key: str, package_of: dict) -> str:
    """`text` with each relative Markdown link of the model file `file_key` resolved (P4):
    a link to a model file (a key of `package_of`) as the package it holds, any other as
    its path below the repository; a URL or a bare anchor stays as written."""

    def link(match) -> str:
        target = match[1]
        if re.match(r"[A-Za-z][\w+.-]*:|#", target):
            return match[0]
        path, _, anchor = target.partition("#")
        full = posixpath.normpath(posixpath.join("docs/sysml", posixpath.dirname(file_key),
                                                 urllib.parse.unquote(path)))
        model = full[len("docs/sysml/"):] if full.startswith("docs/sysml/") else None
        resolved = f"package:{package_of[model]}" if model in package_of else "file:" + full
        return "](<" + resolved + ">" + ("#" + anchor if anchor else "") + ")"

    return LINK.sub(link, text)


class Normal:
    """Normalises the facts of one side for comparison. `token` maps an entry key to the
    token its references compare by."""

    def __init__(self, side: Side, token):
        self.side, self.token = side, token

    def ref(self, value: str) -> str:
        if value.startswith("M:"):
            key, separator, path = value[2:].partition("#")
            return self.token(key) + separator + path
        return value

    def text(self, body: str, file_key: str) -> str:
        lines = [line.rstrip() for line in body.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
        rest = [line for line in lines[1:] if line.strip()]
        indent = min((len(line) - len(line.lstrip()) for line in rest), default=0)
        body = "\n".join(lines[:1] + [line[indent:] for line in lines[1:]]).strip()

        def name(match) -> str:
            target = self.side.export["resolved"].get(match[0])
            return "<" + self.ref(target) + ">" if target else match[0]

        return QNAME.sub(name, resolve_links(body, file_key, self.side.package_of))

    def facts(self, facts: tuple, file_key: str) -> tuple:
        return tuple((path, kind, feature,
                      tuple(self.ref(value) for value in values) if kind == "ref" else
                      self.text(values, file_key) if kind == "text" else values)
                     for path, kind, feature, values in facts)


def label(fact, facts: tuple = ()) -> str:
    """The property or relationship kind a differing fact names; a fact of the element
    itself is named with the element's class, taken from `facts`."""
    path, kind, feature, _value = fact
    if path == "" and kind == "kind":
        return "kind"
    classes = [step.split("[", 1)[0] for step in path.split("/") if step]
    if kind == "text":
        return "doc" if classes and classes[-1] == "Documentation" else "comment"
    if not classes:
        own = next((value for step, sort, _feature, value in facts if step == "" and sort == "kind"), None)
        classes = [own] if own else []
    return "/".join(classes) + "." + (feature or "kind") if classes else feature or "kind"


def summary(facts: tuple) -> str:
    """A package-level item in one phrase: the class it owns and the start of its text."""
    owned = next((value for path, kind, _feature, value in facts if kind == "kind" and path.count("/") == 0 and path), None)
    text = next((value for _path, kind, _feature, value in facts if kind == "text"), "")
    words = " ".join(text.split())
    return (owned or facts[0][3]) + (" " + json.dumps(words[:60]) if words else "")


def compare(base: Side, head: Side, citations: list, exempt=None) -> tuple[int, list[str]]:
    """P2 to P6 of TR-21 for two exported sides: (exit code, lines). `exempt` maps a citation
    of a fixture reader to its reader kind (`exemptions`)."""
    entries_b, entries_h = base.export["entries"], head.export["entries"]

    def by_rel(entries):
        grouped = {}
        for key, entry in entries.items():
            grouped.setdefault(entry["rel"], []).append(key)
        return grouped

    def rel(entries, key: str) -> str:
        return entries[key]["rel"] if key in entries else key.partition("::")[2]

    def children(entries) -> dict:
        found = {}
        for key, entry in entries.items():
            if entry["owner"]:
                found.setdefault(entry["owner"], []).append(key)
        return found

    def deep(entries, members, normal, memo, key):
        """An element's own facts and those of its named members, by member name: the
        content same-named elements are paired by."""
        if key not in memo:
            entry = entries[key]
            nested = sorted((entries[member]["rel"].rsplit("::", 1)[-1], repr(deep(entries, members, normal, memo, member)))
                            for member in members.get(key, []))
            memo[key] = (normal.facts(entry["facts"], entry["file"]), tuple(nested))
        return memo[key]

    loose_b = Normal(base, lambda key: "R:" + rel(entries_b, key))
    loose_h = Normal(head, lambda key: "R:" + rel(entries_h, key))
    members_b, members_h, memo_b, memo_h = children(entries_b), children(entries_h), {}, {}
    rel_b, rel_h = by_rel(entries_b), by_rel(entries_h)
    pair, missing, added = {}, [], []
    # Owners first, so that a member prefers the counterpart under its owner's counterpart.
    # Among equal candidates each name is paired in passes, so that no element takes a
    # candidate another one is preferred for: a member of a paired owner under the owner's
    # counterpart; then a top-level element, or a member of an unpaired owner, in its own
    # package (P3 still allows a change of package); then any equal one. File order decides
    # only among candidates no pass tells apart.
    for name in sorted(set(rel_b) | set(rel_h), key=lambda name: (len(QNAME_SEGMENT.findall(name)), name)):
        bases, heads = rel_b.get(name, []), list(rel_h.get(name, []))
        if len(bases) == 1 and len(heads) == 1:
            pair[bases[0]] = heads[0]
            continue
        matches = {}
        for key in bases:
            content = deep(entries_b, members_b, loose_b, memo_b, key)
            matches[key] = [other for other in heads if deep(entries_h, members_h, loose_h, memo_h, other) == content]

        def by_owner(key, other):
            owner = entries_b[key]["owner"]
            return owner in pair and entries_h[other]["owner"] == pair[owner]

        def by_package(key, other):
            owner = entries_b[key]["owner"]
            return (owner is None or owner not in pair) and entries_h[other]["package"] == entries_b[key]["package"]

        for preferred in (by_owner, by_package, lambda _key, _other: True):
            for key in bases:
                if key in pair:
                    continue
                match = next((other for other in matches[key] if other in heads and preferred(key, other)), None)
                if match is not None:
                    pair[key] = match
                    heads.remove(match)
        missing.extend(key for key in bases if key not in pair)
        added.extend(heads)
    paired = set(pair.values())
    strict_b = Normal(base, lambda key: "M:" + pair[key] if key in pair else "U:" + rel(entries_b, key))
    strict_h = Normal(head, lambda key: "M:" + key if key in paired else "U:" + rel(entries_h, key))
    differences, moves, info = [], [], []

    changed = []
    for key_b, key_h in sorted(pair.items()):
        b, h = entries_b[key_b], entries_h[key_h]
        facts_b, facts_h = strict_b.facts(b["facts"], b["file"]), strict_h.facts(h["facts"], h["file"])
        if facts_b != facts_h:
            index = next((i for i, (x, y) in enumerate(zip(facts_b, facts_h)) if x != y), min(len(facts_b), len(facts_h)))
            fact = facts_b[index] if index < len(facts_b) else facts_h[index]
            changed.append(f"changed {b['rel']} {label(fact, facts_b)} {b['file']} -> {h['file']}")
    # A pair whose owner is a named element has paired owners.
    for key_b, key_h in sorted(pair.items()):
        owner_b, owner_h = entries_b[key_b]["owner"], entries_h[key_h]["owner"]
        if owner_b is not None and pair.get(owner_b) != owner_h:
            b, h = entries_b[key_b], entries_h[key_h]
            differences.append(f"changed {b['rel']} owner {b['file']} -> {h['file']}")
    for key in missing:
        entry = entries_b[key]
        differences.append(f"missing {entry['rel']} {entry['package']} {entry['file']}")
    for key in added:
        entry = entries_h[key]
        differences.append(f"added {entry['rel']} {entry['package']} {entry['file']}")
    differences.extend(changed)
    pairs = Counter()
    for key_b, key_h in sorted(pair.items()):
        b, h = entries_b[key_b], entries_h[key_h]
        if (b["package"], b["file"]) != (h["package"], h["file"]):
            moves.append(f"moved {b['rel']} {b['package']} {b['file']} -> {h['package']} {h['file']}")
            pairs[(b["file"], h["file"])] += 1
    # P3: package-level items as a multiset, whatever package holds them.
    items = []
    for side, normal in ((base, strict_b), (head, strict_h)):
        found = {}
        for item in side.export["items"]:
            found.setdefault(normal.facts(item["facts"], item["file"]), []).append(item["file"])
        items.append(found)
    count_b = Counter({facts: len(files) for facts, files in items[0].items()})
    count_h = Counter({facts: len(files) for facts, files in items[1].items()})
    for word, extra, files in (("missing", count_b - count_h, items[0]), ("added", count_h - count_b, items[1])):
        for facts, number in sorted(extra.items(), key=lambda pair_: summary(pair_[0])):
            for file in files[facts][:number]:
                differences.append(f"{word} package-level {summary(facts)} {file}")
    # P4: line notes as a multiset over the whole model.
    notes = []
    for side in (base, head):
        found = {}
        for key, source in side.sources.items():
            for note in line_notes(source):
                found.setdefault(note, []).append(key)
        notes.append(found)
    count_b = Counter({note: len(files) for note, files in notes[0].items()})
    count_h = Counter({note: len(files) for note, files in notes[1].items()})
    for word, extra, files in (("missing", count_b - count_h, notes[0]), ("added", count_h - count_b, notes[1])):
        for note, number in sorted(extra.items()):
            for file in files[note][:number]:
                differences.append(f"{word} note {json.dumps(note)} {file}")
    # P6: citations outside the model, read at <head>; an exempt one is an info line.
    exempt, exempt_counts = exempt or {}, {}
    for path, line, kind, citation in citations:
        on_b, on_h = on_side(base, kind, citation), on_side(head, kind, citation)
        if on_b and not on_h:
            reader = exempt.get((path, line, kind, citation))
            if reader:
                info.append(f"exempt {path}:{line} {citation} ({reader})")
                exempt_counts[path] = exempt_counts.get(path, 0) + 1
            else:
                differences.append(f"stale-by-change {path}:{line} {citation}")
        elif not on_b and not on_h and kind != "joined":
            info.append(f"unresolved {path}:{line} {citation}")
    lines = differences + moves + [f"pair {files[0]} -> {files[1]}: {count}" for files, count in sorted(pairs.items())] + info
    lines.append((f"{len(differences)} differences; {len(pair)} entries paired, {len(moves)} moved"
                  if differences else f"equivalent: {len(pair)} entries paired, {len(moves)} moved")
                 + ("; exempt: " + ", ".join(f"{path} {count}" for path, count in exempt_counts.items())
                    if exempt_counts else ""))
    return (1 if differences else 0), lines


def on_side(side: Side, kind: str, citation: str) -> bool:
    """Whether a citation resolves on an exported side: a written name by the Pilot's
    resolution, a lookup name of test or tool code (`lookup`, `joined`) by declaration, a path
    in its tree."""
    if kind == "name":
        return side.export["resolved"].get(citation) is not None
    if kind in ("lookup", "joined"):
        return declared(side, citation)
    return (side.root / citation).exists()


def exemptions(pairs: list, citations: list) -> list[dict]:
    """P6 for each exported (base, head) pair: {(file, line, kind, citation): "fixture"} for
    each name citation that would be stale-by-change in a fixture reader of its package."""
    readers, found = {}, []
    for (base, head), cited in zip(pairs, citations):
        marks = {}
        for path, line, kind, citation in cited:
            if kind == "path" or not path.startswith(READERS) or not on_side(base, kind, citation) or on_side(head, kind, citation):
                continue
            if (id(head), path) not in readers:
                try:
                    text = (head.root / path).read_text(encoding="utf-8", errors="replace")
                except OSError:
                    text = ""
                readers[(id(head), path)] = citation_reader(path, text)
            reader = readers[(id(head), path)]
            if reader is not None and citation.split("::", 1)[0] in reader[1]:
                marks[(path, line, kind, citation)] = "fixture"
        found.append(marks)
    return found


def compare_revisions(pairs: list[tuple[str, object]], cache: Path) -> tuple[list[tuple[int, list[str]]], int]:
    """P1 for each (base, head) pair, head None for the working tree, with one Pilot export
    per distinct tree: ([(exit code, lines)], number of exports)."""
    with tempfile.TemporaryDirectory(prefix="sysml-equivalence-") as folder:
        folder = Path(folder)
        sides = {}

        def side_of(revision):
            if revision is None:
                if None not in sides:
                    sides[None] = Side("working tree", ROOT, None)
                return sides[None]
            commit = commit_of(revision)
            tree = git("rev-parse", commit + "^{tree}").strip()
            if tree not in sides:
                extract(commit, folder / tree[:16])
                sides[tree] = Side(revision, folder / tree[:16], commit)
            return sides[tree]

        resolved = [(side_of(base), side_of(head)) for base, head in pairs]
        citations = [head.citations(base.tops | head.tops) for base, head in resolved]
        names = set()
        for side in sides.values():
            for source in side.sources.values():
                names.update(QNAME.findall(source))
        for found in citations:
            names.update(citation for _path, _line, kind, citation in found if kind == "name")
        names = sorted(names)

        def exported(chosen, wanted):
            chosen = [side for side in chosen if side.export is None]
            with ThreadPoolExecutor(max_workers=EXPORT_WORKERS) as pool:
                exports = {id(side): pool.submit(run_export, side, sorted(wanted.get(id(side), names)), cache, folder)
                           for side in chosen}
                for side in chosen:
                    side.export = exports[id(side)].result()

        exported(list(sides.values()), {})
        exempt = exemptions(resolved, citations)
        return [compare(base, head, found, marks)
                for (base, head), found, marks in zip(resolved, citations, exempt)], len(sides)


def marked(cache: Path) -> tuple[int, list[str]]:
    """P8: each commit of master..HEAD with the trailer `Model-Move: pure` against its first parent."""
    log = git("log", "--reverse", "--format=%H %P%x1f%B%x1e", "master..HEAD")
    commits, lines = [], []
    for record in log.split("\x1e"):
        if not record.strip():
            continue
        head, _, message = record.strip().partition("\x1f")
        sha, *parents = head.split()
        if MOVE_TRAILER.search(message) and parents:
            commits.append((parents[0], sha))
            lines.append(f"checked {sha}")
        else:
            lines.append(f"skipped {sha} (no Model-Move: pure)")
    if not commits:
        return 0, lines + ["no marked commit"]
    results, exports = compare_revisions(commits, cache)
    lines.append(f"{exports} exports")
    failed = []
    for (_parent, sha), (code, found) in zip(commits, results):
        lines.append(f"commit {sha}: " + ("equivalent" if code == 0 else "differences"))
        lines.extend("  " + line for line in found)
        if code:
            failed.append(sha)
    lines.append(f"{len(commits)} marked commits checked; " + (f"differences in {', '.join(failed)}" if failed else "all equivalent"))
    return (1 if failed else 0), lines


def identity_side(directory: Path) -> dict:
    """P7: identity -> (text, file, package) of one side, read from the declarations without
    validating the tree."""
    files = model_files(directory) if directory.is_dir() else {}
    sources = {key: path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n") for key, path in files.items()}
    codes = {key: blanked(source, strings=False) for key, source in sources.items()}
    tops = set().union(*(top_packages(blanked(source)) for source in sources.values())) if sources else set()
    package_of = {key: file_package(blanked(source)) for key, source in sources.items()}

    def normal(text: str, key: str) -> str:
        text = resolve_links(text, key, package_of)
        return re.sub(r"(?<![\w:'])(\w+)::", lambda match: "" if match[1] in tops else match[0], text)

    entries, dependencies = {}, {}
    for key in files:
        source, code = sources[key], codes[key]
        spans = []
        for match in DECLARATION.finditer(code):
            opening = match.end() - 1
            end = opening + len(declaration_body(code, opening)) + 2
            spans.append((match.start(), end))
            entries.setdefault(match[3], (normal(source[match.start():end], key), key, package_of[key]))
        for match in re.finditer(r"\bdependency\b[^;{}]*;", code):
            if any(start <= match.start() < end for start, end in spans):
                continue
            origin = re.search(r"\bfrom\s+(?:(?:\w+|'[^']*')::)*'(" + IDENTITY + r")'", match[0])
            if origin:
                dependencies.setdefault(origin[1], []).append(" ".join(normal(source[match.start():match.end()], key).split()))
    texts = {identity: (text + "\n" + "\n".join(sorted(dependencies.get(identity, []))), key, package)
             for identity, (text, key, package) in entries.items()}
    return texts


STATUSES = ("unchanged", "moved", "changed", "added", "removed")


def identities(base: str, head) -> tuple[int, list[str]]:
    """P7: one line per identity of either side, then a count per status."""
    with tempfile.TemporaryDirectory(prefix="sysml-identities-") as folder:
        sides = []
        for name, revision in (("base", base), ("head", head)):
            if revision is None:
                sides.append(identity_side(MODELS))
                continue
            extract(commit_of(revision), Path(folder) / name, ["docs/sysml"])
            sides.append(identity_side(Path(folder) / name / "docs/sysml"))
    old, new = sides
    lines, counts = [], Counter()

    def order(identity: str):
        return ("FR", "CL", "TC").index(identity[:2]), identity

    for identity in sorted(set(old) | set(new), key=order):
        before, after = old.get(identity), new.get(identity)
        suffix = ""
        if before and after:
            status = "changed" if before[0] != after[0] else "unchanged" if before[1:] == after[1:] else "moved"
        elif after:
            status = "added"
        else:
            status = "removed"
        counts[status] += 1
        lines.append(f"{identity} {status} {before[1] if before else '-'} -> {after[1] if after else '-'}{suffix}")
    lines.append(f"{len(lines)} identities: " + ", ".join(f"{counts[status]} {status}" for status in STATUSES))
    return 0, lines

# ---- The rules of the finished model (TR-03 to TR-08, TR-11, TR-13, TR-15 to TR-18) ----

# M2.1: the model files by folder; `*` marks a part's own file, whose package adds `Part`.
MODEL_TREE = {
    "": ("Context", "Requirements", "Shack", "UseCases"),
    "interfaces/internal": ("StationLink", "StationCommands", "Strategies", "RankingControl", "AutoControl",
                            "QsoControl", "LogControl", "ReceiveControl", "TransmitControl", "AudioControl",
                            "RadioControl", "Keying", "Decodes", "DisplayData", "StationTime", "OperatingChain",
                            "Hearing", "AudioStreams", "ModeProcessing", "ProfileAccess", "RecordingTransfer",
                            "UdpControl", "WebControl"),
    "interfaces/external": ("OperatorInteraction", "Mcp", "Cat", "RadioProperties", "FlexApi", "SoundDevice", "Udp",
                            "PskReporter", "ClubLog", "CountryFiles", "TimeSource"),
    "backend/supervisor": ("Supervisor*", "OperatingSelection", "StationAuthority", "Startup", "SettingsCheck"),
    "backend/web": ("Web*", "Listener", "ContentCoding"),
    "backend/mcp": ("Mcp*", "McpEndpoint"),
    "backend/profile": ("Profile*", "ProfileDocument", "Recordings"),
    "backend/receive": ("Receive*", "ReceiveJob", "Spectrum", "LiveReceive"),
    "backend/modes": ("Modes*", "Decode", "MessageEncode", "MessagePayload"),
    "backend/clock": ("Clock*", "StationClock"),
    "backend/transmit": ("Transmit*", "TransmitState", "Schedule", "TxLevel"),
    "backend/operating": ("Operating*", "StrategySelection"),
    "backend/operating/ranking": ("Ranking*", "ValueOrder", "ContestRanking", "IgnoreLists", "WantedList",
                                  "MostWanted", "Alert"),
    "backend/operating/auto": ("Auto*", "TargetChoice", "CqWhenIdle", "TxSlot", "Leave", "AutoMode"),
    "backend/operating/qso": ("Qso*", "StandardQso", "SpecialActivities", "MessageChoice", "QsoTransmit", "HoldTx"),
    "backend/log": ("Log*", "Logbook", "CountryFile"),
    "backend/spots": ("Spots*", "HearingFeed", "SpotsReporting"),
    "backend/udp": ("Udp*", "UdpSender"),
    "backend/audio": ("Audio*", "AudioDevice", "Capture", "Endpoints", "Playback"),
    "backend/radioControl": ("RadioControl*", "CatControl", "CatLifecycle", "RadioFacts", "RadioSetup"),
    "backend/flexAdapter": ("FlexAdapter*", "FlexSession"),
    "frontend": ("BrowserClient*", "OperatingScreen", "BandActivityPane", "SignalArea", "QsoPane", "LowerPanel",
                 "Settings"),
    "shared": ("Units", "ModelBindings", "ModelNotes"),
}
DATA_FOLDER = "data/"
SHACK_FILE = "Shack.sysml"
USE_CASES_FILE = "UseCases.sysml"
REQUIREMENTS_FILE = "Requirements.sysml"
STATION_LINK = "interfaces/internal/StationLink.sysml"
STATION_COMMANDS = "interfaces/internal/StationCommands.sysml"
# M3.4: the transport files and the operating chain's file, which no control interface names.
TRANSPORT_PACKAGES = ("WstxStationLink", "WstxMcp", "WstxOperatingChain")
LINE_LIMIT = 100


def tree_files() -> dict[str, str]:
    """The model file keys of M2.1 with the package each declares (M7.5)."""
    found = {}
    for folder, names in MODEL_TREE.items():
        for name in names:
            plain = name.rstrip("*")
            found[(folder + "/" if folder else "") + plain + ".sysml"] = "Wstx" + plain + ("Part" if name.endswith("*") else "")
    return found


def layer(key: str):
    """M3.1: the layer of a model file, counted from 0 (shared); None for Requirements.sysml
    and a file of no layer."""
    if key.startswith("shared/"):
        return 0
    if key.startswith("interfaces/"):
        return 1
    if key.startswith(("backend/", "frontend/")):
        return 2
    return {SHACK_FILE: 3, CONTEXT_FILE: 4, USE_CASES_FILE: 5}.get(key)


def part_folder(key: str):
    """The part a model file belongs to, as its folder: `frontend`, `backend/<part>`, or for a
    part inside operating `backend/operating/<part>`; None for any other file."""
    parts = key.split("/")
    if parts[0] == "frontend" and len(parts) >= 2:
        return "frontend"
    if parts[0] == "backend" and len(parts) >= 3:
        if parts[1] == "operating" and len(parts) >= 4:
            return "/".join(parts[:3])
        return "/".join(parts[:2])
    return None


def structure_code(source: str) -> str:
    """`source` with comments, the inside of strings and every `doc` and `comment` with its
    body replaced by spaces; offsets and line breaks kept."""
    code = blanked(source)
    for match in list(re.finditer(r"\b(?:doc|comment)\b", code)):
        opening = source.find("/*", match.end())
        if opening < 0 or re.search(r"[;{}]", code[match.end():opening]):
            continue
        closing = source.find("*/", opening)
        end = len(source) if closing < 0 else closing + 2
        code = code[:match.start()] + re.sub(r"[^\r\n]", " ", code[match.start():end]) + code[end:]
    return code


def statement_end(code: str, begin: int, end: int) -> int:
    """The end of the statement starting at `begin`: after its `;` or its body's `}`."""
    depth = 0
    for index in range(begin, end):
        if code[index] == "{":
            depth += 1
        elif code[index] == "}":
            depth -= 1
            if depth <= 0:
                return index + 1
        elif code[index] == ";" and depth == 0:
            return index + 1
    return end


KIND = re.compile(
    r"(?:(?:private|public|protected|abstract|variation|ref|in|out|inout|end|derived|readonly|individual|then|first|"
    r"constant)\s+)*"
    r"(use\s+case\s+def\b|use\s+case\b|(?:part|attribute|item|port|interface|connection|action|state|enum|requirement|"
    r"verification|metadata|calc|constraint|occurrence|flow|view|analysis|concern|allocation|viewpoint|rendering)\s+def\b|"
    r"library\s+package\b|package\b|import\b|alias\b|part\b|attribute\b|item\b|port\b|interface\b|connection\b|action\b|"
    r"state\b|enum\b|requirement\b|verification\b|metadata\b|calc\b|constraint\b|occurrence\b|flow\b|view\b|subject\b|"
    r"actor\b|objective\b|satisfy\b|verify\b|assert\b|assume\b|require\b|expose\b|connect\b|bind\b|binding\b|"
    r"succession\b|transition\b|entry\b|exit\b|do\b|accept\b|send\b|perform\b|exhibit\b|include\b|event\b|message\b|"
    r"dependency\b|@|#)")
NAME = re.compile(r"\s*(?:<[^<>]*>\s*)?('(?:[^'\\]|\\.)*'|[A-Za-z_]\w*)")
NONSPACE = re.compile(r"\S")


class Element:
    """One statement of a model file: its kind (`part def`, `attribute`, `@`, ...), its name
    (None for an unnamed one), its offsets, its body's elements and its docs."""

    def __init__(self, key: str, kind: str, name, begin: int, stop: int, opening: int, parent, head: str):
        self.key, self.kind, self.name, self.begin, self.stop = key, kind, name, begin, stop
        self.opening, self.parent, self.head = opening, parent, head
        self.children, self.docs, self.line = [], [], 0

    @property
    def doc(self) -> str:
        """The text of its first doc, whitespace collapsed; "" without one."""
        return " ".join(self.docs[0][1].split()) if self.docs else ""

    def walk(self):
        yield self
        for child in self.children:
            yield from child.walk()

    def type_name(self):
        """The simple name of the first type written after `:` in its head; None without."""
        typed = re.search(r":(?![:>])\s*~?((?:(?:\w+|'[^']*')::)*(\w+|'[^']*'))", self.head)
        return typed[2] if typed else None

    def type_written(self):
        typed = re.search(r":(?![:>])\s*~?((?:(?:\w+|'[^']*')::)*(?:\w+|'[^']*'))", self.head)
        return typed[1] if typed else None


def parse_model(key: str, source: str) -> Element:
    """The elements of one model file as a tree under an element of kind `file`."""
    code = structure_code(source)
    root = Element(key, "file", None, 0, len(code), -1, None, "")
    found = [root]

    def walk(parent: Element, start: int, end: int):
        position = start
        while begin := NONSPACE.search(code, position, end):
            begin = begin.start()
            stop = statement_end(code, begin, end)
            opening = code.find("{", begin, stop)
            head = code[begin:opening if opening >= 0 else stop]
            kind_match = KIND.match(head)
            kind = re.sub(r"\s+", " ", kind_match[1]) if kind_match else head.split()[0] if head.split() else ""
            name = NAME.match(head, kind_match.end()) if kind_match else None
            element = Element(key, kind, name[1] if name else None, begin, stop, opening, parent, head)
            element.line = source.count("\n", 0, begin) + 1
            parent.children.append(element)
            found.append(element)
            if opening >= 0 and code[stop - 1:stop] == "}":
                walk(element, opening + 1, stop - 1)
            position = stop

    walk(root, 0, len(code))
    text = blanked(source)
    for match in re.finditer(r"\b(doc|comment)\b", text):
        opening = source.find("/*", match.end())
        if opening < 0 or re.search(r"[;{}]", text[match.end():opening]):
            continue
        closing = source.find("*/", opening)
        owner = root
        for element in found[1:]:
            if element.opening >= 0 and element.opening < match.start() < element.stop and \
                    (owner is root or element.opening > owner.opening):
                owner = element
        owner.docs.append((match.start(), source[opening + 2:closing if closing >= 0 else len(source)], match[1]))
    return root


class Model:
    """The model files below a folder, read once: sources, codes, packages and trees."""

    def __init__(self, directory: Path):
        self.directory = directory
        self.files = model_files(directory) if directory.is_dir() else {}
        self.sources = {key: path.read_text(encoding="utf-8") for key, path in self.files.items()}
        self.codes = {key: structure_code(source) for key, source in self.sources.items()}
        self.packages = {key: file_package(blanked(source)) for key, source in self.sources.items()}
        self.trees = {key: parse_model(key, source) for key, source in self.sources.items()}
        self.package_files = {}
        for key, code in self.codes.items():
            for package in top_packages(code):
                self.package_files.setdefault(package, key)

    def elements(self, key=None):
        for name in ([key] if key else self.trees):
            yield from list(self.trees[name].walk())[1:]

    def definition(self, key: str, name: str, kinds=None):
        """The first definition of simple `name` in the file `key`."""
        for element in self.elements(key):
            if element.name == name and element.kind.endswith("def") and (kinds is None or element.kind in kinds):
                return element
        return None

    def find_definition(self, key: str, written: str, kinds=None):
        """The definition `written` (simple or qualified) names, seen from the file `key`: in
        the package a qualified name or an import names, in the file itself, or the one
        definition of that name in the model."""
        segments = [segment for segment in written.split("::") if segment]
        name = segments[-1]
        if len(segments) > 1 and (target := self.package_files.get(segments[-2] if len(segments) == 2 else segments[0])):
            return self.definition(target, name, kinds)
        if found := self.definition(key, name, kinds):
            return found
        for match in re.finditer(r"\bimport\s+(\w+)::(?:\*|" + re.escape(name) + r")\s*;", self.codes.get(key, "")):
            if (target := self.package_files.get(match[1])) and (found := self.definition(target, name, kinds)):
                return found
        candidates = [element for element in self.elements() if element.name == name and element.kind.endswith("def")
                      and (kinds is None or element.kind in kinds)]
        return candidates[0] if len(candidates) == 1 else None


def fault_lines(faults) -> list[str]:
    """The fault lines, sorted by rule, file or deployment path, and line, each once; a fault of
    the deployment has no line."""
    ordered = sorted(set(faults), key=lambda fault: (fault[0], fault[1], fault[2] if fault[2] is not None else -1, fault[3]))
    return [f"{what}: {key}" + (f":{line}" if line is not None else "") for rule, key, line, what in ordered]


def tree_faults(directory: Path, model: Model) -> list[tuple]:
    """TR-03: the model files are exactly those of M2.1; beside them only `data/`."""
    expected, faults = tree_files(), []
    for key in model.files:
        if key not in expected:
            faults.append(("TR-03", key, 1, "model file outside the tree"))
    for key in expected:
        if key not in model.files:
            faults.append(("TR-03", key, 0, "model file of the tree missing"))
    for path in sorted(directory.rglob("*")):
        relative = path.relative_to(directory).as_posix()
        if path.is_file() and not relative.endswith(".sysml") and not relative.startswith(DATA_FOLDER):
            faults.append(("TR-03", relative, 0, "file outside the model files and data/"))
    return faults


def control_packages(model: Model) -> set[str]:
    """M3.4: the packages that `WstxStationLink::WireNames` names, the control interfaces."""
    tree = model.trees.get(STATION_LINK)
    if tree is None:
        return set()
    names = next((element for element in tree.walk() if element.name == "WireNames"), None)
    return set(re.findall(r"\bWstx\w+", " ".join(text for _offset, text, _kind in names.docs))) if names else set()


def named_packages(code: str) -> list[tuple[int, str]]:
    """The packages a file names in code: by `import` or as the first segment of a
    qualified name; quoted names left out."""
    unquoted = re.sub(r"'[^'\r\n]*'", lambda match: " " * len(match[0]), code)
    named = {match.start(1): match[1] for match in re.finditer(r"\bimport\s+(?:all\s+)?(\w+)", unquoted)}
    named.update((match.start(), match[0].split("::", 1)[0]) for match in QNAME.finditer(unquoted))
    return sorted(named.items())


def layer_faults(model: Model) -> list[tuple]:
    """TR-04: M3.1 to M3.4 on every model file."""
    controls, faults = control_packages(model), []
    for key, code in model.codes.items():
        own = model.packages.get(key)
        for offset, package in named_packages(code):
            target = model.package_files.get(package)
            if target is None or target == key:
                continue
            line = code.count("\n", 0, offset) + 1
            what = None
            mine, theirs = layer(key), layer(target)
            if package == CONTEXT_PACKAGE and key not in (CONTEXT_FILE, USE_CASES_FILE):
                what = "names the context package " + package
            elif key == REQUIREMENTS_FILE:
                if not target.startswith("shared/"):
                    what = "Requirements names " + package
            elif target == REQUIREMENTS_FILE or mine is None or theirs is None or theirs < mine:
                what = None
            elif theirs > mine:
                what = f"names {package} of a later layer"
            elif mine == 1:
                if own in controls and package in TRANSPORT_PACKAGES:
                    what = f"control interface names {package}"
                elif key.startswith("interfaces/external/") and package in controls:
                    what = f"external interface names the control interface {package}"
            elif mine == 2 and part_folder(key) != part_folder(target):
                what = f"part names {package} of another part"
            elif mine > 2:
                what = "names " + package
            if what:
                faults.append(("TR-04", key, line, what))
    return faults


SATISFY_FR = re.compile(r"satisfy\s+(?:requirement\s+)?(?:(?:\w+|'[^'\r\n]*')::)*'(FR-\d{3})'\s+by\s+([\w.]+)")
SHACK_KINDS = {"package", "import", "part def", "part", "interface", "connection", "connect", "bind", "binding", "satisfy"}
USE_CASE_KINDS = {"package", "import", "use case def", "use case", "subject", "actor", "objective", "action", "succession",
                  "include", "perform", "requirement", "first", "then"}


def identity_of(element: Element):
    """The identity a requirement or verification declares; None for any other element."""
    if element.kind in ("requirement", "verification") and element.name and re.fullmatch(r"'" + IDENTITY + r"'", element.name):
        return element.name.strip("'")
    return None


def content_faults(model: Model) -> list[tuple]:
    """TR-05: what Requirements, Shack, UseCases and Context hold (M4.1 to M4.3, M4.9); an FR
    only in Requirements, a satisfy only in Shack."""
    faults = []
    for key, tree in model.trees.items():
        for element in list(tree.walk())[1:]:
            identity = identity_of(element)
            if identity and identity.startswith("FR-") and key != REQUIREMENTS_FILE:
                faults.append(("TR-05", key, element.line, f"{identity} outside Requirements.sysml"))
            if element.kind == "satisfy" and key != SHACK_FILE:
                faults.append(("TR-05", key, element.line, "satisfy outside Shack.sysml"))
    if tree := model.trees.get(REQUIREMENTS_FILE):
        for element in list(tree.walk())[1:]:
            identity = identity_of(element)
            parent = element.parent
            if parent.kind == "package" and parent.parent is tree:
                if element.kind == "import" or element.kind == "attribute def" and element.name == "BehaviorBaseline" \
                        or element.kind == "requirement" and identity and identity.startswith("FR-"):
                    continue
                faults.append(("TR-05", REQUIREMENTS_FILE, element.line, f"Requirements holds {element.kind} {element.name or ''}".rstrip()))
            elif identity_of(parent) and identity_of(parent).startswith("FR-"):
                faults.append(("TR-05", REQUIREMENTS_FILE, element.line, f"{identity_of(parent)} holds {element.kind} {element.name or ''}".rstrip()))
        for element in tree.walk():
            if (identity := identity_of(element)) and identity.startswith("FR-") and re.search(r"#\d+", element.doc):
                faults.append(("TR-05", REQUIREMENTS_FILE, element.line, f"{identity} names an issue"))
    if tree := model.trees.get(SHACK_FILE):
        for element in list(tree.walk())[1:]:
            if element.kind not in SHACK_KINDS:
                faults.append(("TR-05", SHACK_FILE, element.line, f"Shack holds {element.kind} {element.name or ''}".rstrip()))
            elif element.kind == "satisfy" and not SATISFY_FR.match(element.head):
                faults.append(("TR-05", SHACK_FILE, element.line, "satisfy of no FR"))
    if tree := model.trees.get(USE_CASES_FILE):
        for element in list(tree.walk())[1:]:
            if element.kind not in USE_CASE_KINDS or element.kind == "requirement" and element.name:
                faults.append(("TR-05", USE_CASES_FILE, element.line, f"UseCases holds {element.kind} {element.name or ''}".rstrip()))
            if re.search(r"=", element.head) and element.kind != "requirement":
                faults.append(("TR-05", USE_CASES_FILE, element.line, "UseCases holds a value"))
            for _offset, text, _kind in element.docs:
                if re.search(r"\b(?:CL|FR|TC)-\d", text):
                    faults.append(("TR-05", USE_CASES_FILE, element.line, "a step names a clause in its text"))
    if tree := model.trees.get(CONTEXT_FILE):
        for element in tree.walk():
            if identity_of(element):
                faults.append(("TR-05", CONTEXT_FILE, element.line, f"Context declares {identity_of(element)}"))
    return faults


def subject_of(element: Element):
    return next((child for child in element.children if child.kind == "subject"), None)


def part_definitions(model: Model) -> dict[str, Element]:
    """The part definition of each part, by its folder: the first `part def` of its own file."""
    found = {}
    for key, package in tree_files().items():
        if package.endswith("Part") and key in model.trees and (folder := part_folder(key)):
            if definition := next((element for element in model.elements(key) if element.kind == "part def"), None):
                found[folder] = definition
    return found


def carried_clauses(model: Model) -> set[str]:
    """The clauses a use-case step subsets (`requirement :> <Package>::'<CL>'`)."""
    return set(re.findall(r"\brequirement\s*:>\s*(?:\w+::)*'(CL-\d{3}-\d{2})'", model.codes.get(USE_CASES_FILE, "")))


def has_annotation(element: Element, name: str) -> bool:
    return any(child.kind == "@" and child.name == name for child in element.children)


def clause_faults(model: Model, entries: dict, served=None, ends=None) -> list[tuple]:
    """TR-11: subjects (M6.9), the place and the FR of a clause (M6.2, M6.3), the form of a
    case (M6.5), the use-case steps (M6.11) and no dependency (M7.1). `served` maps a
    definition's simple name to the FRs Shack gives it, `ends` an interface's simple name to
    the definitions at its ends; without them the FR check is left out."""
    faults, carried, parts = [], carried_clauses(model), part_definitions(model)
    for key, tree in model.trees.items():
        folder = part_folder(key)
        own = folder and tree_files().get(key, "").endswith("Part")
        for element in list(tree.walk())[1:]:
            if element.kind == "dependency":
                faults.append(("TR-11", key, element.line, "dependency declared"))
            identity = identity_of(element)
            if not identity or identity.startswith("FR-"):
                continue
            subject = subject_of(element)
            if subject is None:
                faults.append(("TR-11", key, element.line, f"{identity} names no subject"))
            if identity.startswith("TC-"):
                case_form(key, element, identity, faults)
                continue
            if not (folder and not own or key.startswith("interfaces/")):
                faults.append(("TR-11", key, element.line, f"{identity} outside a function or interface file"))
                continue
            entry = entries.get(identity, {})
            if subject is not None:
                written = subject.type_name()
                if folder and (parts.get(folder) is None or written != parts[folder].name):
                    faults.append(("TR-11", key, element.line, f"{identity} names a subject other than its part"))
                elif key.startswith("interfaces/") and model.definition(key, written or "") is None:
                    faults.append(("TR-11", key, element.line, f"{identity} names a subject outside its interface file"))
            frs = entry.get("frs", [])
            if len(frs) != 1:
                faults.append(("TR-11", key, element.line, f"{identity} derives from {len(frs)} FRs"))
            elif served is not None and subject is not None:
                written = subject.type_name()
                if folder:
                    part = parts.get(folder)
                    if frs[0] not in served.get(part.name if part else written, set()):
                        faults.append(("TR-11", key, element.line, f"{identity} derives from {frs[0]}, which its part does not serve"))
                elif not any(frs[0] in served.get(end, set()) for end in ends.get(written, ())):
                    faults.append(("TR-11", key, element.line, f"{identity} derives from {frs[0]}, which no part at its ends serves"))
            if identity not in carried and not has_annotation(element, "Debugging"):
                faults.append(("TR-11", key, element.line, f"{identity} is carried by no use-case step"))
    for identity, entry in entries.items():
        if identity.startswith("CL-") and entry["state"] == "implemented" and not entry["cases"]:
            faults.append(("TR-11", entry["file"], entry["line"], f"{identity} is implemented and has no case"))
    return faults


CASE_ANNOTATIONS = {"TestLevel", "Automation", "TestedBy"}


def case_form(key: str, element: Element, identity: str, faults: list):
    """M6.5: a case is its identity, a one-line title, `subject`, `verify` in its objective,
    `@TestLevel`, `@Automation` and `@TestedBy`."""
    for child in element.children:
        if child.kind == "subject" or child.kind == "@" and child.name in CASE_ANNOTATIONS:
            continue
        if child.kind == "objective" and all(grand.kind == "verify" for grand in child.children) and not child.docs:
            continue
        faults.append(("TR-11", key, child.line, f"{identity} holds {child.kind} {child.name or ''}".rstrip()))
    for name in sorted(CASE_ANNOTATIONS):
        if not has_annotation(element, name):
            faults.append(("TR-11", key, element.line, f"{identity} has no @{name}"))
    docs = [text for _offset, text, kind in element.docs if kind == "doc"]
    if len(docs) != 1 or len(element.docs) != 1:
        faults.append(("TR-11", key, element.line, f"{identity} has {len(element.docs)} titles"))
    elif len(docs[0].strip().splitlines()) != 1:
        faults.append(("TR-11", key, element.line, f"{identity} has a title of {len(docs[0].strip().splitlines())} lines"))


def code_links(model: Model, entries: dict, origins: dict | None = None) -> tuple[dict, list[tuple]]:
    """TR-13 (M6.6): `@ImplementedIn` stands on a part definition or a clause; a clause's code
    link is its own, else its subject's part definition's. Returns (the modules of each
    clause, the faults); `origins` receives the name of the part definition of each link taken
    from one."""
    faults, links = [], {}
    for key in model.trees:
        for element in model.elements(key):
            if element.kind == "@" and element.name == "ImplementedIn":
                owner = element.parent
                identity = identity_of(owner)
                if not (owner.kind == "part def" or owner.kind == "requirement" and identity and identity.startswith("CL-")):
                    faults.append(("TR-13", key, element.line, f"code link on {owner.kind} {owner.name or ''}".rstrip()))
    for identity, entry in entries.items():
        if not identity.startswith("CL-"):
            continue
        if entry["own"]:
            links[identity] = list(entry["own"])
            continue
        element = next((element for element in model.elements(entry["file"]) if identity_of(element) == identity), None)
        subject = subject_of(element) if element else None
        definition = model.find_definition(entry["file"], subject.type_written(), {"part def"}) if subject and subject.type_written() else None
        candidates = []
        while definition is not None and definition not in [found for found, _modules in candidates]:
            if modules := part_link(model, definition):
                candidates.append((definition, modules))
            supertype = re.search(r"(?::>|\bspecializes\b)\s*((?:\w+::)*\w+)", definition.head)
            definition = model.find_definition(definition.key, supertype[1], {"part def"}) if supertype else None
        if len(candidates) > 1:
            faults.append(("TR-13", entry["file"], entry["line"], f"{identity} inherits two code links: "
                           + ", ".join(found.name for found, _modules in candidates)))
        elif candidates:
            links[identity] = candidates[0][1]
            if origins is not None:
                origins[identity] = candidates[0][0].name
        elif entry["state"] in ("partial", "implemented"):
            faults.append(("TR-13", entry["file"], entry["line"], f"{identity} is delivered and has no code link"))
    return links, faults


def part_link(model: Model, definition: Element) -> list[str]:
    """The modules a part definition's own `@ImplementedIn` names."""
    source = model.sources[definition.key]
    for child in definition.children:
        if child.kind == "@" and child.name == "ImplementedIn":
            body = source[child.opening + 1:child.stop - 1] if child.opening >= 0 else ""
            for feature, value in assignments(body, blanked(body)):
                if feature == "module" and (text := string_literal(value)) is not None:
                    return [path.strip() for path in text.split(";") if path.strip()]
    return []


HISTORY = re.compile(r"20\d\d-\d\d-\d\d|(?<![A-Za-z0-9])#\d+\b|\bformerly\b|\breplaces\b|\bno longer\b"
                     r"|\bremains\b|\bNot delivered yet\b|\bNot automated yet\b|\boperator decision\b", re.I)
DEFINED_NAME = re.compile(r"^\s*(?:abstract\s+)?(?:part|attribute|item|action|state|enum|port|interface|calc|constraint|"
                          r"metadata|occurrence)\s+(?:def\s+)?([A-Za-z_][A-Za-z0-9_]*)", re.M)


def sentences(text: str) -> list[str]:
    return [part for part in re.split(r"(?<=[.!?])\s+(?=[A-Z(\"'])", text) if part.strip()]


def writing_faults(model: Model) -> list[tuple]:
    """TR-18: the writing rules M5.10 (no "user"), M6.4, M6.10, M7.3 to M7.6 and the package
    names of M7.5."""
    faults, expected = [], tree_files()
    for key, source in model.sources.items():
        package = model.packages.get(key)
        wanted = expected.get(key, "Wstx" + Path(key).stem)
        if package != wanted:
            declared = re.search(r"\bpackage\s+\w+\s*\{", blanked(source))
            at = source.count("\n", 0, declared.start()) + 1 if declared else 1
            faults.append(("TR-18", key, at, f"package {package} is not {wanted}"))
        for number, line in enumerate(source.split("\n"), 1):
            line = line.rstrip("\r")
            if len(line) > LINE_LIMIT:
                faults.append(("TR-18", key, number, f"line of {len(line)} characters"))
            if re.search(r"\busers?\b", line, re.I):
                faults.append(("TR-18", key, number, "the word user"))
            scan = re.sub(r'"[^"]*"', '""', line) if re.search(r"\battribute\b[^=]*=|\breference\s*=", line) else line
            if history := HISTORY.search(scan):
                faults.append(("TR-18", key, number, "history in a text: " + history[0]))
        for token in re.finditer(r'/\*[\s\S]*?\*/|//[^\r\n]*|' + STRING + r"|'(?:\\.|[^'\\])*'|[^/\"']+|.", source):
            text, offset = token.group(), token.start()
            line = source.count("\n", 0, offset) + 1
            if text.startswith("//") and not (key == REQUIREMENTS_FILE and offset == 0 and text == CANONICAL_MARKER):
                faults.append(("TR-18", key, line, "comment //"))
            elif text.startswith("/*") and not re.search(r"\b(?:doc)\s*$", source[max(0, offset - 40):offset]):
                faults.append(("TR-18", key, line, "comment /* */ outside a doc"))
        for match in re.finditer(r'(' + STRING + r')\s*\+\s*(?=(' + STRING + r'))', source):
            left, right = match[1][1:-1], match[2][1:-1]
            # A binding `<path>::<test name>` may join right after `::`: neither is split.
            if not (left.endswith((" ", ";", "::")) or right.startswith((" ", ";"))):
                faults.append(("TR-18", key, source.count("\n", 0, match.start()) + 1, "joined value split inside a word"))
        names = set(DEFINED_NAME.findall(model.codes[key]))
        for element in model.elements(key):
            if element.name and not element.name.startswith("'"):
                if "_" in element.name:
                    faults.append(("TR-18", key, element.line, f"name with an underscore: {element.name}"))
                if element.kind.endswith("def") and not element.name[0].isupper():
                    faults.append(("TR-18", key, element.line, f"definition not in UpperCamelCase: {element.name}"))
            identity = identity_of(element)
            if identity and not identity.startswith("FR-") and identity in element.doc:
                faults.append(("TR-18", key, element.line, f"{identity} names itself"))
            if identity and identity.startswith("CL-"):
                doc = element.doc
                if len(sentences(doc)) != 1:
                    faults.append(("TR-18", key, element.line, f"{identity} is {len(sentences(doc))} sentences"))
                if not re.search(r"\b(?:MUST|SHOULD|MAY)\b", doc):
                    faults.append(("TR-18", key, element.line, f"{identity} has no MUST, SHOULD or MAY"))
                if not any(re.search(r"\b" + re.escape(name) + r"\b", doc) for name in names):
                    faults.append(("TR-18", key, element.line, f"{identity} names no element of its file"))
    return faults


# ---- The deployment (TR-06, TR-07, TR-08), read from the Pilot inventory ----

# M2.2, M5.5 with Context.sysml and Shack.sysml: each role by its path below the deployment,
# the simple name of its type where the rule fixes it, and its multiplicity.
DEPLOYMENT = ("context", "ShackContext")
ROLES = (("shack", "Shack", "1:1"), ("shack.stations", "Station", "0:-1"), ("shack.stations.frontend", None, "1:1"),
         ("shack.stations.frontend.browsers", "BrowserClient", "0:-1"), ("shack.stations.backend", None, "1:1"),
         *(("shack.stations.backend." + name, None, "1:1") for name in (
             "supervisor", "web", "mcp", "profile", "receive", "modes", "clock", "transmit", "operating",
             "operating.ranking", "operating.auto", "operating.qso", "log", "spots", "udp", "audio", "radioControl")),
         ("shack.stations.backend.flexAdapter", None, "0:1"),
         ("shack.stations.backend.audioAdapter", "AudioDeviceAdapter", "1:1"),
         ("shack.stations.backend.catAdapter", "CatAdapter", "1:1"))
EXCLUSIVE_TYPES = ("AudioDeviceAdapter", "CatAdapter")
OPERATOR_INTERACTION = "interfaces/external/OperatorInteraction.sysml"
OUTSIDE_MEMBERS = {"port", "attribute", "metadata"}


def of_type(values: list, type_name: str) -> bool:
    """A PART row's definition, or a definition it specializes, has the simple name
    `type_name`, in any package."""
    return len(values) > 4 and any(kind.rsplit("::", 1)[-1] == type_name for kind in values[4].split(",") if kind)


def fixed_rules(records: dict, root=None) -> None:
    """TR-09's fixed rules, whatever the oracle file lists: one package-level part usage (and,
    given `root`, the oracle's) and no view that adds a part or a connection."""
    roots = records.get("ROOTPART", [])
    if len(roots) != 1 or root is not None and roots != [[root]]:
        raise ValueError("Architecture integrity: expected one physical deployment")
    if records.get("VIEWSEMANTIC"):
        raise ValueError("Architecture integrity: views may expose, not create runtime parts/connections")


class Deployment:
    """The resolved deployment of an inventory: parts, ports, connections and element files."""

    def __init__(self, records: dict, keys: list[str]):
        self.records = records
        roots = records.get("ROOTPART", [])
        self.root = roots[0][0].rsplit("::", 1)[-1] if len(roots) == 1 else None
        self.parts = {row[0]: row[1:] for row in records.get("PART", [])}
        self.ports = {row[0]: row[1] for row in records.get("PORT", [])}
        refs = {row[0]: row[1:] for row in records.get("REF", [])}
        self.files = {}
        for name, _kind, index, *_rest in records.get("ELEM", []):
            position = int(index)
            self.files.setdefault(name, keys[position] if 0 <= position < len(keys) else "")
        self.kinds = {row[0]: row[1] for row in records.get("ELEM", [])}
        resolved = end_resolver(self.root or "", refs)
        self.connections = []
        for owner, name, ends, types, _index, anchor in records.get("CONN", []):
            written = ends.split("|")
            if len(written) == 2:
                self.connections.append({"label": f"{owner}.{name}" if name else owner, "ends": [resolved(owner, end) for end in written],
                                         "types": [typed for typed in types.split(",") if typed], "anchor": anchor})

    def joined(self, port: str) -> list[dict]:
        return [connection for connection in self.connections if port in connection["ends"]]


def within(path: str, base: str) -> bool:
    return path == base or path.startswith(base + ".")


def role_faults(deployment: Deployment) -> list[tuple]:
    """TR-06: the one deployment, the fixed roles (M2.2, M5.5) and the browser client's two
    ports, each joined as M5.5 says."""
    faults = []
    root = deployment.root
    if root != DEPLOYMENT[0] or not of_type(deployment.parts.get(root, []), DEPLOYMENT[1]):
        faults.append(("TR-06", "docs/sysml", None, "expected one deployment context : ShackContext"))
        return faults
    for view in deployment.records.get("VIEWSEMANTIC", []):
        faults.append(("TR-06", view[0], None, "view adds a part or a connection"))
    for relative, type_name, bounds in ROLES:
        path = root + "." + relative
        values = deployment.parts.get(path)
        if values is None:
            faults.append(("TR-06", path, None, "role missing"))
        elif type_name and not of_type(values, type_name):
            faults.append(("TR-06", path, None, "role not typed " + type_name))
        elif values[1] != bounds:
            faults.append(("TR-06", path, None, "role with multiplicity " + population(values[1])))
    for type_name in EXCLUSIVE_TYPES:
        role = next(root + "." + relative for relative, typed, _bounds in ROLES if typed == type_name)
        for path, values in deployment.parts.items():
            if path != role and of_type(values, type_name):
                faults.append(("TR-06", path, None, "second part of type " + type_name))
    frontend = root + ".shack.stations.frontend"
    browsers = frontend + ".browsers"
    web = root + ".shack.stations.backend.web"
    operator = root + ".operator"
    own = sorted(port for port in deployment.ports if port.startswith(browsers + ".") and "." not in port[len(browsers) + 1:])

    def file_of(port: str) -> str:
        return deployment.files.get(deployment.ports[port].removeprefix("~"), "")

    toward_station = [port for port in own if file_of(port).startswith("interfaces/internal/")]
    allowed = {}
    if len(toward_station) != 1:
        faults.append(("TR-06", browsers, None, f"browser client with {len(toward_station)} ports toward the station"))
    for port in toward_station:
        if file_of(port) != STATION_LINK:
            faults.append(("TR-06", port, None, "port toward the station not typed by StationLink"))
        elif not any(any(within(end, web) for end in connection["ends"] if end != port) for connection in deployment.joined(port)):
            faults.append(("TR-06", port, None, "StationLink port not joined to web"))
        allowed[port] = web
    for port in own:
        if port in toward_station:
            continue
        if file_of(port) != OPERATOR_INTERACTION:
            faults.append(("TR-06", port, None, "browser port that is neither toward the station nor the operator's"))
            continue
        if not any(any(within(end, operator) for end in connection["ends"] if end != port) for connection in deployment.joined(port)):
            faults.append(("TR-06", port, None, "operator port not joined to the operator"))
        allowed[port] = operator
    for connection in deployment.connections:
        first, second = connection["ends"]
        for inside, other in ((first, second), (second, first)):
            if within(inside, frontend) and not within(other, frontend) and \
                    not any(within(inside, port) and within(other, peer) for port, peer in allowed.items()):
                faults.append(("TR-06", connection["label"], None, "frontend connection ends at " + other))
    return faults


def context_faults(deployment: Deployment) -> list[tuple]:
    """TR-07 (M4.1): each outside thing of the deployment is a black box of ports, each port
    joined once, through an interface of `interfaces/external`, to a station function, and
    no requirement names it as its subject."""
    faults, root = [], deployment.root
    if root is None:
        return faults
    shack = root + ".shack"
    outside = sorted(path for path in deployment.parts if path.count(".") == 1 and path.startswith(root + ".") and path != shack)
    members = {}
    for path, side, category, name in deployment.records.get("MEMBER", []):
        members.setdefault(path, []).append((side, category, name))
    for path in outside:
        for side, category, name in members.get(path, []):
            if category not in OUTSIDE_MEMBERS:
                faults.append(("TR-07", path, None, f"outside thing with {category} {name}" + (" in its type" if side == "type" else "")))
        ports = sorted(port for port in deployment.ports if port.startswith(path + ".") and "." not in port[len(path) + 1:])
        if not ports:
            faults.append(("TR-07", path, None, "outside thing without a port"))
        for port in ports:
            joined = deployment.joined(port)
            if not joined:
                faults.append(("TR-07", port, None, "port joined to nothing"))
                continue
            if len(joined) > 1:
                faults.append(("TR-07", port, None, f"port joined {len(joined)} times"))
            for connection in joined:
                if not any(deployment.files.get(typed, "").startswith("interfaces/external/") for typed in connection["types"]):
                    faults.append(("TR-07", port, None, "port joined by no interface of interfaces/external"))
                if not all(within(end, shack) for end in connection["ends"] if end != port):
                    faults.append(("TR-07", port, None, "port joined to no station function"))
        types = [typed for typed in deployment.parts[path][0].split(",") if typed and deployment.files.get(typed)]
        usage = deployment.parts[root][0].split(",")[0] + "::" + path.split(".", 1)[1]
        for anchor, _index, subject_types, subsetted in deployment.records.get("SUBJECT", []):
            if set(subject_types.split(",")) & set(types) or usage in subsetted.split(","):
                faults.append(("TR-07", path, None, "outside thing is the subject of " + anchor))
    return faults


def connection_faults(deployment: Deployment) -> list[tuple]:
    """TR-08 (M5.8): every connection typed by an interface of `interfaces/`; no empty item in
    a port definition: none untyped (an abstract one stands when a typed item subsets it),
    none typed by a definition with neither doc nor feature."""
    faults = []
    for connection in deployment.connections:
        interfaces = [typed for typed in connection["types"] if deployment.kinds.get(typed) == "InterfaceDefinition"]
        if not connection["types"]:
            faults.append(("TR-08", connection["label"], None, "untyped connection"))
        elif not interfaces:
            faults.append(("TR-08", connection["label"], None, "connection typed by no interface"))
        elif not any(deployment.files.get(typed, "").startswith("interfaces/") for typed in interfaces):
            faults.append(("TR-08", connection["label"], None, "connection typed by an interface outside interfaces/"))
    empty = {row[0] for row in deployment.records.get("ELEM", []) if len(row) > 6 and row[1].endswith("Definition")
             and row[5] == "0" and row[6] == "0"}
    items = deployment.records.get("PITEM", [])
    subsetted = {name for row in items if row[2] for name in row[3].split(",") if name}
    for name, abstract, typing, _subsets, redefines, index, line in items:
        if redefines == "true":
            continue
        if not typing:
            if abstract == "true" and name in subsetted:
                continue
            faults.append(("TR-08", name, None, "abstract item no typed item subsets" if abstract == "true" else "untyped item"))
        for typed in typing.split(","):
            if typed in empty:
                faults.append(("TR-08", name, None, f"item typed by {typed}, which has neither doc nor feature"))
    return faults


def served_and_ends(deployment: Deployment, model: Model) -> tuple[dict, dict]:
    """The FRs Shack gives each part definition (by simple name), and the part definitions at
    the ends of each interface and port definition (by simple name)."""
    served, ends = {}, {}
    tree = model.trees.get(SHACK_FILE)
    satisfied = []
    if tree is not None:
        for element in tree.walk():
            if element.kind == "part def":
                for child in element.children:
                    if child.kind == "satisfy" and (found := SATISFY_FR.match(child.head)):
                        satisfied.append((element.name, found[1], found[2]))

    def simple(values) -> str:
        return values[0].split(",")[0].rsplit("::", 1)[-1] if values and values[0] else ""

    for path, values in deployment.parts.items():
        for owner, fr, by in satisfied:
            if simple(values) == owner and (target := deployment.parts.get(path + "." + by)):
                served.setdefault(simple(target), set()).add(fr)
    for connection in deployment.connections:
        owners = [simple(deployment.parts.get(end.rsplit(".", 1)[0], [])) for end in connection["ends"]]
        names = {typed.rsplit("::", 1)[-1] for typed in connection["types"]}
        names.update(deployment.ports[end].removeprefix("~").rsplit("::", 1)[-1] for end in connection["ends"] if end in deployment.ports)
        for name in names:
            ends.setdefault(name, set()).update(owner for owner in owners if owner)
    return served, ends


ENTRY_COMMANDS = ("createEntry", "updateEntry", "deleteEntry")


def agent_faults(model: Model) -> list[tuple]:
    """TR-06 for M5.10: `WstxStationCommands::AgentRefusal` names commands of
    StationOperations and collections of `SettingsCollection`; mcp's port toward the
    supervisor is typed by AgentOperations: StationOperations with exactly the refused
    commands redefined to `[0]` and its entry commands' `collection` typed by
    AgentCollection, which admits exactly the collections AgentRefusal does not name."""
    faults = []
    operations = model.definition(STATION_COMMANDS, "StationOperations", {"port def"}) if STATION_COMMANDS in model.trees else None
    if operations is None:
        return [("TR-06", STATION_COMMANDS, 0, "no port def StationOperations")]
    commands = {child.name for child in operations.children if child.kind == "item" and re.search(r":>\s*commands\b", child.head)}
    collection_def = next((element for key in model.trees for element in model.elements(key)
                           if element.kind == "enum def" and element.name == "SettingsCollection"), None)
    collections = {child.name for child in collection_def.children if child.kind == "enum" and child.name} if collection_def else set()
    refusal = next((element for key in model.trees for element in model.elements(key)
                    if element.kind == "enum def" and element.name == "AgentRefusal"), None)
    if refusal is None:
        return [("TR-06", STATION_COMMANDS, 0, "no enum def AgentRefusal")]
    refused = {child.name: child for child in refusal.children if child.kind == "enum" and child.name}
    for name, literal in refused.items():
        if name not in commands and name not in collections:
            faults.append(("TR-06", literal.key, literal.line, f"AgentRefusal literal {name} names no command or collection"))
    agent = next((element for key in model.trees for element in model.elements(key)
                  if element.kind == "port def" and element.name == "AgentOperations"), None)
    if agent is None or not re.search(r"(?::>|\bspecializes\b)\s*(?:\w+::)*StationOperations\b", agent.head):
        return faults + [("TR-06", STATION_COMMANDS, 0, "no port def AgentOperations :> StationOperations")]
    removed, entries = {}, {}
    for child in agent.children:
        if child.kind == "item" and (found := re.search(r"(?::>>|\bredefines\b)\s*(\w+)\s*\[\s*0\s*\]", child.head)):
            removed[found[1]] = child
        elif child.kind == "item" and (found := re.search(r"(?::>>|\bredefines\b)\s*(\w+)\s*$", child.head.strip())):
            entries[found[1]] = child
    for name in sorted((set(refused) & commands) - set(removed)):
        faults.append(("TR-06", agent.key, agent.line, f"mcp offers the refused command {name}"))
    for name in sorted(set(removed) - set(refused)):
        faults.append(("TR-06", agent.key, removed[name].line, f"mcp lacks the command {name}"))
    for name in ENTRY_COMMANDS:
        if name not in commands:
            continue
        child = entries.get(name)
        if child is None or not any(grand.kind == "attribute" and re.search(r":>>\s*collection\s*:\s*(?:\w+::)*AgentCollection\b", grand.head)
                                    for grand in child.children):
            faults.append(("TR-06", agent.key, (child or agent).line, f"an agent's {name} takes every collection"))
    admitted = next((element for key in model.trees for element in model.elements(key)
                     if element.kind == "attribute def" and element.name == "AgentCollection"), None)
    refused_collections = set(refused) & collections
    if admitted is None or not re.search(r"(?::>|\bspecializes\b)\s*(?:\w+::)*SettingsCollection\b", admitted.head):
        faults.append(("TR-06", STATION_COMMANDS, 0, "no attribute def AgentCollection :> SettingsCollection"))
    else:
        text = model.codes[admitted.key][admitted.begin:admitted.stop]
        named = set(re.findall(r"\bSettingsCollection::(\w+)", text))
        for name in sorted(named & refused_collections):
            faults.append(("TR-06", admitted.key, admitted.line, f"an agent's entry command on {name}"))
        for name in sorted(collections - refused_collections - named):
            faults.append(("TR-06", admitted.key, admitted.line, f"AgentCollection lacks the collection {name}"))
    mcp = model.definition("backend/mcp/Mcp.sysml", "McpAdapter", {"part def"}) if "backend/mcp/Mcp.sysml" in model.trees else None
    if mcp is not None:
        typed = [child.type_name() for child in mcp.children if child.kind == "port"]
        if "AgentOperations" not in typed:
            faults.append(("TR-06", mcp.key, mcp.line, "mcp has no port typed AgentOperations"))
        if "StationOperations" in typed:
            faults.append(("TR-06", mcp.key, mcp.line, "mcp offers every command of StationOperations"))
    return faults


# ---- The identity history (TR-15, M6.12) ----

MAIN_BRANCH = "master"


def repository_git(root: Path, *args: str) -> str:
    """git in the repository at `root`; Unreadable when it fails."""
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    try:
        result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, encoding="utf-8",
                                errors="replace", env=env)
    except OSError as error:
        raise Unreadable(f"git {' '.join(args)}: {error}") from None
    if result.returncode:
        raise Unreadable(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


def identity_history(root: Path, head: str = "HEAD") -> tuple[set[str], set[str]]:
    """(used, present): the identities whose declarations were added to model files in the
    history of `git merge-base <head> master`, and those declared in that commit's model.
    Refused as `Identity history unavailable: <reason>` without a repository, a `master` or
    a working git."""
    try:
        base = repository_git(root, "merge-base", head, MAIN_BRANCH).strip()
        log = repository_git(root, "log", "-p", "--format=", "-U0", base, "--", "docs/sysml")
        listing = repository_git(root, "ls-tree", "-r", "--name-only", base, "--", "docs/sysml")
        declared = []
        for path in (line for line in listing.splitlines() if line.endswith(".sysml")):
            declared.append(repository_git(root, "show", f"{base}:{path}"))
    except Unreadable as error:
        raise Unreadable(f"Identity history unavailable: {error}") from None
    used = {match[1] or match[2] for line in log.splitlines() if line.startswith("+") and not line.startswith("+++")
            for match in IDENTITY_DECLARATION.finditer(line)}
    present = {match[1] or match[2] for text in declared for match in IDENTITY_DECLARATION.finditer(blanked(text))}
    return used, present


def reuse_faults(entries: dict, used: set[str], present: set[str]) -> list[tuple]:
    """TR-15: an identity the main branch's history declared and its merge base does not is
    declared again, whatever its text."""
    return [("TR-15", entry["file"], entry["line"], "Identity declared again: " + identity)
            for identity, entry in entries.items() if identity in used and identity not in present]


# ---- The code structure (TR-17, M2.3) ----

CODE_PATH = re.compile(r"(?:server|client)/[\w./-]+\.(?:rs|js|html|css)\b")
RUST_MOD = re.compile(r"((?:#\[[^\]]*\]\s*)*)(?:pub(?:\([^)]*\))?\s+)?mod\s+(\w+)\s*;")


def rust_modules(root: Path) -> list[str]:
    """The Rust code modules: every `*.rs` below `server/src/` but `*_tests.rs`, `tests.rs`
    and a module that every declaration declares under `#[cfg(test)]` or from a test file."""
    source_root = root / "server/src"
    files = sorted(path for path in source_root.rglob("*.rs") if path.is_file())
    declared = {}
    for path in files:
        code = blanked(path.read_text(encoding="utf-8"))
        folder = path.parent if path.name in ("mod.rs", "lib.rs", "main.rs") else path.parent / path.stem
        for match in RUST_MOD.finditer(code):
            attributes = match[1]
            source = path.read_text(encoding="utf-8")[match.start():match.end()]
            explicit = re.search(r'#\[path\s*=\s*"([^"]+)"\]', source)
            if explicit:
                target = (path.parent / explicit[1]).resolve()
            else:
                target = (folder / (match[2] + ".rs")).resolve()
                if not target.is_file():
                    target = (folder / match[2] / "mod.rs").resolve()
            # A declaration in a test file is one under `#[cfg(test)]`.
            test_file = path.name == "tests.rs" or path.name.endswith("_tests.rs")
            declared.setdefault(target, []).append(test_file or "cfg(test)" in attributes.replace(" ", ""))
    modules = []
    for path in files:
        if path.name == "tests.rs" or path.name.endswith("_tests.rs"):
            continue
        flags = declared.get(path.resolve())
        if flags and all(flags):
            continue
        modules.append(path.relative_to(root).as_posix())
    return modules


def code_modules(root: Path) -> list[str]:
    """The code modules of M2.3: the Rust modules and every `*.js` below `client/`."""
    scripts = sorted(path.relative_to(root).as_posix() for path in (root / "client").rglob("*.js") if path.is_file())
    return rust_modules(root) + scripts


def code_folders(folder: str) -> tuple[str, str]:
    """A part's code folders: `server/src/<folder>/` and `client/src/<folder>/`, `<folder>` its
    model folder below `backend/`, or `frontend`."""
    below = folder.removeprefix("backend/")
    return f"server/src/{below}/", f"client/src/{below}/"


def code_differs(model: Model, element: Element) -> list[tuple[Element, str]]:
    """The `@CodeDiffers` annotations directly in an element, with their `what` text."""
    found, source = [], model.sources[element.key]
    for child in element.children:
        if child.kind == "@" and child.name == "CodeDiffers" and child.opening >= 0:
            body = source[child.opening + 1:child.stop - 1]
            texts = [string_literal(value) for feature, value in assignments(body, blanked(body)) if feature == "what"]
            found.append((child, texts[0] if texts and texts[0] is not None else ""))
    return found


def structure_faults(model: Model, links: dict, root: Path) -> list[tuple]:
    """TR-17: every code module belongs to exactly one part by its part definition's
    `@ImplementedIn`; a part's modules, and the modules its clauses name, stand in its folder
    or are named by its part definition's `@CodeDiffers`; such a marker names no module
    inside the folder."""
    faults, owners, parts = [], {}, part_definitions(model)
    for folder, definition in parts.items():
        for module in part_link(model, definition):
            owners.setdefault(module, []).append(folder)
    for module in code_modules(root):
        found = owners.get(module, [])
        if not found and not module.startswith("server/src/shared/"):
            faults.append(("TR-17", module, None, "module of no part"))
        if len(found) > 1:
            faults.append(("TR-17", module, None, "module of two parts: " + ", ".join(sorted(found))))
    for folder, definition in parts.items():
        inside = code_folders(folder)
        named = {path for _marker, text in code_differs(model, definition) for path in CODE_PATH.findall(text)}
        used = set(part_link(model, definition))
        for identity, modules in links.items():
            if part_folder(model_entry_file(model, identity)) == folder:
                used.update(modules)
        for module in sorted(used):
            if not module.startswith(inside) and module not in named:
                faults.append(("TR-17", module, None, f"module of {definition.name} outside its folder without CodeDiffers"))
        for marker, text in code_differs(model, definition):
            for path in CODE_PATH.findall(text):
                if path.startswith(inside):
                    faults.append(("TR-17", definition.key, marker.line, f"CodeDiffers names a module inside the folder: {path}"))
    return faults


def model_entry_file(model: Model, identity: str) -> str:
    """The model file that declares `identity`."""
    if not hasattr(model, "declared_in"):
        model.declared_in = {identity_of(element): key for key in model.trees for element in model.elements(key)
                             if identity_of(element)}
    return model.declared_in.get(identity, "")


# ---- Model and code (TR-16, M6.8, M6.13) ----

UNIT_SCALE = {"Ms": 1.0, "Seconds": 1000.0}
RUST_SUFFIX = r"(?:u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|i128|isize|f32|f64)"
CODE_TOKEN = re.compile(r"/\*[\s\S]*?\*/|//[^\n]*|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`|[^/\"'`]+|.")
WIRE_FILES = ("interfaces/internal/StationLink.sysml", STATION_COMMANDS, "interfaces/external/Mcp.sysml",
              "backend/profile/ProfileDocument.sysml")
VARIABLE = re.compile(r"\bWSTX_[A-Z0-9_]+\b")


def snake(name: str) -> str:
    """A model name as `WstxStationLink::WireNames` writes it: each capital letter becomes an
    underscore and its small letter; digits stay with the word before them."""
    special = {"treat73AsCq": "treat_73_as_cq", "onePlusPer3000Km": "one_plus_per_3000_km",
               "onePlusPer500KmUp": "one_plus_per_500_km_up"}
    if name in special:
        return special[name]
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def upper_camel(name: str) -> str:
    return "".join(part[:1].upper() + part[1:] for part in snake(name).split("_") if part)


def code_text(source: str) -> tuple[str, set[str], set[str]]:
    """A code file without comments (strings kept), its identifiers, and its string values
    with the words each holds."""
    kept, identifiers, strings = [], set(), set()
    for token in CODE_TOKEN.finditer(source):
        text = token.group()
        if text.startswith(("//", "/*")):
            kept.append(re.sub(r"[^\n]", " ", text))
            continue
        kept.append(text)
        if text[:1] in "\"'`" and len(text) > 1:
            strings.add(text[1:-1])
            strings.update(re.findall(r"[A-Za-z0-9_]+", text[1:-1]))
        else:
            identifiers.update(re.findall(r"[A-Za-z_]\w*", text))
    return "".join(kept), identifiers, strings


class CodeScope:
    """The constants of the code modules: per module its top-level ones, the ones of each
    `impl D` and `mod d` block, and for JavaScript each `const D = Object.freeze({...})`."""

    def __init__(self, root: Path, modules: list[str]):
        self.root = root
        self.modules = modules
        self.text, self.identifiers, self.strings = {}, {}, {}
        self.top, self.impl, self.mod, self.types = {}, {}, {}, set()
        for module in modules:
            path = root / module
            if not path.is_file():
                continue
            text, identifiers, strings = code_text(path.read_text(encoding="utf-8"))
            self.text[module], self.identifiers[module], self.strings[module] = text, identifiers, strings
            if module.endswith(".rs"):
                self.read_rust(module, text)
            else:
                self.read_script(module, text)

    def read_rust(self, module: str, text: str):
        code = re.sub(r"\"(?:\\.|[^\"\\])*\"", lambda match: '"' + "_" * (len(match[0]) - 2) + '"', text)
        stack, start = [], 0
        for index, character in enumerate(code):
            if character in ";{}":
                if character == "{":
                    header = code[start:index]
                    impl = re.search(r"\bimpl\b(?:\s*<[^{]*?>)?\s+(?:(?:[\w:]+)(?:<[^{]*?>)?\s+for\s+)?(?:[\w]+::)*(\w+)(?:<[^{]*>)?\s*(?:where\b[^{]*)?$", header)
                    mod = re.search(r"\bmod\s+(\w+)\s*$", header)
                    kind = ("impl", impl[1]) if impl else ("mod", mod[1]) if mod else ("other", "")
                    shaped = re.search(r"\b(?:struct|enum)\s+(\w+)(?:<[^{]*>)?\s*(?:where\b[^{]*)?$", header)
                    if shaped and re.search(r"\w", code[index + 1:code.find("}", index)] if code.find("}", index) > 0 else ""):
                        self.types.add(shaped[1])
                    stack.append(kind)
                elif character == "}":
                    if stack:
                        stack.pop()
                start = index + 1
            if character == "(" and re.search(r"\bstruct\s+(\w+)\s*$", code[start:index]):
                self.types.add(re.search(r"\bstruct\s+(\w+)\s*$", code[start:index])[1])
        for match in re.finditer(r"(?:pub(?:\([^)]*\))?\s+)?(?:const|static)\s+(?:mut\s+)?([A-Z][A-Z0-9_]*)\s*:\s*[^=;]+?=\s*([^;]+);", code):
            depth = self.context(code, match.start())
            value = text[match.start(2):match.end(2)]
            if depth == []:
                self.top.setdefault(module, {})[match[1]] = value
            elif len(depth) == 1 and depth[0][0] == "impl":
                self.impl.setdefault((module, depth[0][1]), {})[match[1]] = value
            elif len(depth) == 1 and depth[0][0] == "mod":
                self.mod.setdefault((module, depth[0][1]), {})[match[1]] = value

    @staticmethod
    def context(code: str, offset: int) -> list:
        stack, start = [], 0
        for index in range(offset):
            character = code[index]
            if character == "{":
                header = code[start:index]
                impl = re.search(r"\bimpl\b(?:\s*<[^{]*?>)?\s+(?:(?:[\w:]+)(?:<[^{]*?>)?\s+for\s+)?(?:[\w]+::)*(\w+)(?:<[^{]*>)?\s*(?:where\b[^{]*)?$", header)
                mod = re.search(r"\bmod\s+(\w+)\s*$", header)
                stack.append(("impl", impl[1]) if impl else ("mod", mod[1]) if mod else ("other", ""))
                start = index + 1
            elif character == "}":
                if stack:
                    stack.pop()
                start = index + 1
            elif character == ";":
                start = index + 1
        return stack

    def read_script(self, module: str, text: str):
        depth = 0
        for index, line in enumerate(text.split("\n")):
            if depth == 0:
                if frozen := re.match(r"\s*(?:export\s+)?const\s+([A-Za-z_]\w*)\s*=\s*Object\.freeze\(\{", line):
                    body = text.split("\n")[index:]
                    joined = "\n".join(body)
                    end = joined.find("})")
                    for key, value in re.findall(r"\b([A-Z][A-Z0-9_]*)\s*:\s*([^,\n}]+)", joined[:end]):
                        self.impl.setdefault(("client/", frozen[1]), {})[key] = value.strip()
                elif plain := re.match(r"\s*(?:export\s+)?const\s+([A-Z][A-Z0-9_]*)\s*=\s*([^;]+);", line):
                    self.top.setdefault("client/", {})[plain[1]] = plain[2]
            depth += line.count("{") - line.count("}")

    def scope_of(self, module: str) -> str:
        return "client/" if module.endswith(".js") else module


def evaluate(text: str, names: dict, seen=()):
    """The value of a constant or model expression: a number, a string, a bool, None, a list,
    ("duration", milliseconds) or ("enum", literal); a ValueError when it is no constant."""
    text = text.strip()
    text = re.sub(r"(?<=\d)_(?=\d)", "", text)
    text = re.sub(r"(\d)_?" + RUST_SUFFIX + r"\b", r"\1", text)
    text = re.sub(r"\bas\s+" + RUST_SUFFIX + r"\b", "", text)
    text = re.sub(r"(?:std::time::)?Duration::from_secs(?:_f64)?\s*\(", "__seconds(", text)
    text = re.sub(r"(?:std::time::)?Duration::from_millis\s*\(", "__milliseconds(", text)
    text = re.sub(r"&\s*\[", "[", text)
    text = re.sub(r"(?<![\w.])(\d+)\.(?![\d\w])", r"\1.0", text)
    text = re.sub(r"\bSelf::", "", text)
    enum = re.fullmatch(r"(?:\w+::)*\w+::('[^']+'|\w+)", text)
    if enum and not re.fullmatch(r"\d.*", text):
        return ("enum", enum[1].strip("'"))
    text = re.sub(r"\btrue\b", "True", re.sub(r"\bfalse\b", "False", re.sub(r"\bnull\b", "None", text)))
    try:
        tree = ast.parse(text, mode="eval")
    except SyntaxError:
        raise ValueError("no constant: " + text) from None
    operators = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul, ast.Mod: operator.mod,
                 ast.LShift: operator.lshift, ast.FloorDiv: operator.floordiv}

    def value(node):
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, (ast.List, ast.Tuple)):
            return [value(item) for item in node.elts]
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
            inner = value(node.operand)
            return -inner if isinstance(node.op, ast.USub) else inner
        if isinstance(node, ast.BinOp):
            left, right = value(node.left), value(node.right)
            if isinstance(node.op, ast.Div):
                return int(left / right) if isinstance(left, int) and isinstance(right, int) else left / right
            if type(node.op) in operators:
                return operators[type(node.op)](left, right)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and len(node.args) == 1:
            scale = {"__seconds": 1000.0, "__milliseconds": 1.0}.get(node.func.id)
            if scale is not None:
                return ("duration", value(node.args[0]) * scale)
        if isinstance(node, ast.Name) and node.id in names and node.id not in seen:
            return evaluate(names[node.id], names, (*seen, node.id))
        raise ValueError("no constant: " + text)

    return value(tree.body)


def equal(model_text: str, model_value, code_value, feature: str) -> bool:
    """Whether a code constant holds the model value, read in the unit of the feature's name."""
    if isinstance(code_value, tuple) and code_value[0] == "duration":
        unit = next((suffix for suffix in UNIT_SCALE if feature.endswith(suffix)), None)
        if unit is None:
            return False
        code_value = code_value[1] / UNIT_SCALE[unit]
    if isinstance(model_value, tuple) and model_value[0] == "enum":
        return isinstance(code_value, str) and code_value in (model_value[1], snake(model_value[1]))
    if isinstance(model_value, list):
        return isinstance(code_value, list) and len(model_value) == len(code_value) and \
            all(equal(str(item), item, other, feature) for item, other in zip(model_value, code_value))
    if isinstance(model_value, bool) or isinstance(code_value, bool):
        return model_value is code_value
    if isinstance(model_value, (int, float)) and isinstance(code_value, (int, float)):
        decimals = re.search(r"\.(\d+)\s*$", model_text)
        if decimals and isinstance(model_value, float):
            return round(code_value, len(decimals[1])) == round(model_value, len(decimals[1]))
        return code_value == model_value
    return model_value == code_value


class Compared:
    """One compared element of the model: a value, a name or a variable."""

    def __init__(self, kind: str, element: Element, qualified: str, owner, feature: str, text: str = ""):
        self.kind, self.element, self.qualified, self.owner, self.feature, self.text = kind, element, qualified, owner, feature, text


def compared_elements(model: Model, controls: set[str]) -> list[Compared]:
    """The elements TR-16 compares: each attribute value below a definition, each enumeration
    literal outside `shared/`, each feature name of the wire files and control interfaces,
    each `'type'` value and each `WSTX_*` variable the model names; Requirements.sysml left
    out."""
    found = []
    wire = set(WIRE_FILES) | {key for key, package in model.packages.items() if package in controls}
    for key, tree in model.trees.items():
        if key == REQUIREMENTS_FILE:
            continue
        package = model.packages.get(key)
        source = model.sources[key]
        for element in list(tree.walk())[1:]:
            owner = element.parent
            while owner is not None and not owner.kind.endswith("def"):
                owner = owner.parent
            if owner is None or not element.name:
                continue
            name = element.name.strip("'")
            qualified = f"{package}::{owner.name}::{element.name}"
            if element.kind == "enum" and owner.kind == "enum def":
                if not key.startswith("shared/"):
                    found.append(Compared("name", element, qualified, owner, name))
                continue
            if element.kind not in ("attribute", "item"):
                continue
            equals = re.search(r"(?<![=!<>:])=(?![=>])", element.head)
            if element.kind == "attribute" and equals:
                text = source[element.begin + equals.end():element.begin + len(element.head)].strip().rstrip(";").strip()
                if name == "type":
                    literal = string_literal(text)
                    found.append(Compared("name", element, qualified, owner, literal if literal is not None else text))
                elif key in wire and owner.kind == "item def":
                    found.append(Compared("name", element, qualified, owner, name))
                else:
                    found.append(Compared("value", element, qualified, owner, name, text))
            elif key in wire and owner.kind.endswith("def"):
                found.append(Compared("name", element, qualified, owner, name))
        for number, line in enumerate(source.split(chr(10)), 1):
            for match in VARIABLE.finditer(line):
                holder = Element(key, "variable", match[0], 0, 0, -1, None, "")
                holder.line = number
                found.append(Compared("variable", holder, match[0], None, match[0]))
    unique = {}
    for item in found:
        unique.setdefault((item.kind, item.qualified, item.element.key, item.element.line), item)
    return list(unique.values())


def clause_reach(model: Model, entries: dict) -> dict[int, list[str]]:
    """For each definition (by id of its element) the clauses that name it in their sentence
    or reach it through the typed features of one they name."""
    definitions = {}
    for key in model.trees:
        for element in model.elements(key):
            if element.kind.endswith("def") and element.name:
                definitions.setdefault((key, element.name), element)

    def resolve(key: str, written: str):
        return model.find_definition(key, written)

    def typed(definition: Element) -> list[Element]:
        reached = []
        for child in definition.children:
            if child.kind in ("attribute", "item", "part", "port", "ref", "enum") and child.type_written():
                if found := resolve(definition.key, child.type_written()):
                    reached.append(found)
        if supertype := re.search(r"(?::>|\bspecializes\b)\s*((?:\w+::)*\w+)", definition.head):
            if found := resolve(definition.key, supertype[1]):
                reached.append(found)
        return reached

    reach = {}
    for identity, entry in entries.items():
        if not identity.startswith("CL-"):
            continue
        key = entry["file"]
        element = next((element for element in model.elements(key) if identity_of(element) == identity), None)
        if element is None:
            continue
        doc = element.doc
        named = [definition for (file, name), definition in definitions.items()
                 if file == key and re.search(r"\b" + re.escape(name) + r"\b", doc)]
        for qualified in re.findall(r"\b(Wstx\w+)::(\w+)", doc):
            if (target := model.package_files.get(qualified[0])) and (found := definitions.get((target, qualified[1]))):
                named.append(found)
        queue, seen = list(named), set()
        while queue:
            definition = queue.pop()
            if id(definition) in seen:
                continue
            seen.add(id(definition))
            reach.setdefault(id(definition), []).append(identity)
            queue.extend(typed(definition))
    return reach


def part_code(model: Model, links: dict, all_modules: list[str]) -> dict[str, list[str]]:
    """The code of each part folder: its part definition's modules and those its clauses name."""
    code = {}
    for folder, definition in part_definitions(model).items():
        code[folder] = set(part_link(model, definition))
    for identity, modules in links.items():
        if folder := part_folder(model_entry_file(model, identity)):
            code.setdefault(folder, set()).update(modules)
    return {folder: sorted(module for module in modules if module in all_modules) for folder, modules in code.items()}


def value_faults(model: Model, entries: dict, links: dict, root: Path) -> list[tuple]:
    """TR-16: each compared element is covered, in this order, by V3 (every clause naming or
    reaching it is target or partial), V4 (its `@CodeDiffers`, refused where its code
    matches), V1 (its constant, name or variable in its code) or V2: a test bound to a case
    of a clause reaching it (the test `symbol` of a `path::symbol` binding, or a test of a
    bound file that names the case by its `Proves:` tag or title) holds in its own code,
    outside comments, its qualified name, or its definition's qualified name and the
    feature's name. Its own code is its body and the bodies of the functions of its file it
    calls, directly or through each other. A comment is a Rust `//`, `///`, `//!` or block
    comment, a Node `//` or block comment, or a Python `#` comment or docstring. Another
    test, the file's top level, a comment before the test and a comment inside it do not
    count. A variable is never verified by V2."""
    modules = code_modules(root)
    scope = CodeScope(root, modules)
    controls = control_packages(model)
    elements = compared_elements(model, controls)
    reach = clause_reach(model, entries)
    codes = part_code(model, links, modules)
    readers = BoundTestCode(root)
    faults = []

    def code_of(element: Element) -> list[str]:
        if element.key.startswith(("interfaces/", "shared/")) or part_folder(element.key) is None:
            return modules
        return codes.get(part_folder(element.key), [])

    values_by_feature = {}
    for item in elements:
        if item.kind == "value":
            for module in code_of(item.element):
                values_by_feature.setdefault((scope.scope_of(module), item.feature), set()).add(item.qualified)

    def candidates(item: Compared, mine: list[str]):
        constant = snake(item.feature).upper()
        owner = item.owner.name
        scopes = sorted({scope.scope_of(module) for module in mine})
        first = [(module, values[constant]) for (module, typed), values in scope.impl.items()
                 if typed == owner and constant in values and module in scopes
                 and (module == "client/" or owner in scope.types)]
        if first:
            return first, None
        second = [(module, values[constant]) for (module, name), values in scope.mod.items()
                  if name == snake(owner) and constant in values and module in scopes]
        if second:
            return second, None
        third = [(module, scope.top[module][constant]) for module in scopes if constant in scope.top.get(module, {})]
        if len(third) == 1 and len(values_by_feature.get((third[0][0], item.feature), set())) > 1:
            return third, "shared"
        return third, None

    def matches(item: Compared, mine: list[str]):
        """(found, equal, what) for V1."""
        if item.kind == "variable":
            found = any(item.feature in scope.strings.get(module, ()) for module in mine)
            return found, found, ""
        if item.kind == "name":
            forms = {item.feature, snake(item.feature), upper_camel(item.feature)}
            found = any(forms & (scope.identifiers.get(module, set()) | scope.strings.get(module, set())) for module in mine)
            return found, found, ""
        found, shared = candidates(item, mine)
        if not found:
            return False, False, ""
        if len(found) > 1 or shared:
            return True, None, "twice"
        module, text = found[0]
        names = dict(scope.top.get(module, {}))
        for (holder, _owner), values in list(scope.impl.items()) + list(scope.mod.items()):
            if holder == module:
                names.update(values)
        try:
            model_value = evaluate(item.text, {})
            code_value = evaluate(text, names)
        except (ValueError, ZeroDivisionError, TypeError, RecursionError):
            return True, False, f"model {item.text}, code {text.strip()}"
        return True, equal(item.text, model_value, code_value, item.feature), f"model {item.text}, code {text.strip()}"

    for item in elements:
        element = item.element
        mine = code_of(element)
        line = element.line
        owner_reach = reach.get(id(item.owner), []) if item.owner is not None else []
        clauses = sorted(set(owner_reach))
        if clauses and all(entries[clause]["state"] in ("target", "partial") for clause in clauses):
            continue
        markers = code_differs(model, element) if item.kind != "variable" else []
        found, same, what = matches(item, mine)
        if markers:
            if same:
                faults.append(("TR-16", element.key, line, "Code matches its CodeDiffers: " + item.qualified))
            continue
        if same is None:
            faults.append(("TR-16", element.key, line, "Name twice in one code: " + snake(item.feature).upper()))
            continue
        if same:
            continue
        if found and item.kind == "value":
            faults.append(("TR-16", element.key, line, f"Model and code differ: {item.qualified}: {what}"))
            continue
        package, _, rest = item.qualified.partition("::")
        definition = package + "::" + rest.rsplit("::", 1)[0]
        if item.kind != "variable" and any(
                held_in(code, item.qualified, definition, item.element.name)
                for clause in clauses for case in entries[clause]["cases"]
                for binding in entries[case]["bindings"] if binding
                for code in readers.codes(case, binding)):
            continue
        faults.append(("TR-16", element.key, line, "Value not verified: " + item.qualified))
    return faults


def held_in(code: str, qualified: str, definition: str, name: str) -> bool:
    """V2: the code of one bound test holds, outside comments, the qualified name, or both its
    definition's qualified name and the feature's name. The code is the test's own code: its
    body and the bodies of the functions of its file it calls, directly or through each
    other (`BoundTestCode`); another test, the file's top level, a comment before the test
    and a comment inside it are not in it."""
    return qualified in code or definition in code and re.search(r"(?<![\w'])" + re.escape(name.strip("'")) + r"(?![\w'])", code) is not None


# ---- The own code of a bound test (TR-16, V2) ----

RUST_FUNCTION = re.compile(r"(?<![\w$])fn\s+(\w+)")
JS_FUNCTION = re.compile(r"(?<![\w$.])(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)\s*\(")
JS_ARROW_HEAD = re.compile(r"(?<![\w$.])(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?")
JS_ARROW_PARAMETER = re.compile(r"[A-Za-z_$][\w$]*\s*=>")
CALL_FORM = re.compile(r"(?<![\w$])([A-Za-z_$][\w$]*)\s*\(")
CLOSERS = {"(": ")", "[": "]", "{": "}"}


def spaced_out(source: str, spans) -> str:
    """`source` with each (start, end) span replaced by spaces, its line breaks kept."""
    code = list(source)
    for start, end in spans:
        code[start:end] = re.sub(r"[^\n]", " ", source[start:end])
    return "".join(code)


def closing(code: str, opening: int) -> int:
    """The end, after the closing bracket, of the bracket at `opening` in `code` (comments and
    strings blanked); refused when it does not close."""
    stack, index = [], opening
    while index < len(code):
        character = code[index]
        if character in CLOSERS:
            stack.append(CLOSERS[character])
        elif character in ")]}":
            if not stack or stack.pop() != character:
                break
            if not stack:
                return index + 1
        index += 1
    raise SourceUnreadable("a bracket without its end", opening)


class SourceCode:
    """One source file read for V2: `functions` maps each function name to its (start, end)
    spans, `tests` maps each test name to its spans, `code` is the text without comments,
    `masked` the text without comments and strings."""

    def __init__(self, code: str, masked: str, functions: dict, tests: dict, calls=None):
        self.code, self.masked, self.functions, self.tests = code, masked, functions, tests
        self._calls = calls

    def calls(self, span) -> set[str]:
        if self._calls is not None:
            return self._calls.get(span, set())
        return set(CALL_FORM.findall(self.masked, span[0], span[1]))

    def own_code(self, name: str) -> list[str]:
        """The code of each test named `name`: its body and the bodies of the functions of
        the file it calls, directly or through each other; other tests never."""
        test_spans = {span for spans in self.tests.values() for span in spans}
        found = []
        for span in self.tests.get(name) or self.functions.get(name, []):
            seen, todo = {span}, [span]
            while todo:
                for called in self.calls(todo.pop()):
                    for helper in self.functions.get(called, []):
                        if helper not in seen and helper not in test_spans:
                            seen.add(helper)
                            todo.append(helper)
            found.append("\n".join(self.code[start:end] for start, end in sorted(seen)))
        return found


def rust_code(source: str) -> SourceCode:
    """The functions and tests of Rust source; a test is a function under `#[test]` or
    `#[tokio::test]`, or any function named by a `path::symbol` binding."""
    segments = rust_segments(source)
    code = spaced_out(source, [(start, end) for kind, start, end in segments if kind == "comment"])
    masked = spaced_out(source, [(start, end) for _kind, start, end in segments])
    characters, index = [], 0
    while index < len(masked):
        if masked[index] == "'":
            literal = RUST_CHARACTER.match(masked, index) or RUST_LIFETIME.match(masked, index)
            end = literal.end() if literal else index + 1
            if literal and literal.group().endswith("'"):
                characters.append((index, end))
        elif word := SOURCE_WORD.match(masked, index):
            end = word.end()
        else:
            end = index + 1
        index = end
    masked = spaced_out(masked, characters)
    functions = {}
    for match in RUST_FUNCTION.finditer(masked):
        index, depth = match.end(), 0
        while index < len(masked):
            if masked[index] in "([":
                depth += 1
            elif masked[index] in ")]":
                depth -= 1
            elif masked[index] in "{;" and depth == 0:
                break
            index += 1
        if index < len(masked) and masked[index] == "{":
            functions.setdefault(match[1], []).append((match.start(), closing(masked, index)))
    marked = {name for name, _offset in rust_test_names(source, segments)}
    tests = {name: spans for name, spans in functions.items() if name in marked}
    return SourceCode(code, masked, functions, tests)


def javascript_code(source: str) -> SourceCode:
    """The functions (`function name(`, `const name = … =>`) and the tests (each `test(`,
    `it(` call by its title, as `node_tests` reads it) of JavaScript source."""
    regexes = []
    found, _end = javascript_segments(source, regexes=regexes)
    comments = [(start, end) for kind, start, end in found if kind == "comment"]
    if source.startswith("#!"):
        comments.append((0, line_end(source, 0)))
    code = spaced_out(source, comments)
    masked = spaced_out(source, comments +[(start, end) for _kind, start, end in found] + regexes)
    strings = {start: end for kind, start, end in found if kind == "string"}
    functions = {}
    for match in JS_FUNCTION.finditer(masked):
        body = masked.find("{", closing(masked, match.end() - 1))
        if body >= 0:
            functions.setdefault(match[1], []).append((match.start(), closing(masked, body)))
    for match in JS_ARROW_HEAD.finditer(masked):
        index = match.end()
        if masked.startswith("(", index):
            index = closing(masked, index)
            arrow = re.compile(r"\s*=>").match(masked, index)
        else:
            arrow = JS_ARROW_PARAMETER.match(masked, index)
        if not arrow:
            continue
        index = arrow.end()
        while index < len(masked) and masked[index] in " \t":
            index += 1
        if masked.startswith("{", index):
            end = closing(masked, index)
        else:
            end, depth = index, 0
            while end < len(masked):
                character = masked[end]
                if character in CLOSERS:
                    depth += 1
                elif character in ")]}":
                    if depth == 0:
                        break
                    depth -= 1
                elif character in ";\n" and depth == 0:
                    break
                end += 1
        functions.setdefault(match[1], []).append((match.start(), end))
    tests = {}
    for match in JS_TEST_CALL.finditer(masked):
        if not match[1] and JS_FUNCTION_HEAD.search(masked, max(0, match.start() - 40), match.start()):
            continue
        index = match.end()
        while index < len(masked) and masked[index].isspace():
            index += 1
        opening = source[index] if index < len(source) else ""
        if opening in ("'", '"') and index + 1 in strings:
            title = re.sub(r"\\(.)", r"\1", source[index + 1:strings[index + 1]])
        elif opening == "`":
            end = javascript_template(source, index, [])
            title = source[index + 1:end - 1].replace("\r\n", "\n").replace("\n", "\\n")
        else:
            continue
        tests.setdefault(title, []).append((match.start(), closing(masked, match.end() - 1)))
    return SourceCode(code, masked, functions, tests)


def python_code(source: str) -> SourceCode:
    """The functions and the tests (`<Class>.<name>` or `<name>`, as `python_tests` names them)
    of Python source; comments are its `#` comments and the docstrings."""
    module = ast.parse(source)
    lines = source.splitlines(keepends=True)
    starts = [0]
    for text in lines:
        starts.append(starts[-1] + len(text))

    def offset(line: int, column: int) -> int:
        """The character offset of a 1-based line and a UTF-8 byte column."""
        text = lines[line - 1] if line <= len(lines) else ""
        return starts[line - 1] + len(text.encode("utf-8")[:column].decode("utf-8", "ignore"))

    comments = []
    for token in tokenize.generate_tokens(io.StringIO(source).readline):
        if token.type == tokenize.COMMENT:
            comments.append((starts[token.start[0] - 1] + token.start[1], starts[token.end[0] - 1] + token.end[1]))
    for node in ast.walk(module):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Module)) and node.body:
            first = node.body[0]
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
                comments.append((offset(first.lineno, first.col_offset), offset(first.end_lineno, first.end_col_offset)))
    code = spaced_out(source, comments)
    functions, tests, calls = {}, {}, {}

    def span(node) -> tuple[int, int]:
        return starts[node.lineno - 1], starts[min(node.end_lineno, len(lines))]

    definitions = {}
    for node in ast.walk(module):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            definitions[node.lineno] = node
    for line, name in python_test_lines(module).items():
        tests.setdefault(name, []).append(span(definitions[line]))
    for node in ast.walk(module):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            functions.setdefault(node.name, []).append(span(node))
            calls[span(node)] = {call.func.id if isinstance(call.func, ast.Name) else call.func.attr
                                 for call in ast.walk(node) if isinstance(call, ast.Call)
                                 and isinstance(call.func, (ast.Name, ast.Attribute))}
    return SourceCode(code, code, functions, tests, calls)


class BoundTestCode:
    """V2's reader: the code of each test bound to a case, read once per file. A file that
    cannot be read, or code its reader cannot place, gives no code."""

    READERS = {"rust": rust_code, "node": javascript_code, "python": python_code}

    def __init__(self, root: Path):
        self.root, self.files, self.found = root, {}, {}

    def source(self, path: str):
        if path not in self.files:
            try:
                source = source_text(path, self.root / path)
                read = self.READERS[TEST_KINDS.get(posixpath.splitext(path)[1], "node")](source)
                self.files[path] = read
            except (OSError, ValueError, SyntaxError, IndexError, tokenize.TokenError):
                self.files[path] = None
        return self.files[path]

    def codes(self, case: str, binding: str) -> list[str]:
        """The code, without comments, of each test `bound_tests` names for `case` by
        `binding`."""
        if (case, binding) not in self.found:
            codes = []
            if code := self.source(binding.partition("::")[0]):
                try:
                    names = {line.split(" ", 1)[1] for line in bound_tests(case, [binding], self.root)}
                except (OSError, ValueError):
                    names = set()
                for name in sorted(names):
                    codes += code.own_code(name)
            self.found[(case, binding)] = codes
        return self.found[(case, binding)]


# ---- History in comments, names and test strings (TR-22) ----

HISTORY_SUFFIXES = (".rs", ".js", ".cjs", ".mjs", ".css", ".html", ".py", ".ps1", ".java", ".sysml", ".toml", ".yml", ".md")
HISTORY_ROOTS = ("server/", "client/", "tests/", "tools/", "fixtures/")
HISTORY_FILES = ("README.md", "Cargo.toml", "server/Cargo.toml", "rust-toolchain.toml")
HISTORY_OUTSIDE = ("server/third-party/",)
WORKFLOWS = ".github/workflows/"
HARNESS_CONFIG = "harness/project/config.yaml"
# The places whose string literals are test or tool code.
STRING_PLACES = ("tests/", "server/tests/", "tools/", "fixtures/")
TEST_MODULE = re.compile(r"server/(?:.*/)?[^/]*_tests?\.rs")
STRING_SUFFIXES = (".rs", ".js", ".cjs", ".mjs", ".py", ".ps1")
COMMENT_EXCEPTIONS = "tools/sysml/comment-exceptions.json"
EXCEPTION_KINDS = ("D1", "D2", "D3", "M", "S", "I")
POINTER_FORMS = (
    re.compile(r"(?:(?:[A-Za-z0-9._-]+/)?[A-Za-z0-9._-]+)?(?<![&#])#\d+(?![A-Za-z0-9])"),
    re.compile(r"(?<![A-Za-z0-9])(?:issue|cr|pr)[ _#-]?\d+(?![A-Za-z0-9])", re.I),
    re.compile(r"(?<![A-Za-z0-9])review \d{6,}(?![A-Za-z0-9])", re.I),
)
DATE_FORM = re.compile(r"(?<![A-Za-z0-9])(?:19|20)\d\d-[01]\d-[0-3]\d(?![0-9])")
STORY_FORM = re.compile(r"\b(?:formerly|previously|no[ \t]+longer|any[ \t]+more|anymore|as[ \t]+before|used[ \t]+to"
                        r"|originally|retired|legacy|was[ \t]+changed|were[ \t]+changed|red[ \t]+on[ \t]+the[ \t]+parent"
                        r"|review[ \t]+finding|finding[ \t]+\d+|round[ \t]+\d+|operator[ \t]+grill|operator[ \t]+decision"
                        r"|coordinator(?:['’]s)?[ \t]+decision|live[ \t]+defect|live[ \t]+finding)\b", re.I)
URL_TEXT = re.compile(r"\b[A-Za-z][A-Za-z0-9+.-]*://[^\s<>\"'`)\]]*")
MARKDOWN_TARGET = re.compile(r"\]\(\s*<?([^)\s>]*)")
TEST_NAME_POINTER = re.compile(r"(?:^|_)(?:issue|cr|pr)_?\d+(?=_|$)", re.I)
RUST_TEST_ATTRIBUTE = re.compile(r"#\[(?:tokio::)?test\b[^\]]*\]((?:\s*#\[[^\]]*\])*)\s*(?:pub(?:\([^)]*\))?\s+)?"
                                 r"(?:async\s+)?(?:unsafe\s+)?fn\s+(\w+)")
RUST_CHARACTER = re.compile(r"""'(?:[^'\\\n\r\t]|\\(?:[nrt\\0'"]|x[0-9a-fA-F]{2}|u\{[0-9a-fA-F_]{1,8}\}))'""")
RUST_LIFETIME = re.compile(r"'(?:r#)?[^\W\d]\w*")
RUST_RAW_STRING = re.compile(r'(?:br|cr|r)(#*)"')
SOURCE_WORD = re.compile(r"[\w$]+")
# The JavaScript words after which a `/` opens a regular expression, the control heads, and the
# words after which a `{` opens a block.
JS_BEFORE_EXPRESSION = {"return", "typeof", "instanceof", "in", "of", "new", "delete", "void", "throw", "case",
                        "do", "else", "yield", "await"}
JS_CONTROL = {"if", "while", "for", "with"}
JS_BLOCK_AFTER = {"else", "do", "try", "finally"}


class SourceUnreadable(ValueError):
    """A text the reader of its language cannot read: the reason and the offset."""

    def __init__(self, reason: str, offset: int):
        super().__init__(reason)
        self.reason, self.offset = reason, offset


def quoted_end(source: str, start: int, quote: str, escape: str | None = "\\", multiline: bool = True) -> int:
    """The end, after the closing quote, of the string that opens at `start` with `quote`."""
    index = start + len(quote)
    while index < len(source):
        if escape and source[index] == escape:
            index += 2
        elif source.startswith(quote, index):
            return index + len(quote)
        elif source[index] == "\n" and not multiline:
            break
        else:
            index += 1
    raise SourceUnreadable("a string without its end", start)


def block_end(source: str, start: int, opener: str, closer: str, nested: bool = False) -> int:
    """The end of the block comment that opens at `start`."""
    depth, index = 1, start + len(opener)
    while depth:
        if index >= len(source):
            raise SourceUnreadable("a block comment without its end", start)
        if source.startswith(closer, index):
            depth, index = depth - 1, index + len(closer)
        elif nested and source.startswith(opener, index):
            depth, index = depth + 1, index + len(opener)
        else:
            index += 1
    return index


def line_end(source: str, start: int) -> int:
    end = source.find("\n", start)
    return len(source) if end < 0 else end


def rust_segments(source: str) -> list[tuple[str, int, int]]:
    """(kind, start, end) of the comments and the string contents of Rust source."""
    found, index = [], 0
    while index < len(source):
        character = source[index]
        if source.startswith("//", index):
            end = line_end(source, index)
            found.append(("comment", index, end))
        elif source.startswith("/*", index):
            end = block_end(source, index, "/*", "*/", nested=True)
            found.append(("comment", index, end))
        elif character == '"':
            end = quoted_end(source, index, '"')
            found.append(("string", index + 1, end - 1))
        elif character == "'":
            literal = RUST_CHARACTER.match(source, index) or RUST_LIFETIME.match(source, index)
            if not literal:
                raise SourceUnreadable("a ' that opens neither a char literal nor a lifetime", index)
            end = literal.end()
        elif raw := RUST_RAW_STRING.match(source, index):
            close = source.find('"' + raw[1], raw.end())
            if close < 0:
                raise SourceUnreadable("a raw string without its end", index)
            found.append(("string", raw.end(), close))
            end = close + 1 + len(raw[1])
        elif word := SOURCE_WORD.match(source, index):
            end = word.end()
        else:
            end = index + 1
        index = end
    return found


def rust_test_names(source: str, found: list[tuple[str, int, int]]) -> list[tuple[str, int]]:
    """(name, offset) of every function under `#[test]` or `#[tokio::test]`."""
    code = list(source)
    for _kind, start, end in found:
        code[start:end] = re.sub(r"[^\n]", " ", source[start:end])
    return [(match[2], match.start(2)) for match in RUST_TEST_ATTRIBUTE.finditer("".join(code))]


def javascript_segments(source: str, start: int = 0, nested: bool = False, regexes: list | None = None) -> tuple[list, int]:
    """(segments, end) of JavaScript from `start`: to the end of the text, or with `nested` (a
    template's `${`) to the brace that closes it. A regular expression literal is one token,
    neither string nor comment, whose (start, end) `regexes` receives; a `/` that opens none
    the line closes is unreadable."""
    found, index, significant, parens, braces, closed = [], start, [], [], [], None
    while index < len(source):
        character = source[index]
        if character.isspace():
            index += 1
            continue
        if index == 0 and source.startswith("#!"):
            end = line_end(source, index)
        elif source.startswith("//", index):
            end = line_end(source, index)
            found.append(("comment", index, end))
        elif source.startswith("/*", index):
            end = block_end(source, index, "/*", "*/")
            found.append(("comment", index, end))
        elif source.startswith("<!--", index) or (source.startswith("-->", index)
                                                   and not source[source.rfind("\n", 0, index) + 1:index].strip()):
            raise SourceUnreadable("an HTML-like comment in JavaScript", index)
        elif character in "'\"":
            end = quoted_end(source, index, character, multiline=False)
            found.append(("string", index + 1, end - 1))
            significant.append((character, "literal"))
        elif character == "`":
            end = javascript_template(source, index, found, regexes)
            significant.append((character, "literal"))
        elif character == "/" and javascript_regex_here(significant, closed):
            end = javascript_regex_end(source, index)
            if regexes is not None:
                regexes.append((index, end))
            significant.append((character, "literal"))
        elif word := SOURCE_WORD.match(source, index):
            end = word.end()
            significant.append((word.group(), "word"))
        else:
            if character == "(":
                parens.append(bool(significant) and significant[-1][0] in JS_CONTROL)
            elif character == ")":
                closed = ("paren", parens.pop() if parens else False)
            elif character == "{":
                braces.append(javascript_block_here(significant))
            elif character == "}":
                if not braces and nested:
                    return found, index + 1
                closed = ("brace", braces.pop() if braces else True)
            end = index + 1
            significant.append((character, "punct", index))
        index = end
    if nested:
        raise SourceUnreadable("a template string's ${ without its }", start)
    return found, index


def javascript_regex_here(significant: list, closed) -> bool:
    """Does a `/` here open a regular expression? After an operand it divides."""
    if not significant:
        return True
    token, kind = significant[-1][:2]
    if kind == "literal":
        return False
    if kind == "word":
        return token in JS_BEFORE_EXPRESSION
    if token == "]":
        return False
    if token in ")}":
        return bool(closed and closed[1])
    if token in "+-" and len(significant) >= 3 and significant[-2][0] == token and significant[-2][1] == "punct" \
            and significant[-1][2] == significant[-2][2] + 1:
        before = significant[-3]
        return not (before[1] == "literal" or before[0] in (")", "]")
                    or (before[1] == "word" and before[0] not in JS_BEFORE_EXPRESSION))
    return True


def javascript_block_here(significant: list) -> bool:
    """Does a `{` here open a block, not an object?"""
    if not significant:
        return True
    token, kind = significant[-1][:2]
    if kind == "word":
        return token in JS_BLOCK_AFTER
    return token in (";", "{", "}", ")") or (token == ">" and len(significant) >= 2 and significant[-2][0] == "=")


def javascript_template(source: str, start: int, found: list, regexes: list | None = None) -> int:
    """The end of the template string at `start`; its text parts are strings, its `${}` code."""
    index, part = start + 1, start + 1
    while index < len(source):
        if source[index] == "\\":
            index += 2
        elif source[index] == "`":
            found.append(("string", part, index))
            return index + 1
        elif source.startswith("${", index):
            found.append(("string", part, index))
            inner, index = javascript_segments(source, index + 2, nested=True, regexes=regexes)
            found.extend(inner)
            part = index
        else:
            index += 1
    raise SourceUnreadable("a template string without its end", start)


def javascript_regex_end(source: str, start: int) -> int:
    """The end of the regular expression literal at `start`, its flags included."""
    index, in_class = start + 1, False
    while index < len(source) and source[index] not in "\n\r  ":
        if source[index] == "\\":
            index += 2
            continue
        if source[index] == "[":
            in_class = True
        elif source[index] == "]":
            in_class = False
        elif source[index] == "/" and not in_class:
            index += 1
            while index < len(source) and (source[index].isalnum() or source[index] in "_$"):
                index += 1
            return index
        index += 1
    raise SourceUnreadable("a / that opens no regular expression the line closes", start)


def c_like_segments(source: str, text_blocks: bool = False, names: bool = False) -> list[tuple[str, int, int]]:
    """Comments and string contents of CSS, Java (`text_blocks`) and SysML (`names`: a quoted
    name is code)."""
    found, index = [], 0
    while index < len(source):
        character = source[index]
        if source.startswith("/*", index):
            end = block_end(source, index, "/*", "*/")
            found.append(("comment", index, end))
        elif source.startswith("//", index) and (text_blocks or names):
            end = line_end(source, index)
            found.append(("comment", index, end))
        elif text_blocks and source.startswith('"""', index):
            end = quoted_end(source, index, '"""')
            found.append(("string", index + 3, end - 3))
        elif character in "'\"":
            end = quoted_end(source, index, character, multiline=names)
            if not (names and character == "'"):
                found.append(("string", index + 1, end - 1))
        elif word := SOURCE_WORD.match(source, index):
            end = word.end()
        else:
            end = index + 1
        index = end
    return found


def html_segments(source: str) -> list[tuple[str, int, int]]:
    """The `<!-- -->` comments of HTML, outside script and style elements."""
    found, index = [], 0
    while index < len(source):
        if source.startswith("<!--", index):
            close = source.find("-->", index + 4)
            if close < 0:
                raise SourceUnreadable("a <!-- without its -->", index)
            found.append(("comment", index, close + 3))
            index = close + 3
        elif raw := re.compile(r"<(script|style)\b", re.I).match(source, index):
            close = re.compile(rf"</{raw[1]}\s*>", re.I).search(source, raw.end())
            if not close:
                raise SourceUnreadable(f"a <{raw[1]}> without its end tag", index)
            index = close.end()
        else:
            index += 1
    return found


def python_segments(source: str) -> tuple[list[tuple[str, int, int]], list[tuple[str, int]]]:
    """The comments, docstrings (comments) and string contents of Python, and (name, offset) of
    every function whose name starts with `test`."""
    try:
        tree = ast.parse(source)
    except (SyntaxError, ValueError) as error:
        raise SourceUnreadable(f"Python that does not parse ({error.__class__.__name__})", 0) from None
    lines = io.StringIO(source).readlines()
    starts = [0]
    for line in lines:
        starts.append(starts[-1] + len(line))

    def offset(line: int, column: int, byte: bool = False) -> int:
        if byte:
            column = len(lines[line - 1].encode("utf-8")[:column].decode("utf-8", "replace"))
        return starts[line - 1] + column

    documents, names = set(), []
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)) and node.body:
            first = node.body[0]
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
                documents.add(offset(first.lineno, first.col_offset, byte=True))
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test"):
            name_line = lines[node.lineno - 1]
            column = name_line.find(node.name)
            names.append((node.name, starts[node.lineno - 1] + max(column, 0)))
    found = []
    middle = getattr(tokenize, "FSTRING_MIDDLE", None)
    try:
        for token in tokenize.generate_tokens(io.StringIO(source).readline):
            begin, end = offset(*token.start), offset(*token.end)
            if token.type == tokenize.COMMENT:
                found.append(("comment", begin, end))
            elif token.type == tokenize.STRING:
                if begin in documents:
                    found.append(("comment", begin, end))
                else:
                    quote = re.match(r"[A-Za-z]*('''|\"\"\"|'|\")", token.string)
                    found.append(("string", begin + quote.end(), end - len(quote[1])))
            elif middle is not None and token.type == middle:
                found.append(("string", begin, end))
    except (tokenize.TokenError, SyntaxError) as error:
        raise SourceUnreadable(f"Python that does not tokenize ({error})", 0) from None
    return found, names


POWERSHELL_DOUBLE, POWERSHELL_SINGLE = '"“”„', "'‘’‚‛"
POWERSHELL_HERE = re.compile(r"@([\"“”„'‘’‚‛])[ \t]*\r?\n")


def powershell_segments(source: str) -> list[tuple[str, int, int]]:
    """The `#` and `<# #>` comments and the string contents of PowerShell. A `#` or `<#` right
    after a word belongs to the word."""
    found, index, open_ = [], 0, True
    while index < len(source):
        character = source[index]
        if character.isspace():
            index, open_ = index + 1, True
            continue
        if open_ and source.startswith("<#", index):
            end = block_end(source, index, "<#", "#>")
            found.append(("comment", index, end))
        elif open_ and character == "#":
            end = line_end(source, index)
            found.append(("comment", index, end))
        elif character == "`":
            index, open_ = min(index + 2, len(source)), False
            continue
        elif here := POWERSHELL_HERE.match(source, index):
            quotes = POWERSHELL_DOUBLE if here[1] in POWERSHELL_DOUBLE else POWERSHELL_SINGLE
            close = re.compile(rf"\n[{quotes}]@").search(source, here.end() - 1)
            if not close:
                raise SourceUnreadable("a here-string without its end", index)
            found.append(("string", here.end(), close.start()))
            end = close.end()
        elif character in POWERSHELL_SINGLE or character in POWERSHELL_DOUBLE:
            end = powershell_string_end(source, index)
            found.append(("string", index + 1, end - 1))
        elif word := SOURCE_WORD.match(source, index):
            index, open_ = word.end(), False
            continue
        else:
            index, open_ = index + 1, character in ";(){}|,"
            continue
        index, open_ = end, True
    return found


def powershell_string_end(source: str, start: int) -> int:
    quotes = POWERSHELL_SINGLE if source[start] in POWERSHELL_SINGLE else POWERSHELL_DOUBLE
    index, depth = start + 1, 0
    while index < len(source):
        character = source[index]
        if character == "`" and quotes is POWERSHELL_DOUBLE:
            index += 2
            continue
        if quotes is POWERSHELL_DOUBLE and source.startswith("$(", index):
            depth, index = depth + 1, index + 2
            continue
        if depth and character == ")":
            depth -= 1
        elif not depth and character in quotes:
            if index + 1 < len(source) and source[index + 1] in quotes:
                index += 2
                continue
            return index + 1
        index += 1
    raise SourceUnreadable("a string without its end", start)


def hash_segments(source: str, yaml: bool = False) -> list[tuple[str, int, int]]:
    """The `#` comments of TOML, and of YAML outside its block scalars, outside strings."""
    found, offset, block = [], 0, None
    for line in source.splitlines(keepends=True):
        body = line.rstrip("\r\n")
        indent = len(body) - len(body.lstrip(" "))
        if block is not None and (not body.strip() or indent > block):
            offset += len(line)
            continue
        block, quote, index = None, None, 0
        while index < len(body):
            character = body[index]
            if quote:
                if character == "\\" and quote == '"':
                    index += 1
                elif character == quote:
                    quote = None
            elif character in "'\"" and (not yaml or index == 0 or body[index - 1] in " \t[{,"):
                quote = character
            elif character == "#" and (index == 0 or body[index - 1] in " \t" or not yaml):
                found.append(("comment", offset + index, offset + len(body)))
                body = body[:index]
                break
            index += 1
        if yaml and re.search(r"(?:^|:|-)\s*[|>][-+0-9]*\s*$", body):
            block = indent
        offset += len(line)
    return found


MARKDOWN_FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")


def markdown_segments(source: str) -> list[tuple[str, int, int]]:
    """Markdown: fenced code blocks and code spans as `code`, the prose between as `comment`."""
    found, offset, fence, prose = [], 0, None, []
    for line in source.splitlines(keepends=True):
        opening = MARKDOWN_FENCE.match(line)
        if fence is None and opening:
            fence = opening[1]
            found.append(("code", offset, offset + len(line)))
        elif fence is not None:
            found.append(("code", offset, offset + len(line)))
            if opening and opening[1][0] == fence[0] and len(opening[1]) >= len(fence) and not line[opening.end():].strip():
                fence = None
        else:
            prose.append((offset, offset + len(line)))
        offset += len(line)
    for begin, end in merged(prose):
        index = part = begin
        while index < end:
            if source[index] == "`":
                run = re.compile(r"`+").match(source, index).group()
                close = re.compile(r"(?<!`)" + run + r"(?!`)").search(source, index + len(run), end)
                if close:
                    found.append(("comment", part, index))
                    found.append(("code", index, close.end()))
                    index = part = close.end()
                    continue
                index += len(run)
            elif source[index] == "\\":
                index += 2
            else:
                index += 1
        found.append(("comment", part, end))
    return found


def merged(spans: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Adjacent spans joined into one."""
    joined = []
    for begin, end in spans:
        if joined and joined[-1][1] == begin:
            joined[-1] = (joined[-1][0], end)
        else:
            joined.append((begin, end))
    return joined


def source_segments(key: str, source: str) -> tuple[list[tuple[str, int, int]], list[tuple[str, int]]]:
    """The segments of a file by its kind, and its test function names."""
    suffix = Path(key).suffix
    if suffix == ".rs":
        found = rust_segments(source)
        return found, rust_test_names(source, found)
    if suffix in (".js", ".cjs", ".mjs"):
        return javascript_segments(source)[0], []
    if suffix == ".py":
        return python_segments(source)
    if suffix == ".ps1":
        return powershell_segments(source), []
    if suffix == ".css":
        return c_like_segments(source), []
    if suffix == ".java":
        return c_like_segments(source, text_blocks=True), []
    if suffix == ".sysml":
        return c_like_segments(source, names=True), []
    if suffix == ".html":
        return html_segments(source), []
    if suffix in (".toml", ".yml"):
        return hash_segments(source, yaml=suffix == ".yml"), []
    return markdown_segments(source), []


def harness_paths(root: Path) -> tuple[str, ...]:
    """The `harness_paths:` list of the project's harness configuration."""
    path, listed, inside = root / HARNESS_CONFIG, [], False
    if not path.is_file():
        return ()
    for line in path.read_text(encoding="utf-8").splitlines():
        if re.match(r"harness_paths:\s*$", line):
            inside = True
        elif inside and (item := re.match(r"\s+-\s+(\S+)\s*$", line)):
            listed.append(item[1])
        elif inside and line.strip() and not line.lstrip().startswith("#"):
            inside = False
    return tuple(listed)


def history_files(root: Path, commit: str | None = None) -> list[str]:
    """The tracked files TR-22 reads, by repository path, sorted. With `commit`, `root` holds
    that commit's tree and the files are those of the commit in the repository `ROOT`."""
    if commit:
        tracked = git("-c", "core.quotepath=off", "ls-tree", "-r", "--name-only", "-z", commit).split("\0")
    else:
        tracked = repository_git(root, "-c", "core.quotepath=off", "ls-files", "-z").split("\0")
    harness = harness_paths(root)
    read = []
    for key in tracked:
        if not key.endswith(HISTORY_SUFFIXES) or not (root / key).is_file():
            continue
        if key.startswith(HISTORY_ROOTS) and not key.startswith(HISTORY_OUTSIDE) or key in HISTORY_FILES:
            read.append(key)
        elif key.startswith(WORKFLOWS) and not any(key == path or key.startswith(path.rstrip("/") + "/")
                                                   for path in harness):
            read.append(key)
    return sorted(read)


def strings_read(key: str) -> bool:
    """Are the string literals of `key` test or tool code?"""
    return key.endswith(STRING_SUFFIXES) and (key.startswith(STRING_PLACES) or TEST_MODULE.fullmatch(key) is not None)


def unread_urls(text: str, markdown: bool) -> str:
    """`text` with the text of every URL, and in Markdown of every link target, blanked."""
    text = URL_TEXT.sub(lambda match: " " * len(match.group()), text)
    if markdown:
        text = MARKDOWN_TARGET.sub(lambda match: match.group()[:match.start(1) - match.start()]
                                   + " " * len(match[1]), text)
    return text


def pointers(text: str) -> list[tuple[int, int]]:
    """The spans of the issue pointers of `text`; of two that overlap, the longer."""
    spans = {match.span() for form in POINTER_FORMS for match in form.finditer(text)}
    kept = []
    for begin, end in sorted(spans, key=lambda span: (span[0] - span[1], span[0])):
        if not any(begin < other_end and other_begin < end for other_begin, other_end in kept):
            kept.append((begin, end))
    return sorted(kept)


def file_findings(key: str, source: str) -> list[tuple[int, int, str]]:
    """(start, end, message) of every history TR-22 finds in one file."""
    found, names = source_segments(key, source)
    markdown, strings, findings = key.endswith(".md"), strings_read(key), []
    for kind, begin, end in found:
        if kind == "string" and not strings:
            continue
        text = unread_urls(source[begin:end], markdown)
        for start, stop in pointers(text):
            what = {"comment": "history in a comment: issue pointer ", "string": "issue pointer in a string: ",
                    "code": "issue pointer in Markdown code: "}[kind]
            findings.append((begin + start, begin + stop, what + text[start:stop]))
        if kind == "comment":
            for form, what in ((DATE_FORM, "date "), (STORY_FORM, "change story ")):
                for match in form.finditer(text):
                    findings.append((begin + match.start(), begin + match.end(),
                                     "history in a comment: " + what + match.group()))
    for name, offset in names:
        if TEST_NAME_POINTER.search(name):
            findings.append((offset, offset + len(name), "issue pointer in a test name: " + name))
    return findings


def comment_exceptions(root: Path) -> tuple[list[tuple[int, str, str]], list[tuple]]:
    """(line, path, text) of each entry of the exception list, and its faults."""
    path, faults, entries = root / COMMENT_EXCEPTIONS, [], []
    if not path.is_file():
        return entries, faults
    text = path.read_text(encoding="utf-8")
    try:
        listed = json.loads(text)
    except json.JSONDecodeError:
        listed = None
    if not isinstance(listed, list):
        return entries, [("TR-22", COMMENT_EXCEPTIONS, 1, "comment exception malformed: not a JSON array")]
    decoder, space = json.JSONDecoder(), re.compile(r"[\s,]*")
    index = space.match(text, text.index("[") + 1).end()
    for _ in listed:
        line = text.count("\n", 0, index) + 1
        entry, index = decoder.raw_decode(text, index)
        index = space.match(text, index).end()
        reason = None
        if not isinstance(entry, dict):
            reason = "an entry that is no object"
        elif not isinstance(entry.get("path"), str) or not entry["path"]:
            reason = "no path"
        elif not isinstance(entry.get("text"), str) or not entry["text"]:
            reason = "no text"
        elif entry.get("kind") not in EXCEPTION_KINDS:
            reason = f"kind {entry.get('kind')} is not one of {', '.join(EXCEPTION_KINDS)}"
        elif set(entry) != {"path", "text", "kind"}:
            reason = "a field other than path, text and kind"
        if reason:
            faults.append(("TR-22", COMMENT_EXCEPTIONS, line, "comment exception malformed: " + reason))
        else:
            entries.append((line, entry["path"], entry["text"]))
    return entries, faults


def history_faults(root: Path, commit: str | None = None) -> tuple[list[tuple], int, int]:
    """TR-22: (faults, files read, comment exceptions used). Comments, docstrings and Markdown
    prose hold no issue pointer, date or change story; test and tool strings, Markdown code
    and test function names hold no issue pointer; an exception holds its own text in its own
    file. With `commit`, `root` holds that commit's tree (`history_files`)."""
    entries, faults = comment_exceptions(root)
    used, keys = set(), history_files(root, commit)
    for key in keys:
        try:
            source = (root / key).read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            faults.append(("TR-22", key, None, "source not UTF-8"))
            continue
        source = source[1:] if source.startswith("﻿") else source
        try:
            findings = file_findings(key, source)
        except SourceUnreadable as error:
            faults.append(("TR-22", key, source.count("\n", 0, error.offset) + 1, f"source not readable: {error.reason}"))
            continue
        exempt = [(entry, match.start(), match.end()) for entry in entries if entry[1] == key
                  for match in re.finditer(re.escape(entry[2]), source)]
        for start, end, what in findings:
            covering = [entry for entry, begin, stop in exempt if begin <= start and end <= stop]
            if covering:
                used.update(covering)
            else:
                faults.append(("TR-22", key, source.count("\n", 0, start) + 1, what))
    for entry in entries:
        if entry not in used:
            faults.append(("TR-22", COMMENT_EXCEPTIONS, entry[0], f"comment exception unused: {entry[1]} {entry[2]}"))
    return faults, len(keys), len(used)


def model_keys(directory: Path) -> tuple[list[str], list[Path]]:
    """The model file keys and paths in the order the Pilot reads them: Requirements first."""
    files = model_files(directory)
    keys = [REQUIREMENTS_FILE, *(key for key in files if key != REQUIREMENTS_FILE)]
    return keys, [files[key] for key in keys if key in files]


def trace_faults(entries: dict, model: Model, root: Path, origins: dict | None = None) -> tuple[dict, list[tuple]]:
    """The checks of `traces` after the catalog and the tags: code links (TR-13), model and
    code (TR-16) and the code structure (TR-17). `origins` as `code_links` fills it."""
    links, faults = code_links(model, entries, origins)
    faults += value_faults(model, entries, links, root)
    faults += structure_faults(model, links, root)
    return links, faults


def refuse(lines: list[str]) -> None:
    if lines:
        print("\n".join(lines))
        raise ValueError(f"{len(lines)} faults")


class Tree:
    """The files the checks read: the working tree (`commit` None) or the tree of `commit`
    extracted below `root`. The tool's own code and the toolchain are never taken from it."""

    def __init__(self, root: Path, models: Path, fsd: Path, oracle: Path, commit: str | None):
        self.root, self.models, self.fsd, self.oracle, self.commit = root, models, fsd, oracle, commit


@contextlib.contextmanager
def revision_tree(revision: str | None):
    """The working tree for no revision; else the tree of the commit `revision` names,
    written into a temporary folder that is gone when the block ends. The repository, its
    index and its working tree are not written."""
    if revision is None:
        yield Tree(ROOT, MODELS, FSD, ORACLE, None)
        return
    commit = commit_of(revision)
    with tempfile.TemporaryDirectory(prefix="sysml-revision-") as folder:
        root = Path(folder) / "tree"
        extract(commit, root)
        yield Tree(root, root / "docs/sysml", root / "docs/WSTX Rust FSD.md",
                   root / "tools/sysml/architecture-oracle.json", commit)


def checked_entries(tree: Tree | None = None) -> dict:
    """The authority, the catalog, the tags and the tag bindings, as `traces` and `check`
    begin; on the working tree without `tree`."""
    tree = tree or Tree(ROOT, MODELS, FSD, ORACLE, None)
    authority(tree.models, tree.fsd)
    entries = canonical_catalog(tree.models, tree.root)
    refuse(tag_faults(entries, tree.root))
    binding_agreement(entries, tree.root)
    return entries


# ---- The code proof listings (TR-23) ----

NODE_TEST_FILE = re.compile(r"[^/]+\.test\.(?:js|cjs|mjs)")
# A Node test call: `test(`, `it(`, `test.skip(`, `test.only(`, `test.todo(`, and `.test(` (a
# subtest, or a RegExp test when its first argument is no literal).
JS_TEST_CALL = re.compile(r"(\.)\s*test\s*\(|(?<![\w$.])(?:test|it)(?:\s*\.\s*(?:skip|only|todo))?\s*\(")
JS_FUNCTION_HEAD = re.compile(r"\bfunction\s*\*?\s*$")
TEST_KINDS = {".rs": "rust", ".js": "node", ".cjs": "node", ".mjs": "node", ".py": "python"}
IDENTITY_ORDER = {"FR": 0, "CL": 1, "TC": 2}


def source_text(key: str, path: Path) -> str:
    """The text of a source file, without its byte order mark; refused when it is no UTF-8."""
    try:
        source = path.read_bytes().decode("utf-8")
    except UnicodeDecodeError:
        raise ValueError(f"source not readable: {key}:1: source not UTF-8") from None
    return source[1:] if source.startswith("﻿") else source


def not_readable(key: str, source: str, error: SourceUnreadable) -> ValueError:
    return ValueError(f"source not readable: {key}:{source.count(chr(10), 0, error.offset) + 1}: {error.reason}")


def rust_tests(key: str, source: str) -> list[str]:
    """The names of the functions under `#[test]` or `#[tokio::test…]` of Rust source."""
    try:
        return [name for name, _offset in rust_test_names(source, rust_segments(source))]
    except SourceUnreadable as error:
        raise not_readable(key, source, error) from None


def node_tests(key: str, source: str) -> list[str]:
    """The titles of the Node tests of `source` (TR-23): the first argument of each `test(`,
    `it(`, `test.skip(`, `test.only(`, `test.todo(` and `.test(` call outside comments,
    strings and regular expressions. A quoted title with its escapes resolved, a template
    title as written with a line break written `\\n`. A `test(` or `it(` whose title is no
    literal is refused; a `.test(` without a literal is a RegExp test and not listed."""
    regexes = []
    try:
        found, _end = javascript_segments(source, regexes=regexes)
    except SourceUnreadable as error:
        raise not_readable(key, source, error) from None
    code = list(source)
    for begin, end in [(begin, end) for _kind, begin, end in found] + regexes:
        code[begin:end] = re.sub(r"[^\n]", " ", source[begin:end])
    if source.startswith("#!"):
        end = line_end(source, 0)
        code[0:end] = " " * end
    code = "".join(code)
    strings = {begin: end for kind, begin, end in found if kind == "string"}
    titles = []
    for match in JS_TEST_CALL.finditer(code):
        if not match[1] and JS_FUNCTION_HEAD.search(code, max(0, match.start() - 40), match.start()):
            continue
        index = match.end()
        while index < len(code) and code[index].isspace():
            index += 1
        opening = source[index] if index < len(source) else ""
        if opening in ("'", '"') and index + 1 in strings:
            titles.append(re.sub(r"\\(.)", r"\1", source[index + 1:strings[index + 1]]))
        elif opening == "`":
            end = javascript_template(source, index, [])
            titles.append(source[index + 1:end - 1].replace("\r\n", "\n").replace("\n", "\\n"))
        elif not match[1]:
            raise ValueError(f"unreadable test name: {key}:{source.count(chr(10), 0, match.start()) + 1}")
    return titles


def python_tests(key: str, source: str) -> list[str]:
    """`<Class>.<name>` of each `def test_…` directly in a class body and `<name>` of each at
    module level."""
    try:
        module = ast.parse(source)
    except (SyntaxError, ValueError) as error:
        line = getattr(error, "lineno", None) or 1
        raise ValueError(f"source not readable: {key}:{line}: Python that does not parse ({error.__class__.__name__})") from None
    return list(python_test_lines(module).values())


def python_test_lines(module: ast.Module) -> dict[int, str]:
    """The line of each `def test_…` directly in a class body or at module level, in source
    order, with its name: `<Class>.<name>` or `<name>`."""
    names = {}

    def scan(body: list, owner: str | None):
        for node in body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test_"):
                names[node.lineno] = f"{owner}.{node.name}" if owner else node.name
            elif isinstance(node, ast.ClassDef):
                scan(node.body, node.name)

    scan(module.body, None)
    return names


def tracked_files(tree: Tree) -> list[str]:
    """The files of the tree's commit, by repository path, sorted."""
    listing = git("-c", "core.quotepath=off", "ls-tree", "-r", "--name-only", "-z", tree.commit)
    return sorted(key for key in listing.split("\0") if key and (tree.root / key).is_file())


def inventory_lines(tree: Tree) -> list[str]:
    """TR-23: one line per product test of the tree's commit, sorted; no line holds a path."""
    harness = harness_paths(tree.root)
    lines = []
    for key in tracked_files(tree):
        name, below = posixpath.basename(key), key.split("/", 1)[0] in SOURCE_BINDING_ROOTS and "/" in key
        if below and key.endswith(".rs"):
            lines += ["rust " + test for test in rust_tests(key, source_text(key, tree.root / key))]
        elif below and NODE_TEST_FILE.fullmatch(name):
            lines += ["node " + test for test in node_tests(key, source_text(key, tree.root / key))]
        elif name.startswith("test_") and name.endswith(".py") and not key.startswith("tools/sysml/") \
                and not any(key == path or key.startswith(path.rstrip("/") + "/") for path in harness):
            lines += ["python " + test for test in python_tests(key, source_text(key, tree.root / key))]
    return sorted(lines)


def bound_tests(identity: str, bindings: list[str], root: Path) -> list[str]:
    """The inventory lines of the tests bound to a case: for `path::symbol` the test
    `symbol`, for a whole file each of its tests that names the case by its `Proves:` tag or
    its title."""
    found = set()
    for binding in bindings:
        path, separator, symbol = binding.partition("::")
        kind = TEST_KINDS.get(posixpath.splitext(path)[1], "node")
        if separator:
            found.add(f"{kind} {symbol}")
            continue
        source = source_text(path, root / path)
        found.update(f"{kind} {name}" for name, cases in naming_tests(source) if identity in cases)
        if kind == "node" and NODE_TEST_FILE.fullmatch(posixpath.basename(path)):
            found.update("node " + title for title in node_tests(path, source)
                         if re.search(r"\b" + re.escape(identity) + r"\b", title))
    return sorted(found)


def trace_lines(entries: dict, origins: dict, root: Path) -> list[str]:
    """TR-23: the trace listing, one line per identity, FR then CL then TC, each in identity
    order; no line holds a path or a model file key."""
    def listed(items) -> str:
        return ",".join(items) or "-"

    lines = []
    for identity in sorted(entries, key=lambda name: (IDENTITY_ORDER[name[:2]], name)):
        entry = entries[identity]
        if identity.startswith("FR-"):
            lines.append(f"{identity} {entry['status']} clauses {listed(entry['clauses'])}")
        elif identity.startswith("CL-"):
            own = sorted({posixpath.basename(module) for module in entry["own"] if module})
            link = "own " + ",".join(own) if own else "part " + origins[identity] if identity in origins else "none"
            lines.append(f"{identity} {entry['state']} from {listed(entry['frs'])} cases {listed(entry['cases'])} link {link}")
        else:
            tests = "; ".join(bound_tests(identity, [binding for binding in entry["bindings"] if binding], root)) or "-"
            lines.append(f"{identity} {entry['state']} {'manual' if entry['manual'] else 'automated'} "
                         f"verifies {listed(sorted(entry['refs']))} tests {tests}")
    return lines


def print_lines(lines: list[str]) -> None:
    """`lines` on stdout as UTF-8, whatever the console's code page: a test title may hold
    any character."""
    text = "".join(line + "\n" for line in lines)
    if hasattr(sys.stdout, "buffer"):
        sys.stdout.flush()
        sys.stdout.buffer.write(text.encode("utf-8"))
        sys.stdout.buffer.flush()
    else:
        sys.stdout.write(text)


def model_check(tree: Tree, cache: Path) -> int:
    """`check` on `tree`: the traces, the Pilot validation, the oracle and every rule."""
    entries = checked_entries(tree)
    model = Model(tree.models)
    _links, faults = trace_faults(entries, model, tree.root)
    faults += history_faults(tree.root, tree.commit)[0]
    used, present = identity_history(ROOT, tree.commit or "HEAD")
    keys, paths = model_keys(tree.models)
    result = validate(paths, cache, inventory=True)
    print(f"Canonical SysML catalog/trace checks passed: {len(entries)} identities; behavioral correspondence remains independently reviewed.")
    for line in result.stdout.splitlines():
        if not line.startswith(("Reading ", "AST\t")):
            print(line)
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="")
    if result.returncode:
        return result.returncode
    counts = architecture_integrity(result.stdout, tree.oracle)
    print("Architecture integrity passed: " + ", ".join(f"{count} {kind}" for kind, count in counts.items()) + "; runtime behavior not proved.")
    deployment = Deployment(inventory_records(result.stdout), keys)
    served, ends = served_and_ends(deployment, model)
    faults += tree_faults(tree.models, model) + layer_faults(model) + content_faults(model)
    faults += clause_faults(model, entries, served, ends) + role_faults(deployment) + agent_faults(model)
    faults += context_faults(deployment) + connection_faults(deployment) + reuse_faults(entries, used, present)
    faults += writing_faults(model)
    refuse(fault_lines(faults))
    print(f"Model rules passed: {len(model.files)} model files.")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=Path, default=Path.home() / ".cache/wsjtx-rust/sysml-tools")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("setup", help="Download and verify pinned portable tools; no global installation")
    commands.add_parser("fingerprints", help="Print canonical model fingerprints for review; never updates models")
    whole = commands.add_parser("check", help="Check the model whole: traces, the Pilot validation, the oracle and every rule "
                                "(revision omitted: the working tree)")
    whole.add_argument("revision", nargs="?")
    traced = commands.add_parser("traces", help="Check the catalog, tags, code links, model values and code structure; no Pilot. "
                                 "With a revision, print its trace listing")
    traced.add_argument("revision", nargs="?")
    inventory = commands.add_parser("tests", help="Print the test inventory of a revision; writes nothing")
    inventory.add_argument("revision", nargs="?")
    listing = commands.add_parser("markers", help="List the WstxModelNotes markers of the model by file key and line; checks and writes nothing")
    listing.add_argument("kinds", nargs="*", metavar="Kind")
    commands.add_parser("status", help="Check the catalog, then print each FR's status computed from its clauses; writes nothing")
    commands.add_parser("oracle", help="Write the architecture oracle file from the resolved inventory after validation and the fixed rules; print its changes")
    semantic = commands.add_parser("validate", help="Run real semantic validation on ordered files")
    semantic.add_argument("files", nargs="+", type=Path)
    same = commands.add_parser("equivalence", help="Compare the model of two revisions by meaning (head omitted: the working tree); writes nothing")
    same.add_argument("--marked", action="store_true", help="each commit of master..HEAD marked Model-Move: pure against its first parent")
    same.add_argument("base", nargs="?")
    same.add_argument("head", nargs="?")
    listed = commands.add_parser("identities", help="List the FR/CL/TC identities of two revisions with their status; writes nothing")
    listed.add_argument("base")
    listed.add_argument("head", nargs="?")
    renames = commands.add_parser("paths", help="Rewrite the code paths the model names from a rename list, after the files were moved")
    renames.add_argument("list", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "setup":
            setup(args.cache_dir)
            return 0
        if args.command in ("equivalence", "identities"):
            if args.command == "identities":
                code, lines = identities(args.base, args.head)
            elif args.marked:
                if args.base or args.head:
                    raise Unreadable("--marked takes no revision")
                code, lines = marked(args.cache_dir)
            elif not args.base:
                raise Unreadable("equivalence needs <base> or --marked")
            else:
                results, _exports = compare_revisions([(args.base, args.head)], args.cache_dir)
                code, lines = results[0]
            print("\n".join(lines))
            return code
        if args.command == "tests":
            if not args.revision:
                raise Unreadable("unknown revision: none given")
            with revision_tree(args.revision) as tree:
                lines = inventory_lines(tree)
            print_lines(lines)
            return 0
        if args.command == "traces":
            with revision_tree(args.revision) as tree:
                entries = checked_entries(tree)
                origins = {}
                _links, faults = trace_faults(entries, Model(tree.models), tree.root, origins)
                history, read, used = history_faults(tree.root, tree.commit)
                refuse(fault_lines(faults + history))
                if tree.commit:
                    lines = trace_lines(entries, origins, tree.root)
            if tree.commit:
                print_lines(lines)
                return 0
            print(f"Canonical source/model trace checks passed: {len(entries)} identities; {read} files read for history, "
                  f"{used} comment exceptions used; no semantic validation or behavior execution.")
            return 0
        if args.command == "markers":
            authority(MODELS, FSD)
            print("\n".join(markers(MODELS, args.kinds)))
            return 0
        if args.command == "paths":
            authority(MODELS, FSD)
            code, lines = rewrite_paths(args.list, MODELS, ROOT)
            print("\n".join(lines))
            return code
        if args.command == "status":
            authority(MODELS, FSD)
            print("\n".join(status_lines(canonical_catalog(MODELS, ROOT))))
            return 0
        if args.command == "oracle":
            authority(MODELS, FSD)
            print("\n".join(write_architecture_oracle(args.cache_dir)))
            return 0
        if args.command == "fingerprints":
            authority(MODELS, FSD)
            canonical_catalog(MODELS, ROOT)
            print(json.dumps({key: digest(path.read_text(encoding="utf-8")) for key, path in model_files(MODELS).items()}, indent=2))
            return 0
        if args.command == "validate":
            result = validate(args.files, args.cache_dir)
            for line in result.stdout.splitlines():
                if not line.startswith("Reading "):
                    print(line)
            if result.stderr:
                print(result.stderr, file=sys.stderr, end="")
            return result.returncode
        with revision_tree(args.revision) as tree:
            return model_check(tree, args.cache_dir)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"SysML check failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
