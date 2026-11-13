"""The catalog of #183 on the real model, read in place (#183 T2 and C1).

These read docs/sysml as it stands: they change when the model does. Nothing is written
and the Pilot is not run.
"""
import contextlib
import importlib.util
import io
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("real_catalog_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class RealModelStatusTests(unittest.TestCase):
    # T2: section 6 of the target (#53): FR-013, FR-014, FR-015 and FR-017 have no clause
    # today; FR-017 states partial.
    # Proves: CL-014-19; TC-DOC-017
    def test_status_on_this_tree_prints_24_frs_and_the_four_without_clauses(self):
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = tool.main(["status"])
        self.assertEqual((status, errors.getvalue()), (0, ""))
        lines = output.getvalue().splitlines()
        self.assertEqual(len(lines), 25)
        self.assertRegex(lines[-1], r"^24 FRs: \d+ implemented, \d+ partial, \d+ target$")
        without = {line.split(" ", 1)[0]: line for line in lines[:-1] if " 0 clauses," in line}
        self.assertEqual(without, {
            "FR-013": "FR-013 target: 0 clauses, 0 implemented, 0 partial, 0 target",
            "FR-014": "FR-014 target: 0 clauses, 0 implemented, 0 partial, 0 target",
            "FR-015": "FR-015 target: 0 clauses, 0 implemented, 0 partial, 0 target",
            "FR-017": "FR-017 target: 0 clauses, 0 implemented, 0 partial, 0 target; stated partial",
        })


class RealModelPackageTests(unittest.TestCase):
    # C1, accepted: this tree, with WstxProductScope present
    # Proves: CL-014-10; TC-DOC-008
    def test_this_tree_with_productscope_is_accepted(self):
        packages = {tool.file_package(tool.blanked(path.read_text(encoding="utf-8")))
                    for path in tool.model_files(tool.MODELS).values()}
        self.assertIn("WstxProductScope", packages)
        self.assertGreater(len(tool.canonical_catalog(tool.MODELS, tool.ROOT)), 0)


if __name__ == "__main__":
    unittest.main()
