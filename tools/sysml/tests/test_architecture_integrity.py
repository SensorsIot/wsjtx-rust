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
# Counted by hand from the parent's lists in tools/sysml.py architecture_integrity
# (expected_refs 8; role_contracts 56; contracts 11; expected 34 pairs, of which the 4 of
# required_bindings are bindings) and from the issue's table of 26 parts below the root.
HAND_COUNTS = {"parts": 26, "references": 8, "ports": 56, "contracts": 11, "pairs": 34}
MASTER_COUNTS = {"parts": 27, "references": 8, "ports": 56, "connections": 46}
# Every refusal of the contract (promises 4 and 6); nothing else may refuse.
REFUSALS = re.compile(r"Architecture integrity: (?:Architecture oracle unavailable: |Invalid architecture oracle: "
                      r"|missing resolved Pilot inventory|expected one physical deployment|views may expose"
                      r"|station population|exactly one direct|duplicate or detached|shared radio requires one effective authority"
                      r"|invalid endpoint/resource/authority association |missing required |unexpected (?:connection|binding)/bypass "
                      r"|missing or unexpected boundary port roles|semantic exchange signature mismatch |wrong exchange direction "
                      r"|wrong semantic item type |wrong port definition |missing part |unexpected part "
                      r"|wrong part type or population |unexpected reference )")

# Fixture models (R3 to R6, R10): one added model file each, with its edits of the architecture.
STATION_PART = "part catAdapter : RustRadioDriver;"
STATION_DEFINITION = "part def StationProcess {"
SERVICE_PORT = "port audioStatus : ~AudioStatus;"
TOP_PART = "part radioControlAttachments[*] : RadioControlAttachment;"
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
    part def ListeningProgram { port messages : ~ProbeMessages; }
    part def ProbeAttachment {
        ref part listener : ListeningProgram :> WstxArchitecture::physicalStation.listeners;
        ref part station : WstxArchitecture::StationProcess :> WstxArchitecture::physicalStation.backend.stations;
        connection probeMessages connect station.station.probe to listener.messages;
    }
    part def ProxyAuthority :> WstxArchitecture::RadioAuthority;
    part def ProxyDriver :> WstxArchitecture::RustRadioDriver;
}
"""
UDP_EDITS = ((SERVICE_PORT, SERVICE_PORT + "\n        port probe : WstxProbeUdp::ProbeMessages;"),
             (TOP_PART, TOP_PART + "\n        part listeners[*] : WstxProbeUdp::ListeningProgram;"
                                   "\n        part probeAttachments[*] : WstxProbeUdp::ProbeAttachment;"))
# The entries of the R4 model, written by hand.
UDP_ORACLE = {
    "parts": {"physicalStation.listeners": {"type": "WstxProbeUdp::ListeningProgram", "population": "0..*"},
              "physicalStation.probeAttachments": {"type": "WstxProbeUdp::ProbeAttachment", "population": "0..*"}},
    "references": {
        "physicalStation.probeAttachments.listener": {"type": "WstxProbeUdp::ListeningProgram", "population": "1..1",
                                                      "target": "physicalStation.listeners"},
        "physicalStation.probeAttachments.station": {"type": "WstxArchitecture::StationProcess", "population": "1..1",
                                                     "target": "physicalStation.backend.stations"}},
    "contracts": {"WstxProbeUdp::ProbeMessages": {"items": {"datagram": ["out", "WstxProbeUdp::Datagram"],
                                                            "reply": ["in", "WstxProbeUdp::Reply"]}}},
    "ports": {"physicalStation.backend.stations.station.probe": "WstxProbeUdp::ProbeMessages",
              "physicalStation.listeners.messages": "~WstxProbeUdp::ProbeMessages"},
    "connections": {"physicalStation.probeAttachments": [["station.station.probe", "listener.messages"]]},
}
UDP_COUNTS = {"parts": 29, "references": 10, "ports": 58, "connections": 47}


def authority_entries(path, type_name):
    """The oracle entries of one more authority part at `path`: part, ports and bindings."""
    return {"parts": {path: {"type": type_name, "population": "1..1"}},
            "ports": {path + ".requests": "~WstxArchitecture::RadioControl",
                      path + ".authorized": "WstxArchitecture::RadioControl"},
            "bindings": {path: [["authorized.request", "requests.request"], ["requests.outcome", "authorized.outcome"]]}}


DRIVER_ENTRIES = {"parts": {"physicalStation.backend.stations.proxyDriver": {"type": "WstxProbeUdp::ProxyDriver",
                                                                             "population": "1..1"}},
                  "ports": {"physicalStation.backend.stations.proxyDriver.authorized": "~WstxArchitecture::RadioControl",
                            "physicalStation.backend.stations.proxyDriver.radio": "WstxArchitecture::RadioControl"}}
HOLDER_PACKAGE = "package WstxPartProbe {\n    part def Hidden;\n    part def Holder { part hidden : Hidden; }\n}\n"


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
            "connection probeMessages", "ref part spare : ListeningProgram :> WstxArchitecture::physicalStation.listeners;"
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
        """The integrity check of `output` against `oracle`: a dict, or the text of the file."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "architecture-oracle.json"
            path.write_text(oracle if isinstance(oracle, str) else json.dumps(oracle, indent=1), encoding="utf-8")
            return tool.architecture_integrity(output, path)

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
            with mock.patch.object(tool, "ORACLE", path), mock.patch.object(tool, "validate", return_value=self.accepted), \
                    contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = tool.main(["check"])
            return code, out.getvalue(), err.getvalue()

    def test_complete_resolved_deployment(self):
        self.assertEqual(self.accepted.returncode, 0, self.accepted.stdout + self.accepted.stderr)
        counts = tool.architecture_integrity(self.accepted.stdout)
        self.assertEqual(counts, {"parts": 27, "references": 8, "ports": 56, "connections": 46})

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

    test_frontend_container_cannot_forward_ports = rejects("part def Frontend {", "part def Frontend { port operator : ~LocalInteraction;", "missing or unexpected boundary port roles")

    test_backend_container_cannot_forward_ports = rejects("part def Backend {", "part def Backend { port radioAudio : AudioExchange;", "missing or unexpected boundary port roles")

    test_selected_radio_identity_cannot_be_redirected = rejects("ref part radio : Radio :> physicalStation.radio;", "part otherRadio : Radio; ref part radio : Radio :> otherRadio;", "invalid endpoint/resource/authority association")

    test_missing_encoding_path = rejects("connection encodeModem connect transmit.encode to modes.encode;", "", "missing required connection")

    test_missing_contact_transmit_path = rejects("connection contactTransmit connect qso.transmit to transmit.contacts;", "", "missing required connection")

    test_control_bypasses_common_authority = rejects("connect radioControl.backend to authorityRequest;", "connect radioControl.backend to catAdapter.authorized;", "missing required connection")

    test_duplicate_audio_adapter = rejects("part audioAdapter : AudioDeviceAdapter;", "part audioAdapter : AudioDeviceAdapter; part duplicateAudio : AudioDeviceAdapter;", "duplicate or detached audioAdapter")

    test_duplicate_cat_adapter = rejects("part catAdapter : RustRadioDriver;", "part catAdapter : RustRadioDriver; part duplicateCat : RustRadioDriver;", "duplicate or detached catAdapter")

    test_audio_adapter_must_be_single = rejects("part audioAdapter : AudioDeviceAdapter;", "part audioAdapter[0..1] : AudioDeviceAdapter;", "exactly one direct audioAdapter")

    test_cat_adapter_must_be_single = rejects("part catAdapter : RustRadioDriver;", "part catAdapter[0..1] : RustRadioDriver;", "exactly one direct catAdapter")

    test_audio_adapter_wrong_port = rejects("connect audio.backend to audioAdapter.host;", "connect audio.backend to audioAdapter.radio;", "missing required connection")

    test_cat_adapter_wrong_port = rejects("connect authorizedControl to catAdapter.authorized;", "connect authorizedControl to catAdapter.radio;", "missing required connection")

    test_audio_cat_paths_cannot_be_mixed = rejects("connect audio.backend to audioAdapter.host;", "connect audio.backend to catAdapter.authorized;", "missing required connection")

    test_audio_attachment_selects_bound_radio = rejects("connect station.audioAdapter.radio to station.radioBinding.radio.audio;", "connect station.audioAdapter.radio to physicalStation.radio.audio;", "missing required connection")

    test_cat_attachment_selects_bound_radio = rejects("connect station.catAdapter.radio to station.radioBinding.radio.control;", "connect station.catAdapter.radio to physicalStation.radio.control;", "missing required connection")

    test_split_shared_authority = rejects("ref part authority : RadioAuthority :> physicalStation.backend.radioAuthority;", "part authority : RadioAuthority;", "one effective authority")

    test_swapped_browser_station_association = rejects("ref part station : StationProcess :> physicalStation.backend.stations;", "ref part station : StationProcess :> physicalStation.backend.mcpAttachments.station;", "invalid endpoint/resource/authority association")

    test_wrong_requesting_resource_context = rejects("binding catContext bind catAdapter.authorized.request.resourceContext = radioBinding;", "part otherContext : RadioBinding; binding catContext bind catAdapter.authorized.request.resourceContext = otherContext;", "missing required binding")

    test_wrong_waveform_direction = rejects("in item waveform : Waveform;", "out item waveform : Waveform;", "wrong exchange direction")

    test_receive_modem_provider_conjugation = rejects("port receive : ~ReceiveProcessing;", "port receive : ReceiveProcessing;", "wrong exchange direction")

    test_authority_identity_binding_cannot_be_weakened_to_connection = rejects("binding authorizedContext bind authorized.request = requests.request;", "connection authorizedContext connect authorized.request to requests.request;", "missing required binding")

    test_request_context_binding_cannot_be_weakened_to_connection = rejects("binding requestContext bind authorityRequest.request.resourceContext = radioBinding;", "connection requestContext connect authorityRequest.request.resourceContext to radioBinding;", "missing required binding")

    test_radio_audio_provider_conjugation = rejects("port audio : ~AudioExchange;\n        port control : ~RadioControl;\n    }\n    part def Backend", "port audio : AudioExchange;\n        port control : ~RadioControl;\n    }\n    part def Backend", "wrong exchange direction physicalStation.radio.audio")

    test_radio_control_provider_conjugation = rejects("port audio : ~AudioExchange;\n        port control : ~RadioControl;\n    }\n    part def Backend", "port audio : ~AudioExchange;\n        port control : RadioControl;\n    }\n    part def Backend", "wrong exchange direction physicalStation.radio.control")

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
        listed = {"connections": {owner: [BYPASS_ENDS]}}
        self.assertEqual(self.judge(self.inventory("bypass part"), oracle_with(part, listed))["connections"],
                         MASTER_COUNTS["connections"] + 1)
        self.refuses(self.inventory("bypass inherited"), real_oracle(),
                     "unexpected connection/bypass at physicalStation.backend.stations " + re.escape(" <-> ".join(sorted(BYPASS_ENDS))))

    # Proves: CL-014-03, CL-014-06; TC-DOC-005
    def test_interface_of_another_package_passes_once_listed(self):
        """R4: a port, an outside part and a connection of another package pass when listed."""
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
                "type": "WstxProbeUdp::ListeningProgram", "population": "1..1"}}}), "missing part physicalStation.ghost$"),
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
            ("port path twice", text.replace(anchor, anchor + '    "physicalStation.radio.audio": "~WstxArchitecture::AudioExchange",\n', 1),
             "Invalid architecture oracle: key stated twice: physicalStation.radio.audio"),
            ("direction inout", changed(lambda oracle: oracle["contracts"]["WstxArchitecture::RadioControl"]["items"]["request"]
                                        .__setitem__(0, "inout")),
             "Invalid architecture oracle: direction other than in or out: WstxArchitecture::RadioControl: request"),
            ("population many", changed(lambda oracle: oracle["parts"]["physicalStation.user"].update(population="many")),
             "Invalid architecture oracle: malformed population: physicalStation.user"),
            ("absent contract", changed(lambda oracle: oracle["ports"].update({"physicalStation.user.interaction": "WstxArchitecture::Absent"})),
             "Invalid architecture oracle: port names an absent contract: physicalStation.user.interaction"),
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
        self.assertIn("Architecture integrity passed: 27 parts, 8 references, 56 ports, 46 connections; runtime behavior not proved.", out)

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
        self.refuses(self.inventory("library deployment"), real_oracle(), "one physical deployment")
        self.refuses(self.inventory("library view"), real_oracle(), "views may expose")


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
