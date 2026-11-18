"""TR-13: the code link stands on a part definition or a clause; a clause inherits its part's,
and its own wins.

Isolated fixtures in a temporary folder; every link and fault line is written by hand from the
fixture lines below.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("code_links_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

PART_KEY = "backend/clock/Clock.sysml"
FUNCTION_KEY = "backend/clock/StationClock.sysml"
PART_LINK = """        @ImplementedIn {
            module = "server/src/transmit/air.rs; "
                + "server/src/transmit/clock.rs";
        }
"""
MODEL = {
    "Requirements.sysml": "// Canonical authority: SysML\npackage WstxRequirements {\n"
                          "    requirement 'FR-006' {\n        doc /* Time */\n    }\n}\n",
    "Shack.sysml": "package WstxShack {\n}\n",
    "Context.sysml": "package WstxContext {\n}\n",
    PART_KEY: """package WstxClockPart {
    private import WstxModelBindings::ImplementedIn;

    part def ClockService {
""" + PART_LINK + """    }
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
}
""",
}
SOURCES = ("server/src/transmit/air.rs", "server/src/transmit/clock.rs", "server/src/transmit/windows_time.rs",
           "server/src/transmit/time.rs")
INHERITED = ["server/src/transmit/air.rs", "server/src/transmit/clock.rs"]


class CodeLinkTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.models = self.root / "docs/sysml"
        for key in SOURCES:
            self.write(self.root / key, "pub fn station_time() {}\n")

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def links(self, changes=()):
        """(links, fault lines) of the fixture with each (key, old, new) replaced once."""
        for key, text in MODEL.items():
            for changed, old, new in changes:
                if changed == key:
                    self.assertEqual(text.count(old), 1, old)
                    text = text.replace(old, new)
            self.write(self.models / key, text)
        entries = tool.canonical_catalog(self.models, self.root)
        links, faults = tool.code_links(tool.Model(self.models), entries)
        return links, tool.fault_lines(faults)

    def test_clause_inherits_its_part_link(self):
        """TV-041 (TR-13): a clause without its own code link inherits its part definition's, joined value as one."""
        self.assertEqual(self.links(), ({"CL-043-01": INHERITED, "CL-043-02": INHERITED}, []))

    def test_own_link_wins(self):
        """TV-042 (TR-13): a clause's own code link wins over its part's."""
        self.assertEqual(self.links([(FUNCTION_KEY, "@Status { build = ImplementationState::implemented; }",
                                      "@Status { build = ImplementationState::implemented; }\n"
                                      '        @ImplementedIn { module = "server/src/transmit/windows_time.rs"; }')]),
                         ({"CL-043-01": ["server/src/transmit/windows_time.rs"], "CL-043-02": INHERITED}, []))

    def test_each_fault_of_a_code_link_is_refused(self):
        """TV-043 (TR-13): a link on an action definition, two inherited candidates and a delivered clause without
        a link are each refused with key and line."""
        faults = {
            "on an action definition": (
                [(FUNCTION_KEY, "'CL-043-02'; }\n}\n",
                  "'CL-043-02'; }\n\n    action def Estimate {\n"
                  '        @ImplementedIn { module = "server/src/transmit/air.rs"; }\n    }\n}\n')],
                [f"code link on action def Estimate: {FUNCTION_KEY}:21"]),
            "two candidates": (
                [(PART_KEY, "part def ClockService {", "part def ClockService :> TimeKeeper {"),
                 (PART_KEY, "    }\n}\n", "    }\n\n    part def TimeKeeper {\n"
                                          '        @ImplementedIn { module = "server/src/transmit/time.rs"; }\n'
                                          "    }\n}\n")],
                [f"CL-043-01 inherits two code links: ClockService, TimeKeeper: {FUNCTION_KEY}:6",
                 f"CL-043-02 inherits two code links: ClockService, TimeKeeper: {FUNCTION_KEY}:13"]),
            "delivered clause without": (
                [(PART_KEY, PART_LINK, "")],
                [f"CL-043-01 is delivered and has no code link: {FUNCTION_KEY}:6"]),
        }
        for label, (changes, expected) in faults.items():
            with self.subTest(label):
                self.assertEqual(self.links(changes)[1], expected)


if __name__ == "__main__":
    unittest.main()
