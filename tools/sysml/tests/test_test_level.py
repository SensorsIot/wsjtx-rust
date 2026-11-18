"""TR-19: the test level and location of a verification case.

Isolated fixtures in a temporary folder; every list of pairs and every message is written by
hand from the fixture lines below. One test runs the pinned Pilot on the real definitions of
WstxModelBindings.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("test_level_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CACHE = Path.home() / ".cache/wsjtx-rust/sysml-tools"
FUNCTION_KEY = "backend/clock/StationClock.sysml"
DEV = "@TestLevel { cost = 2; location = TestLocation::developmentPc; }"
STATION = "@TestLevel { cost = 4; location = TestLocation::station; }"


def requirements(fr=""):
    return ("// Canonical authority: SysML\npackage WstxRequirements {\n"
            f"    requirement 'FR-006' {{\n        doc /* Time */\n        {fr}\n    }}\n}}\n")


def function(clause="", definition="", case="", holder=""):
    """The clause CL-043-01, a verification definition ClockCase, the case TC-043-001 and a part
    definition Holder; each argument is put into the body named by it."""
    return ("package WstxStationClock {\n"
            "    private import WstxRequirements::*;\n"
            "    private import WstxModelBindings::*;\n"
            "    requirement 'CL-043-01' {\n"
            "        subject clock : ClockService;\n"
            "        doc /* The clock MUST hold station time. */\n"
            "        @Status { build = ImplementationState::target; }\n"
            f"        {clause}\n    }}\n"
            "    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-043-01'; }\n"
            f"    verification def ClockCase {{\n        {definition}\n    }}\n"
            "    verification 'TC-043-001' {\n"
            "        doc /* Station time from the PC clock. */\n"
            "        subject clock : ClockService;\n"
            f"        {case}\n"
            "        @Automation { run = AutomationState::planned; }\n"
            "        objective { verify 'CL-043-01'; }\n    }\n"
            f"    part def Holder {{ {holder} }}\n"
            "}\n")


class Fixture(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in tool.SOURCE_BINDING_ROOTS:
            (self.root / name).mkdir()
        self.models = self.root / "docs/sysml"
        (self.models / "backend/clock").mkdir(parents=True)
        (self.models / "Shack.sysml").write_text("package WstxShack {\n}\n", encoding="utf-8")
        (self.models / "Context.sysml").write_text("package WstxContext {\n}\n", encoding="utf-8")

    def levels(self, fr="", **parts):
        (self.models / "Requirements.sysml").write_text(requirements(fr), encoding="utf-8")
        (self.models / FUNCTION_KEY).write_text(function(**parts), encoding="utf-8")
        return tool.canonical_catalog(self.models, self.root)["TC-043-001"]["levels"]


class LevelTests(Fixture):
    def test_levels_of_a_case_are_read(self):
        """TV-119 (TR-19): a case states no level, one, several or each location, with or without package names."""
        accepted = {
            "none": ({}, []),
            "without package names": ({"case": DEV}, [(2, "developmentPc")]),
            "with package names": ({"case": "@WstxModelBindings::TestLevel { cost = 2; "
                                            "location = WstxModelBindings::TestLocation::developmentPc; }"},
                                   [(2, "developmentPc")]),
            "two pairs": ({"case": STATION + " " + DEV}, [(2, "developmentPc"), (4, "station")]),
            "every location": ({"case": " ".join(f"@TestLevel {{ cost = 3; location = TestLocation::{place}; }}"
                                                 for place in ("flexRadio", "simulator", "station", "developmentPc"))},
                               [(3, "developmentPc"), (3, "flexRadio"), (3, "simulator"), (3, "station")]),
            "cost 1 and cost 5": ({"case": "@TestLevel { cost = 1; location = TestLocation::developmentPc; } "
                                           "@TestLevel { cost = 5; location = TestLocation::station; }"},
                                  [(1, "developmentPc"), (5, "station")]),
            "on a verification definition": ({"definition": DEV}, []),
        }
        for label, (parts, expected) in accepted.items():
            with self.subTest(label):
                self.assertEqual(self.levels(**parts), expected)

    def test_each_fault_of_a_level_is_refused(self):
        """TV-120 (TR-19): a cost, location, feature or form outside the rule, and a level on anything but a
        verification, are each refused naming the case or the element and its key."""
        case = "Invalid test level: TC-043-001"
        faults = {
            "cost 0": ({"case": "@TestLevel { cost = 0; location = TestLocation::developmentPc; }"}, case),
            "cost 6": ({"case": "@TestLevel { cost = 6; location = TestLocation::developmentPc; }"}, case),
            'cost "2"': ({"case": '@TestLevel { cost = "2"; location = TestLocation::developmentPc; }'}, case),
            "cost 2.0": ({"case": "@TestLevel { cost = 2.0; location = TestLocation::developmentPc; }"}, case),
            "location lab": ({"case": "@TestLevel { cost = 2; location = TestLocation::lab; }"}, case),
            "location missing": ({"case": "@TestLevel { cost = 2; }"}, case),
            "cost twice": ({"case": "@TestLevel { cost = 2; cost = 2; location = TestLocation::developmentPc; }"},
                           case),
            "another feature": ({"case": "@TestLevel { cost = 2; location = TestLocation::developmentPc; "
                                         "consent = true; }"}, case),
            "the same pair twice": ({"case": DEV + " " + DEV}, case),
            "the metadata keyword form": ({"case": "metadata TestLevel { cost = 2; "
                                                   "location = TestLocation::developmentPc; }"}, case),
            "the metadata keyword form, named": ({"case": "metadata level : TestLevel { cost = 2; "
                                                          "location = TestLocation::developmentPc; }"}, case),
            "on an FR": ({"fr": DEV}, "Invalid test level: FR-006"),
            "on a clause": ({"clause": DEV}, "Invalid test level: CL-043-01"),
            "on a definition, cost 7": ({"definition": "@TestLevel { cost = 7; "
                                                       "location = TestLocation::developmentPc; }"},
                                        "Invalid test level: ClockCase: " + FUNCTION_KEY),
            "on a part definition": ({"holder": DEV}, "Invalid test level: Holder: " + FUNCTION_KEY),
        }
        for label, (parts, message) in faults.items():
            with self.subTest(label):
                with self.assertRaises(ValueError) as refused:
                    self.levels(**parts)
                self.assertEqual(str(refused.exception), message)


class PilotLevelTests(unittest.TestCase):
    def test_pilot_resolves_the_level_and_refuses_a_misspelt_location(self):
        """TV-121 (TR-19): the pinned Pilot resolves TestLevel of WstxModelBindings and refuses a misspelt feature."""
        bindings = (ROOT / "docs/sysml/shared/ModelBindings.sysml").read_text(encoding="utf-8")
        self.assertIn("enum def TestLocation { enum developmentPc; enum station; enum simulator; enum flexRadio; }",
                      bindings)
        self.assertIn("metadata def TestLevel { attribute cost : Integer; attribute location : TestLocation; }",
                      bindings)
        cases = ("package WstxCases {\n    private import WstxModelBindings::*;\n    verification def Shared {\n"
                 "        @TestLevel { cost = 2; location = TestLocation::developmentPc; }\n    }\n"
                 "    verification checked : Shared {\n"
                 "        @WstxModelBindings::TestLevel { cost = 4; "
                 "location = WstxModelBindings::TestLocation::station; }\n"
                 "        @TestLevel { cost = 3; location = TestLocation::flexRadio; }\n    }\n}\n")
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            texts = {"Requirements.sysml": "package WstxRequirements {\n}\n", "ModelBindings.sysml": bindings,
                     "Cases.sysml": cases}
            for name, text in texts.items():
                (folder / name).write_text(text, encoding="utf-8")
            files = [folder / name for name in texts]
            result = tool.validate(files, CACHE)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed.",
                          result.stdout)
            (folder / "Cases.sysml").write_text(cases.replace("location = TestLocation::flexRadio",
                                                              "locaton = TestLocation::flexRadio"), encoding="utf-8")
            self.assertNotEqual(tool.validate(files, CACHE).returncode, 0)


if __name__ == "__main__":
    unittest.main()
