"""TC-DOC-007: actual registry source selection and evidence invalidation."""
import fnmatch
import importlib.util
from pathlib import Path
import re
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

TESTS = ROOT / "tools/sysml/tests"
CONTEXT = "sysml-architecture-context"
VALIDATOR = "sysml-architecture"
WORKING_MODEL_MODULE = "test_architecture_context.py"
SOURCES = ("client/app.js", "server/src/profile.rs", "tests/profiles.test.cjs")
DISCOVER = re.compile(r'discover -s tools/sysml/tests -p "?([^"\s]+)"?')


def discover_patterns(rows):
    """{suite: [-p pattern, ...]} of every `discover -s tools/sysml/tests` in a run."""
    return {name: found for name, row in rows.items() if (found := DISCOVER.findall(row["run"]))}


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

    # A guard of existing behaviour.
    # Proves: CL-014-10; TC-DOC-008
    def test_model_file_in_a_subfolder_selects_the_model_suites(self):
        selected = registry.selection(self.rows, ["docs/sysml/backend/qso/X.sysml"])
        self.assertIn("sysml-documentation", selected)
        self.assertIn("source-model-traces", selected)

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

    def assert_selection(self, path, selected, not_selected):
        chosen = registry.selection(self.rows, [path])
        for name in selected:
            self.assertIn(name, chosen, f"{path} must select {name}")
        for name in not_selected:
            self.assertNotIn(name, chosen, f"{path} must not select {name}")

    # T1 (#202): model edits run the working-model checks, not the Pilot validator tests.
    # Proves: TC-DOC-007
    def test_model_and_model_data_changes_select_the_working_model_suite_not_the_validator(self):
        for path in ("docs/sysml/Station.sysml", "docs/sysml/Context.sysml",
                     "docs/sysml/interfaces/internal/StationLink.sysml",
                     "tools/sysml/architecture-oracle.json", "tools/sysml/pending-structure.json"):
            with self.subTest(path=path):
                self.assert_selection(path, (CONTEXT, "sysml-documentation"), (VALIDATOR,))
        with self.subTest(path="docs/sysml/backend/qso/X.sysml"):
            self.assert_selection("docs/sysml/backend/qso/X.sysml", ("sysml-documentation",),
                                  (CONTEXT, VALIDATOR))

    # T2 (#202): the tool selects both architecture suites; the validator, its library pin
    # and its test files the validator suite; the working-model module its own suite.
    # Proves: TC-DOC-007
    def test_tool_changes_select_the_architecture_suites_they_feed(self):
        self.assert_selection("tools/sysml.py", (CONTEXT, VALIDATOR), ())
        pattern, = discover_patterns(self.rows)[VALIDATOR]
        validator_tests = sorted(p.name for p in TESTS.glob("test_*.py") if fnmatch.fnmatch(p.name, pattern))
        self.assertGreaterEqual(len(validator_tests), 3, validator_tests)
        for path in ("tools/sysml/Validate.java", "tools/sysml/toolchain.json",
                     *(f"tools/sysml/tests/{name}" for name in validator_tests),
                     "tools/sysml/tests/test_a_future.py"):
            with self.subTest(path=path):
                self.assert_selection(path, (VALIDATOR,), (CONTEXT,))
        with self.subTest(path=WORKING_MODEL_MODULE):
            self.assert_selection(f"tools/sysml/tests/{WORKING_MODEL_MODULE}", (CONTEXT,), (VALIDATOR,))
        with self.subTest(path="tools/sysml/tests/test_structure_rules.py"):
            self.assert_selection("tools/sysml/tests/test_structure_rules.py", (), (CONTEXT, VALIDATOR))

    # T3 (#202), a guard of existing behaviour: the suite definitions select both suites.
    # Proves: TC-DOC-007
    def test_suite_definitions_select_both_architecture_suites(self):
        self.assert_selection(".harness/suites.yaml", (CONTEXT, VALIDATOR), ())

    # T4 (#202): source edits select neither architecture suite; they invalidate the
    # validator suite's evidence (its pinned checks read them), not the working-model suite's.
    # Proves: TC-DOC-007
    def test_source_change_selects_neither_architecture_suite_and_invalidates_only_the_validator(self):
        for source in SOURCES:
            with self.subTest(source=source):
                self.assert_selection(source, (), (CONTEXT, VALIDATOR))
                before = [(source, "100644", "independent-source-before")]
                changed = [(source, "100644", "independent-source-after")]
                validator = self.rows[VALIDATOR]
                self.assertNotEqual(registry.fingerprint(validator, before, self.rows),
                                    registry.fingerprint(validator, changed, self.rows))
                context = self.rows[CONTEXT]
                self.assertEqual(registry.fingerprint(context, before, self.rows),
                                 registry.fingerprint(context, changed, self.rows))

    # T5 (#202), a guard of existing behaviour: every test file runs in exactly one suite.
    # Proves: TC-DOC-007
    def test_every_sysml_test_file_runs_in_exactly_one_suite(self):
        patterns = discover_patterns(self.rows)
        names = sorted(p.name for p in TESTS.glob("test_*.py"))
        self.assertIn(WORKING_MODEL_MODULE, names)
        for name in (*names, "test_a_future.py"):
            with self.subTest(name=name):
                runs = [suite for suite, found in patterns.items()
                        for pattern in found if fnmatch.fnmatch(name, pattern)]
                self.assertEqual(len(runs), 1, f"{name} runs in {runs}")
        self.assertEqual([suite for suite, found in patterns.items()
                          if any(fnmatch.fnmatch("test_a_future.py", p) for p in found)], [VALIDATOR])


if __name__ == "__main__":
    unittest.main()
