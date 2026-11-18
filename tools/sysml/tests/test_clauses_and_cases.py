"""TR-11: a clause names its part, derives from one FR its part serves and is carried by a
use-case step; a case is a skeleton with a one-line title.

Isolated fixtures in a temporary folder; Shack's FRs and the interface's ends are given by
hand. Every fault line is written by hand from the fixture lines below.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("clauses_and_cases_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

FUNCTION_KEY = "backend/clock/StationClock.sysml"
INTERFACE_KEY = "interfaces/internal/StationTime.sysml"
CASE = """
    verification 'TC-043-001' {
        doc /* Station time from the PC clock. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-043-01'; }
        @TestedBy { test = "server/tests/clock.rs"; }
    }
"""
MODEL = {
    "Requirements.sysml": """// Canonical authority: SysML
package WstxRequirements {
    requirement 'FR-006' {
        doc /* Time */
    }
    requirement 'FR-007' {
        doc /* Transmit */
    }
    requirement 'FR-008' {
        doc /* Operating */
    }
}
""",
    "Shack.sysml": "package WstxShack {\n}\n",
    "Context.sysml": "package WstxContext {\n}\n",
    "UseCases.sysml": """package WstxUseCases {
    use case def KeepTime {
        action measure {
            requirement :> WstxStationClock::'CL-043-01';
            requirement :> WstxStationClock::'CL-043-02';
            requirement :> WstxStationTime::'CL-044-01';
        }
    }
}
""",
    "backend/clock/Clock.sysml": """package WstxClockPart {
    private import WstxModelBindings::ImplementedIn;

    part def ClockService {
        @ImplementedIn { module = "server/src/transmit/clock.rs"; }
    }
}
""",
    FUNCTION_KEY: """package WstxStationClock {
    private import WstxRequirements::*;
    private import WstxClockPart::ClockService;
    private import WstxModelBindings::*;

    requirement 'CL-043-01' {
        subject clock : ClockService;
        doc /* The clock MUST hold station time as the PC clock plus its correction. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-043-01'; }

    requirement 'CL-043-02' {
        subject clock : ClockService;
        doc /* The clock MUST estimate how far station time is off. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-043-02'; }
""" + CASE + "}\n",
    INTERFACE_KEY: """package WstxStationTime {
    private import WstxRequirements::*;
    private import WstxModelBindings::*;

    interface def StationTimeLink;

    requirement 'CL-044-01' {
        subject link : StationTimeLink;
        doc /* The clock MUST give station time to each function that keeps time. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-044-01'; }
}
""",
}
SOURCES = {
    "server/src/transmit/clock.rs": "pub fn station_time() {}\n",
    "server/tests/clock.rs": "// Proves: TC-043-001\n#[test]\nfn station_time() {}\n",
}
SERVED = {"ClockService": {"FR-006"}, "TransmitService": {"FR-007"}}
ENDS = {"StationTimeLink": ("ClockService", "TransmitService")}


class ClauseTests(unittest.TestCase):
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

    def faults(self, changes=()):
        """The fault lines of the fixture with each (key, old, new) replaced once."""
        for key, text in MODEL.items():
            for changed, old, new in changes:
                if changed == key:
                    self.assertEqual(text.count(old), 1, old)
                    text = text.replace(old, new)
            self.write(self.models / key, text)
        entries = tool.canonical_catalog(self.models, self.root)
        return tool.fault_lines(tool.clause_faults(tool.Model(self.models), entries, SERVED, ENDS))

    def test_skeleton_case_target_clause_and_interface_clause_are_accepted(self):
        """TV-038 (TR-11): a skeleton case, a target clause without case and an interface clause from an end's FR."""
        self.assertEqual(self.faults(), [])

    def test_debugging_clause_without_step_is_accepted(self):
        """TV-039 (TR-11): a clause of a debugging function carries no use-case step."""
        self.assertEqual(self.faults([
            ("UseCases.sysml", "            requirement :> WstxStationClock::'CL-043-02';\n", ""),
            (FUNCTION_KEY, "@Status { build = ImplementationState::target; }",
             "@Status { build = ImplementationState::target; }\n        @Debugging;"),
        ]), [])

    def test_each_fault_of_a_clause_or_case_is_refused(self):
        """TV-040 (TR-11): each way to break the rules of clauses and cases is refused with its message, key and line."""
        faults = {
            "clause without subject": (
                [(FUNCTION_KEY, "    requirement 'CL-043-01' {\n        subject clock : ClockService;\n",
                  "    requirement 'CL-043-01' {\n")],
                [f"CL-043-01 names no subject: {FUNCTION_KEY}:6"]),
            "case without subject": (
                [(FUNCTION_KEY, "PC clock. */\n        subject clock : ClockService;\n", "PC clock. */\n")],
                [f"TC-043-001 names no subject: {FUNCTION_KEY}:20"]),
            "subject another part": (
                [(FUNCTION_KEY, "    requirement 'CL-043-01' {\n        subject clock : ClockService;\n",
                  "    requirement 'CL-043-01' {\n        subject clock : TransmitService;\n")],
                [f"CL-043-01 names a subject other than its part: {FUNCTION_KEY}:6"]),
            "two FRs": (
                [(FUNCTION_KEY, "end #derive ::> 'CL-043-01'; }\n",
                  "end #derive ::> 'CL-043-01'; }\n"
                  "    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-043-01'; }\n")],
                [f"CL-043-01 derives from 2 FRs: {FUNCTION_KEY}:6"]),
            "FR its part does not serve": (
                [(FUNCTION_KEY, "'FR-006'; end #derive ::> 'CL-043-01';", "'FR-007'; end #derive ::> 'CL-043-01';")],
                [f"CL-043-01 derives from FR-007, which its part does not serve: {FUNCTION_KEY}:6"]),
            "interface clause from an FR no end serves": (
                [(INTERFACE_KEY, "'FR-006'", "'FR-008'")],
                [f"CL-044-01 derives from FR-008, which no part at its ends serves: {INTERFACE_KEY}:7"]),
            "two-line title": (
                [(FUNCTION_KEY, "doc /* Station time from the PC clock. */",
                  "doc /* Station time\n             from the PC clock. */")],
                [f"TC-043-001 has a title of 2 lines: {FUNCTION_KEY}:20"]),
            "extra feature": (
                [(FUNCTION_KEY, "        @TestLevel", "        attribute toleranceMs : Integer = 5;\n        @TestLevel")],
                [f"TC-043-001 holds attribute toleranceMs: {FUNCTION_KEY}:23"]),
            "implemented clause without case": (
                [(FUNCTION_KEY, CASE, "")],
                [f"CL-043-01 is implemented and has no case: {FUNCTION_KEY}:6"]),
            "no step, not debugging": (
                [("UseCases.sysml", "            requirement :> WstxStationClock::'CL-043-02';\n", "")],
                [f"CL-043-02 is carried by no use-case step: {FUNCTION_KEY}:13"]),
            "dependency": (
                [(FUNCTION_KEY, "end #derive ::> 'CL-043-02'; }\n",
                  "end #derive ::> 'CL-043-02'; }\n    dependency from 'CL-043-02' to 'FR-006';\n")],
                [f"dependency declared: {FUNCTION_KEY}:19"]),
        }
        for label, (changes, expected) in faults.items():
            with self.subTest(label):
                self.assertEqual(self.faults(changes), expected)


if __name__ == "__main__":
    unittest.main()
