"""CL-014-06 (#185): `oracle` writes the architecture oracle file from the resolved
inventory, after the Pilot validation and the fixed rules, and prints its changes; the
inventory starts at the one package-level part usage; the fixed rules find their parts by
type name in any package.

A fixture tree in the skeleton's form (a context root in Context.sysml, parts and
interfaces in packages of their own folders) is validated once per model state by the
real pinned Pilot, in a bounded pool; the commands then judge the recorded inventories.
One `oracle` run on a model the Pilot refuses calls the Pilot itself.
"""
from concurrent.futures import ThreadPoolExecutor
import contextlib
import functools
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import tempfile
import unittest
from unittest import mock

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("architecture_oracle_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CACHE = Path.home() / ".cache/wsjtx-rust/sysml-tools"
WORKERS = max(1, min(6, os.cpu_count() or 1))
REQUIRED = {"FR-001", "CL-003-01", "TC-001-001"}
# The catalog the skeleton merges into Requirements.sysml, without ProductScope.
ENTRY = '''// Canonical authority: SysML
package WstxRequirements {
    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }
    requirement 'FR-001' {
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    requirement 'CL-003-01' {
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    verification 'TC-001-001' {
        attribute automation : AutomationState = AutomationState::planned;
        objective { verify 'FR-001'; verify 'CL-003-01'; }
    }
    dependency owns from 'CL-003-01' to 'FR-001';
    dependency checks from 'CL-003-01' to 'TC-001-001';
}
'''
STATION = '''package WstxArchitecture {
    private import WstxProfile::*;
    private import WstxAuthority::*;
    private import WstxControl::*;
    private import WstxOperations::*;
    part def AudioDeviceAdapter;
    part def RustRadioDriver { port radio : RadioControl; }
    part def StationProcess {
        port operations : ~Operations;
        port control : RadioControl;
        part profile : PersistedProfile;
        part audioAdapter : AudioDeviceAdapter;
        part catAdapter : RustRadioDriver;
    }
    part def Station {
        port operator : ~Operations;
        part stations[*] : StationProcess;
        part radioAuthority : RadioAuthority;
        connection operating connect operator to stations.operations;
        connection control connect stations.control to radioAuthority.requests;
    }
}
'''
PROFILE = '''package WstxProfile {
    part def Recordings;
    part def PersistedProfile { part recordings : Recordings; }
}
'''
AUTHORITY = '''package WstxAuthority {
    private import WstxControl::*;
    part def RadioAuthority { port requests : ~RadioControl; }
}
'''
CONTROL = '''package WstxControl {
    item def ControlRequest;
    item def ControlOutcome;
    port def RadioControl {
        out item request : ControlRequest;
        in item outcome : ControlOutcome;
    }
}
'''
OPERATIONS = '''package WstxOperations {
    item def OperatorRequest;
    item def Presentation;
    port def Operations {
        out item request : OperatorRequest;
        in item display : Presentation;
    }
}
'''
CONTEXT = '''package WstxContext {
    private import WstxArchitecture::*;
    private import WstxControl::*;
    private import WstxOperations::*;
    part def Operator { port console : Operations; }
    part def Radio { port cat : ~RadioControl; }
    part context {
        part station : Station;
        part operator : Operator;
        part radio : Radio;
        connection operating connect operator.console to station.operator;
        connection cat connect station.stations.catAdapter.radio to radio.cat;
    }
}
'''
EXTRA = '''package WstxExtra {
    private import WstxAuthority::*;
    part def Backup { part authority : RadioAuthority; }
}
'''
BASE = {"Requirements.sysml": ENTRY, "Station.sysml": STATION, "Context.sysml": CONTEXT,
        "backend/profile/Profile.sysml": PROFILE, "backend/authority/Authority.sysml": AUTHORITY,
        "interfaces/internal/Control.sysml": CONTROL, "interfaces/internal/Operations.sysml": OPERATIONS}
# The deployment of BASE, written by hand from the fixture text: part path -> type, port path -> contract.
PARTS = {
    "context.station": "WstxArchitecture::Station",
    "context.operator": "WstxContext::Operator",
    "context.radio": "WstxContext::Radio",
    "context.station.stations": "WstxArchitecture::StationProcess",
    "context.station.radioAuthority": "WstxAuthority::RadioAuthority",
    "context.station.stations.profile": "WstxProfile::PersistedProfile",
    "context.station.stations.profile.recordings": "WstxProfile::Recordings",
    "context.station.stations.audioAdapter": "WstxArchitecture::AudioDeviceAdapter",
    "context.station.stations.catAdapter": "WstxArchitecture::RustRadioDriver",
}
PORTS = {
    "context.station.operator": "~WstxOperations::Operations",
    "context.station.stations.operations": "~WstxOperations::Operations",
    "context.station.stations.control": "WstxControl::RadioControl",
    "context.station.stations.catAdapter.radio": "WstxControl::RadioControl",
    "context.station.radioAuthority.requests": "~WstxControl::RadioControl",
    "context.operator.console": "WstxOperations::Operations",
    "context.radio.cat": "~WstxControl::RadioControl",
}

# One edit of BASE per state: (file key, original, replacement), or a file added (original None).
CONNECTION = "connection cat connect station.stations.catAdapter.radio to radio.cat;"
STATES = {
    "base": (),
    "part": (("Station.sysml", "part radioAuthority : RadioAuthority;",
              "part radioAuthority : RadioAuthority;\n        part logbook : Recordings;"),),
    "port": (("Context.sysml", "part def Operator { port console : Operations; }",
              "part def Operator { port console : Operations; port spare : Operations; }"),),
    "connection": (("Context.sysml", CONNECTION,
                    CONNECTION + "\n        connection spare connect radio.cat to station.stations.control;"),),
    "item type": (("interfaces/internal/Operations.sysml", "in item display : Presentation;",
                   "in item display : OperatorRequest;"),),
    "second root": (("Context.sysml", "    part context {", "    part spareOperator : Operator;\n    part context {"),),
    "second authority": (("backend/extra/Extra.sysml", None, EXTRA),
                         ("Context.sysml", "part radio : Radio;", "part radio : Radio;\n        part backup : WstxExtra::Backup;")),
    "duplicate catAdapter": (("Station.sysml", "part catAdapter : RustRadioDriver;",
                              "part catAdapter : RustRadioDriver;\n        part spareCat : RustRadioDriver;"),),
    "station population 1..1": (("Station.sysml", "part stations[*]", "part stations[1..1]"),),
    "unjoined outside port": (("Context.sysml", CONNECTION, ""),),
}
# G4: the edits in sequence on BASE, each followed by `oracle`, with the one line written before the run.
SEQUENCE = (
    ("part", "added part context.station.logbook WstxProfile::Recordings"),
    ("base", "removed part context.station.logbook WstxProfile::Recordings"),
    ("port", "added port context.operator.spare WstxOperations::Operations"),
    ("base", "removed port context.operator.spare WstxOperations::Operations"),
    ("connection", "added connection context radio.cat <-> station.stations.control"),
    ("base", "removed connection context radio.cat <-> station.stations.control"),
    ("item type", "changed contracts WstxOperations::Operations"),
)
PILOT_REFUSED = (("Station.sysml", "part radioAuthority : RadioAuthority;", "part radioAuthority : MissingAuthority;"),)


def texts(edits=()):
    """BASE with each edit applied once; fails when an edit no longer targets the fixture."""
    files = dict(BASE)
    for key, original, replacement in edits:
        if original is None:
            files[key] = replacement
            continue
        if original not in files[key]:
            raise AssertionError(f"edit no longer targets {key}: {original}")
        files[key] = files[key].replace(original, replacement, 1)
    return files


def write_tree(root, files):
    """A repository-like tree below `root`: the source roots and docs/sysml with `files`."""
    for name in tool.SOURCE_BINDING_ROOTS:
        (root / name).mkdir(parents=True, exist_ok=True)
    models = root / "docs/sysml"
    for key, text in files.items():
        (models / key).parent.mkdir(parents=True, exist_ok=True)
        (models / key).write_text(text, encoding="utf-8")
    return models


def model_paths(models):
    """The files as `check` and `oracle` pass them: Requirements.sysml first."""
    files = tool.model_files(models)
    return [files["Requirements.sysml"], *(path for key, path in files.items() if key != "Requirements.sysml")]


def validate_state(edits):
    with tempfile.TemporaryDirectory() as directory:
        return tool.validate(model_paths(write_tree(Path(directory), texts(edits))), CACHE, inventory=True)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


class OracleCommandTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            futures = {state: pool.submit(validate_state, edits) for state, edits in STATES.items()}
            cls.results = {state: future.result() for state, future in futures.items()}

    def setUp(self):
        folder = tempfile.TemporaryDirectory(prefix="sysml-oracle-test-")
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.models = write_tree(self.root, BASE)
        self.oracle = self.root / "tools/sysml/architecture-oracle.json"
        self.oracle.parent.mkdir(parents=True)

    def inventory(self, state):
        result = self.results[state]
        diagnostics = "\n".join(line for line in result.stdout.splitlines() if not line.startswith(("Reading ", "AST\t")))
        self.assertEqual(result.returncode, 0, diagnostics + result.stderr[-3000:])
        self.assertIn("syntax/name/semantic validation passed", result.stdout)
        return result

    def run_command(self, command, state=None, pilot=False):
        """`command` on the fixture tree, its oracle file at self.oracle and, given `state`,
        the Pilot's result of that model state: (exit code, stdout lines, stderr). With
        `pilot` the real Pilot runs, from the tool's own folder."""
        out, err = io.StringIO(), io.StringIO()
        patches = [mock.patch.object(tool, "MODELS", self.models),
                   mock.patch.object(tool, "FSD", self.root / "docs/absent FSD.md"),
                   mock.patch.object(tool, "ORACLE", self.oracle),
                   mock.patch.object(tool, "canonical_catalog", functools.partial(tool.canonical_catalog, required=REQUIRED))]
        if not pilot:
            patches.append(mock.patch.object(tool, "ROOT", self.root))
        if state is not None:
            patches.append(mock.patch.object(tool, "validate", return_value=self.inventory(state)))
        with contextlib.ExitStack() as stack:
            for patch in patches:
                stack.enter_context(patch)
            stack.enter_context(contextlib.redirect_stdout(out))
            stack.enter_context(contextlib.redirect_stderr(err))
            code = tool.main([command])
        return code, out.getvalue().splitlines(), err.getvalue()

    def changes(self, lines):
        return [line for line in lines if not line.startswith("Architecture oracle ")]

    # G2: the skeleton's form round trip: oracle, check, oracle unchanged, an added connection
    # Proves: CL-014-06; TC-DOC-005
    def test_oracle_then_check_round_trip_on_a_context_root(self):
        self.assertEqual(tool.canonical_catalog(self.models, self.root, required=REQUIRED).keys(), REQUIRED)
        code, lines, err = self.run_command("oracle", "base")
        self.assertEqual(code, 0, err)
        self.assertEqual(lines[-1], "Architecture oracle written: 9 parts, 0 references, 2 contracts, 7 ports, "
                                    "4 connections, 0 bindings")
        written = json.loads(self.oracle.read_text(encoding="utf-8"))
        self.assertEqual(written["about"], tool.ORACLE_ABOUT)
        self.assertEqual(written["root"], "WstxContext::context")
        self.assertEqual({path: entry["type"] for path, entry in written["parts"].items()}, PARTS)
        self.assertEqual(written["ports"], PORTS)
        self.assertEqual(self.changes(lines), sorted(
            [f"added part {path} {typed}" for path, typed in PARTS.items()]
            + [f"added port {path} {typed}" for path, typed in PORTS.items()]
            + ["added connection context operator.console <-> station.operator",
               "added connection context station.stations.catAdapter.radio <-> radio.cat",
               "added connection context.station operator <-> stations.operations",
               "added connection context.station stations.control <-> radioAuthority.requests",
               "changed contracts WstxControl::RadioControl", "changed contracts WstxOperations::Operations",
               "changed root WstxContext::context"]))
        code, lines, err = self.run_command("check", "base")
        self.assertEqual(code, 0, err)
        self.assertIn("Architecture integrity passed: 10 parts, 0 references, 7 ports, 4 connections; "
                      "runtime behavior not proved.", lines)
        before = self.oracle.read_bytes()
        code, lines, err = self.run_command("oracle", "base")
        self.assertEqual((code, lines), (0, ["Architecture oracle unchanged"]), err)
        self.assertEqual(self.oracle.read_bytes(), before)
        code, lines, err = self.run_command("check", "connection")
        self.assertEqual(code, 2)
        self.assertIn("SysML check failed: Architecture integrity: unexpected connection/bypass at context "
                      "radio.cat <-> station.stations.control", err)
        code, lines, err = self.run_command("oracle", "connection")
        self.assertEqual(code, 0, err)
        code, lines, err = self.run_command("check", "connection")
        self.assertEqual(code, 0, err)

    # G4: one edit at a time, each followed by oracle: exactly the line written before the run
    # Proves: CL-014-06; TC-DOC-005
    def test_each_edit_prints_its_change_line(self):
        self.assertEqual(self.run_command("oracle", "base")[0], 0)
        for state, expected in SEQUENCE:
            with self.subTest(state=state, expected=expected):
                code, lines, err = self.run_command("oracle", state)
                self.assertEqual(code, 0, err)
                self.assertEqual(self.changes(lines), [expected])
                self.assertRegex(lines[-1], r"^Architecture oracle written: ")
        self.assertEqual(json.loads(self.oracle.read_text(encoding="utf-8"))["contracts"]["WstxOperations::Operations"],
                         {"items": {"request": ["out", "WstxOperations::OperatorRequest"],
                                    "display": ["in", "WstxOperations::OperatorRequest"]}})

    # G3: a refused model leaves the file as it was; no other command creates or changes it
    # Proves: CL-014-06; TC-DOC-005
    def test_refused_model_and_other_commands_leave_the_file(self):
        for command in ("traces", "markers", "fingerprints", "status"):
            with self.subTest(command=command, file="absent"):
                code, _lines, err = self.run_command(command)
                self.assertEqual(code, 0, err)
                self.assertFalse(self.oracle.exists())
        with self.subTest(case="second authority, no file"):
            code, lines, err = self.run_command("oracle", "second authority")
            self.assertEqual((code, lines), (2, []))
            self.assertIn("SysML check failed: Architecture integrity: shared radio requires one effective authority", err)
            self.assertFalse(self.oracle.exists())
        self.assertEqual(self.run_command("oracle", "base")[0], 0)
        before = digest(self.oracle)
        with self.subTest(case="second authority, file present"):
            code, lines, err = self.run_command("oracle", "second authority")
            self.assertEqual((code, lines), (2, []))
            self.assertEqual(digest(self.oracle), before)
        with self.subTest(case="the Pilot refuses"):
            write_tree(self.root, texts(PILOT_REFUSED))
            code, lines, err = self.run_command("oracle", pilot=True)
            self.assertEqual(code, 2, lines)
            self.assertIn("SysML check failed: Semantic validation failed; architecture oracle not written", err)
            self.assertRegex("\n".join(lines), r"Couldn't resolve reference to \w+ 'MissingAuthority'")
            self.assertNotIn("syntax/name/semantic validation passed", "\n".join(lines))
            self.assertEqual(digest(self.oracle), before)
            write_tree(self.root, BASE)
        for command in ("traces", "markers", "fingerprints", "status", "check"):
            with self.subTest(command=command, file="present"):
                code, _lines, err = self.run_command(command, "base" if command == "check" else None)
                self.assertEqual(code, 0, err)
                self.assertEqual(digest(self.oracle), before)

    # F1: the inventory starts at the context root; the fixed rules by type name, today's messages
    # Proves: CL-014-06; TC-DOC-005
    def test_fixed_rules_on_a_context_root(self):
        records = tool.inventory_records(self.inventory("base").stdout)
        self.assertEqual(records["ROOTPART"], [["WstxContext::context"]])
        paths = [row[0] for kind in ("PART", "REF", "PORT", "ITEM", "EDGE") for row in records.get(kind, [])]
        self.assertTrue(paths)
        self.assertEqual([path for path in paths if path != "context" and not path.startswith("context.")], [])
        tool.fixed_rules(records)
        refused = {
            "second root": "expected one physical deployment",
            "second authority": "shared radio requires one effective authority",
            "duplicate catAdapter": "duplicate or detached catAdapter",
            "station population 1..1": "station population must remain variable",
        }
        for state, message in refused.items():
            with self.subTest(state=state):
                code, lines, err = self.run_command("oracle", state)
                self.assertEqual((code, lines), (2, []))
                self.assertIn("SysML check failed: Architecture integrity: " + message, err)
                self.assertFalse(self.oracle.exists())
        with self.subTest(state="no package-level part usage"):
            with self.assertRaisesRegex(ValueError, "^Architecture integrity: expected one physical deployment$"):
                tool.fixed_rules(tool.inventory_records("AST\tROOTS\t0\n"))

    # X1: an outside part in Context.sysml joined to its owner's port passes; unjoined it is refused
    # Proves: CL-014-06; TC-DOC-005
    def test_outside_part_port_joined_to_a_function(self):
        self.assertEqual(self.run_command("oracle", "base")[0], 0)
        code, lines, err = self.run_command("check", "base")
        self.assertEqual(code, 0, err)
        code, lines, err = self.run_command("oracle", "unjoined outside port")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.changes(lines),
                         ["removed connection context station.stations.catAdapter.radio <-> radio.cat"])
        code, lines, err = self.run_command("check", "unjoined outside port")
        self.assertEqual(code, 2)
        self.assertRegex(err, re.escape("SysML check failed: Architecture integrity: port joined to no function ")
                         + r"context\.radio\.cat\n")


if __name__ == "__main__":
    unittest.main()
