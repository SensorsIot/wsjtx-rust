"""TC-196-07 (#196): no tracked text states an operator's OK for the deploy or the parameter that carried it.

The oracle is git grep over the tracked files of this repository (not the harness submodule,
whose rule is SensorsIot/harness#89's), this file excluded: it names both strings, joined from
two parts so that this file is the only place that would otherwise hold them.
"""
import os
import subprocess
import unittest

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
THIS = os.path.relpath(os.path.abspath(__file__), ROOT).replace(os.sep, "/")
FORBIDDEN = ("Deploy " + "OK:", "-Ok" + "Comment")


class NoOkTextTests(unittest.TestCase):
    def test_no_tracked_file_states_the_deploy_ok(self):
        for text in FORBIDDEN:
            with self.subTest(text):
                proc = subprocess.run(["git", "-C", ROOT, "grep", "-n", "-F", "-e", text, "--", ".", f":(exclude){THIS}"],
                                      capture_output=True, text=True, encoding="utf-8", errors="replace")
                self.assertEqual(proc.returncode, 1, f"{text!r} is still stated:\n{proc.stdout}{proc.stderr}")


if __name__ == "__main__":
    unittest.main()
