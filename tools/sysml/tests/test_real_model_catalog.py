"""The catalog of #183 on the real model, read in place (#183 T2 and C1).

These read docs/sysml as it stands and assert only what holds for any model the catalog
accepts: no FR number, count or package name of today's model. Nothing is written and the
Pilot is not run.
"""
import contextlib
from collections import Counter
import importlib.util
import io
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("real_catalog_tool", ROOT / "tools/sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

LINE = re.compile(r"(FR-\d{3}) (implemented|partial|target): (\d+) clauses, (\d+) implemented, (\d+) partial, (\d+) target"
                  r"(?:; stated (implemented|partial|target))?")
SUMMARY = re.compile(r"(\d+) FRs: (\d+) implemented, (\d+) partial, (\d+) target")


def expected_status(states):
    """Q3 of #183, written here independently: implemented when all clauses are,
    target when all are target or there is none, partial otherwise."""
    if all(state == "target" for state in states):
        return "target"
    if all(state == "implemented" for state in states):
        return "implemented"
    return "partial"


class RealModelStatusTests(unittest.TestCase):
    # T2: status on the working tree, in the P2 form, agreeing with the catalog
    # Proves: CL-014-19; TC-DOC-017
    def test_status_on_this_tree_prints_each_fr_of_the_catalog_with_its_computed_status(self):
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = tool.main(["status"])
        self.assertEqual((status, errors.getvalue()), (0, ""))
        lines = output.getvalue().splitlines()
        entries = tool.canonical_catalog(tool.MODELS, tool.ROOT)
        frs = sorted(identifier for identifier in entries if identifier.startswith("FR-"))
        parsed = [LINE.fullmatch(line) for line in lines[:-1]]
        self.assertTrue(all(parsed), lines)
        self.assertEqual([match[1] for match in parsed], frs)
        for match in parsed:
            with self.subTest(fr=match[1]):
                entry = entries[match[1]]
                states = [entries[clause]["state"] for clause in entry["clauses"]]
                counts = Counter(states)
                self.assertEqual(match[2], expected_status(states))
                self.assertEqual([int(value) for value in match.group(3, 4, 5, 6)],
                                 [len(states), counts["implemented"], counts["partial"], counts["target"]])
                stated = entry["stated"] if entry["stated"] and entry["stated"] != match[2] else None
                self.assertEqual(match[7], stated)
        summary = SUMMARY.fullmatch(lines[-1])
        self.assertIsNotNone(summary, lines[-1])
        per_line = Counter(match[2] for match in parsed)
        self.assertEqual([int(value) for value in summary.groups()],
                         [len(parsed), per_line["implemented"], per_line["partial"], per_line["target"]])


class RealModelPackageTests(unittest.TestCase):
    # C1, accepted: this tree
    # Proves: CL-014-10; TC-DOC-008
    def test_this_tree_is_accepted(self):
        self.assertGreater(len(tool.canonical_catalog(tool.MODELS, tool.ROOT)), 0)


if __name__ == "__main__":
    unittest.main()
