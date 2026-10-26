"""Markdown-authoritative SysML projection and real OMG Pilot validation.

sync is generation, not semantic proof. check additionally calls the pinned Java
parser/name resolver/semantic validator. Neither executes modeled behavior.
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
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FSD = ROOT / "docs/WSTX Rust FSD.md"
MODELS = ROOT / "docs/sysml"
TOOLCHAIN = Path(__file__).with_name("sysml") / "toolchain.json"
ID = re.compile(r"\b(?:FR-\d{3}|CL-\d{3}-\d{2}|TC-(?:\d{3}|DOC)-\d{3})\b")


def digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def library_digest(directory: Path) -> str:
    fingerprint = hashlib.sha256()
    for path in sorted(p for p in directory.rglob("*") if p.suffix in (".sysml", ".kerml")):
        fingerprint.update(path.relative_to(directory).as_posix().encode("utf-8") + b"\0")
        fingerprint.update(hashlib.sha256(path.read_bytes()).digest())
    return fingerprint.hexdigest()


def legacy_catalog(text: str) -> dict[str, dict]:
    """Read only defined table rows/headings, never incidental ID mentions."""
    entries: dict[str, dict] = {}
    lines = text.splitlines()

    def add(identifier: str, kind: str, prose: str, refs: list[str]):
        # The operator keeps documentation/harness methods in Markdown only.
        if identifier.startswith(("CL-014-", "TC-DOC-")):
            return
        if identifier in entries:
            raise ValueError(f"Duplicate definition: {identifier}")
        if "*/" in prose:
            raise ValueError(f"SysML doc terminator in Markdown: {identifier}")
        entries[identifier] = {"kind": kind, "text": prose.strip(), "refs": sorted(set(refs))}

    for index, line in enumerate(lines):
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if line.startswith("|") and cells[0].startswith(("FR-", "CL-", "TC-")) and not ID.match(cells[0]):
            raise ValueError(f"Malformed definition identity: {cells[0]}")
        if line.startswith("|") and re.fullmatch(r"FR-\d{3}", cells[0]):
            if len(cells) != 3:
                raise ValueError(f"Expected three requirement columns: {cells[0]}")
            add(cells[0], "requirement", f"{cells[1]}\n{cells[2]}", [])
        elif line.startswith("|") and re.fullmatch(r"CL-\d{3}-\d{2}", cells[0]):
            if len(cells) != 4:
                raise ValueError(f"Expected four clause columns: {cells[0]}")
            add(cells[0], "clause", cells[2], re.findall(r"FR-\d{3}", cells[1]))
        elif line.startswith("|") and re.match(r"TC-(?:\d{3}|DOC)-\d{3}\b", cells[0]):
            identifier = ID.match(cells[0]).group()
            add(identifier, "verification", "\n".join(cells), re.findall(r"FR-\d{3}|CL-\d{3}-\d{2}", cells[1]))
        else:
            match = re.match(r"#### (TC-\d{3}-\d{3})\b", line)
            if match:
                end = index + 1
                while end < len(lines) and not re.match(r"#{1,4} ", lines[end]):
                    end += 1
                body = "\n".join(lines[index:end])
                refs = re.findall(r"FR-\d{3}|CL-\d{3}-\d{2}", body)
                add(match[1], "verification", body, refs or ["FR-" + match[1].split("-")[1]])
    if not entries:
        raise ValueError("No FSD definitions found")
    for identifier, entry in entries.items():
        for ref in entry["refs"]:
            if ref not in entries:
                raise ValueError(f"{identifier} refers to undefined {ref}")
    return entries


PROJECTION_V2 = "<!-- sysml-projection: 2 -->"


def projection_v2(text: str) -> bool:
    markers = re.findall(r"<!--\s*sysml-projection:[^>]*-->", text)
    if markers and markers != [PROJECTION_V2]:
        raise ValueError("Expected one exact sysml-projection: 2 marker")
    return bool(markers)


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


def declared_metadata(text: str, entries: dict[str, dict]) -> tuple[dict[str, str], dict[str, list[str]]]:
    states, companions = {}, {}
    table = None
    for line in text.splitlines():
        if not line.startswith("|"):
            table = None
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if cells == ["Model identity", "Declared state"]:
            table = "states"
            continue
        if cells == ["Manual companion", "FSD sections"]:
            table = "companions"
            continue
        if not table or all(re.fullmatch(r"[-:]+", cell) for cell in cells):
            continue
        if not re.fullmatch(r"`[^`]+`", cells[0]):
            raise ValueError("Expected backticked metadata identity: " + cells[0])
        key = cells[0][1:-1]
        if table == "states":
            if len(cells) != 2 or key not in entries or key in states:
                raise ValueError("Invalid/duplicate/undefined declared metadata: " + key)
            allowed = {"planned", "partial", "implemented"} if entries[key]["kind"] == "verification" else {"target", "partial", "implemented"}
            if cells[1] not in allowed:
                raise ValueError("Invalid declared state: " + key)
            states[key] = cells[1]
        elif table == "companions":
            if len(cells) != 2 or not key.endswith(".sysml") or Path(key).name != key or "/" in key or "\\" in key or key == "Requirements.sysml" or key in companions:
                raise ValueError("Invalid/duplicate manual companion: " + key)
            sections = [section.strip() for section in cells[1].split(",")]
            if any(not re.fullmatch(r"\d+(?:\.\d+)*", section) for section in sections):
                raise ValueError("Invalid FSD section selection: " + key)
            companions[key] = sections
    if set(states) != set(entries):
        raise ValueError("Missing declared metadata: " + ", ".join(sorted(set(entries) - set(states))))
    return states, companions


def section_digest(text: str, sections: list[str]) -> str:
    """Hash selected numbered heading subtrees, once, with exact UTF-8 text."""
    lines = text.splitlines(keepends=True)
    headings = {}
    for index, line in enumerate(lines):
        match = re.match(r"(#{1,6}) (\d+(?:\.\d+)*)\.?\s+", line)
        if match:
            key = match[2]
            if key in headings:
                raise ValueError("Duplicate numbered FSD heading: " + key)
            headings[key] = (index, len(match[1]))
    ranges = []
    for section in sections:
        if section not in headings:
            raise ValueError("Missing FSD section: " + section)
        start, depth = headings[section]
        end = next((i for i in range(start + 1, len(lines)) if re.match(r"#{1," + str(depth) + r"} ", lines[i])), len(lines))
        ranges.append((start, end, section))
    ranges.sort()
    if any(left[1] > right[0] for left, right in zip(ranges, ranges[1:])):
        raise ValueError("Overlapping or repeated FSD sections")
    payload = "".join(section + "\0" + "".join(lines[start:end]) + "\0" for start, end, section in ranges)
    return digest(payload)


def catalog(text: str) -> dict[str, dict]:
    entries = legacy_catalog(text)
    if not projection_v2(text):
        return entries
    clause_tests = {}
    for line in text.splitlines():
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if line.startswith("|") and re.fullmatch(r"CL-\d{3}-\d{2}", cells[0]) and cells[0] in entries:
            entries[cells[0]]["refs"] = references(cells[1])
            if any(not ref.startswith("FR-") for ref in entries[cells[0]]["refs"]):
                raise ValueError("Clause requirement reference must name FR: " + cells[0])
            clause_tests[cells[0]] = references(cells[3])
    for identifier, entry in entries.items():
        if entry["kind"] == "verification":
            entry["refs"] = [ref for ref in references(entry["text"]) if ref != identifier and not ref.startswith("TC-")]
        for ref in entry["refs"]:
            if ref not in entries:
                raise ValueError(f"{identifier} refers to undefined {ref}")
    for clause, tests in clause_tests.items():
        if not tests:
            raise ValueError("Missing linked verification: " + clause)
        for test in tests:
            if test not in entries or entries[test]["kind"] != "verification":
                raise ValueError(f"{clause} refers to undefined verification {test}")
            if clause not in entries[test]["refs"]:
                raise ValueError(f"Verification mismatch: {clause} lists {test}, which does not verify it")
    for test, entry in entries.items():
        if entry["kind"] == "verification":
            if not entry["refs"]:
                raise ValueError("Missing verification objective: " + test)
            for clause in (ref for ref in entry["refs"] if ref.startswith("CL-")):
                if test not in clause_tests.get(clause, []):
                    raise ValueError(f"Verification mismatch: {test} verifies {clause}, whose table omits it")
    states, _ = declared_metadata(text, entries)
    for identifier, state in states.items():
        entries[identifier]["state"] = state
    return entries


def companion_fingerprints(text: str) -> dict[str, str]:
    _, companions = declared_metadata(text, catalog(text))
    if not companions:
        raise ValueError("Missing manual companion declarations")
    return {name: section_digest(text, sections) for name, sections in companions.items()}


def check_companions(text: str, directory: Path):
    expected = companion_fingerprints(text)
    actual = {path.name for path in directory.glob("*.sysml") if path.name != "Requirements.sysml"}
    if actual != set(expected):
        raise ValueError("Manual companion declaration/file mismatch: " + ", ".join(sorted(actual ^ set(expected))))
    for name, fingerprint in expected.items():
        model = (directory / name).read_text(encoding="utf-8")
        markers = re.findall(r"^// Canonical FSD slices SHA256: ([a-f0-9]{64})$", model, re.MULTILINE)
        if markers != [fingerprint]:
            raise ValueError("Manual companion source slices changed: " + name + "; reconcile meaning before renewing its marker")

def render(text: str) -> str:
    entries = catalog(text)
    result = [
        "// GENERATED by python tools/sysml.py sync; edit canonical Markdown instead.",
        f"// Canonical FSD SHA256: {digest(text)}",
        "package WstxRequirements {",
        "    doc /* Markdown FSD is authoritative. Prose requirements and verification",
        "         definitions are projected here; validation does not execute tests.",
        "         Coverage flags describe implemented source slices, not acceptance or whole-project parity. */",
        "    enum def ImplementationState { enum target; enum partial; enum implemented; }",
        ("    enum def AutomationState { enum planned; enum partial; enum implemented; }" if projection_v2(text) else "    enum def AutomationState { enum planned; enum implemented; }"),
    ]
    for identifier, entry in entries.items():
        kind = "verification" if entry["kind"] == "verification" else "requirement"
        result.append(f"    {kind} '{identifier}' {{")
        result.append("        doc /* " + entry["text"].replace("\n", "\n             ") + " */")
        if kind == "requirement":
            state = "implemented" if entry["kind"] == "clause" and identifier.startswith(("CL-003-", "CL-005-", "CL-006-")) else "implemented" if identifier in ("FR-018", "FR-022") else "partial" if identifier in ("FR-001", "FR-010", "FR-016", "FR-019", "FR-021") else "target"
            state = entry.get("state", state)
            result.append(f"        attribute coverage : ImplementationState = ImplementationState::{state};")
        else:
            automated = {f"TC-021-{i:03}" for i in range(5, 10)} | {f"TC-022-{i:03}" for i in range(1, 6)} | {f"TC-018-{i:03}" for i in range(1, 4)} | {f"TC-010-{i:03}" for i in range(1, 8)}
            state = "implemented" if identifier in automated else "planned"
            state = entry.get("state", state)
            result.append(f"        attribute automation : AutomationState = AutomationState::{state};")
            result.append("        objective {")
            result.extend(f"            verify '{ref}';" for ref in entry["refs"])
            result.append("        }")
        result.append("    }")
        if entry["kind"] == "clause":
            for ref in entry["refs"]:
                name = (identifier + "_to_" + ref).replace("-", "_")
                result.append(f"    dependency {name} from '{identifier}' to '{ref}';")
    return "\n".join(line.rstrip() for line in "\n".join(result + ["}", ""]).split("\n"))


def check_architecture(model: str, source: str):
    marker = re.search(r"^// Canonical architecture SHA256: ([a-f0-9]{64})$", model, re.MULTILINE)
    if not marker or marker[1] != digest(source):
        raise ValueError("Architecture source changed: review Architecture.sysml against FSD chapter 11 and update its source-hash marker explicitly")


def check_profiles_contract(model: str, source: str):
    marker = re.search(r"^// Canonical profile contract SHA256: ([a-f0-9]{64})$", model, re.MULTILINE)
    if not marker or marker[1] != digest(source):
        raise ValueError("Profile contract source changed: reconcile Profiles.sysml with FSD 4.2, 6.2 and 12.5 before updating its source-hash marker")


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
    """TC-DOC-005: independent structural oracle for FSD section 11.9.

    Input is the pinned Pilot's resolved semantic inventory, not SysML source or a
    viewer graph. Endpoint expectations bind the Markdown responsibilities to model
    names; they are deliberately not generated from the candidate model.
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
    station = p + ".controller.stations"
    if {path for path in parts if path.count(".") == 1} != {p + "." + role for role in ("user", "viewer", "controller", "radio")}:
        raise ValueError("Architecture integrity: expected four physical roles")
    if parts.get(station, [None, None])[1] != "0:-1":
        raise ValueError("Architecture integrity: station population must remain variable")
    for path in (station + ".profile", station + ".backend"):
        if parts.get(path, [None, None])[1] != "1:1":
            raise ValueError("Architecture integrity: exactly one selected profile/backend per station")
    variation = parts.get(station + ".backend", [])
    if len(variation) < 3 or variation[2] != "true":
        raise ValueError("Architecture integrity: backend must be an exclusive variation")
    variants = dict(records.get("VARIANTS", []))
    if variants.get(station + ".backend") != "standardDevices,nativeFlex":
        raise ValueError("Architecture integrity: expected standard/native backend alternatives")
    backend_parts = {path for path, values in parts.items() if values[0] in ("WstxArchitecture::StandardBackend", "WstxArchitecture::NativeBackend")}
    if backend_parts != {station + ".backend.standardDevices", station + ".backend.nativeFlex"}:
        raise ValueError("Architecture integrity: duplicate or detached backend")
    authorities = [path for path, values in parts.items() if values[0] == "WstxArchitecture::RadioAuthority"]
    if authorities != [p + ".controller.radioAuthority"]:
        raise ValueError("Architecture integrity: shared radio requires one effective authority")

    expected_refs = {
        station + ".authority": p + ".controller.radioAuthority",
        station + ".radioBinding.radio": p + ".radio",
        p + ".stationLink.attachments.browser": p + ".viewer.browsers",
        p + ".stationLink.attachments.station": station,
        p + ".controller.mcpAttachments.client": p + ".controller.mcpClients",
        p + ".controller.mcpAttachments.station": station,
        p + ".radioAudio.channels.station": station,
        p + ".radioControl.channels.station": station,
    }
    for path, target in expected_refs.items():
        if path not in refs or refs[path][1] != "1:1" or refs[path][3] != target:
            raise ValueError("Architecture integrity: invalid endpoint/resource/authority association " + path)

    # Required exchanges/delegations by independently specified responsibility.
    expected = {
        p: [("user.interaction", "viewer.operator"), ("viewer.stationLink", "controller.viewerLink"),
            ("controller.radioAudio", "radio.audio"), ("controller.radioControl", "radio.control")],
        p + ".viewer": [("operator", "browsers.operator")],
        p + ".stationLink.attachments": [("browser.station", "clientBoundary"), ("clientBoundary", "station.web.client")],
        p + ".controller.mcpAttachments": [("client.station", "station.mcp.client")],
        p + ".radioAudio.channels": [("station.backend.radioAudio", "station.radioBinding.radio.audio")],
        p + ".radioControl.channels": [("station.backend.radioControl", "station.radioBinding.radio.control")],
        p + ".controller.radioAuthority": [("authorized.request", "requests.request"), ("requests.outcome", "authorized.outcome")],
        station: [("web.station", "station.webOperations"), ("mcp.station", "station.mcpOperations"),
            ("station.profile", "profile.context"), ("station.receive", "receive.jobs"),
            ("station.transmit", "transmit.operations"), ("station.qso", "qso.operations"),
            ("station.control", "radioControl.station"), ("audio.receive", "receive.audio"),
            ("audio.status", "station.audioStatus"), ("receive.processing", "modes.receive"),
            ("transmit.encode", "modes.encode"), ("transmit.audio", "audio.transmit"),
            ("transmit.control", "radioControl.transmit"), ("web.recording", "station.upload"),
            ("station.acceptedRecording", "profile.upload"), ("profile.recordedSamples", "audio.recorded"),
            ("qso.contacts", "profile.contacts"), ("audio.backend", "backend.audio"),
            ("radioControl.backend", "authorityRequest"), ("authorizedControl", "backend.control"),
            ("authorityRequest", "authority.requests"), ("authority.authorized", "authorizedControl"),
            ("authorityRequest.request.resourceContext", "radioBinding"), ("backend.control.request.resourceContext", "radioBinding")],
        station + ".profile": [("upload", "recordings.upload"), ("recordings.samples", "recordedSamples")],
    }
    for selection in ("standardDevices", "nativeFlex"):
        expected[station + ".backend." + selection] = [("audio", "audioDevices.host"), ("audioDevices.radio", "radioAudio"),
            ("control", "controlDriver.authorized"), ("controlDriver.radio", "radioControl")]
    expected[station + ".backend.nativeFlex"] += [("audioDevices.session", "session.audio"), ("controlDriver.session", "session.control")]
    # Independent role/contract bindings from FSD section 11.9. A leading
    # ~ marks the provider/conjugate role. Do not infer expected roles from the model.
    role_contracts = {}

    def roles(owner, **bindings):
        role_contracts.update({owner + "." + name: contract for name, contract in bindings.items()})

    roles(p + ".user", interaction="LocalInteraction")
    roles(p + ".viewer", operator="~LocalInteraction", stationLink="BrowserExchange")
    roles(p + ".viewer.browsers", operator="~LocalInteraction", station="BrowserExchange")
    roles(p + ".controller", viewerLink="~BrowserExchange", radioAudio="AudioExchange", radioControl="RadioControl")
    roles(p + ".controller.mcpClients", station="StationOperations")
    roles(p + ".radio", audio="~AudioExchange", control="~RadioControl")
    roles(p + ".stationLink.attachments", clientBoundary="~BrowserExchange")
    roles(p + ".controller.radioAuthority", requests="~RadioControl", authorized="RadioControl")
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
    roles(station + ".transmit", operations="~StationOperations", encode="EncodeProcessing", audio="AudioExchange", control="RadioControl")
    roles(station + ".qso", operations="~StationOperations", contacts="ProfileAccess")
    for backend in (station + ".backend", station + ".backend.standardDevices", station + ".backend.nativeFlex"):
        roles(backend, audio="~AudioExchange", control="~RadioControl", radioAudio="AudioExchange", radioControl="RadioControl")
    for selection in ("standardDevices", "nativeFlex"):
        backend = station + ".backend." + selection
        roles(backend + ".audioDevices", host="~AudioExchange", radio="AudioExchange")
        roles(backend + ".controlDriver", authorized="~RadioControl", radio="RadioControl")
    roles(station + ".backend.nativeFlex.audioDevices", session="SessionAccess")
    roles(station + ".backend.nativeFlex.controlDriver", session="SessionAccess")
    roles(station + ".backend.nativeFlex.session", audio="~SessionAccess", control="~SessionAccess")
    for path, contract in role_contracts.items():
        if contract.lstrip("~") == "RadioControl":
            expected[path] = [("outcome.request", "request")]
    required_bindings = {
        (p + ".controller.radioAuthority", frozenset(("authorized.request", "requests.request"))),
        (p + ".controller.radioAuthority", frozenset(("requests.outcome", "authorized.outcome"))),
        (station, frozenset(("authorityRequest.request.resourceContext", "radioBinding"))),
        (station, frozenset(("backend.control.request.resourceContext", "radioBinding"))),
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
        "SessionAccess": {"operation": ("out", "NativeSessionOperation"), "outcome": ("in", "NativeSessionOutcome")},
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
    commands.add_parser("sync", help="Regenerate the FSD projection only; not semantic validation")
    commands.add_parser("fingerprints", help="Print declared v2 companion slice digests; never updates models")
    commands.add_parser("check", help="Check Markdown synchronization and run real semantic validation")
    semantic = commands.add_parser("validate", help="Run real semantic validation on ordered files")
    semantic.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "setup":
            setup(args.cache_dir)
            return 0
        if args.command == "fingerprints":
            print(json.dumps(companion_fingerprints(FSD.read_text(encoding="utf-8")), indent=2))
            return 0
        if args.command in ("sync", "check"):
            expected = render(FSD.read_text(encoding="utf-8"))
            generated = MODELS / "Requirements.sysml"
            if args.command == "sync":
                generated.write_text(expected, encoding="utf-8", newline="\n")
                print("FSD projection regenerated; run check for syntax/name/semantic validation.")
                return 0
            if not generated.exists() or generated.read_text(encoding="utf-8") != expected:
                raise ValueError("FSD projection is stale; run python tools/sysml.py sync")
            source = FSD.read_text(encoding="utf-8")
            if projection_v2(source):
                check_companions(source, MODELS)
            else:
                print("WARNING: legacy projection uses fixed status lists and whole-source markers; v2 fidelity is NOT active.", file=sys.stderr)
                architecture = MODELS / "Architecture.sysml"
                check_architecture(architecture.read_text(encoding="utf-8"), source)
                profiles = MODELS / "Profiles.sysml"
                check_profiles_contract(profiles.read_text(encoding="utf-8"), source)
            paths = [generated, *sorted(path for path in MODELS.glob("*.sysml") if path != generated)]
            print("Markdown synchronization passed; this alone is not semantic validation.")
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
