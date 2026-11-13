"""station-update.ps1 after the switch: probe, live page check, return, launcher and install record.

TC-171-03 (return and lock), TC-171-04 (install record) and the launcher write of TC-171-02 (g).
The station is simulated by mocks that let the stop and the start succeed: the scheduled task,
the station process, its receipt, the network, git, GitHub, cr_state.py and the two checks the
deploy starts (station-probe.ps1 and live-page-check.ps1, as powershell.exe). Each mock writes
what reached it to a log, with the holder of update.lock at that moment, so the order of the
steps and the lock are the oracle. The package and the pins are the drill's sandbox.
"""
import hashlib
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import station_drill  # noqa: E402
from station_drill import COMMENT_ID, COMMIT, CURRENT, MECHANISM, Sandbox  # noqa: E402

OLD_LAUNCHER = b"# the launcher the station runs before the update\n"

FLOW = station_drill.CLOCK + r"""
function Flow($what) { Add-Content -LiteralPath $env:FLOW_LOG -Value $what }
function Station-File($name) { Join-Path "$env:LOCALAPPDATA\WstxRust\station" $name }
function Lock-State { try { ([IO.File]::Open((Station-File 'logs\update.lock'), 'OpenOrCreate', 'ReadWrite', 'None')).Dispose(); 'free' } catch { 'held' } }
function Launcher-Id { (Get-FileHash -LiteralPath (Station-File 'launcher.ps1') -Algorithm SHA256).Hash.ToLowerInvariant().Substring(0, 12) }
$global:Up = $true; $global:RunVer = 'ccccccccc'
function Get-ScheduledTask { param($TaskName)
  [pscustomobject]@{ Actions = @([pscustomobject]@{ Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$env:LOCALAPPDATA\WstxRust\station\launcher.ps1`"" }); State = 'Ready' } }
function Register-ScheduledTask { Flow 'TASK CHANGED' }
function Set-ScheduledTask { Flow 'TASK CHANGED' }
function Stop-ScheduledTask { param($TaskName, $ErrorAction) }
function Start-Process { param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru, [switch]$Wait)
  Flow "stop $global:RunVer lock=$(Lock-State)"; $global:Up = $false; [pscustomobject]@{ ExitCode = 0 } }
function Stop-Process { Flow 'FORCED STOP' }
function Start-ScheduledTask { param($TaskName)
  $a = [IO.File]::ReadAllText((Station-File 'active.json')) | ConvertFrom-Json
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
  if ($args -contains 'show') {
    $spec = [string]$args[$args.Count - 1]; $i = $spec.IndexOf(':')
    $file = Join-Path (Join-Path $env:DRILL_GIT_STORE $spec.Substring(0, $i)) ($spec.Substring($i + 1) -replace '/', '\')
    if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file; $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 128 }
    return }
  if ($args -contains 'log') { Flow "git log $($args[$args.Count - 1])"; 'Deploy without the operator (#171)'; 'Unrelated fix (#23)'; $global:LASTEXITCODE = 0; return }
  throw "unexpected git $args" }
function gh {
  if ($args[0] -eq 'api') {
    if (Test-Path -LiteralPath $env:DRILL_COMMENT) { Get-Content -LiteralPath $env:DRILL_COMMENT -Raw; $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 1 }
    return }
  if ($args[0] -eq 'issue' -and $args[1] -eq 'comment') {
    $n = $args[2]; $body = $args[[array]::IndexOf($args, '--body') + 1]; $repo = $args[[array]::IndexOf($args, '--repo') + 1]
    [IO.File]::WriteAllText((Join-Path $env:FLOW_POSTS "$n.txt"), $body); Flow "posted $n repo=$repo"; $global:LASTEXITCODE = 0; return }
  throw "unexpected gh $args" }
function python { Flow "python $($args -join ' ')"; '#171 landed -> installed'; '#23: not moved, at implementing'; $global:LASTEXITCODE = 0 }
function powershell.exe {
  $joined = $args -join ' '
  if ($joined -like '*station-probe.ps1*') { Flow "probe lock=$(Lock-State) $joined"; $env:FLOW_PROBE_LINE; $global:LASTEXITCODE = [int]$env:FLOW_PROBE_RC; return }
  if ($joined -like '*live-page-check.ps1*') { Flow "page-check lock=$(Lock-State) $joined"; $env:FLOW_PAGE_LINE; $global:LASTEXITCODE = [int]$env:FLOW_PAGE_RC; return }
  throw "unexpected powershell.exe $joined" }
"""

PROBE_PASS = ("PROBE PASS 123456789 PID 4242", "0")
PAGE_PASS = ('LIVE PAGE CHECK PASS see the "PAGE CHECK" line $x `y', "0")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    with open(path, "rb") as f:
        return f.read()


class DeployFlowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.s = Sandbox(os.path.join(self.tmp.name, "sandbox"), station_drill.SCRIPT)
        self.log = os.path.join(self.tmp.name, "flow.log")
        self.posts = os.path.join(self.tmp.name, "posts")
        os.makedirs(self.posts)

    def tearDown(self):
        self.tmp.cleanup()

    def with_ok_and_old_launcher(self):
        """The station runs another launcher, pinned so by the running commit: item 5, with the OK."""
        s = self.s
        station_drill.write(os.path.join(s.station, "launcher.ps1"), OLD_LAUNCHER)
        pins = s.pins()
        pins[2] = (sha(OLD_LAUNCHER), pins[2][1])
        s.pin(CURRENT, pins)
        s.comment(s.ok_line())

    def deploy(self, probe=PROBE_PASS, page=PAGE_PASS):
        open(self.log, "w").close()
        env = {"FLOW_LOG": self.log, "FLOW_POSTS": self.posts, "FLOW_PROBE_LINE": probe[0], "FLOW_PROBE_RC": probe[1],
               "FLOW_PAGE_LINE": page[0], "FLOW_PAGE_RC": page[1]}
        rc, out, _ = self.s.run(env=env, prelude=FLOW)
        with open(self.log, encoding="utf-8") as f:
            # A check's line ends with the lock holder; its arguments are read separately.
            steps = [line.split(" -")[0] if line.startswith(("probe", "page-check")) else line
                     for line in f.read().splitlines()]
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

    def test_probe_and_page_check_pass_install_with_the_new_launcher_and_post_the_record(self):
        """TC-171-02 (g) launcher, TC-171-03 order and lock, TC-171-04 record with the OK id."""
        self.with_ok_and_old_launcher()
        new = sha(station_drill.LAUNCHER)[:12]
        rc, out, steps = self.deploy()
        self.assertEqual(rc, 0, out)
        self.assertEqual(steps, ["stop ccccccccc lock=held", f"start 123456789 lock=held launcher={new}", "probe lock=held",
                                 "page-check lock=free", f"python {self.s.repo}\\harness\\core\\tools\\cr_state.py installed {COMMIT} --since {CURRENT}",
                                 "posted 171 repo=SensorsIot/wsjtx-rust"], out)
        self.assertEqual(self.active(), COMMIT)
        self.assertEqual(self.station_launcher(), station_drill.LAUNCHER)
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
        self.assertIn(f"Operator OK comment: {COMMENT_ID}", lines)
        self.assertIn("Return to the previous version: none", lines)

    def test_install_without_a_changed_mechanism_records_no_ok_and_keeps_the_launcher(self):
        """TC-171-04: no OK comment, no return; the launcher is not written."""
        before = self.station_launcher()
        rc, out, steps = self.deploy()
        self.assertEqual(rc, 0, out)
        self.assertEqual(steps[:4], ["stop ccccccccc lock=held", f"start 123456789 lock=held launcher={sha(before)[:12]}",
                                     "probe lock=held", "page-check lock=free"], out)
        self.assertEqual(self.station_launcher(), before)
        lines = self.post(171).splitlines()
        self.assertIn("Operator OK comment: none", lines)
        self.assertIn("Return to the previous version: none", lines)

    def test_probe_fail_page_check_red_or_error_return_under_the_lock(self):
        """TC-171-03: each is followed by the return, under the lock, with the old launcher restored."""
        old = sha(OLD_LAUNCHER)[:12]
        new = sha(station_drill.LAUNCHER)[:12]
        cases = [("probe FAIL", ("PROBE FAIL listener PID 4242 runs another image", "1"), PAGE_PASS, False),
                 ("page check RED", PROBE_PASS, ("LIVE PAGE CHECK RED see the PAGE CHECK line", "1"), True),
                 ("page check ERROR", PROBE_PASS, ("LIVE PAGE CHECK ERROR the check exited with 9", "2"), True)]
        for name, probe, page, page_ran in cases:
            with self.subTest(name):
                self.tearDown()
                self.setUp()
                self.with_ok_and_old_launcher()
                rc, out, steps = self.deploy(probe, page)
                self.assertEqual(rc, 1, out)
                self.assertEqual(steps, ["stop ccccccccc lock=held", f"start 123456789 lock=held launcher={new}", "probe lock=held"]
                                 + (["page-check lock=free"] if page_ran else [])
                                 + ["stop 123456789 lock=held", f"start ccccccccc lock=held launcher={old}",
                                    f"git log {CURRENT}..{COMMIT}", "posted 23 repo=SensorsIot/wsjtx-rust",
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

    def test_the_task_is_never_changed(self):
        """TC-171-02 (g): no command that changes the scheduled task is in the script."""
        self.with_ok_and_old_launcher()
        rc, out, steps = self.deploy()
        self.assertNotIn("TASK CHANGED", steps, out)
        with open(station_drill.SCRIPT, encoding="utf-8") as f:
            text = f.read()
        for command in ("Register-ScheduledTask", "Set-ScheduledTask", "Unregister-ScheduledTask", "New-ScheduledTask"):
            self.assertNotIn(command, text)


if __name__ == "__main__":
    unittest.main()
