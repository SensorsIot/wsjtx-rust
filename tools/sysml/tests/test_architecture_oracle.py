"""TR-09: `oracle` writes the architecture oracle file from the resolved inventory, after the
Pilot validation and the fixed rules, and prints its changes; `check`'s architecture
comparison then judges the model against the file.

A small fixture tree in the finished form (the deployment `context : ShackContext` in
Context.sysml, the shack and its stations in Shack.sysml, each part definition in its part's
file, the interfaces under interfaces/) is validated once per model state by the real pinned
Pilot, in a bounded pool; the commands then judge the recorded inventories. One `oracle` run
on a model the Pilot refuses calls the Pilot itself. Every expected line is written by hand
from the fixture text.
"""
from concurrent.futures import ThreadPoolExecutor
import contextlib
import hashlib
import importlib.util
import io
import json
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
WORKERS = 2
SHACK = "Shack.sysml"
CONTEXT = "Context.sysml"
SUPERVISOR = "backend/supervisor/Supervisor.sysml"
RECEIVE_CONTROL = "interfaces/internal/ReceiveControl.sysml"
BASE = {
    "Requirements.sysml": '''// Canonical authority: SysML
package WstxRequirements {
}
''',
    "interfaces/internal/StationLink.sysml": '''package WstxStationLink {
    private import ScalarValues::*;
    item def StationRequest { attribute text : String; }
    port def StationLinkPort {
        out item request : StationRequest;
    }
    interface def StationLink {
        end browser : StationLinkPort;
        end station : ~StationLinkPort;
    }
}
''',
    RECEIVE_CONTROL: '''package WstxReceiveControl {
    private import ScalarValues::*;
    item def ReceiveJob { attribute band : String; }
    port def JobPort {
        out item job : ReceiveJob;
    }
    interface def ReceiveControl {
        end station : JobPort;
        end receive : ~JobPort;
    }
}
''',
    "interfaces/external/Cat.sysml": '''package WstxCat {
    private import ScalarValues::*;
    item def CatFrame { attribute bytes : String; }
    port def CatPort {
        out item command : CatFrame;
    }
    interface def Cat {
        end station : CatPort;
        end radio : ~CatPort;
    }
}
''',
    "frontend/BrowserClient.sysml": '''package WstxBrowserClientPart {
    private import WstxStationLink::StationLinkPort;
    part def BrowserClient {
        port station : StationLinkPort;
    }
}
''',
    "backend/web/Web.sysml": '''package WstxWebPart {
    private import WstxStationLink::StationLinkPort;
    part def WebAdapter {
        port client : ~StationLinkPort;
    }
}
''',
    SUPERVISOR: '''package WstxSupervisorPart {
    private import WstxReceiveControl::JobPort;
    part def Supervisor {
        port receive : JobPort;
    }
}
''',
    "backend/receive/Receive.sysml": '''package WstxReceivePart {
    private import WstxReceiveControl::JobPort;
    part def ReceiveService {
        port jobs : ~JobPort;
    }
}
''',
    "backend/profile/Profile.sysml": '''package WstxProfilePart {
    part def Recordings {
        doc /* The recordings of the profile. */
    }
    part def PersistedProfile {
        doc /* The profile. */
    }
}
''',
    "backend/radioControl/RadioControl.sysml": '''package WstxRadioControlPart {
    private import WstxCat::CatPort;
    part def CatAdapter {
        port radio : CatPort;
    }
}
''',
    SHACK: '''package WstxShack {
    private import WstxBrowserClientPart::BrowserClient;
    private import WstxSupervisorPart::Supervisor;
    private import WstxWebPart::WebAdapter;
    private import WstxReceivePart::ReceiveService;
    private import WstxProfilePart::PersistedProfile;
    private import WstxProfilePart::Recordings;
    private import WstxRadioControlPart::CatAdapter;
    private import WstxStationLink::StationLink;
    private import WstxReceiveControl::ReceiveControl;

    part def Shack {
        part stations[*] : Station;
    }
    part def Station {
        part frontend : Frontend;
        part backend : Backend;
        interface browserStation : StationLink
            connect frontend.browsers.station to backend.web.client;
    }
    part def Frontend {
        part browsers[*] : BrowserClient;
    }
    part def Backend {
        part supervisor : Supervisor;
        part web : WebAdapter;
        part receive : ReceiveService;
        part profile : PersistedProfile;
        part catAdapter : CatAdapter;
        interface receiveJobs : ReceiveControl connect supervisor.receive to receive.jobs;
    }
}
''',
    CONTEXT: '''package WstxContext {
    private import WstxShack::Shack;
    private import WstxCat::CatPort;
    private import WstxCat::Cat;

    part def ShackContext {
        part shack : Shack;
        part catRadio {
            port link : ~CatPort;
        }
        interface catLink : Cat connect shack.stations.backend.catAdapter.radio to catRadio.link;
    }

    part context : ShackContext;

    view physicalInterconnection : StandardViewDefinitions::InterconnectionView {
        expose context::shack::*;
    }
}
''',
}
STATIONS = "context.shack.stations"
BACKEND = STATIONS + ".backend"
# The deployment of BASE, written by hand from the fixture text: part path -> type, port path -> port definition.
PARTS = {
    "context.shack": "WstxShack::Shack",
    "context.catRadio": "Parts::Part",
    STATIONS: "WstxShack::Station",
    STATIONS + ".frontend": "WstxShack::Frontend",
    STATIONS + ".frontend.browsers": "WstxBrowserClientPart::BrowserClient",
    BACKEND: "WstxShack::Backend",
    BACKEND + ".supervisor": "WstxSupervisorPart::Supervisor",
    BACKEND + ".web": "WstxWebPart::WebAdapter",
    BACKEND + ".receive": "WstxReceivePart::ReceiveService",
    BACKEND + ".profile": "WstxProfilePart::PersistedProfile",
    BACKEND + ".catAdapter": "WstxRadioControlPart::CatAdapter",
}
PORTS = {
    "context.catRadio.link": "~WstxCat::CatPort",
    STATIONS + ".frontend.browsers.station": "WstxStationLink::StationLinkPort",
    BACKEND + ".web.client": "~WstxStationLink::StationLinkPort",
    BACKEND + ".supervisor.receive": "WstxReceiveControl::JobPort",
    BACKEND + ".receive.jobs": "~WstxReceiveControl::JobPort",
    BACKEND + ".catAdapter.radio": "WstxCat::CatPort",
}

CAT_LINK = "        interface catLink : Cat connect shack.stations.backend.catAdapter.radio to catRadio.link;\n"
BROWSER_STATION = "            connect frontend.browsers.station to backend.web.client;\n"
EXPOSE = "        expose context::shack::*;\n"
# One edit of BASE per state: (file key, original, replacement).
STATES = {
    "base": (),
    "part": ((SHACK, "        part catAdapter : CatAdapter;\n",
              "        part catAdapter : CatAdapter;\n        part logbook : Recordings;\n"),),
    "port": ((SUPERVISOR, "        port receive : JobPort;\n", "        port receive : JobPort;\n        port spare : JobPort;\n"),),
    "connection": ((SHACK, BROWSER_STATION, BROWSER_STATION + "        interface spareJobs : ReceiveControl\n"
                                                              "            connect backend.supervisor.receive to backend.receive.jobs;\n"),),
    "item type": ((RECEIVE_CONTROL, "        out item job : ReceiveJob;\n", "        out item job : ReceivePlan;\n"),
                  (RECEIVE_CONTROL, "    port def JobPort", "    item def ReceivePlan { attribute mode : String; }\n"
                                                           "    port def JobPort")),
    "second deployment": ((CONTEXT, "    part context : ShackContext;\n",
                           "    part context : ShackContext;\n    part spareContext : ShackContext;\n"),),
    "view part": ((CONTEXT, EXPOSE, EXPOSE + "        part inventedStation : WstxShack::Station;\n"),),
    "unjoined outside port": ((CONTEXT, CAT_LINK, ""),),
}
# The edits in sequence on BASE, each followed by `oracle`, with the one line written before the run.
SEQUENCE = (
    ("part", f"added part {BACKEND}.logbook WstxProfilePart::Recordings"),
    ("base", f"removed part {BACKEND}.logbook WstxProfilePart::Recordings"),
    ("port", f"added port {BACKEND}.supervisor.spare WstxReceiveControl::JobPort"),
    ("base", f"removed port {BACKEND}.supervisor.spare WstxReceiveControl::JobPort"),
    ("connection", f"added connection {STATIONS} backend.supervisor.receive <-> backend.receive.jobs"),
    ("base", f"removed connection {STATIONS} backend.supervisor.receive <-> backend.receive.jobs"),
    ("item type", "changed contracts WstxReceiveControl::JobPort"),
)
PILOT_REFUSED = ((SHACK, "        part receive : ReceiveService;\n", "        part receive : MissingService;\n"),)


def texts(edits=()):
    """BASE with each edit applied once; fails when an edit does not target the fixture."""
    files = dict(BASE)
    for key, original, replacement in edits:
        if files[key].count(original) != 1:
            raise AssertionError(f"edit does not target {key} once: {original}")
        files[key] = files[key].replace(original, replacement, 1)
    return files


def write_tree(root, files):
    """A repository-like tree below `root`: the source roots and docs/sysml with `files`."""
    for name in tool.SOURCE_BINDING_ROOTS:
        (root / name).mkdir(parents=True, exist_ok=True)
    models = root / "docs/sysml"
    for key, text in files.items():
        (models / key).parent.mkdir(parents=True, exist_ok=True)
        (models / key).write_text(text, encoding="utf-8", newline="\n")
    return models


def validate_state(edits):
    with tempfile.TemporaryDirectory() as directory:
        _keys, paths = tool.model_keys(write_tree(Path(directory), texts(edits)))
        return tool.validate(paths, CACHE, inventory=True)


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
                   mock.patch.object(tool, "ORACLE", self.oracle)]
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

    def compare(self, state):
        """`check`'s architecture comparison of the state against the oracle file."""
        with mock.patch.object(tool, "ORACLE", self.oracle):
            return tool.architecture_integrity(self.inventory(state).stdout)

    def changes(self, lines):
        return [line for line in lines if not line.startswith("Architecture oracle ")]

    def test_oracle_then_check_round_trip(self):
        """TR-09: `oracle` writes the deployment and prints each addition; the comparison
        passes; `oracle` again leaves the file; an added connection is refused until
        `oracle` lists it."""
        code, lines, err = self.run_command("oracle", "base")
        self.assertEqual(code, 0, err)
        self.assertEqual(lines[-1], "Architecture oracle written: 11 parts, 0 references, 3 contracts, 6 ports, "
                                    "3 connections, 0 bindings")
        written = json.loads(self.oracle.read_text(encoding="utf-8"))
        self.assertEqual(written["about"], tool.ORACLE_ABOUT)
        self.assertEqual(written["root"], "WstxContext::context")
        self.assertEqual({path: entry["type"] for path, entry in written["parts"].items()}, PARTS)
        self.assertEqual(written["ports"], PORTS)
        self.assertEqual(self.changes(lines), sorted(
            [f"added part {path} {typed}" for path, typed in PARTS.items()]
            + [f"added port {path} {typed}" for path, typed in PORTS.items()]
            + [f"added connection {BACKEND} supervisor.receive <-> receive.jobs",
               f"added connection {STATIONS} frontend.browsers.station <-> backend.web.client",
               "added connection context shack.stations.backend.catAdapter.radio <-> catRadio.link",
               "changed contracts WstxCat::CatPort", "changed contracts WstxReceiveControl::JobPort",
               "changed contracts WstxStationLink::StationLinkPort", "changed root WstxContext::context"]))
        self.assertEqual(self.compare("base"), {"parts": 12, "references": 0, "ports": 6, "connections": 3})
        before = self.oracle.read_bytes()
        code, lines, err = self.run_command("oracle", "base")
        self.assertEqual((code, lines), (0, ["Architecture oracle unchanged"]), err)
        self.assertEqual(self.oracle.read_bytes(), before)
        with self.assertRaisesRegex(ValueError, "^" + re.escape(f"Architecture integrity: unexpected connection/bypass at {STATIONS} "
                                                                "backend.receive.jobs <-> backend.supervisor.receive") + "$"):
            self.compare("connection")
        code, lines, err = self.run_command("oracle", "connection")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.compare("connection"), {"parts": 12, "references": 0, "ports": 6, "connections": 4})

    def test_each_edit_prints_its_change_line(self):
        """TR-09: one edit at a time, each followed by `oracle`: exactly the line written before the run."""
        self.assertEqual(self.run_command("oracle", "base")[0], 0)
        for state, expected in SEQUENCE:
            with self.subTest(state=state, expected=expected):
                code, lines, err = self.run_command("oracle", state)
                self.assertEqual(code, 0, err)
                self.assertEqual(self.changes(lines), [expected])
                self.assertRegex(lines[-1], r"^Architecture oracle written: ")
        self.assertEqual(json.loads(self.oracle.read_text(encoding="utf-8"))["contracts"]["WstxReceiveControl::JobPort"],
                         {"items": {"job": ["out", "WstxReceiveControl::ReceivePlan"]}})

    def test_refused_model_leaves_the_file(self):
        """TR-09: a model the fixed rules or the Pilot refuse leaves the oracle file as it was,
        absent or present; no other command creates or changes it."""
        refused = {"second deployment": "expected one physical deployment",
                   "view part": "views may expose, not create runtime parts/connections"}
        for command in ("markers", "fingerprints", "status"):
            with self.subTest(command=command, file="absent"):
                code, _lines, err = self.run_command(command)
                self.assertEqual(code, 0, err)
                self.assertFalse(self.oracle.exists())
        for state, message in refused.items():
            with self.subTest(state=state, file="absent"):
                code, lines, err = self.run_command("oracle", state)
                self.assertEqual((code, lines), (2, []))
                self.assertIn("SysML check failed: Architecture integrity: " + message, err)
                self.assertFalse(self.oracle.exists())
        self.assertEqual(self.run_command("oracle", "base")[0], 0)
        before = digest(self.oracle)
        for state, message in refused.items():
            with self.subTest(state=state, file="present"):
                code, lines, err = self.run_command("oracle", state)
                self.assertEqual((code, lines), (2, []))
                self.assertIn("SysML check failed: Architecture integrity: " + message, err)
                self.assertEqual(digest(self.oracle), before)
        with self.subTest(case="the Pilot refuses"):
            write_tree(self.root, texts(PILOT_REFUSED))
            code, lines, err = self.run_command("oracle", pilot=True)
            self.assertEqual(code, 2, lines)
            self.assertIn("SysML check failed: Semantic validation failed; architecture oracle not written", err)
            self.assertRegex("\n".join(lines), r"Couldn't resolve reference to \w+ 'MissingService'")
            self.assertNotIn("syntax/name/semantic validation passed", "\n".join(lines))
            self.assertEqual(digest(self.oracle), before)
            write_tree(self.root, BASE)
        for command in ("markers", "fingerprints", "status"):
            with self.subTest(command=command, file="present"):
                code, _lines, err = self.run_command(command)
                self.assertEqual(code, 0, err)
                self.assertEqual(digest(self.oracle), before)
        self.compare("base")
        self.assertEqual(digest(self.oracle), before)

    def test_fixed_rules_on_the_deployment(self):
        """TR-09: the inventory starts at the one package-level part usage; the fixed rules
        refuse none, two, or a view that adds a part."""
        records = tool.inventory_records(self.inventory("base").stdout)
        self.assertEqual(records["ROOTPART"], [["WstxContext::context"]])
        paths = [row[0] for kind in ("PART", "REF", "PORT", "ITEM", "EDGE") for row in records.get(kind, [])]
        self.assertTrue(paths)
        self.assertEqual([path for path in paths if path != "context" and not path.startswith("context.")], [])
        tool.fixed_rules(records)
        with self.assertRaisesRegex(ValueError, "^Architecture integrity: expected one physical deployment$"):
            tool.fixed_rules(tool.inventory_records(self.inventory("second deployment").stdout))
        with self.assertRaisesRegex(ValueError, "^Architecture integrity: views may expose, not create runtime parts/connections$"):
            tool.fixed_rules(tool.inventory_records(self.inventory("view part").stdout))
        with self.assertRaisesRegex(ValueError, "^Architecture integrity: expected one physical deployment$"):
            tool.fixed_rules(tool.inventory_records("AST\tROOTS\t0\n"))

    def test_outside_port_joined_to_a_function(self):
        """TR-09: an outside thing's port joined to a function passes; unjoined, `oracle`
        prints the removed connection and the comparison refuses the port."""
        self.assertEqual(self.run_command("oracle", "base")[0], 0)
        self.compare("base")
        code, lines, err = self.run_command("oracle", "unjoined outside port")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.changes(lines),
                         ["removed connection context shack.stations.backend.catAdapter.radio <-> catRadio.link"])
        with self.assertRaisesRegex(ValueError, "^" + re.escape("Architecture integrity: port joined to no function "
                                                                "context.catRadio.link") + "$"):
            self.compare("unjoined outside port")


if __name__ == "__main__":
    unittest.main()
