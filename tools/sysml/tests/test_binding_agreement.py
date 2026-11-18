"""TR-14: model and code are bound both ways: each test a tag names is in its case's binding,
and each file a case binds holds a test whose tag names the case.

Isolated fixtures in a temporary folder; every message is written by hand from the fixture
lines below.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("binding_agreement_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

MODEL_KEY = "docs/sysml/backend/modes/Decode.sysml"


def case(identity, test="server/tests/decode.rs", method=""):
    return (f"    verification '{identity}' {{\n"
            "        doc /* A window of known signals. */\n"
            "        subject modes : ModeFunctions;\n"
            "        @TestLevel { cost = 2; location = TestLocation::developmentPc; }\n"
            f"        @Automation {{ run = AutomationState::implemented;{method} }}\n"
            "        objective { verify 'CL-022-01'; }\n"
            f'        @TestedBy {{ test = "{test}"; }}\n'
            "    }\n")


FILES = {
    "docs/sysml/Requirements.sysml": "// Canonical authority: SysML\npackage WstxRequirements {\n"
                                     "    requirement 'FR-004' {\n        doc /* Decoding */\n    }\n}\n",
    "docs/sysml/Shack.sysml": "package WstxShack {\n}\n",
    "docs/sysml/Context.sysml": "package WstxContext {\n}\n",
    MODEL_KEY: """package WstxDecode {
    private import WstxRequirements::*;
    private import WstxModelBindings::*;

    requirement 'CL-022-01' {
        subject modes : ModeFunctions;
        doc /* The decoder MUST decode every FT8 signal of a window. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-004'; end #derive ::> 'CL-022-01'; }
""" + case("TC-022-004") + case("TC-022-005") + "}\n",
    "server/tests/decode.rs": ("// Proves: TC-022-004\n#[test]\nfn known_signals() {}\n\n"
                               "// Proves: TC-022-004, TC-022-005\n#[test]\nfn weak_signals() {}\n"),
    "server/tests/plain.rs": "#[test]\nfn plain() {}\n",
}


class BindingAgreementTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)

    def build(self, changes=()):
        """The catalog of the fixture, in a new folder, with each (path, old, new) replaced once,
        or a new file where old is None."""
        self.root = Path(tempfile.mkdtemp(dir=self.base))
        files = dict(FILES)
        for path, old, new in changes:
            if old is None:
                files[path] = new
            else:
                self.assertEqual(files[path].count(old), 1, old)
                files[path] = files[path].replace(old, new)
        for path, text in files.items():
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8")
        return tool.canonical_catalog(self.root / "docs/sysml", self.root)

    def refused(self, changes):
        """The message of the first refusal of the catalog or the agreement."""
        with self.assertRaises(ValueError) as refused:
            tool.binding_agreement(self.build(changes), self.root)
        return str(refused.exception)

    def test_tagged_tests_in_their_bindings_are_accepted(self):
        """TR-14: tests in a bound file, tests bound by name, and a manual case's untagged file are accepted."""
        accepted = {
            "file": [],
            "test names": [(MODEL_KEY, case("TC-022-004"), case(
                "TC-022-004", "server/tests/decode.rs::known_signals; server/tests/decode.rs::weak_signals"))],
            "manual case, untagged file": [(MODEL_KEY, case("TC-022-005"), case(
                "TC-022-005", "server/tests/decode.rs; server/tests/plain.rs", ' method = "manual";'))],
        }
        for label, changes in accepted.items():
            with self.subTest(label):
                self.assertIsNone(tool.binding_agreement(self.build(changes), self.root))

    def test_each_test_or_file_outside_the_binding_is_refused(self):
        """TR-14: a tagged test its case's binding lacks, a bound file without a test that names the case,
        a tag on no test and a bound test name that no test has are each refused."""
        faults = {
            "binding lacking the test": (
                [(MODEL_KEY, case("TC-022-004"), case("TC-022-004", "server/tests/decode.rs::weak_signals"))],
                "Proves tag outside the verification binding: TC-022-004: server/tests/decode.rs::known_signals"),
            "tagged test in an unbound file": (
                [("server/tests/window.rs", None, "// Proves: TC-022-005\n#[test]\nfn full_window() {}\n")],
                "Proves tag outside the verification binding: TC-022-005: server/tests/window.rs::full_window"),
            "bound file naming no case": (
                [(MODEL_KEY, case("TC-022-005"), case("TC-022-005", "server/tests/decode.rs; server/tests/plain.rs"))],
                "No Proves tag or named-test identity for TC-022-005: server/tests/plain.rs"),
            "tag on no test": (
                [("server/tests/helper.rs", None, "// Proves: TC-022-005\nfn helper() {}\n"),
                 (MODEL_KEY, case("TC-022-005"), case("TC-022-005", "server/tests/decode.rs; server/tests/helper.rs"))],
                "No Proves tag or named-test identity for TC-022-005: server/tests/helper.rs"),
            "bound test name no test has": (
                [(MODEL_KEY, case("TC-022-005"), case("TC-022-005", "server/tests/decode.rs::full_window"))],
                "Missing executable test symbol: TC-022-005: server/tests/decode.rs::full_window"),
        }
        for label, (changes, message) in faults.items():
            with self.subTest(label):
                self.assertEqual(self.refused(changes), message)


if __name__ == "__main__":
    unittest.main()
