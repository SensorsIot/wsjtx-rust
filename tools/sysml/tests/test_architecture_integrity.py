"""TC-DOC-005: independent architecture oracle using the real pinned Pilot AST."""
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("architecture_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

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
        cls.requirements = tool.MODELS / "Requirements.sysml"
        mutated = [cls.source.replace(PACKAGE, COMPANION_PROBE, 1), cls.source.replace(PACKAGE, UNDEFINED_PROBE, 1)]
        for name in dir(cls):
            original, replacement = getattr(getattr(cls, name), "mutation", (None, None))
            # A mutation whose target is gone is not validated; its test fails on that.
            if original is not None and original in cls.source:
                mutated.append(cls.source.replace(original, replacement, 1))
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            accepted = pool.submit(tool.validate, cls.model_paths(), cls.cache, inventory=True)
            cls.results = {source: pool.submit(cls.validate_architecture, source) for source in mutated}
            cls.accepted = accepted.result()

    @classmethod
    def model_paths(cls, architecture=None):
        files = tool.model_files(tool.MODELS)
        companions = [path for key, path in files.items()
                      if key not in ("Requirements.sysml", "Architecture.sysml")]
        return [files["Requirements.sysml"], architecture or files["Architecture.sysml"], *companions]

    @classmethod
    def validate_architecture(cls, source):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "Architecture.sysml"
            model.write_text(source, encoding="utf-8")
            return tool.validate(cls.model_paths(model), cls.cache, inventory=True)

    def validated(self, mutated):
        """The full validation of `mutated` from setUpClass; a validator exception is raised here."""
        return self.results[mutated].result()

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
            with mock.patch.object(tool, "MODELS", models), \
                    mock.patch.object(ArchitectureIntegrityTests, "requirements", models / "Requirements.sysml", create=True):
                companions = [models / key for key in ("Profiles.sysml", "Udp.sysml", "backend/qso/Part.sysml", "interfaces/Udp.sysml")]
                self.assertEqual(ArchitectureIntegrityTests.model_paths(),
                                 [models / "Requirements.sysml", models / "Architecture.sysml", *companions])
                self.assertEqual(ArchitectureIntegrityTests.model_paths(mutated),
                                 [models / "Requirements.sysml", mutated, *companions])


if __name__ == "__main__":
    unittest.main()
