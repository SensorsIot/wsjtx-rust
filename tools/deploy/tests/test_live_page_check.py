"""live-page-check.ps1: it restarts the station only when it is free,
and before the restart makes one band selection of the band the station receives on.

Everything that reaches the system is mocked: the agent client, the station process, the Ctrl+C
helper, the scheduled task. The page check is a stand-in that asks for the restart, reports the
lines it was handed (their keys only), writes <control>/rows once a selection is reported and
ends NOT-EXERCISED when it was told the selection was not made or did not take.
"""
import json
import os
import re
import shutil
import tempfile
import unittest

import pwsh

SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "live-page-check.ps1")

FAKE_CHECK = r"""
const fs=require('node:fs'),path=require('node:path'),readline=require('node:readline');
const control=process.env.WSTX_LIVE_PAGE_CONTROL,log=what=>fs.appendFileSync(process.env.LPC_LOG,what+'\n');
console.log('CHECK CWD '+process.cwd()+' FILE '+__filename);
fs.writeFileSync(path.join(control,'restart'),'');
let sessions=0;const unexercised=[];
readline.createInterface({input:process.stdin}).on('line',line=>{
  const m=JSON.parse(line.replace(/^﻿/,''));
  console.log('CHECK GOT '+Object.keys(m).join(','));
  if(m.abort)process.exit(3);
  if(m.unexercised){console.log('CHECK UNEXERCISED '+m.unexercised);unexercised.push(m.unexercised);}
  if(m.selected){
    console.log('CHECK SELECTED generation '+m.selected.generation+' ms '+m.selected.ms);
    // While the page waits for the raised generation, the station may come into use.
    const later=JSON.parse(process.env.LPC_LATER||'{}');
    if(later.lease)fs.writeFileSync(process.env.LPC_LEASE,JSON.stringify(later.lease));
    else if(later.procs)fs.writeFileSync(process.env.LPC_PROCS,'');
    else if(Object.keys(later).length)fs.writeFileSync(process.env.LPC_STATE,JSON.stringify({...JSON.parse(fs.readFileSync(process.env.LPC_STATE,'utf8')),...later}));
    const delay=process.env.LPC_ROWS_AFTER==='wait'?m.selected.ms:Number(process.env.LPC_ROWS_AFTER||0);
    setTimeout(()=>{log('rows');console.log('CHECK ROWS');fs.writeFileSync(path.join(control,'rows'),'');},delay);
  }
  // Once the new boot answers, the restart has given the update lock back.
  if(m.cookies&&++sessions===2){try{fs.closeSync(fs.openSync(process.env.LPC_LOCK,'r+'));console.log('CHECK LOCK free');}catch{console.log('CHECK LOCK held');}process.exit(unexercised.length?4:0);}
});
"""

AGENT_CLIENT = r"""
$AgentUrl = 'https://localhost:9'
$global:LpcCommand = $null; $global:LpcPosts = 0; $global:LpcRevision = 0
function Log($what) { Add-Content -LiteralPath $env:LPC_LOG -Value $what }
function Open-AgentSession {
  $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  $s.Cookies.Add((New-Object Net.Cookie 'wstx_session_p', 'secret', '/', 'localhost'))
  [pscustomobject]@{ Session = $s }
}
function Agent-Get($c, [string]$Route) {
  $state = [IO.File]::ReadAllText($env:LPC_STATE) | ConvertFrom-Json
  if ($state.PSObject.Properties['unreadable']) { throw [Net.WebException]::new('down') }
  switch ($Route) {
    '/transmit' { [pscustomobject]@{ ptt = $state.ptt; transmitting = $state.transmitting; transmit = [pscustomobject]@{ arm_state = $state.arm } } }
    '/contact' { [pscustomobject]@{ contact = $state.contact } }
    '/automation' { [pscustomobject]@{ run = $state.run } }
    '/receive/startup' { $state.startup }
    '/receive/selection' {
      $view = $state.sel
      $view.operating_revision = $view.operating_revision + $global:LpcRevision
      $op = $null
      if ($global:LpcCommand) { $op = [pscustomobject]@{ command_id = $global:LpcCommand; result = $state.op.result; error = $state.op.error } }
      $view | Add-Member -NotePropertyName operation -NotePropertyValue $op -Force
      $view
    }
  }
}
function Agent-Post($c, [string]$Route, $Body) {
  Log 'select'
  Add-Content -LiteralPath $env:LPC_POSTS -Value ($Body | ConvertTo-Json -Compress)
  $state = [IO.File]::ReadAllText($env:LPC_STATE) | ConvertFrom-Json
  $replies = @($state.replies)
  $reply = $replies[[Math]::Min($global:LpcPosts, $replies.Count - 1)]; $global:LpcPosts++
  if ($reply -eq 202) { $global:LpcCommand = $Body.command_id; return [pscustomobject]@{ Status = 202; Body = [pscustomobject]@{ accepted = $true } } }
  # A refused selection changes nothing but what the next read shows anew.
  $global:LpcRevision++
  [pscustomobject]@{ Status = 409; Body = [pscustomobject]@{ error = [pscustomobject]@{ code = $reply; field = $null } } }
}
"""


def prelude(station):
    exe = pwsh.ps_quote(os.path.join(station, "0d7d5c922", "wstx-rust.exe"))
    down = pwsh.ps_quote(os.path.join(station, "down"))
    procs = pwsh.ps_quote(os.path.join(station, "procs2"))
    lock = pwsh.ps_quote(os.path.join(station, "logs", "update.lock"))
    return f"""
function Log($what) {{ Add-Content -LiteralPath $env:LPC_LOG -Value $what }}
function Get-CimInstance {{ param($ClassName,$Filter)
  if (-not (Test-Path -LiteralPath {down})) {{ [pscustomobject]@{{ProcessId=4242; ExecutablePath={exe}}} }}
  if (Test-Path -LiteralPath {procs}) {{ [pscustomobject]@{{ProcessId=4243; ExecutablePath={exe}}} }} }}
function Start-Process {{ param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru,[switch]$Wait) Log 'ctrlc'; Set-Content -LiteralPath {down} -Value ''; [pscustomobject]@{{ExitCode=0}} }}
function Stop-ScheduledTask {{ param($TaskName,$ErrorAction) }}
function Get-ScheduledTask {{ param($TaskName) [pscustomobject]@{{State='Ready'}} }}
function Start-ScheduledTask {{ param($TaskName)
  try {{ ([IO.File]::Open({lock}, 'OpenOrCreate', 'ReadWrite', 'None')).Dispose(); Log 'start-unlocked' }} catch [IO.IOException] {{ Log 'start-locked' }}
  Remove-Item -LiteralPath {down} }}
function Start-Sleep {{ param($Seconds,$Milliseconds) [Threading.Thread]::Sleep(20) }}
"""


PROFILE = "6f1c2d3e-4a5b-4c6d-8e7f-901234567890"
BOOT = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"
# FT8 receive on 20m, the saved choice ft8 20m, Monitor off at startup not set.
SELECTION = {"v": 1, "profile_id": PROFILE, "boot_id": BOOT, "profile_revision": 3, "generation": 1,
             "operating_revision": 7, "selection": {"mode": "ft8", "band": "20m"},
             "receive": {"job_id": "j1", "mode": "ft8", "state": "running"}}
STARTUP = {"monitor_off_at_startup": False,
           "last_receive": {"mode": "ft8", "band": "20m", "input_device": "USB Audio CODEC"}}
FREE = {"arm": "disarmed", "ptt": "released", "transmitting": False, "contact": None, "run": None,
        "sel": SELECTION, "startup": STARTUP, "replies": [202], "op": {"result": "success", "error": None}}


def with_selection(**changes):
    return dict(FREE, sel=dict(SELECTION, **changes))


class LivePageCheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.station = os.path.join(self.tmp.name, "station")
        os.makedirs(os.path.join(self.station, "logs"))
        self.shared = os.path.join(self.tmp.name, "shared")
        self.radio = os.path.join(self.shared, "radio")
        os.makedirs(self.radio)
        self.repo = os.path.join(self.tmp.name, "repo")
        os.makedirs(self.repo)
        self.log = os.path.join(self.tmp.name, "log.txt")
        open(self.log, "w").close()
        self.posts = os.path.join(self.tmp.name, "posts.txt")
        self.state = os.path.join(self.tmp.name, "state.json")
        self.check = os.path.join(self.tmp.name, "check.cjs")
        with open(self.check, "w", encoding="utf-8") as f:
            f.write(FAKE_CHECK)
        self.client = os.path.join(self.tmp.name, "agent-client.ps1")
        with open(self.client, "w", encoding="utf-8") as f:
            f.write(AGENT_CLIENT)

    def tearDown(self):
        self.tmp.cleanup()

    def run_check(self, state, script=SCRIPT, check=True, later=None, rows_after=None):
        with open(self.state, "w", encoding="utf-8") as f:
            json.dump(state, f)
        open(self.posts, "w").close()
        args = ["-WaitSeconds", "1", "-Station", self.station, "-AgentClient", self.client,
                "-Repo", self.repo, "-Shared", self.shared] + (["-Check", self.check] if check else [])
        env = {"LPC_LOG": self.log, "LPC_STATE": self.state, "LPC_POSTS": self.posts,
               "LPC_LOCK": os.path.join(self.station, "logs", "update.lock"),
               "LPC_LEASE": os.path.join(self.radio, "lease.json"),
               "LPC_PROCS": os.path.join(self.station, "procs2"),
               "LPC_LATER": json.dumps(later or {}), "LPC_ROWS_AFTER": str(rows_after or 0)}
        rc, out = pwsh.run(script, args, prelude(self.station), env=env)
        with open(self.log, encoding="utf-8") as f:
            return rc, out, f.read().split()

    def bodies(self):
        with open(self.posts, encoding="utf-8-sig") as f:
            return [json.loads(line) for line in f.read().splitlines() if line.strip()]

    def got(self, out):
        return [line for line in out.splitlines() if line.startswith("CHECK GOT")]

    def assert_busy(self, state, why):
        rc, out, log = self.run_check(state)
        self.assertEqual(rc, 3, out)
        self.assertNotIn("select", log, out)
        self.assertNotIn("ctrlc", log, out)
        self.assertFalse([entry for entry in log if entry.startswith("start")], out)
        self.assertIn("CHECK GOT abort", out)
        self.assertIn(why, out)
        self.assertIn("LIVE PAGE CHECK BUSY", out)

    def assert_not_exercised(self, state, why, posts=0):
        """No PASS: the reason is named and the restart still follows. posts None: retried."""
        rc, out, log = self.run_check(state)
        self.assertEqual(rc, 4, out)
        selects = len(self.bodies())
        if posts is None:
            self.assertGreater(selects, 1, out)
        else:
            self.assertEqual(selects, posts, out)
        self.assertEqual(log, ["select"] * selects + ["ctrlc", "start-locked"], out)
        self.assertEqual(self.got(out), ["CHECK GOT cookies", "CHECK GOT unexercised", "CHECK GOT stopping",
                                         "CHECK GOT cookies"], out)
        self.assertIn(f"CHECK UNEXERCISED {why}", out)
        self.assertIn("LIVE PAGE CHECK NOT-EXERCISED", out)
        return out

    def test_free_station_selects_its_band_once_then_is_restarted_and_the_new_session_handed_on(self):
        rc, out, log = self.run_check(FREE)
        self.assertEqual(rc, 0, out)
        # The selection, the page's rows, then the station starts while this holds the update lock,
        # and gets it back once it answers.
        self.assertEqual(log, ["select", "rows", "ctrlc", "start-locked"], out)
        self.assertIn("CHECK LOCK free", out)
        self.assertEqual(self.got(out), ["CHECK GOT cookies", "CHECK GOT selected", "CHECK GOT stopping",
                                         "CHECK GOT cookies"], out)
        self.assertIn("CHECK SELECTED generation 1 ms ", out)
        self.assertNotIn("secret", out)
        self.assertIn("LIVE PAGE CHECK PASS", out)

    def test_the_selection_names_the_band_read_and_no_mode_with_the_read_revisions(self):
        rc, out, log = self.run_check(FREE)
        self.assertEqual(rc, 0, out)
        [body] = self.bodies()
        command = body.pop("command_id")
        self.assertRegex(command, r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
        self.assertEqual(body, {"v": 1, "action": "band", "profile_id": PROFILE, "boot_id": BOOT,
                                "profile_revision": 3, "generation": 1, "operating_revision": 7, "band": "20m"})

    def test_the_station_is_stopped_only_after_the_check_reports_the_raised_generation_with_rows(self):
        rc, out, log = self.run_check(FREE, rows_after=1500)
        self.assertEqual(rc, 0, out)
        self.assertEqual(log, ["select", "rows", "ctrlc", "start-locked"], out)
        lines = out.splitlines()
        self.assertLess(lines.index("CHECK ROWS"), lines.index("CHECK GOT stopping"), out)

    def test_the_wait_for_rows_is_bounded_from_the_202_and_the_restart_follows_it(self):
        """The page check waits at most the ms it is handed, -WaitSeconds counted from the 202; its
        verdict on rows that never came is tests/frontend/receive-page.test.cjs's."""
        rc, out, log = self.run_check(FREE, rows_after="wait")
        self.assertEqual(log, ["select", "rows", "ctrlc", "start-locked"], out)
        ms = int(out.split("CHECK SELECTED generation 1 ms ")[1].split()[0])
        self.assertTrue(0 <= ms <= 1000, out)

    def test_spectrum_receive(self):
        self.assert_not_exercised(with_selection(receive={"job_id": "j1", "mode": "spectrum", "state": "running"}),
                                  "no band selection: receive runs spectrum, not FT8 or FT4")

    def test_no_selected_band(self):
        self.assert_not_exercised(with_selection(selection={"mode": "ft8", "band": None}),
                                  "no band selection: no band is selected")

    def test_receive_stopped(self):
        self.assert_not_exercised(with_selection(receive={"job_id": None, "mode": None, "state": None}),
                                  "no band selection: receive is not running (state none)")

    def test_monitor_off_at_startup(self):
        self.assert_not_exercised(dict(FREE, startup=dict(STARTUP, monitor_off_at_startup=True)),
                                  "no band selection: Monitor off at startup is set")

    def test_saved_choice_differs_from_the_running_one(self):
        for name, saved, shown in (("other band", {"mode": "ft8", "band": "40m", "input_device": "x"}, "ft8 40m"),
                                   ("other mode", {"mode": "ft4", "band": "20m", "input_device": "x"}, "ft4 20m"),
                                   ("none", None, "none")):
            with self.subTest(name):
                open(self.log, "w").close()
                self.assert_not_exercised(dict(FREE, startup=dict(STARTUP, last_receive=saved)),
                                          f"no band selection: the saved receive choice ({shown}) is not the running ft8 20m")

    def test_selected_mode_differs_from_the_receive_mode(self):
        self.assert_not_exercised(with_selection(selection={"mode": "ft4", "band": "20m"}),
                                  "no band selection: the selected mode ft4 is not the receive mode ft8")

    def test_busy_again_just_before_ctrl_c(self):
        for name, later, why in (("armed", {"arm": "armed"}, "transmit is armed"),
                                 ("ptt keyed", {"ptt": "keyed"}, "PTT is keyed"),
                                 ("transmitting", {"transmitting": True}, "transmitting: True"),
                                 ("contact running", {"contact": {"state": "report"}}, "a contact is report"),
                                 ("automation run", {"run": {"state": "waiting"}}, "an automation run is waiting"),
                                 ("unreadable", {"unreadable": True}, "its state cannot be read"),
                                 ("radio lease", {"lease": {"holder": "qso-test", "expires": "2099-01-01T00:00:00Z"}},
                                  "qso-test holds the radio lease"),
                                 ("two processes", {"procs": True}, "2 station processes are running")):
            with self.subTest(name):
                open(self.log, "w").close()
                for leftover in (os.path.join(self.radio, "lease.json"), os.path.join(self.station, "procs2")):
                    if os.path.exists(leftover):
                        os.remove(leftover)
                rc, out, log = self.run_check(FREE, later=later)
                self.assertEqual(rc, 3, out)
                self.assertEqual(log, ["select", "rows"], out)
                self.assertEqual(self.got(out), ["CHECK GOT cookies", "CHECK GOT selected", "CHECK GOT abort"], out)
                self.assertRegex(out, "in use before the stop: [^\n]*" + re.escape(why))
                self.assertIn("LIVE PAGE CHECK BUSY", out)

    def test_a_transient_refusal_is_read_afresh_and_retried_then_accepted(self):
        rc, out, log = self.run_check(dict(FREE, replies=["busy", 202]))
        self.assertEqual(rc, 0, out)
        self.assertEqual(log, ["select", "select", "rows", "ctrlc", "start-locked"], out)
        first, second = self.bodies()
        self.assertEqual(second["operating_revision"], first["operating_revision"] + 1, "read afresh")
        self.assertNotEqual(first["command_id"], second["command_id"])
        self.assertIn("LIVE PAGE CHECK PASS", out)

    def test_a_refusal_that_remains(self):
        self.assert_not_exercised(dict(FREE, replies=["radio_unavailable"]),
                                  "the band selection was refused: radio_unavailable", posts=None)

    def test_a_refusal_not_retried(self):
        self.assert_not_exercised(dict(FREE, replies=["select_band_first"]),
                                  "the band selection was refused: select_band_first", posts=1)

    def test_an_operation_that_ends_failed_or_cancelled(self):
        for result, error, why in (("failed", "release_failed", "the band selection ended failed: release_failed"),
                                   ("cancelled", None, "the band selection ended cancelled: no error named")):
            with self.subTest(result):
                open(self.log, "w").close()
                self.assert_not_exercised(dict(FREE, op={"result": result, "error": error}), why, posts=1)

    def test_run_from_a_package_folder_takes_every_path_from_its_parameters(self):
        """TC-171-03: the page check runs from the station package, outside any repository."""
        package = os.path.join(self.tmp.name, "pkg", "deploy", "tools", "deploy")
        os.makedirs(package)
        script = os.path.join(package, "live-page-check.ps1")
        shutil.copyfile(SCRIPT, script)
        os.makedirs(os.path.join(self.repo, "tests"))
        checker = os.path.join(self.repo, "tests", "live-page-check.cjs")
        shutil.copyfile(self.check, checker)
        rc, out, log = self.run_check(FREE, script=script, check=False)
        self.assertEqual(rc, 0, out)
        self.assertIn(f"CHECK CWD {self.repo} FILE {checker}", out)
        self.assertEqual(log, ["select", "rows", "ctrlc", "start-locked"], out)
        self.assertIn("LIVE PAGE CHECK PASS", out)
        # The lease of the -Shared folder, not of a repository around the script, makes it busy.
        with open(os.path.join(self.radio, "lease.json"), "w", encoding="utf-8") as f:
            json.dump({"holder": "qso-test", "expires": "2099-01-01T00:00:00Z"}, f)
        open(self.log, "w").close()
        rc, out, log = self.run_check(FREE, script=script, check=False)
        self.assertEqual(rc, 3, out)
        self.assertIn("qso-test holds the radio lease", out)

    def test_armed(self):
        self.assert_busy(dict(FREE, arm="armed"), "transmit is armed")

    def test_ptt_keyed(self):
        self.assert_busy(dict(FREE, ptt="keyed"), "PTT is keyed")

    def test_transmitting(self):
        self.assert_busy(dict(FREE, transmitting=True), "transmitting: True")

    def test_contact_running(self):
        self.assert_busy(dict(FREE, contact={"state": "report"}), "a contact is report")

    def test_automation_run(self):
        self.assert_busy(dict(FREE, run={"state": "waiting"}), "an automation run is waiting")

    def test_unreadable_state(self):
        self.assert_busy(dict(FREE, unreadable=True), "its state cannot be read")

    def test_radio_lease(self):
        with open(os.path.join(self.radio, "lease.json"), "w", encoding="utf-8") as f:
            json.dump({"holder": "qso-test", "expires": "2099-01-01T00:00:00Z"}, f)
        self.assert_busy(FREE, "qso-test holds the radio lease")

    def test_update_running(self):
        with open(os.path.join(self.station, "logs", "update.lock"), "w"):
            self.assert_busy(FREE, "an update is running")


if __name__ == "__main__":
    unittest.main()
