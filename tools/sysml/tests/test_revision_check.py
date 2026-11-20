"""TR-23: `check <rev>`, the model check at a revision. `check` without a revision is TV-113's.

`check` needs the pinned toolchain, so these cases run in the suite that runs `check`. The
fixture is a temporary git repository whose first `master` commit is the tree of this
repository's HEAD; its later commits rename one target clause's identity in the model, or add
a comment line to Shack.sysml. The tool runs as a process with the fixture as its repository,
in the fixture's folder; this repository is read only.
"""
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
ROOT = TOOL.parents[1]
spec = importlib.util.spec_from_file_location("revision_check_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

RUNNER = ("import importlib.util, sys\nfrom pathlib import Path\n"
          "spec = importlib.util.spec_from_file_location('sysml_tool', sys.argv[1])\n"
          "tool = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(tool)\n"
          "root = tool.ROOT = Path(sys.argv[2])\ntool.MODELS, tool.FSD = root / 'docs/sysml', root / 'docs/WSTX Rust FSD.md'\n"
          "tool.ORACLE = root / 'tools/sysml/architecture-oracle.json'\nraise SystemExit(tool.main(sys.argv[3:]))\n")
SHACK = "docs/sysml/Shack.sysml"


def environment(temporary=None) -> dict:
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    if temporary is not None:
        env.update(TMP=str(temporary), TEMP=str(temporary), TMPDIR=str(temporary))
    return env


def run(root: Path, *argv: str, temporary=None) -> tuple[int, list[str], str]:
    """(exit code, stdout lines, stderr with `\\n` line ends) of the tool on the repository `root`."""
    result = subprocess.run([sys.executable, "-c", RUNNER, str(TOOL), str(root), *argv], cwd=root,
                            capture_output=True, env=environment(temporary), timeout=1200)
    return (result.returncode, result.stdout.decode("utf-8", "replace").splitlines(),
            result.stderr.decode("utf-8", "replace").replace("\r\n", "\n"))


class RevisionCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory(prefix="sysml-check-test-")
        cls.root = root = Path(cls.folder.name) / "repo"
        cls.temporary = Path(cls.folder.name) / "temporary"
        cls.temporary.mkdir()
        tool.extract("HEAD", root)
        cls.git("init", "-q", "-b", "master")
        cls.commit("this repository's HEAD")
        entries = tool.canonical_catalog(root / "docs/sysml", root)
        cls.kept = next(identity for identity, entry in sorted(entries.items())
                        if identity.startswith("CL-") and entry["state"] == "target" and not entry["cases"])
        cls.renamed = next(cls.kept[:-2] + str(number) for number in range(90, 100) if cls.kept[:-2] + str(number) not in entries)
        cls.rename(cls.kept, cls.renamed)
        cls.before_drop = cls.commit("rename")
        cls.rename(cls.renamed, cls.kept)
        cls.clean = cls.commit("rename back")
        cls.git("checkout", "-q", "-b", "again")
        cls.rename(cls.kept, cls.renamed)
        cls.again = cls.commit("rename again")
        again = tool.canonical_catalog(root / "docs/sysml", root)[cls.renamed]
        cls.reuse = f"Identity declared again: {cls.renamed}: {again['file']}:{again['line']}"
        cls.git("checkout", "-q", "-b", "fault", "master")
        cls.writing = cls.writing_fault()
        cls.faulty = cls.commit("comment")
        cls.git("checkout", "-q", "master")
        cls.status = cls.git("status", "--porcelain")
        runs = {"clean": (root, "check", cls.clean), "faulty": (root, "check", cls.faulty),
                "again": (root, "check", cls.again), "before drop": (root, "check", cls.before_drop),
                "HEAD": (ROOT, "check", "HEAD")}
        # Two Pilot runs at a time stay inside the validator's time bound.
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = {name: pool.submit(run, *argv) for name, argv in runs.items()}
            cls.results = {name: future.result() for name, future in futures.items()}
        cls.stashes = cls.git("stash", "list")
        cls.changed = cls.change_working_tree()
        try:
            cls.working_faults = tool.fault_lines(tool.writing_faults(tool.Model(root / "docs/sysml")))
            cls.results["changed clean"] = run(root, "check", cls.clean, temporary=cls.temporary)
            cls.after = (cls.git("status", "--porcelain"), cls.git("stash", "list"),
                         sorted(path.name for path in cls.temporary.iterdir()))
        finally:
            cls.git("checkout", "-q", "--", ".")
            cls.git("clean", "-q", "-f", "--", "tests", "docs/sysml")

    @classmethod
    def change_working_tree(cls) -> str:
        """The working tree changed: a test added to a Node file and one removed from a Rust file,
        a clause's state edited, an untracked test and model file and a writing-rule fault
        added. Returns its status."""
        script = sorted((cls.root / "tests").glob("*.test.cjs"))[0]
        script.write_bytes(script.read_bytes() + b"\ntest('added in the working tree', () => {});\n")
        rust = next(path for path in sorted((cls.root / "server").rglob("*.rs"))
                    if b"#[test]" in path.read_bytes() and b"Proves:" not in path.read_bytes())
        rust.write_bytes(rust.read_bytes().replace(b"#[test]", b"#[allow(dead_code)]", 1))
        clause = next(path for path in sorted((cls.root / "docs/sysml").rglob("*.sysml"))
                      if b"ImplementationState::implemented" in path.read_bytes())
        clause.write_bytes(clause.read_bytes().replace(b"ImplementationState::implemented", b"ImplementationState::target", 1))
        (cls.root / "tests/untracked.test.cjs").write_bytes(b"test('untracked', () => {});\n")
        (cls.root / "docs/sysml/Untracked.sysml").write_bytes(b"package WstxUntracked {\n}\n")
        cls.working_fault = cls.writing_fault()
        return cls.git("status", "--porcelain")

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    @classmethod
    def git(cls, *args: str) -> str:
        env = environment()
        env.update(GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        return subprocess.run(["git", "-c", "core.autocrlf=false", "-C", str(cls.root), *args], check=True,
                              capture_output=True, text=True, env=env).stdout.strip()

    @classmethod
    def commit(cls, message: str) -> str:
        cls.git("add", "-A")
        cls.git("commit", "-q", "-m", message)
        return cls.git("rev-parse", "HEAD")

    @classmethod
    def rename(cls, old: str, new: str):
        """Every `old` in the model files becomes `new`."""
        for path in (cls.root / "docs/sysml").rglob("*.sysml"):
            text = path.read_bytes().decode("utf-8")
            if old in text:
                path.write_bytes(text.replace(old, new).encode("utf-8"))

    @classmethod
    def writing_fault(cls) -> str:
        """A `//` comment as the last line of Shack.sysml; its fault line."""
        path = cls.root / SHACK
        text = path.read_bytes().decode("utf-8")
        newline = "\r\n" if "\r\n" in text else "\n"
        text = text if text.endswith("\n") else text + newline
        path.write_bytes((text + "// a note" + newline).encode("utf-8"))
        return f"comment //: Shack.sysml:{text.count(chr(10)) + 1}"

    def passed(self, result) -> list[str]:
        code, lines, errors = result
        self.assertEqual(code, 0, errors[-3000:] + "\n".join(lines[-20:]))
        self.assertRegex(lines[-1], r"^Model rules passed: \d+ model files\.$")
        return lines

    def refused(self, result, fault: str):
        code, lines, errors = result
        self.assertEqual(code, 2, errors[-3000:])
        self.assertIn(fault, lines)
        self.assertTrue(errors.endswith("SysML check failed: 1 faults\n"), errors[-3000:])
        self.assertFalse(any(line.startswith("Model rules passed") for line in lines))

    def test_tv187_model_check_at_a_revision(self):
        """TV-187 (TR-23): a clean revision passes while the working tree has a writing-rule fault;
        the revision with that fault fails while the working tree is clean; an identity `master`
        dropped and the revision declares again is refused, accepted at a revision before the
        drop."""
        self.passed(self.results["clean"])
        self.refused(self.results["faulty"], self.writing)
        self.refused(self.results["again"], self.reuse)
        self.passed(self.results["before drop"])
        self.assertEqual(self.passed(self.results["changed clean"]), self.results["clean"][1])
        self.assertIn(self.working_fault, self.working_faults)

    def test_tv181_check_does_not_read_the_working_tree(self):
        """TV-181 (TR-23): `check <rev>` prints the same lines and exit code after a test is added
        and one removed, a clause's state edited and an untracked test and model file added; the
        status, the stash list and the temporary folder are unchanged."""
        self.assertNotEqual(self.changed, self.status)
        self.passed(self.results["clean"])
        self.assertEqual(self.results["changed clean"], self.results["clean"])
        self.assertEqual(self.after, (self.changed, self.stashes, []))
        self.assertEqual(self.git("status", "--porcelain"), self.status)

    def test_tv189_check_head(self):
        """TV-189 (TR-23): `check HEAD` passes on this repository."""
        self.passed(self.results["HEAD"])


if __name__ == "__main__":
    unittest.main()
