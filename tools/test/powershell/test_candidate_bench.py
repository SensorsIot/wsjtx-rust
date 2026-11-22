"""candidate-bench.ps1: the candidate's own build on a scratch simulator profile, never the installed station.

The repository, the station folder, the run folder and the build folder are temporary fakes; the
emulator script is a fake that logs its call. Everything else that reaches the system is a mock
function: git, cargo (which writes the fake build), Start-Process (the lock holder, which in the mock
reports its locks, and the candidate, which in the mock writes the listening line the server prints),
the process table (Get-CimInstance Win32_Process) and taskkill. Nothing is
built, started or ended, and no COM port is opened. bench-hold.ps1 itself is tested for real in
test_bench_hold.py.
"""
import json
import msvcrt
import os
import sys
import tempfile
import unittest

# The one copy of the PowerShell runner is tools/deploy/tests/pwsh.py.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "deploy", "tests"))
import pwsh  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "candidate-bench.ps1")
COMMIT = "c0ffee00" * 5
CREATED = "2026-11-22T10:00:00Z"
STAMP = "2026-11-22T10:00:00.0000000Z"
RADIO = "USB\\VID_10C4&PID_EA60\\IC-7300 03001234 A"


def prelude(log, procs=(), candidate="listens", holder="holds", kill="works"):
    """`procs`: (pid, creation time, executable, command line) of the fake process table. `candidate`:
    "listens", "silent" (runs, no listening line), "gone" (no process after the start) or "unwritable"
    (it runs and the record can no longer be written). `holder`: "holds" (reports its locks) or
    "silent". `kill`: "works" or "fails" (taskkill leaves the process)."""
    rows = "\n".join(f"Add-Proc {pid} {pwsh.ps_quote(created)} {pwsh.ps_quote(exe)} {pwsh.ps_quote(cmd)}"
                     for pid, created, exe, cmd in procs)
    return f"""
$global:Log = {pwsh.ps_quote(log)}
function Note($t) {{ Add-Content -LiteralPath $global:Log -Value $t }}
$global:Procs = New-Object System.Collections.ArrayList
function Add-Proc($id, $created, $exe, $cmd) {{
  [void]$global:Procs.Add([pscustomobject]@{{ProcessId=[uint32]$id; ExecutablePath=$exe; CommandLine=$cmd;
    CreationDate=[DateTime]::Parse($created, [Globalization.CultureInfo]::InvariantCulture, 'AdjustToUniversal,AssumeUniversal').ToLocalTime()}}) }}
{rows}
function Get-CimInstance {{ param($ClassName, $Filter)
  if ($Filter -match '^ProcessId=(\\d+)$') {{ $id = [int]$Matches[1]; return @($global:Procs | Where-Object {{ $_.ProcessId -eq $id }}) }}
  throw "unexpected query $ClassName $Filter" }}
function git {{ Note "git $($args -join ' ')"; $global:LASTEXITCODE = 0; '{COMMIT}' }}
function cargo {{
  Note "cargo $($args -join ' ') | target $env:CARGO_TARGET_DIR"
  $exe = Join-Path $env:CARGO_TARGET_DIR 'release\\wstx-rust.exe'
  [void][IO.Directory]::CreateDirectory((Split-Path $exe)); [IO.File]::WriteAllText($exe, 'fake')
  $global:LASTEXITCODE = 0 }}
function Start-Process {{ param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru, $RedirectStandardOutput, $RedirectStandardError)
  if ($FilePath -eq 'powershell.exe') {{
    $i = [array]::IndexOf($ArgumentList, '-Record'); $record = $ArgumentList[$i + 1].Trim('"')
    $j = [array]::IndexOf($ArgumentList, '-KeepPort'); $keep = $ArgumentList[$j + 1]
    $k = [array]::IndexOf($ArgumentList, '-LockRoot'); $root = $ArgumentList[$k + 1].Trim('"')
    Note "hold every port but COM$keep | root $root"
    Add-Proc 6900 '2026-11-22T10:59:00Z' 'C:\\WINDOWS\\powershell.exe' ('powershell.exe -File bench-hold.ps1 ' + ($ArgumentList -join ' '))
    if ('{holder}' -eq 'holds') {{ [IO.File]::WriteAllText("$record.holding", '[]') }}
    return [pscustomobject]@{{Id=6900}} }}
  $profileDir = $ArgumentList[1].Trim('"')
  $bind = ([IO.File]::ReadAllText((Join-Path $profileDir 'profile.json')) | ConvertFrom-Json).endpoint.bind
  $wstx = @(Get-ChildItem Env: | Where-Object {{ $_.Name -like 'WSTX_*' -and $_.Name -ne 'WSTX_SNTP_SERVERS' }}).Count
  $held = Test-Path -LiteralPath ((Join-Path (Split-Path $profileDir) 'bench.json') + '.holding')
  Note "start $FilePath $($ArgumentList -join ' ') | window $WindowStyle | appdata $env:LOCALAPPDATA | other WSTX $wstx | locks held $held"
  if ('{candidate}' -ne 'gone') {{ Add-Proc 7000 '2026-11-22T11:00:00Z' $FilePath 'wstx-rust.exe' }}
  if ('{candidate}' -eq 'listens') {{ [IO.File]::WriteAllText($RedirectStandardOutput, "WSTX listening http://$bind`n") }}
  if ('{candidate}' -eq 'unwritable') {{   # the record becomes a folder: no write of it succeeds any more
    $rec = Join-Path (Split-Path $profileDir) 'bench.json'; Remove-Item -LiteralPath $rec -Force
    [void][IO.Directory]::CreateDirectory($rec) }}
  [pscustomobject]@{{Id=7000}} }}
if ('{kill}' -ne 'native') {{ function global:taskkill {{
  Note "taskkill $($args -join ' ')"
  $ids = @(for ($i = 0; $i -lt $args.Count; $i++) {{ if ($args[$i] -eq '/PID') {{ [int]$args[$i + 1] }} }})
  if ('{kill}' -eq 'works') {{ foreach ($id in $ids) {{ $global:Procs.Remove(($global:Procs | Where-Object {{ $_.ProcessId -eq $id }})) }} }}
  $global:LASTEXITCODE = if ('{kill}' -eq 'works') {{ 0 }} else {{ 128 }} }} }}
function Start-Sleep {{ }}
"""


class CandidateBenchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.repo, self.live, self.build = os.path.join(t, "repo"), os.path.join(t, "live"), os.path.join(t, "build")
        self.station = os.path.join(t, "station")
        self.worktree = os.path.join(self.repo, ".git", "harness-parallel", "worktrees", "issue-7-g2")
        os.makedirs(self.worktree)
        self.state({"7": {"path": self.worktree}})
        self.sim = os.path.join(self.station, "profiles", "SIM-IC7300")
        self.profile("icom7300://COM4?baud=115200&radio=94&controller=e0")
        self.write(os.path.join(self.sim, "pskr.json"), {"schema_version": 2, "profile_id": "p-sim", "enabled": True, "use": True})
        self.write(os.path.join(self.station, "station-running.json"), {"profile": os.path.join(self.station, "profiles", "ic7300")})
        self.log = os.path.join(t, "system.log")
        self.emulator = os.path.join(t, "emulator.ps1")
        with open(self.emulator, "w", encoding="utf-8") as f:
            f.write(f"Add-Content -LiteralPath {pwsh.ps_quote(self.log)} -Value ('emulator ' + ($args -join ' '))\n"
                    "Write-Output 'EMULATOR OK'\nexit 0\n")
        self.exe = os.path.join(self.build, "issue-7-bench", "release", "wstx-rust.exe")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, value):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(value, f)

    def read(self, path):
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f)

    def profile(self, cat):
        self.write(os.path.join(self.sim, "profile.json"), {
            "schema_version": 1, "profile_id": "p-sim", "endpoint": {"bind": "192.168.0.37:18081", "origin": "https://192.168.0.37:18081"},
            "control": {"mode": "cat", "endpoint": cat, "ptt": "cat"}})

    def state(self, issues):
        self.write(os.path.join(self.repo, ".git", "harness-parallel", "state.json"), {"issues": issues})

    def run_tool(self, *args, procs=(), env=None, **mode):
        return pwsh.run(TOOL, [*args, "-Repo", self.repo, "-Live", self.live, "-BuildRoot", self.build,
                               "-Station", self.station, "-ReadySeconds", "2", "-EmulatorScript", self.emulator],
                        prelude(self.log, procs, **mode), env={"WSTX_TOKEN": "x" * 40, **(env or {})})

    def native_taskkill(self):
        """A native taskkill on PATH, as the real one answers: for the candidate's pid 7000, which is gone,
        an error line on stderr and exit 128; for any other pid nothing and exit 0. Each call is logged."""
        stub = os.path.join(self.tmp.name, "bin")
        os.makedirs(stub)
        with open(os.path.join(stub, "taskkill.cmd"), "w", encoding="ascii") as f:
            f.write("@echo off\r\n"
                    f'>>"{self.log}" echo taskkill %*\r\n'
                    'echo %* | findstr /C:"/PID 7000" >nul && (echo ERROR: The process "7000" not found. 1>&2 & exit /b 128)\r\n'
                    "exit /b 0\r\n")
        return {"PATH": stub + os.pathsep + os.environ["PATH"]}

    def system(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log, encoding="utf-8") as f:
            return f.read().splitlines()

    def bench(self, n=7):
        return os.path.join(self.live, str(n), "bench")

    def record(self, n=7, **fields):
        value = {"issue": n, "pid": 7000, "created": STAMP, "url": "http://127.0.0.1:5", "commit": COMMIT, "emulator": True,
                 "holder": 6900, "holder_created": STAMP, **fields}
        self.write(os.path.join(self.bench(n), "bench.json"), value)

    def running(self, n=7):
        return [(7000, CREATED, os.path.join(self.build, f"issue-{n}-bench", "release", "wstx-rust.exe"), "wstx-rust.exe"),
                (6900, CREATED, "C:\\WINDOWS\\powershell.exe", "powershell.exe -File bench-hold.ps1 -Record x")]

    # Accepted

    def test_start_holds_every_port_but_com4_then_runs_the_candidates_own_build(self):
        rc, out = self.run_tool("-Start", "-Issue", "7")
        self.assertEqual(rc, 0, out)
        record = self.read(os.path.join(self.bench(), "bench.json"))
        self.assertRegex(record["url"], r"^http://127\.0\.0\.1:\d+$")
        self.assertIn(f"BENCH STARTED {record['url']} {COMMIT}", out)
        scratch, appdata = os.path.join(self.bench(), "profile"), os.path.join(self.bench(), "appdata")
        self.assertEqual(self.system()[1:], [
            f"cargo build --release --locked --manifest-path {os.path.join(self.worktree, 'Cargo.toml')} "
            f"| target {os.path.join(self.build, 'issue-7-bench')}",
            f"hold every port but COM4 | root {appdata}",  # every port Windows knows but the simulator's, in the candidate's data
            "emulator -Start",
            f'start {self.exe} --profile "{scratch}" | window Hidden | appdata {appdata} | other WSTX 0 | locks held True'])
        self.assertEqual((record["exe"], record["commit"], record["pid"], record["holder"], record["emulator"]),
                         (self.exe, COMMIT, 7000, 6900, True))
        doc = self.read(os.path.join(scratch, "profile.json"))
        self.assertEqual(doc["endpoint"]["bind"], record["url"][len("http://"):])
        self.assertEqual(self.read(os.path.join(scratch, "pskr.json"))["enabled"], False)
        self.assertEqual(self.read(os.path.join(scratch, "udp.json"))["targets"], [])
        self.assertEqual(self.read(os.path.join(scratch, "radio-discovery.json"))["at_start"], False)
        self.assertEqual(self.read(os.path.join(self.sim, "profile.json"))["endpoint"]["bind"], "192.168.0.37:18081")
        self.assertEqual(self.read(os.path.join(self.sim, "pskr.json"))["enabled"], True)

    def test_status_and_stop_act_only_on_the_benchs_own_build(self):
        self.record()
        rc, out = self.run_tool("-Status", "-Issue", "7", procs=self.running())
        self.assertIn("BENCH RUNNING http://127.0.0.1:5", out)
        rc, out = self.run_tool("-Stop", "-Issue", "7", procs=self.running())
        self.assertEqual(rc, 0, out)
        self.assertIn("BENCH STOPPED 7000", out)
        self.assertEqual(self.system(), ["taskkill /F /T /PID 7000", "emulator -Stop -Bench", "taskkill /F /T /PID 6900"])
        self.assertFalse(os.path.exists(os.path.join(self.bench(), "bench.json")))

    def test_a_record_naming_another_program_or_a_reused_pid_kills_nothing(self):
        for procs in ([(7000, CREATED, "C:\\Program Files\\Other\\other.exe", "other.exe")],     # the tester's record names another pid
                      [(7000, "2026-11-22T12:00:00Z", self.exe, "wstx-rust.exe")]):            # the pid was reused
            with self.subTest(procs=procs):
                self.record(holder=None, emulator=False)
                if os.path.exists(self.log):
                    os.remove(self.log)
                rc, out = self.run_tool("-Status", "-Issue", "7", procs=procs)
                self.assertIn("BENCH NOT-RUNNING", out)
                rc, out = self.run_tool("-Stop", "-Issue", "7", procs=procs)
                self.assertEqual(rc, 0, out)
                self.assertNotIn("taskkill", "\n".join(self.system()))

    def test_stop_without_a_record_does_nothing(self):
        rc, out = self.run_tool("-Stop", "-Issue", "7")
        self.assertEqual(rc, 0, out)
        self.assertIn("BENCH NONE", out)
        self.assertEqual(self.system(), [])

    # Refused (negative tests): nothing built, nothing held, nothing started

    def assertRefused(self, result, why):
        rc, out = result
        self.assertEqual(rc, 2, out)
        self.assertIn("BENCH ERROR", out)
        self.assertIn(why, out)
        self.assertFalse([line for line in self.system() if line.startswith(("cargo", "start", "hold", "emulator"))])

    def test_wrong_arguments_are_refused(self):
        for args in (("-Start", "-Issue", "0"), ("-Start", "-Issue", "-3"), ("-Start",), ("-Start", "-Stop", "-Issue", "7"),
                     ("-Issue", "7"), ("-Start", "-Issue", "7", "-Extra"), ("-Start", "-Issue", "7", "more")):
            with self.subTest(args=args):
                rc, out = self.run_tool(*args)
                self.assertNotEqual(rc, 0, out)
                self.assertFalse([line for line in self.system() if line.startswith(("cargo", "start", "hold", "emulator"))])

    def test_a_bench_is_refused_while_the_installed_station_runs_the_simulator_profile(self):
        self.write(os.path.join(self.station, "station-running.json"), {"profile": self.sim})
        self.assertRefused(self.run_tool("-Start", "-Issue", "7"), "the installed station runs the simulator profile")

    def test_one_bench_at_a_time(self):
        self.record(9)
        self.assertRefused(self.run_tool("-Start", "-Issue", "7", procs=self.running(9)), "the bench of #9 runs")

    def test_a_second_start_beside_a_running_start_is_refused(self):
        os.makedirs(self.live, exist_ok=True)
        with open(os.path.join(self.live, "candidate-bench.lock"), "w") as held:
            msvcrt.locking(held.fileno(), msvcrt.LK_NBLCK, 1)
            try:
                self.assertRefused(self.run_tool("-Start", "-Issue", "7"), "another candidate-bench.ps1 -Start is running")
            finally:
                held.seek(0)
                msvcrt.locking(held.fileno(), msvcrt.LK_UNLCK, 1)

    def test_a_simulator_profile_naming_the_real_radio_or_another_port_is_refused(self):
        self.profile("icom7300://COM3?baud=115200")
        self.assertRefused(self.run_tool("-Start", "-Issue", "7"), "names COM3, the real radio")
        self.profile("icom7300://COM7?baud=115200")
        self.assertRefused(self.run_tool("-Start", "-Issue", "7"), "is 'icom7300://COM7?baud=115200', not COM4")

    def test_a_missing_simulator_profile_is_refused(self):
        os.remove(os.path.join(self.sim, "profile.json"))
        self.assertRefused(self.run_tool("-Start", "-Issue", "7"), "no simulator profile")

    def test_only_the_issues_own_worktree_is_built(self):
        other = os.path.join(self.repo, "elsewhere")
        os.makedirs(other)
        self.state({"7": {"path": other}})
        self.assertRefused(self.run_tool("-Start", "-Issue", "7"), "is not its own issue worktree")
        named8 = os.path.join(self.repo, ".git", "harness-parallel", "worktrees", "issue-8")
        os.makedirs(named8)
        self.state({"7": {"path": named8}})
        self.assertRefused(self.run_tool("-Start", "-Issue", "7"), "is not its own issue worktree")
        self.state({"8": {"path": self.worktree}})
        self.assertRefused(self.run_tool("-Start", "-Issue", "7"), "has no workspace record")

    # A start that fails ends what it started

    def test_no_candidate_starts_while_the_locks_are_not_held(self):
        rc, out = self.run_tool("-Start", "-Issue", "7", holder="silent")
        self.assertEqual(rc, 2, out)
        self.assertIn("the radio lock holder did not hold the locks", out)
        self.assertFalse([line for line in self.system() if line.startswith(("start", "emulator"))])
        self.assertIn("taskkill /F /T /PID 6900", self.system())
        self.assertFalse(os.path.exists(os.path.join(self.bench(), "bench.json")))

    def test_a_candidate_that_does_not_listen_or_exits_is_ended_and_unrecorded(self):
        for candidate, why in (("silent", "did not listen"), ("gone", "the candidate exited at once")):
            with self.subTest(candidate=candidate):
                if os.path.exists(self.log):
                    os.remove(self.log)
                rc, out = self.run_tool("-Start", "-Issue", "7", candidate=candidate)
                self.assertEqual(rc, 2, out)
                self.assertIn(why, out)
                system = self.system()
                if candidate == "silent":                   # a candidate already gone needs no taskkill
                    self.assertIn("taskkill /F /T /PID 7000", system)
                else:
                    self.assertNotIn("taskkill /F /T /PID 7000", system)
                self.assertIn("emulator -Stop -Bench", system)
                self.assertIn("taskkill /F /T /PID 6900", system)
                self.assertFalse(os.path.exists(os.path.join(self.bench(), "bench.json")))

    def test_a_failed_start_ends_the_candidate_it_started_by_its_own_pid(self):
        # The record can no longer be written after the candidate started, so it does not name the
        # candidate: the start ends it by the pid it got from the start.
        rc, out = self.run_tool("-Start", "-Issue", "7", candidate="unwritable")
        self.assertEqual(rc, 2, out)
        self.assertIn("BENCH ERROR the bench did not start", out)
        self.assertIn("taskkill /F /T /PID 7000", self.system())

    def test_a_candidate_gone_at_once_is_cleaned_up_with_the_real_taskkill(self):
        # The real taskkill writes to stderr and exits non-zero for a process that is gone; under Windows
        # PowerShell that output must never end the cleanup: the start still ends the emulator and the
        # holder, removes the record and reports BENCH ERROR with exit 2.
        rc, out = self.run_tool("-Start", "-Issue", "7", candidate="gone", kill="native", env=self.native_taskkill())
        self.assertEqual(rc, 2, out)
        self.assertIn("BENCH ERROR the bench did not start: the candidate exited at once", out)
        system = self.system()
        self.assertIn("emulator -Stop -Bench", system)
        self.assertTrue(any(line.startswith("taskkill") and "6900" in line for line in system), system)
        self.assertFalse(os.path.exists(os.path.join(self.bench(), "bench.json")))

    def test_a_failed_taskkill_is_an_error_not_a_stop(self):
        self.record()
        rc, out = self.run_tool("-Stop", "-Issue", "7", procs=self.running(), kill="fails")
        self.assertEqual(rc, 2, out)
        self.assertIn("taskkill of 7000 failed", out)
        self.assertTrue(os.path.exists(os.path.join(self.bench(), "bench.json")))


if __name__ == "__main__":
    unittest.main()
