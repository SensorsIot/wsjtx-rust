"""TR-09: the architecture oracle, judged on a fixture tree in the finished form.

FILES is a model tree in the form of `docs/sysml/`: the deployment `context : ShackContext`
in Context.sysml with two outside things, the shack and its stations in Shack.sysml, each
part definition in its part's file, the interfaces under interfaces/internal/ and
interfaces/external/. The real pinned Pilot validates each model state once, in a bounded
pool; `oracle` writes the oracle file from the base state's inventory and `check`'s
architecture comparison (`architecture_integrity`) judges each state against it. The
deployment, the counts and the refusals are written by hand from the fixture text.
"""
from concurrent.futures import ThreadPoolExecutor
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest import mock

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("architecture_integrity_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CACHE = Path.home() / ".cache/wsjtx-rust/sysml-tools"
WORKERS = 2

STATION_COMMANDS = "interfaces/internal/StationCommands.sysml"
RECEIVE_CONTROL = "interfaces/internal/ReceiveControl.sysml"
SHACK = "Shack.sysml"
CONTEXT = "Context.sysml"
BROWSER = "frontend/BrowserClient.sysml"
SUPERVISOR = "backend/supervisor/Supervisor.sysml"
RECEIVE = "backend/receive/Receive.sysml"
RADIO_CONTROL = "backend/radioControl/RadioControl.sysml"
MCP = "backend/mcp/Mcp.sysml"


FILES = {
    "Requirements.sysml": '''// Canonical authority: SysML
package WstxRequirements {
    doc /* The functional requirements of the station. */
}
''',
    "interfaces/internal/StationLink.sysml": '''package WstxStationLink {
    private import ScalarValues::*;
    item def StationRequest { attribute text : String; }
    item def StationView { attribute text : String; }
    port def StationLinkPort {
        out item request : StationRequest;
        in item display : StationView;
    }
    interface def StationLink {
        end browser : StationLinkPort;
        end station : ~StationLinkPort;
    }
}
''',
    STATION_COMMANDS: '''package WstxStationCommands {
    private import ScalarValues::*;
    item def Halt {
        doc /* The emergency stop. */
    }
    item def SaveConfig { attribute profile : String; }
    item def SaveShack { attribute call : String; }
    item def StationAnswer { attribute text : String; }
    port def StationOperations {
        out abstract item commands[0..*] {
            doc /* A command for the station. */
        }
        in item answer : StationAnswer;
        out item halt : Halt :> commands;
        out item saveConfig : SaveConfig :> commands;
        out item saveShack : SaveShack :> commands;
    }
    enum def AgentRefusal {
        enum saveConfig;
        enum saveShack;
    }
    port def AgentOperations :> StationOperations {
        out item :>> saveConfig[0];
        out item :>> saveShack[0];
    }
    interface def StationCommands {
        end requester : StationOperations;
        end station : ~StationOperations;
    }
    interface def AgentCommands {
        end requester : AgentOperations;
        end station : ~AgentOperations;
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
    "interfaces/external/OperatorInteraction.sysml": '''package WstxOperatorInteraction {
    private import ScalarValues::*;
    item def Gesture { attribute key : String; }
    item def Screen { attribute text : String; }
    port def OperatorInteractionPort {
        in item gesture : Gesture;
        out item screen : Screen;
    }
    interface def OperatorInteraction {
        end browserClient : OperatorInteractionPort;
        end operator : ~OperatorInteractionPort;
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
    "interfaces/external/RadioProperties.sysml": '''package WstxRadioProperties {
    private import ScalarValues::*;
    part def Radio {
        doc /* A transceiver. */
        attribute model : String;
    }
}
''',
    SUPERVISOR: '''package WstxSupervisorPart {
    private import WstxStationCommands::StationOperations;
    private import WstxStationCommands::AgentOperations;
    private import WstxReceiveControl::JobPort;
    part def Supervisor {
        port webOperations : ~StationOperations;
        port mcpOperations : ~AgentOperations;
        port receive : JobPort;
    }
}
''',
    "backend/web/Web.sysml": '''package WstxWebPart {
    private import WstxStationLink::StationLinkPort;
    private import WstxStationCommands::StationOperations;
    part def WebAdapter {
        port client : ~StationLinkPort;
        port supervisor : StationOperations;
    }
}
''',
    MCP: '''package WstxMcpPart {
    private import WstxStationCommands::AgentOperations;
    part def McpAdapter {
        port supervisor : AgentOperations;
    }
}
''',
    RECEIVE: '''package WstxReceivePart {
    private import WstxReceiveControl::JobPort;
    part def ReceiveService {
        port jobs : ~JobPort;
    }
}
''',
    RADIO_CONTROL: '''package WstxRadioControlPart {
    private import WstxCat::CatPort;
    part def RadioControlInterface {
        doc /* The radio control part. */
    }
    part def CatAdapter {
        port radio : CatPort;
    }
}
''',
    "backend/audio/Audio.sysml": '''package WstxAudioPart {
    part def AudioInterface {
        doc /* The audio part. */
    }
    part def AudioDeviceAdapter {
        doc /* The binding to the sound devices. */
    }
}
''',
    "backend/profile/Profile.sysml": '''package WstxProfilePart {
    part def PersistedProfile {
        doc /* The PersistedProfile part. */
    }
}
''',
    "backend/modes/Modes.sysml": '''package WstxModesPart {
    part def ModeFunctions {
        doc /* The ModeFunctions part. */
    }
}
''',
    "backend/clock/Clock.sysml": '''package WstxClockPart {
    part def ClockService {
        doc /* The ClockService part. */
    }
}
''',
    "backend/transmit/Transmit.sysml": '''package WstxTransmitPart {
    part def TransmitService {
        doc /* The TransmitService part. */
    }
}
''',
    "backend/operating/Operating.sysml": '''package WstxOperatingPart {
    part def OperatingService {
        doc /* The OperatingService part. */
    }
}
''',
    "backend/operating/ranking/Ranking.sysml": '''package WstxRankingPart {
    part def RankingService {
        doc /* The RankingService part. */
    }
}
''',
    "backend/operating/auto/Auto.sysml": '''package WstxAutoPart {
    part def AutoService {
        doc /* The AutoService part. */
    }
}
''',
    "backend/operating/qso/Qso.sysml": '''package WstxQsoPart {
    part def QsoService {
        doc /* The QsoService part. */
    }
}
''',
    "backend/log/Log.sysml": '''package WstxLogPart {
    part def LogService {
        doc /* The LogService part. */
    }
}
''',
    "backend/spots/Spots.sysml": '''package WstxSpotsPart {
    part def SpotsService {
        doc /* The SpotsService part. */
    }
}
''',
    "backend/udp/Udp.sysml": '''package WstxUdpPart {
    part def UdpService {
        doc /* The UdpService part. */
    }
}
''',
    "backend/flexAdapter/FlexAdapter.sysml": '''package WstxFlexAdapterPart {
    part def FlexAdapter {
        doc /* The FlexAdapter part. */
    }
}
''',
    BROWSER: '''package WstxBrowserClientPart {
    private import WstxStationLink::StationLinkPort;
    private import WstxOperatorInteraction::OperatorInteractionPort;
    part def BrowserClient {
        port station : StationLinkPort;
        port operator : OperatorInteractionPort;
    }
}
''',
    SHACK: '''package WstxShack {
    private import WstxBrowserClientPart::BrowserClient;
    private import WstxSupervisorPart::Supervisor;
    private import WstxWebPart::WebAdapter;
    private import WstxMcpPart::McpAdapter;
    private import WstxProfilePart::PersistedProfile;
    private import WstxReceivePart::ReceiveService;
    private import WstxModesPart::ModeFunctions;
    private import WstxClockPart::ClockService;
    private import WstxTransmitPart::TransmitService;
    private import WstxOperatingPart::OperatingService;
    private import WstxRankingPart::RankingService;
    private import WstxAutoPart::AutoService;
    private import WstxQsoPart::QsoService;
    private import WstxLogPart::LogService;
    private import WstxSpotsPart::SpotsService;
    private import WstxUdpPart::UdpService;
    private import WstxAudioPart::AudioInterface;
    private import WstxAudioPart::AudioDeviceAdapter;
    private import WstxRadioControlPart::RadioControlInterface;
    private import WstxRadioControlPart::CatAdapter;
    private import WstxFlexAdapterPart::FlexAdapter;
    private import WstxStationLink::StationLink;
    private import WstxStationCommands::StationCommands;
    private import WstxStationCommands::AgentCommands;
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
        part mcp : McpAdapter;
        part profile : PersistedProfile;
        part receive : ReceiveService;
        part modes : ModeFunctions;
        part clock : ClockService;
        part transmit : TransmitService;
        part operating : OperatingService {
            part ranking : RankingService;
            part auto : AutoService;
            part qso : QsoService;
        }
        part log : LogService;
        part spots : SpotsService;
        part udp : UdpService;
        part audio : AudioInterface;
        part radioControl : RadioControlInterface;
        part flexAdapter[0..1] : FlexAdapter;
        part audioAdapter : AudioDeviceAdapter;
        part catAdapter : CatAdapter;

        interface webOperations : StationCommands connect web.supervisor to supervisor.webOperations;
        interface mcpOperations : AgentCommands connect mcp.supervisor to supervisor.mcpOperations;
        interface receiveJobs : ReceiveControl connect supervisor.receive to receive.jobs;
    }
}
''',
    CONTEXT: '''package WstxContext {
    private import WstxShack::Shack;
    private import WstxRadioProperties::Radio;
    private import WstxOperatorInteraction::OperatorInteractionPort;
    private import WstxOperatorInteraction::OperatorInteraction;
    private import WstxCat::CatPort;
    private import WstxCat::Cat;

    part def ShackContext {
        part shack : Shack;
        part operator {
            doc /* The licensed person who operates the stations. */
            port link : ~OperatorInteractionPort;
        }
        part catRadio : Radio {
            port link : ~CatPort;
        }

        interface operatorLink : OperatorInteraction
            connect shack.stations.frontend.browsers.operator to operator.link;
        interface catLink : Cat connect shack.stations.backend.catAdapter.radio to catRadio.link;
    }

    part context : ShackContext;

    view physicalInterconnection : StandardViewDefinitions::InterconnectionView {
        expose context::shack::*;
    }
}
''',
}

# The deployment of FILES below the root, written by hand: part path -> (type, population);
# port path -> port definition.
STATIONS = "context.shack.stations"
BACKEND = STATIONS + ".backend"
PARTS = {
    "context.shack": ("WstxShack::Shack", "1..1"),
    "context.operator": ("Parts::Part", "1..1"),
    "context.catRadio": ("WstxRadioProperties::Radio", "1..1"),
    STATIONS: ("WstxShack::Station", "0..*"),
    STATIONS + ".frontend": ("WstxShack::Frontend", "1..1"),
    STATIONS + ".frontend.browsers": ("WstxBrowserClientPart::BrowserClient", "0..*"),
    BACKEND: ("WstxShack::Backend", "1..1"),
    BACKEND + ".supervisor": ("WstxSupervisorPart::Supervisor", "1..1"),
    BACKEND + ".web": ("WstxWebPart::WebAdapter", "1..1"),
    BACKEND + ".mcp": ("WstxMcpPart::McpAdapter", "1..1"),
    BACKEND + ".profile": ("WstxProfilePart::PersistedProfile", "1..1"),
    BACKEND + ".receive": ("WstxReceivePart::ReceiveService", "1..1"),
    BACKEND + ".modes": ("WstxModesPart::ModeFunctions", "1..1"),
    BACKEND + ".clock": ("WstxClockPart::ClockService", "1..1"),
    BACKEND + ".transmit": ("WstxTransmitPart::TransmitService", "1..1"),
    BACKEND + ".operating": ("WstxOperatingPart::OperatingService", "1..1"),
    BACKEND + ".operating.ranking": ("WstxRankingPart::RankingService", "1..1"),
    BACKEND + ".operating.auto": ("WstxAutoPart::AutoService", "1..1"),
    BACKEND + ".operating.qso": ("WstxQsoPart::QsoService", "1..1"),
    BACKEND + ".log": ("WstxLogPart::LogService", "1..1"),
    BACKEND + ".spots": ("WstxSpotsPart::SpotsService", "1..1"),
    BACKEND + ".udp": ("WstxUdpPart::UdpService", "1..1"),
    BACKEND + ".audio": ("WstxAudioPart::AudioInterface", "1..1"),
    BACKEND + ".radioControl": ("WstxRadioControlPart::RadioControlInterface", "1..1"),
    BACKEND + ".flexAdapter": ("WstxFlexAdapterPart::FlexAdapter", "0..1"),
    BACKEND + ".audioAdapter": ("WstxAudioPart::AudioDeviceAdapter", "1..1"),
    BACKEND + ".catAdapter": ("WstxRadioControlPart::CatAdapter", "1..1"),
}
PORTS = {
    "context.operator.link": "~WstxOperatorInteraction::OperatorInteractionPort",
    "context.catRadio.link": "~WstxCat::CatPort",
    STATIONS + ".frontend.browsers.station": "WstxStationLink::StationLinkPort",
    STATIONS + ".frontend.browsers.operator": "WstxOperatorInteraction::OperatorInteractionPort",
    BACKEND + ".web.client": "~WstxStationLink::StationLinkPort",
    BACKEND + ".web.supervisor": "WstxStationCommands::StationOperations",
    BACKEND + ".mcp.supervisor": "WstxStationCommands::AgentOperations",
    BACKEND + ".supervisor.webOperations": "~WstxStationCommands::StationOperations",
    BACKEND + ".supervisor.mcpOperations": "~WstxStationCommands::AgentOperations",
    BACKEND + ".supervisor.receive": "WstxReceiveControl::JobPort",
    BACKEND + ".receive.jobs": "~WstxReceiveControl::JobPort",
    BACKEND + ".catAdapter.radio": "WstxCat::CatPort",
}
# Connections by owner path, written by hand from the interfaces of Shack.sysml and Context.sysml.
CONNECTIONS = {
    "context": [["shack.stations.backend.catAdapter.radio", "catRadio.link"],
                ["shack.stations.frontend.browsers.operator", "operator.link"]],
    STATIONS: [["frontend.browsers.station", "backend.web.client"]],
    BACKEND: [["mcp.supervisor", "supervisor.mcpOperations"], ["supervisor.receive", "receive.jobs"],
              ["web.supervisor", "supervisor.webOperations"]],
}
# The integrity counts of FILES: the root and the 27 parts below it, no reference, 12 ports,
# 6 connections and no binding.
COUNTS = {"parts": 28, "references": 0, "ports": 12, "connections": 6}

RECEIVE_JOBS = "        interface receiveJobs : ReceiveControl connect supervisor.receive to receive.jobs;\n"
JOBS_PORT = "        port jobs : ~JobPort;\n"
RECEIVE_PORT = "        port receive : JobPort;\n"
CONTEXT_PART = "    part context : ShackContext;\n"
EXPOSE = "        expose context::shack::*;\n"

# One edit list of FILES per model state: (file key, original, replacement), each original
# replaced once; original None adds the file.
STATES = {
    "base": (),
    "removed connection": ((SHACK, RECEIVE_JOBS, ""),),
    "conjugation": ((RECEIVE, JOBS_PORT, "        port jobs : JobPort;\n"),),
    "other port definition": (
        (RECEIVE_CONTROL, "    interface def ReceiveControl", "    port def OtherJobPort {\n        out item job : ReceiveJob;\n"
                                                              "    }\n    interface def ReceiveControl"),
        (RECEIVE, "    private import WstxReceiveControl::JobPort;\n",
         "    private import WstxReceiveControl::JobPort;\n    private import WstxReceiveControl::OtherJobPort;\n"),
        (RECEIVE, JOBS_PORT, "        port jobs : ~OtherJobPort;\n")),
    "item type": ((RECEIVE_CONTROL, "        out item job : ReceiveJob;\n", "        out item job : ReceivePlan;\n"),
                  (RECEIVE_CONTROL, "    port def JobPort", "    item def ReceivePlan { attribute mode : String; }\n"
                                                           "    port def JobPort")),
    "unlisted part": ((SHACK, "        part log : LogService;\n",
                       "        part log : LogService;\n        part archive : PersistedProfile;\n"),),
    "unlisted port": ((SUPERVISOR, RECEIVE_PORT, RECEIVE_PORT + "        port spare : JobPort;\n"),),
    "unlisted connection": ((SHACK, "            connect frontend.browsers.station to backend.web.client;\n",
                             "            connect frontend.browsers.station to backend.web.client;\n"
                             "        interface spareJobs : ReceiveControl\n"
                             "            connect backend.supervisor.receive to backend.receive.jobs;\n"),),
    "second deployment": ((CONTEXT, CONTEXT_PART, CONTEXT_PART + "    part spareContext : ShackContext;\n"),),
    "view part": ((CONTEXT, EXPOSE, EXPOSE + "        part inventedStation : WstxShack::Station;\n"),),
}


def texts(edits=()):
    """FILES with each edit applied once (original None: a new file); fails when an edit no
    longer targets the fixture."""
    files = dict(FILES)
    for key, original, replacement in edits:
        if original is None:
            files[key] = replacement
            continue
        if files.get(key, "").count(original) != 1:
            raise AssertionError(f"edit does not target {key} once: {original}")
        files[key] = files[key].replace(original, replacement, 1)
    return files


def write_tree(root, files):
    """docs/sysml below `root` holding `files`; the model folder."""
    models = root / "docs/sysml"
    for key, text in files.items():
        (models / key).parent.mkdir(parents=True, exist_ok=True)
        (models / key).write_text(text, encoding="utf-8", newline="\n")
    return models


def validate_state(edits):
    """The pinned Pilot's validation with inventory of FILES with `edits`, the files in the
    order `check` passes them, and their keys in that order."""
    with tempfile.TemporaryDirectory() as directory:
        keys, paths = tool.model_keys(write_tree(Path(directory), texts(edits)))
        return tool.validate(paths, CACHE, inventory=True), keys


def line_of(edits, key, needle):
    """The line of the one occurrence of `needle` in the file `key` of FILES with `edits`."""
    text = texts(edits)[key]
    if text.count(needle) != 1:
        raise AssertionError(f"needle not found once: {needle}")
    return text[:text.index(needle)].count("\n") + 1


# Every refusal of the comparison; nothing else may refuse.
REFUSALS = re.compile(r"^Architecture integrity: (?:Architecture oracle unavailable: |Invalid architecture oracle: "
                      r"|missing resolved Pilot inventory|expected one physical deployment|views may expose"
                      r"|invalid endpoint/resource/authority association |missing required |unexpected (?:connection|binding)/bypass "
                      r"|missing or unexpected boundary port roles|semantic exchange signature mismatch |wrong exchange direction "
                      r"|wrong semantic item type |wrong port definition |missing part |unexpected part "
                      r"|wrong part type or population |unexpected reference |port joined to no function )")


class ArchitectureIntegrityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            futures = {state: pool.submit(validate_state, edits) for state, edits in STATES.items()}
            cls.results = {state: future.result()[0] for state, future in futures.items()}
        folder = tempfile.TemporaryDirectory(prefix="sysml-integrity-")
        cls.addClassCleanup(folder.cleanup)
        cls.root = Path(folder.name)
        cls.models = write_tree(cls.root, FILES)
        cls.oracle_path = cls.root / "tools/sysml/architecture-oracle.json"
        cls.oracle_path.parent.mkdir(parents=True)
        cls.written = cls.run_oracle(cls.oracle_path)

    @classmethod
    def run_oracle(cls, path, state="base"):
        """`oracle` on the fixture tree, its oracle file at `path`, the Pilot's result of
        `state`: (exit code, stdout lines, stderr)."""
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(tool, "MODELS", cls.models), mock.patch.object(tool, "FSD", cls.root / "docs/absent FSD.md"), \
                mock.patch.object(tool, "ORACLE", path), mock.patch.object(tool, "validate", return_value=cls.results[state]), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = tool.main(["oracle"])
        return code, out.getvalue().splitlines(), err.getvalue()

    def inventory(self, state):
        """The Pilot's inventory output of `state`, which the Pilot accepts."""
        result = self.results[state]
        diagnostics = "\n".join(line for line in result.stdout.splitlines() if not line.startswith(("Reading ", "AST\t")))
        self.assertEqual(result.returncode, 0, diagnostics + result.stderr[-3000:])
        self.assertIn("syntax/name/semantic validation passed", result.stdout)
        return result.stdout

    def oracle(self):
        """The oracle file `oracle` wrote from the base state, as data."""
        return json.loads(self.oracle_path.read_text(encoding="utf-8"))

    def judge(self, output, oracle):
        """`check`'s architecture comparison of `output` against `oracle` (a dict, the text
        of the file, or None for no file) at the tool's oracle path."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "architecture-oracle.json"
            if oracle is not None:
                path.write_text(oracle if isinstance(oracle, str) else json.dumps(oracle, indent=1), encoding="utf-8")
            with mock.patch.object(tool, "ORACLE", path):
                return tool.architecture_integrity(output)

    def refuses(self, state, message, oracle=None):
        """The state, judged against the written oracle (or `oracle`), is refused with the
        refusal `message` (a regular expression), a refusal of the comparison."""
        with self.assertRaises(ValueError) as refused:
            self.judge(self.inventory(state), self.oracle() if oracle is None else oracle)
        self.assertRegex(str(refused.exception), REFUSALS)
        self.assertRegex(str(refused.exception), "^Architecture integrity: " + message)

    def test_oracle_then_check_accepts_the_finished_form(self):
        """TV-003 (TR-09): `oracle` writes the fixture's parts, ports and connections; `check`'s
        comparison then passes with the fixture's counts; `oracle` again leaves the file."""
        code, lines, err = self.written
        self.assertEqual(code, 0, err)
        self.assertEqual(lines[-1], "Architecture oracle written: 27 parts, 0 references, 6 contracts, 12 ports, "
                                    "6 connections, 0 bindings")
        written = self.oracle()
        self.assertEqual(written["root"], "WstxContext::context")
        self.assertEqual(written["about"], tool.ORACLE_ABOUT)
        self.assertEqual({path: (entry["type"], entry["population"]) for path, entry in written["parts"].items()}, PARTS)
        self.assertEqual(written["ports"], PORTS)
        self.assertEqual({owner: sorted(map(sorted, pairs)) for owner, pairs in written["connections"].items()},
                         {owner: sorted(map(sorted, pairs)) for owner, pairs in CONNECTIONS.items()})
        self.assertEqual((written["references"], written["bindings"]), ({}, {}))
        self.assertEqual(self.judge(self.inventory("base"), written), COUNTS)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "architecture-oracle.json"
            path.write_bytes(self.oracle_path.read_bytes())
            code, lines, err = self.run_oracle(path)
            self.assertEqual((code, lines), (0, ["Architecture oracle unchanged"]), err)
            self.assertEqual(path.read_bytes(), self.oracle_path.read_bytes())

    def test_other_about_text_is_accepted(self):
        """TV-004 (TR-09): the oracle's free `about` text does not take part in the comparison."""
        oracle = self.oracle()
        oracle["about"] = "another free text"
        self.assertEqual(self.judge(self.inventory("base"), oracle), COUNTS)

    def test_each_oracle_entry_removed_is_refused(self):
        """TV-005 (TR-09): each entry of the written oracle, removed alone, is refused."""
        oracle = self.oracle()
        removals = [("root", lambda copy: copy.pop("root"), "Invalid architecture oracle: missing section: root$")]
        for section in ("parts", "references", "contracts", "ports", "connections", "bindings"):
            for key in oracle[section]:
                expected = {"parts": "unexpected part " + re.escape(key) + "$",
                            "ports": "missing or unexpected boundary port roles |Invalid architecture oracle: "}.get(section, "")
                removals.append((section + " " + key, lambda copy, s=section, k=key: copy[s].pop(k), expected))
        for owner, pairs in oracle["connections"].items():
            for index, pair in enumerate(pairs):
                removals.append(("connection " + owner + " " + " <-> ".join(pair),
                                 lambda copy, o=owner, i=index: copy["connections"][o].pop(i),
                                 "unexpected connection/bypass at " + re.escape(owner) + " "))
        for name, contract in oracle["contracts"].items():
            for item in contract["items"]:
                removals.append(("item " + name + " " + item,
                                 lambda copy, n=name, i=item: copy["contracts"][n]["items"].pop(i),
                                 "semantic exchange signature mismatch "))
        removals.append(("every port", lambda copy: copy["ports"].clear(), ""))
        # 27 parts, 6 contracts, 12 ports, 3 owners of connections, 6 connections, their items and root.
        self.assertEqual(sum(1 for name, _remove, _expected in removals if name.startswith("parts ")), 27)
        self.assertEqual(sum(1 for name, _remove, _expected in removals if name.startswith("ports ")), 12)
        self.assertEqual(sum(1 for name, _remove, _expected in removals if name.startswith("connection ")), 6)
        for name, remove, expected in removals:
            with self.subTest(removed=name):
                copy = self.oracle()
                remove(copy)
                with self.assertRaises(ValueError) as refused:
                    self.judge(self.inventory("base"), copy)
                self.assertRegex(str(refused.exception), REFUSALS)
                if expected:
                    self.assertRegex(str(refused.exception), "^Architecture integrity: (?:" + expected + ")")

    def test_removed_connection_is_refused(self):
        """TV-006 (TR-09): a connection the oracle lists, removed from the model, is refused."""
        self.refuses("removed connection", re.escape(f"missing required connection at {BACKEND} "
                                                     "receive.jobs <-> supervisor.receive") + "$")

    def test_wrong_port_type_is_refused(self):
        """TV-007 (TR-09): a port typed otherwise than the oracle lists is refused: the conjugate
        turns its items' directions, another definition is another port definition."""
        self.refuses("conjugation", re.escape(f"wrong exchange direction {BACKEND}.receive.jobs.job") + "$")
        self.refuses("other port definition", re.escape(f"wrong port definition {BACKEND}.receive.jobs") + "$")

    def test_wrong_item_type_is_refused(self):
        """TV-008 (TR-09): an item of another type than the oracle's contract is refused."""
        self.refuses("item type", re.escape(f"wrong semantic item type {BACKEND}.receive.jobs.job") + "$")

    def test_unlisted_part_port_and_connection_are_refused(self):
        """TV-009 (TR-09): a part, a port or a connection the oracle does not list is refused."""
        self.refuses("unlisted part", re.escape(f"unexpected part {BACKEND}.archive") + "$")
        self.refuses("unlisted port", re.escape(f"missing or unexpected boundary port roles ['{BACKEND}.supervisor.spare']") + "$")
        self.refuses("unlisted connection", re.escape(f"unexpected connection/bypass at {STATIONS} "
                                                      "backend.receive.jobs <-> backend.supervisor.receive") + "$")

    def test_fixed_rules_hold_whatever_the_oracle_lists(self):
        """TV-010 (TR-09): a second deployment and a view that adds a part are refused, by `check`
        and by `oracle`, which then leaves the file as it was."""
        self.refuses("second deployment", "expected one physical deployment$")
        self.refuses("view part", "views may expose, not create runtime parts/connections$")
        before = self.oracle_path.read_bytes()
        for state, message in (("second deployment", "expected one physical deployment"),
                               ("view part", "views may expose, not create runtime parts/connections")):
            with self.subTest(state=state):
                code, lines, err = self.run_oracle(self.oracle_path, state)
                self.assertEqual((code, lines), (2, []))
                self.assertIn("SysML check failed: Architecture integrity: " + message, err)
                self.assertEqual(self.oracle_path.read_bytes(), before)

    def test_missing_inventory_is_refused(self):
        """TV-011 (TR-09): a validator output without the resolved inventory is refused."""
        with self.assertRaisesRegex(ValueError, "^Architecture integrity: missing resolved Pilot inventory$"):
            self.judge("OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed.\n", self.oracle())

    def test_missing_or_malformed_oracle_file_is_refused(self):
        """TV-012 (TR-09): the comparison refuses a missing or malformed oracle file whole."""
        text = self.oracle_path.read_text(encoding="utf-8")
        anchor = '"ports": {\n'
        self.assertEqual(text.count(anchor), 1)
        browser = STATIONS + ".frontend.browsers.station"

        def changed(change):
            oracle = self.oracle()
            change(oracle)
            return json.dumps(oracle, indent=1)

        cases = [
            ("missing", None, "Architecture oracle unavailable: "),
            ("empty", "", "Architecture oracle unavailable: "),
            ("not JSON", text[:len(text) // 2], "Architecture oracle unavailable: "),
            ("not a map", "[]", "Invalid architecture oracle: entry of another shape: file"),
            ("without ports", changed(lambda oracle: oracle.pop("ports")), "Invalid architecture oracle: missing section: ports"),
            ("unknown key", changed(lambda oracle: oracle.update(colour="blue")), "Invalid architecture oracle: unknown key: colour"),
            ("port path twice", text.replace(anchor, anchor + f'    "{browser}": "WstxStationLink::StationLinkPort",\n', 1),
             "Invalid architecture oracle: key stated twice: " + browser),
            ("direction inout", changed(lambda oracle: oracle["contracts"]["WstxReceiveControl::JobPort"]["items"]["job"]
                                        .__setitem__(0, "inout")),
             "Invalid architecture oracle: direction other than in or out: WstxReceiveControl::JobPort: job"),
            ("population many", changed(lambda oracle: oracle["parts"][BACKEND].update(population="many")),
             "Invalid architecture oracle: malformed population: " + BACKEND),
            ("absent contract", changed(lambda oracle: oracle["ports"].update({browser: "WstxStationLink::Absent"})),
             "Invalid architecture oracle: port names an absent contract: " + browser),
            ("pair under both kinds", changed(lambda oracle: oracle["bindings"].update(
                {STATIONS: [["frontend.browsers.station", "backend.web.client"]]})),
             "Invalid architecture oracle: pair listed twice: " + STATIONS),
        ]
        for name, oracle_text, message in cases:
            with self.subTest(case=name):
                with self.assertRaises(ValueError) as refused:
                    self.judge(self.inventory("base"), oracle_text)
                self.assertTrue(str(refused.exception).startswith("Architecture integrity: " + message), str(refused.exception))


if __name__ == "__main__":
    unittest.main()
