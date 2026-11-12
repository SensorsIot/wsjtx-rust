"""TC-DOC-005: independent architecture oracle using the real pinned Pilot AST."""
from concurrent.futures import ThreadPoolExecutor
import contextlib
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
spec = importlib.util.spec_from_file_location("architecture_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

# The oracle file by its contract path, not by the tool's constant.
ORACLE_FILE = TOOL.parent / "sysml/architecture-oracle.json"
SECTIONS = ("parts", "references", "contracts", "ports", "connections", "bindings")
# The oracle file's sizes are the parent's, counted by hand before the outside things left
# (26 parts below the root, 8 references, 56 ports, 11 contracts, 34 pairs of which 4 are
# bindings), less the entries the outside things took with them: 6 parts (user, radio,
# radioAudioAttachments, radioControlAttachments, mcpClients, mcpAttachments), 5 references
# (radioBinding.radio, mcpAttachments.client and .station, the two radio attachments'
# station), 8 ports (user.interaction, browsers.operator, mcpClients.station, radio.audio,
# radio.control, mcp.client, audioAdapter.radio, catAdapter.radio), 1 contract
# (LocalInteraction) and 4 pairs (the local interaction and the three attachments' pairs).
PARENT_HAND_COUNTS = {"parts": 26, "references": 8, "ports": 56, "contracts": 11, "pairs": 34}
REMOVED_ENTRIES = {"parts": 6, "references": 5, "ports": 8, "contracts": 1, "pairs": 4}
HAND_COUNTS = {kind: PARENT_HAND_COUNTS[kind] - REMOVED_ENTRIES[kind] for kind in PARENT_HAND_COUNTS}
# The parent's passed line, less the removed parts, references and ports, and 6 connections:
# the 4 pairs and the reply binding RadioControl declares at the 2 removed ports it typed.
PARENT_COUNTS = {"parts": 27, "references": 8, "ports": 56, "connections": 46}
REMOVED_COUNTS = {"parts": 6, "references": 5, "ports": 8, "connections": 6}
MASTER_COUNTS = {kind: PARENT_COUNTS[kind] - REMOVED_COUNTS[kind] for kind in PARENT_COUNTS}
# Every refusal of the contract (promises 4 and 6); nothing else may refuse.
REFUSALS = re.compile(r"Architecture integrity: (?:Architecture oracle unavailable: |Invalid architecture oracle: "
                      r"|missing resolved Pilot inventory|expected one physical deployment|views may expose"
                      r"|station population|exactly one direct|duplicate or detached|shared radio requires one effective authority"
                      r"|invalid endpoint/resource/authority association |missing required |unexpected (?:connection|binding)/bypass "
                      r"|missing or unexpected boundary port roles|semantic exchange signature mismatch |wrong exchange direction "
                      r"|wrong semantic item type |wrong port definition |missing part |unexpected part "
                      r"|wrong part type or population |unexpected reference |port joined to no function )")

# Fixture models (R3 to R6, R10): one added model file each, with its edits of the architecture.
STATION_PART = "part catAdapter : RustRadioDriver;"
STATION_DEFINITION = "part def StationProcess {"
SERVICE_PORT = "port audioStatus : ~AudioStatus;"
TOP_PART = "part browserAttachments[*] : BrowserAttachment;"
BYPASS_ENDS = ["physicalStation.backend.stations.radioControl.backend",
               "physicalStation.backend.stations.catAdapter.authorized"]


def bypass_package(keyword):
    """A part definition of another package whose connection joins two ports of a station."""
    return (keyword + " WstxBypassProbe {\n    part def Bypass {\n        connection bypass connect WstxArchitecture::"
            + BYPASS_ENDS[0] + " to WstxArchitecture::" + BYPASS_ENDS[1] + ";\n    }\n}\n")


UDP_PACKAGE = """package WstxProbeUdp {
    item def Datagram;
    item def Reply;
    port def ProbeMessages {
        out item datagram : Datagram;
        in item reply : Reply;
    }
    port def OtherMessages {
        out item datagram : Datagram;
        in item reply : Reply;
    }
    part def ListeningFunction { port messages : ~ProbeMessages; }
    part def ProbeAttachment {
        ref part listener : ListeningFunction :> WstxArchitecture::physicalStation.listeners;
        ref part station : WstxArchitecture::StationProcess :> WstxArchitecture::physicalStation.backend.stations;
        connection probeMessages connect station.station.probe to listener.messages;
    }
    part def ProxyAuthority :> WstxArchitecture::RadioAuthority;
    part def ProxyDriver :> WstxArchitecture::RustRadioDriver;
}
"""
UDP_EDITS = ((SERVICE_PORT, SERVICE_PORT + "\n        port probe : WstxProbeUdp::ProbeMessages;"),
             (TOP_PART, TOP_PART + "\n        part listeners[*] : WstxProbeUdp::ListeningFunction;"
                                   "\n        part probeAttachments[*] : WstxProbeUdp::ProbeAttachment;"))
# The entries of the R4 model, written by hand.
UDP_ORACLE = {
    "parts": {"physicalStation.listeners": {"type": "WstxProbeUdp::ListeningFunction", "population": "0..*"},
              "physicalStation.probeAttachments": {"type": "WstxProbeUdp::ProbeAttachment", "population": "0..*"}},
    "references": {
        "physicalStation.probeAttachments.listener": {"type": "WstxProbeUdp::ListeningFunction", "population": "1..1",
                                                      "target": "physicalStation.listeners"},
        "physicalStation.probeAttachments.station": {"type": "WstxArchitecture::StationProcess", "population": "1..1",
                                                     "target": "physicalStation.backend.stations"}},
    "contracts": {"WstxProbeUdp::ProbeMessages": {"items": {"datagram": ["out", "WstxProbeUdp::Datagram"],
                                                            "reply": ["in", "WstxProbeUdp::Reply"]}}},
    "ports": {"physicalStation.backend.stations.station.probe": "WstxProbeUdp::ProbeMessages",
              "physicalStation.listeners.messages": "~WstxProbeUdp::ProbeMessages"},
    "connections": {"physicalStation.probeAttachments": [["station.station.probe", "listener.messages"]]},
}
# Counted by hand: the tip's counts plus the two parts, two references, two ports and one
# connection of UDP_ORACLE.
UDP_COUNTS = {kind: MASTER_COUNTS[kind] + added for kind, added in
              {"parts": 2, "references": 2, "ports": 2, "connections": 1}.items()}


def authority_entries(path, type_name):
    """The oracle entries of one more authority part at `path`: part, ports and bindings."""
    return {"parts": {path: {"type": type_name, "population": "1..1"}},
            "ports": {path + ".requests": "~WstxArchitecture::RadioControl",
                      path + ".authorized": "WstxArchitecture::RadioControl"},
            "bindings": {path: [["authorized.request", "requests.request"], ["requests.outcome", "authorized.outcome"]]}}


DRIVER_ENTRIES = {"parts": {"physicalStation.backend.stations.proxyDriver": {"type": "WstxProbeUdp::ProxyDriver",
                                                                             "population": "1..1"}},
                  "ports": {"physicalStation.backend.stations.proxyDriver.authorized": "~WstxArchitecture::RadioControl"}}
HOLDER_PACKAGE = "package WstxPartProbe {\n    part def Hidden;\n    part def Holder { part hidden : Hidden; }\n}\n"

# The parent's outside things, put back into the tip model as the parent wrote them (R3).
RADIO_DOC_END = "controls, meters and scope remain distinct from requested settings. */"
RADIO_PORTS = "\n        port audio : ~AudioExchange;\n        port control : ~RadioControl;"
BINDING_DOC_END = "reconciliation; actual radio capacity is reported at runtime. */"
AUTHORITY_DEFINITION = "    part def RadioAuthority {"
AUDIO_HOST = "port host : ~AudioExchange;"
DRIVER_AUTHORIZED = "port authorized : ~RadioControl;"
BROWSER_STATION_PORT = "port station : BrowserExchange;"
BROWSER_STATION = "connection browserStation connect browser.station to station.web.client;"
BROWSER_DEFINITION = "    part def BrowserClient {"
BACKEND_AUTHORITY = "part radioAuthority : RadioAuthority;"
MCP_STATION_PORT = "port station : StationOperations;\n    }\n    part def PersistedProfile {"
RADIO_RESTORED = (
    (TOP_PART, TOP_PART + "\n        part radio : Radio;"
               "\n        part radioAudioAttachments[*] : RadioAudioAttachment;"
               "\n        part radioControlAttachments[*] : RadioControlAttachment;"),
    (RADIO_DOC_END, RADIO_DOC_END + RADIO_PORTS),
    (BINDING_DOC_END, BINDING_DOC_END + "\n        ref part radio : Radio :> physicalStation.radio;"),
    (AUDIO_HOST, AUDIO_HOST + "\n        port radio : AudioExchange;"),
    (DRIVER_AUTHORIZED, DRIVER_AUTHORIZED + "\n        port radio : RadioControl;"),
    (AUTHORITY_DEFINITION, """    part def RadioAudioAttachment {
        ref part station : StationProcess :> physicalStation.backend.stations;
        connection audioDelegation connect station.audioAdapter.radio to station.radioBinding.radio.audio;
    }
    part def RadioControlAttachment {
        ref part station : StationProcess :> physicalStation.backend.stations;
        connection controlDelegation connect station.catAdapter.radio to station.radioBinding.radio.control;
    }
""" + AUTHORITY_DEFINITION),
)
USER_RESTORED = (
    (TOP_PART, TOP_PART + "\n        part user : User;"),
    (BROWSER_DEFINITION, """    item def OperatorRequest;
    item def Presentation;
    port def LocalInteraction {
        out item request : OperatorRequest;
        in item presentation : Presentation;
    }
    part def User { port interaction : LocalInteraction; }
""" + BROWSER_DEFINITION),
    (BROWSER_STATION_PORT, "port operator : ~LocalInteraction;\n        " + BROWSER_STATION_PORT),
    (BROWSER_STATION, "connection localInteraction connect physicalStation.user.interaction to browser.operator;"
                      "\n        " + BROWSER_STATION),
)
MCP_PORT_RESTORED = (MCP_STATION_PORT, "port client : ~StationOperations;\n        " + MCP_STATION_PORT)
MCP_RESTORED = (
    (BACKEND_AUTHORITY, BACKEND_AUTHORITY + "\n        ref part mcpClients[*] : McpClient;"
                                            "\n        part mcpAttachments[*] : McpAttachment;"),
    (AUTHORITY_DEFINITION, """    part def McpClient { port station : StationOperations; }
    part def McpAttachment {
        ref part client : McpClient :> physicalStation.backend.mcpClients;
        ref part station : StationProcess :> physicalStation.backend.stations;
        connection mcpClientOperations connect client.station to station.mcp.client;
    }
""" + AUTHORITY_DEFINITION),
    MCP_PORT_RESTORED,
)
# Ports joined to no function (R4), each with its oracle entries written by hand.
SPARE_PORT = (SERVICE_PORT, SERVICE_PORT + "\n        port spare : StationOperations;")
SPARE_ENTRIES = {"ports": {"physicalStation.backend.stations.station.spare": "WstxArchitecture::StationOperations"}}
LONE_RADIO = ((TOP_PART, TOP_PART + "\n        part radio : Radio;"), (RADIO_DOC_END, RADIO_DOC_END + RADIO_PORTS))
LONE_RADIO_ENTRIES = {"parts": {"physicalStation.radio": {"type": "WstxArchitecture::Radio", "population": "1..1"}},
                      "ports": {"physicalStation.radio.audio": "~WstxArchitecture::AudioExchange",
                                "physicalStation.radio.control": "~WstxArchitecture::RadioControl"}}
MCP_PORT_ENTRIES = {"ports": {"physicalStation.backend.stations.mcp.client": "~WstxArchitecture::StationOperations"}}


def edited(text, *changes):
    """`text` with each (original, replacement) applied once; None when a target is gone."""
    for original, replacement in changes:
        if text is None or original not in text:
            return None
        text = text.replace(original, replacement, 1)
    return text


def fixtures(source):
    """{case: (architecture text or None, ((file name, text), ...))} of the fixture models."""
    udp = edited(source, *UDP_EDITS)
    bypass = (STATION_PART, STATION_PART + "\n        part bypass : WstxBypassProbe::Bypass;")
    return {
        "bypass part": (edited(source, bypass), (("BypassProbe.sysml", bypass_package("package")),)),
        "bypass library part": (edited(source, bypass), (("BypassProbe.sysml", bypass_package("library package")),)),
        "bypass inherited": (edited(source, (STATION_DEFINITION, "part def StationProcess :> WstxBypassProbe::Bypass {")),
                             (("BypassProbe.sysml", bypass_package("package")),)),
        "udp": (udp, (("Udp.sysml", UDP_PACKAGE),)),
        "udp direction": (udp, (("Udp.sysml", edited(UDP_PACKAGE, ("out item datagram", "in item datagram"))),)),
        "udp item type": (udp, (("Udp.sysml", edited(UDP_PACKAGE, ("datagram : Datagram;", "datagram : Reply;"))),)),
        "udp third item": (udp, (("Udp.sysml", edited(UDP_PACKAGE, ("in item reply : Reply;",
                                                                    "in item reply : Reply;\n        in item extra : Reply;"))),)),
        "udp other definition": (edited(udp, ("WstxProbeUdp::ProbeMessages;", "WstxProbeUdp::OtherMessages;")),
                                 (("Udp.sysml", UDP_PACKAGE),)),
        "udp population": (edited(udp, ("listeners[*]", "listeners[0..1]")), (("Udp.sysml", UDP_PACKAGE),)),
        "udp extra reference": (udp, (("Udp.sysml", edited(UDP_PACKAGE, (
            "connection probeMessages", "ref part spare : ListeningFunction :> WstxArchitecture::physicalStation.listeners;"
                                        "\n        connection probeMessages"))),)),
        "udp second authority": (edited(udp, (TOP_PART, TOP_PART + "\n        part secondAuthority : RadioAuthority;")),
                                 (("Udp.sysml", UDP_PACKAGE),)),
        "udp authority subtype": (edited(udp, (TOP_PART, TOP_PART + "\n        part proxyAuthority : WstxProbeUdp::ProxyAuthority;")),
                                  (("Udp.sysml", UDP_PACKAGE),)),
        "udp driver subtype": (edited(udp, (STATION_PART, STATION_PART + "\n        part proxyDriver : WstxProbeUdp::ProxyDriver;")),
                               (("Udp.sysml", UDP_PACKAGE),)),
        "hidden part": (edited(source, (STATION_PART, STATION_PART + "\n        part holder : WstxPartProbe::Holder;")),
                        (("PartProbe.sysml", HOLDER_PACKAGE),)),
        "library deployment": (source, (("LibraryProbe.sysml", "library package WstxLibraryProbe {\n"
                                         "    part hiddenStations[*] : WstxArchitecture::StationProcess;\n}\n"),)),
        "library view": (source, (("LibraryProbe.sysml", "library package WstxLibraryProbe {\n    view inventedView {\n"
                                   "        part inventedStation : WstxArchitecture::StationProcess;\n    }\n}\n"),)),
        "radio restored": (edited(source, *RADIO_RESTORED), ()),
        "user restored": (edited(source, *USER_RESTORED), ()),
        "mcp clients restored": (edited(source, *MCP_RESTORED), ()),
        "spare port": (edited(source, SPARE_PORT), ()),
        "lone radio": (edited(source, *LONE_RADIO), ()),
        "mcp port": (edited(source, MCP_PORT_RESTORED), ()),
    }


def real_oracle():
    return json.loads(ORACLE_FILE.read_text(encoding="utf-8"))


def oracle_with(*additions, removed=()):
    """The real oracle file's content, with the sections of each addition extended and each
    (section, key) of `removed` taken out."""
    oracle = real_oracle()
    for addition in additions:
        for section, entries in addition.items():
            oracle[section].update(entries)
    for section, key in removed:
        del oracle[section][key]
    return oracle


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None

# Each case is a full, independent Pilot validation (its own JVM and, for a mutation, its
# own temporary Architecture.sysml), so setUpClass runs them in a bounded pool. Every test
# still asserts its own result; only the order of the validations changes.
# Six, not more: the JVMs contend, so 8 workers finished no sooner (~240 s) but stretched the
# slowest validation to ~80 s of tool.validate's 120 s timeout; 6 kept it at ~55 s (#59).
WORKERS = max(1, min(6, os.cpu_count() or 1))
PACKAGE = "package WstxArchitecture {"
COMPANION_PROBE = PACKAGE + "\n    attribute propertyOwnerProbe : WstxProfiles::Settings;"
UNDEFINED_PROBE = PACKAGE + "\n    attribute propertyOwnerProbe : WstxProfiles::UndefinedPropertyType;"


def rejects(original, replacement, diagnostic):
    """A test that the architecture with `original` replaced stays valid SysML but fails the oracle."""
    def test(self):
        self.reject(original, replacement, diagnostic)
    test.mutation = (original, replacement)
    return test


class ArchitectureIntegrityTests(unittest.TestCase):
    # Proves: CL-014-03, CL-014-06; TC-DOC-005. No viewer/parser substitute.
    @classmethod
    def setUpClass(cls):
        cls.cache = Path.home() / ".cache/wsjtx-rust/sysml-tools"
        cls.source = (tool.MODELS / "Architecture.sysml").read_text(encoding="utf-8")
        mutated = [cls.source.replace(PACKAGE, COMPANION_PROBE, 1), cls.source.replace(PACKAGE, UNDEFINED_PROBE, 1)]
        for name in dir(cls):
            original, replacement = getattr(getattr(cls, name), "mutation", (None, None))
            # A mutation whose target is gone is not validated; its test fails on that.
            if original is not None and original in cls.source:
                mutated.append(cls.source.replace(original, replacement, 1))
        # A fixture whose target is gone is not validated; its test fails on that.
        models = {case: model for case, model in fixtures(cls.source).items()
                  if model[0] is not None and all(text is not None for _name, text in model[1])}
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            accepted = pool.submit(tool.validate, cls.model_paths(), cls.cache, inventory=True)
            cls.results = {source: pool.submit(cls.validate_architecture, source) for source in mutated}
            cls.fixture_results = {case: pool.submit(cls.validate_architecture, source, added)
                                   for case, (source, added) in models.items()}
            cls.accepted = accepted.result()

    @classmethod
    def model_paths(cls, architecture=None):
        files = tool.model_files(tool.MODELS)
        companions = [path for key, path in files.items()
                      if key not in ("Requirements.sysml", "Architecture.sysml")]
        return [files["Requirements.sysml"], architecture or files["Architecture.sysml"], *companions]

    @classmethod
    def validate_architecture(cls, source, added=()):
        """One full validation of the model with `source` as Architecture.sysml and each
        (file name, text) of `added` as one more model file."""
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "Architecture.sysml"
            model.write_text(source, encoding="utf-8")
            extra = []
            for name, text in added:
                extra.append(Path(directory) / name)
                extra[-1].write_text(text, encoding="utf-8")
            return tool.validate([*cls.model_paths(model), *extra], cls.cache, inventory=True)

    def validated(self, mutated):
        """The full validation of `mutated` from setUpClass; a validator exception is raised here."""
        return self.results[mutated].result()

    def inventory(self, case):
        """The resolved inventory of the fixture model `case`, which the Pilot accepts."""
        self.assertIn(case, self.fixture_results, "fixture no longer targets the accepted architecture")
        result = self.fixture_results[case].result()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("syntax/name/semantic validation passed", result.stdout)
        return result.stdout

    def judge(self, output, oracle):
        """The integrity check of `output` against `oracle` (a dict, or the text of the file)
        as `check` runs it: the oracle file at the tool's path."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "architecture-oracle.json"
            path.write_text(oracle if isinstance(oracle, str) else json.dumps(oracle, indent=1), encoding="utf-8")
            with mock.patch.object(tool, "ORACLE", path, create=True):
                return tool.architecture_integrity(output)

    def refuses(self, output, oracle, diagnostic):
        with self.assertRaisesRegex(ValueError, diagnostic):
            self.judge(output, oracle)

    def check_with(self, oracle_text):
        """`check` on the recorded inventory with `oracle_text` as the oracle file (None:
        no file): (exit code, stdout, stderr)."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "architecture-oracle.json"
            if oracle_text is not None:
                path.write_text(oracle_text, encoding="utf-8")
            out, err = io.StringIO(), io.StringIO()
            with mock.patch.object(tool, "ORACLE", path, create=True), mock.patch.object(tool, "validate", return_value=self.accepted), \
                    contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = tool.main(["check"])
            return code, out.getvalue(), err.getvalue()

    def test_complete_resolved_deployment(self):
        self.assertEqual(self.accepted.returncode, 0, self.accepted.stdout + self.accepted.stderr)
        counts = tool.architecture_integrity(self.accepted.stdout)
        self.assertEqual(counts, MASTER_COUNTS)

    def reject(self, original, replacement, diagnostic):
        self.assertIn(original, self.source, "mutation no longer targets the accepted architecture")
        result = self.validated(self.source.replace(original, replacement, 1))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("syntax/name/semantic validation passed", result.stdout)
        with self.assertRaisesRegex(ValueError, diagnostic):
            tool.architecture_integrity(result.stdout)

    def test_companion_property_type_resolves_without_changing_architecture(self):
        result = self.validated(self.source.replace(PACKAGE, COMPANION_PROBE, 1))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("syntax/name/semantic validation passed", result.stdout)
        self.assertEqual(tool.architecture_integrity(result.stdout),
                         tool.architecture_integrity(self.accepted.stdout))

    def test_undefined_property_type_fails_full_validation(self):
        result = self.validated(self.source.replace(PACKAGE, UNDEFINED_PROBE, 1))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Couldn't resolve reference to Type 'WstxProfiles::UndefinedPropertyType'", result.stdout)
        self.assertNotIn("syntax/name/semantic validation passed", result.stdout)

    test_missing_selected_browser_direct_link = rejects("connection browserStation connect browser.station to station.web.client;", "", "missing required connection")

    test_frontend_container_cannot_forward_ports = rejects("part def Frontend {", "part def Frontend { port station : BrowserExchange;", "missing or unexpected boundary port roles")

    test_backend_container_cannot_forward_ports = rejects("part def Backend {", "part def Backend { port radioAudio : AudioExchange;", "missing or unexpected boundary port roles")

    test_missing_encoding_path = rejects("connection encodeModem connect transmit.encode to modes.encode;", "", "missing required connection")

    test_missing_contact_transmit_path = rejects("connection contactTransmit connect qso.transmit to transmit.contacts;", "", "missing required connection")

    test_control_bypasses_common_authority = rejects("connect radioControl.backend to authorityRequest;", "connect radioControl.backend to catAdapter.authorized;", "missing required connection")

    test_duplicate_audio_adapter = rejects("part audioAdapter : AudioDeviceAdapter;", "part audioAdapter : AudioDeviceAdapter; part duplicateAudio : AudioDeviceAdapter;", "duplicate or detached audioAdapter")

    test_duplicate_cat_adapter = rejects("part catAdapter : RustRadioDriver;", "part catAdapter : RustRadioDriver; part duplicateCat : RustRadioDriver;", "duplicate or detached catAdapter")

    test_audio_adapter_must_be_single = rejects("part audioAdapter : AudioDeviceAdapter;", "part audioAdapter[0..1] : AudioDeviceAdapter;", "exactly one direct audioAdapter")

    test_cat_adapter_must_be_single = rejects("part catAdapter : RustRadioDriver;", "part catAdapter[0..1] : RustRadioDriver;", "exactly one direct catAdapter")

    test_audio_cat_paths_cannot_be_mixed = rejects("connect audio.backend to audioAdapter.host;", "connect audio.backend to catAdapter.authorized;", "missing required connection")

    test_split_shared_authority = rejects("ref part authority : RadioAuthority :> physicalStation.backend.radioAuthority;", "part authority : RadioAuthority;", "one effective authority")

    test_swapped_browser_station_association = rejects("ref part station : StationProcess :> physicalStation.backend.stations;", "ref part otherStation : StationProcess :> physicalStation.backend.stations; ref part station : StationProcess :> otherStation;", "invalid endpoint/resource/authority association physicalStation.browserAttachments.station$")

    test_wrong_requesting_resource_context = rejects("binding catContext bind catAdapter.authorized.request.resourceContext = radioBinding;", "part otherContext : RadioBinding; binding catContext bind catAdapter.authorized.request.resourceContext = otherContext;", "missing required binding")

    test_wrong_waveform_direction = rejects("in item waveform : Waveform;", "out item waveform : Waveform;", "wrong exchange direction")

    test_receive_modem_provider_conjugation = rejects("port receive : ~ReceiveProcessing;", "port receive : ReceiveProcessing;", "wrong exchange direction")

    test_authority_identity_binding_cannot_be_weakened_to_connection = rejects("binding authorizedContext bind authorized.request = requests.request;", "connection authorizedContext connect authorized.request to requests.request;", "missing required binding")

    test_request_context_binding_cannot_be_weakened_to_connection = rejects("binding requestContext bind authorityRequest.request.resourceContext = radioBinding;", "connection requestContext connect authorityRequest.request.resourceContext to radioBinding;", "missing required binding")

    test_audio_playback_semantic_item_type = rejects("out item playback : SampleBlock;", "out item playback : Recording;", "wrong semantic item type")

    test_disconnected_parallel_world = rejects("part physicalStation {", "part detachedStations[*] : StationProcess; part physicalStation {", "one physical deployment")

    test_view_cannot_create_semantics = rejects("expose physicalStation::*;", "expose physicalStation::*; part inventedStation : StationProcess;", "views may expose")

    def test_missing_inventory_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "missing resolved Pilot inventory"):
            tool.architecture_integrity("semantic validation passed without inventory")

    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_every_oracle_entry_is_needed(self):
        """R2: each entry of the real oracle file, removed alone, is refused."""
        oracle = real_oracle()
        sizes = {section: len(oracle[section]) for section in ("parts", "references", "ports", "contracts")}
        sizes["pairs"] = sum(len(pairs) for section in ("connections", "bindings") for pairs in oracle[section].values())
        self.assertEqual(sizes, HAND_COUNTS)
        self.assertEqual(self.judge(self.accepted.stdout, oracle), MASTER_COUNTS)
        removals = [("root", lambda copy: copy.pop("root"), "missing section: root")]
        for section in SECTIONS:
            for key in oracle[section]:
                expected = {"parts": "unexpected part " + re.escape(key) + "$",
                            "references": "unexpected reference " + re.escape(key) + "$"}.get(section, "")
                removals.append((section + " " + key, lambda copy, s=section, k=key: copy[s].pop(k), expected))
        for owner_section in ("connections", "bindings"):
            for owner, pairs in oracle[owner_section].items():
                for index in range(len(pairs)):
                    removals.append((owner_section + " " + owner + " " + str(index),
                                     lambda copy, s=owner_section, o=owner, i=index: copy[s][o].pop(i), ""))
        for name, contract in oracle["contracts"].items():
            for item in contract["items"]:
                removals.append(("item " + name + " " + item,
                                 lambda copy, n=name, i=item: copy["contracts"][n]["items"].pop(i), ""))
            for kind in ("bindings", "connections"):
                for index in range(len(contract.get(kind, []))):
                    removals.append((kind + " of " + name + " " + str(index),
                                     lambda copy, n=name, k=kind, i=index: copy["contracts"][n][k].pop(i), ""))
        removals.append(("empty ports", lambda copy: copy["ports"].clear(), ""))
        self.assertGreater(len(removals), sum(HAND_COUNTS.values()))
        for name, remove, expected in removals:
            with self.subTest(removed=name):
                copy = real_oracle()
                remove(copy)
                with self.assertRaises(ValueError) as refused:
                    self.judge(self.accepted.stdout, copy)
                self.assertRegex(str(refused.exception), REFUSALS)
                if expected:
                    self.assertRegex(str(refused.exception), expected)

    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_bypass_declared_in_another_package_is_refused(self):
        """R3: a connection declared in a definition of another package is inventoried."""
        owner = "physicalStation.backend.stations.bypass"
        part = {"parts": {owner: {"type": "WstxBypassProbe::Bypass", "population": "1..1"}}}
        for case in ("bypass part", "bypass library part"):
            with self.subTest(case=case):
                self.refuses(self.inventory(case), oracle_with(part), "unexpected connection/bypass at " + re.escape(owner) + " ")
        with self.subTest(case="bypass inherited"):
            self.refuses(self.inventory("bypass inherited"), real_oracle(),
                         "unexpected connection/bypass at physicalStation.backend.stations " + re.escape(" <-> ".join(sorted(BYPASS_ENDS))))
        with self.subTest(case="bypass part, connection listed"):
            listed = {"connections": {owner: [BYPASS_ENDS]}}
            self.assertEqual(self.judge(self.inventory("bypass part"), oracle_with(part, listed))["connections"],
                             MASTER_COUNTS["connections"] + 1)

    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_interface_of_another_package_passes_once_listed(self):
        """R4: a function of another package with its port and connection passes when listed."""
        output = self.inventory("udp")
        self.assertEqual(self.judge(output, oracle_with(UDP_ORACLE)), UDP_COUNTS)
        with self.assertRaises(ValueError):
            self.judge(output, real_oracle())

    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_interface_faults_are_refused(self):
        """R5: one fault at a time in the R4 model or its oracle copy."""
        udp = oracle_with(UDP_ORACLE)
        cases = [
            ("udp", oracle_with(UDP_ORACLE, removed=[("parts", "physicalStation.listeners")]),
             "unexpected part physicalStation.listeners$"),
            ("udp", oracle_with(UDP_ORACLE, removed=[("ports", "physicalStation.listeners.messages")]),
             "boundary port roles"),
            ("udp direction", udp, "wrong exchange direction .*\\.datagram$"),
            ("udp item type", udp, "wrong semantic item type .*\\.datagram$"),
            ("udp third item", udp, "semantic exchange signature mismatch"),
            ("udp other definition", udp, "wrong port definition physicalStation.backend.stations.station.probe$"),
            ("udp population", udp, "wrong part type or population physicalStation.listeners$"),
            ("udp extra reference", udp, "unexpected reference physicalStation.probeAttachments.spare$"),
            ("udp", oracle_with(UDP_ORACLE, {"parts": {"physicalStation.ghost": {
                "type": "WstxProbeUdp::ListeningFunction", "population": "1..1"}}}), "missing part physicalStation.ghost$"),
            ("udp second authority",
             oracle_with(UDP_ORACLE, authority_entries("physicalStation.secondAuthority", "WstxArchitecture::RadioAuthority")),
             "one effective authority"),
            ("udp authority subtype",
             oracle_with(UDP_ORACLE, authority_entries("physicalStation.proxyAuthority", "WstxProbeUdp::ProxyAuthority")),
             "one effective authority"),
            ("udp driver subtype", oracle_with(UDP_ORACLE, DRIVER_ENTRIES), "duplicate or detached catAdapter"),
        ]
        for case, oracle, diagnostic in cases:
            with self.subTest(case=case, diagnostic=diagnostic):
                self.refuses(self.inventory(case), oracle, diagnostic)

    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_unlisted_part_of_another_package_is_refused(self):
        """R6: a part declared in a definition of another package is inventoried."""
        holder = {"parts": {"physicalStation.backend.stations.holder": {"type": "WstxPartProbe::Holder", "population": "1..1"}}}
        self.refuses(self.inventory("hidden part"), oracle_with(holder),
                     "unexpected part physicalStation.backend.stations.holder.hidden$")

    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_invalid_oracle_file_fails_closed(self):
        """R7: `check` refuses a missing or malformed oracle file and prints no passed line."""
        text = ORACLE_FILE.read_text(encoding="utf-8")
        anchor = '"ports": {\n'
        self.assertIn(anchor, text)

        def changed(change):
            oracle = real_oracle()
            change(oracle)
            return json.dumps(oracle, indent=1)

        cases = [
            ("missing", None, "Architecture oracle unavailable: "),
            ("empty", "", "Architecture oracle unavailable: "),
            ("not JSON", text[:len(text) // 2], "Architecture oracle unavailable: "),
            ("without ports", changed(lambda oracle: oracle.pop("ports")), "Invalid architecture oracle: missing section: ports"),
            ("unknown key", changed(lambda oracle: oracle.update(colour="blue")), "Invalid architecture oracle: unknown key: colour"),
            ("port path twice", text.replace(anchor, anchor + '    "physicalStation.frontend.browsers.station": "WstxArchitecture::BrowserExchange",\n', 1),
             "Invalid architecture oracle: key stated twice: physicalStation.frontend.browsers.station"),
            ("direction inout", changed(lambda oracle: oracle["contracts"]["WstxArchitecture::RadioControl"]["items"]["request"]
                                        .__setitem__(0, "inout")),
             "Invalid architecture oracle: direction other than in or out: WstxArchitecture::RadioControl: request"),
            ("population many", changed(lambda oracle: oracle["parts"]["physicalStation.frontend"].update(population="many")),
             "Invalid architecture oracle: malformed population: physicalStation.frontend"),
            ("absent contract", changed(lambda oracle: oracle["ports"].update({"physicalStation.frontend.browsers.station": "WstxArchitecture::Absent"})),
             "Invalid architecture oracle: port names an absent contract: physicalStation.frontend.browsers.station"),
            ("pair under both kinds", changed(lambda oracle: oracle["bindings"].update(
                {"physicalStation.browserAttachments": [["browser.station", "station.web.client"]]})),
             "Invalid architecture oracle: pair listed twice: physicalStation.browserAttachments"),
        ]
        for name, oracle_text, message in cases:
            with self.subTest(case=name):
                code, out, err = self.check_with(oracle_text)
                self.assertEqual(code, 2, out + err)
                self.assertIn("SysML check failed: Architecture integrity: " + message, err)
                self.assertNotIn("Architecture integrity passed", out)
        code, out, err = self.check_with(changed(lambda oracle: oracle.update(about="another free text")))
        self.assertEqual(code, 0, out + err)
        self.assertIn("Architecture integrity passed: " + ", ".join(f"{MASTER_COUNTS[kind]} {kind}" for kind in
                      ("parts", "references", "ports", "connections")) + "; runtime behavior not proved.", out)

    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_other_commands_neither_need_nor_write_the_oracle(self):
        """R8: traces, markers and fingerprints run without the oracle file; check leaves it unchanged."""
        with tempfile.TemporaryDirectory() as directory:
            absent = Path(directory) / "architecture-oracle.json"
            for command in ("traces", "markers", "fingerprints"):
                with self.subTest(command=command), mock.patch.object(tool, "ORACLE", absent, create=True), \
                        contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(tool.main([command]), 0)
            self.assertFalse(absent.exists())
        before = digest(ORACLE_FILE)
        with mock.patch.object(tool, "validate", return_value=self.accepted), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(tool.main(["check"]), 0)
        self.assertEqual(digest(ORACLE_FILE), before)

    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_library_package_in_a_model_file_is_judged(self):
        """R10: a second deployment or a view-made part in a library package is refused."""
        for case, diagnostic in (("library deployment", "one physical deployment"), ("library view", "views may expose")):
            with self.subTest(case=case):
                self.refuses(self.inventory(case), real_oracle(), diagnostic)

    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_removed_outside_things_put_back_are_refused(self):
        """R3: the parent's outside things with their ports and connections, put back into the
        model, are refused while the oracle file does not list them; the first unlisted edge
        (a binding RadioControl declares at a put-back port sorts before the connections)."""
        cases = [
            ("radio restored", "unexpected binding/bypass at physicalStation.backend.stations.catAdapter.radio "
                               "outcome.request <-> request$"),
            ("user restored", "unexpected connection/bypass at physicalStation.browserAttachments "
                              "browser.operator <-> physicalStation.user.interaction$"),
            ("mcp clients restored", "unexpected connection/bypass at physicalStation.backend.mcpAttachments "
                                     "client.station <-> station.mcp.client$"),
        ]
        for case, diagnostic in cases:
            with self.subTest(case=case):
                self.refuses(self.inventory(case), real_oracle(), diagnostic)

    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_port_joined_to_no_function_is_refused(self):
        """R4: a listed port that no connection joins is refused, naming the first in sorted
        path order; a port joined only through a reference is joined."""
        cases = [
            ("spare port", oracle_with(SPARE_ENTRIES),
             "port joined to no function physicalStation.backend.stations.station.spare$"),
            ("lone radio", oracle_with(LONE_RADIO_ENTRIES), "port joined to no function physicalStation.radio.audio$"),
            ("mcp port", oracle_with(MCP_PORT_ENTRIES),
             "port joined to no function physicalStation.backend.stations.mcp.client$"),
        ]
        for case, oracle, diagnostic in cases:
            with self.subTest(case=case):
                self.refuses(self.inventory(case), oracle, diagnostic)
        with self.subTest(case="authority joined through stations.authority"):
            rows = [line.split("\t") for line in self.accepted.stdout.splitlines() if line.startswith("AST\tEDGE\t")]
            ends = {end for row in rows if row[4] == "connection" for end in row[5].split("|")}
            self.assertIn("authority.requests", ends)
            self.assertFalse([end for end in ends if "radioAuthority" in end], ends)
            self.assertEqual(self.judge(self.accepted.stdout, real_oracle()), MASTER_COUNTS)


class CompanionListTests(unittest.TestCase):
    """The file list of the mutation tests on a fixture tree; no validation runs here."""

    # Proves: CL-014-10; TC-DOC-008
    def test_companions_are_every_model_file_of_the_tree_but_requirements_and_architecture(self):
        with tempfile.TemporaryDirectory() as directory:
            models = Path(directory) / "docs/sysml"
            keys = ("Requirements.sysml", "Architecture.sysml", "Profiles.sysml", "Udp.sysml",
                    "backend/qso/Part.sysml", "interfaces/Udp.sysml")
            for key in keys:
                (models / key).parent.mkdir(parents=True, exist_ok=True)
                (models / key).write_text("package P {}", encoding="utf-8")
            (models / "reference").mkdir()
            (models / "reference/Old.sysml.txt").write_text("package Old {}", encoding="utf-8")
            mutated = Path(directory) / "mutated/Architecture.sysml"
            with mock.patch.object(tool, "MODELS", models):
                companions = [models / key for key in ("Profiles.sysml", "Udp.sysml", "backend/qso/Part.sysml", "interfaces/Udp.sysml")]
                self.assertEqual(ArchitectureIntegrityTests.model_paths(),
                                 [models / "Requirements.sysml", models / "Architecture.sysml", *companions])
                self.assertEqual(ArchitectureIntegrityTests.model_paths(mutated),
                                 [models / "Requirements.sysml", mutated, *companions])


if __name__ == "__main__":
    unittest.main()
