"""station-update.ps1 after the switch: probe, live page check, return, launcher and install record.

TC-171-03 (return and lock), TC-171-04 (install record) and the launcher write of TC-171-02 (g).
The station is simulated by mocks that let the stop and the start succeed: the scheduled task,
the station process, its receipt, the network, git, GitHub, cr_state.py and the two checks the
deploy starts (station-probe.ps1 and live-page-check.ps1, as powershell.exe). Each mock writes
what reached it to a log, with the holder of update.lock at that moment, so the order of the
steps and the lock are the oracle. The package and the pins are the drill's sandbox. The
Ctrl+C helper and the station's GET /transmit can also be scripted (FlowCase.deploy); the stop
path's own tests are in test_deploy_stop.py.
"""
import glob
import hashlib
import json
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import station_drill  # noqa: E402
from station_drill import COMMIT, CURRENT, MECHANISM, Sandbox  # noqa: E402

OLD_LAUNCHER = b"# the launcher the station runs before the update\n"

FLOW = station_drill.CLOCK + r"""
function Flow($what) { Add-Content -LiteralPath $env:FLOW_LOG -Value $what }
function Station-File($name) { Join-Path "$env:LOCALAPPDATA\WstxRust\station" $name }
function Lock-State { try { ([IO.File]::Open((Station-File 'logs\update.lock'), 'OpenOrCreate', 'ReadWrite', 'None')).Dispose(); 'free' } catch { 'held' } }
function Launcher-Id { (Get-FileHash -LiteralPath (Station-File 'launcher.ps1') -Algorithm SHA256).Hash.ToLowerInvariant().Substring(0, 12) }
$global:Up = $true; $global:RunVer = 'ccccccccc'
# FlowBoot counts the starts; FlowStop the stops (one Ctrl+C each); FlowBreak is set from a
# Ctrl+Break until the next start; FlowReadIdx is the next GET /transmit reading per boot.
$global:FlowBoot = 0; $global:FlowStop = 0; $global:FlowBreak = $false; $global:FlowReadIdx = @{}
# FLOW_TASK_RUNNING: the task reports Running throughout; FLOW_TASK_STOP_FAILS: Stop-ScheduledTask throws.
function Get-ScheduledTask { param($TaskName)
  [pscustomobject]@{ Actions = @([pscustomobject]@{ Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$env:LOCALAPPDATA\WstxRust\station\launcher.ps1`"" }); State = $(if ($env:FLOW_TASK_RUNNING) { 'Running' } else { 'Ready' }) } }
function Register-ScheduledTask { Flow 'TASK CHANGED' }
function Set-ScheduledTask { Flow 'TASK CHANGED' }
function Stop-ScheduledTask { param($TaskName, $ErrorAction) if ($env:FLOW_TASK_STOP_FAILS) { throw 'flow: the task cannot be stopped' } }
# The Ctrl+C helper: FLOW_STOPS gives, per stop, the helper's exit and Windows error for Ctrl+C
# (c) and Ctrl+Break (b), and whether the station stays after a delivered signal (stay). The
# error goes to the file the helper's code names, as the helper writes it.
function Start-Process { param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru, [switch]$Wait)
  $code = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String([string]$ArgumentList[-1]))
  $ctrl = if ($code -match '\[W\.C\]::Raise\(([0-9]+)\)') { [int]$Matches[1] } else { -1 }
  $file = if ($code -match '\$f=''([^'']*)''') { $Matches[1] } else { $null }
  if ($ctrl -eq 0) { $global:FlowStop++; $global:FlowBreak = $false; Flow "stop $global:RunVer lock=$(Lock-State)" }
  else { $global:FlowBreak = $true; Flow "break $global:RunVer" }
  $stops = @(($env:FLOW_STOPS | ConvertFrom-Json) | ForEach-Object { $_ })
  $cfg = if ($global:FlowStop -le $stops.Count) { $stops[$global:FlowStop - 1] } else { [pscustomobject]@{ c = @(0, $null); b = @(0, $null); stay = $false } }
  $sig = if ($ctrl -eq 0) { @($cfg.c) } else { @($cfg.b) }
  $rc = [int]$sig[0]
  if ($rc -ne 0 -and $null -ne $sig[1] -and $file) { [IO.File]::WriteAllText($file, [string]$sig[1]) }
  if ($rc -eq 0 -and -not $cfg.stay) { $global:Up = $false }
  [pscustomobject]@{ ExitCode = $rc } }
function Stop-Process { Flow 'FORCED STOP'; $global:Up = $false }
function Start-ScheduledTask { param($TaskName)
  $a = [IO.File]::ReadAllText((Station-File 'active.json')) | ConvertFrom-Json
  $global:FlowBoot++; $global:FlowBreak = $false
  $global:RunVer = $a.version; $global:Up = $true
  Flow "start $($a.version) lock=$(Lock-State) launcher=$(Launcher-Id)"
  [IO.File]::WriteAllText((Station-File 'station-running.json'), (@{ source_commit = $a.source_commit; process_id = 4242; launcher = 'active.json' } | ConvertTo-Json)) }
function Get-CimInstance { param($ClassName, $Filter)
  if ($global:Up) { [pscustomobject]@{ ProcessId = 4242; ExecutablePath = (Station-File "$($global:RunVer)\wstx-rust.exe") } } }
function Invoke-WebRequest { [pscustomobject]@{ StatusCode = 200 } }
function Get-NetFirewallRule { param($Name) [pscustomobject]@{ Enabled = 'True'; Direction = 'Inbound'; Action = 'Allow' } }
function Get-NetFirewallAddressFilter { process { [pscustomobject]@{ LocalAddress = '192.168.0.37'; RemoteAddress = '192.168.0.6' } } }
function Get-NetFirewallPortFilter { process { [pscustomobject]@{ Protocol = 'TCP'; LocalPort = '18081' } } }
function git {
  if ($args -contains 'fetch' -or $args -contains 'merge-base') { $global:LASTEXITCODE = 0; return }
  if ($args -contains 'ls-tree') {
    $path = [string]$args[$args.Count - 1]; $commit = [string]$args[[array]::IndexOf($args, '--') - 1]
    if (Test-Path -LiteralPath (Join-Path (Join-Path $env:DRILL_GIT_STORE $commit) ($path -replace '/', '\')) -PathType Leaf) { $path }
    $global:LASTEXITCODE = 0; return }
  if ($args -contains 'show') {
    $spec = [string]$args[$args.Count - 1]; $i = $spec.IndexOf(':')
    $file = Join-Path (Join-Path $env:DRILL_GIT_STORE $spec.Substring(0, $i)) ($spec.Substring($i + 1) -replace '/', '\')
    if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file; $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 128 }
    return }
  if ($args -contains 'log') { Flow "git log $($args[$args.Count - 1])"; $env:FLOW_SUBJECTS -split '\|'; $global:LASTEXITCODE = 0; return }
  throw "unexpected git $args" }
function gh {
  if ($args[0] -eq 'issue' -and $args[1] -eq 'view') {
    $n = [string]$args[2]; Flow "issue view $n"
    $p = ($env:FLOW_ISSUES | ConvertFrom-Json).PSObject.Properties[$n]
    if (-not $p) { $global:LASTEXITCODE = 1; return }
    [pscustomobject]@{ state = $p.Value.state; labels = @($p.Value.labels | ForEach-Object { [pscustomobject]@{ name = $_ } }) } | ConvertTo-Json -Depth 4 -Compress
    $global:LASTEXITCODE = 0; return }
  if ($args[0] -eq 'issue' -and $args[1] -eq 'comment') {
    $n = $args[2]; $body = $args[[array]::IndexOf($args, '--body') + 1]; $repo = $args[[array]::IndexOf($args, '--repo') + 1]
    [IO.File]::WriteAllText((Join-Path $env:FLOW_POSTS "$n.txt"), $body); Flow "posted $n repo=$repo"; $global:LASTEXITCODE = 0; return }
  throw "unexpected gh $args" }
function python { Flow "python $($args -join ' ')"; 'cr state: #171 landed -> installed'; 'cr state: #23: not moved, at implementing'; $global:LASTEXITCODE = 0 }
function powershell.exe {
  $joined = $args -join ' '
  if ($joined -like '*station-probe.ps1*') { Flow "probe lock=$(Lock-State) $joined"; $env:FLOW_PROBE_LINE; $global:LASTEXITCODE = [int]$env:FLOW_PROBE_RC; return }
  if ($joined -like '*live-page-check.ps1*') { Flow "page-check lock=$(Lock-State) $joined"; $env:FLOW_PAGE_LINE; $global:LASTEXITCODE = [int]$env:FLOW_PAGE_RC; return }
  throw "unexpected powershell.exe $joined" }
"""

# The package's agent client of the flow: the drill's, whose GET /transmit is logged with the boot
# and the clock (seconds past 12:00:00). FLOW_READS gives, per boot after the first start, the
# readings in order ('<ptt>,<transmitting>,<startup_release>' or 'throw'), the last one repeated;
# FLOW_BEFORE_THROW makes the reading after a Ctrl+Break (the one before a forced stop) throw.
FLOW_AGENT_CLIENT = station_drill.FAKE_AGENT_CLIENT.replace("function Agent-Get(", "function Drill-AgentGet(") + r"""
function Agent-Get($c, [string]$Route) {
  if ($Route -ne '/transmit') { return Drill-AgentGet $c $Route }
  $seconds = [int](($global:DrillClock - $global:DrillT0).TotalSeconds)
  Add-Content -LiteralPath $env:FLOW_LOG -Value "transmit boot=$global:FlowBoot t=$seconds"
  if ($global:FlowBreak -and $env:FLOW_BEFORE_THROW) { throw [Net.WebException]::new('flow: transmit unreadable') }
  $p = $null; if ($env:FLOW_READS) { $p = ($env:FLOW_READS | ConvertFrom-Json).PSObject.Properties["$global:FlowBoot"] }
  if (-not $p) { return Drill-AgentGet $c $Route }
  $list = @($p.Value | ForEach-Object { $_ }); $k = "$global:FlowBoot"
  $i = 0; if ($global:FlowReadIdx.ContainsKey($k)) { $i = $global:FlowReadIdx[$k] }
  $global:FlowReadIdx[$k] = $i + 1
  $r = [string]$list[[Math]::Min($i, $list.Count - 1)]
  if ($r -eq 'throw') { throw [Net.WebException]::new('flow: transmit unreadable') }
  $v = $r -split ','
  [pscustomobject]@{ ptt = $v[0]; transmitting = ($v[1] -eq 'true'); startup_release = $v[2]; transmit = [pscustomobject]@{ arm_state = 'disarmed' } }
}
"""


class FlowSandbox(Sandbox):
    """The drill's sandbox whose package carries the flow's agent client (pinned as built)."""

    def mechanism(self):
        files = super().mechanism()
        files[MECHANISM[3]] = FLOW_AGENT_CLIENT.encode("utf-8")
        return files


SUBJECTS =["Deploy without the operator (#171)", "Unrelated fix (#23)"]
ISSUES = {"171": ("OPEN", ["cr:landed"]), "23": ("OPEN", ["cr:implementing"])}
OK_LINE_START = "Operator " + "OK comment"
PROBE_PASS = ("PROBE PASS 123456789 PID 4242", "0")
PAGE_PASS = ('LIVE PAGE CHECK PASS see the "PAGE CHECK" line $x `y', "0")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    with open(path, "rb") as f:
        return f.read()


class FlowCase(unittest.TestCase):
    """The flow's sandbox and its run; the tests are in the subclasses."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.s = FlowSandbox(os.path.join(self.tmp.name, "sandbox"), station_drill.SCRIPT)
        self.log = os.path.join(self.tmp.name, "flow.log")
        self.posts = os.path.join(self.tmp.name, "posts")
        os.makedirs(self.posts)

    def tearDown(self):
        self.tmp.cleanup()

    def with_old_launcher(self):
        """The station runs another launcher, pinned so by the running commit: no OK is asked."""
        s = self.s
        station_drill.write(os.path.join(s.station, "launcher.ps1"), OLD_LAUNCHER)
        pins = s.pins()
        pins[2] = (sha(OLD_LAUNCHER), pins[2][1])
        s.pin(CURRENT, pins)

    def cr_state_at(self, *parts):
        """The repository's harness has cr_state.py at <repo>/<parts>/core/tools/; returns the call."""
        path = os.path.join(self.s.repo, *parts, "core", "tools", "cr_state.py")
        station_drill.write(path, "# drill: cr_state.py\n")
        return f"python {path} installed {COMMIT} --since {CURRENT}"

    def deploy(self, probe=PROBE_PASS, page=PAGE_PASS, subjects=SUBJECTS, issues=ISSUES, stops=(), reads=None,
               before_throw=False, rollback=False, task_stop_fails=False, task_running=False):
        """Run the package's script. `stops`: per stop {"c": [rc, error], "b": [rc, error], "stay": bool};
        `reads`: {boot: [reading, ...]}. The steps leave out the Ctrl+Break and GET /transmit lines,
        which self.flow keeps with every other line."""
        open(self.log, "w").close()
        env = {"FLOW_LOG": self.log, "FLOW_POSTS": self.posts, "FLOW_PROBE_LINE": probe[0], "FLOW_PROBE_RC": probe[1],
               "FLOW_PAGE_LINE": page[0], "FLOW_PAGE_RC": page[1], "FLOW_SUBJECTS": "|".join(subjects),
               "FLOW_ISSUES": json.dumps({n: {"state": st, "labels": labels} for n, (st, labels) in issues.items()}),
               "FLOW_STOPS": json.dumps([dict({"c": [0, None], "b": [0, None], "stay": False}, **s) for s in stops]),
               "FLOW_READS": json.dumps({str(k): v for k, v in (reads or {}).items()})}
        if before_throw:
            env["FLOW_BEFORE_THROW"] = "1"
        if task_stop_fails:
            env["FLOW_TASK_STOP_FAILS"] = "1"
        if task_running:
            env["FLOW_TASK_RUNNING"] = "1"
        rc, out, _ = self.s.run(env=env, prelude=FLOW, rollback=rollback)
        with open(self.log, encoding="utf-8") as f:
            self.flow = f.read().splitlines()
        # A check's line ends with the lock holder; its arguments are read separately.
        steps = [line.split(" -")[0] if line.startswith(("probe", "page-check")) else line
                 for line in self.flow if not line.startswith(("break ", "transmit "))]
        return rc, out, steps

    def active(self):
        with open(os.path.join(self.s.station, "active.json"), encoding="utf-8") as f:
            return json.load(f)["source_commit"]

    def station_launcher(self):
        return read(os.path.join(self.s.station, "launcher.ps1"))

    def post(self, n):
        path = os.path.join(self.posts, f"{n}.txt")
        self.assertTrue(os.path.exists(path), f"no record posted on #{n}")
        with open(path, encoding="utf-8") as f:
            return f.read()

    def expected_record_lines(self):
        s = self.s
        exe = sha(read(os.path.join(s.pkg, "package", "wstx-rust.exe")))
        files = [f"{sha(read(os.path.join(s.pkg, 'deploy', *p.split('/'))))} {p}" for p in MECHANISM]
        return [f"Previous version: {CURRENT}", f"Package executable SHA-256: {exe}"] + files

    def assert_postable(self, record):
        for ch in "'\"$`":
            self.assertNotIn(ch, record)


class DeployFlowTests(FlowCase):
    def test_probe_and_page_check_pass_install_with_the_new_launcher_and_post_the_record(self):
        """TC-196-03 (a) and (c): launcher written without an OK; TC-171-03 order and lock; TC-171-04 record."""
        self.with_old_launcher()
        record_call = self.cr_state_at("harness", "general")
        new = sha(station_drill.LAUNCHER)[:12]
        rc, out, steps = self.deploy()
        self.assertEqual(rc, 0, out)
        self.assertEqual(steps, ["stop ccccccccc lock=held", f"start 123456789 lock=held launcher={new}", "probe lock=held",
                                 "page-check lock=free", record_call,
                                 "posted 171 repo=SensorsIot/wsjtx-rust"], out)
        self.assertEqual(self.active(), COMMIT)
        self.assertEqual(self.station_launcher(), station_drill.LAUNCHER)
        saved = glob.glob(os.path.join(self.s.station, "logs", "update-*-launcher.ps1"))
        self.assertEqual([read(p) for p in saved], [OLD_LAUNCHER])
        # The page check gets the repository, the shared folder and the package's agent client.
        with open(self.log, encoding="utf-8") as f:
            page = next(line for line in f.read().splitlines() if line.startswith("page-check"))
        self.assertIn(f"-Repo {self.s.repo} -Shared {self.s.repo}\\.git\\harness-parallel "
                      f"-AgentClient {os.path.join(self.s.pkg, 'deploy', 'tools', 'deploy', 'agent-client.ps1')}", page)
        record = self.post(171)
        self.assert_postable(record)
        lines = record.splitlines()
        self.assertEqual(lines[0], f"Install record: {COMMIT} installed")
        for line in self.expected_record_lines():
            self.assertIn(line, lines)
        self.assertIn("Probe: PROBE PASS 123456789 PID 4242", lines)
        self.assertIn("Page check: LIVE PAGE CHECK PASS see the PAGE CHECK line x y", lines)
        self.assertEqual([l for l in lines if l.startswith(OK_LINE_START)], [])
        self.assertIn("Return to the previous version: none", lines)

    # Proves: TC-248-04
    def test_the_record_runs_the_cr_state_of_harness_general_only(self):
        self.cr_state_at("harness")
        record_call = f"python {os.path.join(self.s.repo, 'harness', 'general', 'core', 'tools', 'cr_state.py')} installed {COMMIT} --since {CURRENT}"
        rc, out, steps = self.deploy()
        self.assertEqual(rc, 0, out)
        self.assertEqual(steps[4:], [record_call, "posted 171 repo=SensorsIot/wsjtx-rust"], out)

    def test_install_without_a_changed_mechanism_keeps_the_launcher(self):
        """TC-171-04: no return; the launcher is not written; the record holds no OK line (TC-196-03 c)."""
        before = self.station_launcher()
        rc, out, steps = self.deploy()
        self.assertEqual(rc, 0, out)
        self.assertEqual(steps[:4], ["stop ccccccccc lock=held", f"start 123456789 lock=held launcher={sha(before)[:12]}",
                                     "probe lock=held", "page-check lock=free"], out)
        self.assertEqual(self.station_launcher(), before)
        lines = self.post(171).splitlines()
        self.assertEqual([l for l in lines if l.startswith(OK_LINE_START)], [])
        self.assertIn("Return to the previous version: none", lines)

    def test_probe_fail_page_check_red_or_error_return_under_the_lock(self):
        """TC-171-03, TC-196-03 (b): each is followed by the return, under the lock, with the old launcher restored."""
        old = sha(OLD_LAUNCHER)[:12]
        new = sha(station_drill.LAUNCHER)[:12]
        cases = [("probe FAIL", ("PROBE FAIL listener PID 4242 runs another image", "1"), PAGE_PASS, False),
                 ("page check RED", PROBE_PASS, ("LIVE PAGE CHECK RED see the PAGE CHECK line", "1"), True),
                 ("page check ERROR", PROBE_PASS, ("LIVE PAGE CHECK ERROR the check exited with 9", "2"), True)]
        for name, probe, page, page_ran in cases:
            with self.subTest(name):
                self.tearDown()
                self.setUp()
                self.with_old_launcher()
                rc, out, steps = self.deploy(probe, page)
                self.assertEqual(rc, 1, out)
                self.assertEqual(steps, ["stop ccccccccc lock=held", f"start 123456789 lock=held launcher={new}", "probe lock=held"]
                                 + (["page-check lock=free"] if page_ran else [])
                                 + ["stop 123456789 lock=held", f"start ccccccccc lock=held launcher={old}",
                                    f"git log {CURRENT}..{COMMIT}", "issue view 23", "issue view 171",
                                    "posted 171 repo=SensorsIot/wsjtx-rust"], out)
                self.assertEqual(self.active(), CURRENT)
                self.assertEqual(self.station_launcher(), OLD_LAUNCHER)
                record = self.post(171)
                self.assert_postable(record)
                lines = record.splitlines()
                self.assertEqual(lines[0], f"Install record: {COMMIT} returned")
                for line in self.expected_record_lines():
                    self.assertIn(line, lines)
                self.assertIn(f"Probe: {probe[0]}", lines)
                self.assertIn(f"Page check: {page[0] if page_ran else 'not run'}", lines)
                self.assertTrue([l for l in lines if l.startswith(f"Return to the previous version: to {CURRENT} (")], record)

    def test_page_check_busy_or_not_exercised_keeps_the_install(self):
        """TC-171-03: no return; the result is recorded."""
        for word, rc_page in (("BUSY", "3"), ("NOT-EXERCISED", "4")):
            with self.subTest(word):
                self.tearDown()
                self.setUp()
                line = f"LIVE PAGE CHECK {word} see the PAGE CHECK line"
                rc, out, steps = self.deploy(page=(line, rc_page))
                self.assertEqual(rc, 0, out)
                self.assertEqual([s for s in steps if s.startswith(("stop", "start"))],
                                 ["stop ccccccccc lock=held", steps[1]], out)
                self.assertEqual(self.active(), COMMIT)
                lines = self.post(171).splitlines()
                self.assertIn(f"Page check: {line}", lines)
                self.assertIn("Return to the previous version: none", lines)

    def test_return_record_goes_only_on_open_issues_at_landed_or_installed(self):
        """TC-196-05 (a): the other issues the subjects name are logged, not posted on."""
        subjects = [f"Change (#{n})" for n in (171, 50, 23, 137, 60, 70)]
        issues = {"171": ("OPEN", ["cr:landed"]), "50": ("OPEN", ["cr:installed"]), "23": ("OPEN", ["cr:implementing"]),
                  "137": ("CLOSED", ["cr:accepted"]), "60": ("CLOSED", ["cr:landed"])}
        rc, out, steps = self.deploy(("PROBE FAIL listener PID 4242 runs another image", "1"), subjects=subjects, issues=issues)
        self.assertEqual(rc, 1, out)
        self.assertEqual(sorted(p for p in os.listdir(self.posts)), ["171.txt", "50.txt"], out)
        for line in ("record not posted on #23: at cr:implementing", "record not posted on #137: closed",
                     "record not posted on #60: closed", "record not posted on #70: state cannot be read"):
            self.assertIn(line, out)
        self.assertIn("posted 50 repo=SensorsIot/wsjtx-rust", steps)
        self.assertIn("posted 171 repo=SensorsIot/wsjtx-rust", steps)

    def test_open_issue_without_a_cr_state_gets_no_return_record(self):
        """TC-196-05 (a) variant: the third reason of F3."""
        rc, out, steps = self.deploy(("PROBE FAIL listener PID 4242 runs another image", "1"), subjects=["Change (#23)"],
                                     issues={"23": ("OPEN", ["bug"])})
        self.assertEqual(rc, 1, out)
        self.assertEqual(os.listdir(self.posts), [], out)
        self.assertIn("record not posted on #23: no cr state", out)

    def test_install_record_reads_no_issue(self):
        """TC-196-05 (b): after a successful install the cr_state.py result decides, no gh issue view."""
        rc, out, steps = self.deploy()
        self.assertEqual(rc, 0, out)
        self.assertEqual([s for s in steps if s.startswith("issue view")], [], out)
        self.assertEqual(os.listdir(self.posts), ["171.txt"], out)

    def test_the_task_is_never_changed(self):
        """TC-171-02 (g): no command that changes the scheduled task is in the script."""
        self.with_old_launcher()
        rc, out, steps = self.deploy()
        self.assertNotIn("TASK CHANGED", steps, out)
        with open(station_drill.SCRIPT, encoding="utf-8") as f:
            text = f.read()
        for command in ("Register-ScheduledTask", "Set-ScheduledTask", "Unregister-ScheduledTask", "New-ScheduledTask"):
            self.assertNotIn(command, text)


def lines_of(out):
    """The update's lines without their HH:mm:ss stamp."""
    return [re.sub(r"^\d\d:\d\d:\d\d ", "", line) for line in out.splitlines()]


class SharedStopTests(FlowCase):
    """The update's stop on the shared station-process.ps1: each caller's sequence unchanged."""
    NOTE = "note: Stop-ScheduledTask: flow: the task cannot be stopped"

    def use_script(self, old, new):
        """Run a scratch copy of the update with `old` replaced by `new` from here on."""
        text = read(station_drill.SCRIPT).decode("utf-8")
        self.assertEqual(text.count(old), 1, old)
        path = os.path.join(self.tmp.name, "scratch", "station-update.ps1")
        station_drill.write(path, text.replace(old, new))
        self.s = FlowSandbox(os.path.join(self.tmp.name, "scratch-sandbox"), path)

    def update_log(self):
        [log] = glob.glob(os.path.join(self.s.station, "logs", "update-*.log"))
        with open(log, encoding="utf-8") as f:
            return f.read().splitlines()

    def note_case(self):
        rc, out, steps = self.deploy(task_stop_fails=True)
        self.assertEqual(rc, 0, out)
        self.assertTrue([line for line in self.update_log() if re.fullmatch(r"\d\d:\d\d:\d\d " + re.escape(self.NOTE), line)],
                        self.update_log())
        self.assertIn("started: 123456789 running, PID 4242; previous ccccccccc kept for -Rollback", lines_of(out))

    def running_case(self):
        rc, out, steps = self.deploy(task_running=True)
        self.assertEqual(rc, 1, out)
        self.assertIn("FAILED at step 'stop station': task still Running after the station exited; a restart would be ignored",
                      lines_of(out))
        self.assertEqual(self.active(), CURRENT)

    def break_case(self):
        rc, out, steps = self.deploy(stops=[{"stay": True}], reads={1: ["released,false,not_needed"]})
        self.assertEqual(rc, 0, out)
        self.assertEqual([line for line in self.flow if line.startswith(("stop ", "break "))],
                         ["stop ccccccccc lock=held", "break ccccccccc"], self.flow)

    def graceful_case(self):
        rc, out, steps = self.deploy()
        self.assertEqual(rc, 0, out)
        self.assertIn("graceful stop (Ctrl+C) sent to PID 4242: helper exit 0", lines_of(out))
        self.assertEqual([p for p in glob.glob(os.path.join(self.s.station, "logs", "*")) if p.endswith("-ctrl.txt")], [])

    # Proves: TC-317-06
    def test_a_failed_stop_scheduled_task_is_a_logged_step_and_the_update_goes_on(self):
        self.note_case()
        self.use_script("foreach ($note in @(Settle-Task)) { Step $note }", "Settle-Task")
        with self.assertRaises(AssertionError):
            self.note_case()

    # Proves: TC-317-06
    def test_a_task_still_running_after_the_settle_is_refused(self):
        self.running_case()
        self.use_script("  if ((Get-ScheduledTask -TaskName $TaskName).State -eq 'Running') { throw 'task still Running after the "
                        "station exited; a restart would be ignored' }\n", "")
        with self.assertRaises(AssertionError):
            self.running_case()

    # Proves: TC-317-06
    def test_the_second_signal_is_ctrl_break(self):
        self.break_case()
        self.use_script("$b=Send-CtrlC $id 1", "$b=Send-CtrlC $id")
        with self.assertRaises(AssertionError):
            self.break_case()

    # Proves: TC-317-06
    def test_the_update_names_the_helper_error_file(self):
        self.graceful_case()
        self.use_script('$CtrlErrFile=Join-Path $Station "logs\\update-$stamp-ctrl.txt"\n', "")
        with self.assertRaises(AssertionError):
            self.graceful_case()


if __name__ == "__main__":
    unittest.main()
