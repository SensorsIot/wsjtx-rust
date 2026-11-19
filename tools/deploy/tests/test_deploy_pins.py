"""The deploy pins of harness/project/docs/Project-Specifics.md (section Deploy pins).

The mechanism files are versioned with -text and each pin is the
SHA-256 of its blob; TC-171-02 (i): a checkout or export with CRLF settings holds the blob's bytes.
The oracle is git itself: the blob of HEAD and git archive under core.autocrlf=true.
"""
import hashlib
import io
import os
import re
import subprocess
import sys
import tarfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.dirname(HERE))
import station_drill  # noqa: E402

SPECIFICS = os.path.join(ROOT, "harness", "project", "docs", "Project-Specifics.md")
STATION_UPDATE = os.path.join(ROOT, "tools", "deploy", "station-update", "station-update.ps1")
MAKE_PACKAGE = os.path.join(ROOT, "tools", "deploy", "station-update", "make_package.py")
# A text=auto file of the same tree: under the CRLF settings its export must differ from its blob.
CONTROL = "tools/deploy/tests/pwsh.py"


def git(*args):
    return subprocess.run(["git", "-C", ROOT, *args], check=True, capture_output=True).stdout


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def pins():
    """[(sha256, path)] of the Deploy pins section of the checked-out Project-Specifics.md."""
    found, inside = [], False
    with open(SPECIFICS, encoding="utf-8") as f:
        for line in f.read().splitlines():
            if re.match(r"#{1,6} ", line):
                inside = re.match(r"#{1,6} Deploy pins\s*$", line) is not None
                continue
            m = re.match(r"([0-9a-f]{64})  (\S+)\s*$", line)
            if inside and m:
                found.append((m.group(1), m.group(2)))
    return found


class DeployPinTests(unittest.TestCase):
    def test_each_pin_is_the_sha256_of_its_blob_and_of_the_checked_out_file(self):
        p = pins()
        self.assertTrue(p, "Project-Specifics.md has no Deploy pins")
        wrong = []
        for pin, path in p:
            blob = sha256(git("cat-file", "blob", f"HEAD:{path}"))
            with open(os.path.join(ROOT, *path.split("/")), "rb") as f:
                checked_out = sha256(f.read())
            if pin != blob or pin != checked_out:
                wrong.append(f"{path}: pin {pin}, blob {blob}, checked out {checked_out}")
        self.assertEqual(wrong, [], "\n".join(wrong))

    def test_the_pins_name_every_mechanism_file_in_the_order_the_deploy_reads(self):
        tree = git("ls-tree", "-r", "--name-only", "HEAD", "--", "tools/deploy/station-update/").decode().split()
        with open(MAKE_PACKAGE, encoding="utf-8") as f:
            extra = re.search(r"MECHANISM_FILES = \(([^)]*)\)", f.read()).group(1)
        expected = sorted(tree) + re.findall(r'"([^"]+)"', extra)
        pinned = [path for _, path in pins()]
        self.assertEqual(sorted(pinned), sorted(expected))
        with open(STATION_UPDATE, encoding="utf-8") as f:
            order = re.findall(r"'([^']+)'", re.search(r"\$MechanismPaths=@\(([^)]*)\)", f.read()).group(1))
        self.assertEqual(pinned, order, "pin order is not the order station-update.ps1 reads")
        self.assertEqual(tuple(order), station_drill.MECHANISM)

    def test_mechanism_files_are_not_text(self):
        out = git("check-attr", "text", "--", *station_drill.MECHANISM).decode().splitlines()
        self.assertEqual([line.rsplit(": ", 1)[1] for line in out], ["unset"] * len(station_drill.MECHANISM), out)

    def test_a_crlf_export_holds_the_blob_bytes(self):
        """TC-171-02 (i): git archive applies the checked-out .gitattributes and CRLF settings."""
        paths = list(station_drill.MECHANISM) + [CONTROL]
        data = git("-c", "core.autocrlf=true", "-c", "core.eol=crlf", "archive", "--worktree-attributes",
                   "--format=tar", "HEAD", *paths)
        with tarfile.open(fileobj=io.BytesIO(data)) as t:
            exported = {m.name: t.extractfile(m).read() for m in t.getmembers() if m.isfile()}
        for path in station_drill.MECHANISM:
            with self.subTest(path):
                self.assertEqual(sha256(exported[path]), sha256(git("cat-file", "blob", f"HEAD:{path}")))
        control = git("cat-file", "blob", f"HEAD:{CONTROL}")
        self.assertNotIn(b"\r\n", control)
        self.assertIn(b"\r\n", exported[CONTROL], "the CRLF settings did not reach the export")


# Read-Pins and Specifics-Path of station-update.ps1, taken from the script by the PowerShell
# parser and run alone under Stop, as a caller that captures stderr (`& script 2>&1`) runs them.
PROBE = r"""
param([string]$Repo, [string]$Script, [string]$Commit, [switch]$OldForm)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$tokens, [ref]$errs)
$wanted = @('Specifics-Path', 'Read-Pins')
foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $n.Name }, $true)) {
  . ([scriptblock]::Create($f.Extent.Text)) }
if ($OldForm) { $text = @(& git -C $Repo show "${Commit}:harness/project/docs/Project-Specifics.md"); 'old form returned'; exit 0 }
"path=$(Specifics-Path $Commit)"
$pins = Read-Pins $Commit
if ($null -eq $pins) { 'pins=none' } else { 'pins=' + (@($pins | ForEach-Object { $_.path }) -join ',') }
"""


class ReadPinsStderrTests(unittest.TestCase):
    """Whether a commit has harness/project/docs/Project-Specifics.md is asked without writing to
    stderr, so a caller that captures stderr under Stop gets no pins, not a NativeCommandError."""

    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = os.path.join(self.tmp.name, "repo")
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env = env

        def g(*args):
            return subprocess.run(["git", "-C", self.repo, "-c", "user.name=drill", "-c", "user.email=drill@invalid",
                                   "-c", "commit.gpgsign=false", *args], check=True, capture_output=True,
                                  env=env).stdout.decode().strip()
        os.makedirs(self.repo)
        g("init", "-q")
        self.commits = {}
        for name, rel, pin in (("old", "docs/harness/Project-Specifics.md", "old/path.ps1"),
                               ("new", "harness/project/docs/Project-Specifics.md", "new/path.ps1"),
                               ("neither", None, None)):
            g("rm", "-q", "-r", "--ignore-unmatch", ".")
            if rel:
                station_drill.write(os.path.join(self.repo, *rel.split("/")), station_drill.pins_text([("a" * 64, pin)]))
            station_drill.write(os.path.join(self.repo, "README.md"), name + "\n")
            g("add", "-A")
            g("commit", "-q", "-m", name)
            self.commits[name] = g("rev-parse", "HEAD")
        self.probe = os.path.join(self.tmp.name, "probe.ps1")
        with open(self.probe, "w", encoding="utf-8-sig") as f:
            f.write(PROBE)

    def tearDown(self):
        self.tmp.cleanup()

    def run_probe(self, commit, old_form=False):
        call = (f"& '{self.probe}' -Repo '{self.repo}' -Script '{STATION_UPDATE}' -Commit {commit}"
                + (" -OldForm" if old_form else "") + " 2>&1")
        proc = subprocess.run([station_drill.POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                               "-Command", f"$ErrorActionPreference = 'Stop'; {call}; exit $LASTEXITCODE"],
                              capture_output=True, text=True, encoding="utf-8", errors="replace", env=self.env, timeout=120)
        return proc.returncode, proc.stdout + proc.stderr

    def test_the_old_form_writes_to_stderr_for_a_missing_file(self):
        """The control: a git show of a missing file writes to stderr, which a caller capturing
        stderr under Stop in Windows PowerShell 5.1 receives as a terminating NativeCommandError
        (whether this host does so as well is not what the test relies on)."""
        rc, out = self.run_probe(self.commits["old"], old_form=True)
        self.assertIn("fatal: path 'harness/project/docs/Project-Specifics.md' does not exist", out)

    # Proves: TC-248-03
    def test_only_harness_project_docs_holds_pins_and_none_is_asked_without_an_error(self):
        expected = {"new": ("harness/project/docs/Project-Specifics.md", "new/path.ps1"),
                    "old": ("", "none"),
                    "neither": ("", "none")}
        for name, (path, pins) in expected.items():
            with self.subTest(name):
                rc, out = self.run_probe(self.commits[name])
                self.assertEqual(rc, 0, out)
                self.assertIn(f"path={path}\n", out)
                self.assertIn(f"pins={pins}", out)
                self.assertNotIn("NativeCommandError", out)
                self.assertNotIn("fatal:", out, "nothing on stderr, so nothing for Stop to end on")


if __name__ == "__main__":
    unittest.main()
