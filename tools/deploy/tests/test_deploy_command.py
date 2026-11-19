"""make_package.py as the one deploy command: given only the commit, it checks the
commit and its push-gate log, builds or reuses the package and runs the package's own
station-update.ps1, whose exit it returns.

Each case runs in a temporary git repository with a local bare origin, its own logs and
packages folders, a stub station-update.ps1 committed there (it records its path, its
arguments and the SHA-256 of its own bytes and exits with STUB_EXIT) and a fake cargo and
rustc first on PATH (the fake cargo writes FAKE_CARGO_LINES numbered lines to stderr and
exits with FAKE_CARGO_EXIT, both 0 unless a test sets them). The command is the repository's make_package.py, committed in the
temporary repository with REPO and BUILD_ROOT pointing inside the temporary folder.
"""
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.dirname(HERE))
import station_drill  # noqa: E402

MAKE_PACKAGE = os.path.join(ROOT, "tools", "deploy", "station-update", "make_package.py")
SCRIPT = "tools/deploy/station-update/station-update.ps1"
COMMAND = "tools/deploy/station-update/make_package.py"
USAGE = "usage: make_package.py <commit> [--dry-run]"
FLAGS = ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"]

STUB = r"""# test stub of station-update.ps1
$record = [ordered]@{ path = $PSCommandPath; args = @($args)
  argv = @([Environment]::GetCommandLineArgs() | Select-Object -Skip 1)
  sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash.ToLowerInvariant() }
[IO.File]::WriteAllText($env:STUB_RECORD, ($record | ConvertTo-Json -Compress))
'stub: station-update ran'
exit [int]$env:STUB_EXIT
"""

FAKE_CARGO = """import os, sys
with open(os.environ["FAKE_CARGO_RECORD"], "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\\n")
release = os.path.join(os.environ["CARGO_TARGET_DIR"], "release")
os.makedirs(release, exist_ok=True)
with open(os.path.join(release, "wstx-rust.exe"), "wb") as f:
    f.write(b"fake station executable")
for n in range(1, int(os.environ.get("FAKE_CARGO_LINES", "0")) + 1):
    print(f"cargo-{n:02d}", file=sys.stderr)
sys.exit(int(os.environ.get("FAKE_CARGO_EXIT", "0")))
"""
FAKE_RUSTC = 'print("rustc 0.0.0 (fake)")\n'


def fake_exe(path, script):
    """An .exe that runs `script` with this Python: the launcher pip installs console scripts
    with (distlib), followed by the shebang and a zip holding __main__.py. A subprocess on
    Windows finds only .exe files on PATH, so a .bat or .cmd fake would not be found."""
    import pip
    with open(os.path.join(os.path.dirname(pip.__file__), "_vendor", "distlib", "t64.exe"), "rb") as f:
        launcher = f.read()
    exe = sys.executable
    shebang = (f'#!"{exe}"\n' if " " in exe else f"#!{exe}\n").encode("utf-8")
    data = io.BytesIO()
    with zipfile.ZipFile(data, "w") as z:
        z.writestr("__main__.py", script)
    with open(path, "wb") as f:
        f.write(launcher + shebang + data.getvalue())


def git_bash():
    """Git's own bash (a bare `bash` on Windows may be the WSL launcher)."""
    core = subprocess.run(["git", "--exec-path"], capture_output=True, text=True, check=True).stdout.strip()
    bash = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(core))), "bin", "bash.exe")
    if not os.path.isfile(bash):
        raise RuntimeError(f"no Git Bash beside {core}")
    return bash


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def same_path(a, b):
    return os.path.normcase(os.path.normpath(a)) == os.path.normcase(os.path.normpath(b))


def snapshot(folder):
    """Every file and directory under folder with its digest."""
    state = {}
    for dirpath, _, names in os.walk(folder):
        state[os.path.relpath(dirpath, folder) + os.sep] = "dir"
        for name in names:
            with open(os.path.join(dirpath, name), "rb") as f:
                state[os.path.relpath(os.path.join(dirpath, name), folder)] = sha256(f.read())
    return state


def green_log(new, old="5a5a5a5a5"):
    return (f"$ bash -c gate\nharness gate: 4 suites, green\n$ git push origin HEAD:refs/heads/master\n"
            f"To github.com:example/repo.git\n   {old}..{new}  HEAD -> master\n")


def red_log():
    return "$ bash -c gate\nRED     deploy-tooling: exit 1\nharness gate: red: deploy-tooling\n"


class DeployCommandTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.repo = os.path.join(t, "repo")
        self.origin = os.path.join(t, "origin.git")
        self.build_root = os.path.join(t, "build")
        self.record = os.path.join(t, "stub.json")
        self.cargo_record = os.path.join(t, "cargo.txt")
        self.station = os.path.join(t, "LocalAppData", "WstxRust", "station")
        bindir = os.path.join(t, "bin")
        os.makedirs(bindir)
        fake_exe(os.path.join(bindir, "cargo.exe"), FAKE_CARGO)
        fake_exe(os.path.join(bindir, "rustc.exe"), FAKE_RUSTC)
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        env.update(PATH=os.pathsep.join([bindir, os.path.dirname(sys.executable), env.get("PATH", "")]),
                   STUB_RECORD=self.record, STUB_EXIT="0", FAKE_CARGO_RECORD=self.cargo_record,
                   LOCALAPPDATA=os.path.join(t, "LocalAppData"))
        self.env = env

        with open(MAKE_PACKAGE, encoding="utf-8", newline="") as f:
            source = f.read()
        for name, live, test in (("REPO", r"D:\Github\wsjtx-rust", self.repo),
                                 ("BUILD_ROOT", r"C:\wstx-build", self.build_root)):
            line = f'{name} = r"{live}"'
            self.assertEqual(source.count(line), 1, f"make_package.py has no {line}")
            source = source.replace(line, f'{name} = r"{test}"')

        self.git("init", "-q", "--bare", self.origin, repo=t)
        os.makedirs(self.repo)
        self.git("init", "-q", "--initial-branch=master")
        shutil.copyfile(os.path.join(ROOT, ".gitattributes"), os.path.join(self.repo, ".gitattributes"))
        files = {path: f"# {path}\n" for path in station_drill.MECHANISM}
        files.update({SCRIPT: STUB, COMMAND: source, "COPYING": "licence\n",
                      "server/third-party/cty/LICENSE": "notice\n"})
        for path, text in files.items():
            station_drill.write(os.path.join(self.repo, *path.split("/")), text)
        self.commit_all("first")
        self.parent = self.git("rev-parse", "HEAD")
        station_drill.write(os.path.join(self.repo, "README.md"), "second\n")
        self.commit_all("second")
        self.commit = self.git("rev-parse", "HEAD")
        self.ver = self.commit[:9]
        self.git("remote", "add", "origin", self.origin)
        self.git("push", "-q", "origin", "master")
        common = os.path.join(self.repo, ".git", "harness-parallel")
        self.logs = os.path.join(common, "queue", "logs")
        self.packages = os.path.join(common, "resources", "station-update", "packages")
        self.out = os.path.join(self.packages, self.ver)
        self.source = self.blob(COMMAND)

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args, repo=None):
        return subprocess.run(["git", "-C", repo or self.repo, "-c", "user.name=test", "-c", "user.email=test@invalid",
                               "-c", "commit.gpgsign=false", *args], check=True, capture_output=True,
                              env=self.env).stdout.decode().strip()

    def commit_all(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def blob(self, path, commit=None):
        return subprocess.run(["git", "-C", self.repo, "cat-file", "blob", f"{commit or self.commit}:{path}"],
                              check=True, capture_output=True, env=self.env).stdout

    def log(self, name, text):
        station_drill.write(os.path.join(self.logs, name), text)
        return name

    def qualifying_log(self, commit=None):
        commit = commit or self.commit
        return self.log(f"20261119T080000Z-{commit[:12]}.log", green_log(commit[:9]))

    def plant_package(self, source_commit=None, manifest=True, out=None):
        """A package folder: the committed stub as its station-update.ps1 and a manifest."""
        out = out or self.out
        station_drill.write(os.path.join(out, "deploy", *SCRIPT.split("/")), self.blob(SCRIPT))
        if manifest:
            station_drill.write_json(os.path.join(out, "manifest.json"),
                                     {"source_commit": source_commit or self.commit})

    def plant_neighbours(self):
        """A complete package of the parent commit and a build folder of its version; returns
        their snapshots."""
        pver = self.parent[:9]
        self.neighbours = [os.path.join(self.packages, pver), os.path.join(self.build_root, pver)]
        self.plant_package(self.parent, out=self.neighbours[0])
        station_drill.write(os.path.join(self.neighbours[1], "src", "kept.txt"), "neighbour\n")
        return [snapshot(p) for p in self.neighbours]

    def assert_neighbours(self, before):
        self.assertEqual([snapshot(p) for p in self.neighbours], before)

    def reset(self):
        """No package folder of the commit, no stub record, no cargo record."""
        shutil.rmtree(self.out, ignore_errors=True)
        for path in (self.record, self.cargo_record):
            if os.path.exists(path):
                os.remove(path)

    def build_dir(self, ver=None):
        return os.path.join(self.build_root, ver or self.ver)

    def run_command(self, *args, env=None):
        """The command as the one line runs it: the commit's make_package.py on python's stdin."""
        proc = subprocess.run([sys.executable, "-", *args], input=self.source, capture_output=True,
                              cwd=self.tmp.name, env=dict(self.env, **(env or {})), timeout=300)
        return proc.returncode, (proc.stdout + proc.stderr).decode("utf-8", "replace")

    def run_merged(self, *args, env=None):
        """The command as Alex's run_bound runs it: stdout and stderr into one file, read as one stream."""
        with tempfile.TemporaryFile() as f:
            proc = subprocess.run([sys.executable, "-", *args], input=self.source, stdout=f, stderr=subprocess.STDOUT,
                                  cwd=self.tmp.name, env=dict(self.env, **(env or {})), timeout=300)
            f.seek(0)
            return proc.returncode, f.read().decode("utf-8", "replace")

    def assert_built(self, rc, out):
        self.assertEqual(rc, 0, out)
        self.assertIn(f"package {self.ver}: built", out)
        with open(self.manifest_path(), encoding="utf-8") as f:
            self.assertEqual(json.load(f)["source_commit"], self.commit)
        self.assertIsNotNone(self.stub_record(), out)

    def assert_removed(self, out, path):
        self.assertIn(f"removed the leftover {os.path.normpath(path)}".lower(), out.lower())

    def run_line(self, commit, *args):
        """The one line in Git Bash, with set -o pipefail."""
        repo = self.repo.replace("\\", "/")
        line = (f"set -o pipefail; git -C '{repo}' show {commit}:{COMMAND} | python - {commit}"
                + "".join(" " + a for a in args))
        proc = subprocess.run([git_bash(), "-c", line], capture_output=True, cwd=self.tmp.name, env=self.env,
                              timeout=300)
        return proc.returncode, (proc.stdout + proc.stderr).decode("utf-8", "replace")

    def stub_record(self):
        if not os.path.exists(self.record):
            return None
        with open(self.record, encoding="utf-8-sig") as f:
            return json.load(f)

    def manifest_path(self, ver=None):
        return os.path.join(self.packages, ver or self.ver, "manifest.json")

    def assert_nothing_ran(self, out, ver=None):
        self.assertFalse(os.path.exists(os.path.join(self.packages, ver or self.ver)), out)
        self.assertIsNone(self.stub_record(), out)

    def assert_args(self, record, dry_run):
        args = record["args"]
        self.assertEqual(len(args), 3 if dry_run else 2, args)
        self.assertEqual(args[0], "-Manifest")
        self.assertTrue(same_path(args[1], self.manifest_path()), args)
        self.assertEqual(args[2:], ["-DryRun"] if dry_run else [])

    # Proves: TC-245-01
    def test_dry_run_passes_manifest_and_dry_run_only(self):
        self.qualifying_log()
        self.plant_package()
        script = os.path.join(self.out, "deploy", *SCRIPT.split("/"))
        for dry_run in (True, False):
            with self.subTest(dry_run=dry_run):
                if os.path.exists(self.record):
                    os.remove(self.record)
                rc, out = self.run_command(self.commit, *(["--dry-run"] if dry_run else []))
                self.assertEqual(rc, 0, out)
                self.assertIn("stub: station-update ran", out)
                record = self.stub_record()
                self.assertTrue(same_path(record["path"], script), record)
                self.assert_args(record, dry_run)
                argv = record["argv"]
                self.assertEqual(argv[:5], FLAGS, argv)
                self.assertTrue(same_path(argv[5], script), argv)
                self.assertEqual(argv[6:], record["args"])

    # Proves: TC-245-02
    def test_the_exit_of_station_update_passes_through(self):
        self.qualifying_log()
        self.plant_package()
        for code in (0, 1, 3, 6):
            with self.subTest(exit=code):
                rc, out = self.run_command(self.commit, env={"STUB_EXIT": str(code)})
                self.assertEqual(rc, code, out)
                self.assertIsNotNone(self.stub_record(), out)

    # Proves: TC-245-03
    def test_a_package_of_the_commit_is_reused_and_an_absent_one_is_built(self):
        self.qualifying_log()
        self.plant_package()
        rc, out = self.run_command(self.commit, "--dry-run")
        self.assertEqual(rc, 0, out)
        self.assertIn(f"package {self.ver}: reused", out)
        self.assertFalse(os.path.exists(self.cargo_record), "cargo was called for a package that exists")
        self.assertIsNotNone(self.stub_record(), out)
        shutil.rmtree(self.out)
        os.remove(self.record)
        rc, out = self.run_command(self.commit, "--dry-run")
        self.assertEqual(rc, 0, out)
        self.assertIn(f"package {self.ver}: built", out)
        with open(self.cargo_record, encoding="utf-8") as f:
            self.assertEqual(f.read(), "build --release --locked -p wstx-rust\n")
        with open(os.path.join(self.out, "gates.json"), encoding="utf-8") as f:
            self.assertEqual(json.load(f)["toolchain"], "rustc 0.0.0 (fake)")
        self.assertIsNotNone(self.stub_record(), out)

    # Proves: TC-245-04
    def test_exactly_the_qualifying_push_gate_log_is_named(self):
        c12, other = self.commit[:12], self.parent
        close = self.ver[:8] + ("0" if self.ver[8] != "0" else "1")
        cases = [
            ("a red first run and a green rerun", [(f"20261119T080000Z-{c12}.log", red_log()),
                                                   (f"20261119T081000Z-{c12}-rerun.log", green_log(self.ver))],
             f"20261119T081000Z-{c12}-rerun.log"),
            ("a push line with a longer abbreviation", [(f"20261119T080000Z-{c12}.log", green_log(c12))],
             f"20261119T080000Z-{c12}.log"),
            ("a log of another commit", [(f"20261118T080000Z-{other[:12]}.log", green_log(other[:9])),
                                         (f"20261119T080000Z-{c12}.log", green_log(self.ver))],
             f"20261119T080000Z-{c12}.log"),
            ("a push line naming another commit's prefix", [(f"20261119T070000Z-{close}000.log", green_log(close)),
                                                            (f"20261119T080000Z-{c12}.log", green_log(self.ver))],
             f"20261119T080000Z-{c12}.log"),
        ]
        self.plant_package()
        for name, logs, expected in cases:
            with self.subTest(name):
                shutil.rmtree(self.logs, ignore_errors=True)
                for log_name, text in logs:
                    self.log(log_name, text)
                rc, out = self.run_command(self.commit, "--dry-run")
                self.assertEqual(rc, 0, out)
                named = [line[len("push-gate log: "):] for line in out.splitlines() if line.startswith("push-gate log: ")]
                self.assertEqual(len(named), 1, out)
                self.assertTrue(same_path(named[0], os.path.join(self.logs, expected)), named)

    # Proves: TC-245-05
    def test_a_commit_not_on_github_master_is_refused(self):
        self.git("checkout", "-q", "-b", "side")
        station_drill.write(os.path.join(self.repo, "side.txt"), "side\n")
        self.commit_all("side")
        side = self.git("rev-parse", "HEAD")
        self.git("checkout", "-q", "master")
        self.qualifying_log(side)
        rc, out = self.run_command(side)
        self.assertEqual(rc, 1, out)
        self.assertIn(f"refused: {side[:9]} is not on GitHub master", out)
        self.assert_nothing_ran(out, side[:9])

    # Proves: TC-245-06
    def test_no_qualifying_push_gate_log_is_refused(self):
        other = ("1" if self.ver[0] != "1" else "2") * 9
        self.log(f"20261119T080000Z-{self.commit[:12]}.log", red_log())
        self.log(f"20261119T090000Z-{other}000.log", green_log(other))
        self.log(f"20261118T080000Z-{self.parent[:12]}.log", green_log(self.parent[:9]))
        rc, out = self.run_command(self.commit)
        self.assertEqual(rc, 1, out)
        self.assertIn(f"refused: no push-gate log shows the push of {self.ver} to master", out)
        self.assert_nothing_ran(out)

    # Proves: TC-245-07
    def test_two_qualifying_push_gate_logs_are_refused(self):
        a = self.log(f"20261119T080000Z-{self.commit[:12]}.log", green_log(self.ver))
        b = self.log(f"20261119T081000Z-{self.commit[:12]}-rerun.log", green_log(self.ver))
        rc, out = self.run_command(self.commit)
        self.assertEqual(rc, 1, out)
        self.assertIn(f"refused: 2 push-gate logs show the push of {self.ver}: {a}, {b}", out)
        self.assert_nothing_ran(out)

    # Proves: TC-245-08
    def test_the_one_line_runs_no_working_tree_bytes(self):
        marker = "WORKING-TREE-MARKER"
        for path, line in ((COMMAND, f'print("{marker}")\n'), (SCRIPT, f"'{marker}'\n")):
            full = os.path.join(self.repo, *path.split("/"))
            with open(full, "rb") as f:
                data = f.read()
            with open(full, "wb") as f:
                f.write(line.encode() + data)
        self.assertIn("make_package.py", self.git("status", "--porcelain"))
        self.qualifying_log()
        rc, out = self.run_line(self.commit, "--dry-run")
        self.assertEqual(rc, 0, out)
        self.assertNotIn(marker, out)
        self.assertIn(f"package {self.ver}: built", out)
        record = self.stub_record()
        self.assertTrue(same_path(record["path"], os.path.join(self.out, "deploy", *SCRIPT.split("/"))), record)
        self.assertEqual(record["sha256"], sha256(self.blob(SCRIPT)))
        self.assert_args(record, dry_run=True)

    # Proves: TC-245-09
    def test_any_other_argument_list_is_refused_with_the_usage_line(self):
        log = os.path.join(self.logs, self.qualifying_log())
        c = self.commit
        for args in ([], [c, log], [c, "--force"], [c, "-DryRun"], [c, "--dry-run", "--dry-run"], ["--dry-run"]):
            with self.subTest(args=args):
                rc, out = self.run_command(*args)
                self.assertEqual(rc, 1, out)
                self.assertIn(USAGE, out)
                self.assertFalse(os.path.exists(os.path.join(self.repo, ".git", "FETCH_HEAD")), out)
                self.assert_nothing_ran(out)

    # Proves: TC-245-10
    def test_a_dry_run_changes_neither_station_nor_packages(self):
        self.qualifying_log()
        self.plant_package()
        station_drill.write(os.path.join(self.station, "ccccccccc", "wstx-rust.exe"), b"running image")
        station_drill.write(os.path.join(self.station, "launcher.ps1"), station_drill.LAUNCHER)
        station_drill.write(os.path.join(self.station, "profiles", "ic7300", "station.json"), '{"profile": 1}')
        station_drill.write_json(os.path.join(self.station, "active.json"), {"source_commit": "c" * 40})
        before = (snapshot(self.station), snapshot(self.packages))
        rc, out = self.run_command(self.commit, "--dry-run")
        self.assertEqual(rc, 0, out)
        self.assertEqual((snapshot(self.station), snapshot(self.packages)), before)
        self.assertEqual(self.stub_record()["args"][-1], "-DryRun")

    # Proves: TC-245-11
    def test_a_commit_git_cannot_show_runs_nothing(self):
        self.qualifying_log()
        missing = "0" * 40
        rc, out = self.run_line(missing, "--dry-run")
        self.assertNotIn(rc, (0, 3, 6), out)
        self.assertFalse(os.path.exists(os.path.join(self.repo, ".git", "FETCH_HEAD")), out)
        self.assertFalse(os.path.exists(self.packages), out)
        self.assertIsNone(self.stub_record(), out)

    # Proves: TC-245-12
    def test_a_package_of_another_commit_is_refused_unchanged(self):
        self.qualifying_log()
        neighbours = self.plant_neighbours()
        self.plant_package(source_commit=self.parent)
        station_drill.write(os.path.join(self.out, "build.log"), "an earlier build\n")
        station_drill.write(os.path.join(self.build_dir(), "src", "main.rs"), "stopped\n")
        before = snapshot(self.out)
        rc, out = self.run_command(self.commit, "--dry-run")
        self.assertEqual(rc, 1, out)
        self.assertIn(f"refused: {os.path.normpath(self.out)} exists and holds no package of {self.commit}"
                      .lower(), out.lower())
        self.assertEqual(snapshot(self.out), before)
        self.assert_removed(out, self.build_dir())
        self.assertFalse(os.path.exists(self.build_dir()), out)
        self.assertFalse(os.path.exists(self.cargo_record), out)
        self.assertIsNone(self.stub_record(), out)
        self.assert_neighbours(neighbours)

    # Proves: TC-246-01
    def test_a_package_folder_holding_only_a_build_log_is_removed_and_built(self):
        self.qualifying_log()
        neighbours = self.plant_neighbours()
        station_drill.write(os.path.join(self.out, "build.log"), "an earlier failed build\n")
        rc, out = self.run_command(self.commit, "--dry-run")
        self.assert_removed(out, self.out)
        self.assert_built(rc, out)
        with open(os.path.join(self.out, "build.log"), encoding="utf-8") as f:
            self.assertNotIn("an earlier failed build", f.read())
        self.assert_neighbours(neighbours)

    # Proves: TC-246-02
    def test_a_partial_package_folder_without_a_manifest_is_removed_and_built(self):
        self.qualifying_log()
        neighbours = self.plant_neighbours()
        for name, extra in (("build.log, package and deploy", False), ("with gates.json and the gate receipt", True)):
            with self.subTest(name):
                self.reset()
                self.plant_package(manifest=False)
                station_drill.write(os.path.join(self.out, "build.log"), "an earlier build\n")
                station_drill.write(os.path.join(self.out, "package", "wstx-rust.exe"), b"partial image")
                if extra:
                    station_drill.write_json(os.path.join(self.out, "gates.json"), {"source_commit": self.commit})
                    station_drill.write(os.path.join(self.out, f"gate-receipt-{self.ver}.log"), "receipt\n")
                rc, out = self.run_command(self.commit, "--dry-run")
                self.assert_removed(out, self.out)
                self.assert_built(rc, out)
                self.assert_neighbours(neighbours)

    # Proves: TC-246-03
    def test_a_manifest_that_names_no_commit_is_removed_and_built(self):
        self.qualifying_log()
        neighbours = self.plant_neighbours()
        rc, out = self.run_command(self.commit, "--dry-run")
        self.assertEqual(rc, 0, out)
        with open(self.manifest_path(), encoding="utf-8") as f:
            real = f.read()
        for name, text in (("a manifest cut mid-write", real[:len(real) // 2]), ("{}", "{}"), ("[]", "[]"),
                           ("a null source_commit", '{"source_commit": null}')):
            with self.subTest(name):
                self.reset()
                self.plant_package(manifest=False)
                station_drill.write(os.path.join(self.out, "manifest.json"), text)
                rc, out = self.run_command(self.commit, "--dry-run")
                self.assert_removed(out, self.out)
                self.assert_built(rc, out)
                self.assert_neighbours(neighbours)

    # Proves: TC-246-04
    def test_a_leftover_build_folder_is_removed_before_the_build(self):
        self.qualifying_log()
        neighbours = self.plant_neighbours()
        station_drill.write(os.path.join(self.build_dir(), "src", "Cargo.toml"), "[workspace]\n")
        station_drill.write(os.path.join(self.build_dir(), "src.tar"), b"half an archive")
        os.makedirs(os.path.join(self.build_dir(), "target", "release"))
        rc, out = self.run_command(self.commit, "--dry-run")
        self.assert_removed(out, self.build_dir())
        self.assert_built(rc, out)
        self.assertFalse(os.path.exists(self.build_dir()), out)
        self.assertNotIn("Traceback", out)
        self.assert_neighbours(neighbours)

    # Proves: TC-246-05
    def test_a_leftover_build_folder_beside_the_commits_package_is_removed_and_the_package_reused(self):
        self.qualifying_log()
        neighbours = self.plant_neighbours()
        self.plant_package()
        station_drill.write(os.path.join(self.build_dir(), "target", "release", "wstx-rust.exe"), b"built image")
        before = snapshot(self.out)
        rc, out = self.run_command(self.commit, "--dry-run")
        self.assertEqual(rc, 0, out)
        self.assertIn(f"package {self.ver}: reused", out)
        self.assertFalse(os.path.exists(self.cargo_record), out)
        self.assertFalse(os.path.exists(self.build_dir()), out)
        self.assertEqual(snapshot(self.out), before)
        self.assert_neighbours(neighbours)

    # Proves: TC-246-06
    def test_a_failed_build_prints_its_last_lines_and_leaves_nothing_behind(self):
        self.qualifying_log()
        neighbours = self.plant_neighbours()
        failure = "release build failed (cargo exit 101)"
        for lines, expected in ((11, [f"cargo-{n:02d}" for n in range(2, 12)]), (3, ["cargo-01", "cargo-02", "cargo-03"])):
            with self.subTest(lines=lines):
                self.reset()
                rc, out = self.run_merged(self.commit, "--dry-run",
                                          env={"FAKE_CARGO_EXIT": "101", "FAKE_CARGO_LINES": str(lines)})
                self.assertEqual(rc, 1, out)
                self.assertEqual(out.strip().splitlines()[-len(expected) - 1:], expected + [failure], out)
                if lines == 11:
                    self.assertNotIn("cargo-01", out)
                self.assertFalse(os.path.exists(self.out), out)
                self.assertFalse(os.path.exists(self.build_dir()), out)
                self.assertIsNone(self.stub_record(), out)
                self.assert_neighbours(neighbours)
        self.reset()
        rc, out = self.run_merged(self.commit, "--dry-run")
        self.assert_built(rc, out)
        self.assert_neighbours(neighbours)

    # Proves: TC-246-07
    def test_a_failure_after_the_copy_started_leaves_nothing_behind(self):
        neighbours = self.plant_neighbours()
        for path, message in (("server/third-party", "server/third-party is missing or empty in the commit"),
                              ("tools/deploy/station-probe.ps1",
                               "the commit has no tools/deploy/station-probe.ps1")):
            with self.subTest(path):
                self.git("checkout", "-q", self.commit)
                self.git("rm", "-q", "-r", path)
                self.git("commit", "-q", "-m", f"without {path}")
                commit = self.git("rev-parse", "HEAD")
                self.git("push", "-q", "-f", "origin", "HEAD:master")
                self.qualifying_log(commit)
                ver = commit[:9]
                rc, out = self.run_command(commit, "--dry-run")
                self.assertEqual(rc, 1, out)
                self.assertIn(message, out)
                self.assertFalse(os.path.exists(os.path.join(self.packages, ver)), out)
                self.assertFalse(os.path.exists(self.build_dir(ver)), out)
                self.assertIsNone(self.stub_record(), out)
                self.assert_neighbours(neighbours)

    # Proves: TC-246-08
    def test_a_leftover_that_cannot_be_removed_is_refused_before_any_build(self):
        self.qualifying_log()
        neighbours = self.plant_neighbours()
        for name, folder, held in (("in the package folder", self.out, "build.log"),
                                   ("in the build folder", self.build_dir(), os.path.join("src", "held.txt"))):
            with self.subTest(name):
                self.reset()
                shutil.rmtree(self.build_dir(), ignore_errors=True)
                station_drill.write(os.path.join(folder, held), "held open\n")
                with open(os.path.join(folder, held), "rb"):
                    rc, out = self.run_command(self.commit, "--dry-run")
                self.assertEqual(rc, 1, out)
                self.assertIn(f"refused: the leftover {os.path.normpath(folder)} cannot be removed: ".lower(),
                              out.lower())
                self.assertNotIn("Traceback", out)
                self.assertFalse(os.path.exists(self.cargo_record), out)
                self.assertIsNone(self.stub_record(), out)
                self.assert_neighbours(neighbours)
                shutil.rmtree(folder)

    # Proves: TC-245-14
    def test_an_unreachable_origin_is_refused(self):
        self.qualifying_log()
        os.rename(self.origin, self.origin + "-moved")
        rc, out = self.run_command(self.commit)
        self.assertEqual(rc, 1, out)
        self.assertIn("refused: git fetch of GitHub master failed", out)
        self.assert_nothing_ran(out)

    # Proves: TC-245-15
    def test_an_abbreviated_commit_is_resolved_to_its_full_id(self):
        self.qualifying_log()
        self.plant_package()
        rc, out = self.run_command(self.commit[:7], "--dry-run")
        self.assertEqual(rc, 0, out)
        self.assertIn(f"package {self.ver}: reused", out)
        self.assert_args(self.stub_record(), dry_run=True)


if __name__ == "__main__":
    unittest.main()
