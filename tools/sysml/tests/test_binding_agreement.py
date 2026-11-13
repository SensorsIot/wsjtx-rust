"""TC-DOC-011: every test that names a verification case is in that case's binding.

Isolated fixtures in a temporary folder: `traces` on a small model and hand-written sources,
and one throwaway git repository for the gate's model bindings. The expected messages are
the contract text of CL-014-13, written out by hand.
"""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("binding_agreement_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

REQUIRED = {"FR-001", "CL-003-01", "TC-001-001"}
REQUIRED_FILES = {"Requirements.sysml": "WstxRequirements", "Architecture.sysml": "WstxArchitecture"}
REFUSED = "Proves tag outside the verification binding: "


def body(state="partial", binding=None, method=None, form="attribute"):
    """The statements of one case: its state, its method and its binding, in either form."""
    lines = [f"        attribute automation : AutomationState = AutomationState::{state};\n"]
    if method:
        lines.append(f'        attribute method : String = "{method}";\n')
    if binding is not None:
        lines.append(f'        attribute executable : String = "{binding}";\n' if form == "attribute"
                     else f'        @TestedBy {{ test = "{binding}"; }}\n')
    return "".join(lines)


def model(first, second=None):
    """TC-001-001 with the statements `first`, TC-001-002 with `second` (planned, unbound)."""
    return ("// Canonical authority: SysML\npackage WstxRequirements {\n"
            "    enum def ImplementationState { enum target; enum partial; enum implemented; }\n"
            "    enum def AutomationState { enum planned; enum partial; enum implemented; }\n"
            "    requirement 'FR-001' {\n"
            "        attribute coverage : ImplementationState = ImplementationState::target;\n    }\n"
            "    requirement 'CL-003-01' {\n"
            "        attribute coverage : ImplementationState = ImplementationState::target;\n    }\n"
            "    verification 'TC-001-001' {\n" + first
            + "        objective { verify 'FR-001'; verify 'CL-003-01'; }\n    }\n"
            "    verification 'TC-001-002' {\n" + (second if second is not None else body("planned"))
            + "        objective { verify 'CL-003-01'; }\n    }\n"
            "    dependency owns from 'CL-003-01' to 'FR-001';\n"
            "    dependency checks from 'CL-003-01' to 'TC-001-001';\n"
            "    dependency checksToo from 'CL-003-01' to 'TC-001-002';\n}\n")


def rust(tag, name, *attributes):
    return f"// Proves: {tag}\n#[test]\n" + "".join(a + "\n" for a in attributes) + f"fn {name}() {{}}\n"


class BindingAgreementTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in tool.SOURCE_BINDING_ROOTS:
            (self.root / name).mkdir()
        self.models = self.root / "docs/sysml"
        self.models.mkdir(parents=True)
        for name, package in REQUIRED_FILES.items():
            (self.models / name).write_text("package " + package + " {}", encoding="utf-8")

    def source(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def traces(self, first, second=None):
        """(exit code, error output) of `traces` on the fixture."""
        (self.models / "Requirements.sysml").write_text(model(first, second), encoding="utf-8")
        real_catalog = tool.canonical_catalog
        with mock.patch.object(tool, "ROOT", self.root), mock.patch.object(tool, "MODELS", self.models), \
                mock.patch.object(tool, "FSD", self.root / "docs/FSD.md"), \
                mock.patch.object(tool, "canonical_catalog", side_effect=lambda d, r: real_catalog(d, r, required=REQUIRED)), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()) as errors:
            code = tool.main(["traces"])
        return code, errors.getvalue().strip()

    def assertRefused(self, result, *pairs):
        self.assertEqual(result, (2, "SysML check failed: " + REFUSED + "; ".join(pairs)))

    def assertAccepted(self, result):
        self.assertEqual(result, (0, ""))

    # T1
    # Proves: CL-014-13; TC-DOC-011
    def test_a_tagged_test_in_a_file_the_case_does_not_bind_is_refused(self):
        self.source("server/a.rs", rust("TC-001-001", "in_a"))
        b = self.source("server/b.rs", rust("CL-003-01; TC-001-001", "in_b"))
        for form in ("attribute", "metadata"):
            with self.subTest(form=form):
                self.assertRefused(self.traces(body(binding="server/a.rs", form=form)), "TC-001-001: server/b.rs::in_b")
                self.assertAccepted(self.traces(body(binding="server/a.rs; server/b.rs", form=form)))
        b.write_text(rust("CL-003-01", "in_b"), encoding="utf-8")
        self.assertAccepted(self.traces(body(binding="server/a.rs")))

    # T2
    # Proves: CL-014-13; TC-DOC-011
    def test_another_symbol_of_a_file_bound_by_symbols_is_refused_by_name(self):
        self.source("server/a.rs", rust("TC-001-001", "one") + rust("TC-001-001", "two"))
        self.assertRefused(self.traces(body(binding="server/a.rs::one")), "TC-001-001: server/a.rs::two")
        self.assertAccepted(self.traces(body(binding="server/a.rs::one; server/a.rs::two")))
        self.assertAccepted(self.traces(body(binding="server/a.rs")))

    # T3, the refusals
    # Proves: CL-014-13; TC-DOC-011
    def test_every_way_of_naming_a_case_and_every_kind_of_case_is_judged(self):
        bound = body(binding="server/c.rs")
        cases = {
            # Shorthand names both cases; the tag is refused only for the case that does not bind.
            "shorthand": ({"server/c.rs": rust("TC-001-001/002", "shared")}, bound, None,
                          ["TC-001-002: server/c.rs::shared"]),
            "two cases": ({"server/c.rs": rust("CL-003-01; TC-001-001, TC-001-002", "shared")}, bound, None,
                          ["TC-001-002: server/c.rs::shared"]),
            "test name": ({"server/c.rs": rust("TC-001-001", "c"),
                           "tests/d.cjs": "test('TC-001-002 named by its name',()=>{});\n"}, bound, None,
                          ["TC-001-002: tests/d.cjs::TC-001-002 named by its name"]),
            "tag and name": ({"server/c.rs": rust("TC-001-001", "c"),
                              "tests/d.cjs": "// Proves: TC-001-002\ntest('tagged',()=>{});\n"}, bound, None,
                             ["TC-001-002: tests/d.cjs::tagged"]),
            "ignored": ({"server/c.rs": rust("TC-001-001", "c"),
                         "server/e.rs": rust("TC-001-002", "operator_run", '#[ignore = "hardware"]')}, bound, None,
                        ["TC-001-002: server/e.rs::operator_run"]),
            "left out": ({"server/c.rs": rust("TC-001-001", "c"),
                          "server/e.rs": rust("TC-001-002", "release_only", "#[cfg(not(debug_assertions))]")},
                         bound, None, ["TC-001-002: server/e.rs::release_only"]),
            "async": ({"server/c.rs": rust("TC-001-001", "c"),
                       "server/e.rs": "// Proves: TC-001-002\n#[tokio::test]\nasync fn awaited() {}\n"}, bound, None,
                      ["TC-001-002: server/e.rs::awaited"]),
            "manual": ({"server/c.rs": rust("TC-001-001", "c"), "server/m.rs": "#[test]\nfn by_hand() {}\n",
                        "client/e.js": "// Proves: TC-001-002\ntest('in the client',()=>{});\n"}, bound,
                       body("implemented", "server/m.rs", "manual"), ["TC-001-002: client/e.js::in the client"]),
            "planned, unbound": ({"server/c.rs": rust("TC-001-001", "c"), "server/e.rs": rust("TC-001-002", "early")},
                                 bound, body("planned"), ["TC-001-002: server/e.rs::early"]),
            "sorted": ({"server/c.rs": rust("TC-001-001", "c"), "server/z.rs": rust("TC-001-001", "zeta") + rust("TC-001-001", "alpha"),
                        "server/b.rs": rust("TC-001-002", "beta")}, bound, None,
                       ["TC-001-001: server/z.rs::alpha", "TC-001-001: server/z.rs::zeta", "TC-001-002: server/b.rs::beta"]),
        }
        for label, (sources, first, second, pairs) in cases.items():
            with self.subTest(label):
                written = [self.source(name, text) for name, text in sources.items()]
                self.assertRefused(self.traces(first, second), *pairs)
                for path in written:
                    path.unlink()

    # T3, the guards: what names no test is not judged, as before.
    # Proves: CL-014-13; TC-DOC-011
    def test_a_tag_that_names_no_test_and_a_file_outside_the_source_roots_are_not_judged(self):
        self.source("server/c.rs", "// Proves: TC-001-002\n\nuse std::fmt;\n" + rust("TC-001-001", "c")
                    + "// Proves: TC-001-002\nfn helper() {}\n")
        self.source("tools/e.rs", rust("TC-001-002", "outside"))
        self.source("tests/e_test.py", "# Proves: TC-001-002\ndef test_outside():\n    pass\n")
        self.assertAccepted(self.traces(body(binding="server/c.rs")))

    # T4
    # Proves: CL-014-13; TC-DOC-011
    def test_a_manual_case_binding_a_missing_symbol_is_refused(self):
        self.source("server/m.rs", '#[test]\n#[ignore = "operator run"]\nfn present() {}\n')
        code, errors = self.traces(body("partial", "server/m.rs::missing", "manual"))
        self.assertEqual((code, errors), (2, "SysML check failed: Missing executable test symbol: TC-001-001: server/m.rs::missing"))
        self.assertAccepted(self.traces(body("partial", "server/m.rs::present", "manual")))
        # A guard of existing behaviour: an untagged file binding of a manual case.
        self.assertAccepted(self.traces(body("partial", "server/m.rs", "manual")))

    # T5, a guard: the gate's bindings report a revision, they do not judge it.
    # Proves: CL-014-13; TC-DOC-011
    def test_gate_model_bindings_report_a_revision_with_a_tag_outside_a_binding(self):
        spec = importlib.util.spec_from_file_location("binding_agreement_model_bindings", ROOT / ".harness/model_bindings.py")
        bindings = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bindings)

        def git(*args):
            subprocess.run(["git", "-C", str(self.root), "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
                            "-c", "core.autocrlf=false", "-c", "commit.gpgsign=false", *args], check=True, capture_output=True)

        self.source("server/a.rs", rust("TC-001-001", "one"))
        self.source("server/b.rs", rust("TC-001-001", "outside"))
        self.source("server/m.rs", '#[test]\n#[ignore]\nfn first() {}\n#[test]\n#[ignore]\nfn second() {}\n')
        (self.models / "Requirements.sysml").write_text(
            model(body(binding="server/a.rs"), body("implemented", "server/m.rs::first; server/m.rs::second", "manual")),
            encoding="utf-8")
        git("init", "-q")
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m", "a tag outside its binding")
        # Written by hand from the fixture.
        cases = {
            "TC-001-001": {"automated": True, "verifies": ["FR-001", "CL-003-01"], "paths": ["server/a.rs"],
                           "tests": [{"path": "server/a.rs", "name": "one"}], "unresolved": []},
            "TC-001-002": {"automated": False, "verifies": ["CL-003-01"], "paths": ["server/m.rs", "server/m.rs"],
                           "tests": [{"path": "server/m.rs", "name": "first"}, {"path": "server/m.rs", "name": "second"}],
                           "unresolved": []},
        }
        real_catalog = bindings.sysml.canonical_catalog
        with mock.patch.object(bindings, "ROOT", self.root), \
                mock.patch.object(bindings.sysml, "canonical_catalog", side_effect=lambda d, r: real_catalog(d, r, required=REQUIRED)):
            self.assertEqual(bindings.bindings("HEAD")["cases"], cases)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(bindings.main(["--rev", "HEAD"]), 0)


if __name__ == "__main__":
    unittest.main()
