"""TC-DOC-007: actual registry source selection and evidence invalidation."""
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
tool_spec = importlib.util.spec_from_file_location("trace_sysml", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(tool_spec)
tool_spec.loader.exec_module(tool)
TOOLS = ROOT / "harness/core/tools"
sys.path.insert(0, str(TOOLS))
try:
    spec = importlib.util.spec_from_file_location("trace_registry", TOOLS / "registry.py")
    registry = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(registry)
finally:
    sys.path.remove(str(TOOLS))


class TraceSelectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = registry.parse((ROOT / ".harness/suites.yaml").read_text(encoding="utf-8"))

    def test_code_changes_select_fast_trace_check_without_full_model_suite(self):
        for source in ("client/app.js", "server/src/profile.rs", "tests/profiles.test.cjs"):
            with self.subTest(source=source):
                selected = registry.selection(self.rows, [source])
                self.assertIn("source-model-traces", selected)
                self.assertNotIn("sysml-documentation", selected)
        for source in ("docs/sysml/Profiles.sysml", "tools/sysml.py", "tools/sysml/tests/test_canonical_authority.py"):
            with self.subTest(source=source):
                selected = registry.selection(self.rows, [source])
                self.assertIn("source-model-traces", selected)
                self.assertIn("sysml-documentation", selected)

    def test_source_change_or_deletion_invalidates_both_evidence_fingerprints(self):
        for source in ("client/app.js", "server/src/profile.rs", "tests/profiles.test.cjs"):
            self.assertFalse(registry.global_input(source, self.rows), "Regression needs a source owned by its runtime suite, not global fallback")
            before = [(source, "100644", "independent-source-before")]
            changed = [(source, "100644", "independent-source-after")]
            for name in ("sysml-documentation", "source-model-traces"):
                with self.subTest(source=source, suite=name):
                    row = self.rows[name]
                    original = registry.fingerprint(row, before, self.rows)
                    self.assertNotEqual(original, registry.fingerprint(row, changed, self.rows))
                    self.assertNotEqual(original, registry.fingerprint(row, [], self.rows))

    def test_every_admitted_source_root_is_fingerprinted_and_selects_fast_traces(self):
        for root in tool.SOURCE_BINDING_ROOTS:
            prefix = root + "/"
            for name in ("source-model-traces", "sysml-documentation"):
                with self.subTest(root=root, suite=name):
                    self.assertIn(prefix, self.rows[name]["paths"])
            self.assertIn(prefix, self.rows["source-model-traces"]["select"])
            self.assertNotIn(prefix, self.rows["sysml-documentation"]["select"])


if __name__ == "__main__":
    unittest.main()
