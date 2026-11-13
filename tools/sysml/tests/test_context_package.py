"""CL-014-10 (#183 C1): the required packages are WstxRequirements and WstxArchitecture, and
WstxContext whenever the model file Context.sysml exists; no ProductScope reference is asked.

Isolated fixtures in a temporary folder and one fixture run through the real pinned Pilot;
the real model is test_real_model_catalog.py's.
"""
import importlib.util
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("context_package_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CACHE = Path.home() / ".cache/wsjtx-rust/sysml-tools"
REQUIRED = {"FR-001", "CL-003-01", "TC-001-001"}
MARKER = "// Canonical authority: SysML\n"
# The content the skeleton merges into Requirements.sysml: the catalog beside a scope part.
ENTRY = MARKER + '''package WstxRequirements {
    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }
    part def ProductScope;
    requirement 'FR-001' {
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    requirement 'CL-003-01' {
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    verification 'TC-001-001' {
        attribute automation : AutomationState = AutomationState::planned;
        objective { verify 'FR-001'; verify 'CL-003-01'; }
    }
    dependency owns from 'CL-003-01' to 'FR-001';
    dependency checks from 'CL-003-01' to 'TC-001-001';
}
'''
ARCHITECTURE = "package WstxArchitecture {\n    part def Station;\n}\n"
CONTEXT = "package WstxContext {\n    private import WstxArchitecture::*;\n    part context : Station;\n}\n"


class RequiredPackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in tool.SOURCE_BINDING_ROOTS:
            (self.root / name).mkdir()
        self.models = self.root / "docs/sysml"
        self.write("Requirements.sysml", ENTRY)
        self.write("Station.sysml", ARCHITECTURE)

    def write(self, key, text):
        path = self.models / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def remove(self, key):
        (self.models / key).unlink()

    def check(self):
        return set(tool.canonical_catalog(self.models, self.root, required=REQUIRED))

    def refused(self, message):
        return self.assertRaisesRegex(ValueError, message)

    # C1, accepted: no WstxProductScope, an additional package referred to nowhere, two packages
    # Proves: CL-014-10; TC-DOC-007; TC-DOC-008
    def test_two_packages_are_required_without_context_and_no_scope_reference(self):
        with self.subTest("without WstxProductScope, its content in Requirements.sysml"):
            self.assertEqual(sorted(path.name for path in self.models.rglob("*.sysml")), ["Requirements.sysml", "Station.sysml"])
            self.assertEqual(self.check(), REQUIRED)
        with self.subTest("an additional package referred to nowhere"):
            self.write("backend/Extra.sysml", "package WstxExtra { part def Spare; }\n")
            self.assertEqual(self.check(), REQUIRED)
        with self.subTest("WstxProductScope present"):
            self.write("ProductScope.sysml", "package WstxProductScope { private import WstxExtra::*; }\n")
            self.assertEqual(self.check(), REQUIRED)
        for key, package in (("Station.sysml", "WstxArchitecture"), ("Requirements.sysml", "WstxRequirements")):
            text = (self.models / key).read_text(encoding="utf-8")
            with self.subTest(missing=package), self.refused("Canonical model packages missing: " + package + "$"):
                self.write(key, text.replace("package " + package + " {", "package Other {"))
                self.check()
            self.write(key, text)
            with self.subTest(twice=package), self.refused(
                    "Duplicate canonical model package: " + package + ": " + re.escape(key) + r", more/Again\.sysml$"):
                self.write("more/Again.sysml", "package " + package + " {}\n")
                self.check()
            self.remove("more/Again.sysml")
        with self.subTest("the removed constants"):
            self.assertEqual(tool.REQUIRED_PACKAGES, {"WstxRequirements", "WstxArchitecture"})
            self.assertFalse(any(hasattr(tool, name) for name in ("SCOPE_PACKAGE", "LIBRARY_PACKAGES", "scope_reference")))

    # C1: Context.sysml present makes WstxContext a third required package
    # Proves: CL-014-10; TC-DOC-007; TC-DOC-008
    def test_context_file_holds_the_context_package_named_by_no_other_file(self):
        self.write("Context.sysml", CONTEXT)
        with self.subTest("Context.sysml with WstxContext"):
            self.assertEqual(self.check(), REQUIRED)
        refused = {
            "Context.sysml with another package": ("Context.sysml", CONTEXT.replace("WstxContext", "WstxTop"),
                                                   r"Context file package is not WstxContext: Context\.sysml$"),
            "Context.sysml without a package": ("Context.sysml", "part def Loose;\n",
                                                r"Context file package is not WstxContext: Context\.sysml$"),
            "Context.sysml declaring an FR": ("Context.sysml", CONTEXT.replace("    part context", "    requirement 'FR-002' {}\n    part context"),
                                              r"Context file declares an identity: FR-002: Context\.sysml$"),
            "a file importing WstxContext": ("backend/Uses.sysml", "package WstxUses { private import WstxContext::*; }\n",
                                             r"Model file names the context package: WstxContext: backend/Uses\.sysml$"),
            "a file naming it in a qualified name": ("Uses.sysml", "package WstxUses { part p : WstxContext::Thing; }\n",
                                                     r"Model file names the context package: WstxContext: Uses\.sysml$"),
            "a second file declaring WstxContext": ("top/Context.sysml", "package WstxContext {}\n",
                                                    r"Model file names the context package: WstxContext: top/Context\.sysml$"),
        }
        for label, (key, text, message) in refused.items():
            with self.subTest(label), self.refused(message):
                self.write(key, text)
                self.check()
            if key == "Context.sysml":
                self.write(key, CONTEXT)
            else:
                self.remove(key)
        with self.subTest("named only in a comment or a string"):
            self.write("Uses.sysml", 'package WstxUses {\n    // WstxContext\n    doc /* WstxContext */\n'
                                     '    attribute a : ScalarValues::String = "WstxContext";\n}\n')
            self.assertEqual(self.check(), REQUIRED)
        self.remove("Context.sysml")
        with self.subTest("without Context.sysml, the name in another file"), self.refused(
                r"Model file names the context package: WstxContext: top/Context\.sysml$"):
            self.write("top/Context.sysml", "package WstxContext {}\n")
            self.check()


class ContextOnThePilotTests(unittest.TestCase):
    # C1: with Context.sysml the Pilot resolves the model; with it removed while another file
    # still names WstxContext, the Pilot refuses, so a lost context file does not go unnoticed.
    # Proves: CL-014-10; TC-DOC-008
    def test_real_pilot_refuses_a_name_of_the_removed_context_package(self):
        with tempfile.TemporaryDirectory() as directory:
            models = Path(directory) / "docs/sysml"
            models.mkdir(parents=True)
            texts = {"Requirements.sysml": ENTRY, "Station.sysml": ARCHITECTURE, "Context.sysml": CONTEXT,
                     "Uses.sysml": "package WstxUses {\n    private import WstxContext::*;\n}\n"}
            for key, text in texts.items():
                (models / key).write_text(text, encoding="utf-8")
            passed = "OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed."
            result = tool.validate([models / key for key in texts], CACHE)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(passed, result.stdout)
            (models / "Context.sysml").unlink()
            result = tool.validate([models / key for key in texts if key != "Context.sysml"], CACHE)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn(passed, result.stdout)


if __name__ == "__main__":
    unittest.main()
