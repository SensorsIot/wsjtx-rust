"""CL-014-18 (#186), S12: `check` on this tree passes with the structure line of its
pending list, after the architecture line; no fault line."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("real_model_structure_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class RealModelStructureTests(unittest.TestCase):
    # S12: on this tree, the files of the pending list pending and the others in target form
    # Proves: CL-014-18; TC-DOC-016
    def test_check_on_this_tree_prints_the_structure_line(self):
        pending = json.loads(tool.PENDING.read_text(encoding="utf-8"))
        files = tool.model_files(tool.MODELS)
        expected = (f"Structure checks passed: {len(files) - len(pending['files'])} files in target form, "
                    f"{len(pending['files'])} files and {len(pending['elements'])} elements pending; deployment rules "
                    + ("off" if "Station.sysml" in pending["files"] else "on"))
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = tool.main(["check"])
        lines = output.getvalue().splitlines()
        self.assertEqual(status, 0, errors.getvalue())
        self.assertEqual([line for line in lines if line.startswith("Structure rule ")], [])
        self.assertRegex(lines[-2], r"^Architecture integrity passed: \d+ parts, \d+ references, \d+ ports, \d+ connections; ")
        self.assertEqual(lines[-1], expected)


if __name__ == "__main__":
    unittest.main()
