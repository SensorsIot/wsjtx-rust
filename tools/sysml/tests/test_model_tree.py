"""TR-10: the catalog reads every FR, clause and case of the rebuilt forms and refuses the
first fault; TR-20: the states and bindings it reads.

Isolated fixtures in a temporary folder; every entry and message is written by hand from the
fixture lines below.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("model_tree_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CLOCK_KEY = "backend/clock/Clock.sysml"
STATION_CLOCK_KEY = "backend/clock/StationClock.sysml"
MODEL = {
    "Requirements.sysml": """// Canonical authority: SysML
package WstxRequirements {
    requirement 'FR-006' {
        doc /* Time
             Keep station time with the stations heard. */
    }
}
""",
    "Shack.sysml": "package WstxShack {\n}\n",
    "Context.sysml": "package WstxContext {\n}\n",
    CLOCK_KEY: """package WstxClockPart {
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;

    part def ClockService {
        doc /* The station's clock. */
        @ImplementedIn { module = "server/src/transmit/clock.rs"; }
        @DetailTests { tests = "server/src/transmit/clock_tests.rs"; covers = "the correction"; }
    }
}
""",
    STATION_CLOCK_KEY: """package WstxStationClock {
    private import WstxRequirements::'FR-006';
    private import WstxClockPart::ClockService;
    private import WstxModelBindings::*;

    requirement 'CL-043-01' {
        subject clock : ClockService;
        doc /* The clock MUST hold station time as the PC clock plus its correction. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/transmit/air.rs; " + "server/src/transmit/clock.rs"; }
    }
    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-043-01'; }

    verification 'TC-043-001' {
        doc /* Station time from the PC clock. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-043-01'; }
        @TestedBy { test = "server/tests/clock.rs"; }
    }
}
""",
}
SOURCES = {
    "server/src/transmit/air.rs": "pub fn estimate() {}\n",
    "server/src/transmit/clock.rs": "pub fn station_time() {}\n",
    "server/src/transmit/clock_tests.rs": "#[test]\nfn correction() {}\n",
    "server/tests/clock.rs": "// Proves: TC-043-001\n#[test]\nfn station_time() {}\n",
    "server/tests/plain.rs": "#[test]\nfn plain() {}\n",
    "tools/outside.rs": "pub fn outside() {}\n",
}


class Fixture(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.models = self.root / "docs/sysml"
        for key, text in MODEL.items():
            self.write(self.models / key, text)
        for key, text in SOURCES.items():
            self.write(self.root / key, text)

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def change(self, key, old, new):
        """Replace the one occurrence of `old` in the model file `key`."""
        text = MODEL[key]
        self.assertEqual(text.count(old), 1, old)
        self.write(self.models / key, text.replace(old, new))

    def restore(self):
        for key, text in MODEL.items():
            self.write(self.models / key, text)

    def catalog(self):
        return tool.canonical_catalog(self.models, self.root)

    def assertRefused(self, message):
        with self.assertRaises(ValueError) as refused:
            self.catalog()
        self.assertEqual(str(refused.exception), message)


class CatalogTests(Fixture):
    def test_rebuilt_forms_are_read_into_the_catalog(self):
        """TV-090 (TR-10): the FR, the clause with its derivation and the case of the rebuilt forms are read."""
        self.assertEqual(self.catalog(), {
            "FR-006": {"kind": "requirement", "state": "implemented", "status": "implemented", "refs": [],
                       "bindings": [], "manual": False, "file": "Requirements.sysml", "line": 3,
                       "clauses": ["CL-043-01"]},
            "CL-043-01": {"kind": "requirement", "state": "implemented", "refs": [], "manual": False,
                          "file": STATION_CLOCK_KEY, "line": 6, "frs": ["FR-006"], "cases": ["TC-043-001"],
                          "own": ["server/src/transmit/air.rs", "server/src/transmit/clock.rs"]},
            "TC-043-001": {"kind": "verification", "state": "implemented", "refs": ["CL-043-01"],
                           "bindings": ["server/tests/clock.rs"], "manual": False, "file": STATION_CLOCK_KEY,
                           "line": 14, "levels": [(2, "developmentPc")]},
        })

    def test_duplicate_identity_is_refused(self):
        """TV-091 (TR-10): an identity declared twice is refused."""
        self.change("Requirements.sysml", "    }\n}\n", "    }\n    requirement 'FR-006' {\n    }\n}\n")
        self.assertRefused("Duplicate canonical identity: FR-006")

    def test_wrong_kind_is_refused(self):
        """TV-092 (TR-10): an FR or a clause declared as a verification is refused."""
        for old, new, identity in (("requirement 'FR-006' {", "verification 'FR-006' {", "FR-006"),
                                   ("requirement 'CL-043-01' {", "verification 'CL-043-01' {", "CL-043-01")):
            with self.subTest(identity):
                key = "Requirements.sysml" if identity.startswith("FR-") else STATION_CLOCK_KEY
                self.change(key, old, new)
                self.assertRefused("Wrong canonical identity kind: " + identity)
                self.restore()

    def test_unreadable_form_is_refused(self):
        """TV-093 (TR-10): a definition, a typed declaration and a short name with an identity are refused."""
        forms = {
            "definition": ("requirement 'CL-043-01' {", "requirement def 'CL-043-01' {", "CL-043-01"),
            "typed": ("requirement 'CL-043-01' {", "requirement 'CL-043-01' : ClockRule {", "CL-043-01"),
            "specialized": ("requirement 'CL-043-01' {", "requirement 'CL-043-01' :> ClockRule {", "CL-043-01"),
            "short name": ("verification 'TC-043-001' {", "verification <'TC-043-001'> stationTime {", "TC-043-001"),
        }
        for label, (old, new, identity) in forms.items():
            with self.subTest(label):
                self.change(STATION_CLOCK_KEY, old, new)
                self.assertRefused(f"Unreadable canonical declaration: {identity}: {STATION_CLOCK_KEY}")
                self.restore()

    def test_derivation_from_a_missing_fr_is_refused(self):
        """TV-094 (TR-10): a derivation whose original is no declared FR is refused."""
        self.change(STATION_CLOCK_KEY, "end #original ::> 'FR-006';", "end #original ::> 'FR-099';")
        self.assertRefused("Invalid canonical clause derivation: CL-043-01 -> FR-099")

    def test_clause_without_derivation_is_refused(self):
        """TV-095 (TR-10): a clause that derives from no FR is refused."""
        self.change(STATION_CLOCK_KEY,
                    "    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-043-01'; }\n", "")
        self.assertRefused("Canonical clause lacks requirement ownership: CL-043-01")

    def test_required_package_missing_is_refused(self):
        """TV-096 (TR-10): each of WstxRequirements, WstxShack and WstxContext declared by no file is refused."""
        for key, package in (("Requirements.sysml", "WstxRequirements"), ("Shack.sysml", "WstxShack"),
                             ("Context.sysml", "WstxContext")):
            with self.subTest(package):
                self.change(key, "package " + package + " {", "package WstxOther {")
                self.assertRefused("Canonical model packages missing: " + package)
                self.restore()

    def test_required_package_declared_twice_is_refused(self):
        """TV-097 (TR-10): each of WstxRequirements, WstxShack and WstxContext declared by two files is refused."""
        for key, package in (("Requirements.sysml", "WstxRequirements"), ("Shack.sysml", "WstxShack"),
                             ("Context.sysml", "WstxContext")):
            with self.subTest(package):
                again = self.models / "shared/Again.sysml"
                self.write(again, "package " + package + " {\n}\n")
                self.assertRefused(f"Duplicate canonical model package: {package}: {key}, shared/Again.sysml")
                again.unlink()


class StatedTests(Fixture):
    def test_states_and_bindings_are_read_once_each(self):
        """TV-098 (TR-20): package names, a manual method and a binding of joined literals are read as one value each."""
        self.change(STATION_CLOCK_KEY, "@Status { build = ImplementationState::implemented; }",
                    "@WstxModelBindings::Status { build = WstxModelBindings::ImplementationState::partial; }")
        entries = self.catalog()
        self.assertEqual(entries["CL-043-01"]["state"], "partial")
        self.restore()
        self.change(STATION_CLOCK_KEY, '@Automation { run = AutomationState::implemented; }\n'
                                       '        objective { verify \'CL-043-01\'; }\n'
                                       '        @TestedBy { test = "server/tests/clock.rs"; }',
                    '@Automation { run = AutomationState::implemented; method = "manual"; }\n'
                    "        objective { verify 'CL-043-01'; }\n"
                    '        @TestedBy { test = "server/tests/" + "plain.rs"; }')
        entries = self.catalog()
        self.assertEqual((entries["TC-043-001"]["manual"], entries["TC-043-001"]["bindings"]),
                         (True, ["server/tests/plain.rs"]))

    def test_each_fault_of_a_state_or_binding_is_refused(self):
        """TV-099 (TR-20): a missing, unknown or repeated state, a repeated binding or method, an unknown method, a
        missing or outside file, and a delivered case without a test are each refused."""
        status = "@Status { build = ImplementationState::implemented; }"
        automation = "@Automation { run = AutomationState::implemented; }"
        tested = '@TestedBy { test = "server/tests/clock.rs"; }'
        detail = 'tests = "server/src/transmit/clock_tests.rs";'
        faults = {
            "clause without state": (STATION_CLOCK_KEY, status, "",
                                     "Missing or invalid declared model state: CL-043-01"),
            "clause state of no kind": (STATION_CLOCK_KEY, status, "@Status { build = ImplementationState::built; }",
                                        "Missing or invalid declared model state: CL-043-01"),
            "clause state twice": (STATION_CLOCK_KEY, status, status + " " + status,
                                   "Missing or invalid declared model state: CL-043-01"),
            "clause state in the metadata keyword form": (
                STATION_CLOCK_KEY, status, "metadata Status { build = ImplementationState::implemented; }",
                "Missing or invalid declared model state: CL-043-01"),
            "case without state": (STATION_CLOCK_KEY, automation, "",
                                   "Missing or invalid declared model state: TC-043-001"),
            "clause bound twice": (STATION_CLOCK_KEY, status,
                                   status + ' @ImplementedIn { module = "server/src/transmit/clock.rs"; }',
                                   "Invalid verification/implementation metadata: CL-043-01"),
            "case bound twice": (STATION_CLOCK_KEY, tested, tested + " " + tested,
                                 "Invalid verification/implementation metadata: TC-043-001"),
            "another method": (STATION_CLOCK_KEY, automation,
                               '@Automation { run = AutomationState::implemented; method = "by hand"; }',
                               "Invalid verification/implementation metadata: TC-043-001"),
            "missing file": (STATION_CLOCK_KEY, tested, '@TestedBy { test = "server/tests/gone.rs"; }',
                             "Missing or out-of-scope implementation/test binding: TC-043-001: server/tests/gone.rs"),
            "outside the source roots": (STATION_CLOCK_KEY, tested, '@TestedBy { test = "tools/outside.rs"; }',
                                         "Binding outside declared source inputs: TC-043-001: tools/outside.rs; "
                                         "update HOW input coverage before admitting a new root"),
            "delivered case without a test": (STATION_CLOCK_KEY, tested, "",
                                              "Delivered declaration lacks implementation/test binding: TC-043-001"),
            "detail tests missing": (CLOCK_KEY, detail, 'tests = "server/src/transmit/gone_tests.rs";',
                                     "Missing or out-of-scope implementation/test binding: " + CLOCK_KEY
                                     + ": server/src/transmit/gone_tests.rs"),
        }
        for label, (key, old, new, message) in faults.items():
            with self.subTest(label):
                self.change(key, old, new)
                self.assertRefused(message)
                self.restore()


if __name__ == "__main__":
    unittest.main()
