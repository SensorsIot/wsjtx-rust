"""TC-DOC-001..004: level 2, local fixtures plus the real pinned OMG validator."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("sysml_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

SOURCE = """| FR-001 | Setup | Retain the station identity. |
| CL-003-01 | FR-001 | Display its identity. | TC-001-001 |
#### TC-001-001 — Identity
**Promise:** FR-001.
Send a status query and expect its own identity.
"""


class ProjectionTests(unittest.TestCase):
    # Proves: CL-014-01, CL-014-02, CL-014-05; TC-DOC-001.
    def test_stable_definitions_and_references(self):
        entries = tool.catalog(SOURCE)
        self.assertEqual(set(entries), {"FR-001", "CL-003-01", "TC-001-001"})
        rendered = tool.render(SOURCE)
        self.assertIn("requirement 'FR-001'", rendered)
        self.assertIn("verification 'TC-001-001'", rendered)
        self.assertIn("verify 'FR-001';", rendered)
        self.assertIn("Retain the station identity.", rendered)
        self.assertEqual(rendered, tool.render(SOURCE))

    # The single FSD contains both definitions and linked architecture coverage rows.
    def test_architecture_coverage_references_do_not_redefine_requirements(self):
        merged = SOURCE + "\n## 11. Architecture\n| [FR-001](#4-proposed-functional-requirements) | Profile responsibility | Target coverage |\n"
        self.assertEqual(set(tool.catalog(merged)), {"FR-001", "CL-003-01", "TC-001-001"})

    # Proves: CL-014-04, CL-014-05; TC-DOC-002.
    def test_reject_duplicate_and_unknown_identity(self):
        with self.assertRaisesRegex(ValueError, "Duplicate definition"):
            tool.catalog(SOURCE + "\n| FR-001 | Other | Incorrect duplicate. |")
        with self.assertRaisesRegex(ValueError, "undefined FR-999"):
            tool.catalog(SOURCE.replace("**Promise:** FR-001", "**Promise:** FR-999"))
        with self.assertRaisesRegex(ValueError, "Malformed definition identity"):
            tool.catalog(SOURCE.replace("| FR-001 |", "| FR-1 |"))

    # Proves: CL-014-02; TC-DOC-001. Method documentation remains Markdown-only.
    def test_documentation_method_identities_are_not_product_model_elements(self):
        method = "\n### Documentation methods\n| CL-014-01 | Authority | Markdown remains authoritative. | TC-DOC-001 |\n| TC-DOC-001 | CL-014-01 | Generate | Current |\n"
        entries = tool.catalog(SOURCE + method)
        self.assertNotIn("CL-014-01", entries)
        self.assertNotIn("TC-DOC-001", entries)

    # Proves: CL-014-01, CL-014-04, CL-014-05; TC-DOC-001, TC-DOC-002.
    def test_sync_does_not_mutate_source_and_check_rejects_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fsd = root / "FSD.md"
            fsd.write_text(SOURCE, encoding="utf-8")
            with mock.patch.object(tool, "FSD", fsd), mock.patch.object(tool, "MODELS", root):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(tool.main(["sync"]), 0)
                self.assertEqual(fsd.read_text(encoding="utf-8"), SOURCE)
                generated = root / "Requirements.sysml"
                for action in ("source", "corrupt", "missing"):
                    generated.write_text(tool.render(SOURCE), encoding="utf-8")
                    fsd.write_text(SOURCE + ("\nChanged source." if action == "source" else ""), encoding="utf-8")
                    if action == "corrupt":
                        generated.write_text("package Wrong {}", encoding="utf-8")
                    elif action == "missing":
                        generated.unlink()
                    errors = io.StringIO()
                    with contextlib.redirect_stderr(errors):
                        self.assertEqual(tool.main(["check"]), 2)
                    self.assertIn("FSD projection is stale", errors.getvalue())

    # Proves: CL-014-03, CL-014-05; TC-DOC-002.
    def test_manual_architecture_source_drift_is_not_auto_accepted(self):
        original = "Independent audio and control."
        model = "// Canonical architecture SHA256: " + tool.digest(original)
        tool.check_architecture(model, original)
        with self.assertRaisesRegex(ValueError, "Architecture source changed"):
            tool.check_architecture(model, original + " Changed interface.")


class ValidatorTests(unittest.TestCase):
    # Proves: CL-014-04; TC-DOC-003. This invokes the real parser/resolver, not a mock.
    def test_actual_pilot_accepts_valid_and_rejects_syntax_and_reference(self):
        cache = Path.home() / ".cache/wsjtx-rust/sysml-tools"
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "case.sysml"
            vectors = (
                ("package Valid { part def Station; part station : Station; }", 0, "validation passed"),
                ("package Broken { part def Station {", 1, "ERROR"),
                ("package Broken { part station : MissingType; }", 1, "Couldn't resolve reference"),
            )
            for source, expected_status, diagnostic in vectors:
                with self.subTest(source=source):
                    model.write_text(source, encoding="utf-8")
                    result = tool.validate([model], cache)
                    self.assertEqual(result.returncode, expected_status, result.stdout + result.stderr)
                    self.assertIn(diagnostic, result.stdout)

    # Proves: CL-014-04; TC-DOC-004.
    def test_missing_tool_never_reports_semantic_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = root / "valid.sysml"
            model.write_text("package Valid {}", encoding="utf-8")
            errors, output = io.StringIO(), io.StringIO()
            with contextlib.redirect_stderr(errors), contextlib.redirect_stdout(output):
                self.assertEqual(tool.main(["--cache-dir", str(root), "validate", str(model)]), 2)
            self.assertIn("Semantic validator unavailable", errors.getvalue())
            self.assertNotIn("validation passed", output.getvalue())

    # Proves: CL-014-04; TC-DOC-004.
    def test_empty_or_corrupt_cached_library_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            packages = tool.json.loads(tool.TOOLCHAIN.read_text(encoding="utf-8"))
            java = cache / packages["jdk_windows_x64"]["directory"] / packages["jdk_windows_x64"]["executable"]
            java.parent.mkdir(parents=True)
            java.write_bytes(b"not a JDK")
            pilot = cache / "pilot-0.62.0/sysml"
            pilot.mkdir(parents=True)
            (pilot / "jupyter-sysml-kernel-0.62.0-all.jar").write_bytes(b"not the pinned validator")
            with mock.patch.dict(os.environ, {"WSTX_SYSML_JAVA": ""}):
                with self.assertRaisesRegex(FileNotFoundError, "Semantic validator unavailable"):
                    tool.tool_paths(cache)
                (pilot / "sysml.library").mkdir()
                with self.assertRaisesRegex(ValueError, "Pinned semantic validator or model-library contents differ"):
                    tool.tool_paths(cache)
                real_jar = tool.tool_paths(Path.home() / ".cache/wsjtx-rust/sysml-tools")[1]
                shutil.copyfile(real_jar, pilot / "jupyter-sysml-kernel-0.62.0-all.jar")
                with self.assertRaisesRegex(ValueError, "Pinned semantic validator or model-library contents differ"):
                    tool.tool_paths(cache)


if __name__ == "__main__":
    unittest.main()
