"""TC-DOC-019 L1 to L3: the test level and location of a verification case (CL-014-21).

Isolated fixtures in a temporary folder, without the Pilot; every expected list of pairs
and every message is written by hand from the fixture lines below. L3 runs the pinned
Pilot on the real `ModelBindings` definitions and checks the real model's traces.
"""
import contextlib
import importlib.util
import io
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("test_level_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CACHE = Path.home() / ".cache/wsjtx-rust/sysml-tools"
MARKER = "// Canonical authority: SysML\n"
ENUMS = '''    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }
'''
DEV = "@TestLevel { cost = 2; location = TestLocation::developmentPc; }"
STATION = "@TestLevel { cost = 4; location = TestLocation::station; }"


def model(fr="", clause="", definition="", case="", typed="", holder=""):
    """One FR, its derived clause, a definition `Isolated`, a case TC-001-001, a case
    TC-001-002 typed by `Isolated` and a `part def Holder`; each argument is put into the
    body named by it."""
    return (MARKER + "package WstxRequirements {\n" + ENUMS
            + f"    requirement 'FR-901' {{ {fr} }}\n"
            + "    requirement 'CL-901-01' {\n"
              "        attribute coverage : ImplementationState = ImplementationState::target;\n"
              f"        {clause}\n    }}\n"
            + "    #derivation connection { end #original ::> 'FR-901'; end #derive ::> 'CL-901-01'; }\n"
            + "    verification def Isolated {\n"
              "        attribute automation : AutomationState = AutomationState::planned;\n"
              f"        {definition}\n    }}\n"
            + "    verification 'TC-001-001' {\n"
              "        attribute automation : AutomationState = AutomationState::planned;\n"
              f"        {case}\n        objective {{ verify 'CL-901-01'; }}\n    }}\n"
            + f"    verification 'TC-001-002' : Isolated {{\n        {typed}\n        objective {{ verify 'CL-901-01'; }}\n    }}\n"
            + f"    part def Holder {{ {holder} }}\n"
            + "}\n")


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in tool.SOURCE_BINDING_ROOTS:
            (self.root / name).mkdir()
        self.models = self.root / "docs/sysml"
        self.models.mkdir(parents=True)
        (self.models / "Architecture.sysml").write_text("package WstxArchitecture {}\n", encoding="utf-8")

    def levels(self, **parts):
        (self.models / "Requirements.sysml").write_text(model(**parts), encoding="utf-8")
        entries = tool.canonical_catalog(self.models, self.root, required=set())
        return entries["TC-001-001"]["levels"], entries["TC-001-002"]["levels"]


class AcceptedLevelTests(Fixture):
    # L1, accepted: the levels of each entry are the hand-written pairs
    # Proves: CL-014-21; TC-DOC-019
    def test_levels_with_and_without_package_names_several_and_taken_from_the_definition(self):
        accepted = {
            "none": ({}, ([], [])),
            "without package names": ({"case": DEV}, ([(2, "developmentPc")], [])),
            "with package names": ({"case": "@ModelBindings::TestLevel { cost = 2; "
                                            "location = ModelBindings::TestLocation::developmentPc; }"},
                                   ([(2, "developmentPc")], [])),
            "two pairs on one case": ({"case": STATION + " " + DEV}, ([(2, "developmentPc"), (4, "station")], [])),
            "every location": ({"case": " ".join(f"@TestLevel {{ cost = 3; location = TestLocation::{place}; }}"
                                                 for place in ("flexRadio", "simulator", "station", "developmentPc"))},
                               ([(3, "developmentPc"), (3, "flexRadio"), (3, "simulator"), (3, "station")], [])),
            "cost 1 and cost 5": ({"case": "@TestLevel { cost = 1; location = TestLocation::developmentPc; } "
                                           "@TestLevel { cost = 5; location = TestLocation::station; }"},
                                  ([(1, "developmentPc"), (5, "station")], [])),
            "taken from the definition": ({"definition": "@TestLevel { cost = 2; location = TestLocation::simulator; }"},
                                          ([], [(2, "simulator")])),
            "a case stating its own keeps them": ({"definition": DEV,
                                                   "typed": "@TestLevel { cost = 3; location = TestLocation::flexRadio; }"},
                                                  ([], [(3, "flexRadio")])),
        }
        for label, (parts, expected) in accepted.items():
            with self.subTest(label):
                self.assertEqual(self.levels(**parts), expected)


class RefusedLevelTests(Fixture):
    # L2, refused, one fault at a time, each with its message
    # Proves: CL-014-21; TC-DOC-019
    def test_each_fault_is_refused_naming_the_case_or_the_definition_and_its_key(self):
        case = "Invalid test level: TC-001-001$"
        faults = {
            "cost 0": ({"case": "@TestLevel { cost = 0; location = TestLocation::developmentPc; }"}, case),
            "cost 6": ({"case": "@TestLevel { cost = 6; location = TestLocation::developmentPc; }"}, case),
            'cost "2"': ({"case": '@TestLevel { cost = "2"; location = TestLocation::developmentPc; }'}, case),
            "cost 2.0": ({"case": "@TestLevel { cost = 2.0; location = TestLocation::developmentPc; }"}, case),
            "location lab": ({"case": "@TestLevel { cost = 2; location = TestLocation::lab; }"}, case),
            "location missing": ({"case": "@TestLevel { cost = 2; }"}, case),
            "cost twice": ({"case": "@TestLevel { cost = 2; cost = 2; location = TestLocation::developmentPc; }"}, case),
            "a feature consent": ({"case": "@TestLevel { cost = 2; location = TestLocation::developmentPc; consent = true; }"}, case),
            "the same pair twice": ({"case": DEV + " " + DEV}, case),
            "the metadata keyword form": ({"case": "metadata TestLevel { cost = 2; location = TestLocation::developmentPc; }"}, case),
            "the metadata keyword form, named": ({"case": "metadata level : TestLevel { cost = 2; "
                                                          "location = TestLocation::developmentPc; }"}, case),
            "on an FR": ({"fr": DEV}, "Invalid test level: FR-901$"),
            "on a clause": ({"clause": DEV}, "Invalid test level: CL-901-01$"),
            "on a definition": ({"definition": "@TestLevel { cost = 7; location = TestLocation::developmentPc; }"},
                                "Invalid test level: Isolated: " + re.escape("Requirements.sysml") + "$"),
            "on a part def": ({"holder": DEV}, "Invalid test level: Holder: " + re.escape("Requirements.sysml") + "$"),
        }
        for label, (parts, message) in faults.items():
            with self.subTest(label), self.assertRaisesRegex(ValueError, message):
                self.levels(**parts)


class PilotLevelTests(unittest.TestCase):
    # L3: the pinned Pilot accepts the real definitions and refuses a misspelt feature;
    # traces passes on the real model
    # Proves: CL-014-21; TC-DOC-019
    def test_real_model_bindings_resolve_and_a_misspelt_location_is_refused(self):
        bindings = (ROOT / "docs/sysml/shared/ModelBindings.sysml").read_text(encoding="utf-8")
        self.assertIn("enum def TestLocation { enum developmentPc; enum station; enum simulator; enum flexRadio; }", bindings)
        self.assertIn("metadata def TestLevel { attribute cost : Integer; attribute location : TestLocation; }", bindings)
        requirements = "package WstxRequirements {\n" + ENUMS + "}\n"
        case = ("package Cases {\n    private import ModelBindings::*;\n    verification def Shared {\n"
                "        @TestLevel { cost = 2; location = TestLocation::developmentPc; }\n    }\n"
                "    verification checked : Shared {\n"
                "        @ModelBindings::TestLevel { cost = 4; location = ModelBindings::TestLocation::station; }\n"
                "        @TestLevel { cost = 3; location = TestLocation::flexRadio; }\n    }\n}\n")
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            for name, text in (("Requirements.sysml", requirements), ("ModelBindings.sysml", bindings), ("Cases.sysml", case)):
                (folder / name).write_text(text, encoding="utf-8")
            files = [folder / name for name in ("Requirements.sysml", "ModelBindings.sysml", "Cases.sysml")]
            result = tool.validate(files, CACHE)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed.", result.stdout)
            (folder / "Cases.sysml").write_text(case.replace("location = TestLocation::flexRadio", "locaton = TestLocation::flexRadio"),
                                                encoding="utf-8")
            self.assertNotEqual(tool.validate(files, CACHE).returncode, 0)
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = tool.main(["traces"])
        self.assertEqual(status, 0, errors.getvalue())
        self.assertTrue(output.getvalue().startswith("Canonical source/model trace checks passed: "), output.getvalue())


if __name__ == "__main__":
    unittest.main()
