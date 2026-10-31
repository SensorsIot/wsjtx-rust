"""Canonical-authority SysML checks and real OMG Pilot validation.

traces checks catalog and source/model bindings only. check additionally calls the
pinned Java parser/name resolver/semantic validator. Neither executes modeled behavior.
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
CANONICAL_MODELS = {
    "Requirements.sysml", "Architecture.sysml", "Profiles.sysml",
    "RecordingReceive.sysml", "StationDecode.sysml", "RadioIO.sysml",
    "OperatingLayout.sysml", "OperatingReceive.sysml", "StationProtocol.sysml", "ProductScope.sysml",
}
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
        proves = " ".join(re.findall(r"(?m)^\s*(?://|#)\s*Proves:([^\r\n]+)", source))
        named = re.search(r"\btest\s*\(\s*['\"][^'\"\r\n]*\b" + re.escape(identifier) + r"\b", source)
        return identifier in source_proves(proves) or bool(named)


def source_proves(text: str) -> set[str]:
    # Fixture-specific and HOW names are not product identities. Numeric product
    # IDs retain the existing strict shape and shorthand-expansion checks.
    text = re.sub(r"\b(?:FR|CL|TC)-[A-Za-z][A-Za-z0-9-]*", "", text)
    return {ref for ref in references(text) if not ref.startswith(("CL-014-", "TC-DOC-"))}


def canonical_catalog(directory: Path, root: Path, required=BASELINE_IDENTITIES) -> dict[str, dict]:
    actual = {path.name for path in directory.glob("*.sysml")}
    if missing := CANONICAL_MODELS - actual:
        raise ValueError("Canonical model files missing: " + ", ".join(sorted(missing)))
    entries = {}
    clean_models = {}
    for path in sorted(directory.glob("*.sysml")):
        source = path.read_text(encoding="utf-8")
        if re.search(r"Canonical FSD|\bFSD(?:\s+(?:chapter|section))?\s*\d|WSTX(?:%20| )Rust(?:%20| )FSD", source):
            raise ValueError("Canonical model retains a retired FSD dependency: " + path.name)
        for target in re.findall(r"\]\(([^)]+)\)", source):
            target = target.strip("<>")
            if target.startswith(("https://", "http://", "#")):
                continue
            target = urllib.parse.unquote(target.split("#", 1)[0])
            if target and not (path.parent / target).resolve().is_file():
                raise ValueError("Dangling model documentation link: " + path.name + ": " + target)
        clean = without_comments(source)
        clean_models[path.name] = clean
        for match in re.finditer(r"\b(requirement|verification)(?:\s+def)?\s+'((?:FR-\d{3}|CL-\d{3}-\d{2}|TC-\d{3}-\d{3}))'\s*\{", clean):
            kind, identifier = match[1], match[2]
            if identifier in entries:
                raise ValueError("Duplicate canonical identity: " + identifier)
            if kind != ("verification" if identifier.startswith("TC-") else "requirement"):
                raise ValueError("Wrong canonical identity kind: " + identifier)
            body = declaration_body(clean, match.end() - 1)
            state_name, enum = ("automation", "AutomationState") if kind == "verification" else ("coverage", "ImplementationState")
            states = re.findall(r"\battribute\s+" + state_name + r"\s*:\s*" + enum + r"\s*=\s*" + enum + r"::(\w+)\s*;", body)
            allowed = {"planned", "partial", "implemented"} if kind == "verification" else {"target", "partial", "implemented"}
            if len(states) != 1 or states[0] not in allowed:
                raise ValueError("Missing or invalid declared model state: " + identifier)
            refs = re.findall(r"\bverify\s+(?:WstxRequirements::)?'([^']+)'\s*;", body)
            key = "executable" if kind == "verification" else "implementation"
            bindings = re.findall(r'\battribute\s+' + key + r'\s*:\s*String\s*=\s*"([^"\r\n]*)"\s*;', body)
            methods = re.findall(r'\battribute\s+method\s*:\s*String\s*=\s*"([^"\r\n]*)"\s*;', body)
            if len(bindings) > 1 or len(methods) > 1 or (methods and methods[0] not in {"manual", "automated"}):
                raise ValueError("Invalid verification/implementation metadata: " + identifier)
            if states[0] in {"partial", "implemented"} and (not bindings or not bindings[0].strip()):
                raise ValueError("Delivered declaration lacks implementation/test binding: " + identifier)
            matched = [source_binding(identifier, binding.strip(), root, manual=methods == ["manual"])
                       for binding in (bindings[0].split(";") if bindings else [])]
            if kind == "verification" and bindings and not any(matched):
                raise ValueError(f"No Proves tag or named-test identity for {identifier}: {bindings[0]}")
            entries[identifier] = {"kind": kind, "state": states[0], "refs": refs}
    if missing := set(required) - entries.keys():
        raise ValueError("Missing stable canonical identities: " + ", ".join(sorted(missing)))
    for name in actual - CANONICAL_MODELS:
        package = re.search(r"\bpackage\s+(\w+)\s*\{", clean_models[name])
        if not package or not re.search(r"\b" + re.escape(package[1]) + r"::", clean_models["ProductScope.sysml"]):
            raise ValueError("Additional canonical package lacks a ProductScope reference: " + name)
    dependencies, case_links = {}, {}
    for source in clean_models.values():
        for owner, target in re.findall(r"\bdependency\s+\w+\s+from\s+'(CL-[^']+)'\s+to\s+'([^']+)'\s*;", source):
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
    result = subprocess.run([str(java), "-classpath", str(jar), str(ROOT / "tools/sysml/Validate.java"), str(library), *(["--inventory"] if inventory else []), *map(str, paths)], text=True, capture_output=True, timeout=120)
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
        if args.command == "fingerprints":
            authority(MODELS, FSD)
            canonical_catalog(MODELS, ROOT)
            print(json.dumps({path.name: digest(path.read_text(encoding="utf-8")) for path in sorted(MODELS.glob("*.sysml"))}, indent=2))
            return 0
        if args.command == "check":
            authority(MODELS, FSD)
            entries = canonical_catalog(MODELS, ROOT)
            print(f"Canonical SysML catalog/trace checks passed: {len(entries)} identities; behavioral correspondence remains independently reviewed.")
            entry = MODELS / "Requirements.sysml"
            paths = [entry, *sorted(path for path in MODELS.glob("*.sysml") if path != entry)]
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
