"""TR-01: canonical SysML is the one functional authority; an active FSD is refused.

Isolated fixtures in a temporary folder; every message is written by hand from the rule.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("canonical_authority_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

MARKER = "// Canonical authority: SysML\n"
REQUIREMENTS = MARKER + "package WstxRequirements {\n    requirement 'FR-006' {\n        doc /* Time */\n    }\n}\n"
FILES = {
    "Requirements.sysml": REQUIREMENTS,
    "Shack.sysml": "package WstxShack {\n}\n",
    "Context.sysml": "package WstxContext {\n}\n",
}


class AuthorityTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.models = self.root / "docs/sysml"
        self.models.mkdir(parents=True)
        for name in tool.SOURCE_BINDING_ROOTS:
            (self.root / name).mkdir()
        for key, text in FILES.items():
            (self.models / key).write_text(text, encoding="utf-8")
        self.fsd = self.root / "docs/WSTX Rust FSD.md"

    def test_marker_and_no_fsd_make_sysml_the_authority(self):
        """TR-01: the marker on the first line of Requirements.sysml and no FSD make SysML the authority."""
        self.assertEqual(tool.authority(self.models, self.fsd), "sysml")
        self.assertEqual(set(tool.canonical_catalog(self.models, self.root)), {"FR-006"})

    def test_each_fault_of_the_authority_is_refused(self):
        """TR-01: no marker, two markers, and an FSD with or without the marker are each refused."""
        faults = {
            "no marker": (REQUIREMENTS.replace(MARKER, ""), False,
                          "No declared functional authority: canonical SysML marker required"),
            "two markers": (REQUIREMENTS + MARKER, False, "Invalid or duplicate canonical-authority declaration"),
            "FSD with the marker": (REQUIREMENTS, True, "Two functional authorities: canonical SysML and active FSD"),
            "FSD without the marker": (REQUIREMENTS.replace(MARKER, ""), True,
                                       "Retired Markdown FSD is not a functional authority: archive it and "
                                       "declare canonical SysML"),
        }
        for label, (text, fsd, message) in faults.items():
            with self.subTest(label):
                (self.models / "Requirements.sysml").write_text(text, encoding="utf-8")
                if fsd:
                    self.fsd.write_text("# WSTX Rust FSD\n", encoding="utf-8")
                with self.assertRaises(ValueError) as refused:
                    tool.authority(self.models, self.fsd)
                self.assertEqual(str(refused.exception), message)
                self.fsd.unlink(missing_ok=True)

    def test_model_file_naming_the_fsd_is_refused(self):
        """TR-01: a model file that names the FSD as a source is refused with its key."""
        (self.models / "Shack.sysml").write_text(
            "package WstxShack {\n    doc /* See WSTX Rust FSD chapter 4. */\n}\n", encoding="utf-8")
        with self.assertRaises(ValueError) as refused:
            tool.canonical_catalog(self.models, self.root)
        self.assertEqual(str(refused.exception), "Canonical model retains a retired FSD dependency: Shack.sysml")


if __name__ == "__main__":
    unittest.main()
