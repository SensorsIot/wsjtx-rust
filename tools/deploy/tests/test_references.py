"""Acceptance item 3 of #171: no tracked file names the old location of a moved deploy file.

The deploy scripts moved from .git/harness-parallel/resources/station-update/ and .harness/deploy/
to tools/deploy/. A hit is allowed only where the issue marks the reference unchanged:
.harness/deploy/authority/ (retired by #188).
"""
import os
import subprocess
import unittest

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OLD = (r"resources[/\\]station-update[/\\](station-update\.ps1|make_package\.py|launcher\.ps1|agent-client\.ps1)"
       r"|\.harness[/\\]deploy[/\\](live-page-check\.ps1|station-probe\.ps1|station_drill\.py)"
       r"|\.harness[/\\]deploy[/\\]tests[/\\](pwsh|test_station_probe|test_live_page_check|test_station_drill)\b")
UNCHANGED = (".harness/deploy/authority/",)
SELF = "tools/deploy/tests/test_references.py"


class ReferenceTests(unittest.TestCase):
    def test_no_reference_to_the_old_location(self):
        r = subprocess.run(["git", "-C", ROOT, "grep", "-n", "-I", "-E", OLD, "--", ".", f":(exclude){SELF}"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertIn(r.returncode, (0, 1), r.stderr)
        hits = [line for line in r.stdout.splitlines() if not line.startswith(UNCHANGED)]
        self.assertEqual(hits, [], "\n".join(hits))


if __name__ == "__main__":
    unittest.main()
