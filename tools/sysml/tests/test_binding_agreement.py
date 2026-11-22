"""TR-14: model and code are bound both ways. Every test below the source roots is one of two
kinds: a contract test, which carries the tag of each case it proves (an attached `Proves:`
tag, or a JavaScript test's title naming the case), each of those cases naming it in its
`@TestedBy` as `<file>::<test>`; or a detail test, which carries no tag, in a file the
`@DetailTests` of a part names. A file may hold both kinds. A `@TestedBy` names tests only.

Isolated fixtures in a temporary folder; every message is written by hand from the fixture
lines below.
"""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("binding_agreement_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

MODEL_KEY = "docs/sysml/backend/modes/Decode.sysml"
BOTH = "server/tests/decode.rs::known_signals; server/tests/decode.rs::weak_signals"
WEAK = "server/tests/decode.rs::weak_signals"


def case(identity, test, method=""):
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
    "docs/sysml/backend/modes/Modes.sysml": ("package WstxModesPart {\n    part def ModeFunctions {\n"
                                             '        @DetailTests { tests = "server/tests/plain.rs"; covers = "a plain window"; }\n'
                                             "    }\n}\n"),
    MODEL_KEY: """package WstxDecode {
    private import WstxRequirements::*;
    private import WstxModelBindings::*;

    requirement 'CL-022-01' {
        subject modes : ModeFunctions;
        doc /* The decoder MUST decode every FT8 signal of a window. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-004'; end #derive ::> 'CL-022-01'; }
""" + case("TC-022-004", BOTH) + case("TC-022-005", WEAK) + "}\n",
    "server/tests/decode.rs": ("// Proves: TC-022-004\n#[test]\nfn known_signals() {}\n\n"
                               "// Proves: TC-022-004, TC-022-005\n#[test]\nfn weak_signals() {}\n"),
    "server/tests/plain.rs": "#[test]\nfn plain() {}\n",
}


def bound(identity, old, new, method=""):
    """The change that binds `identity` by `new` in place of `old`."""
    return (MODEL_KEY, case(identity, old), case(identity, new, method))


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

    def checked(self, changes):
        """`checked_entries` on the fixture, as `check` and `traces` begin."""
        self.build(changes)
        models = self.root / "docs/sysml"
        return tool.checked_entries(tool.Tree(self.root, models, self.root / "docs/WSTX Rust FSD.md",
                                              self.root / "tools/sysml/architecture-oracle.json", None))

    def fault_lines(self, changes):
        """The fault lines `checked_entries` prints before it refuses the fixture."""
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed), self.assertRaises(ValueError):
            self.checked(changes)
        return printed.getvalue().splitlines()

    def refused(self, changes):
        """The message of the first refusal of the catalog or the agreement."""
        with self.assertRaises(ValueError) as refused:
            tool.binding_agreement(self.build(changes), self.root)
        return str(refused.exception)

    def test_tagged_tests_in_their_bindings_are_accepted(self):
        """TV-033 (TR-14): a test bound by name with its case's tag, a tag of two cases bound by
        both, a `#[tokio::test(...)]` bound by name with its tag, a JavaScript test bound by its
        title that names the case, an untagged test in a `@DetailTests` file, and a `@DetailTests`
        file that also holds a tagged test bound by name are accepted."""
        accepted = {
            "by name with its tag, a tag of two cases bound by both, untagged in a DetailTests file": [],
            "tokio test by name with its tag": [
                ("server/tests/window.rs", None,
                 '// Proves: TC-022-005\n#[tokio::test(flavor = "current_thread")]\nasync fn full_window() {}\n'),
                bound("TC-022-005", WEAK, WEAK + "; server/tests/window.rs::full_window")],
            "JavaScript test by its title naming the case": [
                ("tests/decode.test.cjs", None, "test('TC-022-005 a full window', () => {});\n"),
                bound("TC-022-005", WEAK, WEAK + "; tests/decode.test.cjs::TC-022-005 a full window")],
            "DetailTests file holding a tagged test bound by name": [
                ("server/tests/plain.rs", "#[test]\nfn plain() {}\n",
                 "#[test]\nfn plain() {}\n\n// Proves: TC-022-005\n#[test]\nfn tagged_plain() {}\n"),
                bound("TC-022-005", WEAK, WEAK + "; server/tests/plain.rs::tagged_plain")],
        }
        for label, changes in accepted.items():
            with self.subTest(label):
                self.assertIn("TC-022-005", self.checked(changes))

    def test_each_test_or_file_outside_the_binding_is_refused(self):
        """TV-034 (TR-14): a tagged test its case's binding lacks, a tagged test in a file no case
        binds and a bound test name that no test has are each refused."""
        faults = {
            "binding lacking the test": (
                [bound("TC-022-004", BOTH, "server/tests/decode.rs::weak_signals")],
                "Proves tag outside the verification binding: TC-022-004: server/tests/decode.rs::known_signals"),
            "tagged test in an unbound file": (
                [("server/tests/window.rs", None, "// Proves: TC-022-005\n#[test]\nfn full_window() {}\n")],
                "Proves tag outside the verification binding: TC-022-005: server/tests/window.rs::full_window"),
            "bound test name no test has": (
                [bound("TC-022-005", WEAK, "server/tests/decode.rs::full_window")],
                "Missing executable test symbol: TC-022-005: server/tests/decode.rs::full_window"),
        }
        for label, (changes, message) in faults.items():
            with self.subTest(label):
                self.assertEqual(self.refused(changes), message)

    def test_bound_test_without_the_tag_of_its_case_is_refused(self):
        """TV-160 (TR-14): a test a case binds by name that does not carry the case's tag is refused
        with exactly its one line: a `#[test]` without a tag, a `#[test]` whose tag names only
        another case, a `#[tokio::test(flavor = "current_thread")]` without a tag, and a
        JavaScript test bound by its title, without a tag and without the case in its title."""
        window = WEAK + "; server/tests/window.rs::full_window"
        faults = {
            "#[test] without a tag": (
                [("server/tests/window.rs", None, "#[test]\nfn full_window() {}\n"), bound("TC-022-005", WEAK, window)],
                "Bound test lacks the Proves tag of its case: TC-022-005: server/tests/window.rs:1 full_window"),
            "#[test] tagged with another case only": (
                [("server/tests/window.rs", None, "// Proves: TC-022-004\n#[test]\nfn full_window() {}\n"),
                 bound("TC-022-004", BOTH, BOTH + "; server/tests/window.rs::full_window"), bound("TC-022-005", WEAK, window)],
                "Bound test lacks the Proves tag of its case: TC-022-005: server/tests/window.rs:2 full_window"),
            "#[tokio::test(...)] without a tag": (
                [("server/tests/window.rs", None, '#[tokio::test(flavor = "current_thread")]\nasync fn full_window() {}\n'),
                 bound("TC-022-005", WEAK, window)],
                "Bound test lacks the Proves tag of its case: TC-022-005: server/tests/window.rs:1 full_window"),
            "JavaScript test without the case": (
                [("tests/decode.test.cjs", None, "test('a full window', () => {});\n"),
                 bound("TC-022-005", WEAK, WEAK + "; tests/decode.test.cjs::a full window")],
                "Bound test lacks the Proves tag of its case: TC-022-005: tests/decode.test.cjs:1 a full window"),
        }
        for label, (changes, line) in faults.items():
            with self.subTest(label):
                self.assertEqual(self.fault_lines(changes), [line])

    def test_test_neither_tagged_nor_a_detail_test_is_refused(self):
        """TV-161 (TR-14): a test no case binds, without a tag and outside the `@DetailTests` files,
        is refused with exactly its one line: an untagged `#[test]`, an untagged JavaScript
        `test(`, an untagged `#[test]` in a `#[cfg(test)]` module of a product source file, and
        an untagged test beside a tagged test that a case binds by name."""
        faults = {
            "untagged #[test]": (
                [("server/tests/window.rs", None, "#[test]\nfn full_window() {}\n")],
                "Test neither tagged nor a detail test: server/tests/window.rs:1 full_window"),
            "untagged JavaScript test": (
                [("tests/decode.test.cjs", None, "test('a full window', () => {});\n")],
                "Test neither tagged nor a detail test: tests/decode.test.cjs:1 a full window"),
            "#[cfg(test)] module of a product file": (
                [("server/src/decode.rs", None,
                  "pub fn decode() {}\n\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn decodes() {}\n}\n")],
                "Test neither tagged nor a detail test: server/src/decode.rs:5 decodes"),
            "beside a tagged bound test": (
                [("server/tests/decode.rs", "fn weak_signals() {}\n", "fn weak_signals() {}\n\n#[test]\nfn untagged() {}\n")],
                "Test neither tagged nor a detail test: server/tests/decode.rs:9 untagged"),
        }
        for label, (changes, line) in faults.items():
            with self.subTest(label):
                self.assertEqual(self.fault_lines(changes), [line])

    def test_file_binding_is_refused(self):
        """TV-162 (TR-14): a `@TestedBy` that names a whole file is refused with its line: a case
        binding one file, a case binding a file and a test name in one value, a manual case binding
        a file, a bound file whose tests name no case, and a bound file whose tag stands on no
        test (with that tag's TR-14 line)."""
        faults = {
            "one file": (
                [bound("TC-022-005", WEAK, "server/tests/decode.rs")],
                ["TestedBy binds a whole file: TC-022-005: server/tests/decode.rs"]),
            "a file and a test name": (
                [("server/tests/window.rs", None, "// Proves: TC-022-005\n#[test]\nfn full_window() {}\n"),
                 bound("TC-022-005", WEAK, "server/tests/window.rs; " + WEAK)],
                ["TestedBy binds a whole file: TC-022-005: server/tests/window.rs"]),
            "manual case": (
                [bound("TC-022-005", WEAK, "server/tests/plain.rs; " + WEAK, ' method = "manual";')],
                ["TestedBy binds a whole file: TC-022-005: server/tests/plain.rs"]),
            "bound file naming no case": (
                [bound("TC-022-005", WEAK, WEAK + "; server/tests/plain.rs")],
                ["TestedBy binds a whole file: TC-022-005: server/tests/plain.rs"]),
            "tag on no test": (
                [("server/tests/helper.rs", None, "// Proves: TC-022-005\nfn helper() {}\n"),
                 bound("TC-022-005", WEAK, WEAK + "; server/tests/helper.rs")],
                ["Invalid Proves tag: server/tests/helper.rs:1",
                 "TestedBy binds a whole file: TC-022-005: server/tests/helper.rs"]),
        }
        for label, (changes, lines) in faults.items():
            with self.subTest(label):
                self.assertEqual(self.fault_lines(changes), lines)


if __name__ == "__main__":
    unittest.main()
