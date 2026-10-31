"""TC-DOC-003..004: level 2, local fixtures plus the real pinned OMG validator."""
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


class ValidatorTests(unittest.TestCase):
    def test_actual_pilot_rejects_files_that_stitch_invalid_syntax(self):
        cache = Path.home() / ".cache/wsjtx-rust/sysml-tools"
        with tempfile.TemporaryDirectory() as directory:
            first, second = (Path(directory) / name for name in ("A.sysml", "B.sysml"))
            for opening, closing in (("package A { /*\n", "*/ }\n"), ("package A {\n", "}\n")):
                first.write_text(opening, encoding="utf-8")
                second.write_text(closing, encoding="utf-8")
                for models in ([first, second], [second, first]):
                    with self.subTest(opening=opening, order=[model.name for model in models]):
                        result = tool.validate(models, cache)
                        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                        self.assertIn(f"{first}:", result.stdout)
                        self.assertIn(f"{second}:", result.stdout)
                        self.assertNotIn("validation passed", result.stdout)

    # Harness #15: file order cannot hide a valid reference or its real diagnostic.
    def test_actual_pilot_resolves_complete_graph_and_keeps_file_diagnostics(self):
        cache = Path.home() / ".cache/wsjtx-rust/sysml-tools"
        with tempfile.TemporaryDirectory() as directory:
            consumer = Path(directory) / "AConsumer.sysml"
            provider = Path(directory) / "ZProvider.sysml"
            consumer.write_bytes(b"\xef\xbb\xbfpackage Consumer {\r\n    item def Derived :> Provider::Base;\r\n}\r\n")
            provider.write_text("package Provider {\n    item def Base;\n}", encoding="utf-8")
            for models in ([consumer, provider], [provider, consumer]):
                with self.subTest(order=[model.name for model in models]):
                    result = tool.validate(models, cache)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            consumer.write_text("package Consumer {\n    item def Derived :> Provider::Missing;\n}\n", encoding="utf-8")
            result = tool.validate([provider, consumer], cache)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn(f"{consumer}:2: ERROR", result.stdout)
            self.assertIn("Couldn't resolve reference", result.stdout)
            self.assertNotIn("validation passed", result.stdout)

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
