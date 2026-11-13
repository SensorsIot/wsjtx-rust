"""CL-014-18 (#186): the file rules of the target structure checks (rules 1, 2, 8, 9 and
10) and the pending list's file entries, on isolated model trees without the Pilot.

Each case writes a small model tree, runs the rules as `check` runs them after the Pilot
(no deployment: the inventory is empty) and compares the fault lines with lines written
by hand from the rule text: rule, what, file key and the line of the fault.
"""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("structure_rules_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

REQUIREMENTS = '''// Canonical authority: SysML
package WstxRequirements {
    private import ScalarValues::*;
    enum def ImplementationState { enum target; enum partial; enum implemented; }
}
'''
# Rule 1: a part file, a file of its own folder below it, a file of another part, and the
# interface files the rule text and #53 name.
NAMING = {
    "Requirements.sysml": REQUIREMENTS,
    "shared/Units.sysml": "package WstxUnits { attribute def Hz; }\n",
    "backend/receive/Receive.sysml": '''package WstxReceive {
    private import WstxReceiveData::*;
    private import WstxStationLink::*;
    private import WstxUnits::*;
    private import WstxRequirements::*;
    private import ScalarValues::*;
    doc /* Reads WstxQso::Strategy only in its doc. */
    part def Receive {
        attribute rate : WstxReceiveData::Rate;
    }
}
''',
    "backend/receive/data/Data.sysml": "package WstxReceiveData { attribute def Rate; }\n",
    "backend/qso/Qso.sysml": "package WstxQso { part def Strategy; }\n",
    "interfaces/internal/StationLink.sysml": "package WstxStationLink {\n    private import WstxQsoControl::*;\n}\n",
    "interfaces/internal/QsoControl.sysml": '''package WstxQsoControl {
    item def QsoProgress { attribute count : ScalarValues::Integer; }
}
''',
    "interfaces/internal/ReceiveControl.sysml": "package WstxReceiveControl {\n    private import WstxQsoControl::QsoProgress;\n}\n",
    "interfaces/internal/RadioControl.sysml": "package WstxRadioControl {\n    private import WstxRadioProperties::*;\n}\n",
    "interfaces/external/RadioProperties.sysml": "package WstxRadioProperties { attribute def Band; }\n",
    "interfaces/internal/Hearing.sysml": "package WstxHearing {\n    private import WstxPskReporter::*;\n}\n",
    "interfaces/external/PskReporter.sysml": "package WstxPskReporter { item def Spot { attribute call : ScalarValues::String; } }\n",
    "interfaces/external/Mcp.sysml": "package WstxMcp {\n    private import WstxQsoControl::*;\n}\n",
    "interfaces/internal/OperatingChain.sysml": "package WstxOperatingChain {\n    private import WstxQsoControl::QsoProgress;\n}\n",
    "interfaces/external/Cat.sysml": "package WstxCat {\n}\n",
}
STATION = '''package WstxArchitecture {
    private import WstxReceive::*;
    doc /* The station: composition only. */
    part def Station {
        doc /* Its parts. */
        part receive : Receive;
        ref part peer : Receive;
        connection link connect receive to peer;
        binding same bind receive = peer;
        satisfy 'FR-001' by receive;
    }
    part physical : Station;
    satisfy WstxRequirements::'FR-001' by physical;
}
'''
COMPOSITION = {
    "Requirements.sysml": REQUIREMENTS,
    "Station.sysml": STATION,
    "backend/receive/Receive.sysml": "package WstxReceive { part def Receive; }\n",
    "backend/station/Station.sysml": "package WstxStationPart {\n    attribute def Frequency;\n}\n",
}
FR = '''    requirement 'FR-001' {
        subject station;
        doc /* The station decodes. */
    }
'''
DERIVED = '''    requirement 'CL-003-01' {
        subject station;
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    verification 'TC-001-001' {
        objective { verify 'CL-003-01'; }
    }
    #derivation connection {
        end #original ::> 'FR-001';
        end #derive ::> 'CL-003-01';
    }
'''


def catalog(*parts):
    return REQUIREMENTS.replace("}\n}\n", "}\n" + "".join(parts) + "}\n")


def edited(files, *edits):
    """`files` with each (key, original, replacement) applied once, or a file added."""
    files = dict(files)
    for key, original, replacement in edits:
        if original is None:
            files[key] = replacement
            continue
        if original not in files[key]:
            raise AssertionError(f"edit no longer targets {key}: {original}")
        files[key] = files[key].replace(original, replacement, 1)
    return files


def line_of(text, needle):
    """The line of `needle` in `text`, counted from 1; the needle occurs once."""
    if text.count(needle) != 1:
        raise AssertionError(f"needle not found once: {needle}")
    return text[:text.index(needle)].count("\n") + 1


class FileRuleTests(unittest.TestCase):
    def run_rules(self, files, listed=()):
        """The fault lines `check` prints for `files` with `listed` on the pending list,
        or [] when it prints the passed line."""
        with tempfile.TemporaryDirectory() as directory:
            models = Path(directory) / "docs/sysml"
            for key, text in files.items():
                (models / key).parent.mkdir(parents=True, exist_ok=True)
                (models / key).write_text(text, encoding="utf-8")
            found = tool.model_files(models)
            keys = ["Requirements.sysml", *(key for key in found if key != "Requirements.sysml")]
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                try:
                    lines = tool.structure_lines(models, {}, keys, (set(listed), {}), {})
                except ValueError as error:
                    faults = output.getvalue().splitlines()
                    self.assertEqual(str(error), f"{len(faults)} structure faults")
                    return faults
            self.assertEqual(output.getvalue(), "")
            self.assertRegex(lines[0], r"^Structure checks passed: \d+ files in target form, ")
            return []

    def assert_faults(self, files, expected, listed=()):
        self.assertEqual(self.run_rules(files, listed), expected)

    # S1: rule 1, the packages a file names by import or by qualified name in code
    # Proves: CL-014-18; TC-DOC-016
    def test_rule_1_part_and_interface_files_name_only_allowed_packages(self):
        self.assert_faults(NAMING, [])
        receive = "backend/receive/Receive.sysml"
        cases = {
            "imports another part's package": (
                (receive, "    private import ScalarValues::*;\n", "    private import ScalarValues::*;\n    private import WstxQso::*;\n"),
                "    private import WstxQso::*;", "WstxQso"),
            "names another part in code without an import": (
                (receive, "        attribute rate : WstxReceiveData::Rate;\n",
                 "        attribute rate : WstxReceiveData::Rate;\n        part strategy : WstxQso::Strategy;\n"),
                "part strategy : WstxQso::Strategy;", "WstxQso"),
            "a control interface names StationLink": (
                ("interfaces/internal/QsoControl.sysml", "package WstxQsoControl {\n",
                 "package WstxQsoControl {\n    private import WstxStationLink::*;\n"),
                "private import WstxStationLink::*;", "WstxStationLink"),
            "an external interface names an internal control interface": (
                ("interfaces/external/Cat.sysml", "package WstxCat {\n", "package WstxCat {\n    private import WstxReceiveControl::*;\n"),
                "private import WstxReceiveControl::*;", "WstxReceiveControl"),
            "a control interface names the operating chain": (
                ("interfaces/internal/QsoControl.sysml", "package WstxQsoControl {\n",
                 "package WstxQsoControl {\n    private import WstxOperatingChain::*;\n"),
                "private import WstxOperatingChain::*;", "WstxOperatingChain"),
        }
        for label, (edit, needle, package) in cases.items():
            with self.subTest(label):
                files = edited(NAMING, edit)
                self.assert_faults(files, [f"Structure rule 1: names package {package}: {edit[0]}:{line_of(files[edit[0]], needle)}"])
                with self.subTest("the faulty file on the pending list"):
                    self.assert_faults(files, [], listed=[edit[0]])

    # S2: rule 2, what Station.sysml may hold, at package level and in its part definitions
    # Proves: CL-014-18; TC-DOC-016
    def test_rule_2_station_holds_only_composition_connections_and_fr_allocation(self):
        self.assert_faults(COMPOSITION, [])
        top = "    part physical : Station;\n"
        inside = "        part receive : Receive;\n"
        cases = {
            "an attribute def at package level": (top, "    attribute def Frequency;\n", "attribute def"),
            "a port def at package level": (top, "    port def Link;\n", "port def"),
            "a requirement at package level": (top, "    requirement 'CL-003-01' { subject station; }\n", "requirement"),
            "a satisfy of a clause": (top, "    satisfy 'CL-003-01' by physical;\n", None),
            "a dependency at package level": (top, "    dependency owns from physical to physical;\n", "dependency"),
            "an attribute in a part definition": (inside, "        attribute power : ScalarValues::Real;\n", "attribute"),
            "a port in a part definition": (inside, "        port link : Link;\n", "port"),
        }
        for label, (anchor, statement, word) in cases.items():
            with self.subTest(label):
                files = edited(COMPOSITION, ("Station.sysml", anchor, anchor + statement))
                line = line_of(files["Station.sysml"], statement)
                expected = [f"Structure rule 2: {word} not allowed: Station.sysml:{line}" if word
                            else f"Structure rule 2: satisfy of no FR: Station.sysml:{line}"]
                if word == "dependency":
                    expected.append(f"Structure rule 9: dependency declared: Station.sysml:{line}")
                self.assert_faults(files, expected)
                with self.subTest("Station.sysml on the pending list"):
                    self.assert_faults(files, [], listed=["Station.sysml"])
        with self.subTest("backend/station/Station.sysml is not judged by rule 2"):
            self.assertIn("attribute def Frequency;", COMPOSITION["backend/station/Station.sysml"])
            self.assert_faults(edited(COMPOSITION, ("backend/station/Station.sysml", "attribute def Frequency;",
                                                    "attribute def Frequency;\n    port def Link;")), [])

    # S8: rule 8, an FR states no status, no binding and no issue reference
    # Proves: CL-014-18; TC-DOC-016
    def test_rule_8_fr_states_no_status_binding_or_issue(self):
        self.assert_faults({"Requirements.sysml": catalog(FR)}, [])
        anchor = "        subject station;\n"
        cases = {
            "coverage": "        attribute coverage : ImplementationState = ImplementationState::target;\n",
            "@Status": "        @Status { build = ImplementationState::target; }\n",
            "implementation": '        attribute implementation : String = "server/src/main.rs";\n',
            "@ImplementedIn": '        @ImplementedIn { module = "server/src/main.rs"; }\n',
        }
        for word, statement in cases.items():
            with self.subTest(word):
                text = catalog(FR.replace(anchor, anchor + statement))
                files = {"Requirements.sysml": text}
                self.assert_faults(files, [f"Structure rule 8: FR-001 states {word}: Requirements.sysml:{line_of(text, statement)}"])
                with self.subTest("in a listed file"):
                    self.assert_faults(files, [], listed=["Requirements.sysml"])
        with self.subTest("#40 in its doc"):
            text = catalog(FR.replace("The station decodes.", "The station decodes (see #40)."))
            self.assert_faults({"Requirements.sysml": text},
                               [f"Structure rule 8: FR-001 names issue #40: Requirements.sysml:{line_of(text, '#40')}"])
            self.assert_faults({"Requirements.sysml": text}, [], listed=["Requirements.sysml"])

    # S9: rule 9, no dependency; a derivation is the trace
    # Proves: CL-014-18; TC-DOC-016
    def test_rule_9_no_dependency(self):
        statement = "    dependency owns from 'CL-003-01' to 'FR-001';\n"
        text = catalog(FR, DERIVED, statement)
        self.assert_faults({"Requirements.sysml": text},
                           [f"Structure rule 9: dependency declared: Requirements.sysml:{line_of(text, statement)}"])
        self.assert_faults({"Requirements.sysml": text}, [], listed=["Requirements.sysml"])
        with self.subTest("a derived clause with its verifying case"):
            self.assert_faults({"Requirements.sysml": catalog(FR, DERIVED)}, [])

    # S10: rule 10, every requirement, definition or usage, declares a subject
    # Proves: CL-014-18; TC-DOC-016
    def test_rule_10_every_requirement_declares_a_subject(self):
        with_subject = "    requirement def Decoding { subject station; }\n    requirement decoding : Decoding { subject station; }\n"
        self.assert_faults({"Requirements.sysml": catalog(with_subject)}, [])
        cases = {
            "a definition without a body": ("    requirement def Decoding;\n", "Decoding"),
            "a definition without a subject": ("    requirement def Decoding { doc /* subject in a doc */ }\n", "Decoding"),
            "a usage without a body": ("    requirement decoding : Decoding;\n", "decoding"),
            "a usage whose subject is nested deeper": (
                "    requirement decoding : Decoding { requirement inner { subject station; } }\n", "decoding"),
        }
        for label, (statement, name) in cases.items():
            with self.subTest(label):
                text = catalog(statement)
                self.assert_faults({"Requirements.sysml": text},
                                   [f"Structure rule 10: requirement {name} declares no subject: Requirements.sysml:{line_of(text, statement)}"])


if __name__ == "__main__":
    unittest.main()
