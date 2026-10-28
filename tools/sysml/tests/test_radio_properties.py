"""Independent Hamlib source/property reconciliation; cost 2, no radio or Java.

The source table was authored from pinned rig.h, not exported from the model.
Full Pilot and the independent physical-graph oracle remain separate checks.
"""
import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("radio_model_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


def body(text, name):
    match = re.search(r"\b(?:attribute|part|action|constraint) def " + re.escape(name) + r"\b[^{}]*\{", text)
    if not match:
        raise AssertionError("missing property type " + name)
    return tool.declaration_body(text, match.end() - 1)


def field(text, name):
    match = re.search(r"\battribute " + re.escape(name) + r"\s*:\s*([\w:]+)", text)
    if not match:
        raise AssertionError("missing owned property " + name)
    return match.group(1)


class RadioPropertyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = (ROOT / "docs/sysml/Architecture.sysml").read_text(encoding="utf-8")
        cls.code = tool.without_comments(cls.text)

    # Proves: ComponentPropertyOwnership, RadioModelReferenceSeparation.
    def test_independent_standard_source_coverage(self):
        rows = [line.split("|") for line in Path(__file__).with_name("radio_source_coverage.tsv").read_text().splitlines()
                if line and not line.startswith("#")]
        self.assertEqual(len(rows), 114)
        self.assertEqual(len({row[0] for row in rows}), 114)
        additions = [line.split("|") for line in Path(__file__).with_name("radio_additional_coverage.tsv").read_text().splitlines()
                     if line and not line.startswith("#")]
        self.assertGreaterEqual(len(additions), 40)
        for source, path, expected in rows + additions:
            with self.subTest(source=source):
                if expected == "unresolved":
                    self.assertIn("KEYLIGHT observation type", self.text)
                    continue
                owner = body(self.code, "Radio")
                for name in path.split(".")[:-1]:
                    owner = body(self.code, field(owner, name))
                self.assertEqual(field(owner, path.split(".")[-1]), expected)
                if expected == "OperationAvailability":
                    self.assertNotIn("observed", body(self.code, expected))
                    continue
                # Every actual value has a separately typed descriptor and native owner link.
                names = path.split(".")
                group = "audio" if names[0] == "audioControls" else names[0]
                member = names[-1] if len(names) == 2 or group == "tuning" else names[1]
                cap_owner = "Radio" + group[0].upper() + group[1:] + "Capabilities"
                value_owner = "RadioVfoValues" if group == "tuning" else field(body(self.code, "Radio"), names[0])
                value_type = field(body(self.code, value_owner), member)
                readonly = "ReadOnly" if group == "meters" or member in ("audioPresent", "firmwareIdentity") else ""
                self.assertEqual(field(body(self.code, cap_owner), member + "Domain"), readonly + value_type + "Capability")
                self.assertIn("from " + cap_owner + "::" + member + "Domain to " + value_owner + "::" + member + ";", self.code)

    def test_one_current_value_and_quantity_domains(self):
        vfo = body(self.code, "RadioVfoValues")
        self.assertEqual(field(vfo, "frequency"), "HertzValue")
        self.assertNotIn("frequencyHz", vfo.split("transmitFrequencyHz")[0])
        self.assertNotIn("observations", vfo)
        self.assertNotIn("capabilities", vfo)
        self.assertNotIn("observedState", body(self.code, "Radio"))
        self.assertIn(":>> mRef = SI::Hz", body(self.code, "HertzValue"))
        for name, typ in (("frequency", "HertzValue"), ("transmitFrequencyHz", "HertzValue")):
            self.assertEqual(field(body(self.code, "RadioTuningCapabilities"), name + "Domain"), typ + "Capability")
        domain = body(self.code, "HertzValueDomain")
        for name in ("context", "minimum", "maximum", "step", "choices", "associatedMinimumPower", "associatedMaximumPower"):
            field(domain, name)
        context = body(self.code, "RadioPropertyContext")
        for name in ("vfo", "rfMode", "antenna", "region", "direction", "filterSelection"):
            field(context, name)
        for text in ("supported=false", "readable=false", "writable=false", "absence means unknown"):
            self.assertIn(text, self.text)

    def test_readonly_and_temporary_action_authority(self):
        self.assertNotIn("writable", body(self.code, "ReadAccessDescription"))
        for match in re.finditer(r"attribute (\w+) : (\w+)\[", body(self.code, "RadioMetersCapabilities")):
            self.assertTrue(match[2].startswith("ReadOnly"), match[0])
        for action in ("QueryRadioFrequency", "SetRadioFrequency"):
            contract = body(self.text, action)
            self.assertIn("in ref part radio : Radio", contract)
            self.assertIn("RadioAuthority", contract)
            self.assertIn("out attribute actualHz : HertzValue[0..1]", contract)
            self.assertIn("radio.tuning.vfos[*].frequency", contract)
        setter = body(self.text, "SetRadioFrequency")
        self.assertIn("in attribute requestedHz : HertzValue", setter)
        self.assertIn("never copies requestedHz", setter)
        self.assertIn("ACK alone is not", setter)
        self.assertIn("requested >= lower and requested <= upper", body(self.code, "FrequencyWithinApplicableRange"))
        self.assertNotIn("attribute meters", body(self.code, "RadioSettings"))
        self.assertIn("read-only/unknown-access/context-invalid", body(self.text, "ApplyRadioProperties"))
        self.assertIn("Projection ownership", self.text)
        self.assertNotRegex(body(self.code, "Radio"), r"\bpart\b")

    def test_memory_storage_and_source_corrections(self):
        memory = body(self.code, "RadioMemoryValues")
        field(memory, "selectedChannel")
        field(memory, "channels")
        self.assertNotIn("currentBank", memory)
        cap = body(self.code, "RadioMemoryCapabilities")
        for name in ("capacity", "selectBank", "readChannel", "writeChannel", "sendVoiceMemory"):
            field(cap, name)
        channel = body(self.code, "StoredMemoryChannel")
        for name in ("number", "bank", "vfo", "antennas", "receiveFrequencyHz", "receiveMode", "receiveFilterHz",
                     "transmitFrequencyHz", "transmitMode", "transmitFilterHz", "split", "repeaterShift", "repeaterOffsetHz",
                     "tuningStepHz", "ritOffsetHz", "xitOffsetHz", "storedFunctions", "storedLevels", "ctcssToneHz",
                     "ctcssSquelchToneHz", "dcsCode", "dcsSquelchCode", "scanGroup", "flags", "description", "extensionSettings", "tag"):
            field(channel, name)
        self.assertEqual(field(channel, "tag"), "String")
        self.assertEqual(field(body(self.code, "SplitSelection"), "transmitVfo"), "VfoSelection")
        self.assertIn("storage access is not live command permission", self.text.lower().replace("\n", " ").replace("             ", ""))
        self.assertEqual(field(body(self.code, "RadioKeyerSettings"), "breakInDelayMilliseconds"), "MillisecondsValue")
        self.assertEqual(field(body(self.code, "RadioKeyerSettings"), "breakInDelayTenthsOfDot"), "Real")
        self.assertEqual(field(body(self.code, "RadioReceiverSettings"), "filterLowCutoffHz"), "HertzValue")
        self.assertEqual(field(body(self.code, "RadioReceiverSettings"), "squelchMonitorEnabled"), "Boolean")
        self.assertIn("No claim of", self.text)

    def test_oracles_detect_removed_misrouted_and_mistyped_ownership(self):
        receiver = body(self.code, "RadioReceiverSettings")
        for changed in (receiver.replace("attribute squelchMonitorEnabled", "attribute unrelated"),
                        receiver.replace("attribute squelchMonitorEnabled : Boolean", "attribute squelchMonitorEnabled : String")):
            with self.assertRaises(AssertionError):
                self.assertEqual(field(changed, "squelchMonitorEnabled"), "Boolean")
        link = "from RadioReceiverCapabilities::filterLowCutoffHzDomain to RadioReceiverSettings::filterLowCutoffHz;"
        self.assertIn(link, self.code)
        for mutation in (self.code.replace(link, ""), self.code.replace(link, link.replace("to RadioReceiverSettings::filterLowCutoffHz", "to RadioReceiverSettings::rfGainFraction"))):
            with self.assertRaises(AssertionError):
                self.assertIn(link, mutation)


if __name__ == "__main__":
    unittest.main()
