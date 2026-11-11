"""Canonical-authority SysML checks and real OMG Pilot validation.

traces checks catalog and source/model bindings only. check additionally calls the
pinned Java parser/name resolver/semantic validator. markers lists the ModelNotes markers
and checks nothing. None executes modeled behavior.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import urllib.request
import urllib.parse
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FSD = ROOT / "docs/WSTX Rust FSD.md"
MODELS = ROOT / "docs/sysml"
TOOLCHAIN = Path(__file__).with_name("sysml") / "toolchain.json"
ID = re.compile(r"\b(?:FR-\d{3}|CL-\d{3}-\d{2}|TC-(?:\d{3}|DOC)-\d{3})\b")
CANONICAL_MARKER = "// Canonical authority: SysML"
SOURCE_BINDING_ROOTS = ("client", "server", "tests")
# Each required package is the package of exactly one model file, whatever the file's
# name and folder. A change that renames or dissolves one changes this list with it.
REQUIRED_PACKAGES = {
    "WstxRequirements", "WstxArchitecture", "WstxProfiles",
    "WstxRecordingReceive", "WstxOfflineDecode", "WstxRadioIO",
    "WstxOperatingLayout", "WstxOperatingReceive", "WstxStationProtocol", "WstxProductScope",
}
# The required package whose model file is the text ProductScope references are looked up in.
SCOPE_PACKAGE = "WstxProductScope"
# Packages that need no ProductScope reference, by package name (not file name).
LIBRARY_PACKAGES = {"ModelNotes", "ModelBindings"}
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
    if not identifier.startswith("TC-") or manual:
        return True
    source = resolved.read_text(encoding="utf-8")
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


def scope_reference(package: str, scope: str) -> bool:
    """Whether comment-free ProductScope text refers to `package`: a qualified name
    `Package::...`, `import Package;` or `alias <name> for Package;`."""
    name = re.escape(package)
    return bool(re.search(r"\b" + name + r"::|\bimport\s+" + name + r"\s*;|\balias\s+\w+\s+for\s+" + name + r"\s*;", scope))


def canonical_catalog(directory: Path, root: Path, required=BASELINE_IDENTITIES) -> dict[str, dict]:
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
    entries = {}
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
            if len(states) != 1 or states[0] not in allowed:
                raise ValueError("Missing or invalid declared model state: " + identifier)
            refs = re.findall(r"\bverify\s+(?:\w+::)*'([^']+)'\s*;", body)
            if len(bindings) > 1 or len(methods) > 1 or None in bindings or (methods and methods[0] not in {"manual", "automated"}):
                raise ValueError("Invalid verification/implementation metadata: " + identifier)
            delivered = states[0] in {"partial", "implemented"}
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
            entries[identifier] = {"kind": kind, "state": states[0], "refs": refs,
                                   "bindings": [binding.strip() for binding in bindings[0].split(";")] if bindings else [],
                                   "manual": methods == ["manual"]}
    if missing := set(required) - entries.keys():
        raise ValueError("Missing stable canonical identities: " + ", ".join(sorted(missing)))
    scope = clean_models[keys_of[SCOPE_PACKAGE][0]]
    for key, package in packages.items():
        if package in REQUIRED_PACKAGES or package in LIBRARY_PACKAGES:
            continue
        if not package or not scope_reference(package, scope):
            raise ValueError("Additional canonical package lacks a ProductScope reference: " + key)
    dependencies, case_links = {}, {}
    for source in clean_models.values():
        for owner, target in re.findall(r"\bdependency\s+\w+\s+from\s+(?:\w+::)*'(CL-[^']+)'\s+to\s+(?:\w+::)*'([^']+)'\s*;", source):
            if owner not in entries or target not in entries or not target.startswith(("FR-", "TC-")):
                raise ValueError("Invalid canonical clause dependency: " + owner + " -> " + target)
            (dependencies if target.startswith("FR-") else case_links).setdefault(owner, set()).add(target)
    verified = set()
    for identifier, entry in entries.items():
        if identifier.startswith("CL-") and identifier not in dependencies:
            raise ValueError("Canonical clause lacks requirement ownership: " + identifier)
        if identifier.startswith("CL-") and identifier not in case_links:
            raise ValueError("Canonical clause lacks a declared verification case: " + identifier)
        if entry["kind"] == "verification":
            if not entry["refs"] or any(ref not in entries or ref.startswith("TC-") for ref in entry["refs"]):
                raise ValueError("Undefined or absent verification target: " + identifier)
            verified.update(entry["refs"])
            actual_clauses = {ref for ref in entry["refs"] if ref.startswith("CL-")}
            declared_clauses = {clause for clause, cases in case_links.items() if identifier in cases}
            if actual_clauses != declared_clauses:
                raise ValueError("Nonreciprocal canonical verification links: " + identifier)
    unverified = {i for i in entries if i.startswith("CL-")} - verified
    if unverified:
        raise ValueError("Canonical clauses lack verification links: " + ", ".join(sorted(unverified)))
    for directory_name in SOURCE_BINDING_ROOTS:
        for path in sorted((root / directory_name).rglob("*")):
            if not path.is_file() or path.suffix not in {".rs", ".js", ".cjs"}:
                continue
            for tag in re.findall(r"(?m)^\s*(?://|#)\s*Proves:([^\r\n]+)", path.read_text(encoding="utf-8")):
                if unknown := source_proves(tag) - entries.keys():
                    raise ValueError("Source Proves tag names undefined model identities: " + path.relative_to(root).as_posix() + ": " + ", ".join(sorted(unknown)))
    return entries


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


def architecture_integrity(output: str) -> dict[str, int]:
    """TC-DOC-005 (CL-014-03, CL-014-06): independent structural oracle for WstxArchitecture.

    Input is the pinned Pilot's resolved semantic inventory, not SysML source or a
    viewer graph. Endpoint expectations bind the reviewed architecture responsibilities
    to model names; they are deliberately not generated from the candidate model.
    """
    rows = [line.split("\t")[1:] for line in output.splitlines() if line.startswith("AST\t")]
    if not rows:
        raise ValueError("Architecture integrity: missing resolved Pilot inventory")
    records = {kind: [row[1:] for row in rows if row[0] == kind] for kind in {row[0] for row in rows}}
    if records.get("ROOTPART") != [["WstxArchitecture::physicalStation"]]:
        raise ValueError("Architecture integrity: expected one physical deployment")
    if records.get("VIEWSEMANTIC"):
        raise ValueError("Architecture integrity: views may expose, not create runtime parts/connections")
    parts = {row[0]: row[1:] for row in records.get("PART", [])}
    refs = {row[0]: row[1:] for row in records.get("REF", [])}
    ports = {row[0]: row[1] for row in records.get("PORT", [])}
    p = "physicalStation"
    station = p + ".backend.stations"
    if {path for path in parts if path.count(".") == 1} != {p + "." + role for role in ("user", "frontend", "backend", "radio",
                                                                                   "browserAttachments", "radioAudioAttachments", "radioControlAttachments")}:
        raise ValueError("Architecture integrity: expected four physical roles")
    if parts.get(station, [None, None])[1] != "0:-1":
        raise ValueError("Architecture integrity: station population must remain variable")
    for name, type_name in (("profile", "PersistedProfile"),
                            ("audioAdapter", "AudioDeviceAdapter"), ("catAdapter", "RustRadioDriver")):
        path = station + "." + name
        values = parts.get(path, [])
        if len(values) < 3 or values[:2] != ["WstxArchitecture::" + type_name, "1:1"] or values[2] != "false":
            raise ValueError("Architecture integrity: exactly one direct " + name + " per station")
    for name, type_name in (("audioAdapter", "AudioDeviceAdapter"), ("catAdapter", "RustRadioDriver")):
        adapter_parts = {path for path, values in parts.items() if values[0] == "WstxArchitecture::" + type_name}
        if adapter_parts != {station + "." + name}:
            raise ValueError("Architecture integrity: duplicate or detached " + name)
    authorities = [path for path, values in parts.items() if values[0] == "WstxArchitecture::RadioAuthority"]
    if authorities != [p + ".backend.radioAuthority"]:
        raise ValueError("Architecture integrity: shared radio requires one effective authority")

    expected_refs = {
        station + ".authority": p + ".backend.radioAuthority",
        station + ".radioBinding.radio": p + ".radio",
        p + ".browserAttachments.browser": p + ".frontend.browsers",
        p + ".browserAttachments.station": station,
        p + ".backend.mcpAttachments.client": p + ".backend.mcpClients",
        p + ".backend.mcpAttachments.station": station,
        p + ".radioAudioAttachments.station": station,
        p + ".radioControlAttachments.station": station,
    }
    for path, target in expected_refs.items():
        if path not in refs or refs[path][1] != "1:1" or refs[path][3] != target:
            raise ValueError("Architecture integrity: invalid endpoint/resource/authority association " + path)

    # Required exchanges/delegations by independently specified responsibility.
    expected = {
        p + ".browserAttachments": [("physicalStation.user.interaction", "browser.operator"),
                                    ("browser.station", "station.web.client")],
        p + ".backend.mcpAttachments": [("client.station", "station.mcp.client")],
        p + ".radioAudioAttachments": [("station.audioAdapter.radio", "station.radioBinding.radio.audio")],
        p + ".radioControlAttachments": [("station.catAdapter.radio", "station.radioBinding.radio.control")],
        p + ".backend.radioAuthority": [("authorized.request", "requests.request"), ("requests.outcome", "authorized.outcome")],
        station: [("web.station", "station.webOperations"), ("mcp.station", "station.mcpOperations"),
            ("station.profile", "profile.context"), ("station.receive", "receive.jobs"),
            ("station.transmit", "transmit.operations"), ("station.qso", "qso.operations"),
            ("station.control", "radioControl.station"), ("audio.receive", "receive.audio"),
            ("audio.status", "station.audioStatus"), ("receive.processing", "modes.receive"),
            ("transmit.encode", "modes.encode"), ("transmit.audio", "audio.transmit"),
            ("transmit.control", "radioControl.transmit"), ("web.recording", "station.upload"),
            ("station.acceptedRecording", "profile.upload"), ("profile.recordedSamples", "audio.recorded"),
            ("qso.contacts", "profile.contacts"), ("qso.transmit", "transmit.contacts"),
            ("audio.backend", "audioAdapter.host"),
            ("radioControl.backend", "authorityRequest"), ("authorizedControl", "catAdapter.authorized"),
            ("authorityRequest", "authority.requests"), ("authority.authorized", "authorizedControl"),
            ("authorityRequest.request.resourceContext", "radioBinding"), ("catAdapter.authorized.request.resourceContext", "radioBinding")],
        station + ".profile": [("upload", "recordings.upload"), ("recordings.samples", "recordedSamples")],
    }
    # Independent TC-DOC-005 role/contract bindings. A leading
    # ~ marks the provider/conjugate role. Do not infer expected roles from the model.
    role_contracts = {}

    def roles(owner, **bindings):
        role_contracts.update({owner + "." + name: contract for name, contract in bindings.items()})

    roles(p + ".user", interaction="LocalInteraction")
    roles(p + ".frontend.browsers", operator="~LocalInteraction", station="BrowserExchange")
    roles(p + ".backend.mcpClients", station="StationOperations")
    roles(p + ".radio", audio="~AudioExchange", control="~RadioControl")
    roles(p + ".backend.radioAuthority", requests="~RadioControl", authorized="RadioControl")
    roles(station, authorityRequest="RadioControl", authorizedControl="~RadioControl")
    roles(station + ".profile", context="~ProfileAccess", contacts="~ProfileAccess", upload="~RecordingTransfer", recordedSamples="ReceiveSamples")
    roles(station + ".profile.recordings", upload="~RecordingTransfer", samples="ReceiveSamples")
    roles(station + ".station", webOperations="~StationOperations", mcpOperations="~StationOperations", profile="ProfileAccess",
          receive="StationOperations", transmit="StationOperations", qso="StationOperations", control="RadioControl",
          upload="~RecordingTransfer", acceptedRecording="RecordingTransfer", audioStatus="~AudioStatus")
    roles(station + ".web", client="~BrowserExchange", station="StationOperations", recording="RecordingTransfer")
    roles(station + ".mcp", client="~StationOperations", station="StationOperations")
    roles(station + ".receive", jobs="~StationOperations", audio="~ReceiveSamples", processing="ReceiveProcessing")
    roles(station + ".modes", receive="~ReceiveProcessing", encode="~EncodeProcessing")
    roles(station + ".audio", status="AudioStatus", recorded="~ReceiveSamples", receive="ReceiveSamples", transmit="~AudioExchange", backend="AudioExchange")
    roles(station + ".radioControl", station="~RadioControl", transmit="~RadioControl", backend="RadioControl")
    roles(station + ".transmit", operations="~StationOperations", contacts="~StationOperations", encode="EncodeProcessing", audio="AudioExchange", control="RadioControl")
    roles(station + ".qso", operations="~StationOperations", contacts="ProfileAccess", transmit="StationOperations")
    roles(station + ".audioAdapter", host="~AudioExchange", radio="AudioExchange")
    roles(station + ".catAdapter", authorized="~RadioControl", radio="RadioControl")
    for path, contract in role_contracts.items():
        if contract.lstrip("~") == "RadioControl":
            expected[path] = [("outcome.request", "request")]
    required_bindings = {
        (p + ".backend.radioAuthority", frozenset(("authorized.request", "requests.request"))),
        (p + ".backend.radioAuthority", frozenset(("requests.outcome", "authorized.outcome"))),
        (station, frozenset(("authorityRequest.request.resourceContext", "radioBinding"))),
        (station, frozenset(("catAdapter.authorized.request.resourceContext", "radioBinding"))),
    }
    required_bindings.update((path, frozenset(("outcome.request", "request")))
                             for path, contract in role_contracts.items() if contract.lstrip("~") == "RadioControl")
    expected_edges = {(owner, "binding" if (owner, frozenset(pair)) in required_bindings else "connection", frozenset(pair))
                      for owner, pairs in expected.items() for pair in pairs}
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
    # Full item signatures, independently declared rather than copied from the AST.
    # Delegation may join equal directions; each role is checked against its own
    # contract instead of imposing a blanket opposite-directions rule on edges.
    contracts = {
        "LocalInteraction": {"request": ("out", "OperatorRequest"), "presentation": ("in", "Presentation")},
        "StationOperations": {"request": ("out", "StationRequest"), "outcome": ("in", "StationOutcome")},
        "BrowserExchange": {"request": ("out", "StationRequest"), "outcome": ("in", "StationOutcome"), "upload": ("out", "Recording")},
        "RecordingTransfer": {"recording": ("out", "Recording")},
        "ProfileAccess": {"request": ("out", "ProfileRequest"), "outcome": ("in", "ProfileOutcome")},
        "AudioExchange": {"playback": ("out", "SampleBlock"), "capture": ("in", "SampleBlock"), "outcome": ("in", "AudioOutcome")},
        "AudioStatus": {"outcome": ("out", "AudioOutcome")},
        "ReceiveSamples": {"samples": ("out", "SampleBlock"), "outcome": ("out", "AudioOutcome")},
        "ReceiveProcessing": {"request": ("out", "ProcessingRequest"), "result": ("in", "ProcessingResult")},
        "EncodeProcessing": {"request": ("out", "EncodeRequest"), "waveform": ("in", "Waveform")},
        "RadioControl": {"request": ("out", "ControlRequest"), "outcome": ("in", "ControlOutcome")},
    }
    if set(ports) != set(role_contracts):
        raise ValueError("Architecture integrity: missing or unexpected boundary port roles " + str(sorted(set(ports) ^ set(role_contracts))))
    for path, role in role_contracts.items():
        signature = contracts[role.lstrip("~")]
        actual = items.get(path, {})
        if set(actual) != set(signature):
            raise ValueError("Architecture integrity: semantic exchange signature mismatch " + path)
        for item, (direction, semantic_type) in signature.items():
            if role.startswith("~"):
                direction = {"in": "out", "out": "in"}[direction]
            actual_direction, actual_type = actual[item]
            if actual_direction != direction:
                raise ValueError("Architecture integrity: wrong exchange direction " + path + "." + item)
            if actual_type != "WstxArchitecture::" + semantic_type:
                raise ValueError("Architecture integrity: wrong semantic item type " + path + "." + item)
    return {"parts": len(parts), "references": len(refs), "ports": len(ports), "connections": len(actual_edges)}


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
    semantic = commands.add_parser("validate", help="Run real semantic validation on ordered files")
    semantic.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "setup":
            setup(args.cache_dir)
            return 0
        if args.command == "traces":
            authority(MODELS, FSD)
            entries = canonical_catalog(MODELS, ROOT)
            print(f"Canonical source/model trace checks passed: {len(entries)} identities; no semantic validation or behavior execution.")
            return 0
        if args.command == "markers":
            authority(MODELS, FSD)
            print("\n".join(markers(MODELS, args.kinds)))
            return 0
        if args.command == "fingerprints":
            authority(MODELS, FSD)
            canonical_catalog(MODELS, ROOT)
            print(json.dumps({key: digest(path.read_text(encoding="utf-8")) for key, path in model_files(MODELS).items()}, indent=2))
            return 0
        if args.command == "check":
            authority(MODELS, FSD)
            entries = canonical_catalog(MODELS, ROOT)
            print(f"Canonical SysML catalog/trace checks passed: {len(entries)} identities; behavioral correspondence remains independently reviewed.")
            entry = "Requirements.sysml"
            paths = [MODELS / entry, *(path for key, path in model_files(MODELS).items() if key != entry)]
        else:
            paths = args.files
        result = validate(paths, args.cache_dir, inventory=args.command == "check")
        for line in result.stdout.splitlines():
            if not line.startswith(("Reading ", "AST\t")):
                print(line)
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
        if result.returncode == 0 and args.command == "check":
            counts = architecture_integrity(result.stdout)
            print("Architecture integrity passed: " + ", ".join(f"{count} {kind}" for kind, count in counts.items()) + "; runtime behavior not proved.")
        return result.returncode
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"SysML check failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
