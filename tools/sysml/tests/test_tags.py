"""TR-14: a `Proves:` tag is `// Proves: TC-ddd-ddd`, several joined by `, `, on a test, and
names declared cases only.

Isolated fixtures in a temporary folder; every fault line is written by hand from the fixture
lines below.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("tags_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

TEST_KEY = "server/tests/decode.rs"


def case(identity):
    return (f"    verification '{identity}' {{\n"
            "        doc /* A window of known signals. */\n"
            "        subject modes : ModeFunctions;\n"
            "        @TestLevel { cost = 2; location = TestLocation::developmentPc; }\n"
            "        @Automation { run = AutomationState::implemented; }\n"
            "        objective { verify 'CL-022-01'; }\n"
            f'        @TestedBy {{ test = "{TEST_KEY}"; }}\n'
            "    }\n")


MODEL = {
    "Requirements.sysml": "// Canonical authority: SysML\npackage WstxRequirements {\n"
                          "    requirement 'FR-004' {\n        doc /* Decoding */\n    }\n}\n",
    "Shack.sysml": "package WstxShack {\n}\n",
    "Context.sysml": "package WstxContext {\n}\n",
    "backend/modes/Decode.sysml": """package WstxDecode {
    private import WstxRequirements::*;
    private import WstxModelBindings::*;

    requirement 'CL-022-01' {
        subject modes : ModeFunctions;
        doc /* The decoder MUST decode every FT8 signal of a window. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-004'; end #derive ::> 'CL-022-01'; }
""" + case("TC-022-004") + case("TC-022-005") + "}\n",
}
TESTS = ("// Proves: TC-022-004\n#[test]\nfn known_signals() {}\n\n"
         "// Proves: TC-022-004, TC-022-005\n#[test]\nfn weak_signals() {}\n")


class TagTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for key, text in MODEL.items():
            self.write(self.root / "docs/sysml" / key, text)
        self.write(self.root / TEST_KEY, TESTS)
        self.entries = tool.canonical_catalog(self.root / "docs/sysml", self.root)

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_tags_of_one_and_two_cases_are_accepted(self):
        """TV-120 (TR-14): a tag of one case and a tag of two cases joined by a comma are accepted."""
        self.assertEqual(tool.tag_faults(self.entries, self.root), [])

    def test_each_tag_outside_the_form_is_refused(self):
        """TV-121 (TR-14): a tag naming an FR, a clause, shorthand, an issue number or added text is refused with its line."""
        tags = {
            "FR": "// Proves: FR-004",
            "clause": "// Proves: CL-022-01",
            "shorthand": "// Proves: TC-022-004/005",
            "issue number": "// Proves: TC-022-004 " + "#" + "123",
            "added text": "// Proves: TC-022-004 known signals",
        }
        for label, tag in tags.items():
            with self.subTest(label):
                self.write(self.root / TEST_KEY, TESTS.replace("// Proves: TC-022-004\n", tag + "\n", 1))
                self.assertEqual(tool.tag_faults(self.entries, self.root), [f"Invalid Proves tag: {TEST_KEY}:1"])

    def test_tag_naming_an_undeclared_case_is_refused(self):
        """TV-122 (TR-14): a tag naming a case the model does not declare is refused with its line."""
        self.write(self.root / TEST_KEY, TESTS.replace("// Proves: TC-022-004, TC-022-005",
                                                       "// Proves: TC-022-004, TC-022-009"))
        self.assertEqual(tool.tag_faults(self.entries, self.root),
                         [f"Proves tag names an undeclared case: TC-022-009: {TEST_KEY}:5"])


if __name__ == "__main__":
    unittest.main()
