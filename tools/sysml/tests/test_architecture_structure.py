"""CL-014-18 (#186): the target structure checks that read the resolved deployment (rule 3
for connections and items, rules 4 to 7), and the pending list as `check` reads it.

A fixture tree in the target form (root `context` in Context.sysml, each part in its own
part folder, interfaces under interfaces/internal/ and interfaces/external/, composition
in Station.sysml) passes every rule. Each case edits it once; the real pinned Pilot
validates each model state once, in a bounded pool, and `check` then judges the recorded
inventory with the architecture oracle comparison left out (it is TC-DOC-005's). The
expected fault lines are written by hand from the rule text and the fixture's paths.
"""
from concurrent.futures import ThreadPoolExecutor
import contextlib
import functools
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("architecture_structure_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CACHE = Path.home() / ".cache/wsjtx-rust/sysml-tools"
WORKERS = max(1, min(4, os.cpu_count() or 1))
REQUIRED = {"FR-001", "CL-003-01", "TC-001-001"}
SP = "Station.sysml"
CTX = "Context.sysml"
RECEIVE = "backend/receive/Receive.sysml"
FRONTEND = "frontend/Frontend.sysml"
RECEIVE_CONTROL = "interfaces/internal/ReceiveControl.sysml"

BASE = {
    "Requirements.sysml": '''// Canonical authority: SysML
package WstxRequirements {
    private import RequirementDerivation::*;
    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }
    requirement 'FR-001' {
        subject station;
    }
    requirement 'CL-003-01' {
        subject station;
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    verification 'TC-001-001' {
        attribute automation : AutomationState = AutomationState::planned;
        objective { verify 'CL-003-01'; }
    }
    #derivation connection {
        end #original ::> 'FR-001';
        end #derive ::> 'CL-003-01';
    }
}
''',
    "shared/ModelBindings.sysml": '''package WstxModelBindings {
    private import ScalarValues::*;
    metadata def FollowsSource { attribute reference : String; }
}
''',
    "interfaces/internal/StationLink.sysml": '''package WstxStationLink {
    private import ScalarValues::*;
    item def OperatorRequest { attribute text : String; }
    item def StationState { attribute text : String; }
    port def LinkPort {
        out item request : OperatorRequest;
        in item status : StationState;
    }
    interface def StationLink {
        end client : LinkPort;
        end server : ~LinkPort;
    }
}
''',
    "interfaces/external/OperatorInteraction.sysml": '''package WstxOperatorInteraction {
    private import ScalarValues::*;
    item def Gesture { attribute key : String; }
    item def View { attribute text : String; }
    port def ScreenPort {
        in item gesture : Gesture;
        out item display : View;
    }
    interface def OperatorInteraction {
        end person : ~ScreenPort;
        end screen : ScreenPort;
    }
}
''',
    RECEIVE_CONTROL: '''package WstxReceiveControl {
    private import ScalarValues::*;
    item def ReceiveCommand { attribute band : String; }
    port def ReceiveCommandPort { out item command : ReceiveCommand; }
    interface def ReceiveControl {
        end commanding : ReceiveCommandPort;
        end commanded : ~ReceiveCommandPort;
    }
}
''',
    "interfaces/internal/QsoControl.sysml": '''package WstxQsoControl {
    private import ScalarValues::*;
    item def QsoProgress { attribute step : Integer; }
    port def ProgressPort { out item progress : QsoProgress; }
    interface def QsoControl {
        end commanding : ProgressPort;
        end commanded : ~ProgressPort;
    }
}
''',
    "interfaces/internal/OperatingChain.sysml": '''package WstxOperatingChain {
    private import ScalarValues::*;
    private import WstxQsoControl::*;
    item def Ranked { attribute call : String; }
    item def TransmitOrder { attribute text : String; }
    port def RankedPort { out item ranked : Ranked; }
    port def OrderPort { out item order : TransmitOrder; }
    interface def RankedTargets { end ranking : RankedPort; end automation : ~RankedPort; }
    interface def TargetChoice { end chooser : ProgressPort; end chosen : ~ProgressPort; }
    interface def TransmitRequest { end requester : OrderPort; end transmitter : ~OrderPort; }
}
''',
    "interfaces/internal/Keying.sysml": '''package WstxKeying {
    private import ScalarValues::*;
    item def Key { attribute down : Boolean; }
    port def KeyingPort { out item key : Key; }
    interface def Keying { end keyer : KeyingPort; end keyed : ~KeyingPort; }
}
''',
    "interfaces/internal/RadioControl.sysml": '''package WstxRadioControlInterface {
    private import WstxKeying::*;
    interface def RadioControl { end commanding : KeyingPort; end commanded : ~KeyingPort; }
}
''',
    "interfaces/external/Cat.sysml": '''package WstxCat {
    private import ScalarValues::*;
    item def Frame { attribute bytes : String; }
    port def CatPort { out item command : Frame; }
    interface def Cat { end driver : CatPort; end radio : ~CatPort; }
}
''',
    "backend/station/StationService.sysml": '''package WstxStationService {
    private import WstxReceiveControl::*;
    part def StationService { port receive : ReceiveCommandPort; }
}
''',
    "backend/web/Web.sysml": '''package WstxWeb {
    private import WstxStationLink::*;
    part def Web { port link : ~LinkPort; }
}
''',
    RECEIVE: '''package WstxReceive {
    private import WstxReceiveControl::*;
    private import WstxStationLink::*;
    part def Receive {
        port control : ~ReceiveCommandPort;
    }
}
''',
    "backend/operating/ranking/Ranking.sysml": '''package WstxRanking {
    private import WstxOperatingChain::*;
    private import WstxQsoControl::*;
    part def Ranking {
        port next : RankedPort;
    }
}
''',
    "backend/operating/auto/Auto.sysml": '''package WstxAuto {
    private import WstxOperatingChain::*;
    private import WstxQsoControl::*;
    part def Auto {
        port ranked : ~RankedPort;
        port choice : ProgressPort;
    }
}
''',
    "backend/operating/qso/Qso.sysml": '''package WstxQso {
    private import WstxOperatingChain::*;
    private import WstxQsoControl::*;
    part def Qso {
        port choice : ~ProgressPort;
        port transmit : OrderPort;
    }
}
''',
    "backend/operating/transmit/Transmit.sysml": '''package WstxTransmit {
    private import WstxOperatingChain::*;
    private import WstxKeying::*;
    part def Transmit {
        port request : ~OrderPort;
        port keying : KeyingPort;
    }
}
''',
    "backend/radioControl/RadioControl.sysml": '''package WstxRadioControl {
    private import WstxKeying::*;
    private import WstxCat::*;
    part def RadioControlFunction { port keying : ~KeyingPort; }
    part def RustRadioDriver { port radio : CatPort; }
}
''',
    "backend/profile/Profile.sysml": "package WstxProfile { part def PersistedProfile; }\n",
    "backend/audio/Audio.sysml": "package WstxAudio { part def AudioDeviceAdapter; }\n",
    "backend/authority/Authority.sysml": "package WstxAuthority { part def RadioAuthority; }\n",
    FRONTEND: '''package WstxFrontend {
    private import WstxStationLink::*;
    private import WstxOperatorInteraction::*;
    part def BrowserClient {
        port link : LinkPort;
        port screen : ScreenPort;
    }
    part def Frontend {
        part browsers[*] : BrowserClient;
    }
}
''',
    SP: '''package WstxArchitecture {
    private import WstxStationService::*;
    private import WstxWeb::*;
    private import WstxReceive::*;
    private import WstxRanking::*;
    private import WstxAuto::*;
    private import WstxQso::*;
    private import WstxTransmit::*;
    private import WstxRadioControl::*;
    private import WstxProfile::*;
    private import WstxAudio::*;
    private import WstxAuthority::*;
    private import WstxFrontend::*;
    private import WstxStationLink::*;
    private import WstxReceiveControl::*;
    private import WstxOperatingChain::*;
    private import WstxKeying::*;
    private import WstxQsoControl::*;
    private import WstxRadioControlInterface::*;
    part def StationProcess {
        part station : StationService;
        part web : Web;
        part receive : Receive;
        part ranking : Ranking;
        part auto : Auto;
        part qso : Qso;
        part transmit : Transmit;
        part radioControl : RadioControlFunction;
        part profile : PersistedProfile;
        part audioAdapter : AudioDeviceAdapter;
        part catAdapter : RustRadioDriver;
        interface commandReceive : ReceiveControl connect station.receive to receive.control;
        interface ranked : RankedTargets connect ranking.next to auto.ranked;
        interface chosen : TargetChoice connect auto.choice to qso.choice;
        interface orders : TransmitRequest connect qso.transmit to transmit.request;
        interface keyed : Keying connect transmit.keying to radioControl.keying;
    }
    part def Station {
        part frontend : Frontend;
        part stations[*] : StationProcess;
        part radioAuthority : RadioAuthority;
        interface link : StationLink connect frontend.browsers.link to stations.web.link;
    }
}
''',
    CTX: '''package WstxContext {
    private import ScalarValues::*;
    private import WstxArchitecture::*;
    private import WstxOperatorInteraction::*;
    private import WstxCat::*;
    private import WstxModelBindings::*;
    part def Operator { port screen : ~ScreenPort; }
    part def CatRadio {
        @FollowsSource { reference = "IC-7300 CI-V reference guide"; }
        port cat : ~CatPort;
        port spare : ~CatPort;
        attribute baud : Integer;
        attribute address : Integer;
    }
    part context {
        part station : Station;
        part operator : Operator;
        part catRadio : CatRadio;
        interface operating : OperatorInteraction connect operator.screen to station.frontend.browsers.screen;
        interface cat : Cat connect station.stations.catAdapter.radio to catRadio.cat;
        bind catRadio.baud = catRadio.address;
    }
}
''',
}

COMMAND = "interface commandReceive : ReceiveControl connect station.receive to receive.control;"
ORDERED = "interface orders : TransmitRequest connect qso.transmit to transmit.request;"
OPERATING = "        interface operating : OperatorInteraction connect operator.screen to station.frontend.browsers.screen;\n"
CAT_LINK = "interface cat : Cat connect station.stations.catAdapter.radio to catRadio.cat;"
CAT_LAST = "        attribute address : Integer;\n"
CONTEXT_PART = "    part context {"
LONELY = ((CTX, "        part catRadio : CatRadio;\n", "        part catRadio : CatRadio;\n        part lonely : Lonely;\n"),
          (CTX, CONTEXT_PART, "    part def Lonely { attribute weight : Integer; }\n" + CONTEXT_PART))
LINK_AT_RECEIVE = (RECEIVE, "        port control : ~ReceiveCommandPort;\n",
                   "        port control : ~ReceiveCommandPort;\n        port link : ~LinkPort;\n")
STATIONS = "context.station.stations"

# One edit list of BASE per model state; each state is validated once by the Pilot.
STATES = {
    "base": (),
    # S3
    "untyped connection": ((SP, COMMAND, COMMAND + "\n        connect station.receive to receive.control;"),),
    "interface outside interfaces": (
        (RECEIVE, "    part def Receive", "    interface def LocalLink {\n        end commanding : ReceiveCommandPort;\n"
                                          "        end commanded : ~ReceiveCommandPort;\n    }\n    part def Receive"),
        (SP, "commandReceive : ReceiveControl", "commandReceive : LocalLink")),
    "interface without items": ((RECEIVE_CONTROL, "    interface def ReceiveControl",
                                 "    port def EmptyPort;\n    interface def Bare {\n        end a : EmptyPort;\n"
                                 "        end b : ~EmptyPort;\n    }\n    interface def ReceiveControl"),),
    "untyped item": ((RECEIVE_CONTROL, "out item command : ReceiveCommand;", "out item command;"),),
    "featureless item": ((RECEIVE_CONTROL, "out item command : ReceiveCommand;", "out item command : Empty;"),
                         (RECEIVE_CONTROL, "    item def ReceiveCommand", "    item def Empty;\n    item def ReceiveCommand")),
    # S4
    "type with a part": ((CTX, CAT_LAST, CAT_LAST + "        part board;\n"),),
    "type with an action": ((CTX, CAT_LAST, CAT_LAST + "        action poll;\n"),),
    "type with a state": ((CTX, CAT_LAST, CAT_LAST + "        state mode;\n"),),
    "usage with a part": ((CTX, "part catRadio : CatRadio;", "part catRadio : CatRadio { part extra; }"),),
    "requirement on the outside part": ((CTX, CONTEXT_PART, "    requirement def RadioRule { subject radio : CatRadio; }\n" + CONTEXT_PART),),
    # S5
    "reversed command": ((SP, COMMAND, "interface commandReceive : ReceiveControl connect receive.control to station.receive;"),),
    "keying by RadioControl": ((SP, "keyed : Keying", "keyed : RadioControl"),),
    "auto to qso by QsoControl": ((SP, "chosen : TargetChoice", "chosen : QsoControl"),),
    "no station service": ((SP, "        part station : StationService;\n", ""), (SP, "        " + COMMAND + "\n", "")),
    # S6
    "second internal port": ((FRONTEND, "        port screen : ScreenPort;\n", "        port screen : ScreenPort;\n        port control : ReceiveCommandPort;\n"),
                             (FRONTEND, "    private import WstxOperatorInteraction::*;\n",
                              "    private import WstxOperatorInteraction::*;\n    private import WstxReceiveControl::*;\n")),
    "link to receive": (LINK_AT_RECEIVE, (SP, "to stations.web.link;", "to stations.receive.link;")),
    "third port to an outside part": (
        (FRONTEND, "        port screen : ScreenPort;\n", "        port screen : ScreenPort;\n        port radio : CatPort;\n"),
        (FRONTEND, "    private import WstxOperatorInteraction::*;\n", "    private import WstxOperatorInteraction::*;\n    private import WstxCat::*;\n"),
        (CTX, CAT_LINK, CAT_LINK + "\n        interface spare : Cat connect station.frontend.browsers.radio to catRadio.spare;")),
    "frontend part to receive": (
        LINK_AT_RECEIVE,
        (FRONTEND, "    part def Frontend {\n", "    part def Helper { port link : LinkPort; }\n    part def Frontend {\n        part helper : Helper;\n"),
        (SP, "to stations.web.link;", "to stations.web.link;\n        interface sneak : StationLink connect frontend.helper.link to stations.receive.link;")),
    "no operator": ((CTX, "        part operator : Operator;\n", ""), (CTX, OPERATING, "")),
    # S7
    "auto to transmit": (("backend/operating/auto/Auto.sysml", "        port choice : ProgressPort;\n",
                          "        port choice : ProgressPort;\n        port order : OrderPort;\n"),
                         (SP, ORDERED, ORDERED + "\n        interface skip : TransmitRequest connect auto.order to transmit.request;")),
    "ranking to qso": (("backend/operating/ranking/Ranking.sysml", "        port next : RankedPort;\n",
                        "        port next : RankedPort;\n        port choice : ProgressPort;\n"),
                       (SP, ORDERED, ORDERED + "\n        interface jump : TargetChoice connect ranking.choice to qso.choice;")),
    "qso to auto": (("backend/operating/qso/Qso.sysml", "        port transmit : OrderPort;\n",
                     "        port transmit : OrderPort;\n        port back : RankedPort;\n"),
                    (SP, ORDERED, ORDERED + "\n        interface back : RankedTargets connect qso.back to auto.ranked;")),
    "no ranking": ((SP, "        part ranking : Ranking;\n", ""),
                   (SP, "        interface ranked : RankedTargets connect ranking.next to auto.ranked;\n", "")),
    # X2, and two faults of two rules (S11)
    "lonely": LONELY,
    "two faults": LONELY + ((CTX, CONTEXT_PART, "    dependency watch from CatRadio to Operator;\n" + CONTEXT_PART),),
}


def texts(edits=()):
    """BASE with each edit applied once; fails when an edit no longer targets the fixture."""
    files = dict(BASE)
    for key, original, replacement in edits:
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


def validate_state(edits):
    with tempfile.TemporaryDirectory() as directory:
        files = tool.model_files(write_tree(Path(directory), texts(edits)))
        paths = [files["Requirements.sysml"], *(path for key, path in files.items() if key != "Requirements.sysml")]
        return tool.validate(paths, CACHE, inventory=True)


def line_of(state, key, needle):
    text = texts(STATES[state])[key]
    if text.count(needle) != 1:
        raise AssertionError(f"needle not found once: {needle}")
    return text[:text.index(needle)].count("\n") + 1


class StructureCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            futures = {state: pool.submit(validate_state, edits) for state, edits in STATES.items()}
            cls.results = {state: future.result() for state, future in futures.items()}

    def check(self, state, pending=None, text=None):
        """`check` on the model state with the pending list `pending` (or the file text
        `text`; neither: no list file): (exit code, stdout lines, stderr)."""
        result = self.results[state]
        diagnostics = "\n".join(line for line in result.stdout.splitlines() if not line.startswith(("Reading ", "AST\t")))
        self.assertEqual(result.returncode, 0, diagnostics + result.stderr[-3000:])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            models = write_tree(root, texts(STATES[state]))
            listing = root / "tools/sysml/pending-structure.json"
            listing.parent.mkdir(parents=True)
            if pending is not None:
                text = json.dumps(pending)
            if text is not None:
                listing.write_text(text, encoding="utf-8")
            out, err = io.StringIO(), io.StringIO()
            patches = [mock.patch.object(tool, "MODELS", models), mock.patch.object(tool, "ROOT", root),
                       mock.patch.object(tool, "FSD", root / "docs/absent FSD.md"),
                       mock.patch.object(tool, "PENDING", listing),
                       mock.patch.object(tool, "canonical_catalog", functools.partial(tool.canonical_catalog, required=REQUIRED)),
                       mock.patch.object(tool, "validate", return_value=result),
                       mock.patch.object(tool, "architecture_integrity", return_value={"parts": 0})]
            with contextlib.ExitStack() as stack:
                for patch in patches:
                    stack.enter_context(patch)
                stack.enter_context(contextlib.redirect_stdout(out))
                stack.enter_context(contextlib.redirect_stderr(err))
                code = tool.main(["check"])
        return code, out.getvalue().splitlines(), err.getvalue()

    def faults(self, state, elements=None, files=()):
        """The fault lines of `check` on the state, [] when it passes with the passed line."""
        code, lines, err = self.check(state, {"files": list(files), "elements": elements or {}})
        faults = [line for line in lines if line.startswith("Structure rule ")]
        if code == 0:
            self.assertEqual(faults, [])
            self.assertRegex(lines[-1], r"^Structure checks passed: ")
            return []
        self.assertEqual(code, 2, err)
        self.assertIn(f"SysML check failed: {len(faults)} structure faults", err)
        self.assertFalse([line for line in lines if line.startswith("Structure checks passed")])
        return faults

    def assert_cases(self, cases):
        for state, expected in cases.items():
            with self.subTest(state=state):
                self.assertEqual(self.faults(state), expected)

    # The fixture in target form passes every rule, with every rule applied.
    # Proves: CL-014-18; TC-DOC-016
    def test_target_form_fixture_passes_with_the_deployment_rules_on(self):
        code, lines, err = self.check("base", {"files": [], "elements": {}})
        self.assertEqual(code, 0, err)
        self.assertEqual(lines[-1], f"Structure checks passed: {len(BASE)} files in target form, 0 files and 0 elements "
                                    "pending; deployment rules on")

    # S3: every connection typed by an interface of interfaces/; every interface item typed by a definition with a feature
    # Proves: CL-014-18; TC-DOC-016
    def test_rule_3_connections_and_items(self):
        interface = line_of("base", RECEIVE_CONTROL, "interface def ReceiveControl")
        self.assert_cases({
            "untyped connection": [f"Structure rule 3: untyped connection: {STATIONS} station.receive -> receive.control"],
            "interface outside interfaces": [f"Structure rule 3: connection typed by an interface outside interfaces/: "
                                             f"{STATIONS} station.receive -> receive.control"],
            "interface without items": [f"Structure rule 3: interface Bare without items: {RECEIVE_CONTROL}:"
                                        f"{line_of('interface without items', RECEIVE_CONTROL, 'interface def Bare')}"],
            "untyped item": [f"Structure rule 3: interface ReceiveControl item command untyped: {RECEIVE_CONTROL}:{interface}"],
            "featureless item": [f"Structure rule 3: interface ReceiveControl item command typed by featureless "
                                 f"WstxReceiveControl::Empty: {RECEIVE_CONTROL}:"
                                 f"{line_of('featureless item', RECEIVE_CONTROL, 'interface def ReceiveControl')}"],
        })
        self.assertIn("bind catRadio.baud = catRadio.address;", BASE[CTX])
        with self.subTest("the placeholder Empty listed under elements"):
            self.assertEqual(self.faults("featureless item", {"WstxReceiveControl::Empty": "receive"}), [])
        with self.subTest("Station.sysml listed: the connection faults pass"):
            for state in ("untyped connection", "interface outside interfaces"):
                self.assertEqual(self.faults(state, files=[SP]), [])

    # S4: an outside part has ports and attributes only and is no requirement's subject
    # Proves: CL-014-18; TC-DOC-016
    def test_rule_4_outside_parts_are_black_boxes(self):
        self.assert_cases({
            "base": [],
            "type with a part": ["Structure rule 4: outside part with PartUsage board in its type: context.catRadio"],
            "type with an action": ["Structure rule 4: outside part with ActionUsage poll in its type: context.catRadio"],
            "type with a state": ["Structure rule 4: outside part with StateUsage mode in its type: context.catRadio"],
            "usage with a part": ["Structure rule 4: outside part with PartUsage extra: context.catRadio"],
            "requirement on the outside part": ["Structure rule 4: subject of requirement WstxContext::RadioRule: context.catRadio"],
        })

    # S5: a control interface has the station service at its commanding end
    # Proves: CL-014-18; TC-DOC-016
    def test_rule_5_commands_come_from_the_station_service(self):
        self.assert_cases({
            "base": [],
            "reversed command": [f"Structure rule 5: control interface ReceiveControl not commanded by the station service: "
                                 f"{STATIONS} receive.control -> station.receive"],
            "keying by RadioControl": [f"Structure rule 5: control interface RadioControl not commanded by the station "
                                       f"service: {STATIONS} transmit.keying -> radioControl.keying"],
            "auto to qso by QsoControl": [f"Structure rule 5: control interface QsoControl not commanded by the station "
                                          f"service: {STATIONS} auto.choice -> qso.choice"],
            "no station service": [f"Structure rule 5: missing role part: {STATIONS}.station"],
        })

    # S6: the browser client has one internal port, to web, and its operator port; the frontend connects nowhere else
    # Proves: CL-014-18; TC-DOC-016
    def test_rule_6_browser_client_and_frontend(self):
        browsers = "context.station.frontend.browsers"
        self.assert_cases({
            "base": [],
            "second internal port": [f"Structure rule 6: browser client with 2 ports typed by internal interfaces: {browsers}",
                                     f"Structure rule 6: internal port not typed by StationLink: {browsers}.control"],
            "link to receive": [
                f"Structure rule 6: frontend connection ends at {STATIONS}.receive.link: "
                "context.station frontend.browsers.link -> stations.receive.link",
                f"Structure rule 6: StationLink port not connected to web: {browsers}.link"],
            "third port to an outside part": [
                "Structure rule 6: frontend connection ends at context.catRadio.spare: "
                "context station.frontend.browsers.radio -> catRadio.spare",
                f"Structure rule 6: port of an interface the browser client may not have: {browsers}.radio"],
            "frontend part to receive": [
                f"Structure rule 6: frontend connection ends at {STATIONS}.receive.link: "
                "context.station frontend.helper.link -> stations.receive.link"],
            "no operator": ["Structure rule 6: missing role part: context.operator"],
        })

    # S7: the operating chain connects only neighbours, downward
    # Proves: CL-014-18; TC-DOC-016
    def test_rule_7_operating_chain_commands_only_downward(self):
        self.assert_cases({
            "base": [],
            "auto to transmit": [f"Structure rule 7: auto to transmit outside the operating chain: {STATIONS} auto.order -> transmit.request"],
            "ranking to qso": [f"Structure rule 7: ranking to qso outside the operating chain: {STATIONS} ranking.choice -> qso.choice"],
            "qso to auto": [f"Structure rule 7: qso to auto outside the operating chain: {STATIONS} qso.back -> auto.ranked"],
            "no ranking": [f"Structure rule 7: missing role part: {STATIONS}.ranking"],
        })

    # X2: an outside part joined to no function is refused unless listed under its owner
    # Proves: CL-014-03, CL-014-18; TC-DOC-005, TC-DOC-016
    def test_outside_part_without_connection_needs_the_pending_list(self):
        self.assertEqual(self.faults("lonely"), ["Structure rule 4: outside part joined to no function: context.lonely"])
        self.assertEqual(self.faults("lonely", {"WstxContext::context::lonely": "station"}), [])

    # S11: the pending list is refused whole; faults are listed in rule, key and line order
    # Proves: CL-014-18; TC-DOC-016
    def test_pending_list_is_refused_whole_and_faults_are_sorted(self):
        refused = {
            "missing": None,
            "empty file": "",
            "not JSON": "{files: []}",
            "a key twice": json.dumps({"files": [RECEIVE, RECEIVE], "elements": {}}),
            "a name twice": '{"files": [], "elements": {"WstxContext::CatRadio": "radioControl", '
                            '"WstxContext::CatRadio": "radioControl"}}',
            "an unknown key": json.dumps({"files": ["backend/receive/Gone.sysml"], "elements": {}}),
            "a renamed file's old key": json.dumps({"files": ["backend/receive/OldReceive.sysml"], "elements": {}}),
            "a name resolving to nothing": json.dumps({"files": [], "elements": {"WstxContext::Missing": "station"}}),
            "an element with an empty owner": json.dumps({"files": [], "elements": {"WstxContext::CatRadio": " "}}),
            "files naming Context.sysml": json.dumps({"files": [CTX], "elements": {}}),
            "files naming interfaces/internal/X.sysml": json.dumps({"files": ["interfaces/internal/X.sysml"], "elements": {}}),
        }
        for label, text in refused.items():
            with self.subTest(label):
                code, lines, err = self.check("base", text=text)
                self.assertEqual(code, 2, lines)
                self.assertIn("SysML check failed: Pending structure list: ", err)
                self.assertEqual([line for line in lines if "passed" in line], [])
        with self.subTest("element entries inside Context.sysml and interfaces/ are accepted"):
            code, lines, err = self.check("base", {"files": [], "elements": {"WstxContext::CatRadio": "radioControl",
                                                                            "WstxReceiveControl::ReceiveCommand": "receive"}})
            self.assertEqual(code, 0, err)
            self.assertEqual(lines[-1], f"Structure checks passed: {len(BASE)} files in target form, 0 files and 2 elements "
                                        "pending; deployment rules on")
        with self.subTest("two faults of two rules"):
            code, lines, err = self.check("two faults", {"files": [], "elements": {}})
            self.assertEqual(code, 2)
            dependency = line_of("two faults", CTX, "dependency watch")
            self.assertEqual(lines[-2:], ["Structure rule 4: outside part joined to no function: context.lonely",
                                          f"Structure rule 9: dependency declared: {CTX}:{dependency}"])
            self.assertTrue(err.endswith("SysML check failed: 2 structure faults\n"), err)


if __name__ == "__main__":
    unittest.main()
