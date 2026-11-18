"""TR-06, TR-07, TR-08: the deployment rules that `check` reads from the resolved inventory.

The fixture tree is the finished form of test_architecture_integrity (FILES): the deployment
`context : ShackContext`, the shack with its stations, the frontend's browser clients with
one StationLink port to `web` and an operator port to `context.operator`, every backend role,
and two outside things whose ports are joined through interfaces of interfaces/external. It
passes every rule. Each case edits it once; the real pinned Pilot validates each model state
once, in a bounded pool, and the deployment rules then judge its inventory. The M5.10 rules
read the model text and need no Pilot. The expected fault lines are written by hand from the
rule text and the fixture's paths: `<message>: <deployment path>`, or `<message>: <file>:<line>`.
"""
from concurrent.futures import ThreadPoolExecutor
import importlib.util
from pathlib import Path
import tempfile
import unittest

from test_architecture_integrity import (BROWSER, CONTEXT, FILES, MCP, RADIO_CONTROL, RECEIVE, RECEIVE_CONTROL, SHACK,
                                         STATION_COMMANDS, line_of, texts, validate_state, write_tree)

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("architecture_structure_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

WORKERS = 2
STATIONS = "context.shack.stations"
BROWSERS = STATIONS + ".frontend.browsers"
BACKEND = STATIONS + ".backend"
RADIO_PROPERTIES = "interfaces/external/RadioProperties.sysml"

OPERATOR_LINK = ("        interface operatorLink : OperatorInteraction\n"
                 "            connect shack.stations.frontend.browsers.operator to operator.link;\n")
CAT_LINK = "        interface catLink : Cat connect shack.stations.backend.catAdapter.radio to catRadio.link;\n"
BROWSER_STATION = ("        interface browserStation : StationLink\n"
                   "            connect frontend.browsers.station to backend.web.client;\n")
WEB_OPERATIONS = "        interface webOperations : StationCommands connect web.supervisor to supervisor.webOperations;\n"
MCP_OPERATIONS = "        interface mcpOperations : AgentCommands connect mcp.supervisor to supervisor.mcpOperations;\n"
RECEIVE_JOBS = "        interface receiveJobs : ReceiveControl connect supervisor.receive to receive.jobs;\n"
OPERATING = ("        part operating : OperatingService {\n            part ranking : RankingService;\n"
             "            part auto : AutoService;\n            part qso : QsoService;\n        }\n")
EXPOSE = "        expose context::shack::*;\n"
CONTEXT_PART = "    part context : ShackContext;\n"
CAT_RADIO_PORT = "            port link : ~CatPort;\n"
JOB_ITEM = "        out item job : ReceiveJob;\n"
LOG_PART = "        part log : LogService;\n"
RECEIVE_IMPORT = "    private import WstxReceiveControl::JobPort;\n"
RECEIVE_LINK = ((RECEIVE, RECEIVE_IMPORT, RECEIVE_IMPORT + "    private import WstxStationLink::StationLinkPort;\n"),
                (RECEIVE, "        port jobs : ~JobPort;\n", "        port jobs : ~JobPort;\n        port link : ~StationLinkPort;\n"))


def removed(key, text):
    return key, text, ""


def part_line(name, type_name):
    return f"        part {name} : {type_name};\n"


# The roles of M2.2 and M5.5 at the places and multiplicities Context.sysml and Shack.sysml give
# them, below the deployment; each with the edits that remove it (and the connections that
# name it) and the fault lines beyond its own and its inner roles' "role missing".
UNJOINED_OPERATOR = "port joined to nothing: context.operator.link"
UNJOINED_RADIO = "port joined to nothing: context.catRadio.link"
NO_BROWSER_PORT = f"browser client with 0 ports toward the station: {BROWSERS}"
STATION_PORT_ALONE = f"StationLink port not joined to web: {BROWSERS}.station"
ROLES = {
    "shack": ((removed(CONTEXT, "        part shack : Shack;\n"), removed(CONTEXT, OPERATOR_LINK), removed(CONTEXT, CAT_LINK),
               (CONTEXT, EXPOSE, "        expose context::*;\n")),
              [NO_BROWSER_PORT, UNJOINED_OPERATOR, UNJOINED_RADIO]),
    "shack.stations": ((removed(SHACK, "        part stations[*] : Station;\n"), removed(CONTEXT, OPERATOR_LINK),
                        removed(CONTEXT, CAT_LINK)),
                       [NO_BROWSER_PORT, UNJOINED_OPERATOR, UNJOINED_RADIO]),
    "shack.stations.frontend": ((removed(SHACK, part_line("frontend", "Frontend")), removed(SHACK, BROWSER_STATION),
                                 removed(CONTEXT, OPERATOR_LINK)),
                                [NO_BROWSER_PORT, UNJOINED_OPERATOR]),
    "shack.stations.frontend.browsers": ((removed(SHACK, "        part browsers[*] : BrowserClient;\n"),
                                          removed(SHACK, BROWSER_STATION), removed(CONTEXT, OPERATOR_LINK)),
                                         [NO_BROWSER_PORT, UNJOINED_OPERATOR]),
    "shack.stations.backend": ((removed(SHACK, part_line("backend", "Backend")), removed(SHACK, BROWSER_STATION),
                                removed(CONTEXT, CAT_LINK)),
                               [STATION_PORT_ALONE, UNJOINED_RADIO]),
    "shack.stations.backend.supervisor": ((removed(SHACK, part_line("supervisor", "Supervisor")),
                                           removed(SHACK, WEB_OPERATIONS), removed(SHACK, MCP_OPERATIONS),
                                           removed(SHACK, RECEIVE_JOBS)), []),
    "shack.stations.backend.web": ((removed(SHACK, part_line("web", "WebAdapter")), removed(SHACK, WEB_OPERATIONS),
                                    removed(SHACK, BROWSER_STATION)), [STATION_PORT_ALONE]),
    "shack.stations.backend.mcp": ((removed(SHACK, part_line("mcp", "McpAdapter")), removed(SHACK, MCP_OPERATIONS)), []),
    "shack.stations.backend.profile": ((removed(SHACK, part_line("profile", "PersistedProfile")),), []),
    "shack.stations.backend.receive": ((removed(SHACK, part_line("receive", "ReceiveService")),
                                        removed(SHACK, RECEIVE_JOBS)), []),
    "shack.stations.backend.modes": ((removed(SHACK, part_line("modes", "ModeFunctions")),), []),
    "shack.stations.backend.clock": ((removed(SHACK, part_line("clock", "ClockService")),), []),
    "shack.stations.backend.transmit": ((removed(SHACK, part_line("transmit", "TransmitService")),), []),
    "shack.stations.backend.operating": ((removed(SHACK, OPERATING),), []),
    "shack.stations.backend.operating.ranking": ((removed(SHACK, "            part ranking : RankingService;\n"),), []),
    "shack.stations.backend.operating.auto": ((removed(SHACK, "            part auto : AutoService;\n"),), []),
    "shack.stations.backend.operating.qso": ((removed(SHACK, "            part qso : QsoService;\n"),), []),
    "shack.stations.backend.log": ((removed(SHACK, LOG_PART),), []),
    "shack.stations.backend.spots": ((removed(SHACK, part_line("spots", "SpotsService")),), []),
    "shack.stations.backend.udp": ((removed(SHACK, part_line("udp", "UdpService")),), []),
    "shack.stations.backend.audio": ((removed(SHACK, part_line("audio", "AudioInterface")),), []),
    "shack.stations.backend.radioControl": ((removed(SHACK, part_line("radioControl", "RadioControlInterface")),), []),
    "shack.stations.backend.flexAdapter": ((removed(SHACK, "        part flexAdapter[0..1] : FlexAdapter;\n"),), []),
    "shack.stations.backend.audioAdapter": ((removed(SHACK, part_line("audioAdapter", "AudioDeviceAdapter")),), []),
    "shack.stations.backend.catAdapter": ((removed(SHACK, part_line("catAdapter", "CatAdapter")), removed(CONTEXT, CAT_LINK)),
                                          [UNJOINED_RADIO]),
}

# One edit list of FILES per model state; each state is validated once by the Pilot.
STATES = {
    "base": (),
    **{"no " + role: edits for role, (edits, _extra) in ROLES.items()},
    # TR-06
    "stations 1..1": ((SHACK, "part stations[*] : Station;", "part stations[1..1] : Station;"),),
    "second catAdapter": ((SHACK, part_line("catAdapter", "CatAdapter"),
                           part_line("catAdapter", "CatAdapter") + part_line("spareCat", "CatAdapter")),),
    "ranking outside operating": (removed(SHACK, "            part ranking : RankingService;\n"),
                                  (SHACK, LOG_PART, LOG_PART + part_line("ranking", "RankingService"))),
    "second deployment": ((CONTEXT, CONTEXT_PART, CONTEXT_PART + "    part spareContext : ShackContext;\n"),),
    "second browser port to the station": (
        (BROWSER, "        port station : StationLinkPort;\n",
         "        port station : StationLinkPort;\n        port spare : StationLinkPort;\n"),
        (SHACK, BROWSER_STATION, BROWSER_STATION + "        interface spareStation : StationLink\n"
                                                   "            connect frontend.browsers.spare to backend.web.client;\n")),
    "StationLink port to receive": (*RECEIVE_LINK, (SHACK, "to backend.web.client;", "to backend.receive.link;")),
    "frontend connection to receive": (
        *RECEIVE_LINK,
        (SHACK, "        part browsers[*] : BrowserClient;\n",
         "        part browsers[*] : BrowserClient;\n"
         "        part helper {\n            port link : WstxStationLink::StationLinkPort;\n        }\n"),
        (SHACK, BROWSER_STATION, BROWSER_STATION + "        interface sneak : StationLink\n"
                                                   "            connect frontend.helper.link to backend.receive.link;\n")),
    "view adding a part": ((CONTEXT, EXPOSE, EXPOSE + "        part inventedStation : Shack;\n"),),
    # TR-07
    "outside part with a part": ((CONTEXT, CAT_RADIO_PORT, CAT_RADIO_PORT + "            part board;\n"),),
    "outside type with an action": ((RADIO_PROPERTIES, "        attribute model : String;\n",
                                     "        attribute model : String;\n        action poll;\n"),),
    "outside thing without a port": ((CONTEXT, "        part catRadio : Radio {\n",
                                      "        part clubLog {\n            doc /* The Club Log service. */\n        }\n"
                                      "        part catRadio : Radio {\n"),),
    "port joined twice": ((CONTEXT, CAT_LINK, CAT_LINK + "        interface catSpare : Cat\n"
                                                         "            connect shack.stations.backend.catAdapter.radio "
                                                         "to catRadio.link;\n"),),
    "port joined by an internal interface": (
        ("interfaces/internal/RadioControl.sysml", None,
         "package WstxRadioControl {\n    private import WstxCat::CatPort;\n"
         "    interface def CatBus {\n        end station : CatPort;\n        end radio : ~CatPort;\n    }\n}\n"),
        (CONTEXT, "interface catLink : Cat connect", "interface catLink : WstxRadioControl::CatBus connect")),
    "port joined to nothing": (removed(CONTEXT, CAT_LINK),),
    "port joined to an outside thing": (
        (CONTEXT, "        part catRadio : Radio {\n",
         "        part bench {\n            port link : CatPort;\n        }\n        part catRadio : Radio {\n"),
        (CONTEXT, "connect shack.stations.backend.catAdapter.radio to catRadio.link;",
         "connect bench.link to catRadio.link;")),
    "outside thing as subject": (
        (RADIO_CONTROL, "    private import WstxCat::CatPort;\n",
         "    private import WstxCat::CatPort;\n    private import WstxRadioProperties::Radio;\n"),
        (RADIO_CONTROL, "    part def CatAdapter {", "    requirement def RadioRule {\n        subject radio : Radio;\n"
                                                      "    }\n    part def CatAdapter {")),
    # TR-08
    "untyped connection": ((SHACK, RECEIVE_JOBS, "        connection receiveJobs connect supervisor.receive to receive.jobs;\n"),),
    "connection typed by no interface": (
        (RECEIVE_CONTROL, "    interface def ReceiveControl", "    connection def JobLink {\n        end station : JobPort;\n"
                                                              "        end receive : ~JobPort;\n    }\n"
                                                              "    interface def ReceiveControl"),
        (SHACK, "    private import WstxReceiveControl::ReceiveControl;\n",
         "    private import WstxReceiveControl::ReceiveControl;\n    private import WstxReceiveControl::JobLink;\n"),
        (SHACK, RECEIVE_JOBS, "        connection receiveJobs : JobLink connect supervisor.receive to receive.jobs;\n")),
    "interface outside interfaces": (
        (RECEIVE, "    part def ReceiveService", "    interface def LocalJobs {\n        end station : JobPort;\n"
                                                  "        end receive : ~JobPort;\n    }\n    part def ReceiveService"),
        (SHACK, "    private import WstxReceiveControl::ReceiveControl;\n",
         "    private import WstxReceiveControl::ReceiveControl;\n    private import WstxReceivePart::LocalJobs;\n"),
        (SHACK, "receiveJobs : ReceiveControl", "receiveJobs : LocalJobs")),
    "untyped item": ((RECEIVE_CONTROL, JOB_ITEM, "        out item job;\n"),),
    "item of an empty type": ((RECEIVE_CONTROL, JOB_ITEM, "        out item job : Blank;\n"),
                              (RECEIVE_CONTROL, "    port def JobPort", "    item def Blank;\n    port def JobPort")),
    "abstract item no typed item subsets": (
        (STATION_COMMANDS, "        in item answer : StationAnswer;\n",
         "        out abstract item queries[0..*] {\n            doc /* A query of the station. */\n        }\n"
         "        in item answer : StationAnswer;\n"),),
}


def role_case(role):
    """The fault lines of the state without `role`: the role and every role inside it
    missing, and the faults its removed connections leave."""
    edits, extra = ROLES[role]
    return [f"role missing: context.{inner}" for inner in ROLES if inner == role or inner.startswith(role + ".")] + extra


class DeploymentRuleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            futures = {state: pool.submit(validate_state, edits) for state, edits in STATES.items()}
            cls.results = {state: future.result() for state, future in futures.items()}

    def records(self, state):
        result, _keys = self.results[state]
        diagnostics = "\n".join(line for line in result.stdout.splitlines() if not line.startswith(("Reading ", "AST\t")))
        self.assertEqual(result.returncode, 0, diagnostics + result.stderr[-3000:])
        return tool.inventory_records(result.stdout)

    def faults(self, state):
        """The fault lines of the deployment rules (TR-06 to TR-08) on the state."""
        deployment = tool.Deployment(self.records(state), self.results[state][1])
        found = tool.role_faults(deployment) + tool.context_faults(deployment) + tool.connection_faults(deployment)
        return tool.fault_lines(found)

    def assert_cases(self, cases):
        for state, expected in cases.items():
            with self.subTest(state=state):
                self.assertCountEqual(self.faults(state), expected)

    def test_finished_form_passes_every_deployment_rule(self):
        """TR-06: the finished deployment, with Halt as a whole-message command and an
        abstract command item that typed items subset, passes TR-06 to TR-08."""
        self.assertEqual(self.faults("base"), [])
        records = self.records("base")
        halt = [row for row in records["ELEM"] if row[0] == "WstxStationCommands::Halt"]
        self.assertEqual([(row[5], row[6]) for row in halt], [("0", "1")])
        self.assertIn(["WstxStationCommands::StationOperations::halt", "false", "WstxStationCommands::Halt",
                       "WstxStationCommands::StationOperations::commands", "false"],
                      [row[:5] for row in records["PITEM"]])
        self.assertIn(["WstxStationCommands::StationOperations::commands", "true", "", "", "false"],
                      [row[:5] for row in records["PITEM"]])

    def test_each_role_missing_is_refused(self):
        """TR-06: each role of M2.2 and M5.5 removed alone is refused, with every role inside it."""
        self.assertEqual(len(ROLES), 25)
        for role in ROLES:
            with self.subTest(role=role):
                self.assertCountEqual(self.faults("no " + role), role_case(role))

    def test_roles_at_their_places_and_multiplicities(self):
        """TR-06: one deployment, stations of any number, one catAdapter, ranking inside
        operating, and no view that adds a part."""
        self.assert_cases({
            "stations 1..1": [f"role with multiplicity 1..1: {STATIONS}"],
            "second catAdapter": [f"second part of type CatAdapter: {BACKEND}.spareCat"],
            "ranking outside operating": [f"role missing: {BACKEND}.operating.ranking"],
            "second deployment": ["expected one deployment context : ShackContext: docs/sysml"],
            "view adding a part": ["view adds a part or a connection: WstxContext::physicalInterconnection::inventedStation"],
        })

    def test_browser_client_has_one_port_to_web(self):
        """TR-06: the browser client has one port toward the station, joined to web, and the
        frontend connects to nothing else of the station."""
        self.assert_cases({
            "second browser port to the station": [f"browser client with 2 ports toward the station: {BROWSERS}"],
            "StationLink port to receive": [
                STATION_PORT_ALONE,
                f"frontend connection ends at {BACKEND}.receive.link: {STATIONS}.browserStation"],
            "frontend connection to receive": [f"frontend connection ends at {BACKEND}.receive.link: {STATIONS}.sneak"],
        })

    def test_outside_things_are_black_boxes_joined_once_to_a_function(self):
        """TR-07: an outside thing holds ports only, each joined once, through an interface of
        interfaces/external, to a station function, and is no requirement's subject."""
        self.assert_cases({
            "outside part with a part": ["outside thing with PartUsage board: context.catRadio"],
            "outside type with an action": ["outside thing with ActionUsage poll in its type: context.catRadio"],
            "outside thing without a port": ["outside thing without a port: context.clubLog"],
            "port joined twice": ["port joined 2 times: context.catRadio.link"],
            "port joined by an internal interface": ["port joined by no interface of interfaces/external: context.catRadio.link"],
            "port joined to nothing": ["port joined to nothing: context.catRadio.link"],
            "port joined to an outside thing": ["port joined to no station function: context.bench.link",
                                                "port joined to no station function: context.catRadio.link"],
            "outside thing as subject": ["outside thing is the subject of WstxRadioControlPart::RadioRule: context.catRadio"],
        })

    def test_connections_typed_and_items_not_empty(self):
        """TR-08: every connection is typed by an interface of interfaces/; no port item is
        untyped, typed by a definition with neither doc nor feature, or an abstract item no
        typed item subsets."""
        self.assert_cases({
            "untyped connection": [f"untyped connection: {BACKEND}.receiveJobs"],
            "connection typed by no interface": [f"connection typed by no interface: {BACKEND}.receiveJobs"],
            "interface outside interfaces": [f"connection typed by an interface outside interfaces/: {BACKEND}.receiveJobs"],
            "untyped item": ["untyped item: WstxReceiveControl::JobPort::job"],
            "item of an empty type": ["item typed by WstxReceiveControl::Blank, which has neither doc nor feature: "
                                      "WstxReceiveControl::JobPort::job"],
            "abstract item no typed item subsets": [
                "abstract item no typed item subsets: WstxStationCommands::StationOperations::queries"],
        })


# M5.10 on the model text: (edits, expected lines) by case; the lines name the file and line.
AGENT_PORT = "    port def AgentOperations :> StationOperations {\n"
SAVE_SHACK_REMOVED = "        out item :>> saveShack[0];\n"
SAVE_SHACK_LITERAL = "        enum saveShack;\n"
MCP_PORT = "        port supervisor : AgentOperations;\n"


class AgentCommandTests(unittest.TestCase):
    """TR-06 for M5.10: mcp gives every command web gives except those AgentRefusal names."""

    def faults(self, edits=()):
        with tempfile.TemporaryDirectory() as directory:
            model = tool.Model(write_tree(Path(directory), texts(edits)))
            return tool.fault_lines(tool.agent_faults(model))

    def test_finished_form_passes(self):
        """TR-06: AgentOperations removes exactly the commands AgentRefusal names and mcp's
        port toward the supervisor is typed by it."""
        self.assertEqual(self.faults(), [])

    def test_mcp_offering_a_refused_command_is_refused(self):
        """TR-06: an AgentRefusal command that AgentOperations keeps is refused."""
        line = line_of((), STATION_COMMANDS, AGENT_PORT)
        self.assertEqual(self.faults([(STATION_COMMANDS, SAVE_SHACK_REMOVED, "")]),
                         [f"mcp offers the refused command saveShack: {STATION_COMMANDS}:{line}"])

    def test_mcp_port_typed_by_every_command_is_refused(self):
        """TR-06: mcp's port toward the supervisor typed by StationOperations offers the refused commands."""
        edits = [(MCP, "    private import WstxStationCommands::AgentOperations;\n",
                  "    private import WstxStationCommands::StationOperations;\n"),
                 (MCP, MCP_PORT, "        port supervisor : StationOperations;\n")]
        line = line_of(edits, MCP, "    part def McpAdapter {")
        self.assertCountEqual(self.faults(edits), [f"mcp has no port typed AgentOperations: {MCP}:{line}",
                                                   f"mcp offers every command of StationOperations: {MCP}:{line}"])

    def test_mcp_lacking_another_command_is_refused(self):
        """TR-06: a command AgentOperations removes that AgentRefusal does not name is refused."""
        edits = [(STATION_COMMANDS, SAVE_SHACK_REMOVED, SAVE_SHACK_REMOVED + "        out item :>> halt[0];\n")]
        line = line_of(edits, STATION_COMMANDS, "        out item :>> halt[0];\n")
        self.assertEqual(self.faults(edits), [f"mcp lacks the command halt: {STATION_COMMANDS}:{line}"])

    def test_refusal_literal_naming_no_command_is_refused(self):
        """TR-06: an AgentRefusal literal that names no command of StationOperations is refused."""
        edits = [(STATION_COMMANDS, SAVE_SHACK_LITERAL, SAVE_SHACK_LITERAL + "        enum saveRig;\n")]
        line = line_of(edits, STATION_COMMANDS, "        enum saveRig;\n")
        self.assertEqual(self.faults(edits), [f"AgentRefusal literal saveRig names no command: {STATION_COMMANDS}:{line}"])


if __name__ == "__main__":
    unittest.main()
