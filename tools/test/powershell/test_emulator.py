"""emulator.ps1: starts, stops and reports the IC-7300 emulator on COM5.

The emulator folder and the record folder are temporary fakes. Everything that reaches the system
is a mock function: the process table (Get-CimInstance Win32_Process), the process start
(Invoke-CimMethod Win32_Process Create, which in the mock also writes the emulator's run folder as
simulator.py does) and taskkill. No process is started or ended, no COM port is opened.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

# The one copy of the PowerShell runner is tools/deploy/tests/pwsh.py.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "deploy", "tests"))
import pwsh  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "emulator.ps1")
T0 = "2026-11-19T10:00:00Z"
T1 = "2026-11-19T10:00:01Z"
STAMP0 = "2026-11-19T10:00:00.0000000Z"
STAMP1 = "2026-11-19T10:00:01.0000000Z"


def prelude(log, procs, emulator="ready"):
    """`procs`: (pid, parent pid, creation time, command line) of the fake process table.
    `emulator`: what the started process does: "ready" (its launcher 5000 and interpreter 5001 run
    and a new run folder starts the transport on COM5), "error" (the run folder says
    transport_error), "silent" (it runs, no run folder), "gone" (no process after the start),
    "exits" (it runs once, then is gone before any run folder)."""
    rows = "\n".join(f"Add-Proc {pid} {parent} {pwsh.ps_quote(created)} {pwsh.ps_quote(cmd)}"
                     for pid, parent, created, cmd in procs)
    return f"""
$global:Log = {pwsh.ps_quote(log)}
function Note($t) {{ Add-Content -LiteralPath $global:Log -Value $t }}
$global:Procs = New-Object System.Collections.ArrayList
function Add-Proc($id, $parent, $created, $cmd) {{
  [void]$global:Procs.Add([pscustomobject]@{{ProcessId=[uint32]$id; ParentProcessId=[uint32]$parent;
    CreationDate=[DateTime]::Parse($created, [Globalization.CultureInfo]::InvariantCulture, 'AdjustToUniversal,AssumeUniversal').ToLocalTime();
    CommandLine=$cmd}}) }}
{rows}
$global:Mode = {pwsh.ps_quote(emulator)}
$global:Reads = 0
function Get-CimInstance {{ param($ClassName, $Filter)
  if ($ClassName -ne 'Win32_Process') {{ throw "unexpected class $ClassName" }}
  if ($Filter -match '^ProcessId=(\\d+)$') {{
    if ($global:Mode -eq 'exits' -and [int]$Matches[1] -eq 5000) {{ $global:Reads++; if ($global:Reads -gt 1) {{ return }} }}
    $id = [int]$Matches[1]; return @($global:Procs | Where-Object {{ $_.ProcessId -eq $id }}) }}
  if ($Filter -match '^ParentProcessId=(\\d+)$') {{ $id = [int]$Matches[1]; return @($global:Procs | Where-Object {{ $_.ParentProcessId -eq $id }}) }}
  if ($Filter -eq "CommandLine like '%simulator.py%'") {{ return @($global:Procs | Where-Object {{ $_.CommandLine -like '*simulator.py*' }}) }}
  throw "unexpected filter $Filter" }}
function Invoke-CimMethod {{ param($ClassName, $MethodName, $Arguments)
  Note "create $($Arguments.CommandLine) | in $($Arguments.CurrentDirectory) | window $($Arguments.ProcessStartupInformation.CimInstanceProperties['ShowWindow'].Value)"
  if ($global:Mode -ne 'gone') {{
    Add-Proc 5000 900 '2026-11-19T11:00:00Z' $Arguments.CommandLine
    Add-Proc 5001 5000 '2026-11-19T11:00:01Z' ($Arguments.CommandLine -replace '^"[^"]+"', '"C:\\Python312\\python.exe"')
  }}
  $run = Join-Path $Arguments.CurrentDirectory 'artifacts\\run-new'
  if ($global:Mode -in @('ready', 'error')) {{
    [void][IO.Directory]::CreateDirectory($run)
    $kind = if ($global:Mode -eq 'ready') {{ '{{"sequence": 0, "kind": "transport_start", "transport": {{"run_id": "run-new", "kind": "serial", "endpoint": "COM5"}}}}' }}
            else {{ '{{"sequence": 0, "kind": "transport_error", "error": "could not open port COM5"}}' }}
    [IO.File]::WriteAllText((Join-Path $run 'events.jsonl'), $kind + "`n")
  }}
  [pscustomobject]@{{ReturnValue=0; ProcessId=5000}} }}
function taskkill {{
  Note "taskkill $($args -join ' ')"
  $ids = @(for ($i = 0; $i -lt $args.Count; $i++) {{ if ($args[$i] -eq '/PID') {{ [int]$args[$i + 1] }} }})
  if ($env:FAKE_KILL -ne 'fails') {{ foreach ($id in $ids) {{ $global:Procs.Remove(($global:Procs | Where-Object {{ $_.ProcessId -eq $id }})) }} }}
  $global:LASTEXITCODE = 0 }}
"""


class EmulatorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.emulator = os.path.join(self.tmp.name, "IC-7300 simulator")
        for rel in (os.path.join(".venv", "Scripts", "python.exe"), "simulator.py"):
            path = os.path.join(self.emulator, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w").close()
        self.state = os.path.join(self.tmp.name, "harness-parallel", "radio")
        self.log = os.path.join(self.tmp.name, "system.log")
        self.command = (f'"{self.emulator}\\.venv\\Scripts\\python.exe" "{self.emulator}\\simulator.py" '
                        "--serial COM5 --baud 115200")

    def tearDown(self):
        self.tmp.cleanup()

    def run_tool(self, *args, procs=(), emulator="ready", env=None):
        return pwsh.run(TOOL, [*args, "-Emulator", self.emulator, "-StateDir", self.state, "-ReadySeconds", "2"],
                        prelude(self.log, procs, emulator), env=env)

    def system(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log, encoding="utf-8") as f:
            return f.read().splitlines()

    def record_path(self):
        return os.path.join(self.state, "emulator.json")

    def record(self):
        with open(self.record_path(), encoding="utf-8") as f:
            return json.load(f)

    def write_record(self, pid=5000, created=STAMP0, command=None):
        os.makedirs(self.state, exist_ok=True)
        with open(self.record_path(), "w", encoding="utf-8") as f:
            json.dump({"pid": pid, "created": created, "command": command or self.command, "run": "run-1"}, f)

    def ours(self):
        """The recorded emulator as it runs: the venv launcher, its interpreter and its console."""
        return [(5000, 900, T0, self.command),
                (5001, 5000, T1, self.command.replace(f"{self.emulator}\\.venv\\Scripts\\python.exe", "C:\\Python312\\python.exe")),
                (5002, 5000, T1, "\\??\\C:\\WINDOWS\\system32\\conhost.exe 0x4")]

    def files(self):
        out = []
        for top, _, names in os.walk(self.tmp.name):
            for name in names:
                path = os.path.join(top, name)
                with open(path, "rb") as f:
                    out.append((os.path.relpath(path, self.tmp.name), f.read()))
        return sorted(out)

    # Accepted

    def test_start_runs_the_emulator_hidden_on_com5_and_records_it(self):
        rc, out = self.run_tool("-Start")
        self.assertEqual(rc, 0, out)
        self.assertIn("EMULATOR STARTED 5000 on COM5 at 115200 baud, run run-new", out)
        self.assertEqual(self.system(), [f"create {self.command} | in {self.emulator} | window 0"])
        self.assertEqual(self.record(), {"pid": 5000, "created": "2026-11-19T11:00:00.0000000Z",
                                         "command": self.command, "run": "run-new"})

    def test_start_is_not_blocked_by_an_emulator_on_another_port_or_a_stale_record(self):
        cases = {
            "an emulator on another port": ([(7000, 1, T0, self.command.replace("COM5", "COM6")),
                                             (7001, 1, T0, "python simulator.py --serial COM50")], None),
            "a record whose process is gone": ([], 4000),
            "a record whose pid runs another program": ([(4000, 1, T0, "notepad.exe")], 4000),
        }
        for label, (procs, recorded) in cases.items():
            with self.subTest(label):
                if os.path.exists(self.record_path()):
                    os.unlink(self.record_path())
                if recorded:
                    self.write_record(pid=recorded)
                rc, out = self.run_tool("-Start", procs=procs)
                self.assertEqual(rc, 0, out)
                self.assertIn("EMULATOR STARTED 5000", out)
                self.assertEqual((self.record()["pid"], self.record()["run"]), (5000, "run-new"))
                shutil.rmtree(os.path.join(self.emulator, "artifacts"))

    def test_stop_ends_the_recorded_tree_and_removes_the_record(self):
        self.write_record()
        rc, out = self.run_tool("-Stop", procs=self.ours())
        self.assertEqual(rc, 0, out)
        self.assertIn("EMULATOR STOPPED 5000", out)
        self.assertEqual(self.system(), ["taskkill /F /PID 5000 /PID 5001 /PID 5002"])
        self.assertFalse(os.path.exists(self.record_path()))

    def test_status_reports_the_recorded_emulator(self):
        self.write_record()
        rc, out = self.run_tool("-Status", procs=self.ours())
        self.assertEqual(rc, 0, out)
        self.assertIn(f"EMULATOR RUNNING 5000 since {STAMP0}, run run-1: {self.command}", out)
        rc, out = self.run_tool("-Status", procs=[])
        self.assertEqual(rc, 0, out)
        self.assertIn("EMULATOR NOT-RUNNING the record names process 5000, which is gone", out)
        os.unlink(self.record_path())
        rc, out = self.run_tool("-Status", procs=[(7000, 1, T0, "python simulator.py --serial COM5 --baud 115200")])
        self.assertEqual(rc, 0, out)
        self.assertIn("EMULATOR NOT-RUNNING no record at", out)
        self.assertIn("another process runs the emulator on COM5, not touched: 7000", out)
        self.assertEqual(self.system(), [])
        self.assertFalse(os.path.exists(self.record_path()))

    def test_the_defaults_are_the_shared_record_and_the_emulator_project(self):
        rc, out = pwsh.run(TOOL, ["-Status"], prelude(self.log, []))
        self.assertEqual(rc, 0, out)
        common = subprocess.run(["git", "-C", HERE, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                capture_output=True, text=True, check=True).stdout.strip()
        expected = os.path.normcase(os.path.normpath(os.path.join(common, "harness-parallel", "radio", "emulator.json")))
        shown = next(line for line in out.splitlines() if line.strip().startswith("record "))
        self.assertEqual(os.path.normcase(os.path.normpath(shown.strip()[len("record "):])), expected)
        rc, out = pwsh.run(TOOL, ["-Start", "-DryRun", "-StateDir", self.state], prelude(self.log, []))
        self.assertIn(rc, (0, 2), out)   # 2 where that folder is not installed
        self.assertIn("D:\\Github\\IC-7300 simulator\\", out)
        self.assertEqual((self.system(), os.path.exists(self.state)), ([], False))

    # Negative: a second start

    def test_a_start_while_a_process_runs_the_emulator_on_com5_starts_nothing(self):
        for cmd in (self.command,
                    '"./.venv/Scripts/python.exe" simulator.py --serial COM5 --baud 115200',
                    "python simulator.py --baud 115200 --serial=COM5",
                    '"C:\\Program Files\\Git\\bin\\bash.exe" -c "tail -f /dev/null | ./.venv/Scripts/python.exe simulator.py --serial com5"'):
            with self.subTest(cmd):
                rc, out = self.run_tool("-Start", procs=[(7000, 1, T0, cmd)])
                self.assertEqual(rc, 2, out)
                self.assertIn("a process already runs the emulator on COM5 (7000", out)
                self.assertEqual(self.system(), [])
                self.assertFalse(os.path.exists(self.record_path()))

    def test_a_start_while_the_recorded_emulator_runs_starts_nothing(self):
        self.write_record()
        rc, out = self.run_tool("-Start", procs=self.ours())
        self.assertEqual(rc, 2, out)
        self.assertIn("the recorded emulator still runs (process 5000", out)
        self.assertEqual(self.system(), [])
        self.assertEqual(self.record()["run"], "run-1")

    def test_a_start_while_another_start_or_stop_runs_starts_nothing(self):
        os.makedirs(self.state)
        with open(os.path.join(self.state, "emulator.lock"), "w"):
            rc, out = self.run_tool("-Start")
        self.assertEqual(rc, 2, out)
        self.assertIn("another emulator.ps1 -Start or -Stop is running", out)
        self.assertEqual(self.system(), [])
        self.assertFalse(os.path.exists(self.record_path()))

    # Negative: a start that does not come up leaves nothing behind

    def test_a_start_that_does_not_come_up_ends_what_it_started(self):
        cases = {
            "error": ("could not open COM5", ["taskkill /F /PID 5000 /PID 5001"]),
            "silent": ("within 2 s", ["taskkill /F /PID 5000 /PID 5001"]),
            "exits": ("exited before it started the transport", []),
            "gone": ("exited at once", []),
        }
        for mode, (why, kills) in cases.items():
            with self.subTest(mode):
                if os.path.exists(self.log):
                    os.unlink(self.log)
                rc, out = self.run_tool("-Start", emulator=mode)
                self.assertEqual(rc, 2, out)
                self.assertIn(why, out)
                self.assertEqual(self.system()[1:], kills, out)
                self.assertFalse(os.path.exists(self.record_path()))
                shutil.rmtree(os.path.join(self.emulator, "artifacts"), ignore_errors=True)

    def test_an_old_run_folder_does_not_count_as_started(self):
        old = os.path.join(self.emulator, "artifacts", "run-old")
        os.makedirs(old)
        with open(os.path.join(old, "events.jsonl"), "w", encoding="utf-8") as f:
            f.write('{"sequence": 0, "kind": "transport_start", "transport": {"endpoint": "COM5"}}\n')
        rc, out = self.run_tool("-Start", emulator="silent")
        self.assertEqual(rc, 2, out)
        self.assertIn("no new run folder started the transport on COM5", out)
        self.assertFalse(os.path.exists(self.record_path()))

    # Negative: a stop of a process it did not start

    def test_a_stop_whose_recorded_pid_runs_another_program_ends_nothing(self):
        cases = {
            "another program": [(5000, 900, T0, "notepad.exe")],
            "another emulator started later on that pid": [(5000, 900, T1, self.command)],
        }
        for label, procs in cases.items():
            with self.subTest(label):
                self.write_record()
                rc, out = self.run_tool("-Stop", procs=procs)
                self.assertEqual(rc, 0, out)
                self.assertIn("EMULATOR NONE the recorded process 5000 is gone or runs another program now: nothing stopped", out)
                self.assertEqual(self.system(), [])
                self.assertFalse(os.path.exists(self.record_path()))

    def test_a_stop_without_a_record_ends_nothing(self):
        rc, out = self.run_tool("-Stop", procs=[(7000, 1, T0, '"./.venv/Scripts/python.exe" simulator.py --serial COM5 --baud 115200')])
        self.assertEqual(rc, 0, out)
        self.assertIn("EMULATOR NONE no record at", out)
        self.assertIn("another process runs the emulator on COM5, not touched: 7000", out)
        self.assertEqual(self.system(), [])

    def test_a_stop_ends_no_older_orphan_of_a_reused_parent_pid(self):
        self.write_record()
        procs = self.ours() + [(6000, 5000, "2026-11-19T09:00:00Z", "orphan.exe")]
        rc, out = self.run_tool("-Stop", procs=procs)
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.system(), ["taskkill /F /PID 5000 /PID 5001 /PID 5002"])

    def test_a_stop_that_leaves_a_process_keeps_the_record(self):
        self.write_record()
        rc, out = self.run_tool("-Stop", procs=self.ours(), env={"FAKE_KILL": "fails"})
        self.assertEqual(rc, 2, out)
        self.assertIn("still run after taskkill", out)
        self.assertNotIn("EMULATOR STOPPED", out)
        self.assertEqual(self.record()["pid"], 5000)

    # Negative: arguments

    def test_anything_but_exactly_one_of_start_stop_status_is_refused(self):
        for args in ((), ("-DryRun",), ("-Start", "-Stop"), ("-Start", "-Status"), ("-Stop", "-Status"),
                     ("-Start", "-Stop", "-Status"), ("-Status", "-DryRun"), ("-Bogus",), ("-Start", "-Bogus"),
                     ("-Start", "extra"), ("-Start", "-Verbose"), ("-Start:$false",), ("-To", "back")):
            with self.subTest(args):
                rc, out = self.run_tool(*args, procs=self.ours())
                self.assertEqual(rc, 2, out)
                self.assertIn("EMULATOR ERROR need exactly one of -Start, -Stop, -Status", out)
                self.assertEqual(self.system(), [])
                self.assertFalse(os.path.exists(self.state))

    # Negative: -DryRun

    def test_dry_run_prints_the_steps_and_changes_nothing(self):
        before = self.files()
        rc, out = self.run_tool("-Start", "-DryRun", emulator="ready")
        self.assertEqual(rc, 0, out)
        for step in ("would: start", "would: write the record", "would: wait up to", "EMULATOR DRY-RUN -Start"):
            self.assertIn(step, out)
        self.assertEqual((self.files(), self.system()), (before, []))
        self.write_record()
        before = self.files()
        rc, out = self.run_tool("-Stop", "-DryRun", procs=self.ours())
        self.assertEqual(rc, 0, out)
        for step in ("would: end process 5000 and its descendants", "would: remove the record", "EMULATOR DRY-RUN -Stop"):
            self.assertIn(step, out)
        self.assertEqual((self.files(), self.system()), (before, []))

    def test_the_script_opens_no_port_and_writes_only_its_record(self):
        with open(TOOL, encoding="utf-8") as f:
            text = f.read()
        for word in ("SerialPort", "Set-Content", "Stop-Process", "Start-Process"):
            self.assertNotIn(word, text)
        for line in text.splitlines():
            if "WriteAllText" in line or "Remove-Item" in line:
                self.assertIn("Record-Path", line, line)


if __name__ == "__main__":
    unittest.main()
