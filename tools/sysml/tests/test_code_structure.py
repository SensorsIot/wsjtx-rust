"""TR-17: the code follows the tree (M2.3), on a temporary root with model and code files.

Every code module belongs to exactly one part by its part definition's `@ImplementedIn`;
a module of no part stands in `server/src/shared/`; a part's modules, and those its
clauses name, stand in its folder or are named by its part definition's `@CodeDiffers`,
which names no module inside the folder. A test file and a module declared only under
`#[cfg(test)]` or from a test file are no modules. Expected lines are written by hand.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("code_structure_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CLOCK_PART = "docs/sysml/backend/clock/Clock.sysml"
TRANSMIT_PART = "docs/sysml/backend/transmit/Transmit.sysml"
MARKER = ('        @CodeDiffers { what = "Its code also stands in server/src/time/sync.rs, client/clock.html and '
          'server/src/transmit/schedule.rs."; }\n')
FILES = {
    CLOCK_PART: """package WstxClockPart {
    part def ClockService {
        @ImplementedIn {
            module = "server/src/clock/mod.rs; server/src/clock/air.rs; "
                + "server/src/time/sync.rs; client/src/clock/clock.js; client/src/clock/clock.css; "
                + "client/clock.html";
        }
""" + MARKER + """    }
}
""",
    TRANSMIT_PART: """package WstxTransmitPart {
    part def TransmitService {
        @ImplementedIn { module = "server/src/transmit/schedule.rs"; }
    }
}
""",
    "docs/sysml/backend/clock/StationClock.sysml": """package WstxStationClock {
    private import WstxClockPart::ClockService;

    requirement 'CL-043-01' {
        subject clock : ClockService;
        doc /* The clock MUST start transmissions on station time. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/clock/air.rs; server/src/transmit/schedule.rs"; }
    }
}
""",
    "server/src/clock/mod.rs": "pub mod air;\n#[cfg(test)]\nmod air_checks;\n#[cfg(test)]\nmod tests;\n",
    "server/src/clock/air.rs": "pub fn now() -> i64 {\n    0\n}\n",
    "server/src/clock/air_checks.rs": "#[test]\nfn holds() {}\n",
    "server/src/clock/air_tests.rs": "#[test]\nfn starts() {}\n",
    "server/src/clock/tests.rs": "mod fixtures;\n#[test]\nfn runs() {}\n",
    "server/src/clock/tests/fixtures.rs": "pub fn clock() {}\n",
    "server/src/time/sync.rs": "pub fn sync() {}\n",
    "server/src/transmit/schedule.rs": "pub fn slot() {}\n",
    "server/src/shared/util.rs": "pub fn clamp() {}\n",
    "client/src/clock/clock.js": "export const tick = () => 0;\n",
    "client/src/clock/clock.css": ".clock { color: black; }\n",
    "client/clock.html": '<script src="src/clock/clock.js"></script>\n',
}
ENTRIES = {"CL-043-01": {"file": "backend/clock/StationClock.sysml", "line": 4, "state": "implemented",
                         "own": ["server/src/clock/air.rs", "server/src/transmit/schedule.rs"]}}


class CodeStructureTest(unittest.TestCase):
    def faults(self, edits=()) -> list[str]:
        """The fault lines of the fixture after each (path, old, new) edit; old None writes
        the file."""
        files = dict(FILES)
        for path, old, new in edits:
            if old is None:
                files[path] = new
            else:
                self.assertIn(old, files[path])
                files[path] = files[path].replace(old, new, 1)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for path, text in files.items():
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).write_text(text, encoding="utf-8", newline="\n")
            model = tool.Model(root / "docs/sysml")
            links, link_faults = tool.code_links(model, ENTRIES)
            self.assertEqual(link_faults, [])
            return tool.fault_lines(tool.structure_faults(model, links, root))

    def test_each_module_in_one_part_folder_is_accepted(self):
        """TR-17: each module in one part's folder, a module and a page outside it named by
        the part's CodeDiffers, a shared module, test files and modules declared only under
        `#[cfg(test)]` or from a test file are accepted."""
        self.assertEqual(self.faults(), [])

    def test_module_of_no_part_is_refused(self):
        """TR-17: a module no part names outside server/src/shared/ is refused."""
        cases = {
            "new file": ([("server/src/clock/extra.rs", None, "pub fn extra() {}\n")],
                         ["module of no part: server/src/clock/extra.rs"]),
            "declared outside cfg(test) too": ([("server/src/clock/mod.rs", "pub mod air;\n", "pub mod air;\nmod air_checks;\n")],
                                               ["module of no part: server/src/clock/air_checks.rs"]),
            "declared from a code file too": (
                [("server/src/clock/air.rs", "pub fn now", '#[path = "tests/fixtures.rs"]\nmod fixtures;\npub fn now')],
                ["module of no part: server/src/clock/tests/fixtures.rs"]),
        }
        for name, (edits, expected) in cases.items():
            with self.subTest(name):
                self.assertEqual(self.faults(edits), expected)

    def test_module_of_two_parts_is_refused(self):
        """TR-17: a module two part definitions name is refused."""
        edits = [(TRANSMIT_PART, '"server/src/transmit/schedule.rs"', '"server/src/transmit/schedule.rs; server/src/clock/air.rs"')]
        self.assertEqual(self.faults(edits), [
            "module of TransmitService outside its folder without CodeDiffers: server/src/clock/air.rs",
            "module of two parts: backend/clock, backend/transmit: server/src/clock/air.rs",
        ])

    def test_module_outside_its_folder_unmarked_is_refused(self):
        """TR-17: a part's module, or a module its clause names, outside the part's folder
        and not named by its CodeDiffers is refused."""
        cases = {
            "part's module": ([(CLOCK_PART, MARKER, MARKER.replace("server/src/time/sync.rs, ", ""))],
                              ["module of ClockService outside its folder without CodeDiffers: server/src/time/sync.rs"]),
            "part's page": ([(CLOCK_PART, MARKER, MARKER.replace("client/clock.html and", "and"))],
                            ["module of ClockService outside its folder without CodeDiffers: client/clock.html"]),
            "clause's module": ([(CLOCK_PART, MARKER, MARKER.replace(" and server/src/transmit/schedule.rs", ""))],
                                ["module of ClockService outside its folder without CodeDiffers: server/src/transmit/schedule.rs"]),
        }
        for name, (edits, expected) in cases.items():
            with self.subTest(name):
                self.assertEqual(self.faults(edits), expected)

    def test_marker_naming_a_module_inside_is_refused(self):
        """TR-17: a CodeDiffers naming a module inside the part's folder is refused."""
        for inside in ("server/src/clock/air.rs", "client/src/clock/clock.css"):
            with self.subTest(inside):
                edits = [(CLOCK_PART, "client/clock.html and", f"client/clock.html, {inside} and")]
                self.assertEqual(self.faults(edits), [
                    f"CodeDiffers names a module inside the folder: {inside}: backend/clock/Clock.sysml:8",
                ])


if __name__ == "__main__":
    unittest.main()
