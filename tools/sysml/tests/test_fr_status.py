"""TR-12: an FR's status is computed from its clauses and stated nowhere.

Isolated fixtures in a temporary folder; every status, line and message is written by hand
from the fixture lines below.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("fr_status_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

FUNCTION_KEY = "backend/clock/StationClock.sysml"


def clause(identity, fr, state):
    return (f"    requirement '{identity}' {{\n"
            "        subject clock : ClockService;\n"
            "        doc /* The clock MUST keep station time. */\n"
            f"        @Status {{ build = ImplementationState::{state}; }}\n"
            "    }\n"
            f"    #derivation connection {{ end #original ::> '{fr}'; end #derive ::> '{identity}'; }}\n")


MODEL = {
    "Requirements.sysml": """// Canonical authority: SysML
package WstxRequirements {
    requirement 'FR-001' {
        doc /* Station setup */
    }
    requirement 'FR-002' {
        doc /* Audio */
    }
    requirement 'FR-003' {
        doc /* Receive processing */
    }
    requirement 'FR-004' {
        doc /* Decoding */
    }
}
""",
    "Shack.sysml": "package WstxShack {\n}\n",
    "Context.sysml": "package WstxContext {\n}\n",
    FUNCTION_KEY: ("package WstxStationClock {\n    private import WstxRequirements::*;\n"
                   "    private import WstxModelBindings::*;\n"
                   + clause("CL-001-01", "FR-001", "implemented") + clause("CL-001-02", "FR-001", "implemented")
                   + clause("CL-002-01", "FR-002", "implemented") + clause("CL-002-02", "FR-002", "target")
                   + clause("CL-003-01", "FR-003", "target") + clause("CL-003-02", "FR-003", "target")
                   + "}\n"),
}


class Fixture(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.models = self.root / "docs/sysml"
        for name in tool.SOURCE_BINDING_ROOTS:
            (self.root / name).mkdir()
        (self.root / "server/src").mkdir()
        (self.root / "server/src/clock.rs").write_text("pub fn station_time() {}\n", encoding="utf-8")
        for key, text in MODEL.items():
            self.write(key, text)

    def write(self, key, text):
        path = self.models / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def catalog(self):
        return tool.canonical_catalog(self.models, self.root)


class ComputedStatusTests(Fixture):
    def test_status_is_computed_from_the_clauses(self):
        """TR-12: all implemented gives implemented, mixed gives partial, all target or none gives target."""
        entries = self.catalog()
        self.assertEqual({identity: (entries[identity]["status"], entries[identity]["clauses"])
                          for identity in ("FR-001", "FR-002", "FR-003", "FR-004")}, {
            "FR-001": ("implemented", ["CL-001-01", "CL-001-02"]),
            "FR-002": ("partial", ["CL-002-01", "CL-002-02"]),
            "FR-003": ("target", ["CL-003-01", "CL-003-02"]),
            "FR-004": ("target", []),
        })

    def test_computed_status_of_each_mix_of_states(self):
        """TR-12: each mix of clause states gives the status the rule names."""
        mixes = {
            (): "target",
            ("target", "target"): "target",
            ("implemented", "implemented"): "implemented",
            ("implemented", "target"): "partial",
            ("implemented", "partial"): "partial",
            ("partial", "partial"): "partial",
            ("partial", "target"): "partial",
        }
        for states, status in mixes.items():
            with self.subTest(states=states):
                self.assertEqual(tool.computed_status(list(states)), status)

    def test_status_lines_name_each_fr_with_its_counts(self):
        """TR-12: status prints each FR's computed status with its clause counts, then the summary."""
        self.assertEqual(tool.status_lines(self.catalog()), [
            "FR-001 implemented: 2 clauses, 2 implemented, 0 partial, 0 target",
            "FR-002 partial: 2 clauses, 1 implemented, 0 partial, 1 target",
            "FR-003 target: 2 clauses, 0 implemented, 0 partial, 2 target",
            "FR-004 target: 0 clauses, 0 implemented, 0 partial, 0 target",
            "4 FRs: 1 implemented, 1 partial, 2 target",
        ])

    def test_fr_stating_a_status_is_refused(self):
        """TR-12: an FR that states a status or a code link is refused."""
        for label, statement in (("status", "@Status { build = ImplementationState::implemented; }"),
                                 ("code link", '@ImplementedIn { module = "server/src/clock.rs"; }')):
            with self.subTest(label):
                self.write("Requirements.sysml", MODEL["Requirements.sysml"].replace(
                    "doc /* Station setup */", "doc /* Station setup */\n        " + statement))
                with self.assertRaises(ValueError) as refused:
                    self.catalog()
                self.assertEqual(str(refused.exception), "FR states a status or a binding: FR-001")


if __name__ == "__main__":
    unittest.main()
