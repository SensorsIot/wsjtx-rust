"""TR-02: the suites of the registry harness/project/suites/ select and fingerprint the model checks."""
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
TOOLS = ROOT / "harness/general/core/tools"
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
        cls.rows = registry.load(ROOT)

    def test_code_changes_select_fast_trace_check_without_full_model_suite(self):
        """TV-126 (TR-02): a code change selects traces, not the full model suite."""
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
    def test_model_file_in_a_subfolder_selects_the_model_suites(self):
        """TV-127 (TR-02): a model file in a subfolder selects the model suites."""
        selected = registry.selection(self.rows, ["docs/sysml/backend/qso/X.sysml"])
        self.assertIn("sysml-documentation", selected)
        self.assertIn("source-model-traces", selected)

    def test_source_change_or_deletion_invalidates_both_evidence_fingerprints(self):
        """TV-128 (TR-02): a source change or deletion invalidates both evidence fingerprints."""
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
        """TV-129 (TR-02): every source root is fingerprinted and selects traces."""
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

    # T1: model edits run the working-model checks, not the Pilot validator tests.
    def test_model_and_model_data_changes_select_the_working_model_suite_not_the_validator(self):
        """TV-130 (TR-02): the inputs of the working-model suite select it, not the validator tests; another model file, an internal interface among them, and the oracle file select neither."""
        for path in ("docs/sysml/Context.sysml", "docs/sysml/interfaces/external/Udp.sysml"):
            with self.subTest(path=path):
                self.assert_selection(path, (CONTEXT, "sysml-documentation"), (VALIDATOR,))
        for path in ("docs/sysml/Shack.sysml", "docs/sysml/backend/qso/X.sysml",
                     "docs/sysml/interfaces/internal/StationLink.sysml", "tools/sysml/architecture-oracle.json"):
            with self.subTest(path=path):
                self.assert_selection(path, ("sysml-documentation",), (CONTEXT, VALIDATOR))

    # T2: the tool selects both architecture suites; the validator, its library pin
    # and its test files the validator suite; the working-model module its own suite.
    def test_tool_changes_select_the_architecture_suites_they_feed(self):
        """TV-131 (TR-02): a tool change selects the architecture suites it feeds."""
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

    # T3, a guard of existing behaviour: the suite definitions select both suites.
    def test_suite_definitions_select_both_architecture_suites(self):
        """TV-132 (TR-02): the suite definitions select both architecture suites."""
        architecture = [name for name in self.rows if name.startswith(VALIDATOR)]
        self.assertIn(VALIDATOR, architecture)
        self.assert_selection("harness/project/suites/sysml-architecture.yaml", architecture, ())

    # T4: source edits select neither architecture suite; they invalidate the
    # validator suite's evidence (its pinned checks read them), not the working-model suite's.
    def test_source_change_selects_neither_architecture_suite_and_invalidates_only_the_validator(self):
        """TV-133 (TR-02): a source edit selects neither architecture suite and invalidates only the validator's evidence."""
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

    # T5, a guard of existing behaviour: every test file runs in exactly one suite.
    def test_every_sysml_test_file_runs_in_exactly_one_suite(self):
        """TV-134 (TR-02): every tool test file runs in exactly one suite."""
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
