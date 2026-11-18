"""TR-15: the reuse guard (M6.12) on a temporary git repository with a `master` branch.

An identity that a commit of the main branch up to the merge base declared and that the
merge base's model does not declare is used: declared again, whatever its text, it is
refused. Expected lines are written by hand: message, file key and line.
"""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
spec = importlib.util.spec_from_file_location("identity_history_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CLOCK = "docs/sysml/backend/clock/StationClock.sysml"
FIXED = {
    "docs/sysml/Requirements.sysml": """// Canonical authority: SysML
package WstxRequirements {
    requirement 'FR-001' {
        doc /* The station keeps time. */
    }
}
""",
    "docs/sysml/Shack.sysml": "package WstxShack {\n}\n",
    "docs/sysml/Context.sysml": "package WstxContext {\n}\n",
}
KEPT = "The clock MUST hold station time."
KEPT_CHANGED = "The clock MUST hold station time as the PC clock plus its correction."
DROPPED = "The clock MUST correct its time from the stations heard."
NEW = "The clock MUST measure the PC clock against a time server."


def clock_file(*clauses) -> str:
    """The clock's function file with one target clause per (identity, sentence); clause n
    (from 0) starts at line 2 + 5 n."""
    lines = ["package WstxStationClock {"]
    for identity, sentence in clauses:
        lines += [f"    requirement '{identity}' {{",
                  f"        doc /* {sentence} */",
                  "        @Status { build = ImplementationState::target; }",
                  "    }",
                  f"    #derivation connection {{ end #original ::> 'FR-001'; end #derive ::> '{identity}'; }}"]
    return "\n".join(lines + ["}", ""])


class Repository:
    """A temporary git repository; `commit` writes a whole model tree."""

    def __init__(self, folder: Path, branch: str = "master"):
        self.root = folder
        self.git("init", "-q", "-b", branch)

    def git(self, *args: str) -> str:
        env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        env.update(GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        return subprocess.run(["git", "-c", "core.autocrlf=false", "-C", str(self.root), *args], check=True,
                              capture_output=True, text=True, env=env).stdout.strip()

    def write(self, clock: str):
        for path, text in {**FIXED, CLOCK: clock}.items():
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8", newline="\n")

    def commit(self, clock: str, message: str):
        self.write(clock)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)


class IdentityHistoryTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = Path(self.folder.name)
        self.repository = Repository(self.root)
        self.repository.commit(clock_file(("CL-001-01", KEPT), ("CL-001-02", DROPPED)), "two clauses")
        self.repository.commit(clock_file(("CL-001-01", KEPT)), "one clause")
        self.repository.git("checkout", "-q", "-b", "work")

    def tearDown(self):
        self.folder.cleanup()

    def faults(self, clock: str) -> list[str]:
        self.repository.write(clock)
        entries = tool.canonical_catalog(self.root / "docs/sysml", self.root)
        used, present = tool.identity_history(self.root)
        return tool.fault_lines(tool.reuse_faults(entries, used, present))

    def test_kept_and_new_identities_are_accepted(self):
        """TV-082 (TR-15): a kept identity with changed text and a new identity are accepted."""
        self.assertEqual(self.faults(clock_file(("CL-001-01", KEPT_CHANGED), ("CL-001-03", NEW))), [])

    def test_used_identity_declared_again_is_refused(self):
        """TV-083 (TR-15): an identity of an earlier commit that the merge base does not declare is
        refused when declared again, with other text and with its old text."""
        for name, sentence in {"other text": "The clock MUST warn the operator.", "old text": DROPPED}.items():
            with self.subTest(name):
                clock = clock_file(("CL-001-01", KEPT_CHANGED), ("CL-001-03", NEW), ("CL-001-02", sentence))
                self.assertEqual(self.faults(clock),
                                 ["Identity declared again: CL-001-02: backend/clock/StationClock.sysml:12"])


class NoMainBranchTest(unittest.TestCase):
    def test_history_without_master_is_unavailable(self):
        """TV-084 (TR-15): a repository without a `master` branch gives no identity history."""
        with tempfile.TemporaryDirectory() as folder:
            repository = Repository(Path(folder), branch="main")
            repository.commit(clock_file(("CL-001-01", KEPT)), "one clause")
            with self.assertRaises(tool.Unreadable) as raised:
                tool.identity_history(Path(folder))
            self.assertTrue(str(raised.exception).startswith("Identity history unavailable: git merge-base HEAD master: "),
                            str(raised.exception))


if __name__ == "__main__":
    unittest.main()
