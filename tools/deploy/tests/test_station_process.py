"""tools/deploy/station-process.ps1: the one definition of the station's process list, its Ctrl+C
helper and its task settle, shared by the update, the page check and the test bench.

Each function is dot-sourced from the file (or from a scratch copy for a negative) into a runner
under Stop and strict mode, with every command that reaches the system replaced by a mock
function: Get-CimInstance, Start-Process, Stop-ScheduledTask, Get-ScheduledTask, Start-Sleep.
The runner sets only the caller variables the file names ($Station, $TaskName, $CtrlErrFile).
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.dirname(HERE))
import station_drill  # noqa: E402

PROCESS = os.path.join(ROOT, "tools", "deploy", "station-process.ps1")
CALLERS = ("tools/deploy/live-page-check.ps1", "tools/deploy/station-update/station-update.ps1",
           "tools/test/powershell/station-control.ps1")
DEFINITION = re.compile(r"function (Send-CtrlC|Station-Procs|Settle-Task)\b")
# The update's old name of the process list; written in two parts, so that the search for it
# does not find this test.
OLD_NAME = "Station-" + "Processes"
DEFINE = "function" + " "


def read(path):
    with open(path, encoding="utf-8-sig") as f:
        return f.read()


def scratch(tmp, text, name="station-process.ps1"):
    path = os.path.join(tmp, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return path


def run_ps(runner, tmp, *args, timeout=120):
    path = scratch(tmp, runner, "runner.ps1")
    proc = subprocess.run([station_drill.POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", path,
                           *args], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    return proc.returncode, proc.stdout + proc.stderr


def definitions(texts):
    """[(path, function)] of each definition of the three functions, and each use of the old name."""
    found = []
    for path, text in texts.items():
        found += [(path, m.group(1)) for m in DEFINITION.finditer(text)]
        found += [(path, OLD_NAME)] * text.count(OLD_NAME)
    return found


class OneDefinitionTests(unittest.TestCase):
    # Proves: TC-317-01
    def test_the_three_functions_are_defined_once_in_station_process_ps1(self):
        out = subprocess.run(["git", "-C", ROOT, "grep", "-n", "-E", r"function (Send-CtrlC|Station-Procs|Settle-Task)\b", "--",
                              "tools", "harness"], capture_output=True, text=True).stdout.splitlines()
        self.assertEqual(len(out), 3, out)
        self.assertEqual({line.split(":", 1)[0] for line in out}, {"tools/deploy/station-process.ps1"}, out)
        old = subprocess.run(["git", "-C", ROOT, "grep", "-n", OLD_NAME, "--", "tools"], capture_output=True, text=True)
        self.assertEqual(old.stdout.splitlines(), [], old.stdout)
        # The scan of the negatives, on the files as they are: the same three hits, no copy.
        texts = {p: read(os.path.join(ROOT, *p.split("/"))) for p in CALLERS + ("tools/deploy/station-process.ps1",)}
        self.assertEqual(sorted(definitions(texts)), sorted(("tools/deploy/station-process.ps1", n)
                                                            for n in ("Send-CtrlC", "Station-Procs", "Settle-Task")))
        # Negatives: a copy left in a caller is found.
        for path, added, hit in (("tools/deploy/live-page-check.ps1", DEFINE + "Send-CtrlC([int]$TargetPid) { 0 }\n", "Send-CtrlC"),
                                 ("tools/test/powershell/station-control.ps1", DEFINE + "Settle-Task { }\n", "Settle-Task"),
                                 ("tools/deploy/station-update/station-update.ps1", DEFINE + OLD_NAME + " { @() }\n", OLD_NAME)):
            with self.subTest(path):
                changed = dict(texts, **{path: texts[path] + added})
                self.assertIn((path, hit), definitions(changed))


PROCS_RUNNER = r"""
param([string]$Process, [string]$Station, [string]$Seen)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest
$TaskName = 'task'; $CtrlErrFile = Join-Path $env:TEMP 'unused-ctrl.txt'
function Get-CimInstance { param($ClassName, $Filter)
  Set-Content -LiteralPath $Seen -Value "$ClassName|$Filter"
  $t = Split-Path -Parent $Station
  [pscustomobject]@{ ProcessId = 1; ExecutablePath = "$t\station\a\wstx-rust.exe" }
  [pscustomobject]@{ ProcessId = 2; ExecutablePath = "$($t.ToUpperInvariant())\STATION\b\wstx-rust.exe" }
  [pscustomobject]@{ ProcessId = 3; ExecutablePath = "$t\station-old\c\wstx-rust.exe" }
  [pscustomobject]@{ ProcessId = 4; ExecutablePath = $null } }
. $Process
'IDS ' + ((@(Station-Procs) | ForEach-Object { $_.ProcessId }) -join ',')
"""


class StationProcsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def check(self, process):
        """The process list of a mocked Win32_Process: the station's two entries, by its filter."""
        seen = os.path.join(self.tmp.name, "seen.txt")
        rc, out = run_ps(PROCS_RUNNER, self.tmp.name, "-Process", process, "-Station", os.path.join(self.tmp.name, "station"),
                         "-Seen", seen)
        self.assertEqual(rc, 0, out)
        self.assertIn("IDS 1,2\n", out)
        self.assertEqual(read(seen).strip(), "Win32_Process|Name='wstx-rust.exe'")

    # Proves: TC-317-02
    def test_the_station_processes_are_those_below_the_station_folder(self):
        self.check(PROCESS)
        text = read(PROCESS)
        filtered = "-Filter \"Name='wstx-rust.exe'\""
        for name, old, new in (("prefix without the separator", '"$Station\\"', "$Station"),
                               ("case-sensitive prefix", "OrdinalIgnoreCase", "Ordinal"),
                               ("filter without the name", filtered, "")):
            with self.subTest(name):
                self.assertIn(old, text)
                path = scratch(self.tmp.name, text.replace(old, new), "negative.ps1")
                with self.assertRaises(AssertionError):
                    self.check(path)


# Each case: the helper's exit (rc), the number it writes to its $f file (write, or none), a
# leftover error file before the call (leftover), the event (event, or none: the default).
CTRL_RUNNER = r"""
param([string]$Process, [string]$Station, [string]$Cases)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest
$TaskName = 'task'
$CtrlErrFile = Join-Path (Split-Path -Parent $Station) 'ctrl-test\ctrl.txt'
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $CtrlErrFile))
$global:Mock = $null
function Start-Process { param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru, [switch]$Wait)
  $code = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String([string]$ArgumentList[-1]))
  $global:Mock.code = $code; $global:Mock.window = [string]$WindowStyle; $global:Mock.wait = [bool]$Wait; $global:Mock.file = [string]$FilePath
  $f = if ($code -match '\$f=''([^'']*)''') { $Matches[1] } else { '' }
  $global:Mock.f = $f
  if ($null -ne $global:Mock.write) { [IO.File]::WriteAllText($f, [string]$global:Mock.write) }
  [pscustomobject]@{ ExitCode = [int]$global:Mock.rc } }
. $Process
$results = @()
$list = [IO.File]::ReadAllText($Cases) | ConvertFrom-Json
foreach ($c in $list) {
  $global:Mock = @{ rc = $c.rc; write = $c.write; code = ''; window = ''; wait = $false; file = ''; f = '' }
  if ($c.leftover) { [IO.File]::WriteAllText($CtrlErrFile, '99') }
  $r = [ordered]@{ threw = '' }
  try {
    $s = if ($null -eq $c.event) { Send-CtrlC 4242 } else { Send-CtrlC 4242 $c.event }
    $r.has_rc = [bool]$s.PSObject.Properties['Rc']
    $r.rc = if ($r.has_rc) { $s.Rc } else { $null }
    $r.delivered = $s.Delivered; $r.error = $s.Error
  } catch { $r.threw = $_.Exception.Message }
  $r.code = $global:Mock.code; $r.window = $global:Mock.window; $r.wait = $global:Mock.wait; $r.file = $global:Mock.file
  $r.f = $global:Mock.f; $r.ctrl_file = $CtrlErrFile; $r.left = (Test-Path -LiteralPath $CtrlErrFile)
  $results += [pscustomobject]$r
}
'RESULTS ' + (ConvertTo-Json -InputObject @($results) -Compress -Depth 3)
"""

CTRL_CASES = [{"rc": 3, "write": None, "leftover": True, "event": None},
              {"rc": 3, "write": 6, "leftover": False, "event": None},
              {"rc": 4, "write": 5, "leftover": False, "event": None},
              {"rc": 0, "write": None, "leftover": False, "event": None},
              {"rc": 0, "write": None, "leftover": False, "event": 1}]


class SendCtrlCTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.station = os.path.join(self.tmp.name, "station")
        os.makedirs(os.path.join(self.station, "logs"))

    def tearDown(self):
        self.tmp.cleanup()

    def results(self, process):
        cases = scratch(self.tmp.name, json.dumps(CTRL_CASES), "cases.json")
        rc, out = run_ps(CTRL_RUNNER, self.tmp.name, "-Process", process, "-Station", self.station, "-Cases", cases)
        self.assertEqual(rc, 0, out)
        line = next((line for line in out.splitlines() if line.startswith("RESULTS ")), None)
        self.assertIsNotNone(line, out)
        return json.loads(line[len("RESULTS "):])

    def check(self, process):
        """The helper's result under strict mode with no $stamp, for each scripted exit."""
        r = self.results(process)
        for x in r:
            self.assertEqual(x["threw"], "", x)
            self.assertTrue(x["has_rc"], x)
            self.assertEqual(x["f"], x["ctrl_file"], "the helper's error file is $CtrlErrFile")
            self.assertFalse(x["left"], "the error file is gone afterwards")
            self.assertEqual((x["file"], x["window"], x["wait"]), ("powershell.exe", "Hidden", True), x)
            self.assertNotIn(os.path.join(self.station, "logs").lower(), x["code"].lower())
        self.assertEqual((r[0]["rc"], r[0]["delivered"], r[0]["error"]), (3, False, "AttachConsole error unknown"))
        self.assertIn("[W.C]::Attach(4242)", r[0]["code"])
        self.assertIn("[W.C]::Raise(0)", r[0]["code"])
        self.assertEqual((r[1]["rc"], r[1]["error"]), (3, "AttachConsole error 6"))
        self.assertEqual((r[2]["rc"], r[2]["error"]), (4, "GenerateConsoleCtrlEvent error 5"))
        self.assertEqual((r[3]["rc"], r[3]["delivered"], r[3]["error"]), (0, True, ""))
        self.assertIn("[W.C]::Raise(1)", r[4]["code"])
        self.assertNotIn("[W.C]::Raise(0)", r[4]["code"])

    # Proves: TC-317-03
    def test_the_helper_result_names_the_failed_call_and_its_error(self):
        self.check(PROCESS)
        text = read(PROCESS)
        source = "$errFile = $CtrlErrFile"
        leftover = "  if (Test-Path -LiteralPath $errFile) { Remove-Item -LiteralPath $errFile -Force }\n"
        for name, old, new in (("reads $stamp", source, '$errFile = Join-Path $Station "logs\\update-$stamp-ctrl.txt"'),
                               ("error file under $Station\\logs", source, "$errFile = Join-Path $Station 'logs\\ctrl.txt'"),
                               ("event ignored", "[W.C]::Raise($CtrlEvent)", "[W.C]::Raise(0)"),
                               (".Rc missing", "Rc = $rc; ", ""),
                               ("leftover not removed", leftover, "")):
            with self.subTest(name):
                self.assertEqual(text.count(old), 1, old)
                path = scratch(self.tmp.name, text.replace(old, new), "negative.ps1")
                with self.assertRaises(AssertionError):
                    self.check(path)


# The scheduled task reports Running for the first `running` polls (-1: always). The clock is the
# caller's Now, moved only by Start-Sleep; it stands far after the real time, so a settle that
# reads the real clock instead does not wait at all.
SETTLE_RUNNER = r"""
param([string]$Process, [string]$Cases)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest
$Station = 'unused'; $TaskName = 'WSTX Rust Station HB9BLA'; $CtrlErrFile = 'unused'
$global:T0 = [DateTime]::new(2100, 1, 1, 12, 0, 0, [DateTimeKind]::Utc)
function Now { $global:Clock }
function Start-Sleep { param($Seconds = 0, $Milliseconds = 0)
  $global:Sleeps += [int]([double]$Seconds * 1000 + [double]$Milliseconds); $global:Clock = $global:Clock.AddMilliseconds([double]$Seconds * 1000 + [double]$Milliseconds) }
function Stop-ScheduledTask { param($TaskName, $ErrorAction) $global:Stops++; if ($global:StopFails) { throw 'access denied (mock)' } }
function Get-ScheduledTask { param($TaskName)
  $global:Polls++
  $state = if ($global:Running -lt 0 -or $global:Polls -le $global:Running) { 'Running' } else { 'Ready' }
  [pscustomobject]@{ State = $state } }
. $Process
$results = @()
$list = [IO.File]::ReadAllText($Cases) | ConvertFrom-Json
foreach ($c in $list) {
  $global:Clock = $global:T0; $global:Sleeps = @(); $global:Polls = 0; $global:Stops = 0
  $global:Running = [int]$c.running; $global:StopFails = [bool]$c.stop_fails
  $r = [ordered]@{ threw = ''; out = @() }
  try { $r.out = @(Settle-Task | ForEach-Object { [string]$_ }) } catch { $r.threw = $_.Exception.Message }
  $r.polls = $global:Polls; $r.stops = $global:Stops; $r.sleeps = @($global:Sleeps)
  $r.elapsed_ms = [int]($global:Clock - $global:T0).TotalMilliseconds
  $results += [pscustomobject]$r
}
'RESULTS ' + (ConvertTo-Json -InputObject @($results) -Compress -Depth 3)
"""

SETTLE_CASES = [{"running": 3, "stop_fails": False}, {"running": -1, "stop_fails": False}, {"running": 0, "stop_fails": True}]


class SettleTaskTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def check(self, process):
        cases = scratch(self.tmp.name, json.dumps(SETTLE_CASES), "cases.json")
        rc, out = run_ps(SETTLE_RUNNER, self.tmp.name, "-Process", process, "-Cases", cases, timeout=180)
        self.assertEqual(rc, 0, out)
        line = next((line for line in out.splitlines() if line.startswith("RESULTS ")), None)
        self.assertIsNotNone(line, out)
        stops_at_ready, still_running, stop_fails = json.loads(line[len("RESULTS "):])
        # Running for 3 polls: the fourth reads Ready, then the 800 ms pause.
        self.assertEqual(stops_at_ready["threw"], "", stops_at_ready)
        self.assertEqual((stops_at_ready["stops"], stops_at_ready["polls"]), (1, 4), stops_at_ready)
        self.assertEqual(stops_at_ready["sleeps"], [200, 200, 200, 800], stops_at_ready)
        self.assertEqual(stops_at_ready["out"], [], stops_at_ready)
        # Running throughout: it returns after 10 s and the pause, and does not throw.
        self.assertEqual(still_running["threw"], "", still_running)
        self.assertEqual(still_running["sleeps"][-1], 800, still_running["sleeps"][-3:])
        self.assertTrue(10000 <= still_running["elapsed_ms"] - 800 < 10200, still_running["elapsed_ms"])
        # Stop-ScheduledTask throws: the note, then the wait.
        self.assertEqual(stop_fails["threw"], "", stop_fails)
        self.assertEqual(stop_fails["out"], ["note: Stop-ScheduledTask: access denied (mock)"], stop_fails)
        self.assertGreaterEqual(stop_fails["polls"], 1, stop_fails)
        self.assertEqual(stop_fails["sleeps"], [800], stop_fails)

    # Proves: TC-317-04
    def test_the_settle_waits_for_the_task_at_most_10_s_then_pauses(self):
        self.check(PROCESS)
        text = read(PROCESS)
        pause = "  Start-Sleep -Milliseconds 800\n"
        for name, old, new in (("throws on a running task", pause,
                                pause + "  if ((Get-ScheduledTask -TaskName $TaskName).State -eq 'Running') { throw 'still Running' }\n"),
                               ("no pause", pause, ""),
                               ("its own clock", "$deadline = (Now).AddSeconds(10)", "$deadline = [DateTime]::UtcNow.AddSeconds(10)")):
            with self.subTest(name):
                self.assertEqual(text.count(old), 1, old)
                path = scratch(self.tmp.name, text.replace(old, new), "negative.ps1")
                with self.assertRaises(AssertionError):
                    self.check(path)


class UpdateWithoutTheFileTests(unittest.TestCase):
    """The update loads station-process.ps1 before its first write."""

    def run_without_the_file(self, script):
        with tempfile.TemporaryDirectory() as tmp:
            s = station_drill.Sandbox(os.path.join(tmp, "sandbox"), script)
            os.remove(os.path.join(s.pkg, "deploy", "tools", "deploy", "station-process.ps1"))
            rc, out, sentinels = s.run()
            logs = os.path.join(s.station, "logs")
            return rc, out, sentinels, glob.glob(os.path.join(logs, "update-*.log")), os.path.exists(os.path.join(logs, "update.lock"))

    def check(self, script):
        rc, out, sentinels, logs, lock = self.run_without_the_file(script)
        self.assertNotEqual(rc, 0, out)
        self.assertIn("station-process.ps1", out)
        self.assertEqual(logs, [], out)
        self.assertFalse(lock, out)
        self.assertEqual(sentinels, [], out)
        self.assertEqual([line for line in out.splitlines() if re.match(r"\d\d:\d\d:\d\d ", line)], [], out)

    # Proves: TC-317-07
    def test_a_package_without_station_process_ps1_ends_before_any_step(self):
        self.check(station_drill.SCRIPT)
        # Negative: a script that dot-sources the file after its log is created.
        text = read(station_drill.SCRIPT)
        load = '. "$PSScriptRoot\\..\\station-process.ps1"\n'
        first = 'Step "verify package: $Manifest"\n'
        self.assertEqual((text.count(load), text.count(first)), (1, 1))
        with tempfile.TemporaryDirectory() as tmp:
            late = scratch(tmp, text.replace(load, "").replace(first, first + load), "station-update.ps1")
            with self.assertRaises(AssertionError):
                self.check(late)


if __name__ == "__main__":
    unittest.main()
