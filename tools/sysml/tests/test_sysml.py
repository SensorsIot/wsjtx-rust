"""TR-02: level 2, local fixtures plus the real pinned OMG validator."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import types
import unittest
from unittest import mock

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("sysml_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class ValidatorTests(unittest.TestCase):
    def test_actual_pilot_rejects_files_that_stitch_invalid_syntax(self):
        """TV-115 (TR-02): files that only stitch into valid syntax are refused, each named."""
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

    def test_actual_pilot_resolves_complete_graph_and_keeps_file_diagnostics(self):
        """TV-116 (TR-02): file order hides neither a valid reference nor its diagnostic."""
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

    # This invokes the real parser/resolver, not a mock.
    def test_actual_pilot_accepts_valid_and_rejects_syntax_and_reference(self):
        """TV-117 (TR-02): the Pilot accepts a valid model and refuses a syntax error and an unresolved name."""
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

    def test_missing_tool_never_reports_semantic_pass(self):
        """TV-118 (TR-02): a missing Java or JAR never reports a semantic pass."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = root / "valid.sysml"
            model.write_text("package Valid {}", encoding="utf-8")
            errors, output = io.StringIO(), io.StringIO()
            with contextlib.redirect_stderr(errors), contextlib.redirect_stdout(output):
                self.assertEqual(tool.main(["--cache-dir", str(root), "validate", str(model)]), 2)
            self.assertIn("Semantic validator unavailable", errors.getvalue())
            self.assertNotIn("validation passed", output.getvalue())

    def test_empty_or_corrupt_cached_library_is_refused(self):
        """TV-119 (TR-02): an empty or corrupt cached library is refused."""
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


MARKER = "OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed."
DURATION = re.compile(r"^validator: (\d+\.\d) s \(limit 600 s\)$")
STUB_TOOLS = (Path("stub-java"), Path("stub-validator.jar"), Path("stub-library"))


class Process:
    """A stand-in for the Pilot's Java process: records each start, waits `delay`
    seconds, then returns its result or, with `times_out`, raises the run's timeout."""

    def __init__(self, stdout="", returncode=0, stderr="", delay=0.0, times_out=False):
        self.stdout, self.returncode, self.stderr = stdout, returncode, stderr
        self.delay, self.times_out = delay, times_out
        self.calls = []

    def __call__(self, command, **options):
        self.calls.append((command, options))
        time.sleep(self.delay)
        if self.times_out:
            raise subprocess.TimeoutExpired(command, options.get("timeout"))
        return subprocess.CompletedProcess(command, self.returncode, self.stdout, self.stderr)


class ValidatorRunTests(unittest.TestCase):
    """TR-02: the limit of the Pilot run, its duration line and its timeout, with the Java
    process and the tool check stubbed."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.model = self.root / "valid.sysml"
        self.model.write_text("package Valid {}", encoding="utf-8")

    def run_main(self, process, argv):
        output, errors = io.StringIO(), io.StringIO()
        with mock.patch.object(tool, "tool_paths", return_value=STUB_TOOLS), \
                mock.patch.object(tool.subprocess, "run", process), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = tool.main(["--cache-dir", str(self.root), *argv])
        return status, output.getvalue(), errors.getvalue()

    # Timing: timer
    def test_limit_is_600_seconds(self):
        """TV-191 (TR-02): the Pilot run is started with a time limit of 600 s."""
        process = Process(stdout=MARKER + "\n")
        status, _output, _errors = self.run_main(process, ["validate", str(self.model)])
        self.assertEqual(status, 0)
        self.assertEqual(len(process.calls), 1)
        self.assertEqual(process.calls[0][1]["timeout"], 600)

    def test_command_line_and_pass_unchanged(self):
        """TV-192 (TR-02): the Pilot's command line is unchanged, and stdout and the exit
        code are the process's pass."""
        script = str(TOOL.with_name("sysml") / "Validate.java")
        base = ["stub-java", "-Xmx512m", "-XX:+UseSerialGC", "-XX:-UsePerfData", "-classpath", "stub-validator.jar",
                script, "stub-library"]
        process = Process(stdout="Reading " + str(self.model) + "\n" + MARKER + "\n")
        status, output, _errors = self.run_main(process, ["validate", str(self.model)])
        self.assertEqual(status, 0)
        self.assertEqual(output, MARKER + "\n")
        command, options = process.calls[0]
        self.assertEqual(command, base + [str(self.model)])
        self.assertEqual({key: value for key, value in options.items() if key != "timeout"},
                         {"text": True, "capture_output": True})
        with mock.patch.object(tool, "tool_paths", return_value=STUB_TOOLS), \
                mock.patch.object(tool.subprocess, "run", process), contextlib.redirect_stderr(io.StringIO()):
            tool.validate([self.model, self.model], self.root, inventory=True)
        self.assertEqual(process.calls[1][0], base + ["--inventory", str(self.model), str(self.model)])

    def test_duration_line_after_a_pass(self):
        """TV-193 (TR-02): after a pass, stderr holds exactly one duration line whose value
        is the run's duration; stdout holds none."""
        delay = 1.0
        status, output, errors = self.run_main(Process(stdout=MARKER + "\n", delay=delay), ["validate", str(self.model)])
        self.assertEqual(status, 0, errors)
        durations = [line for line in errors.splitlines() if line.startswith("validator:")]
        self.assertEqual(len(durations), 1, errors)
        match = DURATION.match(durations[0])
        self.assertIsNotNone(match, durations[0])
        self.assertLessEqual(abs(float(match[1]) - delay), 0.5)
        self.assertNotIn("validator:", output)

    def test_duration_line_after_a_validation_error(self):
        """TV-194 (TR-02): after a validation error the duration line is printed once, the
        error line on stdout, and the exit code is 1."""
        error = f"{self.model}:1: ERROR Couldn't resolve reference"
        status, output, errors = self.run_main(Process(stdout=error + "\n", returncode=1), ["validate", str(self.model)])
        self.assertEqual(status, 1)
        self.assertEqual(output, error + "\n")
        self.assertEqual(len([line for line in errors.splitlines() if DURATION.match(line)]), 1, errors)
        self.assertEqual(len([line for line in errors.splitlines() if line.startswith("validator:")]), 1, errors)

    def test_duration_line_without_the_completion_marker(self):
        """TV-195 (TR-02): a pass without the completion marker prints the duration line, then
        the missing marker, and exits 2."""
        status, _output, errors = self.run_main(Process(stdout="no marker\n"), ["validate", str(self.model)])
        self.assertEqual(status, 2)
        lines = errors.splitlines()
        self.assertEqual(len(lines), 2, errors)
        self.assertRegex(lines[0], DURATION)
        self.assertEqual(lines[1], "SysML check failed: Validator returned no semantic completion marker")

    def test_no_duration_line_when_the_validator_does_not_start(self):
        """TV-196 (TR-02): a missing tool and a missing model file print no duration line and
        exit 2 with their message."""
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stderr(errors), contextlib.redirect_stdout(output):
            status = tool.main(["--cache-dir", str(self.root), "validate", str(self.model)])
        self.assertEqual(status, 2)
        self.assertIn("Semantic validator unavailable", errors.getvalue())
        self.assertNotIn("validator:", errors.getvalue() + output.getvalue())
        process = Process(stdout=MARKER + "\n")
        status, output, errors = self.run_main(process, ["validate", str(self.root / "missing.sysml")])
        self.assertEqual(status, 2)
        self.assertEqual(errors, "SysML check failed: Semantic validation requires existing model files\n")
        self.assertNotIn("validator:", output)
        self.assertEqual(process.calls, [])

    def test_timeout_is_no_model_fault(self):
        """TV-197 (TR-02): a run past the limit prints the duration line, then `validator timed
        out after 600 s` as the last line, exits 2 and reports no model fault."""
        status, output, errors = self.run_main(Process(times_out=True), ["validate", str(self.model)])
        self.assertEqual(status, 2)
        lines = errors.splitlines()
        self.assertEqual(len(lines), 2, errors)
        self.assertRegex(lines[0], DURATION)
        self.assertEqual(lines[1], "SysML check failed: validator timed out after 600 s")
        for text in ("faults", "Command '", "Semantic validation failed"):
            self.assertNotIn(text, output + errors)

    def test_timeout_names_the_limit_in_force(self):
        """TV-198 (TR-02): a lowered limit is the limit the duration line and the timeout
        message name."""
        with mock.patch.object(tool, "VALIDATOR_SECONDS", 0.5):
            status, output, errors = self.run_main(Process(delay=0.6, times_out=True), ["validate", str(self.model)])
        self.assertEqual(status, 2)
        lines = errors.splitlines()
        self.assertEqual(len(lines), 2, errors)
        self.assertRegex(lines[0], r"^validator: \d+\.\d s \(limit 0\.5 s\)$")
        self.assertGreaterEqual(float(lines[0].split()[1]), 0.5)
        self.assertEqual(lines[1], "SysML check failed: validator timed out after 0.5 s")
        self.assertNotIn("600", output + errors)

    def test_timeout_in_oracle_keeps_the_oracle_file(self):
        """TV-199 (TR-02): `oracle` with the Pilot run timing out exits 2 with the
        timeout message and leaves the oracle file byte for byte."""
        copy = self.root / tool.ORACLE.name
        shutil.copyfile(tool.ORACLE, copy)
        before = copy.read_bytes()
        with mock.patch.object(tool, "ORACLE", copy):
            status, output, errors = self.run_main(Process(times_out=True), ["oracle"])
        self.assertEqual(status, 2)
        self.assertEqual(errors.splitlines()[-1], "SysML check failed: validator timed out after 600 s")
        self.assertNotIn("Semantic validation failed", output + errors)
        self.assertEqual(copy.read_bytes(), before)

    # Timing: timer
    def test_export_run_unchanged(self):
        """TV-200 (TR-02): the Pilot export keeps its 900 s limit and its 1 GB heap and prints
        no duration line."""
        side = types.SimpleNamespace(label="stub side", paths=[self.model], keys=["valid.sysml"])
        process = Process(stdout="OMG Pilot 0.62.0 syntax/name/semantic validation passed\n")
        errors = io.StringIO()
        with mock.patch.object(tool, "tool_paths", return_value=STUB_TOOLS), \
                mock.patch.object(tool.subprocess, "run", process), contextlib.redirect_stderr(errors):
            tool.run_export(side, ["Valid"], self.root, self.root)
        command, options = process.calls[0]
        self.assertEqual(options["timeout"], 900)
        self.assertEqual(command[1:3], ["-Xmx1g", "-XX:+UseSerialGC"])
        self.assertNotIn("validator:", errors.getvalue())

    def test_traces_prints_no_duration_line(self):
        """TV-202 (TR-02): `traces` starts no Pilot and prints no duration line."""
        output, errors = io.StringIO(), io.StringIO()
        unavailable = mock.Mock(side_effect=AssertionError("traces started the Pilot"))
        with mock.patch.object(tool, "tool_paths", unavailable), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = tool.main(["traces"])
        self.assertEqual(status, 0, errors.getvalue())
        self.assertRegex(output.getvalue().splitlines()[-1], r"^Canonical source/model trace checks passed: \d+ identities; ")
        self.assertNotIn("validator:", output.getvalue() + errors.getvalue())
        unavailable.assert_not_called()


if __name__ == "__main__":
    unittest.main()
