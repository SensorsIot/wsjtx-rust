"""TC-DOC-005: independent architecture oracle using the real pinned Pilot AST."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("architecture_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class ArchitectureIntegrityTests(unittest.TestCase):
    # Proves: CL-014-03, CL-014-06; TC-DOC-005. No viewer/parser substitute.
    @classmethod
    def setUpClass(cls):
        cls.cache = Path.home() / ".cache/wsjtx-rust/sysml-tools"
        cls.source = (tool.MODELS / "Architecture.sysml").read_text(encoding="utf-8")
        cls.requirements = tool.MODELS / "Requirements.sysml"
        cls.accepted = tool.validate(cls.model_paths(), cls.cache, inventory=True)

    @classmethod
    def model_paths(cls, architecture=None):
        original = tool.MODELS / "Architecture.sysml"
        companions = sorted(path for path in tool.MODELS.glob("*.sysml")
                            if path not in (cls.requirements, original))
        return [cls.requirements, architecture or original, *companions]

    def test_complete_resolved_deployment(self):
        self.assertEqual(self.accepted.returncode, 0, self.accepted.stdout + self.accepted.stderr)
        counts = tool.architecture_integrity(self.accepted.stdout)
        self.assertEqual(counts, {"parts": 27, "references": 8, "ports": 56, "connections": 46})

    def reject(self, original, replacement, diagnostic):
        self.assertIn(original, self.source, "mutation no longer targets the accepted architecture")
        mutated = self.source.replace(original, replacement, 1)
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "Architecture.sysml"
            model.write_text(mutated, encoding="utf-8")
            result = tool.validate(self.model_paths(model), self.cache, inventory=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("syntax/name/semantic validation passed", result.stdout)
        with self.assertRaisesRegex(ValueError, diagnostic):
            tool.architecture_integrity(result.stdout)

    def test_companion_property_type_resolves_without_changing_architecture(self):
        mutated = self.source.replace("package WstxArchitecture {", "package WstxArchitecture {\n"
                                      "    attribute propertyOwnerProbe : WstxProfiles::Settings;", 1)
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "Architecture.sysml"
            model.write_text(mutated, encoding="utf-8")
            result = tool.validate(self.model_paths(model), self.cache, inventory=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("syntax/name/semantic validation passed", result.stdout)
        self.assertEqual(tool.architecture_integrity(result.stdout),
                         tool.architecture_integrity(self.accepted.stdout))

    def test_undefined_property_type_fails_full_validation(self):
        mutated = self.source.replace("package WstxArchitecture {", "package WstxArchitecture {\n"
                                      "    attribute propertyOwnerProbe : WstxProfiles::UndefinedPropertyType;", 1)
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "Architecture.sysml"
            model.write_text(mutated, encoding="utf-8")
            result = tool.validate(self.model_paths(model), self.cache, inventory=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Couldn't resolve reference to Type 'WstxProfiles::UndefinedPropertyType'", result.stdout)
        self.assertNotIn("syntax/name/semantic validation passed", result.stdout)

    def test_missing_selected_browser_direct_link(self):
        self.reject("connection browserStation connect browser.station to station.web.client;", "", "missing required connection")

    def test_frontend_container_cannot_forward_ports(self):
        self.reject("part def Frontend {", "part def Frontend { port operator : ~LocalInteraction;", "missing or unexpected boundary port roles")

    def test_backend_container_cannot_forward_ports(self):
        self.reject("part def Backend {", "part def Backend { port radioAudio : AudioExchange;", "missing or unexpected boundary port roles")

    def test_selected_radio_identity_cannot_be_redirected(self):
        self.reject("ref part radio : Radio :> physicalStation.radio;", "part otherRadio : Radio; ref part radio : Radio :> otherRadio;", "invalid endpoint/resource/authority association")

    def test_missing_encoding_path(self):
        self.reject("connection encodeModem connect transmit.encode to modes.encode;", "", "missing required connection")

    def test_missing_contact_transmit_path(self):
        self.reject("connection contactTransmit connect qso.transmit to transmit.contacts;", "", "missing required connection")

    def test_control_bypasses_common_authority(self):
        self.reject("connect radioControl.backend to authorityRequest;", "connect radioControl.backend to catAdapter.authorized;", "missing required connection")

    def test_duplicate_audio_adapter(self):
        self.reject("part audioAdapter : AudioDeviceAdapter;", "part audioAdapter : AudioDeviceAdapter; part duplicateAudio : AudioDeviceAdapter;", "duplicate or detached audioAdapter")

    def test_duplicate_cat_adapter(self):
        self.reject("part catAdapter : RustRadioDriver;", "part catAdapter : RustRadioDriver; part duplicateCat : RustRadioDriver;", "duplicate or detached catAdapter")

    def test_audio_adapter_must_be_single(self):
        self.reject("part audioAdapter : AudioDeviceAdapter;", "part audioAdapter[0..1] : AudioDeviceAdapter;", "exactly one direct audioAdapter")

    def test_cat_adapter_must_be_single(self):
        self.reject("part catAdapter : RustRadioDriver;", "part catAdapter[0..1] : RustRadioDriver;", "exactly one direct catAdapter")

    def test_audio_adapter_wrong_port(self):
        self.reject("connect audio.backend to audioAdapter.host;", "connect audio.backend to audioAdapter.radio;", "missing required connection")

    def test_cat_adapter_wrong_port(self):
        self.reject("connect authorizedControl to catAdapter.authorized;", "connect authorizedControl to catAdapter.radio;", "missing required connection")

    def test_audio_cat_paths_cannot_be_mixed(self):
        self.reject("connect audio.backend to audioAdapter.host;", "connect audio.backend to catAdapter.authorized;", "missing required connection")

    def test_audio_attachment_selects_bound_radio(self):
        self.reject("connect station.audioAdapter.radio to station.radioBinding.radio.audio;", "connect station.audioAdapter.radio to physicalStation.radio.audio;", "missing required connection")

    def test_cat_attachment_selects_bound_radio(self):
        self.reject("connect station.catAdapter.radio to station.radioBinding.radio.control;", "connect station.catAdapter.radio to physicalStation.radio.control;", "missing required connection")

    def test_split_shared_authority(self):
        self.reject("ref part authority : RadioAuthority :> physicalStation.backend.radioAuthority;", "part authority : RadioAuthority;", "one effective authority")

    def test_swapped_browser_station_association(self):
        self.reject("ref part station : StationProcess :> physicalStation.backend.stations;", "ref part station : StationProcess :> physicalStation.backend.mcpAttachments.station;", "invalid endpoint/resource/authority association")

    def test_wrong_requesting_resource_context(self):
        self.reject("binding catContext bind catAdapter.authorized.request.resourceContext = radioBinding;", "part otherContext : RadioBinding; binding catContext bind catAdapter.authorized.request.resourceContext = otherContext;", "missing required binding")

    def test_wrong_waveform_direction(self):
        self.reject("in item waveform : Waveform;", "out item waveform : Waveform;", "wrong exchange direction")

    def test_receive_modem_provider_conjugation(self):
        self.reject("port receive : ~ReceiveProcessing;", "port receive : ReceiveProcessing;", "wrong exchange direction")

    def test_authority_identity_binding_cannot_be_weakened_to_connection(self):
        self.reject("binding authorizedContext bind authorized.request = requests.request;", "connection authorizedContext connect authorized.request to requests.request;", "missing required binding")

    def test_request_context_binding_cannot_be_weakened_to_connection(self):
        self.reject("binding requestContext bind authorityRequest.request.resourceContext = radioBinding;", "connection requestContext connect authorityRequest.request.resourceContext to radioBinding;", "missing required binding")

    def test_radio_audio_provider_conjugation(self):
        self.reject("port audio : ~AudioExchange;\n        port control : ~RadioControl;\n    }\n    part def Backend", "port audio : AudioExchange;\n        port control : ~RadioControl;\n    }\n    part def Backend", "wrong exchange direction physicalStation.radio.audio")

    def test_radio_control_provider_conjugation(self):
        self.reject("port audio : ~AudioExchange;\n        port control : ~RadioControl;\n    }\n    part def Backend", "port audio : ~AudioExchange;\n        port control : RadioControl;\n    }\n    part def Backend", "wrong exchange direction physicalStation.radio.control")

    def test_audio_playback_semantic_item_type(self):
        self.reject("out item playback : SampleBlock;", "out item playback : Recording;", "wrong semantic item type")

    def test_disconnected_parallel_world(self):
        self.reject("part physicalStation {", "part detachedStations[*] : StationProcess; part physicalStation {", "one physical deployment")

    def test_view_cannot_create_semantics(self):
        self.reject("expose physicalStation::*;", "expose physicalStation::*; part inventedStation : StationProcess;", "views may expose")

    def test_missing_inventory_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "missing resolved Pilot inventory"):
            tool.architecture_integrity("semantic validation passed without inventory")


if __name__ == "__main__":
    unittest.main()
