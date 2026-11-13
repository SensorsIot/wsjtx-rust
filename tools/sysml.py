"""Canonical-authority SysML checks and real OMG Pilot validation.

traces checks catalog and source/model bindings only, and that every test naming a
case is in that case's binding (binding_agreement). check additionally calls the
pinned Java parser/name resolver/semantic validator. markers lists the ModelNotes markers
and checks nothing. retired checks the catalog and lists the `@RetiredCase` retirements;
status checks it and prints each FR's status computed from its clauses (CL-014-19).
equivalence compares two revisions of the model by meaning and identities lists the
identity diff of two revisions (CL-014-17); both only read the repository. oracle
writes the architecture oracle file from the resolved inventory, printing one line per
change (CL-014-06); no other command writes it. None executes modeled behavior.
"""
from __future__ import annotations

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import posixpath
import re
import stat
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import urllib.parse
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FSD = ROOT / "docs/WSTX Rust FSD.md"
MODELS = ROOT / "docs/sysml"
TOOLCHAIN = Path(__file__).with_name("sysml") / "toolchain.json"
# The TC-DOC-005 oracle of the deployment. `check` compares it with the inventory; only
# `oracle` writes it, after the Pilot validation and the fixed rules pass (CL-014-06).
ORACLE = Path(__file__).with_name("sysml") / "architecture-oracle.json"
ID = re.compile(r"\b(?:FR-\d{3}|CL-\d{3}-\d{2}|TC-(?:\d{3}|DOC)-\d{3})\b")
CANONICAL_MARKER = "// Canonical authority: SysML"
SOURCE_BINDING_ROOTS = ("client", "server", "tests")
# Each required package is the package of exactly one model file, whatever the file's
# name and folder. A change that renames or dissolves one changes this list with it.
REQUIRED_PACKAGES = {"WstxRequirements", "WstxArchitecture"}
# The context file, directly in the model folder: whenever it exists, its package is
# CONTEXT_PACKAGE and is required too; no other model file names that package in code,
# and the context file declares no identity (CL-014-10).
CONTEXT_FILE = "Context.sysml"
CONTEXT_PACKAGE = "WstxContext"
# The package whose `metadata def` names are the marker kinds that `markers` lists.
MARKER_PACKAGE = "ModelNotes"
IDENTITY = r"(?:FR-\d{3}|CL-\d{3}-\d{2}|TC-\d{3}-\d{3})"
# A declaration the catalog reads: `requirement '<ID>' {`, the same with `def`, and a
# verification case typed by a definition, `verification '<TC>' : <Definition> {`.
DECLARATION = re.compile(r"\b(requirement|verification)(\s+def)?\s+'(" + IDENTITY + r")'\s*(?::\s*((?:\w+::)*\w+)\s*)?\{")
# A requirement or verification whose name or short name is a stable identity, in any form.
IDENTITY_DECLARATION = re.compile(r"\b(?:requirement|verification)(?:\s+def)?\s+(?:<\s*'(" + IDENTITY + r")'\s*>|(?:<[^<>{};]*>\s*)?'(" + IDENTITY + r")')")
# A verification definition without identity: a shared definition for test cases.
CASE_DEFINITION = re.compile(r"\bverification\s+def\s+(?:<[^<>{};]*>\s*)?(\w+|'[^']*')[^{};]*\{")
STRING = r'"(?:\\.|[^"\\])*"'
# Stable identities are an independent migration admission baseline, not generated
# from the candidate under review. New identities may be added without renumbering.
BASELINE_IDENTITIES = {f"FR-{i:03}" for i in range(1, 24)}
for _group, _suffixes in {
    3: range(1, 9), 5: range(1, 6), 6: range(1, 5), 7: range(1, 5),
    8: range(1, 8), 10: (5, 7, 8, 9), 13: range(1, 7),
}.items():
    BASELINE_IDENTITIES.update(f"CL-{_group:03}-{i:02}" for i in _suffixes)
for _group, _suffixes in {
    2: (1, 3), 4: range(1, 4), 7: (2, 6), 9: range(1, 6),
    10: range(1, 8), 18: range(1, 4), 21: range(5, 10),
    22: range(1, 6), 23: range(1, 7),
}.items():
    BASELINE_IDENTITIES.update(f"TC-{_group:03}-{i:03}" for i in _suffixes)


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


def string_literal(value: str):
    """The text of a value that is one string literal; None for anything else."""
    literal = re.fullmatch(r'"([^"\r\n]*)"', value)
    return literal[1] if literal else None


def stated(body: str, code: str, kind: str) -> tuple[list, list, list, set]:
    """What one body states, in the attribute form and the metadata form together:
    (states, bindings, methods, unread). An invalid state is "", a binding or method that
    is not one string literal is None. `unread` holds each of "state", "binding" and
    "method" that the body names in a spelling that is not read: such a fact is the
    declaration's own, so nothing is taken over for it."""
    if kind == "verification":
        state_name, enum, status, state_feature = "automation", "AutomationState", "Automation", "run"
        binding_name, bound, bound_feature = "executable", "TestedBy", "test"
    else:
        state_name, enum, status, state_feature = "coverage", "ImplementationState", "Status", "build"
        binding_name, bound, bound_feature = "implementation", "ImplementedIn", "module"
    states = re.findall(r"\battribute\s+" + state_name + r"\s*:\s*" + enum + r"\s*=\s*" + enum + r"::(\w+)\s*;", body)
    bindings = re.findall(r'\battribute\s+' + binding_name + r'\s*:\s*String\s*=\s*"([^"\r\n]*)"\s*;', body)
    methods = re.findall(r'\battribute\s+method\s*:\s*String\s*=\s*"([^"\r\n]*)"\s*;', body)
    # The feature word outside the read annotations, more often than the attribute form was
    # read: another spelling of the attribute, such as `attribute :>> automation = ...`.
    plain = code
    for name in (status, bound):
        for match in re.finditer(r"@\s*(?:\w+::)*" + name + r"\b(?!::)\s*\{", code):
            inside = len(declaration_body(body, match.end() - 1))
            plain = plain[:match.end()] + " " * inside + plain[match.end() + inside:]
    unread = {fact for fact, name, read in (("state", state_name, states), ("binding", binding_name, bindings), ("method", "method", methods))
              if len(re.findall(r"\b" + name + r"\b", plain)) > len(read)}
    # The same metadata written with the `metadata` keyword is not read either.
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


def file_retirements(key: str, source: str) -> list[tuple[str, str, int, tuple]]:
    """The `@RetiredCase` annotations of one model file, in the order of the file, as
    (identity, test, line, superseding cases). A retirement into the detail tests,
    `{ identity = "<TC>"; test = "<path>"; }`, has no superseding cases; a superseded one,
    `{ identity = "<TC>"; supersededBy = "<TC>; <TC>"; }`, has test None. Each is checked
    in that order: an FR or CL identity, any other spelling (the line of the `@`, or of
    the word `metadata` in the keyword form), and for the test form a test that no
    `@DetailTests` directly in the same body names as written. The file itself is the
    `@DetailTests` check's; whether the superseding cases exist is the catalog's."""
    text, code = blanked(source, strings=False), blanked(source)
    found = list(annotations(text, code, "RetiredCase"))
    found += [(match.start(), None) for match in
              re.finditer(r"\bmetadata(?!\s+def\b)\s+[^;{}]*\bRetiredCase\b(?!::)", code)]
    details = []
    for offset, pairs in annotations(text, code, "DetailTests"):
        for feature, value in pairs:
            if feature == "tests" and (literal := string_literal(value)) is not None:
                details.append((offset, [path.strip() for path in literal.split(";")]))
    owners = owning_bodies(code, [offset for offset, _pairs in found] + [offset for offset, _paths in details])
    named = {}
    for offset, paths in details:
        named.setdefault(owners[offset], set()).update(paths)
    retired = []
    for offset, pairs in sorted(found, key=lambda item: item[0]):
        line = code.count("\n", 0, offset) + 1
        features = [feature for feature, _value in pairs or []]
        values = {feature: string_literal(value) for feature, value in pairs or []}
        identity, test, superseded = values.get("identity"), values.get("test"), values.get("supersededBy")
        if features.count("identity") == 1 and identity and re.fullmatch(r"FR-\d{3}|CL-\d{3}-\d{2}", identity):
            raise ValueError(f"Only a verification case retires: {identity}: {key}")
        invalid = ValueError(f"Invalid retired case: {key}:{line}")
        if pairs is None or features.count("identity") != 1 or identity is None or not re.fullmatch(r"TC-\d{3}-\d{3}", identity):
            raise invalid
        others = sorted(feature for feature in features if feature != "identity")
        if others == ["supersededBy"]:
            # One literal of one or more distinct case identities, separated by `;`, not the case itself.
            names = tuple(name.strip() for name in superseded.split(";")) if superseded is not None else ()
            if not names or not all(re.fullmatch(r"TC-\d{3}-\d{3}", name) for name in names) \
                    or len(set(names)) != len(names) or identity in names:
                raise invalid
            retired.append((identity, None, line, names))
            continue
        if others != ["test"] or test is None or ";" in test or "::" in test:
            raise invalid
        if test not in named.get(owners[offset], set()):
            raise ValueError(f"Retired case outside the detail tests: {identity}: {test}: {key}")
        retired.append((identity, test, line, ()))
    return retired


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


def naming_tests(source: str) -> list[tuple[str, set[str]]]:
    """(test name, case identities) of every test of `source` that names a case: by the
    `Proves:` tag attached to it (as `attached_proves` reads it, shorthand expanded) or, for
    a JavaScript test, by its name. A Rust test is named by its function."""
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
    found = []
    for test, cases in sorted(named.items()):
        if script := JS_TEST_NAME.match(lines[test]):
            name = re.sub(r"\\(.)", r"\1", script[2])
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


def source_proves(text: str) -> set[str]:
    # Fixture-specific and HOW names are not product identities. Numeric product
    # IDs retain the existing strict shape and shorthand-expansion checks.
    text = re.sub(r"\b(?:FR|CL|TC)-[A-Za-z][A-Za-z0-9-]*", "", text)
    return {ref for ref in references(text) if not ref.startswith(("CL-014-", "TC-DOC-"))}


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


def computed_status(states: list[str]) -> str:
    """CL-014-19: implemented when all clauses are, target when all are or there is none,
    partial in every other case."""
    if all(state == "target" for state in states):
        return "target"
    if all(state == "implemented" for state in states):
        return "implemented"
    return "partial"


def canonical_catalog(directory: Path, root: Path, required=BASELINE_IDENTITIES) -> dict[str, dict]:
    files = model_files(directory)
    sources = {key: path.read_text(encoding="utf-8") for key, path in files.items()}
    clean_models = {key: without_comments(source) for key, source in sources.items()}
    packages = {key: file_package(clean) for key, clean in clean_models.items()}
    required_packages = set(REQUIRED_PACKAGES)
    if CONTEXT_FILE in files:
        if packages[CONTEXT_FILE] != CONTEXT_PACKAGE:
            raise ValueError(f"Context file package is not {CONTEXT_PACKAGE}: {CONTEXT_FILE}")
        if identity := IDENTITY_DECLARATION.search(blanked(clean_models[CONTEXT_FILE])):
            raise ValueError(f"Context file declares an identity: {identity[1] or identity[2]}: {CONTEXT_FILE}")
        required_packages.add(CONTEXT_PACKAGE)
    for key, clean in clean_models.items():
        if key != CONTEXT_FILE and re.search(r"\b" + CONTEXT_PACKAGE + r"\b", blanked(clean)):
            raise ValueError(f"Model file names the context package: {CONTEXT_PACKAGE}: {key}")
    keys_of = {}
    for key, package in packages.items():
        if package in required_packages:
            keys_of.setdefault(package, []).append(key)
    if missing := required_packages - keys_of.keys():
        raise ValueError("Canonical model packages missing: " + ", ".join(sorted(missing)))
    for package in sorted(required_packages):
        if len(keys_of[package]) > 1:
            raise ValueError("Duplicate canonical model package: " + package + ": " + ", ".join(sorted(keys_of[package])))
    entries, declared_in, retired, superseding, derivations = {}, {}, {}, {}, []
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
        # A typed declaration is read only as a verification case typed by a definition.
        declarations = [match for match in DECLARATION.finditer(clean)
                        if not match[4] or (match[1] == "verification" and not match[2])]
        read = {match.start() for match in declarations}
        for match in IDENTITY_DECLARATION.finditer(code):
            if match.start() not in read:
                raise ValueError(f"Unreadable canonical declaration: {match[1] or match[2]}: {key}")
        bodies = [(match.end(), match.end() + len(declaration_body(clean, match.end() - 1))) for match in declarations]
        # A function binding: an @ImplementedIn outside the body of every declaration.
        functions = [value for offset, pairs in annotations(clean, code, "ImplementedIn")
                     if not any(start <= offset < end for start, end in bodies)
                     for feature, value in pairs if feature == "module"]
        functions = [string_literal(value) for value in functions]
        for value in functions:
            file_bindings(key, value, root)
        for _offset, pairs in annotations(clean, code, "DetailTests"):
            for feature, value in pairs:
                if feature == "tests":
                    file_bindings(key, string_literal(value), root)
        # The verification definitions of this file by name: what a case typed by one takes.
        definitions = {}
        for match in CASE_DEFINITION.finditer(code):
            name = match[1].strip("'")
            if re.fullmatch(IDENTITY, name):
                continue
            body = declaration_body(clean, match.end() - 1)
            states, bindings, methods, _unread = stated(body, code[match.end():match.end() + len(body)], "verification")
            if bindings:
                raise ValueError(f"Verification definition carries a test binding: {name}: {key}")
            definitions.setdefault(name, []).append((states, methods))
        for match, (start, end) in zip(declarations, bodies):
            kind, identifier = match[1], match[3]
            if identifier in entries:
                raise ValueError("Duplicate canonical identity: " + identifier)
            if kind != ("verification" if identifier.startswith("TC-") else "requirement"):
                raise ValueError("Wrong canonical identity kind: " + identifier)
            body = clean[start:end]
            states, bindings, methods, unread = stated(body, code[start:end], kind)
            # Only a definition of the same file, named without package names and found
            # once, gives its state and method; the case's own statement wins, and a fact
            # the case names in a spelling that is not read is refused, never taken over.
            definition = definitions.get(match[4] or "", [])
            if len(definition) == 1:
                if not states and "state" not in unread:
                    states = definition[0][0]
                if not methods and definition[0][1]:
                    if "method" in unread and states:
                        raise ValueError("Invalid verification/implementation metadata: " + identifier)
                    methods = definition[0][1]
            allowed = {"planned", "partial", "implemented"} if kind == "verification" else {"target", "partial", "implemented"}
            # An FR may state no status: its status is computed from its clauses (CL-014-19).
            unstated = identifier.startswith("FR-") and not states and "state" not in unread
            if not unstated and (len(states) != 1 or states[0] not in allowed):
                raise ValueError("Missing or invalid declared model state: " + identifier)
            refs = re.findall(r"\bverify\s+(?:\w+::)*'([^']+)'\s*;", body)
            if len(bindings) > 1 or len(methods) > 1 or None in bindings or (methods and methods[0] not in {"manual", "automated"}):
                raise ValueError("Invalid verification/implementation metadata: " + identifier)
            delivered = not unstated and states[0] in {"partial", "implemented"}
            if kind == "requirement" and delivered and not bindings:
                # A clause takes its module from the function of its own model file.
                if functions and "binding" in unread:
                    raise ValueError("Invalid verification/implementation metadata: " + identifier)
                if len(functions) > 1:
                    raise ValueError(f"Ambiguous function binding: {identifier}: {key}")
                bindings = list(functions)
            if delivered and (not bindings or not bindings[0].strip()):
                raise ValueError("Delivered declaration lacks implementation/test binding: " + identifier)
            matched = [source_binding(identifier, binding.strip(), root, manual=methods == ["manual"])
                       for binding in (bindings[0].split(";") if bindings else [])]
            unbound = [binding.strip() for binding, bound in zip(bindings[0].split(";"), matched) if not bound] if bindings else []
            if kind == "verification" and unbound:
                raise ValueError(f"No Proves tag or named-test identity for {identifier}: {'; '.join(unbound)}")
            # The effective values, stated or taken over, whatever form states them.
            entries[identifier] = {"kind": kind, "state": states[0] if states else None, "refs": refs,
                                   "bindings": [binding.strip() for binding in bindings[0].split(";")] if bindings else [],
                                   "manual": methods == ["manual"]}
            declared_in[identifier] = key
        derivations.extend(file_derivations(key, clean))
        # Retired cases: after the file's detail tests and declarations are checked.
        for identity, _test, _line, names in file_retirements(key, source):
            retired.setdefault(identity, []).append(key)
            if names:
                superseding[identity] = (names, key)
    for identity in sorted(retired):
        if len(retired[identity]) > 1:
            raise ValueError(f"Duplicate retired case: {identity}: " + ", ".join(sorted(set(retired[identity]))))
    for identity in sorted(retired):
        if identity in entries:
            raise ValueError(f"Retired case declared again: {identity}: {declared_in[identity]}")
    # A superseded retirement names declared cases that are not retired.
    for identity in sorted(superseding):
        names, key = superseding[identity]
        for name in names:
            if name not in entries or name in retired:
                raise ValueError(f"Superseding case missing or retired: {identity}: {name}: {key}")
    # A retired identity counts as present for the baseline; it is not a catalog entry.
    if missing := set(required) - entries.keys() - retired.keys():
        raise ValueError("Missing stable canonical identities: " + ", ".join(sorted(missing)))
    dependencies, case_links, derived = {}, {}, {}
    for source in clean_models.values():
        for owner, target in re.findall(r"\bdependency\s+\w+\s+from\s+(?:\w+::)*'(CL-[^']+)'\s+to\s+(?:\w+::)*'([^']+)'\s*;", source):
            if owner not in entries or target not in entries or not target.startswith(("FR-", "TC-")):
                raise ValueError("Invalid canonical clause dependency: " + owner + " -> " + target)
            (dependencies if target.startswith("FR-") else case_links).setdefault(owner, set()).add(target)
    # A clause derived from its FR is owned by it; no reciprocal dependency is written for it.
    for original, clauses in derivations:
        for clause in clauses:
            if clause not in entries or original not in entries or not clause.startswith("CL-") or not original.startswith("FR-"):
                raise ValueError("Invalid canonical clause dependency: " + clause + " -> " + original)
            derived.setdefault(clause, set()).add(original)
    verified = set()
    for identifier, entry in entries.items():
        if identifier.startswith("CL-") and identifier not in dependencies and identifier not in derived:
            raise ValueError("Canonical clause lacks requirement ownership: " + identifier)
        if identifier.startswith("CL-") and identifier in dependencies and identifier not in case_links:
            raise ValueError("Canonical clause lacks a declared verification case: " + identifier)
        if entry["kind"] == "verification":
            if not entry["refs"] or any(ref not in entries or ref.startswith("TC-") for ref in entry["refs"]):
                raise ValueError("Undefined or absent verification target: " + identifier)
            verified.update(entry["refs"])
            # Reciprocity holds for the clauses owned by a dependency only.
            actual_clauses = {ref for ref in entry["refs"] if ref.startswith("CL-") and ref in dependencies}
            declared_clauses = {clause for clause, cases in case_links.items() if identifier in cases and clause in dependencies}
            if actual_clauses != declared_clauses:
                raise ValueError("Nonreciprocal canonical verification links: " + identifier)
    unverified = {i for i in entries if i.startswith("CL-")} - verified
    if unverified:
        raise ValueError("Canonical clauses lack verification links: " + ", ".join(sorted(unverified)))
    # CL-014-19: each FR's status, computed from the clauses it owns by either form. The
    # entry keeps the stated status (None when there is none) beside the computed one.
    for identifier, entry in entries.items():
        if identifier.startswith("FR-"):
            clauses = sorted(clause for clause in entries if identifier in dependencies.get(clause, set()) | derived.get(clause, set()))
            entry["stated"] = entry["state"]
            entry["clauses"] = clauses
            entry["status"] = computed_status([entries[clause]["state"] for clause in clauses])
            if entry["state"] is None:
                entry["state"] = entry["status"]
    for directory_name in SOURCE_BINDING_ROOTS:
        for path in sorted((root / directory_name).rglob("*")):
            if not path.is_file() or path.suffix not in {".rs", ".js", ".cjs"}:
                continue
            for tag in re.findall(r"(?m)^\s*(?://|#)\s*Proves:([^\r\n]+)", path.read_text(encoding="utf-8")):
                if unknown := source_proves(tag) - entries.keys():
                    raise ValueError("Source Proves tag names undefined model identities: " + path.relative_to(root).as_posix() + ": " + ", ".join(sorted(unknown)))
    return entries


def status_lines(entries: dict[str, dict]) -> list[str]:
    """The lines of `status` (CL-014-19): one per FR in identity order, then the summary."""
    lines, counts = [], Counter()
    for identifier in sorted(identifier for identifier in entries if identifier.startswith("FR-")):
        entry = entries[identifier]
        states = Counter(entries[clause]["state"] for clause in entry["clauses"])
        line = (f"{identifier} {entry['status']}: {len(entry['clauses'])} clauses, {states['implemented']} implemented, "
                f"{states['partial']} partial, {states['target']} target")
        if entry["stated"] and entry["stated"] != entry["status"]:
            line += "; stated " + entry["stated"]
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
# The fixed rules of CL-014-06 find their parts by these simple definition names, in any
# package, and the station's direct parts by usage name; the oracle file cannot change them.
STATION_TYPE = "StationProcess"
AUTHORITY_TYPE = "RadioAuthority"
STATION_PARTS = (("profile", "PersistedProfile"), ("audioAdapter", "AudioDeviceAdapter"),
                 ("catAdapter", "RustRadioDriver"))
EXCLUSIVE_PARTS = ("audioAdapter", "catAdapter")
ORACLE_ABOUT = "TC-DOC-005 oracle, written by python tools/sysml.py oracle from the resolved inventory"


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


def of_type(values: list, type_name: str) -> bool:
    """A PART row's definition, or a definition it specializes, has the simple name
    `type_name`, in any package."""
    return len(values) > 4 and any(kind.rsplit("::", 1)[-1] == type_name for kind in values[4].split(",") if kind)


def fixed_rules(records: dict, root=None) -> None:
    """The fixed rules of CL-014-06, whatever the oracle file lists: the one deployment
    (and, given `root`, the oracle's), no view-made part or connection, one variable
    station population, its direct profile and adapters, no other adapter and one
    authority. Parts are found by type name, never by path or package."""
    roots = records.get("ROOTPART", [])
    if len(roots) != 1 or root is not None and roots != [[root]]:
        raise ValueError("Architecture integrity: expected one physical deployment")
    if records.get("VIEWSEMANTIC"):
        raise ValueError("Architecture integrity: views may expose, not create runtime parts/connections")
    parts = {row[0]: row[1:] for row in records.get("PART", [])}
    stations = [path for path, values in parts.items() if of_type(values, STATION_TYPE)]
    if len(stations) != 1 or parts[stations[0]][1] != "0:-1":
        raise ValueError("Architecture integrity: station population must remain variable")
    station = stations[0]
    for name, type_name in STATION_PARTS:
        values = parts.get(station + "." + name, [])
        if len(values) < 3 or not of_type(values, type_name) or values[1] != "1:1" or values[2] != "false":
            raise ValueError("Architecture integrity: exactly one direct " + name + " per station")
    for name, type_name in STATION_PARTS:
        if name in EXCLUSIVE_PARTS:
            if {path for path, values in parts.items() if of_type(values, type_name)} != {station + "." + name}:
                raise ValueError("Architecture integrity: duplicate or detached " + name)
    if len([path for path, values in parts.items() if of_type(values, AUTHORITY_TYPE)]) != 1:
        raise ValueError("Architecture integrity: shared radio requires one effective authority")


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


def architecture_integrity(output: str) -> dict[str, int]:
    """TC-DOC-005 (CL-014-03, CL-014-06): the deployment against the oracle file.

    Input is the pinned Pilot's resolved semantic inventory, not SysML source or a
    viewer graph. The oracle is the file `ORACLE`, which only `oracle` writes; the
    inventory and the file must agree exactly. The fixed rules hold whatever the file
    lists. Only the first difference is reported.
    """
    oracle = architecture_oracle(ORACLE)
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
    """`oracle` (CL-014-06): the Pilot validation and the fixed rules on the working tree's
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


# ---- Target structure checks (CL-014-18, TC-DOC-016) ----

# What is not yet in target form: `files` (model file keys, exempt from every rule) and
# `elements` (qualified name -> owning function; exempt with their members). Only `check`
# reads it; a rewrite takes its entries off.
PENDING = Path(__file__).with_name("sysml") / "pending-structure.json"
STATION_FILE = "Station.sysml"
STATION_LINK = "interfaces/internal/StationLink.sysml"
STATION_COMMANDS = "interfaces/internal/StationCommands.sysml"
MCP_INTERFACE = "interfaces/external/Mcp.sysml"
OPERATING_CHAIN = "interfaces/internal/OperatingChain.sysml"
OPERATOR_INTERACTION = "interfaces/external/OperatorInteraction.sysml"
# The outside interfaces the browser client may have, each with the usage directly in the
# root its port connects to. An issue that needs a further outside connection adds it here.
BROWSER_OUTSIDE = {OPERATOR_INTERACTION: "operator"}
CONTROL_SUFFIX = "Control"
CHAIN = ("ranking", "auto", "qso", "transmit")
OUTSIDE_MEMBERS = {"port", "attribute", "metadata"}
UNLISTABLE = (CONTEXT_FILE, "interfaces/internal/", "interfaces/external/")
FR_STATED = ((re.compile(r"\bcoverage\b"), "coverage"), (re.compile(r"\bimplementation\b"), "implementation"),
             (re.compile(r"(?:@|\bmetadata\b[^;{}]*?:)\s*(?:\w+::)*(Status|ImplementedIn|TestedBy|DetailTests)\b(?!::)"), None))
SATISFY_FR = re.compile(r"satisfy\s+(?:requirement\s+)?(?:(?:\w+|'[^'\r\n]*')::)*'FR-\d{3}'\s+by\b")
STATION_ALLOWED = re.compile(r"(?:part\s+def|part|ref\s+part|connection(?!\s+def\b)|connect|interface(?!\s+def\b)"
                             r"|flow(?!\s+def\b)|binding|bind|import|doc|comment)\b")


def pending_list(path: Path, keys) -> tuple[set, dict]:
    """The pending list at `path` as (file keys, {element name: owner}); refused whole
    when it is unreadable, not of its form, lists an entry twice, a key that is no model
    file or that cannot be listed, or an element with an empty owner."""
    def refused(what: str) -> ValueError:
        return ValueError("Pending structure list: " + what)

    def unique(pairs):
        names = [name for name, _value in pairs]
        if twice := sorted({name for name in names if names.count(name) > 1}):
            raise refused("listed twice: " + twice[0])
        return dict(pairs)

    try:
        data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        raise refused(f"unavailable or not JSON: {path}") from None
    if not isinstance(data, dict) or set(data) != {"files", "elements"} or not isinstance(data["files"], list) \
            or not all(isinstance(key, str) for key in data["files"]) or not isinstance(data["elements"], dict) \
            or not all(isinstance(owner, str) for owner in data["elements"].values()):
        raise refused("not a map of files (a list of keys) and elements (names to owners)")
    files = data["files"]
    if twice := sorted({key for key in files if files.count(key) > 1}):
        raise refused("listed twice: " + twice[0])
    for key in sorted(files):
        if key == CONTEXT_FILE or key.startswith(UNLISTABLE[1:]):
            raise refused("file cannot be listed: " + key)
        if key not in keys:
            raise refused("no model file: " + key)
    for name, owner in sorted(data["elements"].items()):
        if not owner.strip():
            raise refused("element without owner: " + name)
    return set(files), dict(data["elements"])


def model_elements(records: dict, keys: list[str]) -> dict:
    """The named elements of the inventory by qualified name: (metaclass, file key, first
    line, last line, model features of a definition or None); the first of a name."""
    elements = {}
    for name, kind, index, start, end, features in records.get("ELEM", []):
        position = int(index)
        elements.setdefault(name, (kind, keys[position] if 0 <= position < len(keys) else "", int(start), int(end),
                                   int(features) if features else None))
    return elements


def pending_elements(listed: dict, records: dict, keys: list[str]) -> dict:
    """Each listed element name with the place of its element; a name that resolves to no
    element of the model files refuses the list."""
    elements = model_elements(records, keys) if listed else {}
    for name in sorted(listed):
        if name not in elements or not elements[name][1]:
            raise ValueError("Pending structure list: no model element: " + name)
    return {name: elements[name] for name in listed}


def part_folder(key: str):
    """The part folder of a model file: a folder directly under `backend/` other than
    `operating/`, a folder directly under `backend/operating/`, or `frontend/`."""
    parts = key.split("/")
    if parts[0] == "backend" and len(parts) >= 3:
        if parts[1] == "operating":
            return "/".join(parts[:3]) if len(parts) >= 4 else None
        return "/".join(parts[:2])
    if parts[0] == "frontend" and len(parts) >= 2:
        return "frontend"
    return None


def control_file(key: str) -> bool:
    return re.fullmatch(r"interfaces/internal/[^/]*" + CONTROL_SUFFIX + r"\.sysml", key) is not None


def may_name(key: str, target: str) -> bool:
    """Rule 1: whether the file `key` may name the package of the file `target`."""
    if target == key or target == "Requirements.sysml" or target.startswith("shared/"):
        return True
    if (folder := part_folder(key)) is not None:
        return target.startswith("interfaces/") or part_folder(target) == folder
    if not target.startswith("interfaces/"):
        return False
    if key.startswith("interfaces/external/") and target.startswith("interfaces/internal/"):
        return key == MCP_INTERFACE and control_file(target)
    return not (control_file(key) and target in (STATION_LINK, STATION_COMMANDS, MCP_INTERFACE, OPERATING_CHAIN))


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


def station_faults(key: str, code: str) -> list[tuple]:
    """Rule 2: the statements of `Station.sysml` at package level and in its part
    definitions other than composition, connections, `satisfy` of an FR and imports."""
    faults = []

    def judge(start: int, end: int, top: bool):
        position = start
        while begin := re.compile(r"\S").search(code, position, end):
            begin = begin.start()
            stop = statement_end(code, begin, end)
            head = re.sub(r"^(?:(?:private|public|protected)\s+)?(?:(?:abstract|variation)\s+)*", "", code[begin:stop])
            opening = code.find("{", begin, stop)
            line = code.count("\n", 0, begin) + 1
            if top and re.match(r"package\b", head):
                if opening >= 0:
                    judge(opening + 1, stop - 1, False)
            elif re.match(r"part\s+def\b", head):
                if opening >= 0:
                    judge(opening + 1, stop - 1, False)
            elif re.match(r"satisfy\b", head):
                if not SATISFY_FR.match(head):
                    faults.append((2, key, line, "satisfy of no FR"))
            elif not STATION_ALLOWED.match(head):
                word = re.match(r"@\s*(?:\w+::)*\w+|#?\w+(?:\s+def\b)?|\S", head)[0]
                faults.append((2, key, line, re.sub(r"\s+", " ", word) + " not allowed"))
            position = stop

    judge(0, len(code), True)
    return faults


def file_faults(sources: dict[str, str]) -> list[tuple]:
    """Rules 1, 2, 8, 9 and 10 on the model text, as (rule, key, line, what)."""
    codes = {key: structure_code(source) for key, source in sources.items()}
    package_files = {}
    for key, code in codes.items():
        for package in top_packages(code):
            package_files.setdefault(package, set()).add(key)
    faults = []
    for key, source in sources.items():
        code = codes[key]
        unquoted = re.sub(r"'[^'\r\n]*'", lambda match: " " * len(match[0]), code)

        def at(offset: int) -> int:
            return code.count("\n", 0, offset) + 1

        # Rule 1: the packages a file names by import or by qualified name in code.
        if part_folder(key) is not None or key.startswith("interfaces/"):
            named = {match.start(1): match[1] for match in re.finditer(r"\bimport\s+(?:all\s+)?(\w+|'[^'\r\n]*')", code)}
            named.update((match.start(), match[0].split("::", 1)[0]) for match in QNAME.finditer(code))
            for offset, package in sorted(named.items()):
                targets = package_files.get(package, set())
                if targets and not any(may_name(key, target) for target in targets):
                    faults.append((1, key, at(offset), "names package " + package))
        if key == STATION_FILE:
            faults += station_faults(key, code)
        # Rule 8: an FR states no status, no binding and no issue reference.
        text = blanked(source, strings=False)
        for match in DECLARATION.finditer(text):
            if match[1] != "requirement" or not match[3].startswith("FR-"):
                continue
            start = match.end()
            end = start + len(declaration_body(text, start - 1))
            for pattern, what in FR_STATED:
                for found in pattern.finditer(code, start, end):
                    faults.append((8, key, at(found.start()), f"{match[3]} states {what or '@' + found[1]}"))
            for found in re.finditer(r"#\d+", source[start:end]):
                faults.append((8, key, at(start + found.start()), f"{match[3]} names issue {found[0]}"))
        # Rule 9: no dependency.
        for found in re.finditer(r"\bdependency\b", unquoted):
            faults.append((9, key, at(found.start()), "dependency declared"))
        # Rule 10: every requirement, definition or usage, declares a subject.
        for found in re.finditer(r"\brequirement\b(?:\s+def\b)?", unquoted):
            if re.search(r"(?:\bsatisfy|\bverify|\bframe|\brequire|\bassume|#|::|\.)\s*$", unquoted[:found.start()]):
                continue
            stop = re.compile(r"[;{]").search(code, found.end())
            name = (code[found.end():stop.start() if stop else len(code)].split() or ["?"])[0]
            if stop and stop[0] == "{":
                flat, depth = [], 0
                for character in declaration_body(code, stop.start()):
                    depth += character == "{"
                    flat.append(character if depth == 0 else " ")
                    depth -= character == "}"
                if re.search(r"\bsubject\b", "".join(flat)):
                    continue
            faults.append((10, key, at(found.start()), f"requirement {name} declares no subject"))
    return faults


def interface_faults(records: dict, elements: dict) -> list[tuple]:
    """Rule 3 on the interface definitions: one under `interfaces/` has items; every item
    is typed by a definition with a model feature. As (rule, key, line, what, names)."""
    items = {}
    for interface, _end, item, _direction, types in records.get("IITEM", []):
        items.setdefault(interface, []).append((item, [name for name in types.split(",") if name]))
    faults = []
    for name, (kind, key, line, _end, _features) in elements.items():
        if kind != "InterfaceDefinition" or not key:
            continue
        simple = name.rsplit("::", 1)[-1]
        if key.startswith("interfaces/") and not items.get(name):
            faults.append((3, key, line, f"interface {simple} without items", (name,)))
        for item, types in items.get(name, []):
            if not types:
                faults.append((3, key, line, f"interface {simple} item {item} untyped", (name,)))
            for typed in types:
                if not (elements.get(typed) or (None,) * 5)[4]:
                    faults.append((3, key, line, f"interface {simple} item {item} typed by featureless {typed}", (name, typed)))
    return faults


def deployment_faults(records: dict, keys: list[str], elements: dict) -> list[tuple]:
    """Rules 3 (connections), 4, 5, 6 and 7 on the resolved deployment, as (rule, path,
    what, places), each place a (file key, qualified name) that exempts the fault."""
    def key_of(index: str) -> str:
        position = int(index)
        return keys[position] if 0 <= position < len(keys) else ""

    def within(path: str, base: str) -> bool:
        return path == base or path.startswith(base + ".")

    root = records["ROOTPART"][0][0].rsplit("::", 1)[-1]
    parts = {row[0]: row[1:] for row in records.get("PART", [])}
    refs = {row[0]: row[1:] for row in records.get("REF", [])}
    ports = {row[0]: row[1] for row in records.get("PORT", [])}
    where = {path: (key_of(index), name) for path, name, index in records.get("WHERE", [])}
    resolved = end_resolver(root, refs)
    connections = []
    for owner, _name, ends, types, index, anchor in records.get("CONN", []):
        written = ends.split("|")
        if len(written) < 2:
            continue
        connections.append({"label": f"{owner} {written[0]} -> {written[1]}", "first": resolved(owner, written[0]),
                            "second": resolved(owner, written[1]), "types": [name for name in types.split(",") if name],
                            "places": [(key_of(index), anchor)]})

    def kind(name: str) -> str:
        return (elements.get(name) or ("",))[0]

    def file(name: str) -> str:
        return (elements.get(name) or ("", ""))[1]

    def connected(path: str, base: str) -> bool:
        return any(within(connection[a], path) and within(connection[b], base) for connection in connections
                   for a, b in (("first", "second"), ("second", "first")))

    faults = []
    stations = sorted(path for path, values in parts.items() if of_type(values, STATION_TYPE))
    # Rule 3: every connection is typed by an interface definition of `interfaces/`.
    for connection in connections:
        interfaces = [name for name in connection["types"] if kind(name) == "InterfaceDefinition"]
        if not connection["types"]:
            what = "untyped connection"
        elif not interfaces:
            what = "connection typed by no interface"
        elif not any(file(name).startswith("interfaces/") for name in interfaces):
            what = "connection typed by an interface outside interfaces/"
        else:
            continue
        faults.append((3, connection["label"], what, connection["places"]))
    # Rule 4: the outside parts, directly in the root other than the station.
    station = root + ".station"
    members = {}
    for path, side, category, name in records.get("MEMBER", []):
        members.setdefault(path, []).append((side, category, name))
    for path, types in records.get("OUTSIDE", []):
        if path == station:
            continue
        types = [name for name in types.split(",") if name]
        places = [where.get(path, ("", ""))] + [(file(name), name) for name in types]
        for side, category, name in members.get(path, []):
            if category not in OUTSIDE_MEMBERS:
                faults.append((4, path, f"outside part with {category} {name}" + (" in its type" if side == "type" else ""), places))
        usage = where.get(path, ("", ""))[1]
        for anchor, index, subject_types, subsetted in records.get("SUBJECT", []):
            if set(subject_types.split(",")) & set(types) or usage and usage in subsetted.split(","):
                faults.append((4, path, f"subject of requirement {anchor}", places + [(key_of(index), anchor)]))
        own = [port for port in ports if port.startswith(path + ".") and "." not in port[len(path) + 1:]]
        if not any(connected(port, station) for port in own):
            faults.append((4, path, "outside part joined to no function", places))
    # Rule 5: a control interface has the station service at its commanding end.
    for process in stations:
        if process + ".station" not in parts:
            faults.append((5, process + ".station", "missing role part", []))
    for connection in connections:
        controls = [name for name in connection["types"]
                    if kind(name) == "InterfaceDefinition" and name.rsplit("::", 1)[-1].endswith(CONTROL_SUFFIX)]
        if controls and not any(within(connection["first"], process + ".station") for process in stations):
            faults.append((5, connection["label"], f"control interface {controls[0].rsplit('::', 1)[-1]} not commanded "
                                                   "by the station service", connection["places"]))
    # Rule 6: the browser client.
    frontend = station + ".frontend"
    browsers = frontend + ".browsers"
    webs = [process + ".web" for process in stations]
    missing = [path for path in (station, frontend, browsers, root + ".operator", *webs) if path not in parts]
    faults += [(6, path, "missing role part", []) for path in missing]
    faults += [(6, key, "missing role file", []) for key in (STATION_LINK, OPERATOR_INTERACTION) if key not in keys]
    if not missing and STATION_LINK in keys and OPERATOR_INTERACTION in keys:
        own = sorted(port for port in ports if port.startswith(browsers + ".") and "." not in port[len(browsers) + 1:])
        typed = {port: file(ports[port].removeprefix("~")) for port in own}
        internal = [port for port in own if typed[port].startswith("interfaces/internal/")]
        if len(internal) != 1:
            faults.append((6, browsers, f"browser client with {len(internal)} ports typed by internal interfaces",
                           [where.get(browsers, ("", ""))]))
        allowed = {}
        for port in internal:
            if typed[port] != STATION_LINK:
                faults.append((6, port, "internal port not typed by StationLink", [where.get(port, ("", ""))]))
            elif not any(connected(port, web) for web in webs):
                faults.append((6, port, "StationLink port not connected to web", [where.get(port, ("", ""))]))
            else:
                allowed[port] = webs
        counts = Counter()
        for port in own:
            if port in internal:
                continue
            if typed[port] not in BROWSER_OUTSIDE:
                faults.append((6, port, "port of an interface the browser client may not have", [where.get(port, ("", ""))]))
                continue
            counts[typed[port]] += 1
            peer = root + "." + BROWSER_OUTSIDE[typed[port]]
            if not connected(port, peer):
                faults.append((6, port, "port not connected to " + BROWSER_OUTSIDE[typed[port]], [where.get(port, ("", ""))]))
            allowed[port] = [peer]
        for key, count in sorted(counts.items()):
            if count > 1:
                faults.append((6, browsers, f"browser client with {count} ports typed by {key}", [where.get(browsers, ("", ""))]))
        for connection in connections:
            for inside, other in (("first", "second"), ("second", "first")):
                if within(connection[inside], frontend) and not within(connection[other], frontend) \
                        and not any(within(connection[inside], port) and any(within(connection[other], peer) for peer in peers)
                                    for port, peers in allowed.items()):
                    faults.append((6, connection["label"], "frontend connection ends at " + connection[other],
                                   connection["places"]))
    # Rule 7: the operating chain commands only downward, between neighbours.
    order = set(zip(CHAIN, CHAIN[1:]))
    for process in stations:
        faults += [(7, process + "." + role, "missing role part", []) for role in CHAIN if process + "." + role not in parts]

        def role(path: str):
            return next((name for name in CHAIN if within(path, process + "." + name)), None)

        for connection in connections:
            first, second = role(connection["first"]), role(connection["second"])
            if first and second and first != second and (first, second) not in order:
                faults.append((7, connection["label"], f"{first} to {second} outside the operating chain", connection["places"]))
    return faults


def structure_lines(models: Path, records: dict, keys: list[str], pending: tuple[set, dict], named: dict) -> list[str]:
    """CL-014-18: the ten rules on every model file and element not on the pending list,
    the deployment rules once `Station.sysml` is not listed. Returns the passed line;
    prints every fault, sorted by rule, key and line, and raises when there is one."""
    listed, listed_elements = pending
    files = model_files(models)
    sources = {key: files[key].read_text(encoding="utf-8") for key in keys if key in files}
    elements = model_elements(records, keys)
    deployment = STATION_FILE not in listed

    def covered(name: str) -> bool:
        return any(name == listed_name or name.startswith(listed_name + "::") for listed_name in named)

    def exempt_line(key: str, line: int) -> bool:
        return key in listed or any(place[1] == key and place[2] <= line <= place[3] for place in named.values())

    found = set()
    for rule, key, line, what in file_faults(sources):
        if not exempt_line(key, line):
            found.add((rule, key, line, f"Structure rule {rule}: {what}: {key}:{line}"))
    for rule, key, line, what, names in interface_faults(records, elements):
        if not exempt_line(key, line) and not any(covered(name) for name in names):
            found.add((rule, key, line, f"Structure rule {rule}: {what}: {key}:{line}"))
    if deployment and records.get("ROOTPART"):
        for rule, path, what, places in deployment_faults(records, keys, elements):
            if not any(key in listed or covered(name) for key, name in places if key or name):
                found.add((rule, path, 0, f"Structure rule {rule}: {what}: {path}"))
    if found:
        for *_order, line in sorted(found):
            print(line)
        raise ValueError(f"{len(found)} structure faults")
    return [f"Structure checks passed: {len(keys) - len(listed)} files in target form, {len(listed)} files and "
            f"{len(listed_elements)} elements pending; deployment rules {'on' if deployment else 'off'}"]


def validate(paths: list[Path], cache: Path, inventory: bool = False) -> subprocess.CompletedProcess:
    java, jar, library = tool_paths(cache)
    if not paths or any(not path.is_file() for path in paths):
        raise ValueError("Semantic validation requires existing model files")
    # Cap the heap: the JVM default (a quarter of RAM) let parallel checks take
    # gigabytes next to the real-time station; 512 MB with the serial collector passes.
    result = subprocess.run([str(java), "-Xmx512m", "-XX:+UseSerialGC", "-classpath", str(jar), str(ROOT / "tools/sysml/Validate.java"), str(library), *(["--inventory"] if inventory else []), *map(str, paths)], text=True, capture_output=True, timeout=120)
    if result.returncode == 0 and "OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed." not in result.stdout:
        raise ValueError("Validator returned no semantic completion marker")
    return result


# ---- equivalence and identities (CL-014-17, TC-DOC-015) ----

# A qualified name as written in text: two or more segments, each a word or a quoted name.
QNAME = re.compile(r"(?<![\w':])(?:[A-Za-z_]\w*|'[^'\r\n]+')(?:::(?:[A-Za-z_]\w*|'[^'\r\n]+'))+")
QNAME_SEGMENT = re.compile(r"(?:[A-Za-z_]\w*|'[^'\r\n]+')(?:::|$)")
MODEL_PATH = re.compile(r"docs/sysml/[\w./-]*[\w/]")
LINK = re.compile(r"\]\(\s*<?([^)\s>]+)>?\s*\)")
# The tracked files at <head> whose model citations `equivalence` checks.
CITATION_ROOTS = ("server", "client", "tests", "tools", "fixtures", "docs/harness", ".harness", "README.md")
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
    process = subprocess.Popen(["git", "-C", str(ROOT), "archive", "--format=tar", commit, *paths],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    try:
        with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
            for member in archive:
                if member.isfile() or member.isdir():
                    archive.extract(member, destination, filter="data")
    except tarfile.TarError:
        pass
    error = process.stderr.read().decode("utf-8", "replace").strip()
    if process.wait():
        raise Unreadable(f"git archive {commit} {' '.join(paths)}: {error}")


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
            for number, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
                for match in QNAME.finditer(line):
                    if match[0].split("::", 1)[0] in tops:
                        found.add((path, number, "name", match[0]))
                for match in MODEL_PATH.finditer(line):
                    found.add((path, number, "path", match[0].rstrip(".")))
        return sorted(found)


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


def compare(base: Side, head: Side, citations: list) -> tuple[int, list[str]]:
    """P2 to P6 of CL-014-17 for two exported sides: (exit code, lines)."""
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
        content same-named elements are paired by (D2)."""
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
    # Among equal candidates (D2) each name is paired in passes, so that no element takes a
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
    pairs = Counter()
    for key_b, key_h in sorted(pair.items()):
        b, h = entries_b[key_b], entries_h[key_h]
        facts_b, facts_h = strict_b.facts(b["facts"], b["file"]), strict_h.facts(h["facts"], h["file"])
        if facts_b != facts_h:
            index = next((i for i, (x, y) in enumerate(zip(facts_b, facts_h)) if x != y), min(len(facts_b), len(facts_h)))
            fact = facts_b[index] if index < len(facts_b) else facts_h[index]
            differences.append(f"changed {b['rel']} {label(fact, facts_b)} {b['file']} -> {h['file']}")
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
    # P6: citations outside the model, read at <head>.
    for path, line, kind, citation in citations:
        if kind == "name":
            on_b = base.export["resolved"].get(citation) is not None
            on_h = head.export["resolved"].get(citation) is not None
        else:
            on_b, on_h = (base.root / citation).exists(), (head.root / citation).exists()
        if on_b and not on_h:
            differences.append(f"stale-by-change {path}:{line} {citation}")
        elif not on_b and not on_h:
            info.append(f"unresolved {path}:{line} {citation}")
    lines = differences + moves + [f"pair {files[0]} -> {files[1]}: {count}" for files, count in sorted(pairs.items())] + info
    lines.append(f"{len(differences)} differences; {len(pair)} entries paired, {len(moves)} moved"
                 if differences else f"equivalent: {len(pair)} entries paired, {len(moves)} moved")
    return (1 if differences else 0), lines


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
        with ThreadPoolExecutor(max_workers=EXPORT_WORKERS) as pool:
            exports = {id(side): pool.submit(run_export, side, names, cache, folder) for side in sides.values()}
            for side in sides.values():
                side.export = exports[id(side)].result()
        return [compare(base, head, found) for (base, head), found in zip(resolved, citations)], len(sides)


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


def identity_side(directory: Path) -> tuple[dict, dict]:
    """P7: (identity -> (text, file, package), retired identity -> `test <path>` or
    `superseded by <TC>, <TC>`) of one side, read from the declarations without validating
    the tree."""
    files = model_files(directory) if directory.is_dir() else {}
    sources = {key: path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n") for key, path in files.items()}
    codes = {key: blanked(source, strings=False) for key, source in sources.items()}
    tops = set().union(*(top_packages(blanked(source)) for source in sources.values())) if sources else set()
    package_of = {key: file_package(blanked(source)) for key, source in sources.items()}

    def normal(text: str, key: str) -> str:
        text = resolve_links(text, key, package_of)
        return re.sub(r"(?<![\w:'])(\w+)::", lambda match: "" if match[1] in tops else match[0], text)

    entries, dependencies, retired = {}, {}, {}
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
        for identity, test, _line, names in file_retirements(key, sources[key]):
            retired[identity] = "superseded by " + ", ".join(names) if names else "test " + test
    texts = {identity: (text + "\n" + "\n".join(sorted(dependencies.get(identity, []))), key, package)
             for identity, (text, key, package) in entries.items()}
    return texts, retired


STATUSES = ("unchanged", "moved", "changed", "added", "retired", "removed")


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
    (old, _retired_old), (new, retired) = sides
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
        elif identity in retired:
            status, suffix = "retired", " " + retired[identity]
        else:
            status = "removed"
        counts[status] += 1
        lines.append(f"{identity} {status} {before[1] if before else '-'} -> {after[1] if after else '-'}{suffix}")
    lines.append(f"{len(lines)} identities: " + ", ".join(f"{counts[status]} {status}" for status in STATUSES))
    return 0, lines


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=Path, default=Path.home() / ".cache/wsjtx-rust/sysml-tools")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("setup", help="Download and verify pinned portable tools; no global installation")
    commands.add_parser("fingerprints", help="Print canonical model fingerprints for review; never updates models")
    commands.add_parser("check", help="Check canonical SysML authority and run full semantic validation")
    commands.add_parser("traces", help="Check canonical source/model bindings only; no Pilot or behavior execution")
    listing = commands.add_parser("markers", help="List the ModelNotes markers of the model by file key and line; checks and writes nothing")
    listing.add_argument("kinds", nargs="*", metavar="Kind")
    commands.add_parser("retired", help="Check the catalog as fingerprints does, then list the retired cases by identity; writes nothing")
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
        if args.command == "traces":
            authority(MODELS, FSD)
            entries = canonical_catalog(MODELS, ROOT)
            binding_agreement(entries, ROOT)
            print(f"Canonical source/model trace checks passed: {len(entries)} identities; no semantic validation or behavior execution.")
            return 0
        if args.command == "markers":
            authority(MODELS, FSD)
            print("\n".join(markers(MODELS, args.kinds)))
            return 0
        if args.command == "retired":
            authority(MODELS, FSD)
            canonical_catalog(MODELS, ROOT)
            lines = sorted(f"{identity}: {'superseded by ' + ', '.join(names) if names else test}: {key}:{line}"
                           for key, path in model_files(MODELS).items()
                           for identity, test, line, names in file_retirements(key, path.read_text(encoding="utf-8")))
            print("\n".join(lines + [f"{len(lines)} retired cases"]))
            return 0
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
        if args.command == "check":
            authority(MODELS, FSD)
            entries = canonical_catalog(MODELS, ROOT)
            binding_agreement(entries, ROOT)
            entry = "Requirements.sysml"
            files = model_files(MODELS)
            keys = [entry, *(key for key in files if key != entry)]
            paths = [MODELS / entry, *(path for key, path in files.items() if key != entry)]
            # The pending list is refused whole before any passed line (CL-014-18).
            pending = pending_list(PENDING, set(files))
        else:
            paths = args.files
        result = validate(paths, args.cache_dir, inventory=args.command == "check")
        if args.command == "check":
            if result.returncode == 0:
                named = pending_elements(pending[1], inventory_records(result.stdout) if pending[1] else {}, keys)
            print(f"Canonical SysML catalog/trace checks passed: {len(entries)} identities; behavioral correspondence remains independently reviewed.")
        for line in result.stdout.splitlines():
            if not line.startswith(("Reading ", "AST\t")):
                print(line)
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
        if result.returncode == 0 and args.command == "check":
            counts = architecture_integrity(result.stdout)
            print("Architecture integrity passed: " + ", ".join(f"{count} {kind}" for kind, count in counts.items()) + "; runtime behavior not proved.")
            records = inventory_records(result.stdout) if "AST\t" in result.stdout else {}
            print("\n".join(structure_lines(MODELS, records, keys, pending, named)))
        return result.returncode
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"SysML check failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
