"""TR-03 to TR-08 on the real model: `check` on this tree passes every rule after the
architecture comparison, with no fault line."""
import contextlib
import importlib.util
import io
from pathlib import Path
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("real_model_structure_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class RealModelStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # One Pilot run of `check` on this tree serves every test of the class.
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            cls.status = tool.main(["check"])
        cls.output, cls.errors = output.getvalue(), errors.getvalue()

    def test_check_on_this_tree_passes_every_model_rule(self):
        """TV-113 (TR-06): `check` on this tree, whose Shack.sysml holds WstxShack, prints the
        architecture line and then the model rules' line for every model file."""
        shack = tool.MODELS / "Shack.sysml"
        self.assertEqual(tool.file_package(tool.blanked(shack.read_text(encoding="utf-8"))), "WstxShack")
        files = tool.model_files(tool.MODELS)
        lines = self.output.splitlines()
        self.assertEqual(self.status, 0, "\n".join(lines[-40:]) + self.errors)
        self.assertRegex(lines[-2], r"^Architecture integrity passed: \d+ parts, \d+ references, \d+ ports, \d+ connections; ")
        self.assertEqual(lines[-1], f"Model rules passed: {len(files)} model files.")

    def test_check_on_this_tree_prints_one_validator_duration(self):
        """TV-201 (TR-02): `check` on this tree passes and prints exactly one validator
        duration line with the limit 600 s, on stderr only."""
        self.assertEqual(self.status, 0, self.output[-4000:] + self.errors)
        durations = [line for line in self.errors.splitlines() if line.startswith("validator:")]
        self.assertEqual(len(durations), 1, self.errors)
        self.assertRegex(durations[0], r"^validator: \d+\.\d s \(limit 600 s\)$")
        self.assertNotIn("validator:", self.output)


if __name__ == "__main__":
    unittest.main()
